// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery

import "base:runtime"

/* Revision_Sequence_Process_Phase identifies one checked revision-sequence child phase. */
Revision_Sequence_Process_Phase :: enum u8 {
	None,
	Prepare_Index_Tree,
	Prepare_Index,
	Check_Head_Name,
	Check_Head_Object,
	Check_Target,
	Check_Index_Tree,
	Check_Index,
	Mutate,
}

/* repository_process_start_revision_sequence_precondition captures exact action identities for confirmation. */
repository_process_start_revision_sequence_precondition :: proc(
	status: ^Status_Observation,
	history: ^History_Observation,
	refs: ^Ref_Observation,
	sequence: ^Sequence_Observation,
	set: ^Revision_Sequence_Set,
	family: Revision_Sequence_Family,
	action: Revision_Sequence_Action,
	lineage: Revision_Sequence_Precondition,
	editor: Revision_Sequence_Editor_State,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil || family == .Invalid || action == .Invalid ||
	   !revision_sequence_editor_state_is_valid(editor) {
		return {}, false, .Invalid_Request
	}
	status_descriptor, status_ok := status_observation_descriptor(status)
	history_descriptor, history_ok := history_observation_descriptor(history)
	refs_descriptor, refs_ok := ref_observation_descriptor(refs)
	sequence_descriptor, sequence_ok := sequence_observation_descriptor(sequence)
	selection, selected := revision_sequence_set_descriptor(set)
	if !status_ok || !history_ok || !refs_ok || !sequence_ok || !selected ||
	   status_descriptor.repository != history_descriptor.repository ||
	   status_descriptor.repository != refs_descriptor.repository ||
	   status_descriptor.repository != sequence_descriptor.repository ||
	   refs_descriptor.state == .Truncated || refs_descriptor.head.state != .Symbolic {
		return {}, false, .Stale_Observation
	}
	worktree_paths, counted := status_observation_path_count(status)
	if !counted do return {}, false, .Stale_Observation
	unmerged_paths: u32
	for path_index in 0 ..< worktree_paths {
		path, found := status_observation_path(status, path_index)
		if !found do return {}, false, .Stale_Observation
		if path.group == .Unmerged do unmerged_paths += 1
	}
	precondition := Revision_Sequence_Precondition {
		repository = status_descriptor.repository,
		status_generation = status_descriptor.generation,
		history_generation = history_descriptor.generation,
		ref_generation = refs_descriptor.generation,
		sequence_generation = sequence_descriptor.generation,
		head = refs_descriptor.head,
		repository_operation = status_descriptor.operation,
		sequence_kind = sequence_descriptor.kind,
		sequence_state = sequence_descriptor.state,
		worktree_paths = worktree_paths,
		unmerged_paths = unmerged_paths,
		editor = editor,
		family = family,
		action = action,
		selection = selection,
	}
	if action == .Start {
		precondition.original_head = {
			branch = refs_descriptor.head.branch.name,
			revision = refs_descriptor.head.object,
		}
		precondition.message.mode = .Preserve_Selected
		precondition.signing = .Configured
	} else {
		if !revision_sequence_precondition_is_valid(lineage) || lineage.action != .Start ||
		   lineage.family != family || lineage.repository != precondition.repository ||
		   lineage.selection != selection ||
		   (sequence_descriptor.state != .Active && sequence_descriptor.state != .Conflicted) {
			return {}, false, .Action_Unavailable
		}
		expected_operation, expected_kind, family_ok := revision_sequence_family_state(family)
		if !family_ok || sequence_descriptor.kind != expected_kind || sequence_descriptor.target == {} {
			return {}, false, .Action_Unavailable
		}
		precondition.repository_operation = expected_operation
		target, target_position, found := repository_process_revision_sequence_find_target(
			set, sequence_descriptor.target,
		)
		if !found do return {}, false, .Stale_Observation
		position := sequence_descriptor.step.position
		total := sequence_descriptor.step.total
		if sequence_descriptor.step == {} {
			position = target_position
			total = selection.commits
		}
		precondition.original_head = lineage.original_head
		precondition.sequence = {
			generation = sequence_descriptor.generation,
			fingerprint = sequence_descriptor.fingerprint,
		}
		precondition.step = {position = position, total = total, target = target}
		precondition.message.mode = .Not_Used
		precondition.signing = .Not_Used
		if action == .Continue {
			precondition.message.mode = .Git_Prepared
			precondition.signing = .Configured
		}
	}
	request_kind := family == .Cherry_Pick ? Request_Kind.Cherry_Pick_Repository : .Revert_Repository
	process_request := Process_Request {
		kind = request_kind,
		repository = precondition.repository,
		limits = DEFAULT_PROCESS_LIMITS,
	}
	if !process_request_is_valid(process_request) do return {}, false, .Invalid_Request
	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = process_request
	state.revision_sequence.precondition = precondition
	state.output_limit = process_request.limits.stdout_bytes
	state.output, allocation_error = make([dynamic]u8, 0, 4 * KIBIBYTE, allocator)
	if allocation_error == nil {
		state.diagnostic, allocation_error = make([dynamic]u8, 0, 4 * KIBIBYTE, allocator)
	}
	if allocation_error != nil {
		repository_process_data_destroy(state)
		return {}, false, .Allocation
	}
	if action == .Start || action == .Continue {
		state.revision_sequence_command = {
			"git", "write-tree", "", "", "", "", "", "", "", "", "", "", "", "", "", "",
		}
		state.command_count = 2
		state.revision_sequence_phase = .Prepare_Index_Tree
	} else {
		state.revision_sequence_command = {
			"git", "ls-files", "--stage", "-z", "", "", "", "", "", "", "", "", "", "", "", "",
		}
		state.command_count = 4
		state.revision_sequence_phase = .Prepare_Index
	}
	state.child, state.failure = repository_process_start_revision_sequence_child(state)
	if state.failure != .None {
		repository_process_data_destroy(state)
		return {}, false, state.failure
	}
	state.deadline_ns = now_ns + process_request.limits.timeout_nanoseconds
	state.state = .Running
	return Repository_Process{state = state}, true, .None
}

/* repository_process_start_cherry_pick rechecks and applies one exact ordered commit set. */
repository_process_start_cherry_pick :: proc(
	sequence: ^Sequence_Observation,
	set: ^Revision_Sequence_Set,
	current: Revision_Sequence_Precondition,
	request: Revision_Sequence_Request,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	return repository_process_start_revision_sequence(
		sequence, set, current, request, .Cherry_Pick, .Cherry_Pick_Repository, now_ns, allocator,
	)
}

/* repository_process_start_revert rechecks and inversely applies one exact ordered commit set. */
repository_process_start_revert :: proc(
	sequence: ^Sequence_Observation,
	set: ^Revision_Sequence_Set,
	current: Revision_Sequence_Precondition,
	request: Revision_Sequence_Request,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	return repository_process_start_revision_sequence(
		sequence, set, current, request, .Revert, .Revert_Repository, now_ns, allocator,
	)
}

@(private)
repository_process_start_revision_sequence :: proc(
	sequence: ^Sequence_Observation,
	set: ^Revision_Sequence_Set,
	current: Revision_Sequence_Precondition,
	request: Revision_Sequence_Request,
	family: Revision_Sequence_Family,
	request_kind: Request_Kind,
	now_ns: i64,
	allocator: runtime.Allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil || request.precondition.family != family ||
	   (family != .Cherry_Pick && family != .Revert) ||
	   !revision_sequence_set_matches(set, request.precondition.selection) {
		return {}, false, .Invalid_Request
	}
	request_current, request_failure := revision_sequence_request_revalidate(current, request)
	if !request_current do return {}, false, request_failure
	if request.precondition.message.mode == .Composed do return {}, false, .Action_Unavailable
	descriptor, described := sequence_observation_descriptor(sequence)
	if !described || descriptor.repository != request.precondition.repository ||
	   descriptor.generation != request.precondition.sequence_generation ||
	   descriptor.kind != request.precondition.sequence_kind ||
	   descriptor.state != request.precondition.sequence_state {
		return {}, false, .Stale_Observation
	}
	if request.precondition.action != .Start &&
	   (descriptor.fingerprint != request.precondition.sequence.fingerprint ||
	    descriptor.target != request.precondition.step.target.revision ||
	    (descriptor.step != {} &&
	     (descriptor.step.position != request.precondition.step.position ||
	      descriptor.step.total != request.precondition.step.total))) {
		return {}, false, .Stale_Observation
	}
	process_request := Process_Request {
		kind = request_kind,
		repository = request.precondition.repository,
		limits = request.limits,
	}
	if !process_request_is_valid(process_request) do return {}, false, .Invalid_Request
	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = process_request
	state.revision_sequence = request
	state.output_limit = request.limits.stdout_bytes
	set_state := revision_sequence_set_data(set)
	state.revision_sequence_targets, allocation_error = make(
		[dynamic]Revision_Sequence_Target, len(set_state.targets), allocator,
	)
	if allocation_error == nil {
		copy(state.revision_sequence_targets[:], set_state.targets[:])
		state.output, allocation_error = make([dynamic]u8, 0, 4 * KIBIBYTE, allocator)
	}
	if allocation_error == nil {
		state.diagnostic, allocation_error = make([dynamic]u8, 0, 4 * KIBIBYTE, allocator)
	}
	if allocation_error == nil {
		state.revision_sequence_output, allocation_error = make([dynamic]u8, 0, 4 * KIBIBYTE, allocator)
	}
	if allocation_error == nil {
		state.revision_sequence_diagnostic, allocation_error = make([dynamic]u8, 0, 4 * KIBIBYTE, allocator)
	}
	if allocation_error != nil {
		repository_process_data_destroy(state)
		return {}, false, .Allocation
	}
	state.revision_sequence_command = {
		"git", "symbolic-ref", "-q", "HEAD", "", "", "", "", "", "", "", "", "", "", "", "",
	}
	state.command_count = 4
	state.revision_sequence_phase = .Check_Head_Name
	state.child, state.failure = repository_process_start_revision_sequence_child(state)
	if state.failure != .None {
		repository_process_data_destroy(state)
		return {}, false, state.failure
	}
	state.deadline_ns = now_ns + request.limits.timeout_nanoseconds
	state.state = .Running
	return Repository_Process{state = state}, true, .None
}

@(private)
repository_process_advance_revision_sequence :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil ||
	   (state.request.kind != .Cherry_Pick_Repository && state.request.kind != .Revert_Repository) ||
	   state.revision_sequence_phase == .None {
		return .Invalid_Request
	}
	if state.revision_sequence_phase == .Prepare_Index_Tree ||
	   state.revision_sequence_phase == .Prepare_Index {
		return repository_process_advance_revision_sequence_precondition(state)
	}
	if !revision_sequence_request_is_valid(state.revision_sequence) do return .Invalid_Request
	precondition := state.revision_sequence.precondition
	switch state.revision_sequence_phase {
	case .Check_Head_Name:
		if state.exit_status != 0 || !repository_process_revision_sequence_output_matches(
			state, ref_name_string(&precondition.original_head.branch),
		) {
			return .Stale_Observation
		}
		return repository_process_start_revision_sequence_head_check(state)
	case .Check_Head_Object:
		expected := precondition.head.object
		if state.exit_status != 0 || !repository_process_revision_sequence_output_matches(
			state, revision_identity_string(&expected),
		) {
			return .Stale_Observation
		}
		state.revision_sequence_target_index = 0
		return repository_process_start_revision_sequence_target_check(state)
	case .Check_Target:
		if state.exit_status != 0 || !repository_process_revision_sequence_target_matches(state) {
			return .Stale_Observation
		}
		state.revision_sequence_target_index += 1
		if state.revision_sequence_target_index < u32(len(state.revision_sequence_targets)) {
			return repository_process_start_revision_sequence_target_check(state)
		}
		if precondition.action == .Skip || precondition.action == .Abort {
			return repository_process_start_revision_sequence_index_check(state)
		}
		return repository_process_start_revision_sequence_index_tree_check(state)
	case .Check_Index_Tree:
		expected := precondition.index_tree.object
		if state.exit_status != 0 || !repository_process_revision_sequence_output_matches(
			state, revision_identity_string(&expected),
		) {
			return .Stale_Observation
		}
		return repository_process_start_revision_sequence_index_check(state)
	case .Check_Index:
		fingerprint: Revision_Sequence_Index_Fingerprint
		if state.exit_status != 0 ||
		   !revision_sequence_index_fingerprint_compute(&fingerprint, state.output[:]) ||
		   fingerprint != precondition.index_fingerprint {
			return .Stale_Observation
		}
		state.revision_sequence_target_index = 0
		return repository_process_start_revision_sequence_mutation(state)
	case .Mutate:
		if failure := repository_process_retain_revision_sequence_output(state); failure != .None do return failure
		clear(&state.output)
		clear(&state.diagnostic)
		if state.exit_status != 0 do return .Process_Failed
		if state.revision_sequence_resume_remaining {
			state.revision_sequence_target_index += 1
			if state.revision_sequence_target_index < u32(len(state.revision_sequence_targets)) {
				return repository_process_start_revision_sequence_mutation(state)
			}
		} else if precondition.action == .Continue || precondition.action == .Skip {
			state.revision_sequence_target_index = precondition.step.position
			if state.revision_sequence_target_index < u32(len(state.revision_sequence_targets)) {
				state.revision_sequence_resume_remaining = true
				return repository_process_start_revision_sequence_mutation(state)
			}
		} else if precondition.action == .Start {
			state.revision_sequence_target_index += 1
			if state.revision_sequence_target_index < u32(len(state.revision_sequence_targets)) {
				return repository_process_start_revision_sequence_mutation(state)
			}
		}
		state.revision_sequence_phase = .None
		state.state = .Completed
		return .None
	case .None, .Prepare_Index_Tree, .Prepare_Index:
		return .Invalid_Request
	}
	return .Invalid_Request
}

@(private)
repository_process_advance_revision_sequence_precondition :: proc(
	state: ^Repository_Process_Data,
) -> Failure_Code {
	if state == nil ||
	   (state.revision_sequence_phase != .Prepare_Index_Tree &&
	    state.revision_sequence_phase != .Prepare_Index) {
		return .Invalid_Request
	}
	if state.exit_status != 0 do return .Process_Failed
	if state.revision_sequence_phase == .Prepare_Index_Tree {
		identity: Revision_Identity
		if len(state.output) < 2 || state.output[len(state.output) - 1] != '\n' ||
		   !revision_identity_assign(&identity, string(state.output[:len(state.output) - 1])) {
			return .Parse
		}
		state.revision_sequence.precondition.index_tree = {identity}
		repository_process_revision_sequence_reset_child(state)
		state.revision_sequence_command = {
			"git", "ls-files", "--stage", "-z", "", "", "", "", "", "", "", "", "", "", "", "",
		}
		state.command_count = 4
		return repository_process_start_revision_sequence_phase_child(state, .Prepare_Index)
	}
	if !revision_sequence_index_fingerprint_compute(
		&state.revision_sequence.precondition.index_fingerprint, state.output[:],
	) {
		return .Parse
	}
	if failure := revision_sequence_precondition_failure(state.revision_sequence.precondition);
	   failure != .None {
		return failure
	}
	state.revision_sequence_phase = .None
	state.state = .Completed
	return .None
}

@(private)
repository_process_start_revision_sequence_head_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.revision_sequence_phase != .Check_Head_Name do return .Invalid_Request
	repository_process_revision_sequence_reset_child(state)
	state.revision_sequence_command = {
		"git", "rev-parse", "--verify", "HEAD^{commit}", "", "", "", "", "", "", "", "", "", "", "", "",
	}
	state.command_count = 4
	return repository_process_start_revision_sequence_phase_child(state, .Check_Head_Object)
}

@(private)
repository_process_start_revision_sequence_target_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.revision_sequence_target_index >= u32(len(state.revision_sequence_targets)) {
		return .Invalid_Request
	}
	repository_process_revision_sequence_reset_child(state)
	target := state.revision_sequence_targets[state.revision_sequence_target_index].revision
	target_text := revision_identity_string(&target)
	if len(target_text) == 0 do return .Invalid_Request
	state.revision_sequence_command = {
		"git", "rev-list", "--parents", "-n", "1", target_text, "", "", "", "", "", "", "", "", "", "",
	}
	state.command_count = 6
	return repository_process_start_revision_sequence_phase_child(state, .Check_Target)
}

@(private)
repository_process_start_revision_sequence_index_tree_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.revision_sequence_phase != .Check_Target do return .Invalid_Request
	repository_process_revision_sequence_reset_child(state)
	state.revision_sequence_command = {
		"git", "write-tree", "", "", "", "", "", "", "", "", "", "", "", "", "", "",
	}
	state.command_count = 2
	return repository_process_start_revision_sequence_phase_child(state, .Check_Index_Tree)
}

@(private)
repository_process_start_revision_sequence_index_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil ||
	   (state.revision_sequence_phase != .Check_Index_Tree && state.revision_sequence_phase != .Check_Target) {
		return .Invalid_Request
	}
	repository_process_revision_sequence_reset_child(state)
	state.revision_sequence_command = {
		"git", "ls-files", "--stage", "-z", "", "", "", "", "", "", "", "", "", "", "", "",
	}
	state.command_count = 4
	return repository_process_start_revision_sequence_phase_child(state, .Check_Index)
}

@(private)
repository_process_start_revision_sequence_mutation :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || !revision_sequence_request_is_valid(state.revision_sequence) do return .Invalid_Request
	repository_process_revision_sequence_reset_child(state)
	precondition := state.revision_sequence.precondition
	command := "cherry-pick"
	if state.request.kind == .Revert_Repository {
		command = "revert"
	} else if state.request.kind != .Cherry_Pick_Repository {
		return .Invalid_Request
	}
	switch precondition.action {
	case .Start, .Continue, .Skip:
		if !state.revision_sequence_resume_remaining && precondition.action != .Start {
			if precondition.action == .Continue {
				if precondition.message.mode != .Git_Prepared do return .Action_Unavailable
				state.revision_sequence_command = {
					"git", "-c", "core.editor=true", command, "--continue", "", "", "", "", "", "", "", "", "", "", "",
				}
				state.command_count = 5
			} else {
				state.revision_sequence_command = {
					"git", command, "--skip", "", "", "", "", "", "", "", "", "", "", "", "", "",
				}
				state.command_count = 3
			}
			break
		}
		if precondition.action == .Start && precondition.message.mode != .Preserve_Selected ||
		   state.revision_sequence_target_index >= u32(len(state.revision_sequence_targets)) {
			return .Action_Unavailable
		}
		target := state.revision_sequence_targets[state.revision_sequence_target_index]
		revision := target.revision
		revision_text := revision_identity_string(&revision)
		if target.mainline == {} {
			state.revision_sequence_command = {
				"git", "-c", "core.editor=true", command, "--no-edit", "--", revision_text,
				"", "", "", "", "", "", "", "", "",
			}
			state.command_count = 7
		} else {
			mainline, formatted := repository_process_revision_sequence_mainline_argument(
				&state.revision_sequence_mainline, target.mainline.number,
			)
			if !formatted do return .Invalid_Request
			state.revision_sequence_command = {
				"git", "-c", "core.editor=true", command, "--no-edit", "-m", mainline, "--", revision_text,
				"", "", "", "", "", "", "",
			}
			state.command_count = 9
		}
	case .Abort:
		state.revision_sequence_command = {
			"git", command, "--abort", "", "", "", "", "", "", "", "", "", "", "", "", "",
		}
		state.command_count = 3
	case .Invalid:
		return .Invalid_Request
	}
	state.child, state.failure = repository_process_start_revision_sequence_child(state)
	if state.failure != .None do return state.failure
	state.revision_sequence_phase = .Mutate
	state.revision_sequence_started = true
	return .None
}

@(private)
repository_process_start_revision_sequence_phase_child :: proc(
	state: ^Repository_Process_Data,
	phase: Revision_Sequence_Process_Phase,
) -> Failure_Code {
	if state == nil || phase == .None do return .Invalid_Request
	state.child, state.failure = repository_process_start_revision_sequence_child(state)
	if state.failure == .None do state.revision_sequence_phase = phase
	return state.failure
}

@(private)
repository_process_start_revision_sequence_child :: proc(
	state: ^Repository_Process_Data,
) -> (Local_Child, Failure_Code) {
	if state == nil || state.command_count == 0 ||
	   int(state.command_count) > len(state.revision_sequence_command) {
		return {}, .Invalid_Request
	}
	if state.termination.reason != .None {
		return {}, state.termination.reason == .Timeout ? .Timeout : .Cancelled
	}
	repository := state.request.repository
	child, failure := local_child_start(
		state.revision_sequence_command[:int(state.command_count)],
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
repository_process_revision_sequence_exit_is_expected :: proc(
	state: ^Repository_Process_Data,
	exit_status: i32,
) -> bool {
	return state != nil &&
	       (state.request.kind == .Cherry_Pick_Repository || state.request.kind == .Revert_Repository) &&
	       exit_status != 0 &&
	       state.revision_sequence_phase == .Mutate
}

@(private)
repository_process_revision_sequence_output_matches :: proc(
	state: ^Repository_Process_Data,
	expected: string,
) -> bool {
	return state != nil && len(expected) > 0 && len(state.output) == len(expected) + 1 &&
	       state.output[len(state.output) - 1] == '\n' && string(state.output[:len(expected)]) == expected
}

@(private)
repository_process_revision_sequence_target_matches :: proc(state: ^Repository_Process_Data) -> bool {
	if state == nil || state.revision_sequence_target_index >= u32(len(state.revision_sequence_targets)) ||
	   len(state.output) < 2 || state.output[len(state.output) - 1] != '\n' {
		return false
	}
	target := state.revision_sequence_targets[state.revision_sequence_target_index]
	line := state.output[:len(state.output) - 1]
	token_start := 0
	token_index := 0
	parents: u32
	for index := 0; index <= len(line); index += 1 {
		if index < len(line) && line[index] != ' ' do continue
		if index == token_start do return false
		token := string(line[token_start:index])
		if token_index == 0 {
			revision := target.revision
			if token != revision_identity_string(&revision) do return false
		} else {
			parents += 1
			if target.mainline.number == u8(token_index) {
				parent := target.mainline.parent
				if token != revision_identity_string(&parent) do return false
			}
		}
		token_index += 1
		token_start = index + 1
	}
	return parents == u32(target.parent_count) &&
	       (target.mainline == {} || target.mainline.number <= u8(parents))
}

@(private)
repository_process_revision_sequence_find_target :: proc(
	set: ^Revision_Sequence_Set,
	revision: Revision_Identity,
) -> (Revision_Sequence_Target, u32, bool) {
	descriptor, described := revision_sequence_set_descriptor(set)
	if !described do return {}, 0, false
	for index in 0 ..< descriptor.commits {
		target, found := revision_sequence_set_target(set, index)
		if found && target.revision == revision do return target, index + 1, true
	}
	return {}, 0, false
}

@(private)
repository_process_retain_revision_sequence_output :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil do return .Invalid_Request
	if u64(len(state.revision_sequence_output)) + u64(len(state.output)) > state.request.limits.stdout_bytes ||
	   u64(len(state.revision_sequence_diagnostic)) + u64(len(state.diagnostic)) >
	   state.request.limits.diagnostic_bytes {
		return .Output_Limit
	}
	if _, allocation_error := append(&state.revision_sequence_output, ..state.output[:]); allocation_error != nil {
		return .Allocation
	}
	if _, allocation_error := append(&state.revision_sequence_diagnostic, ..state.diagnostic[:]); allocation_error != nil {
		return .Allocation
	}
	return .None
}

@(private)
repository_process_revision_sequence_reset_child :: proc(state: ^Repository_Process_Data) {
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
repository_process_revision_sequence_mainline_argument :: proc(
	storage: ^[4]u8,
	number: u8,
) -> (string, bool) {
	if storage == nil || number == 0 do return "", false
	storage^ = {}
	remaining := u32(number)
	digits: [3]u8
	count := 0
	for remaining > 0 {
		digits[count] = u8('0') + u8(remaining % 10)
		remaining /= 10
		count += 1
	}
	for index in 0 ..< count do storage[index] = digits[count - index - 1]
	return string(storage[:count]), true
}

/* repository_process_take_revision_sequence_precondition copies one exact observed action boundary. */
repository_process_take_revision_sequence_precondition :: proc(
	process: ^Repository_Process,
) -> (Revision_Sequence_Precondition, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || state.state != .Completed ||
	   (state.request.kind != .Cherry_Pick_Repository && state.request.kind != .Revert_Repository) ||
	   state.revision_sequence_phase != .None {
		return {}, false, .Invalid_Request
	}
	precondition := state.revision_sequence.precondition
	if failure := revision_sequence_precondition_failure(precondition); failure != .None {
		return {}, false, failure
	}
	return precondition, true, .None
}

/* repository_process_take_cherry_pick copies one bounded child outcome after execution. */
repository_process_take_cherry_pick :: proc(
	process: ^Repository_Process,
	allocator := context.allocator,
) -> (Revision_Sequence_Result, bool, Failure_Code) {
	return repository_process_take_revision_sequence(process, .Cherry_Pick_Repository, allocator)
}

/* repository_process_take_revert copies one bounded child outcome after execution. */
repository_process_take_revert :: proc(
	process: ^Repository_Process,
	allocator := context.allocator,
) -> (Revision_Sequence_Result, bool, Failure_Code) {
	return repository_process_take_revision_sequence(process, .Revert_Repository, allocator)
}

@(private)
repository_process_take_revision_sequence :: proc(
	process: ^Repository_Process,
	request_kind: Request_Kind,
	allocator: runtime.Allocator,
) -> (Revision_Sequence_Result, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || (state.state != .Completed && state.state != .Failed) ||
	   state.request.kind != request_kind ||
	   !revision_sequence_request_is_valid(state.revision_sequence) {
		return {}, false, .Invalid_Request
	}
	if !state.revision_sequence_started && state.failure != .Cancelled do return {}, false, state.failure
	if state.revision_sequence_started && state.revision_sequence_phase == .Mutate {
		if retain_failure := repository_process_retain_revision_sequence_output(state); retain_failure != .None {
			return {}, false, retain_failure
		}
		clear(&state.output)
		clear(&state.diagnostic)
	}
	return revision_sequence_result_open(
		state.revision_sequence,
		state.revision_sequence_started,
		state.exit_status,
		state.revision_sequence_output[:],
		state.revision_sequence_diagnostic[:],
		state.failure,
		allocator,
	)
}
