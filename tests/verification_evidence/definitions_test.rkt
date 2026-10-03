#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

(require rackunit
         "../../scripts/evidence/definitions.rkt"
         "../../scripts/evidence/vendor/canonical-json.rkt"
         "../../scripts/evidence/vendor/validation.rkt")

;; Native definitions must stay compatible with the collector's pinned registry.
(test-case "resolves registered workflow and operation identities"
  (define subjects (read-json-file subjects-path))
  (define workflows (read-json-file workflows-path))
  (check-equal? (validate-subject-registry subjects) '())
  (check-equal? (validate-workflow-registry workflows subjects) '())
  (for ([workflow '("odra/main-check" "odra/nightly" "odra/release")])
    (define definition (workflow-definition workflow))
    (for ([step (hash-ref definition 'steps)])
      (define stage (substring step (add1 (string-length workflow))))
      (check-equal? (hash-ref (operation-definition workflow stage) 'step_id) step))
    (check-equal? (jsexpr-sha256 (workflow-definition workflow))
                  (jsexpr-sha256 definition))))

;; Operation identity advances for semantic edits, not UI names or ordering.
(test-case "separates semantic definitions from presentation"
  (define definition (operation-definition "odra/main-check" "build"))
  (check-false (hash-has-key? definition 'label))
  (check-false (hash-has-key? definition 'ordinal))
  (check-not-equal? (jsexpr-sha256 definition)
                    (jsexpr-sha256 (hash-set definition 'operation "replacement-build")))
  (check-exn exn:fail? (lambda () (workflow-definition "odra/unknown")))
  (check-exn exn:fail? (lambda () (operation-definition "odra/nightly" "unknown"))))
