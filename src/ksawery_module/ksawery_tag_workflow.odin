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
ksawery_workflow_selected_tag_target :: proc(
	state: ^Ksawery_Workflow_State,
	operation: ksawery.Tag_Operation,
) -> (ksawery.Ref_Identity, bool) {
	if state == nil || state.refs.state == nil ||
	   !ksawery.ref_selection_is_current(&state.refs, state.ref_selection) ||
	   state.ref_selection.current.kind != .Ref {
		return {}, false
	}
	target := state.ref_selection.current.reference
	if operation == .Create && target.object_type == .Commit do return target, true
	if operation == .Delete && target.kind == .Tag do return target, true
	return {}, false
}

@(private)
ksawery_workflow_current_tag_operation :: proc(
	state: ^Ksawery_Workflow_State,
) -> ksawery.Tag_Operation_ID {
	if state == nil || state.next_tag == ksawery.Tag_Operation_ID(0) {
		return ksawery.Tag_Operation_ID(1)
	}
	return state.next_tag
}

@(private)
ksawery_workflow_clear_tag_preparation :: proc(state: ^Ksawery_Workflow_State) {
	if state == nil do return
	state.tag_intent = {}
	state.tag_precondition = {}
	state.tag_confirmation = {}
	state.tag_request = {}
	state.tag_draft = {}
	state.tag_draft_length = 0
}

@(private)
ksawery_workflow_begin_tag :: proc(
	commands: ^Command_Context,
	operation: ksawery.Tag_Operation,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Refs || state.refs.state == nil ||
	   state.observation.state == nil || state.process.state != nil {
		return false
	}
	target, available := ksawery_workflow_selected_tag_target(state, operation)
	if !available {
		state.failure = .Ref_Unavailable
		message := "Select one exact commit-backed ref"
		if operation == .Delete do message = "Select one exact local tag"
		command_context_set_diagnostic(commands, message)
		return true
	}
	ksawery_workflow_clear_tag_preparation(state)
	state.tag_intent = {operation = operation, target = target}
	if operation == .Create {
		state.view_mode = .Tag_Name
		state.position = {}
		state.failure = .None
		return true
	}
	return ksawery_workflow_prepare_tag_confirmation(commands, state.tag_intent)
}

@(private)
ksawery_workflow_prepare_tag_confirmation :: proc(
	commands: ^Command_Context,
	intent: ksawery.Tag_Intent,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.refs.state == nil || state.observation.state == nil ||
	   state.process.state != nil {
		return false
	}
	precondition, prepared, failure := ksawery.tag_precondition_prepare(
		&state.observation,
		&state.refs,
		intent,
	)
	if !prepared {
		state.failure = failure
		state.view_mode = .Refs
		command_context_set_diagnostic(commands, ksawery_workflow_tag_rejection_text(intent.operation, failure))
		return true
	}
	confirmation_id := state.next_tag_confirmation
	if confirmation_id == ksawery.Tag_Confirmation_ID(0) {
		confirmation_id = ksawery.Tag_Confirmation_ID(1)
	}
	confirmation, confirmation_ready, confirmation_failure := ksawery.tag_confirmation_prepare(
		precondition,
		confirmation_id,
	)
	if !confirmation_ready {
		state.failure = confirmation_failure
		state.view_mode = .Refs
		command_context_set_diagnostic(commands, "Exact local tag confirmation could not be prepared")
		return true
	}
	state.tag_intent = intent
	state.tag_precondition = precondition
	state.tag_confirmation = confirmation
	state.next_tag_confirmation = confirmation_id + 1
	if state.next_tag_confirmation == ksawery.Tag_Confirmation_ID(0) {
		state.next_tag_confirmation = ksawery.Tag_Confirmation_ID(1)
	}
	state.view_mode = .Tag_Confirmation
	state.position = {}
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_tag_rejection_text :: proc(
	operation: ksawery.Tag_Operation,
	failure: ksawery.Failure_Code,
) -> string {
	if operation == .Create && failure == .Target_Duplicate {
		return "The requested local tag name already exists"
	}
	if failure == .Action_Unavailable {
		return "Local tag operations require normal repository state and commit-backed targets"
	}
	return "The selected local tag operation is unavailable"
}

@(private)
ksawery_workflow_tag_name_append :: proc(state: ^Ksawery_Workflow_State, text: string) -> bool {
	if state == nil || len(text) == 0 ||
	   int(state.tag_draft_length) + len(text) > len(state.tag_draft) {
		return false
	}
	for byte in transmute([]u8)text {
		if byte == 0 || byte == '\n' || byte == '\r' do return false
	}
	start := int(state.tag_draft_length)
	copy(state.tag_draft[start:], transmute([]u8)text)
	state.tag_draft_length += u16(len(text))
	return true
}

@(private)
ksawery_workflow_tag_name_delete_previous :: proc(state: ^Ksawery_Workflow_State) -> bool {
	if state == nil || state.tag_draft_length == 0 do return false
	start := int(state.tag_draft_length) - 1
	for start > 0 && state.tag_draft[start] & 0xc0 == 0x80 do start -= 1
	state.tag_draft_length = u16(start)
	return true
}

@(private)
ksawery_workflow_finalize_tag_name :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Tag_Name || state.process.state != nil do return false
	name: ksawery.Local_Tag_Name
	if !ksawery.local_tag_name_assign(
		&name,
		string(state.tag_draft[:state.tag_draft_length]),
	) {
		state.failure = .Invalid_Request
		command_context_set_diagnostic(commands, "Local tag name is invalid")
		return true
	}
	intent := state.tag_intent
	intent.name = name
	return ksawery_workflow_prepare_tag_confirmation(commands, intent)
}

@(private)
dispatch_ksawery_tag_name_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Tag_Name || state.process.state != nil {
		return {}, App_Failure{stage = .UI}
	}
	if input.kind == .Key && input.stroke.kind == .Unicode_Scalar &&
	   input.stroke.scalar == 'g' && input.stroke.modifiers == {.Control} {
		ksawery_workflow_clear_tag_preparation(state)
		state.view_mode = .Refs
		state.failure = .Cancelled
		command_context_set_diagnostic(commands, "Local tag naming cancelled")
		return Interaction_Result{changed = true}, {}
	}
	if input.kind == .Key && input.stroke.kind == .Enter && input.stroke.modifiers == {} {
		return Interaction_Result{changed = ksawery_workflow_finalize_tag_name(commands)}, {}
	}
	if input.kind == .Key && (input.stroke.kind == .Backspace || input.stroke.kind == .Delete) {
		return Interaction_Result{changed = ksawery_workflow_tag_name_delete_previous(state)}, {}
	}
	if (input.kind == .Text_Commit || input.kind == .Key) && len(input.text) > 0 &&
	   input.stroke.modifiers == {} {
		if ksawery_workflow_tag_name_append(state, input.text) {
			state.failure = .None
			return Interaction_Result{changed = true}, {}
		}
		state.failure = .Invalid_Request
		command_context_set_diagnostic(commands, "Local tag name rejected invalid or oversized text")
		return Interaction_Result{changed = true}, {}
	}
	return {}, {}
}

@(private)
dispatch_ksawery_tag_confirmation_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Tag_Confirmation || state.process.state != nil {
		return {}, App_Failure{stage = .UI}
	}
	if input.kind == .Key && input.stroke.kind == .Unicode_Scalar &&
	   ((input.stroke.scalar == 'g' && input.stroke.modifiers == {.Control}) ||
	    (input.stroke.scalar == 'q' && input.stroke.modifiers == {})) {
		ksawery_workflow_clear_tag_preparation(state)
		state.view_mode = .Refs
		state.failure = .Cancelled
		command_context_set_diagnostic(commands, "Local tag confirmation cancelled")
		return Interaction_Result{changed = true}, {}
	}
	if input.kind == .Key && input.stroke.kind == .Enter && input.stroke.modifiers == {.Control} {
		return Interaction_Result{changed = ksawery_workflow_confirm_tag(commands)}, {}
	}
	return {}, {}
}

@(private)
ksawery_workflow_confirm_tag :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Tag_Confirmation || state.process.state != nil do return false
	confirmed, confirmation_failure := ksawery.tag_confirmation_confirm(
		&state.tag_confirmation,
		state.tag_confirmation.id,
	)
	if !confirmed {
		state.failure = confirmation_failure
		command_context_set_diagnostic(commands, "Exact local tag confirmation was rejected")
		return true
	}
	operation := ksawery_workflow_current_tag_operation(state)
	request, prepared, failure := ksawery.tag_request_prepare(
		state.tag_precondition,
		operation,
		&state.tag_confirmation,
	)
	if !prepared {
		state.failure = failure
		state.view_mode = .Refs
		command_context_set_diagnostic(commands, "Confirmed local tag request was rejected")
		return true
	}
	process, started, start_failure := ksawery.repository_process_start_tag(
		&state.observation,
		&state.refs,
		request,
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
	)
	if !started {
		state.failure = start_failure
		state.view_mode = .Refs
		command_context_set_diagnostic(commands, "Checked local tag operation could not start")
		return true
	}
	kind := ksawery.Repository_Operation_Kind.Create_Tag
	title := "Create Local Tag"
	if request.precondition.intent.operation == .Delete {
		kind = .Delete_Tag
		title = "Delete Local Tag"
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
			phase_detail = "Applying local tag operation",
		},
		ksawery_workflow_now(commands),
	)
	if !recorded {
		ksawery.repository_process_close(&process)
		state.failure = record_failure
		state.view_mode = .Refs
		command_context_set_diagnostic(commands, "Checked local tag operation could not start")
		return true
	}
	if state.tag_result.state != nil do ksawery.tag_result_close(&state.tag_result)
	if state.branch_result.state != nil do ksawery.branch_result_close(&state.branch_result)
	if state.fetch_result.state != nil do ksawery.fetch_result_close(&state.fetch_result)
	if state.push_result.state != nil do ksawery.push_result_close(&state.push_result)
	state.tag_request = request
	state.process = process
	state.pending = .Tag
	state.view_mode = .Refs
	state.next_tag = operation + 1
	if state.next_tag == ksawery.Tag_Operation_ID(0) {
		state.next_tag = ksawery.Tag_Operation_ID(1)
	}
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_finish_tag_refresh :: proc(
	commands: ^Command_Context,
	refresh_failed: bool,
) {
	state := commands.ksawery_workflow
	if state == nil do return
	descriptor, described := ksawery.tag_result_descriptor(&state.tag_result)
	verification := Ksawery_Repository_Verification_State.Unavailable
	if !refresh_failed && described {
		verification = .Verified if descriptor.succeeded else .Known_Failure
	}
	message := "Local tag operation verified"
	if verification == .Known_Failure do message = "Local tag operation failed"
	if verification == .Unavailable do message = "Local tag operation outcome is indeterminate"
	ksawery_workflow_finish_synchronization_record(commands, verification, message)
	state.tag_refresh = .None
	state.view_mode = .Refs
	ksawery_workflow_clear_tag_preparation(state)
	if refresh_failed {
		state.failure = .Process_Failed
		command_context_set_diagnostic(commands, "Local tag operation finished, but repository refresh failed")
		return
	}
	if !described {
		state.failure = .Process_Failed
		command_context_set_diagnostic(commands, "Local tag result was unavailable")
		return
	}
	state.failure = descriptor.failure if !descriptor.succeeded else .None
	#partial switch ksawery.tag_feedback(descriptor) {
	case .Completed:
		command_context_set_diagnostic(commands, "Local tag operation completed")
	case .Cancelled:
		command_context_set_diagnostic(commands, "Local tag operation cancelled")
	case .Stale:
		command_context_set_diagnostic(commands, "Local tag operation result is stale")
	case:
		command_context_set_diagnostic(commands, "Local tag operation failed")
	}
}

@(private)
ksawery_tag_name_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || viewport_items == 0 || allocator.procedure == nil ||
	   state.tag_intent.operation != .Create {
		return nil, nil, false
	}
	rows, rows_error := make([]ui.List_Item_Definition, 7, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, len(rows) * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {
		delete(rows, allocator)
		return nil, nil, false
	}
	write := 0
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xD600_0000_0000_0001, "Ksawery Create Local Tag", true,
		{surface = .Refs, subject = .Section},
	)
	target := state.tag_intent.target
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xD600_0000_0000_0002,
		fmt.tprintf("Target: %s %s", ksawery.ref_name_string(&target.name), ksawery.revision_identity_string(&target.object)),
		true, {surface = .Refs, subject = .Tag, current = true},
	)
	label := "Name: "
	if state.tag_draft_length > 0 {
		label = fmt.tprintf("Name: %s", string(state.tag_draft[:state.tag_draft_length]))
	}
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xD600_0000_0000_0003, label, false,
		{surface = .Refs, subject = .Tag, current = true},
	)
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xD600_0000_0000_0004,
		"Enter prepares exact confirmation; C-g cancels.", true,
		{surface = .Refs, subject = .Operation},
	)
	if state.failure != .None {
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xD600_0000_0000_0005,
			fmt.tprintf("Tag name feedback: %v", state.failure), true,
			{surface = .Refs, subject = .Failure, destructive = true},
		)
	}
	definitions = rows[:write]
	current_item := i32(-1)
	for definition, index in definitions {
		if !definition.passive {
			current_item = i32(index)
			break
		}
	}
	state.position = {presentation_generation = 1, selection_owner = .View, current_item = current_item,
		first_visible_item = 0, viewport_items = min(viewport_items, u32(write))}
	return definitions, storage, true
}

@(private)
ksawery_tag_confirmation_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || viewport_items == 0 || allocator.procedure == nil ||
	   !ksawery.tag_precondition_is_valid(state.tag_precondition) {
		return nil, nil, false
	}
	rows, rows_error := make([]ui.List_Item_Definition, 10, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, len(rows) * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {
		delete(rows, allocator)
		return nil, nil, false
	}
	precondition := state.tag_precondition
	intent := precondition.intent
	write := 0
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xD700_0000_0000_0001, "Ksawery Local Tag Confirmation", true,
		{surface = .Refs, subject = .Section},
	)
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xD700_0000_0000_0002,
		fmt.tprintf("Operation: %v", intent.operation), true,
		{surface = .Refs, subject = .Operation, destructive = intent.operation == .Delete},
	)
	target := intent.target
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xD700_0000_0000_0003,
		fmt.tprintf("Target: %s %s", ksawery.ref_name_string(&target.name), ksawery.revision_identity_string(&target.object)),
		true, {surface = .Refs, subject = .Tag, current = true, destructive = intent.operation == .Delete},
	)
	if intent.name != {} {
		name := intent.name
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xD700_0000_0000_0004,
			fmt.tprintf("New tag: %s", ksawery.local_tag_name_string(&name)), true,
			{surface = .Refs, subject = .Tag},
		)
	}
	boundary := "Creates one lightweight local tag at the exact selected commit; no signing or remote mutation."
	if intent.operation == .Delete {
		boundary = "Deletes only the exact selected local tag; no force or remote mutation."
	}
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xD700_0000_0000_0005, boundary, true,
		{surface = .Refs, subject = .Failure, destructive = intent.operation == .Delete},
	)
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xD700_0000_0000_0006,
		"C-Enter confirms this exact operation; C-g cancels.", false,
		{surface = .Refs, subject = .Operation},
	)
	definitions = rows[:write]
	state.position = {presentation_generation = 1, selection_owner = .View, current_item = i32(write - 1),
		first_visible_item = 0, viewport_items = min(viewport_items, u32(write))}
	return definitions, storage, true
}
