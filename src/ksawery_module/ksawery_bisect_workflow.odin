// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import "../interaction"
import "../ksawery"
import "../ui"
import "base:runtime"
import "core:fmt"

@(private)
ksawery_workflow_selected_bisect_revision :: proc(state: ^Ksawery_Workflow_State) -> (ksawery.Revision_Identity, bool) {
	if state == nil || state.view_mode != .History || state.history.state == nil ||
	   !ksawery.history_selection_is_current(&state.history, state.history_selection) ||
	   state.history_selection.current.kind != .Revision {
		return {}, false
	}
	return state.history_selection.current.revision.revision, true
}

@(private)
ksawery_workflow_bisect_good_index :: proc(
	state: ^Ksawery_Workflow_State,
	revision: ksawery.Revision_Identity,
) -> (int, bool) {
	if state == nil do return 0, false
	for boundary, index in state.bisect_good[:state.bisect_good_count] {
		if boundary == revision do return index, true
	}
	return 0, false
}

@(private)
ksawery_workflow_history_item_is_bisect_marked :: proc(
	state: ^Ksawery_Workflow_State,
	item: ksawery.History_Item_ID,
) -> bool {
	if state == nil || item.kind != .Revision do return false
	if item.revision.revision == state.bisect_bad do return true
	_, found := ksawery_workflow_bisect_good_index(state, item.revision.revision)
	return found
}

@(private)
ksawery_workflow_mark_bisect_boundary :: proc(commands: ^Command_Context, good: bool) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.process.state != nil || state.view_mode != .History do return false
	revision, selected := ksawery_workflow_selected_bisect_revision(state)
	if !selected {
		state.failure = .Target_Incompatible
		command_context_set_diagnostic(commands, "Select one exact History commit for the bisect boundary")
		return true
	}
	if good {
		if revision == state.bisect_bad {
			state.failure = .Target_Overlap
			command_context_set_diagnostic(commands, "The bad boundary cannot also be known good")
			return true
		}
		if index, marked := ksawery_workflow_bisect_good_index(state, revision); marked {
			for next in index + 1 ..< int(state.bisect_good_count) do state.bisect_good[next - 1] = state.bisect_good[next]
			state.bisect_good_count -= 1
			state.bisect_good[state.bisect_good_count] = {}
			state.failure = .None
			command_context_set_diagnostic(commands, "Removed the exact known-good bisect boundary")
			return true
		}
		if state.bisect_good_count >= ksawery.DEFAULT_BISECT_LIMITS.good_boundaries {
			state.failure = .Target_Limit
			return true
		}
		state.bisect_good[state.bisect_good_count] = revision
		state.bisect_good_count += 1
		state.failure = .None
		command_context_set_diagnostic(commands, fmt.tprintf("Known-good bisect boundaries: %d", state.bisect_good_count))
		return true
	}
	if _, overlap := ksawery_workflow_bisect_good_index(state, revision); overlap {
		state.failure = .Target_Overlap
		command_context_set_diagnostic(commands, "Remove this revision from the known-good boundaries before marking it bad")
		return true
	}
	state.bisect_bad = revision
	state.failure = .None
	command_context_set_diagnostic(commands, "Marked the exact known-bad bisect boundary")
	return true
}

@(private)
ksawery_workflow_clear_bisect_preparation :: proc(state: ^Ksawery_Workflow_State, clear_boundaries: bool) {
	if state == nil do return
	state.bisect_action = .Invalid
	state.bisect_confirmation = {}
	state.bisect_request = {}
	if clear_boundaries {
		state.bisect_bad = {}
		state.bisect_good = {}
		state.bisect_good_count = 0
		if state.bisect_boundaries.state != nil do ksawery.bisect_boundary_set_close(&state.bisect_boundaries)
		state.bisect_precondition = {}
		state.bisect_progress = {}
	}
}

@(private)
ksawery_workflow_begin_bisect :: proc(commands: ^Command_Context, action: ksawery.Bisect_Action) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.observation.state == nil || state.history.state == nil ||
	   state.refs.state == nil || state.sequence.state == nil || state.process.state != nil || action == .Invalid {
		return false
	}
	lineage: ksawery.Bisect_Precondition
	progress: ksawery.Bisect_Progress
	if action == .Start {
		if state.view_mode != .History || !ksawery.revision_identity_is_valid(state.bisect_bad) ||
		   state.bisect_good_count == 0 {
			state.failure = .Action_Unavailable
			command_context_set_diagnostic(commands, "Mark one exact bad and at least one exact good History boundary")
			return true
		}
		if state.bisect_boundaries.state != nil do ksawery.bisect_boundary_set_close(&state.bisect_boundaries)
		set, opened, set_failure := ksawery.bisect_boundary_set_open(
			state.bisect_bad, state.bisect_good[:state.bisect_good_count],
			ksawery.DEFAULT_BISECT_LIMITS, state.allocator,
		)
		if !opened {
			state.failure = set_failure
			return true
		}
		state.bisect_boundaries = set
	} else {
		if state.view_mode != .Sequence || state.bisect_boundaries.state == nil ||
		   !ksawery.bisect_precondition_is_valid(state.bisect_precondition) ||
		   state.bisect_precondition.action != .Start ||
		   !ksawery.bisect_progress_is_valid(state.bisect_progress, state.bisect_precondition.limits) ||
		   (state.bisect_progress.complete && action != .Reset) {
			state.failure = .Action_Unavailable
			command_context_set_diagnostic(commands, "No retained active manual bisect candidate is available")
			return true
		}
		lineage = state.bisect_precondition
		progress = state.bisect_progress
	}
	editor, inspected := ksawery_workflow_branch_editor_state(commands)
	if !inspected {
		state.failure = .Presentation_Unavailable
		return true
	}
	if editor.modified_repository_resources != 0 {
		state.failure = .Modified_Buffer
		command_context_set_diagnostic(commands, "Save repository buffers before preparing this bisect action")
		return true
	}
	process, started, failure := ksawery.repository_process_start_bisect_precondition(
		&state.observation,
		&state.history,
		&state.refs,
		&state.sequence,
		&state.bisect_boundaries,
		action,
		lineage,
		progress,
		{
			repository_resources = editor.repository_resources,
			modified_repository_resources = editor.modified_repository_resources,
		},
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
	)
	if !started {
		state.failure = failure
		command_context_set_diagnostic(commands, "Checked manual bisect preconditions are unavailable")
		return true
	}
	kind, title := ksawery_workflow_bisect_operation(action)
	recorded, record_failure := ksawery_process_observation_begin(
		&state.process_coordinator,
		&process,
		state.process_coordinator.confirmed_observation,
		{
			kind = kind,
			target_kind = .Repository,
			title = title,
			target = ksawery.repository_context_string(&state.repository),
			phase_detail = "Checking manual bisect preconditions",
			checking = true,
		},
		ksawery_workflow_now(commands),
	)
	if !recorded {
		ksawery.repository_process_close(&process)
		state.failure = record_failure
		return true
	}
	state.bisect_action = action
	state.process = process
	state.pending = .Bisect_Precondition
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_bisect_operation :: proc(action: ksawery.Bisect_Action) -> (ksawery.Repository_Operation_Kind, string) {
	switch action {
	case .Start: return .Bisect, "Start Manual Bisect"
	case .Good: return .Bisect_Good, "Classify Bisect Candidate Good"
	case .Bad: return .Bisect_Bad, "Classify Bisect Candidate Bad"
	case .Skip: return .Bisect_Skip, "Skip Bisect Candidate"
	case .Reset: return .Bisect_Reset, "Reset Manual Bisect"
	case .Invalid: return .Invalid, "Invalid Manual Bisect"
	}
	return .Invalid, "Invalid Manual Bisect"
}

@(private)
ksawery_workflow_finish_bisect_precondition :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	if state == nil || state.pending != .Bisect_Precondition do return {}, false
	precondition, opened, failure := ksawery.repository_process_take_bisect_precondition(&state.process)
	if !opened {
		_, _ = ksawery_process_observation_finish(
			&state.process_coordinator, &state.process, false,
			"Manual bisect precondition failed", ksawery_workflow_now(commands),
		)
		state.failure = poll.failure if poll.failure != .None else failure
		return ksawery_workflow_sequence_outcome(), true
	}
	detached, detach_failure := ksawery_process_operation_detach_child(&state.process_coordinator, &state.process)
	if !detached {
		state.failure = detach_failure
		return ksawery_workflow_sequence_outcome(), true
	}
	_, _ = ksawery_process_operation_publish_phase(
		&state.process_coordinator, nil, .Checking,
		"Waiting for exact manual bisect confirmation", false, ksawery_workflow_now(commands),
	)
	state.bisect_precondition = precondition
	return ksawery_workflow_sequence_outcome(.Prepare_Bisect_Confirmation), true
}

@(private)
ksawery_workflow_confirm_bisect :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Bisect_Confirmation || state.process.state != nil ||
	   state.bisect_boundaries.state == nil {
		return false
	}
	confirmed, confirmation_failure := ksawery.bisect_confirmation_confirm(
		&state.bisect_confirmation, state.bisect_confirmation.id,
	)
	if !confirmed {
		state.failure = confirmation_failure
		return true
	}
	operation := state.next_bisect
	if operation == ksawery.Bisect_Operation_ID(0) do operation = 1
	request, prepared, failure := ksawery.bisect_request_prepare(
		state.bisect_confirmation.precondition, operation, &state.bisect_confirmation,
	)
	if !prepared {
		state.failure = failure
		return true
	}
	process, started, start_failure := ksawery.repository_process_start_bisect(
		&state.sequence,
		request.precondition,
		&state.bisect_boundaries,
		request,
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
	)
	if !started {
		state.failure = start_failure
		return true
	}
	attached, attach_failure := ksawery_process_operation_attach_child(
		&state.process_coordinator, &process, ksawery_workflow_now(commands),
	)
	if !attached {
		ksawery.repository_process_close(&process)
		state.failure = attach_failure
		return true
	}
	published, publish_failure := ksawery_process_operation_publish_phase(
		&state.process_coordinator, &process, .Executing,
		"Executing checked manual bisect action", true, ksawery_workflow_now(commands),
	)
	if !published {
		_, _ = ksawery_process_operation_detach_child(&state.process_coordinator, &process)
		ksawery.repository_process_close(&process)
		state.failure = publish_failure
		return true
	}
	if state.bisect_result.state != nil do ksawery.bisect_result_close(&state.bisect_result)
	state.bisect_request = request
	state.process = process
	state.pending = .Bisect
	state.next_bisect = operation + 1
	if state.next_bisect == ksawery.Bisect_Operation_ID(0) do state.next_bisect = 1
	state.view_mode = request.precondition.action == .Start ? .History : .Sequence
	state.failure = .None
	return true
}

@(private)
dispatch_ksawery_bisect_confirmation_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Bisect_Confirmation || state.process.state != nil {
		return {}, App_Failure{stage = .UI}
	}
	if input.kind == .Key && input.stroke.kind == .Unicode_Scalar &&
	   ((input.stroke.scalar == 'g' && input.stroke.modifiers == {.Control}) ||
	    (input.stroke.scalar == 'q' && input.stroke.modifiers == {})) {
		_ = ksawery_process_observation_finish_without_child(
			&state.process_coordinator, .Cancelled, .Cancelled_Before_Effect,
			"Manual bisect confirmation cancelled", ksawery_workflow_now(commands),
		)
		state.bisect_confirmation = {}
		state.bisect_request = {}
		state.view_mode = state.bisect_action == .Start ? .History : .Sequence
		state.failure = .Cancelled
		return Interaction_Result{changed = true}, {}
	}
	if input.kind == .Key && input.stroke.kind == .Enter && input.stroke.modifiers == {.Control} {
		return Interaction_Result{changed = ksawery_workflow_confirm_bisect(commands)}, {}
	}
	return {}, {}
}

@(private)
ksawery_workflow_finish_bisect_process :: proc(
	commands: ^Command_Context,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	if state == nil || state.pending != .Bisect do return {}, false
	result, opened, failure := ksawery.repository_process_take_bisect(
		&state.process, commands.persistent_allocator,
	)
	succeeded := false
	if opened {
		if state.bisect_result.state != nil do ksawery.bisect_result_close(&state.bisect_result)
		state.bisect_result = result
		descriptor, described := ksawery.bisect_result_descriptor(&state.bisect_result)
		succeeded = described && descriptor.process_succeeded
	}
	effect, prepared, prepare_failure := ksawery_process_operation_prepare_refresh(
		&state.process_coordinator, &state.process,
		"Refreshing Status, History, Refs, and Sequence after bisect",
		ksawery_workflow_now(commands),
	)
	if !prepared {
		_, _ = ksawery_process_observation_finish(
			&state.process_coordinator, &state.process, false,
			"Manual bisect mutation could not refresh", ksawery_workflow_now(commands),
		)
		state.failure = prepare_failure
		return ksawery_workflow_sequence_outcome(), true
	}
	state.operation_effect = effect
	state.operation_verification = succeeded ? .Unavailable : .Known_Failure
	state.failure = failure if !opened else .None
	state.sequence_mutation_refresh = true
	state.sequence_mutation_conflict = false
	state.sequence_mutation_kind = .Bisect
	state.view_mode = .Status
	return ksawery_workflow_sequence_outcome(.Start_Bisect_Refresh), true
}

@(private)
ksawery_bisect_confirmation_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || viewport_items == 0 || allocator.procedure == nil ||
	   state.bisect_confirmation.id == ksawery.Bisect_Confirmation_ID(0) ||
	   !ksawery.bisect_precondition_is_valid(state.bisect_confirmation.precondition) {
		return nil, nil, false
	}
	precondition := state.bisect_confirmation.precondition
	row_count := min(int(precondition.boundaries.good_count) + 8, int(ui.MAX_LIST_ITEMS))
	rows, rows_error := make([]ui.List_Item_Definition, row_count, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, row_count * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {delete(rows, allocator); return nil, nil, false}
	write := 0
	_ = ksawery_append_presented_label(rows, storage, &write, 0xDE00_0000_0000_0001,
		"Ksawery Manual Bisect Confirmation", true, {surface = .Sequence, subject = .Section})
	_ = ksawery_append_presented_label(rows, storage, &write, 0xDE00_0000_0000_0002,
		fmt.tprintf("Action: %v", precondition.action), true,
		{surface = .Sequence, subject = .Operation, destructive = precondition.action == .Reset})
	_ = ksawery_append_presented_label(rows, storage, &write, 0xDE00_0000_0000_0003,
		fmt.tprintf("Current: %s", ksawery.revision_identity_string(&precondition.head.object)), true,
		{surface = .Sequence, subject = .Revision})
	if precondition.action == .Start {
		_ = ksawery_append_presented_label(rows, storage, &write, 0xDE00_0000_0000_0004,
			fmt.tprintf("Known bad: %s", ksawery.revision_identity_string(&precondition.boundaries.bad)), true,
			{surface = .Sequence, subject = .Revision})
		for index in 0 ..< precondition.boundaries.good_count {
			boundary, found := ksawery.bisect_boundary_set_good(&state.bisect_boundaries, index)
			if !found do break
			_ = ksawery_append_presented_label(rows, storage, &write,
				ui.List_Item_ID(0xDE10_0000_0000_0000 | u64(index + 1)),
				fmt.tprintf("Known good %d: %s", index + 1, ksawery.revision_identity_string(&boundary)), true,
				{surface = .Sequence, subject = .Revision})
		}
	} else {
		_ = ksawery_append_presented_label(rows, storage, &write, 0xDE00_0000_0000_0005,
			fmt.tprintf("Candidate: %s", ksawery.revision_identity_string(&precondition.progress.candidate)), true,
			{surface = .Sequence, subject = .Revision})
	}
	_ = ksawery_append_presented_label(rows, storage, &write, 0xDE00_0000_0000_0006,
		"C-Enter confirms this exact action; C-g cancels.", false,
		{surface = .Sequence, subject = .Operation, destructive = true})
	definitions = rows[:write]
	state.position = {presentation_generation = 1, selection_owner = .View, current_item = i32(write - 1),
		first_visible_item = 0, viewport_items = min(viewport_items, u32(write))}
	return definitions, storage, true
}
