#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

(require rackunit
         (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/file
         racket/path
         racket/port
         racket/system
         "../support/terminal-readiness.rkt")

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for product-module containment tests")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")
(define maksym-path (getenv "ODRA_MAKSYM_MODULE"))
(check-not-false maksym-path "ODRA_MAKSYM_MODULE must identify the built Maksym module")

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define root (make-temporary-file "odra-product-module-containment-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define isolated-binary (build-path root "odra-development"))
   (define modules-directory (build-path root "modules"))
   (define isolated-maksym (build-path modules-directory "libodra-maksym.so"))
   (define manifest-path (build-path modules-directory "product-modules.manifest"))
   (define managed-directory (build-path root "managed"))
   (define document-path (build-path managed-directory "ordinary.org"))
   (copy-file odra-path isolated-binary)
   (make-directory modules-directory)
   (make-directory managed-directory)
   (copy-file maksym-path isolated-maksym)
   (define maksym-digest
     (call-with-input-file isolated-maksym
       (lambda (input) (bytes->hex-string (sha256-bytes input)))
       #:mode 'binary))
   (call-with-output-file manifest-path
     #:exists 'truncate/replace
     (lambda (output)
       (fprintf output
                (string-append
                 "odra-product-modules 1\n"
                 "module\n"
                 "identity=odra.maksym\n"
                 "version=1.0.0\n"
                 "role=file-management\n"
                 "artifact=libodra-maksym.so\n"
                 "digest=~a\n"
                 "size=~a\n"
                 "entrypoint=odra_product_module_entrypoint\n"
                 "abi-minimum=5\n"
                 "abi-maximum=5\n"
                 "end\n")
                maksym-digest
                (file-size isolated-maksym))))
   (call-with-output-file document-path
     #:exists 'truncate/replace
     (lambda (output) (display "ordinary editing remains available\n" output)))
   (define command
     (string-append
      "stty rows 18 cols 100; cd "
      (shell-quote (path->string root))
      " && exec env HOME="
      (shell-quote (path->string root))
      " "
      (shell-quote (path->string isolated-binary))
      " "
      (shell-quote (path->string document-path))))
   (define-values (process output input error-output)
     (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
   (define transcript (open-output-bytes))
   (wait-for-terminal-readiness!
    'product-module-failure-containment
    process output input error-output transcript
    #:content-marker #"ordinary editing remains available")
   (define output-reader (thread (lambda () (copy-port output transcript))))
   (write-bytes #"x" input)
   (flush-output input)
   (sleep 0.1)
   (write-bytes (bytes 24 19) input)
   (flush-output input)
   (sleep 0.3)
   (define maksym-start (bytes-length (get-output-bytes transcript)))
   (write-bytes (bytes-append (bytes 24) #"d") input)
   (flush-output input)
   (define navigation-deadline (+ (current-inexact-milliseconds) 12000))
   (let wait-for-navigation ()
     (define current (get-output-bytes transcript))
     (unless (and (<= maksym-start (bytes-length current))
                  (regexp-match? #rx#"Open directory in Maksym" (subbytes current maksym-start)))
       (when (>= (current-inexact-milliseconds) navigation-deadline)
         (displayln (bytes->string/utf-8 current #\?) (current-error-port))
         (fail-check "Maksym navigation did not open while Darek was absent"))
       (sleep 0.05)
       (wait-for-navigation)))
   (write-bytes #"managed" input)
   (flush-output input)
   (write-byte 13 input)
   (flush-output input)
   (define maksym-deadline (+ (current-inexact-milliseconds) 12000))
   (let wait-for-maksym ()
     (define current (get-output-bytes transcript))
     (unless (and (<= maksym-start (bytes-length current))
                  (regexp-match? #rx#"Opened directory" (subbytes current maksym-start)))
       (when (>= (current-inexact-milliseconds) maksym-deadline)
         (displayln (bytes->string/utf-8 current #\?) (current-error-port))
         (fail-check "Maksym did not open while Darek was absent"))
       (sleep 0.05)
       (wait-for-maksym)))
   (write-bytes (bytes 24 3) input)
   (flush-output input)
   (define completed? (sync/timeout 30 process))
   (unless completed? (subprocess-kill process #t))
   (subprocess-wait process)
   (thread-wait output-reader)
   (define output-bytes (get-output-bytes transcript))
   (define error-bytes (port->bytes error-output))
   (close-output-port input)
   (close-input-port output)
   (close-input-port error-output)
   (check-not-false completed? (bytes->string/utf-8 output-bytes #\?))
   (check-equal? (subprocess-status process) 0)
   (check-equal? error-bytes #"")
   (check-true (regexp-match? #rx#"ordinary editing remains available" output-bytes))
   (check-true (regexp-match? #rx#"Opened directory" output-bytes))
   (check-equal? (file->bytes document-path) #"xordinary editing remains available\n")

   (define jan-path (build-path managed-directory "ordinary.jan"))
   (call-with-output-file jan-path
     #:exists 'truncate/replace
     (lambda (output-port) (display "Jan remains ordinary text\n" output-port)))
   (define jan-command
     (string-append
      "stty rows 18 cols 100; cd "
      (shell-quote (path->string root))
      " && exec env HOME="
      (shell-quote (path->string root))
      " "
      (shell-quote (path->string isolated-binary))
      " "
      (shell-quote (path->string jan-path))))
   (define-values (jan-process jan-output jan-input jan-error-output)
     (subprocess #f #f #f script-path "-qfec" jan-command "/dev/null"))
   (define jan-transcript (open-output-bytes))
   (wait-for-terminal-readiness!
    'jan-module-failure-containment
    jan-process jan-output jan-input jan-error-output jan-transcript
    #:content-marker #"Jan remains ordinary text")
   (define jan-reader (thread (lambda () (copy-port jan-output jan-transcript))))
   (write-bytes #"x" jan-input)
   (flush-output jan-input)
   (sleep 0.1)
   (write-bytes (bytes 24 19) jan-input)
   (flush-output jan-input)
   (sleep 0.3)
   (write-bytes (bytes 24 3) jan-input)
   (flush-output jan-input)
   (define jan-completed? (sync/timeout 30 jan-process))
   (unless jan-completed? (subprocess-kill jan-process #t))
   (subprocess-wait jan-process)
   (thread-wait jan-reader)
   (define jan-output-bytes (get-output-bytes jan-transcript))
   (define jan-error-bytes (port->bytes jan-error-output))
   (close-output-port jan-input)
   (close-input-port jan-output)
   (close-input-port jan-error-output)
   (check-not-false jan-completed? (bytes->string/utf-8 jan-output-bytes #\?))
   (check-equal? (subprocess-status jan-process) 0)
   (check-equal? jan-error-bytes #"")
   (check-equal? (file->bytes jan-path) #"xJan remains ordinary text\n"))
 (lambda ()
   (when (directory-exists? root)
     (delete-directory/files root))))
