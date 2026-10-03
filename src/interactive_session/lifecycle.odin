// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interactive_session

import "core:unicode/utf8"

/* prepare_record validates and copies one resource-free session description. */
prepare_record :: proc(
	ref: Session_Ref,
	name: string,
	owner_kind: Owner_Kind,
	owner_label: string,
	working_directory: string,
) -> (record: Session_Record, ok: bool, failure: Failure_Record) {
	if ref.id == Session_ID(0) || ref.generation == Session_Generation(0) ||
	   owner_kind == .Invalid || !session_name_valid(name) ||
	   !owner_label_valid(owner_label) || !working_directory_valid(working_directory) {
		return {}, false, failure_record(.Prepare, .Invalid_Argument)
	}
	record.ref = ref
	record.lifecycle = .Prepared
	record.owner.kind = owner_kind
	record.name.length = u8(copy(record.name.bytes[:], transmute([]u8)name))
	record.owner.length = u8(copy(record.owner.label[:], transmute([]u8)owner_label))
	record.working_context.length = u16(copy(
		record.working_context.directory[:], transmute([]u8)working_directory))
	return record, true, {}
}

/* transition advances one record only through admitted lifecycle edges. */
transition :: proc(record: ^Session_Record, target: Lifecycle) -> (bool, Failure_Record) {
	if record == nil || target == .Invalid || !transition_allowed(record.lifecycle, target) {
		return false, failure_record(.Prepare, .Invalid_Transition)
	}
	record.lifecycle = target
	if target == .Closed {
		record.resources = {}
		record.cancel_requested = false
	}
	return true, {}
}

/* record_exit retains one normal or signalled child result. */
record_exit :: proc(record: ^Session_Record, status: Exit_Status) -> (bool, Failure_Record) {
	if record == nil || record.lifecycle != .Running || status.kind == .None {
		return false, failure_record(.Poll, .Invalid_Transition)
	}
	record.exit_status = status
	record.lifecycle = .Exited
	record.resources.process_id = 0
	record.resources.process_group_id = 0
	return true, {}
}

/* record_failure preserves the first failure and enters Failed. */
record_failure :: proc(record: ^Session_Record, failure: Failure_Record) -> bool {
	if record == nil || failure.code == .None || record.lifecycle == .Closed {
		return false
	}
	if record.failure.code == .None {
		record.failure = failure
	}
	record.lifecycle = .Failed
	return true
}

/* request_cancel marks one live or starting session for owner-driven shutdown. */
request_cancel :: proc(record: ^Session_Record) -> bool {
	if record == nil || (record.lifecycle != .Starting && record.lifecycle != .Running) {
		return false
	}
	record.cancel_requested = true
	return true
}

/* failure_record constructs one stable failure without unbounded context. */
failure_record :: proc(
	stage: Failure_Stage,
	code: Failure_Code,
	os_errno: i32 = 0,
	limit: u64 = 0,
	actual: u64 = 0,
	diagnostic: string = "",
) -> Failure_Record {
	value := Failure_Record {
		stage = stage,
		code = code,
		os_errno = os_errno,
		limit = limit,
		actual = actual,
	}
	count := min(len(diagnostic), len(value.diagnostic.bytes), int(max(u16)))
	value.diagnostic.length = u16(copy(
		value.diagnostic.bytes[:count], transmute([]u8)diagnostic[:count]))
	return value
}

/* limits_valid admits operating policy only within immutable ceilings. */
limits_valid :: proc(limits: Limits) -> bool {
	return limits.input_bytes > 0 && limits.input_bytes <= MAX_INPUT_BYTES &&
		limits.output_bytes > 0 && limits.output_bytes <= MAX_OUTPUT_BYTES &&
		limits.read_chunk_bytes > 0 && limits.read_chunk_bytes <= MAX_CHUNK_BYTES &&
		limits.write_chunk_bytes > 0 && limits.write_chunk_bytes <= MAX_CHUNK_BYTES &&
		limits.output_turn_bytes > 0 && limits.output_turn_bytes <= MAX_OUTPUT_TURN_BYTES &&
		limits.output_turn_nanoseconds > 0 &&
		limits.output_turn_nanoseconds <= MAX_OUTPUT_TURN_NANOSECONDS &&
		limits.shutdown_nanoseconds > 0 &&
		limits.shutdown_nanoseconds <= MAX_SHUTDOWN_NANOSECONDS &&
		limits.columns > 0 && limits.columns <= MAX_COLUMNS &&
		limits.rows > 0 && limits.rows <= MAX_ROWS &&
		u64(limits.columns) * u64(limits.rows) <= MAX_CELLS
}

@(private)
transition_allowed :: proc(source, target: Lifecycle) -> bool {
	switch source {
	case .Prepared:
		return target == .Starting || target == .Closing || target == .Failed
	case .Starting:
		return target == .Running || target == .Closing || target == .Failed
	case .Running:
		return target == .Exited || target == .Closing || target == .Failed
	case .Exited:
		return target == .Closing
	case .Failed:
		return target == .Closing
	case .Closing:
		return target == .Closed || target == .Failed
	case .Invalid, .Closed:
		return false
	}
	return false
}

@(private)
session_name_valid :: proc(value: string) -> bool {
	return len(value) > 0 && len(value) <= MAX_NAME_BYTES && utf8.valid_string(value)
}

@(private)
owner_label_valid :: proc(value: string) -> bool {
	return len(value) <= MAX_OWNER_LABEL_BYTES && utf8.valid_string(value)
}

@(private)
working_directory_valid :: proc(value: string) -> bool {
	return len(value) > 0 && len(value) <= MAX_DIRECTORY_BYTES &&
		value[0] == '/' && utf8.valid_string(value)
}
