#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         racket/match)

(provide
 ksawery-extension-api-version
 default-ksawery-extension-limits
 make-ksawery-extension-limits
 ksawery-extension-limits?
 make-ksawery-contribution
 ksawery-contribution?
 make-ksawery-contributor
 ksawery-contributor?
 ksawery-contributor-compatible?
 ksawery-contributor-annotation-provider
 ksawery-contributor-annotation-execution-limits
 ksawery-contributor-conflict-assistance-provider
 ksawery-contributor-conflict-assistance-execution-limits
 ksawery-contributor-command-execution-limits
 ksawery-contributor-status-provider
 ksawery-contributor-status-execution-limits
 ksawery-contributor->datum
 ksawery-contributor-encode
 decode-ksawery-contributor)

(define ksawery-extension-api-version 1)
(define maximum-contributors 32)
(define maximum-contributions-per-contributor 64)
(define maximum-total-contributions 2048)
(define maximum-identity-bytes 96)
(define maximum-label-bytes 128)
(define maximum-provenance-bytes 1024)
(define maximum-declaration-bytes (* 8 1024 1024))
(define maximum-observation-bytes (* 8 1024 1024))
(define maximum-result-bytes (* 8 1024 1024))
(define maximum-provider-value-bytes (* 4 1024 1024))
(define maximum-diagnostic-bytes (* 64 1024))
(define maximum-turn-deadline-milliseconds 2000)
(define maximum-custodian-memory-bytes (* 128 1024 1024))
(define maximum-callbacks-per-turn 256)
(define maximum-retained-native-bytes (* 32 1024 1024))
(define maximum-temporary-native-bytes (* 32 1024 1024))

(define contribution-kinds
  '(command keymap status-section annotation command-family
            external-operation conflict-assistance provider-role))
(define provider-roles '(none conflict-assistance))
(define observation-families '(status history refs sequence conflict process))
(define authorities
  '(inspect present invoke-declared-command request-core-action
            submit-external-operation assist-conflict))
(define contributor-origins '(built-in personal package))

(define origin-codes '((built-in . 1) (personal . 2) (package . 3)))
(define contribution-kind-codes
  '((command . 1) (keymap . 2) (status-section . 3) (annotation . 4)
                 (command-family . 5) (external-operation . 6)
                 (conflict-assistance . 7) (provider-role . 8)))
(define provider-role-codes '((none . 0) (conflict-assistance . 1)))

(struct ksawery-extension-limits
  (contributors contributions-per-contributor total-contributions
                declaration-bytes observation-bytes result-bytes
                provider-value-bytes diagnostic-bytes turn-deadline-milliseconds
                custodian-memory-bytes callbacks-per-turn nesting-depth
                retained-native-bytes temporary-native-bytes)
  #:transparent)

(struct ksawery-contribution
  (id identity kind provider-role required-observations requested-authorities)
  #:transparent)

(struct ksawery-contributor
  (identity display-name origin provenance generation api-version limits contributions)
  #:transparent)

(define contributor-status-providers (make-weak-hasheq))
(define contributor-annotation-providers (make-weak-hasheq))
(define contributor-conflict-assistance-providers (make-weak-hasheq))

;; make-ksawery-extension-limits validates one complete requested policy.
(define (make-ksawery-extension-limits
         #:contributors [contributors 8]
         #:contributions-per-contributor [per-contributor 16]
         #:total-contributions [total-contributions 128]
         #:declaration-bytes [declaration-bytes (* 1024 1024)]
         #:observation-bytes [observation-bytes (* 1024 1024)]
         #:result-bytes [result-bytes (* 1024 1024)]
         #:provider-value-bytes [provider-value-bytes (* 256 1024)]
         #:diagnostic-bytes [diagnostic-bytes (* 4 1024)]
         #:turn-deadline-milliseconds [deadline 250]
         #:custodian-memory-bytes [custodian-memory (* 32 1024 1024)]
         #:callbacks-per-turn [callbacks 64]
         #:nesting-depth [nesting-depth 1]
         #:retained-native-bytes [retained-native (* 32 1024 1024)]
         #:temporary-native-bytes [temporary-native (* 32 1024 1024)])
  (check-limit 'contributors contributors maximum-contributors)
  (check-limit 'contributions-per-contributor per-contributor
               maximum-contributions-per-contributor)
  (check-limit 'total-contributions total-contributions
               maximum-total-contributions)
  (unless (>= (* contributors per-contributor) total-contributions)
    (raise-arguments-error 'make-ksawery-extension-limits
                           "aggregate contribution capacity is inconsistent"))
  (check-limit 'declaration-bytes declaration-bytes maximum-declaration-bytes)
  (check-limit 'observation-bytes observation-bytes maximum-observation-bytes)
  (check-limit 'result-bytes result-bytes maximum-result-bytes)
  (check-limit 'provider-value-bytes provider-value-bytes
               maximum-provider-value-bytes)
  (check-limit 'diagnostic-bytes diagnostic-bytes maximum-diagnostic-bytes)
  (check-limit 'turn-deadline-milliseconds deadline
               maximum-turn-deadline-milliseconds)
  (check-limit 'custodian-memory-bytes custodian-memory
               maximum-custodian-memory-bytes)
  (check-limit 'callbacks-per-turn callbacks maximum-callbacks-per-turn)
  (unless (= nesting-depth 1)
    (raise-arguments-error 'make-ksawery-extension-limits
                           "provider turns must be non-reentrant"))
  (check-limit 'retained-native-bytes retained-native
               maximum-retained-native-bytes)
  (check-limit 'temporary-native-bytes temporary-native
               maximum-temporary-native-bytes)
  (ksawery-extension-limits
   contributors per-contributor total-contributions declaration-bytes
   observation-bytes result-bytes provider-value-bytes diagnostic-bytes
   deadline custodian-memory callbacks nesting-depth retained-native
   temporary-native))

;; make-ksawery-contribution constructs one inert owner-local declaration.
(define (make-ksawery-contribution id identity kind
                                   #:provider-role [provider-role 'none]
                                   #:observations [observations '()]
                                   #:authorities [requested '(inspect)])
  (unless (exact-positive-integer? id)
    (raise-argument-error 'make-ksawery-contribution
                          "exact-positive-integer?" id))
  (define copied-identity (validated-identity 'make-ksawery-contribution identity))
  (check-member 'make-ksawery-contribution 'kind kind contribution-kinds)
  (check-member 'make-ksawery-contribution 'provider-role provider-role provider-roles)
  (unless (or (and (eq? kind 'provider-role)
                   (not (eq? provider-role 'none)))
              (and (not (eq? kind 'provider-role))
                   (eq? provider-role 'none)))
    (raise-arguments-error 'make-ksawery-contribution
                           "provider-role is valid only for provider-role contributions"))
  (define copied-observations
    (validated-symbol-list 'make-ksawery-contribution 'observations
                           observations observation-families #t))
  (define copied-authorities
    (validated-symbol-list 'make-ksawery-contribution 'authorities
                           requested authorities #f))
  (ksawery-contribution id copied-identity kind provider-role
                        copied-observations copied-authorities))

;; make-ksawery-contributor constructs one complete inert generation.
(define (make-ksawery-contributor identity display-name provenance generation contributions
                                  #:origin [origin 'personal]
                                  #:api-version [api-version ksawery-extension-api-version]
                                  #:limits [limits default-ksawery-extension-limits]
                                  #:annotation-provider [annotation-provider #f]
                                  #:conflict-assistance-provider [conflict-assistance-provider #f]
                                  #:status-provider [status-provider #f])
  (define copied-identity (validated-identity 'make-ksawery-contributor identity))
  (define copied-label
    (validated-text 'make-ksawery-contributor 'display-name display-name
                    maximum-label-bytes))
  (check-member 'make-ksawery-contributor 'origin origin contributor-origins)
  (define copied-provenance
    (validated-text 'make-ksawery-contributor 'provenance provenance
                    maximum-provenance-bytes))
  (unless (exact-positive-integer? generation)
    (raise-argument-error 'make-ksawery-contributor
                          "exact-positive-integer?" generation))
  (unless (= api-version ksawery-extension-api-version)
    (raise-arguments-error 'make-ksawery-contributor
                           "incompatible Ksawery extension API"
                           "requested" api-version
                           "supported" ksawery-extension-api-version))
  (unless (ksawery-extension-limits? limits)
    (raise-argument-error 'make-ksawery-contributor
                          "ksawery-extension-limits?" limits))
  (unless (and (list? contributions) (pair? contributions)
               (andmap ksawery-contribution? contributions))
    (raise-argument-error 'make-ksawery-contributor
                          "non-empty list of ksawery-contribution?" contributions))
  (when (> (length contributions)
           (ksawery-extension-limits-contributions-per-contributor limits))
    (raise-arguments-error 'make-ksawery-contributor
                           "contribution count exceeds the requested policy"))
  (unless (= (length contributions)
             (length
              (remove-duplicates
               (map ksawery-contribution-id contributions))))
    (raise-arguments-error 'make-ksawery-contributor
                           "duplicate contribution identity"))
  (when status-provider
    (unless (and (procedure? status-provider)
                 (procedure-arity-includes? status-provider 1)
                 (ormap (lambda (contribution)
                          (and (eq? (ksawery-contribution-kind contribution)
                                    'status-section)
                               (memq 'status
                                     (ksawery-contribution-required-observations
                                      contribution))
                               (memq 'inspect
                                     (ksawery-contribution-requested-authorities
                                      contribution))
                               (memq 'present
                                     (ksawery-contribution-requested-authorities
                                      contribution))))
                        contributions))
      (raise-arguments-error
       'make-ksawery-contributor
       "Status provider must accept one observation and own an admitted status-section contribution")))
  (when annotation-provider
    (unless (and (procedure? annotation-provider)
                 (procedure-arity-includes? annotation-provider 1)
                 (ormap (lambda (contribution)
                          (and (eq? (ksawery-contribution-kind contribution)
                                    'annotation)
                               (pair?
                                (ksawery-contribution-required-observations contribution))
                               (memq 'inspect
                                     (ksawery-contribution-requested-authorities
                                      contribution))
                               (memq 'present
                                     (ksawery-contribution-requested-authorities
                                      contribution))))
                        contributions))
      (raise-arguments-error
       'make-ksawery-contributor
       "Annotation provider must accept one observation and own an admitted annotation contribution")))
  (when conflict-assistance-provider
    (unless (and (procedure? conflict-assistance-provider)
                 (procedure-arity-includes? conflict-assistance-provider 3)
                 (ormap (lambda (contribution)
                          (and (eq? (ksawery-contribution-kind contribution)
                                    'provider-role)
                               (eq? (ksawery-contribution-provider-role contribution)
                                    'conflict-assistance)
                               (andmap
                                (lambda (observation)
                                  (memq observation
                                        (ksawery-contribution-required-observations
                                         contribution)))
                                '(sequence conflict))
                               (andmap
                                (lambda (authority)
                                  (memq authority
                                        (ksawery-contribution-requested-authorities
                                         contribution)))
                                '(inspect present assist-conflict))))
                        contributions))
      (raise-arguments-error
       'make-ksawery-contributor
       "Conflict-assistance provider must accept the contributor, request, and one observation and own the admitted role")))
  (define copied-contributions (map values contributions))
  (define declaration-bytes
    (+ (utf8-bytes copied-identity) (utf8-bytes copied-label)
       (utf8-bytes copied-provenance)
       (for/sum ([contribution (in-list copied-contributions)])
         (+ 64 (utf8-bytes (ksawery-contribution-identity contribution))))))
  (when (> declaration-bytes
           (ksawery-extension-limits-declaration-bytes limits))
    (raise-arguments-error 'make-ksawery-contributor
                           "declaration exceeds the requested byte policy"))
  (define contributor
    (ksawery-contributor copied-identity copied-label origin copied-provenance
                         generation api-version limits copied-contributions))
  (when status-provider
    (hash-set! contributor-status-providers contributor status-provider))
  (when annotation-provider
    (hash-set! contributor-annotation-providers contributor annotation-provider))
  (when conflict-assistance-provider
    (hash-set! contributor-conflict-assistance-providers
               contributor conflict-assistance-provider))
  contributor)

;; ksawery-contributor-annotation-provider returns only the retained implementation.
(define (ksawery-contributor-annotation-provider contributor)
  (hash-ref contributor-annotation-providers contributor #f))

;; ksawery-contributor-annotation-execution-limits copies the provider turn policy.
(define (ksawery-contributor-annotation-execution-limits contributor)
  (ksawery-contributor-provider-execution-limits
   'ksawery-contributor-annotation-execution-limits contributor))

;; ksawery-contributor-conflict-assistance-provider returns only the retained implementation.
(define (ksawery-contributor-conflict-assistance-provider contributor)
  (hash-ref contributor-conflict-assistance-providers contributor #f))

;; ksawery-contributor-conflict-assistance-execution-limits copies the turn policy.
(define (ksawery-contributor-conflict-assistance-execution-limits contributor)
  (ksawery-contributor-provider-execution-limits
   'ksawery-contributor-conflict-assistance-execution-limits contributor))

;; ksawery-contributor-command-execution-limits copies the command-turn policy.
(define (ksawery-contributor-command-execution-limits contributor)
  (ksawery-contributor-provider-execution-limits
   'ksawery-contributor-command-execution-limits contributor))

;; ksawery-contributor-status-provider returns only the retained implementation.
(define (ksawery-contributor-status-provider contributor)
  (hash-ref contributor-status-providers contributor #f))

;; ksawery-contributor-status-execution-limits copies the provider turn policy.
(define (ksawery-contributor-status-execution-limits contributor)
  (ksawery-contributor-provider-execution-limits
   'ksawery-contributor-status-execution-limits contributor))

(define (ksawery-contributor-provider-execution-limits who contributor)
  (unless (ksawery-contributor? contributor)
    (raise-argument-error who
                          "ksawery-contributor?" contributor))
  (define limits (ksawery-contributor-limits contributor))
  (hash
   'observation-bytes (ksawery-extension-limits-observation-bytes limits)
   'result-bytes (ksawery-extension-limits-result-bytes limits)
   'provider-value-bytes (ksawery-extension-limits-provider-value-bytes limits)
   'deadline-milliseconds
   (ksawery-extension-limits-turn-deadline-milliseconds limits)
   'custodian-memory-bytes
   (ksawery-extension-limits-custodian-memory-bytes limits)
   'diagnostic-bytes (ksawery-extension-limits-diagnostic-bytes limits)
   'temporary-native-bytes
   (ksawery-extension-limits-temporary-native-bytes limits)))

;; ksawery-contributor-compatible? checks the explicit API generation only.
(define (ksawery-contributor-compatible? contributor)
  (and (ksawery-contributor? contributor)
       (= (ksawery-contributor-api-version contributor)
          ksawery-extension-api-version)))

;; ksawery-contributor->datum returns an immutable data-only declaration.
(define (ksawery-contributor->datum contributor)
  (unless (ksawery-contributor? contributor)
    (raise-argument-error 'ksawery-contributor->datum "ksawery-contributor?" contributor))
  (hash 'identity (ksawery-contributor-identity contributor)
        'display-name (ksawery-contributor-display-name contributor)
        'origin (ksawery-contributor-origin contributor)
        'provenance (ksawery-contributor-provenance contributor)
        'generation (ksawery-contributor-generation contributor)
        'api-version (ksawery-contributor-api-version contributor)
        'limits (ksawery-contributor-limits contributor)
        'contributions
        (for/list ([contribution (in-list (ksawery-contributor-contributions contributor))])
          (hash 'id (ksawery-contribution-id contribution)
                'identity (ksawery-contribution-identity contribution)
                'kind (ksawery-contribution-kind contribution)
                'provider-role (ksawery-contribution-provider-role contribution)
                'observations (ksawery-contribution-required-observations contribution)
                'authorities (ksawery-contribution-requested-authorities contribution)))))

;; ksawery-contributor-encode copies one complete declaration for native staging.
(define (ksawery-contributor-encode contributor registry-generation)
  (unless (ksawery-contributor? contributor)
    (raise-argument-error 'ksawery-contributor-encode "ksawery-contributor?" contributor))
  (unless (exact-positive-integer? registry-generation)
    (raise-argument-error 'ksawery-contributor-encode
                          "exact-positive-integer?" registry-generation))
  (define contributions (ksawery-contributor-contributions contributor))
  (define text-values
    (append
     (list (ksawery-contributor-identity contributor)
           (ksawery-contributor-display-name contributor)
           (ksawery-contributor-provenance contributor))
     (map ksawery-contribution-identity contributions)))
  (define text-parts (map string->bytes/utf-8 text-values))
  (define offsets
    (let loop ([parts text-parts] [offset 0] [result '()])
      (if (null? parts)
          (reverse result)
          (loop (cdr parts) (+ offset (bytes-length (car parts)))
                (cons offset result)))))
  (define text (apply bytes-append text-parts))
  (define contribution-count (length contributions))
  (define record-bytes (+ 96 128 (* contribution-count 64) 112 (bytes-length text)))
  (define limits (ksawery-contributor-limits contributor))
  (when (> record-bytes (ksawery-extension-limits-declaration-bytes limits))
    (raise-arguments-error 'ksawery-contributor-encode
                           "encoded declaration exceeds the requested byte policy"
                           "limit" (ksawery-extension-limits-declaration-bytes limits)
                           "actual" record-bytes))
  (define authority-mask
    (for/fold ([result 0]) ([contribution (in-list contributions)])
      (bitwise-ior
       result
       (symbol-set-code (ksawery-contribution-requested-authorities contribution)
                        authorities))))
  (define contributor-record
    (words
     1
     (ksawery-contributor-generation contributor)
     (symbol-code (ksawery-contributor-origin contributor) origin-codes)
     1
     (list-ref offsets 0) (bytes-length (list-ref text-parts 0))
     (list-ref offsets 1) (bytes-length (list-ref text-parts 1))
     (list-ref offsets 2) (bytes-length (list-ref text-parts 2))
     authority-mask 0 contribution-count 0
     (count (lambda (entry)
              (not (eq? (ksawery-contribution-provider-role entry) 'none)))
            contributions)
     0))
  (define contribution-records
    (for/list ([contribution (in-list contributions)] [index (in-naturals 3)])
      (words
       (ksawery-contribution-id contribution)
       (symbol-code (ksawery-contribution-kind contribution) contribution-kind-codes)
       (symbol-code (ksawery-contribution-provider-role contribution) provider-role-codes)
       (symbol-set-code (ksawery-contribution-required-observations contribution)
                        observation-families)
       (symbol-set-code (ksawery-contribution-requested-authorities contribution)
                        authorities)
       (list-ref offsets index)
       (bytes-length (list-ref text-parts index))
       0)))
  (define limits-record
    (words
     (ksawery-extension-limits-contributors limits)
     (ksawery-extension-limits-contributions-per-contributor limits)
     (ksawery-extension-limits-total-contributions limits)
     (ksawery-extension-limits-declaration-bytes limits)
     (ksawery-extension-limits-observation-bytes limits)
     (ksawery-extension-limits-result-bytes limits)
     (ksawery-extension-limits-provider-value-bytes limits)
     (ksawery-extension-limits-diagnostic-bytes limits)
     (* 1000000 (ksawery-extension-limits-turn-deadline-milliseconds limits))
     (ksawery-extension-limits-custodian-memory-bytes limits)
     (ksawery-extension-limits-callbacks-per-turn limits)
     (ksawery-extension-limits-nesting-depth limits)
     (ksawery-extension-limits-retained-native-bytes limits)
     (ksawery-extension-limits-temporary-native-bytes limits)))
  (bytes-append
   (words 1 record-bytes ksawery-extension-api-version registry-generation
          1 contribution-count (bytes-length text) 0 1 0 0 0)
   contributor-record
   (apply bytes-append contribution-records)
   limits-record
   text))

;; decode-ksawery-contributor validates bounded data without activating it.
(define (decode-ksawery-contributor value)
  (unless (hash? value)
    (raise-argument-error 'decode-ksawery-contributor "hash?" value))
  (define decoded-contributions
    (for/list ([entry (in-list (hash-ref value 'contributions '()))])
      (unless (hash? entry)
        (raise-argument-error 'decode-ksawery-contributor "contribution hash?" entry))
      (make-ksawery-contribution
       (hash-ref entry 'id) (hash-ref entry 'identity) (hash-ref entry 'kind)
       #:provider-role (hash-ref entry 'provider-role 'none)
       #:observations (hash-ref entry 'observations '())
       #:authorities (hash-ref entry 'authorities '(inspect)))))
  (make-ksawery-contributor
   (hash-ref value 'identity) (hash-ref value 'display-name)
   (hash-ref value 'provenance) (hash-ref value 'generation)
   decoded-contributions
   #:origin (hash-ref value 'origin 'personal)
   #:api-version (hash-ref value 'api-version 0)
   #:limits (hash-ref value 'limits default-ksawery-extension-limits)))

(define (check-limit name value maximum)
  (unless (and (exact-positive-integer? value) (<= value maximum))
    (raise-arguments-error 'make-ksawery-extension-limits
                           "requested limit is outside the immutable maximum"
                           "limit" name "requested" value "maximum" maximum)))

(define (check-member who field value admitted)
  (unless (memq value admitted)
    (raise-arguments-error who "value is not admitted" field value)))

(define (validated-symbol-list who field entries admitted empty-allowed?)
  (unless (and (list? entries) (or empty-allowed? (pair? entries))
               (= (length entries) (length (remove-duplicates entries)))
               (andmap (lambda (value) (memq value admitted)) entries))
    (raise-arguments-error who "invalid or duplicate declaration values" field entries))
  (map values entries))

(define (validated-identity who value)
  (define text (if (symbol? value) (symbol->string value) value))
  (unless (and (string? text)
               (regexp-match? #px"^[a-z][a-z0-9]*(?:[./-][a-z0-9]+)*$" text)
               (<= (utf8-bytes text) maximum-identity-bytes))
    (raise-argument-error who "bounded lowercase semantic identity" value))
  (string->immutable-string text))

(define (validated-text who field value maximum)
  (unless (and (string? value) (positive? (string-length value))
               (not (for/or ([character (in-string value)])
                      (char=? character #\nul)))
               (<= (utf8-bytes value) maximum))
    (raise-arguments-error who "invalid or oversized text" field value))
  (string->immutable-string value))

(define (utf8-bytes value)
  (bytes-length (string->bytes/utf-8 value)))

(define (word value)
  (integer->integer-bytes value 8 #f #f))

(define (words . values)
  (apply bytes-append (map word values)))

(define (symbol-code value table)
  (define entry (assq value table))
  (unless entry (error 'ksawery-contributor-encode "unsupported value: ~a" value))
  (cdr entry))

(define (symbol-set-code values order)
  (for/fold ([result 0]) ([value (in-list values)])
    (bitwise-ior result (arithmetic-shift 1 (index-of order value)))))

(define default-ksawery-extension-limits (make-ksawery-extension-limits))
