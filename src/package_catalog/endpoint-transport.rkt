#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require net/url
         racket/contract/base
         racket/list
         racket/match
         racket/port
         racket/string
         "contracts.rkt"
         "state-records.rkt")

(provide
 (struct-out odra-package-catalog-transport-policy)
 (struct-out odra-package-catalog-fetch-result)
 (struct-out odra-package-catalog-fetch-failure)
 (contract-out
  [fetch-package-catalog-endpoint
   (->* (odra-package-catalog-state-endpoint?
         odra-package-catalog-transport-policy?
         procedure?)
        (#:cancelled? procedure?)
        (or/c odra-package-catalog-fetch-result?
              odra-package-catalog-fetch-failure?))]))

(define maximum-diagnostic-bytes 4096)
(define maximum-transport-bytes (* 4 1024 1024))
(define maximum-deadline-milliseconds (* 10 60 1000))
(define maximum-redirects 8)
(define maximum-retries 8)
(define transfer-buffer-bytes (* 64 1024))
(define redirect-statuses '(301 302 307 308))
(define retry-statuses '(408 429 500 502 503 504))

(define (bounded-positive? value maximum)
  (and (exact-positive-integer? value) (<= value maximum)))

(struct odra-package-catalog-transport-policy
  (maximum-bytes deadline-milliseconds redirect-limit retry-limit proxy-policy)
  #:transparent
  #:guard
  (lambda (maximum-bytes deadline-milliseconds redirect-limit retry-limit
                         proxy-policy _)
    (unless (and (bounded-positive? maximum-bytes maximum-transport-bytes)
                 (bounded-positive? deadline-milliseconds
                                    maximum-deadline-milliseconds)
                 (exact-nonnegative-integer? redirect-limit)
                 (<= redirect-limit maximum-redirects)
                 (exact-nonnegative-integer? retry-limit)
                 (<= retry-limit maximum-retries)
                 (memq proxy-policy '(direct system)))
      (raise-arguments-error 'odra-package-catalog-transport-policy
                             "invalid bounded endpoint transport policy"))
    (values maximum-bytes deadline-milliseconds redirect-limit retry-limit
            proxy-policy)))

(struct odra-package-catalog-fetch-result
  (endpoint-id catalog-id bytes observed-bytes attempts redirected?
               credential-used?)
  #:transparent
  #:guard
  (lambda (endpoint-id catalog-id bytes observed-bytes attempts redirected?
                       credential-used? _)
    (unless (and (string? endpoint-id) (string? catalog-id)
                 (bytes? bytes) (immutable? bytes)
                 (= observed-bytes (bytes-length bytes))
                 (exact-positive-integer? attempts)
                 (boolean? redirected?) (boolean? credential-used?))
      (raise-arguments-error 'odra-package-catalog-fetch-result
                             "invalid bounded endpoint fetch result"))
    (values (string->immutable-string endpoint-id)
            (string->immutable-string catalog-id) bytes observed-bytes attempts
            redirected? credential-used?)))

(define failure-codes
  '(cancelled credential deadline http-status io limit redirect transport))

(struct odra-package-catalog-fetch-failure
  (code endpoint-id retryable? detail)
  #:transparent
  #:guard
  (lambda (code endpoint-id retryable? detail _)
    (unless (and (memq code failure-codes) (string? endpoint-id)
                 (boolean? retryable?) (string? detail)
                 (<= (bytes-length (string->bytes/utf-8 detail))
                     maximum-diagnostic-bytes))
      (raise-arguments-error 'odra-package-catalog-fetch-failure
                             "invalid redacted endpoint fetch failure"))
    (values code (string->immutable-string endpoint-id) retryable?
            (string->immutable-string detail))))

(struct transport-response (status headers body) #:transparent)
(struct exn:fail:catalog-fetch exn:fail (code retryable?) #:transparent)

(define (raise-fetch code message [retryable? #f])
  (raise
   (exn:fail:catalog-fetch
    message (current-continuation-marks) code retryable?)))

(define (status-code status)
  (match (regexp-match #px#"^HTTP/[0-9.]+ ([0-9]{3})" status)
    [(list _ code) (string->number (bytes->string/utf-8 code))]
    [_ 0]))

(define (response-headers headers)
  (for/hash ([header (in-list headers)]
             #:do [(define matched
                     (regexp-match #px#"^([^:]+):[ ]*(.*)$" header))]
             #:when matched)
    (values (string-downcase (bytes->string/utf-8 (cadr matched)))
            (bytes->string/utf-8 (caddr matched)))))

(define (request-headers headers)
  (for/list ([(name value) (in-hash headers)])
    (string->bytes/utf-8 (format "~a: ~a" name value))))

(define (default-transport-open uri headers proxy-policy)
  (define-values (status response-header-lines body)
    (parameterize
        ([current-proxy-servers
          (if (eq? proxy-policy 'direct) '() (current-proxy-servers))])
      (http-sendrecv/url
       (string->url uri) #:headers (request-headers headers)
       #:content-decode '())))
  (transport-response
   (status-code status) (response-headers response-header-lines) body))

(define current-catalog-transport-open
  (make-parameter default-transport-open))

(define (valid-credential-headers? value)
  (and (hash? value)
       (for/and ([(name content) (in-hash value)])
         (and (string? name) (string? content)
              (regexp-match? #px"^(?:authorization|x-[a-z0-9-]+)$"
                             (string-downcase name))
              (<= 1 (bytes-length (string->bytes/utf-8 content)) 4096)
              (not (string-contains? content "\r"))
              (not (string-contains? content "\n"))))))

(define (credential-headers endpoint-state resolver)
  (define reference
    (odra-package-catalog-state-endpoint-credential-reference endpoint-state))
  (cond
    [(not reference) (values (hash) #f)]
    [else
     (define resolved
       (with-handlers ([exn:fail? (lambda (_) #f)]) (resolver reference)))
     (unless (valid-credential-headers? resolved)
       (raise-fetch 'credential "endpoint credential could not be resolved"))
     (values
      (for/hash ([(name content) (in-hash resolved)])
        (values (string-downcase name) content))
      #t)]))

(define (deadline-expired? deadline)
  (>= (current-inexact-monotonic-milliseconds) deadline))

(define (check-interruption cancelled? deadline)
  (when (cancelled?)
    (raise-fetch 'cancelled "catalog endpoint fetch was cancelled"))
  (when (deadline-expired? deadline)
    (raise-fetch 'deadline "catalog endpoint deadline expired" #t)))

(define (read-bounded input policy cancelled? deadline)
  (define maximum
    (odra-package-catalog-transport-policy-maximum-bytes policy))
  (define output (open-output-bytes))
  (define buffer (make-bytes transfer-buffer-bytes))
  (let loop ([total 0])
    (check-interruption cancelled? deadline)
    (define ready
      (sync/timeout
       (min 0.05
            (max 0.0
                 (/ (- deadline (current-inexact-monotonic-milliseconds))
                    1000.0)))
       input))
    (cond
      [(not ready) (loop total)]
      [else
       (define amount (read-bytes-avail! buffer input))
       (cond
         [(eof-object? amount)
          (bytes->immutable-bytes (get-output-bytes output))]
         [else
          (define next (+ total amount))
          (when (> next maximum)
            (raise-fetch 'limit "catalog endpoint exceeded its byte limit"))
          (write-bytes buffer output 0 amount)
          (loop next)])])))

(define (safe-https-uri? uri)
  (and (string? uri)
       (regexp-match? #px"^https://[^/@?#]+(?::[0-9]+)?/[^?#]*$" uri)))

(define (uri-authority uri)
  (define parsed (string->url uri))
  (list (url-host parsed) (or (url-port parsed) 443)))

(define (open-https-response uri headers policy cancelled? deadline)
  (check-interruption cancelled? deadline)
  (define result-channel (make-channel))
  (define owner (make-custodian))
  (parameterize ([current-custodian owner])
    (thread
     (lambda ()
       (with-handlers ([exn:fail? (lambda (_) (channel-put result-channel #f))])
         (channel-put
          result-channel
          ((current-catalog-transport-open)
           uri headers
           (odra-package-catalog-transport-policy-proxy-policy policy)))))))
  (with-handlers ([exn:fail:catalog-fetch?
                   (lambda (observed)
                     (custodian-shutdown-all owner)
                     (raise observed))])
    (let loop ()
      (check-interruption cancelled? deadline)
      (define observed (sync/timeout 0.05 result-channel))
      (cond
        [(not observed) (loop)]
        [(not (transport-response? observed))
         (raise-fetch 'transport "catalog endpoint transport failed" #t)]
        [else (values observed owner)]))))

(define (fetch-https uri headers credential-used? policy cancelled? deadline)
  (define attempts 0)
  (define redirected? #f)
  (define (attempt current redirects retries)
    (set! attempts (add1 attempts))
    (define opened
      (with-handlers ([exn:fail:catalog-fetch? values])
        (call-with-values
         (lambda ()
           (open-https-response current headers policy cancelled? deadline))
         list)))
    (cond
      [(exn:fail:catalog-fetch? opened)
       (if (and (exn:fail:catalog-fetch-retryable? opened)
                (positive? retries))
           (attempt current redirects (sub1 retries))
           (raise opened))]
      [else
       (define response (car opened))
       (define owner (cadr opened))
       (define status (transport-response-status response))
       (cond
      [(= status 200)
       (dynamic-wind
         void
         (lambda ()
           (values (read-bounded (transport-response-body response) policy
                                 cancelled? deadline)
                   attempts redirected?))
         (lambda () (custodian-shutdown-all owner)))]
      [(memq status redirect-statuses)
       (define location
         (hash-ref (transport-response-headers response) "location" #f))
       (custodian-shutdown-all owner)
       (unless (and location (safe-https-uri? location))
         (raise-fetch 'redirect "catalog endpoint redirect is unsafe"))
       (when (zero? redirects)
         (raise-fetch 'redirect "catalog endpoint redirect limit was exceeded"))
       (when (and credential-used?
                  (not (equal? (uri-authority uri) (uri-authority location))))
         (raise-fetch 'redirect
                      "credentialed catalog endpoint cannot change authority"))
       (set! redirected? #t)
       (attempt location (sub1 redirects) retries)]
      [(and (memq status retry-statuses) (positive? retries))
       (custodian-shutdown-all owner)
       (attempt current redirects (sub1 retries))]
      [else
       (custodian-shutdown-all owner)
       (raise-fetch 'http-status
                    (format "catalog endpoint returned HTTP status ~a" status)
                    (and (memq status retry-statuses) #t))])]))
  (attempt uri
           (odra-package-catalog-transport-policy-redirect-limit policy)
           (odra-package-catalog-transport-policy-retry-limit policy)))

(define (fetch-file uri policy cancelled? deadline)
  (check-interruption cancelled? deadline)
  (define path (url->path (string->url uri)))
  (with-handlers ([exn:fail:filesystem?
                   (lambda (_)
                     (raise-fetch 'io "local catalog endpoint is unavailable" #t))])
    (call-with-input-file path
      (lambda (input)
        (values (read-bounded input policy cancelled? deadline) 1 #f))
      #:mode 'binary)))

(define (fetch-package-catalog-endpoint endpoint-state policy credential-resolver
                                        #:cancelled? [cancelled? (lambda () #f)])
  (define endpoint
    (odra-package-catalog-state-endpoint-endpoint endpoint-state))
  (define endpoint-id (odra-package-catalog-endpoint-id endpoint))
  (define deadline
    (+ (current-inexact-monotonic-milliseconds)
       (odra-package-catalog-transport-policy-deadline-milliseconds policy)))
  (with-handlers
      ([exn:fail:catalog-fetch?
        (lambda (observed)
          (odra-package-catalog-fetch-failure
           (exn:fail:catalog-fetch-code observed) endpoint-id
           (exn:fail:catalog-fetch-retryable? observed)
           (exn-message observed)))])
    (define-values (headers credential-used?)
      (credential-headers endpoint-state credential-resolver))
    (define-values (bytes attempts redirected?)
      (case (odra-package-catalog-endpoint-transport endpoint)
        [(file)
         (fetch-file (odra-package-catalog-endpoint-uri endpoint) policy
                     cancelled? deadline)]
        [(https)
         (fetch-https (odra-package-catalog-endpoint-uri endpoint) headers
                      credential-used? policy cancelled? deadline)]))
    (odra-package-catalog-fetch-result
     endpoint-id (odra-package-catalog-endpoint-catalog-id endpoint)
     bytes (bytes-length bytes) attempts redirected? credential-used?)))

(module+ test-support
  (provide current-catalog-transport-open
           (struct-out transport-response)))
