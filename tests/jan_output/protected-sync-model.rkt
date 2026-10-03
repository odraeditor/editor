#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         racket/match)

(provide plan-protection
         protected-consumer-visible?
         plaintext-save-allowed?
         stage-synchronization
         reconcile-protected-synchronization
         plan-synchronization-apply)

(define (select-provider identity generation providers capability)
  (define selected
    (filter (lambda (provider)
              (and (eq? (hash-ref provider 'identity #f) identity)
                   (= (hash-ref provider 'generation 0) generation)))
            providers))
  (and (= (length selected) 1)
       (let ([provider (car selected)])
         (and (hash-ref provider 'admitted? #f)
              (eq? (hash-ref provider 'state #f) 'available)
              (member capability (hash-ref provider 'capabilities '()))
              provider))))

(define (plan-protection request providers)
  (define action (hash-ref request 'action #f))
  (define capability (case action [(encrypt) 'encrypt] [(decrypt) 'decrypt] [else #f]))
  (define provider
    (and capability
         (select-provider (hash-ref request 'provider #f)
                          (hash-ref request 'provider-generation 0)
                          providers capability)))
  (and provider
       (hash-ref request 'explicit? #f)
       (eq? (hash-ref request 'trigger #f) 'explicit-command)
       (exact-positive-integer? (hash-ref request 'configuration-generation #f))
       (exact-positive-integer? (hash-ref request 'credential-handle #f))
       (= (hash-ref request 'credential-generation 0)
          (hash-ref provider 'credential-generation -1))
       (or (and (eq? action 'encrypt) (eq? (hash-ref request 'input-state #f) 'plaintext))
           (and (eq? action 'decrypt) (eq? (hash-ref request 'input-state #f) 'encrypted-opaque)))
       (hasheq 'operation (hash-ref request 'operation)
               'action action
               'provider (hash-ref provider 'identity)
               'provider-generation (hash-ref provider 'generation)
               'configuration-generation (hash-ref request 'configuration-generation)
               'credential-handle (hash-ref request 'credential-handle)
               'credential-generation (hash-ref request 'credential-generation)
               'resource (hash-ref request 'resource)
               'revision (hash-ref request 'revision)
               'preserve-markers? #t
               'preserve-archive? #t)))

(define (protected-consumer-visible? state consumer)
  (case state
    [(plaintext) #t]
    [(encrypted-opaque) #f]
    [(decrypted-transient) (eq? consumer 'interactive-view)]
    [else #f]))

(define (plaintext-save-allowed? state policy confirmed? explicit?)
  (and explicit? (eq? state 'decrypted-transient)
       (case policy
         [(deny) #f]
         [(confirm) confirmed?]
         [(allow) #t]
         [else #f])))

(define (candidate-included? candidate attachment-policy)
  (and (hash-ref candidate 'selected? #f)
       (or (eq? (hash-ref candidate 'kind #f) 'document)
           (eq? attachment-policy 'all)
           (and (eq? attachment-policy 'referenced)
                (hash-ref candidate 'referenced? #f)))))

(define (stage-synchronization request providers candidates)
  (define provider
    (select-provider (hash-ref request 'provider #f)
                     (hash-ref request 'provider-generation 0)
                     providers 'synchronize))
  (define resources (map (lambda (candidate) (hash-ref candidate 'resource #f)) candidates))
  (define selected
    (sort (filter (lambda (candidate)
                    (candidate-included? candidate (hash-ref request 'attachment-policy #f)))
                  candidates)
          < #:key (lambda (candidate) (hash-ref candidate 'resource))))
  (and provider
       (hash-ref request 'explicit? #f)
       (= (length resources) (length (remove-duplicates resources)))
       (pair? selected)
       (ormap (lambda (candidate) (eq? (hash-ref candidate 'kind) 'document)) selected)
       (for/and ([candidate (in-list selected)])
         (and (exact-positive-integer? (hash-ref candidate 'base-revision #f))
              (>= (hash-ref candidate 'local-revision 0) (hash-ref candidate 'base-revision))
              (bytes? (hash-ref candidate 'base-digest #f))
              (positive? (bytes-length (hash-ref candidate 'base-digest)))
              (bytes? (hash-ref candidate 'local-digest #f))
              (positive? (bytes-length (hash-ref candidate 'local-digest)))))
       (hasheq 'manifest (hash-ref request 'manifest)
               'provider (hash-ref provider 'identity)
               'provider-generation (hash-ref provider 'generation)
               'transport (hash-ref provider 'transport)
               'staging-resource (hash-ref request 'staging-resource)
               'push-generation (hash-ref request 'push-generation)
               'pull-generation (hash-ref request 'pull-generation)
               'entries
               (for/list ([candidate (in-list selected)])
                 (hasheq 'resource (hash-ref candidate 'resource)
                         'kind (hash-ref candidate 'kind)
                         'base-revision (hash-ref candidate 'base-revision)
                         'local-revision (hash-ref candidate 'local-revision)
                         'base-digest (hash-ref candidate 'base-digest)
                         'local-digest (hash-ref candidate 'local-digest)
                         'staging-checksum (hash-ref candidate 'local-digest))))))

(define (classify-entry entry remote)
  (define base (hash-ref entry 'base-digest))
  (define local (hash-ref entry 'local-digest))
  (define pulled (hash-ref remote 'remote-digest))
  (cond
    [(and (equal? base local) (equal? base pulled)) 'unchanged]
    [(equal? base pulled) 'local-only]
    [(equal? base local) 'remote-only]
    [(equal? local pulled) 'converged]
    [else 'conflict]))

(define (reconcile-protected-synchronization staged observations resolutions)
  (define entries (hash-ref staged 'entries))
  (define remote-by-resource
    (for/hasheq ([observation (in-list observations)])
      (values (hash-ref observation 'resource) observation)))
  (define resolution-by-resource
    (for/hasheq ([resolution (in-list resolutions)])
      (values (hash-ref resolution 'resource) resolution)))
  (and (= (length observations) (length entries))
       (= (hash-count remote-by-resource) (length observations))
       (= (hash-count resolution-by-resource) (length resolutions))
       (let ([reconciled
              (for/list ([entry (in-list entries)])
                (define resource (hash-ref entry 'resource))
                (define remote (hash-ref remote-by-resource resource #f))
                (and remote (hash-ref remote 'checksum-valid? #f)
                     (equal? (hash-ref remote 'base-digest) (hash-ref entry 'base-digest))
                     (let* ([change (classify-entry entry remote)]
                            [resolution (hash-ref resolution-by-resource resource #f)]
                            [decision
                             (case change
                               [(unchanged local-only converged) 'keep-local]
                               [(remote-only) 'accept-remote]
                               [(conflict) (if resolution (hash-ref resolution 'decision) 'unresolved)])]
                            [result-revision
                             (case decision
                               [(accept-remote) (hash-ref remote 'remote-revision)]
                               [(manual-merge) (hash-ref resolution 'merged-revision)]
                               [else (hash-ref entry 'local-revision)])]
                            [result-digest
                             (case decision
                               [(accept-remote) (hash-ref remote 'remote-digest)]
                               [(manual-merge) (hash-ref resolution 'merged-digest)]
                               [else (hash-ref entry 'local-digest)])])
                       (hasheq 'resource resource 'change change 'decision decision
                               'result-revision result-revision 'result-digest result-digest))))])
         (and (andmap values reconciled)
              (for/and ([resolution (in-list resolutions)])
                (for/or ([entry (in-list reconciled)])
                  (and (= (hash-ref resolution 'resource) (hash-ref entry 'resource))
                       (eq? (hash-ref entry 'change) 'conflict))))
              (let ([conflicts (count (lambda (entry) (eq? (hash-ref entry 'decision) 'unresolved)) reconciled)]
                    [applicable (count (lambda (entry)
                                         (memq (hash-ref entry 'decision) '(accept-remote manual-merge)))
                                       reconciled)])
                (hasheq 'manifest (hash-ref staged 'manifest)
                        'entries reconciled
                        'changed (count (lambda (entry) (not (eq? (hash-ref entry 'change) 'unchanged))) reconciled)
                        'conflicts conflicts
                        'applicable applicable
                        'state (if (zero? conflicts) 'received 'conflicted)))))))

(define (plan-synchronization-apply reconciliation)
  (and (eq? (hash-ref reconciliation 'state #f) 'received)
       (zero? (hash-ref reconciliation 'conflicts 1))
       (sort
        (for/list ([entry (in-list (hash-ref reconciliation 'entries))]
                   #:when (memq (hash-ref entry 'decision) '(accept-remote manual-merge)))
          (hash-ref entry 'resource))
        <)))
