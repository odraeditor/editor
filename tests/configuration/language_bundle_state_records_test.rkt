#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         "../../src/language_bundle/state-records.rkt")

(define digest-a (make-string 64 #\a))
(define digest-b (make-string 64 #\b))
(define digest-c (make-string 64 #\c))
(define digest-d (make-string 64 #\d))

(define bundle
  (odra-installed-bundle
   "org.example.language" "1.0.0" digest-a (list digest-b)
   '("org.example.runtime") "catalog.example" "org.example"
   'linux 'x86-64 '("native-grammar") "user grant" 'active-confirmed
   7 #f #f))
(define lock
  (odra-activation-lock
   3 5 (hash "org.example.language" "1.0.0") (list digest-a digest-b)
   digest-c digest-d (hash "org.example.language" 7) digest-a))
(define operation
  (odra-bundle-operation
   "verify-language" 'verify 'verify 5 3 (list digest-b)
   '("/tmp/odra-operation") 'pending #f ""))
(define accounting (odra-bundle-accounting 1 1 512 4096 0))
(define state
  (language-bundle-state-with-checksum
   (odra-language-bundle-state
    2 "default" 5 3 (list bundle) lock #f (list operation) '()
    accounting (make-string 64 #\0))))

(test-case "complete installed state round trips through the versioned codec"
  (define root (make-temporary-file "odra-bundle-record-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define path (build-path root "installed-state.rktd"))
      (call-with-output-file path
        (lambda (output) (write-bytes (language-bundle-state->module-bytes state) output))
        #:exists 'truncate/replace #:mode 'binary)
      (check-equal? (language-bundle-state-module-load path) state))
    (lambda () (delete-directory/files root))))

(test-case "checksum and canonical bytes are deterministic"
  (check-equal? (language-bundle-state-checksum state)
                (odra-language-bundle-state-checksum state))
  (check-equal? (language-bundle-state->module-bytes state)
                (language-bundle-state->module-bytes state)))

(test-case "aggregate accounting rejects inconsistent state"
  (check-exn
   exn:fail?
   (lambda ()
     (odra-language-bundle-state
      2 "default" 5 3 (list bundle) lock #f (list operation) '()
      (odra-bundle-accounting 1 0 512 4096 0) digest-a))))
