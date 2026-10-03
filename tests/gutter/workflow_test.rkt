#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         racket/path
         racket/port
         racket/system)

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for the Gutter PTY scenario")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (contains? haystack needle)
  (regexp-match? (byte-regexp (regexp-quote needle)) haystack))

(define (without-terminal-controls value)
  (regexp-replace* #px#"\033\\[[0-9;?]*[ -/]*[@-~]" value #""))

(define document-path (make-temporary-file "odra-gutter-~a.odin"))
(define configuration-home (make-temporary-file "odra-gutter-config-~a" 'directory))

(define (configuration-source provider-generation marker detail action)
  (string-append
   "#lang racket/base\n"
   "(require odra/gutters)\n"
   "(provide odra-gutter-configuration odra-gutter-provider)\n"
   "(define odra-gutter-configuration\n"
   "  '#hash((mode . relative)\n"
   "          (current-line . zero)\n"
   "          (separator . \">\")\n"
   "          (separator-fallback . \">\")))\n"
   (if marker
       (string-append
        "(define odra-gutter-provider\n"
        "  (gutter-provider\n"
        "   \"Personal Notes\" 'personal-notes\n"
        "   (list (gutter-lane 'notes))\n"
        "   (list (gutter-marker 'review 'notes 5 \"" marker "\"\n"
        "                        #:fallback \"*\"\n"
        "                        #:style 'diagnostic-information\n"
        "                        #:detail \"" detail "\"\n"
        "                        #:actions '(" action ")))\n"
        "   #:generation " (number->string provider-generation) "\n"
        "   #:marker-generation " (number->string provider-generation) "))\n")
       "(define odra-gutter-provider #f)\n")))

(dynamic-wind
 void
 (lambda ()
   (define odra-configuration-directory
     (build-path configuration-home "odra"))
   (make-directory* odra-configuration-directory)
   (define configuration-path (build-path odra-configuration-directory "init.rkt"))
   (define (write-configuration provider-generation marker detail action)
     (call-with-output-file configuration-path
       #:exists 'truncate/replace
       (lambda (output)
         (display (configuration-source provider-generation marker detail action) output))))
   (write-configuration 1 "◆" "Review this line" "gutter-inspect-numbering")
   (call-with-output-file
    document-path
    #:exists 'truncate/replace
    (lambda (output)
      (for ([line (in-range 1 13)])
        (if (= line 6)
            (fprintf output "line_6 :: \"This deliberately long viewport row proves semantic clipping markers remain inspectable from the keyboard.\"\n")
            (fprintf output "line_~a :: ~a\n" line line)))))
   (define command
     (string-append
      "stty rows 20 cols 100; exec env XDG_CONFIG_HOME="
      (shell-quote (path->string configuration-home))
      " " (shell-quote odra-path) " " (shell-quote (path->string document-path))))
   (define-values (process output input error-output)
     (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
   (define output-lock (make-semaphore 1))
   (define output-transcript (open-output-bytes))
   (define read-buffer (make-bytes 4096))
   (define output-reader
     (thread
      (lambda ()
        (let loop ()
          (define count (read-bytes-avail!* read-buffer output))
          (cond
            [(eof-object? count) (void)]
            [(exact-positive-integer? count)
             (call-with-semaphore
              output-lock
              (lambda () (write-bytes read-buffer output-transcript 0 count)))
             (loop)]
            [else
             (sync output)
             (loop)])))))
   (define (output-snapshot)
     (call-with-semaphore output-lock (lambda () (get-output-bytes output-transcript))))
   (define (wait-for-output! value [timeout 10])
     (define deadline (+ (current-inexact-milliseconds) (* timeout 1000)))
     (let loop ()
       (cond
         [(contains? (output-snapshot) value) #t]
         [(>= (current-inexact-milliseconds) deadline) #f]
         [else
          (sleep 0.05)
          (loop)])))
   (define (output-tail)
     (define bytes (output-snapshot))
     (bytes->string/utf-8 (subbytes bytes (max 0 (- (bytes-length bytes) 4096))) #\?))
   (define input-open? #t)
   (define (send bytes)
     (when input-open?
       (with-handlers ([exn:fail? (lambda (_) (set! input-open? #f))])
         (write-bytes bytes input)
         (flush-output input))))
   (sleep 1.6)
   (for ([_ (in-range 4)])
     (send (bytes 14))
     (sleep 0.05))
   (send #"\33xgutter-set-line-numbers-hybrid\r")
   (sleep 0.2)
   (send #"\33xgutter-toggle-line-number-side\r")
   (sleep 0.2)
   (send #"\33xgutter-inspect-numbering\r")
   (sleep 0.2)
   (send (bytes 14))
   (sleep 0.2)
   (send #"\33xgutter-inspect-markers\r")
   (sleep 0.2)
   (send (bytes 7))
   (sleep 0.2)
   (send #"\33xgutter-inspect-markers\r")
   (sleep 0.2)
   (send (bytes 16))
   (sleep 0.2)
   (send #"\33xgutter-inspect-markers\r")
   (sleep 0.2)
   (send #"\33xgutter-invoke-primary-marker-action\r")
   (sleep 0.2)
   (write-configuration 2 "▲" "Replacement marker" "gutter-inspect-numbering")
   (send #"\33xreload-personal-commands\r")
   (send #"\33xgutter-inspect-markers\r")
   (check-true (wait-for-output! #"Replacement marker") (output-tail))
   (write-configuration 3 "!" "Rejected marker" "command-does-not-exist")
   (send #"\33xreload-personal-commands\r")
   (send #"\33xgutter-inspect-markers\r")
   (check-true (wait-for-output! #"Programmable Gutter provider rejected") (output-tail))
   (write-configuration 4 #f "" "")
   (send #"\33xreload-personal-commands\r")
   (send #"\33xgutter-inspect-markers\r")
   (check-true (wait-for-output! #"No semantic Gutter markers at the active line") (output-tail))
   (write-configuration 5 "◇" "Restored marker" "gutter-inspect-numbering")
   (send #"\33xreload-personal-commands\r")
   (send #"\33xgutter-inspect-markers\r")
   (check-true (wait-for-output! #"Restored marker") (output-tail))
   (send (bytes 24 3))
   (define completed? (sync/timeout 15 process))
   (unless completed? (subprocess-kill process #t))
   (subprocess-wait process)
   (thread-wait output-reader)
   (define output-bytes (output-snapshot))
   (define error-bytes (port->bytes error-output))
   (define plain-output (without-terminal-controls output-bytes))
   (close-output-port input)
   (close-input-port output)
   (close-input-port error-output)

   (check-not-false completed?)
   (check-equal? (subprocess-status process) 0
                 (bytes->string/utf-8 output-bytes #\?))
   (check-equal? error-bytes #"" (bytes->string/utf-8 output-bytes #\?))
   (define rendered-output (bytes->string/utf-8 plain-output #\?))
   (check-true (contains? plain-output #"   0 >") rendered-output)
   (check-true (contains? plain-output #"Gutter numbering: mode=hybrid") rendered-output)
   (check-true (contains? plain-output #"side=right") rendered-output)
   (check-true (contains? plain-output #"source=view") rendered-output)
   (check-true (contains? plain-output #"Review this line") rendered-output)
   (check-true (contains? plain-output (string->bytes/utf-8 "┌")) rendered-output)
   (check-true (contains? plain-output (string->bytes/utf-8 "┘")) rendered-output)
   (check-true (contains? plain-output #"Replacement marker") rendered-output)
   (check-true (contains? plain-output #"Programmable Gutter provider rejected") rendered-output)
   (check-true (contains? plain-output #"No semantic Gutter markers at the active line") rendered-output)
   (check-true (contains? plain-output #"Restored marker") rendered-output)
   (check-true (contains? plain-output #"line_1 :: 1"))
   (check-true (contains? plain-output #"line_12 :: 12")))
 (lambda ()
   (when (file-exists? document-path)
     (delete-file document-path))
   (when (directory-exists? configuration-home)
     (delete-directory/files configuration-home))))
