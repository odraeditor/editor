// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import "../ksawery"

@(private)
ksawery_workflow_start_extension_operation_refresh :: proc(
	commands: ^Command_Context,
	refresh: Ksawery_Extension_Operation_Refresh,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.extension_operation == nil || !state.extension_operation.awaiting_refresh ||
	   state.process.state != nil || state.process_coordinator.child_attached {
		return false
	}
	process: ksawery.Repository_Process
	started := false
	failure := ksawery.Failure_Code.None
	switch refresh {
	case .Status:
		process, started, failure = ksawery.repository_process_start(
			{kind = .Observe_Status, repository = state.repository, limits = ksawery.DEFAULT_PROCESS_LIMITS},
			ksawery_workflow_now(commands), commands.persistent_allocator,
		)
	case .History:
		process, started, failure = ksawery.repository_process_start(
			{kind = .Observe_History, repository = state.repository,
			 history = {limits = ksawery.DEFAULT_HISTORY_LIMITS}, limits = ksawery.DEFAULT_PROCESS_LIMITS},
			ksawery_workflow_now(commands), commands.persistent_allocator,
		)
	case .Refs:
		process, started, failure = ksawery.repository_process_start_ref_observation(
			state.repository, ksawery_workflow_now(commands), commands.persistent_allocator,
		)
	case .Sequence:
		process, started, failure = ksawery.repository_process_start_sequence_observation(
			state.repository, ksawery_workflow_now(commands), ksawery.DEFAULT_SEQUENCE_LIMITS,
			commands.persistent_allocator,
		)
	case .None:
		return false
	}
	if !started {
		state.failure = failure
		return false
	}
	attached, attach_failure := ksawery_process_operation_attach_child(
		&state.process_coordinator, &process, ksawery_workflow_now(commands),
	)
	if !attached {
		ksawery.repository_process_close(&process)
		state.failure = attach_failure
		return false
	}
	switch refresh {
	case .Status:
		state.generation += 1
		if state.generation == 0 do state.generation = 1
	case .History:
		state.history_generation += 1
		if state.history_generation == 0 do state.history_generation = 1
	case .Refs:
		state.ref_generation += 1
		if state.ref_generation == 0 do state.ref_generation = 1
	case .Sequence:
		state.sequence_generation += 1
		if state.sequence_generation == 0 do state.sequence_generation = 1
	case .None:
	}
	state.process = process
	state.pending = .Extension_Operation
	state.extension_operation_refresh = refresh
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_advance_extension_operation_refresh :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.extension_operation == nil || !state.extension_operation.awaiting_refresh || state.process.state != nil {
		return false
	}
	requested := state.extension_operation.plan.refresh
	sequence := [?]struct {
		family: ksawery.Extension_Observation_Family,
		refresh: Ksawery_Extension_Operation_Refresh,
	} {
		{.Status, .Status},
		{.History, .History},
		{.Refs, .Refs},
		{.Sequence, .Sequence},
		{.Conflict, .Sequence},
	}
	for item in sequence {
		if item.family not_in requested || item.family in state.extension_operation_refresh_completed {
			continue
		}
		if item.refresh == .Sequence &&
		   (.Sequence in state.extension_operation_refresh_completed ||
		    .Conflict in state.extension_operation_refresh_completed) {
			continue
		}
		if ksawery_workflow_start_extension_operation_refresh(commands, item.refresh) do return true
		state.extension_operation_refresh_completed += {item.family}
	}
	return ksawery_workflow_finish_extension_operation(commands)
}

@(private)
ksawery_workflow_finish_extension_operation_refresh_child :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.process.state == nil ||
	   (poll.state != .Completed && poll.state != .Failed) {
		return false
	}
	opened := false
	failure := poll.failure
	switch state.extension_operation_refresh {
	case .Status:
		observation: ksawery.Status_Observation
		if poll.state == .Completed {
			observation, opened, failure = ksawery.repository_process_take_status(
				&state.process, state.generation, commands.persistent_allocator,
			)
		}
		if opened {
			next_selection, reconciled, _ := ksawery.status_selection_reconcile(
				&state.observation, &observation, state.selection, nil,
			)
			if state.observation.state != nil do ksawery.status_observation_close(&state.observation)
			state.observation = observation
			state.selection = next_selection if reconciled else ksawery.Status_Selection{}
			if !reconciled do state.selection, _ = ksawery.status_selection_begin(&state.observation)
			_ = ksawery_extension_status_refresh(
				&state.extension_registry, &commands.host, &state.observation,
				commands.temporary_allocator,
			)
			state.extension_operation_refresh_completed += {.Status}
		}
	case .History:
		history: ksawery.History_Observation
		if poll.state == .Completed {
			history, opened, failure = ksawery.repository_process_take_history(
				&state.process, state.history_generation, commands.persistent_allocator,
			)
		}
		if opened {
			if state.history.state != nil do ksawery.history_observation_close(&state.history)
			state.history = history
			state.history_selection, _ = ksawery.history_selection_begin(&state.history)
			_ = ksawery_extension_annotations_refresh_history(
				&state.extension_registry, &commands.host, &state.history,
				commands.temporary_allocator,
			)
			state.extension_operation_refresh_completed += {.History}
		}
	case .Refs:
		refs: ksawery.Ref_Observation
		if poll.state == .Completed {
			refs, opened, failure = ksawery.repository_process_take_refs(
				&state.process, state.ref_generation, commands.persistent_allocator,
			)
		}
		if opened {
			if state.refs.state != nil do ksawery.ref_observation_close(&state.refs)
			state.refs = refs
			state.ref_selection, _ = ksawery.ref_selection_begin(&state.refs)
			_ = ksawery_extension_annotations_refresh_refs(
				&state.extension_registry, &commands.host, &state.refs,
				commands.temporary_allocator,
			)
			state.extension_operation_refresh_completed += {.Refs}
		}
	case .Sequence:
		sequence: ksawery.Sequence_Observation
		if poll.state == .Completed {
			sequence, opened, failure = ksawery.repository_process_take_sequence(
				&state.process, state.sequence_generation, commands.persistent_allocator,
			)
		}
		if opened {
			if state.sequence.state != nil do ksawery.sequence_observation_close(&state.sequence)
			state.sequence = sequence
			state.conflict_selection = 0
			_ = ksawery_extension_annotations_refresh_sequence(
				&state.extension_registry, &commands.host, &state.sequence,
				commands.temporary_allocator,
			)
			state.extension_operation_refresh_completed += {.Sequence, .Conflict}
		}
	case .None:
		return false
	}
	detached, detach_failure := ksawery_process_operation_detach_child(
		&state.process_coordinator, &state.process,
	)
	if !detached do state.process_failure = detach_failure
	ksawery.repository_process_close(&state.process)
	if !opened do state.failure = failure
	return ksawery_workflow_advance_extension_operation_refresh(commands)
}

@(private)
ksawery_extension_operation_target_identity_matches :: proc(
	expected, candidate: ksawery.Extension_Annotation_Target,
) -> bool {
	if expected.family != candidate.family || expected.length != candidate.length do return false
	for index in 0 ..< int(expected.length) {
		if expected.identity[index] != candidate.identity[index] do return false
	}
	return true
}

@(private)
ksawery_workflow_extension_operation_target :: proc(
	state: ^Ksawery_Workflow_State,
	expected: ksawery.Extension_Annotation_Target,
) -> (ksawery.Extension_Annotation_Target, bool) {
	candidate := expected
	switch expected.family {
	case .Path:
		descriptor, described := ksawery.status_observation_descriptor(&state.observation)
		count, counted := ksawery.status_observation_path_count(&state.observation)
		if !described || !counted do return {}, false
		candidate.generation = u64(descriptor.generation)
		observation := ksawery.Extension_Annotation_Observation{.Status, descriptor.repository, candidate.generation}
		for ordinal in 0 ..< count {
			path, found := ksawery.status_observation_path(&state.observation, ordinal)
			if !found do continue
			current, mapped := ksawery.extension_annotation_target_from_path(
				observation, {generation = descriptor.generation, path = path.id},
			)
			if mapped && ksawery_extension_operation_target_identity_matches(expected, current) do return current, true
		}
	case .Revision:
		descriptor, described := ksawery.history_observation_descriptor(&state.history)
		count, counted := ksawery.history_observation_revision_count(&state.history)
		if !described || !counted do return {}, false
		candidate.generation = u64(descriptor.generation)
		observation := ksawery.Extension_Annotation_Observation{.History, descriptor.repository, candidate.generation}
		for ordinal in 0 ..< count {
			revision, found := ksawery.history_observation_revision(&state.history, ordinal)
			if !found do continue
			current, mapped := ksawery.extension_annotation_target_from_revision(
				observation, {generation = descriptor.generation, revision = revision.identity},
			)
			if mapped && ksawery_extension_operation_target_identity_matches(expected, current) do return current, true
		}
	case .Ref, .Remote:
		descriptor, described := ksawery.ref_observation_descriptor(&state.refs)
		if !described do return {}, false
		candidate.generation = u64(descriptor.generation)
		observation := ksawery.Extension_Annotation_Observation{.Refs, descriptor.repository, candidate.generation}
		if expected.family == .Ref {
			count, counted := ksawery.ref_observation_ref_count(&state.refs)
			if !counted do return {}, false
			for ordinal in 0 ..< count {
				reference, found := ksawery.ref_observation_ref(&state.refs, ordinal)
				if !found do continue
				current, mapped := ksawery.extension_annotation_target_from_ref(observation, reference)
				if mapped && ksawery_extension_operation_target_identity_matches(expected, current) do return current, true
			}
		} else {
			count, counted := ksawery.ref_observation_remote_count(&state.refs)
			if !counted do return {}, false
			for ordinal in 0 ..< count {
				remote, found := ksawery.ref_observation_remote(&state.refs, ordinal)
				if !found do continue
				current, mapped := ksawery.extension_annotation_target_from_remote(observation, remote)
				if mapped && ksawery_extension_operation_target_identity_matches(expected, current) do return current, true
			}
		}
	case .Sequence, .Conflict:
		descriptor, described := ksawery.sequence_observation_descriptor(&state.sequence)
		if !described do return {}, false
		candidate.generation = u64(descriptor.generation)
		family := ksawery.Extension_Observation_Family.Sequence
		if expected.family == .Conflict do family = .Conflict
		observation := ksawery.Extension_Annotation_Observation{family, descriptor.repository, candidate.generation}
		sequence := ksawery.Sequence_Target{descriptor.generation, descriptor.fingerprint}
		if expected.family == .Sequence {
			current, mapped := ksawery.extension_annotation_target_from_sequence(observation, sequence)
			if mapped && ksawery_extension_operation_target_identity_matches(expected, current) do return current, true
		} else {
			count, counted := ksawery.sequence_observation_conflict_count(&state.sequence)
			if !counted do return {}, false
			for ordinal in 0 ..< count {
				conflict, found := ksawery.sequence_observation_conflict(&state.sequence, ordinal)
				if !found do continue
				current, mapped := ksawery.extension_annotation_target_from_conflict(
					observation, {sequence = sequence, conflict = conflict.id},
				)
				if mapped && ksawery_extension_operation_target_identity_matches(expected, current) do return current, true
			}
		}
	case .Process:
		candidate.generation = expected.generation + 1
		observation := ksawery.Extension_Annotation_Observation{.Process, state.repository, candidate.generation}
		records := ksawery_workflow_process_records(state)
		for &record in records {
			descriptor, described := ksawery.process_record_descriptor(&record)
			if !described do continue
			row := ksawery.Process_Row_Descriptor {
				id = {operation = descriptor.operation, generation = descriptor.generation},
				repository = descriptor.repository,
			}
			current, mapped := ksawery.extension_annotation_target_from_process(observation, row)
			if mapped && ksawery_extension_operation_target_identity_matches(expected, current) do return current, true
		}
	case .Diff_Unit, .Revision_Range, .Invalid:
		return {}, false
	}
	if candidate.generation <= expected.generation do candidate.generation = expected.generation + 1
	return candidate, false
}

@(private)
ksawery_workflow_extension_operation_state :: proc(
	state: ^Ksawery_Workflow_State,
	observation: ksawery.Extension_Observation_Family,
) -> (ksawery.Operation_State, bool) {
	if observation == .Status {
		descriptor, described := ksawery.status_observation_descriptor(&state.observation)
		if described do return descriptor.operation, true
	}
	if observation == .Sequence || observation == .Conflict {
		descriptor, described := ksawery.sequence_observation_descriptor(&state.sequence)
		if !described do return .Unknown, false
		if descriptor.state == .Inactive do return .Normal, true
		switch descriptor.kind {
		case .Merge:         return .Merging, true
		case .Rebase:        return .Rebasing, true
		case .Cherry_Pick:   return .Cherry_Picking, true
		case .Revert:        return .Reverting, true
		case .Bisect:        return .Bisecting, true
		case .Apply_Patches: return .Applying_Patches, true
		case .Other:         return .Other_Sequence, true
		case .None:          return .Normal, true
		case .Invalid:       return .Unknown, false
		}
	}
	return .Unknown, false
}

@(private)
ksawery_workflow_finish_extension_operation :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.extension_operation == nil || !state.extension_operation.active ||
	   !state.extension_operation.awaiting_refresh || state.process.state != nil {
		return false
	}
	plan := state.extension_operation.plan
	refreshed_generation := ksawery.Repository_Generation(state.generation)
	if refreshed_generation <= state.extension_operation.submission.repository_generation {
		refreshed_generation = state.extension_operation.submission.repository_generation + 1
	}
	evidence := ksawery.Extension_Operation_Refresh_Evidence {
		repository = state.repository,
		repository_generation = refreshed_generation,
		attempted = plan.refresh,
		completed = state.extension_operation_refresh_completed,
	}
	if plan.verifier.kind == .Target_Present || plan.verifier.kind == .Target_Absent {
		if plan.verifier.observation in evidence.completed {
			evidence.target, evidence.target_present =
				ksawery_workflow_extension_operation_target(state, plan.verifier.target)
			evidence.target_checked = evidence.target != {}
		}
	} else if plan.verifier.kind == .Operation_State &&
	          plan.verifier.observation in evidence.completed {
		evidence.operation, evidence.operation_checked =
			ksawery_workflow_extension_operation_state(state, plan.verifier.observation)
	}
	completed, operation_failure := ksawery_extension_operation_workflow_complete(
		state.extension_operation, &state.process_coordinator, evidence,
		ksawery_workflow_now(commands),
	)
	status := ksawery.Extension_Command_Result_Status.Failed
	message := "Ksawery extension external operation evidence was rejected"
	if completed {
		result, inspected := ksawery_extension_operation_workflow_inspect(state.extension_operation)
		if inspected {
			switch result.outcome {
			case .Verified_Success:
				status = .Completed
				message = "Ksawery extension external operation completed with typed verification"
			case .Cancelled_Before_Effect, .Cancelled_After_Possible_Effect:
				status = .Cancelled
				message = "Ksawery extension external operation was cancelled"
			case .Known_Failure, .Timed_Out_Before_Effect, .Timed_Out_After_Possible_Effect,
			     .Verification_Mismatch, .Indeterminate, .None:
				status = .Failed
				message = "Ksawery extension external operation ended without a verified effect"
			}
		}
	} else {
		_ = operation_failure
	}
	workflow := &state.extension_command_workflow
	command_result := ksawery.Extension_Command_Result {
		request = workflow.request,
		family = workflow.family,
		family_generation = workflow.family_generation,
		action = workflow.action,
		status = status,
		external_operation_requested = status == .Completed,
	}
	refreshed_context := workflow.initial_context
	refreshed_context.repository_generation = refreshed_generation
	if refreshed_context.worktree_generation < ksawery.Worktree_Generation(refreshed_generation) {
		refreshed_context.worktree_generation = ksawery.Worktree_Generation(refreshed_generation)
	}
	command_completed, _ := ksawery_extension_command_workflow_complete(
		workflow, command_result, refreshed_context, completed,
	)
	if !command_completed {
		_ = ksawery_extension_command_workflow_abort(workflow)
		message = "Ksawery extension command result failed closed"
	}
	state.pending = .None
	state.extension_operation_refresh = .None
	state.extension_operation_refresh_completed = {}
	state.view_mode = state.extension_operation_return_mode
	state.position = state.extension_operation_return_position
	state.extension_operation_return_mode = .Status
	state.extension_operation_return_position = {}
	switch status {
	case .Completed: state.failure = .None
	case .Cancelled: state.failure = .Cancelled
	case .Failed, .Rejected, .Invalid: state.failure = .Process_Failed
	}
	command_context_set_diagnostic(commands, message)
	return true
}

@(private)
ksawery_workflow_step_extension_operation :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.pending != .Extension_Operation || state.extension_operation == nil ||
	   !state.extension_operation.active {
		return false
	}
	if state.extension_operation.awaiting_refresh {
		if state.process.state != nil {
			poll, polled := ksawery.repository_process_poll(&state.process, ksawery_workflow_now(commands))
			if !polled || (poll.state != .Completed && poll.state != .Failed) do return false
			return ksawery_workflow_finish_extension_operation_refresh_child(commands, poll)
		}
		return ksawery_workflow_advance_extension_operation_refresh(commands)
	}
	_, refresh_ready, failure := ksawery_extension_operation_workflow_poll(
		state.extension_operation, &state.process_coordinator, ksawery_workflow_now(commands),
	)
	if failure.code != .None {
		state.failure = .Process_Failed
		command_context_set_diagnostic(commands, "Ksawery extension external operation Process evidence was rejected")
		return true
	}
	if refresh_ready do return ksawery_workflow_advance_extension_operation_refresh(commands)
	return false
}

@(private)
ksawery_workflow_cancel_extension_operation :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.pending != .Extension_Operation || state.extension_operation == nil ||
	   !state.extension_operation.active {
		return false
	}
	cancelled, _ := ksawery_extension_operation_workflow_cancel(
		state.extension_operation, &state.process_coordinator, ksawery_workflow_now(commands),
	)
	if cancelled {
		command_context_set_diagnostic(commands, "Ksawery extension external operation cancellation requested")
	}
	return cancelled
}
