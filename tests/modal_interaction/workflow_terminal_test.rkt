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
(check-not-false script-path "util-linux script is required for modal interaction acceptance")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (contains? haystack needle)
  (regexp-match? (byte-regexp (regexp-quote needle)) haystack))

(define root (make-temporary-file "odra-modal-interaction-~a" 'directory))

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
     (lambda (output) (display "alpha beta alpha gamma alpha\n" output)))
   (define secondary-path (build-path root "secondary.txt"))
   (call-with-output-file secondary-path #:exists 'truncate/replace
     (lambda (output) (display "secondary modal buffer\n" output)))
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
   (define (visible-bytes captured)
     (string->bytes/utf-8
      (regexp-replace*
       #px"\u001b\\[[0-?]*[ -/]*[@-~]"
       (bytes->string/utf-8 captured #\?)
       "")))
   (define (wait-for-output! value [timeout 12] [after 0])
     (define deadline (+ (current-inexact-milliseconds) (* timeout 1000)))
     (let loop ()
       (define captured (transcript-bytes))
       (cond
         [(and (<= after (bytes-length captured))
               (let ([recent (subbytes captured after)])
                 (or (contains? recent value)
                     (contains? (visible-bytes recent) value))))
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
   (define (execute-command name)
     (send #"\33x")
     (send (string->bytes/utf-8 name))
     (send #"\r"))

   (check-true (wait-for-output! #"NORMAL") "modal startup must show NORMAL")
   (check-true (wait-for-output! #"\33[2 q") "Normal must use a block cursor")
   (send #"2fa")
   (send #";")
   (send #",")
   (define insert-start (bytes-length (transcript-bytes)))
   (send #"i")
   (check-true (wait-for-output! #"INSERT" 12 insert-start) "i must enter INSERT")
   (check-true (wait-for-output! #"\33[6 q" 12 insert-start) "Insert must use a bar cursor")
   (send #"Z")
   (define normal-start (bytes-length (transcript-bytes)))
   (send #"\33")
   (check-true (wait-for-output! #"NORMAL" 12 normal-start) "Escape must return to NORMAL")

   (send #"gg2wiY")
   (send #"\33")
   (define search-start (bytes-length (transcript-bytes)))
   (send #"/")
   (check-true (wait-for-output! #"Search " 12 search-start) "/ must open canonical search")
   (send #"alpha\r")
   (send #"niQ")
   (send #"\33")
   (send #"2NiR")
   (send #"\33")

   (send #"ggdd")
   (send #"u")
   (define visual-start (bytes-length (transcript-bytes)))
   (send #"ggv")
   (check-true
    (wait-for-output! #"VISUAL" 12 visual-start)
    "v must enter Visual Character")
   (send #"ly")
   (check-true
    (wait-for-output! #"NORMAL" 12 visual-start)
    "Visual copy must return to NORMAL")

   (send #":")
   (send #"save-associated-document")
   (send #"\r")

   (send (bytes 23 118))
   (send (bytes 23 104))
   (send (bytes 23 108))
   (execute-command "find-file")
   (send #"~/secondary.txt\r")
   (check-true
    (wait-for-output! #"secondary modal buffer")
    "secondary buffer must be presented in the split layout")
   (execute-command "find-file")
   (send #"~/sample.txt\r")
   (check-true
    (wait-for-output! #"alpha gamma")
    "the edited document buffer must remain available")

   (define terminal-insert-start (bytes-length (transcript-bytes)))
   (send #"i")
   (check-true
    (wait-for-output! #"INSERT" 12 terminal-insert-start)
    "terminal entry must begin from INSERT")
   (execute-command "terminal-new")
   (define live-start (bytes-length (transcript-bytes)))
   (send #"printf 'MODAL-LIVE\\n'\r" 0.5)
   (check-true
    (wait-for-output! #"MODAL-LIVE" 12 live-start)
    "live terminal input must reach the child")

   (send
    #"stty raw -echo; byte=$(dd bs=1 count=1 2>/dev/null | od -An -tx1); stty sane; printf 'ESCAPE-BYTE:%s\\n' \"$byte\"\r"
    0.5)
   (define escape-start (bytes-length (transcript-bytes)))
   (send #"\33")
   (check-true
    (wait-for-output! #"ESCAPE-BYTE: 1b" 12 escape-start)
    "ordinary terminal Escape must reach the child")
   (check-true
    (wait-for-output! #"INSERT" 12 escape-start)
    "ordinary terminal Escape must preserve modal INSERT")

   (define copy-start (bytes-length (transcript-bytes)))
   (send (bytes 28 14))
   (check-true
    (wait-for-output! #"NORMAL" 12 copy-start)
    "C-backslash C-n must enter modal terminal copy navigation")
   (send #"h")
   (define copy-done-start (bytes-length (transcript-bytes)))
   (send #"i")
   (check-true
    (wait-for-output! #"INSERT" 12 copy-done-start)
    "i must finish terminal copy mode in INSERT")

   (send
    #"stty raw -echo; byte=$(dd bs=1 count=1 2>/dev/null | od -An -tx1); stty sane; printf 'LITERAL-BYTE:%s\\n' \"$byte\"\r"
    0.5)
   (execute-command "terminal-send-next-key")
   (define literal-start (bytes-length (transcript-bytes)))
   (send (bytes 17))
   (check-true
    (wait-for-output! #"LITERAL-BYTE: 11" 12 literal-start)
    "terminal-send-next-key must forward one intercepted key")

   (execute-command "find-file")
   (send #"~/sample.txt\r")
   (define restored-start (bytes-length (transcript-bytes)))
   (send #"\33")
   (check-true
    (wait-for-output! #"NORMAL" 12 restored-start)
    "text-buffer restoration must recover modal state routing")

   (send #"\33xselect-interaction-profile\r" 0.5)
   (check-true
    (wait-for-output! #"Select interaction profile: ")
    "profile selection must require a candidate")
   (send #"direct\r" 0.5)
   (send (bytes 24 19) 0.4)
   (define exit-start (bytes-length (transcript-bytes)))
   (send (bytes 24 3))
   (check-true
    (wait-for-output! #"Exit and terminate 1 live terminal?" 12 exit-start)
    "exit must confirm termination of the live terminal")
   (send #"y" 0)
   (define exited? (sync/timeout 15 process))
   (unless exited? (subprocess-kill process #t))
   (subprocess-wait process)
   (define errors (port->bytes error-output))
   (define captured (transcript-bytes))
   (close-output-port input)
   (close-input-port output)
   (close-input-port error-output)

   (check-not-false exited? "modal interaction editor session did not exit")
   (check-equal? (subprocess-status process) 0)
   (check-equal? errors #"")
   (check-true (contains? captured #"Profiles [session]"))
   (check-true
    (contains? captured #"\33[?25h\33[?2026l")
    "terminal cleanup must restore the cursor and leave synchronized output")
   (check-equal? (file->bytes document-path) #"alpha betZa YRalpha gamma alphaQ\n"))
 (lambda ()
   (when (directory-exists? root) (delete-directory/files root))))
