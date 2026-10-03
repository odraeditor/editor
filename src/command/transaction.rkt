#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/match
         racket/port
         "native-contracts.rkt"
         (prefix-in cap: "../hosting/scoped-capability.rkt"))

(define host-dispatch/c
  (-> exact-positive-integer? symbol? hash? list?))

(provide
 (contract-out
  [transaction-session? (-> any/c boolean?)]
  [transaction-limits? (-> any/c boolean?)]
  [transaction-edit? (-> any/c boolean?)]
  [transaction-edit-start (-> transaction-edit? exact-nonnegative-integer?)]
  [transaction-edit-end (-> transaction-edit? exact-nonnegative-integer?)]
  [transaction-edit-replacement (-> transaction-edit? bytes?)]
  [transaction-failure? (-> any/c boolean?)]
  [transaction-failure-code (-> transaction-failure? symbol?)]
  [transaction-failure-detail (-> transaction-failure? hash?)]
  [make-transaction-limits
   (->* ()
        (#:inspection-bytes exact-positive-integer?
         #:batch-splices exact-positive-integer?
         #:text-bytes exact-positive-integer?
         #:nested-depth exact-positive-integer?
         #:descriptor-bytes exact-positive-integer?)
        transaction-limits?)]
  [make-transaction-edit
   (-> exact-nonnegative-integer? exact-nonnegative-integer? bytes?
       transaction-edit?)]
  [call-with-transaction
   (->* (exact-positive-integer? host-dispatch/c
                                 (-> transaction-session? any/c))
        (#:limits transaction-limits?)
        any/c)]
  [transaction-inspect
   (-> transaction-session? exact-nonnegative-integer?
       exact-nonnegative-integer? (or/c bytes? transaction-failure?))]
  [transaction-apply-batch!
   (-> transaction-session? list? (or/c void? transaction-failure?))]
  [transaction-splice!
   (-> transaction-session? exact-nonnegative-integer?
       exact-nonnegative-integer? bytes? (or/c void? transaction-failure?))]
  [transaction-invoke-nested
   (-> transaction-session? symbol? string? (-> transaction-session? any/c)
       any/c)]
  [transaction-reject
   (->* (symbol?) ((and/c hash? immutable?)) transaction-failure?)]
  [transaction-request-abort!
   (-> transaction-session? (or/c void? transaction-failure?))]
  [transaction-jan-analyze
   (-> transaction-session? bytes? (or/c jan-analysis? transaction-failure?))]
  [jan-analysis? (-> any/c boolean?)]
  [jan-analysis-source-bytes (-> jan-analysis? exact-nonnegative-integer?)]
  [jan-analysis-generation (-> jan-analysis? exact-positive-integer?)]
  [jan-analysis-nodes (-> jan-analysis? list?)]
  [jan-analysis-attributes (-> jan-analysis? list?)]
  [jan-analysis-recoveries (-> jan-analysis? list?)]
  [jan-analysis-indexes (-> jan-analysis? list?)]
  [jan-node? (-> any/c boolean?)]
  [jan-node-id (-> jan-node? exact-positive-integer?)]
  [jan-node-parent-id (-> jan-node? exact-nonnegative-integer?)]
  [jan-node-layer (-> jan-node? exact-positive-integer?)]
  [jan-node-kind (-> jan-node? exact-positive-integer?)]
  [jan-node-start (-> jan-node? exact-nonnegative-integer?)]
  [jan-node-end (-> jan-node? exact-nonnegative-integer?)]
  [jan-node-structural-depth (-> jan-node? exact-nonnegative-integer?)]
  [jan-node-inline-depth (-> jan-node? exact-nonnegative-integer?)]
  [jan-node-attribute-count (-> jan-node? exact-nonnegative-integer?)]
  [jan-node-kind-text (-> jan-node? string?)]
  [jan-attribute? (-> any/c boolean?)]
  [jan-attribute-node-id (-> jan-attribute? exact-positive-integer?)]
  [jan-attribute-kind (-> jan-attribute? exact-positive-integer?)]
  [jan-attribute-start (-> jan-attribute? exact-nonnegative-integer?)]
  [jan-attribute-end (-> jan-attribute? exact-nonnegative-integer?)]
  [jan-attribute-name (-> jan-attribute? string?)]
  [jan-attribute-value (-> jan-attribute? string?)]
  [jan-recovery? (-> any/c boolean?)]
  [jan-recovery-node-id (-> jan-recovery? exact-positive-integer?)]
  [jan-recovery-code (-> jan-recovery? exact-positive-integer?)]
  [jan-recovery-start (-> jan-recovery? exact-nonnegative-integer?)]
  [jan-recovery-end (-> jan-recovery? exact-nonnegative-integer?)]
  [jan-index? (-> any/c boolean?)]
  [jan-index-id (-> jan-index? exact-positive-integer?)]
  [jan-index-kind (-> jan-index? exact-positive-integer?)]
  [jan-index-node-id (-> jan-index? exact-positive-integer?)]
  [jan-index-start (-> jan-index? exact-nonnegative-integer?)]
  [jan-index-end (-> jan-index? exact-nonnegative-integer?)]
  [call-with-native-transaction
   (->* (exact-positive-integer? exact-positive-integer?
                                 (-> transaction-session? any/c))
        (#:limits transaction-limits?)
        any/c)]
  [native-transaction-turn
   (-> exact-positive-integer? exact-positive-integer? list?)]))

(define (contract item) (native-contract-value 'transaction item))
(define edit-record-bytes (contract 'edit-record-bytes))
(define maximum-inspection-bytes (contract 'maximum-inspection-bytes))
(define maximum-batch-splices (contract 'maximum-batch-splices))
(define maximum-text-bytes (contract 'maximum-text-bytes))
(define maximum-nested-depth (contract 'maximum-nested-depth))
(define maximum-descriptor-bytes (contract 'maximum-descriptor-bytes))

(struct transaction-limits
  (inspection-bytes batch-splices text-bytes nested-depth descriptor-bytes))
(struct transaction-edit (start end replacement))
(struct transaction-failure (code detail))
(struct transaction-session
  (token dispatch limits [active? #:mutable] [aborted? #:mutable]
         [nested-depth #:mutable]))
(struct jan-analysis (source-bytes generation nodes attributes recoveries indexes)
  #:transparent)
(struct jan-node
  (id parent-id layer kind start end structural-depth inline-depth
      attribute-count kind-text)
  #:transparent)
(struct jan-attribute (node-id kind start end name value) #:transparent)
(struct jan-recovery (node-id code start end) #:transparent)
(struct jan-index (id kind node-id start end) #:transparent)

(define jan-wire-magic #x4f4452414a414e31)
(define jan-wire-version 1)
(define jan-wire-header-bytes 64)

(define expected-failure-codes
  '(cancelled invalid-identity invalid-limits invalid-state invalid-origin
    origin-limit command-limit nesting-limit savepoint-limit
    invalid-nested-command participant-limit view-failure wrong-buffer
    stale-revision mismatched-revision reversed-range out-of-range
    mid-encoding-offset malformed-utf8 overlapping-batch ambiguous-order
    splice-limit text-limit temporary-memory-limit metadata-memory-limit
    persistent-memory-limit work-limit changeset-mismatch reentrant-mutation
    nested-failure))

;; make-transaction-limits creates one facade-side admission profile.
(define (make-transaction-limits
         #:inspection-bytes [inspection-bytes maximum-inspection-bytes]
         #:batch-splices [batch-splices maximum-batch-splices]
         #:text-bytes [text-bytes maximum-text-bytes]
         #:nested-depth [nested-depth maximum-nested-depth]
         #:descriptor-bytes [descriptor-bytes maximum-descriptor-bytes])
  (check-upper-bound 'make-transaction-limits
                     'inspection-bytes inspection-bytes maximum-inspection-bytes)
  (check-upper-bound 'make-transaction-limits
                     'batch-splices batch-splices maximum-batch-splices)
  (check-upper-bound 'make-transaction-limits
                     'text-bytes text-bytes maximum-text-bytes)
  (check-upper-bound 'make-transaction-limits
                     'nested-depth nested-depth maximum-nested-depth)
  (check-upper-bound 'make-transaction-limits
                     'descriptor-bytes descriptor-bytes maximum-descriptor-bytes)
  (transaction-limits inspection-bytes batch-splices text-bytes
                      nested-depth descriptor-bytes))

;; make-transaction-edit copies replacement bytes into an immutable request value.
(define (make-transaction-edit start end replacement)
  (when (> start end)
    (raise-arguments-error 'make-transaction-edit
                           "start must not exceed end"
                           "start" start
                           "end" end))
  (transaction-edit start end (bytes->immutable-bytes replacement)))

;; call-with-transaction bounds one opaque token to the dynamic command extent.
(define (call-with-transaction token dispatch command
                               #:limits [limits (make-transaction-limits)])
  (define session (transaction-session token dispatch limits #t #f 0))
  (dynamic-wind
   void
   (lambda () (command session))
   (lambda () (set-transaction-session-active?! session #f))))

;; transaction-inspect reads one bounded range from the current private revision.
(define (transaction-inspect session start end)
  (define readiness (session-readiness-failure session))
  (cond
    [readiness readiness]
    [(> start end)
     (transaction-reject 'reversed-range (hasheq 'start start 'end end))]
    [(> (- end start)
        (transaction-limits-inspection-bytes (transaction-session-limits session)))
     (transaction-reject
      'work-limit
      (hasheq 'limit
              (transaction-limits-inspection-bytes
               (transaction-session-limits session))
              'actual (- end start)))]
    [else
     (define result
       (host-call session 'inspect (hasheq 'start start 'end end)))
     (cond
       [(transaction-failure? result) result]
       [(and (bytes? result) (= (bytes-length result) (- end start)))
        (bytes->immutable-bytes result)]
       [else (raise-result-error 'transaction-inspect
                                 "bytes matching the requested range"
                                 result)])]))

;; transaction-apply-batch! submits one bounded copied base-relative edit list.
(define (transaction-apply-batch! session edits)
  (define readiness (session-readiness-failure session))
  (if readiness
      readiness
      (let ([admitted (admit-batch session edits)])
        (if (transaction-failure? admitted)
            admitted
            (host-void-result session 'apply-batch (hasheq 'edits admitted))))))

;; transaction-splice! applies one sequential edit against the current private revision.
(define (transaction-splice! session start end replacement)
  (define readiness (session-readiness-failure session))
  (cond
    [readiness readiness]
    [else
     (define edit (make-transaction-edit start end replacement))
     (define limit (transaction-limits-text-bytes (transaction-session-limits session)))
     (define actual (+ (- end start) (bytes-length replacement)))
     (if (> actual limit)
         (transaction-reject 'text-limit (hasheq 'limit limit 'actual actual))
         (host-void-result session 'splice (hasheq 'edit edit)))]))

;; transaction-invoke-nested joins success, restores handled failure, and propagates exceptions.
(define (transaction-invoke-nested session origin command child)
  (define readiness (session-readiness-failure session))
  (cond
    [readiness readiness]
    [(not (memq origin '(built-in racket language-tool external-proposal)))
     (raise-argument-error 'transaction-invoke-nested
                           "an admitted origin symbol"
                           origin)]
    [(> (bytes-length (string->bytes/utf-8 command))
        (transaction-limits-descriptor-bytes (transaction-session-limits session)))
     (transaction-reject
      'work-limit
      (hasheq 'limit
              (transaction-limits-descriptor-bytes
               (transaction-session-limits session))))]
    [(>= (transaction-session-nested-depth session)
         (transaction-limits-nested-depth (transaction-session-limits session)))
     (transaction-reject
      'nesting-limit
      (hasheq 'limit
              (transaction-limits-nested-depth
               (transaction-session-limits session))))]
    [else
     (define begun
       (host-call session 'nested-begin
                  (hasheq 'origin origin 'command command)))
     (if (transaction-failure? begun)
         begun
         (let ([entered? #f]
               [completed? #f])
           (unless (exact-positive-integer? begun)
             (raise-result-error 'transaction-invoke-nested
                                 "a positive nested command token"
                                 begun))
           (dynamic-wind
            (lambda ()
              (when completed?
                (raise-arguments-error
                 'transaction-invoke-nested
                 "a completed nested command continuation cannot be resumed"))
              (set! entered? #t)
              (set-transaction-session-nested-depth!
               session (add1 (transaction-session-nested-depth session))))
            (lambda ()
              (define result (child session))
              (cond
                [(transaction-failure? result)
                 (define restored
                   (host-void-result
                    session 'nested-fail
                    (hasheq 'nested-token begun 'disposition 'handled)))
                 (unless (transaction-failure? restored)
                   (set! completed? #t))
                 (if (transaction-failure? restored) restored result)]
                [else
                 (define joined
                   (host-void-result session 'nested-succeed
                                     (hasheq 'nested-token begun)))
                 (unless (transaction-failure? joined)
                   (set! completed? #t))
                 (if (transaction-failure? joined) joined result)]))
            (lambda ()
              (when entered?
                (set! entered? #f)
                (set-transaction-session-nested-depth!
                 session (sub1 (transaction-session-nested-depth session))))
              (unless completed?
                (with-handlers ([exn? (lambda (_failure) (void))])
                  (host-void-result
                   session 'nested-fail
                   (hasheq 'nested-token begun 'disposition 'unhandled)))
                (set! completed? #t))))))]))

;; transaction-reject creates one explicit expected-failure value for composition.
(define (transaction-reject code [detail (hasheq)])
  (unless (memq code expected-failure-codes)
    (raise-argument-error 'transaction-reject
                          "an admitted transaction failure symbol"
                          code))
  (unless (immutable? detail)
    (raise-argument-error 'transaction-reject "an immutable hash" detail))
  (transaction-failure code detail))

;; transaction-request-abort! asks Odin to abort and makes the local facade terminal.
(define (transaction-request-abort! session)
  (define readiness (session-readiness-failure session))
  (if readiness
      readiness
      (let ([result (host-void-result session 'abort (hasheq))])
        (unless (transaction-failure? result)
          (set-transaction-session-aborted?! session #t))
        result)))

;; transaction-jan-analyze obtains one bounded native Jan semantic snapshot.
(define (transaction-jan-analyze session source)
  (define readiness (session-readiness-failure session))
  (cond
    [readiness readiness]
    [(> (bytes-length source)
        (transaction-limits-inspection-bytes (transaction-session-limits session)))
     (transaction-reject
      'work-limit
      (hasheq 'limit
              (transaction-limits-inspection-bytes
               (transaction-session-limits session))
              'actual (bytes-length source)))]
    [else
     (define result
       (host-call
        session 'jan-analyze
        (hasheq
         'source (bytes->immutable-bytes source)
         'output-capacity
         (transaction-limits-inspection-bytes
          (transaction-session-limits session)))))
     (if (transaction-failure? result) result (decode-jan-analysis result))]))

(define (decode-jan-analysis encoded)
  (unless (and (bytes? encoded) (>= (bytes-length encoded) jan-wire-header-bytes))
    (raise-result-error 'transaction-jan-analyze "a Jan analysis record" encoded))
  (define cursor 0)
  (define (word)
    (when (> (+ cursor 8) (bytes-length encoded))
      (error 'transaction-jan-analyze "truncated Jan analysis record"))
    (define value (integer-bytes->integer encoded #f #f cursor (+ cursor 8)))
    (set! cursor (+ cursor 8))
    value)
  (define (text length)
    (when (> (+ cursor length) (bytes-length encoded))
      (error 'transaction-jan-analyze "truncated Jan analysis text"))
    (define value (bytes->string/utf-8 encoded #f cursor (+ cursor length)))
    (set! cursor (+ cursor length))
    (string->immutable-string value))
  (unless (= (word) jan-wire-magic)
    (error 'transaction-jan-analyze "invalid Jan analysis magic"))
  (unless (= (word) jan-wire-version)
    (error 'transaction-jan-analyze "unsupported Jan analysis version"))
  (define source-bytes (word))
  (define generation (word))
  (define node-count (word))
  (define attribute-count (word))
  (define recovery-count (word))
  (define index-count (word))
  (define nodes
    (for/list ([_ (in-range node-count)])
      (define fields (for/list ([_ (in-range 10)]) (word)))
      (apply jan-node
             (append (take fields 9) (list (text (list-ref fields 9)))))))
  (define attributes
    (for/list ([_ (in-range attribute-count)])
      (define fields (for/list ([_ (in-range 6)]) (word)))
      (jan-attribute
       (list-ref fields 0) (list-ref fields 1)
       (list-ref fields 2) (list-ref fields 3)
       (text (list-ref fields 4)) (text (list-ref fields 5)))))
  (define recoveries
    (for/list ([_ (in-range recovery-count)])
      (apply jan-recovery (for/list ([_ (in-range 4)]) (word)))))
  (define indexes
    (for/list ([_ (in-range index-count)])
      (apply jan-index (for/list ([_ (in-range 5)]) (word)))))
  (unless (= cursor (bytes-length encoded))
    (error 'transaction-jan-analyze "trailing Jan analysis bytes"))
  (jan-analysis source-bytes generation nodes attributes recoveries indexes))

(define (admit-batch session edits)
  (define limits (transaction-session-limits session))
  (let loop ([remaining edits] [count 0] [text-bytes 0] [admitted '()])
    (cond
      [(null? remaining) (reverse admitted)]
      [(not (pair? remaining))
       (raise-argument-error 'transaction-apply-batch! "a proper edit list" edits)]
      [(>= count (transaction-limits-batch-splices limits))
       (transaction-reject 'splice-limit
                           (hasheq 'limit (transaction-limits-batch-splices limits)
                                   'actual (add1 count)))]
      [(not (transaction-edit? (car remaining)))
       (raise-argument-error 'transaction-apply-batch!
                             "a list of transaction edits"
                             edits)]
      [else
       (define edit (car remaining))
       (define next-text-bytes
         (+ text-bytes
            (- (transaction-edit-end edit) (transaction-edit-start edit))
            (bytes-length (transaction-edit-replacement edit))))
       (if (> next-text-bytes (transaction-limits-text-bytes limits))
           (transaction-reject
            'text-limit
            (hasheq 'limit (transaction-limits-text-bytes limits)
                    'actual next-text-bytes))
           (loop (cdr remaining) (add1 count) next-text-bytes
                 (cons edit admitted)))])))

(define (host-void-result session operation payload)
  (define result (host-call session operation payload))
  (cond
    [(transaction-failure? result) result]
    [(eq? result #t) (void)]
    [else (raise-result-error operation "#t" result)]))

(define (host-call session operation payload)
  (match ((transaction-session-dispatch session)
          (transaction-session-token session)
          operation
          payload)
    [(list 'ok value) value]
    [(list 'error code detail)
     (transaction-reject code detail)]
    [other
     (raise-result-error operation
                         "a host response '(ok value) or '(error code detail)"
                         other)]))

(define (session-readiness-failure session)
  (cond
    [(not (transaction-session-active? session))
     (raise-arguments-error 'transaction-session
                            "transaction capability escaped its dynamic extent")]
    [(transaction-session-aborted? session)
     (transaction-reject 'invalid-state (hasheq 'state 'aborted))]
    [else #f]))

(define (check-upper-bound who field value limit)
  (when (> value limit)
    (raise-arguments-error who
                           "limit exceeds the supported facade maximum"
                           "field" field
                           "limit" limit
                           "actual" value)))

  (define operation-inspect (contract 'operation-inspect))
  (define operation-batch (contract 'operation-batch))
  (define operation-splice (contract 'operation-splice))
  (define operation-nested-begin (contract 'operation-nested-begin))
  (define operation-nested-succeed (contract 'operation-nested-succeed))
  (define operation-nested-fail (contract 'operation-nested-fail))
  (define operation-abort (contract 'operation-abort))
  (define operation-jan-analyze (contract 'operation-jan-analyze))

  (define failure-symbols
    '#(invalid-state invalid-identity invalid-limits invalid-origin origin-limit
       command-limit nesting-limit savepoint-limit invalid-nested-command
       participant-limit view-failure wrong-buffer stale-revision
       mismatched-revision reversed-range out-of-range mid-encoding-offset
       malformed-utf8 overlapping-batch ambiguous-order splice-limit text-limit
       temporary-memory-limit metadata-memory-limit persistent-memory-limit
       work-limit cancelled changeset-mismatch reentrant-mutation
       invalid-state invalid-state invalid-state invalid-state invalid-state))

  ;; call-with-native-transaction supplies the private adapter to one facade extent.
  (define (call-with-native-transaction generation token command
                                        #:limits [limits (make-transaction-limits)])
    (cap:call-with-scoped-capability
     'transaction generation token
     (lambda (capability)
       (call-with-transaction
        token
        (lambda (_token operation payload)
          (native-dispatch capability operation payload))
        command
        #:limits limits))))

  ;; native-transaction-turn executes one production transaction composition.
  (define (native-transaction-turn generation token)
    (with-handlers ([exn?
                     (lambda (failure)
                       (list #f #f (string->bytes/utf-8 (exn-message failure))))])
      (define result
        (call-with-native-transaction
         generation token
         (lambda (transaction)
           (define before (transaction-inspect transaction 0 3))
           (transaction-splice! transaction 1 2 #"X")
           (list before (transaction-inspect transaction 0 3)))))
      (list #t result #"")))

  (module+ test-support
    (provide native-dispatch host-call))

  (define (native-dispatch capability operation payload)
    (case operation
      [(inspect)
       (native-invoke capability operation-inspect
                      (hash-ref payload 'start) (hash-ref payload 'end)
                      #"" (- (hash-ref payload 'end) (hash-ref payload 'start))
                      'bytes)]
      [(apply-batch)
       (define-values (input count record-bytes)
         (encode-batch (hash-ref payload 'edits)))
       (native-invoke capability operation-batch count record-bytes input 0 'void)]
      [(splice)
       (define edit (hash-ref payload 'edit))
       (native-invoke capability operation-splice
                      (transaction-edit-start edit) (transaction-edit-end edit)
                      (transaction-edit-replacement edit) 0 'void)]
      [(nested-begin)
       (native-invoke capability operation-nested-begin
                      (origin-code (hash-ref payload 'origin)) 0
                      (string->bytes/utf-8 (hash-ref payload 'command)) 0 'value)]
      [(nested-succeed)
       (native-invoke capability operation-nested-succeed
                      (hash-ref payload 'nested-token) 0 #"" 0 'void)]
      [(nested-fail)
       (native-invoke capability operation-nested-fail
                      (hash-ref payload 'nested-token)
                      (if (eq? (hash-ref payload 'disposition) 'handled) 1 2)
                      #"" 0 'void)]
      [(abort)
       (native-invoke capability operation-abort 0 0 #"" 0 'void)]
      [(jan-analyze)
       (native-invoke capability operation-jan-analyze 0 0
                      (hash-ref payload 'source)
                      (hash-ref payload 'output-capacity)
                      'bytes)]
      [(malformed-batch)
       (native-invoke capability operation-batch 1 edit-record-bytes #"\0" 0 'void)]
      [else (error 'native-dispatch "unsupported transaction operation")]))

  (define (native-invoke capability operation arg0 arg1 input output-capacity result-kind)
    (define result
      (cap:scoped-capability-invoke
       capability operation arg0 arg1 input output-capacity))
    (case (cap:scoped-capability-result-status result)
      [(0)
       (list 'ok
             (case result-kind
               [(bytes) (cap:scoped-capability-result-output result)]
               [(value) (cap:scoped-capability-result-value result)]
               [else #t]))]
      [(1)
       (define code (cap:scoped-capability-result-failure-code result))
       (unless (< code (vector-length failure-symbols))
         (error 'native-dispatch "native transaction failure code is invalid"))
       (list 'error
             (vector-ref failure-symbols code)
             (hasheq 'limit (cap:scoped-capability-result-limit result)
                     'actual (cap:scoped-capability-result-actual result)))]
      [else (error 'native-dispatch "native transaction adapter rejected the call")]))

  (define (encode-batch edits)
    (define records (make-bytes (* edit-record-bytes (length edits))))
    (define replacements (open-output-bytes))
    (for ([edit (in-list edits)] [index (in-naturals)])
      (define replacement (transaction-edit-replacement edit))
      (define replacement-offset (file-position replacements))
      (write-bytes replacement replacements)
      (define base (* index edit-record-bytes))
      (integer->integer-bytes (transaction-edit-start edit) 8 #f #f records base)
      (integer->integer-bytes (transaction-edit-end edit) 8 #f #f records (+ base 8))
      (integer->integer-bytes replacement-offset 8 #f #f records (+ base 16))
      (integer->integer-bytes (bytes-length replacement) 8 #f #f records (+ base 24)))
    (values (bytes-append records (get-output-bytes replacements))
            (length edits)
            (bytes-length records)))

  (define (origin-code origin)
    (case origin
      [(built-in) 1]
      [(racket) 2]
      [(language-tool) 3]
      [(external-proposal) 4]
      [else (error 'native-dispatch "unsupported nested origin")]))
(module+ test
  (require rackunit)

  (define calls '())
  (define private-bytes #"abc")
  (define (jan-test-record)
    (define output (open-output-bytes))
    (define (word value)
      (write-bytes (integer->integer-bytes value 8 #f #f) output))
    (for-each word
              (list jan-wire-magic jan-wire-version 12 7 1 1 1 1
                    1 0 1 3 0 12 1 0 1 7))
    (write-bytes #"heading" output)
    (for-each word '(1 1 2 5 5 5))
    (write-bytes #"titleAlpha" output)
    (for-each word '(1 2 6 7))
    (for-each word '(1 2 1 8 12))
    (get-output-bytes output))
  (define (fake-host token operation payload)
    (set! calls (cons (list token operation payload) calls))
    (case operation
      [(inspect)
       (list 'ok
             (subbytes private-bytes
                       (hash-ref payload 'start)
                       (hash-ref payload 'end)))]
      [(splice)
       (define edit (hash-ref payload 'edit))
       (set! private-bytes
             (bytes-append
              (subbytes private-bytes 0 (transaction-edit-start edit))
              (transaction-edit-replacement edit)
              (subbytes private-bytes (transaction-edit-end edit))))
       (list 'ok #t)]
      [(apply-batch) (list 'ok #t)]
      [(nested-begin) (list 'ok 17)]
      [(nested-succeed nested-fail abort) (list 'ok #t)]
      [(jan-analyze) (list 'ok (jan-test-record))]
      [else (list 'error 'invalid-state (hasheq 'operation operation))]))

  (check-equal?
   (call-with-transaction
    9 fake-host
    (lambda (transaction)
      (check-equal? (transaction-inspect transaction 0 3) #"abc")
      (check-true
       (void? (transaction-splice! transaction 1 2 #"X")))
      (check-equal? (transaction-inspect transaction 0 3) #"aXc")
      (transaction-invoke-nested
       transaction 'racket "child"
       (lambda (nested)
         (transaction-splice! nested 2 2 #"Y")
         'joined))))
   'joined)
  (check-equal? private-bytes #"aXYc")
  (check-equal? (map cadr (reverse calls))
                '(inspect splice inspect nested-begin splice nested-succeed))

  (set! calls '())
  (define analyzed
    (call-with-transaction
     13 fake-host
     (lambda (transaction) (transaction-jan-analyze transaction #"* Alpha\n"))))
  (check-true (jan-analysis? analyzed))
  (check-equal? (jan-analysis-source-bytes analyzed) 12)
  (check-equal? (jan-analysis-generation analyzed) 7)
  (check-equal? (jan-node-kind-text (car (jan-analysis-nodes analyzed)))
                "heading")
  (check-equal? (jan-attribute-value
                 (car (jan-analysis-attributes analyzed)))
                "Alpha")
  (check-equal? (jan-recovery-code
                 (car (jan-analysis-recoveries analyzed)))
                2)
  (check-equal? (jan-index-end (car (jan-analysis-indexes analyzed))) 12)
  (check-equal? (map cadr (reverse calls)) '(jan-analyze))

  (set! calls '())
  (define handled
    (call-with-transaction
     10 fake-host
     (lambda (transaction)
       (transaction-invoke-nested
        transaction 'racket "handled-child"
        (lambda (_nested)
          (transaction-reject 'out-of-range (hasheq 'actual 99)))))))
  (check-true (transaction-failure? handled))
  (check-eq? (transaction-failure-code handled) 'out-of-range)
  (check-equal? (map cadr (reverse calls)) '(nested-begin nested-fail))

  (define escaped #f)
  (call-with-transaction 11 fake-host
                         (lambda (transaction)
                           (set! escaped transaction)))
  (check-exn exn:fail:contract?
             (lambda () (transaction-inspect escaped 0 1)))

  (define limited
    (make-transaction-limits #:inspection-bytes 2
                             #:batch-splices 1
                             #:text-bytes 2
                             #:nested-depth 1
                             #:descriptor-bytes 8))
  (call-with-transaction
   12 fake-host
   (lambda (transaction)
     (check-eq? (transaction-failure-code
                 (transaction-inspect transaction 0 3))
                'work-limit)
     (check-eq?
      (transaction-failure-code
       (transaction-apply-batch!
        transaction
        (list (make-transaction-edit 0 0 #"a")
              (make-transaction-edit 0 0 #"b"))))
      'splice-limit)
     (check-true (void? (transaction-request-abort! transaction)))
     (check-eq? (transaction-failure-code
                 (transaction-splice! transaction 0 0 #"x"))
                'invalid-state))
   #:limits limited))
