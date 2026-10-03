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
         "../support/terminal-readiness.rkt"
         "../../src/project/persistence.rkt"
         "../../src/project/records.rkt")

;; Drives the real terminal so Project commands, key sequences, components, and
;; dirty-buffer decisions are verified across the complete application path.
(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for Project scenarios")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define control-x (bytes 24))
(define control-b (bytes 2))
(define control-c (bytes 3))
(define control-g (bytes 7))
(define enter (bytes 13))
(define down #"\33[B")

(define (utf8 text)
  (string->bytes/utf-8 text))

(define (contains? haystack needle)
  (regexp-match? (byte-regexp (regexp-quote needle)) haystack))

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define fixture-directory (make-temporary-file "odra-project-workflows-~a" 'directory))
;; Keep the absolute file path wider than the terminal even under a short TMPDIR.
(define home-directory
  (build-path fixture-directory (string-append "long-home-" (make-string 120 #\h))))
(make-directory home-directory)
(define root (build-path home-directory "project-workflow"))
(make-directory root)
(dynamic-wind
 void
 (lambda ()
   (define alpha-path (build-path root "alpha.md"))
   (define unicode-path (build-path root "zeta-界.md"))
   (call-with-output-file alpha-path #:exists 'truncate/replace
     (lambda (output) (display "alpha project text\n" output)))
   (call-with-output-file unicode-path #:exists 'truncate/replace
     (lambda (output) (display "unicode project text\n" output)))
   (check-true
    (odra-record-publication?
     (local-project-record-persist
      root
      (local-project-record
       #:format-version current-local-project-format-version
       #:id "project-workflow"
       #:generation 1
       #:name "Project Workflow"
       #:root (path->string root)
       #:trust 'untrusted))))

   (define command
     (string-append
      "stty rows 18 cols 120; HOME="
      (shell-quote (path->string home-directory))
      " exec " odra-path))
   (define-values (process output input error-output)
     (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
   (define transcript (open-output-bytes))
   (define error-bytes #f)
   (wait-for-terminal-readiness!
    'project-command-workflow process output input error-output transcript
    #:content-marker #"Open Dir")
   (define output-reader
     (thread (lambda () (copy-port output transcript))))
   (define error-reader
     (thread (lambda () (set! error-bytes (port->bytes error-output)))))
   (write-bytes
    (bytes-append
     ;; Open the exact local Project and select its first content file.
     down down enter #"~/project-workflow" enter
     #"alpha" enter
     ;; Keep an unassociated live buffer for the Project-buffer boundary.
     control-x control-b (utf8 "notes") enter
     ;; Find the first deterministic file candidate and open it.
     control-c #"pf" enter
     ;; Select among Project-owned live buffers.
     control-c #"pb" enter
     ;; Modify and save only the Project-owned buffer.
     #"Z" control-c #"pS"
     ;; Reconcile observations, open the Project command menu, and inspect the
     ;; effective plus reserved Project-prefix bindings.
     control-c #"pi"
     control-c #"pm" control-g
     control-c #"p" (bytes 8) #"q"
     ;; Dirty protection asks for an explicit decision before closing.
     #"Y" control-c #"pk" #"d"
     control-x control-c)
    input)
   (flush-output input)
   (define completed? (sync/timeout 20 process))
   (unless completed?
     (subprocess-kill process #t))
   (subprocess-wait process)
   (thread-wait output-reader)
   (thread-wait error-reader)
   (define output-bytes (get-output-bytes transcript))
   (close-input-port output)
   (close-input-port error-output)

   (check-not-false completed? "Project command workflow completion timeout")
   (check-equal? (subprocess-status process) 0)
   (check-equal? error-bytes #"")
   (define unexpected-open-message
     (regexp-match #rx#".{0,80}Project opened.{0,80}" output-bytes))
   (check-false unexpected-open-message unexpected-open-message)
   ;; Verify file identity and the persisted edit without requiring an unclipped path.
   (check-true (contains? output-bytes #"alpha.md"))
   (check-equal? (file->string alpha-path) "Zalpha project text\n")
   (check-equal? (file->string unicode-path) "unicode project text\n")
   (check-true (contains? output-bytes (utf8 "zeta-界.md")))
   (check-true (contains? output-bytes #"alpha project text"))
   (check-true (contains? output-bytes #"Files [active Project]"))
   (check-true (contains? output-bytes #"Project buffers saved: 1 of 1 modified"))
   (check-true (contains? output-bytes #"Project refreshed: generation"))
   (check-true (contains? output-bytes #"project-find-file"))
   (check-true (contains? output-bytes #"project-command-menu"))
   (check-true (contains? output-bytes #"Project buffer: [s]ave [d]iscard [c]ancel"))
   (check-true (contains? output-bytes #"Project buffers closed: 1"))
   (check-true (contains? output-bytes #"\33[?25h\33[0m\r\n")))
 (lambda ()
   (delete-directory/files fixture-directory)))
