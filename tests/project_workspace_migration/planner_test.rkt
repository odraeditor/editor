#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/migration/legacy-inventory.rkt"
         "../../src/migration/persistence.rkt"
         "../../src/migration/planner.rkt"
         "../../src/migration/records.rkt"
         "../../src/project/persistence.rkt"
         "../../src/project/records.rkt"
         "../../src/workspace/persistence.rkt"
         "../../src/workspace/records.rkt")

(define (with-roots action)
  (define root (make-temporary-file "odra-migration-plan-~a" 'directory))
  (define legacy-root (build-path root "legacy"))
  (define configuration-root (build-path root "config" "odra"))
  (make-directory legacy-root)
  (dynamic-wind void
                (lambda () (action root legacy-root configuration-root))
                (lambda () (delete-directory/files root))))

(define (legacy-project id name roots trusts source)
  (odra-legacy-project-proposal id 1 name roots trusts source))

(define (inventory projects [rejections '()])
  (odra-legacy-migration-inventory projects '() rejections
                                   (length projects) 0))

  (test-case "single-dir keeps identity name and trust"
  (with-roots
   (lambda (root legacy-root configuration-root)
     (define project-root (build-path root "single"))
     (make-directory project-root)
     (define source (build-path legacy-root "single.rkt"))
     (define plan
       (legacy-migration-plan-compose
        configuration-root
        (inventory
         (list (legacy-project "single" "Single"
                               (list (path->string project-root))
                               '(trusted) (path->string source))))))
     (check-equal? (length (odra-legacy-migration-plan-projects plan)) 1)
     (define target
       (odra-legacy-migration-project-local
        (car (odra-legacy-migration-plan-projects plan))))
     (check-equal? (odra-local-project-record-id target) "single")
     (check-equal? (odra-local-project-record-name target) "Single")
     (check-equal? (odra-local-project-record-trust target) 'trusted)
     (check-equal? (map odra-legacy-migration-source-state
                        (odra-legacy-migration-plan-sources plan))
                   '(ready)))))

  (test-case "multi-dir keeps order and shared roots"
  (with-roots
   (lambda (root legacy-root configuration-root)
     (define first (build-path root "first"))
     (define shared (build-path root "shared"))
     (define last (build-path root "last"))
     (for ([dir (in-list (list first shared last))]) (make-directory dir))
     (define plan
       (legacy-migration-plan-compose
        configuration-root
        (inventory
         (list
          (legacy-project "alpha" "Alpha"
                          (map path->string (list first shared))
                          '(trusted trusted)
                          (path->string (build-path legacy-root "alpha.rkt")))
          (legacy-project "beta" "Beta"
                          (map path->string (list shared last))
                          '(untrusted trusted)
                          (path->string (build-path legacy-root "beta.rkt")))))))
     (check-equal? (length (odra-legacy-migration-plan-projects plan)) 3)
     (check-equal? (length (odra-legacy-migration-plan-workspaces plan)) 2)
     (define alpha
       (odra-legacy-migration-workspace-record
        (car (odra-legacy-migration-plan-workspaces plan))))
     (define beta
       (odra-legacy-migration-workspace-record
        (cadr (odra-legacy-migration-plan-workspaces plan))))
     (check-equal?
      (map odra-workspace-project-reference-root
           (odra-workspace-record-projects alpha))
      (map path->string (list first shared)))
     (check-equal?
      (odra-workspace-project-reference-id
       (cadr (odra-workspace-record-projects alpha)))
      (odra-workspace-project-reference-id
       (car (odra-workspace-record-projects beta))))
     (define shared-target
       (for/first ([target (in-list (odra-legacy-migration-plan-projects plan))]
                   #:when (string=?
                           (odra-local-project-record-root
                            (odra-legacy-migration-project-local target))
                           (path->string shared)))
         (odra-legacy-migration-project-local target)))
     (check-equal? (odra-local-project-record-trust shared-target) 'untrusted))))

  (test-case "root conflicts stay visible and retryable"
  (with-roots
   (lambda (root legacy-root configuration-root)
     (define conflict (build-path root "conflict"))
     (make-directory conflict)
     (make-directory (build-path conflict ".odra"))
     (define missing (build-path root "missing"))
     (define plan
       (legacy-migration-plan-compose
        configuration-root
        (inventory
         (list
          (legacy-project "conflict" "Conflict" (list (path->string conflict))
                          '(trusted)
                          (path->string (build-path legacy-root "conflict.rkt")))
          (legacy-project "missing" "Missing" (list (path->string missing))
                          '(untrusted)
                          (path->string (build-path legacy-root "missing.rkt")))))))
     (check-equal? (map odra-legacy-migration-source-state
                        (odra-legacy-migration-plan-sources plan))
                   '(rejected rejected))
     (check-equal? (map odra-legacy-migration-rejection-code
                        (odra-legacy-migration-plan-rejections plan))
                   '(conflicting-root unavailable-root)))))

  (test-case "journal plans idempotent outcomes"
  (with-roots
   (lambda (root legacy-root configuration-root)
     (define first (build-path root "first"))
     (define second (build-path root "second"))
     (make-directory first)
     (make-directory second)
     (define first-local
       (local-project-record
        #:format-version current-local-project-format-version
        #:id "first" #:generation 1 #:name "First"
        #:root (path->string first) #:trust 'trusted))
     (define first-discovery
       (project-discovery-record
        #:format-version current-project-discovery-format-version
        #:id "first" #:expected-project-generation 1
        #:root (path->string first)))
     (check-true
      (odra-record-publication?
       (local-project-record-persist first first-local)))
     (check-true
      (odra-record-publication?
       (project-discovery-record-persist configuration-root first-discovery)))
     (define journal
       (migration-journal-record
        #:format-version current-migration-journal-format-version
        #:generation 1
        #:entries
        (list
         (migration-entry #:source-id "first"
                          #:source-path
                          (path->string (build-path legacy-root "first.rkt"))
                          #:target-id "first" #:state 'published)
         (migration-entry #:source-id "second"
                          #:source-path
                          (path->string (build-path legacy-root "second.rkt"))
                          #:target-id "second" #:state 'staged))))
     (check-true
      (odra-record-publication?
       (migration-journal-record-persist configuration-root journal)))
     (define plan
       (legacy-migration-plan-compose
        configuration-root
        (inventory
         (list
          (legacy-project "first" "First" (list (path->string first)) '(trusted)
                          (path->string (build-path legacy-root "first.rkt")))
          (legacy-project "second" "Second" (list (path->string second)) '(trusted)
                          (path->string (build-path legacy-root "second.rkt")))))))
     (check-equal? (map odra-legacy-migration-source-state
                        (odra-legacy-migration-plan-sources plan))
                   '(already-published retry))
     (check-equal? (odra-legacy-migration-plan-journal-generation plan) 2))))
