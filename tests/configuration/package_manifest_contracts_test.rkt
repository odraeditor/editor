#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/package/manifest-contracts.rkt")

(define digest-a (make-string 64 #\a))
(define digest-b (make-string 64 #\b))
(define source-revision (make-string 40 #\c))
(define linux-x86 (odra-package-target 'linux 'x86-64))
(define linux-arm (odra-package-target 'linux 'aarch64))
(define no-managed-state
  (odra-package-state-compatibility #f #f #f 'none))
(define runtime-dependency
  (odra-package-dependency
   "org.example.runtime" 'required
   (list (odra-package-version-constraint 'compatible-major "1.0.0"))
   "1.0.0" "1.9.0" '(command) #f))
(define entrypoint-artifact
  (odra-package-artifact
   "entrypoint" 'racket-module "main.rkt" digest-a 1024 #f #f
   'racket-extension '()))
(define license-artifact
  (odra-package-artifact
   "license" 'license "LICENSE" digest-b 128 #f #f #f '()))
(define command-contribution
  (odra-package-contribution
   "example-command" 'command '(active-buffer active-region)
   '(buffer text-mutation view)))
(define source-documentation
  (odra-package-documentation 'source "https://packages.example/source"))
(define issue-documentation
  (odra-package-documentation 'issues "https://packages.example/issues"))

(define (proposal #:id [id "org.example.extension"]
                  #:kind [kind 'extension]
                  #:version [version "1.2.3"]
                  #:api-minimum [api-minimum "1.0.0"]
                  #:api-maximum [api-maximum "2.0.0"]
                  #:targets [targets (list linux-x86 linux-arm)]
                  #:dependencies [dependencies (list runtime-dependency)]
                  #:authorities [authorities '(racket-extension project-read)]
                  #:artifacts [artifacts (list entrypoint-artifact license-artifact)]
                  #:entrypoint [entrypoint
                                (odra-package-entrypoint
                                 "main.rkt" 'odra-package-contributions)]
                  #:contributions [contributions (list command-contribution)]
                  #:documentation
                  [documentation (list source-documentation issue-documentation)])
  (odra-package-manifest-proposal
   current-package-manifest-format-version id kind "Example Extension" version
   "Example package manifest fixture" "MIT" "LICENSE" "example.publisher"
   source-revision api-minimum api-maximum targets dependencies authorities
   artifacts entrypoint contributions documentation no-managed-state))

(test-case "manifest confirmation canonicalizes independent ordered records"
  (define-values (manifest rejection) (confirm-package-manifest (proposal)))
  (check-false rejection)
  (check-equal? (odra-package-manifest-targets manifest)
                (list linux-arm linux-x86))
  (check-equal? (odra-package-manifest-authorities manifest)
                '(project-read racket-extension))
  (check-equal? (map odra-package-artifact-path
                     (odra-package-manifest-artifacts manifest))
                '("LICENSE" "main.rkt"))
  (check-equal? (map odra-package-documentation-kind
                     (odra-package-manifest-documentation manifest))
                '(issues source)))

(test-case "canonical manifest bytes bind every confirmed field deterministically"
  (define-values (first first-rejection) (confirm-package-manifest (proposal)))
  (define-values
    (second second-rejection)
    (confirm-package-manifest
     (proposal #:targets (list linux-arm linux-x86)
               #:authorities '(project-read racket-extension)
               #:artifacts (list license-artifact entrypoint-artifact)
               #:documentation (list issue-documentation source-documentation))))
  (check-false first-rejection)
  (check-false second-rejection)
  (check-equal? (package-manifest->canonical-bytes first)
                (package-manifest->canonical-bytes second))
  (check-equal? (package-manifest-digest first)
                (package-manifest-digest second))
  (check-regexp-match #px"^[0-9a-f]{64}$" (package-manifest-digest first)))

(test-case "manifest identity and version exclude mutable repository coordinates"
  (define mutable-id (string-copy "org.example.extension"))
  (define mutable-version (string-copy "1.2.3"))
  (define candidate (proposal #:id mutable-id #:version mutable-version))
  (string-set! mutable-id 0 #\x)
  (string-set! mutable-version 0 #\9)
  (define-values (manifest rejection) (confirm-package-manifest candidate))
  (check-false rejection)
  (check-equal? (odra-package-manifest-package-id manifest)
                "org.example.extension")
  (check-equal? (odra-package-manifest-version manifest) "1.2.3")
  (check-true (immutable? (odra-package-manifest-package-id manifest))))

(test-case "manifest rejects self dependencies and duplicate target identities"
  (define self-dependency
    (odra-package-dependency
     "org.example.extension" 'required
     (list (odra-package-version-constraint 'minimum "1.0.0"))
     "1.0.0" "2.0.0" '() #f))
  (define-values
    (self-manifest self-rejection)
    (confirm-package-manifest (proposal #:dependencies (list self-dependency))))
  (check-false self-manifest)
  (check-eq? (odra-package-manifest-rejection-code self-rejection)
             'self-dependency)
  (define-values
    (target-manifest target-rejection)
    (confirm-package-manifest (proposal #:targets (list linux-x86 linux-x86))))
  (check-false target-manifest)
  (check-eq? (odra-package-manifest-rejection-code target-rejection)
             'duplicate-identity))

(test-case "dependency constraints reject ambiguous and contradictory ranges"
  (check-exn
   exn:fail?
   (lambda ()
     (odra-package-dependency
      "org.example.runtime" 'required
      (list (odra-package-version-constraint 'exact "1.0.0")
            (odra-package-version-constraint 'minimum "1.0.0"))
      "1.0.0" "2.0.0" '() #f)))
  (check-exn
   exn:fail?
   (lambda ()
     (odra-package-dependency
      "org.example.runtime" 'required
      (list (odra-package-version-constraint 'maximum "1.0.0")
            (odra-package-version-constraint 'minimum "2.0.0"))
      "1.0.0" "2.0.0" '() #f))))

(test-case "entrypoints require a declared Racket module and authority"
  (define-values
    (authority-manifest authority-rejection)
    (confirm-package-manifest
     (proposal #:authorities '(project-read))))
  (check-false authority-manifest)
  (check-eq? (odra-package-manifest-rejection-field authority-rejection)
             'authorities)
  (define-values
    (artifact-manifest artifact-rejection)
    (confirm-package-manifest
     (proposal #:artifacts (list license-artifact))))
  (check-false artifact-manifest)
  (check-eq? (odra-package-manifest-rejection-field artifact-rejection)
             'entrypoint))

(test-case "declared contributions cannot exist without an entrypoint"
  (define-values
    (manifest rejection)
    (confirm-package-manifest (proposal #:entrypoint #f)))
  (check-false manifest)
  (check-eq? (odra-package-manifest-rejection-field rejection) 'entrypoint)
  (define-values
    (data-manifest data-rejection)
    (confirm-package-manifest
     (proposal #:entrypoint #f #:contributions '()
               #:authorities '() #:artifacts (list license-artifact))))
  (check-false data-rejection)
  (check-false (odra-package-manifest-entrypoint data-manifest)))

(test-case "package artifacts reject traversal and executable content"
  (for ([path '("/tmp/main.rkt" "../main.rkt" "lib/../main.rkt")])
    (check-exn
     exn:fail?
     (lambda ()
       (odra-package-artifact
        "entrypoint" 'racket-module path digest-a 10 #f #f
        'racket-extension '()))))
  (check-exn
   exn:fail?
   (lambda ()
     (odra-package-artifact
      "entrypoint" 'racket-module "main.rkt" digest-a 10 #f #t
      'racket-extension '()))))

(test-case "managed state policy is explicit or absent as one complete record"
  (define managed
    (odra-package-state-compatibility
     "org.example.state" "1.0.0" "2.0.0" 'preserve))
  (check-equal? (odra-package-state-compatibility-schema-id managed)
                "org.example.state")
  (check-exn
   exn:fail?
   (lambda ()
     (odra-package-state-compatibility
      "org.example.state" #f #f 'preserve))))
