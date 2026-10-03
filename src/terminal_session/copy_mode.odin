// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "core:strings"
import "core:unicode/utf8"
import "../terminal_emulator"

/* registry_copy_mode_enter creates caller-owned copy state at the live cursor. */
registry_copy_mode_enter :: proc(
	registry: ^Registry,
	ref: Session_Ref,
) -> (transition: Copy_Mode_Transition, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil do return {}, false, registry_access_failure(registry, .Copy_Mode)
	session, resolved := registry_resolve(state, ref)
	if !resolved do return {}, false, failure_record(.Copy_Mode, .Stale_Reference)
	scrollback, scroll_result := terminal_emulator.scroll_state(session.record.emulator)
	if scroll_result != .OK do return {}, false, emulator_failure(.Copy_Mode, scroll_result)
	render, render_result := terminal_emulator.render(session.record.emulator)
	if render_result != .OK do return {}, false, emulator_failure(.Copy_Mode, render_result)
	point_row := copy_mode_max_row(scrollback.total_rows)
	if scrollback.total_rows > 0 {
		point_row = min(scrollback.viewport_offset + u64(render.cursor_row), point_row)
	}
	point_column := u32(render.cursor_column)
	if session.columns > 0 do point_column = min(point_column, u32(session.columns - 1))
	copy_state := Copy_Mode_State {
		active = true,
		point_row = point_row,
		point_column = point_column,
		desired_column = point_column,
		viewport_top_row = copy_mode_clamp_viewport(
			scrollback.viewport_offset,
			scrollback.total_rows,
			scrollback.viewport_rows,
		),
		viewport_rows = max(scrollback.viewport_rows, u64(1)),
		follow_tail_on_entry = scrollback.viewport_active,
	}
	return Copy_Mode_Transition{state = copy_state, changed = true}, true, {}
}

/* registry_copy_mode_move moves one caller-owned point within retained bounds. */
registry_copy_mode_move :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	copy_state: Copy_Mode_State,
	movement: Copy_Movement,
	count: u32 = 1,
) -> (transition: Copy_Mode_Transition, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil do return {}, false, registry_access_failure(registry, .Copy_Mode)
	session, resolved := registry_resolve(state, ref)
	if !resolved do return {}, false, failure_record(.Copy_Mode, .Stale_Reference)
	if !copy_state.active || movement == .Invalid || count == 0 {
		return {}, false, failure_record(.Copy_Mode, .Invalid_Argument)
	}
	scrollback, scroll_result := terminal_emulator.scroll_state(session.record.emulator)
	if scroll_result != .OK do return {}, false, emulator_failure(.Copy_Mode, scroll_result)
	next := copy_mode_reconciled(copy_state, scrollback, session.columns)
	previous := next
	max_row := copy_mode_max_row(scrollback.total_rows)
	max_column := copy_mode_max_column(session.columns)
	amount := u64(count)
	#partial switch movement {
	case .Previous_Column:
		next.point_column = u32(copy_mode_sub(u64(next.point_column), amount))
		next.desired_column = next.point_column
	case .Next_Column:
		next.point_column = u32(min(u64(max_column), u64(next.point_column) + amount))
		next.desired_column = next.point_column
	case .Previous_Row:
		next.point_row = copy_mode_sub(next.point_row, amount)
		next.point_column = min(next.desired_column, max_column)
	case .Next_Row:
		next.point_row = min(max_row, next.point_row + amount)
		next.point_column = min(next.desired_column, max_column)
	case .Line_Start:
		next.point_column = 0
		next.desired_column = 0
	case .Line_End:
		next.point_column = max_column
		next.desired_column = max_column
	case .Previous_Page:
		next.point_row = copy_mode_sub(next.point_row, amount * next.viewport_rows)
		next.point_column = min(next.desired_column, max_column)
	case .Next_Page:
		next.point_row = min(max_row, next.point_row + amount * next.viewport_rows)
		next.point_column = min(next.desired_column, max_column)
	case .Retained_Start:
		next.point_row = 0
		next.point_column = 0
		next.desired_column = 0
	case .Retained_End:
		next.point_row = max_row
		next.point_column = max_column
		next.desired_column = max_column
	}
	next.viewport_top_row = copy_mode_reveal_point(next, scrollback.total_rows)
	return Copy_Mode_Transition{state = next, changed = next != previous}, true, {}
}

/* registry_copy_mode_set_mark activates a selection at the current point. */
registry_copy_mode_set_mark :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	copy_state: Copy_Mode_State,
) -> (transition: Copy_Mode_Transition, ok: bool, failure: Failure_Record) {
	reconciled, reconciled_ok, reconcile_failure := registry_copy_mode_reconcile(
		registry, ref, copy_state,
	)
	if !reconciled_ok do return {}, false, reconcile_failure
	next := reconciled.state
	if !next.active do return {}, false, failure_record(.Copy_Mode, .Invalid_Argument)
	next.mark_present = true
	next.selection_active = true
	next.mark_row = next.point_row
	next.mark_column = next.point_column
	return Copy_Mode_Transition{state = next, changed = next != copy_state}, true, {}
}

/* registry_copy_mode_select_pointer maps one viewport cell into local copy state. */
registry_copy_mode_select_pointer :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	copy_state: Copy_Mode_State,
	request: Copy_Pointer_Request,
) -> (transition: Copy_Mode_Transition, ok: bool, failure: Failure_Record) {
	if request.action == .Invalid {
		return {}, false, failure_record(.Copy_Mode, .Invalid_Argument)
	}
	reconciled, reconciled_ok, reconcile_failure := registry_copy_mode_reconcile(
		registry, ref, copy_state,
	)
	if !reconciled_ok do return {}, false, reconcile_failure
	next := reconciled.state
	if request.action == .Extend && !next.mark_present {
		return {}, false, failure_record(.Copy_Mode, .Invalid_Argument)
	}
	state := registry_state(registry)
	session, resolved := registry_resolve(state, ref)
	if !resolved do return {}, false, failure_record(.Copy_Mode, .Stale_Reference)
	scrollback, scroll_result := terminal_emulator.scroll_state(session.record.emulator)
	if scroll_result != .OK do return {}, false, emulator_failure(.Copy_Mode, scroll_result)

	max_row := copy_mode_max_row(scrollback.total_rows)
	local_row := copy_mode_clamp_signed(request.viewport_row, next.viewport_rows - 1)
	point_row := min(next.viewport_top_row, max_row)
	point_row += min(local_row, max_row - point_row)
	point_column := u32(copy_mode_clamp_signed(
		request.column,
		u64(copy_mode_max_column(session.columns)),
	))
	next.point_row = point_row
	next.point_column = point_column
	next.desired_column = point_column

	switch request.action {
	case .Begin:
		next.mark_present = true
		next.selection_active = false
		next.mark_row = point_row
		next.mark_column = point_column
	case .Extend:
		next.selection_active = next.mark_row != point_row || next.mark_column != point_column
	case .Invalid:
	}
	return Copy_Mode_Transition{state = next, changed = next != copy_state}, true, {}
}

/* registry_copy_mode_cancel deactivates selection before completing copy mode. */
registry_copy_mode_cancel :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	copy_state: Copy_Mode_State,
) -> (transition: Copy_Mode_Transition, ok: bool, failure: Failure_Record) {
	reconciled, reconciled_ok, reconcile_failure := registry_copy_mode_reconcile(
		registry, ref, copy_state,
	)
	if !reconciled_ok do return {}, false, reconcile_failure
	next := reconciled.state
	if !next.active do return {}, false, failure_record(.Copy_Mode, .Invalid_Argument)
	if next.selection_active {
		next.selection_active = false
		return Copy_Mode_Transition {
			state = next,
			changed = true,
			selection_deactivated = true,
		}, true, {}
	}
	return Copy_Mode_Transition {
		changed = true,
		completed = true,
		resume_follow_tail = next.follow_tail_on_entry,
	}, true, {}
}

/* registry_copy_mode_done completes copy mode without emitting terminal input. */
registry_copy_mode_done :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	copy_state: Copy_Mode_State,
) -> (transition: Copy_Mode_Transition, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil do return {}, false, registry_access_failure(registry, .Copy_Mode)
	_, resolved := registry_resolve(state, ref)
	if !resolved do return {}, false, failure_record(.Copy_Mode, .Stale_Reference)
	if !copy_state.active do return {}, false, failure_record(.Copy_Mode, .Invalid_Argument)
	return Copy_Mode_Transition {
		changed = true,
		completed = true,
		resume_follow_tail = copy_state.follow_tail_on_entry,
	}, true, {}
}

/* registry_copy_mode_reconcile clamps local state after output, reflow, or eviction. */
registry_copy_mode_reconcile :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	copy_state: Copy_Mode_State,
) -> (transition: Copy_Mode_Transition, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil do return {}, false, registry_access_failure(registry, .Copy_Mode)
	session, resolved := registry_resolve(state, ref)
	if !resolved do return {}, false, failure_record(.Copy_Mode, .Stale_Reference)
	if !copy_state.active do return {}, false, failure_record(.Copy_Mode, .Invalid_Argument)
	scrollback, scroll_result := terminal_emulator.scroll_state(session.record.emulator)
	if scroll_result != .OK do return {}, false, emulator_failure(.Copy_Mode, scroll_result)
	next := copy_mode_reconciled(copy_state, scrollback, session.columns)
	return Copy_Mode_Transition{state = next, changed = next != copy_state}, true, {}
}

/* registry_copy_mode_search performs one bounded literal retained-text search. */
registry_copy_mode_search :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	copy_state: Copy_Mode_State,
	query: string,
	direction: Copy_Search_Direction,
	scratch: []u8,
) -> (observation: Copy_Search_Observation, ok: bool, failure: Failure_Record) {
	if !copy_state.active || len(query) == 0 || !utf8.valid_string(query) ||
	   direction == .Invalid || len(scratch) == 0 {
		return {}, false, failure_record(.Copy_Mode, .Invalid_Argument)
	}
	snapshot, copied, copy_failure := registry_copy_text(
		registry, ref, Text_Request{scope = .Screen, normalized = true}, scratch,
	)
	if !copied do return {}, false, copy_failure
	if snapshot.truncated {
		return {}, false, failure_record(
			.Copy_Mode, .Output_Limit,
			limit = snapshot.limit_bytes,
			actual = snapshot.required_bytes,
		)
	}
	text := string(scratch[:int(snapshot.copied_bytes)])
	start := copy_mode_position_byte_offset(text, copy_state.point_row, copy_state.point_column)
	match := -1
	wrapped := false
	if direction == .Forward {
		match = strings.index(text[start:], query)
		if match >= 0 {
			match += start
		} else if start > 0 {
			match = strings.index(text[:start], query)
			wrapped = match >= 0
		}
	} else {
		match = strings.last_index(text[:start], query)
		if match < 0 && start < len(text) {
			match = strings.last_index(text[start:], query)
			if match >= 0 {
				match += start
				wrapped = true
			}
		}
	}
	next_transition, next_ok, next_failure := registry_copy_mode_reconcile(
		registry, ref, copy_state,
	)
	if !next_ok do return {}, false, next_failure
	next := next_transition.state
	if match >= 0 {
		next.point_row, next.point_column = copy_mode_byte_position(text, match)
		next.desired_column = next.point_column
		scrollback, scroll_ok, scroll_failure := registry_scrollback(registry, ref)
		if !scroll_ok do return {}, false, scroll_failure
		next.viewport_top_row = copy_mode_reveal_point(next, scrollback.total_rows)
	}
	return Copy_Search_Observation {
		state = next,
		found = match >= 0,
		wrapped = wrapped,
		searched_bytes = snapshot.copied_bytes,
	}, true, {}
}

/* registry_copy_mode_copy_selection copies a range without changing local state. */
registry_copy_mode_copy_selection :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	copy_state: Copy_Mode_State,
	output: []u8,
) -> (snapshot: Text_Copy, ok: bool, failure: Failure_Record) {
	if !copy_state.active || !copy_state.mark_present || !copy_state.selection_active {
		return {}, false, failure_record(.Copy_Mode, .Invalid_Argument)
	}
	start_row, start_column := copy_state.mark_row, copy_state.mark_column
	end_row, end_column := copy_state.point_row, copy_state.point_column
	if end_row < start_row || (end_row == start_row && end_column < start_column) {
		start_row, end_row = end_row, start_row
		start_column, end_column = end_column, start_column
	}
	if start_row > u64(max(u32)) || end_row > u64(max(u32)) ||
	   start_column > u32(max(u16)) || end_column > u32(max(u16)) {
		return {}, false, failure_record(.Copy_Mode, .Invalid_Argument)
	}
	return registry_copy_text(
		registry,
		ref,
		Text_Request {
			scope = .History_Range,
			range = Text_Range {
				start_column = u16(start_column),
				start_row = u32(start_row),
				end_column = u16(end_column),
				end_row = u32(end_row),
			},
		},
		output,
	)
}

@(private)
copy_mode_max_row :: proc(total_rows: u64) -> u64 {
	if total_rows == 0 do return 0
	return total_rows - 1
}

@(private)
copy_mode_max_column :: proc(columns: u16) -> u32 {
	if columns == 0 do return 0
	return u32(columns - 1)
}

@(private)
copy_mode_clamp_signed :: proc(value: i64, upper: u64) -> u64 {
	if value <= 0 do return 0
	return min(u64(value), upper)
}

@(private)
copy_mode_sub :: proc(value, amount: u64) -> u64 {
	if amount >= value do return 0
	return value - amount
}

@(private)
copy_mode_clamp_viewport :: proc(top, total_rows, viewport_rows: u64) -> u64 {
	rows := max(viewport_rows, u64(1))
	if total_rows <= rows do return 0
	return min(top, total_rows - rows)
}

@(private)
copy_mode_reconciled :: proc(
	copy_state: Copy_Mode_State,
	scrollback: terminal_emulator.Scroll_State,
	columns: u16,
) -> Copy_Mode_State {
	next := copy_state
	next.viewport_rows = max(scrollback.viewport_rows, u64(1))
	next.point_row = min(next.point_row, copy_mode_max_row(scrollback.total_rows))
	next.point_column = min(next.point_column, copy_mode_max_column(columns))
	next.desired_column = min(next.desired_column, copy_mode_max_column(columns))
	if next.mark_present {
		next.mark_row = min(next.mark_row, copy_mode_max_row(scrollback.total_rows))
		next.mark_column = min(next.mark_column, copy_mode_max_column(columns))
	}
	next.viewport_top_row = copy_mode_clamp_viewport(
		next.viewport_top_row,
		scrollback.total_rows,
		scrollback.viewport_rows,
	)
	next.viewport_top_row = copy_mode_reveal_point(next, scrollback.total_rows)
	return next
}

@(private)
copy_mode_reveal_point :: proc(copy_state: Copy_Mode_State, total_rows: u64) -> u64 {
	top := copy_mode_clamp_viewport(
		copy_state.viewport_top_row,
		total_rows,
		copy_state.viewport_rows,
	)
	rows := max(copy_state.viewport_rows, u64(1))
	if copy_state.point_row < top do top = copy_state.point_row
	if copy_state.point_row >= top + rows do top = copy_state.point_row - (rows - 1)
	return copy_mode_clamp_viewport(top, total_rows, copy_state.viewport_rows)
}

@(private)
copy_mode_position_byte_offset :: proc(text: string, row: u64, column: u32) -> int {
	offset := 0
	current_row: u64
	for current_row < row && offset < len(text) {
		newline := strings.index_byte(text[offset:], '\n')
		if newline < 0 do return len(text)
		offset += newline + 1
		current_row += 1
	}
	current_column: u32
	for current_column < column && offset < len(text) && text[offset] != '\n' {
		_, width := utf8.decode_rune(text[offset:])
		if width <= 0 do break
		offset += width
		current_column += 1
	}
	return offset
}

@(private)
copy_mode_byte_position :: proc(text: string, byte_offset: int) -> (row: u64, column: u32) {
	offset := 0
	limit := min(max(byte_offset, 0), len(text))
	for offset < limit {
		if text[offset] == '\n' {
			row += 1
			column = 0
			offset += 1
			continue
		}
		_, width := utf8.decode_rune(text[offset:])
		if width <= 0 do break
		offset += width
		column += 1
	}
	return
}
