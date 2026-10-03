// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../document"
import "../editor"
import "../editor_session"
import "../interaction"
import editor_view "../view"
import "base:runtime"
import "core:os"
import "core:path/filepath"
import "core:strings"

@(private)
Named_Location_Workflow_State :: struct {
	batch:          command.Named_Location_Batch,
	command_handle: interaction.Command_Handle,
	pending_target: string,
	pending_summary: string,
	allocator:      runtime.Allocator,
	pending_point: u64,
	pending_mark: u64,
	pending_has_mark: bool,
	pending_region_active: bool,
}

@(private)
command_context_begin_named_location_save :: proc(
	commands: ^Command_Context,
	command_handle: interaction.Command_Handle,
	document_owner: ^document.Document,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
) -> (Interaction_Result, App_Failure) {
	status, status_ok, status_failure := document.document_status(document_owner)
	if !status_ok || !status.has_target {
		return {}, App_Failure{stage = .Document_Inspect, document = status_failure}
	}
	logical, logical_ok, logical_failure := editor_view.snapshot(view_registry, view)
	if !logical_ok do return {}, App_Failure{stage = .View_Snapshot, view = logical_failure}
	if len(status.target_path) > int(document.MAX_PATH_BYTES) {
		return {}, App_Failure{stage = .Component_Access}
	}
	summary := filepath.base(status.target_path)
	if len(summary) == 0 {
		return {}, App_Failure{stage = .Component_Access}
	}
	target_copy, target_error := strings.clone(status.target_path, commands.persistent_allocator)
	if target_error != nil do return {}, App_Failure{stage = .Component_Access}
	summary_copy, summary_error := strings.clone(summary, commands.persistent_allocator)
	if summary_error != nil {
		delete(target_copy, commands.persistent_allocator)
		return {}, App_Failure{stage = .Component_Access}
	}
	named_location_workflow_reset(&commands.named_location_workflow)
	commands.named_location_workflow.pending_target = target_copy
	commands.named_location_workflow.pending_summary = summary_copy
	commands.named_location_workflow.allocator = commands.persistent_allocator
	commands.named_location_workflow.pending_point = u64(logical.point_position.byte_offset)
	commands.named_location_workflow.pending_has_mark = logical.mark.present
	if logical.mark.present do commands.named_location_workflow.pending_mark = u64(logical.mark.position.byte_offset)
	commands.named_location_workflow.pending_region_active = logical.region_active
	commands.named_location_workflow.command_handle = command_handle
	prompt_ok, prompt_failure := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		interaction.Prompt_Config {
			kind = .Text_Entry,
			text_bytes_limit = 256,
			allow_empty = false,
			allocator = commands.persistent_allocator,
		},
	)
	if !prompt_ok {
		named_location_workflow_reset(&commands.named_location_workflow)
		return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	}
	if !prompt_workflow_begin_projection(&commands.prompt_workflow, .Named_Location_Name) {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		named_location_workflow_reset(&commands.named_location_workflow)
		return {}, App_Failure{stage = .Prompt}
	}
	if map_failure := command_context_activate_prompt_map(commands, .Named_Location_Name); map_failure.stage != .None {
		command_context_end_prompt(commands)
		return {}, map_failure
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_named_location_prompt :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	metadata, resolution, resolved, resolve_failure := command_context_resolve_prompt_input(commands, input)
	if !resolved do return {}, resolve_failure
	if resolution.kind != .Command do return {}, {}
	if command_metadata_is_cancel(metadata) {
		_, _ = interaction.prompt_cancel(&commands.prompt_workflow.prompt)
		command_context_deactivate_prompt_map(commands, .Cancelled)
		command_context_end_prompt(commands)
		named_location_workflow_reset(&commands.named_location_workflow)
		return Interaction_Result{changed = true}, {}
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
	state := &commands.named_location_workflow
	saved, saved_ok, _ := command.named_location_save(
		commands.racket_runtime,
		commands.lifecycle_configuration_root,
		prompt_view.text,
		state.pending_target,
		state.pending_point,
		state.pending_mark,
		state.pending_has_mark,
		state.pending_region_active,
		state.pending_summary,
		commands.persistent_allocator,
	)
	command_context_deactivate_prompt_map(commands, .Completed)
	command_context_end_prompt(commands)
	if !saved_ok {
		named_location_workflow_reset(state)
		command_context_set_diagnostic(commands, "Named location could not be saved")
		return Interaction_Result{changed = true}, {}
	}
	command.named_location_batch_close(&saved)
	named_location_workflow_reset(state)
	command_context_set_diagnostic(commands, "Named location saved")
	return Interaction_Result{changed = true}, {}
}

@(private)
named_location_workflow_reset :: proc(state: ^Named_Location_Workflow_State) {
	if state == nil do return
	if state.batch.state != nil do command.named_location_batch_close(&state.batch)
	if len(state.pending_target) > 0 do delete(state.pending_target, state.allocator)
	if len(state.pending_summary) > 0 do delete(state.pending_summary, state.allocator)
	state^ = {}
}

@(private)
command_context_present_named_locations :: proc(
	commands: ^Command_Context,
	command_handle: interaction.Command_Handle,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.racket_runtime == nil ||
	   len(commands.lifecycle_configuration_root) == 0 {
		return {}, App_Failure{stage = .Component_Access}
	}
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner, commands.session_handle,
	)
	if !visible_ok do return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	listed, listed_ok, list_failure := command.named_locations_list(
		commands.racket_runtime,
		commands.lifecycle_configuration_root,
		commands.persistent_allocator,
	)
	if !listed_ok {
		command_context_set_diagnostic(commands, "Named locations are unavailable")
		_ = list_failure
		return Interaction_Result{changed = true}, {}
	}
	keep_batch := false
	defer if !keep_batch do command.named_location_batch_close(&listed)
	fields: [command.MAX_NAMED_LOCATIONS][1]string
	annotations: [command.MAX_NAMED_LOCATIONS][1]interaction.Candidate_Annotation_Definition
	descriptors: [command.MAX_NAMED_LOCATIONS]interaction.Candidate_Descriptor_Definition
	source_generation := commands.candidate_ui.next_source_generation
	session_id := commands.candidate_ui.next_session_id
	if source_generation == 0 || source_generation == max(u64) ||
	   session_id == 0 || session_id == max(u64) {
		return {}, App_Failure{stage = .Component_Access}
	}
	for location, index in listed.locations {
		fields[index] = {location.target}
		annotations[index] = {{kind = .Project_Member, text = location.summary}}
		descriptors[index] = interaction.Candidate_Descriptor_Definition {
			identity = {kind = 13, primary = u64(index + 1), secondary = listed.generation},
			label = location.name,
			searchable_fields = fields[index][:],
			annotations = annotations[index][:],
			action = {
				kind = .Visit_Location,
				owner_generation = source_generation,
				primary = u64(index + 1),
				secondary = listed.generation,
			},
			availability = .Available,
			durable_category = .Document,
			durable_key = location.target,
		}
	}
	source := interaction.Candidate_Source_Definition {
		kind = .Named_Locations,
		scope_identity = 1,
		scope_generation = max(listed.generation, 1),
		source_generation = source_generation,
		descriptors = descriptors[:len(listed.locations)],
	}
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
		command_context_candidate_failure_diagnostic(commands, "Named location candidates", candidate_failure)
		return Interaction_Result{changed = true}, {}
	}
	keep_session := false
	defer if !keep_session do _, _, _ = interaction.candidate_session_close(&candidate_session)
	if commands.candidate_ui.catalog.state != nil do interaction.command_catalog_close(&commands.candidate_ui.catalog)
	if commands.candidate_ui.session.state != nil do _, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	named_location_workflow_reset(&commands.named_location_workflow)
	commands.named_location_workflow.batch = listed
	commands.named_location_workflow.command_handle = command_handle
	commands.candidate_ui.session = candidate_session
	commands.candidate_ui.return_target = visible
	commands.candidate_ui.next_session_id = session_id + 1
	commands.candidate_ui.next_source_generation = source_generation + 1
	keep_batch = true
	keep_session = true
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner, commands.session_handle, candidate_ui_visible_target().ui,
	)
	if !presented {
		command_context_close_named_locations(commands)
		return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	commands.pending = {}
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_named_location_navigation_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed || view.source_kind != .Named_Locations {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	if map_failure := command_context_sync_candidate_map(commands, .Named_Locations); map_failure.stage != .None {
		return {}, map_failure
	}
	metadata, resolution, resolved, resolution_failure := command_context_resolve_context_input(commands, input)
	if !resolved do return {}, resolution_failure
	if resolution.kind != .Command do return {}, {}
	request := interaction.Candidate_Request {session_id = view.session_id, session_generation = view.session_generation}
	contextual_route, contextual_ok := command.contextual_route_decode(metadata.route)
	if contextual_ok && (contextual_route == .Component_Previous_Row || contextual_route == .Component_Next_Row) {
		if len(view.rows) == 0 do return {}, {}
		delta := i32(1)
		if contextual_route == .Component_Previous_Row do delta = -1
		_, moved, move_failure := interaction.candidate_session_move(&commands.candidate_ui.session, request, delta)
		if !moved do command_context_candidate_failure_diagnostic(commands, "Named location movement", move_failure)
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Query_Text {
		if len(resolution.text) == 0 do return {}, {}
		if len(view.query) + len(resolution.text) > int(interaction.MAX_CANDIDATE_QUERY_BYTES) do return {}, {}
		query: [interaction.MAX_CANDIDATE_QUERY_BYTES]u8
		copy(query[:], transmute([]u8)view.query)
		copy(query[len(view.query):], transmute([]u8)resolution.text)
		return command_context_refresh_named_locations(commands, string(query[:len(view.query) + len(resolution.text)]))
	}
	if contextual_route == .Component_Query_Delete_Previous {
		if len(view.query) == 0 do return {}, {}
		end := len(view.query) - 1
		bytes := transmute([]u8)view.query
		for end > 0 && bytes[end] & 0xc0 == 0x80 do end -= 1
		return command_context_refresh_named_locations(commands, view.query[:end])
	}
	if contextual_route == .Component_Activate_Current {
		if !view.has_selection || len(view.rows) == 0 do return {}, {}
		row := view.rows[view.selected_row]
		if row.action.kind != .Visit_Location || row.action.owner_generation != view.source_generation ||
		   row.action.secondary != commands.named_location_workflow.batch.generation ||
		   row.action.primary == 0 || row.action.primary > u64(len(commands.named_location_workflow.batch.locations)) {
			command_context_set_diagnostic(commands, "Named location changed; reopen the list")
			return Interaction_Result{changed = true}, {}
		}
		location := commands.named_location_workflow.batch.locations[int(row.action.primary - 1)]
		target_storage: [document.MAX_PATH_BYTES]u8
		if len(location.target) > len(target_storage) do return {}, App_Failure{stage = .Component_Access}
		copy(target_storage[:], transmute([]u8)location.target)
		target := string(target_storage[:len(location.target)])
		point, mark := location.point, location.mark
		has_mark, region_active := location.has_mark, location.region_active
		command_handle := commands.named_location_workflow.command_handle
		return_target := commands.candidate_ui.return_target
		previous, previous_ok := command_context_named_location_return_state(commands, return_target)
		if !named_location_target_is_available(target) {
			command_context_deactivate_context_map(commands, .Completed)
			command_context_close_named_locations(commands)
			if return_target.kind == .Primary_View {
				_, _, _ = editor_session.session_activate(commands.session_owner, return_target.entry)
			}
			command_context_set_diagnostic(commands, "Named location target is unavailable")
			return Interaction_Result{changed = true}, {}
		}
		command_context_deactivate_context_map(commands, .Completed)
		command_context_close_named_locations(commands)
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
			command_context_buffer_session_diagnostic(commands, open_failure)
			return Interaction_Result{changed = true}, {}
		}
		if !command_context_restore_named_location(commands, result.entry, point, mark, has_mark, region_active) {
			if return_target.kind == .Primary_View {
				_, _, _ = editor_session.session_activate(commands.session_owner, return_target.entry)
			}
			command_context_set_diagnostic(commands, "Named location anchor is stale")
			return Interaction_Result{changed = true}, {}
		}
		if previous_ok {
			pushed := command.location_history_push(commands.location_history, previous)
			assert(pushed)
		}
		command_context_set_diagnostic(commands, "Visited named location")
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Close || command_metadata_is_native(metadata, .Keyboard_Quit) {
		return command_context_leave_named_locations(commands)
	}
	return {}, {}
}

@(private)
named_location_target_is_available :: proc(target: string) -> bool {
	return len(target) > 0 && os.is_file(target)
}

@(private)
command_context_restore_named_location :: proc(
	commands: ^Command_Context,
	entry_handle: editor_session.Entry_Handle,
	point, mark: u64,
	has_mark, region_active: bool,
) -> bool {
	access, accessible, _ := editor_session.session_entry_access(commands.session_owner, entry_handle)
	if !accessible do return false
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	if !borrowed do return false
	stats, stats_ok, _ := editor.buffer_stats(entry.buffer)
	if !stats_ok || point > stats.text_bytes || (has_mark && mark > stats.text_bytes) do return false
	point_position, point_ok, _ := editor.buffer_position(entry.buffer, editor.Byte_Offset(point))
	if !point_ok do return false
	if has_mark {
		mark_position, mark_ok, _ := editor.buffer_position(entry.buffer, editor.Byte_Offset(mark))
		if !mark_ok do return false
		_, mark_failure := editor_view.set_mark(entry.view_registry, entry.primary_view, mark_position, region_active)
		if mark_failure.code != .None do return false
	} else {
		_, _ = editor.buffer_selection_clear_mark(entry.buffer)
	}
	moved, _ := editor_view.set_point(entry.view_registry, entry.primary_view, point_position)
	return moved
}

@(private)
command_context_named_location_return_state :: proc(
	commands: ^Command_Context,
	target: editor_session.Visible_Target,
) -> (command.Location_State, bool) {
	if commands == nil || target.kind != .Primary_View do return {}, false
	access, accessible, _ := editor_session.session_entry_access(commands.session_owner, target.entry)
	if !accessible do return {}, false
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	if !borrowed do return {}, false
	selection, selected, _ := editor.buffer_selection_snapshot(entry.buffer)
	if !selected do return {}, false
	return command.location_state_from_selection(selection)
}

@(private)
command_context_refresh_named_locations :: proc(commands: ^Command_Context, query: string) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed do return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	_, refreshed, refresh_failure := interaction.candidate_session_set_query(
		&commands.candidate_ui.session,
		interaction.Candidate_Request {session_id = view.session_id, session_generation = view.session_generation},
		query,
	)
	if !refreshed do command_context_candidate_failure_diagnostic(commands, "Named location query", refresh_failure)
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_leave_named_locations :: proc(commands: ^Command_Context) -> (Interaction_Result, App_Failure) {
	command_context_deactivate_context_map(commands, .Completed)
	return_target := commands.candidate_ui.return_target
	defer command_context_close_named_locations(commands)
	switch return_target.kind {
	case .Primary_View:
		_, activated, failure := editor_session.session_activate(commands.session_owner, return_target.entry)
		if !activated do return {}, App_Failure{stage = .Session_Access, editor_session = failure}
	case .UI_Root:
		_, _, presented, failure := editor_session.session_present_ui(commands.session_owner, commands.session_handle, return_target.ui)
		if !presented do return {}, App_Failure{stage = .Session_Access, editor_session = failure}
	case .None: return {}, App_Failure{stage = .Session_Access}
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_close_named_locations :: proc(commands: ^Command_Context) {
	if commands == nil do return
	if commands.candidate_ui.session.state != nil do _, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	named_location_workflow_reset(&commands.named_location_workflow)
	commands.candidate_ui.return_target = {}
}
