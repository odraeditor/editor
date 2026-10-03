#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "model.rkt")

(for ([profile (in-list computation-resource-profiles)])
  (unless (validate-computation-resource-profile profile)
    (error 'jan-computation-resource-study
           "profile ~a exceeds the accepted computation limits"
           (hash-ref profile 'name)))
  (printf
   (string-append
    "study=jan-computation profile=~a valid=true table_cells=~a "
    "formula_dependencies=~a executable_targets=~a active_sessions=~a "
    "child_processes=~a generated_files=~a retained_estimate_bytes=~a "
    "temporary_estimate_bytes=~a\n")
   (hash-ref profile 'name)
   (hash-ref profile 'table-cells)
   (hash-ref profile 'formula-dependencies)
   (hash-ref profile 'executable-targets)
   (hash-ref profile 'active-sessions)
   (hash-ref profile 'child-processes)
   (hash-ref profile 'generated-files)
   (estimate-computation-retained-bytes profile)
   (estimate-computation-temporary-bytes profile)))
