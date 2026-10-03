// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_interaction

/* Workflow retains only operation coordination and copied evidence. */
Workflow :: struct {
	current:         Snapshot,
	next_generation: u64,
}

@(private)
Operation_Profile :: struct {
	class:           Operation_Class,
	initial_phase:   Phase,
	initial_surface: Surface,
	factory_owned:   bool,
}

/* workflow_begin starts one exact operation or retains actionable unavailability. */
workflow_begin :: proc(
	workflow: ^Workflow,
	request: Begin_Request,
) -> (Snapshot, bool, Failure) {
	if workflow == nil || request.operation == .Invalid {
		return {}, false, Failure{code = .Invalid_Request, operation = request.operation}
	}
	if snapshot_active(workflow.current) {
		return workflow.current, false, Failure{
			code = .Busy,
			operation = workflow.current.operation,
			generation = workflow.current.generation,
		}
	}
	profile, profiled := operation_profile(request.operation)
	if !profiled {
		return workflow.current, false, Failure{code = .Invalid_Request, operation = request.operation}
	}
	generation := workflow.next_generation
	if generation == 0 do generation = 1
	if generation == max(u64) {
		return workflow.current, false, Failure{code = .Generation_Limit, operation = request.operation}
	}
	workflow.next_generation = generation + 1
	if !request.availability.available {
		reason := request.availability.reason
		recovery := request.availability.recovery
		if len(text_string(&reason)) == 0 || len(text_string(&recovery)) == 0 {
			return workflow.current, false, Failure{code = .Invalid_Text, operation = request.operation}
		}
		workflow.current = Snapshot {
			generation = generation,
			operation = request.operation,
			class = profile.class,
			phase = .Failed,
			health = .Failed,
			factory_owned = profile.factory_owned,
			failure = reason,
			recovery = recovery,
		}
		return workflow.current, true, Failure{
			code = .Unavailable,
			operation = request.operation,
			generation = generation,
		}
	}
	workflow.current = Snapshot {
		generation = generation,
		operation = request.operation,
		class = profile.class,
		phase = profile.initial_phase,
		surface = profile.initial_surface,
		health = .Busy,
		factory_owned = profile.factory_owned,
		cancellable = true,
	}
	return workflow.current, true, {}
}

/* workflow_submit advances a shared prompt or candidate selection. */
workflow_submit :: proc(
	workflow: ^Workflow,
	generation: u64,
) -> (Snapshot, bool, Failure) {
	current, valid, failure := workflow_transition_state(workflow, generation)
	if !valid do return current, false, failure
	#partial switch current.phase {
	case .Prompting:
		current.phase = .Requesting
		current.surface = .Progress
	case .Selecting:
		if operation_requires_confirmation(current.operation) {
			current.phase = .Confirming
			current.surface = .Confirmation
		} else {
			current.phase = .Requesting
			current.surface = .Progress
		}
	case:
		return current, false, Failure{code = .Invalid_Transition, operation = current.operation, generation = generation}
	}
	workflow.current = current
	return current, true, {}
}

/* workflow_publish routes one admitted result or proposal to its shared owner. */
workflow_publish :: proc(
	workflow: ^Workflow,
	generation: u64,
) -> (Snapshot, bool, Failure) {
	current, valid, failure := workflow_transition_state(workflow, generation)
	if !valid do return current, false, failure
	if current.phase != .Requesting {
		return current, false, Failure{code = .Invalid_Transition, operation = current.operation, generation = generation}
	}
	#partial switch current.operation {
	case .Show_Hover, .Signature_Help:
		current.phase = .Completed
		current.surface = .Popup
		current.health = .Idle
		current.cancellable = false
	case .Go_To_Definition, .Find_References:
		current.phase = .Completed
		current.surface = .Results
		current.health = .Idle
		current.cancellable = false
	case .Document_Symbols, .Workspace_Symbols, .Bundle_Search:
		current.phase = .Completed
		current.surface = .Candidates
		current.health = .Idle
		current.cancellable = false
	case .Rename, .Format_Buffer, .Format_Region, .Code_Actions:
		current.phase = .Previewing
		current.surface = .Preview
	case .Describe_Bundle, .Support_Doctor, .Bundle_List, .Bundle_Refresh_Catalogs:
		current.phase = .Completed
		current.surface = .Results
		current.health = .Idle
		current.cancellable = false
	case .Bundle_Install, .Bundle_Enable, .Bundle_Disable, .Bundle_Update,
	     .Bundle_Rollback, .Bundle_Remove:
		current.phase = .Confirming
		current.surface = .Confirmation
	case .Invalid:
		return current, false, Failure{code = .Invalid_Request, operation = current.operation, generation = generation}
	}
	workflow.current = current
	return current, true, {}
}

/* workflow_confirm transfers an admitted preview or confirmation to its native owner. */
workflow_confirm :: proc(
	workflow: ^Workflow,
	generation: u64,
) -> (Snapshot, bool, Failure) {
	current, valid, failure := workflow_transition_state(workflow, generation)
	if !valid do return current, false, failure
	if current.phase != .Previewing && current.phase != .Confirming {
		return current, false, Failure{code = .Invalid_Transition, operation = current.operation, generation = generation}
	}
	current.phase = .Applying
	current.surface = .Progress
	current.health = .Busy
	workflow.current = current
	return current, true, {}
}

/* workflow_progress updates bounded monotonic progress for requesting or applying work. */
workflow_progress :: proc(
	workflow: ^Workflow,
	generation, progress, total: u64,
	message: string,
) -> (Snapshot, bool, Failure) {
	current, valid, failure := workflow_transition_state(workflow, generation)
	if !valid do return current, false, failure
	if (current.phase != .Requesting && current.phase != .Applying) || total == 0 ||
	   progress > total || progress < current.progress ||
	   (current.progress_total != 0 && total != current.progress_total) {
		return current, false, Failure{code = .Invalid_Transition, operation = current.operation, generation = generation}
	}
	message_text, copied := text_copy(message)
	if !copied {
		return current, false, Failure{code = .Invalid_Text, operation = current.operation, generation = generation}
	}
	current.progress = progress
	current.progress_total = total
	current.message = message_text
	workflow.current = current
	return current, true, {}
}

/* workflow_complete finishes native application or lifecycle work. */
workflow_complete :: proc(
	workflow: ^Workflow,
	generation: u64,
	message: string,
) -> (Snapshot, bool, Failure) {
	current, valid, failure := workflow_transition_state(workflow, generation)
	if !valid do return current, false, failure
	if current.phase != .Requesting && current.phase != .Applying {
		return current, false, Failure{code = .Invalid_Transition, operation = current.operation, generation = generation}
	}
	message_text, copied := text_copy(message)
	if !copied {
		return current, false, Failure{code = .Invalid_Text, operation = current.operation, generation = generation}
	}
	current.phase = .Completed
	current.surface = .None
	current.health = .Idle
	current.cancellable = false
	current.message = message_text
	workflow.current = current
	return current, true, {}
}

/* workflow_fail contains one exact failure and recovery action. */
workflow_fail :: proc(
	workflow: ^Workflow,
	generation: u64,
	reason, recovery: string,
) -> (Snapshot, bool, Failure) {
	current, valid, failure := workflow_transition_state(workflow, generation)
	if !valid do return current, false, failure
	if !snapshot_active(current) {
		return current, false, Failure{code = .Invalid_Transition, operation = current.operation, generation = generation}
	}
	reason_text, reason_ok := text_copy(reason)
	recovery_text, recovery_ok := text_copy(recovery)
	if len(reason) == 0 || len(recovery) == 0 || !reason_ok || !recovery_ok {
		return current, false, Failure{code = .Invalid_Text, operation = current.operation, generation = generation}
	}
	current.phase = .Failed
	current.surface = .None
	current.health = .Failed
	current.cancellable = false
	current.failure = reason_text
	current.recovery = recovery_text
	workflow.current = current
	return current, true, {}
}

/* workflow_cancel invalidates one live interaction without publishing effects. */
workflow_cancel :: proc(
	workflow: ^Workflow,
	generation: u64,
) -> (Snapshot, bool, Failure) {
	current, valid, failure := workflow_transition_state(workflow, generation)
	if !valid do return current, false, failure
	if !snapshot_active(current) || !current.cancellable {
		return current, false, Failure{code = .Invalid_Transition, operation = current.operation, generation = generation}
	}
	current.phase = .Cancelled
	current.surface = .None
	current.health = .Idle
	current.cancellable = false
	current.progress = 0
	current.progress_total = 0
	current.message = {}
	workflow.current = current
	return current, true, {}
}

/* workflow_snapshot copies the current coordinator state. */
workflow_snapshot :: proc(workflow: ^Workflow) -> (Snapshot, bool) {
	if workflow == nil || workflow.current.generation == 0 do return {}, false
	return workflow.current, true
}

/* workflow_reset releases no UI resources because the coordinator owns none. */
workflow_reset :: proc(workflow: ^Workflow) {
	if workflow == nil do return
	next_generation := workflow.next_generation
	workflow^ = Workflow{next_generation = next_generation}
}

@(private)
workflow_transition_state :: proc(
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
operation_profile :: proc(operation: Operation) -> (Operation_Profile, bool) {
	switch operation {
	case .Show_Hover, .Go_To_Definition, .Find_References, .Document_Symbols,
	     .Signature_Help:
		return {class = .Service_Query, initial_phase = .Requesting, initial_surface = .Progress}, true
	case .Workspace_Symbols:
		return {class = .Service_Query, initial_phase = .Prompting, initial_surface = .Prompt}, true
	case .Rename:
		return {class = .Checked_Edit, initial_phase = .Prompting, initial_surface = .Prompt}, true
	case .Format_Buffer, .Format_Region:
		return {class = .Checked_Edit, initial_phase = .Requesting, initial_surface = .Progress}, true
	case .Code_Actions:
		return {class = .Checked_Edit, initial_phase = .Selecting, initial_surface = .Candidates}, true
	case .Describe_Bundle:
		return {class = .Factory_Inspection, initial_phase = .Selecting, initial_surface = .Candidates, factory_owned = true}, true
	case .Support_Doctor, .Bundle_List:
		return {class = .Factory_Inspection, initial_phase = .Requesting, initial_surface = .Progress, factory_owned = true}, true
	case .Bundle_Search:
		return {class = .Factory_Inspection, initial_phase = .Prompting, initial_surface = .Prompt, factory_owned = true}, true
	case .Bundle_Install, .Bundle_Enable, .Bundle_Disable, .Bundle_Update,
	     .Bundle_Rollback, .Bundle_Remove:
		return {class = .Bundle_Management, initial_phase = .Selecting, initial_surface = .Candidates, factory_owned = true}, true
	case .Bundle_Refresh_Catalogs:
		return {class = .Bundle_Management, initial_phase = .Requesting, initial_surface = .Progress, factory_owned = true}, true
	case .Invalid:
	}
	return {}, false
}

@(private)
operation_requires_confirmation :: proc(operation: Operation) -> bool {
	return operation == .Bundle_Install || operation == .Bundle_Enable ||
	       operation == .Bundle_Disable || operation == .Bundle_Update ||
	       operation == .Bundle_Rollback || operation == .Bundle_Remove
}
