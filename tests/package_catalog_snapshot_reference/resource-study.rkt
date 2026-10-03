#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "model.rkt")

(for ([profile (in-list snapshot-resource-profiles)])
  (unless (validate-snapshot-resource-profile profile)
    (error 'package-catalog-snapshot-resource-study
           "profile ~a exceeds the selected snapshot limits"
           (hash-ref profile 'name)))
  (printf
   "study=package-catalog-snapshot profile=~a valid=true metadata_bytes=~a signatures=~a observations=~a retained_snapshots=~a retained_estimate_bytes=~a retained_limit_bytes=~a temporary_estimate_bytes=~a temporary_limit_bytes=~a\n"
   (hash-ref profile 'name)
   (hash-ref profile 'metadata-bytes)
   (hash-ref profile 'signatures)
   (hash-ref profile 'observations)
   (hash-ref profile 'retained-snapshots)
   (estimate-snapshot-retained-bytes profile)
   (hash-ref snapshot-limits 'retained-bytes)
   (estimate-snapshot-temporary-bytes profile)
   (hash-ref snapshot-limits 'temporary-bytes)))
