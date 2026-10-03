#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "configuration.rkt")

(define valid-project
  (hasheq 'identity 'site
          'generation 7
          'components '(shared)
          'roots (list (hasheq 'resource "docs"
                               'recursive? #t
                               'include "guide/"
                               'exclude "guide/drafts/"
                               'suffix ".org"))
          'destination "public"
          'action 'build-and-upload
          'backend 'html
          'shared-options (hasheq 'language "en" 'section-numbers? #f)
          'backend-options (hasheq 'stylesheet "site.css")
          'copy-static? #t
          'link-policy 'rewrite-and-validate
          'sitemap "sitemap.xml"
          'index "index.html"
          'cache? #t
          'timestamps? #t
          'remote 'deployment
          'remote-generation 11
          'concurrency 4
          'failure-policy 'stop
          'cleanup? #t
          'retention 3))

(define shared-project
  (hash-set* valid-project
             'identity 'shared
             'components '()
             'action 'build
             'remote #f
             'remote-generation 0
             'sitemap #f
             'index #f))

(define valid-candidate
  (hasheq 'generation 13
          'provider-generation 17
          'projects (list valid-project shared-project)))

(test-case "publishing configuration copies one complete generation"
  (define destination (string-copy "public"))
  (define project (hash-set valid-project 'destination destination))
  (define candidate (hash-set valid-candidate 'projects (list project shared-project)))
  (define admitted (admit-publishing-configuration candidate 12 16))
  (string-set! destination 0 #\P)
  (check-equal? (hash-ref admitted 'generation) 13)
  (check-equal? (hash-ref admitted 'provider-generation) 17)
  (check-equal? (hash-ref (car (hash-ref admitted 'projects)) 'destination) "public"))

(test-case "publishing composition rejects missing and cyclic components"
  (check-false
   (admit-publishing-configuration
    (hash-set valid-candidate 'projects
              (list (hash-set valid-project 'components '(missing)) shared-project))
    12 16))
  (define cyclic-shared (hash-set shared-project 'components '(site)))
  (check-false
   (admit-publishing-configuration
    (hash-set valid-candidate 'projects (list valid-project cyclic-shared))
    12 16)))

(test-case "publishing roots and remote authority remain bounded"
  (define unsafe-root
    (hasheq 'resource "docs" 'recursive? #t 'include "../private"
            'exclude #f 'suffix ".org"))
  (check-false
   (admit-publishing-configuration
    (hash-set valid-candidate 'projects
              (list (hash-set shared-project 'roots (list unsafe-root))))
    12 16))
  (check-false
   (admit-publishing-configuration
    (hash-set valid-candidate 'projects
              (list (hash-set valid-project 'remote-generation 0) shared-project))
    12 16))
  (check-false (admit-publishing-configuration valid-candidate 13 16)))
