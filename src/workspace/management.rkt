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
         "../project/persistence.rkt"
         "../project/records.rkt"
         "../storage/record-codec.rkt"
         "persistence.rkt"
         "records.rkt")

(provide
 (struct-out odra-workspace-proposal)
 (struct-out odra-workspace-publication)
 (struct-out odra-workspace-member-resolution)
 (struct-out odra-workspace-resolution)
 (struct-out odra-workspace-failure)
 (contract-out
  [workspace-create-compose
   (-> path-string? string? (listof path-string?)
       (or/c odra-workspace-proposal? odra-workspace-failure?))]
  [workspace-update-compose
   (-> path-string? string? exact-positive-integer? string? (listof path-string?)
       (or/c odra-workspace-proposal? odra-workspace-failure?))]
  [workspace-add-project-compose
   (-> path-string? string? exact-positive-integer? path-string?
       (or/c odra-workspace-proposal? odra-workspace-failure?))]
  [workspace-remove-project-compose
   (-> path-string? string? exact-positive-integer? path-string?
       (or/c odra-workspace-proposal? odra-workspace-failure?))]
  [workspace-move-project-compose
   (-> path-string? string? exact-positive-integer? path-string? (or/c 'earlier 'later)
       (or/c odra-workspace-proposal? odra-workspace-failure?))]
  [workspace-unregister
   (-> path-string? string? exact-positive-integer?
       (or/c odra-record-catalog? odra-workspace-failure?))]
  [workspace-prune-project-references
   (-> path-string? path-string?
       (or/c odra-record-catalog? odra-workspace-failure?))]
  [workspace-publish
   (-> path-string? odra-workspace-proposal?
       (or/c odra-workspace-publication? odra-workspace-failure?))]
  [workspace-resolve
   (-> odra-workspace-record? odra-workspace-resolution?)]
  [workspace-inspect
   (-> path-string? string?
       (or/c odra-workspace-resolution? odra-workspace-failure?))]
  [workspace-list (-> path-string? odra-record-catalog?)]))

(define identity-attempts 16)
(define maximum-workspaces 256)
(define allowed-publication-states '(published reconciled))
(define allowed-member-states '(ready missing unavailable conflict stale))
(define allowed-failure-codes
  '(invalid-name invalid-project-set identity-limit duplicate-name
                 duplicate-project missing-workspace invalid-workspace
                 stale-workspace member-unresolved persistence-failed
                 publication-unresolved))
(define allowed-publications '(none complete uncertain))

(define current-workspace-identity
  (make-parameter
   (lambda () (bytes->hex-string (crypto-random-bytes 16)))))

(struct odra-workspace-proposal (record) #:transparent
  #:guard
  (lambda (record _)
    (unless (odra-workspace-record? record)
      (raise-arguments-error 'odra-workspace-proposal
                             "invalid copied Workspace proposal"))
    record))

(struct odra-workspace-publication (state record) #:transparent
  #:guard
  (lambda (state record _)
    (unless (and (memq state allowed-publication-states)
                 (odra-workspace-record? record))
      (raise-arguments-error 'odra-workspace-publication
                             "invalid Workspace publication result"))
    (values state record)))

(struct odra-workspace-member-resolution
  (index state reference project diagnostic)
  #:transparent
  #:guard
  (lambda (index state reference project diagnostic _)
    (unless (and (exact-nonnegative-integer? index)
                 (memq state allowed-member-states)
                 (odra-workspace-project-reference? reference)
                 (or (not project) (odra-local-project-record? project))
                 (string? diagnostic)
                 (<= (bytes-length (string->bytes/utf-8 diagnostic))
                     maximum-record-diagnostic-bytes)
                 (if (eq? state 'ready) project (not project)))
      (raise-arguments-error 'odra-workspace-member-resolution
                             "invalid copied Workspace member resolution"))
    (values index state reference project (record-copied-text diagnostic))))

(struct odra-workspace-resolution (record members ready?) #:transparent
  #:guard
  (lambda (record members ready? _)
    (unless (and (odra-workspace-record? record)
                 (list? members)
                 (= (length members)
                    (length (odra-workspace-record-projects record)))
                 (andmap odra-workspace-member-resolution? members)
                 (boolean? ready?)
                 (eq? ready?
                      (andmap
                       (lambda (member)
                         (eq? (odra-workspace-member-resolution-state member)
                              'ready))
                       members)))
      (raise-arguments-error 'odra-workspace-resolution
                             "invalid copied Workspace resolution"))
    (values record (for/list ([member (in-list members)]) member) ready?)))

(struct odra-workspace-failure (code message publication) #:transparent
  #:guard
  (lambda (code message publication _)
    (unless (and (memq code allowed-failure-codes)
                 (string? message)
                 (positive? (string-length message))
                 (<= (bytes-length (string->bytes/utf-8 message))
                     maximum-record-diagnostic-bytes)
                 (memq publication allowed-publications))
      (raise-arguments-error 'odra-workspace-failure
                             "invalid bounded Workspace failure"))
    (values code (record-copied-text message) publication)))

;; workspace-create-compose snapshots one ordered set of exact local Projects.
(define (workspace-create-compose configuration-root name roots)
  (cond
    [(not (record-name? name))
     (workspace-failure 'invalid-name "Workspace name must be bounded, nonempty UTF-8")]
    [else
     (define catalog (load-workspace-catalog configuration-root))
     (cond
       [(findf (lambda (record)
                 (string=? name (odra-workspace-record-name record)))
               (odra-record-catalog-records catalog))
        (workspace-failure 'duplicate-name "A Workspace already uses this display name")]
       [else
        (define references (resolve-project-roots roots))
        (cond
          [(odra-workspace-failure? references) references]
          [else
           (define id (fresh-workspace-identity configuration-root catalog))
           (if id
               (odra-workspace-proposal
                (workspace-record
                 #:format-version current-workspace-format-version
                 #:id id
                 #:generation 1
                 #:name name
                 #:projects references))
               (workspace-failure
                'identity-limit
                "Could not allocate a collision-free Workspace identity"))])])]))

;; workspace-update-compose prepares one exact next-generation replacement.
(define (workspace-update-compose configuration-root id expected-generation name roots)
  (cond
    [(not (record-identity? id))
     (workspace-failure 'invalid-workspace "Workspace identity is invalid")]
    [else
     (workspace-update-compose-valid
      configuration-root id expected-generation name roots)]))

(define (workspace-update-compose-valid configuration-root id expected-generation name roots)
  (define current (load-workspace configuration-root id))
  (cond
    [(not current)
     (workspace-failure 'missing-workspace "Workspace identity is not available")]
    [(not (= expected-generation (odra-workspace-record-generation current)))
     (workspace-failure 'stale-workspace "Workspace generation changed before update")]
    [(not (record-name? name))
     (workspace-failure 'invalid-name "Workspace name must be bounded, nonempty UTF-8")]
    [else
     (define catalog (load-workspace-catalog configuration-root))
     (define duplicate
       (findf
        (lambda (record)
          (and (not (string=? id (odra-workspace-record-id record)))
               (string=? name (odra-workspace-record-name record))))
        (odra-record-catalog-records catalog)))
     (cond
       [duplicate
        (workspace-failure 'duplicate-name "A Workspace already uses this display name")]
       [else
        (define references (resolve-project-roots roots))
        (if (odra-workspace-failure? references)
            references
            (odra-workspace-proposal
             (workspace-record
              #:format-version current-workspace-format-version
              #:id id
              #:generation (add1 expected-generation)
              #:name name
              #:projects references)))])]))

;; workspace-add-project-compose appends one exact local Project to a Workspace.
(define (workspace-add-project-compose configuration-root id expected-generation root)
  (workspace-member-compose configuration-root id expected-generation root 'add))

;; workspace-remove-project-compose removes one exact local Project from a Workspace.
(define (workspace-remove-project-compose configuration-root id expected-generation root)
  (workspace-member-compose configuration-root id expected-generation root 'remove))

;; workspace-move-project-compose reorders one exact member without changing ownership.
(define (workspace-move-project-compose configuration-root id expected-generation root direction)
  (define root-text (path->string (path->complete-path root)))
  (define inspected (workspace-inspect configuration-root id))
  (cond
    [(odra-workspace-failure? inspected) inspected]
    [else
     (define record (odra-workspace-resolution-record inspected))
     (cond
       [(not (= expected-generation (odra-workspace-record-generation record)))
        (workspace-failure 'stale-workspace "Workspace generation changed before reorder")]
       [else
        (define roots
          (map odra-workspace-project-reference-root
               (odra-workspace-record-projects record)))
        (define index (index-of roots root-text string=?))
        (cond
          [(not index)
           (workspace-failure 'invalid-project-set "Project is not a Workspace member")]
          [else
           (define target (if (eq? direction 'earlier) (sub1 index) (add1 index)))
           (if (or (< target 0) (>= target (length roots)))
               (odra-workspace-proposal record)
               (workspace-update-compose
                configuration-root id expected-generation
                (odra-workspace-record-name record)
                (list-set (list-set roots index (list-ref roots target))
                          target root-text)))])])]))

(define (workspace-member-compose configuration-root id expected-generation root operation)
  (define root-text (path->string (path->complete-path root)))
  (define inspected (workspace-inspect configuration-root id))
  (cond
    [(odra-workspace-failure? inspected) inspected]
    [else
     (define record (odra-workspace-resolution-record inspected))
     (define existing-roots
       (map odra-workspace-project-reference-root
            (odra-workspace-record-projects record)))
     (define next-roots
       (if (eq? operation 'add)
           (append existing-roots (list root-text))
           (filter (lambda (candidate) (not (string=? candidate root-text)))
                   existing-roots)))
     (workspace-update-compose
      configuration-root id expected-generation
      (odra-workspace-record-name record)
      next-roots)]))

;; workspace-unregister removes one exact durable Workspace from the global catalog.
(define (workspace-unregister configuration-root id expected-generation)
  (define current (load-workspace configuration-root id))
  (cond
    [(not current)
     (workspace-failure 'missing-workspace "Workspace identity is not available")]
    [(not (= expected-generation (odra-workspace-record-generation current)))
     (workspace-failure 'stale-workspace "Workspace generation changed before removal")]
    [else
     (with-handlers ([exn:fail?
                      (lambda (failure)
                        (workspace-failure 'persistence-failed
                                           (exn-message failure)
                                           'uncertain))])
       (delete-file (workspace-record-path configuration-root id))
       (workspace-list configuration-root))]))

;; workspace-prune-project-references removes one Project root from every Workspace.
(define (workspace-prune-project-references configuration-root project-root)
  (define root-text (path->string (path->complete-path project-root)))
  (let loop ([records (odra-record-catalog-records
                       (workspace-list configuration-root))])
    (cond
      [(null? records) (workspace-list configuration-root)]
      [else
       (define record (car records))
       (define roots
         (map odra-workspace-project-reference-root
              (odra-workspace-record-projects record)))
       (cond
         [(not (member root-text roots string=?))
          (loop (cdr records))]
         [(= (length roots) 1)
          (define removed
            (workspace-unregister
             configuration-root
             (odra-workspace-record-id record)
             (odra-workspace-record-generation record)))
          (if (odra-workspace-failure? removed)
              removed
              (loop (cdr records)))]
         [else
          (define composed
            (workspace-remove-project-compose
             configuration-root
             (odra-workspace-record-id record)
             (odra-workspace-record-generation record)
             root-text))
          (cond
            [(odra-workspace-failure? composed) composed]
            [else
             (define published (workspace-publish configuration-root composed))
             (if (odra-workspace-failure? published)
                 published
                 (loop (cdr records)))])])])))

;; workspace-publish atomically publishes one complete current proposal.
(define (workspace-publish configuration-root proposal)
  (define record (odra-workspace-proposal-record proposal))
  (define resolution (workspace-resolve record))
  (cond
    [(not (odra-workspace-resolution-ready? resolution))
     (workspace-failure
      'member-unresolved "Workspace members changed before publication")]
    [else
     (define target
       (workspace-record-path configuration-root (odra-workspace-record-id record)))
     (define existing (load-workspace configuration-root (odra-workspace-record-id record)))
     (cond
       [(equal? existing record)
        (odra-workspace-publication 'reconciled record)]
       [(and (not existing) (or (file-exists? target) (link-exists? target)))
        (workspace-failure 'invalid-workspace "Existing Workspace metadata is invalid")]
       [else
        (define persisted (workspace-record-persist configuration-root record))
        (define reloaded
          (load-workspace configuration-root (odra-workspace-record-id record)))
        (cond
          [(and (equal? reloaded record)
                (odra-record-publication? persisted))
           (odra-workspace-publication 'published record)]
          [(odra-record-publication-failure? persisted)
           (workspace-failure
            (if (eq? (odra-record-publication-failure-publication persisted)
                     'not-published)
                'persistence-failed
                'publication-unresolved)
            (odra-record-publication-failure-message persisted)
            (if (eq? (odra-record-publication-failure-publication persisted)
                     'not-published)
                'none
                'uncertain))]
          [else
           (workspace-failure
            'publication-unresolved
            "Workspace publication could not be reconciled"
            'uncertain)])])]))

;; workspace-resolve preserves member order and reports every invalid reference.
(define (workspace-resolve record)
  (define members
    (for/list ([reference (in-list (odra-workspace-record-projects record))]
               [index (in-naturals)])
      (resolve-member index reference)))
  (odra-workspace-resolution
   record
   members
   (andmap
    (lambda (member)
      (eq? (odra-workspace-member-resolution-state member) 'ready))
    members)))

;; workspace-inspect loads and resolves one exact durable Workspace identity.
(define (workspace-inspect configuration-root id)
  (cond
    [(not (record-identity? id))
     (workspace-failure 'invalid-workspace "Workspace identity is invalid")]
    [else
     (define target (workspace-record-path configuration-root id))
     (define record (load-workspace configuration-root id))
     (cond
       [record (workspace-resolve record)]
       [(or (file-exists? target) (link-exists? target))
        (workspace-failure 'invalid-workspace "Workspace metadata is invalid")]
       [else
        (workspace-failure 'missing-workspace "Workspace identity is not available")])]))

;; workspace-list returns the deterministic bounded Workspace catalog.
(define (workspace-list configuration-root)
  (load-workspace-catalog configuration-root))

(define (resolve-project-roots roots)
  (cond
    [(or (< (length roots) 1) (> (length roots) maximum-workspace-projects))
     (workspace-failure
      'invalid-project-set "Workspace composition requires 1 to 256 Projects")]
    [else
     (define resolved
       (for/list ([root (in-list roots)])
         (resolve-project-root root)))
     (cond
       [(findf odra-workspace-failure? resolved) => values]
       [else
        (define ids (map odra-workspace-project-reference-id resolved))
        (if (= (length ids) (length (remove-duplicates ids)))
            resolved
            (workspace-failure
             'duplicate-project "Workspace composition contains a duplicate Project"))])]))

(define (resolve-project-root root)
  (define normalized (normalized-project-root root))
  (cond
    [(not normalized)
     (workspace-failure 'invalid-project-set "Workspace member Dir is unavailable")]
    [else
     (define record (load-local-project normalized))
     (cond
       [(and record
             (string=? (path->string normalized)
                       (odra-local-project-record-root record)))
        (workspace-project-reference
         #:id (odra-local-project-record-id record)
         #:expected-project-generation
         (odra-local-project-record-generation record)
         #:root (odra-local-project-record-root record))]
       [else
        (workspace-failure
         'invalid-project-set "Workspace members must be exact valid Projects")])]))

(define (resolve-member index reference)
  (define root (string->path (odra-workspace-project-reference-root reference)))
  (cond
    [(not (directory-exists? root))
     (member-resolution index 'unavailable reference #f "Project root is unavailable")]
    [else
     (define target (local-project-record-path root))
     (define local (load-local-project root))
     (cond
       [(and (not local) (not (or (file-exists? target) (link-exists? target))))
        (member-resolution index 'missing reference #f "Local Project record is missing")]
       [(not local)
        (member-resolution index 'conflict reference #f "Local Project metadata is invalid")]
       [(or (not (string=? (odra-workspace-project-reference-id reference)
                           (odra-local-project-record-id local)))
            (not (string=? (odra-workspace-project-reference-root reference)
                           (odra-local-project-record-root local))))
        (member-resolution index 'conflict reference #f "Project identity or root changed")]
       [(not (= (odra-workspace-project-reference-expected-project-generation reference)
                (odra-local-project-record-generation local)))
        (member-resolution index 'stale reference #f "Project generation changed")]
       [else
        (member-resolution index 'ready reference local "")])]))

(define (member-resolution index state reference project diagnostic)
  (odra-workspace-member-resolution index state reference project diagnostic))

(define (normalized-project-root root)
  (with-handlers ([exn:fail:filesystem? (lambda (_) #f)])
    (define complete (simplify-path (path->complete-path root) #t))
    (and (absolute-path? complete) (directory-exists? complete) complete)))

(define (load-local-project root)
  (define loaded
    (local-project-record-module-load (local-project-record-path root)))
  (and (odra-local-project-record? loaded) loaded))

(define (load-workspace configuration-root id)
  (define loaded
    (workspace-record-module-load (workspace-record-path configuration-root id)))
  (and (odra-workspace-record? loaded) loaded))

(define (fresh-workspace-identity configuration-root catalog)
  (define existing
    (for/hash ([record (in-list (odra-record-catalog-records catalog))])
      (values (odra-workspace-record-id record) #t)))
  (for/or ([_attempt (in-range identity-attempts)])
    (define id ((current-workspace-identity)))
    (and (record-identity? id)
         (not (hash-ref existing id #f))
         (not (or (file-exists? (workspace-record-path configuration-root id))
                  (link-exists? (workspace-record-path configuration-root id))))
         id)))

(define (load-workspace-catalog configuration-root)
  (workspace-catalog-load
   configuration-root
   #:maximum-entries maximum-workspaces))

(define (workspace-failure code message [publication 'none])
  (odra-workspace-failure code message publication))

(module+ test-support
  (provide current-workspace-identity))
