#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         racket/match
         racket/string)

(provide catalog-limits
         catalog-resource-profiles
         (struct-out language-definition)
         (struct-out catalog)
         (struct-out association)
         (struct-out rejection)
         confirm-catalog
         resolve-language
         estimate-retained-bytes
         estimate-temporary-bytes
         validate-resource-profile)

;; These operating limits mirror the first bounded native catalog contract.
(define catalog-limits
  '#hasheq((languages . 32)
           (selectors-per-language . 16)
           (exact-filenames-per-language . 8)
           (suffixes-per-language . 8)
           (selectors-total . 512)
           (identity-bytes . 64)
           (display-name-bytes . 96)
           (selector-bytes . 32)
           (provenance-bytes . 256)
           (retained-bytes . 1048576)
           (temporary-bytes . 2097152)))

;; Ordinary and boundary profiles select the initial fixed catalog capacities.
(define catalog-resource-profiles
  (list
   '#hasheq((name . ordinary)
            (languages . 3)
            (selectors . 4)
            (identity-bytes . 13)
            (display-name-bytes . 20)
            (selector-bytes . 18)
            (provenance-bytes . 72))
   '#hasheq((name . demanding)
            (languages . 24)
            (selectors . 192)
            (identity-bytes . 1152)
            (display-name-bytes . 1728)
            (selector-bytes . 4608)
            (provenance-bytes . 4608))
   '#hasheq((name . boundary)
            (languages . 32)
            (selectors . 512)
            (identity-bytes . 2048)
            (display-name-bytes . 3072)
            (selector-bytes . 16384)
            (provenance-bytes . 8192))))

;; A definition is immutable source data and never contains a capability provider.
(struct language-definition
  (identity display-name source scope source-generation exact-filenames suffixes provenance)
  #:transparent)

;; A catalog is one complete confirmed generation in canonical order.
(struct catalog (generation definitions latest-rejection) #:transparent)

;; An association retains the winning selector and the shadowed alternatives.
(struct association
  (catalog-generation identity selector-kind selector source scope source-generation shadowed)
  #:transparent)

;; A rejection identifies the violated field and preserves source provenance.
(struct rejection (code field limit actual source scope source-generation) #:transparent)

(define empty-catalog (catalog 0 '() #f))

;; Confirmation validates the complete candidate before replacing the prior snapshot.
(define (confirm-catalog previous candidate-generation definitions)
  (define current (or previous empty-catalog))
  (define stale
    (and (exact-integer? candidate-generation)
         (<= candidate-generation (catalog-generation current))))
  (define failure
    (cond
      [(or (not (exact-integer? candidate-generation))
           (not (positive? candidate-generation)))
       (rejection 'invalid-generation 'catalog-generation #f candidate-generation
                  'factory "" 0)]
      [stale
       (rejection 'stale-generation 'catalog-generation
                  (add1 (catalog-generation current)) candidate-generation
                  'factory "" 0)]
      [else (validate-definitions definitions)]))
  (if failure
      (values (struct-copy catalog current [latest-rejection failure]) #f failure)
      (values (catalog candidate-generation (canonical-definitions definitions) #f)
              #t
              #f)))

;; Resolution applies explicit choice first, then source and selector specificity.
(define (resolve-language confirmed target-path
                          #:explicit [explicit #f]
                          #:project-scope [project-scope #f])
  (cond
    [(or (not (catalog? confirmed))
         (not (exact-positive-integer? (catalog-generation confirmed))))
     (values #f (rejection 'invalid-catalog 'catalog-generation #f 0 'factory "" 0))]
    [(and explicit (not (valid-identity? explicit)))
     (values #f (rejection 'invalid-explicit 'identity
                           (hash-ref catalog-limits 'identity-bytes)
                           (utf8-length explicit) 'native "" 0))]
    [explicit
     (resolve-explicit confirmed explicit project-scope)]
    [else
     (resolve-path confirmed target-path project-scope)]))

(define (resolve-explicit confirmed identity project-scope)
  (define candidates
    (filter (lambda (definition)
              (and (string=? identity (language-definition-identity definition))
                   (definition-applies? definition project-scope)))
            (catalog-definitions confirmed)))
  (define-values (winner shadowed failure) (select-by-source candidates))
  (if winner
      (values
       (association (catalog-generation confirmed)
                    identity
                    'explicit
                    identity
                    (language-definition-source winner)
                    (language-definition-scope winner)
                    (language-definition-source-generation winner)
                    (map language-definition-identity shadowed))
       #f)
      (values #f (or failure
                     (rejection 'unknown-language 'identity #f identity 'native "" 0)))))

(define (resolve-path confirmed target-path project-scope)
  (define basename (path-basename target-path))
  (define matches
    (append-map
     (lambda (definition)
       (if (definition-applies? definition project-scope)
           (definition-matches definition basename target-path)
           '()))
     (catalog-definitions confirmed)))
  (define grouped
    (group-by (lambda (entry)
                (source-precedence (language-definition-source (car entry))))
              matches))
  (let loop ([groups (sort grouped > #:key (lambda (group)
                                             (source-precedence
                                              (language-definition-source
                                               (caar group)))))]
             [shadowed '()])
    (cond
      [(null? groups)
       (values #f (rejection 'no-match 'selector #f target-path 'factory "" 0))]
      [else
       (define best (best-selector-matches (car groups)))
       (define identities
         (remove-duplicates
          (map (lambda (entry) (language-definition-identity (car entry))) best)))
       (if (= (length identities) 1)
           (let* ([entry (car (sort best match<?))]
                  [definition (car entry)]
                  [kind (cadr entry)]
                  [selector (caddr entry)])
             (values
              (association (catalog-generation confirmed)
                           (language-definition-identity definition)
                           kind
                           selector
                           (language-definition-source definition)
                           (language-definition-scope definition)
                           (language-definition-source-generation definition)
                           (sort (append shadowed
                                         (append-map
                                          (lambda (group)
                                            (map (lambda (candidate)
                                                   (language-definition-identity (car candidate)))
                                                 group))
                                          (cdr groups)))
                                 string<?))
              #f))
           ;; Same-precedence ambiguity does not allow declaration order to win.
           (values #f
                   (rejection 'ambiguous-selector 'selector #f
                              (sort identities string<?)
                              (language-definition-source (caar best))
                              (language-definition-scope (caar best))
                              (language-definition-source-generation (caar best)))))])))

(define (validate-definitions definitions)
  (cond
    [(not (list? definitions))
     (rejection 'invalid-field 'definitions #f definitions 'factory "" 0)]
    [(> (length definitions) (hash-ref catalog-limits 'languages))
     (rejection 'limit 'languages (hash-ref catalog-limits 'languages)
                (length definitions) 'factory "" 0)]
    [else
     (or (for/or ([definition (in-list definitions)])
           (validate-definition definition))
         (validate-identity-conflicts definitions)
         (validate-selector-conflicts definitions)
         (let ([selector-count
                (for/sum ([definition (in-list definitions)])
                  (+ (length (language-definition-exact-filenames definition))
                     (length (language-definition-suffixes definition))))])
           (and (> selector-count (hash-ref catalog-limits 'selectors-total))
                (rejection 'limit 'selectors-total
                           (hash-ref catalog-limits 'selectors-total)
                           selector-count 'factory "" 0))))]))

(define (validate-definition definition)
  (if (not (language-definition? definition))
      (rejection 'invalid-field 'definition #f definition 'factory "" 0)
      (let* ([identity (language-definition-identity definition)]
             [display-name (language-definition-display-name definition)]
             [source (language-definition-source definition)]
             [scope (language-definition-scope definition)]
             [source-generation (language-definition-source-generation definition)]
             [exact-filenames (language-definition-exact-filenames definition)]
             [suffixes (language-definition-suffixes definition)]
             [provenance (language-definition-provenance definition)]
             [selectors (+ (if (list? exact-filenames) (length exact-filenames) 0)
                           (if (list? suffixes) (length suffixes) 0))])
        (or (invalid-string identity 'identity
                            (hash-ref catalog-limits 'identity-bytes) source scope source-generation)
            (and (not (valid-identity? identity))
                 (rejection 'invalid-field 'identity
                            (hash-ref catalog-limits 'identity-bytes)
                            (utf8-length identity) source scope source-generation))
            (invalid-string display-name 'display-name
                            (hash-ref catalog-limits 'display-name-bytes)
                            source scope source-generation)
            (and (not (memq source '(factory package personal project)))
                 (rejection 'invalid-field 'source #f source source scope source-generation))
            (and (or (not (string? scope))
                     (and (eq? source 'project) (string=? scope "")))
                 (rejection 'invalid-field 'scope #f scope source "" source-generation))
            (and (not (exact-positive-integer? source-generation))
                 (rejection 'invalid-generation 'source-generation #f source-generation
                            source scope 0))
            (and (not (list? exact-filenames))
                 (rejection 'invalid-field 'exact-filenames #f exact-filenames
                            source scope source-generation))
            (and (not (list? suffixes))
                 (rejection 'invalid-field 'suffixes #f suffixes
                            source scope source-generation))
            (and (> selectors (hash-ref catalog-limits 'selectors-per-language))
                 (rejection 'limit 'selectors-per-language
                            (hash-ref catalog-limits 'selectors-per-language)
                            selectors source scope source-generation))
            (and (list? exact-filenames)
                 (> (length exact-filenames)
                    (hash-ref catalog-limits 'exact-filenames-per-language))
                 (rejection 'limit 'exact-filenames-per-language
                            (hash-ref catalog-limits 'exact-filenames-per-language)
                            (length exact-filenames) source scope source-generation))
            (and (list? suffixes)
                 (> (length suffixes) (hash-ref catalog-limits 'suffixes-per-language))
                 (rejection 'limit 'suffixes-per-language
                            (hash-ref catalog-limits 'suffixes-per-language)
                            (length suffixes) source scope source-generation))
            (and (list? exact-filenames)
                 (for/or ([filename (in-list exact-filenames)])
                   (and (not (valid-exact-filename? filename))
                        (rejection 'invalid-selector 'exact-filename
                                   (hash-ref catalog-limits 'selector-bytes)
                                   filename source scope source-generation))))
            (and (list? suffixes)
                 (for/or ([suffix (in-list suffixes)])
                   (and (not (valid-suffix? suffix))
                        (rejection 'invalid-selector 'suffix
                                   (hash-ref catalog-limits 'selector-bytes)
                                   suffix source scope source-generation))))
            (and (list? exact-filenames) (check-duplicates exact-filenames)
                 (rejection 'duplicate-selector 'exact-filename #f
                            (check-duplicates exact-filenames)
                            source scope source-generation))
            (and (list? suffixes) (check-duplicates suffixes)
                 (rejection 'duplicate-selector 'suffix #f
                            (check-duplicates suffixes)
                            source scope source-generation))
            (invalid-string provenance 'provenance
                            (hash-ref catalog-limits 'provenance-bytes)
                            source scope source-generation)))))

(define (validate-identity-conflicts definitions)
  (for*/or ([left (in-list definitions)]
            [right (in-list definitions)]
            #:when (and (not (eq? left right))
                        (eq? (language-definition-source left)
                             (language-definition-source right))
                        (string=? (language-definition-scope left)
                                  (language-definition-scope right))
                        (string=? (language-definition-identity left)
                                  (language-definition-identity right))))
    (rejection 'duplicate-identity 'identity #f
               (language-definition-identity left)
               (language-definition-source left)
               (language-definition-scope left)
               (language-definition-source-generation left))))

(define (validate-selector-conflicts definitions)
  (for*/or ([left (in-list definitions)]
            [right (in-list definitions)]
            #:when (and (not (eq? left right))
                        (eq? (language-definition-source left)
                             (language-definition-source right))
                        (string=? (language-definition-scope left)
                                  (language-definition-scope right))
                        (not (string=? (language-definition-identity left)
                                       (language-definition-identity right)))))
    (define exact-conflict
      (findf (lambda (selector)
               (member selector (language-definition-exact-filenames right)))
             (language-definition-exact-filenames left)))
    (define suffix-conflict
      (findf (lambda (selector)
               (member selector (language-definition-suffixes right)))
             (language-definition-suffixes left)))
    (and (or exact-conflict suffix-conflict)
         (rejection 'ambiguous-selector
                    (if exact-conflict 'exact-filename 'suffix)
                    #f
                    (or exact-conflict suffix-conflict)
                    (language-definition-source left)
                    (language-definition-scope left)
                    (language-definition-source-generation left)))))

(define (definition-matches definition basename path)
  (append
   (for/list ([filename (in-list (language-definition-exact-filenames definition))]
              #:when (string=? filename basename))
     (list definition 'exact-filename filename))
   (for/list ([suffix (in-list (language-definition-suffixes definition))]
              #:when (string-suffix? path suffix))
     (list definition 'suffix suffix))))

(define (best-selector-matches matches)
  (define exacts (filter (lambda (entry) (eq? (cadr entry) 'exact-filename)) matches))
  (if (pair? exacts)
      exacts
      (let ([longest (apply max (map (lambda (entry) (string-length (caddr entry))) matches))])
        (filter (lambda (entry) (= (string-length (caddr entry)) longest)) matches))))

(define (select-by-source definitions)
  (cond
    [(null? definitions) (values #f '() #f)]
    [else
     (define highest (apply max (map (lambda (definition)
                                      (source-precedence (language-definition-source definition)))
                                    definitions)))
     (define winners
       (filter (lambda (definition)
                 (= highest (source-precedence (language-definition-source definition))))
               definitions))
     (if (= (length winners) 1)
         (values (car winners)
                 (filter (lambda (definition) (not (eq? definition (car winners)))) definitions)
                 #f)
         (values #f '()
                 (rejection 'ambiguous-identity 'identity #f
                            (language-definition-identity (car winners))
                            (language-definition-source (car winners))
                            (language-definition-scope (car winners))
                            (language-definition-source-generation (car winners)))))]))

(define (definition-applies? definition project-scope)
  (or (not (eq? (language-definition-source definition) 'project))
      (and (string? project-scope)
           (string=? project-scope (language-definition-scope definition)))))

(define (source-precedence source)
  (case source
    [(project) 4]
    [(personal) 3]
    [(package) 2]
    [(factory) 1]
    [else 0]))

(define (canonical-definitions definitions)
  (sort definitions definition<?))

(define (definition<? left right)
  (string<?
   (format "~a\0~a\0~a\0~a"
           (- (source-precedence (language-definition-source left)))
           (language-definition-scope left)
           (language-definition-identity left)
           (language-definition-source-generation left))
   (format "~a\0~a\0~a\0~a"
           (- (source-precedence (language-definition-source right)))
           (language-definition-scope right)
           (language-definition-identity right)
           (language-definition-source-generation right))))

(define (match<? left right)
  (definition<? (car left) (car right)))

(define (valid-identity? value)
  (and (string? value)
       (positive? (string-length value))
       (<= (utf8-length value) (hash-ref catalog-limits 'identity-bytes))
       (regexp-match? #px"^[a-z][a-z0-9-]*$" value)))

(define (valid-exact-filename? value)
  (and (bounded-string? value (hash-ref catalog-limits 'selector-bytes))
       (not (regexp-match? #px"[/\\\\]" value))))

(define (valid-suffix? value)
  (and (bounded-string? value (hash-ref catalog-limits 'selector-bytes))
       (string-prefix? value ".")
       (> (string-length value) 1)
       (not (regexp-match? #px"[/\\\\]" value))))

(define (invalid-string value field limit source scope source-generation)
  (and (not (bounded-string? value limit))
       (rejection 'limit field limit (utf8-length value) source scope source-generation)))

(define (bounded-string? value limit)
  (and (string? value) (positive? (string-length value)) (<= (utf8-length value) limit)))

(define (utf8-length value)
  (if (string? value) (bytes-length (string->bytes/utf-8 value)) 0))

(define (path-basename path)
  (if (string? path)
      (let ([parts (regexp-split #px"[/\\\\]" path)])
        (if (null? parts) "" (last parts)))
      ""))

;; The estimate includes fixed records, copied fields, selectors, and index entries.
(define (estimate-retained-bytes profile)
  (+ (* (hash-ref profile 'languages) 256)
     (* (hash-ref profile 'selectors) 64)
     (hash-ref profile 'identity-bytes)
     (hash-ref profile 'display-name-bytes)
     (hash-ref profile 'selector-bytes)
     (hash-ref profile 'provenance-bytes)))

;; Candidate construction retains one additional record and selector index copy.
(define (estimate-temporary-bytes profile)
  (* 2 (estimate-retained-bytes profile)))

(define (validate-resource-profile profile)
  (and (hash? profile)
       (for/and ([key (in-list '(languages selectors identity-bytes display-name-bytes
                                           selector-bytes provenance-bytes))])
         (exact-positive-integer? (hash-ref profile key #f)))
       (<= (hash-ref profile 'languages) (hash-ref catalog-limits 'languages))
       (<= (hash-ref profile 'selectors) (hash-ref catalog-limits 'selectors-total))
       (<= (estimate-retained-bytes profile) (hash-ref catalog-limits 'retained-bytes))
       (<= (estimate-temporary-bytes profile) (hash-ref catalog-limits 'temporary-bytes))))
