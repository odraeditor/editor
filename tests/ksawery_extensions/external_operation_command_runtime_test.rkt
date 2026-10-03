#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/configuration/personal.rkt"
         "../../src/hosting/command-catalog-bridge.rkt"
         "../../src/hosting/personal-configuration-bridge.rkt")

(define (words . values)
  (apply bytes-append
         (map (lambda (value) (integer->integer-bytes value 8 #f #f)) values)))

(define (word value offset)
  (integer-bytes->integer value #f #f offset (+ offset 8)))

(define (write-external-command-provider root generation)
  (make-directory* root)
  (call-with-output-file (build-path root "init.rkt")
    (lambda (output)
      (display
       (string-append
        "#lang racket/base\n"
        "(require odra/commands)\n"
        "(provide odra-ksawery-contributor odra-ksawery-command-families)\n"
        "(define command-contribution\n"
        "  (make-ksawery-contribution\n"
        "   7 'commands.review 'command-family\n"
        "   #:observations '(refs)\n"
        "   #:authorities '(inspect submit-external-operation)))\n"
        "(define operation-contribution\n"
        "  (make-ksawery-contribution\n"
        "   8 'operations.review 'external-operation\n"
        "   #:observations '(status refs)\n"
        "   #:authorities '(inspect submit-external-operation)))\n"
        "(define odra-ksawery-contributor\n"
        "  (make-ksawery-contributor\n"
        "   'personal.repository-tools \"Repository tools\"\n"
        "   \"modules/repository-tools.rkt\" "
        (number->string generation)
        " (list command-contribution operation-contribution)))\n"
        "(define operation-action\n"
        "  (make-ksawery-command-action\n"
        "   1 'action.review \"Review repository\" 'submit-external-operation '(refs)\n"
        "   #:targets '(ref) #:operation 'idle #:confirmation-required? #t\n"
        "   #:external-operation\n"
        "   (lambda (_context values)\n"
        "     (make-ksawery-operation-plan\n"
        "      odra-ksawery-contributor 8 21 'operation.review \"Review repository\" 23\n"
        "      (make-ksawery-operation-git)\n"
        "      (list \"status\" \"--short\" (ksawery-command-value-value (car values)))\n"
        "      'read-only\n"
        "      '(status refs) (make-ksawery-operation-verifier 'observation-available\n"
        "                                                       #:observation 'status)))))\n"
        "(define selector\n"
        "  (make-ksawery-command-argument\n"
        "   9 'argument.selector \"Selector\" 'text #:required? #t #:maximum-bytes 32))\n"
        "(define family\n"
        "  (make-ksawery-command-family\n"
        "   odra-ksawery-contributor 7 11 'family.review \"Review tools\" 17\n"
        "   '(refs) (list selector) (list operation-action)))\n"
        "(define odra-ksawery-command-families (list family))\n")
       output))
    #:exists 'truncate/replace))

(define (catalog-extension-route batch)
  (define count (word batch 32))
  (define text-start (+ 64 (* 128 count)))
  (for/first ([index (in-range count)]
              #:when (= (word batch (+ 64 (* index 128))) 4))
    (define record (+ 64 (* index 128)))
    (define offset (word batch (+ record 48)))
    (define length (word batch (+ record 56)))
    (list (add1 index)
          (subbytes batch (+ text-start offset) (+ text-start offset length)))))

(define repository #"/tmp/repository")
(define target #"refs/heads/main")
(define context
  (bytes-append
   (words 1 (+ 184 (bytes-length repository) (bytes-length target))
          3 5 11 13 2 19 2 23 29 1 5 19 1 1 31 0 1
          184 (bytes-length repository) (+ 184 (bytes-length repository))
          (bytes-length target))
   repository target))

(define (submission confirmation)
  (define payload #"branch")
  (bytes-append
   (words 1 (+ 80 (bytes-length context) 72 (bytes-length payload))
          71 11 17 1 confirmation 1 (bytes-length context) (bytes-length payload))
   context
   (words 9 3 0 0 (bytes-length payload) 0 0 0 0)
   payload))

(test-case "contributed commands return one generation-bound external-operation plan"
  (define temporary
    (make-temporary-file "odra-ksawery-external-command-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define root (build-path temporary "config" "odra"))
     (write-external-command-provider root 5)
     (define observation (personal-config-load (personal-config-source root)))
     (check-equal? (odra-personal-config-observation-state observation) 'confirmed)
     (define startup
       (runtime-personal-configuration-startup-batch (path->bytes root)))
     (check-true (car startup) (bytes->string/utf-8 (caddr startup)))
     (define generation (word (cadr startup) 24))
     (define catalog (runtime-command-catalog-batch generation))
     (check-true (car catalog) (bytes->string/utf-8 (cadddr catalog)))
     (define route (catalog-extension-route (caddr catalog)))
     (check-equal? (runtime-personal-generation-transition 1 generation)
                   '(#t #t #""))
     (define result
       (runtime-ksawery-external-operation-batch
        generation (car route) (cadr route) (submission 41)))
     (check-true (car result) (bytes->string/utf-8 (caddr result)))
     (define plan (cadr result))
     (check-equal? (word plan 16) 5)
     (check-equal? (word plan 24) 8)
     (check-equal? (word plan 32) 21)
     (check-equal? (word plan 40) 23)
     (check-equal? (word plan 88) 3)
     (define unconfirmed
       (runtime-ksawery-external-operation-batch
        generation (car route) (cadr route) (submission 0)))
     (check-false (car unconfirmed))
     (check-regexp-match #rx"positive|confirmation"
                         (bytes->string/utf-8 (caddr unconfirmed))))
   (lambda () (delete-directory/files temporary))))
