#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         racket/path
         racket/port
         racket/string
         racket/system
         "../support/terminal-readiness.rkt")

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for Ksawery commit revision acceptance")
(define git-path (find-executable-path "git"))
(check-not-false git-path "git is required for Ksawery commit revision acceptance")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define meta-x #"\33x")
(define enter (bytes 13))
(define control-g (bytes 7))
(define control-enter #"\33[13;5u")
(define up #"\33[A")
(define down #"\33[B")
(define exit-editor (bytes-append (bytes 24) (bytes 3)))
(define restoration #"\33[?25h\33[0m")

(define (contains? output value)
  (regexp-match? (byte-regexp (regexp-quote value)) output))

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define root (make-temporary-file "odra-ksawery-commit-revision-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define home (build-path root "home"))
   (define repository (build-path home "repository"))
   (define start-path (build-path repository "start.odin"))
   (define root-content
     "package ksawery_commit_acceptance\n\nphase := \"root\"\n")
   (define head-content
     "package ksawery_commit_acceptance\n\nphase := \"replaceable\"\n")
   (define normal-content
     "package ksawery_commit_acceptance\n\nphase := \"normal\"\n")
   (define fixup-content
     "package ksawery_commit_acceptance\n\nphase := \"fixup\"\n")
   (define (write-file! path content)
     (call-with-output-file path
       #:exists 'truncate
       (lambda (output) (display content output))))
   (define (git! . arguments)
     (parameterize ([current-directory repository])
       (apply system* git-path arguments)))
   (define (git-text . arguments)
     (parameterize ([current-directory repository])
       (define-values (process output input error-output)
         (apply subprocess #f #f #f git-path arguments))
       (close-output-port input)
       (define result (port->string output))
       (define diagnostic (port->string error-output))
       (subprocess-wait process)
       (close-input-port output)
       (close-input-port error-output)
       (check-equal? (subprocess-status process) 0 diagnostic)
       (string-trim result)))

   (make-directory* (build-path home ".config" "odra"))
   (make-directory repository)
   (check-true (git! "init" "-q" "-b" "main"))
   (check-true (git! "config" "user.name" "Odra Test"))
   (check-true (git! "config" "user.email" "odra@example.invalid"))
   (check-true (git! "config" "commit.gpgSign" "false"))
   (write-file! start-path root-content)
   (check-true (git! "add" "--" "start.odin"))
   (check-true (git! "commit" "-qm" "root target"))
   (write-file! start-path head-content)
   (check-true (git! "add" "--" "start.odin"))
   (check-true (git! "commit" "-qm" "replaceable head"))
   (define root-revision (git-text "rev-parse" "HEAD~1"))
   (write-file! start-path normal-content)
   (check-true (git! "add" "--" "start.odin"))

   (define command
     (string-append
      "stty rows 30 cols 140; XDG_CONFIG_HOME="
      (shell-quote (path->string (build-path home ".config")))
      " HOME="
      (shell-quote (path->string home))
      " exec env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor "
      (shell-quote odra-path)
      " "
      (shell-quote (path->string start-path))))
   (define-values (process output input error-output)
     (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
   (define transcript (open-output-bytes))
   (define error-result (make-channel))
   (wait-for-terminal-readiness!
    'ksawery-commit-revision process output input error-output transcript
    #:content-marker #"ksawery_commit_acceptance")
   (define output-reader (thread (lambda () (copy-port output transcript))))
   (thread (lambda () (channel-put error-result (port->bytes error-output))))
   (define (send bytes [pause 0.25])
     (with-handlers ([exn:fail?
                      (lambda (failure)
                        (displayln (bytes->string/utf-8 (get-output-bytes transcript) #\?)
                                   (current-error-port))
                        (raise failure))])
       (write-bytes bytes input)
       (flush-output input))
     (sleep pause))
   (define (await-from value start [seconds 15])
     (define deadline (+ (current-inexact-milliseconds) (* seconds 1000)))
     (let wait ()
       (define current (get-output-bytes transcript))
       (cond
         [(and (<= start (bytes-length current))
               (contains? (subbytes current start) value))
          #t]
         [(>= (current-inexact-milliseconds) deadline)
          (displayln (bytes->string/utf-8 current #\?) (current-error-port))
          (fail-check (format "timed out waiting for ~s" value))]
         [(sync/timeout 0 process)
          (define process-error (channel-get error-result))
          (displayln (bytes->string/utf-8 current #\?) (current-error-port))
          (fail-check
           (format "editor exited (~a) while waiting for ~s: ~a"
                   (subprocess-status process)
                   value
                   (bytes->string/utf-8 process-error #\?)))]
         [else
          (sleep 0.05)
          (wait)])))
   (define (move! key count)
     (for ([ignored (in-range count)])
       (send key 0.1)))

   (define status-start (bytes-length (get-output-bytes transcript)))
   (send (bytes-append meta-x #"ksawery-status" enter))
   (await-from #"Ksawery Status" status-start)
   (await-from #"Staged (1)" status-start)

   (define normal-compose-start (bytes-length (get-output-bytes transcript)))
   (send #"c")
   (await-from #"Ksawery Commit Message" normal-compose-start)
   (define normal-cancel-start (bytes-length (get-output-bytes transcript)))
   (send control-g)
   (await-from #"Commit composition cancelled" normal-cancel-start)
   (define normal-commit-start (bytes-length (get-output-bytes transcript)))
   (send #"c")
   (await-from #"Ksawery Commit Message" normal-commit-start)
   (send #"normal acceptance")
   (send control-enter)
   (await-from #"Repository commit completed" normal-commit-start)
   (check-equal? (git-text "log" "-1" "--format=%s") "normal acceptance")

   (define detail-start (bytes-length (get-output-bytes transcript)))
   (send (bytes 9))
   (await-from #"Ksawery Revision Inspection" detail-start)
   (await-from #"normal acceptance" detail-start)
   (define detail-return-start (bytes-length (get-output-bytes transcript)))
   (send #"q")
   (await-from #"Ksawery History" detail-return-start)

   (move! down 4)
   (define mark-start (bytes-length (get-output-bytes transcript)))
   (send #"m")
   (await-from #"Range base:" mark-start)
   (move! up 4)
   (define range-start (bytes-length (get-output-bytes transcript)))
   (send enter)
   (await-from #"Ksawery Revision Range" range-start)
   (define range-return-start (bytes-length (get-output-bytes transcript)))
   (send #"q")
   (await-from #"Ksawery History" range-return-start)

   (define amend-start (bytes-length (get-output-bytes transcript)))
   (send #"A")
   (await-from #"Ksawery Commit Message" amend-start)
   (await-from #"Mode: amend the checked repository HEAD" amend-start)
   (send #"amended acceptance")
   (define amend-confirmation-start (bytes-length (get-output-bytes transcript)))
   (send control-enter)
   (await-from #"Ksawery Amend Confirmation" amend-confirmation-start)
   (await-from #"Observed HEAD:" amend-confirmation-start)
   (await-from #"Publication safety is not inferred" amend-confirmation-start)
   (define amend-complete-start (bytes-length (get-output-bytes transcript)))
   (send control-enter)
   (await-from #"Repository commit completed" amend-complete-start)
   (await-from #"Amended:" amend-complete-start)
   (check-equal? (git-text "log" "-1" "--format=%s") "amended acceptance")

   (define status-return-start (bytes-length (get-output-bytes transcript)))
   (send #"q")
   (await-from #"Ksawery Status" status-return-start)
   (write-file! start-path fixup-content)
   (check-true (git! "add" "--" "start.odin"))
   (define status-refresh-start (bytes-length (get-output-bytes transcript)))
   (send #"r")
   (await-from #"Staged (1)" status-refresh-start)
   (define history-refresh-start (bytes-length (get-output-bytes transcript)))
   (send #"h")
   (await-from #"Ksawery History" history-refresh-start)
   (move! down 4)
   (define fixup-start (bytes-length (get-output-bytes transcript)))
   (send #"F")
   (await-from #"Ksawery Commit Message" fixup-start)
   (await-from #"Mode: fixup for the selected exact revision" fixup-start)
   (await-from #"Fixup target:" fixup-start)
   (send #"forged subject")
   (define fixup-complete-start (bytes-length (get-output-bytes transcript)))
   (send control-enter)
   (await-from #"Repository commit completed" fixup-complete-start)
   (await-from #"Fixup created:" fixup-complete-start)
   (check-equal? (git-text "log" "-1" "--format=%s") "fixup! root target")
   (check-true (git! "merge-base" "--is-ancestor" root-revision "HEAD"))
   (check-equal? (git-text "rev-list" "--count" "HEAD") "4")

   (define restore-start (bytes-length (get-output-bytes transcript)))
   (send #"q")
   (await-from #"Ksawery Status" restore-start)
   (send #"q")
   (await-from #"ksawery_commit_acceptance" restore-start)
   (await-from #"start.odin" restore-start)

   (send exit-editor 0)
   (define completed? (sync/timeout 45 process))
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
   (check-true (contains? output-bytes #"Ksawery Status"))
   (check-true (contains? output-bytes #"Ksawery History"))
   (check-true (contains? output-bytes #"Ksawery Revision Inspection"))
   (check-true (contains? output-bytes #"Ksawery Revision Range"))
   (check-true (contains? output-bytes #"Repository commit completed"))
   (check-true (contains? output-bytes #"Fixup created:"))
   (check-true (contains? output-bytes #"\33[38;2;"))
   (check-true (contains? output-bytes restoration))
   (check-equal? (file->string start-path) fixup-content))
 (lambda ()
   (when (directory-exists? root)
     (delete-directory/files root))))
