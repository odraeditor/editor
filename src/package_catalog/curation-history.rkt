#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "curation-records.rkt")

(provide
 maximum-package-curation-history-records
 (struct-out odra-package-curation-history-failure)
 (contract-out
  [reconcile-package-curation-assertion
   (-> (listof odra-package-curation-assertion?)
       odra-package-curation-assertion?
       (values (listof odra-package-curation-assertion?)
               (or/c #f odra-package-curation-history-failure?)))]
  [package-curation-latest-assertions
   (-> (listof odra-package-curation-assertion?)
       (listof odra-package-curation-assertion?))]))

(define maximum-package-curation-history-records 4096)

(struct odra-package-curation-history-failure (code field expected actual)
  #:transparent
  #:guard
  (lambda (code field expected actual _)
    (unless
        (and (memq code '(duplicate-release history-limit identity-change
                                            invalid-generation invalid-transition
                                            rewrite stale-generation))
             (symbol? field))
      (raise-arguments-error 'odra-package-curation-history-failure
                             "invalid curation history failure"))
    (values code field expected actual)))

(define (failure code field [expected #f] [actual #f])
  (odra-package-curation-history-failure code field expected actual))

(define (assertion-key assertion)
  (cons (odra-package-curation-assertion-id assertion)
        (odra-package-curation-assertion-sequence assertion)))

(define (assertion<? left right)
  (define left-id (odra-package-curation-assertion-id left))
  (define right-id (odra-package-curation-assertion-id right))
  (if (string=? left-id right-id)
      (< (odra-package-curation-assertion-sequence left)
         (odra-package-curation-assertion-sequence right))
      (string<? left-id right-id)))

(define (same-release-identity? left right)
  (define left-release (odra-package-curation-assertion-release left))
  (define right-release (odra-package-curation-assertion-release right))
  (and (string=? (odra-package-curation-assertion-catalog-id left)
                 (odra-package-curation-assertion-catalog-id right))
       (string=? (odra-package-release-reference-release-id left-release)
                 (odra-package-release-reference-release-id right-release))))

(define (latest-for-id history assertion-id)
  (for/fold ([latest #f]) ([candidate (in-list history)]
                           #:when
                           (string=? assertion-id
                                     (odra-package-curation-assertion-id candidate)))
    (if (or (not latest)
            (> (odra-package-curation-assertion-sequence candidate)
               (odra-package-curation-assertion-sequence latest)))
        candidate
        latest)))

(define (transition-valid? previous next)
  (define previous-status
    (odra-package-curation-assertion-status previous))
  (define next-status (odra-package-curation-assertion-status next))
  (and (not (eq? previous-status next-status))
       (case previous-status
         [(admitted) (memq next-status '(deprecated quarantined withdrawn))]
         [(deprecated) (memq next-status '(admitted quarantined withdrawn))]
         [(withdrawn) (memq next-status '(admitted quarantined))]
         [(quarantined) (memq next-status '(admitted withdrawn))]
         [else #f])))

(define (reconcile-package-curation-assertion history candidate)
  (cond
    [(>= (length history) maximum-package-curation-history-records)
     (values history
             (failure 'history-limit 'assertions
                      maximum-package-curation-history-records
                      (add1 (length history))))]
    [(member (assertion-key candidate) (map assertion-key history) equal?)
     (values history
             (failure 'rewrite 'sequence #f
                      (odra-package-curation-assertion-sequence candidate)))]
    [else
     (define previous
       (latest-for-id history (odra-package-curation-assertion-id candidate)))
     (cond
       [(not previous)
        (cond
          [(not (= (odra-package-curation-assertion-sequence candidate) 1))
           (values history
                   (failure 'invalid-generation 'sequence 1
                            (odra-package-curation-assertion-sequence candidate)))]
          [(not (eq? (odra-package-curation-assertion-status candidate) 'admitted))
           (values history
                   (failure 'invalid-transition 'status 'admitted
                            (odra-package-curation-assertion-status candidate)))]
          [(not (= (odra-package-curation-assertion-first-snapshot-sequence candidate)
                   (odra-package-curation-assertion-last-status-snapshot-sequence
                    candidate)))
           (values history
                   (failure 'invalid-generation 'snapshot-sequence
                            (odra-package-curation-assertion-first-snapshot-sequence
                             candidate)
                            (odra-package-curation-assertion-last-status-snapshot-sequence
                             candidate)))]
          [(for/or ([existing (in-list history)])
             (same-release-identity? existing candidate))
           (values history
                   (failure 'duplicate-release 'release-id #f
                            (odra-package-release-reference-release-id
                             (odra-package-curation-assertion-release candidate))))]
          [else
           (values (sort (cons candidate history) assertion<?) #f)])]
       [(not (and
              (string=? (odra-package-curation-assertion-catalog-id previous)
                        (odra-package-curation-assertion-catalog-id candidate))
              (same-package-release?
               (odra-package-curation-assertion-release previous)
               (odra-package-curation-assertion-release candidate))
              (= (odra-package-curation-assertion-first-snapshot-sequence previous)
                 (odra-package-curation-assertion-first-snapshot-sequence candidate))))
        (values history (failure 'identity-change 'assertion))]
       [(not (= (odra-package-curation-assertion-sequence candidate)
                (add1 (odra-package-curation-assertion-sequence previous))))
        (values history
                (failure 'stale-generation 'sequence
                         (add1 (odra-package-curation-assertion-sequence previous))
                         (odra-package-curation-assertion-sequence candidate)))]
       [(or (string=? (odra-package-curation-assertion-decision-id previous)
                      (odra-package-curation-assertion-decision-id candidate))
            (<= (odra-package-curation-assertion-last-status-snapshot-sequence
                 candidate)
                (odra-package-curation-assertion-last-status-snapshot-sequence
                 previous)))
        (values history
                (failure 'stale-generation 'decision-or-snapshot #f
                         (odra-package-curation-assertion-decision-id candidate)))]
       [(not (transition-valid? previous candidate))
        (values history
                (failure 'invalid-transition 'status
                         (odra-package-curation-assertion-status previous)
                         (odra-package-curation-assertion-status candidate)))]
       [else (values (sort (cons candidate history) assertion<?) #f)])]))

(define (package-curation-latest-assertions history)
  (sort
   (hash-values
    (for/fold ([latest (hash)]) ([candidate (in-list history)])
      (define id (odra-package-curation-assertion-id candidate))
      (define current (hash-ref latest id #f))
      (if (or (not current)
              (> (odra-package-curation-assertion-sequence candidate)
                 (odra-package-curation-assertion-sequence current)))
          (hash-set latest id candidate)
          latest)))
   string<? #:key odra-package-curation-assertion-id))
