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
         "../../src/project/persistence.rkt"
         "../../src/project/records.rkt")

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for Project promotion scenarios")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define enter (bytes 13))
(define control-g (bytes 7))
(define control-x (bytes 24))
(define control-c (bytes 3))
(define close-pane (bytes-append control-x #"0"))
(define meta-x #"\33x")
(define exit-editor (bytes-append control-x control-c))
(define restoration-sequence #"\33[?25h\33[0m\r\n")

(define (utf8 value)
  (string->bytes/utf-8 value))

(define (contains? haystack needle)
  (regexp-match? (byte-regexp (regexp-quote needle)) haystack))

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (run-editor name home dir input-bytes)
  (define command
    (string-append
     "stty rows 16 cols 110; XDG_CONFIG_HOME="
     (shell-quote (path->string (build-path home ".config")))
     " HOME="
     (shell-quote (path->string home))
     " exec "
     (shell-quote odra-path)
     " "
     (shell-quote (path->string dir))))
  (define-values (process output input error-output)
    (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
  (define output-channel (make-channel))
  (define error-channel (make-channel))
  (thread (lambda () (channel-put output-channel (port->bytes output))))
  (thread (lambda () (channel-put error-channel (port->bytes error-output))))
  (sleep 2)
  (write-bytes input-bytes input)
  (flush-output input)
  (define completed? (sync/timeout 60 process))
  (unless completed? (subprocess-kill process #t))
  (subprocess-wait process)
  (define output-bytes (channel-get output-channel))
  (define error-bytes (channel-get error-channel))
  (close-output-port input)
  (close-input-port output)
  (close-input-port error-output)
  (check-not-false completed? (string-append name ": completion timeout"))
  (check-equal? (subprocess-status process) 0
                (format "~a output: ~s" name output-bytes))
  (check-equal? error-bytes #"" name)
  (check-true (contains? output-bytes restoration-sequence)
              (format "~a: terminal restoration; output: ~s" name output-bytes))
  output-bytes)

(define (make-dir root name)
  (define dir (build-path root name))
  (make-directory dir)
  (call-with-output-file (build-path dir "main.odin")
    (lambda (output) (display "package main\n" output)))
  dir)

(define root (make-temporary-file "odra-project-promotion-workflow-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define direct-home (build-path root "direct-home"))
   (define direct-dir (make-dir root "direct"))
   (make-directory direct-home)
   (define direct-output
     (run-editor
      "direct promotion"
      direct-home
      direct-dir
      (bytes-append
       #"main.odin" enter
       meta-x #"project-promote" enter enter
       exit-editor)))
   (check-true (contains? direct-output #"Dir promoted to Project"))
   (define direct-record
     (local-project-record-module-load (local-project-record-path direct-dir)))
   (check-true (odra-local-project-record? direct-record))
   (check-eq? (odra-local-project-record-trust direct-record) 'untrusted)

   (define no-home (build-path root "no-home"))
   (define no-dir (make-dir root "no"))
   (make-directory no-home)
   (define no-output
     (run-editor
      "declined abandonment"
      no-home
      no-dir
      (bytes-append #"main.odin" enter close-pane #"y" #"n")))
   (check-true (contains? no-output #"Last pane. Exit Odra?"))
   (check-true (contains? no-output #"Add this Dir to Projects?"))
   (check-false (contains? no-output #"Register this Project before exiting?"))
   (check-false (directory-exists? (build-path no-dir ".odra")))

   (define cancel-home (build-path root "cancel-home"))
   (define cancel-dir (make-dir root "cancel"))
   (make-directory cancel-home)
   (define cancel-output
     (run-editor
      "cancelled abandonment"
      cancel-home
      cancel-dir
      (bytes-append #"main.odin" enter exit-editor #"c" exit-editor #"n")))
   (check-true (contains? cancel-output #"Add this Dir to Projects?"))
   (check-false (directory-exists? (build-path cancel-dir ".odra")))

   (define convert-home (build-path root "convert-home"))
   (define convert-dir (make-dir root "convert"))
   (make-directory convert-home)
   (define convert-output
     (run-editor
      "promotion during abandonment"
      convert-home
      convert-dir
      (bytes-append #"main.odin" enter exit-editor #"y" enter)))
   (check-true (contains? convert-output #"Add this Dir to Projects?"))
   (check-true
    (odra-local-project-record?
     (local-project-record-module-load (local-project-record-path convert-dir))))

   (define disable-home (build-path root "disable-home"))
   (define disable-dir (make-dir root "disable"))
   (make-directory disable-home)
   (define disable-output
     (run-editor
      "disabled abandonment prompt"
      disable-home
      disable-dir
      (bytes-append #"main.odin" enter exit-editor #"d")))
   (check-true (contains? disable-output #"Add this Dir to Projects?"))
   (define suppression-path
     (promotion-suppressions-record-path (build-path disable-home ".config" "odra")))
   (check-true (file-exists? suppression-path))
   (define restart-output
     (run-editor
      "suppressed abandonment after restart"
      disable-home
      disable-dir
      (bytes-append #"main.odin" enter exit-editor)))
   (check-false (contains? restart-output #"Add this Dir to Projects?")))
 (lambda ()
   (when (directory-exists? root)
     (delete-directory/files root))))
