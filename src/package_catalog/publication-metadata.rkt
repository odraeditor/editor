#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/match
         "../storage/record-codec.rkt"
         "contracts.rkt"
         "integrity.rkt")

(provide
 current-package-catalog-publication-metadata-format-version
 (struct-out odra-package-catalog-publication-metadata)
 (contract-out
  [package-catalog-publication-metadata->module-bytes
   (-> odra-package-catalog-publication-metadata? immutable-bytes?)]
  [package-catalog-publication-metadata-module-load
   (-> path-string?
       (or/c odra-package-catalog-publication-metadata?
             odra-record-diagnostic?))]))

(define current-package-catalog-publication-metadata-format-version 1)

(define (immutable-bytes? value)
  (and (bytes? value) (immutable? value)))

(define (publisher-key-ids profile)
  (remove-duplicates
   (append*
    (for/list
        ([authorization
          (in-list (odra-package-catalog-profile-publishers profile))])
      (odra-package-catalog-publisher-authorization-key-ids authorization)))
   string=?))

(define (metadata-valid? profile publisher-keys)
  (and (odra-package-catalog-profile? profile)
       (eq? #t (verify-package-catalog-profile-identity profile))
       (list? publisher-keys)
       (pair? publisher-keys)
       (andmap odra-package-catalog-publisher-key? publisher-keys)
       (= (length publisher-keys)
          (length
           (remove-duplicates
            publisher-keys string=?
            #:key odra-package-catalog-publisher-key-id)))
       (equal?
        (sort (publisher-key-ids profile) string<?)
        (sort (map odra-package-catalog-publisher-key-id publisher-keys)
              string<?))
       (for/and ([key (in-list publisher-keys)])
         (string=?
          (package-catalog-public-key-id
           (odra-package-catalog-publisher-key-public-key key))
          (odra-package-catalog-publisher-key-id key)))))

(struct odra-package-catalog-publication-metadata
  (format-version profile publisher-keys)
  #:transparent
  #:guard
  (lambda (format-version profile publisher-keys _)
    (unless (and (= format-version
                    current-package-catalog-publication-metadata-format-version)
                 (metadata-valid? profile publisher-keys))
      (raise-arguments-error
       'odra-package-catalog-publication-metadata
       "invalid verified package catalog publication metadata"))
    (values format-version profile (for/list ([key (in-list publisher-keys)]) key))))

(define (publisher-key->datum key)
  (list (odra-package-catalog-publisher-key-id key)
        (odra-package-catalog-publisher-key-algorithm key)
        (odra-package-catalog-publisher-key-public-key key)))

(define (package-catalog-publication-metadata->module-bytes metadata)
  (record-datum->module-bytes
   (list 'package-catalog-publication-metadata
         (odra-package-catalog-publication-metadata-format-version metadata)
         (package-catalog-profile->datum
          (odra-package-catalog-publication-metadata-profile metadata))
         (map publisher-key->datum
              (odra-package-catalog-publication-metadata-publisher-keys
               metadata)))))

(define (decode-root value)
  (match value
    [(list id generation algorithm public-key valid-from valid-until)
     (odra-package-catalog-root-key
      id generation algorithm public-key valid-from valid-until)]))

(define (decode-curator value)
  (match value
    [(list id subject class valid-from valid-until policy-ids)
     (odra-package-catalog-curator-authorization
      id subject class valid-from valid-until policy-ids)]))

(define (decode-publisher value)
  (match value
    [(list id key-ids threshold valid-from valid-until)
     (odra-package-catalog-publisher-authorization
      id key-ids threshold valid-from valid-until)]))

(define (decode-policy value)
  (match value
    [(list id generation effective-from package-eligibility authority-policy
           assessment-policy decision-policy retention-policy)
     (odra-package-catalog-policy
      id generation effective-from package-eligibility authority-policy
      assessment-policy decision-policy retention-policy)]))

(define (decode-endpoint value)
  (match value
    [(list id catalog-id uri transport role priority enabled?)
     (odra-package-catalog-endpoint
      id catalog-id uri transport role priority enabled?)]))

(define (decode-profile value)
  (match value
    [(list 'package-catalog-profile format-version identity display-name roots
           curators publishers policies endpoints)
     (define-values (profile rejection)
       (confirm-package-catalog-profile
        (odra-package-catalog-profile-proposal
         format-version identity display-name
         (map decode-root roots)
         (map decode-curator curators)
         (map decode-publisher publishers)
         (map decode-policy policies)
         (map decode-endpoint endpoints))))
     (when rejection
       (raise-arguments-error
        'package-catalog-publication-metadata
        "publication profile was rejected" "rejection" rejection))
     profile]))

(define (decode-publisher-key value)
  (match value
    [(list id algorithm public-key)
     (odra-package-catalog-publisher-key id algorithm public-key)]))

(define (decode-metadata value)
  (match value
    [(list 'package-catalog-publication-metadata format-version profile keys)
     (odra-package-catalog-publication-metadata
      format-version (decode-profile profile) (map decode-publisher-key keys))]
    [_
     (raise-arguments-error
      'package-catalog-publication-metadata
      "unsupported publication metadata schema")]))

(define (package-catalog-publication-metadata-module-load path)
  (record-module-load path decode-metadata))

(module+ test
  (require racket/file rackunit)

  (define root-public-key
    "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
  (define publisher-public-key
    "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c")
  (define root-id (package-catalog-public-key-id root-public-key))
  (define publisher-id (package-catalog-public-key-id publisher-public-key))
  (define root
    (odra-package-catalog-root-key root-id 1 'ed25519 root-public-key 1 #f))
  (define catalog-id (package-catalog-identity root))
  (define-values (profile rejection)
    (confirm-package-catalog-profile
     (odra-package-catalog-profile-proposal
      1 catalog-id "Local Catalog" (list root) '()
      (list
       (odra-package-catalog-publisher-authorization
        "publisher" (list publisher-id) 1 1 #f))
      (list
       (odra-package-catalog-policy
        "policy" 1 1 "eligible" "authority" "assessment" "decision"
        "retention"))
      '())))
  (check-false rejection)
  (define metadata
    (odra-package-catalog-publication-metadata
     1 profile
     (list
      (odra-package-catalog-publisher-key
       publisher-id 'ed25519 publisher-public-key))))
  (define path (make-temporary-file "package-catalog-metadata-~a.rktd"))
  (dynamic-wind
    void
    (lambda ()
      (call-with-output-file path
        (lambda (output)
          (write-bytes
           (package-catalog-publication-metadata->module-bytes metadata)
           output))
        #:exists 'truncate/replace
        #:mode 'binary)
      (check-equal?
       (package-catalog-publication-metadata-module-load path)
       metadata))
    (lambda () (delete-file path))))
