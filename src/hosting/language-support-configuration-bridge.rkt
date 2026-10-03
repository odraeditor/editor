#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require json
         racket/contract/base
         racket/list
         (prefix-in languages: "../command/languages.rkt"))

(provide
 language-support-configuration-schema-version
 maximum-language-support-configuration-bytes
 (contract-out
  [load-language-support-configuration-value
   (-> any/c languages:odra-language-support-set?)]
  [language-support-configuration-encode
   (-> languages:odra-language-support-set? bytes?)]))

(define language-support-configuration-schema-version 1)
(define maximum-language-support-configuration-bytes (* 128 1024))

(define (load-language-support-configuration-value value)
  (cond
    [(not value) (languages:language-support-set)]
    [(languages:odra-language-support-set? value) value]
    [else
     (raise-arguments-error
      'odra-language-support
      "language support export must be one admitted language-support set")]))

(define (symbol-text value)
  (symbol->string value))

(define (language->jsexpr value)
  (hasheq
   'id (symbol-text (languages:odra-language-id value))
   'display-name (languages:odra-language-display-name value)
   'filenames (languages:odra-language-filenames value)
   'suffixes (languages:odra-language-suffixes value)))

(define (environment->jsexpr value)
  (for/list ([key (in-list (sort (hash-keys value) string<?))])
    (hasheq 'key key 'value (hash-ref value key))))

(define (service->jsexpr value)
  (hasheq
   'id (symbol-text (languages:odra-language-service-id value))
   'display-name (languages:odra-language-service-display-name value)
   'languages (map symbol-text (languages:odra-language-service-languages value))
   'command (languages:odra-language-service-command value)
   'root-markers (languages:odra-language-service-root-markers value)
   'initialization-options
   (languages:odra-language-service-initialization-options value)
   'settings (languages:odra-language-service-settings value)
   'environment
   (environment->jsexpr (languages:odra-language-service-environment value))
   'features (map symbol-text (languages:odra-language-service-features value))
   'enabled (languages:odra-language-service-enabled? value)
   'default (languages:odra-language-service-default? value)))

(define (selections->jsexpr value)
  (for/list ([language-id (in-list (sort (hash-keys value) symbol<?))])
    (hasheq 'language (symbol-text language-id)
            'service (symbol-text (hash-ref value language-id)))))

(define (language-support-configuration-encode configuration)
  (define encoded
    (jsexpr->bytes
     (hasheq
      'schema language-support-configuration-schema-version
      'languages
      (map language->jsexpr
           (languages:odra-language-support-set-languages configuration))
      'services
      (map service->jsexpr
           (languages:odra-language-support-set-services configuration))
      'selections
      (selections->jsexpr
       (languages:odra-language-support-set-selections configuration)))))
  (when (> (bytes-length encoded) maximum-language-support-configuration-bytes)
    (raise-arguments-error
     'odra-language-support
     "encoded language support exceeds the admitted byte bound"))
  (bytes->immutable-bytes encoded))

(module+ test
  (require rackunit)

  (define configured
    (languages:language-support
     #:language 'rust
     #:suffixes '(".rs")
     #:server
     (languages:language-service
      #:id 'rust-analyzer
      #:command '("rust-analyzer")
      #:root-markers '("Cargo.toml"))))
  (define encoded (language-support-configuration-encode configured))
  (define decoded (bytes->jsexpr encoded))
  (check-equal? (hash-ref decoded 'schema) 1)
  (check-equal? (hash-ref (car (hash-ref decoded 'languages)) 'id) "rust")
  (check-equal? (hash-ref (car (hash-ref decoded 'services)) 'languages)
                '("rust"))
  (check-equal?
   (bytes->jsexpr
    (language-support-configuration-encode
     (load-language-support-configuration-value #f)))
   '#hasheq((languages . ()) (schema . 1) (selections . ()) (services . ())))
  (check-exn exn:fail?
             (lambda () (load-language-support-configuration-value 'invalid))))
