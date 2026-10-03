#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "reference-model.rkt")

(unless (validate-fixture-manifest (load-fixture-manifest))
  (error 'jan-document-language-resource-study
         "fixture manifest does not cover the complete Stage 1 inventory"))

(unless (validate-resource-profiles resource-profiles)
  (error 'jan-document-language-resource-study
         "resource profile exceeds the selected Stage 1 policy"))

(for ([profile (in-list resource-profiles)])
  (printf
   "study=jan-document-language profile=~a valid=true source_bytes=~a nodes=~a structural_depth=~a inline_depth=~a attributes_per_node=~a index_facts=~a diagnostics=~a incremental_edits=~a retained_estimate_bytes=~a retained_limit_bytes=~a temporary_estimate_bytes=~a temporary_limit_bytes=~a\n"
   (hash-ref profile 'name)
   (hash-ref profile 'source-bytes)
   (hash-ref profile 'nodes)
   (hash-ref profile 'structural-depth)
   (hash-ref profile 'inline-depth)
   (hash-ref profile 'attributes-per-node)
   (hash-ref profile 'index-facts)
   (hash-ref profile 'diagnostics)
   (hash-ref profile 'incremental-edits)
   (estimated-retained-bytes profile)
   (hash-ref resource-limits 'retained-bytes)
   (estimated-temporary-bytes profile)
   (hash-ref resource-limits 'temporary-bytes)))
