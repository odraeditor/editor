#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/path
         "../project/candidate-usage.rkt"
         "private/legacy-catalog.rkt"
         "private/legacy-records.rkt")

(provide
 (struct-out odra-legacy-project-proposal)
 (struct-out odra-legacy-state-proposal)
 (struct-out odra-legacy-inventory-rejection)
 (struct-out odra-legacy-migration-inventory)
 (contract-out
  [legacy-migration-inventory-load
   (-> path-string? odra-legacy-migration-inventory?)]))

(define maximum-legacy-proposals 1024)
(define maximum-legacy-path-bytes maximum-project-path-bytes)
(define maximum-legacy-message-bytes maximum-project-diagnostic-bytes)
(define allowed-state-observations '(confirmed rejected unavailable))

(define (bounded-text? value maximum [empty-allowed? #f])
  (and (string? value)
       (or empty-allowed? (positive? (string-length value)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (copied-text value)
  (string->immutable-string
   (if (path? value) (path->string value) value)))

(struct odra-legacy-project-proposal
  (id generation name roots trusts source)
  #:transparent
  #:guard
  (lambda (id generation name roots trusts source _)
    (unless (and (bounded-text? id maximum-project-identity-bytes)
                 (exact-positive-integer? generation)
                 (bounded-text? name maximum-project-name-bytes)
                 (list? roots)
                 (pair? roots)
                 (<= (length roots) maximum-project-directories)
                 (andmap (lambda (root) (bounded-text? root maximum-legacy-path-bytes)) roots)
                 (list? trusts)
                 (= (length trusts) (length roots))
                 (andmap (lambda (trust) (memq trust '(untrusted trusted))) trusts)
                 (bounded-text? source maximum-legacy-path-bytes))
      (raise-arguments-error 'odra-legacy-project-proposal
                             "invalid copied legacy Project proposal"))
    (values (copied-text id)
            generation
            (copied-text name)
            (map copied-text roots)
            (for/list ([trust (in-list trusts)]) trust)
            (copied-text source))))

(struct odra-legacy-state-proposal
  (project-id observation source generation module-bytes)
  #:transparent
  #:guard
  (lambda (project-id observation source generation module-bytes _)
    (unless (and (bounded-text? project-id maximum-project-identity-bytes)
                 (memq observation allowed-state-observations)
                 (bounded-text? source maximum-legacy-path-bytes)
                 (exact-nonnegative-integer? generation)
                 (bytes? module-bytes)
                 (<= (bytes-length module-bytes) maximum-candidate-usage-module-bytes))
      (raise-arguments-error 'odra-legacy-state-proposal
                             "invalid copied legacy state proposal"))
    (values (copied-text project-id)
            observation
            (copied-text source)
            generation
            (bytes->immutable-bytes module-bytes))))

(struct odra-legacy-inventory-rejection (source code message)
  #:transparent
  #:guard
  (lambda (source code message _)
    (unless (and (bounded-text? source maximum-legacy-path-bytes)
                 (symbol? code)
                 (bounded-text? message maximum-legacy-message-bytes))
      (raise-arguments-error 'odra-legacy-inventory-rejection
                             "invalid copied legacy inventory rejection"))
    (values (copied-text source) code (copied-text message))))

(struct odra-legacy-migration-inventory
  (projects states rejections examined-projects evaluated-bytes)
  #:transparent
  #:guard
  (lambda (projects states rejections examined-projects evaluated-bytes _)
    (unless (and (list? projects)
                 (andmap odra-legacy-project-proposal? projects)
                 (<= (length projects) maximum-legacy-proposals)
                 (list? states)
                 (andmap odra-legacy-state-proposal? states)
                 (<= (length states) maximum-legacy-proposals)
                 (list? rejections)
                 (andmap odra-legacy-inventory-rejection? rejections)
                 (<= (length rejections) (* 2 maximum-legacy-proposals))
                 (exact-nonnegative-integer? examined-projects)
                 (exact-nonnegative-integer? evaluated-bytes))
      (raise-arguments-error 'odra-legacy-migration-inventory
                             "invalid bounded legacy migration inventory"))
    (values projects states rejections examined-projects evaluated-bytes)))

;; legacy-migration-inventory-load copies legacy Project and candidate state without writing.
(define (legacy-migration-inventory-load legacy-root)
  (define root (path->complete-path legacy-root))
  (define catalog (project-catalog-load (build-path root "projects")))
  (define projects
    (for/list ([entry (in-list (odra-project-catalog-entries catalog))])
      (entry->project-proposal entry)))
  (define-values (states state-rejections state-bytes)
    (for/fold ([states '()] [rejections '()] [evaluated-bytes 0])
              ([project (in-list projects)])
      (define observation
        (candidate-usage-load
         (build-path root "state")
         (odra-legacy-project-proposal-id project)))
      (define state (odra-candidate-usage-observation-state observation))
      (cond
        [(eq? state 'absent) (values states rejections evaluated-bytes)]
        [(eq? state 'confirmed)
         (define record (odra-candidate-usage-observation-record observation))
         (define module-bytes (odra-candidate-usage-observation-module-bytes observation))
         (values
          (cons
           (odra-legacy-state-proposal
            (odra-legacy-project-proposal-id project)
            state
            (odra-candidate-usage-observation-target observation)
            (odra-candidate-usage-record-generation record)
            module-bytes)
           states)
          rejections
          (+ evaluated-bytes (bytes-length module-bytes)))]
        [else
         (define diagnostic (odra-candidate-usage-observation-diagnostic observation))
         (values
          states
          (cons
           (odra-legacy-inventory-rejection
            (odra-candidate-usage-observation-target observation)
            (odra-candidate-usage-diagnostic-code diagnostic)
            (odra-candidate-usage-diagnostic-message diagnostic))
           rejections)
          evaluated-bytes)])))
  (odra-legacy-migration-inventory
   projects
   (reverse states)
   (sort
    (append
     (map catalog-rejection->inventory (project-catalog-rejected catalog))
     state-rejections)
    (lambda (left right)
      (string<? (odra-legacy-inventory-rejection-source left)
                (odra-legacy-inventory-rejection-source right))))
   (odra-project-catalog-examined-entries catalog)
   (+ (odra-project-catalog-evaluated-bytes catalog) state-bytes)))

(define (entry->project-proposal entry)
  (define descriptor (odra-project-catalog-entry-descriptor entry))
  (define record
    (odra-project-proposal-record
     (odra-project-catalog-entry-proposal entry)))
  (define dirs (odra-project-record-directories record))
  (odra-legacy-project-proposal
   (odra-project-record-id record)
   (odra-project-record-generation record)
   (odra-project-record-name record)
   (map odra-project-directory-path dirs)
   (map odra-project-directory-trust dirs)
   (odra-project-catalog-descriptor-source descriptor)))

(define (catalog-rejection->inventory rejection)
  (odra-legacy-inventory-rejection
   (odra-project-catalog-rejection-source rejection)
   (odra-project-catalog-rejection-code rejection)
   (odra-project-catalog-rejection-message rejection)))
