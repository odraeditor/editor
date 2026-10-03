#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         racket/list
         racket/path
         racket/port
         racket/system
         "../support/terminal-readiness.rkt")

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for package acceptance")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define control-space (bytes 0))
(define control-x (bytes 24))
(define control-s (bytes 19))
(define right #"\33[C")
(define exit-sequence (bytes 24 3))
(define restoration-sequence #"\33[?25h\33[0m")

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define sandbox
  (make-temporary-file "odra-package-canary-acceptance-~a" 'directory))
(define configuration-base (build-path sandbox "config"))
(define state-root (build-path configuration-base "odra"))
(define data-base (build-path sandbox "data"))
(define cache-base (build-path sandbox "cache"))
(define runtime-state-base (build-path sandbox "state"))
(define document-path (build-path sandbox "canary.txt"))

(dynamic-wind
 void
 (lambda ()
   (for ([directory
          (in-list (list state-root data-base cache-base runtime-state-base))])
     (make-directory* directory)
     (file-or-directory-permissions directory #o700))
   (file-or-directory-permissions configuration-base #o700)
   ;; Exercise package activation alongside a valid personal configuration.
   (call-with-output-file (build-path state-root "init.rkt")
     #:exists 'truncate/replace
     (lambda (output)
       (display "#lang racket/base\n(define selected-theme 'night)\n" output)))
   (call-with-output-file document-path
     #:exists 'truncate/replace
     (lambda (output) (display "Hello from Odra" output)))
   (define command
     (string-append
      "stty rows 24 cols 100; "
      "exec env -u NO_COLOR COLORTERM=truecolor "
      "TERM=xterm-256color XDG_DATA_HOME="
      (shell-quote (path->string data-base))
      " XDG_CACHE_HOME="
      (shell-quote (path->string cache-base))
      " XDG_STATE_HOME="
      (shell-quote (path->string runtime-state-base))
      " ODRA_DEVELOPMENT_XDG_CONFIG_HOME="
      (shell-quote (path->string configuration-base))
      " " (shell-quote odra-path) " "
      (shell-quote (path->string document-path))))
   (define-values (process output input error-output)
     (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
   (define transcript (open-output-bytes))
   (wait-for-terminal-readiness!
    'package-canary process output input error-output transcript
    #:content-marker #"Hello from Odra")
   (define output-reader (thread (lambda () (copy-port output transcript))))
   (define (transcript-tail)
     (define bytes (get-output-bytes transcript))
     (subbytes bytes (max 0 (- (bytes-length bytes) 4096))))
   (define (send bytes)
     (with-handlers
         ([exn:fail?
           (lambda (observed)
             (raise-user-error
              'package-canary
              "editor input failed: ~a; status=~s; transcript tail: ~s"
              (exn-message observed) (subprocess-status process)
              (transcript-tail)))])
       (write-bytes bytes input)
       (flush-output input)))
   (define (wait-for-transcript marker [start 0])
     (define deadline (+ (current-inexact-milliseconds) 10000))
     (let wait ()
       (define content (get-output-bytes transcript))
       (cond
         [(and (<= start (bytes-length content))
               (regexp-match? (byte-regexp (regexp-quote marker))
                              (subbytes content start)))
          (void)]
         [(< (current-inexact-milliseconds) deadline)
          (sleep 0.05)
          (wait)]
         [else
         (subprocess-kill process #t)
         (subprocess-wait process)
         (raise-user-error 'package-canary
                            "editor did not report ~s; transcript tail: ~s"
                            marker (transcript-tail))])))
   (define discovery-start
     (bytes-length (get-output-bytes transcript)))
   (send #"\33xpackage-discover\r")
   (wait-for-transcript #"Packages" discovery-start)
   (define filter-start
     (bytes-length (get-output-bytes transcript)))
   (send #"odra.rot13@0.1.0")
   (wait-for-transcript #"Packages 1/1 Search:" filter-start)
   (wait-for-transcript #"odra.rot13@0.1.0" filter-start)
   (define install-start
     (bytes-length (get-output-bytes transcript)))
   (send #"\r")
   (wait-for-transcript #"Confirm: [y]es [n]o" install-start)
   (define enable-start
     (bytes-length (get-output-bytes transcript)))
   (send #"y")
   (wait-for-transcript #"Enabled odra.rot13@0.1.0" enable-start)
   (define direct-install-start
     (bytes-length (get-output-bytes transcript)))
   (send #"\33xpackage-install\r")
   (wait-for-transcript #"Packages" direct-install-start)
   (define direct-filter-start
     (bytes-length (get-output-bytes transcript)))
   (send #"odra.rot13@0.1.1")
   (wait-for-transcript #"Packages 1/1 Search:" direct-filter-start)
   (wait-for-transcript #"odra.rot13@0.1.1" direct-filter-start)
   (define direct-selection-start
     (bytes-length (get-output-bytes transcript)))
   (send #"\r")
   (wait-for-transcript
    #"Installed odra.rot13@0.1.1 in disabled state"
    direct-selection-start)
   (send
    (bytes-append
     control-space
     (apply bytes-append (make-list 15 right))
     #"\33xrot13-region\r"))
   (sleep 0.5)
   (send (bytes-append control-x control-s))
   (sleep 0.5)
   (send exit-sequence)
   (unless (sync/timeout 15 process)
     (subprocess-kill process #t)
     (subprocess-wait process)
     (raise-user-error
      'package-canary
      "editor did not exit; transcript tail: ~s"
      (transcript-tail)))
   (thread-wait output-reader)
   (define output-bytes (get-output-bytes transcript))
   (define error-bytes (port->bytes error-output))
   (close-output-port input)
   (close-input-port output)
   (close-input-port error-output)

   (check-equal? (subprocess-status process) 0)
   (check-equal? error-bytes #"")
   (check-true
    (regexp-match? (byte-regexp (regexp-quote restoration-sequence))
                   output-bytes))
   (check-equal? (file->string document-path) "Uryyb sebz Bqen"))
 (lambda ()
   (when (directory-exists? sandbox)
     (delete-directory/files sandbox))))
