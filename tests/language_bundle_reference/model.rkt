#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         racket/match
         racket/port
         racket/string)

(provide bundle-limits
         bundle-resource-profiles
         (struct-out bundle-version)
         (struct-out bundle-api-range)
         (struct-out bundle-target)
         (struct-out bundle-dependency)
         (struct-out bundle-artifact)
         (struct-out bundle-contribution)
         (struct-out bundle-manifest)
         (struct-out bundle-rejection)
         confirm-bundle-manifest
         bundle-manifest->canonical-bytes
         bundle-api-compatible?
         select-bundle-artifact
         validate-bundle-resource-profile)

(define bundle-limits
  '#hasheq((manifest-bytes . 2097152)
           (identity-bytes . 96)
           (display-name-bytes . 128)
           (description-bytes . 4096)
           (publisher-bytes . 128)
           (source-bytes . 128)
           (dependencies . 256)
           (artifacts . 1024)
           (contributions . 640)
           (authorities . 16)
           (targets . 16)
           (path-bytes . 4096)
           (artifact-bytes . 1099511627776)))

(define bundle-resource-profiles
  (list
   '#hasheq((name . ordinary)
            (dependencies . 2)
            (artifacts . 8)
            (contributions . 12)
            (authorities . 3)
            (targets . 2)
            (manifest-bytes . 8192))
   '#hasheq((name . demanding)
            (dependencies . 96)
            (artifacts . 384)
            (contributions . 256)
            (authorities . 6)
            (targets . 6)
            (manifest-bytes . 786432))
   '#hasheq((name . boundary)
            (dependencies . 256)
            (artifacts . 1024)
            (contributions . 640)
            (authorities . 6)
            (targets . 6)
            (manifest-bytes . 2097152))))

(define admitted-platforms '(darwin linux windows))
(define admitted-architectures '(aarch64 x86-64))
(define admitted-authorities
  '(external-process native-grammar network-acquisition project-read
                     project-write racket-extension))
(define admitted-artifact-kinds
  '(data documentation executable license manifest query racket-module
         tree-sitter-grammar))
(define admitted-contribution-kinds
  '(command formatter keymap language service syntax-provider))

(struct bundle-version (major minor patch pre-release) #:transparent)
(struct bundle-api-range (minimum maximum) #:transparent)
(struct bundle-target (platform architecture) #:transparent)
(struct bundle-dependency (identity minimum maximum optional? facets) #:transparent)
(struct bundle-artifact
  (identity kind path digest size targets authority)
  #:transparent)
(struct bundle-contribution
  (kind identity languages artifacts dependencies authorities)
  #:transparent)
(struct bundle-manifest
  (format-version identity display-name version api-range description
                  publisher source targets dependencies
                  authorities contributions artifacts entrypoint)
  #:transparent)
(struct bundle-rejection (code field limit actual identity) #:transparent)

(define (utf8-length value)
  (if (string? value) (bytes-length (string->bytes/utf-8 value)) +inf.0))

(define (bounded-text? value maximum #:empty? [empty? #f])
  (and (string? value)
       (or empty? (positive? (string-length value)))
       (not (string-contains? value (string #\nul)))
       (<= (utf8-length value) maximum)))

(define (identity? value)
  (and (bounded-text? value (hash-ref bundle-limits 'identity-bytes))
       (regexp-match? #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$" value)))

(define (version? value)
  (and (bundle-version? value)
       (for/and ([part (in-list (list (bundle-version-major value)
                                      (bundle-version-minor value)
                                      (bundle-version-patch value)))])
         (exact-nonnegative-integer? part))
       (or (not (bundle-version-pre-release value))
           (bounded-text? (bundle-version-pre-release value) 64))))

(define (version-core value)
  (list (bundle-version-major value)
        (bundle-version-minor value)
        (bundle-version-patch value)))

(define (version<=? left right)
  (define left-core (version-core left))
  (define right-core (version-core right))
  (define (core<? left-parts right-parts)
    (cond
      [(null? left-parts) #f]
      [(< (car left-parts) (car right-parts)) #t]
      [(> (car left-parts) (car right-parts)) #f]
      [else (core<? (cdr left-parts) (cdr right-parts))]))
  (or (core<? left-core right-core)
      (and (equal? left-core right-core)
           (let ([left-pre (bundle-version-pre-release left)]
                 [right-pre (bundle-version-pre-release right)])
             (or (equal? left-pre right-pre)
                 (and left-pre (not right-pre))
                 (and left-pre right-pre (string<=? left-pre right-pre)))))))

(define (api-range? value)
  (and (bundle-api-range? value)
       (version? (bundle-api-range-minimum value))
       (version? (bundle-api-range-maximum value))
       (version<=? (bundle-api-range-minimum value)
                   (bundle-api-range-maximum value))))

(define (unique-list? values [same? equal?])
  (and (list? values)
       (= (length values) (length (remove-duplicates values same?)))))

(define (admitted-set? values admitted limit)
  (and (unique-list? values eq?)
       (<= (length values) limit)
       (andmap (lambda (value) (and (memq value admitted) #t)) values)))

(define (target? value)
  (and (bundle-target? value)
       (memq (bundle-target-platform value) admitted-platforms)
       (memq (bundle-target-architecture value) admitted-architectures)
       #t))

(define (target-set? values)
  (and (unique-list? values equal?)
       (positive? (length values))
       (<= (length values) (hash-ref bundle-limits 'targets))
       (andmap target? values)))

(define (valid-digest? value)
  (and (string? value) (regexp-match? #px"^[0-9a-f]{64}$" value)))

(define (valid-relative-path? value)
  (and (bounded-text? value (hash-ref bundle-limits 'path-bytes))
       (not (regexp-match? #px"^(?:/|\\\\|[A-Za-z]:)" value))
       (for/and ([part (in-list (string-split value "/"))])
         (not (member part '("" "." ".."))))))

(define (validate-dependency value owner)
  (cond
    [(not (bundle-dependency? value))
     (bundle-rejection 'invalid-field 'dependency #f value owner)]
    [(not (identity? (bundle-dependency-identity value)))
     (bundle-rejection 'invalid-field 'dependency-identity
                       (hash-ref bundle-limits 'identity-bytes)
                       (bundle-dependency-identity value) owner)]
    [(string=? owner (bundle-dependency-identity value))
     (bundle-rejection 'self-dependency 'dependency #f owner owner)]
    [(or (not (version? (bundle-dependency-minimum value)))
         (not (version? (bundle-dependency-maximum value)))
         (not (version<=? (bundle-dependency-minimum value)
                          (bundle-dependency-maximum value))))
     (bundle-rejection 'invalid-version-range 'dependency #f
                       (bundle-dependency-identity value) owner)]
    [(not (boolean? (bundle-dependency-optional? value)))
     (bundle-rejection 'invalid-field 'optional #f
                       (bundle-dependency-optional? value) owner)]
    [(not (and (unique-list? (bundle-dependency-facets value) eq?)
               (andmap (lambda (facet)
                         (and (memq facet admitted-contribution-kinds) #t))
                       (bundle-dependency-facets value))))
     (bundle-rejection 'invalid-field 'dependency-facets #f
                       (bundle-dependency-facets value) owner)]
    [else #f]))

(define (validate-artifact value owner)
  (cond
    [(not (bundle-artifact? value))
     (bundle-rejection 'invalid-field 'artifact #f value owner)]
    [(not (identity? (bundle-artifact-identity value)))
     (bundle-rejection 'invalid-field 'artifact-identity
                       (hash-ref bundle-limits 'identity-bytes)
                       (bundle-artifact-identity value) owner)]
    [(not (memq (bundle-artifact-kind value) admitted-artifact-kinds))
     (bundle-rejection 'invalid-field 'artifact-kind #f
                       (bundle-artifact-kind value) owner)]
    [(not (valid-relative-path? (bundle-artifact-path value)))
     (bundle-rejection 'invalid-path 'artifact-path
                       (hash-ref bundle-limits 'path-bytes)
                       (bundle-artifact-path value) owner)]
    [(not (valid-digest? (bundle-artifact-digest value)))
     (bundle-rejection 'invalid-digest 'artifact-digest 64
                       (bundle-artifact-digest value) owner)]
    [(not (and (exact-nonnegative-integer? (bundle-artifact-size value))
               (<= (bundle-artifact-size value)
                   (hash-ref bundle-limits 'artifact-bytes))))
     (bundle-rejection 'limit 'artifact-bytes
                       (hash-ref bundle-limits 'artifact-bytes)
                       (bundle-artifact-size value) owner)]
    [(not (target-set? (bundle-artifact-targets value)))
     (bundle-rejection 'invalid-field 'artifact-targets
                       (hash-ref bundle-limits 'targets)
                       (bundle-artifact-targets value) owner)]
    [(and (bundle-artifact-authority value)
          (not (memq (bundle-artifact-authority value) admitted-authorities)))
     (bundle-rejection 'invalid-field 'artifact-authority #f
                       (bundle-artifact-authority value) owner)]
    [else #f]))

(define (validate-contribution value owner artifacts dependencies authorities)
  (cond
    [(not (bundle-contribution? value))
     (bundle-rejection 'invalid-field 'contribution #f value owner)]
    [(not (memq (bundle-contribution-kind value) admitted-contribution-kinds))
     (bundle-rejection 'invalid-field 'contribution-kind #f
                       (bundle-contribution-kind value) owner)]
    [(not (identity? (bundle-contribution-identity value)))
     (bundle-rejection 'invalid-field 'contribution-identity
                       (hash-ref bundle-limits 'identity-bytes)
                       (bundle-contribution-identity value) owner)]
    [(not (and (unique-list? (bundle-contribution-languages value) string=?)
               (andmap identity? (bundle-contribution-languages value))))
     (bundle-rejection 'invalid-field 'contribution-languages #f
                       (bundle-contribution-languages value) owner)]
    [(not (and (unique-list? (bundle-contribution-artifacts value) string=?)
               (andmap (lambda (identity) (member identity artifacts string=?))
                       (bundle-contribution-artifacts value))))
     (bundle-rejection 'unknown-reference 'contribution-artifacts #f
                       (bundle-contribution-artifacts value) owner)]
    [(not (and (unique-list? (bundle-contribution-dependencies value) string=?)
               (andmap (lambda (identity) (member identity dependencies string=?))
                       (bundle-contribution-dependencies value))))
     (bundle-rejection 'unknown-reference 'contribution-dependencies #f
                       (bundle-contribution-dependencies value) owner)]
    [(not (and (unique-list? (bundle-contribution-authorities value) eq?)
               (andmap (lambda (authority) (memq authority authorities))
                       (bundle-contribution-authorities value))))
     (bundle-rejection 'unknown-reference 'contribution-authorities #f
                       (bundle-contribution-authorities value) owner)]
    [else #f]))

(define (validate-bundle-manifest value)
  (cond
    [(not (bundle-manifest? value))
     (bundle-rejection 'invalid-field 'manifest #f value "")]
    [(not (= (bundle-manifest-format-version value) 1))
     (bundle-rejection 'unsupported-format 'format-version 1
                       (bundle-manifest-format-version value) "")]
    [(not (identity? (bundle-manifest-identity value)))
     (bundle-rejection 'invalid-field 'identity
                       (hash-ref bundle-limits 'identity-bytes)
                       (bundle-manifest-identity value) "")]
    [(not (bounded-text? (bundle-manifest-display-name value)
                         (hash-ref bundle-limits 'display-name-bytes)))
     (bundle-rejection 'limit 'display-name
                       (hash-ref bundle-limits 'display-name-bytes)
                       (utf8-length (bundle-manifest-display-name value))
                       (bundle-manifest-identity value))]
    [(not (version? (bundle-manifest-version value)))
     (bundle-rejection 'invalid-field 'version #f
                       (bundle-manifest-version value)
                       (bundle-manifest-identity value))]
    [(not (api-range? (bundle-manifest-api-range value)))
     (bundle-rejection 'invalid-field 'api-range #f
                       (bundle-manifest-api-range value)
                       (bundle-manifest-identity value))]
    [(not (bounded-text? (bundle-manifest-description value)
                         (hash-ref bundle-limits 'description-bytes)))
     (bundle-rejection 'limit 'description
                       (hash-ref bundle-limits 'description-bytes)
                       (utf8-length (bundle-manifest-description value))
                       (bundle-manifest-identity value))]
    [(not (bounded-text? (bundle-manifest-publisher value)
                         (hash-ref bundle-limits 'publisher-bytes)))
     (bundle-rejection 'invalid-field 'publisher #f
                       (bundle-manifest-publisher value)
                       (bundle-manifest-identity value))]
    [(not (bounded-text? (bundle-manifest-source value)
                         (hash-ref bundle-limits 'source-bytes)))
     (bundle-rejection 'invalid-field 'source #f
                       (bundle-manifest-source value)
                       (bundle-manifest-identity value))]
    [(not (target-set? (bundle-manifest-targets value)))
     (bundle-rejection 'invalid-field 'targets
                       (hash-ref bundle-limits 'targets)
                       (bundle-manifest-targets value)
                       (bundle-manifest-identity value))]
    [(not (admitted-set? (bundle-manifest-authorities value)
                         admitted-authorities
                         (hash-ref bundle-limits 'authorities)))
     (bundle-rejection 'invalid-field 'authorities #f
                       (bundle-manifest-authorities value)
                       (bundle-manifest-identity value))]
    [else
     (validate-bundle-collections value)]))

(define (validate-bundle-collections value)
  (define owner (bundle-manifest-identity value))
  (define dependencies (bundle-manifest-dependencies value))
  (define artifacts (bundle-manifest-artifacts value))
  (define contributions (bundle-manifest-contributions value))
  (cond
    [(or (not (list? dependencies))
         (> (length dependencies) (hash-ref bundle-limits 'dependencies)))
     (bundle-rejection 'limit 'dependencies
                       (hash-ref bundle-limits 'dependencies)
                       (if (list? dependencies) (length dependencies) dependencies)
                       owner)]
    [(or (not (list? artifacts))
         (> (length artifacts) (hash-ref bundle-limits 'artifacts)))
     (bundle-rejection 'limit 'artifacts
                       (hash-ref bundle-limits 'artifacts)
                       (if (list? artifacts) (length artifacts) artifacts)
                       owner)]
    [(or (not (list? contributions))
         (> (length contributions) (hash-ref bundle-limits 'contributions)))
     (bundle-rejection 'limit 'contributions
                       (hash-ref bundle-limits 'contributions)
                       (if (list? contributions) (length contributions) contributions)
                       owner)]
    [(not (andmap bundle-dependency? dependencies))
     (bundle-rejection 'invalid-field 'dependency #f #f owner)]
    [(not (andmap bundle-artifact? artifacts))
     (bundle-rejection 'invalid-field 'artifact #f #f owner)]
    [(not (andmap bundle-contribution? contributions))
     (bundle-rejection 'invalid-field 'contribution #f #f owner)]
    [(not (unique-list? (map bundle-dependency-identity dependencies) string=?))
     (bundle-rejection 'duplicate-identity 'dependencies #f #f owner)]
    [(not (unique-list? (map bundle-artifact-identity artifacts) string=?))
     (bundle-rejection 'duplicate-identity 'artifacts #f #f owner)]
    [(not (unique-list? (map (lambda (entry)
                              (cons (bundle-contribution-kind entry)
                                    (bundle-contribution-identity entry)))
                            contributions)
                        equal?))
     (bundle-rejection 'duplicate-identity 'contributions #f #f owner)]
    [else
     (or (for/or ([entry (in-list dependencies)])
           (validate-dependency entry owner))
         (for/or ([entry (in-list artifacts)])
           (validate-artifact entry owner))
         (let ([artifact-identities (map bundle-artifact-identity artifacts)]
               [dependency-identities (map bundle-dependency-identity dependencies)]
               [authorities (bundle-manifest-authorities value)])
           (for/or ([entry (in-list contributions)])
             (validate-contribution entry owner artifact-identities
                                    dependency-identities authorities)))
         (and (bundle-manifest-entrypoint value)
              (not (and (valid-relative-path? (bundle-manifest-entrypoint value))
                        (for/or ([artifact (in-list artifacts)])
                          (and (eq? (bundle-artifact-kind artifact) 'racket-module)
                               (string=? (bundle-artifact-path artifact)
                                         (bundle-manifest-entrypoint value))))))
              (bundle-rejection 'unknown-reference 'entrypoint #f
                                (bundle-manifest-entrypoint value) owner)))]))

(define (version->datum value)
  (list (bundle-version-major value)
        (bundle-version-minor value)
        (bundle-version-patch value)
        (bundle-version-pre-release value)))

(define (dependency->datum value)
  (list (bundle-dependency-identity value)
        (version->datum (bundle-dependency-minimum value))
        (version->datum (bundle-dependency-maximum value))
        (bundle-dependency-optional? value)
        (sort (bundle-dependency-facets value) symbol<?)))

(define (artifact->datum value)
  (list (bundle-artifact-identity value)
        (bundle-artifact-kind value)
        (bundle-artifact-path value)
        (bundle-artifact-digest value)
        (bundle-artifact-size value)
        (map target->datum (sort-targets (bundle-artifact-targets value)))
        (bundle-artifact-authority value)))

(define (target->datum value)
  (list (bundle-target-platform value)
        (bundle-target-architecture value)))

(define (target<? left right)
  (string<? (format "~a/~a" (bundle-target-platform left)
                    (bundle-target-architecture left))
            (format "~a/~a" (bundle-target-platform right)
                    (bundle-target-architecture right))))

(define (sort-targets values)
  (sort values target<?))

(define (contribution->datum value)
  (list (bundle-contribution-kind value)
        (bundle-contribution-identity value)
        (sort (bundle-contribution-languages value) string<?)
        (sort (bundle-contribution-artifacts value) string<?)
        (sort (bundle-contribution-dependencies value) string<?)
        (sort (bundle-contribution-authorities value) symbol<?)))

(define (manifest->datum value)
  (list 'language-support-bundle
        (bundle-manifest-format-version value)
        (bundle-manifest-identity value)
        (bundle-manifest-display-name value)
        (version->datum (bundle-manifest-version value))
        (list (version->datum (bundle-api-range-minimum
                              (bundle-manifest-api-range value)))
              (version->datum (bundle-api-range-maximum
                              (bundle-manifest-api-range value))))
        (bundle-manifest-description value)
        (bundle-manifest-publisher value)
        (bundle-manifest-source value)
        (map target->datum (sort-targets (bundle-manifest-targets value)))
        (map dependency->datum
             (sort (bundle-manifest-dependencies value) string<?
                   #:key bundle-dependency-identity))
        (sort (bundle-manifest-authorities value) symbol<?)
        (map contribution->datum
             (sort (bundle-manifest-contributions value)
                   string<?
                   #:key (lambda (entry)
                           (format "~a/~a"
                                   (bundle-contribution-kind entry)
                                   (bundle-contribution-identity entry)))))
        (map artifact->datum
             (sort (bundle-manifest-artifacts value) string<?
                   #:key bundle-artifact-identity))
        (bundle-manifest-entrypoint value)))

(define (bundle-manifest->canonical-bytes value)
  (define rejection (validate-bundle-manifest value))
  (when rejection
    (raise-arguments-error
     'bundle-manifest->canonical-bytes
     "manifest is not valid"
     "rejection" rejection))
  (define output (open-output-bytes))
  (parameterize ([print-graph #f]
                 [print-unreadable #f])
    (write (manifest->datum value) output))
  (bytes->immutable-bytes (get-output-bytes output #t)))

(define (confirm-bundle-manifest value)
  (define rejection (validate-bundle-manifest value))
  (if rejection
      (values #f rejection)
      (let ([encoded (bundle-manifest->canonical-bytes value)])
        (if (> (bytes-length encoded) (hash-ref bundle-limits 'manifest-bytes))
            (values #f
                    (bundle-rejection 'limit 'manifest-bytes
                                      (hash-ref bundle-limits 'manifest-bytes)
                                      (bytes-length encoded)
                                      (bundle-manifest-identity value)))
            (values encoded #f)))))

(define (select-bundle-artifact value identity platform architecture)
  (define matches
    (for/list ([artifact (in-list (bundle-manifest-artifacts value))]
               #:when (and (string=? identity (bundle-artifact-identity artifact))
                           (member (bundle-target platform architecture)
                                   (bundle-artifact-targets artifact)
                                   equal?)))
      artifact))
  (cond
    [(null? matches)
     (values #f (bundle-rejection 'unavailable-platform 'artifact #f identity
                                  (bundle-manifest-identity value)))]
    [(pair? (cdr matches))
     (values #f (bundle-rejection 'ambiguous-platform 'artifact 1
                                  (length matches)
                                  (bundle-manifest-identity value)))]
    [else (values (car matches) #f)]))

(define (bundle-api-compatible? value api-version)
  (and (bundle-manifest? value)
       (api-range? (bundle-manifest-api-range value))
       (version? api-version)
       (version<=? (bundle-api-range-minimum (bundle-manifest-api-range value))
                   api-version)
       (version<=? api-version
                   (bundle-api-range-maximum (bundle-manifest-api-range value)))))

(define (validate-bundle-resource-profile profile)
  (and (hash? profile)
       (for/and ([field (in-list '(dependencies artifacts contributions authorities
                                               targets manifest-bytes))])
         (define value (hash-ref profile field #f))
         (and (exact-nonnegative-integer? value)
              (<= value (hash-ref bundle-limits field))))))
