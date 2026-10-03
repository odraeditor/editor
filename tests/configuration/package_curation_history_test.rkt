#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/package_catalog/curation-history.rkt"
         "../../src/package_catalog/curation-records.rkt")

(define (digest character) (make-string 64 character))
(define artifact
  (odra-package-artifact-reference
   'linux 'x86-64 '("artifact.tar.zst") (digest #\a) 1024 #f #f 'unverified))
(define (release release-id version artifact-digest)
  (odra-package-release-reference
   1 "org.example.package" release-id version "org.example.publisher"
   "https://forge.example/org/package" (make-string 40 #\b) #f (digest #\c)
   (list (struct-copy odra-package-artifact-reference artifact
                      [digest artifact-digest]))
   (digest #\d) (digest #\e) (digest #\f) (digest #\1)))
(define first-release (release (digest #\2) "1.0.0" (digest #\3)))
(define successor-release (release (digest #\4) "2.0.0" (digest #\5)))

(define (assertion id sequence release status decision snapshot
                   #:first [first 1])
  (odra-package-curation-assertion
   1 id (digest #\6) sequence release decision "policy-v1" status
   (if (eq? status 'admitted) "" (symbol->string status))
   '("assessment-1") first snapshot))

(define admitted
  (assertion (digest #\7) 1 first-release 'admitted "decision-1" 1))

(define (add history candidate)
  (reconcile-package-curation-assertion history candidate))

(test-case "new release history begins as admitted at generation one"
  (define-values (history rejection) (add '() admitted))
  (check-false rejection)
  (check-equal? history (list admitted)))

(test-case "published assertion generations cannot be rewritten"
  (define-values (history first-rejection) (add '() admitted))
  (check-false first-rejection)
  (define-values (unchanged rejection) (add history admitted))
  (check-equal? unchanged history)
  (check-eq? (odra-package-curation-history-failure-code rejection) 'rewrite))

(test-case "deprecation withdrawal quarantine and restoration append history"
  (define transitions '(deprecated quarantined admitted withdrawn admitted))
  (define-values (history _rejection) (add '() admitted))
  (for ([status (in-list transitions)] [sequence (in-naturals 2)])
    (define next
      (assertion (digest #\7) sequence first-release status
                 (format "decision-~a" sequence) sequence))
    (define-values (advanced rejection) (add history next))
    (check-false rejection)
    (set! history advanced))
  (check-equal?
   (map odra-package-curation-assertion-status history)
   '(admitted deprecated quarantined admitted withdrawn admitted)))

(test-case "status changes require a new human decision and snapshot sequence"
  (define-values (history _rejection) (add '() admitted))
  (for ([candidate
         (list
          (assertion (digest #\7) 2 first-release 'deprecated "decision-1" 2)
          (assertion (digest #\7) 2 first-release 'deprecated "decision-2" 1))])
    (define-values (unchanged rejection) (add history candidate))
    (check-equal? unchanged history)
    (check-eq? (odra-package-curation-history-failure-code rejection)
               'stale-generation)))

(test-case "assertion identity cannot be rebound to another release"
  (define-values (history _rejection) (add '() admitted))
  (define candidate
    (assertion (digest #\7) 2 successor-release 'deprecated "decision-2" 2))
  (define-values (unchanged rejection) (add history candidate))
  (check-equal? unchanged history)
  (check-eq? (odra-package-curation-history-failure-code rejection)
             'identity-change))

(test-case "successor releases retain independent assertion histories"
  (define successor
    (assertion (digest #\8) 1 successor-release 'admitted "decision-2" 2
               #:first 2))
  (define-values (first-history _first-rejection) (add '() admitted))
  (define-values (history rejection) (add first-history successor))
  (check-false rejection)
  (check-equal? (package-curation-latest-assertions history)
                (sort (list admitted successor) string<?
                      #:key odra-package-curation-assertion-id)))

(test-case "a release cannot acquire a second assertion identity in one catalog"
  (define duplicate
    (assertion (digest #\9) 1 first-release 'admitted "decision-2" 2
               #:first 2))
  (define-values (history _rejection) (add '() admitted))
  (define-values (unchanged rejection) (add history duplicate))
  (check-equal? unchanged history)
  (check-eq? (odra-package-curation-history-failure-code rejection)
             'duplicate-release))
