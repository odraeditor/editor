#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "ksawery-extension.rkt")

(provide
 (struct-out ksawery-annotation-target-value)
 (struct-out ksawery-annotation-command-reference)
 (struct-out ksawery-annotation-value)
 (struct-out ksawery-annotation-proposal-value)
 (contract-out
  [make-ksawery-annotation-target
   (-> symbol? exact-positive-integer? bytes? ksawery-annotation-target-value?)]
  [make-ksawery-annotation-command-reference
   (-> (or/c symbol? string?) ksawery-annotation-command-reference?)]
  [make-ksawery-annotation
   (->* (exact-positive-integer? exact-positive-integer? (or/c symbol? string?)
                                 ksawery-annotation-target-value?)
        (#:label (or/c #f string?) #:detail string? #:severity symbol? #:style symbol?
         #:command (or/c #f ksawery-annotation-command-reference?))
        ksawery-annotation-value?)]
  [compose-ksawery-annotation-proposal
   (->* (ksawery-contributor? path-string? symbol?
                              exact-positive-integer? exact-positive-integer?
                              (listof ksawery-annotation-value?))
        (#:truncation symbol?)
        ksawery-annotation-proposal-value?)]
  [ksawery-annotation-proposal->datum
   (-> ksawery-annotation-proposal-value? hash?)]
  [decode-ksawery-annotation-proposal
   (-> hash? ksawery-annotation-proposal-value?)]
  [decode-ksawery-annotation-observation
   (-> bytes? hash?)]
  [encode-ksawery-annotation-proposal
   (-> ksawery-annotation-proposal-value? bytes?)]))

(define schema-version 1)
(define header-bytes 120)
(define annotation-record-bytes 152)
(define observation-header-bytes 64)
(define observation-target-record-bytes 40)
(define maximum-annotations 2048)
(define maximum-observation-targets 4096)
(define maximum-identity-bytes 96)
(define maximum-label-bytes 128)
(define maximum-detail-bytes 1024)
(define maximum-target-bytes 1280)
(define maximum-repository-bytes 4096)
(define maximum-proposal-bytes (* 4 1024 1024))
(define maximum-generation (sub1 (expt 2 64)))
(define identity-pattern #px"^[a-z][a-z0-9]*(?:[./-][a-z0-9]+)*$")
(define target-families
  '(path diff-unit revision revision-range ref remote conflict sequence process))
(define observation-families '(status history refs sequence conflict process))
(define severities '(none hint information warning error))
(define styles '(none normal muted identity active success warning alert information))
(define truncations '(complete annotation-limit text-limit provider-limit))
(define target-family-codes
  '((path . 1) (diff-unit . 2) (revision . 3) (revision-range . 4)
              (ref . 5) (remote . 6) (conflict . 7) (sequence . 8) (process . 9)))
(define observation-family-codes
  '((status . 0) (history . 1) (refs . 2) (sequence . 3)
                  (conflict . 4) (process . 5)))
(define severity-codes
  '((none . 0) (hint . 1) (information . 2) (warning . 3) (error . 4)))
(define style-codes
  '((none . 0) (normal . 1) (muted . 2) (identity . 3) (active . 4)
           (success . 5) (warning . 6) (alert . 7) (information . 8)))
(define truncation-codes
  '((complete . 1) (annotation-limit . 2) (text-limit . 3) (provider-limit . 4)))

(struct ksawery-annotation-target-value (family generation identity) #:transparent)
(struct ksawery-annotation-command-reference (identity) #:transparent)
(struct ksawery-annotation-value
  (id contribution identity target label detail severity style command) #:transparent)
(struct ksawery-annotation-proposal-value
  (contributor-identity contributor-generation generation repository
                        observation-family observation-generation annotations truncation)
  #:transparent)

;; make-ksawery-annotation-target copies one exact opaque semantic target identity.
(define (make-ksawery-annotation-target family generation identity)
  (check-member 'make-ksawery-annotation-target 'family family target-families)
  (validated-generation 'make-ksawery-annotation-target generation)
  (unless (and (positive? (bytes-length identity))
               (<= (bytes-length identity) maximum-target-bytes))
    (raise-arguments-error 'make-ksawery-annotation-target
                           "target identity must be non-empty and bounded"
                           "bytes" (bytes-length identity)))
  (ksawery-annotation-target-value
   family generation (bytes->immutable-bytes identity)))

;; make-ksawery-annotation-command-reference identifies one admitted semantic command.
(define (make-ksawery-annotation-command-reference identity)
  (ksawery-annotation-command-reference
   (validated-identity 'make-ksawery-annotation-command-reference identity)))

;; make-ksawery-annotation constructs one bounded provider-owned target projection.
(define (make-ksawery-annotation contribution id identity target
                                 #:label [label #f]
                                 #:detail [detail ""]
                                 #:severity [severity 'none]
                                 #:style [style 'none]
                                 #:command [command #f])
  (validated-generation 'make-ksawery-annotation contribution)
  (validated-generation 'make-ksawery-annotation id)
  (unless (ksawery-annotation-target-value? target)
    (raise-argument-error 'make-ksawery-annotation
                          "ksawery-annotation-target-value?" target))
  (when label
    (validated-text 'make-ksawery-annotation 'label label maximum-label-bytes #f))
  (define copied-detail
    (validated-text 'make-ksawery-annotation 'detail detail maximum-detail-bytes #t))
  (check-member 'make-ksawery-annotation 'severity severity severities)
  (check-member 'make-ksawery-annotation 'style style styles)
  (unless (or label (positive? (string-length copied-detail))
              (not (eq? severity 'none)) (not (eq? style 'none)) command)
    (raise-arguments-error 'make-ksawery-annotation
                           "annotation content cannot be empty"))
  (ksawery-annotation-value
   id contribution
   (validated-identity 'make-ksawery-annotation identity)
   target
   (and label (string->immutable-string label))
   copied-detail severity style command))

;; compose-ksawery-annotation-proposal validates and canonicalizes one whole generation.
(define (compose-ksawery-annotation-proposal contributor repository
                                             observation-family observation-generation
                                             generation annotations
                                             #:truncation [truncation 'complete])
  (validated-generation 'compose-ksawery-annotation-proposal observation-generation)
  (validated-generation 'compose-ksawery-annotation-proposal generation)
  (check-member 'compose-ksawery-annotation-proposal
                'observation-family observation-family observation-families)
  (check-member 'compose-ksawery-annotation-proposal 'truncation truncation truncations)
  (unless (and (list? annotations) (<= (length annotations) maximum-annotations)
               (andmap ksawery-annotation-value? annotations))
    (raise-arguments-error 'compose-ksawery-annotation-proposal
                           "annotations must be a bounded annotation list"))
  (define contributor-data (ksawery-contributor->datum contributor))
  (for ([annotation (in-list annotations)])
    (define contribution (ksawery-annotation-value-contribution annotation))
    (define declaration
      (for/first ([entry (in-list (hash-ref contributor-data 'contributions))]
                  #:when (= (hash-ref entry 'id) contribution))
        entry))
    (unless (and declaration (eq? (hash-ref declaration 'kind) 'annotation)
                 (memq observation-family (hash-ref declaration 'observations))
                 (memq 'inspect (hash-ref declaration 'authorities))
                 (memq 'present (hash-ref declaration 'authorities)))
      (raise-arguments-error 'compose-ksawery-annotation-proposal
                             "contribution does not admit annotations for this observation"
                             "contribution" contribution
                             "observation-family" observation-family))
    (unless (target-family-supports-observation?
             (ksawery-annotation-target-value-family
              (ksawery-annotation-value-target annotation))
             observation-family)
      (raise-arguments-error 'compose-ksawery-annotation-proposal
                             "target family is incompatible with the observation"
                             "target-family"
                             (ksawery-annotation-target-value-family
                              (ksawery-annotation-value-target annotation))))
    (unless (= (ksawery-annotation-target-value-generation
                (ksawery-annotation-value-target annotation))
               observation-generation)
      (raise-arguments-error 'compose-ksawery-annotation-proposal
                             "annotation target is stale")))
  (define ids (map ksawery-annotation-value-id annotations))
  (define identities (map ksawery-annotation-value-identity annotations))
  (unless (and (= (length ids) (length (remove-duplicates ids)))
               (= (length identities) (length (remove-duplicates identities))))
    (raise-arguments-error 'compose-ksawery-annotation-proposal
                           "annotation identities must be unique"))
  (define repository-text
    (if (path? repository) (path->string repository) repository))
  (validated-text 'compose-ksawery-annotation-proposal 'repository repository-text
                  maximum-repository-bytes #f)
  (define proposal
    (ksawery-annotation-proposal-value
     (hash-ref contributor-data 'identity)
     (hash-ref contributor-data 'generation)
     generation (string->immutable-string repository-text)
     observation-family observation-generation
     (sort annotations annotation<?) truncation))
  (encode-ksawery-annotation-proposal proposal)
  proposal)

;; ksawery-annotation-proposal->datum returns an immutable data-only proposal.
(define (ksawery-annotation-proposal->datum proposal)
  (hash
   'contributor-identity (ksawery-annotation-proposal-value-contributor-identity proposal)
   'contributor-generation (ksawery-annotation-proposal-value-contributor-generation proposal)
   'generation (ksawery-annotation-proposal-value-generation proposal)
   'repository (ksawery-annotation-proposal-value-repository proposal)
   'observation-family (ksawery-annotation-proposal-value-observation-family proposal)
   'observation-generation (ksawery-annotation-proposal-value-observation-generation proposal)
   'truncation (ksawery-annotation-proposal-value-truncation proposal)
   'annotations
   (for/list ([annotation (in-list
                           (ksawery-annotation-proposal-value-annotations proposal))])
     (define target (ksawery-annotation-value-target annotation))
     (hash
      'id (ksawery-annotation-value-id annotation)
      'contribution (ksawery-annotation-value-contribution annotation)
      'identity (ksawery-annotation-value-identity annotation)
      'target (hash 'family (ksawery-annotation-target-value-family target)
                    'generation (ksawery-annotation-target-value-generation target)
                    'identity (ksawery-annotation-target-value-identity target))
      'label (ksawery-annotation-value-label annotation)
      'detail (ksawery-annotation-value-detail annotation)
      'severity (ksawery-annotation-value-severity annotation)
      'style (ksawery-annotation-value-style annotation)
      'command (and (ksawery-annotation-value-command annotation)
                    (ksawery-annotation-command-reference-identity
                     (ksawery-annotation-value-command annotation)))))))

;; decode-ksawery-annotation-proposal validates a data-only proposal representation.
(define (decode-ksawery-annotation-proposal value)
  (unless (hash? value)
    (raise-argument-error 'decode-ksawery-annotation-proposal "hash?" value))
  (ksawery-annotation-proposal-value
   (validated-identity 'decode-ksawery-annotation-proposal
                       (hash-ref value 'contributor-identity))
   (validated-generation 'decode-ksawery-annotation-proposal
                         (hash-ref value 'contributor-generation))
   (validated-generation 'decode-ksawery-annotation-proposal
                         (hash-ref value 'generation))
   (validated-text 'decode-ksawery-annotation-proposal 'repository
                   (hash-ref value 'repository) maximum-repository-bytes #f)
   (validated-member 'decode-ksawery-annotation-proposal
                     (hash-ref value 'observation-family) observation-families)
   (validated-generation 'decode-ksawery-annotation-proposal
                         (hash-ref value 'observation-generation))
   (sort
    (for/list ([entry (in-list (hash-ref value 'annotations))])
      (define target (hash-ref entry 'target))
      (make-ksawery-annotation
       (hash-ref entry 'contribution)
       (hash-ref entry 'id)
       (hash-ref entry 'identity)
       (make-ksawery-annotation-target
        (hash-ref target 'family)
        (hash-ref target 'generation)
        (hash-ref target 'identity))
       #:label (hash-ref entry 'label #f)
       #:detail (hash-ref entry 'detail "")
       #:severity (hash-ref entry 'severity 'none)
       #:style (hash-ref entry 'style 'none)
       #:command
       (let ([command (hash-ref entry 'command #f)])
         (and command (make-ksawery-annotation-command-reference command)))))
    annotation<?)
   (validated-member 'decode-ksawery-annotation-proposal
                     (hash-ref value 'truncation) truncations)))

;; decode-ksawery-annotation-observation copies one native semantic target set.
(define (decode-ksawery-annotation-observation input)
  (unless (>= (bytes-length input) observation-header-bytes)
    (raise-arguments-error 'decode-ksawery-annotation-observation
                           "annotation observation header is incomplete"))
  (define schema (input-word input 0))
  (define total (input-word input 8))
  (define target-count (input-word input 16))
  (define family-code (input-word input 24))
  (define generation (input-word input 32))
  (define repository-offset (input-word input 40))
  (define repository-length (input-word input 48))
  (define reserved (input-word input 56))
  (define record-bytes
    (+ observation-header-bytes (* target-count observation-target-record-bytes)))
  (unless (and (= schema schema-version) (= total (bytes-length input))
               (<= target-count maximum-observation-targets) (<= record-bytes total)
               (zero? reserved))
    (raise-arguments-error 'decode-ksawery-annotation-observation
                           "annotation observation header is invalid"))
  (define observation-family
    (code-symbol 'decode-ksawery-annotation-observation
                 family-code observation-family-codes))
  (validated-generation 'decode-ksawery-annotation-observation generation)
  (define repository
    (bytes->string/utf-8
     (input-range input repository-offset repository-length record-bytes
                  maximum-repository-bytes #f)))
  (define targets
    (for/list ([index (in-range target-count)])
      (define base (+ observation-header-bytes
                      (* index observation-target-record-bytes)))
      (define family
        (code-symbol 'decode-ksawery-annotation-observation
                     (input-word input base) target-family-codes))
      (define target-generation (input-word input (+ base 8)))
      (define identity
        (input-range input
                     (input-word input (+ base 16))
                     (input-word input (+ base 24))
                     record-bytes maximum-target-bytes #f))
      (unless (zero? (input-word input (+ base 32)))
        (raise-arguments-error 'decode-ksawery-annotation-observation
                               "annotation target reserved field is nonzero"))
      (unless (and (= target-generation generation)
                   (target-family-supports-observation? family observation-family))
        (raise-arguments-error 'decode-ksawery-annotation-observation
                               "annotation target does not match its observation"))
      (make-ksawery-annotation-target family target-generation identity)))
  (hash 'repository (string->immutable-string repository)
        'family observation-family
        'generation generation
        'targets targets))

;; encode-ksawery-annotation-proposal copies one whole generation into fixed records.
(define (encode-ksawery-annotation-proposal proposal)
  (define annotations (ksawery-annotation-proposal-value-annotations proposal))
  (define text-start (+ header-bytes (* annotation-record-bytes (length annotations))))
  (define cursor text-start)
  (define trailing '())
  (define (append-bytes value #:empty? [empty? #f])
    (define range (if (and empty? (zero? (bytes-length value)))
                      '(0 0)
                      (list cursor (bytes-length value))))
    (unless (and empty? (zero? (bytes-length value)))
      (set! cursor (+ cursor (bytes-length value)))
      (set! trailing (cons value trailing)))
    range)
  (define (append-text value #:empty? [empty? #f])
    (append-bytes (string->bytes/utf-8 value) #:empty? empty?))
  (define repository-range
    (append-text (ksawery-annotation-proposal-value-repository proposal)))
  (define contributor-range
    (append-text (ksawery-annotation-proposal-value-contributor-identity proposal)))
  (define ranges
    (for/list ([annotation (in-list annotations)])
      (define target (ksawery-annotation-value-target annotation))
      (list
       (append-bytes (ksawery-annotation-target-value-identity target))
       (append-text (ksawery-annotation-value-identity annotation))
       (if (ksawery-annotation-value-label annotation)
           (append-text (ksawery-annotation-value-label annotation))
           '(0 0))
       (append-text (ksawery-annotation-value-detail annotation) #:empty? #t)
       (if (ksawery-annotation-value-command annotation)
           (append-text
            (ksawery-annotation-command-reference-identity
             (ksawery-annotation-value-command annotation)))
           '(0 0)))))
  (when (> cursor maximum-proposal-bytes)
    (error 'encode-ksawery-annotation-proposal
           "Ksawery annotation proposal exceeds copied storage"))
  (define records
    (for/list ([annotation (in-list annotations)] [entry (in-list ranges)])
      (define target (ksawery-annotation-value-target annotation))
      (define label? (and (ksawery-annotation-value-label annotation) #t))
      (define command? (and (ksawery-annotation-value-command annotation) #t))
      (words
       (append
        (list (ksawery-annotation-value-id annotation)
              (ksawery-annotation-value-contribution annotation)
              (symbol-code (ksawery-annotation-target-value-family target)
                           target-family-codes)
              (ksawery-annotation-target-value-generation target))
        (list-ref entry 0) (list-ref entry 1) (list-ref entry 2)
        (list-ref entry 3)
        (list (symbol-code (ksawery-annotation-value-severity annotation)
                           severity-codes)
              (symbol-code (ksawery-annotation-value-style annotation) style-codes))
        (list-ref entry 4)
        (list (+ (if label? 1 0) (if command? 2 0)) 0 0)))))
  (bytes-append
   (words
    (list schema-version cursor (length annotations)
          (ksawery-annotation-proposal-value-contributor-generation proposal)
          (ksawery-annotation-proposal-value-generation proposal)
          (symbol-code
           (ksawery-annotation-proposal-value-observation-family proposal)
           observation-family-codes)
          (ksawery-annotation-proposal-value-observation-generation proposal)
          (symbol-code (ksawery-annotation-proposal-value-truncation proposal)
                       truncation-codes)
          (car repository-range) (cadr repository-range)
          (car contributor-range) (cadr contributor-range) 0 0 0))
   (apply bytes-append records)
   (apply bytes-append (reverse trailing))))

(define (target-family-supports-observation? target observation)
  (case target
    [(path diff-unit) (eq? observation 'status)]
    [(revision revision-range) (eq? observation 'history)]
    [(ref remote) (eq? observation 'refs)]
    [(conflict) (memq observation '(conflict sequence))]
    [(sequence) (eq? observation 'sequence)]
    [(process) (eq? observation 'process)]
    [else #f]))

(define (annotation<? left right)
  (define left-target (ksawery-annotation-value-target left))
  (define right-target (ksawery-annotation-value-target right))
  (define left-family
    (symbol-code (ksawery-annotation-target-value-family left-target)
                 target-family-codes))
  (define right-family
    (symbol-code (ksawery-annotation-target-value-family right-target)
                 target-family-codes))
  (cond
    [(< left-family right-family) #t]
    [(> left-family right-family) #f]
    [(< (ksawery-annotation-target-value-generation left-target)
        (ksawery-annotation-target-value-generation right-target)) #t]
    [(> (ksawery-annotation-target-value-generation left-target)
        (ksawery-annotation-target-value-generation right-target)) #f]
    [(bytes-lexicographic<? (ksawery-annotation-target-value-identity left-target)
                            (ksawery-annotation-target-value-identity right-target)) #t]
    [(bytes=? (ksawery-annotation-target-value-identity left-target)
              (ksawery-annotation-target-value-identity right-target))
     (string<? (ksawery-annotation-value-identity left)
               (ksawery-annotation-value-identity right))]
    [else #f]))

(define (bytes-lexicographic<? left right)
  (let loop ([index 0])
    (cond
      [(= index (min (bytes-length left) (bytes-length right)))
       (< (bytes-length left) (bytes-length right))]
      [(< (bytes-ref left index) (bytes-ref right index)) #t]
      [(> (bytes-ref left index) (bytes-ref right index)) #f]
      [else (loop (add1 index))])))

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

(define (validated-member who value admitted)
  (check-member who 'value value admitted)
  value)

(define (check-member who field value admitted)
  (unless (memq value admitted)
    (raise-arguments-error who "value is outside the closed vocabulary" field value)))

(define (symbol-code value table)
  (define found (assq value table))
  (unless found (error 'encode-ksawery-annotation-proposal "unsupported value: ~a" value))
  (cdr found))

(define (code-symbol who value table)
  (define found (for/first ([entry (in-list table)] #:when (= (cdr entry) value)) entry))
  (unless found
    (raise-arguments-error who "numeric code is outside the closed vocabulary"
                           "code" value))
  (car found))

(define (input-word input offset)
  (unless (<= (+ offset 8) (bytes-length input))
    (raise-arguments-error 'decode-ksawery-annotation-observation
                           "word exceeds the copied observation"))
  (integer-bytes->integer input #f #f offset (+ offset 8)))

(define (input-range input offset length minimum-offset maximum empty?)
  (cond
    [(zero? length)
     (unless (and empty? (zero? offset))
       (raise-arguments-error 'decode-ksawery-annotation-observation
                              "empty range has an invalid offset"))
     #""]
    [(or (> length maximum) (< offset minimum-offset)
         (> offset (bytes-length input))
         (> length (- (bytes-length input) offset)))
     (raise-arguments-error 'decode-ksawery-annotation-observation
                            "range exceeds the copied observation")]
    [else (bytes->immutable-bytes (subbytes input offset (+ offset length)))]))

(define (word value)
  (integer->integer-bytes value 8 #f #f))

(define (words values)
  (apply bytes-append (map word values)))
