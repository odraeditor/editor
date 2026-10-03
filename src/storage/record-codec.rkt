#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/file
         racket/path
         racket/port
         racket/pretty
         racket/string)

(provide
 record-module-header
 maximum-record-module-bytes
 maximum-record-identity-bytes
 maximum-record-name-bytes
 maximum-record-path-bytes
 maximum-record-diagnostic-bytes
 (struct-out odra-record-diagnostic)
 (contract-out
  [record-identity? (-> any/c boolean?)]
  [record-name? (-> any/c boolean?)]
  [record-path? (-> any/c boolean?)]
  [record-u64? (-> any/c boolean?)]
  [record-copied-text (-> string? string?)]
  [record-datum->module-bytes (-> list? immutable-bytes?)]
  [record-module-parse
   (-> bytes? path-string? (-> any/c any/c)
       (or/c any/c odra-record-diagnostic?))]
  [record-module-load
   (-> path-string? (-> any/c any/c)
       (or/c any/c odra-record-diagnostic?))]))

(define record-module-header #"#lang odra/config\n")
(define maximum-record-module-bytes (* 4 1024 1024))
(define maximum-record-identity-bytes 128)
(define maximum-record-name-bytes 1024)
(define maximum-record-path-bytes 4096)
(define maximum-record-diagnostic-bytes 4096)
(define allowed-diagnostic-codes
  '(io record-size invalid-language invalid-encoding invalid-syntax
       invalid-schema unsupported-version))

(define (immutable-bytes? value)
  (and (bytes? value) (immutable? value)))

(define (record-u64? value)
  (and (exact-positive-integer? value) (<= value (sub1 (expt 2 64)))))

(define (bounded-text? value maximum)
  (and (string? value)
       (positive? (string-length value))
       (not (string-contains? value (string #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (record-identity? value)
  (and (bounded-text? value maximum-record-identity-bytes)
       (regexp-match? #px"^[a-z0-9]+(?:-[a-z0-9]+)*$" value)))

(define (record-name? value)
  (bounded-text? value maximum-record-name-bytes))

(define (record-path? value)
  (and (bounded-text? value maximum-record-path-bytes)
       (absolute-path? (string->path value))))

(define (record-copied-text value)
  (string->immutable-string value))

(struct odra-record-diagnostic (code message source limit actual)
  #:transparent
  #:guard
  (lambda (code message source limit actual _)
    (unless (and (memq code allowed-diagnostic-codes)
                 (string? message)
                 (<= (bytes-length (string->bytes/utf-8 message))
                     maximum-record-diagnostic-bytes)
                 (string? source)
                 (exact-nonnegative-integer? limit)
                 (exact-nonnegative-integer? actual))
      (raise-arguments-error 'odra-record-diagnostic
                             "invalid bounded record diagnostic"))
    (values code
            (record-copied-text message)
            (record-copied-text source)
            limit
            actual)))

;; record-datum->module-bytes emits one deterministic closed record form.
(define (record-datum->module-bytes datum)
  (define output (open-output-bytes))
  (write-bytes record-module-header output)
  (pretty-write datum output)
  (bytes->immutable-bytes (get-output-bytes output)))

;; record-module-parse reads one datum and delegates exact schema decoding.
(define (record-module-parse module-bytes source decode)
  (define source-text (path-source source))
  (cond
    [(> (bytes-length module-bytes) maximum-record-module-bytes)
     (diagnostic 'record-size
                 "Record exceeds the module byte limit"
                 source-text
                 maximum-record-module-bytes
                 (bytes-length module-bytes))]
    [(not (bytes-prefix? module-bytes record-module-header))
     (diagnostic 'invalid-language
                 "Record must begin with #lang odra/config"
                 source-text)]
    [else
     (define body-bytes
       (subbytes module-bytes (bytes-length record-module-header)))
     (define body
       (with-handlers ([exn:fail?
                        (lambda (failure)
                          (diagnostic 'invalid-encoding
                                      (exn-message failure)
                                      source-text))])
         (bytes->string/utf-8 body-bytes #f)))
     (if (odra-record-diagnostic? body)
         body
         (parse-body body source-text decode))]))

;; record-module-load bounds a file before and during copied reading.
(define (record-module-load path decode)
  (define source (path-source path))
  (with-handlers ([exn:fail:filesystem?
                   (lambda (failure)
                     (diagnostic 'io (exn-message failure) source))])
    (define observed-size (file-size path))
    (if (> observed-size maximum-record-module-bytes)
        (diagnostic 'record-size
                    "Record exceeds the module byte limit"
                    source
                    maximum-record-module-bytes
                    observed-size)
        (call-with-input-file path
          (lambda (input)
            (define bytes (read-bytes (add1 maximum-record-module-bytes) input))
            (record-module-parse
             (if (eof-object? bytes) #"" bytes)
             source
             decode))
          #:mode 'binary))))

(define (parse-body body source decode)
  (with-handlers ([exn:fail:read?
                   (lambda (failure)
                     (diagnostic 'invalid-syntax (exn-message failure) source))]
                  [exn:fail?
                   (lambda (failure)
                     (diagnostic 'invalid-schema (exn-message failure) source))])
    (define input (open-input-string body source))
    (parameterize ([read-accept-reader #f]
                   [read-accept-lang #f])
      (define datum (read input))
      (when (eof-object? datum)
        (raise-arguments-error 'odra-record "missing record form"))
      (unless (eof-object? (read input))
        (raise-arguments-error 'odra-record "multiple record forms"))
      (decode datum))))

(define (bytes-prefix? bytes prefix)
  (and (>= (bytes-length bytes) (bytes-length prefix))
       (bytes=? (subbytes bytes 0 (bytes-length prefix)) prefix)))

(define (path-source source)
  (cond
    [(path? source) (path->string source)]
    [(string? source) source]
    [else (format "~a" source)]))

(define (diagnostic code message source [limit 0] [actual 0])
  (odra-record-diagnostic
   code
   (bounded-message message)
   source
   limit
   actual))

(define (bounded-message message)
  (define bytes (string->bytes/utf-8 message))
  (if (<= (bytes-length bytes) maximum-record-diagnostic-bytes)
      message
      (bytes->string/utf-8
       (subbytes bytes 0 maximum-record-diagnostic-bytes)
       #\uFFFD)))
