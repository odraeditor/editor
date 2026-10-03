// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package feedback owns bounded semantic feedback identity, lifecycle, active
// state, retained history, and frontend-independent inspection.
package feedback

import "base:runtime"
import "core:unicode/utf8"

/* KIBIBYTE is the binary byte unit used by feedback policy. */
KIBIBYTE :: u64(1_024)
/* MEBIBYTE is 1,024 kibibytes. */
MEBIBYTE :: u64(1_024) * KIBIBYTE

/* MIN_ACTIVE_RECORDS is the smallest admitted active capacity. */
MIN_ACTIVE_RECORDS :: u64(8)
/* MAX_ACTIVE_RECORDS is the largest admitted active capacity. */
MAX_ACTIVE_RECORDS :: u64(1_024)
/* DEFAULT_ACTIVE_RECORDS is the calibrated active capacity. */
DEFAULT_ACTIVE_RECORDS :: u64(128)
/* MIN_HISTORY_RECORDS is the smallest admitted history capacity. */
MIN_HISTORY_RECORDS :: u64(16)
/* MAX_HISTORY_RECORDS is the largest admitted history capacity. */
MAX_HISTORY_RECORDS :: u64(4_096)
/* DEFAULT_HISTORY_RECORDS is the calibrated history capacity. */
DEFAULT_HISTORY_RECORDS :: u64(256)
/* MIN_HISTORY_BYTES is the smallest admitted retained-content budget. */
MIN_HISTORY_BYTES :: 64 * KIBIBYTE
/* MAX_HISTORY_BYTES is the largest admitted retained-content budget. */
MAX_HISTORY_BYTES :: 64 * MEBIBYTE
/* DEFAULT_HISTORY_BYTES is the calibrated retained-content budget. */
DEFAULT_HISTORY_BYTES :: 2 * MEBIBYTE
/* MAX_TITLE_BYTES bounds one copied title. */
MAX_TITLE_BYTES :: 256
/* MAX_MESSAGE_BYTES bounds one copied message. */
MAX_MESSAGE_BYTES :: 4 * 1_024
/* MAX_PHASE_BYTES bounds one copied progress phase. */
MAX_PHASE_BYTES :: 128
/* MAX_COALESCING_KEY_BYTES bounds one source-scoped coalescing key. */
MAX_COALESCING_KEY_BYTES :: 128
/* MAX_METADATA_ENTRIES bounds semantic metadata per record. */
MAX_METADATA_ENTRIES :: 8
/* MAX_METADATA_KEY_BYTES bounds one metadata key. */
MAX_METADATA_KEY_BYTES :: 64
/* MAX_METADATA_VALUE_BYTES bounds one metadata value. */
MAX_METADATA_VALUE_BYTES :: 256
/* MAX_ACTIONS bounds checked actions per record. */
MAX_ACTIONS :: 4
/* MAX_ACTION_NAME_BYTES bounds one command identity. */
MAX_ACTION_NAME_BYTES :: 128
/* MAX_ACTION_ARGUMENT_BYTES bounds one copied action argument. */
MAX_ACTION_ARGUMENT_BYTES :: 512
/* MAX_REPETITIONS bounds a coalesced notification counter. */
MAX_REPETITIONS :: u32(65_535)
/* MAX_INSPECTION_RECORDS bounds each copied inspection collection. */
MAX_INSPECTION_RECORDS :: u64(256)
/* MAX_HEADLESS_BYTES bounds one caller-owned observation buffer. */
MAX_HEADLESS_BYTES :: 1_024
/* MAX_UPDATES_PER_RECORD bounds one record lifetime. */
MAX_UPDATES_PER_RECORD :: u64(1_000_000)
/* DEFAULT_HEADLESS_PROGRESS_STRIDE coalesces routine progress observation. */
DEFAULT_HEADLESS_PROGRESS_STRIDE :: u32(32)

/* Registry_ID identifies one live feedback registry. */
Registry_ID :: distinct u64
/* Registry_Generation identifies one exact registry state. */
Registry_Generation :: distinct u64
/* Record_ID identifies one stable notification or operation. */
Record_ID :: distinct u64
/* Record_Generation identifies one immutable record update. */
Record_Generation :: distinct u64
/* Source_ID identifies the owner that reports feedback. */
Source_ID :: distinct u64
/* Source_Generation identifies one exact source lifetime. */
Source_Generation :: distinct u64
/* Action_ID identifies one record-scoped checked action. */
Action_ID :: distinct u64

/* Record_Kind distinguishes notifications from progress operations. */
Record_Kind :: enum u8 {
	Invalid,
	Notification,
	Progress,
}

/* Semantic_Class classifies feedback independently from severity. */
Semantic_Class :: enum u8 {
	Invalid,
	Acknowledgement,
	Information,
	Warning,
	Error,
	Progress,
	Completion,
}

/* Severity expresses the consequence of one record. */
Severity :: enum u8 {
	Invalid,
	Information,
	Warning,
	Error,
}

/* Attention records whether a record requires explicit user attention. */
Attention :: enum u8 {
	Ordinary,
	Required,
}

/* Lifecycle_Policy selects active-state retirement behavior. */
Lifecycle_Policy :: enum u8 {
	Invalid,
	Transient,
	Retained,
	Attention,
	Source_Bound,
}

/* Retention_Policy selects whether admitted snapshots enter history. */
Retention_Policy :: enum u8 {
	None,
	History,
}

/* Visibility separates ordinary content from explicit diagnostics. */
Visibility :: enum u8 {
	Invalid,
	Public,
	Diagnostic,
}

/* Sensitivity controls copied inspection and headless redaction. */
Sensitivity :: enum u8 {
	Ordinary,
	Sensitive,
}

/* Progress_State defines the monotonic operation lifecycle. */
Progress_State :: enum u8 {
	Invalid,
	Pending,
	Running,
	Succeeded,
	Failed,
	Cancelled,
}

/* Measurement_Kind distinguishes measured and indeterminate progress. */
Measurement_Kind :: enum u8 {
	Invalid,
	Indeterminate,
	Determinate,
}

/* Operation identifies one checked feedback operation. */
Operation :: enum u8 {
	Invalid,
	Initialize,
	Publish,
	Replace,
	Coalesce,
	Dismiss,
	Expire,
	Cancel,
	Resolve_Action,
	Retire_Source,
	Inspect,
	Clear_History,
	Observe,
	Close,
}

/* Failure_Code classifies expected feedback rejection. */
Failure_Code :: enum u16 {
	None,
	Invalid_Registry,
	Closed_Registry,
	Invalid_Identity,
	Invalid_Generation,
	Stale_Generation,
	Invalid_Kind,
	Invalid_Class,
	Invalid_Severity,
	Invalid_Lifecycle,
	Invalid_Progress,
	Invalid_Transition,
	Invalid_UTF8,
	Unsafe_Content,
	Title_Limit,
	Message_Limit,
	Phase_Limit,
	Metadata_Limit,
	Action_Limit,
	Active_Limit,
	History_Limit,
	Update_Limit,
	Inspection_Limit,
	Record_Not_Found,
	Source_Mismatch,
	Action_Not_Found,
	Cancellation_Unavailable,
	Allocation,
}

/* Policy_Field identifies one rejected resource-policy dimension. */
Policy_Field :: enum u8 {
	Invalid,
	Active_Records,
	History_Records,
	History_Bytes,
	Inspection_Records,
	Updates_Per_Record,
	Headless_Progress_Stride,
}

/* Policy contains active, history, update, inspection, and headless limits. */
Policy :: struct {
	active_records:           u64,
	history_records:          u64,
	history_bytes:            u64,
	inspection_records:       u64,
	updates_per_record:       u64,
	headless_progress_stride: u32,
}

/* DEFAULT_POLICY is the calibrated initial feedback policy. */
DEFAULT_POLICY :: Policy {
	active_records = DEFAULT_ACTIVE_RECORDS,
	history_records = DEFAULT_HISTORY_RECORDS,
	history_bytes = DEFAULT_HISTORY_BYTES,
	inspection_records = MAX_INSPECTION_RECORDS,
	updates_per_record = MAX_UPDATES_PER_RECORD,
	headless_progress_stride = DEFAULT_HEADLESS_PROGRESS_STRIDE,
}

/* Allocator_Set separates retained and temporary feedback storage. */
Allocator_Set :: struct {
	persistent: runtime.Allocator,
	temporary:  runtime.Allocator,
}

/* Source_Reference identifies one exact reporting owner lifetime. */
Source_Reference :: struct {
	id:         Source_ID,
	generation: Source_Generation,
}

/* Action_Proposal borrows one named command and bounded argument. */
Action_Proposal :: struct {
	id:        Action_ID,
	command:   string,
	argument:  string,
	cancel:    bool,
	sensitive: bool,
}

/* Action owns one copied checked action description. */
Action :: struct {
	id:        Action_ID,
	command:   string,
	argument:  string,
	cancel:    bool,
	sensitive: bool,
}

/* Metadata_Proposal borrows one semantic key-value pair. */
Metadata_Proposal :: struct {
	key:       string,
	value:     string,
	sensitive: bool,
}

/* Metadata owns one copied semantic key-value pair. */
Metadata :: struct {
	key:       string,
	value:     string,
	sensitive: bool,
}

/* Progress describes one complete operation generation. */
Progress :: struct {
	state:       Progress_State,
	measurement: Measurement_Kind,
	current:     u64,
	total:       u64,
	phase:       string,
}

/* Proposal borrows one complete candidate record for atomic admission. */
Proposal :: struct {
	id:             Record_ID,
	generation:     Record_Generation,
	replacement:    Record_ID,
	source:         Source_Reference,
	kind:           Record_Kind,
	class:          Semantic_Class,
	severity:       Severity,
	attention:      Attention,
	lifecycle:      Lifecycle_Policy,
	retention:      Retention_Policy,
	visibility:     Visibility,
	sensitivity:    Sensitivity,
	title:          string,
	message:        string,
	coalescing_key: string,
	progress:       Progress,
	metadata:       []Metadata_Proposal,
	actions:        []Action_Proposal,
}

/* Record owns one immutable admitted feedback generation. */
Record :: struct {
	id:              Record_ID,
	generation:      Record_Generation,
	source:          Source_Reference,
	kind:            Record_Kind,
	class:           Semantic_Class,
	severity:        Severity,
	attention:       Attention,
	lifecycle:       Lifecycle_Policy,
	retention:       Retention_Policy,
	visibility:      Visibility,
	sensitivity:     Sensitivity,
	title:           string,
	message:         string,
	coalescing_key:  string,
	progress:        Progress,
	metadata:        []Metadata,
	actions:         []Action,
	created_sequence: u64,
	updated_sequence: u64,
	repetition_count: u32,
}

/* Resource_Usage reports active, retained, eviction, and update accounting. */
Resource_Usage :: struct {
	active_records:       u64,
	active_bytes:         u64,
	history_records:      u64,
	history_bytes:        u64,
	evicted_history:      u64,
	dropped_history:      u64,
	accepted_updates:     u64,
	rejected_updates:     u64,
}

/* Registry_Stats copies identity, policy, sequence, and resource usage. */
Registry_Stats :: struct {
	registry_id: Registry_ID,
	generation:  Registry_Generation,
	sequence:    u64,
	policy:      Policy,
	usage:       Resource_Usage,
}

/* Inspection_Request bounds copied active and historical inspection. */
Inspection_Request :: struct {
	expected_generation: Registry_Generation,
	active_limit:        u64,
	history_limit:       u64,
	include_sensitive:   bool,
}

/* Inspection owns copied newest-first active and historical records. */
Inspection :: struct {
	stats:          Registry_Stats,
	active:         []Record,
	history:        []Record,
	last_rejection: Failure,
}

/* Cancellation_Request revalidates record and source authority. */
Cancellation_Request :: struct {
	record_id:         Record_ID,
	record_generation: Record_Generation,
	source:            Source_Reference,
}

/* Cancellation owns the copied cancellation command for its source owner. */
Cancellation :: struct {
	record_id:         Record_ID,
	record_generation: Record_Generation,
	source:            Source_Reference,
	action:            Action,
}

/* Action_Request revalidates one named action against exact record authority. */
Action_Request :: struct {
	record_id:         Record_ID,
	record_generation: Record_Generation,
	source:            Source_Reference,
	action_id:         Action_ID,
}

/* Action_Authority owns one copied action from an exact current or retained record. */
Action_Authority :: struct {
	record_id:         Record_ID,
	record_generation: Record_Generation,
	source:            Source_Reference,
	action:            Action,
}

/* Failure identifies one rejected operation without retaining proposal content. */
Failure :: struct {
	operation:  Operation,
	code:       Failure_Code,
	field:      Policy_Field,
	record_id:  Record_ID,
	generation: Record_Generation,
	source:     Source_Reference,
	limit:      u64,
	actual:     u64,
}

/* Registry is an opaque owner of active feedback and retained history. */
Registry :: struct {
	state:  rawptr,
	closed: bool,
}

/* policy_validate checks every policy limit without mutation. */
policy_validate :: proc(policy: Policy) -> (bool, Failure) {
	checks := [5]struct {value, minimum, maximum: u64, field: Policy_Field} {
		{policy.active_records, MIN_ACTIVE_RECORDS, MAX_ACTIVE_RECORDS, .Active_Records},
		{policy.history_records, MIN_HISTORY_RECORDS, MAX_HISTORY_RECORDS, .History_Records},
		{policy.history_bytes, MIN_HISTORY_BYTES, MAX_HISTORY_BYTES, .History_Bytes},
		{policy.inspection_records, 1, MAX_INSPECTION_RECORDS, .Inspection_Records},
		{policy.updates_per_record, 1, MAX_UPDATES_PER_RECORD, .Updates_Per_Record},
	}
	for check in checks {
		if check.value < check.minimum || check.value > check.maximum {
			return false, Failure {
				operation = .Initialize,
				code = .Invalid_Registry,
				field = check.field,
				limit = check.maximum,
				actual = check.value,
			}
		}
	}
	if policy.headless_progress_stride == 0 {
		return false, Failure {
			operation = .Initialize,
			code = .Invalid_Registry,
			field = .Headless_Progress_Stride,
			actual = 0,
		}
	}
	return true, {}
}

/* record_is_terminal reports whether progress has reached a final state. */
record_is_terminal :: proc(record: Record) -> bool {
	return record.kind == .Progress && progress_state_is_terminal(record.progress.state)
}

/* progress_state_is_terminal reports whether one lifecycle state is final. */
progress_state_is_terminal :: proc(state: Progress_State) -> bool {
	return state == .Succeeded || state == .Failed || state == .Cancelled
}

/* progress_transition_is_valid checks one monotonic lifecycle transition. */
progress_transition_is_valid :: proc(previous, next: Progress_State) -> bool {
	if previous == .Invalid || next == .Invalid || progress_state_is_terminal(previous) {
		return false
	}
	if previous == .Pending {
		return next == .Running || progress_state_is_terminal(next)
	}
	return previous == .Running && (next == .Running || progress_state_is_terminal(next))
}

/* content_is_safe rejects oversized, invalid UTF-8, escape, and NUL content. */
content_is_safe :: proc(value: string, maximum: int) -> bool {
	if len(value) > maximum || !utf8.valid_string(value) do return false
	for byte in transmute([]u8)value {
		if byte == 0x1b || byte == 0 do return false
	}
	return true
}
