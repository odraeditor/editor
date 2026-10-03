#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/file
         racket/list
         "../storage/record-codec.rkt"
         "persistence.rkt"
         "records.rkt")

(provide
 (struct-out odra-promotion-suppression-state)
 (struct-out odra-promotion-suppression-failure)
 (contract-out
  [promotion-suppression-inspect
   (-> path-string? string?
       (or/c odra-promotion-suppression-state?
             odra-promotion-suppression-failure?))]
  [promotion-suppression-add
   (-> path-string? string?
       (or/c odra-promotion-suppression-state?
             odra-promotion-suppression-failure?))]
  [promotion-suppression-remove
   (-> path-string? string?
       (or/c odra-promotion-suppression-state?
             odra-promotion-suppression-failure?))]))

(define allowed-actions '(inspected added removed unchanged))
(define allowed-failure-codes
  '(invalid-dir invalid-record suppression-limit persistence-failed
                publication-unresolved))
(define allowed-publications '(none durable uncertain))

(struct suppression-snapshot (generation dirs) #:transparent)

(struct odra-promotion-suppression-state (action generation suppressed? dirs)
  #:transparent
  #:guard
  (lambda (action generation suppressed? dirs _)
    (unless (and (memq action allowed-actions)
                 (exact-nonnegative-integer? generation)
                 (boolean? suppressed?)
                 (list? dirs)
                 (<= (length dirs) maximum-promotion-suppressions)
                 (andmap record-path? dirs))
      (raise-arguments-error 'odra-promotion-suppression-state
                             "invalid copied promotion suppression state"))
    (values action generation suppressed?
            (for/list ([dir (in-list dirs)]) (record-copied-text dir)))))

(struct odra-promotion-suppression-failure (code message publication)
  #:transparent
  #:guard
  (lambda (code message publication _)
    (unless (and (memq code allowed-failure-codes)
                 (string? message)
                 (positive? (string-length message))
                 (<= (bytes-length (string->bytes/utf-8 message))
                     maximum-record-diagnostic-bytes)
                 (memq publication allowed-publications))
      (raise-arguments-error 'odra-promotion-suppression-failure
                             "invalid bounded suppression failure"))
    (values code (record-copied-text message) publication)))

;; promotion-suppression-inspect reads one exact global Dir preference without writing.
(define (promotion-suppression-inspect configuration-root dir)
  (cond
    [(not (record-path? dir))
     (suppression-failure 'invalid-dir "Suppression requires a normalized absolute Dir")]
    [else
     (define loaded (load-suppressions configuration-root))
     (if (odra-promotion-suppression-failure? loaded)
         loaded
         (suppression-state 'inspected loaded dir))]))

;; promotion-suppression-add atomically adds one bounded exact Dir preference.
(define (promotion-suppression-add configuration-root dir)
  (update-suppression configuration-root dir #t))

;; promotion-suppression-remove atomically removes one exact Dir preference.
(define (promotion-suppression-remove configuration-root dir)
  (update-suppression configuration-root dir #f))

(define (update-suppression configuration-root dir add?)
  (cond
    [(not (record-path? dir))
     (suppression-failure 'invalid-dir "Suppression requires a normalized absolute Dir")]
    [else
     (define loaded (load-suppressions configuration-root))
     (cond
       [(odra-promotion-suppression-failure? loaded) loaded]
       [else
        (define dirs (suppression-snapshot-dirs loaded))
        (define present? (and (member dir dirs) #t))
        (cond
          [(eq? present? add?)
           (odra-promotion-suppression-state
            'unchanged
            (suppression-snapshot-generation loaded)
            add?
            dirs)]
          [(and add? (= (length dirs) maximum-promotion-suppressions))
           (suppression-failure
            'suppression-limit "Promotion suppression limit reached")]
          [else
           (define next-dirs
             (sort
              (if add? (cons dir dirs) (remove dir dirs))
              string<?))
           (define next
             (promotion-suppressions-record
              #:format-version current-promotion-suppressions-format-version
              #:generation
              (add1 (suppression-snapshot-generation loaded))
              #:dirs next-dirs))
           (persist-suppression configuration-root next dir add?)])])]))

(define (load-suppressions configuration-root)
  (define target (promotion-suppressions-record-path configuration-root))
  (cond
    [(not (or (file-exists? target) (link-exists? target)))
     (suppression-snapshot 0 '())]
    [(link-exists? target)
     (suppression-failure 'invalid-record
                          "Promotion suppressions cannot be a symbolic link")]
    [else
     (define loaded (promotion-suppressions-record-module-load target))
     (if (odra-promotion-suppressions-record? loaded)
         (suppression-snapshot
          (odra-promotion-suppressions-record-generation loaded)
          (odra-promotion-suppressions-record-dirs loaded))
         (suppression-failure
          'invalid-record
          (odra-record-diagnostic-message loaded)))]))

(define (persist-suppression configuration-root record dir add?)
  (define persisted
    (promotion-suppressions-record-persist configuration-root record))
  (define reloaded (load-suppressions configuration-root))
  (cond
    [(and (odra-record-publication? persisted)
          (suppression-snapshot? reloaded)
          (= (suppression-snapshot-generation reloaded)
             (odra-promotion-suppressions-record-generation record))
          (equal? (suppression-snapshot-dirs reloaded)
                  (odra-promotion-suppressions-record-dirs record)))
     (odra-promotion-suppression-state
      (if add? 'added 'removed)
      (odra-promotion-suppressions-record-generation record)
      add?
      (odra-promotion-suppressions-record-dirs record))]
    [(odra-record-publication-failure? persisted)
     (suppression-failure
      (if (eq? (odra-record-publication-failure-publication persisted)
               'not-published)
          'persistence-failed
          'publication-unresolved)
      (odra-record-publication-failure-message persisted)
      (if (eq? (odra-record-publication-failure-publication persisted)
               'not-published)
          'none
          'uncertain))]
    [else
     (suppression-failure
      'publication-unresolved
      "Promotion suppression publication could not be reconciled"
      'uncertain)]))

(define (suppression-state action record dir)
  (odra-promotion-suppression-state
   action
   (suppression-snapshot-generation record)
   (and (member dir (suppression-snapshot-dirs record)) #t)
   (suppression-snapshot-dirs record)))

(define (suppression-failure code message [publication 'none])
  (odra-promotion-suppression-failure code message publication))
