// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package package_catalog_interaction

/* Workflow owns only copied coordination state and bounded candidates. */
Workflow :: struct {
	current:         Snapshot,
	candidates:      Candidate_List,
	next_generation: u64,
}

/* workflow_begin starts one semantic operation through a shared surface. */
workflow_begin :: proc(
	workflow: ^Workflow,
	operation: Operation,
	availability: Availability,
) -> (Snapshot, bool, Failure) {
	if workflow == nil || operation == .Invalid {
		return {}, false, Failure{code = .Invalid_Request, operation = operation}
	}
	if snapshot_active(workflow.current) {
		return workflow.current, false, Failure{
			code = .Busy,
			operation = workflow.current.operation,
			generation = workflow.current.generation,
		}
	}
	generation := workflow.next_generation
	if generation == 0 do generation = 1
	if generation == max(u64) {
		return workflow.current, false, Failure{code = .Limit, operation = operation}
	}
	workflow.next_generation = generation + 1
	workflow.candidates = {}
	if !availability.available {
		reason := availability.reason
		recovery := availability.recovery
		if len(text_string(&reason)) == 0 || len(text_string(&recovery)) == 0 {
			return workflow.current, false, Failure{code = .Invalid_Text, operation = operation}
		}
		workflow.current = Snapshot{
			generation = generation,
			operation = operation,
			phase = .Failed,
			failure = reason,
			recovery = recovery,
		}
		return workflow.current, true, Failure{
			code = .Unavailable,
			operation = operation,
			generation = generation,
		}
	}
	phase := Phase.Requesting
	surface := Surface.Progress
	if operation == .Catalog_Add || operation == .Catalog_Search ||
	   operation == .Manual_Acquire || operation == .Package_Discover ||
	   operation == .Package_Describe || operation == .Package_Install ||
	   operation == .Package_Enable || operation == .Package_Disable ||
	   operation == .Package_Update || operation == .Package_Rollback ||
	   operation == .Package_Remove {
		phase = .Prompting
		surface = .Prompt
	}
	workflow.current = Snapshot{
		generation = generation,
		operation = operation,
		phase = phase,
		surface = surface,
		cancellable = true,
	}
	return workflow.current, true, {}
}

/* workflow_submit_prompt transfers copied prompt input to the native owner. */
workflow_submit_prompt :: proc(
	workflow: ^Workflow,
	generation: u64,
) -> (Snapshot, bool, Failure) {
	current, valid, failure := workflow_transition(workflow, generation)
	if !valid do return current, false, failure
	if current.phase != .Prompting {
		return current, false, invalid_transition(current)
	}
	current.phase = .Requesting
	current.surface = .Progress
	workflow.current = current
	return current, true, {}
}

/* workflow_publish_candidates copies one generation before presenting it. */
workflow_publish_candidates :: proc(
	workflow: ^Workflow,
	generation, candidate_generation: u64,
	values: []Candidate,
) -> (Snapshot, bool, Failure) {
	current, valid, failure := workflow_transition(workflow, generation)
	if !valid do return current, false, failure
	if current.phase != .Requesting || candidate_generation == 0 ||
	   len(values) == 0 || len(values) > MAX_CANDIDATES {
		return current, false, Failure{
			code = .Limit,
			operation = current.operation,
			generation = generation,
		}
	}
	copied := Candidate_List{generation = candidate_generation, count = u16(len(values))}
	for candidate_value, index in values {
		candidate_id := candidate_value.id
		if len(text_string(&candidate_id)) == 0 || candidate_value.kind == .Invalid {
			return current, false, Failure{
				code = .Invalid_Request,
				operation = current.operation,
				generation = generation,
			}
		}
		copied.values[index] = candidate_value
	}
	workflow.candidates = copied
	current.phase = .Selecting
	current.surface = .Candidates
	current.return_surface = .Candidates
	current.selection_valid = false
	workflow.current = current
	return current, true, {}
}

/* workflow_select binds one action to exact workflow and candidate generations. */
workflow_select :: proc(
	workflow: ^Workflow,
	generation, candidate_generation: u64,
	index: int,
) -> (Snapshot, bool, Failure) {
	current, valid, failure := workflow_transition(workflow, generation)
	if !valid do return current, false, failure
	if current.phase != .Selecting {
		return current, false, invalid_transition(current)
	}
	if candidate_generation == 0 || candidate_generation != workflow.candidates.generation {
		return current, false, Failure{
			code = .Stale_Candidates,
			operation = current.operation,
			generation = generation,
		}
	}
	if index < 0 || index >= int(workflow.candidates.count) {
		return current, false, Failure{
			code = .Invalid_Request,
			operation = current.operation,
			generation = generation,
		}
	}
	selected := workflow.candidates.values[index]
	current.selected_index = u16(index)
	current.selection_valid = true
	if operation_requires_confirmation(current.operation) {
		current.phase = .Confirming
		current.surface = .Confirmation
		current.confirmation = Confirmation{
			workflow_generation = generation,
			operation = current.operation,
			candidate_id = selected.id,
			record_generation = selected.record_generation,
			catalog_generation = selected.catalog_generation,
			snapshot_id = selected.snapshot_id,
		}
	} else {
		current.phase = .Inspecting
		current.surface = .Progress
	}
	workflow.current = current
	return current, true, {}
}

/* workflow_confirm accepts only the exact retained confirmation projection. */
workflow_confirm :: proc(
	workflow: ^Workflow,
	confirmation: Confirmation,
) -> (Snapshot, bool, Failure) {
	current, valid, failure := workflow_transition(workflow, confirmation.workflow_generation)
	if !valid do return current, false, failure
	if current.phase != .Confirming || !confirmation_equal(current.confirmation, confirmation) {
		return current, false, Failure{
			code = .Stale_Confirmation,
			operation = current.operation,
			generation = current.generation,
		}
	}
	current.phase = .Applying
	current.surface = .Progress
	workflow.current = current
	return current, true, {}
}

/* workflow_publish_inspection retains independent trust and lifecycle facts. */
workflow_publish_inspection :: proc(
	workflow: ^Workflow,
	generation: u64,
	value: Inspection,
) -> (Snapshot, bool, Failure) {
	current, valid, failure := workflow_transition(workflow, generation)
	if !valid do return current, false, failure
	if current.phase != .Requesting && current.phase != .Inspecting {
		return current, false, invalid_transition(current)
	}
	subject_id := value.subject_id
	if len(text_string(&subject_id)) == 0 {
		return current, false, Failure{
			code = .Invalid_Request,
			operation = current.operation,
			generation = generation,
		}
	}
	current.inspection = value
	current.phase = .Completed
	current.surface = .Results
	current.cancellable = false
	workflow.current = current
	return current, true, {}
}

/* workflow_return restores the retained candidate surface after inspection. */
workflow_return :: proc(
	workflow: ^Workflow,
	generation, candidate_generation: u64,
) -> (Snapshot, bool, Failure) {
	current, valid, failure := workflow_transition(workflow, generation)
	if !valid do return current, false, failure
	if current.phase != .Completed || current.return_surface != .Candidates ||
	   workflow.candidates.generation != candidate_generation {
		return current, false, Failure{
			code = .Stale_Candidates,
			operation = current.operation,
			generation = generation,
		}
	}
	current.phase = .Selecting
	current.surface = .Candidates
	current.cancellable = true
	current.inspection = {}
	workflow.current = current
	return current, true, {}
}

/* workflow_progress records monotonic asynchronous progress. */
workflow_progress :: proc(
	workflow: ^Workflow,
	generation, progress, total: u64,
	message: string,
) -> (Snapshot, bool, Failure) {
	current, valid, failure := workflow_transition(workflow, generation)
	if !valid do return current, false, failure
	if (current.phase != .Requesting && current.phase != .Applying &&
	    current.phase != .Inspecting) || total == 0 || progress > total ||
	   progress < current.progress ||
	   (current.progress_total != 0 && total != current.progress_total) {
		return current, false, invalid_transition(current)
	}
	message_text, copied := text_copy(message)
	if !copied {
		return current, false, Failure{
			code = .Invalid_Text,
			operation = current.operation,
			generation = generation,
		}
	}
	current.progress = progress
	current.progress_total = total
	current.message = message_text
	workflow.current = current
	return current, true, {}
}

/* workflow_complete finishes requesting or applying work. */
workflow_complete :: proc(
	workflow: ^Workflow,
	generation: u64,
	message: string,
) -> (Snapshot, bool, Failure) {
	current, valid, failure := workflow_transition(workflow, generation)
	if !valid do return current, false, failure
	if current.phase != .Requesting && current.phase != .Applying &&
	   current.phase != .Inspecting {
		return current, false, invalid_transition(current)
	}
	message_text, copied := text_copy(message)
	if !copied {
		return current, false, Failure{
			code = .Invalid_Text,
			operation = current.operation,
			generation = generation,
		}
	}
	current.phase = .Completed
	current.surface = .Results
	current.cancellable = false
	current.message = message_text
	workflow.current = current
	return current, true, {}
}

/* workflow_fail retains bounded exact failure and recovery details. */
workflow_fail :: proc(
	workflow: ^Workflow,
	generation: u64,
	reason, recovery: string,
) -> (Snapshot, bool, Failure) {
	current, valid, failure := workflow_transition(workflow, generation)
	if !valid do return current, false, failure
	if !snapshot_active(current) do return current, false, invalid_transition(current)
	reason_text, reason_ok := text_copy(reason)
	recovery_text, recovery_ok := text_copy(recovery)
	if len(reason) == 0 || len(recovery) == 0 || !reason_ok || !recovery_ok {
		return current, false, Failure{
			code = .Invalid_Text,
			operation = current.operation,
			generation = generation,
		}
	}
	current.phase = .Failed
	current.surface = .Results
	current.cancellable = false
	current.failure = reason_text
	current.recovery = recovery_text
	workflow.current = current
	return current, true, {}
}

/* workflow_cancel invalidates active work without applying an operation. */
workflow_cancel :: proc(
	workflow: ^Workflow,
	generation: u64,
) -> (Snapshot, bool, Failure) {
	current, valid, failure := workflow_transition(workflow, generation)
	if !valid do return current, false, failure
	if !snapshot_active(current) || !current.cancellable {
		return current, false, invalid_transition(current)
	}
	current.phase = .Cancelled
	current.surface = .None
	current.cancellable = false
	current.progress = 0
	current.progress_total = 0
	current.message = {}
	workflow.current = current
	return current, true, {}
}

/* workflow_snapshot returns one copied current observation. */
workflow_snapshot :: proc(workflow: ^Workflow) -> (Snapshot, bool) {
	if workflow == nil || workflow.current.generation == 0 do return {}, false
	return workflow.current, true
}

/* workflow_candidates returns the retained copied candidate generation. */
workflow_candidates :: proc(workflow: ^Workflow) -> (Candidate_List, bool) {
	if workflow == nil || workflow.candidates.generation == 0 do return {}, false
	return workflow.candidates, true
}

/* workflow_reset releases all retained interaction data. */
workflow_reset :: proc(workflow: ^Workflow) {
	if workflow == nil do return
	next_generation := workflow.next_generation
	workflow^ = Workflow{next_generation = next_generation}
}

@(private)
workflow_transition :: proc(
	workflow: ^Workflow,
	generation: u64,
) -> (Snapshot, bool, Failure) {
	if workflow == nil || generation == 0 || workflow.current.generation == 0 {
		return {}, false, Failure{code = .Invalid_Request, generation = generation}
	}
	if workflow.current.generation != generation {
		return workflow.current, false, Failure{
			code = .Stale_Generation,
			operation = workflow.current.operation,
			generation = generation,
		}
	}
	return workflow.current, true, {}
}

@(private)
invalid_transition :: proc(snapshot: Snapshot) -> Failure {
	return {
		code = .Invalid_Transition,
		operation = snapshot.operation,
		generation = snapshot.generation,
	}
}

@(private)
operation_requires_confirmation :: proc(operation: Operation) -> bool {
	return operation == .Catalog_Add || operation == .Catalog_Disable ||
	       operation == .Catalog_Remove || operation == .Catalog_Refresh ||
	       operation == .Manual_Acquire || operation == .Package_Install ||
	       operation == .Package_Enable || operation == .Package_Disable ||
	       operation == .Package_Update || operation == .Package_Rollback ||
	       operation == .Package_Remove || operation == .Package_Cleanup
}

@(private)
confirmation_equal :: proc(left, right: Confirmation) -> bool {
	return left.workflow_generation == right.workflow_generation &&
	       left.operation == right.operation &&
	       text_equal(left.candidate_id, right.candidate_id) &&
	       left.record_generation == right.record_generation &&
	       left.catalog_generation == right.catalog_generation &&
	       text_equal(left.snapshot_id, right.snapshot_id)
}
