#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/bytes
         racket/list
         racket/match
         racket/set
         racket/vector)

(provide computation-limits
         computation-resource-profiles
         order-formula-graph
         evaluate-table-formula
         recalculate-table
         lookup-table-value
         render-text-plot
         prepare-gnuplot-request
         resolve-execution-arguments
         resolve-execution-authority
         select-execution-adapter
         serialize-execution-variables
         transition-execution-process
         update-adapter-health
         normalize-typed-result
         decode-typed-result
         order-result-processing
         prepare-result-publication
         transition-session
         cache-key-current?
         inspect-result-cache
         prepare-source-edit
         publish-source-edit
         order-noweb-graph
         plan-extraction
         order-batch-targets
         prepare-execution-batch
         summarize-execution-batch
         computation-capability-states
         validate-computation-resource-profile
         estimate-computation-retained-bytes
         estimate-computation-temporary-bytes)

;; These values mirror the accepted Computable Documents resource contract.
(define computation-limits
  '#hasheq((table-cells . 65536)
           (formula-dependencies . 16384)
           (graph-depth . 1024)
           (executable-targets . 4096)
           (active-sessions . 64)
           (child-processes . 32)
           (output-bytes . 67108864)
           (retained-output-bytes . 268435456)
           (generated-files . 4096)
           (result-rows . 16384)
           (cache-bytes . 268435456)
           (cancellation-entries . 4096)))

;; Ordinary, demanding, and exact-boundary profiles remain independently bounded.
(define computation-resource-profiles
  (list
   '#hasheq((name . ordinary) (table-cells . 256) (formula-dependencies . 128)
            (executable-targets . 8) (active-sessions . 1) (child-processes . 1)
            (output-bytes . 262144) (retained-output-bytes . 1048576)
            (generated-files . 8) (result-rows . 256) (cache-bytes . 4194304))
   '#hasheq((name . demanding) (table-cells . 49152) (formula-dependencies . 12288)
            (executable-targets . 3072) (active-sessions . 48) (child-processes . 24)
            (output-bytes . 50331648) (retained-output-bytes . 201326592)
            (generated-files . 3072) (result-rows . 12288) (cache-bytes . 201326592))
   '#hasheq((name . boundary) (table-cells . 65536) (formula-dependencies . 16384)
            (executable-targets . 4096) (active-sessions . 64) (child-processes . 32)
            (output-bytes . 67108864) (retained-output-bytes . 268435456)
            (generated-files . 4096) (result-rows . 16384) (cache-bytes . 268435456))))

;; Formula dependencies produce one stable order or reject missing and cyclic graphs.
(define (order-formula-graph nodes)
  (and (list? nodes)
       (<= (length nodes) (hash-ref computation-limits 'formula-dependencies))
       (let ([identities (map (lambda (node) (hash-ref node 'identity #f)) nodes)])
         (and (andmap symbol? identities)
              (= (length identities) (length (remove-duplicates identities)))
              (for/and ([node (in-list nodes)])
                (and (list? (hash-ref node 'dependencies #f))
                     (andmap (lambda (dependency) (member dependency identities))
                             (hash-ref node 'dependencies))))
              (let ([by-id (for/hasheq ([node (in-list nodes)])
                             (values (hash-ref node 'identity) node))]
                    [temporary (make-hasheq)]
                    [permanent (make-hasheq)]
                    [ordered '()])
                (define (visit identity depth)
                  (cond
                    [(> depth (hash-ref computation-limits 'graph-depth)) #f]
                    [(hash-ref permanent identity #f) #t]
                    [(hash-ref temporary identity #f) #f]
                    [else
                     (hash-set! temporary identity #t)
                     (and (for/and ([dependency (in-list (hash-ref (hash-ref by-id identity)
                                                                    'dependencies))])
                            (visit dependency (add1 depth)))
                          (begin
                            (hash-remove! temporary identity)
                            (hash-set! permanent identity #t)
                            (set! ordered (cons identity ordered))
                            #t))]))
                (and (for/and ([identity (in-list identities)]) (visit identity 1))
                     (reverse ordered)))))))

;; Formula programs operate on copied row-major values and return an optional trace.
(define (evaluate-table-formula table instructions current-row current-column)
  (define rows (hash-ref table 'rows #f))
  (define columns (hash-ref table 'columns #f))
  (define names (hash-ref table 'names #f))
  (define cells (hash-ref table 'cells #f))
  (define (cell row column)
    (and (exact-nonnegative-integer? row) (< row rows)
         (exact-nonnegative-integer? column) (< column columns)
         (vector-ref cells (+ (* row columns) column))))
  (define (reference value)
    (match value
      [(list 'relative row-delta column-delta)
       (cell (+ current-row row-delta) (+ current-column column-delta))]
      [(list 'absolute row column) (cell row column)]
      [(list 'named name)
       (define positions (indexes-of names name))
       (and (= (length positions) 1) (cell current-row (car positions)))]
      [_ #f]))
  (and (exact-positive-integer? rows)
       (exact-positive-integer? columns)
       (list? names)
       (= (length names) columns)
       (vector? cells)
       (= (vector-length cells) (* rows columns))
       (let loop ([remaining instructions] [stack '()] [trace '()] [step 0])
         (cond
           [(null? remaining)
            (and (= (length stack) 1)
                 (hasheq 'value (car stack) 'trace (reverse trace)))]
           [else
            (define instruction (car remaining))
            (define next
              (match instruction
                [(list 'literal (? number? value)) (cons value stack)]
                [(list 'reference target)
                 (define value (reference target))
                 (and (number? value) (cons value stack))]
                [(list (and operator (or 'add 'subtract 'multiply 'divide)))
                 (and (pair? stack) (pair? (cdr stack))
                      (let ([right (car stack)] [left (cadr stack)])
                        (and (number? left) (number? right)
                             (or (not (eq? operator 'divide)) (not (zero? right)))
                             (cons (case operator
                                     [(add) (+ left right)]
                                     [(subtract) (- left right)]
                                     [(multiply) (* left right)]
                                     [(divide) (/ left right)])
                                   (cddr stack)))))]
                [(list (and operator (or 'sum 'average 'minimum 'maximum))
                       row-start column-start row-end column-end)
                 (define values
                   (for*/list ([row (in-range row-start (add1 row-end))]
                               [column (in-range column-start (add1 column-end))])
                     (cell row column)))
                 (and (pair? values)
                      (andmap number? values)
                      (cons (case operator
                              [(sum) (apply + values)]
                              [(average) (/ (apply + values) (length values))]
                              [(minimum) (apply min values)]
                              [(maximum) (apply max values)])
                            stack))]
                [_ #f]))
            (and next
                 (loop (cdr remaining) next
                       (cons (hasheq 'step step 'instruction instruction
                                    'stack-depth (length next) 'value (car next))
                             trace)
                       (add1 step)))]))))

;; Recalculation returns a new table only after every formula and target validates.
(define (recalculate-table table calculations)
  (define evaluated
    (for/list ([calculation (in-list calculations)])
      (match calculation
        [(hash-table ('target (list row column)) ('instructions instructions))
         (define result (evaluate-table-formula table instructions row column))
         (and result (list row column (hash-ref result 'value)))]
        [_ #f])))
  (and (andmap values evaluated)
       (= (length evaluated)
          (length (remove-duplicates (map (lambda (item) (take item 2)) evaluated))))
       (let ([cells (vector-copy (hash-ref table 'cells))]
             [columns (hash-ref table 'columns)])
         (for ([item (in-list evaluated)])
           (vector-set! cells (+ (* (car item) columns) (cadr item)) (caddr item)))
         (hash-set table 'cells (vector->immutable-vector cells)))))

;; Lookups support exact, relational, associative, and inclusive range modes.
(define (lookup-table-value table kind key key-column value-column [upper-column key-column])
  (define rows (hash-ref table 'rows))
  (define columns (hash-ref table 'columns))
  (define cells (hash-ref table 'cells))
  (define (cell row column) (vector-ref cells (+ (* row columns) column)))
  (case kind
    [(exact associative)
     (for/first ([row (in-range rows)] #:when (equal? (cell row key-column) key))
       (cell row value-column))]
    [(relational)
     (for/fold ([value #f] [best #f] #:result value) ([row (in-range rows)])
       (define candidate (cell row key-column))
       (if (and (real? candidate) (<= candidate key) (or (not best) (> candidate best)))
           (values (cell row value-column) candidate)
           (values value best)))]
    [(range)
     (for/first ([row (in-range rows)]
                 #:when (<= (cell row key-column) key (cell row upper-column)))
       (cell row value-column))]
    [else #f]))

;; Text plots scale copied values deterministically within the requested width.
(define (render-text-plot title points width)
  (and (string? title)
       (positive? (string-length title))
       (exact-positive-integer? width)
       (<= width 256)
       (pair? points)
       (andmap (lambda (point) (match point [(list (? string?) (? real?)) #t] [_ #f])) points)
       (let ([maximum (max 1 (apply max (map (lambda (point) (abs (cadr point))) points)))])
         (string-append
          title "\n"
          (apply string-append
                 (for/list ([point (in-list points)])
                   (define count (max (if (zero? (cadr point)) 0 1)
                                      (inexact->exact (floor (* width (/ (abs (cadr point)) maximum))))))
                   (format "~a ~a~a\n" (car point) (if (negative? (cadr point)) "-" "+")
                           (make-string count #\#))))))))

;; Gnuplot adaptation produces a bounded copied-data request and never runs it.
(define (prepare-gnuplot-request snapshot adapter-generation terminal output input-bytes)
  (and (hash? snapshot)
       (exact-positive-integer? adapter-generation)
       (memq terminal '(png svg pdf))
       (string? output)
       (positive? (string-length output))
       (<= input-bytes (hash-ref computation-limits 'output-bytes))
       (hasheq 'operation (hash-ref snapshot 'operation)
               'scope (hash-ref snapshot 'scope)
               'digest (hash-ref snapshot 'digest)
               'adapter-generation adapter-generation
               'terminal terminal
               'output (string->immutable-string output)
               'point-count (length (hash-ref snapshot 'points))
               'input-bytes input-bytes)))

;; Argument scopes apply from low to high precedence with explicit additive keys.
(define (resolve-execution-arguments scopes additive-keys)
  (and (list? scopes)
       (list? additive-keys)
       (for/and ([entry (in-list scopes)])
         (match entry [(list (? symbol?) (? hash?)) #t] [_ #f]))
       (for/fold ([effective #hasheq()] [provenance #hasheq()] [shadowed #hasheq()]
                  #:result (hasheq 'values effective 'provenance provenance 'shadowed shadowed))
                 ([entry (in-list scopes)])
         (define scope (car entry))
         (for/fold ([current effective] [origins provenance] [prior shadowed])
                   ([(key value) (in-hash (cadr entry))])
           (define present? (hash-has-key? current key))
           (define next-value
             (if (and present? (member key additive-keys))
                 (append (if (list? (hash-ref current key)) (hash-ref current key) (list (hash-ref current key)))
                         (if (list? value) value (list value)))
                 value))
           (values (hash-set current key next-value)
                   (hash-set origins key scope)
                   (if present?
                       (hash-update prior key
                                    (lambda (items) (append items (list (cons (hash-ref origins key) (hash-ref current key)))))
                                    '())
                       prior))))))

;; Authority is deny-first; batch and export never convert confirmation into approval.
(define (resolve-execution-authority rules language origin context effects trusted?
                                     #:adapter [adapter #f]
                                     #:trigger [trigger 'command])
  (and (list? rules)
       (memq context '(interactive batch export))
       (if (not (memq trigger '(command explicit-export explicit-batch)))
           'deny
           (let* ([matching
               (filter (lambda (rule)
                         (and (equal? (hash-ref rule 'language #f) language)
                              (or (not (hash-has-key? rule 'adapter))
                                  (equal? (hash-ref rule 'adapter) adapter))
                              (memq origin (hash-ref rule 'origins '()))
                              (subset? (list->set effects)
                                       (list->set (hash-ref rule 'effects '())))))
                       rules)]
              [decisions (map (lambda (rule) (hash-ref rule context 'deny)) matching)])
         (cond
           [(or (null? matching) (member 'deny decisions)) 'deny]
           [(member 'confirm decisions) (if (and trusted? (eq? context 'interactive)) 'confirm 'deny)]
           [(andmap (lambda (decision) (eq? decision 'allow)) decisions) 'allow]
           [else 'deny])))))

;; Adapter selection is exact by language, identity, generation, and runtime state.
(define (select-execution-adapter adapters language requested generation runtime-available?)
  (and (list? adapters)
       (exact-positive-integer? generation)
       (let ([matching (filter (lambda (adapter)
                                 (equal? (hash-ref adapter 'language #f) language))
                               adapters)])
         (cond
           [(null? matching) 'unavailable]
           [(not (= (length matching) 1)) 'conflict]
           [else
            (define selected (car matching))
            (cond
              [(not (= (hash-ref selected 'generation 0) generation)) 'stale]
              [(and requested (not (equal? requested (hash-ref selected 'identity)))) 'conflict]
              [(and (hash-ref selected 'runtime-required? #f) (not runtime-available?)) 'unavailable]
              [else selected])]))))

;; Variable serialization is deterministic data and never shell input.
(define (serialize-execution-variables variables)
  (and (list? variables)
       (<= (length variables) 512)
       (= (length variables)
          (length (remove-duplicates (map (lambda (variable) (hash-ref variable 'name #f)) variables))))
       (for/and ([variable (in-list variables)])
         (and (symbol? (hash-ref variable 'name #f))
              (memq (hash-ref variable 'kind #f)
                    '(scalar list table source result property resource))
              (string? (hash-ref variable 'value #f))))
       (apply string-append
              (for/list ([variable (in-list variables)])
                (format "~a:~a:~a\n"
                        (hash-ref variable 'name)
                        (hash-ref variable 'kind)
                        (hash-ref variable 'value))))))

;; Process lifecycle contains cancellation and timeout until cleanup is confirmed.
(define (transition-execution-process state event)
  (case state
    [(prepared) (and (eq? event 'start) 'starting)]
    [(starting) (case event [(started) 'running] [(fail) 'failed] [else #f])]
    [(running) (case event [(complete) 'completed] [(cancel) 'cancelling]
                           [(timeout) 'timed-out] [(fail) 'failed] [else #f])]
    [(cancelling) (case event [(complete fail) 'cleaning] [(timeout) 'quarantined] [else #f])]
    [(completed failed timed-out) (case event [(cleanup) 'cleaning]
                                               [(quarantine) 'quarantined] [else #f])]
    [(quarantined) (and (eq? event 'reconcile) 'cleaning)]
    [(cleaning) (and (eq? event 'cleanup-confirmed) 'closed)]
    [else #f]))

;; Adapter health remains quarantined until the exact generation is reconciled.
(define (update-adapter-health health generation operation event)
  (and (exact-positive-integer? generation)
       (exact-positive-integer? operation)
       (or (not health) (= generation (hash-ref health 'generation)))
       (case event
         [(timeout quarantine)
          (hasheq 'generation generation 'operation operation 'quarantined? #t)]
         [(reconcile)
          (and health (hash-ref health 'quarantined? #f)
               (hasheq 'generation generation 'operation #f 'quarantined? #f))]
         [else #f])))

;; Typed results retain collection, type, format, handling, and bounded accounting.
(define (normalize-typed-result candidate)
  (match candidate
    [(hash-table ('collection (and collection (or 'value 'output)))
                 ('type (and type (or 'absence 'scalar 'list 'table 'resource 'text
                                     'document-fragment 'graphics)))
                 ('format (and format (or 'raw 'verbatim 'code 'table 'list 'file 'link 'structured)))
                 ('handling (and handling (or 'replace 'append 'prepend 'silent 'discard)))
                 ('rows (? exact-nonnegative-integer? rows))
                 ('bytes (? exact-nonnegative-integer? bytes))
                 ('complete? (? boolean? complete?)))
     (and (<= rows (hash-ref computation-limits 'result-rows))
          (<= bytes (hash-ref computation-limits 'output-bytes))
          (hasheq 'collection collection 'type type 'format format 'handling handling
                  'rows rows 'bytes bytes 'complete? complete?))]
    [_ #f]))

;; Decoding accepts only complete successful output whose accounting matches.
(define (decode-typed-result candidate payload)
  (define normalized (normalize-typed-result candidate))
  (and normalized
       (hash-ref normalized 'complete?)
       (zero? (hash-ref candidate 'exit-status 0))
       (= (hash-ref normalized 'bytes) (bytes-length payload))
       (let ([rows (if (memq (hash-ref normalized 'type) '(list table))
                       (if (zero? (bytes-length payload))
                           0
                           (length (regexp-split #rx#"\n" payload)))
                       0)])
         (and (= rows (hash-ref normalized 'rows))
              (hash-set* candidate 'payload (bytes-copy payload) 'decoded? #t)))))

;; Result processors form a bounded directed acyclic graph.
(define (order-result-processing steps)
  (and (list? steps)
       (positive? (length steps))
       (<= (length steps) (hash-ref computation-limits 'graph-depth))
       (let ([identities (map (lambda (step) (hash-ref step 'identity #f)) steps)])
         (and (andmap exact-positive-integer? identities)
              (= (length identities) (length (remove-duplicates identities)))
              (let loop ([remaining steps] [ordered '()])
                (cond
                  [(null? remaining) (reverse ordered)]
                  [else
                   (define ready
                     (filter (lambda (step)
                               (andmap (lambda (dependency) (member dependency ordered))
                                       (hash-ref step 'dependencies '())))
                             remaining))
                   (and (pair? ready)
                        (loop (filter (lambda (step) (not (member step ready))) remaining)
                              (append (reverse (map (lambda (step) (hash-ref step 'identity)) ready))
                                      ordered)))]))))))

;; Publication returns one exact-owner transaction candidate without editing source.
(define (prepare-result-publication decoded confirmed-owner prior-result payload)
  (and (hash? decoded)
       (hash-ref decoded 'decoded? #f)
       (equal? (hash-ref decoded 'owner #f) confirmed-owner)
       (case (hash-ref decoded 'handling)
         [(silent discard) (hasheq 'owner confirmed-owner 'mutates? #f 'replacement #"")]
         [(replace) (hasheq 'owner confirmed-owner 'mutates? #t 'replacement (bytes-copy payload))]
         [(append) (hasheq 'owner confirmed-owner 'mutates? #t
                           'replacement (bytes-append prior-result payload))]
         [(prepend) (hasheq 'owner confirmed-owner 'mutates? #t
                            'replacement (bytes-append payload prior-result))]
         [else #f])))

;; Session transitions never make an adapter context canonical document state.
(define (transition-session state event)
  (case state
    [(prepared) (case event [(start) 'active] [(cancel close) 'closed] [else #f])]
    [(active) (case event [(close) 'closing] [(fail) 'failed] [(quarantine) 'quarantined]
                          [(restart provider-invalidated) 'recovery-required] [else #f])]
    [(closing) (case event [(closed) 'closed] [(fail) 'failed] [else #f])]
    [(failed quarantined) (case event [(close cleanup-confirmed) 'closed] [else #f])]
    [(recovery-required) (case event [(reconnect) 'active] [(close cleanup-confirmed) 'closed]
                                     [else #f])]
    [else #f]))

;; Cache reuse requires every semantic, adapter, environment, and policy field.
(define (cache-key-current? candidate confirmed)
  (and (hash? candidate)
       (hash? confirmed)
       (for/and ([key (in-list '(source arguments inputs references adapter version environment policy))])
         (and (hash-has-key? candidate key)
              (equal? (hash-ref candidate key) (hash-ref confirmed key #f))))))

;; Cache inspection distinguishes exact hits, mismatches, and absent source keys.
(define (inspect-result-cache entries key)
  (cond
    [(for/first ([entry (in-list entries)]
                 #:when (cache-key-current? (hash-ref entry 'key) key))
       entry)
     => (lambda (entry)
          (if (hash-ref entry 'complete? #f)
              (hasheq 'state 'hit 'reason 'exact 'entry entry)
              (hasheq 'state 'rejected 'reason 'incomplete 'entry entry)))]
    [(for/first ([entry (in-list entries)]
                 #:when (equal? (hash-ref (hash-ref entry 'key) 'source #f)
                                (hash-ref key 'source #f)))
       entry)
     => (lambda (entry) (hasheq 'state 'invalidated 'reason 'key-mismatch 'entry entry))]
    [else (hasheq 'state 'miss 'reason 'no-entry)]))

;; Focused source editing retains an exact owner range and original body.
(define (prepare-source-edit source owner start end indent)
  (and (bytes? source)
       (symbol? owner)
       (exact-nonnegative-integer? start)
       (exact-nonnegative-integer? end)
       (<= start end (bytes-length source))
       (bytes? indent)
       (for/and ([value (in-bytes indent)]) (memv value '(9 32)))
       (let* ([body (subbytes source start end)]
              [lines (regexp-split #rx#"\n" body)])
         (and (for/and ([line (in-list lines)] #:unless (zero? (bytes-length line)))
                (and (<= (bytes-length indent) (bytes-length line))
                     (bytes=? indent (subbytes line 0 (bytes-length indent)))))
              (hasheq 'owner owner 'start start 'end end 'indent (bytes-copy indent)
                      'original (bytes-copy body)
                      'focused
                      (bytes-join
                       (for/list ([line (in-list lines)])
                         (if (zero? (bytes-length line)) line (subbytes line (bytes-length indent))))
                       #"\n"))))))

;; Publication revalidates the original bytes and returns a whole-source candidate.
(define (publish-source-edit edit source focused)
  (and (hash? edit)
       (bytes? source)
       (bytes? focused)
       (let ([start (hash-ref edit 'start)] [end (hash-ref edit 'end)])
         (and (<= end (bytes-length source))
              (bytes=? (subbytes source start end) (hash-ref edit 'original))
              (let* ([indent (hash-ref edit 'indent)]
                     [replacement
                      (bytes-join
                       (for/list ([line (in-list (regexp-split #rx#"\n" focused))])
                         (if (zero? (bytes-length line)) line (bytes-append indent line)))
                       #"\n")])
                (bytes-append (subbytes source 0 start) replacement
                              (subbytes source end)))))))

;; Noweb definitions form a complete bounded acyclic graph before expansion.
(define (order-noweb-graph definitions root)
  (define table
    (for/hasheq ([definition (in-list definitions)])
      (values (hash-ref definition 'identity) definition)))
  (define (visit identity visiting visited ordered)
    (cond
      [(member identity visiting) #f]
      [(member identity visited) (list visited ordered)]
      [else
       (define definition (hash-ref table identity #f))
       (and definition
            (hash-ref definition 'admitted? #f)
            (let ([state
                   (for/fold ([state (list visited ordered)])
                             ([dependency (in-list (hash-ref definition 'references '()))]
                              #:break (not state))
                     (and state
                          (visit dependency (cons identity visiting)
                                 (car state) (cadr state))))])
              (and state
                   (list (cons identity (car state)) (cons identity (cadr state))))))]))
  (and (<= (length definitions) (hash-ref computation-limits 'graph-depth))
       (let ([result (visit root '() '() '())])
         (and result (reverse (cadr result))))))

;; Extraction validates all targets and collisions before returning a complete plan.
(define (plan-extraction targets overwrite? #:cancelled? [cancelled? #f])
  (and (list? targets)
       (not cancelled?)
       (<= (length targets) (hash-ref computation-limits 'generated-files))
       (for/and ([target (in-list targets)])
         (match target
           [(hash-table ('identity (? symbol?)) ('resource (? string?)) ('bytes (? bytes?))) #t]
           [_ #f]))
       (or overwrite?
           (= (length targets)
              (length (remove-duplicates (map (lambda (target) (hash-ref target 'resource)) targets)))))
       (hasheq 'targets targets
               'resources (length targets)
               'bytes (for/sum ([target (in-list targets)]) (bytes-length (hash-ref target 'bytes)))
               'complete? #t)))

;; Batch ordering is stable by document, source offset, then target identity.
(define (order-batch-targets targets)
  (and (list? targets)
       (<= (length targets) (hash-ref computation-limits 'executable-targets))
       (for/and ([target (in-list targets)])
         (and (exact-positive-integer? (hash-ref target 'document #f))
              (exact-nonnegative-integer? (hash-ref target 'start #f))
              (symbol? (hash-ref target 'identity #f))))
       (sort targets
             (lambda (left right)
               (define left-key (list (hash-ref left 'document) (hash-ref left 'start)
                                      (symbol->string (hash-ref left 'identity))))
               (define right-key (list (hash-ref right 'document) (hash-ref right 'start)
                                       (symbol->string (hash-ref right 'identity))))
               (cond [(< (car left-key) (car right-key)) #t]
                     [(> (car left-key) (car right-key)) #f]
                     [(< (cadr left-key) (cadr right-key)) #t]
                     [(> (cadr left-key) (cadr right-key)) #f]
                     [else (string<? (caddr left-key) (caddr right-key))])))))

;; Batch admission requires explicit authority and exact policy/adapter generations.
(define (prepare-execution-batch targets mode concurrency)
  (define ordered (order-batch-targets targets))
  (and ordered
       (memq mode '(atomic best-effort))
       (exact-positive-integer? concurrency)
       (<= concurrency (hash-ref computation-limits 'child-processes))
       (for/and ([target (in-list ordered)])
         (and (eq? (hash-ref target 'authority #f) 'allow)
              (hash-ref target 'explicit-trigger? #f)
              (= (hash-ref target 'policy-generation #f)
                 (hash-ref target 'scope-policy-generation #f))
              (eq? (hash-ref target 'adapter-state #f) 'selected)
              (= (hash-ref target 'adapter-generation #f)
                 (hash-ref target 'scope-adapter-generation #f))))
       (hasheq 'mode mode
               'concurrency concurrency
               'targets ordered
               'cache-hits
               (count (lambda (target) (eq? (hash-ref target 'cache-state 'miss) 'hit))
                      ordered)
               'complete? #t)))

;; Batch summaries keep execution accounting separate from publication semantics.
(define (summarize-execution-batch plan outcomes)
  (define targets (and (hash? plan) (hash-ref plan 'targets #f)))
  (define valid-states '(completed cache-hit rejected unattempted cancelled))
  (and (list? targets)
       (list? outcomes)
       (= (length targets) (length outcomes))
       (for/and ([target (in-list targets)] [outcome (in-list outcomes)])
         (and (eq? (hash-ref target 'identity #f) (hash-ref outcome 'identity #f))
              (memq (hash-ref outcome 'state #f) valid-states)
              (exact-nonnegative-integer? (hash-ref outcome 'bytes #f))
              (<= (hash-ref outcome 'bytes) (hash-ref computation-limits 'output-bytes))
              (exact-nonnegative-integer? (hash-ref outcome 'rows #f))
              (<= (hash-ref outcome 'rows) (hash-ref computation-limits 'result-rows))
              (or (not (eq? (hash-ref outcome 'state) 'rejected))
                  (symbol? (hash-ref outcome 'failure #f)))))
       (let* ([state-count (lambda (state)
                             (count (lambda (outcome) (eq? (hash-ref outcome 'state) state))
                                    outcomes))]
              [executed (state-count 'completed)]
              [cache-hits (state-count 'cache-hit)]
              [rejected (state-count 'rejected)]
              [unattempted (state-count 'unattempted)]
              [cancelled (state-count 'cancelled)]
              [successful (+ executed cache-hits)]
              [output-bytes (for/sum ([outcome (in-list outcomes)])
                              (hash-ref outcome 'bytes))]
              [result-rows (for/sum ([outcome (in-list outcomes)])
                             (hash-ref outcome 'rows))])
         (and (<= output-bytes (hash-ref computation-limits 'retained-output-bytes))
              (hasheq 'executed executed
                      'cache-hits cache-hits
                      'published (if (and (eq? (hash-ref plan 'mode) 'atomic)
                                          (positive? (+ rejected unattempted cancelled)))
                                     0
                                     successful)
                      'rejected rejected
                      'unattempted unattempted
                      'cancelled cancelled
                      'output-bytes output-bytes
                      'result-rows result-rows
                      'complete? #t)))))

;; Capability state exposes which optional owners make computation operational.
(define (computation-capability-states runtime)
  (define language? (hash-ref runtime 'language-ready? #f))
  (define execution? (and language?
                          (hash-ref runtime 'execution-adapter? #f)
                          (hash-ref runtime 'process-owner? #f)))
  (hasheq 'formulas language?
          'text-plots language?
          'graphical-plots (and language? (hash-ref runtime 'graphical-adapter? #f))
          'execution execution?
          'results language?
          'sessions execution?
          'cache language?
          'source-editing language?
          'tangling (and language? (hash-ref runtime 'resource-owner? #f))
          'noweb language?
          'batch execution?))

;; Resource profiles may reduce but never exceed a stable computation ceiling.
(define (validate-computation-resource-profile profile)
  (and (hash? profile)
       (for/and ([(key limit) (in-hash computation-limits)]
                 #:unless (memq key '(graph-depth cancellation-entries)))
         (define value (hash-ref profile key #f))
         (and (exact-positive-integer? value) (<= value limit)))))

;; Retained estimates account for output, cache, sessions, and result rows.
(define (estimate-computation-retained-bytes profile)
  (+ (hash-ref profile 'retained-output-bytes)
     (hash-ref profile 'cache-bytes)
     (* (hash-ref profile 'active-sessions) 4096)
     (* (hash-ref profile 'result-rows) 64)))

;; Temporary estimates account for graphs, targets, cells, processes, and files.
(define (estimate-computation-temporary-bytes profile)
  (+ (* (hash-ref profile 'formula-dependencies) 64)
     (* (hash-ref profile 'executable-targets) 128)
     (* (hash-ref profile 'table-cells) 32)
     (* (hash-ref profile 'child-processes) 4096)
     (* (hash-ref profile 'generated-files) 256)))
