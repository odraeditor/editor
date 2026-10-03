#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/port
         rackunit
         "../../scripts/migrate-project-workspaces.rkt"
         "../../src/project/persistence.rkt"
         "../../src/project/records.rkt"
         "../../src/workspace/persistence.rkt"
         "../../src/workspace/records.rkt"
         "legacy_fixture.rkt")

(define (with-roots action)
  (define root (make-temporary-file "odra-migration-cli-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (define legacy-root (build-path root "legacy"))
  (define configuration-root (build-path root "config" "odra"))
  (define first (build-path root "first"))
  (define second (build-path root "second"))
  (for ([dir (in-list (list legacy-root first second))])
    (make-directory dir)
    (file-or-directory-permissions dir #o700))
  (dynamic-wind
   void
   (lambda () (action root legacy-root configuration-root first second))
   (lambda () (delete-directory/files root))))

(define (publish-legacy legacy-root id name roots trusts)
  (write-legacy-project-record legacy-root id name roots trusts))

  (test-case "preview is read-only; apply is repeatable"
  (with-roots
   (lambda (_root legacy-root configuration-root first second)
     (publish-legacy legacy-root "legacy" "Legacy" (list first second)
                     '(trusted untrusted))
     (define source (build-path legacy-root "projects" "legacy.rkt"))
     (define source-before (file->bytes source))
     (define preview-output (open-output-string))
     (check-equal?
      (run-legacy-migration legacy-root configuration-root #f
                            #:out preview-output)
      0)
     (check-true
      (regexp-match? #rx"sources=1 projects=2 workspaces=1 states=0 rejected=0"
                     (get-output-string preview-output)))
     (check-false (directory-exists? configuration-root))
     (check-false (file-exists? (local-project-record-path first)))
     (check-equal? (file->bytes source) source-before)

     (define apply-output (open-output-string))
     (check-equal?
      (run-legacy-migration legacy-root configuration-root #t
                            #:out apply-output)
      0)
     (check-true
      (regexp-match? #rx"published=1 already-published=0 rejected=0 failures=0"
                     (get-output-string apply-output)))
     (check-true (file-exists? (local-project-record-path first)))
     (check-true (file-exists? (local-project-record-path second)))
     (check-true
      (file-exists? (workspace-record-path configuration-root "legacy")))
     (check-equal? (file->bytes source) source-before)

     (define restart-output (open-output-string))
     (check-equal?
      (run-legacy-migration legacy-root configuration-root #t
                            #:out restart-output)
      0)
     (check-true
      (regexp-match? #rx"published=0 already-published=1 rejected=0 failures=0"
                     (get-output-string restart-output)))
     (check-equal? (file->bytes source) source-before))))

  (test-case "rejections stay inspectable with status"
  (with-roots
   (lambda (_root legacy-root configuration-root first _second)
     (define missing (build-path first "missing"))
     (publish-legacy legacy-root "unavailable" "Unavailable" (list missing)
                     '(untrusted))
     (define output (open-output-string))
     (check-equal?
      (run-legacy-migration legacy-root configuration-root #t #:out output)
      2)
     (check-true (regexp-match? #rx"rejected=1" (get-output-string output)))
     (check-true (regexp-match? #rx"unavailable-root" (get-output-string output)))
     (check-false (file-exists? (local-project-record-path missing))))))
