#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         (prefix-in host: "../hosting/result-provider-bridge.rkt")
         "native-contracts.rkt")

(provide
 (struct-out result-scope)
 (struct-out result-location)
 (struct-out result-group)
 (struct-out result-continuation)
 (struct-out result-refresh)
 (struct-out result-definition)
 (struct-out result-view)
 (struct-out result-outcome)
 (struct-out result-failure)
 (contract-out
  [result-command-control? (-> any/c boolean?)]
  [call-with-results
   (-> exact-positive-integer? exact-positive-integer?
       (-> result-command-control? any/c) any/c)]
  [result-current-scope
   (-> result-command-control? (or/c result-scope? result-failure?))]
  [result-inspect
   (-> result-command-control? (or/c result-view? result-failure?))]
  [result-publish
   (-> result-command-control? result-definition?
       (or/c result-outcome? result-failure?))]
  [result-move
   (-> result-command-control? (or/c 'first 'previous 'next 'last)
       (or/c result-outcome? result-failure?))]
  [native-result-turn
   (-> exact-positive-integer? exact-positive-integer? list?)]))

(define (contract item) (native-contract-value 'result item))
(define scope-record-bytes (contract 'scope-record-bytes))
(define publication-header-bytes (contract 'publication-header-bytes))
(define view-header-bytes (contract 'view-header-bytes))
(define location-record-bytes (contract 'location-record-bytes))
(define group-record-bytes (contract 'group-record-bytes))
(define movement-request-bytes (contract 'movement-request-bytes))
(define outcome-record-bytes (contract 'outcome-record-bytes))
(define maximum-inspection-bytes (contract 'maximum-inspection-bytes))
(define maximum-locations (contract 'maximum-locations))
(define maximum-groups (contract 'maximum-groups))
(define maximum-text-bytes (contract 'maximum-text-bytes))
(define operation-inspect (contract 'operation-inspect))
(define operation-publish (contract 'operation-publish))
(define operation-move (contract 'operation-move))
(define source-kind-programmable (contract 'source-kind-programmable))

(struct result-command-control (host [scope #:mutable]))
(struct result-scope
  (schema-version access editor-session-id set-id set-generation capability-generation)
  #:transparent)
(struct result-location
  (id group-id buffer-id revision start end source-identity preview annotation)
  #:transparent)
(struct result-group (id label) #:transparent)
(struct result-continuation (present? provider cursor limit) #:transparent)
(struct result-refresh (provider query-identity policy-generation scope-generation) #:transparent)
(struct result-definition
  (source-id source-generation descriptor metadata-values completeness continuation
             refresh edit-capability locations groups selected-id has-selection?)
  #:transparent)
(struct result-view
  (scope source-id source-generation source-kind descriptor metadata-values
         completeness continuation refresh edit-capability locations groups
         selected-index has-selection? accounting)
  #:transparent)
(struct result-outcome
  (scope transition set-id generation location-id selected-index has-selection?)
  #:transparent)
(struct result-failure (code limit actual) #:transparent)

;; call-with-results confines the typed facade to one native turn.
(define (call-with-results generation token command)
  (host:call-with-result-host-control
   generation token
   (lambda (control) (command (result-command-control control #f)))))

(define (result-current-scope control)
  (or (result-command-control-scope control)
      (let ([result (host:result-host-scope (result-command-control-host control))])
        (if (host:result-host-failure? result)
            (host-failure->result-failure result)
            (let ([scope (decode-scope result 0)])
              (set-result-command-control-scope! control scope)
              scope)))))

(define (result-inspect control)
  (define scope (result-current-scope control))
  (if (result-failure? scope)
      scope
      (let ([result
             (host:result-host-invoke
              (result-command-control-host control)
              operation-inspect 0 0 (encode-scope scope) maximum-inspection-bytes)])
        (if (host:result-host-failure? result)
            (host-failure->result-failure result)
            (let ([view (decode-view result)])
              (set-result-command-control-scope! control (result-view-scope view))
              view)))))

(define (result-publish control definition)
  (define scope (result-current-scope control))
  (if (result-failure? scope)
      scope
      (let ([result
             (host:result-host-invoke
              (result-command-control-host control)
              operation-publish 0 0
              (encode-publication scope definition) outcome-record-bytes)])
        (decode-outcome-or-failure control result))))

(define (result-move control movement)
  (define scope (result-current-scope control))
  (if (result-failure? scope)
      scope
      (let ([request (make-bytes movement-request-bytes)])
        (bytes-copy! request 0 (encode-scope scope))
        (write-u64! request scope-record-bytes
                    (case movement [(first) 1] [(previous) 2] [(next) 3] [(last) 4]))
        (decode-outcome-or-failure
         control
         (host:result-host-invoke
          (result-command-control-host control)
          operation-move 0 0 request outcome-record-bytes)))))

(define (decode-outcome-or-failure control result)
  (if (host:result-host-failure? result)
      (host-failure->result-failure result)
      (let ([outcome (decode-outcome result)])
        (set-result-command-control-scope! control (result-outcome-scope outcome))
        outcome)))

(define (encode-publication scope definition)
  (define locations (result-definition-locations definition))
  (define groups (result-definition-groups definition))
  (unless (<= (length locations) maximum-locations)
    (raise-arguments-error 'result-publish "too many result locations"))
  (unless (<= (length groups) maximum-groups)
    (raise-arguments-error 'result-publish "too many result groups"))
  (unless (= (length (result-definition-metadata-values definition)) 8)
    (raise-arguments-error 'result-publish "metadata-values must contain eight integers"))
  (define descriptor (string->bytes/utf-8 (result-definition-descriptor definition)))
  (define preview-bytes (map (lambda (item) (string->bytes/utf-8 (result-location-preview item))) locations))
  (define annotation-bytes (map (lambda (item) (string->bytes/utf-8 (result-location-annotation item))) locations))
  (define group-bytes (map (lambda (item) (string->bytes/utf-8 (result-group-label item))) groups))
  (define text-length
    (+ (bytes-length descriptor)
       (for/sum ([value (in-list preview-bytes)]) (bytes-length value))
       (for/sum ([value (in-list annotation-bytes)]) (bytes-length value))
       (for/sum ([value (in-list group-bytes)]) (bytes-length value))))
  (unless (<= text-length maximum-text-bytes)
    (raise-arguments-error 'result-publish "result text exceeds the copied text limit"))
  (define records-end
    (+ publication-header-bytes
       (* (length locations) location-record-bytes)
       (* (length groups) group-record-bytes)))
  (define output (make-bytes (+ records-end text-length)))
  (bytes-copy! output 0 (encode-scope scope))
  (define continuation (result-definition-continuation definition))
  (define refresh (result-definition-refresh definition))
  (for ([value
         (in-list
          (list (result-definition-source-id definition)
                (result-definition-source-generation definition)
                source-kind-programmable
                (completeness->integer (result-definition-completeness definition))
                (boolean->integer (result-continuation-present? continuation))
                (result-continuation-provider continuation)
                (result-continuation-cursor continuation)
                (result-continuation-limit continuation)
                (result-refresh-provider refresh)
                (result-refresh-query-identity refresh)
                (result-refresh-policy-generation refresh)
                (result-refresh-scope-generation refresh)
                (edit-capability->integer (result-definition-edit-capability definition))
                (result-definition-selected-id definition)
                (boolean->integer (result-definition-has-selection? definition))
                (length locations)
                (length groups)
                (bytes-length descriptor)
                text-length))]
        [offset (in-range scope-record-bytes publication-header-bytes 8)])
    (write-u64! output offset value))
  (for ([value (in-list (result-definition-metadata-values definition))]
        [offset (in-range 200 publication-header-bytes 8)])
    (write-u64! output offset value))
  (define text-offset records-end)
  (bytes-copy! output text-offset descriptor)
  (set! text-offset (+ text-offset (bytes-length descriptor)))
  (for ([location (in-list locations)]
        [preview (in-list preview-bytes)]
        [annotation (in-list annotation-bytes)]
        [index (in-naturals)])
    (define base (+ publication-header-bytes (* index location-record-bytes)))
    (define preview-offset text-offset)
    (bytes-copy! output text-offset preview)
    (set! text-offset (+ text-offset (bytes-length preview)))
    (define annotation-offset text-offset)
    (bytes-copy! output text-offset annotation)
    (set! text-offset (+ text-offset (bytes-length annotation)))
    (for ([value
           (in-list
            (list (result-location-id location)
                  (result-location-group-id location)
                  (result-location-buffer-id location)
                  (result-location-revision location)
                  (result-location-start location)
                  (result-location-end location)
                  (result-location-source-identity location)
                  preview-offset (bytes-length preview)
                  annotation-offset (bytes-length annotation)))]
          [offset (in-range base (+ base location-record-bytes) 8)])
      (write-u64! output offset value)))
  (for ([group (in-list groups)]
        [label (in-list group-bytes)]
        [index (in-naturals)])
    (define base (+ publication-header-bytes
                    (* (length locations) location-record-bytes)
                    (* index group-record-bytes)))
    (define label-offset text-offset)
    (bytes-copy! output text-offset label)
    (set! text-offset (+ text-offset (bytes-length label)))
    (write-u64! output base (result-group-id group))
    (write-u64! output (+ base 8) label-offset)
    (write-u64! output (+ base 16) (bytes-length label)))
  output)

(define (decode-view input)
  (require-width 'decode-result-view input 0 view-header-bytes)
  (define scope (decode-scope input 0))
  (define location-count (read-u64 input 248))
  (define group-count (read-u64 input 256))
  (define text-bytes (read-u64 input 264))
  (when (or (> location-count maximum-locations) (> group-count maximum-groups)
            (> text-bytes maximum-text-bytes))
    (error 'decode-result-view "copied result view exceeds declared limits"))
  (define records-end (+ view-header-bytes
                         (* location-count location-record-bytes)
                         (* group-count group-record-bytes)))
  (require-width 'decode-result-view input 0 (+ records-end text-bytes))
  (define locations
    (for/list ([index (in-range location-count)])
      (define base (+ view-header-bytes (* index location-record-bytes)))
      (result-location
       (read-u64 input base) (read-u64 input (+ base 8))
       (read-u64 input (+ base 16)) (read-u64 input (+ base 24))
       (read-u64 input (+ base 32)) (read-u64 input (+ base 40))
       (read-u64 input (+ base 48))
       (decode-text input (read-u64 input (+ base 56)) (read-u64 input (+ base 64)))
       (decode-text input (read-u64 input (+ base 72)) (read-u64 input (+ base 80))))))
  (define groups
    (for/list ([index (in-range group-count)])
      (define base (+ view-header-bytes (* location-count location-record-bytes)
                      (* index group-record-bytes)))
      (result-group
       (read-u64 input base)
       (decode-text input (read-u64 input (+ base 8)) (read-u64 input (+ base 16))))))
  (result-view
   scope
   (read-u64 input 48) (read-u64 input 56) (read-u64 input 64)
   (decode-text input (read-u64 input 72) (read-u64 input 80))
   (for/list ([offset (in-range 88 152 8)]) (read-u64 input offset))
   (integer->completeness (read-u64 input 152))
   (result-continuation (read-boolean input 160) (read-u64 input 168)
                        (read-u64 input 176) (read-u64 input 184))
   (result-refresh (read-u64 input 192) (read-u64 input 200)
                   (read-u64 input 208) (read-u64 input 216))
   (integer->edit-capability (read-u64 input 224))
   locations groups (read-u64 input 232) (read-boolean input 240)
   (for/list ([offset (in-range 272 336 8)]) (read-u64 input offset))))

(define (decode-outcome input)
  (require-width 'decode-result-outcome input 0 outcome-record-bytes)
  (result-outcome
   (decode-scope input 0)
   (read-u64 input 48) (read-u64 input 56) (read-u64 input 64)
   (read-u64 input 72) (read-u64 input 80) (read-boolean input 88)))

(define (encode-scope scope)
  (define output (make-bytes scope-record-bytes))
  (for ([value (in-list (list (result-scope-schema-version scope)
                              (result-scope-access scope)
                              (result-scope-editor-session-id scope)
                              (result-scope-set-id scope)
                              (result-scope-set-generation scope)
                              (result-scope-capability-generation scope)))]
        [offset (in-range 0 scope-record-bytes 8)])
    (write-u64! output offset value))
  output)

(define (decode-scope input offset)
  (require-width 'decode-result-scope input offset scope-record-bytes)
  (apply result-scope
         (for/list ([field-offset (in-range offset (+ offset scope-record-bytes) 8)])
           (read-u64 input field-offset))))

(define (host-failure->result-failure failure)
  (result-failure (host:result-host-failure-code failure)
                  (host:result-host-failure-limit failure)
                  (host:result-host-failure-actual failure)))

(define (decode-text input offset length)
  (require-width 'decode-result-text input offset length)
  (bytes->string/utf-8 input #f offset (+ offset length)))

(define (require-width who input offset width)
  (when (or (> offset (bytes-length input)) (> width (- (bytes-length input) offset)))
    (error who "truncated result record")))

(define (read-u64 input offset)
  (integer-bytes->integer input #f #f offset (+ offset 8)))
(define (write-u64! output offset value)
  (integer->integer-bytes value 8 #f #f output offset)
  (void))
(define (read-boolean input offset)
  (case (read-u64 input offset) [(0) #f] [(1) #t]
    [else (error 'decode-result-record "invalid copied boolean")]))
(define (boolean->integer value) (if value 1 0))
(define (completeness->integer value)
  (case value [(complete) 1] [(incomplete) 2]
    [else (raise-argument-error 'result-publish "'complete or 'incomplete" value)]))
(define (integer->completeness value)
  (case value [(1) 'complete] [(2) 'incomplete]
    [else (error 'decode-result-record "invalid completeness")]))
(define (edit-capability->integer value)
  (case value [(read-only) 1] [(single-buffer) 2] [(multiple-buffers) 3]
    [else (raise-argument-error 'result-publish "a result edit capability" value)]))
(define (integer->edit-capability value)
  (case value [(1) 'read-only] [(2) 'single-buffer] [(3) 'multiple-buffers]
    [else (error 'decode-result-record "invalid edit capability")]))

;; native-result-turn publishes one bounded factory fixture through the public facade.
(define (native-result-turn generation token)
  (with-handlers ([exn? (lambda (failure)
                          (list #f #f (string->bytes/utf-8 (exn-message failure))))])
    (define result
      (call-with-results
       generation token
       (lambda (control)
         (define published
           (result-publish
            control
            (result-definition
             41 1 "factory programmable results" (make-list 8 0)
             'complete (result-continuation #f 0 0 0)
             (result-refresh 41 1 1 1) 'read-only
             (list (result-location 1 0 1 1 0 1 1 "fixture" "programmable"))
             '() 1 #t)))
         (if (result-failure? published) published (result-inspect control)))))
    (if (result-failure? result)
        (list #f result #"native result provider rejected the fixture")
        (list #t result #""))))

(module+ test
  (require rackunit)

  (define scope (result-scope 1 7 9 12 0 3))
  (define definition
    (result-definition
     41 1 "fixture" (make-list 8 0) 'complete
     (result-continuation #f 0 0 0) (result-refresh 41 1 1 1) 'read-only
     (list (result-location 1 0 1 1 0 4 5 "text" "note"))
     (list (result-group 1 "group")) 1 #t))
  (define encoded (encode-publication scope definition))
  (check-equal? (read-u64 encoded 168) 1)
  (check-equal? (read-u64 encoded 176) 1)
  (check-equal? (read-u64 encoded 184) 7)
  (check-exn
   exn:fail:contract?
   (lambda ()
     (encode-publication
      scope
      (struct-copy result-definition definition [metadata-values '(1 2)]))))
  (define escaped #f)
  (call-with-results 1 1 (lambda (control) (set! escaped control)))
  (check-exn exn:fail? (lambda () (result-current-scope escaped))))
