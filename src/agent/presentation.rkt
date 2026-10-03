#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/string
         "admission.rkt"
         "authority.rkt"
         "continuity.rkt"
         "controls.rkt"
         "driver.rkt"
         "execution.rkt"
         "inspection.rkt"
         "registry.rkt")

(provide
 minimum-agent-surface-width
 maximum-agent-surface-rows
 (struct-out odra-agent-surface-row)
 (struct-out odra-agent-local-surface)
 (contract-out
  [present-agent-candidates
   (->* (symbol? list?)
        (#:width exact-positive-integer?)
        odra-agent-local-surface?)]
  [present-agent-task
   (->* (odra-agent-continuity-store? (or/c symbol? string?))
        (#:width exact-positive-integer? #:limit exact-positive-integer?)
        odra-agent-local-surface?)]
  [present-agent-detail
   (->* (odra-agent-inspection-projection?)
        (#:width exact-positive-integer?)
        odra-agent-local-surface?)]
  [present-agent-empty-state
   (-> symbol? odra-agent-local-surface?)]
  [present-agent-diagnostic
   (-> symbol? any/c odra-agent-local-surface?)]
  [start-local-agent-task!
   (->* (odra-agent-continuity-store? odra-agent-catalog?
         odra-agent-control-candidate? (or/c symbol? string?) any/c
         (or/c symbol? string?) exact-nonnegative-integer?)
        (#:context-references list?)
        (or/c odra-agent-task? odra-agent-control-denial?))]
  [send-local-agent-interaction!
   (-> odra-agent-continuity-store? odra-agent-control-candidate?
       (or/c symbol? string?) string? (or/c symbol? string?)
       exact-nonnegative-integer?
       (or/c odra-agent-interaction? odra-agent-control-denial?))]))

(define minimum-agent-surface-width 24)
(define maximum-agent-surface-rows 256)

(struct odra-agent-surface-row
  (identity label state content attention? actions)
  #:transparent)

(struct odra-agent-local-surface
  (kind title status headline rows actions diagnostic)
  #:transparent)

(define (bounded-list values limit)
  (if (> (length values) limit) (take values limit) values))

(define (safe-character character)
  (if (or (char<? character #\space)
          (= (char->integer character) 127))
      #\space
      character))

(define (safe-text value)
  (define text (if (string? value) value (format "~s" value)))
  (string->immutable-string
   (list->string (map safe-character (string->list text)))))

(define (fit-text value width)
  (define text (safe-text value))
  (cond
    [(<= (string-length text) width) text]
    [(<= width 3) (substring text 0 width)]
    [else (string-append (substring text 0 (- width 3)) "...")]))

(define (validated-width who width)
  (unless (>= width minimum-agent-surface-width)
    (raise-arguments-error
     who "surface width is below 24 columns" "width" width))
  width)

(define (human-state state)
  (string-titlecase
   (string-replace (symbol->string state) "-" " ")))

(define (candidate-row candidate width)
  (define state (human-state (odra-agent-control-candidate-state candidate)))
  (define prefix (string-append state " - "))
  (odra-agent-surface-row
   (odra-agent-control-candidate-identity candidate)
   (fit-text (odra-agent-control-candidate-label candidate) width)
   (odra-agent-control-candidate-state candidate)
   (fit-text
    (string-append prefix (odra-agent-control-candidate-summary candidate))
    width)
   (memq (odra-agent-control-candidate-state candidate)
         '(blocked cancelling failed needs-human-decision outcome-unknown
                   reconciling rejected revoked unavailable waiting))
   (append (odra-agent-control-candidate-actions candidate) '())))

(define (empty-guidance command)
  (case command
    [(agent-list agent-describe agent-task-start)
     "No agents are available. Activate an agent package or inspect package status."]
    [(agent-task-list agent-task-open agent-send)
     "No tasks exist. Run agent-task-start to create one."]
    [(agent-request-list agent-request-decide)
     "No capability requests require attention."]
    [(agent-grant)
     "No capabilities are available for a grant."]
    [(agent-revoke)
     "No active grants can be revoked."]
    [(agent-cancel)
     "No running task, turn, or operation can be cancelled."]
    [(agent-audit)
     "No audit events have been recorded."]
    [else "No matching substrate records were found."]))

(define (present-agent-empty-state command)
  (odra-agent-local-surface
   'empty (human-state command) 'empty
   (empty-guidance command) '() '(back) #f))

(define (present-agent-candidates command candidates #:width [width 80])
  (validated-width 'present-agent-candidates width)
  (cond
    [(null? candidates) (present-agent-empty-state command)]
    [else
     (odra-agent-local-surface
      'candidates (human-state command) 'ready
      (format "~a matching item~a"
              (length candidates) (if (= (length candidates) 1) "" "s"))
      (for/list
          ([candidate
            (in-list (bounded-list candidates maximum-agent-surface-rows))])
        (candidate-row candidate width))
      '(move select inspect cancel) #f)]))

(define (visible-interaction? interaction)
  (memq (odra-agent-interaction-visibility interaction)
        '(local-user participants sender-recipient)))

(define (interaction-row interaction width)
  (define label
    (format "~a - ~a"
            (human-state (odra-agent-interaction-kind interaction))
            (odra-agent-interaction-sender interaction)))
  (odra-agent-surface-row
   (odra-agent-interaction-identity interaction)
   (fit-text label width)
   (odra-agent-interaction-kind interaction)
   (fit-text (odra-agent-interaction-payload interaction) width)
   (memq (odra-agent-interaction-kind interaction)
         '(failure question request))
   '(inspect)))

(define (present-agent-task store identity #:width [width 80] #:limit [limit 64])
  (validated-width 'present-agent-task width)
  (unless (<= limit maximum-agent-surface-rows)
    (raise-arguments-error
     'present-agent-task "row limit exceeds 256" "limit" limit))
  (define task (inspect-agent-task store identity))
  (cond
    [(not task)
     (odra-agent-local-surface
      'diagnostic "Agent Task" 'unavailable
      "The selected task no longer exists." '() '(back task-list)
      "Return to agent-task-list and choose a current task.")]
    [else
     (define interactions
       (filter visible-interaction?
               (inspect-agent-task-interactions store identity)))
     (odra-agent-local-surface
      'task
      (fit-text (odra-agent-task-objective task) width)
      (odra-agent-task-state task)
      (fit-text
       (format "~a - ~a"
               (human-state (odra-agent-task-state task))
               (or (odra-agent-task-owner-agent task) "No agent"))
       width)
      (for/list
          ([interaction
            (in-list
             (bounded-list interactions limit))])
        (interaction-row interaction width))
      (if (memq (odra-agent-task-state task) '(cancelled failed succeeded))
          '(inspect back)
          '(send cancel inspect back))
      (and (odra-agent-task-pending-decision-id task)
           "A capability request requires a decision."))]))

(define (detail-row entry width)
  (define key (human-state (car entry)))
  (odra-agent-surface-row
   (symbol->string (car entry)) key 'detail
   (fit-text (format "~a: ~s" key (cdr entry)) width)
   #f '()))

(define (present-agent-detail record #:width [width 80])
  (validated-width 'present-agent-detail width)
  (odra-agent-local-surface
   'detail
   (fit-text (odra-agent-inspection-projection-label record) width)
   (odra-agent-inspection-projection-state record)
   (fit-text (odra-agent-inspection-projection-summary record) width)
   (for/list
       ([entry
         (in-list
          (bounded-list
           (odra-agent-inspection-projection-details record)
           maximum-agent-surface-rows))])
     (detail-row entry width))
   '(follow-relation copy-identity back) #f))

(define (denial-fields value)
  (cond
    [(odra-agent-control-denial? value)
     (values (odra-agent-control-denial-code value)
             (odra-agent-control-denial-safe-detail value))]
    [(odra-agent-continuity-denial? value)
     (values (odra-agent-continuity-denial-code value)
             (odra-agent-continuity-denial-safe-detail value))]
    [(odra-agent-admission-denial? value)
     (values (odra-agent-admission-denial-code value)
             (odra-agent-admission-denial-safe-detail value))]
    [(odra-agent-authority-denial? value)
     (values (odra-agent-authority-denial-code value)
             (odra-agent-authority-denial-detail value))]
    [(odra-agent-driver-denial? value)
     (values (odra-agent-driver-denial-code value)
             (odra-agent-driver-denial-safe-detail value))]
    [(odra-agent-execution-denial? value)
     (values (odra-agent-execution-denial-code value)
             (odra-agent-execution-denial-safe-detail value))]
    [else (values 'unavailable "The requested operation is unavailable.")]))

(define (diagnostic-action code)
  (case code
    [(stale-selection stale-task stale-turn stale-attempt)
     "Refresh the list and select the current item."]
    [(absent-task absent-request unknown-attempt unknown-turn)
     "Return to the related list and choose an available item."]
    [(inactive-grant authority-denied revoked)
     "Inspect effective authority before trying the operation again."]
    [(task-limit interaction-limit grant-limit)
     "Finish or remove retained work before creating more."]
    [else "Inspect the related record for current state and available actions."]))

(define (present-agent-diagnostic operation value)
  (define-values (code detail) (denial-fields value))
  (odra-agent-local-surface
   'diagnostic (human-state operation) 'failed
   (safe-text detail) '() '(inspect back)
   (diagnostic-action code)))

(define (start-local-agent-task!
         store catalog candidate task-id objective actor now
         #:context-references [context-references '()])
  (cond
    [(or (not (eq? (odra-agent-control-candidate-command candidate)
                   'agent-task-start))
         (not (eq? (odra-agent-control-candidate-kind candidate) 'agent)))
     (odra-agent-control-denial
      'invalid-selection "Select one agent from agent-task-start.")]
    [(not (eq? (odra-agent-control-candidate-state candidate) 'available))
     (odra-agent-control-denial
      'unavailable-agent "The selected agent is unavailable.")]
    [else
     (define current
       (agent-catalog-agent-by-identity
        catalog (odra-agent-control-candidate-identity candidate)))
     (cond
       [(or (not current)
            (not
             (=
              (odra-agent-control-candidate-generation candidate)
              (odra-agent-definition-projection-definition-generation current))))
        (odra-agent-control-denial
         'stale-selection "Refresh agent-list and select the current agent.")]
       [else
        (create-agent-task!
         store task-id objective
         (make-agent-task-origin 'local-user actor) now
         #:owner-agent (odra-agent-control-candidate-identity candidate)
         #:owner-references context-references)])]))

(define (send-local-agent-interaction!
         store candidate interaction-id text actor now)
  (cond
    [(or (not (eq? (odra-agent-control-candidate-command candidate)
                   'agent-send))
         (not (eq? (odra-agent-control-candidate-kind candidate) 'task)))
     (odra-agent-control-denial
      'invalid-selection "Select one task from agent-send.")]
    [else
     (define task
       (inspect-agent-task store
                           (odra-agent-control-candidate-identity candidate)))
     (cond
       [(not task)
        (odra-agent-control-denial
         'stale-selection "The selected task no longer exists.")]
       [(not (= (odra-agent-control-candidate-generation candidate)
                (odra-agent-task-generation task)))
        (odra-agent-control-denial
         'stale-selection "Refresh agent-task-list and select the current task.")]
       [(memq (odra-agent-task-state task) '(cancelled failed succeeded))
        (odra-agent-control-denial
         'terminal-task "The selected task is already complete.")]
       [(not (odra-agent-task-owner-agent task))
        (odra-agent-control-denial
         'unavailable-agent "The selected task has no active agent owner.")]
       [else
        (record-agent-interaction!
         store interaction-id (odra-agent-task-identity task)
         actor (odra-agent-task-owner-agent task) 'request text 'local-user
         (make-agent-interaction-provenance 'local-user actor) now)])]))
