#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         (only-in "../configuration/platform-roots.rkt"
                  odra-platform-roots-package-data
                  runtime-platform-roots-batch
                  runtime-platform-roots-current)
         "../package/acquisition.rkt"
         "../package/lifecycle-service.rkt"
         "../package_catalog/runtime-service.rkt"
         "personal-configuration-bridge.rkt")

(provide
 (contract-out
  [runtime-package-catalog-command-batch (-> bytes? bytes? list?)]))

(define schema-version 1)
(define request-header-bytes 40)
(define result-header-bytes 56)
(define maximum-copy-bytes (* 256 1024))

(define (word value) (integer->integer-bytes value 8 #f #f))
(define (words . values) (apply bytes-append (map word values)))
(define (read-word input offset)
  (integer-bytes->integer input #f #f offset (+ offset 8)))

(define (decode-request request)
  (unless (>= (bytes-length request) request-header-bytes)
    (raise-arguments-error 'runtime-package-catalog-command-batch
                           "truncated request"))
  (define schema (read-word request 0))
  (define action (read-word request 8))
  (define argument-bytes (read-word request 16))
  (define confirmed (read-word request 24))
  (define reserved (read-word request 32))
  (unless (and (= schema schema-version) (<= 1 action 20)
               (<= argument-bytes 4096) (<= confirmed 1) (= reserved 0)
               (= (+ request-header-bytes argument-bytes)
                  (bytes-length request)))
    (raise-arguments-error 'runtime-package-catalog-command-batch
                           "invalid request header"))
  (values action
          (bytes->string/utf-8
           (subbytes request request-header-bytes) #f)
          (= confirmed 1)))

(define (dispatch catalog-root package-root action argument confirmed?)
  (define configuration (runtime-personal-package-catalog-configuration))
  (case action
    [(1) (package-catalog-runtime-list catalog-root configuration)]
    [(2) (package-catalog-runtime-preview-add catalog-root configuration argument)]
    [(3)
     (unless confirmed?
       (raise-arguments-error 'runtime-package-catalog-command-batch
                              "catalog addition requires confirmation"))
     (package-catalog-runtime-add catalog-root configuration argument)]
    [(4)
     (package-catalog-runtime-set-enabled catalog-root configuration argument #f)]
    [(5)
     (unless confirmed?
       (raise-arguments-error 'runtime-package-catalog-command-batch
                              "catalog removal requires confirmation"))
     (package-catalog-runtime-remove catalog-root configuration argument)]
    [(6)
     (package-catalog-runtime-refresh catalog-root configuration argument)]
    [(7) (package-catalog-runtime-search catalog-root configuration argument)]
    [(8) (package-catalog-runtime-describe catalog-root configuration argument)]
    [(9) (package-catalog-runtime-doctor catalog-root configuration)]
    [(10) (lifecycle-result (package-lifecycle-runtime-list package-root))]
    [(11) (package-catalog-runtime-discover catalog-root configuration argument)]
    [(12) (lifecycle-result
           (package-lifecycle-runtime-describe package-root argument))]
    [(13)
     (lifecycle-result
      (package-lifecycle-runtime-install
       package-root argument
       #:installer
       (lambda (_installation-root package-id version)
         (define prepared
           (package-catalog-runtime-prepare-installation
            catalog-root configuration package-id version
            #:acquisition-root package-root))
         (if (odra-package-installation-acquisition-failure? prepared)
             (odra-package-installation-acquisition-failure-detail prepared)
             prepared))))]
    [(14)
     (require-confirmation confirmed? "package enablement")
     (lifecycle-result (package-lifecycle-runtime-enable package-root argument))]
    [(15)
     (lifecycle-result (package-lifecycle-runtime-disable package-root argument))]
    [(16)
     (require-confirmation confirmed? "package update")
     (lifecycle-result (package-lifecycle-runtime-update package-root argument))]
    [(17)
     (require-confirmation confirmed? "package rollback")
     (lifecycle-result (package-lifecycle-runtime-rollback package-root argument))]
    [(18)
     (require-confirmation confirmed? "package removal")
     (lifecycle-result (package-lifecycle-runtime-remove package-root argument))]
    [(19)
     (require-confirmation confirmed? "package cleanup")
     (lifecycle-result (package-lifecycle-runtime-cleanup package-root))]
    [(20) (lifecycle-result (package-lifecycle-runtime-doctor package-root))]))

(define (require-confirmation confirmed? operation)
  (unless confirmed?
    (raise-arguments-error 'runtime-package-catalog-command-batch
                           (string-append operation " requires confirmation"))))

(define (lifecycle-result result)
  (odra-package-catalog-runtime-result
   (odra-package-lifecycle-runtime-result-status result)
   (odra-package-lifecycle-runtime-result-generation result)
   (odra-package-lifecycle-runtime-result-item-count result)
   (odra-package-lifecycle-runtime-result-identity result)
   (odra-package-lifecycle-runtime-result-detail result)))

(define (package-data-root catalog-root)
  (define roots (runtime-platform-roots-current))
  (if roots (odra-platform-roots-package-data roots) catalog-root))

(define (status-code status)
  (case status [(success) 1] [(confirmation) 2] [(failure) 3] [else 0]))

(define (encode-result action result)
  (define identity
    (string->bytes/utf-8
     (odra-package-catalog-runtime-result-identity result)))
  (define detail
    (string->bytes/utf-8
     (odra-package-catalog-runtime-result-detail result)))
  (define encoded
    (bytes-append
     (words schema-version action
            (status-code
             (odra-package-catalog-runtime-result-status result))
            (odra-package-catalog-runtime-result-generation result)
            (odra-package-catalog-runtime-result-item-count result)
            (bytes-length identity)
            (bytes-length detail))
     identity detail))
  (when (> (bytes-length encoded) maximum-copy-bytes)
    (error 'runtime-package-catalog-command-batch
           "package catalog result exceeds copied storage"))
  encoded)

(define (runtime-package-catalog-command-batch configuration-root-bytes request)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #"" (string->bytes/utf-8 (exn-message failure))))])
    (define root (bytes->string/utf-8 configuration-root-bytes #f))
    (define package-root (package-data-root root))
    (define-values (action argument confirmed?) (decode-request request))
    (list #t (encode-result action
                            (dispatch root package-root action argument confirmed?))
          #"")))

(module+ test
  (require racket/file rackunit)

  (define root (make-temporary-file "odra-package-catalog-bridge-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind
    void
    (lambda ()
      (define environment
        (environment-variables-copy (current-environment-variables)))
      (define data-base (build-path root "data"))
      (environment-variables-set! environment #"HOME" (path->bytes root))
      (environment-variables-set! environment #"XDG_DATA_HOME"
                                  (path->bytes data-base))
      (parameterize ([current-environment-variables environment])
        (check-true (car (runtime-platform-roots-batch))))
      (check-equal? (package-data-root (path->string root))
                    (path->string (build-path data-base "odra")))
      (define request (words schema-version 1 0 0 0))
      (define envelope
        (runtime-package-catalog-command-batch (path->bytes root) request))
      (check-true (car envelope))
      (define result (cadr envelope))
      (check-equal? (bytes-length result)
                    (+ result-header-bytes (read-word result 40)
                       (read-word result 48)))
      (check-equal? (read-word result 0) schema-version)
      (check-equal? (read-word result 8) 1)
      (check-equal? (read-word result 16) 1)
      (for ([action '(10 20)])
        (define package-envelope
          (runtime-package-catalog-command-batch
           (path->bytes root) (words schema-version action 0 0 0)))
        (check-true (car package-envelope))
        (define package-result (cadr package-envelope))
        (check-equal? (read-word package-result 8) action)
        (check-equal? (read-word package-result 16) 1))
      (for ([action '(4 6 13 15)]
            [argument '("missing-catalog" "missing-catalog"
                        "missing.package@1.0.0" "missing.package")])
        (define argument-bytes (string->bytes/utf-8 argument))
        (define direct-envelope
          (runtime-package-catalog-command-batch
           (path->bytes root)
           (bytes-append
            (words schema-version action (bytes-length argument-bytes) 0 0)
            argument-bytes)))
        (check-true (car direct-envelope)))
      (define authority-bytes #"missing.package@1.0.0")
      (define unconfirmed-authority
        (runtime-package-catalog-command-batch
         (path->bytes root)
         (bytes-append
          (words schema-version 14 (bytes-length authority-bytes) 0 0)
          authority-bytes)))
      (check-false (car unconfirmed-authority)))
    (lambda () (delete-directory/files root))))
