#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require json
         (except-in openssl/sha1 sha1)
         (only-in file/sha1 bytes->hex-string)
         racket/file
         racket/list
         racket/path
         racket/string
         "publication-identity.rkt")

(provide candidate-store-schema
         (struct-out retention-policy)
         (struct-out candidate-store)
         (struct-out phase-start-result)
         default-retention-policy
         open-candidate-store
         initialize-candidate!
         read-candidate-state
         candidate-phase-reusable?
         candidate-first-incomplete-phase
         candidate-artifact-path
         retain-candidate-artifact!
         start-candidate-phase!
         finish-candidate-phase!)

(define candidate-store-schema 1)

(struct retention-policy
  (maximum-candidates maximum-attempts maximum-artifacts maximum-bytes)
  #:transparent)

(struct candidate-store (root policy) #:transparent)
(struct phase-start-result (state disposition attempt) #:transparent)

(define default-retention-policy
  (retention-policy 3 16 32 (* 8 1024 1024 1024)))

(define digest-pattern #px"^[0-9a-f]{64}$")
(define semver-pattern
  #px"^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")
(define timestamp-pattern
  #px"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\\.[0-9]+)?(?:Z|[+-][0-9]{2}:[0-9]{2})$")
(define sensitive-key-pattern
  #px"(?i:token|secret|authorization|credential|password|private[_-]?key)")
(define credential-url-pattern
  #px"^[a-z][a-z0-9+.-]*://[^/@[:space:]]+@")
(define token-query-pattern
  #px"(?i:[?&](?:access_token|token|key|signature|sig)=)")
(define credential-assignment-pattern
  #px"(?i:(?:token|secret|authorization|credential|password|private[_-]?key)[[:space:]]*[:=][[:space:]]*[^[:space:]]+)")

(define (digest? value)
  (and (string? value) (regexp-match? digest-pattern value)))

(define (timestamp? value)
  (and (string? value) (regexp-match? timestamp-pattern value)))

(define (retention-policy-errors policy)
  (for/list ([entry (in-list
                     (list
                      (cons 'maximum-candidates
                            (retention-policy-maximum-candidates policy))
                      (cons 'maximum-attempts
                            (retention-policy-maximum-attempts policy))
                      (cons 'maximum-artifacts
                            (retention-policy-maximum-artifacts policy))
                      (cons 'maximum-bytes
                            (retention-policy-maximum-bytes policy))))]
             #:unless (exact-positive-integer? (cdr entry)))
    (format "~a must be a positive integer" (car entry))))

(define (persistable-value? value)
  (cond
    [(hash? value)
     (for/and ([(key child) (in-hash value)])
       (and (not (regexp-match? sensitive-key-pattern
                                (if (symbol? key)
                                    (symbol->string key)
                                    key)))
            (persistable-value? child)))]
    [(list? value) (andmap persistable-value? value)]
    [(string? value)
     (and (not (regexp-match? credential-url-pattern value))
          (not (regexp-match? token-query-pattern value))
          (not (regexp-match? #px"[[:cntrl:]]" value)))]
    [else #t]))

(define (candidate-directory store candidate-id)
  (unless (digest? candidate-id)
    (raise-argument-error 'candidate-directory
                          "lowercase SHA-256 digest"
                          candidate-id))
  (build-path (candidate-store-root store) candidate-id))

(define (candidate-state-path store candidate-id)
  (build-path (candidate-directory store candidate-id) "state.json"))

(define (candidate-artifact-path store candidate-id artifact)
  (unless (artifact-identity-valid? artifact)
    (raise-arguments-error 'candidate-artifact-path
                           "invalid artifact identity"
                           "errors" (artifact-identity-errors artifact)))
  (define relative (artifact-identity-relative-path artifact))
  (unless (string-prefix? relative "artifacts/")
    (raise-user-error 'candidate-artifact-path
                      "retained artifact path must begin with artifacts/"))
  (build-path (candidate-directory store candidate-id) relative))

(define (candidate-directories store)
  (for/list ([entry (in-list (directory-list (candidate-store-root store)))]
             #:when (and (digest? (path->string entry))
                         (directory-exists?
                          (build-path (candidate-store-root store) entry))))
    entry))

(define (open-candidate-store root [policy default-retention-policy])
  (define errors (retention-policy-errors policy))
  (unless (null? errors)
    (raise-arguments-error 'open-candidate-store
                           "invalid retention policy"
                           "errors" errors))
  (define complete-root (path->complete-path root))
  (make-directory* complete-root)
  (file-or-directory-permissions complete-root #o700)
  (candidate-store complete-root policy))

(define (artifact-jsexpr->identity value)
  (artifact-identity
   (hash-ref value 'name #f)
   (hash-ref value 'media_type #f)
   (hash-ref value 'byte_size #f)
   (hash-ref value 'sha256 #f)
   (string->symbol (hash-ref value 'phase "invalid"))
   (hash-ref value 'path #f)))

(define (phase-jsexpr->record value)
  (phase-record
   (string->symbol (hash-ref value 'phase "invalid"))
   (string->symbol (hash-ref value 'state "invalid"))
   (hash-ref value 'input_sha256 #f)
   (hash-ref value 'attempt #f)
   (hash-ref value 'started_at #f)
   (hash-ref value 'finished_at #f)
   (for/list ([artifact (in-list (hash-ref value 'evidence '()))])
     (artifact-jsexpr->identity artifact))
   (hash-ref value 'failure #f)))

(define (phase-entry-valid? value)
  (and (hash? value)
       (member (string->symbol (hash-ref value 'phase "invalid"))
               publication-phases)
       (list? (hash-ref value 'attempts #f))
       (let ([records
              (for/list ([attempt (in-list (hash-ref value 'attempts))])
                (phase-jsexpr->record attempt))])
         (and (andmap phase-record-valid? records)
              (equal? (map phase-record-attempt records)
                      (range 1 (add1 (length records))))
              (andmap
               (lambda (record)
                 (eq? (phase-record-phase record)
                      (string->symbol (hash-ref value 'phase))))
               records)))))

(define (candidate-state-valid? state)
  (and (hash? state)
       (equal? (hash-ref state 'schema #f) candidate-store-schema)
       (equal? (hash-ref state 'model #f) "odra-release-candidate-state")
       (digest? (hash-ref state 'candidate_id #f))
       (and (string? (hash-ref state 'version #f))
            (regexp-match? semver-pattern (hash-ref state 'version)))
       (digest? (hash-ref state 'request_sha256 #f))
       (timestamp? (hash-ref state 'created_at #f))
       (timestamp? (hash-ref state 'updated_at #f))
       (list? (hash-ref state 'phases #f))
       (andmap phase-entry-valid? (hash-ref state 'phases))
       (= (length (hash-ref state 'phases))
          (length (remove-duplicates
                   (map (lambda (entry) (hash-ref entry 'phase))
                        (hash-ref state 'phases)))))
       (list? (hash-ref state 'artifacts #f))
       (andmap artifact-identity-valid?
               (map artifact-jsexpr->identity
                    (hash-ref state 'artifacts)))
       (persistable-value? state)))

(define (write-candidate-state! store state)
  (unless (candidate-state-valid? state)
    (raise-arguments-error 'write-candidate-state!
                           "invalid or unsafe candidate state"
                           "state" state))
  (define candidate-id (hash-ref state 'candidate_id))
  (define directory (candidate-directory store candidate-id))
  (make-directory* directory)
  (file-or-directory-permissions directory #o700)
  (define temporary
    (make-temporary-file "state-~a.json" #f directory))
  (call-with-output-file temporary
    #:exists 'truncate/replace
    (lambda (output)
      (write-bytes (canonical-json-bytes state) output)
      (newline output)))
  (file-or-directory-permissions temporary #o600)
  (rename-file-or-directory temporary
                            (candidate-state-path store candidate-id)
                            #t)
  state)

(define (read-candidate-state store candidate-id)
  (define path (candidate-state-path store candidate-id))
  (unless (file-exists? path)
    (raise-user-error 'read-candidate-state
                      "candidate state is unavailable: ~a"
                      candidate-id))
  (define state (call-with-input-file path read-json))
  (unless (and (candidate-state-valid? state)
               (equal? (hash-ref state 'candidate_id) candidate-id))
    (raise-user-error 'read-candidate-state
                      "candidate state is invalid: ~a"
                      candidate-id))
  state)

(define (initialize-candidate!
         store candidate-id version request-sha256 observed-at)
  (unless (and (digest? candidate-id)
               (string? version)
               (regexp-match? semver-pattern version)
               (digest? request-sha256)
               (timestamp? observed-at))
    (raise-arguments-error 'initialize-candidate!
                           "invalid candidate identity"))
  (define path (candidate-state-path store candidate-id))
  (cond
    [(file-exists? path)
     (define state (read-candidate-state store candidate-id))
     (unless (and (equal? (hash-ref state 'version) version)
                  (equal? (hash-ref state 'request_sha256) request-sha256))
       (raise-user-error 'initialize-candidate!
                         "candidate identity conflicts with retained state"))
     state]
    [else
     (when (>= (length (candidate-directories store))
               (retention-policy-maximum-candidates
                (candidate-store-policy store)))
       (raise-user-error 'initialize-candidate!
                         "candidate retention limit reached"))
     (write-candidate-state!
      store
      (hasheq 'schema candidate-store-schema
              'model "odra-release-candidate-state"
              'candidate_id candidate-id
              'version version
              'request_sha256 request-sha256
              'created_at observed-at
              'updated_at observed-at
              'phases '()
              'artifacts '()))]))

(define (phase-entry state phase)
  (findf (lambda (entry)
           (string=? (hash-ref entry 'phase) (symbol->string phase)))
         (hash-ref state 'phases)))

(define (artifact-entry state name)
  (findf (lambda (entry) (string=? (hash-ref entry 'name) name))
         (hash-ref state 'artifacts)))

(define (sha256-file path)
  (call-with-input-file path
    (lambda (input) (bytes->hex-string (sha256-bytes input)))))

(define (textual-media-type? media-type)
  (or (string-prefix? media-type "text/")
      (member media-type
              '("application/json" "application/xml" "application/yaml"))))

(define (text-artifact-contains-credential? path)
  (call-with-input-file path
    (lambda (input)
      (for/or ([line (in-lines input)])
        (or (regexp-match? credential-url-pattern line)
            (regexp-match? token-query-pattern line)
            (regexp-match? credential-assignment-pattern line))))))

(define (retained-byte-size state)
  (for/sum ([entry (in-list (hash-ref state 'artifacts))])
    (hash-ref entry 'byte_size)))

(define (retain-candidate-artifact! store candidate-id source artifact)
  (unless (artifact-identity-valid? artifact)
    (raise-arguments-error 'retain-candidate-artifact!
                           "invalid artifact identity"
                           "errors" (artifact-identity-errors artifact)))
  (define source-path (path->complete-path source))
  (unless (and (file-exists? source-path)
               (not (link-exists? source-path)))
    (raise-user-error 'retain-candidate-artifact!
                      "artifact source must be a regular file"))
  (define actual-size (file-size source-path))
  (define actual-sha256 (sha256-file source-path))
  (unless (and (= actual-size (artifact-identity-byte-size artifact))
               (string=? actual-sha256
                         (artifact-identity-sha256 artifact)))
    (raise-user-error 'retain-candidate-artifact!
                      "artifact source differs from its declared identity"))
  (when (and (textual-media-type? (artifact-identity-media-type artifact))
             (text-artifact-contains-credential? source-path))
    (raise-user-error 'retain-candidate-artifact!
                      "text artifact contains credential material"))
  (define state (read-candidate-state store candidate-id))
  (define serialized (artifact-identity->jsexpr artifact))
  (define existing (artifact-entry state (artifact-identity-name artifact)))
  (when (and existing (not (equal? existing serialized)))
    (raise-user-error 'retain-candidate-artifact!
                      "artifact name conflicts with retained identity"))
  (define path-conflict
    (findf
     (lambda (entry)
       (and (string=? (hash-ref entry 'path)
                      (artifact-identity-relative-path artifact))
            (not (string=? (hash-ref entry 'name)
                           (artifact-identity-name artifact)))))
     (hash-ref state 'artifacts)))
  (when path-conflict
    (raise-user-error 'retain-candidate-artifact!
                      "artifact path conflicts with retained identity"))
  (define destination (candidate-artifact-path store candidate-id artifact))
  (when (and (file-exists? destination)
             (not (and (= (file-size destination) actual-size)
                       (string=? (sha256-file destination) actual-sha256))))
    (raise-user-error 'retain-candidate-artifact!
                      "retained artifact content conflicts with identity"))
  (cond
    [existing
     (unless (file-exists? destination)
       (raise-user-error 'retain-candidate-artifact!
                         "retained artifact state lacks its file"))
     destination]
    [else
     (define policy (candidate-store-policy store))
     (when (>= (length (hash-ref state 'artifacts))
               (retention-policy-maximum-artifacts policy))
       (raise-user-error 'retain-candidate-artifact!
                         "artifact retention count limit reached"))
     (when (> (+ (retained-byte-size state) actual-size)
              (retention-policy-maximum-bytes policy))
       (raise-user-error 'retain-candidate-artifact!
                         "artifact retention byte limit reached"))
     (make-parent-directory* destination)
     (file-or-directory-permissions (path-only destination) #o700)
     (unless (file-exists? destination)
       (define temporary
         (make-temporary-file "artifact-~a" #f (path-only destination)))
       (copy-file source-path temporary #t)
       (file-or-directory-permissions temporary #o600)
       (rename-file-or-directory temporary destination #f))
     (define artifacts
       (sort (cons serialized (hash-ref state 'artifacts))
             string<?
             #:key (lambda (entry) (hash-ref entry 'name))))
     (write-candidate-state! store (hash-set state 'artifacts artifacts))
     destination]))

(define (replace-phase-entry state phase replacement)
  (define remaining
    (filter (lambda (entry)
              (not (string=? (hash-ref entry 'phase)
                             (symbol->string phase))))
            (hash-ref state 'phases)))
  (define ordered
    (sort (cons replacement remaining)
          <
          #:key (lambda (entry)
                  (index-of publication-phases
                            (string->symbol (hash-ref entry 'phase))))))
  (hash-set state 'phases ordered))

(define (latest-phase-record state phase)
  (define entry (phase-entry state phase))
  (and entry
       (pair? (hash-ref entry 'attempts))
       (phase-jsexpr->record (last (hash-ref entry 'attempts)))))

(define (candidate-phase-reusable? state phase input-sha256)
  (unless (and (member phase publication-phases) (digest? input-sha256))
    (raise-arguments-error 'candidate-phase-reusable?
                           "invalid phase identity"))
  (define latest (latest-phase-record state phase))
  (and latest
       (eq? (phase-record-state latest) 'passed)
       (string=? (phase-record-input-sha256 latest) input-sha256)))

(define (expected-phase-input expected-inputs phase)
  (define value
    (cond
      [(hash-has-key? expected-inputs phase) (hash-ref expected-inputs phase)]
      [(hash-has-key? expected-inputs (symbol->string phase))
       (hash-ref expected-inputs (symbol->string phase))]
      [else #f]))
  (unless (digest? value)
    (raise-arguments-error 'candidate-first-incomplete-phase
                           "every phase requires a complete input digest"
                           "phase" phase
                           "input" value))
  value)

(define (candidate-first-incomplete-phase state expected-inputs)
  (unless (and (candidate-state-valid? state) (hash? expected-inputs))
    (raise-arguments-error 'candidate-first-incomplete-phase
                           "invalid candidate state or expected inputs"))
  (for/first ([phase (in-list publication-phases)]
              #:unless
              (candidate-phase-reusable?
               state phase (expected-phase-input expected-inputs phase)))
    phase))

(define (interrupted-record record finished-at)
  (struct-copy phase-record
               record
               [state 'failed]
               [finished-at finished-at]
               [failure
                (hasheq 'code "interrupted"
                        'summary
                        "prior attempt did not reach a terminal state")]))

(define (start-candidate-phase!
         store candidate-id phase input-sha256 started-at
         #:restart-running? [restart-running? #f])
  (unless (and (member phase publication-phases)
               (digest? input-sha256)
               (timestamp? started-at))
    (raise-arguments-error 'start-candidate-phase!
                           "invalid phase start"))
  (define state (read-candidate-state store candidate-id))
  (define existing (phase-entry state phase))
  (define attempts (if existing (hash-ref existing 'attempts) '()))
  (define latest
    (and (pair? attempts) (phase-jsexpr->record (last attempts))))
  (cond
    [(and latest
          (eq? (phase-record-state latest) 'passed)
          (string=? (phase-record-input-sha256 latest) input-sha256))
     (phase-start-result state 'reused (phase-record-attempt latest))]
    [(and latest
          (eq? (phase-record-state latest) 'running)
          (not (string=? (phase-record-input-sha256 latest) input-sha256))
          (not restart-running?))
     (raise-user-error 'start-candidate-phase!
                       "running phase input conflicts with retry: ~a"
                       phase)]
    [(and latest
          (eq? (phase-record-state latest) 'running)
          (not restart-running?))
     (phase-start-result state 'running (phase-record-attempt latest))]
    [else
     (define prior-attempts
       (if (and latest
                (eq? (phase-record-state latest) 'running)
                restart-running?)
           (append (drop-right attempts 1)
                   (list (phase-record->jsexpr
                          (interrupted-record latest started-at))))
           attempts))
     (define attempt (add1 (length prior-attempts)))
     (when (> attempt
              (retention-policy-maximum-attempts
               (candidate-store-policy store)))
       (raise-user-error 'start-candidate-phase!
                         "phase attempt retention limit reached: ~a"
                         phase))
     (define record
       (phase-record phase 'running input-sha256 attempt started-at #f '() #f))
     (define updated
       (hash-set
        (replace-phase-entry
         state phase
         (hasheq 'phase (symbol->string phase)
                 'attempts (append prior-attempts
                                   (list (phase-record->jsexpr record)))))
        'updated_at started-at))
     (phase-start-result
      (write-candidate-state! store updated) 'started attempt)]))

(define (finish-candidate-phase!
         store candidate-id phase attempt state finished-at
         #:evidence [evidence '()]
         #:failure [failure #f])
  (unless (and (member phase publication-phases)
               (exact-positive-integer? attempt)
               (member state '(passed failed unavailable))
               (timestamp? finished-at))
    (raise-arguments-error 'finish-candidate-phase!
                           "invalid phase completion"))
  (when (and (eq? state 'unavailable)
             (not (eq? phase 'public-verification)))
    (raise-user-error 'finish-candidate-phase!
                      "only public verification may be unavailable"))
  (define retained (read-candidate-state store candidate-id))
  (define entry (phase-entry retained phase))
  (unless entry
    (raise-user-error 'finish-candidate-phase!
                      "phase has no running attempt: ~a"
                      phase))
  (define attempts (hash-ref entry 'attempts))
  (define running (phase-jsexpr->record (last attempts)))
  (unless (and (= (phase-record-attempt running) attempt)
               (eq? (phase-record-state running) 'running))
    (raise-user-error 'finish-candidate-phase!
                      "phase attempt is not the current running attempt"))
  (define completed
    (struct-copy phase-record
                 running
                 [state state]
                 [finished-at finished-at]
                 [evidence evidence]
                 [failure failure]))
  (unless (phase-record-valid? completed)
    (raise-arguments-error 'finish-candidate-phase!
                           "invalid terminal phase record"
                           "errors" (phase-record-errors completed)))
  (unless (persistable-value? (phase-record->jsexpr completed))
    (raise-user-error 'finish-candidate-phase!
                      "phase completion contains credential material"))
  (for ([artifact (in-list evidence)])
    (define retained-artifact
      (artifact-entry retained (artifact-identity-name artifact)))
    (unless (and retained-artifact
                 (equal? retained-artifact
                         (artifact-identity->jsexpr artifact)))
      (raise-user-error 'finish-candidate-phase!
                        "phase evidence is not retained: ~a"
                        (artifact-identity-name artifact))))
  (define replacement
    (hash-set entry
              'attempts
              (append (drop-right attempts 1)
                      (list (phase-record->jsexpr completed)))))
  (write-candidate-state!
   store
   (hash-set (replace-phase-entry retained phase replacement)
             'updated_at finished-at)))
