// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import "../interaction"
import "../ksawery"
import "../product_module"
import "../ui"
import "base:runtime"
import "core:fmt"

@(private)
ksawery_workflow_branch_editor_state :: proc(
	commands: ^Command_Context,
) -> (ksawery.Branch_Editor_State, bool) {
	if commands == nil || commands.host.call == nil || commands.ksawery_workflow == nil do return {}, false
	repository := ksawery.repository_context_string(&commands.ksawery_workflow.repository)
	inspection, inspected := host_session_request(
		&commands.host,
		.Inspect_Documents,
		0,
		product_module.SESSION_PATH_PREFIX,
		repository,
	)
	if !inspected || inspection.total > ksawery.MAX_BRANCH_EDITOR_RESOURCES do return {}, false
	result := ksawery.Branch_Editor_State {
		repository_resources = inspection.total,
		modified_repository_resources = inspection.modified,
	}
	return result, ksawery.branch_editor_state_is_valid(result)
}

@(private)
ksawery_workflow_selected_local_branch :: proc(
	state: ^Ksawery_Workflow_State,
) -> (ksawery.Ref_Identity, bool) {
	if state == nil || state.refs.state == nil ||
	   !ksawery.ref_selection_is_current(&state.refs, state.ref_selection) ||
	   state.ref_selection.current.kind != .Ref ||
	   state.ref_selection.current.reference.kind != .Local_Branch {
		return {}, false
	}
	return state.ref_selection.current.reference, true
}

@(private)
ksawery_workflow_current_branch_operation :: proc(
	state: ^Ksawery_Workflow_State,
) -> ksawery.Branch_Operation_ID {
	if state == nil || state.next_branch == ksawery.Branch_Operation_ID(0) {
		return ksawery.Branch_Operation_ID(1)
	}
	return state.next_branch
}

@(private)
ksawery_workflow_clear_branch_preparation :: proc(state: ^Ksawery_Workflow_State) {
	if state == nil do return
	state.branch_intent = {}
	state.branch_precondition = {}
	state.branch_confirmation = {}
	state.branch_request = {}
	state.branch_draft = {}
	state.branch_draft_length = 0
}

@(private)
ksawery_workflow_begin_branch :: proc(
	commands: ^Command_Context,
	operation: ksawery.Branch_Operation,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Refs || state.refs.state == nil ||
	   state.observation.state == nil || state.process.state != nil {
		return false
	}
	selected: ksawery.Ref_Identity
	if operation != .Create {
		available := false
		selected, available = ksawery_workflow_selected_local_branch(state)
		if !available {
			state.failure = .Ref_Unavailable
			command_context_set_diagnostic(commands, "Select one exact local branch")
			return true
		}
	}
	ksawery_workflow_clear_branch_preparation(state)
	state.branch_intent = {
		operation = operation,
		selected = selected,
		require_merged_to_head = operation == .Delete,
	}
	if operation == .Create || operation == .Rename {
		state.view_mode = .Branch_Name
		state.position = {}
		state.failure = .None
		return true
	}
	return ksawery_workflow_prepare_branch_confirmation(commands, state.branch_intent)
}

@(private)
ksawery_workflow_prepare_branch_confirmation :: proc(
	commands: ^Command_Context,
	intent: ksawery.Branch_Intent,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.refs.state == nil || state.observation.state == nil ||
	   state.process.state != nil {
		return false
	}
	editor_state, inspected := ksawery_workflow_branch_editor_state(commands)
	if !inspected {
		state.failure = .Presentation_Unavailable
		state.view_mode = .Refs
		command_context_set_diagnostic(commands, "Repository-associated editor resources could not be checked")
		return true
	}
	precondition, prepared, failure := ksawery.branch_precondition_prepare(
		&state.observation,
		&state.refs,
		editor_state,
		intent,
	)
	if !prepared {
		state.failure = failure
		state.view_mode = .Refs
		command_context_set_diagnostic(commands, ksawery_workflow_branch_rejection_text(intent.operation, failure))
		return true
	}
	confirmation_id := state.next_branch_confirmation
	if confirmation_id == ksawery.Branch_Confirmation_ID(0) {
		confirmation_id = ksawery.Branch_Confirmation_ID(1)
	}
	confirmation, confirmation_ready, confirmation_failure := ksawery.branch_confirmation_prepare(
		precondition,
		confirmation_id,
	)
	if !confirmation_ready {
		state.failure = confirmation_failure
		state.view_mode = .Refs
		command_context_set_diagnostic(commands, "Exact local branch confirmation could not be prepared")
		return true
	}
	state.branch_intent = intent
	state.branch_precondition = precondition
	state.branch_confirmation = confirmation
	state.next_branch_confirmation = confirmation_id + 1
	if state.next_branch_confirmation == ksawery.Branch_Confirmation_ID(0) {
		state.next_branch_confirmation = ksawery.Branch_Confirmation_ID(1)
	}
	state.view_mode = .Branch_Confirmation
	state.position = {}
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_branch_rejection_text :: proc(
	operation: ksawery.Branch_Operation,
	failure: ksawery.Failure_Code,
) -> string {
	if operation == .Switch && failure == .Modified_Buffer {
		return "Branch switching is unavailable while a repository buffer is modified"
	}
	if operation == .Switch && failure == .Action_Unavailable {
		return "Branch switching requires a clean worktree and index"
	}
	if operation == .Delete && failure == .Action_Unavailable {
		return "The current or unmerged local branch cannot be deleted"
	}
	if failure == .Target_Duplicate do return "The requested local branch name already exists"
	return "The selected local branch operation is unavailable"
}

@(private)
ksawery_workflow_branch_name_append :: proc(state: ^Ksawery_Workflow_State, text: string) -> bool {
	if state == nil || len(text) == 0 ||
	   int(state.branch_draft_length) + len(text) > len(state.branch_draft) {
		return false
	}
	for byte in transmute([]u8)text {
		if byte == 0 || byte == '\n' || byte == '\r' do return false
	}
	start := int(state.branch_draft_length)
	copy(state.branch_draft[start:], transmute([]u8)text)
	state.branch_draft_length += u16(len(text))
	return true
}

@(private)
ksawery_workflow_branch_name_delete_previous :: proc(state: ^Ksawery_Workflow_State) -> bool {
	if state == nil || state.branch_draft_length == 0 do return false
	start := int(state.branch_draft_length) - 1
	for start > 0 && state.branch_draft[start] & 0xc0 == 0x80 do start -= 1
	state.branch_draft_length = u16(start)
	return true
}

@(private)
ksawery_workflow_finalize_branch_name :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Branch_Name || state.process.state != nil do return false
	name: ksawery.Local_Branch_Name
	if !ksawery.local_branch_name_assign(
		&name,
		string(state.branch_draft[:state.branch_draft_length]),
	) {
		state.failure = .Invalid_Request
		command_context_set_diagnostic(commands, "Local branch name is invalid")
		return true
	}
	intent := state.branch_intent
	intent.name = name
	return ksawery_workflow_prepare_branch_confirmation(commands, intent)
}

@(private)
dispatch_ksawery_branch_name_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Branch_Name || state.process.state != nil {
		return {}, App_Failure{stage = .UI}
	}
	if input.kind == .Key && input.stroke.kind == .Unicode_Scalar &&
	   input.stroke.scalar == 'g' && input.stroke.modifiers == {.Control} {
		ksawery_workflow_clear_branch_preparation(state)
		state.view_mode = .Refs
		state.failure = .Cancelled
		command_context_set_diagnostic(commands, "Local branch naming cancelled")
		return Interaction_Result{changed = true}, {}
	}
	if input.kind == .Key && input.stroke.kind == .Enter && input.stroke.modifiers == {} {
		return Interaction_Result{changed = ksawery_workflow_finalize_branch_name(commands)}, {}
	}
	if input.kind == .Key && (input.stroke.kind == .Backspace || input.stroke.kind == .Delete) {
		return Interaction_Result{changed = ksawery_workflow_branch_name_delete_previous(state)}, {}
	}
	if (input.kind == .Text_Commit || input.kind == .Key) && len(input.text) > 0 &&
	   input.stroke.modifiers == {} {
		if ksawery_workflow_branch_name_append(state, input.text) {
			state.failure = .None
			return Interaction_Result{changed = true}, {}
		}
		state.failure = .Invalid_Request
		command_context_set_diagnostic(commands, "Local branch name rejected invalid or oversized text")
		return Interaction_Result{changed = true}, {}
	}
	return {}, {}
}

@(private)
dispatch_ksawery_branch_confirmation_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Branch_Confirmation || state.process.state != nil {
		return {}, App_Failure{stage = .UI}
	}
	if input.kind == .Key && input.stroke.kind == .Unicode_Scalar &&
	   ((input.stroke.scalar == 'g' && input.stroke.modifiers == {.Control}) ||
	    (input.stroke.scalar == 'q' && input.stroke.modifiers == {})) {
		ksawery_workflow_clear_branch_preparation(state)
		state.view_mode = .Refs
		state.failure = .Cancelled
		command_context_set_diagnostic(commands, "Local branch confirmation cancelled")
		return Interaction_Result{changed = true}, {}
	}
	if input.kind == .Key && input.stroke.kind == .Enter && input.stroke.modifiers == {.Control} {
		return Interaction_Result{changed = ksawery_workflow_confirm_branch(commands)}, {}
	}
	return {}, {}
}

@(private)
ksawery_workflow_confirm_branch :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Branch_Confirmation || state.process.state != nil do return false
	confirmed, confirmation_failure := ksawery.branch_confirmation_confirm(
		&state.branch_confirmation,
		state.branch_confirmation.id,
	)
	if !confirmed {
		state.failure = confirmation_failure
		command_context_set_diagnostic(commands, "Exact local branch confirmation was rejected")
		return true
	}
	operation := ksawery_workflow_current_branch_operation(state)
	request, prepared, failure := ksawery.branch_request_prepare(
		state.branch_precondition,
		operation,
		&state.branch_confirmation,
	)
	if !prepared {
		state.failure = failure
		state.view_mode = .Refs
		command_context_set_diagnostic(commands, "Confirmed local branch request was rejected")
		return true
	}
	editor_state, inspected := ksawery_workflow_branch_editor_state(commands)
	if !inspected {
		state.failure = .Presentation_Unavailable
		state.view_mode = .Refs
		command_context_set_diagnostic(commands, "Repository-associated editor resources could not be rechecked")
		return true
	}
	process, started, start_failure := ksawery.repository_process_start_branch(
		&state.observation,
		&state.refs,
		editor_state,
		request,
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
	)
	if !started {
		state.failure = start_failure
		state.view_mode = .Refs
		command_context_set_diagnostic(commands, "Checked local branch operation could not start")
		return true
	}
	kind := ksawery.Repository_Operation_Kind.Create_Branch
	title := "Create Local Branch"
	switch request.precondition.intent.operation {
	case .Create:
	case .Switch:
		kind = .Switch_Branch
		title = "Switch Local Branch"
	case .Rename:
		kind = .Rename_Branch
		title = "Rename Local Branch"
	case .Delete:
		kind = .Delete_Branch
		title = "Delete Local Branch"
	case .Invalid:
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
			phase_detail = "Applying local branch operation",
		},
		ksawery_workflow_now(commands),
	)
	if !recorded {
		ksawery.repository_process_close(&process)
		state.failure = record_failure
		state.view_mode = .Refs
		command_context_set_diagnostic(commands, "Checked local branch operation could not start")
		return true
	}
	if state.branch_result.state != nil do ksawery.branch_result_close(&state.branch_result)
	if state.tag_result.state != nil do ksawery.tag_result_close(&state.tag_result)
	if state.fetch_result.state != nil do ksawery.fetch_result_close(&state.fetch_result)
	if state.push_result.state != nil do ksawery.push_result_close(&state.push_result)
	state.branch_request = request
	state.process = process
	state.pending = .Branch
	state.view_mode = .Refs
	state.next_branch = operation + 1
	if state.next_branch == ksawery.Branch_Operation_ID(0) {
		state.next_branch = ksawery.Branch_Operation_ID(1)
	}
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_finish_branch_refresh :: proc(
	commands: ^Command_Context,
	refresh_failed: bool,
) {
	state := commands.ksawery_workflow
	if state == nil do return
	descriptor, described := ksawery.branch_result_descriptor(&state.branch_result)
	verification := Ksawery_Repository_Verification_State.Unavailable
	if !refresh_failed && described {
		verification = .Verified if descriptor.succeeded else .Known_Failure
	}
	message := "Local branch operation verified"
	if verification == .Known_Failure do message = "Local branch operation failed"
	if verification == .Unavailable do message = "Local branch operation outcome is indeterminate"
	ksawery_workflow_finish_synchronization_record(commands, verification, message)
	state.branch_refresh = .None
	state.view_mode = .Refs
	ksawery_workflow_clear_branch_preparation(state)
	if refresh_failed {
		state.failure = .Process_Failed
		command_context_set_diagnostic(commands, "Local branch operation finished, but repository refresh failed")
		return
	}
	if !described {
		state.failure = .Process_Failed
		command_context_set_diagnostic(commands, "Local branch result was unavailable")
		return
	}
	state.failure = descriptor.failure if !descriptor.succeeded else .None
	#partial switch ksawery.branch_feedback(descriptor) {
	case .Completed:
		command_context_set_diagnostic(commands, "Local branch operation completed")
	case .Cancelled:
		command_context_set_diagnostic(commands, "Local branch operation cancelled")
	case .Stale:
		command_context_set_diagnostic(commands, "Local branch operation result is stale")
	case:
		command_context_set_diagnostic(commands, "Local branch operation failed")
	}
}

@(private)
ksawery_branch_name_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || viewport_items == 0 || allocator.procedure == nil ||
	   (state.branch_intent.operation != .Create && state.branch_intent.operation != .Rename) {
		return nil, nil, false
	}
	rows, rows_error := make([]ui.List_Item_Definition, 9, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, len(rows) * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {
		delete(rows, allocator)
		return nil, nil, false
	}
	write := 0
	title := "Ksawery Create Local Branch" if state.branch_intent.operation == .Create else
		"Ksawery Rename Local Branch"
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xD300_0000_0000_0001, title, true,
		{surface = .Refs, subject = .Section},
	)
	if state.branch_intent.operation == .Rename {
		selected := state.branch_intent.selected
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xD300_0000_0000_0002,
			fmt.tprintf("Selected: %s %s", ksawery.ref_name_string(&selected.name), ksawery.revision_identity_string(&selected.object)),
			true, {surface = .Refs, subject = .Branch, current = true},
		)
	}
	label := "Name: "
	if state.branch_draft_length > 0 {
		label = fmt.tprintf("Name: %s", string(state.branch_draft[:state.branch_draft_length]))
	}
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xD300_0000_0000_0003, label, false,
		{surface = .Refs, subject = .Branch, current = true},
	)
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xD300_0000_0000_0004,
		"Enter prepares exact confirmation; C-g cancels.", true,
		{surface = .Refs, subject = .Operation},
	)
	if state.failure != .None {
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xD300_0000_0000_0005,
			fmt.tprintf("Branch name feedback: %v", state.failure), true,
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
ksawery_branch_confirmation_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || viewport_items == 0 || allocator.procedure == nil ||
	   !ksawery.branch_precondition_is_valid(state.branch_precondition) {
		return nil, nil, false
	}
	rows, rows_error := make([]ui.List_Item_Definition, 12, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, len(rows) * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {
		delete(rows, allocator)
		return nil, nil, false
	}
	precondition := state.branch_precondition
	intent := precondition.intent
	operation := fmt.tprintf("%v", intent.operation)
	write := 0
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xD400_0000_0000_0001, "Ksawery Local Branch Confirmation", true,
		{surface = .Refs, subject = .Section},
	)
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xD400_0000_0000_0002,
		fmt.tprintf("Operation: %s", operation), true,
		{surface = .Refs, subject = .Operation, destructive = intent.operation == .Delete},
	)
	head := precondition.head
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xD400_0000_0000_0003,
		fmt.tprintf("HEAD: %s %s", ksawery.ref_name_string(&head.branch.name), ksawery.revision_identity_string(&head.object)),
		true, {surface = .Refs, subject = .Branch, head = true},
	)
	if intent.selected != {} {
		selected := intent.selected
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xD400_0000_0000_0004,
			fmt.tprintf("Selected: %s %s", ksawery.ref_name_string(&selected.name), ksawery.revision_identity_string(&selected.object)),
			true, {surface = .Refs, subject = .Branch, current = true, destructive = intent.operation == .Delete},
		)
	}
	if intent.name != {} {
		name := intent.name
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xD400_0000_0000_0005,
			fmt.tprintf("New name: %s", ksawery.local_branch_name_string(&name)), true,
			{surface = .Refs, subject = .Branch},
		)
	}
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xD400_0000_0000_0006,
		fmt.tprintf("Checked editor resources: %d; modified: %d", precondition.editor.repository_resources,
			precondition.editor.modified_repository_resources), true,
		{surface = .Refs, subject = .Operation},
	)
	boundary := "The operation changes local refs only and never infers force."
	if intent.operation == .Switch {
		boundary = "Switching requires a clean worktree, clean index, and no modified repository buffers."
	} else if intent.operation == .Delete {
		boundary = "Deletion requires the selected noncurrent branch to remain merged into HEAD."
	}
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xD400_0000_0000_0007, boundary, true,
		{surface = .Refs, subject = .Failure, destructive = intent.operation == .Delete || intent.operation == .Switch},
	)
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xD400_0000_0000_0008,
		"C-Enter confirms this exact operation; C-g cancels.", false,
		{surface = .Refs, subject = .Operation},
	)
	definitions = rows[:write]
	state.position = {presentation_generation = 1, selection_owner = .View, current_item = i32(write - 1),
		first_visible_item = 0, viewport_items = min(viewport_items, u32(write))}
	return definitions, storage, true
}
