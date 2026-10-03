#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/file
         racket/list
         racket/path
         "durable-file.rkt"
         "record-codec.rkt")

(provide
 default-record-catalog-entries
 maximum-record-catalog-entries
 record-publication-reject
 (struct-out odra-record-publication)
 (struct-out odra-record-publication-failure)
 (struct-out odra-record-catalog-rejection)
 (struct-out odra-record-catalog)
 (contract-out
  [record-persist
   (->* (symbol? path-string? any/c procedure? procedure? procedure?)
        (#:owned-root (or/c #f path-string?)
         #:validate-generation procedure?)
        (or/c odra-record-publication? odra-record-publication-failure?))]
  [record-catalog-load
   (-> path-string? exact-positive-integer? procedure? procedure? procedure? symbol?
       string? odra-record-catalog?)]))

(define default-record-catalog-entries 128)
(define maximum-record-catalog-entries 1024)
(define allowed-publications
  '(not-published published-durable published-durability-uncertain))
(define allowed-failure-codes
  '(invalid-root invalid-target unsafe-permissions invalid-generation
                 stale-generation temporary-name-limit create-failed
                 write-failed file-sync-failed validation-failed rename-failed
                 directory-sync-failed cleanup-failed))
(define allowed-rejection-codes
  '(catalog-limit catalog-io noncanonical-filename invalid-entry-type
                  filename-mismatch invalid-record duplicate-identity
                  duplicate-root duplicate-name))

(define (bounded-path? value)
  (and (string? value)
       (positive? (string-length value))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum-record-path-bytes)))

(define (bounded-message? value)
  (and (string? value)
       (positive? (string-length value))
       (<= (bytes-length (string->bytes/utf-8 value))
           maximum-record-diagnostic-bytes)))

(struct odra-record-publication
  (kind publication target generation file-synced? directory-synced?)
  #:transparent
  #:guard
  (lambda (kind publication target generation file-synced? directory-synced? _)
    (unless (and (symbol? kind)
                 (memq publication '(published-durable published-durability-uncertain))
                 (bounded-path? target)
                 (record-u64? generation)
                 (boolean? file-synced?)
                 (boolean? directory-synced?))
      (raise-arguments-error 'odra-record-publication "invalid record publication"))
    (values kind publication (record-copied-text target) generation
            file-synced? directory-synced?)))

(struct odra-record-publication-failure
  (kind code message target recovery-path publication platform-code)
  #:transparent
  #:guard
  (lambda (kind code message target recovery-path publication platform-code _)
    (unless (and (symbol? kind)
                 (memq code allowed-failure-codes)
                 (bounded-message? message)
                 (bounded-path? target)
                 (or (string=? recovery-path "") (bounded-path? recovery-path))
                 (memq publication allowed-publications)
                 (exact-nonnegative-integer? platform-code))
      (raise-arguments-error 'odra-record-publication-failure
                             "invalid record publication failure"))
    (values kind code (record-copied-text message)
            (record-copied-text target)
            (record-copied-text recovery-path)
            publication
            platform-code)))

(struct odra-record-catalog-rejection (source code message)
  #:transparent
  #:guard
  (lambda (source code message _)
    (unless (and (bounded-path? source)
                 (memq code allowed-rejection-codes)
                 (bounded-message? message))
      (raise-arguments-error 'odra-record-catalog-rejection
                             "invalid record catalog rejection"))
    (values (record-copied-text source) code (record-copied-text message))))

(struct odra-record-catalog (records rejections examined-entries evaluated-bytes)
  #:transparent
  #:guard
  (lambda (records rejections examined-entries evaluated-bytes _)
    (unless (and (list? records)
                 (list? rejections)
                 (andmap odra-record-catalog-rejection? rejections)
                 (<= (length records) maximum-record-catalog-entries)
                 (<= (length rejections) maximum-record-catalog-entries)
                 (exact-nonnegative-integer? examined-entries)
                 (exact-nonnegative-integer? evaluated-bytes))
      (raise-arguments-error 'odra-record-catalog "invalid bounded record catalog"))
    (values records rejections examined-entries evaluated-bytes)))

(struct exn:fail:record-publication exn:fail
  (code target recovery-path publication platform-code)
  #:transparent)

(define (record-persist kind target record encode load generation-of
                        #:owned-root [owned-root #f]
                        #:validate-generation
                        [validate-record-generation validate-generation])
  (define complete-target (path->complete-path target))
  (define parent (path-only complete-target))
  (with-handlers
      ([exn:fail:record-publication?
        (lambda (failure) (failure-result kind failure))]
       [exn:fail?
        (lambda (failure)
          (publication-failure kind 'validation-failed (exn-message failure)
                               complete-target))])
    (validate-record-generation complete-target record load generation-of)
    (define module-bytes (encode record))
    (define result
      (durable-file-publish
       complete-target
       module-bytes
       #:private-directories
       (if owned-root (list owned-root parent) (list parent))
       #:validate-stage (lambda (stage) (equal? (load stage) record))))
    (durable-result->record-result kind record generation-of result)))

(define (durable-result->record-result kind record generation-of result)
  (cond
    [(odra-durable-file-failure? result)
     (odra-record-publication-failure
      kind
      (odra-durable-file-failure-code result)
      (bounded-message (odra-durable-file-failure-message result))
      (odra-durable-file-failure-target result)
      (odra-durable-file-failure-recovery-path result)
      (odra-durable-file-failure-publication result)
      (odra-durable-file-failure-platform-code result))]
    [(eq? (odra-durable-file-publication-publication result)
          'published-durability-uncertain)
     (odra-record-publication-failure
      kind
      'directory-sync-failed
      "Record was replaced but parent durability is uncertain"
      (odra-durable-file-publication-target result)
      ""
      'published-durability-uncertain
      (odra-durable-file-publication-platform-code result))]
    [else
     (odra-record-publication
      kind
      'published-durable
      (odra-durable-file-publication-target result)
      (generation-of record)
      (odra-durable-file-publication-file-synced? result)
      (odra-durable-file-publication-directory-synced? result))]))

(define (validate-generation target candidate load generation-of)
  (define candidate-generation (generation-of candidate))
  (cond
    [(file-exists? target)
     (define current (load target))
     (when (odra-record-diagnostic? current)
       (raise-publication 'validation-failed "Existing record cannot be validated" target))
     (unless (= candidate-generation (add1 (generation-of current)))
       (raise-publication 'invalid-generation
                          "Updated record generation must increment once" target))]
    [(not (= candidate-generation 1))
     (raise-publication 'invalid-generation
                        "New records begin at generation one" target)]))

(define (record-publication-reject code message target)
  (raise-publication code message (path->complete-path target)))

(define (record-catalog-load root maximum-entries load id-of conflict-key-of
                             conflict-code conflict-message)
  (unless (<= maximum-entries maximum-record-catalog-entries)
    (raise-argument-error 'record-catalog-load
                          (format "an entry limit no greater than ~a"
                                  maximum-record-catalog-entries)
                          maximum-entries))
  (define complete-root (path->complete-path root))
  (cond
    [(not (directory-exists? complete-root)) (odra-record-catalog '() '() 0 0)]
    [(link-exists? complete-root)
     (catalog-with-rejection complete-root 'catalog-io
                             "Catalog root is a symbolic link")]
    [else
     (with-handlers ([exn:fail:filesystem?
                      (lambda (failure)
                        (catalog-with-rejection complete-root 'catalog-io
                                                (exn-message failure)))])
       (define paths (sort (directory-list complete-root #:build? #t) path-string<?))
       (if (> (length paths) maximum-entries)
           (catalog-with-rejection complete-root 'catalog-limit
                                   "Record catalog exceeds its entry limit"
                                   (add1 maximum-entries))
           (build-catalog paths load id-of conflict-key-of
                          conflict-code conflict-message))) ]))

(define (build-catalog paths load id-of conflict-key-of conflict-code conflict-message)
  (define-values (records rejections evaluated-bytes)
    (for/fold ([records '()] [rejections '()] [evaluated-bytes 0])
              ([path (in-list paths)])
      (define-values (record rejection bytes) (load-catalog-path path load id-of))
      (values (if record (cons (cons path record) records) records)
              (if rejection (cons rejection rejections) rejections)
              (+ evaluated-bytes bytes))))
  (define identity-counts
    (for/fold ([counts (hash)]) ([candidate (in-list records)])
      (define id (id-of (cdr candidate)))
      (hash-set counts id (add1 (hash-ref counts id 0)))))
  (define conflict-counts
    (for/fold ([counts (hash)]) ([candidate (in-list records)])
      (define key (conflict-key-of (cdr candidate)))
      (hash-set counts key (add1 (hash-ref counts key 0)))))
  (define-values (accepted duplicate-rejections)
    (for/fold ([accepted '()] [rejections '()]) ([candidate (in-list records)])
      (define source (car candidate))
      (define record (cdr candidate))
      (define id (id-of record))
      (define conflict-key (conflict-key-of record))
      (cond
        [(> (hash-ref identity-counts id) 1)
         (values accepted
                 (cons (catalog-rejection source 'duplicate-identity
                                          "Duplicate record identity")
                       rejections))]
        [(> (hash-ref conflict-counts conflict-key) 1)
         (values accepted
                 (cons (catalog-rejection source conflict-code conflict-message)
                       rejections))]
        [else (values (cons record accepted) rejections)])))
  (odra-record-catalog
   (sort accepted (lambda (left right) (string<? (id-of left) (id-of right))))
   (sort (append rejections duplicate-rejections)
         (lambda (left right)
           (string<? (odra-record-catalog-rejection-source left)
                     (odra-record-catalog-rejection-source right))))
   (length paths)
   evaluated-bytes))

(define (load-catalog-path path load id-of)
  (define filename (path->string (file-name-from-path path)))
  (define filename-id (record-filename-id filename))
  (cond
    [(not filename-id)
     (values #f (catalog-rejection path 'noncanonical-filename
                                   "Noncanonical record filename") 0)]
    [(or (link-exists? path) (not (file-exists? path)))
     (values #f (catalog-rejection path 'invalid-entry-type
                                   "Catalog entry is not a regular file") 0)]
    [else
     (define loaded (load path))
     (cond
       [(odra-record-diagnostic? loaded)
        (values #f
                (catalog-rejection path 'invalid-record
                                   (odra-record-diagnostic-message loaded))
                0)]
       [(not (string=? filename-id (id-of loaded)))
        (values #f (catalog-rejection path 'filename-mismatch
                                      "Record identity does not match filename") 0)]
       [else (values loaded #f (file-size path))])]))

(define (record-filename-id filename)
  (define matched (regexp-match #px"^([a-z0-9]+(?:-[a-z0-9]+)*)[.]rkt$" filename))
  (and matched (cadr matched)))

(define (catalog-with-rejection root code message [examined 0])
  (odra-record-catalog '() (list (catalog-rejection root code message)) examined 0))

(define (catalog-rejection source code message)
  (odra-record-catalog-rejection (path->string source) code (bounded-message message)))

(define (path-string<? left right)
  (string<? (path->string left) (path->string right)))

(define (raise-publication code message target
                           [recovery #f]
                           [publication 'not-published]
                           [platform-code 0])
  (raise
   (exn:fail:record-publication
    message
    (current-continuation-marks)
    code
    (path->string target)
    (if recovery (path->string recovery) "")
    publication
    platform-code)))

(define (failure-result kind failure)
  (odra-record-publication-failure
   kind
   (exn:fail:record-publication-code failure)
   (bounded-message (exn-message failure))
   (exn:fail:record-publication-target failure)
   (exn:fail:record-publication-recovery-path failure)
   (exn:fail:record-publication-publication failure)
   (exn:fail:record-publication-platform-code failure)))

(define (publication-failure kind code message target
                             [recovery #f]
                             [publication 'not-published]
                             [platform-code 0])
  (odra-record-publication-failure
   kind code (bounded-message message) (path->string target)
   (if recovery (path->string recovery) "") publication platform-code))

(define (bounded-message message)
  (define bytes (string->bytes/utf-8 message))
  (if (<= (bytes-length bytes) maximum-record-diagnostic-bytes)
      message
      (bytes->string/utf-8
       (subbytes bytes 0 maximum-record-diagnostic-bytes)
       #\uFFFD)))
