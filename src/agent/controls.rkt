#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require file/sha1
         racket/contract/base
         racket/list
         racket/string
         "admission.rkt"
         "audit.rkt"
         "authority.rkt"
         "continuity.rkt"
         "driver.rkt"
         "execution.rkt"
         "inspection.rkt"
         "registry.rkt")

(provide
 agent-control-command-identities
 maximum-agent-control-candidates
 (struct-out odra-agent-control-candidate)
 (struct-out odra-agent-control-denial)
 (struct-out odra-agent-control-outcome)
 (contract-out
  [agent-control-candidates
   (->* (odra-agent-continuity-store? odra-agent-authority-store?
         odra-agent-catalog? odra-agent-driver-registry? symbol?)
        (#:query string? #:at exact-nonnegative-integer?
         #:limit exact-positive-integer?)
        (listof odra-agent-control-candidate?))]
  [control-grant-agent-capability!
   (-> odra-agent-authority-store? odra-agent-catalog?
       odra-agent-control-candidate? odra-agent-grant-request?
       odra-agent-authority-policy? exact-nonnegative-integer?
       (or/c odra-agent-control-outcome? odra-agent-control-denial?))]
  [control-decide-agent-request!
   (-> odra-agent-continuity-store? odra-agent-authority-store?
       odra-agent-catalog? odra-agent-target-registry?
       odra-agent-driver-registry? odra-agent-control-candidate?
       (or/c symbol? string?) (or/c symbol? string?) (or/c symbol? string?)
       symbol? odra-agent-admission-policy? exact-nonnegative-integer?
       exact-positive-integer?
       (or/c odra-agent-control-outcome? odra-agent-control-denial?))]
  [control-revoke-agent-grant!
   (-> odra-agent-authority-store? odra-agent-control-candidate? string?
       exact-nonnegative-integer?
       (or/c odra-agent-control-outcome? odra-agent-control-denial?))]
  [control-cancel-agent-work!
   (-> odra-agent-continuity-store? odra-agent-driver-registry?
       odra-agent-control-candidate? (or/c symbol? string?) string?
       exact-nonnegative-integer?
       (or/c odra-agent-control-outcome? odra-agent-control-denial?))]
  [control-acknowledge-agent-uncertainty!
   (-> odra-agent-continuity-store? odra-agent-control-candidate?
       (or/c symbol? string?) exact-nonnegative-integer?
       (or/c odra-agent-control-outcome? odra-agent-control-denial?))]))

(define agent-control-command-identities
  '(agent-list agent-describe agent-task-start agent-task-list agent-task-open
               agent-send agent-request-list agent-request-decide agent-grant
               agent-revoke agent-cancel agent-inspect agent-audit))

(define maximum-agent-control-candidates 256)

(struct odra-agent-control-candidate
  (command kind identity generation label state summary actions)
  #:transparent)

(struct odra-agent-control-denial (code safe-detail) #:transparent)

(struct odra-agent-control-outcome (action target state value) #:transparent)

(define (denial code detail)
  (odra-agent-control-denial code (string->immutable-string detail)))

(define (command-kind command)
  (case command
    [(agent-list agent-describe agent-task-start) '(agent)]
    [(agent-task-list agent-task-open agent-send) '(task)]
    [(agent-request-list agent-request-decide) '(request)]
    [(agent-grant) '(capability)]
    [(agent-revoke) '(grant)]
    [(agent-cancel) '(attempt result task turn)]
    [(agent-audit) '(audit)]
    [(agent-inspect)
     '(agent attempt audit capability decision driver driver-session grant
             interaction reconciliation request result task turn)]
    [else #f]))

(define (command-actions command record)
  (case command
    [(agent-list agent-describe agent-task-list agent-task-open
                 agent-request-list agent-audit agent-inspect)
     '(inspect)]
    [(agent-task-start) '(start)]
    [(agent-send) '(send)]
    [(agent-grant) '(grant)]
    [(agent-revoke) '(revoke)]
    [(agent-request-decide) '(approve-once reject cancel-task)]
    [(agent-cancel)
     (if (and
          (eq? (odra-agent-inspection-projection-kind record) 'result)
          (eq? (odra-agent-inspection-projection-state record)
               'outcome-unknown))
         '(acknowledge-uncertainty)
         '(cancel))]
    [else '()]))

(define (record-search-text record)
  (string-downcase
   (string-append
    (odra-agent-inspection-projection-label record) " "
    (odra-agent-inspection-projection-identity record) " "
    (odra-agent-inspection-projection-summary record))))

(define (candidate-visible? record query)
  (or (string=? query "")
      (string-contains? (record-search-text record) (string-downcase query))))

(define (command-record-visible? command record)
  (define kind (odra-agent-inspection-projection-kind record))
  (define state (odra-agent-inspection-projection-state record))
  (and
   (memq kind (command-kind command))
   (case command
     [(agent-request-decide) (memq state '(needs-human-decision pending))]
     [(agent-revoke) (eq? state 'active)]
     [(agent-cancel)
      (not (memq state
                 '(cancelled closed completed failed recorded rejected revoked
                             succeeded timed-out)))]
     [else #t])))

(define (agent-control-candidates
         store authority-store catalog driver-registry command
         #:query [query ""] #:at [at 0] #:limit [limit 64])
  (unless (memq command agent-control-command-identities)
    (raise-arguments-error
     'agent-control-candidates "unknown agent command" "command" command))
  (unless (<= limit maximum-agent-control-candidates)
    (raise-arguments-error
     'agent-control-candidates "candidate limit exceeds 256" "limit" limit))
  (define matches
    (filter
     (lambda (record)
       (and (command-record-visible? command record)
            (candidate-visible? record query)))
     (inspect-agent-substrate-records
      store authority-store catalog driver-registry
      #:at at #:limit maximum-agent-inspection-records)))
  (for/list ([record (in-list (if (> (length matches) limit)
                                 (take matches limit)
                                 matches))])
    (odra-agent-control-candidate
     command
     (odra-agent-inspection-projection-kind record)
     (odra-agent-inspection-projection-identity record)
     (odra-agent-inspection-projection-generation record)
     (odra-agent-inspection-projection-label record)
     (odra-agent-inspection-projection-state record)
     (odra-agent-inspection-projection-summary record)
     (command-actions command record))))

(define (candidate-for? candidate command kind action)
  (and (eq? command (odra-agent-control-candidate-command candidate))
       (eq? kind (odra-agent-control-candidate-kind candidate))
       (memq action (odra-agent-control-candidate-actions candidate))))

(define (control-grant-agent-capability!
         authority-store catalog candidate request policy now)
  (cond
    [(not (candidate-for? candidate 'agent-grant 'capability 'grant))
     (denial 'invalid-selection "Select one capability from agent-grant.")]
    [(not
      (string=?
       (odra-agent-control-candidate-identity candidate)
       (odra-agent-grant-request-capability-pattern request)))
     (denial 'stale-selection
             "The selected capability no longer matches the grant request.")]
    [else
     (define result
       (grant-agent-capability! authority-store catalog request policy now))
     (if (odra-agent-authority-denial? result)
         (denial
          (odra-agent-authority-denial-code result)
          (odra-agent-authority-denial-detail result))
         (odra-agent-control-outcome
          'grant (odra-agent-control-candidate-identity candidate)
          'granted result))]))

(define (control-decide-agent-request!
         store authority-store catalog target-registry driver-registry
         candidate human-decision-id admission-decision-id actor value policy
         now valid-until)
  (cond
    [(not (candidate-for?
           candidate 'agent-request-decide 'request value))
     (denial 'invalid-selection
             "Select one pending request and one available decision.")]
    [else
     (define current
       (inspect-agent-substrate-detail
        store authority-store catalog driver-registry 'request
        (odra-agent-control-candidate-identity candidate) #:at now))
     (cond
       [(or
         (not current)
         (not (memq (odra-agent-inspection-projection-state current)
                    '(needs-human-decision pending))))
        (denial 'stale-selection "The selected request is no longer pending.")]
       [else
        (define recorded
          (record-agent-human-decision!
           store (odra-agent-control-candidate-identity candidate)
           human-decision-id actor value policy now valid-until))
        (cond
          [(odra-agent-admission-denial? recorded)
           (denial
            (odra-agent-admission-denial-code recorded)
            (odra-agent-admission-denial-safe-detail recorded))]
          [else
           (define decided
             (decide-agent-capability-request!
              store authority-store catalog target-registry
              (odra-agent-control-candidate-identity candidate)
              admission-decision-id policy now))
           (cond
             [(odra-agent-admission-denial? decided)
              (denial
               (odra-agent-admission-denial-code decided)
               (odra-agent-admission-denial-safe-detail decided))]
             [else
              (when (eq? value 'cancel-task)
                (define request
                  (inspect-agent-capability-request
                   store (odra-agent-control-candidate-identity candidate)))
                (define task
                  (inspect-agent-task
                   store (odra-agent-capability-request-task-id request)))
                (when task
                  (cancel-agent-task!
                   store (odra-agent-task-identity task)
                   (odra-agent-task-generation task) actor
                   "The user cancelled the task while deciding its request."
                   now)))
              (odra-agent-control-outcome
               value (odra-agent-control-candidate-identity candidate)
               (odra-agent-admission-decision-state decided) decided)])])])]))

(define (control-revoke-agent-grant! authority-store candidate reason now)
  (cond
    [(not (candidate-for? candidate 'agent-revoke 'grant 'revoke))
     (denial 'invalid-selection "Select one active grant from agent-revoke.")]
    [else
     (define result
       (revoke-agent-capability-grant!
        authority-store
        (odra-agent-control-candidate-identity candidate)
        (odra-agent-control-candidate-generation candidate)
        reason now))
     (if (odra-agent-authority-denial? result)
         (denial
          (odra-agent-authority-denial-code result)
          (odra-agent-authority-denial-detail result))
         (odra-agent-control-outcome
          'revoke (odra-agent-control-candidate-identity candidate)
          'revoked result))]))

(define (control-cancel-agent-work!
         store driver-registry candidate actor reason now)
  (cond
    [(not (memq 'cancel (odra-agent-control-candidate-actions candidate)))
     (denial 'invalid-selection "Select one cancellable task, turn, or attempt.")]
    [else
     (define result
       (case (odra-agent-control-candidate-kind candidate)
         [(task)
          (cancel-agent-task!
           store (odra-agent-control-candidate-identity candidate)
           (odra-agent-control-candidate-generation candidate)
           actor reason now)]
         [(turn)
          (cancel-agent-turn!
           store driver-registry
           (odra-agent-control-candidate-identity candidate)
           (odra-agent-control-candidate-generation candidate) now)]
         [(attempt)
          (request-agent-capability-cancellation!
           store (odra-agent-control-candidate-identity candidate)
           (odra-agent-control-candidate-generation candidate)
           actor reason now)]
         [else #f]))
     (if (or (not result)
             (odra-agent-continuity-denial? result)
             (odra-agent-driver-denial? result)
             (odra-agent-execution-denial? result))
         (denial 'stale-selection
                 "The selected work can no longer be cancelled.")
         (odra-agent-control-outcome
          'cancel (odra-agent-control-candidate-identity candidate)
          'cancelled result))]))

(define (control-acknowledge-agent-uncertainty! store candidate actor now)
  (cond
    [(not
      (and
       (eq? (odra-agent-control-candidate-kind candidate) 'result)
       (eq? (odra-agent-control-candidate-state candidate) 'outcome-unknown)
       (memq 'acknowledge-uncertainty
             (odra-agent-control-candidate-actions candidate))))
     (denial 'invalid-selection
             "Select one uncertain result before acknowledging it.")]
    [else
     (define result
       (inspect-agent-operation-result
        store (odra-agent-control-candidate-identity candidate)))
     (cond
       [(or (not result)
            (not (eq? (odra-agent-operation-result-state result)
                      'outcome-unknown)))
        (denial 'stale-selection "The selected result is no longer uncertain.")]
       [else
        (define event
          (record-agent-audit-event!
           store
           (string-append
            "audit.uncertainty."
            (sha1
             (open-input-string
              (format "~a:~a"
                      (odra-agent-control-candidate-identity candidate) now))))
           'uncertainty-acknowledged actor
           (list 'result (odra-agent-control-candidate-identity candidate)
                 'state 'outcome-unknown)
           now
           #:visibility 'local-user
           #:redaction-class 'identity-only))
        (if (odra-agent-audit-denial? event)
            (denial
             (odra-agent-audit-denial-code event)
             (odra-agent-audit-denial-safe-detail event))
            (odra-agent-control-outcome
             'acknowledge-uncertainty
             (odra-agent-control-candidate-identity candidate)
             'outcome-unknown event))])]))
