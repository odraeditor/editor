#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(provide assessment-resource-limits
         assessment-resource-profiles
         estimate-assessment-retained-bytes
         estimate-assessment-temporary-bytes
         validate-assessment-resource-profile)

(define assessment-resource-limits
  (hash 'retained-bytes (* 192 1024 1024)
        'temporary-bytes (* 4 1024 1024)
        'assessments 128
        'findings-per-assessment 256
        'inputs-per-assessment 128
        'finding-bytes 4096))

(define assessment-resource-profiles
  (list
   (hash 'name 'ordinary 'assessments 8 'findings 8 'inputs 8
         'finding-bytes 512)
   (hash 'name 'demanding 'assessments 32 'findings 64 'inputs 32
         'finding-bytes 2048)
   (hash 'name 'boundary 'assessments 128 'findings 256 'inputs 128
         'finding-bytes 4096)))

(define (estimate-assessment-retained-bytes profile)
  (define assessments (hash-ref profile 'assessments))
  (* assessments
     (+ 1024
        (* (hash-ref profile 'findings)
           (+ 256 (hash-ref profile 'finding-bytes)))
        (* (hash-ref profile 'inputs) 64))))

(define (estimate-assessment-temporary-bytes profile)
  (+ 65536
     (* (hash-ref profile 'findings)
        (+ 256 (hash-ref profile 'finding-bytes)))
     (* (hash-ref profile 'inputs) 64)))

(define (validate-assessment-resource-profile profile)
  (and (<= (hash-ref profile 'assessments)
           (hash-ref assessment-resource-limits 'assessments))
       (<= (hash-ref profile 'findings)
           (hash-ref assessment-resource-limits 'findings-per-assessment))
       (<= (hash-ref profile 'inputs)
           (hash-ref assessment-resource-limits 'inputs-per-assessment))
       (<= (hash-ref profile 'finding-bytes)
           (hash-ref assessment-resource-limits 'finding-bytes))
       (<= (estimate-assessment-retained-bytes profile)
           (hash-ref assessment-resource-limits 'retained-bytes))
       (<= (estimate-assessment-temporary-bytes profile)
           (hash-ref assessment-resource-limits 'temporary-bytes))))
