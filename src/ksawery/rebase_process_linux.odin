// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery

import "core:os"

@(private)
Rebase_Process_Phase :: enum u8 {
	None,
	Prepare_Index_Tree,
	Prepare_Index,
	Check_Head_Name,
	Check_Head_Object,
	Check_Branch,
	Check_Base,
	Check_Index,
	Check_Index_Tree,
	Check_Status,
	Check_Step,
	Check_Operation,
	Mutate,
}

/* repository_process_start_rebase_precondition captures exact index identities for confirmation. */
repository_process_start_rebase_precondition :: proc(
	status: ^Status_Observation,
	refs: ^Ref_Observation,
	sequence: ^Sequence_Observation,
	base: Ref_Identity,
	action: Rebase_Action,
	mode: Rebase_Mode,
	plan: Rebase_Reviewed_Plan,
	lineage: Rebase_Precondition,
	step: Rebase_Replay_Step,
	editor: Rebase_Editor_State,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil || action == .Invalid || mode == .Invalid ||
	   !rebase_editor_state_is_valid(editor) {
		return {}, false, .Invalid_Request
	}
	status_descriptor, status_described := status_observation_descriptor(status)
	refs_descriptor, refs_described := ref_observation_descriptor(refs)
	sequence_descriptor, sequence_described := sequence_observation_descriptor(sequence)
	if !status_described || !refs_described || !sequence_described ||
	   status_descriptor.repository != refs_descriptor.repository ||
	   status_descriptor.repository != sequence_descriptor.repository ||
	   refs_descriptor.state == .Truncated {
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
	precondition := Rebase_Precondition {
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
		mode = mode,
		plan = plan,
		plan_limits = DEFAULT_REBASE_PLAN_LIMITS,
	}
	if action == .Start {
		if refs_descriptor.head.state != .Symbolic || !ref_identity_is_valid(base) ||
		   base.object_type != .Commit || base.repository != precondition.repository ||
		   base.generation != precondition.ref_generation {
			return {}, false, .Ref_Unavailable
		}
		precondition.branch = refs_descriptor.head.branch
		precondition.old_tip = refs_descriptor.head.object
		precondition.base = {reference = base, revision = base.object}
	} else {
		if !rebase_precondition_is_valid(lineage) || lineage.action != .Start ||
		   lineage.repository != precondition.repository ||
		   sequence_descriptor.kind != .Rebase ||
		   (sequence_descriptor.state != .Active && sequence_descriptor.state != .Conflicted) ||
		   sequence_descriptor.target != step.revision ||
		   sequence_descriptor.step.position != step.position ||
		   sequence_descriptor.step.total != step.total {
			return {}, false, .Action_Unavailable
		}
		branch, branch_found := repository_process_rebase_find_ref(refs, lineage.branch.name)
		base_ref, base_found := repository_process_rebase_find_ref(refs, lineage.base.reference.name)
		if !branch_found || !base_found || branch.object != lineage.old_tip ||
		   base_ref.object != lineage.base.revision {
			return {}, false, .Stale_Observation
		}
		precondition.branch = branch
		precondition.repository_operation = .Rebasing
		precondition.old_tip = lineage.old_tip
		precondition.base = {reference = base_ref, revision = lineage.base.revision}
		precondition.sequence = {
			generation = sequence_descriptor.generation,
			fingerprint = sequence_descriptor.fingerprint,
		}
		precondition.step = step
		precondition.mode = lineage.mode
		precondition.plan = lineage.plan
		precondition.plan_limits = lineage.plan_limits
	}
	process_request := Process_Request {
		kind = .Rebase_Repository,
		repository = precondition.repository,
		limits = DEFAULT_PROCESS_LIMITS,
	}
	if !process_request_is_valid(process_request) do return {}, false, .Invalid_Request
	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = process_request
	state.rebase_precondition = precondition
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
		state.rebase_command = {"git", "write-tree", "", "", "", "", "", "", "", "", "", "", "", "", "", ""}
		state.command_count = 2
		state.rebase_phase = .Prepare_Index_Tree
	} else {
		state.rebase_command = {"git", "ls-files", "--stage", "-z", "", "", "", "", "", "", "", "", "", "", "", ""}
		state.command_count = 4
		state.rebase_phase = .Prepare_Index
	}
	state.child, state.failure = repository_process_start_rebase_child(state)
	if state.failure != .None {
		repository_process_data_destroy(state)
		return {}, false, state.failure
	}
	state.deadline_ns = now_ns + process_request.limits.timeout_nanoseconds
	state.state = .Running
	return Repository_Process{state = state}, true, .None
}

/* repository_process_start_rebase rechecks exact live identities before one confirmed replay action. */
repository_process_start_rebase :: proc(
	sequence: ^Sequence_Observation,
	current: Rebase_Precondition,
	request: Rebase_Request,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil do return {}, false, .Invalid_Request
	revalidated, failure := rebase_request_revalidate(current, request)
	if !revalidated do return {}, false, failure
	descriptor, described := sequence_observation_descriptor(sequence)
	if !described || descriptor.repository != current.repository ||
	   descriptor.generation != current.sequence_generation ||
	   descriptor.state != current.sequence_state {
		return {}, false, .Stale_Observation
	}
	if current.action == .Start {
		if descriptor.kind != .None || descriptor.state != .Inactive do return {}, false, .Action_Unavailable
	} else if descriptor.kind != .Rebase ||
	          (descriptor.state != .Active && descriptor.state != .Conflicted) ||
	          descriptor.fingerprint != current.sequence.fingerprint ||
	          descriptor.target != current.step.revision ||
	          descriptor.step.position != current.step.position ||
	          descriptor.step.total != current.step.total {
		return {}, false, .Stale_Observation
	}
	process_request := Process_Request {
		kind = .Rebase_Repository,
		repository = request.precondition.repository,
		limits = request.limits,
	}
	if !process_request_is_valid(process_request) do return {}, false, .Invalid_Request
	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = process_request
	state.rebase = request
	state.output_limit = request.limits.stdout_bytes
	state.output, allocation_error = make([dynamic]u8, 0, int(min(state.output_limit, 64 * KIBIBYTE)), allocator)
	if allocation_error == nil {
		state.diagnostic, allocation_error = make(
			[dynamic]u8, 0, int(min(request.limits.diagnostic_bytes, 16 * KIBIBYTE)), allocator,
		)
	}
	if allocation_error != nil {
		repository_process_data_destroy(state)
		return {}, false, .Allocation
	}
	if current.action == .Start {
		state.rebase_command = {"git", "symbolic-ref", "--quiet", "HEAD", "", "", "", "", "", "", "", "", "", "", "", ""}
		state.command_count = 4
		state.rebase_phase = .Check_Head_Name
	} else {
		state.rebase_command = {"git", "rev-parse", "--verify", "--quiet", "HEAD^{commit}", "", "", "", "", "", "", "", "", "", "", ""}
		state.command_count = 5
		state.rebase_phase = .Check_Head_Object
	}
	state.child, state.failure = repository_process_start_rebase_child(state)
	if state.failure != .None {
		repository_process_data_destroy(state)
		return {}, false, state.failure
	}
	state.deadline_ns = now_ns + request.limits.timeout_nanoseconds
	state.state = .Running
	return Repository_Process{state = state}, true, .None
}

@(private)
repository_process_advance_rebase :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.request.kind != .Rebase_Repository || state.rebase_phase == .None {
		return .Invalid_Request
	}
	if state.rebase_phase == .Prepare_Index_Tree || state.rebase_phase == .Prepare_Index {
		return repository_process_advance_rebase_precondition(state)
	}
	if !rebase_request_is_valid(state.rebase) do return .Invalid_Request
	precondition := state.rebase.precondition
	switch state.rebase_phase {
	case .Check_Head_Name:
		name := precondition.branch.name
		if state.exit_status != 0 || !repository_process_rebase_output_matches(state, ref_name_string(&name)) {
			return .Stale_Observation
		}
		return repository_process_start_rebase_head_check(state)
	case .Check_Head_Object:
		head := precondition.head.object
		if state.exit_status != 0 || !repository_process_rebase_output_matches(
			state,
			revision_identity_string(&head),
		) {
			return .Stale_Observation
		}
		return repository_process_start_rebase_branch_check(state)
	case .Check_Branch:
		old_tip := precondition.old_tip
		if state.exit_status != 0 || !repository_process_rebase_output_matches(
			state,
			revision_identity_string(&old_tip),
		) {
			return .Stale_Observation
		}
		return repository_process_start_rebase_base_check(state)
	case .Check_Base:
		base := precondition.base.revision
		if state.exit_status != 0 || !repository_process_rebase_output_matches(
			state,
			revision_identity_string(&base),
		) {
			return .Stale_Observation
		}
		return repository_process_start_rebase_index_check(state)
	case .Check_Index:
		if state.exit_status != 0 do return .Process_Failed
		fingerprint: Rebase_Index_Fingerprint
		if !rebase_index_fingerprint_compute(&fingerprint, state.output[:]) do return .Parse
		if fingerprint != precondition.index_fingerprint do return .Stale_Observation
		if precondition.action == .Start || precondition.action == .Continue {
			return repository_process_start_rebase_index_tree_check(state)
		}
		if precondition.action == .Skip do return repository_process_start_rebase_step_check(state)
		return repository_process_start_rebase_mutation(state)
	case .Check_Index_Tree:
		index_tree := precondition.index_tree.object
		if state.exit_status != 0 || !repository_process_rebase_output_matches(
			state,
			revision_identity_string(&index_tree),
		) {
			return .Stale_Observation
		}
		return repository_process_start_rebase_status_check(state)
	case .Check_Status:
		if state.exit_status != 0 do return .Process_Failed
		if len(state.output) != 0 do return .Action_Unavailable
		if precondition.action == .Continue do return repository_process_start_rebase_step_check(state)
		state.rebase_operation_marker = 0
		return repository_process_start_rebase_operation_check(state)
	case .Check_Step:
		step := precondition.step.revision
		if state.exit_status != 0 || !repository_process_rebase_output_matches(
			state,
			revision_identity_string(&step),
		) {
			return .Stale_Observation
		}
		return repository_process_start_rebase_mutation(state)
	case .Check_Operation:
		if state.exit_status != 0 do return .Process_Failed
		active, inspected := repository_process_rebase_operation_is_active(state)
		if !inspected do return .Parse
		if active do return .Action_Unavailable
		state.rebase_operation_marker += 1
		if int(state.rebase_operation_marker) < len(COMMIT_OPERATION_MARKERS) {
			return repository_process_start_rebase_operation_check(state)
		}
		return repository_process_start_rebase_mutation(state)
	case .Mutate:
		if state.exit_status != 0 {
			state.failure = .Process_Failed
			state.rebase_phase = .None
			state.state = .Failed
			return .None
		}
		state.rebase_phase = .None
		state.state = .Completed
		return .None
	case .None, .Prepare_Index_Tree, .Prepare_Index:
		return .Invalid_Request
	}
	return .Invalid_Request
}

@(private)
repository_process_advance_rebase_precondition :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || (state.rebase_phase != .Prepare_Index_Tree && state.rebase_phase != .Prepare_Index) {
		return .Invalid_Request
	}
	if state.exit_status != 0 do return .Process_Failed
	if state.rebase_phase == .Prepare_Index_Tree {
		identity: Revision_Identity
		if len(state.output) < 2 || state.output[len(state.output) - 1] != '\n' ||
		   !revision_identity_assign(&identity, string(state.output[:len(state.output) - 1])) {
			return .Parse
		}
		state.rebase_precondition.index_tree = {identity}
		repository_process_rebase_reset_child(state)
		state.rebase_command = {"git", "ls-files", "--stage", "-z", "", "", "", "", "", "", "", "", "", "", "", ""}
		state.command_count = 4
		return repository_process_start_rebase_phase_child(state, .Prepare_Index)
	}
	if !rebase_index_fingerprint_compute(&state.rebase_precondition.index_fingerprint, state.output[:]) {
		return .Parse
	}
	if failure := rebase_precondition_failure(state.rebase_precondition); failure != .None do return failure
	state.rebase_phase = .None
	state.state = .Completed
	return .None
}

@(private)
repository_process_start_rebase_head_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.rebase_phase != .Check_Head_Name do return .Invalid_Request
	repository_process_rebase_reset_child(state)
	state.rebase_command = {"git", "rev-parse", "--verify", "--quiet", "HEAD^{commit}", "", "", "", "", "", "", "", "", "", "", ""}
	state.command_count = 5
	return repository_process_start_rebase_phase_child(state, .Check_Head_Object)
}

@(private)
repository_process_start_rebase_branch_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.rebase_phase != .Check_Head_Object do return .Invalid_Request
	repository_process_rebase_reset_child(state)
	name := state.rebase.precondition.branch.name
	argument, assigned := repository_process_rebase_revision_argument(state, &name)
	if !assigned do return .Invalid_Request
	state.rebase_command = {"git", "rev-parse", "--verify", "--quiet", argument, "", "", "", "", "", "", "", "", "", "", ""}
	state.command_count = 5
	return repository_process_start_rebase_phase_child(state, .Check_Branch)
}

@(private)
repository_process_start_rebase_base_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.rebase_phase != .Check_Branch do return .Invalid_Request
	repository_process_rebase_reset_child(state)
	name := state.rebase.precondition.base.reference.name
	argument, assigned := repository_process_rebase_revision_argument(state, &name)
	if !assigned do return .Invalid_Request
	state.rebase_command = {"git", "rev-parse", "--verify", "--quiet", argument, "", "", "", "", "", "", "", "", "", "", ""}
	state.command_count = 5
	return repository_process_start_rebase_phase_child(state, .Check_Base)
}

@(private)
repository_process_start_rebase_index_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.rebase_phase != .Check_Base do return .Invalid_Request
	repository_process_rebase_reset_child(state)
	state.rebase_command = {"git", "ls-files", "--stage", "-z", "", "", "", "", "", "", "", "", "", "", "", ""}
	state.command_count = 4
	return repository_process_start_rebase_phase_child(state, .Check_Index)
}

@(private)
repository_process_start_rebase_status_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.rebase_phase != .Check_Index_Tree do return .Invalid_Request
	repository_process_rebase_reset_child(state)
	if state.rebase.precondition.action == .Start {
		state.rebase_command = {"git", "status", "--porcelain=v2", "-z", "--untracked-files=all", "", "", "", "", "", "", "", "", "", "", ""}
		state.command_count = 5
	} else {
		state.rebase_command = {"git", "ls-files", "--unmerged", "-z", "", "", "", "", "", "", "", "", "", "", "", ""}
		state.command_count = 4
	}
	return repository_process_start_rebase_phase_child(state, .Check_Status)
}

@(private)
repository_process_start_rebase_index_tree_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.rebase_phase != .Check_Index do return .Invalid_Request
	repository_process_rebase_reset_child(state)
	state.rebase_command = {"git", "write-tree", "", "", "", "", "", "", "", "", "", "", "", "", "", ""}
	state.command_count = 2
	return repository_process_start_rebase_phase_child(state, .Check_Index_Tree)
}

@(private)
repository_process_start_rebase_step_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || (state.rebase_phase != .Check_Index && state.rebase_phase != .Check_Status) {
		return .Invalid_Request
	}
	repository_process_rebase_reset_child(state)
	state.rebase_command = {"git", "rev-parse", "--verify", "--quiet", "REBASE_HEAD^{commit}", "", "", "", "", "", "", "", "", "", "", ""}
	state.command_count = 5
	return repository_process_start_rebase_phase_child(state, .Check_Step)
}

@(private)
repository_process_start_rebase_operation_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || (state.rebase_phase != .Check_Status && state.rebase_phase != .Check_Operation) ||
	   int(state.rebase_operation_marker) >= len(COMMIT_OPERATION_MARKERS) {
		return .Invalid_Request
	}
	repository_process_rebase_reset_child(state)
	markers := COMMIT_OPERATION_MARKERS
	marker := markers[int(state.rebase_operation_marker)]
	state.rebase_command = {"git", "rev-parse", "--git-path", marker, "", "", "", "", "", "", "", "", "", "", "", ""}
	state.command_count = 4
	return repository_process_start_rebase_phase_child(state, .Check_Operation)
}

@(private)
repository_process_start_rebase_mutation :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || !rebase_request_is_valid(state.rebase) do return .Invalid_Request
	repository_process_rebase_reset_child(state)
	precondition := state.rebase.precondition
	base := precondition.base.revision
	base_text := revision_identity_string(&base)
	switch precondition.action {
	case .Start:
		if precondition.mode == .Ordinary {
			state.rebase_command = {"git", "-c", "core.editor=true", "-c", "sequence.editor=true", "rebase", "--no-autostash", "--no-update-refs", "--", base_text, "", "", "", "", "", ""}
			state.command_count = 10
		} else if precondition.mode == .Autosquash {
			state.rebase_command = {"git", "-c", "core.editor=true", "-c", "sequence.editor=true", "rebase", "--interactive", "--autosquash", "--no-autostash", "--no-update-refs", "--", base_text, "", "", "", ""}
			state.command_count = 12
		} else {
			return .Invalid_Request
		}
	case .Continue:
		state.rebase_command = {"git", "-c", "core.editor=true", "-c", "sequence.editor=true", "rebase", "--continue", "", "", "", "", "", "", "", "", ""}
		state.command_count = 7
	case .Skip:
		state.rebase_command = {"git", "rebase", "--skip", "", "", "", "", "", "", "", "", "", "", "", "", ""}
		state.command_count = 3
	case .Abort:
		state.rebase_command = {"git", "rebase", "--abort", "", "", "", "", "", "", "", "", "", "", "", "", ""}
		state.command_count = 3
	case .Invalid:
		return .Invalid_Request
	}
	state.child, state.failure = repository_process_start_rebase_child(state)
	if state.failure != .None do return state.failure
	state.rebase_phase = .Mutate
	state.rebase_started = true
	return .None
}

@(private)
repository_process_start_rebase_phase_child :: proc(
	state: ^Repository_Process_Data,
	phase: Rebase_Process_Phase,
) -> Failure_Code {
	if state == nil || phase == .None do return .Invalid_Request
	state.child, state.failure = repository_process_start_rebase_child(state)
	if state.failure == .None do state.rebase_phase = phase
	return state.failure
}

@(private)
repository_process_rebase_revision_argument :: proc(
	state: ^Repository_Process_Data,
	name: ^Ref_Name,
) -> (string, bool) {
	if state == nil || name == nil || !ref_name_is_valid(name^) do return "", false
	text := ref_name_string(name)
	suffix := "^{commit}"
	required := len(text) + len(suffix)
	if required > len(state.rebase_argument) do return "", false
	state.rebase_argument = {}
	copy(state.rebase_argument[:len(text)], transmute([]u8)text)
	copy(state.rebase_argument[len(text):required], transmute([]u8)suffix)
	return string(state.rebase_argument[:required]), true
}

@(private)
repository_process_rebase_output_matches :: proc(state: ^Repository_Process_Data, expected: string) -> bool {
	return state != nil && len(expected) > 0 && len(state.output) == len(expected) + 1 &&
	       state.output[len(state.output) - 1] == '\n' && string(state.output[:len(expected)]) == expected
}

@(private)
repository_process_rebase_operation_is_active :: proc(state: ^Repository_Process_Data) -> (bool, bool) {
	if state == nil || state.rebase_phase != .Check_Operation ||
	   int(state.rebase_operation_marker) >= len(COMMIT_OPERATION_MARKERS) ||
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
repository_process_start_rebase_child :: proc(state: ^Repository_Process_Data) -> (Local_Child, Failure_Code) {
	if state == nil || state.command_count == 0 || int(state.command_count) > len(state.rebase_command) {
		return {}, .Invalid_Request
	}
	if state.termination.reason != .None {
		return {}, state.termination.reason == .Timeout ? .Timeout : .Cancelled
	}
	repository := state.request.repository
	child, failure := local_child_start(
		state.rebase_command[:int(state.command_count)],
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
repository_process_rebase_exit_is_expected :: proc(state: ^Repository_Process_Data, exit_status: i32) -> bool {
	return state != nil && state.request.kind == .Rebase_Repository && exit_status != 0 &&
	       state.rebase_phase == .Mutate
}

@(private)
repository_process_rebase_find_ref :: proc(
	refs: ^Ref_Observation,
	name: Ref_Name,
) -> (Ref_Identity, bool) {
	count, counted := ref_observation_ref_count(refs)
	if !counted do return {}, false
	for index in 0 ..< count {
		candidate, found := ref_observation_ref(refs, index)
		if !found do return {}, false
		if candidate.name == name do return candidate, true
	}
	return {}, false
}

@(private)
repository_process_rebase_reset_child :: proc(state: ^Repository_Process_Data) {
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

/* repository_process_take_rebase_precondition returns one exact prepared confirmation boundary. */
repository_process_take_rebase_precondition :: proc(
	process: ^Repository_Process,
) -> (Rebase_Precondition, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || state.state != .Completed || state.request.kind != .Rebase_Repository ||
	   state.rebase_phase != .None {
		return {}, false, .Invalid_Request
	}
	if failure := rebase_precondition_failure(state.rebase_precondition); failure != .None {
		return {}, false, failure
	}
	return state.rebase_precondition, true, .None
}

/* repository_process_take_rebase copies one started or pre-start-cancelled replay outcome. */
repository_process_take_rebase :: proc(
	process: ^Repository_Process,
	allocator := context.allocator,
) -> (Rebase_Result, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || (state.state != .Completed && state.state != .Failed) ||
	   state.request.kind != .Rebase_Repository || !rebase_request_is_valid(state.rebase) {
		return {}, false, .Invalid_Request
	}
	if !state.rebase_started && state.failure != .Cancelled do return {}, false, state.failure
	return rebase_result_open(
		state.rebase,
		state.rebase_started,
		state.exit_status,
		state.output[:],
		state.diagnostic[:],
		state.failure,
		allocator,
	)
}
