#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/match
         racket/string
         "curation-records.rkt")

(provide
 (struct-out odra-package-curated-source)
 (struct-out odra-package-resolution-request)
 (struct-out odra-package-resolution)
 (struct-out odra-package-resolution-failure)
 (contract-out
  [resolve-curated-package
   (-> (listof odra-package-curated-source?)
       odra-package-resolution-request?
       (or/c odra-package-resolution? odra-package-resolution-failure?))]))

(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
(define digest-pattern #px"^[0-9a-f]{64}$")
(define version-pattern
  #px"^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z.-]+))?$")

(define (identity? value)
  (and (string? value)
       (<= 1 (bytes-length (string->bytes/utf-8 value)) 128)
       (regexp-match? identity-pattern value)))

(define (digest? value)
  (and (string? value) (regexp-match? digest-pattern value)))

(define (parse-version value)
  (match (and (string? value) (regexp-match version-pattern value))
    [(list _ major minor patch pre-release)
     (list (string->number major) (string->number minor) (string->number patch)
           (and pre-release (string-split pre-release ".")))]
    [_ #f]))

(define (compare-number left right)
  (cond [(< left right) -1] [(> left right) 1] [else 0]))

(define (numeric-identifier? value)
  (regexp-match? #px"^(?:0|[1-9][0-9]*)$" value))

(define (compare-pre-release left right)
  (cond
    [(and (not left) (not right)) 0]
    [(not left) 1]
    [(not right) -1]
    [else
     (let loop ([left left] [right right])
       (cond
         [(and (null? left) (null? right)) 0]
         [(null? left) -1]
         [(null? right) 1]
         [else
          (define left-id (car left))
          (define right-id (car right))
          (define compared
            (cond
              [(and (numeric-identifier? left-id)
                    (numeric-identifier? right-id))
               (compare-number (string->number left-id)
                               (string->number right-id))]
              [(numeric-identifier? left-id) -1]
              [(numeric-identifier? right-id) 1]
              [(string<? left-id right-id) -1]
              [(string>? left-id right-id) 1]
              [else 0]))
          (if (zero? compared)
              (loop (cdr left) (cdr right))
              compared)]))]))

(define (version-compare left right)
  (define parsed-left (parse-version left))
  (define parsed-right (parse-version right))
  (and parsed-left parsed-right
       (or (for/or ([left-part (in-list (take parsed-left 3))]
                    [right-part (in-list (take parsed-right 3))])
             (define compared (compare-number left-part right-part))
             (and (not (zero? compared)) compared))
           (compare-pre-release (last parsed-left) (last parsed-right)))))

(define (version<=? left right)
  (define compared (version-compare left right))
  (and compared (<= compared 0)))

(struct odra-package-curated-source
  (catalog-id snapshot-id precedence assertions)
  #:transparent
  #:guard
  (lambda (catalog-id snapshot-id precedence assertions _)
    (define assertion-ids
      (and (list? assertions)
           (map odra-package-curation-assertion-id assertions)))
    (unless
        (and (digest? catalog-id)
             (digest? snapshot-id)
             (exact-nonnegative-integer? precedence)
             (<= precedence 65535)
             (list? assertions)
             (andmap odra-package-curation-assertion? assertions)
             (andmap
              (lambda (assertion)
                (string=? catalog-id
                          (odra-package-curation-assertion-catalog-id assertion)))
              assertions)
             (equal? assertion-ids
                     (sort (remove-duplicates assertion-ids string=?) string<?)))
      (raise-arguments-error 'odra-package-curated-source
                             "invalid verified catalog assertion projection"))
    (values (string->immutable-string catalog-id)
            (string->immutable-string snapshot-id) precedence assertions)))

(struct odra-package-resolution-request
  (package-id minimum maximum platform architecture catalog-pin)
  #:transparent
  #:guard
  (lambda (package-id minimum maximum platform architecture catalog-pin _)
    (unless
        (and (identity? package-id)
             (parse-version minimum)
             (parse-version maximum)
             (version<=? minimum maximum)
             (memq platform '(darwin linux windows))
             (memq architecture '(aarch64 x86-64))
             (or (not catalog-pin) (digest? catalog-pin)))
      (raise-arguments-error 'odra-package-resolution-request
                             "invalid curated package resolution request"))
    (values (string->immutable-string package-id)
            (string->immutable-string minimum)
            (string->immutable-string maximum)
            platform architecture
            (and catalog-pin (string->immutable-string catalog-pin)))))

(struct odra-package-resolution
  (release artifact assertions catalog-ids snapshot-ids curation-status
           selected-assertion selected-catalog-id selected-snapshot-id)
  #:transparent)

(struct odra-package-resolution-failure (code package-id catalog-ids digests)
  #:transparent
  #:guard
  (lambda (code package-id catalog-ids digests _)
    (unless
        (and (memq code '(artifact-identity-conflict invalid-source
                                                     no-candidate
                                                     release-projection-conflict))
             (identity? package-id)
             (list? catalog-ids)
             (equal? catalog-ids
                     (sort (remove-duplicates catalog-ids string=?) string<?))
             (list? digests)
             (equal? digests
                     (sort (remove-duplicates digests string=?) string<?)))
      (raise-arguments-error 'odra-package-resolution-failure
                             "invalid deterministic package resolution failure"))
    (values code (string->immutable-string package-id)
            (map string->immutable-string catalog-ids)
            (map string->immutable-string digests))))

(struct candidate (source assertion release artifact) #:transparent)

(define (request-candidate? request assertion)
  (define release (odra-package-curation-assertion-release assertion))
  (and (memq (odra-package-curation-assertion-status assertion)
             '(admitted deprecated))
       (string=? (odra-package-resolution-request-package-id request)
                 (odra-package-release-reference-package-id release))
       (version<=? (odra-package-resolution-request-minimum request)
                   (odra-package-release-reference-version release))
       (version<=? (odra-package-release-reference-version release)
                   (odra-package-resolution-request-maximum request))))

(define (inventory sources request)
  (for*/list ([source (in-list sources)]
              [assertion
               (in-list (odra-package-curated-source-assertions source))]
              #:when (request-candidate? request assertion)
              #:do
              [(define release
                 (odra-package-curation-assertion-release assertion))
               (define artifact
                 (package-release-artifact
                  release
                  (odra-package-resolution-request-platform request)
                  (odra-package-resolution-request-architecture request)))]
              #:when artifact)
    (candidate source assertion release artifact)))

(define (candidate-version candidate)
  (odra-package-release-reference-version (candidate-release candidate)))

(define (candidate-catalog-id candidate)
  (odra-package-curated-source-catalog-id (candidate-source candidate)))

(define (candidate-artifact-digest candidate)
  (odra-package-artifact-reference-digest (candidate-artifact candidate)))

(define (conflict-for candidates request)
  (for*/first
      ([left (in-list candidates)]
       [right (in-list candidates)]
       #:when
       (and (string=? (candidate-version left) (candidate-version right))
            (not (string=? (candidate-catalog-id left)
                           (candidate-catalog-id right)))
            (or (not (string=? (candidate-artifact-digest left)
                               (candidate-artifact-digest right)))
                (not (same-package-release? (candidate-release left)
                                            (candidate-release right))))))
    (define catalog-ids
      (sort (list (candidate-catalog-id left) (candidate-catalog-id right))
            string<?))
    (define digests
      (sort (remove-duplicates
             (list (candidate-artifact-digest left)
                   (candidate-artifact-digest right))
             string=?)
            string<?))
    (odra-package-resolution-failure
     (if (> (length digests) 1)
         'artifact-identity-conflict
         'release-projection-conflict)
     (odra-package-resolution-request-package-id request)
     catalog-ids digests)))

(define (candidate-better? left right)
  (define left-precedence
    (odra-package-curated-source-precedence (candidate-source left)))
  (define right-precedence
    (odra-package-curated-source-precedence (candidate-source right)))
  (cond
    [(not (= left-precedence right-precedence))
     (> left-precedence right-precedence)]
    [(not (zero? (version-compare (candidate-version left)
                                  (candidate-version right))))
     (> (version-compare (candidate-version left) (candidate-version right)) 0)]
    [else (string<? (candidate-catalog-id left) (candidate-catalog-id right))]))

(define (resolve-curated-package sources request)
  (define source-ids (map odra-package-curated-source-catalog-id sources))
  (cond
    [(not (= (length source-ids)
             (length (remove-duplicates source-ids string=?))))
     (odra-package-resolution-failure
      'invalid-source (odra-package-resolution-request-package-id request)
      (sort (remove-duplicates source-ids string=?) string<?) '())]
    [else
     (define candidates (inventory sources request))
     (define conflict (conflict-for candidates request))
     (cond
       [conflict conflict]
       [else
        (define pin (odra-package-resolution-request-catalog-pin request))
        (define eligible
          (if pin
              (filter (lambda (value)
                        (string=? pin (candidate-catalog-id value)))
                      candidates)
              candidates))
        (cond
          [(null? eligible)
           (odra-package-resolution-failure
            'no-candidate (odra-package-resolution-request-package-id request)
            (if pin (list pin) '()) '())]
          [else
           (define selected (car (sort eligible candidate-better?)))
           (define equivalents
             (sort
              (filter
               (lambda (value)
                 (same-package-release? (candidate-release selected)
                                        (candidate-release value)))
               candidates)
              string<? #:key candidate-catalog-id))
           (define assertions (map candidate-assertion equivalents))
           (odra-package-resolution
            (candidate-release selected)
            (candidate-artifact selected)
            assertions
            (map candidate-catalog-id equivalents)
            (map (lambda (value)
                   (odra-package-curated-source-snapshot-id
                    (candidate-source value)))
                 equivalents)
            (if (for/or ([assertion (in-list assertions)])
                  (eq? (odra-package-curation-assertion-status assertion)
                       'admitted))
                'admitted
                'deprecated)
            (candidate-assertion selected)
            (candidate-catalog-id selected)
            (odra-package-curated-source-snapshot-id
             (candidate-source selected)))])])]))
