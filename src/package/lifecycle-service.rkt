#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/file
         racket/list
         racket/path
         racket/string
         "../command/catalog.rkt"
         (prefix-in bundle: "../command/language-bundles.rkt")
         "acquisition.rkt"
         "lifecycle.rkt"
         "resolution.rkt"
         "runtime.rkt"
         "state-records.rkt")

(provide
 (struct-out odra-package-lifecycle-runtime-result)
 (contract-out
  [package-lifecycle-runtime-list
   (-> path-string? odra-package-lifecycle-runtime-result?)]
  [package-lifecycle-runtime-describe
   (-> path-string? string? odra-package-lifecycle-runtime-result?)]
  [package-lifecycle-runtime-install
   (->* (path-string? string?)
        (#:installer procedure?)
        odra-package-lifecycle-runtime-result?)]
  [package-lifecycle-runtime-enable
   (-> path-string? string? odra-package-lifecycle-runtime-result?)]
  [package-lifecycle-runtime-disable
   (-> path-string? string? odra-package-lifecycle-runtime-result?)]
  [package-lifecycle-runtime-update
   (-> path-string? string? odra-package-lifecycle-runtime-result?)]
  [package-lifecycle-runtime-rollback
   (-> path-string? string? odra-package-lifecycle-runtime-result?)]
  [package-lifecycle-runtime-remove
   (-> path-string? string? odra-package-lifecycle-runtime-result?)]
  [package-lifecycle-runtime-cleanup
   (-> path-string? odra-package-lifecycle-runtime-result?)]
  [package-lifecycle-runtime-doctor
   (-> path-string? odra-package-lifecycle-runtime-result?)]
  [package-lifecycle-runtime-catalog
   (-> path-string? odra-command-catalog?)]
  [package-lifecycle-runtime-keymaps
   (-> path-string? (listof bundle:odra-language-keymap?))]
  [package-lifecycle-runtime-command-call
   (-> path-string? string? any/c any/c)]))

(struct odra-package-lifecycle-runtime-result
  (status generation item-count identity detail)
  #:transparent)

(define managers (make-hash))

(define current-package-lifecycle-installer
  (make-parameter
   (lambda (_root _id _version)
     "No exact resolved release is available; refresh package catalogs and select a release")))

(module+ test-support
  (provide current-package-lifecycle-installer
           reset-package-lifecycle-runtime!))

(define (reset-package-lifecycle-runtime!)
  (for ([manager (in-hash-values managers)])
    (package-runtime-close! (package-lifecycle-runtime manager)))
  (hash-clear! managers))

(define (manager-for root)
  (define complete (path->string (path->complete-path root)))
  (hash-ref!
   managers complete
   (lambda ()
     (when (link-exists? complete)
       (raise-arguments-error 'package-lifecycle-runtime
                              "package data root cannot be a symbolic link"
                              "root" complete))
     (unless (directory-exists? complete)
       (make-directory* complete))
     (file-or-directory-permissions complete #o700)
     (define manager (make-package-lifecycle-manager complete))
     (package-lifecycle-restore! manager)
     manager)))

(define (runtime-result manager status detail [item-count 0] [identity ""])
  (odra-package-lifecycle-runtime-result
   status
   (odra-package-state-generation (package-lifecycle-state manager))
   item-count identity detail))

(define (authority-summary authorities)
  (if (null? authorities)
      "none"
      (string-join (map symbol->string authorities) ", ")))

(define (inspection-line inspection)
  (format "~a@~a | ~a | publisher ~a | requested authorities ~a | granted authorities ~a"
          (odra-package-lifecycle-inspection-package-id inspection)
          (odra-package-lifecycle-inspection-version inspection)
          (odra-package-lifecycle-inspection-lifecycle inspection)
          (odra-package-lifecycle-inspection-publisher inspection)
          (authority-summary
           (odra-package-lifecycle-inspection-requested-authorities inspection))
          (authority-summary
           (odra-package-lifecycle-inspection-granted-authorities inspection))))

(define (package-lifecycle-runtime-list root)
  (define manager (manager-for root))
  (define inspections (package-lifecycle-list manager))
  (runtime-result
   manager 'success
   (if (null? inspections)
       "No packages are installed"
       (string-join (map inspection-line inspections) "\n"))
   (length inspections)))

(define (split-release value required-version?)
  (define parts (string-split value "@" #:trim? #f))
  (cond
    [(and (= (length parts) 2)
          (not (string=? (car parts) ""))
          (not (string=? (cadr parts) "")))
     (values (car parts) (cadr parts) #f)]
    [(and (not required-version?) (= (length parts) 1)
          (not (string=? value "")))
     (values value #f #f)]
    [else
     (values #f #f
             (if required-version?
                 "Select a package as package.name@1.2.3"
                 "Select a package by name, optionally as package.name@1.2.3"))]))

(define (package-lifecycle-runtime-describe root value)
  (define manager (manager-for root))
  (define-values (id version problem) (split-release value #f))
  (cond
    [problem (runtime-result manager 'failure problem)]
    [else
     (define inspections (package-lifecycle-inspect manager id version))
     (runtime-result
      manager
      (if (null? inspections) 'failure 'success)
      (if (null? inspections)
          (format "Package ~a is not installed; run package-discover" value)
          (string-join (map inspection-line inspections) "\n"))
      (length inspections) value)]))

(define (from-lifecycle manager result identity success-detail)
  (runtime-result
   manager
   (if (memq (odra-package-lifecycle-result-status result)
             '(cleaned disabled enabled installed removed restored rolled-back
                       unchanged updated healthy))
       'success 'failure)
   (if (string=? (odra-package-lifecycle-result-detail result) "")
       success-detail
       (odra-package-lifecycle-result-detail result))
   (length (odra-package-lifecycle-result-values result))
   identity))

(define (package-lifecycle-runtime-install
         root value #:installer [installer (current-package-lifecycle-installer)])
  (define manager (manager-for root))
  (define-values (id version problem) (split-release value #t))
  (cond
    [problem (runtime-result manager 'failure problem)]
    [else
     (define prepared (installer root id version))
     (cond
       [(string? prepared) (runtime-result manager 'failure prepared 0 value)]
       [(and (pair? prepared)
             (odra-package-installation-candidate? (car prepared))
             (pair? (cdr prepared))
             (odra-package-acquisition? (cadr prepared)))
        (define installed
          (package-lifecycle-install! manager (car prepared) (cadr prepared)))
        (define installed-package
          (odra-package-lifecycle-result-package installed))
        (define requested-authorities
          (if (odra-installed-package? installed-package)
              (odra-installed-package-requested-authorities installed-package)
              '()))
        (from-lifecycle
         manager
         installed
         value
         (format
          "Installed ~a in disabled state; requested authorities: ~a"
          value
          (authority-summary requested-authorities)))]
       [else
        (runtime-result manager 'failure
                        "The resolved package release is incomplete" 0 value)])]))

(define (package-lifecycle-runtime-enable root value)
  (define manager (manager-for root))
  (define-values (id version problem) (split-release value #t))
  (if problem
      (runtime-result manager 'failure problem)
      (from-lifecycle
       manager
       (package-lifecycle-enable!
        manager id version "confirmed through package-enable")
       value (format "Enabled ~a" value))))

(define (package-lifecycle-runtime-disable root value)
  (define manager (manager-for root))
  (define-values (id _version problem) (split-release value #f))
  (if problem
      (runtime-result manager 'failure problem)
      (from-lifecycle manager (package-lifecycle-disable! manager id)
                      id (format "Disabled ~a" id))))

(define (package-lifecycle-runtime-update root value)
  (define manager (manager-for root))
  (define-values (id version problem) (split-release value #t))
  (if problem
      (runtime-result manager 'failure problem)
      (from-lifecycle
       manager
       (package-lifecycle-update!
        manager id version "confirmed through package-update")
       value (format "Updated ~a" value))))

(define (package-lifecycle-runtime-rollback root value)
  (define manager (manager-for root))
  (define-values (id _version problem) (split-release value #f))
  (if problem
      (runtime-result manager 'failure problem)
      (from-lifecycle
       manager
       (package-lifecycle-rollback!
        manager id "confirmed through package-rollback")
       id (format "Rolled back ~a" id))))

(define (package-lifecycle-runtime-remove root value)
  (define manager (manager-for root))
  (define-values (id version problem) (split-release value #t))
  (if problem
      (runtime-result manager 'failure problem)
      (from-lifecycle manager (package-lifecycle-remove! manager id version)
                      value (format "Removed ~a" value))))

(define digest-pattern #px"^[0-9a-f]{64}$")

(define (stored-content root)
  (define sha-root
    (build-path (path->complete-path root) "packages" "content" "sha256"))
  (if (directory-exists? sha-root)
      (sort
       (for*/list ([prefix (in-list (directory-list sha-root #:build? #t))]
                   #:when (directory-exists? prefix)
                   [path (in-list (directory-list prefix #:build? #t))]
                   #:do [(define name (path->string (file-name-from-path path)))]
                   #:when (and (file-exists? path)
                               (regexp-match? digest-pattern name)))
         name)
       string<?)
      '()))

(define (package-lifecycle-runtime-cleanup root)
  (define manager (manager-for root))
  (define result
    (package-lifecycle-cleanup!
     manager (stored-content root)
     (lambda (digest)
       (define path (package-content-path root digest))
       (and (file-exists? path)
            (begin (delete-file path) #t)))))
  (from-lifecycle
   manager result "package-content"
   (format "Removed ~a unreachable content object(s)"
           (length (odra-package-lifecycle-result-values result)))))

(define (package-lifecycle-runtime-doctor root)
  (define manager (manager-for root))
  (define result (package-lifecycle-doctor manager))
  (from-lifecycle manager result "package-runtime"
                  "Package lifecycle state is healthy"))

(define (package-lifecycle-runtime-catalog root)
  (package-runtime-catalog (package-lifecycle-runtime (manager-for root))))

(define (package-lifecycle-runtime-keymaps root)
  (package-runtime-keymaps (package-lifecycle-runtime (manager-for root))))

(define (package-lifecycle-runtime-command-call root name context)
  (package-runtime-command-call
   (package-lifecycle-runtime (manager-for root)) name context))
