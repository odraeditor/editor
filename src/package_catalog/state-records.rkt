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
         racket/string
         "../storage/record-codec.rkt"
         "contracts.rkt")

(provide
 current-package-catalog-state-format-version
 minimum-package-catalog-state-format-version
 maximum-package-catalog-registrations
 maximum-package-catalog-state-endpoints
 maximum-package-catalog-confirmed-snapshots
 maximum-package-catalog-state-failures
 maximum-package-catalog-quarantine-references
 (struct-out odra-package-catalog-registration)
 (struct-out odra-package-catalog-state-endpoint)
 (struct-out odra-package-catalog-confirmed-snapshot-reference)
 (struct-out odra-package-catalog-state-failure)
 (struct-out odra-package-catalog-state)
 package-catalog-state-checksum
 package-catalog-state-with-checksum
 package-catalog-state-compatible-format?
 (contract-out
  [package-catalog-empty-state (-> string? odra-package-catalog-state?)]
  [package-catalog-state->module-bytes
   (-> odra-package-catalog-state? immutable-bytes?)]
  [package-catalog-state-module-format
   (-> path-string? (or/c exact-positive-integer? odra-record-diagnostic?))]
  [package-catalog-state-module-load
   (-> path-string? (or/c odra-package-catalog-state? odra-record-diagnostic?))]))

(define current-package-catalog-state-format-version 1)
(define minimum-package-catalog-state-format-version 1)
(define maximum-package-catalog-registrations 64)
(define maximum-package-catalog-state-endpoints 256)
(define maximum-package-catalog-confirmed-snapshots 64)
(define maximum-package-catalog-state-failures 256)
(define maximum-package-catalog-quarantine-references 256)
(define maximum-state-text-bytes 4096)

(define digest-pattern #px"^[0-9a-f]{64}$")
(define configuration-origins '(administrator built-in project user))
(define refresh-states '(blocked current failed never offline stale))
(define advisory-policies '(enforce observe warn))
(define failure-codes
  '(allocation catalog-disabled corrupt-state endpoint-unavailable
               invalid-snapshot io publication stale-generation))

(define (immutable-bytes? value)
  (and (bytes? value) (immutable? value)))

(define (digest? value)
  (and (string? value) (regexp-match? digest-pattern value)))

(define (u64? value)
  (and (exact-nonnegative-integer? value) (<= value (sub1 (expt 2 64)))))

(define (generation? value)
  (and (exact-positive-integer? value) (u64? value)))

(define (identity? value)
  (and (string? value)
       (positive? (string-length value))
       (<= (bytes-length (string->bytes/utf-8 value)) 128)
       (regexp-match? #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$" value)))

(define (bounded-text? value)
  (and (string? value)
       (not (string-contains? value (string #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum-state-text-bytes)))

(define (relative-reference? value)
  (and (bounded-text? value)
       (positive? (string-length value))
       (not (regexp-match? #px"^(?:/|\\\\|[A-Za-z]:)" value))
       (for/and ([part (in-list (string-split value "/"))])
         (not (member part '("" "." "..") string=?)))))

(define (copied value)
  (if (string? value) (record-copied-text value) value))

(define (copied-list values)
  (for/list ([value (in-list values)]) (copied value)))

(define (unique-sorted? values key less? same?)
  (and (list? values)
       (= (length values) (length (remove-duplicates values same? #:key key)))
       (equal? values (sort values less? #:key key))))

(struct odra-package-catalog-registration
  (format-version id generation catalog-id configuration-origin trust-root-ref
      endpoint-ids package-precedence advisory-policy enabled? refresh-state)
  #:transparent
  #:guard
  (lambda (format-version id generation catalog-id configuration-origin
                          trust-root-ref endpoint-ids package-precedence
                          advisory-policy enabled? refresh-state _)
    (unless (and (= format-version current-package-catalog-state-format-version)
                 (identity? id)
                 (generation? generation)
                 (digest? catalog-id)
                 (memq configuration-origin configuration-origins)
                 (digest? trust-root-ref)
                 (list? endpoint-ids)
                 (<= (length endpoint-ids) maximum-package-catalog-state-endpoints)
                 (andmap identity? endpoint-ids)
                 (equal? endpoint-ids
                         (sort (remove-duplicates endpoint-ids string=?) string<?))
                 (exact-nonnegative-integer? package-precedence)
                 (<= package-precedence 65535)
                 (memq advisory-policy advisory-policies)
                 (boolean? enabled?)
                 (or (not enabled?) (pair? endpoint-ids))
                 (memq refresh-state refresh-states))
      (raise-arguments-error 'odra-package-catalog-registration
                             "invalid versioned catalog registration"))
    (values format-version (copied id) generation (copied catalog-id)
            configuration-origin (copied trust-root-ref)
            (copied-list endpoint-ids) package-precedence advisory-policy
            enabled? refresh-state)))

(struct odra-package-catalog-state-endpoint
  (format-version generation endpoint credential-reference)
  #:transparent
  #:guard
  (lambda (format-version generation endpoint credential-reference _)
    (unless (and (= format-version current-package-catalog-state-format-version)
                 (generation? generation)
                 (odra-package-catalog-endpoint? endpoint)
                 (or (not credential-reference)
                     (and (bounded-text? credential-reference)
                          (positive? (string-length credential-reference))))
                 (if (eq? (odra-package-catalog-endpoint-transport endpoint) 'file)
                     (not credential-reference)
                     #t))
      (raise-arguments-error 'odra-package-catalog-state-endpoint
                             "invalid versioned catalog endpoint state"))
    (values format-version generation endpoint
            (and credential-reference (copied credential-reference)))))

(struct odra-package-catalog-confirmed-snapshot-reference
  (format-version catalog-id snapshot-id sequence digest cache-reference confirmed-at)
  #:transparent
  #:guard
  (lambda (format-version catalog-id snapshot-id sequence digest cache-reference
                          confirmed-at _)
    (unless (and (= format-version current-package-catalog-state-format-version)
                 (digest? catalog-id)
                 (digest? snapshot-id)
                 (generation? sequence)
                 (digest? digest)
                 (relative-reference? cache-reference)
                 (u64? confirmed-at))
      (raise-arguments-error 'odra-package-catalog-confirmed-snapshot-reference
                             "invalid confirmed catalog snapshot reference"))
    (values format-version (copied catalog-id) (copied snapshot-id) sequence
            (copied digest) (copied cache-reference) confirmed-at)))

(struct odra-package-catalog-state-failure
  (format-version id catalog-id code generation detail)
  #:transparent
  #:guard
  (lambda (format-version id catalog-id code generation detail _)
    (unless (and (= format-version current-package-catalog-state-format-version)
                 (identity? id)
                 (digest? catalog-id)
                 (memq code failure-codes)
                 (generation? generation)
                 (bounded-text? detail))
      (raise-arguments-error 'odra-package-catalog-state-failure
                             "invalid bounded catalog state failure"))
    (values format-version (copied id) (copied catalog-id) code generation
            (copied detail))))

(define (registration-endpoints-valid? registration endpoints-by-id)
  (for/and ([endpoint-id
             (in-list (odra-package-catalog-registration-endpoint-ids registration))])
    (define endpoint-state (hash-ref endpoints-by-id endpoint-id #f))
    (and endpoint-state
         (string=?
          (odra-package-catalog-registration-catalog-id registration)
          (odra-package-catalog-endpoint-catalog-id
           (odra-package-catalog-state-endpoint-endpoint endpoint-state))))))

(define (endpoint-owned? endpoint-state registrations)
  (define endpoint (odra-package-catalog-state-endpoint-endpoint endpoint-state))
  (for/or ([registration (in-list registrations)])
    (and (string=? (odra-package-catalog-endpoint-catalog-id endpoint)
                   (odra-package-catalog-registration-catalog-id registration))
         (member (odra-package-catalog-endpoint-id endpoint)
                 (odra-package-catalog-registration-endpoint-ids registration)
                 string=?))))

(struct odra-package-catalog-state
  (format-version root-id generation registrations endpoints confirmed-snapshots
                  failures quarantine checksum)
  #:transparent
  #:guard
  (lambda (format-version root-id generation registrations endpoints
                          confirmed-snapshots failures quarantine checksum _)
    (define endpoints-by-id
      (and (list? endpoints)
           (for/hash ([endpoint-state (in-list endpoints)]
                      #:when (odra-package-catalog-state-endpoint? endpoint-state))
             (values
              (odra-package-catalog-endpoint-id
               (odra-package-catalog-state-endpoint-endpoint endpoint-state))
              endpoint-state))))
    (unless
        (and (= format-version current-package-catalog-state-format-version)
             (identity? root-id)
             (generation? generation)
             (list? registrations)
             (<= (length registrations) maximum-package-catalog-registrations)
             (andmap odra-package-catalog-registration? registrations)
             (unique-sorted? registrations odra-package-catalog-registration-id
                             string<? string=?)
             (list? endpoints)
             (<= (length endpoints) maximum-package-catalog-state-endpoints)
             (andmap odra-package-catalog-state-endpoint? endpoints)
             (unique-sorted?
              endpoints
              (lambda (value)
                (odra-package-catalog-endpoint-id
                 (odra-package-catalog-state-endpoint-endpoint value)))
              string<? string=?)
             (andmap
              (lambda (registration)
                (registration-endpoints-valid? registration endpoints-by-id))
              registrations)
             (andmap (lambda (endpoint-state)
                       (endpoint-owned? endpoint-state registrations))
                     endpoints)
             (list? confirmed-snapshots)
             (<= (length confirmed-snapshots)
                 maximum-package-catalog-confirmed-snapshots)
             (andmap odra-package-catalog-confirmed-snapshot-reference?
                     confirmed-snapshots)
             (unique-sorted?
              confirmed-snapshots
              odra-package-catalog-confirmed-snapshot-reference-catalog-id
              string<? string=?)
             (list? failures)
             (<= (length failures) maximum-package-catalog-state-failures)
             (andmap odra-package-catalog-state-failure? failures)
             (unique-sorted? failures odra-package-catalog-state-failure-id
                             string<? string=?)
             (list? quarantine)
             (<= (length quarantine)
                 maximum-package-catalog-quarantine-references)
             (andmap relative-reference? quarantine)
             (equal? quarantine
                     (sort (remove-duplicates quarantine string=?) string<?))
             (digest? checksum))
      (raise-arguments-error 'odra-package-catalog-state
                             "invalid aggregate package catalog state"))
    (values format-version (copied root-id) generation
            (for/list ([value (in-list registrations)]) value)
            (for/list ([value (in-list endpoints)]) value)
            (for/list ([value (in-list confirmed-snapshots)]) value)
            (for/list ([value (in-list failures)]) value)
            (copied-list quarantine) (copied checksum))))

(define (package-catalog-empty-state root-id)
  (package-catalog-state-with-checksum
   (odra-package-catalog-state
    current-package-catalog-state-format-version root-id 1 '() '() '() '() '()
    (make-string 64 #\0))))

(define (endpoint->datum endpoint)
  (list (odra-package-catalog-endpoint-id endpoint)
        (odra-package-catalog-endpoint-catalog-id endpoint)
        (odra-package-catalog-endpoint-uri endpoint)
        (odra-package-catalog-endpoint-transport endpoint)
        (odra-package-catalog-endpoint-role endpoint)
        (odra-package-catalog-endpoint-priority endpoint)
        (odra-package-catalog-endpoint-enabled? endpoint)))

(define (registration->datum registration)
  (list (odra-package-catalog-registration-format-version registration)
        (odra-package-catalog-registration-id registration)
        (odra-package-catalog-registration-generation registration)
        (odra-package-catalog-registration-catalog-id registration)
        (odra-package-catalog-registration-configuration-origin registration)
        (odra-package-catalog-registration-trust-root-ref registration)
        (odra-package-catalog-registration-endpoint-ids registration)
        (odra-package-catalog-registration-package-precedence registration)
        (odra-package-catalog-registration-advisory-policy registration)
        (odra-package-catalog-registration-enabled? registration)
        (odra-package-catalog-registration-refresh-state registration)))

(define (state-endpoint->datum endpoint-state)
  (list (odra-package-catalog-state-endpoint-format-version endpoint-state)
        (odra-package-catalog-state-endpoint-generation endpoint-state)
        (endpoint->datum
         (odra-package-catalog-state-endpoint-endpoint endpoint-state))
        (odra-package-catalog-state-endpoint-credential-reference endpoint-state)))

(define (confirmed->datum confirmed)
  (list
   (odra-package-catalog-confirmed-snapshot-reference-format-version confirmed)
   (odra-package-catalog-confirmed-snapshot-reference-catalog-id confirmed)
   (odra-package-catalog-confirmed-snapshot-reference-snapshot-id confirmed)
   (odra-package-catalog-confirmed-snapshot-reference-sequence confirmed)
   (odra-package-catalog-confirmed-snapshot-reference-digest confirmed)
   (odra-package-catalog-confirmed-snapshot-reference-cache-reference confirmed)
   (odra-package-catalog-confirmed-snapshot-reference-confirmed-at confirmed)))

(define (failure->datum failure)
  (list (odra-package-catalog-state-failure-format-version failure)
        (odra-package-catalog-state-failure-id failure)
        (odra-package-catalog-state-failure-catalog-id failure)
        (odra-package-catalog-state-failure-code failure)
        (odra-package-catalog-state-failure-generation failure)
        (odra-package-catalog-state-failure-detail failure)))

(define (state-payload state)
  (list 'package-catalog-state
        '#:format-version (odra-package-catalog-state-format-version state)
        '#:root-id (odra-package-catalog-state-root-id state)
        '#:generation (odra-package-catalog-state-generation state)
        '#:registrations
        (map registration->datum
             (odra-package-catalog-state-registrations state))
        '#:endpoints
        (map state-endpoint->datum (odra-package-catalog-state-endpoints state))
        '#:confirmed-snapshots
        (map confirmed->datum
             (odra-package-catalog-state-confirmed-snapshots state))
        '#:failures
        (map failure->datum (odra-package-catalog-state-failures state))
        '#:quarantine (odra-package-catalog-state-quarantine state)))

(define (package-catalog-state-checksum state)
  (bytes->hex-string
   (sha256-bytes
    (open-input-bytes (record-datum->module-bytes (state-payload state))))))

(define (package-catalog-state-with-checksum state)
  (struct-copy odra-package-catalog-state state
               [checksum (package-catalog-state-checksum state)]))

(define (package-catalog-state->module-bytes state)
  (unless (string=? (odra-package-catalog-state-checksum state)
                    (package-catalog-state-checksum state))
    (raise-arguments-error 'package-catalog-state->module-bytes
                           "package catalog state checksum differs"))
  (record-datum->module-bytes
   (append (state-payload state)
           (list '#:checksum (odra-package-catalog-state-checksum state)))))

(define (decode-endpoint datum)
  (match datum
    [(list id catalog-id uri transport role priority enabled?)
     (odra-package-catalog-endpoint
      id catalog-id uri transport role priority enabled?)]))

(define (decode-registration datum)
  (apply odra-package-catalog-registration datum))

(define (decode-state-endpoint datum)
  (match datum
    [(list format-version generation endpoint credential-reference)
     (odra-package-catalog-state-endpoint
      format-version generation (decode-endpoint endpoint) credential-reference)]))

(define (decode-confirmed datum)
  (apply odra-package-catalog-confirmed-snapshot-reference datum))

(define (decode-failure datum)
  (apply odra-package-catalog-state-failure datum))

(define (decode-state datum)
  (match datum
    [(list 'package-catalog-state
           '#:format-version format-version
           '#:root-id root-id
           '#:generation generation
           '#:registrations registrations
           '#:endpoints endpoints
           '#:confirmed-snapshots confirmed
           '#:failures failures
           '#:quarantine quarantine
           '#:checksum checksum)
     (unless (package-catalog-state-compatible-format? format-version)
       (raise-arguments-error 'package-catalog-state
                              "unsupported package catalog state version"))
     (define state
       (odra-package-catalog-state
        format-version root-id generation
        (map decode-registration registrations)
        (map decode-state-endpoint endpoints)
        (map decode-confirmed confirmed)
        (map decode-failure failures)
        quarantine checksum))
     (unless (string=? checksum (package-catalog-state-checksum state))
       (raise-arguments-error 'package-catalog-state "checksum mismatch"))
     state]
    [_
     (raise-arguments-error 'package-catalog-state
                            "unsupported package catalog state schema")]))

(define (decode-state-format datum)
  (match datum
    [(list* 'package-catalog-state '#:format-version
            (? exact-positive-integer? version) _)
     version]
    [_
     (raise-arguments-error 'package-catalog-state
                            "unsupported package catalog state schema")]))

(define (package-catalog-state-compatible-format? version)
  (and (exact-positive-integer? version)
       (<= minimum-package-catalog-state-format-version version
           current-package-catalog-state-format-version)))

(define (package-catalog-state-module-format path)
  (record-module-load path decode-state-format))

(define (package-catalog-state-module-load path)
  (record-module-load path decode-state))
