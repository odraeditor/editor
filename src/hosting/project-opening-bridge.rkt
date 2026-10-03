#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "../project/persistence.rkt"
         "../project/records.rkt")

(provide
 (contract-out
  [runtime-project-directory-resolution
   (-> bytes? bytes? list?)]
  [runtime-project-catalog-resolution
   (-> bytes? list?)]))

(define schema-version 1)
(define header-bytes 32)
(define record-bytes 88)
(define maximum-copy-bytes (* 4 1024 1024))
(define fnv-offset 14695981039346656037)

(define (word value)
  (integer->integer-bytes value 8 #f #f))

(define (words . values)
  (apply bytes-append (map word values)))

(define (fnv-bytes hash value)
  (for/fold ([result hash]) ([byte (in-bytes value)])
    (bitwise-and
     (* (bitwise-xor result byte) 1099511628211)
     (sub1 (expt 2 64)))))

(define (project-records-encode records generation who)
  (define text-output (open-output-bytes))
  (define (add-text value)
    (define encoded (string->bytes/utf-8 value))
    (define offset (file-position text-output))
    (write-bytes encoded text-output)
    (values offset (bytes-length encoded)))
  (define encoded-records
    (for/list ([record (in-list records)])
      (define id (odra-local-project-record-id record))
      (define-values (id-offset id-bytes) (add-text id))
      (define-values (name-offset name-bytes)
        (add-text (odra-local-project-record-name record)))
      (define-values (membership-offset membership-bytes)
        (add-text (string-append id "-root")))
      (define-values (path-offset path-bytes)
        (add-text (odra-local-project-record-root record)))
      (define runtime-id
        (let ([value (fnv-bytes fnv-offset (string->bytes/utf-8 id))])
          (if (zero? value) 1 value)))
      (words runtime-id
             (odra-local-project-record-generation record)
             (if (eq? (odra-local-project-record-trust record) 'trusted) 2 1)
             id-offset id-bytes
             name-offset name-bytes
             membership-offset membership-bytes
             path-offset path-bytes)))
  (define text (get-output-bytes text-output))
  (define total-bytes (+ header-bytes (* record-bytes (length encoded-records))
                         (bytes-length text)))
  (when (> total-bytes maximum-copy-bytes)
    (error who "Project resolution exceeds copied storage"))
  (bytes-append
   (words schema-version generation (length encoded-records) (bytes-length text))
   (apply bytes-append encoded-records)
   text))

(define (runtime-project-directory-resolution _projects-directory-bytes directory-bytes)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #"" (string->bytes/utf-8 (exn-message failure))))])
    (define normalized-path
      (bytes->string/utf-8 directory-bytes #f))
    (define record-path (build-path normalized-path ".odra" "project.rkt"))
    (define loaded
      (and (file-exists? record-path)
           (local-project-record-module-load record-path)))
    (define matches
      (if (and (odra-local-project-record? loaded)
               (string=? (odra-local-project-record-root loaded)
                         normalized-path))
          (list loaded)
          '()))
    (define batch
      (project-records-encode
       matches
       (if (null? matches)
           1
           (odra-local-project-record-generation (car matches)))
       'runtime-project-directory-resolution))
    (list #t batch #"")))

(define (runtime-project-catalog-resolution configuration-root-bytes)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #"" (string->bytes/utf-8 (exn-message failure))))])
    (define catalog
      (project-discovery-catalog-load (bytes->path configuration-root-bytes)))
    (define valid-records
      (filter-map
       (lambda (reference)
         (define loaded
           (local-project-record-module-load
            (local-project-record-path
             (odra-project-discovery-record-root reference))))
         (and (odra-local-project-record? loaded)
              (string=? (odra-local-project-record-id loaded)
                        (odra-project-discovery-record-id reference))
              (string=? (odra-local-project-record-root loaded)
                        (odra-project-discovery-record-root reference))
              (= (odra-local-project-record-generation loaded)
                 (odra-project-discovery-record-expected-project-generation reference))
              loaded))
       (odra-record-catalog-records catalog)))
    (define generation
      (for/fold ([value fnv-offset]) ([record (in-list valid-records)])
        (fnv-bytes
         (fnv-bytes value
                    (string->bytes/utf-8 (odra-local-project-record-id record)))
         (word (odra-local-project-record-generation record)))))
    (list #t
          (project-records-encode valid-records (if (zero? generation) 1 generation)
                                  'runtime-project-catalog-resolution)
          #"")))

(module+ test
  (require racket/file
           rackunit)

  (define home (make-temporary-file "odra-project-opening-~a" 'directory))
  (define directory (build-path home "workspace"))
  (dynamic-wind
   void
   (lambda ()
     (make-directory directory)
     (define record
       (local-project-record
        #:format-version current-local-project-format-version
        #:id "example"
        #:generation 7
        #:name "Example"
        #:root (path->string directory)
        #:trust 'trusted))
     (make-directory* (build-path directory ".odra"))
     (call-with-output-file (build-path directory ".odra" "project.rkt")
       (lambda (output) (write-bytes (local-project-record->module-bytes record) output))
       #:exists 'truncate/replace
       #:mode 'binary)
     (define resolved
      (runtime-project-directory-resolution
        #"ignored"
        (string->bytes/utf-8 (path->string directory))))
     (check-true (car resolved))
     (define batch (cadr resolved))
     (check-equal? (integer-bytes->integer batch #f #f 0 8) schema-version)
     (check-not-equal? (integer-bytes->integer batch #f #f 8 16) 0)
     (check-equal? (integer-bytes->integer batch #f #f 16 24) 1)
     (check-equal? (integer-bytes->integer batch #f #f 40 48) 7)
     (define configuration-root (build-path home "config"))
     (make-directory* (build-path configuration-root "projects"))
     (call-with-output-file (build-path configuration-root "projects" "example.rkt")
       (lambda (output)
         (write-bytes
          (project-discovery-record->module-bytes
           (project-discovery-record
            #:format-version current-project-discovery-format-version
            #:id "example"
            #:expected-project-generation 7
            #:root (path->string directory)))
          output))
       #:exists 'truncate/replace
       #:mode 'binary)
     (define catalog
       (runtime-project-catalog-resolution
        (path->bytes configuration-root)))
     (check-true (car catalog))
     (check-equal? (integer-bytes->integer (cadr catalog) #f #f 16 24) 1)
     (call-with-output-file (build-path configuration-root "projects" "example.rkt")
       (lambda (output)
         (write-bytes
          (project-discovery-record->module-bytes
           (project-discovery-record
            #:format-version current-project-discovery-format-version
            #:id "example"
            #:expected-project-generation 8
            #:root (path->string directory)))
          output))
       #:exists 'truncate/replace
       #:mode 'binary)
     (define stale
       (runtime-project-catalog-resolution
        (path->bytes configuration-root)))
     (check-true (car stale))
     (check-equal? (integer-bytes->integer (cadr stale) #f #f 16 24) 0))
   (lambda () (delete-directory/files home))))
