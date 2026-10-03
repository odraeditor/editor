#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/cmdline
         "../src/package_catalog/curation-publication.rkt"
         "../src/package_catalog/snapshot-records.rkt"
         "package-catalog-publication-support.rkt")

(module+ main
  (define repository-path #f)
  (command-line
   #:program "validate-package-catalog-publication.rkt"
   #:once-each
   [("--repository") path "Trusted governance repository module"
                       (set! repository-path path)]
   #:args () (void))
  (unless repository-path
    (raise-user-error 'package-catalog-publication "--repository is required"))
  (define repository
    (load-package-catalog-publication-repository repository-path))
  (define publication
    (validate-package-catalog-publication-repository repository))
  (define snapshot (odra-package-catalog-publication-snapshot publication))
  (printf "package-catalog-publication: valid catalog=~a sequence=~a snapshot=~a assertions=~a\n"
          (odra-package-catalog-snapshot-catalog-id snapshot)
          (odra-package-catalog-snapshot-sequence snapshot)
          (odra-package-catalog-snapshot-id snapshot)
          (length (odra-package-catalog-publication-assertions publication))))
