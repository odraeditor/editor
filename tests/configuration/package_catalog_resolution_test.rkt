#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/package_catalog/curation-records.rkt"
         "../../src/package_catalog/curation-resolution.rkt")

(define (digest character) (make-string 64 character))
(define catalog-a (digest #\a))
(define catalog-b (digest #\b))

(define (release version release-id artifact-digest
                 #:platform [platform 'linux]
                 #:manifest [manifest (digest #\c)])
  (odra-package-release-reference
   1 "org.example.package" release-id version "org.example.publisher"
   "https://forge.example/org/package" (make-string 40 #\d) #f manifest
   (list
    (odra-package-artifact-reference
     platform 'x86-64 '("artifact.tar.zst") artifact-digest 1024 #f #f
     'unverified))
   (digest #\e) (digest #\f) (digest #\1) (digest #\2)))

(define (assertion catalog id release [status 'admitted])
  (odra-package-curation-assertion
   1 id catalog 1 release "decision-1" "policy-v1" status
   (if (eq? status 'admitted) "" (symbol->string status))
   '() 1 1))

(define (source catalog precedence assertions [snapshot-id (digest #\9)])
  (odra-package-curated-source catalog snapshot-id precedence
                               (sort assertions string<?
                                     #:key odra-package-curation-assertion-id)))

(define (request #:minimum [minimum "0.0.0"]
                 #:maximum [maximum "99.0.0"]
                 #:platform [platform 'linux]
                 #:pin [pin #f])
  (odra-package-resolution-request
   "org.example.package" minimum maximum platform 'x86-64 pin))

(test-case "equivalent artifacts retain distinct curator assertions"
  (define shared (release "1.0.0" (digest #\3) (digest #\4)))
  (define result
    (resolve-curated-package
     (list (source catalog-b 10 (list (assertion catalog-b (digest #\6) shared)))
           (source catalog-a 20 (list (assertion catalog-a (digest #\5) shared))))
     (request)))
  (check-true (odra-package-resolution? result))
  (check-equal? (odra-package-resolution-catalog-ids result)
                (list catalog-a catalog-b))
  (check-equal? (length (odra-package-resolution-assertions result)) 2)
  (check-equal? (odra-package-resolution-selected-catalog-id result) catalog-a)
  (check-equal? (odra-package-curation-assertion-id
                 (odra-package-resolution-selected-assertion result))
                (digest #\5)))

(test-case "precedence then semantic version select deterministically"
  (define low-catalog-high-version
    (release "2.0.0" (digest #\3) (digest #\4)))
  (define high-catalog-low-version
    (release "1.0.0" (digest #\5) (digest #\6)))
  (define sources
    (list
     (source catalog-a 10
             (list (assertion catalog-a (digest #\7)
                              low-catalog-high-version)))
     (source catalog-b 20
             (list (assertion catalog-b (digest #\8)
                              high-catalog-low-version)))))
  (for ([ordered (list sources (reverse sources))])
    (define result (resolve-curated-package ordered (request)))
    (check-equal?
     (odra-package-release-reference-version
      (odra-package-resolution-release result))
     "1.0.0")))

(test-case "highest compatible version wins within one precedence"
  (define first (release "1.9.0" (digest #\3) (digest #\4)))
  (define second (release "2.0.0" (digest #\5) (digest #\6)))
  (define result
    (resolve-curated-package
     (list
      (source catalog-a 10
              (list (assertion catalog-a (digest #\7) first)
                    (assertion catalog-a (digest #\8) second))))
     (request #:maximum "2.0.0")))
  (check-equal?
   (odra-package-release-reference-version
    (odra-package-resolution-release result))
   "2.0.0"))

(test-case "explicit pin selects one catalog but preserves exact validation"
  (define first (release "1.0.0" (digest #\3) (digest #\4)))
  (define second (release "2.0.0" (digest #\5) (digest #\6)))
  (define result
    (resolve-curated-package
     (list (source catalog-a 20 (list (assertion catalog-a (digest #\7) first)))
           (source catalog-b 10 (list (assertion catalog-b (digest #\8) second))))
     (request #:pin catalog-b)))
  (check-equal?
   (odra-package-resolution-catalog-ids result) (list catalog-b)))

(test-case "artifact conflicts are symmetric and cannot be hidden by pins"
  (define first (release "1.0.0" (digest #\3) (digest #\4)))
  (define second (release "1.0.0" (digest #\5) (digest #\6)))
  (define sources
    (list (source catalog-a 100 (list (assertion catalog-a (digest #\7) first)))
          (source catalog-b 1 (list (assertion catalog-b (digest #\8) second)))))
  (for ([ordered (list sources (reverse sources))]
        [pin (list #f catalog-a)])
    (define result (resolve-curated-package ordered (request #:pin pin)))
    (check-true (odra-package-resolution-failure? result))
    (check-eq? (odra-package-resolution-failure-code result)
               'artifact-identity-conflict)
    (check-equal? (odra-package-resolution-failure-catalog-ids result)
                  (list catalog-a catalog-b))))

(test-case "withdrawn and quarantined assertions never contribute candidates"
  (for ([status '(withdrawn quarantined)])
    (define candidate (release "1.0.0" (digest #\3) (digest #\4)))
    (define result
      (resolve-curated-package
       (list (source catalog-a 10
                     (list (assertion catalog-a (digest #\7)
                                      candidate status))))
       (request)))
    (check-eq? (odra-package-resolution-failure-code result) 'no-candidate)))

(test-case "deprecated exact artifacts remain attributable"
  (define candidate (release "1.0.0" (digest #\3) (digest #\4)))
  (define result
    (resolve-curated-package
     (list (source catalog-a 10
                   (list (assertion catalog-a (digest #\7)
                                    candidate 'deprecated))))
     (request)))
  (check-eq? (odra-package-resolution-curation-status result) 'deprecated))

(test-case "platform selectors are exact"
  (define candidate
    (release "1.0.0" (digest #\3) (digest #\4) #:platform 'darwin))
  (define result
    (resolve-curated-package
     (list (source catalog-a 10
                   (list (assertion catalog-a (digest #\7) candidate))))
     (request)))
  (check-eq? (odra-package-resolution-failure-code result) 'no-candidate))
