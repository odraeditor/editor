#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/project/persistence.rkt"
         "../../src/project/records.rkt"
         "../../src/project/promotion.rkt"
         (submod "../../src/project/promotion.rkt" test-support)
         (submod "../../src/storage/durable-file.rkt" test-support))

(define (with-roots action)
  (define root (make-temporary-file "odra-project-promotion-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (define dir (build-path root "source"))
  (define configuration-root (build-path root "config" "odra"))
  (make-directory dir)
  (dynamic-wind void
                (lambda () (action root dir configuration-root))
                (lambda () (delete-directory/files root))))

(define (fixed-proposal configuration-root dir [name "Source"])
  (parameterize ([current-project-promotion-identity (lambda () "fixed-id")])
    (project-promotion-compose configuration-root dir name)))

  (test-case "promotion publishes local and discovery IDs"
  (with-roots
   (lambda (_root dir configuration-root)
     (define mutable-name (string-copy "Editable"))
     (define proposal (fixed-proposal configuration-root dir mutable-name))
     (check-true (odra-project-promotion-proposal? proposal))
     (check-eq? (odra-project-dir-inspection-state (project-dir-inspect dir))
                'ordinary)
     (string-set! mutable-name 0 #\X)

     (define local (odra-project-promotion-proposal-local-project proposal))
     (define discovery
       (odra-project-promotion-proposal-discovery-reference proposal))
     (check-equal? (odra-local-project-record-name local) "Editable")
     (check-true (immutable? (odra-local-project-record-name local)))
     (check-eq? (odra-local-project-record-trust local) 'untrusted)
     (check-equal? (odra-local-project-record-id local)
                   (odra-project-discovery-record-id discovery))

     (define published (project-promotion-publish configuration-root proposal))
     (check-true (odra-project-promotion-result? published))
     (check-eq? (odra-project-promotion-result-state published) 'published)
     (check-equal?
      (local-project-record-module-load (local-project-record-path dir))
      local)
     (check-equal?
      (project-discovery-record-module-load
       (project-discovery-record-path configuration-root "fixed-id"))
      discovery)
     (define inspection (project-dir-inspect dir))
     (check-eq? (odra-project-dir-inspection-state inspection) 'project)
     (check-equal? (odra-project-dir-inspection-project inspection) local)
     (check-equal?
      (map odra-project-discovery-record-id
           (odra-record-catalog-records
            (project-discovery-list configuration-root)))
      '("fixed-id"))

     (define repeated (project-promotion-publish configuration-root proposal))
     (check-true (odra-project-promotion-result? repeated))
     (check-eq? (odra-project-promotion-result-state repeated) 'reconciled))))

  (test-case "existing metadata blocks promotion"
  (with-roots
   (lambda (_root dir configuration-root)
     (make-directory (build-path dir ".odra"))
     (file-or-directory-permissions (build-path dir ".odra") #o700)
     (define composed (fixed-proposal configuration-root dir))
     (check-true (odra-project-promotion-failure? composed))
     (check-eq? (odra-project-promotion-failure-code composed)
                'conflicting-local-metadata)
     (check-false (file-exists? (local-project-record-path dir))))))

  (test-case "failed publish removes empty metadata"
  (with-roots
   (lambda (_root dir configuration-root)
     (define proposal (fixed-proposal configuration-root dir))
     (define failed
       (parameterize
           ([current-durable-file-write
             (lambda (_bytes _output) (error 'promotion "simulated write failure"))])
         (project-promotion-publish configuration-root proposal)))
     (check-true (odra-project-promotion-failure? failed))
     (check-eq? (odra-project-promotion-failure-code failed)
                'local-publication-failed)
     (check-eq? (odra-project-promotion-failure-publication failed) 'none)
     (check-false (directory-exists? (build-path dir ".odra"))))))

(test-case "local-only publication resumes deterministically"
  (with-roots
   (lambda (_root dir configuration-root)
     (define proposal (fixed-proposal configuration-root dir))
     (define writes 0)
     (define partial
       (parameterize
           ([current-durable-file-write
             (lambda (bytes output)
               (set! writes (add1 writes))
               (if (= writes 2)
                   (error 'promotion "simulated discovery failure")
                   (write-bytes bytes output)))])
         (project-promotion-publish configuration-root proposal)))
     (check-true (odra-project-promotion-failure? partial))
     (check-eq? (odra-project-promotion-failure-code partial)
                'discovery-publication-failed)
     (check-eq? (odra-project-promotion-failure-publication partial) 'local)
     (check-true (file-exists? (local-project-record-path dir)))
     (check-false
      (file-exists?
       (project-discovery-record-path configuration-root "fixed-id")))

     (define resumed (project-promotion-publish configuration-root proposal))
     (check-true (odra-project-promotion-result? resumed))
     (check-eq? (odra-project-promotion-result-state resumed) 'reconciled))))

  (test-case "uncertain durability stops discovery"
  (with-roots
   (lambda (_root dir configuration-root)
     (define proposal (fixed-proposal configuration-root dir))
     (define uncertain
       (parameterize ([current-durable-directory-sync (lambda (_) 5)])
         (project-promotion-publish configuration-root proposal)))
     (check-true (odra-project-promotion-failure? uncertain))
     (check-eq? (odra-project-promotion-failure-code uncertain)
                'publication-unresolved)
     (check-eq? (odra-project-promotion-failure-publication uncertain)
                'uncertain)
     (check-true (file-exists? (local-project-record-path dir)))
     (check-false
      (file-exists?
       (project-discovery-record-path configuration-root "fixed-id")))

     (define reconciled (project-promotion-publish configuration-root proposal))
     (check-true (odra-project-promotion-result? reconciled))
     (check-eq? (odra-project-promotion-result-state reconciled) 'reconciled))))

  (test-case "reconciliation advances expected generation"
  (with-roots
   (lambda (_root dir configuration-root)
     (define initial
       (local-project-record
        #:format-version current-local-project-format-version
        #:id "generation-id"
        #:generation 1
        #:name "Generation"
        #:root (path->string dir)
        #:trust 'untrusted))
     (check-true
      (odra-record-publication?
       (local-project-record-persist dir initial)))
     (check-true
      (odra-project-promotion-result?
       (project-discovery-reconcile configuration-root initial)))

     (define updated
       (local-project-record
        #:format-version current-local-project-format-version
        #:id "generation-id"
        #:generation 2
        #:name "Renamed"
        #:root (path->string dir)
        #:trust 'untrusted))
     (check-true
      (odra-record-publication?
       (local-project-record-persist dir updated)))
     (check-true
      (odra-project-promotion-result?
       (project-discovery-reconcile configuration-root updated)))
     (check-equal?
      (odra-project-discovery-record-expected-project-generation
       (project-discovery-record-module-load
        (project-discovery-record-path configuration-root "generation-id")))
      2))))

(test-case "discovery conflict preserves local authority"
  (with-roots
   (lambda (root dir configuration-root)
     (define other-root (build-path root "other"))
     (make-directory other-root)
     (define proposal (fixed-proposal configuration-root dir))
     (check-true
      (odra-record-publication?
       (project-discovery-record-persist
        configuration-root
        (project-discovery-record
         #:format-version current-project-discovery-format-version
         #:id "fixed-id"
         #:expected-project-generation 1
         #:root (path->string other-root)))))
     (define result (project-promotion-publish configuration-root proposal))
     (check-true (odra-project-promotion-failure? result))
     (check-eq? (odra-project-promotion-failure-code result)
                'discovery-conflict)
     (check-eq? (odra-project-promotion-failure-publication result) 'local)
     (check-true (file-exists? (local-project-record-path dir))))))

  (test-case "post-rename metadata ignores moved Dir"
  (with-roots
   (lambda (root dir configuration-root)
     (define proposal (fixed-proposal configuration-root dir))
     (check-true
      (odra-project-promotion-result?
       (project-promotion-publish configuration-root proposal)))
     (define moved (build-path root "moved"))
     (rename-file-or-directory dir moved)
     (define inspection (project-dir-inspect moved))
     (check-eq? (odra-project-dir-inspection-state inspection) 'conflict)
     (check-false (odra-project-dir-inspection-project inspection)))))
