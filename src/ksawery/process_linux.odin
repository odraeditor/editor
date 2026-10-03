// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery

import "base:runtime"
import "core:crypto/sha2"
import "core:io"
import "core:os"
import "core:strings"
import "core:sys/linux"

/* Repository_Process owns one bounded noninteractive repository child. */
Repository_Process :: struct {
	state: rawptr,
}

/* Repository_Process_State reports the lifetime of one repository request. */
Repository_Process_State :: enum u8 {
	Invalid,
	Running,
	Completed,
	Failed,
	Closed,
}

/* Repository_Process_Poll reports one bounded child-maintenance step. */
Repository_Process_Poll :: struct {
	state:            Repository_Process_State,
	read_bytes:       u64,
	diagnostic_bytes: u64,
	exit_status:      i32,
	failure:          Failure_Code,
}

/* Repository_Process_Usage reports retained bounded process payload. */
Repository_Process_Usage :: struct {
	input_bytes:      u64,
	output_bytes:     u64,
	diagnostic_bytes: u64,
}

@(private)
Commit_Process_Phase :: enum u8 {
	None,
	Observe_Head,
	Observe_Index_Tree,
	Check_Head,
	Check_Index_Tree,
	Check_Operation,
	Commit,
	Observe_Result_Head,
}

@(private)
Ref_Process_Phase :: enum u8 {
	None,
	Observe_Refs,
	Observe_Remotes,
	Observe_Head,
}

@(private)
Sequence_Process_Phase :: enum u8 {
	None,
	Resolve_Git_Directory,
	Observe_Status,
}

@(private)
Inspection_Process_Phase :: enum u8 {
	None,
	Check_Stash,
	Check_Worktree,
	Action,
}

@(private)
Remote_Configuration_Process_Phase :: enum u8 {
	None,
	Observe_URL,
	Observe_Fetch_Refspec,
	Check_URL,
	Check_Fetch_Refspec,
	Check_Operation,
	Fetch,
}

@(private)
Push_Process_Phase :: enum u8 {
	None,
	Observe_URL,
	Observe_Push_URL,
	Check_URL,
	Check_Push_URL,
	Check_Source,
	Check_Tracking_Remote,
	Check_Tracking_Merge,
	Check_Operation,
	Push,
}

@(private)
COMMIT_OPERATION_MARKERS :: [7]string {
	"MERGE_HEAD",
	"rebase-merge",
	"rebase-apply",
	"CHERRY_PICK_HEAD",
	"REVERT_HEAD",
	"BISECT_LOG",
	"AM_HEAD",
}

@(private)
Sequence_Marker :: enum u8 {
	Merge,
	Rebase_Merge,
	Rebase_Apply,
	Cherry_Pick,
	Revert,
	Bisect,
	Apply,
	Sequencer,
}

@(private)
SEQUENCE_MARKER_PATHS :: [8]string {
	"MERGE_HEAD",
	"rebase-merge",
	"rebase-apply",
	"CHERRY_PICK_HEAD",
	"REVERT_HEAD",
	"BISECT_LOG",
	"rebase-apply/applying",
	"sequencer",
}

@(private)
HISTORY_PRETTY_FORMAT :: "--pretty=format:%x1e%H%x00%P%x00%an%x00%ae%x00%aI%x00%cI%x00%s%x00%b%x00"

@(private)
REVISION_DETAIL_PRETTY_FORMAT :: "--format=%x1e%H%x00%P%x00%an%x00%ae%x00%aI%x00%cn%x00%ce%x00%cI%x00%s%x00%B%x00%G?%x00%GS%x00"

@(private)
REVISION_RANGE_PRETTY_FORMAT :: "--format=%x1e%H%x00%s%x00"

@(private)
REF_PRETTY_FORMAT :: "--format=%(refname)%00%(objectname)%00%(objecttype)%00%(upstream)%00%(upstream:track)%00%(HEAD)%00"

@(private)
Local_Child :: struct {
	process: os.Process,
	stdin:   ^os.File,
	stdout:  ^os.File,
	stderr:  ^os.File,
	live:    bool,
	reaped:  bool,
}

@(private)
Repository_Process_Data :: struct {
	child:             Local_Child,
	association:       Repository_Process_Association,
	associated:        bool,
	public_phase:      Repository_Process_Phase,
	phase_generation:  u32,
	lifecycle_timing:  Process_Record_Timing,
	child_evidence:    Repository_Child_Evidence,
	termination:       Repository_Process_Termination_Evidence,
	failure_evidence:  Repository_Process_Failure_Evidence,
	children_started:  u32,
	children_reaped:   u32,
	output_truncated:  bool,
	diagnostic_truncated: bool,
	request:           Process_Request,
	index_action:      Index_Action_Request,
	partial_action:    Partial_Index_Action_Request_Descriptor,
	grouped_action:    Grouped_Index_Action_Request_Descriptor,
	discard_action:    Discard_Action_Request,
	commit:            Commit_Request,
	fetch:             Fetch_Request,
	push:              Push_Request,
	branch:            Branch_Request,
	tag:               Tag_Request,
	merge:             Merge_Request,
	merge_precondition: Merge_Precondition,
	rebase:            Rebase_Request,
	rebase_precondition: Rebase_Precondition,
	revision_sequence: Revision_Sequence_Request,
	revision_sequence_targets: [dynamic]Revision_Sequence_Target,
	manual_bisect:      Bisect_Request,
	manual_bisect_precondition: Bisect_Precondition,
	manual_bisect_good: [dynamic]Revision_Identity,
	conflict_resolution: Conflict_Resolution_Request,
	conflict_precondition: Conflict_Resolution_Precondition,
	extension_operation_submission: Extension_Operation_Submission,
	extension_operation: Extension_Operation_Plan,
	extension_operation_arguments: [dynamic]Extension_Operation_Argument,
	extension_operation_command: [MAX_EXTENSION_OPERATION_ARGUMENTS + 1]string,
	raw_repository_command: Raw_Repository_Command_Request,
	raw_command_arguments: [MAX_RAW_REPOSITORY_COMMAND_ARGUMENTS + 1]string,
	raw_command_argument_storage: [MAX_RAW_REPOSITORY_COMMAND_BYTES]u8,
	remote_configuration: Remote_Identity,
	remote_configuration_phase: Remote_Configuration_Process_Phase,
	remote_configuration_hash: sha2.Context_256,
	remote_configuration_digest: Remote_Configuration_Fingerprint,
	fetch_started:     bool,
	fetch_operation_marker: u8,
	push_configuration: Remote_Identity,
	push_phase:        Push_Process_Phase,
	push_configuration_hash: sha2.Context_256,
	push_configuration_digest: Remote_Configuration_Fingerprint,
	push_started:      bool,
	push_operation_marker: u8,
	branch_phase:      Branch_Process_Phase,
	branch_started:    bool,
	branch_operation_marker: u8,
	tag_phase:         Tag_Process_Phase,
	tag_started:       bool,
	tag_operation_marker: u8,
	merge_phase:       Merge_Process_Phase,
	merge_started:     bool,
	merge_operation_marker: u8,
	rebase_phase:      Rebase_Process_Phase,
	rebase_started:    bool,
	rebase_operation_marker: u8,
	revision_sequence_phase: Revision_Sequence_Process_Phase,
	revision_sequence_started: bool,
	revision_sequence_resume_remaining: bool,
	revision_sequence_target_index: u32,
	manual_bisect_phase: Bisect_Process_Phase,
	manual_bisect_started: bool,
	manual_bisect_boundary_index: u32,
	conflict_resolution_phase: Conflict_Resolution_Process_Phase,
	conflict_resolution_started: bool,
	commit_precondition: Commit_Precondition,
	commit_phase:      Commit_Process_Phase,
	ref_phase:         Ref_Process_Phase,
	sequence_phase:    Sequence_Process_Phase,
	inspection_phase:  Inspection_Process_Phase,
	inspection_started: bool,
	sequence_source:   Sequence_Source,
	git_directory:     [MAX_REPOSITORY_CONTEXT_BYTES]u8,
	git_directory_length: u32,
	commit_resulting:  Revision_Identity,
	commit_operation_marker: u8,
	command:           [10]string,
	rebase_command:    [16]string,
	revision_sequence_command: [16]string,
	manual_bisect_command: [MAX_BISECT_GOOD_BOUNDARIES + 8]string,
	remote_configuration_key: [MAX_REF_NAME_BYTES + 32]u8,
	push_source_argument: [MAX_REF_NAME_BYTES + 16]u8,
	push_refspec:      [MAX_REF_NAME_BYTES * 2 + 1]u8,
	branch_argument:   [MAX_REF_NAME_BYTES + 16]u8,
	merge_argument:    [MAX_REF_NAME_BYTES + 16]u8,
	rebase_argument:   [MAX_REF_NAME_BYTES + 16]u8,
	revision_sequence_argument: [MAX_REVISION_ID_BYTES + 16]u8,
	revision_sequence_mainline: [4]u8,
	manual_bisect_argument: [MAX_REVISION_ID_BYTES + 16]u8,
	conflict_path:     [dynamic]u8,
	commit_fixup_argument: [MAX_REVISION_ID_BYTES + 8]u8,
	commit_fixup_argument_length: u8,
	history_count:     [32]u8,
	history_skip:      [32]u8,
	revision_range:    [MAX_REVISION_ID_BYTES * 2 + 2]u8,
	command_count:     u8,
	output_limit:      u64,
	input:             [dynamic]u8,
	input_offset:      u64,
	output:            [dynamic]u8,
	diagnostic:        [dynamic]u8,
	commit_output:     [dynamic]u8,
	commit_diagnostic: [dynamic]u8,
	revision_sequence_output: [dynamic]u8,
	revision_sequence_diagnostic: [dynamic]u8,
	ref_output:        [dynamic]u8,
	remote_output:     [dynamic]u8,
	commit_outcome_retained: bool,
	deadline_ns:       i64,
	exit_status:       i32,
	stdout_closed:     bool,
	stderr_closed:     bool,
	stdin_closed:      bool,
	state:             Repository_Process_State,
	failure:           Failure_Code,
	allocator:         runtime.Allocator,
}

/* repository_process_start_grouped_index_action starts one checked group mutation. */
repository_process_start_grouped_index_action :: proc(
	observation: ^Status_Observation,
	document: ^Diff_Document,
	selection: ^Grouped_Selection,
	request: ^Grouped_Index_Action_Request,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	current, failure := grouped_index_action_request_revalidate(observation, document, selection, request)
	if !current do return {}, false, failure
	descriptor, described := grouped_index_action_request_descriptor(request)
	input, copied := grouped_index_action_request_input(request)
	process_request, mapped := grouped_index_action_process_request(request)
	if !described || !copied || !mapped do return {}, false, .Invalid_Request
	return repository_process_start_grouped_index_action_checked(
		process_request,
		descriptor,
		input,
		now_ns,
		allocator,
	)
}

/* repository_process_start_partial_index_action starts one checked hunk mutation. */
repository_process_start_partial_index_action :: proc(
	observation: ^Status_Observation,
	document: ^Diff_Document,
	request: ^Partial_Index_Action_Request,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	current, failure := partial_index_action_request_revalidate(observation, document, request)
	if !current do return {}, false, failure
	descriptor, described := partial_index_action_request_descriptor(request)
	patch, copied := partial_index_action_request_patch(request)
	process_request, mapped := partial_index_action_process_request(request)
	if !described || !copied || !mapped do return {}, false, .Invalid_Request
	return repository_process_start_partial_index_action_checked(
		process_request,
		descriptor,
		patch,
		now_ns,
		allocator,
	)
}

/* repository_process_start_commit rechecks exact HEAD and index-tree identities before one checked commit. */
repository_process_start_commit :: proc(
	request: Commit_Request,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil || !commit_request_is_valid(request) do return {}, false, .Invalid_Request
	process_request := Process_Request {
		kind = .Commit_Normal,
		repository = request.precondition.repository,
		limits = request.limits,
	}
	if !process_request_is_valid(process_request) do return {}, false, .Invalid_Request
	return repository_process_start_commit_checked(process_request, request, now_ns, allocator)
}

/* repository_process_start_commit_precondition observes one bounded commit precondition from Status, HEAD, and index. */
repository_process_start_commit_precondition :: proc(
	observation: ^Status_Observation,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil do return {}, false, .Invalid_Request
	descriptor, described := status_observation_descriptor(observation)
	if !described do return {}, false, .Stale_Observation
	staged_paths, unmerged_paths, counted := repository_process_commit_status_counts(observation)
	if !counted do return {}, false, .Stale_Observation
	precondition := Commit_Precondition {
		repository = descriptor.repository,
		generation = Commit_Generation(u64(descriptor.generation)),
		operation = descriptor.operation,
		staged_paths = staged_paths,
		unmerged_paths = unmerged_paths,
	}
	if precondition.generation == Commit_Generation(0) || precondition.operation == .Unknown {
		return {}, false, .Invalid_Request
	}
	process_request := Process_Request {
		kind = .Commit_Normal,
		repository = precondition.repository,
		limits = DEFAULT_PROCESS_LIMITS,
	}
	if !process_request_is_valid(process_request) do return {}, false, .Invalid_Request
	return repository_process_start_commit_precondition_checked(process_request, precondition, now_ns, allocator)
}

/* repository_process_start_remote_configuration observes one selected remote's credential-free identity. */
repository_process_start_remote_configuration :: proc(
	observation: ^Ref_Observation,
	selection: Ref_Selection,
	now_ns: i64,
	limits := DEFAULT_PROCESS_LIMITS,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil || !process_limits_are_valid(limits) ||
	   !ref_selection_is_current(observation, selection) || selection.current.kind != .Remote {
		return {}, false, .Invalid_Request
	}
	descriptor, described := ref_observation_descriptor(observation)
	if !described || descriptor.state == .Truncated do return {}, false, .Stale_Observation
	remote := selection.current.remote
	if !remote_identity_is_valid(remote) || remote.repository != descriptor.repository ||
	   remote.generation != descriptor.generation {
		return {}, false, .Stale_Observation
	}
	request := Process_Request {
		kind = .Observe_Remote_Configuration,
		repository = descriptor.repository,
		limits = limits,
	}
	return repository_process_start_remote_configuration_checked(
		request,
		remote,
		.Observe_URL,
		now_ns,
		allocator,
	)
}

/* repository_process_start_fetch rechecks exact remote configuration before one closed fetch. */
repository_process_start_fetch :: proc(
	observation: ^Ref_Observation,
	configuration: Remote_Configuration_Identity,
	repository_operation: Operation_State,
	request: Fetch_Request,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil do return {}, false, .Invalid_Request
	current, failure := fetch_request_revalidate(
		observation,
		configuration,
		repository_operation,
		request,
	)
	if !current do return {}, false, failure
	process_request := Process_Request {
		kind = .Fetch_Remote,
		repository = request.precondition.configuration.remote.repository,
		limits = request.limits,
	}
	return repository_process_start_remote_configuration_checked(
		process_request,
		request.precondition.configuration.remote,
		.Check_URL,
		now_ns,
		allocator,
		request,
	)
}

/* repository_process_start_push_configuration observes one selected remote's push destination identity. */
repository_process_start_push_configuration :: proc(
	observation: ^Ref_Observation,
	selection: Ref_Selection,
	now_ns: i64,
	limits := DEFAULT_PROCESS_LIMITS,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil || !process_limits_are_valid(limits) ||
	   !ref_selection_is_current(observation, selection) || selection.current.kind != .Remote {
		return {}, false, .Invalid_Request
	}
	descriptor, described := ref_observation_descriptor(observation)
	if !described || descriptor.state == .Truncated do return {}, false, .Stale_Observation
	remote := selection.current.remote
	if !remote_identity_is_valid(remote) || remote.repository != descriptor.repository ||
	   remote.generation != descriptor.generation {
		return {}, false, .Stale_Observation
	}
	process_request := Process_Request {
		kind = .Observe_Push_Configuration,
		repository = descriptor.repository,
		limits = limits,
	}
	return repository_process_start_push_configuration_checked(
		process_request,
		remote,
		.Observe_URL,
		now_ns,
		allocator,
	)
}

/* repository_process_start_push rechecks exact source, destination, configuration, and operation state. */
repository_process_start_push :: proc(
	observation: ^Ref_Observation,
	configuration: Push_Configuration_Identity,
	repository_operation: Operation_State,
	request: Push_Request,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil do return {}, false, .Invalid_Request
	current, failure := push_request_revalidate(
		observation,
		configuration,
		repository_operation,
		request,
	)
	if !current do return {}, false, failure
	process_request := Process_Request {
		kind = .Push_Remote,
		repository = request.precondition.source.repository,
		limits = request.limits,
	}
	return repository_process_start_push_configuration_checked(
		process_request,
		request.precondition.destination.remote,
		.Check_URL,
		now_ns,
		allocator,
		request,
	)
}

/* repository_process_start starts one validated noninteractive repository observation request. */
repository_process_start :: proc(
	request: Process_Request,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil || !process_request_is_valid(request) ||
	   (request.kind != .Observe_Status && request.kind != .Observe_Sequence && request.kind != .Observe_History && request.kind != .Observe_Refs &&
	    request.kind != .Inspect_Revision_Detail_Metadata && request.kind != .Inspect_Revision_Detail_Comparison &&
	    request.kind != .Inspect_Revision_Range_Summary && request.kind != .Inspect_Revision_Range_Comparison &&
	    request.kind != .Inspection_Workflow) {
		return {}, false, .Invalid_Request
	}
	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = request
	switch request.kind {
	case .Observe_Status:
		state.command = {"git", "-c", "color.status=false", "status", "--porcelain=v2", "--branch", "--untracked-files=all", "-z", "", ""}
		state.command_count = 8
		state.output_limit = request.limits.stdout_bytes
	case .Observe_Sequence:
		if !repository_process_assign_sequence_command(state) {
			repository_process_data_destroy(state)
			return {}, false, .Invalid_Request
		}
	case .Observe_History:
		if !repository_process_assign_history_command(state) {
			repository_process_data_destroy(state)
			return {}, false, .Invalid_Request
		}
	case .Observe_Refs:
		if !repository_process_assign_ref_command(state) {
			repository_process_data_destroy(state)
			return {}, false, .Invalid_Request
		}
	case .Inspect_Revision_Detail_Metadata, .Inspect_Revision_Detail_Comparison,
	     .Inspect_Revision_Range_Summary, .Inspect_Revision_Range_Comparison:
		if !repository_process_assign_revision_inspection_command(state) {
			repository_process_data_destroy(state)
			return {}, false, .Invalid_Request
		}
	case .Inspection_Workflow:
		if !repository_process_assign_inspection_workflow_command(state) {
			repository_process_data_destroy(state)
			return {}, false, .Invalid_Request
		}
	case .Invalid, .Observe_Remote_Configuration, .Observe_Push_Configuration, .Inspect_Path, .Stage_Path, .Unstage_Path, .Stage_Diff_Unit,
	     .Unstage_Diff_Unit, .Stage_Group, .Unstage_Group, .Discard_Path,
	     .Commit_Normal, .Fetch_Remote, .Push_Remote, .Branch_Local, .Tag_Local,
	     .Merge_Repository, .Rebase_Repository, .Cherry_Pick_Repository, .Revert_Repository, .Bisect_Repository, .Resolve_Conflict,
	     .External_Operation, .Raw_Command:
		repository_process_data_destroy(state)
		return {}, false, .Invalid_Request
	}
	state.output, allocation_error = make([dynamic]u8, 0, int(min(state.output_limit, 64 * KIBIBYTE)), allocator)
	if allocation_error != nil {
		repository_process_data_destroy(state)
		return {}, false, .Allocation
	}
	state.diagnostic, allocation_error = make([dynamic]u8, 0, int(min(request.limits.diagnostic_bytes, 16 * KIBIBYTE)), allocator)
	if allocation_error != nil {
		repository_process_data_destroy(state)
		return {}, false, .Allocation
	}
	repository := state.request.repository
	state.child, state.failure = local_child_start(
		state.command[:int(state.command_count)],
		repository_context_string(&repository),
	)
	if state.failure != .None {
		repository_process_data_destroy(state)
		return {}, false, state.failure
	}
	if request.kind == .Inspection_Workflow &&
	   inspection_action_is_mutating(request.inspection_workflow.action) &&
	   state.inspection_phase == .None {
		state.inspection_started = true
	}
	state.deadline_ns = now_ns + request.limits.timeout_nanoseconds
	state.state = .Running
	return Repository_Process{state = state}, true, .None
}

/* repository_process_start_inspection_workflow starts one checked familiar family operation. */
repository_process_start_inspection_workflow :: proc(
	observation: ^Status_Observation,
	request: Inspection_Request,
	now_ns: i64,
	allocator := context.allocator,
	family_observation: ^Inspection_Observation = nil,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil || !inspection_request_is_valid(request) do return {}, false, .Invalid_Request
	descriptor, described := status_observation_descriptor(observation)
	if !described || descriptor.repository != request.repository ||
	   descriptor.generation != request.observation_generation {
		return {}, false, .Stale_Observation
	}
	current, current_failure := inspection_request_revalidate(family_observation, request)
	if !current do return {}, false, current_failure
	process_request := Process_Request {
		kind = .Inspection_Workflow,
		repository = request.repository,
		inspection_workflow = request,
		limits = request.limits,
	}
	return repository_process_start(process_request, now_ns, allocator)
}

/* repository_process_start_sequence_observation starts one bounded read-only sequence observation. */
repository_process_start_sequence_observation :: proc(
	repository: Repository_Context,
	now_ns: i64,
	limits := DEFAULT_SEQUENCE_LIMITS,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	request := Process_Request {
		kind = .Observe_Sequence,
		repository = repository,
		sequence = {limits = limits},
		limits = DEFAULT_PROCESS_LIMITS,
	}
	request.limits.stdout_bytes = min(
		MAX_PROCESS_OUTPUT_BYTES,
		max(request.limits.stdout_bytes, limits.temporary_bytes),
	)
	return repository_process_start(request, now_ns, allocator)
}

/* repository_process_start_ref_observation starts one complete bounded Ref observation. */
repository_process_start_ref_observation :: proc(
	repository: Repository_Context,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	request := Process_Request {
		kind = .Observe_Refs,
		repository = repository,
		refs = {limits = DEFAULT_REF_LIMITS},
		limits = DEFAULT_PROCESS_LIMITS,
	}
	return repository_process_start(request, now_ns, allocator)
}

/* repository_process_start_revision_detail_metadata starts one checked exact-revision metadata observation. */
repository_process_start_revision_detail_metadata :: proc(
	observation: ^History_Observation,
	request: Revision_Detail_Request,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	inspection := Revision_Inspection_Request{kind = .Detail, detail = request}
	return repository_process_start_revision_inspection(
		observation,
		.Inspect_Revision_Detail_Metadata,
		inspection,
		now_ns,
		allocator,
	)
}

/* repository_process_start_revision_detail_comparison starts one checked explicit-parent revision comparison. */
repository_process_start_revision_detail_comparison :: proc(
	observation: ^History_Observation,
	request: Revision_Detail_Request,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	inspection := Revision_Inspection_Request{kind = .Detail, detail = request}
	return repository_process_start_revision_inspection(
		observation,
		.Inspect_Revision_Detail_Comparison,
		inspection,
		now_ns,
		allocator,
	)
}

/* repository_process_start_revision_range_summary starts one checked ordered range summary observation. */
repository_process_start_revision_range_summary :: proc(
	observation: ^History_Observation,
	request: Revision_Range_Request,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	inspection := Revision_Inspection_Request{kind = .Range, range = request}
	return repository_process_start_revision_inspection(
		observation,
		.Inspect_Revision_Range_Summary,
		inspection,
		now_ns,
		allocator,
	)
}

/* repository_process_start_revision_range_comparison starts one checked base-to-target range comparison. */
repository_process_start_revision_range_comparison :: proc(
	observation: ^History_Observation,
	request: Revision_Range_Request,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	inspection := Revision_Inspection_Request{kind = .Range, range = request}
	return repository_process_start_revision_inspection(
		observation,
		.Inspect_Revision_Range_Comparison,
		inspection,
		now_ns,
		allocator,
	)
}

@(private)
repository_process_start_revision_inspection :: proc(
	observation: ^History_Observation,
	kind: Request_Kind,
	inspection: Revision_Inspection_Request,
	now_ns: i64,
	allocator: runtime.Allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil ||
	   (kind != .Inspect_Revision_Detail_Metadata && kind != .Inspect_Revision_Detail_Comparison &&
	    kind != .Inspect_Revision_Range_Summary && kind != .Inspect_Revision_Range_Comparison) {
		return {}, false, .Invalid_Request
	}
	current, failure := revision_inspection_request_revalidate(observation, inspection)
	if !current do return {}, false, failure
	descriptor, available := history_observation_descriptor(observation)
	if !available do return {}, false, .Stale_Observation
	request := Process_Request {
		kind = kind,
		repository = descriptor.repository,
		inspection = inspection,
		limits = DEFAULT_PROCESS_LIMITS,
	}
	return repository_process_start(request, now_ns, allocator)
}

@(private)
repository_process_start_remote_configuration_checked :: proc(
	process_request: Process_Request,
	remote: Remote_Identity,
	phase: Remote_Configuration_Process_Phase,
	now_ns: i64,
	allocator: runtime.Allocator,
	fetch: Fetch_Request = {},
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil || !process_request_is_valid(process_request) ||
	   !remote_identity_is_valid(remote) || remote.repository != process_request.repository ||
	   (phase != .Observe_URL && phase != .Check_URL) {
		return {}, false, .Invalid_Request
	}
	if process_request.kind == .Observe_Remote_Configuration {
		if phase != .Observe_URL || fetch != {} do return {}, false, .Invalid_Request
	} else if process_request.kind == .Fetch_Remote {
		if phase != .Check_URL || !fetch_request_is_valid(fetch) ||
		   fetch.precondition.configuration.remote != remote {
			return {}, false, .Invalid_Request
		}
	} else {
		return {}, false, .Invalid_Request
	}
	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = process_request
	state.fetch = fetch
	state.remote_configuration = remote
	state.remote_configuration_phase = phase
	state.output_limit = process_request.limits.stdout_bytes
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
			int(min(process_request.limits.diagnostic_bytes, 16 * KIBIBYTE)),
			allocator,
		)
	}
	if allocation_error != nil {
		repository_process_data_destroy(state)
		return {}, false, .Allocation
	}
	sha2.init_256(&state.remote_configuration_hash)
	if !repository_process_assign_remote_configuration_command(state, phase) {
		repository_process_data_destroy(state)
		return {}, false, .Invalid_Request
	}
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None {
		repository_process_data_destroy(state)
		return {}, false, state.failure
	}
	state.deadline_ns = now_ns + process_request.limits.timeout_nanoseconds
	state.state = .Running
	return Repository_Process{state = state}, true, .None
}

@(private)
repository_process_start_push_configuration_checked :: proc(
	process_request: Process_Request,
	remote: Remote_Identity,
	phase: Push_Process_Phase,
	now_ns: i64,
	allocator: runtime.Allocator,
	push: Push_Request = {},
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil || !process_request_is_valid(process_request) ||
	   !remote_identity_is_valid(remote) || remote.repository != process_request.repository ||
	   (phase != .Observe_URL && phase != .Check_URL) {
		return {}, false, .Invalid_Request
	}
	if process_request.kind == .Observe_Push_Configuration {
		if phase != .Observe_URL || push != {} do return {}, false, .Invalid_Request
	} else if process_request.kind == .Push_Remote {
		if phase != .Check_URL || !push_request_is_valid(push) ||
		   push.precondition.destination.remote != remote || process_request.limits != push.limits {
			return {}, false, .Invalid_Request
		}
	} else {
		return {}, false, .Invalid_Request
	}
	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = process_request
	state.push = push
	state.push_configuration = remote
	state.push_phase = phase
	state.output_limit = process_request.limits.stdout_bytes
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
			int(min(process_request.limits.diagnostic_bytes, 16 * KIBIBYTE)),
			allocator,
		)
	}
	if allocation_error != nil {
		repository_process_data_destroy(state)
		return {}, false, .Allocation
	}
	sha2.init_256(&state.push_configuration_hash)
	if !repository_process_assign_push_configuration_command(state, phase) {
		repository_process_data_destroy(state)
		return {}, false, .Invalid_Request
	}
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None {
		repository_process_data_destroy(state)
		return {}, false, state.failure
	}
	state.deadline_ns = now_ns + process_request.limits.timeout_nanoseconds
	state.state = .Running
	return Repository_Process{state = state}, true, .None
}

@(private)
repository_process_assign_history_command :: proc(state: ^Repository_Process_Data) -> bool {
	if state == nil || state.request.kind != .Observe_History || !history_request_is_valid(state.request.history) {
		return false
	}
	continuation := state.request.history.continuation
	count := state.request.history.limits.page_revisions + 1
	skip: u32
	anchor := "HEAD"
	if continuation != {} {
		count += 1
		skip = continuation.skipped - 1
		anchor = revision_identity_string(&state.request.history.continuation.head)
		if len(anchor) == 0 do return false
	}
	count_argument, count_formatted := repository_process_format_history_argument(
		&state.history_count,
		"--max-count=",
		count,
	)
	skip_argument, skip_formatted := repository_process_format_history_argument(
		&state.history_skip,
		"--skip=",
		skip,
	)
	if !count_formatted || !skip_formatted do return false
	state.command = {
		"git", "-c", "color.ui=false", "log", "--topo-order", "--date-order",
		count_argument, skip_argument, HISTORY_PRETTY_FORMAT, anchor,
	}
	state.command_count = 10
	state.output_limit = min(state.request.limits.stdout_bytes, state.request.history.limits.metadata_bytes)
	return state.output_limit > 0
}

@(private)
repository_process_assign_ref_command :: proc(state: ^Repository_Process_Data) -> bool {
	if state == nil || state.request.kind != .Observe_Refs || !ref_request_is_valid(state.request.refs) {
		return false
	}
	state.command = {
		"git", "-c", "color.ui=false", "for-each-ref", REF_PRETTY_FORMAT,
		"refs/heads", "refs/remotes", "refs/tags", "", "",
	}
	state.command_count = 8
	state.ref_phase = .Observe_Refs
	state.output_limit = min(state.request.limits.stdout_bytes, state.request.refs.limits.temporary_bytes)
	return state.output_limit > 0
}

@(private)
repository_process_assign_sequence_command :: proc(state: ^Repository_Process_Data) -> bool {
	if state == nil || state.request.kind != .Observe_Sequence ||
	   !sequence_request_is_valid(state.request.sequence) {
		return false
	}
	state.command = {"git", "rev-parse", "--absolute-git-dir", "", "", "", "", "", "", ""}
	state.command_count = 3
	state.sequence_phase = .Resolve_Git_Directory
	state.output_limit = MAX_REPOSITORY_CONTEXT_BYTES
	return true
}

@(private)
repository_process_assign_revision_inspection_command :: proc(state: ^Repository_Process_Data) -> bool {
	if state == nil || !revision_inspection_request_is_valid(state.request.inspection) do return false
	inspection := state.request.inspection
	switch state.request.kind {
	case .Inspect_Revision_Detail_Metadata:
		revision := revision_identity_string(&state.request.inspection.detail.target.revision)
		if len(revision) == 0 do return false
		state.command = {
			"git", "show", "--no-color", "-s", REVISION_DETAIL_PRETTY_FORMAT, "--no-patch", revision, "", "", "",
		}
		state.command_count = 7
		state.output_limit = min(state.request.limits.stdout_bytes, inspection.detail.limits.metadata_bytes)
	case .Inspect_Revision_Detail_Comparison:
		revision := revision_identity_string(&state.request.inspection.detail.target.revision)
		if len(revision) == 0 do return false
		comparison_limit := inspection.detail.limits.changed_path_bytes + inspection.detail.limits.diff_bytes
		state.output_limit = min(state.request.limits.stdout_bytes, comparison_limit)
		switch inspection.detail.parent.kind {
		case .Empty_Tree:
			state.command = {
				"git", "diff-tree", "--root", "--no-commit-id", "--no-ext-diff", "--no-color", "--raw", "-z", "-p", revision,
			}
			state.command_count = 10
		case .Parent:
			parent := revision_identity_string(&state.request.inspection.detail.parent.parent)
			if len(parent) == 0 do return false
			state.command = {
				"git", "diff", "--no-ext-diff", "--no-color", "--raw", "-z", "-p", parent, revision, "",
			}
			state.command_count = 9
		case .Invalid:
			return false
		}
	case .Inspect_Revision_Range_Summary:
		range, assigned := repository_process_assign_revision_range(state, inspection.range.range)
		if !assigned do return false
		state.command = {
			"git", "log", "--no-color", "--topo-order", "--date-order", REVISION_RANGE_PRETTY_FORMAT, range, "", "", "",
		}
		state.command_count = 7
		state.output_limit = min(state.request.limits.stdout_bytes, inspection.range.limits.summary_bytes)
	case .Inspect_Revision_Range_Comparison:
		base := revision_identity_string(&state.request.inspection.range.range.base.revision)
		target := revision_identity_string(&state.request.inspection.range.range.target.revision)
		if len(base) == 0 || len(target) == 0 do return false
		comparison_limit := inspection.range.limits.changed_path_bytes + inspection.range.limits.diff_bytes
		state.command = {
			"git", "diff", "--no-ext-diff", "--no-color", "--raw", "-z", "-p", base, target, "",
		}
		state.command_count = 9
		state.output_limit = min(state.request.limits.stdout_bytes, comparison_limit)
	case .Invalid, .Observe_Status, .Observe_Sequence, .Observe_History, .Observe_Refs, .Observe_Remote_Configuration,
	     .Observe_Push_Configuration,
	     .Inspect_Path, .Stage_Path, .Unstage_Path,
	     .Stage_Diff_Unit, .Unstage_Diff_Unit, .Stage_Group, .Unstage_Group, .Discard_Path,
	     .Commit_Normal, .Fetch_Remote, .Push_Remote, .Branch_Local, .Tag_Local,
	     .Merge_Repository, .Rebase_Repository, .Cherry_Pick_Repository, .Revert_Repository, .Bisect_Repository, .Resolve_Conflict,
	     .Inspection_Workflow, .External_Operation, .Raw_Command:
		return false
	}
	return state.output_limit > 0
}

@(private)
repository_process_assign_inspection_workflow_command :: proc(state: ^Repository_Process_Data) -> bool {
	if state == nil || state.request.kind != .Inspection_Workflow ||
	   !inspection_request_is_valid(state.request.inspection_workflow) {
		return false
	}
	request := &state.request.inspection_workflow
	target := inspection_text_string(&request.target)
	secondary := inspection_text_string(&request.secondary)
	if (len(target) > 0 && target[0] == '-') || (len(secondary) > 0 && secondary[0] == '-') {
		return false
	}
	switch request.family {
	case .Stash:
		switch request.action {
		case .List:
			state.command = {"git", "stash", "list", "--format=%gd%x00%H%x00%gs%x00", "", "", "", "", "", ""}
			state.command_count = 4
		case .Create:
			state.command = {"git", "stash", "push", "-m", target, "", "", "", "", ""}
			state.command_count = 5
		case .Inspect, .Apply, .Pop, .Branch, .Drop:
			state.command = {"git", "rev-parse", "--verify", target, "", "", "", "", "", ""}
			state.command_count = 4
			state.inspection_phase = .Check_Stash
		case .Invalid, .Visit, .Lock, .Unlock, .Prune, .Remove:
			return false
		}
	case .Worktree:
		switch request.action {
		case .List:
			state.command = {"git", "worktree", "list", "--porcelain", "-z", "", "", "", "", ""}
			state.command_count = 5
		case .Create:
			state.command = {"git", "worktree", "add", "--", target, secondary, "", "", "", ""}
			state.command_count = 6
		case .Visit, .Lock, .Unlock, .Remove:
			state.command = {"git", "-C", target, "rev-parse", "--verify", "HEAD", "", "", "", ""}
			state.command_count = 6
			state.inspection_phase = .Check_Worktree
		case .Prune:
			state.command = {"git", "worktree", "prune", "", "", "", "", "", "", ""}
			state.command_count = 3
		case .Invalid, .Inspect, .Apply, .Pop, .Branch, .Drop:
			return false
		}
	case .Blame:
		if request.action == .Inspect {
			state.command = {"git", "blame", "--line-porcelain", "--", target, "", "", "", "", ""}
			state.command_count = 5
		} else if request.action == .Visit {
			state.command = {"git", "show", "--no-color", "--stat", "--patch", target, "", "", "", ""}
			state.command_count = 6
		} else {
			return false
		}
	case .Reflog:
		if request.action == .List {
			state.command = {"git", "reflog", "show", "--format=%H%x00%gd%x00%gs%x00", "", "", "", "", "", ""}
			state.command_count = 4
		} else if request.action == .Visit {
			state.command = {"git", "show", "--no-color", "--stat", "--patch", target, "", "", "", ""}
			state.command_count = 6
		} else {
			return false
		}
	case .Invalid:
		return false
	}
	state.output_limit = min(state.request.limits.stdout_bytes, MAX_INSPECTION_OUTPUT_BYTES)
	return state.command_count > 0 && state.output_limit > 0
}

@(private)
repository_process_advance_inspection_workflow :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.request.kind != .Inspection_Workflow || state.exit_status != 0 {
		return .Process_Failed
	}
	switch state.inspection_phase {
	case .Check_Stash, .Check_Worktree:
		expected := inspection_text_string(&state.request.inspection_workflow.evidence)
		observed := strings.trim_space(string(state.output[:]))
		if len(expected) == 0 || observed != expected do return .Stale_Observation
		repository_process_inspection_reset_child(state)
		request := &state.request.inspection_workflow
		target := inspection_text_string(&request.target)
		secondary := inspection_text_string(&request.secondary)
		if request.family == .Stash {
			switch request.action {
			case .Inspect:
				state.command = {"git", "stash", "show", "--no-color", "--stat", "--patch", target, "", "", ""}
				state.command_count = 7
			case .Apply:
				state.command = {"git", "stash", "apply", "--index", target, "", "", "", "", ""}
				state.command_count = 5
			case .Pop:
				state.command = {"git", "stash", "pop", "--index", target, "", "", "", "", ""}
				state.command_count = 5
			case .Branch:
				state.command = {"git", "stash", "branch", secondary, target, "", "", "", "", ""}
				state.command_count = 5
			case .Drop:
				state.command = {"git", "stash", "drop", target, "", "", "", "", "", ""}
				state.command_count = 4
			case .Invalid, .List, .Create, .Visit, .Lock, .Unlock, .Prune, .Remove:
				return .Invalid_Request
			}
		} else if request.family == .Worktree {
			switch request.action {
			case .Visit:
				state.command = {"git", "-C", target, "rev-parse", "--show-toplevel", "", "", "", "", ""}
				state.command_count = 5
			case .Lock:
				state.command = {"git", "worktree", "lock", "--", target, "", "", "", "", ""}
				state.command_count = 5
			case .Unlock:
				state.command = {"git", "worktree", "unlock", "--", target, "", "", "", "", ""}
				state.command_count = 5
			case .Remove:
				state.command = {"git", "worktree", "remove", "--", target, "", "", "", "", ""}
				state.command_count = 5
			case .Invalid, .List, .Create, .Inspect, .Apply, .Pop, .Branch, .Drop, .Prune:
				return .Invalid_Request
			}
		} else {
			return .Invalid_Request
		}
		state.child, state.failure = repository_process_start_child(state)
		if state.failure != .None do return state.failure
		state.inspection_started = inspection_action_is_mutating(request.action)
		state.inspection_phase = .Action
		return .None
	case .Action:
		state.inspection_phase = .None
		state.state = .Completed
		return .None
	case .None:
		return .Invalid_Request
	}
	return .Invalid_Request
}

@(private)
repository_process_inspection_reset_child :: proc(state: ^Repository_Process_Data) {
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

@(private)
repository_process_assign_revision_range :: proc(
	state: ^Repository_Process_Data,
	range: Revision_Range,
) -> (string, bool) {
	if state == nil || !revision_range_is_valid(range) do return "", false
	base_identity := range.base.revision
	target_identity := range.target.revision
	base := revision_identity_string(&base_identity)
	target := revision_identity_string(&target_identity)
	if len(base) == 0 || len(target) == 0 || len(base) + 2 + len(target) > len(state.revision_range) {
		return "", false
	}
	copy(state.revision_range[:len(base)], transmute([]u8)base)
	state.revision_range[len(base)] = '.'
	state.revision_range[len(base) + 1] = '.'
	copy(state.revision_range[len(base) + 2:len(base) + 2 + len(target)], transmute([]u8)target)
	return string(state.revision_range[:len(base) + 2 + len(target)]), true
}

@(private)
repository_process_format_history_argument :: proc(
	storage: ^[32]u8,
	prefix: string,
	value: u32,
) -> (string, bool) {
	if storage == nil || len(prefix) + 10 > len(storage^) do return "", false
	copy(storage^[:len(prefix)], transmute([]u8)prefix)
	end := len(prefix)
	digits: [10]u8
	digit_count := 0
	if value == 0 {
		digits[0] = '0'
		digit_count = 1
	} else {
		remaining := value
		for remaining > 0 {
			digits[digit_count] = u8('0') + u8(remaining % 10)
			digit_count += 1
			remaining /= 10
		}
	}
	for index in 0 ..< digit_count do storage^[end + index] = digits[digit_count - index - 1]
	end += digit_count
	return string(storage^[:end]), true
}

/* repository_process_start_path_detail starts one checked read-only path inspection. */
repository_process_start_path_detail :: proc(
	observation: ^Status_Observation,
	target: Path_Target,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	descriptor, available := status_observation_descriptor(observation)
	if !available || !path_target_is_valid(target) || target.generation != descriptor.generation {
		return {}, false, .Stale_Observation
	}
	path, found := status_observation_path_by_id(observation, target.path)
	if !found do return {}, false, .Path_Unavailable
	path_text, copied := status_observation_path_text(observation, path)
	if !copied || len(path_text) == 0 do return {}, false, .Path_Unavailable
	request := Process_Request{
		kind = .Inspect_Path,
		repository = descriptor.repository,
		target = target,
		limits = DEFAULT_PROCESS_LIMITS,
	}
	return repository_process_start_detail(request, string(path_text), path.group, now_ns, allocator)
}

/* repository_process_start_index_action starts one revalidated complete-path mutation. */
repository_process_start_index_action :: proc(
	observation: ^Status_Observation,
	request: Index_Action_Request,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	path, admitted, failure := index_action_revalidate(observation, request)
	if !admitted do return {}, false, failure
	path_text, copied := status_observation_path_text(observation, path)
	if !copied || len(path_text) == 0 do return {}, false, .Path_Unavailable
	process_request, mapped := index_action_process_request(request)
	if !mapped do return {}, false, .Invalid_Request
	return repository_process_start_index_action_checked(
		process_request,
		request,
		string(path_text),
		now_ns,
		allocator,
	)
}

/* repository_process_start_discard_action starts one confirmed tracked-path restore. */
repository_process_start_discard_action :: proc(
	observation: ^Status_Observation,
	request: Discard_Action_Request,
	modified_buffer: bool,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Failure_Code) {
	path, admitted, failure := discard_action_revalidate(observation, request, modified_buffer)
	if !admitted do return {}, false, failure
	path_text, copied := status_observation_path_text(observation, path)
	if !copied || len(path_text) == 0 do return {}, false, .Path_Unavailable
	process_request, mapped := discard_action_process_request(request)
	if !mapped do return {}, false, .Invalid_Request
	return repository_process_start_discard_action_checked(
		process_request,
		request,
		string(path_text),
		now_ns,
		allocator,
	)
}

@(private)
repository_process_start_commit_checked :: proc(
	process_request: Process_Request,
	commit_request: Commit_Request,
	now_ns: i64,
	allocator: runtime.Allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil || !process_request_is_valid(process_request) ||
	   process_request.kind != .Commit_Normal || !commit_request_is_valid(commit_request) ||
	   process_request.repository != commit_request.precondition.repository ||
	   process_request.limits != commit_request.limits {
		return {}, false, .Invalid_Request
	}
	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = process_request
	state.commit = commit_request
	state.commit_phase = .Check_Head
	state.output_limit = commit_request.limits.stdout_bytes
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
			int(min(commit_request.limits.diagnostic_bytes, 16 * KIBIBYTE)),
			allocator,
		)
	}
	if allocation_error != nil {
		repository_process_data_destroy(state)
		return {}, false, .Allocation
	}
	state.command = {"git", "rev-parse", "--verify", "--quiet", "HEAD", "", "", "", "", ""}
	state.command_count = 5
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None {
		repository_process_data_destroy(state)
		return {}, false, state.failure
	}
	state.deadline_ns = now_ns + commit_request.limits.timeout_nanoseconds
	state.state = .Running
	return Repository_Process{state = state}, true, .None
}

@(private)
repository_process_start_commit_precondition_checked :: proc(
	process_request: Process_Request,
	precondition: Commit_Precondition,
	now_ns: i64,
	allocator: runtime.Allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil || !process_request_is_valid(process_request) ||
	   process_request.kind != .Commit_Normal ||
	   !repository_context_is_valid(precondition.repository) ||
	   precondition.generation == Commit_Generation(0) || precondition.operation == .Unknown ||
	   process_request.repository != precondition.repository {
		return {}, false, .Invalid_Request
	}
	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = process_request
	state.commit_precondition = precondition
	state.commit_phase = .Observe_Head
	state.output_limit = process_request.limits.stdout_bytes
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
			int(min(process_request.limits.diagnostic_bytes, 16 * KIBIBYTE)),
			allocator,
		)
	}
	if allocation_error != nil {
		repository_process_data_destroy(state)
		return {}, false, .Allocation
	}
	state.command = {"git", "rev-parse", "--verify", "--quiet", "HEAD", "", "", "", "", ""}
	state.command_count = 5
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None {
		repository_process_data_destroy(state)
		return {}, false, state.failure
	}
	state.deadline_ns = now_ns + process_request.limits.timeout_nanoseconds
	state.state = .Running
	return Repository_Process{state = state}, true, .None
}

@(private)
repository_process_start_discard_action_checked :: proc(
	process_request: Process_Request,
	discard_request: Discard_Action_Request,
	path: string,
	now_ns: i64,
	allocator: runtime.Allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil || !process_request_is_valid(process_request) ||
	   !discard_action_request_is_valid(discard_request) || !discard_request.confirmed ||
	   len(path) == 0 {
		return {}, false, .Invalid_Request
	}
	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = process_request
	state.discard_action = discard_request
	state.output_limit = discard_request.limits.stdout_bytes
	state.command = {"git", "restore", "--worktree", "--", path, "", "", "", "", ""}
	state.command_count = 5
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
			int(min(discard_request.limits.diagnostic_bytes, 16 * KIBIBYTE)),
			allocator,
		)
	}
	if allocation_error != nil {
		repository_process_data_destroy(state)
		return {}, false, .Allocation
	}
	repository := process_request.repository
	state.child, state.failure = local_child_start(
		state.command[:int(state.command_count)],
		repository_context_string(&repository),
	)
	if state.failure != .None {
		repository_process_data_destroy(state)
		return {}, false, state.failure
	}
	state.deadline_ns = now_ns + discard_request.limits.timeout_nanoseconds
	state.state = .Running
	return Repository_Process{state = state}, true, .None
}

@(private)
repository_process_start_index_action_checked :: proc(
	process_request: Process_Request,
	index_request: Index_Action_Request,
	path: string,
	now_ns: i64,
	allocator: runtime.Allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil || !process_request_is_valid(process_request) ||
	   !index_action_request_is_valid(index_request) || len(path) == 0 {
		return {}, false, .Invalid_Request
	}
	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = process_request
	state.index_action = index_request
	state.output_limit = index_request.limits.stdout_bytes
	switch index_request.action {
	case .Stage:
		state.command = {"git", "add", "--", path, "", "", "", "", "", ""}
		state.command_count = 4
	case .Unstage:
		state.command = {"git", "reset", "-q", "--", path, "", "", "", "", ""}
		state.command_count = 5
	case .Invalid:
		repository_process_data_destroy(state)
		return {}, false, .Invalid_Request
	}
	state.output, allocation_error = make(
		[dynamic]u8,
		0,
		int(min(state.output_limit, 64 * KIBIBYTE)),
		allocator,
	)
	if allocation_error != nil {
		repository_process_data_destroy(state)
		return {}, false, .Allocation
	}
	state.diagnostic, allocation_error = make(
		[dynamic]u8,
		0,
		int(min(index_request.limits.diagnostic_bytes, 16 * KIBIBYTE)),
		allocator,
	)
	if allocation_error != nil {
		repository_process_data_destroy(state)
		return {}, false, .Allocation
	}
	repository := process_request.repository
	state.child, state.failure = local_child_start(
		state.command[:int(state.command_count)],
		repository_context_string(&repository),
	)
	if state.failure != .None {
		repository_process_data_destroy(state)
		return {}, false, state.failure
	}
	state.deadline_ns = now_ns + index_request.limits.timeout_nanoseconds
	state.state = .Running
	return Repository_Process{state = state}, true, .None
}

@(private)
repository_process_start_partial_index_action_checked :: proc(
	process_request: Process_Request,
	partial_request: Partial_Index_Action_Request_Descriptor,
	patch: []u8,
	now_ns: i64,
	allocator: runtime.Allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil || !process_request_is_valid(process_request) ||
	   !partial_index_action_request_descriptor_is_valid(partial_request) ||
	   len(patch) == 0 || u64(len(patch)) != partial_request.input_bytes {
		return {}, false, .Invalid_Request
	}
	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = process_request
	state.partial_action = partial_request
	state.output_limit = partial_request.limits.stdout_bytes
	state.command = {"git", "apply", "--cached", "--whitespace=nowarn", "-", "", "", "", "", ""}
	state.command_count = 5
	if partial_request.direction == .Reverse {
		state.command = {"git", "apply", "--cached", "--reverse", "--whitespace=nowarn", "-", "", "", "", ""}
		state.command_count = 6
	}
	state.input, allocation_error = make([dynamic]u8, 0, len(patch), allocator)
	if allocation_error == nil do _, allocation_error = append(&state.input, ..patch)
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
			int(min(partial_request.limits.diagnostic_bytes, 16 * KIBIBYTE)),
			allocator,
		)
	}
	if allocation_error != nil {
		repository_process_data_destroy(state)
		return {}, false, .Allocation
	}
	repository := process_request.repository
	state.child, state.failure = local_child_start(
		state.command[:int(state.command_count)],
		repository_context_string(&repository),
	)
	if state.failure != .None {
		repository_process_data_destroy(state)
		return {}, false, state.failure
	}
	state.deadline_ns = now_ns + partial_request.limits.timeout_nanoseconds
	state.state = .Running
	return Repository_Process{state = state}, true, .None
}

@(private)
repository_process_start_grouped_index_action_checked :: proc(
	process_request: Process_Request,
	grouped_request: Grouped_Index_Action_Request_Descriptor,
	input: []u8,
	now_ns: i64,
	allocator: runtime.Allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil || !process_request_is_valid(process_request) ||
	   !grouped_index_action_request_descriptor_is_valid(grouped_request) || len(input) == 0 ||
	   u64(len(input)) != grouped_request.input_bytes {
		return {}, false, .Invalid_Request
	}
	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = process_request
	state.grouped_action = grouped_request
	state.output_limit = grouped_request.limits.stdout_bytes
	if grouped_request.input_kind == .Pathspec {
		if grouped_request.selection.action == .Stage {
			state.command = {"git", "add", "--pathspec-from-file=-", "--pathspec-file-nul", "", "", "", "", "", ""}
			state.command_count = 4
		} else {
			state.command = {"git", "reset", "-q", "--pathspec-from-file=-", "--pathspec-file-nul", "", "", "", "", ""}
			state.command_count = 5
		}
	} else {
		state.command = {"git", "apply", "--cached", "--whitespace=nowarn", "-", "", "", "", "", ""}
		state.command_count = 5
		if grouped_request.selection.action == .Unstage {
			state.command = {"git", "apply", "--cached", "--reverse", "--whitespace=nowarn", "-", "", "", "", ""}
			state.command_count = 6
		}
	}
	state.input, allocation_error = make([dynamic]u8, 0, len(input), allocator)
	if allocation_error == nil do _, allocation_error = append(&state.input, ..input)
	if allocation_error == nil {
		state.output, allocation_error = make([dynamic]u8, 0, int(min(state.output_limit, 64 * KIBIBYTE)), allocator)
	}
	if allocation_error == nil {
		state.diagnostic, allocation_error = make(
			[dynamic]u8,
			0,
			int(min(grouped_request.limits.diagnostic_bytes, 16 * KIBIBYTE)),
			allocator,
		)
	}
	if allocation_error != nil {
		repository_process_data_destroy(state)
		return {}, false, .Allocation
	}
	repository := process_request.repository
	state.child, state.failure = local_child_start(
		state.command[:int(state.command_count)],
		repository_context_string(&repository),
	)
	if state.failure != .None {
		repository_process_data_destroy(state)
		return {}, false, state.failure
	}
	state.deadline_ns = now_ns + grouped_request.limits.timeout_nanoseconds
	state.state = .Running
	return Repository_Process{state = state}, true, .None
}

@(private)
repository_process_start_detail :: proc(
	request: Process_Request,
	path: string,
	group: Change_Group,
	now_ns: i64,
	allocator: runtime.Allocator,
) -> (Repository_Process, bool, Failure_Code) {
	if allocator.procedure == nil || !process_request_is_valid(request) || request.kind != .Inspect_Path || len(path) == 0 {
		return {}, false, .Invalid_Request
	}
	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = request
	state.output_limit = request.limits.diff_bytes
	switch group {
	case .Staged:
		state.command = {"git", "-c", "color.ui=false", "diff", "--cached", "--no-ext-diff", "--no-color", "--", path, ""}
		state.command_count = 9
	case .Untracked:
		state.command = {"git", "-c", "color.ui=false", "diff", "--no-index", "--no-ext-diff", "--no-color", "--", "/dev/null", path}
		state.command_count = 10
	case .Unstaged, .Unmerged:
		state.command = {"git", "-c", "color.ui=false", "diff", "--no-ext-diff", "--no-color", "--", path, "", ""}
		state.command_count = 8
	case .Invalid:
		repository_process_data_destroy(state)
		return {}, false, .Path_Unavailable
	}
	state.output, allocation_error = make([dynamic]u8, 0, int(min(state.output_limit, 64 * KIBIBYTE)), allocator)
	if allocation_error != nil {
		repository_process_data_destroy(state)
		return {}, false, .Allocation
	}
	state.diagnostic, allocation_error = make([dynamic]u8, 0, int(min(request.limits.diagnostic_bytes, 16 * KIBIBYTE)), allocator)
	if allocation_error != nil {
		repository_process_data_destroy(state)
		return {}, false, .Allocation
	}
	repository := request.repository
	state.child, state.failure = local_child_start(state.command[:int(state.command_count)], repository_context_string(&repository))
	if state.failure != .None {
		repository_process_data_destroy(state)
		return {}, false, state.failure
	}
	state.deadline_ns = now_ns + request.limits.timeout_nanoseconds
	state.state = .Running
	return Repository_Process{state = state}, true, .None
}

@(private)
repository_process_commit_status_counts :: proc(
	observation: ^Status_Observation,
) -> (staged_paths, unmerged_paths: u32, ok: bool) {
	path_count, counted := status_observation_path_count(observation)
	if !counted do return
	for index in 0 ..< path_count {
		path, found := status_observation_path(observation, index)
		if !found do return 0, 0, false
		if path.group == .Staged do staged_paths += 1
		if path.group == .Unmerged do unmerged_paths += 1
	}
	return staged_paths, unmerged_paths, true
}

@(private)
repository_process_start_child :: proc(state: ^Repository_Process_Data) -> (Local_Child, Failure_Code) {
	if state == nil || state.command_count == 0 || int(state.command_count) > len(state.command) do return {}, .Invalid_Request
	if state.termination.reason != .None {
		return {}, state.termination.reason == .Timeout ? .Timeout : .Cancelled
	}
	repository := state.request.repository
	child, failure := local_child_start(state.command[:int(state.command_count)], repository_context_string(&repository))
	if failure == .None {
		repository_process_note_child_started(state)
	} else {
		repository_process_note_failure(state, .Start, failure)
	}
	return child, failure
}

@(private)
repository_process_commit_preflight_active :: proc(state: ^Repository_Process_Data) -> bool {
	return state != nil && (state.commit_phase == .Observe_Head ||
		state.commit_phase == .Observe_Index_Tree || state.commit_phase == .Check_Head ||
		state.commit_phase == .Check_Index_Tree || state.commit_phase == .Check_Operation)
}

@(private)
repository_process_advance_commit_preflight :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || !repository_process_commit_preflight_active(state) do return .Invalid_Request
	switch state.commit_phase {
	case .Observe_Head:
		head, observed := repository_process_commit_observed_head(state)
		if !observed do return .Process_Failed
		state.commit_precondition.head = head
		return repository_process_start_commit_index_preflight(state)
	case .Observe_Index_Tree:
		if state.exit_status != 0 do return .Process_Failed
		identity, valid := repository_process_commit_output_identity(state)
		if !valid do return .Parse
		state.commit_precondition.index_tree = {object = identity}
		if !commit_precondition_is_valid(state.commit_precondition) do return .Invalid_Request
		state.commit_phase = .None
		state.state = .Completed
		return .None
	case .Check_Head:
		if !repository_process_commit_head_matches(state) do return .Stale_Observation
		return repository_process_start_commit_index_preflight(state)
	case .Check_Index_Tree:
		if state.exit_status != 0 do return .Stale_Observation
		identity, valid := repository_process_commit_output_identity(state)
		if !valid || identity != state.commit.precondition.index_tree.object do return .Stale_Observation
		state.commit_operation_marker = 0
		return repository_process_start_commit_operation_check(state)
	case .Check_Operation:
		if state.exit_status != 0 do return .Process_Failed
		active, inspected := repository_process_commit_operation_is_active(state)
		if !inspected do return .Parse
		if active do return .Commit_Unavailable
		state.commit_operation_marker += 1
		if int(state.commit_operation_marker) < len(COMMIT_OPERATION_MARKERS) {
			return repository_process_start_commit_operation_check(state)
		}
		return repository_process_start_commit_child(state)
	case .None, .Commit, .Observe_Result_Head:
		return .Invalid_Request
	}
	return .Invalid_Request
}

@(private)
repository_process_start_commit_operation_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || (state.commit_phase != .Check_Index_Tree && state.commit_phase != .Check_Operation) ||
	   int(state.commit_operation_marker) >= len(COMMIT_OPERATION_MARKERS) {
		return .Invalid_Request
	}
	repository_process_commit_reset_child(state)
	markers := COMMIT_OPERATION_MARKERS
	state.command = {
		"git", "rev-parse", "--git-path", markers[int(state.commit_operation_marker)],
		"", "", "", "", "", "",
	}
	state.command_count = 4
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	state.commit_phase = .Check_Operation
	return .None
}

@(private)
repository_process_commit_operation_is_active :: proc(state: ^Repository_Process_Data) -> (active, inspected: bool) {
	if state == nil || state.commit_phase != .Check_Operation ||
	   int(state.commit_operation_marker) >= len(COMMIT_OPERATION_MARKERS) ||
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
repository_process_commit_observed_head :: proc(state: ^Repository_Process_Data) -> (Commit_Head, bool) {
	if state == nil do return {}, false
	if state.exit_status == 1 && len(state.output) == 0 && len(state.diagnostic) == 0 {
		return {kind = .Unborn}, true
	}
	identity, valid := repository_process_commit_output_identity(state)
	if state.exit_status != 0 || !valid do return {}, false
	return {kind = .Revision, revision = identity}, true
}

@(private)
repository_process_commit_head_matches :: proc(state: ^Repository_Process_Data) -> bool {
	if state == nil do return false
	expected := state.commit.precondition.head
	switch expected.kind {
	case .Unborn:
		return state.exit_status == 1 && len(state.output) == 0 && len(state.diagnostic) == 0
	case .Revision:
		identity, valid := repository_process_commit_output_identity(state)
		return state.exit_status == 0 && valid && identity == expected.revision
	case .Invalid:
		return false
	}
	return false
}

@(private)
repository_process_commit_output_identity :: proc(
	state: ^Repository_Process_Data,
) -> (Revision_Identity, bool) {
	if state == nil || len(state.output) < 2 || state.output[len(state.output) - 1] != '\n' do return {}, false
	identity: Revision_Identity
	if !revision_identity_assign(&identity, string(state.output[:len(state.output) - 1])) do return {}, false
	return identity, true
}

@(private)
repository_process_start_commit_index_preflight :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || (state.commit_phase != .Observe_Head && state.commit_phase != .Check_Head) {
		return .Invalid_Request
	}
	next_phase := Commit_Process_Phase.Observe_Index_Tree if state.commit_phase == .Observe_Head else .Check_Index_Tree
	repository_process_commit_reset_child(state)
	state.command = {"git", "write-tree", "", "", "", "", "", "", "", ""}
	state.command_count = 2
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	state.commit_phase = next_phase
	return .None
}

@(private)
repository_process_start_commit_child :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.commit_phase != .Check_Operation ||
	   int(state.commit_operation_marker) != len(COMMIT_OPERATION_MARKERS) {
		return .Invalid_Request
	}
	repository_process_commit_reset_child(state)
	allocation_error: runtime.Allocator_Error
	switch state.commit.mode {
	case .Normal, .Amend:
		message, copied := commit_message_text(&state.commit.message)
		if !copied do return .Commit_Message_Invalid
		if state.commit.mode == .Normal {
			state.command = {"git", "commit", "--file=-", "", "", "", "", "", "", ""}
			state.command_count = 3
		} else {
			state.command = {"git", "commit", "--amend", "--file=-", "", "", "", "", "", ""}
			state.command_count = 4
		}
		state.input, allocation_error = make([dynamic]u8, 0, len(message), state.allocator)
		if allocation_error == nil do _, allocation_error = append(&state.input, ..message)
	case .Fixup:
		if !repository_process_assign_commit_fixup_argument(state) do return .Invalid_Request
		state.command = {"git", "commit", string(state.commit_fixup_argument[:state.commit_fixup_argument_length]), "--no-edit", "", "", "", "", "", ""}
		state.command_count = 4
	case .Invalid:
		return .Invalid_Request
	}
	if allocation_error != nil do return .Allocation
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	if len(state.input) == 0 {
		os.close(state.child.stdin)
		state.child.stdin = nil
		state.stdin_closed = true
	}
	state.commit_phase = .Commit
	return .None
}

@(private)
repository_process_assign_commit_fixup_argument :: proc(state: ^Repository_Process_Data) -> bool {
	if state == nil || state.commit.mode != .Fixup do return false
	target := state.commit.arguments.target.observation.revision
	identity := revision_identity_string(&target)
	prefix := "--fixup="
	if len(identity) == 0 || len(prefix) + len(identity) > len(state.commit_fixup_argument) do return false
	state.commit_fixup_argument = {}
	copy(state.commit_fixup_argument[:len(prefix)], prefix)
	copy(state.commit_fixup_argument[len(prefix):len(prefix) + len(identity)], identity)
	state.commit_fixup_argument_length = u8(len(prefix) + len(identity))
	return true
}

@(private)
repository_process_start_commit_result_head :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.commit_phase != .Commit || state.failure != .None || state.exit_status != 0 ||
	   state.commit_outcome_retained {
		return .Invalid_Request
	}
	state.commit_output = state.output
	state.commit_diagnostic = state.diagnostic
	state.commit_outcome_retained = true
	state.output = {}
	state.diagnostic = {}
	repository_process_commit_reset_child(state)
	allocation_error: runtime.Allocator_Error
	state.output, allocation_error = make([dynamic]u8, 0, int(min(state.output_limit, 64 * KIBIBYTE)), state.allocator)
	if allocation_error == nil {
		state.diagnostic, allocation_error = make(
			[dynamic]u8,
			0,
			int(min(state.request.limits.diagnostic_bytes, 16 * KIBIBYTE)),
			state.allocator,
		)
	}
	if allocation_error != nil do return .Allocation
	state.command = {"git", "rev-parse", "--verify", "--quiet", "HEAD", "", "", "", "", ""}
	state.command_count = 5
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	os.close(state.child.stdin)
	state.child.stdin = nil
	state.stdin_closed = true
	state.commit_phase = .Observe_Result_Head
	return .None
}

@(private)
repository_process_finish_commit_result_head :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.commit_phase != .Observe_Result_Head || state.exit_status != 0 do return .Process_Failed
	identity, valid := repository_process_commit_output_identity(state)
	if !valid do return .Parse
	if state.commit.precondition.head.kind == .Revision && identity == state.commit.precondition.head.revision {
		return .Process_Failed
	}
	state.commit_resulting = identity
	clear(&state.output)
	clear(&state.diagnostic)
	state.commit_phase = .None
	state.state = .Completed
	return .None
}

@(private)
repository_process_commit_reset_child :: proc(state: ^Repository_Process_Data) {
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

@(private)
repository_process_advance_ref_observation :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.ref_phase == .None || state.request.kind != .Observe_Refs {
		return .Invalid_Request
	}
	switch state.ref_phase {
	case .Observe_Refs:
		if state.exit_status != 0 do return .Process_Failed
		state.ref_output = state.output
		state.output = {}
		return repository_process_start_ref_phase(state, .Observe_Remotes)
	case .Observe_Remotes:
		if state.exit_status != 0 do return .Process_Failed
		state.remote_output = state.output
		state.output = {}
		return repository_process_start_ref_phase(state, .Observe_Head)
	case .Observe_Head:
		if state.exit_status != 0 && state.exit_status != 1 do return .Process_Failed
		state.ref_phase = .None
		state.state = .Completed
		return .None
	case .None:
		return .Invalid_Request
	}
	return .Invalid_Request
}

@(private)
repository_process_start_ref_phase :: proc(
	state: ^Repository_Process_Data,
	phase: Ref_Process_Phase,
) -> Failure_Code {
	if state == nil || state.request.kind != .Observe_Refs || state.ref_phase == .None ||
	   (phase != .Observe_Remotes && phase != .Observe_Head) {
		return .Invalid_Request
	}
	repository_process_ref_reset_child(state)
	allocation_error: runtime.Allocator_Error
	state.output, allocation_error = make(
		[dynamic]u8,
		0,
		int(min(state.output_limit, 64 * KIBIBYTE)),
		state.allocator,
	)
	if allocation_error != nil do return .Allocation
	switch phase {
	case .Observe_Remotes:
		state.command = {"git", "remote", "", "", "", "", "", "", "", ""}
		state.command_count = 2
	case .Observe_Head:
		state.command = {"git", "rev-parse", "--verify", "--quiet", "HEAD", "", "", "", "", ""}
		state.command_count = 5
	case .None, .Observe_Refs:
		return .Invalid_Request
	}
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	state.ref_phase = phase
	return .None
}

@(private)
repository_process_ref_reset_child :: proc(state: ^Repository_Process_Data) {
	if state == nil do return
	local_child_close(&state.child)
	state.child = {}
	state.stdout_closed = false
	state.stderr_closed = false
	state.stdin_closed = false
	state.exit_status = 0
	clear(&state.input)
	clear(&state.diagnostic)
}

@(private)
repository_process_advance_sequence_observation :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.sequence_phase == .None || state.request.kind != .Observe_Sequence ||
	   state.exit_status != 0 {
		return .Process_Failed
	}
	switch state.sequence_phase {
	case .Resolve_Git_Directory:
		if !repository_process_assign_git_directory(state, state.output[:]) do return .Parse
		source, observed := repository_process_observe_sequence_source(state)
		if !observed do return .Parse
		state.sequence_source = source
		return repository_process_start_sequence_status(state)
	case .Observe_Status:
		current, observed := repository_process_observe_sequence_source(state)
		if !observed do return .Parse
		if current != state.sequence_source do return .Stale_Observation
		state.sequence_phase = .None
		state.state = .Completed
		return .None
	case .None:
		return .Invalid_Request
	}
	return .Invalid_Request
}

@(private)
repository_process_start_sequence_status :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.request.kind != .Observe_Sequence ||
	   state.sequence_phase != .Resolve_Git_Directory {
		return .Invalid_Request
	}
	repository_process_sequence_reset_child(state)
	limit := min(state.request.limits.stdout_bytes, state.request.sequence.limits.temporary_bytes)
	state.output_limit = limit
	state.command = {
		"git", "-c", "color.status=false", "status", "--porcelain=v2", "--branch",
		"--untracked-files=no", "-z", "", "",
	}
	state.command_count = 8
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	state.sequence_phase = .Observe_Status
	return .None
}

@(private)
repository_process_sequence_reset_child :: proc(state: ^Repository_Process_Data) {
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

@(private)
repository_process_assign_git_directory :: proc(state: ^Repository_Process_Data, output: []u8) -> bool {
	if state == nil || len(output) < 2 || output[len(output) - 1] != '\n' do return false
	path := output[:len(output) - 1]
	if len(path) == 0 || len(path) > len(state.git_directory) || path[0] != '/' do return false
	for value in path {
		if value == 0 || value == '\n' || value == '\r' do return false
	}
	state.git_directory = {}
	copy(state.git_directory[:len(path)], path)
	state.git_directory_length = u32(len(path))
	return true
}

@(private)
repository_process_observe_sequence_source :: proc(state: ^Repository_Process_Data) -> (Sequence_Source, bool) {
	if state == nil || state.git_directory_length == 0 ||
	   int(state.git_directory_length) > len(state.git_directory) {
		return {}, false
	}
	git_directory := string(state.git_directory[:state.git_directory_length])
	source := Sequence_Source{origin = .External, supported = true}
	marker_paths := SEQUENCE_MARKER_PATHS
	for marker in Sequence_Marker {
		path, path_error := os.join_path({git_directory, marker_paths[int(marker)]}, state.allocator)
		if path_error != nil do return {}, false
		present := os.exists(path)
		delete(path, state.allocator)
		if present do source.marker_mask |= u16(1) << u16(marker)
	}
	if source.marker_mask == 0 {
		source.kind = .None
		return source, true
	}
	families: u8
	if sequence_marker_present(source.marker_mask, .Merge) {
		source.kind = .Merge
		families += 1
	}
	if sequence_marker_present(source.marker_mask, .Rebase_Merge) ||
	   (sequence_marker_present(source.marker_mask, .Rebase_Apply) &&
	    !sequence_marker_present(source.marker_mask, .Apply)) {
		source.kind = .Rebase
		families += 1
	}
	if sequence_marker_present(source.marker_mask, .Cherry_Pick) {
		source.kind = .Cherry_Pick
		families += 1
	}
	if sequence_marker_present(source.marker_mask, .Revert) {
		source.kind = .Revert
		families += 1
	}
	if sequence_marker_present(source.marker_mask, .Bisect) {
		source.kind = .Bisect
		families += 1
	}
	if sequence_marker_present(source.marker_mask, .Apply) {
		source.kind = .Apply_Patches
		families += 1
	}
	if families != 1 {
		source.kind = .Other
		source.supported = false
	}
	if target_path := repository_process_sequence_target_path(source.kind); len(target_path) > 0 {
		path, path_error := os.join_path({git_directory, target_path}, state.allocator)
		if path_error != nil do return {}, false
		present := os.exists(path)
		delete(path, state.allocator)
		if present {
			target, bytes, read := repository_process_read_sequence_identity(git_directory, target_path, state.allocator)
			if !read do return {}, false
			source.target = target
			source.metadata_bytes += bytes
		}
	}
	position_path, total_path := repository_process_sequence_step_paths(source.kind, source.marker_mask)
	if len(position_path) > 0 {
		position, position_bytes, position_read := repository_process_read_sequence_u32(
			git_directory,
			position_path,
			state.allocator,
		)
		total, total_bytes, total_read := repository_process_read_sequence_u32(
			git_directory,
			total_path,
			state.allocator,
		)
		if !position_read || !total_read do return {}, false
		source.step = {position = position, total = total}
		source.metadata_bytes += position_bytes + total_bytes
	}
	if !sequence_source_is_valid(source, state.request.sequence.limits) do return {}, false
	return source, true
}

@(private)
sequence_marker_present :: proc(mask: u16, marker: Sequence_Marker) -> bool {
	return mask & (u16(1) << u16(marker)) != 0
}

@(private)
repository_process_sequence_target_path :: proc(kind: Sequence_Kind) -> string {
	switch kind {
	case .Merge: return "MERGE_HEAD"
	case .Rebase: return "REBASE_HEAD"
	case .Cherry_Pick: return "CHERRY_PICK_HEAD"
	case .Revert: return "REVERT_HEAD"
	case .None, .Bisect, .Apply_Patches, .Other, .Invalid: return ""
	}
	return ""
}

@(private)
repository_process_sequence_step_paths :: proc(kind: Sequence_Kind, mask: u16) -> (string, string) {
	switch kind {
	case .Rebase:
		if sequence_marker_present(mask, .Rebase_Merge) do return "rebase-merge/msgnum", "rebase-merge/end"
		return "rebase-apply/next", "rebase-apply/last"
	case .Apply_Patches:
		return "rebase-apply/next", "rebase-apply/last"
	case .Invalid, .None, .Merge, .Cherry_Pick, .Revert, .Bisect, .Other:
		return "", ""
	}
	return "", ""
}

@(private)
repository_process_read_sequence_identity :: proc(
	git_directory: string,
	relative: string,
	allocator: runtime.Allocator,
) -> (Revision_Identity, u64, bool) {
	data, count, read := repository_process_read_sequence_file(git_directory, relative, allocator)
	if !read do return {}, 0, false
	identity: Revision_Identity
	if !revision_identity_assign(&identity, string(data[:count])) do return {}, 0, false
	return identity, u64(count), true
}

@(private)
repository_process_read_sequence_u32 :: proc(
	git_directory: string,
	relative: string,
	allocator: runtime.Allocator,
) -> (u32, u64, bool) {
	data, count, read := repository_process_read_sequence_file(git_directory, relative, allocator)
	if !read || count == 0 do return 0, 0, false
	value: u32
	for byte in data[:count] {
		if byte < '0' || byte > '9' do return 0, 0, false
		digit := u32(byte - '0')
		if value > (max(u32) - digit) / 10 do return 0, 0, false
		value = value * 10 + digit
	}
	return value, u64(count), value > 0
}

@(private)
repository_process_read_sequence_file :: proc(
	git_directory: string,
	relative: string,
	allocator: runtime.Allocator,
) -> ([MAX_REVISION_ID_BYTES + 2]u8, int, bool) {
	data: [MAX_REVISION_ID_BYTES + 2]u8
	path, path_error := os.join_path({git_directory, relative}, allocator)
	if path_error != nil do return data, 0, false
	defer delete(path, allocator)
	file, open_error := os.open(path, {.Read})
	if open_error != nil do return data, 0, false
	defer os.close(file)
	count, read_error := os.read(file, data[:])
	if read_error != nil && read_error != io.Error.EOF do return data, 0, false
	if count == len(data) do return data, 0, false
	for count > 0 && (data[count - 1] == '\n' || data[count - 1] == '\r') do count -= 1
	return data, count, count > 0
}

@(private)
repository_process_assign_remote_configuration_command :: proc(
	state: ^Repository_Process_Data,
	phase: Remote_Configuration_Process_Phase,
) -> bool {
	if state == nil || !remote_identity_is_valid(state.remote_configuration) do return false
	suffix := ""
	switch phase {
	case .Observe_URL, .Check_URL:
		suffix = ".url"
	case .Observe_Fetch_Refspec, .Check_Fetch_Refspec:
		suffix = ".fetch"
	case .None, .Check_Operation, .Fetch:
		return false
	}
	remote := remote_name_string(&state.remote_configuration.name)
	prefix := "remote."
	required := len(prefix) + len(remote) + len(suffix)
	if len(remote) == 0 || required > len(state.remote_configuration_key) do return false
	state.remote_configuration_key = {}
	copy(state.remote_configuration_key[:len(prefix)], transmute([]u8)prefix)
	copy(state.remote_configuration_key[len(prefix):len(prefix) + len(remote)], transmute([]u8)remote)
	copy(state.remote_configuration_key[len(prefix) + len(remote):required], transmute([]u8)suffix)
	key := string(state.remote_configuration_key[:required])
	state.command = {"git", "config", "--null", "--get-all", "--", key, "", "", "", ""}
	state.command_count = 6
	return true
}

@(private)
repository_process_advance_remote_configuration :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.remote_configuration_phase == .None ||
	   (state.request.kind != .Observe_Remote_Configuration && state.request.kind != .Fetch_Remote) {
		return .Invalid_Request
	}
	switch state.remote_configuration_phase {
	case .Observe_URL, .Check_URL:
		if state.exit_status != 0 || len(state.output) == 0 do return .Remote_Unavailable
		repository_process_hash_remote_configuration_part(state, "url\x00", state.output[:])
		next := Remote_Configuration_Process_Phase.Observe_Fetch_Refspec
		if state.remote_configuration_phase == .Check_URL do next = .Check_Fetch_Refspec
		return repository_process_start_remote_configuration_phase(state, next)
	case .Observe_Fetch_Refspec, .Check_Fetch_Refspec:
		if state.exit_status != 0 && state.exit_status != 1 do return .Process_Failed
		repository_process_hash_remote_configuration_part(state, "fetch\x00", state.output[:])
		sha2.final(&state.remote_configuration_hash, state.remote_configuration_digest.bytes[:])
		clear(&state.output)
		clear(&state.diagnostic)
		if !remote_configuration_fingerprint_is_valid(state.remote_configuration_digest) do return .Parse
		if state.remote_configuration_phase == .Observe_Fetch_Refspec {
			state.remote_configuration_phase = .None
			state.state = .Completed
			return .None
		}
		if state.remote_configuration_digest != state.fetch.precondition.configuration.fingerprint {
			return .Stale_Observation
		}
		state.fetch_operation_marker = 0
		return repository_process_start_fetch_operation_check(state)
	case .Check_Operation:
		if state.exit_status != 0 do return .Process_Failed
		active, inspected := repository_process_fetch_operation_is_active(state)
		if !inspected do return .Parse
		if active do return .Action_Unavailable
		state.fetch_operation_marker += 1
		if int(state.fetch_operation_marker) < len(COMMIT_OPERATION_MARKERS) {
			return repository_process_start_fetch_operation_check(state)
		}
		return repository_process_start_fetch_child(state)
	case .Fetch:
		if state.exit_status != 0 do return .Process_Failed
		state.remote_configuration_phase = .None
		state.state = .Completed
		return .None
	case .None:
		return .Invalid_Request
	}
	return .Invalid_Request
}

@(private)
repository_process_hash_remote_configuration_part :: proc(
	state: ^Repository_Process_Data,
	label: string,
	bytes: []u8,
) {
	if state == nil do return
	sha2.update(&state.remote_configuration_hash, transmute([]u8)label)
	sha2.update(&state.remote_configuration_hash, bytes)
}

@(private)
repository_process_start_remote_configuration_phase :: proc(
	state: ^Repository_Process_Data,
	phase: Remote_Configuration_Process_Phase,
) -> Failure_Code {
	if state == nil ||
	   (phase != .Observe_Fetch_Refspec && phase != .Check_Fetch_Refspec) {
		return .Invalid_Request
	}
	repository_process_remote_configuration_reset_child(state)
	state.remote_configuration_phase = phase
	if !repository_process_assign_remote_configuration_command(state, phase) do return .Invalid_Request
	state.child, state.failure = repository_process_start_child(state)
	return state.failure
}

@(private)
repository_process_start_fetch_child :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.request.kind != .Fetch_Remote ||
	   state.remote_configuration_phase != .Check_Operation ||
	   int(state.fetch_operation_marker) != len(COMMIT_OPERATION_MARKERS) ||
	   !fetch_request_is_valid(state.fetch) {
		return .Invalid_Request
	}
	repository_process_remote_configuration_reset_child(state)
	remote := remote_name_string(&state.remote_configuration.name)
	if len(remote) == 0 do return .Remote_Unavailable
	state.command = {
		"git", "-c", "credential.interactive=false", "fetch", "--no-recurse-submodules",
		"--no-write-fetch-head", "--", remote, "", "",
	}
	state.command_count = 8
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	state.remote_configuration_phase = .Fetch
	state.fetch_started = true
	return .None
}

@(private)
repository_process_start_fetch_operation_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.request.kind != .Fetch_Remote ||
	   (state.remote_configuration_phase != .Check_Fetch_Refspec &&
	    state.remote_configuration_phase != .Check_Operation) ||
	   int(state.fetch_operation_marker) >= len(COMMIT_OPERATION_MARKERS) {
		return .Invalid_Request
	}
	repository_process_remote_configuration_reset_child(state)
	markers := COMMIT_OPERATION_MARKERS
	state.command = {
		"git", "rev-parse", "--git-path", markers[int(state.fetch_operation_marker)],
		"", "", "", "", "", "",
	}
	state.command_count = 4
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	state.remote_configuration_phase = .Check_Operation
	return .None
}

@(private)
repository_process_fetch_operation_is_active :: proc(state: ^Repository_Process_Data) -> (active, inspected: bool) {
	if state == nil || state.remote_configuration_phase != .Check_Operation ||
	   int(state.fetch_operation_marker) >= len(COMMIT_OPERATION_MARKERS) ||
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
repository_process_remote_configuration_reset_child :: proc(state: ^Repository_Process_Data) {
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

@(private)
repository_process_assign_push_configuration_command :: proc(
	state: ^Repository_Process_Data,
	phase: Push_Process_Phase,
) -> bool {
	if state == nil || !remote_identity_is_valid(state.push_configuration) do return false
	suffix := ""
	switch phase {
	case .Observe_URL, .Check_URL:
		suffix = ".url"
	case .Observe_Push_URL, .Check_Push_URL:
		suffix = ".pushurl"
	case .None, .Check_Source, .Check_Tracking_Remote, .Check_Tracking_Merge, .Check_Operation, .Push:
		return false
	}
	remote := remote_name_string(&state.push_configuration.name)
	prefix := "remote."
	required := len(prefix) + len(remote) + len(suffix)
	if len(remote) == 0 || required > len(state.remote_configuration_key) do return false
	state.remote_configuration_key = {}
	copy(state.remote_configuration_key[:len(prefix)], transmute([]u8)prefix)
	copy(state.remote_configuration_key[len(prefix):len(prefix) + len(remote)], transmute([]u8)remote)
	copy(state.remote_configuration_key[len(prefix) + len(remote):required], transmute([]u8)suffix)
	key := string(state.remote_configuration_key[:required])
	state.command = {"git", "config", "--null", "--get-all", "--", key, "", "", "", ""}
	state.command_count = 6
	return true
}

@(private)
repository_process_advance_push :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.push_phase == .None ||
	   (state.request.kind != .Observe_Push_Configuration && state.request.kind != .Push_Remote) {
		return .Invalid_Request
	}
	switch state.push_phase {
	case .Observe_URL, .Check_URL:
		if state.exit_status != 0 || len(state.output) == 0 do return .Remote_Unavailable
		repository_process_hash_push_configuration_part(state, "url\x00", state.output[:])
		next := Push_Process_Phase.Observe_Push_URL
		if state.push_phase == .Check_URL do next = .Check_Push_URL
		return repository_process_start_push_phase(state, next)
	case .Observe_Push_URL, .Check_Push_URL:
		if state.exit_status != 0 && state.exit_status != 1 do return .Process_Failed
		repository_process_hash_push_configuration_part(state, "pushurl\x00", state.output[:])
		sha2.final(&state.push_configuration_hash, state.push_configuration_digest.bytes[:])
		clear(&state.output)
		clear(&state.diagnostic)
		if !remote_configuration_fingerprint_is_valid(state.push_configuration_digest) do return .Parse
		if state.push_phase == .Observe_Push_URL {
			state.push_phase = .None
			state.state = .Completed
			return .None
		}
		if state.push_configuration_digest != state.push.precondition.configuration.fingerprint {
			return .Stale_Observation
		}
		return repository_process_start_push_source_check(state)
	case .Check_Source:
		if state.exit_status != 0 || !repository_process_push_source_matches(state) {
			return .Stale_Observation
		}
		return repository_process_start_push_tracking_check(state, .Check_Tracking_Remote)
	case .Check_Tracking_Remote:
		if state.exit_status != 0 || !repository_process_push_tracking_value_matches(state, true) {
			return .Stale_Observation
		}
		return repository_process_start_push_tracking_check(state, .Check_Tracking_Merge)
	case .Check_Tracking_Merge:
		if state.exit_status != 0 || !repository_process_push_tracking_value_matches(state, false) {
			return .Stale_Observation
		}
		state.push_operation_marker = 0
		return repository_process_start_push_operation_check(state)
	case .Check_Operation:
		if state.exit_status != 0 do return .Process_Failed
		active, inspected := repository_process_push_operation_is_active(state)
		if !inspected do return .Parse
		if active do return .Action_Unavailable
		state.push_operation_marker += 1
		if int(state.push_operation_marker) < len(COMMIT_OPERATION_MARKERS) {
			return repository_process_start_push_operation_check(state)
		}
		return repository_process_start_push_child(state)
	case .Push:
		if state.exit_status != 0 do return .Process_Failed
		state.push_phase = .None
		state.state = .Completed
		return .None
	case .None:
		return .Invalid_Request
	}
	return .Invalid_Request
}

@(private)
repository_process_hash_push_configuration_part :: proc(
	state: ^Repository_Process_Data,
	label: string,
	bytes: []u8,
) {
	if state == nil do return
	sha2.update(&state.push_configuration_hash, transmute([]u8)label)
	sha2.update(&state.push_configuration_hash, bytes)
}

@(private)
repository_process_start_push_phase :: proc(
	state: ^Repository_Process_Data,
	phase: Push_Process_Phase,
) -> Failure_Code {
	if state == nil || (phase != .Observe_Push_URL && phase != .Check_Push_URL) {
		return .Invalid_Request
	}
	repository_process_remote_configuration_reset_child(state)
	state.push_phase = phase
	if !repository_process_assign_push_configuration_command(state, phase) do return .Invalid_Request
	state.child, state.failure = repository_process_start_child(state)
	return state.failure
}

@(private)
repository_process_start_push_source_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.request.kind != .Push_Remote || state.push_phase != .Check_Push_URL ||
	   !push_request_is_valid(state.push) {
		return .Invalid_Request
	}
	repository_process_remote_configuration_reset_child(state)
	source := state.push.precondition.source.name
	name := ref_name_string(&source)
	suffix := "^{commit}"
	if len(name) == 0 || len(name) + len(suffix) > len(state.push_source_argument) do return .Invalid_Request
	state.push_source_argument = {}
	copy(state.push_source_argument[:len(name)], transmute([]u8)name)
	copy(state.push_source_argument[len(name):len(name) + len(suffix)], transmute([]u8)suffix)
	argument := string(state.push_source_argument[:len(name) + len(suffix)])
	state.command = {"git", "rev-parse", "--verify", "--quiet", argument, "", "", "", "", ""}
	state.command_count = 5
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	state.push_phase = .Check_Source
	return .None
}

@(private)
repository_process_start_push_tracking_check :: proc(
	state: ^Repository_Process_Data,
	phase: Push_Process_Phase,
) -> Failure_Code {
	if state == nil || state.request.kind != .Push_Remote ||
	   (phase != .Check_Tracking_Remote && phase != .Check_Tracking_Merge) ||
	   !push_request_is_valid(state.push) {
		return .Invalid_Request
	}
	repository_process_remote_configuration_reset_child(state)
	source := state.push.precondition.source.name
	name := ref_name_string(&source)
	branch_prefix := "refs/heads/"
	if len(name) <= len(branch_prefix) || name[:len(branch_prefix)] != branch_prefix do return .Invalid_Request
	short := name[len(branch_prefix):]
	prefix := "branch."
	suffix := ".remote"
	if phase == .Check_Tracking_Merge do suffix = ".merge"
	required := len(prefix) + len(short) + len(suffix)
	if required > len(state.remote_configuration_key) do return .Invalid_Request
	state.remote_configuration_key = {}
	copy(state.remote_configuration_key[:len(prefix)], transmute([]u8)prefix)
	copy(state.remote_configuration_key[len(prefix):len(prefix) + len(short)], transmute([]u8)short)
	copy(state.remote_configuration_key[len(prefix) + len(short):required], transmute([]u8)suffix)
	key := string(state.remote_configuration_key[:required])
	state.command = {"git", "config", "--null", "--get-all", "--", key, "", "", "", ""}
	state.command_count = 6
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	state.push_phase = phase
	return .None
}

@(private)
repository_process_start_push_operation_check :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.request.kind != .Push_Remote ||
	   (state.push_phase != .Check_Tracking_Merge && state.push_phase != .Check_Operation) ||
	   int(state.push_operation_marker) >= len(COMMIT_OPERATION_MARKERS) {
		return .Invalid_Request
	}
	repository_process_remote_configuration_reset_child(state)
	markers := COMMIT_OPERATION_MARKERS
	state.command = {
		"git", "rev-parse", "--git-path", markers[int(state.push_operation_marker)],
		"", "", "", "", "", "",
	}
	state.command_count = 4
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	state.push_phase = .Check_Operation
	return .None
}

@(private)
repository_process_start_push_child :: proc(state: ^Repository_Process_Data) -> Failure_Code {
	if state == nil || state.request.kind != .Push_Remote || state.push_phase != .Check_Operation ||
	   int(state.push_operation_marker) != len(COMMIT_OPERATION_MARKERS) || !push_request_is_valid(state.push) {
		return .Invalid_Request
	}
	repository_process_remote_configuration_reset_child(state)
	remote := state.push.precondition.destination.remote.name
	remote_name := remote_name_string(&remote)
	source := state.push.precondition.source.name
	source_name := ref_name_string(&source)
	destination := state.push.precondition.destination.branch
	destination_name := ref_name_string(&destination)
	required := len(source_name) + 1 + len(destination_name)
	if len(remote_name) == 0 || len(source_name) == 0 || len(destination_name) == 0 ||
	   required > len(state.push_refspec) {
		return .Invalid_Request
	}
	state.push_refspec = {}
	copy(state.push_refspec[:len(source_name)], transmute([]u8)source_name)
	state.push_refspec[len(source_name)] = ':'
	copy(
		state.push_refspec[len(source_name) + 1:required],
		transmute([]u8)destination_name,
	)
	refspec := string(state.push_refspec[:required])
	state.command = {
		"git", "-c", "credential.interactive=false", "push", "--porcelain", "--",
		remote_name, refspec, "", "",
	}
	state.command_count = 8
	state.child, state.failure = repository_process_start_child(state)
	if state.failure != .None do return state.failure
	state.push_phase = .Push
	state.push_started = true
	return .None
}

@(private)
repository_process_push_source_matches :: proc(state: ^Repository_Process_Data) -> bool {
	if state == nil || state.push_phase != .Check_Source || len(state.output) < 2 ||
	   state.output[len(state.output) - 1] != '\n' {
		return false
	}
	expected := state.push.precondition.source.object
	text := revision_identity_string(&expected)
	return len(state.output) == len(text) + 1 && string(state.output[:len(text)]) == text
}

@(private)
repository_process_push_tracking_value_matches :: proc(
	state: ^Repository_Process_Data,
	remote_value: bool,
) -> bool {
	if state == nil || len(state.output) < 2 || state.output[len(state.output) - 1] != 0 do return false
	expected := ""
	if remote_value {
		remote := state.push.precondition.destination.remote.name
		expected = remote_name_string(&remote)
	} else {
		destination := state.push.precondition.destination.branch
		expected = ref_name_string(&destination)
	}
	return len(state.output) == len(expected) + 1 && string(state.output[:len(expected)]) == expected
}

@(private)
repository_process_push_operation_is_active :: proc(state: ^Repository_Process_Data) -> (active, inspected: bool) {
	if state == nil || state.push_phase != .Check_Operation ||
	   int(state.push_operation_marker) >= len(COMMIT_OPERATION_MARKERS) ||
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

/* repository_process_poll reads bounded output, reaps, and enforces deadline. */
repository_process_poll :: proc(
	process: ^Repository_Process,
	now_ns: i64,
) -> (Repository_Process_Poll, bool) {
	state := repository_process_data(process)
	if state == nil do return Repository_Process_Poll{state = .Closed, failure = .Invalid_Request}, false
	result := Repository_Process_Poll{state = state.state, exit_status = state.exit_status, failure = state.failure}
	if state.state != .Running do return result, true
	if state.associated && now_ns < state.lifecycle_timing.updated_ns {
		result.failure = .Process_Record_Stale
		return result, false
	}
	repository_process_note_poll(state, now_ns)

	if state.child.live && state.termination.reason == .None && now_ns >= state.deadline_ns {
		if _, failure := repository_process_begin_termination(state, .Timeout, now_ns); failure != .None {
			repository_process_note_failure(state, .Signal, failure)
			state.failure = failure
			state.state = .Failed
		}
	}
	if state.state == .Running && state.termination.reason == .None && len(state.input) > 0 && !state.stdin_closed {
		_, completed, failure := repository_process_write_input(state)
		if failure != .None {
			repository_process_note_failure(state, .Input, failure)
			_ = os.process_kill(state.child.process)
			state.failure = failure
			state.state = .Failed
		} else if completed {
			state.stdin_closed = true
		}
	}
	if state.state == .Running {
		read, closed, failure := repository_process_read_stream(state.child.stdout, &state.output, state.output_limit)
		result.read_bytes = read
		state.stdout_closed = state.stdout_closed || closed
		if failure != .None {
			if failure == .Output_Limit do state.output_truncated = true
			repository_process_note_failure(state, .Output, failure)
			_ = os.process_kill(state.child.process)
			state.failure = failure
			state.state = .Failed
		}
	}
	if state.state == .Running {
		read, closed, failure := repository_process_read_stream(state.child.stderr, &state.diagnostic, state.request.limits.diagnostic_bytes)
		result.diagnostic_bytes = read
		state.stderr_closed = state.stderr_closed || closed
		if failure != .None {
			if failure == .Output_Limit do state.diagnostic_truncated = true
			repository_process_note_failure(state, .Diagnostic, failure)
			_ = os.process_kill(state.child.process)
			state.failure = failure
			state.state = .Failed
		}
	}
	if state.child.live {
		was_reaped := state.child.reaped
		exited, exit_status, failure := local_child_poll(&state.child)
		if failure != .None {
			repository_process_note_failure(state, .Reap, failure)
			state.failure = failure
			state.state = .Failed
		} else if exited {
			state.exit_status = exit_status
			if !was_reaped && state.child.reaped do repository_process_note_child_reaped(state, now_ns, exit_status)
			if state.termination.reason == .None && exit_status != 0 && state.failure == .None &&
			   !repository_process_commit_preflight_active(state) &&
			   !repository_process_branch_exit_is_expected(state, exit_status) &&
			   !repository_process_tag_exit_is_expected(state, exit_status) &&
			   !repository_process_merge_exit_is_expected(state, exit_status) &&
			   !repository_process_rebase_exit_is_expected(state, exit_status) &&
			   !repository_process_revision_sequence_exit_is_expected(state, exit_status) &&
			   !repository_process_bisect_exit_is_expected(state, exit_status) &&
			   !repository_process_conflict_resolution_exit_is_expected(state, exit_status) &&
			   !(state.ref_phase == .Observe_Head && exit_status == 1) &&
			   !((state.remote_configuration_phase == .Observe_Fetch_Refspec ||
			      state.remote_configuration_phase == .Check_Fetch_Refspec) && exit_status == 1) &&
			   !((state.push_phase == .Observe_Push_URL || state.push_phase == .Check_Push_URL) &&
			     exit_status == 1) &&
			   !(state.request.kind == .Inspect_Path && state.request.target.path != Path_ID(0) && exit_status == 1) {
				state.failure = .Process_Failed
				repository_process_note_failure(state, .Exit, .Process_Failed, exit_status, true)
			}
		} else if state.termination.phase == .Graceful_Signal &&
		          now_ns >= state.termination.grace_deadline_ns {
			if escalation_failure := repository_process_escalate_termination(state, now_ns);
			   escalation_failure != .None {
				state.failure = escalation_failure
				state.state = .Failed
			}
		}
	}
	if !state.child.live && state.state == .Running && state.stdout_closed && state.stderr_closed {
		if state.termination.reason != .None {
			repository_process_finish_termination(state, now_ns)
		} else if repository_process_commit_preflight_active(state) {
			if failure := repository_process_advance_commit_preflight(state); failure != .None {
				state.failure = failure
				state.state = .Failed
			}
		} else if state.sequence_phase != .None {
			if failure := repository_process_advance_sequence_observation(state); failure != .None {
				state.failure = failure
				state.state = .Failed
			}
		} else if state.ref_phase != .None {
			if failure := repository_process_advance_ref_observation(state); failure != .None {
				state.failure = failure
				state.state = .Failed
			}
		} else if state.remote_configuration_phase != .None {
			if failure := repository_process_advance_remote_configuration(state); failure != .None {
				state.failure = failure
				state.state = .Failed
			}
		} else if state.push_phase != .None {
			if failure := repository_process_advance_push(state); failure != .None {
				state.failure = failure
				state.state = .Failed
			}
		} else if state.branch_phase != .None {
			if failure := repository_process_advance_branch(state); failure != .None {
				state.failure = failure
				state.state = .Failed
			}
		} else if state.tag_phase != .None {
			if failure := repository_process_advance_tag(state); failure != .None {
				state.failure = failure
				state.state = .Failed
			}
		} else if state.merge_phase != .None {
			if failure := repository_process_advance_merge(state); failure != .None {
				state.failure = failure
				state.state = .Failed
			}
		} else if state.rebase_phase != .None {
			if failure := repository_process_advance_rebase(state); failure != .None {
				state.failure = failure
				state.state = .Failed
			}
		} else if state.revision_sequence_phase != .None {
			if failure := repository_process_advance_revision_sequence(state); failure != .None {
				state.failure = failure
				state.state = .Failed
			}
		} else if state.manual_bisect_phase != .None {
			if failure := repository_process_advance_bisect(state); failure != .None {
				state.failure = failure
				state.state = .Failed
			}
		} else if state.conflict_resolution_phase != .None {
			if failure := repository_process_advance_conflict_resolution(state); failure != .None {
				state.failure = failure
				state.state = .Failed
			}
		} else if state.inspection_phase != .None {
			if failure := repository_process_advance_inspection_workflow(state); failure != .None {
				state.failure = failure
				state.state = .Failed
			}
		} else if state.commit_phase == .Commit && state.failure == .None && state.exit_status == 0 {
			if failure := repository_process_start_commit_result_head(state); failure != .None {
				state.failure = failure
				state.state = .Failed
			}
		} else if state.commit_phase == .Observe_Result_Head && state.failure == .None {
			if failure := repository_process_finish_commit_result_head(state); failure != .None {
				state.failure = failure
				state.state = .Failed
			}
		} else {
			state.state = state.failure == .None ? .Completed : .Failed
		}
	}
	result.state = state.state
	result.exit_status = state.exit_status
	result.failure = state.failure
	repository_process_note_phase_and_terminal(state, now_ns)
	if state.state != .Running do repository_process_close_terminal_child(state, now_ns)
	return result, true
}

/* repository_process_take_partial_index_action copies one hunk-action outcome. */
repository_process_take_partial_index_action :: proc(
	process: ^Repository_Process,
	allocator := context.allocator,
) -> (Partial_Index_Action_Result, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil ||
	   (state.state != .Completed && state.state != .Failed) ||
	   !partial_index_action_request_descriptor_is_valid(state.partial_action) {
		return {}, false, .Invalid_Request
	}
	return partial_index_action_result_open(
		state.partial_action,
		state.exit_status,
		state.output[:],
		state.diagnostic[:],
		state.failure,
		allocator,
	)
}

/* repository_process_take_grouped_index_action copies one group-action outcome. */
repository_process_take_grouped_index_action :: proc(
	process: ^Repository_Process,
	allocator := context.allocator,
) -> (Grouped_Index_Action_Result, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || (state.state != .Completed && state.state != .Failed) ||
	   !grouped_index_action_request_descriptor_is_valid(state.grouped_action) {
		return {}, false, .Invalid_Request
	}
	return grouped_index_action_result_open(
		state.grouped_action,
		state.exit_status,
		state.output[:],
		state.diagnostic[:],
		state.failure,
		allocator,
	)
}

/* repository_process_take_discard_action copies one terminal discard outcome. */
repository_process_take_discard_action :: proc(
	process: ^Repository_Process,
	allocator := context.allocator,
) -> (Discard_Action_Result, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || (state.state != .Completed && state.state != .Failed) ||
	   !discard_action_request_is_valid(state.discard_action) || !state.discard_action.confirmed {
		return {}, false, .Invalid_Request
	}
	return discard_action_result_open(
		state.discard_action,
		state.exit_status,
		state.output[:],
		state.diagnostic[:],
		state.failure,
		allocator,
	)
}

/* repository_process_take_index_action copies one terminal mutation outcome. */
repository_process_take_index_action :: proc(
	process: ^Repository_Process,
	allocator := context.allocator,
) -> (Index_Action_Result, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil ||
	   (state.state != .Completed && state.state != .Failed) ||
	   !index_action_request_is_valid(state.index_action) {
		return {}, false, .Invalid_Request
	}
	return index_action_result_open(
		state.index_action,
		state.exit_status,
		state.output[:],
		state.diagnostic[:],
		state.failure,
		allocator,
	)
}

/* repository_process_take_commit_precondition copies one observed exact commit precondition. */
repository_process_take_commit_precondition :: proc(
	process: ^Repository_Process,
) -> (Commit_Precondition, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || state.state != .Completed || state.request.kind != .Commit_Normal ||
	   state.commit_phase != .None || !commit_precondition_is_valid(state.commit_precondition) {
		return {}, false, .Invalid_Request
	}
	return state.commit_precondition, true, .None
}

/* repository_process_take_commit copies one revalidated checked-commit outcome. */
repository_process_take_commit :: proc(
	process: ^Repository_Process,
	allocator := context.allocator,
) -> (Commit_Result, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || (state.state != .Completed && state.state != .Failed) ||
	   state.request.kind != .Commit_Normal || !commit_request_is_valid(state.commit) {
		return {}, false, .Invalid_Request
	}
	output, diagnostic := repository_process_commit_result_payloads(state)
	return commit_result_open(
		state.commit,
		state.commit_resulting,
		state.exit_status,
		output,
		diagnostic,
		state.failure,
		allocator,
	)
}

/* repository_process_take_remote_configuration returns one credential-free exact configuration identity. */
repository_process_take_remote_configuration :: proc(
	process: ^Repository_Process,
) -> (Remote_Configuration_Identity, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || state.state != .Completed ||
	   state.request.kind != .Observe_Remote_Configuration ||
	   state.remote_configuration_phase != .None ||
	   !remote_identity_is_valid(state.remote_configuration) ||
	   !remote_configuration_fingerprint_is_valid(state.remote_configuration_digest) {
		return {}, false, .Invalid_Request
	}
	return {
		remote = state.remote_configuration,
		fingerprint = state.remote_configuration_digest,
	}, true, .None
}

/* repository_process_take_fetch copies one terminal started or pre-start-cancelled fetch outcome. */
repository_process_take_fetch :: proc(
	process: ^Repository_Process,
	allocator := context.allocator,
) -> (Fetch_Result, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || (state.state != .Completed && state.state != .Failed) ||
	   state.request.kind != .Fetch_Remote || !fetch_request_is_valid(state.fetch) {
		return {}, false, .Invalid_Request
	}
	if !state.fetch_started && state.failure != .Cancelled do return {}, false, state.failure
	return fetch_result_open(
		state.fetch,
		state.fetch_started,
		state.exit_status,
		state.output[:],
		state.diagnostic[:],
		state.failure,
		allocator,
	)
}

/* repository_process_take_push_configuration returns one credential-free exact push destination identity. */
repository_process_take_push_configuration :: proc(
	process: ^Repository_Process,
) -> (Push_Configuration_Identity, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || state.state != .Completed ||
	   state.request.kind != .Observe_Push_Configuration || state.push_phase != .None ||
	   !remote_identity_is_valid(state.push_configuration) ||
	   !remote_configuration_fingerprint_is_valid(state.push_configuration_digest) {
		return {}, false, .Invalid_Request
	}
	return {
		remote = state.push_configuration,
		fingerprint = state.push_configuration_digest,
	}, true, .None
}

/* repository_process_take_push copies one started or pre-start-cancelled push transport outcome. */
repository_process_take_push :: proc(
	process: ^Repository_Process,
	allocator := context.allocator,
) -> (Push_Result, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || (state.state != .Completed && state.state != .Failed) ||
	   state.request.kind != .Push_Remote || !push_request_is_valid(state.push) {
		return {}, false, .Invalid_Request
	}
	if !state.push_started && state.failure != .Cancelled do return {}, false, state.failure
	return push_result_open(
		state.push,
		state.push_started,
		state.exit_status,
		state.output[:],
		state.diagnostic[:],
		state.failure,
		allocator,
	)
}

@(private)
repository_process_commit_result_payloads :: proc(state: ^Repository_Process_Data) -> (output, diagnostic: []u8) {
	if state == nil do return nil, nil
	if state.commit_outcome_retained do return state.commit_output[:], state.commit_diagnostic[:]
	return state.output[:], state.diagnostic[:]
}

@(private)
status_observation_path_by_id :: proc(observation: ^Status_Observation, wanted: Path_ID) -> (Status_Path, bool) {
	path_count, available := status_observation_path_count(observation)
	if !available do return {}, false
	for path_index in 0 ..< path_count {
		path, found := status_observation_path(observation, path_index)
		if found && path.id == wanted do return path, true
	}
	return {}, false
}

/* repository_process_output exposes retained stdout only after process completion. */
repository_process_output :: proc(process: ^Repository_Process) -> ([]u8, bool) {
	state := repository_process_data(process)
	if state == nil || state.state != .Completed do return nil, false
	return state.output[:], true
}

/* repository_process_revision_output exposes retained revision-inspection stdout after completion or bounded truncation. */
repository_process_revision_output :: proc(process: ^Repository_Process) -> ([]u8, bool) {
	state := repository_process_data(process)
	if state == nil ||
	   (state.state != .Completed && state.failure != .Output_Limit) {
		return nil, false
	}
	switch state.request.kind {
	case .Inspect_Revision_Detail_Metadata, .Inspect_Revision_Detail_Comparison,
	     .Inspect_Revision_Range_Summary, .Inspect_Revision_Range_Comparison:
		return state.output[:], true
	case .Observe_Status, .Observe_Sequence, .Observe_History, .Observe_Refs, .Observe_Remote_Configuration,
	     .Observe_Push_Configuration,
	     .Invalid, .Inspect_Path,
	     .Stage_Path, .Unstage_Path, .Stage_Diff_Unit, .Unstage_Diff_Unit,
	     .Stage_Group, .Unstage_Group, .Discard_Path, .Commit_Normal, .Fetch_Remote, .Push_Remote, .Branch_Local, .Tag_Local,
	     .Merge_Repository, .Rebase_Repository, .Cherry_Pick_Repository, .Revert_Repository, .Bisect_Repository, .Resolve_Conflict,
	     .Inspection_Workflow, .External_Operation, .Raw_Command:
		return nil, false
	}
	return nil, false
}

/* repository_process_diagnostic exposes retained bounded standard error. */
repository_process_diagnostic :: proc(process: ^Repository_Process) -> ([]u8, bool) {
	state := repository_process_data(process)
	if state == nil do return nil, false
	return state.diagnostic[:], true
}

/* repository_process_usage copies exact retained process-payload accounting. */
repository_process_usage :: proc(process: ^Repository_Process) -> (Repository_Process_Usage, bool) {
	state := repository_process_data(process)
	if state == nil do return {}, false
	return Repository_Process_Usage {
		input_bytes = u64(len(state.input)),
		output_bytes = u64(len(state.output)) + u64(len(state.commit_output)) +
		               u64(len(state.ref_output)) + u64(len(state.remote_output)) +
		               u64(len(state.revision_sequence_output)),
		diagnostic_bytes = u64(len(state.diagnostic)) + u64(len(state.commit_diagnostic)) +
		                   u64(len(state.revision_sequence_diagnostic)),
	}, true
}

@(private)
repository_process_write_input :: proc(
	state: ^Repository_Process_Data,
) -> (u64, bool, Failure_Code) {
	if state == nil || state.child.stdin == nil || state.stdin_closed do return 0, false, .Cleanup
	if state.input_offset >= u64(len(state.input)) {
		os.close(state.child.stdin)
		state.child.stdin = nil
		return 0, true, .None
	}
	start := int(state.input_offset)
	end := int(min(u64(len(state.input)), state.input_offset + 64 * KIBIBYTE))
	count, write_error := os.write(state.child.stdin, state.input[start:end])
	if write_error == nil {
		if count <= 0 do return 0, false, .Process_Failed
		state.input_offset += u64(count)
		if state.input_offset == u64(len(state.input)) {
			os.close(state.child.stdin)
			state.child.stdin = nil
			return u64(count), true, .None
		}
		return u64(count), false, .None
	}
	if repository_process_error_is_again(write_error) do return 0, false, .None
	return 0, false, .Process_Failed
}

/* repository_process_close kills, reaps, closes streams, and releases storage. */
repository_process_close :: proc(process: ^Repository_Process) {
	state := repository_process_data(process)
	if state == nil do return
	repository_process_data_destroy(state)
	process^ = {}
}

/* repository_process_cancel stops one running repository request while retaining its bounded outcome. */
repository_process_cancel :: proc(process: ^Repository_Process) -> bool {
	state := repository_process_data(process)
	if state == nil || state.state != .Running do return false
	repository_process_note_failure(state, .Cancellation, .Cancelled)
	_, close_stage, close_failure := local_child_close_checked(&state.child)
	if close_failure != .None do repository_process_note_failure(state, close_stage, close_failure)
	state.stdout_closed = true
	state.stderr_closed = true
	state.stdin_closed = true
	state.failure = .Cancelled
	state.state = .Failed
	return true
}

@(private)
repository_process_data :: proc(process: ^Repository_Process) -> ^Repository_Process_Data {
	if process == nil || process.state == nil do return nil
	return cast(^Repository_Process_Data)process.state
}

@(private)
repository_process_read_stream :: proc(
	file: ^os.File,
	destination: ^[dynamic]u8,
	limit: u64,
) -> (u64, bool, Failure_Code) {
	if file == nil || destination == nil do return 0, false, .Cleanup
	storage: [64 * KIBIBYTE]u8
	remaining := limit - u64(len(destination^))
	read_limit := int(min(u64(len(storage)), remaining + 1))
	count, read_error := os.read(file, storage[:read_limit])
	if read_error == nil {
		if count == 0 do return 0, true, .None
		if u64(count) > remaining do return u64(count), false, .Output_Limit
		_, append_error := append(destination, ..storage[:count])
		if append_error != nil do return u64(count), false, .Allocation
		return u64(count), false, .None
	}
	if repository_process_error_is_again(read_error) do return 0, false, .None
	if repository_process_error_is_closed(read_error) do return 0, true, .None
	return 0, false, .Process_Failed
}

@(private)
local_child_start :: proc(command: []string, working_directory: string) -> (Local_Child, Failure_Code) {
	return local_child_start_with_environment(command, working_directory, nil)
}

@(private)
local_child_start_with_environment :: proc(
	command: []string,
	working_directory: string,
	environment: []string,
) -> (Local_Child, Failure_Code) {
	stdin_read, stdin_write, stdin_error := os.pipe()
	if stdin_error != nil do return {}, .Process_Failed
	stdout_read, stdout_write, stdout_error := os.pipe()
	if stdout_error != nil {
		local_close_files(stdin_read, stdin_write)
		return {}, .Process_Failed
	}
	stderr_read, stderr_write, stderr_error := os.pipe()
	if stderr_error != nil {
		local_close_files(stdin_read, stdin_write, stdout_read, stdout_write)
		return {}, .Process_Failed
	}
	if !local_file_nonblocking(stdin_write) || !local_file_nonblocking(stdout_read) ||
	   !local_file_nonblocking(stderr_read) {
		local_close_files(stdin_read, stdin_write, stdout_read, stdout_write, stderr_read, stderr_write)
		return {}, .Process_Failed
	}
	child, child_error := os.process_start(os.Process_Desc {
		working_dir = working_directory,
		command = command,
		env = environment,
		stdin = stdin_read,
		stdout = stdout_write,
		stderr = stderr_write,
	})
	local_close_files(stdin_read, stdout_write, stderr_write)
	if child_error != nil {
		local_close_files(stdin_write, stdout_read, stderr_read)
		return {}, .Executable_Unavailable
	}
	return Local_Child{process = child, stdin = stdin_write, stdout = stdout_read, stderr = stderr_read, live = true}, .None
}

@(private)
local_child_poll :: proc(child: ^Local_Child) -> (bool, i32, Failure_Code) {
	if child == nil || !child.live do return false, 0, .None
	result, wait_error := os.process_wait(child.process, 0)
	if wait_error != nil {
		if repository_process_error_is_timeout(wait_error) do return false, 0, .None
		return false, 0, .Process_Failed
	}
	child.live = false
	child.reaped = true
	return result.exited, i32(result.exit_code), .None
}

@(private)
local_child_close :: proc(child: ^Local_Child) {
	_, _, _ = local_child_close_checked(child)
}

@(private)
local_child_close_checked :: proc(
	child: ^Local_Child,
) -> (bool, Repository_Process_Failure_Stage, Failure_Code) {
	if child == nil do return false, .None, .None
	stage := Repository_Process_Failure_Stage.None
	failure := Failure_Code.None
	reaped := child.reaped
	if child.live {
		if os.process_kill(child.process) != nil {
			stage = .Signal
			failure = .Process_Failed
		}
		if _, wait_error := os.process_wait(child.process); wait_error != nil {
			if stage == .None {
				stage = .Reap
				failure = .Process_Failed
			}
		} else {
			reaped = true
		}
	}
	files := [?]^os.File{child.stdin, child.stdout, child.stderr}
	for file in files {
		if file != nil && os.close(file) != nil && stage == .None {
			stage = .Cleanup
			failure = .Cleanup
		}
	}
	child^ = Local_Child{reaped = reaped}
	return reaped, stage, failure
}

@(private = "file")
local_file_nonblocking :: proc(file: ^os.File) -> bool {
	if file == nil do return false
	fd := linux.Fd(os.fd(file))
	flags, get_error := linux.fcntl(fd, linux.F_GETFL)
	if get_error != .NONE do return false
	flags += {.NONBLOCK}
	return linux.fcntl(fd, linux.F_SETFL, flags) == .NONE
}

@(private = "file")
local_close_files :: proc(files: ..^os.File) {
	for file in files {
		if file != nil do os.close(file)
	}
}

@(private)
repository_process_data_destroy :: proc(state: ^Repository_Process_Data) {
	if state == nil do return
	local_child_close(&state.child)
	delete(state.input)
	delete(state.output)
	delete(state.diagnostic)
	delete(state.commit_output)
	delete(state.commit_diagnostic)
	delete(state.revision_sequence_output)
	delete(state.revision_sequence_diagnostic)
	delete(state.ref_output)
	delete(state.remote_output)
	delete(state.conflict_path)
	delete(state.revision_sequence_targets)
	delete(state.manual_bisect_good)
	delete(state.extension_operation_arguments)
	free(state, state.allocator)
}

@(private = "file")
repository_process_error_is_again :: proc(value: os.Error) -> bool {
	#partial switch error_value in value {
	case os.Platform_Error:
		return error_value == .EAGAIN
	case:
		return false
	}
}

@(private = "file")
repository_process_error_is_timeout :: proc(value: os.Error) -> bool {
	#partial switch error_value in value {
	case os.General_Error:
		return error_value == .Timeout
	case:
		return false
	}
}

@(private = "file")
repository_process_error_is_closed :: proc(value: os.Error) -> bool {
	#partial switch error_value in value {
	case os.General_Error:
		return error_value == .Broken_Pipe
	case io.Error:
		return error_value == .EOF
	case:
		return false
	}
}
