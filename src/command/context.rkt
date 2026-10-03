#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/file
         racket/list
         racket/path
         racket/string
         "package-resources.rkt"
         "transaction.rkt")

(provide
 (contract-out
  [command-context? (-> any/c boolean?)]
  [text-position? (-> any/c boolean?)]
  [text-range? (-> any/c boolean?)]
  [text-edit? (-> any/c boolean?)]
  [contextual-value? (-> any/c boolean?)]
  [text-position-offset (-> text-position? exact-nonnegative-integer?)]
  [text-range-start (-> text-range? exact-nonnegative-integer?)]
  [text-range-end (-> text-range? exact-nonnegative-integer?)]
  [contextual-value-text (-> contextual-value? string?)]
  [contextual-value-range (-> contextual-value? (or/c #f text-range?))]
  [contextual-value-source (-> contextual-value? symbol?)]
  [command-context-source-revision
   (-> command-context? exact-nonnegative-integer?)]
  [command-context-point (-> command-context? text-position?)]
  [command-context-active-region
   (-> command-context? (or/c #f text-range?))]
  [command-context-current-line (-> command-context? text-range?)]
  [command-context-buffer-range (-> command-context? text-range?)]
  [command-context-range
   (-> command-context? exact-nonnegative-integer? exact-nonnegative-integer?
       text-range?)]
  [command-context-word-at-point
   (-> command-context? (or/c #f text-range?))]
  [command-context-jan-value-at-point
   (-> command-context? (or/c #f text-range?))]
  [command-context-resolve-value
   (->* (command-context?)
        (#:at-point (-> command-context? (or/c #f text-range?))
         #:interactive-value (or/c #f string?)
         #:maximum-bytes exact-positive-integer?)
        (or/c #f contextual-value?))]
  [command-context-candidate-selection
   (-> command-context? (or/c #f string?))]
  [command-context-document-path (-> command-context? (or/c #f string?))]
  [command-context-project-root (-> command-context? (or/c #f string?))]
  [command-context-package-data-root (-> command-context? (or/c #f string?))]
  [command-context-package-resources (-> command-context? package-resources?)]
  [command-context-package-resource-root
   (-> command-context? symbol? (or/c #f string?))]
  [command-context-write-package-artifact!
   (-> command-context? string? bytes? string?)]
  [command-context-render-graphviz!
   (-> command-context? string? string? exact-positive-integer?
       command-tool-result?)]
  [command-tool-result? (-> any/c boolean?)]
  [command-tool-result-status (-> command-tool-result? symbol?)]
  [command-tool-result-exit-code
   (-> command-tool-result? (or/c #f exact-integer?))]
  [command-tool-result-diagnostic (-> command-tool-result? string?)]
  [command-context-read (-> command-context? text-range? string?)]
  [command-context-replace!
   (-> command-context? text-range? string? void?)]
  [make-text-edit (-> text-range? string? text-edit?)]
  [command-context-replace-batch!
   (-> command-context? list? void?)]
  [command-context-cancelled? (-> command-context? boolean?)]
  [command-context-message! (-> command-context? string? void?)]
  [command-context-jan-analyze (-> command-context? bytes? jan-analysis?)]
  [command-context-message (-> command-context? string?)]
  [command-context-abort! (-> command-context? void?)]
  [call-with-command-context
   (->* (transaction-session?
       exact-nonnegative-integer?
       exact-nonnegative-integer?
       (or/c #f exact-nonnegative-integer?)
       (or/c #f exact-nonnegative-integer?)
       exact-nonnegative-integer?
       exact-nonnegative-integer?
       exact-nonnegative-integer?
       list?
       (-> boolean?)
       (-> command-context? any/c))
       (#:document-path (or/c #f string?)
        #:project-root (or/c #f string?)
        #:package-data-root (or/c #f string?)
        #:package-resources package-resources?
        #:candidate-selection (or/c #f string?))
       any/c)]))

(provide call-with-command-tool-runner command-tool-result)

(struct command-context
  (owner transaction revision point-offset active-region-offsets
               current-line-offsets buffer-end effects cancelled-procedure
               document-path project-root package-data-root package-resources candidate-selection
               owner-thread
               [state #:mutable] [mutated? #:mutable] [feedback #:mutable]))
(struct text-position (owner revision offset))
(struct text-range (owner revision start end))
(struct text-edit (range replacement))
(struct contextual-value (text range source) #:transparent)
(struct command-tool-result (status exit-code diagnostic)
  #:transparent
  #:guard
  (lambda (status exit-code diagnostic _)
    (unless (and (memq status '(success unavailable denied timeout failed))
                 (or (not exit-code) (exact-integer? exit-code))
                 (string? diagnostic)
                 (not (regexp-match? #rx"\0" diagnostic))
                 (<= (bytes-length (string->bytes/utf-8 diagnostic)) 4096))
      (raise-arguments-error 'command-tool-result
                             "invalid bounded command tool result"))
    (values status exit-code (string->immutable-string diagnostic))))

(define current-command-tool-runner
  (make-parameter
   (lambda (_tool _input _output _timeout)
     (command-tool-result 'denied #f "External process authority is unavailable."))))

(define (call-with-command-tool-runner runner action)
  (parameterize ([current-command-tool-runner runner]) (action)))

;; call-with-command-context admits copied editor coordinates for one dynamic turn.
(define (call-with-command-context
         transaction revision point region-start region-end
         line-start line-end buffer-end effects cancelled? command
         #:document-path [document-path #f]
         #:project-root [project-root #f]
         #:package-data-root [package-data-root #f]
         #:package-resources [package-resources '()]
         #:candidate-selection [candidate-selection #f])
  (validate-context-input
   point region-start region-end line-start line-end buffer-end effects)
  (define owner (gensym 'personal-command-context))
  (define context
    (command-context
     owner transaction revision point
     (and region-start (cons region-start region-end))
     (cons line-start line-end)
     buffer-end
     (append effects '())
     cancelled?
     (and document-path (string->immutable-string document-path))
     (and project-root (string->immutable-string project-root))
     (and package-data-root (string->immutable-string package-data-root))
     package-resources
     (and candidate-selection
          (string->immutable-string candidate-selection))
     (current-thread)
     'fresh
     #f
     ""))
  (dynamic-wind
   (lambda ()
     (unless (eq? (command-context-state context) 'fresh)
       (raise-arguments-error
        'command-context "a completed command context cannot be resumed"))
     (set-command-context-state! context 'active))
   (lambda ()
     (command context))
   (lambda () (set-command-context-state! context 'closed))))

(define (command-context-point context)
  (ensure-context 'command-context-point context)
  (text-position (context-owner context)
                 (command-context-revision context)
                 (context-point-offset context)))

(define (command-context-source-revision context)
  (ensure-context 'command-context-source-revision context)
  (command-context-revision context))

(define (command-context-package-resource-root context name)
  (ensure-context 'command-context-package-resource-root context)
  (for/first ([resource (in-list (command-context-package-resources context))]
              #:when (eq? name (package-resource-name resource)))
    (package-resource-root resource)))

(define (command-context-active-region context)
  (ensure-context 'command-context-active-region context)
  (define offsets (command-context-active-region-offsets context))
  (and offsets (context-range context (car offsets) (cdr offsets))))

(define (command-context-current-line context)
  (ensure-context 'command-context-current-line context)
  (define offsets (command-context-current-line-offsets context))
  (context-range context (car offsets) (cdr offsets)))

(define (command-context-buffer-range context)
  (ensure-context 'command-context-buffer-range context)
  (context-range context 0 (command-context-buffer-end context)))

(define (command-context-range context start end)
  (ensure-context 'command-context-range context)
  (unless (<= start end (command-context-buffer-end context))
    (raise-arguments-error 'command-context-range
                           "range exceeds the active buffer"
                           "start" start "end" end))
  (context-range context start end))

;; command-context-word-at-point returns one bounded lexical token on the current line.
(define (command-context-word-at-point context)
  (ensure-context 'command-context-word-at-point context)
  (define line (command-context-current-line context))
  (define line-bytes
    (string->bytes/utf-8 (command-context-read context line)))
  (define point
    (- (text-position-offset (command-context-point context))
       (text-range-start line)))
  (define offsets
    (value-token-offsets line-bytes point 0 (bytes-length line-bytes)))
  (and offsets
       (context-range context
                      (+ (text-range-start line) (car offsets))
                      (+ (text-range-start line) (cdr offsets)))))

;; command-context-jan-value-at-point narrows Jan syntax before lexical extraction.
(define (command-context-jan-value-at-point context)
  (ensure-context 'command-context-jan-value-at-point context)
  (define line (command-context-current-line context))
  (define line-start (text-range-start line))
  (define line-bytes
    (string->bytes/utf-8 (command-context-read context line)))
  (define point
    (- (text-position-offset (command-context-point context)) line-start))
  (define analysis (command-context-jan-analyze context line-bytes))
  (define semantic-range
    (jan-value-range-at-point analysis point))
  (define offsets
    (and semantic-range
         (value-token-offsets line-bytes point
                              (car semantic-range)
                              (cdr semantic-range))))
  (if offsets
      (context-range context
                     (+ line-start (car offsets))
                     (+ line-start (cdr offsets)))
      (command-context-word-at-point context)))

;; command-context-resolve-value applies region, point, then supplied interactive input precedence.
(define (command-context-resolve-value
         context
         #:at-point [at-point command-context-word-at-point]
         #:interactive-value [interactive-value #f]
         #:maximum-bytes [maximum-bytes 4096])
  (ensure-context 'command-context-resolve-value context)
  (unless (<= maximum-bytes (* 64 1024))
    (raise-arguments-error
     'command-context-resolve-value
     "maximum value size exceeds the command boundary"
     "limit" (* 64 1024)
     "actual" maximum-bytes))
  (define region (command-context-active-region context))
  (define active-region
    (and region (< (text-range-start region) (text-range-end region)) region))
  (cond
    [active-region
     (admit-contextual-value
      'command-context-resolve-value context active-region 'region maximum-bytes)]
    [else
     (define point-range (at-point context))
     (cond
       [point-range
        (admit-contextual-value
         'command-context-resolve-value context point-range 'point maximum-bytes)]
       [(and interactive-value
             (not (string=? (string-trim interactive-value) "")))
        (admit-contextual-text
         'command-context-resolve-value
         (string-trim interactive-value) #f 'interactive maximum-bytes)]
       [else #f])]))

(define (command-context-read context range)
  (ensure-range 'command-context-read context range)
  (ensure-unmodified 'command-context-read context)
  (define result
    (transaction-inspect
     (command-context-transaction context)
     (text-range-start range)
     (text-range-end range)))
  (when (transaction-failure? result)
    (raise-transaction-failure 'command-context-read result))
  (string->immutable-string (bytes->string/utf-8 result #f)))

(define (command-context-replace! context range replacement)
  (ensure-range 'command-context-replace! context range)
  (ensure-mutation 'command-context-replace! context)
  (define result
    (transaction-splice!
     (command-context-transaction context)
     (text-range-start range)
     (text-range-end range)
     (string->bytes/utf-8 replacement)))
  (when (transaction-failure? result)
    (raise-transaction-failure 'command-context-replace! result))
  (set-command-context-mutated?! context #t)
  (void))

(define (make-text-edit range replacement)
  (text-edit range (string->immutable-string replacement)))

(define (command-context-replace-batch! context edits)
  (ensure-mutation 'command-context-replace-batch! context)
  (unless (and (pair? edits) (andmap text-edit? edits))
    (raise-argument-error
     'command-context-replace-batch! "a non-empty list of text edits" edits))
  (for ([edit (in-list edits)])
    (ensure-range 'command-context-replace-batch! context (text-edit-range edit)))
  (define ordered
    (sort edits < #:key (lambda (edit) (text-range-start (text-edit-range edit)))))
  (for ([left (in-list ordered)]
        [right (in-list (cdr ordered))])
    (when (or (= (text-range-start (text-edit-range left))
                 (text-range-start (text-edit-range right)))
              (> (text-range-end (text-edit-range left))
                 (text-range-start (text-edit-range right))))
      (raise-arguments-error
       'command-context-replace-batch! "text edit ranges must not overlap")))
  (define result
    (transaction-apply-batch!
     (command-context-transaction context)
     (for/list ([edit (in-list ordered)])
       (define range (text-edit-range edit))
       (make-transaction-edit
        (text-range-start range)
        (text-range-end range)
        (string->bytes/utf-8 (text-edit-replacement edit))))))
  (when (transaction-failure? result)
    (raise-transaction-failure 'command-context-replace-batch! result))
  (set-command-context-mutated?! context #t)
  (void))

(define (command-context-cancelled? context)
  (ensure-context 'command-context-cancelled? context)
  (define result ((command-context-cancelled-procedure context)))
  (unless (boolean? result)
    (raise-result-error 'command-context-cancelled? "boolean?" result))
  result)

(define (command-context-message! context message)
  (ensure-context 'command-context-message! context)
  (unless (and (string? message)
               (not (regexp-match? #rx"\0" message))
               (<= (bytes-length (string->bytes/utf-8 message)) 4096))
    (raise-arguments-error
     'command-context-message! "message exceeds the admitted bound"))
  (set-command-context-feedback! context (string->immutable-string message))
  (void))

(define (command-context-jan-analyze context source)
  (ensure-context 'command-context-jan-analyze context)
  (define result
    (transaction-jan-analyze (command-context-transaction context) source))
  (when (transaction-failure? result)
    (raise-transaction-failure 'command-context-jan-analyze result))
  result)

(define (package-artifact-path who context relative)
  (ensure-context who context)
  (define root (command-context-package-data-root context))
  (unless root
    (raise-arguments-error who "package data storage is unavailable"))
  (define path (string->path relative))
  (unless (and (relative-path? path)
               (pair? (explode-path path))
               (for/and ([part (in-list (explode-path path))])
                 (and (path? part)
                      (not (member (path->string part) '("" "." "..") string=?)))))
    (raise-arguments-error who "artifact path must be normalized and relative"))
  (simplify-path (build-path root path)))

(define (command-context-write-package-artifact! context relative content)
  (define destination
    (package-artifact-path 'command-context-write-package-artifact!
                           context relative))
  (when (> (bytes-length content) (* 64 1024 1024))
    (raise-arguments-error 'command-context-write-package-artifact!
                           "artifact exceeds the admitted byte bound"))
  (make-directory* (path-only destination))
  (call-with-output-file destination
    (lambda (output) (write-bytes content output))
    #:exists 'truncate/replace
    #:mode 'binary)
  (path->string destination))

(define (command-context-render-graphviz! context input-relative output-relative
                                          timeout-milliseconds)
  (define input
    (package-artifact-path 'command-context-render-graphviz!
                           context input-relative))
  (define output
    (package-artifact-path 'command-context-render-graphviz!
                           context output-relative))
  (unless (<= timeout-milliseconds 10000)
    (raise-arguments-error 'command-context-render-graphviz!
                           "renderer timeout exceeds the admitted bound"))
  ((current-command-tool-runner)
   'graphviz-dot input output timeout-milliseconds))

(define (command-context-message context)
  (ensure-context 'command-context-message context)
  (command-context-feedback context))

(define (command-context-abort! context)
  (ensure-context 'command-context-abort! context)
  (define result
    (transaction-request-abort! (command-context-transaction context)))
  (when (transaction-failure? result)
    (raise-transaction-failure 'command-context-abort! result))
  (void))

(define (context-owner context)
  (command-context-owner context))

(define (context-point-offset context)
  (command-context-point-offset context))

(define (context-range context start end)
  (text-range (context-owner context) (command-context-revision context) start end))

(define (admit-contextual-value who context range source maximum-bytes)
  (ensure-range who context range)
  (define value (command-context-read context range))
  (and (not (string=? value ""))
       (admit-contextual-text who value range source maximum-bytes)))

(define (admit-contextual-text who value range source maximum-bytes)
  (define encoded (string->bytes/utf-8 value))
  (when (> (bytes-length encoded) maximum-bytes)
    (raise-arguments-error
     who "contextual value exceeds the admitted byte bound"
     "limit" maximum-bytes
     "actual" (bytes-length encoded)))
  (when (regexp-match? #rx"\0" value)
    (raise-arguments-error who "contextual value contains a NUL byte"))
  (contextual-value (string->immutable-string value) range source))

(define jan-contextual-node-kinds
  '("plain-link" "angle-link" "regular-link" "radio-link"
    "citation" "citation-reference" "node-property"))

(define jan-contextual-attribute-names '("value" "tag"))

(define (jan-value-range-at-point analysis point)
  (define candidates
    (append
     (for/list ([attribute (in-list (jan-analysis-attributes analysis))]
                #:when
                (and (member (jan-attribute-name attribute)
                             jan-contextual-attribute-names string=?)
                     (offset-inside? point
                                     (jan-attribute-start attribute)
                                     (jan-attribute-end attribute))))
       (cons (jan-attribute-start attribute) (jan-attribute-end attribute)))
     (for/list ([node (in-list (jan-analysis-nodes analysis))]
                #:when
                (and (member (jan-node-kind-text node)
                             jan-contextual-node-kinds string=?)
                     (offset-inside? point (jan-node-start node)
                                     (jan-node-end node))))
       (cons (jan-node-start node) (jan-node-end node)))))
  (and (pair? candidates)
       (argmin (lambda (range) (- (cdr range) (car range))) candidates)))

(define (offset-inside? point start end)
  (and (<= start point) (< point end)))

(define (value-token-offsets source point lower upper)
  (cond
    [(or (< point lower) (>= point upper)
         (value-token-delimiter? (bytes-ref source point)))
     #f]
    [else
     (define start
       (let loop ([cursor point])
         (if (and (> cursor lower)
                  (not (value-token-delimiter?
                        (bytes-ref source (sub1 cursor)))))
             (loop (sub1 cursor))
             cursor)))
     (define end
       (let loop ([cursor point])
         (if (and (< cursor upper)
                  (not (value-token-delimiter? (bytes-ref source cursor))))
             (loop (add1 cursor))
             cursor)))
     (define trimmed-start
       (let loop ([cursor start])
         (if (and (< cursor end)
                  (value-token-edge? (bytes-ref source cursor)))
             (loop (add1 cursor))
             cursor)))
     (define trimmed-end
       (let loop ([cursor end])
         (if (and (> cursor trimmed-start)
                  (value-token-edge? (bytes-ref source (sub1 cursor))))
             (loop (sub1 cursor))
             cursor)))
     (and (< trimmed-start trimmed-end)
          (<= trimmed-start point)
          (< point trimmed-end)
          (cons trimmed-start trimmed-end))]))

(define (value-token-delimiter? byte)
  (and (memv byte '(9 10 13 32 34 39 40 41 60 62 91 92 93 96 123 124 125))
       #t))

(define (value-token-edge? byte)
  (and (memv byte '(33 42 44 46 58 59 63)) #t))

(define (ensure-context who context)
  (unless (eq? (command-context-owner-thread context) (current-thread))
    (raise-arguments-error who "command context belongs to another thread"))
  (unless (eq? (command-context-state context) 'active)
    (raise-arguments-error who "command context escaped its dynamic extent")))

(define (ensure-range who context range)
  (ensure-context who context)
  (unless (and (eq? (text-range-owner range) (context-owner context))
               (= (text-range-revision range) (command-context-revision context)))
    (raise-arguments-error who "text range belongs to another command context")))

(define (ensure-unmodified who context)
  (when (command-context-mutated? context)
    (raise-arguments-error who "command context text values are stale after mutation")))

(define (ensure-mutation who context)
  (ensure-context who context)
  (ensure-unmodified who context)
  (unless (memq 'text-mutation (command-context-effects context))
    (raise-arguments-error who "command does not admit text mutation")))

(define (raise-transaction-failure who failure)
  (raise-arguments-error
   who
   "editor transaction rejected the command context operation"
   "code" (transaction-failure-code failure)
   "detail" (transaction-failure-detail failure)))

(define (validate-context-input
         point region-start region-end line-start line-end buffer-end effects)
  (unless (and (<= point buffer-end)
               (<= line-start line-end buffer-end)
               (or (and (not region-start) (not region-end))
                   (and region-start region-end
                        (<= region-start region-end buffer-end))))
    (raise-arguments-error
     'call-with-command-context "editor coordinates exceed the active buffer"))
  (unless (and (= (length effects) (length (remove-duplicates effects)))
               (andmap (lambda (effect) (memq effect '(buffer view text-mutation)))
                       effects))
    (raise-arguments-error
     'call-with-command-context "invalid command effect set" "effects" effects))
  (void))
