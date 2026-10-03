// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery

import "core:os"

@(private)
Branch_Process_Phase :: enum u8 {
	None,
	Check_Head_Name,
	Check_Head_Object,
	Check_Target,
	Check_Destination,
	Check_Status,
	Check_Merged,
	Check_Operation,
	Mutate,
}

/* repository_process_start_branch rechecks live repository truth before one confirmed local branch mutation. */
repository_process_start_branch :: proc(
	status: ^Status_Observation,
	refs: ^Ref_Observation,
	editor: Branch_Editor_State,
	request: Branch_Request,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil do return {}, false, .Invalid_Request
	current, failure := branch_request_revalidate(status, refs, editor, request)
	if !current do return {}, false, failure
	process_request := Process_Request {
		kind = .Branch_Local,
		repository = request.precondition.repository,
		limits = request.limits,
	}
	if !process_request_is_valid(process_request) do return {}, false, .Invalid_Request
	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = process_request
	state.branch = request
	state.branch_phase = .Check_Head_Name
	state.output_limit = request.limits.stdout_bytes
	state.output, allocation_error = make(
		[dynamic]u8,
		0,
		int(min(state.output_limit, 64 * KIBIBYTE)),
		allocator,
	)
	if allocation_error == nil {
		state.diagnostic, allocation_error = make(
			[dynamic]u8,
			0,
			int(min(request.limits.diagnostic_bytes, 16 * KIBIBYTE)),
			allocator,
		)
	}
	if allocation_error != nil {
		repository_process_data_destroy(state)
		return {}, false, .Allocation
	}
	state.command = {"git", "symbolic-ref", "--quiet", "HEAD", "", "", "", "", "", ""}
	state.command_count = 4
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None {
		repository_process_data_destroy(state)
		return {}, false, state.failure
	}
	state.deadline_ns = now_ns + request.limits.timeout_nanoseconds
	state.state = .Running
	return Repository_Process{state = state}, true, .None
}

@(private)
repository_process_advance_branch :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.request.kind != .Branch_Local || state.branch_phase == .None ||
	   !branch_request_is_valid(state.branch) {
		return .Invalid_Request
	}
	intent := state.branch.precondition.intent
	switch state.branch_phase {
	case .Check_Head_Name:
		head_name := state.branch.precondition.head.branch.name
		if state.exit_status != 0 || !repository_process_branch_output_matches(
			state,
			ref_name_string(&head_name),
		) {
			return .Stale_Observation
		}
		return repository_process_start_branch_head_object_check(state)
	case .Check_Head_Object:
		head_object := state.branch.precondition.head.object
		if state.exit_status != 0 || !repository_process_branch_output_matches(
			state,
			revision_identity_string(&head_object),
		) {
			return .Stale_Observation
		}
		switch intent.operation {
		case .Create:
			return repository_process_start_branch_destination_check(state)
		case .Switch, .Rename, .Delete:
			return repository_process_start_branch_target_check(state)
		case .Invalid:
			return .Invalid_Request
		}
	case .Check_Target:
		target_object := intent.selected.object
		if state.exit_status != 0 || !repository_process_branch_output_matches(
			state,
			revision_identity_string(&target_object),
		) {
			return .Stale_Observation
		}
		switch intent.operation {
		case .Switch:
			return repository_process_start_branch_status_check(state)
		case .Rename:
			return repository_process_start_branch_destination_check(state)
		case .Delete:
			return repository_process_start_branch_merged_check(state)
		case .Create, .Invalid:
			return .Invalid_Request
		}
	case .Check_Destination:
		if state.exit_status == 0 do return .Target_Duplicate
		if state.exit_status != 1 || len(state.output) != 0 do return .Process_Failed
		state.branch_operation_marker = 0
		return repository_process_start_branch_operation_check(state)
	case .Check_Status:
		if state.exit_status != 0 do return .Process_Failed
		if len(state.output) != 0 do return .Action_Unavailable
		state.branch_operation_marker = 0
		return repository_process_start_branch_operation_check(state)
	case .Check_Merged:
		if state.exit_status == 1 do return .Action_Unavailable
		if state.exit_status != 0 do return .Process_Failed
		state.branch_operation_marker = 0
		return repository_process_start_branch_operation_check(state)
	case .Check_Operation:
		if state.exit_status != 0 do return .Process_Failed
		active, inspected := repository_process_branch_operation_is_active(state)
		if !inspected do return .Parse
		if active do return .Action_Unavailable
		state.branch_operation_marker += 1
		if int(state.branch_operation_marker) < len(COMMIT_OPERATION_MARKERS) {
			return repository_process_start_branch_operation_check(state)
		}
		return repository_process_start_branch_mutation(state)
	case .Mutate:
		if state.exit_status != 0 do return .Process_Failed
		state.branch_phase = .None
		state.state = .Completed
		return .None
	case .None:
		return .Invalid_Request
	}
	return .Invalid_Request
}

@(private)
repository_process_start_branch_head_object_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.branch_phase != .Check_Head_Name do return .Invalid_Request
	repository_process_branch_reset_child(state)
	state.command = {"git", "rev-parse", "--verify", "--quiet", "HEAD^{commit}", "", "", "", "", ""}
	state.command_count = 5
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	state.branch_phase = .Check_Head_Object
	return .None
}

@(private)
repository_process_start_branch_target_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.branch_phase != .Check_Head_Object do return .Invalid_Request
	repository_process_branch_reset_child(state)
	target := state.branch.precondition.intent.selected.name
	argument, assigned := repository_process_branch_revision_argument(state, &target)
	if !assigned do return .Invalid_Request
	state.command = {"git", "rev-parse", "--verify", "--quiet", argument, "", "", "", "", ""}
	state.command_count = 5
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	state.branch_phase = .Check_Target
	return .None
}

@(private)
repository_process_start_branch_destination_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil ||
	   (state.branch_phase != .Check_Head_Object && state.branch_phase != .Check_Target) {
		return .Invalid_Request
	}
	repository_process_branch_reset_child(state)
	destination := state.branch.precondition.intent.name.reference
	name := ref_name_string(&destination)
	if len(name) == 0 do return .Invalid_Request
	state.command = {"git", "show-ref", "--verify", "--quiet", "--", name, "", "", "", ""}
	state.command_count = 6
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	state.branch_phase = .Check_Destination
	return .None
}

@(private)
repository_process_start_branch_status_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.branch_phase != .Check_Target ||
	   state.branch.precondition.intent.operation != .Switch {
		return .Invalid_Request
	}
	repository_process_branch_reset_child(state)
	state.command = {"git", "status", "--porcelain=v2", "-z", "--untracked-files=all", "", "", "", "", ""}
	state.command_count = 5
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	state.branch_phase = .Check_Status
	return .None
}

@(private)
repository_process_start_branch_merged_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.branch_phase != .Check_Target ||
	   state.branch.precondition.intent.operation != .Delete {
		return .Invalid_Request
	}
	repository_process_branch_reset_child(state)
	target := state.branch.precondition.intent.selected.object
	head := state.branch.precondition.head.object
	target_text := revision_identity_string(&target)
	head_text := revision_identity_string(&head)
	if len(target_text) == 0 || len(head_text) == 0 do return .Invalid_Request
	state.command = {"git", "merge-base", "--is-ancestor", target_text, head_text, "", "", "", "", ""}
	state.command_count = 5
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	state.branch_phase = .Check_Merged
	return .None
}

@(private)
repository_process_start_branch_operation_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.request.kind != .Branch_Local ||
	   (state.branch_phase != .Check_Destination && state.branch_phase != .Check_Status &&
	    state.branch_phase != .Check_Merged && state.branch_phase != .Check_Operation) ||
	   int(state.branch_operation_marker) >= len(COMMIT_OPERATION_MARKERS) {
		return .Invalid_Request
	}
	repository_process_branch_reset_child(state)
	markers := COMMIT_OPERATION_MARKERS
	state.command = {
		"git", "rev-parse", "--git-path", markers[int(state.branch_operation_marker)],
		"", "", "", "", "", "",
	}
	state.command_count = 4
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	state.branch_phase = .Check_Operation
	return .None
}

@(private)
repository_process_start_branch_mutation :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.request.kind != .Branch_Local || state.branch_phase != .Check_Operation ||
	   int(state.branch_operation_marker) != len(COMMIT_OPERATION_MARKERS) ||
	   !branch_request_is_valid(state.branch) {
		return .Invalid_Request
	}
	repository_process_branch_reset_child(state)
	intent := state.branch.precondition.intent
	switch intent.operation {
	case .Create:
		name := local_branch_name_string(&intent.name)
		head_object := state.branch.precondition.head.object
		head_text := revision_identity_string(&head_object)
		if len(name) == 0 || len(head_text) == 0 do return .Invalid_Request
		state.command = {"git", "branch", "--", name, head_text, "", "", "", "", ""}
		state.command_count = 5
	case .Switch:
		name, available := repository_process_branch_selected_short_name(state)
		if !available do return .Invalid_Request
		state.command = {"git", "switch", "--no-guess", "--", name, "", "", "", "", ""}
		state.command_count = 5
	case .Rename:
		old_name, available := repository_process_branch_selected_short_name(state)
		new_name := local_branch_name_string(&intent.name)
		if !available || len(new_name) == 0 do return .Invalid_Request
		state.command = {"git", "branch", "-m", "--", old_name, new_name, "", "", "", ""}
		state.command_count = 6
	case .Delete:
		name, available := repository_process_branch_selected_short_name(state)
		if !available do return .Invalid_Request
		state.command = {"git", "branch", "-d", "--", name, "", "", "", "", ""}
		state.command_count = 5
	case .Invalid:
		return .Invalid_Request
	}
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	state.branch_phase = .Mutate
	state.branch_started = true
	return .None
}

@(private)
repository_process_branch_revision_argument :: proc(
	state: ^Repository_Process_Data,
	name: ^Ref_Name,
) -> (string, bool) {
	if state == nil || name == nil || !ref_name_is_valid(name^) do return "", false
	text := ref_name_string(name)
	suffix := "^{commit}"
	required := len(text) + len(suffix)
	if len(text) == 0 || required > len(state.branch_argument) do return "", false
	state.branch_argument = {}
	copy(state.branch_argument[:len(text)], transmute([]u8)text)
	copy(state.branch_argument[len(text):required], transmute([]u8)suffix)
	return string(state.branch_argument[:required]), true
}

@(private)
repository_process_branch_selected_short_name :: proc(state: ^Repository_Process_Data) -> (string, bool) {
	if state == nil do return "", false
	name := state.branch.precondition.intent.selected.name
	full := ref_name_string(&name)
	prefix := "refs/heads/"
	if len(full) <= len(prefix) || full[:len(prefix)] != prefix do return "", false
	return full[len(prefix):], true
}

@(private)
repository_process_branch_output_matches :: proc(state: ^Repository_Process_Data, expected: string) -> bool {
	return state != nil && len(expected) > 0 && len(state.output) == len(expected) + 1 &&
	       state.output[len(state.output) - 1] == '\n' && string(state.output[:len(expected)]) == expected
}

@(private)
repository_process_branch_operation_is_active :: proc(state: ^Repository_Process_Data) -> (active, inspected: bool) {
	if state == nil || state.branch_phase != .Check_Operation ||
	   int(state.branch_operation_marker) >= len(COMMIT_OPERATION_MARKERS) ||
	   len(state.output) < 2 || state.output[len(state.output) - 1] != '\n' {
		return false, false
	}
	marker := string(state.output[:len(state.output) - 1])
	if len(marker) == 0 do return false, false
	repository := state.request.repository
	path := marker
	owned_path: string
	if !os.is_absolute_path(path) {
		resolved_path, path_error := os.join_path({repository_context_string(&repository), marker}, state.allocator)
		if path_error != nil do return false, false
		path = resolved_path
		owned_path = resolved_path
	}
	defer if len(owned_path) > 0 do delete(owned_path, state.allocator)
	return os.exists(path), true
}

@(private)
repository_process_branch_exit_is_expected :: proc(state: ^Repository_Process_Data, exit_status: i32) -> bool {
	return state != nil && state.request.kind == .Branch_Local && exit_status == 1 &&
	       (state.branch_phase == .Check_Destination || state.branch_phase == .Check_Merged)
}

@(private)
repository_process_branch_reset_child :: proc(state: ^Repository_Process_Data) {
	if state == nil do return
	local_child_close(&state.child)
	state.child = {}
	state.stdout_closed = false
	state.stderr_closed = false
	state.stdin_closed = false
	state.exit_status = 0
	clear(&state.input)
	clear(&state.output)
	clear(&state.diagnostic)
}

/* repository_process_take_branch copies one started or pre-start-cancelled local branch outcome. */
repository_process_take_branch :: proc(
	process: ^Repository_Process,
	allocator := context.allocator,
) -> (Branch_Result, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || (state.state != .Completed && state.state != .Failed) ||
	   state.request.kind != .Branch_Local || !branch_request_is_valid(state.branch) {
		return {}, false, .Invalid_Request
	}
	if !state.branch_started && state.failure != .Cancelled do return {}, false, state.failure
	return branch_result_open(
		state.branch,
		state.branch_started,
		state.exit_status,
		state.output[:],
		state.diagnostic[:],
		state.failure,
		allocator,
	)
}
