#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/match
         "../storage/record-codec.rkt")

(provide
 current-workspace-format-version
 maximum-workspace-projects
 (struct-out odra-workspace-project-reference)
 (struct-out odra-workspace-record)
 (contract-out
  [workspace-project-reference
   (-> #:id string?
       #:expected-project-generation exact-positive-integer?
       #:root string?
       odra-workspace-project-reference?)]
  [workspace-record
   (-> #:format-version exact-positive-integer?
       #:id string?
       #:generation exact-positive-integer?
       #:name string?
       #:projects (listof odra-workspace-project-reference?)
       odra-workspace-record?)]
  [workspace-record->module-bytes (-> odra-workspace-record? immutable-bytes?)]
  [workspace-record-module-load
   (-> path-string? (or/c odra-workspace-record? odra-record-diagnostic?))]))

(define current-workspace-format-version 1)
(define maximum-workspace-projects 256)

(define (immutable-bytes? value)
  (and (bytes? value) (immutable? value)))

(struct odra-workspace-project-reference (id expected-project-generation root)
  #:transparent
  #:guard
  (lambda (id expected-project-generation root _)
    (unless (and (record-identity? id)
                 (record-u64? expected-project-generation)
                 (record-path? root))
      (raise-arguments-error 'workspace-project-reference
                             "invalid Workspace Project reference"))
    (values (record-copied-text id)
            expected-project-generation
            (record-copied-text root))))

(struct odra-workspace-record (format-version id generation name projects)
  #:transparent
  #:guard
  (lambda (format-version id generation name projects _)
    (unless (= format-version current-workspace-format-version)
      (raise-arguments-error 'workspace-record "unsupported Workspace format"))
    (unless (and (record-identity? id)
                 (record-u64? generation)
                 (record-name? name)
                 (list? projects)
                 (<= 1 (length projects) maximum-workspace-projects)
                 (andmap odra-workspace-project-reference? projects))
      (raise-arguments-error 'workspace-record "invalid Workspace record"))
    (define project-ids (map odra-workspace-project-reference-id projects))
    (unless (= (length project-ids) (length (remove-duplicates project-ids)))
      (raise-arguments-error 'workspace-record "duplicate Project reference"))
    (values format-version
            (record-copied-text id)
            generation
            (record-copied-text name)
            (for/list ([project (in-list projects)]) project))))

(define (workspace-project-reference #:id id
                                     #:expected-project-generation generation
                                     #:root root)
  (odra-workspace-project-reference id generation root))

(define (workspace-record #:format-version format-version
                          #:id id
                          #:generation generation
                          #:name name
                          #:projects projects)
  (odra-workspace-record format-version id generation name projects))

(define (workspace-record->module-bytes record)
  (record-datum->module-bytes
   (list 'workspace
         '#:format-version (odra-workspace-record-format-version record)
         '#:id (odra-workspace-record-id record)
         '#:generation (odra-workspace-record-generation record)
         '#:name (odra-workspace-record-name record)
         '#:projects
         (for/list ([project (in-list (odra-workspace-record-projects record))])
           (list 'workspace-project
                 '#:id (odra-workspace-project-reference-id project)
                 '#:expected-project-generation
                 (odra-workspace-project-reference-expected-project-generation project)
                 '#:root (odra-workspace-project-reference-root project))))))

(define (workspace-record-module-load path)
  (record-module-load path decode-workspace))

(define (decode-workspace datum)
  (match datum
    [(list 'workspace
           '#:format-version format-version
           '#:id id
           '#:generation generation
           '#:name name
           '#:projects projects)
     (workspace-record
      #:format-version format-version
      #:id id
      #:generation generation
      #:name name
      #:projects (map decode-project-reference projects))]
    [_ (raise-arguments-error 'workspace-record "invalid closed record shape")]))

(define (decode-project-reference datum)
  (match datum
    [(list 'workspace-project
           '#:id id
           '#:expected-project-generation generation
           '#:root root)
     (workspace-project-reference
      #:id id
      #:expected-project-generation generation
      #:root root)]
    [_ (raise-arguments-error 'workspace-project-reference
                              "invalid closed reference shape")]))
