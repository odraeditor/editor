#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/command/api.rkt"
         "../../src/command/context.rkt"
         "../../src/command/transaction.rkt")

(define source (string->bytes/utf-8 "ask αsk\nnext"))

(define jan-wire-magic #x4f4452414a414e31)

(define (jan-analysis-record source-bytes kind start end
                             #:attribute-name [attribute-name #f]
                             #:attribute-start [attribute-start 0]
                             #:attribute-end [attribute-end 0])
  (define output (open-output-bytes))
  (define (word value)
    (write-bytes (integer->integer-bytes value 8 #f #f) output))
  (define attribute-count (if attribute-name 1 0))
  (for-each word
            (list jan-wire-magic 1 source-bytes 1 1 attribute-count 0 0
                  1 0 1 1 start end 0 0 attribute-count
                  (bytes-length (string->bytes/utf-8 kind))))
  (write-bytes (string->bytes/utf-8 kind) output)
  (when attribute-name
    (define name-bytes (string->bytes/utf-8 attribute-name))
    (define value-bytes #"value")
    (for-each word
              (list 1 2 attribute-start attribute-end
                    (bytes-length name-bytes) (bytes-length value-bytes)))
    (write-bytes name-bytes output)
    (write-bytes value-bytes output))
  (get-output-bytes output))

(define (call-with-test-context command
                                #:source [document-source source]
                                #:point [point 4]
                                #:region-start [region-start 0]
                                #:region-end [region-end 3]
                                #:line-start [line-start 0]
                                #:line-end [line-end 8]
                                #:effects [effects '(buffer view text-mutation)]
                                #:cancelled? [cancelled? #f]
                                #:package-data-root [package-data-root #f]
                                #:jan-record [jan-record #f]
                                #:operations [operations #f])
  (call-with-transaction
   1
   (lambda (_token operation payload)
     (when operations (set-box! operations (cons operation (unbox operations))))
     (case operation
       [(inspect)
        (list 'ok
              (subbytes document-source
                        (hash-ref payload 'start)
                        (hash-ref payload 'end)))]
       [(jan-analyze)
        (list 'ok
              (or jan-record
                  (jan-analysis-record
                   (bytes-length (hash-ref payload 'source))
                   "plain-text" 0 (bytes-length (hash-ref payload 'source)))))]
       [(splice apply-batch abort) (list 'ok #t)]))
   (lambda (transaction)
     (call-with-command-context
     transaction 7 point region-start region-end line-start line-end
      (bytes-length document-source) effects (lambda () cancelled?) command
      #:package-data-root package-data-root))))

  (test-case "context exposes revision-bound text"
  (define escaped-context #f)
  (define escaped-range #f)
  (call-with-test-context
   (lambda (context)
     (set! escaped-context context)
     (check-true (command-context? context))
     (check-true (text-position? (command-context-point context)))
     (define region (command-context-active-region context))
     (set! escaped-range region)
     (check-true (text-range? region))
     (check-equal? (command-context-read context region) "ask")
     (check-true (immutable? (command-context-read context region)))
     (check-equal?
      (command-context-read context (command-context-current-line context))
      "ask αsk")
     (check-equal?
      (command-context-read context (command-context-buffer-range context))
      "ask αsk\nnext")))
  (check-exn #rx"escaped its dynamic extent"
             (lambda () (command-context-read escaped-context escaped-range))))

(test-case "context reports an absent active region"
  (call-with-test-context
   (lambda (context)
     (check-false (command-context-active-region context)))
   #:region-start #f
   #:region-end #f))

(test-case "contextual value precedence prefers region then point then input"
  (call-with-test-context
   (lambda (context)
     (define resolved
       (command-context-resolve-value
        context #:interactive-value "fallback"))
     (check-equal? (contextual-value-text resolved) "ask")
     (check-eq? (contextual-value-source resolved) 'region)))
  (call-with-test-context
   (lambda (context)
     (define resolved (command-context-resolve-value context))
     (check-equal? (contextual-value-text resolved) "αsk")
     (check-eq? (contextual-value-source resolved) 'point))
   #:region-start #f
   #:region-end #f)
  (call-with-test-context
   (lambda (context)
     (define resolved
       (command-context-resolve-value
        context #:interactive-value "  prompted value  "))
     (check-equal? (contextual-value-text resolved) "prompted value")
     (check-eq? (contextual-value-source resolved) 'interactive)
     (check-false (contextual-value-range resolved)))
   #:source #"   "
   #:point 1
   #:region-start #f
   #:region-end #f
   #:line-end 3))

(test-case "Jan contextual values exclude syntax delimiters"
  (define property #":ROAM_TAGS: :experiment:\n")
  (define property-value-start 12)
  (define property-value-end 24)
  (call-with-test-context
   (lambda (context)
     (define resolved
       (command-context-resolve-value
        context #:at-point command-context-jan-value-at-point))
     (check-equal? (contextual-value-text resolved) "experiment")
     (check-equal?
      (list (text-range-start (contextual-value-range resolved))
            (text-range-end (contextual-value-range resolved)))
      '(13 23)))
   #:source property
   #:point 18
   #:region-start #f
   #:region-end #f
   #:line-end 25
   #:jan-record
   (jan-analysis-record 25 "node-property" 0 25
                        #:attribute-name "value"
                        #:attribute-start property-value-start
                        #:attribute-end property-value-end))
  (for ([point '(2 6 10)])
    (define link #"[[id:engine][Engine]]")
    (call-with-test-context
     (lambda (context)
       (define resolved
         (command-context-resolve-value
          context #:at-point command-context-jan-value-at-point))
       (check-equal? (contextual-value-text resolved) "id:engine"))
     #:source link
     #:point point
     #:region-start #f
     #:region-end #f
     #:line-end (bytes-length link)
     #:jan-record
     (jan-analysis-record (bytes-length link) "regular-link"
                          0 (bytes-length link))))
  (define citation #"[cite:@lovelace1843]")
  (call-with-test-context
   (lambda (context)
     (check-equal?
      (contextual-value-text
       (command-context-resolve-value
        context #:at-point command-context-jan-value-at-point))
      "cite:@lovelace1843"))
   #:source citation
   #:point 9
   #:region-start #f
   #:region-end #f
   #:line-end (bytes-length citation)
   #:jan-record
   (jan-analysis-record (bytes-length citation) "citation-reference"
                        0 (bytes-length citation)))
  (define url #"<https://example.test/wiki/Ada_Lovelace>")
  (call-with-test-context
   (lambda (context)
     (check-equal?
      (contextual-value-text
       (command-context-resolve-value
        context #:at-point command-context-jan-value-at-point))
      "https://example.test/wiki/Ada_Lovelace"))
   #:source url
   #:point 22
   #:region-start #f
   #:region-end #f
   #:line-end (bytes-length url)
   #:jan-record
   (jan-analysis-record (bytes-length url) "angle-link"
                        0 (bytes-length url))))

(test-case "contextual values enforce their copied byte bound"
  (call-with-test-context
   (lambda (context)
     (check-exn
      #rx"exceeds the admitted byte bound"
      (lambda ()
        (command-context-resolve-value context #:maximum-bytes 2))))))

(test-case "single replacement stages one UTF-8 splice"
  (define operations (box '()))
  (call-with-test-context
   (lambda (context)
     (command-context-replace!
      context (command-context-active-region context) "pytaj")
     (check-exn #rx"stale after mutation"
                (lambda ()
                  (command-context-read
                   context (command-context-current-line context)))))
   #:operations operations)
  (check-equal? (reverse (unbox operations)) '(splice)))

(test-case "batch replacement admits distinct ranges once"
  (define operations (box '()))
  (call-with-test-context
   (lambda (context)
     (define region (command-context-active-region context))
     (define line (command-context-current-line context))
     (command-context-replace-batch!
      context
      (list (make-text-edit line "next!")
            (make-text-edit region "ASK"))))
   #:region-start 0
   #:region-end 3
   #:line-start 9
   #:line-end 13
   #:operations operations)
  (check-equal? (reverse (unbox operations)) '(apply-batch)))

(test-case "batch replacement rejects ambiguous ranges"
  (call-with-test-context
   (lambda (context)
     (define region (command-context-active-region context))
     (check-exn
      #rx"must not overlap"
      (lambda ()
        (command-context-replace-batch!
         context
         (list (make-text-edit region "A")
               (make-text-edit region "B"))))))))

(test-case "context enforces owner and declared effects"
  (define first-range #f)
  (call-with-test-context
   (lambda (context)
     (set! first-range (command-context-active-region context))))
  (call-with-test-context
   (lambda (context)
     (check-exn #rx"another command context"
                (lambda () (command-context-read context first-range)))
     (check-exn
      #rx"does not admit text mutation"
      (lambda ()
        (command-context-replace!
         context (command-context-active-region context) "ASK"))))
   #:effects '(buffer view)))

(test-case "cancellation and abort remain turn-scoped"
  (define operations (box '()))
  (call-with-test-context
   (lambda (context)
     (check-true (command-context-cancelled? context))
     (command-context-abort! context))
   #:cancelled? #t
   #:operations operations)
  (check-equal? (reverse (unbox operations)) '(abort)))

(test-case "package artifacts and admitted renderers stay inside package storage"
  (define root (make-temporary-file "command-artifacts-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (call-with-test-context
       (lambda (context)
         (define written
           (command-context-write-package-artifact!
            context "exports/graph.dot" #"digraph roman {}"))
         (check-equal? written (path->string (build-path root "exports/graph.dot")))
         (check-equal? (file->bytes written) #"digraph roman {}")
         (check-exn
          #rx"normalized and relative"
          (lambda ()
            (command-context-write-package-artifact!
             context "../escape.dot" #"denied")))
         (define observed (box #f))
         (define result
           (call-with-command-tool-runner
            (lambda (tool input output timeout)
              (set-box! observed (list tool input output timeout))
              (command-tool-result 'success 0 ""))
            (lambda ()
              (command-context-render-graphviz!
               context "exports/graph.dot" "exports/graph.svg" 1000))))
         (check-eq? (command-tool-result-status result) 'success)
         (check-equal?
          (unbox observed)
          (list 'graphviz-dot
                (build-path root "exports/graph.dot")
                (build-path root "exports/graph.svg")
                1000)))
       #:package-data-root (path->string root)))
    (lambda () (delete-directory/files root))))
