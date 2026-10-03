#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "definition.rkt")

(provide
 maximum-active-agent-definitions
 maximum-active-agent-capability-definitions
 (struct-out odra-agent-definition-projection)
 (struct-out odra-agent-capability-projection)
 (struct-out odra-agent-contribution-source)
 (struct-out odra-agent-catalog)
 (contract-out
  [make-agent-contribution-source
   (->* (string? string? exact-positive-integer? list? list?)
        (#:authorities list?)
        odra-agent-contribution-source?)]
  [compose-agent-catalog
   (-> exact-positive-integer? list? odra-agent-catalog?)]
  [empty-agent-catalog (-> odra-agent-catalog?)]
  [agent-catalog-agent-by-identity
   (-> odra-agent-catalog? string?
       (or/c #f odra-agent-definition-projection?))]
  [agent-catalog-capability-by-identity
   (-> odra-agent-catalog? string?
       (or/c #f odra-agent-capability-projection?))]))

(define maximum-active-agent-definitions 64)
(define maximum-active-agent-capability-definitions 256)

(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
(define version-pattern
  #px"^(?:0|[1-9][0-9]*)[.](?:0|[1-9][0-9]*)[.](?:0|[1-9][0-9]*)(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$")

(define (identity? value)
  (and (string? value)
       (<= (bytes-length (string->bytes/utf-8 value)) 128)
       (regexp-match? identity-pattern value)))

(define (version? value)
  (and (string? value)
       (<= (bytes-length (string->bytes/utf-8 value)) 128)
       (regexp-match? version-pattern value)))

(struct odra-agent-definition-projection
  (identity definition-generation package-id package-version
            contribution-generation display-name description interaction-kinds
            provider-requirements requested-capabilities resource-profile
            continuation-policy api-version source location)
  #:transparent)

(struct odra-agent-capability-projection
  (identity definition-generation package-id package-version
            contribution-generation owner-namespace purpose input-schema
            result-schema target-kinds effects required-authorities
            package-authorities
            default-limits hard-limits approval-class idempotency-class
            verification-class retirement-policy compatibility-version source
            location)
  #:transparent)

(struct odra-agent-contribution-source
  (package-id package-version contribution-generation agent-definitions
              capability-definitions admitted-authorities agent-projections
              capability-projections)
  #:transparent)

(struct odra-agent-catalog (generation sources agents capabilities)
  #:transparent)

(define (definition->projection package-id version generation definition)
  (odra-agent-definition-projection
   (odra-agent-definition-identity definition) generation package-id version
   generation (odra-agent-definition-display-name definition)
   (odra-agent-definition-description definition)
   (odra-agent-definition-interaction-kinds definition)
   (odra-agent-definition-provider-requirements definition)
   (odra-agent-definition-requested-capabilities definition)
   (odra-agent-definition-resource-profile definition)
   (odra-agent-definition-continuation-policy definition)
   (odra-agent-definition-api-version definition)
   (odra-agent-definition-source definition)
   (odra-agent-definition-location definition)))

(define (capability->projection
         package-id version generation admitted-authorities definition)
  (odra-agent-capability-projection
   (odra-agent-capability-definition-identity definition) generation package-id
   version generation
   (odra-agent-capability-definition-owner-namespace definition)
   (odra-agent-capability-definition-purpose definition)
   (odra-agent-capability-definition-input-schema definition)
   (odra-agent-capability-definition-result-schema definition)
   (odra-agent-capability-definition-target-kinds definition)
   (odra-agent-capability-definition-effects definition)
   (odra-agent-capability-definition-required-authorities definition)
   admitted-authorities
   (odra-agent-capability-definition-default-limits definition)
   (odra-agent-capability-definition-hard-limits definition)
   (odra-agent-capability-definition-approval-class definition)
   (odra-agent-capability-definition-idempotency-class definition)
   (odra-agent-capability-definition-verification-class definition)
   (odra-agent-capability-definition-retirement-policy definition)
   (odra-agent-capability-definition-compatibility-version definition)
   (odra-agent-capability-definition-source definition)
   (odra-agent-capability-definition-location definition)))

(define (make-agent-contribution-source
         package-id package-version generation agents capabilities
         #:authorities [authorities '()])
  (unless (and (identity? package-id)
               (version? package-version)
               (exact-positive-integer? generation)
               (list? agents)
               (andmap odra-agent-definition? agents)
               (<= (length agents) maximum-active-agent-definitions)
               (list? capabilities)
               (andmap odra-agent-capability-definition? capabilities)
               (<= (length capabilities)
                   maximum-active-agent-capability-definitions)
               (list? authorities)
               (andmap symbol? authorities)
               (equal? authorities
                       (sort (remove-duplicates authorities) symbol<?)))
    (raise-arguments-error 'make-agent-contribution-source
                           "invalid bounded agent contribution source"))
  (odra-agent-contribution-source
   (string->immutable-string package-id)
   (string->immutable-string package-version)
   generation (append agents '()) (append capabilities '())
   (append authorities '())
   (for/list ([definition (in-list agents)])
     (definition->projection package-id package-version generation definition))
   (for/list ([definition (in-list capabilities)])
     (capability->projection
      package-id package-version generation authorities definition))))

(define (projection-identities projections identity)
  (map identity projections))

(define (ensure-unique who kind projections identity)
  (define identities (projection-identities projections identity))
  (unless (= (length identities) (length (remove-duplicates identities string=?)))
    (raise-arguments-error who
                           (format "~a identities must be unique" kind)
                           "identities" identities)))

(define (compose-agent-catalog generation sources)
  (unless (and (exact-positive-integer? generation)
               (list? sources)
               (andmap odra-agent-contribution-source? sources))
    (raise-arguments-error 'compose-agent-catalog
                           "invalid agent contribution source set"))
  (define sorted-sources
    (sort sources string<? #:key odra-agent-contribution-source-package-id))
  (define package-ids
    (map odra-agent-contribution-source-package-id sorted-sources))
  (unless (= (length package-ids) (length (remove-duplicates package-ids string=?)))
    (raise-arguments-error 'compose-agent-catalog
                           "package contribution sources must be unique"))
  (define agents
    (append* (map odra-agent-contribution-source-agent-projections
                  sorted-sources)))
  (define capabilities
    (append* (map odra-agent-contribution-source-capability-projections
                  sorted-sources)))
  (unless (<= (length agents) maximum-active-agent-definitions)
    (raise-arguments-error 'compose-agent-catalog
                           "active agent definition limit exceeded"))
  (unless (<= (length capabilities)
              maximum-active-agent-capability-definitions)
    (raise-arguments-error 'compose-agent-catalog
                           "active agent capability definition limit exceeded"))
  (ensure-unique 'compose-agent-catalog "agent"
                 agents odra-agent-definition-projection-identity)
  (ensure-unique 'compose-agent-catalog "capability"
                 capabilities odra-agent-capability-projection-identity)
  (odra-agent-catalog
   generation sorted-sources
   (sort agents string<? #:key odra-agent-definition-projection-identity)
   (sort capabilities string<?
         #:key odra-agent-capability-projection-identity)))

(define (empty-agent-catalog)
  (compose-agent-catalog 1 '()))

(define (agent-catalog-agent-by-identity catalog identity)
  (for/first ([definition (in-list (odra-agent-catalog-agents catalog))]
              #:when
              (string=? identity
                        (odra-agent-definition-projection-identity definition)))
    definition))

(define (agent-catalog-capability-by-identity catalog identity)
  (for/first
      ([definition (in-list (odra-agent-catalog-capabilities catalog))]
       #:when
       (string=? identity
                 (odra-agent-capability-projection-identity definition)))
    definition))
