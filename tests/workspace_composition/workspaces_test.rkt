#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/project/persistence.rkt"
         "../../src/project/rename.rkt"
         "../../src/project/records.rkt"
         "../../src/workspace/persistence.rkt"
         "../../src/workspace/records.rkt"
         "../../src/workspace/management.rkt"
         (submod "../../src/workspace/management.rkt" test-support))

(define (with-fixture action)
  (define root (make-temporary-file "odra-workspace-composition-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (define configuration-root (build-path root "config" "odra"))
  (define first (build-path root "first"))
  (define second (build-path root "second"))
  (define third (build-path root "third"))
  (for ([dir (in-list (list first second third))]) (make-directory dir))
  (define (publish-project dir id generation trust)
    (local-project-record-persist
     dir
     (local-project-record
      #:format-version current-local-project-format-version
      #:id id
      #:generation generation
      #:name (string-titlecase id)
      #:root (path->string dir)
      #:trust trust)))
  (check-true (odra-record-publication?
               (publish-project first "first" 1 'untrusted)))
  (check-true (odra-record-publication?
               (publish-project second "second" 1 'trusted)))
  (check-true (odra-record-publication?
               (publish-project third "third" 1 'untrusted)))
  (dynamic-wind
   void
   (lambda () (action root configuration-root first second third publish-project))
   (lambda () (delete-directory/files root))))

  (test-case "creation publishes identity and keeps Projects"
  (with-fixture
   (lambda (_root configuration-root first second _third _publish-project)
     (define proposal
       (parameterize ([current-workspace-identity (lambda () "daily")])
         (workspace-create-compose configuration-root "Daily" (list first second))))
     (check-true (odra-workspace-proposal? proposal))
     (define publication (workspace-publish configuration-root proposal))
     (check-true (odra-workspace-publication? publication))
     (check-eq? (odra-workspace-publication-state publication) 'published)
     (define resolution (workspace-inspect configuration-root "daily"))
     (check-true (odra-workspace-resolution? resolution))
     (check-true (odra-workspace-resolution-ready? resolution))
     (check-equal?
      (map odra-workspace-project-reference-id
           (odra-workspace-record-projects
            (odra-workspace-resolution-record resolution)))
      '("first" "second"))
     (check-equal?
      (map (lambda (member)
             (odra-local-project-record-trust
              (odra-workspace-member-resolution-project member)))
           (odra-workspace-resolution-members resolution))
      '(untrusted trusted))
     (check-equal?
      (odra-local-project-record-generation
       (local-project-record-module-load (local-project-record-path first)))
      1)
     (check-eq?
      (odra-workspace-publication-state
       (workspace-publish configuration-root proposal))
      'reconciled))))

(test-case "Workspace creation admits one Project"
  (with-fixture
   (lambda (_root configuration-root first _second _third _publish-project)
     (define proposal
       (parameterize ([current-workspace-identity (lambda () "solo")])
         (workspace-create-compose configuration-root "Solo" (list first))))
     (check-true (odra-workspace-proposal? proposal))
     (check-true (odra-workspace-publication?
                  (workspace-publish configuration-root proposal)))
     (define resolution (workspace-inspect configuration-root "solo"))
     (check-true (odra-workspace-resolution? resolution))
     (check-true (odra-workspace-resolution-ready? resolution))
     (check-equal?
      (map odra-workspace-project-reference-id
           (odra-workspace-record-projects
            (odra-workspace-resolution-record resolution)))
      '("first")))))

  (test-case "updates require generation and keep order"
  (with-fixture
   (lambda (_root configuration-root first second third _publish-project)
     (define created
       (parameterize ([current-workspace-identity (lambda () "daily")])
         (workspace-create-compose configuration-root "Daily" (list first second))))
     (check-true (odra-workspace-publication?
                  (workspace-publish configuration-root created)))
     (define stale
       (workspace-update-compose configuration-root "daily" 2 "Daily" (list third first)))
     (check-true (odra-workspace-failure? stale))
     (check-eq? (odra-workspace-failure-code stale) 'stale-workspace)
     (define updated
       (workspace-update-compose configuration-root "daily" 1 "Daily Work" (list third first)))
     (check-true (odra-workspace-proposal? updated))
     (check-true (odra-workspace-publication?
                  (workspace-publish configuration-root updated)))
     (define record (odra-workspace-resolution-record
                     (workspace-inspect configuration-root "daily")))
     (check-equal? (odra-workspace-record-generation record) 2)
     (check-equal?
      (map odra-workspace-project-reference-id
           (odra-workspace-record-projects record))
      '("third" "first")))))

  (test-case "member commands reject stale updates"
  (with-fixture
   (lambda (_root configuration-root first second third _publish-project)
     (define created
       (parameterize ([current-workspace-identity (lambda () "daily")])
         (workspace-create-compose configuration-root "Daily" (list first second))))
     (check-true (odra-workspace-publication?
                  (workspace-publish configuration-root created)))
     (define added
       (workspace-add-project-compose configuration-root "daily" 1 third))
     (check-true (odra-workspace-proposal? added))
     (check-true (odra-workspace-publication?
                  (workspace-publish configuration-root added)))
     (define stale-remove
       (workspace-remove-project-compose configuration-root "daily" 1 first))
     (check-true (odra-workspace-failure? stale-remove))
     (check-eq? (odra-workspace-failure-code stale-remove) 'stale-workspace)
     (define removed
       (workspace-remove-project-compose configuration-root "daily" 2 second))
     (check-true (odra-workspace-proposal? removed))
     (check-true (odra-workspace-publication?
                  (workspace-publish configuration-root removed)))
     (define record (odra-workspace-resolution-record
                     (workspace-inspect configuration-root "daily")))
     (check-equal? (odra-workspace-record-generation record) 3)
     (check-equal?
      (map odra-workspace-project-reference-id
           (odra-workspace-record-projects record))
      '("first" "third")))))

  (test-case "Project reorder preserves membership"
  (with-fixture
   (lambda (_root configuration-root first second third _publish-project)
     (define created
       (parameterize ([current-workspace-identity (lambda () "daily")])
         (workspace-create-compose configuration-root "Daily" (list first second third))))
     (check-true (odra-workspace-publication?
                  (workspace-publish configuration-root created)))
     (define moved
       (workspace-move-project-compose configuration-root "daily" 1 third 'earlier))
     (check-true (odra-workspace-proposal? moved))
     (check-true (odra-workspace-publication?
                  (workspace-publish configuration-root moved)))
     (define record
       (odra-workspace-resolution-record
        (workspace-inspect configuration-root "daily")))
     (check-equal? (odra-workspace-record-generation record) 2)
     (check-equal?
      (map odra-workspace-project-reference-id
           (odra-workspace-record-projects record))
      '("first" "third" "second"))
     (define boundary
       (workspace-move-project-compose configuration-root "daily" 2 first 'earlier))
     (check-true (odra-workspace-proposal? boundary))
     (check-equal? (odra-workspace-proposal-record boundary) record))))

  (test-case "Project rename updates Workspace refs"
  (with-fixture
   (lambda (_root configuration-root first _second _third _publish-project)
     (define created
       (parameterize ([current-workspace-identity (lambda () "solo")])
         (workspace-create-compose configuration-root "Solo" (list first))))
     (check-true (odra-workspace-publication?
                  (workspace-publish configuration-root created)))
     (define renamed (project-rename configuration-root first 1 "Renamed"))
     (check-true (odra-project-rename-result? renamed))
     (check-equal? (odra-project-rename-result-workspace-count renamed) 1)
     (define local
       (local-project-record-module-load (local-project-record-path first)))
     (check-equal? (odra-local-project-record-name local) "Renamed")
     (check-equal? (odra-local-project-record-generation local) 2)
     (define workspace
       (odra-workspace-resolution-record
        (workspace-inspect configuration-root "solo")))
     (check-equal? (odra-workspace-record-generation workspace) 2)
     (check-equal?
      (odra-workspace-project-reference-expected-project-generation
       (car (odra-workspace-record-projects workspace)))
      2))))

  (test-case "unregister removes exact Workspace"
  (with-fixture
   (lambda (_root configuration-root first second _third _publish-project)
     (define created
       (parameterize ([current-workspace-identity (lambda () "daily")])
         (workspace-create-compose configuration-root "Daily" (list first second))))
     (check-true (odra-workspace-publication?
                  (workspace-publish configuration-root created)))
     (define stale (workspace-unregister configuration-root "daily" 2))
     (check-true (odra-workspace-failure? stale))
     (check-eq? (odra-workspace-failure-code stale) 'stale-workspace)
     (define removed (workspace-unregister configuration-root "daily" 1))
     (check-true (odra-record-catalog? removed))
     (check-equal? (odra-record-catalog-records removed) '())
     (check-false
      (file-exists? (workspace-record-path configuration-root "daily"))))))

  (test-case "Project removal prunes Workspace refs"
  (with-fixture
   (lambda (_root configuration-root first second third _publish-project)
     (define daily
       (parameterize ([current-workspace-identity (lambda () "daily")])
         (workspace-create-compose configuration-root "Daily" (list first second third))))
     (check-true (odra-workspace-publication?
                  (workspace-publish configuration-root daily)))
     (define pair
       (parameterize ([current-workspace-identity (lambda () "pair")])
         (workspace-create-compose configuration-root "Pair" (list first second))))
     (check-true (odra-workspace-publication?
                  (workspace-publish configuration-root pair)))
     (define pruned (workspace-prune-project-references configuration-root second))
     (check-true (odra-record-catalog? pruned))
     (check-equal?
      (map odra-workspace-record-id
           (odra-record-catalog-records (workspace-list configuration-root)))
      '("daily" "pair"))
     (define daily-record
       (odra-workspace-resolution-record
        (workspace-inspect configuration-root "daily")))
     (check-equal?
      (map odra-workspace-project-reference-id
           (odra-workspace-record-projects daily-record))
      '("first" "third"))
     (define pair-record
       (odra-workspace-resolution-record
        (workspace-inspect configuration-root "pair")))
     (check-equal?
      (map odra-workspace-project-reference-id
           (odra-workspace-record-projects pair-record))
      '("first")))))

  (test-case "duplicates reject before publication"
  (with-fixture
   (lambda (_root configuration-root first second _third _publish-project)
     (define created
       (parameterize ([current-workspace-identity (lambda () "daily")])
         (workspace-create-compose configuration-root "Daily" (list first second))))
     (check-true (odra-workspace-publication?
                  (workspace-publish configuration-root created)))
     (define duplicate-name
       (workspace-create-compose configuration-root "Daily" (list second first)))
     (check-true (odra-workspace-failure? duplicate-name))
     (check-eq? (odra-workspace-failure-code duplicate-name) 'duplicate-name)
     (define duplicate-project
       (workspace-create-compose configuration-root "Other" (list first first)))
     (check-true (odra-workspace-failure? duplicate-project))
     (check-eq? (odra-workspace-failure-code duplicate-project) 'duplicate-project))))

  (test-case "missing members stay visible without rewrite"
  (with-fixture
   (lambda (_root configuration-root first second _third publish-project)
     (define created
       (parameterize ([current-workspace-identity (lambda () "daily")])
         (workspace-create-compose configuration-root "Daily" (list first second))))
     (check-true (odra-workspace-publication?
                  (workspace-publish configuration-root created)))
     (define original
       (workspace-record-module-load (workspace-record-path configuration-root "daily")))
     (delete-file (local-project-record-path first))
     (check-true (odra-record-publication?
                  (publish-project second "second" 2 'trusted)))
     (define resolution (workspace-inspect configuration-root "daily"))
     (check-false (odra-workspace-resolution-ready? resolution))
     (check-equal?
      (map odra-workspace-member-resolution-state
           (odra-workspace-resolution-members resolution))
      '(missing stale))
     (check-equal?
      (workspace-record-module-load (workspace-record-path configuration-root "daily"))
      original))))

  (test-case "moved members stay visible without rewrite"
  (with-fixture
   (lambda (_root configuration-root first second _third _publish-project)
     (define created
       (parameterize ([current-workspace-identity (lambda () "daily")])
         (workspace-create-compose configuration-root "Daily" (list first second))))
     (check-true (odra-workspace-publication?
                  (workspace-publish configuration-root created)))
     (define original
       (workspace-record-module-load (workspace-record-path configuration-root "daily")))
     (check-true
      (odra-record-publication?
       (local-project-record-persist
        first
        (local-project-record
         #:format-version current-local-project-format-version
         #:id "first"
         #:generation 2
         #:name "First"
         #:root (path->string second)
         #:trust 'untrusted))))
     (delete-directory/files second)
     (define resolution (workspace-inspect configuration-root "daily"))
     (check-false (odra-workspace-resolution-ready? resolution))
     (check-equal?
      (map odra-workspace-member-resolution-state
           (odra-workspace-resolution-members resolution))
      '(conflict unavailable))
     (check-equal?
      (workspace-record-module-load (workspace-record-path configuration-root "daily"))
      original))))

(test-case "Workspace catalog ordering is deterministic"
  (with-fixture
   (lambda (_root configuration-root first second third _publish-project)
     (for ([id (in-list '("zeta" "alpha"))]
           [name (in-list '("Zeta" "Alpha"))]
           [roots (in-list (list (list first second) (list second third)))])
       (define proposal
         (parameterize ([current-workspace-identity (lambda () id)])
           (workspace-create-compose configuration-root name roots)))
       (check-true (odra-workspace-publication?
                    (workspace-publish configuration-root proposal))))
     (check-equal?
      (map odra-workspace-record-id
           (odra-record-catalog-records (workspace-list configuration-root)))
      '("alpha" "zeta")))))
