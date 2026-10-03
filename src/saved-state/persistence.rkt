#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         (only-in "../configuration/root.rkt" configuration-named-locations-path)
         "../storage/record-store.rkt"
         "records.rkt")

(provide
 (struct-out odra-record-publication)
 (struct-out odra-record-publication-failure)
 (contract-out
  [saved-state-record-path (-> path-string? path?)]
  [saved-state-record-persist
   (-> path-string? odra-saved-state-record?
       (or/c odra-record-publication? odra-record-publication-failure?))]))

(define (saved-state-record-path configuration-root)
  (configuration-named-locations-path configuration-root))

(define (saved-state-record-persist configuration-root record)
  (record-persist
   'saved-state
   (saved-state-record-path configuration-root)
   record
   saved-state-record->module-bytes
   saved-state-record-module-load
   odra-saved-state-record-generation
   #:owned-root configuration-root))
