#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         racket/path
         "../../src/command/languages.rkt"
         "../../src/configuration/personal.rkt"
         "../../src/hosting/language-support-configuration-bridge.rkt"
         "../../src/hosting/personal-configuration-bridge.rkt")

(define (with-root action)
  (define root (make-temporary-file "odra-language-support-~a" 'directory))
  (dynamic-wind void (lambda () (action root))
                (lambda () (delete-directory/files root))))

(define (write-module root relative content)
  (define path (build-path root relative))
  (make-directory* (path-only path))
  (call-with-output-file path
    (lambda (output) (display content output))
    #:exists 'truncate/replace))

(define (write-init root content)
  (write-module root "init.rkt" content))

(define (load-root root)
  (personal-config-load (personal-config-source root)))

(define startup-schema-version 10)

(define (word bytes offset)
  (integer-bytes->integer bytes #f #f offset (+ offset 8)))

(test-case "absent support confirms an empty payload"
  (with-root
   (lambda (root)
     (write-init root "#lang racket/base\n")
     (define observation (load-root root))
     (check-eq? (odra-personal-config-observation-state observation) 'confirmed)
     (check-false
      (personal-config-observation-export observation 'odra-language-support #f))
     (define startup (runtime-personal-configuration-startup-batch (path->bytes root)))
     (check-true (car startup))
     (define batch (cadr startup))
     (check-equal? (word batch 0) startup-schema-version)
     (check-true (positive? (word batch 344))))))

(test-case "minimal support confirms defaults"
  (with-root
   (lambda (root)
     (write-init
      root
      (string-append
       "#lang racket/base\n"
       "(require odra/languages)\n"
       "(provide odra-language-support)\n"
       "(define odra-language-support\n"
       "  (language-support\n"
       "   #:language 'rust #:suffixes '(\".rs\")\n"
       "   #:server (language-service #:id 'rust-analyzer\n"
       "             #:command '(\"rust-analyzer\"))))\n"))
     (define observation (load-root root))
     (check-eq? (odra-personal-config-observation-state observation) 'confirmed)
     (define support
       (personal-config-observation-export observation 'odra-language-support))
     (define service (car (odra-language-support-set-services support)))
     (check-equal? (odra-language-service-languages service) '(rust))
     (check-equal? (odra-language-service-features service)
                   '(diagnostics completion))
     (check-true (odra-language-service-default? service)))))

(test-case "modular support composes several languages"
  (with-root
   (lambda (root)
     (write-module
      root
      "languages/racket.rkt"
      (string-append
       "#lang racket/base\n"
       "(require odra/languages)\n"
       "(provide racket-language racket-service)\n"
       "(define racket-language (language #:id 'racket #:suffixes '(\".rkt\")))\n"
       "(define racket-service\n"
       "  (language-service #:id 'racket-langserver #:languages '(racket)\n"
       "                    #:command '(\"racket\" \"-l\" \"racket-langserver\")))\n"))
     (write-init
      root
      (string-append
       "#lang racket/base\n"
       "(require odra/languages \"languages/racket.rkt\")\n"
       "(provide odra-language-support)\n"
       "(define odra-language-support\n"
       "  (language-support-set\n"
       "   #:languages (list racket-language (language #:id 'rust #:suffixes '(\".rs\")))\n"
       "   #:services (list racket-service\n"
       "                    (language-service #:id 'rust-analyzer #:languages '(rust)\n"
       "                                      #:command '(\"rust-analyzer\")))))\n"))
     (define observation (load-root root))
     (check-eq? (odra-personal-config-observation-state observation) 'confirmed)
     (define support
       (personal-config-observation-export observation 'odra-language-support))
     (check-equal? (length (odra-language-support-set-languages support)) 2)
     (check-equal? (length (odra-language-support-set-services support)) 2))))

(test-case "invalid support rejects sibling exports"
  (with-root
   (lambda (root)
     (write-init
      root
      (string-append
       "#lang racket/base\n"
       "(require odra/languages)\n"
       "(provide odra-language-support odra-status-bar-configuration)\n"
       "(define odra-status-bar-configuration '#hash((position . line-column)))\n"
       "(define odra-language-support\n"
       "  (language-support #:language 'rust #:suffixes '(\"rs\")))\n"))
     (define observation (load-root root))
     (check-eq? (odra-personal-config-observation-state observation) 'rejected)
     (check-false
      (personal-config-observation-export
       observation 'odra-status-bar-configuration #f)))))

(test-case "duplicates conflicts and excess are rejected"
  (check-exn
   exn:fail?
   (lambda ()
     (language-support-set
      #:languages (list (language #:id 'rust) (language #:id 'rust)))))
  (check-exn
   exn:fail?
   (lambda ()
     (language-support
      #:language 'rust
      #:servers
      (list (language-service #:id 'server #:command '("first"))
            (language-service #:id 'server #:command '("second"))))))
  (check-exn
   exn:fail?
   (lambda ()
     (language-support-set
      #:languages
      (for/list ([index (in-range 33)])
        (language #:id (string->symbol (format "language-~a" index))))))))

(test-case "reload rejection preserves confirmed support"
  (with-root
   (lambda (root)
     (define source (personal-config-source root))
     (write-init
      root
      (string-append
       "#lang racket/base\n"
       "(require odra/languages)\n"
       "(provide odra-language-support)\n"
       "(define odra-language-support (language-support #:language 'rust))\n"))
     (define confirmed (personal-config-reload (personal-config-initialize) 1 source))
     (define active (odra-personal-config-result-state confirmed))
     (write-init
      root
      (string-append
       "#lang racket/base\n"
       "(require odra/languages)\n"
       "(provide odra-language-support)\n"
       "(define odra-language-support\n"
       "  (language-support #:language 'rust #:selected-service 'missing))\n"))
     (define rejected (personal-config-reload active 2 source))
     (check-eq? (odra-personal-config-result-status rejected) 'rejected)
     (check-equal?
      (odra-personal-config-state-proposal
       (odra-personal-config-result-state rejected))
      (odra-personal-config-state-proposal active))
     (define stale (personal-config-reload active 1 source))
     (check-eq? (odra-personal-config-result-status stale) 'rejected)
     (check-equal?
      (odra-personal-config-state-confirmed-generation
       (odra-personal-config-result-state stale))
      2))))

(test-case "Racket exceptions reject support generation"
  (with-root
   (lambda (root)
     (write-init
      root
      (string-append
       "#lang racket/base\n"
       "(require odra/languages)\n"
       "(provide odra-language-support)\n"
       "(define odra-language-support (error 'init \"fixture failure\"))\n"))
     (define observation (load-root root))
     (check-eq? (odra-personal-config-observation-state observation) 'rejected)
     (check-regexp-match
      #rx"fixture failure"
      (odra-personal-config-diagnostic-message
       (odra-personal-config-observation-diagnostic observation))))))

(test-case "bridge rejects support beyond copied width"
  (with-root
   (lambda (root)
     (write-init
      root
      (string-append
       "#lang racket/base\n"
       "(require odra/languages)\n"
       "(provide odra-language-support)\n"
       "(define odra-language-support\n"
       "  (language-support-set\n"
       "   #:languages (list (language #:id 'rust))\n"
       "   #:services\n"
       "   (list (language-service #:id 'server #:languages '(rust)\n"
       "          #:command '(\"server\")\n"
       "          #:settings (hasheq 'payload (make-string 140000 #\\x))))))\n"))
     (define observation (load-root root))
     (check-eq? (odra-personal-config-observation-state observation) 'rejected)
     (check-regexp-match
      #rx"encoded language support"
      (odra-personal-config-diagnostic-message
       (odra-personal-config-observation-diagnostic observation))))))

(test-case "encoded support is immutable and bounded"
  (define support
    (language-support
     #:language 'rust
     #:server (language-service #:id 'server #:command '("server"))))
  (define encoded (language-support-configuration-encode support))
  (check-true (immutable? encoded))
  (check-true (<= (bytes-length encoded)
                  maximum-language-support-configuration-bytes)))
