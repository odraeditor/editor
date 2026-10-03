// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../editor"
import "../editor_session"
import "../interaction"
import "../ui"
import editor_view "../view"
import "core:strconv"

@(private)
Prompt_Mode :: enum u8 {
	None,
	Save_Path,
	Write_File_Path,
	Insert_File_Path,
	Navigation_Target,
	Find_File,
	Find_Alternate_File,
	Find_File_Other_Pane,
	Darek_Show_Directory,
	Switch_To_Buffer,
	Kill_Buffer,
	Project_Create_Directory,
	Project_Promote_Name,
	Terminal_Rename,
	Terminal_Kill_Choice,
	Dir_Abandonment_Choice,
	Kill_File_Discard_Choice,
	Kill_Unassociated_Choice,
	Kill_Save_Path,
	Marked_Kill_Choice,
	Project_Close_Choice,
	Marked_Save_Path,
	Last_Pane_Exit_Choice,
	Terminal_Exit_Choice,
	Exit_Choice,
	Exit_Save_Path,
	Incremental_Search,
	Project_Search,
	Query_Replacement_Pattern,
	Query_Replacement_Replacement,
	Query_Replacement_Response,
	Keymap_Sequence,
	Keymap_Command,
	Keymap_Map,
	Keyboard_Macro_Name,
	Keyboard_Macro_Call,
	Shell_Command,
	Async_Shell_Command,
	Compile_Command,
	Named_Location_Name,
	Named_Slot_Input,
	Named_Slot_Confirmation,
	Package_Catalog_Input,
	Package_Catalog_Confirmation,
	Result_Edit,
}

@(private)
Prompt_Workflow_State :: struct {
	map_handle:                 interaction.Context_Map_Handle,
	prompt:                     interaction.Prompt,
	mode:                       Prompt_Mode,
	projection_generation:      ui.Model_Generation,
	next_projection_generation: ui.Model_Generation,
	focus_captured:              bool,
	rejected:                   bool,
}

@(private)
command_context_expand_home_path :: proc(
	commands: ^Command_Context,
	path: string,
	storage: []u8,
) -> (string, bool) {
	if len(path) == 0 || path[0] != '~' do return path, true
	if len(path) > 1 && path[1] != '/' do return path, true
	if commands == nil || len(commands.home_directory) == 0 do return "", false
	suffix := path[1:]
	if len(commands.home_directory) > len(storage) - len(suffix) do return "", false
	length := copy(storage, transmute([]u8)commands.home_directory)
	length += copy(storage[length:], transmute([]u8)suffix)
	return string(storage[:length]), true
}

@(private)
prompt_save_discard_cancel_choices :: proc() -> [3]interaction.Prompt_Choice_Definition {
	return {
		{name = "[s]ave", command_name = "prompt-choice-1"},
		{name = "[d]iscard", command_name = "prompt-choice-2"},
		{name = "[c]ancel", command_name = "prompt-choice-3"},
	}
}

@(private)
prompt_yes_no_choices :: proc() -> [2]interaction.Prompt_Choice_Definition {
	return {
		{name = "[y]es", command_name = "prompt-choice-1"},
		{name = "[n]o", command_name = "prompt-choice-2"},
	}
}

@(private)
prompt_yes_no_cancel_choices :: proc() -> [3]interaction.Prompt_Choice_Definition {
	return {
		{name = "[y]es", command_name = "prompt-choice-1"},
		{name = "[n]o", command_name = "prompt-choice-2"},
		{name = "[c]ancel", command_name = "prompt-choice-3"},
	}
}

@(private)
prompt_dir_abandonment_choices :: proc() -> [4]interaction.Prompt_Choice_Definition {
	return {
		{name = "[y]es", command_name = "prompt-choice-1"},
		{name = "[n]o", command_name = "prompt-choice-2"},
		{name = "[c]ancel", command_name = "prompt-choice-3"},
		{name = "[d]on't ask again", command_name = "prompt-choice-4"},
	}
}

@(private)
command_context_begin_keymap_inspection :: proc(
	commands: ^Command_Context,
	command_name: string,
	command_handle: interaction.Command_Handle,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if command_name == "describe-key" {
		if !prompt_workflow_begin_projection(&commands.prompt_workflow, .Keymap_Sequence) {
			return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
		}
		commands.document_workflow.buffer_command = command_handle
		commands.interaction_workflow.inspection_pending = {}
		commands.interaction_workflow.inspection_sequence = {}
		commands.pending = {}
		return Interaction_Result{changed = true}, {}
	}
	if command_name == "where-is" || command_name == "describe-keymap" {
		mode := Prompt_Mode.Keymap_Command
		limit := interaction.MAX_COMMAND_NAME_BYTES
		if command_name == "describe-keymap" {
			mode = .Keymap_Map
			limit = 20
		}
		prompt_ok, prompt_failure := interaction.prompt_init(
			&commands.prompt_workflow.prompt,
			interaction.Prompt_Config {
				kind = .Text_Entry,
				text_bytes_limit = u64(limit),
				allow_empty = false,
				allocator = commands.persistent_allocator,
			},
		)
		if !prompt_ok {
			return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		}
		if !prompt_workflow_begin_projection(&commands.prompt_workflow, mode) {
			_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
			return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
		}
		commands.document_workflow.buffer_command = command_handle
		if map_failure := command_context_activate_prompt_map(commands, mode); map_failure.stage != .None {
			_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
			commands.prompt_workflow.mode = .None
			commands.document_workflow.buffer_command = {}
			return {}, map_failure
		}
		return Interaction_Result{changed = true}, {}
	}
	query := interaction.Inspection_Query{kind = .Bindings}
	if command_name == "describe-keymap-conflicts" {
		query.kind = .Latest_Rejection
	} else if command_name == "describe-keymap-state" {
		query.kind = .Compatibility
		query.include_inactive = true
	} else if command_name != "describe-bindings" {
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	return command_context_present_keymap_inspection(
		commands,
		query,
		buffer,
		view_registry,
		view,
		constraints,
	)
}

@(private)
dispatch_keymap_sequence_prompt :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if input.kind != .Key || input.stroke.kind == .Invalid {
		commands.prompt_workflow.rejected = true
		return Interaction_Result{changed = true}, {}
	}
	if commands.interaction_workflow.inspection_sequence.stroke_count >= interaction.MAX_SEQUENCE_STROKES {
		command_context_end_prompt(commands)
		command_context_set_diagnostic(commands, "Key sequence limit reached")
		return Interaction_Result{changed = true}, {}
	}
	index := commands.interaction_workflow.inspection_sequence.stroke_count
	commands.interaction_workflow.inspection_sequence.strokes[index] = input.stroke
	commands.interaction_workflow.inspection_sequence.stroke_count += 1
	resolution, resolution_failure := interaction.resolve_input(
		commands.keymap,
		commands.registry_generation,
		&commands.interaction_workflow.inspection_pending,
		input,
	)
	if resolution_failure.code != .None {
		command_context_end_prompt(commands)
		return {}, App_Failure{stage = .Command_Resolution, interaction = resolution_failure}
	}
	if resolution.kind == .Pending {
		commands.prompt_workflow.rejected = false
		return Interaction_Result{changed = true}, {}
	}
	if resolution.kind == .Command {
		metadata, found, metadata_failure := interaction.command_metadata(
			commands.registry,
			resolution.command,
		)
		if !found {
			command_context_end_prompt(commands)
			return {}, App_Failure{stage = .Command_Dispatch, interaction = metadata_failure}
		}
		if command_metadata_is_native(metadata, .Keyboard_Quit) {
			command_context_end_prompt(commands)
			return Interaction_Result{changed = true}, {}
		}
	}
	sequence := commands.interaction_workflow.inspection_sequence
	command_context_end_prompt(commands)
	return command_context_present_keymap_inspection(
		commands,
		interaction.Inspection_Query{kind = .Sequence, sequence = sequence},
		buffer,
		view_registry,
		view,
		constraints,
	)
}

@(private)
dispatch_keymap_text_prompt :: proc(
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
		_, cancel_failure := interaction.prompt_cancel(&commands.prompt_workflow.prompt)
		if cancel_failure.code != .None {
			return {}, App_Failure{stage = .Prompt, prompt_failure = cancel_failure}
		}
		command_context_end_prompt(commands)
		return Interaction_Result{changed = true}, {}
	}
	if command_metadata_is_native(metadata, .Execute_Extended_Command) {
		command_context_end_prompt(commands)
		return command_context_present_command_navigation(
			commands,
			buffer,
			view_registry,
			view,
			constraints,
		)
	}
	if command_metadata_is_contextual(metadata, .Prompt_Delete_Previous) {
		transition, prompt_failure := interaction.prompt_text_delete_previous(&commands.prompt_workflow.prompt)
		if prompt_failure.code != .None {
			return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		}
		commands.prompt_workflow.rejected = false
		return Interaction_Result{changed = transition == .Changed}, {}
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
		return Interaction_Result{changed = transition == .Changed}, {}
	}
	if !command_metadata_is_contextual(metadata, .Prompt_Accept) {
		return {}, {}
	}
	_, accept_failure := interaction.prompt_text_accept(&commands.prompt_workflow.prompt)
	if accept_failure.code != .None {
		commands.prompt_workflow.rejected = true
		return Interaction_Result{changed = true}, {}
	}
	prompt_view, viewed, prompt_failure := interaction.prompt_view(&commands.prompt_workflow.prompt)
	if !viewed {
		return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	}
	query: interaction.Inspection_Query
	command_name: [interaction.MAX_COMMAND_NAME_BYTES]u8
	if commands.prompt_workflow.mode == .Keymap_Command {
		_, found, _ := interaction.command_lookup(commands.registry, prompt_view.text)
		if !found {
			commands.prompt_workflow.rejected = true
			return Interaction_Result{changed = true}, {}
		}
		copy(command_name[:], transmute([]u8)prompt_view.text)
		query = interaction.Inspection_Query {
			kind = .Command,
			command_name = string(command_name[:len(prompt_view.text)]),
		}
	} else {
		map_id, parsed := strconv.parse_u64_of_base(prompt_view.text, 10)
		if !parsed || map_id == 0 {
			commands.prompt_workflow.rejected = true
			return Interaction_Result{changed = true}, {}
		}
		query = interaction.Inspection_Query{kind = .Map, map_id = interaction.Map_ID(map_id)}
		probe, found, _ := command.keymap_inspection_run(command.Keymap_Inspection_Request {
			registry = commands.registry,
			activation = commands.profile_activation,
			pending = &commands.pending,
			query = query,
			allocator = commands.temporary_allocator,
		})
		if !found {
			commands.prompt_workflow.rejected = true
			return Interaction_Result{changed = true}, {}
		}
		interaction.inspection_result_close(&probe)
	}
	command_context_end_prompt(commands)
	return command_context_present_keymap_inspection(
		commands,
		query,
		buffer,
		view_registry,
		view,
		constraints,
	)
}

@(private)
dispatch_prompt_mode :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if commands.prompt_workflow.mode == .Keymap_Sequence {
		return dispatch_keymap_sequence_prompt(
			commands,
			buffer,
			view_registry,
			view,
			input,
			constraints,
		)
	}
	if commands.prompt_workflow.mode == .Keymap_Command || commands.prompt_workflow.mode == .Keymap_Map {
		return dispatch_keymap_text_prompt(
			commands,
			buffer,
			view_registry,
			view,
			input,
			constraints,
		)
	}
	if commands.prompt_workflow.mode == .Keyboard_Macro_Name ||
	   commands.prompt_workflow.mode == .Keyboard_Macro_Call {
		return dispatch_keyboard_macro_prompt(
			commands,
			buffer,
			view_registry,
			view,
			input,
			constraints,
		)
	}
	if commands.prompt_workflow.mode == .Shell_Command ||
	   commands.prompt_workflow.mode == .Async_Shell_Command ||
	   commands.prompt_workflow.mode == .Compile_Command {
		return dispatch_shell_command_prompt(commands, input)
	}
	if commands.prompt_workflow.mode == .Incremental_Search {
		return dispatch_search_prompt(commands, buffer, view_registry, view, input, constraints)
	}
	if commands.prompt_workflow.mode == .Project_Search {
		return dispatch_project_search_prompt(commands, input)
	}
	if commands.prompt_workflow.mode == .Query_Replacement_Response {
		return dispatch_query_replacement_response(
			commands,
			buffer,
			view_registry,
			view,
			input,
			constraints,
		)
	}
	if commands.prompt_workflow.mode == .Query_Replacement_Pattern ||
	   commands.prompt_workflow.mode == .Query_Replacement_Replacement {
		return dispatch_query_replacement_entry(
			commands,
			buffer,
			view_registry,
			view,
			input,
			constraints,
		)
	}
	if commands.prompt_workflow.mode == .Find_File ||
	   commands.prompt_workflow.mode == .Find_File_Other_Pane ||
	   commands.prompt_workflow.mode == .Switch_To_Buffer ||
	   commands.prompt_workflow.mode == .Kill_Buffer {
		return dispatch_buffer_session_prompt(commands, input)
	}
	if commands.prompt_workflow.mode == .Project_Create_Directory ||
	   commands.prompt_workflow.mode == .Project_Promote_Name {
		return dispatch_project_prompt(commands, input, constraints)
	}
	if commands.prompt_workflow.mode == .Terminal_Rename {
		return dispatch_terminal_rename_prompt(commands, input)
	}
	if commands.prompt_workflow.mode == .Named_Location_Name {
		return dispatch_named_location_prompt(commands, input)
	}
	if commands.prompt_workflow.mode == .Named_Slot_Input ||
	   commands.prompt_workflow.mode == .Named_Slot_Confirmation {
		return dispatch_named_slot_prompt(commands, input, constraints)
	}
	if commands.prompt_workflow.mode == .Package_Catalog_Input ||
	   commands.prompt_workflow.mode == .Package_Catalog_Confirmation {
		return dispatch_package_catalog_prompt(commands, input)
	}
	if commands.prompt_workflow.mode == .Result_Edit {
		return dispatch_result_edit_prompt(commands, input)
	}
	switch commands.prompt_workflow.mode {
	case .Last_Pane_Exit_Choice:
		return dispatch_last_pane_exit_prompt(commands, input)
	case .Terminal_Exit_Choice:
		return dispatch_terminal_exit_prompt(commands, input)
	case .Terminal_Kill_Choice:
		return dispatch_terminal_kill_prompt(commands, input)
	case .Exit_Choice:
		return dispatch_exit_choice_prompt(commands, buffer, input)
	case .Kill_File_Discard_Choice, .Kill_Unassociated_Choice:
		return dispatch_kill_choice_prompt(commands, input)
	case .Save_Path, .Write_File_Path, .Exit_Save_Path, .Kill_Save_Path:
		return dispatch_save_path_prompt(commands, buffer, input)
	case .Insert_File_Path:
		return dispatch_insert_file_path_prompt(commands, input)
	case .Navigation_Target:
		return dispatch_navigation_target_prompt(commands, input)
	case .Marked_Kill_Choice, .Marked_Save_Path:
		return dispatch_marked_inventory_prompt(commands, input)
	case .Project_Close_Choice:
		return dispatch_project_close_prompt(commands, input, constraints)
	case .Dir_Abandonment_Choice:
		return dispatch_dir_abandonment_prompt(commands, input, constraints)
	case .None, .Find_File, .Find_Alternate_File, .Find_File_Other_Pane, .Darek_Show_Directory,
	     .Switch_To_Buffer, .Kill_Buffer,
	     .Project_Create_Directory, .Project_Promote_Name, .Terminal_Rename,
	     .Incremental_Search, .Project_Search, .Query_Replacement_Pattern,
	     .Query_Replacement_Replacement, .Query_Replacement_Response, .Keymap_Sequence,
	     .Keymap_Command, .Keymap_Map, .Keyboard_Macro_Name, .Keyboard_Macro_Call,
	     .Shell_Command, .Async_Shell_Command, .Compile_Command,
	     .Named_Location_Name,
	     .Named_Slot_Input, .Named_Slot_Confirmation,
	     .Package_Catalog_Input, .Package_Catalog_Confirmation, .Result_Edit:
		return {}, App_Failure{stage = .Prompt}
	}
	unreachable()
}

@(private)
dispatch_prompt :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	mode := commands.prompt_workflow.mode
	generation := commands.prompt_workflow.projection_generation
	if prompt_mode_projects_input(mode) &&
	   commands.prompt_workflow.next_projection_generation == ui.Model_Generation(max(u64)) {
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	result, failure := dispatch_prompt_mode(
		commands,
		buffer,
		view_registry,
		view,
		input,
		constraints,
	)
	if failure.stage != .None do return result, failure
	if mode == .Incremental_Search && commands.prompt_workflow.mode == .None &&
	   interaction.profile_activation_modal_visual_kind(commands.profile_activation) != .None {
		visual_result, visual_failure := command_context_modal_visual_reconcile_point(
			commands, buffer, view_registry, view,
		)
		if visual_failure.stage != .None do return {}, visual_failure
		result.changed = result.changed || visual_result.changed
	}
	if result.changed && commands.prompt_workflow.mode == mode &&
	   commands.prompt_workflow.projection_generation == generation &&
	   prompt_mode_projects_input(mode) &&
	   !prompt_workflow_advance_projection(&commands.prompt_workflow) {
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	return result, {}
}


@(private)
command_context_activate_prompt_map :: proc(
	commands: ^Command_Context,
	mode: Prompt_Mode,
) -> App_Failure {
	if commands.context_maps == nil || mode == .None {
		return App_Failure{stage = .Command_Resolution}
	}
	if interaction.context_map_handle_is_valid(commands.prompt_workflow.map_handle) {
		_, ended, end_failure := interaction.context_map_end(
			commands.context_maps,
			commands.prompt_workflow.map_handle,
			.Invalidated,
			&commands.context_pending,
			&commands.pending,
		)
		if !ended {
			return App_Failure{stage = .Command_Resolution, interaction = end_failure}
		}
		commands.prompt_workflow.map_handle = {}
	}
	bindings: [17]interaction.Binding_Definition
	binding_count := 0
	policy := interaction.Unmatched_Input_Policy.Reject
	fallback := ""
	switch mode {
	case .Save_Path, .Write_File_Path, .Insert_File_Path, .Navigation_Target,
	     .Find_File, .Find_File_Other_Pane, .Darek_Show_Directory,
	     .Switch_To_Buffer, .Kill_Buffer,
	     .Project_Create_Directory, .Project_Promote_Name, .Terminal_Rename,
	     .Project_Search,
	     .Named_Location_Name, .Named_Slot_Input, .Package_Catalog_Input, .Kill_Save_Path,
	     .Exit_Save_Path, .Marked_Save_Path, .Query_Replacement_Pattern,
	     .Query_Replacement_Replacement, .Keymap_Command, .Keymap_Map,
	     .Keyboard_Macro_Name, .Keyboard_Macro_Call,
	     .Shell_Command, .Async_Shell_Command, .Compile_Command, .Result_Edit:
		command_context_add_prompt_binding(
			bindings[:],
			&binding_count,
			command_context_prompt_special(.Backspace),
			"prompt-delete-previous",
		)
		command_context_add_prompt_binding(
			bindings[:],
			&binding_count,
			command_context_prompt_special(.Enter),
			"prompt-accept",
		)
		policy = .Text_Input
		fallback = "prompt-insert-text"
	case .Named_Slot_Confirmation, .Package_Catalog_Confirmation,
	     .Last_Pane_Exit_Choice, .Terminal_Exit_Choice,
	     .Terminal_Kill_Choice:
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('y', {}), "prompt-choice-1")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('Y', {}), "prompt-choice-1")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('n', {}), "prompt-choice-2")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('N', {}), "prompt-choice-2")
	case .Incremental_Search:
		command_context_add_prompt_binding(
			bindings[:],
			&binding_count,
			command_context_prompt_special(.Backspace),
			"prompt-delete-previous",
		)
		command_context_add_prompt_binding(
			bindings[:],
			&binding_count,
			command_context_prompt_special(.Enter),
			"prompt-accept",
		)
		modifiers: interaction.Modifiers = {.Control}
		if commands.search.kind == .Regular_Expression {
			modifiers = {.Control, .Meta}
		}
		command_context_add_prompt_binding(
			bindings[:],
			&binding_count,
			command_context_prompt_scalar('s', modifiers),
			"isearch-forward",
		)
		command_context_add_prompt_binding(
			bindings[:],
			&binding_count,
			command_context_prompt_scalar('r', modifiers),
			"isearch-backward",
		)
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('n', {.Meta}), "search-history-newer")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('p', {.Meta}), "search-history-older")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Tab), "search-history-complete")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('w', {.Control}), "search-extend-textual")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('y', {.Control, .Meta}), "search-extend-structural")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('y', {.Control}), "search-extend-transferred")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_pair('s', {.Meta}, 'c', {}), "search-toggle-case")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_pair('s', {.Meta}, 'r', {}), "search-toggle-pattern")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_pair('s', {.Meta}, 'w', {}), "search-toggle-word")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_pair('s', {.Meta}, '_', {}), "search-toggle-symbol")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_pair('s', {.Meta}, ' ', {}), "search-toggle-whitespace")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_pair('s', {.Meta}, 'o', {}), "search-materialize-results")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_pair('s', {.Meta}, '.', {}), "search-symbol-at-point")
		policy = .Text_Input
		fallback = "prompt-insert-text"
	case .Query_Replacement_Response:
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Enter), "query-quit")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Backspace), "prompt-choice-2")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Delete), "prompt-choice-2")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('y', {}), "prompt-choice-1")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar(' ', {}), "prompt-choice-1")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('n', {}), "prompt-choice-2")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('!', {}), "prompt-choice-3")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('.', {}), "query-replace-and-exit")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('q', {}), "query-quit")
	case .Exit_Choice, .Kill_Unassociated_Choice, .Marked_Kill_Choice, .Project_Close_Choice:
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('s', {}), "prompt-choice-1")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('S', {}), "prompt-choice-1")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('d', {}), "prompt-choice-2")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('D', {}), "prompt-choice-2")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('c', {}), "prompt-choice-3")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('C', {}), "prompt-choice-3")
	case .Dir_Abandonment_Choice:
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('y', {}), "prompt-choice-1")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('Y', {}), "prompt-choice-1")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('n', {}), "prompt-choice-2")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('N', {}), "prompt-choice-2")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('c', {}), "prompt-choice-3")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('C', {}), "prompt-choice-3")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('d', {}), "prompt-choice-4")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('D', {}), "prompt-choice-4")
	case .Kill_File_Discard_Choice:
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('y', {}), "prompt-choice-1")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('Y', {}), "prompt-choice-1")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('n', {}), "prompt-choice-2")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('N', {}), "prompt-choice-2")
	case .None, .Find_Alternate_File, .Keymap_Sequence:
		return App_Failure{stage = .Command_Resolution}
	}
	result, activated, activation_failure := interaction.context_map_activate(
		commands.context_maps,
		interaction.Context_Map_Definition {
			identity = interaction.Map_Identity {
				id = interaction.Map_ID(1_000 + u64(mode)),
				revision = 1,
			},
			name = "active-prompt",
			owner_id = interaction.Owner_ID(prompt_mode_owner_id(mode)),
			precedence = .Transient_Interaction,
			priority = 0,
			bindings = bindings[:binding_count],
			text_fallback_name = fallback,
			unmatched_input_policy = policy,
		},
		&commands.context_pending,
		&commands.pending,
	)
	if !activated {
		return App_Failure{stage = .Command_Resolution, interaction = activation_failure}
	}
	commands.prompt_workflow.map_handle = result.handle
	command_context_suspend_modal_pending(commands, false)
	return {}
}

@(private)
command_context_resolve_prompt_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (metadata: interaction.Command_Metadata, resolution: interaction.Resolution, ok: bool, failure: App_Failure) {
	resolution_failure: interaction.Failure_Context
	resolution, resolution_failure = interaction.resolve_contextual_input(
		commands.context_maps,
		commands.keymap,
		commands.registry_generation,
		&commands.context_pending,
		&commands.pending,
		input,
	)
	if resolution_failure.code == .Context_Input_Rejected {
		return {}, resolution, true, {}
	}
	if resolution_failure.code != .None {
		return {}, resolution, false, App_Failure {
			stage = .Command_Resolution,
			interaction = resolution_failure,
		}
	}
	if resolution.kind != .Command {
		return {}, resolution, true, {}
	}
	found: bool
	metadata_failure: interaction.Failure_Context
	metadata, found, metadata_failure = interaction.command_metadata(commands.registry, resolution.command)
	if !found {
		return {}, resolution, false, App_Failure {
			stage = .Command_Dispatch,
			interaction = metadata_failure,
		}
	}
	return metadata, resolution, true, {}
}

@(private)
command_context_deactivate_prompt_map :: proc(
	commands: ^Command_Context,
	end: interaction.Context_Map_End,
) {
	if !interaction.context_map_handle_is_valid(commands.prompt_workflow.map_handle) {
		return
	}
	_, ended, failure := interaction.context_map_end(
		commands.context_maps,
		commands.prompt_workflow.map_handle,
		end,
		&commands.context_pending,
		&commands.pending,
	)
	assert(ended && failure.code == .None)
	commands.prompt_workflow.map_handle = {}
}

@(private)
command_context_add_prompt_binding :: proc(
	bindings: []interaction.Binding_Definition,
	count: ^int,
	sequence: interaction.Key_Sequence,
	command_name: string,
) {
	assert(count^ < len(bindings))
	bindings[count^] = interaction.Binding_Definition {
		strokes = sequence.strokes,
		stroke_count = sequence.stroke_count,
		command_name = command_name,
	}
	count^ += 1
}

@(private)
command_context_prompt_scalar :: proc(
	value: rune,
	modifiers: interaction.Modifiers,
) -> interaction.Key_Sequence {
	sequence: interaction.Key_Sequence
	sequence.stroke_count = 1
	sequence.strokes[0] = interaction.Key_Stroke {
		kind = .Unicode_Scalar,
		scalar = value,
		modifiers = modifiers,
	}
	return sequence
}

@(private)
command_context_prompt_special :: proc(
	kind: interaction.Logical_Key_Kind,
) -> interaction.Key_Sequence {
	sequence: interaction.Key_Sequence
	sequence.stroke_count = 1
	sequence.strokes[0] = interaction.Key_Stroke{kind = kind}
	return sequence
}

@(private)
command_context_prompt_pair :: proc(
	first: rune,
	first_modifiers: interaction.Modifiers,
	second: rune,
	second_modifiers: interaction.Modifiers,
) -> interaction.Key_Sequence {
	sequence: interaction.Key_Sequence
	sequence.stroke_count = 2
	sequence.strokes[0] = interaction.Key_Stroke {
		kind = .Unicode_Scalar,
		scalar = first,
		modifiers = first_modifiers,
	}
	sequence.strokes[1] = interaction.Key_Stroke {
		kind = .Unicode_Scalar,
		scalar = second,
		modifiers = second_modifiers,
	}
	return sequence
}

@(private)
command_context_end_prompt :: proc(commands: ^Command_Context) {
	if commands.search.history_navigation_active {
		_, _ = editor_session.session_search_history_end(
			commands.session_owner,
			commands.session_handle,
		)
	}
	command_context_deactivate_prompt_map(commands, .Completed)
	command_context_release_prompt_focus(commands)
	if commands.prompt_workflow.prompt.state != nil {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
	}
	commands.prompt_workflow.mode = .None
	commands.prompt_workflow.projection_generation = {}
	commands.prompt_workflow.rejected = false
	search_workflow_reset(&commands.search)
	document_workflow_reset_transient(&commands.document_workflow)
	interaction_workflow_reset_inspection(&commands.interaction_workflow)
	project_workflow_reset_transient(&commands.project_workflow)
}
