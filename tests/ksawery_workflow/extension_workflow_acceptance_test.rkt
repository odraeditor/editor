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
         "../../src/hosting/personal-configuration-bridge.rkt"
         "../support/terminal-readiness.rkt")

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for Ksawery extension acceptance")
(define git-path (find-executable-path "git"))
(check-not-false git-path "git is required for Ksawery extension acceptance")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define meta-x #"\33x")
(define enter (bytes 13))
(define control-enter #"\33[13;5u")
(define down #"\33[B")
(define exit-editor (bytes-append (bytes 24) (bytes 3)))
(define restoration #"\33[?25h\33[0m")

(define (contains? output value)
  (regexp-match? (byte-regexp (regexp-quote value)) output))

(define (transcript-tail output [limit 12000])
  (define length (bytes-length output))
  (subbytes output (max 0 (- length limit))))

(define (report-transcript-tail output)
  (displayln (bytes->string/utf-8 (transcript-tail output) #\?)
             (current-error-port)))

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (word value offset)
  (integer-bytes->integer value #f #f offset (+ offset 8)))

(define (words . values)
  (apply bytes-append
         (map (lambda (value) (integer->integer-bytes value 8 #f #f)) values)))

(define (annotation-observation repository target generation)
  (define repository-bytes (string->bytes/utf-8 repository))
  (define record-bytes 104)
  (define repository-offset record-bytes)
  (define target-offset (+ repository-offset (bytes-length repository-bytes)))
  (define total (+ target-offset (bytes-length target)))
  (bytes-append
   (words 1 total 1 2 generation
          repository-offset (bytes-length repository-bytes) 0)
   (words 5 generation target-offset (bytes-length target) 0)
   repository-bytes target))

(define (provider-source generation)
  (string-append
   "#lang racket/base\n"
   "(require odra/commands)\n"
   "(provide odra-ksawery-contributor odra-ksawery-command-families)\n"
   "(define contributions\n"
   "  (list\n"
   "   (make-ksawery-contribution 1 'command.review 'command\n"
   "    #:observations '(status) #:authorities '(inspect invoke-declared-command))\n"
   "   (make-ksawery-contribution 2 'keymap.review 'keymap\n"
   "    #:observations '(status) #:authorities '(inspect present))\n"
   "   (make-ksawery-contribution 3 'status.acceptance 'status-section\n"
   "    #:observations '(status) #:authorities '(inspect present))\n"
   "   (make-ksawery-contribution 4 'annotation.acceptance 'annotation\n"
   "    #:observations '(refs)\n"
   "    #:authorities '(inspect present))\n"
   "   (make-ksawery-contribution 5 'family.workflow 'command-family\n"
   "    #:observations '(status)\n"
   "    #:authorities '(inspect request-core-action submit-external-operation))\n"
   "   (make-ksawery-contribution 6 'operation.inspect 'external-operation\n"
   "    #:observations '(status process)\n"
   "    #:authorities '(inspect submit-external-operation))\n"
   "   (make-ksawery-contribution 7 'conflict.guidance 'conflict-assistance\n"
   "    #:observations '(conflict) #:authorities '(inspect present assist-conflict))\n"
   "   (make-ksawery-contribution 8 'provider.conflict 'provider-role\n"
   "    #:provider-role 'conflict-assistance\n"
   "    #:observations '(status sequence conflict process)\n"
   "    #:authorities '(inspect present assist-conflict))))\n"
   "(define (status-provider observation)\n"
   "  (list\n"
   "   (make-ksawery-status-section\n"
   "    3 'status.acceptance \"Acceptance insight\"\n"
   "    (list\n"
   "     (make-ksawery-status-item\n"
   "      1 'status.ready \"Provider status active\" #:style 'success\n"
   "      #:command (make-ksawery-status-command-reference 'command.review))))))\n"
   "(define (annotation-provider observation)\n"
   "  (define targets (hash-ref observation 'targets))\n"
   "  (if (or (not (eq? (hash-ref observation 'family) 'refs))\n"
   "          (null? targets))\n"
   "      '()\n"
   "      (list\n"
   "       (make-ksawery-annotation\n"
   "        4 1 'annotation.acceptance (car targets)\n"
   "        #:label \"Acceptance annotation\"\n"
   "        #:detail \"Provider-owned ref projection\"\n"
   "        #:severity 'information\n"
   "        #:style 'information))))\n"
   "(define (conflict-provider contributor request observation)\n"
   "  (define provider\n"
   "    (make-ksawery-conflict-provider\n"
   "     contributor 8 11 13 'conflict.helper \"Acceptance conflict helper\"\n"
   "     '(text truncated) '(present-guidance) #:lifecycle 'active))\n"
   "  (make-ksawery-conflict-guidance\n"
   "   request provider\n"
   "   (string-append\n"
   "    \"Inspect \"\n"
   "    (ksawery-conflict-target-path\n"
   "     (ksawery-conflict-observation-target observation)))))\n"
   "(define odra-ksawery-contributor\n"
   "  (make-ksawery-contributor\n"
   "   'personal.acceptance \"Acceptance provider\" \"test-owned/init.rkt\" "
   (number->string generation)
   " contributions\n"
   "   #:limits (make-ksawery-extension-limits #:turn-deadline-milliseconds 2000)\n"
   "   #:status-provider status-provider\n"
   "   #:annotation-provider annotation-provider\n"
   "   #:conflict-assistance-provider conflict-provider))\n"
   "(define stage-action\n"
   "  (make-ksawery-command-action\n"
   "   1 'action.stage \"Stage selected path\" 'request-core-action '(status)\n"
   "   #:targets '(path) #:operation 'idle #:core-operation 'stage\n"
   "   #:mutates-repository? #t #:confirmation-required? #t))\n"
   "(define inspect-action\n"
   "  (make-ksawery-command-action\n"
   "   2 'action.inspect \"Inspect repository\" 'submit-external-operation '(status)\n"
   "   #:operation 'idle #:confirmation-required? #t\n"
   "   #:external-operation\n"
   "   (lambda (_context _values)\n"
   "     (make-ksawery-operation-plan\n"
   "      odra-ksawery-contributor 6 21 'operation.inspect \"Inspect repository\" 23\n"
   "      (make-ksawery-operation-git) (list \"status\" \"--short\") 'read-only\n"
   "      '(status process)\n"
   "      (make-ksawery-operation-verifier\n"
   "       'observation-available #:observation 'status)))))\n"
   "(define workflow-family\n"
   "  (make-ksawery-command-family\n"
   "   odra-ksawery-contributor 5 11 'family.workflow \"Acceptance workflows\" 17\n"
   "   '(status) '() (list stage-action inspect-action)))\n"
   "(define odra-ksawery-command-families (list workflow-family))\n"))

(define root (make-temporary-file "odra-ksawery-extension-acceptance-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define home (build-path root "home"))
   (define configuration-root (build-path home ".config" "odra"))
   (define init-path (build-path configuration-root "init.rkt"))
   (define repository (build-path home "repository"))
   (define start-path (build-path repository "start.odin"))
   (define conflict-path (build-path repository "conflict.txt"))
   (define start-baseline
     "package ksawery_extension_acceptance\n\nphase := \"baseline\"\n")
   (define start-changed
     "package ksawery_extension_acceptance\n\nphase := \"changed\"\n")
   (define (write-file! path content)
     (call-with-output-file path
       #:exists 'truncate/replace
       (lambda (output) (display content output))))
   (define (write-provider! generation)
     (write-file! init-path (provider-source generation)))
   (define (write-malformed-provider!)
     (write-file! init-path "#lang racket/base\n(define broken\n"))
   (define (git! . arguments)
     (parameterize ([current-directory repository])
       (apply system* git-path arguments)))
   (define (git-path-exists? name)
     (file-exists? (build-path repository ".git" name)))

   (make-directory* configuration-root)
   (make-directory repository)
   (check-true (git! "init" "-q" "-b" "main"))
   (check-true (git! "config" "user.name" "Odra Test"))
   (check-true (git! "config" "user.email" "odra@example.invalid"))
   (check-true (git! "config" "commit.gpgSign" "false"))
   (write-provider! 1)
   (define runtime-startup
     (runtime-personal-configuration-startup-batch
      (path->bytes configuration-root)))
   (check-true (car runtime-startup)
               (bytes->string/utf-8 (caddr runtime-startup)))
   (define runtime-startup-batch (cadr runtime-startup))
   (define runtime-generation (word runtime-startup-batch 24))
   (check-equal? (runtime-personal-generation-transition 1 runtime-generation)
                 '(#t #t #""))
   (define runtime-annotation
     (runtime-ksawery-annotation-projection-batch
      (annotation-observation "/tmp/odra-ksawery-extension"
                              #"refs/heads/main" 19)))
   (check-true (car runtime-annotation)
               (bytes->string/utf-8 (caddr runtime-annotation)))
   (check-not-equal? (cadr runtime-annotation) #"")
   (write-file! start-path start-baseline)
   (write-file! conflict-path "baseline\n")
   (check-true (git! "add" "--" "start.odin" "conflict.txt"))
   (check-true (git! "commit" "-qm" "baseline"))
   (write-file! start-path start-changed)

   (define command
     (string-append
      "stty rows 44 cols 180; XDG_CONFIG_HOME="
      (shell-quote (path->string (build-path home ".config")))
      " HOME=" (shell-quote (path->string home))
      " exec env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor "
      (shell-quote odra-path) " " (shell-quote (path->string start-path))))
   (define-values (process output input error-output)
     (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
   (define transcript (open-output-bytes))
   (define error-result (make-channel))
   (wait-for-terminal-readiness!
    'ksawery-extension process output input error-output transcript
    #:content-marker #"ksawery_extension_acceptance")
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
   (define (await-from value start [seconds 25])
     (define deadline (+ (current-inexact-milliseconds) (* seconds 1000)))
     (let wait ()
       (define current (get-output-bytes transcript))
       (cond
         [(and (<= start (bytes-length current))
               (contains? (subbytes current start) value))
          #t]
         [(>= (current-inexact-milliseconds) deadline)
          (report-transcript-tail current)
          (raise-user-error 'ksawery-extension-acceptance
                            "timed out waiting for ~s"
                            value)]
         [(sync/timeout 0 process)
          (define process-error (channel-get error-result))
          (report-transcript-tail current)
          (raise-user-error
           'ksawery-extension-acceptance
           "editor exited (~a) while waiting for ~s: ~a"
           (subprocess-status process)
           value
           (bytes->string/utf-8 process-error #\?))]
         [else
          (sleep 0.05)
          (wait)])))
   (define (refresh!)
     (send #"r")
     (send #"r")
     (send #"r"))

   (define status-start (bytes-length (get-output-bytes transcript)))
   (send (bytes-append meta-x #"ksawery-status" enter))
   (await-from #"Ksawery Status" status-start)
   (await-from #"Acceptance insight" status-start)
   (await-from #"Provider status active" status-start)
   (await-from #"Action: h browse repository history" status-start)

   (define refs-start (bytes-length (get-output-bytes transcript)))
   (send #"b" 0.8)
   (await-from #"Ksawery Refs" refs-start)
   (await-from #"Branch: refs/heads/main" refs-start)
   (await-from #"Acceptance annotation" refs-start)
   (send #"q")
   (await-from #"Ksawery Status" refs-start)

   (define inspection-start (bytes-length (get-output-bytes transcript)))
   (send #"v")
   (await-from #"Ksawery Providers" inspection-start)
   (await-from #"Contributor: Acceptance provider (personal.acceptance)" inspection-start)
   (await-from #"Provenance: origin=Personal source=test-owned/init.rkt" inspection-start)
   (await-from #"Latest failure: none" inspection-start)
   (for ([identity (in-list '(#"command.review" #"keymap.review" #"status.acceptance"
                              #"annotation.acceptance" #"family.workflow"
                              #"operation.inspect" #"conflict.guidance"
                              #"provider.conflict"))])
     (await-from identity inspection-start))

   (write-malformed-provider!)
   (define rejected-start (bytes-length (get-output-bytes transcript)))
   (send #"L" 0.8)
   (await-from #"Personal command reload rejected" rejected-start)
   (await-from #"status=Rejected" rejected-start)
   (await-from #"Effective provider: personal.acceptance" rejected-start)

   (write-provider! 2)
   (define reload-start (bytes-length (get-output-bytes transcript)))
   (send #"L" 0.8)
   (await-from #"Personal commands reloaded" reload-start)
   (await-from #"Generation: contributor=2" reload-start)

   (define disabled-start (bytes-length (get-output-bytes transcript)))
   (send #"z" 0.8)
   (await-from #"Personal Ksawery provider disabled; built-in fallback active" disabled-start)
   (await-from #"Effective provider: built-in fallback" disabled-start)

   (write-provider! 3)
   (define recovered-start (bytes-length (get-output-bytes transcript)))
   (send #"L" 0.8)
   (await-from #"Personal commands reloaded" recovered-start)
   (await-from #"Generation: contributor=3" recovered-start)
   (await-from #"Effective provider: personal.acceptance" recovered-start)
   (send #"q")
   (await-from #"Ksawery Status" recovered-start)

   (define raw-start (bytes-length (get-output-bytes transcript)))
   (send #"!")
   (await-from #"Ksawery Raw Repository Command" raw-start)
   (send #"status --short")
   (send control-enter)
   (await-from #"Ksawery Raw Command Confirmation" raw-start)
   (send #"q" 0.8)
   (await-from #"Raw repository command confirmation cancelled" raw-start)
   (await-from #"Ksawery Status" raw-start)
   (define post-cancel-start (bytes-length (get-output-bytes transcript)))
   (refresh!)
   (await-from #"Unstaged (1)" post-cancel-start)

   (send down 0.8)
   (define core-start (bytes-length (get-output-bytes transcript)))
   (send meta-x 0.8)
   (await-from #"Commands [active editor context]" core-start)
   (send #"personal.acceptance" 0.8)
   (await-from #"personal.acceptance" core-start)
   (send #"/family.workflow/action.stage" 0.8)
   (await-from #"personal.acceptance/family.workflow/action.stage" core-start)
   (send enter 0.8)
   (await-from #"Ksawery Extension Command: Acceptance workflows" core-start)
   (send enter 0.8)
   (await-from #"Ksawery extension command completed after repository refresh" core-start)
   (sleep 0.5)
   (check-false (git! "diff" "--cached" "--quiet"))
   (check-true (git! "reset" "-q" "HEAD" "--" "start.odin"))
   (write-file! start-path start-baseline)
   (define clean-start (bytes-length (get-output-bytes transcript)))
   (refresh!)
   (await-from #"Working tree clean" clean-start)

   (define external-start (bytes-length (get-output-bytes transcript)))
   (send meta-x 0.8)
   (await-from #"Commands [active editor context]" external-start)
   (send #"personal.acceptance" 0.8)
   (await-from #"personal.acceptance" external-start)
   (send #"/family.workflow/action.inspect" 0.8)
   (await-from #"personal.acceptance/family.workflow/action.inspect" external-start)
   (send enter 0.8)
   (await-from #"Ksawery Extension Command: Acceptance workflows" external-start)
   (send enter 0.8)
   (await-from #"Ksawery extension command external operation is running in Process" external-start)
   (await-from #"Ksawery extension external operation completed with typed verification"
               external-start)
   (define process-start (bytes-length (get-output-bytes transcript)))
   (send #"$")
   (await-from #"Ksawery Processes" process-start)
   (await-from #"Inspect repository" process-start)
   (await-from #"[Verified_Success]" process-start)
   (send #"q")
   (await-from #"Ksawery Status" process-start)

   (check-true (git! "checkout" "-q" "-b" "side"))
   (write-file! conflict-path "side\n")
   (check-true (git! "add" "--" "conflict.txt"))
   (check-true (git! "commit" "-qm" "side change"))
   (check-true (git! "checkout" "-q" "main"))
   (write-file! conflict-path "current\n")
   (check-true (git! "add" "--" "conflict.txt"))
   (check-true (git! "commit" "-qm" "current change"))
   (check-false (git! "merge" "--no-edit" "side"))
   (define conflict-start (bytes-length (get-output-bytes transcript)))
   (refresh!)
   (await-from #"Unmerged" conflict-start)
   (await-from #"Action: o inspect active sequence" conflict-start)
   (send #"o" 0.8)
   (await-from #"Ksawery Sequence" conflict-start)
   (await-from #"Conflict: conflict.txt" conflict-start)
   (send enter)
   (await-from #"Ksawery Conflict" conflict-start)
   (await-from #"H asks helper" conflict-start)
   (define assistance-start (bytes-length (get-output-bytes transcript)))
   (send #"H" 0.8)
   (await-from #"Assistance: Acceptance conflict helper" assistance-start)
   (await-from #"Guidance: Inspect conflict.txt" assistance-start)
   (send #"q")
   (await-from #"Ksawery Sequence" assistance-start)
   (send #"q")
   (await-from #"Ksawery Status" assistance-start)
   (check-true (git! "merge" "--abort"))
   (define restored-status-start (bytes-length (get-output-bytes transcript)))
   (refresh!)
   (await-from #"Working tree clean" restored-status-start)
   (check-false (git-path-exists? "MERGE_HEAD"))

   (define final-inspection-start (bytes-length (get-output-bytes transcript)))
   (send #"v")
   (await-from #"Usage: turns=" final-inspection-start)
   (await-from #"Latest failure:" final-inspection-start)
   (send #"q")
   (await-from #"Ksawery Status" final-inspection-start)

   (define canvas-start (bytes-length (get-output-bytes transcript)))
   (send #"q")
   (await-from #"ksawery_extension_acceptance" canvas-start)
   (await-from #"phase := " canvas-start)
   (await-from #"\"changed\"" canvas-start)

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
   (check-true (contains? output-bytes #"Provider status active"))
   (check-true (contains? output-bytes #"Acceptance annotation"))
   (check-true (contains? output-bytes #"Ksawery extension command completed"))
   (check-true (contains? output-bytes #"completed with typed verification"))
   (check-true (contains? output-bytes #"Guidance: Inspect conflict.txt"))
   (check-true (contains? output-bytes #"Effective provider: built-in fallback"))
   (check-true (contains? output-bytes restoration))
   (check-true (git! "diff" "--cached" "--quiet"))
   (check-true (git! "diff" "--quiet")))
 (lambda ()
   (when (directory-exists? root)
     (delete-directory/files root))))
