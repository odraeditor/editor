#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

(require racket/date
         racket/list
         racket/string
         "bundle.rkt"
         "definitions.rkt"
         "session.rkt"
         "vendor/canonical-json.rkt")

(provide finalize-release! release-records)

(define phase-mapping
  (hasheq 'source-snapshot '("export" "snapshot-transfer")
          'build-and-validate '("bundle-validation")
          'prepare-user-guide '("guide-preparation")
          'retain-candidate '("candidate-retention")
          'candidate-complete '()
          'publish-source '("source-publication")
          'publish-bundle '("bundle-publication")
          'publish-user-guide '("guide-publication")
          'public-verification '("public-verification")))

(define (timestamp-ms value)
  (define match
    (and (string? value)
         (regexp-match #px"^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})Z$" value)))
  (unless match (raise-user-error 'native-evidence "release timestamp must be UTC"))
  (define n (map string->number (cdr match)))
  (* 1000 (find-seconds (list-ref n 5) (list-ref n 4) (list-ref n 3)
                        (list-ref n 2) (list-ref n 1) (list-ref n 0) #f)))

(define (latest-phases candidate names)
  (for/list ([name names]
              #:do [(define phase
                      (findf (lambda (entry) (equal? (hash-ref entry 'phase #f) name))
                             (hash-ref candidate 'phases '())))]
              #:when (and phase (pair? (hash-ref phase 'attempts '()))))
    (last (hash-ref phase 'attempts))))

;; Needs results are the authority for this attempt; old retained phases are inputs only.
(define (release-records needs candidate inputs started-at)
  (unless (and (hash? needs)
               (equal? (sort (map symbol->string (hash-keys needs)) string<?)
                       (sort release-job-names string<?)))
    (raise-user-error 'native-evidence "release needs must contain exactly the product jobs"))
  (define start-ms (timestamp-ms started-at))
  (for/list ([job release-job-names] [ordinal (in-naturals)])
    (define result (hash-ref (hash-ref needs (string->symbol job)) 'result #f))
    (define outcome
      (cond [(equal? result "success") "passed"] [(equal? result "failure") "failed"]
            [(equal? result "cancelled") "cancelled"] [(equal? result "skipped") "skipped"]
            [else (raise-user-error 'native-evidence "release job result is invalid")]))
    (define names (hash-ref phase-mapping (string->symbol job) '()))
    (define phases (latest-phases candidate names))
    (define input
      (jsexpr-sha256
       (hasheq 'declared inputs
               'phase_inputs
               (for/list ([phase phases])
                 (define digest (hash-ref phase 'input_sha256 #f))
                 (unless (and (string? digest) (regexp-match? #px"^[0-9a-f]{64}$" digest))
                   (raise-user-error 'native-evidence "retained phase input digest is invalid"))
                 (hasheq 'phase (hash-ref phase 'phase) 'input_digest digest)))))
    (define reused?
      (and (equal? outcome "passed") (pair? phases) (= (length phases) (length names))
           (andmap (lambda (phase)
                     (and (equal? (hash-ref phase 'state #f) "passed")
                          (< (timestamp-ms (hash-ref phase 'started_at)) start-ms)))
                   phases)))
    (stage-record
     "odra/release" job ordinal input outcome
     #:reuse (if reused?
                 (hasheq 'classification "reused" 'input_digest input)
                 (hasheq 'classification "unknown" 'reason "native/reuse-decision-unavailable")))))

(define (retained-artifacts candidate)
  (for/list ([artifact (hash-ref candidate 'artifacts '())])
    (define name (hash-ref artifact 'name))
    (unless (regexp-match? #px"^[a-z0-9][a-z0-9-]{0,79}$" name)
      (raise-user-error 'native-evidence "retained artifact name is invalid"))
    (hasheq 'artifact_id (string-append "release:" name ":" (hash-ref artifact 'sha256))
            'kind "release/retained-artifact" 'media_type (hash-ref artifact 'media_type)
            'size_bytes (hash-ref artifact 'byte_size) 'sha256 (hash-ref artifact 'sha256)
            'storage (hasheq 'provider "odra-candidate"
                             'reference (string-append "candidates/" (hash-ref candidate 'candidate_id)
                                                       "/" name))
            'availability "available")))

(define (finalize-release! directory source environment inputs needs candidate started-at)
  (define finished-at (utc-now))
  (define start-ms (timestamp-ms started-at))
  (define duration (- (timestamp-ms finished-at) start-ms))
  (unless (and (<= 0 duration (* 8 60 60 1000))
               (<= (length (hash-ref candidate 'artifacts '())) 32))
    (raise-user-error 'native-evidence "release duration or artifact count exceeds bounds"))
  (define semantic-inputs (hash-remove inputs 'attempt))
  (define steps (release-records needs candidate semantic-inputs started-at))
  (define state
    (hasheq 'workflow "odra/release" 'source source 'environment environment
            'inputs semantic-inputs 'attempt (hash-ref inputs 'attempt) 'started_at started-at))
  (finalize-bundle!
   directory
   (envelope
    state steps finished-at duration
    '("native/release-job-timing-unavailable" "native/release-resource-observation-unavailable"
      "native/release-authority-context-unavailable" "native/reuse-decision-unavailable")
    (retained-artifacts candidate))
   steps))
