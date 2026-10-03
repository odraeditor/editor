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
         racket/system
         "../../src/configuration/personal.rkt"
         "../../src/hosting/language-support-configuration-bridge.rkt")

(define expected-version (or (getenv "GOPLS_VERSION") "v0.23.0"))
(define configured-executable (getenv "GOPLS_EXECUTABLE"))
(define gopls-executable
  (and configured-executable
       (not (string=? configured-executable ""))
       (string->path configured-executable)))

(check-not-false gopls-executable "GOPLS_EXECUTABLE must identify the pinned gopls executable")
(check-true (file-exists? gopls-executable) "the pinned gopls executable does not exist")

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
  (subprocess-output gopls-executable "version"))
(check-equal? version-status 0 version-error)
(check-true
 (string-contains? version-output expected-version)
 (format "expected gopls ~a, received ~s" expected-version version-output))

(define (write-message output value)
  (define body (jsexpr->bytes value))
  (fprintf output "Content-Length: ~a\r\n\r\n" (bytes-length body))
  (write-bytes body output)
  (flush-output output))

(define (read-frame input timeout-seconds)
  (check-not-false (sync/timeout timeout-seconds input)
                   "timed out waiting for gopls")
  (define content-length #f)
  (let read-header ()
    (define line (read-line input 'any))
    (cond
      [(eof-object? line) (fail-check "gopls closed its output")]
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
        (make-list
         (length (hash-ref (hash-ref message 'params (hasheq)) 'items '()))
         (hasheq))
        'null))
  (write-message output (hasheq 'jsonrpc "2.0" 'id (hash-ref message 'id) 'result result)))

(define (completion-items result)
  (cond
    [(list? result) result]
    [(hash? result) (hash-ref result 'items '())]
    [else '()]))

(define (path->file-uri path)
  (string-append "file://" (path->string path)))

(define root (make-temporary-file "odra-gopls-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (call-with-output-file (build-path root "go.mod")
     (lambda (output)
       (display "module example.com/odra-gopls-fixture\n\ngo 1.22\n" output))
     #:exists 'truncate/replace)
   (define source (build-path root "main.go"))
   (define source-text
     (string-append
      "package main\n\n"
      "import \"fmt\"\n\n"
      "func main() {\n"
      "    fmt.Prin\n"
      "    _ = missingName\n"
      "}\n"))
   (call-with-output-file source
     (lambda (output) (display source-text output))
     #:exists 'truncate/replace)

   (define configuration-root (build-path root "configuration"))
   (make-directory configuration-root)
   (call-with-output-file (build-path configuration-root "init.rkt")
     (lambda (output)
       (display
        (string-append
         "#lang racket/base\n"
         "(require odra/languages)\n"
         "(provide odra-language-support)\n"
         "(define odra-language-support\n"
         "  (language-support\n"
         "   #:language 'go\n"
         "   #:display-name \"Go\"\n"
         "   #:suffixes '(\".go\")\n"
         "   #:server\n"
         "   (language-service\n"
         "    #:id 'gopls\n"
         "    #:display-name \"gopls\"\n"
         "    #:command '(\"gopls\" \"serve\")\n"
         "    #:root-markers '(\"go.work\" \"go.mod\")\n"
         "    #:features '(diagnostics completion))))\n")
        output))
     #:exists 'truncate/replace)
   (define configuration
     (personal-config-load (personal-config-source configuration-root)))
   (check-eq? (odra-personal-config-observation-state configuration) 'confirmed)
   (define support
     (personal-config-observation-export configuration 'odra-language-support #f))
   (check-not-false support "the public configuration did not publish Go support")
   (define encoded-support (language-support-configuration-encode support))
   (define decoded-support (bytes->jsexpr encoded-support))
   (check-equal? (hash-ref (car (hash-ref decoded-support 'languages)) 'id) "go")
   (check-equal?
    (hash-ref (car (hash-ref decoded-support 'services)) 'command)
    '("gopls" "serve"))

   (define root-uri (path->file-uri root))
   (define source-uri (path->file-uri source))
   (define-values (server server-output server-input server-error)
     (subprocess #f #f #f gopls-executable "serve"))
   (define error-result (box #""))
   (define error-reader
     (thread (lambda () (set-box! error-result (port->bytes server-error)))))
   (dynamic-wind
    void
    (lambda ()
      (write-message
       server-input
       (hasheq
        'jsonrpc "2.0"
        'id 1
        'method "initialize"
        'params
        (hasheq
         'processId 'null
         'clientInfo (hasheq 'name "Odra interoperability acceptance")
         'rootPath (path->string root)
         'rootUri root-uri
         'capabilities
         (hasheq
          'general (hasheq 'positionEncodings '("utf-16"))
          'textDocument
          (hasheq 'completion (hasheq 'completionItem (hasheq 'snippetSupport #f))))
         'workspaceFolders (list (hasheq 'uri root-uri 'name "fixture")))))
      (define initialize-response
        (let loop ([remaining 32])
          (check-true (positive? remaining) "initialize response bound exceeded")
          (define message (read-frame server-output 30))
          (cond
            [(server-request? message)
             (answer-server-request server-input message)
             (loop (sub1 remaining))]
            [(equal? (hash-ref message 'id #f) 1) message]
            [else (loop (sub1 remaining))])))
      (check-true (hash? (hash-ref initialize-response 'result #f)))
      (write-message server-input
                     (hasheq 'jsonrpc "2.0" 'method "initialized" 'params (hasheq)))
      (write-message
       server-input
       (hasheq
        'jsonrpc "2.0"
        'method "textDocument/didOpen"
        'params
        (hasheq
         'textDocument
         (hasheq 'uri source-uri 'languageId "go" 'version 1 'text source-text))))
      (write-message
       server-input
       (hasheq
        'jsonrpc "2.0"
        'id 2
        'method "textDocument/completion"
        'params
        (hasheq
         'textDocument (hasheq 'uri source-uri)
         'position (hasheq 'line 5 'character 12))))

      (define diagnostics-seen? #f)
      (define completion-response #f)
      (let loop ([remaining 96])
        (unless (and diagnostics-seen? completion-response)
          (check-true (positive? remaining) "gopls evidence message bound exceeded")
          (define message (read-frame server-output 30))
          (cond
            [(server-request? message) (answer-server-request server-input message)]
            [(and (equal? (hash-ref message 'method #f)
                          "textDocument/publishDiagnostics")
                  (equal? (hash-ref (hash-ref message 'params (hasheq)) 'uri #f)
                          source-uri))
             (define diagnostics
               (hash-ref (hash-ref message 'params (hasheq)) 'diagnostics '()))
             (when
                 (for/or ([diagnostic (in-list diagnostics)])
                   (string-contains?
                    (hash-ref diagnostic 'message "")
                    "missingName"))
               (set! diagnostics-seen? #t))]
            [(equal? (hash-ref message 'id #f) 2)
             (set! completion-response message)])
          (loop (sub1 remaining))))
      (check-true diagnostics-seen? "gopls did not publish the expected diagnostic")
      (check-true
       (for/or ([item (in-list
                       (completion-items
                        (hash-ref completion-response 'result '())))])
         (string-prefix? (hash-ref item 'label "") "Print"))
       "gopls completion omitted the fmt Print family")

      (write-message server-input
                     (hasheq 'jsonrpc "2.0" 'id 3 'method "shutdown" 'params 'null))
      (define shutdown-response
        (let loop ([remaining 32])
          (check-true (positive? remaining) "shutdown response bound exceeded")
          (define message (read-frame server-output 15))
          (cond
            [(server-request? message)
             (answer-server-request server-input message)
             (loop (sub1 remaining))]
            [(equal? (hash-ref message 'id #f) 3) message]
            [else (loop (sub1 remaining))])))
      (check-true (hash-has-key? shutdown-response 'result))
      (write-message server-input
                     (hasheq 'jsonrpc "2.0" 'method "exit" 'params 'null))
      (check-not-false (sync/timeout 15 server) "gopls shutdown timed out")
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
 (lambda () (delete-directory/files root)))
