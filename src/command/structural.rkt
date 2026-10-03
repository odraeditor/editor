#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         (prefix-in host: "../hosting/structural-bridge.rkt")
         "native-contracts.rkt")

(provide
 (struct-out structural-scope)
 (struct-out structural-request)
 (struct-out structural-target)
 (struct-out structural-indent-edit)
 (struct-out structural-usage)
 (struct-out structural-plan)
 (struct-out structural-outcome)
 (struct-out structural-diagnostic)
 (struct-out structural-inspection)
 (struct-out structural-failure)
 (contract-out
  [structural-command-control? (-> any/c boolean?)]
  [call-with-structural-commands
   (-> exact-positive-integer? exact-positive-integer?
       (-> structural-command-control? any/c) any/c)]
  [structural-current-scope
   (-> structural-command-control? (or/c structural-scope? structural-failure?))]
  [structural-inspect
   (-> structural-command-control? (or/c structural-inspection? structural-failure?))]
  [structural-forward
   (-> structural-command-control? (or/c structural-outcome? structural-failure?))]
  [structural-backward
   (-> structural-command-control? (or/c structural-outcome? structural-failure?))]
  [structural-up
   (-> structural-command-control? (or/c structural-outcome? structural-failure?))]
  [structural-down
   (-> structural-command-control? (or/c structural-outcome? structural-failure?))]
  [structural-select
   (-> structural-command-control? (or/c structural-outcome? structural-failure?))]
  [structural-indent
   (-> structural-command-control? (or/c structural-outcome? structural-failure?))]
  [structural-definition
   (-> structural-command-control? (or/c structural-outcome? structural-failure?))]
  [native-structural-turn
   (-> exact-positive-integer? exact-positive-integer? list?)]))

(define (contract item) (native-contract-value 'structural item))
(define scope-record-bytes (contract 'scope-record-bytes))
(define request-record-bytes (contract 'request-record-bytes))
(define target-record-bytes (contract 'target-record-bytes))
(define plan-record-bytes (contract 'plan-record-bytes))
(define indent-edit-record-bytes (contract 'indent-edit-record-bytes))
(define usage-record-bytes (contract 'usage-record-bytes))
(define outcome-record-bytes (contract 'outcome-record-bytes))
(define diagnostic-record-bytes (contract 'diagnostic-record-bytes))
(define maximum-target-text-bytes (contract 'maximum-target-text-bytes))
(define maximum-plan-edits (contract 'maximum-plan-edits))
(define maximum-diagnostic-bytes (contract 'maximum-diagnostic-bytes))
(define maximum-inspection-bytes (contract 'maximum-inspection-bytes))

(define operation-scope (contract 'operation-scope))
(define operation-inspect (contract 'operation-inspect))
(define operation-forward (contract 'operation-forward))
(define operation-backward (contract 'operation-backward))
(define operation-up (contract 'operation-up))
(define operation-down (contract 'operation-down))
(define operation-select (contract 'operation-select))
(define operation-indent (contract 'operation-indent))
(define operation-definition (contract 'operation-definition))

(define maximum-inspection-record-bytes
  (+ scope-record-bytes target-record-bytes plan-record-bytes
     (* maximum-plan-edits indent-edit-record-bytes)
     outcome-record-bytes usage-record-bytes diagnostic-record-bytes
     maximum-target-text-bytes maximum-diagnostic-bytes))

(struct structural-command-control (host [scope #:mutable]))
(struct structural-scope
  (schema-version access editor-session-id view-registry-id view-id
                  view-generation view-state-generation buffer-id source-revision
                  selection-generation language-id language-generation
                  provider-registry-id provider-language-id provider-id
                  provider-generation parser-generation tree-generation
                  command-registry-generation capability-generation)
  #:transparent)
(struct structural-request (scope operation point start end has-region?) #:transparent)
(struct structural-target (scope present? start end kind depth) #:transparent)
(struct structural-indent-edit (start end indent-level indent-bytes) #:transparent)
(struct structural-usage
  (visited-nodes visited-depth indent-lines prepared-bytes temporary-bytes)
  #:transparent)
(struct structural-plan (scope start end edits usage) #:transparent)
(struct structural-outcome
  (scope operation completion changed? point mark region-active?
         transaction-id undo-unit-id usage)
  #:transparent)
(struct structural-diagnostic
  (operation failure-code structural-code language-code buffer-id view-id
             expected-revision actual-revision expected-generation actual-generation
             limit actual message)
  #:transparent)
(struct structural-inspection (scope target plan outcome usage diagnostic) #:transparent)
(struct structural-failure (code limit actual) #:transparent)

;; call-with-structural-commands confines typed structural composition to one host turn.
(define (call-with-structural-commands generation token command)
  (host:call-with-structural-host-control
   generation token
   (lambda (control)
     (command (structural-command-control control #f)))))

;; structural-current-scope obtains one exact editor and analysis identity snapshot.
(define (structural-current-scope control)
  (or (structural-command-control-scope control)
      (let ([result (host:structural-host-scope (structural-command-control-host control))])
        (if (host:structural-host-failure? result)
            (host-failure->structural-failure result)
            (let ([scope (decode-scope result 0)])
              (set-structural-command-control-scope! control scope)
              scope)))))

;; structural-inspect copies current state without triggering native analysis.
(define (structural-inspect control)
  (define scope (structural-current-scope control))
  (if (structural-failure? scope)
      scope
      (let ([result
             (host:structural-host-invoke
              (structural-command-control-host control)
              operation-inspect 0 0 (encode-scope scope)
              maximum-inspection-record-bytes)])
        (if (host:structural-host-failure? result)
            (host-failure->structural-failure result)
            (let ([inspection (decode-inspection result)])
              (set-structural-command-control-scope!
               control (structural-inspection-scope inspection))
              inspection)))))

(define (structural-forward control) (structural-run control operation-forward))
(define (structural-backward control) (structural-run control operation-backward))
(define (structural-up control) (structural-run control operation-up))
(define (structural-down control) (structural-run control operation-down))
(define (structural-select control) (structural-run control operation-select))
(define (structural-indent control) (structural-run control operation-indent))
(define (structural-definition control) (structural-run control operation-definition))

;; structural-run sends exact copied scope and selection expectations for one operation.
(define (structural-run control operation)
  (define inspection (structural-inspect control))
  (if (structural-failure? inspection)
      inspection
      (let* ([outcome (structural-inspection-outcome inspection)]
             [point (structural-outcome-point outcome)]
             [mark (structural-outcome-mark outcome)]
             [has-region? (structural-outcome-region-active? outcome)]
             [request
              (structural-request
               (structural-inspection-scope inspection)
               operation
               point
               (if has-region? (min point mark) point)
               (if has-region? (max point mark) point)
               has-region?)]
             [result
              (host:structural-host-invoke
               (structural-command-control-host control)
               operation 0 0 (encode-request request) outcome-record-bytes)])
        (if (host:structural-host-failure? result)
            (host-failure->structural-failure result)
            (let ([refreshed (decode-outcome result 0)])
              (set-structural-command-control-scope!
               control (structural-outcome-scope refreshed))
              refreshed)))))

(define (host-failure->structural-failure failure)
  (structural-failure
   (host:structural-host-failure-code failure)
   (host:structural-host-failure-limit failure)
   (host:structural-host-failure-actual failure)))

(define (encode-request request)
  (define output (make-bytes request-record-bytes))
  (bytes-copy! output 0 (encode-scope (structural-request-scope request)))
  (for ([value (in-list
                (list (structural-request-operation request)
                      (structural-request-point request)
                      (structural-request-start request)
                      (structural-request-end request)
                      (if (structural-request-has-region? request) 1 0)))]
        [offset (in-range scope-record-bytes request-record-bytes 8)])
    (write-u64! output offset value))
  output)

(define (encode-scope scope)
  (define output (make-bytes scope-record-bytes))
  (for ([value (in-list (structural-scope-values scope))]
        [offset (in-range 0 scope-record-bytes 8)])
    (write-u64! output offset value))
  output)

(define (structural-scope-values scope)
  (list
   (structural-scope-schema-version scope)
   (structural-scope-access scope)
   (structural-scope-editor-session-id scope)
   (structural-scope-view-registry-id scope)
   (structural-scope-view-id scope)
   (structural-scope-view-generation scope)
   (structural-scope-view-state-generation scope)
   (structural-scope-buffer-id scope)
   (structural-scope-source-revision scope)
   (structural-scope-selection-generation scope)
   (structural-scope-language-id scope)
   (structural-scope-language-generation scope)
   (structural-scope-provider-registry-id scope)
   (structural-scope-provider-language-id scope)
   (structural-scope-provider-id scope)
   (structural-scope-provider-generation scope)
   (structural-scope-parser-generation scope)
   (structural-scope-tree-generation scope)
   (structural-scope-command-registry-generation scope)
   (structural-scope-capability-generation scope)))

(define (decode-scope input offset)
  (require-width 'decode-scope input offset scope-record-bytes)
  (apply structural-scope
         (for/list ([field-offset (in-range offset (+ offset scope-record-bytes) 8)])
           (read-u64 input field-offset))))

(define (decode-usage input offset)
  (require-width 'decode-usage input offset usage-record-bytes)
  (apply structural-usage
         (for/list ([field-offset (in-range offset (+ offset usage-record-bytes) 8)])
           (read-u64 input field-offset))))

(define (decode-target input offset)
  (require-width 'decode-target input offset target-record-bytes)
  (define present? (read-boolean input (+ offset scope-record-bytes)))
  (define kind-offset (read-u64 input (+ offset scope-record-bytes 24)))
  (define kind-bytes (read-u64 input (+ offset scope-record-bytes 32)))
  (when (> kind-bytes maximum-target-text-bytes)
    (error 'decode-target "node kind exceeds the copied text limit"))
  (structural-target
   (decode-scope input offset)
   present?
   (read-u64 input (+ offset scope-record-bytes 8))
   (read-u64 input (+ offset scope-record-bytes 16))
   (if present? (decode-text input kind-offset kind-bytes) "")
   (read-u64 input (+ offset scope-record-bytes 40))))

(define (decode-plan input offset)
  (require-width 'decode-plan input offset plan-record-bytes)
  (define edit-count (read-u64 input (+ offset scope-record-bytes 16)))
  (when (> edit-count maximum-plan-edits)
    (error 'decode-plan "indentation edit count exceeds the copied plan limit"))
  (define edit-offset (+ offset plan-record-bytes))
  (require-width 'decode-plan input edit-offset (* edit-count indent-edit-record-bytes))
  (define edits
    (for/list ([index (in-range edit-count)])
      (define base (+ edit-offset (* index indent-edit-record-bytes)))
      (structural-indent-edit
       (read-u64 input base)
       (read-u64 input (+ base 8))
       (read-u64 input (+ base 16))
       (read-u64 input (+ base 24)))))
  (values
   (structural-plan
    (decode-scope input offset)
    (read-u64 input (+ offset scope-record-bytes))
    (read-u64 input (+ offset scope-record-bytes 8))
    edits
    (decode-usage input (+ offset scope-record-bytes 24)))
   (+ edit-offset (* edit-count indent-edit-record-bytes))))

(define (decode-outcome input offset)
  (require-width 'decode-outcome input offset outcome-record-bytes)
  (structural-outcome
   (decode-scope input offset)
   (read-u64 input (+ offset scope-record-bytes))
   (read-u64 input (+ offset scope-record-bytes 8))
   (read-boolean input (+ offset scope-record-bytes 16))
   (read-u64 input (+ offset scope-record-bytes 24))
   (read-u64 input (+ offset scope-record-bytes 32))
   (read-boolean input (+ offset scope-record-bytes 40))
   (read-u64 input (+ offset scope-record-bytes 48))
   (read-u64 input (+ offset scope-record-bytes 56))
   (decode-usage input (+ offset scope-record-bytes 64))))

(define (decode-diagnostic input offset)
  (require-width 'decode-diagnostic input offset diagnostic-record-bytes)
  (define message-offset (read-u64 input (+ offset 96)))
  (define message-bytes (read-u64 input (+ offset 104)))
  (when (> message-bytes maximum-diagnostic-bytes)
    (error 'decode-diagnostic "diagnostic exceeds the copied text limit"))
  (structural-diagnostic
   (read-u64 input offset)
   (read-u64 input (+ offset 8))
   (read-u64 input (+ offset 16))
   (read-u64 input (+ offset 24))
   (read-u64 input (+ offset 32))
   (read-u64 input (+ offset 40))
   (read-u64 input (+ offset 48))
   (read-u64 input (+ offset 56))
   (read-u64 input (+ offset 64))
   (read-u64 input (+ offset 72))
   (read-u64 input (+ offset 80))
   (read-u64 input (+ offset 88))
   (if (zero? message-bytes) "" (decode-text input message-offset message-bytes))))

(define (decode-inspection input)
  (require-width
   'decode-inspection input 0
   (+ scope-record-bytes target-record-bytes plan-record-bytes
      outcome-record-bytes usage-record-bytes diagnostic-record-bytes))
  (define scope (decode-scope input 0))
  (define target-offset scope-record-bytes)
  (define plan-offset (+ target-offset target-record-bytes))
  (define-values (plan outcome-offset) (decode-plan input plan-offset))
  (define usage-offset (+ outcome-offset outcome-record-bytes))
  (define diagnostic-offset (+ usage-offset usage-record-bytes))
  (structural-inspection
   scope
   (decode-target input target-offset)
   plan
   (decode-outcome input outcome-offset)
   (decode-usage input usage-offset)
   (decode-diagnostic input diagnostic-offset)))

(define (decode-text input offset length)
  (when (or (> offset (bytes-length input))
            (> length (- (bytes-length input) offset)))
    (error 'decode-structural-record "copied text range is outside the response"))
  (bytes->string/utf-8 input #f offset (+ offset length)))

(define (require-width who input offset width)
  (when (or (> offset (bytes-length input))
            (> width (- (bytes-length input) offset)))
    (error who "truncated structural record")))

(define (read-boolean input offset)
  (case (read-u64 input offset)
    [(0) #f]
    [(1) #t]
    [else (error 'decode-structural-record "invalid copied boolean")]))

(define (read-u64 input offset)
  (integer-bytes->integer input #f #f offset (+ offset 8)))

(define (write-u64! output offset value)
  (integer->integer-bytes value 8 #f #f output offset)
  (void))

;; native-structural-turn executes one production structural capability turn.
(define (native-structural-turn generation token)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #f (string->bytes/utf-8 (exn-message failure))))])
    (define result
      (call-with-structural-commands generation token structural-current-scope))
    (list #t result #"")))

(module+ test-support
  (provide structural-command-control-host
           encode-request
           write-u64!
           operation-forward
           operation-inspect
           outcome-record-bytes
           request-record-bytes
           maximum-inspection-bytes))

(module+ test
  (require rackunit)

  (define scope
    (apply structural-scope (for/list ([value (in-range 1 21)]) value)))
  (check-equal? (decode-scope (encode-scope scope) 0) scope)

  (define request (structural-request scope operation-select 12 4 12 #t))
  (define encoded-request (encode-request request))
  (check-equal? (bytes-length encoded-request) request-record-bytes)
  (check-equal? (read-u64 encoded-request scope-record-bytes) operation-select)
  (check-equal? (read-u64 encoded-request (- request-record-bytes 8)) 1)
  (for ([operation (in-list
                    (list operation-forward operation-backward operation-up
                          operation-down operation-select operation-indent operation-definition))])
    (define generated
      (encode-request (structural-request scope operation 12 12 12 #f)))
    (check-equal? (bytes-length generated) request-record-bytes)
    (check-equal? (decode-scope generated 0) scope)
    (check-equal? (read-u64 generated scope-record-bytes) operation)
    (check-equal? (read-u64 generated (- request-record-bytes 8)) 0))

  (define kind #"identifier")
  (define message #"stale")
  (define fixed-bytes
    (+ scope-record-bytes target-record-bytes plan-record-bytes
       outcome-record-bytes usage-record-bytes diagnostic-record-bytes))
  (define payload (make-bytes (+ fixed-bytes (bytes-length kind) (bytes-length message))))
  (define target-offset scope-record-bytes)
  (define plan-offset (+ target-offset target-record-bytes))
  (define outcome-offset (+ plan-offset plan-record-bytes))
  (define usage-offset (+ outcome-offset outcome-record-bytes))
  (define diagnostic-offset (+ usage-offset usage-record-bytes))
  (bytes-copy! payload 0 (encode-scope scope))
  (bytes-copy! payload target-offset (encode-scope scope))
  (write-u64! payload (+ target-offset scope-record-bytes) 1)
  (write-u64! payload (+ target-offset scope-record-bytes 8) 4)
  (write-u64! payload (+ target-offset scope-record-bytes 16) 12)
  (write-u64! payload (+ target-offset scope-record-bytes 24) fixed-bytes)
  (write-u64! payload (+ target-offset scope-record-bytes 32) (bytes-length kind))
  (write-u64! payload (+ target-offset scope-record-bytes 40) 3)
  (bytes-copy! payload plan-offset (encode-scope scope))
  (write-u64! payload (+ plan-offset scope-record-bytes) 4)
  (write-u64! payload (+ plan-offset scope-record-bytes 8) 12)
  (bytes-copy! payload outcome-offset (encode-scope scope))
  (write-u64! payload (+ outcome-offset scope-record-bytes) operation-select)
  (write-u64! payload (+ outcome-offset scope-record-bytes 8) 2)
  (write-u64! payload (+ outcome-offset scope-record-bytes 16) 1)
  (write-u64! payload (+ outcome-offset scope-record-bytes 24) 12)
  (write-u64! payload (+ outcome-offset scope-record-bytes 32) 4)
  (write-u64! payload (+ outcome-offset scope-record-bytes 40) 1)
  (write-u64! payload diagnostic-offset operation-select)
  (write-u64! payload (+ diagnostic-offset 8) 9)
  (write-u64! payload (+ diagnostic-offset 96) (+ fixed-bytes (bytes-length kind)))
  (write-u64! payload (+ diagnostic-offset 104) (bytes-length message))
  (bytes-copy! payload fixed-bytes kind)
  (bytes-copy! payload (+ fixed-bytes (bytes-length kind)) message)

  (define inspection (decode-inspection payload))
  (check-equal? (structural-inspection-scope inspection) scope)
  (check-equal? (structural-target-kind (structural-inspection-target inspection)) "identifier")
  (check-equal? (structural-outcome-point (structural-inspection-outcome inspection)) 12)
  (check-equal? (structural-diagnostic-message
                 (structural-inspection-diagnostic inspection))
                "stale")
  (define malformed-target (bytes-copy payload))
  (write-u64! malformed-target (+ target-offset scope-record-bytes) 2)
  (check-exn exn:fail? (lambda () (decode-inspection malformed-target)))
  (check-exn exn:fail? (lambda () (decode-inspection (subbytes payload 0 100)))))
