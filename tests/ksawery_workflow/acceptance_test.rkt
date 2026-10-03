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
(check-not-false script-path "util-linux script is required for Ksawery workflow scenarios")
(define git-path (find-executable-path "git"))
(check-not-false git-path "git is required for Ksawery workflow scenarios")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define meta-x #"\33x")
(define enter (bytes 13))
(define tab (bytes 9))
(define up #"\33[A")
(define down #"\33[B")
(define exit-editor (bytes-append (bytes 24) (bytes 3)))
(define restoration #"\33[?25h\33[0m")

(define (contains? output value)
  (regexp-match? (byte-regexp (regexp-quote value)) output))

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define root (make-temporary-file "odra-ksawery-workflow-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define home (build-path root "home"))
   (define repository (build-path home "repository"))
   (define start-path (build-path repository "start.odin"))
   (define first-group-path (build-path repository "group-one.txt"))
   (define second-group-path (build-path repository "group-two.txt"))
   (define discard-path (build-path repository "discard.txt"))
   (define start-baseline
     (string-append
      "package ksawery_acceptance\n\n"
      "first := \"baseline\"\n"
      "context_01 := 1\n"
      "context_02 := 2\n"
      "context_03 := 3\n"
      "context_04 := 4\n"
      "context_05 := 5\n"
      "context_06 := 6\n"
      "context_07 := 7\n"
      "context_08 := 8\n"
      "second := \"baseline\"\n"))
   (define start-changed
     (string-append
      "package ksawery_acceptance\n\n"
      "first := \"changed\"\n"
      "context_01 := 1\n"
      "context_02 := 2\n"
      "context_03 := 3\n"
      "context_04 := 4\n"
      "context_05 := 5\n"
      "context_06 := 6\n"
      "context_07 := 7\n"
      "context_08 := 8\n"
      "second := \"changed\"\n"))
   (define (write-file! path content)
     (call-with-output-file path
       #:exists 'truncate
       (lambda (output) (display content output))))
   (make-directory* (build-path home ".config" "odra"))
   (make-directory repository)
   (define (git! . arguments)
     (parameterize ([current-directory repository])
       (apply system* git-path arguments)))
   (check-true (git! "init" "-q"))
   (check-true (git! "config" "user.name" "Odra Test"))
   (check-true (git! "config" "user.email" "odra@example.invalid"))
   (write-file! start-path start-baseline)
   (write-file! first-group-path "group one baseline\n")
   (write-file! second-group-path "group two baseline\n")
   (write-file! discard-path "discard baseline\n")
   (check-true (git! "add" "--" "start.odin" "group-one.txt" "group-two.txt" "discard.txt"))
   (check-true (git! "commit" "-qm" "baseline"))
   (write-file! start-path start-changed)

   (define command
     (string-append
      "stty rows 24 cols 100; XDG_CONFIG_HOME="
      (shell-quote (path->string (build-path home ".config")))
      " HOME="
      (shell-quote (path->string home))
      " exec env NO_COLOR=1 TERM=xterm-256color "
      (shell-quote odra-path)
      " "
      (shell-quote (path->string start-path))))
   (define-values (process output input error-output)
     (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
   (define transcript (open-output-bytes))
   (define error-result (make-channel))
   (wait-for-terminal-readiness!
    'ksawery-workflow process output input error-output transcript
    #:content-marker #"ksawery_acceptance")
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
   (define (refresh!)
     (send #"r")
     (send #"r")
     (send #"r"))
   (define (await-from value start [seconds 12])
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

   (define status-start (bytes-length (get-output-bytes transcript)))
   (send (bytes-append meta-x #"ksawery-status" enter))
   (await-from #"Ksawery Status" status-start)
   (await-from #"Unstaged" status-start)
   (send down)
   (define detail-start (bytes-length (get-output-bytes transcript)))
   (send tab)
   (await-from #"-first := \"baseline\"" detail-start)
   (await-from #"+second := \"changed\"" detail-start)
   (send down)
   (define partial-stage-start (bytes-length (get-output-bytes transcript)))
   (send #"s")
   (await-from #"Hunk action Stage completed" partial-stage-start)
   (await-from #"Staged (1)" partial-stage-start)
   (send down)
   (send down)
   (send down)
   (define indexed-detail-start (bytes-length (get-output-bytes transcript)))
   (send tab)
   (await-from #"+first := \"changed\"" indexed-detail-start)
   (send down)
   (define partial-unstage-start (bytes-length (get-output-bytes transcript)))
   (send #"u")
   (await-from #"Hunk action Unstage completed" partial-unstage-start)
   (sleep 0.5)
   (check-true (git! "diff" "--cached" "--quiet"))
   (check-false (git! "diff" "--quiet"))

   (write-file! start-path start-baseline)
   (write-file! first-group-path "group one changed\n")
   (write-file! second-group-path "group two changed\n")
   (define group-refresh-start (bytes-length (get-output-bytes transcript)))
   (refresh!)
   (await-from #"group-one.txt" group-refresh-start)
   (await-from #"group-two.txt" group-refresh-start)
   (send down)
   (send #"m")
   (send down)
   (define group-mark-start (bytes-length (get-output-bytes transcript)))
   (send #"m")
   (await-from #"Marked: 2 paths for Stage" group-mark-start)
   (define group-stage-start (bytes-length (get-output-bytes transcript)))
   (send #"s")
   (await-from #"Grouped action Stage completed" group-stage-start)
   (await-from #"Staged (2)" group-stage-start)
   (await-from #"Action: u unstage selected path" group-stage-start)
   (send up)
   (send #"m")
   (send down)
   (define group-unstage-mark-start (bytes-length (get-output-bytes transcript)))
   (send #"m")
   (await-from #"Marked: 2 paths for Unstage" group-unstage-mark-start)
   (define group-unstage-start (bytes-length (get-output-bytes transcript)))
   (send #"u")
   (await-from #"Grouped action Unstage completed" group-unstage-start)
   (await-from #"Action: s stage or d discard selected path" group-unstage-start)
   (check-true (git! "diff" "--cached" "--quiet"))
   (check-false (git! "diff" "--quiet"))

   (write-file! first-group-path "group one baseline\n")
   (write-file! second-group-path "group two baseline\n")
   (write-file! discard-path "discard changed\n")
   (define discard-refresh-start (bytes-length (get-output-bytes transcript)))
   (refresh!)
   (await-from #"discard.txt" discard-refresh-start)
   (send down)
   (await-from #"Action: s stage or d discard selected path" discard-refresh-start)
   (define discard-prompt-start (bytes-length (get-output-bytes transcript)))
   (send #"d")
   (await-from #"Discard working-tree changes in discard.txt?" discard-prompt-start)
   (sleep 0.5)
   (define discard-cancel-start (bytes-length (get-output-bytes transcript)))
   (send #"n")
   (await-from #"Repository discard cancelled" discard-cancel-start)
   (check-equal? (file->string discard-path) "discard changed\n")
   (define discard-confirm-start (bytes-length (get-output-bytes transcript)))
   (send #"d")
   (await-from #"Discard working-tree changes in discard.txt?" discard-confirm-start)
   (sleep 0.5)
   (send #"y")
   (await-from #"Discard completed" discard-confirm-start)
   (await-from #"Working tree clean" discard-confirm-start)
   (check-equal? (file->string discard-path) "discard baseline\n")

   (define restore-start (bytes-length (get-output-bytes transcript)))
   (send #"q")
   (await-from #"ksawery_acceptance" restore-start)
   (await-from #"first := \"changed\"" restore-start)

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
   (check-true (contains? output-bytes #"Ksawery Status"))
   (check-true (contains? output-bytes #"Hunk action Stage completed"))
   (check-true (contains? output-bytes #"Hunk action Unstage completed"))
   (check-true (contains? output-bytes #"Grouped action Stage completed"))
   (check-true (contains? output-bytes #"Grouped action Unstage completed"))
   (check-true (contains? output-bytes #"Repository discard cancelled"))
   (check-true (contains? output-bytes #"Discard completed"))
   (check-true (contains? output-bytes restoration))
   (check-true (git! "diff" "--cached" "--quiet"))
   (check-true (git! "diff" "--quiet"))
   (check-equal? (file->string start-path) start-baseline))
 (lambda ()
   (when (directory-exists? root)
     (delete-directory/files root))))
