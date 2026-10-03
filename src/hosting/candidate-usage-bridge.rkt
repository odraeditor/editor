#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/file
         racket/list
         "../project/candidate-usage.rkt")

(provide
 (contract-out
  [runtime-candidate-usage-load-batch (-> bytes? bytes? list?)]
  [runtime-candidate-usage-publish-batch (-> bytes? bytes? bytes? list?)]))

(define schema-version 1)
(define load-header-bytes 64)
(define entry-record-bytes 32)
(define publish-header-bytes 48)
(define publication-record-bytes 48)
(define maximum-copy-bytes (* 8 1024 1024))

(define category-codes
  '((command . 1) (document . 2) (project-file . 3) (project . 4) (workspace . 5)))
(define observation-codes '((absent . 1) (confirmed . 2) (rejected . 3) (unavailable . 4)))
(define publication-codes
  '((published-durable . 1)
    (published-recovered . 2)
    (published-durability-uncertain . 3)))

(define (word value)
  (integer->integer-bytes value 8 #f #f))

(define (words . values)
  (apply bytes-append (map word values)))

(define (read-word value offset)
  (integer-bytes->integer value #f #f offset (+ offset 8)))

(define (code table key who)
  (define found (assq key table))
  (unless found (error who "unsupported value: ~a" key))
  (cdr found))

(define (category-symbol value)
  (define found (findf (lambda (entry) (= (cdr entry) value)) category-codes))
  (unless found (error 'candidate-usage-publish-decode "unsupported category: ~a" value))
  (car found))

(define (utf8 value)
  (string->bytes/utf-8 value))

;; runtime-candidate-usage-load-batch returns one bounded all-or-nothing observation.
(define (runtime-candidate-usage-load-batch state-root-bytes project-id-bytes)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #"" (utf8 (exn-message failure))))])
    (define observation
      (candidate-usage-load
       (bytes->path state-root-bytes)
       (bytes->string/utf-8 project-id-bytes #f)))
    (list #t (candidate-usage-load-encode observation) #"")))

;; runtime-candidate-usage-publish-batch validates and publishes one exact native snapshot.
(define (runtime-candidate-usage-publish-batch
         state-root-bytes project-id-bytes request)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #"" (utf8 (exn-message failure))))])
    (define-values (record expected-generation)
      (candidate-usage-publish-decode
       request
       (bytes->string/utf-8 project-id-bytes #f)))
    (define result
      (candidate-usage-publish
       (bytes->path state-root-bytes)
       record
       #:expected-generation expected-generation))
    (cond
      [(odra-candidate-usage-publication? result)
       (list #t (candidate-usage-publication-encode result) #"")]
      [else
       (list #f #""
             (utf8 (odra-candidate-usage-persistence-failure-message result)))])))

(define (candidate-usage-load-encode observation)
  (define state (odra-candidate-usage-observation-state observation))
  (define record (odra-candidate-usage-observation-record observation))
  (define entries (if record (odra-candidate-usage-record-entries record) '()))
  (define-values (entry-bytes key-bytes) (candidate-usage-entries-encode entries))
  (define diagnostic
    (odra-candidate-usage-observation-diagnostic observation))
  (define diagnostic-bytes
    (if diagnostic (utf8 (odra-candidate-usage-diagnostic-message diagnostic)) #""))
  (define total
    (+ load-header-bytes (bytes-length entry-bytes)
       (bytes-length key-bytes) (bytes-length diagnostic-bytes)))
  (when (> total maximum-copy-bytes)
    (error 'candidate-usage-load-encode "candidate usage observation exceeds copied storage"))
  (bytes-append
   (words schema-version
          (code observation-codes state 'candidate-usage-load-encode)
          (if record (odra-candidate-usage-record-generation record) 0)
          (if record (odra-candidate-usage-record-next-sequence record) 1)
          (length entries)
          (bytes-length key-bytes)
          (bytes-length key-bytes)
          (bytes-length diagnostic-bytes))
   entry-bytes key-bytes diagnostic-bytes))

(define (candidate-usage-entries-encode entries)
  (define output (open-output-bytes))
  (define keys (open-output-bytes))
  (for ([entry (in-list entries)])
    (define key (utf8 (odra-candidate-usage-entry-key entry)))
    (define offset (file-position keys))
    (write-bytes key keys)
    (write-bytes
     (words (code category-codes
                  (odra-candidate-usage-entry-category entry)
                  'candidate-usage-entries-encode)
            offset
            (bytes-length key)
            (odra-candidate-usage-entry-sequence entry))
     output))
  (values (get-output-bytes output #t) (get-output-bytes keys #t)))

(define (candidate-usage-publish-decode request project-id)
  (unless (and (<= publish-header-bytes (bytes-length request))
               (<= (bytes-length request) maximum-copy-bytes))
    (error 'candidate-usage-publish-decode "invalid copied request width"))
  (define schema (read-word request 0))
  (define generation (read-word request 8))
  (define next-sequence (read-word request 16))
  (define entry-count (read-word request 24))
  (define key-byte-count (read-word request 32))
  (define expected-generation-word (read-word request 40))
  (unless (= schema schema-version)
    (error 'candidate-usage-publish-decode "unsupported copied request schema"))
  (unless (<= entry-count maximum-candidate-usage-entries)
    (error 'candidate-usage-publish-decode "candidate usage entry count exceeds limit"))
  (define entry-bytes (* entry-count entry-record-bytes))
  (define key-start (+ publish-header-bytes entry-bytes))
  (unless (= (bytes-length request) (+ key-start key-byte-count))
    (error 'candidate-usage-publish-decode "candidate usage request width does not match its header"))
  (define entries
    (for/list ([index (in-range entry-count)])
      (define offset (+ publish-header-bytes (* index entry-record-bytes)))
      (define category (category-symbol (read-word request offset)))
      (define key-offset (read-word request (+ offset 8)))
      (define key-length (read-word request (+ offset 16)))
      (define sequence (read-word request (+ offset 24)))
      (unless (and (<= key-offset key-byte-count)
                   (<= key-length (- key-byte-count key-offset)))
        (error 'candidate-usage-publish-decode "candidate usage key exceeds copied storage"))
      (odra-candidate-usage-entry
       category
       (bytes->string/utf-8
        request #f
        (+ key-start key-offset)
        (+ key-start key-offset key-length))
       sequence)))
  (values
   (odra-candidate-usage-record
    current-candidate-usage-format-version
    project-id
    generation
    next-sequence
    entries)
   (and (positive? expected-generation-word) expected-generation-word)))

(define (candidate-usage-publication-encode publication)
  (define encoded
    (words schema-version
           (code publication-codes
                 (odra-candidate-usage-publication-publication publication)
                 'candidate-usage-publication-encode)
           (odra-candidate-usage-publication-generation publication)
           (if (odra-candidate-usage-publication-file-synced? publication) 1 0)
           (if (odra-candidate-usage-publication-directory-synced? publication) 1 0)
           0))
  (unless (= (bytes-length encoded) publication-record-bytes)
    (error 'candidate-usage-publication-encode "invalid publication record width"))
  encoded)

(module+ test
  (require rackunit)

  (define sample
    (odra-candidate-usage-record
     1 "odra-development" 4 8
     (list
      (odra-candidate-usage-entry 'command "project-find-file" 7)
      (odra-candidate-usage-entry 'document "/tmp/alpha.odin" 5))))
  (define-values (sample-entry-bytes sample-key-bytes)
    (candidate-usage-entries-encode
     (odra-candidate-usage-record-entries sample)))
  (define sample-request
    (bytes-append
     (words 1 4 8 2 (bytes-length sample-key-bytes) 3)
     sample-entry-bytes sample-key-bytes))
  (define-values (decoded expected)
    (candidate-usage-publish-decode sample-request "odra-development"))
  (check-equal? decoded sample)
  (check-equal? expected 3)
  (check-exn exn:fail?
             (lambda ()
               (candidate-usage-publish-decode
                (bytes-append (words 2 1 2 0 0 0))
                "odra-development")))

  (define absent-root (make-temporary-file "odra-candidate-bridge~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define envelope
        (runtime-candidate-usage-load-batch
         (path->bytes absent-root) #"odra-development"))
      (check-true (car envelope))
      (check-equal? (read-word (cadr envelope) 8) 1))
    (lambda () (delete-directory/files absent-root))))
