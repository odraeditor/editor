#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require file/sha1
         racket/contract/base
         racket/file
         racket/list
         racket/path
         racket/random
         "../storage/record-codec.rkt"
         "persistence.rkt"
         "records.rkt")

(provide
 (struct-out odra-project-promotion-proposal)
 (struct-out odra-project-promotion-result)
 (struct-out odra-project-promotion-failure)
 (struct-out odra-project-dir-inspection)
 (contract-out
  [project-promotion-compose
   (-> path-string? path-string? string?
       (or/c odra-project-promotion-proposal?
             odra-project-promotion-failure?))]
  [project-promotion-publish
   (-> path-string? odra-project-promotion-proposal?
       (or/c odra-project-promotion-result?
             odra-project-promotion-failure?))]
  [project-discovery-reconcile
   (-> path-string? odra-local-project-record?
       (or/c odra-project-promotion-result?
             odra-project-promotion-failure?))]
  [project-dir-inspect (-> path-string? odra-project-dir-inspection?)]
  [project-discovery-list (-> path-string? odra-record-catalog?)]))

(define identity-attempts 16)
(define allowed-result-states '(published reconciled))
(define allowed-failure-codes
  '(invalid-dir invalid-name identity-limit conflicting-local-metadata
                discovery-conflict local-publication-failed
                discovery-publication-failed publication-unresolved))
(define allowed-publication-states '(none local complete uncertain))
(define allowed-inspection-states '(ordinary project conflict unavailable))

(define current-project-promotion-identity
  (make-parameter
   (lambda () (bytes->hex-string (crypto-random-bytes 16)))))

(struct odra-project-promotion-proposal (local-project discovery-reference)
  #:transparent
  #:guard
  (lambda (local-project discovery-reference _)
    (unless (and (odra-local-project-record? local-project)
                 (odra-project-discovery-record? discovery-reference)
                 (= (odra-local-project-record-generation local-project) 1)
                 (eq? (odra-local-project-record-trust local-project) 'untrusted)
                 (local-discovery-match? local-project discovery-reference))
      (raise-arguments-error 'odra-project-promotion-proposal
                             "invalid copied Project promotion proposal"))
    (values local-project discovery-reference)))

(struct odra-project-promotion-result (state local-project discovery-reference)
  #:transparent
  #:guard
  (lambda (state local-project discovery-reference _)
    (unless (and (memq state allowed-result-states)
                 (odra-local-project-record? local-project)
                 (odra-project-discovery-record? discovery-reference)
                 (local-discovery-match? local-project discovery-reference))
      (raise-arguments-error 'odra-project-promotion-result
                             "invalid Project promotion result"))
    (values state local-project discovery-reference)))

(struct odra-project-promotion-failure (code message publication)
  #:transparent
  #:guard
  (lambda (code message publication _)
    (unless (and (memq code allowed-failure-codes)
                 (string? message)
                 (positive? (string-length message))
                 (<= (bytes-length (string->bytes/utf-8 message))
                     maximum-record-diagnostic-bytes)
                 (memq publication allowed-publication-states))
      (raise-arguments-error 'odra-project-promotion-failure
                             "invalid bounded Project promotion failure"))
    (values code (record-copied-text message) publication)))

(struct odra-project-dir-inspection (state root project diagnostic)
  #:transparent
  #:guard
  (lambda (state root project diagnostic _)
    (unless (and (memq state allowed-inspection-states)
                 (string? root)
                 (or (string=? root "") (record-path? root))
                 (or (not project) (odra-local-project-record? project))
                 (string? diagnostic)
                 (<= (bytes-length (string->bytes/utf-8 diagnostic))
                     maximum-record-diagnostic-bytes)
                 (if (eq? state 'project) project (not project)))
      (raise-arguments-error 'odra-project-dir-inspection
                             "invalid copied Dir inspection"))
    (values state
            (record-copied-text root)
            project
            (record-copied-text diagnostic))))

;; project-promotion-compose prepares one copied initial identity for an ordinary Dir.
(define (project-promotion-compose configuration-root dir-root name)
  (define root (normalized-root dir-root))
  (cond
    [(not root)
     (promotion-failure 'invalid-dir
                        "Project promotion requires an existing absolute Dir")]
    [(not (record-name? name))
     (promotion-failure 'invalid-name
                        "Project name must be bounded, nonempty UTF-8")]
    [else
     (define local-state (local-project-state root))
     (cond
       [(not (eq? local-state 'absent))
        (promotion-failure
         'conflicting-local-metadata
         "Project promotion requires a Dir without existing .odra metadata")]
       [else
        (define catalog (project-discovery-catalog-load configuration-root))
        (define root-text (path->string root))
        (cond
          [(findf (lambda (record)
                    (string=? root-text
                              (odra-project-discovery-record-root record)))
                  (odra-record-catalog-records catalog))
           (promotion-failure
            'discovery-conflict
            "A Project discovery reference already uses this Dir")]
          [else
           (define id (fresh-project-identity configuration-root catalog))
           (if id
               (promotion-proposal id name root-text)
               (promotion-failure
                'identity-limit
                "Could not allocate a collision-free Project identity"))])])]))

;; project-promotion-publish publishes local identity first and then its global reference.
(define (project-promotion-publish configuration-root proposal)
  (define local (odra-project-promotion-proposal-local-project proposal))
  (define discovery
    (odra-project-promotion-proposal-discovery-reference proposal))
  (define root (string->path (odra-local-project-record-root local)))
  (define existing-local (load-local-project root))
  (cond
    [(and existing-local (not (equal? existing-local local)))
     (promotion-failure
      'conflicting-local-metadata
      "Existing local Project metadata does not match the promotion proposal")]
    [(and (not existing-local) (not (eq? (local-project-state root) 'absent)))
     (promotion-failure
      'conflicting-local-metadata
      "Existing .odra metadata blocks Project promotion")]
    [else
     (define local-was-present? (and existing-local #t))
     (define local-result
       (if local-was-present?
           local
           (publish-local-project root local)))
     (cond
       [(odra-project-promotion-failure? local-result) local-result]
       [else
        (define discovery-result
          (project-discovery-reconcile configuration-root local))
        (cond
          [(odra-project-promotion-failure? discovery-result) discovery-result]
          [else
           (odra-project-promotion-result
            (if local-was-present? 'reconciled 'published)
            local
            discovery)])])]))

;; project-discovery-reconcile makes a rebuildable reference match local authority.
(define (project-discovery-reconcile configuration-root local)
  (define discovery
    (project-discovery-record
     #:format-version current-project-discovery-format-version
     #:id (odra-local-project-record-id local)
     #:expected-project-generation
     (odra-local-project-record-generation local)
     #:root (odra-local-project-record-root local)))
  (define target
    (project-discovery-record-path
     configuration-root
     (odra-project-discovery-record-id discovery)))
  (define existing (load-discovery target))
  (cond
    [(equal? existing discovery)
     (odra-project-promotion-result 'reconciled local discovery)]
    [(and existing
          (or (not (string=?
                    (odra-project-discovery-record-id existing)
                    (odra-project-discovery-record-id discovery)))
              (>=
               (odra-project-discovery-record-expected-project-generation existing)
               (odra-project-discovery-record-expected-project-generation discovery))))
     (promotion-failure
      'discovery-conflict
      "Existing Project discovery state cannot be replaced by this generation"
      'local)]
    [(and (not existing) (or (file-exists? target) (link-exists? target)))
     (promotion-failure
      'discovery-conflict
      "Existing Project discovery metadata is invalid"
      'local)]
    [else
     (define persisted
       (project-discovery-record-persist configuration-root discovery))
     (define reloaded (load-discovery target))
     (cond
       [(and (equal? reloaded discovery)
             (odra-record-publication? persisted))
        (odra-project-promotion-result 'published local discovery)]
       [(odra-record-publication-failure? persisted)
        (promotion-failure
         (if (eq? (odra-record-publication-failure-publication persisted)
                  'not-published)
             'discovery-publication-failed
             'publication-unresolved)
         (odra-record-publication-failure-message persisted)
         (if (eq? (odra-record-publication-failure-publication persisted)
                  'not-published)
             'local
             'uncertain))]
       [else
        (promotion-failure
         'publication-unresolved
         "Project discovery publication could not be reconciled"
         'uncertain)])]))

;; project-dir-inspect classifies local authority without consulting global discovery.
(define (project-dir-inspect dir-root)
  (define root (normalized-root dir-root))
  (cond
    [(not root)
     (odra-project-dir-inspection
      'unavailable "" #f "Dir is invalid or unavailable")]
    [else
     (define root-text (path->string root))
     (define state (local-project-state root))
     (define local (load-local-project root))
     (cond
       [(eq? state 'absent)
        (odra-project-dir-inspection 'ordinary root-text #f "")]
       [(and local (string=? root-text (odra-local-project-record-root local)))
        (odra-project-dir-inspection 'project root-text local "")]
       [else
        (odra-project-dir-inspection
         'conflict root-text #f "Local .odra metadata is not a valid Project")])]))

;; project-discovery-list returns the bounded rebuildable global reference catalog.
(define (project-discovery-list configuration-root)
  (project-discovery-catalog-load configuration-root))

(define (promotion-proposal id name root)
  (define local
    (local-project-record
     #:format-version current-local-project-format-version
     #:id id
     #:generation 1
     #:name name
     #:root root
     #:trust 'untrusted))
  (odra-project-promotion-proposal
   local
   (project-discovery-record
    #:format-version current-project-discovery-format-version
    #:id id
    #:expected-project-generation 1
    #:root root)))

(define (publish-local-project root local)
  (define metadata-root (build-path root ".odra"))
  (define metadata-existed? (directory-exists? metadata-root))
  (define persisted (local-project-record-persist root local))
  (define reloaded (load-local-project root))
  (cond
    [(and (equal? reloaded local)
          (odra-record-publication? persisted))
     local]
    [else
     (when (and (not metadata-existed?)
                (directory-exists? metadata-root)
                (null? (directory-list metadata-root)))
       (delete-directory metadata-root))
     (if (odra-record-publication-failure? persisted)
         (promotion-failure
          (if (eq? (odra-record-publication-failure-publication persisted)
                   'not-published)
              'local-publication-failed
              'publication-unresolved)
          (odra-record-publication-failure-message persisted)
          (if (eq? (odra-record-publication-failure-publication persisted)
                   'not-published)
              'none
              'uncertain))
         (promotion-failure
          'publication-unresolved
          "Local Project publication could not be reconciled"
          'uncertain))]))

(define (normalized-root value)
  (with-handlers ([exn:fail:filesystem? (lambda (_) #f)]
                  [exn:fail:contract? (lambda (_) #f)])
    (define root (simplify-path (path->complete-path value) #f))
    (and (absolute-path? root)
         (directory-exists? root)
         (not (link-exists? root))
         root)))

(define (local-project-state root)
  (define metadata-root (build-path root ".odra"))
  (define target (local-project-record-path root))
  (cond
    [(or (file-exists? target) (link-exists? target)) 'record]
    [(or (directory-exists? metadata-root) (link-exists? metadata-root)) 'metadata]
    [else 'absent]))

(define (load-local-project root)
  (define target (local-project-record-path root))
  (and (file-exists? target)
       (not (link-exists? target))
       (let ([loaded (local-project-record-module-load target)])
         (and (odra-local-project-record? loaded) loaded))))

(define (load-discovery target)
  (and (file-exists? target)
       (not (link-exists? target))
       (let ([loaded (project-discovery-record-module-load target)])
         (and (odra-project-discovery-record? loaded) loaded))))

(define (local-discovery-match? local discovery)
  (and (string=? (odra-local-project-record-id local)
                 (odra-project-discovery-record-id discovery))
       (string=? (odra-local-project-record-root local)
                 (odra-project-discovery-record-root discovery))
       (= (odra-local-project-record-generation local)
          (odra-project-discovery-record-expected-project-generation discovery))))

(define (fresh-project-identity configuration-root catalog)
  (let loop ([attempt 0])
    (cond
      [(= attempt identity-attempts) #f]
      [else
       (define candidate ((current-project-promotion-identity)))
       (if (and (record-identity? candidate)
                (not
                 (or (file-exists?
                      (project-discovery-record-path configuration-root candidate))
                     (link-exists?
                      (project-discovery-record-path configuration-root candidate))))
                (not
                 (findf
                  (lambda (record)
                    (string=?
                     candidate
                     (odra-project-discovery-record-id record)))
                  (odra-record-catalog-records catalog))))
           (record-copied-text candidate)
           (loop (add1 attempt)))])))

(define (promotion-failure code message [publication 'none])
  (odra-project-promotion-failure code message publication))

(module+ test-support
  (provide current-project-promotion-identity))
