// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../document"
import "../editor"
import "../editor_session"
import "../interaction"
import editor_view "../view"
import "base:runtime"
import "core:fmt"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

// NAMED_SLOT_CANDIDATE_PREVIEW_BYTES bounds the inline preview for one named-slot candidate.
NAMED_SLOT_CANDIDATE_PREVIEW_BYTES :: 96

@(private)
Named_Slot_Operation :: enum u8 {
	Invalid,
	Store_Number,
	Increment_Number,
	Store_Text,
	Store_Region_Text,
	Modal_Store_Text,
	Store_Position,
	Insert_Slot,
	Store_Layout,
	Visit_Slot,
	Restore_Layout,
}

@(private)
Named_Slot_Phase :: enum u8 {
	Invalid,
	Name,
	Value,
	Confirm_Replacement,
}

@(private)
Named_Slot_Workflow_State :: struct {
	operation:       Named_Slot_Operation,
	phase:           Named_Slot_Phase,
	command_handle:  interaction.Command_Handle,
	name:            string,
	value:           string,
	target:          string,
	summary:         string,
	region_entry:    editor_session.Entry_Handle,
	region_view:     editor_view.View_Handle,
	point:           u64,
	integer:         i64,
	generation:      u64,
	return_target:   editor_session.Visible_Target,
	allocator:       runtime.Allocator,
}

@(private)
named_slot_operation_type_label :: proc(operation: Named_Slot_Operation) -> string {
	switch operation {
	case .Store_Number, .Increment_Number: return "Integer"
	case .Store_Text, .Store_Region_Text, .Modal_Store_Text, .Insert_Slot: return "Text"
	case .Store_Position: return "Position"
	case .Store_Layout, .Restore_Layout: return "Layout"
	case .Visit_Slot: return "Named"
	case .Invalid: return "Named"
	}
	return "Named"
}

@(private)
command_context_begin_named_slot :: proc(
	commands: ^Command_Context,
	operation: Named_Slot_Operation,
	command_handle: interaction.Command_Handle,
	buffer: ^editor.Buffer,
	document_owner: ^document.Document,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || operation == .Invalid || commands.racket_runtime == nil ||
	   len(commands.lifecycle_configuration_root) == 0 {
		return {}, App_Failure{stage = .Component_Access}
	}
	named_slot_workflow_reset(&commands.named_slot_workflow)
	state := &commands.named_slot_workflow
	state.operation = operation
	state.phase = .Name
	state.command_handle = command_handle
	state.allocator = commands.persistent_allocator
	if operation == .Increment_Number || operation == .Insert_Slot ||
	   operation == .Visit_Slot || operation == .Restore_Layout {
		return command_context_begin_named_slot_navigation(commands)
	}
	if operation == .Store_Region_Text {
		if buffer == nil do return {}, App_Failure{stage = .Component_Access}
		region, copied := named_slot_region_text(buffer, state.allocator)
		if !copied {
			named_slot_workflow_reset(state)
			command_context_set_diagnostic(commands, "Active non-empty region required")
			return Interaction_Result{changed = true}, {}
		}
		state.value = region
		state.region_entry = commands.current_entry
		state.region_view = view
	} else if operation == .Store_Position {
		status, status_ok, status_failure := document.document_status(document_owner)
		logical, logical_ok, logical_failure := editor_view.snapshot(view_registry, view)
		if !status_ok || !status.has_target || !logical_ok {
			named_slot_workflow_reset(state)
			_ = status_failure
			_ = logical_failure
			return {}, App_Failure{stage = .Document_Inspect}
		}
		target, target_error := strings.clone(status.target_path, state.allocator)
		if target_error != nil {
			named_slot_workflow_reset(state)
			return {}, App_Failure{stage = .Component_Access}
		}
		summary, summary_error := strings.clone(filepath.base(status.target_path), state.allocator)
		if summary_error != nil {
			delete(target, state.allocator)
			named_slot_workflow_reset(state)
			return {}, App_Failure{stage = .Component_Access}
		}
		state.target = target
		state.summary = summary
		state.point = u64(logical.point_position.byte_offset)
	} else if operation == .Store_Layout {
		value, encoded := command_context_layout_snapshot_encode(commands)
		if !encoded {
			named_slot_workflow_reset(state)
			command_context_set_diagnostic(commands, "Current layout cannot be stored")
			return Interaction_Result{changed = true}, {}
		}
		state.value = value
	}
	return command_context_begin_named_slot_prompt(commands, .Named_Slot_Input, .Text_Entry, 256, false)
}

@(private)
command_context_begin_named_slot_navigation :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	state := &commands.named_slot_workflow
	expected_kind := command.Named_Slot_Kind.Invalid
	#partial switch state.operation {
	case .Increment_Number: expected_kind = .Integer
	case .Insert_Slot:      expected_kind = .Text
	case .Restore_Layout:   expected_kind = .Layout
	case .Visit_Slot:       expected_kind = .Invalid
	}
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
	)
	if !visible_ok {
		named_slot_workflow_reset(state)
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	listed, listed_ok, list_failure := command.named_slots_list(
		commands.racket_runtime,
		commands.lifecycle_configuration_root,
		commands.persistent_allocator,
	)
	if !listed_ok {
		command_context_set_diagnostic(commands, "Named slots are unavailable")
		_ = list_failure
		named_slot_workflow_reset(state)
		return Interaction_Result{changed = true}, {}
	}
	defer command.named_slot_batch_close(&listed)
	preview_storage, preview_error := make(
		[]u8,
		command.MAX_NAMED_SLOTS * NAMED_SLOT_CANDIDATE_PREVIEW_BYTES,
		commands.temporary_allocator,
	)
	if preview_error != nil {
		named_slot_workflow_reset(state)
		return {}, App_Failure{stage = .Component_Access}
	}
	defer delete(preview_storage, commands.temporary_allocator)
	fields: [command.MAX_NAMED_SLOTS][1]string
	annotations: [command.MAX_NAMED_SLOTS][1]interaction.Candidate_Annotation_Definition
	descriptors: [command.MAX_NAMED_SLOTS]interaction.Candidate_Descriptor_Definition
	descriptor_count := 0
	slot_generation := max(listed.generation, 1)
	source_generation := commands.candidate_ui.next_source_generation
	session_id := commands.candidate_ui.next_session_id
	if source_generation == 0 || source_generation == max(u64) ||
	   session_id == 0 || session_id == max(u64) {
		named_slot_workflow_reset(state)
		return {}, App_Failure{stage = .Component_Access}
	}
	for slot, slot_index in listed.slots {
		if expected_kind != .Invalid && slot.kind != expected_kind do continue
		preview_start := descriptor_count * NAMED_SLOT_CANDIDATE_PREVIEW_BYTES
		preview := named_slot_candidate_preview(
			slot,
			preview_storage[preview_start:preview_start + NAMED_SLOT_CANDIDATE_PREVIEW_BYTES],
		)
		descriptor := interaction.Candidate_Descriptor_Definition {
			identity = {kind = 14, primary = u64(slot_index + 1), secondary = slot_generation},
			label = slot.name,
			action = {
				kind = .Select_Named_Slot,
				owner_generation = source_generation,
				primary = u64(slot_index + 1),
				secondary = slot_generation,
			},
			availability = .Available,
		}
		if len(preview) > 0 {
			fields[descriptor_count] = {preview}
			annotations[descriptor_count] = {{kind = .Description, text = preview}}
			descriptor.searchable_fields = fields[descriptor_count][:]
			descriptor.annotations = annotations[descriptor_count][:]
		}
		descriptors[descriptor_count] = descriptor
		descriptor_count += 1
	}
	source := interaction.Candidate_Source_Definition {
		kind = .Named_Slots,
		scope_identity = u64(expected_kind),
		scope_generation = slot_generation,
		source_generation = source_generation,
		descriptors = descriptors[:descriptor_count],
	}
	state.generation = listed.generation
	candidate_session: interaction.Candidate_Session
	_, initialized, candidate_failure := interaction.candidate_session_init(
		&candidate_session,
		interaction.Candidate_Config {
			session_id = interaction.Candidate_Session_ID(session_id),
			limits = interaction.DEFAULT_CANDIDATE_LIMITS,
			persistent_allocator = commands.persistent_allocator,
			temporary_allocator = commands.temporary_allocator,
		},
		source,
	)
	if !initialized {
		command_context_candidate_failure_diagnostic(commands, "Named slot candidates", candidate_failure)
		named_slot_workflow_reset(state)
		return Interaction_Result{changed = true}, {}
	}
	keep_session := false
	defer if !keep_session do _, _, _ = interaction.candidate_session_close(&candidate_session)
	if commands.candidate_ui.catalog.state != nil do interaction.command_catalog_close(&commands.candidate_ui.catalog)
	if commands.candidate_ui.session.state != nil do _, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	commands.candidate_ui.session = candidate_session
	commands.candidate_ui.return_target = visible
	commands.candidate_ui.next_session_id = session_id + 1
	commands.candidate_ui.next_source_generation = source_generation + 1
	keep_session = true
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner,
		commands.session_handle,
		candidate_ui_visible_target().ui,
	)
	if !presented {
		command_context_close_named_slot_navigation(commands, true)
		return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	commands.pending = {}
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}

@(private)
named_slot_candidate_preview :: proc(
	slot: command.Named_Slot_Descriptor,
	output: []u8,
) -> string {
	if len(output) < 4 do return ""
	switch slot.kind {
	case .Integer:
		return fmt.bprintf(output, "%d", slot.integer)
	case .Text:
		return named_slot_text_candidate_preview(slot.text, output)
	case .Position:
		filename := filepath.base(slot.target)
		if len(filename) == 0 do return ""
		return fmt.bprintf(output, "%s @ byte %d", filename, slot.point)
	case .Invalid, .Location, .Layout:
		return ""
	}
	return ""
}

@(private)
named_slot_text_candidate_preview :: proc(text: string, output: []u8) -> string {
	if len(text) == 0 || len(output) < 4 do return ""
	input_offset := 0
	output_offset := 0
	pending_space := false
	truncated := false
	content_limit := len(output) - len("...")
	for input_offset < len(text) {
		value, width := utf8.decode_rune(text[input_offset:])
		if width <= 0 do return ""
		input_offset += width
		if unicode.is_space(value) {
			if output_offset > 0 do pending_space = true
			continue
		}
		required := width
		if pending_space do required += 1
		if output_offset + required > content_limit {
			truncated = true
			break
		}
		if pending_space {
			output[output_offset] = ' '
			output_offset += 1
			pending_space = false
		}
		copy(output[output_offset:], text[input_offset - width:input_offset])
		output_offset += width
	}
	if input_offset < len(text) do truncated = true
	if truncated {
		copy(output[output_offset:], "...")
		output_offset += len("...")
	}
	return string(output[:output_offset])
}

@(private)
dispatch_named_slot_navigation_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed || view.source_kind != .Named_Slots {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	if map_failure := command_context_sync_candidate_map(commands, .Named_Slots);
	   map_failure.stage != .None {
		return {}, map_failure
	}
	metadata, resolution, resolved, resolution_failure := command_context_resolve_context_input(commands, input)
	if !resolved do return {}, resolution_failure
	if resolution.kind != .Command do return {}, {}
	request := interaction.Candidate_Request {
		session_id = view.session_id,
		session_generation = view.session_generation,
	}
	contextual_route, contextual_ok := command.contextual_route_decode(metadata.route)
	if contextual_ok &&
	   (contextual_route == .Component_Previous_Row || contextual_route == .Component_Next_Row) {
		if len(view.rows) == 0 do return {}, {}
		delta := i32(1)
		if contextual_route == .Component_Previous_Row do delta = -1
		_, moved, move_failure := interaction.candidate_session_move(
			&commands.candidate_ui.session,
			request,
			delta,
		)
		if !moved do command_context_candidate_failure_diagnostic(commands, "Named slot movement", move_failure)
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Query_Text {
		if len(resolution.text) == 0 do return {}, {}
		if len(view.query) + len(resolution.text) > int(interaction.MAX_CANDIDATE_QUERY_BYTES) do return {}, {}
		query: [interaction.MAX_CANDIDATE_QUERY_BYTES]u8
		copy(query[:], transmute([]u8)view.query)
		copy(query[len(view.query):], transmute([]u8)resolution.text)
		return command_context_refresh_named_slots(
			commands,
			string(query[:len(view.query) + len(resolution.text)]),
		)
	}
	if contextual_route == .Component_Query_Delete_Previous {
		if len(view.query) == 0 do return {}, {}
		end := len(view.query) - 1
		bytes := transmute([]u8)view.query
		for end > 0 && bytes[end] & 0xc0 == 0x80 do end -= 1
		return command_context_refresh_named_slots(commands, view.query[:end])
	}
	if contextual_route == .Component_Activate_Current {
		if !view.has_selection || len(view.rows) == 0 do return {}, {}
		row := view.rows[view.selected_row]
		if row.action.kind != .Select_Named_Slot ||
		   row.action.owner_generation != view.source_generation ||
		   row.action.secondary != view.scope_generation {
			command_context_set_diagnostic(commands, "Named slot changed; reopen the list")
			return Interaction_Result{changed = true}, {}
		}
		state := &commands.named_slot_workflow
		name, name_error := strings.clone(row.label, state.allocator)
		if name_error != nil do return {}, App_Failure{stage = .Component_Access}
		state.name = name
		return_target := commands.candidate_ui.return_target
		state.return_target = return_target
		command_context_deactivate_context_map(commands, .Completed)
		command_context_close_named_slot_navigation(commands, false)
		if return_target.kind != .Primary_View {
			named_slot_workflow_reset(state)
			return {}, App_Failure{stage = .Session_Access}
		}
		_, activated, activation_failure := editor_session.session_activate(
			commands.session_owner,
			return_target.entry,
		)
		if !activated {
			named_slot_workflow_reset(state)
			return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
		}
		if state.operation == .Increment_Number {
			state.phase = .Value
			return command_context_begin_named_slot_prompt(
				commands,
				.Named_Slot_Input,
				.Text_Entry,
				64,
				false,
			)
		}
		return command_context_finish_named_slot(commands, false, constraints)
	}
	if contextual_route == .Component_Close || command_metadata_is_native(metadata, .Keyboard_Quit) {
		return command_context_leave_named_slots(commands)
	}
	return {}, {}
}

@(private)
command_context_refresh_named_slots :: proc(
	commands: ^Command_Context,
	query: string,
) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed do return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	_, refreshed, refresh_failure := interaction.candidate_session_set_query(
		&commands.candidate_ui.session,
		interaction.Candidate_Request {
			session_id = view.session_id,
			session_generation = view.session_generation,
		},
		query,
	)
	if !refreshed do command_context_candidate_failure_diagnostic(commands, "Named slot query", refresh_failure)
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_leave_named_slots :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	command_context_deactivate_context_map(commands, .Completed)
	return_target := commands.candidate_ui.return_target
	defer command_context_close_named_slot_navigation(commands, true)
	if return_target.kind != .Primary_View do return {}, App_Failure{stage = .Session_Access}
	_, activated, activation_failure := editor_session.session_activate(
		commands.session_owner,
		return_target.entry,
	)
	if !activated {
		return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_close_named_slot_navigation :: proc(
	commands: ^Command_Context,
	reset_workflow: bool,
) {
	if commands == nil do return
	if commands.candidate_ui.session.state != nil {
		_, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	}
	commands.candidate_ui.return_target = {}
	if reset_workflow do named_slot_workflow_reset(&commands.named_slot_workflow)
}

@(private)
named_slot_region_text :: proc(buffer: ^editor.Buffer, allocator: runtime.Allocator) -> (string, bool) {
	if buffer == nil || allocator.procedure == nil do return "", false
	selection, selected, _ := editor.buffer_selection_snapshot(buffer)
	if !selected || !selection.region_active || !selection.mark.present do return "", false
	start := selection.point_position.byte_offset
	end := selection.mark.position.byte_offset
	if start > end do start, end = end, start
	length := u64(end) - u64(start)
	if length == 0 || length > command.MAX_NAMED_SLOT_TEXT_BYTES do return "", false
	storage, allocation_error := make([]byte, int(length), allocator)
	if allocation_error != nil do return "", false
	_, inspected, _ := editor.buffer_inspect(buffer, start, end, storage)
	if !inspected {
		delete(storage, allocator)
		return "", false
	}
	return string(storage), true
}

@(private)
command_context_begin_named_slot_prompt :: proc(
	commands: ^Command_Context,
	mode: Prompt_Mode,
	kind: interaction.Prompt_Kind,
	text_limit: u64,
	allow_empty: bool,
) -> (Interaction_Result, App_Failure) {
	config := interaction.Prompt_Config {
		kind = kind,
		text_bytes_limit = text_limit,
		allow_empty = allow_empty,
		allocator = commands.persistent_allocator,
	}
	choices := prompt_yes_no_choices()
	if kind == .Fixed_Choice do config.choices = choices[:]
	prompt_ok, prompt_failure := interaction.prompt_init(&commands.prompt_workflow.prompt, config)
	if !prompt_ok do return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	if !prompt_workflow_begin_projection(&commands.prompt_workflow, mode) {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		return {}, App_Failure{stage = .Prompt}
	}
	if map_failure := command_context_activate_prompt_map(commands, mode); map_failure.stage != .None {
		command_context_end_prompt(commands)
		return {}, map_failure
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_named_slot_prompt :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	metadata, resolution, resolved, resolve_failure := command_context_resolve_prompt_input(commands, input)
	if !resolved do return {}, resolve_failure
	if resolution.kind != .Command do return {}, {}
	if command_metadata_is_cancel(metadata) {
		_, _ = interaction.prompt_cancel(&commands.prompt_workflow.prompt)
		command_context_end_prompt(commands)
		if state := &commands.named_slot_workflow; state.operation == .Modal_Store_Text &&
		   commands.profile_activation != nil {
			interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
		}
		named_slot_workflow_reset(&commands.named_slot_workflow)
		return Interaction_Result{changed = true}, {}
	}
	state := &commands.named_slot_workflow
	if state.phase == .Confirm_Replacement {
		if command_metadata_is_contextual(metadata, .Prompt_Choice_2) {
			command_context_end_prompt(commands)
			if state.operation == .Modal_Store_Text && commands.profile_activation != nil {
				interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
			}
			named_slot_workflow_reset(state)
			command_context_set_diagnostic(commands, "Named slot replacement cancelled")
			return Interaction_Result{changed = true}, {}
		}
		if !command_metadata_is_contextual(metadata, .Prompt_Choice_1) do return {}, {}
		return command_context_finish_named_slot(commands, true, constraints)
	}
	if command_metadata_is_contextual(metadata, .Prompt_Delete_Previous) {
		transition, prompt_failure := interaction.prompt_text_delete_previous(&commands.prompt_workflow.prompt)
		if prompt_failure.code != .None do return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		commands.prompt_workflow.rejected = false
		return Interaction_Result{changed = transition == .Changed}, {}
	}
	if command_metadata_is_contextual(metadata, .Prompt_Insert_Text) {
		transition, prompt_failure := interaction.prompt_text_append(&commands.prompt_workflow.prompt, resolution.text)
		if prompt_failure.code == .Text_Limit || prompt_failure.code == .Malformed_UTF8 {
			commands.prompt_workflow.rejected = true
			return Interaction_Result{changed = true}, {}
		}
		if prompt_failure.code != .None do return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		commands.prompt_workflow.rejected = false
		return Interaction_Result{changed = transition == .Changed}, {}
	}
	if !command_metadata_is_contextual(metadata, .Prompt_Accept) do return {}, {}
	_, accept_failure := interaction.prompt_text_accept(&commands.prompt_workflow.prompt)
	if accept_failure.code != .None {
		commands.prompt_workflow.rejected = true
		return Interaction_Result{changed = true}, {}
	}
	prompt_view, viewed, view_failure := interaction.prompt_view(&commands.prompt_workflow.prompt)
	if !viewed do return {}, App_Failure{stage = .Prompt, prompt_failure = view_failure}
	if state.phase == .Name &&
	   (state.operation == .Store_Number || state.operation == .Increment_Number ||
	    state.operation == .Store_Text) {
		name, name_error := strings.clone(prompt_view.text, state.allocator)
		if name_error != nil do return {}, App_Failure{stage = .Component_Access}
		state.name = name
		state.phase = .Value
		command_context_end_prompt(commands)
		limit := u64(64) if state.operation != .Store_Text else u64(command.MAX_NAMED_SLOT_TEXT_BYTES)
		allow_empty := state.operation == .Store_Text
		return command_context_begin_named_slot_prompt(commands, .Named_Slot_Input, .Text_Entry, limit, allow_empty)
	}
	if state.phase == .Name {
		name, name_error := strings.clone(prompt_view.text, state.allocator)
		if name_error != nil do return {}, App_Failure{stage = .Component_Access}
		state.name = name
	} else if state.phase == .Value {
		if state.operation == .Store_Number || state.operation == .Increment_Number {
			value, parsed := strconv.parse_i64_of_base(prompt_view.text, 10)
			if !parsed {
				commands.prompt_workflow.rejected = true
				return Interaction_Result{changed = true}, {}
			}
			state.integer = value
		} else {
			value, value_error := strings.clone(prompt_view.text, state.allocator)
			if value_error != nil do return {}, App_Failure{stage = .Component_Access}
			state.value = value
		}
	}
	return command_context_finish_named_slot(commands, false, constraints)
}

@(private)
command_context_finish_named_slot :: proc(
	commands: ^Command_Context,
	replace_conflict: bool,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	state := &commands.named_slot_workflow
	if state.operation == .Visit_Slot {
		return command_context_visit_named_slot(commands)
	}
	if state.operation == .Modal_Store_Text && replace_conflict {
		execution, active := interaction.profile_activation_modal_operator_execution_inspect(
			commands.profile_activation,
		)
		listed, listed_ok, list_failure := command.named_slots_list(
			commands.racket_runtime,
			commands.lifecycle_configuration_root,
			state.allocator,
		)
		if listed.state != nil do defer command.named_slot_batch_close(&listed)
		if !active || !listed_ok || listed.generation != execution.slot_generation {
			_ = list_failure
			command_context_end_prompt(commands)
			if commands.profile_activation != nil {
				interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
			}
			named_slot_workflow_reset(state)
			command_context_set_diagnostic(commands, "Named slot changed during confirmation")
			return Interaction_Result{changed = true}, {}
		}
	}
	batch: command.Named_Slot_Batch
	ok: bool
	failure: command.Failure_Context
	switch state.operation {
	case .Store_Number:
		batch, ok, failure = command.named_slot_store_integer(commands.racket_runtime, commands.lifecycle_configuration_root, state.name, state.integer, replace_conflict, state.allocator)
	case .Increment_Number:
		if replace_conflict {
			batch, ok, failure = command.named_slot_store_integer(commands.racket_runtime, commands.lifecycle_configuration_root, state.name, state.integer, true, state.allocator)
		} else {
			batch, ok, failure = command.named_slot_increment_integer(commands.racket_runtime, commands.lifecycle_configuration_root, state.name, state.integer, state.allocator)
		}
	case .Store_Text, .Store_Region_Text, .Modal_Store_Text:
		batch, ok, failure = command.named_slot_store_text(commands.racket_runtime, commands.lifecycle_configuration_root, state.name, state.value, replace_conflict, state.allocator)
	case .Store_Position:
		batch, ok, failure = command.named_slot_store_position(commands.racket_runtime, commands.lifecycle_configuration_root, state.name, state.target, state.summary, state.point, replace_conflict, state.allocator)
	case .Store_Layout:
		batch, ok, failure = command.named_slot_store_layout(commands.racket_runtime, commands.lifecycle_configuration_root, state.name, state.value, replace_conflict, state.allocator)
	case .Restore_Layout:
		batch, ok, failure = command.named_slot_lookup_layout(commands.racket_runtime, commands.lifecycle_configuration_root, state.name, state.allocator)
	case .Insert_Slot:
		batch, ok, failure = command.named_slot_lookup_text(commands.racket_runtime, commands.lifecycle_configuration_root, state.name, state.allocator)
	case .Visit_Slot: unreachable()
	case .Invalid: return {}, App_Failure{stage = .Component_Access}
	}
	_ = failure
	if !ok && batch.conflict_kind != .Invalid && !replace_conflict &&
	   state.operation != .Insert_Slot && state.operation != .Restore_Layout {
		command.named_slot_batch_close(&batch)
		state.phase = .Confirm_Replacement
		command_context_end_prompt(commands)
		return command_context_begin_named_slot_prompt(commands, .Named_Slot_Confirmation, .Fixed_Choice, 0, false)
	}
	if !ok {
		if batch.state != nil do command.named_slot_batch_close(&batch)
		command_context_end_prompt(commands)
		if state.operation == .Modal_Store_Text && commands.profile_activation != nil {
			interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
		}
		named_slot_workflow_reset(state)
		command_context_set_diagnostic(commands, "Named slot command failed")
		return Interaction_Result{changed = true}, {}
	}
	if state.operation == .Insert_Slot {
		if len(batch.slots) != 1 || batch.slots[0].kind != .Text {
			command.named_slot_batch_close(&batch)
			command_context_end_prompt(commands)
			named_slot_workflow_reset(state)
			command_context_set_diagnostic(commands, "Named text slot not found")
			return Interaction_Result{changed = true}, {}
		}
		inserted, allocation_error := strings.clone(batch.slots[0].text, state.allocator)
		command.named_slot_batch_close(&batch)
		if allocation_error != nil do return {}, App_Failure{stage = .Component_Access}
		command_context_end_prompt(commands)
		named_slot_workflow_reset(state)
		result, dispatch_failure := dispatch_session_input(
			commands,
			commands.session_owner,
			commands.session_handle,
			interaction.Input{kind = .Text_Commit, text = inserted},
			constraints,
		)
		delete(inserted, commands.persistent_allocator)
		return result, dispatch_failure
	}
	if state.operation == .Restore_Layout {
		if len(batch.slots) != 1 || batch.slots[0].kind != .Layout {
			command.named_slot_batch_close(&batch)
			command_context_end_prompt(commands)
			named_slot_workflow_reset(state)
			command_context_set_diagnostic(commands, "Named layout not found")
			return Interaction_Result{changed = true}, {}
		}
		restored, complete := command_context_layout_snapshot_restore(commands, batch.slots[0].text)
		command.named_slot_batch_close(&batch)
		command_context_end_prompt(commands)
		named_slot_workflow_reset(state)
		if !restored {
			command_context_set_diagnostic(commands, "Named layout could not be restored")
		} else if complete {
			command_context_set_diagnostic(commands, "Named layout restored")
		} else {
			command_context_set_diagnostic(commands, "Compatible layout portion restored")
		}
		return Interaction_Result{changed = true}, {}
	}
	if state.operation == .Modal_Store_Text {
		deferred_command := state.command_handle
		command.named_slot_batch_close(&batch)
		command_context_end_prompt(commands)
		named_slot_workflow_reset(state)
		return dispatch_session_input(
			commands,
			commands.session_owner,
			commands.session_handle,
			{},
			constraints,
			deferred_command,
		)
	}
	command.named_slot_batch_close(&batch)
	command_context_end_prompt(commands)
	label := named_slot_operation_type_label(state.operation)
	region_deactivated := command_context_deactivate_stored_region(commands, state)
	diagnostic := fmt.bprintf(commands.overlay_label[:], "%s slot saved", label)
	if !region_deactivated {
		diagnostic = fmt.bprintf(
			commands.overlay_label[:],
			"%s slot saved; region remains active",
			label,
		)
	}
	named_slot_workflow_reset(state)
	command_context_set_diagnostic(commands, diagnostic)
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_visit_named_slot :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	state := &commands.named_slot_workflow
	listed, listed_ok, list_failure := command.named_slots_list(
		commands.racket_runtime,
		commands.lifecycle_configuration_root,
		state.allocator,
	)
	if listed.state != nil do defer command.named_slot_batch_close(&listed)
	if !listed_ok || listed.generation != state.generation {
		_ = list_failure
		named_slot_workflow_reset(state)
		command_context_set_diagnostic(commands, "Named slot changed; reopen the list")
		return Interaction_Result{changed = true}, {}
	}
	selected: ^command.Named_Slot_Descriptor
	for &slot in listed.slots {
		if slot.name == state.name {
			selected = &slot
			break
		}
	}
	if selected == nil {
		named_slot_workflow_reset(state)
		command_context_set_diagnostic(commands, "Named slot no longer exists")
		return Interaction_Result{changed = true}, {}
	}
	if selected.kind == .Layout {
		restored, complete := command_context_layout_snapshot_restore(commands, selected.text)
		named_slot_workflow_reset(state)
		if !restored {
			command_context_set_diagnostic(commands, "Named layout could not be restored")
		} else if complete {
			command_context_set_diagnostic(commands, "Named layout restored")
		} else {
			command_context_set_diagnostic(commands, "Compatible layout portion restored")
		}
		return Interaction_Result{changed = true}, {}
	}
	if selected.kind != .Position {
		kind := selected.kind
		named_slot_workflow_reset(state)
		label := "text" if kind == .Text else "integer"
		command_context_set_diagnostic(
			commands,
			fmt.bprintf(commands.overlay_label[:], "Named %s slot cannot be visited", label),
		)
		return Interaction_Result{changed = true}, {}
	}
	target_storage: [document.MAX_PATH_BYTES]u8
	if len(selected.target) > len(target_storage) {
		named_slot_workflow_reset(state)
		return {}, App_Failure{stage = .Component_Access}
	}
	copy(target_storage[:], transmute([]u8)selected.target)
	target := string(target_storage[:len(selected.target)])
	point := selected.point
	command_handle := state.command_handle
	return_target := state.return_target
	previous, previous_ok := command_context_named_location_return_state(commands, return_target)
	if !named_location_target_is_available(target) {
		named_slot_workflow_reset(state)
		command_context_set_diagnostic(commands, "Named position target is unavailable")
		return Interaction_Result{changed = true}, {}
	}
	result, opened, open_failure := command.buffer_session_find_file(
		command.Buffer_Session_Context {
			session = commands.session_owner,
			handle = commands.session_handle,
			command = command_handle,
			configuration = commands.entry_configuration,
		},
		target,
	)
	if !opened {
		named_slot_workflow_reset(state)
		command_context_buffer_session_diagnostic(commands, open_failure)
		return Interaction_Result{changed = true}, {}
	}
	if !command_context_restore_named_location(commands, result.entry, point, 0, false, false) {
		if return_target.kind == .Primary_View {
			_, _, _ = editor_session.session_activate(commands.session_owner, return_target.entry)
		}
		named_slot_workflow_reset(state)
		command_context_set_diagnostic(commands, "Named position anchor is stale")
		return Interaction_Result{changed = true}, {}
	}
	if previous_ok {
		pushed := command.location_history_push(commands.location_history, previous)
		assert(pushed)
	}
	named_slot_workflow_reset(state)
	command_context_set_diagnostic(commands, "Visited named position")
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_deactivate_stored_region :: proc(
	commands: ^Command_Context,
	state: ^Named_Slot_Workflow_State,
) -> bool {
	if state.operation != .Store_Region_Text do return true
	if commands == nil || commands.session_owner == nil ||
	   !editor_session.entry_handle_is_valid(state.region_entry) {
		return false
	}
	access, accessible, _ := editor_session.session_entry_access(
		commands.session_owner,
		state.region_entry,
	)
	if !accessible do return false
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	if !borrowed do return false
	deactivated, _ := editor_view.set_region_active(
		entry.view_registry,
		state.region_view,
		false,
	)
	return deactivated
}

@(private)
named_slot_workflow_reset :: proc(state: ^Named_Slot_Workflow_State) {
	if state == nil do return
	allocator := state.allocator
	if len(state.name) > 0 do delete(state.name, allocator)
	if len(state.value) > 0 do delete(state.value, allocator)
	if len(state.target) > 0 do delete(state.target, allocator)
	if len(state.summary) > 0 do delete(state.summary, allocator)
	state^ = {}
}
