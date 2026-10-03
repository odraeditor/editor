// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../document"
import "../editor_session"
import "../interaction"
import "../project"
import "../ui"
import "core:fmt"
import "core:path/filepath"
import "core:strings"

@(private)
Project_Open_Continuation :: enum u8 {
	None,
	Path,
	Candidate,
}

@(private)
Project_Selection_Purpose :: enum u8 {
	Open,
	Unregister,
	Workspace_Add,
	Workspace_Remove,
	Workspace_Hierarchy_Module_Add,
}

@(private)
Project_Workflow_State :: struct {
	command_handle:  interaction.Command_Handle,
	next_project_id: project.Project_ID,
	file_search:     command.Project_File_Search,
	file_candidates: project.File_Candidate_Batch,
	buffer_candidate_project: project.Project_Handle,
	directory_candidates: project.Descriptor_Batch,
	directory_open_candidates: command.Project_Directory_Candidate_Batch,
	selection_candidates: command.Project_Directory_Candidate_Batch,
	selection_purpose: Project_Selection_Purpose,
	list_mode:        Project_List_Mode,
	list_position:    ui.List_View_Position,
	list_return_target: editor_session.Visible_Target,
	list_project:     project.Project_Descriptor,
	list_current_membership: project.Membership_Handle,
	list_current_candidate_id: project.Project_ID,
	list_current_candidate_generation: project.Project_Generation,
	list_model_generation: u64,
	list_next_model_generation: u64,
	close_authorities: [editor_session.MAX_LIVE_BUFFERS]editor_session.Close_Buffer_Request,
	close_authority_count: u32,
	pending_close_entry: editor_session.Entry_Handle,
	open_continuation: Project_Open_Continuation,
	pending_open_path: [document.MAX_PATH_BYTES]u8,
	pending_open_path_length: int,
	pending_open_candidate: int,
	pending_selection_id: [project.MAX_DURABLE_ID_STORAGE_BYTES]u8,
	pending_selection_id_length: int,
	pending_promotion_path: [document.MAX_PATH_BYTES]u8,
	pending_promotion_path_length: int,
	pending_workspace_project_path: [document.MAX_PATH_BYTES]u8,
	pending_workspace_project_path_length: int,
	candidate_history: project.Candidate_History,
	candidate_history_project: project.Project_Handle,
	candidate_history_global: bool,
	candidate_history_persistence_ready: bool,
}

@(private)
project_workflow_clear_open_continuation :: proc(state: ^Project_Workflow_State) {
	if state != nil {
		state.open_continuation = .None
		state.pending_open_path_length = 0
		state.pending_open_candidate = 0
		state.pending_selection_id_length = 0
	}
}

@(private)
command_context_record_pending_project_selection :: proc(commands: ^Command_Context) {
	if commands == nil || commands.project_workflow.pending_selection_id_length == 0 {
		return
	}
	state := &commands.project_workflow
	_ = command_context_global_candidate_history_record(
		commands,
		.Project,
		string(state.pending_selection_id[:state.pending_selection_id_length]),
	)
	state.pending_selection_id_length = 0
}

@(private)
project_workflow_clear_close_attempt :: proc(state: ^Project_Workflow_State) {
	if state != nil {
		state.close_authority_count = 0
		state.pending_close_entry = {}
	}
}

@(private)
project_workflow_reset_transient :: proc(state: ^Project_Workflow_State) {
	if state != nil {
		if state.file_candidates.state != nil {
			project.file_candidate_batch_close(&state.file_candidates)
		}
		if state.file_search.enumerator.state != nil {
			command.project_find_file_close(&state.file_search)
		}
		if state.directory_candidates.state != nil {
			project.descriptor_batch_close(&state.directory_candidates)
		}
		if state.directory_open_candidates.state != nil {
			command.project_directory_candidate_batch_close(&state.directory_open_candidates)
		}
		if state.selection_candidates.state != nil {
			command.project_directory_candidate_batch_close(&state.selection_candidates)
		}
		project_list_workflow_reset(state)
		state.command_handle = {}
		state.buffer_candidate_project = {}
		project_workflow_clear_close_attempt(state)
		project_workflow_clear_open_continuation(state)
		state.pending_promotion_path_length = 0
	}
}

@(private)
command_context_begin_project_prompt :: proc(
	commands: ^Command_Context,
	mode: Prompt_Mode,
	command_handle: interaction.Command_Handle,
) -> (Interaction_Result, App_Failure) {
	if mode != .Project_Create_Directory && mode != .Project_Promote_Name {
		return {}, App_Failure{stage = .Prompt}
	}
	if mode == .Project_Create_Directory {
		return filesystem_path_navigation_begin(commands, mode, command_handle)
	}
	command_context_end_prompt(commands)
	initial_text := ""
	text_limit := document.MAX_PATH_BYTES
	if mode == .Project_Promote_Name {
		promotion_path := ""
		found := false
		if commands.document_workflow.dir_abandonment.outcome == .Decision_Required {
			promotion_path = editor_session.dir_abandonment_path_text(
				&commands.document_workflow.dir_abandonment,
			)
			found = len(promotion_path) > 0 && command_context_set_pending_promotion_path(
				commands,
				promotion_path,
			)
		} else {
			promotion_path, found = command_context_active_dir_path(commands)
		}
		if !found {
			command_context_set_channel_diagnostic(commands, .Project, "Project promotion requires an active ordinary Dir")
			return Interaction_Result{changed = true}, {}
		}
		initial_text = filepath.base(promotion_path)
		text_limit = project.MAX_NAME_BYTES
	}
	prompt_ok, prompt_failure := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		interaction.Prompt_Config {
			kind = .Text_Entry,
			text_bytes_limit = text_limit,
			allow_empty = false,
			allocator = commands.persistent_allocator,
		},
	)
	if !prompt_ok {
		return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	}
	if len(initial_text) > 0 {
		_, append_failure := interaction.prompt_text_append(
			&commands.prompt_workflow.prompt,
			initial_text,
		)
		if append_failure.code != .None {
			_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
			return {}, App_Failure{stage = .Prompt, prompt_failure = append_failure}
		}
	}
	if !prompt_workflow_begin_projection(&commands.prompt_workflow, mode) {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	commands.project_workflow.command_handle = command_handle
	if map_failure := command_context_activate_prompt_map(commands, mode); map_failure.stage != .None {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		commands.prompt_workflow.mode = .None
		project_workflow_reset_transient(&commands.project_workflow)
		return {}, map_failure
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_project_prompt :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24},
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
		command_context_deactivate_prompt_map(commands, .Cancelled)
		command_context_end_prompt(commands)
		if commands.document_workflow.dir_abandonment.outcome != .Invalid {
			document_workflow_reset_dir_abandonment(&commands.document_workflow)
		}
		return Interaction_Result{changed = true}, {}
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
	prompt_view, viewed, view_failure := interaction.prompt_view(&commands.prompt_workflow.prompt)
	if !viewed {
		return {}, App_Failure{stage = .Prompt, prompt_failure = view_failure}
	}
	mode := commands.prompt_workflow.mode
	command_handle := commands.project_workflow.command_handle
	path := prompt_view.text
	if mode != .Project_Promote_Name {
		path_storage: [document.MAX_PATH_BYTES]u8
		path_ok: bool
		path, path_ok = command_context_expand_home_path(commands, path, path_storage[:])
		if !path_ok {
			command_context_end_prompt(commands)
			command_context_set_channel_diagnostic(commands, .Project, "Home-relative path exceeds the path limit")
			return Interaction_Result{changed = true}, {}
		}
	}
	ctx := command.Project_Command_Context {
		session = commands.session_owner,
		handle = commands.session_handle,
		command = command_handle,
		persistent_allocator = commands.persistent_allocator,
		temporary_allocator = commands.temporary_allocator,
	}
	if mode == .Project_Promote_Name {
		promotion_path := string(
			commands.project_workflow.pending_promotion_path[
				:commands.project_workflow.pending_promotion_path_length
			],
		)
		promotion, promoted, promotion_failure := command.project_promote(
			ctx,
			commands.racket_runtime,
			commands.project_catalog_root,
			promotion_path,
			path,
		)
		abandonment_pending := commands.document_workflow.dir_abandonment.outcome != .Invalid
		command_context_end_prompt(commands)
		if !promoted {
			if abandonment_pending {
				document_workflow_reset_dir_abandonment(&commands.document_workflow)
			}
			command_context_project_failure_diagnostic(commands, promotion_failure)
			return Interaction_Result{changed = true}, {}
		}
		if abandonment_pending {
			_, admitted, admit_failure := editor_session.session_admit_dir_abandonment(
				commands.session_owner,
				&commands.document_workflow.dir_abandonment,
				.Convert,
			)
			if !admitted {
				document_workflow_reset_dir_abandonment(&commands.document_workflow)
				return {}, App_Failure{stage = .Session_Access, editor_session = admit_failure}
			}
			return command_context_continue_dir_abandonment(commands, constraints)
		}
		command_context_set_channel_diagnostic(
			commands,
			.Project,
			"Project reconciled" if promotion.reconciled else "Dir promoted to Project",
		)
		return Interaction_Result{changed = true}, {}
	}
	if mode == .Project_Create_Directory {
		requested_path: [document.MAX_PATH_BYTES]u8
		copy(requested_path[:], transmute([]u8)path)
		requested := string(requested_path[:len(path)])
		command_context_end_prompt(commands)
		return command_context_open_project_directory(commands, requested, constraints)
	}
	return {}, App_Failure{stage = .Prompt}
}

@(private)
command_context_active_dir_path :: proc(commands: ^Command_Context) -> (string, bool) {
	if commands == nil || commands.session_owner == nil {
		return "", false
	}
	state := &commands.project_workflow
	state.pending_promotion_path_length = 0
	roots, roots_ok, _ := editor_session.session_roots(commands.session_owner, commands.session_handle)
	if !roots_ok {
		return "", false
	}
	defer editor_session.root_batch_close(&roots)
	target := ""
	if commands.document_owner != nil {
		status, status_ok, _ := document.document_status(commands.document_owner)
		if status_ok && status.has_target {
			target = status.target_path
		}
	}
	selected := ""
	dir_count := 0
	sole_dir := ""
	for descriptor in roots.descriptors {
		if descriptor.kind != .Dir {
			continue
		}
		dir_count += 1
		sole_dir = descriptor.path
		inside := target == descriptor.path || descriptor.path == "/" && strings.has_prefix(target, "/") ||
		          len(target) > len(descriptor.path) && strings.has_prefix(target, descriptor.path) &&
		          target[len(descriptor.path)] == '/'
		if inside && len(descriptor.path) > len(selected) {
			selected = descriptor.path
		}
	}
	if len(selected) == 0 && dir_count == 1 {
		selected = sole_dir
	}
	if len(selected) == 0 || !command_context_set_pending_promotion_path(commands, selected) {
		return "", false
	}
	return string(state.pending_promotion_path[:state.pending_promotion_path_length]), true
}

@(private)
command_context_set_pending_promotion_path :: proc(commands: ^Command_Context, path: string) -> bool {
	if commands == nil || len(path) == 0 || len(path) > len(commands.project_workflow.pending_promotion_path) {
		return false
	}
	state := &commands.project_workflow
	copy(state.pending_promotion_path[:], transmute([]u8)path)
	state.pending_promotion_path_length = len(path)
	return true
}

@(private)
command_context_begin_dir_abandonment :: proc(
	commands: ^Command_Context,
	action: editor_session.Dir_Abandonment_Action,
	continuation: Dir_Abandonment_Continuation,
	open_path := "",
) -> (Interaction_Result, App_Failure) {
	state := &commands.document_workflow
	if state.dir_abandonment_continuation == .None {
		state.dir_abandonment_continuation = continuation
		if continuation == .Open_Path {
			if len(open_path) == 0 || len(open_path) > len(state.dir_abandonment_open_path) {
				document_workflow_reset_dir_abandonment(state)
				return {}, App_Failure{stage = .Command_Dispatch}
			}
			copy(state.dir_abandonment_open_path[:], transmute([]u8)open_path)
			state.dir_abandonment_open_path_length = len(open_path)
		}
	}
	roots, listed, list_failure := editor_session.session_roots(
		commands.session_owner,
		commands.session_handle,
	)
	if !listed {
		document_workflow_reset_dir_abandonment(state)
		return {}, App_Failure{stage = .Session_Access, editor_session = list_failure}
	}
	defer editor_session.root_batch_close(&roots)
	if continuation == .Open_Path {
		requested := string(state.dir_abandonment_open_path[:state.dir_abandonment_open_path_length])
		normalized: document.Normalized_Path
		normalized_ok, _ := document.path_normalize(
			requested,
			&normalized,
			commands.temporary_allocator,
		)
		if !normalized_ok {
			return command_context_continue_dir_abandonment(commands)
		}
		target := document.normalized_path_text(&normalized)
		for root in roots.descriptors {
			if root.path == target {
				return command_context_continue_dir_abandonment(commands)
			}
		}
	}
	for root, index in roots.descriptors {
		if index < int(state.dir_abandonment_next_root) || root.kind != .Dir {
			continue
		}
		state.dir_abandonment_next_root = u32(index + 1)
		suppression, inspected, suppression_failure := command.project_promotion_suppression(
			commands.racket_runtime,
			commands.project_catalog_root,
			root.path,
			.Inspect,
		)
		if !inspected {
			document_workflow_reset_dir_abandonment(state)
			command_context_project_failure_diagnostic(commands, suppression_failure)
			return Interaction_Result{changed = true}, {}
		}
		prepared, prepare_failure := editor_session.session_prepare_dir_abandonment(
			commands.session_owner,
			commands.session_handle,
			root.handle,
			action,
			suppression.suppressed,
			&state.dir_abandonment,
		)
		if !prepared {
			document_workflow_reset_dir_abandonment(state)
			return {}, App_Failure{stage = .Session_Access, editor_session = prepare_failure}
		}
		if state.dir_abandonment.outcome == .Ready {
			_, admitted, admit_failure := editor_session.session_admit_dir_abandonment(
				commands.session_owner,
				&state.dir_abandonment,
				.Continue,
			)
			if !admitted {
				document_workflow_reset_dir_abandonment(state)
				return {}, App_Failure{stage = .Session_Access, editor_session = admit_failure}
			}
			return command_context_begin_dir_abandonment(commands, action, continuation)
		}
		choices := prompt_dir_abandonment_choices()
		prompt_ok, prompt_failure := interaction.prompt_init(
			&commands.prompt_workflow.prompt,
			interaction.Prompt_Config {
				kind = .Fixed_Choice,
				choices = choices[:],
				allocator = commands.persistent_allocator,
			},
		)
		if !prompt_ok {
			document_workflow_reset_dir_abandonment(state)
			return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		}
		if !prompt_workflow_begin_projection(&commands.prompt_workflow, .Dir_Abandonment_Choice) {
			_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
			document_workflow_reset_dir_abandonment(state)
			return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
		}
		if map_failure := command_context_activate_prompt_map(commands, .Dir_Abandonment_Choice); map_failure.stage != .None {
			_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
			commands.prompt_workflow.mode = .None
			document_workflow_reset_dir_abandonment(state)
			return {}, map_failure
		}
		return Interaction_Result{changed = true}, {}
	}
	return command_context_continue_dir_abandonment(commands)
}

@(private)
command_context_continue_dir_abandonment :: proc(
	commands: ^Command_Context,
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24},
) -> (Interaction_Result, App_Failure) {
	state := &commands.document_workflow
	continuation := state.dir_abandonment_continuation
	path_storage := state.dir_abandonment_open_path
	path_length := state.dir_abandonment_open_path_length
	document_workflow_reset_dir_abandonment(state)
	switch continuation {
	case .Exit:
		command_context_clear_exit(commands)
		return Interaction_Result{exit = true}, {}
	case .Open_Path:
		path := string(path_storage[:path_length])
		return command_context_open_project_directory_unchecked(commands, path, constraints)
	case .None:
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	unreachable()
}

@(private)
dispatch_dir_abandonment_prompt :: proc(
	commands: ^Command_Context,
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
	choice := command_metadata_prompt_choice(metadata)
	if choice < 1 || choice > 4 {
		return {}, {}
	}
	prepared := &commands.document_workflow.dir_abandonment
	path := editor_session.dir_abandonment_path_text(prepared)
	action := prepared.action
	continuation := commands.document_workflow.dir_abandonment_continuation
	command_handle := commands.document_workflow.exit_command
	command_context_end_prompt(commands)
	if choice == 1 {
		commands.project_workflow.command_handle = command_handle
		return command_context_begin_project_prompt(commands, .Project_Promote_Name, command_handle)
	}
	decision := editor_session.Dir_Abandonment_Decision.Decline
	if choice == 3 {
		decision = .Cancel
	} else if choice == 4 {
		_, persisted, suppression_failure := command.project_promotion_suppression(
			commands.racket_runtime,
			commands.project_catalog_root,
			path,
			.Add,
		)
		if !persisted {
			document_workflow_reset_dir_abandonment(&commands.document_workflow)
			command_context_project_failure_diagnostic(commands, suppression_failure)
			return Interaction_Result{changed = true}, {}
		}
		decision = .Disable_Prompt
	}
	admission, admitted, admit_failure := editor_session.session_admit_dir_abandonment(
		commands.session_owner,
		prepared,
		decision,
	)
	if !admitted {
		document_workflow_reset_dir_abandonment(&commands.document_workflow)
		return {}, App_Failure{stage = .Session_Access, editor_session = admit_failure}
	}
	if admission == .Cancelled {
		document_workflow_reset_dir_abandonment(&commands.document_workflow)
		command_context_clear_exit(commands)
		return Interaction_Result{changed = true}, {}
	}
	return command_context_begin_dir_abandonment(
		commands,
		action,
		continuation,
	)
}

@(private)
command_context_open_project_directory :: proc(
	commands: ^Command_Context,
	path: string,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if commands.document_workflow.dir_abandonment_continuation == .None {
		return command_context_begin_dir_abandonment(
			commands,
			.Replace_Roots,
			.Open_Path,
			path,
		)
	}
	return command_context_open_project_directory_unchecked(commands, path, constraints)
}

@(private)
command_context_open_project_directory_unchecked :: proc(
	commands: ^Command_Context,
	path: string,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	state := &commands.project_workflow
	if state.next_project_id == project.Project_ID(0) {
		project_workflow_reset_transient(state)
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	opened, completed, command_failure := command.project_open_directory(
		command_context_project_command_context(commands, state.command_handle),
		commands.racket_runtime,
		commands.projects_directory,
		path,
		state.next_project_id,
	)
	if !completed {
		if command_failure.project_code == .Project_Switch_Unavailable &&
		   state.open_continuation == .None {
			if len(path) > len(state.pending_open_path) {
				project_workflow_reset_transient(state)
				return {}, App_Failure{stage = .Command_Dispatch}
			}
			copy(state.pending_open_path[:], transmute([]u8)path)
			state.pending_open_path_length = len(path)
			state.open_continuation = .Path
			return command_context_close_project_buffers(commands, state.command_handle, constraints)
		}
		project_workflow_clear_open_continuation(state)
		if command_failure.code == .Invalid_Request {
			command_context_set_channel_diagnostic(commands, .Project, "Directory is invalid or unavailable")
		} else {
			command_context_project_failure_diagnostic(commands, command_failure)
		}
		return Interaction_Result{changed = true}, {}
	}
	if opened.completion == .Already_Active {
		command_context_record_pending_project_selection(commands)
		project_workflow_clear_open_continuation(state)
		commands.diagnostic_length = 0
		return Interaction_Result{changed = true}, {}
	}
	if opened.completion == .Ambiguous {
		state.directory_open_candidates = opened.candidates
		project_workflow_clear_open_continuation(state)
		return command_context_present_directory_project_choices(commands, constraints)
	}
	if opened.completion == .Unregistered {
		state.next_project_id += 1
	}
	command_context_record_pending_project_selection(commands)
	project_workflow_clear_open_continuation(state)
	commands.diagnostic_length = 0
	return command_context_present_project_files(
		commands,
		constraints,
		state.command_handle,
	)
}

@(private)
command_context_open_directory_candidate :: proc(
	commands: ^Command_Context,
	index: int,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	state := &commands.project_workflow
	_, activated, activation_failure := command.project_open_directory_candidate(
		command_context_project_command_context(commands, state.command_handle),
		commands.racket_runtime,
		commands.projects_directory,
		&state.directory_open_candidates,
		index,
	)
	if !activated {
		if activation_failure.project_code == .Project_Switch_Unavailable &&
		   state.open_continuation == .None {
			state.open_continuation = .Candidate
			state.pending_open_candidate = index
			return command_context_close_project_buffers(commands, state.command_handle, constraints)
		}
		project_workflow_clear_open_continuation(state)
		command_context_project_failure_diagnostic(commands, activation_failure)
		return Interaction_Result{changed = true}, {}
	}
	command_context_deactivate_context_map(commands, .Completed)
	project_directory_choices_close(commands)
	project_list_workflow_reset(state)
	project_workflow_clear_open_continuation(state)
	commands.diagnostic_length = 0
	return command_context_present_project_files(commands, constraints, state.command_handle)
}

@(private)
command_context_continue_project_open :: proc(
	commands: ^Command_Context,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	state := &commands.project_workflow
	switch state.open_continuation {
	case .Path:
		path := string(state.pending_open_path[:state.pending_open_path_length])
		return command_context_open_project_directory(commands, path, constraints)
	case .Candidate:
		return command_context_open_directory_candidate(
			commands,
			state.pending_open_candidate,
			constraints,
		)
	case .None:
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	unreachable()
}

@(private)
command_context_present_directory_project_choices :: proc(
	commands: ^Command_Context,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	batch := &commands.project_workflow.directory_open_candidates
	if batch.state == nil || len(batch.candidates) < 2 {
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	state := &commands.project_workflow
	if state.list_mode != .Directory_Choices {
		state.list_position = {}
		state.list_current_membership = {}
		state.list_current_candidate_id = {}
		state.list_current_candidate_generation = {}
	}
	state.list_mode = .Directory_Choices
	state.list_return_target = startup_visible_target()
	if !project_list_workflow_advance_generation(state) {
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	if prepared, prepare_failure := project_list_workflow_prepare(
		state,
		constraints.height_rows,
	); !prepared {
		return {}, App_Failure{stage = .UI, ui = prepare_failure}
	}
	target := project_list_visible_target()
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner,
		commands.session_handle,
		target.ui,
	)
	if !presented {
		return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	commands.pending = {}
	command_context_set_channel_diagnostic(commands, .Project, "Select the registered Project for this directory")
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_present_project_inventory :: proc(
	commands: ^Command_Context,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
	)
	if !visible_ok {
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	return_target := visible
	if visible.kind != .Primary_View {
		if visible == project_list_visible_target() &&
		   commands.project_workflow.list_mode == .Inventory {
			return_target = commands.project_workflow.list_return_target
		} else {
			return_target = {}
		}
	}
	ctx := command.Project_Command_Context {
		session = commands.session_owner,
		handle = commands.session_handle,
		temporary_allocator = commands.temporary_allocator,
	}
	active, inspected, inspect_failure := command.project_inspect_active(ctx)
	if !inspected {
		command_context_project_failure_diagnostic(commands, inspect_failure)
		return Interaction_Result{changed = true}, {}
	}
	batch, listed, list_failure := command.project_list_directories(ctx)
	if !listed {
		command_context_project_failure_diagnostic(commands, list_failure)
		return Interaction_Result{changed = true}, {}
	}
	if commands.project_workflow.directory_candidates.state != nil {
		project.descriptor_batch_close(&commands.project_workflow.directory_candidates)
	}
	state := &commands.project_workflow
	state.directory_candidates = batch
	if state.list_mode != .Inventory {
		state.list_position = {}
		state.list_current_membership = {}
		state.list_current_candidate_id = {}
		state.list_current_candidate_generation = {}
	}
	state.list_mode = .Inventory
	state.list_return_target = return_target
	state.list_project = active.descriptor
	if !project_list_workflow_advance_generation(state) {
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	if prepared, prepare_failure := project_list_workflow_prepare(
		state,
		constraints.height_rows,
	); !prepared {
		return {}, App_Failure{stage = .UI, ui = prepare_failure}
	}
	target := project_list_visible_target()
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
command_context_project_command_context :: proc(
	commands: ^Command_Context,
	command_handle: interaction.Command_Handle = {},
) -> command.Project_Command_Context {
	return command.Project_Command_Context {
		session = commands.session_owner,
		handle = commands.session_handle,
		command = command_handle,
		persistent_allocator = commands.persistent_allocator,
		temporary_allocator = commands.temporary_allocator,
	}
}

@(private)
command_context_present_project_files :: proc(
	commands: ^Command_Context,
	constraints: display.Viewport_Constraints,
	command_handle: interaction.Command_Handle,
) -> (Interaction_Result, App_Failure) {
	if commands.candidate_ui.session.state != nil {
		_, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	}
	project_workflow_reset_transient(&commands.project_workflow)
	commands.project_workflow.command_handle = command_handle
	keep_workflow := false
	defer if !keep_workflow {project_workflow_reset_transient(&commands.project_workflow)}
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
	)
	if !visible_ok {
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	return_target := visible
	if visible.kind != .Primary_View {
		return_target = {}
	}
	ctx := command_context_project_command_context(commands, command_handle)
	policy := project.DEFAULT_POLICY
	policy.file_candidates = interaction.MAX_CANDIDATES
	started, start_failure := command.root_find_file_begin(
		ctx,
		&commands.project_workflow.file_search,
		policy,
	)
	if !started {
		command_context_project_failure_diagnostic(commands, start_failure)
		return Interaction_Result{changed = true}, {}
	}
	for {
		progress, advanced, advance_failure := command.root_find_file_advance(
			ctx,
			&commands.project_workflow.file_search,
		)
		if !advanced {
			command_context_project_failure_diagnostic(commands, advance_failure)
			return Interaction_Result{changed = true}, {}
		}
		if progress.complete {
			break
		}
	}
	batch, copied, copy_failure := command.root_find_file_candidates(
		ctx,
		&commands.project_workflow.file_search,
	)
	if !copied {
		command_context_project_failure_diagnostic(commands, copy_failure)
		return Interaction_Result{changed = true}, {}
	}
	root_path_buffer: [document.MAX_PATH_BYTES]u8
	root_path := command.root_find_file_path(&commands.project_workflow.file_search)
	copy(root_path_buffer[:], transmute([]u8)root_path)
	root_path = string(root_path_buffer[:len(root_path)])
	commands.project_workflow.file_candidates = batch
	if !command.project_find_file_close(&commands.project_workflow.file_search) {
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	source_generation := commands.candidate_ui.next_source_generation
	if source_generation == 0 || source_generation == max(u64) {
		return {}, App_Failure{stage = .Component_Access}
	}
	source: interaction.Root_File_Candidate_Source
	source_ok := false
	source_failure: interaction.Candidate_Failure
	if project.dir_handle_is_valid(commands.project_workflow.file_candidates.dir) {
		source, source_ok, source_failure = interaction.dir_file_candidate_source_build_generation(
			&commands.project_workflow.file_candidates,
			root_path,
			source_generation,
			commands.temporary_allocator,
		)
	} else {
		memberships, memberships_ok, memberships_failure := command.project_find_directory_candidates(ctx)
		if !memberships_ok {
			command_context_project_failure_diagnostic(commands, memberships_failure)
			return Interaction_Result{changed = true}, {}
		}
		defer project.descriptor_batch_close(&memberships)
		source, source_ok, source_failure = interaction.project_file_candidate_source_build_generation(
			&commands.project_workflow.file_candidates,
			memberships.descriptors,
			source_generation,
			commands.temporary_allocator,
		)
	}
	if !source_ok {
		command_context_candidate_failure_diagnostic(commands, "Root file candidate source", source_failure)
		return Interaction_Result{changed = true}, {}
	}
	defer interaction.project_file_candidate_source_close(&source)
	command_context_candidate_history_rank_source(commands, &source.definition, command_handle)
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
		source.definition,
	)
	if !initialized {
		command_context_candidate_failure_diagnostic(commands, "Root file candidate session", initialization_failure)
		return Interaction_Result{changed = true}, {}
	}
	keep_session := false
	defer if !keep_session {_, _, _ = interaction.candidate_session_close(&candidate_session)}
	_, viewed, candidate_failure := interaction.candidate_session_view(&candidate_session)
	if !viewed {
		return {}, App_Failure{stage = .Component_Access, candidate = candidate_failure}
	}
	if commands.candidate_ui.catalog.state != nil {
		interaction.command_catalog_close(&commands.candidate_ui.catalog)
	}
	target := candidate_ui_visible_target()
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner,
		commands.session_handle,
		target.ui,
	)
	if !presented {
		return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	commands.candidate_ui.session = candidate_session
	commands.candidate_ui.return_target = return_target
	commands.candidate_ui.next_session_id = session_id + 1
	commands.candidate_ui.next_source_generation = source_generation + 1
	keep_session = true
	keep_workflow = true
	commands.pending = {}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_present_project_buffers :: proc(
	commands: ^Command_Context,
	constraints: display.Viewport_Constraints,
	command_handle: interaction.Command_Handle,
) -> (Interaction_Result, App_Failure) {
	project_workflow_reset_transient(&commands.project_workflow)
	commands.project_workflow.command_handle = command_handle
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
	)
	if !visible_ok || visible.kind != .Primary_View {
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	active, active_ok, active_failure := command.project_inspect_active(
		command_context_project_command_context(commands, command_handle),
	)
	if !active_ok {
		command_context_project_failure_diagnostic(commands, active_failure)
		return Interaction_Result{changed = true}, {}
	}
	descriptors, descriptors_ok, descriptors_failure := editor_session.session_descriptors(
		commands.session_owner,
		commands.session_handle,
		commands.temporary_allocator,
	)
	if !descriptors_ok {
		return {}, App_Failure{stage = .Session_Access, editor_session = descriptors_failure}
	}
	defer editor_session.descriptor_batch_close(&descriptors)
	classified, classified_ok, classified_failure := editor_session.session_classify_project_buffers(
		commands.session_owner,
		commands.session_handle,
		active.descriptor.handle,
		commands.temporary_allocator,
	)
	if !classified_ok {
		return {}, App_Failure{stage = .Session_Access, editor_session = classified_failure}
	}
	defer editor_session.project_buffer_batch_close(&classified)
	source_generation := commands.candidate_ui.next_source_generation
	session_id := commands.candidate_ui.next_session_id
	if source_generation == 0 || source_generation == max(u64) ||
	   session_id == 0 || session_id == max(u64) {
		return {}, App_Failure{stage = .Component_Access}
	}
	source, source_ok, source_failure := interaction.project_buffer_candidate_source_build_query(
		&descriptors,
		&classified,
		source_generation,
		commands.temporary_allocator,
	)
	if !source_ok {
		command_context_candidate_failure_diagnostic(commands, "Project buffer candidate source", source_failure)
		return Interaction_Result{changed = true}, {}
	}
	defer interaction.buffer_candidate_source_close(&source)
	command_context_candidate_history_rank_source(commands, &source.definition, command_handle)
	candidate_session: interaction.Candidate_Session
	_, initialized, initialization_failure := interaction.candidate_session_init(
		&candidate_session,
		interaction.Candidate_Config {
			session_id = interaction.Candidate_Session_ID(session_id),
			limits = interaction.DEFAULT_CANDIDATE_LIMITS,
			persistent_allocator = commands.persistent_allocator,
			temporary_allocator = commands.temporary_allocator,
		},
		source.definition,
	)
	if !initialized {
		command_context_candidate_failure_diagnostic(commands, "Project buffer candidate session", initialization_failure)
		return Interaction_Result{changed = true}, {}
	}
	keep_session := false
	defer if !keep_session {_, _, _ = interaction.candidate_session_close(&candidate_session)}
	_, viewed, candidate_failure := interaction.candidate_session_view(&candidate_session)
	if !viewed {
		return {}, App_Failure{stage = .Component_Access, candidate = candidate_failure}
	}
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
	commands.project_workflow.buffer_candidate_project = active.descriptor.handle
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
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_project_list_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24},
) -> (Interaction_Result, App_Failure) {
	state := &commands.project_workflow
	if prepared, prepare_failure := project_list_workflow_prepare(
		state,
		constraints.height_rows,
	); !prepared {
		return {}, App_Failure{stage = .UI, ui = prepare_failure}
	}
	if map_failure := command_context_sync_list_map(commands, .Project); map_failure.stage != .None {
		return {}, map_failure
	}
	metadata, resolution, resolved, resolution_failure := command_context_resolve_context_input(commands, input)
	if !resolved {
		return {}, resolution_failure
	}
	if resolution.kind != .Command {
		return {}, {}
	}
	contextual_route, contextual_ok := command.contextual_route_decode(metadata.route)
	native_route, native_ok := command.native_route_decode(metadata.route)
	if native_ok && native_route == .Request_Editor_Exit {
		return command_context_request_exit(commands, resolution.command, nil)
	}
	if contextual_ok &&
	   (contextual_route == .Component_Previous_Row || contextual_route == .Component_Next_Row) {
		delta := i32(1)
		if contextual_route == .Component_Previous_Row {
			delta = -1
		}
		changed, moved, move_failure := project_list_workflow_move(state, delta)
		if !moved {
			return {}, App_Failure{stage = .UI, ui = move_failure}
		}
		return Interaction_Result{changed = changed}, {}
	}
	if contextual_route == .Component_Activate_Current {
		action, index, action_ok := project_list_workflow_current_action(state)
		if !action_ok do return {}, App_Failure{stage = .UI}
		if action == .Open_Directory_Candidate {
			return command_context_open_directory_candidate(commands, index, constraints)
		}
		if action == .Inspect_Directory {
			descriptor := state.directory_candidates.descriptors[index]
			command_context_set_channel_diagnostic(
				commands,
				.Project,
				fmt.bprintf(
					commands.overlay_text[:],
					"Directory [%v; %v]: %s",
					descriptor.trust,
					descriptor.availability,
					project.directory_path_text(&descriptor.path),
				),
			)
			return Interaction_Result{changed = true}, {}
		}
		if action == .Close {
			return command_context_leave_project_list(commands)
		}
	}
	if contextual_route != .Component_Close && !command_metadata_is_native(metadata, .Keyboard_Quit) {
		return {}, {}
	}
	return command_context_leave_project_list(commands)
}

@(private)
command_context_leave_project_list :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	state := &commands.project_workflow
	mode := state.list_mode
	return_target := state.list_return_target
	command_context_deactivate_context_map(commands, .Completed)
	if mode == .Directory_Choices {
		project_directory_choices_close(commands)
		project_list_workflow_reset(state)
		if return_target.kind != .UI_Root {
			return {}, App_Failure{stage = .Session_Access}
		}
		_, _, presented, present_failure := editor_session.session_present_ui(
			commands.session_owner,
			commands.session_handle,
			return_target.ui,
		)
		if !presented {
			return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
		}
		return Interaction_Result{changed = true}, {}
	}
	if mode != .Inventory {
		return {}, App_Failure{stage = .Session_Access}
	}
	if state.directory_candidates.state != nil {
		project.descriptor_batch_close(&state.directory_candidates)
	}
	project_list_workflow_reset(state)
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
project_directory_choices_close :: proc(commands: ^Command_Context) {
	command.project_directory_candidate_batch_close(
		&commands.project_workflow.directory_open_candidates,
	)
}

@(private)
command_context_leave_project_file_navigation :: proc(
	commands: ^Command_Context,
	return_target: editor_session.Visible_Target,
) -> (Interaction_Result, App_Failure) {
	command_context_deactivate_context_map(commands, .Completed)
	view, viewed, view_failure := interaction.candidate_session_view(
		&commands.candidate_ui.session,
	)
	if viewed {
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
	} else if commands.candidate_ui.session.state != nil {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	defer command_context_close_project_file_navigation(commands)
	commands.diagnostic_length = 0
	if return_target.kind == .Primary_View {
		_, activated, activation_failure := editor_session.session_activate(
			commands.session_owner,
			return_target.entry,
		)
		if !activated {
			return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
		}
		return Interaction_Result{changed = true}, {}
	}
	target := startup_visible_target()
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner,
		commands.session_handle,
		target.ui,
	)
	if !presented {
		return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_close_project_file_navigation :: proc(commands: ^Command_Context) {
	if commands.candidate_ui.session.state != nil {
		_, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	}
	commands.candidate_ui.return_target = {}
	project_workflow_reset_transient(&commands.project_workflow)
}

@(private)
command_context_set_project_file_query :: proc(
	commands: ^Command_Context,
	query: string,
) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(
		&commands.candidate_ui.session,
	)
	if !viewed || (view.source_kind != .Project_Files && view.source_kind != .Dir_Files) {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	_, changed, change_failure := interaction.candidate_session_set_query(
		&commands.candidate_ui.session,
		interaction.Candidate_Request {
			session_id = view.session_id,
			session_generation = view.session_generation,
		},
		query,
	)
	if !changed {
		command_context_candidate_failure_diagnostic(commands, "Project file candidate query", change_failure)
		return Interaction_Result{changed = true}, {}
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_refresh_project_file_candidates :: proc(
	commands: ^Command_Context,
	refresh_command: interaction.Command_Handle,
) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(
		&commands.candidate_ui.session,
	)
	if !viewed || (view.source_kind != .Project_Files && view.source_kind != .Dir_Files) ||
	   commands.project_workflow.file_candidates.state == nil {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	if project.dir_handle_is_valid(commands.project_workflow.file_candidates.dir) {
		return command_context_refresh_dir_file_candidates(commands, refresh_command, view)
	}
	ctx := command_context_project_command_context(commands, refresh_command)
	refresh: command.Project_Refresh_State
	initialized, init_failure := command.project_refresh_init(ctx, &refresh)
	if !initialized {
		command_context_project_failure_diagnostic(commands, init_failure)
		return Interaction_Result{changed = true}, {}
	}
	defer command.project_refresh_close(&refresh)
	requested, request_failure := command.project_refresh_request(ctx, &refresh)
	if !requested {
		command_context_project_failure_diagnostic(commands, request_failure)
		return Interaction_Result{changed = true}, {}
	}
	reconciliation: project.Reconcile_Result
	for {
		advanced: bool
		advance_failure: command.Failure_Context
		reconciliation, advanced, advance_failure = command.project_refresh_advance(ctx, &refresh)
		if !advanced {
			command_context_project_failure_diagnostic(commands, advance_failure)
			return Interaction_Result{changed = true}, {}
		}
		if reconciliation.published || reconciliation.cancelled {break}
	}
	if reconciliation.cancelled {
		command_context_set_channel_diagnostic(commands, .Project, "Project file refresh cancelled; prior candidates preserved")
		return Interaction_Result{changed = true}, {}
	}

	search: command.Project_File_Search
	policy := project.DEFAULT_POLICY
	policy.file_candidates = interaction.MAX_CANDIDATES
	started, start_failure := command.project_find_file_begin(ctx, &search, policy)
	if !started {
		command_context_project_failure_diagnostic(commands, start_failure)
		return Interaction_Result{changed = true}, {}
	}
	defer command.project_find_file_close(&search)
	for {
		progress, advanced, advance_failure := command.project_find_file_advance(ctx, &search)
		if !advanced {
			command_context_project_failure_diagnostic(commands, advance_failure)
			return Interaction_Result{changed = true}, {}
		}
		if progress.complete {break}
	}
	next_batch, copied, copy_failure := command.project_find_file_candidates(ctx, &search)
	if !copied {
		command_context_project_failure_diagnostic(commands, copy_failure)
		return Interaction_Result{changed = true}, {}
	}
	keep_batch := false
	defer if !keep_batch {project.file_candidate_batch_close(&next_batch)}
	memberships, memberships_ok, memberships_failure := command.project_find_directory_candidates(ctx)
	if !memberships_ok {
		command_context_project_failure_diagnostic(commands, memberships_failure)
		return Interaction_Result{changed = true}, {}
	}
	defer project.descriptor_batch_close(&memberships)
	source_generation := commands.candidate_ui.next_source_generation
	if source_generation == 0 || source_generation == max(u64) {
		return {}, App_Failure{stage = .Component_Access}
	}
	source, source_ok, source_failure := interaction.project_file_candidate_source_build_generation(
		&next_batch,
		memberships.descriptors,
		source_generation,
		commands.temporary_allocator,
	)
	if !source_ok {
		command_context_set_channel_diagnostic(commands, .Project, "Project file refresh exceeded candidate source limits; prior candidates preserved")
		_ = source_failure
		return Interaction_Result{changed = true}, {}
	}
	defer interaction.project_file_candidate_source_close(&source)
	command_context_candidate_history_rank_source(
		commands,
		&source.definition,
		commands.project_workflow.command_handle,
	)
	_, refreshed, refresh_failure := interaction.candidate_session_refresh(
		&commands.candidate_ui.session,
		interaction.Candidate_Request {
			session_id = view.session_id,
			session_generation = view.session_generation,
		},
		source.definition,
	)
	if !refreshed {
		command_context_candidate_failure_diagnostic(commands, "Project file candidate refresh", refresh_failure)
		return Interaction_Result{changed = true}, {}
	}
	project.file_candidate_batch_close(&commands.project_workflow.file_candidates)
	commands.project_workflow.file_candidates = next_batch
	keep_batch = true
	commands.candidate_ui.next_source_generation = source_generation + 1
	command_context_set_channel_diagnostic(
		commands,
		.Project,
		fmt.bprintf(
			commands.overlay_text[:],
			"Project files refreshed: generation %d; %d candidates; %d unavailable directories",
			reconciliation.generation,
			len(next_batch.descriptors),
			reconciliation.unavailable_directories,
		),
	)
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_refresh_dir_file_candidates :: proc(
	commands: ^Command_Context,
	refresh_command: interaction.Command_Handle,
	view: interaction.Candidate_View,
) -> (Interaction_Result, App_Failure) {
	ctx := command_context_project_command_context(commands, refresh_command)
	search: command.Project_File_Search
	policy := project.DEFAULT_POLICY
	policy.file_candidates = interaction.MAX_CANDIDATES
	started, start_failure := command.root_find_file_begin(ctx, &search, policy)
	if !started || !project.dir_handle_is_valid(search.dir) {
		command_context_project_failure_diagnostic(commands, start_failure)
		return Interaction_Result{changed = true}, {}
	}
	defer command.project_find_file_close(&search)
	for {
		progress, advanced, advance_failure := command.root_find_file_advance(ctx, &search)
		if !advanced {
			command_context_project_failure_diagnostic(commands, advance_failure)
			return Interaction_Result{changed = true}, {}
		}
		if progress.complete {break}
	}
	next_batch, copied, copy_failure := command.root_find_file_candidates(ctx, &search)
	if !copied {
		command_context_project_failure_diagnostic(commands, copy_failure)
		return Interaction_Result{changed = true}, {}
	}
	keep_batch := false
	defer if !keep_batch {project.file_candidate_batch_close(&next_batch)}
	source_generation := commands.candidate_ui.next_source_generation
	if source_generation == 0 || source_generation == max(u64) {
		return {}, App_Failure{stage = .Component_Access}
	}
	source, source_ok, source_failure := interaction.dir_file_candidate_source_build_generation(
		&next_batch,
		command.root_find_file_path(&search),
		source_generation,
		commands.temporary_allocator,
	)
	if !source_ok {
		command_context_candidate_failure_diagnostic(commands, "Dir file candidate refresh", source_failure)
		return Interaction_Result{changed = true}, {}
	}
	defer interaction.project_file_candidate_source_close(&source)
	command_context_candidate_history_rank_source(commands, &source.definition, refresh_command)
	_, refreshed, refresh_failure := interaction.candidate_session_refresh(
		&commands.candidate_ui.session,
		interaction.Candidate_Request {
			session_id = view.session_id,
			session_generation = view.session_generation,
		},
		source.definition,
	)
	if !refreshed {
		command_context_candidate_failure_diagnostic(commands, "Dir file candidate refresh", refresh_failure)
		return Interaction_Result{changed = true}, {}
	}
	project.file_candidate_batch_close(&commands.project_workflow.file_candidates)
	commands.project_workflow.file_candidates = next_batch
	keep_batch = true
	commands.candidate_ui.next_source_generation = source_generation + 1
	command_context_set_channel_diagnostic(
		commands,
		.Project,
		fmt.bprintf(
			commands.overlay_text[:],
			"Dir files refreshed: generation %d; %d candidates",
			next_batch.generation,
			len(next_batch.descriptors),
		),
	)
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_project_file_candidate_is_current :: proc(
	commands: ^Command_Context,
	view: interaction.Candidate_View,
	row: interaction.Candidate_Row,
) -> bool {
	if (view.source_kind != .Project_Files && view.source_kind != .Dir_Files) ||
	   row.action.kind != .Open_Document ||
	   row.durable_category != .Project_File || len(row.durable_key) == 0 ||
	   commands.project_workflow.file_candidates.state == nil {
		return false
	}
	batch := &commands.project_workflow.file_candidates
	if project.dir_handle_is_valid(batch.dir) {
		if view.source_kind != .Dir_Files || view.scope_identity != u64(batch.dir.id) ||
		   view.scope_generation != u64(batch.dir.generation) {
			return false
		}
		for descriptor in batch.descriptors {
			if descriptor.path == row.durable_key {
				return interaction.dir_file_candidate_action_matches(row.action, descriptor)
			}
		}
		return false
	}
	if view.source_kind != .Project_Files || view.scope_identity != u64(batch.project.id) ||
	   view.scope_generation != u64(batch.project.generation) {
		return false
	}
	active, active_ok, _ := command.project_inspect_active(
		command_context_project_command_context(commands, commands.project_workflow.command_handle),
	)
	if !active_ok || active.descriptor.handle != batch.project {
		return false
	}
	for descriptor in batch.descriptors {
		if descriptor.path == row.durable_key {
			return interaction.project_file_candidate_action_matches(row.action, descriptor)
		}
	}
	return false
}

@(private)
command_context_refresh_project_buffer_navigation :: proc(
	commands: ^Command_Context,
	query: string,
) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(
		&commands.candidate_ui.session,
	)
	if !viewed || view.source_kind != .Project_Buffers {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	active, active_ok, active_failure := command.project_inspect_active(
		command_context_project_command_context(commands, commands.project_workflow.command_handle),
	)
	if !active_ok || active.descriptor.handle != commands.project_workflow.buffer_candidate_project {
		command_context_project_failure_diagnostic(commands, active_failure)
		command_context_set_channel_diagnostic(commands, .Project, "Active Project changed; reopen project-switch-buffer")
		return Interaction_Result{changed = true}, {}
	}
	descriptors, descriptors_ok, descriptors_failure := editor_session.session_descriptors(
		commands.session_owner,
		commands.session_handle,
		commands.temporary_allocator,
	)
	if !descriptors_ok {
		return {}, App_Failure{stage = .Session_Access, editor_session = descriptors_failure}
	}
	defer editor_session.descriptor_batch_close(&descriptors)
	classified, classified_ok, classified_failure := editor_session.session_classify_project_buffers(
		commands.session_owner,
		commands.session_handle,
		active.descriptor.handle,
		commands.temporary_allocator,
	)
	if !classified_ok {
		return {}, App_Failure{stage = .Session_Access, editor_session = classified_failure}
	}
	defer editor_session.project_buffer_batch_close(&classified)
	source_generation := commands.candidate_ui.next_source_generation
	if source_generation == 0 || source_generation == max(u64) {
		return {}, App_Failure{stage = .Component_Access}
	}
	source, source_ok, source_failure := interaction.project_buffer_candidate_source_build_query(
		&descriptors,
		&classified,
		source_generation,
		commands.temporary_allocator,
	)
	if !source_ok {
		command_context_candidate_failure_diagnostic(commands, "Project buffer candidate refresh", source_failure)
		return Interaction_Result{changed = true}, {}
	}
	defer interaction.buffer_candidate_source_close(&source)
	command_context_candidate_history_rank_source(
		commands,
		&source.definition,
		commands.project_workflow.command_handle,
	)
	_, refreshed, refresh_failure := interaction.candidate_session_refresh(
		&commands.candidate_ui.session,
		interaction.Candidate_Request {
			session_id = view.session_id,
			session_generation = view.session_generation,
		},
		source.definition,
	)
	if !refreshed {
		command_context_candidate_failure_diagnostic(commands, "Project buffer candidate refresh", refresh_failure)
		return Interaction_Result{changed = true}, {}
	}
	commands.candidate_ui.next_source_generation = source_generation + 1
	view, viewed, view_failure = interaction.candidate_session_view(
		&commands.candidate_ui.session,
	)
	if !viewed {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	_, queried, query_failure := interaction.candidate_session_set_query(
		&commands.candidate_ui.session,
		interaction.Candidate_Request {
			session_id = view.session_id,
			session_generation = view.session_generation,
		},
		query,
	)
	if !queried {
		command_context_candidate_failure_diagnostic(commands, "Project buffer candidate query", query_failure)
		return Interaction_Result{changed = true}, {}
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_project_buffer_navigation_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	if commands.candidate_ui.session.state == nil ||
	   !project.project_handle_is_valid(commands.project_workflow.buffer_candidate_project) {
		return {}, App_Failure{stage = .Component_Access}
	}
	candidate_view, candidate_ok, candidate_failure := interaction.candidate_session_view(
		&commands.candidate_ui.session,
	)
	if !candidate_ok || candidate_view.source_kind != .Project_Buffers ||
	   candidate_view.scope_identity != u64(commands.project_workflow.buffer_candidate_project.id) ||
	   candidate_view.scope_generation != u64(commands.project_workflow.buffer_candidate_project.generation) {
		return {}, App_Failure{stage = .Component_Access, candidate = candidate_failure}
	}
	if map_failure := command_context_sync_candidate_map(commands, candidate_view.source_kind); map_failure.stage != .None {
		return {}, map_failure
	}
	metadata, resolution, resolved, resolution_failure := command_context_resolve_context_input(commands, input)
	if !resolved {return {}, resolution_failure}
	if resolution.kind != .Command {return {}, {}}
	request := interaction.Candidate_Request {
		session_id = candidate_view.session_id,
		session_generation = candidate_view.session_generation,
	}
	contextual_route, contextual_ok := command.contextual_route_decode(metadata.route)
	native_route, native_ok := command.native_route_decode(metadata.route)
	if native_ok && native_route == .Project_Refresh {
		return command_context_refresh_project_file_candidates(commands, resolution.command)
	}
	if contextual_ok &&
	   (contextual_route == .Component_Previous_Row || contextual_route == .Component_Next_Row) {
		if len(candidate_view.rows) == 0 {return {}, {}}
		delta := i32(1)
		if contextual_route == .Component_Previous_Row {delta = -1}
		_, moved, move_failure := interaction.candidate_session_move(
			&commands.candidate_ui.session,
			request,
			delta,
		)
		if !moved {
			command_context_candidate_failure_diagnostic(commands, "Project buffer candidate movement", move_failure)
			return Interaction_Result{changed = true}, {}
		}
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Query_Text {
		if len(resolution.text) == 0 {return {}, {}}
		if len(candidate_view.query) + len(resolution.text) > int(interaction.MAX_CANDIDATE_QUERY_BYTES) {
			command_context_set_channel_diagnostic(commands, .Project, "Project buffer query limit reached")
			return Interaction_Result{changed = true}, {}
		}
		query: [interaction.MAX_CANDIDATE_QUERY_BYTES]u8
		copy(query[:], transmute([]u8)candidate_view.query)
		copy(query[len(candidate_view.query):], transmute([]u8)resolution.text)
		return command_context_refresh_project_buffer_navigation(
			commands,
			string(query[:len(candidate_view.query) + len(resolution.text)]),
		)
	}
	if contextual_route == .Component_Query_Delete_Previous {
		if len(candidate_view.query) == 0 {return {}, {}}
		end := len(candidate_view.query) - 1
		bytes := transmute([]u8)candidate_view.query
		for end > 0 && bytes[end] & 0xc0 == 0x80 {end -= 1}
		return command_context_refresh_project_buffer_navigation(commands, candidate_view.query[:end])
	}
	if contextual_route == .Component_Activate_Current {
		if !candidate_view.has_selection || len(candidate_view.rows) == 0 {return {}, {}}
		row := candidate_view.rows[candidate_view.selected_row]
		entry, entry_ok := interaction.buffer_candidate_action_entry(row.action, commands.session_handle)
		if !entry_ok || !command_context_project_buffer_candidate_is_current(commands, row.action) {
			command_context_set_channel_diagnostic(commands, .Project, "Project buffer candidates changed; reopen project-switch-buffer")
			return Interaction_Result{changed = true}, {}
		}
		_, activated, activation_failure := editor_session.session_activate(commands.session_owner, entry)
		if !activated {
			command_context_set_channel_diagnostic(commands, .Project, "Project buffer candidate changed; reopen project-switch-buffer")
			_ = activation_failure
			return Interaction_Result{changed = true}, {}
		}
		_, visual_failure := command_context_modal_visual_finish_buffer_switch(commands, entry)
		if visual_failure.stage != .None do return {}, visual_failure
		_ = command_context_candidate_history_record(
			commands,
			row.durable_category,
			row.durable_key,
		)
		_, recorded, record_failure := interaction.candidate_session_record_success(
			&commands.candidate_ui.session,
			request,
			row.identity,
		)
		command_context_deactivate_context_map(commands, .Completed)
		command_context_close_project_buffer_navigation(commands)
		if !recorded {
			command_context_candidate_failure_diagnostic(commands, "Project buffer candidate recency", record_failure)
		}
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Close || command_metadata_is_native(metadata, .Keyboard_Quit) {
		return command_context_leave_project_buffer_navigation(commands, commands.candidate_ui.return_target)
	}
	return {}, {}
}

@(private)
command_context_project_buffer_candidate_is_current :: proc(
	commands: ^Command_Context,
	action: interaction.Candidate_Action,
) -> bool {
	active, active_ok, _ := command.project_inspect_active(
		command_context_project_command_context(commands, commands.project_workflow.command_handle),
	)
	if !active_ok || active.descriptor.handle != commands.project_workflow.buffer_candidate_project {
		return false
	}
	classified, classified_ok, _ := editor_session.session_classify_project_buffers(
		commands.session_owner,
		commands.session_handle,
		active.descriptor.handle,
		commands.temporary_allocator,
	)
	if !classified_ok {return false}
	defer editor_session.project_buffer_batch_close(&classified)
	for descriptor in classified.descriptors {
		if descriptor.scope == .Project_Owned &&
		   interaction.buffer_candidate_action_graph_matches(action, descriptor.graph) {
			return true
		}
	}
	return false
}

@(private)
command_context_leave_project_buffer_navigation :: proc(
	commands: ^Command_Context,
	return_target: editor_session.Visible_Target,
) -> (Interaction_Result, App_Failure) {
	command_context_deactivate_context_map(commands, .Completed)
	view, viewed, view_failure := interaction.candidate_session_view(
		&commands.candidate_ui.session,
	)
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
	defer command_context_close_project_buffer_navigation(commands)
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
command_context_close_project_buffer_navigation :: proc(commands: ^Command_Context) {
	if commands.candidate_ui.session.state != nil {
		_, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	}
	commands.candidate_ui.return_target = {}
	project_workflow_reset_transient(&commands.project_workflow)
}

@(private)
dispatch_project_file_navigation_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	if commands.candidate_ui.session.state == nil ||
	   commands.project_workflow.file_candidates.state == nil {
		return {}, App_Failure{stage = .Component_Access}
	}
	candidate_view, candidate_ok, candidate_failure := interaction.candidate_session_view(
		&commands.candidate_ui.session,
	)
	scope_matches := false
	if candidate_ok {
		batch := &commands.project_workflow.file_candidates
		if project.dir_handle_is_valid(batch.dir) {
			scope_matches = candidate_view.source_kind == .Dir_Files &&
			                candidate_view.scope_identity == u64(batch.dir.id) &&
			                candidate_view.scope_generation == u64(batch.dir.generation)
		} else {
			scope_matches = candidate_view.source_kind == .Project_Files &&
			                candidate_view.scope_identity == u64(batch.project.id) &&
			                candidate_view.scope_generation == u64(batch.project.generation)
		}
	}
	if !candidate_ok ||
	   (candidate_view.source_kind != .Project_Files && candidate_view.source_kind != .Dir_Files) ||
	   !scope_matches {
		return {}, App_Failure{stage = .Component_Access, candidate = candidate_failure}
	}
	if map_failure := command_context_sync_candidate_map(commands, candidate_view.source_kind);
	   map_failure.stage != .None {
		return {}, map_failure
	}
	metadata, resolution, resolved, resolution_failure := command_context_resolve_context_input(commands, input)
	if !resolved {return {}, resolution_failure}
	if resolution.kind != .Command {return {}, {}}
	request := interaction.Candidate_Request {
		session_id = candidate_view.session_id,
		session_generation = candidate_view.session_generation,
	}
	contextual_route, contextual_ok := command.contextual_route_decode(metadata.route)
	if contextual_ok &&
	   (contextual_route == .Component_Previous_Row || contextual_route == .Component_Next_Row) {
		if len(candidate_view.rows) == 0 {return {}, {}}
		delta := i32(1)
		if contextual_route == .Component_Previous_Row {delta = -1}
		_, moved, move_failure := interaction.candidate_session_move(
			&commands.candidate_ui.session,
			request,
			delta,
		)
		if !moved {
			command_context_candidate_failure_diagnostic(commands, "Project file candidate movement", move_failure)
			return Interaction_Result{changed = true}, {}
		}
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Query_Text {
		if len(resolution.text) == 0 {return {}, {}}
		if len(candidate_view.query) + len(resolution.text) > int(interaction.MAX_CANDIDATE_QUERY_BYTES) {
			command_context_set_channel_diagnostic(commands, .Project, "Project file query limit reached")
			return Interaction_Result{changed = true}, {}
		}
		query: [interaction.MAX_CANDIDATE_QUERY_BYTES]u8
		copy(query[:], transmute([]u8)candidate_view.query)
		copy(query[len(candidate_view.query):], transmute([]u8)resolution.text)
		return command_context_set_project_file_query(
			commands,
			string(query[:len(candidate_view.query) + len(resolution.text)]),
		)
	}
	if contextual_route == .Component_Query_Delete_Previous {
		if len(candidate_view.query) == 0 {return {}, {}}
		end := len(candidate_view.query) - 1
		bytes := transmute([]u8)candidate_view.query
		for end > 0 && bytes[end] & 0xc0 == 0x80 {end -= 1}
		return command_context_set_project_file_query(commands, candidate_view.query[:end])
	}
	if contextual_route == .Component_Activate_Current {
		if !candidate_view.has_selection || len(candidate_view.rows) == 0 {return {}, {}}
		row := candidate_view.rows[candidate_view.selected_row]
		if !command_context_project_file_candidate_is_current(commands, candidate_view, row) {
			command_context_set_channel_diagnostic(commands, .Project, "Project file candidates changed; refresh or reopen project-find-file")
			return Interaction_Result{changed = true}, {}
		}
		_, open_ok, open_failure := command.buffer_session_find_file(
			command.Buffer_Session_Context {
				session = commands.session_owner,
				handle = commands.session_handle,
				command = commands.project_workflow.command_handle,
				configuration = commands.entry_configuration,
			},
			row.durable_key,
		)
		if !open_ok {
			command_context_project_failure_diagnostic(commands, open_failure)
			return Interaction_Result{changed = true}, {}
		}
		_ = command_context_candidate_history_record(
			commands,
			row.durable_category,
			row.durable_key,
		)
		_, recorded, record_failure := interaction.candidate_session_record_success(
			&commands.candidate_ui.session,
			request,
			row.identity,
		)
		command_context_deactivate_context_map(commands, .Completed)
		command_context_close_project_file_navigation(commands)
		if !recorded {
			command_context_candidate_failure_diagnostic(commands, "Project file candidate recency", record_failure)
		}
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Close || command_metadata_is_native(metadata, .Keyboard_Quit) {
		return command_context_leave_project_file_navigation(commands, commands.candidate_ui.return_target)
	}
	return {}, {}
}

@(private)
command_context_save_project_buffers :: proc(
	commands: ^Command_Context,
	command_handle: interaction.Command_Handle,
) -> (Interaction_Result, App_Failure) {
	result, saved, failure := command.project_save_buffers(
		command_context_project_command_context(commands, command_handle),
	)
	if !saved {
		command_context_set_channel_diagnostic(
			commands,
			.Save,
			"Project buffers could not be saved",
			.Error,
			fmt.bprintf(
				commands.feedback_content[:],
				"Project save failed: %v (session: %v, project: %v)",
				failure.code,
				failure.editor_session_code,
				failure.project_code,
			),
			.Required,
			.History,
		)
		return Interaction_Result{changed = true}, {}
	}
	command_context_set_channel_diagnostic(
		commands,
		.Save,
		fmt.bprintf(
			commands.overlay_text[:],
			"Project buffers saved: %d of %d modified (%d examined)",
			result.saved_buffers,
			result.modified_buffers,
			result.examined_buffers,
		),
	)
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_close_project_buffers :: proc(
	commands: ^Command_Context,
	command_handle: interaction.Command_Handle,
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24},
) -> (Interaction_Result, App_Failure) {
	commands.project_workflow.command_handle = command_handle
	ctx := command_context_project_command_context(commands, command_handle)
	owned, owned_ok, owned_failure := command.project_switch_buffer_candidates(ctx)
	if !owned_ok {
		command_context_project_failure_diagnostic(commands, owned_failure)
		project_workflow_reset_transient(&commands.project_workflow)
		return Interaction_Result{changed = true}, {}
	}
	active_will_close := false
	for candidate in owned.candidates {
		if candidate.entry == commands.current_entry {
			active_will_close = true
			break
		}
	}
	command.project_buffer_candidate_batch_close(&owned)
	result, closed, failure := command.project_close_buffers(
		ctx,
		commands.project_workflow.close_authorities[:commands.project_workflow.close_authority_count],
	)
	if !closed {
		command_context_project_failure_diagnostic(commands, failure)
		project_workflow_reset_transient(&commands.project_workflow)
		return Interaction_Result{changed = true}, {}
	}
	if result.outcome == .Decision_Required {
		return command_context_begin_project_close_choice(commands, result.decision_entry)
	}
	if commands.project_workflow.open_continuation != .None {
		project_workflow_clear_close_attempt(&commands.project_workflow)
		continued, continue_failure := command_context_continue_project_open(commands, constraints)
		continued.active_entry_closed = continued.active_entry_closed || active_will_close
		return continued, continue_failure
	}
	command_context_set_channel_diagnostic(
		commands,
		.Project,
		fmt.bprintf(
			commands.overlay_text[:],
			"Project buffers closed: %d (%d examined)",
			result.closed_buffers,
			result.examined_buffers,
		),
	)
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
	)
	if !visible_ok {
		project_workflow_reset_transient(&commands.project_workflow)
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	if visible.kind == .None {
		target := startup_visible_target()
		_, _, presented, present_failure := editor_session.session_present_ui(
			commands.session_owner,
			commands.session_handle,
			target.ui,
		)
		if !presented {
			project_workflow_reset_transient(&commands.project_workflow)
			return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
		}
	}
	project_workflow_reset_transient(&commands.project_workflow)
	return Interaction_Result{changed = true, active_entry_closed = active_will_close}, {}
}

@(private)
command_context_begin_project_close_choice :: proc(
	commands: ^Command_Context,
	entry: editor_session.Entry_Handle,
) -> (Interaction_Result, App_Failure) {
	if commands.prompt_workflow.prompt.state != nil {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
	}
	choices := prompt_save_discard_cancel_choices()
	prompt_ok, prompt_failure := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		interaction.Prompt_Config {
			kind = .Fixed_Choice,
			choices = choices[:],
			allocator = commands.persistent_allocator,
		},
	)
	if !prompt_ok {
		return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	}
	if !prompt_workflow_begin_projection(&commands.prompt_workflow, .Project_Close_Choice) {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	commands.document_workflow.buffer_command = commands.project_workflow.command_handle
	commands.project_workflow.pending_close_entry = entry
	if map_failure := command_context_activate_prompt_map(commands, .Project_Close_Choice); map_failure.stage != .None {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		commands.prompt_workflow.mode = .None
		return {}, map_failure
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_project_close_prompt :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24},
) -> (Interaction_Result, App_Failure) {
	metadata, resolution, resolved, resolve_failure := command_context_resolve_prompt_input(commands, input)
	if !resolved {
		return {}, resolve_failure
	}
	if resolution.kind != .Command {
		return {}, {}
	}
	if command_metadata_is_cancel(metadata) {
		_, _ = interaction.prompt_cancel(&commands.prompt_workflow.prompt)
		command_context_deactivate_prompt_map(commands, .Cancelled)
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		commands.prompt_workflow.mode = .None
		if commands.project_workflow.open_continuation != .None {
			project_workflow_clear_close_attempt(&commands.project_workflow)
			project_workflow_clear_open_continuation(&commands.project_workflow)
			commands.diagnostic_length = 0
		} else {
			command_context_set_channel_diagnostic(commands, .Project, "Project buffer close cancelled")
			project_workflow_reset_transient(&commands.project_workflow)
		}
		return Interaction_Result{changed = true}, {}
	}
	choice := command_metadata_prompt_choice(metadata)
	if choice < 1 || choice > 3 {
		return {}, {}
	}
	_, choice_failure := interaction.prompt_choice_accept(&commands.prompt_workflow.prompt, choice)
	if choice_failure.code != .None {
		return {}, App_Failure{stage = .Prompt, prompt_failure = choice_failure}
	}
	_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
	command_context_deactivate_prompt_map(commands, .Completed)
	commands.prompt_workflow.mode = .None
	entry := commands.project_workflow.pending_close_entry
	command_handle := commands.project_workflow.command_handle
	if choice == 3 {
		if commands.project_workflow.open_continuation != .None {
			project_workflow_clear_close_attempt(&commands.project_workflow)
			project_workflow_clear_open_continuation(&commands.project_workflow)
			commands.diagnostic_length = 0
		} else {
			command_context_set_channel_diagnostic(commands, .Project, "Project buffer close cancelled")
			project_workflow_reset_transient(&commands.project_workflow)
		}
		return Interaction_Result{changed = true}, {}
	}
	if choice == 1 {
		_, saved, save_failure := command.buffer_session_save_entry(
			command.Buffer_Session_Context {
				session = commands.session_owner,
				handle = commands.session_handle,
				command = command_handle,
			},
			entry,
		)
		if !saved {
			command_context_project_failure_diagnostic(commands, save_failure)
			project_workflow_reset_transient(&commands.project_workflow)
			return Interaction_Result{changed = true}, {}
		}
	} else {
		index := commands.project_workflow.close_authority_count
		if index >= editor_session.MAX_LIVE_BUFFERS {
			project_workflow_reset_transient(&commands.project_workflow)
			return {}, App_Failure{stage = .Command_Dispatch}
		}
		commands.project_workflow.close_authorities[index] = editor_session.Close_Buffer_Request {
			entry = entry,
			authority = .Discard_Modified,
		}
		commands.project_workflow.close_authority_count += 1
	}
	return command_context_close_project_buffers(commands, command_handle, constraints)
}

@(private)
command_context_refresh_project :: proc(
	commands: ^Command_Context,
	command_handle: interaction.Command_Handle,
) -> (Interaction_Result, App_Failure) {
	state: command.Project_Refresh_State
	ctx := command_context_project_command_context(commands, command_handle)
	initialized, init_failure := command.project_refresh_init(ctx, &state)
	if !initialized {
		command_context_project_failure_diagnostic(commands, init_failure)
		return Interaction_Result{changed = true}, {}
	}
	defer command.project_refresh_close(&state)
	requested, request_failure := command.project_refresh_request(ctx, &state)
	if !requested {
		command_context_project_failure_diagnostic(commands, request_failure)
		return Interaction_Result{changed = true}, {}
	}
	result: project.Reconcile_Result
	for {
		advanced: bool
		failure: command.Failure_Context
		result, advanced, failure = command.project_refresh_advance(ctx, &state)
		if !advanced {
			command_context_project_failure_diagnostic(commands, failure)
			return Interaction_Result{changed = true}, {}
		}
		if result.published || result.cancelled {
			break
		}
	}
	if result.published {
		command_context_project_search_invalidate(commands)
	}
	command_context_set_channel_diagnostic(
		commands,
		.Project,
		fmt.bprintf(
			commands.overlay_text[:],
			"Project refreshed: generation %d; %d unavailable directories",
			result.generation,
			result.unavailable_directories,
		),
	)
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_inspect_active_project :: proc(commands: ^Command_Context) -> (Interaction_Result, App_Failure) {
	active, inspected, failure := command.project_inspect_active(
		command.Project_Command_Context {
			session = commands.session_owner,
			handle = commands.session_handle,
			temporary_allocator = commands.temporary_allocator,
		},
	)
	if !inspected {
		command_context_project_failure_diagnostic(commands, failure)
		return Interaction_Result{changed = true}, {}
	}
	message := fmt.bprintf(
		commands.feedback_content[:],
		"Project %s [%s]: %d directories",
		project.project_name_text(&active.descriptor.name),
		"temporary" if active.descriptor.temporary else "named",
		active.descriptor.directory_count,
	)
	command_context_set_channel_diagnostic(commands, .Project, message)
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_project_failure_diagnostic :: proc(
	commands: ^Command_Context,
	failure: command.Failure_Context,
) {
	#partial switch failure.code {
	case .Project_Scope_Required:
		command_context_set_channel_diagnostic(commands, .Project, "Project command requires an active Project")
		return
	case .Project_Duplicate:
		command_context_set_channel_diagnostic(
			commands,
			.Project,
			"A registered single-directory Project already uses this directory",
		)
		return
	case .Project_Durability_Failure:
		command_context_set_channel_diagnostic(commands, .Project, "Project state could not be persisted")
		return
	case .Project_Promotion_Rejected:
		command_context_set_channel_diagnostic(commands, .Project, "Dir promotion was rejected by local or discovery state")
		return
	case .Project_Promotion_Unresolved:
		command_context_set_channel_diagnostic(commands, .Project, "Project promotion requires durable reconciliation")
		return
	case .Project_Suppression_Rejected:
		command_context_set_channel_diagnostic(commands, .Project, "Dir promotion preference could not be persisted")
		return
	case .Project_Suppression_Unresolved:
		command_context_set_channel_diagnostic(commands, .Project, "Dir promotion preference requires durable reconciliation")
		return
	case .None:
	}
	#partial switch failure.project_code {
	case .Project_Switch_Unavailable:
		command_context_set_channel_diagnostic(
			commands,
			.Project,
			"Project switch unavailable: close the active Project before opening another directory",
		)
		return
	case .Stale_Catalog:
		command_context_set_channel_diagnostic(commands, .Project, "Project catalog changed; open the directory again")
		return
	case .Invalid_Resolution:
		command_context_set_channel_diagnostic(commands, .Project, "Project directory resolution is invalid")
		return
	case .None:
	}
	detail := fmt.bprintf(
		commands.feedback_content[:],
		"Project command failed: %v (session: %v, project: %v)",
		failure.code,
		failure.editor_session_code,
		failure.project_code,
	)
	command_context_set_channel_diagnostic(
		commands,
		.Project,
		"Project operation could not be completed",
		.Error,
		detail,
		.Required,
		.History,
	)
}
