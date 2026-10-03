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
         racket/string
         "../project/candidate-usage.rkt"
         "../project/persistence.rkt"
         "../project/records.rkt"
         "../storage/record-codec.rkt"
         "../workspace/persistence.rkt"
         "../workspace/records.rkt"
         "legacy-inventory.rkt"
         "persistence.rkt"
         "records.rkt")

(provide
 (struct-out odra-legacy-migration-project)
 (struct-out odra-legacy-migration-workspace)
 (struct-out odra-legacy-migration-state)
 (struct-out odra-legacy-migration-source)
 (struct-out odra-legacy-migration-rejection)
 (struct-out odra-legacy-migration-plan)
 (contract-out
  [legacy-migration-plan-compose
   (-> path-string? odra-legacy-migration-inventory?
       odra-legacy-migration-plan?)]))

(define allowed-source-states '(ready retry already-published rejected))
(define allowed-rejection-codes
  '(invalid-source unavailable-root conflicting-root conflicting-project
                   conflicting-workspace invalid-journal inventory-rejection))

(struct odra-legacy-migration-project (source-ids local discovery)
  #:transparent
  #:guard
  (lambda (source-ids local discovery _)
    (unless (and (list? source-ids)
                 (pair? source-ids)
                 (andmap record-identity? source-ids)
                 (= (length source-ids) (length (remove-duplicates source-ids)))
                 (odra-local-project-record? local)
                 (odra-project-discovery-record? discovery)
                 (string=? (odra-local-project-record-id local)
                           (odra-project-discovery-record-id discovery))
                 (string=? (odra-local-project-record-root local)
                           (odra-project-discovery-record-root discovery)))
      (raise-arguments-error 'odra-legacy-migration-project
                             "invalid migration Project target"))
    (values (map record-copied-text source-ids) local discovery)))

(struct odra-legacy-migration-workspace (source-id record)
  #:transparent
  #:guard
  (lambda (source-id record _)
    (unless (and (record-identity? source-id)
                 (odra-workspace-record? record))
      (raise-arguments-error 'odra-legacy-migration-workspace
                             "invalid migration Workspace target"))
    (values (record-copied-text source-id) record)))

(struct odra-legacy-migration-state (source-id source-path record)
  #:transparent
  #:guard
  (lambda (source-id source-path record _)
    (unless (and (record-identity? source-id)
                 (record-path? source-path)
                 (odra-candidate-usage-record? record))
      (raise-arguments-error 'odra-legacy-migration-state
                             "invalid migration candidate state target"))
    (values (record-copied-text source-id)
            (record-copied-text source-path)
            record)))

(struct odra-legacy-migration-source
  (source-id source-path state target-id diagnostic)
  #:transparent
  #:guard
  (lambda (source-id source-path state target-id diagnostic _)
    (unless (and (record-identity? source-id)
                 (record-path? source-path)
                 (memq state allowed-source-states)
                 (record-identity? target-id)
                 (string? diagnostic)
                 (<= (bytes-length (string->bytes/utf-8 diagnostic))
                     maximum-record-diagnostic-bytes))
      (raise-arguments-error 'odra-legacy-migration-source
                             "invalid migration source result"))
    (values (record-copied-text source-id)
            (record-copied-text source-path)
            state
            (record-copied-text target-id)
            (record-copied-text diagnostic))))

(struct odra-legacy-migration-rejection (source-id source-path code message)
  #:transparent
  #:guard
  (lambda (source-id source-path code message _)
    (unless (and (string? source-id)
                 (or (string=? source-id "") (record-identity? source-id))
                 (record-path? source-path)
                 (memq code allowed-rejection-codes)
                 (string? message)
                 (positive? (string-length message))
                 (<= (bytes-length (string->bytes/utf-8 message))
                     maximum-record-diagnostic-bytes))
      (raise-arguments-error 'odra-legacy-migration-rejection
                             "invalid migration rejection"))
    (values (record-copied-text source-id)
            (record-copied-text source-path)
            code
            (record-copied-text message))))

(struct odra-legacy-migration-plan
  (projects workspaces states sources rejections journal-generation)
  #:transparent
  #:guard
  (lambda (projects workspaces states sources rejections journal-generation _)
    (unless (and (list? projects)
                 (andmap odra-legacy-migration-project? projects)
                 (list? workspaces)
                 (andmap odra-legacy-migration-workspace? workspaces)
                 (list? states)
                 (andmap odra-legacy-migration-state? states)
                 (list? sources)
                 (andmap odra-legacy-migration-source? sources)
                 (list? rejections)
                 (andmap odra-legacy-migration-rejection? rejections)
                 (record-u64? journal-generation))
      (raise-arguments-error 'odra-legacy-migration-plan
                             "invalid bounded migration plan"))
    (values projects workspaces states sources rejections journal-generation)))

(struct prepared-source (proposal roots issue) #:transparent)

;; legacy-migration-plan-compose produces a deterministic, read-only target plan.
(define (legacy-migration-plan-compose configuration-root inventory)
  (define root (path->complete-path configuration-root))
  (define-values (journal journal-rejection) (load-journal root))
  (define journal-generation
    (if journal (add1 (odra-migration-journal-record-generation journal)) 1))
  (define journal-by-source
    (if journal
        (for/hash ([entry (in-list (odra-migration-journal-record-entries journal))])
          (values (odra-migration-entry-source-id entry) entry))
        (hash)))
  (define prepared
    (sort
     (for/list ([proposal
                 (in-list (odra-legacy-migration-inventory-projects inventory))])
       (prepare-source proposal))
     string<?
     #:key (lambda (source)
             (odra-legacy-project-proposal-source
              (prepared-source-proposal source)))))
  (define single-root-owners (collect-single-root-owners prepared))
  (define root-sources (collect-root-sources prepared))
  (define discovery-catalog (project-discovery-catalog-load root))
  (define discovery-by-id
    (for/hash ([record (in-list (odra-record-catalog-records discovery-catalog))])
      (values (odra-project-discovery-record-id record) record)))
  (define discovery-by-root
    (for/hash ([record (in-list (odra-record-catalog-records discovery-catalog))])
      (values (odra-project-discovery-record-root record) record)))
  (define root-targets (make-hash))
  (define root-issues (make-hash))
  (for ([root-text (in-list (sort (hash-keys root-sources) string<?))])
    (define owners (hash-ref single-root-owners root-text '()))
    (cond
      [(> (length owners) 1)
       (hash-set! root-issues root-text
                  "Several legacy single-dir Projects claim this root")]
      [else
       (define target
         (plan-root-target root-text owners (hash-ref root-sources root-text)
                           discovery-by-id discovery-by-root))
       (if (odra-legacy-migration-rejection? target)
           (hash-set! root-issues root-text
                      (odra-legacy-migration-rejection-message target))
           (hash-set! root-targets root-text target))]))
  (define workspace-catalog (workspace-catalog-load root))
  (define workspace-by-id
    (for/hash ([record (in-list (odra-record-catalog-records workspace-catalog))])
      (values (odra-workspace-record-id record) record)))
  (define source-results '())
  (define source-rejections '())
  (define workspace-targets '())
  (define accepted-source-ids (make-hash))
  (for ([source (in-list prepared)])
    (define proposal (prepared-source-proposal source))
    (define source-id (odra-legacy-project-proposal-id proposal))
    (define source-path (odra-legacy-project-proposal-source proposal))
    (define roots (prepared-source-roots source))
    (define issue
      (or (prepared-source-issue source)
          (for/first ([root-text (in-list roots)]
                      #:when (hash-has-key? root-issues root-text))
            (hash-ref root-issues root-text))))
    (cond
      [issue
       (set! source-results
             (cons (odra-legacy-migration-source
                    source-id source-path 'rejected source-id issue)
                   source-results))
       (set! source-rejections
             (cons (odra-legacy-migration-rejection
                    source-id source-path
                    (if (prepared-source-issue source)
                        'unavailable-root
                        'conflicting-root)
                    issue)
                   source-rejections))]
      [else
       (define projects
         (for/list ([root-text (in-list roots)])
           (hash-ref root-targets root-text)))
       (define target-id
         (if (= (length projects) 1)
             (odra-local-project-record-id
              (odra-legacy-migration-project-local (car projects)))
             source-id))
       (define workspace-issue #f)
       (define workspace-target #f)
       (when (> (length projects) 1)
         (define candidate (source-workspace proposal projects))
         (define existing (hash-ref workspace-by-id source-id #f))
         (cond
           [(and existing (not (equal? existing candidate)))
            (set! workspace-issue
                  "Existing Workspace identity does not match the migration target")]
           [else
            (set! workspace-target (or existing candidate))
            (set! workspace-targets
                  (cons (odra-legacy-migration-workspace
                         source-id workspace-target)
                        workspace-targets))]))
       (if workspace-issue
           (begin
             (set! source-results
                   (cons (odra-legacy-migration-source
                          source-id source-path 'rejected target-id workspace-issue)
                         source-results))
             (set! source-rejections
                   (cons (odra-legacy-migration-rejection
                          source-id source-path 'conflicting-workspace workspace-issue)
                         source-rejections)))
           (let* ([journal-entry (hash-ref journal-by-source source-id #f)]
                  [state (cond
                           [(and journal-entry
                                 (eq? (odra-migration-entry-state journal-entry)
                                      'published)
                                 (source-target-published?
                                  root projects workspace-target))
                            'already-published]
                           [journal-entry 'retry]
                           [else 'ready])])
             (hash-set! accepted-source-ids source-id #t)
             (set! source-results
                   (cons (odra-legacy-migration-source
                          source-id source-path state target-id "")
                         source-results))))]))
  (define projects
    (sort
     (for/list ([(root-text target) (in-hash root-targets)]
                #:when
                (for/or ([source-id
                          (in-list
                           (odra-legacy-migration-project-source-ids target))])
                  (hash-ref accepted-source-ids source-id #f)))
       target)
     string<?
     #:key (lambda (target)
             (odra-local-project-record-root
              (odra-legacy-migration-project-local target)))))
  (define inventory-rejections
    (for/list ([rejection
                (in-list (odra-legacy-migration-inventory-rejections inventory))])
      (odra-legacy-migration-rejection
       ""
       (odra-legacy-inventory-rejection-source rejection)
       'inventory-rejection
       (odra-legacy-inventory-rejection-message rejection))))
  (define state-targets
    (plan-state-targets inventory projects accepted-source-ids))
  (odra-legacy-migration-plan
   projects
   (sort workspace-targets string<?
         #:key (lambda (target)
                 (odra-legacy-migration-workspace-source-id target)))
   state-targets
   (reverse source-results)
   (append
    (if journal-rejection (list journal-rejection) '())
    inventory-rejections
    (reverse source-rejections))
   journal-generation))

(define (plan-state-targets inventory projects accepted-source-ids)
  (define used-projects (make-hash))
  (for*/fold ([targets '()])
             ([state
               (in-list
                (sort (odra-legacy-migration-inventory-states inventory)
                      string<? #:key odra-legacy-state-proposal-source))]
              #:when
              (hash-ref accepted-source-ids
                        (odra-legacy-state-proposal-project-id state) #f)
              [project
               (in-list
                (filter
                 (lambda (target)
                   (member (odra-legacy-state-proposal-project-id state)
                           (odra-legacy-migration-project-source-ids target)))
                 projects))]
              #:unless
              (hash-ref
               used-projects
               (odra-local-project-record-id
                (odra-legacy-migration-project-local project))
               #f))
    (define target-id
      (odra-local-project-record-id
       (odra-legacy-migration-project-local project)))
    (define source-record (load-legacy-state-record state))
    (if source-record
        (begin
          (hash-set! used-projects target-id #t)
          (cons
           (odra-legacy-migration-state
            (odra-legacy-state-proposal-project-id state)
            (odra-legacy-state-proposal-source state)
            (odra-candidate-usage-record
             current-candidate-usage-format-version
             target-id
             1
             (odra-candidate-usage-record-next-sequence source-record)
             (odra-candidate-usage-record-entries source-record)))
           targets))
        targets)))

(define (load-legacy-state-record state)
  (define source (string->path (odra-legacy-state-proposal-source state)))
  (define project-directory (parent-path source))
  (define projects-directory (and project-directory (parent-path project-directory)))
  (define state-root (and projects-directory (parent-path projects-directory)))
  (and state-root
       (let ([observation
              (candidate-usage-load
               state-root (odra-legacy-state-proposal-project-id state))])
         (and (eq? (odra-candidate-usage-observation-state observation) 'confirmed)
              (equal? (odra-candidate-usage-observation-module-bytes observation)
                      (odra-legacy-state-proposal-module-bytes state))
              (odra-candidate-usage-observation-record observation)))))

(define (parent-path path)
  (define-values (base _name _directory?) (split-path path))
  (and (path? base) base))

(define (prepare-source proposal)
  (define-values (roots issue)
    (for/fold ([roots '()] [issue #f])
              ([root-text (in-list (odra-legacy-project-proposal-roots proposal))])
      (cond
        [issue (values roots issue)]
        [else
         (define normalized (normalized-root root-text))
         (if normalized
             (values (cons normalized roots) #f)
             (values roots "Legacy Project contains an unavailable root"))])))
  (prepared-source proposal (reverse roots) issue))

(define (normalized-root root-text)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (define root (simplify-path (path->complete-path root-text) #f))
    (and (absolute-path? root)
         (directory-exists? root)
         (not (link-exists? root))
         (path->string root))))

(define (collect-single-root-owners sources)
  (for/fold ([owners (hash)]) ([source (in-list sources)])
    (if (and (not (prepared-source-issue source))
             (= (length (prepared-source-roots source)) 1))
        (let ([root-text (car (prepared-source-roots source))]
              [proposal (prepared-source-proposal source)])
          (hash-update owners root-text
                       (lambda (current) (append current (list proposal)))
                       '()))
        owners)))

(define (collect-root-sources sources)
  (for*/fold ([by-root (hash)])
             ([source (in-list sources)]
              #:unless (prepared-source-issue source)
              [root-text (in-list (prepared-source-roots source))])
    (hash-update by-root root-text
                 (lambda (current)
                   (append current (list (prepared-source-proposal source))))
                 '())))

(define (plan-root-target root-text owners sources discovery-by-id discovery-by-root)
  (define local-state (local-project-state root-text))
  (define existing-local (and (eq? local-state 'project) (load-local root-text)))
  (cond
    [(eq? local-state 'conflict)
     (migration-rejection "" root-text 'conflicting-project
                          "Existing local metadata is not a valid Project")]
    [existing-local
     (define existing-discovery
       (hash-ref discovery-by-id (odra-local-project-record-id existing-local) #f))
     (cond
       [(and existing-discovery
             (or (not (string=?
                       (odra-project-discovery-record-root existing-discovery)
                       root-text))
                 (not (=
                       (odra-project-discovery-record-expected-project-generation
                        existing-discovery)
                       (odra-local-project-record-generation existing-local)))))
        (migration-rejection "" root-text 'conflicting-project
                             "Existing Project discovery does not match local authority")]
       [else
        (migration-project sources existing-local)])]
    [else
     (define id
       (if (= (length owners) 1)
           (odra-legacy-project-proposal-id (car owners))
           (root-project-id root-text)))
     (define id-conflict (hash-ref discovery-by-id id #f))
     (define root-conflict (hash-ref discovery-by-root root-text #f))
     (cond
       [(or id-conflict root-conflict)
        (migration-rejection "" root-text 'conflicting-project
                             "Existing Project discovery conflicts with migration target")]
       [else
        (define representative (car sources))
        (define root-index
          (index-of (map normalize-known-root
                         (odra-legacy-project-proposal-roots representative))
                    root-text))
        (define trust
          (if (for/and ([source (in-list sources)])
                (define index
                  (index-of
                   (map normalize-known-root
                        (odra-legacy-project-proposal-roots source))
                   root-text))
                (and index
                     (eq? (list-ref (odra-legacy-project-proposal-trusts source)
                                    index)
                          'trusted)))
              'trusted
              'untrusted))
        (define name
          (if (= (length (odra-legacy-project-proposal-roots representative)) 1)
              (odra-legacy-project-proposal-name representative)
              (format "~a / ~a"
                      (odra-legacy-project-proposal-name representative)
                      (path-basename root-text))))
        (define local
          (local-project-record
           #:format-version current-local-project-format-version
           #:id id
           #:generation 1
           #:name name
           #:root root-text
           #:trust trust))
        (migration-project sources local)])]))

(define (migration-project sources local)
  (odra-legacy-migration-project
   (sort (remove-duplicates (map odra-legacy-project-proposal-id sources)) string<?)
   local
   (project-discovery-record
    #:format-version current-project-discovery-format-version
    #:id (odra-local-project-record-id local)
    #:expected-project-generation (odra-local-project-record-generation local)
    #:root (odra-local-project-record-root local))))

(define (source-workspace source projects)
  (workspace-record
   #:format-version current-workspace-format-version
   #:id (odra-legacy-project-proposal-id source)
   #:generation 1
   #:name (odra-legacy-project-proposal-name source)
   #:projects
   (for/list ([project (in-list projects)])
     (define local (odra-legacy-migration-project-local project))
     (workspace-project-reference
      #:id (odra-local-project-record-id local)
      #:expected-project-generation (odra-local-project-record-generation local)
      #:root (odra-local-project-record-root local)))))

(define (source-target-published? configuration-root projects workspace)
  (and
   (for/and ([project (in-list projects)])
     (define local (odra-legacy-migration-project-local project))
     (define discovery (odra-legacy-migration-project-discovery project))
     (and (equal? (load-local (odra-local-project-record-root local)) local)
          (equal? (load-discovery configuration-root
                                  (odra-project-discovery-record-id discovery))
                  discovery)))
   (or (not workspace)
       (equal? (load-workspace configuration-root
                               (odra-workspace-record-id workspace))
               workspace))))

(define (root-project-id root-text)
  (string-append "migrated-"
                 (substring (sha1 (open-input-string root-text)) 0 32)))

(define (path-basename root-text)
  (define name (file-name-from-path (string->path root-text)))
  (if name (path->string name) root-text))

(define (normalize-known-root root-text)
  (path->string (simplify-path (path->complete-path root-text) #f)))

(define (local-project-state root-text)
  (define metadata-root (build-path root-text ".odra"))
  (define target (local-project-record-path root-text))
  (cond
    [(and (file-exists? target) (not (link-exists? target))
          (odra-local-project-record? (local-project-record-module-load target)))
     'project]
    [(or (file-exists? target) (link-exists? target)
         (directory-exists? metadata-root) (link-exists? metadata-root))
     'conflict]
    [else 'absent]))

(define (load-local root-text)
  (define loaded (local-project-record-module-load
                  (local-project-record-path root-text)))
  (and (odra-local-project-record? loaded)
       (string=? root-text (odra-local-project-record-root loaded))
       loaded))

(define (load-discovery configuration-root id)
  (define target (project-discovery-record-path configuration-root id))
  (and (file-exists? target)
       (not (link-exists? target))
       (let ([loaded (project-discovery-record-module-load target)])
         (and (odra-project-discovery-record? loaded) loaded))))

(define (load-workspace configuration-root id)
  (define target (workspace-record-path configuration-root id))
  (and (file-exists? target)
       (not (link-exists? target))
       (let ([loaded (workspace-record-module-load target)])
         (and (odra-workspace-record? loaded) loaded))))

(define (load-journal configuration-root)
  (define target (migration-journal-record-path configuration-root))
  (cond
    [(not (or (file-exists? target) (link-exists? target))) (values #f #f)]
    [(link-exists? target)
     (values #f
             (migration-rejection "" (path->string target) 'invalid-journal
                                  "Migration journal must be a regular file"))]
    [else
     (define loaded (migration-journal-record-module-load target))
     (if (odra-migration-journal-record? loaded)
         (values loaded #f)
         (values #f
                 (migration-rejection "" (path->string target) 'invalid-journal
                                      "Migration journal is invalid"))) ]))

(define (migration-rejection source-id source-path code message)
  (odra-legacy-migration-rejection source-id source-path code message))
