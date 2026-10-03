#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

(require (only-in file/sha1 bytes->hex-string)
         json
         racket/contract
         racket/list
         racket/port)

(provide
 (contract-out
  [jsexpr->canonical-bytes (-> jsexpr? bytes?)]
  [jsexpr-sha256 (-> jsexpr? string?)]
  [bytes-sha256 (-> bytes? string?)]
  [file-sha256 (-> path-string? string?)]
  [read-json-file (-> path-string? jsexpr?)]))

(define (json-key->string key)
  (cond
    [(symbol? key) (symbol->string key)]
    [(string? key) key]
    [else
     (raise-arguments-error 'jsexpr->canonical-bytes
                            "JSON object key is not a symbol or string"
                            "key" key)]))

(define (normalized-object-entries value)
  (define entries
    (sort
     (for/list ([(key item) (in-hash value)])
       (cons (json-key->string key) item))
     string<?
     #:key car))
  (when (pair? entries)
    (for ([left (in-list entries)]
          [right (in-list (cdr entries))])
      (when (string=? (car left) (car right))
        (raise-arguments-error 'jsexpr->canonical-bytes
                               "JSON object has duplicate normalized keys"
                               "key" (car left)))))
  entries)

(define (write-canonical-json value output)
  (cond
    [(hash? value)
     (write-byte (char->integer #\{) output)
     (for ([entry (in-list (normalized-object-entries value))]
           [index (in-naturals)])
       (unless (zero? index)
         (write-byte (char->integer #\,) output))
       (write-json (car entry) output)
       (write-byte (char->integer #\:) output)
       (write-canonical-json (cdr entry) output))
     (write-byte (char->integer #\}) output)]
    [(list? value)
     (write-byte (char->integer #\[) output)
     (for ([item (in-list value)]
           [index (in-naturals)])
       (unless (zero? index)
         (write-byte (char->integer #\,) output))
       (write-canonical-json item output))
     (write-byte (char->integer #\]) output)]
    [(or (string? value) (boolean? value) (eq? value 'null))
     (write-json value output)]
    [(exact-integer? value)
     (display value output)]
    [else
     (raise-arguments-error 'jsexpr->canonical-bytes
                            "unsupported canonical JSON value"
                            "value" value)]))

(define (jsexpr->canonical-bytes value)
  (call-with-output-bytes
   (lambda (output)
     (write-canonical-json value output))))

(define (bytes-sha256 value)
  (bytes->hex-string
   (sha256-bytes (open-input-bytes value))))

(define (jsexpr-sha256 value)
  (bytes-sha256 (jsexpr->canonical-bytes value)))

(define (file-sha256 path)
  (call-with-input-file path
    (lambda (input)
      (bytes->hex-string (sha256-bytes input)))
    #:mode 'binary))

(define (read-json-file path)
  (call-with-input-file path read-json))
