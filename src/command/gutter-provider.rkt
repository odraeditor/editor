#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list)

(provide
 (struct-out odra-gutter-lane)
 (struct-out odra-gutter-marker)
 (struct-out odra-gutter-provider)
 (contract-out
  [gutter-lane
   (->* (symbol?)
        (#:side symbol? #:order exact-integer? #:width symbol?
         #:minimum-cells exact-positive-integer?
         #:maximum-cells exact-positive-integer? #:alignment symbol?
         #:visibility symbol? #:collision symbol?
         #:priority exact-nonnegative-integer? #:style symbol?
         #:separator string? #:separator-fallback string?)
        odra-gutter-lane?)]
  [gutter-marker
   (->* (symbol? symbol? exact-positive-integer? string?)
        (#:fallback string? #:style symbol? #:priority exact-nonnegative-integer?
         #:aggregation string? #:detail string?
         #:actions (listof (or/c symbol? string?)) #:stale? boolean?)
        odra-gutter-marker?)]
  [gutter-provider
   (->* (string? symbol? (listof odra-gutter-lane?)
                (listof odra-gutter-marker?))
        (#:generation exact-positive-integer?
         #:marker-generation exact-positive-integer? #:complete? boolean?)
        odra-gutter-provider?)]))

(define maximum-lanes 1)
(define maximum-markers 256)
(define maximum-actions 4)
(define maximum-identity-bytes 64)
(define maximum-provider-name-bytes 128)
(define maximum-package-name-bytes 64)
(define maximum-command-name-bytes 128)
(define maximum-representation-bytes 64)
(define maximum-detail-bytes 512)
(define maximum-line (sub1 (expt 2 64)))
(define maximum-generation maximum-line)
(define machine-identity-pattern #px"^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$")
(define sides '(left right))
(define width-policies '(fixed automatic bounded-automatic content-presence))
(define alignments '(left center right))
(define visibility-policies '(always when-content configured))
(define collision-policies '(highest-priority stack aggregate primary-with-details))
(define style-roles
  '(ordinary background separator diagnostic-error diagnostic-warning
             diagnostic-information diagnostic-hint continuation clipping stale
             aggregate unavailable))

(define (machine-identity? value maximum)
  (and (symbol? value)
       (regexp-match? machine-identity-pattern (symbol->string value))
       (<= (bytes-length (string->bytes/utf-8 (symbol->string value))) maximum)))

(define (display-text? value maximum #:empty? [empty? #t])
  (and (string? value)
       (or empty? (positive? (string-length value)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)
       (for/and ([character (in-string value)])
         (define code (char->integer character))
         (not (or (< code 32) (<= 127 code 159))))))

(define (command-identity? value)
  (define symbol-value
    (cond [(symbol? value) value]
          [(string? value) (string->symbol value)]
          [else #f]))
  (and symbol-value (machine-identity? symbol-value maximum-command-name-bytes)))

(define (immutable-text value)
  (string->immutable-string value))

(struct odra-gutter-lane
  (identity side order width minimum-cells maximum-cells alignment visibility
            collision priority style separator separator-fallback)
  #:transparent
  #:guard
  (lambda (identity side order width minimum-cells maximum-cells alignment visibility
                    collision priority style separator separator-fallback _)
    (unless (machine-identity? identity maximum-identity-bytes)
      (raise-arguments-error 'odra-gutter-lane "invalid bounded lane identity"
                             "identity" identity))
    (unless (memq side sides)
      (raise-arguments-error 'odra-gutter-lane "side must be left or right" "side" side))
    (unless (and (exact-integer? order) (<= -32768 order 32767))
      (raise-arguments-error 'odra-gutter-lane "order must fit a signed 16-bit field"
                             "order" order))
    (unless (memq width width-policies)
      (raise-arguments-error 'odra-gutter-lane "unsupported width policy" "width" width))
    (unless (and (exact-positive-integer? minimum-cells)
                 (exact-positive-integer? maximum-cells)
                 (<= minimum-cells maximum-cells 64)
                 (or (not (eq? width 'fixed)) (= minimum-cells maximum-cells)))
      (raise-arguments-error 'odra-gutter-lane "invalid bounded cell width"))
    (unless (and (memq alignment alignments)
                 (memq visibility visibility-policies)
                 (memq collision collision-policies)
                 (memq style style-roles)
                 (exact-nonnegative-integer? priority)
                 (<= priority #xffff))
      (raise-arguments-error 'odra-gutter-lane "invalid lane presentation policy"))
    (unless (and (display-text? separator maximum-representation-bytes #:empty? #f)
                 (display-text? separator-fallback maximum-representation-bytes #:empty? #f))
      (raise-arguments-error 'odra-gutter-lane "invalid bounded separator representation"))
    (values identity side order width minimum-cells maximum-cells alignment visibility
            collision priority style (immutable-text separator)
            (immutable-text separator-fallback))))

(struct odra-gutter-marker
  (identity lane line value fallback style priority aggregation detail actions stale?)
  #:transparent
  #:guard
  (lambda (identity lane line value fallback style priority aggregation detail actions stale? _)
    (unless (and (machine-identity? identity maximum-identity-bytes)
                 (machine-identity? lane maximum-identity-bytes))
      (raise-arguments-error 'odra-gutter-marker "invalid bounded marker or lane identity"))
    (unless (and (exact-positive-integer? line) (<= line maximum-line))
      (raise-arguments-error 'odra-gutter-marker "line must be a positive 64-bit value"
                             "line" line))
    (unless (and (display-text? value maximum-representation-bytes #:empty? #f)
                 (display-text? fallback maximum-representation-bytes #:empty? #f)
                 (display-text? aggregation maximum-representation-bytes)
                 (display-text? detail maximum-detail-bytes))
      (raise-arguments-error 'odra-gutter-marker "invalid bounded marker text"))
    (unless (and (memq style style-roles)
                 (exact-nonnegative-integer? priority) (<= priority #xffff))
      (raise-arguments-error 'odra-gutter-marker "invalid marker style or priority"))
    (unless (and (list? actions) (<= (length actions) maximum-actions)
                 (andmap command-identity? actions))
      (raise-arguments-error 'odra-gutter-marker "actions must be bounded command identities"
                             "actions" actions))
    (values identity lane line (immutable-text value) (immutable-text fallback) style
            priority (immutable-text aggregation) (immutable-text detail)
            (map (lambda (action)
                   (immutable-text (if (symbol? action) (symbol->string action) action)))
                 actions)
            stale?)))

(struct odra-gutter-provider
  (name package generation marker-generation complete? lanes markers)
  #:transparent
  #:guard
  (lambda (name package generation marker-generation complete? lanes markers _)
    (unless (display-text? name maximum-provider-name-bytes #:empty? #f)
      (raise-arguments-error 'odra-gutter-provider "invalid bounded provider name" "name" name))
    (unless (machine-identity? package maximum-package-name-bytes)
      (raise-arguments-error 'odra-gutter-provider "invalid bounded package identity"
                             "package" package))
    (unless (and (exact-positive-integer? generation) (<= generation maximum-generation)
                 (exact-positive-integer? marker-generation)
                 (<= marker-generation maximum-generation))
      (raise-arguments-error 'odra-gutter-provider "invalid provider generation"))
    (unless (and complete? (list? lanes) (pair? lanes) (<= (length lanes) maximum-lanes)
                 (andmap odra-gutter-lane? lanes))
      (raise-arguments-error 'odra-gutter-provider "lanes must be a non-empty bounded list"))
    (unless (and (list? markers) (<= (length markers) maximum-markers)
                 (andmap odra-gutter-marker? markers))
      (raise-arguments-error 'odra-gutter-provider "markers must be a bounded list"))
    (define lane-identities (map odra-gutter-lane-identity lanes))
    (define marker-identities (map odra-gutter-marker-identity markers))
    (unless (= (length lane-identities) (length (remove-duplicates lane-identities)))
      (raise-arguments-error 'odra-gutter-provider "lane identities must be unique"))
    (unless (= (length marker-identities) (length (remove-duplicates marker-identities)))
      (raise-arguments-error 'odra-gutter-provider "marker identities must be unique"))
    (for ([marker (in-list markers)])
      (unless (memq (odra-gutter-marker-lane marker) lane-identities)
        (raise-arguments-error 'odra-gutter-provider "marker references an unknown lane"
                               "lane" (odra-gutter-marker-lane marker))))
    (values (immutable-text name) package generation marker-generation complete? lanes markers)))

;; gutter-lane constructs one immutable programmable lane declaration.
(define (gutter-lane identity
                     #:side [side 'right]
                     #:order [order 20]
                     #:width [width 'content-presence]
                     #:minimum-cells [minimum-cells 2]
                     #:maximum-cells [maximum-cells 2]
                     #:alignment [alignment 'center]
                     #:visibility [visibility 'when-content]
                     #:collision [collision 'highest-priority]
                     #:priority [priority 100]
                     #:style [style 'ordinary]
                     #:separator [separator "│"]
                     #:separator-fallback [separator-fallback "|"])
  (odra-gutter-lane identity side order width minimum-cells maximum-cells alignment
                    visibility collision priority style separator separator-fallback))

;; gutter-marker constructs one immutable one-based logical-line marker.
(define (gutter-marker identity lane line value
                       #:fallback [fallback "*"]
                       #:style [style 'ordinary]
                       #:priority [priority 0]
                       #:aggregation [aggregation ""]
                       #:detail [detail ""]
                       #:actions [actions '()]
                       #:stale? [stale? #f])
  (odra-gutter-marker identity lane line value fallback style priority aggregation detail
                      actions stale?))

;; gutter-provider constructs one complete replaceable personal provider generation.
(define (gutter-provider name package lanes markers
                         #:generation [generation 1]
                         #:marker-generation [marker-generation 1]
                         #:complete? [complete? #t])
  (odra-gutter-provider name package generation marker-generation complete? lanes markers))

(module+ test
  (require rackunit)

  (define notes-lane (gutter-lane 'notes))
  (define review-marker
    (gutter-marker 'review 'notes 5 "◆" #:fallback "*"
                   #:style 'diagnostic-information #:detail "Review this line"
                   #:actions '(gutter-inspect-markers)))
  (define provider
    (gutter-provider "Personal Notes" 'personal-notes
                     (list notes-lane) (list review-marker)))
  (check-equal? (odra-gutter-provider-package provider) 'personal-notes)
  (check-equal? (odra-gutter-marker-line review-marker) 5)
  (check-exn exn:fail? (lambda () (gutter-lane 'bad_lane)))
  (check-exn exn:fail?
             (lambda ()
               (gutter-provider "Unknown lane" 'bad-provider
                                (list notes-lane)
                                (list (gutter-marker 'bad 'missing 1 "!"))))))
