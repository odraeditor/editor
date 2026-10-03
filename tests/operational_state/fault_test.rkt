#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/project/persistence.rkt"
         "../../src/project/records.rkt"
         "../../src/storage/record-store.rkt"
         (submod "../../src/storage/durable-file.rkt" test-support)
         "../../src/workspace/persistence.rkt"
         "../../src/workspace/records.rkt")

(define (with-root action)
  (define root (make-temporary-file "odra-record-fault-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind void (lambda () (action root))
                (lambda () (delete-directory/files root))))

(define (project-record root id [generation 1])
  (local-project-record
   #:format-version current-local-project-format-version
   #:id id
   #:generation generation
   #:name id
   #:root (path->string root)
   #:trust 'untrusted))

(define (stage-files root)
  (if (directory-exists? root)
      (filter (lambda (path)
                (regexp-match? #px"[.]odra-stage-" (path->string path)))
              (directory-list root #:build? #t))
      '()))

(test-case "prepublication faults remove private stages"
  (for ([fault
         (in-list
          (list
           (cons 'write-failed
                 (lambda (root record)
                   (parameterize
                       ([current-durable-file-write
                         (lambda (bytes output)
                           (write-bytes (subbytes bytes 0 (quotient (bytes-length bytes) 2))
                                        output)
                           (error 'partial-write "simulated interruption"))])
                     (local-project-record-persist root record))))
           (cons 'file-sync-failed
                 (lambda (root record)
                   (parameterize ([current-durable-file-sync (lambda (_) 5)])
                     (local-project-record-persist root record))))
           (cons 'validation-failed
                 (lambda (root record)
                   (parameterize
                       ([current-durable-file-write
                         (lambda (bytes output)
                           (define invalid (bytes-copy bytes))
                           (bytes-set! invalid 0 (char->integer #\!))
                           (write-bytes invalid output))])
                     (local-project-record-persist root record))))
           (cons 'rename-failed
                 (lambda (root record)
                   (parameterize ([current-durable-file-rename
                                   (lambda (_source _target) 5)])
                     (local-project-record-persist root record))))))])
    (with-root
     (lambda (root)
       (define project-root (build-path root "project"))
       (make-directory project-root)
       (define result ((cdr fault) project-root (project-record project-root "faulted")))
       (check-true (odra-record-publication-failure? result))
       (check-eq? (odra-record-publication-failure-code result) (car fault))
       (check-eq? (odra-record-publication-failure-publication result)
                  'not-published)
       (check-false (file-exists? (local-project-record-path project-root)))
       (check-equal? (stage-files (build-path project-root ".odra")) '())))))

  (test-case "dir sync reports uncertain publication"
  (with-root
   (lambda (root)
     (define project-root (build-path root "project"))
     (make-directory project-root)
     (define result
       (parameterize ([current-durable-directory-sync (lambda (_) 5)])
         (local-project-record-persist
          project-root
          (project-record project-root "uncertain"))))
     (check-true (odra-record-publication-failure? result))
     (check-eq? (odra-record-publication-failure-code result)
                'directory-sync-failed)
     (check-eq? (odra-record-publication-failure-publication result)
                'published-durability-uncertain)
     (check-true (file-exists? (local-project-record-path project-root))))))

  (test-case "unsafe metadata permissions block writes"
  (with-root
   (lambda (root)
     (define project-root (build-path root "project"))
     (define metadata-root (build-path project-root ".odra"))
     (make-directory* metadata-root)
     (file-or-directory-permissions metadata-root #o755)
     (define result
       (local-project-record-persist project-root (project-record project-root "unsafe")))
     (check-true (odra-record-publication-failure? result))
     (check-eq? (odra-record-publication-failure-code result) 'unsafe-permissions)
     (check-false (file-exists? (local-project-record-path project-root))))))

  (test-case "catalogs reject duplicate roots and names"
  (with-root
   (lambda (root)
     (define configuration-root (build-path root "config" "odra"))
     (define shared-root (path->string (build-path root "shared")))
     (for ([id (in-list '("first" "second"))])
       (check-true
        (odra-record-publication?
         (project-discovery-record-persist
          configuration-root
          (project-discovery-record
           #:format-version current-project-discovery-format-version
           #:id id
           #:expected-project-generation 1
           #:root shared-root)))))
     (define project-catalog (project-discovery-catalog-load configuration-root))
     (check-equal? (odra-record-catalog-records project-catalog) '())
     (check-equal?
      (map odra-record-catalog-rejection-code
           (odra-record-catalog-rejections project-catalog))
      '(duplicate-root duplicate-root))

     (define projects
       (list
        (workspace-project-reference
         #:id "first" #:expected-project-generation 1 #:root "/first")
        (workspace-project-reference
         #:id "second" #:expected-project-generation 1 #:root "/second")))
     (for ([id (in-list '("alpha" "beta"))])
       (check-true
        (odra-record-publication?
         (workspace-record-persist
          configuration-root
          (workspace-record
           #:format-version current-workspace-format-version
           #:id id
           #:generation 1
           #:name "Shared"
           #:projects projects)))))
     (define workspace-catalog (workspace-catalog-load configuration-root))
     (check-equal? (odra-record-catalog-records workspace-catalog) '())
     (check-equal?
      (map odra-record-catalog-rejection-code
           (odra-record-catalog-rejections workspace-catalog))
      '(duplicate-name duplicate-name)))))
