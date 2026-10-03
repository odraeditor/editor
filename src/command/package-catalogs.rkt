#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/string
         "../package_catalog/contracts.rkt"
         "../package_catalog/endpoint-transport.rkt"
         "../package_catalog/federated-resolution.rkt"
         "../package_catalog/official-bootstrap.rkt"
         "../package_catalog/security-advisories.rkt"
         "../package_catalog/state-records.rkt")

(provide
 factory-package-catalog-refresh-policy
 factory-package-catalog-advisory-response-policy
 factory-package-catalog-configuration
 (struct-out odra-package-catalog-trust-reference)
 (struct-out odra-package-catalog-config-endpoint)
 (struct-out odra-package-catalog-config-registration)
 (struct-out odra-package-catalog-refresh-policy)
 (struct-out odra-package-catalog-configuration)
 (contract-out
  [package-catalog-trust-reference
   (->* (#:id string? #:catalog-id string?)
        (#:designation symbol?)
        odra-package-catalog-trust-reference?)]
  [package-catalog-endpoint
   (->* (#:id string? #:catalog-id string? #:uri string?)
        (#:role symbol? #:priority exact-nonnegative-integer?
         #:credential-reference (or/c #f string?))
        odra-package-catalog-config-endpoint?)]
  [package-catalog-registration
   (->* (#:id string? #:kind symbol?
         #:trust odra-package-catalog-trust-reference?
         #:endpoints (listof odra-package-catalog-config-endpoint?))
        (#:configuration-origin symbol?
         #:precedence exact-nonnegative-integer?
         #:advisory-policy symbol?
         #:enabled? boolean?)
        odra-package-catalog-config-registration?)]
  [package-catalog-refresh-policy
   (->* ()
        (#:transport odra-package-catalog-transport-policy?
         #:offline-grace-seconds exact-nonnegative-integer?
         #:automatic? boolean?
         #:interval-seconds exact-positive-integer?)
        odra-package-catalog-refresh-policy?)]
  [package-source-pin
   (-> string? string? odra-package-source-pin?)]
  [package-organization-override
   (-> string? string? odra-package-organization-override?)]
  [package-catalog-configuration
   (->* ()
        (#:registrations (listof odra-package-catalog-config-registration?)
         #:source-pins (listof odra-package-source-pin?)
         #:organization-overrides
         (listof odra-package-organization-override?)
         #:refresh-policy odra-package-catalog-refresh-policy?
         #:advisory-response-policy
         odra-security-advisory-response-policy?)
        odra-package-catalog-configuration?)]
  [package-catalog-registration-state
   (-> odra-package-catalog-config-registration?
       (values odra-package-catalog-registration?
               (listof odra-package-catalog-state-endpoint?)))]))

(define maximum-configuration-text-bytes 4096)
(define maximum-refresh-interval-seconds (* 30 24 60 60))
(define digest-pattern #px"^[0-9a-f]{64}$")
(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")

(define (digest? value)
  (and (string? value) (regexp-match? digest-pattern value)))

(define (identity? value)
  (and (string? value)
       (<= 1 (bytes-length (string->bytes/utf-8 value)) 128)
       (regexp-match? identity-pattern value)))

(define (bounded-text? value)
  (and (string? value)
       (positive? (string-length value))
       (not (string-contains? value (string #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value))
           maximum-configuration-text-bytes)))

(define (copied value)
  (if (string? value) (string->immutable-string value) value))

(define (unique? values key same?)
  (= (length values) (length (remove-duplicates values same? #:key key))))

(struct odra-package-catalog-trust-reference (id catalog-id designation)
  #:transparent
  #:guard
  (lambda (id catalog-id designation _)
    (unless (and (digest? id) (digest? catalog-id)
                 (memq designation '(independent official))
                 (if (eq? designation 'official)
                     (and (string=? id official-package-catalog-root-key-id)
                          (string=? catalog-id
                                    official-package-catalog-identity))
                     #t))
      (raise-arguments-error
       'odra-package-catalog-trust-reference
       "invalid pinned package catalog trust reference"))
    (values (copied id) (copied catalog-id) designation)))

(struct odra-package-catalog-config-endpoint (endpoint credential-reference)
  #:transparent
  #:guard
  (lambda (endpoint credential-reference _)
    (unless
        (and (odra-package-catalog-endpoint? endpoint)
             (or (not credential-reference)
                 (bounded-text? credential-reference))
             (or (not credential-reference)
                 (eq? (odra-package-catalog-endpoint-transport endpoint)
                      'https)))
      (raise-arguments-error
       'odra-package-catalog-config-endpoint
       "invalid checked package catalog endpoint configuration"))
    (values endpoint (and credential-reference (copied credential-reference)))))

(define (config-endpoint-id value)
  (odra-package-catalog-endpoint-id
   (odra-package-catalog-config-endpoint-endpoint value)))

(define (config-endpoint-catalog-id value)
  (odra-package-catalog-endpoint-catalog-id
   (odra-package-catalog-config-endpoint-endpoint value)))

(define (local-endpoint? value)
  (eq? (odra-package-catalog-endpoint-transport
        (odra-package-catalog-config-endpoint-endpoint value))
       'file))

(struct odra-package-catalog-config-registration
  (id kind configuration-origin trust endpoints precedence advisory-policy
      enabled?)
  #:transparent
  #:guard
  (lambda (id kind configuration-origin trust endpoints precedence
              advisory-policy enabled? _)
    (define catalog-id
      (and (odra-package-catalog-trust-reference? trust)
           (odra-package-catalog-trust-reference-catalog-id trust)))
    (unless
        (and (identity? id)
             (memq kind '(independent local official private))
             (memq configuration-origin
                   '(administrator built-in project user))
             catalog-id
             (list? endpoints)
             (or (not enabled?) (pair? endpoints))
             (<= (length endpoints) maximum-package-catalog-state-endpoints)
             (andmap odra-package-catalog-config-endpoint? endpoints)
             (unique? endpoints config-endpoint-id string=?)
             (andmap
              (lambda (endpoint)
                (string=? catalog-id (config-endpoint-catalog-id endpoint)))
              endpoints)
             (if (eq? kind 'official)
                 (eq? (odra-package-catalog-trust-reference-designation trust)
                      'official)
                 (eq? (odra-package-catalog-trust-reference-designation trust)
                      'independent))
             (if (eq? kind 'local)
                 (andmap local-endpoint? endpoints)
                 #t)
             (if (eq? kind 'private)
                 (ormap
                  odra-package-catalog-config-endpoint-credential-reference
                  endpoints)
                 #t)
             (exact-nonnegative-integer? precedence)
             (<= precedence 65535)
             (memq advisory-policy '(enforce observe warn))
             (boolean? enabled?))
      (raise-arguments-error
       'odra-package-catalog-config-registration
       "invalid explicit package catalog registration configuration"))
    (values
     (copied id) kind configuration-origin trust
     (sort endpoints string<? #:key config-endpoint-id)
     precedence advisory-policy enabled?)))

(struct odra-package-catalog-refresh-policy
  (transport offline-grace-seconds automatic? interval-seconds)
  #:transparent
  #:guard
  (lambda (transport offline-grace-seconds automatic? interval-seconds _)
    (unless
        (and (odra-package-catalog-transport-policy? transport)
             (exact-nonnegative-integer? offline-grace-seconds)
             (<= offline-grace-seconds maximum-refresh-interval-seconds)
             (boolean? automatic?)
             (exact-positive-integer? interval-seconds)
             (<= interval-seconds maximum-refresh-interval-seconds))
      (raise-arguments-error
       'odra-package-catalog-refresh-policy
       "invalid bounded package catalog refresh policy"))
    (values transport offline-grace-seconds automatic? interval-seconds)))

(struct odra-package-catalog-configuration
  (registrations source-pins organization-overrides refresh-policy
      advisory-response-policy)
  #:transparent
  #:guard
  (lambda (registrations source-pins organization-overrides refresh-policy
                          advisory-response-policy _)
    (unless
        (and (list? registrations)
             (<= (length registrations) maximum-package-catalog-registrations)
             (andmap odra-package-catalog-config-registration? registrations)
             (unique? registrations
                      odra-package-catalog-config-registration-id string=?)
             (unique?
              registrations
              (lambda (registration)
                (odra-package-catalog-trust-reference-catalog-id
                 (odra-package-catalog-config-registration-trust registration)))
              string=?)
             (list? source-pins)
             (andmap odra-package-source-pin? source-pins)
             (unique? source-pins odra-package-source-pin-package-id string=?)
             (list? organization-overrides)
             (andmap odra-package-organization-override?
                     organization-overrides)
             (unique?
              organization-overrides
              odra-package-organization-override-organization-id string=?)
             (odra-package-catalog-refresh-policy? refresh-policy)
             (odra-security-advisory-response-policy?
              advisory-response-policy))
      (raise-arguments-error
       'odra-package-catalog-configuration
       "invalid bounded package catalog configuration"))
    (values
     (sort registrations string<?
           #:key odra-package-catalog-config-registration-id)
     (sort source-pins string<? #:key odra-package-source-pin-package-id)
     (sort organization-overrides string<?
           #:key odra-package-organization-override-organization-id)
     refresh-policy advisory-response-policy)))

(define factory-package-catalog-refresh-policy
  (odra-package-catalog-refresh-policy
   (odra-package-catalog-bootstrap-transport-policy
    official-package-catalog-bootstrap)
   (odra-package-catalog-bootstrap-offline-grace-seconds
    official-package-catalog-bootstrap)
   (odra-package-catalog-bootstrap-automatic?
    official-package-catalog-bootstrap)
   (odra-package-catalog-bootstrap-interval-seconds
    official-package-catalog-bootstrap)))

(define factory-package-catalog-advisory-response-policy
  (odra-package-catalog-bootstrap-advisory-response-policy
   official-package-catalog-bootstrap))

(define official-profile
  (odra-package-catalog-bootstrap-profile official-package-catalog-bootstrap))
(define official-endpoints
  (for/list ([endpoint
              (in-list
               (odra-package-catalog-profile-endpoints official-profile))])
    (odra-package-catalog-config-endpoint
     endpoint official-package-catalog-credential-reference)))
(define factory-official-package-catalog-registration
  (odra-package-catalog-config-registration
   "odra-official" 'official 'built-in
   (odra-package-catalog-trust-reference
    official-package-catalog-root-key-id
    official-package-catalog-identity
    'official)
   official-endpoints 0 'enforce #t))

(define factory-package-catalog-configuration
  (odra-package-catalog-configuration
   (list factory-official-package-catalog-registration)
   '() '() factory-package-catalog-refresh-policy
   factory-package-catalog-advisory-response-policy))

(define (package-catalog-trust-reference
         #:id id #:catalog-id catalog-id
         #:designation [designation 'independent])
  (odra-package-catalog-trust-reference id catalog-id designation))

(define (endpoint-transport uri)
  (cond
    [(regexp-match? #px"^file:///" uri) 'file]
    [(regexp-match? #px"^https://" uri) 'https]
    [else
     (raise-arguments-error
      'package-catalog-endpoint
      "endpoint URI must use file or HTTPS transport")]))

(define (package-catalog-endpoint
         #:id id #:catalog-id catalog-id #:uri uri
         #:role [role 'origin] #:priority [priority 0]
         #:credential-reference [credential-reference #f])
  (odra-package-catalog-config-endpoint
   (odra-package-catalog-endpoint
    id catalog-id uri (endpoint-transport uri) role priority #t)
   credential-reference))

(define (package-catalog-registration
         #:id id #:kind kind #:trust trust #:endpoints endpoints
         #:configuration-origin [configuration-origin 'user]
         #:precedence [precedence 0]
         #:advisory-policy [advisory-policy 'enforce]
         #:enabled? [enabled? #t])
  (odra-package-catalog-config-registration
   id kind configuration-origin trust endpoints precedence advisory-policy
   enabled?))

(define (package-catalog-refresh-policy
         #:transport
         [transport
          (odra-package-catalog-refresh-policy-transport
           factory-package-catalog-refresh-policy)]
         #:offline-grace-seconds
         [offline-grace-seconds
          (odra-package-catalog-refresh-policy-offline-grace-seconds
           factory-package-catalog-refresh-policy)]
         #:automatic?
         [automatic?
          (odra-package-catalog-refresh-policy-automatic?
           factory-package-catalog-refresh-policy)]
         #:interval-seconds
         [interval-seconds
          (odra-package-catalog-refresh-policy-interval-seconds
           factory-package-catalog-refresh-policy)])
  (odra-package-catalog-refresh-policy
   transport offline-grace-seconds automatic? interval-seconds))

(define (package-source-pin package-id catalog-id)
  (odra-package-source-pin package-id catalog-id))

(define (package-organization-override organization-id catalog-id)
  (odra-package-organization-override organization-id catalog-id))

(define (package-catalog-configuration
         #:registrations [registrations '()]
         #:source-pins [source-pins '()]
         #:organization-overrides [organization-overrides '()]
         #:refresh-policy
         [refresh-policy factory-package-catalog-refresh-policy]
         #:advisory-response-policy
         [advisory-response-policy
          factory-package-catalog-advisory-response-policy])
  (odra-package-catalog-configuration
   registrations source-pins organization-overrides refresh-policy
   advisory-response-policy))

(define (package-catalog-registration-state registration)
  (define trust
    (odra-package-catalog-config-registration-trust registration))
  (values
   (odra-package-catalog-registration
    current-package-catalog-state-format-version
    (odra-package-catalog-config-registration-id registration)
    1
    (odra-package-catalog-trust-reference-catalog-id trust)
    (odra-package-catalog-config-registration-configuration-origin registration)
    (odra-package-catalog-trust-reference-id trust)
    (map config-endpoint-id
         (odra-package-catalog-config-registration-endpoints registration))
    (odra-package-catalog-config-registration-precedence registration)
    (odra-package-catalog-config-registration-advisory-policy registration)
    (odra-package-catalog-config-registration-enabled? registration)
    (if (odra-package-catalog-config-registration-enabled? registration)
        'never
        'blocked))
   (for/list
       ([configured
         (in-list
          (odra-package-catalog-config-registration-endpoints registration))])
     (odra-package-catalog-state-endpoint
      current-package-catalog-state-format-version 1
      (odra-package-catalog-config-endpoint-endpoint configured)
      (odra-package-catalog-config-endpoint-credential-reference configured)))))

(module+ test
  (require rackunit)

  (define catalog-id (make-string 64 #\a))
  (define trust-id (make-string 64 #\b))
  (define trust
    (package-catalog-trust-reference #:id trust-id #:catalog-id catalog-id))
  (define local
    (package-catalog-endpoint
     #:id "local" #:catalog-id catalog-id #:uri "file:///tmp/catalog.rktd"
     #:role 'local))
  (define registration
    (package-catalog-registration
     #:id "local" #:kind 'local #:trust trust #:endpoints (list local)
     #:precedence 20))
  (define configuration
    (package-catalog-configuration #:registrations (list registration)))
  (check-true (odra-package-catalog-configuration? configuration))
  (define-values (state-registration endpoints)
    (package-catalog-registration-state registration))
  (check-equal?
   (odra-package-catalog-registration-catalog-id state-registration) catalog-id)
  (check-equal? (length endpoints) 1)
  (check-exn
   exn:fail?
   (lambda ()
     (package-catalog-registration
      #:id "private" #:kind 'private #:trust trust
      #:endpoints
      (list
       (package-catalog-endpoint
        #:id "public" #:catalog-id catalog-id
        #:uri "https://catalog.example/snapshot.rktd")))))
  (check-exn
   exn:fail?
   (lambda ()
     (package-catalog-registration
      #:id "local" #:kind 'local #:trust trust
      #:endpoints
      (list
       (package-catalog-endpoint
        #:id "remote" #:catalog-id catalog-id
        #:uri "https://catalog.example/snapshot.rktd"))))))
