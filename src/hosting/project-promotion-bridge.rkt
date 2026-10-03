#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         "../project/persistence.rkt"
         "../project/records.rkt"
         "../project/promotion.rkt"
         "../project/rename.rkt"
         "../project/promotion-suppressions.rkt"
         "../workspace/management.rkt")

(provide
 (contract-out
  [runtime-project-promotion-batch (-> bytes? bytes? bytes? list?)]
  [runtime-project-unregister-batch
   (-> bytes? bytes? bytes? exact-positive-integer? list?)]
  [runtime-project-rename-batch
   (-> bytes? bytes? bytes? exact-positive-integer? list?)]
  [runtime-promotion-suppression-batch
   (-> bytes? bytes? exact-nonnegative-integer? list?)]))

(define schema-version 1)
(define header-bytes 32)
(define publication-codes '((none . 1) (local . 2) (complete . 3) (uncertain . 4)))
(define suppression-publication-codes '((none . 1) (durable . 2) (uncertain . 3)))

(define (word value)
  (integer->integer-bytes value 8 #f #f))

(define (runtime-project-promotion-batch configuration-root-bytes root-bytes name-bytes)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #"" (string->bytes/utf-8 (exn-message failure))))])
    (define configuration-root
      (bytes->string/utf-8 configuration-root-bytes #f))
    (define root (bytes->string/utf-8 root-bytes #f))
    (define name (bytes->string/utf-8 name-bytes #f))
    (define composed (project-promotion-compose configuration-root root name))
    (define result
      (if (odra-project-promotion-proposal? composed)
          (project-promotion-publish configuration-root composed)
          composed))
    (define success? (odra-project-promotion-result? result))
    (define diagnostic
      (if success?
          #""
          (string->bytes/utf-8
           (odra-project-promotion-failure-message result))))
    (define state
      (cond
        [(not success?) 0]
        [(eq? (odra-project-promotion-result-state result) 'published) 1]
        [else 2]))
    (define publication
      (if success?
          3
          (cdr
           (assq (odra-project-promotion-failure-publication result)
                 publication-codes))))
    (list
     #t
     (bytes-append
      (word schema-version)
      (word (if success? 1 2))
      (word state)
      (word publication)
      diagnostic)
     #"")))

(define (runtime-project-unregister-batch configuration-root-bytes id-bytes root-bytes generation)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #"" (string->bytes/utf-8 (exn-message failure))))])
    (define configuration-root
      (bytes->string/utf-8 configuration-root-bytes #f))
    (define id (bytes->string/utf-8 id-bytes #f))
    (define root (bytes->string/utf-8 root-bytes #f))
    (define target (project-discovery-record-path configuration-root id))
    (define loaded
      (and (file-exists? target)
           (project-discovery-record-module-load target)))
    (define-values (success? state publication diagnostic)
      (cond
        [(not loaded)
         (values #t 2 3 #"")]
        [(not (odra-project-discovery-record? loaded))
         (values #f 0 1 #"Project registry metadata is invalid")]
        [(or (not (string=? root (odra-project-discovery-record-root loaded)))
             (not (= generation
                     (odra-project-discovery-record-expected-project-generation
                      loaded))))
         (values #f 0 1 #"Project registry entry changed before removal")]
        [else
         (delete-file target)
         (define pruned (workspace-prune-project-references configuration-root root))
         (if (odra-workspace-failure? pruned)
             (values #f 0 4
                     (string->bytes/utf-8
                      (odra-workspace-failure-message pruned)))
             (values #t 1 3 #""))]))
    (list
     #t
     (bytes-append
      (word schema-version)
      (word (if success? 1 2))
      (word state)
      (word publication)
      diagnostic)
     #"")))

(define (runtime-project-rename-batch configuration-root-bytes root-bytes name-bytes generation)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #"" (string->bytes/utf-8 (exn-message failure))))])
    (define result
      (project-rename
       (bytes->string/utf-8 configuration-root-bytes #f)
       (bytes->string/utf-8 root-bytes #f)
       generation
       (bytes->string/utf-8 name-bytes #f)))
    (define success? (odra-project-rename-result? result))
    (define diagnostic
      (if success?
          #""
          (string->bytes/utf-8 (odra-project-rename-failure-message result))))
    (define publication
      (if success?
          3
          (case (odra-project-rename-failure-publication result)
            [(none) 1]
            [else 4])))
    (list
     #t
     (bytes-append
      (word schema-version)
      (word (if success? 1 2))
      (word (if success? 1 0))
      (word publication)
      diagnostic)
     #"")))

(define (runtime-promotion-suppression-batch configuration-root-bytes root-bytes action)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #"" (string->bytes/utf-8 (exn-message failure))))])
    (define configuration-root
      (bytes->string/utf-8 configuration-root-bytes #f))
    (define root (bytes->string/utf-8 root-bytes #f))
    (define result
      (case action
        [(1) (promotion-suppression-inspect configuration-root root)]
        [(2) (promotion-suppression-add configuration-root root)]
        [(3) (promotion-suppression-remove configuration-root root)]
        [else (raise-argument-error
               'runtime-promotion-suppression-batch
               "an action from one through three"
               action)]))
    (define success? (odra-promotion-suppression-state? result))
    (define diagnostic
      (if success?
          #""
          (string->bytes/utf-8
           (odra-promotion-suppression-failure-message result))))
    (define publication
      (if success?
          2
          (cdr
           (assq (odra-promotion-suppression-failure-publication result)
                 suppression-publication-codes))))
    (list
     #t
     (bytes-append
      (word schema-version)
      (word (if success? 1 2))
      (word (if (and success?
                     (odra-promotion-suppression-state-suppressed? result))
                1
                0))
      (word (if success?
                (odra-promotion-suppression-state-generation result)
                0))
      (word publication)
      diagnostic)
     #"")))

(module+ test
  (require racket/file
           rackunit
           (submod "../project/promotion.rkt" test-support))

  (define root (make-temporary-file "odra-promotion-bridge-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (define dir (build-path root "source"))
  (define configuration-root (build-path root "config" "odra"))
  (make-directory dir)
  (dynamic-wind
   void
   (lambda ()
     (define batch
       (parameterize ([current-project-promotion-identity (lambda () "bridge-id")])
         (runtime-project-promotion-batch
          (path->bytes configuration-root)
          (path->bytes dir)
          #"Editable")))
     (check-true (car batch))
     (check-equal? (bytes-length (cadr batch)) header-bytes)
     (check-equal? (integer-bytes->integer (cadr batch) #f #f 8 16) 1))
   (lambda () (delete-directory/files root))))
