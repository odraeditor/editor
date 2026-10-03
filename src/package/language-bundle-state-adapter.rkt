#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         (prefix-in bundle: "../language_bundle/state-records.rkt")
         "state-records.rkt")

(provide
 (struct-out odra-package-state-adapter-rejection)
 (contract-out
  [language-bundle-state->package-state
   (-> bundle:odra-language-bundle-state?
       (values (or/c #f odra-package-state?)
               (or/c #f odra-package-state-adapter-rejection?)))]))

(struct odra-package-state-adapter-rejection (code package-id detail)
  #:transparent
  #:guard
  (lambda (code package-id detail _)
    (unless (and (memq code '(ambiguous-dependency missing-dependency invalid-state))
                 (string? package-id)
                 (string? detail))
      (raise-arguments-error 'odra-package-state-adapter-rejection
                             "invalid language-bundle adapter rejection"))
    (values code (string->immutable-string package-id)
            (string->immutable-string detail))))

(define (bundle-key value)
  (format "~a@~a" (bundle:odra-installed-bundle-id value)
          (bundle:odra-installed-bundle-version value)))

(define (candidate-dependency-versions state id)
  (sort
   (remove-duplicates
    (for/list ([bundle (in-list (bundle:odra-language-bundle-state-bundles state))]
               #:when (and (string=? id (bundle:odra-installed-bundle-id bundle))
                           (not (eq? 'removed
                                     (bundle:odra-installed-bundle-lifecycle bundle)))))
      (bundle:odra-installed-bundle-version bundle))
    string=?)
   string<?))

(define (resolve-dependencies state bundle)
  (let/ec return
    (define releases
      (for/list ([id (in-list (bundle:odra-installed-bundle-dependencies bundle))])
        (define versions (candidate-dependency-versions state id))
        (cond
          [(null? versions)
           (return
            #f
            (odra-package-state-adapter-rejection
             'missing-dependency (bundle:odra-installed-bundle-id bundle) id))]
          [(pair? (cdr versions))
           (return
            #f
            (odra-package-state-adapter-rejection
             'ambiguous-dependency (bundle:odra-installed-bundle-id bundle) id))]
          [else (odra-package-release id (car versions))])))
    (values (sort releases
                  string<?
                  #:key (lambda (release)
                          (format "~a@~a" (odra-package-release-id release)
                                  (odra-package-release-version release))))
            #f)))

(define (adapt-installed state bundle)
  (define-values (dependencies rejection) (resolve-dependencies state bundle))
  (if rejection
      (values #f rejection)
      (values
       (odra-installed-package
        (bundle:odra-installed-bundle-id bundle)
        'language-support
        (bundle:odra-installed-bundle-version bundle)
        (bundle:odra-language-bundle-state-generation state)
        (bundle:odra-installed-bundle-manifest bundle)
        #f
        (bundle:odra-installed-bundle-artifacts bundle)
        dependencies
        (odra-package-provenance
         'migrated-language-bundle
         (bundle:odra-installed-bundle-source bundle)
         #f #f
         (bundle:odra-installed-bundle-publisher bundle)
         #f)
        (bundle:odra-installed-bundle-platform bundle)
        (bundle:odra-installed-bundle-architecture bundle)
        (map string->symbol (bundle:odra-installed-bundle-authorities bundle))
        (map string->symbol (bundle:odra-installed-bundle-authorities bundle))
        (bundle:odra-installed-bundle-authority-provenance bundle)
        (bundle:odra-installed-bundle-lifecycle bundle)
        (bundle:odra-installed-bundle-contribution-generation bundle)
        (bundle:odra-installed-bundle-predecessor bundle)
        (bundle:odra-installed-bundle-pinned? bundle)
        #f #f "")
       #f)))

(define (adapt-packages state)
  (let/ec return
    (define packages
      (for/list ([bundle
                  (in-list
                   (sort (bundle:odra-language-bundle-state-bundles state)
                         string<? #:key bundle-key))])
        (define-values (package rejection) (adapt-installed state bundle))
        (when rejection (return #f rejection))
        package))
    (values packages #f)))

(define (adapt-lock value)
  (and value
       (let ([packages (bundle:odra-activation-lock-bundles value)])
         (package-activation-lock-with-checksum
          (odra-package-activation-lock
           (bundle:odra-activation-lock-generation value)
           (bundle:odra-activation-lock-state-generation value)
           packages
           (bundle:odra-activation-lock-content value)
           (bundle:odra-activation-lock-dependency-digest value)
           (bundle:odra-activation-lock-authority-digest value)
           (for/hash ([(id _) (in-hash packages)]) (values id 0))
           (bundle:odra-activation-lock-contribution-generations value)
           0
           (make-string 64 #\0))))))

(define (adapt-operation value)
  (odra-package-operation
   (bundle:odra-bundle-operation-id value)
   (bundle:odra-bundle-operation-kind value)
   (bundle:odra-bundle-operation-phase value)
   (bundle:odra-bundle-operation-base-state-generation value)
   (bundle:odra-bundle-operation-base-lock-generation value)
   '()
   (bundle:odra-bundle-operation-content value)
   (bundle:odra-bundle-operation-temporary-paths value)
   (bundle:odra-bundle-operation-result value)
   (bundle:odra-bundle-operation-cleanup-complete? value)
   (bundle:odra-bundle-operation-failure value)))

(define (language-bundle-state->package-state state)
  (define-values (packages rejection) (adapt-packages state))
  (if rejection
      (values #f rejection)
      (with-handlers
          ([exn:fail?
            (lambda (failure)
              (values
               #f
               (odra-package-state-adapter-rejection
                'invalid-state "" (exn-message failure))))])
        (define accounting (bundle:odra-language-bundle-state-accounting state))
        (values
         (package-state-with-checksum
          (odra-package-state
           current-package-state-format-version
           (bundle:odra-language-bundle-state-root-id state)
           (bundle:odra-language-bundle-state-generation state)
           (bundle:odra-language-bundle-state-confirmed-lock-generation state)
           packages
           (adapt-lock (bundle:odra-language-bundle-state-lock state))
           (adapt-lock (bundle:odra-language-bundle-state-previous-lock state))
           (map adapt-operation
                (bundle:odra-language-bundle-state-operations state))
           (bundle:odra-language-bundle-state-quarantine state)
           (odra-package-accounting
            (bundle:odra-bundle-accounting-bundle-count accounting)
            (bundle:odra-bundle-accounting-artifact-count accounting)
            (bundle:odra-bundle-accounting-manifest-bytes accounting)
            (bundle:odra-bundle-accounting-artifact-bytes accounting)
            (bundle:odra-bundle-accounting-quarantine-count accounting))
           'language-bundle-v2
           (make-string 64 #\0)))
         #f))))
