#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/list
         rackunit
         "inline-corpus.rkt"
         "structural-corpus.rkt")

(struct corpus-case (name source) #:transparent)
(struct splice (start end replacement removed) #:transparent)

(define (evidence-cases family cases)
  (append
   (for/list ([(evidence value) (in-hash cases)]
              #:when (string? value))
     (corpus-case (format "~a/~a" family evidence) value))
   (let ([availability (hash-ref cases 'availability #hasheq())])
     (for/list ([(suffix value) (in-hash availability)])
       (corpus-case (format "~a/availability/~a" family suffix) value)))))

(define generated-corpus
  (append
   (append-map
    (lambda (fixture)
      (evidence-cases
       (structural-fixture-family fixture)
       (structural-fixture-cases fixture)))
    structural-fixtures)
   (append-map
    (lambda (fixture)
      (evidence-cases
       (inline-fixture-family fixture)
       (inline-fixture-cases fixture)))
    inline-fixtures)))

(define (common-prefix-length left right)
  (let loop ([index 0])
    (if (and (< index (bytes-length left))
             (< index (bytes-length right))
             (= (bytes-ref left index) (bytes-ref right index)))
        (loop (add1 index))
        index)))

(define (common-suffix-length left right prefix-length)
  (let loop ([length 0])
    (define left-index (- (bytes-length left) length 1))
    (define right-index (- (bytes-length right) length 1))
    (if (and (>= left-index prefix-length)
             (>= right-index prefix-length)
             (= (bytes-ref left left-index) (bytes-ref right right-index)))
        (loop (add1 length))
        length)))

(define (minimal-splice original replacement)
  (and
   (not (bytes=? original replacement))
   (let* ([prefix-length (common-prefix-length original replacement)]
          [suffix-length
           (common-suffix-length original replacement prefix-length)])
     (splice
      prefix-length
      (- (bytes-length original) suffix-length)
      (subbytes replacement
                prefix-length
                (- (bytes-length replacement) suffix-length))
      (subbytes original
                prefix-length
                (- (bytes-length original) suffix-length))))))

(define (apply-splice source edit)
  (bytes-append
   (subbytes source 0 (splice-start edit))
   (splice-replacement edit)
   (subbytes source (splice-end edit))))

(define (inverse-splice edit)
  (splice
   (splice-start edit)
   (+ (splice-start edit) (bytes-length (splice-replacement edit)))
   (splice-removed edit)
   (splice-replacement edit)))

(define (edited-source source)
  (define character-index (quotient (string-length source) 2))
  (define prefix (string->bytes/utf-8 (substring source 0 character-index)))
  (define suffix (string->bytes/utf-8 (substring source character-index)))
  (bytes-append prefix #"!" suffix))

(define (write-exact path content)
  (call-with-output-file
   path
   #:exists 'truncate/replace
   (lambda (output) (write-bytes content output))))

;; Every generated structural and inline case preserves exact bytes through an
;; unchanged save, one minimal edit, close/reopen, undo, and redo sequence.
(test-case "complete corpus preserves source and minimal edit ranges"
  (check-equal?
   (remove-duplicates (map corpus-case-name generated-corpus))
   (map corpus-case-name generated-corpus))
  (for ([entry (in-list generated-corpus)])
    (define original (string->bytes/utf-8 (corpus-case-source entry)))
    (define edited (edited-source (corpus-case-source entry)))
    (define edit (minimal-splice original edited))
    (check-false (minimal-splice original original) (corpus-case-name entry))
    (check-not-false edit (corpus-case-name entry))
    (when edit
      (check-equal? (apply-splice original edit) edited (corpus-case-name entry))
      (check-equal?
       (subbytes original 0 (splice-start edit))
       (subbytes edited 0 (splice-start edit))
       (corpus-case-name entry))
      (check-equal?
       (subbytes original (splice-end edit))
       (subbytes edited (+ (splice-start edit)
                           (bytes-length (splice-replacement edit))))
       (corpus-case-name entry))
      (check-equal?
       (apply-splice edited (inverse-splice edit))
       original
       (corpus-case-name entry))
      (define path (make-temporary-file "odra-jan-preservation-~a"))
      (dynamic-wind
       void
       (lambda ()
         (write-exact path original)
         (check-equal? (file->bytes path) original (corpus-case-name entry))
         (write-exact path original)
         (check-equal? (file->bytes path) original (corpus-case-name entry))
         (write-exact path edited)
         (check-equal? (file->bytes path) edited (corpus-case-name entry))
         (write-exact path (apply-splice edited (inverse-splice edit)))
         (check-equal? (file->bytes path) original (corpus-case-name entry))
         (write-exact path (apply-splice original edit))
         (check-equal? (file->bytes path) edited (corpus-case-name entry)))
       (lambda ()
         (when (file-exists? path) (delete-file path)))))))
