#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base)

(provide
 factory-gutter-configuration
 (struct-out odra-gutter-configuration)
 (contract-out
  [gutter-configuration
   (->* ()
        (#:visible? boolean? #:side symbol? #:order exact-integer?
         #:mode symbol? #:scope symbol? #:current-line symbol?
         #:minimum-digits exact-positive-integer?
         #:maximum-digits exact-positive-integer?
         #:left-padding exact-nonnegative-integer?
         #:right-padding exact-nonnegative-integer?
         #:separator string? #:separator-fallback string?)
        odra-gutter-configuration?)]
  [normalize-gutter-configuration
   (-> any/c odra-gutter-configuration?)]
  [gutter-side-code (-> odra-gutter-configuration? exact-positive-integer?)]
  [gutter-mode-code (-> odra-gutter-configuration? exact-positive-integer?)]
  [gutter-scope-code (-> odra-gutter-configuration? exact-positive-integer?)]
  [gutter-current-line-code
   (-> odra-gutter-configuration? exact-positive-integer?)]))

(define maximum-representation-bytes 64)
(define sides '(left right))
(define modes '(none absolute relative hybrid))
(define scopes '(logical visual))
(define current-line-presentations '(absolute zero hidden))

(define (bounded-representation? value)
  (and (positive? (string-length value))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum-representation-bytes)
       (for/and ([character (in-string value)])
         (define code (char->integer character))
         (not (or (< code 32) (<= 127 code 159))))))

(struct odra-gutter-configuration
  (visible? side order mode scope current-line minimum-digits maximum-digits
            left-padding right-padding separator separator-fallback)
  #:transparent
  #:guard
  (lambda (visible? side order mode scope current-line minimum-digits maximum-digits
                    left-padding right-padding separator separator-fallback _)
    (unless (memq side sides)
      (raise-arguments-error 'odra-gutter-configuration
                             "side must be left or right" "side" side))
    (unless (and (exact-integer? order) (<= -32768 order 32767))
      (raise-arguments-error 'odra-gutter-configuration
                             "order must fit a signed 16-bit field" "order" order))
    (unless (memq mode modes)
      (raise-arguments-error 'odra-gutter-configuration
                             "unsupported numbering mode" "mode" mode))
    (unless (memq scope scopes)
      (raise-arguments-error 'odra-gutter-configuration
                             "unsupported numbering scope" "scope" scope))
    (unless (memq current-line current-line-presentations)
      (raise-arguments-error 'odra-gutter-configuration
                             "unsupported current-line presentation"
                             "current-line" current-line))
    (unless (and (exact-positive-integer? minimum-digits)
                 (exact-positive-integer? maximum-digits)
                 (<= minimum-digits maximum-digits 20))
      (raise-arguments-error 'odra-gutter-configuration
                             "digit bounds must satisfy 1 <= minimum <= maximum <= 20"
                             "minimum-digits" minimum-digits
                             "maximum-digits" maximum-digits))
    (unless (and (exact-nonnegative-integer? left-padding)
                 (exact-nonnegative-integer? right-padding)
                 (<= left-padding 255)
                 (<= right-padding 255))
      (raise-arguments-error 'odra-gutter-configuration
                             "padding must fit unsigned 8-bit fields"))
    (unless (and (bounded-representation? separator)
                 (bounded-representation? separator-fallback))
      (raise-arguments-error 'odra-gutter-configuration
                             "separator representations must be bounded display text"))
    (values visible? side order mode scope current-line minimum-digits maximum-digits
            left-padding right-padding
            (string->immutable-string separator)
            (string->immutable-string separator-fallback))))

(define factory-gutter-configuration
  (odra-gutter-configuration
   #t 'left 100 'absolute 'logical 'absolute 4 20 0 1 "│" "|"))

(define (gutter-configuration
         #:visible? [visible? #t]
         #:side [side 'left]
         #:order [order 100]
         #:mode [mode 'absolute]
         #:scope [scope 'logical]
         #:current-line [current-line 'absolute]
         #:minimum-digits [minimum-digits 4]
         #:maximum-digits [maximum-digits 20]
         #:left-padding [left-padding 0]
         #:right-padding [right-padding 1]
         #:separator [separator "│"]
         #:separator-fallback [separator-fallback "|"])
  (odra-gutter-configuration
   visible? side order mode scope current-line minimum-digits maximum-digits
   left-padding right-padding separator separator-fallback))

(define (normalize-gutter-configuration value)
  (cond
    [(not value) factory-gutter-configuration]
    [(odra-gutter-configuration? value) value]
    [(hash? value)
     (gutter-configuration
      #:visible? (hash-ref value 'visible? #t)
      #:side (hash-ref value 'side 'left)
      #:order (hash-ref value 'order 100)
      #:mode (hash-ref value 'mode 'absolute)
      #:scope (hash-ref value 'scope 'logical)
      #:current-line (hash-ref value 'current-line 'absolute)
      #:minimum-digits (hash-ref value 'minimum-digits 4)
      #:maximum-digits (hash-ref value 'maximum-digits 20)
      #:left-padding (hash-ref value 'left-padding 0)
      #:right-padding (hash-ref value 'right-padding 1)
      #:separator (hash-ref value 'separator "│")
      #:separator-fallback (hash-ref value 'separator-fallback "|"))]
    [else
     (raise-arguments-error 'normalize-gutter-configuration
                            "expected a Gutter configuration or hash"
                            "value" value)]))

(define (gutter-side-code configuration)
  (case (odra-gutter-configuration-side configuration)
    [(left) 1]
    [(right) 2]))

(define (gutter-mode-code configuration)
  (case (odra-gutter-configuration-mode configuration)
    [(none) 1]
    [(absolute) 2]
    [(relative) 3]
    [(hybrid) 4]))

(define (gutter-scope-code configuration)
  (case (odra-gutter-configuration-scope configuration)
    [(logical) 1]
    [(visual) 2]))

(define (gutter-current-line-code configuration)
  (case (odra-gutter-configuration-current-line configuration)
    [(absolute) 1]
    [(zero) 2]
    [(hidden) 3]))

(module+ test
  (require rackunit)

  (check-equal? (gutter-side-code factory-gutter-configuration) 1)
  (check-equal? (gutter-mode-code factory-gutter-configuration) 2)
  (check-equal? (gutter-scope-code factory-gutter-configuration) 1)
  (check-equal? (gutter-current-line-code factory-gutter-configuration) 1)
  (define configured
    (normalize-gutter-configuration
     '#hash((visible? . #f)
            (side . right)
            (order . -2)
            (mode . hybrid)
            (current-line . zero)
            (minimum-digits . 3)
            (maximum-digits . 12)
            (left-padding . 1)
            (right-padding . 2)
            (separator . "|")
            (separator-fallback . "|"))))
  (check-false (odra-gutter-configuration-visible? configured))
  (check-equal? (gutter-side-code configured) 2)
  (check-equal? (gutter-mode-code configured) 4)
  (check-equal? (odra-gutter-configuration-order configured) -2)
  (check-exn exn:fail?
             (lambda () (gutter-configuration #:minimum-digits 8 #:maximum-digits 4))))
