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
(check-not-false script-path "util-linux script is required for preview runtime acceptance")

(define preview-executable (getenv "ODRA_PREVIEW_EXECUTABLE"))
(define racket-boot-directory (getenv "ODRA_RACKET_BOOT_DIR"))
(define racket-collects-directory (getenv "ODRA_RACKET_COLLECTS_DIR"))
(define racket-config-directory (getenv "ODRA_RACKET_CONFIG_DIR"))
(check-not-false preview-executable "ODRA_PREVIEW_EXECUTABLE must identify the preview executable")
(check-not-false racket-boot-directory "ODRA_RACKET_BOOT_DIR must identify Racket boot resources")
(check-not-false racket-collects-directory "ODRA_RACKET_COLLECTS_DIR must identify Racket collections")
(check-not-false racket-config-directory "ODRA_RACKET_CONFIG_DIR must identify Racket configuration")

(define restoration-sequence #"\33[?25h\33[0m\r\n")
(define process-timeout-seconds 15)
(define diagnostic-byte-limit 8192)

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (path-string value)
  (path->string (simple-form-path value)))

(define (set-environment-path! environment name value)
  (environment-variables-set!
   environment
   (string->bytes/utf-8 name)
   (string->bytes/utf-8 (path-string value))))

(define (stop-process! process)
  (when (eq? (subprocess-status process) 'running)
    (subprocess-kill process #f)
    (unless (sync/timeout 1 process)
      (subprocess-kill process #t)))
  (subprocess-wait process))

(define (wait-for-exit! owner process)
  (unless (sync/timeout process-timeout-seconds process)
    (stop-process! process)
    (raise-user-error owner "preview process exit timeout"))
  (subprocess-wait process))

(define (copy-runtime-tree! root)
  (define binary-directory (build-path root "bin"))
  (define boot-directory (build-path root "lib" "odra" "racket" "lib"))
  (define collects-directory (build-path root "share" "odra" "racket" "collects"))
  (define config-directory (build-path root "share" "odra" "racket" "etc"))
  (make-directory* binary-directory)
  (make-directory* boot-directory)
  (make-directory* (build-path root "share" "odra" "racket"))
  (copy-file preview-executable (build-path binary-directory "odra"))
  (file-or-directory-permissions (build-path binary-directory "odra") #o755)
  (for ([name (in-list '("petite.boot" "scheme.boot" "racket.boot" "system.rktd"))])
    (copy-file (build-path racket-boot-directory name) (build-path boot-directory name)))
  (copy-directory/files racket-collects-directory collects-directory)
  (copy-directory/files racket-config-directory config-directory)
  (values (build-path binary-directory "odra") boot-directory))

(define (isolated-environment empty-path home config-home)
  (define environment (environment-variables-copy (current-environment-variables)))
  (set-environment-path! environment "PATH" empty-path)
  (set-environment-path! environment "HOME" home)
  (set-environment-path! environment "XDG_CONFIG_HOME" config-home)
  (environment-variables-set! environment #"TERM" #"xterm-256color")
  (environment-variables-set! environment #"COLORTERM" #"truecolor")
  environment)

(define (run-pty executable document working-directory environment)
  (define command
    (string-append
     "cd " (shell-quote (path-string working-directory))
     " && /usr/bin/stty rows 24 cols 80"
     " && exec " (shell-quote (path-string executable))
     " " (shell-quote (path-string document))))
  (define-values (process output input error-output)
    (parameterize ([current-environment-variables environment])
      (subprocess #f #f #f script-path "-qfec" command "/dev/null")))
  (define transcript (open-output-bytes))
  (wait-for-terminal-readiness!
   'preview-runtime process output input error-output transcript
   #:content-marker (string->bytes/utf-8 (path->string (file-name-from-path document))))
  (define output-reader (thread (lambda () (copy-port output transcript))))
  (write-bytes
   (bytes-append #"\33xuppercase-current-line\r" (bytes 24 19 24 3))
   input)
  (flush-output input)
  (wait-for-exit! 'preview-runtime process)
  (thread-wait output-reader)
  (define output-bytes (get-output-bytes transcript))
  (define error-bytes (port->bytes error-output))
  (close-output-port input)
  (close-input-port output)
  (close-input-port error-output)
  (values (subprocess-status process) output-bytes error-bytes))

(define (run-direct executable working-directory environment)
  (define-values (process output input error-output)
    (parameterize ([current-directory working-directory]
                   [current-environment-variables environment])
      (subprocess #f #f #f executable)))
  (close-output-port input)
  (wait-for-exit! 'preview-runtime-missing-resource process)
  (define output-bytes (port->bytes output))
  (define error-bytes (port->bytes error-output))
  (close-input-port output)
  (close-input-port error-output)
  (values (subprocess-status process) output-bytes error-bytes))

(define temporary-directory (make-temporary-file "odra-preview-runtime-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define bundle-root (build-path temporary-directory "bundle"))
   (define working-directory (build-path temporary-directory "working"))
   (define empty-path (build-path temporary-directory "empty-path"))
   (define home (build-path temporary-directory "home"))
   (define config-home (build-path temporary-directory "config"))
   (for ([directory (in-list (list working-directory empty-path home config-home))])
     (make-directory* directory))
   (define-values (executable boot-directory) (copy-runtime-tree! bundle-root))
   (define environment (isolated-environment empty-path home config-home))

   (parameterize ([current-environment-variables environment])
     (check-false (find-executable-path "racket")))

   (define document (build-path working-directory "preview.txt"))
   (call-with-output-file
    document
    #:exists 'truncate/replace
    (lambda (output) (display "preview runtime\n" output)))
   (define-values (status output-bytes error-bytes)
     (run-pty executable document working-directory environment))
   (check-equal? status 0)
   (check-equal? error-bytes #"")
   (check-equal? (file->string document) "PREVIEW RUNTIME\n")
   (check-true
    (regexp-match? (byte-regexp (regexp-quote #"PREVIEW RUNTIME")) output-bytes))
   (check-true
    (regexp-match? (byte-regexp (regexp-quote restoration-sequence)) output-bytes))

   (delete-file (build-path boot-directory "racket.boot"))
   (define-values (missing-status missing-output missing-error)
     (run-direct executable working-directory environment))
   (check-equal? missing-status 1)
   (check-equal? missing-output #"")
   (check-true (< (bytes-length missing-error) diagnostic-byte-limit))
   (check-true (regexp-match? #rx#"stage=Racket_Start" missing-error))
   (check-true
    (regexp-match? #rx#"Racket runtime resources are unavailable" missing-error)))
 (lambda () (delete-directory/files temporary-directory)))
