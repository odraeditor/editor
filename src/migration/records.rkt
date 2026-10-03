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
 current-migration-journal-format-version
 maximum-migration-entries
 (struct-out odra-migration-entry)
 (struct-out odra-migration-journal-record)
 (contract-out
  [migration-entry
   (-> #:source-id string?
       #:source-path string?
       #:target-id string?
       #:state (or/c 'planned 'staged 'published 'rejected)
       odra-migration-entry?)]
  [migration-journal-record
   (-> #:format-version exact-positive-integer?
       #:generation exact-positive-integer?
       #:entries (listof odra-migration-entry?)
       odra-migration-journal-record?)]
  [migration-journal-record->module-bytes
   (-> odra-migration-journal-record? immutable-bytes?)]
  [migration-journal-record-module-load
   (-> path-string? (or/c odra-migration-journal-record?
                          odra-record-diagnostic?))]))

(define current-migration-journal-format-version 1)
(define maximum-migration-entries 4096)

(define (immutable-bytes? value)
  (and (bytes? value) (immutable? value)))

(struct odra-migration-entry (source-id source-path target-id state)
  #:transparent
  #:guard
  (lambda (source-id source-path target-id state _)
    (unless (and (record-identity? source-id)
                 (record-path? source-path)
                 (record-identity? target-id)
                 (memq state '(planned staged published rejected)))
      (raise-arguments-error 'migration-entry "invalid migration entry"))
    (values (record-copied-text source-id)
            (record-copied-text source-path)
            (record-copied-text target-id)
            state)))

(struct odra-migration-journal-record (format-version generation entries)
  #:transparent
  #:guard
  (lambda (format-version generation entries _)
    (unless (= format-version current-migration-journal-format-version)
      (raise-arguments-error 'migration-journal-record
                             "unsupported migration-journal format"))
    (unless (and (record-u64? generation)
                 (list? entries)
                 (<= (length entries) maximum-migration-entries)
                 (andmap odra-migration-entry? entries))
      (raise-arguments-error 'migration-journal-record
                             "invalid migration-journal record"))
    (define source-ids (map odra-migration-entry-source-id entries))
    (unless (= (length source-ids) (length (remove-duplicates source-ids)))
      (raise-arguments-error 'migration-journal-record
                             "duplicate migration source identity"))
    (values format-version generation (for/list ([entry (in-list entries)]) entry))))

(define (migration-entry #:source-id source-id
                         #:source-path source-path
                         #:target-id target-id
                         #:state state)
  (odra-migration-entry source-id source-path target-id state))

(define (migration-journal-record #:format-version format-version
                                  #:generation generation
                                  #:entries entries)
  (odra-migration-journal-record format-version generation entries))

(define (migration-journal-record->module-bytes record)
  (record-datum->module-bytes
   (list 'migration-journal
         '#:format-version (odra-migration-journal-record-format-version record)
         '#:generation (odra-migration-journal-record-generation record)
         '#:entries
         (for/list ([entry (in-list (odra-migration-journal-record-entries record))])
           (list 'migration-entry
                 '#:source-id (odra-migration-entry-source-id entry)
                 '#:source-path (odra-migration-entry-source-path entry)
                 '#:target-id (odra-migration-entry-target-id entry)
                 '#:state (odra-migration-entry-state entry))))))

(define (migration-journal-record-module-load path)
  (record-module-load path decode-migration-journal))

(define (decode-migration-journal datum)
  (match datum
    [(list 'migration-journal
           '#:format-version format-version
           '#:generation generation
           '#:entries entries)
     (migration-journal-record
      #:format-version format-version
      #:generation generation
      #:entries (map decode-migration-entry entries))]
    [_ (raise-arguments-error 'migration-journal-record "invalid closed record shape")]))

(define (decode-migration-entry datum)
  (match datum
    [(list 'migration-entry
           '#:source-id source-id
           '#:source-path source-path
           '#:target-id target-id
           '#:state state)
     (migration-entry
      #:source-id source-id
      #:source-path source-path
      #:target-id target-id
      #:state state)]
    [_ (raise-arguments-error 'migration-entry "invalid closed entry shape")]))
