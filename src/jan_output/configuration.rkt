#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         racket/match
         racket/string)

(provide publishing-configuration-limits
         admit-publishing-configuration)

;; Publishing configuration remains subordinate to the stable output ceilings.
(define publishing-configuration-limits
  '#hasheq((projects . 256)
           (component-projects . 256)
           (source-roots . 1024)
           (options . 256)
           (configuration-bytes . 16777216)
           (path-bytes . 4096)
           (identity-bytes . 96)
           (option-value-bytes . 65536)
           (concurrency . 256)
           (retention-generations . 4096)))

(define (bounded-text? value maximum)
  (and (string? value)
       (positive? (string-length value))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (bounded-symbol? value maximum)
  (and (symbol? value) (bounded-text? (symbol->string value) maximum)))

(define (copy-text value)
  (string->immutable-string value))

(define (unique? values)
  (= (length values) (length (remove-duplicates values))))

(define (safe-relative-path? value)
  (and (string? value)
       (not (string-prefix? value "/"))
       (not (string=? value ".."))
       (not (string-prefix? value "../"))
       (not (string-contains? value "/../"))
       (not (string-suffix? value "/.."))))

(define (option-value-valid? value)
  (or (and (string? value)
           (<= (bytes-length (string->bytes/utf-8 value))
               (hash-ref publishing-configuration-limits 'option-value-bytes)))
      (boolean? value)
      (symbol? value)
      (exact-integer? value)))

(define (normalize-option-value value)
  (cond
    [(string? value) (copy-text value)]
    [else value]))

(define (normalize-options options)
  (and (hash? options)
       (<= (hash-count options) (hash-ref publishing-configuration-limits 'options))
       (for/and ([(key value) (in-hash options)])
         (and (bounded-symbol? key (hash-ref publishing-configuration-limits 'identity-bytes))
              (option-value-valid? value)))
       (for/hasheq ([(key value) (in-hash options)])
         (values key (normalize-option-value value)))))

(define (normalize-root candidate)
  (match candidate
    [(hash-table ('resource resource)
                 ('recursive? (? boolean? recursive?))
                 ('include include)
                 ('exclude exclude)
                 ('suffix suffix))
     (and (bounded-text? resource (hash-ref publishing-configuration-limits 'path-bytes))
          (or (not include)
              (and (bounded-text? include (hash-ref publishing-configuration-limits 'path-bytes))
                   (safe-relative-path? include)))
          (or (not exclude)
              (and (bounded-text? exclude (hash-ref publishing-configuration-limits 'path-bytes))
                   (safe-relative-path? exclude)))
          (bounded-text? suffix (hash-ref publishing-configuration-limits 'identity-bytes))
          (string-prefix? suffix ".")
          (hasheq 'resource (copy-text resource)
                  'recursive? recursive?
                  'include (and include (copy-text include))
                  'exclude (and exclude (copy-text exclude))
                  'suffix (copy-text suffix)))]
    [_ #f]))

(define (normalize-project candidate)
  (and (hash? candidate)
       (let* ([identity (hash-ref candidate 'identity #f)]
              [generation (hash-ref candidate 'generation #f)]
              [components (hash-ref candidate 'components #f)]
              [roots (hash-ref candidate 'roots #f)]
              [destination (hash-ref candidate 'destination #f)]
              [action (hash-ref candidate 'action #f)]
              [backend (hash-ref candidate 'backend #f)]
              [shared-options (normalize-options (hash-ref candidate 'shared-options #f))]
              [backend-options (normalize-options (hash-ref candidate 'backend-options #f))]
              [copy-static? (hash-ref candidate 'copy-static? #f)]
              [link-policy (hash-ref candidate 'link-policy #f)]
              [sitemap (hash-ref candidate 'sitemap #f)]
              [index (hash-ref candidate 'index #f)]
              [cache? (hash-ref candidate 'cache? #f)]
              [timestamps? (hash-ref candidate 'timestamps? #f)]
              [remote (hash-ref candidate 'remote #f)]
              [remote-generation (hash-ref candidate 'remote-generation #f)]
              [concurrency (hash-ref candidate 'concurrency #f)]
              [failure-policy (hash-ref candidate 'failure-policy #f)]
              [cleanup? (hash-ref candidate 'cleanup? #f)]
              [retention (hash-ref candidate 'retention #f)])
         (and (bounded-symbol? identity (hash-ref publishing-configuration-limits 'identity-bytes))
              (exact-positive-integer? generation)
              (list? components)
              (<= (length components)
                  (hash-ref publishing-configuration-limits 'component-projects))
              (andmap (lambda (component)
                        (bounded-symbol? component
                                         (hash-ref publishing-configuration-limits 'identity-bytes)))
                      components)
              (unique? components)
              (not (memq identity components))
              (list? roots)
              (pair? roots)
              (<= (length roots) (hash-ref publishing-configuration-limits 'source-roots))
              (bounded-text? destination (hash-ref publishing-configuration-limits 'path-bytes))
              (memq action '(build build-and-upload))
              (bounded-symbol? backend (hash-ref publishing-configuration-limits 'identity-bytes))
              shared-options
              backend-options
              (boolean? copy-static?)
              (memq link-policy '(preserve rewrite-relative validate rewrite-and-validate))
              (or (not sitemap)
                  (and (bounded-text? sitemap (hash-ref publishing-configuration-limits 'path-bytes))
                       (safe-relative-path? sitemap)))
              (or (not index)
                  (and (bounded-text? index (hash-ref publishing-configuration-limits 'path-bytes))
                       (safe-relative-path? index)))
              (boolean? cache?)
              (boolean? timestamps?)
              (or (and (eq? action 'build) (not remote)
                       (exact-nonnegative-integer? remote-generation) (zero? remote-generation))
                  (and (eq? action 'build-and-upload)
                       (bounded-symbol? remote
                                        (hash-ref publishing-configuration-limits 'identity-bytes))
                       (exact-positive-integer? remote-generation)))
              (exact-positive-integer? concurrency)
              (<= concurrency (hash-ref publishing-configuration-limits 'concurrency))
              (memq failure-policy '(stop continue))
              (boolean? cleanup?)
              (exact-positive-integer? retention)
              (<= retention (hash-ref publishing-configuration-limits 'retention-generations))
              (let ([normalized-roots (map normalize-root roots)])
                (and (andmap values normalized-roots)
                     (unique? (map (lambda (root) (hash-ref root 'resource)) normalized-roots))
                     (hasheq 'identity identity
                             'generation generation
                             'components components
                             'roots normalized-roots
                             'destination (copy-text destination)
                             'action action
                             'backend backend
                             'shared-options shared-options
                             'backend-options backend-options
                             'copy-static? copy-static?
                             'link-policy link-policy
                             'sitemap (and sitemap (copy-text sitemap))
                             'index (and index (copy-text index))
                             'cache? cache?
                             'timestamps? timestamps?
                             'remote remote
                             'remote-generation remote-generation
                             'concurrency concurrency
                             'failure-policy failure-policy
                             'cleanup? cleanup?
                             'retention retention)))))))

(define (acyclic-projects? projects)
  (define identities (map (lambda (project) (hash-ref project 'identity)) projects))
  (and (for/and ([project (in-list projects)])
         (andmap (lambda (component) (memq component identities))
                 (hash-ref project 'components)))
       (let loop ([remaining projects] [resolved '()])
         (cond
           [(null? remaining) #t]
           [else
            (define ready
              (filter (lambda (project)
                        (andmap (lambda (component) (memq component resolved))
                                (hash-ref project 'components)))
                      remaining))
            (and (pair? ready)
                 (loop (foldl remove remaining ready)
                       (append (map (lambda (project) (hash-ref project 'identity)) ready)
                               resolved)))]))))

(define (configuration-text-bytes value)
  (cond
    [(string? value) (bytes-length (string->bytes/utf-8 value))]
    [(hash? value) (for/sum ([(key item) (in-hash value)])
                     (+ (configuration-text-bytes key) (configuration-text-bytes item)))]
    [(list? value) (for/sum ([item (in-list value)]) (configuration-text-bytes item))]
    [else 0]))

;; Admission validates and copies one complete publishing generation.
(define (admit-publishing-configuration candidate
                                         [confirmed-generation 0]
                                         [confirmed-provider-generation 0])
  (and (hash? candidate)
       (let ([generation (hash-ref candidate 'generation #f)]
             [provider-generation (hash-ref candidate 'provider-generation #f)]
             [projects (hash-ref candidate 'projects #f)])
         (and (exact-positive-integer? generation)
              (> generation confirmed-generation)
              (exact-positive-integer? provider-generation)
              (> provider-generation confirmed-provider-generation)
              (list? projects)
              (pair? projects)
              (<= (length projects) (hash-ref publishing-configuration-limits 'projects))
              (let ([normalized-projects (map normalize-project projects)])
                (and (andmap values normalized-projects)
                     (unique? (map (lambda (project) (hash-ref project 'identity))
                                   normalized-projects))
                     (acyclic-projects? normalized-projects)
                     (let ([result
                            (hasheq 'generation generation
                                    'provider-generation provider-generation
                                    'projects normalized-projects)])
                       (and (<= (configuration-text-bytes result)
                                (hash-ref publishing-configuration-limits
                                          'configuration-bytes))
                            result))))))))
