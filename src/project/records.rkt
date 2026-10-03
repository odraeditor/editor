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
 current-local-project-format-version
 current-project-discovery-format-version
 current-promotion-suppressions-format-version
 maximum-promotion-suppressions
 (struct-out odra-local-project-record)
 (struct-out odra-project-discovery-record)
 (struct-out odra-promotion-suppressions-record)
 (contract-out
  [local-project-record
   (-> #:format-version exact-positive-integer?
       #:id string?
       #:generation exact-positive-integer?
       #:name string?
       #:root string?
       #:trust (or/c 'untrusted 'trusted)
       odra-local-project-record?)]
  [project-discovery-record
   (-> #:format-version exact-positive-integer?
       #:id string?
       #:expected-project-generation exact-positive-integer?
       #:root string?
       odra-project-discovery-record?)]
  [promotion-suppressions-record
   (-> #:format-version exact-positive-integer?
       #:generation exact-positive-integer?
       #:dirs (listof string?)
       odra-promotion-suppressions-record?)]
  [local-project-record->module-bytes (-> odra-local-project-record? immutable-bytes?)]
  [project-discovery-record->module-bytes
   (-> odra-project-discovery-record? immutable-bytes?)]
  [promotion-suppressions-record->module-bytes
   (-> odra-promotion-suppressions-record? immutable-bytes?)]
  [local-project-record-module-load
   (-> path-string? (or/c odra-local-project-record? odra-record-diagnostic?))]
  [project-discovery-record-module-load
   (-> path-string? (or/c odra-project-discovery-record? odra-record-diagnostic?))]
  [promotion-suppressions-record-module-load
   (-> path-string? (or/c odra-promotion-suppressions-record?
                          odra-record-diagnostic?))]))

(define current-local-project-format-version 2)
(define current-project-discovery-format-version 1)
(define current-promotion-suppressions-format-version 1)
(define maximum-promotion-suppressions 4096)

(define (immutable-bytes? value)
  (and (bytes? value) (immutable? value)))

(struct odra-local-project-record (format-version id generation name root trust)
  #:transparent
  #:guard
  (lambda (format-version id generation name root trust _)
    (unless (= format-version current-local-project-format-version)
      (raise-arguments-error 'local-project-record "unsupported local Project format"))
    (unless (and (record-identity? id)
                 (record-u64? generation)
                 (record-name? name)
                 (record-path? root)
                 (memq trust '(untrusted trusted)))
      (raise-arguments-error 'local-project-record "invalid local Project record"))
    (values format-version
            (record-copied-text id)
            generation
            (record-copied-text name)
            (record-copied-text root)
            trust)))

(struct odra-project-discovery-record
  (format-version id expected-project-generation root)
  #:transparent
  #:guard
  (lambda (format-version id expected-project-generation root _)
    (unless (= format-version current-project-discovery-format-version)
      (raise-arguments-error 'project-discovery-record
                             "unsupported Project discovery format"))
    (unless (and (record-identity? id)
                 (record-u64? expected-project-generation)
                 (record-path? root))
      (raise-arguments-error 'project-discovery-record
                             "invalid Project discovery record"))
    (values format-version
            (record-copied-text id)
            expected-project-generation
            (record-copied-text root))))

(struct odra-promotion-suppressions-record (format-version generation dirs)
  #:transparent
  #:guard
  (lambda (format-version generation dirs _)
    (unless (= format-version current-promotion-suppressions-format-version)
      (raise-arguments-error 'promotion-suppressions-record
                             "unsupported promotion-suppressions format"))
    (unless (and (record-u64? generation)
                 (list? dirs)
                 (<= (length dirs) maximum-promotion-suppressions)
                 (andmap record-path? dirs)
                 (= (length dirs) (length (remove-duplicates dirs))))
      (raise-arguments-error 'promotion-suppressions-record
                             "invalid promotion-suppressions record"))
    (values format-version generation
            (for/list ([dir (in-list dirs)]) (record-copied-text dir)))))

(define (local-project-record #:format-version format-version
                              #:id id
                              #:generation generation
                              #:name name
                              #:root root
                              #:trust trust)
  (odra-local-project-record format-version id generation name root trust))

(define (project-discovery-record #:format-version format-version
                                  #:id id
                                  #:expected-project-generation generation
                                  #:root root)
  (odra-project-discovery-record format-version id generation root))

(define (promotion-suppressions-record #:format-version format-version
                                       #:generation generation
                                       #:dirs dirs)
  (odra-promotion-suppressions-record format-version generation dirs))

(define (local-project-record->module-bytes record)
  (record-datum->module-bytes
   (list 'local-project
         '#:format-version (odra-local-project-record-format-version record)
         '#:id (odra-local-project-record-id record)
         '#:generation (odra-local-project-record-generation record)
         '#:name (odra-local-project-record-name record)
         '#:root (odra-local-project-record-root record)
         '#:trust (odra-local-project-record-trust record))))

(define (project-discovery-record->module-bytes record)
  (record-datum->module-bytes
   (list 'project-reference
         '#:format-version (odra-project-discovery-record-format-version record)
         '#:id (odra-project-discovery-record-id record)
         '#:expected-project-generation
         (odra-project-discovery-record-expected-project-generation record)
         '#:root (odra-project-discovery-record-root record))))

(define (promotion-suppressions-record->module-bytes record)
  (record-datum->module-bytes
   (list 'promotion-suppressions
         '#:format-version (odra-promotion-suppressions-record-format-version record)
         '#:generation (odra-promotion-suppressions-record-generation record)
         '#:dirs (odra-promotion-suppressions-record-dirs record))))

(define (local-project-record-module-load path)
  (record-module-load path decode-local-project))

(define (project-discovery-record-module-load path)
  (record-module-load path decode-project-discovery))

(define (promotion-suppressions-record-module-load path)
  (record-module-load path decode-promotion-suppressions))

(define (decode-local-project datum)
  (match datum
    [(list 'local-project
           '#:format-version format-version
           '#:id id
           '#:generation generation
           '#:name name
           '#:root root
           '#:trust trust)
     (local-project-record
      #:format-version format-version
      #:id id
      #:generation generation
      #:name name
      #:root root
      #:trust trust)]
    [_ (raise-arguments-error 'local-project-record "invalid closed record shape")]))

(define (decode-project-discovery datum)
  (match datum
    [(list 'project-reference
           '#:format-version format-version
           '#:id id
           '#:expected-project-generation generation
           '#:root root)
     (project-discovery-record
      #:format-version format-version
      #:id id
      #:expected-project-generation generation
      #:root root)]
    [_ (raise-arguments-error 'project-discovery-record "invalid closed record shape")]))

(define (decode-promotion-suppressions datum)
  (match datum
    [(list 'promotion-suppressions
           '#:format-version format-version
           '#:generation generation
           '#:dirs dirs)
     (promotion-suppressions-record
      #:format-version format-version
      #:generation generation
      #:dirs dirs)]
    [_ (raise-arguments-error 'promotion-suppressions-record
                              "invalid closed record shape")]))
