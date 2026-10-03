// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "core:strings"
import "core:unicode/utf8"
import "../interactive_session"
import "../terminal_emulator"

/* registry_route_mouse applies local override, explicit link, and child-reporting precedence. */
registry_route_mouse :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	request: Mouse_Request,
	hyperlink_output: []u8,
) -> (observation: Mouse_Observation, ok: bool, failure: Failure_Record) {
	observation.ref = ref
	state := registry_state(registry)
	if state == nil do return observation, false, registry_access_failure(registry, .Mouse)
	session, resolved := registry_resolve(state, ref)
	if !resolved do return observation, false, failure_record(.Mouse, .Stale_Reference)
	if session.record.lifecycle != .Running || !mouse_request_valid(request) {
		return observation, false, failure_record(.Mouse, .Invalid_Argument)
	}
	mouse_state, mouse_result := terminal_emulator.mouse_state(session.record.emulator)
	if mouse_result != .OK do return observation, false, emulator_failure(.Mouse, mouse_result)
	observation.mouse_tracking = mouse_state.tracking
	if .Shift in request.modifiers {
		observation.route = .Local
		return observation, true, {}
	}
	if request.action == .Press && request.button == .Left && .Control in request.modifiers {
		column, row, positioned := mouse_viewport_cell(session, request.x, request.y)
		if positioned {
			link, linked, link_failure := hyperlink_copy_session(
				session, ref, column, row, hyperlink_output,
			)
			if link_failure.code == .Hyperlink_Rejected do return observation, false, link_failure
			if link_failure.code != .None do return observation, false, link_failure
			if linked {
				observation.route = .Hyperlink
				observation.hyperlink_bytes = link.bytes
				return observation, true, {}
			}
		}
	}
	if !mouse_state.tracking {
		observation.route = .Local
		return observation, true, {}
	}
	action, action_ok := mouse_emulator_action(request.action)
	button, button_ok := mouse_emulator_button(request.button)
	if !action_ok || !button_ok do return observation, false, failure_record(.Mouse, .Invalid_Argument)
	encoded: [MAX_ENCODED_MOUSE_BYTES]u8
	written, encode_result := terminal_emulator.encode_mouse(
		session.record.emulator,
		action,
		button,
		input_emulator_modifiers(request.modifiers),
		request.x,
		request.y,
		encoded[:],
	)
	if encode_result != .OK {
		if encode_result == .Buffer_Too_Small {
			return observation, false, failure_record(.Mouse, .Input_Limit, limit = MAX_ENCODED_MOUSE_BYTES)
		}
		return observation, false, emulator_failure(.Mouse, encode_result)
	}
	observation.route = .Child
	observation.encoded_bytes = u64(written)
	if written == 0 do return observation, true, {}
	queued, process_issue := interactive_session.registry_send(
		&state.interactive, session.record.process.ref, encoded[:written],
	)
	if !queued do return observation, false, mouse_process_failure(process_issue)
	process_record, recorded, record_issue := interactive_session.registry_record(
		&state.interactive, session.record.process.ref,
	)
	if !recorded do return observation, false, mouse_process_failure(record_issue)
	session.record.process = process_record
	observation.queued_bytes = u64(written)
	observation.queue_bytes = process_record.resources.queued_input_bytes
	return observation, true, {}
}

@(private)
mouse_process_failure :: proc(issue: interactive_session.Failure_Record) -> Failure_Record {
	if issue.code == .Input_Limit {
		return failure_record(.Mouse, .Input_Limit, limit = issue.limit, actual = issue.actual)
	}
	return process_failure(.Mouse, issue)
}

/* registry_hyperlink_at copies and validates one inert viewport-cell target. */
registry_hyperlink_at :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	column: u16,
	row: u32,
	output: []u8,
) -> (Hyperlink_Observation, bool, Failure_Record) {
	state := registry_state(registry)
	if state == nil do return {}, false, registry_access_failure(registry, .Hyperlink)
	session, resolved := registry_resolve(state, ref)
	if !resolved do return {}, false, failure_record(.Hyperlink, .Stale_Reference)
	return hyperlink_copy_session(session, ref, column, row, output)
}

@(private)
hyperlink_copy_session :: proc(
	session: ^Session_State,
	ref: Session_Ref,
	column: u16,
	row: u32,
	output: []u8,
) -> (observation: Hyperlink_Observation, ok: bool, failure: Failure_Record) {
	if len(output) > MAX_HYPERLINK_BYTES || column >= session.columns || row >= u32(session.rows) {
		return {}, false, failure_record(.Hyperlink, .Invalid_Argument)
	}
	written, result := terminal_emulator.hyperlink_at(
		session.record.emulator, column, row, output,
	)
	if result == .Buffer_Too_Small {
		return {}, false, failure_record(.Hyperlink, .Input_Limit, limit = MAX_HYPERLINK_BYTES)
	}
	if result != .OK do return {}, false, emulator_failure(.Hyperlink, result)
	if written == 0 do return {}, false, {}
	target := string(output[:written])
	kind, safe := hyperlink_target_kind(target)
	if !safe do return {}, false, failure_record(.Hyperlink, .Hyperlink_Rejected)
	return Hyperlink_Observation {
		ref = ref, kind = kind, column = column, row = row, bytes = u32(written),
	}, true, {}
}

@(private)
hyperlink_target_kind :: proc(target: string) -> (Hyperlink_Target_Kind, bool) {
	if len(target) == 0 || len(target) > MAX_HYPERLINK_BYTES || !utf8.valid_string(target) {
		return {}, false
	}
	for byte in transmute([]u8)target do if byte <= 0x20 || byte == 0x7f do return {}, false
	separator := strings.index_byte(target, ':')
	if separator <= 0 || separator > 16 do return {}, false
	scheme := target[:separator]
	for byte, index in transmute([]u8)scheme {
		letter := (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z')
		if index == 0 && !letter do return {}, false
		if !letter && !(byte >= '0' && byte <= '9') && byte != '+' && byte != '-' && byte != '.' {
			return {}, false
		}
	}
	remainder := target[separator + 1:]
	if strings.equal_fold(scheme, "http") || strings.equal_fold(scheme, "https") {
		if len(remainder) <= 2 || !strings.has_prefix(remainder, "//") do return {}, false
		authority := remainder[2:]
		if len(authority) == 0 || authority[0] == '/' || authority[0] == '?' || authority[0] == '#' {
			return {}, false
		}
		kind := Hyperlink_Target_Kind.HTTP
		if strings.equal_fold(scheme, "https") do kind = .HTTPS
		return kind, true
	}
	if strings.equal_fold(scheme, "mailto") do return .Mailto, len(remainder) > 0
	if strings.equal_fold(scheme, "file") {
		return .File, strings.has_prefix(remainder, "//") && len(remainder) > 2
	}
	return {}, false
}

@(private)
mouse_request_valid :: proc(request: Mouse_Request) -> bool {
	if request.action == .Invalid || !(request.x >= 0 && request.x <= f32(max(u32))) ||
	   !(request.y >= 0 && request.y <= f32(max(u32))) {
		return false
	}
	if request.action == .Motion do return request.button == .None || request.button == .Left ||
		request.button == .Right || request.button == .Middle
	return request.button != .None
}

@(private)
mouse_viewport_cell :: proc(session: ^Session_State, x, y: f32) -> (u16, u32, bool) {
	if session.cell_width_pixels == 0 || session.cell_height_pixels == 0 do return 0, 0, false
	column := u32(x / f32(session.cell_width_pixels))
	row := u32(y / f32(session.cell_height_pixels))
	if column >= u32(session.columns) || row >= u32(session.rows) do return 0, 0, false
	return u16(column), row, true
}

@(private)
mouse_emulator_action :: proc(action: Mouse_Action) -> (terminal_emulator.Mouse_Action, bool) {
	switch action {
	case .Press:   return .Press, true
	case .Release: return .Release, true
	case .Motion:  return .Motion, true
	case .Invalid:
	}
	return {}, false
}

@(private)
mouse_emulator_button :: proc(button: Mouse_Button) -> (terminal_emulator.Mouse_Button, bool) {
	switch button {
	case .None:       return .None, true
	case .Left:       return .Left, true
	case .Right:      return .Right, true
	case .Middle:     return .Middle, true
	case .Wheel_Up:   return .Wheel_Up, true
	case .Wheel_Down: return .Wheel_Down, true
	}
	return {}, false
}
