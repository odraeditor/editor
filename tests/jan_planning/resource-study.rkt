#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "model.rkt")

(for ([profile (in-list planning-resource-profiles)])
  (unless (validate-planning-resource-profile profile)
    (error 'jan-planning-resource-study
           "profile ~a exceeds the accepted planning limits"
           (hash-ref profile 'name)))
  (printf
   (string-append
    "study=jan-planning profile=~a valid=true semantic_targets=~a "
    "source_documents=~a agenda_entries=~a capture_candidates=~a "
    "refile_candidates=~a feed_entries=~a retained_estimate_bytes=~a temporary_estimate_bytes=~a\n")
   (hash-ref profile 'name)
   (hash-ref profile 'semantic-targets)
   (hash-ref profile 'source-documents)
   (hash-ref profile 'agenda-entries)
   (hash-ref profile 'capture-candidates)
   (hash-ref profile 'refile-candidates)
   (hash-ref profile 'feed-entries)
   (estimate-planning-retained-bytes profile)
   (estimate-planning-temporary-bytes profile)))
