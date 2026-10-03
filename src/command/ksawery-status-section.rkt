#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "ksawery-extension.rkt")

(provide
 (struct-out ksawery-status-metadata-value)
 (struct-out ksawery-status-command-reference)
 (struct-out ksawery-status-item-value)
 (struct-out ksawery-status-section-value)
 (struct-out ksawery-status-proposal-value)
 (contract-out
  [make-ksawery-status-metadata
   (-> (or/c symbol? string?) string? ksawery-status-metadata-value?)]
  [make-ksawery-status-command-reference
   (-> (or/c symbol? string?) ksawery-status-command-reference?)]
  [make-ksawery-status-item
   (->* (exact-positive-integer? (or/c symbol? string?) string?)
        (#:detail string? #:style symbol?
         #:command (or/c #f ksawery-status-command-reference?)
         #:metadata (listof ksawery-status-metadata-value?))
        ksawery-status-item-value?)]
  [make-ksawery-status-section
   (->* (exact-positive-integer? (or/c symbol? string?) string?
                                 (listof ksawery-status-item-value?))
        (#:truncation symbol?)
        ksawery-status-section-value?)]
  [compose-ksawery-status-proposal
   (-> ksawery-contributor? path-string? exact-positive-integer?
       exact-positive-integer? (listof ksawery-status-section-value?)
       ksawery-status-proposal-value?)]
  [ksawery-status-proposal->datum
   (-> ksawery-status-proposal-value? hash?)]
  [decode-ksawery-status-proposal
   (-> hash? ksawery-status-proposal-value?)]
  [encode-ksawery-status-proposal
   (-> ksawery-status-proposal-value? bytes?)]))

(define schema-version 1)
(define header-bytes 104)
(define section-record-bytes 96)
(define item-record-bytes 128)
(define metadata-record-bytes 40)
(define maximum-sections 16)
(define maximum-items-per-section 256)
(define maximum-items 4096)
(define maximum-metadata-per-item 8)
(define maximum-metadata 16384)
(define maximum-identity-bytes 96)
(define maximum-label-bytes 128)
(define maximum-text-bytes 4096)
(define maximum-metadata-value-bytes 1024)
(define maximum-repository-bytes 4096)
(define maximum-proposal-bytes (* 4 1024 1024))
(define maximum-generation (sub1 (expt 2 64)))
(define identity-pattern #px"^[a-z][a-z0-9]*(?:[./-][a-z0-9]+)*$")
(define styles '(normal muted identity active success warning alert information))
(define truncations '(complete item-limit metadata-limit text-limit provider-limit))
(define style-codes
  '((normal . 1) (muted . 2) (identity . 3) (active . 4)
                 (success . 5) (warning . 6) (alert . 7) (information . 8)))
(define truncation-codes
  '((complete . 1) (item-limit . 2) (metadata-limit . 3)
                   (text-limit . 4) (provider-limit . 5)))

(struct ksawery-status-metadata-value (key value) #:transparent)
(struct ksawery-status-command-reference (identity) #:transparent)
(struct ksawery-status-item-value
  (id identity text detail style command metadata) #:transparent)
(struct ksawery-status-section-value
  (contribution identity label items truncation) #:transparent)
(struct ksawery-status-proposal-value
  (contributor-identity contributor-generation generation repository
                        observation-generation sections)
  #:transparent)

;; make-ksawery-status-metadata constructs one immutable public key and value.
(define (make-ksawery-status-metadata key value)
  (ksawery-status-metadata-value
   (validated-identity 'make-ksawery-status-metadata key)
   (validated-text 'make-ksawery-status-metadata 'value value
                   maximum-metadata-value-bytes #f)))

;; make-ksawery-status-command-reference identifies one admitted semantic command.
(define (make-ksawery-status-command-reference identity)
  (ksawery-status-command-reference
   (validated-identity 'make-ksawery-status-command-reference identity)))

;; make-ksawery-status-item constructs one bounded provider-owned semantic item.
(define (make-ksawery-status-item id identity text
                                  #:detail [detail ""]
                                  #:style [style 'normal]
                                  #:command [command #f]
                                  #:metadata [metadata '()])
  (unless (<= id maximum-generation)
    (raise-arguments-error 'make-ksawery-status-item "item identity exceeds 64 bits"))
  (unless (memq style styles)
    (raise-arguments-error 'make-ksawery-status-item
                           "style is not an admitted semantic role" "style" style))
  (unless (and (list? metadata)
               (<= (length metadata) maximum-metadata-per-item)
               (andmap ksawery-status-metadata-value? metadata))
    (raise-arguments-error 'make-ksawery-status-item
                           "metadata must be a bounded metadata list"))
  (define keys (map ksawery-status-metadata-value-key metadata))
  (unless (= (length keys) (length (remove-duplicates keys)))
    (raise-arguments-error 'make-ksawery-status-item "metadata keys must be unique"))
  (ksawery-status-item-value
   id
   (validated-identity 'make-ksawery-status-item identity)
   (validated-text 'make-ksawery-status-item 'text text maximum-text-bytes #f)
   (validated-text 'make-ksawery-status-item 'detail detail maximum-text-bytes #t)
   style command (map values metadata)))

;; make-ksawery-status-section constructs one complete immutable section result.
(define (make-ksawery-status-section contribution identity label items
                                      #:truncation [truncation 'complete])
  (unless (<= contribution maximum-generation)
    (raise-arguments-error 'make-ksawery-status-section
                           "contribution identity exceeds 64 bits"))
  (unless (and (list? items) (<= (length items) maximum-items-per-section)
               (andmap ksawery-status-item-value? items))
    (raise-arguments-error 'make-ksawery-status-section
                           "items must be a bounded Status item list"))
  (define ids (map ksawery-status-item-value-id items))
  (define identities (map ksawery-status-item-value-identity items))
  (unless (and (= (length ids) (length (remove-duplicates ids)))
               (= (length identities) (length (remove-duplicates identities))))
    (raise-arguments-error 'make-ksawery-status-section
                           "item identities must be unique within a section"))
  (unless (memq truncation truncations)
    (raise-arguments-error 'make-ksawery-status-section
                           "truncation is not an admitted state" "truncation" truncation))
  (ksawery-status-section-value
   contribution
   (validated-identity 'make-ksawery-status-section identity)
   (validated-text 'make-ksawery-status-section 'label label maximum-label-bytes #f)
   (map values items) truncation))

;; compose-ksawery-status-proposal validates and canonicalizes one whole generation.
(define (compose-ksawery-status-proposal contributor repository
                                         observation-generation generation sections)
  (unless (and (<= observation-generation maximum-generation)
               (<= generation maximum-generation))
    (raise-arguments-error 'compose-ksawery-status-proposal
                           "generation exceeds 64 bits"))
  (define contributor-data (ksawery-contributor->datum contributor))
  (define admitted-sections
    (for/hash ([entry (in-list (hash-ref contributor-data 'contributions))]
               #:when (eq? (hash-ref entry 'kind) 'status-section))
      (values (hash-ref entry 'id) #t)))
  (unless (and (list? sections) (<= (length sections) maximum-sections)
               (andmap ksawery-status-section-value? sections))
    (raise-arguments-error 'compose-ksawery-status-proposal
                           "sections must be a bounded Status section list"))
  (for ([section (in-list sections)])
    (unless (hash-ref admitted-sections
                      (ksawery-status-section-value-contribution section) #f)
      (raise-arguments-error 'compose-ksawery-status-proposal
                             "section does not reference a declared Status contribution"
                             "contribution"
                             (ksawery-status-section-value-contribution section))))
  (define identities (map ksawery-status-section-value-identity sections))
  (unless (= (length identities) (length (remove-duplicates identities)))
    (raise-arguments-error 'compose-ksawery-status-proposal
                           "section identities must be unique"))
  (define ordered
    (sort sections string<? #:key ksawery-status-section-value-identity))
  (define item-count
    (for/sum ([section (in-list ordered)])
      (length (ksawery-status-section-value-items section))))
  (define metadata-count
    (for*/sum ([section (in-list ordered)]
               [item (in-list (ksawery-status-section-value-items section))])
      (length (ksawery-status-item-value-metadata item))))
  (when (> item-count maximum-items)
    (raise-arguments-error 'compose-ksawery-status-proposal
                           "Status item count exceeds the generation limit"))
  (when (> metadata-count maximum-metadata)
    (raise-arguments-error 'compose-ksawery-status-proposal
                           "Status metadata count exceeds the generation limit"))
  (define repository-text
    (if (path? repository) (path->string repository) repository))
  (validated-text 'compose-ksawery-status-proposal 'repository repository-text
                  maximum-repository-bytes #f)
  (define proposal
    (ksawery-status-proposal-value
     (hash-ref contributor-data 'identity)
     (hash-ref contributor-data 'generation)
     generation
     (string->immutable-string repository-text)
     observation-generation
     ordered))
  (encode-ksawery-status-proposal proposal)
  proposal)

;; ksawery-status-proposal->datum returns an immutable data-only proposal.
(define (ksawery-status-proposal->datum proposal)
  (hash
   'contributor-identity (ksawery-status-proposal-value-contributor-identity proposal)
   'contributor-generation (ksawery-status-proposal-value-contributor-generation proposal)
   'generation (ksawery-status-proposal-value-generation proposal)
   'repository (ksawery-status-proposal-value-repository proposal)
   'observation-generation (ksawery-status-proposal-value-observation-generation proposal)
   'sections
   (for/list ([section (in-list (ksawery-status-proposal-value-sections proposal))])
     (hash
      'contribution (ksawery-status-section-value-contribution section)
      'identity (ksawery-status-section-value-identity section)
      'label (ksawery-status-section-value-label section)
      'truncation (ksawery-status-section-value-truncation section)
      'items
      (for/list ([item (in-list (ksawery-status-section-value-items section))])
        (hash
         'id (ksawery-status-item-value-id item)
         'identity (ksawery-status-item-value-identity item)
         'text (ksawery-status-item-value-text item)
         'detail (ksawery-status-item-value-detail item)
         'style (ksawery-status-item-value-style item)
         'command (and (ksawery-status-item-value-command item)
                       (ksawery-status-command-reference-identity
                        (ksawery-status-item-value-command item)))
         'metadata
         (for/list ([metadata (in-list (ksawery-status-item-value-metadata item))])
           (cons (ksawery-status-metadata-value-key metadata)
                 (ksawery-status-metadata-value-value metadata)))))))))

;; decode-ksawery-status-proposal validates a data-only proposal representation.
(define (decode-ksawery-status-proposal value)
  (unless (hash? value)
    (raise-argument-error 'decode-ksawery-status-proposal "hash?" value))
  (ksawery-status-proposal-value
   (validated-identity 'decode-ksawery-status-proposal
                       (hash-ref value 'contributor-identity))
   (validated-generation 'decode-ksawery-status-proposal
                         (hash-ref value 'contributor-generation))
   (validated-generation 'decode-ksawery-status-proposal
                         (hash-ref value 'generation))
   (validated-text 'decode-ksawery-status-proposal 'repository
                   (hash-ref value 'repository) maximum-repository-bytes #f)
   (validated-generation 'decode-ksawery-status-proposal
                         (hash-ref value 'observation-generation))
   (sort
    (for/list ([section (in-list (hash-ref value 'sections))])
      (make-ksawery-status-section
       (hash-ref section 'contribution)
       (hash-ref section 'identity)
       (hash-ref section 'label)
       (for/list ([item (in-list (hash-ref section 'items))])
         (make-ksawery-status-item
          (hash-ref item 'id) (hash-ref item 'identity) (hash-ref item 'text)
          #:detail (hash-ref item 'detail "")
          #:style (hash-ref item 'style 'normal)
          #:command
          (let ([command (hash-ref item 'command #f)])
            (and command (make-ksawery-status-command-reference command)))
          #:metadata
          (for/list ([metadata (in-list (hash-ref item 'metadata '()))])
            (make-ksawery-status-metadata (car metadata) (cdr metadata)))))
       #:truncation (hash-ref section 'truncation 'complete)))
    string<? #:key ksawery-status-section-value-identity)))

;; encode-ksawery-status-proposal copies one whole generation into fixed records.
(define (encode-ksawery-status-proposal proposal)
  (define sections (ksawery-status-proposal-value-sections proposal))
  (define items (append-map ksawery-status-section-value-items sections))
  (define metadata (append-map ksawery-status-item-value-metadata items))
  (define text-start
    (+ header-bytes (* section-record-bytes (length sections))
       (* item-record-bytes (length items))
       (* metadata-record-bytes (length metadata))))
  (define cursor text-start)
  (define trailing '())
  (define (append-text value #:empty? [empty? #f])
    (define bytes (string->bytes/utf-8 value))
    (define range (if (and empty? (zero? (bytes-length bytes)))
                      '(0 0)
                      (list cursor (bytes-length bytes))))
    (unless (and empty? (zero? (bytes-length bytes)))
      (set! cursor (+ cursor (bytes-length bytes)))
      (set! trailing (cons bytes trailing)))
    range)
  (define repository-range
    (append-text (ksawery-status-proposal-value-repository proposal)))
  (define contributor-range
    (append-text (ksawery-status-proposal-value-contributor-identity proposal)))
  (define section-ranges
    (for/list ([section (in-list sections)])
      (list (append-text (ksawery-status-section-value-identity section))
            (append-text (ksawery-status-section-value-label section)))))
  (define item-ranges
    (for/list ([item (in-list items)])
      (list
       (append-text (ksawery-status-item-value-identity item))
       (append-text (ksawery-status-item-value-text item))
       (append-text (ksawery-status-item-value-detail item) #:empty? #t)
       (if (ksawery-status-item-value-command item)
           (append-text
            (ksawery-status-command-reference-identity
             (ksawery-status-item-value-command item)))
           '(0 0)))))
  (define metadata-ranges
    (for/list ([entry (in-list metadata)])
      (list (append-text (ksawery-status-metadata-value-key entry))
            (append-text (ksawery-status-metadata-value-value entry)))))
  (when (> cursor maximum-proposal-bytes)
    (error 'encode-ksawery-status-proposal
           "Ksawery Status proposal exceeds copied storage"))
  (define section-records '())
  (define item-records '())
  (define metadata-records '())
  (define item-index 0)
  (define metadata-index 0)
  (for ([section (in-list sections)]
        [section-range (in-list section-ranges)]
        [section-index (in-naturals)])
    (define section-items (ksawery-status-section-value-items section))
    (set! section-records
          (cons
           (words
            (append
             (list (ksawery-status-section-value-contribution section)
                   section-index)
             (car section-range) (cadr section-range)
             (list item-index (length section-items)
                   (symbol-code (ksawery-status-section-value-truncation section)
                                truncation-codes)
                   (if (pair? section-items) 1 0) 0 0)))
           section-records))
    (for ([item (in-list section-items)])
      (define ranges (list-ref item-ranges item-index))
      (define item-metadata (ksawery-status-item-value-metadata item))
      (set! item-records
            (cons
             (words
              (append
               (list (ksawery-status-item-value-id item) section-index)
               (list-ref ranges 0) (list-ref ranges 1) (list-ref ranges 2)
               (list (symbol-code (ksawery-status-item-value-style item) style-codes)
                     (car (list-ref ranges 3)) (cadr (list-ref ranges 3))
                     metadata-index (length item-metadata) 0 0 0)))
             item-records))
      (for ([entry (in-list item-metadata)])
        (define ranges (list-ref metadata-ranges metadata-index))
        (set! metadata-records
              (cons (words (append (list item-index) (car ranges) (cadr ranges)))
                    metadata-records))
        (set! metadata-index (add1 metadata-index)))
      (set! item-index (add1 item-index))))
  (bytes-append
   (words
    (list schema-version cursor (length sections) (length items) (length metadata)
          1
          (ksawery-status-proposal-value-contributor-generation proposal)
          (ksawery-status-proposal-value-generation proposal)
          (ksawery-status-proposal-value-observation-generation proposal)
          (car repository-range) (cadr repository-range)
          (car contributor-range) (cadr contributor-range)))
   (apply bytes-append (reverse section-records))
   (apply bytes-append (reverse item-records))
   (apply bytes-append (reverse metadata-records))
   (apply bytes-append (reverse trailing))))

(define (validated-generation who value)
  (unless (and (exact-positive-integer? value) (<= value maximum-generation))
    (raise-argument-error who "positive 64-bit generation" value))
  value)

(define (validated-identity who value)
  (define text (if (symbol? value) (symbol->string value) value))
  (unless (and (string? text) (regexp-match? identity-pattern text)
               (<= (bytes-length (string->bytes/utf-8 text)) maximum-identity-bytes))
    (raise-argument-error who "bounded lowercase semantic identity" value))
  (string->immutable-string text))

(define (validated-text who field value maximum empty?)
  (unless (and (string? value) (or empty? (positive? (string-length value)))
               (<= (bytes-length (string->bytes/utf-8 value)) maximum)
               (for/and ([character (in-string value)])
                 (define code (char->integer character))
                 (not (or (< code 32) (<= 127 code 159)))))
    (raise-arguments-error who "invalid or oversized public text" field value))
  (string->immutable-string value))

(define (symbol-code value table)
  (define found (assq value table))
  (unless found (error 'encode-ksawery-status-proposal "unsupported value: ~a" value))
  (cdr found))

(define (word value)
  (integer->integer-bytes value 8 #f #f))

(define (words values)
  (apply bytes-append (map word values)))
