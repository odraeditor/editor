#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         racket/match
         racket/string)

(provide order-publishing-projects
         discover-publication-sources
         construct-publication-manifest
         advance-publication)

(define semantic-keys '(source dependencies backend filters settings tools))

(define (valid-project? project)
  (and (symbol? (hash-ref project 'identity #f))
       (exact-positive-integer? (hash-ref project 'generation #f))
       (pair? (hash-ref project 'roots '()))
       (member (hash-ref project 'action #f) '(build build-and-upload))
       (symbol? (hash-ref project 'backend #f))
       (positive? (hash-ref project 'concurrency 0))
       (positive? (hash-ref project 'retention 0))
       (or (eq? (hash-ref project 'action) 'build)
           (and (symbol? (hash-ref project 'remote #f))
                (exact-positive-integer? (hash-ref project 'remote-generation #f))))))

(define (order-publishing-projects projects)
  (define identities (map (lambda (project) (hash-ref project 'identity #f)) projects))
  (and (andmap valid-project? projects)
       (= (length identities) (length (remove-duplicates identities)))
       (for/and ([project (in-list projects)])
         (for/and ([component (in-list (hash-ref project 'components '()))])
           (member component identities)))
       (let loop ([remaining projects] [ordered '()])
         (cond
           [(null? remaining) (reverse ordered)]
           [else
            (define ready
              (sort
               (filter (lambda (project)
                         (andmap (lambda (component)
                                   (member component (map (lambda (value) (hash-ref value 'identity)) ordered)))
                                 (hash-ref project 'components '())))
                       remaining)
               symbol<? #:key (lambda (project) (hash-ref project 'identity))))
            (and (pair? ready)
                 (loop (remove (car ready) remaining) (cons (car ready) ordered)))]))))

(define (safe-relative-path? path)
  (and (string? path) (not (string-prefix? path "/"))
       (not (string=? path "..")) (not (string-prefix? path "../"))
       (not (string-contains? path "/../")) (not (string-suffix? path "/.."))))

(define (discover-publication-sources project candidates)
  (define roots (hash-ref project 'roots))
  (define (selected? candidate)
    (define root-index (hash-ref candidate 'root -1))
    (and (<= 0 root-index) (< root-index (length roots))
         (safe-relative-path? (hash-ref candidate 'path #f))
         (let ([root (list-ref roots root-index)] [path (hash-ref candidate 'path)])
           (and (or (not (hash-ref root 'include #f))
                    (string-prefix? path (hash-ref root 'include)))
                (or (not (hash-ref root 'exclude #f))
                    (not (string-prefix? path (hash-ref root 'exclude))))
                (or (string-suffix? path (hash-ref root 'suffix))
                    (and (hash-ref candidate 'static? #f) (hash-ref project 'copy-static? #f)))))))
  (and (= (length candidates)
          (length (remove-duplicates (map (lambda (candidate) (hash-ref candidate 'resource)) candidates))))
       (sort (filter selected? candidates) string<? #:key (lambda (candidate) (hash-ref candidate 'path)))))

(define (reusable? candidate cached)
  (and cached (hash-ref cached 'complete? #f)
       (for/and ([key (in-list semantic-keys)])
         (equal? (hash-ref candidate key #f) (hash-ref cached key #f)))))

(define (construct-publication-manifest project candidates cache existing)
  (define selected (discover-publication-sources project candidates))
  (and selected
       (let* ([entries
               (append
                (for/list ([candidate (in-list selected)])
                  (hasheq 'path (hash-ref candidate 'path)
                          'output (hash-ref candidate 'output)
                          'kind (if (hash-ref candidate 'static? #f) 'static-copy 'generated)
                          'reuse? (and (hash-ref project 'cache? #f)
                                       (reusable? candidate (hash-ref cache (hash-ref candidate 'output) #f)))))
                (if (hash-ref project 'sitemap? #f)
                    (list (hasheq 'path "sitemap.xml" 'output (hash-ref project 'sitemap-output)
                                  'kind 'sitemap 'reuse? #f)) '())
                (if (hash-ref project 'index? #f)
                    (list (hasheq 'path "index.html" 'output (hash-ref project 'index-output)
                                  'kind 'index 'reuse? #f)) '()))]
              [outputs (map (lambda (entry) (hash-ref entry 'output)) entries)]
              [stale
               (for/list ([prior (in-list existing)]
                          #:unless (member (hash-ref prior 'resource) outputs))
                 (hasheq 'resource (hash-ref prior 'resource)
                         'action (if (and (hash-ref prior 'generated? #f)
                                          (eq? (hash-ref prior 'project) (hash-ref project 'identity)))
                                     'delete 'preserve)))])
         (hasheq 'project (hash-ref project 'identity)
                 'entries entries
                 'stale stale
                 'local-state 'candidate
                 'remote-state 'not-started
                 'complete? #t))))

(define (advance-publication run event [count 0])
  (match* ((hash-ref run 'state) event)
    [('prepared 'start-local) (hash-set run 'state 'local-in-progress)]
    [('local-in-progress 'local-succeeded)
     (and (= count (hash-ref run 'entries))
          (hash-set* run 'state 'local-complete 'local count))]
    [('local-complete 'start-remote)
     (and (hash-ref run 'remote? #f)
          (hash-set* run 'state 'remote-in-progress 'attempt (add1 (hash-ref run 'attempt 0))))]
    [('remote-in-progress 'remote-progress)
     (hash-update run 'uploaded (lambda (value) (+ value count)) 0)]
    [('remote-in-progress 'remote-failed)
     (hash-set* run 'state (if (positive? (hash-ref run 'uploaded 0)) 'remote-partial 'retry-ready)
                'failed count)]
    [('remote-partial 'retry)
     (hash-set* run 'state 'remote-in-progress 'failed 0 'attempt (add1 (hash-ref run 'attempt 0)))]
    [('remote-in-progress 'remote-succeeded)
     (and (= count (hash-ref run 'entries))
          (hash-set* run 'state 'published 'uploaded count 'failed 0))]
    [(_ _) #f]))
