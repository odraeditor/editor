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
(check-not-false script-path "util-linux script is required for Ksawery refs synchronization acceptance")
(define git-path (find-executable-path "git"))
(check-not-false git-path "git is required for Ksawery refs synchronization acceptance")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define meta-x #"\33x")
(define enter (bytes 13))
(define control-enter #"\33[13;5u")
(define up #"\33[A")
(define down #"\33[B")
(define exit-editor (bytes-append (bytes 24) (bytes 3)))
(define restoration #"\33[?25h\33[0m")

(define (contains? output value)
  (regexp-match? (byte-regexp (regexp-quote value)) output))

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define root (make-temporary-file "odra-ksawery-refs-acceptance-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define home (build-path root "home"))
   (define remote (build-path root "origin.git"))
   (define seed (build-path root "seed"))
   (define repository (build-path home "repository"))
   (define start-path (build-path repository "start.odin"))
   (define remote-path (build-path seed "remote.txt"))
   (define local-path (build-path repository "local.txt"))
   (define (write-file! path content)
     (call-with-output-file path
       #:exists 'truncate
       (lambda (output) (display content output))))
   (define (git-at! directory . arguments)
     (parameterize ([current-directory directory])
       (apply system* git-path arguments)))
   (define (git-text directory . arguments)
     (parameterize ([current-directory directory])
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
   (make-directory seed)
   (check-true (git-at! root "init" "--bare" "-q" "--initial-branch=main" remote))
   (check-true (git-at! seed "init" "-q" "-b" "main"))
   (check-true (git-at! seed "config" "user.name" "Odra Test"))
   (check-true (git-at! seed "config" "user.email" "odra@example.invalid"))
   (check-true (git-at! seed "config" "commit.gpgSign" "false"))
   (write-file! (build-path seed "start.odin")
                "package ksawery_refs_acceptance\n\nphase := \"baseline\"\n")
   (check-true (git-at! seed "add" "--" "start.odin"))
   (check-true (git-at! seed "commit" "-qm" "baseline"))
   (check-true (git-at! seed "remote" "add" "origin" remote))
   (check-true (git-at! seed "push" "-q" "-u" "origin" "main"))
   (make-directory repository)
   (check-true (git-at! repository "init" "-q" "-b" "fixture"))
   (check-true (git-at! repository "config" "user.name" "Odra Test"))
   (check-true (git-at! repository "config" "user.email" "odra@example.invalid"))
   (check-true (git-at! repository "config" "commit.gpgSign" "false"))
   (check-true (git-at! repository "remote" "add" "origin" remote))
   (check-true (git-at! repository "fetch" "-q" "origin"
                        "refs/heads/main:refs/remotes/origin/main"))
   (check-true (git-at! repository "checkout" "-q" "-b" "main" "--track"
                        "refs/remotes/origin/main"))
   (write-file! remote-path "remote update\n")
   (check-true (git-at! seed "add" "--" "remote.txt"))
   (check-true (git-at! seed "commit" "-qm" "remote update"))
   (check-true (git-at! seed "push" "-q" "origin" "main"))

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
    'ksawery-refs-synchronization process output input error-output transcript
    #:content-marker #"ksawery_refs_acceptance")
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
   (define (await-from value start [seconds 20])
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
   (await-from #"Working tree clean" status-start)
   (define refs-start (bytes-length (get-output-bytes transcript)))
   (send #"b")
   (await-from #"Ksawery Refs" refs-start)
   (await-from #"Branch: refs/heads/main" refs-start)
   (await-from #"Remote branch: refs/remotes/origin/main" refs-start)
   (await-from #"Remote: origin" refs-start)

   (move! down 2)
   (define fetch-start (bytes-length (get-output-bytes transcript)))
   (send #"g")
   (await-from #"Fetch result: Completed" fetch-start)
   (sleep 1.0)
   (check-equal? (git-text repository "rev-parse" "refs/remotes/origin/main")
                 (git-text seed "rev-parse" "HEAD"))

   (check-true (git-at! repository "merge" "-q" "--ff-only" "refs/remotes/origin/main"))
   (write-file! local-path "local publication\n")
   (check-true (git-at! repository "add" "--" "local.txt"))
   (check-true (git-at! repository "commit" "-qm" "local publication"))
   (define refresh-start (bytes-length (get-output-bytes transcript)))
   (send #"r" 1.0)
   (await-from #"Tracking: refs/heads/main -> refs/remotes/origin/main Ahead +1 -0" refresh-start)
   (await-from #"Action: =/i/I merge; e/E rebase/autosquash; S switch; R rename; D delete; m mark push; r refresh" refresh-start)
   (sleep 0.5)
   (send #"m")
   (move! down 3)
   (define push-start (bytes-length (get-output-bytes transcript)))
   (send #"p")
   (await-from #"Ksawery Push Confirmation" push-start)
   (await-from #"Destination: refs/heads/main" push-start)
   (send control-enter)
   (await-from #"Push result: Completed" push-start)
   (sleep 1.0)
   (check-equal? (git-text repository "rev-parse" "HEAD")
                 (git-text root "--git-dir" remote "rev-parse" "refs/heads/main"))

   (define branch-start (bytes-length (get-output-bytes transcript)))
   (send #"n")
   (await-from #"Ksawery Create Local Branch" branch-start)
   (send #"topic")
   (send enter)
   (await-from #"Ksawery Local Branch Confirmation" branch-start)
   (await-from #"New name: topic" branch-start)
   (send control-enter)
   (await-from #"Branch result: Completed" branch-start)
   (sleep 1.0)
   (check-true (git-at! repository "show-ref" "--verify" "--quiet" "refs/heads/topic"))

   (define tag-start (bytes-length (get-output-bytes transcript)))
   (send #"t")
   (await-from #"Ksawery Create Local Tag" tag-start)
   (send #"local-v1")
   (send enter)
   (await-from #"Ksawery Local Tag Confirmation" tag-start)
   (await-from #"New tag: local-v1" tag-start)
   (send control-enter)
   (await-from #"Tag result: Completed" tag-start)
   (sleep 1.0)
   (check-true (git-at! repository "show-ref" "--verify" "--quiet" "refs/tags/local-v1"))

   (move! down 4)
   (define delete-start (bytes-length (get-output-bytes transcript)))
   (send #"T")
   (await-from #"Ksawery Local Tag Confirmation" delete-start)
   (send control-enter)
   (await-from #"Tag result: Completed" delete-start)
   (sleep 1.0)
   (check-false (git-at! repository "show-ref" "--verify" "--quiet" "refs/tags/local-v1"))

   (define status-return-start (bytes-length (get-output-bytes transcript)))
   (send #"q")
   (await-from #"Ksawery Status" status-return-start)
   (define canvas-return-start (bytes-length (get-output-bytes transcript)))
   (send #"q")
   (await-from #"ksawery_refs_acceptance" canvas-return-start)
   (await-from #"phase := " canvas-return-start)
   (await-from #"baseline" canvas-return-start)

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
   (check-true (contains? output-bytes #"Ksawery Refs"))
   (check-true (contains? output-bytes #"Fetch result: Completed"))
   (check-true (contains? output-bytes #"Push result: Completed"))
   (check-true (contains? output-bytes #"Branch result: Completed"))
   (check-true (contains? output-bytes #"Tag result: Completed"))
   (check-true (contains? output-bytes restoration)))
 (lambda ()
   (when (directory-exists? root)
     (delete-directory/files root))))
