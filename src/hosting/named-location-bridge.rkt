#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         "../saved-state/named-locations.rkt"
         "../saved-state/records.rkt")

(provide
 (contract-out
  [runtime-named-location-command-batch (-> bytes? bytes? list?)]))

(define schema-version 1)
(define request-header-bytes 64)
(define result-header-bytes 48)
(define location-record-bytes 72)
(define maximum-copy-bytes (* 4 1024 1024))
(define absent-mark #xffffffffffffffff)

(define (word value) (integer->integer-bytes value 8 #f #f))
(define (words . values) (apply bytes-append (map word values)))
(define (read-word input offset)
  (integer-bytes->integer input #f #f offset (+ offset 8)))

(define (runtime-named-location-command-batch configuration-root-bytes request)
  (with-handlers ([exn? (lambda (failure)
                          (list #f #"" (string->bytes/utf-8 (exn-message failure))))])
    (define configuration-root (bytes->string/utf-8 configuration-root-bytes #f))
    (define-values (action name target point mark region-active? summary)
      (decode-request request))
    (define result
      (case action
        [(1) (named-locations-save
              configuration-root #:name name #:target target #:point point #:mark mark
              #:region-active? region-active? #:summary summary)]
        [(2) (named-locations-list configuration-root)]
        [else (raise-arguments-error 'runtime-named-location-command-batch
                                      "invalid named location action")]))
    (list #t (encode-result action result) #"")))

(define (decode-request request)
  (unless (>= (bytes-length request) request-header-bytes)
    (raise-arguments-error 'runtime-named-location-command-batch "truncated request"))
  (define schema (read-word request 0))
  (define action (read-word request 8))
  (define name-bytes (read-word request 16))
  (define target-bytes (read-word request 24))
  (define point (read-word request 32))
  (define mark (read-word request 40))
  (define region-active? (read-word request 48))
  (define summary-bytes (read-word request 56))
  (unless (and (= schema schema-version) (<= 1 action 2)
               (<= name-bytes maximum-named-location-name-bytes)
               (<= target-bytes 4096) (<= summary-bytes maximum-named-location-summary-bytes)
               (or (= mark absent-mark) (<= mark (sub1 (expt 2 64))))
               (<= region-active? 1))
    (raise-arguments-error 'runtime-named-location-command-batch "invalid request header"))
  (define offset request-header-bytes)
  (define (take-text length)
    (define end (+ offset length))
    (unless (<= end (bytes-length request))
      (raise-arguments-error 'runtime-named-location-command-batch "truncated request text"))
    (define value (bytes->string/utf-8 (subbytes request offset end) #f))
    (set! offset end)
    value)
  (define name (take-text name-bytes))
  (define target (take-text target-bytes))
  (define summary (take-text summary-bytes))
  (unless (= offset (bytes-length request))
    (raise-arguments-error 'runtime-named-location-command-batch "trailing request bytes"))
  (values action name target point (and (not (= mark absent-mark)) mark)
          (= region-active? 1) summary))

(define (encode-result action result)
  (cond
    [(odra-named-locations-failure? result)
     (define diagnostic (string->bytes/utf-8 (odra-named-locations-failure-message result)))
     (bytes-append (words schema-version action 0 0 0 (bytes-length diagnostic)) diagnostic)]
    [(odra-named-locations-state? result)
     (define locations (odra-named-locations-state-locations result))
     (define text-output (open-output-bytes))
     (define (add-text value)
       (define bytes (string->bytes/utf-8 value))
       (define offset (file-position text-output))
       (write-bytes bytes text-output)
       (values offset (bytes-length bytes)))
     (define locations-output (open-output-bytes))
     (for ([location (in-list locations)])
       (define-values (name-offset name-bytes) (add-text (odra-named-location-name location)))
       (define-values (target-offset target-bytes) (add-text (odra-named-location-target location)))
       (define-values (summary-offset summary-bytes) (add-text (odra-named-location-summary location)))
       (write-bytes
        (words name-offset name-bytes target-offset target-bytes
               (odra-named-location-point location)
               (or (odra-named-location-mark location) absent-mark)
               (if (odra-named-location-region-active? location) 1 0)
               summary-offset summary-bytes)
        locations-output))
     (define text (get-output-bytes text-output))
     (define location-bytes (get-output-bytes locations-output))
     (define total (+ result-header-bytes (bytes-length location-bytes) (bytes-length text)))
     (when (> total maximum-copy-bytes)
       (error 'runtime-named-location-command-batch "Named locations exceed copied storage"))
     (bytes-append
      (words schema-version action 1
             (odra-named-locations-state-generation result)
             (length locations) (bytes-length text))
      location-bytes text)]
    [else (raise-arguments-error 'runtime-named-location-command-batch
                                  "invalid named location result" result)]))

(module+ test
  (require racket/file rackunit)

  (define root (make-temporary-file "odra-named-location-bridge~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind
    void
    (lambda ()
      (define name #"first")
      (define target #"/tmp/first.odin")
      (define summary #"first.odin")
      (define save-request
        (bytes-append
         (words schema-version 1 (bytes-length name) (bytes-length target)
                3 absent-mark 0 (bytes-length summary))
         name target summary))
      (define saved
        (runtime-named-location-command-batch (path->bytes root) save-request))
      (check-true (car saved))
      (check-equal? (read-word (cadr saved) 16) 1)
      (check-equal? (read-word (cadr saved) 24) 1)
      (define list-request (words schema-version 2 0 0 0 absent-mark 0 0))
      (define listed
        (runtime-named-location-command-batch (path->bytes root) list-request))
      (check-true (car listed))
      (check-equal? (read-word (cadr listed) 8) 2)
      (check-equal? (read-word (cadr listed) 32) 1))
    (lambda () (delete-directory/files root))))
