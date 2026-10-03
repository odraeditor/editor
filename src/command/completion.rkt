#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base)

(provide
 factory-completion-configuration
 (struct-out odra-completion-configuration)
 (contract-out
  [completion-configuration
   (->* ()
        (#:enabled? boolean?
         #:provider symbol?
         #:policy symbol?
         #:presentation symbol?
         #:explicit? boolean?
         #:identifier? boolean?
         #:trigger-character? boolean?
         #:minimum-prefix exact-positive-integer?
         #:case-sensitive-prefix? boolean?
         #:case-insensitive-prefix? boolean?
         #:subsequence? boolean?
         #:candidate-limit exact-positive-integer?
         #:additional-edit-limit exact-nonnegative-integer?
         #:text-byte-limit exact-positive-integer?
         #:detail-byte-limit exact-positive-integer?
         #:resolve-byte-limit exact-positive-integer?
         #:implementation-limit exact-positive-integer?
         #:replacement-limit exact-positive-integer?
         #:request-replacement-limit exact-positive-integer?)
        odra-completion-configuration?)]
  [normalize-completion-configuration
   (-> any/c odra-completion-configuration?)]))

(define maximum-name-bytes 96)

(define (bounded-name? value)
  (and (symbol? value)
       (positive? (string-length (symbol->string value)))
       (<= (bytes-length (string->bytes/utf-8 (symbol->string value)))
           maximum-name-bytes)))

(struct odra-completion-configuration
  (enabled? provider policy presentation explicit? identifier? trigger-character?
            minimum-prefix case-sensitive-prefix? case-insensitive-prefix? subsequence?
            candidate-limit additional-edit-limit text-byte-limit detail-byte-limit
            resolve-byte-limit implementation-limit replacement-limit
            request-replacement-limit)
  #:transparent
  #:guard
  (lambda (enabled? provider policy presentation explicit? identifier? trigger-character?
            minimum-prefix case-sensitive-prefix? case-insensitive-prefix? subsequence?
            candidate-limit additional-edit-limit text-byte-limit detail-byte-limit
            resolve-byte-limit implementation-limit replacement-limit
            request-replacement-limit _)
    (unless (andmap bounded-name? (list provider policy presentation))
      (raise-arguments-error 'odra-completion-configuration
                             "role names must be bounded non-empty symbols"))
    (unless (and (<= 1 minimum-prefix 65535)
                 (or case-sensitive-prefix? case-insensitive-prefix? subsequence?))
      (raise-arguments-error 'odra-completion-configuration
                             "prefix and filtering policy is invalid"))
    (unless (and (<= 1 candidate-limit 128)
                 (<= 0 additional-edit-limit 8)
                 (<= 1 text-byte-limit 256)
                 (<= 1 detail-byte-limit 1024)
                 (<= 1 resolve-byte-limit 512)
                 (<= 3 implementation-limit 16)
                 (<= 1 replacement-limit 1024)
                 (<= 1 request-replacement-limit 1024))
      (raise-arguments-error 'odra-completion-configuration
                             "completion resource limits exceed admitted bounds"))
    (values enabled? provider policy presentation explicit? identifier?
            trigger-character? minimum-prefix case-sensitive-prefix?
            case-insensitive-prefix? subsequence? candidate-limit
            additional-edit-limit text-byte-limit detail-byte-limit
            resolve-byte-limit implementation-limit replacement-limit
            request-replacement-limit)))

(define factory-completion-configuration
  (odra-completion-configuration
   #t 'language-service 'factory-completion 'interactive-candidate
   #t #f #t 2 #t #t #t 128 8 256 1024 512 16 1024 1024))

;; completion-configuration constructs one complete immutable policy generation.
(define (completion-configuration
         #:enabled? [enabled? #t]
         #:provider [provider 'language-service]
         #:policy [policy 'factory-completion]
         #:presentation [presentation 'interactive-candidate]
         #:explicit? [explicit? #t]
         #:identifier? [identifier? #f]
         #:trigger-character? [trigger-character? #t]
         #:minimum-prefix [minimum-prefix 2]
         #:case-sensitive-prefix? [case-sensitive-prefix? #t]
         #:case-insensitive-prefix? [case-insensitive-prefix? #t]
         #:subsequence? [subsequence? #t]
         #:candidate-limit [candidate-limit 128]
         #:additional-edit-limit [additional-edit-limit 8]
         #:text-byte-limit [text-byte-limit 256]
         #:detail-byte-limit [detail-byte-limit 1024]
         #:resolve-byte-limit [resolve-byte-limit 512]
         #:implementation-limit [implementation-limit 16]
         #:replacement-limit [replacement-limit 1024]
         #:request-replacement-limit [request-replacement-limit 1024])
  (odra-completion-configuration
   enabled? provider policy presentation explicit? identifier? trigger-character?
   minimum-prefix case-sensitive-prefix? case-insensitive-prefix? subsequence?
   candidate-limit additional-edit-limit text-byte-limit detail-byte-limit
   resolve-byte-limit implementation-limit replacement-limit
   request-replacement-limit))

(define (normalize-completion-configuration value)
  (cond
    [(not value) factory-completion-configuration]
    [(odra-completion-configuration? value) value]
    [(hash? value)
     (completion-configuration
      #:enabled? (hash-ref value 'enabled? #t)
      #:provider (hash-ref value 'provider 'language-service)
      #:policy (hash-ref value 'policy 'factory-completion)
      #:presentation (hash-ref value 'presentation 'interactive-candidate)
      #:explicit? (hash-ref value 'explicit? #t)
      #:identifier? (hash-ref value 'identifier? #f)
      #:trigger-character? (hash-ref value 'trigger-character? #t)
      #:minimum-prefix (hash-ref value 'minimum-prefix 2)
      #:case-sensitive-prefix? (hash-ref value 'case-sensitive-prefix? #t)
      #:case-insensitive-prefix? (hash-ref value 'case-insensitive-prefix? #t)
      #:subsequence? (hash-ref value 'subsequence? #t)
      #:candidate-limit (hash-ref value 'candidate-limit 128)
      #:additional-edit-limit (hash-ref value 'additional-edit-limit 8)
      #:text-byte-limit (hash-ref value 'text-byte-limit 256)
      #:detail-byte-limit (hash-ref value 'detail-byte-limit 1024)
      #:resolve-byte-limit (hash-ref value 'resolve-byte-limit 512)
      #:implementation-limit (hash-ref value 'implementation-limit 16)
      #:replacement-limit (hash-ref value 'replacement-limit 1024)
      #:request-replacement-limit (hash-ref value 'request-replacement-limit 1024))]
    [else
     (raise-arguments-error 'normalize-completion-configuration
                            "expected a completion configuration or hash"
                            "value" value)]))

(module+ test
  (require rackunit)

  (check-equal?
   (normalize-completion-configuration #f)
   factory-completion-configuration)
  (check-false
   (odra-completion-configuration-identifier?
    factory-completion-configuration))
  (define configured
    (normalize-completion-configuration
     '#hash((identifier? . #t)
            (minimum-prefix . 3)
            (subsequence? . #f)
            (candidate-limit . 64))))
  (check-true (odra-completion-configuration-identifier? configured))
  (check-equal? (odra-completion-configuration-minimum-prefix configured) 3)
  (check-equal? (odra-completion-configuration-candidate-limit configured) 64)
  (check-exn exn:fail?
             (lambda ()
               (completion-configuration
                #:case-sensitive-prefix? #f
                #:case-insensitive-prefix? #f
                #:subsequence? #f))))
