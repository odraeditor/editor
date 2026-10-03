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
 (struct-out odra-named-locations-state)
 (struct-out odra-named-locations-failure)
 (contract-out
  [named-locations-list
   (-> path-string?
       (or/c odra-named-locations-state? odra-named-locations-failure?))]
  [named-locations-save
   (-> path-string?
       #:name string?
       #:target string?
       #:point exact-nonnegative-integer?
       #:mark (or/c #f exact-nonnegative-integer?)
       #:region-active? boolean?
       #:summary string?
       (or/c odra-named-locations-state? odra-named-locations-failure?))]))

(define allowed-actions '(listed saved replaced))
(define allowed-failure-codes
  '(invalid-location invalid-record location-limit persistence-failed
                     publication-unresolved))
(define allowed-publications '(none durable uncertain))

(struct named-locations-snapshot (generation locations slots) #:transparent)

(struct odra-named-locations-state (action generation locations)
  #:transparent
  #:guard
  (lambda (action generation locations _)
    (unless (and (memq action allowed-actions)
                 (exact-nonnegative-integer? generation)
                 (list? locations)
                 (<= (length locations) maximum-saved-entries)
                 (andmap odra-named-location? locations))
      (raise-arguments-error 'odra-named-locations-state
                             "invalid named locations state"))
    (values action generation (for/list ([location (in-list locations)]) location))))

(struct odra-named-locations-failure (code message publication)
  #:transparent
  #:guard
  (lambda (code message publication _)
    (unless (and (memq code allowed-failure-codes)
                 (string? message)
                 (positive? (string-length message))
                 (<= (bytes-length (string->bytes/utf-8 message))
                     maximum-record-diagnostic-bytes)
                 (memq publication allowed-publications))
      (raise-arguments-error 'odra-named-locations-failure
                             "invalid named locations failure"))
    (values code (record-copied-text message) publication)))

;; named-locations-list reads the complete validated global location collection.
(define (named-locations-list configuration-root)
  (define loaded (load-named-locations configuration-root))
  (if (odra-named-locations-failure? loaded)
      loaded
      (odra-named-locations-state
       'listed
       (named-locations-snapshot-generation loaded)
       (named-locations-snapshot-locations loaded))))

;; named-locations-save creates or atomically replaces one normalized location name.
(define (named-locations-save configuration-root
                              #:name name
                              #:target target
                              #:point point
                              #:mark mark
                              #:region-active? region-active?
                              #:summary summary)
  (define location
    (with-handlers ([exn:fail?
                     (lambda (failure)
                       (named-locations-failure 'invalid-location
                                                (exn-message failure)))])
      (named-location
       #:name name #:target target #:point point #:mark mark
       #:region-active? region-active? #:summary summary)))
  (cond
    [(odra-named-locations-failure? location) location]
    [else
     (define loaded (load-named-locations configuration-root))
     (cond
       [(odra-named-locations-failure? loaded) loaded]
       [else
        (define locations (named-locations-snapshot-locations loaded))
        (define slots (named-locations-snapshot-slots loaded))
        (define existing
          (for/first ([current (in-list locations)]
                      #:when (string=? (odra-named-location-name current)
                                       (odra-named-location-name location)))
            current))
        (cond
          [(for/or ([slot (in-list slots)])
             (string=? (odra-named-slot-name slot) (odra-named-location-name location)))
           (named-locations-failure 'invalid-location
                                    "Named entry already has another kind")]
          [(and (not existing)
                (= (+ (length locations) (length slots)) maximum-saved-entries))
           (named-locations-failure 'location-limit "Named location limit reached")]
          [else
           (define next-locations
             (sort
              (if existing
                  (for/list ([current (in-list locations)])
                    (if (string=? (odra-named-location-name current)
                                  (odra-named-location-name location))
                        location
                        current))
                  (cons location locations))
              string<?
              #:key odra-named-location-name))
           (define next
             (saved-state-record
              #:format-version current-saved-state-format-version
              #:generation (add1 (named-locations-snapshot-generation loaded))
              #:locations next-locations
              #:slots slots))
           (persist-named-locations configuration-root next existing)])])]))

(define (load-named-locations configuration-root)
  (define target (saved-state-record-path configuration-root))
  (cond
    [(not (or (file-exists? target) (link-exists? target)))
     (named-locations-snapshot 0 '() '())]
    [(link-exists? target)
     (named-locations-failure 'invalid-record
                              "Named locations cannot be a symbolic link")]
    [else
     (define loaded (saved-state-record-module-load target))
     (if (odra-saved-state-record? loaded)
         (named-locations-snapshot
          (odra-saved-state-record-generation loaded)
          (odra-saved-state-record-locations loaded)
          (odra-saved-state-record-slots loaded))
         (named-locations-failure
          'invalid-record
          (odra-record-diagnostic-message loaded)))]))

(define (persist-named-locations configuration-root record existing)
  (define persisted (saved-state-record-persist configuration-root record))
  (define reloaded (load-named-locations configuration-root))
  (cond
    [(and (odra-record-publication? persisted)
          (named-locations-snapshot? reloaded)
          (= (named-locations-snapshot-generation reloaded)
             (odra-saved-state-record-generation record))
          (equal? (named-locations-snapshot-locations reloaded)
                  (odra-saved-state-record-locations record)))
     (odra-named-locations-state
      (if existing 'replaced 'saved)
      (odra-saved-state-record-generation record)
      (odra-saved-state-record-locations record))]
    [(odra-record-publication-failure? persisted)
     (named-locations-failure
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
     (named-locations-failure
      'publication-unresolved
      "Named location publication could not be reconciled"
      'uncertain)]))

(define (named-locations-failure code message [publication 'none])
  (odra-named-locations-failure code message publication))

(module+ test
  (require racket/file rackunit)

  (define root (make-temporary-file "odra-named-locations-api~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind
    void
    (lambda ()
      (define saved
        (named-locations-save
         root #:name "first" #:target "/tmp/first.odin" #:point 2 #:mark #f
         #:region-active? #f #:summary "first.odin"))
      (check-equal? (odra-named-locations-state-action saved) 'saved)
      (define replaced
        (named-locations-save
         root #:name " first " #:target "/tmp/replaced.odin" #:point 8 #:mark 3
         #:region-active? #t #:summary "replaced.odin"))
      (check-equal? (odra-named-locations-state-action replaced) 'replaced)
      (check-equal? (odra-named-locations-state-generation replaced) 2)
      (define listed (named-locations-list root))
      (check-equal? (odra-named-locations-state-action listed) 'listed)
      (check-equal? (length (odra-named-locations-state-locations listed)) 1)
      (check-equal?
       (odra-named-location-target
        (car (odra-named-locations-state-locations listed)))
       "/tmp/replaced.odin")
      (define full-record
        (saved-state-record
         #:format-version current-saved-state-format-version
         #:generation 3
         #:locations
         (sort
          (for/list ([index (in-range maximum-saved-entries)])
            (named-location
             #:name (format "location-~a" index)
             #:target (format "/tmp/location-~a.odin" index)
             #:point index
             #:mark #f
             #:region-active? #f
             #:summary (format "location-~a.odin" index)))
          string<?
          #:key odra-named-location-name)
         #:slots '()))
      (check-true
       (odra-record-publication?
        (saved-state-record-persist root full-record)))
      (define limited
        (named-locations-save
         root #:name "overflow" #:target "/tmp/overflow.odin" #:point 0 #:mark #f
         #:region-active? #f #:summary "overflow.odin"))
      (check-equal? (odra-named-locations-failure-code limited) 'location-limit)
      (check-equal?
       (odra-named-locations-state-generation (named-locations-list root))
       3))
    (lambda () (delete-directory/files root))))
