#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/package_catalog/curation-change-classification.rkt"
         "../../src/package_catalog/curation-records.rkt"
         "../../src/package_catalog/curation-submissions.rkt")

(define (digest character) (make-string 64 character))
(define (release package-id publisher source revision artifact dependency
                 compatibility capability contribution builder)
  (odra-package-release-reference
   1 package-id (digest #\9) "1.0.0" publisher source revision #f (digest #\8)
   (list
    (odra-package-artifact-reference
     'linux 'x86-64 '("package.tar.zst") artifact 1024 builder
     "build/1" 'unverified))
   dependency compatibility capability contribution))

(define base
  (release "org.example.package" "org.example.publisher"
           "https://forge.example/org/package" (make-string 40 #\a)
           (digest #\b) (digest #\c) (digest #\d) (digest #\e)
           (digest #\f) "builder-v1"))
(define no-risks (odra-package-risk-profile #f #f #f #f #f))

(define (classes changes)
  (map odra-package-change-summary-class changes))

(test-case "equal releases and risk profiles have no semantic changes"
  (check-equal?
   (classify-package-release-change base no-risks base no-risks) '()))

(test-case "publisher source and build changes remain distinct"
  (define changed
    (release "org.example.package" "org.example.new-publisher"
             "https://forge.example/new/package" (make-string 40 #\b)
             (digest #\b) (digest #\c) (digest #\d) (digest #\e)
             (digest #\f) "builder-v2"))
  (check-equal?
   (classes (classify-package-release-change base no-risks changed no-risks))
   '(publisher source build)))

(test-case "manifest projections classify dependency capability and contribution"
  (define changed
    (struct-copy odra-package-release-reference base
                 [dependency-set-digest (digest #\1)]
                 [compatibility-digest (digest #\2)]
                 [capability-set-digest (digest #\3)]
                 [contribution-set-digest (digest #\4)]))
  (check-equal?
   (classes (classify-package-release-change base no-risks changed no-risks))
   '(dependency compatibility capability contribution)))

(test-case "native foreign process network and filesystem risks are explicit"
  (define risks (odra-package-risk-profile #t #t #t #t #t))
  (define changes
    (classify-package-release-change base no-risks base risks))
  (check-equal? (classes changes) '(native foreign process network filesystem))
  (check-true
   (andmap (lambda (value)
             (eq? (odra-package-change-summary-risk value) 'critical))
           changes)))

(test-case "immutable-version artifact substitution is critical"
  (define changed
    (struct-copy
     odra-package-release-reference base
     [artifact-set
      (list
       (struct-copy odra-package-artifact-reference
                    (car (odra-package-release-reference-artifact-set base))
                    [digest (digest #\1)]))]))
  (define result
    (classify-package-release-change base no-risks changed no-risks))
  (check-equal? (classes result) '(artifact-content))
  (check-eq? (odra-package-change-summary-risk (car result)) 'critical))
