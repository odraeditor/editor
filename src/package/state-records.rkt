#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/contract/base
         racket/list
         racket/match
         racket/set
         racket/string
         "../storage/record-codec.rkt"
         "authority-contract.rkt")

(provide
 current-package-state-format-version
 (struct-out odra-package-release)
 (struct-out odra-package-provenance)
 (struct-out odra-installed-package)
 (struct-out odra-package-activation-lock)
 (struct-out odra-package-operation)
 (struct-out odra-package-accounting)
 (struct-out odra-package-state)
 package-activation-lock-checksum
 package-activation-lock-with-checksum
 package-state-checksum
 package-state-with-checksum
 (contract-out
  [package-state-find
   (-> odra-package-state? string? string? (or/c #f odra-installed-package?))]
  [package-state-reachable-content
   (-> odra-package-state? (listof string?))]
  [package-state-garbage-collection-plan
   (-> odra-package-state? (listof string?) (listof string?))]
  [package-state->module-bytes
   (-> odra-package-state? immutable-bytes?)]
  [package-state-module-format
   (-> path-string? (or/c exact-positive-integer? odra-record-diagnostic?))]
  [package-state-module-load
   (-> path-string? (or/c odra-package-state? odra-record-diagnostic?))]))

(define current-package-state-format-version 1)
(define maximum-packages 4096)
(define maximum-operations 128)
(define maximum-content-references 65536)
(define maximum-dependencies 256)
(define maximum-authorities 16)
(define maximum-failure-bytes 4096)
(define digest-pattern #px"^[0-9a-f]{64}$")
(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
(define version-pattern
  #px"^(?:0|[1-9][0-9]*)\\.(?:0|[1-9][0-9]*)\\.(?:0|[1-9][0-9]*)(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$")
(define lifecycle-states
  '(staged verified installed-disabled enabled-pending active-confirmed
           activation-rejected update-pending rollback-available
           removal-pending removed quarantined))
(define operation-kinds
  '(refresh resolve install enable disable update rollback remove verify
            quarantine garbage-collect))
(define operation-phases
  '(resolve review acquire verify durable-install prepare validate publish
            cleanup complete failed))
(define operation-results '(pending confirmed rejected cancelled failed))

(define (immutable-bytes? value)
  (and (bytes? value) (immutable? value)))

(define (copied-text value)
  (string->immutable-string value))

(define (bounded-text? value maximum #:empty? [empty? #f])
  (and (string? value)
       (or empty? (positive? (string-length value)))
       (not (string-contains? value (string #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (identity? value)
  (and (bounded-text? value 128) (regexp-match? identity-pattern value)))

(define (version? value)
  (and (bounded-text? value 128) (regexp-match? version-pattern value)))

(define (digest? value)
  (and (string? value) (regexp-match? digest-pattern value)))

(define (u64? value)
  (and (exact-nonnegative-integer? value) (<= value (sub1 (expt 2 64)))))

(define (symbol<? left right)
  (string<? (symbol->string left) (symbol->string right)))

(define (unique-sorted? values less?)
  (and (list? values)
       (equal? values (sort (remove-duplicates values) less?))))

(define (digest-list? values)
  (and (unique-sorted? values string<?)
       (<= (length values) maximum-content-references)
       (andmap digest? values)))

(struct odra-package-release (id version)
  #:transparent
  #:guard
  (lambda (id version _)
    (unless (and (identity? id) (version? version))
      (raise-arguments-error 'odra-package-release
                             "invalid exact package release"))
    (values (copied-text id) (copied-text version))))

(define (release-key value)
  (format "~a@~a" (odra-package-release-id value)
          (odra-package-release-version value)))

(define (release<? left right)
  (string<? (release-key left) (release-key right)))

(struct odra-package-provenance
  (kind catalog-id snapshot-digest assertion-id publisher-id source-revision)
  #:transparent
  #:guard
  (lambda (kind catalog-id snapshot-digest assertion-id publisher-id source-revision _)
    (define complete-catalog?
      (and (eq? kind 'catalog) (digest? catalog-id) (digest? snapshot-digest)
           (digest? assertion-id) (identity? publisher-id)
           (and (string? source-revision)
                (regexp-match? #px"^(?:[0-9a-f]{40}|[0-9a-f]{64})$"
                               source-revision))))
    (define complete-manual?
      (and (eq? kind 'manual) (not catalog-id) (digest? snapshot-digest)
           (digest? assertion-id) (identity? publisher-id)
           (or (not source-revision)
               (and (string? source-revision)
                    (regexp-match? #px"^(?:[0-9a-f]{40}|[0-9a-f]{64})$"
                                   source-revision)))))
    (define migrated?
      (and (eq? kind 'migrated-language-bundle)
           (identity? catalog-id) (not snapshot-digest) (not assertion-id)
           (identity? publisher-id) (not source-revision)))
    (define bundled?
      (and (eq? kind 'bundled)
           (identity? catalog-id) (not snapshot-digest) (not assertion-id)
           (identity? publisher-id)
           (and (string? source-revision)
                (regexp-match? #px"^(?:[0-9a-f]{40}|[0-9a-f]{64})$"
                               source-revision))))
    (unless (or complete-catalog? complete-manual? migrated? bundled?)
      (raise-arguments-error 'odra-package-provenance
                             "invalid package provenance"))
    (values kind (and catalog-id (copied-text catalog-id))
            (and snapshot-digest (copied-text snapshot-digest))
            (and assertion-id (copied-text assertion-id))
            (copied-text publisher-id)
            (and source-revision (copied-text source-revision)))))

(struct odra-installed-package
  (id kind version record-generation manifest archive artifacts dependencies
      provenance platform architecture requested-authorities granted-authorities
      authority-provenance lifecycle contribution-generation predecessor pinned?
      automatic-update? state-schema latest-failure)
  #:transparent
  #:guard
  (lambda (id kind version record-generation manifest archive artifacts dependencies
              provenance platform architecture requested-authorities granted-authorities
              authority-provenance lifecycle contribution-generation predecessor pinned?
              automatic-update? state-schema latest-failure _)
    (unless (and (identity? id)
                 (memq kind '(extension language-support))
                 (version? version)
                 (u64? record-generation)
                 (digest? manifest)
                 (or (not archive) (digest? archive))
                 (digest-list? artifacts)
                 (unique-sorted? dependencies release<?)
                 (<= (length dependencies) maximum-dependencies)
                 (andmap odra-package-release? dependencies)
                 (for/and ([dependency (in-list dependencies)])
                   (not (string=? id (odra-package-release-id dependency))))
                 (odra-package-provenance? provenance)
                 (memq platform '(darwin linux windows))
                 (memq architecture '(aarch64 x86-64))
                 (package-authority-set? requested-authorities
                                         #:maximum maximum-authorities)
                 (package-authority-set? granted-authorities
                                         #:maximum maximum-authorities)
                 (for/and ([authority (in-list granted-authorities)])
                   (memq authority requested-authorities))
                 (bounded-text? authority-provenance 4096 #:empty? #t)
                 (memq lifecycle lifecycle-states)
                 (u64? contribution-generation)
                 (or (not predecessor) (version? predecessor))
                 (boolean? pinned?)
                 (boolean? automatic-update?)
                 (or (not state-schema) (identity? state-schema))
                 (bounded-text? latest-failure maximum-failure-bytes #:empty? #t))
      (raise-arguments-error 'odra-installed-package
                             "invalid generic installed package record"))
    (values (copied-text id) kind (copied-text version) record-generation
            (copied-text manifest) (and archive (copied-text archive))
            (map copied-text artifacts) dependencies provenance platform architecture
            requested-authorities granted-authorities (copied-text authority-provenance)
            lifecycle contribution-generation
            (and predecessor (copied-text predecessor)) pinned? automatic-update?
            (and state-schema (copied-text state-schema))
            (copied-text latest-failure))))

(struct odra-package-activation-lock
  (generation state-generation packages content dependency-digest authority-digest
              grant-generations contribution-generations runtime-api-generation checksum)
  #:transparent
  #:guard
  (lambda (generation state-generation packages content dependency-digest authority-digest
                      grant-generations contribution-generations runtime-api-generation checksum _)
    (unless (and (u64? generation)
                 (u64? state-generation)
                 (hash? packages)
                 (immutable? packages)
                 (<= (hash-count packages) maximum-packages)
                 (for/and ([(id version) (in-hash packages)])
                   (and (identity? id) (version? version)))
                 (digest-list? content)
                 (digest? dependency-digest)
                 (digest? authority-digest)
                 (hash? grant-generations)
                 (immutable? grant-generations)
                 (for/and ([(id generation) (in-hash grant-generations)])
                   (and (identity? id) (u64? generation)))
                 (hash? contribution-generations)
                 (immutable? contribution-generations)
                 (for/and ([(id generation) (in-hash contribution-generations)])
                   (and (identity? id) (u64? generation)))
                 (u64? runtime-api-generation)
                 (equal? (sort (hash-keys packages) string<?)
                         (sort (hash-keys grant-generations) string<?))
                 (equal? (sort (hash-keys packages) string<?)
                         (sort (hash-keys contribution-generations) string<?))
                 (digest? checksum))
      (raise-arguments-error 'odra-package-activation-lock
                             "invalid generic package activation lock"))
    (values generation state-generation
            (make-immutable-hash (sort (hash->list packages) string<? #:key car))
            (map copied-text content) (copied-text dependency-digest)
            (copied-text authority-digest)
            (make-immutable-hash
             (sort (hash->list grant-generations) string<? #:key car))
            (make-immutable-hash
             (sort (hash->list contribution-generations) string<? #:key car))
            runtime-api-generation (copied-text checksum))))

(struct odra-package-operation
  (id kind phase base-state-generation base-lock-generation package-releases content
      temporary-refs result cleanup-complete? failure)
  #:transparent
  #:guard
  (lambda (id kind phase base-state-generation base-lock-generation package-releases content
              temporary-refs result cleanup-complete? failure _)
    (unless (and (identity? id)
                 (memq kind operation-kinds)
                 (memq phase operation-phases)
                 (u64? base-state-generation)
                 (u64? base-lock-generation)
                 (unique-sorted? package-releases release<?)
                 (andmap odra-package-release? package-releases)
                 (digest-list? content)
                 (unique-sorted? temporary-refs string<?)
                 (andmap (lambda (value) (bounded-text? value 4096)) temporary-refs)
                 (memq result operation-results)
                 (boolean? cleanup-complete?)
                 (bounded-text? failure maximum-failure-bytes #:empty? #t))
      (raise-arguments-error 'odra-package-operation
                             "invalid generic package operation"))
    (values (copied-text id) kind phase base-state-generation base-lock-generation
            package-releases (map copied-text content) (map copied-text temporary-refs)
            result cleanup-complete? (copied-text failure))))

(struct odra-package-accounting
  (package-count artifact-count manifest-bytes artifact-bytes quarantine-count)
  #:transparent
  #:guard
  (lambda (package-count artifact-count manifest-bytes artifact-bytes quarantine-count _)
    (unless (andmap exact-nonnegative-integer?
                    (list package-count artifact-count manifest-bytes artifact-bytes
                          quarantine-count))
      (raise-arguments-error 'odra-package-accounting
                             "invalid aggregate package accounting"))
    (values package-count artifact-count manifest-bytes artifact-bytes quarantine-count)))

(define (package-key package)
  (format "~a@~a" (odra-installed-package-id package)
          (odra-installed-package-version package)))

(define (lock-package-valid? packages id version current?)
  (for/or ([package (in-list packages)])
    (and (string=? id (odra-installed-package-id package))
         (string=? version (odra-installed-package-version package))
         (if current?
             (eq? 'active-confirmed (odra-installed-package-lifecycle package))
             (memq (odra-installed-package-lifecycle package)
                   '(active-confirmed installed-disabled rollback-available))))))

(struct odra-package-state
  (format-version root-id generation confirmed-lock-generation packages lock
                  previous-lock operations quarantine accounting migration-source checksum)
  #:transparent
  #:guard
  (lambda (format-version root-id generation confirmed-lock-generation packages lock
                          previous-lock operations quarantine accounting migration-source checksum _)
    (define package-keys
      (and (list? packages) (map package-key packages)))
    (define (lock-bounded? value current?)
      (or (not value)
          (and (odra-package-activation-lock? value)
               ((if current? = <=)
                (odra-package-activation-lock-state-generation value)
                generation)
                 (for/and ([(id version)
                          (in-hash (odra-package-activation-lock-packages value))])
                 (lock-package-valid? packages id version current?)))))
    (unless (and (= format-version current-package-state-format-version)
                 (identity? root-id)
                 (u64? generation)
                 (u64? confirmed-lock-generation)
                 (list? packages)
                 (<= (length packages) maximum-packages)
                 (andmap odra-installed-package? packages)
                 (equal? package-keys
                         (sort (remove-duplicates package-keys) string<?))
                 (lock-bounded? lock #t)
                 (lock-bounded? previous-lock #f)
                 (= confirmed-lock-generation
                    (if lock (odra-package-activation-lock-generation lock) 0))
                 (list? operations)
                 (<= (length operations) maximum-operations)
                 (andmap odra-package-operation? operations)
                 (= (length (map odra-package-operation-id operations))
                    (length (remove-duplicates
                             (map odra-package-operation-id operations))))
                 (unique-sorted? quarantine string<?)
                 (andmap (lambda (value) (bounded-text? value 4096)) quarantine)
                 (odra-package-accounting? accounting)
                 (= (odra-package-accounting-package-count accounting)
                    (length packages))
                 (= (odra-package-accounting-artifact-count accounting)
                    (for/sum ([package (in-list packages)])
                      (length (odra-installed-package-artifacts package))))
                 (= (odra-package-accounting-quarantine-count accounting)
                    (length quarantine))
                 (or (not migration-source) (eq? migration-source 'language-bundle-v2))
                 (digest? checksum))
      (raise-arguments-error 'odra-package-state
                             "invalid generic package state"))
    (values format-version (copied-text root-id) generation confirmed-lock-generation
            packages lock previous-lock operations (map copied-text quarantine)
            accounting migration-source (copied-text checksum))))

(define (release->datum value)
  (list (odra-package-release-id value)
        (odra-package-release-version value)))

(define (provenance->datum value)
  (list (odra-package-provenance-kind value)
        (odra-package-provenance-catalog-id value)
        (odra-package-provenance-snapshot-digest value)
        (odra-package-provenance-assertion-id value)
        (odra-package-provenance-publisher-id value)
        (odra-package-provenance-source-revision value)))

(define (package->datum value)
  (list (odra-installed-package-id value)
        (odra-installed-package-kind value)
        (odra-installed-package-version value)
        (odra-installed-package-record-generation value)
        (odra-installed-package-manifest value)
        (odra-installed-package-archive value)
        (odra-installed-package-artifacts value)
        (map release->datum (odra-installed-package-dependencies value))
        (provenance->datum (odra-installed-package-provenance value))
        (odra-installed-package-platform value)
        (odra-installed-package-architecture value)
        (odra-installed-package-requested-authorities value)
        (odra-installed-package-granted-authorities value)
        (odra-installed-package-authority-provenance value)
        (odra-installed-package-lifecycle value)
        (odra-installed-package-contribution-generation value)
        (odra-installed-package-predecessor value)
        (odra-installed-package-pinned? value)
        (odra-installed-package-automatic-update? value)
        (odra-installed-package-state-schema value)
        (odra-installed-package-latest-failure value)))

(define (lock->datum value)
  (and value
       (list (odra-package-activation-lock-generation value)
             (odra-package-activation-lock-state-generation value)
             (sort (hash->list (odra-package-activation-lock-packages value))
                   string<? #:key car)
             (odra-package-activation-lock-content value)
             (odra-package-activation-lock-dependency-digest value)
             (odra-package-activation-lock-authority-digest value)
             (sort (hash->list
                    (odra-package-activation-lock-grant-generations value))
                   string<? #:key car)
             (sort (hash->list
                    (odra-package-activation-lock-contribution-generations value))
                   string<? #:key car)
             (odra-package-activation-lock-runtime-api-generation value)
             (odra-package-activation-lock-checksum value))))

(define (lock-payload value)
  (drop-right (lock->datum value) 1))

(define (package-activation-lock-checksum value)
  (bytes->hex-string
   (sha256-bytes
    (open-input-bytes (record-datum->module-bytes (lock-payload value))))))

(define (package-activation-lock-with-checksum value)
  (struct-copy odra-package-activation-lock value
               [checksum (package-activation-lock-checksum value)]))

(define (operation->datum value)
  (list (odra-package-operation-id value)
        (odra-package-operation-kind value)
        (odra-package-operation-phase value)
        (odra-package-operation-base-state-generation value)
        (odra-package-operation-base-lock-generation value)
        (map release->datum (odra-package-operation-package-releases value))
        (odra-package-operation-content value)
        (odra-package-operation-temporary-refs value)
        (odra-package-operation-result value)
        (odra-package-operation-cleanup-complete? value)
        (odra-package-operation-failure value)))

(define (accounting->datum value)
  (list (odra-package-accounting-package-count value)
        (odra-package-accounting-artifact-count value)
        (odra-package-accounting-manifest-bytes value)
        (odra-package-accounting-artifact-bytes value)
        (odra-package-accounting-quarantine-count value)))

(define (state-payload value)
  (list 'package-state
        '#:format-version (odra-package-state-format-version value)
        '#:root-id (odra-package-state-root-id value)
        '#:generation (odra-package-state-generation value)
        '#:confirmed-lock-generation
        (odra-package-state-confirmed-lock-generation value)
        '#:packages (map package->datum (odra-package-state-packages value))
        '#:lock (lock->datum (odra-package-state-lock value))
        '#:previous-lock (lock->datum (odra-package-state-previous-lock value))
        '#:operations (map operation->datum (odra-package-state-operations value))
        '#:quarantine (odra-package-state-quarantine value)
        '#:accounting (accounting->datum (odra-package-state-accounting value))
        '#:migration-source (odra-package-state-migration-source value)))

(define (package-state-checksum value)
  (bytes->hex-string
   (sha256-bytes
    (open-input-bytes (record-datum->module-bytes (state-payload value))))))

(define (package-state-with-checksum value)
  (struct-copy odra-package-state value
               [checksum (package-state-checksum value)]))

(define (package-state->module-bytes value)
  (unless (string=? (odra-package-state-checksum value)
                    (package-state-checksum value))
    (raise-arguments-error 'package-state->module-bytes
                           "invalid package state checksum"))
  (for ([lock (in-list
               (filter values
                       (list (odra-package-state-lock value)
                             (odra-package-state-previous-lock value))))])
    (unless (string=? (odra-package-activation-lock-checksum lock)
                      (package-activation-lock-checksum lock))
      (raise-arguments-error 'package-state->module-bytes
                             "invalid package activation lock checksum")))
  (record-datum->module-bytes
   (append (state-payload value)
           (list '#:checksum (odra-package-state-checksum value)))))

(define (decode-release value)
  (apply odra-package-release value))

(define (decode-provenance value)
  (apply odra-package-provenance value))

(define (decode-package value)
  (match value
    [(list id kind version record-generation manifest archive artifacts dependencies
           provenance platform architecture requested granted authority-provenance
           lifecycle contribution-generation predecessor pinned? automatic-update?
           state-schema latest-failure)
     (odra-installed-package
      id kind version record-generation manifest archive artifacts
      (map decode-release dependencies) (decode-provenance provenance)
      platform architecture requested granted authority-provenance lifecycle
      contribution-generation predecessor pinned? automatic-update? state-schema
      latest-failure)]))

(define (decode-lock value)
  (and value
       (match value
         [(list generation state-generation packages content dependency authority
                grants contributions runtime-api-generation checksum)
          (define lock
            (odra-package-activation-lock
             generation state-generation (make-immutable-hash packages) content
             dependency authority (make-immutable-hash grants)
             (make-immutable-hash contributions) runtime-api-generation checksum))
          (unless (string=? checksum (package-activation-lock-checksum lock))
            (raise-arguments-error 'package-state
                                   "activation lock checksum mismatch"))
          lock])))

(define (decode-operation value)
  (match value
    [(list id kind phase base-state-generation base-lock-generation releases
           content temporary-refs result cleanup-complete? failure)
     (odra-package-operation
      id kind phase base-state-generation base-lock-generation
      (map decode-release releases) content temporary-refs result cleanup-complete?
      failure)]))

(define (decode-state value)
  (match value
    [(list 'package-state
           '#:format-version format-version
           '#:root-id root-id
           '#:generation generation
           '#:confirmed-lock-generation confirmed-lock-generation
           '#:packages packages
           '#:lock lock
           '#:previous-lock previous-lock
           '#:operations operations
           '#:quarantine quarantine
           '#:accounting accounting
           '#:migration-source migration-source
           '#:checksum checksum)
     (define state
       (odra-package-state
        format-version root-id generation confirmed-lock-generation
        (map decode-package packages) (decode-lock lock) (decode-lock previous-lock)
        (map decode-operation operations) quarantine
        (apply odra-package-accounting accounting) migration-source checksum))
     (unless (string=? checksum (package-state-checksum state))
       (raise-arguments-error 'package-state "package state checksum mismatch"))
     state]
    [_ (raise-arguments-error 'package-state "unsupported package state schema")]))

(define (decode-state-format value)
  (match value
    [(list* 'package-state '#:format-version
            (? exact-positive-integer? version) _)
     version]
    [_ (raise-arguments-error 'package-state "unsupported package state schema")]))

(define (package-state-module-format path)
  (record-module-load path decode-state-format))

(define (package-state-module-load path)
  (record-module-load path decode-state))

(define (package-state-find state id version)
  (for/first ([package (in-list (odra-package-state-packages state))]
              #:when (and (string=? id (odra-installed-package-id package))
                          (string=? version (odra-installed-package-version package))))
    package))

(define (package-content package)
  (append (list (odra-installed-package-manifest package))
          (if (odra-installed-package-archive package)
              (list (odra-installed-package-archive package))
              '())
          (odra-installed-package-artifacts package)))

(define (package-state-reachable-content state)
  (define installed-content
    (for/fold ([reachable (set)])
              ([package (in-list (odra-package-state-packages state))]
               #:when (or (odra-installed-package-pinned? package)
                          (not (eq? 'removed
                                    (odra-installed-package-lifecycle package)))))
      (set-union reachable (list->set (package-content package)))))
  (define lock-and-operation-content
    (for/fold ([reachable installed-content])
              ([owner
                (in-list
                 (append
                  (filter values
                          (list (odra-package-state-lock state)
                                (odra-package-state-previous-lock state)))
                  (odra-package-state-operations state)))])
      (set-union
       reachable
       (list->set
        (if (odra-package-activation-lock? owner)
            (odra-package-activation-lock-content owner)
            (odra-package-operation-content owner))))))
  (sort
   (set->list
    (for/fold ([reachable lock-and-operation-content])
              ([reference (in-list (odra-package-state-quarantine state))]
               #:when (digest? reference))
      (set-add reachable reference)))
   string<?))

(define (package-state-garbage-collection-plan state content-store)
  (unless (and (list? content-store) (andmap digest? content-store))
    (raise-argument-error 'package-state-garbage-collection-plan
                          "a list of SHA-256 digests" content-store))
  (define reachable (list->set (package-state-reachable-content state)))
  (sort (set->list (set-subtract (list->set content-store) reachable)) string<?))
