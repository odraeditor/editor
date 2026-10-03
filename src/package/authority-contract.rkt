#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list)

(provide
 (contract-out
  [package-authority-symbols (listof symbol?)]
  [package-authority? (-> any/c boolean?)]
  [package-authority<? (-> symbol? symbol? boolean?)]
  [package-authority-set?
   (->* (any/c)
        (#:maximum exact-nonnegative-integer? #:ordered? boolean?)
        boolean?)]
  [package-authority->string (-> package-authority? string?)]
  [string->package-authority (-> string? (or/c #f package-authority?))]))

;; package-authority-symbols is the complete public package authority vocabulary.
(define package-authority-symbols
  '(racket-extension external-process project-read project-write
                     network-acquisition native-grammar))

;; package-authority? recognizes one canonical package authority identity.
(define (package-authority? value)
  (and (symbol? value)
       (if (memq value package-authority-symbols) #t #f)))

;; package-authority<? defines the stable persisted ordering for authorities.
(define (package-authority<? left right)
  (string<? (symbol->string left) (symbol->string right)))

;; package-authority-set? validates a unique bounded authority collection.
(define (package-authority-set? values
                                #:maximum [maximum (length package-authority-symbols)]
                                #:ordered? [ordered? #t])
  (and (list? values)
       (<= (length values) maximum)
       (andmap package-authority? values)
       (= (length values) (length (remove-duplicates values)))
       (or (not ordered?)
           (equal? values (sort values package-authority<?)))))

;; package-authority->string returns the public text form of an authority.
(define (package-authority->string authority)
  (string->immutable-string (symbol->string authority)))

;; string->package-authority decodes only known public authority text.
(define (string->package-authority value)
  (for/first ([authority (in-list package-authority-symbols)]
              #:when (string=? value (symbol->string authority)))
    authority))

(module+ test
  (require rackunit)

  (check-true
   (package-authority-set?
    (sort package-authority-symbols package-authority<?)))
  (check-equal?
   (map string->package-authority
        (map package-authority->string package-authority-symbols))
   package-authority-symbols)
  (check-false (package-authority? 'unknown-authority))
  (check-false (string->package-authority "unknown-authority"))
  (check-false (package-authority-set? '(racket-extension unknown-authority)
                                       #:ordered? #f)))
