#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

(require json
         racket/cmdline
         racket/file
         "bundle.rkt"
         "definitions.rkt"
         "observations.rkt"
         "release.rkt"
         "vendor/canonical-json.rkt"
         "../release/candidate-store.rkt")

(module+ main
  (define output #f)
  (define source-root #f)
  (command-line
   #:once-each
   [("--output") value "New final bundle destination" (set! output value)]
   [("--source-root") value "Exact source checkout" (set! source-root value)])
  (unless (and output source-root) (raise-user-error 'native-evidence "release paths missing"))
  (define (required name pattern)
    (define value (getenv name))
    (unless (and value (regexp-match? pattern value))
      (raise-user-error 'native-evidence "release identity input is absent or invalid"))
    value)
  (define commit (required "ODRA_EVIDENCE_SOURCE_COMMIT" #px"^[0-9a-f]{40}$"))
  (define adapter (required "ODRA_EVIDENCE_ADAPTER_COMMIT" #px"^[0-9a-f]{40}$"))
  (define version (required "ODRA_EVIDENCE_VERSION" #px"^[0-9]+\\.[0-9]+\\.[0-9]+$"))
  (define mode (required "ODRA_EVIDENCE_RELEASE_MODE" #px"^(candidate|publish)$"))
  (define run-id (required "ODRA_EVIDENCE_RUN_ID" #px"^[0-9]{1,16}$"))
  (define started-at (required "ODRA_EVIDENCE_STARTED_AT" #px"^[0-9TZ:-]{20}$"))
  (define candidate-id (required "ODRA_EVIDENCE_CANDIDATE_ID" #px"^[0-9a-f]{64}$"))
  (define needs-text (getenv "ODRA_EVIDENCE_NEEDS"))
  (unless (and needs-text (< (string-length needs-text) 65536))
    (raise-user-error 'native-evidence "release job result input exceeds bounds"))
  (define needs
    (with-handlers ([exn:fail? (lambda (_failure)
                                (raise-user-error 'native-evidence "release job result JSON is invalid"))])
      (string->jsexpr needs-text)))
  (define store-root (getenv "ODRA_RELEASE_CANDIDATE_STORE"))
  (unless store-root (raise-user-error 'native-evidence "candidate store is unavailable"))
  (define path (build-path store-root candidate-id "state.json"))
  (read-bounded-json path)
  ;; The existing candidate reader validates phase and artifact identities.
  ;; Constructing the read-only handle must not create or modify a candidate.
  (define candidate (read-candidate-state (candidate-store (path->complete-path store-root)
                                                          default-retention-policy)
                                          candidate-id))
  (unless (equal? version (hash-ref candidate 'version))
    (raise-user-error 'native-evidence "candidate version does not match this release"))
  (define source (source-observation source-root commit "detached"))
  (define environment (environment-observation))
  (define inputs
    (hasheq 'source (hash-remove source 'ref) 'environment environment 'adapter_commit adapter
            'configuration (input-observation source-root) 'mode mode 'version version
            'candidate_request_digest (hash-ref candidate 'request_sha256)
            'attempt (string-append "forgejo-native:odra/odra:" run-id)))
  (void (finalize-release! output source environment inputs needs candidate started-at)))
