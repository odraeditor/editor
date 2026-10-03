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

(define (conflict-observation repository path)
  (define repository-bytes (string->bytes/utf-8 repository))
  (define path-bytes (string->bytes/utf-8 path))
  (define fixed-bytes (+ 160 (* 4 64)))
  (define path-offset (bytes-length repository-bytes))
  (define payload (bytes-append repository-bytes path-bytes))
  (bytes-append
   (words 1 (+ fixed-bytes (bytes-length payload))
          17 19 23 29 31 37 1 #b10 4 (bytes-length payload)
          0 (bytes-length repository-bytes) path-offset (bytes-length path-bytes)
          0 0 0 0)
   (apply bytes-append
          (for/list ([kind (in-range 1 5)])
            (words kind 1 0 0 0 0 0 0)))
   payload))

(define (write-conflict-provider root [generation 5] [failing? #f])
  (make-directory* root)
  (call-with-output-file (build-path root "init.rkt")
    (lambda (output)
      (display
       (format
        (string-append
        "#lang racket/base\n"
        "(require odra/commands)\n"
        "(provide odra-ksawery-contributor)\n"
        "(define (conflict-provider contributor request observation)\n"
        "  (define provider\n"
        "    (make-ksawery-conflict-provider\n"
        "     contributor 7 11 13 'conflict.helper \"Conflict helper\"\n"
        "     '(text) '(present-guidance) #:lifecycle 'active))\n"
        "  ~a)\n"
        "(define odra-ksawery-contributor\n"
        "  (make-ksawery-contributor\n"
        "   'personal.conflict-tools \"Conflict tools\"\n"
        "   \"modules/conflict-tools.rkt\" ~a\n"
        "   (list (make-ksawery-contribution\n"
        "          7 'conflict.helper 'provider-role\n"
        "          #:provider-role 'conflict-assistance\n"
        "          #:observations '(status sequence conflict process)\n"
        "          #:authorities '(inspect present assist-conflict)))\n"
        "   #:conflict-assistance-provider conflict-provider))\n")
        (if failing?
            "(error 'conflict-provider \"provider failed\")"
            (string-append
             "(make-ksawery-conflict-guidance request provider "
             "(string-append \"Inspect \" "
             "(ksawery-conflict-target-path "
             "(ksawery-conflict-observation-target observation))))"))
        generation)
       output))
    #:exists 'truncate/replace))

(test-case "active personal contributor returns one attributable guidance response"
  (define temporary
    (make-temporary-file "odra-ksawery-conflict-provider-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define root (build-path temporary "config" "odra"))
     (write-conflict-provider root)
     (define startup
       (runtime-personal-configuration-startup-batch (path->bytes root)))
     (check-true (car startup))
     (define generation (word (cadr startup) 24))
     (check-equal? (runtime-personal-generation-transition 1 generation)
                   '(#t #t #""))
     (define evaluated
       (runtime-ksawery-conflict-assistance-batch
        41 (conflict-observation "/tmp/repository" "src/main.odin")))
     (check-true (car evaluated) (bytes->string/utf-8 (caddr evaluated)))
     (define batch (cadr evaluated))
     (define provider-bytes (word batch 0))
     (define response-bytes (word batch 8))
     (check-equal? (+ 16 provider-bytes response-bytes) (bytes-length batch))
     (check-equal? (word batch (+ 16 (* 5 8))) 11)
     (define response-offset (+ 16 provider-bytes))
     (check-equal? (word batch (+ response-offset (* 2 8))) 41)
     (check-equal? (word batch (+ response-offset (* 5 8))) 2)
     (define guidance-offset (word batch (+ response-offset (* 7 8))))
     (define guidance-bytes (word batch (+ response-offset (* 8 8))))
     (define payload-offset (+ response-offset 128))
     (check-equal?
      (bytes->string/utf-8
       (subbytes batch (+ payload-offset guidance-offset)
                 (+ payload-offset guidance-offset guidance-bytes)))
      "Inspect src/main.odin")

     (write-conflict-provider root 6)
     (define reload
       (runtime-personal-configuration-reload-batch
        (path->bytes root) generation))
     (check-true (car reload))
     (define reload-generation (word (cadr reload) 24))
     (check-equal? (runtime-personal-generation-transition 1 reload-generation)
                   '(#t #t #""))
     (define reloaded
       (runtime-ksawery-conflict-assistance-batch
        43 (conflict-observation "/tmp/repository" "src/main.odin")))
     (check-true (car reloaded) (bytes->string/utf-8 (caddr reloaded)))
     (check-equal? (word (cadr reloaded) (+ 16 (* 3 8))) 6)

     (write-conflict-provider root 7 #t)
     (define failing-reload
       (runtime-personal-configuration-reload-batch
        (path->bytes root) reload-generation))
     (check-true (car failing-reload))
     (define failing-generation (word (cadr failing-reload) 24))
     (check-equal? (runtime-personal-generation-transition 1 failing-generation)
                   '(#t #t #""))
     (define failed
       (runtime-ksawery-conflict-assistance-batch
        47 (conflict-observation "/tmp/repository" "src/main.odin")))
     (check-false (car failed))
     (check-equal? (cadr failed) #"")
     (check-regexp-match #rx"provider failed"
                         (bytes->string/utf-8 (caddr failed))))
   (lambda () (delete-directory/files temporary))))
