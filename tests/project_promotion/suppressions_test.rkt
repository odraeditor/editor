#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/project/persistence.rkt"
         (submod "../../src/storage/durable-file.rkt" test-support)
         "../../src/project/promotion-suppressions.rkt")

(define root (make-temporary-file "odra-promotion-suppressions-~a" 'directory))
(file-or-directory-permissions root #o700)
(define configuration-root (build-path root "config" "odra"))
(define first (path->string (build-path root "first")))
(define second (path->string (build-path root "second")))

(dynamic-wind
 void
 (lambda ()
   (define absent (promotion-suppression-inspect configuration-root first))
   (check-true (odra-promotion-suppression-state? absent))
   (check-false (odra-promotion-suppression-state-suppressed? absent))
   (check-equal? (odra-promotion-suppression-state-generation absent) 0)

   (define added (promotion-suppression-add configuration-root first))
   (check-true (odra-promotion-suppression-state? added))
   (check-eq? (odra-promotion-suppression-state-action added) 'added)
   (check-true (odra-promotion-suppression-state-suppressed? added))
   (check-equal? (odra-promotion-suppression-state-generation added) 1)

   (define repeated (promotion-suppression-add configuration-root first))
   (check-eq? (odra-promotion-suppression-state-action repeated) 'unchanged)
   (check-equal? (odra-promotion-suppression-state-generation repeated) 1)

   (define second-added (promotion-suppression-add configuration-root second))
   (check-equal? (odra-promotion-suppression-state-generation second-added) 2)
   (check-equal? (odra-promotion-suppression-state-dirs second-added)
                 (sort (list first second) string<?))

   (define removed (promotion-suppression-remove configuration-root first))
   (check-eq? (odra-promotion-suppression-state-action removed) 'removed)
   (check-false (odra-promotion-suppression-state-suppressed? removed))
   (check-equal? (odra-promotion-suppression-state-generation removed) 3)
   (check-false
    (odra-promotion-suppression-state-suppressed?
     (promotion-suppression-inspect configuration-root first)))
   (check-true
    (odra-promotion-suppression-state-suppressed?
     (promotion-suppression-inspect configuration-root second))))
 (lambda () (delete-directory/files root)))

  (test-case "bad suppression state is isolated"
  (define isolated (make-temporary-file "odra-promotion-suppression-invalid-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define isolated-config (build-path isolated "config" "odra"))
     (make-directory* isolated-config)
     (define target (promotion-suppressions-record-path isolated-config))
     (call-with-output-file target
       (lambda (output) (display "#lang racket/base\n(error 'invalid)\n" output)))
     (define inspected
       (promotion-suppression-inspect isolated-config (path->string isolated)))
     (check-true (odra-promotion-suppression-failure? inspected))
     (check-eq? (odra-promotion-suppression-failure-code inspected) 'invalid-record)
     (check-true (file-exists? target)))
   (lambda () (delete-directory/files isolated))))

  (test-case "uncertain suppression never reports success"
  (define isolated (make-temporary-file "odra-promotion-suppression-sync-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define isolated-config (build-path isolated "config" "odra"))
     (define dir (path->string (build-path isolated "source")))
     (define uncertain
       (parameterize ([current-durable-directory-sync (lambda (_) 5)])
         (promotion-suppression-add isolated-config dir)))
     (check-true (odra-promotion-suppression-failure? uncertain))
     (check-eq? (odra-promotion-suppression-failure-code uncertain)
                'publication-unresolved)
     (check-eq? (odra-promotion-suppression-failure-publication uncertain)
                'uncertain))
   (lambda () (delete-directory/files isolated))))
