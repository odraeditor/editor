#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/migration/executor.rkt"
         (submod "../../src/migration/executor.rkt" test-support)
         "../../src/migration/legacy-inventory.rkt"
         "../../src/migration/persistence.rkt"
         "../../src/migration/planner.rkt"
         "../../src/migration/records.rkt"
         "../../src/project/candidate-usage.rkt"
         "../../src/project/persistence.rkt"
         "../../src/project/records.rkt"
         "../../src/workspace/persistence.rkt"
         "../../src/workspace/records.rkt")

(define (with-roots action)
  (define root (make-temporary-file "odra-migration-run-~a" 'directory))
  (define legacy-root (build-path root "legacy"))
  (define configuration-root (build-path root "config" "odra"))
  (make-directory legacy-root)
  (dynamic-wind void
                (lambda () (action root legacy-root configuration-root))
                (lambda () (delete-directory/files root))))

(define (proposal id name roots trusts legacy-root)
  (odra-legacy-project-proposal
   id 1 name (map path->string roots) trusts
   (path->string (build-path legacy-root (string-append id ".rkt")))))

(define (inventory proposals [states '()])
  (odra-legacy-migration-inventory proposals states '() (length proposals) 0))

(define (write-source proposal bytes)
  (call-with-output-file (odra-legacy-project-proposal-source proposal)
    (lambda (output) (write-bytes bytes output))
    #:mode 'binary))

  (test-case "migration publishes without source changes"
  (with-roots
   (lambda (root legacy-root configuration-root)
     (define first (build-path root "first"))
     (define second (build-path root "second"))
     (define third (build-path root "third"))
     (for ([dir (in-list (list first second third))]) (make-directory dir))
     (define single (proposal "single" "Single" (list first) '(trusted) legacy-root))
     (define group
       (proposal "group" "Group" (list second third)
                 '(trusted untrusted) legacy-root))
     (write-source single #"single-source")
     (write-source group #"group-source")
     (define source-bytes
       (for/hash ([source (in-list (list single group))])
         (values (odra-legacy-project-proposal-source source)
                 (file->bytes (odra-legacy-project-proposal-source source)))))
     (define plan
       (legacy-migration-plan-compose configuration-root
                                      (inventory (list single group))))
     (define result (legacy-migration-execute configuration-root plan))
     (check-equal? (odra-legacy-migration-result-published result)
                   '("group" "single"))
     (check-equal? (odra-legacy-migration-result-failures result) '())
     (for ([(source bytes) (in-hash source-bytes)])
       (check-equal? (file->bytes source) bytes))
     (check-true (file-exists? (local-project-record-path first)))
     (check-true (file-exists? (local-project-record-path second)))
     (check-true (file-exists? (local-project-record-path third)))
     (check-true (file-exists? (workspace-record-path configuration-root "group")))
     (define journal
       (migration-journal-record-module-load
        (migration-journal-record-path configuration-root)))
     (check-true (odra-migration-journal-record? journal))
     (check-equal? (map odra-migration-entry-state
                        (odra-migration-journal-record-entries journal))
                   '(published published)))))

  (test-case "retry finishes exact partial journal"
  (with-roots
   (lambda (root legacy-root configuration-root)
     (define project-root (build-path root "project"))
     (make-directory project-root)
     (define source
       (proposal "project" "Project" (list project-root) '(trusted) legacy-root))
     (write-source source #"source")
     (define first-plan
       (legacy-migration-plan-compose configuration-root (inventory (list source))))
     (define target
       (car (odra-legacy-migration-plan-projects first-plan)))
     (check-true
      (odra-record-publication?
       (local-project-record-persist
        project-root (odra-legacy-migration-project-local target))))
     (define staged
       (migration-journal-record
        #:format-version current-migration-journal-format-version
        #:generation 1
        #:entries
        (list
         (migration-entry #:source-id "project"
                          #:source-path
                          (odra-legacy-project-proposal-source source)
                          #:target-id "project" #:state 'staged))))
     (check-true
      (odra-record-publication?
       (migration-journal-record-persist configuration-root staged)))
     (define retry-plan
       (legacy-migration-plan-compose configuration-root (inventory (list source))))
     (check-equal? (odra-legacy-migration-source-state
                    (car (odra-legacy-migration-plan-sources retry-plan)))
                   'retry)
     (define result (legacy-migration-execute configuration-root retry-plan))
     (check-equal? (odra-legacy-migration-result-published result) '("project"))
     (check-equal? (odra-legacy-migration-result-failures result) '())
     (check-true
      (file-exists? (project-discovery-record-path configuration-root "project"))))))

  (test-case "failed publish rolls back attempt records"
  (with-roots
   (lambda (root legacy-root configuration-root)
     (define project-root (build-path root "project"))
     (make-directory project-root)
     (define source
       (proposal "project" "Project" (list project-root) '(trusted) legacy-root))
     (write-source source #"preserved-source")
     (define plan
       (legacy-migration-plan-compose configuration-root (inventory (list source))))
     (define result
       (parameterize
           ([current-migration-before-publication
             (lambda (kind _target)
               (when (eq? kind 'discovery)
                 (error 'migration-test "injected discovery failure")))])
         (legacy-migration-execute configuration-root plan)))
     (check-equal? (length (odra-legacy-migration-result-failures result)) 1)
     (check-false (file-exists? (local-project-record-path project-root)))
     (check-false
      (file-exists? (project-discovery-record-path configuration-root "project")))
     (check-equal? (file->bytes (odra-legacy-project-proposal-source source))
                   #"preserved-source")
     (define journal
       (migration-journal-record-module-load
        (migration-journal-record-path configuration-root)))
     (check-equal? (odra-migration-entry-state
                    (car (odra-migration-journal-record-entries journal)))
                   'planned))))

  (test-case "migration keeps entries with absent sources"
  (with-roots
   (lambda (root legacy-root configuration-root)
     (define project-root (build-path root "current"))
     (make-directory project-root)
     (define source
       (proposal "current" "Current" (list project-root) '(trusted) legacy-root))
     (write-source source #"current-source")
     (define prior
       (migration-journal-record
        #:format-version current-migration-journal-format-version
        #:generation 1
        #:entries
        (list
         (migration-entry #:source-id "retired"
                          #:source-path (path->string (build-path legacy-root "retired.rkt"))
                          #:target-id "retired" #:state 'published))))
     (check-true
      (odra-record-publication?
       (migration-journal-record-persist configuration-root prior)))
     (define plan
       (legacy-migration-plan-compose configuration-root (inventory (list source))))
     (define result (legacy-migration-execute configuration-root plan))
     (check-equal? (odra-legacy-migration-result-failures result) '())
     (define journal (odra-legacy-migration-result-journal result))
     (check-equal? (map odra-migration-entry-source-id
                        (odra-migration-journal-record-entries journal))
                   '("current" "retired")))))

  (test-case "invalid journal preserves existing bytes"
  (with-roots
   (lambda (root legacy-root configuration-root)
     (define project-root (build-path root "project"))
     (make-directory project-root)
     (define source
       (proposal "project" "Project" (list project-root) '(trusted) legacy-root))
     (write-source source #"source")
     (make-directory* configuration-root)
     (define journal-path (migration-journal-record-path configuration-root))
     (call-with-output-file journal-path
       (lambda (output) (write-bytes #"invalid-journal" output))
       #:mode 'binary)
     (define before (file->bytes journal-path))
     (define plan
       (legacy-migration-plan-compose configuration-root (inventory (list source))))
     (define result (legacy-migration-execute configuration-root plan))
     (check-equal? (length (odra-legacy-migration-result-failures result)) 1)
     (check-equal? (odra-legacy-migration-failure-code
                    (car (odra-legacy-migration-result-failures result)))
                   'invalid-plan)
     (check-equal? (file->bytes journal-path) before)
     (check-false (file-exists? (local-project-record-path project-root))))))

  (test-case "candidate state adopts one global writer"
  (with-roots
   (lambda (root legacy-root configuration-root)
     (define project-root (build-path root "project"))
     (make-directory project-root)
     (define source
       (proposal "project" "Project" (list project-root) '(trusted) legacy-root))
     (write-source source #"source")
     (define legacy-state-root (build-path legacy-root "state"))
     (define legacy-record
       (odra-candidate-usage-record
        current-candidate-usage-format-version
        "project" 1 3
        (list
         (odra-candidate-usage-entry 'command "project-find-file" 2))))
     (define legacy-publication
       (candidate-usage-publish legacy-state-root legacy-record))
     (check-true (odra-candidate-usage-publication? legacy-publication))
     (define legacy-state
       (odra-legacy-state-proposal
        "project" 'confirmed
        (path->string (candidate-usage-path legacy-state-root "project"))
        1
        (odra-candidate-usage-publication-module-bytes legacy-publication)))
     (check-equal?
      (odra-candidate-usage-observation-state
       (candidate-usage-load legacy-state-root "project"))
      'confirmed)
     (define plan
       (legacy-migration-plan-compose
        configuration-root (inventory (list source) (list legacy-state))))
     (check-equal?
      (odra-legacy-migration-project-source-ids
       (car (odra-legacy-migration-plan-projects plan)))
      '("project"))
     (check-equal? (length (odra-legacy-migration-plan-states plan)) 1)
     (define result (legacy-migration-execute configuration-root plan))
     (check-equal? (odra-legacy-migration-result-failures result) '())
     (define target-observation
       (candidate-usage-load (project-state-root configuration-root) "project"))
     (check-equal? (odra-candidate-usage-observation-state target-observation)
                   'confirmed)
     (check-equal?
      (odra-candidate-usage-record-entries
       (odra-candidate-usage-observation-record target-observation))
      (odra-candidate-usage-record-entries legacy-record))
     (check-equal?
      (file->bytes (candidate-usage-path legacy-state-root "project"))
      (odra-candidate-usage-publication-module-bytes legacy-publication)))))
