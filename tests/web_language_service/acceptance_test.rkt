#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require json
         rackunit
         racket/file
         racket/list
         racket/path
         racket/port
         racket/string
         racket/system)

(define (required-executable variable)
  (define value (getenv variable))
  (check-not-false value (format "~a must identify the pinned executable" variable))
  (define path (and value (string->path value)))
  (check-true (and path (file-exists? path)) (format "~a does not exist" variable))
  path)

(define typescript-executable (required-executable "TYPESCRIPT_LANGUAGE_SERVER_EXECUTABLE"))
(define html-executable (required-executable "HTML_LANGUAGE_SERVER_EXECUTABLE"))
(define css-executable (required-executable "CSS_LANGUAGE_SERVER_EXECUTABLE"))
(define typescript-version (or (getenv "TYPESCRIPT_LANGUAGE_SERVER_VERSION") "6.0.0"))
(define expected-typescript-version (or (getenv "TYPESCRIPT_VERSION") "6.0.3"))
(define vscode-version (or (getenv "VSCODE_LANGSERVERS_VERSION") "4.10.0"))
(define typescript-library-path (or (getenv "TYPESCRIPT_LIBRARY_PATH") ""))
(check-true (directory-exists? typescript-library-path)
            "TYPESCRIPT_LIBRARY_PATH must identify the pinned TypeScript library")

(define (subprocess-output executable . arguments)
  (define-values (process output input error)
    (apply subprocess #f #f #f executable arguments))
  (close-output-port input)
  (define stdout (port->string output))
  (define stderr (port->string error))
  (close-input-port output)
  (close-input-port error)
  (subprocess-wait process)
  (values (subprocess-status process) stdout stderr))

(define-values (version-status version-output version-error)
  (subprocess-output typescript-executable "--version"))
(check-equal? version-status 0 version-error)
(check-true (string-contains? version-output typescript-version)
            (format "unexpected TypeScript server version: ~s" version-output))
(define package-json (string->path (or (getenv "VSCODE_LANGSERVERS_PACKAGE_JSON") "")))
(check-true (file-exists? package-json) "VSCODE_LANGSERVERS_PACKAGE_JSON must identify the package")
(define package-version
  (hash-ref (call-with-input-file package-json read-json) 'version #f))
(check-equal? package-version vscode-version)
(define typescript-package-json
  (string->path (or (getenv "TYPESCRIPT_PACKAGE_JSON") "")))
(check-true (file-exists? typescript-package-json)
            "TYPESCRIPT_PACKAGE_JSON must identify the compiler package")
(check-equal?
 (hash-ref (call-with-input-file typescript-package-json read-json) 'version #f)
 expected-typescript-version)

(define (write-message output value)
  (define body (jsexpr->bytes value))
  (fprintf output "Content-Length: ~a\r\n\r\n" (bytes-length body))
  (write-bytes body output)
  (flush-output output))

(define (read-frame input name)
  (check-not-false (sync/timeout 30 input) (format "timed out waiting for ~a" name))
  (define content-length #f)
  (let read-header ()
    (define line (read-line input 'any))
    (cond
      [(eof-object? line) (fail-check (format "~a closed its output" name))]
      [(string=? line "")
       (check-not-false content-length "response omitted Content-Length")
       (bytes->jsexpr (read-bytes content-length input))]
      [else
       (define match (regexp-match #rx"(?i:^Content-Length:[ ]*([0-9]+)$)" line))
       (when match (set! content-length (string->number (cadr match))))
       (read-header)])))

(define (server-request? message)
  (and (hash-has-key? message 'id) (hash-has-key? message 'method)))

(define (answer-server-request output message)
  (define method (hash-ref message 'method))
  (define result
    (if (equal? method "workspace/configuration")
        (make-list (length (hash-ref (hash-ref message 'params (hasheq)) 'items '()))
                   (hasheq))
        'null))
  (write-message output
                 (hasheq 'jsonrpc "2.0" 'id (hash-ref message 'id) 'result result)))

(define (read-response input output name expected-id)
  (let loop ([remaining 64])
    (check-true (positive? remaining) (format "~a response bound exceeded" name))
    (define message (read-frame input name))
    (cond
      [(server-request? message)
       (answer-server-request output message)
       (loop (sub1 remaining))]
      [(equal? (hash-ref message 'id #f) expected-id) message]
      [else (loop (sub1 remaining))])))

(define (path->file-uri path)
  (string-append "file://" (path->string path)))

(define cases
  (list
   (hasheq 'name "typescript-language-server"
           'executable typescript-executable
           'language "typescript"
           'filename "main.ts"
           'text "const alphaValue = 1;\nalp\n"
           'initialization-options
           (hasheq 'tsserver (hasheq 'path typescript-library-path))
           'line 1 'character 3)
   (hasheq 'name "vscode-html-language-server"
           'executable html-executable
           'language "html"
           'filename "index.html"
           'text "<main><sp\n"
           'initialization-options (hasheq)
           'line 0 'character 9)
   (hasheq 'name "vscode-css-language-server"
           'executable css-executable
           'language "css"
           'filename "site.css"
           'text ".card { col\n"
           'initialization-options (hasheq)
           'line 0 'character 11)))

(for ([case (in-list cases)])
  (define name (hash-ref case 'name))
  (define root (make-temporary-file "odra-web-language-server-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (call-with-output-file (build-path root "package.json")
       (lambda (output) (display "{\"private\":true}\n" output))
       #:exists 'truncate/replace)
     (define source (build-path root (hash-ref case 'filename)))
     (call-with-output-file source
       (lambda (output) (display (hash-ref case 'text) output))
       #:exists 'truncate/replace)
     (define root-uri (path->file-uri root))
     (define source-uri (path->file-uri source))
     (define-values (server server-output server-input server-error)
       (subprocess #f #f #f (hash-ref case 'executable) "--stdio"))
     (define error-result (box #""))
     (define error-reader
       (thread (lambda () (set-box! error-result (port->bytes server-error)))))
     (dynamic-wind
      void
      (lambda ()
        (write-message
         server-input
         (hasheq 'jsonrpc "2.0" 'id 1 'method "initialize"
                 'params
                 (hasheq 'processId 'null
                         'clientInfo (hasheq 'name "Odra web interoperability acceptance")
                         'rootPath (path->string root)
                         'rootUri root-uri
                         'initializationOptions (hash-ref case 'initialization-options)
                         'capabilities
                         (hasheq 'general (hasheq 'positionEncodings '("utf-16"))
                                 'textDocument
                                 (hasheq 'completion
                                         (hasheq 'completionItem
                                                 (hasheq 'snippetSupport #f))))
                         'workspaceFolders
                         (list (hasheq 'uri root-uri 'name "fixture")))))
        (define initialize-response
          (read-response server-output server-input name 1))
        (define capabilities
          (hash-ref (hash-ref initialize-response 'result (hasheq)) 'capabilities #f))
        (check-true (hash? capabilities)
                    (format "~a initialize response: ~s" name initialize-response))
        (when (hash? capabilities)
          (check-true (positive? (hash-count capabilities))
                      (format "~a published empty capabilities" name)))
        (write-message server-input
                       (hasheq 'jsonrpc "2.0" 'method "initialized" 'params (hasheq)))
        (write-message
         server-input
         (hasheq 'jsonrpc "2.0" 'method "textDocument/didOpen"
                 'params
                 (hasheq 'textDocument
                         (hasheq 'uri source-uri
                                 'languageId (hash-ref case 'language)
                                 'version 1
                                 'text (hash-ref case 'text)))))
        (write-message
         server-input
         (hasheq 'jsonrpc "2.0" 'id 2 'method "textDocument/completion"
                 'params
                 (hasheq 'textDocument (hasheq 'uri source-uri)
                         'position
                         (hasheq 'line (hash-ref case 'line)
                                 'character (hash-ref case 'character)))))
        (define completion-response
          (read-response server-output server-input name 2))
        (check-true (hash-has-key? completion-response 'result)
                    (format "~a omitted completion result" name))
        (write-message server-input
                       (hasheq 'jsonrpc "2.0" 'id 3 'method "shutdown" 'params 'null))
        (define shutdown-response
          (read-response server-output server-input name 3))
        (check-true (hash-has-key? shutdown-response 'result))
        (write-message server-input
                       (hasheq 'jsonrpc "2.0" 'method "exit" 'params 'null))
        (check-not-false (sync/timeout 15 server) (format "~a shutdown timed out" name))
        (subprocess-wait server)
        (check-equal? (subprocess-status server) 0
                      (bytes->string/utf-8 (unbox error-result) #\?)))
      (lambda ()
        (when (eq? (subprocess-status server) 'running)
          (subprocess-kill server #t))
        (close-output-port server-input)
        (close-input-port server-output)
        (close-input-port server-error)
        (thread-wait error-reader))))
   (lambda () (delete-directory/files root))))
