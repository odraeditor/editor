#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         (only-in "../command/completion.rkt"
                  factory-completion-configuration
                  normalize-completion-configuration
                  odra-completion-configuration?
                  odra-completion-configuration-enabled?
                  odra-completion-configuration-provider
                  odra-completion-configuration-policy
                  odra-completion-configuration-presentation
                  odra-completion-configuration-explicit?
                  odra-completion-configuration-identifier?
                  odra-completion-configuration-trigger-character?
                  odra-completion-configuration-minimum-prefix
                  odra-completion-configuration-case-sensitive-prefix?
                  odra-completion-configuration-case-insensitive-prefix?
                  odra-completion-configuration-subsequence?
                  odra-completion-configuration-candidate-limit
                  odra-completion-configuration-additional-edit-limit
                  odra-completion-configuration-text-byte-limit
                  odra-completion-configuration-detail-byte-limit
                  odra-completion-configuration-resolve-byte-limit
                  odra-completion-configuration-implementation-limit
                  odra-completion-configuration-replacement-limit
                  odra-completion-configuration-request-replacement-limit))

(provide
 (struct-out completion-startup-result)
 (contract-out
  [load-completion-startup-value (-> any/c completion-startup-result?)]
  [completion-configuration-role-code
   (-> odra-completion-configuration? symbol? exact-positive-integer?)]))

(define maximum-diagnostic-bytes 4096)
(define factory-role-names
  '#hash((provider . language-service)
         (policy . factory-completion)
         (presentation . interactive-candidate)))

(struct completion-startup-result (status configuration diagnostic)
  #:transparent
  #:guard
  (lambda (status configuration diagnostic _)
    (unless (and (memq status '(confirmed rejected))
                 (odra-completion-configuration? configuration)
                 (string? diagnostic)
                 (<= (bytes-length (string->bytes/utf-8 diagnostic))
                     maximum-diagnostic-bytes))
      (raise-arguments-error 'completion-startup-result
                             "invalid bounded completion startup result"))
    (values status configuration diagnostic)))

(define (load-completion-startup-value candidate)
  (with-handlers
      ([exn:fail?
        (lambda (failure)
          (completion-startup-result
           'rejected factory-completion-configuration
           (bounded-diagnostic (exn-message failure))))])
    (define configuration (normalize-completion-configuration candidate))
    (for ([role '(provider policy presentation)])
      (completion-configuration-role-code configuration role))
    (completion-startup-result 'confirmed configuration "")))

(define (completion-configuration-role-code configuration role)
  (define value
    (case role
      [(provider) (odra-completion-configuration-provider configuration)]
      [(policy) (odra-completion-configuration-policy configuration)]
      [(presentation) (odra-completion-configuration-presentation configuration)]
      [else (raise-argument-error 'completion-configuration-role-code
                                  "provider, policy, or presentation" role)]))
  (unless (eq? value (hash-ref factory-role-names role))
    (raise-arguments-error 'completion-configuration-role-code
                           "named completion role is unavailable"
                           "role" role
                           "name" value))
  1)

(define (bounded-diagnostic message)
  (if (> (bytes-length (string->bytes/utf-8 message)) maximum-diagnostic-bytes)
      "Completion configuration failed with an oversized diagnostic"
      message))

(module+ test
  (require rackunit)

  (define confirmed
    (load-completion-startup-value
     '#hash((minimum-prefix . 3) (subsequence? . #f))))
  (check-equal? (completion-startup-result-status confirmed) 'confirmed)
  (check-equal?
   (odra-completion-configuration-minimum-prefix
    (completion-startup-result-configuration confirmed))
   3)
  (check-equal?
   (completion-startup-result-status
    (load-completion-startup-value '#hash((provider . unavailable))))
   'rejected))
