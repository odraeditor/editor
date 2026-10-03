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
import "../result_set"
import "../search"
import edit_transaction "../transaction"
import editor_view "../view"
import "core:fmt"
import "core:strings"

@(private)
Search_Post_Accept :: enum u8 {
	None,
	Materialize_Results,
	Retain_Highlight,
	Retain_Line_Highlight,
}

@(private)
Search_Workflow_State :: struct {
	direction:          search.Direction,
	kind:               search.Pattern_Kind,
	confirmed_direction: search.Direction,
	confirmed_kind:      search.Pattern_Kind,
	diagnostic:         search.Regex_Diagnostic,
	policy:             search.Policy,
	policy_generation:  search.Policy_Generation,
	history_navigation_active: bool,
	query_command:      interaction.Command_Handle,
	query_pattern:      [search.DEFAULT_PATTERN_BYTES]byte,
	query_pattern_length: int,
	query_replacement:  [search.DEFAULT_REPLACEMENT_TEMPLATE_BYTES]byte,
	query_replacement_length: int,
	query_group:        editor_view.Query_Replacement_Group_ID,
	next_query_id:      u64,
	next_generation:    u64,
	next_group:         u64,
	post_accept:        Search_Post_Accept,
}

@(private)
search_workflow_reset :: proc(state: ^Search_Workflow_State) {
	if state == nil {
		return
	}
	state.direction = .Invalid
	state.kind = .Invalid
	state.diagnostic = {}
	state.policy = search.DEFAULT_POLICY
	state.policy_generation = search.Policy_Generation(1)
	state.history_navigation_active = false
	state.query_command = {}
	state.query_pattern_length = 0
	state.query_replacement_length = 0
	state.query_group = {}
	state.post_accept = .None
}

@(private)
dispatch_search_prompt :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	search_snapshot, viewed, view_failure := editor_view.search_session_view(view_registry, view)
	if !viewed {
		return {}, App_Failure{stage = .Command_Dispatch, view = view_failure}
	}
	metadata, resolution, resolved, resolve_failure := command_context_resolve_prompt_input(commands, input)
	if !resolved {
		return {}, resolve_failure
	}
	if resolution.kind != .Command {
		return {}, {}
	}
	if command_metadata_is_cancel(metadata) {
			if commands.prompt_workflow.rejected && search_snapshot.present &&
			   len(search_snapshot.last_successful_query) > 0 {
				_, replace_failure := interaction.prompt_text_replace(
					&commands.prompt_workflow.prompt,
					search_snapshot.last_successful_query,
				)
				if replace_failure.code != .None {
					return {}, App_Failure{stage = .Prompt, prompt_failure = replace_failure}
				}
				commands.prompt_workflow.rejected = false
				commands.search.diagnostic = {}
				return Interaction_Result{changed = true}, {}
			}
			if search_snapshot.present && search_snapshot.status == .Failing &&
			   len(search_snapshot.last_successful_query) > 0 {
				_, replace_failure := interaction.prompt_text_replace(
					&commands.prompt_workflow.prompt,
					search_snapshot.last_successful_query,
				)
				if replace_failure.code != .None {
					return {}, App_Failure{stage = .Prompt, prompt_failure = replace_failure}
				}
				if commands.search.next_query_id == 0 {
					return {}, App_Failure{stage = .Command_Dispatch}
				}
				recovered, recover_failure := command.incremental_search_recover(
					view_registry,
					view,
					search.Query_ID(commands.search.next_query_id),
					commands.search.policy,
					search.DEFAULT_LIMITS,
					commands.persistent_allocator,
					commands.temporary_allocator,
				)
				commands.search.next_query_id += 1
				if !recovered {
					return {}, App_Failure{stage = .Command_Dispatch, command = recover_failure}
				}
				return Interaction_Result{changed = true}, {}
			}
			if search_snapshot.present {
				aborted, abort_failure := command.incremental_search_abort(view_registry, view)
				if !aborted {
					return {}, App_Failure{stage = .Command_Dispatch, command = abort_failure}
				}
			}
			command_context_deactivate_prompt_map(commands, .Cancelled)
			command_context_end_prompt(commands)
			if commands.profile_activation != nil do interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
			return Interaction_Result{changed = true}, {}
	}
	if command_metadata_is_native(metadata, .ISearch_Forward) {
			return command_context_search_turn(
				commands,
				buffer,
				view_registry,
				view,
				search.Direction.Forward,
				command.Incremental_Search_Turn.Repeat,
				constraints,
			)
	}
	if command_metadata_is_native(metadata, .ISearch_Backward) {
			return command_context_search_turn(
				commands,
				buffer,
				view_registry,
				view,
				search.Direction.Backward,
				command.Incremental_Search_Turn.Repeat,
				constraints,
			)
	}
	if command_metadata_is_native(metadata, .Search_Symbol_At_Point) {
		return command_context_search_symbol_at_point(
			commands,
			buffer,
			view_registry,
			view,
			constraints,
		)
	}
	if command_metadata_is_contextual(metadata, .Prompt_Accept) {
		prompt_view, prompt_ok, prompt_failure := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !prompt_ok {
			return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		}
		operator_execution, operator_active := interaction.profile_activation_modal_operator_execution_inspect(
			commands.profile_activation,
		)
		if operator_active && operator_execution.active && operator_execution.operation.count > 1 {
			for _ in 1 ..< operator_execution.operation.count {
				_, repeat_failure := command_context_search_turn(
					commands,
					buffer,
					view_registry,
					view,
					commands.search.direction,
					command.Incremental_Search_Turn.Repeat,
					constraints,
				)
				if repeat_failure.stage != .None {
					interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
					return {}, repeat_failure
				}
			}
			search_snapshot, viewed, view_failure = editor_view.search_session_view(view_registry, view)
			if !viewed {
				interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
				return {}, App_Failure{stage = .Command_Dispatch, view = view_failure}
			}
		}
		post_accept := commands.search.post_accept
		if search_snapshot.present && post_accept == .None {
			accepted, accept_failure := command.incremental_search_accept(view_registry, view)
			if !accepted {
				return {}, App_Failure{stage = .Command_Dispatch, command = accept_failure}
			}
		}
		if search_snapshot.present && !commands.prompt_workflow.rejected && len(prompt_view.text) > 0 {
			commands.search.confirmed_direction = commands.search.direction
			commands.search.confirmed_kind = commands.search.kind
		}
		if search_snapshot.present && !commands.prompt_workflow.rejected && len(prompt_view.text) > 0 {
			stored, store_failure := editor_session.session_search_history_accept(
				commands.session_owner,
				commands.session_handle,
				commands.search.kind,
				prompt_view.text,
				commands.search.policy,
			)
			if !stored {
				return {}, App_Failure{stage = .Session_Access, editor_session = store_failure}
			}
		}
		_, prompt_failure = interaction.prompt_text_accept(&commands.prompt_workflow.prompt)
		if prompt_failure.code != .None {
			return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		}
		command_context_end_prompt(commands)
		commands.search.post_accept = .None
		if post_accept == .Retain_Line_Highlight {
			projected, projection_failure := editor_view.search_session_presentation_set(
				view_registry,
				view,
				.Lines,
			)
			if !projected {
				return {}, App_Failure{stage = .Command_Dispatch, view = projection_failure}
			}
		}
		if post_accept == .Materialize_Results {
			registry, registry_ok, registry_failure := editor_session.session_result_registry(
				commands.session_owner,
				commands.session_handle,
			)
			if !registry_ok {
				return {}, App_Failure{stage = .Session_Access, editor_session = registry_failure}
			}
			expected := result_set.Result_Set_Generation(0)
			if current, present, _ := result_set.registry_view(registry, 1); present {
				expected = current.generation
			}
			_, materialized, _ := result_set.search_materialize(
				registry,
				search_snapshot,
				result_set.Search_Materialization_Config {
					set_id = 1,
					expected_generation = expected,
					source_id = 1,
					buffer = buffer,
					allocator = commands.temporary_allocator,
				},
			)
			if !materialized {
				command_context_set_diagnostic(commands, "No matches to list")
				return Interaction_Result{changed = true}, {}
			}
			accepted, accept_failure := command.incremental_search_accept(view_registry, view)
			if !accepted {
				return {}, App_Failure{stage = .Command_Dispatch, command = accept_failure}
			}
			_, source_active, source_failure := editor_session.session_result_source_activate(
				commands.session_owner,
				commands.session_handle,
				1,
			)
			if !source_active {
				return {}, App_Failure{stage = .Session_Access, editor_session = source_failure}
			}
			return command_context_present_results(commands, 1)
		}
		operator_execution, operator_active = interaction.profile_activation_modal_operator_execution_inspect(
			commands.profile_activation,
		)
		if operator_active && operator_execution.active {
			return command_context_modal_operator_defer_search(
				commands, buffer, view_registry, view,
			)
		}
		return Interaction_Result{changed = true}, {}
	}
	if command_metadata_is_contextual(metadata, .Search_History_Older) ||
	   command_metadata_is_contextual(metadata, .Search_History_Newer) ||
	   command_metadata_is_contextual(metadata, .Search_History_Complete) {
		return command_context_search_history_turn(
			commands,
			buffer,
			view_registry,
			view,
			metadata,
			constraints,
		)
	}
	if command_metadata_is_contextual(metadata, .Search_Extend_Textual) ||
	   command_metadata_is_contextual(metadata, .Search_Extend_Structural) ||
	   command_metadata_is_contextual(metadata, .Search_Extend_Transferred) {
		return command_context_search_extension_turn(
			commands,
			buffer,
			view_registry,
			view,
			search_snapshot,
			metadata,
			constraints,
		)
	}
	if command_metadata_is_contextual(metadata, .Search_Toggle_Case) ||
	   command_metadata_is_contextual(metadata, .Search_Toggle_Pattern) ||
	   command_metadata_is_contextual(metadata, .Search_Toggle_Word) ||
	   command_metadata_is_contextual(metadata, .Search_Toggle_Symbol) ||
	   command_metadata_is_contextual(metadata, .Search_Toggle_Whitespace) {
		return command_context_search_policy_turn(
			commands,
			buffer,
			view_registry,
			view,
			search_snapshot,
			metadata,
			constraints,
		)
	}
	if command_metadata_is_contextual(metadata, .Search_Materialize) {
		registry, registry_ok, registry_failure := editor_session.session_result_registry(
			commands.session_owner,
			commands.session_handle,
		)
		if !registry_ok {
			return {}, App_Failure{stage = .Session_Access, editor_session = registry_failure}
		}
		expected := result_set.Result_Set_Generation(0)
		if current, present, _ := result_set.registry_view(registry, 1); present {
			expected = current.generation
		}
		_, materialized, materialize_failure := result_set.search_materialize(
			registry,
			search_snapshot,
			result_set.Search_Materialization_Config {
				set_id = 1,
				expected_generation = expected,
				source_id = 1,
				buffer = buffer,
				allocator = commands.temporary_allocator,
			},
		)
		if !materialized {
			command_context_set_diagnostic(commands, "Active search cannot be materialized")
			_ = materialize_failure
			return Interaction_Result{changed = true}, {}
		}
		_, source_active, source_failure := editor_session.session_result_source_activate(
			commands.session_owner, commands.session_handle, 1)
		if !source_active {
			return {}, App_Failure{stage = .Session_Access, editor_session = source_failure}
		}
		if search_snapshot.present {
			accepted, accept_failure := command.incremental_search_accept(view_registry, view)
			if !accepted {
				return {}, App_Failure{stage = .Command_Dispatch, command = accept_failure}
			}
		}
		return command_context_present_results(commands, 1)
	}
	if command_metadata_is_contextual(metadata, .Prompt_Delete_Previous) {
		if history_failure := command_context_search_history_end(commands); history_failure.stage != .None {
			return {}, history_failure
		}
		transition, prompt_failure := interaction.prompt_text_delete_previous(&commands.prompt_workflow.prompt)
		if prompt_failure.code != .None {
			return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		}
		if transition != .Changed {
			return {}, {}
		}
		prompt_view, prompt_ok, prompt_view_failure := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !prompt_ok {
			return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_view_failure}
		}
		if len(prompt_view.text) == 0 {
			if search_snapshot.present {
				aborted, abort_failure := command.incremental_search_abort(view_registry, view)
				if !aborted {
					return {}, App_Failure{stage = .Command_Dispatch, command = abort_failure}
				}
			}
			return Interaction_Result{changed = true}, {}
		}
		direction := commands.search.direction
		if search_snapshot.present {
			direction = search_snapshot.direction
		}
		return command_context_search_turn(
			commands,
			buffer,
			view_registry,
			view,
			direction,
			command.Incremental_Search_Turn.Query_Update,
			constraints,
		)
	}
	if command_metadata_is_contextual(metadata, .Prompt_Insert_Text) {
		if history_failure := command_context_search_history_end(commands); history_failure.stage != .None {
			return {}, history_failure
		}
		_, prompt_failure := interaction.prompt_text_append(&commands.prompt_workflow.prompt, resolution.text)
		if prompt_failure.code == .Text_Limit || prompt_failure.code == .Malformed_UTF8 {
			commands.prompt_workflow.rejected = true
			return Interaction_Result{changed = true}, {}
		}
		if prompt_failure.code != .None {
			return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		}
		commands.prompt_workflow.rejected = false
		direction := commands.search.direction
		if search_snapshot.present {
			direction = search_snapshot.direction
		}
		return command_context_search_turn(
			commands,
			buffer,
			view_registry,
			view,
			direction,
			command.Incremental_Search_Turn.Query_Update,
			constraints,
		)
	}
	return {}, {}
}

@(private)
command_context_begin_search :: proc(
	commands: ^Command_Context,
	direction: search.Direction,
	kind: search.Pattern_Kind,
) -> (Interaction_Result, App_Failure) {
	prompt_ok, prompt_failure := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		interaction.Prompt_Config {
			kind = .Text_Entry,
			text_bytes_limit = search.DEFAULT_PATTERN_BYTES,
			allow_empty = true,
			allocator = commands.persistent_allocator,
		},
	)
	if !prompt_ok {
		return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	}
	if !prompt_workflow_begin_projection(&commands.prompt_workflow, .Incremental_Search) {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	commands.search.direction = direction
	commands.search.kind = kind
	commands.search.diagnostic = {}
	commands.search.policy = search.DEFAULT_POLICY
	commands.search.policy_generation = search.Policy_Generation(1)
	commands.search.history_navigation_active = false
	commands.search.post_accept = .None
	if map_failure := command_context_activate_prompt_map(commands, .Incremental_Search); map_failure.stage != .None {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		commands.prompt_workflow.mode = .None
		commands.prompt_workflow.projection_generation = {}
		return {}, map_failure
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_repeat_confirmed_search :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	same_direction: bool,
	count: u64,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if commands.search.confirmed_direction == .Invalid ||
	   (commands.search.confirmed_kind != .Literal &&
	    commands.search.confirmed_kind != .Regular_Expression) ||
	   count == 0 ||
	   count > interaction.MAX_MODAL_COUNT {
		command_context_set_diagnostic(commands, "No confirmed search")
		return Interaction_Result{changed = true}, {}
	}
	direction := commands.search.confirmed_direction
	if !same_direction {
		if direction == .Forward {
			direction = .Backward
		} else if direction == .Backward {
			direction = .Forward
		} else {
			command_context_set_diagnostic(commands, "No confirmed search")
			return Interaction_Result{changed = true}, {}
		}
	}
	kind := commands.search.confirmed_kind
	_, begin_failure := command_context_begin_search(commands, direction, kind)
	if begin_failure.stage != .None {
		return {}, begin_failure
	}
	for _ in 0 ..< count {
		_, turn_failure := command_context_search_turn(
			commands,
			buffer,
			view_registry,
			view,
			direction,
			command.Incremental_Search_Turn.Repeat,
			constraints,
		)
		if turn_failure.stage != .None {
			search_snapshot, viewed, _ := editor_view.search_session_view(view_registry, view)
			if viewed && search_snapshot.present {
				_, _ = command.incremental_search_abort(view_registry, view)
			}
			command_context_end_prompt(commands)
			return {}, turn_failure
		}
	}
	search_snapshot, viewed, view_failure := editor_view.search_session_view(view_registry, view)
	if !viewed {
		command_context_end_prompt(commands)
		return {}, App_Failure{stage = .Command_Dispatch, view = view_failure}
	}
	if !search_snapshot.present {
		command_context_end_prompt(commands)
		command_context_set_diagnostic(commands, "No confirmed search")
		return Interaction_Result{changed = true}, {}
	}
	accepted, accept_failure := command.incremental_search_accept(view_registry, view)
	if !accepted {
		_, _ = command.incremental_search_abort(view_registry, view)
		command_context_end_prompt(commands)
		return {}, App_Failure{stage = .Command_Dispatch, command = accept_failure}
	}
	command_context_end_prompt(commands)
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_search_symbol_at_point :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	logical, viewed, view_failure := editor_view.snapshot(view_registry, view)
	if !viewed do return {}, App_Failure{stage = .Command_Dispatch, view = view_failure}
	document_id, has_document := command_context_active_document_identity(commands, buffer)
	resolved, symbol_ok, symbol_failure := syntax_workflow_symbol_at_point(
		commands.syntax_workflow,
		buffer,
		document_id,
		has_document,
		logical.point_position.byte_offset,
	)
	if !symbol_ok {
		if symbol_failure.code == .No_Symbol ||
		   symbol_failure.code == .Symbol_Capability_Unavailable {
			command_context_set_diagnostic(commands, "No symbol at point")
			return Interaction_Result{changed = true}, {}
		}
		return {}, App_Failure{stage = .Command_Dispatch, language = symbol_failure}
	}
	if commands.prompt_workflow.mode == .None {
		_, begin_failure := command_context_begin_search(commands, .Forward, .Literal)
		if begin_failure.stage != .None do return {}, begin_failure
	}
	commands.search.direction = .Forward
	commands.search.kind = .Literal
	commands.search.policy = search.DEFAULT_POLICY
	commands.search.policy.boundary_mode = .Symbol
	if commands.search.policy_generation == search.Policy_Generation(max(u64)) {
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	commands.search.policy_generation += 1
	name := resolved.name
	_, prompt_failure := interaction.prompt_text_replace(
		&commands.prompt_workflow.prompt,
		string(name.bytes[:name.length]),
	)
	if prompt_failure.code != .None {
		return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	}
	return command_context_search_turn(
		commands,
		buffer,
		view_registry,
		view,
		.Forward,
		.Query_Update,
		constraints,
	)
}

@(private)
command_context_active_document_identity :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
) -> (document.Document_ID, bool) {
	if commands == nil || commands.session_owner == nil || buffer == nil do return 0, false
	access, accessible, _ := editor_session.session_entry_access(
		commands.session_owner,
		commands.current_entry,
	)
	if !accessible {
		if commands.document_owner == nil do return 0, false
		status, inspected, _ := document.document_status(commands.document_owner)
		if !inspected || status.document_id == document.Document_ID(0) do return 0, false
		return status.document_id, true
	}
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	if !borrowed || entry.buffer != buffer || !entry.has_document || entry.document == nil {
		return 0, false
	}
	status, inspected, _ := document.document_status(entry.document)
	if !inspected || status.document_id == document.Document_ID(0) do return 0, false
	return status.document_id, true
}

@(private)
command_context_search_turn :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	direction: search.Direction,
	turn: command.Incremental_Search_Turn,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	prompt_view, prompt_ok, prompt_failure := interaction.prompt_view(&commands.prompt_workflow.prompt)
	if !prompt_ok {
		return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	}
	commands.search.direction = direction
	if len(prompt_view.text) == 0 {
		if turn != .Repeat {
			return Interaction_Result{changed = true}, {}
		}
		batch, copied, copy_failure := editor_session.session_search_history_descriptors(
			commands.session_owner,
			commands.session_handle,
			commands.search.kind,
			commands.temporary_allocator,
		)
		if !copied {
			return {}, App_Failure{stage = .Session_Access, editor_session = copy_failure}
		}
		defer editor_session.search_history_batch_close(&batch)
		if len(batch.descriptors) == 0 {
			return Interaction_Result{changed = true}, {}
		}
		descriptor := batch.descriptors[0]
		_, replace_failure := interaction.prompt_text_replace(
			&commands.prompt_workflow.prompt,
			descriptor.pattern,
		)
		if replace_failure.code != .None {
			return {}, App_Failure{stage = .Prompt, prompt_failure = replace_failure}
		}
		if descriptor.policy != commands.search.policy {
			if commands.search.policy_generation == search.Policy_Generation(max(u64)) {
				return {}, App_Failure{stage = .Command_Dispatch}
			}
			commands.search.policy = descriptor.policy
			commands.search.policy_generation += 1
		}
		prompt_view, prompt_ok, prompt_failure = interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !prompt_ok {
			return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		}
	}
	if commands.search.next_query_id == 0 || commands.search.next_generation == 0 {
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	query_id := commands.search.next_query_id
	generation := commands.search.next_generation
	commands.search.next_query_id += 1
	commands.search.next_generation += 1
	changed, searched, search_failure := command.incremental_search(
		command.Incremental_Search_Request {
			buffer = buffer,
			view_registry = view_registry,
			view = view,
			pattern = prompt_view.text,
			pattern_kind = commands.search.kind,
			direction = direction,
			turn = turn,
			query_id = search.Query_ID(query_id),
			search_generation = search.Search_Generation(generation),
			policy_generation = commands.search.policy_generation,
			policy = commands.search.policy,
			limits = search.DEFAULT_LIMITS,
			profile = display.terminal_unicode17_profile(),
			constraints = constraints,
			persistent_allocator = commands.persistent_allocator,
			temporary_allocator = commands.temporary_allocator,
		},
	)
	if !searched {
		if search_failure.search_code == .Regex_Parser_Error ||
		   search_failure.search_code == .Regex_Compiler_Error {
			commands.prompt_workflow.rejected = true
			commands.search.diagnostic = search_failure.search_diagnostic
			return Interaction_Result{changed = true}, {}
		}
		return {}, App_Failure{stage = .Command_Dispatch, command = search_failure}
	}
	commands.prompt_workflow.rejected = false
	commands.search.diagnostic = {}
	presentation := editor_view.Search_Presentation.Matches
	if commands.search.post_accept == .Retain_Line_Highlight {
		presentation = .Lines
	}
	presentation_set, presentation_failure := editor_view.search_session_presentation_set(
		view_registry,
		view,
		presentation,
	)
	if !presentation_set {
		return {}, App_Failure{stage = .Command_Dispatch, view = presentation_failure}
	}
	return Interaction_Result{changed = changed}, {}
}

@(private)
command_context_search_history_turn :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	metadata: interaction.Command_Metadata,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	prompt_view, prompt_ok, prompt_failure := interaction.prompt_view(&commands.prompt_workflow.prompt)
	if !prompt_ok {
		return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	}
	if !commands.search.history_navigation_active {
		started, start_failure := editor_session.session_search_history_begin(
			commands.session_owner,
			commands.session_handle,
			commands.search.kind,
			prompt_view.text,
		)
		if !started {
			return {}, App_Failure{stage = .Session_Access, editor_session = start_failure}
		}
		commands.search.history_navigation_active = true
	}
	recall: editor_session.Search_History_Recall
	recalled := false
	history_failure: editor_session.Failure_Context
	if command_metadata_is_contextual(metadata, .Search_History_Older) {
		recall, recalled, history_failure = editor_session.session_search_history_older(
			commands.session_owner,
			commands.session_handle,
		)
	} else if command_metadata_is_contextual(metadata, .Search_History_Newer) {
		recall, recalled, history_failure = editor_session.session_search_history_newer(
			commands.session_owner,
			commands.session_handle,
		)
	} else {
		batch, copied, copy_failure := editor_session.session_search_history_descriptors(
			commands.session_owner,
			commands.session_handle,
			commands.search.kind,
			commands.temporary_allocator,
		)
		if !copied {
			return {}, App_Failure{stage = .Session_Access, editor_session = copy_failure}
		}
		defer editor_session.search_history_batch_close(&batch)
		for descriptor in batch.descriptors {
			if len(prompt_view.text) == 0 || strings.has_prefix(descriptor.pattern, prompt_view.text) {
				recall = editor_session.Search_History_Recall{present = true, descriptor = descriptor}
				recalled = true
				break
			}
		}
	}
	if !recalled {
		return {}, App_Failure{stage = .Session_Access, editor_session = history_failure}
	}
	if !recall.present {
		return {}, {}
	}
	_, replace_failure := interaction.prompt_text_replace(
		&commands.prompt_workflow.prompt,
		recall.descriptor.pattern,
	)
	if replace_failure.code != .None {
		return {}, App_Failure{stage = .Prompt, prompt_failure = replace_failure}
	}
	if !recall.restored_in_progress && recall.descriptor.policy != commands.search.policy {
		if commands.search.policy_generation == search.Policy_Generation(max(u64)) {
			return {}, App_Failure{stage = .Command_Dispatch}
		}
		commands.search.policy = recall.descriptor.policy
		commands.search.policy_generation += 1
	}
	return command_context_search_turn(
		commands,
		buffer,
		view_registry,
		view,
		commands.search.direction,
		.Query_Update,
		constraints,
	)
}

@(private)
command_context_search_extension_turn :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	snapshot: editor_view.Search_Snapshot,
	metadata: interaction.Command_Metadata,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	extension: command.Search_Query_Extension
	available := false
	extension_failure: command.Failure_Context
	if command_metadata_is_contextual(metadata, .Search_Extend_Transferred) {
		extension, available, extension_failure = command.search_query_extend_transfer(
			commands.kill_ring,
			commands.search.kind,
			search.DEFAULT_PATTERN_BYTES,
			commands.temporary_allocator,
		)
	} else {
		logical, logical_ok, logical_failure := editor_view.snapshot(view_registry, view)
		if !logical_ok {
			return {}, App_Failure{stage = .Command_Dispatch, view = logical_failure}
		}
		origin := logical.point_position.byte_offset
		if snapshot.present && snapshot.has_current &&
		   int(snapshot.current_index) < len(snapshot.occurrences) {
			origin = snapshot.occurrences[snapshot.current_index].end
		}
		unit := command.Search_Extension_Unit.Textual
		if command_metadata_is_contextual(metadata, .Search_Extend_Structural) {
			unit = .Structural
		}
		extension, available, extension_failure = command.search_query_extend_nearby(
			buffer,
			origin,
			unit,
			commands.search.kind,
			search.DEFAULT_PATTERN_BYTES,
			commands.temporary_allocator,
			commands.temporary_allocator,
		)
	}
	if !available {
		if extension_failure.code == .None {
			return {}, {}
		}
		return {}, App_Failure{stage = .Command_Dispatch, command = extension_failure}
	}
	defer command.search_query_extension_close(&extension)
	_, prompt_failure := interaction.prompt_text_append(
		&commands.prompt_workflow.prompt,
		extension.text,
	)
	if prompt_failure.code == .Text_Limit {
		commands.prompt_workflow.rejected = true
		return Interaction_Result{changed = true}, {}
	}
	if prompt_failure.code != .None {
		return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	}
	if history_failure := command_context_search_history_end(commands); history_failure.stage != .None {
		return {}, history_failure
	}
	return command_context_search_turn(
		commands,
		buffer,
		view_registry,
		view,
		commands.search.direction,
		.Query_Update,
		constraints,
	)
}

@(private)
command_context_search_policy_turn :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	snapshot: editor_view.Search_Snapshot,
	metadata: interaction.Command_Metadata,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if commands.search.policy_generation == search.Policy_Generation(max(u64)) {
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	if command_metadata_is_contextual(metadata, .Search_Toggle_Case) {
		if commands.search.policy.case_mode == .Sensitive {
			commands.search.policy.case_mode = .Insensitive
		} else if commands.search.policy.case_mode == .Insensitive {
			commands.search.policy.case_mode = .Sensitive
		} else if snapshot.present && snapshot.effective_case == .Sensitive {
			commands.search.policy.case_mode = .Insensitive
		} else {
			commands.search.policy.case_mode = .Sensitive
		}
	} else if command_metadata_is_contextual(metadata, .Search_Toggle_Pattern) {
		commands.search.kind = .Regular_Expression if commands.search.kind == .Literal else .Literal
	} else if command_metadata_is_contextual(metadata, .Search_Toggle_Word) {
		commands.search.policy.boundary_mode = .Unrestricted if
			commands.search.policy.boundary_mode == .Word else .Word
	} else if command_metadata_is_contextual(metadata, .Search_Toggle_Symbol) {
		commands.search.policy.boundary_mode = .Unrestricted if
			commands.search.policy.boundary_mode == .Symbol else .Symbol
	} else {
		commands.search.policy.whitespace_mode = .Exact if
			commands.search.policy.whitespace_mode == .Flexible else .Flexible
	}
	commands.search.policy_generation += 1
	if command_metadata_is_contextual(metadata, .Search_Toggle_Pattern) {
		if map_failure := command_context_activate_prompt_map(commands, .Incremental_Search);
		   map_failure.stage != .None {
			return {}, map_failure
		}
	}
	prompt_view, prompt_ok, prompt_failure := interaction.prompt_view(&commands.prompt_workflow.prompt)
	if !prompt_ok {
		return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	}
	if len(prompt_view.text) == 0 {
		return Interaction_Result{changed = true}, {}
	}
	return command_context_search_turn(
		commands,
		buffer,
		view_registry,
		view,
		commands.search.direction,
		.Query_Update,
		constraints,
	)
}

@(private)
command_context_search_history_end :: proc(commands: ^Command_Context) -> App_Failure {
	if !commands.search.history_navigation_active {
		return {}
	}
	ended, end_failure := editor_session.session_search_history_end(
		commands.session_owner,
		commands.session_handle,
	)
	if !ended {
		return App_Failure{stage = .Session_Access, editor_session = end_failure}
	}
	commands.search.history_navigation_active = false
	return {}
}

@(private)
command_context_begin_query_replacement :: proc(
	commands: ^Command_Context,
	command_handle: interaction.Command_Handle,
	kind: search.Pattern_Kind,
) -> (Interaction_Result, App_Failure) {
	if commands.search.next_group == 0 {
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	prompt_ok, prompt_failure := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		interaction.Prompt_Config {
			kind = .Text_Entry,
			text_bytes_limit = search.DEFAULT_PATTERN_BYTES,
			allow_empty = false,
			allocator = commands.persistent_allocator,
		},
	)
	if !prompt_ok {
		return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	}
	if !prompt_workflow_begin_projection(&commands.prompt_workflow, .Query_Replacement_Pattern) {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	commands.search.kind = kind
	commands.search.diagnostic = {}
	commands.search.query_command = command_handle
	commands.search.query_pattern_length = 0
	commands.search.query_replacement_length = 0
	commands.search.query_group = editor_view.Query_Replacement_Group_ID(commands.search.next_group)
	commands.search.next_group += 1
	if map_failure := command_context_activate_prompt_map(commands, .Query_Replacement_Pattern); map_failure.stage != .None {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		commands.prompt_workflow.mode = .None
		commands.prompt_workflow.projection_generation = {}
		return {}, map_failure
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_query_replacement_entry :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	metadata, resolution, resolved, resolve_failure := command_context_resolve_prompt_input(commands, input)
	if !resolved {
		return {}, resolve_failure
	}
	if resolution.kind != .Command {
		return {}, {}
	}
	if command_metadata_is_cancel(metadata) {
		command_context_deactivate_prompt_map(commands, .Cancelled)
		command_context_end_prompt(commands)
		return Interaction_Result{changed = true}, {}
	}
	if command_metadata_is_contextual(metadata, .Prompt_Delete_Previous) {
		transition, prompt_failure := interaction.prompt_text_delete_previous(&commands.prompt_workflow.prompt)
		if prompt_failure.code != .None {
			return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		}
		commands.prompt_workflow.rejected = false
		commands.search.diagnostic = {}
		return Interaction_Result{changed = transition == .Changed}, {}
	}
	if command_metadata_is_contextual(metadata, .Prompt_Accept) {
		_, accept_failure := interaction.prompt_text_accept(&commands.prompt_workflow.prompt)
		if accept_failure.code != .None {
			commands.prompt_workflow.rejected = true
			return Interaction_Result{changed = true}, {}
		}
		prompt_view, viewed, view_failure := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !viewed {
			return {}, App_Failure{stage = .Prompt, prompt_failure = view_failure}
		}
		if commands.prompt_workflow.mode == .Query_Replacement_Pattern {
			commands.search.query_pattern_length = len(prompt_view.text)
			copy(
				commands.search.query_pattern[:],
				transmute([]u8)prompt_view.text[:commands.search.query_pattern_length],
			)
			_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
			prompt_ok, prompt_failure := interaction.prompt_init(
				&commands.prompt_workflow.prompt,
				interaction.Prompt_Config {
					kind = .Text_Entry,
					text_bytes_limit = search.DEFAULT_REPLACEMENT_TEMPLATE_BYTES,
					allow_empty = true,
					allocator = commands.persistent_allocator,
				},
			)
			if !prompt_ok {
				return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
			}
			commands.prompt_workflow.mode = .Query_Replacement_Replacement
			commands.prompt_workflow.rejected = false
			if !prompt_workflow_advance_projection(&commands.prompt_workflow) {
				_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
				commands.prompt_workflow.mode = .None
				commands.prompt_workflow.projection_generation = {}
				return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
			}
			if map_failure := command_context_activate_prompt_map(commands, .Query_Replacement_Replacement); map_failure.stage != .None {
				_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
				commands.prompt_workflow.mode = .None
				commands.prompt_workflow.projection_generation = {}
				return {}, map_failure
			}
			return Interaction_Result{changed = true}, {}
		}
		commands.search.query_replacement_length = len(prompt_view.text)
		copy(
			commands.search.query_replacement[:],
			transmute([]u8)prompt_view.text[:commands.search.query_replacement_length],
		)
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		commands.prompt_workflow.mode = .Query_Replacement_Response
		commands.prompt_workflow.rejected = false
		if !prompt_workflow_advance_projection(&commands.prompt_workflow) {
			commands.prompt_workflow.mode = .None
			commands.prompt_workflow.projection_generation = {}
			return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
		}
		if map_failure := command_context_activate_prompt_map(commands, .Query_Replacement_Response); map_failure.stage != .None {
			commands.prompt_workflow.mode = .None
			commands.prompt_workflow.projection_generation = {}
			return {}, map_failure
		}
		result, ran, run_failure := command_context_query_replacement_turn(
			commands,
			buffer,
			view_registry,
			view,
			constraints,
			.Start,
		)
		if !ran {
			if run_failure.command.search_code == .Regex_Parser_Error ||
			   run_failure.command.search_code == .Regex_Compiler_Error {
				commands.search.diagnostic = run_failure.command.search_diagnostic
				return command_context_restart_query_pattern(commands)
			}
			command_context_query_failure_diagnostic(commands, run_failure.command)
			command_context_end_prompt(commands)
			return Interaction_Result{changed = true}, {}
		}
		return command_context_apply_query_result(commands, &result)
	}
	if command_metadata_is_contextual(metadata, .Prompt_Insert_Text) {
		transition, prompt_failure := interaction.prompt_text_append(&commands.prompt_workflow.prompt, resolution.text)
		if prompt_failure.code == .Text_Limit || prompt_failure.code == .Malformed_UTF8 {
			commands.prompt_workflow.rejected = true
			return Interaction_Result{changed = true}, {}
		}
		if prompt_failure.code != .None {
			return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		}
		commands.prompt_workflow.rejected = false
		commands.search.diagnostic = {}
		return Interaction_Result{changed = transition == .Changed}, {}
	}
	return {}, {}
}

@(private)
dispatch_query_replacement_response :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	action := command.Query_Replacement_Action.Invalid
	metadata, resolution, resolved, resolve_failure := command_context_resolve_prompt_input(commands, input)
	if !resolved {
		return {}, resolve_failure
	}
	if resolution.kind != .Command {
		return {}, {}
	}
	if command_metadata_is_cancel(metadata) {
		action = .Cancel
	} else {
		route, route_ok := command.contextual_route_decode(metadata.route)
		if route_ok {
			#partial switch route {
			case .Prompt_Choice_1:        action = .Replace
			case .Prompt_Choice_2:        action = .Skip
			case .Prompt_Choice_3:        action = .Replace_Remaining
			case .Query_Replace_And_Exit: action = .Replace_And_Exit
			case .Query_Quit:             action = .Quit
			case:
			}
		}
	}
	if action == .Invalid {
		return {}, {}
	}
	state, state_ok, state_failure := editor_view.query_replacement_session_view(
		view_registry,
		view,
	)
	if !state_ok {
		return {}, App_Failure{stage = .Command_Dispatch, view = state_failure}
	}
	if !state.present {
		command_context_end_prompt(commands)
		return Interaction_Result{changed = true}, {}
	}
	preparation := command.Query_Replacement_Action.Invalid
	if state.status == .Recomputation_Required {
		preparation = .Recompute
	} else if state.status == .Pending || state.status == .Wrapped {
		preparation = .Continue
	}
	if preparation != .Invalid {
		prepared, ran, run_failure := command_context_query_replacement_turn(
			commands,
			buffer,
			view_registry,
			view,
			constraints,
			preparation,
		)
		if !ran {
			command_context_query_failure_diagnostic(commands, run_failure.command)
			return Interaction_Result{changed = true}, {}
		}
		prepared_status := prepared.status
		prepared_finished := prepared.finished
		prepared_failure := prepared.continuation_failure
		command.query_replacement_result_close(&prepared)
		if prepared_finished {
			command_context_end_prompt(commands)
			return Interaction_Result{changed = true}, {}
		}
		if prepared_failure.code != .None {
			command_context_query_failure_diagnostic(commands, prepared_failure)
			command_context_end_prompt(commands)
			return Interaction_Result{changed = true}, {}
		}
		if prepared_status != .Awaiting_Response {
			return Interaction_Result{changed = true}, {}
		}
	}
	result, ran, run_failure := command_context_query_replacement_turn(
		commands,
		buffer,
		view_registry,
		view,
		constraints,
		action,
	)
	if !ran {
		command_context_query_failure_diagnostic(commands, run_failure.command)
		return Interaction_Result{changed = true}, {}
	}
	return command_context_apply_query_result(commands, &result)
}

@(private)
command_context_query_replacement_turn :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	constraints: display.Viewport_Constraints,
	action: command.Query_Replacement_Action,
) -> (command.Query_Replacement_Result, bool, App_Failure) {
	if commands.next_transaction_id == 0 || commands.next_undo_unit_id == 0 ||
	   commands.search.next_query_id == 0 || commands.search.next_generation == 0 {
		return {}, false, App_Failure{stage = .Command_Dispatch}
	}
	transaction_id := commands.next_transaction_id
	undo_unit_id := commands.next_undo_unit_id
	query_id := commands.search.next_query_id
	search_generation := commands.search.next_generation
	commands.next_transaction_id += 1
	commands.next_undo_unit_id += 1
	commands.search.next_query_id += 1
	commands.search.next_generation += 1
	grouping := command_history_grouping(commands, .Query_Replace, view, transaction_id)
	native := command.Native_Context {
		registry = commands.registry,
		command = commands.search.query_command,
		buffer = buffer,
		view_registry = view_registry,
		view = view,
		profile = display.terminal_unicode17_profile(),
		constraints = constraints,
		temporary_allocator = commands.temporary_allocator,
		persistent_allocator = commands.persistent_allocator,
		transaction_id = edit_transaction.Transaction_ID(transaction_id),
		undo_unit_id = edit_transaction.Undo_Unit_ID(undo_unit_id),
		history_store = commands.history_store,
		history_grouping = grouping,
		event_sequence = transaction_id,
	}
	request := command.Query_Replacement_Request {
		native = native,
		action = action,
		pattern_kind = commands.search.kind,
		direction = .Forward,
		semantic_group = commands.search.query_group,
		query_id = search.Query_ID(query_id),
		search_generation = search.Search_Generation(search_generation),
		policy_generation = search.Policy_Generation(1),
		search_policy = search.DEFAULT_POLICY,
		search_limits = search.DEFAULT_LIMITS,
		replacement_policy = search.DEFAULT_REPLACEMENT_POLICY,
		replace_all_limits = command.DEFAULT_REPLACE_ALL_LIMITS,
		replacement_limits = search.DEFAULT_REPLACEMENT_LIMITS,
	}
	if action == .Start {
		request.pattern = string(commands.search.query_pattern[:commands.search.query_pattern_length])
		request.replacement = string(
			commands.search.query_replacement[:commands.search.query_replacement_length],
		)
	}
	result, ok, command_failure := command.query_replacement(request)
	if !ok {
		return {}, false, App_Failure{stage = .Command_Dispatch, command = command_failure}
	}
	clipboard_workflow_break_kill_sequence(&commands.clipboard_workflow)
	return result, true, {}
}

@(private)
command_context_apply_query_result :: proc(
	commands: ^Command_Context,
	result: ^command.Query_Replacement_Result,
) -> (Interaction_Result, App_Failure) {
	finished := result.finished
	replacements := result.replacements
	skips := result.skips
	continuation_failure := result.continuation_failure
	command.query_replacement_result_close(result)
	if continuation_failure.code != .None {
		command_context_query_failure_diagnostic(commands, continuation_failure)
		command_context_end_prompt(commands)
		return Interaction_Result{changed = true}, {}
	}
	if finished {
		command_context_end_prompt(commands)
		message := fmt.bprintf(
			commands.diagnostic[:],
			"Replaced %d; skipped %d",
			replacements,
			skips,
		)
		commands.diagnostic_length = len(message)
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_restart_query_pattern :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	prompt_ok, prompt_failure := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		interaction.Prompt_Config {
			kind = .Text_Entry,
			text_bytes_limit = search.DEFAULT_PATTERN_BYTES,
			allow_empty = false,
			allocator = commands.persistent_allocator,
		},
	)
	if !prompt_ok {
		return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	}
	_, replace_failure := interaction.prompt_text_replace(
		&commands.prompt_workflow.prompt,
		string(commands.search.query_pattern[:commands.search.query_pattern_length]),
	)
	if replace_failure.code != .None {
		return {}, App_Failure{stage = .Prompt, prompt_failure = replace_failure}
	}
	commands.prompt_workflow.mode = .Query_Replacement_Pattern
	commands.prompt_workflow.rejected = true
	if !prompt_workflow_advance_projection(&commands.prompt_workflow) {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		commands.prompt_workflow.mode = .None
		commands.prompt_workflow.projection_generation = {}
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	if map_failure := command_context_activate_prompt_map(commands, .Query_Replacement_Pattern); map_failure.stage != .None {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		commands.prompt_workflow.mode = .None
		commands.prompt_workflow.projection_generation = {}
		return {}, map_failure
	}
	return Interaction_Result{changed = true}, {}
}
