#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "model.rkt")

(for ([profile (in-list catalog-resource-profiles)])
  (unless (validate-resource-profile profile)
    (error 'language-catalog-resource-study
           "profile ~a exceeds the selected catalog policy"
           (hash-ref profile 'name)))
  (printf
   "study=language-catalog profile=~a valid=true languages=~a selectors=~a retained_estimate_bytes=~a retained_limit_bytes=~a temporary_estimate_bytes=~a temporary_limit_bytes=~a\n"
   (hash-ref profile 'name)
   (hash-ref profile 'languages)
   (hash-ref profile 'selectors)
   (estimate-retained-bytes profile)
   (hash-ref catalog-limits 'retained-bytes)
   (estimate-temporary-bytes profile)
   (hash-ref catalog-limits 'temporary-bytes)))
