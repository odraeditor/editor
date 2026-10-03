#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list)

(provide
 maximum-indentation-rules
 maximum-indentation-matcher-bytes
 factory-indentation-policy
 factory-indentation-configuration
 indentation-configuration-encode
 (struct-out odra-indentation-policy)
 (struct-out odra-indentation-rule)
 (struct-out odra-indentation-configuration)
 (contract-out
  [indentation-policy
   (->* ()
        (#:representation symbol?
         #:indent-width exact-positive-integer?
         #:display-tab-width exact-positive-integer?)
        odra-indentation-policy?)]
  [indentation-rule
   (->* (#:scope symbol? #:policy odra-indentation-policy?)
        (#:profile-id exact-positive-integer?
         #:matcher-kind symbol?
         #:matcher (or/c #f string?)
         #:buffer-id exact-nonnegative-integer?
         #:source-generation exact-positive-integer?)
        odra-indentation-rule?)]
  [indentation-configuration
   (->* ()
        (#:factory odra-indentation-policy? #:rules list?)
        odra-indentation-configuration?)]))

(define maximum-indentation-rules 128)
(define maximum-indentation-matcher-bytes 128)
(define maximum-width 64)
(define maximum-u64 (sub1 (expt 2 64)))
(define representations '(tabs spaces))
(define scopes '(user-global project file-type language buffer-local))
(define matcher-kinds '(none project exact-filename filename-suffix language buffer))

(define (positive-u64? value)
  (and (exact-positive-integer? value) (<= value maximum-u64)))

(define (bounded-matcher? value)
  (and (string? value)
       (positive? (string-length value))
       (not (for/or ([character (in-string value)]) (char=? character #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value))
           maximum-indentation-matcher-bytes)))

(struct odra-indentation-policy (representation indent-width display-tab-width)
  #:transparent
  #:guard
  (lambda (representation indent-width display-tab-width _)
    (unless (and (memq representation representations)
                 (exact-positive-integer? indent-width)
                 (<= indent-width maximum-width)
                 (exact-positive-integer? display-tab-width)
                 (<= display-tab-width maximum-width))
      (raise-arguments-error
       'odra-indentation-policy
       "invalid representation or width"))
    (values representation indent-width display-tab-width)))

(struct odra-indentation-rule
  (profile-id scope matcher-kind matcher buffer-id policy source-generation)
  #:transparent
  #:guard
  (lambda (profile-id scope matcher-kind matcher buffer-id policy source-generation _)
    (unless (and (positive-u64? profile-id)
                 (memq scope scopes)
                 (memq matcher-kind matcher-kinds)
                 (exact-nonnegative-integer? buffer-id)
                 (<= buffer-id maximum-u64)
                 (odra-indentation-policy? policy)
                 (positive-u64? source-generation)
                 (rule-shape? scope matcher-kind matcher buffer-id))
      (raise-arguments-error 'odra-indentation-rule "invalid scoped indentation rule"))
    (values profile-id scope matcher-kind
            (if (string? matcher) (string->immutable-string matcher) matcher)
            buffer-id policy source-generation)))

(struct odra-indentation-configuration (factory rules)
  #:transparent
  #:guard
  (lambda (factory rules _)
    (unless (and (odra-indentation-policy? factory)
                 (list? rules)
                 (<= (length rules) maximum-indentation-rules)
                 (andmap odra-indentation-rule? rules)
                 (= (length rules) (length (remove-duplicates rules equal?))))
      (raise-arguments-error
       'odra-indentation-configuration
       "invalid immutable indentation configuration"))
    (values factory rules)))

(define factory-indentation-policy
  (odra-indentation-policy 'spaces 4 4))

(define factory-indentation-configuration
  (odra-indentation-configuration factory-indentation-policy '()))

;; indentation-policy constructs independent insertion and display values.
(define (indentation-policy #:representation [representation 'spaces]
                            #:indent-width [indent-width 4]
                            #:display-tab-width [display-tab-width 4])
  (odra-indentation-policy representation indent-width display-tab-width))

;; indentation-rule constructs one scoped policy contribution.
(define (indentation-rule #:scope scope
                          #:policy policy
                          #:profile-id [profile-id 1]
                          #:matcher-kind [matcher-kind 'none]
                          #:matcher [matcher #f]
                          #:buffer-id [buffer-id 0]
                          #:source-generation [source-generation 1])
  (odra-indentation-rule profile-id scope matcher-kind matcher buffer-id policy
                         source-generation))

;; indentation-configuration constructs one complete atomic generation.
(define (indentation-configuration
         #:factory [factory factory-indentation-policy]
         #:rules [rules '()])
  (odra-indentation-configuration factory rules))

(define (rule-shape? scope matcher-kind matcher buffer-id)
  (case scope
    [(user-global)
     (and (eq? matcher-kind 'none) (not matcher) (zero? buffer-id))]
    [(project)
     (and (eq? matcher-kind 'project) (bounded-matcher? matcher) (zero? buffer-id))]
    [(file-type)
     (and (memq matcher-kind '(exact-filename filename-suffix))
          (bounded-matcher? matcher)
          (zero? buffer-id))]
    [(language)
     (and (eq? matcher-kind 'language) (bounded-matcher? matcher) (zero? buffer-id))]
    [(buffer-local)
     (and (eq? matcher-kind 'buffer) (not matcher) (positive-u64? buffer-id))]
    [else #f]))

(define representation-codes '((tabs . 1) (spaces . 2)))
(define scope-codes
  '((user-global . 2) (project . 3) (file-type . 4)
    (language . 5) (buffer-local . 6)))
(define matcher-codes
  '((none . 1) (project . 2) (exact-filename . 3)
    (filename-suffix . 4) (language . 5) (buffer . 6)))

(define (word value)
  (integer->integer-bytes value 8 #f #f))

(define (code table value)
  (define found (assq value table))
  (unless found
    (raise-argument-error 'indentation-configuration-encode "known indentation symbol" value))
  (cdr found))

(define (policy-words policy)
  (bytes-append
   (word (code representation-codes
               (odra-indentation-policy-representation policy)))
   (word (odra-indentation-policy-indent-width policy))
   (word (odra-indentation-policy-display-tab-width policy))))

;; indentation-configuration-encode copies one complete configuration generation.
(define (indentation-configuration-encode configuration)
  (unless (odra-indentation-configuration? configuration)
    (raise-argument-error
     'indentation-configuration-encode
     "odra-indentation-configuration?"
     configuration))
  (define rules (odra-indentation-configuration-rules configuration))
  (define records
    (for/list ([rule (in-list rules)])
      (define matcher-bytes
        (if (string? (odra-indentation-rule-matcher rule))
            (string->bytes/utf-8 (odra-indentation-rule-matcher rule))
            #""))
      (bytes-append
       (word (odra-indentation-rule-profile-id rule))
       (word (code scope-codes (odra-indentation-rule-scope rule)))
       (word (code matcher-codes (odra-indentation-rule-matcher-kind rule)))
       (word (odra-indentation-rule-buffer-id rule))
       (policy-words (odra-indentation-rule-policy rule))
       (word (odra-indentation-rule-source-generation rule))
       (word (bytes-length matcher-bytes))
       matcher-bytes)))
  (bytes-append
   (word 1)
   (policy-words (odra-indentation-configuration-factory configuration))
   (word (length rules))
   (apply bytes-append records)))

(module+ test
  (require rackunit)

  (define configuration
    (indentation-configuration
     #:factory (indentation-policy #:indent-width 2 #:display-tab-width 8)
     #:rules
     (list
      (indentation-rule
       #:scope 'language
       #:matcher-kind 'language
       #:matcher "odin"
       #:policy (indentation-policy
                 #:representation 'tabs
                 #:indent-width 4
                 #:display-tab-width 8)
       #:source-generation 7))))
  (define encoded (indentation-configuration-encode configuration))
  (check-equal? (integer-bytes->integer encoded #f #f 0 8) 1)
  (check-equal? (integer-bytes->integer encoded #f #f 32 40) 1)
  (check-equal? (subbytes encoded (- (bytes-length encoded) 4)) #"odin")
  (check-exn
   exn:fail:contract?
   (lambda ()
     (odra-indentation-rule
      1 'language 'language "" 0 factory-indentation-policy 1))))
