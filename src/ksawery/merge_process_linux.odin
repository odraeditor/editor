// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery

import "core:os"

@(private)
Merge_Process_Phase :: enum u8 {
	None,
	Prepare_Index_Tree,
	Prepare_Index,
	Check_Head_Name,
	Check_Head_Object,
	Check_Target,
	Check_Index,
	Check_Status,
	Check_Operation,
	Mutate,
	Check_Pending_Commit,
	Commit,
}

/* repository_process_start_merge_precondition observes the exact index identities needed for confirmation. */
repository_process_start_merge_precondition :: proc(
	status: ^Status_Observation,
	refs: ^Ref_Observation,
	sequence: ^Sequence_Observation,
	source: Ref_Identity,
	action: Merge_Action,
	policy: Merge_Fast_Forward_Policy,
	editor: Merge_Editor_State,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil || action == .Invalid || !merge_editor_state_is_valid(editor) {
		return {}, false, .Invalid_Request
	}
	status_descriptor, status_described := status_observation_descriptor(status)
	refs_descriptor, refs_described := ref_observation_descriptor(refs)
	sequence_descriptor, sequence_described := sequence_observation_descriptor(sequence)
	if !status_described || !refs_described || !sequence_described ||
	   status_descriptor.repository != refs_descriptor.repository ||
	   status_descriptor.repository != sequence_descriptor.repository ||
	   refs_descriptor.state == .Truncated || refs_descriptor.head.state != .Symbolic {
		return {}, false, .Stale_Observation
	}
	worktree_paths, unmerged_paths, counted := repository_process_merge_status_counts(status)
	if !counted do return {}, false, .Stale_Observation
	precondition := Merge_Precondition {
		repository = status_descriptor.repository,
		status_generation = status_descriptor.generation,
		ref_generation = refs_descriptor.generation,
		sequence_generation = sequence_descriptor.generation,
		head = refs_descriptor.head,
		repository_operation = status_descriptor.operation,
		sequence_state = sequence_descriptor.state,
		worktree_paths = worktree_paths,
		unmerged_paths = unmerged_paths,
		editor = editor,
		action = action,
	}
	if action == .Start {
		if !ref_identity_is_valid(source) || source.object_type != .Commit ||
		   source.repository != precondition.repository || source.generation != precondition.ref_generation {
			return {}, false, .Ref_Unavailable
		}
		precondition.source = {reference = source, revision = source.object}
		precondition.target_revision = source.object
		precondition.policy = policy
		precondition.message = {.Not_Used, {}}
		if policy != .Fast_Forward_Only do precondition.message = {.Git_Default, {}}
	} else {
		if sequence_descriptor.kind != .Merge ||
		   (sequence_descriptor.state != .Active && sequence_descriptor.state != .Conflicted) ||
		   sequence_descriptor.current != refs_descriptor.head.object ||
		   !revision_identity_is_valid(sequence_descriptor.target) {
			return {}, false, .Action_Unavailable
		}
		precondition.sequence = {
			generation = sequence_descriptor.generation,
			fingerprint = sequence_descriptor.fingerprint,
		}
		precondition.repository_operation = .Merging
		precondition.target_revision = sequence_descriptor.target
		precondition.message = {.Not_Used, {}}
		if action == .Continue do precondition.message = {.Git_Default, {}}
	}
	request := Process_Request {
		kind = .Merge_Repository,
		repository = precondition.repository,
		limits = DEFAULT_PROCESS_LIMITS,
	}
	if !process_request_is_valid(request) do return {}, false, .Invalid_Request
	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = request
	state.merge_precondition = precondition
	state.output_limit = request.limits.stdout_bytes
	state.output, allocation_error = make([dynamic]u8, 0, int(min(state.output_limit, 64 * KIBIBYTE)), allocator)
	if allocation_error == nil {
		state.diagnostic, allocation_error = make([dynamic]u8, 0, int(min(request.limits.diagnostic_bytes, 16 * KIBIBYTE)), allocator)
	}
	if allocation_error != nil {
		repository_process_data_destroy(state)
		return {}, false, .Allocation
	}
	if action == .Abort && sequence_descriptor.state == .Conflicted {
		state.command = {"git", "ls-files", "--stage", "-z", "", "", "", "", "", ""}
		state.command_count = 4
		state.merge_phase = .Prepare_Index
	} else {
		state.command = {"git", "write-tree", "", "", "", "", "", "", "", ""}
		state.command_count = 2
		state.merge_phase = .Prepare_Index_Tree
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

/* repository_process_start_merge rechecks live Git identity before one confirmed merge action. */
repository_process_start_merge :: proc(
	current: Merge_Precondition,
	request: Merge_Request,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil do return {}, false, .Invalid_Request
	revalidated, failure := merge_request_revalidate(current, request)
	if !revalidated do return {}, false, failure
	process_request := Process_Request {
		kind = .Merge_Repository,
		repository = request.precondition.repository,
		limits = request.limits,
	}
	if !process_request_is_valid(process_request) do return {}, false, .Invalid_Request
	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = process_request
	state.merge = request
	state.merge_phase = .Check_Head_Name
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
repository_process_advance_merge :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.request.kind != .Merge_Repository || state.merge_phase == .None {
		return .Invalid_Request
	}
	if state.merge_phase == .Prepare_Index_Tree || state.merge_phase == .Prepare_Index {
		return repository_process_advance_merge_precondition(state)
	}
	if
	   !merge_request_is_valid(state.merge) {
		return .Invalid_Request
	}
	precondition := state.merge.precondition
	switch state.merge_phase {
	case .Check_Head_Name:
		name := precondition.head.branch.name
		if state.exit_status != 0 || !repository_process_merge_output_matches(state, ref_name_string(&name)) {
			return .Stale_Observation
		}
		return repository_process_start_merge_head_object_check(state)
	case .Check_Head_Object:
		head := precondition.head.object
		if state.exit_status != 0 || !repository_process_merge_output_matches(
			state,
			revision_identity_string(&head),
		) {
			return .Stale_Observation
		}
		return repository_process_start_merge_target_check(state)
	case .Check_Target:
		target := precondition.target_revision
		if state.exit_status != 0 || !repository_process_merge_output_matches(
			state,
			revision_identity_string(&target),
		) {
			return .Stale_Observation
		}
		return repository_process_start_merge_index_check(state)
	case .Check_Index:
		if state.exit_status != 0 do return .Process_Failed
		fingerprint: Merge_Index_Fingerprint
		if !merge_index_fingerprint_compute(&fingerprint, state.output[:]) do return .Parse
		if fingerprint != precondition.index_fingerprint do return .Stale_Observation
		if precondition.action == .Abort do return repository_process_start_merge_mutation(state)
		return repository_process_start_merge_status_check(state)
	case .Check_Status:
		if state.exit_status != 0 do return .Process_Failed
		if precondition.action == .Start {
			if len(state.output) != 0 do return .Action_Unavailable
			state.merge_operation_marker = 0
			return repository_process_start_merge_operation_check(state)
		}
		if precondition.action == .Continue {
			if len(state.output) != 0 do return .Action_Unavailable
			return repository_process_start_merge_mutation(state)
		}
		return .Invalid_Request
	case .Check_Operation:
		if state.exit_status != 0 do return .Process_Failed
		active, inspected := repository_process_merge_operation_is_active(state)
		if !inspected do return .Parse
		if active do return .Action_Unavailable
		state.merge_operation_marker += 1
		if int(state.merge_operation_marker) < len(COMMIT_OPERATION_MARKERS) {
			return repository_process_start_merge_operation_check(state)
		}
		return repository_process_start_merge_mutation(state)
	case .Mutate:
		if state.exit_status != 0 {
			state.failure = .Process_Failed
			state.merge_phase = .None
			state.state = .Failed
			return .None
		}
		if precondition.action == .Start && precondition.policy != .Fast_Forward_Only {
			return repository_process_start_merge_pending_commit_check(state)
		}
		state.merge_phase = .None
		state.state = .Completed
		return .None
	case .Check_Pending_Commit:
		if state.exit_status == 1 {
			state.merge_phase = .None
			state.state = .Completed
			return .None
		}
		if state.exit_status != 0 do return .Process_Failed
		target := precondition.target_revision
		if !repository_process_merge_output_matches(state, revision_identity_string(&target)) {
			return .Stale_Observation
		}
		return repository_process_start_merge_commit(state)
	case .Commit:
		if state.exit_status != 0 {
			state.failure = .Process_Failed
			state.merge_phase = .None
			state.state = .Failed
			return .None
		}
		state.merge_phase = .None
		state.state = .Completed
		return .None
	case .None, .Prepare_Index_Tree, .Prepare_Index:
		return .Invalid_Request
	}
	return .Invalid_Request
}

@(private)
repository_process_advance_merge_precondition :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.request.kind != .Merge_Repository do return .Invalid_Request
	switch state.merge_phase {
	case .Prepare_Index_Tree:
		if state.exit_status != 0 do return .Action_Unavailable
		identity, valid := repository_process_commit_output_identity(state)
		if !valid do return .Parse
		state.merge_precondition.index_tree = {object = identity}
		repository_process_merge_reset_child(state)
		state.command = {"git", "ls-files", "--stage", "-z", "", "", "", "", "", ""}
		state.command_count = 4
		return repository_process_start_merge_phase_child(state, .Prepare_Index)
	case .Prepare_Index:
		if state.exit_status != 0 do return .Process_Failed
		if !merge_index_fingerprint_compute(&state.merge_precondition.index_fingerprint, state.output[:]) {
			return .Parse
		}
		if failure := merge_precondition_failure(state.merge_precondition); failure != .None do return failure
		state.merge_phase = .None
		state.state = .Completed
		return .None
	case .None, .Check_Head_Name, .Check_Head_Object, .Check_Target, .Check_Index,
	     .Check_Status, .Check_Operation, .Mutate, .Check_Pending_Commit, .Commit:
		return .Invalid_Request
	}
	return .Invalid_Request
}

@(private)
repository_process_merge_status_counts :: proc(
	observation: ^Status_Observation,
) -> (worktree_paths, unmerged_paths: u32, ok: bool) {
	path_count, counted := status_observation_path_count(observation)
	if !counted do return
	for index in 0 ..< path_count {
		path, found := status_observation_path(observation, index)
		if !found do return 0, 0, false
		worktree_paths += 1
		if path.group == .Unmerged do unmerged_paths += 1
	}
	return worktree_paths, unmerged_paths, true
}

@(private)
repository_process_start_merge_head_object_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.merge_phase != .Check_Head_Name do return .Invalid_Request
	repository_process_merge_reset_child(state)
	state.command = {"git", "rev-parse", "--verify", "--quiet", "HEAD^{commit}", "", "", "", "", ""}
	state.command_count = 5
	return repository_process_start_merge_phase_child(state, .Check_Head_Object)
}

@(private)
repository_process_start_merge_target_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.merge_phase != .Check_Head_Object do return .Invalid_Request
	repository_process_merge_reset_child(state)
	argument := "MERGE_HEAD^{commit}"
	if state.merge.precondition.action == .Start {
		name := state.merge.precondition.source.reference.name
		assigned: bool
		argument, assigned = repository_process_merge_revision_argument(state, &name)
		if !assigned do return .Invalid_Request
	}
	state.command = {"git", "rev-parse", "--verify", "--quiet", argument, "", "", "", "", ""}
	state.command_count = 5
	return repository_process_start_merge_phase_child(state, .Check_Target)
}

@(private)
repository_process_start_merge_index_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.merge_phase != .Check_Target do return .Invalid_Request
	repository_process_merge_reset_child(state)
	state.command = {"git", "ls-files", "--stage", "-z", "", "", "", "", "", ""}
	state.command_count = 4
	return repository_process_start_merge_phase_child(state, .Check_Index)
}

@(private)
repository_process_start_merge_status_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.merge_phase != .Check_Index do return .Invalid_Request
	repository_process_merge_reset_child(state)
	if state.merge.precondition.action == .Start {
		state.command = {"git", "status", "--porcelain=v2", "-z", "--untracked-files=all", "", "", "", "", ""}
		state.command_count = 5
	} else if state.merge.precondition.action == .Continue {
		state.command = {"git", "ls-files", "--unmerged", "-z", "", "", "", "", "", ""}
		state.command_count = 4
	} else {
		return .Invalid_Request
	}
	return repository_process_start_merge_phase_child(state, .Check_Status)
}

@(private)
repository_process_start_merge_operation_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.request.kind != .Merge_Repository ||
	   (state.merge_phase != .Check_Status && state.merge_phase != .Check_Operation) ||
	   int(state.merge_operation_marker) >= len(COMMIT_OPERATION_MARKERS) {
		return .Invalid_Request
	}
	repository_process_merge_reset_child(state)
	markers := COMMIT_OPERATION_MARKERS
	marker := markers[int(state.merge_operation_marker)]
	state.command = {"git", "rev-parse", "--git-path", marker, "", "", "", "", "", ""}
	state.command_count = 4
	return repository_process_start_merge_phase_child(state, .Check_Operation)
}

@(private)
repository_process_start_merge_mutation :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.request.kind != .Merge_Repository || !merge_request_is_valid(state.merge) {
		return .Invalid_Request
	}
	precondition := state.merge.precondition
	if precondition.action == .Start && state.merge_phase != .Check_Operation ||
	   precondition.action == .Continue && state.merge_phase != .Check_Status ||
	   precondition.action == .Abort && state.merge_phase != .Check_Index {
		return .Invalid_Request
	}
	repository_process_merge_reset_child(state)
	switch precondition.action {
	case .Start:
		target := precondition.target_revision
		target_text := revision_identity_string(&target)
		if len(target_text) == 0 do return .Invalid_Request
		switch precondition.policy {
		case .Fast_Forward_Only:
			state.command = {"git", "-c", "core.editor=true", "merge", "--no-edit", "--ff-only", "--", target_text, "", ""}
			state.command_count = 8
		case .Allow_Merge_Commit:
			state.command = {"git", "-c", "core.editor=true", "merge", "--no-edit", "--no-commit", "--ff", "--", target_text, ""}
			state.command_count = 9
		case .Require_Merge_Commit:
			state.command = {"git", "-c", "core.editor=true", "merge", "--no-edit", "--no-commit", "--no-ff", "--", target_text, ""}
			state.command_count = 9
		case .Invalid:
			return .Invalid_Request
		}
	case .Continue:
		if failure := repository_process_assign_merge_commit(state); failure != .None do return failure
	case .Abort:
		state.command = {"git", "merge", "--abort", "", "", "", "", "", "", ""}
		state.command_count = 3
	case .Invalid:
		return .Invalid_Request
	}
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	state.merge_phase = precondition.action == .Continue ? .Commit : .Mutate
	state.merge_started = true
	return .None
}

@(private)
repository_process_start_merge_pending_commit_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.merge_phase != .Mutate || !state.merge_started do return .Invalid_Request
	repository_process_merge_reset_child(state)
	state.command = {"git", "rev-parse", "--verify", "--quiet", "MERGE_HEAD^{commit}", "", "", "", "", ""}
	state.command_count = 5
	return repository_process_start_merge_phase_child(state, .Check_Pending_Commit)
}

@(private)
repository_process_start_merge_commit :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.merge_phase != .Check_Pending_Commit do return .Invalid_Request
	repository_process_merge_reset_child(state)
	if failure := repository_process_assign_merge_commit(state); failure != .None do return failure
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	state.merge_phase = .Commit
	return .None
}

@(private)
repository_process_assign_merge_commit :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || !merge_request_is_valid(state.merge) do return .Invalid_Request
	message := state.merge.precondition.message
	switch message.mode {
	case .Git_Default:
		state.command = {"git", "-c", "core.editor=true", "commit", "--no-edit", "", "", "", "", ""}
		state.command_count = 5
	case .Composed:
		content, copied := commit_message_text(&message.content)
		if !copied do return .Commit_Message_Invalid
		input, make_error := make([dynamic]u8, 0, len(content) + 1, state.allocator)
		if make_error != nil do return .Allocation
		state.input = input
		if _, allocation_error := append(&state.input, ..content); allocation_error != nil {
			return .Allocation
		}
		if _, allocation_error := append(&state.input, '\n'); allocation_error != nil {
			return .Allocation
		}
		state.input_offset = 0
		state.command = {"git", "-c", "core.editor=true", "commit", "--file=-", "", "", "", "", ""}
		state.command_count = 5
	case .Not_Used, .Invalid:
		return .Commit_Message_Invalid
	}
	return .None
}

@(private)
repository_process_start_merge_phase_child :: proc(
	state: ^Repository_Process_Data,
	phase: Merge_Process_Phase,
) -> Failure_Code {
	if state == nil || phase == .None do return .Invalid_Request
	state.child, state.failure = repository_process_start_child(state)
	if state.failure == .None do state.merge_phase = phase
	return state.failure
}

@(private)
repository_process_merge_revision_argument :: proc(
	state: ^Repository_Process_Data,
	name: ^Ref_Name,
) -> (string, bool) {
	if state == nil || name == nil || !ref_name_is_valid(name^) do return "", false
	text := ref_name_string(name)
	suffix := "^{commit}"
	required := len(text) + len(suffix)
	if required > len(state.merge_argument) do return "", false
	state.merge_argument = {}
	copy(state.merge_argument[:len(text)], transmute([]u8)text)
	copy(state.merge_argument[len(text):required], transmute([]u8)suffix)
	return string(state.merge_argument[:required]), true
}

@(private)
repository_process_merge_output_matches :: proc(state: ^Repository_Process_Data, expected: string) -> bool {
	return state != nil && len(expected) > 0 && len(state.output) == len(expected) + 1 &&
	       state.output[len(state.output) - 1] == '\n' && string(state.output[:len(expected)]) == expected
}

@(private)
repository_process_merge_operation_is_active :: proc(state: ^Repository_Process_Data) -> (active, inspected: bool) {
	if state == nil || state.merge_phase != .Check_Operation ||
	   int(state.merge_operation_marker) >= len(COMMIT_OPERATION_MARKERS) ||
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
repository_process_merge_exit_is_expected :: proc(state: ^Repository_Process_Data, exit_status: i32) -> bool {
	return state != nil && state.request.kind == .Merge_Repository && exit_status == 1 &&
	       (state.merge_phase == .Mutate || state.merge_phase == .Commit ||
	        state.merge_phase == .Check_Pending_Commit)
}

@(private)
repository_process_merge_reset_child :: proc(state: ^Repository_Process_Data) {
	if state == nil do return
	local_child_close(&state.child)
	state.child = {}
	state.stdout_closed = false
	state.stderr_closed = false
	state.stdin_closed = false
	state.exit_status = 0
	state.input_offset = 0
	clear(&state.input)
	clear(&state.output)
	clear(&state.diagnostic)
}

/* repository_process_take_merge copies one started or pre-start-cancelled merge outcome. */
repository_process_take_merge :: proc(
	process: ^Repository_Process,
	allocator := context.allocator,
) -> (Merge_Result, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || (state.state != .Completed && state.state != .Failed) ||
	   state.request.kind != .Merge_Repository || !merge_request_is_valid(state.merge) {
		return {}, false, .Invalid_Request
	}
	if !state.merge_started && state.failure != .Cancelled do return {}, false, state.failure
	return merge_result_open(
		state.merge,
		state.merge_started,
		state.exit_status,
		state.output[:],
		state.diagnostic[:],
		state.failure,
		allocator,
	)
}

/* repository_process_take_merge_precondition copies one checked confirmation boundary. */
repository_process_take_merge_precondition :: proc(
	process: ^Repository_Process,
) -> (Merge_Precondition, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || state.state != .Completed || state.request.kind != .Merge_Repository ||
	   state.merge_phase != .None || !merge_precondition_is_valid(state.merge_precondition) {
		return {}, false, .Invalid_Request
	}
	return state.merge_precondition, true, .None
}
