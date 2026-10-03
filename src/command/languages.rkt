#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require json
         racket/contract/base
         racket/list
         racket/string)

(provide
 language-feature?
 (struct-out odra-language)
 (struct-out odra-language-service)
 (struct-out odra-language-support-set)
 (contract-out
  [language
   (->* (#:id symbol?)
        (#:display-name (or/c #f string?)
         #:filenames any/c
         #:suffixes any/c)
        odra-language?)]
  [language-service
   (->* (#:id symbol? #:command any/c)
        (#:display-name (or/c #f string?)
         #:languages any/c
         #:root-markers any/c
         #:initialization-options any/c
         #:settings any/c
         #:environment any/c
         #:features any/c
         #:enabled? boolean?
         #:default? boolean?)
        odra-language-service?)]
  [language-support
   (->* (#:language symbol?)
        (#:display-name (or/c #f string?)
         #:filenames any/c
         #:suffixes any/c
         #:server (or/c #f odra-language-service?)
         #:servers any/c
         #:selected-service (or/c #f symbol?))
        odra-language-support-set?)]
  [language-support-set
   (->* ()
        (#:languages any/c
         #:services any/c
         #:selections any/c)
        odra-language-support-set?)]))

(define maximum-languages 32)
(define maximum-services 64)
(define maximum-selections 64)
(define maximum-language-identity-bytes 64)
(define maximum-service-identity-bytes 96)
(define maximum-display-name-bytes 96)
(define maximum-filenames 8)
(define maximum-suffixes 8)
(define maximum-selectors 16)
(define maximum-selector-bytes 32)
(define maximum-command-parts 64)
(define maximum-command-bytes (* 64 1024))
(define maximum-executable-bytes (* 4 1024))
(define maximum-root-markers 16)
(define maximum-root-marker-bytes (* 4 1024))
(define maximum-root-markers-bytes (* 16 1024))
(define maximum-environment-entries 64)
(define maximum-environment-bytes (* 64 1024))
(define maximum-json-depth 64)
(define maximum-json-values 65536)
(define maximum-json-bytes (* 1024 1024))
(define maximum-features 16)
(define admitted-language-features
  '(diagnostics completion navigation hover references symbols signature-help
                rename formatting semantic-tokens code-actions))

(define (configuration-error who message)
  (raise-arguments-error who message))

(define (text-has-nul? value)
  (for/or ([character (in-string value)]) (char=? character #\nul)))

(define (bounded-text? value maximum #:empty? [empty? #f])
  (and (string? value)
       (or empty? (positive? (string-length value)))
       (not (text-has-nul? value))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (bounded-symbol? value maximum)
  (and (symbol? value)
       (bounded-text? (symbol->string value) maximum)))

(define (immutable-proper-list? value)
  (list? value))

(define (copy-list values copy-value)
  (for/list ([value (in-list values)]) (copy-value value)))

(define (duplicate? values [same? equal?])
  (not (= (length values) (length (remove-duplicates values same?)))))

(define (language-feature? value)
  (and (memq value admitted-language-features) #t))

(define (display-name-value who identity display-name)
  (define value (or display-name (symbol->string identity)))
  (unless (bounded-text? value maximum-display-name-bytes)
    (configuration-error who "display name must be non-empty bounded UTF-8 text"))
  (string->immutable-string value))

(define (filename? value)
  (and (bounded-text? value maximum-selector-bytes)
       (not (member value '("." "..")))
       (not (regexp-match? #rx"[/\\\\]" value))))

(define (suffix? value)
  (and (bounded-text? value maximum-selector-bytes)
       (> (string-length value) 1)
       (char=? (string-ref value 0) #\.)
       (not (regexp-match? #rx"[/\\\\]" value))))

(define (selector-list who field values predicate maximum)
  (unless (and (immutable-proper-list? values)
               (<= (length values) maximum)
               (andmap predicate values)
               (not (duplicate? values string=?)))
    (configuration-error
     who
     (format "~a must be an immutable bounded list of unique valid selectors" field)))
  (copy-list values string->immutable-string))

(define (root-marker? value)
  (and (bounded-text? value maximum-root-marker-bytes)
       (not (regexp-match? #rx"^(?:[/\\\\]|[A-Za-z]:)" value))
       (not (regexp-match? #rx"[*?\\[\\]{}]" value))
       (not (for/or ([part (in-list (regexp-split #rx"[/\\\\]" value))])
              (or (string=? part "") (string=? part ".."))))))

(define (root-marker-list values)
  (unless (and (immutable-proper-list? values)
               (<= (length values) maximum-root-markers)
               (andmap root-marker? values)
               (not (duplicate? values string=?))
               (<= (for/sum ([value (in-list values)])
                     (bytes-length (string->bytes/utf-8 value)))
                   maximum-root-markers-bytes))
    (configuration-error
     'language-service
     "root markers must be an immutable bounded list of unique relative paths"))
  (copy-list values string->immutable-string))

(define (identity-list who values #:empty? [empty? #f])
  (unless (and (immutable-proper-list? values)
               (or empty? (pair? values))
               (<= (length values) maximum-languages)
               (andmap (lambda (value)
                         (bounded-symbol? value maximum-language-identity-bytes))
                       values)
               (not (duplicate? values eq?)))
    (configuration-error
     who
     "languages must be an immutable bounded list of unique language identities"))
  (copy-list values (lambda (value) value)))

(define (command-list values)
  (unless (and (immutable-proper-list? values)
               (pair? values)
               (<= (length values) maximum-command-parts)
               (andmap (lambda (value)
                         (bounded-text? value maximum-command-bytes #:empty? #t))
                       values)
               (bounded-text? (car values) maximum-executable-bytes)
               (<= (for/sum ([value (in-list values)])
                     (bytes-length (string->bytes/utf-8 value)))
                   maximum-command-bytes))
    (configuration-error
     'language-service
     "command must be an immutable non-empty bounded list of strings"))
  (copy-list values string->immutable-string))

(define (environment-map value)
  (unless (and (hash? value)
               (immutable? value)
               (<= (hash-count value) maximum-environment-entries)
               (for/and ([(key entry) (in-hash value)])
                 (and (bounded-text? key maximum-environment-bytes)
                      (not (string-contains? key "="))
                      (bounded-text? entry maximum-environment-bytes #:empty? #t)))
               (<= (for/sum ([(key entry) (in-hash value)])
                     (+ (bytes-length (string->bytes/utf-8 key))
                        1
                        (bytes-length (string->bytes/utf-8 entry))))
                   maximum-environment-bytes))
    (configuration-error
     'language-service
     "environment must be an immutable bounded mapping of strings to strings"))
  (make-immutable-hash
   (for/list ([(key entry) (in-hash value)])
     (cons (string->immutable-string key) (string->immutable-string entry)))))

(define (json-value-copy who value)
  (define values-seen 0)
  (define (copy value depth)
    (set! values-seen (add1 values-seen))
    (when (or (> depth maximum-json-depth)
              (> values-seen maximum-json-values))
      (configuration-error who "JSON value exceeds bounded depth or value count"))
    (cond
      [(or (eq? value 'null) (boolean? value)) value]
      [(string? value) (string->immutable-string value)]
      [(and (number? value) (jsexpr? value))
       value]
      [(list? value)
       (copy-list value (lambda (entry) (copy entry (add1 depth))))]
      [(hash? value)
       (unless (immutable? value)
         (configuration-error who "JSON objects must be immutable mappings"))
       (unless (for/and ([key (in-hash-keys value)]) (symbol? key))
         (configuration-error who "JSON object keys must be symbols"))
       (make-immutable-hasheq
        (for/list ([(key entry) (in-hash value)])
          (cons key (copy entry (add1 depth)))))]
      [else
       (configuration-error who "expected a bounded immutable JSON value")]))
  (define copied (copy value 1))
  (unless (jsexpr? copied)
    (configuration-error who "expected a bounded immutable JSON value"))
  copied)

(define (json-profile-values initialization-options settings)
  (define copied-initialization
    (json-value-copy 'language-service initialization-options))
  (define copied-settings (json-value-copy 'language-service settings))
  (define byte-count
    (+ (bytes-length (jsexpr->bytes copied-initialization))
       (bytes-length (jsexpr->bytes copied-settings))))
  (when (> byte-count maximum-json-bytes)
    (configuration-error 'language-service "JSON profile exceeds the admitted byte bound"))
  (values copied-initialization copied-settings))

(define (feature-list values)
  (unless (and (immutable-proper-list? values)
               (<= (length values) maximum-features)
               (andmap language-feature? values)
               (not (duplicate? values eq?)))
    (configuration-error
     'language-service
     "features must be an immutable bounded list of unique known feature identities"))
  (copy-list values (lambda (value) value)))

(struct odra-language (id display-name filenames suffixes)
  #:transparent
  #:guard
  (lambda (id display-name filenames suffixes _)
    (unless (bounded-symbol? id maximum-language-identity-bytes)
      (configuration-error 'odra-language "id must be a non-empty bounded symbol"))
    (define copied-filenames
      (selector-list 'odra-language 'filenames filenames filename? maximum-filenames))
    (define copied-suffixes
      (selector-list 'odra-language 'suffixes suffixes suffix? maximum-suffixes))
    (when (> (+ (length copied-filenames) (length copied-suffixes)) maximum-selectors)
      (configuration-error 'odra-language "language selector count exceeds the admitted bound"))
    (values id (display-name-value 'odra-language id display-name)
            copied-filenames copied-suffixes)))

(struct odra-language-service
  (id display-name languages command root-markers initialization-options settings
      environment features enabled? default?)
  #:transparent
  #:guard
  (lambda (id display-name languages command root-markers initialization-options settings
              environment features enabled? default? _)
    (unless (bounded-symbol? id maximum-service-identity-bytes)
      (configuration-error 'odra-language-service
                           "id must be a non-empty bounded symbol"))
    (define copied-languages
      (identity-list 'odra-language-service languages #:empty? #t))
    (define-values (copied-initialization copied-settings)
      (json-profile-values initialization-options settings))
    (values id
            (display-name-value 'odra-language-service id display-name)
            copied-languages
            (command-list command)
            (root-marker-list root-markers)
            copied-initialization
            copied-settings
            (environment-map environment)
            (feature-list features)
            enabled?
            default?)))

(struct odra-language-support-set (languages services selections)
  #:transparent
  #:guard
  (lambda (languages services selections _)
    (unless (and (immutable-proper-list? languages)
                 (<= (length languages) maximum-languages)
                 (andmap odra-language? languages)
                 (not (duplicate? (map odra-language-id languages) eq?)))
      (configuration-error
       'odra-language-support-set
       "languages must be an immutable bounded list with unique identities"))
    (unless (and (immutable-proper-list? services)
                 (<= (length services) maximum-services)
                 (andmap odra-language-service? services)
                 (andmap (lambda (service)
                           (pair? (odra-language-service-languages service)))
                         services)
                 (not (duplicate? (map odra-language-service-id services) eq?)))
      (configuration-error
       'odra-language-support-set
       "services must be an immutable bounded list with unique identities and languages"))
    (unless (and (hash? selections)
                 (immutable? selections)
                 (<= (hash-count selections) maximum-selections)
                 (for/and ([(language-id service-id) (in-hash selections)])
                   (and (bounded-symbol? language-id maximum-language-identity-bytes)
                        (bounded-symbol? service-id maximum-service-identity-bytes))))
      (configuration-error
       'odra-language-support-set
       "selections must be an immutable bounded mapping of language to service identities"))
    (values (copy-list languages values)
            (copy-list services values)
            (make-immutable-hasheq (hash->list selections)))))

;; language constructs one immutable language definition.
(define (language #:id id
                  #:display-name [display-name #f]
                  #:filenames [filenames '()]
                  #:suffixes [suffixes '()])
  (odra-language id display-name filenames suffixes))

;; language-service constructs one immutable data-only server definition.
(define (language-service #:id id
                          #:display-name [display-name #f]
                          #:languages [languages '()]
                          #:command command
                          #:root-markers [root-markers '()]
                          #:initialization-options [initialization-options (hasheq)]
                          #:settings [settings (hasheq)]
                          #:environment [environment (hash)]
                          #:features [features '(diagnostics completion)]
                          #:enabled? [enabled? #t]
                          #:default? [default? #f])
  (odra-language-service
   id display-name languages command root-markers initialization-options settings
   environment features enabled? default?))

(define (service-with-language service language-id only-server?)
  (define languages (odra-language-service-languages service))
  (unless (or (null? languages) (equal? languages (list language-id)))
    (configuration-error
     'language-support
     "a nested service may name only its surrounding language"))
  (struct-copy
   odra-language-service service
   [languages (list language-id)]
   [default? (if only-server? #t (odra-language-service-default? service))]))

;; language-support composes one language and its directly associated services.
(define (language-support #:language language-id
                          #:display-name [display-name #f]
                          #:filenames [filenames '()]
                          #:suffixes [suffixes '()]
                          #:server [server #f]
                          #:servers [servers '()]
                          #:selected-service [selected-service #f])
  (when (and server (pair? servers))
    (configuration-error 'language-support "server and servers are mutually exclusive"))
  (unless (and (immutable-proper-list? servers)
               (<= (length servers) maximum-services)
               (andmap odra-language-service? servers))
    (configuration-error
     'language-support
     "servers must be an immutable bounded list of language services"))
  (define supplied-services (if server (list server) servers))
  (define nested-services
    (for/list ([service (in-list supplied-services)])
      (service-with-language service language-id (= (length supplied-services) 1))))
  (when (duplicate? (map odra-language-service-id nested-services) eq?)
    (configuration-error 'language-support "nested service identities must be unique"))
  (when selected-service
    (define selected
      (findf (lambda (service)
               (eq? selected-service (odra-language-service-id service)))
             nested-services))
    (unless (and selected (odra-language-service-enabled? selected))
      (configuration-error
       'language-support
       "selected service must name one nested enabled service")))
  (odra-language-support-set
   (list (language #:id language-id
                   #:display-name display-name
                   #:filenames filenames
                   #:suffixes suffixes))
   nested-services
   (if selected-service (hasheq language-id selected-service) (hasheq))))

;; language-support-set composes one complete immutable contribution source.
(define (language-support-set #:languages [languages '()]
                              #:services [services '()]
                              #:selections [selections (hasheq)])
  (odra-language-support-set languages services selections))

(module+ test
  (require rackunit)

  (define rust-service
    (language-service
     #:id 'rust-analyzer
     #:languages '(rust)
     #:command '("rust-analyzer")
     #:root-markers '("Cargo.toml")
     #:environment (hash "RUST_BACKTRACE" "1")))
  (define rust-support
    (language-support
     #:language 'rust
     #:suffixes '(".rs")
     #:server rust-service
     #:selected-service 'rust-analyzer))
  (check-equal? (map odra-language-id
                     (odra-language-support-set-languages rust-support))
                '(rust))
  (check-equal? (odra-language-service-languages
                 (car (odra-language-support-set-services rust-support)))
                '(rust))
  (check-true (odra-language-service-default?
               (car (odra-language-support-set-services rust-support))))
  (check-true (immutable? (odra-language-service-environment rust-service)))
  (check-true (immutable? (odra-language-service-initialization-options rust-service)))
  (check-true (language-feature? 'diagnostics))
  (check-false (language-feature? 'unknown))

  (define modular
    (language-support-set
     #:languages
     (list (language #:id 'rust #:suffixes '(".rs"))
           (language #:id 'racket #:suffixes '(".rkt")))
     #:services
     (list rust-service
           (language-service
            #:id 'racket-langserver
            #:languages '(racket)
            #:command '("racket" "-l" "racket-langserver")))
     #:selections (hasheq 'racket 'racket-langserver)))
  (check-equal? (length (odra-language-support-set-languages modular)) 2)
  (check-equal? (hash-ref (odra-language-support-set-selections modular) 'racket)
                'racket-langserver)

  (check-exn exn:fail?
             (lambda () (language #:id 'bad #:suffixes '("rs"))))
  (check-exn exn:fail?
             (lambda ()
               (language-service #:id 'bad #:command '("server")
                                 #:features '(unknown))))
  (check-exn exn:fail?
             (lambda ()
               (language-service #:id 'bad #:command '("server")
                                 #:environment (make-hash))))
  (check-exn exn:fail?
             (lambda ()
               (language-support
                #:language 'rust
                #:server rust-service
                #:servers (list rust-service))))
  (check-exn exn:fail?
             (lambda ()
               (language-support
                #:language 'rust
                #:server (language-service
                          #:id 'shared
                          #:languages '(racket)
                          #:command '("server")))))
  (check-exn exn:fail?
             (lambda ()
               (language-support
                #:language 'rust
                #:server (language-service #:id 'disabled #:command '("server")
                                           #:enabled? #f)
                #:selected-service 'disabled))))
