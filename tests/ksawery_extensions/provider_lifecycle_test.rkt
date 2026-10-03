#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/hosting/personal-configuration-bridge.rkt")

(define (word value offset)
  (integer-bytes->integer value #f #f offset (+ offset 8)))

(define (extension-start batch)
  (+ 464
     (word batch 40)
     (word batch 152)
     (word batch 160)
     (word batch 168)
     (word batch 328)))

(define (write-contributor root generation [valid? #t])
  (make-directory* root)
  (call-with-output-file (build-path root "init.rkt")
    (lambda (output)
      (display
       (if valid?
           (format
            (string-append
             "#lang racket/base\n"
             "(require odra/commands)\n"
             "(provide odra-ksawery-contributor)\n"
             "(define odra-ksawery-contributor\n"
             "  (make-ksawery-contributor\n"
             "   'personal.repository-tools \"Repository tools\"\n"
             "   \"~a/init.rkt\" ~a\n"
             "   (list (make-ksawery-contribution\n"
             "          7 'status.ahead-behind 'status-section\n"
             "          #:observations '(status refs)\n"
             "          #:authorities '(inspect present)))))\n")
            (path->string root) generation)
           (string-append
            "#lang racket/base\n"
            "(provide odra-ksawery-contributor)\n"
            "(define odra-ksawery-contributor 'invalid)\n"))
       output))
    #:exists 'truncate/replace))

(test-case "personal contributor generations encode, replace, and reject atomically"
  (define temporary (make-temporary-file "odra-ksawery-provider-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define root (build-path temporary "config" "odra"))
     (write-contributor root 5)
     (define startup
       (runtime-personal-configuration-startup-batch (path->bytes root)))
     (check-equal? (list (car startup) (bytes->string/utf-8 (caddr startup)))
                   '(#t ""))
     (define first (cadr startup))
     (check-equal? (word first 0) 10)
     (check-equal?
      (list (word first 8) (word first 16)
            (bytes->string/utf-8
             (subbytes first 352 (+ 352 (word first 40)))))
      '(1 2 ""))
     (check-true (> (word first 336) 0))
     (define first-extension (extension-start first))
     (check-equal? (word first first-extension) 1)
     (check-equal? (word first (+ first-extension 24)) (word first 24))
     (check-equal? (word first (+ first-extension 104)) 5)
     (check-equal?
      (runtime-personal-generation-transition 1 (word first 24))
      '(#t #t #""))

     (write-contributor root 6)
     (define replacement
       (runtime-personal-configuration-reload-batch
        (path->bytes root) (word first 24)))
     (check-true (car replacement))
     (define second (cadr replacement))
     (check-equal? (word second 24) (add1 (word first 24)))
     (check-true (> (word second 336) 0))
     (define second-extension (extension-start second))
     (check-equal? (word second (+ second-extension 104)) 6)
     (check-equal?
      (runtime-personal-generation-transition 1 (word second 24))
      '(#t #t #""))

     (write-contributor root 7 #f)
     (define rejected
       (runtime-personal-configuration-reload-batch
        (path->bytes root) (word second 24)))
     (check-true (car rejected))
     (check-equal? (word (cadr rejected) 8) 2)
     (check-equal? (word (cadr rejected) 24) (word second 24))
     (check-equal? (word (cadr rejected) 336) 0))
   (lambda () (delete-directory/files temporary))))

(test-case "absent contributor keeps the built-in fallback and emits no provider batch"
  (define temporary (make-temporary-file "odra-ksawery-fallback-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define startup
       (runtime-personal-configuration-startup-batch
        (path->bytes (build-path temporary "config" "odra"))))
     (check-true (car startup))
     (check-equal? (word (cadr startup) 8) 1)
     (check-equal? (word (cadr startup) 336) 0))
   (lambda () (delete-directory/files temporary))))
