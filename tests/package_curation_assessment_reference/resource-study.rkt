#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "model.rkt")

(for ([profile (in-list assessment-resource-profiles)])
  (unless (validate-assessment-resource-profile profile)
    (error 'package-curation-resource-study
           "profile ~a exceeds the selected assessment limits"
           (hash-ref profile 'name)))
  (printf
   "study=package-curation-assessment profile=~a valid=true assessments=~a findings_per_assessment=~a inputs_per_assessment=~a retained_estimate_bytes=~a retained_limit_bytes=~a temporary_estimate_bytes=~a temporary_limit_bytes=~a\n"
   (hash-ref profile 'name)
   (hash-ref profile 'assessments)
   (hash-ref profile 'findings)
   (hash-ref profile 'inputs)
   (estimate-assessment-retained-bytes profile)
   (hash-ref assessment-resource-limits 'retained-bytes)
   (estimate-assessment-temporary-bytes profile)
   (hash-ref assessment-resource-limits 'temporary-bytes)))
