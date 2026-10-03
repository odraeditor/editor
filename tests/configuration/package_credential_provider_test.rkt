#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/package/credential-provider.rkt")

(define (provider lookup [refresh lookup])
  (make-package-credential-provider
   #:id "test-provider" #:generation 7
   #:lookup lookup #:refresh refresh))

(test-case "available credentials resolve without exposing header values"
  (define result
    (resolve-package-credential
     (provider
      (lambda (_)
        (make-package-credential
         #:headers (hash "Authorization" "Bearer private-value")
         #:expires-at 200)))
     "catalog.private" #:now 100))
  (check-true (odra-package-credential-resolution? result))
  (check-equal?
   (package-credential-resolution-headers result)
   (hash "authorization" "Bearer private-value"))
  (check-false (regexp-match? #px"private-value" (format "~s" result)))
  (check-false
   (regexp-match?
    #px"private-value"
    (format "~s" (package-credential-resolution->projection result)))))

(test-case "expired lookup refreshes once and records safe provenance"
  (define refreshes 0)
  (define result
    (resolve-package-credential
     (provider
      (lambda (_)
        (make-package-credential
         #:headers (hash "authorization" "Bearer expired")
         #:expires-at 100))
      (lambda (_)
        (set! refreshes (add1 refreshes))
        (make-package-credential
         #:headers (hash "authorization" "Bearer refreshed")
         #:expires-at 300)))
     "catalog.private" #:now 200))
  (check-equal? refreshes 1)
  (check-equal?
   (package-credential-resolution->projection result)
   (odra-package-credential-projection
    "test-provider" 7 "catalog.private" 'available 300 #t)))

(test-case "missing and rejected credentials produce redacted failures"
  (define missing
    (resolve-package-credential (provider (lambda (_) #f)) "catalog.missing"))
  (check-eq? (odra-package-credential-failure-code missing) 'unavailable)
  (check-equal?
   (package-credential-failure->projection missing)
   (odra-package-credential-projection
    "test-provider" 7 "catalog.missing" 'unavailable #f #f))
  (define rejected
    (resolve-package-credential
     (provider (lambda (_) (hash "authorization" "Bearer not-admitted")))
     "catalog.rejected"))
  (check-eq? (odra-package-credential-failure-code rejected) 'rejected)
  (check-false (regexp-match? #px"not-admitted" (format "~s" rejected))))

(test-case "environment provider treats references as variable names"
  (define environment
    (make-environment-package-credential-provider
     #:environment
     (lambda (name)
       (and (string=? name "ODRA_PRIVATE_TOKEN") "Bearer environment"))))
  (define result
    (resolve-package-credential environment "ODRA_PRIVATE_TOKEN"))
  (check-true (odra-package-credential-resolution? result))
  (check-equal?
   (package-credential-resolution-headers result)
   (hash "authorization" "Bearer environment"))
  (check-eq?
   (odra-package-credential-failure-code
    (resolve-package-credential environment "not-an-environment-variable"))
   'unavailable))

(test-case "artifact bindings retain only exact local policy"
  (define binding
    (package-artifact-credential-binding
     #:endpoint-id "kasper-artifacts"
     #:origin "https://packages.example:8443"
     #:credential-reference "ODRA_PRIVATE_TOKEN"
     #:provider-id "environment"
     #:provider-generation 1))
  (check-equal?
   (odra-package-artifact-credential-binding-header-policy binding)
   '("authorization"))
  (check-false (regexp-match? #px"Bearer" (format "~s" binding))))
