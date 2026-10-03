#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/list
         racket/string)

(define workflow-path "src/ksawery_module/ksawery_workflow.odin")
(define workflow-source (file->string workflow-path))

(define failures '())

(define (record-failure! message)
  (set! failures (cons message failures)))

(define (check-occurrences label source pattern expected)
  (define actual (length (regexp-match* pattern source)))
  (unless (= actual expected)
    (record-failure!
     (format "~a: expected ~a occurrence(s), found ~a" label expected actual))))

(define family-cases
  '("case .None, .Conflict_Assistance, .Extension_Operation:"
    "case .Raw_Command:"
    "case .Observe, .Refresh:"
    "case .History_Observe, .History_Refresh, .History_Next:"
    "case .Commit_Precondition, .Commit:"))

(for ([family-case (in-list family-cases)])
  (unless (string-contains? workflow-source family-case)
    (record-failure! (format "pending-family classifier is missing ~s" family-case))))

(check-occurrences
 "repository process polling owner"
 workflow-source
 #rx"ksawery[.]repository_process_poll[(]"
 1)
(check-occurrences
 "top-level single-poll call"
 workflow-source
 #rx"poll, polled := ksawery_workflow_poll_once[(]"
 1)
(check-occurrences
 "terminal poll classification"
 workflow-source
 #rx"if !polled [|][|] !ksawery_workflow_poll_is_terminal[(]poll[)]"
 1)
(check-occurrences
 "raw-command family completion dispatch"
 workflow-source
 #rx"candidate, completed := ksawery_workflow_complete_raw_command[(]"
 1)
(check-occurrences
 "repository-observation family completion dispatch"
 workflow-source
 #rx"candidate, completed := ksawery_workflow_complete_repository_observation[(]"
 1)
(check-occurrences
 "changes-and-index family completion dispatch"
 workflow-source
 #rx"candidate, completed := ksawery_workflow_complete_changes_and_index[(]"
 1)
(check-occurrences
 "commit family completion dispatch"
 workflow-source
 #rx"candidate, completed := ksawery_workflow_complete_commit[(]"
 1)
(check-occurrences
 "history family completion dispatch"
 workflow-source
 #rx"candidate, completed := ksawery_workflow_complete_history[(]"
 1)
(check-occurrences
 "revision-inspection family completion dispatch"
 workflow-source
 #rx"candidate, completed := ksawery_workflow_complete_revision_inspection[(]"
 1)
(check-occurrences
 "refs family completion dispatch"
 workflow-source
 #rx"candidate, completed := ksawery_workflow_complete_refs[(]"
 1)
(check-occurrences
 "synchronization family completion dispatch"
 workflow-source
 #rx"candidate, completed := ksawery_workflow_complete_synchronization[(]"
 1)
(check-occurrences
 "sequence family completion dispatch"
 workflow-source
 #rx"candidate, completed := ksawery_workflow_complete_sequence[(]"
 1)
(check-occurrences
 "common family outcome publication"
 workflow-source
 #rx"published := ksawery_workflow_publish_completion[(]"
 1)
(check-occurrences
 "local-child advancement"
 workflow-source
 #rx"local_changed, local_owned_turn := ksawery_workflow_advance_local_children[(]"
 1)
(check-occurrences
 "exhaustive family selection"
 workflow-source
 #rx"ksawery_workflow_complete_family[(]commands, family, poll, &outcome[)]"
 1)

(define workflow-step-tail
  (last (regexp-split #rx"ksawery_workflow_step :: proc" workflow-source)))
(define workflow-step-source
  (first (regexp-split #rx"ksawery_workflow_selected_path :: proc" workflow-step-tail)))
(define extracted-result-readers
  '("repository_process_take_path_detail"
    "repository_process_take_index_action"
    "repository_process_take_partial_index_action"
    "repository_process_take_grouped_index_action"
    "repository_process_take_discard_action"
    "repository_process_take_commit_precondition"
    "repository_process_take_commit("
    "repository_process_take_history"
    "repository_process_revision_output"
    "repository_process_take_refs"
    "repository_process_take_remote_configuration"
    "repository_process_take_fetch"
    "repository_process_take_push_configuration"
    "repository_process_take_push"
    "repository_process_take_branch"
    "repository_process_take_tag"
    "repository_process_take_merge_precondition"
    "repository_process_take_rebase_precondition"
    "repository_process_take_revision_sequence_precondition"
    "repository_process_take_bisect_precondition"
    "repository_process_take_conflict_resolution_precondition"
    "repository_process_take_merge"
    "repository_process_take_rebase"
    "repository_process_take_cherry_pick"
    "repository_process_take_revert"
    "repository_process_take_bisect"
    "repository_process_take_conflict_resolution"
    "repository_process_take_sequence"))

(for ([reader (in-list extracted-result-readers)])
  (when (string-contains? workflow-step-source reader)
    (record-failure! (format "top-level workflow still decodes extracted result: ~a" reader))))

(define forbidden-top-level-details
  '("repository_process_close"
    "command_context_set_diagnostic"
    "commit_refresh"
    "fetch_refresh"
    "push_refresh"
    "branch_refresh"
    "tag_refresh"
    "sequence_mutation_refresh"))

(for ([detail (in-list forbidden-top-level-details)])
  (when (string-contains? workflow-step-source detail)
    (record-failure! (format "top-level workflow still owns feature completion: ~a" detail))))

(check-occurrences
 "top-level family classification"
 workflow-step-source
 #rx"ksawery_workflow_pending_family[(]"
 1)
(check-occurrences
 "top-level common publication"
 workflow-step-source
 #rx"ksawery_workflow_publish_completion[(]"
 1)

(define local-child-source
  (first
   (regexp-split
    #rx"ksawery_workflow_coordination_failure_outcome :: proc"
    (last (regexp-split #rx"ksawery_workflow_advance_local_children :: proc" workflow-source)))))
(when (string-contains? local-child-source "repository_process_poll")
  (record-failure! "local-child advancement directly polls the repository process"))

(unless (null? failures)
  (for-each displayln (reverse failures))
  (exit 1))

(printf "Checked Ksawery pending families, single polling, and extracted-family completion publication.\n")
