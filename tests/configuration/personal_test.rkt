#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         racket/path
         "../../src/command/package-resources.rkt"
         "../../src/command/catalog.rkt"
         (only-in "../../src/command/keymap-model.rkt"
                  odra-interaction-profile?
                  odra-interaction-profile-name)
         "../../src/configuration/personal.rkt"
         (submod "../../src/configuration/personal.rkt" test-support))

(define (with-root action)
  (define root (make-temporary-file "odra-personal-config-~a" 'directory))
  (dynamic-wind void (lambda () (action root))
                (lambda () (delete-directory/files root))))

(define (configuration-root root)
  (build-path root "config" "odra"))

(define (write-init root content)
  (define config-root (configuration-root root))
  (make-directory* config-root)
  (call-with-output-file (build-path config-root "init.rkt")
    (lambda (output) (display content output))
    #:exists 'truncate/replace))

(define (write-config-module root relative-path content)
  (define path (build-path (configuration-root root) relative-path))
  (make-directory* (path-only path))
  (call-with-output-file path
    (lambda (output) (display content output))
    #:exists 'truncate/replace))

(define (diagnostic-code result)
  (odra-personal-config-diagnostic-code
   (car
    (odra-personal-config-state-diagnostics
     (odra-personal-config-result-state result)))))

  (test-case "missing init confirms empty generation"
  (with-root
   (lambda (root)
     (define source (personal-config-source (configuration-root root)))
     (define result
       (personal-config-reload (personal-config-initialize) 1 source))
     (check-eq? (odra-personal-config-result-status result) 'confirmed)
     (define state (odra-personal-config-result-state result))
     (check-equal? (odra-personal-config-state-confirmed-generation state) 2)
     (check-eq?
      (odra-personal-config-observation-state
       (odra-personal-config-state-observation state))
      'absent)
     (check-false
      (odra-personal-config-proposal-source
       (odra-personal-config-state-proposal state)))
     (check-equal?
      (odra-personal-config-proposal-module-bytes
       (odra-personal-config-state-proposal state))
      #""))))

(test-case "valid personal init confirms copied module bytes"
  (with-root
   (lambda (root)
     (write-init root "#lang racket/base\n(define selected-theme 'night)\n")
     (define source (personal-config-source (configuration-root root)))
     (define result
       (personal-config-reload (personal-config-initialize) 1 source))
     (check-eq? (odra-personal-config-result-status result) 'confirmed)
     (define state (odra-personal-config-result-state result))
     (define observation (odra-personal-config-state-observation state))
     (check-eq? (odra-personal-config-observation-state observation) 'confirmed)
     (check-equal?
      (odra-personal-config-proposal-source
       (odra-personal-config-state-proposal state))
      source)
     (check-equal?
      (odra-personal-config-proposal-module-bytes
       (odra-personal-config-state-proposal state))
      (odra-personal-config-observation-module-bytes observation)))))

;; The generic resource export must survive confirmed loading without a Project.
(test-case "personal configuration admits named package resources"
  (with-root
   (lambda (root)
     (write-init
      root
      (format
       "#lang racket/base\n(require odra/commands)\n(provide odra-package-resources)\n(define odra-package-resources (list (make-package-resource #:package \"odra.roman\" #:name 'brain #:root ~s #:access 'read-write)))\n"
       (path->string (build-path root "personal"))))
     (define observation
       (personal-config-load (personal-config-source (configuration-root root))))
     (check-eq? (odra-personal-config-observation-state observation) 'confirmed
                (format "~s" (odra-personal-config-observation-diagnostic observation)))
     (define resources (personal-config-observation-export observation 'odra-package-resources))
     (check-true (package-resources? resources))
     (check-equal? (package-resource-root (car resources))
                   (path->string (build-path root "personal"))))))

;; Invalid duplicate names must preserve the previously confirmed generation.
(test-case "duplicate configured resources preserve confirmed configuration"
  (with-root
   (lambda (root)
     (define source (personal-config-source (configuration-root root)))
     (define initial (personal-config-reload (personal-config-initialize) 1 source))
     (write-init
      root
      (format
       "#lang racket/base\n(require odra/commands)\n(provide odra-package-resources)\n(define resource (make-package-resource #:package \"odra.roman\" #:name 'brain #:root ~s))\n(define odra-package-resources (list resource resource))\n"
       (path->string root)))
     (define rejected (personal-config-reload (odra-personal-config-result-state initial) 2 source))
     (check-eq? (odra-personal-config-result-status rejected) 'rejected)
     (check-equal? (odra-personal-config-state-confirmed-generation
                   (odra-personal-config-result-state rejected)) 2))))

(test-case "terminal facade imports without configuration side effects"
  (with-root
   (lambda (root)
     (write-init
      root
      (string-append
       "#lang racket/base\n"
       "(require odra/terminal)\n"
       "(define retained-ref (terminal-session-ref 1 1))\n"))
     (define observation
       (personal-config-load (personal-config-source (configuration-root root))))
     (check-eq? (odra-personal-config-observation-state observation) 'confirmed)
     (check-equal? (odra-personal-config-observation-exports observation)
                   #hasheq()))))

  (test-case "init exports come from one evaluation"
  (with-root
   (lambda (root)
     (define config-root (configuration-root root))
     (make-directory* config-root)
     (call-with-output-file (build-path config-root "evaluation-count")
       (lambda (output) (display 0 output))
       #:exists 'truncate/replace)
     (write-init
      root
      (string-append
       "#lang racket/base\n"
       "(require odra/keymaps)\n"
       "(provide odra-status-bar-configuration odra-interaction-profile)\n"
       "(define counter-path\n"
       "  (build-path (current-load-relative-directory) \"evaluation-count\"))\n"
       "(define evaluation-count\n"
       "  (add1 (call-with-input-file counter-path read)))\n"
       "(call-with-output-file counter-path\n"
       "  (lambda (output) (display evaluation-count output))\n"
       "  #:exists 'truncate/replace)\n"
       "(define odra-status-bar-configuration\n"
       "  (hash 'position 'line-column))\n"
       "(define odra-interaction-profile (factory-interaction-profile))\n"))
     (define source (personal-config-source config-root))
     (define observation (personal-config-load source))
     (check-eq? (odra-personal-config-observation-state observation) 'confirmed)
     (check-equal?
      (personal-config-observation-export
       observation 'odra-status-bar-configuration)
      (hash 'position 'line-column))
     (check-true
      (odra-interaction-profile?
       (personal-config-observation-export observation 'odra-interaction-profile)))
     (check-equal?
      (call-with-input-file (build-path config-root "evaluation-count") read)
      1))))

  (test-case "init can select the factory modal profile"
    (with-root
     (lambda (root)
       (write-init
        root
        (string-append
         "#lang racket/base\n"
         "(require odra/keymaps)\n"
         "(provide odra-interaction-profile)\n"
         "(define odra-interaction-profile (factory-modal-interaction-profile))\n"))
       (define observation
         (personal-config-load (personal-config-source (configuration-root root))))
       (check-eq? (odra-personal-config-observation-state observation) 'confirmed)
       (define profile
         (personal-config-observation-export observation 'odra-interaction-profile))
       (check-true (odra-interaction-profile? profile))
       (check-equal? (odra-interaction-profile-name profile) "modal"))))

  (test-case "bad profile rejects sibling commands"
  (with-root
   (lambda (root)
     (write-init
      root
      (string-append
       "#lang racket/base\n"
       "(require odra/commands)\n"
       "(provide odra-personal-commands odra-interaction-profile)\n"
       "(define odra-personal-commands\n"
       "  (list (make-command 'candidate-command (lambda (_context) (void)))))\n"
       "(define odra-interaction-profile '(not-a-profile))\n"))
     (define observation
       (personal-config-load (personal-config-source (configuration-root root))))
     (check-eq? (odra-personal-config-observation-state observation) 'rejected)
     (check-regexp-match
      #rx"interaction profile"
      (odra-personal-config-diagnostic-message
       (odra-personal-config-observation-diagnostic observation)))
     (check-equal?
      (personal-config-observation-export
       observation 'odra-personal-commands '())
      '()))))

  (test-case "modular config selects personal commands"
  (with-root
   (lambda (root)
     (write-config-module
      root
      "modules/text-commands.rkt"
      (string-append
       "#lang racket/base\n"
       "(require odra/commands)\n"
       "(provide text-commands)\n"
       "(define text-commands\n"
       "  (list\n"
       "   (make-command\n"
       "    'trim-trailing-space\n"
       "    (lambda (_context) (void))\n"
       "    #:description \"Trim trailing whitespace.\"\n"
       "    #:source \"modules/text-commands.rkt\")))\n"))
     (write-init
      root
      (string-append
       "#lang racket/base\n"
       "(require \"modules/text-commands.rkt\")\n"
       "(provide odra-personal-commands)\n"
       "(define odra-personal-commands text-commands)\n"))
     (define observation
       (personal-config-load (personal-config-source (configuration-root root))))
     (check-eq? (odra-personal-config-observation-state observation) 'confirmed)
     (define commands
       (personal-config-observation-export observation 'odra-personal-commands))
     (check-equal? (length commands) 1)
     (check-equal?
      (odra-command-definition-name (car commands))
      "trim-trailing-space")
     (check-equal?
      (odra-command-source-source
       (odra-command-definition-provenance (car commands)))
      "modules/text-commands.rkt"))))

  (test-case "bad command exports reject candidate"
  (with-root
   (lambda (root)
     (define source (personal-config-source (configuration-root root)))
     (write-init
      root
      (string-append
       "#lang racket/base\n"
       "(provide odra-personal-commands)\n"
       "(define odra-personal-commands '#(not-a-list))\n"))
     (define malformed (personal-config-load source))
     (check-eq? (odra-personal-config-observation-state malformed) 'rejected)
     (check-regexp-match
      #rx"proper immutable list"
      (odra-personal-config-diagnostic-message
       (odra-personal-config-observation-diagnostic malformed)))

     (write-init
      root
      (string-append
       "#lang racket/base\n"
       "(require odra/commands)\n"
       "(provide odra-personal-commands)\n"
       "(define odra-personal-commands\n"
       "  (list (make-command 'describe-key (lambda (_context) (void)))))\n"))
     (define collision (personal-config-load source))
     (check-eq? (odra-personal-config-observation-state collision) 'rejected)
     (check-regexp-match
      #rx"command names must be unique"
      (odra-personal-config-diagnostic-message
       (odra-personal-config-observation-diagnostic collision))))))

  (test-case "bad init language rejects reload"
  (with-root
   (lambda (root)
     (write-init root "#lang racket\n(define x 1)\n")
     (define source (personal-config-source (configuration-root root)))
     (define invalid-language
       (personal-config-reload (personal-config-initialize) 1 source))
     (check-eq? (odra-personal-config-result-status invalid-language) 'rejected)
     (check-eq? (diagnostic-code invalid-language) 'invalid-language)

     (write-init root "#lang racket/base\n(define x\n")
     (define invalid-syntax
       (personal-config-reload (personal-config-initialize) 1 source))
     (check-eq? (odra-personal-config-result-status invalid-syntax) 'rejected)
     (check-eq? (diagnostic-code invalid-syntax) 'invalid-syntax))))

  (test-case "oversized init rejects before read"
  (with-root
   (lambda (root)
     (write-init root "#lang racket/base\n")
     (define source (personal-config-source (configuration-root root)))
     (define result
       (parameterize
           ([current-personal-configuration-file-size
             (lambda (_path) (add1 maximum-personal-configuration-bytes))]
            [current-personal-configuration-read-file
             (lambda (_path) (error 'personal-config-test "read should not run"))])
         (personal-config-reload (personal-config-initialize) 1 source)))
     (check-eq? (odra-personal-config-result-status result) 'rejected)
     (check-eq? (diagnostic-code result) 'size))))

  (test-case "loader faults become rejected diagnostics"
  (with-root
   (lambda (root)
     (write-init root "#lang racket/base\n")
     (define source (personal-config-source (configuration-root root)))
     (define result
       (parameterize
           ([current-personal-configuration-read-file
             (lambda (_path) (error 'personal-config-test "simulated fault"))])
         (personal-config-reload (personal-config-initialize) 1 source)))
     (check-eq? (odra-personal-config-result-status result) 'rejected)
     (check-eq? (diagnostic-code result) 'exception))))

  (test-case "stale reloads preserve generation"
  (with-root
   (lambda (root)
     (write-init root "#lang racket/base\n(define selected-theme 'night)\n")
     (define source (personal-config-source (configuration-root root)))
     (define confirmed
       (personal-config-reload (personal-config-initialize) 1 source))
     (define active (odra-personal-config-result-state confirmed))

     (write-init root "#lang racket/base\n(define broken\n")
     (define rejected (personal-config-reload active 2 source))
     (check-eq? (odra-personal-config-result-status rejected) 'rejected)
     (define preserved (odra-personal-config-result-state rejected))
     (check-equal? (odra-personal-config-state-confirmed-generation preserved) 2)
     (check-equal? (odra-personal-config-state-proposal preserved)
                   (odra-personal-config-state-proposal active))
     (check-equal? (odra-personal-config-state-rejected-generation preserved) 1)

     (define stale (personal-config-reload active 1 source))
     (check-eq? (odra-personal-config-result-status stale) 'rejected)
     (check-eq? (diagnostic-code stale) 'stale-generation)
     (check-equal?
      (odra-personal-config-state-confirmed-generation
       (odra-personal-config-result-state stale))
      2))))
