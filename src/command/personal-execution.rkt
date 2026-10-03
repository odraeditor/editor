#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         (only-in "../configuration/platform-roots.rkt"
                  odra-platform-roots-package-data
                  runtime-platform-roots-current)
         racket/string
         "catalog.rkt"
         "context.rkt"
         "personal.rkt"
         "package-resources.rkt"
         "personal-limits.rkt"
         "transaction.rkt"
         "../hosting/personal-command-containment.rkt"
         "../hosting/personal-command-runtime.rkt"
         "../hosting/personal-configuration-bridge.rkt"
         "../package/lifecycle-service.rkt"
         (only-in "../package/runtime.rkt"
                  call-with-contained-package-command))

(provide
 (contract-out
  [runtime-personal-command-dispatch
   (-> bytes?
       bytes?
       bytes?
       bytes?
       exact-positive-integer?
       exact-positive-integer?
       exact-positive-integer?
       exact-positive-integer?
       exact-nonnegative-integer?
       exact-nonnegative-integer?
       (or/c #f exact-nonnegative-integer?)
       (or/c #f exact-nonnegative-integer?)
       exact-nonnegative-integer?
       exact-nonnegative-integer?
       exact-nonnegative-integer?
       exact-nonnegative-integer?
       boolean?
       list?)]))

(define effect-bits
  '((#x01 . buffer) (#x02 . view) (#x08 . text-mutation)))

(define candidate-result-schema 2)
(define candidate-result-header-bytes 64)
(define candidate-result-record-bytes 96)
(define maximum-candidate-result-bytes (* 8 1024 1024))

(struct encoded-command-target
  (identity label searchable-fields document-path start end source-revision
            action))

(define (u64 value)
  (integer->integer-bytes value 8 #f #f))

(define (command-target-result-encode generation title initial-query targets)
  (define strings (open-output-bytes))
  (define records (open-output-bytes))
  (define (write-text value)
    (define encoded (string->bytes/utf-8 value))
    (define offset (file-position strings))
    (write-bytes encoded strings)
    (values offset (bytes-length encoded)))
  (define title-bytes (string->bytes/utf-8 title))
  (write-bytes title-bytes strings)
  (define-values (query-offset query-length)
    (write-text initial-query))
  (for ([target (in-list targets)])
    (define-values (identity-offset identity-length)
      (write-text (encoded-command-target-identity target)))
    (define-values (label-offset label-length)
      (write-text (encoded-command-target-label target)))
    (define-values (search-offset search-length)
      (write-text
       (string-join (encoded-command-target-searchable-fields target) " ")))
    (define target-path (encoded-command-target-document-path target))
    (define-values (path-offset path-length)
      (write-text (if (path? target-path)
                      (path->string target-path)
                      target-path)))
    (for ([value (in-list
                  (list identity-offset identity-length label-offset label-length
                        search-offset search-length path-offset path-length
                        (encoded-command-target-start target)
                        (encoded-command-target-end target)
                        (encoded-command-target-source-revision target)
                        (case (encoded-command-target-action target)
                          [(navigate) 1]
                          [(resume) 2]
                          [(resume-value) 3]
                          [(resume-query) 4]
                          [(navigate-direct) 5])))])
      (write-bytes (u64 value) records)))
  (define record-bytes (get-output-bytes records #t))
  (define string-bytes (get-output-bytes strings #t))
  (define encoded
    (bytes-append
     (apply bytes-append
            (map u64
                 (list candidate-result-schema
                       generation
                       (length targets)
                       candidate-result-record-bytes
                       query-offset query-length
                       (bytes-length string-bytes) (bytes-length title-bytes))))
     record-bytes string-bytes))
  (when (> (bytes-length encoded) maximum-candidate-result-bytes)
    (raise-arguments-error
     'command-candidate-result
     "encoded candidate result exceeds copied storage"
     "limit" maximum-candidate-result-bytes
     "actual" (bytes-length encoded)))
  encoded)

(define (command-candidate-result-encode result)
  (command-target-result-encode
   (command-candidate-result-generation result)
   (command-candidate-result-title result)
   (command-candidate-result-initial-query result)
   (for/list ([candidate
               (in-list (command-candidate-result-candidates result))])
     (encoded-command-target
      (command-candidate-identity candidate)
      (command-candidate-label candidate)
      (command-candidate-searchable-fields candidate)
      (command-candidate-document-path candidate)
      (command-candidate-start candidate)
      (command-candidate-end candidate)
      (command-candidate-source-revision candidate)
      (command-candidate-action candidate)))))

(define (command-navigation-result-encode result)
  (command-target-result-encode
   (command-navigation-result-source-revision result)
   "" ""
   (list
    (encoded-command-target
     "direct-navigation"
     (command-navigation-result-label result)
     '()
     (command-navigation-result-document-path result)
     (command-navigation-result-start result)
     (command-navigation-result-end result)
     (command-navigation-result-source-revision result)
     'navigate-direct))))

;; runtime-personal-command-dispatch invokes one exact retained procedure and context.
(define (runtime-personal-command-dispatch
         command-name document-path project-root candidate-selection
         route-generation route-slot capability-generation token
         revision point region-start region-end line-start line-end buffer-end
         effect-mask cancelled?)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #f (string->bytes/utf-8 (exn-message failure)) #""))])
    (define name (bytes->string/utf-8 command-name #f))
    (define effects
      (for/list ([entry (in-list effect-bits)]
                 #:when (not (zero? (bitwise-and effect-mask (car entry)))))
        (cdr entry)))
    (define roots (runtime-platform-roots-current))
    (define package-root
      (or (and roots (odra-platform-roots-package-data roots))
          (runtime-personal-configuration-root)))
    (define package-definition
      (and package-root
           (for/first
               ([definition
                 (in-list
                  (odra-command-catalog-definitions
                   (package-lifecycle-runtime-catalog package-root)))]
                #:when
                (and
                 (string=? name (odra-command-definition-name definition))
                 (string-prefix?
                  (odra-command-source-provider
                   (odra-command-definition-provenance definition))
                  "package:")))
             definition)))
    (define (package-data-root provenance)
      (and package-root
           (string-prefix? provenance "package:")
           (path->string
            (build-path package-root "packages" "data"
                        (substring provenance (string-length "package:"))))))
    (define (optional-path value)
      (and (positive? (bytes-length value))
           (path->string (bytes->path value))))
    (define (invoke implementation provenance)
      (define limits (personal-command-implementation-limits implementation))
      (call-with-personal-command-turn
       name provenance route-generation limits
       (lambda ()
         (call-with-native-transaction
          capability-generation token
          (lambda (transaction)
            (call-with-command-context
             transaction revision point region-start region-end
             line-start line-end buffer-end effects
             (lambda () cancelled?)
             (lambda (context)
               (define result
                 (if (command-context-cancelled? context)
                     (begin
                       (command-context-abort! context)
                       (command-reject 'cancelled "Command cancelled"))
                     (implementation context)))
               (list result (command-context-message context)))
             #:document-path (optional-path document-path)
             #:project-root (optional-path project-root)
             #:package-data-root (package-data-root provenance)
             #:package-resources
             (if (string-prefix? provenance "package:")
                 (filter
                  (lambda (resource)
                    (string=? (package-resource-package resource)
                              (substring provenance (string-length "package:"))))
                  (runtime-personal-package-resources))
                 '())
             #:candidate-selection
             (and (positive? (bytes-length candidate-selection))
                  (bytes->string/utf-8 candidate-selection #f))))
          #:limits
          (make-transaction-limits
           #:inspection-bytes
           (personal-command-limits-inspection-bytes limits)
           #:batch-splices
           (personal-command-limits-splices limits)
           #:text-bytes
           (personal-command-limits-replacement-bytes limits)
           #:nested-depth
           (personal-command-limits-nested-operations limits))))))
    (define outcome
      (if package-definition
          (invoke
           (lambda (context)
             (call-with-contained-package-command
              (lambda ()
                ((odra-command-definition-implementation package-definition)
                 context))))
           (odra-command-source-provider
            (odra-command-definition-provenance package-definition)))
          (personal-command-runtime-call
           route-generation route-slot name
           (lambda (implementation)
             (invoke implementation "personal configuration")))))
    (define result (car outcome))
    (define message (cadr outcome))
    (cond
      [(void? result) (list #t #t (string->bytes/utf-8 message) #"")]
      [(command-candidate-result? result)
       (list #t #t (string->bytes/utf-8 message)
             (command-candidate-result-encode result))]
      [(command-navigation-result? result)
       (list #t #t (string->bytes/utf-8 message)
             (command-navigation-result-encode result))]
      [(command-rejection? result)
       (list #t #f
             (string->bytes/utf-8
              (personal-command-safe-diagnostic
               name (command-rejection-message result)
               maximum-personal-diagnostic-bytes))
             #"")]
      [else
       (raise-result-error
        'runtime-personal-command-dispatch
        "void, command candidate result, command navigation result, or command rejection"
        result)])))

(module+ test
  (require rackunit)

  (define encoded
    (command-candidate-result-encode
     (make-command-candidate-result
      7
      "Ada"
      (list
       (make-command-candidate
        "ada" "Ada Lovelace" '("mathematician" "computing")
        "/brain/ada.org" 12 24 3))
      #:title "Roman relations: Ada Lovelace")))
  (define (encoded-u64 offset)
    (integer-bytes->integer encoded #f #f offset (+ offset 8)))
  (check-equal? (encoded-u64 0) candidate-result-schema)
  (check-equal? (encoded-u64 8) 7)
  (check-equal? (encoded-u64 16) 1)
  (check-equal? (encoded-u64 24) candidate-result-record-bytes)
  (check-equal? (encoded-u64 32) 29)
  (check-equal? (encoded-u64 40) 3)
  (check-equal? (encoded-u64 56) 29)
  (check-equal? (encoded-u64 (+ candidate-result-header-bytes (* 8 8))) 12)
  (check-equal? (encoded-u64 (+ candidate-result-header-bytes (* 9 8))) 24)
  (check-equal? (encoded-u64 (+ candidate-result-header-bytes (* 10 8))) 3)
  (check-equal? (encoded-u64 (+ candidate-result-header-bytes (* 11 8))) 1)
  (define string-start (+ candidate-result-header-bytes candidate-result-record-bytes))
  (check-equal? (subbytes encoded string-start (+ string-start 29))
                #"Roman relations: Ada Lovelace")
  (check-equal? (subbytes encoded (+ string-start 29) (+ string-start 32))
                #"Ada")

  (define encoded-resume
    (command-candidate-result-encode
     (make-command-candidate-result
      8
      ""
      (list
       (make-command-candidate
        "engine" "Analytical Engine" '("machine")
        "/brain/notes.org" 4 10 7 #:action 'resume)))))
  (check-equal?
   (integer-bytes->integer
    encoded-resume #f #f
    (+ candidate-result-header-bytes (* 11 8))
    (+ candidate-result-header-bytes (* 12 8)))
   2)

  (for ([action (in-list '(resume-value resume-query))]
        [encoded-action (in-list '(3 4))])
    (define encoded-input
      (command-candidate-result-encode
       (make-command-candidate-result
        9
        ""
        (list
         (make-command-candidate
          "value" "Use value" '()
          "/brain/notes.org" 4 4 7 #:action action)))))
    (check-equal?
     (integer-bytes->integer
      encoded-input #f #f
      (+ candidate-result-header-bytes (* 11 8))
      (+ candidate-result-header-bytes (* 12 8)))
     encoded-action))

  (define encoded-navigation
    (command-navigation-result-encode
     (make-command-navigation-result
      "Daily 2026-09-23 — daily/2026-09-23.org"
      "/brain/daily/2026-09-23.org" 0 0 4)))
  (check-equal?
   (integer-bytes->integer
    encoded-navigation #f #f
    (+ candidate-result-header-bytes (* 11 8))
    (+ candidate-result-header-bytes (* 12 8)))
   5))
