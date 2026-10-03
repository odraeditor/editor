#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "../hosting/buffer-session-bridge.rkt"
         "native-contracts.rkt")

(provide
 (contract-out
  [buffer-session? (-> any/c boolean?)]
  [buffer-scope? (-> any/c boolean?)]
  [buffer-scope-editor-session-id (-> buffer-scope? exact-positive-integer?)]
  [buffer-scope-access (-> buffer-scope? exact-nonnegative-integer?)]
  [buffer-scope-session-id (-> buffer-scope? exact-positive-integer?)]
  [buffer-scope-session-generation (-> buffer-scope? exact-positive-integer?)]
  [buffer-scope-registry-generation (-> buffer-scope? exact-positive-integer?)]
  [buffer-scope-visible-kind (-> buffer-scope? exact-nonnegative-integer?)]
  [buffer-scope-visible-entry (-> buffer-scope? buffer-handle?)]
  [buffer-scope-visible-view (-> buffer-scope? list?)]
  [buffer-scope-visible-ui (-> buffer-scope? list?)]
  [buffer-handle? (-> any/c boolean?)]
  [buffer-handle-session-id (-> buffer-handle? exact-nonnegative-integer?)]
  [buffer-handle-session-generation (-> buffer-handle? exact-nonnegative-integer?)]
  [buffer-handle-registry-generation (-> buffer-handle? exact-nonnegative-integer?)]
  [buffer-handle-entry-id (-> buffer-handle? exact-nonnegative-integer?)]
  [buffer-handle-slot (-> buffer-handle? exact-nonnegative-integer?)]
  [buffer-handle-generation (-> buffer-handle? exact-nonnegative-integer?)]
  [buffer-descriptor? (-> any/c boolean?)]
  [buffer-descriptor-handle (-> buffer-descriptor? buffer-handle?)]
  [buffer-descriptor-buffer-id (-> buffer-descriptor? exact-nonnegative-integer?)]
  [buffer-descriptor-history-id (-> buffer-descriptor? exact-nonnegative-integer?)]
  [buffer-descriptor-view (-> buffer-descriptor? list?)]
  [buffer-descriptor-document-id
   (-> buffer-descriptor? (or/c #f exact-nonnegative-integer?))]
  [buffer-descriptor-label (-> buffer-descriptor? bytes?)]
  [buffer-descriptor-association (-> buffer-descriptor? exact-nonnegative-integer?)]
  [buffer-descriptor-persistence (-> buffer-descriptor? exact-nonnegative-integer?)]
  [buffer-descriptor-operation (-> buffer-descriptor? exact-nonnegative-integer?)]
  [buffer-descriptor-active? (-> buffer-descriptor? boolean?)]
  [buffer-descriptor-modified? (-> buffer-descriptor? boolean?)]
  [buffer-descriptor-activation-sequence
   (-> buffer-descriptor? exact-nonnegative-integer?)]
  [buffer-usage? (-> any/c boolean?)]
  [buffer-usage-scope (-> buffer-usage? buffer-scope?)]
  [buffer-usage-live-buffers (-> buffer-usage? exact-nonnegative-integer?)]
  [buffer-usage-live-documents (-> buffer-usage? exact-nonnegative-integer?)]
  [buffer-usage-live-primary-views (-> buffer-usage? exact-nonnegative-integer?)]
  [buffer-usage-activation-entries (-> buffer-usage? exact-nonnegative-integer?)]
  [buffer-usage-canonical-text-bytes (-> buffer-usage? exact-nonnegative-integer?)]
  [buffer-usage-retained-label-bytes (-> buffer-usage? exact-nonnegative-integer?)]
  [buffer-usage-view-anchors (-> buffer-usage? exact-nonnegative-integer?)]
  [buffer-usage-view-context-bytes (-> buffer-usage? exact-nonnegative-integer?)]
  [buffer-usage-history-bytes (-> buffer-usage? exact-nonnegative-integer?)]
  [buffer-usage-registry-bytes (-> buffer-usage? exact-nonnegative-integer?)]
  [buffer-usage-outstanding-capabilities
   (-> buffer-usage? exact-nonnegative-integer?)]
  [buffer-usage-prepared-operations (-> buffer-usage? exact-nonnegative-integer?)]
  [buffer-usage-detached-cleanup-entries
   (-> buffer-usage? exact-nonnegative-integer?)]
  [buffer-outcome? (-> any/c boolean?)]
  [buffer-outcome-scope (-> buffer-outcome? buffer-scope?)]
  [buffer-outcome-completion (-> buffer-outcome? exact-nonnegative-integer?)]
  [buffer-outcome-handle (-> buffer-outcome? buffer-handle?)]
  [buffer-outcome-document-id (-> buffer-outcome? exact-nonnegative-integer?)]
  [buffer-outcome-buffer-id (-> buffer-outcome? exact-nonnegative-integer?)]
  [buffer-outcome-saved-revision (-> buffer-outcome? exact-nonnegative-integer?)]
  [buffer-outcome-publication (-> buffer-outcome? exact-nonnegative-integer?)]
  [buffer-outcome-closure-outcome (-> buffer-outcome? exact-nonnegative-integer?)]
  [buffer-outcome-modified? (-> buffer-outcome? boolean?)]
  [buffer-outcome-last-buffer? (-> buffer-outcome? boolean?)]
  [buffer-outcome-marked-outcome (-> buffer-outcome? exact-nonnegative-integer?)]
  [buffer-outcome-completed-saves (-> buffer-outcome? exact-nonnegative-integer?)]
  [buffer-outcome-pending-saves (-> buffer-outcome? exact-nonnegative-integer?)]
  [buffer-outcome-completed-kills (-> buffer-outcome? exact-nonnegative-integer?)]
  [buffer-outcome-pending-kills (-> buffer-outcome? exact-nonnegative-integer?)]
  [buffer-outcome-decision-entry-id (-> buffer-outcome? exact-nonnegative-integer?)]
  [buffer-outcome-failed-entry-id (-> buffer-outcome? exact-nonnegative-integer?)]
  [buffer-outcome-live-buffers (-> buffer-outcome? exact-nonnegative-integer?)]
  [buffer-outcome-live-documents (-> buffer-outcome? exact-nonnegative-integer?)]
  [buffer-mark-decision
   (-> buffer-handle? (or/c 'save 'discard 'cancel) (or/c #f path-string? bytes?)
       buffer-mark-decision?)]
  [buffer-mark-decision? (-> any/c boolean?)]
  [buffer-mark-decision-handle (-> buffer-mark-decision? buffer-handle?)]
  [buffer-mark-decision-kind
   (-> buffer-mark-decision? (or/c 'save 'discard 'cancel))]
  [buffer-mark-decision-path
   (-> buffer-mark-decision? (or/c #f path-string? bytes?))]
  [buffer-mark (-> buffer-handle? (or/c 'save 'kill) buffer-mark?)]
  [buffer-mark? (-> any/c boolean?)]
  [buffer-mark-handle (-> buffer-mark? buffer-handle?)]
  [buffer-mark-kind (-> buffer-mark? (or/c 'save 'kill))]
  [buffer-session-failure? (-> any/c boolean?)]
  [buffer-session-failure-code
   (-> buffer-session-failure? exact-nonnegative-integer?)]
  [buffer-session-failure-limit
   (-> buffer-session-failure? exact-nonnegative-integer?)]
  [buffer-session-failure-actual
   (-> buffer-session-failure? exact-nonnegative-integer?)]
  [buffer-command-names (listof symbol?)]
  [call-with-buffer-session
   (-> exact-positive-integer? exact-positive-integer?
       (-> buffer-session? any/c) any/c)]
  [buffer-session-scope (-> buffer-session? buffer-scope?)]
  [buffer-session-usage
   (-> buffer-session? (or/c buffer-usage? buffer-session-failure?))]
  [buffer-session-descriptors
   (->* (buffer-session?)
        (#:count exact-nonnegative-integer?
         #:label-bytes exact-nonnegative-integer?)
        (or/c (listof buffer-descriptor?) buffer-session-failure?))]
  [buffer-session-descriptor
   (-> buffer-session? buffer-handle?
       (or/c buffer-descriptor? buffer-session-failure?))]
  [buffer-session-create!
   (-> buffer-session? (or/c string? bytes?)
       (or/c buffer-outcome? buffer-session-failure?))]
  [buffer-session-open!
   (-> buffer-session? (or/c path-string? bytes?)
       (or/c buffer-outcome? buffer-session-failure?))]
  [buffer-session-activate!
   (-> buffer-session? buffer-handle?
       (or/c buffer-outcome? buffer-session-failure?))]
  [buffer-session-save!
   (->* (buffer-session? buffer-handle?)
        (#:path (or/c #f path-string? bytes?))
        (or/c buffer-outcome? buffer-session-failure?))]
  [buffer-session-kill!
   (->* (buffer-session? buffer-handle?)
        (#:discard? boolean?)
        (or/c buffer-outcome? buffer-session-failure?))]
  [buffer-session-execute-marks!
   (-> buffer-session? (listof buffer-mark?) (listof buffer-mark-decision?)
       (or/c buffer-outcome? buffer-session-failure?))]
  [native-buffer-session-turn
   (-> exact-positive-integer? exact-positive-integer? list?)]))

(define (contract item) (native-contract-value 'buffer-session item))
(define scope-record-bytes (contract 'scope-record-bytes))
(define usage-record-bytes (contract 'usage-record-bytes))
(define descriptor-header-bytes (contract 'descriptor-header-bytes))
(define descriptor-record-bytes (contract 'descriptor-record-bytes))
(define request-header-bytes (contract 'request-header-bytes))
(define outcome-record-bytes (contract 'outcome-record-bytes))
(define decision-record-bytes (contract 'decision-record-bytes))
(define mark-record-bytes (contract 'mark-record-bytes))
(define maximum-descriptors (contract 'maximum-descriptors))
(define maximum-label-bytes (contract 'maximum-label-bytes))
(define maximum-decisions (contract 'maximum-decisions))
(define maximum-marks (contract 'maximum-marks))
(define operation-scope (contract 'operation-scope))
(define operation-usage (contract 'operation-usage))
(define operation-descriptors (contract 'operation-descriptors))
(define operation-descriptor (contract 'operation-descriptor))
(define operation-create (contract 'operation-create))
(define operation-open (contract 'operation-open))
(define operation-activate (contract 'operation-activate))
(define operation-save (contract 'operation-save))
(define operation-kill (contract 'operation-kill))
(define operation-execute-marks (contract 'operation-execute-marks))

(define buffer-command-names
  '(find-file switch-to-buffer kill-buffer list-buffers save-associated-document))

(struct buffer-session (control [scope-bytes #:mutable]))
(struct buffer-scope
  (raw editor-session-id access session-id session-generation registry-generation
       visible-kind visible-entry visible-view visible-ui)
  #:transparent)
(struct buffer-handle
  (session-id session-generation registry-generation entry-id slot generation)
  #:transparent)
(struct buffer-descriptor
  (handle buffer-id history-id view document-id label association persistence
          operation active? modified? activation-sequence)
  #:transparent)
(struct buffer-usage
  (scope live-buffers live-documents live-primary-views activation-entries
         canonical-text-bytes retained-label-bytes view-anchors view-context-bytes
         history-bytes registry-bytes outstanding-capabilities prepared-operations
         detached-cleanup-entries)
  #:transparent)
(struct buffer-outcome
  (scope completion handle document-id buffer-id saved-revision publication
         closure-outcome modified? last-buffer? marked-outcome completed-saves
         pending-saves completed-kills pending-kills decision-entry-id failed-entry-id
         live-buffers live-documents)
  #:transparent)
(struct buffer-mark-decision (handle kind path) #:transparent)
(struct buffer-mark (handle kind) #:transparent)

;; call-with-buffer-session creates one cohesive facade over the dynamic native turn.
(define (call-with-buffer-session generation token command)
  (call-with-buffer-session-control
   generation token
   (lambda (control)
     (define raw-scope
       (buffer-session-native-invoke control operation-scope 0 0 #"" scope-record-bytes))
     (when (buffer-session-failure? raw-scope)
       (error 'call-with-buffer-session "native scope inspection failed"))
     (command (buffer-session control raw-scope)))))

(define (buffer-session-scope session)
  (decode-scope (buffer-session-scope-bytes session)))

(define (buffer-session-usage session)
  (define result
    (buffer-session-native-invoke
     (buffer-session-control session) operation-usage 0 0
     (buffer-session-scope-bytes session) usage-record-bytes))
  (if (buffer-session-failure? result)
      result
      (buffer-usage
       (decode-scope result)
       (read-u64 result 144) (read-u64 result 152) (read-u64 result 160)
       (read-u64 result 168) (read-u64 result 176) (read-u64 result 184)
       (read-u64 result 192) (read-u64 result 200) (read-u64 result 208)
       (read-u64 result 216) (read-u64 result 224) (read-u64 result 232)
       (read-u64 result 240))))

(define (buffer-session-descriptors session
                                    #:count [count maximum-descriptors]
                                    #:label-bytes [label-bytes maximum-label-bytes])
  (when (> count maximum-descriptors)
    (raise-arguments-error 'buffer-session-descriptors
                           "descriptor count exceeds the supported maximum"
                           "limit" maximum-descriptors "actual" count))
  (when (> label-bytes maximum-label-bytes)
    (raise-arguments-error 'buffer-session-descriptors
                           "label bytes exceed the supported maximum"
                           "limit" maximum-label-bytes "actual" label-bytes))
  (define result
    (buffer-session-native-invoke
     (buffer-session-control session) operation-descriptors count label-bytes
     (buffer-session-scope-bytes session)
     (+ descriptor-header-bytes (* count descriptor-record-bytes) label-bytes)))
  (if (buffer-session-failure? result)
      result
      (decode-descriptors result count label-bytes)))

(define (buffer-session-descriptor session handle)
  (define request (make-request session operation-descriptor #:handle handle))
  (define result
    (buffer-session-native-invoke
     (buffer-session-control session) operation-descriptor 0 0 request
     (+ descriptor-header-bytes descriptor-record-bytes maximum-label-bytes)))
  (if (buffer-session-failure? result)
      result
      (let ([descriptors (decode-descriptors result 1 maximum-label-bytes)])
        (unless (= (length descriptors) 1)
          (raise-result-error 'buffer-session-descriptor "one descriptor" result))
        (car descriptors))))

(define (buffer-session-create! session name)
  (invoke-mutation session operation-create #:text (text-bytes name)))

(define (buffer-session-open! session path)
  (invoke-mutation session operation-open #:text (text-bytes path)))

(define (buffer-session-activate! session handle)
  (invoke-mutation session operation-activate #:handle handle))

(define (buffer-session-save! session handle #:path [path #f])
  (invoke-mutation session operation-save #:handle handle
                   #:text (if path (text-bytes path) #"")))

(define (buffer-session-kill! session handle #:discard? [discard? #f])
  (invoke-mutation session operation-kill #:handle handle
                   #:authority (if discard? 1 0)))

(define (buffer-session-execute-marks! session marks decisions)
  (when (or (null? marks) (> (length marks) maximum-marks))
    (raise-arguments-error 'buffer-session-execute-marks!
                           "mark count is outside the supported range"
                           "limit" maximum-marks
                           "actual" (length marks)))
  (when (> (length decisions) maximum-decisions)
    (raise-arguments-error 'buffer-session-execute-marks!
                           "decision count exceeds the supported maximum"
                           "limit" maximum-decisions
                           "actual" (length decisions)))
  (define request
    (make-request session operation-execute-marks
                  #:marks marks #:decisions decisions))
  (define result
    (buffer-session-native-invoke
     (buffer-session-control session) operation-execute-marks 0 0
     request outcome-record-bytes))
  (if (buffer-session-failure? result)
      result
      (begin
        (set-buffer-session-scope-bytes! session (subbytes result 0 scope-record-bytes))
        (decode-outcome result))))

(define (invoke-mutation session operation
                         #:handle [handle #f]
                         #:authority [authority 0]
                         #:text [text #""])
  (define request
    (make-request session operation #:handle handle #:authority authority #:text text))
  (define result
    (buffer-session-native-invoke
     (buffer-session-control session) operation 0 0 request outcome-record-bytes))
  (if (buffer-session-failure? result)
      result
      (begin
        (set-buffer-session-scope-bytes! session (subbytes result 0 scope-record-bytes))
        (decode-outcome result))))

(define (make-request session operation
                      #:handle [handle #f]
                      #:authority [authority 0]
                      #:marks [marks '()]
                      #:decisions [decisions '()]
                      #:text [text #""])
  (define paths (for/list ([decision (in-list decisions)])
                  (if (buffer-mark-decision-path decision)
                      (text-bytes (buffer-mark-decision-path decision))
                      #"")))
  (define path-bytes (apply + (map bytes-length paths)))
  (define records-bytes (* (length decisions) decision-record-bytes))
  (define marks-bytes (* (length marks) mark-record-bytes))
  (define request
    (make-bytes (+ request-header-bytes (bytes-length text) marks-bytes
                   records-bytes path-bytes)))
  (bytes-copy! request 0 (buffer-session-scope-bytes session))
  (write-u64! request 144 operation)
  (write-u64! request 152 authority)
  (when handle (write-handle! request 160 handle))
  (write-u64! request 208 (length marks))
  (write-u64! request 256 (bytes-length text))
  (write-u64! request 264 (length decisions))
  (bytes-copy! request request-header-bytes text)
  (define marks-start (+ request-header-bytes (bytes-length text)))
  (for ([mark (in-list marks)] [index (in-naturals)])
    (define base (+ marks-start (* index mark-record-bytes)))
    (write-handle! request base (buffer-mark-handle mark))
    (write-u64! request (+ base 48)
                (case (buffer-mark-kind mark) [(save) 1] [(kill) 2])))
  (define records-start (+ marks-start marks-bytes))
  (define paths-start (+ records-start records-bytes))
  (define path-offset 0)
  (for ([decision (in-list decisions)] [path (in-list paths)] [index (in-naturals)])
    (define base (+ records-start (* index decision-record-bytes)))
    (write-handle! request base (buffer-mark-decision-handle decision))
    (write-u64! request (+ base 48)
                (case (buffer-mark-decision-kind decision)
                  [(save) 1] [(discard) 2] [(cancel) 3]))
    (write-u64! request (+ base 56) path-offset)
    (write-u64! request (+ base 64) (bytes-length path))
    (bytes-copy! request (+ paths-start path-offset) path)
    (set! path-offset (+ path-offset (bytes-length path))))
  request)

(define (decode-descriptors result count-limit label-limit)
  (unless (>= (bytes-length result) descriptor-header-bytes)
    (raise-result-error 'buffer-session-descriptors "a complete header" result))
  (define count (read-u64 result 144))
  (define label-bytes (read-u64 result 152))
  (define label-start (+ descriptor-header-bytes (* count descriptor-record-bytes)))
  (unless (and (<= count count-limit) (<= label-bytes label-limit)
               (= (bytes-length result) (+ label-start label-bytes)))
    (raise-result-error 'buffer-session-descriptors "a bounded complete batch" result))
  (for/list ([index (in-range count)])
    (define base (+ descriptor-header-bytes (* index descriptor-record-bytes)))
    (define label-offset (read-u64 result (+ base 104)))
    (define label-length (read-u64 result (+ base 112)))
    (unless (and (<= label-offset label-bytes)
                 (<= label-length (- label-bytes label-offset)))
      (raise-result-error 'buffer-session-descriptors "valid label offsets" result))
    (buffer-descriptor
     (read-handle result base)
     (read-u64 result (+ base 48))
     (read-u64 result (+ base 56))
     (list (read-u64 result (+ base 64))
           (read-u64 result (+ base 72))
           (read-u64 result (+ base 80)))
     (and (positive? (read-u64 result (+ base 88)))
          (read-u64 result (+ base 96)))
     (bytes->immutable-bytes
      (subbytes result (+ label-start label-offset)
                (+ label-start label-offset label-length)))
     (read-u64 result (+ base 120))
     (read-u64 result (+ base 128))
     (read-u64 result (+ base 136))
     (positive? (read-u64 result (+ base 144)))
     (positive? (read-u64 result (+ base 152)))
     (read-u64 result (+ base 160)))))

(define (decode-outcome result)
  (unless (= (bytes-length result) outcome-record-bytes)
    (raise-result-error 'buffer-session "one complete operation outcome" result))
  (buffer-outcome
   (decode-scope result)
   (read-u64 result 144)
   (read-handle result 152)
   (read-u64 result 200) (read-u64 result 208) (read-u64 result 216)
   (read-u64 result 224) (read-u64 result 232)
   (positive? (read-u64 result 240)) (positive? (read-u64 result 248))
   (read-u64 result 256) (read-u64 result 264) (read-u64 result 272)
   (read-u64 result 280) (read-u64 result 288) (read-u64 result 296)
   (read-u64 result 304) (read-u64 result 312) (read-u64 result 320)))

(define (decode-scope bytes)
  (unless (>= (bytes-length bytes) scope-record-bytes)
    (raise-result-error 'buffer-session-scope "one complete scope" bytes))
  (buffer-scope
   (bytes->immutable-bytes (subbytes bytes 0 scope-record-bytes))
   (read-u64 bytes 0) (read-u64 bytes 8) (read-u64 bytes 16)
   (read-u64 bytes 24) (read-u64 bytes 32) (read-u64 bytes 40)
   (read-handle bytes 48)
   (list (read-u64 bytes 96) (read-u64 bytes 104) (read-u64 bytes 112))
   (list (read-u64 bytes 120) (read-u64 bytes 128) (read-u64 bytes 136))))

(define (read-handle bytes base)
  (buffer-handle
   (read-u64 bytes base) (read-u64 bytes (+ base 8))
   (read-u64 bytes (+ base 16)) (read-u64 bytes (+ base 24))
   (read-u64 bytes (+ base 32)) (read-u64 bytes (+ base 40))))

(define (write-handle! bytes base handle)
  (for ([value (in-list
                (list (buffer-handle-session-id handle)
                      (buffer-handle-session-generation handle)
                      (buffer-handle-registry-generation handle)
                      (buffer-handle-entry-id handle)
                      (buffer-handle-slot handle)
                      (buffer-handle-generation handle)))]
        [offset (in-range base (+ base 48) 8)])
    (write-u64! bytes offset value)))

(define (text-bytes value)
  (cond
    [(bytes? value) value]
    [(path? value) (path->bytes value)]
    [else (string->bytes/utf-8 value)]))

(define (read-u64 bytes offset)
  (integer-bytes->integer bytes #f #f offset (+ offset 8)))

(define (write-u64! bytes offset value)
  (integer->integer-bytes value 8 #f #f bytes offset))

;; native-buffer-session-turn executes one production buffer-session turn.
(define (native-buffer-session-turn generation token)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #f (string->bytes/utf-8 (exn-message failure))))])
    (define result
      (call-with-buffer-session generation token buffer-session-scope))
    (list #t result #"")))

(module+ test-support
  (provide buffer-session-scope-bytes
           set-buffer-session-scope-bytes!
           buffer-session-control
           buffer-session-native-invoke
           operation-create
           outcome-record-bytes))

(module+ test
  (require rackunit)

  (check-equal? buffer-command-names
                '(find-file switch-to-buffer kill-buffer list-buffers
                            save-associated-document))
  (define handle (buffer-handle 1 2 3 4 5 6))
  (define bytes (make-bytes 48))
  (write-handle! bytes 0 handle)
  (check-equal? (read-handle bytes 0) handle)
  (check-equal? (text-bytes "λ") #"\316\273")
  (define marked-request
    (make-request
     (buffer-session #f (make-bytes scope-record-bytes))
     operation-execute-marks
     #:marks (list (buffer-mark handle 'kill))
     #:decisions (list (buffer-mark-decision handle 'discard #f))))
  (check-equal?
   (bytes-length marked-request)
   (+ request-header-bytes mark-record-bytes decision-record-bytes))
  (check-equal? (read-u64 marked-request 208) 1)
  (check-equal? (read-handle marked-request request-header-bytes) handle)
  (check-equal? (read-u64 marked-request (+ request-header-bytes 48)) 2)
  (check-equal?
   (read-handle marked-request (+ request-header-bytes mark-record-bytes))
   handle)
  (define malformed-descriptors (make-bytes descriptor-header-bytes))
  (void (write-u64! malformed-descriptors 144 1))
  (check-exn
   exn:fail?
   (lambda () (decode-descriptors malformed-descriptors 1 maximum-label-bytes))))
