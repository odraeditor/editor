#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/list
         rackunit
         "../../src/migration/persistence.rkt"
         "../../src/migration/records.rkt"
         "../../src/project/persistence.rkt"
         "../../src/project/records.rkt"
         "../../src/saved-state/persistence.rkt"
         "../../src/saved-state/records.rkt"
         "../../src/storage/record-codec.rkt"
         "../../src/storage/record-store.rkt"
         "../../src/workspace/persistence.rkt"
         "../../src/workspace/records.rkt")

(define (with-temporary-root action)
  (define root (make-temporary-file "odra-operational-state-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind void (lambda () (action root))
                (lambda () (delete-directory/files root))))

(define (sample-project id root [generation 1])
  (local-project-record
   #:format-version current-local-project-format-version
   #:id id
   #:generation generation
   #:name (string-titlecase id)
   #:root root
   #:trust 'untrusted))

(define (sample-discovery id root [generation 1])
  (project-discovery-record
   #:format-version current-project-discovery-format-version
   #:id id
   #:expected-project-generation generation
   #:root root))

(test-case "configuration root follows XDG then HOME"
  (check-equal?
   (odra-configuration-root #:xdg-config-home "/tmp/config" #:home "/tmp/home")
   (string->path "/tmp/config/odra"))
  (check-equal?
   (odra-configuration-root #:xdg-config-home #f #:home "/tmp/home")
   (string->path "/tmp/home/.config/odra")))

(test-case "domain encoders preserve canonical record forms"
  (define project
    (local-project-record
     #:format-version 2 #:id "alpha" #:generation 1 #:name "Alpha"
     #:root "/tmp/alpha" #:trust 'untrusted))
  (define workspace
    (workspace-record
     #:format-version 1 #:id "daily" #:generation 1 #:name "Daily"
     #:projects
     (list
      (workspace-project-reference
       #:id "alpha" #:expected-project-generation 1 #:root "/tmp/alpha")
      (workspace-project-reference
       #:id "beta" #:expected-project-generation 2 #:root "/tmp/beta"))))
  (define saved
    (saved-state-record
     #:format-version 2 #:generation 1
     #:locations
     (list (named-location #:name "first" #:target "/tmp/a" #:point 1
                           #:mark #f #:region-active? #f #:summary "a"))
     #:slots '()))
  (define journal
    (migration-journal-record
     #:format-version 1 #:generation 1
     #:entries
     (list (migration-entry #:source-id "old" #:source-path "/tmp/old"
                            #:target-id "alpha" #:state 'planned))))
  (check-equal?
   (local-project-record->module-bytes project)
   (record-datum->module-bytes
    '(local-project #:format-version 2 #:id "alpha" #:generation 1
                    #:name "Alpha" #:root "/tmp/alpha" #:trust untrusted)))
  (check-equal?
   (workspace-record->module-bytes workspace)
   (record-datum->module-bytes
    '(workspace #:format-version 1 #:id "daily" #:generation 1 #:name "Daily"
                #:projects
                ((workspace-project #:id "alpha" #:expected-project-generation 1
                                    #:root "/tmp/alpha")
                 (workspace-project #:id "beta" #:expected-project-generation 2
                                    #:root "/tmp/beta")))))
  (check-equal?
   (saved-state-record->module-bytes saved)
   (record-datum->module-bytes
    '(named-locations #:format-version 2 #:generation 1
                      #:locations
                      ((named-location #:name "first" #:target "/tmp/a" #:point 1
                                       #:mark #f #:region-active? #f #:summary "a"))
                      #:slots ())))
  (check-equal?
   (migration-journal-record->module-bytes journal)
   (record-datum->module-bytes
    '(migration-journal #:format-version 1 #:generation 1
                        #:entries
                        ((migration-entry #:source-id "old" #:source-path "/tmp/old"
                                          #:target-id "alpha" #:state planned))))))

  (test-case "records round-trip local and global storage"
  (with-temporary-root
   (lambda (root)
     (define configuration-root (build-path root "config" "odra"))
     (define first-root (build-path root "first"))
     (define second-root (build-path root "second"))
     (make-directory first-root)
     (make-directory second-root)

     (define first-project
       (sample-project "first" (path->string first-root)))
     (define second-project
       (sample-project "second" (path->string second-root)))
     (check-true
      (odra-record-publication?
       (local-project-record-persist first-root first-project)))
     (check-true
      (odra-record-publication?
       (local-project-record-persist second-root second-project)))
     (check-equal?
      (local-project-record-module-load (local-project-record-path first-root))
      first-project)

     (define first-discovery
       (sample-discovery "first" (path->string first-root)))
     (define second-discovery
       (sample-discovery "second" (path->string second-root)))
     (check-true
      (odra-record-publication?
       (project-discovery-record-persist configuration-root second-discovery)))
     (check-true
      (odra-record-publication?
       (project-discovery-record-persist configuration-root first-discovery)))

     (define workspace
       (workspace-record
        #:format-version current-workspace-format-version
        #:id "daily"
        #:generation 1
        #:name "Daily"
        #:projects
        (list
         (workspace-project-reference
          #:id "first"
          #:expected-project-generation 1
          #:root (path->string first-root))
         (workspace-project-reference
          #:id "second"
          #:expected-project-generation 1
          #:root (path->string second-root)))))
     (check-true
      (odra-record-publication?
       (workspace-record-persist configuration-root workspace)))

     (define suppressions
       (promotion-suppressions-record
        #:format-version current-promotion-suppressions-format-version
        #:generation 1
        #:dirs (list (path->string (build-path root "scratch")))))
     (check-true
      (odra-record-publication?
       (promotion-suppressions-record-persist configuration-root suppressions)))

     (define migration
       (migration-journal-record
        #:format-version current-migration-journal-format-version
        #:generation 1
        #:entries
        (list
         (migration-entry
          #:source-id "legacy-first"
          #:source-path (path->string (build-path root "legacy" "first.rkt"))
          #:target-id "first"
          #:state 'planned))))
     (check-true
      (odra-record-publication?
       (migration-journal-record-persist configuration-root migration)))

     (define project-catalog (project-discovery-catalog-load configuration-root))
     (check-equal?
      (map odra-project-discovery-record-id
           (odra-record-catalog-records project-catalog))
      '("first" "second"))
     (check-equal? (odra-record-catalog-rejections project-catalog) '())
     (define workspace-catalog (workspace-catalog-load configuration-root))
     (check-equal?
      (map odra-workspace-record-id
           (odra-record-catalog-records workspace-catalog))
      '("daily"))
     (check-equal?
      (promotion-suppressions-record-module-load
       (promotion-suppressions-record-path configuration-root))
      suppressions)
     (check-equal?
      (migration-journal-record-module-load
       (migration-journal-record-path configuration-root))
      migration))))

(test-case "updates require one exact generation increment"
  (with-temporary-root
   (lambda (root)
     (define project-root (build-path root "project"))
     (make-directory project-root)
     (define initial (sample-project "project" (path->string project-root) 1))
     (define skipped (sample-project "project" (path->string project-root) 3))
     (define updated (sample-project "project" (path->string project-root) 2))
     (check-true
      (odra-record-publication?
       (local-project-record-persist project-root initial)))
     (define skipped-result (local-project-record-persist project-root skipped))
     (check-true (odra-record-publication-failure? skipped-result))
     (check-eq? (odra-record-publication-failure-code skipped-result)
                'invalid-generation)
     (check-equal?
      (local-project-record-module-load (local-project-record-path project-root))
      initial)
     (check-true
      (odra-record-publication?
       (local-project-record-persist project-root updated)))
     (check-equal?
      (local-project-record-module-load (local-project-record-path project-root))
      updated)

     (define configuration-root (build-path root "config" "odra"))
     (define discovery (sample-discovery "project" (path->string project-root) 2))
     (check-true
      (odra-record-publication?
       (project-discovery-record-persist configuration-root discovery)))
     (define stale
       (project-discovery-record-persist configuration-root discovery))
     (check-true (odra-record-publication-failure? stale))
     (check-eq? (odra-record-publication-failure-code stale) 'stale-generation))))

  (test-case "malformed entries remain separate rejects"
  (with-temporary-root
   (lambda (root)
     (define configuration-root (build-path root "config" "odra"))
     (define projects-root (build-path configuration-root "projects"))
     (make-directory* projects-root)
     (file-or-directory-permissions projects-root #o700)
     (call-with-output-file (build-path projects-root "broken.rkt")
       (lambda (output) (display "not an Odra record" output))
       #:permissions #o600)
     (define catalog (project-discovery-catalog-load configuration-root))
     (check-equal? (odra-record-catalog-records catalog) '())
     (check-equal?
      (map odra-record-catalog-rejection-code
           (odra-record-catalog-rejections catalog))
      '(invalid-record)))))
