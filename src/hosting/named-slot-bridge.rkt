#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         "../saved-state/named-layouts.rkt"
         "../saved-state/named-slots.rkt"
         "../saved-state/records.rkt")

(provide
 (contract-out
  [runtime-named-slot-command-batch (-> bytes? bytes? list?)]))

(define schema-version 1)
(define request-header-bytes 72)
(define result-header-bytes 48)
(define slot-record-bytes 64)
(define maximum-copy-bytes (* 4 1024 1024))

(define (word value) (integer->integer-bytes value 8 #f #f))
(define (signed-word value) (integer->integer-bytes value 8 #t #f))
(define (words . values) (apply bytes-append (map word values)))
(define (read-word input offset)
  (integer-bytes->integer input #f #f offset (+ offset 8)))
(define (read-signed-word input offset)
  (integer-bytes->integer input #t #f offset (+ offset 8)))

(define (runtime-named-slot-command-batch configuration-root-bytes request)
  (with-handlers ([exn? (lambda (failure)
                          (list #f #"" (string->bytes/utf-8 (exn-message failure))))])
    (define configuration-root (bytes->string/utf-8 configuration-root-bytes #f))
    (define-values (action name text target summary scalar replace-conflict?)
      (decode-request request))
    (define result
      (case action
        [(1) (named-slot-store configuration-root #:name name #:kind 'integer
                               #:value scalar #:replace-conflict? replace-conflict?)]
        [(2) (named-slot-increment configuration-root #:name name #:delta scalar)]
        [(3) (named-slot-store configuration-root #:name name #:kind 'text
                               #:value text #:replace-conflict? replace-conflict?)]
        [(4) (named-slot-store
              configuration-root #:name name #:kind 'position
              #:value (named-position #:target target #:point scalar #:summary summary)
              #:replace-conflict? replace-conflict?)]
        [(5) (named-slots-list configuration-root)]
        [(6) (named-slot-lookup configuration-root #:name name #:kind 'text)]
        [(7) (named-slot-store configuration-root #:name name #:kind 'layout
                               #:value (string->named-layout text)
                               #:replace-conflict? replace-conflict?)]
        [(8) (named-slot-lookup configuration-root #:name name #:kind 'layout)]
        [else (raise-arguments-error 'runtime-named-slot-command-batch
                                      "invalid named slot action")]))
    (list #t (encode-result action result) #"")))

(define (decode-request request)
  (unless (>= (bytes-length request) request-header-bytes)
    (raise-arguments-error 'runtime-named-slot-command-batch "truncated request"))
  (define schema (read-word request 0))
  (define action (read-word request 8))
  (define name-bytes (read-word request 16))
  (define text-bytes (read-word request 24))
  (define target-bytes (read-word request 32))
  (define summary-bytes (read-word request 40))
  (define scalar (if (memq action '(1 2))
                     (read-signed-word request 48)
                     (read-word request 48)))
  (define replace-conflict? (read-word request 56))
  (define reserved (read-word request 64))
  (unless (and (= schema schema-version) (<= 1 action 8)
               (<= name-bytes maximum-named-location-name-bytes)
               (<= text-bytes maximum-named-entry-text-bytes)
               (<= target-bytes 4096)
               (<= summary-bytes maximum-named-location-summary-bytes)
               (<= replace-conflict? 1) (= reserved 0))
    (raise-arguments-error 'runtime-named-slot-command-batch "invalid request header"))
  (define offset request-header-bytes)
  (define (take-text length)
    (define end (+ offset length))
    (unless (<= end (bytes-length request))
      (raise-arguments-error 'runtime-named-slot-command-batch "truncated request text"))
    (define value (bytes->string/utf-8 (subbytes request offset end) #f))
    (set! offset end)
    value)
  (define name (take-text name-bytes))
  (define text (take-text text-bytes))
  (define target (take-text target-bytes))
  (define summary (take-text summary-bytes))
  (unless (= offset (bytes-length request))
    (raise-arguments-error 'runtime-named-slot-command-batch "trailing request bytes"))
  (values action name text target summary scalar (= replace-conflict? 1)))

(define (kind-code kind)
  (case kind [(integer) 1] [(text) 2] [(position) 3] [(location) 4] [(layout) 5]
    [else 0]))

(define (encode-result action result)
  (cond
    [(odra-named-slots-failure? result)
     (define diagnostic (string->bytes/utf-8 (odra-named-slots-failure-message result)))
     (bytes-append
      (words schema-version action 0
             (kind-code (odra-named-slots-failure-conflict-kind result))
             0 (bytes-length diagnostic))
      diagnostic)]
    [(odra-named-slots-state? result)
     (define slots (odra-named-slots-state-slots result))
     (define text-output (open-output-bytes))
     (define (add-text value)
       (define bytes (string->bytes/utf-8 value))
       (define offset (file-position text-output))
       (write-bytes bytes text-output)
       (values offset (bytes-length bytes)))
     (define records-output (open-output-bytes))
     (for ([slot (in-list slots)])
       (define-values (name-offset name-bytes) (add-text (odra-named-slot-name slot)))
       (define kind (odra-named-slot-kind slot))
       (define scalar 0)
       (define value-offset 0)
       (define value-bytes 0)
       (define summary-offset 0)
       (define summary-bytes 0)
       (case kind
         [(integer) (set! scalar (odra-named-slot-value slot))]
         [(text)
          (define-values (offset length) (add-text (odra-named-slot-value slot)))
          (set! value-offset offset)
          (set! value-bytes length)]
         [(position)
          (define position (odra-named-slot-value slot))
          (set! scalar (odra-named-position-point position))
          (define-values (offset length) (add-text (odra-named-position-target position)))
          (set! value-offset offset)
          (set! value-bytes length)
          (define-values (s-offset s-length) (add-text (odra-named-position-summary position)))
          (set! summary-offset s-offset)
          (set! summary-bytes s-length)]
         [(layout)
          (define-values (offset length)
            (add-text (named-layout->string (odra-named-slot-value slot))))
          (set! value-offset offset)
          (set! value-bytes length)])
       (write-bytes (words name-offset name-bytes (kind-code kind)) records-output)
       (write-bytes (if (eq? kind 'integer) (signed-word scalar) (word scalar)) records-output)
       (write-bytes (words value-offset value-bytes summary-offset summary-bytes) records-output))
     (define text (get-output-bytes text-output))
     (define records (get-output-bytes records-output))
     (define total (+ result-header-bytes (bytes-length records) (bytes-length text)))
     (when (> total maximum-copy-bytes)
       (error 'runtime-named-slot-command-batch "Named slots exceed copied storage"))
     (bytes-append
      (words schema-version action 1 (odra-named-slots-state-generation result)
             (length slots) (bytes-length text))
      records text)]
    [else (raise-arguments-error 'runtime-named-slot-command-batch
                                  "invalid named slot result" result)]))

(module+ test
  (require racket/file rackunit)
  (define root (make-temporary-file "odra-named-slot-bridge~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind
    void
    (lambda ()
      (define name #"counter")
      (define request
        (bytes-append
         (words schema-version 1 (bytes-length name) 0 0 0)
         (signed-word -3) (words 0 0) name))
      (define stored (runtime-named-slot-command-batch (path->bytes root) request))
      (check-true (car stored))
      (check-equal? (read-word (cadr stored) 16) 1)
      (check-equal? (read-signed-word (cadr stored) (+ result-header-bytes 24)) -3)
      (define layout-text "ODRA-LAYOUT-1\nV\t1\t0\tL3RtcC9sYXlvdXQub2Rpbg==")
      (define layout-name #"layout")
      (define layout-bytes (string->bytes/utf-8 layout-text))
      (define layout-request
        (bytes-append
         (words schema-version 7 (bytes-length layout-name) (bytes-length layout-bytes)
                0 0 0 0 0)
         layout-name layout-bytes))
      (define layout-stored
        (runtime-named-slot-command-batch (path->bytes root) layout-request))
      (check-true (car layout-stored))
      (check-equal? (read-word (cadr layout-stored) 32) 2))
    (lambda () (delete-directory/files root))))
