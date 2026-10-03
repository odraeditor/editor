#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/match
         racket/string
         "../storage/record-codec.rkt")

(provide
 current-saved-state-format-version
 maximum-saved-entries
 maximum-named-slots
 maximum-named-entry-text-bytes
 maximum-named-entry-aggregate-text-bytes
 maximum-named-location-name-bytes
 maximum-named-location-summary-bytes
 maximum-named-layout-nodes
 maximum-named-layout-depth
 (struct-out odra-named-location)
 (struct-out odra-named-position)
 (struct-out odra-named-layout-node)
 (struct-out odra-named-layout)
 (struct-out odra-named-slot)
 (struct-out odra-saved-state-record)
 (contract-out
  [named-location
   (-> #:name string?
       #:target string?
       #:point exact-nonnegative-integer?
       #:mark (or/c #f exact-nonnegative-integer?)
       #:region-active? boolean?
       #:summary string?
       odra-named-location?)]
  [named-position
   (-> #:target string?
       #:point exact-nonnegative-integer?
       #:summary string?
       odra-named-position?)]
  [named-layout-node
   (-> #:kind (or/c 'partition 'pane)
       #:arrangement (or/c #f 'above-below 'left-right)
       #:target string?
       #:selected? boolean?
       #:dedication (or/c 'none 'soft 'hard)
       odra-named-layout-node?)]
  [named-layout (-> #:nodes (listof odra-named-layout-node?) odra-named-layout?)]
  [named-slot
   (-> #:name string?
       #:kind (or/c 'integer 'text 'position 'layout)
       #:value any/c
       odra-named-slot?)]
  [saved-state-record
   (-> #:format-version exact-positive-integer?
       #:generation exact-positive-integer?
       #:locations (listof odra-named-location?)
       #:slots (listof odra-named-slot?)
       odra-saved-state-record?)]
  [saved-state-record->module-bytes
   (-> odra-saved-state-record? immutable-bytes?)]
  [saved-state-record-module-load
   (-> path-string? (or/c odra-saved-state-record?
                          odra-record-diagnostic?))]))

(define current-saved-state-format-version 2)
(define maximum-saved-entries 256)
(define maximum-named-slots 256)
(define maximum-named-entry-text-bytes (* 64 1024))
(define maximum-named-entry-aggregate-text-bytes (* 1024 1024))
(define maximum-named-location-name-bytes 256)
(define maximum-named-location-summary-bytes 512)
(define maximum-named-layout-nodes 255)
(define maximum-named-layout-depth 32)

(define (immutable-bytes? value)
  (and (bytes? value) (immutable? value)))

(define (location-offset? value)
  (and (exact-nonnegative-integer? value)
       (<= value (sub1 (expt 2 64)))))

(define (bounded-text? value maximum #:empty? [empty? #f])
  (and (string? value)
       (or empty? (positive? (string-length value)))
       (not (string-contains? value (string #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (named-location-name? value)
  (bounded-text? value maximum-named-location-name-bytes))

(define (named-location-summary? value)
  (bounded-text? value maximum-named-location-summary-bytes))

(define (named-entry-text? value)
  (bounded-text? value maximum-named-entry-text-bytes #:empty? #t))

(define (normalize-name name)
  (string->immutable-string (string-normalize-nfc (string-trim name))))

(struct odra-named-location (name target point mark region-active? summary)
  #:transparent
  #:guard
  (lambda (name target point mark region-active? summary _)
    (define normalized-name (normalize-name name))
    (unless (and (named-location-name? normalized-name)
                 (record-path? target)
                 (location-offset? point)
                 (or (not mark) (location-offset? mark))
                 (boolean? region-active?)
                 (or (not region-active?) mark)
                 (named-location-summary? summary))
      (raise-arguments-error 'named-location "invalid named location"))
    (values normalized-name
            (record-copied-text target)
            point
            mark
            region-active?
            (record-copied-text summary))))

(struct odra-named-position (target point summary)
  #:transparent
  #:guard
  (lambda (target point summary _)
    (unless (and (record-path? target)
                 (location-offset? point)
                 (named-location-summary? summary))
      (raise-arguments-error 'named-position "invalid named position"))
    (values (record-copied-text target) point (record-copied-text summary))))

(struct odra-named-layout-node (kind arrangement target selected? dedication)
  #:transparent
  #:guard
  (lambda (kind arrangement target selected? dedication _)
    (unless
        (or (and (eq? kind 'partition)
                 (memq arrangement '(above-below left-right))
                 (string=? target "")
                 (not selected?)
                 (eq? dedication 'none))
            (and (eq? kind 'pane)
                 (not arrangement)
                 (record-path? target)
                 (boolean? selected?)
                 (memq dedication '(none soft hard))))
      (raise-arguments-error 'named-layout-node "invalid named layout node"))
    (values kind arrangement (record-copied-text target) selected? dedication)))

(define (named-layout-next-index nodes index depth)
  (when (or (>= index (length nodes)) (> depth maximum-named-layout-depth))
    (raise-arguments-error 'named-layout "invalid named layout topology"))
  (define node (list-ref nodes index))
  (if (eq? (odra-named-layout-node-kind node) 'pane)
      (add1 index)
      (named-layout-next-index
       nodes
       (named-layout-next-index nodes (add1 index) (add1 depth))
       (add1 depth))))

(struct odra-named-layout (nodes)
  #:transparent
  #:guard
  (lambda (nodes _)
    (unless (and (list? nodes)
                 (positive? (length nodes))
                 (<= (length nodes) maximum-named-layout-nodes)
                 (andmap odra-named-layout-node? nodes)
                 (= (for/sum ([node (in-list nodes)])
                      (if (odra-named-layout-node-selected? node) 1 0))
                    1)
                 (= (named-layout-next-index nodes 0 0) (length nodes)))
      (raise-arguments-error 'named-layout "invalid named layout"))
    (values (for/list ([node (in-list nodes)]) node))))

(struct odra-named-slot (name kind value)
  #:transparent
  #:guard
  (lambda (name kind value _)
    (define normalized-name (normalize-name name))
    (unless (and (named-location-name? normalized-name)
                 (or (and (eq? kind 'integer)
                          (exact-integer? value)
                          (<= (- (expt 2 63)) value (sub1 (expt 2 63))))
                     (and (eq? kind 'text) (named-entry-text? value))
                     (and (eq? kind 'position) (odra-named-position? value))
                     (and (eq? kind 'layout) (odra-named-layout? value))))
      (raise-arguments-error 'named-slot "invalid named slot"))
    (values normalized-name kind
            (if (eq? kind 'text) (record-copied-text value) value))))

(struct odra-saved-state-record (format-version generation locations slots)
  #:transparent
  #:guard
  (lambda (format-version generation locations slots _)
    (unless (and (exact-positive-integer? format-version)
                 (<= format-version current-saved-state-format-version)
                 (or (> format-version 1) (null? slots)))
      (raise-arguments-error 'saved-state-record
                             "unsupported named locations format"))
    (unless (and (record-u64? generation)
                 (list? locations)
                 (list? slots)
                 (<= (+ (length locations) (length slots)) maximum-saved-entries)
                 (<= (length slots) maximum-named-slots)
                 (andmap odra-named-location? locations)
                 (andmap odra-named-slot? slots)
                 (<= (for/sum ([slot (in-list slots)]
                               #:when (eq? (odra-named-slot-kind slot) 'text))
                       (bytes-length (string->bytes/utf-8 (odra-named-slot-value slot))))
                     maximum-named-entry-aggregate-text-bytes))
      (raise-arguments-error 'saved-state-record "invalid saved-state record"))
    (define location-names (map odra-named-location-name locations))
    (define slot-names (map odra-named-slot-name slots))
    (define names (append location-names slot-names))
    (unless (and (= (length names) (length (remove-duplicates names)))
                 (equal? location-names (sort location-names string<?))
                 (equal? slot-names (sort slot-names string<?)))
      (raise-arguments-error 'saved-state-record
                             "named entries must have unique sorted names"))
    (values format-version
            generation
            (for/list ([location (in-list locations)]) location)
            (for/list ([slot (in-list slots)]) slot))))

(define (named-location #:name name #:target target #:point point #:mark mark
                        #:region-active? region-active? #:summary summary)
  (odra-named-location name target point mark region-active? summary))

(define (named-position #:target target #:point point #:summary summary)
  (odra-named-position target point summary))

(define (named-layout-node #:kind kind #:arrangement arrangement #:target target
                           #:selected? selected? #:dedication dedication)
  (odra-named-layout-node kind arrangement target selected? dedication))

(define (named-layout #:nodes nodes)
  (odra-named-layout nodes))

(define (named-slot #:name name #:kind kind #:value value)
  (odra-named-slot name kind value))

(define (saved-state-record #:format-version format-version
                                #:generation generation
                                #:locations locations
                                #:slots slots)
  (odra-saved-state-record format-version generation locations slots))

(define (saved-state-record->module-bytes record)
  (record-datum->module-bytes
   (list 'named-locations
         '#:format-version (odra-saved-state-record-format-version record)
         '#:generation (odra-saved-state-record-generation record)
         '#:locations
         (for/list ([location (in-list (odra-saved-state-record-locations record))])
           (list 'named-location
                 '#:name (odra-named-location-name location)
                 '#:target (odra-named-location-target location)
                 '#:point (odra-named-location-point location)
                 '#:mark (odra-named-location-mark location)
                 '#:region-active? (odra-named-location-region-active? location)
                 '#:summary (odra-named-location-summary location)))
         '#:slots
         (for/list ([slot (in-list (odra-saved-state-record-slots record))])
           (list 'named-slot
                 '#:name (odra-named-slot-name slot)
                 '#:kind (odra-named-slot-kind slot)
                 '#:value (encode-slot-value slot))))))

(define (encode-slot-value slot)
  (case (odra-named-slot-kind slot)
    [(position)
     (define position (odra-named-slot-value slot))
     (list 'named-position
           '#:target (odra-named-position-target position)
           '#:point (odra-named-position-point position)
           '#:summary (odra-named-position-summary position))]
    [(layout) (encode-layout (odra-named-slot-value slot))]
    [else (odra-named-slot-value slot)]))

(define (encode-layout layout)
  (list
   'named-layout
   '#:nodes
   (for/list ([node (in-list (odra-named-layout-nodes layout))])
     (list 'layout-node
           '#:kind (odra-named-layout-node-kind node)
           '#:arrangement (odra-named-layout-node-arrangement node)
           '#:target (odra-named-layout-node-target node)
           '#:selected? (odra-named-layout-node-selected? node)
           '#:dedication (odra-named-layout-node-dedication node)))))

(define (saved-state-record-module-load path)
  (record-module-load path decode-named-locations))

(define (decode-named-locations datum)
  (match datum
    [(list 'named-locations '#:format-version 1 '#:generation generation
           '#:locations locations)
     (saved-state-record #:format-version 1 #:generation generation
                             #:locations (map decode-named-location locations)
                             #:slots '())]
    [(list 'named-locations '#:format-version format-version '#:generation generation
           '#:locations locations '#:slots slots)
     (saved-state-record #:format-version format-version #:generation generation
                             #:locations (map decode-named-location locations)
                             #:slots (map decode-named-slot slots))]
    [_ (raise-arguments-error 'saved-state-record "invalid closed record shape")]))

(define (decode-named-location datum)
  (match datum
    [(list 'named-location '#:name name '#:target target '#:point point
           '#:mark mark '#:region-active? region-active? '#:summary summary)
     (named-location #:name name #:target target #:point point #:mark mark
                     #:region-active? region-active? #:summary summary)]
    [_ (raise-arguments-error 'named-location "invalid closed record shape")]))

(define (decode-named-slot datum)
  (match datum
    [(list 'named-slot '#:name name '#:kind kind '#:value value)
     (named-slot #:name name #:kind kind
                 #:value (case kind
                           [(position) (decode-position value)]
                           [(layout) (decode-layout value)]
                           [else value]))]
    [_ (raise-arguments-error 'named-slot "invalid closed slot shape")]))

(define (decode-position datum)
  (match datum
    [(list 'named-position '#:target target '#:point point '#:summary summary)
     (named-position #:target target #:point point #:summary summary)]
    [_ (raise-arguments-error 'named-position "invalid closed position shape")]))

(define (decode-layout datum)
  (match datum
    [(list 'named-layout '#:nodes nodes)
     (named-layout #:nodes (map decode-layout-node nodes))]
    [_ (raise-arguments-error 'named-layout "invalid closed layout shape")]))

(define (decode-layout-node datum)
  (match datum
    [(list 'layout-node '#:kind kind '#:arrangement arrangement '#:target target
           '#:selected? selected? '#:dedication dedication)
     (named-layout-node #:kind kind #:arrangement arrangement #:target target
                        #:selected? selected? #:dedication dedication)]
    [_ (raise-arguments-error 'named-layout-node "invalid closed layout node shape")]))

(module+ test
  (require rackunit)

  (define location
    (named-location #:name "  Café  " #:target "/tmp/first.odin" #:point 0
                    #:mark #f #:region-active? #f #:summary "first.odin"))
  (define record
    (saved-state-record
     #:format-version current-saved-state-format-version
     #:generation 1
     #:locations (list location)
     #:slots (list (named-slot #:name "counter" #:kind 'integer #:value 3))))
  (check-equal? (odra-named-location-name location) "Café")
  (check-equal?
   (record-module-parse
    (saved-state-record->module-bytes record)
    "/tmp/named-locations.rkt"
    decode-named-locations)
   record))
