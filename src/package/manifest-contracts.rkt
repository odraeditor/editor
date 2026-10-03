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
         racket/string
         "../storage/record-codec.rkt"
         "authority-contract.rkt")

(provide
 current-package-manifest-format-version
 maximum-package-manifest-dependencies
 maximum-package-manifest-artifacts
 maximum-package-manifest-contributions
 maximum-package-manifest-documentation-links
 maximum-package-manifest-expanded-bytes
 (struct-out odra-package-target)
 (struct-out odra-package-version-constraint)
 (struct-out odra-package-dependency)
 (struct-out odra-package-artifact)
 (struct-out odra-package-entrypoint)
 (struct-out odra-package-contribution)
 (struct-out odra-package-documentation)
 (struct-out odra-package-state-compatibility)
 (struct-out odra-package-manifest-proposal)
 (struct-out odra-package-manifest-rejection)
 odra-package-manifest?
 odra-package-manifest-format-version
 odra-package-manifest-package-id
 odra-package-manifest-kind
 odra-package-manifest-display-name
 odra-package-manifest-version
 odra-package-manifest-description
 odra-package-manifest-license-id
 odra-package-manifest-license-artifact
 odra-package-manifest-publisher-id
 odra-package-manifest-source-revision
 odra-package-manifest-api-minimum
 odra-package-manifest-api-maximum
 odra-package-manifest-targets
 odra-package-manifest-dependencies
 odra-package-manifest-authorities
 odra-package-manifest-artifacts
 odra-package-manifest-entrypoint
 odra-package-manifest-contributions
 odra-package-manifest-documentation
 odra-package-manifest-state-compatibility
 (contract-out
  [package-manifest->canonical-bytes
   (-> odra-package-manifest? immutable-bytes?)]
  [package-manifest-digest (-> odra-package-manifest? string?)]
  [package-manifest-api-compatible?
   (-> odra-package-manifest? string? boolean?)]
  [package-manifest-module-parse
   (-> bytes? path-string?
       (or/c odra-package-manifest? odra-record-diagnostic?))]
  [package-manifest-module-load
   (-> path-string?
       (or/c odra-package-manifest? odra-record-diagnostic?))]
  [confirm-package-manifest
   (-> odra-package-manifest-proposal?
       (values (or/c #f odra-package-manifest?)
               (or/c #f odra-package-manifest-rejection?)))]))

(define current-package-manifest-format-version 1)
(define maximum-package-identity-bytes 128)
(define maximum-package-display-name-bytes 256)
(define maximum-package-description-bytes 4096)
(define maximum-package-license-bytes 128)
(define maximum-package-path-bytes 4096)
(define maximum-package-uri-bytes 4096)
(define maximum-package-source-revision-bytes 128)
(define maximum-package-manifest-dependencies 256)
(define maximum-package-dependency-constraints 8)
(define maximum-package-dependency-facets 8)
(define maximum-package-manifest-authorities 16)
(define maximum-package-manifest-artifacts 8192)
(define maximum-package-artifact-locations 16)
(define maximum-package-manifest-contributions 1024)
(define maximum-package-contribution-properties 32)
(define maximum-package-manifest-documentation-links 32)
(define maximum-package-manifest-expanded-bytes (expt 2 30))

(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
(define version-pattern
  #px"^(?:0|[1-9][0-9]*)\\.(?:0|[1-9][0-9]*)\\.(?:0|[1-9][0-9]*)(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$")
(define digest-pattern #px"^[0-9a-f]{64}$")
(define source-revision-pattern #px"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")
(define license-pattern #px"^[A-Za-z0-9][A-Za-z0-9.+-]*$")
(define admitted-package-kinds '(extension language-support))
(define admitted-platforms '(darwin linux windows))
(define admitted-architectures '(aarch64 x86-64))
(define admitted-constraint-kinds '(exact minimum maximum compatible-major))
(define admitted-facets
  '(agent agent-capability command formatter keymap language service
          syntax-provider))
(define admitted-artifact-kinds
  '(data documentation grammar license manifest query racket-module runtime-adapter))
(define admitted-documentation-kinds '(issues reference source support tutorial))
(define admitted-cleanup-policies '(none preserve remove-after-confirmation))

(define (copied-text value)
  (string->immutable-string value))

(define (immutable-bytes? value)
  (and (bytes? value) (immutable? value)))

(define (bounded-text? value maximum #:empty? [empty? #f])
  (and (string? value)
       (or empty? (positive? (string-length value)))
       (not (string-contains? value (string #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (identity? value)
  (and (bounded-text? value maximum-package-identity-bytes)
       (regexp-match? identity-pattern value)))

(define (version? value)
  (and (bounded-text? value maximum-package-identity-bytes)
       (regexp-match? version-pattern value)))

(define (digest? value)
  (and (string? value) (regexp-match? digest-pattern value)))

(define (source-revision? value)
  (and (bounded-text? value maximum-package-source-revision-bytes)
       (regexp-match? source-revision-pattern value)))

(define (relative-path? value)
  (and (bounded-text? value maximum-package-path-bytes)
       (not (regexp-match? #px"^(?:/|\\\\|[A-Za-z]:)" value))
       (for/and ([part (in-list (string-split value "/"))])
         (not (member part '("" "." ".."))))))

(define (https-uri? value)
  (and (bounded-text? value maximum-package-uri-bytes)
       (regexp-match? #px"^https://[^/@?#]+(?::[0-9]+)?/[^?#]*$" value)))

(define (symbol<? left right)
  (string<? (symbol->string left) (symbol->string right)))

(define (unique-sorted? values less?)
  (and (list? values)
       (equal? values (sort (remove-duplicates values) less?))))

(define (symbol-set? values admitted maximum)
  (and (list? values)
       (andmap symbol? values)
       (unique-sorted? values symbol<?)
       (<= (length values) maximum)
       (andmap (lambda (value) (and (memq value admitted) #t)) values)))

(define (semantic-symbol-set? values maximum)
  (and (list? values)
       (andmap symbol? values)
       (<= (length values) maximum)
       (andmap (lambda (value) (identity? (symbol->string value))) values)
       (equal? values (sort (remove-duplicates values) symbol<?))))

(define (version-components value)
  (match (regexp-match #px"^([0-9]+)\\.([0-9]+)\\.([0-9]+)(?:-(.+))?$" value)
    [(list _ major minor patch prerelease)
     (list (string->number major) (string->number minor) (string->number patch)
           (and prerelease (string-split prerelease ".")))]))

(define (prerelease-part<? left right)
  (define left-number (string->number left))
  (define right-number (string->number right))
  (cond
    [(and left-number right-number) (< left-number right-number)]
    [left-number #t]
    [right-number #f]
    [else (string<? left right)]))

(define (prerelease<? left right)
  (cond
    [(not left) #f]
    [(not right) #t]
    [else
     (let loop ([left left] [right right])
       (cond
         [(null? left) (pair? right)]
         [(null? right) #f]
         [(string=? (car left) (car right)) (loop (cdr left) (cdr right))]
         [else (prerelease-part<? (car left) (car right))]))]))

(define (version<? left right)
  (match-define (list left-major left-minor left-patch left-prerelease)
    (version-components left))
  (match-define (list right-major right-minor right-patch right-prerelease)
    (version-components right))
  (or (< left-major right-major)
      (and (= left-major right-major)
           (or (< left-minor right-minor)
               (and (= left-minor right-minor)
                    (or (< left-patch right-patch)
                        (and (= left-patch right-patch)
                             (prerelease<? left-prerelease right-prerelease))))))))

(define (version<=? left right)
  (or (string=? left right) (version<? left right)))

(define (package-manifest-api-compatible? manifest version)
  (and (version? version)
       (version<=? (odra-package-manifest-api-minimum manifest) version)
       (version<=? version (odra-package-manifest-api-maximum manifest))))

(struct odra-package-target (platform architecture)
  #:transparent
  #:guard
  (lambda (platform architecture _)
    (unless (and (memq platform admitted-platforms)
                 (memq architecture admitted-architectures))
      (raise-arguments-error 'odra-package-target
                             "unsupported platform or architecture"))
    (values platform architecture)))

(define (target<? left right)
  (string<? (format "~a/~a" (odra-package-target-platform left)
                    (odra-package-target-architecture left))
            (format "~a/~a" (odra-package-target-platform right)
                    (odra-package-target-architecture right))))

(struct odra-package-version-constraint (kind version)
  #:transparent
  #:guard
  (lambda (kind version _)
    (unless (and (memq kind admitted-constraint-kinds) (version? version))
      (raise-arguments-error 'odra-package-version-constraint
                             "invalid semantic-version constraint"))
    (values kind (copied-text version))))

(define (constraint-key value)
  (format "~a/~a" (odra-package-version-constraint-kind value)
          (odra-package-version-constraint-version value)))

(define (constraint<? left right)
  (string<? (constraint-key left) (constraint-key right)))

(define (dependency-constraints-compatible? constraints)
  (define kinds (map odra-package-version-constraint-kind constraints))
  (define (version-for kind)
    (for/first ([constraint (in-list constraints)]
                #:when (eq? kind (odra-package-version-constraint-kind constraint)))
      (odra-package-version-constraint-version constraint)))
  (define exact (version-for 'exact))
  (define minimum (version-for 'minimum))
  (define maximum (version-for 'maximum))
  (and (= (length kinds) (length (remove-duplicates kinds)))
       (or (not exact) (= (length constraints) 1))
       (or (not (and minimum maximum)) (version<=? minimum maximum))))

(struct odra-package-dependency
  (id kind constraints api-minimum api-maximum facets target)
  #:transparent
  #:guard
  (lambda (id kind constraints api-minimum api-maximum facets target _)
    (unless (and (identity? id)
                 (memq kind '(required optional))
                 (unique-sorted? constraints constraint<?)
                 (pair? constraints)
                 (<= (length constraints) maximum-package-dependency-constraints)
                 (andmap odra-package-version-constraint? constraints)
                 (dependency-constraints-compatible? constraints)
                 (version? api-minimum)
                 (version? api-maximum)
                 (version<=? api-minimum api-maximum)
                 (symbol-set? facets admitted-facets maximum-package-dependency-facets)
                 (or (not target) (odra-package-target? target)))
      (raise-arguments-error 'odra-package-dependency
                             "invalid bounded package dependency"))
    (values (copied-text id) kind constraints (copied-text api-minimum)
            (copied-text api-maximum) facets target)))

(define (dependency<? left right)
  (string<? (odra-package-dependency-id left)
            (odra-package-dependency-id right)))

(struct odra-package-artifact
  (role kind path digest size target executable? authority locations)
  #:transparent
  #:guard
  (lambda (role kind path digest size target executable? authority locations _)
    (unless (and (identity? role)
                 (memq kind admitted-artifact-kinds)
                 (relative-path? path)
                 (digest? digest)
                 (exact-nonnegative-integer? size)
                 (<= size maximum-package-manifest-expanded-bytes)
                 (or (not target) (odra-package-target? target))
                 (boolean? executable?)
                 (not executable?)
                 (or (not authority) (package-authority? authority))
                 (unique-sorted? locations string<?)
                 (<= (length locations) maximum-package-artifact-locations)
                 (andmap https-uri? locations))
      (raise-arguments-error 'odra-package-artifact
                             "invalid immutable package artifact descriptor"))
    (values (copied-text role) kind (copied-text path) (copied-text digest) size
            target executable? authority (map copied-text locations))))

(define (artifact<? left right)
  (string<? (odra-package-artifact-path left)
            (odra-package-artifact-path right)))

(struct odra-package-entrypoint (module-path binding)
  #:transparent
  #:guard
  (lambda (module-path binding _)
    (unless (and (relative-path? module-path)
                 (eq? binding 'odra-package-contributions))
      (raise-arguments-error 'odra-package-entrypoint
                             "invalid restricted Racket package entrypoint"))
    (values (copied-text module-path) binding)))

(struct odra-package-contribution (id facet requirements effects)
  #:transparent
  #:guard
  (lambda (id facet requirements effects _)
    (unless (and (identity? id)
                 (memq facet admitted-facets)
                 (semantic-symbol-set? requirements
                                       maximum-package-contribution-properties)
                 (semantic-symbol-set? effects
                                       maximum-package-contribution-properties))
      (raise-arguments-error 'odra-package-contribution
                             "invalid declared package contribution"))
    (values (copied-text id) facet requirements effects)))

(define (contribution<? left right)
  (string<? (format "~a/~a" (odra-package-contribution-facet left)
                    (odra-package-contribution-id left))
            (format "~a/~a" (odra-package-contribution-facet right)
                    (odra-package-contribution-id right))))

(struct odra-package-documentation (kind uri)
  #:transparent
  #:guard
  (lambda (kind uri _)
    (unless (and (memq kind admitted-documentation-kinds) (https-uri? uri))
      (raise-arguments-error 'odra-package-documentation
                             "invalid HTTPS package documentation link"))
    (values kind (copied-text uri))))

(define (documentation<? left right)
  (symbol<? (odra-package-documentation-kind left)
            (odra-package-documentation-kind right)))

(struct odra-package-state-compatibility
  (schema-id minimum maximum cleanup-policy)
  #:transparent
  #:guard
  (lambda (schema-id minimum maximum cleanup-policy _)
    (unless (and (memq cleanup-policy admitted-cleanup-policies)
                 (or (and (not schema-id) (not minimum) (not maximum)
                          (eq? cleanup-policy 'none))
                     (and (identity? schema-id)
                          (version? minimum)
                          (version? maximum)
                          (version<=? minimum maximum)
                          (not (eq? cleanup-policy 'none)))))
      (raise-arguments-error 'odra-package-state-compatibility
                             "invalid managed-state compatibility policy"))
    (values (and schema-id (copied-text schema-id))
            (and minimum (copied-text minimum))
            (and maximum (copied-text maximum))
            cleanup-policy)))

(struct odra-package-manifest-proposal
  (format-version package-id kind display-name version description license-id
                  license-artifact publisher-id source-revision api-minimum api-maximum
                  targets dependencies authorities artifacts entrypoint contributions
                  documentation state-compatibility)
  #:transparent
  #:guard
  (lambda (format-version package-id kind display-name version description license-id
                          license-artifact publisher-id source-revision api-minimum api-maximum
                          targets dependencies authorities artifacts entrypoint contributions
                          documentation state-compatibility _)
    (unless (and (exact-positive-integer? format-version)
                 (string? package-id)
                 (symbol? kind)
                 (string? display-name)
                 (string? version)
                 (string? description)
                 (string? license-id)
                 (or (not license-artifact) (string? license-artifact))
                 (string? publisher-id)
                 (string? source-revision)
                 (string? api-minimum)
                 (string? api-maximum)
                 (list? targets)
                 (list? dependencies)
                 (list? authorities)
                 (list? artifacts)
                 (or (not entrypoint) (odra-package-entrypoint? entrypoint))
                 (list? contributions)
                 (list? documentation)
                 (odra-package-state-compatibility? state-compatibility))
      (raise-arguments-error 'odra-package-manifest-proposal
                             "manifest proposal fields have invalid primitive types"))
    (values format-version (copied-text package-id) kind (copied-text display-name)
            (copied-text version) (copied-text description) (copied-text license-id)
            (and license-artifact (copied-text license-artifact))
            (copied-text publisher-id) (copied-text source-revision)
            (copied-text api-minimum) (copied-text api-maximum)
            (for/list ([value (in-list targets)]) value)
            (for/list ([value (in-list dependencies)]) value)
            (for/list ([value (in-list authorities)]) value)
            (for/list ([value (in-list artifacts)]) value)
            entrypoint
            (for/list ([value (in-list contributions)]) value)
            (for/list ([value (in-list documentation)]) value)
            state-compatibility)))

(struct odra-package-manifest
  (format-version package-id kind display-name version description license-id
                  license-artifact publisher-id source-revision api-minimum api-maximum
                  targets dependencies authorities artifacts entrypoint contributions
                  documentation state-compatibility)
  #:transparent)

(struct odra-package-manifest-rejection (code field limit actual package-id)
  #:transparent
  #:guard
  (lambda (code field limit actual package-id _)
    (unless (and (memq code '(duplicate-identity invalid-field limit
                                                 self-dependency unsupported-format))
                 (symbol? field)
                 (or (not limit) (exact-nonnegative-integer? limit))
                 (or (not actual) (exact-nonnegative-integer? actual))
                 (string? package-id))
      (raise-arguments-error 'odra-package-manifest-rejection
                             "invalid typed package manifest rejection"))
    (values code field limit actual (copied-text package-id))))

(define (proposal-id proposal)
  (odra-package-manifest-proposal-package-id proposal))

(define (reject proposal code field [limit #f] [actual #f])
  (odra-package-manifest-rejection
   code field limit actual
   (if (identity? (proposal-id proposal)) (proposal-id proposal) "")))

(define (duplicate? values key equal?)
  (not (= (length values)
          (length (remove-duplicates (map key values) equal?)))))

(define (artifact-path-kind? artifacts path kind)
  (for/or ([artifact (in-list artifacts)])
    (and (string=? path (odra-package-artifact-path artifact))
         (eq? kind (odra-package-artifact-kind artifact)))))

(define (manifest-rejection proposal)
  (define targets (odra-package-manifest-proposal-targets proposal))
  (define dependencies (odra-package-manifest-proposal-dependencies proposal))
  (define authorities (odra-package-manifest-proposal-authorities proposal))
  (define artifacts (odra-package-manifest-proposal-artifacts proposal))
  (define entrypoint (odra-package-manifest-proposal-entrypoint proposal))
  (define contributions (odra-package-manifest-proposal-contributions proposal))
  (define documentation (odra-package-manifest-proposal-documentation proposal))
  (cond
    [(not (= (odra-package-manifest-proposal-format-version proposal)
             current-package-manifest-format-version))
     (reject proposal 'unsupported-format 'format-version)]
    [(not (identity? (proposal-id proposal)))
     (reject proposal 'invalid-field 'package-id)]
    [(not (memq (odra-package-manifest-proposal-kind proposal)
                admitted-package-kinds))
     (reject proposal 'invalid-field 'kind)]
    [(not (bounded-text? (odra-package-manifest-proposal-display-name proposal)
                         maximum-package-display-name-bytes))
     (reject proposal 'invalid-field 'display-name)]
    [(not (version? (odra-package-manifest-proposal-version proposal)))
     (reject proposal 'invalid-field 'version)]
    [(not (bounded-text? (odra-package-manifest-proposal-description proposal)
                         maximum-package-description-bytes #:empty? #t))
     (reject proposal 'invalid-field 'description)]
    [(not (and (bounded-text? (odra-package-manifest-proposal-license-id proposal)
                              maximum-package-license-bytes)
               (regexp-match? license-pattern
                              (odra-package-manifest-proposal-license-id proposal))))
     (reject proposal 'invalid-field 'license-id)]
    [(not (and (identity? (odra-package-manifest-proposal-publisher-id proposal))
               (source-revision? (odra-package-manifest-proposal-source-revision proposal))))
     (reject proposal 'invalid-field 'provenance)]
    [(not (and (version? (odra-package-manifest-proposal-api-minimum proposal))
               (version? (odra-package-manifest-proposal-api-maximum proposal))
               (version<=? (odra-package-manifest-proposal-api-minimum proposal)
                           (odra-package-manifest-proposal-api-maximum proposal))))
     (reject proposal 'invalid-field 'api-compatibility)]
    [(or (null? targets)
         (> (length targets) 16)
         (not (andmap odra-package-target? targets)))
     (reject proposal 'limit 'targets 16 (length targets))]
    [(not (= (length targets) (length (remove-duplicates targets))))
     (reject proposal 'duplicate-identity 'targets)]
    [(> (length dependencies) maximum-package-manifest-dependencies)
     (reject proposal 'limit 'dependencies maximum-package-manifest-dependencies
             (length dependencies))]
    [(not (andmap odra-package-dependency? dependencies))
     (reject proposal 'invalid-field 'dependencies)]
    [(for/or ([dependency (in-list dependencies)])
       (string=? (proposal-id proposal) (odra-package-dependency-id dependency)))
     (reject proposal 'self-dependency 'dependencies)]
    [(duplicate? dependencies odra-package-dependency-id string=?)
     (reject proposal 'duplicate-identity 'dependencies)]
    [(not (package-authority-set? authorities
                                  #:maximum maximum-package-manifest-authorities
                                  #:ordered? #f))
     (reject proposal 'invalid-field 'authorities)]
    [(or (null? artifacts)
         (> (length artifacts) maximum-package-manifest-artifacts))
     (reject proposal 'limit 'artifacts maximum-package-manifest-artifacts
             (length artifacts))]
    [(not (andmap odra-package-artifact? artifacts))
     (reject proposal 'invalid-field 'artifacts)]
    [(for/or ([artifact (in-list artifacts)])
       (string=? "odra-package.rktd"
                 (odra-package-artifact-path artifact)))
     (reject proposal 'invalid-field 'artifacts)]
    [(or (duplicate? artifacts odra-package-artifact-role string=?)
         (duplicate? artifacts odra-package-artifact-path string=?))
     (reject proposal 'duplicate-identity 'artifacts)]
    [(and (odra-package-manifest-proposal-license-artifact proposal)
          (not (artifact-path-kind?
                artifacts
                (odra-package-manifest-proposal-license-artifact proposal)
                'license)))
     (reject proposal 'invalid-field 'license-artifact)]
    [(> (for/sum ([artifact (in-list artifacts)])
          (odra-package-artifact-size artifact))
        maximum-package-manifest-expanded-bytes)
     (reject proposal 'limit 'expanded-bytes maximum-package-manifest-expanded-bytes
             (for/sum ([artifact (in-list artifacts)])
               (odra-package-artifact-size artifact)))]
    [(> (length contributions) maximum-package-manifest-contributions)
     (reject proposal 'limit 'contributions maximum-package-manifest-contributions
             (length contributions))]
    [(not (andmap odra-package-contribution? contributions))
     (reject proposal 'invalid-field 'contributions)]
    [(duplicate? contributions
                 (lambda (value)
                   (cons (odra-package-contribution-facet value)
                         (odra-package-contribution-id value)))
                 equal?)
     (reject proposal 'duplicate-identity 'contributions)]
    [(and (pair? contributions) (not entrypoint))
     (reject proposal 'invalid-field 'entrypoint)]
    [(and entrypoint
          (not (artifact-path-kind? artifacts
                                    (odra-package-entrypoint-module-path entrypoint)
                                    'racket-module)))
     (reject proposal 'invalid-field 'entrypoint)]
    [(and entrypoint (not (memq 'racket-extension authorities)))
     (reject proposal 'invalid-field 'authorities)]
    [(> (length documentation) maximum-package-manifest-documentation-links)
     (reject proposal 'limit 'documentation
             maximum-package-manifest-documentation-links
             (length documentation))]
    [(not (andmap odra-package-documentation? documentation))
     (reject proposal 'invalid-field 'documentation)]
    [(duplicate? documentation odra-package-documentation-kind eq?)
     (reject proposal 'duplicate-identity 'documentation)]
    [else #f]))

(define (confirm-package-manifest proposal)
  (define rejection (manifest-rejection proposal))
  (if rejection
      (values #f rejection)
      (values
       (odra-package-manifest
        current-package-manifest-format-version
        (proposal-id proposal)
        (odra-package-manifest-proposal-kind proposal)
        (odra-package-manifest-proposal-display-name proposal)
        (odra-package-manifest-proposal-version proposal)
        (odra-package-manifest-proposal-description proposal)
        (odra-package-manifest-proposal-license-id proposal)
        (odra-package-manifest-proposal-license-artifact proposal)
        (odra-package-manifest-proposal-publisher-id proposal)
        (odra-package-manifest-proposal-source-revision proposal)
        (odra-package-manifest-proposal-api-minimum proposal)
        (odra-package-manifest-proposal-api-maximum proposal)
        (sort (remove-duplicates (odra-package-manifest-proposal-targets proposal))
              target<?)
        (sort (odra-package-manifest-proposal-dependencies proposal) dependency<?)
        (sort (odra-package-manifest-proposal-authorities proposal) symbol<?)
        (sort (odra-package-manifest-proposal-artifacts proposal) artifact<?)
        (odra-package-manifest-proposal-entrypoint proposal)
        (sort (odra-package-manifest-proposal-contributions proposal) contribution<?)
        (sort (odra-package-manifest-proposal-documentation proposal) documentation<?)
       (odra-package-manifest-proposal-state-compatibility proposal))
       #f)))

(define (target->datum value)
  (list (odra-package-target-platform value)
        (odra-package-target-architecture value)))

(define (constraint->datum value)
  (list (odra-package-version-constraint-kind value)
        (odra-package-version-constraint-version value)))

(define (dependency->datum value)
  (list (odra-package-dependency-id value)
        (odra-package-dependency-kind value)
        (map constraint->datum (odra-package-dependency-constraints value))
        (odra-package-dependency-api-minimum value)
        (odra-package-dependency-api-maximum value)
        (odra-package-dependency-facets value)
        (and (odra-package-dependency-target value)
             (target->datum (odra-package-dependency-target value)))))

(define (artifact->datum value)
  (list (odra-package-artifact-role value)
        (odra-package-artifact-kind value)
        (odra-package-artifact-path value)
        (odra-package-artifact-digest value)
        (odra-package-artifact-size value)
        (and (odra-package-artifact-target value)
             (target->datum (odra-package-artifact-target value)))
        (odra-package-artifact-executable? value)
        (odra-package-artifact-authority value)
        (odra-package-artifact-locations value)))

(define (entrypoint->datum value)
  (and value
       (list (odra-package-entrypoint-module-path value)
             (odra-package-entrypoint-binding value))))

(define (contribution->datum value)
  (list (odra-package-contribution-id value)
        (odra-package-contribution-facet value)
        (odra-package-contribution-requirements value)
        (odra-package-contribution-effects value)))

(define (documentation->datum value)
  (list (odra-package-documentation-kind value)
        (odra-package-documentation-uri value)))

(define (state-compatibility->datum value)
  (list (odra-package-state-compatibility-schema-id value)
        (odra-package-state-compatibility-minimum value)
        (odra-package-state-compatibility-maximum value)
        (odra-package-state-compatibility-cleanup-policy value)))

(define (manifest->datum value)
  (list 'odra-package-manifest
        '#:format-version (odra-package-manifest-format-version value)
        '#:package-id (odra-package-manifest-package-id value)
        '#:kind (odra-package-manifest-kind value)
        '#:display-name (odra-package-manifest-display-name value)
        '#:version (odra-package-manifest-version value)
        '#:description (odra-package-manifest-description value)
        '#:license-id (odra-package-manifest-license-id value)
        '#:license-artifact (odra-package-manifest-license-artifact value)
        '#:publisher-id (odra-package-manifest-publisher-id value)
        '#:source-revision (odra-package-manifest-source-revision value)
        '#:api-minimum (odra-package-manifest-api-minimum value)
        '#:api-maximum (odra-package-manifest-api-maximum value)
        '#:targets (map target->datum (odra-package-manifest-targets value))
        '#:dependencies
        (map dependency->datum (odra-package-manifest-dependencies value))
        '#:authorities (odra-package-manifest-authorities value)
        '#:artifacts (map artifact->datum (odra-package-manifest-artifacts value))
        '#:entrypoint (entrypoint->datum (odra-package-manifest-entrypoint value))
        '#:contributions
        (map contribution->datum (odra-package-manifest-contributions value))
        '#:documentation
        (map documentation->datum (odra-package-manifest-documentation value))
        '#:state-compatibility
        (state-compatibility->datum
         (odra-package-manifest-state-compatibility value))))

(define (package-manifest->canonical-bytes value)
  (record-datum->module-bytes (manifest->datum value)))

(define (package-manifest-digest value)
  (bytes->hex-string
   (sha256-bytes
    (open-input-bytes (package-manifest->canonical-bytes value)))))

(define (datum->target value)
  (match value
    [(list platform architecture) (odra-package-target platform architecture)]
    [_ (raise-arguments-error 'odra-package-manifest "invalid target")]))

(define (datum->constraint value)
  (match value
    [(list kind version) (odra-package-version-constraint kind version)]
    [_ (raise-arguments-error 'odra-package-manifest "invalid constraint")]))

(define (datum->dependency value)
  (match value
    [(list id kind constraints api-minimum api-maximum facets target)
     (odra-package-dependency
      id kind (map datum->constraint constraints) api-minimum api-maximum facets
      (and target (datum->target target)))]
    [_ (raise-arguments-error 'odra-package-manifest "invalid dependency")]))

(define (datum->artifact value)
  (match value
    [(list role kind path digest size target executable? authority locations)
     (odra-package-artifact
      role kind path digest size (and target (datum->target target)) executable?
      authority locations)]
    [_ (raise-arguments-error 'odra-package-manifest "invalid artifact")]))

(define (datum->entrypoint value)
  (match value
    [#f #f]
    [(list module-path binding) (odra-package-entrypoint module-path binding)]
    [_ (raise-arguments-error 'odra-package-manifest "invalid entrypoint")]))

(define (datum->contribution value)
  (match value
    [(list id facet requirements effects)
     (odra-package-contribution id facet requirements effects)]
    [_ (raise-arguments-error 'odra-package-manifest "invalid contribution")]))

(define (datum->documentation value)
  (match value
    [(list kind uri) (odra-package-documentation kind uri)]
    [_ (raise-arguments-error 'odra-package-manifest "invalid documentation")]))

(define (datum->state-compatibility value)
  (match value
    [(list schema-id minimum maximum cleanup-policy)
     (odra-package-state-compatibility
      schema-id minimum maximum cleanup-policy)]
    [_
     (raise-arguments-error 'odra-package-manifest
                            "invalid state compatibility")]))

(define (decode-manifest value)
  (match value
    [(list 'odra-package-manifest
           '#:format-version format-version
           '#:package-id package-id
           '#:kind kind
           '#:display-name display-name
           '#:version version
           '#:description description
           '#:license-id license-id
           '#:license-artifact license-artifact
           '#:publisher-id publisher-id
           '#:source-revision source-revision
           '#:api-minimum api-minimum
           '#:api-maximum api-maximum
           '#:targets targets
           '#:dependencies dependencies
           '#:authorities authorities
           '#:artifacts artifacts
           '#:entrypoint entrypoint
           '#:contributions contributions
           '#:documentation documentation
           '#:state-compatibility state-compatibility)
     (define-values (manifest rejection)
       (confirm-package-manifest
        (odra-package-manifest-proposal
         format-version package-id kind display-name version description
         license-id license-artifact publisher-id source-revision api-minimum
         api-maximum (map datum->target targets)
         (map datum->dependency dependencies) authorities
         (map datum->artifact artifacts) (datum->entrypoint entrypoint)
         (map datum->contribution contributions)
         (map datum->documentation documentation)
         (datum->state-compatibility state-compatibility))))
     (when rejection
       (raise-arguments-error 'odra-package-manifest
                              "manifest confirmation rejected"))
     manifest]
    [_ (raise-arguments-error 'odra-package-manifest
                              "unsupported package manifest schema")]))

(define (package-manifest-module-parse bytes source)
  (record-module-parse bytes source decode-manifest))

(define (package-manifest-module-load path)
  (record-module-load path decode-manifest))
