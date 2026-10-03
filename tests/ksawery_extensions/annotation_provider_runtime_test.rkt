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

(define (words . values)
  (apply bytes-append
         (map (lambda (value) (integer->integer-bytes value 8 #f #f)) values)))

(define (annotation-observation repository target generation)
  (define repository-bytes (string->bytes/utf-8 repository))
  (define record-bytes 104)
  (define repository-offset record-bytes)
  (define target-offset (+ repository-offset (bytes-length repository-bytes)))
  (define total (+ target-offset (bytes-length target)))
  (bytes-append
   (words 1 total 1 2 generation
          repository-offset (bytes-length repository-bytes) 0)
   (words 5 generation target-offset (bytes-length target) 0)
   repository-bytes target))

(define (write-annotation-provider root [contributor-generation 5]
                                   [fail? #f] [empty? #f])
  (make-directory* root)
  (call-with-output-file (build-path root "init.rkt")
    (lambda (output)
      (display
       (string-append
        "#lang racket/base\n"
        "(require odra/commands)\n"
        "(provide odra-ksawery-contributor)\n"
        (cond
          [fail?
            (string-append
             "(define (annotation-provider _observation)\n"
             "  (error 'annotation-provider \"projection failed\"))\n")]
          [empty?
           "(define (annotation-provider _observation) '())\n"]
          [else
           (string-append
             "(define (annotation-provider observation)\n"
             "  (define target (car (hash-ref observation 'targets)))\n"
             "  (list (make-ksawery-annotation\n"
             "         7 1 'annotation.protected target\n"
             "         #:label \"Protected\"\n"
             "         #:detail \"Requires review\"\n"
             "         #:severity 'warning\n"
             "         #:style 'alert\n"
             "         #:command\n"
             "         (make-ksawery-annotation-command-reference\n"
             "          'command.open-history))))\n")])
        "(define odra-ksawery-contributor\n"
        "  (make-ksawery-contributor\n"
        "   'personal.repository-tools \"Repository tools\"\n"
        "   \"modules/repository-tools.rkt\" "
        (number->string contributor-generation) "\n"
        "   (list\n"
        "    (make-ksawery-contribution\n"
        "     7 'annotations.repository-policy 'annotation\n"
        "     #:observations '(refs)\n"
        "     #:authorities '(inspect present))\n"
        "    (make-ksawery-contribution\n"
        "     9 'command.open-history 'command\n"
        "     #:observations '(refs)\n"
        "     #:authorities '(inspect invoke-declared-command)))\n"
        "   #:annotation-provider annotation-provider))\n")
       output))
    #:exists 'truncate/replace))

(test-case "active contributor projects, reloads, and contains annotation failure"
  (define temporary
    (make-temporary-file "odra-ksawery-annotation-provider-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define root (build-path temporary "config" "odra"))
     (write-annotation-provider root)
     (define startup
       (runtime-personal-configuration-startup-batch (path->bytes root)))
     (check-true (car startup))
     (define startup-batch (cadr startup))
     (define diagnostic
       (bytes->string/utf-8
        (subbytes startup-batch 352 (+ 352 (word startup-batch 40)))))
     (check-equal? (word startup-batch 8) 1 diagnostic)
     (define generation (word startup-batch 24))
     (check-equal? (runtime-personal-generation-transition 1 generation)
                   '(#t #t #""))
     (define observation
       (annotation-observation "/tmp/odra-ksawery-extension"
                               #"refs/heads/main" 19))
     (define projection
       (runtime-ksawery-annotation-projection-batch observation))
     (check-true (car projection) (bytes->string/utf-8 (caddr projection)))
     (check-equal? (caddr projection) #"")
     (define encoded (cadr projection))
     (check-equal? (word encoded 0) 1)
     (check-equal? (word encoded 16) 1)
     (check-equal? (word encoded 24) 5)
     (check-equal? (word encoded 32) 19)
     (check-equal? (word encoded 40) 2)
     (check-equal? (word encoded 48) 19)
     (check-equal? (word encoded 128) 7)
     (check-equal? (word encoded 136) 5)

     (write-annotation-provider root 6)
     (define reload
       (runtime-personal-configuration-reload-batch
        (path->bytes root) generation))
     (check-true (car reload))
     (define reload-generation (word (cadr reload) 24))
     (check-equal? (runtime-personal-generation-transition 1 reload-generation)
                   '(#t #t #""))
     (define reloaded
       (runtime-ksawery-annotation-projection-batch observation))
     (check-true (car reloaded) (bytes->string/utf-8 (caddr reloaded)))
     (check-equal? (word (cadr reloaded) 24) 6)

     (write-annotation-provider root 7 #f #t)
     (define empty-reload
       (runtime-personal-configuration-reload-batch
        (path->bytes root) reload-generation))
     (check-true (car empty-reload))
     (define empty-generation (word (cadr empty-reload) 24))
     (check-equal? (runtime-personal-generation-transition 1 empty-generation)
                   '(#t #t #""))
     (define empty
       (runtime-ksawery-annotation-projection-batch observation))
     (check-true (car empty))
     (check-equal? (cadr empty) #"")
     (check-equal? (caddr empty) #"")

     (write-annotation-provider root 8 #t)
     (define failing-reload
       (runtime-personal-configuration-reload-batch
        (path->bytes root) empty-generation))
     (check-true (car failing-reload))
     (define failing-generation (word (cadr failing-reload) 24))
     (check-equal? (runtime-personal-generation-transition 1 failing-generation)
                   '(#t #t #""))
     (define failed
       (runtime-ksawery-annotation-projection-batch observation))
     (check-false (car failed))
     (check-equal? (cadr failed) #"")
     (check-regexp-match #rx"projection failed"
                         (bytes->string/utf-8 (caddr failed))))
   (lambda () (delete-directory/files temporary))))
