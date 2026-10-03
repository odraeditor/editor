#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/list
         racket/runtime-path
         rackunit
         "../../src/package_catalog/contracts.rkt"
         "../../src/package_catalog/curation-decisions.rkt"
         "../../src/package_catalog/curation-records.rkt"
         "../../src/package_catalog/curation-submissions.rkt"
         "../../src/package_catalog/official-bootstrap.rkt"
         "../../src/package_catalog/security-advisories.rkt"
         "../../src/package_catalog/snapshot-records.rkt")

(define-runtime-path kit "../../assets/package-catalog/curator-kit")
(define-runtime-path template
  "../../assets/package-catalog/curator-kit/template/catalog.rkt")

(define (export name) (dynamic-require template name))

(test-case "neutral curator template covers every public authoring record"
  (define profile (export 'profile))
  (check-true (odra-package-catalog-profile? profile))
  (check-true (andmap odra-package-catalog-publisher-key?
                      (export 'publisher-keys)))
  (check-true (odra-package-catalog-endpoint? (export 'origin-endpoint)))
  (check-true (odra-package-catalog-endpoint? (export 'mirror-endpoint)))
  (check-true (odra-package-release-reference? (export 'release)))
  (check-true (odra-curation-submission? (export 'submission)))
  (check-true (odra-curation-assessment? (export 'assessment)))
  (check-true (odra-human-curation-decision? (export 'decision)))
  (check-true (odra-package-curation-assertion? (export 'assertion)))
  (check-true (odra-security-advisory? (export 'advisory)))
  (check-true (odra-package-catalog-snapshot? (export 'snapshot)))
  (check-not-equal? (odra-package-catalog-profile-identity profile)
                    official-package-catalog-identity))

(test-case "curator kit contains no official or secret-bearing material"
  (define files
    (sort (find-files file-exists? kit) string<? #:key path->string))
  (check-true (pair? files))
  (for ([path (in-list files)])
    (define content (file->bytes path))
    (check-false (regexp-match? #rx#"BEGIN[ ]+(?:ENCRYPTED[ ]+)?PRIVATE[ ]+KEY"
                                content)
                 (path->string path))
    (check-false (regexp-match? #rx#"adrianpk" content)
                 (path->string path))
    (check-false
     (regexp-match? (byte-regexp (string->bytes/utf-8
                                  official-package-catalog-identity))
                    content)
     (path->string path))))
