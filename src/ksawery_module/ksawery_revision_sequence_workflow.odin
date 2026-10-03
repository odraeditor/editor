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
ksawery_workflow_revision_sequence_target_count :: proc(state: ^Ksawery_Workflow_State) -> int {
	if state == nil || state.revision_sequence_selection == nil do return 0
	return len(state.revision_sequence_selection.targets)
}

@(private)
ksawery_workflow_revision_sequence_selection_bytes :: proc(state: ^Ksawery_Workflow_State) -> u64 {
	if state == nil || state.revision_sequence_selection == nil do return 0
	return u64(size_of(Ksawery_Revision_Sequence_Selection)) +
	       u64(cap(state.revision_sequence_selection.targets)) * u64(size_of(ksawery.Revision_Sequence_Target))
}

@(private)
ksawery_workflow_clear_revision_sequence_selection :: proc(state: ^Ksawery_Workflow_State) {
	if state == nil do return
	if state.revision_sequence_selection != nil {
		clear(&state.revision_sequence_selection.targets)
	}
	if state.revision_sequence_set.state != nil {
		ksawery.revision_sequence_set_close(&state.revision_sequence_set)
	}
	state.revision_sequence_family = .Invalid
	state.revision_sequence_action = .Invalid
	state.revision_sequence_precondition = {}
	state.revision_sequence_confirmation = {}
	state.revision_sequence_request = {}
}

@(private)
ksawery_workflow_clear_revision_sequence_targets :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .History || state.process.state != nil ||
	   ksawery_workflow_revision_sequence_target_count(state) == 0 {
		return false
	}
	ksawery_workflow_clear_revision_sequence_selection(state)
	state.failure = .None
	command_context_set_diagnostic(commands, "Cleared the ordered sequence set")
	return true
}

@(private)
ksawery_workflow_history_revision_entry :: proc(
	state: ^Ksawery_Workflow_State,
	revision: ksawery.Revision_Identity,
) -> (ksawery.Revision_Entry, bool) {
	if state == nil || state.history.state == nil do return {}, false
	count, counted := ksawery.history_observation_revision_count(&state.history)
	if !counted do return {}, false
	for index in 0 ..< count {
		entry, found := ksawery.history_observation_revision(&state.history, index)
		if found && entry.identity == revision do return entry, true
	}
	return {}, false
}

@(private)
ksawery_workflow_selected_revision_sequence_target :: proc(
	state: ^Ksawery_Workflow_State,
) -> (ksawery.Revision_Sequence_Target, bool) {
	if state == nil || state.view_mode != .History || state.history.state == nil ||
	   !ksawery.history_selection_is_current(&state.history, state.history_selection) ||
	   state.history_selection.current == {} {
		return {}, false
	}
	item := state.history_selection.current
	entry, found := ksawery_workflow_history_revision_entry(state, item.revision.revision)
	if !found do return {}, false
	target := ksawery.Revision_Sequence_Target {
		revision = entry.identity,
		parent_count = entry.parent_count,
	}
	if entry.parent_count > 1 {
		if item.kind != .Parent do return {}, false
		for parent, parent_index in entry.parents[:entry.parent_count] {
			if parent == item.parent {
				target.mainline = {number = u8(parent_index + 1), parent = parent}
				return target, true
			}
		}
		return {}, false
	}
	if item.kind != .Revision do return {}, false
	return target, true
}

@(private)
ksawery_workflow_revision_sequence_target_index :: proc(
	state: ^Ksawery_Workflow_State,
	revision: ksawery.Revision_Identity,
) -> (int, bool) {
	if state == nil || state.revision_sequence_selection == nil do return 0, false
	for target, index in state.revision_sequence_selection.targets {
		if target.revision == revision do return index, true
	}
	return 0, false
}

@(private)
ksawery_workflow_history_item_is_sequence_marked :: proc(
	state: ^Ksawery_Workflow_State,
	item: ksawery.History_Item_ID,
) -> bool {
	if state == nil || item == {} do return false
	index, found := ksawery_workflow_revision_sequence_target_index(state, item.revision.revision)
	if !found do return false
	if item.kind == .Revision do return true
	return item.kind == .Parent &&
	       state.revision_sequence_selection.targets[index].mainline.parent == item.parent
}

@(private)
ksawery_workflow_mark_revision_sequence_target :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.process.state != nil do return false
	target, selected := ksawery_workflow_selected_revision_sequence_target(state)
	if !selected {
		state.failure = .Target_Incompatible
		command_context_set_diagnostic(commands, "Select a commit, or one exact parent row to choose a merge mainline")
		return true
	}
	if _, duplicate := ksawery_workflow_revision_sequence_target_index(state, target.revision); duplicate {
		state.failure = .Target_Duplicate
		command_context_set_diagnostic(commands, "The selected commit is already in the ordered sequence set")
		return true
	}
	if ksawery_workflow_revision_sequence_target_count(state) >= int(ksawery.DEFAULT_REVISION_SEQUENCE_LIMITS.commits) {
		state.failure = .Target_Limit
		return true
	}
	if state.revision_sequence_selection == nil {
		allocation_error: runtime.Allocator_Error
		state.revision_sequence_selection, allocation_error = new(
			Ksawery_Revision_Sequence_Selection, state.allocator,
		)
		if allocation_error == nil {
			state.revision_sequence_selection.allocator = state.allocator
			state.revision_sequence_selection.targets, allocation_error = make(
			[dynamic]ksawery.Revision_Sequence_Target, 0, 8, state.allocator,
			)
		}
		if allocation_error != nil {
			if state.revision_sequence_selection != nil {
				free(state.revision_sequence_selection, state.allocator)
				state.revision_sequence_selection = nil
			}
			state.failure = .Allocation
			return true
		}
	}
	if _, allocation_error := append(&state.revision_sequence_selection.targets, target); allocation_error != nil {
		state.failure = .Allocation
		return true
	}
	if state.revision_sequence_set.state != nil do ksawery.revision_sequence_set_close(&state.revision_sequence_set)
	state.failure = .None
	command_context_set_diagnostic(
		commands,
		fmt.tprintf("Added exact commit %d to the ordered sequence set", ksawery_workflow_revision_sequence_target_count(state)),
	)
	return true
}

@(private)
ksawery_workflow_unmark_revision_sequence_target :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .History || state.process.state != nil ||
	   state.history_selection.current == {} {
		return false
	}
	revision := state.history_selection.current.revision.revision
	index, found := ksawery_workflow_revision_sequence_target_index(state, revision)
	if !found {
		state.failure = .Action_Unavailable
		return true
	}
	for next in index + 1 ..< len(state.revision_sequence_selection.targets) {
		state.revision_sequence_selection.targets[next - 1] = state.revision_sequence_selection.targets[next]
	}
	resize(&state.revision_sequence_selection.targets, len(state.revision_sequence_selection.targets) - 1)
	if state.revision_sequence_set.state != nil do ksawery.revision_sequence_set_close(&state.revision_sequence_set)
	state.failure = .None
	command_context_set_diagnostic(commands, "Removed the exact commit from the ordered sequence set")
	return true
}

@(private)
ksawery_workflow_revision_sequence_editor_state :: proc(
	commands: ^Command_Context,
) -> (ksawery.Revision_Sequence_Editor_State, bool) {
	editor, inspected := ksawery_workflow_branch_editor_state(commands)
	if !inspected do return {}, false
	return {
		repository_resources = editor.repository_resources,
		modified_repository_resources = editor.modified_repository_resources,
	}, true
}

@(private)
ksawery_workflow_begin_revision_sequence :: proc(
	commands: ^Command_Context,
	family: ksawery.Revision_Sequence_Family,
	action: ksawery.Revision_Sequence_Action,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.observation.state == nil || state.history.state == nil ||
	   state.refs.state == nil || state.sequence.state == nil || state.process.state != nil ||
	   family == .Invalid || action == .Invalid {
		return false
	}
	lineage: ksawery.Revision_Sequence_Precondition
	if action == .Start {
		if state.view_mode != .History || ksawery_workflow_revision_sequence_target_count(state) == 0 {
			state.failure = .Action_Unavailable
			command_context_set_diagnostic(commands, "Mark an ordered set of exact History commits before starting this action")
			return true
		}
		if state.revision_sequence_set.state != nil {
			ksawery.revision_sequence_set_close(&state.revision_sequence_set)
		}
		set, opened, set_failure := ksawery.revision_sequence_set_open(
			state.revision_sequence_selection.targets[:],
			ksawery.DEFAULT_REVISION_SEQUENCE_LIMITS,
			state.allocator,
		)
		if !opened {
			state.failure = set_failure
			return true
		}
		state.revision_sequence_set = set
	} else {
		if state.view_mode != .Sequence || state.revision_sequence_set.state == nil ||
		   !ksawery.revision_sequence_precondition_is_valid(state.revision_sequence_precondition) ||
		   state.revision_sequence_precondition.action != .Start ||
		   state.revision_sequence_precondition.family != family {
			state.failure = .Action_Unavailable
			command_context_set_diagnostic(commands, "No retained checked ordered set is available for this sequence")
			return true
		}
		lineage = state.revision_sequence_precondition
	}
	editor, inspected := ksawery_workflow_revision_sequence_editor_state(commands)
	if !inspected {
		state.failure = .Presentation_Unavailable
		return true
	}
	if editor.modified_repository_resources != 0 {
		state.failure = .Modified_Buffer
		command_context_set_diagnostic(commands, "Save repository buffers before preparing this sequence action")
		return true
	}
	process, started, failure := ksawery.repository_process_start_revision_sequence_precondition(
		&state.observation,
		&state.history,
		&state.refs,
		&state.sequence,
		&state.revision_sequence_set,
		family,
		action,
		lineage,
		editor,
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
	)
	if !started {
		state.failure = failure
		command_context_set_diagnostic(commands, "Checked sequenced revision preconditions are unavailable")
		return true
	}
	kind, title := ksawery_workflow_revision_sequence_operation(family, action)
	recorded, record_failure := ksawery_process_observation_begin(
		&state.process_coordinator,
		&process,
		state.process_coordinator.confirmed_observation,
		{
			kind = kind,
			target_kind = .Repository,
			title = title,
			target = ksawery.repository_context_string(&state.repository),
			phase_detail = "Checking sequenced revision preconditions",
			checking = true,
		},
		ksawery_workflow_now(commands),
	)
	if !recorded {
		ksawery.repository_process_close(&process)
		state.failure = record_failure
		return true
	}
	state.revision_sequence_family = family
	state.revision_sequence_action = action
	state.process = process
	state.pending = .Revision_Sequence_Precondition
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_revision_sequence_operation :: proc(
	family: ksawery.Revision_Sequence_Family,
	action: ksawery.Revision_Sequence_Action,
) -> (ksawery.Repository_Operation_Kind, string) {
	if family == .Cherry_Pick {
		switch action {
		case .Start: return .Cherry_Pick, "Cherry-Pick Ordered Revisions"
		case .Continue: return .Continue_Cherry_Pick, "Continue Cherry-Pick"
		case .Skip: return .Skip_Cherry_Pick, "Skip Cherry-Pick Step"
		case .Abort: return .Abort_Cherry_Pick, "Abort Cherry-Pick"
		case .Invalid: return .Invalid, "Invalid Revision Sequence"
		}
	} else if family == .Revert {
		switch action {
		case .Start: return .Revert, "Revert Ordered Revisions"
		case .Continue: return .Continue_Revert, "Continue Revert"
		case .Skip: return .Skip_Revert, "Skip Revert Step"
		case .Abort: return .Abort_Revert, "Abort Revert"
		case .Invalid: return .Invalid, "Invalid Revision Sequence"
		}
	}
	return .Invalid, "Invalid Revision Sequence"
}

@(private)
ksawery_workflow_finish_revision_sequence_precondition :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	if state == nil || state.pending != .Revision_Sequence_Precondition do return {}, false
	precondition, opened, failure :=
		ksawery.repository_process_take_revision_sequence_precondition(&state.process)
	if !opened {
		_, _ = ksawery_process_observation_finish(
			&state.process_coordinator, &state.process, false,
			"Sequenced revision precondition failed", ksawery_workflow_now(commands),
		)
		state.failure = poll.failure if poll.failure != .None else failure
		return ksawery_workflow_sequence_outcome(), true
	}
	detached, detach_failure := ksawery_process_operation_detach_child(
		&state.process_coordinator, &state.process,
	)
	if !detached {
		state.failure = detach_failure
		return ksawery_workflow_sequence_outcome(), true
	}
	_, _ = ksawery_process_operation_publish_phase(
		&state.process_coordinator, nil, .Checking,
		"Waiting for exact sequenced revision confirmation", false, ksawery_workflow_now(commands),
	)
	state.revision_sequence_precondition = precondition
	return ksawery_workflow_sequence_outcome(.Prepare_Revision_Sequence_Confirmation), true
}

@(private)
ksawery_workflow_confirm_revision_sequence :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Revision_Sequence_Confirmation ||
	   state.process.state != nil || state.revision_sequence_set.state == nil {
		return false
	}
	confirmed, confirmation_failure := ksawery.revision_sequence_confirmation_confirm(
		&state.revision_sequence_confirmation, state.revision_sequence_confirmation.id,
	)
	if !confirmed {
		state.failure = confirmation_failure
		return true
	}
	operation := state.next_revision_sequence
	if operation == ksawery.Revision_Sequence_Operation_ID(0) do operation = 1
	request, prepared, failure := ksawery.revision_sequence_request_prepare(
		state.revision_sequence_confirmation.precondition,
		operation,
		&state.revision_sequence_confirmation,
	)
	if !prepared {
		state.failure = failure
		return true
	}
	process: ksawery.Repository_Process
	started := false
	start_failure := ksawery.Failure_Code.None
	if state.revision_sequence_family == .Cherry_Pick {
		process, started, start_failure = ksawery.repository_process_start_cherry_pick(
			&state.sequence, &state.revision_sequence_set,
			request.precondition, request, ksawery_workflow_now(commands), commands.persistent_allocator,
		)
	} else if state.revision_sequence_family == .Revert {
		process, started, start_failure = ksawery.repository_process_start_revert(
			&state.sequence, &state.revision_sequence_set,
			request.precondition, request, ksawery_workflow_now(commands), commands.persistent_allocator,
		)
	}
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
		"Applying checked sequenced revision action", true, ksawery_workflow_now(commands),
	)
	if !published {
		_, _ = ksawery_process_operation_detach_child(&state.process_coordinator, &process)
		ksawery.repository_process_close(&process)
		state.failure = publish_failure
		return true
	}
	if state.revision_sequence_result.state != nil {
		ksawery.revision_sequence_result_close(&state.revision_sequence_result)
	}
	state.revision_sequence_request = request
	state.process = process
	state.pending = .Revision_Sequence
	state.next_revision_sequence = operation + 1
	if state.next_revision_sequence == ksawery.Revision_Sequence_Operation_ID(0) {
		state.next_revision_sequence = 1
	}
	state.view_mode = request.precondition.action == .Start ? .History : .Sequence
	state.failure = .None
	return true
}

@(private)
dispatch_ksawery_revision_sequence_confirmation_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Revision_Sequence_Confirmation || state.process.state != nil {
		return {}, App_Failure{stage = .UI}
	}
	if input.kind == .Key && input.stroke.kind == .Unicode_Scalar &&
	   ((input.stroke.scalar == 'g' && input.stroke.modifiers == {.Control}) ||
	    (input.stroke.scalar == 'q' && input.stroke.modifiers == {})) {
		_ = ksawery_process_observation_finish_without_child(
			&state.process_coordinator, .Cancelled, .Cancelled_Before_Effect,
			"Sequenced revision confirmation cancelled", ksawery_workflow_now(commands),
		)
		state.revision_sequence_confirmation = {}
		state.revision_sequence_request = {}
		state.view_mode = state.revision_sequence_action == .Start ? .History : .Sequence
		state.failure = .Cancelled
		return Interaction_Result{changed = true}, {}
	}
	if input.kind == .Key && input.stroke.kind == .Enter && input.stroke.modifiers == {.Control} {
		return Interaction_Result{changed = ksawery_workflow_confirm_revision_sequence(commands)}, {}
	}
	return {}, {}
}

@(private)
ksawery_workflow_finish_revision_sequence_process :: proc(
	commands: ^Command_Context,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	if state == nil || state.pending != .Revision_Sequence do return {}, false
	result: ksawery.Revision_Sequence_Result
	opened := false
	failure := ksawery.Failure_Code.None
	if state.revision_sequence_family == .Cherry_Pick {
		result, opened, failure = ksawery.repository_process_take_cherry_pick(
			&state.process, commands.persistent_allocator,
		)
	} else if state.revision_sequence_family == .Revert {
		result, opened, failure = ksawery.repository_process_take_revert(
			&state.process, commands.persistent_allocator,
		)
	}
	succeeded := false
	if opened {
		if state.revision_sequence_result.state != nil {
			ksawery.revision_sequence_result_close(&state.revision_sequence_result)
		}
		state.revision_sequence_result = result
		descriptor, described := ksawery.revision_sequence_result_descriptor(&state.revision_sequence_result)
		succeeded = described && descriptor.process_succeeded
	}
	effect, prepared, prepare_failure := ksawery_process_operation_prepare_refresh(
		&state.process_coordinator, &state.process,
		"Refreshing Status, History, and Sequence after revision mutation",
		ksawery_workflow_now(commands),
	)
	if !prepared {
		_, _ = ksawery_process_observation_finish(
			&state.process_coordinator, &state.process, false,
			"Sequenced revision mutation could not refresh", ksawery_workflow_now(commands),
		)
		state.failure = prepare_failure
		return ksawery_workflow_sequence_outcome(), true
	}
	state.operation_effect = effect
	state.operation_verification = succeeded ? .Unavailable : .Known_Failure
	state.failure = failure if !opened else .None
	state.sequence_mutation_refresh = true
	state.sequence_mutation_conflict = false
	state.sequence_mutation_kind = state.revision_sequence_family == .Cherry_Pick ? .Cherry_Pick : .Revert
	state.view_mode = .Status
	return ksawery_workflow_sequence_outcome(.Start_Revision_Sequence_Refresh), true
}

@(private)
ksawery_workflow_verify_revision_sequence :: proc(
	state: ^Ksawery_Workflow_State,
) -> Ksawery_Repository_Verification_State {
	if state == nil || state.refs.state == nil || state.sequence.state == nil ||
	   state.revision_sequence_result.state == nil {
		return .Unavailable
	}
	result, result_ok := ksawery.revision_sequence_result_descriptor(&state.revision_sequence_result)
	refs, refs_ok := ksawery.ref_observation_descriptor(&state.refs)
	sequence, sequence_ok := ksawery.sequence_observation_descriptor(&state.sequence)
	if !result_ok || !refs_ok || !sequence_ok do return .Mismatch
	expected_kind := ksawery.Sequence_Kind.Cherry_Pick if
		result.request.precondition.family == .Cherry_Pick else .Revert
	if result.process_succeeded {
		if result.request.precondition.action == .Abort {
			return .Verified if sequence.state == .Inactive &&
				refs.head.object == result.request.precondition.original_head.revision else .Mismatch
		}
		return .Verified if sequence.state == .Inactive else .Mismatch
	}
	if result.failure == .Process_Failed && sequence.kind == expected_kind &&
	   (sequence.state == .Active || sequence.state == .Conflicted) {
		return .Known_Failure
	}
	return .Mismatch
}

@(private)
ksawery_revision_sequence_confirmation_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || viewport_items == 0 || allocator.procedure == nil ||
	   state.revision_sequence_confirmation.id == ksawery.Revision_Sequence_Confirmation_ID(0) ||
	   !ksawery.revision_sequence_precondition_is_valid(state.revision_sequence_confirmation.precondition) {
		return nil, nil, false
	}
	precondition := state.revision_sequence_confirmation.precondition
	row_count := min(int(precondition.selection.commits) + 8, int(ui.MAX_LIST_ITEMS))
	rows, rows_error := make([]ui.List_Item_Definition, row_count, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, row_count * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {delete(rows, allocator); return nil, nil, false}
	write := 0
	_ = ksawery_append_presented_label(rows, storage, &write, 0xDD00_0000_0000_0001,
		"Ksawery Sequenced Revision Confirmation", true, {surface = .Sequence, subject = .Section})
	_ = ksawery_append_presented_label(rows, storage, &write, 0xDD00_0000_0000_0002,
		fmt.tprintf("Action: %v %v", precondition.action, precondition.family), true,
		{surface = .Sequence, subject = .Operation, destructive = precondition.family == .Revert || precondition.action == .Abort})
	_ = ksawery_append_presented_label(rows, storage, &write, 0xDD00_0000_0000_0003,
		fmt.tprintf("Original HEAD: %s", ksawery.revision_identity_string(&precondition.original_head.revision)), true,
		{surface = .Sequence, subject = .Revision})
	for index in 0 ..< precondition.selection.commits {
		target, found := ksawery.revision_sequence_set_target(&state.revision_sequence_set, index)
		if !found do break
		label := fmt.tprintf("%d. %s", index + 1, ksawery.revision_identity_string(&target.revision))
		if target.mainline != {} {
			label = fmt.tprintf("%d. %s (mainline %d: %s)", index + 1,
				ksawery.revision_identity_string(&target.revision), target.mainline.number,
				ksawery.revision_identity_string(&target.mainline.parent))
		}
		_ = ksawery_append_presented_label(rows, storage, &write,
			ui.List_Item_ID(0xDD10_0000_0000_0000 | u64(index + 1)), label, true,
			{surface = .Sequence, subject = .Revision})
	}
	_ = ksawery_append_presented_label(rows, storage, &write, 0xDD00_0000_0000_0004,
		"C-Enter confirms this exact ordered action; C-g cancels.", false,
		{surface = .Sequence, subject = .Operation, destructive = true})
	definitions = rows[:write]
	state.position = {presentation_generation = 1, selection_owner = .View, current_item = i32(write - 1),
		first_visible_item = 0, viewport_items = min(viewport_items, u32(write))}
	return definitions, storage, true
}
