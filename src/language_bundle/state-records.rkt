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
         "../storage/record-codec.rkt")

(provide
 current-language-bundle-state-format-version
 (struct-out odra-installed-bundle)
 (struct-out odra-activation-lock)
 (struct-out odra-bundle-operation)
 (struct-out odra-bundle-accounting)
 (struct-out odra-language-bundle-state)
 language-bundle-state-checksum
 language-bundle-state-with-checksum
 activation-lock-checksum
 activation-lock-with-checksum
 (contract-out
  [language-bundle-state-reachable-content
   (-> odra-language-bundle-state? (listof string?))]
  [language-bundle-state-garbage-collection-plan
   (-> odra-language-bundle-state? (listof string?) (listof string?))]
  [language-bundle-state->module-bytes
   (-> odra-language-bundle-state? immutable-bytes?)]
  [language-bundle-state-module-format
   (-> path-string? (or/c exact-positive-integer? odra-record-diagnostic?))]
  [language-bundle-state-module-load
   (-> path-string? (or/c odra-language-bundle-state? odra-record-diagnostic?))]))

(define current-language-bundle-state-format-version 2)
(define maximum-bundles 1024)
(define maximum-operations 64)
(define maximum-content-references 16384)
(define digest-pattern #px"^[0-9a-f]{64}$")
(define version-pattern #px"^(?:0|[1-9][0-9]*)\\.(?:0|[1-9][0-9]*)\\.(?:0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?$")
(define lifecycle-states
  '(staged verified installed-disabled enabled-pending active-confirmed
           activation-rejected update-pending rollback-available
           removal-pending removed quarantined))
(define operation-kinds '(refresh install enable disable update rollback remove verify garbage-collect))
(define operation-phases
  '(resolve review acquire verify durable-install prepare validate publish cleanup complete failed))

(define (immutable-bytes? value) (and (bytes? value) (immutable? value)))
(define (digest? value) (and (string? value) (regexp-match? digest-pattern value)))
(define (version? value) (and (string? value) (regexp-match? version-pattern value)))
(define (identity? value)
  (and (string? value) (<= 1 (string-length value) 96)
       (regexp-match? #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$" value)))
(define (copied value) (if (string? value) (record-copied-text value) value))
(define (unique-sorted? values)
  (and (list? values) (equal? values (sort (remove-duplicates values) string<?))))
(define (digest-list? values)
  (and (unique-sorted? values) (<= (length values) maximum-content-references)
       (andmap digest? values)))

(struct odra-installed-bundle
  (id version manifest artifacts dependencies source publisher platform architecture
      authorities authority-provenance lifecycle contribution-generation predecessor pinned?)
  #:transparent
  #:guard
  (lambda (id version manifest artifacts dependencies source publisher platform architecture
              authorities authority-provenance lifecycle contribution-generation predecessor pinned? _)
    (unless (and (identity? id) (version? version) (digest? manifest)
                 (digest-list? artifacts) (unique-sorted? dependencies)
                 (andmap identity? dependencies) (identity? source) (identity? publisher)
                 (memq platform '(darwin linux windows))
                 (memq architecture '(aarch64 x86-64))
                 (unique-sorted? authorities)
                 (andmap identity? authorities)
                 (string? authority-provenance)
                 (memq lifecycle lifecycle-states)
                 (exact-nonnegative-integer? contribution-generation)
                 (or (not predecessor) (version? predecessor))
                 (boolean? pinned?))
      (raise-arguments-error 'odra-installed-bundle "invalid installed bundle record"))
    (values (copied id) (copied version) (copied manifest) (map copied artifacts)
            (map copied dependencies) (copied source) (copied publisher) platform architecture
            (map copied authorities) (copied authority-provenance) lifecycle
            contribution-generation (and predecessor (copied predecessor)) pinned?)))

(struct odra-activation-lock
  (generation state-generation bundles content dependency-digest authority-digest
              contribution-generations checksum)
  #:transparent
  #:guard
  (lambda (generation state-generation bundles content dependency-digest authority-digest
                      contribution-generations checksum _)
    (unless (and (record-u64? generation) (record-u64? state-generation)
                 (hash? bundles) (immutable? bundles) (<= (hash-count bundles) maximum-bundles)
                 (for/and ([(id version) (in-hash bundles)])
                   (and (identity? id) (version? version)))
                 (digest-list? content) (digest? dependency-digest) (digest? authority-digest)
                 (hash? contribution-generations) (immutable? contribution-generations)
                 (for/and ([(id value) (in-hash contribution-generations)])
                   (and (identity? id) (record-u64? value)))
                 (digest? checksum))
      (raise-arguments-error 'odra-activation-lock "invalid activation lock"))
    (values generation state-generation
            (make-immutable-hash (sort (hash->list bundles) string<? #:key car))
            (map copied content) (copied dependency-digest) (copied authority-digest)
            (make-immutable-hash (sort (hash->list contribution-generations) string<? #:key car))
            (copied checksum))))

(struct odra-bundle-operation
  (id kind phase base-state-generation base-lock-generation content temporary-paths
      result cleanup-complete? failure)
  #:transparent
  #:guard
  (lambda (id kind phase base-state-generation base-lock-generation content temporary-paths
              result cleanup-complete? failure _)
    (unless (and (identity? id) (memq kind operation-kinds) (memq phase operation-phases)
                 (exact-nonnegative-integer? base-state-generation)
                 (exact-nonnegative-integer? base-lock-generation)
                 (digest-list? content) (unique-sorted? temporary-paths)
                 (andmap string? temporary-paths) (symbol? result)
                 (boolean? cleanup-complete?) (string? failure))
      (raise-arguments-error 'odra-bundle-operation "invalid bundle operation"))
    (values (copied id) kind phase base-state-generation base-lock-generation
            (map copied content) (map copied temporary-paths) result cleanup-complete?
            (copied failure))))

(struct odra-bundle-accounting
  (bundle-count artifact-count manifest-bytes artifact-bytes quarantine-count)
  #:transparent
  #:guard
  (lambda (bundle-count artifact-count manifest-bytes artifact-bytes quarantine-count _)
    (unless (andmap exact-nonnegative-integer?
                    (list bundle-count artifact-count manifest-bytes artifact-bytes
                          quarantine-count))
      (raise-arguments-error 'odra-bundle-accounting "invalid aggregate accounting"))
    (values bundle-count artifact-count manifest-bytes artifact-bytes quarantine-count)))

(struct odra-language-bundle-state
  (format-version root-id generation confirmed-lock-generation bundles lock previous-lock
                  operations quarantine accounting checksum)
  #:transparent
  #:guard
  (lambda (format-version root-id generation confirmed-lock-generation bundles lock previous-lock
                          operations quarantine accounting checksum _)
    (unless (and (= format-version current-language-bundle-state-format-version)
                 (identity? root-id) (record-u64? generation)
                 (exact-nonnegative-integer? confirmed-lock-generation)
                 (list? bundles) (<= (length bundles) maximum-bundles)
                 (andmap odra-installed-bundle? bundles)
                 (or (not lock) (odra-activation-lock? lock))
                 (or (not previous-lock) (odra-activation-lock? previous-lock))
                 (list? operations) (<= (length operations) maximum-operations)
                 (andmap odra-bundle-operation? operations)
                 (unique-sorted? quarantine) (andmap string? quarantine)
                 (odra-bundle-accounting? accounting) (digest? checksum)
                 (= (odra-bundle-accounting-bundle-count accounting) (length bundles))
                 (= (odra-bundle-accounting-artifact-count accounting)
                    (for/sum ([bundle bundles])
                      (length (odra-installed-bundle-artifacts bundle))))
                 (= (odra-bundle-accounting-quarantine-count accounting)
                    (length quarantine))
                 (let ([bundle-keys
                        (for/list ([bundle bundles])
                          (format "~a@~a" (odra-installed-bundle-id bundle)
                                  (odra-installed-bundle-version bundle)))])
                   (equal? bundle-keys (sort (remove-duplicates bundle-keys) string<?)))
                 (let ([operation-ids (map odra-bundle-operation-id operations)])
                   (= (length operation-ids) (length (remove-duplicates operation-ids)))))
      (raise-arguments-error 'odra-language-bundle-state "invalid installed state"))
    (values format-version (copied root-id) generation confirmed-lock-generation
            (for/list ([value bundles]) value) lock previous-lock
            (for/list ([value operations]) value) (map copied quarantine) accounting
            (copied checksum))))

(define (bundle->datum value)
  (list (odra-installed-bundle-id value) (odra-installed-bundle-version value)
        (odra-installed-bundle-manifest value) (odra-installed-bundle-artifacts value)
        (odra-installed-bundle-dependencies value) (odra-installed-bundle-source value)
        (odra-installed-bundle-publisher value) (odra-installed-bundle-platform value)
        (odra-installed-bundle-architecture value) (odra-installed-bundle-authorities value)
        (odra-installed-bundle-authority-provenance value) (odra-installed-bundle-lifecycle value)
        (odra-installed-bundle-contribution-generation value)
        (odra-installed-bundle-predecessor value) (odra-installed-bundle-pinned? value)))

(define (lock->datum value)
  (and value
       (list (odra-activation-lock-generation value)
             (odra-activation-lock-state-generation value)
             (sort (hash->list (odra-activation-lock-bundles value)) string<? #:key car)
             (odra-activation-lock-content value)
             (odra-activation-lock-dependency-digest value)
             (odra-activation-lock-authority-digest value)
             (sort (hash->list (odra-activation-lock-contribution-generations value)) string<? #:key car)
             (odra-activation-lock-checksum value))))

(define (lock-payload value)
  (drop-right (lock->datum value) 1))

(define (activation-lock-checksum value)
  (bytes->hex-string
   (sha256-bytes (open-input-bytes (record-datum->module-bytes (lock-payload value))))))

(define (activation-lock-with-checksum value)
  (struct-copy odra-activation-lock value
               [checksum (activation-lock-checksum value)]))

(define (operation->datum value)
  (list (odra-bundle-operation-id value) (odra-bundle-operation-kind value)
        (odra-bundle-operation-phase value) (odra-bundle-operation-base-state-generation value)
        (odra-bundle-operation-base-lock-generation value) (odra-bundle-operation-content value)
        (odra-bundle-operation-temporary-paths value) (odra-bundle-operation-result value)
        (odra-bundle-operation-cleanup-complete? value) (odra-bundle-operation-failure value)))

(define (accounting->datum value)
  (list (odra-bundle-accounting-bundle-count value)
        (odra-bundle-accounting-artifact-count value)
        (odra-bundle-accounting-manifest-bytes value)
        (odra-bundle-accounting-artifact-bytes value)
        (odra-bundle-accounting-quarantine-count value)))

(define (state-payload value)
  (list 'language-bundle-state '#:format-version (odra-language-bundle-state-format-version value)
        '#:root-id (odra-language-bundle-state-root-id value)
        '#:generation (odra-language-bundle-state-generation value)
        '#:confirmed-lock-generation (odra-language-bundle-state-confirmed-lock-generation value)
        '#:bundles (map bundle->datum (odra-language-bundle-state-bundles value))
        '#:lock (lock->datum (odra-language-bundle-state-lock value))
        '#:previous-lock (lock->datum (odra-language-bundle-state-previous-lock value))
        '#:operations (map operation->datum (odra-language-bundle-state-operations value))
        '#:quarantine (odra-language-bundle-state-quarantine value)
        '#:accounting (accounting->datum (odra-language-bundle-state-accounting value))))

(define (language-bundle-state-checksum value)
  (bytes->hex-string
   (sha256-bytes (open-input-bytes (record-datum->module-bytes (state-payload value))))))

(define (language-bundle-state-with-checksum value)
  (struct-copy odra-language-bundle-state value
               [checksum (language-bundle-state-checksum value)]))

(define (language-bundle-state->module-bytes value)
  (unless (string=? (odra-language-bundle-state-checksum value)
                    (language-bundle-state-checksum value))
    (raise-arguments-error 'language-bundle-state->module-bytes "invalid checksum"))
  (record-datum->module-bytes
   (append (state-payload value)
           (list '#:checksum (odra-language-bundle-state-checksum value)))))

(define (legacy-state-payload root generation bundles lock)
  (list 'language-bundle-state '#:format-version 1
        '#:root-id root
        '#:generation generation
        '#:bundles (map bundle->datum bundles)
        '#:lock (lock->datum lock)))

(define (legacy-state-checksum root generation bundles lock)
  (bytes->hex-string
   (sha256-bytes
    (open-input-bytes
     (record-datum->module-bytes
      (legacy-state-payload root generation bundles lock))))))

(define (legacy-state->module-bytes root generation bundles lock)
  (record-datum->module-bytes
   (append (legacy-state-payload root generation bundles lock)
           (list '#:checksum
                 (legacy-state-checksum root generation bundles lock)))))

(define (decode-lock datum)
  (and datum (match datum [(list generation state-generation bundles content dependency authority contributions checksum)
                           (odra-activation-lock generation state-generation (make-immutable-hash bundles)
                                                 content dependency authority
                                                 (make-immutable-hash contributions) checksum)])))
(define (decode-bundle datum) (apply odra-installed-bundle datum))
(define (decode-operation datum) (apply odra-bundle-operation datum))
(define (decode-accounting datum) (apply odra-bundle-accounting datum))

(define (migrate-legacy-state root generation bundle-data lock-data checksum)
  (define bundles (map decode-bundle bundle-data))
  (define lock (decode-lock lock-data))
  (unless (string=? checksum (legacy-state-checksum root generation bundles lock))
    (raise-arguments-error 'language-bundle-state "checksum mismatch"))
  (language-bundle-state-with-checksum
   (odra-language-bundle-state
    2 root generation
    (if lock (odra-activation-lock-generation lock) 0)
    bundles lock #f '() '()
    (odra-bundle-accounting
     (length bundles)
     (for/sum ([bundle (in-list bundles)])
       (length (odra-installed-bundle-artifacts bundle)))
     0 0 0)
    (make-string 64 #\0))))

(define (decode-state datum)
  (match datum
    [(list 'language-bundle-state '#:format-version 1 '#:root-id root
           '#:generation generation '#:bundles bundles '#:lock lock
           '#:checksum checksum)
     (migrate-legacy-state root generation bundles lock checksum)]
    [(list 'language-bundle-state '#:format-version 2 '#:root-id root
           '#:generation generation '#:confirmed-lock-generation lock-generation
           '#:bundles bundles '#:lock lock '#:previous-lock previous
           '#:operations operations '#:quarantine quarantine '#:accounting accounting
           '#:checksum checksum)
     (define state
       (odra-language-bundle-state
        2 root generation lock-generation (map decode-bundle bundles)
        (decode-lock lock) (decode-lock previous) (map decode-operation operations)
        quarantine (decode-accounting accounting) checksum))
     (unless (string=? checksum (language-bundle-state-checksum state))
       (raise-arguments-error 'language-bundle-state "checksum mismatch"))
     state]
    [_ (raise-arguments-error 'language-bundle-state "unsupported state schema")]))

(define (decode-state-format datum)
  (match datum
    [(list* 'language-bundle-state '#:format-version
            (? exact-positive-integer? version) _)
     version]
    [_ (raise-arguments-error 'language-bundle-state "unsupported state schema")]))

(define (language-bundle-state-module-format path)
  (record-module-load path decode-state-format))

(define (language-bundle-state-module-load path)
  (record-module-load path decode-state))

(define (language-bundle-state-reachable-content state)
  (define bundle-content
    (for/fold ([reachable (set)])
              ([bundle (in-list (odra-language-bundle-state-bundles state))]
               #:when (or (odra-installed-bundle-pinned? bundle)
                          (not (eq? (odra-installed-bundle-lifecycle bundle)
                                    'removed))))
      (set-union
       reachable
       (list->set
        (cons (odra-installed-bundle-manifest bundle)
              (odra-installed-bundle-artifacts bundle))))))
  (define lock-and-operation-content
    (for/fold ([reachable bundle-content])
              ([owner (in-list
                       (append
                        (filter values
                                (list (odra-language-bundle-state-lock state)
                                      (odra-language-bundle-state-previous-lock state)))
                        (odra-language-bundle-state-operations state)))])
      (set-union
       reachable
       (list->set
        (if (odra-activation-lock? owner)
            (odra-activation-lock-content owner)
            (odra-bundle-operation-content owner))))))
  (sort
   (set->list
    (for/fold ([reachable lock-and-operation-content])
              ([reference (in-list (odra-language-bundle-state-quarantine state))]
               #:when (digest? reference))
      (set-add reachable reference)))
   string<?))

(define (language-bundle-state-garbage-collection-plan state content-store)
  (unless (andmap digest? content-store)
    (raise-argument-error 'language-bundle-state-garbage-collection-plan
                          "a list of SHA-256 digests" content-store))
  (define reachable
    (list->set (language-bundle-state-reachable-content state)))
  (sort
   (set->list (set-subtract (list->set content-store) reachable))
   string<?))

(module+ test-support
  (provide legacy-state->module-bytes))
