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
(check-not-false script-path "util-linux script is required for Ksawery process workflow acceptance")
(define git-path (find-executable-path "git"))
(check-not-false git-path "git is required for Ksawery process workflow acceptance")
(define mkfifo-path (find-executable-path "mkfifo"))
(check-not-false mkfifo-path "mkfifo is required for Ksawery process workflow acceptance")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define meta-x #"\33x")
(define enter (bytes 13))
(define control-g (bytes 7))
(define down #"\33[B")
(define exit-editor (bytes-append (bytes 24) (bytes 3)))
(define restoration #"\33[?25h\33[0m")

(define (contains? output value)
  (regexp-match? (byte-regexp (regexp-quote value)) output))

(define (transcript-tail output [limit 8000])
  (define length (bytes-length output))
  (subbytes output (max 0 (- length limit))))

(define (report-transcript-tail output)
  (displayln (bytes->string/utf-8 (transcript-tail output) #\?)
             (current-error-port)))

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define root (make-temporary-file "odra-ksawery-process-workflow-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define home (build-path root "home"))
   (define repository (build-path home "repository"))
   (define start-path (build-path repository "start.odin"))
   (define change-path (build-path repository "change.txt"))
   (define bin-directory (build-path root "bin"))
   (define git-wrapper (build-path bin-directory "git"))
   (define arm-path (build-path root "arm-indeterminate"))
   (define fail-path (build-path root "fail-next-status"))
   (define index-path (build-path repository ".git" "index"))
   (define saved-index-path (build-path repository ".git" "index.process-acceptance-saved"))
   (define start-content
     "package ksawery_process_acceptance\n\nphase := \"baseline\"\n")
   (define (write-file! path content)
     (call-with-output-file path
       #:exists 'truncate
       (lambda (output) (display content output))))
   (define (git! . arguments)
     (parameterize ([current-directory repository])
       (apply system* git-path arguments)))
   (define wrapper-content
     (string-append
      "#!/bin/sh\n"
      "REAL_GIT=" (shell-quote (path->string git-path)) "\n"
      "ARM=" (shell-quote (path->string arm-path)) "\n"
      "FAIL=" (shell-quote (path->string fail-path)) "\n"
      "if [ -f \"$ARM\" ]; then\n"
      "  case \" $* \" in\n"
      "    *\" reset \"*)\n"
      "      \"$REAL_GIT\" \"$@\"\n"
      "      result=$?\n"
      "      if [ \"$result\" -eq 0 ]; then rm -f \"$ARM\"; : > \"$FAIL\"; fi\n"
      "      exit \"$result\"\n"
      "      ;;\n"
      "  esac\n"
      "fi\n"
      "if [ -f \"$FAIL\" ]; then\n"
      "  case \" $* \" in\n"
      "    *\" status \"*)\n"
      "      rm -f \"$FAIL\"\n"
      "      dd if=/dev/zero bs=1024 count=80 2>/dev/null | tr '\\000' 'x' >&2\n"
      "      printf '\\nforced post-effect status failure\\n' >&2\n"
      "      exit 1\n"
      "      ;;\n"
      "  esac\n"
      "fi\n"
      "exec \"$REAL_GIT\" \"$@\"\n"))

   (make-directory* (build-path home ".config" "odra"))
   (make-directory repository)
   (make-directory bin-directory)
   (check-true (git! "init" "-q" "-b" "main"))
   (check-true (git! "config" "user.name" "Odra Test"))
   (check-true (git! "config" "user.email" "odra@example.invalid"))
   (check-true (git! "config" "commit.gpgSign" "false"))
   (write-file! start-path start-content)
   (write-file! change-path "baseline\n")
   (check-true (git! "add" "--" "start.odin" "change.txt"))
   (check-true (git! "commit" "-qm" "baseline"))
   (write-file! git-wrapper wrapper-content)
   (file-or-directory-permissions git-wrapper #o755)

   (define command
     (string-append
      "stty rows 30 cols 140; XDG_CONFIG_HOME="
      (shell-quote (path->string (build-path home ".config")))
      " HOME="
      (shell-quote (path->string home))
      " PATH="
      (shell-quote (string-append (path->string bin-directory) ":" (or (getenv "PATH") "")))
      " exec env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor "
      (shell-quote odra-path)
      " "
      (shell-quote (path->string start-path))))
   (define-values (process output input error-output)
     (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
   (define transcript (open-output-bytes))
   (define error-result (make-channel))
   (wait-for-terminal-readiness!
    'ksawery-process-workflow process output input error-output transcript
    #:content-marker #"ksawery_process_acceptance")
   (define output-reader (thread (lambda () (copy-port output transcript))))
   (thread (lambda () (channel-put error-result (port->bytes error-output))))
   (define (send bytes [pause 0.25])
     (with-handlers ([exn:fail?
                      (lambda (failure)
                        (report-transcript-tail (get-output-bytes transcript))
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
          (report-transcript-tail current)
          (fail-check (format "timed out waiting for ~s" value))]
         [(sync/timeout 0 process)
          (define process-error (channel-get error-result))
          (report-transcript-tail current)
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
   (await-from #"Working tree clean" status-start)

   (rename-file-or-directory index-path saved-index-path)
   (check-true (system* mkfifo-path index-path))
   (define progress-start (bytes-length (get-output-bytes transcript)))
   (send #"r" 0.1)
   (await-from #"Refreshing repository status" progress-start)
   (define cancellation-start (bytes-length (get-output-bytes transcript)))
   (send (bytes-append #"$" control-g) 0.1)
   (await-from #"Cancelled_Before_Effect" cancellation-start)
   (await-from #"Ksawery Processes" cancellation-start)
   (await-from #"Retained: Repository Status" cancellation-start)
   (send enter)
   (await-from #"Phase: Cancelling repository operation" cancellation-start)
   (delete-file index-path)
   (rename-file-or-directory saved-index-path index-path)
   (send #"q")
   (await-from #"Ksawery Status" cancellation-start)

   (write-file! change-path "verified mutation\n")
   (define mutation-refresh-start (bytes-length (get-output-bytes transcript)))
   (send #"r")
   (await-from #"change.txt" mutation-refresh-start)
   (send down)
   (define verified-start (bytes-length (get-output-bytes transcript)))
   (send #"s")
   (await-from #"Index action Stage completed" verified-start)
   (check-false (git! "diff" "--cached" "--quiet"))
   (check-true (git! "diff" "--quiet"))
   (send #"$")
   (await-from #"Retained: Stage Repository Path" verified-start)
   (await-from #"[Verified_Success]" verified-start)
   (send down)
   (send enter)
   (await-from #"Outcome: Repository mutation verified" verified-start)
   (send #"q")
   (await-from #"Ksawery Status" verified-start)

   (write-file! arm-path "armed\n")
   (define indeterminate-start (bytes-length (get-output-bytes transcript)))
   (send #"u")
   (await-from #"Status observation failed: Output_Limit" indeterminate-start)
   (check-true (git! "diff" "--cached" "--quiet"))
   (check-false (git! "diff" "--quiet"))
   (send #"$")
   (await-from #"Retained: Unstage Repository Path" indeterminate-start)
   (await-from #"[Indeterminate]" indeterminate-start)
   (send enter)
   (await-from #"Outcome: Repository mutation outcome is indeterminate" indeterminate-start)
   (send #"q")
   (await-from #"Ksawery Status" indeterminate-start)

   (define canvas-return-start (bytes-length (get-output-bytes transcript)))
   (send #"q")
   (await-from #"ksawery_process_acceptance" canvas-return-start)
   (await-from #"phase := " canvas-return-start)
   (await-from #"\"baseline\"" canvas-return-start)

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
   (check-true (contains? output-bytes #"Ksawery Processes"))
   (check-true (contains? output-bytes #"Cancelled_Before_Effect"))
   (check-true (contains? output-bytes #"[Verified_Success]"))
   (check-true (contains? output-bytes #"Repository mutation outcome is indeterminate"))
   (check-true (contains? output-bytes #"Status observation failed: Output_Limit"))
   (check-true (contains? output-bytes restoration)))
 (lambda ()
   (when (directory-exists? root)
     (delete-directory/files root))))
