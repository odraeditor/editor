// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

/* MAX_PROCESS_TITLE_BYTES bounds one copied public operation title. */
MAX_PROCESS_TITLE_BYTES :: u32(128)
/* MAX_PROCESS_TARGET_BYTES bounds one copied safe semantic target. */
MAX_PROCESS_TARGET_BYTES :: u32(4 * KIBIBYTE)
/* MAX_PROCESS_PHASE_BYTES bounds one copied operation-specific phase detail. */
MAX_PROCESS_PHASE_BYTES :: u32(64)
/* MAX_PROCESS_MESSAGE_BYTES bounds one copied public outcome message. */
MAX_PROCESS_MESSAGE_BYTES :: u32(2 * KIBIBYTE)
/* DEFAULT_RETAINED_PROCESS_RECORDS is the measured initial session history capacity. */
DEFAULT_RETAINED_PROCESS_RECORDS :: u32(8)
/* MAX_RETAINED_PROCESS_RECORDS is the immutable session history ceiling. */
MAX_RETAINED_PROCESS_RECORDS :: u32(32)
/* DEFAULT_RETAINED_PROCESS_BYTES is the measured initial aggregate record budget. */
DEFAULT_RETAINED_PROCESS_BYTES :: u64(2 * MEBIBYTE)
/* MAX_RETAINED_PROCESS_BYTES is the immutable aggregate record ceiling. */
MAX_RETAINED_PROCESS_BYTES :: u64(8 * MEBIBYTE)
/* MAX_PENDING_PROCESS_EVENTS bounds coalesced child and output events. */
MAX_PENDING_PROCESS_EVENTS :: u32(64)
/* MAX_PROCESS_RECORD_UPDATES_PER_STEP permits one immutable publication per editor step. */
MAX_PROCESS_RECORD_UPDATES_PER_STEP :: u32(1)
/* MAX_PROCESS_STREAM_READ_BYTES_PER_STEP matches one bounded child stream read. */
MAX_PROCESS_STREAM_READ_BYTES_PER_STEP :: u64(64 * KIBIBYTE)
/* DEFAULT_PROCESS_TEMPORARY_BYTES is the measured initial parsing and projection budget. */
DEFAULT_PROCESS_TEMPORARY_BYTES :: u64(2 * MEBIBYTE)
/* MAX_PROCESS_TEMPORARY_BYTES is the immutable parsing and projection ceiling. */
MAX_PROCESS_TEMPORARY_BYTES :: u64(8 * MEBIBYTE)
/* MAX_PROCESS_ACTIONS is the closed action capacity of one process record. */
MAX_PROCESS_ACTIONS :: 3

/* Repository_Operation_ID identifies one high-level operation within one Ksawery session. */
Repository_Operation_ID :: distinct u64
/* Process_Record_Generation identifies one immutable public state of an operation. */
Process_Record_Generation :: distinct u64

/* Repository_Operation_Kind identifies one checked high-level Ksawery workflow. */
Repository_Operation_Kind :: enum u8 {
	Invalid,
	Status,
	Sequence,
	History,
	Refs,
	Revision_Detail,
	Revision_Range,
	Path_Detail,
	Stage,
	Unstage,
	Discard,
	Commit,
	Amend,
	Fixup,
	Fetch,
	Push,
	Create_Branch,
	Switch_Branch,
	Rename_Branch,
	Delete_Branch,
	Create_Tag,
	Delete_Tag,
	Merge,
	Continue_Merge,
	Abort_Merge,
	Rebase,
	Continue_Rebase,
	Skip_Rebase,
	Abort_Rebase,
	Cherry_Pick,
	Continue_Cherry_Pick,
	Skip_Cherry_Pick,
	Abort_Cherry_Pick,
	Revert,
	Continue_Revert,
	Skip_Revert,
	Abort_Revert,
	Bisect,
	Bisect_Good,
	Bisect_Bad,
	Bisect_Skip,
	Bisect_Reset,
	Resolve_Conflict,
	Stash,
	Worktree,
	Blame,
	Reflog,
	External_Operation,
	Raw_Command,
}

/* Repository_Process_Lifecycle identifies the public lifetime of one operation. */
Repository_Process_Lifecycle :: enum u8 {
	Invalid,
	Admitted,
	Running,
	Cancellation_Requested,
	Succeeded,
	Failed,
	Cancelled,
	Timed_Out,
	Indeterminate,
}

/* Repository_Process_Phase identifies one stable public operation phase. */
Repository_Process_Phase :: enum u8 {
	Invalid,
	Checking,
	Executing,
	Refreshing,
	Verifying,
	Cancelling,
	Cleaning_Up,
}

/* Repository_Process_Outcome distinguishes terminal child and repository evidence. */
Repository_Process_Outcome :: enum u8 {
	None,
	Verified_Success,
	Known_Failure,
	Cancelled_Before_Effect,
	Cancelled_After_Possible_Effect,
	Timed_Out_Before_Effect,
	Timed_Out_After_Possible_Effect,
	Verification_Mismatch,
	Indeterminate,
}

/* Process_Target_Kind identifies the authority of one safe semantic target. */
Process_Target_Kind :: enum u8 {
	None,
	Repository,
	Path,
	Revision,
	Revision_Range,
	Ref,
	Remote,
}

/* Process_Progress_Kind distinguishes phase progress from truthful finite progress. */
Process_Progress_Kind :: enum u8 {
	None,
	Phase,
	Determinate,
}

/* Process_Action_Kind identifies one checked action exposed by a process record. */
Process_Action_Kind :: enum u8 {
	Invalid,
	Inspect,
	Cancel,
	Clear,
}

/* Process_Text_Ref identifies copied public bytes owned by one process record. */
Process_Text_Ref :: struct {
	offset: u32,
	length: u32,
}

/* Process_Progress describes phase-based or truthful finite progress. */
Process_Progress :: struct {
	kind:    Process_Progress_Kind,
	current: u64,
	total:   u64,
}

/* Process_Record_Timing contains monotonic operation timing only. */
Process_Record_Timing :: struct {
	admitted_ns: i64,
	started_ns:  i64,
	updated_ns:  i64,
	finished_ns: i64,
	elapsed_ns:  i64,
}

/* Process_Output_Descriptor identifies bounded retained output and diagnostics. */
Process_Output_Descriptor :: struct {
	output:               Process_Text_Ref,
	diagnostic:           Process_Text_Ref,
	output_truncated:     bool,
	diagnostic_truncated: bool,
	exit_status:          i32,
	exit_status_available: bool,
}

/* Process_Action_Descriptor binds one action to an exact immutable record generation. */
Process_Action_Descriptor :: struct {
	kind:       Process_Action_Kind,
	operation:  Repository_Operation_ID,
	generation: Process_Record_Generation,
	available:  bool,
}

/* Process_Record_Descriptor is the copied semantic metadata of one immutable record. */
Process_Record_Descriptor :: struct {
	operation:              Repository_Operation_ID,
	generation:             Process_Record_Generation,
	repository:             Repository_Context,
	observation_generation: Observation_Generation,
	kind:                   Repository_Operation_Kind,
	lifecycle:              Repository_Process_Lifecycle,
	phase:                  Repository_Process_Phase,
	outcome:                Repository_Process_Outcome,
	target_kind:            Process_Target_Kind,
	title:                  Process_Text_Ref,
	target:                 Process_Text_Ref,
	phase_detail:           Process_Text_Ref,
	message:                Process_Text_Ref,
	progress:               Process_Progress,
	timing:                 Process_Record_Timing,
	content:                Process_Output_Descriptor,
	actions:                [MAX_PROCESS_ACTIONS]Process_Action_Descriptor,
	action_count:           u8,
}

/* Process_Action_Proposal requests one checked action in a proposed record generation. */
Process_Action_Proposal :: struct {
	kind:      Process_Action_Kind,
	available: bool,
}

/* Process_Record_Proposal is borrowed input for one checked immutable record copy. */
Process_Record_Proposal :: struct {
	operation:              Repository_Operation_ID,
	generation:             Process_Record_Generation,
	repository:             Repository_Context,
	observation_generation: Observation_Generation,
	kind:                   Repository_Operation_Kind,
	lifecycle:              Repository_Process_Lifecycle,
	phase:                  Repository_Process_Phase,
	outcome:                Repository_Process_Outcome,
	target_kind:            Process_Target_Kind,
	title:                  string,
	target:                 string,
	phase_detail:           string,
	message:                string,
	progress:               Process_Progress,
	timing:                 Process_Record_Timing,
	output:                 []u8,
	diagnostic:             []u8,
	output_truncated:       bool,
	diagnostic_truncated:   bool,
	exit_status:            i32,
	exit_status_available:  bool,
	actions:                [MAX_PROCESS_ACTIONS]Process_Action_Proposal,
	action_count:           u8,
}

/* Process_Record owns one validated immutable process-record generation. */
Process_Record :: struct {
	state: rawptr,
}

/* Process_Record_Usage reports exact retained and temporary record resources. */
Process_Record_Usage :: struct {
	records:          u32,
	retained_bytes:   u64,
	output_bytes:     u64,
	diagnostic_bytes: u64,
	pending_events:   u32,
	active_operations: u8,
	active_children:  u8,
	child_streams:    u8,
	temporary_bytes:  u64,
}

/* Process_Record_Limits bounds one active operation and its session-local records. */
Process_Record_Limits :: struct {
	active_operations:       u8,
	active_children:         u8,
	child_streams:           u8,
	title_bytes:             u32,
	target_bytes:            u32,
	phase_bytes:             u32,
	message_bytes:           u32,
	retained_records:        u32,
	retained_bytes:          u64,
	pending_events:          u32,
	published_updates_step:  u32,
	stream_read_bytes_step:  u64,
	temporary_bytes:         u64,
	child:                   Process_Limits,
}

/* DEFAULT_PROCESS_RECORD_LIMITS selects the measured initial record envelope. */
DEFAULT_PROCESS_RECORD_LIMITS :: Process_Record_Limits {
	active_operations = 1,
	active_children = 1,
	child_streams = 2,
	title_bytes = MAX_PROCESS_TITLE_BYTES,
	target_bytes = MAX_PROCESS_TARGET_BYTES,
	phase_bytes = MAX_PROCESS_PHASE_BYTES,
	message_bytes = MAX_PROCESS_MESSAGE_BYTES,
	retained_records = DEFAULT_RETAINED_PROCESS_RECORDS,
	retained_bytes = DEFAULT_RETAINED_PROCESS_BYTES,
	pending_events = MAX_PENDING_PROCESS_EVENTS,
	published_updates_step = MAX_PROCESS_RECORD_UPDATES_PER_STEP,
	stream_read_bytes_step = MAX_PROCESS_STREAM_READ_BYTES_PER_STEP,
	temporary_bytes = DEFAULT_PROCESS_TEMPORARY_BYTES,
	child = DEFAULT_PROCESS_LIMITS,
}

/* process_record_limits_are_valid checks one complete immutable record envelope. */
process_record_limits_are_valid :: proc(limits: Process_Record_Limits) -> bool {
	return limits.active_operations == 1 &&
	       limits.active_children == 1 &&
	       limits.child_streams == 2 &&
	       limits.title_bytes > 0 && limits.title_bytes <= MAX_PROCESS_TITLE_BYTES &&
	       limits.target_bytes > 0 && limits.target_bytes <= MAX_PROCESS_TARGET_BYTES &&
	       limits.phase_bytes > 0 && limits.phase_bytes <= MAX_PROCESS_PHASE_BYTES &&
	       limits.message_bytes > 0 && limits.message_bytes <= MAX_PROCESS_MESSAGE_BYTES &&
	       limits.retained_records > 0 && limits.retained_records <= MAX_RETAINED_PROCESS_RECORDS &&
	       limits.retained_bytes > 0 && limits.retained_bytes <= MAX_RETAINED_PROCESS_BYTES &&
	       limits.pending_events > 0 && limits.pending_events <= MAX_PENDING_PROCESS_EVENTS &&
	       limits.published_updates_step == MAX_PROCESS_RECORD_UPDATES_PER_STEP &&
	       limits.stream_read_bytes_step > 0 &&
	       limits.stream_read_bytes_step <= MAX_PROCESS_STREAM_READ_BYTES_PER_STEP &&
	       limits.temporary_bytes > 0 && limits.temporary_bytes <= MAX_PROCESS_TEMPORARY_BYTES &&
	       process_limits_are_valid(limits.child)
}

/* repository_process_lifecycle_is_terminal reports whether no later running generation is valid. */
repository_process_lifecycle_is_terminal :: proc(lifecycle: Repository_Process_Lifecycle) -> bool {
	switch lifecycle {
	case .Succeeded, .Failed, .Cancelled, .Timed_Out, .Indeterminate:
		return true
	case .Invalid, .Admitted, .Running, .Cancellation_Requested:
		return false
	}
	return false
}
