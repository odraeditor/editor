#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "../../../src/command/transform.rkt")

(provide command-inspection-request-probe
         command-transform-probe
         command-uppercase-current-line-probe)

(define (command-inspection-request-probe scenario capability buffer-id revision)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f 0 0 (string->bytes/utf-8 (exn-message failure))))])
    (unless (<= 0 scenario 4)
      (raise-argument-error
       'command-inspection-request-probe "an integer from 0 through 4" scenario))
    (command-inspection-request capability buffer-id revision)))

(define (command-uppercase-current-line-probe
         scenario capability buffer-id revision start end source)
  (transform-probe-envelope
   'command-uppercase-current-line-probe
   scenario capability buffer-id revision start end source
   #:oversized? #t))

(define (command-transform-probe
         scenario capability buffer-id revision start end source)
  (transform-probe-envelope
   'command-transform-probe
   scenario capability buffer-id revision start end source))

(define (transform-probe-envelope
         who scenario capability buffer-id revision start end source
         #:oversized? [oversized? #f])
  (cond
    [(= scenario 2) (list #t 'wrong-result #"")]
    [else
     (with-handlers ([exn?
                      (lambda (failure)
                        (list #f 0 0 0 0 0 #""
                              (string->bytes/utf-8 (exn-message failure))))])
       (when (= scenario 1)
         (error who "requested Racket command failure"))
       (when (= scenario 4) (collect-garbage))
       (unless (= (- end start) (bytes-length source))
         (error who "inspection length mismatch"))
       (define replacement
         (cond
           [(= scenario 3) #"\377"]
           [(and oversized? (= scenario 6))
            (make-bytes 4097 (char->integer #\X))]
           [else (uppercase-current-line source)]))
       (list #t capability
             (if (= scenario 5) (add1 buffer-id) buffer-id)
             revision start end replacement #""))]))

(module+ test
  (require rackunit)
  (check-false
   (car (command-transform-probe 1 1 9 0 6 10 #"odra")))
  (check-equal?
   (command-transform-probe 2 1 9 0 6 10 #"odra")
   '(#t wrong-result #"")))
