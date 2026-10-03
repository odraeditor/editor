// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_planning

import "../language"

/* Clock_Start_Request binds one start or resume to an exact durable target. */
Clock_Start_Request :: struct {
	domain:     Clock_Domain_ID,
	resource:   Resource_Identity,
	scope:      Scope,
	target:     Semantic_Target,
	started_at: Absolute_Instant,
	time_zone:  Time_Zone_Text,
	transition: Clock_Transition,
}

/* Clock_Entry is one closed attributable interval. */
Clock_Entry :: struct {
	domain:           Clock_Domain_ID,
	resource:         Resource_Identity,
	target:           Semantic_Target,
	source_bytes:     u64,
	started_at:       Absolute_Instant,
	ended_at:         Absolute_Instant,
	excluded_seconds: u64,
	cancelled:        bool,
}

/* Idle_Resolution selects explicit idle-time handling. */
Idle_Resolution :: enum u8 {
	Invalid,
	Keep,
	Subtract,
	Cancel,
}

/* Clock_Idle_Result reports one explicit idle decision without hidden activity. */
Clock_Idle_Result :: struct {
	record:           Active_Clock_Record,
	excluded_seconds: u64,
	cancelled:        bool,
}

/* Clock_Recovery_Action selects explicit restart recovery. */
Clock_Recovery_Action :: enum u8 {
	Invalid,
	Resume,
	Close,
	Discard,
}

/* Clock_Recovery_Result reports recovered durable state and an optional entry. */
Clock_Recovery_Result :: struct {
	record:    Active_Clock_Record,
	entry:     Clock_Entry,
	has_entry: bool,
}

/* Clock_Table_Row is one bounded target total. */
Clock_Table_Row :: struct {
	target:        Semantic_Target,
	total_seconds: u64,
	entry_count:   u32,
}

/* active_clock_start prepares one durable active record for an empty domain. */
active_clock_start :: proc(
	current: ^Active_Clock_Record,
	request: Clock_Start_Request,
) -> (Active_Clock_Record, bool, Failure) {
	if current != nil && active_clock_record_is_valid(current^) &&
	   current.recovery_state != .Resolved {
		return {}, false, planning_failure(.Time, .Conflict, .Clock)
	}
	if request.domain == Clock_Domain_ID(0) || !resource_identity_is_valid(request.resource) ||
	   !semantic_target_is_valid(request.target, request.scope) ||
	   !absolute_instant_is_valid(request.started_at) ||
	   !active_clock_time_zone_is_valid(request.time_zone) ||
	   (request.transition != .Start && request.transition != .Resume) {
		return {}, false, planning_failure(.Time, .Invalid_Request, .Clock)
	}
	record := Active_Clock_Record{
		schema_version = ACTIVE_CLOCK_SCHEMA_VERSION,
		domain = request.domain,
		resource = request.resource,
		target = request.target,
		started_at = request.started_at,
		time_zone = request.time_zone,
		source_revision = u64(request.target.range.scope.source_revision),
		source_bytes = request.scope.source_bytes,
		last_transition = request.transition,
		recovery_state = .Active,
	}
	if !active_clock_record_is_valid(record) do return {}, false, planning_failure(.Time, .Malformed, .Clock)
	return record, true, {}
}

/* active_clock_stop closes one active record and returns its source entry. */
active_clock_stop :: proc(
	record: Active_Clock_Record,
	ended_at: Absolute_Instant,
	excluded_seconds: u64 = 0,
) -> (Active_Clock_Record, Clock_Entry, bool, Failure) {
	if !active_clock_record_is_valid(record) || record.recovery_state != .Active ||
	   !absolute_instant_is_valid(ended_at) || absolute_instant_compare(ended_at, record.started_at) < 0 {
		return {}, {}, false, planning_failure(.Time, .Invalid_Request, .Clock)
	}
	duration, duration_ok := absolute_instant_elapsed_seconds(record.started_at, ended_at)
	if !duration_ok || excluded_seconds > duration {
		return {}, {}, false, planning_failure(.Time, .Conflict, .Clock)
	}
	closed := record
	closed.last_transition = .Stop
	closed.recovery_state = .Resolved
	entry := Clock_Entry{
		domain = record.domain,
		resource = record.resource,
		target = record.target,
		source_bytes = record.source_bytes,
		started_at = record.started_at,
		ended_at = ended_at,
		excluded_seconds = excluded_seconds,
	}
	return closed, entry, true, {}
}

/* active_clock_cancel resolves one active interval without publishing elapsed time. */
active_clock_cancel :: proc(record: Active_Clock_Record) -> (Active_Clock_Record, bool, Failure) {
	if !active_clock_record_is_valid(record) || record.recovery_state != .Active {
		return {}, false, planning_failure(.Time, .Invalid_Request, .Clock)
	}
	result := record
	result.last_transition = .Cancel
	result.recovery_state = .Resolved
	return result, true, {}
}

/* active_clock_switch closes the current target and starts the next atomically in memory. */
active_clock_switch :: proc(
	record: Active_Clock_Record,
	next: Clock_Start_Request,
	switched_at: Absolute_Instant,
) -> (Active_Clock_Record, Clock_Entry, bool, Failure) {
	closed, entry, stopped, failure := active_clock_stop(record, switched_at)
	if !stopped do return {}, {}, false, failure
	_ = closed
	if next.domain != record.domain do return {}, {}, false, planning_failure(.Time, .Conflict, .Clock)
	next_request := next
	next_request.started_at = switched_at
	next_request.transition = .Resume
	started, started_ok, start_failure := active_clock_start(nil, next_request)
	if !started_ok do return {}, {}, false, start_failure
	started.last_transition = .Switch
	return started, entry, true, {}
}

/* active_clock_resume starts a new interval on one exact closed-entry target. */
active_clock_resume :: proc(
	entry: Clock_Entry,
	scope: Scope,
	target: Semantic_Target,
	resumed_at: Absolute_Instant,
	time_zone: Time_Zone_Text,
) -> (Active_Clock_Record, bool, Failure) {
	if !clock_entry_is_valid(entry) || absolute_instant_compare(resumed_at, entry.ended_at) < 0 {
		return {}, false, planning_failure(.Time, .Malformed, .Clock)
	}
	return active_clock_start(nil, {
		domain = entry.domain,
		resource = entry.resource,
		scope = scope,
		target = target,
		started_at = resumed_at,
		time_zone = time_zone,
		transition = .Resume,
	})
}

/* active_clock_resolve_idle applies one explicit idle decision. */
active_clock_resolve_idle :: proc(
	record: Active_Clock_Record,
	idle_started, resumed_at: Absolute_Instant,
	resolution: Idle_Resolution,
) -> (Clock_Idle_Result, bool, Failure) {
	if !active_clock_record_is_valid(record) || record.recovery_state != .Active ||
	   absolute_instant_compare(idle_started, record.started_at) < 0 ||
	   absolute_instant_compare(resumed_at, idle_started) < 0 {
		return {}, false, planning_failure(.Time, .Invalid_Request, .Clock)
	}
	result := Clock_Idle_Result{record = record}
	result.record.last_transition = .Idle_Resolution
	switch resolution {
	case .Keep:
	case .Subtract:
		result.excluded_seconds, _ = absolute_instant_elapsed_seconds(idle_started, resumed_at)
	case .Cancel:
		result.cancelled = true
		result.record.recovery_state = .Resolved
	case .Invalid:
		return {}, false, planning_failure(.Time, .Confirmation_Required, .Clock)
	}
	return result, true, {}
}

/* active_clock_recover resolves interrupted durable state only through an explicit action. */
active_clock_recover :: proc(
	record: Active_Clock_Record,
	current_scope: Scope,
	current_target: Semantic_Target,
	action: Clock_Recovery_Action,
	instant: Absolute_Instant,
) -> (Clock_Recovery_Result, bool, Failure) {
	if !active_clock_record_is_valid(record) || record.recovery_state == .Resolved ||
	   !scope_is_valid(current_scope) || !absolute_instant_is_valid(instant) ||
	   active_clock_startup_state(record, current_scope.analysis) != .Recovery_Required {
		return {}, false, planning_failure(.Time, .Invalid_Request, .Clock)
	}
	result := Clock_Recovery_Result{record = record}
	switch action {
	case .Resume:
		if !semantic_target_is_valid(current_target, current_scope) {
			return {}, false, planning_failure(.Time, .Stale, .Clock)
		}
		result.record.target = current_target
		result.record.source_revision = u64(current_target.range.scope.source_revision)
		result.record.source_bytes = current_scope.source_bytes
		result.record.last_transition = .Recovery
		result.record.recovery_state = .Active
	case .Close:
		recovering := record
		recovering.recovery_state = .Active
		closed, entry, stopped, failure := active_clock_stop(
			recovering,
			instant,
		)
		if !stopped do return {}, false, failure
		result.record, result.entry, result.has_entry = closed, entry, true
		result.record.last_transition = .Recovery
	case .Discard:
		result.record.last_transition = .Recovery
		result.record.recovery_state = .Resolved
	case .Invalid:
		return {}, false, planning_failure(.Time, .Confirmation_Required, .Clock)
	}
	return result, true, {}
}

/* clock_table_summarize groups valid closed entries by exact semantic target. */
clock_table_summarize :: proc(entries: []Clock_Entry, output: []Clock_Table_Row) -> (int, bool, Failure) {
	if len(entries) > int(MAX_AGENDA_ENTRIES) {
		failure := planning_failure(.Time, .Limited, .Clock)
		failure.limit, failure.actual = u64(MAX_AGENDA_ENTRIES), u64(len(entries))
		return 0, false, failure
	}
	count := 0
	for entry in entries {
		if !clock_entry_is_valid(entry) do return 0, false, planning_failure(.Time, .Malformed, .Clock)
		if entry.cancelled do continue
		duration, duration_ok := clock_entry_elapsed_seconds(entry)
		if !duration_ok do return 0, false, planning_failure(.Time, .Malformed, .Clock)
		row_index := -1
		for index in 0 ..< count {
			if output[index].target == entry.target {
				row_index = index
				break
			}
		}
		if row_index < 0 {
			if count >= len(output) {
				failure := planning_failure(.Time, .Limited, .Clock)
				failure.limit, failure.actual = u64(len(output)), u64(count + 1)
				return 0, false, failure
			}
			row_index, count = count, count + 1
			output[row_index].target = entry.target
		}
		if duration > max(u64) - output[row_index].total_seconds {
			return 0, false, planning_failure(.Time, .Limited, .Clock)
		}
		output[row_index].total_seconds += duration
		output[row_index].entry_count += 1
	}
	return count, true, {}
}

/* clock_entry_elapsed_seconds returns elapsed duration after explicit exclusions. */
clock_entry_elapsed_seconds :: proc(entry: Clock_Entry) -> (u64, bool) {
	duration, ok := absolute_instant_elapsed_seconds(entry.started_at, entry.ended_at)
	if !ok || entry.excluded_seconds > duration do return 0, false
	return duration - entry.excluded_seconds, true
}

@(private)
clock_entry_is_valid :: proc(entry: Clock_Entry) -> bool {
	return entry.domain != Clock_Domain_ID(0) && resource_identity_is_valid(entry.resource) &&
	       entry.target.node_id != language.Jan_Node_ID(0) && entry.target.kind != .Invalid &&
	       language.jan_source_range_is_valid(entry.target.range, entry.source_bytes) &&
	       absolute_instant_is_valid(entry.started_at) && absolute_instant_is_valid(entry.ended_at) &&
	       absolute_instant_compare(entry.ended_at, entry.started_at) >= 0
}

@(private)
absolute_instant_compare :: proc(left, right: Absolute_Instant) -> int {
	if left.seconds != right.seconds do return -1 if left.seconds < right.seconds else 1
	if left.nanoseconds != right.nanoseconds do return -1 if left.nanoseconds < right.nanoseconds else 1
	return 0
}

@(private)
absolute_instant_elapsed_seconds :: proc(start, end: Absolute_Instant) -> (u64, bool) {
	if absolute_instant_compare(end, start) < 0 do return 0, false
	seconds := end.seconds - start.seconds
	if seconds < 0 do return 0, false
	if end.nanoseconds < start.nanoseconds {
		if seconds == 0 do return 0, true
		seconds -= 1
	}
	return u64(seconds), true
}
