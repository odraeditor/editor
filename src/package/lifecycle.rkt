#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/contract/base
         racket/file
         racket/list
         racket/string
         "acquisition.rkt"
         "installation.rkt"
         "manifest-contracts.rkt"
         "resolution.rkt"
         "runtime.rkt"
         "state-persistence.rkt"
         "state-records.rkt")

(provide
 odra-package-lifecycle-manager?
 (struct-out odra-package-lifecycle-result)
 (struct-out odra-package-lifecycle-inspection)
 (contract-out
  [make-package-lifecycle-manager
   (->* (path-string?)
        (#:state (or/c #f odra-package-state?)
         #:runtime odra-package-runtime?)
        odra-package-lifecycle-manager?)]
  [package-lifecycle-state
   (-> odra-package-lifecycle-manager? odra-package-state?)]
  [package-lifecycle-root
   (-> odra-package-lifecycle-manager? path?)]
  [package-lifecycle-runtime
   (-> odra-package-lifecycle-manager? odra-package-runtime?)]
  [package-lifecycle-register-manifest!
   (-> odra-package-lifecycle-manager? odra-package-manifest? void?)]
  [package-lifecycle-install!
   (-> odra-package-lifecycle-manager?
       odra-package-installation-candidate?
       odra-package-acquisition?
       odra-package-lifecycle-result?)]
  [package-lifecycle-enable!
   (-> odra-package-lifecycle-manager? string? string? string?
       odra-package-lifecycle-result?)]
  [package-lifecycle-disable!
   (-> odra-package-lifecycle-manager? string?
       odra-package-lifecycle-result?)]
  [package-lifecycle-update!
   (-> odra-package-lifecycle-manager? string? string? string?
       odra-package-lifecycle-result?)]
  [package-lifecycle-rollback!
   (-> odra-package-lifecycle-manager? string? string?
       odra-package-lifecycle-result?)]
  [package-lifecycle-remove!
   (-> odra-package-lifecycle-manager? string? string?
       odra-package-lifecycle-result?)]
  [package-lifecycle-cleanup!
   (-> odra-package-lifecycle-manager? (listof string?) procedure?
       odra-package-lifecycle-result?)]
  [package-lifecycle-restore!
   (-> odra-package-lifecycle-manager? odra-package-lifecycle-result?)]
  [package-lifecycle-list
   (-> odra-package-lifecycle-manager?
       (listof odra-package-lifecycle-inspection?))]
  [package-lifecycle-inspect
   (-> odra-package-lifecycle-manager? string? (or/c #f string?)
       (listof odra-package-lifecycle-inspection?))]
  [package-lifecycle-doctor
   (-> odra-package-lifecycle-manager? odra-package-lifecycle-result?)]))

(struct odra-package-lifecycle-result (status state package detail values)
  #:transparent)

(struct odra-package-lifecycle-inspection
  (package-id version kind lifecycle source publisher source-revision
              requested-authorities granted-authorities authority-provenance
              contribution-generation predecessor latest-failure)
  #:transparent)

(struct odra-package-lifecycle-manager
  (root runtime [state #:mutable] manifests))

(define (empty-state)
  (package-state-with-checksum
   (odra-package-state
    current-package-state-format-version "default" 0 0 '() #f #f '() '()
    (odra-package-accounting 0 0 0 0 0) #f (make-string 64 #\0))))

(define (startup-state root)
  (define startup (package-state-startup root))
  (or (odra-package-startup-state startup) (empty-state)))

(define (make-package-lifecycle-manager root
                                        #:state [state #f]
                                        #:runtime [runtime (make-package-runtime)])
  (define manager
    (odra-package-lifecycle-manager
     (path->complete-path root) runtime (or state (startup-state root)) (make-hash)))
  (for ([package
         (in-list
          (odra-package-state-packages
           (odra-package-lifecycle-manager-state manager)))]
        #:unless (eq? 'removed (odra-installed-package-lifecycle package)))
    (define manifest
      (package-manifest-module-load
       (package-content-path
        (odra-package-lifecycle-manager-root manager)
        (odra-installed-package-manifest package))))
    (when (odra-package-manifest? manifest)
      (package-lifecycle-register-manifest! manager manifest)))
  manager)

(define (package-lifecycle-state manager)
  (odra-package-lifecycle-manager-state manager))

(define (package-lifecycle-root manager)
  (odra-package-lifecycle-manager-root manager))

(define (package-lifecycle-runtime manager)
  (odra-package-lifecycle-manager-runtime manager))

(define (manifest-key id version) (format "~a@~a" id version))

(define (package-lifecycle-register-manifest! manager manifest)
  (hash-set! (odra-package-lifecycle-manager-manifests manager)
             (manifest-key (odra-package-manifest-package-id manifest)
                           (odra-package-manifest-version manifest))
             manifest)
  (void))

(define (manager-manifest manager package)
  (hash-ref (odra-package-lifecycle-manager-manifests manager)
            (manifest-key (odra-installed-package-id package)
                          (odra-installed-package-version package))
            #f))

(define (result manager status [package #f] [detail ""] [values '()])
  (odra-package-lifecycle-result
   status (package-lifecycle-state manager) package detail values))

(define (publish! manager state)
  (define publication
    (package-state-persist (odra-package-lifecycle-manager-root manager) state))
  (and (odra-record-publication? publication)
       (begin
         (set-odra-package-lifecycle-manager-state! manager state)
         #t)))

(define (package-content package)
  (append (list (odra-installed-package-manifest package))
          (if (odra-installed-package-archive package)
              (list (odra-installed-package-archive package))
              '())
          (odra-installed-package-artifacts package)))

(define (digest-datum value)
  (bytes->hex-string
   (sha256-bytes (open-input-string (format "~s" value)))))

(define (state-with manager packages lock previous-lock
                    #:operations [operations '()]
                    #:quarantine
                    [quarantine
                     (odra-package-state-quarantine
                      (package-lifecycle-state manager))])
  (define current (package-lifecycle-state manager))
  (define generation (add1 (odra-package-state-generation current)))
  (define current-lock
    (and lock
         (package-activation-lock-with-checksum
          (struct-copy odra-package-activation-lock lock
                       [state-generation generation]
                       [checksum (make-string 64 #\0)]))))
  (package-state-with-checksum
   (struct-copy
    odra-package-state current
    [generation generation]
    [confirmed-lock-generation
     (if current-lock (odra-package-activation-lock-generation current-lock) 0)]
    [packages (sort packages string<?
                    #:key (lambda (package)
                            (manifest-key
                             (odra-installed-package-id package)
                             (odra-installed-package-version package))))]
    [lock current-lock]
    [previous-lock previous-lock]
    [operations operations]
    [quarantine quarantine]
    [accounting
     (struct-copy
      odra-package-accounting (odra-package-state-accounting current)
      [package-count (length packages)]
      [artifact-count
       (for/sum ([package (in-list packages)])
         (length (odra-installed-package-artifacts package)))]
      [quarantine-count (length quarantine)])]
    [checksum (make-string 64 #\0)])))

(define (active-packages packages)
  (filter (lambda (package)
            (eq? (odra-installed-package-lifecycle package) 'active-confirmed))
          packages))

(define (make-lock manager packages state-generation)
  (define active (active-packages packages))
  (and
   (pair? active)
   (let* ([current (package-lifecycle-state manager)]
          [generation (add1 (odra-package-state-confirmed-lock-generation current))]
          [versions
           (make-immutable-hash
            (map (lambda (package)
                   (cons (odra-installed-package-id package)
                         (odra-installed-package-version package)))
                 active))]
          [grants
           (make-immutable-hash
            (map (lambda (package)
                   (cons (odra-installed-package-id package)
                         (odra-installed-package-record-generation package)))
                 active))]
          [contributions
           (make-immutable-hash
            (map (lambda (package)
                   (cons (odra-installed-package-id package)
                         (odra-installed-package-contribution-generation package)))
                 active))]
          [content
           (sort (remove-duplicates (append-map package-content active) string=?)
                 string<?)])
     (package-activation-lock-with-checksum
      (odra-package-activation-lock
       generation state-generation versions content
       (digest-datum
        (for/list ([package (in-list active)])
          (map (lambda (release)
                 (cons (odra-package-release-id release)
                       (odra-package-release-version release)))
               (odra-installed-package-dependencies package))))
       (digest-datum
        (for/list ([package (in-list active)])
          (cons (odra-installed-package-id package)
                (odra-installed-package-granted-authorities package))))
       grants contributions 1 (make-string 64 #\0))))))

(define (replace-package packages selected replacement)
  (for/list ([package (in-list packages)])
    (if (equal? package selected) replacement package)))

(define (package-lifecycle-install! manager candidate acquisition)
  (define installed
    (install-package-candidate!
     (odra-package-lifecycle-manager-root manager)
     (package-lifecycle-state manager) candidate acquisition))
  (cond
    [(odra-package-installation-failure? installed)
     (set-odra-package-lifecycle-manager-state!
      manager (odra-package-installation-failure-state installed))
     (result manager 'rejected #f
             (odra-package-installation-failure-detail installed))]
    [else
     (set-odra-package-lifecycle-manager-state!
      manager (odra-package-installation-result-state installed))
     (package-lifecycle-register-manifest!
      manager (odra-package-installation-candidate-manifest candidate))
     (result manager
             (if (odra-package-installation-result-idempotent? installed)
                 'unchanged 'installed)
             (odra-package-installation-result-package installed))]))

(define (find-package manager id version)
  (package-state-find (package-lifecycle-state manager) id version))

(define (active-package manager id)
  (for/first
      ([package
        (in-list (odra-package-state-packages (package-lifecycle-state manager)))]
       #:when
       (and (string=? id (odra-installed-package-id package))
            (eq? 'active-confirmed
                 (odra-installed-package-lifecycle package))))
    package))

(define (dependents manager id)
  (filter
   (lambda (package)
     (and (not (eq? 'removed (odra-installed-package-lifecycle package)))
          (for/or ([dependency
                    (in-list (odra-installed-package-dependencies package))])
            (string=? id (odra-package-release-id dependency)))))
   (odra-package-state-packages (package-lifecycle-state manager))))

(define (activate! manager target authority-provenance predecessor status)
  (define manifest (manager-manifest manager target))
  (cond
    [(not manifest)
     (result manager 'rejected target
             "The verified package manifest is unavailable; reinstall the exact release")]
    [(memq (odra-installed-package-lifecycle target) '(removed quarantined))
     (result manager 'rejected target
             "The selected package release cannot be activated")]
    [else
     (define current (package-lifecycle-state manager))
     (define contribution-generation
       (add1
        (for/fold ([generation 0])
                  ([package (in-list (odra-package-state-packages current))])
          (max generation
               (odra-installed-package-contribution-generation package)))))
     (define grant-generation
       (add1
        (for/fold ([generation 0])
                  ([package (in-list (odra-package-state-packages current))]
                   #:when
                   (string=? (odra-installed-package-id package)
                             (odra-installed-package-id target)))
          (max generation (odra-installed-package-record-generation package)))))
     (define prepared-record
       (struct-copy odra-installed-package target
                    [lifecycle 'installed-disabled]))
     (define candidate
       (prepare-package-runtime
        (odra-package-lifecycle-manager-root manager)
        prepared-record manifest
        (odra-package-authority-grant
         (odra-installed-package-id target)
         (odra-installed-package-version target)
         grant-generation
         (odra-installed-package-requested-authorities target)
         authority-provenance)
        contribution-generation))
     (cond
       [(odra-package-runtime-failure? candidate)
        (result manager 'rejected target
                (odra-package-runtime-failure-detail candidate))]
       [else
        (define activated
          (package-runtime-activate!
           (odra-package-lifecycle-manager-runtime manager) candidate))
        (cond
          [(odra-package-runtime-failure? activated)
           (discard-package-runtime-candidate! candidate)
           (result manager 'rejected target
                   (odra-package-runtime-failure-detail activated))]
          [else
           (define packages
             (for/list ([package (in-list (odra-package-state-packages current))])
               (cond
                 [(equal? package target)
                  (struct-copy
                   odra-installed-package package
                   [record-generation grant-generation]
                   [granted-authorities
                    (odra-installed-package-requested-authorities package)]
                   [authority-provenance authority-provenance]
                   [lifecycle 'active-confirmed]
                   [contribution-generation contribution-generation]
                   [predecessor predecessor]
                   [latest-failure ""])]
                 [(and
                   (string=? (odra-installed-package-id package)
                             (odra-installed-package-id target))
                   (eq? (odra-installed-package-lifecycle package)
                        'active-confirmed))
                  (struct-copy odra-installed-package package
                               [lifecycle 'rollback-available])]
                 [else package])))
           (define next-generation
             (add1 (odra-package-state-generation current)))
           (define lock (make-lock manager packages next-generation))
           (define next (state-with manager packages lock
                                    (odra-package-state-lock current)))
           (if (publish! manager next)
               (result manager status
                       (find-package manager
                                     (odra-installed-package-id target)
                                     (odra-installed-package-version target)))
               (result manager 'interrupted target
                       "Runtime activation succeeded, but durable state requires startup recovery"))])])]))

(define (package-lifecycle-enable! manager id version authority-provenance)
  (define target (find-package manager id version))
  (if target
      (activate! manager target authority-provenance #f 'enabled)
      (result manager 'rejected #f "The selected package release is not installed")))

(define (package-lifecycle-disable! manager id)
  (define target (active-package manager id))
  (cond
    [(not target) (result manager 'rejected #f "The package is not active")]
    [else
     (define runtime-result
       (package-runtime-deactivate!
        (odra-package-lifecycle-manager-runtime manager) id
        (odra-installed-package-contribution-generation target)
        (add1 (odra-installed-package-contribution-generation target))))
     (cond
       [(odra-package-runtime-failure? runtime-result)
        (result manager 'rejected target
                (odra-package-runtime-failure-detail runtime-result))]
       [else
        (define current (package-lifecycle-state manager))
        (define packages
          (replace-package
           (odra-package-state-packages current) target
           (struct-copy odra-installed-package target
                        [lifecycle 'installed-disabled]
                        [granted-authorities '()]
                        [authority-provenance ""])))
        (define next-generation (add1 (odra-package-state-generation current)))
        (define lock (make-lock manager packages next-generation))
        (define next
          (state-with manager packages lock (odra-package-state-lock current)))
        (if (publish! manager next)
            (result manager 'disabled (find-package manager id
                                                     (odra-installed-package-version target)))
            (result manager 'interrupted target
                    "Runtime disablement succeeded, but durable state requires startup recovery"))])]))

(define (package-lifecycle-update! manager id version authority-provenance)
  (define target (find-package manager id version))
  (define active (active-package manager id))
  (cond
    [(not active)
     (result manager 'rejected target "The package has no active release to update")]
    [(not target)
     (result manager 'rejected #f "The selected update release is not installed")]
    [(string=? version (odra-installed-package-version active))
     (result manager 'unchanged active "The selected release is already active")]
    [else
     (activate! manager target authority-provenance
                (odra-installed-package-version active) 'updated)]))

(define (package-lifecycle-rollback! manager id authority-provenance)
  (define active (active-package manager id))
  (define previous-lock (odra-package-state-previous-lock
                         (package-lifecycle-state manager)))
  (define version
    (and previous-lock
         (hash-ref (odra-package-activation-lock-packages previous-lock) id #f)))
  (define target (and version (find-package manager id version)))
  (cond
    [(not active) (result manager 'rejected #f "The package is not active")]
    [(not target) (result manager 'rejected active
                          "No retained rollback release is available")]
    [else
     (activate! manager target authority-provenance
                (odra-installed-package-version active) 'rolled-back)]))

(define (package-lifecycle-remove! manager id version)
  (define target (find-package manager id version))
  (cond
    [(not target) (result manager 'rejected #f "The selected release is not installed")]
    [(eq? 'active-confirmed (odra-installed-package-lifecycle target))
     (result manager 'rejected target "Disable the package before removing it")]
    [(pair? (dependents manager id))
     (result manager 'rejected target "Installed dependents prevent removal")]
    [(eq? 'removed (odra-installed-package-lifecycle target))
     (result manager 'unchanged target "The selected release is already removed")]
    [else
     (define current (package-lifecycle-state manager))
     (define removed
       (struct-copy odra-installed-package target [lifecycle 'removed]))
     (define packages
       (replace-package (odra-package-state-packages current) target removed))
     (define previous (odra-package-state-previous-lock current))
     (define retained-previous
       (if (and previous
                (equal? version
                        (hash-ref
                         (odra-package-activation-lock-packages previous) id #f)))
           #f previous))
     (define next
       (state-with manager packages (odra-package-state-lock current)
                   retained-previous))
     (if (publish! manager next)
         (result manager 'removed (find-package manager id version))
         (result manager 'interrupted target
                 "Removal requires startup recovery"))]))

(define (package-lifecycle-cleanup! manager known-content delete-content!)
  (define current (package-lifecycle-state manager))
  (define plan (package-state-garbage-collection-plan current known-content))
  (define removed
    (for/list ([digest (in-list plan)] #:when (delete-content! digest)) digest))
  (define packages
    (filter (lambda (package)
              (not (eq? 'removed (odra-installed-package-lifecycle package))))
            (odra-package-state-packages current)))
  (define next
    (state-with manager packages (odra-package-state-lock current)
                (odra-package-state-previous-lock current)))
  (if (publish! manager next)
      (result manager 'cleaned #f "" removed)
      (result manager 'interrupted #f
              "Cleanup completed, but durable state requires startup recovery"
              removed)))

(define (package-lifecycle-restore! manager)
  (define active
    (active-packages
     (odra-package-state-packages (package-lifecycle-state manager))))
  (define restored '())
  (define failed '())
  (for ([package (in-list active)])
    (define manifest (manager-manifest manager package))
    (define prepared
      (and manifest
           (prepare-package-runtime
            (odra-package-lifecycle-manager-root manager)
            (struct-copy odra-installed-package package
                         [lifecycle 'installed-disabled])
            manifest
            (odra-package-authority-grant
             (odra-installed-package-id package)
             (odra-installed-package-version package)
             (odra-installed-package-record-generation package)
             (odra-installed-package-granted-authorities package)
             (odra-installed-package-authority-provenance package))
            (odra-installed-package-contribution-generation package))))
    (cond
      [(not prepared) (set! failed (cons (odra-installed-package-id package) failed))]
      [(odra-package-runtime-failure? prepared)
       (set! failed (cons (odra-installed-package-id package) failed))]
      [else
       (define activated
         (package-runtime-activate!
          (odra-package-lifecycle-manager-runtime manager) prepared))
       (if (odra-package-runtime-failure? activated)
           (begin
             (discard-package-runtime-candidate! prepared)
             (set! failed (cons (odra-installed-package-id package) failed)))
           (set! restored (cons (odra-installed-package-id package) restored)))]))
  (if (null? failed)
      (result manager 'restored #f "" (reverse restored))
      (result manager 'degraded #f
              (format "Active package recovery failed for: ~a"
                      (string-join (reverse failed) ", "))
              (reverse restored))))

(define (inspect-package package)
  (define provenance (odra-installed-package-provenance package))
  (odra-package-lifecycle-inspection
   (odra-installed-package-id package)
   (odra-installed-package-version package)
   (odra-installed-package-kind package)
   (odra-installed-package-lifecycle package)
   (odra-package-provenance-kind provenance)
   (odra-package-provenance-publisher-id provenance)
   (or (odra-package-provenance-source-revision provenance) "")
   (odra-installed-package-requested-authorities package)
   (odra-installed-package-granted-authorities package)
   (odra-installed-package-authority-provenance package)
   (odra-installed-package-contribution-generation package)
   (or (odra-installed-package-predecessor package) "")
   (odra-installed-package-latest-failure package)))

(define (package-lifecycle-list manager)
  (map inspect-package
       (odra-package-state-packages (package-lifecycle-state manager))))

(define (package-lifecycle-inspect manager id version)
  (for/list ([package
              (in-list
               (odra-package-state-packages (package-lifecycle-state manager)))]
             #:when
             (and (string=? id (odra-installed-package-id package))
                  (or (not version)
                      (string=? version
                                (odra-installed-package-version package)))))
    (inspect-package package)))

(define (package-lifecycle-doctor manager)
  (define state (package-lifecycle-state manager))
  (define packages (odra-package-state-packages state))
  (define pending (odra-package-state-operations state))
  (define missing-manifests
    (for/list ([package (in-list packages)]
               #:unless (or (eq? 'removed
                                  (odra-installed-package-lifecycle package))
                            (manager-manifest manager package)))
      (manifest-key (odra-installed-package-id package)
                    (odra-installed-package-version package))))
  (cond
    [(pair? pending)
     (result manager 'degraded #f
             (format "~a package operation(s) require recovery"
                     (length pending)) pending)]
    [(pair? missing-manifests)
     (result manager 'degraded #f
             (format "Verified manifests are unavailable for: ~a"
                     (string-join missing-manifests ", "))
             missing-manifests)]
    [else
     (result manager 'healthy #f
             (if (null? packages)
                 "No packages are installed"
                 (format "~a package release(s) are inspectable"
                         (length packages))))]))
