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

(define (word value offset)
  (integer-bytes->integer value #f #f offset (+ offset 8)))

(define (write-command-provider root generation [duplicate? #f])
  (make-directory* root)
  (call-with-output-file (build-path root "init.rkt")
    (lambda (output)
      (display
       (string-append
        "#lang racket/base\n"
        "(require odra/commands)\n"
        "(provide odra-ksawery-contributor odra-ksawery-command-families)\n"
        "(define contribution\n"
        "  (make-ksawery-contribution\n"
        "   7 'commands.refs 'command-family\n"
        "   #:observations '(refs)\n"
        "   #:authorities '(inspect request-core-action)))\n"
        "(define odra-ksawery-contributor\n"
        "  (make-ksawery-contributor\n"
        "   'personal.repository-tools \"Repository tools\"\n"
        "   \"modules/repository-tools.rkt\" "
        (number->string generation)
        " (list contribution)))\n"
        "(define push-action\n"
        "  (make-ksawery-command-action\n"
        "   1 'action.push \"Push\" 'request-core-action '(refs)\n"
        "   #:targets '(ref) #:operation 'idle #:core-operation 'push\n"
        "   #:mutates-repository? #t #:confirmation-required? #t))\n"
        "(define family\n"
        "  (make-ksawery-command-family\n"
        "   odra-ksawery-contributor 7 11 'family.refs \"Ref tools\" 17\n"
        "   '(refs) '() (list push-action)))\n"
        (if duplicate?
            (string-append
             "(define duplicate-family\n"
             "  (make-ksawery-command-family\n"
             "   odra-ksawery-contributor 7 12 'family.refs \"Duplicate\" 18\n"
             "   '(refs) '() (list push-action)))\n"
             "(define odra-ksawery-command-families\n"
             "  (list family duplicate-family))\n")
            "(define odra-ksawery-command-families (list family))\n"))
       output))
    #:exists 'truncate/replace))

(define (catalog-extension-entry batch)
  (define count (word batch 32))
  (define text-start (+ 64 (* 128 count)))
  (for/first ([index (in-range count)]
              #:when (= (word batch (+ 64 (* index 128))) 4))
    (define record (+ 64 (* index 128)))
    (define (text field)
      (define offset (word batch (+ record field)))
      (define length (word batch (+ record field 8)))
      (bytes->string/utf-8
       (subbytes batch (+ text-start offset) (+ text-start offset length))))
    (list (text 48) (text 80) (text 96) (text 112))))

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

(define (catalog-dispatches batch)
  (for/list ([index (in-range (word batch 32))])
    (word batch (+ 64 (* index 128)))))

(test-case "personal command families enter the active shared catalog atomically"
  (define temporary
    (make-temporary-file "odra-ksawery-command-provider-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define root (build-path temporary "config" "odra"))
     (write-command-provider root 5)
     (define observation (personal-config-load (personal-config-source root)))
     (check-equal? (odra-personal-config-observation-state observation)
                   'confirmed
                   (format "observation: ~a" observation))
     (check-equal?
      (length
       (personal-config-observation-export
        observation 'odra-ksawery-command-families '()))
      1)
     (define startup
       (runtime-personal-configuration-startup-batch (path->bytes root)))
     (check-true (car startup) (bytes->string/utf-8 (caddr startup)))
     (define generation (word (cadr startup) 24))
     (define candidate (runtime-command-catalog-batch generation))
     (check-true (car candidate) (bytes->string/utf-8 (cadddr candidate)))
     (check-not-false (member 4 (catalog-dispatches (caddr candidate)))
                      (format "dispatches: ~a" (catalog-dispatches (caddr candidate))))
     (check-equal?
      (catalog-extension-entry (caddr candidate))
      '("personal.repository-tools/family.refs/action.push"
        "personal.repository-tools"
        "modules/repository-tools.rkt"
        "family.refs"))
     (define route (catalog-extension-route (caddr candidate)))
     (check-equal? (runtime-personal-generation-transition 1 generation)
                   '(#t #t #""))
     (define family
       (runtime-ksawery-command-family-batch
        generation (car route) (cadr route)))
     (check-true (car family) (bytes->string/utf-8 (caddr family)))
     (check-equal? (word (cadr family) 0) 1)
     (check-equal? (word (cadr family) 8) (- (bytes-length (cadr family)) 16))
     (check-equal? (word (cadr family) 16) 1)
     (check-equal? (word (cadr family) 48) 11)
     (check-equal? (word (cadr family) 56) 17)

     (define wrong-name
       (runtime-ksawery-command-family-batch
        generation (car route) #"personal.repository-tools/family.refs/action.missing"))
     (check-false (car wrong-name))
     (check-regexp-match #rx"stale" (bytes->string/utf-8 (caddr wrong-name)))

     (write-command-provider root 6)
     (define reload
       (runtime-personal-configuration-reload-batch
        (path->bytes root) generation))
     (check-true (car reload) (bytes->string/utf-8 (caddr reload)))
     (define reload-generation (word (cadr reload) 24))
     (check-equal? (runtime-personal-generation-transition 1 reload-generation)
                   '(#t #t #""))
     (define stale-generation
       (runtime-ksawery-command-family-batch
        generation (car route) (cadr route)))
     (check-false (car stale-generation))
     (check-regexp-match #rx"stale" (bytes->string/utf-8 (caddr stale-generation)))
     (define reloaded-family
       (runtime-ksawery-command-family-batch
        reload-generation (car route) (cadr route)))
     (check-true (car reloaded-family)
                 (bytes->string/utf-8 (caddr reloaded-family)))
     (check-equal? (word (cadr reloaded-family) 32) 6)

     (write-command-provider root 7 #t)
     (define rejected
       (runtime-personal-configuration-reload-batch
        (path->bytes root) reload-generation))
     (check-false (car rejected))
     (check-regexp-match #rx"unique" (bytes->string/utf-8 (caddr rejected)))
     (define retained (runtime-command-catalog-batch reload-generation))
     (check-true (car retained))
     (check-equal?
      (catalog-extension-entry (caddr retained))
      '("personal.repository-tools/family.refs/action.push"
        "personal.repository-tools"
        "modules/repository-tools.rkt"
        "family.refs"))
     (define retained-family
       (runtime-ksawery-command-family-batch
        reload-generation (car route) (cadr route)))
     (check-true (car retained-family)
                 (bytes->string/utf-8 (caddr retained-family)))
     (check-equal? (word (cadr retained-family) 32) 6))
   (lambda () (delete-directory/files temporary))))
