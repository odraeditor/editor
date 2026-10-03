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
ksawery_workflow_clear_rebase_preparation :: proc(state: ^Ksawery_Workflow_State, clear_plan := false) {
	if state == nil do return
	state.rebase_action = .Invalid
	state.rebase_confirmation = {}
	state.rebase_request = {}
	if clear_plan && state.rebase_plan.state != nil do ksawery.rebase_plan_close(&state.rebase_plan)
	if clear_plan {
		state.rebase_mode = .Invalid
		state.rebase_precondition = {}
	}
}

@(private)
ksawery_workflow_rebase_editor_state :: proc(
	commands: ^Command_Context,
) -> (ksawery.Rebase_Editor_State, bool) {
	branch_state, inspected := ksawery_workflow_branch_editor_state(commands)
	if !inspected do return {}, false
	return {
		repository_resources = branch_state.repository_resources,
		modified_repository_resources = branch_state.modified_repository_resources,
	}, true
}

@(private)
ksawery_workflow_selected_rebase_base :: proc(
	state: ^Ksawery_Workflow_State,
) -> (ksawery.Ref_Identity, bool) {
	if state == nil || state.refs.state == nil ||
	   !ksawery.ref_selection_is_current(&state.refs, state.ref_selection) ||
	   state.ref_selection.current.kind != .Ref {
		return {}, false
	}
	base := state.ref_selection.current.reference
	if base.object_type != .Commit ||
	   (base.kind != .Local_Branch && base.kind != .Remote_Tracking_Branch && base.kind != .Tag) {
		return {}, false
	}
	return base, true
}

@(private)
ksawery_workflow_rebase_plan :: proc(
	state: ^Ksawery_Workflow_State,
	old_tip: ksawery.Revision_Identity,
	upstream: ksawery.Revision_Identity,
	allocator: runtime.Allocator,
) -> (ksawery.Rebase_Plan, bool, ksawery.Failure_Code) {
	if state == nil || state.history.state == nil || allocator.procedure == nil do return {}, false, .Invalid_Request
	descriptor, described := ksawery.history_observation_descriptor(&state.history)
	count, counted := ksawery.history_observation_revision_count(&state.history)
	if !described || !counted || descriptor.repository != state.repository || descriptor.head != old_tip || count == 0 {
		return {}, false, .Stale_Observation
	}
	commits, allocation_error := make([]ksawery.Rebase_Plan_Commit, int(count), allocator)
	if allocation_error != nil do return {}, false, .Allocation
	defer delete(commits, allocator)
	current := old_tip
	write := 0
	for current != upstream {
		entry: ksawery.Revision_Entry
		found := false
		for index in 0 ..< count {
			candidate, available := ksawery.history_observation_revision(&state.history, index)
			if available && candidate.identity == current {
				entry = candidate
				found = true
				break
			}
		}
		if !found do return {}, false, .History_Limit
		if entry.parent_count != 1 do return {}, false, .Action_Unavailable
		subject, copied := ksawery.history_observation_text(&state.history, entry.subject)
		if !copied do return {}, false, .Parse
		commits[write] = {revision = entry.identity, subject = string(subject)}
		write += 1
		current = entry.parents[0]
	}
	if write == 0 do return {}, false, .Target_Duplicate
	for left, right := 0, write - 1; left < right; left, right = left + 1, right - 1 {
		commits[left], commits[right] = commits[right], commits[left]
	}
	return ksawery.rebase_plan_project(
		commits[:write], old_tip, upstream, ksawery.DEFAULT_REBASE_PLAN_LIMITS, state.allocator,
	)
}

@(private)
ksawery_workflow_rebase_step :: proc(
	state: ^Ksawery_Workflow_State,
) -> (ksawery.Rebase_Replay_Step, bool) {
	if state == nil || state.sequence.state == nil do return {}, false
	descriptor, described := ksawery.sequence_observation_descriptor(&state.sequence)
	if !described || descriptor.kind != .Rebase || descriptor.step == {} || descriptor.target == {} {
		return {}, false
	}
	step := ksawery.Rebase_Replay_Step {
		position = descriptor.step.position,
		total = descriptor.step.total,
		action = .Pick,
		revision = descriptor.target,
	}
	if state.rebase_mode == .Autosquash {
		plan_descriptor, plan_described := ksawery.rebase_plan_descriptor(&state.rebase_plan)
		if !plan_described || plan_descriptor.state != .Available do return {}, false
		matched := false
		for index in 0 ..< plan_descriptor.step_count {
			candidate, found := ksawery.rebase_plan_step(&state.rebase_plan, index)
			if found && candidate.revision == descriptor.target {
				step.action = candidate.action
				step.target = candidate.target
				matched = true
				break
			}
		}
		if !matched do return {}, false
	}
	return step, ksawery.rebase_replay_step_is_valid(step)
}

@(private)
ksawery_workflow_begin_rebase :: proc(
	commands: ^Command_Context,
	action: ksawery.Rebase_Action,
	mode := ksawery.Rebase_Mode.Invalid,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.observation.state == nil || state.refs.state == nil ||
	   state.sequence.state == nil || state.process.state != nil {
		return false
	}
	base: ksawery.Ref_Identity
	plan: ksawery.Rebase_Reviewed_Plan
	step: ksawery.Rebase_Replay_Step
	lineage: ksawery.Rebase_Precondition
	selected_mode := mode
	if action == .Start {
		if state.view_mode != .Refs {
			state.failure = .Action_Unavailable
			command_context_set_diagnostic(commands, "Open Refs and select one exact commit-backed rebase base")
			return true
		}
		available := false
		base, available = ksawery_workflow_selected_rebase_base(state)
		if !available {
			state.failure = .Ref_Unavailable
			command_context_set_diagnostic(commands, "Select one exact commit-backed branch or tag as the rebase base")
			return true
		}
		ksawery_workflow_clear_rebase_preparation(state, true)
		if mode == .Autosquash {
			refs_descriptor, refs_described := ksawery.ref_observation_descriptor(&state.refs)
			if !refs_described || refs_descriptor.head.state != .Symbolic {
				state.failure = .Action_Unavailable
				return true
			}
			projected, opened, projection_failure := ksawery_workflow_rebase_plan(
				state, refs_descriptor.head.object, base.object, commands.temporary_allocator,
			)
			if !opened {
				state.failure = projection_failure
				command_context_set_diagnostic(commands, "A complete bounded History page is required for autosquash review")
				return true
			}
			plan_descriptor, plan_described := ksawery.rebase_plan_descriptor(&projected)
			if !plan_described || plan_descriptor.state != .Available {
				ksawery.rebase_plan_close(&projected)
				state.failure = .Action_Unavailable
				command_context_set_diagnostic(commands, "The autosquash plan is ambiguous, unsupported, or truncated")
				return true
			}
			accepted, accepted_ok, accept_failure := ksawery.rebase_plan_accept(&projected)
			if !accepted_ok {
				ksawery.rebase_plan_close(&projected)
				state.failure = accept_failure
				return true
			}
			state.rebase_plan = projected
			plan = accepted
		}
	} else {
		if state.view_mode != .Sequence || !ksawery.rebase_precondition_is_valid(state.rebase_precondition) ||
		   state.rebase_precondition.action != .Start {
			state.failure = .Action_Unavailable
			command_context_set_diagnostic(commands, "No retained checked rebase lineage is available for this sequence")
			return true
		}
		lineage = state.rebase_precondition
		selected_mode = lineage.mode
		step_ready := false
		step, step_ready = ksawery_workflow_rebase_step(state)
		if !step_ready {
			state.failure = .Stale_Observation
			return true
		}
	}
	editor_state, inspected := ksawery_workflow_rebase_editor_state(commands)
	if !inspected {
		state.failure = .Presentation_Unavailable
		return true
	}
	if editor_state.modified_repository_resources != 0 {
		state.failure = .Modified_Buffer
		command_context_set_diagnostic(commands, "Save repository buffers before preparing this rebase action")
		return true
	}
	process, started, failure := ksawery.repository_process_start_rebase_precondition(
		&state.observation,
		&state.refs,
		&state.sequence,
		base,
		action,
		selected_mode,
		plan,
		lineage,
		step,
		editor_state,
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
	)
	if !started {
		state.failure = failure
		command_context_set_diagnostic(commands, "Checked rebase preconditions are unavailable")
		return true
	}
	kind := ksawery.Repository_Operation_Kind.Rebase
	title := "Rebase Repository Branch"
	if action == .Continue {
		kind = .Continue_Rebase
		title = "Continue Repository Rebase"
	} else if action == .Skip {
		kind = .Skip_Rebase
		title = "Skip Repository Rebase Step"
	} else if action == .Abort {
		kind = .Abort_Rebase
		title = "Abort Repository Rebase"
	}
	recorded, record_failure := ksawery_process_observation_begin(
		&state.process_coordinator,
		&process,
		state.process_coordinator.confirmed_observation,
		{
			kind = kind,
			target_kind = .Repository,
			title = title,
			target = ksawery.repository_context_string(&state.repository),
			phase_detail = "Checking rebase preconditions",
			checking = true,
		},
		ksawery_workflow_now(commands),
	)
	if !recorded {
		ksawery.repository_process_close(&process)
		state.failure = record_failure
		return true
	}
	state.rebase_mode = selected_mode
	state.rebase_action = action
	state.process = process
	state.pending = .Rebase_Precondition
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_prepare_rebase_confirmation :: proc(
	commands: ^Command_Context,
	precondition: ksawery.Rebase_Precondition,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil do return false
	id := state.next_rebase_confirmation
	if id == ksawery.Rebase_Confirmation_ID(0) do id = 1
	confirmation, prepared, failure := ksawery.rebase_confirmation_prepare(precondition, id)
	if !prepared {
		state.failure = failure
		return true
	}
	if precondition.action == .Start do state.rebase_precondition = precondition
	state.rebase_confirmation = confirmation
	state.next_rebase_confirmation = id + 1
	if state.next_rebase_confirmation == ksawery.Rebase_Confirmation_ID(0) do state.next_rebase_confirmation = 1
	state.view_mode = .Rebase_Confirmation
	state.position = {}
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_confirm_rebase :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Rebase_Confirmation || state.process.state != nil do return false
	confirmed, confirmation_failure := ksawery.rebase_confirmation_confirm(
		&state.rebase_confirmation,
		state.rebase_confirmation.id,
	)
	if !confirmed {
		state.failure = confirmation_failure
		return true
	}
	operation := state.next_rebase
	if operation == ksawery.Rebase_Operation_ID(0) do operation = 1
	request, prepared, failure := ksawery.rebase_request_prepare(
		state.rebase_confirmation.precondition,
		operation,
		&state.rebase_confirmation,
	)
	if !prepared {
		state.failure = failure
		return true
	}
	process, started, start_failure := ksawery.repository_process_start_rebase(
		&state.sequence,
		request.precondition,
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
		"Applying checked rebase action", true, ksawery_workflow_now(commands),
	)
	if !published {
		_, _ = ksawery_process_operation_detach_child(&state.process_coordinator, &process)
		ksawery.repository_process_close(&process)
		state.failure = publish_failure
		return true
	}
	if state.rebase_result.state != nil do ksawery.rebase_result_close(&state.rebase_result)
	state.rebase_request = request
	state.process = process
	state.pending = .Rebase
	state.next_rebase = operation + 1
	if state.next_rebase == ksawery.Rebase_Operation_ID(0) do state.next_rebase = 1
	state.view_mode = request.precondition.action == .Start ? .Refs : .Sequence
	state.failure = .None
	return true
}

@(private)
dispatch_ksawery_rebase_confirmation_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Rebase_Confirmation || state.process.state != nil {
		return {}, App_Failure{stage = .UI}
	}
	if input.kind == .Key && input.stroke.kind == .Unicode_Scalar &&
	   ((input.stroke.scalar == 'g' && input.stroke.modifiers == {.Control}) ||
	    (input.stroke.scalar == 'q' && input.stroke.modifiers == {})) {
		_ = ksawery_process_observation_finish_without_child(
			&state.process_coordinator, .Cancelled, .Cancelled_Before_Effect,
			"Rebase confirmation cancelled", ksawery_workflow_now(commands),
		)
		return_mode := state.rebase_action == .Start ? Ksawery_View_Mode.Refs : .Sequence
		ksawery_workflow_clear_rebase_preparation(state, state.rebase_action == .Start)
		state.view_mode = return_mode
		state.failure = .Cancelled
		return Interaction_Result{changed = true}, {}
	}
	if input.kind == .Key && input.stroke.kind == .Enter && input.stroke.modifiers == {.Control} {
		return Interaction_Result{changed = ksawery_workflow_confirm_rebase(commands)}, {}
	}
	return {}, {}
}

@(private)
ksawery_workflow_finish_rebase_precondition :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	if state == nil || state.pending != .Rebase_Precondition do return {}, false
	precondition, opened, failure := ksawery.repository_process_take_rebase_precondition(&state.process)
	if !opened {
		_, _ = ksawery_process_observation_finish(
			&state.process_coordinator, &state.process, false,
			"Repository rebase precondition failed", ksawery_workflow_now(commands),
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
		"Waiting for exact rebase confirmation", false, ksawery_workflow_now(commands),
	)
	state.rebase_precondition = precondition
	return ksawery_workflow_sequence_outcome(.Prepare_Rebase_Confirmation), true
}

@(private)
ksawery_rebase_confirmation_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || viewport_items == 0 || allocator.procedure == nil ||
	   state.rebase_confirmation.id == ksawery.Rebase_Confirmation_ID(0) ||
	   !ksawery.rebase_precondition_is_valid(state.rebase_confirmation.precondition) {
		return nil, nil, false
	}
	plan_rows := 0
	plan_descriptor, plan_described := ksawery.rebase_plan_descriptor(&state.rebase_plan)
	if state.rebase_mode == .Autosquash && plan_described do plan_rows = int(plan_descriptor.step_count)
	row_count := min(8 + plan_rows, int(ui.MAX_LIST_ITEMS))
	rows, rows_error := make([]ui.List_Item_Definition, row_count, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, row_count * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {delete(rows, allocator); return nil, nil, false}
	write := 0
	precondition := state.rebase_confirmation.precondition
	_ = ksawery_append_presented_label(rows, storage, &write, 0xDC00_0000_0000_0001,
		"Ksawery Rebase Confirmation", true, {surface = .Sequence, subject = .Section})
	_ = ksawery_append_presented_label(rows, storage, &write, 0xDC00_0000_0000_0002,
		fmt.tprintf("Action: %v (%v)", precondition.action, precondition.mode), true,
		{surface = .Sequence, subject = .Operation, destructive = true})
	_ = ksawery_append_presented_label(rows, storage, &write, 0xDC00_0000_0000_0003,
		fmt.tprintf("Branch: %s", ksawery.ref_name_string(&precondition.branch.name)), true,
		{surface = .Sequence, subject = .Branch})
	_ = ksawery_append_presented_label(rows, storage, &write, 0xDC00_0000_0000_0004,
		fmt.tprintf("Old tip: %s", ksawery.revision_identity_string(&precondition.old_tip)), true,
		{surface = .Sequence, subject = .Revision})
	_ = ksawery_append_presented_label(rows, storage, &write, 0xDC00_0000_0000_0005,
		fmt.tprintf("Base: %s", ksawery.revision_identity_string(&precondition.base.revision)), true,
		{surface = .Sequence, subject = .Revision})
	if precondition.mode == .Autosquash && plan_described {
		for index in 0 ..< plan_descriptor.step_count {
			if write >= len(rows) - 1 do break
			step, found := ksawery.rebase_plan_step(&state.rebase_plan, index)
			subject, copied := ksawery.rebase_plan_subject(&state.rebase_plan, step.subject)
			if !found || !copied do break
			_ = ksawery_append_presented_label(
				rows, storage, &write, ui.List_Item_ID(0xDC10_0000_0000_0000 | u64(index + 1)),
				fmt.tprintf("%d. %v %s", step.position, step.action, subject), true,
				{surface = .Sequence, subject = .Step},
			)
		}
	}
	_ = ksawery_append_presented_label(rows, storage, &write, 0xDC00_0000_0000_0006,
		"C-Enter confirms this exact history rewrite; C-g cancels.", false,
		{surface = .Sequence, subject = .Operation, destructive = true})
	definitions = rows[:write]
	state.position = {presentation_generation = 1, selection_owner = .View, current_item = i32(write - 1),
		first_visible_item = 0, viewport_items = min(viewport_items, u32(write))}
	return definitions, storage, true
}
