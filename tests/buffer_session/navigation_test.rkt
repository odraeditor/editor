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
(check-not-false script-path "util-linux script is required for buffer-session scenarios")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define control-x (bytes 24))
(define enter (bytes 13))
(define control-s (bytes 19))
(define control-c (bytes 3))
(define control-slash (bytes 31))
(define backspace (bytes 127))
(define tab (bytes 9))

(define (utf8 text)
  (string->bytes/utf-8 text))

(define (contains? haystack needle)
  (regexp-match? (byte-regexp (regexp-quote needle)) haystack))

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define session-directory (make-temporary-file "odra-buffer-session-~a" 'directory))

(define (run-editor name initial-path input-bytes
                    #:first-input [first-input #f]
                    #:second-input [second-input #f]
                    #:third-input [third-input #f])
  (define command
    (string-append
     "stty rows 12 cols 100; HOME="
     (shell-quote (path->string session-directory))
     " exec " odra-path " " (shell-quote (path->string initial-path))))
  (define-values (process output input error-output)
    (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
  (define transcript (open-output-bytes))
  (define read-buffer (make-bytes 4096))
  (define error-result (make-channel))
  (thread (lambda () (channel-put error-result (port->bytes error-output))))
  (define (transcript-contains? value)
    (regexp-match?
     (byte-regexp (regexp-quote value))
     (get-output-bytes transcript)))
  (define (wait-for-output! value [timeout 10])
    (define deadline (+ (current-inexact-milliseconds) (* timeout 1000)))
    (let loop ()
      (cond
        [(transcript-contains? value) #t]
        [else
         (define remaining (/ (- deadline (current-inexact-milliseconds)) 1000.0))
         (cond
           [(<= remaining 0) #f]
           [(sync/timeout remaining output)
            (define count (read-bytes-avail!* read-buffer output))
            (when (exact-positive-integer? count)
              (write-bytes read-buffer transcript 0 count))
            (loop)]
           [else #f])])))
  (define initial-label
    (string->bytes/utf-8 (path->string (file-name-from-path initial-path))))
  (unless (wait-for-output! initial-label)
    (subprocess-kill process #t)
    (error 'run-editor "~a: initial terminal frame was unavailable" name))
  (define output-reader (thread (lambda () (copy-port output transcript))))
  (when first-input
    (write-bytes first-input input)
    (flush-output input)
    (sleep 0.5))
  (when second-input
    (write-bytes second-input input)
    (flush-output input)
    (sleep 0.5))
  (when third-input
    (write-bytes third-input input)
    (flush-output input)
    (sleep 0.5))
  (write-bytes input-bytes input)
  (flush-output input)
  (subprocess-wait process)
  (thread-wait output-reader)
  (define output-bytes (get-output-bytes transcript))
  (define error-bytes (channel-get error-result))
  (close-input-port output)
  (close-input-port error-output)
  (check-equal? (subprocess-status process) 0 name)
  (check-equal? error-bytes #"" name)
  (check-true (contains? output-bytes #"\33[?25h\33[0m\r\n")
              (string-append name ": terminal restoration"))
  output-bytes)

(dynamic-wind
 void
 (lambda ()
   (define primary-path (build-path session-directory "primary.txt"))
   (call-with-output-file primary-path #:exists 'truncate/replace
     (lambda (output) (display "alpha one\n" output)))
   (define primary-label (path->string (normalize-path primary-path)))
   (define unicode-output
     (run-editor
      "unicode buffer switching"
      primary-path
      (bytes-append
       control-x #"b" (utf8 "λ-notes") enter
       #"note"
       control-x #"b" (utf8 primary-label) enter
       #"X" control-x control-s
       control-s #"alpha" enter
       control-x #"b" (utf8 "λ-notes") enter
       backspace control-slash
       control-x #"b" (utf8 primary-label) enter
       control-x control-c #"d")))
   (check-equal? (file->bytes primary-path) #"Xalpha one\n")
   (check-true (contains? unicode-output #"Buffers [session]"))
   (check-true (contains? unicode-output #"create"))
   (check-true (contains? unicode-output (utf8 "λ-notes")))
   (check-true (contains? unicode-output #"Search \342\206\222"))

   (define left-directory (build-path session-directory "left"))
   (define right-directory (build-path session-directory "right"))
   (make-directory left-directory)
   (make-directory right-directory)
   (define left-path (build-path left-directory "same.txt"))
   (define right-path (build-path right-directory "same.txt"))
   (call-with-output-file left-path #:exists 'truncate/replace
     (lambda (output) (display "left" output)))
   (call-with-output-file right-path #:exists 'truncate/replace
     (lambda (output) (display "right" output)))
   (define left-label (path->string (normalize-path left-path)))
   (define right-label "~/right/same.txt")
   (define alternate-right "~/right/./same.txt")
   (define reuse-output
     (run-editor
      "normalized path reuse"
      left-path
      (bytes-append
       control-x (bytes 6) (utf8 right-label) tab enter
       #"R" control-x control-s
       control-x (bytes 6) (utf8 alternate-right) tab enter
       control-slash control-x control-s
       control-x #"b" (utf8 left-label) enter
       control-x control-c #"d")))
   (check-equal? (file->bytes right-path) #"right")
   (check-true (contains? reuse-output #"Find file [local]"))
   (check-true (contains? reuse-output #"Opened file"))

   (define missing-path (build-path session-directory "created.md"))
   (define missing-label "~/created.md")
   (define create-output
     (run-editor
     "unmaterialized file creation"
      left-path
      (bytes-append
       #"created" control-x control-s
       control-x #"b" (utf8 left-label) enter
       control-x control-c)
      #:first-input (bytes-append control-x (bytes 6) (utf8 missing-label))
      #:second-input enter))
   (check-equal? (file->bytes missing-path) #"created")
   (check-true (contains? create-output #"Opened file")))
 (lambda ()
   (delete-directory/files session-directory)))
