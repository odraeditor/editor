#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         racket/path
         racket/port
         racket/system)

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for the other-pane PTY scenario")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define test-directory (make-temporary-file "odra-other-pane-~a" 'directory))
(define first-path (build-path test-directory "first.txt"))
(define second-path (build-path test-directory "second.txt"))
(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))
(call-with-output-file
 first-path
 #:exists 'truncate/replace
 (lambda (output) (display "alpha-buffer\n" output)))
(call-with-output-file
 second-path
 #:exists 'truncate/replace
 (lambda (output) (display "beta-buffer\n" output)))

(define command
  (string-append
   "stty rows 16 cols 64; HOME="
   (shell-quote (path->string test-directory))
   " exec "
   (shell-quote odra-path)
   " "
   (shell-quote (path->string first-path))))
(define-values (process output input error-output)
  (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
(define output-result (make-channel))
(define error-result (make-channel))
(define output-reader
  (thread (lambda () (channel-put output-result (port->bytes output)))))
(define error-reader
  (thread (lambda () (channel-put error-result (port->bytes error-output)))))

(define input-open? #t)
(define (send bytes [pause 0.18])
  (when input-open?
    (with-handlers ([exn:fail? (lambda (_) (set! input-open? #f))])
      (write-bytes bytes input)
      (flush-output input)))
  (sleep pause))

(sleep 1.1)
(send (bytes 24 (char->integer #\4) (char->integer #\b))) ; selecting buffer command
(send #"notes")
(send #"\r" 0.3)
(send #"omega")
(send (bytes 24 (char->integer #\4) 15)) ; display-only C-x 4 C-o
(send (string->bytes/utf-8 (path->string first-path)))
(send #"\t")
(send #"\r" 0.3)
(send #"z") ; focus must still be in notes
(send (bytes 24 (char->integer #\4) (char->integer #\f))) ; selecting file command
(send #"~/second.txt")
(send #"\t")
(send #"\r" 0.4)
(send (bytes 24 3) 0.25) ; C-x C-c
(send #"d" 0)           ; discard modified notes during exit

(define exited? (sync/timeout 10 process))
(unless exited?
  (subprocess-kill process #t))
(subprocess-wait process)

(define output-bytes (channel-get output-result))
(define error-bytes (channel-get error-result))
(close-input-port output)
(close-input-port error-output)
(delete-directory/files test-directory)

(check-equal?
 (subprocess-status process)
 0
 (bytes->string/utf-8 output-bytes #\?))
(check-not-false exited?)
(check-equal? error-bytes #"")
(check-true (regexp-match? (byte-regexp (regexp-quote #"alpha-buffer")) output-bytes))
(check-true (regexp-match? (byte-regexp (regexp-quote #"omegaz")) output-bytes))
(check-true (regexp-match? (byte-regexp (regexp-quote #"beta-buffer")) output-bytes))
(check-true
 (regexp-match? (byte-regexp (regexp-quote #"Find file in other pane")) output-bytes))
(check-true
 (regexp-match? (byte-regexp (regexp-quote #"\33[?25h\33[0m\r\n")) output-bytes))
