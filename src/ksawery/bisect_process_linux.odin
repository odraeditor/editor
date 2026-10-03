// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery

import "core:os"

@(private)
Bisect_Process_Phase :: enum u8 {
	None,
	Prepare_Index_Tree,
	Prepare_Index,
	Check_Head_Name,
	Check_Head_Object,
	Check_Index,
	Check_Index_Tree,
	Check_Status,
	Check_Operation,
	Check_Bad,
	Check_Good,
	Mutate,
}

/* repository_process_start_bisect_precondition captures exact identities for one confirmation. */
repository_process_start_bisect_precondition :: proc(
	status: ^Status_Observation,
	history: ^History_Observation,
	refs: ^Ref_Observation,
	sequence: ^Sequence_Observation,
	boundaries: ^Bisect_Boundary_Set,
	action: Bisect_Action,
	lineage: Bisect_Precondition,
	progress: Bisect_Progress,
	editor: Bisect_Editor_State,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil || action == .Invalid || !bisect_editor_state_is_valid(editor) {
		return {}, false, .Invalid_Request
	}
	status_descriptor, status_described := status_observation_descriptor(status)
	history_descriptor, history_described := history_observation_descriptor(history)
	refs_descriptor, refs_described := ref_observation_descriptor(refs)
	sequence_descriptor, sequence_described := sequence_observation_descriptor(sequence)
	boundary_identity, boundaries_described := bisect_boundary_set_descriptor(boundaries)
	if !status_described || !history_described || !refs_described || !sequence_described ||
	   !boundaries_described || status_descriptor.repository != history_descriptor.repository ||
	   status_descriptor.repository != refs_descriptor.repository ||
	   status_descriptor.repository != sequence_descriptor.repository || refs_descriptor.state == .Truncated {
		return {}, false, .Stale_Observation
	}
	worktree_paths, counted := status_observation_path_count(status)
	if !counted do return {}, false, .Stale_Observation
	unmerged_paths: u32
	for index in 0 ..< worktree_paths {
		path, found := status_observation_path(status, index)
		if !found do return {}, false, .Stale_Observation
		if path.group == .Unmerged do unmerged_paths += 1
	}
	precondition := Bisect_Precondition {
		repository = status_descriptor.repository,
		status_generation = status_descriptor.generation,
		history_generation = history_descriptor.generation,
		ref_generation = refs_descriptor.generation,
		sequence_generation = sequence_descriptor.generation,
		head = refs_descriptor.head,
		index_fingerprint = {},
		repository_operation = status_descriptor.operation,
		sequence_state = sequence_descriptor.state,
		boundaries = boundary_identity,
		progress = progress,
		action = action,
		classification = repository_process_bisect_classification(action),
		worktree_paths = worktree_paths,
		unmerged_paths = unmerged_paths,
		editor = editor,
		limits = lineage.limits == {} ? DEFAULT_BISECT_LIMITS : lineage.limits,
	}
	if action == .Start {
		precondition.origin = {head = refs_descriptor.head}
		precondition.progress = {}
		precondition.limits = DEFAULT_BISECT_LIMITS
	} else {
		if !bisect_precondition_is_valid(lineage) || lineage.action != .Start ||
		   lineage.repository != precondition.repository || lineage.boundaries != boundary_identity ||
		   sequence_descriptor.kind != .Bisect || sequence_descriptor.state != .Active ||
		   refs_descriptor.head.state != .Detached || sequence_descriptor.current != refs_descriptor.head.object ||
		   !bisect_progress_is_valid(progress, lineage.limits) ||
		   (progress.complete && action != .Reset) ||
		   progress.candidate != refs_descriptor.head.object {
			return {}, false, .Action_Unavailable
		}
		precondition.origin = lineage.origin
		precondition.repository_operation = .Bisecting
		precondition.sequence = {
			generation = sequence_descriptor.generation,
			fingerprint = sequence_descriptor.fingerprint,
		}
		precondition.limits = lineage.limits
	}
	process_request := Process_Request {
		kind = .Bisect_Repository,
		repository = precondition.repository,
		limits = DEFAULT_PROCESS_LIMITS,
	}
	if !process_request_is_valid(process_request) do return {}, false, .Invalid_Request
	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = process_request
	state.manual_bisect_precondition = precondition
	state.output_limit = process_request.limits.stdout_bytes
	state.output, allocation_error = make([dynamic]u8, 0, 4 * KIBIBYTE, allocator)
	if allocation_error == nil do state.diagnostic, allocation_error = make([dynamic]u8, 0, 4 * KIBIBYTE, allocator)
	if allocation_error == nil {
		state.manual_bisect_good, allocation_error = make(
			[dynamic]Revision_Identity,
			int(boundary_identity.good_count),
			allocator,
		)
	}
	copy_valid := true
	if allocation_error == nil {
		for index in 0 ..< boundary_identity.good_count {
			good, found := bisect_boundary_set_good(boundaries, index)
			if !found {
				copy_valid = false
				break
			}
			state.manual_bisect_good[index] = good
		}
	}
	if allocation_error != nil || !copy_valid {
		repository_process_data_destroy(state)
		return {}, false, allocation_error != nil ? .Allocation : .Invalid_Request
	}
	_ = repository_process_bisect_assign_command(state, "git", "write-tree")
	state.manual_bisect_phase = .Prepare_Index_Tree
	state.child, state.failure = repository_process_start_bisect_child(state)
	if state.failure != .None {
		repository_process_data_destroy(state)
		return {}, false, state.failure
	}
	state.deadline_ns = now_ns + process_request.limits.timeout_nanoseconds
	state.state = .Running
	return Repository_Process{state = state}, true, .None
}

/* repository_process_start_bisect rechecks exact live identities before one confirmed action. */
repository_process_start_bisect :: proc(
	sequence: ^Sequence_Observation,
	current: Bisect_Precondition,
	boundaries: ^Bisect_Boundary_Set,
	request: Bisect_Request,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil || !bisect_boundary_set_matches(boundaries, request.precondition.boundaries) {
		return {}, false, .Invalid_Request
	}
	revalidated, failure := bisect_request_revalidate(current, request)
	if !revalidated do return {}, false, failure
	descriptor, described := sequence_observation_descriptor(sequence)
	if !described || descriptor.repository != current.repository ||
	   descriptor.generation != current.sequence_generation || descriptor.state != current.sequence_state {
		return {}, false, .Stale_Observation
	}
	if current.action == .Start {
		if descriptor.kind != .None || descriptor.state != .Inactive do return {}, false, .Action_Unavailable
	} else if descriptor.kind != .Bisect || descriptor.state != .Active ||
	          descriptor.fingerprint != current.sequence.fingerprint || descriptor.current != current.progress.candidate {
		return {}, false, .Stale_Observation
	}
	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = {
		kind = .Bisect_Repository,
		repository = request.precondition.repository,
		limits = request.limits,
	}
	state.manual_bisect = request
	state.output_limit = request.limits.stdout_bytes
	state.output, allocation_error = make([dynamic]u8, 0, int(min(state.output_limit, 64 * KIBIBYTE)), allocator)
	if allocation_error == nil do state.diagnostic, allocation_error = make(
		[dynamic]u8, 0, int(min(request.limits.diagnostic_bytes, 16 * KIBIBYTE)), allocator,
	)
	if allocation_error == nil do state.manual_bisect_good, allocation_error = make(
		[dynamic]Revision_Identity, int(request.precondition.boundaries.good_count), allocator,
	)
	copy_valid := true
	if allocation_error == nil {
		for index in 0 ..< request.precondition.boundaries.good_count {
			good, found := bisect_boundary_set_good(boundaries, index)
			if !found {
				copy_valid = false
				break
			}
			state.manual_bisect_good[index] = good
		}
	}
	if allocation_error != nil || !copy_valid {
		repository_process_data_destroy(state)
		return {}, false, allocation_error != nil ? .Allocation : .Invalid_Request
	}
	_ = repository_process_bisect_assign_command(state, "git", "symbolic-ref", "--quiet", "HEAD")
	state.manual_bisect_phase = .Check_Head_Name
	state.child, state.failure = repository_process_start_bisect_child(state)
	if state.failure != .None {
		repository_process_data_destroy(state)
		return {}, false, state.failure
	}
	state.deadline_ns = now_ns + request.limits.timeout_nanoseconds
	state.state = .Running
	return Repository_Process{state = state}, true, .None
}

@(private)
repository_process_advance_bisect :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.request.kind != .Bisect_Repository || state.manual_bisect_phase == .None {
		return .Invalid_Request
	}
	if state.manual_bisect_phase == .Prepare_Index_Tree || state.manual_bisect_phase == .Prepare_Index {
		return repository_process_advance_bisect_precondition(state)
	}
	if !bisect_request_is_valid(state.manual_bisect) do return .Invalid_Request
	precondition := state.manual_bisect.precondition
	switch state.manual_bisect_phase {
	case .Check_Head_Name:
		if precondition.head.state == .Symbolic {
			name := precondition.head.branch.name
			if state.exit_status != 0 || !repository_process_bisect_output_matches(state, ref_name_string(&name)) {
				return .Stale_Observation
			}
		} else if precondition.head.state != .Detached || state.exit_status != 1 || len(state.output) != 0 {
			return .Stale_Observation
		}
		return repository_process_start_bisect_head_check(state)
	case .Check_Head_Object:
		head := precondition.head.object
		if state.exit_status != 0 || !repository_process_bisect_output_matches(state, revision_identity_string(&head)) {
			return .Stale_Observation
		}
		return repository_process_start_bisect_index_check(state)
	case .Check_Index:
		if state.exit_status != 0 do return .Process_Failed
		fingerprint: Bisect_Index_Fingerprint
		if !bisect_index_fingerprint_compute(&fingerprint, state.output[:]) do return .Parse
		if fingerprint != precondition.index_fingerprint do return .Stale_Observation
		return repository_process_start_bisect_index_tree_check(state)
	case .Check_Index_Tree:
		tree := precondition.index_tree.object
		if state.exit_status != 0 || !repository_process_bisect_output_matches(state, revision_identity_string(&tree)) {
			return .Stale_Observation
		}
		return repository_process_start_bisect_status_check(state)
	case .Check_Status:
		if state.exit_status != 0 do return .Process_Failed
		if len(state.output) != 0 do return .Action_Unavailable
		return repository_process_start_bisect_operation_check(state)
	case .Check_Operation:
		if state.exit_status != 0 do return .Process_Failed
		active, inspected := repository_process_bisect_operation_is_active(state)
		if !inspected do return .Parse
		if precondition.action == .Start {
			if active do return .Action_Unavailable
			return repository_process_start_bisect_bad_check(state)
		}
		if !active do return .Stale_Observation
		return repository_process_start_bisect_mutation(state)
	case .Check_Bad:
		bad := precondition.boundaries.bad
		if state.exit_status != 0 || !repository_process_bisect_output_matches(state, revision_identity_string(&bad)) {
			return .Revision_Unavailable
		}
		state.manual_bisect_boundary_index = 0
		return repository_process_start_bisect_good_check(state)
	case .Check_Good:
		if state.manual_bisect_boundary_index >= u32(len(state.manual_bisect_good)) do return .Invalid_Request
		good := state.manual_bisect_good[state.manual_bisect_boundary_index]
		if state.exit_status != 0 || !repository_process_bisect_output_matches(state, revision_identity_string(&good)) {
			return .Revision_Unavailable
		}
		state.manual_bisect_boundary_index += 1
		if state.manual_bisect_boundary_index < u32(len(state.manual_bisect_good)) {
			return repository_process_start_bisect_good_check(state)
		}
		return repository_process_start_bisect_mutation(state)
	case .Mutate:
		if state.exit_status != 0 {
			state.failure = .Process_Failed
			state.manual_bisect_phase = .None
			state.state = .Failed
			return .None
		}
		state.manual_bisect_phase = .None
		state.state = .Completed
		return .None
	case .None, .Prepare_Index_Tree, .Prepare_Index:
		return .Invalid_Request
	}
	return .Invalid_Request
}

@(private)
repository_process_advance_bisect_precondition :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil ||
	   (state.manual_bisect_phase != .Prepare_Index_Tree && state.manual_bisect_phase != .Prepare_Index) {
		return .Invalid_Request
	}
	if state.exit_status != 0 do return .Process_Failed
	if state.manual_bisect_phase == .Prepare_Index_Tree {
		identity: Revision_Identity
		if len(state.output) < 2 || state.output[len(state.output) - 1] != '\n' ||
		   !revision_identity_assign(&identity, string(state.output[:len(state.output) - 1])) {
			return .Parse
		}
		state.manual_bisect_precondition.index_tree = {identity}
		repository_process_bisect_reset_child(state)
		_ = repository_process_bisect_assign_command(state, "git", "ls-files", "--stage", "-z")
		return repository_process_start_bisect_phase_child(state, .Prepare_Index)
	}
	if !bisect_index_fingerprint_compute(&state.manual_bisect_precondition.index_fingerprint, state.output[:]) {
		return .Parse
	}
	if failure := bisect_precondition_failure(state.manual_bisect_precondition); failure != .None do return failure
	state.manual_bisect_phase = .None
	state.state = .Completed
	return .None
}

@(private)
repository_process_start_bisect_head_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	repository_process_bisect_reset_child(state)
	_ = repository_process_bisect_assign_command(state, "git", "rev-parse", "--verify", "--quiet", "HEAD^{commit}")
	return repository_process_start_bisect_phase_child(state, .Check_Head_Object)
}

@(private)
repository_process_start_bisect_index_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	repository_process_bisect_reset_child(state)
	_ = repository_process_bisect_assign_command(state, "git", "ls-files", "--stage", "-z")
	return repository_process_start_bisect_phase_child(state, .Check_Index)
}

@(private)
repository_process_start_bisect_index_tree_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	repository_process_bisect_reset_child(state)
	_ = repository_process_bisect_assign_command(state, "git", "write-tree")
	return repository_process_start_bisect_phase_child(state, .Check_Index_Tree)
}

@(private)
repository_process_start_bisect_status_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	repository_process_bisect_reset_child(state)
	_ = repository_process_bisect_assign_command(state, "git", "status", "--porcelain=v2", "-z", "--untracked-files=all")
	return repository_process_start_bisect_phase_child(state, .Check_Status)
}

@(private)
repository_process_start_bisect_operation_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	repository_process_bisect_reset_child(state)
	_ = repository_process_bisect_assign_command(state, "git", "rev-parse", "--git-path", "BISECT_LOG")
	return repository_process_start_bisect_phase_child(state, .Check_Operation)
}

@(private)
repository_process_start_bisect_bad_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	repository_process_bisect_reset_child(state)
	bad := state.manual_bisect.precondition.boundaries.bad
	argument, assigned := repository_process_bisect_revision_argument(state, bad)
	if !assigned do return .Invalid_Request
	_ = repository_process_bisect_assign_command(state, "git", "rev-parse", "--verify", "--quiet", argument)
	return repository_process_start_bisect_phase_child(state, .Check_Bad)
}

@(private)
repository_process_start_bisect_good_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.manual_bisect_boundary_index >= u32(len(state.manual_bisect_good)) {
		return .Invalid_Request
	}
	repository_process_bisect_reset_child(state)
	argument, assigned := repository_process_bisect_revision_argument(
		state,
		state.manual_bisect_good[state.manual_bisect_boundary_index],
	)
	if !assigned do return .Invalid_Request
	_ = repository_process_bisect_assign_command(state, "git", "rev-parse", "--verify", "--quiet", argument)
	return repository_process_start_bisect_phase_child(state, .Check_Good)
}

@(private)
repository_process_start_bisect_mutation :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || !bisect_request_is_valid(state.manual_bisect) do return .Invalid_Request
	repository_process_bisect_reset_child(state)
	precondition := state.manual_bisect.precondition
	switch precondition.action {
	case .Start:
		bad := precondition.boundaries.bad
		state.manual_bisect_command[0] = "git"
		state.manual_bisect_command[1] = "bisect"
		state.manual_bisect_command[2] = "start"
		state.manual_bisect_command[3] = revision_identity_string(&bad)
		for good, index in state.manual_bisect_good {
			copy := good
			state.manual_bisect_command[index + 4] = revision_identity_string(&copy)
		}
		state.command_count = u8(4 + len(state.manual_bisect_good))
	case .Good:
		_ = repository_process_bisect_assign_command(state, "git", "bisect", "good")
	case .Bad:
		_ = repository_process_bisect_assign_command(state, "git", "bisect", "bad")
	case .Skip:
		_ = repository_process_bisect_assign_command(state, "git", "bisect", "skip")
	case .Reset:
		_ = repository_process_bisect_assign_command(state, "git", "bisect", "reset")
	case .Invalid:
		return .Invalid_Request
	}
	state.child, state.failure = repository_process_start_bisect_child(state)
	if state.failure != .None do return state.failure
	state.manual_bisect_phase = .Mutate
	state.manual_bisect_started = true
	return .None
}

@(private)
repository_process_start_bisect_phase_child :: proc(
	state: ^Repository_Process_Data,
	phase: Bisect_Process_Phase,
) -> Failure_Code {
	if state == nil || phase == .None do return .Invalid_Request
	state.child, state.failure = repository_process_start_bisect_child(state)
	if state.failure == .None do state.manual_bisect_phase = phase
	return state.failure
}

@(private)
repository_process_bisect_assign_command :: proc(state: ^Repository_Process_Data, command: ..string) -> bool {
	if state == nil || len(command) == 0 || len(command) > len(state.manual_bisect_command) || len(command) > 255 {
		return false
	}
	state.manual_bisect_command = {}
	copy(state.manual_bisect_command[:len(command)], command[:])
	state.command_count = u8(len(command))
	return true
}

@(private)
repository_process_start_bisect_child :: proc(state: ^Repository_Process_Data) -> (Local_Child, Failure_Code) {
	if state == nil || state.command_count == 0 || int(state.command_count) > len(state.manual_bisect_command) {
		return {}, .Invalid_Request
	}
	if state.termination.reason != .None {
		return {}, state.termination.reason == .Timeout ? .Timeout : .Cancelled
	}
	repository := state.request.repository
	child, failure := local_child_start(
		state.manual_bisect_command[:int(state.command_count)],
		repository_context_string(&repository),
	)
	if failure == .None {
		repository_process_note_child_started(state)
	} else {
		repository_process_note_failure(state, .Start, failure)
	}
	return child, failure
}

@(private)
repository_process_bisect_revision_argument :: proc(
	state: ^Repository_Process_Data,
	revision: Revision_Identity,
) -> (string, bool) {
	if state == nil || !revision_identity_is_valid(revision) do return "", false
	revision_copy := revision
	text := revision_identity_string(&revision_copy)
	suffix := "^{commit}"
	required := len(text) + len(suffix)
	if required > len(state.manual_bisect_argument) do return "", false
	state.manual_bisect_argument = {}
	copy(state.manual_bisect_argument[:len(text)], transmute([]u8)text)
	copy(state.manual_bisect_argument[len(text):required], transmute([]u8)suffix)
	return string(state.manual_bisect_argument[:required]), true
}

@(private)
repository_process_bisect_output_matches :: proc(state: ^Repository_Process_Data, expected: string) -> bool {
	return state != nil && len(expected) > 0 && len(state.output) == len(expected) + 1 &&
	       state.output[len(state.output) - 1] == '\n' && string(state.output[:len(expected)]) == expected
}

@(private)
repository_process_bisect_operation_is_active :: proc(state: ^Repository_Process_Data) -> (bool, bool) {
	if state == nil || state.manual_bisect_phase != .Check_Operation ||
	   len(state.output) < 2 || state.output[len(state.output) - 1] != '\n' {
		return false, false
	}
	marker := string(state.output[:len(state.output) - 1])
	if len(marker) == 0 do return false, false
	repository := state.request.repository
	path := marker
	owned_path: string
	if !os.is_absolute_path(path) {
		resolved, path_error := os.join_path({repository_context_string(&repository), marker}, state.allocator)
		if path_error != nil do return false, false
		path = resolved
		owned_path = resolved
	}
	defer if len(owned_path) > 0 do delete(owned_path, state.allocator)
	return os.exists(path), true
}

@(private)
repository_process_bisect_exit_is_expected :: proc(state: ^Repository_Process_Data, exit_status: i32) -> bool {
	if state == nil || state.request.kind != .Bisect_Repository || exit_status == 0 do return false
	if state.manual_bisect_phase == .Mutate do return true
	return state.manual_bisect_phase == .Check_Head_Name &&
	       state.manual_bisect.precondition.head.state == .Detached && exit_status == 1
}

@(private)
repository_process_bisect_reset_child :: proc(state: ^Repository_Process_Data) {
	if state == nil do return
	local_child_close(&state.child)
	state.child = {}
	state.stdout_closed = false
	state.stderr_closed = false
	state.stdin_closed = false
	state.exit_status = 0
	clear(&state.output)
	clear(&state.diagnostic)
}

@(private)
repository_process_bisect_classification :: proc(action: Bisect_Action) -> Bisect_Classification {
	switch action {
	case .Start, .Reset: return .None
	case .Good: return .Good
	case .Bad: return .Bad
	case .Skip: return .Skipped
	case .Invalid: return .Invalid
	}
	return .Invalid
}

/* repository_process_take_bisect_precondition returns one exact prepared confirmation boundary. */
repository_process_take_bisect_precondition :: proc(
	process: ^Repository_Process,
) -> (Bisect_Precondition, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || state.state != .Completed || state.request.kind != .Bisect_Repository ||
	   state.manual_bisect_phase != .None {
		return {}, false, .Invalid_Request
	}
	if failure := bisect_precondition_failure(state.manual_bisect_precondition); failure != .None {
		return {}, false, failure
	}
	return state.manual_bisect_precondition, true, .None
}

/* repository_process_take_bisect copies one started or pre-start-cancelled child outcome. */
repository_process_take_bisect :: proc(
	process: ^Repository_Process,
	allocator := context.allocator,
) -> (Bisect_Result, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || (state.state != .Completed && state.state != .Failed) ||
	   state.request.kind != .Bisect_Repository || !bisect_request_is_valid(state.manual_bisect) {
		return {}, false, .Invalid_Request
	}
	if !state.manual_bisect_started && state.failure != .Cancelled do return {}, false, state.failure
	return bisect_result_open(
		state.manual_bisect,
		state.manual_bisect_started,
		state.exit_status,
		state.output[:],
		state.diagnostic[:],
		state.failure,
		allocator,
	)
}
