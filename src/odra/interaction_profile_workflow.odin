// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../editor_session"
import "../interaction"

@(private)
command_context_present_interaction_profile_navigation :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.profile_activation == nil {
		return {}, App_Failure{stage = .Keymap_Activation}
	}
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
	)
	if !visible_ok || visible.kind != .Primary_View {
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	catalog, catalog_ok := interaction.profile_activation_catalog(commands.profile_activation)
	active_profile, _, selected := interaction.profile_activation_selection(commands.profile_activation)
	if !catalog_ok || !selected {
		return {}, App_Failure{stage = .Keymap_Activation}
	}
	descriptors: [interaction.MAX_INTERACTION_PROFILES]interaction.Candidate_Descriptor_Definition
	fields: [interaction.MAX_INTERACTION_PROFILES][1]string
	annotations: [interaction.MAX_INTERACTION_PROFILES][1]interaction.Candidate_Annotation_Definition
	for profile, index in catalog.profiles {
		state := "available"
		if profile.identity == active_profile do state = "active"
		fields[index] = {state}
		annotations[index] = {{kind = .Generic, text = state}}
		descriptors[index] = interaction.Candidate_Descriptor_Definition {
			identity = {
				kind = 16,
				primary = u64(profile.identity.id),
				secondary = u64(profile.identity.revision),
			},
			label = profile.name,
			searchable_fields = fields[index][:],
			annotations = annotations[index][:],
			action = {
				kind = .Select_Interaction_Profile,
				owner_generation = u64(catalog.generation),
				primary = u64(commands.profile_activation.generation),
				graph_identity = {
					u64(profile.identity.id),
					u64(profile.identity.revision),
					0,
					0,
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
			kind = .Interaction_Profiles,
			scope_identity = u64(catalog.generation),
			scope_generation = u64(commands.profile_activation.generation),
			source_generation = u64(commands.profile_activation.generation),
			descriptors = descriptors[:len(catalog.profiles)],
		},
	)
	if !initialized {
		command_context_candidate_failure_diagnostic(
			commands,
			"Interaction profile candidate session",
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
	commands.candidate_ui.next_session_id = session_id + 1
	keep_session = true
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner,
		commands.session_handle,
		candidate_ui_visible_target().ui,
	)
	if !presented {
		return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	commands.pending = {}
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_interaction_profile_navigation_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed || view.source_kind != .Interaction_Profiles {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	if map_failure := command_context_sync_candidate_map(commands, .Interaction_Profiles); map_failure.stage != .None {
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
			command_context_candidate_failure_diagnostic(
				commands,
				"Interaction profile candidate movement",
				move_failure,
			)
		}
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Query_Text {
		if len(resolution.text) == 0 do return {}, {}
		if len(view.query) + len(resolution.text) > int(interaction.MAX_CANDIDATE_QUERY_BYTES) {
			command_context_set_diagnostic(commands, "Interaction profile query limit reached")
			return Interaction_Result{changed = true}, {}
		}
		query: [interaction.MAX_CANDIDATE_QUERY_BYTES]u8
		copy(query[:], transmute([]u8)view.query)
		copy(query[len(view.query):], transmute([]u8)resolution.text)
		return command_context_refresh_interaction_profile_navigation(
			commands,
			string(query[:len(view.query) + len(resolution.text)]),
		)
	}
	if contextual_route == .Component_Query_Delete_Previous {
		if len(view.query) == 0 do return {}, {}
		end := len(view.query) - 1
		bytes := transmute([]u8)view.query
		for end > 0 && bytes[end] & 0xc0 == 0x80 do end -= 1
		return command_context_refresh_interaction_profile_navigation(commands, view.query[:end])
	}
	if contextual_route == .Component_Activate_Current {
		if !view.has_selection || len(view.rows) == 0 do return {}, {}
		row := view.rows[view.selected_row]
		catalog, catalog_ok := interaction.profile_activation_catalog(commands.profile_activation)
		if !catalog_ok || view.scope_identity != u64(catalog.generation) ||
		   view.scope_generation != u64(commands.profile_activation.generation) ||
		   view.source_generation != u64(commands.profile_activation.generation) {
			command_context_set_diagnostic(commands, "Interaction profiles changed; reopen select-interaction-profile")
			return Interaction_Result{changed = true}, {}
		}
		target, target_ok := interaction_profile_candidate_action(row.action, catalog, commands.profile_activation.generation)
		if !target_ok {
			command_context_set_diagnostic(commands, "Interaction profile selection rejected: invalid candidate")
			return Interaction_Result{changed = true}, {}
		}
		selected_profile, selection_failure := interaction.profile_activation_select_profile(
			commands.profile_activation,
			commands.registry,
			interaction.Profile_Selection_Request {
				catalog_generation = catalog.generation,
				snapshot_generation = commands.profile_activation.generation,
				target = target,
			},
			commands.active_interaction_context,
			&commands.pending,
			interaction.DEFAULT_RESOLUTION_POLICY,
			commands.persistent_allocator,
		)
		if !selected_profile {
			command_context_set_diagnostic(
				commands,
				"Interaction profile selection rejected",
			)
			_ = selection_failure
			return Interaction_Result{changed = true}, {}
		}
		return_target := commands.candidate_ui.return_target
		if return_target.kind != .Primary_View {
			return {}, App_Failure{stage = .Session_Access}
		}
		_, recorded, record_failure := interaction.candidate_session_record_success(
			&commands.candidate_ui.session,
			request,
			row.identity,
		)
		if !recorded {
			command_context_candidate_failure_diagnostic(
				commands,
				"Interaction profile candidate recency",
				record_failure,
			)
		}
		command_context_deactivate_context_map(commands, .Completed)
		command_context_close_interaction_profile_navigation(commands)
		_, activated, activation_failure := editor_session.session_activate(
			commands.session_owner,
			return_target.entry,
		)
		if !activated {
			return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
		}
		commands.context_pending = {}
		commands.diagnostic_length = 0
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Close || command_metadata_is_native(metadata, .Keyboard_Quit) {
		return command_context_leave_interaction_profile_navigation(commands)
	}
	return {}, {}
}

@(private)
command_context_refresh_interaction_profile_navigation :: proc(
	commands: ^Command_Context,
	query: string,
) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed || view.source_kind != .Interaction_Profiles {
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
		command_context_candidate_failure_diagnostic(
			commands,
			"Interaction profile candidate query",
			refresh_failure,
		)
	}
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_leave_interaction_profile_navigation :: proc(
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
	defer command_context_close_interaction_profile_navigation(commands)
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
command_context_close_interaction_profile_navigation :: proc(commands: ^Command_Context) {
	if commands.candidate_ui.session.state != nil {
		_, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	}
	commands.candidate_ui.return_target = {}
}

@(private)
interaction_profile_candidate_action :: proc(
	action: interaction.Candidate_Action,
	catalog: interaction.Profile_Catalog_Definition,
	snapshot_generation: interaction.Snapshot_Generation,
) -> (interaction.Profile_Identity, bool) {
	if action.kind != .Select_Interaction_Profile ||
	   action.owner_generation != u64(catalog.generation) ||
	   action.primary != u64(snapshot_generation) ||
	   action.graph_identity[0] == 0 || action.graph_identity[1] == 0 {
		return {}, false
	}
	target := interaction.Profile_Identity {
		id = interaction.Profile_ID(action.graph_identity[0]),
		revision = interaction.Profile_Revision(action.graph_identity[1]),
	}
	for profile in catalog.profiles do if profile.identity == target do return target, true
	return {}, false
}

@(private)
command_context_transition_modal_state :: proc(
	commands: ^Command_Context,
	target_name: string,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.profile_activation == nil || len(target_name) == 0 {
		return {}, App_Failure{stage = .Keymap_Activation}
	}
	profile, source, selected := interaction.profile_activation_selection(commands.profile_activation)
	catalog, catalog_ok := interaction.profile_activation_catalog(commands.profile_activation)
	if !selected || !catalog_ok {
		return {}, App_Failure{stage = .Keymap_Activation}
	}
	target: interaction.Interaction_State_Identity
	for candidate_profile in catalog.profiles {
		if candidate_profile.identity != profile do continue
		for state in candidate_profile.states do if state.name == target_name {
			target = state.identity
			break
		}
	}
	if target.id == interaction.Interaction_State_ID(0) || target == source.identity {
		return {}, {}
	}
	transitioned, transition_failure := interaction.profile_activation_transition_state(
		commands.profile_activation,
		commands.registry,
		interaction.State_Transition_Request {
			catalog_generation = catalog.generation,
			snapshot_generation = commands.profile_activation.generation,
			profile = profile,
			source = source.identity,
			target = target,
		},
		commands.active_interaction_context,
		&commands.pending,
		interaction.DEFAULT_RESOLUTION_POLICY,
		commands.persistent_allocator,
	)
	if !transitioned {
		_ = transition_failure
		command_context_set_diagnostic(commands, "Modal state transition rejected")
		return Interaction_Result{changed = true}, {}
	}
	commands.context_pending = {}
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}
