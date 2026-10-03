// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../display"
import "../command"
import "../document"
import "../editor_session"
import "../interaction"
import "../ui"

@(private)
Status_Bar_Interaction_State :: struct {
	active:                  bool,
	actions_only:            bool,
	source_root:             ui.Root_Handle,
	presentation_generation: u64,
}

@(private)
status_bar_interaction_reset :: proc(state: ^Status_Bar_Interaction_State) {
	if state != nil do state^ = {}
}

@(private)
command_context_present_status_bar_segments :: proc(
	commands: ^Command_Context,
	constraints: display.Viewport_Constraints,
	actions_only: bool,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.ui_registry.state == nil || commands.ui_registry.closed ||
	   commands.ui_root.generation == ui.Root_Generation(0) {
		return {}, App_Failure{stage = .Component_Access}
	}
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
	)
	if !visible_ok || visible.kind != .Primary_View {
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	snapshot, copied, copy_failure := ui.registry_snapshot(
		&commands.ui_registry,
		commands.ui_root,
		commands.renderer_profile,
		commands.temporary_allocator,
	)
	if !copied do return {}, App_Failure{stage = .UI, ui = copy_failure}
	defer ui.snapshot_close(&snapshot)
	view, viewed := ui.snapshot_view(&snapshot)
	if !viewed do return {}, App_Failure{stage = .UI, ui = {operation = .Inspect, code = .Invalid_View}}
	status: ui.Status_Region_Descriptor
	status_found := false
	for candidate in view.status_regions {
		if candidate.placement == .Attached && candidate.active && candidate.segment_count > 0 {
			status = candidate
			status_found = true
			break
		}
	}
	if !status_found {
		command_context_set_diagnostic(commands, "No visible Status Bar segments")
		return Interaction_Result{changed = true}, {}
	}
	content, content_ok := ui.snapshot_status_content(view, status)
	if !content_ok do return {}, App_Failure{stage = .UI, ui = {operation = .Inspect, code = .Invalid_Status_Region}}

	descriptors: [ui.MAX_STATUS_SEGMENTS]interaction.Candidate_Descriptor_Definition
	fields: [ui.MAX_STATUS_SEGMENTS]string
	annotations: [ui.MAX_STATUS_SEGMENTS]interaction.Candidate_Annotation_Definition
	count := 0
	for index in 0 ..< int(status.segment_count) {
		segment, inspection, segment_ok := ui.snapshot_status_segment(view, status, index)
		if !segment_ok do return {}, App_Failure{stage = .UI, ui = {operation = .Inspect, code = .Invalid_Status_Region}}
		command_reference := segment.primary_command
		actionable := command_reference.registry_generation != 0
		if actions_only && !actionable do continue
		if int(segment.start_byte) > len(content) ||
		   int(segment.end_byte) > len(content) || segment.start_byte >= segment.end_byte {
			return {}, App_Failure{stage = .UI, ui = {operation = .Inspect, code = .Invalid_Status_Region}}
		}
		action := interaction.Candidate_Action {
			kind = .Inspect_Status_Segment,
			owner_generation = u64(view.root.generation),
			primary = segment.identity,
			secondary = status.presentation_generation,
		}
		if actions_only {
			action = interaction.Candidate_Action {
				kind = .Invoke_Command,
				owner_generation = command_reference.registry_generation,
				primary = u64(command_reference.slot),
				secondary = u64(command_reference.entry_generation),
			}
		}
		field_count := 0
		annotation_count := 0
		if len(inspection) > 0 {
			fields[count] = inspection
			annotations[count] = {kind = .Generic, text = inspection}
			field_count = 1
			annotation_count = 1
		}
		descriptors[count] = interaction.Candidate_Descriptor_Definition {
			identity = {kind = 15, primary = segment.identity, secondary = status.presentation_generation},
			label = content[int(segment.start_byte):int(segment.end_byte)],
			searchable_fields = fields[count:count + field_count],
			annotations = annotations[count:count + annotation_count],
			action = action,
			availability = .Available,
		}
		count += 1
	}

	source := interaction.Candidate_Source_Definition {
		kind = .Status_Segments,
		scope_identity = u64(view.root.registry_id),
		scope_generation = u64(view.root.generation),
		source_generation = status.presentation_generation,
		descriptors = descriptors[:count],
	}
	session_id := commands.candidate_ui.next_session_id
	if session_id == 0 || session_id == max(u64) {
		return {}, App_Failure{stage = .Component_Access}
	}
	candidate_session: interaction.Candidate_Session
	_, initialized, initialization_failure := interaction.candidate_session_init(
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
		return {}, App_Failure{stage = .Component_Access, candidate = initialization_failure}
	}
	keep_session := false
	defer if !keep_session do _, _, _ = interaction.candidate_session_close(&candidate_session)
	if commands.candidate_ui.catalog.state != nil do interaction.command_catalog_close(&commands.candidate_ui.catalog)
	if commands.candidate_ui.session.state != nil do _, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	commands.candidate_ui.session = candidate_session
	commands.candidate_ui.return_target = visible
	commands.candidate_ui.next_session_id = session_id + 1
	commands.status_bar_interaction = Status_Bar_Interaction_State {
		active = true,
		actions_only = actions_only,
		source_root = view.root,
		presentation_generation = status.presentation_generation,
	}
	keep_session = true
	target := candidate_ui_visible_target()
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner,
		commands.session_handle,
		target.ui,
	)
	if !presented {
		status_bar_interaction_reset(&commands.status_bar_interaction)
		return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	commands.pending = {}
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_status_bar_segment_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed || view.source_kind != .Status_Segments ||
	   !status_bar_candidate_source_is_current(commands, view) {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	if map_failure := command_context_sync_candidate_map(commands, view.source_kind);
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
		_, moved, move_failure := interaction.candidate_session_move(&commands.candidate_ui.session, request, delta)
		if !moved {
			command_context_candidate_failure_diagnostic(commands, "Status Bar segment movement", move_failure)
		}
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Query_Text {
		if len(resolution.text) == 0 do return {}, {}
		if len(view.query) + len(resolution.text) > int(interaction.MAX_CANDIDATE_QUERY_BYTES) {
			command_context_set_diagnostic(commands, "Status Bar segment query limit reached")
			return Interaction_Result{changed = true}, {}
		}
		query: [interaction.MAX_CANDIDATE_QUERY_BYTES]u8
		copy(query[:], transmute([]u8)view.query)
		copy(query[len(view.query):], transmute([]u8)resolution.text)
		return status_bar_candidate_query_set(commands, view, string(query[:len(view.query) + len(resolution.text)]))
	}
	if contextual_route == .Component_Query_Delete_Previous {
		if len(view.query) == 0 do return {}, {}
		end := len(view.query) - 1
		bytes := transmute([]u8)view.query
		for end > 0 && bytes[end] & 0xc0 == 0x80 do end -= 1
		return status_bar_candidate_query_set(commands, view, view.query[:end])
	}
	if contextual_route == .Component_Activate_Current {
		if !view.has_selection || len(view.rows) == 0 do return {}, {}
		row := view.rows[view.selected_row]
		if row.action.kind == .Inspect_Status_Segment {
			detail := status_bar_candidate_detail(row)
			copied_detail: [document.MAX_DIAGNOSTIC_BYTES]u8
			detail_length := min(len(detail), len(copied_detail))
			copy(copied_detail[:], transmute([]u8)detail[:detail_length])
			result, failure := command_context_leave_command_navigation(commands, commands.candidate_ui.return_target)
			status_bar_interaction_reset(&commands.status_bar_interaction)
			if failure.stage != .None do return {}, failure
			if detail_length > 0 do command_context_set_diagnostic(commands, string(copied_detail[:detail_length]))
			result.changed = true
			return result, {}
		}
		command_handle, handle_ok := interaction.command_candidate_action_handle(row.action)
		if !handle_ok || command_handle.registry_generation != commands.registry_generation {
			command_context_set_diagnostic(commands, "Status Bar action is stale")
			return Interaction_Result{changed = true}, {}
		}
		status_bar_interaction_reset(&commands.status_bar_interaction)
		return command_context_execute_navigation_selection(
			commands,
			commands.candidate_ui.return_target,
			request,
			row.identity,
			.None,
			"",
			command_handle,
			constraints,
		)
	}
	if contextual_route == .Component_Close || command_metadata_is_native(metadata, .Keyboard_Quit) {
		result, failure := command_context_leave_command_navigation(commands, commands.candidate_ui.return_target)
		status_bar_interaction_reset(&commands.status_bar_interaction)
		return result, failure
	}
	return {}, {}
}

@(private)
status_bar_candidate_source_is_current :: proc(
	commands: ^Command_Context,
	view: interaction.Candidate_View,
) -> bool {
	state := commands.status_bar_interaction
	return state.active && view.scope_identity == u64(state.source_root.registry_id) &&
	       view.scope_generation == u64(state.source_root.generation) &&
	       view.source_generation == state.presentation_generation
}

@(private)
status_bar_candidate_query_set :: proc(
	commands: ^Command_Context,
	view: interaction.Candidate_View,
	query: string,
) -> (Interaction_Result, App_Failure) {
	_, updated, failure := interaction.candidate_session_set_query(
		&commands.candidate_ui.session,
		interaction.Candidate_Request {
			session_id = view.session_id,
			session_generation = view.session_generation,
		},
		query,
	)
	if !updated {
		command_context_candidate_failure_diagnostic(commands, "Status Bar segment query", failure)
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
status_bar_candidate_detail :: proc(row: interaction.Candidate_Row) -> string {
	for annotation in row.annotations {
		if annotation.kind == .Generic do return annotation.text
	}
	return row.label
}
