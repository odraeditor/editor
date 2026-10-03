#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "model.rkt")

(for ([profile (in-list structured-editing-resource-profiles)])
  (unless (validate-resource-profile profile)
    (error 'jan-structured-editing-resource-study
           "profile ~a exceeds the accepted Stage 2 limits"
           (hash-ref profile 'name)))
  (printf
   (string-append
    "study=jan-structured-editing profile=~a valid=true hidden_ranges=~a "
    "sparse_matches=~a semantic_targets=~a table_cells=~a "
    "completion_candidates=~a templates=~a active_previews=~a "
    "retained_estimate_bytes=~a temporary_estimate_bytes=~a\n")
   (hash-ref profile 'name)
   (hash-ref profile 'hidden-ranges)
   (hash-ref profile 'sparse-matches)
   (hash-ref profile 'semantic-targets)
   (hash-ref profile 'table-cells)
   (hash-ref profile 'completion-candidates)
   (hash-ref profile 'templates)
   (hash-ref profile 'active-previews-per-view)
   (estimate-retained-bytes profile)
   (estimate-temporary-bytes profile)))
