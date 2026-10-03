#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

(require racket/contract/base
         racket/list
         racket/path)

(provide package-resource?
         package-resource-package
         package-resource-name
         package-resource-root
         package-resource-access
         package-resources?
         (contract-out
          [make-package-resource
           (->* (#:package string? #:name symbol? #:root path-string?)
                (#:access (or/c 'read 'read-write)) package-resource?)]))

;; Resources are user configuration, not authority that a package can self-grant.
(struct package-resource (package name root access) #:transparent)

(define (make-package-resource #:package package #:name name #:root root
                               #:access [access 'read])
  (unless (and (regexp-match? #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$" package)
               (<= (string-length package) 128)
               (regexp-match? #px"^[a-z][a-z0-9-]*$" (symbol->string name))
               (<= (string-length (symbol->string name)) 64)
               (complete-path? root)
               (<= (bytes-length (if (path? root) (path->bytes root)
                                    (string->bytes/utf-8 root))) 4096))
    (raise-arguments-error 'make-package-resource
                           "expected a package identity, resource name, and absolute bounded root"))
  (package-resource (string->immutable-string package) name
                    (string->immutable-string (path->string (simplify-path root #f))) access))

;; Each package has one root per named resource; overlapping names are ambiguous.
(define (package-resources? resources)
  (and (list? resources)
       (<= (length resources) 32)
       (andmap package-resource? resources)
       (let ([identities
              (map (lambda (resource)
                     (cons (package-resource-package resource)
                           (package-resource-name resource))) resources)])
         (= (length identities) (length (remove-duplicates identities))))))

(module+ test
  (require rackunit)

  ;; Reject ambiguous or unbounded configuration before a package turn starts.
  (test-case "resource configuration validates identity roots and uniqueness"
    (define root (build-path (find-system-path 'temp-dir) "package-resource"))
    (define resource
      (make-package-resource #:package "example.notes" #:name 'notes #:root root))
    (check-eq? (package-resource-access resource) 'read)
    (check-true (package-resources? (list resource)))
    (check-false (package-resources? (list resource resource)))
    (check-false (package-resources? (make-list 33 resource)))
    (for ([invalid (in-list (list "Example.notes" "../notes" (make-string 129 #\a)))])
      (check-exn exn:fail:contract?
                 (lambda ()
                   (make-package-resource #:package invalid #:name 'notes #:root root))))
    (check-exn exn:fail:contract?
               (lambda ()
                 (make-package-resource #:package "example.notes" #:name 'notes
                                        #:root "relative/notes")))))
