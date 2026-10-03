#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/string
         (prefix-in bundle: "../command/language-bundles.rkt")
         "factory-bundles.rkt")

(provide
 (contract-out
  [language-keymap-projection
   (->* ((listof bundle:odra-language-support-bundle?) symbol? symbol?)
        ((listof bundle:odra-language-keymap?))
        bytes?)]
  [factory-language-keymap-projection (-> symbol? symbol? bytes?)]))

(define projection-header "odra-language-keymap\t1")
(define maximum-projection-bindings 128)
(define control-modifier #x01)
(define meta-modifier #x02)
(define shift-modifier #x10)

(define special-key-kinds
  (hash "LEFT" 2 "RIGHT" 3 "UP" 4 "DOWN" 5
        "HOME" 6 "END" 7 "BACKSPACE" 8 "DELETE" 9
        "RET" 10 "ENTER" 10 "TAB" 11 "INSERT" 12
        "PRIOR" 13 "NEXT" 14 "ESC" 15 "F4" 16))

(define (token-modifier value prefix bit)
  (if (string-prefix? value prefix)
      (values (substring value (string-length prefix)) bit)
      (values value 0)))

(define (key-token->stroke token)
  (define-values (after-control control)
    (token-modifier token "C-" control-modifier))
  (define-values (after-meta meta)
    (token-modifier after-control "M-" meta-modifier))
  (define-values (name shift)
    (token-modifier after-meta "S-" shift-modifier))
  (define modifiers (bitwise-ior control meta shift))
  (define special (hash-ref special-key-kinds name #f))
  (cond
    [special (list special 0 modifiers)]
    [(= (string-length name) 1)
     (list 1 (char->integer (string-ref name 0)) modifiers)]
    [else
     (raise-arguments-error
      'language-keymap-projection "unsupported bundle key token" "token" token)]))

(define (binding-state-and-sequence state sequence)
  (define match (regexp-match-positions #rx":" sequence))
  (define separator (and match (caar match)))
  (cond
    [(not separator) (values state sequence)]
    [else
     (define declared-state (string->symbol (substring sequence 0 separator)))
     (values declared-state (substring sequence (add1 separator)))]))

(define (matching-keymaps bundles language state extra-keymaps)
  (filter
   (lambda (keymap)
     (and (memq language (bundle:odra-language-keymap-languages keymap))
          (memq state (bundle:odra-language-keymap-states keymap))))
   (append
    (append*
     (for/list ([candidate (in-list bundles)])
       (bundle:odra-language-support-bundle-keymaps candidate)))
    extra-keymaps)))

(define (merge-bindings keymaps state)
  (define merged (make-hash))
  (for* ([keymap (in-list keymaps)]
         [(sequence command) (in-hash (bundle:odra-language-keymap-bindings keymap))])
    (define-values (declared-state unqualified)
      (binding-state-and-sequence state sequence))
    (when (eq? declared-state state)
      (define prior (hash-ref merged unqualified #f))
      (when (and prior (not (eq? prior command)))
        (raise-arguments-error
         'language-keymap-projection
         "duplicate bundle key sequence has different semantics"
         "sequence" unqualified
         "first-command" prior
         "second-command" command))
      (hash-set! merged unqualified command)))
  (when (> (hash-count merged) maximum-projection-bindings)
    (raise-arguments-error
     'language-keymap-projection "bundle keymap exceeds projection limit"
     "limit" maximum-projection-bindings
     "actual" (hash-count merged)))
  merged)

(define (stroke-text stroke)
  (string-join (map number->string stroke) ","))

(define (binding-line sequence command)
  (define strokes
    (map key-token->stroke (string-split sequence)))
  (when (> (length strokes) 16)
    (raise-arguments-error
     'language-keymap-projection "bundle key sequence exceeds projection limit"
     "sequence" sequence))
  (format "~a\t~a"
          (string-join (map stroke-text strokes) ";")
          (symbol->string command)))

(define (language-keymap-projection bundles language state [extra-keymaps '()])
  (define keymaps (matching-keymaps bundles language state extra-keymaps))
  (cond
    [(null? keymaps) #""]
    [else
     (define bindings (merge-bindings keymaps state))
     (define identity
       (string-join
        (map (lambda (value)
               (symbol->string (bundle:odra-language-keymap-id value)))
             keymaps)
        "+"))
     (define priority
       (apply max (map bundle:odra-language-keymap-priority keymaps)))
     (define lines
       (for/list ([entry (in-list (sort (hash->list bindings) string<? #:key car))])
         (binding-line (car entry) (cdr entry))))
     (string->bytes/utf-8
      (string-join
       (append (list (format "~a\t~a\t~a\t~a"
                             projection-header identity priority (length lines)))
               lines)
       "\n"))]))

(define (factory-language-keymap-projection language state)
  (language-keymap-projection (factory-language-bundles) language state))

(module+ test
  (require rackunit)

  (define direct (bytes->string/utf-8 (factory-language-keymap-projection 'jan 'direct)))
  (check-true (string-prefix? direct "odra-language-keymap\t1\tjan.direct\t0\t65\n"))
  (check-true (string-contains? direct "11,0,0\tjan-cycle"))
  (check-true (string-contains? direct "11,0,16\tjan-global-cycle"))
  (check-true (string-contains? direct "10,0,2\tjan-insert-heading-after"))
  (check-true (string-contains? direct "1,99,1;1,106,0;1,99,0\tjan-cycle"))
  (check-true (string-contains? direct "1,99,1;1,118,1;1,116,0\tjan-tangle"))
  (check-equal? (factory-language-keymap-projection 'jan 'insert) #"")

  (define target '((linux x86-64)))
  (define conflicting
    (bundle:language-support-bundle
     #:id 'org.example.conflict #:display-name "Conflict"
     #:version "1.0.0" #:api-min "1.0.0" #:api-max "1.0.0"
     #:description "Conflict fixture." #:publisher 'example #:source 'test
     #:targets target
     #:keymaps
     (list
      (bundle:language-keymap #:id 'first #:languages '(jan) #:states '(direct)
                              #:bindings (hash "TAB" 'jan-cycle))
      (bundle:language-keymap #:id 'second #:languages '(jan) #:states '(direct)
                              #:bindings (hash "TAB" 'jan-global-cycle)))))
  (check-exn exn:fail?
             (lambda () (language-keymap-projection (list conflicting) 'jan 'direct)))

  (define equivalent
    (bundle:language-support-bundle
     #:id 'org.example.equivalent #:display-name "Equivalent"
     #:version "1.0.0" #:api-min "1.0.0" #:api-max "1.0.0"
     #:description "Equivalent fixture." #:publisher 'example #:source 'test
     #:targets target
     #:keymaps
     (list
      (bundle:language-keymap #:id 'first #:languages '(jan) #:states '(direct)
                              #:bindings (hash "TAB" 'jan-cycle))
      (bundle:language-keymap #:id 'second #:languages '(jan) #:states '(direct)
                              #:bindings (hash "TAB" 'jan-cycle)))))
  (check-equal?
   (bytes->string/utf-8 (language-keymap-projection (list equivalent) 'jan 'direct))
   "odra-language-keymap\t1\tfirst+second\t0\t1\n11,0,0\tjan-cycle"))
