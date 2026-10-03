#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/contract/base
         racket/list
         racket/match
         (prefix-in bundle: "../command/language-bundles.rkt")
         "activation-candidate.rkt"
         "activation-runtime.rkt"
         "advisory-response.rkt"
         "state-persistence.rkt"
         "state-records.rkt")

(provide
 (struct-out odra-bundle-install-request)
 (struct-out odra-bundle-lifecycle-result)
 bundle-lifecycle-manager?
 (contract-out
  [make-bundle-lifecycle-manager
   (->* (path-string?)
        (#:root-id string?
         #:runtime bundle-runtime?
         #:inputs (listof odra-bundle-install-request?)
         #:advisory-evaluator procedure?
         #:replacement-policy odra-bundle-replacement-policy?
         #:persistence procedure?
         #:safe-mode? boolean?)
        bundle-lifecycle-manager?)]
  [bundle-lifecycle-state
   (-> bundle-lifecycle-manager? odra-language-bundle-state?)]
  [bundle-lifecycle-runtime-snapshot
   (-> bundle-lifecycle-manager? (or/c #f odra-bundle-runtime-snapshot?))]
  [bundle-lifecycle-advisory-response
   (-> bundle-lifecycle-manager? string? string?
       (or/c #f odra-security-advisory-response?))]
  [bundle-lifecycle-install!
   (-> bundle-lifecycle-manager? odra-bundle-install-request?
       odra-bundle-lifecycle-result?)]
  [bundle-lifecycle-enable!
   (-> bundle-lifecycle-manager? string? string? odra-bundle-lifecycle-result?)]
  [bundle-lifecycle-disable!
   (-> bundle-lifecycle-manager? string? odra-bundle-lifecycle-result?)]
  [bundle-lifecycle-update!
   (-> bundle-lifecycle-manager? odra-bundle-install-request?
       odra-bundle-lifecycle-result?)]
  [bundle-lifecycle-rollback!
   (-> bundle-lifecycle-manager? string? odra-bundle-lifecycle-result?)]
  [bundle-lifecycle-remove!
   (-> bundle-lifecycle-manager? string? string? odra-bundle-lifecycle-result?)]
  [bundle-lifecycle-verify!
   (-> bundle-lifecycle-manager? string? string? odra-bundle-lifecycle-result?)]
  [bundle-lifecycle-quarantine!
   (-> bundle-lifecycle-manager? string? string? odra-bundle-lifecycle-result?)]
  [bundle-lifecycle-garbage-collect!
   (-> bundle-lifecycle-manager? (listof string?) procedure?
       odra-bundle-lifecycle-result?)]))

(define zero-digest (make-string 64 #\0))

(struct odra-bundle-install-request
  (input manifest-digest platform architecture authority-provenance
         manifest-bytes artifact-bytes)
  #:transparent
  #:guard
  (lambda (input manifest-digest platform architecture authority-provenance
                 manifest-bytes artifact-bytes _)
    (unless (and (odra-bundle-preparation-input? input)
                 (regexp-match? #px"^[0-9a-f]{64}$" manifest-digest)
                 (memq platform '(darwin linux windows))
                 (memq architecture '(aarch64 x86-64))
                 (string? authority-provenance)
                 (exact-nonnegative-integer? manifest-bytes)
                 (exact-nonnegative-integer? artifact-bytes))
      (raise-arguments-error
       'odra-bundle-install-request "invalid bundle installation request"))
    (values input (string->immutable-string manifest-digest) platform architecture
            (string->immutable-string authority-provenance)
            manifest-bytes artifact-bytes)))

(struct odra-bundle-lifecycle-result (state installed-state detail values)
  #:transparent)

(struct bundle-lifecycle-manager
  (root root-id runtime state requests advisory-evaluator replacement-policy
        persistence safe-mode?)
  #:transparent #:mutable)

(define (empty-state root-id)
  (language-bundle-state-with-checksum
   (odra-language-bundle-state
    2 root-id 1 0 '() #f #f '() '()
    (odra-bundle-accounting 0 0 0 0 0) zero-digest)))

(define (request-bundle request)
  (odra-bundle-preparation-input-bundle
   (odra-bundle-install-request-input request)))

(define (request-id request)
  (symbol->string (bundle:odra-language-support-bundle-id (request-bundle request))))

(define (request-version request)
  (bundle:odra-language-support-bundle-version (request-bundle request)))

(define (request-key id version)
  (string-append id "@" version))

(define (make-bundle-lifecycle-manager
         root #:root-id [root-id "default"]
         #:runtime [runtime (make-bundle-runtime)]
         #:inputs [inputs '()]
         #:advisory-evaluator
         [advisory-evaluator
          (lambda (_phase _package-id _release-id _artifact-digests
                          _installed? _active?)
            (odra-security-advisory-response '() '() '()))]
         #:replacement-policy
         [replacement-policy (odra-bundle-replacement-policy '() '())]
         #:persistence [persistence language-bundle-state-persist]
         #:safe-mode? [safe-mode? #f])
  (define startup (language-bundle-state-startup root #:safe-mode? safe-mode?))
  (define loaded (odra-language-bundle-startup-state startup))
  (define requests
    (make-hash
     (for/list ([request (in-list inputs)])
       (cons (request-key (request-id request) (request-version request)) request))))
  (define manager
    (bundle-lifecycle-manager
     root (string->immutable-string root-id) runtime (or loaded (empty-state root-id))
     requests advisory-evaluator replacement-policy persistence safe-mode?))
  (unless safe-mode? (restore-runtime! manager))
  manager)

(define (bundle-lifecycle-state manager)
  (bundle-lifecycle-manager-state manager))

(define (bundle-lifecycle-runtime-snapshot manager)
  (bundle-runtime-inspect (bundle-lifecycle-manager-runtime manager)))

(define (result state manager [detail ""] [values '()])
  (odra-bundle-lifecycle-result
   state (bundle-lifecycle-manager-state manager) detail values))

(define (bundle-record-key record)
  (request-key (odra-installed-bundle-id record)
               (odra-installed-bundle-version record)))

(define (find-record state id version)
  (findf (lambda (record)
           (and (string=? id (odra-installed-bundle-id record))
                (string=? version (odra-installed-bundle-version record))))
         (odra-language-bundle-state-bundles state)))

(define (active-records state)
  (filter (lambda (record)
            (eq? (odra-installed-bundle-lifecycle record) 'active-confirmed))
          (odra-language-bundle-state-bundles state)))

(define (request->record request lifecycle [generation 0] [predecessor #f])
  (define value (request-bundle request))
  (define input (odra-bundle-install-request-input request))
  (define artifacts
    (sort
     (for/list ([handle
                 (in-hash-values
                  (odra-bundle-preparation-input-artifact-handles input))])
       (odra-bundle-artifact-handle-digest handle))
     string<?))
  (define dependencies
    (sort
     (map (lambda (dependency)
            (symbol->string (bundle:odra-language-bundle-dependency-id dependency)))
          (filter
           (lambda (dependency)
             (not (bundle:odra-language-bundle-dependency-optional? dependency)))
           (bundle:odra-language-support-bundle-dependencies value)))
     string<?))
  (odra-installed-bundle
   (request-id request) (request-version request)
   (odra-bundle-install-request-manifest-digest request) artifacts dependencies
   (symbol->string (bundle:odra-language-support-bundle-source value))
   (symbol->string (bundle:odra-language-support-bundle-publisher value))
   (odra-bundle-install-request-platform request)
   (odra-bundle-install-request-architecture request)
   (sort
    (map symbol->string
         (odra-bundle-preparation-input-granted-authorities input))
    string<?)
   (odra-bundle-install-request-authority-provenance request)
   lifecycle generation predecessor #f))

(define (record-with-lifecycle record lifecycle
                               #:generation [generation
                                             (odra-installed-bundle-contribution-generation record)]
                               #:predecessor [predecessor
                                              (odra-installed-bundle-predecessor record)])
  (struct-copy odra-installed-bundle record
               [lifecycle lifecycle]
               [contribution-generation generation]
               [predecessor predecessor]))

(define (record-content record)
  (sort
   (remove-duplicates
    (cons (odra-installed-bundle-manifest record)
          (odra-installed-bundle-artifacts record))
    string=?)
   string<?))

(define (advisory-response-for-record manager phase record installed? active?)
  ((bundle-lifecycle-manager-advisory-evaluator manager)
   phase (odra-installed-bundle-id record) #f (record-content record)
   installed? active?))

(define (bundle-lifecycle-advisory-response manager id version)
  (define record
    (find-record (bundle-lifecycle-manager-state manager) id version))
  (and record
       (advisory-response-for-record
        manager 'inspection record #t
        (eq? (odra-installed-bundle-lifecycle record) 'active-confirmed))))

(define (advisory-blocks? response action)
  (and (member action
               (odra-security-advisory-response-actions response))
       #t))

(define (request-accounting manager bundles quarantine)
  (define manifest-bytes 0)
  (define artifact-bytes 0)
  (for ([record (in-list bundles)])
    (define request
      (hash-ref (bundle-lifecycle-manager-requests manager)
                (bundle-record-key record) #f))
    (when request
      (set! manifest-bytes
            (+ manifest-bytes (odra-bundle-install-request-manifest-bytes request)))
      (set! artifact-bytes
            (+ artifact-bytes (odra-bundle-install-request-artifact-bytes request)))))
  (odra-bundle-accounting
   (length bundles)
   (for/sum ([record (in-list bundles)])
     (length (odra-installed-bundle-artifacts record)))
   manifest-bytes artifact-bytes
   (length quarantine)))

(define (rebind-lock lock state-generation)
  (and lock
       (activation-lock-with-checksum
        (struct-copy odra-activation-lock lock
                     [state-generation state-generation]
                     [checksum zero-digest]))))

(define (make-state manager bundles lock previous operations
                    #:quarantine
                    [quarantine
                     (odra-language-bundle-state-quarantine
                      (bundle-lifecycle-manager-state manager))])
  (define current (bundle-lifecycle-manager-state manager))
  (define generation
    (if (file-exists?
         (language-bundle-state-path (bundle-lifecycle-manager-root manager)))
        (add1 (odra-language-bundle-state-generation current))
        1))
  (define rebound-lock (rebind-lock lock generation))
  (language-bundle-state-with-checksum
   (odra-language-bundle-state
    2 (bundle-lifecycle-manager-root-id manager) generation
    (if rebound-lock (odra-activation-lock-generation rebound-lock) 0)
    (sort bundles string<? #:key bundle-record-key)
    rebound-lock previous operations
    quarantine (request-accounting manager bundles quarantine) zero-digest)))

(define (persist-state! manager candidate)
  (define publication
    ((bundle-lifecycle-manager-persistence manager)
     (bundle-lifecycle-manager-root manager) candidate))
  (and (odra-record-publication? publication)
       (begin (set-bundle-lifecycle-manager-state! manager candidate) #t)))

(define (operation state kind id phase content [result-state 'pending])
  (odra-bundle-operation
   (string-append id "-" (symbol->string kind)) kind phase
   (odra-language-bundle-state-generation state)
   (odra-language-bundle-state-confirmed-lock-generation state)
   (sort (remove-duplicates content string=?) string<?) '()
   result-state #f ""))

(define (digest-datum value)
  (bytes->hex-string
   (sha256-bytes
    (open-input-bytes
     (string->bytes/utf-8 (format "~s" value))))))

(define (next-contribution-generations state selected)
  (define prior
    (if (odra-language-bundle-state-lock state)
        (odra-activation-lock-contribution-generations
         (odra-language-bundle-state-lock state))
        (hash)))
  (define next
    (add1 (for/fold ([highest 0]) ([generation (in-hash-values prior)])
            (max highest generation))))
  (for/hash ([record (in-list selected)])
    (define id (odra-installed-bundle-id record))
    (define unchanged
      (and (odra-language-bundle-state-lock state)
           (equal? (hash-ref (odra-activation-lock-bundles
                              (odra-language-bundle-state-lock state)) id #f)
                   (odra-installed-bundle-version record))))
    (define generation (if unchanged (hash-ref prior id) next))
    (unless unchanged (set! next (add1 next)))
    (values id generation)))

(define (make-lock state selected state-generation)
  (define prior (odra-language-bundle-state-lock state))
  (define lock-generation
    (add1 (if prior (odra-activation-lock-generation prior) 0)))
  (define bundles
    (for/hash ([record (in-list selected)])
      (values (odra-installed-bundle-id record)
              (odra-installed-bundle-version record))))
  (define content
    (sort
     (remove-duplicates
      (append-map
       (lambda (record)
         (cons (odra-installed-bundle-manifest record)
               (odra-installed-bundle-artifacts record)))
       selected)
      string=?)
     string<?))
  (define generations (next-contribution-generations state selected))
  (activation-lock-with-checksum
   (odra-activation-lock
    lock-generation state-generation bundles content
    (digest-datum
     (for/list ([record (in-list selected)])
       (cons (odra-installed-bundle-id record)
             (odra-installed-bundle-dependencies record))))
    (digest-datum
     (for/list ([record (in-list selected)])
       (cons (odra-installed-bundle-id record)
             (odra-installed-bundle-authorities record))))
    generations zero-digest)))

(define (inputs-for manager lock)
  (for/list ([(id version) (in-hash (odra-activation-lock-bundles lock))])
    (define request
      (hash-ref (bundle-lifecycle-manager-requests manager)
                (request-key id version) #f))
    (and request (odra-bundle-install-request-input request))))

(define (activation-advisory-block manager lock)
  (define state (bundle-lifecycle-manager-state manager))
  (for/first ([(id version) (in-hash (odra-activation-lock-bundles lock))]
              #:do [(define record (find-record state id version))
                    (define response
                      (and record
                           (advisory-response-for-record
                            manager 'activation record #t #t)))]
              #:when
              (and response (advisory-blocks? response 'block-activation)))
    response))

(define (restore-runtime! manager)
  (define lock
    (odra-language-bundle-state-lock (bundle-lifecycle-manager-state manager)))
  (cond
    [(not lock) #t]
    [else
     (define blocked (activation-advisory-block manager lock))
     (cond
       [blocked #f]
       [else
        (define inputs (inputs-for manager lock))
        (cond
          [(ormap not inputs) #f]
          [else
           (define preparation (prepare-bundle-activation lock inputs))
           (cond
             [(not (eq? (odra-bundle-activation-preparation-state preparation)
                        'prepared))
              #f]
             [else
              (define publication
                (prepare-bundle-publication
                 (bundle-lifecycle-manager-runtime manager)
                 (odra-bundle-activation-preparation-candidate preparation)
                 (bundle-lifecycle-manager-replacement-policy manager)))
              (and (eq? (odra-bundle-publication-state publication) 'prepared)
                   (publish-bundle-publication!
                    (bundle-lifecycle-manager-runtime manager)
                    publication))])])])]))

(define (record-generation lock record)
  (hash-ref (odra-activation-lock-contribution-generations lock)
            (odra-installed-bundle-id record)))

(define (finalize-records records selected lock)
  (define selected-keys
    (for/hash ([record (in-list selected)]) (values (bundle-record-key record) #t)))
  (for/list ([record (in-list records)])
    (cond
      [(hash-ref selected-keys (bundle-record-key record) #f)
       (record-with-lifecycle
        record 'active-confirmed #:generation (record-generation lock record))]
      [(eq? (odra-installed-bundle-lifecycle record) 'active-confirmed)
       (record-with-lifecycle record 'rollback-available)]
      [else record])))

(define (activate-records! manager kind id selected pending-records
                           [advisory-values '()])
  (define state (bundle-lifecycle-manager-state manager))
  (define old-lock (odra-language-bundle-state-lock state))
  (define operation-kind
    (case kind
      [(updated) 'update]
      [(rolled-back) 'rollback]
      [else kind]))
  (define content
    (append-map
     (lambda (record)
       (cons (odra-installed-bundle-manifest record)
             (odra-installed-bundle-artifacts record)))
     selected))
  (define pending-operation (operation state operation-kind id 'publish content))
  (define pending
    (make-state manager pending-records old-lock old-lock (list pending-operation)))
  (cond
    [(not (persist-state! manager pending))
     (result 'rejected manager "Could not persist the pending lifecycle operation")]
    [else
     (define lock
       (make-lock state selected
                  (add1 (odra-language-bundle-state-generation pending))))
     (define inputs (inputs-for manager lock))
     (cond
       [(ormap not inputs)
        (result 'rejected manager "An exact installed bundle input is unavailable")]
       [else
        (define preparation (prepare-bundle-activation lock inputs))
        (cond
          [(not (eq? (odra-bundle-activation-preparation-state preparation) 'prepared))
           (result 'rejected manager "Contribution preparation rejected the activation lock")]
          [else
           (define publication
             (prepare-bundle-publication
              (bundle-lifecycle-manager-runtime manager)
              (odra-bundle-activation-preparation-candidate preparation)
              (bundle-lifecycle-manager-replacement-policy manager)))
           (cond
             [(not (eq? (odra-bundle-publication-state publication) 'prepared))
              (result 'rejected manager "Registry validation rejected the activation")]
             [(not (publish-bundle-publication!
                    (bundle-lifecycle-manager-runtime manager) publication))
              (result 'rejected manager "Registry publication became stale")]
             [else
              (define finalized
                (finalize-records pending-records selected lock))
              (define confirmed
                (make-state manager finalized lock old-lock '()))
              (if (persist-state! manager confirmed)
                  (result
                   kind manager ""
                   (append
                    (odra-bundle-publication-retired-bundles publication)
                    advisory-values))
                  (result 'interrupted manager
                          "Runtime publication requires startup recovery"))])])])]))

(define (bundle-lifecycle-install! manager request)
  (define state (bundle-lifecycle-manager-state manager))
  (define id (request-id request))
  (define version (request-version request))
  (cond
    [(find-record state id version)
     (result 'rejected manager "Bundle version is already installed")]
    [else
     (define verified (request->record request 'verified))
     (define advisory-response
       (advisory-response-for-record manager 'acquisition verified #f #f))
     (cond
       [(advisory-blocks? advisory-response 'block-acquisition)
        (result 'rejected manager
                "Local security policy blocks acquisition of this exact content"
                (list advisory-response))]
       [else
     (hash-set! (bundle-lifecycle-manager-requests manager)
                (request-key id version) request)
     (define pending-operation
       (operation state 'install id 'durable-install
                  (cons (odra-installed-bundle-manifest verified)
                        (odra-installed-bundle-artifacts verified))))
     (define pending
       (make-state manager
                   (cons verified (odra-language-bundle-state-bundles state))
                   (odra-language-bundle-state-lock state)
                   (odra-language-bundle-state-previous-lock state)
                   (list pending-operation)))
     (cond
       [(not (persist-state! manager pending))
        (result 'rejected manager "Could not persist verified installation")]
       [else
        (define installed
          (record-with-lifecycle verified 'installed-disabled))
        (define finalized
          (make-state manager
                      (cons installed (odra-language-bundle-state-bundles state))
                      (odra-language-bundle-state-lock state)
                      (odra-language-bundle-state-previous-lock state) '()))
        (if (persist-state! manager finalized)
            (result
             'installed manager ""
            (if (null? (odra-security-advisory-response-references
                         advisory-response))
                 '()
                 (list advisory-response)))
            (result 'interrupted manager
                    "Installation requires startup recovery"))])])]))

(define (required-record state id)
  (define matching
    (filter
     (lambda (record)
       (and (string=? id (odra-installed-bundle-id record))
            (not (memq (odra-installed-bundle-lifecycle record)
                       '(quarantined removed)))))
     (odra-language-bundle-state-bundles state)))
  (or (findf (lambda (record)
               (eq? (odra-installed-bundle-lifecycle record) 'active-confirmed))
             matching)
      (and (pair? matching) (car matching))))

(define (dependency-closure state initial)
  (let loop ([selected initial])
    (define missing-id
      (for*/first ([record (in-list selected)]
                   [dependency
                    (in-list (odra-installed-bundle-dependencies record))]
                   #:unless
                   (findf (lambda (candidate)
                            (string=? dependency
                                      (odra-installed-bundle-id candidate)))
                          selected))
        dependency))
    (cond
      [(not missing-id) selected]
      [else
       (define dependency (required-record state missing-id))
       (and dependency (loop (cons dependency selected)))])))

(define (bundle-lifecycle-enable-as! manager id version outcome predecessor)
  (define state (bundle-lifecycle-manager-state manager))
  (define target (find-record state id version))
  (cond
    [(or (not target) (eq? (odra-installed-bundle-lifecycle target) 'removed))
     (result 'rejected manager "Bundle version is not installed")]
    [(eq? (odra-installed-bundle-lifecycle target) 'quarantined)
     (result 'rejected manager "Quarantined bundle content cannot be activated")]
    [else
     (define selected
       (cons target
             (filter
              (lambda (record)
                (and (eq? (odra-installed-bundle-lifecycle record) 'active-confirmed)
                     (not (string=? id (odra-installed-bundle-id record)))))
              (odra-language-bundle-state-bundles state))))
     (define complete-selected (dependency-closure state selected))
     (cond
       [(not complete-selected)
        (result 'rejected manager "A required dependency is not installed")]
       [else
        (define advisory-responses
          (for/list ([record (in-list complete-selected)])
            (advisory-response-for-record
             manager 'activation record #t
             (eq? (odra-installed-bundle-lifecycle record) 'active-confirmed))))
        (define blocked
          (findf (lambda (response)
                   (advisory-blocks? response 'block-activation))
                 advisory-responses))
        (cond
          [blocked
           (result 'rejected manager
                   "Local security policy blocks activation of exact content"
                   advisory-responses)]
          [else
        (define pending-records
          (for/list ([record (in-list (odra-language-bundle-state-bundles state))])
            (if (equal? (bundle-record-key record) (bundle-record-key target))
                (record-with-lifecycle
                 record 'enabled-pending #:predecessor predecessor)
                record)))
              (activate-records!
               manager outcome id complete-selected pending-records
               (filter
                (lambda (response)
                  (pair? (odra-security-advisory-response-references response)))
                advisory-responses))])])]))

(define (bundle-lifecycle-enable! manager id version)
  (bundle-lifecycle-enable-as! manager id version 'enable #f))

(define (dependent-closure records id)
  (let loop ([selected (list id)])
    (define expanded
      (remove-duplicates
       (append selected
               (for/list ([record (in-list records)]
                          #:when
                          (for/or ([dependency
                                    (in-list
                                     (odra-installed-bundle-dependencies record))])
                            (member dependency selected string=?)))
                 (odra-installed-bundle-id record)))
       string=?))
    (if (= (length expanded) (length selected)) selected (loop expanded))))

(define (bundle-lifecycle-disable! manager id)
  (define state (bundle-lifecycle-manager-state manager))
  (define active (active-records state))
  (cond
    [(not (findf (lambda (record) (string=? id (odra-installed-bundle-id record))) active))
     (result 'rejected manager "Bundle is not active")]
    [else
     (define removed (dependent-closure active id))
     (define selected
       (filter (lambda (record)
                 (not (member (odra-installed-bundle-id record) removed string=?)))
               active))
     (define pending-records
       (for/list ([record (in-list (odra-language-bundle-state-bundles state))])
         (if (member (odra-installed-bundle-id record) removed string=?)
             (record-with-lifecycle record 'installed-disabled)
             record)))
     (activate-records! manager 'disable id selected pending-records)]))

(define (bundle-lifecycle-quarantine! manager id version)
  (define state (bundle-lifecycle-manager-state manager))
  (define target (find-record state id version))
  (cond
    [(or (not target) (eq? (odra-installed-bundle-lifecycle target) 'removed))
     (result 'rejected manager "Bundle version is not installed")]
    [(eq? (odra-installed-bundle-lifecycle target) 'quarantined)
     (result 'rejected manager "Bundle version is already quarantined")]
    [(eq? (odra-installed-bundle-lifecycle target) 'active-confirmed)
     (result 'rejected manager
             "Disable the active bundle explicitly before quarantine")]
    [else
     (define response
       (advisory-response-for-record manager 'inspection target #t #f))
     (cond
       [(not (advisory-blocks? response 'quarantine))
        (result 'rejected manager
                "No local security policy recommends quarantine for this content"
                (list response))]
       [else
        (define records
          (for/list ([record
                      (in-list (odra-language-bundle-state-bundles state))])
            (if (equal? (bundle-record-key record) (bundle-record-key target))
                (record-with-lifecycle record 'quarantined)
                record)))
        (define previous-lock
          (odra-language-bundle-state-previous-lock state))
        (define retained-previous-lock
          (if (and previous-lock
                   (equal?
                    (hash-ref (odra-activation-lock-bundles previous-lock) id #f)
                    version))
              #f
              previous-lock))
        (define quarantine
          (sort
           (remove-duplicates
            (append (odra-language-bundle-state-quarantine state)
                    (record-content target))
            string=?)
           string<?))
        (define quarantined
          (make-state
           manager records (odra-language-bundle-state-lock state)
           retained-previous-lock '() #:quarantine quarantine))
        (if (persist-state! manager quarantined)
            (result 'quarantined manager "" (list response))
            (result 'interrupted manager
                    "Quarantine state requires startup recovery"))])]))

(define (bundle-lifecycle-update! manager request)
  (define id (request-id request))
  (define current
    (findf (lambda (record)
             (and (string=? id (odra-installed-bundle-id record))
                  (eq? (odra-installed-bundle-lifecycle record) 'active-confirmed)))
           (active-records (bundle-lifecycle-manager-state manager))))
  (cond
    [(not current) (result 'rejected manager "Bundle has no active version to update")]
    [else
     (define installed (bundle-lifecycle-install! manager request))
     (if (not (eq? (odra-bundle-lifecycle-result-state installed) 'installed))
         installed
         (bundle-lifecycle-enable-as!
          manager id (request-version request) 'updated
          (odra-installed-bundle-version current)))]))

(define (bundle-lifecycle-rollback! manager id)
  (define state (bundle-lifecycle-manager-state manager))
  (define previous (odra-language-bundle-state-previous-lock state))
  (define version (and previous (hash-ref (odra-activation-lock-bundles previous) id #f)))
  (if version
      (bundle-lifecycle-enable-as!
       manager id version 'rolled-back
       (and (odra-language-bundle-state-lock state)
            (hash-ref (odra-activation-lock-bundles
                       (odra-language-bundle-state-lock state)) id #f)))
      (result 'rejected manager "No retained rollback version exists")))

(define (bundle-lifecycle-remove! manager id version)
  (define state (bundle-lifecycle-manager-state manager))
  (define target (find-record state id version))
  (define dependents
    (filter
     (lambda (record)
       (and (not (equal? record target))
            (not (eq? (odra-installed-bundle-lifecycle record) 'removed))
            (member id (odra-installed-bundle-dependencies record) string=?)))
     (odra-language-bundle-state-bundles state)))
  (cond
    [(not target) (result 'rejected manager "Bundle version is not installed")]
    [(pair? dependents) (result 'rejected manager "Required dependents prevent removal")]
    [(eq? (odra-installed-bundle-lifecycle target) 'active-confirmed)
     (define disabled (bundle-lifecycle-disable! manager id))
     (if (not (eq? (odra-bundle-lifecycle-result-state disabled) 'disable))
         disabled
         (bundle-lifecycle-remove! manager id version))]
    [else
     (define current (bundle-lifecycle-manager-state manager))
     (define previous-lock
       (odra-language-bundle-state-previous-lock current))
     (define retained-previous-lock
       (if (and previous-lock
                (equal?
                 (hash-ref (odra-activation-lock-bundles previous-lock) id #f)
                 version))
           #f
           previous-lock))
     (define records
       (for/list ([record (in-list (odra-language-bundle-state-bundles current))])
         (if (equal? (bundle-record-key record) (request-key id version))
             (record-with-lifecycle record 'removed)
             record)))
     (define operation-value
       (operation current 'remove id 'cleanup
                  (cons (odra-installed-bundle-manifest target)
                        (odra-installed-bundle-artifacts target)) 'removed))
     (define pending
       (make-state manager records
                   (odra-language-bundle-state-lock current)
                   retained-previous-lock
                   (list operation-value)))
     (define final
       (and (persist-state! manager pending)
            (make-state manager records
                        (odra-language-bundle-state-lock pending)
                        retained-previous-lock '())))
     (if (and final (persist-state! manager final))
         (result 'removed manager)
         (result 'interrupted manager "Removal requires startup recovery"))]))

(define (bundle-lifecycle-verify! manager id version)
  (define record (find-record (bundle-lifecycle-manager-state manager) id version))
  (define request
    (hash-ref (bundle-lifecycle-manager-requests manager)
              (request-key id version) #f))
  (cond
    [(or (not record) (not request))
     (result 'rejected manager "Installed verification inputs are unavailable")]
    [else
     (define expected
       (request->record request (odra-installed-bundle-lifecycle record)
                        (odra-installed-bundle-contribution-generation record)
                        (odra-installed-bundle-predecessor record)))
     (if (and (string=? (odra-installed-bundle-manifest record)
                        (odra-installed-bundle-manifest expected))
              (equal? (odra-installed-bundle-artifacts record)
                      (odra-installed-bundle-artifacts expected)))
         (result 'verified manager)
         (result 'rejected manager "Installed content does not match verified inputs"))]))

(define (bundle-lifecycle-garbage-collect! manager known-content delete-content!)
  (define state (bundle-lifecycle-manager-state manager))
  (define plan (language-bundle-state-garbage-collection-plan state known-content))
  (define retained-records
    (filter (lambda (record)
              (not (eq? (odra-installed-bundle-lifecycle record) 'removed)))
            (odra-language-bundle-state-bundles state)))
  (define operation-value (operation state 'garbage-collect "bundle-gc" 'cleanup plan))
  (define pending
    (make-state manager retained-records
                (odra-language-bundle-state-lock state)
                (odra-language-bundle-state-previous-lock state)
                (list operation-value)))
  (cond
    [(not (persist-state! manager pending))
     (result 'rejected manager "Could not persist garbage-collection intent")]
    [else
     (define removed
       (for/list ([digest (in-list plan)] #:when (delete-content! digest)) digest))
     (define final
       (make-state manager retained-records
                   (odra-language-bundle-state-lock pending)
                   (odra-language-bundle-state-previous-lock pending) '()))
     (if (persist-state! manager final)
         (result 'garbage-collected manager "" removed)
         (result 'interrupted manager
                 "Garbage collection left only extra unreferenced content"))]))
