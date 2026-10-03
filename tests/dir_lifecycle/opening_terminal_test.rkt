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
(check-not-false script-path "util-linux script is required for Dir opening scenarios")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define enter (bytes 13))
(define control-g (bytes 7))
(define control-x (bytes 24))
(define control-c (bytes 3))
(define down #"\33[B")
(define meta-x #"\33x")
(define exit-editor (bytes-append control-x control-c))
(define restoration-sequence #"\33[?25h\33[0m\r\n")

(define (utf8 value)
  (string->bytes/utf-8 value))

(define (contains? haystack needle)
  (regexp-match? (byte-regexp (regexp-quote needle)) haystack))

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (home-path-input name)
  (utf8 (string-append "~/" name)))

(define (open-dir-input name)
  (bytes-append down down enter (home-path-input name) enter))

(define (run-editor name home input-bytes
                    #:first-input [first-input #f]
                    #:between [between #f]
                    #:argument [argument #f])
  (define command
    (string-append
     "stty rows 16 cols 110; HOME="
     (shell-quote (path->string home))
     " exec "
     (shell-quote odra-path)
     (if argument
         (string-append " " (shell-quote (path->string argument)))
         "")))
  (define-values (process output input error-output)
    (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
  (define transcript (open-output-bytes))
  (define error-channel (make-channel))
  (wait-for-terminal-readiness!
   'dir-opening process output input error-output transcript
   #:content-marker
   (if argument #"Files [active Dir]" #"Open Dir"))
  (define output-reader (thread (lambda () (copy-port output transcript))))
  (thread (lambda () (channel-put error-channel (port->bytes error-output))))
  (when first-input
    (write-bytes first-input input)
    (flush-output input)
    (sleep 0.5))
  (when between (between))
  (write-bytes input-bytes input)
  (flush-output input)
  (define completed? (sync/timeout 60 process))
  (unless completed? (subprocess-kill process #t))
  (subprocess-wait process)
  (thread-wait output-reader)
  (define output-bytes (get-output-bytes transcript))
  (define error-bytes (channel-get error-channel))
  (close-output-port input)
  (close-input-port output)
  (close-input-port error-output)
  (check-not-false completed? (string-append name ": completion timeout"))
  (check-equal? (subprocess-status process) 0
                (format "~a output: ~s" name output-bytes))
  (check-equal? error-bytes #"" name)
  (check-true (contains? output-bytes restoration-sequence)
              (string-append name ": terminal restoration"))
  output-bytes)

(define (write-local-project-record dir id name generation)
  (define metadata-dir (build-path dir ".odra"))
  (make-directory metadata-dir)
  (call-with-output-file (build-path metadata-dir "project.rkt")
    (lambda (output)
      (fprintf output
               "#lang odra/config\n(local-project #:format-version 2 #:id ~s #:generation ~a #:name ~s #:root ~s #:trust trusted)\n"
               id generation name (path->string dir)))
    #:exists 'truncate/replace))

(define root (make-temporary-file "odra-dir-lifecycle-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define home (build-path root "home"))
   (define ordinary (build-path home "ordinary"))
   (define replacement (build-path home "replacement"))
   (define empty (build-path home "empty"))
   (define project-dir (build-path home "project"))
   (define unavailable (build-path home "unavailable"))
   (define disappearing (build-path unavailable "gone.txt"))
   (for ([dir (in-list (list home ordinary replacement empty project-dir unavailable))])
     (make-directory dir))
   (make-directory (build-path ordinary "nested"))
   (call-with-output-file (build-path ordinary "nested" "żółć.txt")
     (lambda (output) (display "ordinary nested Unicode body" output)))
   (call-with-output-file (build-path replacement "replacement.txt")
     (lambda (output) (display "replacement Dir body" output)))
   (call-with-output-file (build-path project-dir "project.txt")
     (lambda (output) (display "local Project body" output)))
   (call-with-output-file disappearing
     (lambda (output) (display "disappearing body" output)))
   (write-local-project-record project-dir "local-project" "Local Project" 7)

   (define ordinary-output
     (run-editor
      "ordinary Dir"
      home
      (bytes-append (utf8 "ŻÓŁĆ") enter exit-editor #"n")
      #:first-input (open-dir-input "ordinary")))
   (check-true (contains? ordinary-output #"Files [active Dir]"))
   (check-true (contains? ordinary-output (utf8 "nested/żółć.txt")))
   (check-true (contains? ordinary-output #"ordinary nested Unicode body"))
   (check-false (directory-exists? (build-path ordinary ".odra")))

   (define startup-argument-output
     (run-editor
      "startup Dir argument"
      home
      (bytes-append (utf8 "ŻÓŁĆ") enter exit-editor #"n")
      #:argument ordinary))
   (check-true (contains? startup-argument-output #"Files [active Dir]"))
   (check-true (contains? startup-argument-output #"ordinary nested Unicode body"))

   (define empty-output
     (run-editor
      "empty Dir"
      home
      (bytes-append control-g exit-editor #"n")
      #:first-input (open-dir-input "empty")))
   (check-true (contains? empty-output #"Files [active Dir] 0/0"))

   (define project-output
     (run-editor
      "local Project"
      home
      (bytes-append #"project.txt" enter exit-editor)
      #:first-input (open-dir-input "project")))
   (check-true (contains? project-output #"Files [active Project]"))
   (check-true (contains? project-output #"local Project body"))

   (define replacement-output
     (run-editor
      "Dir replacement"
      home
      (bytes-append
       control-g
       meta-x #"open-directory" enter
       (home-path-input "replacement") enter
       #"n" enter
       exit-editor #"n")
      #:first-input (open-dir-input "ordinary")))
   (check-true (contains? replacement-output #"replacement Dir body"))
   (check-false (contains? replacement-output #"Project switch unavailable"))

   (define unavailable-output
     (run-editor
      "unavailable Dir file"
      home
      (bytes-append enter control-g exit-editor #"n")
      #:first-input (open-dir-input "unavailable")
      #:between
      (lambda ()
        (delete-file disappearing)
        (make-directory disappearing))))
   (check-true (contains? unavailable-output #"gone.txt"))
   (check-false (contains? unavailable-output #"disappearing body"))

   (define faulted (build-path home "faulted"))
   (make-directory faulted)
   (define faulted-output
     (run-editor
      "unavailable root"
      home
      (bytes-append enter exit-editor)
      #:first-input
      (bytes-append down down enter (home-path-input "faulted"))
      #:between (lambda () (delete-directory faulted))))
   (check-true (contains? faulted-output #"Directory is invalid or unavailable"))

   (define cancelled-output
     (run-editor
      "cancel Dir prompt"
      home
      exit-editor
      #:first-input (bytes-append down down enter control-g)))
   (check-true (contains? cancelled-output #"Open Dir")))
 (lambda ()
   (when (directory-exists? root)
     (delete-directory/files root))))
