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

(define (status-observation repository branch path generation)
  (define repository-bytes (string->bytes/utf-8 repository))
  (define branch-bytes (string->bytes/utf-8 branch))
  (define path-bytes (string->bytes/utf-8 path))
  (define text-start 96)
  (define repository-offset text-start)
  (define branch-offset (+ repository-offset (bytes-length repository-bytes)))
  (define path-offset (+ branch-offset (bytes-length branch-bytes)))
  (define total (+ path-offset (bytes-length path-bytes)))
  (bytes-append
   (words 1 total 1 generation
          repository-offset (bytes-length repository-bytes)
          branch-offset (bytes-length branch-bytes))
   (words 1 4 path-offset (bytes-length path-bytes))
   repository-bytes branch-bytes path-bytes))

(define (write-status-provider root [contributor-generation 5] [fail? #f])
  (make-directory* root)
  (call-with-output-file (build-path root "init.rkt")
    (lambda (output)
      (display
       (string-append
        "#lang racket/base\n"
        "(require odra/commands)\n"
        "(provide odra-ksawery-contributor)\n"
        (if fail?
            (string-append
             "(define (status-provider _observation)\n"
             "  (error 'status-provider \"projection failed\"))\n")
            (string-append
             "(define (status-provider observation)\n"
             "  (define item\n"
             "    (make-ksawery-status-item\n"
             "     1 'branch.current (hash-ref observation 'branch)\n"
             "     #:style 'identity\n"
             "     #:metadata\n"
             "     (list (make-ksawery-status-metadata\n"
             "            'change.count\n"
             "            (number->string\n"
             "             (length (hash-ref observation 'changes)))))))\n"
             "  (list (make-ksawery-status-section\n"
             "         7 'status.ahead-behind \"Repository insight\"\n"
             "         (list item))))\n"))
        "(define odra-ksawery-contributor\n"
        "  (make-ksawery-contributor\n"
        "   'personal.repository-tools \"Repository tools\"\n"
        "   \"modules/repository-tools.rkt\" "
        (number->string contributor-generation) "\n"
        "   (list (make-ksawery-contribution\n"
        "          7 'status.ahead-behind 'status-section\n"
        "          #:observations '(status)\n"
        "          #:authorities '(inspect present)))\n"
        "   #:status-provider status-provider))\n")
       output))
    #:exists 'truncate/replace))

(test-case "active personal contributor projects one copied Status observation"
  (define temporary
    (make-temporary-file "odra-ksawery-status-provider-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define root (build-path temporary "config" "odra"))
     (write-status-provider root)
     (define startup
       (runtime-personal-configuration-startup-batch (path->bytes root)))
     (check-true (car startup))
     (define startup-batch (cadr startup))
     (define diagnostic
       (bytes->string/utf-8
        (subbytes startup-batch 352 (+ 352 (word startup-batch 40)))))
     (check-equal? (word startup-batch 8) 1 diagnostic)
     (check-equal? (word startup-batch 16) 2 diagnostic)
     (define generation (word startup-batch 24))
     (check-equal? (runtime-personal-generation-transition 1 generation)
                   '(#t #t #""))
     (define projection
       (runtime-ksawery-status-projection-batch
        (status-observation "/tmp/odra-ksawery-extension" "main"
                            "src/main.odin" 19)))
     (check-true (car projection) (bytes->string/utf-8 (caddr projection)))
     (check-equal? (caddr projection) #"")
     (define encoded (cadr projection))
     (check-equal? (word encoded 0) 1)
     (check-equal? (word encoded 16) 1)
     (check-equal? (word encoded 48) 5)
     (check-equal? (word encoded 64) 19)
     (define item-offset (+ 104 96))
     (define text-offset (word encoded (+ item-offset 32)))
     (define text-length (word encoded (+ item-offset 40)))
     (check-equal?
      (bytes->string/utf-8
       (subbytes encoded text-offset (+ text-offset text-length)))
      "main")

     (write-status-provider root 6)
     (define reload
       (runtime-personal-configuration-reload-batch
        (path->bytes root) generation))
     (check-true (car reload))
     (define reload-batch (cadr reload))
     (check-equal? (word reload-batch 8) 1)
     (define reload-generation (word reload-batch 24))
     (check-equal? (runtime-personal-generation-transition 1 reload-generation)
                   '(#t #t #""))
     (define reloaded-projection
       (runtime-ksawery-status-projection-batch
        (status-observation "/tmp/odra-ksawery-extension" "next"
                            "src/main.odin" 20)))
     (check-true (car reloaded-projection)
                 (bytes->string/utf-8 (caddr reloaded-projection)))
     (check-equal? (word (cadr reloaded-projection) 48) 6)

     (write-status-provider root 7 #t)
     (define failing-reload
       (runtime-personal-configuration-reload-batch
        (path->bytes root) reload-generation))
     (check-true (car failing-reload))
     (define failing-generation (word (cadr failing-reload) 24))
     (check-equal? (runtime-personal-generation-transition 1 failing-generation)
                   '(#t #t #""))
     (define failed-projection
       (runtime-ksawery-status-projection-batch
        (status-observation "/tmp/odra-ksawery-extension" "failed"
                            "src/main.odin" 21)))
     (check-false (car failed-projection))
     (check-equal? (cadr failed-projection) #"")
     (check-regexp-match #rx"projection failed"
                         (bytes->string/utf-8 (caddr failed-projection))))
   (lambda () (delete-directory/files temporary))))
