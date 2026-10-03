// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../document"
import "../editor_session"
import "../filesystem"
import "../interaction"
import "core:path/filepath"
import "core:fmt"
import "core:strings"

@(private)
Filesystem_Path_Navigation_State :: struct {
	batch:          filesystem.Directory_Batch,
	mode:           Prompt_Mode,
	command_handle: interaction.Command_Handle,
	prefix:         [document.MAX_PATH_BYTES]u8,
	prefix_length:  int,
	include_hidden: bool,
	maksym:          bool,
	darek:           bool,
	maksym_jump:     bool,
	maksym_placement: Maksym_Open_Placement,
}

@(private)
filesystem_path_navigation_begin :: proc(
	commands: ^Command_Context,
	mode: Prompt_Mode,
	command_handle: interaction.Command_Handle,
	maksym_placement := Maksym_Open_Placement.Current,
	maksym_mode := false,
	initial_directory := "",
	maksym_jump := false,
	darek_mode := false,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || (mode != .Find_File && mode != .Find_Alternate_File &&
	   mode != .Find_File_Other_Pane &&
	   mode != .Project_Create_Directory && mode != .Darek_Show_Directory) ||
	   len(commands.home_directory) == 0 {
		return {}, App_Failure{stage = .Component_Access}
	}
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
	)
	if !visible_ok || visible.kind == .None || visible == candidate_ui_visible_target() {
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	directory := commands.home_directory
	if len(initial_directory) > 0 do directory = initial_directory
	batch, observed, observe_failure := filesystem.directory_observe(
		directory,
		commands.candidate_ui.next_source_generation,
		filesystem.Allocator_Set {
			persistent = commands.persistent_allocator,
			temporary = commands.temporary_allocator,
		},
	)
	if !observed {
		command_context_set_diagnostic(commands, "Home directory is unavailable")
		_ = observe_failure
		return Interaction_Result{changed = true}, {}
	}
	if !filesystem_path_navigation_publish(commands, &batch, "", false) {
		_, _ = filesystem.directory_batch_close(&batch)
		command_context_set_diagnostic(commands, "Filesystem candidates are unavailable")
		return Interaction_Result{changed = true}, {}
	}
	filesystem_path_navigation_reset(&commands.filesystem_path_navigation)
	commands.filesystem_path_navigation.batch = batch
	commands.filesystem_path_navigation.mode = mode
	commands.filesystem_path_navigation.command_handle = command_handle
	commands.filesystem_path_navigation.maksym = maksym_mode
	commands.filesystem_path_navigation.darek = darek_mode
	commands.filesystem_path_navigation.maksym_jump = maksym_jump
	commands.filesystem_path_navigation.maksym_placement = maksym_placement
	commands.candidate_ui.return_target = visible
	commands.document_workflow.buffer_command = command_handle
	if mode == .Project_Create_Directory {
		commands.project_workflow.command_handle = command_handle
	}
	commands.candidate_ui.next_source_generation += 1
	commands.pending = {}
	target := candidate_ui_visible_target()
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner,
		commands.session_handle,
		target.ui,
	)
	if !presented {
		filesystem_path_navigation_close(commands)
		return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_filesystem_path_navigation_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	state := &commands.filesystem_path_navigation
	if state.mode == .None || state.batch.state == nil || commands.candidate_ui.session.state == nil {
		return {}, App_Failure{stage = .Component_Access}
	}
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed || view.source_kind != .Filesystem_Entries ||
	   view.source_generation != state.batch.generation {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	if map_failure := command_context_sync_candidate_map(commands, .Filesystem_Entries);
	   map_failure.stage != .None {
		return {}, map_failure
	}
	metadata, resolution, resolved, resolve_failure := command_context_resolve_context_input(commands, input)
	if !resolved do return {}, resolve_failure
	if resolution.kind != .Command do return {}, {}
	request := interaction.Candidate_Request {
		session_id = view.session_id,
		session_generation = view.session_generation,
	}
	route, route_ok := command.contextual_route_decode(metadata.route)
	if route_ok && (route == .Component_Previous_Row || route == .Component_Next_Row) {
		if len(view.rows) == 0 do return {}, {}
		delta := i32(1)
		if route == .Component_Previous_Row do delta = -1
		_, moved, move_failure := interaction.candidate_session_move(
			&commands.candidate_ui.session,
			request,
			delta,
		)
		if !moved {
			command_context_candidate_failure_diagnostic(commands, "Path candidate movement", move_failure)
		}
		return Interaction_Result{changed = true}, {}
	}
	if route == .Component_Query_Text {
		return filesystem_path_navigation_append(commands, view, resolution.text)
	}
	if route == .Component_Query_Delete_Previous {
		return filesystem_path_navigation_delete_previous(commands, view)
	}
	if route == .Component_Complete_Current {
		return filesystem_path_navigation_complete(commands, view)
	}
	if route == .Component_Activate_Current {
		return filesystem_path_navigation_activate(commands, view, constraints)
	}
	if route == .Component_Close || command_metadata_is_native(metadata, .Keyboard_Quit) ||
	   command_metadata_is_contextual(metadata, .Cancel) {
		return filesystem_path_navigation_leave(commands)
	}
	return {}, {}
}

@(private)
filesystem_path_navigation_append :: proc(
	commands: ^Command_Context,
	view: interaction.Candidate_View,
	text: string,
) -> (Interaction_Result, App_Failure) {
	state := &commands.filesystem_path_navigation
	if len(text) == 0 do return {}, {}
	if state.prefix_length == 0 && len(view.query) == 0 && (text == "/" || text == "~") {
		copy(state.prefix[:], "~/")
		state.prefix_length = 2
		return Interaction_Result{changed = true}, {}
	}
	if state.prefix_length > 0 && len(view.query) == 0 && text == "/" {
		return {}, {}
	}
	if len(view.query) + len(text) > len(state.prefix) {
		command_context_set_diagnostic(commands, "Path limit reached")
		return Interaction_Result{changed = true}, {}
	}
	combined: [document.MAX_PATH_BYTES]u8
	length := copy(combined[:], transmute([]u8)view.query)
	length += copy(combined[length:], transmute([]u8)text)
	value := string(combined[:length])
	separator := strings.last_index_byte(value, '/')
	if separator >= 0 {
		if state.prefix_length > 0 && !strings.has_prefix(value, "/") &&
		   !strings.has_prefix(value, "~/") {
			return filesystem_path_navigation_resolve_relative_value(commands, value, separator)
		}
		return filesystem_path_navigation_resolve_value(commands, value, separator)
	}
	return filesystem_path_navigation_set_query(commands, value)
}

@(private)
filesystem_path_navigation_resolve_relative_value :: proc(
	commands: ^Command_Context,
	value: string,
	separator: int,
) -> (Interaction_Result, App_Failure) {
	state := &commands.filesystem_path_navigation
	if separator <= 0 || separator >= len(value) || state.prefix_length <= 0 {
		return {}, App_Failure{stage = .Component_Access}
	}
	segment := value[:separator]
	query := value[separator + 1:]
	current := filesystem.normalized_path_text(&state.batch.directory)
	target: [document.MAX_PATH_BYTES]u8
	target_length := copy(target[:], transmute([]u8)current)
	if target_length == 0 || target[target_length - 1] != '/' {
		if target_length >= len(target) {
			command_context_set_diagnostic(commands, "Path limit reached")
			return Interaction_Result{changed = true}, {}
		}
		target[target_length] = '/'
		target_length += 1
	}
	if target_length + len(segment) > len(target) ||
	   state.prefix_length + separator + 1 > len(state.prefix) {
		command_context_set_diagnostic(commands, "Path limit reached")
		return Interaction_Result{changed = true}, {}
	}
	target_length += copy(target[target_length:], transmute([]u8)segment)
	display_prefix: [document.MAX_PATH_BYTES]u8
	display_length := copy(display_prefix[:], state.prefix[:state.prefix_length])
	display_length += copy(display_prefix[display_length:], transmute([]u8)value[:separator + 1])
	return filesystem_path_navigation_transition(
		commands,
		string(target[:target_length]),
		string(display_prefix[:display_length]),
		query,
	)
}

@(private)
filesystem_path_navigation_resolve_value :: proc(
	commands: ^Command_Context,
	value: string,
	separator: int,
) -> (Interaction_Result, App_Failure) {
	display_prefix := value[:separator + 1]
	query := value[separator + 1:]
	actual: [document.MAX_PATH_BYTES]u8
	actual_length := 0
	absolute_fallback := false
	if strings.has_prefix(display_prefix, "~/") && separator > 1 {
		segment := display_prefix[2:separator]
		home_entry := false
		for descriptor in commands.filesystem_path_navigation.batch.descriptors {
			if descriptor.kind == .Directory && descriptor.name == segment {
				home_entry = true
				break
			}
		}
		absolute_fallback = !home_entry
	}
	if absolute_fallback {
		actual[0] = '/'
		actual_length = 1 + copy(actual[1:], transmute([]u8)display_prefix[2:])
		display_storage: [document.MAX_PATH_BYTES]u8
		display_storage[0] = '/'
		display_length := 1 + copy(display_storage[1:], transmute([]u8)display_prefix[2:])
		display_prefix = string(display_storage[:display_length])
	} else if strings.has_prefix(display_prefix, "~/") {
		actual_length = copy(actual[:], transmute([]u8)commands.home_directory)
		suffix := display_prefix[2:]
		if len(suffix) > 0 {
			if actual_length == 0 || actual[actual_length - 1] != '/' {
				actual[actual_length] = '/'
				actual_length += 1
			}
			actual_length += copy(actual[actual_length:], transmute([]u8)suffix)
		}
	} else if strings.has_prefix(display_prefix, "/") {
		actual_length = copy(actual[:], transmute([]u8)display_prefix)
	} else {
		actual_length = copy(actual[:], transmute([]u8)commands.home_directory)
		if actual_length == 0 || actual[actual_length - 1] != '/' {
			actual[actual_length] = '/'
			actual_length += 1
		}
		actual_length += copy(actual[actual_length:], transmute([]u8)display_prefix)
		display_storage: [document.MAX_PATH_BYTES]u8
		display_length := copy(display_storage[:], "~/")
		display_length += copy(display_storage[display_length:], transmute([]u8)display_prefix)
		display_prefix = string(display_storage[:display_length])
	}
	for actual_length > 1 && actual[actual_length - 1] == '/' do actual_length -= 1
	if actual_length == 0 {
		actual[actual_length] = '/'
		actual_length = 1
	}
	return filesystem_path_navigation_transition(
		commands,
		string(actual[:actual_length]),
		display_prefix,
		query,
	)
}

@(private)
filesystem_path_navigation_set_query :: proc(
	commands: ^Command_Context,
	query: string,
) -> (Interaction_Result, App_Failure) {
	state := &commands.filesystem_path_navigation
	include_hidden := len(query) > 0 && query[0] == '.'
	if include_hidden != state.include_hidden {
		return filesystem_path_navigation_transition(
			commands,
			filesystem.normalized_path_text(&state.batch.directory),
			string(state.prefix[:state.prefix_length]),
			query,
			include_hidden,
		)
	}
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed do return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	_, changed, query_failure := interaction.candidate_session_set_query(
		&commands.candidate_ui.session,
		interaction.Candidate_Request {
			session_id = view.session_id,
			session_generation = view.session_generation,
		},
		query,
	)
	if !changed {
		command_context_candidate_failure_diagnostic(commands, "Path candidate query", query_failure)
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
filesystem_path_navigation_complete :: proc(
	commands: ^Command_Context,
	view: interaction.Candidate_View,
) -> (Interaction_Result, App_Failure) {
	if !view.has_selection || len(view.rows) == 0 {
		return {}, {}
	}
	row := view.rows[view.selected_row]
	descriptor, found := interaction.filesystem_candidate_action_entry(
		row.action,
		&commands.filesystem_path_navigation.batch,
	)
	if !found {
		command_context_set_diagnostic(commands, "Path candidate changed; reopen path navigation")
		return Interaction_Result{changed = true}, {}
	}
	if commands.filesystem_path_navigation.maksym_jump {
		return filesystem_path_navigation_set_query(commands, descriptor.name)
	}
	if descriptor.kind == .Regular_File {
		return filesystem_path_navigation_set_query(commands, descriptor.name)
	}
	prefix: [document.MAX_PATH_BYTES]u8
	length := commands.filesystem_path_navigation.prefix_length
	if length == 0 {
		length = copy(prefix[:], "~/")
	} else {
		copy(prefix[:], commands.filesystem_path_navigation.prefix[:length])
	}
	if length + len(descriptor.name) + 1 > len(prefix) {
		command_context_set_diagnostic(commands, "Path limit reached")
		return Interaction_Result{changed = true}, {}
	}
	length += copy(prefix[length:], transmute([]u8)descriptor.name)
	prefix[length] = '/'
	length += 1
	return filesystem_path_navigation_transition(
		commands,
		descriptor.path,
		string(prefix[:length]),
		"",
	)
}

@(private)
filesystem_path_navigation_delete_previous :: proc(
	commands: ^Command_Context,
	view: interaction.Candidate_View,
) -> (Interaction_Result, App_Failure) {
	state := &commands.filesystem_path_navigation
	if len(view.query) > 0 {
		end := len(view.query) - 1
		bytes := transmute([]u8)view.query
		for end > 0 && bytes[end] & 0xc0 == 0x80 do end -= 1
		return filesystem_path_navigation_set_query(commands, view.query[:end])
	}
	if state.prefix_length == 0 do return {}, {}
	if state.prefix_length == 2 && string(state.prefix[:2]) == "~/" {
		state.prefix_length = 0
		return Interaction_Result{changed = true}, {}
	}
	current := filesystem.normalized_path_text(&state.batch.directory)
	parent := filepath.dir(current)
	trimmed := string(state.prefix[:state.prefix_length - 1])
	separator := strings.last_index_byte(trimmed, '/')
	parent_prefix := ""
	if separator >= 0 do parent_prefix = trimmed[:separator + 1]
	return filesystem_path_navigation_transition(commands, parent, parent_prefix, "")
}

@(private)
filesystem_path_navigation_transition :: proc(
	commands: ^Command_Context,
	path, prefix, query: string,
	include_hidden := false,
) -> (Interaction_Result, App_Failure) {
	state := &commands.filesystem_path_navigation
	if len(prefix) > len(state.prefix) || len(query) > int(interaction.MAX_CANDIDATE_QUERY_BYTES) {
		command_context_set_diagnostic(commands, "Path limit reached")
		return Interaction_Result{changed = true}, {}
	}
	batch, observed, observe_failure := filesystem.directory_observe(
		path,
		commands.candidate_ui.next_source_generation,
		filesystem.Allocator_Set {
			persistent = commands.persistent_allocator,
			temporary = commands.temporary_allocator,
		},
		include_hidden,
	)
	if !observed {
		diagnostic: [document.MAX_DIAGNOSTIC_BYTES]u8
		command_context_set_diagnostic(
			commands,
			fmt.bprintf(diagnostic[:], "Directory is unavailable: %s", path),
		)
		_ = observe_failure
		return Interaction_Result{changed = true}, {}
	}
	if !filesystem_path_navigation_publish(commands, &batch, query, true) {
		_, _ = filesystem.directory_batch_close(&batch)
		command_context_set_diagnostic(commands, "Filesystem candidates are unavailable")
		return Interaction_Result{changed = true}, {}
	}
	if state.batch.state != nil do _, _ = filesystem.directory_batch_close(&state.batch)
	state.batch = batch
	state.prefix_length = copy(state.prefix[:], transmute([]u8)prefix)
	state.include_hidden = include_hidden
	commands.candidate_ui.next_source_generation += 1
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}

@(private)
filesystem_path_navigation_publish :: proc(
	commands: ^Command_Context,
	batch: ^filesystem.Directory_Batch,
	query: string,
	replace: bool,
) -> bool {
	source, source_ok, _ := interaction.filesystem_candidate_source_build(
		batch,
		commands.temporary_allocator,
	)
	if !source_ok do return false
	defer interaction.filesystem_candidate_source_close(&source)
	session_id := commands.candidate_ui.next_session_id
	if session_id == 0 || session_id == max(u64) do return false
	session: interaction.Candidate_Session
	_, initialized, _ := interaction.candidate_session_init(
		&session,
		interaction.Candidate_Config {
			session_id = interaction.Candidate_Session_ID(session_id),
			limits = interaction.DEFAULT_CANDIDATE_LIMITS,
			persistent_allocator = commands.persistent_allocator,
			temporary_allocator = commands.temporary_allocator,
		},
		source.definition,
		query,
	)
	if !initialized do return false
	if replace && commands.candidate_ui.session.state != nil {
		_, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	}
	commands.candidate_ui.session = session
	commands.candidate_ui.next_session_id = session_id + 1
	return true
}

@(private)
filesystem_path_navigation_activate :: proc(
	commands: ^Command_Context,
	view: interaction.Candidate_View,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if !view.has_selection || len(view.rows) == 0 {
		if commands.filesystem_path_navigation.mode == .Project_Create_Directory ||
		   len(view.query) == 0 {
			return {}, {}
		}
		path: [document.MAX_PATH_BYTES]u8
		directory := filesystem.normalized_path_text(
			&commands.filesystem_path_navigation.batch.directory,
		)
		if len(directory) + len(view.query) + 1 > len(path) {
			command_context_set_diagnostic(commands, "Path limit reached")
			return Interaction_Result{changed = true}, {}
		}
		length := copy(path[:], transmute([]u8)directory)
		if length == 0 || path[length - 1] != '/' {
			path[length] = '/'
			length += 1
		}
		length += copy(path[length:], transmute([]u8)view.query)
		return filesystem_path_navigation_open_file(commands, string(path[:length]))
	}
	descriptor, found := interaction.filesystem_candidate_action_entry(
		view.rows[view.selected_row].action,
		&commands.filesystem_path_navigation.batch,
	)
	if !found {
		command_context_set_diagnostic(commands, "Path candidate changed; reopen path navigation")
		return Interaction_Result{changed = true}, {}
	}
	mode := commands.filesystem_path_navigation.mode
	if mode != .Project_Create_Directory && !commands.filesystem_path_navigation.maksym &&
	   !commands.filesystem_path_navigation.darek &&
	   descriptor.kind == .Directory {
		return filesystem_path_navigation_complete(commands, view)
	}
	if commands.filesystem_path_navigation.maksym {
		if descriptor.kind != .Directory {
			command_context_set_diagnostic(commands, "Select a directory")
			return Interaction_Result{changed = true}, {}
		}
		path: [document.MAX_PATH_BYTES]u8
		length := copy(path[:], transmute([]u8)descriptor.path)
		return_target := commands.candidate_ui.return_target
		command_handle := commands.filesystem_path_navigation.command_handle
		placement := commands.filesystem_path_navigation.maksym_placement
		command_context_deactivate_context_map(commands, .Completed)
		filesystem_path_navigation_close(commands)
		if restore_failure := filesystem_path_navigation_restore_target(commands, return_target);
		   restore_failure.stage != .None do return {}, restore_failure
		return command_context_open_maksym_directory(
			commands,
			string(path[:length]),
			placement,
			constraints,
			command_handle,
		)
	}
	if commands.filesystem_path_navigation.darek {
		if descriptor.kind != .Directory {
			command_context_set_diagnostic(commands, "Select a directory")
			return Interaction_Result{changed = true}, {}
		}
		path: [document.MAX_PATH_BYTES]u8
		length := copy(path[:], transmute([]u8)descriptor.path)
		return_target := commands.candidate_ui.return_target
		command_handle := commands.filesystem_path_navigation.command_handle
		command_context_deactivate_context_map(commands, .Completed)
		filesystem_path_navigation_close(commands)
		if restore_failure := filesystem_path_navigation_restore_target(commands, return_target);
		   restore_failure.stage != .None do return {}, restore_failure
		return command_context_open_darek_directory(
			commands,
			string(path[:length]),
			constraints,
			command_handle,
		)
	}
	if mode == .Project_Create_Directory {
		if descriptor.kind != .Directory {
			command_context_set_diagnostic(commands, "Select a directory")
			return Interaction_Result{changed = true}, {}
		}
		path: [document.MAX_PATH_BYTES]u8
		length := copy(path[:], transmute([]u8)descriptor.path)
		return_target := commands.candidate_ui.return_target
		command_context_deactivate_context_map(commands, .Completed)
		filesystem_path_navigation_close(commands)
		if restore_failure := filesystem_path_navigation_restore_target(commands, return_target);
		   restore_failure.stage != .None {
			return {}, restore_failure
		}
		return command_context_open_project_directory(commands, string(path[:length]), constraints)
	}
	return filesystem_path_navigation_open_file(commands, descriptor.path)
}

@(private)
filesystem_path_navigation_open_file :: proc(
	commands: ^Command_Context,
	selected_path: string,
) -> (Interaction_Result, App_Failure) {
	path: [document.MAX_PATH_BYTES]u8
	length := copy(path[:], transmute([]u8)selected_path)
	mode := commands.filesystem_path_navigation.mode
	other_pane := mode == .Find_File_Other_Pane
	alternate_file := mode == .Find_Alternate_File
	alternate_entry := commands.document_workflow.kill_entry
	command_handle := commands.filesystem_path_navigation.command_handle
	command_context_deactivate_context_map(commands, .Completed)
	filesystem_path_navigation_close(commands)
	result, opened, open_failure := command.buffer_session_find_file(
		command.Buffer_Session_Context {
			session = commands.session_owner,
			handle = commands.session_handle,
			command = command_handle,
			configuration = commands.entry_configuration,
		},
		string(path[:length]),
	)
	if !opened {
		command_context_buffer_session_diagnostic(commands, open_failure)
		return Interaction_Result{changed = true}, {}
	}
	if other_pane {
		displayed, display_failure := command_context_layout_display_entry(commands, result.entry, true)
		if !displayed {
			command_context_layout_display_diagnostic(commands, display_failure)
			return Interaction_Result{changed = true}, {}
		}
	}
	if alternate_file {
		if editor_session.entry_handle_is_valid(alternate_entry) && alternate_entry != result.entry {
			closure, closed, close_failure := editor_session.session_close_buffer(
				commands.session_owner,
				editor_session.Close_Buffer_Request {
					entry = alternate_entry,
					authority = .Preserve_Modified,
				},
			)
			if !closed || closure.outcome != .Ready {
				_ = close_failure
				command_context_set_diagnostic(commands, "Opened file; prior buffer changed and remains open")
				return Interaction_Result{changed = true}, {}
			}
		}
		command_context_set_diagnostic(commands, "Replaced current buffer")
		return Interaction_Result{changed = true}, {}
	}
	command_context_set_diagnostic(commands, "Opened file" if result.completion == .Opened else "Selected open file")
	return Interaction_Result{changed = true}, {}
}

@(private)
filesystem_path_navigation_restore_target :: proc(
	commands: ^Command_Context,
	target: editor_session.Visible_Target,
) -> App_Failure {
	if target.kind == .Primary_View {
		_, activated, activation_failure := editor_session.session_activate(
			commands.session_owner,
			target.entry,
		)
		if !activated do return App_Failure{stage = .Session_Access, editor_session = activation_failure}
		return {}
	}
	if target.kind == .UI_Root {
		_, _, presented, present_failure := editor_session.session_present_ui(
			commands.session_owner,
			commands.session_handle,
			target.ui,
		)
		if !presented do return App_Failure{stage = .Session_Access, editor_session = present_failure}
		return {}
	}
	return App_Failure{stage = .Session_Access}
}

@(private)
filesystem_path_navigation_leave :: proc(commands: ^Command_Context) -> (Interaction_Result, App_Failure) {
	return_target := commands.candidate_ui.return_target
	command_context_deactivate_context_map(commands, .Cancelled)
	filesystem_path_navigation_close(commands)
	commands.diagnostic_length = 0
	if restore_failure := filesystem_path_navigation_restore_target(commands, return_target);
	   restore_failure.stage != .None do return {}, restore_failure
	return Interaction_Result{changed = true}, {}
}

@(private)
filesystem_path_navigation_close :: proc(commands: ^Command_Context) {
	if commands == nil do return
	if commands.candidate_ui.session.state != nil {
		_, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	}
	commands.candidate_ui.return_target = {}
	filesystem_path_navigation_reset(&commands.filesystem_path_navigation)
	commands.document_workflow.buffer_command = {}
	commands.document_workflow.kill_entry = {}
}

@(private)
filesystem_path_navigation_reset :: proc(state: ^Filesystem_Path_Navigation_State) {
	if state == nil do return
	if state.batch.state != nil do _, _ = filesystem.directory_batch_close(&state.batch)
	state^ = {}
}

@(private)
filesystem_path_navigation_input_value :: proc(
	commands: ^Command_Context,
	query: string,
	storage: []u8,
) -> (string, bool) {
	state := &commands.filesystem_path_navigation
	if state.mode == .None || state.prefix_length + len(query) > len(storage) do return "", false
	length := copy(storage, state.prefix[:state.prefix_length])
	length += copy(storage[length:], transmute([]u8)query)
	return string(storage[:length]), true
}

@(private)
filesystem_path_navigation_prompt_label :: proc(
	commands: ^Command_Context,
	view: interaction.Candidate_View,
	storage: []u8,
) -> (string, bool) {
	if commands == nil || view.source_kind != .Filesystem_Entries || len(storage) < 64 {
		return "", false
	}
	selected := u32(0)
	if view.has_selection do selected = view.selected_row + 1
	label := "Find file"
	if commands.filesystem_path_navigation.maksym_jump {
		label = "Jump to Maksym entry"
	} else if commands.filesystem_path_navigation.mode == .Find_Alternate_File {
		label = "Find alternate file"
	} else if commands.filesystem_path_navigation.mode == .Find_File_Other_Pane {
		label = "Find file in other pane"
	} else if commands.filesystem_path_navigation.maksym {
		label = "Open directory in Maksym"
	} else if commands.filesystem_path_navigation.darek {
		label = "Show directory in Darek"
	} else if commands.filesystem_path_navigation.mode == .Project_Create_Directory {
		label = "Open directory"
	}
	text := fmt.bprintf(storage, "%s [local] %d/%d: ", label, selected, len(view.rows))
	return text, len(text) > 0
}
