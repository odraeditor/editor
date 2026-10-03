#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/file
         racket/list
         racket/path
         "../storage/durable-file.rkt"
         "../storage/record-codec.rkt"
         "../storage/record-store.rkt"
         "state-records.rkt")

(provide
 (struct-out odra-language-bundle-startup)
 (struct-out odra-record-publication)
 (struct-out odra-record-publication-failure)
 (contract-out
  [language-bundle-state-path (-> path-string? path?)]
  [language-bundle-state-persist
   (-> path-string? odra-language-bundle-state?
       (or/c odra-record-publication? odra-record-publication-failure?))]
  [language-bundle-state-startup
   (->* (path-string?)
        (#:safe-mode? boolean? #:content-exists? procedure?)
        odra-language-bundle-startup?)]))

(struct odra-language-bundle-startup (mode state diagnostic quarantine-path)
  #:transparent)

(define idempotent-phases
  '(resolve review acquire verify durable-install prepare validate cleanup))

(define (language-bundle-state-path configuration-root)
  (build-path (path->complete-path configuration-root)
              "language-bundles" "installed-state.rktd"))

(define (language-bundle-state-persist configuration-root state)
  (define target (language-bundle-state-path configuration-root))
  (record-persist
   'language-bundle-state target state
   language-bundle-state->module-bytes
   language-bundle-state-module-load
   odra-language-bundle-state-generation
   #:owned-root configuration-root))

(define (lock-valid? state lock content-exists? #:current? [current? #t])
  (and lock
       ((if current? = <=)
        (odra-activation-lock-state-generation lock)
        (odra-language-bundle-state-generation state))
       (string=? (odra-activation-lock-checksum lock)
                 (activation-lock-checksum lock))
       (andmap content-exists? (odra-activation-lock-content lock))
       (for/and ([(id version) (in-hash (odra-activation-lock-bundles lock))])
         (for/or ([bundle (in-list (odra-language-bundle-state-bundles state))])
           (and (string=? id (odra-installed-bundle-id bundle))
                (string=? version (odra-installed-bundle-version bundle))
                (eq? (odra-installed-bundle-lifecycle bundle) 'active-confirmed))))))

(define (rebind-lock lock state-generation)
  (and lock
       (activation-lock-with-checksum
        (struct-copy odra-activation-lock lock
                     [generation (add1 (odra-activation-lock-generation lock))]
                     [state-generation state-generation]
                     [checksum (make-string 64 #\0)]))))

(define (migrate-lock lock state-generation)
  (and lock
       (activation-lock-with-checksum
        (struct-copy odra-activation-lock lock
                     [state-generation state-generation]
                     [checksum (make-string 64 #\0)]))))

(define (migrated-state state)
  (define next-generation (add1 (odra-language-bundle-state-generation state)))
  (define migrated-lock
    (migrate-lock (odra-language-bundle-state-lock state) next-generation))
  (language-bundle-state-with-checksum
   (struct-copy odra-language-bundle-state state
                [generation next-generation]
                [lock migrated-lock]
                [checksum (make-string 64 #\0)])))

(define (recovered-state state lock)
  (define next-generation (add1 (odra-language-bundle-state-generation state)))
  (define rebound-lock (rebind-lock lock next-generation))
  (language-bundle-state-with-checksum
   (struct-copy odra-language-bundle-state state
                [generation next-generation]
                [confirmed-lock-generation
                 (if rebound-lock (odra-activation-lock-generation rebound-lock) 0)]
                [lock rebound-lock]
                [previous-lock #f]
                [operations '()]
                [checksum (make-string 64 #\0)])))

(define (quarantine-invalid-state root path)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (define quarantine-root (build-path root "language-bundles" "quarantine"))
    (make-directory* quarantine-root)
    (file-or-directory-permissions quarantine-root #o700)
    (define destination
      (build-path quarantine-root
                  (format "installed-state-~a.rktd"
                          (inexact->exact (floor (current-inexact-milliseconds))))))
    (rename-file-or-directory path destination #f)
    (durable-directory-synchronize quarantine-root)
    (durable-directory-synchronize (path-only path))
    destination))

(define (startup-with-state root state content-exists?)
  (define lock (odra-language-bundle-state-lock state))
  (define previous (odra-language-bundle-state-previous-lock state))
  (define operations (odra-language-bundle-state-operations state))
  (cond
    [(and (lock-valid? state lock content-exists?) (null? operations))
     (odra-language-bundle-startup 'confirmed state #f #f)]
    [(and (lock-valid? state lock content-exists?)
          (= (length operations) 1)
          (memq (odra-bundle-operation-phase (car operations)) idempotent-phases))
     (odra-language-bundle-startup 'resume-operation state #f #f)]
    [(lock-valid? state previous content-exists? #:current? #f)
     (define recovered (recovered-state state previous))
     (define publication (language-bundle-state-persist root recovered))
     (if (odra-record-publication? publication)
         (odra-language-bundle-startup 'rollback-previous recovered #f #f)
         (odra-language-bundle-startup 'factory-only state publication #f))]
    [else
     (odra-language-bundle-startup 'factory-only state 'invalid-activation-lock #f)]))

(define (startup-with-migration root state content-exists?)
  (define lock (odra-language-bundle-state-lock state))
  (cond
    [(and lock (not (lock-valid? state lock content-exists?)))
     (odra-language-bundle-startup
      'factory-only state 'invalid-activation-lock #f)]
    [(not (andmap content-exists?
                  (language-bundle-state-reachable-content state)))
     (odra-language-bundle-startup
      'factory-only state 'missing-migration-content #f)]
    [else
     (define candidate (migrated-state state))
     (define publication (language-bundle-state-persist root candidate))
     (if (odra-record-publication? publication)
         (startup-with-state root candidate content-exists?)
         (odra-language-bundle-startup 'factory-only state publication #f))]))

(define (language-bundle-state-startup root
                                       #:safe-mode? [safe-mode? #f]
                                       #:content-exists? [content-exists? (lambda (_) #t)])
  (define complete-root (path->complete-path root))
  (define path (language-bundle-state-path complete-root))
  (cond
    [(not (file-exists? path))
     (odra-language-bundle-startup 'factory-only #f #f #f)]
    [else
     (define format (language-bundle-state-module-format path))
     (define loaded (language-bundle-state-module-load path))
     (cond
       [(odra-record-diagnostic? loaded)
        (odra-language-bundle-startup
         'factory-only #f loaded (quarantine-invalid-state complete-root path))]
       [safe-mode?
        (odra-language-bundle-startup 'factory-only loaded #f #f)]
       [(and (exact-positive-integer? format) (= format 1))
        (startup-with-migration complete-root loaded content-exists?)]
       [else (startup-with-state complete-root loaded content-exists?)])]))
