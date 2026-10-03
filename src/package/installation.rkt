#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/contract/base
         racket/file
         racket/list
         racket/string
         "../package_catalog/curation-records.rkt"
         "acquisition.rkt"
         "manifest-contracts.rkt"
         "resolution.rkt"
         "state-persistence.rkt"
         "state-records.rkt")

(provide
 (struct-out odra-package-installation-result)
 (struct-out odra-package-installation-failure)
 (contract-out
  [install-package-candidate!
   (->* (path-string? (or/c #f odra-package-state?)
                      odra-package-installation-candidate?
                      odra-package-acquisition?)
        (#:operation-id string?)
        (or/c odra-package-installation-result?
              odra-package-installation-failure?))]
  [recover-package-installations!
   (-> path-string? odra-package-state?
       (or/c odra-package-installation-result?
             odra-package-installation-failure?))]))

(struct odra-package-installation-result (state package idempotent? recovered?)
  #:transparent)

(struct odra-package-installation-failure (code package-id detail state)
  #:transparent)

(define current-package-installation-persist
  (make-parameter package-state-persist))

(define (file-digest path)
  (call-with-input-file path
    (lambda (input) (bytes->hex-string (sha256-bytes input)))
    #:mode 'binary))

(define (empty-state)
  (package-state-with-checksum
   (odra-package-state
    current-package-state-format-version "default" 0 0 '() #f #f '() '()
    (odra-package-accounting 0 0 0 0 0) #f (make-string 64 #\0))))

(define (package-key package)
  (format "~a@~a" (odra-installed-package-id package)
          (odra-installed-package-version package)))

(define (content-digests acquisition)
  (sort
   (remove-duplicates
    (cons (odra-package-acquisition-archive-digest acquisition)
          (map odra-package-content-handle-digest
               (odra-package-acquisition-content acquisition)))
    string=?)
   string<?))

(define (verified-file? path digest size)
  (and (file-exists? path) (not (link-exists? path))
       (= (file-size path) size) (string=? (file-digest path) digest)))

(define (acquisition-rejection candidate acquisition)
  (define release (odra-package-installation-candidate-release candidate))
  (define manifest (odra-package-installation-candidate-manifest candidate))
  (define expected-artifacts
    (filter
     (lambda (artifact)
       (define target (odra-package-artifact-target artifact))
       (or (not target)
           (and
            (eq? (odra-package-artifact-reference-platform
                  (odra-package-installation-candidate-artifact candidate))
                 (odra-package-target-platform target))
            (eq? (odra-package-artifact-reference-architecture
                  (odra-package-installation-candidate-artifact candidate))
                 (odra-package-target-architecture target)))))
     (odra-package-manifest-artifacts manifest)))
  (define handles (odra-package-acquisition-content acquisition))
  (define manifest-handles
    (filter (lambda (handle)
              (eq? 'manifest (odra-package-content-handle-kind handle)))
            handles))
  (define artifact-handles
    (filter (lambda (handle)
              (not (eq? 'manifest (odra-package-content-handle-kind handle))))
            handles))
  (cond
    [(not (and (string=? (odra-package-acquisition-package-id acquisition)
                         (odra-package-release-reference-package-id release))
               (string=? (odra-package-acquisition-version acquisition)
                         (odra-package-release-reference-version release))))
     "acquired package identity differs from the resolved release"]
    [(not (string=? (odra-package-acquisition-manifest-digest acquisition)
                    (odra-package-installation-candidate-manifest-digest candidate)))
     "acquired manifest digest differs from the resolved release"]
    [(not (string=? (odra-package-acquisition-archive-digest acquisition)
                    (odra-package-artifact-reference-digest
                     (odra-package-installation-candidate-artifact candidate))))
     "acquired archive digest differs from the resolved release"]
    [(not (verified-file?
           (odra-package-acquisition-archive-path acquisition)
           (odra-package-acquisition-archive-digest acquisition)
           (odra-package-artifact-reference-size
            (odra-package-installation-candidate-artifact candidate))))
     "acquired archive is absent or no longer verifies"]
    [(not (and (= (length manifest-handles) 1)
               (string=?
                (odra-package-content-handle-digest (car manifest-handles))
                (odra-package-installation-candidate-manifest-digest candidate))
               (= (odra-package-content-handle-size (car manifest-handles))
                  (bytes-length (package-manifest->canonical-bytes manifest)))))
     "acquired manifest content is incomplete or ambiguous"]
    [(not (= (length artifact-handles) (length expected-artifacts)))
     "acquired artifact set differs from the confirmed manifest"]
    [(for/or ([artifact (in-list expected-artifacts)])
       (not
        (for/or ([handle (in-list artifact-handles)])
          (and (string=? (odra-package-artifact-digest artifact)
                         (odra-package-content-handle-digest handle))
               (= (odra-package-artifact-size artifact)
                  (odra-package-content-handle-size handle))
               (eq? (odra-package-artifact-kind artifact)
                    (odra-package-content-handle-kind handle))))))
     "acquired artifact metadata differs from the confirmed manifest"]
    [(for/or ([handle (in-list handles)])
       (not (verified-file?
             (odra-package-content-handle-path handle)
             (odra-package-content-handle-digest handle)
             (odra-package-content-handle-size handle))))
     "acquired package content is absent or no longer verifies"]
    [else #f]))

(define (state-with-generation state generation
                               #:packages [packages (odra-package-state-packages state)]
                               #:operations [operations (odra-package-state-operations state)]
                               #:quarantine [quarantine (odra-package-state-quarantine state)]
                               #:manifest-bytes
                               [manifest-bytes
                                (odra-package-accounting-manifest-bytes
                                 (odra-package-state-accounting state))]
                               #:artifact-bytes
                               [artifact-bytes
                                (odra-package-accounting-artifact-bytes
                                 (odra-package-state-accounting state))])
  (define lock
    (and (odra-package-state-lock state)
         (package-activation-lock-with-checksum
          (struct-copy
           odra-package-activation-lock (odra-package-state-lock state)
           [state-generation generation]
           [checksum (make-string 64 #\0)]))))
  (package-state-with-checksum
   (struct-copy
    odra-package-state state
    [generation generation]
    [lock lock]
    [packages packages]
    [operations operations]
    [quarantine quarantine]
    [accounting
     (odra-package-accounting
      (length packages)
      (for/sum ([package (in-list packages)])
        (length (odra-installed-package-artifacts package)))
      manifest-bytes artifact-bytes (length quarantine))]
    [checksum (make-string 64 #\0)])))

(define (publication-failure package-id detail state)
  (odra-package-installation-failure 'publication package-id detail state))

(define (publish-state root package-id state)
  (define published ((current-package-installation-persist) root state))
  (if (odra-record-publication? published)
      #f
      (publication-failure
       package-id
       (if (odra-record-publication-failure? published)
           (odra-record-publication-failure-message published)
           "package state publication failed")
       state)))

(define (quarantine-candidate root state package-id acquisition detail)
  (define quarantine
    (sort
     (remove-duplicates
      (append (odra-package-state-quarantine state)
              (content-digests acquisition))
      string=?)
     string<?))
  (define quarantined
    (state-with-generation state (add1 (odra-package-state-generation state))
                           #:quarantine quarantine))
  (define failed (publish-state root package-id quarantined))
  (if failed failed
      (odra-package-installation-failure
       'verification package-id detail quarantined)))

(define (dependency-releases manifest)
  (sort
   (for/list ([dependency (in-list (odra-package-manifest-dependencies manifest))]
              #:do
              [(define exact
                 (for/first
                     ([constraint
                       (in-list (odra-package-dependency-constraints dependency))]
                      #:when
                      (eq? 'exact
                           (odra-package-version-constraint-kind constraint)))
                   constraint))]
              #:when exact)
     (odra-package-release
      (odra-package-dependency-id dependency)
      (odra-package-version-constraint-version exact)))
   string<? #:key
   (lambda (release)
     (format "~a@~a" (odra-package-release-id release)
             (odra-package-release-version release)))))

(define (installed-record candidate acquisition)
  (define manifest (odra-package-installation-candidate-manifest candidate))
  (define archive (odra-package-installation-candidate-artifact candidate))
  (define compatibility
    (odra-package-manifest-state-compatibility manifest))
  (odra-installed-package
   (odra-package-manifest-package-id manifest)
   (odra-package-manifest-kind manifest)
   (odra-package-manifest-version manifest)
   1
   (odra-package-installation-candidate-manifest-digest candidate)
   (odra-package-acquisition-archive-digest acquisition)
   (sort
    (for/list ([handle (in-list (odra-package-acquisition-content acquisition))]
               #:unless (eq? 'manifest (odra-package-content-handle-kind handle)))
      (odra-package-content-handle-digest handle))
    string<?)
   (dependency-releases manifest)
   (odra-package-installation-candidate-provenance candidate)
   (odra-package-artifact-reference-platform archive)
   (odra-package-artifact-reference-architecture archive)
   (odra-package-manifest-authorities manifest)
   '() "" 'installed-disabled 0 #f #f
   (eq? 'catalog
        (odra-package-provenance-kind
         (odra-package-installation-candidate-provenance candidate)))
   (odra-package-state-compatibility-schema-id compatibility)
   ""))

(define (same-installation? installed candidate acquisition)
  (and (string=? (odra-installed-package-manifest installed)
                 (odra-package-installation-candidate-manifest-digest candidate))
       (equal? (odra-installed-package-archive installed)
               (odra-package-acquisition-archive-digest acquisition))
       (eq? (odra-installed-package-lifecycle installed) 'installed-disabled)))

(define (install-package-candidate!
         root current candidate acquisition
         #:operation-id [operation-id "package-install"])
  (define state (or current (empty-state)))
  (define manifest (odra-package-installation-candidate-manifest candidate))
  (define package-id (odra-package-manifest-package-id manifest))
  (define version (odra-package-manifest-version manifest))
  (define existing (package-state-find state package-id version))
  (cond
    [(and existing (same-installation? existing candidate acquisition))
     (odra-package-installation-result state existing #t #f)]
    [existing
     (quarantine-candidate
      root state package-id acquisition
      "the package identity and version already name different immutable content")]
    [else
     (define rejected (acquisition-rejection candidate acquisition))
     (cond
       [rejected
        (quarantine-candidate root state package-id acquisition rejected)]
       [else
        (define release (odra-package-release package-id version))
        (define journal
          (odra-package-operation
           operation-id 'install 'durable-install
           (odra-package-state-generation state)
           (odra-package-state-confirmed-lock-generation state)
           (list release) (content-digests acquisition) '()
           'pending #f ""))
        (define journaled
          (state-with-generation
           state (add1 (odra-package-state-generation state))
           #:operations (list journal)))
        (define journal-failure (publish-state root package-id journaled))
        (cond
          [journal-failure journal-failure]
          [else
           (define installed (installed-record candidate acquisition))
           (define packages
             (sort (cons installed (odra-package-state-packages state))
                   string<? #:key package-key))
           (define committed
             (state-with-generation
              journaled (add1 (odra-package-state-generation journaled))
              #:packages packages #:operations '()
              #:manifest-bytes
              (+ (odra-package-accounting-manifest-bytes
                  (odra-package-state-accounting state))
                 (bytes-length (package-manifest->canonical-bytes manifest)))
              #:artifact-bytes
              (+ (odra-package-accounting-artifact-bytes
                  (odra-package-state-accounting state))
                 (for/sum
                     ([handle
                       (in-list (odra-package-acquisition-content acquisition))]
                      #:unless
                      (eq? 'manifest (odra-package-content-handle-kind handle)))
                   (odra-package-content-handle-size handle)))))
           (define commit-failure (publish-state root package-id committed))
           (if commit-failure
               (struct-copy odra-package-installation-failure commit-failure
                            [state journaled])
               (odra-package-installation-result
                committed installed #f #f))])])]))

(define (recover-package-installations! root state)
  (define pending
    (filter (lambda (operation)
              (and (eq? 'install (odra-package-operation-kind operation))
                   (eq? 'pending (odra-package-operation-result operation))))
            (odra-package-state-operations state)))
  (cond
    [(null? pending)
     (odra-package-installation-result state #f #t #f)]
    [else
     (define retained
       (filter (lambda (operation)
                 (not (memq operation pending)))
               (odra-package-state-operations state)))
     (define recovered
       (state-with-generation
        state (add1 (odra-package-state-generation state))
        #:operations retained))
     (define package-id
       (odra-package-release-id
        (car (odra-package-operation-package-releases (car pending)))))
     (define failed (publish-state root package-id recovered))
     (if failed failed
         (odra-package-installation-result recovered #f #f #t))]))

(module+ test-support
  (provide current-package-installation-persist))
