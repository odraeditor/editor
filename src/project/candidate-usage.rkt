#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/file
         racket/list
         racket/match
         racket/path
         racket/port
         "../storage/durable-file.rkt")

(provide
 current-candidate-usage-format-version
 maximum-candidate-usage-entries
 maximum-candidate-usage-key-bytes
 maximum-candidate-usage-module-bytes
 maximum-candidate-usage-sequence
 maximum-candidate-usage-retries
 maximum-candidate-usage-callbacks
 (struct-out odra-candidate-usage-entry)
 (struct-out odra-candidate-usage-record)
 (struct-out odra-candidate-usage-observation)
 (struct-out odra-candidate-usage-diagnostic)
 (struct-out odra-candidate-usage-publication)
 (struct-out odra-candidate-usage-persistence-failure)
 (contract-out
  [candidate-usage-path (-> path-string? string? path?)]
  [candidate-usage-load
   (-> path-string? string? odra-candidate-usage-observation?)]
  [candidate-usage-record->module-bytes
   (-> odra-candidate-usage-record? bytes?)]
  [candidate-usage-publish
   (->* (path-string? odra-candidate-usage-record?)
        (#:expected-generation (or/c exact-positive-integer? #f))
        (or/c odra-candidate-usage-publication?
              odra-candidate-usage-persistence-failure?))]))

(define current-candidate-usage-format-version 1)
(define maximum-candidate-usage-entries 1024)
(define maximum-candidate-usage-key-bytes 4096)
(define maximum-candidate-usage-module-bytes (* 8 1024 1024))
(define maximum-candidate-usage-sequence 9223372036854775807)
(define maximum-candidate-usage-retries 1)
(define maximum-candidate-usage-callbacks 8)
(define maximum-project-identity-bytes 128)
(define maximum-diagnostic-bytes 4096)
(define maximum-command-key-bytes 96)
(define module-header #"#lang racket/base\n")
(define allowed-categories '(command document project-file project workspace))
(define allowed-observation-states '(absent confirmed rejected unavailable))
(define allowed-diagnostic-codes
  '(io size unsafe-path unsafe-permissions invalid-language invalid-encoding
       invalid-syntax invalid-schema unsupported-version project-mismatch))
(define allowed-publications
  '(published-durable published-recovered published-durability-uncertain))
(define allowed-persistence-failures
  '(invalid-root invalid-target unsafe-permissions stale-generation
       invalid-generation temporary-name-limit create-failed write-failed
       file-sync-failed validation-failed rename-failed directory-sync-failed
       cleanup-failed))

(define (bounded-text? value limit)
  (and (string? value)
       (positive? (string-length value))
       (not (string-contains-nul? value))
       (<= (bytes-length (string->bytes/utf-8 value)) limit)))

(define (string-contains-nul? value)
  (for/or ([character (in-string value)]) (char=? character #\nul)))

(define (project-identity? value)
  (and (bounded-text? value maximum-project-identity-bytes)
       (regexp-match? #px"^[a-z0-9]+(?:-[a-z0-9]+)*$" value)))

(define (canonical-file-key? value)
  (and (bounded-text? value maximum-candidate-usage-key-bytes)
       (complete-path? (string->path value))
       (equal? (simplify-path (string->path value) #f)
               (string->path value))))

(define (category-key? category key)
  (and (memq category allowed-categories)
       (case category
         [(command) (bounded-text? key maximum-command-key-bytes)]
         [(document project-file) (canonical-file-key? key)]
         [(project workspace) (project-identity? key)]
         [else #f])))

(define (copied-text value)
  (string->immutable-string
   (if (path? value) (path->string value) value)))

(struct odra-candidate-usage-entry (category key sequence)
  #:transparent
  #:guard
  (lambda (category key sequence _)
    (unless (and (category-key? category key)
                 (exact-positive-integer? sequence)
                 (< sequence maximum-candidate-usage-sequence))
      (raise-arguments-error
       'odra-candidate-usage-entry
       "invalid bounded candidate usage entry"
       "category" category
       "key" key
       "sequence" sequence))
    (values category (string->immutable-string key) sequence)))

(struct odra-candidate-usage-record
  (format-version project-id generation next-sequence entries)
  #:transparent
  #:guard
  (lambda (format-version project-id generation next-sequence entries _)
    (unless (= format-version current-candidate-usage-format-version)
      (raise-arguments-error
       'odra-candidate-usage-record
       "unsupported candidate usage format"
       "format-version" format-version))
    (unless (project-identity? project-id)
      (raise-arguments-error
       'odra-candidate-usage-record
       "invalid Project identity"
       "project-id" project-id))
    (unless (and (exact-positive-integer? generation)
                 (< generation maximum-candidate-usage-sequence)
                 (exact-positive-integer? next-sequence)
                 (<= next-sequence maximum-candidate-usage-sequence)
                 (list? entries)
                 (<= (length entries) maximum-candidate-usage-entries)
                 (andmap odra-candidate-usage-entry? entries)
                 (record-entries-valid? entries next-sequence))
      (raise-arguments-error
       'odra-candidate-usage-record
       "invalid bounded candidate usage record"))
    (values format-version
            (string->immutable-string project-id)
            generation
            next-sequence
            (canonical-entry-list
             (for/list ([entry (in-list entries)]) entry)))))

(struct odra-candidate-usage-diagnostic (code message target)
  #:transparent
  #:guard
  (lambda (code message target _)
    (unless (and (memq code allowed-diagnostic-codes)
                 (bounded-text? message maximum-diagnostic-bytes)
                 (path-string? target))
      (raise-arguments-error
       'odra-candidate-usage-diagnostic
       "invalid candidate usage diagnostic"))
    (values code (string->immutable-string message) (copied-text target))))

(struct odra-candidate-usage-observation (state target record diagnostic module-bytes)
  #:transparent
  #:guard
  (lambda (state target record diagnostic module-bytes _)
    (unless (and (memq state allowed-observation-states)
                 (path-string? target)
                 (or (not record) (odra-candidate-usage-record? record))
                 (or (not diagnostic) (odra-candidate-usage-diagnostic? diagnostic))
                 (bytes? module-bytes)
                 (<= (bytes-length module-bytes) maximum-candidate-usage-module-bytes))
      (raise-arguments-error
       'odra-candidate-usage-observation
       "invalid candidate usage observation"))
    (values state (copied-text target) record diagnostic
            (bytes->immutable-bytes module-bytes))))

(struct odra-candidate-usage-publication
  (publication target generation module-bytes file-synced? directory-synced?)
  #:transparent
  #:guard
  (lambda (publication target generation module-bytes file-synced?
                       directory-synced? _)
    (unless (and (memq publication allowed-publications)
                 (path-string? target)
                 (exact-positive-integer? generation)
                 (bytes? module-bytes)
                 (<= (bytes-length module-bytes) maximum-candidate-usage-module-bytes)
                 (boolean? file-synced?)
                 (boolean? directory-synced?))
      (raise-arguments-error
       'odra-candidate-usage-publication
       "invalid candidate usage publication"))
    (values publication (copied-text target) generation
            (bytes->immutable-bytes module-bytes)
            file-synced? directory-synced?)))

(struct odra-candidate-usage-persistence-failure
  (code message target recovery-path publication platform-code)
  #:transparent
  #:guard
  (lambda (code message target recovery-path publication platform-code _)
    (unless (and (memq code allowed-persistence-failures)
                 (bounded-text? message maximum-diagnostic-bytes)
                 (path-string? target)
                 (or (string=? recovery-path "") (path-string? recovery-path))
                 (or (eq? publication 'not-published)
                     (memq publication allowed-publications))
                 (exact-nonnegative-integer? platform-code))
      (raise-arguments-error
       'odra-candidate-usage-persistence-failure
       "invalid candidate usage persistence failure"))
    (values code (string->immutable-string message) (copied-text target)
            (if (string=? recovery-path "") "" (copied-text recovery-path))
            publication platform-code)))

(struct exn:fail:candidate-usage exn:fail
  (code target recovery-path publication platform-code)
  #:transparent)

(struct exn:fail:candidate-usage-load exn:fail (code)
  #:transparent)

;; candidate-usage-path derives state outside the Project catalog and workspace.
(define (candidate-usage-path state-root project-id)
  (unless (project-identity? project-id)
    (raise-argument-error 'candidate-usage-path
                          "a bounded canonical Project identity"
                          project-id))
  (build-path (path->complete-path state-root)
              "projects"
              project-id
              "candidate-usage.rkt"))

;; candidate-usage-load validates one complete declarative record or returns empty evidence.
(define (candidate-usage-load state-root project-id)
  (define target (candidate-usage-path state-root project-id))
  (cond
    [(not (or (file-exists? target) (link-exists? target)))
     (odra-candidate-usage-observation 'absent target #f #f #"")]
    [else
     (with-handlers
         ([exn:fail:candidate-usage-load?
           (lambda (failure)
             (rejected-observation
              'rejected
              (exn:fail:candidate-usage-load-code failure)
              (exn-message failure)
              target))]
          [exn:fail:filesystem?
           (lambda (failure)
             (rejected-observation 'unavailable 'io (exn-message failure) target))]
          [exn:fail?
           (lambda (failure)
             (rejected-observation 'rejected 'invalid-schema
                                   (exn-message failure) target))])
       (validate-existing-target target)
       (define module-bytes (read-bounded-module target))
       (define record (parse-module module-bytes target project-id))
       (odra-candidate-usage-observation
        'confirmed target record #f module-bytes))]))

;; candidate-usage-record->module-bytes renders one deterministic private module.
(define (candidate-usage-record->module-bytes record)
  (define output (open-output-bytes))
  (display "#lang racket/base\n\n" output)
  (display "(provide candidate-usage)\n\n" output)
  (display "(define candidate-usage\n  '((format-version . " output)
  (display (odra-candidate-usage-record-format-version record) output)
  (display ")\n    (project-id . " output)
  (write (odra-candidate-usage-record-project-id record) output)
  (display ")\n    (generation . " output)
  (display (odra-candidate-usage-record-generation record) output)
  (display ")\n    (next-sequence . " output)
  (display (odra-candidate-usage-record-next-sequence record) output)
  (display ")\n    (entries" output)
  (for ([entry (in-list (canonical-entries record))])
    (display "\n      ((category . " output)
    (display (odra-candidate-usage-entry-category entry) output)
    (display ")\n       (key . " output)
    (write (odra-candidate-usage-entry-key entry) output)
    (display ")\n       (sequence . " output)
    (display (odra-candidate-usage-entry-sequence entry) output)
    (display "))" output))
  (display ")))\n" output)
  (define rendered (get-output-bytes output #t))
  (when (> (bytes-length rendered) maximum-candidate-usage-module-bytes)
    (raise-user-error
     'candidate-usage-record->module-bytes
     "candidate usage module exceeds byte limit"))
  (bytes->immutable-bytes rendered))

;; candidate-usage-publish stages, reloads, and atomically replaces one generation.
(define (candidate-usage-publish state-root record
                                 #:expected-generation [expected-generation #f])
  (define target
    (candidate-usage-path state-root
                          (odra-candidate-usage-record-project-id record)))
  (define directory (path-only target))
  (define projects-directory (path-only directory))
  (define module-bytes (candidate-usage-record->module-bytes record))
  (with-handlers
      ([exn:fail:candidate-usage?
        (lambda (failure) (failure->result failure))]
       [exn:fail?
        (lambda (failure)
          (persistence-failure
           'validation-failed (exn-message failure) target))])
    (define current (load-current-record target))
    (validate-publication-generation current record expected-generation target)
    (define result
      (durable-file-publish
       target
       module-bytes
       #:private-directories (list state-root projects-directory directory)
       #:validate-stage
       (lambda (stage)
         (validate-stage stage record target)
         #t)
       #:recover-visible
       (lambda (visible-target)
         (visible-publication-matches? visible-target record))))
    (durable-result->candidate-result result record module-bytes)))

(define (durable-result->candidate-result result record module-bytes)
  (cond
    [(odra-durable-file-failure? result)
     (odra-candidate-usage-persistence-failure
      (odra-durable-file-failure-code result)
      (bounded-message (odra-durable-file-failure-message result))
      (odra-durable-file-failure-target result)
      (odra-durable-file-failure-recovery-path result)
      (odra-durable-file-failure-publication result)
      (odra-durable-file-failure-platform-code result))]
    [else
     (odra-candidate-usage-publication
      (odra-durable-file-publication-publication result)
      (odra-durable-file-publication-target result)
      (odra-candidate-usage-record-generation record)
      module-bytes
      (odra-durable-file-publication-file-synced? result)
      (odra-durable-file-publication-directory-synced? result))]))

(define (record-entries-valid? entries next-sequence)
  (define identities
    (for/list ([entry (in-list entries)])
      (cons (odra-candidate-usage-entry-category entry)
            (odra-candidate-usage-entry-key entry))))
  (and (= (length identities) (length (remove-duplicates identities equal?)))
       (for/and ([entry (in-list entries)])
         (< (odra-candidate-usage-entry-sequence entry) next-sequence))))

(define (canonical-entries record)
  (canonical-entry-list (odra-candidate-usage-record-entries record)))

(define (canonical-entry-list entries)
  (sort entries
        (lambda (left right)
          (cond
            [(not (= (odra-candidate-usage-entry-sequence left)
                     (odra-candidate-usage-entry-sequence right)))
             (> (odra-candidate-usage-entry-sequence left)
                (odra-candidate-usage-entry-sequence right))]
            [(not (eq? (odra-candidate-usage-entry-category left)
                       (odra-candidate-usage-entry-category right)))
             (symbol<? (odra-candidate-usage-entry-category left)
                       (odra-candidate-usage-entry-category right))]
            [else
             (string<? (odra-candidate-usage-entry-key left)
                       (odra-candidate-usage-entry-key right))]))))

(define (read-bounded-module target)
  (define observed-size (file-size target))
  (when (> observed-size maximum-candidate-usage-module-bytes)
    (raise-load 'size "Candidate usage module exceeds byte limit"))
  (define copied
    (call-with-input-file target
      (lambda (input)
        (define value
          (read-bytes (add1 maximum-candidate-usage-module-bytes) input))
        (if (eof-object? value) #"" value))
      #:mode 'binary))
  (when (> (bytes-length copied) maximum-candidate-usage-module-bytes)
    (raise-load 'size "Candidate usage module exceeds byte limit"))
  (bytes->immutable-bytes copied))

(define (parse-module module-bytes target expected-project-id)
  (unless (bytes-prefix? module-bytes module-header)
    (raise-load 'invalid-language
                "Candidate usage module must use #lang racket/base"))
  (define body-bytes (subbytes module-bytes (bytes-length module-header)))
  (define body
    (with-handlers ([exn:fail?
                     (lambda (_)
                       (raise-load 'invalid-encoding
                                   "Candidate usage module is not valid UTF-8"))])
      (bytes->string/utf-8 body-bytes #f)))
  (define input (open-input-string body target))
  (port-count-lines! input)
  (define forms
    (let loop ([values '()])
      (define form (read-syntax target input))
      (if (eof-object? form)
          (reverse values)
          (loop (cons (syntax->datum form) values)))))
  (match forms
    [(list '(provide candidate-usage)
           (list 'define 'candidate-usage (list 'quote record-datum)))
     (parse-record record-datum expected-project-id)]
    [_
     (raise-load
      'invalid-syntax
      "Candidate usage module must contain only the canonical provide and definition")]))

(define (parse-record datum expected-project-id)
  (match datum
    [(list (cons 'format-version format-version)
           (cons 'project-id project-id)
           (cons 'generation generation)
           (cons 'next-sequence next-sequence)
           (list* 'entries entry-data))
     (unless (equal? format-version current-candidate-usage-format-version)
       (raise-load 'unsupported-version
                   "Candidate usage format version is not supported"))
     (unless (equal? project-id expected-project-id)
       (raise-load 'project-mismatch
                   "Candidate usage Project identity does not match its directory"))
     (define entries
       (for/list ([entry-datum (in-list entry-data)])
         (parse-entry entry-datum)))
     (odra-candidate-usage-record
      format-version project-id generation next-sequence entries)]
    [_
     (raise-load 'invalid-schema
                 "Candidate usage record has an invalid schema")]))

(define (parse-entry datum)
  (match datum
    [(list (cons 'category category)
           (cons 'key key)
           (cons 'sequence sequence))
     (odra-candidate-usage-entry category key sequence)]
    [_
     (raise-load 'invalid-schema
                 "Candidate usage entry has an invalid schema")]))

(define (bytes-prefix? value prefix)
  (and (>= (bytes-length value) (bytes-length prefix))
       (bytes=? (subbytes value 0 (bytes-length prefix)) prefix)))

(define (rejected-observation state code message target)
  (odra-candidate-usage-observation
   state target #f
   (odra-candidate-usage-diagnostic code (bounded-message message) target)
   #""))

(define (bounded-message message)
  (define text (if (string? message) message (format "~a" message)))
  (if (<= (bytes-length (string->bytes/utf-8 text)) maximum-diagnostic-bytes)
      text
      "Candidate usage operation failed with an oversized diagnostic"))

(define (validate-existing-target target)
  (define failure (durable-file-check target))
  (when failure
    (raise-load
     (if (eq? (odra-durable-file-failure-code failure) 'unsafe-permissions)
         'unsafe-permissions
         'unsafe-path)
     (odra-durable-file-failure-message failure))))

(define (load-current-record target)
  (cond
    [(or (file-exists? target) (link-exists? target))
     (validate-existing-target target)
     (define-values (project-directory _target-name _target-directory?)
       (split-path target))
     (define-values (projects-directory project-name _project-directory?)
       (split-path project-directory))
     (define-values (state-root _projects-name _projects-directory?)
       (split-path projects-directory))
     (define project-id (path->string project-name))
     (define observation
       (candidate-usage-load
        state-root
        project-id))
     (unless (eq? (odra-candidate-usage-observation-state observation) 'confirmed)
       (raise-persistence 'validation-failed
                          "Existing candidate usage record cannot be validated"
                          target))
     (odra-candidate-usage-observation-record observation)]
    [else #f]))

(define (validate-publication-generation current candidate expected target)
  (define candidate-generation
    (odra-candidate-usage-record-generation candidate))
  (cond
    [current
     (define current-generation
       (odra-candidate-usage-record-generation current))
     (when (and expected (not (= expected current-generation)))
       (raise-persistence 'stale-generation
                          "Candidate usage generation changed before persistence"
                          target))
     (unless (= candidate-generation (add1 current-generation))
       (raise-persistence 'invalid-generation
                          "Updated candidate usage generation must increment exactly once"
                          target))]
    [else
     (when expected
       (raise-persistence 'stale-generation
                          "Candidate usage record disappeared before persistence"
                          target))
     (unless (= candidate-generation 1)
       (raise-persistence 'invalid-generation
                          "Initial candidate usage generation must be one"
                          target))]))

(define (validate-stage stage expected target)
  (define project-id (odra-candidate-usage-record-project-id expected))
  (define module-bytes (read-bounded-module stage))
  (define loaded (parse-module module-bytes stage project-id))
  (unless (equal? loaded expected)
    (raise-persistence 'validation-failed
                       "Candidate usage staging reload changed canonical fields"
                       target stage)))

(define (visible-publication-matches? target expected)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (and (file-exists? target)
         (let* ([loaded-bytes (read-bounded-module target)]
                [loaded (parse-module
                         loaded-bytes target
                         (odra-candidate-usage-record-project-id expected))])
           (equal? loaded expected)))))

(define (raise-load code message)
  (raise
   (exn:fail:candidate-usage-load
    message
    (current-continuation-marks)
    code)))

(define (raise-persistence code message target
                           [recovery-path #f]
                           [publication 'not-published]
                           [platform-code 0])
  (raise
   (exn:fail:candidate-usage
    message
    (current-continuation-marks)
    code
    (path->string target)
    (if recovery-path (path->string recovery-path) "")
    publication
    (or platform-code 0))))

(define (failure->result failure)
  (odra-candidate-usage-persistence-failure
   (exn:fail:candidate-usage-code failure)
   (bounded-message (exn-message failure))
   (exn:fail:candidate-usage-target failure)
   (exn:fail:candidate-usage-recovery-path failure)
   (exn:fail:candidate-usage-publication failure)
   (exn:fail:candidate-usage-platform-code failure)))

(define (persistence-failure code message target
                             [recovery-path ""]
                             [publication 'not-published]
                             [platform-code 0])
  (odra-candidate-usage-persistence-failure
   code (bounded-message message) target recovery-path publication platform-code))

(module+ test
  (require rackunit
           (submod "../storage/durable-file.rkt" test-support))

  (define owner-file-permissions #o600)
  (define owner-directory-permissions #o700)

  (define (with-private-root procedure)
    (define root (make-temporary-file "odra-candidate-usage~a" 'directory))
    (file-or-directory-permissions root owner-directory-permissions)
    (dynamic-wind void (lambda () (procedure root))
                  (lambda () (delete-directory/files root))))

  (define (record project-id generation next-sequence entries)
    (odra-candidate-usage-record
     current-candidate-usage-format-version
     project-id generation next-sequence entries))

  (define first-record
    (record
     "first-project" 1 4
     (list
      (odra-candidate-usage-entry 'document "/tmp/alpha.odin" 1)
      (odra-candidate-usage-entry 'command "project-find-file" 3))))

  (test-case "publication reloads per Project"
    (with-private-root
     (lambda (root)
       (define first (candidate-usage-publish root first-record))
       (check-true (odra-candidate-usage-publication? first))
       (check-eq? (odra-candidate-usage-publication-publication first)
                  'published-durable)
       (define observed (candidate-usage-load root "first-project"))
       (check-eq? (odra-candidate-usage-observation-state observed) 'confirmed)
       (check-equal? (odra-candidate-usage-observation-record observed) first-record)
       (check-equal? (odra-candidate-usage-observation-module-bytes observed)
                     (candidate-usage-record->module-bytes first-record))
       (define other (candidate-usage-load root "second-project"))
       (check-eq? (odra-candidate-usage-observation-state other) 'absent))))

  (test-case "Project and Workspace recency stay separate"
    (with-private-root
     (lambda (root)
       (define global-record
         (record
          "global-selection" 1 3
          (list
           (odra-candidate-usage-entry 'project "odra" 1)
           (odra-candidate-usage-entry 'workspace "daily-work" 2))))
       (check-true
        (odra-candidate-usage-publication?
         (candidate-usage-publish root global-record)))
       (check-equal?
        (odra-candidate-usage-observation-record
         (candidate-usage-load root "global-selection"))
        global-record))))

  (test-case "loader rejects unsafe and oversized modules"
    (with-private-root
     (lambda (root)
       (define target (candidate-usage-path root "first-project"))
       (make-directory* (path-only target))
       (file-or-directory-permissions (path-only target) owner-directory-permissions)
       (define malformed-values
         (list
          #"#lang racket/base\n(displayln \"executed\")\n"
          #"#lang racket/base\n(provide candidate-usage)\n(define candidate-usage '((format-version . 1) (project-id . \"first-project\") (generation . 1) (next-sequence . 3) (entries ((category . command) (key . \"project-find-file\") (sequence . 1)) ((category . command) (key . \"project-find-file\") (sequence . 2))))))\n"))
       (for ([value (in-list malformed-values)])
         (call-with-output-file target
           (lambda (output) (write-bytes value output))
           #:mode 'binary #:exists 'truncate/replace
           #:permissions owner-file-permissions)
         (file-or-directory-permissions target owner-file-permissions)
         (check-eq? (odra-candidate-usage-observation-state
                     (candidate-usage-load root "first-project"))
                    'rejected))
       (call-with-output-file target
         (lambda (output)
           (write-bytes (make-bytes (add1 maximum-candidate-usage-module-bytes) 32)
                        output))
         #:mode 'binary #:exists 'truncate/replace
         #:permissions owner-file-permissions)
       (file-or-directory-permissions target owner-file-permissions)
       (define oversized (candidate-usage-load root "first-project"))
       (check-eq? (odra-candidate-usage-observation-state oversized) 'rejected)
       (check-eq? (odra-candidate-usage-diagnostic-code
                   (odra-candidate-usage-observation-diagnostic oversized))
                  'size))))

  (test-case "stale rename faults preserve visible record"
    (with-private-root
     (lambda (root)
       (check-true (odra-candidate-usage-publication?
                    (candidate-usage-publish root first-record)))
       (define updated
         (record "first-project" 2 5
                 (list (odra-candidate-usage-entry
                        'command "project-find-file" 4))))
       (define stale
         (candidate-usage-publish root updated #:expected-generation 7))
       (check-true (odra-candidate-usage-persistence-failure? stale))
       (check-eq? (odra-candidate-usage-persistence-failure-code stale)
                  'stale-generation)
       (define write-failure
         (parameterize ([current-durable-file-write (lambda (_ __) 0)])
           (candidate-usage-publish root updated #:expected-generation 1)))
       (check-eq? (odra-candidate-usage-persistence-failure-code write-failure)
                  'write-failed)
       (check-equal?
        (odra-candidate-usage-observation-record
         (candidate-usage-load root "first-project"))
        first-record))))

  (test-case "post-rename fault recovers visible publication"
    (with-private-root
     (lambda (root)
       (check-true (odra-candidate-usage-publication?
                    (candidate-usage-publish root first-record)))
       (define updated
         (record "first-project" 2 5
                 (list (odra-candidate-usage-entry
                        'project-file "/tmp/beta.odin" 4))))
       (define recovered
         (parameterize
             ([current-durable-file-rename
               (lambda (source target)
                 (rename-file-or-directory source target #t)
                 5)])
           (candidate-usage-publish root updated #:expected-generation 1)))
       (check-true (odra-candidate-usage-publication? recovered))
       (check-eq? (odra-candidate-usage-publication-publication recovered)
                  'published-recovered)
       (check-equal?
        (odra-candidate-usage-observation-record
         (candidate-usage-load root "first-project"))
        updated))))

  (test-case "dir-sync fault reports durability uncertainty"
    (with-private-root
     (lambda (root)
       (define uncertain
         (parameterize ([current-durable-directory-sync (lambda (_) 5)])
           (candidate-usage-publish root first-record)))
       (check-true (odra-candidate-usage-publication? uncertain))
       (check-eq? (odra-candidate-usage-publication-publication uncertain)
                  'published-durability-uncertain)
       (check-false
        (odra-candidate-usage-publication-directory-synced? uncertain))))))
