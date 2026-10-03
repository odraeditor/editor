#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         racket/port
         racket/system)

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for the PTY scenario")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define project-root (make-temporary-file "odra-result-navigation-~a" 'directory))
(define metadata-root (build-path project-root ".odra"))
(make-directory metadata-root)
(call-with-output-file
 (build-path metadata-root "project.rkt")
 #:exists 'truncate/replace
 (lambda (output)
   (fprintf
    output
    "#lang odra/config\n(local-project #:format-version 2 #:id ~s #:generation 1 #:name ~s #:root ~s #:trust trusted)\n"
    "result-navigation-fixture"
    "Result navigation fixture"
    (path->string project-root))))
(define document-path (build-path project-root "main.txt"))
(call-with-output-file
 document-path
 #:exists 'truncate/replace
 (lambda (output)
   (display "alpha beta alpha\n" output)))

(define command
  (string-append
   "stty rows 24 cols 100; exec " odra-path " " (path->string document-path)))
(define-values (process output input error-output)
  (subprocess #f #f #f script-path "-qfec" command "/dev/null"))

(define transcript (open-output-bytes))
(define read-buffer (make-bytes 4096))

(define (transcript-contains? value)
  (regexp-match?
   (byte-regexp (regexp-quote value))
   (get-output-bytes transcript)))

(define (wait-for-output! value [timeout 10])
  (define deadline (+ (current-inexact-milliseconds) (* timeout 1000)))
  (let loop ()
    (cond
      [(transcript-contains? value) #t]
      [else
       (define remaining (/ (- deadline (current-inexact-milliseconds)) 1000.0))
       (cond
         [(<= remaining 0) #f]
         [(sync/timeout remaining output)
          (define count (read-bytes-avail!* read-buffer output))
          (when (exact-positive-integer? count)
            (write-bytes read-buffer transcript 0 count))
          (loop)]
         [else #f])])))

(check-true
 (wait-for-output! #"alpha beta alpha")
 "Odra did not render its initial terminal frame")
(define (send! content)
  (write-bytes content input)
  (flush-output input))
(define input-written?
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (send! (bytes-append (bytes 19) #"alpha")) ; C-s: begin literal search
    (send! (bytes-append (bytes 27) #"so"))    ; M-s o: materialize results
    (check-true
     (wait-for-output! #"Results [current set]")
     "Search results were not materialized")
    (check-true
     (wait-for-output! #"1:01")
     "Search results did not expose line and column")
    (check-true
     (wait-for-output! #"1:12")
     "Search results did not expose the later source location")
    (check-true
     (wait-for-output! #" beta alpha")
     "Search results did not expose nearby source text")
    (send! #"e")                              ; edit the selected result
    (check-true
     (wait-for-output! #"Edit result text")
     "Result editing did not open")
    (send! (bytes-append (make-bytes 5 127) #"omega" (bytes 13)))
    (send! (bytes 3 3))                        ; C-c C-c: apply staged edits
    (check-true
     (wait-for-output! #"Result edits applied")
     "Staged result edits were not applied")
    (define saved-event (filesystem-change-evt document-path))
    (send! (bytes 24 19))                      ; C-x C-s: save the buffer
    (check-not-false
     (sync/timeout 10 saved-event)
     "The edited document was not published")
    (send! (bytes 24 3))                       ; C-x C-c: exit
    #t))
(define completed? (sync/timeout 20 process))
(unless completed? (subprocess-kill process #t))
(subprocess-wait process)

(copy-port output transcript)
(define output-bytes (get-output-bytes transcript))
(define error-bytes (port->bytes error-output))
(define saved-text (file->string document-path))
(close-input-port output)
(close-input-port error-output)
(delete-directory/files project-root)

(define (contains? value)
  (regexp-match? (byte-regexp (regexp-quote value)) output-bytes))

(check-equal? (subprocess-status process) 0)
(check-not-false completed? "Odra did not complete the result navigation scenario")
(check-true input-written?)
(check-equal? error-bytes #"")
(check-true (contains? #"Results [current set]"))
(check-true (contains? #"Edit result text"))
(check-true (contains? #"\33[?2026h"))
(check-true (contains? #"\33[?2026l"))
(check-equal? saved-text "omega beta alpha\n")
(check-true (contains? #"\33[?25h\33[0m\r\n"))
