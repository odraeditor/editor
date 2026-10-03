#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/command/api.rkt"
         (only-in "../../src/command/ksawery-command.rkt"
                  decode-ksawery-command-context
                  encode-ksawery-command-family
                  ksawery-command-family-definitions)
         (only-in "../../src/command/catalog.rkt"
                  odra-command-definition-name
                  odra-command-definition-dispatch-class
                  odra-command-definition-provenance
                  odra-command-source-provider
                  odra-command-source-source
                  odra-command-source-location))

(define (words . values)
  (apply bytes-append (map (lambda (value) (integer->integer-bytes value 8 #f #f)) values)))
(define repository #"/tmp/repository")
(define target #"refs/heads/main")
(define context-bytes
  (bytes-append
   (words 1 (+ 184 (bytes-length repository) (bytes-length target))
          3 5 11 13 2 19 2 23 29 1 5 19 1 1 31 0 1
          184 (bytes-length repository) (+ 184 (bytes-length repository)) (bytes-length target))
   repository target))
(define command-context (decode-ksawery-command-context context-bytes))

(define contribution
  (make-ksawery-contribution
   7 'commands.repository-policy 'command-family
   #:observations '(refs)
   #:authorities '(inspect request-core-action)))
(define contributor
  (make-ksawery-contributor
   'personal.repository-tools "Repository tools" "modules/repository-tools.rkt"
   5 (list contribution)))
(define choice (make-ksawery-command-choice 1 'choice.fast-forward "Fast-forward"))
(define arguments
  (list (make-ksawery-command-argument 1 'argument.force "Force" 'boolean #:required? #t)
        (make-ksawery-command-argument 2 'argument.mode "Mode" 'closed-choice
                                       #:required? #t #:choices (list choice))
        (make-ksawery-command-argument 3 'argument.ref "Ref" 'ref #:required? #t)))
(define action
  (make-ksawery-command-action
   1 'action.apply "Apply" 'request-core-action '(refs)
   #:targets '(ref) #:operation 'idle
   #:core-operation 'push
   #:mutates-repository? #t #:confirmation-required? #t))
(define family
  (make-ksawery-command-family contributor 7 11 'family.update-ref "Update ref" 17
                               '(refs) arguments (list action)))

(check-equal? (ksawery-command-context-repository command-context) "/tmp/repository")
(check-equal? (ksawery-command-context-observation command-context) 'refs)
(check-equal? (ksawery-command-context-observation-generation command-context) 19)
(check-equal? (ksawery-command-context-surface-generation command-context) 23)
(check-true (ksawery-command-context-mutation-available? command-context))
(check-true (ksawery-command-context-privacy-filtered? command-context))
(define encoded-family (encode-ksawery-command-family family))
(check-true (> (bytes-length encoded-family) 144))
(check-equal? (integer-bytes->integer encoded-family #f #f 8 16)
              (bytes-length encoded-family))
(define family-definitions
  (ksawery-command-family-definitions contributor (list family)))
(check-equal? (length family-definitions) 1)
(define family-definition (car family-definitions))
(check-equal?
 (list (odra-command-definition-name family-definition)
       (odra-command-definition-dispatch-class family-definition))
 '("personal.repository-tools/family.update-ref/action.apply"
   ksawery-extension))
(define family-provenance
  (odra-command-definition-provenance family-definition))
(check-equal?
 (list (odra-command-source-provider family-provenance)
       (odra-command-source-source family-provenance)
       (odra-command-source-location family-provenance))
 '("personal.repository-tools" "modules/repository-tools.rkt"
   "family.update-ref"))

(define values
  (list (make-ksawery-command-boolean 1 #t)
        (make-ksawery-command-choice-value 2 1)
        (make-ksawery-command-target 3 'ref
                                     (make-ksawery-annotation-target 'ref 19 target))))
(check-true
 (ksawery-command-outcome?
  (ksawery-command-request-action command-context family 1 values #:confirmation 41)))
(check-true (ksawery-command-outcome? (ksawery-command-reject command-context "not applicable")))
(check-true (ksawery-command-outcome? (ksawery-command-cancel command-context)))

(check-exn #rx"confirmation does not match"
           (lambda () (ksawery-command-request-action command-context family 1 values)))
(check-exn #rx"choice is not admitted"
           (lambda ()
             (ksawery-command-request-action
              command-context family 1
              (list (car values) (make-ksawery-command-choice-value 2 99) (caddr values))
              #:confirmation 41)))
(check-exn #rx"target argument is stale"
           (lambda ()
             (ksawery-command-request-action
              command-context family 1
              (list (car values) (cadr values)
                    (make-ksawery-command-target
                     3 'ref (make-ksawery-annotation-target 'ref 20 target)))
              #:confirmation 41)))
(check-exn #rx"command context is invalid"
           (lambda () (decode-ksawery-command-context (subbytes context-bytes 0 184))))
