#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require json
         racket/match)

(define (read-frame)
  (define content-length #f)
  (let loop ()
    (define line (read-line (current-input-port) 'any))
    (cond
      [(eof-object? line) #f]
      [(string=? line "")
       (and content-length (read-bytes content-length))]
      [else
       (match (regexp-match #rx"(?i:^Content-Length:[ ]*([0-9]+)$)" line)
         [(list _ length-text)
          (set! content-length (string->number length-text))]
         [_ (void)])
       (loop)])))

(define (write-message value)
  (define body (jsexpr->bytes value))
  (fprintf (current-output-port) "Content-Length: ~a\r\n\r\n" (bytes-length body))
  (write-bytes body)
  (flush-output))

(let loop ()
  (define body (read-frame))
  (when body
    (define message (bytes->jsexpr body))
    (define method (hash-ref message 'method #f))
    (define id (hash-ref message 'id #f))
    (cond
      [(equal? method "initialize")
       (write-message
        (hasheq
         'jsonrpc "2.0"
         'id id
         'result
         (hasheq
          'capabilities
          (hasheq
           'positionEncoding "utf-16"
           'textDocumentSync 1
           'completionProvider (hasheq 'triggerCharacters '("."))))))]
      [(equal? method "textDocument/completion")
       (write-message
        (hasheq
         'jsonrpc "2.0"
         'id id
         'result
         (list (hasheq 'label "quillValue" 'kind 6 'detail "External fixture"))))]
      [(equal? method "shutdown")
       (write-message (hasheq 'jsonrpc "2.0" 'id id 'result 'null))]
      [else (void)])
    (unless (equal? method "exit") (loop))))
