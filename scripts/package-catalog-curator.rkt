#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         "../src/package_catalog/curation-publication.rkt"
         "../src/package_catalog/snapshot-records.rkt"
         "package-catalog-curator-support.rkt"
         "package-catalog-publication-support.rkt")

(define (parse-options arguments)
  (unless (even? (length arguments))
    (raise-user-error 'package-catalog-curator
                      "options must be --name value pairs"))
  (for/hash ([index (in-range 0 (length arguments) 2)])
    (values (list-ref arguments index) (list-ref arguments (add1 index)))))

(define (required options name)
  (hash-ref options name
            (lambda ()
              (raise-user-error 'package-catalog-curator
                                "~a is required" name))))

(define (natural options name)
  (define value (string->number (required options name)))
  (unless (exact-nonnegative-integer? value)
    (raise-user-error 'package-catalog-curator "~a must be an integer" name))
  value)

(define (write-request options request)
  (define-values (metadata message)
    (write-package-catalog-offline-signing-request
     (required options "--output") request))
  (printf "package-catalog-curator: request=~a message=~a digest=~a\n"
          metadata message
          (odra-package-catalog-offline-signing-request-digest request)))

(module+ main
  (define arguments (vector->list (current-command-line-arguments)))
  (when (null? arguments)
    (raise-user-error 'package-catalog-curator "a workflow command is required"))
  (define command (car arguments))
  (define options (parse-options (cdr arguments)))
  (case (string->symbol command)
    [(bootstrap)
     (define target
       (bootstrap-independent-package-catalog
        (required options "--output")))
     (printf "package-catalog-curator: bootstrapped path=~a\n" target)]
    [(prepare-root-rotation)
     (write-request
      options
      (prepare-package-catalog-root-rotation
       (required options "--catalog-id")
       (required options "--current-root-key-id")
       (required options "--new-public-key")
       (natural options "--generation")))]
    [(prepare-publisher-rotation)
     (write-request
      options
      (prepare-package-catalog-publisher-rotation
       (required options "--catalog-id")
       (required options "--current-root-key-id")
       (required options "--authorization-id")
       (required options "--new-public-key")
       (natural options "--effective-from")))]
    [(prepare-snapshot-signing)
     (define repository-path (required options "--repository"))
     (define repository
       (load-package-catalog-publication-repository repository-path))
     (define publication
       (validate-package-catalog-publication-repository repository))
     (write-request
      options
      (prepare-package-catalog-snapshot-signing
       (odra-package-catalog-publication-snapshot publication)
       (required options "--signing-key-id")))]
    [(verify-signature)
     (define request
       (load-package-catalog-offline-signing-request
        (required options "--request")))
     (unless (odra-package-catalog-offline-signing-request? request)
       (raise-user-error 'package-catalog-curator "signing request is invalid"))
     (define result
       (verify-package-catalog-offline-signature
        request (required options "--public-key")
        (required options "--signature")))
     (unless (eq? result #t)
       (raise-user-error 'package-catalog-curator "signature is invalid"))
     (displayln "package-catalog-curator: signature valid")]
    [(verify-snapshot)
     (define result
       (verify-package-catalog-snapshot-file
        (required options "--repository")
        (required options "--snapshot")
        (natural options "--now")))
     (unless (eq? result #t)
       (raise-user-error 'package-catalog-curator "snapshot is invalid"))
     (displayln "package-catalog-curator: snapshot valid")]
    [(validate-mirror)
     (define result
       (validate-package-catalog-exact-mirror
        (required options "--origin") (required options "--mirror")))
     (unless (eq? result #t)
       (raise-user-error 'package-catalog-curator "mirror is not exact"))
     (displayln "package-catalog-curator: mirror exact")]
    [(dry-run)
     (define result
       (dry-run-package-catalog-publication
        (required options "--repository")))
     (printf
      "package-catalog-curator: dry-run catalog=~a sequence=~a snapshot=~a assertions=~a\n"
      (odra-package-catalog-publication-dry-run-catalog-id result)
      (odra-package-catalog-publication-dry-run-sequence result)
      (odra-package-catalog-publication-dry-run-snapshot-id result)
      (odra-package-catalog-publication-dry-run-assertion-count result))]
    [else
     (raise-user-error 'package-catalog-curator
                       "unsupported workflow command: ~a" command)]))
