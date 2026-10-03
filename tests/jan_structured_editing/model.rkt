#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         racket/match
         racket/string)

(provide structured-editing-limits
         structured-editing-resource-profiles
         local-cycle
         global-cycle
         normalize-hidden-ranges
         reveal-position
         estimate-retained-bytes
         estimate-temporary-bytes
         shift-list-indentation
         normalize-structural-targets
         structure-delimiters
         make-empty-table
         delimited-text->table
         normalize-table
         align-table
         table-rectangle
         derive-rich-presentation
         admit-preview
         publish-preview-cache
         normalize-authoring-configuration
         contextual-candidates
         resolve-structure-template
         resolve-authoring-context
         repeat-authoring-context
         validate-resource-profile)

;; These values mirror the accepted Stage 2 resource contract.
(define structured-editing-limits
  '#hasheq((hidden-ranges . 16384)
           (sparse-matches . 16384)
           (semantic-targets . 4096)
           (table-cells . 65536)
           (rewrite-splices . 16384)
           (completion-candidates . 512)
           (completion-bytes . 262144)
           (templates . 256)
           (completion-sources . 256)
           (configuration-bytes . 1048576)
           (active-previews-per-view . 8)
           (preview-result-bytes . 8388608)
           (preview-cache-bytes . 67108864)
           (cancellation-entries . 4096)))

;; The selected profiles exercise normal use, a large document, and every hard
;; capacity without requiring the complete editor executable.
(define structured-editing-resource-profiles
  (list
   '#hasheq((name . ordinary)
            (hidden-ranges . 48)
            (sparse-matches . 24)
            (semantic-targets . 8)
            (table-cells . 120)
            (rewrite-splices . 12)
            (completion-candidates . 40)
            (completion-bytes . 8192)
            (templates . 24)
            (completion-sources . 4)
            (configuration-bytes . 32768)
            (active-previews-per-view . 2)
            (preview-result-bytes . 1048576)
            (preview-cache-bytes . 8388608))
   '#hasheq((name . demanding)
            (hidden-ranges . 8192)
            (sparse-matches . 8192)
            (semantic-targets . 2048)
            (table-cells . 32768)
            (rewrite-splices . 8192)
            (completion-candidates . 384)
            (completion-bytes . 196608)
            (templates . 192)
            (completion-sources . 128)
            (configuration-bytes . 786432)
            (active-previews-per-view . 6)
            (preview-result-bytes . 6291456)
            (preview-cache-bytes . 50331648))
   '#hasheq((name . boundary)
            (hidden-ranges . 16384)
            (sparse-matches . 16384)
            (semantic-targets . 4096)
            (table-cells . 65536)
            (rewrite-splices . 16384)
            (completion-candidates . 512)
            (completion-bytes . 262144)
            (templates . 256)
            (completion-sources . 256)
            (configuration-bytes . 1048576)
            (active-previews-per-view . 8)
            (preview-result-bytes . 8388608)
            (preview-cache-bytes . 67108864))))

;; A heading cycles through its three local visibility states exactly.
(define (local-cycle state)
  (case state
    [(heading-only) 'direct-children]
    [(direct-children) 'complete-subtree]
    [(complete-subtree) 'heading-only]
    [else #f]))

;; One view cycles through the three complete-document visibility states.
(define (global-cycle state)
  (case state
    [(overview) 'contents]
    [(contents) 'show-all]
    [(show-all) 'overview]
    [else #f]))

;; Ranges are half-open pairs. Normalization validates bounds, sorts, and merges
;; overlapping or adjacent ranges into one canonical hidden projection.
(define (normalize-hidden-ranges source-bytes ranges)
  (and (exact-nonnegative-integer? source-bytes)
       (list? ranges)
       (let ([validated
              (for/list ([range (in-list ranges)]
                         #:when (match range
                                  [(list start end)
                                   (and (exact-nonnegative-integer? start)
                                        (exact-nonnegative-integer? end)
                                        (< start end)
                                        (<= end source-bytes))]
                                  [_ #f]))
                range)])
         (and (= (length validated) (length ranges))
              (reverse
               (for/fold ([result '()])
                         ([range (in-list (sort validated < #:key car))])
                 (match* (range result)
                   [((list start end) '()) (list (list start end))]
                   [((list start end) (cons (list prior-start prior-end) rest))
                    (if (<= start prior-end)
                        (cons (list prior-start (max prior-end end)) rest)
                        (cons range result))])))))))

;; Revealing a canonical position removes only the hidden interval containing
;; that position and retains all unrelated view-local ranges.
(define (reveal-position source-bytes ranges position)
  (define normalized (normalize-hidden-ranges source-bytes ranges))
  (and normalized
       (exact-nonnegative-integer? position)
       (<= position source-bytes)
       (filter (lambda (range)
                 (match-define (list start end) range)
                 (not (and (<= start position) (< position end))))
               normalized)))

;; A structural list shift changes each owned line together or rejects a
;; promotion that would cross the left margin.
(define (shift-list-indentation lines width direction)
  (and (list? lines)
       (exact-positive-integer? width)
       (memq direction '(promote demote))
       (for/and ([line (in-list lines)])
         (match line
           [(list indent text)
            (and (exact-nonnegative-integer? indent) (string? text)
                 (or (eq? direction 'demote) (>= indent width)))]
           [_ #f]))
       (for/list ([line (in-list lines)])
         (match-define (list indent text) line)
         (list ((if (eq? direction 'demote) + -) indent width) text))))

;; Multi-element commands admit only complete known ranges, sort them, and
;; reject the entire set if any pair overlaps.
(define (normalize-structural-targets complete-ranges targets limit)
  (and (list? complete-ranges)
       (list? targets)
       (exact-positive-integer? limit)
       (positive? (length targets))
       (<= (length targets) limit)
       (for/and ([target (in-list targets)]) (member target complete-ranges))
       (let ([ordered (sort targets < #:key car)])
         (and (for/and ([left (in-list ordered)]
                       [right (in-list (cdr ordered))])
                (<= (cadr left) (car right)))
              ordered))))

;; One admitted name generates both block delimiters; drawer close syntax is
;; fixed independently from the opening drawer name.
(define (structure-delimiters kind name)
  (and (symbol? kind)
       (string? name)
       (regexp-match? #px"^[A-Za-z0-9_-]+$" name)
       (case kind
         [(drawer) (list (string-append ":" name ":") ":END:")]
         [(block) (list (string-append "#+begin_" name)
                        (string-append "#+end_" name))]
         [else #f])))

;; Tables contain string rows and the symbol separator. Creation is bounded and
;; yields editable empty cells without attaching formula semantics.
(define (make-empty-table rows columns cell-limit)
  (and (exact-positive-integer? rows)
       (exact-positive-integer? columns)
       (exact-positive-integer? cell-limit)
       (<= (* rows columns) cell-limit)
       (build-list rows (lambda (_) (make-list columns "")))))

;; Delimited conversion preserves trimmed cell values and rejects empty,
;; inconsistent, or over-limit input as one candidate.
(define (delimited-text->table text delimiter cell-limit)
  (and (string? text)
       (char? delimiter)
       (exact-positive-integer? cell-limit)
       (let* ([lines (filter (lambda (line) (not (string=? line "")))
                             (string-split text "\n" #:trim? #f))]
              [rows (for/list ([line (in-list lines)])
                      (map string-trim (string-split line (string delimiter) #:trim? #f)))])
         (and (pair? rows)
              (positive? (length (car rows)))
              (for/and ([row (in-list rows)]) (= (length row) (length (car rows))))
              (<= (* (length rows) (length (car rows))) cell-limit)
              rows))))

;; Ragged source rows normalize by padding; separators carry the final width.
(define (normalize-table rows cell-limit)
  (and (list? rows)
       (pair? rows)
       (exact-positive-integer? cell-limit)
       (for/and ([row (in-list rows)])
         (or (eq? row 'separator)
             (and (list? row) (pair? row) (andmap string? row))))
       (let ([columns (for/fold ([width 0]) ([row (in-list rows)])
                        (if (list? row) (max width (length row)) width))])
         (and (positive? columns)
              (<= (* columns (count list? rows)) cell-limit)
              (for/list ([row (in-list rows)])
                (if (eq? row 'separator)
                    (list 'separator columns)
                    (append row (make-list (- columns (length row)) ""))))))))

;; Alignment computes terminal-compatible widths while stored values remain
;; unchanged. Combining marks occupy zero cells and common wide ranges occupy two.
(define (model-char-width character)
  (define scalar (char->integer character))
  (cond
    [(memq (char-general-category character) '(mn me cf)) 0]
    [(or (<= #x1100 scalar #x115f)
         (<= #x2e80 scalar #xa4cf)
         (<= #xac00 scalar #xd7a3)
         (<= #xf900 scalar #xfaff)
         (<= #x1f300 scalar #x1faff)
         (<= #x20000 scalar #x3ffff)) 2]
    [else 1]))

(define (model-string-width text)
  (for/sum ([character (in-string text)]) (model-char-width character)))

(define (align-table rows cell-limit)
  (define normalized (normalize-table rows cell-limit))
  (and normalized
       (let* ([data (filter (lambda (row) (not (eq? (car row) 'separator))) normalized)]
              [columns (length (car data))]
              [widths (for/list ([column (in-range columns)])
                        (for/fold ([width 1]) ([row (in-list data)])
                          (max width (model-string-width (list-ref row column)))))])
         (for/list ([row (in-list normalized)])
           (if (eq? (car row) 'separator)
               (string-append "|"
                              (string-join
                               (for/list ([width (in-list widths)])
                                 (make-string (+ width 2) #\-))
                               "+")
                              "|")
               (string-append
                "| "
                (string-join
                 (for/list ([cell (in-list row)] [width (in-list widths)])
                   (string-append cell (make-string (- width (model-string-width cell)) #\space)))
                 " | ")
                " |"))))))

;; Rectangles use half-open row and column coordinates and reject separators,
;; malformed bounds, or a destination larger than the admitted cell limit.
(define (table-rectangle rows row-start row-end column-start column-end cell-limit)
  (define normalized (normalize-table rows cell-limit))
  (and normalized
       (exact-nonnegative-integer? row-start)
       (exact-nonnegative-integer? column-start)
       (exact-nonnegative-integer? row-end)
       (exact-nonnegative-integer? column-end)
       (< row-start row-end)
       (< column-start column-end)
       (<= row-end (length normalized))
       (<= column-end (length (car (filter list? rows))))
       (<= (* (- row-end row-start) (- column-end column-start)) cell-limit)
       (let ([selected (take (drop normalized row-start) (- row-end row-start))])
         (and (andmap (lambda (row) (not (eq? (car row) 'separator))) selected)
              (for/list ([row (in-list selected)])
                (take (drop row column-start) (- column-end column-start)))))))

;; Rich presentation is derived from exact source ranges. A terminal surface
;; retains source while a rich surface may attach non-mutating display text.
(define (derive-rich-presentation source surface items)
  (and (string? source)
       (memq surface '(rich terminal))
       (list? items)
       (for/and ([item (in-list items)])
         (match item
           [(list start end kind display)
            (and (exact-nonnegative-integer? start)
                 (exact-nonnegative-integer? end)
                 (< start end)
                 (<= end (string-length source))
                 (memq kind '(role markup entity indent number))
                 (string? display))]
           [_ #f]))
       (hasheq 'source source
               'surface surface
               'fallback? (eq? surface 'terminal)
               'items (if (eq? surface 'terminal)
                          (filter (lambda (item) (eq? (list-ref item 2) 'role)) items)
                          items))))

;; Image previews require explicit resource admission. Missing adapters and
;; unsupported surfaces select source fallback without performing an effect.
(define (admit-preview kind adapter? surface? resource-admitted?)
  (and (memq kind '(latex image))
       (cond
         [(or (not adapter?) (not surface?)) 'source-fallback]
         [(and (eq? kind 'image) (not resource-admitted?)) #f]
         [else 'pending])))

;; Publishing a copied result evicts oldest ready entries until the cache fits.
;; A stale identity rejects the whole candidate and preserves the prior cache.
(define (publish-preview-cache entries request-id bytes limit exact?)
  (and (list? entries)
       (exact-positive-integer? request-id)
       (exact-positive-integer? bytes)
       (exact-positive-integer? limit)
       exact?
       (<= bytes limit)
       (let loop ([retained entries])
         (if (<= (+ bytes (for/sum ([entry (in-list retained)]) (cadr entry))) limit)
             (append retained (list (list request-id bytes)))
             (and (pair? retained) (loop (cdr retained)))))))

(define factory-completion-values
  '#hasheq((keyword . ("#+title:" "#+author:" "#+options:"))
           (task-state . ("TODO" "DONE"))
           (tag . ("work" "note"))
           (property . ("ID" "CUSTOM_ID"))
           (link-form . ("file:" "https:" "id:"))
           (target . ("<<target>>" "<<<radio-target>>>"))
           (block-name . ("src" "example" "quote" "comment"))
           (language . ("odin" "racket" "go" "rust" "typescript"))
           (header-argument . (":results" ":exports" ":tangle"))
           (file-setting . ("#+startup:" "#+property:" "#+language:"))))

(define factory-structure-templates
  '#hasheq((h1 . (document "* Heading\n"))
           (ul . (document "- Item\n"))
           (drawer . (heading ":NOTES:\n\n:END:\n"))
           (src . (document "#+begin_src \n\n#+end_src\n"))
           (quote . (document "#+begin_quote\n\n#+end_quote\n"))
           (table . (document "| column |\n|--------|\n|        |\n"))))

;; A complete configured generation either normalizes wholly or leaves the
;; factory-only policy available to the caller.
(define (normalize-authoring-configuration generation templates sources)
  (define template-keys (map car templates))
  (define source-names (map car sources))
  (define candidate-count
    (for/sum ([source (in-list sources)]) (length (caddr source))))
  (define retained-bytes
    (+ (for/sum ([template (in-list templates)])
         (+ (bytes-length (string->bytes/utf-8 (symbol->string (car template))))
            (bytes-length (string->bytes/utf-8 (symbol->string (cadr template))))
            (bytes-length (string->bytes/utf-8 (caddr template)))))
       (for/sum ([source (in-list sources)])
         (+ (bytes-length (string->bytes/utf-8 (symbol->string (car source))))
            (bytes-length (string->bytes/utf-8 (symbol->string (cadr source))))
            (for/sum ([value (in-list (caddr source))])
              (bytes-length (string->bytes/utf-8 value)))))))
  (and (exact-positive-integer? generation)
       (<= (length templates) (hash-ref structured-editing-limits 'templates))
       (<= (length sources) (hash-ref structured-editing-limits 'completion-sources))
       (<= candidate-count (hash-ref structured-editing-limits 'completion-candidates))
       (<= retained-bytes (hash-ref structured-editing-limits 'configuration-bytes))
       (= (length template-keys) (length (remove-duplicates template-keys)))
       (= (length source-names) (length (remove-duplicates source-names)))
       (for/and ([template (in-list templates)])
         (match template
           [(list (? symbol?) (? symbol?) (? non-empty-string?)) #t]
           [_ #f]))
       (for/and ([source (in-list sources)])
         (match source
           [(list (? symbol?) (? symbol?) (and values (list (? non-empty-string?) ...)))
            (= (length values) (length (remove-duplicates values)))]
           [_ #f]))
       (hasheq 'generation generation
               'templates templates
               'sources sources
               'retained-bytes retained-bytes)))

;; Factory candidates precede configured values and duplicate configured text
;; cannot replace factory provenance.
(define (contextual-candidates kind configuration)
  (define factory (hash-ref factory-completion-values kind '()))
  (define configured
    (if configuration
        (append*
         (for/list ([source (in-list (hash-ref configuration 'sources))]
                    #:when (eq? (cadr source) kind))
           (caddr source)))
        '()))
  (define combined (remove-duplicates (append factory configured)))
  (and (<= (length combined) (hash-ref structured-editing-limits 'completion-candidates))
       (<= (for/sum ([value (in-list combined)])
             (bytes-length (string->bytes/utf-8 value)))
           (hash-ref structured-editing-limits 'completion-bytes))
       combined))

;; Factory template keys are protected from configured conflicts.
(define (resolve-structure-template key configuration)
  (or (hash-ref factory-structure-templates key #f)
      (and configuration
           (for/first ([template (in-list (hash-ref configuration 'templates))]
                       #:when (eq? (car template) key))
             (cdr template)))))

;; Candidate contexts are (name start end precedence future-owner). The highest
;; stable precedence wins and future owners produce explicit unavailability.
(define (resolve-authoring-context contexts point)
  (define admitted
    (filter (lambda (entry) (and (<= (cadr entry) point) (<= point (caddr entry))))
            contexts))
  (and (pair? admitted)
       (let* ([ordered
               (sort admitted
                     (lambda (left right)
                       (or (> (list-ref left 3) (list-ref right 3))
                           (and (= (list-ref left 3) (list-ref right 3))
                                (< (- (caddr left) (cadr left))
                                   (- (caddr right) (cadr right)))))))]
              [selected (car ordered)]
              [future-owner (list-ref selected 4)])
         (hasheq 'context (car selected)
                 'status (if future-owner 'unavailable 'resolved)
                 'owner future-owner
                 'range (list (cadr selected) (caddr selected))))))

;; Repeat metadata contains no range; resolution always uses the new point.
(define (repeat-authoring-context contexts point metadata)
  (and (hash? metadata)
       (hash-has-key? metadata 'command)
       (let ([resolved (resolve-authoring-context contexts point)])
         (and resolved
              (hash-set resolved 'command (hash-ref metadata 'command))))))

(define resource-keys
  '(hidden-ranges sparse-matches semantic-targets table-cells rewrite-splices
                  completion-candidates completion-bytes templates
                  completion-sources configuration-bytes
                  active-previews-per-view preview-result-bytes
                  preview-cache-bytes))

;; The estimate intentionally overstates copied records to make the selected
;; limits safe before native layout details are finalized.
(define (estimate-retained-bytes profile)
  (+ (* 24 (hash-ref profile 'hidden-ranges))
     (* 32 (hash-ref profile 'sparse-matches))
     (* 48 (hash-ref profile 'semantic-targets))
     (* 16 (hash-ref profile 'table-cells))
     (hash-ref profile 'completion-bytes)
     (hash-ref profile 'configuration-bytes)
     (hash-ref profile 'preview-cache-bytes)))

(define (estimate-temporary-bytes profile)
  (+ (* 32 (hash-ref profile 'rewrite-splices))
     (* 32 (hash-ref profile 'completion-candidates))
     (* 24 (hash-ref profile 'table-cells))
     (* (hash-ref profile 'active-previews-per-view)
        (hash-ref profile 'preview-result-bytes))))

(define (validate-resource-profile profile)
  (and (hash? profile)
       (symbol? (hash-ref profile 'name #f))
       (for/and ([key (in-list resource-keys)])
         (define value (hash-ref profile key #f))
         (and (exact-nonnegative-integer? value)
              (<= value (hash-ref structured-editing-limits key))))))
