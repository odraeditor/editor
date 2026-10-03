#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/migration/legacy-inventory.rkt"
         "../../src/project/candidate-usage.rkt"
         "../project_workspace_migration/legacy_fixture.rkt")

(define (with-legacy-root action)
  (define root (make-temporary-file "odra-legacy-inventory-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind void (lambda () (action root))
                (lambda () (delete-directory/files root))))

  (test-case "inventory copies Projects without mutation"
  (with-legacy-root
   (lambda (root)
     (define projects-root (build-path root "projects"))
     (define state-root (build-path root "state"))
     (write-legacy-project-record
      root
      "legacy"
      "Legacy"
      (list (build-path root "first") (build-path root "second"))
      '(trusted untrusted))
     (define state-record
       (odra-candidate-usage-record
        current-candidate-usage-format-version
        "legacy"
        1
        2
        (list (odra-candidate-usage-entry 'command "open-file" 1))))
     (check-true
      (odra-candidate-usage-publication?
       (candidate-usage-publish state-root state-record)))

     (define project-path (build-path projects-root "legacy.rkt"))
     (define state-path (candidate-usage-path state-root "legacy"))
     (define project-before (file->bytes project-path))
     (define state-before (file->bytes state-path))
     (define inventory (legacy-migration-inventory-load root))

     (check-equal? (length (odra-legacy-migration-inventory-projects inventory)) 1)
     (define proposal (car (odra-legacy-migration-inventory-projects inventory)))
     (check-equal? (odra-legacy-project-proposal-id proposal) "legacy")
     (check-equal? (odra-legacy-project-proposal-trusts proposal)
                   '(trusted untrusted))
     (check-equal? (length (odra-legacy-migration-inventory-states inventory)) 1)
     (check-equal? (odra-legacy-migration-inventory-rejections inventory) '())
     (check-equal? (file->bytes project-path) project-before)
     (check-equal? (file->bytes state-path) state-before))))

  (test-case "inventory isolates rejected entries"
  (with-legacy-root
   (lambda (root)
     (define projects-root (build-path root "projects"))
     (make-directory projects-root)
     (file-or-directory-permissions projects-root #o700)
     (call-with-output-file (build-path projects-root "broken.rkt")
       (lambda (output) (display "broken" output))
       #:permissions #o600)
     (define inventory (legacy-migration-inventory-load root))
     (check-equal? (odra-legacy-migration-inventory-projects inventory) '())
     (check-equal?
      (map odra-legacy-inventory-rejection-code
           (odra-legacy-migration-inventory-rejections inventory))
      '(invalid-language)))))
