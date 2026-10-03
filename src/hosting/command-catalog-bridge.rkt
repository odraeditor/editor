#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         (only-in "../configuration/platform-roots.rkt"
                  odra-platform-roots-package-data
                  runtime-platform-roots-current)
         racket/string
         "../command/catalog.rkt"
         "../package/lifecycle-service.rkt"
         "personal-configuration-bridge.rkt"
         "personal-command-runtime.rkt"
         "../command/native-contracts.rkt")

(provide
 (contract-out
  [runtime-command-catalog-batch
   (-> exact-positive-integer? list?)]))

(define (contract item) (native-contract-value 'command-catalog item))
(define schema-version (contract 'schema-version))
(define header-bytes (contract 'header-bytes))
(define record-bytes (contract 'record-bytes))
(define maximum-copy-bytes (contract 'maximum-copy-bytes))

(define (unsigned-word value)
  (integer->integer-bytes value 8 #f #f))

(define (words . values)
  (apply bytes-append (map unsigned-word values)))

(define (dispatch-class-value value)
  (case value
    [(keymap-inspection) 1]
    [(transaction) 2]
    [(personal) 3]
    [(ksawery-extension) 4]))

(define (invocation-value value)
  (case value
    [(ordinary) 1]
    [(text-input) 2]
    [(cancellation) 3]))

(define (text-requirement-value value)
  (case value
    [(prohibited) 1]
    [(optional) 2]
    [(required) 3]))

(define (effect-mask effects)
  (for/fold ([result 0]) ([effect (in-list effects)])
    (bitwise-ior
     result
     (case effect
       [(buffer) #x01]
       [(view) #x02]
       [(lifecycle) #x04]
       [(text-mutation) #x08]))))

(define (requirement-mask requirements)
  (for/fold ([result 0]) ([requirement (in-list requirements)])
    (bitwise-ior
     result
     (case requirement
       [(active-buffer) #x01]
       [(active-document) #x02]
       [(active-region) #x04]))))

(define (command-catalog-batch
         registry-generation
         [catalog (runtime-command-catalog registry-generation)]
         [version schema-version])
  (define text-output (open-output-bytes))
  (define (add-text value)
    (define encoded (string->bytes/utf-8 value))
    (define offset (file-position text-output))
    (write-bytes encoded text-output)
    (values offset (bytes-length encoded)))

  (define records
    (for/list ([definition
                (in-list (odra-command-catalog-definitions catalog))])
      (define provenance (odra-command-definition-provenance definition))
      (define-values (name-offset name-bytes)
        (add-text (odra-command-definition-name definition)))
      (define-values (description-offset description-bytes)
        (add-text (odra-command-definition-description definition)))
      (define-values (provider-offset provider-bytes)
        (add-text (odra-command-source-provider provenance)))
      (define-values (source-offset source-bytes)
        (add-text (odra-command-source-source provenance)))
      (define-values (location-offset location-bytes)
        (add-text (odra-command-source-location provenance)))
      (words
       (dispatch-class-value (odra-command-definition-dispatch-class definition))
       (invocation-value (odra-command-definition-invocation definition))
       (text-requirement-value
        (odra-command-definition-text-requirement definition))
       (effect-mask (odra-command-definition-effects definition))
       (if (odra-command-definition-interactive? definition) 1 0)
       (requirement-mask (odra-command-definition-requirements definition))
       name-offset name-bytes
       description-offset description-bytes
       provider-offset provider-bytes
       source-offset source-bytes
       location-offset location-bytes)))
  (define text (get-output-bytes text-output))
  (define total-bytes
    (+ header-bytes (* record-bytes (length records)) (bytes-length text)))
  (when (> total-bytes maximum-copy-bytes)
    (error 'runtime-command-catalog-batch
           "command catalog exceeds copied storage"))
  (bytes-append
   (words version total-bytes registry-generation
          (odra-command-catalog-generation catalog)
          (length records) (bytes-length text) 0 0)
   (apply bytes-append records)
   text))

(define (package-command-definition? definition)
  (string-prefix?
   (odra-command-source-provider
    (odra-command-definition-provenance definition))
   "package:"))

(define (runtime-command-catalog registry-generation)
  (define personal
    (personal-command-runtime-catalog registry-generation))
  (define roots (runtime-platform-roots-current))
  (define root
    (or (and roots (odra-platform-roots-package-data roots))
        (runtime-personal-configuration-root)))
  (if (not root)
      personal
      (compose-command-catalog
       registry-generation
       (append
        (odra-command-catalog-definitions personal)
        (filter
         package-command-definition?
         (odra-command-catalog-definitions
          (package-lifecycle-runtime-catalog root)))))))

;; runtime-command-catalog-batch returns one production command catalog copy.
(define (runtime-command-catalog-batch registry-generation)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f registry-generation #""
                           (string->bytes/utf-8 (exn-message failure))))])
    (list #t registry-generation
          (command-catalog-batch registry-generation)
          #"")))

(module+ test-support
  (provide command-catalog-batch
           batch-with-u64)

  (define (batch-with-u64 batch offset value)
    (define result (bytes-copy batch))
    (bytes-copy! result offset (unsigned-word value))
    result))

(module+ test
  (require rackunit)

  (define result (runtime-command-catalog-batch 17))
  (check-true (car result))
  (check-equal? (cadr result) 17)
  (define batch (caddr result))
  (check-equal? (bytes-length batch)
                (integer-bytes->integer batch #f #f 8 16))
  (check-equal? (integer-bytes->integer batch #f #f 16 24) 17)
  (check-equal? (integer-bytes->integer batch #f #f 32 40) 7))
