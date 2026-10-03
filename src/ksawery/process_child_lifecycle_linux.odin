// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery

import "core:os"

/* Repository_Process_Association binds one native owner to an exact operation generation. */
Repository_Process_Association :: struct {
	authority: Process_Record_Authority,
	generation: Process_Record_Generation,
}

/* Repository_Child_State identifies the latest owned child lifecycle. */
Repository_Child_State :: enum u8 {
	Invalid,
	Running,
	Reaped,
	Uncertain,
}

/* Repository_Child_Evidence reports bounded start and terminal evidence for the latest child. */
Repository_Child_Evidence :: struct {
	generation:            u32,
	children_started:      u32,
	children_reaped:       u32,
	state:                 Repository_Child_State,
	started_ns:            i64,
	finished_ns:           i64,
	exit_status:           i32,
	exit_status_available: bool,
}

/* Repository_Process_Termination_Reason distinguishes cancellation from deadline expiry. */
Repository_Process_Termination_Reason :: enum u8 {
	None,
	Cancellation,
	Timeout,
}

/* Repository_Process_Termination_Phase reports finite signal and reap progress. */
Repository_Process_Termination_Phase :: enum u8 {
	None,
	Graceful_Signal,
	Forced_Signal,
	Reaped,
}

/* Repository_Process_Termination_Evidence reports bounded termination transitions. */
Repository_Process_Termination_Evidence :: struct {
	reason:            Repository_Process_Termination_Reason,
	phase:             Repository_Process_Termination_Phase,
	requested_ns:      i64,
	grace_deadline_ns: i64,
	forced_ns:         i64,
	reaped_ns:         i64,
}

/* Repository_Process_Cancellation_Request targets one exact associated record generation. */
Repository_Process_Cancellation_Request :: struct {
	operation:    Repository_Operation_ID,
	generation:   Process_Record_Generation,
	requested_ns: i64,
}

/* Repository_Process_Failure_Stage identifies the native owner boundary that failed. */
Repository_Process_Failure_Stage :: enum u8 {
	None,
	Start,
	Input,
	Output,
	Diagnostic,
	Exit,
	Timeout,
	Cancellation,
	Signal,
	Reap,
	Cleanup,
}

/* Repository_Process_Effect_Exposure reports whether repository mutation may have started. */
Repository_Process_Effect_Exposure :: enum u8 {
	Not_Applicable,
	Not_Started,
	May_Have_Started,
}

/* Repository_Process_Failure_Evidence preserves primary and cleanup failures without an outcome claim. */
Repository_Process_Failure_Evidence :: struct {
	stage:                 Repository_Process_Failure_Stage,
	failure:               Failure_Code,
	secondary_stage:       Repository_Process_Failure_Stage,
	secondary_failure:     Failure_Code,
	effect:                Repository_Process_Effect_Exposure,
	exit_status:           i32,
	exit_status_available: bool,
}

/* Repository_Process_Lifecycle_View reports one associated native owner's semantic state. */
Repository_Process_Lifecycle_View :: struct {
	association:         Repository_Process_Association,
	owner_state:         Repository_Process_State,
	phase:               Repository_Process_Phase,
	phase_generation:    u32,
	timing:              Process_Record_Timing,
	child:               Repository_Child_Evidence,
	termination:         Repository_Process_Termination_Evidence,
	failure_evidence:    Repository_Process_Failure_Evidence,
	output_bytes:        u64,
	diagnostic_bytes:    u64,
	output_truncated:    bool,
	diagnostic_truncated: bool,
	failure:             Failure_Code,
}

/* repository_process_associate binds one running native owner to a checked operation generation. */
repository_process_associate :: proc(
	process: ^Repository_Process,
	association: Repository_Process_Association,
	now_ns: i64,
) -> (bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || state.state != .Running || state.associated || now_ns < 0 ||
	   !repository_process_association_is_valid(association) {
		return false, .Invalid_Request
	}
	if association.authority.repository != state.request.repository ||
	   !repository_process_kind_is_compatible(state, association.authority.kind) {
		return false, .Stale_Observation
	}
	phase := repository_process_public_phase(state)
	if phase == .Invalid do return false, .Invalid_Request
	state.association = association
	state.associated = true
	state.public_phase = phase
	state.phase_generation = 1
	state.lifecycle_timing = {
		admitted_ns = now_ns,
		started_ns = now_ns,
		updated_ns = now_ns,
	}
	if state.child.live {
		state.children_started = 1
		state.child_evidence = {
			generation = 1,
			children_started = 1,
			state = .Running,
			started_ns = now_ns,
		}
	}
	return true, .None
}

/* repository_process_advance_record_generation checks and advances the associated public generation. */
repository_process_advance_record_generation :: proc(
	process: ^Repository_Process,
	expected: Process_Record_Generation,
	next: Process_Record_Generation,
) -> (bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || !state.associated || expected == Process_Record_Generation(0) ||
	   next == Process_Record_Generation(0) {
		return false, .Invalid_Request
	}
	if state.association.generation != expected || next <= expected do return false, .Process_Record_Stale
	state.association.generation = next
	return true, .None
}

/* repository_process_lifecycle_view returns copied semantic child evidence without native handles. */
repository_process_lifecycle_view :: proc(
	process: ^Repository_Process,
) -> (Repository_Process_Lifecycle_View, bool) {
	state := repository_process_data(process)
	if state == nil || !state.associated do return {}, false
	usage, measured := repository_process_usage(process)
	if !measured do return {}, false
	return Repository_Process_Lifecycle_View {
		association = state.association,
		owner_state = state.state,
		phase = state.public_phase,
		phase_generation = state.phase_generation,
		timing = state.lifecycle_timing,
		child = state.child_evidence,
		termination = state.termination,
		failure_evidence = state.failure_evidence,
		output_bytes = usage.output_bytes,
		diagnostic_bytes = usage.diagnostic_bytes,
		output_truncated = state.output_truncated,
		diagnostic_truncated = state.diagnostic_truncated,
		failure = state.failure,
	}, true
}

/* repository_process_request_cancellation admits one exact-generation graceful cancellation. */
repository_process_request_cancellation :: proc(
	process: ^Repository_Process,
	request: Repository_Process_Cancellation_Request,
) -> (bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || state.state != .Running || !state.associated ||
	   request.operation == Repository_Operation_ID(0) ||
	   request.generation == Process_Record_Generation(0) || request.requested_ns < 0 {
		return false, .Invalid_Request
	}
	if request.operation != state.association.authority.operation ||
	   request.generation != state.association.generation ||
	   request.requested_ns < state.lifecycle_timing.updated_ns {
		return false, .Process_Record_Stale
	}
	if state.termination.reason != .None do return false, .Process_Record_Closed
	return repository_process_begin_termination(state, .Cancellation, request.requested_ns)
}

@(private)
repository_process_association_is_valid :: proc(association: Repository_Process_Association) -> bool {
	return association.authority.operation != Repository_Operation_ID(0) &&
	       repository_context_is_valid(association.authority.repository) &&
	       association.authority.observation_generation != Observation_Generation(0) &&
	       association.authority.kind != .Invalid &&
	       association.generation != Process_Record_Generation(0)
}

@(private)
repository_process_kind_is_compatible :: proc(
	state: ^Repository_Process_Data,
	kind: Repository_Operation_Kind,
) -> bool {
	if state == nil do return false
	switch state.request.kind {
	case .Observe_Status:
		switch kind {
		case .Status, .Stage, .Unstage, .Discard, .Commit, .Amend, .Fixup,
		     .Fetch, .Push, .Create_Branch, .Switch_Branch, .Rename_Branch,
		     .Delete_Branch, .Create_Tag, .Delete_Tag, .Merge, .Continue_Merge,
		     .Abort_Merge, .Rebase, .Continue_Rebase, .Skip_Rebase, .Abort_Rebase,
		     .Cherry_Pick, .Continue_Cherry_Pick, .Skip_Cherry_Pick, .Abort_Cherry_Pick,
		     .Revert, .Continue_Revert, .Skip_Revert, .Abort_Revert,
		     .Bisect, .Bisect_Good, .Bisect_Bad, .Bisect_Skip, .Bisect_Reset,
		     .Resolve_Conflict:
			return true
		case .Invalid, .Sequence, .History, .Refs, .Revision_Detail, .Revision_Range, .Path_Detail,
		     .Stash, .Worktree, .Blame, .Reflog, .External_Operation, .Raw_Command:
			return false
		}
	case .Observe_Sequence:
		return kind == .Sequence
	case .Observe_History:
		switch kind {
		case .History, .Commit, .Amend, .Fixup, .Fetch, .Push, .Create_Branch,
		     .Switch_Branch, .Rename_Branch, .Delete_Branch, .Create_Tag, .Delete_Tag,
		     .Merge, .Continue_Merge, .Abort_Merge,
		     .Rebase, .Continue_Rebase, .Skip_Rebase, .Abort_Rebase,
		     .Cherry_Pick, .Continue_Cherry_Pick, .Skip_Cherry_Pick, .Abort_Cherry_Pick,
		     .Revert, .Continue_Revert, .Skip_Revert, .Abort_Revert,
		     .Bisect, .Bisect_Good, .Bisect_Bad, .Bisect_Skip, .Bisect_Reset,
		     .Resolve_Conflict:
			return true
		case .Invalid, .Status, .Sequence, .Refs, .Revision_Detail, .Revision_Range,
		     .Path_Detail, .Stage, .Unstage, .Discard, .Stash, .Worktree, .Blame, .Reflog,
		     .External_Operation, .Raw_Command:
			return false
		}
	case .Observe_Refs:
		switch kind {
		case .Refs, .Fetch, .Push, .Create_Branch, .Switch_Branch, .Rename_Branch,
		     .Delete_Branch, .Create_Tag, .Delete_Tag,
		     .Merge, .Continue_Merge, .Abort_Merge,
		     .Rebase, .Continue_Rebase, .Skip_Rebase, .Abort_Rebase,
		     .Cherry_Pick, .Continue_Cherry_Pick, .Skip_Cherry_Pick, .Abort_Cherry_Pick,
		     .Revert, .Continue_Revert, .Skip_Revert, .Abort_Revert,
		     .Bisect, .Bisect_Good, .Bisect_Bad, .Bisect_Skip, .Bisect_Reset,
		     .Resolve_Conflict:
			return true
		case .Invalid, .Status, .Sequence, .History, .Revision_Detail, .Revision_Range,
		     .Path_Detail, .Stage, .Unstage, .Discard, .Commit, .Amend, .Fixup,
		     .Stash, .Worktree, .Blame, .Reflog, .External_Operation, .Raw_Command:
			return false
		}
	case .Observe_Remote_Configuration, .Fetch_Remote:
		return kind == .Fetch
	case .Observe_Push_Configuration, .Push_Remote:
		return kind == .Push
	case .Inspect_Revision_Detail_Metadata, .Inspect_Revision_Detail_Comparison:
		return kind == .Revision_Detail
	case .Inspect_Revision_Range_Summary, .Inspect_Revision_Range_Comparison:
		return kind == .Revision_Range
	case .Inspection_Workflow:
		switch state.request.inspection_workflow.family {
		case .Stash:    return kind == .Stash
		case .Worktree: return kind == .Worktree
		case .Blame:    return kind == .Blame
		case .Reflog:   return kind == .Reflog
		case .Invalid:  return false
		}
	case .Inspect_Path:
		return kind == .Path_Detail
	case .Stage_Path, .Stage_Diff_Unit, .Stage_Group:
		return kind == .Stage
	case .Unstage_Path, .Unstage_Diff_Unit, .Unstage_Group:
		return kind == .Unstage
	case .Discard_Path:
		return kind == .Discard
	case .Commit_Normal:
		switch state.commit.mode {
		case .Normal:
			return kind == .Commit
		case .Amend:
			return kind == .Amend
		case .Fixup:
			return kind == .Fixup
		case .Invalid:
			return kind == .Commit || kind == .Amend || kind == .Fixup
		}
	case .Branch_Local:
		switch state.branch.precondition.intent.operation {
		case .Create:
			return kind == .Create_Branch
		case .Switch:
			return kind == .Switch_Branch
		case .Rename:
			return kind == .Rename_Branch
		case .Delete:
			return kind == .Delete_Branch
		case .Invalid:
			return false
		}
	case .Tag_Local:
		switch state.tag.precondition.intent.operation {
		case .Create:
			return kind == .Create_Tag
		case .Delete:
			return kind == .Delete_Tag
		case .Invalid:
			return false
		}
	case .Merge_Repository:
		action := state.merge.precondition.action
		if action == .Invalid do action = state.merge_precondition.action
		switch action {
		case .Start: return kind == .Merge
		case .Continue: return kind == .Continue_Merge
		case .Abort: return kind == .Abort_Merge
		case .Invalid: return false
		}
	case .Rebase_Repository:
		action := state.rebase.precondition.action
		if action == .Invalid do action = state.rebase_precondition.action
		switch action {
		case .Start: return kind == .Rebase
		case .Continue: return kind == .Continue_Rebase
		case .Skip: return kind == .Skip_Rebase
		case .Abort: return kind == .Abort_Rebase
		case .Invalid: return false
		}
	case .Cherry_Pick_Repository:
		switch state.revision_sequence.precondition.action {
		case .Start: return kind == .Cherry_Pick
		case .Continue: return kind == .Continue_Cherry_Pick
		case .Skip: return kind == .Skip_Cherry_Pick
		case .Abort: return kind == .Abort_Cherry_Pick
		case .Invalid: return false
		}
	case .Revert_Repository:
		switch state.revision_sequence.precondition.action {
		case .Start: return kind == .Revert
		case .Continue: return kind == .Continue_Revert
		case .Skip: return kind == .Skip_Revert
		case .Abort: return kind == .Abort_Revert
		case .Invalid: return false
		}
	case .Bisect_Repository:
		action := state.manual_bisect.precondition.action
		if action == .Invalid do action = state.manual_bisect_precondition.action
		switch action {
		case .Start: return kind == .Bisect
		case .Good: return kind == .Bisect_Good
		case .Bad: return kind == .Bisect_Bad
		case .Skip: return kind == .Bisect_Skip
		case .Reset: return kind == .Bisect_Reset
		case .Invalid: return false
		}
	case .Resolve_Conflict:
		return kind == .Resolve_Conflict
	case .External_Operation:
		return kind == .External_Operation
	case .Raw_Command:
		return kind == .Raw_Command
	case .Invalid:
		return false
	}
	return false
}

@(private)
repository_process_public_phase :: proc(state: ^Repository_Process_Data) -> Repository_Process_Phase {
	if state == nil do return .Invalid
	if state.commit_phase != .None {
		switch state.commit_phase {
		case .Commit:
			return .Executing
		case .Observe_Result_Head:
			return .Verifying
		case .Observe_Head, .Observe_Index_Tree, .Check_Head, .Check_Index_Tree, .Check_Operation:
			return .Checking
		case .None:
		}
	}
	if state.remote_configuration_phase != .None {
		if state.remote_configuration_phase == .Fetch do return .Executing
		return .Checking
	}
	if state.push_phase != .None {
		if state.push_phase == .Push do return .Executing
		return .Checking
	}
	if state.branch_phase != .None {
		if state.branch_phase == .Mutate do return .Executing
		return .Checking
	}
	if state.tag_phase != .None {
		if state.tag_phase == .Mutate do return .Executing
		return .Checking
	}
	if state.merge_phase != .None {
		if state.merge_phase == .Mutate || state.merge_phase == .Commit do return .Executing
		return .Checking
	}
	if state.rebase_phase != .None {
		if state.rebase_phase == .Mutate do return .Executing
		return .Checking
	}
	if state.revision_sequence_phase != .None {
		if state.revision_sequence_phase == .Mutate do return .Executing
		return .Checking
	}
	if state.manual_bisect_phase != .None {
		if state.manual_bisect_phase == .Mutate do return .Executing
		return .Checking
	}
	if state.conflict_resolution_phase != .None {
		if state.conflict_resolution_phase == .Mutate ||
		   state.conflict_resolution_phase == .Stage_Result {
			return .Executing
		}
		return .Checking
	}
	if state.inspection_phase != .None {
		if state.inspection_phase == .Action &&
		   inspection_action_is_mutating(state.request.inspection_workflow.action) {
			return .Executing
		}
		return .Checking
	}
	if state.ref_phase != .None || state.sequence_phase != .None do return .Executing
	switch state.request.kind {
	case .Observe_Status, .Observe_Sequence, .Observe_History, .Observe_Refs,
	     .Inspect_Revision_Detail_Metadata, .Inspect_Revision_Detail_Comparison,
	     .Inspect_Revision_Range_Summary, .Inspect_Revision_Range_Comparison,
	     .Inspect_Path, .Stage_Path, .Unstage_Path, .Stage_Diff_Unit,
	     .Unstage_Diff_Unit, .Stage_Group, .Unstage_Group, .Discard_Path,
	     .External_Operation, .Raw_Command:
		return .Executing
	case .Inspection_Workflow:
		return inspection_action_is_mutating(state.request.inspection_workflow.action) ? .Executing : .Checking
	case .Observe_Remote_Configuration, .Observe_Push_Configuration,
	     .Commit_Normal, .Fetch_Remote, .Push_Remote, .Branch_Local, .Tag_Local,
	     .Merge_Repository, .Rebase_Repository, .Cherry_Pick_Repository, .Revert_Repository, .Bisect_Repository, .Resolve_Conflict:
		return .Checking
	case .Invalid:
		return .Invalid
	}
	return .Invalid
}

@(private)
repository_process_note_poll :: proc(state: ^Repository_Process_Data, now_ns: i64) {
	if state == nil || !state.associated do return
	state.lifecycle_timing.updated_ns = now_ns
	state.lifecycle_timing.elapsed_ns = now_ns - state.lifecycle_timing.admitted_ns
}

@(private)
repository_process_note_child_started :: proc(state: ^Repository_Process_Data) {
	if state == nil || !state.associated do return
	state.children_started += 1
	state.child_evidence = {
		generation = state.child_evidence.generation + 1,
		children_started = state.children_started,
		children_reaped = state.children_reaped,
		state = .Running,
		started_ns = state.lifecycle_timing.updated_ns,
	}
}

@(private)
repository_process_note_child_reaped :: proc(state: ^Repository_Process_Data, now_ns: i64, exit_status: i32) {
	if state == nil || !state.associated do return
	state.children_reaped += 1
	state.child_evidence.children_started = state.children_started
	state.child_evidence.children_reaped = state.children_reaped
	state.child_evidence.state = .Reaped
	state.child_evidence.finished_ns = now_ns
	state.child_evidence.exit_status = exit_status
	state.child_evidence.exit_status_available = true
	if state.failure_evidence.stage != .None && !state.failure_evidence.exit_status_available {
		state.failure_evidence.exit_status = exit_status
		state.failure_evidence.exit_status_available = true
	}
	if state.termination.reason != .None {
		state.termination.phase = .Reaped
		state.termination.reaped_ns = now_ns
	}
}

@(private)
repository_process_begin_termination :: proc(
	state: ^Repository_Process_Data,
	reason: Repository_Process_Termination_Reason,
	now_ns: i64,
) -> (bool, Failure_Code) {
	if state == nil || state.state != .Running || state.termination.reason != .None ||
	   reason == .None || !state.child.live {
		return false, .Invalid_Request
	}
	grace_deadline_ns := now_ns + state.request.limits.cancellation_grace_ns
	if grace_deadline_ns < now_ns do return false, .Invalid_Request
	if os.process_terminate(state.child.process) != nil {
		if reason == .Timeout do repository_process_note_failure(state, .Timeout, .Timeout)
		repository_process_note_failure(state, .Signal, .Process_Failed)
		return false, .Process_Failed
	}
	repository_process_note_failure(
		state,
		reason == .Timeout ? .Timeout : .Cancellation,
		reason == .Timeout ? .Timeout : .Cancelled,
	)
	if state.child.stdin != nil {
		_ = os.close(state.child.stdin)
		state.child.stdin = nil
	}
	state.stdin_closed = true
	state.termination = {
		reason = reason,
		phase = .Graceful_Signal,
		requested_ns = now_ns,
		grace_deadline_ns = grace_deadline_ns,
	}
	state.lifecycle_timing.updated_ns = now_ns
	state.lifecycle_timing.elapsed_ns = now_ns - state.lifecycle_timing.admitted_ns
	if state.public_phase != .Cancelling {
		state.public_phase = .Cancelling
		state.phase_generation += 1
	}
	return true, .None
}

@(private)
repository_process_escalate_termination :: proc(state: ^Repository_Process_Data, now_ns: i64) -> Failure_Code {
	if state == nil || state.termination.phase != .Graceful_Signal || !state.child.live do return .Invalid_Request
	if os.process_kill(state.child.process) != nil {
		repository_process_note_failure(state, .Signal, .Process_Failed)
		return .Process_Failed
	}
	state.termination.phase = .Forced_Signal
	state.termination.forced_ns = now_ns
	return .None
}

@(private)
repository_process_finish_termination :: proc(state: ^Repository_Process_Data, now_ns: i64) {
	if state == nil || state.termination.reason == .None do return
	state.termination.phase = .Reaped
	if state.termination.reaped_ns == 0 do state.termination.reaped_ns = now_ns
	state.failure = state.termination.reason == .Timeout ? .Timeout : .Cancelled
	state.state = .Failed
}

@(private)
repository_process_close_terminal_child :: proc(state: ^Repository_Process_Data, now_ns: i64) {
	if state == nil do return
	was_live := state.child.live
	was_reaped := state.child.reaped
	reaped, close_stage, close_failure := local_child_close_checked(&state.child)
	if close_failure != .None do repository_process_note_failure(state, close_stage, close_failure)
	state.stdin_closed = true
	state.stdout_closed = true
	state.stderr_closed = true
	if was_live && !was_reaped {
		if reaped do state.children_reaped += 1
		state.child_evidence.children_started = state.children_started
		state.child_evidence.children_reaped = state.children_reaped
		state.child_evidence.state = reaped ? .Reaped : .Uncertain
		state.child_evidence.finished_ns = now_ns
		state.child_evidence.exit_status_available = false
		if reaped && state.termination.reason != .None {
			state.termination.phase = .Reaped
			state.termination.reaped_ns = now_ns
		}
	}
}

@(private)
repository_process_note_failure :: proc(
	state: ^Repository_Process_Data,
	stage: Repository_Process_Failure_Stage,
	failure: Failure_Code,
	exit_status := i32(0),
	exit_status_available := false,
) {
	if state == nil || stage == .None || failure == .None do return
	if state.failure_evidence.stage == .None {
		state.failure_evidence.stage = stage
		state.failure_evidence.failure = failure
		state.failure_evidence.effect = repository_process_effect_exposure(state)
		state.failure_evidence.exit_status = exit_status
		state.failure_evidence.exit_status_available = exit_status_available
	} else if state.failure_evidence.stage != stage && state.failure_evidence.secondary_stage == .None {
		state.failure_evidence.secondary_stage = stage
		state.failure_evidence.secondary_failure = failure
	}
}

@(private)
repository_process_effect_exposure :: proc(state: ^Repository_Process_Data) -> Repository_Process_Effect_Exposure {
	if state == nil do return .Not_Applicable
	switch state.request.kind {
	case .Observe_Status, .Observe_Sequence, .Observe_History, .Observe_Refs,
	     .Observe_Remote_Configuration, .Observe_Push_Configuration,
	     .Inspect_Revision_Detail_Metadata, .Inspect_Revision_Detail_Comparison,
	     .Inspect_Revision_Range_Summary, .Inspect_Revision_Range_Comparison,
	     .Inspect_Path:
		return .Not_Applicable
	case .Inspection_Workflow:
		if !inspection_action_is_mutating(state.request.inspection_workflow.action) {
			return .Not_Applicable
		}
		return state.inspection_started ? .May_Have_Started : .Not_Started
	case .Stage_Path, .Unstage_Path, .Stage_Diff_Unit, .Unstage_Diff_Unit,
	     .Stage_Group, .Unstage_Group, .Discard_Path:
		return state.children_started > 0 ? .May_Have_Started : .Not_Started
	case .Commit_Normal:
		return state.commit_phase == .Commit || state.commit_outcome_retained ? .May_Have_Started : .Not_Started
	case .Fetch_Remote:
		return state.fetch_started ? .May_Have_Started : .Not_Started
	case .Push_Remote:
		return state.push_started ? .May_Have_Started : .Not_Started
	case .Branch_Local:
		return state.branch_started ? .May_Have_Started : .Not_Started
	case .Tag_Local:
		return state.tag_started ? .May_Have_Started : .Not_Started
	case .Merge_Repository:
		return state.merge_started ? .May_Have_Started : .Not_Started
	case .Rebase_Repository:
		return state.rebase_started ? .May_Have_Started : .Not_Started
	case .Cherry_Pick_Repository, .Revert_Repository:
		return state.revision_sequence_started ? .May_Have_Started : .Not_Started
	case .Bisect_Repository:
		return state.manual_bisect_started ? .May_Have_Started : .Not_Started
	case .Resolve_Conflict:
		return state.conflict_resolution_started ? .May_Have_Started : .Not_Started
	case .External_Operation:
		if state.extension_operation.effect == .Read_Only do return .Not_Applicable
		return state.children_started > 0 ? .May_Have_Started : .Not_Started
	case .Raw_Command:
		return state.children_started > 0 ? .May_Have_Started : .Not_Started
	case .Invalid:
		return .Not_Applicable
	}
	return .Not_Applicable
}

@(private)
repository_process_note_phase_and_terminal :: proc(state: ^Repository_Process_Data, now_ns: i64) {
	if state == nil || !state.associated do return
	if state.state == .Running && state.termination.reason == .None {
		phase := repository_process_public_phase(state)
		if phase != .Invalid && phase != state.public_phase {
			state.public_phase = phase
			state.phase_generation += 1
		}
	}
	if state.state != .Running && state.lifecycle_timing.finished_ns == 0 {
		state.lifecycle_timing.updated_ns = now_ns
		state.lifecycle_timing.finished_ns = now_ns
		state.lifecycle_timing.elapsed_ns = now_ns - state.lifecycle_timing.admitted_ns
	}
}
