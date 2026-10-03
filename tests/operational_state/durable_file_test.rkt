#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/storage/durable-file.rkt"
         (submod "../../src/storage/durable-file.rkt" test-support))

(define payload #"durable payload")

(define (with-private-root action)
  (define root (make-temporary-file "odra-durable-file-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind void (lambda () (action root))
                (lambda () (delete-directory/files root))))

(define (publish root
                 #:validate-stage [validate-stage (lambda (_) #t)]
                 #:recover-visible [recover-visible #f])
  (durable-file-publish
   (build-path root "state.rkt")
   payload
   #:private-directories (list root)
   #:validate-stage validate-stage
   #:recover-visible recover-visible))

(define (staging-files root)
  (filter
   (lambda (path)
     (regexp-match? #px"[.]odra-stage-" (path->string path)))
   (directory-list root #:build? #t)))

  (test-case "durable publication writes private bytes"
  (with-private-root
   (lambda (root)
     (define result
       (publish
        root
        #:validate-stage
        (lambda (stage) (bytes=? (file->bytes stage) payload))))
     (check-true (odra-durable-file-publication? result))
     (check-eq? (odra-durable-file-publication-publication result)
                'published-durable)
     (check-equal? (file->bytes (build-path root "state.rkt")) payload)
     (check-equal?
      (bitwise-and
       (hash-ref (file-or-directory-stat (build-path root "state.rkt") #f) 'mode)
       #o777)
      #o600))))

  (test-case "prepublish faults clean their stage"
  (for ([scenario
         (in-list
          (list
           (cons
            'create-failed
            (lambda (root)
              (parameterize
                  ([current-durable-file-open
                    (lambda (_) (error 'open "simulated create failure"))])
                (publish root))))
           (cons
            'write-failed
            (lambda (root)
              (parameterize ([current-durable-file-write (lambda (_bytes _output) 0)])
                (publish root))))
           (cons
            'write-failed
            (lambda (root)
              (parameterize
                  ([current-durable-file-flush
                    (lambda (_) (error 'flush "simulated flush failure"))])
                (publish root))))
           (cons
            'file-sync-failed
            (lambda (root)
              (parameterize ([current-durable-file-sync (lambda (_) 5)])
                (publish root))))
           (cons
            'validation-failed
            (lambda (root) (publish root #:validate-stage (lambda (_) #f))))
           (cons
            'rename-failed
            (lambda (root)
              (parameterize
                  ([current-durable-file-rename (lambda (_source _target) 5)])
                (publish root))))))])
    (with-private-root
     (lambda (root)
       (define result ((cdr scenario) root))
       (check-true (odra-durable-file-failure? result))
       (check-eq? (odra-durable-file-failure-code result) (car scenario))
       (check-eq? (odra-durable-file-failure-publication result) 'not-published)
       (check-equal? (staging-files root) '())))))

  (test-case "cleanup fault preserves recovery stage"
  (with-private-root
   (lambda (root)
     (define result
       (parameterize
           ([current-durable-file-write (lambda (_bytes _output) 0)]
            [current-durable-file-delete
             (lambda (_) (error 'delete "simulated cleanup failure"))])
         (publish root)))
     (check-true (odra-durable-file-failure? result))
     (check-eq? (odra-durable-file-failure-code result) 'cleanup-failed)
     (check-not-equal? (odra-durable-file-failure-recovery-path result) "")
     (check-true
      (file-exists? (odra-durable-file-failure-recovery-path result))))))

  (test-case "post-rename distinguishes durability states"
  (with-private-root
   (lambda (root)
     (define recovered
       (parameterize
           ([current-durable-file-rename
             (lambda (source target)
               (rename-file-or-directory source target #t)
               5)])
         (publish
          root
          #:recover-visible
          (lambda (target) (bytes=? (file->bytes target) payload)))))
     (check-true (odra-durable-file-publication? recovered))
     (check-eq? (odra-durable-file-publication-publication recovered)
                'published-recovered)

     (define uncertain
       (parameterize ([current-durable-directory-sync (lambda (_) 5)])
         (durable-file-publish
          (build-path root "other.rkt") payload
          #:private-directories (list root))))
     (check-true (odra-durable-file-publication? uncertain))
     (check-eq? (odra-durable-file-publication-publication uncertain)
                'published-durability-uncertain)
     (check-false (odra-durable-file-publication-directory-synced? uncertain)))))

  (test-case "unsafe targets reject before staging"
  (with-private-root
   (lambda (root)
     (file-or-directory-permissions root #o755)
     (define unsafe-root (publish root))
     (check-true (odra-durable-file-failure? unsafe-root))
     (check-eq? (odra-durable-file-failure-code unsafe-root) 'unsafe-permissions)
     (file-or-directory-permissions root #o700)

     (define target (build-path root "state.rkt"))
     (call-with-output-file target
       (lambda (output) (write-bytes #"old" output))
       #:exists 'truncate/replace
       #:mode 'binary
       #:permissions #o600)
     (file-or-directory-permissions target #o644)
     (define unsafe-target (publish root))
     (check-true (odra-durable-file-failure? unsafe-target))
     (check-eq? (odra-durable-file-failure-code unsafe-target)
                'unsafe-permissions))))
