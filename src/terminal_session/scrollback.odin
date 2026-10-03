// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "core:unicode/utf8"
import "../terminal_emulator"

/* registry_scrollback copies retained range, viewport, and follow state. */
registry_scrollback :: proc(
	registry: ^Registry,
	ref: Session_Ref,
) -> (record: Scrollback_Record, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil do return {}, false, registry_access_failure(registry, .Scrollback)
	session, resolved := registry_resolve(state, ref)
	if !resolved do return {}, false, failure_record(.Scrollback, .Stale_Reference)
	return scrollback_record(session, ref)
}

/* registry_scroll_viewport changes the shared viewport and copies its result. */
registry_scroll_viewport :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	action: Viewport_Action,
	value: i64 = 0,
) -> (record: Scrollback_Record, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil do return {}, false, registry_access_failure(registry, .Scrollback)
	session, resolved := registry_resolve(state, ref)
	if !resolved do return {}, false, failure_record(.Scrollback, .Stale_Reference)
	behavior: terminal_emulator.Scroll
	switch action {
	case .Top:    behavior = .Top
	case .Bottom: behavior = .Bottom
	case .Delta:  behavior = .Delta
	case .Row:
		if value < 0 do return {}, false, failure_record(.Scrollback, .Invalid_Argument)
		behavior = .Row
	case:
		return {}, false, failure_record(.Scrollback, .Invalid_Argument)
	}
	if result := terminal_emulator.scroll(session.record.emulator, behavior, value); result != .OK {
		return {}, false, emulator_failure(.Scrollback, result)
	}
	return scrollback_record(session, ref)
}

/* registry_compress_scrollback performs one scheduler-safe compression step. */
registry_compress_scrollback :: proc(
	registry: ^Registry,
	ref: Session_Ref,
) -> (observation: Compression_Observation, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil do return {}, false, registry_access_failure(registry, .Scrollback)
	session, resolved := registry_resolve(state, ref)
	if !resolved do return {}, false, failure_record(.Scrollback, .Stale_Reference)
	before, before_result := terminal_emulator.scroll_state(session.record.emulator)
	if before_result != .OK do return {}, false, emulator_failure(.Scrollback, before_result)
	pending, supported, compression_result := terminal_emulator.compress(session.record.emulator)
	if compression_result != .OK {
		return {}, false, emulator_failure(.Scrollback, compression_result)
	}
	after, after_result := terminal_emulator.scroll_state(session.record.emulator)
	if after_result != .OK do return {}, false, emulator_failure(.Scrollback, after_result)
	observation = Compression_Observation {
		ref = ref,
		activity_before = before.compression_activity,
		activity_after = after.compression_activity,
		pending = pending,
		supported = supported,
		progress = supported,
	}
	return observation, true, {}
}

/* registry_copy_text copies one bounded screen, viewport, or absolute range. */
registry_copy_text :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	request: Text_Request,
	output: []u8,
) -> (snapshot: Text_Copy, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil do return {}, false, registry_access_failure(registry, .Scrollback)
	session, resolved := registry_resolve(state, ref)
	if !resolved do return {}, false, failure_record(.Scrollback, .Stale_Reference)
	foreign_scope: terminal_emulator.Text_Scope
	switch request.scope {
	case .Screen:        foreign_scope = .Screen
	case .Viewport:      foreign_scope = .Viewport
	case .Screen_Range:  foreign_scope = .Screen_Range
	case .History_Range: foreign_scope = .History_Range
	case:
		return {}, false, failure_record(.Scrollback, .Invalid_Argument)
	}
	if request.scope == .Screen_Range || request.scope == .History_Range {
		if request.range.end_row < request.range.start_row ||
		   (request.range.end_row == request.range.start_row &&
		    request.range.end_column < request.range.start_column) {
			return {}, false, failure_record(.Scrollback, .Invalid_Argument)
		}
	}
	capacity := len(output)
	if u64(capacity) > session.limits.copied_text_bytes {
		capacity = int(session.limits.copied_text_bytes)
	}
	foreign_request := terminal_emulator.Text_Request {
		scope = foreign_scope,
		start_column = request.range.start_column,
		start_row = request.range.start_row,
		end_column = request.range.end_column,
		end_row = request.range.end_row,
		rectangle = request.range.rectangle,
		unwrap = request.normalized,
		trim = true,
	}
	copied, required, result := terminal_emulator.format_text_bounded(
		session.record.emulator,
		foreign_request,
		output[:capacity],
	)
	if result != .OK do return {}, false, emulator_failure(.Scrollback, result)
	if !utf8.valid_string(string(output[:copied])) {
		for _ in 0 ..< 3 {
			if copied == 0 do break
			copied -= 1
			if utf8.valid_string(string(output[:copied])) do break
		}
		if !utf8.valid_string(string(output[:copied])) {
			return {}, false, emulator_failure(.Scrollback, .Foreign_Failure)
		}
	}
	snapshot = Text_Copy {
		ref = ref,
		scope = request.scope,
		range = request.range,
		required_bytes = u64(required),
		copied_bytes = u64(copied),
		limit_bytes = session.limits.copied_text_bytes,
		truncated = required > copied,
		normalized = request.normalized,
	}
	return snapshot, true, {}
}

@(private)
scrollback_record :: proc(
	session: ^Session_State,
	ref: Session_Ref,
) -> (record: Scrollback_Record, ok: bool, failure: Failure_Record) {
	state, result := terminal_emulator.scroll_state(session.record.emulator)
	if result != .OK do return {}, false, emulator_failure(.Scrollback, result)
	record = Scrollback_Record {
		ref = ref,
		total_rows = state.total_rows,
		scrollback_rows = state.scrollback_rows,
		retained_start_row = 0,
		retained_end_row = state.total_rows,
		viewport_offset = state.viewport_offset,
		viewport_rows = state.viewport_rows,
		scrollback_max_bytes = state.scrollback_max_bytes,
		scrollback_max_rows = state.scrollback_max_lines,
		compression_activity = state.compression_activity,
		following = state.viewport_active,
	}
	return record, true, {}
}
