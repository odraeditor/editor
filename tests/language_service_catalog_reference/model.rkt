#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         racket/match)

(provide (struct-out service-definition)
         (struct-out explicit-selection)
         (struct-out service-catalog)
         (struct-out service-resolution)
         (struct-out service-rejection)
         confirm-service-catalog
         resolve-service)

;; Definitions are immutable complete records; the model never merges fields.
(struct service-definition
  (handle identity languages source scope enabled? default?)
  #:transparent)

;; Explicit selections name an identity without duplicating its definition.
(struct explicit-selection (language identity source scope) #:transparent)

;; A confirmed catalog retains canonical records and symmetric package conflicts.
(struct service-catalog
  (generation definitions selections package-conflicts latest-rejection)
  #:transparent)

;; A resolution records the deterministic policy branch and retained alternatives.
(struct service-resolution
  (state kind handle identity source shadowed conflicted)
  #:transparent)

;; Rejections preserve the prior confirmed generation.
(struct service-rejection (code source scope identity) #:transparent)

(define empty-catalog (service-catalog 0 '() '() '() #f))

(define (source-precedence source)
  (case source
    [(project) 4]
    [(personal) 3]
    [(package) 2]
    [(factory) 1]
    [else 0]))

(define (definition<? left right)
  (or (> (source-precedence (service-definition-source left))
         (source-precedence (service-definition-source right)))
      (and (= (source-precedence (service-definition-source left))
              (source-precedence (service-definition-source right)))
           (or (string<? (service-definition-identity left)
                         (service-definition-identity right))
               (and (string=? (service-definition-identity left)
                              (service-definition-identity right))
                    (string<? (service-definition-scope left)
                              (service-definition-scope right)))))))

(define (selection<? left right)
  (or (> (source-precedence (explicit-selection-source left))
         (source-precedence (explicit-selection-source right)))
      (and (= (source-precedence (explicit-selection-source left))
              (source-precedence (explicit-selection-source right)))
           (or (symbol<? (explicit-selection-language left)
                         (explicit-selection-language right))
               (and (eq? (explicit-selection-language left)
                         (explicit-selection-language right))
                    (string<? (explicit-selection-scope left)
                              (explicit-selection-scope right)))))))

(define (duplicate-authority definitions)
  (for*/first ([left (in-list definitions)]
               [right (in-list definitions)]
               #:when (and (not (eq? left right))
                           (eq? (service-definition-source left)
                                (service-definition-source right))
                           (string=? (service-definition-scope left)
                                     (service-definition-scope right))
                           (string=? (service-definition-identity left)
                                     (service-definition-identity right))))
    left))

(define (package-conflict-identities definitions)
  (sort
   (remove-duplicates
    (for*/list ([left (in-list definitions)]
                [right (in-list definitions)]
                #:when (and (not (eq? left right))
                            (eq? 'package (service-definition-source left))
                            (eq? 'package (service-definition-source right))
                            (string=? (service-definition-identity left)
                                      (service-definition-identity right))
                            (not (string=? (service-definition-scope left)
                                          (service-definition-scope right)))))
      (service-definition-identity left)))
   string<?))

(define (applies? definition project-scope factory-only?)
  (and (or (not factory-only?)
           (eq? 'factory (service-definition-source definition)))
       (or (not (eq? 'project (service-definition-source definition)))
           (and project-scope
                (string=? project-scope (service-definition-scope definition))))))

(define (effective-definitions definitions conflicts language project-scope factory-only?)
  (define applicable
    (filter
     (lambda (definition)
       (and (member language (service-definition-languages definition))
            (applies? definition project-scope factory-only?)
            (not (and (eq? 'package (service-definition-source definition))
                      (member (service-definition-identity definition) conflicts)))))
     definitions))
  (for/list ([identity (in-list (sort (remove-duplicates
                                       (map service-definition-identity applicable))
                                      string<?))])
    (argmax source-precedence
            (filter (lambda (definition)
                      (string=? identity (service-definition-identity definition)))
                    applicable)
            #:key service-definition-source)))

(define (argmax score values #:key [key values])
  (for/fold ([best (car values)]) ([value (in-list (cdr values))])
    (if (> (score (key value)) (score (key best))) value best)))

(define (selected-explicit selections language project-scope)
  (or (for/first ([selection (in-list selections)]
                  #:when (and (eq? language (explicit-selection-language selection))
                              (eq? 'project (explicit-selection-source selection))
                              project-scope
                              (string=? project-scope (explicit-selection-scope selection))))
        selection)
      (for/first ([selection (in-list selections)]
                  #:when (and (eq? language (explicit-selection-language selection))
                              (eq? 'personal (explicit-selection-source selection))))
        selection)))

(define (resolve-record definitions selections conflicts language project-scope factory-only?)
  (define effective
    (effective-definitions definitions conflicts language project-scope factory-only?))
  (define enabled (filter service-definition-enabled? effective))
  (define explicit
    (and (not factory-only?) (selected-explicit selections language project-scope)))
  (cond
    [explicit
     (define selected
       (findf (lambda (definition)
                (string=? (explicit-selection-identity explicit)
                          (service-definition-identity definition)))
              enabled))
     (and selected (list (if (eq? 'project (explicit-selection-source explicit))
                             'explicit-project
                             'explicit-personal)
                         selected effective))]
    [else
     (define defaults (filter service-definition-default? enabled))
     (define highest
       (and (pair? defaults)
            (apply max (map (lambda (definition)
                              (source-precedence (service-definition-source definition)))
                            defaults))))
     (define winning-defaults
       (if highest
           (filter (lambda (definition)
                     (= highest (source-precedence (service-definition-source definition))))
                   defaults)
           '()))
     (cond
       [(= (length winning-defaults) 1)
        (list (if factory-only? 'factory-restoration 'unique-default)
              (car winning-defaults)
              effective)]
       [(= (length enabled) 1)
        (list (if factory-only? 'factory-restoration 'sole-candidate)
              (car enabled)
              effective)]
       [else #f])]))

(define (catalog-validation definitions selections conflicts)
  (or
   (let ([duplicate (duplicate-authority definitions)])
     (and duplicate
          (service-rejection 'duplicate-identity
                             (service-definition-source duplicate)
                             (service-definition-scope duplicate)
                             (service-definition-identity duplicate))))
   (for*/first ([language (in-list (remove-duplicates
                                    (append-map service-definition-languages definitions)))]
                [scope (in-list (cons #f
                                      (remove-duplicates
                                       (for/list ([definition (in-list definitions)]
                                                  #:when (eq? 'project
                                                             (service-definition-source definition)))
                                         (service-definition-scope definition)))))]
                #:do [(define effective
                        (effective-definitions definitions conflicts language scope #f))
                      (define defaults (filter (lambda (definition)
                                                 (and (service-definition-enabled? definition)
                                                      (service-definition-default? definition)))
                                               effective))]
                #:when (and (pair? defaults)
                            (let* ([highest (apply max (map (lambda (definition)
                                                             (source-precedence
                                                              (service-definition-source definition)))
                                                           defaults))]
                                   [winners (filter (lambda (definition)
                                                      (= highest
                                                         (source-precedence
                                                          (service-definition-source definition))))
                                                    defaults)])
                              (> (length winners) 1))))
     (service-rejection 'ambiguous-default 'factory (or scope "") language))
   (for/first ([selection (in-list selections)]
               #:unless (resolve-record definitions selections conflicts
                                        (explicit-selection-language selection)
                                        (and (eq? 'project (explicit-selection-source selection))
                                             (explicit-selection-scope selection))
                                        #f))
     (service-rejection 'invalid-explicit
                        (explicit-selection-source selection)
                        (explicit-selection-scope selection)
                        (explicit-selection-identity selection)))))

;; Confirmation validates a full snapshot before replacing the previous generation.
(define (confirm-service-catalog previous generation definitions selections)
  (define current (or previous empty-catalog))
  (define conflicts (package-conflict-identities definitions))
  (define rejection
    (cond
      [(or (not (exact-positive-integer? generation))
           (<= generation (service-catalog-generation current)))
       (service-rejection 'stale-generation 'factory "" "")]
      [else (catalog-validation definitions selections conflicts)]))
  (if rejection
      (values (struct-copy service-catalog current [latest-rejection rejection])
              #f
              rejection)
      (values (service-catalog generation
                               (sort definitions definition<?)
                               (sort selections selection<?)
                               conflicts
                               #f)
              #t
              #f)))

;; Resolution applies Project/personal explicit choice, defaults, then sole fallback.
(define (resolve-service catalog language project-scope #:factory? [factory-only? #f])
  (define record
    (resolve-record (service-catalog-definitions catalog)
                    (service-catalog-selections catalog)
                    (service-catalog-package-conflicts catalog)
                    language
                    project-scope
                    factory-only?))
  (if record
      (match-let ([(list kind selected effective) record])
        (define shadowed
          (- (length (filter (lambda (definition)
                               (and (member language (service-definition-languages definition))
                                    (applies? definition project-scope factory-only?)))
                             (service-catalog-definitions catalog)))
             (length effective)
             (length (service-catalog-package-conflicts catalog))))
        (values (service-resolution 'selected
                                    kind
                                    (service-definition-handle selected)
                                    (service-definition-identity selected)
                                    (service-definition-source selected)
                                    (max 0 shadowed)
                                    (length (service-catalog-package-conflicts catalog)))
                #f))
      (values #f (service-rejection 'no-selection 'factory "" language))))
