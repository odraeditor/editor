#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "curation-records.rkt"
         "curation-submissions.rkt")

(provide
 (struct-out odra-package-risk-profile)
 (contract-out
  [classify-package-release-change
   (-> odra-package-release-reference? odra-package-risk-profile?
       odra-package-release-reference? odra-package-risk-profile?
       (listof odra-package-change-summary?))]))

(struct odra-package-risk-profile
  (native? foreign? process? network? filesystem?)
  #:transparent
  #:guard
  (lambda (native? foreign? process? network? filesystem? _)
    (unless (andmap boolean?
                    (list native? foreign? process? network? filesystem?))
      (raise-arguments-error 'odra-package-risk-profile
                             "risk profile fields must be explicit booleans"))
    (values native? foreign? process? network? filesystem?)))

(define (text value)
  (cond [(string? value) value]
        [(boolean? value) (if value "present" "absent")]
        [else (format "~s" value)]))

(define (change class risk previous current)
  (and (not (equal? previous current))
       (odra-package-change-summary
        class
        (cond [(and (boolean? previous) (boolean? current))
               (if current 'added 'removed)]
              [(not previous) 'added]
              [(not current) 'removed]
              [else 'changed])
        risk (text previous) (text current))))

(define (artifact-build-projection release)
  (for/list ([artifact
              (in-list (odra-package-release-reference-artifact-set release))])
    (list (odra-package-artifact-reference-platform artifact)
          (odra-package-artifact-reference-architecture artifact)
          (odra-package-artifact-reference-builder-id artifact)
          (odra-package-artifact-reference-provenance-ref artifact)
          (odra-package-artifact-reference-reproducibility-state artifact))))

(define (artifact-content-projection release)
  (for/list ([artifact
              (in-list (odra-package-release-reference-artifact-set release))])
    (list (odra-package-artifact-reference-platform artifact)
          (odra-package-artifact-reference-architecture artifact)
          (odra-package-artifact-reference-digest artifact)
          (odra-package-artifact-reference-size artifact))))

(define (risk-change class previous current)
  (change class (if current 'critical 'medium) previous current))

(define (classify-package-release-change previous previous-risks
                                         current current-risks)
  (filter
   values
   (list
    (change 'package-identity 'critical
            (odra-package-release-reference-package-id previous)
            (odra-package-release-reference-package-id current))
    (change 'publisher 'critical
            (odra-package-release-reference-publisher-id previous)
            (odra-package-release-reference-publisher-id current))
    (change 'source 'high
            (list (odra-package-release-reference-source-uri previous)
                  (odra-package-release-reference-source-revision previous))
            (list (odra-package-release-reference-source-uri current)
                  (odra-package-release-reference-source-revision current)))
    (change 'build 'high (artifact-build-projection previous)
            (artifact-build-projection current))
    (change 'artifact-content 'critical (artifact-content-projection previous)
            (artifact-content-projection current))
    (change 'dependency 'high
            (odra-package-release-reference-dependency-set-digest previous)
            (odra-package-release-reference-dependency-set-digest current))
    (change 'compatibility 'medium
            (odra-package-release-reference-compatibility-digest previous)
            (odra-package-release-reference-compatibility-digest current))
    (change 'capability 'high
            (odra-package-release-reference-capability-set-digest previous)
            (odra-package-release-reference-capability-set-digest current))
    (change 'contribution 'medium
            (odra-package-release-reference-contribution-set-digest previous)
            (odra-package-release-reference-contribution-set-digest current))
    (risk-change 'native
                 (odra-package-risk-profile-native? previous-risks)
                 (odra-package-risk-profile-native? current-risks))
    (risk-change 'foreign
                 (odra-package-risk-profile-foreign? previous-risks)
                 (odra-package-risk-profile-foreign? current-risks))
    (risk-change 'process
                 (odra-package-risk-profile-process? previous-risks)
                 (odra-package-risk-profile-process? current-risks))
    (risk-change 'network
                 (odra-package-risk-profile-network? previous-risks)
                 (odra-package-risk-profile-network? current-risks))
    (risk-change 'filesystem
                 (odra-package-risk-profile-filesystem? previous-risks)
                 (odra-package-risk-profile-filesystem? current-risks)))))
