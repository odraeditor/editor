#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         (only-in "../command/gutter.rkt"
                  factory-gutter-configuration
                  normalize-gutter-configuration
                  odra-gutter-configuration?
                  odra-gutter-configuration-visible?
                  odra-gutter-configuration-order
                  odra-gutter-configuration-minimum-digits
                  odra-gutter-configuration-maximum-digits
                  odra-gutter-configuration-left-padding
                  odra-gutter-configuration-right-padding
                  odra-gutter-configuration-separator
                  odra-gutter-configuration-separator-fallback
                  gutter-side-code
                  gutter-mode-code
                  gutter-scope-code
                  gutter-current-line-code))

(provide
 (struct-out gutter-startup-result)
 (contract-out
  [load-gutter-startup-value (-> any/c gutter-startup-result?)]))

(define maximum-diagnostic-bytes 4096)

(struct gutter-startup-result (status configuration diagnostic)
  #:transparent
  #:guard
  (lambda (status configuration diagnostic _)
    (unless (and (memq status '(confirmed rejected))
                 (odra-gutter-configuration? configuration)
                 (string? diagnostic)
                 (<= (bytes-length (string->bytes/utf-8 diagnostic))
                     maximum-diagnostic-bytes))
      (raise-arguments-error 'gutter-startup-result
                             "invalid bounded Gutter startup result"))
    (values status configuration diagnostic)))

(define (load-gutter-startup-value candidate)
  (with-handlers
      ([exn:fail?
        (lambda (failure)
          (gutter-startup-result
           'rejected factory-gutter-configuration
           (bounded-diagnostic (exn-message failure))))])
    (define configuration (normalize-gutter-configuration candidate))
    (when (= (gutter-scope-code configuration) 2)
      (raise-arguments-error 'load-gutter-startup-value
                             "visual numbering scope is reserved and unavailable"
                             "scope" 'visual))
    (gutter-startup-result 'confirmed configuration "")))

(define (bounded-diagnostic message)
  (if (> (bytes-length (string->bytes/utf-8 message)) maximum-diagnostic-bytes)
      "Gutter configuration failed with an oversized diagnostic"
      message))

(module+ test
  (require rackunit)

  (define configured
    (load-gutter-startup-value '#hash((mode . relative) (current-line . zero))))
  (check-equal? (gutter-startup-result-status configured) 'confirmed)
  (check-equal?
   (gutter-mode-code (gutter-startup-result-configuration configured)) 3)
  (check-equal?
   (gutter-current-line-code (gutter-startup-result-configuration configured)) 2)
  (check-equal?
   (gutter-startup-result-status
    (load-gutter-startup-value '#hash((scope . visual))))
   'rejected))
