#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/date
         racket/format
         racket/list
         racket/match
         racket/string)

(provide planning-limits
         planning-resource-profiles
         normalize-workflow
         workflow-next-state
         derive-task-statistics
         summarize-habit
         normalize-priority
         resolve-effective-tags
         match-tag-query
         resolve-property
         capture-column-view
         canonical-timestamp
         advance-recurrence
         clock-start
         clock-stop
         timer-tick
         resolve-zone-precedence
         resolve-local-time
         select-refile-candidates
         refile-publication-step
         archive-origin-properties
         archive-visible?
         expand-capture-template
         attachment-publication-step
         deduplicate-feed-entries
         index-agenda-sources
         query-agenda-entries
         present-agenda-entries
         agenda-cache-current?
         summarize-agenda-sources
         plan-multi-resource-outcomes
         recover-active-clock
         estimate-planning-retained-bytes
         estimate-planning-temporary-bytes
         validate-planning-resource-profile)

;; These values mirror the accepted Planning and Agenda resource contract.
(define planning-limits
  '#hasheq((semantic-targets . 4096)
           (source-documents . 1024)
           (agenda-entries . 65536)
           (capture-candidates . 16384)
           (refile-candidates . 16384)
           (attachment-outcomes . 4096)
           (feed-sources . 256)
           (feed-entries . 16384)
           (copied-text-bytes . 16777216)
           (derived-state-bytes . 67108864)
           (time-source-replacements . 64)
           (recurrence-steps . 4096)
           (cancellation-entries . 4096)))

;; Ordinary, demanding, and exact-boundary profiles remain independently bounded.
(define planning-resource-profiles
  (list
   '#hasheq((name . ordinary)
            (semantic-targets . 32)
            (source-documents . 12)
            (agenda-entries . 512)
            (capture-candidates . 64)
            (refile-candidates . 64)
            (attachment-outcomes . 16)
            (feed-sources . 4)
            (feed-entries . 128)
            (copied-text-bytes . 262144)
            (derived-state-bytes . 2097152)
            (time-source-replacements . 8)
            (recurrence-steps . 52))
   '#hasheq((name . demanding)
            (semantic-targets . 2048)
            (source-documents . 768)
            (agenda-entries . 49152)
            (capture-candidates . 12288)
            (refile-candidates . 12288)
            (attachment-outcomes . 3072)
            (feed-sources . 192)
            (feed-entries . 12288)
            (copied-text-bytes . 12582912)
            (derived-state-bytes . 50331648)
            (time-source-replacements . 48)
            (recurrence-steps . 2048))
   '#hasheq((name . boundary)
            (semantic-targets . 4096)
            (source-documents . 1024)
            (agenda-entries . 65536)
            (capture-candidates . 16384)
            (refile-candidates . 16384)
            (attachment-outcomes . 4096)
            (feed-sources . 256)
            (feed-entries . 16384)
            (copied-text-bytes . 16777216)
            (derived-state-bytes . 67108864)
            (time-source-replacements . 64)
            (recurrence-steps . 4096))))

;; A workflow is ordered, uniquely named, and contains unfinished and finished states.
(define (normalize-workflow identity states)
  (and (symbol? identity)
       (pair? states)
       (for/and ([state (in-list states)])
         (match state
           [(list (? symbol?) (? boolean?) key log)
            (and (or (not key) (char? key))
                 (memq log '(none state note time)))]
           [_ #f]))
       (= (length states) (length (remove-duplicates (map car states))))
       (ormap (lambda (state) (not (cadr state))) states)
       (ormap cadr states)
       (hasheq 'identity identity 'states states)))

;; Forward and backward selection stays within one confirmed workflow sequence.
(define (workflow-next-state workflow current direction blocked?)
  (and workflow
       (memq direction '(forward backward))
       (not blocked?)
       (let* ([states (hash-ref workflow 'states)]
              [names (map car states)]
              [position (index-of names current)])
         (and position
              (list-ref names
                        (modulo ((if (eq? direction 'forward) add1 sub1) position)
                                (length names)))))))

;; Completion cookies count checked children; intermediate state is unfinished.
(define (derive-task-statistics states)
  (and (list? states)
       (andmap (lambda (state) (memq state '(unchecked intermediate checked))) states)
       (let* ([total (length states)]
              [completed (count (lambda (state) (eq? state 'checked)) states)])
         (hasheq 'completed completed
                 'total total
                 'percent (if (zero? total) 0 (quotient (* completed 100) total))))))

;; Habit presentation derives from history without changing any occurrence.
(define (summarize-habit occurrences)
  (and (list? occurrences)
       (andmap boolean? occurrences)
       (hasheq 'completed (count values occurrences)
               'missed (count not occurrences)
               'current-streak
               (length (takef (reverse occurrences) values)))))

;; Alphabetic and numeric priority forms normalize while retaining source elsewhere.
(define (normalize-priority source highest lowest default-value)
  (define value
    (cond
      [(equal? source "") default-value]
      [(regexp-match? #px"^[A-Za-z]$" source)
       (add1 (- (char->integer (char-upcase (string-ref source 0)))
                (char->integer #\A)))]
      [(regexp-match? #px"^[0-9]+$" source) (string->number source)]
      [else #f]))
  (and value (<= highest value lowest) value))

;; Effective tags retain their first origin, expand groups, and apply exceptions.
(define (resolve-effective-tags candidates groups exceptions)
  (define records
    (for/fold ([records '()]) ([candidate (in-list candidates)])
      (match candidate
        [(list name origin owner #t)
         (if (or (member name exceptions)
                 (assoc name records))
             records
             (append records (list (list name origin owner))))]
        [(list _ _ _ #f) records]
        [_ #f])))
  (and records
       (for/fold ([resolved records]) ([group (in-list groups)])
         (and resolved
              (match group
                [(list name 'members members)
                 (if (assoc name resolved)
                     (for/fold ([expanded resolved]) ([tag-name (in-list members)])
                       (if (or (member tag-name exceptions) (assoc tag-name expanded))
                           expanded
                           (append expanded (list (list tag-name 'grouped name)))))
                     resolved)]
                [(list name 'regexp expression)
                 (if (assoc name resolved)
                     (for/fold ([expanded resolved]) ([candidate (in-list candidates)])
                       (define tag (car candidate))
                       (if (or (not (cadddr candidate))
                               (member tag exceptions)
                               (assoc tag expanded)
                               (not (regexp-match-exact? (pregexp expression) tag)))
                           expanded
                           (append expanded (list (list tag 'grouped name)))))
                     resolved)]
                [_ #f])))))

;; Postfix Boolean tag matching is deterministic and bounded by the supplied tokens.
(define (match-tag-query records query)
  (define names (map car records))
  (define stack
    (for/fold ([stack '()]) ([token (in-list query)])
      (and stack
           (match token
             [(list 'tag name) (cons (and (member name names) #t) stack)]
             ['not (and (pair? stack) (cons (not (car stack)) (cdr stack)))]
             [(or 'and 'or)
              (and (pair? stack)
                   (pair? (cdr stack))
                   (cons ((if (eq? token 'and) and-proc or-proc)
                          (cadr stack)
                          (car stack))
                         (cddr stack)))]
             [_ #f]))))
  (and stack (= (length stack) 1) (car stack)))

(define (and-proc left right) (and left right))
(define (or-proc left right) (or left right))

;; Stored, inherited, derived, and additive property facts remain inspectable.
(define (resolve-property name candidates generation)
  (define matching (filter (lambda (candidate) (eq? (car candidate) name)) candidates))
  (define primary (findf (lambda (candidate) (not (list-ref candidate 3))) matching))
  (define additive (filter (lambda (candidate) (list-ref candidate 3)) matching))
  (and (positive? generation)
       (or primary (pair? additive))
       (hasheq 'name name
               'value (and primary (cadr primary))
               'origin (and primary (caddr primary))
               'owner (and primary (list-ref primary 4))
               'editable? (and primary (eq? (caddr primary) 'stored))
               'components (map (lambda (candidate)
                                  (list (cadr candidate) (caddr candidate)))
                                additive)
               'generation generation)))

;; Captured column views are deterministic tab-separated snapshots.
(define (capture-column-view definitions rows generation)
  (and (positive? generation)
       (pair? definitions)
       (string-append
        (string-join (map cadr definitions) "\t") "\n"
        (apply string-append
               (for/list ([row (in-list rows)])
                 (string-append
                  (string-join
                   (for/list ([definition (in-list definitions)])
                     (define property (resolve-property (car definition) row generation))
                     (if (and property (hash-ref property 'value))
                         (hash-ref property 'value)
                         ""))
                   "\t")
                  "\n"))))))

;; Stored syntax is canonical English-compatible regardless of presentation locale.
(define (canonical-timestamp year month day
                             #:time [time #f]
                             #:active? [active? #t]
                             #:repeater [repeater #f]
                             #:warning [warning #f]
                             #:locale [_locale "en-US"])
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (define instant (find-seconds 0 0 12 day month year #f))
    (define weekday (vector-ref #("Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat")
                                (date-week-day (seconds->date instant #f))))
    (define opening (if active? "<" "["))
    (define closing (if active? ">" "]"))
    (string-append opening
                   (format "~a-~a-~a ~a"
                           (~r year #:min-width 4 #:pad-string "0")
                           (~r month #:min-width 2 #:pad-string "0")
                           (~r day #:min-width 2 #:pad-string "0")
                           weekday)
                   (if time (format " ~a:~a" (~r (car time) #:min-width 2 #:pad-string "0")
                                             (~r (cadr time) #:min-width 2 #:pad-string "0")) "")
                   (if repeater (format " ~a~a~a" (car repeater) (cadr repeater) (caddr repeater)) "")
                   (if warning (format " -~a~a" (car warning) (cadr warning)) "")
                   closing)))

;; The independent recurrence model covers +, ++, and .+ day/week behavior.
(define (advance-recurrence stored completed now kind amount unit)
  (define delta (* amount (case unit [(day) 1] [(week) 7] [else 0])))
  (and (positive? delta)
       (memq kind '(stored-base catch-up completion-base))
       (let* ([base (if (eq? kind 'completion-base) completed stored)]
              [first (+ base delta)])
         (if (eq? kind 'catch-up)
             (let loop ([candidate first] [steps 1])
               (if (> candidate now)
                   (cons candidate steps)
                   (loop (+ candidate delta) (add1 steps))))
             (cons first 1)))))

;; One clock domain rejects overlap and retains exact source identity.
(define (clock-start current target instant)
  (and (or (not current) (eq? (hash-ref current 'state) 'resolved))
       (hasheq 'state 'active 'target target 'started instant)))

(define (clock-stop current instant #:excluded [excluded 0])
  (and current
       (eq? (hash-ref current 'state) 'active)
       (>= instant (hash-ref current 'started))
       (<= excluded (- instant (hash-ref current 'started)))
       (hasheq 'state 'resolved
               'target (hash-ref current 'target)
               'started (hash-ref current 'started)
               'ended instant
               'elapsed (- instant (hash-ref current 'started) excluded))))

;; Notification failure is visible but does not invalidate completed timer state.
(define (timer-tick timer now notification-available?)
  (match timer
    [(hash-table ('mode 'countdown) ('state 'running) ('started started)
                 ('target target) ('notified? notified?))
     (define elapsed (- now started))
     (if (< elapsed target)
         (hasheq 'state 'running 'elapsed elapsed 'remaining (- target elapsed)
                 'notification 'not-requested)
         (hasheq 'state 'completed 'elapsed elapsed 'remaining 0
                 'notification (cond [notified? 'not-requested]
                                     [notification-available? 'requested]
                                     [else 'unavailable])))]
    [_ #f]))

;; Invocation, document, Project, Workspace, user, then system is fixed precedence.
(define (resolve-zone-precedence candidates)
  (for/first ([owner (in-list '(invocation document project workspace user system))]
              #:when (hash-ref candidates owner #f))
    (cons owner (hash-ref candidates owner))))

;; Gap times reject and folded times require an explicit earlier or later decision.
(define (resolve-local-time classification policy earlier later)
  (case classification
    [(valid) earlier]
    [(gap) #f]
    [(fold) (case policy [(earlier) earlier] [(later) later] [else #f])]
    [else #f]))

;; Refile candidates compose level, file, context, path, recent, and predicate constraints.
(define (select-refile-candidates candidates constraints)
  (and (list? candidates)
       (hash? constraints)
       (filter
        (lambda (candidate)
          (match candidate
            [(list _ level file project workspace path recent admitted?)
             (and (exact-positive-integer? level)
                  (string? file)
                  (string? path)
                  (boolean? admitted?)
                  (or (not (hash-ref constraints 'minimum-level #f))
                      (>= level (hash-ref constraints 'minimum-level)))
                  (or (not (hash-ref constraints 'maximum-level #f))
                      (<= level (hash-ref constraints 'maximum-level)))
                  (or (not (hash-ref constraints 'file #f))
                      (equal? file (hash-ref constraints 'file)))
                  (or (not (hash-ref constraints 'project #f))
                      (equal? project (hash-ref constraints 'project)))
                  (or (not (hash-ref constraints 'workspace #f))
                      (equal? workspace (hash-ref constraints 'workspace)))
                  (or (not (hash-ref constraints 'path-prefix #f))
                      (string-prefix? path (hash-ref constraints 'path-prefix)))
                  (or (not (hash-ref constraints 'recent-limit #f))
                      (and (exact-positive-integer? recent)
                           (<= recent (hash-ref constraints 'recent-limit))))
                  (or (not (hash-ref constraints 'require-predicate? #f)) admitted?))]
            [_ #f]))
        candidates)))

;; External move publication writes the destination first and exposes any duplicate for recovery.
(define (refile-publication-step record event)
  (match record
    [(hash-table ('mode mode) ('state state)
                 ('destination-committed? destination-committed?)
                 ('source-removed? source-removed?))
     (case state
       [(prepared)
        (case event
          [(cancel) (hasheq 'mode mode 'state 'cancelled
                            'destination-committed? #f 'source-removed? #f)]
          [(destination-fail) (hasheq 'mode mode 'state 'failed
                                      'destination-committed? #f 'source-removed? #f)]
          [(destination-commit)
           (hasheq 'mode mode
                   'state (if (eq? mode 'copy) 'completed 'destination-committed)
                   'destination-committed? #t
                   'source-removed? #f)]
          [else #f])]
       [(destination-committed)
        (case event
          [(source-commit) (hasheq 'mode mode 'state 'completed
                                   'destination-committed? #t 'source-removed? #t)]
          [(source-fail cancel) (hasheq 'mode mode 'state 'recovery-required
                                        'destination-committed? #t 'source-removed? #f)]
          [else #f])]
       [(recovery-required)
        (case event
          [(source-commit) (hasheq 'mode mode 'state 'completed
                                   'destination-committed? #t 'source-removed? #t)]
          [(rollback-destination) (hasheq 'mode mode 'state 'rolled-back
                                          'destination-committed? #f 'source-removed? #f)]
          [else #f])]
       [else #f])]
    [_ #f]))

;; Archive origins remain ordinary properties sufficient for visiting or restoring source context.
(define (archive-origin-properties provider resource node parent revision position)
  (and (exact-positive-integer? provider)
       (non-empty-string? resource)
       (exact-positive-integer? node)
       (exact-nonnegative-integer? parent)
       (exact-nonnegative-integer? revision)
       (exact-nonnegative-integer? position)
       (list (cons 'JAN_ARCHIVE_SOURCE_PROVIDER provider)
             (cons 'JAN_ARCHIVE_SOURCE resource)
             (cons 'JAN_ARCHIVE_NODE node)
             (cons 'JAN_ARCHIVE_PARENT parent)
             (cons 'JAN_ARCHIVE_REVISION revision)
             (cons 'JAN_ARCHIVE_POSITION position))))

(define (archive-visible? archived? include-archived?)
  (or (not archived?) include-archived?))

;; Capture expansion substitutes only admitted values and retains one explicit cursor.
(define (expand-capture-template template values position input-limit output-limit)
  (define valid-values?
    (and (list? values)
         (for/and ([value (in-list values)])
           (and (pair? value) (string? (car value)) (string? (cdr value))))
         (= (length values) (length (remove-duplicates (map car values))))
         (<= (for/sum ([value (in-list values)]) (string-length (cdr value))) input-limit)))
  (define expanded
    (and valid-values?
         (for/fold ([text template]) ([value (in-list values)])
           (string-replace text (format "%{~a}" (car value)) (cdr value)))))
  (define cursor-matches (and expanded (regexp-match-positions* #px"%\\?" expanded)))
  (and (string? template)
       (memq position '(start cursor end))
       (exact-positive-integer? input-limit)
       (exact-positive-integer? output-limit)
       expanded
       (not (regexp-match? #px"%\\{" expanded))
       (<= (length cursor-matches) 1)
       (or (not (eq? position 'cursor)) (= (length cursor-matches) 1))
       (let* ([cursor-position (and (pair? cursor-matches) (caar cursor-matches))]
              [text (string-replace expanded "%?" "")]
              [cursor (case position
                        [(start) 0]
                        [(end) (string-length text)]
                        [else cursor-position])])
         (and (positive? (string-length text))
              (<= (string-length text) output-limit)
              (hasheq 'text text 'cursor cursor)))))

;; Resource completion precedes document publication; partial state remains recoverable.
(define (attachment-publication-step record event)
  (match record
    [(hash-table ('state state) ('document-change? document-change?)
                 ('repository? repository?) ('reversible? reversible?)
                 ('resource-committed? resource-committed?)
                 ('document-committed? document-committed?))
     (define (next next-state resource? document?)
       (hasheq 'state next-state
               'document-change? document-change?
               'repository? repository?
               'reversible? reversible?
               'resource-committed? resource?
               'document-committed? document?))
     (case state
       [(prepared)
        (case event
          [(cancel) (next 'cancelled #f #f)]
          [(resource-fail) (next 'failed #f #f)]
          [(resource-commit)
           (next (cond [document-change? 'resource-committed]
                       [repository? 'repository-pending]
                       [else 'completed])
                 #t #f)]
          [else #f])]
       [(resource-committed)
        (case event
          [(document-commit)
           (next (if repository? 'repository-pending 'completed) #t #t)]
          [(document-fail cancel) (next 'recovery-required #t #f)]
          [else #f])]
       [(recovery-required)
        (case event
          [(document-commit)
           (next (if repository? 'repository-pending 'completed) #t #t)]
          [(rollback-resource) (and reversible? (next 'rolled-back #f #f))]
          [else #f])]
       [(repository-pending)
        (case event
          [(repository-commit) (next 'completed resource-committed? document-committed?)]
          [(repository-fail) (next 'completed resource-committed? document-committed?)]
          [else #f])]
       [else #f])]
    [_ #f]))

;; Feed candidates deduplicate against retention and each other without open-time fetches.
(define (deduplicate-feed-entries reason entries retained entry-limit retention-limit)
  (and (memq reason '(explicit scheduled))
       (list? entries)
       (list? retained)
       (= (length retained) (length (remove-duplicates retained)))
       (exact-positive-integer? entry-limit)
       (exact-positive-integer? retention-limit)
       (let-values ([(selected duplicates)
                     (for/fold ([selected '()] [duplicates 0]
                                #:result (values (reverse selected) duplicates))
                               ([entry (in-list entries)])
                       (define identity (car entry))
                       (if (or (member identity retained)
                               (assoc identity selected))
                           (values selected (add1 duplicates))
                           (values (cons entry selected) duplicates)))])
         (define admitted (take selected (min entry-limit (length selected))))
         (hasheq 'entries admitted
                 'duplicates duplicates
                 'truncated? (> (length selected) entry-limit)
                 'retained (take (append (map car admitted) retained)
                                 (min retention-limit
                                      (+ (length admitted) (length retained))))))))

;; One agenda index keeps failed source outcomes while indexing confirmed rows only.
(define (index-agenda-sources sources generation configuration-generation entry-limit)
  (and (list? sources)
       (exact-positive-integer? generation)
       (exact-positive-integer? configuration-generation)
       (exact-positive-integer? entry-limit)
       (for/and ([source (in-list sources)])
         (match source
           [(hash-table ('state (or 'confirmed 'stale 'unavailable 'failed))
                        ('configuration source-generation)
                        ('entries entries))
            (and (exact-positive-integer? source-generation)
                 (list? entries)
                 (or (and (eq? (hash-ref source 'state) 'confirmed)
                          (= source-generation configuration-generation))
                     (null? entries)))]
           [_ #f]))
       (let ([entries
              (append-map (lambda (source)
                            (if (eq? (hash-ref source 'state) 'confirmed)
                                (hash-ref source 'entries)
                                '()))
                          sources)])
         (and (<= (length entries) entry-limit)
              (hasheq 'generation generation
                      'configuration configuration-generation
                      'sources sources
                      'entries entries
                      'confirmed (count (lambda (source)
                                          (eq? (hash-ref source 'state) 'confirmed)) sources)
                      'stale (count (lambda (source)
                                      (eq? (hash-ref source 'state) 'stale)) sources)
                      'unavailable (count (lambda (source)
                                            (eq? (hash-ref source 'state) 'unavailable)) sources)
                      'failed (count (lambda (source)
                                       (eq? (hash-ref source 'state) 'failed)) sources))))))

;; Query families consume copied row facts and never reinterpret failed sources as absence.
(define (query-agenda-entries index kind primary secondary start end include-archived?)
  (and index
       (memq kind '(daily weekly unfinished task tag property text project stuck
                          clock effort column diary calendar anniversary reminder extension))
       (filter
        (lambda (entry)
          (and (or include-archived? (not (hash-ref entry 'archived? #f)))
               (case kind
                 [(daily weekly)
                  (for/or ([key (in-list '(timestamp scheduled deadline))])
                    (define instant (hash-ref entry key 0))
                    (and (positive? instant) (<= start instant end)))]
                 [(unfinished) (and (hash-ref entry 'task #f)
                                    (not (hash-ref entry 'finished? #f)))]
                 [(task) (equal? (hash-ref entry 'task #f) primary)]
                 [(tag) (member primary (hash-ref entry 'tags '()))]
                 [(property) (equal? (hash-ref (hash-ref entry 'properties #hasheq())
                                               primary #f)
                                     secondary)]
                 [(text) (string-contains? (hash-ref entry 'text "") primary)]
                 [(project) (equal? (hash-ref entry 'project #f) primary)]
                 [(stuck) (hash-ref entry 'stuck? #f)]
                 [(clock) (positive? (hash-ref entry 'clock 0))]
                 [(effort) (positive? (hash-ref entry 'effort 0))]
                 [(column) (non-empty-string? (hash-ref entry 'column ""))]
                 [else (eq? (hash-ref entry 'kind #f) kind)])))
        (hash-ref index 'entries))))

;; Stable presentation order and explicit truncation preserve full match counts.
(define (present-agenda-entries entries key descending? limit)
  (and (list? entries)
       (exact-positive-integer? limit)
       (for/and ([entry (in-list entries)]) (hash-has-key? entry key))
       (let* ([ordered (sort entries
                             (if descending?
                                 (lambda (left right) (> (hash-ref left key) (hash-ref right key)))
                                 (lambda (left right) (< (hash-ref left key) (hash-ref right key)))))]
              [rows (take ordered (min limit (length ordered)))])
         (hasheq 'rows rows
                 'matched (length ordered)
                 'truncated? (> (length ordered) limit)))))

;; Cache acceleration is valid only for the exact index and configuration generation.
(define (agenda-cache-current? key index)
  (and (hash? key)
       (hash? index)
       (equal? (hash-ref key 'generation #f) (hash-ref index 'generation #f))
       (equal? (hash-ref key 'configuration #f) (hash-ref index 'configuration #f))))

;; Missing and stale sources remain visible in the summary and never become absence.
(define (summarize-agenda-sources results entry-limit)
  (and (list? results)
       (exact-positive-integer? entry-limit)
       (for/and ([result (in-list results)])
         (match result
           [(list _ (or 'confirmed 'stale 'unavailable) (? exact-nonnegative-integer?)) #t]
           [_ #f]))
       (let* ([confirmed (filter (lambda (result) (eq? (cadr result) 'confirmed)) results)]
              [entries (for/sum ([result (in-list confirmed)]) (caddr result))])
         (hasheq 'confirmed (length confirmed)
                 'stale (count (lambda (result) (eq? (cadr result) 'stale)) results)
                 'unavailable (count (lambda (result) (eq? (cadr result) 'unavailable)) results)
                 'entries (min entries entry-limit)
                 'truncated? (> entries entry-limit)
                 'complete? (and (<= entries entry-limit)
                                 (= (length confirmed) (length results)))))))

;; Multi-resource outcomes are stable, attributable, and explicit about recovery.
(define (plan-multi-resource-outcomes mode outcomes)
  (and (memq mode '(atomic recoverable best-effort))
       (list? outcomes)
       (for/and ([outcome (in-list outcomes)])
         (match outcome
           [(list _ (or 'ready 'committed 'rejected 'cancelled 'unattempted)) #t]
           [_ #f]))
       (case mode
         [(atomic)
          (if (andmap (lambda (outcome) (eq? (cadr outcome) 'ready)) outcomes)
              (map (lambda (outcome) (list (car outcome) 'committed)) outcomes)
              (map (lambda (outcome) (list (car outcome) 'rejected)) outcomes))]
         [(recoverable)
          (hasheq 'state
                  (if (ormap (lambda (outcome) (eq? (cadr outcome) 'committed)) outcomes)
                      'reconciliation-required
                      'failed)
                  'outcomes outcomes)]
         [(best-effort) outcomes])))

;; Startup never silently discards, resumes, or invents an active clock.
(define (recover-active-clock record source-current?)
  (match record
    [(hash-table ('schema 1) ('state (or 'active 'recovery-required 'resolved)))
     (cond
       [(eq? (hash-ref record 'state) 'resolved) 'resolved]
       [source-current? 'active]
       [else 'recovery-required])]
    [_ 'quarantined]))

(define (estimate-planning-retained-bytes profile)
  (+ (hash-ref profile 'copied-text-bytes)
     (* 160 (hash-ref profile 'agenda-entries))
     (* 192 (hash-ref profile 'feed-entries))
     (* 256 (hash-ref profile 'source-documents))))

(define (estimate-planning-temporary-bytes profile)
  (+ (* 96 (hash-ref profile 'semantic-targets))
     (* 112 (hash-ref profile 'capture-candidates))
     (* 112 (hash-ref profile 'refile-candidates))
     (* 128 (hash-ref profile 'attachment-outcomes))))

(define (validate-planning-resource-profile profile)
  (and (hash? profile)
       (for/and ([(key limit) (in-hash planning-limits)]
                 #:unless (eq? key 'cancellation-entries))
         (define value (hash-ref profile key #f))
         (and (exact-nonnegative-integer? value) (<= value limit)))))
