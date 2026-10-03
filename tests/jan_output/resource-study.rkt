#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "model.rkt")

(for ([profile (in-list output-resource-profiles)])
  (unless (validate-output-resource-profile profile)
    (error 'jan-output-resource-study "invalid profile ~a" (hash-ref profile 'name)))
  (printf
   "study=jan-output profile=~a valid=true included_resources=~a include_depth=~a macro_expansions=~a normalized_nodes=~a output_bytes=~a manifest_entries=~a provider_operations=~a retained_estimate_bytes=~a temporary_estimate_bytes=~a\n"
   (hash-ref profile 'name)
   (hash-ref profile 'included-resources)
   (hash-ref profile 'include-depth)
   (hash-ref profile 'macro-expansions)
   (hash-ref profile 'normalized-nodes)
   (hash-ref profile 'output-bytes)
   (hash-ref profile 'manifest-entries)
   (hash-ref profile 'provider-operations)
   (estimate-output-retained-bytes profile)
   (estimate-output-temporary-bytes profile)))
