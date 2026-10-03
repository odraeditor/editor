#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require file/sha1
         racket/contract/base
         racket/list
         racket/match
         racket/port
         "admission.rkt"
         "audit.rkt"
         "authority.rkt"
         "continuity-store.rkt"
         "driver.rkt"
         "execution.rkt"
         "registry.rkt")

(provide
 maximum-agent-definition-tombstones
 maximum-agent-reconciliation-cleanup-batch
 (struct-out odra-agent-definition-tombstone)
 (struct-out odra-agent-lifecycle-summary)
 (struct-out odra-agent-history-preservation)
 (contract-out
  [inspect-agent-definition-tombstones
   (-> odra-agent-continuity-store?
       (listof odra-agent-definition-tombstone?))]
  [reconcile-agent-package-lifecycle!
   (->* (odra-agent-continuity-store? odra-agent-authority-store?
         odra-agent-catalog? odra-agent-catalog? exact-nonnegative-integer?)
        (#:actor (or/c symbol? string?))
        odra-agent-lifecycle-summary?)]
  [inspect-agent-substrate-history
   (-> odra-agent-continuity-store? odra-agent-history-preservation?)]
  [preserve-agent-substrate-history!
   (->* (odra-agent-continuity-store? odra-agent-catalog?
         exact-nonnegative-integer?)
        (#:actor (or/c symbol? string?))
        odra-agent-history-preservation?)]
  [cleanup-agent-reconciliation-history!
   (->* (odra-agent-continuity-store? exact-nonnegative-integer?
         exact-nonnegative-integer?)
        (#:actor (or/c symbol? string?))
        exact-nonnegative-integer?)]))

(define maximum-agent-definition-tombstones 10000)
(define maximum-agent-reconciliation-cleanup-batch 1024)

(struct odra-agent-definition-tombstone
  (identity definition-identity definition-generation definition-kind
            package-id package-version contribution-generation
            compatibility-version display-name owner-namespace target-kinds
            effect-classes provenance-identity retirement-reason retired-at
            projection-digest)
  #:transparent)

(struct odra-agent-lifecycle-summary
  (tombstones grants sessions turns attempts indexes-rebuilt?)
  #:transparent)

(struct odra-agent-history-preservation
  (tasks interactions delegations requests driver-sessions turns attempts
         results audit-events tombstones)
  #:transparent)

(define (encode-datum datum)
  (with-output-to-string (lambda () (write datum))))

(define (decode-datum text who)
  (parameterize ([read-accept-reader #f]
                 [read-accept-lang #f])
    (define input (open-input-string text))
    (define datum (read input))
    (unless (eof-object? (read input))
      (error who "persisted record contains trailing data"))
    datum))

(define (digest datum)
  (string->immutable-string
   (sha1 (open-input-string (encode-datum datum)))))

(define (tombstone-identity kind identity generation)
  (string->immutable-string
   (string-append "tombstone." (symbol->string kind) "."
                  (digest (list identity generation)))))

(define (agent-projection->tombstone projection reason retired-at)
  (define safe-projection
    (list 'agent
          (odra-agent-definition-projection-identity projection)
          (odra-agent-definition-projection-definition-generation projection)
          (odra-agent-definition-projection-package-id projection)
          (odra-agent-definition-projection-package-version projection)
          (odra-agent-definition-projection-contribution-generation projection)
          (odra-agent-definition-projection-api-version projection)
          (odra-agent-definition-projection-display-name projection)))
  (odra-agent-definition-tombstone
   (tombstone-identity
    'agent (odra-agent-definition-projection-identity projection)
    (odra-agent-definition-projection-definition-generation projection))
   (odra-agent-definition-projection-identity projection)
   (odra-agent-definition-projection-definition-generation projection)
   'agent
   (odra-agent-definition-projection-package-id projection)
   (odra-agent-definition-projection-package-version projection)
   (odra-agent-definition-projection-contribution-generation projection)
   (odra-agent-definition-projection-api-version projection)
   (odra-agent-definition-projection-display-name projection)
   (odra-agent-definition-projection-identity projection)
   '() '() 'package-contribution reason retired-at (digest safe-projection)))

(define (capability-projection->tombstone projection reason retired-at)
  (define safe-projection
    (list 'capability
          (odra-agent-capability-projection-identity projection)
          (odra-agent-capability-projection-definition-generation projection)
          (odra-agent-capability-projection-package-id projection)
          (odra-agent-capability-projection-package-version projection)
          (odra-agent-capability-projection-contribution-generation projection)
          (odra-agent-capability-projection-compatibility-version projection)
          (odra-agent-capability-projection-owner-namespace projection)
          (odra-agent-capability-projection-target-kinds projection)
          (odra-agent-capability-projection-effects projection)))
  (odra-agent-definition-tombstone
   (tombstone-identity
    'capability (odra-agent-capability-projection-identity projection)
    (odra-agent-capability-projection-definition-generation projection))
   (odra-agent-capability-projection-identity projection)
   (odra-agent-capability-projection-definition-generation projection)
   'capability
   (odra-agent-capability-projection-package-id projection)
   (odra-agent-capability-projection-package-version projection)
   (odra-agent-capability-projection-contribution-generation projection)
   (odra-agent-capability-projection-compatibility-version projection)
   (odra-agent-capability-projection-identity projection)
   (odra-agent-capability-projection-owner-namespace projection)
   (append (odra-agent-capability-projection-target-kinds projection) '())
   (append (odra-agent-capability-projection-effects projection) '())
   'package-contribution reason retired-at (digest safe-projection)))

(define (tombstone->datum tombstone)
  (list 'definition-tombstone
        (odra-agent-definition-tombstone-compatibility-version tombstone)
        (odra-agent-definition-tombstone-display-name tombstone)
        (odra-agent-definition-tombstone-owner-namespace tombstone)
        (odra-agent-definition-tombstone-target-kinds tombstone)
        (odra-agent-definition-tombstone-effect-classes tombstone)
        (odra-agent-definition-tombstone-provenance-identity tombstone)
        (odra-agent-definition-tombstone-retirement-reason tombstone)
        (odra-agent-definition-tombstone-projection-digest tombstone)))

(define (row->tombstone row)
  (match (decode-datum (vector-ref row 8)
                       'inspect-agent-definition-tombstones)
    [(list 'definition-tombstone compatibility display owner targets effects
           provenance reason projection-digest)
     (odra-agent-definition-tombstone
      (string->immutable-string (vector-ref row 0))
      (string->immutable-string (vector-ref row 1))
      (vector-ref row 2) (string->symbol (vector-ref row 3))
      (string->immutable-string (vector-ref row 4))
      (string->immutable-string (vector-ref row 5))
      (vector-ref row 6) compatibility display owner targets effects
      provenance reason (vector-ref row 7) projection-digest)]
    [_ (error 'inspect-agent-definition-tombstones
              "invalid persisted definition tombstone")]))

(define (inspect-agent-definition-tombstones store)
  (map row->tombstone (continuity-store-tombstone-records store)))

(define (inspect-agent-substrate-history store)
  (odra-agent-history-preservation
   (length (continuity-store-task-records store))
   (continuity-store-interaction-count store)
   (continuity-store-delegation-count store)
   (continuity-store-request-count store)
   (continuity-store-driver-session-count store)
   (continuity-store-turn-count store)
   (continuity-store-attempt-count store)
   (continuity-store-result-count store)
   (continuity-store-audit-count store)
   (continuity-store-tombstone-count store)))

(define (persist-tombstone! store tombstone)
  (cond
    [(>= (continuity-store-tombstone-count store)
         maximum-agent-definition-tombstones)
     #f]
    [else
     (call-with-agent-continuity-transaction
      store 'record-definition-tombstone
      (lambda (connection)
        (continuity-transaction-insert-tombstone!
         connection
         (odra-agent-definition-tombstone-identity tombstone)
         (odra-agent-definition-tombstone-definition-identity tombstone)
         (odra-agent-definition-tombstone-definition-generation tombstone)
         (odra-agent-definition-tombstone-definition-kind tombstone)
         (odra-agent-definition-tombstone-package-id tombstone)
         (odra-agent-definition-tombstone-package-version tombstone)
         (odra-agent-definition-tombstone-contribution-generation tombstone)
         (odra-agent-definition-tombstone-retired-at tombstone)
         (encode-datum (tombstone->datum tombstone)))))]))

(define (projection-retired? identity generation current identity-of generation-of)
  (define replacement
    (for/first ([projection (in-list current)]
                #:when (string=? identity (identity-of projection)))
      projection))
  (or (not replacement) (not (= generation (generation-of replacement)))))

(define (retired-agent? retired identity generation)
  (for/or ([projection (in-list retired)])
    (and (string=? identity
                   (odra-agent-definition-projection-identity projection))
         (= generation
            (odra-agent-definition-projection-definition-generation
             projection)))))

(define (retired-capability? retired identity generation)
  (for/or ([projection (in-list retired)])
    (and (string=? identity
                   (odra-agent-capability-projection-identity projection))
         (= generation
            (odra-agent-capability-projection-definition-generation
             projection)))))

(define (reconcile-count rows inspect retired? reconcile! store now)
  (for/sum ([row (in-list rows)])
    (define record (inspect store (vector-ref row 0)))
    (if (and record (retired? record))
        (let ([result
               (reconcile! store (vector-ref row 0) (vector-ref row 1) now)])
          (if (or (odra-agent-driver-denial? result)
                  (odra-agent-execution-denial? result))
              0 1))
        0)))

(define (package-active? catalog reference)
  (for/or ([source (in-list (odra-agent-catalog-sources catalog))])
    (and
     (string=? (odra-agent-package-reference-identity reference)
               (odra-agent-contribution-source-package-id source))
     (string=? (odra-agent-package-reference-version reference)
               (odra-agent-contribution-source-package-version source))
     (= (odra-agent-package-reference-contribution-generation reference)
        (odra-agent-contribution-source-contribution-generation source)))))

(define (preserve-agent-substrate-history!
         store catalog now #:actor [actor 'local-user])
  (define tombstones
    (append
     (for/list ([projection (in-list (odra-agent-catalog-agents catalog))])
       (agent-projection->tombstone projection 'substrate-disabled now))
     (for/list
         ([projection (in-list (odra-agent-catalog-capabilities catalog))])
       (capability-projection->tombstone projection 'substrate-disabled now))))
  (for ([tombstone (in-list tombstones)])
    (persist-tombstone! store tombstone))
  (record-agent-audit-event!
   store
   (format "audit.substrate-disabled.~a"
           (odra-agent-catalog-generation catalog))
   'substrate-disabled actor
   (list 'definitions (length tombstones) 'operational-state 'retained
         'external-state 'untouched)
   now
   #:visibility 'administrator
   #:redaction-class 'identity-only)
  (inspect-agent-substrate-history store))

(define (cleanup-agent-reconciliation-history!
         store before now #:actor [actor 'local-user])
  (define removed
    (continuity-store-cleanup-reconciliation!
     store before maximum-agent-reconciliation-cleanup-batch))
  (record-agent-audit-event!
   store
   (format "audit.reconciliation-cleanup.~a.~a" before now)
   'retention-cleanup actor
   (list 'record-family 'reconciliation-marker
         'removed removed
         'canonical-owner-state 'untouched)
   now
   #:visibility 'administrator
   #:redaction-class 'identity-only)
  removed)

(define (reconcile-agent-package-lifecycle!
         store authority-store previous current now #:actor [actor 'local-user])
  (define retired-agents
    (filter
     (lambda (projection)
       (projection-retired?
        (odra-agent-definition-projection-identity projection)
        (odra-agent-definition-projection-definition-generation projection)
        (odra-agent-catalog-agents current)
        odra-agent-definition-projection-identity
        odra-agent-definition-projection-definition-generation))
     (odra-agent-catalog-agents previous)))
  (define retired-capabilities
    (filter
     (lambda (projection)
       (projection-retired?
        (odra-agent-capability-projection-identity projection)
        (odra-agent-capability-projection-definition-generation projection)
        (odra-agent-catalog-capabilities current)
        odra-agent-capability-projection-identity
        odra-agent-capability-projection-definition-generation))
     (odra-agent-catalog-capabilities previous)))
  (define tombstones
    (append
     (for/list ([projection (in-list retired-agents)])
       (agent-projection->tombstone
        projection
        (if (agent-catalog-agent-by-identity
             current (odra-agent-definition-projection-identity projection))
            'replaced 'removed)
        now))
     (for/list ([projection (in-list retired-capabilities)])
       (capability-projection->tombstone
        projection
        (if (agent-catalog-capability-by-identity
             current (odra-agent-capability-projection-identity projection))
            'replaced 'removed)
        now))))
  (define tombstone-count
    (for/sum ([tombstone (in-list tombstones)])
      (if (persist-tombstone! store tombstone) 1 0)))
  (define revoked-grants
    (for/sum ([grant (in-list (inspect-agent-grants authority-store #:at now))])
      (if (and
           (eq? (odra-agent-grant-projection-state grant) 'active)
           (or
            (retired-agent?
             retired-agents
             (odra-agent-grant-projection-agent-identity grant)
             (odra-agent-grant-projection-agent-definition-generation grant))
            (retired-capability?
             retired-capabilities
             (odra-agent-grant-projection-capability-identity grant)
             (odra-agent-grant-projection-capability-definition-generation
              grant))))
          (let ([result
                 (revoke-agent-capability-grant!
                  authority-store
                  (odra-agent-grant-projection-identity grant)
                  (odra-agent-grant-projection-generation grant)
                  "The referenced package definition was retired." now)])
            (if (odra-agent-authority-denial? result) 0 1))
          0)))
  (define sessions
    (reconcile-count
     (continuity-store-recovery-session-records store)
     inspect-agent-driver-session
     (lambda (session)
       (retired-agent?
        retired-agents
        (odra-agent-driver-session-agent-identity session)
        (odra-agent-driver-session-agent-definition-generation session)))
     reconcile-agent-driver-session! store now))
  (define turns
    (reconcile-count
     (continuity-store-recovery-turn-records store)
     inspect-agent-turn
     (lambda (turn)
       (retired-agent?
        retired-agents
        (odra-agent-turn-agent-identity turn)
        (odra-agent-turn-agent-definition-generation turn)))
     reconcile-agent-turn! store now))
  (define attempts
    (reconcile-count
     (continuity-store-recovery-attempt-records store)
     inspect-agent-operation-attempt
     (lambda (attempt)
       (define request
         (inspect-agent-capability-request
          store (odra-agent-operation-attempt-request-id attempt)))
       (and request
            (not
             (package-active?
              current
              (odra-agent-capability-request-package-reference request)))))
     reconcile-agent-operation-attempt! store now))
  (continuity-store-rebuild-indexes! store)
  (record-agent-audit-event!
   store
   (format "audit.lifecycle.~a.~a"
           (odra-agent-catalog-generation previous)
           (odra-agent-catalog-generation current))
   'package-lifecycle actor
   (list 'retired-definitions (length tombstones)
         'persisted-tombstones tombstone-count
         'revoked-grants revoked-grants
         'reconciling (+ sessions turns attempts))
   now
   #:visibility 'administrator
   #:redaction-class 'identity-only)
  (odra-agent-lifecycle-summary
   tombstone-count revoked-grants sessions turns attempts #t))
