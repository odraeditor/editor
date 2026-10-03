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
(check-not-false script-path "util-linux script is required for the live terminal PTY scenario")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define test-root (make-temporary-file "odra-live-terminal-~a" 'directory))
(define document-path (build-path test-root "terminal.txt"))
(define shell-path (build-path test-root "shell"))
(call-with-output-file
 document-path
 #:exists 'truncate/replace
 (lambda (output) (display "live terminal acceptance\n" output)))
(call-with-output-file
 shell-path
 #:exists 'truncate/replace
 (lambda (output)
   (display "#!/bin/sh\nprintf 'Ω\\n'\nexec /bin/sh -i\n" output)))
(file-or-directory-permissions shell-path #o700)

(define command
  (string-append
   "stty rows 24 cols 100; exec env TERM=xterm-256color SHELL="
   (shell-quote (path->string shell-path))
   " "
   "HOME=" (shell-quote (path->string test-root)) " "
   "XDG_CONFIG_HOME="
   (shell-quote (path->string (build-path test-root "config"))) " "
   "XDG_STATE_HOME="
   (shell-quote (path->string (build-path test-root "state"))) " "
   "XDG_CACHE_HOME="
   (shell-quote (path->string (build-path test-root "cache"))) " "
   "XDG_DATA_HOME="
   (shell-quote (path->string (build-path test-root "data"))) " "
   (shell-quote odra-path)
   " "
   (shell-quote (path->string document-path))))
(define-values (process output input error-output)
  (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
(define transcript (open-output-bytes))
(define read-buffer (make-bytes 4096))

(define (transcript-contains? value)
  (regexp-match? (byte-regexp (regexp-quote value)) (get-output-bytes transcript)))

(define (transcript-tail)
  (define bytes (get-output-bytes transcript))
  (bytes->string/utf-8 (subbytes bytes (max 0 (- (bytes-length bytes) 4096))) #\?))

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

(define (send bytes [pause 0.25])
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (write-bytes bytes input)
    (flush-output input))
  (sleep pause))

;; Drain terminal rendering while waiting for an observable document save.
(define (wait-for-document-text! text [timeout 10])
  (define deadline (+ (current-inexact-milliseconds) (* timeout 1000)))
  (let loop ()
    (cond
      [(regexp-match? (regexp (regexp-quote text)) (file->string document-path)) #t]
      [(>= (current-inexact-milliseconds) deadline) #f]
      [else
       (when (sync/timeout 0.05 output)
         (define count (read-bytes-avail!* read-buffer output))
         (when (exact-positive-integer? count)
           (write-bytes read-buffer transcript 0 count)))
       (loop)])))

(dynamic-wind
 void
 (lambda ()
   (check-true (wait-for-output! #"live terminal acceptance") "initial editor frame")
   (send #"\33xterminal-open\r" 0.5)
   (check-true
    (wait-for-output! #"\33[2 q")
    (string-append "terminal pane must become active\n" (transcript-tail)))
   (check-true
    (wait-for-output! (string->bytes/utf-8 "Ω"))
    (string-append "live shell output must reach the visible terminal pane\n" (transcript-tail)))
   (sleep 0.5)
   (send #"printf '\\316\\250\\n'\r" 0.5)
   (check-true
    (wait-for-output! (string->bytes/utf-8 "Ψ"))
    (string-append "terminal input must reach the live shell and return visible output\n" (transcript-tail)))
   ;; Pane cycling must route subsequent editing and saving to the original document.
   (send (bytes 24 111) 0.3)
   (send #"pane focus verified\r" 0.3)
   (send (bytes 24 19) 0.5)
   (check-true
    (wait-for-document-text! "pane focus verified")
    (string-append "cycling from the lower terminal must preserve editable document focus\n"
                   (transcript-tail)))
   (send #"\33xterminal-open\r" 0.3)
   (send #"\33xterminal-toggle\r" 0.3)
   (send #"\33xterminal-toggle\r" 0.3)
   (send #"\33xrequest-editor-exit\r" 0.3)
   (check-true
    (wait-for-output! #"Exit and terminate 1 live terminal?")
    (string-append "live terminal exit confirmation must be visible\n" (transcript-tail)))
   (send #"y" 0)
   (define exited? (sync/timeout 10 process))
   (unless exited? (subprocess-kill process #t))
   (subprocess-wait process)
   (define error-bytes (port->bytes error-output))
   (check-not-false exited? "editor exits after confirming live terminal shutdown")
   (check-equal? (subprocess-status process) 0 (transcript-tail))
   (check-equal? error-bytes #""))
 (lambda ()
   (when (directory-exists? test-root) (delete-directory/files test-root))
   (close-output-port input)
   (close-input-port output)
   (close-input-port error-output)))
