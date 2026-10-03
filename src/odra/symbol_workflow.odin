// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../document"
import "../editor_session"
import "../interaction"
import "../language"
import "../result_set"

/* SYMBOL_RESULT_SET_ID identifies the replaceable active-buffer symbol result set. */
SYMBOL_RESULT_SET_ID :: result_set.Result_Set_ID(3)
/* SYMBOL_RESULT_SOURCE_ID identifies the built-in symbol result adapter. */
SYMBOL_RESULT_SOURCE_ID :: result_set.Source_ID(3)

@(private)
Symbol_Workflow_State :: struct {
	next_request_generation: language.Symbol_Request_Generation,
	next_result_generation:  language.Symbol_Result_Generation,
}

@(private)
command_context_present_symbol_navigator :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.session_owner == nil {
		return {}, App_Failure{stage = .Session_Access}
	}
	access, accessible, access_failure := editor_session.session_entry_access(
		commands.session_owner,
		commands.current_entry,
	)
	if !accessible {
		return {}, App_Failure{stage = .Session_Access, editor_session = access_failure}
	}
	entry, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
	if !borrowed {
		return {}, App_Failure{stage = .Session_Access, editor_session = borrow_failure}
	}
	_, published, failure := command_context_publish_symbols(
		commands,
		entry,
		result_set.Result_Set_Generation(0),
	)
	if !published {
		if failure.stage == .Command_Dispatch &&
		   (failure.language.code == .Symbol_Capability_Unavailable ||
		    failure.language.code == .Stale_Selection) {
			command_context_set_diagnostic(commands, "No current symbol index")
			return Interaction_Result{changed = true}, {}
		}
		return {}, failure
	}
	_, activated, activation_failure := editor_session.session_result_source_activate(
		commands.session_owner,
		commands.session_handle,
		SYMBOL_RESULT_SET_ID,
	)
	if !activated {
		return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
	}
	return command_context_present_results(commands, SYMBOL_RESULT_SET_ID)
}

@(private)
command_context_publish_symbols :: proc(
	commands: ^Command_Context,
	entry: editor_session.Entry_Borrow,
	expected_generation: result_set.Result_Set_Generation,
) -> (result_set.View, bool, App_Failure) {
	if commands == nil || entry.buffer == nil {
		return {}, false, App_Failure{stage = .Session_Access}
	}
	request_generation := commands.symbol_workflow.next_request_generation
	result_generation := commands.symbol_workflow.next_result_generation
	if request_generation == language.Symbol_Request_Generation(0) do request_generation = 1
	if result_generation == language.Symbol_Result_Generation(0) do result_generation = 1
	if request_generation == language.Symbol_Request_Generation(max(u64)) ||
	   result_generation == language.Symbol_Result_Generation(max(u64)) {
		return {}, false, App_Failure{stage = .Command_Dispatch}
	}
	document_id := document.Document_ID(0)
	has_document := false
	if entry.has_document && entry.document != nil {
		status, inspected, _ := document.document_status(entry.document)
		if inspected && status.document_id != document.Document_ID(0) {
			document_id = status.document_id
			has_document = true
		}
	}
	index, indexed, index_failure := syntax_workflow_symbol_index(
		commands.syntax_workflow,
		entry.buffer,
		document_id,
		has_document,
		request_generation,
		result_generation,
		commands.temporary_allocator,
	)
	if !indexed {
		return {}, false, App_Failure{stage = .Command_Dispatch, language = index_failure}
	}
	defer language.symbol_index_close(&index)
	registry, registry_ok, registry_failure := editor_session.session_result_registry(
		commands.session_owner,
		commands.session_handle,
	)
	if !registry_ok {
		return {}, false, App_Failure{stage = .Session_Access, editor_session = registry_failure}
	}
	_, materialized, materialize_failure := result_set.symbol_materialize(
		registry,
		&index,
		result_set.Symbol_Materialization_Config {
			set_id = SYMBOL_RESULT_SET_ID,
			expected_generation = expected_generation,
			source_id = SYMBOL_RESULT_SOURCE_ID,
			allocator = commands.temporary_allocator,
		},
	)
	if !materialized {
		_ = materialize_failure
		return {}, false, App_Failure{stage = .Component_Access}
	}
	commands.symbol_workflow.next_request_generation = request_generation + 1
	commands.symbol_workflow.next_result_generation = result_generation + 1
	view, viewed, _ := result_set.registry_view(registry, SYMBOL_RESULT_SET_ID)
	if !viewed do return {}, false, App_Failure{stage = .Component_Access}
	return view, true, {}
}

@(private)
command_context_refresh_symbol_results :: proc(
	commands: ^Command_Context,
	current: result_set.View,
) -> (Interaction_Result, App_Failure) {
	if commands.candidate_ui.return_target.kind != .Primary_View {
		return {}, App_Failure{stage = .Session_Access}
	}
	access, accessible, access_failure := editor_session.session_entry_access(
		commands.session_owner,
		commands.candidate_ui.return_target.entry,
	)
	if !accessible {
		return {}, App_Failure{stage = .Session_Access, editor_session = access_failure}
	}
	entry, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
	if !borrowed {
		return {}, App_Failure{stage = .Session_Access, editor_session = borrow_failure}
	}
	updated, published, publish_failure := command_context_publish_symbols(
		commands,
		entry,
		current.generation,
	)
	if !published {
		if publish_failure.stage == .Command_Dispatch {
			command_context_set_diagnostic(commands, "Symbol index is no longer current")
			return Interaction_Result{changed = true}, {}
		}
		return {}, publish_failure
	}
	source_generation := commands.candidate_ui.next_source_generation
	source, built, source_failure := interaction.result_candidate_source_build(
		updated,
		source_generation,
		commands.temporary_allocator,
	)
	if !built {
		return {}, App_Failure{stage = .Component_Access, candidate = source_failure}
	}
	defer interaction.result_candidate_source_close(&source)
	candidate_view, _, _ := interaction.candidate_session_view(&commands.candidate_ui.session)
	_, refreshed, refresh_failure := interaction.candidate_session_refresh(
		&commands.candidate_ui.session,
		{
			session_id = candidate_view.session_id,
			session_generation = candidate_view.session_generation,
		},
		source.definition,
	)
	if !refreshed {
		return {}, App_Failure{stage = .Component_Access, candidate = refresh_failure}
	}
	commands.candidate_ui.next_source_generation = source_generation + 1
	command_context_sync_result_selection(commands)
	return Interaction_Result{changed = true}, {}
}
