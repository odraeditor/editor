#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

(require racket/file
         racket/path
         racket/port
         racket/system
         rackunit)

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for Visual Block acceptance")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (contains? haystack needle)
  (regexp-match? (byte-regexp (regexp-quote needle)) haystack))

(define root (make-temporary-file "odra-visual-block-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define configuration-base (build-path root "config"))
   (define configuration-root (build-path configuration-base "odra"))
   (make-directory* configuration-root)
   (call-with-output-file
    (build-path configuration-root "init.rkt")
    #:exists 'truncate/replace
    (lambda (output)
      (display
       (string-append
        "#lang racket/base\n"
        "(require odra/keymaps)\n"
        "(provide odra-interaction-profile)\n"
        "(define odra-interaction-profile (factory-modal-interaction-profile))\n")
       output)))
   (define document-path (build-path root "sample.txt"))
   (call-with-output-file document-path #:exists 'truncate/replace
     (lambda (output) (display "abcd\nxy\nalpha\n" output)))
   (define command
     (string-append
      "stty rows 18 cols 100; exec env -u NO_COLOR TERM=xterm-256color "
      "HOME=" (shell-quote (path->string root)) " "
      "XDG_CONFIG_HOME=" (shell-quote (path->string configuration-base)) " "
      (shell-quote odra-path) " " (shell-quote (path->string document-path))))
   (define-values (process output input error-output)
     (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
   (define transcript (open-output-bytes))
   (define read-buffer (make-bytes 4096))
   (define (transcript-bytes) (get-output-bytes transcript))
   (define (repeat-diagnostic after)
     (define captured (transcript-bytes))
     (define recent (subbytes captured (min after (bytes-length captured))))
     (or (for/or ([message (in-list
                            '(#"No modal change is available to repeat"
                              #"The last modal change is stale"
                              #"The last modal change is incompatible"
                              #"No inserted text is available to repeat"))])
           (and (contains? recent message) (bytes->string/utf-8 message)))
         "no repeat diagnostic"))
   (define (wait-for-output! value [timeout 12] [after 0])
     (define deadline (+ (current-inexact-milliseconds) (* timeout 1000)))
     (let loop ()
       (define captured (transcript-bytes))
       (cond
         [(and (<= after (bytes-length captured))
               (contains? (subbytes captured after) value))
          #t]
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
   (define (send bytes [pause 0.25])
     (write-bytes bytes input)
     (flush-output input)
     (sleep pause))

   (check-true (wait-for-output! #"NORMAL") "modal startup must show NORMAL")
   (send #"gg")
   (define block-start (bytes-length (transcript-bytes)))
   (send (bytes 22))
   (check-true
    (wait-for-output! #"VISUAL BLOCK" 12 block-start)
    "C-v must enter Visual Block")
   (send #"l")
   (define copy-start (bytes-length (transcript-bytes)))
   (send #"y")
   (check-true
    (wait-for-output! #"NORMAL" 12 copy-start)
    "Visual Block copy must return to NORMAL")

   (send #"gg")
   (define replace-start (bytes-length (transcript-bytes)))
   (send #"R")
   (check-true
    (wait-for-output! #"REPLACE" 12 replace-start)
    "R must enter Replace")
   (send #"Z")
   (send #"\33")
   (send #"l")
   (define repeat-start (bytes-length (transcript-bytes)))
   (send #".")
   (check-true
    (wait-for-output! #"ZbZd" 12 repeat-start)
    (string-append "dot must repeat the last Replace edit; "
                   (repeat-diagnostic repeat-start)))
   (send #":")
   (send #"save-associated-document")
   (send #"\r")

	   (define exit-start (bytes-length (transcript-bytes)))
	   (send #":")
	   (send #"request-editor-exit")
	   (check-true
	    (wait-for-output! #"request-editor-exit" 12 exit-start)
	    "command entry must receive request-editor-exit")
	   (send #"\r" 0)
	   (define exited? (sync/timeout 15 process))
	   (unless exited? (subprocess-kill process #t))
   (subprocess-wait process)
   (define errors (port->bytes error-output))
   (define captured (transcript-bytes))
   (close-output-port input)
   (close-input-port output)
   (close-input-port error-output)

   (check-not-false exited? "Visual Block editor session did not exit")
   (check-equal? (subprocess-status process) 0)
   (check-equal? errors #"")
   (check-true
    (contains? captured #"\33[?25h\33[?2026l")
    "terminal cleanup must restore the cursor and leave synchronized output")
   (check-equal? (file->bytes document-path) #"ZbZd\nxy\nalpha\n"))
 (lambda ()
   (when (directory-exists? root) (delete-directory/files root))))
