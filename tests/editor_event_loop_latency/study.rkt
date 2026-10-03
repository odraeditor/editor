#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         racket/format
         racket/list
         racket/path
         racket/port
         racket/string
         racket/system
         "model.rkt"
         "../support/terminal-readiness.rkt")

(define warmup-count 3)
(define sample-count 24)
(define action-timeout-seconds 5)
(define frame-buffer-size 16384)
(define marker-text "odra-latency-marker|")
(define inserted-marker-text (string-append marker-text "Q"))

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for the latency study")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify an existing built executable or wrapper")
(check-true (file-exists? odra-path)
            "ODRA_PTY_EXECUTABLE must already exist; this study never builds Odra")

(struct workload (id file-name content) #:transparent)

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (odin-lines count)
  (string-join
   (for/list ([index (in-range count)])
     (format "value_~a :: proc() -> int { return ~a }" index index))
   "\n"))

(define workloads
  (list
   (workload "small-text" "small.txt"
             (string-append marker-text "\nsmall fixture\n"))
   (workload "medium-source" "medium.odin"
             (string-append "package main // " marker-text "\n" (odin-lines 4096) "\n"))
   (workload "stress-source" "stress.odin"
             (string-append "package main // " marker-text "\n" (odin-lines 16384) "\n"))))

(define (contains-frame-after-content? bytes content)
  (define content-position
    (regexp-match-positions
     (byte-regexp (regexp-quote content))
     bytes))
  (and content-position
       (regexp-match-positions
        (byte-regexp (regexp-quote terminal-frame-ready-marker))
        bytes
        (cdar content-position))
       #t))

(define (wait-for-frame! owner process output transcript content)
  (define captured (open-output-bytes))
  (define buffer (make-bytes frame-buffer-size))
  (define deadline
    (+ (current-inexact-monotonic-milliseconds)
       (* action-timeout-seconds 1000)))
  (let loop ()
    (cond
      [(contains-frame-after-content? (get-output-bytes captured) content) #t]
      [(not (eq? (subprocess-status process) 'running))
       (raise-user-error owner "Odra exited before presenting the measured frame")]
      [(<= deadline (current-inexact-monotonic-milliseconds))
       (raise-user-error owner "timed out waiting for the measured frame")]
      [else
       (define remaining
         (/ (- deadline (current-inexact-monotonic-milliseconds)) 1000.0))
       (when (sync/timeout (min 0.1 remaining) output)
         (define count (read-bytes-avail!* buffer output))
         (when (exact-positive-integer? count)
           (write-bytes buffer captured 0 count)
           (write-bytes buffer transcript 0 count)))
       (loop)])))

(define (send! input bytes)
  (write-bytes bytes input)
  (flush-output input))

(define (measure-action! process output input transcript content)
  (define started (current-inexact-monotonic-milliseconds))
  (send! input #"Q")
  (wait-for-frame! 'editor-event-loop-latency process output transcript content)
  (define elapsed-ns
    (inexact->exact
     (round (* 1000000 (- (current-inexact-monotonic-milliseconds) started)))))
  (send! input (bytes 127))
  (wait-for-frame!
   'editor-event-loop-latency
   process
   output
   transcript
   (string->bytes/utf-8 marker-text))
  elapsed-ns)

(define (stop-process! process input)
  (send! input (bytes-append (bytes 24 3) #"d"))
  (unless (sync/timeout 10 process)
    (subprocess-kill process #t))
  (subprocess-wait process))

(define (measure-workload! root configuration-home definition)
  (define path (build-path root (workload-file-name definition)))
  (call-with-output-file
   path
   #:exists 'truncate/replace
   (lambda (output) (display (workload-content definition) output)))
  (define command
    (string-append
     "stty rows 24 cols 120; exec env HOME="
     (shell-quote (path->string root))
     " XDG_CONFIG_HOME="
     (shell-quote (path->string configuration-home))
     " XDG_STATE_HOME="
     (shell-quote (path->string (build-path root "state")))
     " XDG_CACHE_HOME="
     (shell-quote (path->string (build-path root "cache")))
     " XDG_DATA_HOME="
     (shell-quote (path->string (build-path root "data")))
     " "
     (shell-quote odra-path)
     " "
     (shell-quote (path->string path))))
  (define-values (process output input error-output)
    (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
  (define transcript (open-output-bytes))
  (wait-for-terminal-readiness!
   'editor-event-loop-latency
   process
   output
   input
   error-output
   transcript
   #:content-marker
   (string->bytes/utf-8 (path->string (file-name-from-path path)))
   #:timeout 20)
  (send! input (bytes 5))
  (wait-for-frame!
   'editor-event-loop-latency
   process
   output
   transcript
   (string->bytes/utf-8 marker-text))
  (for ([index (in-range warmup-count)])
    (measure-action!
     process output input transcript (string->bytes/utf-8 inserted-marker-text)))
  (define samples
    (for/list ([index (in-range sample-count)])
      (latency-sample
       (workload-id definition)
       'input
       (measure-action!
        process output input transcript (string->bytes/utf-8 inserted-marker-text))
       0
       (hash))))
  (stop-process! process input)
  (define error-bytes (port->bytes error-output))
  (close-output-port input)
  (close-input-port output)
  (close-input-port error-output)
  (check-equal? (subprocess-status process) 0
                (bytes->string/utf-8 (get-output-bytes transcript) #\?))
  (check-equal? error-bytes #""
                (bytes->string/utf-8 (get-output-bytes transcript) #\?))
  (summarize-latency-samples samples))

(define (print-summary summary)
  (printf
   (string-append
    "event-loop-latency workload=~a samples=~a "
    "p50_ns=~a p95_ns=~a p99_ns=~a max_ns=~a external_wait_max_ns=~a\n")
   (latency-summary-workload-id summary)
   (latency-summary-samples summary)
   (latency-summary-p50-ns summary)
   (latency-summary-p95-ns summary)
   (latency-summary-p99-ns summary)
   (latency-summary-maximum-ns summary)
   (latency-summary-external-wait-maximum-ns summary)))

(define fixture-root (make-temporary-file "odra-event-loop-latency-~a" 'directory))
(define configuration-home
  (make-temporary-file "odra-event-loop-latency-config-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (make-directory* (build-path configuration-home "odra"))
   (for ([directory (in-list '("state" "cache" "data"))])
     (make-directory* (build-path fixture-root directory)))
   (for ([definition (in-list workloads)])
     (print-summary
      (measure-workload! fixture-root configuration-home definition))))
 (lambda ()
   (when (directory-exists? fixture-root)
     (delete-directory/files fixture-root))
   (when (directory-exists? configuration-home)
     (delete-directory/files configuration-home))))
