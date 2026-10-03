// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../bridge"
import "../hosting"
import "../terminal_session"
import base_runtime "base:runtime"
import endian "core:encoding/endian"
import "core:unicode/utf8"

/* Terminal_Capability_Session is one borrowed authority-scoped session descriptor. */
Terminal_Capability_Session :: struct {
	ref:                terminal_session.Session_Ref,
	scope:              bridge.Terminal_Capability_Scope,
	workspace_identity: string,
	project_identity:   string,
	title:              string,
}

/* Terminal_Capability_Context lends explicit sessions and operations for one Racket turn. */
Terminal_Capability_Context :: struct {
	registry:             ^terminal_session.Registry,
	sessions:             []Terminal_Capability_Session,
	authority_generation: u64,
	access:               bridge.Terminal_Capability_Access_Set,
	now_nanoseconds:      i64,
	cancelled:            bool,
}

/* Racket_Terminal_Turn reports copied operation accounting without exposing ownership. */
Racket_Terminal_Turn :: struct {
	calls:        u16,
	delivery_ref: terminal_session.Subscription_Ref,
}

@(private)
Racket_Terminal_Call :: struct {
	ctx:     Terminal_Capability_Context,
	token:   u64,
	calls:   u16,
	failure: bridge.Terminal_Capability_Failure_Code,
	delivery_ref: terminal_session.Subscription_Ref,
}

/* racket_terminal_turn lends one exact bounded terminal authority set to Racket. */
racket_terminal_turn :: proc(
	racket_runtime: ^hosting.Runtime,
	capability: Terminal_Capability_Context,
	scenario: i32,
) -> (Racket_Terminal_Turn, bool, bridge.Terminal_Capability_Failure_Code) {
	if racket_runtime == nil || capability.registry == nil ||
	   capability.authority_generation == 0 || len(capability.sessions) > terminal_session.MAX_SESSIONS ||
	   !terminal_capability_sessions_valid(capability.sessions) {
		return {}, false, .Invalid
	}
	token := capability.authority_generation ~ (u64(len(capability.sessions)) << 32)
	if token == 0 do token = capability.authority_generation
	call := Racket_Terminal_Call{ctx = capability, token = token}
	executed, _ := hosting.runtime_terminal_probe(
		racket_runtime, scenario, token, racket_terminal_callback, &call,
	)
	if !executed {
		turn := Racket_Terminal_Turn{calls = call.calls, delivery_ref = call.delivery_ref}
		if call.failure != .None do return turn, false, call.failure
		return turn, false, .Unavailable
	}
	turn := Racket_Terminal_Turn{calls = call.calls, delivery_ref = call.delivery_ref}
	if call.failure != .None do return turn, false, call.failure
	return turn, true, .None
}

/* racket_terminal_delivery_turn runs one bounded event subscriber on the Racket owner thread. */
racket_terminal_delivery_turn :: proc(
	racket_runtime: ^hosting.Runtime,
	capability: Terminal_Capability_Context,
) -> (Racket_Terminal_Turn, bool, bridge.Terminal_Capability_Failure_Code) {
	return racket_terminal_turn(racket_runtime, capability, 1)
}

@(private)
racket_terminal_callback :: proc "c" (
	user_data: rawptr,
	kind: hosting.Scoped_Capability_Kind,
	generation, token, domain_context: u64,
	operation: i32,
	arg0, arg1: u64,
	input: ^u8,
	input_length: u64,
	output: ^u8,
	output_capacity: u64,
	output_length, value: ^u64,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	context = base_runtime.default_context()
	call := (^Racket_Terminal_Call)(user_data)
	if call == nil || kind != .Terminal || generation == 0 || token != call.token ||
	   domain_context != 0 || output_length == nil || value == nil || failure_code == nil ||
	   limit == nil || actual == nil || input_length > u64(max(int)) ||
	   output_capacity > u64(max(int)) {
		return 2
	}
	output_length^ = 0
	value^ = 0
	failure_code^ = 0
	limit^ = 0
	actual^ = 0
	if call.ctx.cancelled {
		return racket_terminal_reject(call, .Cancelled, failure_code, limit, actual)
	}
	if call.calls >= 64 {
		return racket_terminal_reject(call, .Resource_Limited, failure_code, limit, actual, 64, u64(call.calls) + 1)
	}
	call.calls += 1
	input_bytes: []u8
	if input_length > 0 {
		if input == nil do return 2
		input_bytes = ([^]u8)(input)[:int(input_length)]
	}
	destination: []u8
	if output_capacity > 0 {
		if output == nil do return 2
		destination = ([^]u8)(output)[:int(output_capacity)]
	}
	op := bridge.Terminal_Capability_Operation(operation)
	switch op {
	case .Sessions:
		if arg0 != 0 || arg1 != 0 || input_length != 0 ||
		   .Inspect not_in call.ctx.access {
			return racket_terminal_denied(call, op, failure_code, limit, actual)
		}
		written, encoded, failure := racket_terminal_encode_sessions(destination, &call.ctx)
		if !encoded do return racket_terminal_failure(call, failure, failure_code, limit, actual)
		output_length^ = written
		return 0
	case .Session_State:
		if input_length != 0 || .Inspect not_in call.ctx.access do return racket_terminal_denied(call, op, failure_code, limit, actual)
		written, encoded, failure := racket_terminal_encode_session(destination, &call.ctx, terminal_ref(arg0, arg1))
		if !encoded do return racket_terminal_failure(call, failure, failure_code, limit, actual)
		output_length^ = written
		return 0
	case .Visible_Text, .Scrollback:
		if .Inspect not_in call.ctx.access do return racket_terminal_denied(call, op, failure_code, limit, actual)
		written, copied, failure := racket_terminal_copy_text(
			destination, &call.ctx, terminal_ref(arg0, arg1), op, input_bytes,
		)
		if !copied do return racket_terminal_failure(call, failure, failure_code, limit, actual)
		output_length^ = written
		return 0
	case .Send_Text:
		if output_capacity != 0 || .Input not_in call.ctx.access do return racket_terminal_denied(call, op, failure_code, limit, actual)
		if input_length == 0 || input_length > terminal_session.MAX_INPUT_TEXT_BYTES {
			return racket_terminal_reject(call, .Invalid, failure_code, limit, actual,
				terminal_session.MAX_INPUT_TEXT_BYTES, input_length)
		}
		ref, authorized := terminal_capability_ref(&call.ctx, terminal_ref(arg0, arg1))
		if !authorized do return racket_terminal_reject(call, .Stale, failure_code, limit, actual)
		_, queued, session_failure := terminal_session.registry_send_input(
			call.ctx.registry, ref,
			{kind = .Text, action = .Press, text = string(input_bytes), source = .Ordinary, repeat_count = 1},
		)
		if !queued do return racket_terminal_session_failure(call, session_failure, failure_code, limit, actual)
		return 0
	case .Send_Key:
		if output_capacity != 0 || input_length < bridge.TERMINAL_KEY_RECORD_BYTES ||
		   .Input not_in call.ctx.access {
			return racket_terminal_denied(call, op, failure_code, limit, actual)
		}
		ref, authorized := terminal_capability_ref(&call.ctx, terminal_ref(arg0, arg1))
		if !authorized do return racket_terminal_reject(call, .Stale, failure_code, limit, actual)
		request, decoded := racket_terminal_decode_key(input_bytes)
		if !decoded do return racket_terminal_reject(call, .Invalid, failure_code, limit, actual)
		_, queued, session_failure := terminal_session.registry_send_input(call.ctx.registry, ref, request)
		if !queued do return racket_terminal_session_failure(call, session_failure, failure_code, limit, actual)
		return 0
	case .Terminate:
		if input_length != 0 || output_capacity != 0 || .Terminate not_in call.ctx.access do return racket_terminal_denied(call, op, failure_code, limit, actual)
		ref, authorized := terminal_capability_ref(&call.ctx, terminal_ref(arg0, arg1))
		if !authorized do return racket_terminal_reject(call, .Stale, failure_code, limit, actual)
		terminated, session_failure := terminal_session.registry_request_terminate(
			call.ctx.registry, ref, call.ctx.now_nanoseconds,
		)
		if !terminated do return racket_terminal_session_failure(call, session_failure, failure_code, limit, actual)
		return 0
	case .Subscribe:
		if .Subscribe not_in call.ctx.access do return racket_terminal_denied(call, op, failure_code, limit, actual)
		if output_capacity != 16 do return 2
		session_refs: [terminal_session.MAX_SESSIONS]terminal_session.Session_Ref
		definition, decoded := racket_terminal_decode_subscription(input_bytes, &call.ctx, &session_refs)
		if !decoded do return racket_terminal_reject(call, .Invalid, failure_code, limit, actual)
		record, subscribed, session_failure := terminal_session.registry_subscribe(call.ctx.registry, definition)
		if !subscribed do return racket_terminal_session_failure(call, session_failure, failure_code, limit, actual)
		write_terminal_u64(destination, 0, u64(record.ref.id))
		write_terminal_u64(destination, 8, u64(record.ref.generation))
		output_length^ = 16
		return 0
	case .Unsubscribe:
		if .Subscribe not_in call.ctx.access || input_length != 0 || output_capacity != 0 {
			return racket_terminal_denied(call, op, failure_code, limit, actual)
		}
		closed, session_failure := terminal_session.registry_unsubscribe(
			call.ctx.registry,
			{id = terminal_session.Subscription_ID(u32(arg0)), generation = terminal_session.Subscription_Generation(u32(arg1))},
		)
		if !closed do return racket_terminal_session_failure(call, session_failure, failure_code, limit, actual)
		return 0
	case .Delivery_Next:
		if .Subscribe not_in call.ctx.access || input_length != 0 || arg0 != 0 || arg1 != 0 do return 2
		record, pending, session_failure := terminal_session.registry_event_next_subscription(call.ctx.registry)
		if session_failure.code != .None do return racket_terminal_session_failure(call, session_failure, failure_code, limit, actual)
		if !pending do return 0
		call.delivery_ref = record.ref
		written, encoded := racket_terminal_encode_subscription_record(destination, record)
		if !encoded do return racket_terminal_reject(call, .Resource_Limited, failure_code, limit, actual,
			bridge.TERMINAL_SUBSCRIPTION_RECORD_BYTES + terminal_session.MAX_EVENT_PROVIDER_BYTES, output_capacity)
		output_length^ = written
		return 0
	case .Delivery_Snapshot:
		if .Subscribe not_in call.ctx.access || input_length != 0 do return 2
		written, encoded, session_failure := racket_terminal_encode_event_batch(
			destination, call.ctx.registry,
			{id = terminal_session.Subscription_ID(u32(arg0)), generation = terminal_session.Subscription_Generation(u32(arg1))},
		)
		if !encoded do return racket_terminal_session_failure(call, session_failure, failure_code, limit, actual)
		output_length^ = written
		return 0
	case .Delivery_Complete:
		if .Subscribe not_in call.ctx.access || output_capacity != 0 do return 2
		batch, decoded := racket_terminal_decode_ack(input_bytes)
		if !decoded do return racket_terminal_reject(call, .Invalid, failure_code, limit, actual)
		acked, session_failure := terminal_session.registry_event_ack(call.ctx.registry, batch)
		if !acked do return racket_terminal_session_failure(call, session_failure, failure_code, limit, actual)
		return 0
	case .Delivery_Reject:
		if .Subscribe not_in call.ctx.access || input_length != 0 || output_capacity != 0 do return 2
		rejected, session_failure := terminal_session.registry_event_reject(
			call.ctx.registry,
			{id = terminal_session.Subscription_ID(u32(arg0)), generation = terminal_session.Subscription_Generation(u32(arg1))},
			{stage = .Process, code = .Event_Limit},
		)
		if !rejected do return racket_terminal_session_failure(call, session_failure, failure_code, limit, actual)
		return 0
	}
	return 2
}

@(private)
terminal_capability_sessions_valid :: proc(sessions: []Terminal_Capability_Session) -> bool {
	for session, index in sessions {
		if session.ref.id == 0 || session.ref.generation == 0 || session.scope == .Invalid ||
		   (session.scope == .Workspace && len(session.workspace_identity) == 0) ||
		   (session.scope == .Instance && len(session.workspace_identity) != 0) {
			return false
		}
		for previous in sessions[:index] {
			if previous.ref == session.ref do return false
		}
	}
	return true
}

@(private)
terminal_ref :: proc(id, generation: u64) -> terminal_session.Session_Ref {
	if id > u64(max(u32)) || generation > u64(max(u32)) do return {}
	return {id = terminal_session.Session_ID(u32(id)), generation = terminal_session.Session_Generation(u32(generation))}
}

@(private)
terminal_capability_ref :: proc(
	ctx: ^Terminal_Capability_Context,
	requested: terminal_session.Session_Ref,
) -> (terminal_session.Session_Ref, bool) {
	if requested.id == 0 || requested.generation == 0 do return {}, false
	for session in ctx.sessions {
		if session.ref == requested do return requested, true
	}
	return {}, false
}

@(private)
racket_terminal_encode_sessions :: proc(
	destination: []u8,
	ctx: ^Terminal_Capability_Context,
) -> (u64, bool, terminal_session.Failure_Record) {
	minimum := bridge.TERMINAL_SESSIONS_HEADER_BYTES + u64(len(ctx.sessions)) * bridge.TERMINAL_SESSION_RECORD_BYTES
	if minimum > u64(len(destination)) {
		return 0, false, {code = .Projection_Limit, limit = minimum, actual = u64(len(destination))}
	}
	for &byte in destination do byte = 0
	write_terminal_u64(destination, 0, u64(len(ctx.sessions)))
	cursor := minimum
	for descriptor, index in ctx.sessions {
		record, current, failure := terminal_session.registry_record(ctx.registry, descriptor.ref)
		if !current do return 0, false, failure
		encoded, next := racket_terminal_write_session(
			destination, int(bridge.TERMINAL_SESSIONS_HEADER_BYTES + u64(index) * bridge.TERMINAL_SESSION_RECORD_BYTES),
			cursor, record, descriptor,
		)
		if !encoded do return 0, false, {code = .Projection_Limit, limit = cursor, actual = u64(len(destination))}
		cursor = next
	}
	return cursor, true, {}
}

@(private)
racket_terminal_encode_session :: proc(
	destination: []u8,
	ctx: ^Terminal_Capability_Context,
	requested: terminal_session.Session_Ref,
) -> (u64, bool, terminal_session.Failure_Record) {
	ref, authorized := terminal_capability_ref(ctx, requested)
	if !authorized do return 0, false, {code = .Stale_Reference}
	descriptor := terminal_capability_descriptor(ctx.sessions, ref)
	record, current, failure := terminal_session.registry_record(ctx.registry, ref)
	if !current do return 0, false, failure
	if u64(len(destination)) < bridge.TERMINAL_SESSION_RECORD_BYTES {
		return 0, false, {code = .Projection_Limit, limit = bridge.TERMINAL_SESSION_RECORD_BYTES, actual = u64(len(destination))}
	}
	for &byte in destination do byte = 0
	encoded, cursor := racket_terminal_write_session(
		destination, 0, bridge.TERMINAL_SESSION_RECORD_BYTES, record, descriptor,
	)
	if !encoded do return 0, false, {code = .Projection_Limit, limit = cursor, actual = u64(len(destination))}
	return cursor, true, {}
}

@(private)
terminal_capability_descriptor :: proc(
	sessions: []Terminal_Capability_Session,
	ref: terminal_session.Session_Ref,
) -> Terminal_Capability_Session {
	for session in sessions do if session.ref == ref do return session
	return {}
}

@(private)
racket_terminal_write_session :: proc(
	destination: []u8,
	offset: int,
	cursor: u64,
	record: terminal_session.Session_Record,
	descriptor: Terminal_Capability_Session,
) -> (bool, u64) {
	process := record.process
	name := process.name.bytes[:process.name.length]
	directory := process.working_context.directory[:process.working_context.length]
	owner_label := process.owner.label[:process.owner.length]
	strings := [5]string{string(name), descriptor.workspace_identity, descriptor.project_identity, string(directory), descriptor.title}
	owner := string(owner_label)
	values := [10]u64{
		u64(record.ref.id), u64(record.ref.generation), terminal_lifecycle_code(record.lifecycle),
		u64(descriptor.scope), record.render_revision, u64(process.exit_status.kind),
		u64(u32(process.exit_status.value)), u64(process.owner.kind), cursor, u64(len(strings[0])),
	}
	for value, index in values do write_terminal_u64(destination, offset + index * 8, value)
	current := cursor
	for text, index in strings {
		if current + u64(len(text)) > u64(len(destination)) do return false, current + u64(len(text))
		copy(destination[int(current):], transmute([]u8)text)
		if index > 0 {
			write_terminal_u64(destination, offset + 64 + index * 16, current)
			write_terminal_u64(destination, offset + 72 + index * 16, u64(len(text)))
		}
		current += u64(len(text))
	}
	if current + u64(len(owner)) > u64(len(destination)) do return false, current + u64(len(owner))
	copy(destination[int(current):], transmute([]u8)owner)
	write_terminal_u64(destination, offset + 144, current)
	write_terminal_u64(destination, offset + 152, u64(len(owner)))
	current += u64(len(owner))
	return true, current
}

@(private)
terminal_lifecycle_code :: proc(value: terminal_session.Lifecycle) -> u64 {
	switch value {
	case .Running: return 1
	case .Exited: return 2
	case .Failed: return 3
	case .Invalid, .Closed: return 3
	}
	return 3
}

@(private)
racket_terminal_copy_text :: proc(
	destination: []u8,
	ctx: ^Terminal_Capability_Context,
	requested: terminal_session.Session_Ref,
	operation: bridge.Terminal_Capability_Operation,
	input: []u8,
) -> (u64, bool, terminal_session.Failure_Record) {
	ref, authorized := terminal_capability_ref(ctx, requested)
	if !authorized do return 0, false, {code = .Stale_Reference}
	if u64(len(destination)) < bridge.TERMINAL_SNAPSHOT_RECORD_BYTES {
		return 0, false, {code = .Projection_Limit, limit = bridge.TERMINAL_SNAPSHOT_RECORD_BYTES, actual = u64(len(destination))}
	}
	first, count := u64(0), u64(1)
	request := terminal_session.Text_Request{scope = .Screen, normalized = true}
	if operation == .Scrollback {
		if len(input) != 16 do return 0, false, {code = .Invalid_Argument}
		first_value, first_ok := endian.get_u64(input, .Little)
		count_value, count_ok := endian.get_u64(input[8:], .Little)
		if !first_ok || !count_ok || count_value == 0 || first_value > u64(max(u32)) ||
		   count_value - 1 > u64(max(u32)) - first_value {
			return 0, false, {code = .Invalid_Argument}
		}
		first, count = first_value, count_value
		request.scope = .History_Range
		request.range = {start_row = u32(first), end_column = max(u16), end_row = u32(first + count - 1)}
	} else {
		if len(input) != 0 do return 0, false, {code = .Invalid_Argument}
		scrollback, observed, failure := terminal_session.registry_scrollback(ctx.registry, ref)
		if !observed do return 0, false, failure
		count = max(scrollback.viewport_rows, 1)
	}
	text := destination[int(bridge.TERMINAL_SNAPSHOT_RECORD_BYTES):]
	snapshot, copied, failure := terminal_session.registry_copy_text(ctx.registry, ref, request, text)
	if !copied do return 0, false, failure
	record, current, record_failure := terminal_session.registry_record(ctx.registry, ref)
	if !current do return 0, false, record_failure
	values := [9]u64{
		u64(ref.id), u64(ref.generation), record.render_revision, first, count,
		0, u64(snapshot.truncated), bridge.TERMINAL_SNAPSHOT_RECORD_BYTES, snapshot.copied_bytes,
	}
	for value, index in values do write_terminal_u64(destination, index * 8, value)
	return bridge.TERMINAL_SNAPSHOT_RECORD_BYTES + snapshot.copied_bytes, true, {}
}

@(private)
racket_terminal_decode_key :: proc(input: []u8) -> (terminal_session.Input_Request, bool) {
	if len(input) < int(bridge.TERMINAL_KEY_RECORD_BYTES) do return {}, false
	values: [6]u64
	for &value, index in values {
		ok: bool
		value, ok = endian.get_u64(input[index * 8:], .Little)
		if !ok do return {}, false
	}
	text_offset, text_length := values[4], values[5]
	if text_offset < bridge.TERMINAL_KEY_RECORD_BYTES || text_offset + text_length > u64(len(input)) ||
	   values[0] > u64(terminal_session.Input_Key.Space) || values[1] > u64(terminal_session.Input_Action.Repeat) ||
	   values[2] > u64(max(u8)) || values[3] > terminal_session.MAX_INPUT_REPEAT_COUNT {
		return {}, false
	}
	modifiers: terminal_session.Input_Modifiers
	if values[2] & 1 != 0 do modifiers += {.Shift}
	if values[2] & 2 != 0 do modifiers += {.Control}
	if values[2] & 4 != 0 do modifiers += {.Alt}
	if values[2] & 8 != 0 do modifiers += {.Super}
	if values[2] > 15 do return {}, false
	request := terminal_session.Input_Request {
		kind = .Key,
		key = terminal_session.Input_Key(values[0]),
		action = terminal_session.Input_Action(values[1]),
		modifiers = modifiers,
		text = string(input[int(text_offset):int(text_offset + text_length)]),
		source = .Ordinary,
		repeat_count = u16(values[3]),
	}
	return request, true
}

@(private)
racket_terminal_decode_subscription :: proc(
	input: []u8,
	ctx: ^Terminal_Capability_Context,
	refs: ^[terminal_session.MAX_SESSIONS]terminal_session.Session_Ref,
) -> (terminal_session.Subscription_Definition, bool) {
	if len(input) < int(bridge.TERMINAL_SUBSCRIPTION_HEADER_BYTES) do return {}, false
	values: [10]u64
	for &value, index in values {
		ok: bool
		value, ok = endian.get_u64(input[index * 8:], .Little)
		if !ok do return {}, false
	}
	session_count, kind_mask, raw_output := values[0], values[1], values[2]
	handler_offset, handler_length, refs_offset := values[7], values[8], values[9]
	admitted_kind_mask := (u64(1) << (u64(terminal_session.Event_Kind.Overflow) + 1)) - 2
	if session_count == 0 || session_count > terminal_session.MAX_SESSIONS || raw_output > 1 ||
	   kind_mask == 0 || kind_mask & ~admitted_kind_mask != 0 ||
	   values[3] == 0 || values[3] > terminal_session.MAX_EVENT_BATCH_ENTRIES ||
	   values[4] == 0 || values[4] > terminal_session.MAX_EVENT_BATCH_BYTES ||
	   values[5] == 0 || values[5] > terminal_session.MAX_SUBSCRIBER_TURN_MILLISECONDS ||
	   values[6] == 0 || values[6] > terminal_session.MAX_SUBSCRIBER_TEMPORARY_BYTES ||
	   refs_offset != bridge.TERMINAL_SUBSCRIPTION_HEADER_BYTES ||
	   refs_offset + session_count * 16 > u64(len(input)) ||
	   handler_offset < refs_offset + session_count * 16 ||
	   handler_offset + handler_length > u64(len(input)) || handler_length == 0 ||
	   handler_length > terminal_session.MAX_EVENT_PROVIDER_BYTES {
		return {}, false
	}
	handler_bytes := input[int(handler_offset):int(handler_offset + handler_length)]
	if !utf8.valid_string(string(handler_bytes)) do return {}, false
	for byte in handler_bytes do if byte == 0 do return {}, false
	for index in 0 ..< int(session_count) {
		offset := int(refs_offset) + index * 16
		id, id_ok := endian.get_u64(input[offset:], .Little)
		generation, generation_ok := endian.get_u64(input[offset + 8:], .Little)
		if !id_ok || !generation_ok do return {}, false
		ref, authorized := terminal_capability_ref(ctx, terminal_ref(id, generation))
		if !authorized do return {}, false
		refs[index] = ref
	}
	kinds: terminal_session.Event_Kind_Set
	for value := terminal_session.Event_Kind.Prompt_Boundary;
	    value <= .Overflow;
	    value = terminal_session.Event_Kind(u8(value) + 1) {
		if kind_mask & (u64(1) << u64(value)) != 0 do kinds += {value}
	}
	return terminal_session.Subscription_Definition {
		sessions = refs[:int(session_count)],
		kinds = kinds,
		raw_output = raw_output == 1,
		handler = string(handler_bytes),
		batch_events = u16(values[3]),
		batch_bytes = values[4],
		turn_milliseconds = u16(values[5]),
		temporary_memory_bytes = values[6],
	}, true
}

@(private)
racket_terminal_encode_subscription_record :: proc(
	destination: []u8,
	record: terminal_session.Subscription_Record,
) -> (u64, bool) {
	required := bridge.TERMINAL_SUBSCRIPTION_RECORD_BYTES + u64(record.handler.length)
	if required > u64(len(destination)) do return required, false
	values := [9]u64 {
		u64(record.ref.id), u64(record.ref.generation), u64(record.session_count),
		bridge.TERMINAL_SUBSCRIPTION_RECORD_BYTES, u64(record.handler.length),
		u64(record.batch_events), record.batch_bytes, u64(record.turn_milliseconds),
		record.temporary_memory_bytes,
	}
	for value, index in values do write_terminal_u64(destination, index * 8, value)
	handler := record.handler
	copy(destination[int(bridge.TERMINAL_SUBSCRIPTION_RECORD_BYTES):], handler.bytes[:handler.length])
	return required, true
}

@(private)
racket_terminal_encode_event_batch :: proc(
	destination: []u8,
	registry: ^terminal_session.Registry,
	ref: terminal_session.Subscription_Ref,
) -> (u64, bool, terminal_session.Failure_Record) {
	reserved := bridge.TERMINAL_EVENT_BATCH_HEADER_BYTES +
		u64(terminal_session.MAX_EVENT_BATCH_ENTRIES) * bridge.TERMINAL_EVENT_RECORD_BYTES +
		u64(terminal_session.MAX_SESSIONS) * bridge.TERMINAL_EVENT_WATERMARK_RECORD_BYTES
	if reserved + terminal_session.MAX_EVENT_BATCH_BYTES > u64(len(destination)) {
		return 0, false, {code = .Projection_Limit, limit = reserved + terminal_session.MAX_EVENT_BATCH_BYTES, actual = u64(len(destination))}
	}
	events: [terminal_session.MAX_EVENT_BATCH_ENTRIES]terminal_session.Event_Record
	batch, copied, failure := terminal_session.registry_event_snapshot(
		registry, ref, events[:], destination[int(reserved):int(reserved + terminal_session.MAX_EVENT_BATCH_BYTES)],
	)
	if !copied do return 0, false, failure
	values := [5]u64 {
		u64(ref.id), u64(ref.generation), u64(batch.event_count), batch.payload_bytes, u64(batch.session_count),
	}
	for value, index in values do write_terminal_u64(destination, index * 8, value)
	watermark_base := bridge.TERMINAL_EVENT_BATCH_HEADER_BYTES + u64(batch.event_count) * bridge.TERMINAL_EVENT_RECORD_BYTES
	for index in 0 ..< int(batch.session_count) {
		offset := int(watermark_base + u64(index) * bridge.TERMINAL_EVENT_WATERMARK_RECORD_BYTES)
		write_terminal_u64(destination, offset, u64(batch.sessions[index].id))
		write_terminal_u64(destination, offset + 8, u64(batch.sessions[index].generation))
		write_terminal_u64(destination, offset + 16, batch.cursors[index])
	}
	cursor := reserved + batch.payload_bytes
	payload_cursor: u64
	for event, index in batch.events[:batch.event_count] {
		provider_record := event.provider
		provider := provider_record.bytes[:provider_record.length]
		if cursor + u64(len(provider)) > u64(len(destination)) do return 0, false, {code = .Projection_Limit}
		copy(destination[int(cursor):], provider)
		offset := int(bridge.TERMINAL_EVENT_BATCH_HEADER_BYTES + u64(index) * bridge.TERMINAL_EVENT_RECORD_BYTES)
		event_values := [14]u64 {
			u64(event.ref.id), u64(event.ref.generation), event.sequence, u64(event.kind),
			cursor, u64(len(provider)), event.values[0], event.values[1], event.values[2], event.values[3],
			u64(u32(event.signed_value)), u64(event.flags), reserved + payload_cursor, u64(len(event.payload)),
		}
		for value, value_index in event_values do write_terminal_u64(destination, offset + value_index * 8, value)
		cursor += u64(len(provider))
		payload_cursor += u64(len(event.payload))
	}
	return cursor, true, {}
}

@(private)
racket_terminal_decode_ack :: proc(input: []u8) -> (terminal_session.Event_Batch, bool) {
	if len(input) < 24 do return {}, false
	id, id_ok := endian.get_u64(input, .Little)
	generation, generation_ok := endian.get_u64(input[8:], .Little)
	count, count_ok := endian.get_u64(input[16:], .Little)
	if !id_ok || !generation_ok || !count_ok || count > terminal_session.MAX_SESSIONS ||
	   24 + count * bridge.TERMINAL_EVENT_WATERMARK_RECORD_BYTES != u64(len(input)) {
		return {}, false
	}
	batch := terminal_session.Event_Batch {
		subscription = {id = terminal_session.Subscription_ID(u32(id)), generation = terminal_session.Subscription_Generation(u32(generation))},
		session_count = u8(count),
	}
	for index in 0 ..< int(count) {
		offset := 24 + index * int(bridge.TERMINAL_EVENT_WATERMARK_RECORD_BYTES)
		session_id, _ := endian.get_u64(input[offset:], .Little)
		session_generation, _ := endian.get_u64(input[offset + 8:], .Little)
		cursor, _ := endian.get_u64(input[offset + 16:], .Little)
		batch.sessions[index] = terminal_ref(session_id, session_generation)
		batch.cursors[index] = cursor
	}
	return batch, true
}

@(private)
racket_terminal_denied :: proc(
	call: ^Racket_Terminal_Call,
	operation: bridge.Terminal_Capability_Operation,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	_ = operation
	return racket_terminal_reject(call, .Denied, failure_code, limit, actual)
}

@(private)
racket_terminal_failure :: proc(
	call: ^Racket_Terminal_Call,
	failure: terminal_session.Failure_Record,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	return racket_terminal_session_failure(call, failure, failure_code, limit, actual)
}

@(private)
racket_terminal_session_failure :: proc(
	call: ^Racket_Terminal_Call,
	failure: terminal_session.Failure_Record,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	code: bridge.Terminal_Capability_Failure_Code
	switch failure.code {
	case .Stale_Reference: code = .Stale
	case .Capacity, .Allocation, .Input_Limit, .Output_Limit, .Projection_Limit,
	     .Event_Limit, .Subscriber_Limit:
		code = .Resource_Limited
	case .Process, .Emulator, .Cleanup: code = .Unavailable
	case .None, .Invalid_Argument, .Paste_Rejected, .Navigation_Unavailable,
	     .Hyperlink_Rejected:
		code = .Invalid
	}
	return racket_terminal_reject(call, code, failure_code, limit, actual, failure.limit, failure.actual)
}

@(private)
racket_terminal_reject :: proc(
	call: ^Racket_Terminal_Call,
	code: bridge.Terminal_Capability_Failure_Code,
	failure_code: ^u32,
	limit, actual: ^u64,
	rejected_limit: u64 = 0,
	rejected_actual: u64 = 0,
) -> i32 {
	call.failure = code
	failure_code^ = u32(code)
	limit^ = rejected_limit
	actual^ = rejected_actual
	return 1
}

@(private)
write_terminal_u64 :: proc(destination: []u8, offset: int, value: u64) {
	assert(endian.put_u64(destination[offset:], .Little, value))
}
