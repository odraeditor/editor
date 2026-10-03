// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../editor_session"
import "../interaction"
import "../package_catalog_interaction"
import "core:fmt"

/* Package_Catalog_Runtime_Phase identifies the active guided catalog step. */
Package_Catalog_Runtime_Phase :: enum u8 {
	None,
	Input,
	Confirmation,
	Selection,
}

/* MAX_PACKAGE_CATALOG_CANDIDATES bounds one catalog candidate surface. */
MAX_PACKAGE_CATALOG_CANDIDATES :: 256

/* Package_Catalog_Runtime_Workflow_State owns one guided catalog interaction. */
Package_Catalog_Runtime_Workflow_State :: struct {
	operation:           package_catalog_interaction.Operation,
	action:              command.Package_Catalog_Runtime_Action,
	phase:               Package_Catalog_Runtime_Phase,
	argument:            [command.MAX_PACKAGE_CATALOG_RUNTIME_ARGUMENT_BYTES]u8,
	argument_length:     int,
	confirmation:        [512]u8,
	confirmation_length: int,
	guided_activation:   bool,
}

/* Package_Catalog_Failure_Code identifies a redacted application failure. */
Package_Catalog_Failure_Code :: enum u8 {
	Invalid,
	Endpoint_Unavailable,
	Stale_State,
	Credential_Unavailable,
	Integrity_Conflict,
	Advisory_Blocked,
	Partial_Capability,
}

@(private)
command_context_begin_package_catalog_interaction :: proc(
	commands: ^Command_Context,
	route: command.Native_Route,
) -> (Interaction_Result, App_Failure) {
	if commands == nil do return {}, App_Failure{stage = .Command_Dispatch}
	if commands.package_catalog_interaction_workflow == nil ||
	   commands.package_catalog_runtime_workflow == nil {
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	operation, mapped := package_catalog_interaction_operation(route)
	if !mapped do return {}, App_Failure{stage = .Command_Dispatch}
	snapshot, retained, failure := package_catalog_interaction.workflow_begin(
		commands.package_catalog_interaction_workflow,
		operation,
		package_catalog_interaction.availability_available(),
	)
	if !retained {
		if failure.code == .Busy {
			command_context_set_channel_diagnostic(
				commands,
				.Package,
				"Another package catalog operation is active; press C-g to cancel it",
			)
			return Interaction_Result{changed = true}, {}
		}
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	action, executable := package_catalog_runtime_action(operation)
	if !executable {
		_, _, _ = package_catalog_interaction.workflow_fail(
			commands.package_catalog_interaction_workflow,
			snapshot.generation,
			"Package catalog command is not connected to the runtime service.",
			"Use list, add, disable, remove, refresh, search, describe, or doctor.",
		)
		command_context_set_channel_diagnostic(
			commands,
			.Package,
			"This package catalog command is not available in the current runtime integration",
		)
		return Interaction_Result{changed = true}, {}
	}
	package_catalog_runtime_workflow_reset(commands.package_catalog_runtime_workflow)
	commands.package_catalog_runtime_workflow.operation = operation
	commands.package_catalog_runtime_workflow.action = action
	if action == .Package_Discover || action == .Package_Describe ||
	   action == .Package_Install || action == .Package_Enable ||
	   action == .Package_Disable || action == .Package_Update ||
	   action == .Package_Rollback || action == .Package_Remove {
		_, submitted, _ := package_catalog_interaction.workflow_submit_prompt(
			commands.package_catalog_interaction_workflow,
			snapshot.generation,
		)
		if !submitted do return {}, App_Failure{stage = .Command_Dispatch}
	}
	if action == .Package_Doctor {
		return command_context_execute_package_catalog(commands, action, "", false)
	}
	if action == .Package_Cleanup {
		commands.package_catalog_runtime_workflow.phase = .Confirmation
		confirmation: string = "Remove unreachable package content?"
		commands.package_catalog_runtime_workflow.confirmation_length = copy(
			commands.package_catalog_runtime_workflow.confirmation[:],
			transmute([]u8)confirmation,
		)
		return command_context_begin_package_catalog_prompt(
			commands,
			.Package_Catalog_Confirmation,
			.Fixed_Choice,
		)
	}
	if action == .Package_Discover {
		return command_context_execute_package_catalog(commands, action, "", false)
	}
	if action == .List || action == .Doctor || action == .Package_List ||
	   action == .Disable ||
	   action == .Remove || action == .Refresh || action == .Describe ||
	   action == .Package_Describe || action == .Package_Install ||
	   action == .Package_Enable || action == .Package_Disable ||
	   action == .Package_Update || action == .Package_Rollback ||
	   action == .Package_Remove {
		return command_context_prepare_package_catalog_selection(commands)
	}
	commands.package_catalog_runtime_workflow.phase = .Input
	return command_context_begin_package_catalog_prompt(
		commands,
		.Package_Catalog_Input,
		.Text_Entry,
	)
}

@(private)
command_context_prepare_package_catalog_selection :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	state := commands.package_catalog_runtime_workflow
	if state == nil do return {}, App_Failure{stage = .Command_Dispatch}
	runtime_action := command.Package_Catalog_Runtime_Action.List
	if state.action == .Doctor do runtime_action = .Doctor
	if state.action == .Package_Install do runtime_action = .Package_Discover
	if state.action >= .Package_List && state.action != .Package_Install {
		runtime_action = .Package_List
	}
	result, decoded, failure := command.package_catalog_runtime_command(
		commands.racket_runtime,
		commands.lifecycle_configuration_root,
		runtime_action,
		"",
		false,
		commands.temporary_allocator,
	)
	if !decoded do return command_context_package_catalog_runtime_transport_failure(commands, failure)
	defer command.package_catalog_runtime_result_close(&result)
	if result.status == .Failure {
		return command_context_finish_package_catalog_result(commands, result)
	}
	if (state.action == .List || state.action == .Package_List) &&
	   result.item_count == 0 {
		return command_context_finish_package_catalog_result(commands, result)
	}
	if state.action != .List && state.action != .Doctor && result.item_count == 1 &&
	   len(result.identity) > 0 {
		return command_context_select_package_catalog(commands, result.identity)
	}
	return command_context_present_package_catalog_candidates(commands, result)
}

@(private)
package_catalog_candidate_line :: proc(
	detail: string,
	offset: int,
) -> (line: string, next: int, present: bool) {
	if offset < 0 || offset >= len(detail) do return "", len(detail), false
	end := offset
	for end < len(detail) && detail[end] != '\n' do end += 1
	next = end + 1 if end < len(detail) else end
	return detail[offset:end], next, end > offset
}

@(private)
package_catalog_candidate_fields :: proc(line: string) -> (identity, annotation: string) {
	if len(line) < 3 do return line, ""
	for index in 0 ..< len(line) - 2 {
		if line[index] == ' ' && line[index + 1] == '|' && line[index + 2] == ' ' {
			return line[:index], line[index + 3:]
		}
	}
	return line, ""
}

@(private)
command_context_present_package_catalog_candidates :: proc(
	commands: ^Command_Context,
	result: command.Package_Catalog_Runtime_Result,
) -> (Interaction_Result, App_Failure) {
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
	)
	if !visible_ok do return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	state := commands.package_catalog_runtime_workflow
	if state == nil do return {}, App_Failure{stage = .Command_Dispatch}

	fields: [MAX_PACKAGE_CATALOG_CANDIDATES][2]string
	annotations: [MAX_PACKAGE_CATALOG_CANDIDATES][1]interaction.Candidate_Annotation_Definition
	descriptors: [MAX_PACKAGE_CATALOG_CANDIDATES]interaction.Candidate_Descriptor_Definition
	offset := 0
	count := 0
	source_generation := commands.candidate_ui.next_source_generation
	session_id := commands.candidate_ui.next_session_id
	if source_generation == 0 || source_generation == max(u64) ||
	   session_id == 0 || session_id == max(u64) {
		return {}, App_Failure{stage = .Component_Access}
	}
	for offset < len(result.detail) && count < MAX_PACKAGE_CATALOG_CANDIDATES {
		line, next, present := package_catalog_candidate_line(result.detail, offset)
		offset = next
		if !present do continue
		identity, annotation := line, ""
		if state.action != .Doctor {
			identity, annotation = package_catalog_candidate_fields(line)
		}
		fields[count] = {identity, annotation}
		annotation_count := 0
		if len(annotation) > 0 {
			annotations[count][0] = {kind = .Generic, text = annotation}
			annotation_count = 1
		}
		durable_category := interaction.Candidate_Durable_Category.None
		durable_key := ""
		if state.action != .Doctor {
			durable_category = .Package_Catalog
			durable_key = identity
		}
		descriptors[count] = interaction.Candidate_Descriptor_Definition {
			identity = {kind = 20, primary = u64(count + 1), secondary = result.generation},
			label = identity,
			searchable_fields = fields[count][:],
			annotations = annotations[count][:annotation_count],
			action = {
				kind = .Select_Package_Catalog,
				owner_generation = source_generation,
				primary = u64(count + 1),
				secondary = result.generation,
			},
			availability = .Available,
			durable_category = durable_category,
			durable_key = durable_key,
		}
		count += 1
	}
	if offset < len(result.detail) {
		return {}, App_Failure{stage = .Component_Access}
	}
	if state.action != .Doctor && u64(count) != result.item_count {
		return {}, App_Failure{stage = .Component_Access}
	}
	source_kind := interaction.Candidate_Source_Kind.Package_Catalogs
	if state.action >= .Package_List {
		source_kind = .Packages
	}
	if state.action == .Doctor do source_kind = .Package_Catalog_Diagnostics
	source_definition := interaction.Candidate_Source_Definition {
		kind = source_kind,
		scope_identity = 1,
		scope_generation = max(result.generation, 1),
		source_generation = source_generation,
		descriptors = descriptors[:count],
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
		source_definition,
	)
	if !initialized {
		return {}, App_Failure{stage = .Component_Access, candidate = candidate_failure}
	}
	keep_session := false
	defer if !keep_session do _, _, _ = interaction.candidate_session_close(&candidate_session)
	if commands.candidate_ui.catalog.state != nil {
		interaction.command_catalog_close(&commands.candidate_ui.catalog)
	}
	if commands.candidate_ui.session.state != nil {
		_, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	}
	commands.candidate_ui.session = candidate_session
	commands.candidate_ui.return_target = visible
	commands.candidate_ui.next_session_id = session_id + 1
	commands.candidate_ui.next_source_generation = source_generation + 1
	state.phase = .Selection
	keep_session = true
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner,
		commands.session_handle,
		candidate_ui_visible_target().ui,
	)
	if !presented {
		command_context_close_package_catalog_candidates(commands)
		return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	commands.pending = {}
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_select_package_catalog :: proc(
	commands: ^Command_Context,
	registration_id: string,
) -> (Interaction_Result, App_Failure) {
	state := commands.package_catalog_runtime_workflow
	if state == nil || len(registration_id) == 0 || len(registration_id) > len(state.argument) {
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	state.argument_length = copy(state.argument[:], transmute([]u8)registration_id)
	action := state.action
	if action == .List {
		action = .Describe
		state.action = action
	}
	if action == .Package_List {
		action = .Package_Describe
		state.action = action
	}
	if action == .Package_Discover {
		action = .Package_Install
		state.action = action
		state.guided_activation = true
		return command_context_execute_package_catalog(
			commands,
			action,
			registration_id,
			false,
		)
	}
	if package_catalog_runtime_action_requires_confirmation(action) {
		state.phase = .Confirmation
		state.confirmation_length = copy(
			state.confirmation[:],
			transmute([]u8)fmt.bprintf(
				commands.feedback_content[:],
				"%s %s?",
				package_catalog_runtime_action_name(action),
				registration_id,
			),
		)
		return command_context_begin_package_catalog_prompt(
			commands,
			.Package_Catalog_Confirmation,
			.Fixed_Choice,
		)
	}
	return command_context_execute_package_catalog(commands, action, registration_id, false)
}

@(private)
dispatch_package_catalog_candidate_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed || (view.source_kind != .Package_Catalogs &&
	   view.source_kind != .Packages &&
	   view.source_kind != .Package_Catalog_Diagnostics) {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	if map_failure := command_context_sync_candidate_map(commands, view.source_kind);
	   map_failure.stage != .None {
		return {}, map_failure
	}
	metadata, resolution, resolved, resolution_failure :=
		command_context_resolve_context_input(commands, input)
	if !resolved do return {}, resolution_failure
	if resolution.kind != .Command do return {}, {}
	request := interaction.Candidate_Request {
		session_id = view.session_id,
		session_generation = view.session_generation,
	}
	contextual_route, contextual_ok := command.contextual_route_decode(metadata.route)
	if contextual_ok &&
	   (contextual_route == .Component_Previous_Row ||
	    contextual_route == .Component_Next_Row) {
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
				"Package catalog candidate movement",
				move_failure,
			)
		}
		return Interaction_Result{changed = true}, {}
	}
	if contextual_ok && contextual_route == .Component_Query_Text {
		if len(resolution.text) == 0 do return {}, {}
		if len(view.query) + len(resolution.text) > int(interaction.MAX_CANDIDATE_QUERY_BYTES) {
			command_context_set_channel_diagnostic(commands, .Package, "Package catalog query limit reached")
			return Interaction_Result{changed = true}, {}
		}
		query: [interaction.MAX_CANDIDATE_QUERY_BYTES]u8
		copy(query[:], transmute([]u8)view.query)
		copy(query[len(view.query):], transmute([]u8)resolution.text)
		return command_context_refresh_package_catalog_candidates(
			commands,
			string(query[:len(view.query) + len(resolution.text)]),
		)
	}
	if contextual_ok && contextual_route == .Component_Query_Delete_Previous {
		if len(view.query) == 0 do return {}, {}
		end := len(view.query) - 1
		bytes := transmute([]u8)view.query
		for end > 0 && bytes[end] & 0xc0 == 0x80 do end -= 1
		return command_context_refresh_package_catalog_candidates(commands, view.query[:end])
	}
	if contextual_ok && contextual_route == .Component_Activate_Current {
		if !view.has_selection || len(view.rows) == 0 do return {}, {}
		state := commands.package_catalog_runtime_workflow
		if state == nil do return {}, App_Failure{stage = .Command_Dispatch}
		if state.action == .Doctor do return {}, {}
		row := view.rows[view.selected_row]
		if row.action.kind != .Select_Package_Catalog ||
		   row.action.owner_generation != view.source_generation ||
		   len(row.durable_key) == 0 || len(row.durable_key) > len(state.argument) {
			command_context_set_channel_diagnostic(commands, .Package, "Package candidate list changed; reopen it")
			return Interaction_Result{changed = true}, {}
		}
		registration_length := copy(state.argument[:], transmute([]u8)row.durable_key)
		registration_id := string(state.argument[:registration_length])
		if restore_failure := command_context_complete_package_catalog_selection(commands);
		   restore_failure.stage != .None {
			package_catalog_runtime_cancel(commands)
			return {}, restore_failure
		}
		return command_context_select_package_catalog(commands, registration_id)
	}
	if contextual_route == .Component_Close || command_metadata_is_native(metadata, .Keyboard_Quit) {
		return command_context_leave_package_catalog_candidates(commands)
	}
	return {}, {}
}

@(private)
command_context_refresh_package_catalog_candidates :: proc(
	commands: ^Command_Context,
	query: string,
) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed || (view.source_kind != .Package_Catalogs &&
	   view.source_kind != .Packages &&
	   view.source_kind != .Package_Catalog_Diagnostics) {
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
			"Package catalog candidate query",
			refresh_failure,
		)
	}
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_leave_package_catalog_candidates :: proc(
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
	defer command_context_close_package_catalog_candidates(commands)
	package_catalog_runtime_cancel(commands)
	switch return_target.kind {
	case .Primary_View:
		_, activated, activation_failure := editor_session.session_activate(
			commands.session_owner,
			return_target.entry,
		)
		if !activated {
			return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
		}
	case .UI_Root:
		_, _, presented, present_failure := editor_session.session_present_ui(
			commands.session_owner,
			commands.session_handle,
			return_target.ui,
		)
		if !presented {
			return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
		}
	case .None:
		return {}, App_Failure{stage = .Session_Access}
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_close_package_catalog_candidates :: proc(commands: ^Command_Context) {
	if commands == nil do return
	if commands.candidate_ui.session.state != nil {
		_, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	}
	commands.candidate_ui.return_target = {}
}

@(private)
command_context_complete_package_catalog_selection :: proc(
	commands: ^Command_Context,
) -> App_Failure {
	if commands == nil do return App_Failure{stage = .Session_Access}
	return_target := commands.candidate_ui.return_target
	command_context_deactivate_context_map(commands, .Completed)
	command_context_close_package_catalog_candidates(commands)
	return command_context_restore_package_catalog_return_target(commands, return_target)
}

@(private)
command_context_restore_package_catalog_return_target :: proc(
	commands: ^Command_Context,
	return_target: editor_session.Visible_Target,
) -> App_Failure {
	if commands == nil || commands.session_owner == nil {
		return App_Failure{stage = .Session_Access}
	}
	switch return_target.kind {
	case .Primary_View:
		_, activated, activation_failure := editor_session.session_activate(
			commands.session_owner,
			return_target.entry,
		)
		if !activated {
			return App_Failure{stage = .Session_Access, editor_session = activation_failure}
		}
	case .UI_Root:
		_, _, presented, present_failure := editor_session.session_present_ui(
			commands.session_owner,
			commands.session_handle,
			return_target.ui,
		)
		if !presented {
			return App_Failure{stage = .Session_Access, editor_session = present_failure}
		}
	case .None:
		return App_Failure{stage = .Session_Access}
	}
	return {}
}

@(private)
command_context_package_catalog_interaction_cancel :: proc(commands: ^Command_Context) -> bool {
	if commands == nil || commands.package_catalog_interaction_workflow == nil do return false
	snapshot, present := package_catalog_interaction.workflow_snapshot(
		commands.package_catalog_interaction_workflow,
	)
	if !present || !package_catalog_interaction.snapshot_active(snapshot) do return false
	_, cancelled, _ := package_catalog_interaction.workflow_cancel(
		commands.package_catalog_interaction_workflow,
		snapshot.generation,
	)
	if !cancelled do return false
	if commands.prompt_workflow.mode == .Package_Catalog_Input ||
	   commands.prompt_workflow.mode == .Package_Catalog_Confirmation {
		command_context_end_prompt(commands)
	}
	package_catalog_runtime_workflow_reset(commands.package_catalog_runtime_workflow)
	command_context_set_channel_diagnostic(commands, .Package, "Package catalog operation cancelled")
	return true
}

@(private)
command_context_begin_package_catalog_prompt :: proc(
	commands: ^Command_Context,
	mode: Prompt_Mode,
	kind: interaction.Prompt_Kind,
) -> (Interaction_Result, App_Failure) {
	config := interaction.Prompt_Config {
		kind = kind,
		text_bytes_limit = command.MAX_PACKAGE_CATALOG_RUNTIME_ARGUMENT_BYTES if kind == .Text_Entry else 0,
		allow_empty = false,
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
dispatch_package_catalog_prompt :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	metadata, resolution, resolved, resolve_failure := command_context_resolve_prompt_input(commands, input)
	if !resolved do return {}, resolve_failure
	if resolution.kind != .Command do return {}, {}
	if command_metadata_is_cancel(metadata) {
		_, _ = interaction.prompt_cancel(&commands.prompt_workflow.prompt)
		command_context_end_prompt(commands)
		package_catalog_runtime_cancel(commands)
		return Interaction_Result{changed = true}, {}
	}
	state := commands.package_catalog_runtime_workflow
	if state == nil do return {}, App_Failure{stage = .Command_Dispatch}
	if state.phase == .Confirmation {
		if command_metadata_is_contextual(metadata, .Prompt_Choice_2) {
			command_context_end_prompt(commands)
			package_catalog_runtime_cancel(commands)
			return Interaction_Result{changed = true}, {}
		}
		if !command_metadata_is_contextual(metadata, .Prompt_Choice_1) do return {}, {}
		action := state.action
		argument := string(state.argument[:state.argument_length])
		command_context_end_prompt(commands)
		return command_context_execute_package_catalog(commands, action, argument, true)
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
	argument_value := prompt_view.text
	if state.action == .Add {
		expanded, expanded_ok := command_context_expand_home_path(
			commands,
			prompt_view.text,
			commands.feedback_content[:],
		)
		if !expanded_ok {
			commands.prompt_workflow.rejected = true
			return Interaction_Result{changed = true}, {}
		}
		argument_value = expanded
	}
	state.argument_length = copy(state.argument[:], transmute([]u8)argument_value)
	argument := string(state.argument[:state.argument_length])
	action := state.action
	snapshot, present := package_catalog_interaction.workflow_snapshot(
		commands.package_catalog_interaction_workflow,
	)
	if !present do return {}, App_Failure{stage = .Command_Dispatch}
	if snapshot.phase == .Prompting {
		_, submitted, _ := package_catalog_interaction.workflow_submit_prompt(
			commands.package_catalog_interaction_workflow,
			snapshot.generation,
		)
		if !submitted do return {}, App_Failure{stage = .Command_Dispatch}
	}
	if action == .Add {
		return command_context_preview_package_catalog_add(commands, argument)
	}
	if package_catalog_runtime_action_requires_confirmation(action) {
		state.phase = .Confirmation
		state.confirmation_length = copy(
			state.confirmation[:],
			transmute([]u8)fmt.bprintf(
				commands.feedback_content[:],
				"%s %s?",
				package_catalog_runtime_action_name(action),
				argument,
			),
		)
		command_context_end_prompt(commands)
		return command_context_begin_package_catalog_prompt(
			commands,
			.Package_Catalog_Confirmation,
			.Fixed_Choice,
		)
	}
	command_context_end_prompt(commands)
	return command_context_execute_package_catalog(commands, action, argument, false)
}

@(private)
command_context_preview_package_catalog_add :: proc(
	commands: ^Command_Context,
	argument: string,
) -> (Interaction_Result, App_Failure) {
	result, decoded, failure := command.package_catalog_runtime_command(
		commands.racket_runtime,
		commands.lifecycle_configuration_root,
		.Preview_Add,
		argument,
		false,
		commands.temporary_allocator,
	)
	if !decoded {
		command_context_end_prompt(commands)
		return command_context_package_catalog_runtime_transport_failure(commands, failure)
	}
	defer command.package_catalog_runtime_result_close(&result)
	if result.status != .Confirmation {
		command_context_end_prompt(commands)
		return command_context_finish_package_catalog_result(commands, result)
	}
	state := commands.package_catalog_runtime_workflow
	if state == nil do return {}, App_Failure{stage = .Command_Dispatch}
	state.phase = .Confirmation
	state.confirmation_length = copy(state.confirmation[:], transmute([]u8)result.detail)
	command_context_end_prompt(commands)
	return command_context_begin_package_catalog_prompt(
		commands,
		.Package_Catalog_Confirmation,
		.Fixed_Choice,
	)
}

@(private)
command_context_execute_package_catalog :: proc(
	commands: ^Command_Context,
	action: command.Package_Catalog_Runtime_Action,
	argument: string,
	confirmed: bool,
) -> (Interaction_Result, App_Failure) {
	result, decoded, failure := command.package_catalog_runtime_command(
		commands.racket_runtime,
		commands.lifecycle_configuration_root,
		action,
		argument,
		confirmed,
		commands.temporary_allocator,
	)
	if !decoded do return command_context_package_catalog_runtime_transport_failure(commands, failure)
	defer command.package_catalog_runtime_result_close(&result)
	return command_context_finish_package_catalog_result(commands, result)
}

@(private)
command_context_finish_package_catalog_result :: proc(
	commands: ^Command_Context,
	result: command.Package_Catalog_Runtime_Result,
) -> (Interaction_Result, App_Failure) {
	snapshot, present := package_catalog_interaction.workflow_snapshot(
		commands.package_catalog_interaction_workflow,
	)
	if !present do return {}, App_Failure{stage = .Command_Dispatch}
	state := commands.package_catalog_runtime_workflow
	if state != nil && state.guided_activation && state.action == .Package_Install &&
	   result.status == .Success {
		state.action = .Package_Enable
		state.phase = .Confirmation
		state.confirmation_length = copy(
			state.confirmation[:],
			transmute([]u8)fmt.bprintf(
				commands.feedback_content[:],
				"%s. Enable it and grant these requested authorities?",
				result.detail,
			),
		)
		return command_context_begin_package_catalog_prompt(
			commands,
			.Package_Catalog_Confirmation,
			.Fixed_Choice,
		)
	}
	if state != nil && state.action == .Package_Discover &&
	   result.status == .Success && result.item_count > 0 {
		return command_context_present_package_catalog_candidates(commands, result)
	}
	package_operation := state != nil && state.action >= .Package_List
	failure_message := "Package catalog command failed."
	recovery_message := "Inspect package-catalog-doctor and retry against the current catalog state."
	completion_message := "Package catalog command completed."
	if package_operation {
		failure_message = "Package lifecycle command failed."
		recovery_message = "Inspect package-doctor and retry against the current installed state."
		completion_message = "Package lifecycle command completed."
	}
	if result.status == .Failure {
		_, _, _ = package_catalog_interaction.workflow_fail(
			commands.package_catalog_interaction_workflow,
			snapshot.generation,
			failure_message,
			recovery_message,
		)
	} else {
		_, _, _ = package_catalog_interaction.workflow_complete(
			commands.package_catalog_interaction_workflow,
			snapshot.generation,
			completion_message,
		)
	}
	reload_package_commands := result.status == .Success && state != nil &&
		(state.action == .Package_Enable || state.action == .Package_Disable ||
		 state.action == .Package_Update || state.action == .Package_Rollback ||
		 state.action == .Package_Remove)
	command_context_set_channel_diagnostic(commands, .Package, result.detail)
	package_catalog_runtime_workflow_reset(commands.package_catalog_runtime_workflow)
	if reload_package_commands {
		reloaded, reload_failure := command_context_reload_personal_commands(commands)
		if reload_failure.stage != .None do return {}, reload_failure
		command_context_set_channel_diagnostic(commands, .Package, result.detail)
		reloaded.changed = true
		return reloaded, {}
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_package_catalog_runtime_transport_failure :: proc(
	commands: ^Command_Context,
	failure: command.Failure_Context,
) -> (Interaction_Result, App_Failure) {
	snapshot, present := package_catalog_interaction.workflow_snapshot(
		commands.package_catalog_interaction_workflow,
	)
	if present {
		_, _, _ = package_catalog_interaction.workflow_fail(
			commands.package_catalog_interaction_workflow,
			snapshot.generation,
			"Package catalog runtime call failed.",
			"Inspect package-catalog-doctor and retry.",
		)
	}
	diagnostic := failure.diagnostic
	if len(diagnostic) == 0 do diagnostic = "Package catalog runtime call failed"
	command_context_set_channel_diagnostic(commands, .Package, diagnostic)
	package_catalog_runtime_workflow_reset(commands.package_catalog_runtime_workflow)
	return Interaction_Result{changed = true}, {}
}

@(private)
package_catalog_runtime_cancel :: proc(commands: ^Command_Context) {
	snapshot, present := package_catalog_interaction.workflow_snapshot(
		commands.package_catalog_interaction_workflow,
	)
	if present && package_catalog_interaction.snapshot_active(snapshot) {
		_, _, _ = package_catalog_interaction.workflow_cancel(
			commands.package_catalog_interaction_workflow,
			snapshot.generation,
		)
	}
	package_catalog_runtime_workflow_reset(commands.package_catalog_runtime_workflow)
	command_context_set_channel_diagnostic(commands, .Package, "Package catalog operation cancelled")
}

@(private)
package_catalog_runtime_workflow_reset :: proc(state: ^Package_Catalog_Runtime_Workflow_State) {
	if state != nil do state^ = {}
}

@(private)
package_catalog_runtime_action_requires_confirmation :: proc(
	action: command.Package_Catalog_Runtime_Action,
) -> bool {
	return action == .Add || action == .Remove || action == .Package_Enable ||
	       action == .Package_Update ||
	       action == .Package_Rollback || action == .Package_Remove ||
	       action == .Package_Cleanup
}

@(private)
package_catalog_runtime_action :: proc(
	operation: package_catalog_interaction.Operation,
) -> (command.Package_Catalog_Runtime_Action, bool) {
	switch operation {
	case .Catalog_List:     return .List, true
	case .Catalog_Add:      return .Add, true
	case .Catalog_Disable:  return .Disable, true
	case .Catalog_Remove:   return .Remove, true
	case .Catalog_Refresh:  return .Refresh, true
	case .Catalog_Search:   return .Search, true
	case .Catalog_Describe: return .Describe, true
	case .Catalog_Doctor:   return .Doctor, true
	case .Package_List:     return .Package_List, true
	case .Package_Discover: return .Package_Discover, true
	case .Package_Describe: return .Package_Describe, true
	case .Package_Install:  return .Package_Install, true
	case .Package_Enable:   return .Package_Enable, true
	case .Package_Disable:  return .Package_Disable, true
	case .Package_Update:   return .Package_Update, true
	case .Package_Rollback: return .Package_Rollback, true
	case .Package_Remove:   return .Package_Remove, true
	case .Package_Cleanup:  return .Package_Cleanup, true
	case .Package_Doctor:   return .Package_Doctor, true
	case .Invalid, .Manual_Acquire, .Advisory_List, .Curator_Validate:
		return .Invalid, false
	}
	return .Invalid, false
}

@(private)
package_catalog_runtime_action_name :: proc(action: command.Package_Catalog_Runtime_Action) -> string {
	#partial switch action {
	case .Disable: return "Disable catalog"
	case .Remove:  return "Remove catalog"
	case .Refresh: return "Refresh catalog"
	case .Add:     return "Add catalog"
	case .Package_Install:  return "Install package"
	case .Package_Enable:   return "Enable package"
	case .Package_Disable:  return "Disable package"
	case .Package_Update:   return "Update package"
	case .Package_Rollback: return "Rollback package"
	case .Package_Remove:   return "Remove package"
	case .Package_Cleanup:  return "Clean package content"
	case:          return "Run package catalog command for"
	}
}

@(private)
package_catalog_runtime_input_label :: proc(action: command.Package_Catalog_Runtime_Action) -> string {
	#partial switch action {
	case .Add:      return "Catalog publication path: "
	case .Disable:  return "Catalog registration to disable: "
	case .Remove:   return "Catalog registration to remove: "
	case .Refresh:  return "Catalog registration to refresh: "
	case .Search:   return "Package search: "
	case .Describe: return "Catalog or package identity: "
	case .Package_Discover: return "Package search: "
	case .Package_Describe: return "Package name or release: "
	case .Package_Install:  return "Package release (name@version): "
	case .Package_Enable:   return "Package release (name@version): "
	case .Package_Disable:  return "Package name: "
	case .Package_Update:   return "Update release (name@version): "
	case .Package_Rollback: return "Package name: "
	case .Package_Remove:   return "Package release (name@version): "
	case:           return "Package catalog value: "
	}
}

@(private)
command_context_package_catalog_failure :: proc(
	commands: ^Command_Context,
	generation: u64,
	code: Package_Catalog_Failure_Code,
) -> bool {
	if commands == nil || commands.package_catalog_interaction_workflow == nil do return false
	reason, recovery, described := package_catalog_failure_detail(code)
	if !described do return false
	_, retained, _ := package_catalog_interaction.workflow_fail(
		commands.package_catalog_interaction_workflow,
		generation,
		reason,
		recovery,
	)
	if !retained do return false
	command_context_set_channel_diagnostic(
		commands,
		.Package,
		fmt.bprintf(commands.feedback_content[:], "%s Recovery: %s", reason, recovery),
	)
	return true
}

@(private)
package_catalog_failure_detail :: proc(
	code: Package_Catalog_Failure_Code,
) -> (reason, recovery: string, described: bool) {
	switch code {
	case .Endpoint_Unavailable:
		return "No configured catalog endpoint is currently available.",
		       "Inspect package-catalog-doctor and retry or use confirmed offline state.", true
	case .Stale_State:
		return "The package catalog state changed before the operation completed.",
		       "Repeat the command against the current catalog generation.", true
	case .Credential_Unavailable:
		return "A referenced catalog credential is unavailable.",
		       "Restore the configured credential reference and retry.", true
	case .Integrity_Conflict:
		return "Catalog sources disagree about immutable package content.",
		       "Inspect package-catalog-describe and select an explicit trusted source.", true
	case .Advisory_Blocked:
		return "Trusted advisory policy blocks this exact package content.",
		       "Inspect package-advisory-list before selecting another release.", true
	case .Partial_Capability:
		return "This package catalog operation is not available for the selected source.",
		       "Inspect package-catalog-doctor and select a source that provides the operation.", true
	case .Invalid:
		return "", "", false
	}
	return "", "", false
}

@(private)
package_catalog_interaction_operation :: proc(
	route: command.Native_Route,
) -> (package_catalog_interaction.Operation, bool) {
	#partial switch route {
	case .Package_Catalog_List:       return .Catalog_List, true
	case .Package_Catalog_Add:        return .Catalog_Add, true
	case .Package_Catalog_Disable:    return .Catalog_Disable, true
	case .Package_Catalog_Remove:     return .Catalog_Remove, true
	case .Package_Catalog_Refresh:    return .Catalog_Refresh, true
	case .Package_Catalog_Search:     return .Catalog_Search, true
	case .Package_Catalog_Describe:   return .Catalog_Describe, true
	case .Package_Manual_Acquire:     return .Manual_Acquire, true
	case .Package_Advisory_List:      return .Advisory_List, true
	case .Package_Curator_Validate:   return .Curator_Validate, true
	case .Package_Catalog_Doctor:     return .Catalog_Doctor, true
	case .Package_List:               return .Package_List, true
	case .Package_Discover:           return .Package_Discover, true
	case .Package_Describe:           return .Package_Describe, true
	case .Package_Install:            return .Package_Install, true
	case .Package_Enable:             return .Package_Enable, true
	case .Package_Disable:            return .Package_Disable, true
	case .Package_Update:             return .Package_Update, true
	case .Package_Rollback:           return .Package_Rollback, true
	case .Package_Remove:             return .Package_Remove, true
	case .Package_Cleanup:            return .Package_Cleanup, true
	case .Package_Doctor:             return .Package_Doctor, true
	case:                             return .Invalid, false
	}
}

@(private)
package_catalog_interaction_operation_name :: proc(
	operation: package_catalog_interaction.Operation,
) -> string {
	switch operation {
	case .Catalog_List:      return "Package catalog list"
	case .Catalog_Add:       return "Package catalog registration"
	case .Catalog_Disable:   return "Package catalog disablement"
	case .Catalog_Remove:    return "Package catalog removal"
	case .Catalog_Refresh:   return "Package catalog refresh"
	case .Catalog_Search:    return "Package catalog search"
	case .Catalog_Describe:  return "Package catalog inspection"
	case .Manual_Acquire:    return "Manual package acquisition"
	case .Advisory_List:     return "Package advisory inspection"
	case .Curator_Validate:  return "Package curator validation"
	case .Catalog_Doctor:    return "Package catalog diagnosis"
	case .Package_List:      return "Installed package list"
	case .Package_Discover:  return "Package discovery"
	case .Package_Describe:  return "Package inspection"
	case .Package_Install:   return "Package installation"
	case .Package_Enable:    return "Package enablement"
	case .Package_Disable:   return "Package disablement"
	case .Package_Update:    return "Package update"
	case .Package_Rollback:  return "Package rollback"
	case .Package_Remove:    return "Package removal"
	case .Package_Cleanup:   return "Package cleanup"
	case .Package_Doctor:    return "Package diagnosis"
	case .Invalid:           return "Package catalog operation"
	}
	return "Package catalog operation"
}
