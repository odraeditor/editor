#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         "../storage/record-store.rkt"
         "records.rkt")

(provide
 (struct-out odra-record-publication)
 (struct-out odra-record-publication-failure)
 (contract-out
  [migration-journal-record-path (-> path-string? path?)]
  [migration-journal-record-persist
   (-> path-string? odra-migration-journal-record?
       (or/c odra-record-publication? odra-record-publication-failure?))]))

(define (migration-journal-record-path configuration-root)
  (build-path (path->complete-path configuration-root) "migration.rkt"))

(define (migration-journal-record-persist configuration-root record)
  (record-persist
   'migration-journal
   (migration-journal-record-path configuration-root)
   record
   migration-journal-record->module-bytes
   migration-journal-record-module-load
   odra-migration-journal-record-generation
   #:owned-root configuration-root))
