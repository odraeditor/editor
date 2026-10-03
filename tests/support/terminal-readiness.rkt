#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/format
         racket/port
         racket/system)

(provide terminal-frame-ready-marker
         wait-for-terminal-readiness!)

(define diagnostic-byte-limit 4096)
(define terminal-frame-ready-marker #"\33[?2026l")

(define (contains-bytes? haystack needle)
  (regexp-match? (byte-regexp (regexp-quote needle)) haystack))

(define (terminal-ready? transcript marker content-marker)
  (cond
    [(not content-marker) (contains-bytes? transcript marker)]
    [else
     (define content-position
       (regexp-match-positions
        (byte-regexp (regexp-quote content-marker))
        transcript))
     (and content-position
          (regexp-match-positions
           (byte-regexp (regexp-quote marker))
           transcript
           (cdar content-position))
          #t)]))

(define (bounded-tail value)
  (define count (bytes-length value))
  (if (<= count diagnostic-byte-limit)
      value
      (subbytes value (- count diagnostic-byte-limit))))

(define (close-input-port-if-open port)
  (unless (port-closed? port) (close-input-port port)))

(define (close-output-port-if-open port)
  (unless (port-closed? port) (close-output-port port)))

(define (stop-process! process)
  (when (eq? (subprocess-status process) 'running)
    (subprocess-kill process #f)
    (unless (sync/timeout 1 process)
      (subprocess-kill process #t)))
  (subprocess-wait process))

(define (fail-readiness! owner marker content-marker process output input error-output transcript)
  (stop-process! process)
  (define error-bytes (port->bytes error-output))
  (close-output-port-if-open input)
  (close-input-port-if-open output)
  (close-input-port-if-open error-output)
  (raise-user-error
   owner
   (string-append
    "terminal readiness timeout; marker=~s; content-marker=~s; output-tail=~s; error-tail=~s")
   marker
   content-marker
   (bounded-tail (get-output-bytes transcript))
   (bounded-tail error-bytes)))

;; Waits for an observed terminal marker before a fixture may send input.
(define (wait-for-terminal-readiness! owner process output input error-output transcript
                                      #:content-marker [content-marker #f]
                                      #:marker [marker terminal-frame-ready-marker]
                                      #:timeout [timeout 10])
  (define read-buffer (make-bytes 4096))
  (define deadline (+ (current-inexact-milliseconds) (* timeout 1000)))
  (let loop ()
    (cond
      [(terminal-ready? (get-output-bytes transcript) marker content-marker) #t]
      [(or (not (eq? (subprocess-status process) 'running))
           (<= deadline (current-inexact-milliseconds)))
       (fail-readiness!
        owner marker content-marker process output input error-output transcript)]
      [else
       (define remaining
         (/ (- deadline (current-inexact-milliseconds)) 1000.0))
       (when (sync/timeout (min 0.25 remaining) output)
         (define count (read-bytes-avail!* read-buffer output))
         (when (exact-positive-integer? count)
           (write-bytes read-buffer transcript 0 count)))
       (loop)])))

(module+ test
  (require rackunit)

  (define shell-path (find-executable-path "sh"))
  (check-not-false shell-path "sh is required for terminal readiness tests")

  (define (start-fixture output-text)
    (subprocess #f #f #f shell-path "-c"
                (format "printf '~a'; read ignored; printf 'input-received'"
                        output-text)))

  (let-values ([(process output input error-output) (start-fixture "ready")])
    (define transcript (open-output-bytes))
    (check-true
     (wait-for-terminal-readiness!
      'terminal-readiness-test process output input error-output transcript
      #:marker #"ready"
      #:timeout 1))
    (close-output-port input)
    (subprocess-wait process)
    (close-input-port output)
    (close-input-port error-output))

  (let-values ([(process output input error-output) (start-fixture "booting")])
    (define transcript (open-output-bytes))
    (check-exn
     #rx"terminal readiness timeout.*marker.*missing"
     (lambda ()
       (wait-for-terminal-readiness!
        'terminal-readiness-test process output input error-output transcript
        #:content-marker #"missing"
        #:marker #"booting"
        #:timeout 0.05)))
    (check-not-equal? (subprocess-status process) 'running)
    (check-false (contains-bytes? (get-output-bytes transcript) #"input-received"))))
