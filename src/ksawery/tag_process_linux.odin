// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery

import "core:os"

@(private)
Tag_Process_Phase :: enum u8 {
	None,
	Check_Target,
	Check_Destination,
	Check_Operation,
	Mutate,
}

/* repository_process_start_tag rechecks live repository truth before one confirmed local tag mutation. */
repository_process_start_tag :: proc(
	status: ^Status_Observation,
	refs: ^Ref_Observation,
	request: Tag_Request,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil do return {}, false, .Invalid_Request
	current, failure := tag_request_revalidate(status, refs, request)
	if !current do return {}, false, failure
	process_request := Process_Request {
		kind = .Tag_Local,
		repository = request.precondition.repository,
		limits = request.limits,
	}
	if !process_request_is_valid(process_request) do return {}, false, .Invalid_Request
	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = process_request
	state.tag = request
	state.tag_phase = .Check_Target
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
	target := request.precondition.intent.target.name
	name := ref_name_string(&target)
	if len(name) == 0 {
		repository_process_data_destroy(state)
		return {}, false, .Invalid_Request
	}
	state.command = {"git", "rev-parse", "--verify", "--quiet", name, "", "", "", "", ""}
	state.command_count = 5
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
repository_process_advance_tag :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.request.kind != .Tag_Local || state.tag_phase == .None ||
	   !tag_request_is_valid(state.tag) {
		return .Invalid_Request
	}
	intent := state.tag.precondition.intent
	switch state.tag_phase {
	case .Check_Target:
		target_object := intent.target.object
		if state.exit_status != 0 || !repository_process_tag_output_matches(
			state,
			revision_identity_string(&target_object),
		) {
			return .Stale_Observation
		}
		if intent.operation == .Create do return repository_process_start_tag_destination_check(state)
		if intent.operation == .Delete {
			state.tag_operation_marker = 0
			return repository_process_start_tag_operation_check(state)
		}
		return .Invalid_Request
	case .Check_Destination:
		if state.exit_status == 0 do return .Target_Duplicate
		if state.exit_status != 1 || len(state.output) != 0 do return .Process_Failed
		state.tag_operation_marker = 0
		return repository_process_start_tag_operation_check(state)
	case .Check_Operation:
		if state.exit_status != 0 do return .Process_Failed
		active, inspected := repository_process_tag_operation_is_active(state)
		if !inspected do return .Parse
		if active do return .Action_Unavailable
		state.tag_operation_marker += 1
		if int(state.tag_operation_marker) < len(COMMIT_OPERATION_MARKERS) {
			return repository_process_start_tag_operation_check(state)
		}
		return repository_process_start_tag_mutation(state)
	case .Mutate:
		if state.exit_status != 0 do return .Process_Failed
		state.tag_phase = .None
		state.state = .Completed
		return .None
	case .None:
		return .Invalid_Request
	}
	return .Invalid_Request
}

@(private)
repository_process_start_tag_destination_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.tag_phase != .Check_Target ||
	   state.tag.precondition.intent.operation != .Create {
		return .Invalid_Request
	}
	repository_process_tag_reset_child(state)
	destination := state.tag.precondition.intent.name.reference
	name := ref_name_string(&destination)
	if len(name) == 0 do return .Invalid_Request
	state.command = {"git", "show-ref", "--verify", "--quiet", "--", name, "", "", "", ""}
	state.command_count = 6
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	state.tag_phase = .Check_Destination
	return .None
}

@(private)
repository_process_start_tag_operation_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.request.kind != .Tag_Local ||
	   (state.tag_phase != .Check_Target && state.tag_phase != .Check_Destination &&
	    state.tag_phase != .Check_Operation) ||
	   int(state.tag_operation_marker) >= len(COMMIT_OPERATION_MARKERS) {
		return .Invalid_Request
	}
	repository_process_tag_reset_child(state)
	markers := COMMIT_OPERATION_MARKERS
	state.command = {
		"git", "rev-parse", "--git-path", markers[int(state.tag_operation_marker)],
		"", "", "", "", "", "",
	}
	state.command_count = 4
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	state.tag_phase = .Check_Operation
	return .None
}

@(private)
repository_process_start_tag_mutation :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.request.kind != .Tag_Local || state.tag_phase != .Check_Operation ||
	   int(state.tag_operation_marker) != len(COMMIT_OPERATION_MARKERS) ||
	   !tag_request_is_valid(state.tag) {
		return .Invalid_Request
	}
	repository_process_tag_reset_child(state)
	intent := state.tag.precondition.intent
	switch intent.operation {
	case .Create:
		name := local_tag_name_string(&intent.name)
		target_object := intent.target.object
		target := revision_identity_string(&target_object)
		if len(name) == 0 || len(target) == 0 do return .Invalid_Request
		state.command = {"git", "tag", "--", name, target, "", "", "", "", ""}
		state.command_count = 5
	case .Delete:
		name, available := repository_process_tag_selected_short_name(state)
		if !available do return .Invalid_Request
		state.command = {"git", "tag", "-d", "--", name, "", "", "", "", ""}
		state.command_count = 5
	case .Invalid:
		return .Invalid_Request
	}
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	state.tag_phase = .Mutate
	state.tag_started = true
	return .None
}

@(private)
repository_process_tag_selected_short_name :: proc(state: ^Repository_Process_Data) -> (string, bool) {
	if state == nil do return "", false
	name := &state.tag.precondition.intent.target.name
	full := ref_name_string(name)
	prefix := "refs/tags/"
	if len(full) <= len(prefix) || full[:len(prefix)] != prefix do return "", false
	return full[len(prefix):], true
}

@(private)
repository_process_tag_output_matches :: proc(state: ^Repository_Process_Data, expected: string) -> bool {
	return state != nil && len(expected) > 0 && len(state.output) == len(expected) + 1 &&
	       state.output[len(state.output) - 1] == '\n' && string(state.output[:len(expected)]) == expected
}

@(private)
repository_process_tag_operation_is_active :: proc(state: ^Repository_Process_Data) -> (active, inspected: bool) {
	if state == nil || state.tag_phase != .Check_Operation ||
	   int(state.tag_operation_marker) >= len(COMMIT_OPERATION_MARKERS) ||
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
repository_process_tag_exit_is_expected :: proc(state: ^Repository_Process_Data, exit_status: i32) -> bool {
	return state != nil && state.request.kind == .Tag_Local && exit_status == 1 &&
	       state.tag_phase == .Check_Destination
}

@(private)
repository_process_tag_reset_child :: proc(state: ^Repository_Process_Data) {
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

/* repository_process_take_tag copies one started or pre-start-cancelled local tag outcome. */
repository_process_take_tag :: proc(
	process: ^Repository_Process,
	allocator := context.allocator,
) -> (Tag_Result, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || (state.state != .Completed && state.state != .Failed) ||
	   state.request.kind != .Tag_Local || !tag_request_is_valid(state.tag) {
		return {}, false, .Invalid_Request
	}
	if !state.tag_started && state.failure != .Cancelled do return {}, false, state.failure
	return tag_result_open(
		state.tag,
		state.tag_started,
		state.exit_status,
		state.output[:],
		state.diagnostic[:],
		state.failure,
		allocator,
	)
}
