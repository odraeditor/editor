#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/match
         racket/string
         "../package/authority-contract.rkt"
         (only-in "languages.rkt"
                  language
                  language-service
                  odra-language?
                  odra-language-id
                  odra-language-service?
                  odra-language-service-id))

(provide
 language
 language-service
 language-bundle-value?
 (struct-out odra-language-bundle-authority)
 (struct-out odra-language-bundle-dependency)
 (struct-out odra-language-bundle-artifact)
 (struct-out odra-language-injection)
 (struct-out odra-tree-sitter-syntax-provider)
 (struct-out odra-language-formatter)
 (struct-out odra-language-command)
 (struct-out odra-language-keymap)
 (struct-out odra-language-support-bundle)
 (contract-out
  [language-bundle-authority
   (-> symbol? odra-language-bundle-authority?)]
  [language-bundle-dependency
   (->* (#:id symbol? #:minimum string? #:maximum string?)
        (#:optional? boolean? #:facets any/c #:targets any/c)
        odra-language-bundle-dependency?)]
  [language-bundle-artifact
   (->* (#:id symbol? #:kind symbol? #:path string? #:sha256 string?
         #:size exact-nonnegative-integer? #:targets any/c)
        (#:authority (or/c #f symbol?))
        odra-language-bundle-artifact?)]
  [language-injection
   (->* (#:language symbol? #:query-artifact symbol?)
        (#:combined? boolean?)
        odra-language-injection?)]
  [tree-sitter-syntax-provider
   (->* (#:id symbol? #:languages any/c #:grammar-artifact symbol? #:grammar-symbol string?)
        (#:abi-min exact-nonnegative-integer?
         #:abi-max exact-nonnegative-integer?
         #:query-artifacts any/c
         #:captures any/c
         #:injections any/c
         #:resource-profile symbol?
         #:authority symbol?)
        odra-tree-sitter-syntax-provider?)]
  [language-formatter
   (->* (#:id symbol? #:languages any/c #:kind symbol?)
        (#:service (or/c #f symbol?)
         #:command any/c
         #:root-markers any/c
         #:scopes any/c
         #:input symbol?
         #:output symbol?
         #:timeout-ms exact-positive-integer?
         #:output-limit exact-positive-integer?)
        odra-language-formatter?)]
  [language-command
   (->* (#:id symbol? #:description string? #:implementation symbol?)
        (#:requirements any/c
         #:effects any/c
         #:availability symbol?
         #:provenance string?
         #:replaces (or/c #f symbol?))
        odra-language-command?)]
  [language-keymap
   (->* (#:id symbol? #:languages any/c #:bindings any/c)
        (#:states any/c
         #:context symbol?
         #:priority exact-integer?
         #:remaps any/c
         #:before any/c
         #:after any/c
         #:provenance string?)
        odra-language-keymap?)]
  [language-support-bundle
   (->* (#:id symbol?
         #:display-name string?
         #:version string?
         #:api-min string?
         #:api-max string?
         #:description string?
         #:publisher symbol?
         #:source symbol?
         #:targets any/c)
        (#:format-version exact-positive-integer?
         #:license string?
         #:dependencies any/c
         #:authorities any/c
         #:languages any/c
         #:syntax-providers any/c
         #:services any/c
         #:formatters any/c
         #:commands any/c
         #:keymaps any/c
         #:artifacts any/c
         #:entrypoint (or/c #f string?)
         #:provenance string?)
        odra-language-support-bundle?)]))

(define maximum-identity-bytes 96)
(define maximum-display-name-bytes 128)
(define maximum-description-bytes 4096)
(define maximum-path-bytes 4096)
(define maximum-provenance-bytes 256)
(define maximum-dependencies 256)
(define maximum-artifacts 1024)
(define maximum-contributions 640)
(define maximum-targets 16)
(define maximum-references 8192)
(define maximum-timeout-ms 600000)
(define maximum-output-bytes (* 64 1024 1024))
(define maximum-artifact-bytes (expt 2 40))

(define admitted-platforms '(darwin linux windows))
(define admitted-architectures '(aarch64 x86-64))
(define admitted-artifact-kinds
  '(data documentation executable license manifest query racket-module
         tree-sitter-grammar))
(define admitted-resource-profiles '(ordinary demanding boundary))
(define admitted-formatter-kinds '(command language-service racket))
(define admitted-formatter-scopes '(buffer range))
(define admitted-formatter-inputs '(file standard-input text))
(define admitted-formatter-outputs '(file standard-output text-edits))

(define (bundle-error who message)
  (raise-arguments-error who message))

(define (bounded-text? value maximum #:empty? [empty? #f])
  (and (string? value)
       (or empty? (positive? (string-length value)))
       (not (string-contains? value (string #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (bounded-symbol? value)
  (and (symbol? value)
       (bounded-text? (symbol->string value) maximum-identity-bytes)
       (regexp-match? #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$"
                      (symbol->string value))))

(define (semantic-version? value)
  (and (bounded-text? value maximum-identity-bytes)
       (regexp-match?
        #px"^(?:0|[1-9][0-9]*)\\.(?:0|[1-9][0-9]*)\\.(?:0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*)?$"
        value)))

(define (relative-path? value)
  (and (bounded-text? value maximum-path-bytes)
       (not (regexp-match? #px"^(?:/|\\\\|[A-Za-z]:)" value))
       (for/and ([part (in-list (string-split value "/"))])
         (not (member part '("" "." ".."))))))

(define (unique-list? values [same? equal?])
  (and (list? values)
       (= (length values) (length (remove-duplicates values same?)))))

(define (copy-string value)
  (string->immutable-string value))

(define (copy-list values copy-value)
  (for/list ([value (in-list values)]) (copy-value value)))

(define (symbol-list who field values #:maximum [maximum maximum-references]
                     #:admitted [admitted #f] #:empty? [empty? #t])
  (unless (and (unique-list? values eq?)
               (or empty? (pair? values))
               (<= (length values) maximum)
               (andmap bounded-symbol? values)
               (or (not admitted)
                   (andmap (lambda (value) (and (memq value admitted) #t)) values)))
    (bundle-error who (format "~a must be a bounded list of unique admitted symbols" field)))
  (copy-list values (lambda (value) value)))

(define (string-list who field values #:maximum [maximum maximum-references]
                     #:path? [path? #f])
  (define valid? (if path? relative-path? (lambda (value) (bounded-text? value maximum-path-bytes))))
  (unless (and (unique-list? values string=?)
               (<= (length values) maximum)
               (andmap valid? values))
    (bundle-error who (format "~a must be a bounded list of unique valid strings" field)))
  (copy-list values copy-string))

(define (target? value)
  (match value
    [(list platform architecture)
     (and (memq platform admitted-platforms)
          (memq architecture admitted-architectures)
          #t)]
    [_ #f]))

(define (target-list who values)
  (unless (and (unique-list? values equal?)
               (pair? values)
               (<= (length values) maximum-targets)
               (andmap target? values))
    (bundle-error who "targets must be a bounded list of unique (platform architecture) pairs"))
  (for/list ([target (in-list values)])
    (list (car target) (cadr target))))

(define (command-vector who values)
  (unless (and (list? values)
               (<= (length values) 64)
               (andmap (lambda (value) (bounded-text? value maximum-path-bytes #:empty? #t))
                       values))
    (bundle-error who "command must be a bounded list of strings"))
  (copy-list values copy-string))

(struct odra-language-bundle-authority (id)
  #:transparent
  #:guard
  (lambda (id _)
    (unless (package-authority? id)
      (bundle-error 'odra-language-bundle-authority "unknown bundle authority"))
    id))

(struct odra-language-bundle-dependency
  (id minimum maximum optional? facets targets)
  #:transparent
  #:guard
  (lambda (id minimum maximum optional? facets targets _)
    (unless (bounded-symbol? id)
      (bundle-error 'odra-language-bundle-dependency "id must be a stable bounded symbol"))
    (unless (and (semantic-version? minimum) (semantic-version? maximum))
      (bundle-error 'odra-language-bundle-dependency "versions must use semantic version syntax"))
    (values id (copy-string minimum) (copy-string maximum) optional?
            (symbol-list 'odra-language-bundle-dependency 'facets facets #:maximum 6)
            (if (null? targets) '() (target-list 'odra-language-bundle-dependency targets)))))

(struct odra-language-bundle-artifact
  (id kind path sha256 size targets authority)
  #:transparent
  #:guard
  (lambda (id kind path sha256 size targets authority _)
    (unless (bounded-symbol? id)
      (bundle-error 'odra-language-bundle-artifact "id must be a stable bounded symbol"))
    (unless (memq kind admitted-artifact-kinds)
      (bundle-error 'odra-language-bundle-artifact "kind is not admitted"))
    (unless (relative-path? path)
      (bundle-error 'odra-language-bundle-artifact "path must be normalized and relative"))
    (unless (regexp-match? #px"^[0-9a-f]{64}$" sha256)
      (bundle-error 'odra-language-bundle-artifact "sha256 must be 64 lowercase hexadecimal characters"))
    (unless (<= size maximum-artifact-bytes)
      (bundle-error 'odra-language-bundle-artifact "size exceeds the artifact boundary"))
    (unless (or (not authority) (package-authority? authority))
      (bundle-error 'odra-language-bundle-artifact "authority is not admitted"))
    (values id kind (copy-string path) (copy-string sha256) size
            (target-list 'odra-language-bundle-artifact targets) authority)))

(struct odra-language-injection (language query-artifact combined?)
  #:transparent
  #:guard
  (lambda (language query-artifact combined? _)
    (unless (and (bounded-symbol? language) (bounded-symbol? query-artifact))
      (bundle-error 'odra-language-injection "language and query artifact must be stable symbols"))
    (values language query-artifact combined?)))

(struct odra-tree-sitter-syntax-provider
  (id languages grammar-artifact grammar-symbol abi-min abi-max query-artifacts
      captures injections resource-profile authority)
  #:transparent
  #:guard
  (lambda (id languages grammar-artifact grammar-symbol abi-min abi-max query-artifacts
              captures injections resource-profile authority _)
    (unless (and (bounded-symbol? id) (bounded-symbol? grammar-artifact))
      (bundle-error 'odra-tree-sitter-syntax-provider "provider and grammar identities must be stable symbols"))
    (unless (bounded-text? grammar-symbol maximum-identity-bytes)
      (bundle-error 'odra-tree-sitter-syntax-provider "grammar symbol must be bounded text"))
    (unless (<= abi-min abi-max)
      (bundle-error 'odra-tree-sitter-syntax-provider "ABI range must be ordered"))
    (unless (and (hash? captures) (immutable? captures)
                 (<= (hash-count captures) 256)
                 (for/and ([(capture role) (in-hash captures)])
                   (and (bounded-symbol? capture) (bounded-symbol? role))))
      (bundle-error 'odra-tree-sitter-syntax-provider "captures must be an immutable bounded symbol mapping"))
    (unless (and (list? injections) (<= (length injections) 64)
                 (andmap odra-language-injection? injections))
      (bundle-error 'odra-tree-sitter-syntax-provider "injections must be bounded injection values"))
    (unless (memq resource-profile admitted-resource-profiles)
      (bundle-error 'odra-tree-sitter-syntax-provider "resource profile is not admitted"))
    (unless (eq? authority 'native-grammar)
      (bundle-error 'odra-tree-sitter-syntax-provider "Tree-sitter providers require native-grammar authority"))
    (values id
            (symbol-list 'odra-tree-sitter-syntax-provider 'languages languages #:empty? #f)
            grammar-artifact (copy-string grammar-symbol) abi-min abi-max
            (symbol-list 'odra-tree-sitter-syntax-provider 'query-artifacts query-artifacts)
            (make-immutable-hasheq (hash->list captures))
            (copy-list injections values)
            resource-profile authority)))

(struct odra-language-formatter
  (id languages kind service command root-markers scopes input output timeout-ms output-limit)
  #:transparent
  #:guard
  (lambda (id languages kind service command root-markers scopes input output timeout-ms output-limit _)
    (unless (bounded-symbol? id)
      (bundle-error 'odra-language-formatter "id must be a stable bounded symbol"))
    (unless (memq kind admitted-formatter-kinds)
      (bundle-error 'odra-language-formatter "kind is not admitted"))
    (unless (or (not service) (bounded-symbol? service))
      (bundle-error 'odra-language-formatter "service must be a stable symbol"))
    (unless (and (if (eq? kind 'language-service) service #t)
                 (if (eq? kind 'command) (pair? command) #t))
      (bundle-error 'odra-language-formatter "implementation reference does not match formatter kind"))
    (unless (and (<= timeout-ms maximum-timeout-ms)
                 (<= output-limit maximum-output-bytes))
      (bundle-error 'odra-language-formatter "formatter execution bounds are excessive"))
    (values id
            (symbol-list 'odra-language-formatter 'languages languages #:empty? #f)
            kind service
            (command-vector 'odra-language-formatter command)
            (string-list 'odra-language-formatter 'root-markers root-markers #:maximum 16 #:path? #t)
            (symbol-list 'odra-language-formatter 'scopes scopes
                         #:maximum 2 #:admitted admitted-formatter-scopes #:empty? #f)
            (if (memq input admitted-formatter-inputs) input
                (bundle-error 'odra-language-formatter "input mode is not admitted"))
            (if (memq output admitted-formatter-outputs) output
                (bundle-error 'odra-language-formatter "output mode is not admitted"))
            timeout-ms output-limit)))

(struct odra-language-command
  (id description implementation requirements effects availability provenance replaces)
  #:transparent
  #:guard
  (lambda (id description implementation requirements effects availability provenance replaces _)
    (unless (and (bounded-symbol? id) (bounded-symbol? implementation)
                 (bounded-symbol? availability)
                 (or (not replaces) (bounded-symbol? replaces)))
      (bundle-error 'odra-language-command "command identities must be stable bounded symbols"))
    (unless (bounded-text? description maximum-description-bytes)
      (bundle-error 'odra-language-command "description must be bounded text"))
    (unless (bounded-text? provenance maximum-provenance-bytes)
      (bundle-error 'odra-language-command "provenance must be bounded text"))
    (values id (copy-string description) implementation
            (symbol-list 'odra-language-command 'requirements requirements)
            (symbol-list 'odra-language-command 'effects effects)
            availability (copy-string provenance) replaces)))

(struct odra-language-keymap
  (id languages states context priority bindings remaps before after provenance)
  #:transparent
  #:guard
  (lambda (id languages states context priority bindings remaps before after provenance _)
    (unless (and (bounded-symbol? id) (bounded-symbol? context))
      (bundle-error 'odra-language-keymap "keymap identities must be stable bounded symbols"))
    (unless (and (hash? bindings) (immutable? bindings) (<= (hash-count bindings) 256)
                 (hash? remaps) (immutable? remaps) (<= (hash-count remaps) 256))
      (bundle-error 'odra-language-keymap "bindings and remaps must be immutable bounded mappings"))
    (unless (bounded-text? provenance maximum-provenance-bytes)
      (bundle-error 'odra-language-keymap "provenance must be bounded text"))
    (values id
            (symbol-list 'odra-language-keymap 'languages languages #:empty? #f)
            (symbol-list 'odra-language-keymap 'states states #:empty? #f)
            context priority
            (make-immutable-hash (hash->list bindings))
            (make-immutable-hash (hash->list remaps))
            (symbol-list 'odra-language-keymap 'before before)
            (symbol-list 'odra-language-keymap 'after after)
            (copy-string provenance))))

(define (contribution-list who field values predicate
                           #:maximum [maximum maximum-contributions]
                           #:identity [identity #f])
  (unless (and (list? values) (<= (length values) maximum)
               (andmap predicate values)
               (or (not identity)
                   (unique-list? (map identity values) equal?)))
    (bundle-error who (format "~a must be a bounded list of contribution values" field)))
  (copy-list values (lambda (value) value)))

(struct odra-language-support-bundle
  (format-version id display-name version api-min api-max description license
                  publisher source targets dependencies authorities languages
                  syntax-providers services formatters commands keymaps artifacts
                  entrypoint provenance)
  #:transparent
  #:guard
  (lambda (format-version id display-name version api-min api-max description license
                          publisher source targets dependencies authorities languages
                          syntax-providers services formatters commands keymaps artifacts
                          entrypoint provenance _)
    (unless (= format-version 1)
      (bundle-error 'odra-language-support-bundle "format version is not supported"))
    (unless (and (bounded-symbol? id) (bounded-symbol? publisher) (bounded-symbol? source))
      (bundle-error 'odra-language-support-bundle "bundle, publisher, and source identities must be stable symbols"))
    (unless (bounded-text? display-name maximum-display-name-bytes)
      (bundle-error 'odra-language-support-bundle "display name must be bounded text"))
    (unless (and (semantic-version? version) (semantic-version? api-min)
                 (semantic-version? api-max))
      (bundle-error 'odra-language-support-bundle "bundle and API versions must use semantic version syntax"))
    (unless (bounded-text? description maximum-description-bytes)
      (bundle-error 'odra-language-support-bundle "description must be bounded text"))
    (unless (bounded-text? license maximum-identity-bytes)
      (bundle-error 'odra-language-support-bundle "license must be a bounded SPDX expression"))
    (unless (bounded-text? provenance maximum-provenance-bytes)
      (bundle-error 'odra-language-support-bundle "provenance must be bounded text"))
    (unless (or (not entrypoint) (relative-path? entrypoint))
      (bundle-error 'odra-language-support-bundle "entrypoint must be a relative normalized path"))
    (unless (and (list? dependencies) (andmap odra-language-bundle-dependency? dependencies)
                 (list? authorities) (andmap odra-language-bundle-authority? authorities)
                 (list? languages) (andmap odra-language? languages)
                 (list? syntax-providers)
                 (andmap odra-tree-sitter-syntax-provider? syntax-providers)
                 (list? services) (andmap odra-language-service? services)
                 (list? formatters) (andmap odra-language-formatter? formatters)
                 (list? commands) (andmap odra-language-command? commands)
                 (list? keymaps) (andmap odra-language-keymap? keymaps)
                 (list? artifacts) (andmap odra-language-bundle-artifact? artifacts))
      (bundle-error 'odra-language-support-bundle "bundle contribution fields must contain typed lists"))
    (unless (<= (+ (length languages) (length syntax-providers) (length services)
                   (length formatters) (length commands) (length keymaps))
                maximum-contributions)
      (bundle-error 'odra-language-support-bundle "total contribution count exceeds the bundle boundary"))
    (let* ([authority-ids (map odra-language-bundle-authority-id authorities)]
           [artifact-ids (map odra-language-bundle-artifact-id artifacts)]
           [dependency-ids (map odra-language-bundle-dependency-id dependencies)])
      (unless
          (and (not (member id dependency-ids eq?))
               (for/and ([artifact (in-list artifacts)])
                 (and (or (not (odra-language-bundle-artifact-authority artifact))
                          (member (odra-language-bundle-artifact-authority artifact)
                                  authority-ids eq?))
                      (andmap (lambda (target) (member target targets equal?))
                              (odra-language-bundle-artifact-targets artifact))))
               (for/and ([provider (in-list syntax-providers)])
                 (and (member (odra-tree-sitter-syntax-provider-grammar-artifact provider)
                              artifact-ids eq?)
                      (andmap (lambda (artifact-id) (member artifact-id artifact-ids eq?))
                              (odra-tree-sitter-syntax-provider-query-artifacts provider))
                      (member (odra-tree-sitter-syntax-provider-authority provider)
                              authority-ids eq?)))
               (or (not entrypoint)
                   (for/or ([artifact (in-list artifacts)])
                     (and (eq? (odra-language-bundle-artifact-kind artifact) 'racket-module)
                          (string=? (odra-language-bundle-artifact-path artifact)
                                    entrypoint))))
               (for/and ([dependency (in-list dependencies)])
                 (andmap (lambda (target) (member target targets equal?))
                         (odra-language-bundle-dependency-targets dependency))))
        (bundle-error 'odra-language-support-bundle
                      "bundle references, targets, dependencies, or authorities are inconsistent")))
    (values format-version id (copy-string display-name) (copy-string version)
            (copy-string api-min) (copy-string api-max) (copy-string description)
            (copy-string license) publisher source (target-list 'odra-language-support-bundle targets)
            (contribution-list 'odra-language-support-bundle 'dependencies dependencies
                               odra-language-bundle-dependency?
                               #:maximum maximum-dependencies
                               #:identity odra-language-bundle-dependency-id)
            (contribution-list 'odra-language-support-bundle 'authorities authorities
                               odra-language-bundle-authority?
                               #:maximum (length package-authority-symbols)
                               #:identity odra-language-bundle-authority-id)
            (contribution-list 'odra-language-support-bundle 'languages languages odra-language?
                               #:identity odra-language-id)
            (contribution-list 'odra-language-support-bundle 'syntax-providers syntax-providers
                               odra-tree-sitter-syntax-provider?
                               #:identity odra-tree-sitter-syntax-provider-id)
            (contribution-list 'odra-language-support-bundle 'services services odra-language-service?
                               #:identity odra-language-service-id)
            (contribution-list 'odra-language-support-bundle 'formatters formatters odra-language-formatter?
                               #:identity odra-language-formatter-id)
            (contribution-list 'odra-language-support-bundle 'commands commands odra-language-command?
                               #:identity odra-language-command-id)
            (contribution-list 'odra-language-support-bundle 'keymaps keymaps odra-language-keymap?
                               #:identity odra-language-keymap-id)
            (contribution-list 'odra-language-support-bundle 'artifacts artifacts odra-language-bundle-artifact?
                               #:maximum maximum-artifacts
                               #:identity odra-language-bundle-artifact-id)
            (and entrypoint (copy-string entrypoint)) (copy-string provenance))))

(define (language-bundle-authority id)
  (odra-language-bundle-authority id))

(define (language-bundle-dependency #:id id #:minimum minimum #:maximum maximum
                                    #:optional? [optional? #f] #:facets [facets '()]
                                    #:targets [targets '()])
  (odra-language-bundle-dependency id minimum maximum optional? facets targets))

(define (language-bundle-artifact #:id id #:kind kind #:path path #:sha256 sha256
                                  #:size size #:targets targets
                                  #:authority [authority #f])
  (odra-language-bundle-artifact id kind path sha256 size targets authority))

(define (language-injection #:language language #:query-artifact query-artifact
                            #:combined? [combined? #f])
  (odra-language-injection language query-artifact combined?))

(define (tree-sitter-syntax-provider #:id id #:languages languages
                                     #:grammar-artifact grammar-artifact
                                     #:grammar-symbol grammar-symbol
                                     #:abi-min [abi-min 13] #:abi-max [abi-max 15]
                                     #:query-artifacts [query-artifacts '()]
                                     #:captures [captures (hasheq)]
                                     #:injections [injections '()]
                                     #:resource-profile [resource-profile 'ordinary]
                                     #:authority [authority 'native-grammar])
  (odra-tree-sitter-syntax-provider
   id languages grammar-artifact grammar-symbol abi-min abi-max query-artifacts
   captures injections resource-profile authority))

(define (language-formatter #:id id #:languages languages #:kind kind
                            #:service [service #f] #:command [command '()]
                            #:root-markers [root-markers '()] #:scopes [scopes '(buffer)]
                            #:input [input 'standard-input] #:output [output 'standard-output]
                            #:timeout-ms [timeout-ms 10000]
                            #:output-limit [output-limit (* 8 1024 1024)])
  (odra-language-formatter id languages kind service command root-markers scopes
                           input output timeout-ms output-limit))

(define (language-command #:id id #:description description #:implementation implementation
                          #:requirements [requirements '()] #:effects [effects '()]
                          #:availability [availability 'always]
                          #:provenance [provenance "Bundle declaration"]
                          #:replaces [replaces #f])
  (odra-language-command id description implementation requirements effects
                         availability provenance replaces))

(define (language-keymap #:id id #:languages languages #:bindings bindings
                         #:states [states '(direct modal)] #:context [context 'language]
                         #:priority [priority 0] #:remaps [remaps (hash)]
                         #:before [before '()] #:after [after '()]
                         #:provenance [provenance "Bundle declaration"])
  (odra-language-keymap id languages states context priority bindings remaps
                        before after provenance))

(define (language-support-bundle #:id id #:display-name display-name #:version version
                                 #:api-min api-min #:api-max api-max
                                 #:description description #:publisher publisher
                                 #:source source #:targets targets
                                 #:format-version [format-version 1]
                                 #:license [license "NOASSERTION"]
                                 #:dependencies [dependencies '()]
                                 #:authorities [authorities '()]
                                 #:languages [languages '()]
                                 #:syntax-providers [syntax-providers '()]
                                 #:services [services '()]
                                 #:formatters [formatters '()]
                                 #:commands [commands '()]
                                 #:keymaps [keymaps '()]
                                 #:artifacts [artifacts '()]
                                 #:entrypoint [entrypoint #f]
                                 #:provenance [provenance "Bundle declaration"])
  (odra-language-support-bundle
   format-version id display-name version api-min api-max description license
   publisher source targets dependencies authorities languages syntax-providers
   services formatters commands keymaps artifacts entrypoint provenance))

(define (language-bundle-value? value)
  (odra-language-support-bundle? value))

(module+ test
  (require rackunit)

  (define target '((linux x86-64)))
  (define grammar
    (language-bundle-artifact
     #:id 'grammar #:kind 'tree-sitter-grammar #:path "lib/language.so"
     #:sha256 (make-string 64 #\a) #:size 4096 #:targets target
     #:authority 'native-grammar))
  (define syntax
    (tree-sitter-syntax-provider
     #:id 'example-syntax #:languages '(example) #:grammar-artifact 'grammar
     #:grammar-symbol "tree_sitter_example"))
  (define exported
    (language-support-bundle
     #:id 'org.example.language #:display-name "Example Language"
     #:version "1.0.0" #:api-min "1.0.0" #:api-max "2.0.0"
     #:description "Example bundle." #:publisher 'org.example
     #:source 'catalog.example #:targets target
     #:authorities (list (language-bundle-authority 'native-grammar))
     #:languages (list (language #:id 'example #:suffixes '(".example")))
     #:syntax-providers (list syntax) #:artifacts (list grammar)))
  (check-true (language-bundle-value? exported))
  (check-true (immutable? (odra-language-support-bundle-description exported)))
  (check-equal? (odra-language-support-bundle-targets exported) target)
  (check-exn exn:fail?
             (lambda () (language-bundle-authority 'filesystem-root)))
  (check-exn exn:fail?
             (lambda ()
               (language-bundle-artifact
                #:id 'escape #:kind 'data #:path "../escape"
                #:sha256 (make-string 64 #\a) #:size 1 #:targets target))))
