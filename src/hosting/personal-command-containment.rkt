#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/sandbox
         "../command/personal-limits.rkt")

(provide
 (struct-out personal-command-turn-inspection)
 (contract-out
  [call-with-personal-command-turn
   (-> string? string? exact-positive-integer? personal-command-limits?
       (-> any/c) any/c)]
  [personal-command-last-turn
   (-> (or/c #f personal-command-turn-inspection?))]
  [personal-command-safe-diagnostic
   (-> string? string? exact-positive-integer? string?)]
  [personal-command-containment-reset! (-> void?)]))

(struct personal-command-turn-inspection
  (command provenance generation disposition elapsed-milliseconds
           memory-bytes deadline-milliseconds memory-limit-bytes diagnostic)
  #:transparent)

(define current-personal-command-turn (make-parameter #f))
(define last-turn #f)

;; call-with-personal-command-turn gives one invocation a fresh custodian,
;; deadline, memory ceiling, single-entry dynamic extent, and bounded failure.
(define (call-with-personal-command-turn command provenance generation limits thunk)
  (when (current-personal-command-turn)
    (raise-contained-failure
     'reentry command provenance generation limits 0 0
     "recursive editor entry is unavailable"))
  (define started (current-inexact-monotonic-milliseconds))
  (define memory-before (current-memory-use))
  (define completed? #f)
  (define command-custodian (make-custodian))
  (define (usage disposition diagnostic)
    (personal-command-turn-inspection
     command provenance generation disposition
     (max 0 (inexact->exact
             (ceiling (- (current-inexact-monotonic-milliseconds) started))))
     (max 0 (- (current-memory-use) memory-before))
     (personal-command-limits-deadline-milliseconds limits)
     (personal-command-limits-custodian-memory-bytes limits)
     diagnostic))
  (with-handlers
      ([exn:fail:resource?
        (lambda (failure)
          (define code
            (if (eq? (exn:fail:resource-resource failure) 'time)
                'timeout
                'memory-limit))
          (define diagnostic
            (format "Personal command ~a failed: ~a"
                    command
                    (if (eq? code 'timeout)
                        "execution deadline exceeded"
                        "memory limit exceeded")))
          (set! last-turn (usage code diagnostic))
          (raise
           (exn:fail
            diagnostic
            (current-continuation-marks))))]
       [exn?
        (lambda (failure)
          (define memory-failure?
            (regexp-match? #rx"out of memory" (exn-message failure)))
          (define diagnostic
            (if memory-failure?
                (format "Personal command ~a failed: memory limit exceeded" command)
                (personal-command-safe-diagnostic
                 command (exn-message failure)
                 (personal-command-limits-diagnostic-bytes limits))))
          (set! last-turn (usage (if memory-failure? 'memory-limit 'exception)
                                 diagnostic))
          (raise (exn:fail diagnostic (current-continuation-marks))))])
    (define result
      (dynamic-wind
       void
       (lambda ()
         (call-with-limits
          (/ (personal-command-limits-deadline-milliseconds limits) 1000.0)
          (max 1
               (quotient
                (personal-command-limits-custodian-memory-bytes limits)
                (* 1024 1024)))
          (lambda ()
            (parameterize ([current-custodian command-custodian])
              (dynamic-wind
               (lambda ()
                 (when completed?
                   (error 'personal-command
                          "completed continuation cannot resume")))
               (lambda ()
                 (parameterize ([current-personal-command-turn command])
                   (thunk)))
               (lambda () (set! completed? #t)))))))
       (lambda () (custodian-shutdown-all command-custodian))))
    (set! last-turn (usage 'completed ""))
    result))

(define (personal-command-safe-diagnostic command detail maximum-bytes)
  (define without-paths
    (regexp-replace*
     #px"(?:[A-Za-z]:)?/(?:[^[:space:]/]+/)+[^[:space:]]*"
     detail
     "<path>"))
  (define visible
    (list->string
     (for/list ([character (in-string without-paths)]
                #:when (and (char>=? character #\space)
                            (not (= (char->integer character) 127))))
       character)))
  (define prefix (format "Personal command ~a failed: " command))
  (define budget (max 0 (- maximum-bytes
                           (bytes-length (string->bytes/utf-8 prefix)))))
  (string-append prefix (truncate-utf8 visible budget)))

(define (truncate-utf8 value maximum-bytes)
  (let loop ([characters (string->list value)] [used 0] [accepted '()])
    (cond
      [(null? characters) (list->string (reverse accepted))]
      [else
       (define character-bytes
         (bytes-length (string->bytes/utf-8 (string (car characters)))))
       (if (> (+ used character-bytes) maximum-bytes)
           (list->string (reverse accepted))
           (loop (cdr characters) (+ used character-bytes)
                 (cons (car characters) accepted)))])))

(define (raise-contained-failure
         code command provenance generation limits elapsed memory diagnostic)
  (set! last-turn
        (personal-command-turn-inspection
         command provenance generation code elapsed memory
         (personal-command-limits-deadline-milliseconds limits)
         (personal-command-limits-custodian-memory-bytes limits)
         diagnostic))
  (raise (exn:fail diagnostic (current-continuation-marks))))

(define (personal-command-last-turn) last-turn)

(define (personal-command-containment-reset!)
  (set! last-turn #f)
  (void))

(module+ test
  (require rackunit)

  (define fast-limits
    (make-personal-command-limits
     #:deadline-milliseconds 50
     #:custodian-memory-bytes (* 8 1024 1024)))

  (check-equal?
   (call-with-personal-command-turn "ok" "modules/ok.rkt" 3 fast-limits
                                    (lambda () 'ok))
   'ok)
  (check-eq? (personal-command-turn-inspection-disposition
              (personal-command-last-turn))
             'completed)

  (check-exn
   #rx"deadline exceeded"
   (lambda ()
     (call-with-personal-command-turn
      "loop" "modules/loop.rkt" 3 fast-limits
      (lambda () (let loop () (loop))))))

  (check-exn
   #rx"memory limit exceeded"
   (lambda ()
     (call-with-personal-command-turn
      "allocate" "modules/allocate.rkt" 3 fast-limits
      (lambda () (make-bytes (* 64 1024 1024))))))

  (define child #f)
  (call-with-personal-command-turn
   "child" "modules/child.rkt" 3 fast-limits
   (lambda ()
     (set! child (thread (lambda () (sync never-evt))))
     (void)))
  (check-true (thread-dead? child))

  (define escaped-continuation #f)
  (check-equal?
   (call-with-personal-command-turn
    "continuation" "modules/continuation.rkt" 3 fast-limits
    (lambda ()
      (call-with-current-continuation
       (lambda (continuation)
         (set! escaped-continuation continuation)
         'initial))))
   'initial)
  (check-exn #rx"completed continuation cannot resume"
             (lambda () (escaped-continuation 'resumed)))

  (check-exn
   #rx"<path>"
   (lambda ()
     (call-with-personal-command-turn
      "failure" "modules/failure.rkt" 3 fast-limits
      (lambda () (error 'user "bad /home/example/private\u001b[31m")))))
  (check-false
   (regexp-match? #rx"/home/example"
                  (personal-command-turn-inspection-diagnostic
                   (personal-command-last-turn))))

  (check-exn
   #rx"recursive editor entry"
   (lambda ()
     (call-with-personal-command-turn
      "outer" "modules/outer.rkt" 3 fast-limits
      (lambda ()
        (call-with-personal-command-turn
         "inner" "modules/inner.rkt" 3 fast-limits void)))))
  (personal-command-containment-reset!)
  (check-false (personal-command-last-turn)))
