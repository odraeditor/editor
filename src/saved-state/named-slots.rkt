#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "../storage/record-codec.rkt"
         "persistence.rkt"
         "records.rkt")

(provide
 (struct-out odra-named-slots-state)
 (struct-out odra-named-slots-failure)
 (contract-out
  [named-slots-list
   (-> path-string? (or/c odra-named-slots-state? odra-named-slots-failure?))]
  [named-slot-store
   (-> path-string?
       #:name string?
       #:kind (or/c 'integer 'text 'position 'layout)
       #:value any/c
       #:replace-conflict? boolean?
       (or/c odra-named-slots-state? odra-named-slots-failure?))]
  [named-slot-increment
   (-> path-string?
       #:name string?
       #:delta exact-integer?
       (or/c odra-named-slots-state? odra-named-slots-failure?))]
  [named-slot-lookup
   (-> path-string?
       #:name string?
       #:kind (or/c 'integer 'text 'position 'layout)
       (or/c odra-named-slots-state? odra-named-slots-failure?))]))

(define allowed-actions '(listed stored replaced incremented found))
(define allowed-failure-codes
  '(invalid-slot invalid-record entry-limit kind-conflict missing-slot overflow
                 persistence-failed publication-unresolved))
(define allowed-publications '(none durable uncertain))

(struct named-state-snapshot (generation locations slots) #:transparent)

(struct odra-named-slots-state (action generation slots)
  #:transparent
  #:guard
  (lambda (action generation slots _)
    (unless (and (memq action allowed-actions)
                 (exact-nonnegative-integer? generation)
                 (list? slots)
                 (<= (length slots) maximum-named-slots)
                 (andmap odra-named-slot? slots))
      (raise-arguments-error 'odra-named-slots-state "invalid named slots state"))
    (values action generation (for/list ([slot (in-list slots)]) slot))))

(struct odra-named-slots-failure (code message conflict-kind publication)
  #:transparent
  #:guard
  (lambda (code message conflict-kind publication _)
    (unless (and (memq code allowed-failure-codes)
                 (string? message)
                 (positive? (string-length message))
                 (<= (bytes-length (string->bytes/utf-8 message))
                     maximum-record-diagnostic-bytes)
                 (or (not conflict-kind)
                     (memq conflict-kind '(location integer text position layout)))
                 (memq publication allowed-publications))
      (raise-arguments-error 'odra-named-slots-failure "invalid named slots failure"))
    (values code (record-copied-text message) conflict-kind publication)))

(define (named-slots-list configuration-root)
  (define loaded (load-named-state configuration-root))
  (if (odra-named-slots-failure? loaded)
      loaded
      (odra-named-slots-state
       'listed
       (named-state-snapshot-generation loaded)
       (named-state-snapshot-slots loaded))))

(define (named-slot-store configuration-root #:name name #:kind kind #:value value
                          #:replace-conflict? replace-conflict?)
  (define slot
    (with-handlers ([exn:fail?
                     (lambda (failure)
                       (slot-failure 'invalid-slot (exn-message failure)))])
      (named-slot #:name name #:kind kind #:value value)))
  (cond
    [(odra-named-slots-failure? slot) slot]
    [else
     (define loaded (load-named-state configuration-root))
     (cond
       [(odra-named-slots-failure? loaded) loaded]
       [else
        (define normalized-name (odra-named-slot-name slot))
        (define locations (named-state-snapshot-locations loaded))
        (define slots (named-state-snapshot-slots loaded))
        (define location-conflict
          (for/first ([location (in-list locations)]
                      #:when (string=? normalized-name (odra-named-location-name location)))
            location))
        (define existing
          (for/first ([current (in-list slots)]
                      #:when (string=? normalized-name (odra-named-slot-name current)))
            current))
        (define conflict-kind
          (cond [location-conflict 'location]
                [existing (odra-named-slot-kind existing)]
                [else #f]))
        (cond
          [(and conflict-kind
                (not (eq? conflict-kind kind))
                (not replace-conflict?))
           (slot-failure 'kind-conflict "Named entry already has another kind"
                         conflict-kind)]
          [(and (not conflict-kind)
                (= (+ (length locations) (length slots)) maximum-saved-entries))
           (slot-failure 'entry-limit "Named entry limit reached")]
          [else
           (define next-locations
             (if (and location-conflict replace-conflict?)
                 (filter (lambda (location)
                           (not (string=? normalized-name
                                          (odra-named-location-name location))))
                         locations)
                 locations))
           (define next-slots
             (sort
              (cons slot
                    (filter (lambda (current)
                              (not (string=? normalized-name
                                             (odra-named-slot-name current))))
                            slots))
              string<?
              #:key odra-named-slot-name))
           (persist-state
            configuration-root
            (saved-state-record
             #:format-version current-saved-state-format-version
             #:generation (add1 (named-state-snapshot-generation loaded))
             #:locations next-locations
             #:slots next-slots)
            (if conflict-kind 'replaced 'stored))])])]))

(define (named-slot-increment configuration-root #:name name #:delta delta)
  (define loaded (load-named-state configuration-root))
  (cond
    [(odra-named-slots-failure? loaded) loaded]
    [else
     (define normalized-name
       (with-handlers ([exn:fail? (lambda (_) #f)])
         (odra-named-slot-name (named-slot #:name name #:kind 'integer #:value 0))))
     (define existing
       (and normalized-name
            (for/first ([slot (in-list (named-state-snapshot-slots loaded))]
                        #:when (string=? normalized-name (odra-named-slot-name slot)))
              slot)))
     (cond
       [(not normalized-name) (slot-failure 'invalid-slot "Invalid named slot")]
       [(not existing) (slot-failure 'missing-slot "Named slot does not exist")]
       [(not (eq? (odra-named-slot-kind existing) 'integer))
        (slot-failure 'kind-conflict "Named slot is not an integer"
                      (odra-named-slot-kind existing))]
       [else
        (define next-value (+ (odra-named-slot-value existing) delta))
        (if (not (<= (- (expt 2 63)) next-value (sub1 (expt 2 63))))
            (slot-failure 'overflow "Named integer overflow")
            (let ([stored
                   (named-slot-store configuration-root
                                     #:name normalized-name
                                     #:kind 'integer
                                     #:value next-value
                                     #:replace-conflict? #f)])
              (if (odra-named-slots-state? stored)
                  (odra-named-slots-state
                   'incremented
                   (odra-named-slots-state-generation stored)
                   (odra-named-slots-state-slots stored))
                  stored)))])]))

(define (named-slot-lookup configuration-root #:name name #:kind kind)
  (define loaded (load-named-state configuration-root))
  (cond
    [(odra-named-slots-failure? loaded) loaded]
    [else
     (define normalized-name
       (with-handlers ([exn:fail? (lambda (_) #f)])
         (odra-named-slot-name
          (named-slot #:name name #:kind 'integer #:value 0))))
     (define existing
       (and normalized-name
            (for/first ([slot (in-list (named-state-snapshot-slots loaded))]
                        #:when (string=? normalized-name (odra-named-slot-name slot)))
              slot)))
     (cond
       [(not normalized-name) (slot-failure 'invalid-slot "Invalid named slot")]
       [(not existing) (slot-failure 'missing-slot "Named slot does not exist")]
       [(not (eq? (odra-named-slot-kind existing) kind))
        (slot-failure 'kind-conflict "Named slot has another kind"
                      (odra-named-slot-kind existing))]
       [else
        (odra-named-slots-state 'found (named-state-snapshot-generation loaded)
                                (list existing))])]))

(define (load-named-state configuration-root)
  (define target (saved-state-record-path configuration-root))
  (cond
    [(not (or (file-exists? target) (link-exists? target)))
     (named-state-snapshot 0 '() '())]
    [(link-exists? target)
     (slot-failure 'invalid-record "Named state cannot be a symbolic link")]
    [else
     (define loaded (saved-state-record-module-load target))
     (if (odra-saved-state-record? loaded)
         (named-state-snapshot
          (odra-saved-state-record-generation loaded)
          (odra-saved-state-record-locations loaded)
          (odra-saved-state-record-slots loaded))
         (slot-failure 'invalid-record
                       (odra-record-diagnostic-message loaded)))]))

(define (persist-state configuration-root record action)
  (define persisted (saved-state-record-persist configuration-root record))
  (define reloaded (load-named-state configuration-root))
  (cond
    [(and (odra-record-publication? persisted)
          (named-state-snapshot? reloaded)
          (= (named-state-snapshot-generation reloaded)
             (odra-saved-state-record-generation record))
          (equal? (named-state-snapshot-locations reloaded)
                  (odra-saved-state-record-locations record))
          (equal? (named-state-snapshot-slots reloaded)
                  (odra-saved-state-record-slots record)))
     (odra-named-slots-state action
                             (odra-saved-state-record-generation record)
                             (odra-saved-state-record-slots record))]
    [(odra-record-publication-failure? persisted)
     (slot-failure
      (if (eq? (odra-record-publication-failure-publication persisted)
               'not-published)
          'persistence-failed
          'publication-unresolved)
      (odra-record-publication-failure-message persisted)
      #f
      (if (eq? (odra-record-publication-failure-publication persisted)
               'not-published)
          'none
          'uncertain))]
    [else
     (slot-failure 'publication-unresolved
                   "Named state publication could not be reconciled"
                   #f 'uncertain)]))

(define (slot-failure code message [conflict-kind #f] [publication 'none])
  (odra-named-slots-failure code message conflict-kind publication))

(module+ test
  (require racket/file rackunit)

  (define root (make-temporary-file "odra-named-slots~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind
    void
    (lambda ()
      (define stored
        (named-slot-store root #:name "counter" #:kind 'integer #:value 4
                          #:replace-conflict? #f))
      (check-equal? (odra-named-slots-state-action stored) 'stored)
      (define incremented (named-slot-increment root #:name "counter" #:delta 3))
      (check-equal? (odra-named-slots-state-action incremented) 'incremented)
      (check-equal? (odra-named-slot-value
                     (car (odra-named-slots-state-slots incremented)))
                    7)
      (define conflict
        (named-slot-store root #:name "counter" #:kind 'text #:value "seven"
                          #:replace-conflict? #f))
      (check-equal? (odra-named-slots-failure-code conflict) 'kind-conflict)
      (define replaced
        (named-slot-store root #:name "counter" #:kind 'text #:value "seven"
                          #:replace-conflict? #t))
      (check-equal? (odra-named-slots-state-action replaced) 'replaced)
      (check-equal? (odra-named-slot-value
                     (car (odra-named-slots-state-slots
                           (named-slot-lookup root #:name "counter" #:kind 'text))))
                    "seven")
      (define maximum (sub1 (expt 2 63)))
      (named-slot-store root #:name "maximum" #:kind 'integer #:value maximum
                        #:replace-conflict? #f)
      (define overflow (named-slot-increment root #:name "maximum" #:delta 1))
      (check-equal? (odra-named-slots-failure-code overflow) 'overflow)
      (define unicode
        (named-slot-store root #:name "  pamięć  " #:kind 'text #:value "żółć λ"
                          #:replace-conflict? #f))
      (check-true (odra-named-slots-state? unicode))
      (check-equal? (odra-named-slot-name
                     (car (odra-named-slots-state-slots
                           (named-slot-lookup root #:name " pamięć " #:kind 'text))))
                    "pamięć"))
    (lambda () (delete-directory/files root))))
