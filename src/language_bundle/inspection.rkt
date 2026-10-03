#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/match
         "activation-runtime.rkt"
         "state-records.rkt")

(provide
 (struct-out odra-language-bundle-inspection-record)
 (struct-out odra-language-bundle-doctor-issue)
 (struct-out odra-language-bundle-resource-evidence)
 (struct-out odra-language-bundle-inspection)
 (contract-out
  [language-bundle-inspect
   (->* (odra-language-bundle-state?)
        ((or/c #f odra-bundle-runtime-snapshot?)
         #:safe-mode? boolean?
         #:runtime-failure string?)
        odra-language-bundle-inspection?)]
  [language-bundle-inspection-find
   (->* (odra-language-bundle-inspection? string?)
        ((or/c #f string?))
        (or/c #f odra-language-bundle-inspection-record?))]
  [language-bundle-inspection-doctor
   (-> odra-language-bundle-inspection?
       (listof odra-language-bundle-doctor-issue?))]
  [language-bundle-inspection-lines
   (->* (odra-language-bundle-inspection?)
        (#:kind (or/c 'support 'bundle 'doctor))
        (listof string?))]))

(define maximum-identity-bytes 128)
(define maximum-detail-bytes 4096)
(define maximum-inspection-lines 4096)
(define healthy-statuses '(available removed))

(define (bounded-text? value maximum #:empty? [empty? #f])
  (and (string? value)
       (or empty? (positive? (string-length value)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)
       (not (for/or ([character (in-string value)]) (char=? character #\nul)))))

(define (copied value)
  (if (string? value) (string->immutable-string value) value))

(struct odra-language-bundle-inspection-record
  (id version source publisher lifecycle active? contribution-generation
      predecessor pinned? authorities authority-provenance artifacts dependencies
      contribution-statuses)
  #:transparent
  #:guard
  (lambda (id version source publisher lifecycle active? contribution-generation
              predecessor pinned? authorities authority-provenance artifacts dependencies
              contribution-statuses _)
    (unless (and (bounded-text? id maximum-identity-bytes)
                 (bounded-text? version maximum-identity-bytes)
                 (bounded-text? source maximum-identity-bytes)
                 (bounded-text? publisher maximum-identity-bytes)
                 (symbol? lifecycle) (boolean? active?)
                 (exact-nonnegative-integer? contribution-generation)
                 (or (not predecessor) (bounded-text? predecessor maximum-identity-bytes))
                 (boolean? pinned?) (list? authorities) (andmap string? authorities)
                 (bounded-text? authority-provenance maximum-detail-bytes #:empty? #t)
                 (list? artifacts) (andmap string? artifacts)
                 (list? dependencies) (andmap string? dependencies)
                 (list? contribution-statuses)
                 (andmap (lambda (entry)
                           (and (list? entry) (= (length entry) 4)
                                (symbol? (car entry)) (symbol? (cadr entry))
                                (symbol? (caddr entry)) (string? (cadddr entry))))
                         contribution-statuses))
      (raise-arguments-error
       'odra-language-bundle-inspection-record "invalid copied bundle inspection"))
    (values (copied id) (copied version) (copied source) (copied publisher)
            lifecycle active? contribution-generation
            (and predecessor (copied predecessor)) pinned?
            (map copied authorities) (copied authority-provenance)
            (map copied artifacts) (map copied dependencies)
            (for/list ([entry contribution-statuses])
              (list (car entry) (cadr entry) (caddr entry) (copied (cadddr entry)))))))

(struct odra-language-bundle-doctor-issue
  (severity area code bundle-id version detail recovery evidence-generation
            resource-limit resource-actual)
  #:transparent
  #:guard
  (lambda (severity area code bundle-id version detail recovery evidence-generation
                    resource-limit resource-actual _)
    (unless (and (memq severity '(information warning error))
                 (symbol? area) (symbol? code)
                 (bounded-text? bundle-id maximum-identity-bytes #:empty? #t)
                 (bounded-text? version maximum-identity-bytes #:empty? #t)
                 (bounded-text? detail maximum-detail-bytes)
                 (bounded-text? recovery maximum-detail-bytes)
                 (exact-nonnegative-integer? evidence-generation)
                 (exact-nonnegative-integer? resource-limit)
                 (exact-nonnegative-integer? resource-actual))
      (raise-arguments-error 'odra-language-bundle-doctor-issue
                             "invalid actionable doctor issue"))
    (values severity area code (copied bundle-id) (copied version)
            (copied detail) (copied recovery) evidence-generation
            resource-limit resource-actual)))

(struct odra-language-bundle-resource-evidence
  (bundle-count artifact-count manifest-bytes artifact-bytes quarantine-count)
  #:transparent)

(struct odra-language-bundle-inspection
  (state-generation lock-generation runtime-generation safe-mode? bundles issues resources)
  #:transparent)

(define (runtime-statuses-by-bundle runtime)
  (define result (make-hash))
  (when runtime
    (for ([entry (in-list
                  (append
                   (hash-values (odra-bundle-runtime-snapshot-effective runtime))
                   (hash-values (odra-bundle-runtime-snapshot-shadowed runtime))))])
      (hash-update!
       result
       (odra-bundle-runtime-entry-bundle-id entry)
       (lambda (values)
         (cons (list (odra-bundle-runtime-entry-kind entry)
                     (odra-bundle-runtime-entry-identity entry)
                     (odra-bundle-runtime-entry-status entry)
                     (format "source=~a generation=~a"
                             (odra-bundle-runtime-entry-source entry)
                             (odra-bundle-runtime-entry-contribution-generation entry)))
               values))
       '())))
  result)

(define (active-bundle? state id version runtime)
  (define lock (odra-language-bundle-state-lock state))
  (and runtime
       lock
       (equal? (hash-ref (odra-activation-lock-bundles lock) id #f) version)
       (equal? (hash-ref (odra-bundle-runtime-snapshot-bundles runtime) id #f)
               version)))

(define (record-from-installed state runtime statuses installed)
  (define id (odra-installed-bundle-id installed))
  (odra-language-bundle-inspection-record
   id
   (odra-installed-bundle-version installed)
   (odra-installed-bundle-source installed)
   (odra-installed-bundle-publisher installed)
   (odra-installed-bundle-lifecycle installed)
   (and (active-bundle? state id (odra-installed-bundle-version installed) runtime) #t)
   (odra-installed-bundle-contribution-generation installed)
   (odra-installed-bundle-predecessor installed)
   (odra-installed-bundle-pinned? installed)
   (odra-installed-bundle-authorities installed)
   (odra-installed-bundle-authority-provenance installed)
   (odra-installed-bundle-artifacts installed)
   (odra-installed-bundle-dependencies installed)
   (reverse (hash-ref statuses id '()))))

(define (issue severity area code id version detail recovery generation
               [limit 0] [actual 0])
  (odra-language-bundle-doctor-issue
   severity area code (or id "") (or version "") detail recovery generation limit actual))

(define (lifecycle-issue record generation)
  (define lifecycle (odra-language-bundle-inspection-record-lifecycle record))
  (define id (odra-language-bundle-inspection-record-id record))
  (define version (odra-language-bundle-inspection-record-version record))
  (case lifecycle
    [(installed-disabled)
     (issue 'information 'bundle 'disabled id version
            "The bundle is installed but disabled."
            (format "Run language-bundle-enable and select ~a@~a." id version)
            generation)]
    [(staged verified enabled-pending update-pending removal-pending)
     (issue 'warning 'bundle 'interrupted id version
            (format "The bundle remains in lifecycle state ~a." lifecycle)
            "Restart Odra to reconcile the interrupted lifecycle operation, then run language-support-doctor again."
            generation)]
    [(activation-rejected)
     (issue 'error 'bundle 'activation-rejected id version
            "The candidate could not replace the confirmed contribution generation."
            (format "Inspect ~a@~a with describe-language-bundle, then retry language-bundle-enable or run language-bundle-rollback." id version)
            generation)]
    [(rollback-available)
     (issue 'information 'bundle 'rollback-available id version
            "A retained predecessor is available."
            (format "Run language-bundle-rollback and select ~a only when the active version must be replaced." id)
            generation)]
    [(quarantined)
     (issue 'error 'trust 'quarantined id version
            "The installed record or one referenced artifact failed integrity admission."
            (format "Inspect ~a@~a, restore a trusted artifact, then reinstall or remove the bundle." id version)
            generation)]
    [else #f]))

(define (contribution-issues record generation)
  (for/list ([entry (in-list
                     (odra-language-bundle-inspection-record-contribution-statuses record))]
             #:unless (memq (caddr entry) healthy-statuses))
    (define status (caddr entry))
    (define id (odra-language-bundle-inspection-record-id record))
    (define version (odra-language-bundle-inspection-record-version record))
    (issue
     (if (eq? status 'failed) 'error 'warning)
     (car entry)
     (string->symbol (format "contribution-~a" status))
     id version
     (format "Contribution ~a/~a is ~a; ~a"
             (car entry) (cadr entry) status (cadddr entry))
     (case status
       [(disabled) (format "Run language-bundle-enable and select ~a@~a." id version)]
       [(unsupported) "Install a bundle version compatible with this Odra API and platform."]
       [(untrusted) "Review the requested authorities and install only from a trusted source."]
       [else (format "Run describe-language-bundle for ~a@~a, then disable or roll back the failing version." id version)])
     generation)))

(define (operation-issues state)
  (for/list ([operation (in-list (odra-language-bundle-state-operations state))]
             #:unless (and (eq? (odra-bundle-operation-phase operation) 'complete)
                           (odra-bundle-operation-cleanup-complete? operation)))
    (define failed? (or (eq? (odra-bundle-operation-phase operation) 'failed)
                        (positive? (string-length (odra-bundle-operation-failure operation)))))
    (issue
     (if failed? 'error 'warning)
     'operation
     (if failed? 'operation-failed 'operation-incomplete)
     (odra-bundle-operation-id operation) ""
     (format "Bundle operation ~a is in phase ~a with result ~a; failure=~s."
             (odra-bundle-operation-kind operation)
             (odra-bundle-operation-phase operation)
             (odra-bundle-operation-result operation)
             (odra-bundle-operation-failure operation))
     "Restart Odra for idempotent reconciliation, then rerun language-support-doctor before retrying the operation."
     (odra-language-bundle-state-generation state))))

(define (language-bundle-inspect state [runtime #f]
                                 #:safe-mode? [safe-mode? #f]
                                 #:runtime-failure [runtime-failure ""])
  (define statuses (runtime-statuses-by-bundle runtime))
  (define records
    (for/list ([installed (in-list (odra-language-bundle-state-bundles state))])
      (record-from-installed state runtime statuses installed)))
  (define generation (odra-language-bundle-state-generation state))
  (define issues
    (append
     (filter values (map (lambda (record) (lifecycle-issue record generation)) records))
     (append-map (lambda (record) (contribution-issues record generation)) records)
     (operation-issues state)
     (for/list ([reference (in-list (odra-language-bundle-state-quarantine state))])
       (issue 'error 'trust 'quarantine-reference reference ""
              "A quarantined record is excluded from activation."
              "Run describe-language-bundle, restore trusted content, then reinstall or remove the quarantined bundle."
              generation))
     (if (and (odra-language-bundle-state-lock state) (not runtime) (not safe-mode?))
         (list
          (issue 'error 'runtime 'runtime-unavailable "" ""
                 "The confirmed activation lock has no active runtime snapshot."
                 "Restart Odra to restore the last confirmed generation, or start in safe mode and disable the failing bundle."
                 generation))
         '())
     (if (positive? (string-length runtime-failure))
         (list
          (issue 'error 'runtime 'runtime-failed "" "" runtime-failure
                 "Start in safe mode, inspect installed bundles, then disable or roll back the failing bundle."
                 generation))
         '())))
  (define accounting (odra-language-bundle-state-accounting state))
  (odra-language-bundle-inspection
   generation
   (odra-language-bundle-state-confirmed-lock-generation state)
   (if runtime (odra-bundle-runtime-snapshot-runtime-generation runtime) 0)
   safe-mode?
   records
   issues
   (odra-language-bundle-resource-evidence
    (odra-bundle-accounting-bundle-count accounting)
    (odra-bundle-accounting-artifact-count accounting)
    (odra-bundle-accounting-manifest-bytes accounting)
    (odra-bundle-accounting-artifact-bytes accounting)
    (odra-bundle-accounting-quarantine-count accounting))))

(define (language-bundle-inspection-find inspection id [version #f])
  (for/first ([record (in-list (odra-language-bundle-inspection-bundles inspection))]
              #:when (and (string=? id (odra-language-bundle-inspection-record-id record))
                          (or (not version)
                              (string=? version
                                        (odra-language-bundle-inspection-record-version record)))))
    record))

(define (language-bundle-inspection-doctor inspection)
  (odra-language-bundle-inspection-issues inspection))

(define (record-line record)
  (format
   "Bundle ~a@~a: lifecycle=~a active=~a source=~a publisher=~a contribution-generation=~a predecessor=~a pinned=~a authorities=~a artifacts=~a dependencies=~a"
   (odra-language-bundle-inspection-record-id record)
   (odra-language-bundle-inspection-record-version record)
   (odra-language-bundle-inspection-record-lifecycle record)
   (odra-language-bundle-inspection-record-active? record)
   (odra-language-bundle-inspection-record-source record)
   (odra-language-bundle-inspection-record-publisher record)
   (odra-language-bundle-inspection-record-contribution-generation record)
   (or (odra-language-bundle-inspection-record-predecessor record) 'none)
   (odra-language-bundle-inspection-record-pinned? record)
   (odra-language-bundle-inspection-record-authorities record)
   (length (odra-language-bundle-inspection-record-artifacts record))
   (odra-language-bundle-inspection-record-dependencies record)))

(define (issue-line value)
  (format
   "Doctor ~a/~a: bundle=~a version=~a detail=~a recovery=~a evidence-generation=~a resource=~a/~a"
   (odra-language-bundle-doctor-issue-severity value)
   (odra-language-bundle-doctor-issue-code value)
   (odra-language-bundle-doctor-issue-bundle-id value)
   (odra-language-bundle-doctor-issue-version value)
   (odra-language-bundle-doctor-issue-detail value)
   (odra-language-bundle-doctor-issue-recovery value)
   (odra-language-bundle-doctor-issue-evidence-generation value)
   (odra-language-bundle-doctor-issue-resource-actual value)
   (odra-language-bundle-doctor-issue-resource-limit value)))

(define (language-bundle-inspection-lines inspection #:kind [kind 'support])
  (define resources (odra-language-bundle-inspection-resources inspection))
  (define summary
    (format
     "Language bundles: state-generation=~a lock-generation=~a runtime-generation=~a safe-mode=~a bundles=~a artifacts=~a manifest-bytes=~a artifact-bytes=~a quarantine=~a"
     (odra-language-bundle-inspection-state-generation inspection)
     (odra-language-bundle-inspection-lock-generation inspection)
     (odra-language-bundle-inspection-runtime-generation inspection)
     (odra-language-bundle-inspection-safe-mode? inspection)
     (odra-language-bundle-resource-evidence-bundle-count resources)
     (odra-language-bundle-resource-evidence-artifact-count resources)
     (odra-language-bundle-resource-evidence-manifest-bytes resources)
     (odra-language-bundle-resource-evidence-artifact-bytes resources)
     (odra-language-bundle-resource-evidence-quarantine-count resources)))
  (define bundle-lines
    (map record-line (odra-language-bundle-inspection-bundles inspection)))
  (define doctor-lines
    (if (null? (odra-language-bundle-inspection-issues inspection))
        (list "Language support doctor: no bundle lifecycle, trust, runtime, or resource issue is recorded.")
        (map issue-line (odra-language-bundle-inspection-issues inspection))))
  (define lines
    (case kind
      [(bundle) (cons summary bundle-lines)]
      [(doctor) (cons summary doctor-lines)]
      [else (append (list summary) bundle-lines doctor-lines)]))
  (if (> (length lines) maximum-inspection-lines)
      (take lines maximum-inspection-lines)
      lines))

(module+ test
  (require rackunit)

  (define zero-digest (make-string 64 #\0))
  (define one-digest (make-string 64 #\1))
  (define active
    (odra-installed-bundle
     "factory.odin" "1.0.0" zero-digest (list one-digest) '()
     "factory" "odra" 'linux 'x86-64 '("native-grammar")
     "factory authority" 'active-confirmed 11 #f #f))
  (define disabled
    (odra-installed-bundle
     "third.rust" "2.0.0" one-digest '() '()
     "package" "example" 'linux 'x86-64 '("external-process")
     "catalog authority" 'installed-disabled 0 #f #f))
  (define lock
    (odra-activation-lock
     7 9 (hash "factory.odin" "1.0.0") (list one-digest)
     zero-digest one-digest (hash "factory.odin" 11) zero-digest))
  (define failed-operation
    (odra-bundle-operation
     "install.third-rust" 'install 'failed 8 7 '() '()
     'rejected #t "artifact digest mismatch"))
  (define state
    (odra-language-bundle-state
     2 "default" 9 7 (list active disabled) lock #f
     (list failed-operation) (list "quarantine.third-rust")
     (odra-bundle-accounting 2 1 512 1024 1) zero-digest))
  (define runtime
    (odra-bundle-runtime-snapshot
     3 7 9 (hash "factory.odin" "1.0.0")
     (odra-bundle-registry-generations 1 2 3 4 5 6 7 8 9)
     (hash
      '(language . odin)
      (odra-bundle-runtime-entry
       'language 'odin "factory.odin" 'factory 11 'available 'odin)
      '(service . ols)
      (odra-bundle-runtime-entry
       'service 'ols "factory.odin" 'factory 11 'failed 'ols))
     (hash) '() (list "factory.odin")))

  (test-case "inspection copies exact state and runtime evidence"
    (define inspection (language-bundle-inspect state runtime))
    (check-equal? (odra-language-bundle-inspection-state-generation inspection) 9)
    (check-equal? (odra-language-bundle-inspection-runtime-generation inspection) 3)
    (define odin (language-bundle-inspection-find inspection "factory.odin"))
    (check-true (odra-language-bundle-inspection-record-active? odin))
    (check-equal? (length (odra-language-bundle-inspection-record-contribution-statuses odin)) 2)
    (define rust (language-bundle-inspection-find inspection "third.rust" "2.0.0"))
    (check-equal? (odra-language-bundle-inspection-record-lifecycle rust)
                  'installed-disabled))

  (test-case "doctor reports exact recovery and failure evidence"
    (define inspection (language-bundle-inspect state runtime))
    (define issues (language-bundle-inspection-doctor inspection))
    (define codes (map odra-language-bundle-doctor-issue-code issues))
    (check-not-false (member 'disabled codes))
    (check-not-false (member 'contribution-failed codes))
    (check-not-false (member 'operation-failed codes))
    (check-not-false (member 'quarantine-reference codes))
    (for ([entry (in-list issues)])
      (check-true
       (positive? (string-length
                   (odra-language-bundle-doctor-issue-recovery entry))))))

  (test-case "safe mode remains inspectable without extension runtime"
    (define inspection
      (language-bundle-inspect state #f #:safe-mode? #t
                               #:runtime-failure "Installed extension entrypoint failed"))
    (check-true (odra-language-bundle-inspection-safe-mode? inspection))
    (check-false
     (odra-language-bundle-inspection-record-active?
      (language-bundle-inspection-find inspection "factory.odin")))
    (define codes
      (map odra-language-bundle-doctor-issue-code
           (language-bundle-inspection-doctor inspection)))
    (check-false (member 'runtime-unavailable codes))
    (check-not-false (member 'runtime-failed codes)))

  (test-case "inspection lines expose actions and resource totals"
    (define lines
      (language-bundle-inspection-lines
       (language-bundle-inspect state runtime)
       #:kind 'doctor))
    (check-true (regexp-match? #rx"artifact-bytes=1024" (car lines)))
    (check-true (for/and ([line (in-list (cdr lines))])
                  (regexp-match? #rx"recovery=" line)))))
