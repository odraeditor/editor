// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package interactive_session owns process transport lifecycle and bounded IO.
package interactive_session

/* MAX_SESSIONS is the immutable registry safety ceiling. */
MAX_SESSIONS :: 32
/* OPERATING_SESSIONS is the ordinary concurrent-session target. */
OPERATING_SESSIONS :: 8
/* MAX_NAME_BYTES bounds copied session names. */
MAX_NAME_BYTES :: 96
/* MAX_OWNER_LABEL_BYTES bounds copied provenance labels. */
MAX_OWNER_LABEL_BYTES :: 96
/* MAX_DIRECTORY_BYTES bounds one absolute working context. */
MAX_DIRECTORY_BYTES :: 4 * 1_024
/* OPERATING_DIAGNOSTIC_BYTES bounds one ordinary copied failure diagnostic. */
OPERATING_DIAGNOSTIC_BYTES :: 4 * 1_024
/* MAX_DIAGNOSTIC_BYTES bounds admitted launch and diagnostic input. */
MAX_DIAGNOSTIC_BYTES :: 16 * 1_024
/* MAX_ARGUMENTS bounds one structured process launch. */
MAX_ARGUMENTS :: 128
/* MAX_ENVIRONMENT_ENTRIES bounds one structured environment. */
MAX_ENVIRONMENT_ENTRIES :: 256
/* OPERATING_INPUT_BYTES is the ordinary per-session input queue bound. */
OPERATING_INPUT_BYTES :: 1 * 1_024 * 1_024
/* MAX_INPUT_BYTES is the immutable per-session input queue ceiling. */
MAX_INPUT_BYTES :: 4 * 1_024 * 1_024
/* OPERATING_OUTPUT_BYTES is the ordinary per-session output queue bound. */
OPERATING_OUTPUT_BYTES :: 1 * 1_024 * 1_024
/* MAX_OUTPUT_BYTES is the immutable per-session output queue ceiling. */
MAX_OUTPUT_BYTES :: 4 * 1_024 * 1_024
/* OPERATING_AGGREGATE_INPUT_BYTES is the ordinary registry input budget. */
OPERATING_AGGREGATE_INPUT_BYTES :: 8 * 1_024 * 1_024
/* MAX_AGGREGATE_INPUT_BYTES is the immutable registry input ceiling. */
MAX_AGGREGATE_INPUT_BYTES :: 32 * 1_024 * 1_024
/* OPERATING_AGGREGATE_OUTPUT_BYTES is the ordinary registry output budget. */
OPERATING_AGGREGATE_OUTPUT_BYTES :: 8 * 1_024 * 1_024
/* MAX_AGGREGATE_OUTPUT_BYTES is the immutable registry output ceiling. */
MAX_AGGREGATE_OUTPUT_BYTES :: 32 * 1_024 * 1_024
/* OPERATING_CHUNK_BYTES is the ordinary nonblocking syscall chunk. */
OPERATING_CHUNK_BYTES :: 64 * 1_024
/* MAX_CHUNK_BYTES is the immutable nonblocking syscall chunk ceiling. */
MAX_CHUNK_BYTES :: 256 * 1_024
/* OPERATING_OUTPUT_TURN_BYTES is the ordinary event-loop byte budget. */
OPERATING_OUTPUT_TURN_BYTES :: 256 * 1_024
/* MAX_OUTPUT_TURN_BYTES is the immutable event-loop byte ceiling. */
MAX_OUTPUT_TURN_BYTES :: 1 * 1_024 * 1_024
/* OPERATING_OUTPUT_TURN_NANOSECONDS is the ordinary event-loop time budget. */
OPERATING_OUTPUT_TURN_NANOSECONDS :: i64(4_000_000)
/* MAX_OUTPUT_TURN_NANOSECONDS is the immutable event-loop time ceiling. */
MAX_OUTPUT_TURN_NANOSECONDS :: i64(8_000_000)
/* OPERATING_SHUTDOWN_NANOSECONDS is the ordinary escalation interval. */
OPERATING_SHUTDOWN_NANOSECONDS :: i64(2_000_000_000)
/* MAX_SHUTDOWN_NANOSECONDS is the immutable escalation interval ceiling. */
MAX_SHUTDOWN_NANOSECONDS :: i64(5_000_000_000)
/* MAX_COLUMNS bounds one admitted PTY width. */
MAX_COLUMNS :: 2_048
/* MAX_ROWS bounds one admitted PTY height. */
MAX_ROWS :: 1_024
/* MAX_CELLS bounds one admitted PTY geometry product. */
MAX_CELLS :: 1_048_576

/* Session_ID identifies one fixed registry slot. */
Session_ID :: distinct u32
/* Session_Generation invalidates stale references after slot reuse. */
Session_Generation :: distinct u32

/* Session_Ref identifies one exact registry generation. */
Session_Ref :: struct {
	id:         Session_ID,
	generation: Session_Generation,
}

/* Lifecycle records explicit transport ownership transitions. */
Lifecycle :: enum u8 {
	Invalid = 0,
	Prepared,
	Starting,
	Running,
	Exited,
	Closing,
	Closed,
	Failed,
}

/* Owner_Kind records why one session was created. */
Owner_Kind :: enum u8 {
	Invalid = 0,
	Interactive_User,
	Task,
	Language_Integration,
	Agent_Integration,
}

/* Exit_Kind distinguishes normal exit from signal termination. */
Exit_Kind :: enum u8 {
	None = 0,
	Code,
	Signal,
}

/* Failure_Code is the stable process-transport failure vocabulary. */
Failure_Code :: enum u16 {
	None = 0,
	Invalid_Argument,
	Invalid_Transition,
	Stale_Reference,
	Capacity,
	Duplicate_Name,
	Allocation,
	Invalid_Executable,
	Invalid_Working_Context,
	Invalid_Environment,
	PTY_Open,
	PTY_Configure,
	Spawn,
	Nonblocking,
	Resize,
	Read,
	Write,
	Input_Limit,
	Output_Limit,
	Cancelled,
	Signal,
	Reap,
	Cleanup,
}

/* Failure_Stage identifies the owner operation that failed. */
Failure_Stage :: enum u8 {
	None = 0,
	Prepare,
	Start,
	Poll,
	Input,
	Output,
	Resize,
	Terminate,
	Close,
}

/* Bounded_Text owns one copied, bounded UTF-8-independent byte value. */
Bounded_Text :: struct {
	bytes:  [OPERATING_DIAGNOSTIC_BYTES]u8,
	length: u16,
}

/* Session_Name owns one copied display identity. */
Session_Name :: struct {
	bytes:  [MAX_NAME_BYTES]u8,
	length: u8,
}

/* Owner_Provenance owns one copied source classification and label. */
Owner_Provenance :: struct {
	kind:   Owner_Kind,
	label:  [MAX_OWNER_LABEL_BYTES]u8,
	length: u8,
}

/* Working_Context owns one validated local directory. */
Working_Context :: struct {
	directory: [MAX_DIRECTORY_BYTES]u8,
	length:    u16,
}

/* Exit_Status retains one collected child result. */
Exit_Status :: struct {
	kind:  Exit_Kind,
	value: i32,
}

/* Resource_Usage reports process and bounded-queue ownership. */
Resource_Usage :: struct {
	process_id:          i32,
	process_group_id:    i32,
	open_descriptors:    u8,
	queued_input_bytes:  u64,
	queued_output_bytes: u64,
	total_input_bytes:   u64,
	total_output_bytes:  u64,
	input_peak_bytes:    u64,
	output_peak_bytes:   u64,
	read_turns:          u64,
	write_turns:         u64,
}

/* Failure_Record retains the first lifecycle failure and bounded context. */
Failure_Record :: struct {
	stage:      Failure_Stage,
	code:       Failure_Code,
	os_errno:   i32,
	limit:      u64,
	actual:     u64,
	diagnostic: Bounded_Text,
}

/* Session_Record is copied lifecycle inspection without native handles. */
Session_Record :: struct {
	ref:              Session_Ref,
	name:             Session_Name,
	lifecycle:        Lifecycle,
	owner:            Owner_Provenance,
	working_context:  Working_Context,
	resources:        Resource_Usage,
	exit_status:      Exit_Status,
	failure:          Failure_Record,
	default_session:  bool,
	cancel_requested: bool,
}

/* Limits defines configurable operating bounds below immutable ceilings. */
Limits :: struct {
	input_bytes:             u64,
	output_bytes:            u64,
	read_chunk_bytes:        u64,
	write_chunk_bytes:       u64,
	output_turn_bytes:       u64,
	output_turn_nanoseconds: i64,
	shutdown_nanoseconds:    i64,
	columns:                 u16,
	rows:                    u16,
}

/* DEFAULT_LIMITS defines the ordinary bounded interactive-session policy. */
DEFAULT_LIMITS :: Limits {
	input_bytes = OPERATING_INPUT_BYTES,
	output_bytes = OPERATING_OUTPUT_BYTES,
	read_chunk_bytes = OPERATING_CHUNK_BYTES,
	write_chunk_bytes = OPERATING_CHUNK_BYTES,
	output_turn_bytes = OPERATING_OUTPUT_TURN_BYTES,
	output_turn_nanoseconds = OPERATING_OUTPUT_TURN_NANOSECONDS,
	shutdown_nanoseconds = OPERATING_SHUTDOWN_NANOSECONDS,
	columns = 80,
	rows = 24,
}

/* Process_Signal is the platform-independent child signal vocabulary. */
Process_Signal :: enum i32 {
	Interrupt = 0,
	Terminate,
	Kill,
	Hangup,
}

/* Process_Start_Request borrows one structured local process launch. */
Process_Start_Request :: struct {
	executable:        string,
	arguments:         []string,
	environment:       []string,
	working_directory: string,
	columns:           u16,
	rows:              u16,
}

/* Process_Info is copied native process ownership inspection. */
Process_Info :: struct {
	process_id:       i32,
	process_group_id: i32,
	open_descriptors: u8,
	live:             bool,
	reaped:           bool,
}

/* Process_Poll reports one nonblocking exit observation. */
Process_Poll :: struct {
	exited:      bool,
	exit_status: Exit_Status,
}

/* Local_Process owns one private PTY process adapter. */
Local_Process :: struct {
	state: rawptr,
}

/* Registry owns fixed-capacity interactive-session process state. */
Registry :: struct {
	state:  rawptr,
	closed: bool,
}

/* Session_Prepare_Request describes one copied registry entry. */
Session_Prepare_Request :: struct {
	name:              string,
	owner_kind:        Owner_Kind,
	owner_label:       string,
	working_directory: string,
	limits:            Limits,
	make_default:      bool,
}

/* Registry_Stats is one immutable aggregate resource snapshot. */
Registry_Stats :: struct {
	session_count:        u16,
	operating_count:      u16,
	exited_count:         u16,
	failed_count:         u16,
	open_descriptors:     u16,
	queued_input_bytes:   u64,
	queued_output_bytes:  u64,
	total_input_bytes:    u64,
	total_output_bytes:   u64,
	default_session:      Session_Ref,
}

/* Transport_Step reports one bounded nonblocking session turn. */
Transport_Step :: struct {
	ref:               Session_Ref,
	read_bytes:        u64,
	written_bytes:     u64,
	output_ready:      bool,
	input_pending:     bool,
	backpressured:     bool,
	would_block:       bool,
	process_exited:    bool,
	progress:          bool,
	next_wakeup_ns:    i64,
	failure:           Failure_Record,
}

/* Transport_Batch reports one bounded round-robin registry turn. */
Transport_Batch :: struct {
	sessions_visited:   u16,
	sessions_progressed: u16,
	read_bytes:         u64,
	written_bytes:      u64,
	work_remaining:     bool,
	backpressured:      bool,
	next_wakeup_ns:     i64,
	failure:            Failure_Record,
}

/* session_name_view borrows the populated bytes of one copied name. */
session_name_view :: proc(value: ^Session_Name) -> string {
	if value == nil || value.length == 0 || int(value.length) > len(value.bytes) {
		return ""
	}
	return string(value.bytes[:value.length])
}

/* working_context_view borrows the populated bytes of one copied path. */
working_context_view :: proc(value: ^Working_Context) -> string {
	if value == nil || value.length == 0 || int(value.length) > len(value.directory) {
		return ""
	}
	return string(value.directory[:value.length])
}

/* owner_label_view borrows the populated bytes of one copied provenance label. */
owner_label_view :: proc(value: ^Owner_Provenance) -> string {
	if value == nil || int(value.length) > len(value.label) {
		return ""
	}
	return string(value.label[:value.length])
}
