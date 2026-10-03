#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require json
         racket/cmdline
         racket/list
         racket/string)

(provide preview-manifest-schema
         preview-platform
         maximum-source-date-epoch
         (struct-out preview-identity)
         preview-identity-errors
         preview-identity-valid?
         preview-version
         preview-artifact-stem
         preview-archive-name
         preview-checksum-name
         preview-terms-name
         preview-notices-name
         preview-identity->jsexpr)

(define preview-manifest-schema 1)
(define preview-platform "linux-x86_64")
(define maximum-source-date-epoch (sub1 (expt 2 63)))

(define canonical-tag-pattern
  #px"^v(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")
(define full-commit-pattern #px"^[0-9a-f]{40}$")

(struct preview-identity
  (tag tag-commit main-commit source-date-epoch platform)
  #:transparent)

(define (canonical-tag? value)
  (and (string? value) (regexp-match? canonical-tag-pattern value)))

(define (full-commit? value)
  (and (string? value) (regexp-match? full-commit-pattern value)))

(define (source-date-epoch? value)
  (and (exact-nonnegative-integer? value)
       (<= value maximum-source-date-epoch)))

(define (preview-identity-errors identity)
  (append
   (if (canonical-tag? (preview-identity-tag identity))
       '()
       '("tag must use canonical vMAJOR.MINOR.PATCH form"))
   (if (full-commit? (preview-identity-tag-commit identity))
       '()
       '("tag commit must be a full lowercase hexadecimal commit"))
   (if (full-commit? (preview-identity-main-commit identity))
       '()
       '("main commit must be a full lowercase hexadecimal commit"))
   (if (equal? (preview-identity-tag-commit identity)
               (preview-identity-main-commit identity))
       '()
       '("tag commit must equal the selected main commit"))
   (if (source-date-epoch? (preview-identity-source-date-epoch identity))
       '()
       '("source date epoch must be an unsigned 63-bit integer"))
   (if (equal? (preview-identity-platform identity) preview-platform)
       '()
       (list (format "platform must be ~a" preview-platform)))))

(define (preview-identity-valid? identity)
  (null? (preview-identity-errors identity)))

(define (require-valid-identity who identity)
  (define errors (preview-identity-errors identity))
  (unless (null? errors)
    (raise-arguments-error who
                           "invalid preview identity"
                           "errors" errors))
  identity)

(define (preview-version identity)
  (require-valid-identity 'preview-version identity)
  (substring (preview-identity-tag identity) 1))

(define (preview-artifact-stem identity)
  (format "odra-~a-~a"
          (preview-version identity)
          (preview-identity-platform identity)))

(define (preview-archive-name identity)
  (string-append (preview-artifact-stem identity) ".tar.zst"))

(define (preview-checksum-name identity)
  (string-append (preview-archive-name identity) ".sha256"))

(define (preview-notices-name identity)
  (string-append (preview-artifact-stem identity)
                 "-THIRD_PARTY_NOTICES.md"))

(define (preview-terms-name identity)
  (string-append (preview-artifact-stem identity)
                 "-PREVIEW_TERMS.md"))

(define (preview-identity->jsexpr identity)
  (require-valid-identity 'preview-identity->jsexpr identity)
  (hasheq 'schema preview-manifest-schema
          'product "odra"
          'version (preview-version identity)
          'tag (preview-identity-tag identity)
          'commit (preview-identity-tag-commit identity)
          'source_date_epoch (preview-identity-source-date-epoch identity)
          'platform (preview-identity-platform identity)
          'archive (preview-archive-name identity)
          'checksum (preview-checksum-name identity)
          'product_terms (preview-terms-name identity)
          'third_party_notices (preview-notices-name identity)))

(module+ main
  (define identity
    (command-line
     #:program "preview-identity.rkt"
     #:args (tag tag-commit main-commit source-date-epoch platform)
     (preview-identity tag
                       tag-commit
                       main-commit
                       (or (string->number source-date-epoch) source-date-epoch)
                       platform)))
  (define errors (preview-identity-errors identity))
  (unless (null? errors)
    (for-each (lambda (error) (eprintf "preview identity: ~a\n" error)) errors)
    (exit 1))
  (write-json (preview-identity->jsexpr identity))
  (newline))

(module+ test
  (require rackunit)

  (define commit "0123456789abcdef0123456789abcdef01234567")
  (define valid
    (preview-identity "v1.2.3" commit commit 1798761600 preview-platform))

  (test-case "accepts one exact stable release identity"
    (check-true (preview-identity-valid? valid))
    (check-equal? (preview-version valid) "1.2.3")
    (check-equal? (preview-archive-name valid)
                  "odra-1.2.3-linux-x86_64.tar.zst")
    (check-equal? (preview-checksum-name valid)
                  "odra-1.2.3-linux-x86_64.tar.zst.sha256")
    (check-equal? (preview-terms-name valid)
                  "odra-1.2.3-linux-x86_64-PREVIEW_TERMS.md")
    (check-equal? (preview-notices-name valid)
                  "odra-1.2.3-linux-x86_64-THIRD_PARTY_NOTICES.md")
    (check-equal? (hash-ref (preview-identity->jsexpr valid) 'schema)
                  preview-manifest-schema))

  (test-case "rejects noncanonical and unsafe release tags"
    (for ([tag (in-list '("1.2.3"
                          "v01.2.3"
                          "v1.02.3"
                          "v1.2.03"
                          "v1.2.3-rc.1"
                          "v1.2.3+build"
                          "v1.2.3/../../main"
                          "$(touch injected)"))])
      (check-false
       (preview-identity-valid?
        (struct-copy preview-identity valid [tag tag])))))

  (test-case "rejects abbreviated uppercase and mismatched commits"
    (for ([candidate (in-list '("01234567"
                                "0123456789ABCDEF0123456789ABCDEF01234567"
                                "g123456789abcdef0123456789abcdef0123456"))])
      (check-false
       (preview-identity-valid?
        (struct-copy preview-identity valid [tag-commit candidate]))))
    (check-false
     (preview-identity-valid?
      (struct-copy preview-identity
                   valid
                   [main-commit "1123456789abcdef0123456789abcdef01234567"]))))

  (test-case "rejects invalid source dates and platforms"
    (for ([epoch (in-list (list -1 1.5 "1798761600" (expt 2 63)))])
      (check-false
       (preview-identity-valid?
        (struct-copy preview-identity valid [source-date-epoch epoch]))))
    (for ([platform (in-list '("linux-amd64" "linux-arm64" "linux-x86_64/.."))])
      (check-false
       (preview-identity-valid?
        (struct-copy preview-identity valid [platform platform])))))

  (test-case "refuses to derive artifacts from an invalid identity"
    (define invalid (struct-copy preview-identity valid [tag "dev"]))
    (check-exn exn:fail:contract?
               (lambda () (preview-archive-name invalid)))
    (check-exn exn:fail:contract?
               (lambda () (preview-identity->jsexpr invalid)))))
