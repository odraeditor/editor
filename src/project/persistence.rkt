#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/file
         (only-in "../configuration/root.rkt"
                  configuration-root-input?
                  odra-configuration-root)
         "../storage/record-codec.rkt"
         "../storage/record-store.rkt"
         "records.rkt")

(provide
 (struct-out odra-record-publication)
 (struct-out odra-record-publication-failure)
 (struct-out odra-record-catalog-rejection)
 (struct-out odra-record-catalog)
 (contract-out
  [odra-configuration-root
   (->* ()
        (#:xdg-config-home configuration-root-input?
         #:home configuration-root-input?)
        path?)]
  [local-project-record-path (-> path-string? path?)]
  [project-discovery-record-path (-> path-string? string? path?)]
  [promotion-suppressions-record-path (-> path-string? path?)]
  [project-state-root (-> path-string? path?)]
  [local-project-record-persist
   (-> path-string? odra-local-project-record?
       (or/c odra-record-publication? odra-record-publication-failure?))]
  [project-discovery-record-persist
   (-> path-string? odra-project-discovery-record?
       (or/c odra-record-publication? odra-record-publication-failure?))]
  [promotion-suppressions-record-persist
   (-> path-string? odra-promotion-suppressions-record?
       (or/c odra-record-publication? odra-record-publication-failure?))]
  [project-discovery-catalog-load
   (->* (path-string?)
        (#:maximum-entries exact-positive-integer?)
        odra-record-catalog?)]))

(define (local-project-record-path project-root)
  (build-path (path->complete-path project-root) ".odra" "project.rkt"))

(define (project-discovery-record-path configuration-root id)
  (unless (record-identity? id)
    (raise-argument-error 'project-discovery-record-path
                          "a canonical Project identity" id))
  (build-path (path->complete-path configuration-root)
              "projects"
              (string-append id ".rkt")))

(define (promotion-suppressions-record-path configuration-root)
  (build-path (path->complete-path configuration-root) "promotion-suppressions.rkt"))

(define (project-state-root configuration-root)
  (build-path (path->complete-path configuration-root) "state"))

(define (local-project-record-persist project-root record)
  (record-persist
   'local-project
   (local-project-record-path project-root)
   record
   local-project-record->module-bytes
   local-project-record-module-load
   odra-local-project-record-generation))

(define (project-discovery-record-persist configuration-root record)
  (record-persist
   'project-discovery
   (project-discovery-record-path configuration-root
                                  (odra-project-discovery-record-id record))
   record
   project-discovery-record->module-bytes
   project-discovery-record-module-load
   odra-project-discovery-record-expected-project-generation
   #:owned-root configuration-root
   #:validate-generation validate-discovery-generation))

(define (promotion-suppressions-record-persist configuration-root record)
  (record-persist
   'promotion-suppressions
   (promotion-suppressions-record-path configuration-root)
   record
   promotion-suppressions-record->module-bytes
   promotion-suppressions-record-module-load
   odra-promotion-suppressions-record-generation
   #:owned-root configuration-root))

(define (project-discovery-catalog-load configuration-root
                                        #:maximum-entries
                                        [maximum-entries default-record-catalog-entries])
  (record-catalog-load
   (build-path (path->complete-path configuration-root) "projects")
   maximum-entries
   project-discovery-record-module-load
   odra-project-discovery-record-id
   odra-project-discovery-record-root
   'duplicate-root
   "Several Project references use the same root"))

(define (validate-discovery-generation target candidate load generation-of)
  (when (file-exists? target)
    (define current (load target))
    (when (odra-record-diagnostic? current)
      (record-publication-reject
       'validation-failed
       "Existing Project discovery record cannot be validated"
       target))
    (unless (> (generation-of candidate) (generation-of current))
      (record-publication-reject
       'stale-generation
       "Project discovery generation must advance"
       target))))
