#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/path
         rackunit
         "../../src/command/catalog.rkt"
         "../../src/configuration/personal.rkt"
         "../../src/hosting/command-catalog-bridge.rkt"
         "../../src/hosting/status-bar-bridge.rkt"
         (submod "../../src/hosting/command-catalog-bridge.rkt" test-support))

(define (with-configuration action)
  (define root (make-temporary-file "odra-personal-commands-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define configuration-root (build-path root "config" "odra"))
     (make-directory* configuration-root)
     (action configuration-root))
   (lambda () (delete-directory/files root))))

(define (write-module configuration-root relative-path content)
  (define path (build-path configuration-root relative-path))
  (make-directory* (path-only path))
  (call-with-output-file path
    (lambda (output) (display content output))
    #:exists 'truncate/replace))

(define (command-count batch)
  (integer-bytes->integer batch #f #f 32 40))

  (test-case "modular commands form inactive candidate"
  (with-configuration
   (lambda (configuration-root)
     (write-module
      configuration-root
      "modules/unselected.rkt"
      "#lang racket/base\n(error 'unselected \"module must not be scanned\")\n")
     (write-module
      configuration-root
      "modules/text.rkt"
      (string-append
       "#lang racket/base\n"
       "(require odra/commands)\n"
       "(provide selected-commands)\n"
       "(define selected-commands\n"
       "  (list\n"
       "   (make-command\n"
       "    'normalize-heading\n"
       "    (lambda (context)\n"
       "      (define selection (command-context-active-region context))\n"
       "      (when selection\n"
       "        (command-context-replace!\n"
       "         context selection\n"
       "         (string-upcase (command-context-read context selection)))))\n"
       "    #:description \"Normalize the active heading.\"\n"
       "    #:source \"modules/text.rkt\"\n"
       "    #:location \"7:3\")))\n"))
     (write-module
      configuration-root
      "init.rkt"
      (string-append
       "#lang racket/base\n"
       "(require \"modules/text.rkt\")\n"
       "(provide odra-personal-commands odra-status-bar-configuration)\n"
       "(define odra-personal-commands selected-commands)\n"
       "(define odra-status-bar-configuration\n"
       "  (hash 'position 'line-column))\n"))

     (define observation
       (personal-config-load (personal-config-source configuration-root)))
     (check-eq? (odra-personal-config-observation-state observation) 'confirmed)
     (define definitions
       (personal-config-observation-export observation 'odra-personal-commands))
     (check-equal? (map odra-command-definition-name definitions)
                   '("normalize-heading"))
     (check-equal?
      (odra-command-source-source
       (odra-command-definition-provenance (car definitions)))
      "modules/text.rkt")

     (define status-result
       (load-status-bar-startup-value
        (personal-config-observation-export
         observation 'odra-status-bar-configuration)))
     (check-eq? (status-bar-startup-result-status status-result) 'confirmed)

     (define candidate
       (compose-personal-command-catalog 2 definitions))
     (define first-copy (command-catalog-batch 19 candidate))
     (define second-copy (command-catalog-batch 19 candidate))
     (check-equal? first-copy second-copy)
     (check-equal? (bytes-length first-copy)
                   (integer-bytes->integer first-copy #f #f 8 16))
     (check-equal? (command-count first-copy) 8)

     (define active-factory-copy (caddr (runtime-command-catalog-batch 19)))
     (check-equal? (command-count active-factory-copy) 7)
     (check-false
      (car (runtime-command-dispatch
            #"normalize-heading" 1 1 0 0))))))

  (test-case "rejection preserves confirmed proposal"
  (with-configuration
   (lambda (configuration-root)
     (write-module
      configuration-root
      "init.rkt"
      (string-append
       "#lang racket/base\n"
       "(require odra/commands)\n"
       "(provide odra-personal-commands)\n"
       "(define odra-personal-commands\n"
       "  (list (make-command 'private-note (lambda (_context) (void)))))\n"))
     (define source (personal-config-source configuration-root))
     (define confirmed
       (personal-config-reload (personal-config-initialize) 1 source))
     (check-eq? (odra-personal-config-result-status confirmed) 'confirmed)
     (define active (odra-personal-config-result-state confirmed))

     (write-module
      configuration-root
      "init.rkt"
      (string-append
       "#lang racket/base\n"
       "(require odra/commands)\n"
       "(provide odra-personal-commands)\n"
       "(define odra-personal-commands\n"
       "  (list (make-command 'describe-key (lambda (_context) (void)))))\n"))
     (define rejected (personal-config-reload active 2 source))
     (check-eq? (odra-personal-config-result-status rejected) 'rejected)
     (define preserved (odra-personal-config-result-state rejected))
     (check-equal? (odra-personal-config-state-confirmed-generation preserved) 2)
     (check-eq? (odra-personal-config-state-proposal preserved)
                (odra-personal-config-state-proposal active))
     (check-equal?
      (map odra-command-definition-name
           (personal-config-proposal-export
            (odra-personal-config-state-proposal preserved)
            'odra-personal-commands))
      '("private-note")))))
