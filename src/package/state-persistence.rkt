#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/file
         racket/path
         (only-in "../language_bundle/state-persistence.rkt"
                  [language-bundle-state-path bundle:language-bundle-state-path])
         (prefix-in bundle: "../language_bundle/state-records.rkt")
         "../storage/durable-file.rkt"
         "../storage/record-codec.rkt"
         "../storage/record-store.rkt"
         "language-bundle-state-adapter.rkt"
         "state-records.rkt")

(provide
 (struct-out odra-package-startup)
 (struct-out odra-record-publication)
 (struct-out odra-record-publication-failure)
 (contract-out
  [package-state-path (-> path-string? path?)]
  [package-state-persist
   (-> path-string? odra-package-state?
       (or/c odra-record-publication? odra-record-publication-failure?))]
  [package-state-startup
   (->* (path-string?)
        (#:safe-mode? boolean? #:content-exists? procedure?)
        odra-package-startup?)]))

(struct odra-package-startup (mode state diagnostic quarantine-path legacy-path)
  #:transparent)

(define idempotent-phases
  '(resolve review acquire verify durable-install prepare validate cleanup))

(define (package-state-path data-root)
  (build-path (path->complete-path data-root) "packages" "state.rktd"))

(define (package-state-persist data-root state)
  (record-persist
   'package-state (package-state-path data-root) state
   package-state->module-bytes package-state-module-load
   odra-package-state-generation
   #:owned-root data-root))

(define (migration-generation-valid! target candidate load generation-of)
  (cond
    [(file-exists? target)
     (define current (load target))
     (when (odra-record-diagnostic? current)
       (record-publication-reject
        'validation-failed "Existing package state cannot be validated" target))
     (unless (= (generation-of candidate) (add1 (generation-of current)))
       (record-publication-reject
        'invalid-generation "Updated package state must increment once" target))]
    [(not (eq? (odra-package-state-migration-source candidate)
               'language-bundle-v2))
     (record-publication-reject
      'invalid-generation "Non-migrated package state begins at generation one" target)]))

(define (package-state-persist-migration data-root state)
  (record-persist
   'package-state (package-state-path data-root) state
   package-state->module-bytes package-state-module-load
   odra-package-state-generation
   #:owned-root data-root
   #:validate-generation migration-generation-valid!))

(define (lock-checksum-valid? lock)
  (and lock
       (string=? (odra-package-activation-lock-checksum lock)
                 (package-activation-lock-checksum lock))))

(define (lock-valid? state lock content-exists? #:current? [current? #t])
  (and (lock-checksum-valid? lock)
       ((if current? = <=)
        (odra-package-activation-lock-state-generation lock)
        (odra-package-state-generation state))
       (andmap content-exists? (odra-package-activation-lock-content lock))))

(define (rebind-lock lock state-generation)
  (and lock
       (package-activation-lock-with-checksum
        (struct-copy odra-package-activation-lock lock
                     [generation
                      (add1 (odra-package-activation-lock-generation lock))]
                     [state-generation state-generation]
                     [checksum (make-string 64 #\0)]))))

(define (recovered-state state lock)
  (define next-generation (add1 (odra-package-state-generation state)))
  (define rebound (rebind-lock lock next-generation))
  (package-state-with-checksum
   (struct-copy odra-package-state state
                [generation next-generation]
                [confirmed-lock-generation
                 (if rebound
                     (odra-package-activation-lock-generation rebound)
                     0)]
                [lock rebound]
                [previous-lock #f]
                [operations '()]
                [checksum (make-string 64 #\0)])))

(define (quarantine-invalid-state root path)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (define quarantine-root (build-path root "packages" "quarantine"))
    (make-directory* quarantine-root)
    (file-or-directory-permissions quarantine-root #o700)
    (define destination
      (build-path quarantine-root
                  (format "state-~a.rktd"
                          (inexact->exact
                           (floor (current-inexact-milliseconds))))))
    (rename-file-or-directory path destination #f)
    (durable-directory-synchronize quarantine-root)
    (durable-directory-synchronize (path-only path))
    destination))

(define (startup-with-state root state content-exists?)
  (define lock (odra-package-state-lock state))
  (define previous (odra-package-state-previous-lock state))
  (define operations (odra-package-state-operations state))
  (cond
    [(and (or (not lock) (lock-valid? state lock content-exists?))
          (null? operations))
     (odra-package-startup 'confirmed state #f #f #f)]
    [(and (or (not lock) (lock-valid? state lock content-exists?))
          (= (length operations) 1)
          (memq (odra-package-operation-phase (car operations))
                idempotent-phases))
     (odra-package-startup 'resume-operation state #f #f #f)]
    [(lock-valid? state previous content-exists? #:current? #f)
     (define recovered (recovered-state state previous))
     (define publication (package-state-persist root recovered))
     (if (odra-record-publication? publication)
         (odra-package-startup 'rollback-previous recovered #f #f #f)
         (odra-package-startup 'recovery-only state publication #f #f))]
    [else
     (odra-package-startup
      'recovery-only state 'invalid-activation-lock #f #f)]))

(define (startup-with-migration root legacy-path content-exists?)
  (define loaded (bundle:language-bundle-state-module-load legacy-path))
  (cond
    [(odra-record-diagnostic? loaded)
     (odra-package-startup 'recovery-only #f loaded #f legacy-path)]
    [else
     (define-values (candidate rejection)
       (language-bundle-state->package-state loaded))
     (cond
       [rejection
        (odra-package-startup 'recovery-only #f rejection #f legacy-path)]
       [(not (andmap content-exists?
                     (package-state-reachable-content candidate)))
        (odra-package-startup
         'recovery-only #f 'missing-migration-content #f legacy-path)]
       [else
        (define publication (package-state-persist-migration root candidate))
        (if (odra-record-publication? publication)
            (odra-package-startup 'migrated candidate #f #f legacy-path)
            (odra-package-startup
             'recovery-only #f publication #f legacy-path))])]))

(define (package-state-startup root
                               #:safe-mode? [safe-mode? #f]
                               #:content-exists? [content-exists? (lambda (_) #t)])
  (define complete-root (path->complete-path root))
  (define path (package-state-path complete-root))
  (define legacy-path (bundle:language-bundle-state-path complete-root))
  (cond
    [(file-exists? path)
     (define loaded (package-state-module-load path))
     (cond
       [(odra-record-diagnostic? loaded)
        (odra-package-startup
         'quarantined #f loaded
         (quarantine-invalid-state complete-root path)
         (and (file-exists? legacy-path) legacy-path))]
       [safe-mode?
        (odra-package-startup
         'recovery-only loaded #f #f
         (and (file-exists? legacy-path) legacy-path))]
       [else (startup-with-state complete-root loaded content-exists?)])]
    [(file-exists? legacy-path)
     (if safe-mode?
         (odra-package-startup 'recovery-only #f 'migration-deferred #f legacy-path)
         (startup-with-migration complete-root legacy-path content-exists?))]
    [else (odra-package-startup 'empty #f #f #f #f)]))
