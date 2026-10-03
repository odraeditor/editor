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
         "../support/terminal-readiness.rkt")

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for Maksym workflow scenarios")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define control-x (bytes 24))
(define control-c (bytes 3))
(define control-n (bytes 14))
(define enter (bytes 13))
(define delete-key #"\33[3~")
(define exit-editor (bytes-append control-x (bytes 3)))
(define restoration #"\33[?25h\33[0m\r\n")

(define (contains? output value)
  (regexp-match? (byte-regexp (regexp-quote value)) output))

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define root (make-temporary-file "odra-maksym-workflow-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define home (build-path root "home"))
   (define directory (build-path home "maksym-demo"))
   (define archive (build-path directory "archive"))
   (define child (build-path directory "folder"))
   (define discard-path (build-path directory "discard"))
   (define start-path (build-path home "start.odin"))
   (define file-path (build-path directory "notes.odin"))
   (make-directory* (build-path home ".config" "odra"))
   (make-directory directory)
   (make-directory archive)
   (make-directory child)
   (call-with-output-file start-path
     (lambda (output) (display "package start\n" output)))
   (call-with-output-file file-path
     (lambda (output) (display "package maksym_acceptance\n" output)))
   (call-with-output-file discard-path
     (lambda (output) (display "discard\n" output)))

   (define command
     (string-append
      "stty rows 18 cols 100; HOME="
      (shell-quote (path->string home))
      " exec "
      (shell-quote odra-path)
      " "
      (shell-quote (path->string start-path))))
   (define-values (process output input error-output)
     (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
   (define transcript (open-output-bytes))
   (define error-result (make-channel))
   (wait-for-terminal-readiness!
    'maksym-workflow process output input error-output transcript
    #:content-marker #"start.odin")
   (define output-reader (thread (lambda () (copy-port output transcript))))
   (thread (lambda () (channel-put error-result (port->bytes error-output))))
   (define (send bytes [pause 0.25])
     (with-handlers ([exn:fail?
                      (lambda (failure)
                        (subprocess-wait process)
                        (fprintf (current-error-port) "process status: ~a\n"
                                 (subprocess-status process))
                        (displayln (bytes->string/utf-8 (get-output-bytes transcript) #\?)
                                   (current-error-port))
                        (define failure-error (sync/timeout 2 error-result))
                        (when (bytes? failure-error)
                          (displayln (bytes->string/utf-8 failure-error #\?)
                                     (current-error-port)))
                        (raise failure))])
       (write-bytes bytes input)
       (flush-output input)
       (sleep pause)))
   (define (await-from value start [seconds 5])
     (define deadline (+ (current-inexact-milliseconds) (* seconds 1000)))
     (let wait ()
       (define current (get-output-bytes transcript))
       (cond
         [(and (<= start (bytes-length current))
               (contains? (subbytes current start) value))
          #t]
         [(>= (current-inexact-milliseconds) deadline)
          (displayln (bytes->string/utf-8 (get-output-bytes transcript) #\?)
                     (current-error-port))
          (fprintf (current-error-port) "process status: ~a\n" (subprocess-status process))
          (define failure-error (sync/timeout 2 error-result))
          (when (bytes? failure-error)
            (displayln (bytes->string/utf-8 failure-error #\?)
                       (current-error-port)))
          (fail-check (format "timed out waiting for ~s" value))]
         [else
          (sleep 0.05)
          (wait)])))
   (define (await value [seconds 5])
     (await-from value 0 seconds))
   (send (bytes-append control-x #"d"))
   (send #"maksym-demo")
   (send enter)
   (await #"Opened directory")
   (send #"s")
   (await #"Maksym sorted by name")
   (send #"j")
   (send #"notes")
   (send enter)
   (await #"Selected Maksym entry")
   (define editable-start (bytes-length (get-output-bytes transcript)))
   (send (bytes-append control-x (bytes 17)))
   (await-from #"Maksym filename editing enabled" editable-start)
   (await-from #"-rw" editable-start)
   (for ([index (in-range (bytes-length #"notes.odin"))])
     (send delete-key 0.05))
   (send #"renamed.odin")
   (send (bytes-append control-c control-c))
   (await #"Applied 1 rename(s), 0 move(s), and 0 permanent deletion(s)")
   (send enter)
   (await #"maksym_acceptance")
   (define reopen-start (bytes-length (get-output-bytes transcript)))
   (send (bytes-append control-x #"d"))
   (send #"maksym-demo")
   (send enter)
   (await-from #"discard" reopen-start)
   (define delete-jump-start (bytes-length (get-output-bytes transcript)))
   (send #"j")
   (send #"discard")
   (send enter)
   (await-from #"Selected Maksym entry" delete-jump-start)
   (define delete-edit-start (bytes-length (get-output-bytes transcript)))
   (send (bytes-append control-x (bytes 17)))
   (await-from #"Maksym filename editing enabled" delete-edit-start)
   (for ([index (in-range (bytes-length #"discard"))])
     (send delete-key 0.05))
   (send (bytes-append control-c control-c))
   (await #"Applied 0 rename(s), 0 move(s), and 1 permanent deletion(s)")
   (define move-jump-start (bytes-length (get-output-bytes transcript)))
   (send #"j")
   (send #"renamed")
   (send enter)
   (await-from #"Selected Maksym entry" move-jump-start)
   (define move-edit-start (bytes-length (get-output-bytes transcript)))
   (send (bytes-append control-x (bytes 17)))
   (await-from #"Maksym filename editing enabled" move-edit-start)
   (for ([index (in-range (bytes-length #"renamed.odin"))])
     (send delete-key 0.05))
   (send #"archive/moved.odin")
   (send (bytes-append control-c control-c))
   (await #"Applied 0 rename(s), 1 move(s), and 0 permanent deletion(s)")
   (send exit-editor 0)
   (define completed? (sync/timeout 30 process))
   (unless completed? (subprocess-kill process #t))
   (subprocess-wait process)
   (thread-wait output-reader)
   (define output-bytes (get-output-bytes transcript))
   (define error-bytes (channel-get error-result))
   (close-output-port input)
   (close-input-port output)
   (close-input-port error-output)

   (check-not-false completed? (bytes->string/utf-8 output-bytes #\?))
   (check-equal? (subprocess-status process) 0)
   (check-equal? error-bytes #"")
   (check-true (contains? output-bytes #"Open directory in Maksym [local]"))
   (check-true (contains? output-bytes #"Jump to Maksym entry [local]"))
   (check-true
    (contains? output-bytes
               (string->bytes/utf-8 (string-append (path->string directory) ":"))))
   (check-true (contains? output-bytes #"Maksym sorted by name"))
   (check-true (contains? output-bytes #"folder/"))
   (check-true (contains? output-bytes #"notes.odin"))
   (check-true (contains? output-bytes #"Applied 1 rename(s), 0 move(s), and 0 permanent deletion(s)"))
   (check-true (contains? output-bytes #"Applied 0 rename(s), 0 move(s), and 1 permanent deletion(s)"))
   (check-true (contains? output-bytes #"Applied 0 rename(s), 1 move(s), and 0 permanent deletion(s)"))
   (check-true (contains? output-bytes #"renamed.odin"))
   (check-true (contains? output-bytes #"maksym_acceptance"))
   (check-false (file-exists? discard-path))
   (check-false (file-exists? (build-path directory "renamed.odin")))
   (check-true (file-exists? (build-path archive "moved.odin")))
   (check-true (contains? output-bytes restoration)))
 (lambda ()
   (when (directory-exists? root)
     (delete-directory/files root))))
