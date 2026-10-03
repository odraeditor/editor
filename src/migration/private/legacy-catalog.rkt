#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/file
         racket/list
         racket/path
         racket/string
         "legacy-records.rkt")

(provide
 default-project-catalog-entries
 maximum-project-catalog-entries
 (struct-out odra-project-catalog-descriptor)
 (struct-out odra-project-catalog-rejection)
 (struct-out odra-project-catalog-entry)
 (struct-out odra-project-catalog)
 (contract-out
  [project-catalog-name-key (-> string? string?)]
  [project-record-filename-id (-> path-string? (or/c string? #f))]
  [project-catalog-load
   (->* (path-string?)
        (#:maximum-entries exact-positive-integer?)
        odra-project-catalog?)]
  [project-catalog-list (-> odra-project-catalog? (listof odra-project-catalog-descriptor?))]
  [project-catalog-rejected
   (-> odra-project-catalog? (listof odra-project-catalog-rejection?))]
  [project-catalog-resolve-id
   (-> odra-project-catalog? string? (or/c odra-project-catalog-descriptor? #f))]
  [project-catalog-resolve-name
   (-> odra-project-catalog? string? (or/c odra-project-catalog-descriptor? #f))]
  [project-catalog-generation
   (-> odra-project-catalog? exact-positive-integer?)]
  [project-catalog-resolve-exact-single-directory
   (-> odra-project-catalog? string? (listof odra-project-catalog-entry?))]))

(define default-project-catalog-entries 128)
(define maximum-project-catalog-entries 1024)
(define allowed-rejection-codes
  '(catalog-io catalog-limit noncanonical-filename invalid-entry-type
               filename-mismatch duplicate-identity duplicate-name
               record-size invalid-language invalid-encoding invalid-syntax
               invalid-schema unsupported-version io))
(define fnv-offset 14695981039346656037)
(define fnv-prime 1099511628211)
(define u64-mask (sub1 (expt 2 64)))

(define (bounded-text? value maximum [empty-allowed? #f])
  (and (string? value)
       (or empty-allowed? (positive? (string-length value)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (copied-text value)
  (string->immutable-string value))

(struct odra-project-catalog-descriptor
  (id generation name directory-count source)
  #:transparent
  #:guard
  (lambda (id generation name directory-count source _)
    (unless (and (bounded-text? id maximum-project-identity-bytes)
                 (exact-positive-integer? generation)
                 (bounded-text? name maximum-project-name-bytes)
                 (exact-positive-integer? directory-count)
                 (<= directory-count maximum-project-directories)
                 (bounded-text? source maximum-project-path-bytes))
      (raise-arguments-error
       'odra-project-catalog-descriptor
       "invalid copied Project catalog descriptor"
       "id" id
       "generation" generation
       "directory-count" directory-count))
    (values (copied-text id) generation (copied-text name) directory-count
            (copied-text source))))

(struct odra-project-catalog-rejection (source filename code message provenance)
  #:transparent
  #:guard
  (lambda (source filename code message provenance _)
    (unless (and (bounded-text? source maximum-project-path-bytes)
                 (bounded-text? filename maximum-project-path-bytes #t)
                 (memq code allowed-rejection-codes)
                 (bounded-text? message maximum-project-diagnostic-bytes)
                 (odra-project-provenance? provenance))
      (raise-arguments-error
       'odra-project-catalog-rejection
       "invalid copied Project catalog rejection"
       "source" source
       "code" code))
    (values (copied-text source) (copied-text filename) code
            (copied-text message) provenance)))

(struct odra-project-catalog-entry (descriptor proposal)
  #:transparent
  #:guard
  (lambda (descriptor proposal _)
    (unless (and (odra-project-catalog-descriptor? descriptor)
                 (odra-project-proposal? proposal))
      (raise-arguments-error
       'odra-project-catalog-entry
       "invalid copied Project catalog entry"))
    (values descriptor proposal)))

(struct odra-project-catalog
  (entries rejections identity-index name-index examined-entries evaluated-bytes)
  #:transparent
  #:guard
  (lambda (entries rejections identity-index name-index examined-entries evaluated-bytes _)
    (unless (and (list? entries)
                 (andmap odra-project-catalog-entry? entries)
                 (<= (length entries) maximum-project-catalog-entries)
                 (list? rejections)
                 (andmap odra-project-catalog-rejection? rejections)
                 (<= (length rejections) maximum-project-catalog-entries)
                 (hash? identity-index)
                 (immutable? identity-index)
                 (hash? name-index)
                 (immutable? name-index)
                 (exact-nonnegative-integer? examined-entries)
                 (exact-nonnegative-integer? evaluated-bytes))
      (raise-arguments-error
       'odra-project-catalog
       "invalid bounded Project catalog"
       "entry-count" (if (list? entries) (length entries) entries)
       "rejection-count" (if (list? rejections) (length rejections) rejections)))
    (values entries rejections identity-index name-index examined-entries evaluated-bytes)))

;; project-catalog-name-key defines the stable built-in comparison key.
(define (project-catalog-name-key name)
  (string->immutable-string (string-foldcase (string-normalize-nfc name))))

;; project-record-filename-id accepts only one canonical Project record name.
(define (project-record-filename-id filename)
  (define name (if (path? filename) (path->string filename) filename))
  (define matched
    (regexp-match #px"^([a-z0-9]+(?:-[a-z0-9]+)*)[.]rkt$" name))
  (and matched (copied-text (cadr matched))))

;; project-catalog-load reads only a bounded set of immediate directory entries.
(define (project-catalog-load projects-directory
                              #:maximum-entries
                              [maximum-entries default-project-catalog-entries])
  (unless (<= maximum-entries maximum-project-catalog-entries)
    (raise-argument-error
     'project-catalog-load
     (format "an entry limit no greater than ~a" maximum-project-catalog-entries)
     maximum-entries))
  (define root (path->complete-path projects-directory))
  (cond
    [(directory-exists? root)
     (with-handlers ([exn:fail:filesystem?
                      (lambda (failure)
                        (catalog-with-root-rejection root 'catalog-io
                                                     (exn-message failure)))])
       (define paths (bounded-directory-entries root maximum-entries))
       (if (eq? paths 'limit-exceeded)
           (catalog-with-root-rejection
            root
            'catalog-limit
            (format "Project catalog exceeds the entry limit of ~a" maximum-entries)
            (add1 maximum-entries))
           (build-catalog paths)))]
    [(or (file-exists? root) (link-exists? root))
     (catalog-with-root-rejection
      root 'invalid-entry-type "Project catalog path is not a directory")]
    [else (empty-catalog)]))

(define (bounded-directory-entries root maximum-entries)
  (define-values (more? next)
    (sequence-generate (in-directory root (lambda (_) #f))))
  (let loop ([paths '()] [count 0])
    (cond
      [(not (more?)) (sort paths path-string<?)]
      [(= count maximum-entries) 'limit-exceeded]
      [else (loop (cons (next) paths) (add1 count))])))

(define (path-string<? left right)
  (string<? (path->string left) (path->string right)))

(define (build-catalog paths)
  (define-values (candidates initial-rejections evaluated-bytes)
    (for/fold ([candidates '()] [rejections '()] [evaluated-bytes 0])
              ([path (in-list paths)])
      (define loaded (load-catalog-candidate path))
      (if (odra-project-catalog-entry? loaded)
          (values (cons loaded candidates)
                  rejections
                  (+ evaluated-bytes
                     (bytes-length
                      (odra-project-proposal-module-bytes
                       (odra-project-catalog-entry-proposal loaded)))))
          (values candidates (cons loaded rejections) evaluated-bytes))))
  (define identity-counts
    (group-counts candidates
                  (lambda (entry)
                    (odra-project-catalog-descriptor-id
                     (odra-project-catalog-entry-descriptor entry)))))
  (define name-counts
    (group-counts candidates
                  (lambda (entry)
                    (project-catalog-name-key
                     (odra-project-catalog-descriptor-name
                      (odra-project-catalog-entry-descriptor entry))))))
  (define-values (accepted conflict-rejections)
    (for/fold ([accepted '()] [rejections '()])
              ([entry (in-list candidates)])
      (define descriptor (odra-project-catalog-entry-descriptor entry))
      (define id (odra-project-catalog-descriptor-id descriptor))
      (define name-key
        (project-catalog-name-key (odra-project-catalog-descriptor-name descriptor)))
      (cond
        [(> (hash-ref identity-counts id) 1)
         (values accepted
                 (cons (entry-rejection entry 'duplicate-identity
                                        "Duplicate Project identity")
                       rejections))]
        [(> (hash-ref name-counts name-key) 1)
         (values accepted
                 (cons (entry-rejection entry 'duplicate-name
                                        "Duplicate Project display name")
                       rejections))]
        [else (values (cons entry accepted) rejections)])))
  (define ordered-entries (sort accepted catalog-entry<?))
  (define ordered-rejections
    (sort (append initial-rejections conflict-rejections) catalog-rejection<?))
  (define identity-index
    (make-immutable-hash
     (for/list ([entry (in-list ordered-entries)])
       (define descriptor (odra-project-catalog-entry-descriptor entry))
       (cons (odra-project-catalog-descriptor-id descriptor) descriptor))))
  (define name-index
    (make-immutable-hash
     (for/list ([entry (in-list ordered-entries)])
       (define descriptor (odra-project-catalog-entry-descriptor entry))
       (cons (project-catalog-name-key
              (odra-project-catalog-descriptor-name descriptor))
             descriptor))))
  (odra-project-catalog ordered-entries ordered-rejections identity-index name-index
                        (length paths) evaluated-bytes))

(define (load-catalog-candidate path)
  (define source (path->string path))
  (define filename (path->string (file-name-from-path path)))
  (define filename-id (project-record-filename-id filename))
  (cond
    [(not filename-id)
     (catalog-rejection source filename 'noncanonical-filename
                        "Entry is not a canonical Project record filename")]
    [(or (link-exists? path) (not (file-exists? path)))
     (catalog-rejection source filename 'invalid-entry-type
                        "Canonical Project record entry is not a regular file")]
    [else
     (define loaded (project-record-module-load path))
     (cond
       [(odra-project-diagnostic? loaded)
        (odra-project-catalog-rejection
         source filename
         (odra-project-diagnostic-code loaded)
         (bounded-message (odra-project-diagnostic-message loaded))
         (odra-project-diagnostic-provenance loaded))]
       [else
        (define record (odra-project-proposal-record loaded))
        (if (string=? filename-id (odra-project-record-id record))
            (odra-project-catalog-entry
             (odra-project-catalog-descriptor
              (odra-project-record-id record)
              (odra-project-record-generation record)
              (odra-project-record-name record)
              (length (odra-project-record-directories record))
              source)
             loaded)
            (catalog-rejection
             source filename 'filename-mismatch
             "Project identity does not match its canonical filename"
             (odra-project-proposal-provenance loaded)))])]))

(define (group-counts entries key)
  (for/fold ([counts (hash)]) ([entry (in-list entries)])
    (define value (key entry))
    (hash-set counts value (add1 (hash-ref counts value 0)))))

(define (catalog-entry<? left right)
  (define left-descriptor (odra-project-catalog-entry-descriptor left))
  (define right-descriptor (odra-project-catalog-entry-descriptor right))
  (define left-name
    (project-catalog-name-key (odra-project-catalog-descriptor-name left-descriptor)))
  (define right-name
    (project-catalog-name-key (odra-project-catalog-descriptor-name right-descriptor)))
  (or (string<? left-name right-name)
      (and (string=? left-name right-name)
           (string<? (odra-project-catalog-descriptor-id left-descriptor)
                     (odra-project-catalog-descriptor-id right-descriptor)))))

(define (catalog-rejection<? left right)
  (define left-source (odra-project-catalog-rejection-source left))
  (define right-source (odra-project-catalog-rejection-source right))
  (or (string<? left-source right-source)
      (and (string=? left-source right-source)
           (symbol<? (odra-project-catalog-rejection-code left)
                     (odra-project-catalog-rejection-code right)))))

(define (symbol<? left right)
  (string<? (symbol->string left) (symbol->string right)))

(define (entry-rejection entry code message)
  (define descriptor (odra-project-catalog-entry-descriptor entry))
  (define proposal (odra-project-catalog-entry-proposal entry))
  (define source (odra-project-catalog-descriptor-source descriptor))
  (odra-project-catalog-rejection
   source
   (path->string (file-name-from-path source))
   code
   message
   (odra-project-proposal-provenance proposal)))

(define (catalog-rejection source filename code message
                           [provenance (odra-project-provenance source 0 0 0 0)])
  (odra-project-catalog-rejection
   source filename code (bounded-message message) provenance))

(define (bounded-message message)
  (if (<= (bytes-length (string->bytes/utf-8 message))
          maximum-project-diagnostic-bytes)
      message
      "Project catalog diagnostic exceeded the message byte limit"))

(define (empty-catalog)
  (odra-project-catalog '() '() (hash) (hash) 0 0))

(define (catalog-with-root-rejection root code message [examined 0])
  (define source (path->string root))
  (odra-project-catalog
   '()
   (list (catalog-rejection source "" code message))
   (hash)
   (hash)
   examined
   0))

(define (project-catalog-list catalog)
  (for/list ([entry (in-list (odra-project-catalog-entries catalog))])
    (odra-project-catalog-entry-descriptor entry)))

(define (project-catalog-rejected catalog)
  (for/list ([rejection (in-list (odra-project-catalog-rejections catalog))])
    rejection))

(define (project-catalog-resolve-id catalog id)
  (hash-ref (odra-project-catalog-identity-index catalog) id #f))

(define (project-catalog-resolve-name catalog name)
  (hash-ref (odra-project-catalog-name-index catalog)
            (project-catalog-name-key name)
            #f))

;; project-catalog-generation fingerprints all accepted and rejected catalog input.
(define (project-catalog-generation catalog)
  (define accepted
    (for/fold ([hash fnv-offset])
              ([entry (in-list (odra-project-catalog-entries catalog))])
      (fnv-bytes
       hash
       (odra-project-proposal-module-bytes
        (odra-project-catalog-entry-proposal entry)))))
  (define complete
    (for/fold ([hash accepted])
              ([rejection (in-list (odra-project-catalog-rejections catalog))])
      (fnv-bytes
       (fnv-bytes
        hash
        (string->bytes/utf-8 (odra-project-catalog-rejection-source rejection)))
       (string->bytes/utf-8 (odra-project-catalog-rejection-message rejection)))))
  (if (zero? complete) 1 complete))

(define (fnv-bytes hash value)
  (for/fold ([result hash]) ([byte (in-bytes value)])
    (bitwise-and (* (bitwise-xor result byte) fnv-prime) u64-mask)))

;; project-catalog-resolve-exact-single-directory preserves catalog order and
;; returns only valid records whose complete membership is the requested path.
(define (project-catalog-resolve-exact-single-directory catalog normalized-path)
  (for/list ([entry (in-list (odra-project-catalog-entries catalog))]
             #:when
             (let* ([proposal (odra-project-catalog-entry-proposal entry)]
                    [record (odra-project-proposal-record proposal)]
                    [directories (odra-project-record-directories record)])
               (and (= (length directories) 1)
                    (string=?
                     (odra-project-directory-path (first directories))
                     normalized-path))))
    entry))

(module+ test
  (require rackunit)

  (define (sample-record id name [generation 1])
    (project
     #:format-version current-project-record-format-version
     #:id id
     #:generation generation
     #:name name
     #:directories
     (list (project-directory
            #:id (string-append id "-directory")
            #:path (string-append "/tmp/" id)
            #:trust 'untrusted))))

  (define (sample-record-with-paths id name paths)
    (project
     #:format-version current-project-record-format-version
     #:id id
     #:generation 1
     #:name name
     #:directories
     (for/list ([path (in-list paths)] [index (in-naturals 1)])
       (project-directory
        #:id (string-append id "-directory-" (number->string index))
        #:path path
        #:trust 'untrusted))))

  (define (write-record root filename record)
    (call-with-output-file (build-path root filename)
      (lambda (output) (write-bytes (project-record->module-bytes record) output))
      #:exists 'truncate/replace
      #:mode 'binary))

  (test-case "catalog loads records and isolates rejects"
    (define root (make-temporary-file "odra-project-catalog-~a" 'directory))
    (dynamic-wind
     void
     (lambda ()
       (write-record root "beta.rkt" (sample-record "beta" "Beta" 2))
       (write-record root "alpha.rkt" (sample-record "alpha" "alpha" 3))
       (write-record root "mismatch.rkt" (sample-record "other" "Other"))
       (call-with-output-file (build-path root "broken.rkt")
         (lambda (output) (display "#lang odra/config\n(project" output)))
       (call-with-output-file (build-path root ".alpha.rkt.stage") void)
       (define catalog (project-catalog-load root))
       (check-equal? (map odra-project-catalog-descriptor-id
                          (project-catalog-list catalog))
                     '("alpha" "beta"))
       (check-equal? (map odra-project-catalog-rejection-code
                          (project-catalog-rejected catalog))
                     '(noncanonical-filename invalid-syntax filename-mismatch))
       (check-equal? (odra-project-catalog-examined-entries catalog) 5)
       (check-equal? (odra-project-catalog-descriptor-generation
                      (project-catalog-resolve-id catalog "beta"))
                     2)
       (check-equal? (odra-project-catalog-descriptor-id
                      (project-catalog-resolve-name catalog "ALPHA"))
                     "alpha"))
     (lambda () (delete-directory/files root))))

  (test-case "duplicate normalized names reject all records"
    (define root (make-temporary-file "odra-project-duplicates-~a" 'directory))
    (dynamic-wind
     void
     (lambda ()
       (write-record root "first.rkt" (sample-record "first" "Project"))
       (write-record root "second.rkt" (sample-record "second" "PROJECT"))
       (write-record root "third.rkt" (sample-record "third" "Independent"))
       (define catalog (project-catalog-load root))
       (check-equal? (map odra-project-catalog-descriptor-id
                          (project-catalog-list catalog))
                     '("third"))
       (check-equal? (map odra-project-catalog-rejection-code
                          (project-catalog-rejected catalog))
                     '(duplicate-name duplicate-name))
       (check-false (project-catalog-resolve-name catalog "project")))
     (lambda () (delete-directory/files root))))

  (test-case "catalog entry limits reject partial publication"
    (define root (make-temporary-file "odra-project-limit-~a" 'directory))
    (dynamic-wind
     void
     (lambda ()
       (write-record root "a.rkt" (sample-record "a" "A"))
       (write-record root "b.rkt" (sample-record "b" "B"))
       (write-record root "c.rkt" (sample-record "c" "C"))
       (define catalog (project-catalog-load root #:maximum-entries 2))
       (check-equal? (project-catalog-list catalog) '())
       (check-equal? (map odra-project-catalog-rejection-code
                          (project-catalog-rejected catalog))
                     '(catalog-limit))
       (check-equal? (odra-project-catalog-examined-entries catalog) 3))
     (lambda () (delete-directory/files root))))

  (test-case "missing catalog directories are empty"
    (define catalog
      (project-catalog-load "/tmp/odra-project-catalog-does-not-exist"))
    (check-equal? (project-catalog-list catalog) '())
    (check-equal? (project-catalog-rejected catalog) '()))

  (test-case "catalog covers accepted and rejected input"
    (define root (make-temporary-file "odra-project-generation-~a" 'directory))
    (dynamic-wind
     void
     (lambda ()
       (define empty-generation (project-catalog-generation (project-catalog-load root)))
       (write-record root "one.rkt" (sample-record "one" "One"))
       (define accepted-generation
         (project-catalog-generation (project-catalog-load root)))
       (call-with-output-file (build-path root "broken.rkt")
         (lambda (output) (display "#lang odra/config\n(project" output)))
       (define rejected-generation
         (project-catalog-generation (project-catalog-load root)))
       (check-not-equal? empty-generation accepted-generation)
       (check-not-equal? accepted-generation rejected-generation)
       (check-equal? rejected-generation
                     (project-catalog-generation (project-catalog-load root))))
     (lambda () (delete-directory/files root))))

  (test-case "single-dir resolution preserves catalog order"
    (define root (make-temporary-file "odra-project-directory-resolution-~a" 'directory))
    (dynamic-wind
     void
     (lambda ()
       (define target "/work/Zażółć/odra")
       (write-record root "beta.rkt"
                     (sample-record-with-paths "beta" "Beta" (list target)))
       (write-record root "alpha.rkt"
                     (sample-record-with-paths "alpha" "Alpha" (list target)))
       (write-record root "multi.rkt"
                     (sample-record-with-paths
                      "multi" "Multi" (list target "/work/shared")))
       (write-record root "other.rkt"
                     (sample-record-with-paths "other" "Other" (list "/work/other")))
       (call-with-output-file (build-path root "broken.rkt")
         (lambda (output) (display "#lang odra/config\n(project" output)))
       (define catalog (project-catalog-load root))
       (define matches
         (project-catalog-resolve-exact-single-directory catalog target))
       (check-equal?
        (map (lambda (entry)
               (odra-project-catalog-descriptor-id
                (odra-project-catalog-entry-descriptor entry)))
             matches)
        '("alpha" "beta"))
       (check-equal?
        (project-catalog-resolve-exact-single-directory catalog "/work")
        '())
       (check-equal?
        (map odra-project-catalog-rejection-code
             (project-catalog-rejected catalog))
        '(invalid-syntax)))
     (lambda () (delete-directory/files root))))

  (test-case "filename rejects aliases and staging names"
    (check-equal? (project-record-filename-id "project-1.rkt") "project-1")
    (check-false (project-record-filename-id "Project-1.rkt"))
    (check-false (project-record-filename-id "project-1.rkt.tmp"))
    (check-false (project-record-filename-id "../project-1.rkt"))))
