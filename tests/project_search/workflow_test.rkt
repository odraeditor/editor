#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         racket/path
         racket/port
         racket/system
         "../../src/project/persistence.rkt"
         "../../src/project/records.rkt")

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for the PTY scenario")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")
(define home-directory (make-temporary-file "odra-project-search-~a" 'directory))
(define root (build-path home-directory "project-search"))
(make-directory root)
(define (utf8 text) (string->bytes/utf-8 text))
(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(dynamic-wind
 void
 (lambda ()
   (define alpha-path (build-path root "alpha.odin"))
   (define beta-path (build-path root "beta.odin"))
   (call-with-output-file alpha-path #:exists 'truncate/replace
     (lambda (output) (display "package main\nneedle := 1\n" output)))
   (call-with-output-file beta-path #:exists 'truncate/replace
     (lambda (output) (display "package beta\nvalue := \"needle\"\n" output)))
   (check-true
    (odra-record-publication?
     (local-project-record-persist
      root
      (local-project-record
       #:format-version current-local-project-format-version
       #:id "project-search-workflow"
       #:generation 1
       #:name "Project Search Workflow"
       #:root (path->string root)
       #:trust 'untrusted))))

   (define command
     (string-append
      "stty rows 20 cols 120; HOME="
      (shell-quote (path->string home-directory))
      " exec "
      (shell-quote odra-path)))
   (define-values (process output input error-output)
     (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
   (define transcript (open-output-bytes))
   (define read-buffer (make-bytes 4096))
   (define (contains? value)
     (regexp-match? (byte-regexp (regexp-quote value)) (get-output-bytes transcript)))
   (define (wait-for! value [timeout 10])
     (define deadline (+ (current-inexact-milliseconds) (* timeout 1000)))
     (let loop ()
       (cond [(contains? value) #t]
             [(<= deadline (current-inexact-milliseconds)) #f]
             [(sync/timeout 0.25 output)
              (define count (read-bytes-avail!* read-buffer output))
              (when (exact-positive-integer? count)
                (write-bytes read-buffer transcript 0 count))
              (loop)]
             [else (loop)])))
   (define (send! value) (write-bytes value input) (flush-output input))
   (define input-written?
     (with-handlers ([exn:fail? (lambda (_) #f)])
       (check-true (wait-for! #"Open Dir") "Odra did not render startup navigation")
       (send! (bytes-append #"\33[B\33[B\r~/project-search\ralpha\r"))
       (check-true (wait-for! #"needle := 1") "Odra did not open the Project fixture")
       (send! #"\33xproject-search-text\rneedle\r")
       (check-true (wait-for! #"Results [current set]") "Project search results did not open")
       (check-true (wait-for! #"beta.odin") "Project search did not publish both files")
       (check-true (wait-for! #"2:11")
                   "Project search did not expose path and location")
       (send! #"\33[B\r")
       (check-true (wait-for! #"value := \"needle\"") "Project result navigation did not open the selected file")
       (send! (bytes 24 3))
       #t))
   (define completed? (sync/timeout 20 process))
   (unless completed? (subprocess-kill process #t))
   (subprocess-wait process)
   (copy-port output transcript)
   (define error-bytes (port->bytes error-output))
   (close-input-port output)
   (close-input-port error-output)
   (check-not-false completed? "Odra did not complete the Project search scenario")
   (check-equal? (subprocess-status process) 0)
   (check-true input-written?)
   (check-equal? error-bytes #"")
   (check-true (contains? #"alpha.odin"))
   (check-true (contains? #"beta.odin"))
   (check-true (contains? #"\33[?25h\33[0m\r\n")))
 (lambda ()
   (delete-directory/files home-directory)))
