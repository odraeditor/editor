#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "model.rkt")

(for ([profile (in-list catalog-identity-resource-profiles)])
  (unless (validate-catalog-identity-resource-profile profile)
    (error 'package-catalog-resource-study
           "profile ~a exceeds the selected identity limits"
           (hash-ref profile 'name)))
  (printf
   "study=package-catalog-identity profile=~a valid=true roots=~a curators=~a publishers=~a policies=~a endpoints=~a signatures=~a retained_estimate_bytes=~a retained_limit_bytes=~a temporary_estimate_bytes=~a temporary_limit_bytes=~a\n"
   (hash-ref profile 'name)
   (hash-ref profile 'root-keys)
   (hash-ref profile 'curator-authorizations)
   (hash-ref profile 'publisher-authorizations)
   (hash-ref profile 'policies)
   (hash-ref profile 'endpoints)
   (hash-ref profile 'signatures)
   (estimate-catalog-identity-retained-bytes profile)
   (hash-ref catalog-identity-limits 'retained-bytes)
   (estimate-catalog-identity-temporary-bytes profile)
   (hash-ref catalog-identity-limits 'temporary-bytes)))

