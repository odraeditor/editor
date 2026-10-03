// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_planning

import "core:unicode/utf8"

/* MAX_EFFORT_SECONDS bounds one configured effort or countdown duration. */
MAX_EFFORT_SECONDS :: u64(10 * 365 * 24 * 60 * 60)

/* Duration_Value is one normalized nonnegative duration. */
Duration_Value :: struct {
	seconds: u64,
}

/* Duration_Text owns one bounded canonical duration representation. */
Duration_Text :: struct {
	bytes:  [64]u8,
	length: u8,
}

/* Relative_Timer_ID identifies one in-memory timer lifetime. */
Relative_Timer_ID :: distinct u64

/* Relative_Timer_Mode distinguishes stopwatch and countdown behavior. */
Relative_Timer_Mode :: enum u8 {
	Invalid,
	Stopwatch,
	Countdown,
}

/* Relative_Timer_State identifies explicit timer lifecycle. */
Relative_Timer_State :: enum u8 {
	Invalid,
	Running,
	Paused,
	Stopped,
	Completed,
}

/* Relative_Timer_Record is one copied timer state independent from task clocks. */
Relative_Timer_Record :: struct {
	id:                  Relative_Timer_ID,
	mode:                Relative_Timer_Mode,
	state:               Relative_Timer_State,
	started_at:          Absolute_Instant,
	accumulated_seconds: u64,
	target_seconds:      u64,
	notified:            bool,
}

/* Timer_Notification_Outcome isolates optional notification availability. */
Timer_Notification_Outcome :: enum u8 {
	Not_Requested,
	Requested,
	Unavailable,
}

/* Relative_Timer_Snapshot reports elapsed and remaining values. */
Relative_Timer_Snapshot :: struct {
	record:       Relative_Timer_Record,
	elapsed:      u64,
	remaining:    u64,
	notification: Timer_Notification_Outcome,
}

/* effort_parse normalizes compatible H:MM and number-unit duration forms. */
effort_parse :: proc(source: string) -> (Duration_Value, bool) {
	if len(source) == 0 || len(source) > MAX_LABEL_BYTES || !utf8.valid_string(source) do return {}, false
	separator := -1
	for character, index in source do if character == ':' do separator = index
	seconds: u64
	if separator >= 0 {
		if separator == 0 || separator == len(source) - 1 do return {}, false
		hours, hours_ok := timer_parse_u64(source[:separator])
		minutes, minutes_ok := timer_parse_u64(source[separator + 1:])
		if !hours_ok || !minutes_ok || minutes >= 60 || hours > MAX_EFFORT_SECONDS / 3_600 do return {}, false
		seconds = hours * 3_600 + minutes * 60
	} else {
		if len(source) < 2 do return {}, false
		value, parsed := timer_parse_u64(source[:len(source) - 1])
		if !parsed do return {}, false
		multiplier := u64(0)
		switch source[len(source) - 1] {
		case 'm': multiplier = 60
		case 'h': multiplier = 3_600
		case 'd': multiplier = 86_400
		case 'w': multiplier = 604_800
		case:     return {}, false
		}
		if value > MAX_EFFORT_SECONDS / multiplier do return {}, false
		seconds = value * multiplier
	}
	return {seconds = seconds}, seconds > 0 && seconds <= MAX_EFFORT_SECONDS
}

/* duration_text_format emits one deterministic H:MM representation. */
duration_text_format :: proc(value: Duration_Value) -> (Duration_Text, bool) {
	if value.seconds > MAX_EFFORT_SECONDS do return {}, false
	result: Duration_Text
	hours := value.seconds / 3_600
	minutes := (value.seconds % 3_600) / 60
	cursor := 0
	if !time_buffer_write_u64(result.bytes[:], &cursor, hours, 1) ||
	   !time_buffer_write_byte(result.bytes[:], &cursor, ':') ||
	   !time_buffer_write_u64(result.bytes[:], &cursor, minutes, 2) {
		return {}, false
	}
	result.length = u8(cursor)
	return result, true
}

/* duration_text returns one copied duration representation. */
duration_text :: proc(value: ^Duration_Text) -> string {
	if value == nil || value.length == 0 || int(value.length) > len(value.bytes) do return ""
	return string(value.bytes[:value.length])
}

/* relative_timer_start creates one stopwatch or countdown without touching task clocks. */
relative_timer_start :: proc(
	id: Relative_Timer_ID,
	mode: Relative_Timer_Mode,
	started_at: Absolute_Instant,
	target_seconds: u64 = 0,
) -> (Relative_Timer_Record, bool, Failure) {
	if id == Relative_Timer_ID(0) || mode == .Invalid || !absolute_instant_is_valid(started_at) ||
	   target_seconds > MAX_EFFORT_SECONDS || (mode == .Countdown && target_seconds == 0) ||
	   (mode == .Stopwatch && target_seconds != 0) {
		return {}, false, planning_failure(.Time, .Invalid_Request, .Timer)
	}
	return {
		id = id,
		mode = mode,
		state = .Running,
		started_at = started_at,
		target_seconds = target_seconds,
	}, true, {}
}

/* relative_timer_pause captures elapsed time and enters paused state. */
relative_timer_pause :: proc(
	record: Relative_Timer_Record,
	at: Absolute_Instant,
) -> (Relative_Timer_Record, bool, Failure) {
	if !relative_timer_record_is_valid(record) || record.state != .Running {
		return {}, false, planning_failure(.Time, .Invalid_Request, .Timer)
	}
	delta, delta_ok := absolute_instant_elapsed_seconds(record.started_at, at)
	if !delta_ok || delta > max(u64) - record.accumulated_seconds {
		return {}, false, planning_failure(.Time, .Conflict, .Timer)
	}
	result := record
	result.accumulated_seconds += delta
	if result.accumulated_seconds > MAX_EFFORT_SECONDS {
		return {}, false, planning_failure(.Time, .Limited, .Timer)
	}
	result.state = .Paused
	return result, true, {}
}

/* relative_timer_resume restarts one paused timer from a captured instant. */
relative_timer_resume :: proc(
	record: Relative_Timer_Record,
	at: Absolute_Instant,
) -> (Relative_Timer_Record, bool, Failure) {
	if !relative_timer_record_is_valid(record) || record.state != .Paused ||
	   !absolute_instant_is_valid(at) {
		return {}, false, planning_failure(.Time, .Invalid_Request, .Timer)
	}
	result := record
	result.started_at = at
	result.state = .Running
	return result, true, {}
}

/* relative_timer_stop captures elapsed time and stops without task-clock effects. */
relative_timer_stop :: proc(
	record: Relative_Timer_Record,
	at: Absolute_Instant,
) -> (Relative_Timer_Record, bool, Failure) {
	if !relative_timer_record_is_valid(record) ||
	   (record.state != .Running && record.state != .Paused) {
		return {}, false, planning_failure(.Time, .Invalid_Request, .Timer)
	}
	result := record
	if record.state == .Running {
		delta, delta_ok := absolute_instant_elapsed_seconds(record.started_at, at)
		if !delta_ok || delta > max(u64) - result.accumulated_seconds {
			return {}, false, planning_failure(.Time, .Conflict, .Timer)
		}
		result.accumulated_seconds += delta
		if result.accumulated_seconds > MAX_EFFORT_SECONDS {
			return {}, false, planning_failure(.Time, .Limited, .Timer)
		}
	}
	result.state = .Stopped
	return result, true, {}
}

/* relative_timer_reset clears elapsed and notification state. */
relative_timer_reset :: proc(record: Relative_Timer_Record) -> (Relative_Timer_Record, bool) {
	if !relative_timer_record_is_valid(record) do return {}, false
	result := record
	result.state = .Stopped
	result.started_at = {}
	result.accumulated_seconds = 0
	result.notified = false
	return result, true
}

/* relative_timer_tick derives display state and isolates notification failure. */
relative_timer_tick :: proc(
	record: Relative_Timer_Record,
	now: Absolute_Instant,
	notification_available: bool,
	cancel_requested: bool = false,
) -> (Relative_Timer_Snapshot, bool, Failure) {
	if cancel_requested do return {}, false, planning_failure(.Time, .Cancelled, .Timer)
	if !relative_timer_record_is_valid(record) || !absolute_instant_is_valid(now) {
		return {}, false, planning_failure(.Time, .Invalid_Request, .Timer)
	}
	elapsed := record.accumulated_seconds
	if record.state == .Running {
		delta, delta_ok := absolute_instant_elapsed_seconds(record.started_at, now)
		if !delta_ok || delta > max(u64) - elapsed do return {}, false, planning_failure(.Time, .Conflict, .Timer)
		elapsed += delta
	}
	if elapsed > MAX_EFFORT_SECONDS do return {}, false, planning_failure(.Time, .Limited, .Timer)
	result := Relative_Timer_Snapshot{record = record, elapsed = elapsed}
	if record.mode == .Countdown {
		if elapsed < record.target_seconds {
			result.remaining = record.target_seconds - elapsed
		} else {
			result.record.state = .Completed
			result.record.accumulated_seconds = elapsed
			if !record.notified {
				if notification_available {
					result.notification = .Requested
					result.record.notified = true
				} else {
					result.notification = .Unavailable
				}
			}
		}
	}
	return result, true, {}
}

/* relative_timer_elapsed_text emits an insertable HH:MM:SS value. */
relative_timer_elapsed_text :: proc(elapsed_seconds: u64, output: []u8) -> (string, bool) {
	if len(output) < 8 || elapsed_seconds > MAX_EFFORT_SECONDS do return "", false
	hours := elapsed_seconds / 3_600
	minutes := (elapsed_seconds % 3_600) / 60
	seconds := elapsed_seconds % 60
	cursor := 0
	if !time_buffer_write_u64(output, &cursor, hours, 2) ||
	   !time_buffer_write_byte(output, &cursor, ':') ||
	   !time_buffer_write_u64(output, &cursor, minutes, 2) ||
	   !time_buffer_write_byte(output, &cursor, ':') ||
	   !time_buffer_write_u64(output, &cursor, seconds, 2) {
		return "", false
	}
	return string(output[:cursor]), true
}

@(private)
relative_timer_record_is_valid :: proc(record: Relative_Timer_Record) -> bool {
	if record.id == Relative_Timer_ID(0) || record.mode == .Invalid || record.state == .Invalid ||
	   record.accumulated_seconds > MAX_EFFORT_SECONDS || record.target_seconds > MAX_EFFORT_SECONDS {
		return false
	}
	if record.mode == .Countdown && record.target_seconds == 0 do return false
	if record.mode == .Stopwatch && record.target_seconds != 0 do return false
	if record.state == .Running && !absolute_instant_is_valid(record.started_at) do return false
	return true
}

@(private)
timer_parse_u64 :: proc(source: string) -> (u64, bool) {
	if len(source) == 0 do return 0, false
	value: u64
	for character in source {
		if character < '0' || character > '9' do return 0, false
		digit := u64(character - '0')
		if value > (max(u64) - digit) / 10 do return 0, false
		value = value * 10 + digit
	}
	return value, true
}
