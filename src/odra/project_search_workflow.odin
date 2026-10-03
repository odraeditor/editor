// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../editor"
import "../editor_session"
import "../interaction"
import "../project"
import "../project_search"
import "../result_set"
import "../search"
import "base:runtime"
import "core:fmt"
import "core:strings"
import editor_view "../view"

/* PROJECT_SEARCH_RESULT_SET_ID identifies the replaceable active-Project result set. */
PROJECT_SEARCH_RESULT_SET_ID :: result_set.Result_Set_ID(4)
/* PROJECT_SEARCH_RESULT_SOURCE_ID identifies the maintained native Project provider. */
PROJECT_SEARCH_RESULT_SOURCE_ID :: result_set.Source_ID(4)

@(private)
Project_Search_Workflow_State :: struct {
	provider:                 project_search.Native_Provider,
	command_handle:           interaction.Command_Handle,
	project:                  project.Project_Handle,
	kind:                     search.Pattern_Kind,
	policy:                   project_search.Policy,
	pattern:                  string,
	next_request_id:          project_search.Request_ID,
	next_request_generation:  project_search.Request_Generation,
	next_provider_id:         project_search.Provider_ID,
	next_provider_generation: project_search.Provider_Generation,
	next_query_id:            search.Query_ID,
}

@(private)
command_context_begin_project_search :: proc(
	commands: ^Command_Context,
	kind: search.Pattern_Kind,
	command_handle: interaction.Command_Handle,
) -> (Interaction_Result, App_Failure) {
	active, inspected, inspect_failure := editor_session.session_active_project(
		commands.session_owner, commands.session_handle,
	)
	if !inspected {
		return {}, App_Failure{stage = .Session_Access, editor_session = inspect_failure}
	}
	if !active.active {
		command_context_set_diagnostic(commands, "No active Project")
		return Interaction_Result{changed = true}, {}
	}
	prompt_ok, prompt_failure := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		{kind = .Text_Entry, text_bytes_limit = search.DEFAULT_PATTERN_BYTES,
			allow_empty = false, allocator = commands.persistent_allocator},
	)
	if !prompt_ok {
		return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	}
	if !prompt_workflow_begin_projection(&commands.prompt_workflow, .Project_Search) {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	commands.project_search_workflow.kind = kind
	commands.project_search_workflow.command_handle = command_handle
	commands.prompt_workflow.rejected = false
	if map_failure := command_context_activate_prompt_map(commands, .Project_Search);
	   map_failure.stage != .None {
		command_context_end_prompt(commands)
		return {}, map_failure
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_project_search_prompt :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	metadata, resolution, resolved, resolve_failure := command_context_resolve_prompt_input(commands, input)
	if !resolved do return {}, resolve_failure
	if resolution.kind != .Command do return {}, {}
	if command_metadata_is_cancel(metadata) {
		_, _ = interaction.prompt_cancel(&commands.prompt_workflow.prompt)
		command_context_end_prompt(commands)
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
	pattern: [search.DEFAULT_PATTERN_BYTES]u8
	pattern_length := copy(pattern[:], transmute([]u8)prompt_view.text)
	kind := commands.project_search_workflow.kind
	command_handle := commands.project_search_workflow.command_handle
	command_context_end_prompt(commands)
	return command_context_run_project_search(
		commands, string(pattern[:pattern_length]), kind, command_handle,
		result_set.Result_Set_Generation(0), true,
	)
}

@(private)
command_context_repeat_project_search :: proc(
	commands: ^Command_Context,
	command_handle: interaction.Command_Handle,
) -> (Interaction_Result, App_Failure) {
	state := &commands.project_search_workflow
	if len(state.pattern) == 0 || state.kind == .Invalid {
		command_context_set_diagnostic(commands, "No previous Project search")
		return Interaction_Result{changed = true}, {}
	}
	return command_context_run_project_search(
		commands, state.pattern, state.kind, command_handle,
		result_set.Result_Set_Generation(0), true,
	)
}

@(private)
command_context_run_project_search :: proc(
	commands: ^Command_Context,
	pattern: string,
	kind: search.Pattern_Kind,
	command_handle: interaction.Command_Handle,
	expected_generation: result_set.Result_Set_Generation,
	present: bool,
) -> (Interaction_Result, App_Failure) {
	state := &commands.project_search_workflow
	active, inspected, inspect_failure := editor_session.session_active_project(
		commands.session_owner, commands.session_handle,
	)
	if !inspected do return {}, App_Failure{stage = .Session_Access, editor_session = inspect_failure}
	if !active.active {
		command_context_set_diagnostic(commands, "No active Project")
		return Interaction_Result{changed = true}, {}
	}
	memberships, listed, list_failure := editor_session.session_project_memberships(
		commands.session_owner, commands.session_handle, active.descriptor.handle,
	)
	if !listed do return {}, App_Failure{stage = .Session_Access, editor_session = list_failure}
	defer project.descriptor_batch_close(&memberships)
	if len(memberships.descriptors) == 0 {
		command_context_set_diagnostic(commands, "Active Project has no searchable roots")
		return Interaction_Result{changed = true}, {}
	}
	roots, roots_error := make([]project_search.Root, len(memberships.descriptors), commands.temporary_allocator)
	if roots_error != nil do return {}, App_Failure{stage = .Component_Access}
	defer delete(roots, commands.temporary_allocator)
	for descriptor, index in memberships.descriptors {
		if !project.trust_allows_behavior(descriptor.trust, .Search) {
			command_context_set_diagnostic(commands, "Project search authority is unavailable")
			return Interaction_Result{changed = true}, {}
		}
		roots[index] = {membership = descriptor.handle, path = descriptor.path}
	}
	project_search_workflow_ensure_generations(state)
	request := project_search.Request{
		id = state.next_request_id,
		generation = state.next_request_generation,
		provider = state.next_provider_id,
		provider_generation = state.next_provider_generation,
		project = active.descriptor.handle,
		query_id = state.next_query_id,
		pattern_kind = kind,
		pattern = pattern,
		policy = {search = search.DEFAULT_POLICY, hidden = .Exclude,
			ignored = .Respect, binary = .Exclude},
		search_limits = search.DEFAULT_LIMITS,
		limits = project_search.DEFAULT_LIMITS,
		roots = roots,
	}
	candidate: project_search.Native_Provider
	initialized, initialize_failure := project_search.native_provider_init(
		&candidate, request,
		{persistent = commands.persistent_allocator, temporary = commands.temporary_allocator},
	)
	if !initialized {
		command_context_project_search_diagnostic(commands, "Project search", initialize_failure)
		return Interaction_Result{changed = true}, {}
	}
	keep_candidate := false
	defer if !keep_candidate do _, _ = project_search.native_provider_close(&candidate)
	for {
		inspection, advanced, advance_failure := project_search.native_provider_advance(
			&candidate, active.descriptor.handle,
		)
		if !advanced {
			command_context_project_search_diagnostic(commands, "Project search", advance_failure)
			return Interaction_Result{changed = true}, {}
		}
		if inspection.lifecycle == .Complete || inspection.lifecycle == .Cancelled do break
	}
	registry, registry_ok, registry_failure := editor_session.session_result_registry(
		commands.session_owner, commands.session_handle,
	)
	if !registry_ok do return {}, App_Failure{stage = .Session_Access, editor_session = registry_failure}
	publication_generation := expected_generation
	if publication_generation == result_set.Result_Set_Generation(0) {
		if current, current_ok, _ := result_set.registry_view(registry, PROJECT_SEARCH_RESULT_SET_ID);
		   current_ok {
			publication_generation = current.generation
		}
	}
	owned_pattern, pattern_error := strings.clone(pattern, commands.persistent_allocator)
	if pattern_error != nil do return {}, App_Failure{stage = .Component_Access}
	keep_pattern := false
	defer if !keep_pattern do delete(owned_pattern, commands.persistent_allocator)
	_, materialized, materialize_failure := result_set.project_search_materialize(
		registry, &candidate,
		{set_id = PROJECT_SEARCH_RESULT_SET_ID, expected_generation = publication_generation,
			source_id = PROJECT_SEARCH_RESULT_SOURCE_ID, allocator = commands.temporary_allocator},
	)
	if !materialized {
		_ = materialize_failure
		command_context_set_diagnostic(commands, "Project search results could not be published")
		return Interaction_Result{changed = true}, {}
	}
	if state.provider.state != nil do _, _ = project_search.native_provider_close(&state.provider)
	delete(state.pattern, commands.persistent_allocator)
	state.provider = candidate
	keep_candidate = true
	state.pattern = owned_pattern
	keep_pattern = true
	state.command_handle = command_handle
	state.project = active.descriptor.handle
	state.kind = kind
	state.policy = request.policy
	state.next_request_id += 1
	state.next_request_generation += 1
	state.next_provider_id += 1
	state.next_provider_generation += 1
	state.next_query_id += 1
	_, activated, activation_failure := editor_session.session_result_source_activate(
		commands.session_owner, commands.session_handle, PROJECT_SEARCH_RESULT_SET_ID,
	)
	if !activated do return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
	if present do return command_context_present_results(commands, PROJECT_SEARCH_RESULT_SET_ID)
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_refresh_project_search_results :: proc(
	commands: ^Command_Context,
	current: result_set.View,
) -> (Interaction_Result, App_Failure) {
	state := &commands.project_search_workflow
	if len(state.pattern) == 0 || state.provider.state == nil {
		command_context_set_diagnostic(commands, "Project search source is no longer available")
		return Interaction_Result{changed = true}, {}
	}
	_, run_failure := command_context_run_project_search(
		commands, state.pattern, state.kind, state.command_handle,
		current.generation, false,
	)
	if run_failure.stage != .None do return {}, run_failure
	registry, registry_ok, registry_failure := editor_session.session_result_registry(
		commands.session_owner, commands.session_handle,
	)
	if !registry_ok do return {}, App_Failure{stage = .Session_Access, editor_session = registry_failure}
	updated, viewed, _ := result_set.registry_view(registry, PROJECT_SEARCH_RESULT_SET_ID)
	if !viewed do return {}, App_Failure{stage = .Component_Access}
	source_generation := commands.candidate_ui.next_source_generation
	source, built, source_failure := interaction.result_candidate_source_build(
		updated, source_generation, commands.temporary_allocator,
	)
	if !built do return {}, App_Failure{stage = .Component_Access, candidate = source_failure}
	defer interaction.result_candidate_source_close(&source)
	candidate_view, candidate_ok, candidate_failure := interaction.candidate_session_view(
		&commands.candidate_ui.session,
	)
	if !candidate_ok do return {}, App_Failure{stage = .Component_Access, candidate = candidate_failure}
	_, refreshed, refresh_failure := interaction.candidate_session_refresh(
		&commands.candidate_ui.session,
		{session_id = candidate_view.session_id, session_generation = candidate_view.session_generation},
		source.definition,
	)
	if !refreshed do return {}, App_Failure{stage = .Component_Access, candidate = refresh_failure}
	commands.candidate_ui.next_source_generation = source_generation + 1
	command_context_sync_result_selection(commands)
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_visit_project_search_location :: proc(
	commands: ^Command_Context,
	location: result_set.Location,
	return_target: editor_session.Visible_Target,
) -> bool {
	return command_context_activate_project_search_location(commands, location, return_target, true)
}

@(private)
command_context_move_project_search_location :: proc(
	commands: ^Command_Context,
	location: result_set.Location,
	return_target: editor_session.Visible_Target,
) -> bool {
	return command_context_activate_project_search_location(commands, location, return_target, false)
}

@(private)
command_context_activate_project_search_location :: proc(
	commands: ^Command_Context,
	location: result_set.Location,
	return_target: editor_session.Visible_Target,
	update_candidate_return: bool,
) -> bool {
	state := &commands.project_search_workflow
	if state.provider.state == nil do return false
	active, inspected, _ := editor_session.session_active_project(
		commands.session_owner, commands.session_handle,
	)
	if !inspected || !active.active || active.descriptor.handle != state.project do return false
	match, current, _ := project_search.native_provider_revalidate(&state.provider, location.source_identity)
	if !current do return false
	result, opened, _ := command.buffer_session_find_file(
		{session = commands.session_owner, handle = commands.session_handle,
			command = state.command_handle, configuration = commands.entry_configuration},
		match.path,
	)
	if !opened do return false
	access, accessible, _ := editor_session.session_entry_access(commands.session_owner, result.entry)
	if !accessible do return false
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	if !borrowed do return false
	stats, stats_ok, _ := editor.buffer_stats(entry.buffer)
	if !stats_ok || match.start > stats.text_bytes do return false
	position, positioned, _ := editor.buffer_position(entry.buffer, editor.Byte_Offset(match.start))
	if !positioned do return false
	moved, _ := editor_view.set_point(entry.view_registry, entry.primary_view, position)
	if !moved do return false
	if update_candidate_return {
		commands.candidate_ui.return_target = {kind = .Primary_View, entry = result.entry}
	}
	previous, previous_ok := command_context_named_location_return_state(commands, return_target)
	if previous_ok && commands.location_history != nil {
		_ = command.location_history_push(commands.location_history, previous)
	}
	return true
}

@(private)
command_context_project_search_invalidate :: proc(commands: ^Command_Context) {
	state := &commands.project_search_workflow
	registry, registry_ok, _ := editor_session.session_result_registry(
		commands.session_owner, commands.session_handle,
	)
	if registry_ok {
		if view, viewed, _ := result_set.registry_view(registry, PROJECT_SEARCH_RESULT_SET_ID); viewed {
			_, _, _ = result_set.registry_close_set(
				registry, PROJECT_SEARCH_RESULT_SET_ID, view.generation,
			)
			_, _ = editor_session.session_result_source_clear(
				commands.session_owner, commands.session_handle,
				PROJECT_SEARCH_RESULT_SET_ID, view.generation,
			)
		}
	}
	if state.provider.state != nil do _, _ = project_search.native_provider_close(&state.provider)
	state.project = {}
}

@(private)
project_search_workflow_close :: proc(
	state: ^Project_Search_Workflow_State,
	allocator: runtime.Allocator,
) {
	if state == nil do return
	if state.provider.state != nil do _, _ = project_search.native_provider_close(&state.provider)
	delete(state.pattern, allocator)
	state^ = {}
}

@(private)
project_search_workflow_ensure_generations :: proc(state: ^Project_Search_Workflow_State) {
	if state.next_request_id == 0 do state.next_request_id = 1
	if state.next_request_generation == 0 do state.next_request_generation = 1
	if state.next_provider_id == 0 do state.next_provider_id = 1
	if state.next_provider_generation == 0 do state.next_provider_generation = 1
	if state.next_query_id == 0 do state.next_query_id = 1
}

@(private)
command_context_project_search_diagnostic :: proc(
	commands: ^Command_Context,
	operation: string,
	failure: project_search.Failure,
) {
	message := fmt.bprintf(commands.diagnostic[:], "%s failed: %v (limit %d, actual %d)",
		operation, failure.code, failure.limit, failure.actual)
	commands.diagnostic_length = len(message)
}
