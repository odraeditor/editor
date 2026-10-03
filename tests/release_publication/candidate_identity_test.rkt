#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         rackunit/text-ui
         "../../scripts/release/publication-identity.rkt")

(define commit "0123456789abcdef0123456789abcdef01234567")
(define snapshot-commit "1123456789abcdef0123456789abcdef01234567")
(define snapshot-tree "2123456789abcdef0123456789abcdef01234567")
(define digest-a
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
(define digest-b
  "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
(define digest-c
  "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")

(define candidate-request
  (release-request 'candidate
                   "0.2.0"
                   "odra/odra"
                   commit
                   1798761600
                   "odra/editor"
                   (list publication-platform)
                   "source-policy-v1"
                   digest-a
                   digest-b
                   "user-guide-v1"))

(define publish-request
  (struct-copy release-request candidate-request [mode 'publish]))

(define snapshot
  (snapshot-identity (snapshot-candidate-ref candidate-request)
                     snapshot-commit
                     snapshot-tree
                     digest-c
                     digest-a
                     #f))

(define bundle
  (artifact-identity "linux-bundle"
                     "application/zstd"
                     1024
                     digest-b
                     'bundle-build
                     "artifacts/odra-0.2.0-linux-x86_64.tar.zst"))

(define guide
  (artifact-identity "user-guide-site"
                     "application/zstd"
                     512
                     digest-c
                     'guide-preparation
                     "artifacts/odra-0.2.0-user-guide.tar.zst"))

(define exported
  (phase-record 'export
                'passed
                digest-a
                1
                "2026-09-26T12:00:00Z"
                "2026-09-26T12:00:01Z"
                '()
                #f))

(define built
  (phase-record 'bundle-build
                'passed
                digest-b
                1
                "2026-09-26T12:01:00+02:00"
                "2026-09-26T12:30:00+02:00"
                (list bundle)
                #f))

(define candidate-manifest
  (publication-manifest candidate-request
                        (release-candidate-identity candidate-request)
                        snapshot
                        (list guide bundle)
                        (list built exported)
                        (hasheq 'source #f 'bundle #f 'guide #f)))

(define identity-tests
  (test-suite
   "Public release candidate identity"

   (test-case "Accepts one bounded release request"
     (check-true (release-request-valid? candidate-request))
     (check-equal? (release-tag candidate-request) "v0.2.0")
     (check-equal? (snapshot-candidate-ref candidate-request)
                   "refs/heads/candidates/v0.2.0")
     (check-equal? (string-length
                    (release-candidate-identity candidate-request))
                   64))

   (test-case "Keeps operation mode outside candidate identity"
     (check-true (release-request-valid? publish-request))
     (check-equal? (release-candidate-identity candidate-request)
                   (release-candidate-identity publish-request))
     (check-not-equal? (release-request->jsexpr candidate-request)
                       (release-request->jsexpr publish-request)))

   (test-case "Rejects malformed request identities"
     (for ([invalid (in-list
                     (list
                      (struct-copy release-request candidate-request
                                   [mode 'automatic])
                      (struct-copy release-request candidate-request
                                   [version "v0.2.0"])
                      (struct-copy release-request candidate-request
                                   [version "00.2.0"])
                      (struct-copy release-request candidate-request
                                   [source-repository "ssh://private/repo"])
                      (struct-copy release-request candidate-request
                                   [source-commit "01234567"])
                      (struct-copy release-request candidate-request
                                   [source-date-epoch -1])
                      (struct-copy release-request candidate-request
                                   [platforms '("linux-arm64")])
                      (struct-copy release-request candidate-request
                                   [export-policy-sha256 "sha256:bad"])))])
       (check-false (release-request-valid? invalid))))

   (test-case "Validates resolved snapshot and artifact identities"
     (check-true (snapshot-identity-valid? snapshot))
     (check-true (artifact-identity-valid? bundle))
     (for ([path (in-list '("/absolute/archive"
                            "../private/archive"
                            "artifacts/../../private"
                            "artifacts\\archive"))])
       (check-false
        (artifact-identity-valid?
         (struct-copy artifact-identity bundle [relative-path path])))))

   (test-case "Requires terminal phase completion and failure detail"
     (check-true (phase-record-valid? exported))
     (check-false
      (phase-record-valid?
       (struct-copy phase-record exported [finished-at #f])))
     (check-false
      (phase-record-valid?
       (struct-copy phase-record exported
                    [state 'failed]
                    [failure #f])))
     (check-true
      (phase-record-valid?
       (struct-copy phase-record exported
                    [state 'failed]
                    [failure (hasheq 'command "export" 'status 1)]))))

   (test-case "Serializes keys and collections canonically"
     (check-equal? (canonical-json-string (hasheq 'z 1 'a (hasheq 'b 2 'a 1)))
                   "{\"a\":{\"a\":1,\"b\":2},\"z\":1}")
     (check-true (publication-manifest-valid? candidate-manifest))
     (define manifest-json (publication-manifest->jsexpr candidate-manifest))
     (check-equal? (map (lambda (artifact) (hash-ref artifact 'name))
                        (hash-ref manifest-json 'artifacts))
                   '("linux-bundle" "user-guide-site"))
     (check-equal? (map (lambda (phase) (hash-ref phase 'phase))
                        (hash-ref manifest-json 'phases))
                   '("export" "bundle-build")))

   (test-case "Produces stable candidate and manifest digests"
     (define reordered
       (struct-copy publication-manifest
                    candidate-manifest
                    [artifacts (list bundle guide)]
                    [phases (list exported built)]))
     (check-equal?
      (canonical-jsexpr-sha256
       (publication-manifest->jsexpr candidate-manifest))
      (canonical-jsexpr-sha256
       (publication-manifest->jsexpr reordered))))

   (test-case "Rejects duplicate artifact and phase identities"
     (check-false
      (publication-manifest-valid?
       (struct-copy publication-manifest
                    candidate-manifest
                    [artifacts (list bundle bundle)])))
     (check-false
      (publication-manifest-valid?
       (struct-copy publication-manifest
                    candidate-manifest
                    [phases (list exported exported)]))))

   (test-case "Rejects credential-bearing publication evidence"
     (for ([publication
            (in-list
             (list (hasheq 'token "hidden")
                   (hasheq 'url "https://user:password@example.invalid/a")
                   (hasheq 'url "https://example.invalid/a?access_token=x")))])
       (check-false
        (publication-manifest-valid?
         (struct-copy publication-manifest
                      candidate-manifest
                      [publication publication]))))
     (define failed-with-secret
       (struct-copy phase-record
                    exported
                    [state 'failed]
                    [failure (hasheq 'authorization "hidden")]))
     (check-false
      (publication-manifest-valid?
       (struct-copy publication-manifest
                    candidate-manifest
                    [phases (list failed-with-secret)]))))

   (test-case "Reports malformed collections without secondary exceptions"
     (check-not-exn
      (lambda ()
        (publication-manifest-errors
         (struct-copy publication-manifest
                      candidate-manifest
                      [artifacts 'invalid]
                      [phases 'invalid])))))))

(define failures (run-tests identity-tests))
(unless (zero? failures)
  (exit 1))
