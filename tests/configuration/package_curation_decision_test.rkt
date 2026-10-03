#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/package_catalog/curation-decisions.rkt")

(define (digest character) (make-string 64 character))
(define assessment-ids (list (digest #\a) (digest #\b)))
(define governance-revision (make-string 40 #\c))

(define decision
  (make-human-curation-decision
   (digest #\d) 3 "policy-v3" 3 "curator-primary" "human.alice" 'accept
   assessment-ids "The exact candidate satisfies policy version 3." 100
   governance-revision))

(test-case "human decisions bind one exact submission and evidence set"
  (check-equal? (odra-human-curation-decision-submission-generation decision) 3)
  (check-equal? (odra-human-curation-decision-assessment-ids decision)
                assessment-ids)
  (check-equal?
   decision
   (make-human-curation-decision
    (digest #\d) 3 "policy-v3" 3 "curator-primary" "human.alice" 'accept
    assessment-ids "The exact candidate satisfies policy version 3." 100
    governance-revision)))

(test-case "decision identity changes with any authoritative input"
  (define rejected
    (make-human-curation-decision
     (digest #\d) 3 "policy-v3" 3 "curator-primary" "human.alice" 'reject
     assessment-ids "The exact candidate does not satisfy policy version 3."
     100 governance-revision))
  (check-not-equal? (odra-human-curation-decision-id decision)
                    (odra-human-curation-decision-id rejected)))

(test-case "decision evidence and rationale remain bounded"
  (check-exn
   exn:fail?
   (lambda ()
     (make-human-curation-decision
      (digest #\d) 3 "policy-v3" 3 "curator-primary" "human.alice" 'accept
      (reverse assessment-ids) "Ordered evidence is required." 100
      governance-revision)))
  (check-exn
   exn:fail?
   (lambda ()
     (make-human-curation-decision
      (digest #\d) 3 "policy-v3" 3 "curator-primary" "human.alice" 'accept
      assessment-ids
      (make-string (add1 maximum-curation-decision-rationale-bytes) #\x)
      100 governance-revision))))

(test-case "publication proposals bind history and constrained publisher"
  (define proposal
    (make-package-catalog-publication-proposal
     decision (digest #\e) 4 (digest #\f) 110 210 "snapshot-publisher"
     (digest #\1) ""))
  (check-equal?
   (odra-package-catalog-publication-proposal-decision-id proposal)
   (odra-human-curation-decision-id decision))
  (check-equal?
   (odra-package-catalog-publication-proposal-previous-snapshot-id proposal)
   (digest #\f)))

(test-case "publication audit records are deterministic and attributable"
  (define audit
    (make-package-catalog-publication-audit
     'decision-authorized 'human "human.alice"
     (odra-human-curation-decision-id decision) (digest #\2) #f 100))
  (check-equal?
   audit
   (make-package-catalog-publication-audit
    'decision-authorized 'human "human.alice"
    (odra-human-curation-decision-id decision) (digest #\2) #f 100)))

(test-case "malformed decision and proposal histories reject"
  (check-exn
   exn:fail?
   (lambda ()
     (struct-copy odra-human-curation-decision decision [id (digest #\0)])))
  (check-exn
   exn:fail?
   (lambda ()
     (make-package-catalog-publication-proposal
      decision (digest #\e) 2 #f 110 210 "snapshot-publisher" (digest #\1)
      ""))))
