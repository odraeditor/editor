#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "../project/records.rkt"
         "../workspace/persistence.rkt"
         "../workspace/records.rkt"
         "../workspace/management.rkt")

(provide
 (contract-out
  [runtime-workspace-command-batch (-> bytes? bytes? list?)]))

(define schema-version 1)
(define request-header-bytes 48)
(define result-header-bytes 88)
(define workspace-record-bytes 56)
(define member-record-bytes 104)
(define maximum-copy-bytes (* 4 1024 1024))
(define fnv-offset 14695981039346656037)
(define state-codes '((ready . 1) (missing . 2) (unavailable . 3) (conflict . 4) (stale . 5)))

(define (word value)
  (integer->integer-bytes value 8 #f #f))

(define (words . values)
  (apply bytes-append (map word values)))

(define (read-word input offset)
  (integer-bytes->integer input #f #f offset (+ offset 8)))

(define (fnv-bytes hash value)
  (for/fold ([result hash]) ([byte (in-bytes value)])
    (bitwise-and
     (* (bitwise-xor result byte) 1099511628211)
     (sub1 (expt 2 64)))))

(define (runtime-workspace-command-batch configuration-root-bytes request)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #"" (string->bytes/utf-8 (exn-message failure))))])
    (define configuration-root (bytes->string/utf-8 configuration-root-bytes #f))
    (define-values (action expected-generation id name roots) (decode-request request))
    (define result
      (case action
        [(1)
         (define composed (workspace-create-compose configuration-root name roots))
         (if (odra-workspace-proposal? composed)
             (workspace-publish configuration-root composed)
             composed)]
        [(2 5) (workspace-inspect configuration-root id)]
        [(3)
         (define composed
           (workspace-update-compose configuration-root id expected-generation name roots))
         (if (odra-workspace-proposal? composed)
             (workspace-publish configuration-root composed)
             composed)]
        [(4) (workspace-list configuration-root)]
        [(6)
         (define composed
           (workspace-add-project-compose
            configuration-root id expected-generation (single-root roots)))
         (if (odra-workspace-proposal? composed)
             (workspace-publish configuration-root composed)
             composed)]
        [(7)
         (define composed
           (workspace-remove-project-compose
            configuration-root id expected-generation (single-root roots)))
         (if (odra-workspace-proposal? composed)
             (workspace-publish configuration-root composed)
             composed)]
        [(8) (workspace-unregister configuration-root id expected-generation)]
        [(9 10)
         (define composed
           (workspace-move-project-compose
            configuration-root id expected-generation (single-root roots)
            (if (= action 9) 'earlier 'later)))
         (if (odra-workspace-proposal? composed)
             (workspace-publish configuration-root composed)
             composed)]
        [else (raise-arguments-error 'runtime-workspace-command-batch
                                     "invalid Workspace action")]))
    (list #t (encode-result action result) #"")))

(define (decode-request request)
  (unless (>= (bytes-length request) request-header-bytes)
    (raise-arguments-error 'runtime-workspace-command-batch "truncated request"))
  (define schema (read-word request 0))
  (define action (read-word request 8))
  (define generation (read-word request 16))
  (define id-bytes (read-word request 24))
  (define name-bytes (read-word request 32))
  (define root-count (read-word request 40))
  (unless (and (= schema schema-version) (<= 1 action 10)
               (<= id-bytes 128) (<= name-bytes 1024) (<= root-count 256))
    (raise-arguments-error 'runtime-workspace-command-batch "invalid request header"))
  (define offset request-header-bytes)
  (define (take-text length)
    (define end (+ offset length))
    (unless (<= end (bytes-length request))
      (raise-arguments-error 'runtime-workspace-command-batch "truncated request text"))
    (define value (bytes->string/utf-8 (subbytes request offset end) #f))
    (set! offset end)
    value)
  (define id (take-text id-bytes))
  (define name (take-text name-bytes))
  (define roots
    (for/list ([_index (in-range root-count)])
      (unless (<= (+ offset 8) (bytes-length request))
        (raise-arguments-error 'runtime-workspace-command-batch "truncated root width"))
      (define length (read-word request offset))
      (set! offset (+ offset 8))
      (take-text length)))
  (unless (= offset (bytes-length request))
    (raise-arguments-error 'runtime-workspace-command-batch "trailing request bytes"))
  (values action generation id name roots))

(define (encode-result action result)
  (cond
    [(odra-workspace-failure? result)
     (encode-failure action result)]
    [(odra-record-catalog? result)
     (define records (odra-record-catalog-records result))
     (encode-workspaces
      action
      records
      (map (lambda (record)
             (odra-workspace-resolution-members (workspace-resolve record)))
           records)
      1)]
    [(odra-workspace-publication? result)
     (define record (odra-workspace-publication-record result))
     (define resolution (workspace-resolve record))
     (encode-workspaces
      action
      (list record)
      (list (odra-workspace-resolution-members resolution))
      (if (eq? (odra-workspace-publication-state result) 'published) 2 3))]
    [(odra-workspace-resolution? result)
     (encode-workspaces
      action
      (list (odra-workspace-resolution-record result))
      (list (odra-workspace-resolution-members result))
      1)]
    [else (raise-result-error 'runtime-workspace-command-batch "Workspace result" result)]))

(define (single-root roots)
  (unless (= (length roots) 1)
    (raise-arguments-error 'runtime-workspace-command-batch
                           "Workspace member update requires one Project"))
  (car roots))

(define (encode-failure action failure)
  (define diagnostic (string->bytes/utf-8 (odra-workspace-failure-message failure)))
  (define publication
    (case (odra-workspace-failure-publication failure)
      [(none) 1]
      [(complete) 2]
      [(uncertain) 4]))
  (bytes-append
   (words schema-version action 0 0 0 publication
          (bytes-length diagnostic) 1 0 (bytes-length diagnostic) 0)
   diagnostic))

(define (encode-workspaces action records resolution-groups publication)
  (define text-output (open-output-bytes))
  (define (add-text value)
    (define encoded (string->bytes/utf-8 value))
    (define offset (file-position text-output))
    (write-bytes encoded text-output)
    (values offset (bytes-length encoded)))
  (define member-output (open-output-bytes))
  (define member-count 0)
  (define workspace-output (open-output-bytes))
  (for ([record (in-list records)] [workspace-index (in-naturals)])
    (define-values (id-offset id-bytes) (add-text (odra-workspace-record-id record)))
    (define-values (name-offset name-bytes) (add-text (odra-workspace-record-name record)))
    (define members
      (if (< workspace-index (length resolution-groups))
          (list-ref resolution-groups workspace-index)
          '()))
    (write-bytes
     (words id-offset id-bytes (odra-workspace-record-generation record)
            name-offset name-bytes member-count (length members))
     workspace-output)
    (for ([member (in-list members)])
      (write-bytes (encode-member workspace-index member add-text) member-output)
      (set! member-count (add1 member-count))))
  (define text (get-output-bytes text-output))
  (define workspaces (get-output-bytes workspace-output))
  (define members (get-output-bytes member-output))
  (define total (+ result-header-bytes (bytes-length workspaces)
                   (bytes-length members) (bytes-length text)))
  (when (> total maximum-copy-bytes)
    (error 'runtime-workspace-command-batch "Workspace result exceeds copied storage"))
  (bytes-append
   (words schema-version action 1 (length records) member-count publication
          (bytes-length text) 0 0 0 0)
   workspaces members text))

(define (encode-member workspace-index member add-text)
  (define reference (odra-workspace-member-resolution-reference member))
  (define project (odra-workspace-member-resolution-project member))
  (define durable-id (odra-workspace-project-reference-id reference))
  (define name (if project (odra-local-project-record-name project) ""))
  (define root (odra-workspace-project-reference-root reference))
  (define diagnostic (odra-workspace-member-resolution-diagnostic member))
  (define-values (id-offset id-bytes) (add-text durable-id))
  (define-values (name-offset name-bytes) (add-text name))
  (define-values (root-offset root-bytes) (add-text root))
  (define-values (diagnostic-offset diagnostic-bytes) (add-text diagnostic))
  (define runtime-id
    (let ([value (fnv-bytes fnv-offset (string->bytes/utf-8 durable-id))])
      (if (zero? value) 1 value)))
  (words workspace-index
         (cdr (assq (odra-workspace-member-resolution-state member) state-codes))
         runtime-id
         (odra-workspace-project-reference-expected-project-generation reference)
         id-offset id-bytes name-offset name-bytes root-offset root-bytes
         (cond [(not project) 0]
               [(eq? (odra-local-project-record-trust project) 'trusted) 2]
               [else 1])
         diagnostic-offset diagnostic-bytes))

(module+ test
  (require racket/file
           rackunit)

  (define home (make-temporary-file "odra-workspace-bridge-~a" 'directory))
  (define config (build-path home "config" "odra"))
  (define first (build-path home "first"))
  (define second (build-path home "second"))
  (dynamic-wind
   void
   (lambda ()
     (for ([root (in-list (list first second))]
           [id (in-list '("first" "second"))])
       (make-directory* (build-path root ".odra"))
       (call-with-output-file (build-path root ".odra" "project.rkt")
         (lambda (output)
           (write-bytes
            (local-project-record->module-bytes
             (local-project-record
              #:format-version current-local-project-format-version
              #:id id #:generation 1 #:name id
              #:root (path->string root) #:trust 'untrusted))
            output))
         #:exists 'truncate/replace #:mode 'binary))
     (define root-data
       (apply bytes-append
              (for/list ([root (in-list (list first second))])
                (define value (path->bytes root))
                (bytes-append (word (bytes-length value)) value))))
     (define name #"Bridge Workspace")
     (define request
       (bytes-append (words schema-version 1 0 0 (bytes-length name) 2)
                     name root-data))
     (define envelope (runtime-workspace-command-batch (path->bytes config) request))
     (check-true (car envelope))
     (define batch (cadr envelope))
     (check-equal? (read-word batch 16) 1)
     (check-equal? (read-word batch 24) 1)
     (check-equal? (read-word batch 32) 2))
   (lambda () (delete-directory/files home))))
