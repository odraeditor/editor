#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require json
         rackunit
         racket/file
         racket/port
         racket/string
         racket/system)

(define expected-checksum
  (or (getenv "RACKET_LANGSERVER_CHECKSUM")
      "93efe35dcc07a7cc86c958f00497280744f0e75c"))

(define-values (show-status show-output show-input show-error)
  (subprocess #f #f #f
              (find-executable-path "raco")
              "pkg" "show" "--all" "--long" "--full-checksum"
              "racket-langserver"))
(close-output-port show-input)
(subprocess-wait show-status)
(define installed-description (port->string show-output))
(close-input-port show-output)
(close-input-port show-error)
(check-equal? (subprocess-status show-status) 0)
(check-true (string-contains? installed-description expected-checksum))

(define (write-message output value)
  (define body (jsexpr->bytes value))
  (fprintf output "Content-Length: ~a\r\n\r\n" (bytes-length body))
  (write-bytes body output)
  (flush-output output))

(define (read-frame input timeout-seconds)
  (check-not-false (sync/timeout timeout-seconds input)
                   "timed out waiting for racket-langserver")
  (define content-length #f)
  (let read-header ()
    (define line (read-line input 'any))
    (cond
      [(eof-object? line) (fail-check "racket-langserver closed its output")]
      [(string=? line "")
       (check-not-false content-length "response omitted Content-Length")
       (bytes->jsexpr (read-bytes content-length input))]
      [else
       (define match (regexp-match #rx"(?i:^Content-Length:[ ]*([0-9]+)$)" line))
       (when match (set! content-length (string->number (cadr match))))
       (read-header)])))

(define (read-response input expected-id)
  (let loop ([remaining 32])
    (check-true (positive? remaining) "response message bound exceeded")
    (define message (read-frame input 30))
    (if (equal? (hash-ref message 'id #f) expected-id)
        message
        (loop (sub1 remaining)))))

(define racket-executable (find-executable-path "racket"))
(check-not-false racket-executable "racket is required")
(define root (make-temporary-file "odra-racket-langserver-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define source (build-path root "main.rkt"))
   (define source-text "#lang racket/base\n(define alpha-value 1)\nalpha-v\n")
   (call-with-output-file source
     (lambda (output) (display source-text output))
     #:exists 'truncate/replace)
   (define uri (string-append "file://" (path->string source)))
   (define root-uri (string-append "file://" (path->string root)))
   (define-values (server server-output server-input server-error)
     (subprocess #f #f #f racket-executable "-l" "racket-langserver"))
   (define error-result (box #""))
   (define error-reader
     (thread (lambda () (set-box! error-result (port->bytes server-error)))))
   (dynamic-wind
    void
    (lambda ()
      (write-message
       server-input
       (hasheq 'jsonrpc "2.0"
               'id 1
               'method "initialize"
               'params
               (hasheq 'processId 'null
                       'rootPath (path->string root)
                       'rootUri root-uri
                       'capabilities
                       (hasheq 'general (hasheq 'positionEncodings '("utf-16")))
                       'workspaceFolders
                       (list (hasheq 'uri root-uri 'name "fixture")))))
      (define initialize-response (read-response server-output 1))
      (check-true (hash? (hash-ref initialize-response 'result #f))
                  (format "initialize response: ~s" initialize-response))
      (write-message
       server-input
       (hasheq 'jsonrpc "2.0" 'method "initialized" 'params (hasheq)))
      (write-message
       server-input
       (hasheq 'jsonrpc "2.0"
               'method "textDocument/didOpen"
               'params
               (hasheq 'textDocument
                       (hasheq 'uri uri
                               'languageId "racket"
                               'version 1
                               'text source-text))))
      (write-message
       server-input
       (hasheq 'jsonrpc "2.0"
               'id 2
               'method "textDocument/completion"
               'params
               (hasheq 'textDocument (hasheq 'uri uri)
                       'position (hasheq 'line 2 'character 7))))
      (define completion-response (read-response server-output 2))
      (check-true (hash-has-key? completion-response 'result))
      (write-message
       server-input
       (hasheq 'jsonrpc "2.0" 'id 3 'method "shutdown" 'params 'null))
      (define shutdown-response (read-response server-output 3))
      (check-true (hash-has-key? shutdown-response 'result))
      (write-message
       server-input
       (hasheq 'jsonrpc "2.0" 'method "exit" 'params 'null))
      (check-not-false (sync/timeout 15 server) "racket-langserver shutdown timed out")
      (subprocess-wait server)
      (check-equal? (subprocess-status server) 0
                    (bytes->string/utf-8 (unbox error-result) #\?)))
    (lambda ()
      (when (eq? (subprocess-status server) 'running)
        (subprocess-kill server #t))
      (close-output-port server-input)
      (close-input-port server-output)
      (close-input-port server-error)
      (thread-wait error-reader)))
   (check-false (regexp-match? #rx#"(?i:error|exception)" (unbox error-result))))
 (lambda () (delete-directory/files root)))
