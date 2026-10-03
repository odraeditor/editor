#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         "../storage/record-codec.rkt"
         "../storage/record-store.rkt"
         "records.rkt")

(provide
 (struct-out odra-record-publication)
 (struct-out odra-record-publication-failure)
 (struct-out odra-record-catalog-rejection)
 (struct-out odra-record-catalog)
 (contract-out
  [workspace-record-path (-> path-string? string? path?)]
  [workspace-record-persist
   (-> path-string? odra-workspace-record?
       (or/c odra-record-publication? odra-record-publication-failure?))]
  [workspace-catalog-load
   (->* (path-string?)
        (#:maximum-entries exact-positive-integer?)
        odra-record-catalog?)]))

(define (workspace-record-path configuration-root id)
  (unless (record-identity? id)
    (raise-argument-error 'workspace-record-path
                          "a canonical Workspace identity" id))
  (build-path (path->complete-path configuration-root)
              "workspaces"
              (string-append id ".rkt")))

(define (workspace-record-persist configuration-root record)
  (record-persist
   'workspace
   (workspace-record-path configuration-root (odra-workspace-record-id record))
   record
   workspace-record->module-bytes
   workspace-record-module-load
   odra-workspace-record-generation
   #:owned-root configuration-root))

(define (workspace-catalog-load configuration-root
                                #:maximum-entries
                                [maximum-entries default-record-catalog-entries])
  (record-catalog-load
   (build-path (path->complete-path configuration-root) "workspaces")
   maximum-entries
   workspace-record-module-load
   odra-workspace-record-id
   odra-workspace-record-name
   'duplicate-name
   "Several Workspaces use the same display name"))
