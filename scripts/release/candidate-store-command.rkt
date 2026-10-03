#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (except-in openssl/sha1 sha1)
         (only-in file/sha1 bytes->hex-string)
         json
         racket/cmdline
         racket/file
         racket/list
         racket/string
         "candidate-store.rkt"
         "publication-identity.rkt")

(provide file-artifact-identity
         read-artifact-identities)

(define (file-sha256 path)
  (call-with-input-file path
    (lambda (input) (bytes->hex-string (sha256-bytes input)))))

(define (file-artifact-identity name media-type phase relative-path source)
  (artifact-identity name
                     media-type
                     (file-size source)
                     (file-sha256 source)
                     phase
                     relative-path))

(define (jsexpr->artifact value)
  (artifact-identity (hash-ref value 'name #f)
                     (hash-ref value 'media_type #f)
                     (hash-ref value 'byte_size #f)
                     (hash-ref value 'sha256 #f)
                     (string->symbol (hash-ref value 'phase "invalid"))
                     (hash-ref value 'path #f)))

(define (read-artifact-identities path)
  (define value (call-with-input-file path read-json))
  (unless (list? value)
    (raise-user-error 'read-artifact-identities
                      "artifact evidence must be a JSON array"))
  (define artifacts (map jsexpr->artifact value))
  (unless (andmap artifact-identity-valid? artifacts)
    (raise-user-error 'read-artifact-identities
                      "artifact evidence contains an invalid identity"))
  artifacts)

(define (write-forgejo-outputs path entries)
  (when path
    (call-with-output-file path
      #:exists 'append
      (lambda (output)
        (for ([entry (in-list entries)])
          (fprintf output "~a=~a\n" (car entry) (cdr entry)))))))

(module+ main
  (define store-root #f)
  (define candidate-id #f)
  (define phase #f)
  (define input-sha256 #f)
  (define attempt #f)
  (define state #f)
  (define observed-at #f)
  (define restart-running? #f)
  (define evidence-file #f)
  (define failure-code #f)
  (define failure-summary #f)
  (define source #f)
  (define artifact-name #f)
  (define media-type #f)
  (define relative-path #f)
  (define identity-output #f)
  (define forgejo-output #f)
  (define action #f)
  (command-line
   #:program "candidate-store-command.rkt"
   #:once-each
   [("--store") path "Private candidate store root" (set! store-root path)]
   [("--candidate") value "Candidate SHA-256 identity"
                            (set! candidate-id value)]
   [("--phase") value "Publication phase" (set! phase (string->symbol value))]
   [("--input-sha256") value "Complete phase input digest"
                                 (set! input-sha256 value)]
   [("--attempt") value "Current phase attempt"
                         (set! attempt (string->number value))]
   [("--state") value "Terminal phase state"
                       (set! state (string->symbol value))]
   [("--observed-at") value "RFC3339 observation time"
                            (set! observed-at value)]
   [("--restart-running") "Replace one interrupted running attempt"
                           (set! restart-running? #t)]
   [("--evidence") path "JSON artifact identity array"
                         (set! evidence-file path)]
   [("--failure-code") value "Stable failure code"
                              (set! failure-code value)]
   [("--failure-summary") value "Redacted failure summary"
                                 (set! failure-summary value)]
   [("--source") path "Artifact source file" (set! source path)]
   [("--name") value "Artifact logical name" (set! artifact-name value)]
   [("--media-type") value "Artifact media type" (set! media-type value)]
   [("--relative-path") value "Candidate-relative artifact path"
                               (set! relative-path value)]
   [("--identity-output") path "Artifact identity JSON output"
                               (set! identity-output path)]
   [("--forgejo-output") path "Forgejo output file"
                               (set! forgejo-output path)]
   #:args (command)
   (set! action command))
  (unless (and store-root candidate-id)
    (raise-user-error 'candidate-store-command
                      "store and candidate are required"))
  (define store (open-candidate-store store-root))
  (case (string->symbol action)
    [(start)
     (unless (and phase input-sha256 observed-at)
       (raise-user-error 'candidate-store-command
                         "start requires phase, input digest, and observation time"))
     (define result
       (start-candidate-phase! store candidate-id phase input-sha256 observed-at
                               #:restart-running? restart-running?))
     (write-forgejo-outputs
      forgejo-output
      (list (cons "disposition"
                  (symbol->string (phase-start-result-disposition result)))
            (cons "attempt"
                  (number->string (phase-start-result-attempt result)))))
     (printf "candidate-phase: ~a phase=~a attempt=~a\n"
             (phase-start-result-disposition result)
             phase
             (phase-start-result-attempt result))]
    [(finish)
     (unless (and phase attempt state observed-at)
       (raise-user-error 'candidate-store-command
                         "finish requires phase, attempt, state, and observation time"))
     (define evidence
       (if evidence-file (read-artifact-identities evidence-file) '()))
     (define failure
       (and failure-code failure-summary
            (hasheq 'code failure-code 'summary failure-summary)))
     (void
      (finish-candidate-phase! store candidate-id phase attempt state observed-at
                               #:evidence evidence
                               #:failure failure))
     (printf "candidate-phase: finished phase=~a attempt=~a state=~a\n"
             phase attempt state)]
    [(retain)
     (unless (and phase source artifact-name media-type relative-path
                  identity-output)
       (raise-user-error 'candidate-store-command
                         "retain requires phase, source, artifact identity, and identity output"))
     (define artifact
       (file-artifact-identity artifact-name media-type phase relative-path source))
     (void (retain-candidate-artifact! store candidate-id source artifact))
     (make-parent-directory* identity-output)
     (call-with-output-file identity-output
       #:exists 'truncate/replace
       (lambda (output)
         (write-bytes (canonical-json-bytes
                       (artifact-identity->jsexpr artifact))
                      output)
         (newline output)))
     (printf "candidate-artifact: retained name=~a sha256=~a\n"
             artifact-name (artifact-identity-sha256 artifact))]
    [else
     (raise-user-error 'candidate-store-command
                       "action must be start, finish, or retain")]))
