#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (except-in openssl/sha1 sha1)
         (only-in file/sha1 bytes->hex-string)
         racket/file
         racket/list
         rackunit
         rackunit/text-ui
         "../../scripts/release/candidate-store.rkt"
         "../../scripts/release/publication-identity.rkt")

(define candidate-id
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
(define request-digest
  "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
(define input-a
  "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")
(define input-b
  "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd")
(define started-at "2026-09-26T12:00:00Z")
(define restarted-at "2026-09-26T12:01:00Z")
(define finished-at "2026-09-26T12:02:00Z")

(define (call-with-temporary-directory procedure)
  (define root (make-temporary-file "release-candidate-store-test-~a" 'directory))
  (dynamic-wind
    void
    (lambda () (procedure root))
    (lambda () (delete-directory/files root))))

(define (initialize-store root [policy default-retention-policy])
  (define store (open-candidate-store (build-path root "candidates") policy))
  (initialize-candidate! store candidate-id "0.2.0" request-digest started-at)
  store)

(define (write-artifact root name content)
  (define path (build-path root name))
  (call-with-output-file path
    #:exists 'truncate/replace
    (lambda (output) (write-bytes content output)))
  path)

(define (bytes-sha256 content)
  (bytes->hex-string (sha256-bytes (open-input-bytes content))))

(define (artifact-for name content phase path [media-type "application/zstd"])
  (artifact-identity name
                     media-type
                     (bytes-length content)
                     (bytes-sha256 content)
                     phase
                     path))

(define (phase-attempts state phase)
  (hash-ref
   (findf (lambda (entry)
            (string=? (hash-ref entry 'phase) (symbol->string phase)))
          (hash-ref state 'phases))
   'attempts))

(define candidate-store-tests
  (test-suite
   "Retained release candidate recovery"

   (test-case "Initializes one private idempotent candidate"
     (check-equal?
      (retention-policy-maximum-attempts default-retention-policy)
      16)
     (call-with-temporary-directory
      (lambda (root)
        (define store (initialize-store root))
        (define state
          (initialize-candidate!
           store candidate-id "0.2.0" request-digest restarted-at))
        (check-equal? (hash-ref state 'created_at) started-at)
        (check-equal? (file-or-directory-permissions
                       (candidate-store-root store) 'bits)
                      #o700)
        (check-equal? (file-or-directory-permissions
                       (build-path (candidate-store-root store) candidate-id)
                       'bits)
                      #o700)
        (check-equal? (file-or-directory-permissions
                       (build-path (candidate-store-root store)
                                   candidate-id
                                   "state.json")
                       'bits)
                      #o600)
        (check-exn exn:fail?
                   (lambda ()
                     (initialize-candidate!
                      store candidate-id "0.2.1" request-digest restarted-at))))))

   (test-case "Enforces the candidate retention bound"
     (call-with-temporary-directory
      (lambda (root)
        (define store
          (initialize-store root (retention-policy 1 2 2 1024)))
        (check-exn
         exn:fail?
         (lambda ()
           (initialize-candidate!
            store
            "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
            "0.2.1"
            request-digest
            restarted-at))))))

   (test-case "Reuses only a passed phase with the exact input digest"
     (call-with-temporary-directory
      (lambda (root)
        (define store (initialize-store root))
        (define started
          (start-candidate-phase!
           store candidate-id 'request input-a started-at))
        (finish-candidate-phase!
         store candidate-id 'request (phase-start-result-attempt started)
         'passed finished-at)
        (define reused
          (start-candidate-phase!
           store candidate-id 'request input-a restarted-at))
        (check-equal? (phase-start-result-disposition reused) 'reused)
        (check-true
         (candidate-phase-reusable?
          (read-candidate-state store candidate-id) 'request input-a))
        (check-false
         (candidate-phase-reusable?
          (read-candidate-state store candidate-id) 'request input-b))
        (define expected-inputs
          (for/hasheq ([phase (in-list publication-phases)])
            (values phase input-a)))
        (check-equal?
         (candidate-first-incomplete-phase
          (read-candidate-state store candidate-id) expected-inputs)
         'preflight))))

   (test-case "Distinguishes identical, conflicting, and interrupted retries"
     (call-with-temporary-directory
      (lambda (root)
        (define store (initialize-store root))
        (define first-start
          (start-candidate-phase!
           store candidate-id 'bundle-build input-a started-at))
        (define identical
          (start-candidate-phase!
           store candidate-id 'bundle-build input-a restarted-at))
        (check-equal? (phase-start-result-disposition identical) 'running)
        (check-equal? (phase-start-result-attempt identical)
                      (phase-start-result-attempt first-start))
        (check-exn
         exn:fail?
         (lambda ()
           (start-candidate-phase!
            store candidate-id 'bundle-build input-b restarted-at)))
        (define restarted
          (start-candidate-phase!
           store candidate-id 'bundle-build input-b restarted-at
           #:restart-running? #t))
        (check-equal? (phase-start-result-disposition restarted) 'started)
        (check-equal? (phase-start-result-attempt restarted) 2)
        (define attempts
          (phase-attempts (read-candidate-state store candidate-id)
                          'bundle-build))
        (check-equal? (map (lambda (attempt) (hash-ref attempt 'state)) attempts)
                      '("failed" "running"))
        (check-equal? (hash-ref (hash-ref (first attempts) 'failure) 'code)
                      "interrupted")
        (check-equal? (hash-ref (second attempts) 'input_sha256) input-b))))

   (test-case "Enforces attempt bounds and unavailable phase scope"
     (call-with-temporary-directory
      (lambda (root)
        (define store
          (initialize-store root (retention-policy 2 1 4 1024)))
        (define started
          (start-candidate-phase!
           store candidate-id 'export input-a started-at))
        (finish-candidate-phase!
         store candidate-id 'export (phase-start-result-attempt started)
         'failed finished-at
         #:failure (hasheq 'code "export-failed" 'summary "fixture"))
        (check-exn
         exn:fail?
         (lambda ()
           (start-candidate-phase!
            store candidate-id 'export input-a restarted-at)))
        (define preflight
          (start-candidate-phase!
           store candidate-id 'preflight input-a started-at))
        (check-exn
         exn:fail?
         (lambda ()
           (finish-candidate-phase!
            store candidate-id 'preflight
            (phase-start-result-attempt preflight)
            'unavailable finished-at))))))

   (test-case "Retains build and publication artifacts across store reopen"
     (call-with-temporary-directory
      (lambda (root)
        (define store (initialize-store root))
        (define fixtures
          (list
           (list "snapshot" #"snapshot" 'export
                 "artifacts/source/snapshot.tar.zst" "application/zstd")
           (list "linux-bundle" #"bundle" 'bundle-build
                 "artifacts/linux/odra.tar.zst" "application/zstd")
           (list "guide-site" #"guide" 'guide-preparation
                 "artifacts/guide/site.tar.zst" "application/zstd")
           (list "manifest" #"{\"schema\":1}" 'candidate-retention
                 "artifacts/manifests/release.json" "application/json")
           (list "summary" #"candidate passed\n" 'candidate-retention
                 "artifacts/summaries/release.txt" "text/plain")))
        (define identities
          (for/list ([fixture (in-list fixtures)])
            (define source
              (write-artifact root (string-append (first fixture) ".fixture")
                              (second fixture)))
            (define identity
              (artifact-for (first fixture)
                            (second fixture)
                            (third fixture)
                            (fourth fixture)
                            (fifth fixture)))
            (define retained
              (retain-candidate-artifact! store candidate-id source identity))
            (check-equal? (file-or-directory-permissions retained 'bits) #o600)
            (check-equal? (file->bytes retained) (second fixture))
            identity))
        (define reopened
          (open-candidate-store (candidate-store-root store)))
        (check-equal? (length (hash-ref (read-candidate-state reopened candidate-id)
                                        'artifacts))
                      5)
        (define phase-start
          (start-candidate-phase!
           reopened candidate-id 'candidate-retention input-a started-at))
        (finish-candidate-phase!
         reopened candidate-id 'candidate-retention
         (phase-start-result-attempt phase-start)
         'passed finished-at
         #:evidence identities)
        (check-equal?
         (retain-candidate-artifact!
          reopened candidate-id
          (write-artifact root "summary-retry.fixture" #"candidate passed\n")
          (last identities))
         (candidate-artifact-path reopened candidate-id (last identities))))))

   (test-case "Rejects artifact identity conflicts and unretained evidence"
     (call-with-temporary-directory
      (lambda (root)
        (define store (initialize-store root))
        (define content #"bundle")
        (define source (write-artifact root "bundle.fixture" content))
        (define artifact
          (artifact-for "linux-bundle" content 'bundle-build
                        "artifacts/linux/odra.tar.zst"))
        (retain-candidate-artifact! store candidate-id source artifact)
        (check-exn
         exn:fail?
         (lambda ()
           (retain-candidate-artifact!
            store candidate-id source
            (struct-copy artifact-identity artifact
                         [relative-path "artifacts/linux/other.tar.zst"]))))
        (check-exn
         exn:fail?
         (lambda ()
           (retain-candidate-artifact!
            store candidate-id source
            (struct-copy artifact-identity artifact
                         [name "other-bundle"]))))
        (define started
          (start-candidate-phase!
           store candidate-id 'guide-preparation input-a started-at))
        (define absent
          (artifact-for "missing-guide" #"guide" 'guide-preparation
                        "artifacts/guide/missing.tar.zst"))
        (check-exn
         exn:fail?
         (lambda ()
           (finish-candidate-phase!
            store candidate-id 'guide-preparation
            (phase-start-result-attempt started)
            'passed finished-at
            #:evidence (list absent)))))))

   (test-case "Closes a retained candidate with unavailable public verification"
     (call-with-temporary-directory
      (lambda (root)
        (define store (initialize-store root))
        (define summary-content #"{\"candidate\":\"ready\"}\n")
        (define summary
          (artifact-for "candidate-summary"
                        summary-content
                        'candidate-retention
                        "artifacts/manifests/candidate-summary.json"
                        "application/json"))
        (retain-candidate-artifact!
         store candidate-id
         (write-artifact root "candidate-summary.json" summary-content)
         summary)
        (define retention
          (start-candidate-phase!
           store candidate-id 'candidate-retention input-a started-at))
        (finish-candidate-phase!
         store candidate-id 'candidate-retention
         (phase-start-result-attempt retention)
         'passed finished-at
         #:evidence (list summary))
        (define reused
          (start-candidate-phase!
           store candidate-id 'candidate-retention input-a restarted-at))
        (check-equal? (phase-start-result-disposition reused) 'reused)
        (define verification
          (start-candidate-phase!
           store candidate-id 'public-verification input-b restarted-at))
        (finish-candidate-phase!
         store candidate-id 'public-verification
         (phase-start-result-attempt verification)
         'unavailable finished-at)
        (define verification-attempts
          (phase-attempts (read-candidate-state store candidate-id)
                          'public-verification))
        (check-equal? (hash-ref (last verification-attempts) 'state)
                      "unavailable"))))

   (test-case "Enforces artifact count and byte bounds"
     (call-with-temporary-directory
      (lambda (root)
        (define count-store
          (initialize-store root (retention-policy 2 2 1 1024)))
        (define first-content #"one")
        (define second-content #"two")
        (retain-candidate-artifact!
         count-store candidate-id
         (write-artifact root "one.fixture" first-content)
         (artifact-for "one" first-content 'export "artifacts/one"))
        (check-exn
         exn:fail?
         (lambda ()
           (retain-candidate-artifact!
            count-store candidate-id
            (write-artifact root "two.fixture" second-content)
            (artifact-for "two" second-content 'export "artifacts/two"))))
        (define byte-store
          (initialize-store (build-path root "bytes")
                            (retention-policy 2 2 2 2)))
        (check-exn
         exn:fail?
         (lambda ()
           (retain-candidate-artifact!
            byte-store candidate-id
            (write-artifact root "large.fixture" #"abc")
            (artifact-for "large" #"abc" 'export "artifacts/large")))))))

   (test-case "Rejects credential material in state and text artifacts"
     (call-with-temporary-directory
      (lambda (root)
        (define store (initialize-store root))
        (define secret #"authorization=hidden\n")
        (check-exn
         exn:fail?
         (lambda ()
           (retain-candidate-artifact!
            store candidate-id
            (write-artifact root "secret.fixture" secret)
            (artifact-for "secret" secret 'candidate-retention
                          "artifacts/secret.txt" "text/plain"))))
        (define started
          (start-candidate-phase!
           store candidate-id 'preflight input-a started-at))
        (check-exn
         exn:fail?
         (lambda ()
           (finish-candidate-phase!
            store candidate-id 'preflight
            (phase-start-result-attempt started)
            'failed finished-at
            #:failure (hasheq 'authorization "hidden")))))))))

(define failures (run-tests candidate-store-tests))
(unless (zero? failures)
  (exit 1))
