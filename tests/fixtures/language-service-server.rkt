#lang racket/base

(require racket/bytes
         json
         racket/match
         racket/port
         racket/string)

(define (write-fragmented value)
  (let loop ([offset 0])
    (when (< offset (bytes-length value))
      (define end (min (bytes-length value) (+ offset 3)))
      (write-bytes value (current-output-port) offset end)
      (flush-output)
      (sleep 0.001)
      (loop end))))

(define (frame body)
  (bytes-append
   (string->bytes/utf-8
    (format "Content-Length: ~a\r\n\r\n" (bytes-length body)))
   body))

(define (write-message value)
  (write-fragmented (frame (jsexpr->bytes value))))

(define (publish-diagnostics item)
  (write-message
   (hash 'jsonrpc "2.0" 'method "textDocument/publishDiagnostics"
         'params
         (hash 'uri (hash-ref item 'uri)
               'version (hash-ref item 'version)
               'diagnostics
               (list
                (hash 'range
                      (hash 'start (hash 'line 0 'character 0)
                            'end (hash 'line 0 'character 5))
                      'severity 2
                      'source "fixture"
                      'code "W1"
                      'message "fixture diagnostic"))))))

(define (run-language-server)
  (define documents (make-hash))
  (let loop ()
    (define body (read-frame))
    (when body
      (define message (bytes->jsexpr body))
      (define method (hash-ref message 'method #f))
      (define id (hash-ref message 'id #f))
      (cond
        [(equal? method "initialize")
	     (define initialization-options
	       (hash-ref (hash-ref message 'params) 'initializationOptions (hash)))
	     (when (equal? (hash-ref initialization-options 'profile #f) "fixture")
	       (display "initialization-options-applied\n" (current-error-port))
	       (flush-output (current-error-port)))
	     (when (equal? (getenv "ODRA_FIXTURE_PROFILE") "configured")
	       (display "environment-applied\n" (current-error-port))
	       (flush-output (current-error-port)))
         (write-message
          (hash 'jsonrpc "2.0" 'id id
                'result
                (hash 'capabilities
                      (hash 'positionEncoding "utf-16"
                            'textDocumentSync
                            (hash 'openClose #t 'change 1 'save #t)
                            'completionProvider
                            (hash 'resolveProvider #t
                                  'triggerCharacters (list "." ":"))))))]
	[(equal? method "workspace/didChangeConfiguration")
	 (define settings (hash-ref (hash-ref message 'params) 'settings (hash)))
	 (define fixture-settings (hash-ref settings 'fixture (hash)))
	 (when (eq? (hash-ref fixture-settings 'enabled #f) #t)
	   (display "settings-applied\n" (current-error-port))
	   (flush-output (current-error-port)))]
        [(equal? method "textDocument/didOpen")
         (define item (hash-ref (hash-ref message 'params) 'textDocument))
         (hash-set! documents (hash-ref item 'uri) (hash-ref item 'text))
         (write-message
          (hash 'jsonrpc "2.0" 'method "window/logMessage"
                'params (hash 'type 3 'message (hash-ref item 'text))))
         (publish-diagnostics item)]
        [(equal? method "textDocument/didChange")
         (define params (hash-ref message 'params))
         (define item (hash-ref params 'textDocument))
         (define change (car (hash-ref params 'contentChanges)))
         (define text (hash-ref change 'text))
         (hash-set! documents (hash-ref item 'uri) text)
         (write-message
          (hash 'jsonrpc "2.0" 'method "window/logMessage"
                'params (hash 'type 3 'message text)))
         (publish-diagnostics item)]
        [(equal? method "textDocument/didClose")
         (define item (hash-ref (hash-ref message 'params) 'textDocument))
         (hash-remove! documents (hash-ref item 'uri))]
        [(equal? method "textDocument/completion")
         (write-message
          (hash 'jsonrpc "2.0" 'id id
                'result
                (hash 'isIncomplete #f
                      'items
                      (list
                       (hash 'label "alphaValue"
                             'kind 6
                             'detail "fixture value"
                             'documentation
                             (hash 'kind "markdown" 'value "Fixture completion")
                             'sortText "01"
                             'filterText "beta"
                             'textEdit
                             (hash 'range
                                   (hash 'start (hash 'line 1 'character 0)
                                         'end (hash 'line 1 'character 4))
                                   'newText "alpha_value")
                             'additionalTextEdits
                             (list
                              (hash 'range
                                    (hash 'start (hash 'line 0 'character 0)
                                          'end (hash 'line 0 'character 0))
                                    'newText "# completion\n"))
                             'data (hash 'fixture "alpha"))))))]
        [(equal? method "shutdown")
         (write-message (hash 'jsonrpc "2.0" 'id id 'result 'null))]
        [(equal? method "exit") (void)]
        [else (void)])
      (unless (equal? method "exit") (loop)))))

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

(define arguments (current-command-line-arguments))
(define mode
  (if (zero? (vector-length arguments))
      "echo-fragment"
      (vector-ref arguments 0)))

(case (string->symbol mode)
  [(echo-fragment)
   (define body (read-frame))
   (unless body (error 'fixture "expected one framed request"))
   (write-fragmented (frame body))]
  [(malformed-json)
   (write-fragmented (frame #"{\"jsonrpc\":\"2.0\","))]
  [(oversized)
   (define requested
     (if (> (vector-length arguments) 1)
         (string->number (vector-ref arguments 1))
         1024))
   (write-fragmented
    (bytes-append
     (string->bytes/utf-8 (format "Content-Length: ~a\r\n\r\n" requested))
     (make-bytes requested 120)))]
  [(flood)
   (define message (frame #"{\"jsonrpc\":\"2.0\"}"))
   (for ([index (in-range 32)])
     (write-bytes message))
   (flush-output)]
  [(crash)
   (display "fixture-crash" (current-error-port))
   (flush-output (current-error-port))
   (exit 23)]
  [(lsp) (run-language-server)]
  [else
   (error 'fixture "unknown mode: ~a" mode)])
