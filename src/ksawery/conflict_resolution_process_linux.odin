// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery

@(private)
Conflict_Resolution_Process_Phase :: enum u8 {
	None,
	Prepare_Worktree,
	Check_Conflict,
	Check_Worktree,
	Mutate,
	Stage_Result,
	Verify_Result,
}

/* repository_process_start_conflict_resolution_precondition binds saved worktree truth to one conflict. */
repository_process_start_conflict_resolution_precondition :: proc(
	status: ^Status_Observation,
	observation: ^Sequence_Observation,
	conflict: Conflict_ID,
	action: Conflict_Resolution_Action,
	worktree: Conflict_Worktree_Result,
	editor: Conflict_Editor_State,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil || action == .Invalid ||
	   !conflict_editor_state_is_valid(editor, worktree) {
		return {}, false, .Invalid_Request
	}
	status_descriptor, status_described := status_observation_descriptor(status)
	sequence_descriptor, sequence_described := sequence_observation_descriptor(observation)
	if !status_described || !sequence_described ||
	   status_descriptor.repository != sequence_descriptor.repository ||
	   sequence_descriptor.kind != .Merge || sequence_descriptor.state != .Conflicted {
		return {}, false, .Stale_Observation
	}
	target, found := repository_process_conflict_target_by_id(observation, conflict)
	if !found do return {}, false, .Path_Unavailable
	provisional_worktree := worktree
	if provisional_worktree.exists && provisional_worktree.git_object == {} {
		for stage in target.stages {
			if stage.available {
				provisional_worktree.git_object = stage.object
				break
			}
		}
	}
	if !conflict_worktree_result_is_valid(provisional_worktree) do return {}, false, .Invalid_Request
	path, copied := sequence_observation_conflict_path(observation, target)
	if !copied || len(path) == 0 do return {}, false, .Path_Unavailable
	_, unmerged_paths, counted := repository_process_merge_status_counts(status)
	if !counted do return {}, false, .Stale_Observation
	sequence := Sequence_Target {
		generation = sequence_descriptor.generation,
		fingerprint = sequence_descriptor.fingerprint,
	}
	precondition := Conflict_Resolution_Precondition {
		repository = status_descriptor.repository,
		status_generation = status_descriptor.generation,
		sequence_generation = sequence_descriptor.generation,
		repository_operation = .Merging,
		sequence_state = sequence_descriptor.state,
		sequence = sequence,
		conflict = {sequence = sequence, conflict = conflict},
		target = target,
		worktree = worktree,
		editor = editor,
		unmerged_paths = unmerged_paths,
		action = action,
	}
	request := Process_Request {
		kind = .Resolve_Conflict,
		repository = precondition.repository,
		limits = DEFAULT_PROCESS_LIMITS,
	}
	if !process_request_is_valid(request) do return {}, false, .Invalid_Request
	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = request
	state.conflict_precondition = precondition
	state.conflict_resolution_phase = .Prepare_Worktree
	state.output_limit = request.limits.stdout_bytes
	state.conflict_path, allocation_error = make([dynamic]u8, 0, len(path), allocator)
	if allocation_error == nil do _, allocation_error = append(&state.conflict_path, ..transmute([]u8)path)
	if allocation_error == nil {
		state.output, allocation_error = make([dynamic]u8, 0, int(min(state.output_limit, 64 * KIBIBYTE)), allocator)
	}
	if allocation_error == nil {
		state.diagnostic, allocation_error = make([dynamic]u8, 0, int(min(request.limits.diagnostic_bytes, 16 * KIBIBYTE)), allocator)
	}
	if allocation_error != nil {
		repository_process_data_destroy(state)
		return {}, false, .Allocation
	}
	path_argument := string(state.conflict_path[:])
	if worktree.exists {
		state.command = {"git", "hash-object", "--", path_argument, "", "", "", "", "", ""}
		state.command_count = 4
	} else {
		state.command = {"git", "ls-files", "--unmerged", "-z", "--", path_argument, "", "", "", ""}
		state.command_count = 6
	}
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None {
		repository_process_data_destroy(state)
		return {}, false, state.failure
	}
	state.deadline_ns = now_ns + request.limits.timeout_nanoseconds
	state.state = .Running
	return Repository_Process{state = state}, true, .None
}

/* repository_process_start_conflict_resolution rechecks one exact conflict before whole-path mutation. */
repository_process_start_conflict_resolution :: proc(
	observation: ^Sequence_Observation,
	current: Conflict_Resolution_Precondition,
	request: Conflict_Resolution_Request,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil do return {}, false, .Invalid_Request
	revalidated, failure := conflict_resolution_request_revalidate(current, request)
	if !revalidated do return {}, false, failure
	descriptor, described := sequence_observation_descriptor(observation)
	if !described || descriptor.repository != current.repository ||
	   descriptor.generation != current.sequence_generation || descriptor.kind != .Merge ||
	   descriptor.state != .Conflicted || descriptor.fingerprint != current.sequence.fingerprint {
		return {}, false, .Stale_Observation
	}
	target, found := repository_process_conflict_target_by_id(observation, current.conflict.conflict)
	if !found || target != current.target do return {}, false, .Stale_Observation
	path, copied := sequence_observation_conflict_path(observation, target)
	if !copied || len(path) == 0 do return {}, false, .Path_Unavailable
	process_request := Process_Request {
		kind = .Resolve_Conflict,
		repository = request.precondition.repository,
		limits = request.limits,
	}
	if !process_request_is_valid(process_request) do return {}, false, .Invalid_Request
	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = process_request
	state.conflict_resolution = request
	state.conflict_resolution_phase = .Check_Conflict
	state.output_limit = request.limits.stdout_bytes
	state.conflict_path, allocation_error = make([dynamic]u8, 0, len(path), allocator)
	if allocation_error == nil do _, allocation_error = append(&state.conflict_path, ..transmute([]u8)path)
	if allocation_error == nil {
		state.output, allocation_error = make(
			[dynamic]u8,
			0,
			int(min(state.output_limit, 64 * KIBIBYTE)),
			allocator,
		)
	}
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
	path_argument := string(state.conflict_path[:])
	state.command = {"git", "ls-files", "--unmerged", "-z", "--", path_argument, "", "", "", ""}
	state.command_count = 6
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
repository_process_advance_conflict_resolution :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.request.kind != .Resolve_Conflict ||
	   state.conflict_resolution_phase == .None {
		return .Invalid_Request
	}
	if state.conflict_resolution_phase == .Prepare_Worktree {
		return repository_process_advance_conflict_resolution_precondition(state)
	}
	if
	   !conflict_resolution_request_is_valid(state.conflict_resolution) {
		return .Invalid_Request
	}
	switch state.conflict_resolution_phase {
	case .Check_Conflict:
		if state.exit_status != 0 do return .Process_Failed
		if !repository_process_conflict_output_matches(state) do return .Stale_Observation
		return repository_process_start_conflict_worktree_check(state)
	case .Check_Worktree:
		worktree := state.conflict_resolution.precondition.worktree
		if worktree.exists {
			object := worktree.git_object
			if state.exit_status != 0 || !repository_process_conflict_output_matches_text(
				state,
				revision_identity_string(&object),
			) {
				return .Stale_Observation
			}
		} else if state.exit_status == 0 {
			return .Stale_Observation
		}
		return repository_process_start_conflict_mutation(state)
	case .Mutate:
		if state.exit_status != 0 {
			state.failure = .Process_Failed
			state.conflict_resolution_phase = .None
			state.state = .Failed
			return .None
		}
		action := state.conflict_resolution.precondition.action
		if action == .Use_Base || action == .Use_Current || action == .Use_Applied {
			return repository_process_start_conflict_stage_result(state)
		}
		return repository_process_start_conflict_result_verification(state)
	case .Stage_Result:
		if state.exit_status != 0 {
			state.failure = .Process_Failed
			state.conflict_resolution_phase = .None
			state.state = .Failed
			return .None
		}
		return repository_process_start_conflict_result_verification(state)
	case .Verify_Result:
		if state.exit_status != 0 {
			state.failure = .Process_Failed
			state.conflict_resolution_phase = .None
			state.state = .Failed
			return .None
		}
		stage_zero, observed := repository_process_conflict_stage_zero(state)
		if !observed || !conflict_resolution_stage_matches_request(
			stage_zero,
			state.conflict_resolution,
		) {
			state.failure = .Stale_Observation
			state.conflict_resolution_phase = .None
			state.state = .Failed
			return .None
		}
		state.conflict_resolution_phase = .None
		state.state = .Completed
		return .None
	case .None, .Prepare_Worktree:
		return .Invalid_Request
	}
	return .Invalid_Request
}

@(private)
repository_process_start_conflict_result_verification :: proc(
	state: ^Repository_Process_Data,
) -> Failure_Code {
	if state == nil || !state.conflict_resolution_started do return .Invalid_Request
	repository_process_conflict_resolution_reset_child(state)
	path := string(state.conflict_path[:])
	state.command = {"git", "ls-files", "--stage", "-z", "--", path, "", "", "", ""}
	state.command_count = 6
	return repository_process_start_conflict_resolution_phase_child(state, .Verify_Result)
}

@(private)
repository_process_conflict_stage_zero :: proc(
	state: ^Repository_Process_Data,
) -> (Conflict_Stage_Zero, bool) {
	if state == nil || state.request.kind != .Resolve_Conflict do return {}, false
	if len(state.output) == 0 do return {state = .Deleted}, true
	if state.output[len(state.output) - 1] != 0 do return {}, false
	record := state.output[:len(state.output) - 1]
	for byte in record {
		if byte == 0 do return {}, false
	}
	mode_end := 0
	for mode_end < len(record) && record[mode_end] != ' ' do mode_end += 1
	object_start := mode_end + 1
	object_end := object_start
	for object_end < len(record) && record[object_end] != ' ' do object_end += 1
	stage_start := object_end + 1
	path := string(state.conflict_path[:])
	if mode_end == 0 || object_start >= len(record) || object_end == object_start ||
	   stage_start + 1 >= len(record) || record[stage_start] != '0' ||
	   record[stage_start + 1] != '\t' || string(record[stage_start + 2:]) != path {
		return {}, false
	}
	mode, mode_ok := repository_process_conflict_mode_parse(record[:mode_end])
	object: Revision_Identity
	object_ok := revision_identity_assign(&object, string(record[object_start:object_end]))
	if !mode_ok || !object_ok do return {}, false
	return {state = .Present, mode = mode, object = object}, true
}

@(private)
repository_process_advance_conflict_resolution_precondition :: proc(
	state: ^Repository_Process_Data,
) -> Failure_Code {
	if state == nil || state.conflict_resolution_phase != .Prepare_Worktree do return .Invalid_Request
	worktree := &state.conflict_precondition.worktree
	if worktree.exists {
		identity, valid := repository_process_commit_output_identity(state)
		if state.exit_status != 0 || !valid do return .Stale_Observation
		worktree.git_object = identity
	} else if state.exit_status != 0 || len(state.output) == 0 {
		return .Stale_Observation
	}
	if failure := conflict_resolution_precondition_failure(state.conflict_precondition); failure != .None {
		return failure
	}
	state.conflict_resolution_phase = .None
	state.state = .Completed
	return .None
}

@(private)
repository_process_start_conflict_worktree_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.conflict_resolution_phase != .Check_Conflict do return .Invalid_Request
	repository_process_conflict_resolution_reset_child(state)
	path := string(state.conflict_path[:])
	state.command = {"git", "hash-object", "--", path, "", "", "", "", "", ""}
	state.command_count = 4
	return repository_process_start_conflict_resolution_phase_child(state, .Check_Worktree)
}

@(private)
repository_process_start_conflict_mutation :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.conflict_resolution_phase != .Check_Worktree do return .Invalid_Request
	repository_process_conflict_resolution_reset_child(state)
	path := string(state.conflict_path[:])
	action := state.conflict_resolution.precondition.action
	switch action {
	case .Mark_Saved_Result:
		state.command = {"git", "add", "--", path, "", "", "", "", "", ""}
		state.command_count = 4
	case .Delete_Result:
		state.command = {"git", "rm", "--", path, "", "", "", "", "", ""}
		state.command_count = 4
	case .Use_Base, .Use_Current, .Use_Applied:
		stage := "--stage=1"
		if action == .Use_Current do stage = "--stage=2"
		if action == .Use_Applied do stage = "--stage=3"
		state.command = {"git", "checkout-index", "--force", stage, "--", path, "", "", "", ""}
		state.command_count = 6
	case .Invalid:
		return .Invalid_Request
	}
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	state.conflict_resolution_phase = .Mutate
	state.conflict_resolution_started = true
	return .None
}

@(private)
repository_process_start_conflict_stage_result :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.conflict_resolution_phase != .Mutate ||
	   !state.conflict_resolution_started {
		return .Invalid_Request
	}
	repository_process_conflict_resolution_reset_child(state)
	path := string(state.conflict_path[:])
	state.command = {"git", "add", "--", path, "", "", "", "", "", ""}
	state.command_count = 4
	return repository_process_start_conflict_resolution_phase_child(state, .Stage_Result)
}

@(private)
repository_process_start_conflict_resolution_phase_child :: proc(
	state: ^Repository_Process_Data,
	phase: Conflict_Resolution_Process_Phase,
) -> Failure_Code {
	if state == nil || phase == .None do return .Invalid_Request
	state.child, state.failure = repository_process_start_child(state)
	if state.failure == .None do state.conflict_resolution_phase = phase
	return state.failure
}

@(private)
repository_process_conflict_output_matches :: proc(state: ^Repository_Process_Data) -> bool {
	if state == nil || state.conflict_resolution_phase != .Check_Conflict do return false
	target := state.conflict_resolution.precondition.target
	path := string(state.conflict_path[:])
	found: [3]bool
	offset := 0
	for offset < len(state.output) {
		end := offset
		for end < len(state.output) && state.output[end] != 0 do end += 1
		if end == offset || end == len(state.output) do return false
		record := state.output[offset:end]
		offset = end + 1
		mode_end := 0
		for mode_end < len(record) && record[mode_end] != ' ' do mode_end += 1
		object_start := mode_end + 1
		object_end := object_start
		for object_end < len(record) && record[object_end] != ' ' do object_end += 1
		stage_start := object_end + 1
		if mode_end == 0 || object_start >= len(record) || object_end == object_start ||
		   stage_start + 1 >= len(record) || record[stage_start + 1] != '\t' {
			return false
		}
		stage_byte := record[stage_start]
		if stage_byte < '1' || stage_byte > '3' || string(record[stage_start + 2:]) != path do return false
		stage_index := int(stage_byte - '1')
		if found[stage_index] do return false
		expected := target.stages[stage_index]
		mode, mode_ok := repository_process_conflict_mode_parse(record[:mode_end])
		object: Revision_Identity
		object_ok := revision_identity_assign(&object, string(record[object_start:object_end]))
		if !expected.available || !mode_ok || !object_ok || expected.mode != mode || expected.object != object {
			return false
		}
		found[stage_index] = true
	}
	for expected, index in target.stages {
		if expected.available != found[index] do return false
	}
	return true
}

@(private)
repository_process_conflict_mode_parse :: proc(bytes: []u8) -> (u32, bool) {
	if len(bytes) != 6 do return 0, false
	mode: u32
	for byte in bytes {
		if byte < '0' || byte > '7' do return 0, false
		mode = mode * 8 + u32(byte - '0')
	}
	return mode, true
}

@(private)
repository_process_conflict_output_matches_text :: proc(
	state: ^Repository_Process_Data,
	expected: string,
) -> bool {
	return state != nil && len(expected) > 0 && len(state.output) == len(expected) + 1 &&
	       state.output[len(state.output) - 1] == '\n' && string(state.output[:len(expected)]) == expected
}

@(private)
repository_process_conflict_target_by_id :: proc(
	observation: ^Sequence_Observation,
	wanted: Conflict_ID,
) -> (Conflict_Target, bool) {
	count, available := sequence_observation_conflict_count(observation)
	if !available do return {}, false
	for index in 0 ..< count {
		target, found := sequence_observation_conflict(observation, index)
		if found && target.id == wanted do return target, true
	}
	return {}, false
}

@(private)
repository_process_conflict_resolution_exit_is_expected :: proc(
	state: ^Repository_Process_Data,
	exit_status: i32,
) -> bool {
	return state != nil && state.request.kind == .Resolve_Conflict &&
	       state.conflict_resolution_phase == .Check_Worktree &&
	       !state.conflict_resolution.precondition.worktree.exists && exit_status != 0
}

@(private)
repository_process_conflict_resolution_reset_child :: proc(state: ^Repository_Process_Data) {
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

/* repository_process_take_conflict_resolution copies one terminal whole-path process outcome. */
repository_process_take_conflict_resolution :: proc(
	process: ^Repository_Process,
	allocator := context.allocator,
) -> (Conflict_Resolution_Result, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || (state.state != .Completed && state.state != .Failed) ||
	   state.request.kind != .Resolve_Conflict ||
	   !conflict_resolution_request_is_valid(state.conflict_resolution) {
		return {}, false, .Invalid_Request
	}
	if !state.conflict_resolution_started && state.failure != .Cancelled do return {}, false, state.failure
	return conflict_resolution_result_open(
		state.conflict_resolution,
		state.conflict_resolution_started,
		state.exit_status,
		state.output[:],
		state.diagnostic[:],
		state.failure,
		allocator,
	)
}

/* repository_process_take_conflict_stage_zero returns the exact final index result checked by Git. */
repository_process_take_conflict_stage_zero :: proc(
	process: ^Repository_Process,
) -> (Conflict_Stage_Zero, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || state.state != .Completed || state.request.kind != .Resolve_Conflict ||
	   state.conflict_resolution_phase != .None {
		return {}, false, .Invalid_Request
	}
	stage_zero, observed := repository_process_conflict_stage_zero(state)
	if !observed do return {}, false, .Parse
	return stage_zero, true, .None
}

/* repository_process_take_conflict_resolution_precondition copies one checked path boundary. */
repository_process_take_conflict_resolution_precondition :: proc(
	process: ^Repository_Process,
) -> (Conflict_Resolution_Precondition, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || state.state != .Completed || state.request.kind != .Resolve_Conflict ||
	   state.conflict_resolution_phase != .None ||
	   !conflict_resolution_precondition_is_valid(state.conflict_precondition) {
		return {}, false, .Invalid_Request
	}
	return state.conflict_precondition, true, .None
}
