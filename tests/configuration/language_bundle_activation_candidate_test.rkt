#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/command/language-bundles.rkt"
         "../../src/command/languages.rkt"
         "../../src/language_bundle/activation-candidate.rkt"
         "../../src/language_bundle/state-records.rkt")

(define digest-a (make-string 64 #\a))
(define digest-b (make-string 64 #\b))
(define digest-c (make-string 64 #\c))
(define digest-d (make-string 64 #\d))
(define target '((linux x86-64)))

(define grammar
  (language-bundle-artifact
   #:id 'grammar #:kind 'tree-sitter-grammar #:path "lib/example.so"
   #:sha256 digest-a #:size 1024 #:targets target #:authority 'native-grammar))

(define racket-module
  (language-bundle-artifact
   #:id 'entrypoint #:kind 'racket-module #:path "bundle.rkt"
   #:sha256 digest-b #:size 512 #:targets target #:authority 'racket-extension))

(define example-service
  (language-service
   #:id 'example-service #:display-name "Example Service"
   #:languages '(example) #:command '("example-language-server" "--stdio")
   #:features '(diagnostics completion rename formatting code-actions)
   #:default? #t))

(define example-formatter
  (language-formatter
   #:id 'example-formatter #:languages '(example) #:kind 'language-service
   #:service 'example-service #:scopes '(buffer range)))

(define example-keymap
  (language-keymap
   #:id 'example-map #:languages '(example)
   #:bindings (hasheq 'run-example 'example-command)))

(define example-bundle
  (language-support-bundle
   #:id 'org.example.language #:display-name "Example Language"
   #:version "1.2.0" #:api-min "1.0.0" #:api-max "2.0.0"
   #:description "Example activation candidate."
   #:publisher 'org.example #:source 'catalog.example #:targets target
   #:authorities
   (list (language-bundle-authority 'native-grammar)
         (language-bundle-authority 'racket-extension)
         (language-bundle-authority 'external-process))
   #:languages
   (list (language #:id 'example #:display-name "Example" #:suffixes '(".example")))
   #:syntax-providers
   (list (tree-sitter-syntax-provider
          #:id 'example-syntax #:languages '(example)
          #:grammar-artifact 'grammar #:grammar-symbol "tree_sitter_example"))
   #:services (list example-service)
   #:formatters (list example-formatter)
   #:commands
   (list (language-command
          #:id 'example-command #:description "Run the example command."
          #:implementation 'example-command))
   #:keymaps (list example-keymap)
   #:artifacts (list grammar racket-module)
   #:entrypoint "bundle.rkt"))

(define (make-lock [version "1.2.0"])
  (activation-lock-with-checksum
   (odra-activation-lock
    9 14 (hash "org.example.language" version)
    (list digest-a digest-b) digest-c digest-d
    (hash "org.example.language" 27) (make-string 64 #\0))))

(define artifact-handles
  (hasheq
   'grammar (odra-bundle-artifact-handle 'grammar digest-a 1024 "sha256:grammar" #t)
   'entrypoint (odra-bundle-artifact-handle
                'entrypoint digest-b 512 "sha256:entrypoint" #t)))

(define (make-input
         #:authorities [authorities '(native-grammar racket-extension external-process)]
         #:artifacts [artifacts artifact-handles]
         #:availability [availability (hasheq)]
         #:racket-generation [racket-generation 31])
  (odra-bundle-preparation-input
   example-bundle 'package "org.example.language" authorities artifacts availability
   racket-generation))

(test-case "complete registry candidates remain private and lock-bound"
  (define result (prepare-bundle-activation (make-lock) (list (make-input))))
  (check-eq? (odra-bundle-activation-preparation-state result) 'prepared)
  (check-false (odra-bundle-activation-preparation-failure result))
  (define candidate (odra-bundle-activation-preparation-candidate result))
  (check-equal? (odra-bundle-activation-candidate-lock-generation candidate) 9)
  (check-equal? (odra-bundle-activation-candidate-state-generation candidate) 14)
  (define contribution (car (odra-bundle-activation-candidate-contributions candidate)))
  (check-equal? (odra-bundle-contribution-candidate-contribution-generation contribution) 27)
  (check-equal? (map odra-language-id
                     (odra-bundle-contribution-candidate-languages contribution))
                '(example))
  (check-equal? (map odra-tree-sitter-syntax-provider-id
                     (odra-bundle-contribution-candidate-syntax-providers contribution))
                '(example-syntax))
  (check-equal? (map odra-language-service-id
                     (odra-bundle-contribution-candidate-services contribution))
                '(example-service))
  (check-equal? (map odra-language-formatter-id
                     (odra-bundle-contribution-candidate-formatters contribution))
                '(example-formatter))
  (check-equal? (map odra-language-command-id
                     (odra-bundle-contribution-candidate-commands contribution))
                '(example-command))
  (check-equal? (map odra-language-keymap-id
                     (odra-bundle-contribution-candidate-keymaps contribution))
                '(example-map))
  (check-equal? (odra-bundle-contribution-candidate-racket-generation contribution) 31)
  (check-equal? (map odra-bundle-contribution-status-state
                     (odra-bundle-contribution-candidate-statuses contribution))
                '(available available available available available available)))

(test-case "lock, authority, artifact, and runtime mismatches reject the whole preparation"
  (define invalid-lock
    (struct-copy odra-activation-lock (make-lock) [checksum digest-a]))
  (check-eq?
   (odra-bundle-activation-failure-code
    (odra-bundle-activation-preparation-failure
     (prepare-bundle-activation invalid-lock (list (make-input)))))
   'invalid-lock)
  (check-eq?
   (odra-bundle-activation-failure-code
    (odra-bundle-activation-preparation-failure
     (prepare-bundle-activation (make-lock "2.0.0") (list (make-input)))))
   'version-mismatch)
  (define denied-authority
    (prepare-bundle-activation
     (make-lock) (list (make-input #:authorities '(native-grammar)))))
  (check-eq?
   (odra-bundle-activation-failure-code
    (odra-bundle-activation-preparation-failure denied-authority))
   'authority-denied)
  (define missing-runtime
    (prepare-bundle-activation
     (make-lock) (list (make-input #:racket-generation 0))))
  (check-eq?
   (odra-bundle-activation-failure-code
    (odra-bundle-activation-preparation-failure missing-runtime))
   'racket-unavailable))

(test-case "unavailable optional contributions remain explicit in one candidate"
  (define result
    (prepare-bundle-activation
     (make-lock)
     (list (make-input #:availability (hasheq 'example-command 'unavailable)))))
  (check-eq? (odra-bundle-activation-preparation-state result) 'prepared)
  (define statuses
    (odra-bundle-contribution-candidate-statuses
     (car (odra-bundle-activation-candidate-contributions
           (odra-bundle-activation-preparation-candidate result)))))
  (check-eq?
   (odra-bundle-contribution-status-state
    (for/first ([status (in-list statuses)]
                #:when (eq? (odra-bundle-contribution-status-id status)
                            'example-command))
      status))
   'unavailable))
