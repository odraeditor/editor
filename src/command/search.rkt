#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "keymap-model.rkt"
         "native-contracts.rkt"
         (prefix-in bridge: "search-bridge.rkt"))

(define immutable-hash/c (and/c hash? immutable?))

(provide
 (struct-out search-scope)
 (struct-out search-limits)
 (struct-out replacement-limits)
 (struct-out replace-all-limits)
 (struct-out search-policy)
 (struct-out search-range)
 (struct-out search-pattern)
 (struct-out replacement-template)
 (struct-out search-occurrence)
 (struct-out search-capture)
 (struct-out search-progress)
 (struct-out search-usage)
 (struct-out search-state)
 (struct-out search-command)
 (struct-out search-command-result)
 (struct-out search-key-reservation)
 (contract-out
  [search-context? (-> any/c boolean?)]
  [search-failure? (-> any/c boolean?)]
  [search-failure-code (-> bridge:search-failure? exact-nonnegative-integer?)]
  [call-with-search
   (-> exact-positive-integer? exact-positive-integer?
       (-> search-context? any/c) any/c)]
  [inspect-search-scope
   (-> search-context? search-scope?)]
  [inspect-search-policy
   (-> search-context? (or/c search-policy? bridge:search-failure?))]
  [search-policy-inspect (-> search-policy? immutable-hash/c)]
  [search-policy-replace
   (-> search-policy? immutable-hash/c search-policy?)]
  [reload-search-policy! (-> (-> search-policy? search-policy?) void?)]
  [reset-search-policy! (-> void?)]
  [inspect-search-state
   (->* (search-context?)
        (#:occurrences exact-positive-integer?
         #:captures exact-positive-integer?
         #:text-bytes exact-nonnegative-integer?)
        (or/c search-state? bridge:search-failure?))]
  [make-search-range
   (-> exact-positive-integer? exact-nonnegative-integer?
       exact-nonnegative-integer? exact-nonnegative-integer?
       search-range?)]
  [make-search-pattern
   (-> (or/c 'literal 'regular-expression) bytes? search-pattern?)]
  [make-replacement-template
   (-> bytes? replacement-template?)]
  [make-search-command
   (->* (symbol? search-pattern?)
        (#:replacement replacement-template?
         #:direction (or/c 'forward 'backward)
         #:incremental-turn (or/c 'none 'query-update 'repeat)
         #:query-action
         (or/c 'none 'start 'continue 'recompute 'replace 'skip
               'replace-remaining 'replace-and-exit 'quit 'cancel)
         #:query-id exact-nonnegative-integer?
         #:search-generation exact-nonnegative-integer?
         #:semantic-group exact-nonnegative-integer?
         #:scope search-range?
         #:policy (or/c #f search-policy?)
         #:cancelled? boolean?)
        search-command?)]
  [invoke-search-command!
   (-> search-context? search-command?
       (or/c search-command-result? bridge:search-failure?))]
  [search-factory-bindings (-> (listof odra-binding?))]
  [search-reserved-bindings (-> (listof search-key-reservation?))]
  [native-search-turn
   (-> exact-positive-integer? exact-positive-integer? list?)]))

(define (contract item) (native-contract-value 'search item))
(define scope-record-bytes (contract 'scope-record-bytes))
(define policy-record-bytes (contract 'policy-record-bytes))
(define session-header-bytes (contract 'session-header-bytes))
(define occurrence-record-bytes (contract 'occurrence-record-bytes))
(define capture-record-bytes (contract 'capture-record-bytes))
(define command-result-record-bytes (contract 'command-result-record-bytes))
(define maximum-occurrences (contract 'maximum-occurrences))
(define maximum-captures (contract 'maximum-captures))
(define maximum-session-text-bytes (contract 'maximum-session-text-bytes))
(define maximum-pattern-bytes (contract 'maximum-pattern-bytes))
(define maximum-replacement-bytes (contract 'maximum-replacement-bytes))

(define unicode-scalar-key 1)
(define control-modifier #x01)
(define meta-modifier #x02)
(define search-binding-provenance (odra-provenance "odra" "search" ""))
(define configured-search-policy (lambda (current) current))

(struct search-scope
  (editor-session-id access view-registry-id view-id view-generation
                     view-state-generation buffer-id revision
                     command-registry-generation session-kind
                     interaction-generation policy-generation)
  #:transparent)
(struct search-limits
  (pattern-bytes scan-window-bytes cancellation-bytes retained-occurrences
                 temporary-bytes capture-groups match-span-bytes)
  #:transparent)
(struct replacement-limits
  (template-bytes expanded-bytes temporary-bytes)
  #:transparent)
(struct replace-all-limits
  (matches text-bytes temporary-bytes analysis-bytes)
  #:transparent)
(struct search-policy
  (scope case-mode boundary-mode whitespace-mode wrap? search-limits
         case-preservation replacement-limits replace-all-limits)
  #:transparent)
(struct search-range (buffer-id revision start end) #:transparent)
(struct search-pattern (kind bytes) #:transparent)
(struct replacement-template (bytes) #:transparent)
(struct search-occurrence
  (buffer-id revision start end first-capture capture-count)
  #:transparent)
(struct search-capture (group start end) #:transparent)
(struct search-progress (next-offset wrapped? complete?) #:transparent)
(struct search-usage
  (logical-bytes read-bytes scan-turns cancellation-checks
                 retained-occurrences retained-captures temporary-peak-bytes)
  #:transparent)
(struct search-state
  (scope present? kind direction pattern-kind range search-status query-status
         last-response semantic-group pattern last-successful-pattern replacement
         case-mode boundary-mode whitespace-mode wrap? search-limits
         case-preservation replacement-limits
         effective-case source-revision observed-revision source-text-bytes
         observed-text-bytes replacements skips recomputations current-index
         current progress usage occurrences captures)
  #:transparent)
(struct search-command
  (name pattern replacement direction incremental-turn query-action query-id
        search-generation semantic-group scope policy cancelled?)
  #:transparent)
(struct search-command-result
  (scope completion changed? query-status replacements skips finished?
         replacement-usage replace-all-usage continuation-code
         continuation-search-code)
  #:transparent)
(struct search-key-reservation (strokes capability) #:transparent)

;; search-context? recognizes the opaque dynamically scoped bridge context.
(define search-context? bridge:search-control-session?)
(define search-failure? bridge:search-failure?)
(define search-failure-code bridge:search-failure-code)

;; call-with-search grants copied search operations only for one dynamic extent.
(define (call-with-search generation token command)
  (bridge:call-with-search-control generation token command))

;; inspect-search-scope returns the exact immutable native identity snapshot.
(define (inspect-search-scope context)
  (decode-scope (bridge:search-control-scope context) 0))

;; inspect-search-policy returns the resolved native behavior and resource policy.
(define (inspect-search-policy context)
  (define record (bridge:search-control-policy context))
  (if (bridge:search-failure? record) record (decode-policy record)))

;; search-policy-inspect returns every configurable policy field by stable name.
(define (search-policy-inspect policy)
  (define search-limit (search-policy-search-limits policy))
  (define replacement-limit (search-policy-replacement-limits policy))
  (define replace-all-limit (search-policy-replace-all-limits policy))
  (hasheq
   'case-mode (search-policy-case-mode policy)
   'boundary-mode (search-policy-boundary-mode policy)
   'whitespace-mode (search-policy-whitespace-mode policy)
   'wrap? (search-policy-wrap? policy)
   'pattern-bytes (search-limits-pattern-bytes search-limit)
   'scan-window-bytes (search-limits-scan-window-bytes search-limit)
   'cancellation-bytes (search-limits-cancellation-bytes search-limit)
   'retained-occurrences (search-limits-retained-occurrences search-limit)
   'search-temporary-bytes (search-limits-temporary-bytes search-limit)
   'capture-groups (search-limits-capture-groups search-limit)
   'match-span-bytes (search-limits-match-span-bytes search-limit)
   'case-preservation (search-policy-case-preservation policy)
   'template-bytes (replacement-limits-template-bytes replacement-limit)
   'expanded-bytes (replacement-limits-expanded-bytes replacement-limit)
   'replacement-temporary-bytes
   (replacement-limits-temporary-bytes replacement-limit)
   'replace-all-matches (replace-all-limits-matches replace-all-limit)
   'replace-all-text-bytes (replace-all-limits-text-bytes replace-all-limit)
   'replace-all-temporary-bytes
   (replace-all-limits-temporary-bytes replace-all-limit)
   'replace-all-analysis-bytes
   (replace-all-limits-analysis-bytes replace-all-limit)))

;; search-policy-replace creates one copied policy with named field replacements.
(define (search-policy-replace policy replacements)
  (define current (search-policy-inspect policy))
  (for ([field (in-hash-keys replacements)])
    (unless (hash-has-key? current field)
      (raise-arguments-error 'search-policy-replace
                             "unknown search policy field"
                             "field" field)))
  (define fields
    (for/fold ([result current]) ([(field value) (in-hash replacements)])
      (hash-set result field value)))
  (unless (memq (hash-ref fields 'case-mode) '(smart sensitive insensitive))
    (raise-argument-error 'search-policy-replace
                          "a supported case mode"
                          (hash-ref fields 'case-mode)))
  (unless (memq (hash-ref fields 'boundary-mode) '(unrestricted word symbol))
    (raise-argument-error 'search-policy-replace
                          "a supported boundary mode"
                          (hash-ref fields 'boundary-mode)))
  (unless (memq (hash-ref fields 'whitespace-mode) '(exact flexible))
    (raise-argument-error 'search-policy-replace
                          "a supported whitespace mode"
                          (hash-ref fields 'whitespace-mode)))
  (unless (boolean? (hash-ref fields 'wrap?))
    (raise-argument-error 'search-policy-replace
                          "a boolean wrap policy"
                          (hash-ref fields 'wrap?)))
  (unless (memq (hash-ref fields 'case-preservation) '(none smart))
    (raise-argument-error 'search-policy-replace
                          "a supported case-preservation mode"
                          (hash-ref fields 'case-preservation)))
  (for ([field (in-list numeric-search-policy-fields)])
    (unless (exact-nonnegative-integer? (hash-ref fields field))
      (raise-argument-error 'search-policy-replace
                            "a nonnegative exact integer policy field"
                            (hash-ref fields field))))
  (search-policy
   (search-policy-scope policy)
   (hash-ref fields 'case-mode)
   (hash-ref fields 'boundary-mode)
   (hash-ref fields 'whitespace-mode)
   (hash-ref fields 'wrap?)
   (search-limits
    (hash-ref fields 'pattern-bytes)
    (hash-ref fields 'scan-window-bytes)
    (hash-ref fields 'cancellation-bytes)
    (hash-ref fields 'retained-occurrences)
    (hash-ref fields 'search-temporary-bytes)
    (hash-ref fields 'capture-groups)
    (hash-ref fields 'match-span-bytes))
   (hash-ref fields 'case-preservation)
   (replacement-limits
    (hash-ref fields 'template-bytes)
    (hash-ref fields 'expanded-bytes)
    (hash-ref fields 'replacement-temporary-bytes))
   (replace-all-limits
    (hash-ref fields 'replace-all-matches)
    (hash-ref fields 'replace-all-text-bytes)
    (hash-ref fields 'replace-all-temporary-bytes)
    (hash-ref fields 'replace-all-analysis-bytes))))

;; reload-search-policy! replaces the live policy transformation for later turns.
(define (reload-search-policy! configure)
  (set! configured-search-policy configure))

;; reset-search-policy! restores the factory identity transformation.
(define (reset-search-policy!)
  (set! configured-search-policy (lambda (current) current)))

(define numeric-search-policy-fields
  '(pattern-bytes scan-window-bytes cancellation-bytes retained-occurrences
    search-temporary-bytes capture-groups match-span-bytes template-bytes
    expanded-bytes replacement-temporary-bytes replace-all-matches
    replace-all-text-bytes replace-all-temporary-bytes
    replace-all-analysis-bytes))

;; inspect-search-state returns copied bounded interaction state and occurrences.
(define (inspect-search-state context
                              #:occurrences [occurrences maximum-occurrences]
                              #:captures [captures maximum-captures]
                              #:text-bytes [text-bytes maximum-session-text-bytes])
  (define record
    (bridge:search-control-session-copy
     context #:occurrences occurrences #:captures captures #:text-bytes text-bytes))
  (if (bridge:search-failure? record) record (decode-state record)))

;; make-search-range creates one immutable half-open revisioned byte range.
(define (make-search-range buffer-id revision start end)
  (when (> start end)
    (raise-arguments-error 'make-search-range
                           "start must not exceed end"
                           "start" start "end" end))
  (search-range buffer-id revision start end))

;; make-search-pattern copies one literal or regular-expression UTF-8 value.
(define (make-search-pattern kind bytes)
  (validate-utf8 'make-search-pattern bytes)
  (when (> (bytes-length bytes) maximum-pattern-bytes)
    (raise-arguments-error 'make-search-pattern
                           "pattern exceeds the supported maximum"
                           "limit" maximum-pattern-bytes
                           "actual" (bytes-length bytes)))
  (search-pattern kind (bytes->immutable-bytes bytes)))

;; make-replacement-template copies one UTF-8 replacement-template value.
(define (make-replacement-template bytes)
  (validate-utf8 'make-replacement-template bytes)
  (when (> (bytes-length bytes) maximum-replacement-bytes)
    (raise-arguments-error 'make-replacement-template
                           "replacement exceeds the supported maximum"
                           "limit" maximum-replacement-bytes
                           "actual" (bytes-length bytes)))
  (replacement-template (bytes->immutable-bytes bytes)))

;; make-search-command composes one semantic invocation without native ownership.
(define (make-search-command name pattern
                             #:replacement [replacement (make-replacement-template #"")]
                             #:direction [direction 'forward]
                             #:incremental-turn [incremental-turn 'none]
                             #:query-action [query-action 'none]
                             #:query-id [query-id 0]
                             #:search-generation [search-generation 0]
                             #:semantic-group [semantic-group 0]
                             #:scope [scope (make-search-range 1 0 0 0)]
                             #:policy [policy #f]
                             #:cancelled? [cancelled? #f])
  (validate-command-pattern-kind name (search-pattern-kind pattern))
  (search-command name pattern replacement direction incremental-turn query-action
                  query-id search-generation semantic-group scope policy cancelled?))

;; invoke-search-command! invokes one admitted semantic command and decodes its result.
(define (invoke-search-command! context command)
  (let/ec return
    (define range (search-command-scope command))
    (define native-policy (inspect-search-policy context))
    (when (bridge:search-failure? native-policy) (return native-policy))
    (define policy
      (or (search-command-policy command) (configured-search-policy native-policy)))
    (unless (search-policy? policy)
      (raise-result-error 'invoke-search-command! "a search policy" policy))
    (define record
      (bridge:search-control-invoke!
       context (search-command-name command)
       #:pattern (search-pattern-bytes (search-command-pattern command))
       #:replacement
       (replacement-template-bytes (search-command-replacement command))
       #:direction (enum-value 'direction (search-command-direction command)
                               '(invalid forward backward))
       #:incremental-turn
       (enum-value 'incremental-turn (search-command-incremental-turn command)
                   '(none query-update repeat))
       #:query-action
       (enum-value 'query-action (search-command-query-action command)
                   '(none start continue recompute replace skip replace-remaining
                          replace-and-exit quit cancel))
       #:query-id (search-command-query-id command)
       #:search-generation (search-command-search-generation command)
       #:semantic-group (search-command-semantic-group command)
       #:scope (list (search-range-buffer-id range) (search-range-revision range)
                     (search-range-start range) (search-range-end range))
       #:policy (encode-command-policy policy)
       #:cancelled? (search-command-cancelled? command)))
    (if (bridge:search-failure? record) record (decode-command-result record))))

;; search-factory-bindings returns the complete active factory search bindings.
(define (search-factory-bindings)
  (list
   (binding "isearch-forward" (stroke #\s control-modifier))
   (binding "isearch-backward" (stroke #\r control-modifier))
   (binding "isearch-forward-regexp"
            (stroke #\s (bitwise-ior control-modifier meta-modifier)))
   (binding "isearch-backward-regexp"
            (stroke #\r (bitwise-ior control-modifier meta-modifier)))
   (binding "search-symbol-at-point"
            (stroke #\s meta-modifier)
            (stroke #\.))
   (binding "search-word"
            (stroke #\s meta-modifier)
            (stroke #\w))
   (binding "occur"
            (stroke #\s meta-modifier)
            (stroke #\o))
   (binding "highlight-symbol-at-point"
            (stroke #\s meta-modifier)
            (stroke #\h)
            (stroke #\.))
   (binding "highlight-phrase"
            (stroke #\s meta-modifier)
            (stroke #\h)
            (stroke #\p))
   (binding "highlight-regexp"
            (stroke #\s meta-modifier)
            (stroke #\h)
            (stroke #\r))
   (binding "highlight-lines-matching-regexp"
            (stroke #\s meta-modifier)
            (stroke #\h)
            (stroke #\l))
   (binding "unhighlight-regexp"
            (stroke #\s meta-modifier)
            (stroke #\h)
            (stroke #\u))
   (binding "query-replace" (stroke #\% meta-modifier))
   (binding "query-replace-regexp"
            (stroke #\% (bitwise-ior control-modifier meta-modifier)))))

;; search-reserved-bindings exposes the unassigned related M-s namespace.
(define (search-reserved-bindings)
  '())

;; native-search-turn executes one production search capability turn.
(define (native-search-turn generation token)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #f (string->bytes/utf-8 (exn-message failure))))])
    (define result (call-with-search generation token inspect-search-scope))
    (list #t result #"")))

(define (decode-scope record base)
  (require-record 'inspect-search-scope record (+ base scope-record-bytes))
  (search-scope
   (word record base 0)
   (decode-access (word record base 1))
   (word record base 2) (word record base 3) (word record base 4)
   (word record base 5) (word record base 6) (word record base 7)
   (word record base 8)
   (decode-enum 'session-kind (word record base 9)
                '#(none incremental query-replacement))
   (word record base 10) (word record base 11)))

(define (decode-policy record)
  (require-exact-record 'inspect-search-policy record policy-record-bytes)
  (search-policy
   (decode-scope record 0)
   (decode-enum 'case-mode (word record 0 12)
                '#(invalid smart sensitive insensitive))
   (decode-enum 'boundary-mode (word record 0 13)
                '#(invalid unrestricted word symbol))
   (decode-enum 'whitespace-mode (word record 0 14)
                '#(invalid exact flexible))
   (decode-boolean 'wrap (word record 0 15))
   (decode-search-limits record 16)
   (decode-enum 'case-preservation (word record 0 23)
                '#(invalid none smart))
   (decode-replacement-limits record 24)
   (replace-all-limits (word record 0 27) (word record 0 28)
                       (word record 0 29) (word record 0 30))))

(define (encode-command-policy policy)
  (define record (make-bytes 152))
  (define search-limit (search-policy-search-limits policy))
  (define replacement-limit (search-policy-replacement-limits policy))
  (define replace-all-limit (search-policy-replace-all-limits policy))
  (define values
    (list
     (enum-value 'case-mode (search-policy-case-mode policy)
                 '(invalid smart sensitive insensitive))
     (enum-value 'boundary-mode (search-policy-boundary-mode policy)
                 '(invalid unrestricted word symbol))
     (enum-value 'whitespace-mode (search-policy-whitespace-mode policy)
                 '(invalid exact flexible))
     (if (search-policy-wrap? policy) 1 0)
     (search-limits-pattern-bytes search-limit)
     (search-limits-scan-window-bytes search-limit)
     (search-limits-cancellation-bytes search-limit)
     (search-limits-retained-occurrences search-limit)
     (search-limits-temporary-bytes search-limit)
     (search-limits-capture-groups search-limit)
     (search-limits-match-span-bytes search-limit)
     (enum-value 'case-preservation (search-policy-case-preservation policy)
                 '(invalid none smart))
     (replacement-limits-template-bytes replacement-limit)
     (replacement-limits-expanded-bytes replacement-limit)
     (replacement-limits-temporary-bytes replacement-limit)
     (replace-all-limits-matches replace-all-limit)
     (replace-all-limits-text-bytes replace-all-limit)
     (replace-all-limits-temporary-bytes replace-all-limit)
     (replace-all-limits-analysis-bytes replace-all-limit)))
  (for ([value (in-list values)] [offset (in-range 0 152 8)])
    (write-u64! record offset value))
  (bytes->immutable-bytes record))

(define (decode-state record)
  (require-record 'inspect-search-state record session-header-bytes)
  (define occurrence-count (word record 0 68))
  (define capture-count (word record 0 69))
  (define text-count (word record 0 70))
  (when (or (> occurrence-count maximum-occurrences)
            (> capture-count maximum-captures)
            (> text-count maximum-session-text-bytes))
    (raise-result-error 'inspect-search-state "a bounded search record" record))
  (define occurrence-base session-header-bytes)
  (define capture-base (+ occurrence-base (* occurrence-count occurrence-record-bytes)))
  (define text-base (+ capture-base (* capture-count capture-record-bytes)))
  (unless (= (bytes-length record) (+ text-base text-count))
    (raise-result-error 'inspect-search-state "a complete search record" record))
  (define pattern-count (word record 0 24))
  (define successful-count (word record 0 25))
  (define replacement-count (word record 0 26))
  (unless (= text-count (+ pattern-count successful-count replacement-count))
    (raise-result-error 'inspect-search-state "consistent copied text lengths" record))
  (define pattern-end (+ text-base pattern-count))
  (define successful-end (+ pattern-end successful-count))
  (define replacement-end (+ successful-end replacement-count))
  (define present? (decode-boolean 'present (word record 0 12)))
  (define has-current? (decode-boolean 'has-current (word record 0 50)))
  (search-state
   (decode-scope record 0) present?
   (decode-enum 'session-kind (word record 0 13)
                '#(none incremental query-replacement))
   (decode-enum 'direction (word record 0 14) '#(invalid forward backward))
   (decode-enum 'pattern-kind (word record 0 15)
                '#(invalid literal regular-expression))
   (search-range (word record 0 16) (word record 0 17)
                 (word record 0 18) (word record 0 19))
   (decode-enum 'search-status (word record 0 20)
                '#(inactive active failing pending wrapped))
   (decode-enum 'query-status (word record 0 21)
                '#(inactive awaiting-response pending wrapped exhausted
                            recomputation-required))
   (decode-enum 'last-response (word record 0 22)
                '#(invalid started continued skipped replaced recomputed))
   (word record 0 23)
   (immutable-subbytes record text-base pattern-end)
   (immutable-subbytes record pattern-end successful-end)
   (immutable-subbytes record successful-end replacement-end)
   (decode-enum 'case-mode (word record 0 27)
                '#(invalid smart sensitive insensitive))
   (decode-enum 'boundary-mode (word record 0 28)
                '#(invalid unrestricted word symbol))
   (decode-enum 'whitespace-mode (word record 0 29)
                '#(invalid exact flexible))
   (decode-boolean 'wrap (word record 0 30))
   (decode-search-limits record 31)
   (decode-enum 'case-preservation (word record 0 38)
                '#(invalid none smart))
   (decode-replacement-limits record 39)
   (decode-enum 'effective-case (word record 0 42)
                '#(invalid sensitive insensitive))
   (word record 0 43) (word record 0 44) (word record 0 45)
   (word record 0 46) (word record 0 47) (word record 0 48)
   (word record 0 49)
   (and has-current? (word record 0 51))
   (and has-current? (decode-occurrence record (* 8 52)))
   (search-progress (word record 0 58)
                    (decode-boolean 'progress-wrapped (word record 0 59))
                    (decode-boolean 'progress-complete (word record 0 60)))
   (search-usage (word record 0 61) (word record 0 62)
                 (word record 0 63) (word record 0 64)
                 (word record 0 65) (word record 0 66)
                 (word record 0 67))
   (for/list ([index (in-range occurrence-count)])
     (decode-occurrence record (+ occurrence-base (* index occurrence-record-bytes))))
   (for/list ([index (in-range capture-count)])
     (define base (+ capture-base (* index capture-record-bytes)))
     (search-capture (read-u64 record base)
                     (read-u64 record (+ base 8))
                     (read-u64 record (+ base 16))))))

(define (decode-command-result record)
  (require-exact-record 'invoke-search-command! record command-result-record-bytes)
  (search-command-result
   (decode-scope record 0)
   (decode-enum 'completion (word record 0 12)
                '#(invalid no-op view-changed buffer-committed text-retained
                           pending-input-cancelled exit-requested document-saved
                           document-target-required
                           incremental-search-forward-requested
                           incremental-search-backward-requested
                           incremental-regexp-search-forward-requested
                           incremental-regexp-search-backward-requested
                           query-replace-requested query-replace-regexp-requested))
   (decode-boolean 'changed (word record 0 13))
   (decode-enum 'query-status (word record 0 14)
                '#(inactive awaiting-response pending wrapped exhausted
                            recomputation-required))
   (word record 0 15) (word record 0 16)
   (decode-boolean 'finished (word record 0 17))
   (vector (word record 0 18) (word record 0 19) (word record 0 20))
   (for/vector ([index (in-range 21 30)]) (word record 0 index))
   (word record 0 30) (word record 0 31)))

(define (decode-search-limits record index)
  (search-limits
   (word record 0 index) (word record 0 (+ index 1))
   (word record 0 (+ index 2)) (word record 0 (+ index 3))
   (word record 0 (+ index 4)) (word record 0 (+ index 5))
   (word record 0 (+ index 6))))

(define (decode-replacement-limits record index)
  (replacement-limits
   (word record 0 index) (word record 0 (+ index 1))
   (word record 0 (+ index 2))))

(define (decode-occurrence record base)
  (search-occurrence
   (read-u64 record base) (read-u64 record (+ base 8))
   (read-u64 record (+ base 16)) (read-u64 record (+ base 24))
   (read-u64 record (+ base 32)) (read-u64 record (+ base 40))))

(define (decode-access value)
  (when (> value 7)
    (raise-result-error 'inspect-search-scope "a known access mask" value))
  (for/list ([entry (in-list '((1 policy-inspection)
                               (2 session-inspection)
                               (4 semantic-invocation)))]
             #:when (not (zero? (bitwise-and value (car entry)))))
    (cadr entry)))

(define (decode-enum name value values)
  (if (< value (vector-length values))
      (vector-ref values value)
      (raise-result-error name "a known native enumeration value" value)))

(define (decode-boolean name value)
  (case value
    [(0) #f]
    [(1) #t]
    [else (raise-result-error name "a native boolean" value)]))

(define (enum-value name value values)
  (define index (index-of values value))
  (or index (raise-argument-error name "a supported symbolic value" value)))

(define (validate-command-pattern-kind name kind)
  (define regexp-command?
    (memq name '(isearch-forward-regexp isearch-backward-regexp
                 query-replace-regexp replace-regexp)))
  (define known-command?
    (memq name '(isearch-forward isearch-backward
                 isearch-forward-regexp isearch-backward-regexp
                 query-replace query-replace-regexp
                 replace-string replace-regexp)))
  (unless known-command?
    (raise-argument-error 'make-search-command "an admitted search command" name))
  (unless (eq? kind (if regexp-command? 'regular-expression 'literal))
    (raise-arguments-error 'make-search-command
                           "pattern kind does not match the semantic command"
                           "command" name "pattern-kind" kind)))

(define (validate-utf8 name value)
  (with-handlers ([exn:fail:contract?
                   (lambda (_failure)
                     (raise-argument-error name "UTF-8 bytes" value))])
    (bytes->string/utf-8 value)
    (void)))

(define (stroke scalar [modifiers 0])
  (odra-key-stroke unicode-scalar-key (char->integer scalar) modifiers))

(define (binding command-name . strokes)
  (keymap-bind (apply key-sequence strokes) command-name search-binding-provenance))

(define (word record base index)
  (read-u64 record (+ base (* index 8))))

(define (read-u64 record offset)
  (integer-bytes->integer record #f #f offset (+ offset 8)))

(define (write-u64! record offset value)
  (integer->integer-bytes value 8 #f #f record offset)
  (void))

(define (immutable-subbytes record start end)
  (bytes->immutable-bytes (subbytes record start end)))

(define (require-record name record minimum)
  (unless (>= (bytes-length record) minimum)
    (raise-result-error name "a complete native record" record)))

(define (require-exact-record name record size)
  (unless (= (bytes-length record) size)
    (raise-result-error name "an exact native record" record)))

(module+ test
  (require rackunit)

  (define literal (make-search-pattern 'literal #"odra"))
  (define regexp (make-search-pattern 'regular-expression #"o.*a"))
  (check-true (immutable? (search-pattern-bytes literal)))
  (check-equal? (search-pattern-kind regexp) 'regular-expression)
  (check-exn exn:fail:contract? (lambda () (make-search-pattern 'literal #"\377")))
  (check-exn exn:fail:contract?
             (lambda ()
               (make-search-pattern 'literal
                                    (make-bytes (add1 maximum-pattern-bytes)))))
  (check-exn exn:fail:contract?
             (lambda ()
               (make-replacement-template
                (make-bytes (add1 maximum-replacement-bytes)))))
  (check-equal? (search-range-end (make-search-range 1 2 3 9)) 9)
  (check-exn exn:fail:contract? (lambda () (make-search-range 1 0 9 3)))
  (check-equal? (search-command-direction
                 (make-search-command 'isearch-forward literal))
                'forward)
  (check-exn exn:fail:contract?
             (lambda () (make-search-command 'isearch-forward regexp)))
  (define factory-search-bindings (search-factory-bindings))
  (check-equal? (length factory-search-bindings) 14)
  (check-true (andmap odra-binding? factory-search-bindings))
  (check-true
   (andmap (lambda (candidate)
             (string=? (odra-provenance-source
                        (odra-binding-provenance candidate))
                       "search"))
           factory-search-bindings))
  (check-equal? (search-reserved-bindings) '())
  (check-equal?
   (map odra-binding-command (take (drop factory-search-bindings 5) 7))
   '("search-word" "occur" "highlight-symbol-at-point" "highlight-phrase"
     "highlight-regexp" "highlight-lines-matching-regexp"
     "unhighlight-regexp"))

  (define sample-policy
    (search-policy
     (search-scope 1 '(policy-inspection semantic-invocation)
                   1 1 1 1 1 0 1 'none 0 1)
     'smart 'unrestricted 'exact #t
     (search-limits 4096 65536 262144 256 (* 16 1024 1024) 10 65536)
     'smart
     (replacement-limits 4096 (* 16 1024 1024) (* 16 1024 1024))
     (replace-all-limits 100000 (* 256 1024 1024)
                         (* 512 1024 1024) (* 2 1024 1024 1024))))
  (define configured-policy
    (search-policy-replace sample-policy (hasheq 'case-mode 'sensitive 'wrap? #f)))
  (check-equal? (search-policy-case-mode configured-policy) 'sensitive)
  (check-false (search-policy-wrap? configured-policy))
  (check-equal? (hash-ref (search-policy-inspect configured-policy) 'pattern-bytes)
                4096)
  (check-exn exn:fail:contract?
             (lambda () (search-policy-replace sample-policy (hasheq 'unknown 1))))
  (reload-search-policy!
   (lambda (current)
     (search-policy-replace current (hasheq 'case-mode 'insensitive))))
  (check-equal? (search-policy-case-mode (configured-search-policy sample-policy))
                'insensitive)
  (reset-search-policy!)
  (check-eq? (configured-search-policy sample-policy) sample-policy)
  (check-equal? (bytes-length (encode-command-policy sample-policy)) 152)

  (define copied-record (make-bytes session-header-bytes))
  (define copied-state (decode-state copied-record))
  (bytes-set! copied-record 0 255)
  (check-equal? (search-scope-editor-session-id
                 (search-state-scope copied-state))
                0)
  (check-true (immutable? (search-state-pattern copied-state)))
  (check-exn exn:fail:contract?
             (lambda () (decode-state (make-bytes (sub1 session-header-bytes)))))
  (define malformed-boolean (make-bytes session-header-bytes))
  (void (integer->integer-bytes 2 8 #f #f malformed-boolean 96))
  (check-exn exn:fail:contract? (lambda () (decode-state malformed-boolean)))
  (define over-quota (make-bytes session-header-bytes))
  (void
   (integer->integer-bytes
    (add1 maximum-occurrences) 8 #f #f over-quota (* 68 8)))
  (check-exn exn:fail:contract? (lambda () (decode-state over-quota))))
