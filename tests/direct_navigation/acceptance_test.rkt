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
(check-not-false script-path "util-linux script is required for the direct navigation PTY scenario")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define control-a (bytes 1))
(define control-b (bytes 2))
(define control-e (bytes 5))
(define control-f (bytes 6))
(define control-n (bytes 14))
(define control-p (bytes 16))
(define control-g (bytes 7))
(define control-x (bytes 24))
(define exit-sequence (bytes 24 3))
(define insert #"\33[2~")
(define delete #"\33[3~")
(define prior #"\33[5~")
(define next #"\33[6~")
(define restoration-sequence #"\33[?25h\33[0m\r\n")

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (contains? haystack needle)
  (regexp-match? (byte-regexp (regexp-quote needle)) haystack))

(define (run-scenario name contents input-bytes)
  (define document-path (make-temporary-file (string-append "odra-direct-navigation-" name "-~a.txt")))
  (dynamic-wind
   void
   (lambda ()
     (call-with-output-file
      document-path
      #:exists 'truncate/replace
      (lambda (output) (display contents output)))
     (define command
       (string-append
        "stty rows 10 cols 100; exec "
        (shell-quote odra-path)
        " "
        (shell-quote (path->string document-path))))
     (define-values (process output input error-output)
       (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
     (define transcript (open-output-bytes))
     (wait-for-terminal-readiness!
      'direct-navigation process output input error-output transcript
      #:content-marker
      (string->bytes/utf-8 (path->string (file-name-from-path document-path))))
     (define output-reader
       (thread (lambda () (copy-port output transcript))))
     (define input-written?
       (with-handlers ([exn:fail? (lambda (_) #f)])
         (write-bytes input-bytes input)
         (flush-output input)
         #t))
     (define completed? (sync/timeout 20 process))
     (unless completed? (subprocess-kill process #t))
     (subprocess-wait process)
     (thread-wait output-reader)
     (define output-bytes (get-output-bytes transcript))
     (define error-bytes (port->bytes error-output))
     (close-output-port input)
     (close-input-port output)
     (close-input-port error-output)
     (check-not-false completed? name)
     (check-equal? (subprocess-status process) 0 name)
     (check-true input-written? name)
     (check-equal? error-bytes #"" name)
     (check-true (contains? output-bytes restoration-sequence) name)
     (values output-bytes (file->string document-path)))
   (lambda ()
     (when (file-exists? document-path)
       (delete-file document-path)))))

(define navigation-contents
  (string-append
   "alpha beta\n"
   "  gamma delta\n"
   (apply string-append
          (for/list ([index (in-range 24)])
            (format "line-~a\n" index)))))

(define-values (navigation-output navigation-saved)
  (run-scenario
   "ordinary-editing"
   navigation-contents
   (bytes-append
    control-a
    control-f #"X"
    #"\33f" #"!"
    #"\33b" #">"
    control-e #";"
    control-n #"\33m" #"#"
    control-a #"["
    control-e #"]"
    control-p
    #"\33[D\33[C\33[A\33[B\33[H\33[F"
    #"\33[1;5D\33[1;5C\33[1;5A\33[1;5B"
    #"\33xcursor-next-grapheme" control-g
    control-x (bytes 19) exit-sequence)))

(check-true (contains? navigation-output #"Commands [active editor context]"))
(check-true (contains? navigation-output #"cursor-next-grapheme"))
(check-equal?
 navigation-saved
 (string-append
  ">aXlpha! beta;\n"
  "[  #gamma delta]\n"
  (apply string-append
         (for/list ([index (in-range 24)])
           (format "line-~a\n" index)))))

(define overwrite-contents
  (string-append
   "é🙂x\n"
   (apply string-append
          (for/list ([index (in-range 24)])
            (format "page-~a\n" index)))))

(define-values (overwrite-output overwrite-saved)
  (run-scenario
   "overwrite-and-paging"
   overwrite-contents
   (bytes-append
    insert (string->bytes/utf-8 "界")
    insert
    #"\33[C" delete
    next prior
    control-x (bytes 19) exit-sequence)))

(check-true (>= (length (regexp-match* (byte-regexp (regexp-quote #"\33[2J")) overwrite-output)) 3))
(check-equal?
 overwrite-saved
 (string-append
  "界🙂\n"
  (apply string-append
         (for/list ([index (in-range 24)])
           (format "page-~a\n" index)))))
