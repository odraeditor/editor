#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "persistence.rkt"
         "promotion.rkt"
         "records.rkt"
         "../storage/record-codec.rkt"
         "../workspace/management.rkt"
         "../workspace/records.rkt")

(provide
 (struct-out odra-project-rename-result)
 (struct-out odra-project-rename-failure)
 (contract-out
  [project-rename
   (-> path-string? path-string? exact-positive-integer? string?
       (or/c odra-project-rename-result? odra-project-rename-failure?))]))

(struct odra-project-rename-result (project workspace-count) #:transparent)
(struct odra-project-rename-failure (message publication) #:transparent)

;; project-rename publishes one next Project generation and reconciles its references.
(define (project-rename configuration-root root expected-generation name)
  (with-handlers ([exn:fail?
                   (lambda (failure)
                     (odra-project-rename-failure (exn-message failure) 'uncertain))])
    (define target (local-project-record-path root))
    (define current (local-project-record-module-load target))
    (cond
      [(not (odra-local-project-record? current))
       (odra-project-rename-failure "Project metadata is invalid or unavailable" 'none)]
      [(not (= expected-generation (odra-local-project-record-generation current)))
       (odra-project-rename-failure "Project generation changed before rename" 'none)]
      [(not (record-name? name))
       (odra-project-rename-failure "Project name must be bounded, nonempty UTF-8" 'none)]
      [else
       (define updated
         (local-project-record
          #:format-version current-local-project-format-version
          #:id (odra-local-project-record-id current)
          #:generation (add1 expected-generation)
          #:name name
          #:root (odra-local-project-record-root current)
          #:trust (odra-local-project-record-trust current)))
       (define persisted (local-project-record-persist root updated))
       (if (not (odra-record-publication? persisted))
           (odra-project-rename-failure
            "Project rename could not publish local metadata" 'none)
           (rename-published-project configuration-root updated))])))

(define (rename-published-project configuration-root updated)
  (define discovery (project-discovery-reconcile configuration-root updated))
  (cond
    [(odra-project-promotion-failure? discovery)
     (odra-project-rename-failure
      (odra-project-promotion-failure-message discovery) 'uncertain)]
    [else
     (define affected
       (filter
        (lambda (workspace)
          (findf
           (lambda (reference)
             (string=? (odra-workspace-project-reference-id reference)
                       (odra-local-project-record-id updated)))
           (odra-workspace-record-projects workspace)))
        (odra-record-catalog-records (workspace-list configuration-root))))
     (define failure
       (for/or ([workspace (in-list affected)])
         (define composed
           (workspace-update-compose
            configuration-root
            (odra-workspace-record-id workspace)
            (odra-workspace-record-generation workspace)
            (odra-workspace-record-name workspace)
            (map odra-workspace-project-reference-root
                 (odra-workspace-record-projects workspace))))
         (cond
           [(odra-workspace-failure? composed)
            (odra-workspace-failure-message composed)]
           [else
            (define publication (workspace-publish configuration-root composed))
            (and (odra-workspace-failure? publication)
                 (odra-workspace-failure-message publication))])))
     (if failure
         (odra-project-rename-failure failure 'uncertain)
         (odra-project-rename-result updated (length affected)))]))
