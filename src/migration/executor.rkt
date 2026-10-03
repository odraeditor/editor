#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/file
         racket/list
         racket/path
         "../project/candidate-usage.rkt"
         "../project/persistence.rkt"
         "../project/records.rkt"
         "../storage/record-codec.rkt"
         "../workspace/persistence.rkt"
         "../workspace/records.rkt"
         "persistence.rkt"
         "planner.rkt"
         "records.rkt")

(provide
 (struct-out odra-legacy-migration-failure)
 (struct-out odra-legacy-migration-result)
 (contract-out
  [legacy-migration-execute
   (-> path-string? odra-legacy-migration-plan?
       odra-legacy-migration-result?)]))

(define allowed-failure-codes
  '(invalid-plan journal-failed project-failed discovery-failed
                 workspace-failed state-failed rollback-failed
                 publication-unresolved))
(define allowed-publication-states '(none partial complete uncertain))

(define current-migration-before-publication
  (make-parameter (lambda (_kind _target) (void))))

(struct odra-legacy-migration-failure
  (source-id code message publication)
  #:transparent
  #:guard
  (lambda (source-id code message publication _)
    (unless (and (string? source-id)
                 (or (string=? source-id "") (record-identity? source-id))
                 (memq code allowed-failure-codes)
                 (string? message)
                 (positive? (string-length message))
                 (<= (bytes-length (string->bytes/utf-8 message))
                     maximum-record-diagnostic-bytes)
                 (memq publication allowed-publication-states))
      (raise-arguments-error 'odra-legacy-migration-failure
                             "invalid migration execution failure"))
    (values (record-copied-text source-id)
            code
            (record-copied-text message)
            publication)))

(struct odra-legacy-migration-result
  (published already-published rejected failures journal)
  #:transparent
  #:guard
  (lambda (published already-published rejected failures journal _)
    (unless (and (list? published)
                 (andmap record-identity? published)
                 (list? already-published)
                 (andmap record-identity? already-published)
                 (list? rejected)
                 (andmap record-identity? rejected)
                 (list? failures)
                 (andmap odra-legacy-migration-failure? failures)
                 (or (not journal) (odra-migration-journal-record? journal)))
      (raise-arguments-error 'odra-legacy-migration-result
                             "invalid migration execution result"))
    (values (map record-copied-text published)
            (map record-copied-text already-published)
            (map record-copied-text rejected)
            failures
            journal)))

;; legacy-migration-execute journals every source transition and never mutates legacy input.
(define (legacy-migration-execute configuration-root plan)
  (let/ec return
  (define root (path->complete-path configuration-root))
  (define sources (odra-legacy-migration-plan-sources plan))
  (define invalid-journal?
    (for/or ([rejection
              (in-list (odra-legacy-migration-plan-rejections plan))])
      (eq? (odra-legacy-migration-rejection-code rejection) 'invalid-journal)))
  (when invalid-journal?
    (define failure
      (migration-failure "" 'invalid-plan
                         "Migration requires a valid existing journal"
                         'none))
    (return (return-migration-result sources failure)))
  (define initial-journal (initial-journal-record root plan))
  (define initial-publication (persist-journal root initial-journal))
  (cond
    [(odra-legacy-migration-failure? initial-publication)
     (return-migration-result sources initial-publication)]
    [else
     (define journal initial-publication)
     (define published '())
     (define already-published
       (source-ids-with-state sources 'already-published))
     (define rejected (source-ids-with-state sources 'rejected))
     (define failures '())
     (for ([source (in-list sources)]
           #:when (memq (odra-legacy-migration-source-state source)
                        '(ready retry)))
       (define source-id (odra-legacy-migration-source-source-id source))
       (define staged (journal-transition journal source-id 'staged))
       (define staged-publication (persist-journal root staged))
       (cond
         [(odra-legacy-migration-failure? staged-publication)
          (set! failures (cons staged-publication failures))]
         [else
          (set! journal staged-publication)
          (define publication (publish-source root plan source-id))
          (cond
            [(odra-legacy-migration-failure? publication)
             (set! failures (cons publication failures))
             (define retry-journal (journal-transition journal source-id 'planned))
             (define retry-publication (persist-journal root retry-journal))
             (unless (odra-legacy-migration-failure? retry-publication)
               (set! journal retry-publication))]
            [else
             (define completed (journal-transition journal source-id 'published))
             (define completed-publication (persist-journal root completed))
             (if (odra-legacy-migration-failure? completed-publication)
                 (set! failures
                       (cons
                        (migration-failure
                         source-id 'publication-unresolved
                         "Targets are valid but the migration journal could not record completion"
                         'uncertain)
                        failures))
                 (begin
                   (set! journal completed-publication)
                   (set! published (cons source-id published))))])]))
     (odra-legacy-migration-result
      (reverse published)
      already-published
      rejected
      (reverse failures)
      journal)])))

(define (initial-journal-record configuration-root plan)
  (define current (load-journal configuration-root))
  (define planned
    (for/list ([source (in-list (odra-legacy-migration-plan-sources plan))])
      (migration-entry
       #:source-id (odra-legacy-migration-source-source-id source)
       #:source-path (odra-legacy-migration-source-source-path source)
       #:target-id (odra-legacy-migration-source-target-id source)
       #:state
       (case (odra-legacy-migration-source-state source)
         [(already-published) 'published]
         [(rejected) 'rejected]
         [else 'planned]))))
  (define planned-ids (map odra-migration-entry-source-id planned))
  (define retained
    (if current
        (filter
         (lambda (entry)
           (not (member (odra-migration-entry-source-id entry) planned-ids)))
         (odra-migration-journal-record-entries current))
        '()))
  (migration-journal-record
   #:format-version current-migration-journal-format-version
   #:generation (odra-legacy-migration-plan-journal-generation plan)
   #:entries
   (sort (append retained planned) string<?
         #:key odra-migration-entry-source-id)))

(define (journal-transition journal source-id state)
  (migration-journal-record
   #:format-version current-migration-journal-format-version
   #:generation (add1 (odra-migration-journal-record-generation journal))
   #:entries
   (for/list ([entry (in-list (odra-migration-journal-record-entries journal))])
     (if (string=? source-id (odra-migration-entry-source-id entry))
         (migration-entry
          #:source-id (odra-migration-entry-source-id entry)
          #:source-path (odra-migration-entry-source-path entry)
          #:target-id (odra-migration-entry-target-id entry)
          #:state state)
         entry))))

(define (persist-journal configuration-root journal)
  (with-handlers ([exn:fail?
                   (lambda (failure)
                     (migration-failure "" 'journal-failed
                                        (exn-message failure) 'none))])
    ((current-migration-before-publication)
     'journal (migration-journal-record-path configuration-root))
    (define persisted
      (migration-journal-record-persist configuration-root journal))
    (define reloaded
      (load-journal configuration-root))
    (if (and (odra-record-publication? persisted)
             (equal? reloaded journal))
        journal
        (migration-failure "" 'journal-failed
                           "Migration journal publication failed validation"
                           (persistence-state persisted)))))

(define (publish-source configuration-root plan source-id)
  (define projects
    (filter
     (lambda (target)
       (member source-id (odra-legacy-migration-project-source-ids target)))
     (odra-legacy-migration-plan-projects plan)))
  (define workspace
    (findf
     (lambda (target)
       (string=? source-id
                 (odra-legacy-migration-workspace-source-id target)))
     (odra-legacy-migration-plan-workspaces plan)))
  (define states
    (filter
     (lambda (target)
       (string=? source-id (odra-legacy-migration-state-source-id target)))
     (odra-legacy-migration-plan-states plan)))
  (define created '())
  (define failure #f)
  (for ([target (in-list projects)] #:break failure)
    (define local (odra-legacy-migration-project-local target))
    (define discovery (odra-legacy-migration-project-discovery target))
    (define local-created?
      (not (file-exists? (local-project-record-path
                          (odra-local-project-record-root local)))))
    (define local-result
      (ensure-local source-id local))
    (if (odra-legacy-migration-failure? local-result)
        (set! failure local-result)
        (begin
          (when local-created? (set! created (cons (cons 'local local) created)))
          (let* ([discovery-created?
                  (not (file-exists?
                        (project-discovery-record-path
                         configuration-root
                         (odra-project-discovery-record-id discovery))))]
                 [discovery-result
                  (ensure-discovery source-id configuration-root discovery)])
            (if (odra-legacy-migration-failure? discovery-result)
                (set! failure discovery-result)
                (when discovery-created?
                  (set! created (cons (cons 'discovery discovery) created))))))))
  (when (and (not failure) workspace)
    (define record (odra-legacy-migration-workspace-record workspace))
    (define workspace-created?
      (not (file-exists?
            (workspace-record-path configuration-root
                                   (odra-workspace-record-id record)))))
    (define workspace-result
      (ensure-workspace source-id configuration-root record))
    (if (odra-legacy-migration-failure? workspace-result)
        (set! failure workspace-result)
        (when workspace-created?
          (set! created (cons (cons 'workspace record) created)))))
  (for ([target (in-list states)] #:break failure)
    (define record (odra-legacy-migration-state-record target))
    (define state-root (project-state-root configuration-root))
    (define state-created?
      (not (file-exists?
            (candidate-usage-path
             state-root (odra-candidate-usage-record-project-id record)))))
    (define state-result
      (ensure-state source-id state-root record))
    (if (odra-legacy-migration-failure? state-result)
        (set! failure state-result)
        (when state-created?
          (set! created (cons (cons 'state record) created)))))
  (cond
    [failure
     (define rollback-failure
       (rollback-created configuration-root created))
     (or rollback-failure failure)]
    [else #t]))

(define (ensure-local source-id local)
  (define root (odra-local-project-record-root local))
  (define target (local-project-record-path root))
  (with-handlers ([exn:fail?
                   (lambda (failure)
                     (migration-failure source-id 'project-failed
                                        (exn-message failure) 'partial))])
    ((current-migration-before-publication) 'local target)
    (define existing (load-local local))
    (cond
      [(equal? existing local) #t]
      [(or existing (file-exists? target) (link-exists? target))
       (migration-failure source-id 'project-failed
                          "Local Project target conflicts with migration"
                          'partial)]
      [else
       (define persisted (local-project-record-persist root local))
       (if (and (odra-record-publication? persisted)
                (equal? (load-local local) local))
           #t
           (migration-failure source-id 'project-failed
                              "Local Project publication failed validation"
                              (persistence-state persisted)))])))

(define (ensure-discovery source-id configuration-root discovery)
  (define target
    (project-discovery-record-path configuration-root
                                   (odra-project-discovery-record-id discovery)))
  (with-handlers ([exn:fail?
                   (lambda (failure)
                     (migration-failure source-id 'discovery-failed
                                        (exn-message failure) 'partial))])
    ((current-migration-before-publication) 'discovery target)
    (define existing (load-discovery configuration-root discovery))
    (cond
      [(equal? existing discovery) #t]
      [(or existing (file-exists? target) (link-exists? target))
       (migration-failure source-id 'discovery-failed
                          "Project discovery target conflicts with migration"
                          'partial)]
      [else
       (define persisted
         (project-discovery-record-persist configuration-root discovery))
       (if (and (odra-record-publication? persisted)
                (equal? (load-discovery configuration-root discovery) discovery))
           #t
           (migration-failure source-id 'discovery-failed
                              "Project discovery publication failed validation"
                              (persistence-state persisted)))])))

(define (ensure-workspace source-id configuration-root workspace)
  (define target
    (workspace-record-path configuration-root
                           (odra-workspace-record-id workspace)))
  (with-handlers ([exn:fail?
                   (lambda (failure)
                     (migration-failure source-id 'workspace-failed
                                        (exn-message failure) 'partial))])
    ((current-migration-before-publication) 'workspace target)
    (define existing (load-workspace configuration-root workspace))
    (cond
      [(equal? existing workspace) #t]
      [(or existing (file-exists? target) (link-exists? target))
       (migration-failure source-id 'workspace-failed
                          "Workspace target conflicts with migration"
                          'partial)]
      [else
       (define persisted (workspace-record-persist configuration-root workspace))
       (if (and (odra-record-publication? persisted)
                (equal? (load-workspace configuration-root workspace) workspace))
           #t
           (migration-failure source-id 'workspace-failed
                              "Workspace publication failed validation"
                              (persistence-state persisted)))])))

(define (ensure-state source-id state-root record)
  (define target
    (candidate-usage-path state-root
                          (odra-candidate-usage-record-project-id record)))
  (with-handlers ([exn:fail?
                   (lambda (failure)
                     (migration-failure source-id 'state-failed
                                        (exn-message failure) 'partial))])
    ((current-migration-before-publication) 'state target)
    (define existing (candidate-usage-load
                      state-root
                      (odra-candidate-usage-record-project-id record)))
    (cond
      [(and (eq? (odra-candidate-usage-observation-state existing) 'confirmed)
            (equal? (odra-candidate-usage-observation-record existing) record))
       #t]
      [(not (eq? (odra-candidate-usage-observation-state existing) 'absent))
       (migration-failure source-id 'state-failed
                          "Candidate state target conflicts with migration"
                          'partial)]
      [else
       (define persisted (candidate-usage-publish state-root record))
       (define reloaded
         (candidate-usage-load
          state-root (odra-candidate-usage-record-project-id record)))
       (if (and (odra-candidate-usage-publication? persisted)
                (eq? (odra-candidate-usage-observation-state reloaded) 'confirmed)
                (equal? (odra-candidate-usage-observation-record reloaded) record))
           #t
           (migration-failure source-id 'state-failed
                              "Candidate state publication failed validation"
                              'partial))])))

(define (rollback-created configuration-root created)
  (with-handlers ([exn:fail?
                   (lambda (failure)
                     (migration-failure "" 'rollback-failed
                                        (exn-message failure) 'uncertain))])
    (for ([item (in-list created)])
      (define kind (car item))
      (define record (cdr item))
      (case kind
        [(state)
         (delete-exact
          (candidate-usage-path
           (project-state-root configuration-root)
           (odra-candidate-usage-record-project-id record))
          record
          (lambda (target)
            (define project-directory (parent-path target))
            (define projects-directory (and project-directory
                                            (parent-path project-directory)))
            (define state-root (and projects-directory
                                    (parent-path projects-directory)))
            (and state-root
                 (odra-candidate-usage-observation-record
                  (candidate-usage-load
                   state-root
                   (odra-candidate-usage-record-project-id record))))))]
        [(workspace)
         (delete-exact
          (workspace-record-path configuration-root
                                 (odra-workspace-record-id record))
          record workspace-record-module-load)]
        [(discovery)
         (delete-exact
          (project-discovery-record-path
           configuration-root (odra-project-discovery-record-id record))
          record project-discovery-record-module-load)]
        [(local)
         (define root (odra-local-project-record-root record))
         (delete-exact (local-project-record-path root)
                       record local-project-record-module-load)
         (define metadata-root (build-path root ".odra"))
         (when (and (directory-exists? metadata-root)
                    (null? (directory-list metadata-root)))
           (delete-directory metadata-root))]))
    #f))

(define (delete-exact target expected load)
  (when (and (file-exists? target)
             (not (link-exists? target))
             (equal? (load target) expected))
    (delete-file target)))

(define (parent-path path)
  (define-values (base _name _directory?) (split-path path))
  (and (path? base) base))

(define (load-local local)
  (define target
    (local-project-record-path (odra-local-project-record-root local)))
  (and (file-exists? target)
       (not (link-exists? target))
       (let ([loaded (local-project-record-module-load target)])
         (and (odra-local-project-record? loaded) loaded))))

(define (load-discovery configuration-root discovery)
  (define target
    (project-discovery-record-path configuration-root
                                   (odra-project-discovery-record-id discovery)))
  (and (file-exists? target)
       (not (link-exists? target))
       (let ([loaded (project-discovery-record-module-load target)])
         (and (odra-project-discovery-record? loaded) loaded))))

(define (load-workspace configuration-root workspace)
  (define target
    (workspace-record-path configuration-root
                           (odra-workspace-record-id workspace)))
  (and (file-exists? target)
       (not (link-exists? target))
       (let ([loaded (workspace-record-module-load target)])
         (and (odra-workspace-record? loaded) loaded))))

(define (load-journal configuration-root)
  (define target (migration-journal-record-path configuration-root))
  (and (file-exists? target)
       (not (link-exists? target))
       (let ([loaded (migration-journal-record-module-load target)])
         (and (odra-migration-journal-record? loaded) loaded))))

(define (source-ids-with-state sources state)
  (for/list ([source (in-list sources)]
             #:when (eq? (odra-legacy-migration-source-state source) state))
    (odra-legacy-migration-source-source-id source)))

(define (return-migration-result sources failure)
  (odra-legacy-migration-result
   '()
   (source-ids-with-state sources 'already-published)
   (source-ids-with-state sources 'rejected)
   (list failure)
   #f))

(define (persistence-state result)
  (if (and (odra-record-publication-failure? result)
           (not (eq? (odra-record-publication-failure-publication result)
                     'not-published)))
      'uncertain
      'none))

(define (migration-failure source-id code message publication)
  (odra-legacy-migration-failure source-id code message publication))

(module+ test-support
  (provide current-migration-before-publication))
