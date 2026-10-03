// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../editor_session"
import "../interaction"
import "../theme"

@(private)
command_context_present_theme_navigation :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	if commands == nil {
		return {}, App_Failure{stage = .Theme_Access}
	}
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
	)
	if !visible_ok || visible.kind != .Primary_View {
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	inspection, inspected, inspection_failure := theme.theme_registry_inspect(
		&commands.theme_registry,
	)
	if !inspected {
		command_context_set_diagnostic(
			commands,
			theme.failure_code_diagnostic(inspection_failure.code),
		)
		return Interaction_Result{changed = true}, {}
	}

	definition_views: [theme.MAX_DEFINITIONS]theme.Definition_View
	providers: [theme.MAX_DEFINITIONS]theme.Provider_Descriptor
	fields: [theme.MAX_DEFINITIONS][2]string
	annotations: [theme.MAX_DEFINITIONS][3]interaction.Candidate_Annotation_Definition
	descriptors: [theme.MAX_DEFINITIONS]interaction.Candidate_Descriptor_Definition
	count := 0
	for definition_index in 0 ..< inspection.usage.definitions {
		definition, found, definition_failure := theme.theme_registry_definition_at(
			&commands.theme_registry,
			definition_index,
		)
		if !found {
			command_context_set_diagnostic(
				commands,
				theme.failure_code_diagnostic(definition_failure.code),
			)
			return Interaction_Result{changed = true}, {}
		}
		if definition.descriptor.state != .Confirmed do continue
		provider, provider_found, provider_failure := theme.theme_registry_provider(
			&commands.theme_registry,
			definition.descriptor.provider,
		)
		if !provider_found {
			command_context_set_diagnostic(
				commands,
				theme.failure_code_diagnostic(provider_failure.code),
			)
			return Interaction_Result{changed = true}, {}
		}
		definition_views[count] = definition
		providers[count] = provider
		count += 1
	}
	for index in 0 ..< count {
		descriptor := &definition_views[index].descriptor
		provider := &providers[index]
		identity := theme.theme_name_string(&descriptor.identity)
		display_name := theme.display_name_string(&descriptor.display_name)
		provider_name := theme.provider_name_string(&provider.name)
		selection_state := "available"
		if descriptor.handle == inspection.selection.active {
			selection_state = "active"
		}
		if descriptor.handle == inspection.selection.fallback {
			selection_state = "active, fallback" if descriptor.handle == inspection.selection.active else "fallback"
		}
		if descriptor.handle == inspection.selection.baseline {
			selection_state = "active, safe baseline" if descriptor.handle == inspection.selection.active else "safe baseline"
		}
		fields[index] = {identity, provider_name}
		annotations[index] = {
			{kind = .Generic, text = identity},
			{kind = .Provider, text = provider_name},
			{kind = .Availability, text = selection_state},
		}
		descriptors[index] = interaction.Candidate_Descriptor_Definition {
			identity = {
				kind = 5,
				primary = u64(descriptor.handle.definition_id),
				secondary = u64(descriptor.handle.definition_generation),
			},
			label = display_name,
			searchable_fields = fields[index][:],
			annotations = annotations[index][:],
			action = {
				kind = .Select_Theme,
				owner_generation = u64(inspection.selection.registry_generation),
				primary = u64(inspection.selection.registry_id),
				secondary = u64(inspection.selection.selection_generation),
				graph_identity = {
					u64(descriptor.handle.provider_id),
					u64(descriptor.handle.provider_generation),
					u64(descriptor.handle.definition_id),
					u64(descriptor.handle.definition_generation),
					0,
					0,
				},
			},
			availability = .Available,
		}
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
		interaction.Candidate_Source_Definition {
			kind = .Themes,
			scope_identity = u64(inspection.selection.registry_id),
			scope_generation = u64(inspection.selection.registry_generation),
			source_generation = u64(inspection.selection.selection_generation),
			descriptors = descriptors[:count],
		},
	)
	if !initialized {
		command_context_candidate_failure_diagnostic(
			commands,
			"Theme candidate session",
			initialization_failure,
		)
		return Interaction_Result{changed = true}, {}
	}
	keep_session := false
	defer if !keep_session {_, _, _ = interaction.candidate_session_close(&candidate_session)}
	if commands.candidate_ui.catalog.state != nil {
		interaction.command_catalog_close(&commands.candidate_ui.catalog)
	}
	if commands.candidate_ui.session.state != nil {
		_, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	}
	commands.candidate_ui.session = candidate_session
	commands.candidate_ui.return_target = visible
	commands.candidate_ui.theme_selection = inspection.selection
	commands.candidate_ui.next_session_id = session_id + 1
	keep_session = true
	target := candidate_ui_visible_target()
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner,
		commands.session_handle,
		target.ui,
	)
	if !presented {
		return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	commands.pending = {}
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_theme_navigation_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	if commands.candidate_ui.session.state == nil {
		return {}, App_Failure{stage = .Component_Access}
	}
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed || view.source_kind != .Themes {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	if map_failure := command_context_sync_candidate_map(commands, .Themes); map_failure.stage != .None {
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
		if !moved {
			command_context_candidate_failure_diagnostic(commands, "Theme candidate movement", move_failure)
		}
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Query_Text {
		if len(resolution.text) == 0 do return {}, {}
		if len(view.query) + len(resolution.text) > int(interaction.MAX_CANDIDATE_QUERY_BYTES) {
			command_context_set_diagnostic(commands, "Theme query limit reached")
			return Interaction_Result{changed = true}, {}
		}
		query: [interaction.MAX_CANDIDATE_QUERY_BYTES]u8
		copy(query[:], transmute([]u8)view.query)
		copy(query[len(view.query):], transmute([]u8)resolution.text)
		return command_context_refresh_theme_navigation(
			commands,
			string(query[:len(view.query) + len(resolution.text)]),
		)
	}
	if contextual_route == .Component_Query_Delete_Previous {
		if len(view.query) == 0 do return {}, {}
		end := len(view.query) - 1
		bytes := transmute([]u8)view.query
		for end > 0 && bytes[end] & 0xc0 == 0x80 do end -= 1
		return command_context_refresh_theme_navigation(commands, view.query[:end])
	}
	if contextual_route == .Component_Activate_Current {
		if !view.has_selection || len(view.rows) == 0 do return {}, {}
		row := view.rows[view.selected_row]
		current, selected, _ := theme.theme_registry_selection(&commands.theme_registry)
		if !selected || current != commands.candidate_ui.theme_selection ||
		   view.scope_identity != u64(current.registry_id) ||
		   view.scope_generation != u64(current.registry_generation) ||
		   view.source_generation != u64(current.selection_generation) {
			command_context_set_diagnostic(commands, "Themes changed; reopen select-theme")
			return Interaction_Result{changed = true}, {}
		}
		target, target_ok := theme_candidate_action_definition(row.action, current)
		if !target_ok {
			command_context_set_diagnostic(commands, "Theme selection rejected: invalid candidate")
			return Interaction_Result{changed = true}, {}
		}
		definition, found, _ := theme.theme_registry_definition(&commands.theme_registry, target)
		if !found || definition.descriptor.state != .Confirmed {
			command_context_set_diagnostic(commands, "Theme selection rejected: unavailable definition")
			return Interaction_Result{changed = true}, {}
		}
		return_target := commands.candidate_ui.return_target
		if return_target.kind != .Primary_View {
			return {}, App_Failure{stage = .Session_Access}
		}
		_, activated, activation_failure := editor_session.session_activate(
			commands.session_owner,
			return_target.entry,
		)
		if !activated {
			return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
		}
		_, recorded, record_failure := interaction.candidate_session_record_success(
			&commands.candidate_ui.session,
			request,
			row.identity,
		)
		if !recorded {
			command_context_candidate_failure_diagnostic(commands, "Theme candidate recency", record_failure)
		}
		command_context_deactivate_context_map(commands, .Completed)
		command_context_close_theme_navigation(commands)
		if begun, begin_failure := command_context_theme_transition_begin(
			commands,
			.Select,
			current,
			target,
		); !begun {
			command_context_set_diagnostic(
				commands,
				theme.failure_code_diagnostic(begin_failure.theme.code),
			)
		}
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Close || command_metadata_is_native(metadata, .Keyboard_Quit) {
		return command_context_leave_theme_navigation(commands)
	}
	return {}, {}
}

@(private)
command_context_refresh_theme_navigation :: proc(
	commands: ^Command_Context,
	query: string,
) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed || view.source_kind != .Themes {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	_, refreshed, refresh_failure := interaction.candidate_session_set_query(
		&commands.candidate_ui.session,
		interaction.Candidate_Request {
			session_id = view.session_id,
			session_generation = view.session_generation,
		},
		query,
	)
	if !refreshed {
		command_context_candidate_failure_diagnostic(commands, "Theme candidate query", refresh_failure)
	}
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_leave_theme_navigation :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	command_context_deactivate_context_map(commands, .Completed)
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	_, cancelled, cancel_failure := interaction.candidate_session_cancel(
		&commands.candidate_ui.session,
		interaction.Candidate_Request {
			session_id = view.session_id,
			session_generation = view.session_generation,
		},
	)
	if !cancelled {
		return {}, App_Failure{stage = .Component_Access, candidate = cancel_failure}
	}
	return_target := commands.candidate_ui.return_target
	defer command_context_close_theme_navigation(commands)
	commands.diagnostic_length = 0
	if return_target.kind != .Primary_View {
		return {}, App_Failure{stage = .Session_Access}
	}
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
command_context_close_theme_navigation :: proc(commands: ^Command_Context) {
	if commands.candidate_ui.session.state != nil {
		_, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	}
	commands.candidate_ui.return_target = {}
	commands.candidate_ui.theme_selection = {}
}

@(private)
theme_candidate_action_definition :: proc(
	action: interaction.Candidate_Action,
	selection: theme.Selection,
) -> (theme.Definition_Handle, bool) {
	if action.kind != .Select_Theme ||
	   action.owner_generation != u64(selection.registry_generation) ||
	   action.primary != u64(selection.registry_id) ||
	   action.secondary != u64(selection.selection_generation) {
		return {}, false
	}
	return theme.Definition_Handle {
		registry_id = selection.registry_id,
		provider_id = theme.Provider_ID(action.graph_identity[0]),
		provider_generation = theme.Provider_Generation(action.graph_identity[1]),
		definition_id = theme.Definition_ID(action.graph_identity[2]),
		definition_generation = theme.Definition_Generation(action.graph_identity[3]),
	}, action.graph_identity[0] != 0 && action.graph_identity[1] != 0 &&
	   action.graph_identity[2] != 0 && action.graph_identity[3] != 0
}
