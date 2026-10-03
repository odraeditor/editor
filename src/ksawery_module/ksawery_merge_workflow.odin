// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import "../interaction"
import "../ksawery"
import "../product_module"
import "../ui"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:unicode/utf8"

@(private)
ksawery_workflow_clear_merge_preparation :: proc(state: ^Ksawery_Workflow_State) {
	if state == nil do return
	state.merge_policy = .Invalid
	state.merge_action = .Invalid
	state.merge_precondition = {}
	state.merge_confirmation = {}
	state.merge_request = {}
}

@(private)
ksawery_workflow_clear_conflict_preparation :: proc(state: ^Ksawery_Workflow_State) {
	if state == nil do return
	state.conflict_action = .Invalid
	state.conflict_precondition = {}
	state.conflict_confirmation = {}
	state.conflict_request = {}
	state.conflict_stage_zero = {}
	state.conflict_path = {}
	state.conflict_path_length = 0
}

@(private)
ksawery_workflow_merge_editor_state :: proc(
	commands: ^Command_Context,
) -> (ksawery.Merge_Editor_State, bool) {
	branch_state, inspected := ksawery_workflow_branch_editor_state(commands)
	if !inspected do return {}, false
	return {
		repository_resources = branch_state.repository_resources,
		modified_repository_resources = branch_state.modified_repository_resources,
	}, true
}

@(private)
ksawery_workflow_selected_merge_source :: proc(
	state: ^Ksawery_Workflow_State,
) -> (ksawery.Ref_Identity, bool) {
	if state == nil || state.refs.state == nil ||
	   !ksawery.ref_selection_is_current(&state.refs, state.ref_selection) ||
	   state.ref_selection.current.kind != .Ref {
		return {}, false
	}
	source := state.ref_selection.current.reference
	if source.object_type != .Commit ||
	   (source.kind != .Local_Branch && source.kind != .Remote_Tracking_Branch && source.kind != .Tag) {
		return {}, false
	}
	return source, true
}

@(private)
ksawery_workflow_begin_merge :: proc(
	commands: ^Command_Context,
	action: ksawery.Merge_Action,
	policy := ksawery.Merge_Fast_Forward_Policy.Invalid,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.observation.state == nil || state.refs.state == nil ||
	   state.sequence.state == nil || state.process.state != nil {
		return false
	}
	source: ksawery.Ref_Identity
	if action == .Start {
		if state.view_mode != .Refs {
			state.failure = .Action_Unavailable
			command_context_set_diagnostic(commands, "Open Refs and select one exact commit-backed ref to merge")
			return true
		}
		available := false
		source, available = ksawery_workflow_selected_merge_source(state)
		if !available {
			state.failure = .Ref_Unavailable
			command_context_set_diagnostic(commands, "Select one exact commit-backed branch or tag")
			return true
		}
	} else if state.view_mode != .Sequence {
		state.failure = .Action_Unavailable
		command_context_set_diagnostic(commands, "Open the active merge sequence before using merge controls")
		return true
	}
	editor_state, inspected := ksawery_workflow_merge_editor_state(commands)
	if !inspected {
		state.failure = .Presentation_Unavailable
		command_context_set_diagnostic(commands, "Repository-associated editor buffers could not be checked")
		return true
	}
	if editor_state.modified_repository_resources != 0 {
		state.failure = .Modified_Buffer
		command_context_set_diagnostic(commands, "Save repository buffers before preparing this merge action")
		return true
	}
	ksawery_workflow_clear_merge_preparation(state)
	process, started, failure := ksawery.repository_process_start_merge_precondition(
		&state.observation,
		&state.refs,
		&state.sequence,
		source,
		action,
		policy,
		editor_state,
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
	)
	if !started {
		state.failure = failure
		command_context_set_diagnostic(commands, "Checked merge preconditions are unavailable")
		return true
	}
	kind := ksawery.Repository_Operation_Kind.Merge
	title := "Merge Repository Ref"
	if action == .Continue {
		kind = .Continue_Merge
		title = "Continue Repository Merge"
	} else if action == .Abort {
		kind = .Abort_Merge
		title = "Abort Repository Merge"
	}
	recorded, record_failure := ksawery_process_observation_begin(
		&state.process_coordinator,
		&process,
		state.process_coordinator.confirmed_observation,
		{
			kind = kind,
			target_kind = .Repository,
			title = title,
			target = ksawery.repository_context_string(&state.repository),
			phase_detail = "Checking merge preconditions",
			checking = true,
		},
		ksawery_workflow_now(commands),
	)
	if !recorded {
		ksawery.repository_process_close(&process)
		state.failure = record_failure
		return true
	}
	state.merge_policy = policy
	state.merge_action = action
	state.process = process
	state.pending = .Merge_Precondition
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_prepare_merge_confirmation :: proc(
	commands: ^Command_Context,
	precondition: ksawery.Merge_Precondition,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil do return false
	id := state.next_merge_confirmation
	if id == ksawery.Merge_Confirmation_ID(0) do id = 1
	confirmation, prepared, failure := ksawery.merge_confirmation_prepare(precondition, id)
	if !prepared {
		state.failure = failure
		command_context_set_diagnostic(commands, "Exact merge confirmation could not be prepared")
		return true
	}
	state.merge_precondition = precondition
	state.merge_confirmation = confirmation
	state.next_merge_confirmation = id + 1
	if state.next_merge_confirmation == ksawery.Merge_Confirmation_ID(0) do state.next_merge_confirmation = 1
	state.view_mode = .Merge_Confirmation
	state.position = {}
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_confirm_merge :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Merge_Confirmation || state.process.state != nil do return false
	confirmed, confirmation_failure := ksawery.merge_confirmation_confirm(
		&state.merge_confirmation,
		state.merge_confirmation.id,
	)
	if !confirmed {
		state.failure = confirmation_failure
		return true
	}
	operation := state.next_merge
	if operation == ksawery.Merge_Operation_ID(0) do operation = 1
	request, prepared, failure := ksawery.merge_request_prepare(
		state.merge_precondition,
		operation,
		&state.merge_confirmation,
	)
	if !prepared {
		state.failure = failure
		return true
	}
	process, started, start_failure := ksawery.repository_process_start_merge(
		state.merge_precondition,
		request,
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
	)
	if !started {
		state.failure = start_failure
		command_context_set_diagnostic(commands, "Checked merge action could not start")
		return true
	}
	attached, attach_failure := ksawery_process_operation_attach_child(
		&state.process_coordinator, &process, ksawery_workflow_now(commands),
	)
	if !attached {
		ksawery.repository_process_close(&process)
		state.failure = attach_failure
		return true
	}
	published, publish_failure := ksawery_process_operation_publish_phase(
		&state.process_coordinator,
		&process,
		.Executing,
		"Applying checked merge action",
		true,
		ksawery_workflow_now(commands),
	)
	if !published {
		_, _ = ksawery_process_operation_detach_child(&state.process_coordinator, &process)
		ksawery.repository_process_close(&process)
		state.failure = publish_failure
		return true
	}
	if state.merge_result.state != nil do ksawery.merge_result_close(&state.merge_result)
	state.merge_request = request
	state.process = process
	state.pending = .Merge
	state.next_merge = operation + 1
	if state.next_merge == ksawery.Merge_Operation_ID(0) do state.next_merge = 1
	state.view_mode = request.precondition.action == .Start ? .Refs : .Sequence
	state.failure = .None
	return true
}

@(private)
dispatch_ksawery_merge_confirmation_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Merge_Confirmation || state.process.state != nil {
		return {}, App_Failure{stage = .UI}
	}
	if input.kind == .Key && input.stroke.kind == .Unicode_Scalar &&
	   ((input.stroke.scalar == 'g' && input.stroke.modifiers == {.Control}) ||
	    (input.stroke.scalar == 'q' && input.stroke.modifiers == {})) {
		_ = ksawery_process_observation_finish_without_child(
			&state.process_coordinator, .Cancelled, .Cancelled_Before_Effect,
			"Merge confirmation cancelled", ksawery_workflow_now(commands),
		)
		return_mode := state.merge_action == .Start ? Ksawery_View_Mode.Refs : .Sequence
		ksawery_workflow_clear_merge_preparation(state)
		state.view_mode = return_mode
		state.failure = .Cancelled
		return Interaction_Result{changed = true}, {}
	}
	if input.kind == .Key && input.stroke.kind == .Enter && input.stroke.modifiers == {.Control} {
		return Interaction_Result{changed = ksawery_workflow_confirm_merge(commands)}, {}
	}
	return {}, {}
}

@(private)
ksawery_workflow_selected_conflict :: proc(
	state: ^Ksawery_Workflow_State,
) -> (ksawery.Conflict_Target, string, bool) {
	if state == nil || state.sequence.state == nil || state.conflict_selection == 0 do return {}, "", false
	target, found := ksawery.sequence_observation_conflict(
		&state.sequence, u32(state.conflict_selection) - 1,
	)
	if !found do return {}, "", false
	path, copied := ksawery.sequence_observation_conflict_path(&state.sequence, target)
	return target, path, copied && len(path) > 0
}

@(private)
ksawery_workflow_conflict_editor_state :: proc(
	commands: ^Command_Context,
	absolute_path: string,
	fingerprint: ksawery.Conflict_Content_Fingerprint,
) -> (ksawery.Conflict_Editor_State, bool) {
	inspection, inspected := host_session_request(
		&commands.host,
		.Inspect_Documents,
		0,
		product_module.SESSION_PATH_EXACT,
		absolute_path,
	)
	if !inspected do return {}, false
	open := inspection.flags & product_module.SESSION_DOCUMENT_OPEN != 0
	modified := inspection.flags & product_module.SESSION_DOCUMENT_MODIFIED != 0
	return {
		open = open,
		modified = modified,
		saved_fingerprint = fingerprint if open && !modified else {},
	}, true
}

@(private)
ksawery_workflow_conflict_worktree :: proc(
	commands: ^Command_Context,
	path: string,
) -> (ksawery.Conflict_Worktree_Result, ksawery.Conflict_Editor_State, bool) {
	absolute, path_error := os.join_path(
		{ksawery.repository_context_string(&commands.ksawery_workflow.repository), path},
		commands.temporary_allocator,
	)
	if path_error != nil do return {}, {}, false
	defer delete(absolute, commands.temporary_allocator)
	info, stat_error := os.lstat(absolute, commands.temporary_allocator)
	if stat_error != nil {
		worktree := ksawery.Conflict_Worktree_Result{content = .Unavailable}
		editor, inspected := ksawery_workflow_conflict_editor_state(commands, absolute, {})
		return worktree, editor, inspected
	}
	defer os.file_info_delete(info, commands.temporary_allocator)
	if info.type != .Regular || info.size < 0 || u64(info.size) > ksawery.DEFAULT_DIFF_BYTES {
		return {}, {}, false
	}
	content, read_error := os.read_entire_file(absolute, commands.temporary_allocator)
	if read_error != nil do return {}, {}, false
	defer delete(content, commands.temporary_allocator)
	fingerprint: ksawery.Conflict_Content_Fingerprint
	if !ksawery.conflict_content_fingerprint_compute(&fingerprint, content) do return {}, {}, false
	content_kind := ksawery.Conflict_Content_Kind.Text
	if !utf8.valid_string(string(content)) {
		content_kind = .Binary
	} else {
		for byte in content {
			if byte == 0 {
				content_kind = .Binary
				break
			}
		}
	}
	node := ksawery.Conflict_Node_Kind.Regular
	mode := u32(0o100644)
	if .Execute_User in info.mode || .Execute_Group in info.mode || .Execute_Other in info.mode {
		node = .Executable
		mode = 0o100755
	}
	worktree := ksawery.Conflict_Worktree_Result {
		exists = true,
		node = node,
		content = content_kind,
		mode = mode,
		fingerprint = fingerprint,
	}
	editor, inspected := ksawery_workflow_conflict_editor_state(commands, absolute, fingerprint)
	return worktree, editor, inspected
}

@(private)
ksawery_workflow_conflict_assistance_observation :: proc(
	commands: ^Command_Context,
) -> (ksawery.Conflict_Assistance_Observation, []u8, bool) {
	if commands == nil || commands.ksawery_workflow == nil do return {}, nil, false
	state := commands.ksawery_workflow
	conflict, path, selected := ksawery_workflow_selected_conflict(state)
	if !selected || state.generation == 0 do return {}, nil, false
	sequence_descriptor, described := ksawery.sequence_observation_descriptor(&state.sequence)
	if !described do return {}, nil, false
	target := ksawery.Conflict_Assistance_Target {
		repository = state.repository,
		repository_generation = ksawery.Repository_Generation(state.generation),
		worktree_generation = ksawery.Worktree_Generation(state.generation),
		observation_generation = state.generation,
		conflict = {
			sequence = {
				generation = sequence_descriptor.generation,
				fingerprint = sequence_descriptor.fingerprint,
			},
			conflict = conflict.id,
		},
		kind = conflict.kind,
		classes = {.Text},
	}
	if !ksawery.conflict_assistance_path_assign(&target.path, path) do return {}, nil, false
	#partial switch conflict.kind {
	case .Deleted_By_Us, .Deleted_By_Them, .Both_Deleted:
		target.classes += {.Delete}
	case .Other:
		target.classes += {.Unsupported}
	case:
	}
	observation := ksawery.Conflict_Assistance_Observation{target = target}
	truncated := false
	first_mode: u32
	for stage, index in conflict.stages {
		kind := ksawery.Conflict_Assistance_Side_Kind(index + 1)
		if !stage.available {
			observation.sides[index] = {kind = kind, material = .Missing}
			observation.target.classes += {.Missing_Stage}
			continue
		}
		observation.sides[index] = {
			kind = kind,
			material = .Omitted,
			mode = stage.mode,
			object = stage.object,
			truncated = true,
		}
		truncated = true
		if first_mode == 0 {
			first_mode = stage.mode
		} else if first_mode != stage.mode {
			observation.target.classes += {.Type_Change}
		}
		if stage.mode == 0o160000 do observation.target.classes += {.Submodule}
	}
	absolute, path_error := os.join_path(
		{ksawery.repository_context_string(&state.repository), path},
		commands.temporary_allocator,
	)
	if path_error != nil do return {}, nil, false
	defer delete(absolute, commands.temporary_allocator)
	info, stat_error := os.lstat(absolute, commands.temporary_allocator)
	if stat_error != nil {
		observation.sides[3] = {kind = .Worktree, material = .Missing}
	} else {
		defer os.file_info_delete(info, commands.temporary_allocator)
		mode := u32(0o100644)
		if .Execute_User in info.mode || .Execute_Group in info.mode || .Execute_Other in info.mode {
			mode = 0o100755
		}
		if info.type != .Regular || info.size < 0 ||
		   u64(info.size) > ksawery.DEFAULT_CONFLICT_ASSISTANCE_CONTENT_BYTES {
			observation.sides[3] = {
				kind = .Worktree,
				material = .Omitted,
				mode = mode,
				truncated = true,
			}
			observation.target.classes += {.Unsupported}
			truncated = true
		} else {
			content, read_error := os.read_entire_file(absolute, commands.temporary_allocator)
			if read_error != nil do return {}, nil, false
			observation.sides[3] = {
				kind = .Worktree,
				material = .Text,
				mode = mode,
				content = {offset = 0, length = u32(len(content))},
			}
			if !utf8.valid_string(string(content)) {
				observation.sides[3].material = .Binary
				observation.target.classes -= {.Text}
				observation.target.classes += {.Binary}
			} else {
				for byte in content {
					if byte == 0 {
						observation.sides[3].material = .Binary
						observation.target.classes -= {.Text}
						observation.target.classes += {.Binary}
						break
					}
				}
			}
			observation.content = content
		}
	}
	if truncated {
		observation.truncated = true
		observation.target.classes += {.Truncated}
	}
	_, failure := ksawery.conflict_assistance_observation_validate(observation)
	if failure.code != .None {
		if observation.content != nil do delete(observation.content, commands.temporary_allocator)
		return {}, nil, false
	}
	return observation, observation.content, true
}

@(private)
ksawery_workflow_conflict_index_fingerprint :: proc(
	state: ^Ksawery_Workflow_State,
	allocator: runtime.Allocator,
) -> (ksawery.Conflict_Assistance_Index_Fingerprint, bool) {
	if state == nil || allocator.procedure == nil do return {}, false
	repository := ksawery.repository_context_string(&state.repository)
	dot_git, path_error := os.join_path({repository, ".git"}, allocator)
	if path_error != nil do return {}, false
	defer delete(dot_git, allocator)
	info, stat_error := os.lstat(dot_git, allocator)
	if stat_error != nil do return {}, false
	defer os.file_info_delete(info, allocator)
	git_directory := string(dot_git)
	owned_directory: string
	if info.type == .Regular {
		pointer, read_error := os.read_entire_file(dot_git, allocator)
		if read_error != nil do return {}, false
		defer delete(pointer, allocator)
		value := strings.trim_space(string(pointer))
		prefix :: "gitdir:"
		if !strings.has_prefix(value, prefix) do return {}, false
		location := strings.trim_space(value[len(prefix):])
		if len(location) == 0 do return {}, false
		if location[0] == '/' {
			owned_directory, path_error = strings.clone(location, allocator)
		} else {
			joined, join_error := os.join_path({repository, location}, allocator)
			if join_error != nil do return {}, false
			owned_directory = string(joined)
			path_error = nil
		}
		if path_error != nil do return {}, false
		defer delete(owned_directory, allocator)
		git_directory = owned_directory
	} else if info.type != .Directory {
		return {}, false
	}
	index_path, index_error := os.join_path({git_directory, "index"}, allocator)
	if index_error != nil do return {}, false
	defer delete(index_path, allocator)
	index, read_error := os.read_entire_file(index_path, allocator)
	if read_error != nil do return {}, false
	defer delete(index, allocator)
	fingerprint: ksawery.Conflict_Assistance_Index_Fingerprint
	return fingerprint, ksawery.conflict_assistance_index_fingerprint_compute(&fingerprint, index)
}

@(private)
ksawery_workflow_begin_conflict_assistance_tool :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	state := commands.ksawery_workflow
	if state == nil || state.conflict_assistance == nil ||
	   state.conflict_assistance.operation.active || state.process.state != nil {
		return {}, {}
	}
	index, copied := ksawery_workflow_conflict_index_fingerprint(
		state,
		commands.temporary_allocator,
	)
	if !copied {
		state.failure = .Presentation_Unavailable
		command_context_set_diagnostic(commands, "Conflict assistance could not fingerprint the complete Git index")
		return Interaction_Result{changed = true}, {}
	}
	evaluation := &state.conflict_assistance.evaluation
	started, failure := ksawery_conflict_assistance_workflow_begin_tool(
		state.conflict_assistance,
		&state.process_coordinator,
		index,
		evaluation.provider.contributor,
		state.repository,
		ksawery.Repository_Generation(state.generation),
		ksawery_workflow_now(commands),
	)
	if !started {
		state.failure = .Action_Unavailable
		command_context_set_diagnostic(commands, fmt.tprintf(
			"Conflict assistance tool was rejected: %v",
			failure.code,
		))
		return Interaction_Result{changed = true}, {}
	}
	state.pending = .Conflict_Assistance
	state.conflict_assistance_refresh = .None
	state.conflict_assistance_refresh_completed = {.Process}
	state.failure = .None
	command_context_set_diagnostic(commands, "Conflict assistance tool is running in Process")
	return Interaction_Result{changed = true}, {}
}

@(private)
ksawery_workflow_start_conflict_assistance_refresh :: proc(
	commands: ^Command_Context,
	refresh: Ksawery_Conflict_Assistance_Refresh,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.conflict_assistance == nil ||
	   !state.conflict_assistance.operation.awaiting_refresh || state.process.state != nil ||
	   (refresh != .Status && refresh != .Sequence) {
		return false
	}
	process: ksawery.Repository_Process
	started := false
	failure := ksawery.Failure_Code.None
	if refresh == .Status {
		process, started, failure = ksawery.repository_process_start(
			{
				kind = .Observe_Status,
				repository = state.repository,
				limits = ksawery.DEFAULT_PROCESS_LIMITS,
			},
			ksawery_workflow_now(commands),
			commands.persistent_allocator,
		)
	} else {
		process, started, failure = ksawery.repository_process_start_sequence_observation(
			state.repository,
			ksawery_workflow_now(commands),
			ksawery.DEFAULT_SEQUENCE_LIMITS,
			commands.persistent_allocator,
		)
	}
	if !started {
		state.failure = failure
		return false
	}
	attached, attach_failure := ksawery_process_operation_attach_child(
		&state.process_coordinator,
		&process,
		ksawery_workflow_now(commands),
	)
	if !attached {
		ksawery.repository_process_close(&process)
		state.failure = attach_failure
		return false
	}
	if refresh == .Status {
		state.generation += 1
		if state.generation == 0 do state.generation = 1
	} else {
		state.sequence_generation += 1
		if state.sequence_generation == 0 do state.sequence_generation = 1
	}
	state.process = process
	state.pending = .Conflict_Assistance
	state.conflict_assistance_refresh = refresh
	return true
}

@(private)
ksawery_workflow_finish_conflict_assistance :: proc(
	commands: ^Command_Context,
	target_present: bool,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.conflict_assistance == nil do return false
	evaluation := &state.conflict_assistance.evaluation
	evidence := ksawery.Conflict_Assistance_Tool_Refresh_Evidence {
		repository = state.repository,
		repository_generation = ksawery.Repository_Generation(state.generation),
		worktree_generation = ksawery.Worktree_Generation(state.generation),
		observation_generation = state.generation,
		attempted = ksawery.CONFLICT_ASSISTANCE_TOOL_REFRESH,
		completed = state.conflict_assistance_refresh_completed,
		target_checked = true,
		target_present = target_present,
	}
	if target_present {
		observation, content, copied := ksawery_workflow_conflict_assistance_observation(commands)
		if copied {
			if content != nil do defer delete(content, commands.temporary_allocator)
			evidence.target = observation.target
			evidence.target.conflict = evaluation.request.target.conflict
		} else {
			evidence.target_present = false
		}
	}
	evidence.index_after, _ = ksawery_workflow_conflict_index_fingerprint(
		state,
		commands.temporary_allocator,
	)
	completed, failure := ksawery_conflict_assistance_workflow_complete(
		state.conflict_assistance,
		&state.process_coordinator,
		evidence,
		ksawery_workflow_now(commands),
	)
	state.pending = .None
	state.conflict_assistance_refresh = .None
	state.view_mode = .Conflict if evidence.target_present else .Sequence
	state.position = {}
	if completed {
		state.failure = .None
		command_context_set_diagnostic(commands, "Conflict assistance tool returned to refreshed Conflict; choose an explicit core action")
	} else {
		state.failure = .Action_Unavailable
		command_context_set_diagnostic(commands, fmt.tprintf(
			"Conflict assistance tool returned with rejected evidence: %v",
			failure.code,
		))
	}
	return true
}

@(private)
ksawery_workflow_finish_conflict_assistance_refresh_child :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.process.state == nil ||
	   (poll.state != .Completed && poll.state != .Failed) {
		return false
	}
	opened := false
	if state.conflict_assistance_refresh == .Status && poll.state == .Completed {
		observation: ksawery.Status_Observation
		observation, opened, state.failure = ksawery.repository_process_take_status(
			&state.process,
			state.generation,
			commands.persistent_allocator,
		)
		if opened {
			next_selection, reconciled, _ := ksawery.status_selection_reconcile(
				&state.observation,
				&observation,
				state.selection,
				nil,
			)
			if state.observation.state != nil do ksawery.status_observation_close(&state.observation)
			state.observation = observation
			state.selection = next_selection if reconciled else ksawery.Status_Selection{}
			if !reconciled do state.selection, _ = ksawery.status_selection_begin(&state.observation)
			_ = ksawery_extension_status_refresh(
				&state.extension_registry,
				&commands.host,
				&state.observation,
				commands.temporary_allocator,
			)
			state.conflict_assistance_refresh_completed += {.Status}
		}
	} else if state.conflict_assistance_refresh == .Sequence && poll.state == .Completed {
		sequence: ksawery.Sequence_Observation
		sequence, opened, state.failure = ksawery.repository_process_take_sequence(
			&state.process,
			state.sequence_generation,
			commands.persistent_allocator,
		)
		if opened {
			next_conflict := ksawery_workflow_reconcile_conflict_selection(
				&state.sequence,
				&sequence,
				state.conflict_selection,
			)
			if state.sequence.state != nil do ksawery.sequence_observation_close(&state.sequence)
			state.sequence = sequence
			state.conflict_selection = next_conflict
			_ = ksawery_extension_annotations_refresh_sequence(
				&state.extension_registry,
				&commands.host,
				&state.sequence,
				commands.temporary_allocator,
			)
			state.conflict_assistance_refresh_completed += {.Sequence, .Conflict}
		}
	}
	detached, detach_failure := ksawery_process_operation_detach_child(
		&state.process_coordinator,
		&state.process,
	)
	if !detached do state.process_failure = detach_failure
	ksawery.repository_process_close(&state.process)
	if state.conflict_assistance_refresh == .Status && opened {
		if ksawery_workflow_start_conflict_assistance_refresh(commands, .Sequence) do return true
		return ksawery_workflow_finish_conflict_assistance(commands, false)
	}
	return ksawery_workflow_finish_conflict_assistance(
		commands,
		opened && state.conflict_assistance_refresh == .Sequence && state.conflict_selection != 0,
	)
}

@(private)
ksawery_workflow_step_conflict_assistance :: proc(
	commands: ^Command_Context,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.pending != .Conflict_Assistance ||
	   state.conflict_assistance == nil || !state.conflict_assistance.operation.active {
		return false
	}
	if state.conflict_assistance.operation.awaiting_refresh {
		if state.process.state == nil {
			if state.conflict_assistance_refresh == .None {
				if ksawery_workflow_start_conflict_assistance_refresh(commands, .Status) do return true
			}
			return ksawery_workflow_finish_conflict_assistance(commands, false)
		}
		poll, polled := ksawery.repository_process_poll(
			&state.process,
			ksawery_workflow_now(commands),
		)
		if !polled || (poll.state != .Completed && poll.state != .Failed) do return false
		return ksawery_workflow_finish_conflict_assistance_refresh_child(commands, poll)
	}
	_, refresh_ready, operation_failure := ksawery_conflict_assistance_workflow_poll(
		state.conflict_assistance,
		&state.process_coordinator,
		ksawery_workflow_now(commands),
	)
	if operation_failure.code != .None {
		state.failure = .Action_Unavailable
		command_context_set_diagnostic(commands, "Conflict assistance Process evidence was rejected")
		return true
	}
	if refresh_ready {
		if ksawery_workflow_start_conflict_assistance_refresh(commands, .Status) do return true
		return ksawery_workflow_finish_conflict_assistance(commands, false)
	}
	return false
}

@(private)
ksawery_workflow_conflict_assist :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Conflict || state.process.state != nil {
		return {}, {}
	}
	observation, content, copied := ksawery_workflow_conflict_assistance_observation(commands)
	if !copied {
		state.failure = .Presentation_Unavailable
		command_context_set_diagnostic(commands, "Conflict assistance could not copy the selected conflict within bounds")
		return Interaction_Result{changed = true}, {}
	}
	if content != nil do defer delete(content, commands.temporary_allocator)
	if state.conflict_assistance != nil {
		presentation, presented := ksawery_conflict_assistance_workflow_inspect(
			state.conflict_assistance,
		)
		if presented && presentation.tool_available &&
		   state.conflict_assistance.evaluation.request.target == observation.target {
			return ksawery_workflow_begin_conflict_assistance_tool(commands)
		}
	}
	request_id := state.conflict_assistance_request
	selection_generation := state.conflict_assistance_selection_generation
	evaluation: Ksawery_Conflict_Assistance_Evaluation
	failure := ksawery_conflict_assistance_evaluate(
		&evaluation,
		&state.extension_registry,
		&commands.host,
		observation,
		request_id,
		selection_generation,
		commands.host.capability,
		commands.temporary_allocator,
	)
	state.conflict_assistance_request += 1
	if state.conflict_assistance_request == 0 do state.conflict_assistance_request = 1
	state.conflict_assistance_selection_generation += 1
	if state.conflict_assistance_selection_generation == 0 {
		state.conflict_assistance_selection_generation = 1
	}
	if state.conflict_assistance == nil {
		workflow, allocation_error := new(
			Ksawery_Conflict_Assistance_Workflow,
			state.allocator,
		)
		if allocation_error != nil {
			state.failure = .Allocation
			return Interaction_Result{changed = true}, {}
		}
		state.conflict_assistance = workflow
	} else {
		ksawery_conflict_assistance_workflow_close(state.conflict_assistance)
	}
	if !ksawery_conflict_assistance_workflow_compose(
		state.conflict_assistance,
		evaluation,
		failure,
	) {
		state.failure = .Presentation_Unavailable
		command_context_set_diagnostic(commands, "Conflict assistance returned an invalid response")
		return Interaction_Result{changed = true}, {}
	}
	state.position = {}
	state.failure = .None
	switch evaluation.response.kind {
	case .Editor:
		_ = ksawery_conflict_assistance_workflow_choose(
			state.conflict_assistance,
			.Open_Editor,
		)
		return ksawery_workflow_visit_conflict(commands)
	case .Guidance:
		command_context_set_diagnostic(commands, "Conflict assistance guidance is available in Conflict")
	case .External_Tool:
		command_context_set_diagnostic(commands, "Conflict assistance external tool is available")
	case .Declined:
		command_context_set_diagnostic(commands, "No conflict assistance is available; core conflict actions remain available")
	case .Invalid:
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
ksawery_workflow_begin_conflict_resolution :: proc(
	commands: ^Command_Context,
	action: ksawery.Conflict_Resolution_Action,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Conflict || state.process.state != nil do return false
	_, path, selected := ksawery_workflow_selected_conflict(state)
	if !selected {
		state.failure = .Path_Unavailable
		return true
	}
	worktree, editor, inspected := ksawery_workflow_conflict_worktree(commands, path)
	if !inspected {
		state.failure = .Presentation_Unavailable
		command_context_set_diagnostic(commands, "The saved conflict result could not be inspected within bounds")
		return true
	}
	if editor.modified {
		state.failure = .Modified_Buffer
		command_context_set_diagnostic(commands, "Save the conflict buffer before resolving this path")
		return true
	}
	if action == .Mark_Saved_Result && (!worktree.exists || worktree.content != .Text) {
		state.failure = .Action_Unavailable
		command_context_set_diagnostic(commands, "Mark Resolved requires one saved text result")
		return true
	}
	ksawery_workflow_clear_conflict_preparation(state)
	process, started, failure := ksawery.repository_process_start_conflict_resolution_precondition(
		&state.observation,
		&state.sequence,
		state.conflict_selection,
		action,
		worktree,
		editor,
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
	)
	if !started {
		state.failure = failure
		command_context_set_diagnostic(commands, "Checked conflict resolution preconditions are unavailable")
		return true
	}
	recorded, record_failure := ksawery_process_observation_begin(
		&state.process_coordinator,
		&process,
		state.process_coordinator.confirmed_observation,
		{
			kind = .Resolve_Conflict,
			target_kind = .Path,
			title = "Resolve Repository Conflict",
			target = path,
			phase_detail = "Checking saved conflict result",
			checking = true,
		},
		ksawery_workflow_now(commands),
	)
	if !recorded {
		ksawery.repository_process_close(&process)
		state.failure = record_failure
		return true
	}
	state.conflict_action = action
	if len(path) <= len(state.conflict_path) {
		copy(state.conflict_path[:len(path)], transmute([]u8)path)
		state.conflict_path_length = u32(len(path))
	}
	state.process = process
	state.pending = .Conflict_Precondition
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_start_conflict_resolution :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.process.state != nil do return false
	operation := state.next_conflict_resolution
	if operation == ksawery.Conflict_Resolution_Operation_ID(0) do operation = 1
	confirmation: ^ksawery.Conflict_Resolution_Confirmation
	if ksawery.conflict_resolution_action_requires_confirmation(state.conflict_action) {
		confirmed, failure := ksawery.conflict_resolution_confirmation_confirm(
			&state.conflict_confirmation, state.conflict_confirmation.id,
		)
		if !confirmed {
			state.failure = failure
			return true
		}
		confirmation = &state.conflict_confirmation
	}
	request, prepared, failure := ksawery.conflict_resolution_request_prepare(
		state.conflict_precondition, operation, confirmation,
	)
	if !prepared {
		state.failure = failure
		return true
	}
	process, started, start_failure := ksawery.repository_process_start_conflict_resolution(
		&state.sequence,
		state.conflict_precondition,
		request,
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
	)
	if !started {
		state.failure = start_failure
		return true
	}
	attached, attach_failure := ksawery_process_operation_attach_child(
		&state.process_coordinator, &process, ksawery_workflow_now(commands),
	)
	if !attached {
		ksawery.repository_process_close(&process)
		state.failure = attach_failure
		return true
	}
	published, publish_failure := ksawery_process_operation_publish_phase(
		&state.process_coordinator, &process, .Executing,
		"Applying whole-path conflict resolution", true, ksawery_workflow_now(commands),
	)
	if !published {
		_, _ = ksawery_process_operation_detach_child(&state.process_coordinator, &process)
		ksawery.repository_process_close(&process)
		state.failure = publish_failure
		return true
	}
	if state.conflict_result.state != nil do ksawery.conflict_resolution_result_close(&state.conflict_result)
	state.conflict_request = request
	state.process = process
	state.pending = .Conflict_Resolution
	state.next_conflict_resolution = operation + 1
	if state.next_conflict_resolution == ksawery.Conflict_Resolution_Operation_ID(0) {
		state.next_conflict_resolution = 1
	}
	state.view_mode = .Conflict
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_prepare_conflict_confirmation :: proc(
	commands: ^Command_Context,
	precondition: ksawery.Conflict_Resolution_Precondition,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil do return false
	state.conflict_precondition = precondition
	if !ksawery.conflict_resolution_action_requires_confirmation(precondition.action) {
		return ksawery_workflow_start_conflict_resolution(commands)
	}
	id := state.next_conflict_confirmation
	if id == ksawery.Conflict_Resolution_Confirmation_ID(0) do id = 1
	confirmation, prepared, failure := ksawery.conflict_resolution_confirmation_prepare(precondition, id)
	if !prepared {
		state.failure = failure
		return true
	}
	state.conflict_confirmation = confirmation
	state.next_conflict_confirmation = id + 1
	if state.next_conflict_confirmation == ksawery.Conflict_Resolution_Confirmation_ID(0) {
		state.next_conflict_confirmation = 1
	}
	state.view_mode = .Conflict_Confirmation
	state.position = {}
	state.failure = .None
	return true
}

@(private)
dispatch_ksawery_conflict_confirmation_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Conflict_Confirmation || state.process.state != nil {
		return {}, App_Failure{stage = .UI}
	}
	if input.kind == .Key && input.stroke.kind == .Unicode_Scalar &&
	   ((input.stroke.scalar == 'g' && input.stroke.modifiers == {.Control}) ||
	    (input.stroke.scalar == 'q' && input.stroke.modifiers == {})) {
		_ = ksawery_process_observation_finish_without_child(
			&state.process_coordinator, .Cancelled, .Cancelled_Before_Effect,
			"Conflict resolution confirmation cancelled", ksawery_workflow_now(commands),
		)
		ksawery_workflow_clear_conflict_preparation(state)
		state.view_mode = .Conflict
		state.failure = .Cancelled
		return Interaction_Result{changed = true}, {}
	}
	if input.kind == .Key && input.stroke.kind == .Enter && input.stroke.modifiers == {.Control} {
		return Interaction_Result{changed = ksawery_workflow_start_conflict_resolution(commands)}, {}
	}
	return {}, {}
}

@(private)
ksawery_workflow_visit_conflict :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Conflict || state.process.state != nil do return {}, {}
	_, path, selected := ksawery_workflow_selected_conflict(state)
	if !selected do return Interaction_Result{changed = true}, {}
	absolute, path_error := os.join_path(
		{ksawery.repository_context_string(&state.repository), path}, commands.temporary_allocator,
	)
	if path_error != nil {
		state.failure = .Path_Unavailable
		return Interaction_Result{changed = true}, {}
	}
	defer delete(absolute, commands.temporary_allocator)
	opened, open_ok := host_session_request(
		&commands.host,
		.Open_Path,
		0,
		0,
		absolute,
	)
	if !open_ok do return {}, App_Failure{stage = .Session_Publish, host_status = .Failed}
	state.visited = opened.target
	state.resource_return_mode = .Conflict
	state.view_mode = .Resource
	state.failure = .None
	return Interaction_Result{changed = true}, {}
}

@(private)
ksawery_workflow_finish_merge_precondition :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	if state == nil || state.pending != .Merge_Precondition do return {}, false
	precondition, opened, failure := ksawery.repository_process_take_merge_precondition(&state.process)
	if !opened {
		_, _ = ksawery_process_observation_finish(
			&state.process_coordinator, &state.process, false,
			"Repository merge precondition failed", ksawery_workflow_now(commands),
		)
		state.failure = poll.failure if poll.failure != .None else failure
		return ksawery_workflow_sequence_outcome(
			.None, "Repository merge precondition failed",
		), true
	}
	detached, detach_failure := ksawery_process_operation_detach_child(
		&state.process_coordinator, &state.process,
	)
	if !detached {
		state.failure = detach_failure
		return ksawery_workflow_sequence_outcome(), true
	}
	_, _ = ksawery_process_operation_publish_phase(
		&state.process_coordinator, nil, .Checking, "Waiting for exact merge confirmation",
		false, ksawery_workflow_now(commands),
	)
	state.merge_precondition = precondition
	return ksawery_workflow_sequence_outcome(.Prepare_Merge_Confirmation), true
}

@(private)
ksawery_workflow_finish_conflict_precondition :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	if state == nil || state.pending != .Conflict_Precondition do return {}, false
	precondition, opened, failure :=
		ksawery.repository_process_take_conflict_resolution_precondition(&state.process)
	if !opened {
		_, _ = ksawery_process_observation_finish(
			&state.process_coordinator, &state.process, false,
			"Conflict resolution precondition failed", ksawery_workflow_now(commands),
		)
		state.failure = poll.failure if poll.failure != .None else failure
		return ksawery_workflow_sequence_outcome(
			.None, "Conflict resolution precondition failed",
		), true
	}
	detached, detach_failure := ksawery_process_operation_detach_child(
		&state.process_coordinator, &state.process,
	)
	if !detached {
		state.failure = detach_failure
		return ksawery_workflow_sequence_outcome(), true
	}
	_, _ = ksawery_process_operation_publish_phase(
		&state.process_coordinator, nil, .Checking,
		"Waiting for conflict resolution confirmation", false, ksawery_workflow_now(commands),
	)
	state.conflict_precondition = precondition
	return ksawery_workflow_sequence_outcome(.Prepare_Conflict_Confirmation), true
}

@(private)
ksawery_workflow_finish_sequence_mutation_process :: proc(
	commands: ^Command_Context,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	if state == nil || (state.pending != .Merge && state.pending != .Rebase &&
	   state.pending != .Conflict_Resolution) {
		return {}, false
	}
	conflict_mutation := state.pending == .Conflict_Resolution
	mutation_kind := ksawery.Sequence_Kind.Merge
	if state.pending == .Rebase do mutation_kind = .Rebase
	if conflict_mutation {
		sequence, described := ksawery.sequence_observation_descriptor(&state.sequence)
		if described do mutation_kind = sequence.kind
	}
	opened := false
	failure := ksawery.Failure_Code.None
	succeeded := false
	if state.pending == .Merge {
		result: ksawery.Merge_Result
		result, opened, failure = ksawery.repository_process_take_merge(
			&state.process, commands.persistent_allocator,
		)
		if opened {
			if state.merge_result.state != nil do ksawery.merge_result_close(&state.merge_result)
			state.merge_result = result
			descriptor, described := ksawery.merge_result_descriptor(&state.merge_result)
			succeeded = described && descriptor.process_succeeded
		}
	} else if state.pending == .Rebase {
		result: ksawery.Rebase_Result
		result, opened, failure = ksawery.repository_process_take_rebase(
			&state.process, commands.persistent_allocator,
		)
		if opened {
			if state.rebase_result.state != nil do ksawery.rebase_result_close(&state.rebase_result)
			state.rebase_result = result
			descriptor, described := ksawery.rebase_result_descriptor(&state.rebase_result)
			succeeded = described && descriptor.process_succeeded
		}
	} else {
		stage_zero, stage_observed, stage_failure :=
			ksawery.repository_process_take_conflict_stage_zero(&state.process)
		result: ksawery.Conflict_Resolution_Result
		result, opened, failure = ksawery.repository_process_take_conflict_resolution(
			&state.process, commands.persistent_allocator,
		)
		if opened {
			if state.conflict_result.state != nil do ksawery.conflict_resolution_result_close(&state.conflict_result)
			state.conflict_result = result
			descriptor, described := ksawery.conflict_resolution_result_descriptor(&state.conflict_result)
			succeeded = described && descriptor.process_succeeded && stage_observed
			if stage_observed {
				state.conflict_stage_zero = stage_zero
			} else if descriptor.process_succeeded {
				failure = stage_failure
			}
		}
	}
	effect, prepared, prepare_failure := ksawery_process_operation_prepare_refresh(
		&state.process_coordinator,
		&state.process,
		"Refreshing Status and Sequence after sequence mutation",
		ksawery_workflow_now(commands),
	)
	if !prepared {
		_, _ = ksawery_process_observation_finish(
			&state.process_coordinator, &state.process, false,
			"Repository sequence mutation could not refresh", ksawery_workflow_now(commands),
		)
		state.failure = prepare_failure
		return ksawery_workflow_sequence_outcome(), true
	}
	state.operation_effect = effect
	state.operation_verification = succeeded ? .Unavailable : .Known_Failure
	state.failure = failure if !opened else .None
	state.sequence_mutation_refresh = true
	state.sequence_mutation_conflict = conflict_mutation
	state.sequence_mutation_kind = mutation_kind
	state.view_mode = .Status
	return ksawery_workflow_sequence_outcome(.Start_Mutation_Refresh), true
}

@(private)
ksawery_workflow_verify_sequence_mutation :: proc(
	state: ^Ksawery_Workflow_State,
) -> Ksawery_Repository_Verification_State {
	if state == nil || state.refs.state == nil || state.sequence.state == nil do return .Unavailable
	if !state.sequence_mutation_conflict && state.sequence_mutation_kind == .Merge &&
	   state.merge_result.state != nil {
		verified, failure := ksawery.merge_result_verify(&state.merge_result, &state.refs, &state.sequence)
		if !verified do return .Mismatch
		descriptor, described := ksawery.merge_result_descriptor(&state.merge_result)
		if !described do return .Mismatch
		if descriptor.outcome == .Fast_Forwarded || descriptor.outcome == .Merge_Commit_Created ||
		   descriptor.outcome == .Continued || descriptor.outcome == .Aborted {
			return .Verified
		}
		if descriptor.outcome == .Paused_Conflict || descriptor.outcome == .Known_Failure ||
		   failure == .Process_Failed {
			return .Known_Failure
		}
		return .Mismatch
	}
	if !state.sequence_mutation_conflict && state.sequence_mutation_kind == .Rebase &&
	   state.rebase_result.state != nil {
		verified, failure := ksawery.rebase_result_verify(&state.rebase_result, &state.refs, &state.sequence)
		if !verified do return .Mismatch
		descriptor, described := ksawery.rebase_result_descriptor(&state.rebase_result)
		if !described do return .Mismatch
		if descriptor.outcome == .Replayed || descriptor.outcome == .Advanced ||
		   descriptor.outcome == .Skipped || descriptor.outcome == .Aborted {
			return .Verified
		}
		if descriptor.outcome == .Paused_Conflict || descriptor.outcome == .Known_Failure ||
		   failure == .Process_Failed {
			return .Known_Failure
		}
		return .Mismatch
	}
	if !state.sequence_mutation_conflict &&
	   (state.sequence_mutation_kind == .Cherry_Pick || state.sequence_mutation_kind == .Revert) {
		return ksawery_workflow_verify_revision_sequence(state)
	}
	if !state.sequence_mutation_conflict && state.sequence_mutation_kind == .Bisect &&
	   state.bisect_result.state != nil {
		verified, failure := ksawery.bisect_result_verify(&state.bisect_result, &state.refs, &state.sequence)
		if !verified do return .Mismatch
		descriptor, described := ksawery.bisect_result_descriptor(&state.bisect_result)
		if !described do return .Mismatch
		state.bisect_progress = descriptor.progress
		if descriptor.outcome == .Started || descriptor.outcome == .Advanced ||
		   descriptor.outcome == .Found_First_Bad || descriptor.outcome == .Reset {
			return .Verified
		}
		if descriptor.outcome == .Known_Failure || failure == .Process_Failed do return .Known_Failure
		return .Mismatch
	}
	if state.sequence_mutation_conflict && state.conflict_result.state != nil {
		_, described := ksawery.conflict_resolution_result_descriptor(&state.conflict_result)
		if !described do return .Mismatch
		fresh_descriptor, fresh_described := ksawery.sequence_observation_descriptor(&state.sequence)
		if !fresh_described || fresh_descriptor.kind != state.sequence_mutation_kind ||
		   fresh_descriptor.state == .Inactive {
			return .Mismatch
		}
		stage := ksawery.Conflict_Stage_Zero{state = .Still_Unmerged}
		still_unmerged := false
		wanted_path := string(state.conflict_path[:state.conflict_path_length])
		for index in 0 ..< fresh_descriptor.conflict_count {
			candidate, found := ksawery.sequence_observation_conflict(&state.sequence, index)
			if !found do return .Mismatch
			candidate_path, copied := ksawery.sequence_observation_conflict_path(&state.sequence, candidate)
			if copied && candidate_path == wanted_path {
				still_unmerged = true
				break
			}
		}
		if !still_unmerged {
			if !ksawery.conflict_stage_zero_is_valid(state.conflict_stage_zero) do return .Mismatch
			stage = state.conflict_stage_zero
		}
		fresh := ksawery.Sequence_Target {
			generation = fresh_descriptor.generation,
			fingerprint = fresh_descriptor.fingerprint,
		}
		verified, failure := ksawery.conflict_resolution_result_verify(&state.conflict_result, stage, fresh)
		if !verified do return .Mismatch
		result, result_described := ksawery.conflict_resolution_result_descriptor(&state.conflict_result)
		if !result_described do return .Mismatch
		if result.outcome == .Resolved || result.outcome == .Deleted do return .Verified
		if result.outcome == .Still_Unmerged || failure == .Process_Failed do return .Known_Failure
		return .Mismatch
	}
	return .Unavailable
}

@(private)
ksawery_workflow_finish_sequence_mutation_refresh :: proc(
	commands: ^Command_Context,
	opened: bool,
) {
	state := commands.ksawery_workflow
	if state == nil || !state.sequence_mutation_refresh do return
	mutation_kind := state.sequence_mutation_kind
	verification := state.operation_verification
	if !opened do verification = .Unavailable
	if opened do verification = ksawery_workflow_verify_sequence_mutation(state)
	resolution, resolved, failure := ksawery_process_operation_resolve(
		&state.process_coordinator,
		state.operation_effect,
		verification,
		state.generation if opened else ksawery.Observation_Generation(0),
		true,
	)
	if resolved {
		message := "Repository sequence workflow refreshed"
		if state.sequence_mutation_kind == .Merge do message = "Repository merge workflow refreshed"
		if state.sequence_mutation_kind == .Rebase do message = "Repository rebase workflow refreshed"
		if state.sequence_mutation_kind == .Cherry_Pick do message = "Repository cherry-pick workflow refreshed"
		if state.sequence_mutation_kind == .Revert do message = "Repository revert workflow refreshed"
		if state.sequence_mutation_kind == .Bisect do message = "Repository manual bisect workflow refreshed"
		if resolution.lifecycle == .Failed do message = "Repository sequence workflow stopped in known repository state"
		if resolution.lifecycle == .Indeterminate do message = "Repository sequence workflow outcome is indeterminate"
		finished, finish_failure := ksawery_process_operation_finish_resolution(
			&state.process_coordinator, nil, resolution, message, ksawery_workflow_now(commands),
		)
		if !finished do state.process_failure = finish_failure
	} else {
		state.process_failure = failure
	}
	ksawery_workflow_clear_operation_resolution(state)
	state.sequence_mutation_refresh = false
	state.sequence_mutation_conflict = false
	state.sequence_mutation_kind = .Invalid
	state.sequence_mutation_history_refresh = false
	if opened {
		descriptor, described := ksawery.sequence_observation_descriptor(&state.sequence)
		if described && descriptor.state == .Inactive &&
		   (mutation_kind == .Cherry_Pick || mutation_kind == .Revert) {
			ksawery_workflow_clear_revision_sequence_selection(state)
		}
		if described && descriptor.state == .Inactive && mutation_kind == .Bisect {
			ksawery_workflow_clear_bisect_preparation(state, true)
		}
		state.view_mode = .Sequence if described && descriptor.state != .Inactive else .Status
		state.failure = .None
		command_context_set_diagnostic(commands, "Repository sequence workflow refreshed")
	} else {
		state.failure = .Process_Failed
		command_context_set_diagnostic(commands, "Repository sequence refresh failed after mutation")
	}
}

@(private)
ksawery_merge_confirmation_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || viewport_items == 0 || allocator.procedure == nil ||
	   !ksawery.merge_precondition_is_valid(state.merge_precondition) {
		return nil, nil, false
	}
	rows, rows_error := make([]ui.List_Item_Definition, 9, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, len(rows) * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {delete(rows, allocator); return nil, nil, false}
	write := 0
	precondition := state.merge_precondition
	_ = ksawery_append_presented_label(rows, storage, &write, 0xDA00_0000_0000_0001,
		"Ksawery Merge Confirmation", true, {surface = .Sequence, subject = .Section})
	_ = ksawery_append_presented_label(rows, storage, &write, 0xDA00_0000_0000_0002,
		fmt.tprintf("Action: %v", precondition.action), true, {surface = .Sequence, subject = .Operation})
	_ = ksawery_append_presented_label(rows, storage, &write, 0xDA00_0000_0000_0003,
		fmt.tprintf("Current: %s", ksawery.revision_identity_string(&precondition.head.object)), true,
		{surface = .Sequence, subject = .Revision})
	_ = ksawery_append_presented_label(rows, storage, &write, 0xDA00_0000_0000_0004,
		fmt.tprintf("Target: %s", ksawery.revision_identity_string(&precondition.target_revision)), true,
		{surface = .Sequence, subject = .Revision})
	if precondition.action == .Start {
		_ = ksawery_append_presented_label(rows, storage, &write, 0xDA00_0000_0000_0005,
			fmt.tprintf("Policy: %v", precondition.policy), true, {surface = .Sequence, subject = .Operation})
	}
	_ = ksawery_append_presented_label(rows, storage, &write, 0xDA00_0000_0000_0006,
		"C-Enter confirms this exact action; C-g cancels.", false,
		{surface = .Sequence, subject = .Operation, destructive = precondition.action == .Abort})
	definitions = rows[:write]
	state.position = {presentation_generation = 1, selection_owner = .View, current_item = i32(write - 1),
		first_visible_item = 0, viewport_items = min(viewport_items, u32(write))}
	return definitions, storage, true
}

@(private)
ksawery_conflict_confirmation_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || viewport_items == 0 || allocator.procedure == nil ||
	   !ksawery.conflict_resolution_precondition_is_valid(state.conflict_precondition) {
		return nil, nil, false
	}
	rows, rows_error := make([]ui.List_Item_Definition, 7, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, len(rows) * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {delete(rows, allocator); return nil, nil, false}
	write := 0
	precondition := state.conflict_precondition
	_, path, _ := ksawery_workflow_selected_conflict(state)
	_ = ksawery_append_presented_label(rows, storage, &write, 0xDB00_0000_0000_0001,
		"Ksawery Conflict Confirmation", true, {surface = .Conflict, subject = .Section})
	_ = ksawery_append_presented_label(rows, storage, &write, 0xDB00_0000_0000_0002,
		fmt.tprintf("Path: %s", path), true, {surface = .Conflict, subject = .Conflict})
	_ = ksawery_append_presented_label(rows, storage, &write, 0xDB00_0000_0000_0003,
		fmt.tprintf("Action: %v", precondition.action), true,
		{surface = .Conflict, subject = .Operation, destructive = true})
	_ = ksawery_append_presented_label(rows, storage, &write, 0xDB00_0000_0000_0004,
		"C-Enter confirms this exact whole-path replacement; C-g cancels.", false,
		{surface = .Conflict, subject = .Operation, destructive = true})
	definitions = rows[:write]
	state.position = {presentation_generation = 1, selection_owner = .View, current_item = i32(write - 1),
		first_visible_item = 0, viewport_items = min(viewport_items, u32(write))}
	return definitions, storage, true
}
