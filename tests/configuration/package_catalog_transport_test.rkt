#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/package_catalog/contracts.rkt"
         "../../src/package_catalog/endpoint-transport.rkt"
         "../../src/package_catalog/state-records.rkt"
         (submod "../../src/package_catalog/endpoint-transport.rkt" test-support))

(define catalog-id (make-string 64 #\a))
(define policy
  (odra-package-catalog-transport-policy 1024 1000 2 1 'direct))

(define (state-endpoint id uri transport role [credential #f])
  (odra-package-catalog-state-endpoint
   1 1
   (odra-package-catalog-endpoint
    id catalog-id uri transport role 0 #t)
   credential))

(define (no-credentials _reference) #f)

(test-case "local endpoint reads bounded immutable bytes"
  (define path (make-temporary-file "odra-catalog-local-~a.rktd"))
  (dynamic-wind
    (lambda () (display-to-file "catalog" path #:exists 'truncate))
    (lambda ()
      (define endpoint
        (state-endpoint
         "local" (string-append "file://" (path->string path)) 'file 'local))
      (define result
        (fetch-package-catalog-endpoint endpoint policy no-credentials))
      (check-true (odra-package-catalog-fetch-result? result))
      (check-equal? (odra-package-catalog-fetch-result-bytes result) #"catalog")
      (check-true (immutable? (odra-package-catalog-fetch-result-bytes result))))
    (lambda () (delete-file path))))

(test-case "local endpoint byte overflow is rejected without exposing its path"
  (define path (make-temporary-file "odra-catalog-limit-~a.rktd"))
  (dynamic-wind
    (lambda () (display-to-file (make-string 20 #\x) path #:exists 'truncate))
    (lambda ()
      (define endpoint
        (state-endpoint
         "local" (string-append "file://" (path->string path)) 'file 'local))
      (define result
        (fetch-package-catalog-endpoint
         endpoint
         (odra-package-catalog-transport-policy 10 1000 0 0 'direct)
         no-credentials))
      (check-eq? (odra-package-catalog-fetch-failure-code result) 'limit)
      (check-false
       (regexp-match? (regexp (regexp-quote (path->string path)))
                      (odra-package-catalog-fetch-failure-detail result))))
    (lambda () (delete-file path))))

(test-case "HTTPS retry and same-authority redirect remain bounded"
  (define calls 0)
  (define endpoint
    (state-endpoint
     "origin" "https://catalog.example/snapshot" 'https 'origin))
  (define result
    (parameterize
        ([current-catalog-transport-open
          (lambda (_uri _headers proxy-policy)
            (check-eq? proxy-policy 'direct)
            (set! calls (add1 calls))
            (case calls
              [(1) (transport-response 503 (hash) (open-input-bytes #""))]
              [(2)
               (transport-response
                302 (hash "location" "https://catalog.example/current")
                (open-input-bytes #""))]
              [else
               (transport-response 200 (hash)
                                   (open-input-bytes #"snapshot"))]))])
      (fetch-package-catalog-endpoint endpoint policy no-credentials)))
  (check-equal? calls 3)
  (check-equal? (odra-package-catalog-fetch-result-bytes result) #"snapshot")
  (check-true (odra-package-catalog-fetch-result-redirected? result)))

(test-case "credential references resolve locally and never enter results"
  (define endpoint
    (state-endpoint
     "private" "https://catalog.example/private" 'https 'origin
     "credential.catalog.private"))
  (define result
    (parameterize
        ([current-catalog-transport-open
          (lambda (_uri headers _proxy)
            (check-equal? (hash-ref headers "authorization") "Bearer secret")
            (transport-response 200 (hash) (open-input-bytes #"private")))])
      (fetch-package-catalog-endpoint
       endpoint policy
       (lambda (reference)
         (check-equal? reference "credential.catalog.private")
         (hash "Authorization" "Bearer secret")))))
  (check-true (odra-package-catalog-fetch-result-credential-used? result))
  (check-false (regexp-match? #px"secret" (format "~s" result))))

(test-case "credentialed redirect cannot change HTTPS authority"
  (define endpoint
    (state-endpoint
     "private" "https://catalog.example/private" 'https 'origin
     "credential.catalog.private"))
  (define result
    (parameterize
        ([current-catalog-transport-open
          (lambda (_uri _headers _proxy)
            (transport-response
             302 (hash "location" "https://other.example/private")
             (open-input-bytes #"")))])
      (fetch-package-catalog-endpoint
       endpoint policy (lambda (_) (hash "authorization" "Bearer secret")))))
  (check-eq? (odra-package-catalog-fetch-failure-code result) 'redirect))

(test-case "cancellation occurs before endpoint I/O"
  (define opened? #f)
  (define endpoint
    (state-endpoint
     "origin" "https://catalog.example/snapshot" 'https 'origin))
  (define result
    (parameterize
        ([current-catalog-transport-open
          (lambda (_uri _headers _proxy)
            (set! opened? #t)
            (transport-response 200 (hash) (open-input-bytes #"snapshot")))])
      (fetch-package-catalog-endpoint
       endpoint policy no-credentials #:cancelled? (lambda () #t))))
  (check-eq? (odra-package-catalog-fetch-failure-code result) 'cancelled)
  (check-false opened?))

(test-case "deadline interrupts a blocked HTTPS transport owner"
  (define endpoint
    (state-endpoint
     "origin" "https://catalog.example/snapshot" 'https 'origin))
  (define started (current-inexact-monotonic-milliseconds))
  (define result
    (parameterize
        ([current-catalog-transport-open
          (lambda (_uri _headers _proxy)
            (sync never-evt))])
      (fetch-package-catalog-endpoint
       endpoint
       (odra-package-catalog-transport-policy 1024 20 0 0 'direct)
       no-credentials)))
  (check-eq? (odra-package-catalog-fetch-failure-code result) 'deadline)
  (check-true
   (< (- (current-inexact-monotonic-milliseconds) started) 500)))

(test-case "cancellation interrupts active HTTPS endpoint opening"
  (define endpoint
    (state-endpoint
     "origin" "https://catalog.example/snapshot" 'https 'origin))
  (define cancelled? #f)
  (define trigger
    (thread
     (lambda ()
       (sleep 0.02)
       (set! cancelled? #t))))
  (define result
    (parameterize
        ([current-catalog-transport-open
          (lambda (_uri _headers _proxy)
            (sync never-evt))])
      (fetch-package-catalog-endpoint
       endpoint policy no-credentials #:cancelled? (lambda () cancelled?))))
  (thread-wait trigger)
  (check-eq? (odra-package-catalog-fetch-failure-code result) 'cancelled))

(test-case "system proxy policy reaches the HTTPS transport unchanged"
  (define endpoint
    (state-endpoint
     "origin" "https://catalog.example/snapshot" 'https 'origin))
  (define result
    (parameterize
        ([current-catalog-transport-open
          (lambda (_uri _headers proxy-policy)
            (check-eq? proxy-policy 'system)
            (transport-response 200 (hash) (open-input-bytes #"snapshot")))])
      (fetch-package-catalog-endpoint
       endpoint
       (odra-package-catalog-transport-policy 1024 1000 0 0 'system)
       no-credentials)))
  (check-true (odra-package-catalog-fetch-result? result)))
