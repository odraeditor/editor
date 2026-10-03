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
  (define output-root #f)
  (command-line
   #:program "publish-package-catalog-snapshot.rkt"
   #:once-each
   [("--repository") path "Trusted governance repository module"
                       (set! repository-path path)]
   [("--output") path "Local immutable publication root"
                   (set! output-root path)]
   #:args () (void))
  (unless repository-path
    (raise-user-error 'package-catalog-publication "--repository is required"))
  (unless output-root
    (raise-user-error 'package-catalog-publication "--output is required"))
  (define repository
    (load-package-catalog-publication-repository repository-path))
  (define output
    (publish-package-catalog-publication-repository output-root repository))
  (define publication
    (package-catalog-publication-repository-publication repository))
  (define snapshot (odra-package-catalog-publication-snapshot publication))
  (printf "package-catalog-publication: published catalog=~a sequence=~a snapshot=~a files=4\n"
          (odra-package-catalog-snapshot-catalog-id snapshot)
          (odra-package-catalog-snapshot-sequence snapshot)
          (odra-package-catalog-snapshot-id snapshot))
  (void output))
