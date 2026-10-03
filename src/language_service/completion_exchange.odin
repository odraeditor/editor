// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import completion "../completion"
import "base:runtime"
import json "core:encoding/json"

/* Completion_Exchange owns one cancellable protocol request at a time. */
Completion_Exchange :: struct {
	state: rawptr,
}

/* Completion_Request_View borrows one exact queued or sent request body. */
Completion_Request_View :: struct {
	request:       completion.Request,
	session:       Session_Handle,
	binding:       Document_Binding_Handle,
	request_id:    Request_ID,
	table_generation: Request_Generation,
	state:         Request_State,
	deadline_ns:   i64,
	body:          []u8,
}

/* Completion_Exchange_Inspection copies current protocol request authority. */
Completion_Exchange_Inspection :: struct {
	session:          Session_Handle,
	binding:          Document_Binding_Handle,
	request_id:       Request_ID,
	table_generation: Request_Generation,
	state:            Request_State,
	core_request_id:  completion.Request_ID,
	core_generation:  completion.Request_Generation,
	revision:         completion.Document_Revision,
	payload_bytes:    u64,
	latest_failure:   Failure_Context,
}

@(private)
Completion_Exchange_State :: struct {
	session:          Session_Handle,
	binding:          Document_Binding_Handle,
	capabilities:     Capability_Values,
	limits:           Service_Limits,
	deadlines:        Deadline_Policy,
	next_request_id:  i64,
	table_generation: Request_Generation,
	next_batch_id:    completion.Batch_ID,
	next_batch_generation: completion.Batch_Generation,
	request:          completion.Request,
	request_id:       Request_ID,
	request_state:    Request_State,
	deadline_ns:      i64,
	body:             []u8,
	latest_failure:   Failure_Context,
	allocator:        runtime.Allocator,
}

/* completion_exchange_init binds one adapter to an exact service session and document. */
completion_exchange_init :: proc(
	exchange: ^Completion_Exchange,
	session: Session_Handle,
	binding: Document_Binding_Handle,
	capabilities: Capability_Values,
	limits := DEFAULT_LIMITS,
	deadlines := DEFAULT_DEADLINES,
	allocator := context.allocator,
) -> (bool, Failure_Context) {
	if exchange == nil {
		return false, Failure_Context{code = .Invalid_Input}
	}
	exchange^ = {}
	if !session_handle_valid(session) || binding.session != session ||
	   binding.id == Document_Binding_ID(0) || binding.generation == Document_Binding_Generation(0) ||
	   .Completion not_in capabilities.capabilities || !capabilities.completion.available ||
	   !service_limits_valid(limits) || !deadline_policy_valid(deadlines) ||
	   allocator.procedure == nil {
		return false, Failure_Context{code = .Unsupported_Capability, session = session, binding = binding}
	}
	state, allocation_error := new(Completion_Exchange_State, allocator)
	if allocation_error != nil {
		return false, Failure_Context{code = .Allocation, session = session, binding = binding}
	}
	state^ = {
		session = session,
		binding = binding,
		capabilities = capabilities,
		limits = limits,
		deadlines = deadlines,
		next_request_id = 1,
		table_generation = 1,
		next_batch_id = 1,
		next_batch_generation = 1,
		allocator = allocator,
	}
	exchange.state = state
	return true, {}
}

/* completion_exchange_prepare validates synchronization and builds one request body. */
completion_exchange_prepare :: proc(
	exchange: ^Completion_Exchange,
	synchronizer: ^Document_Synchronizer,
	request: completion.Request,
	now_ns: i64,
) -> (Completion_Request_View, bool, Failure_Context) {
	state := completion_exchange_state(exchange)
	if state == nil {
		return {}, false, Failure_Context{code = .Closed}
	}
	request_value := request
	if !completion.request_is_valid(&request_value) ||
	   state.request_state == .Queued || state.request_state == .Sent ||
	   state.request_state == .Cancelling {
		return {}, false, completion_exchange_reject(state, .Invalid_Request)
	}
	descriptor, bound, binding_failure := document_synchronizer_binding(synchronizer, state.binding)
	if !bound {
		state.latest_failure = binding_failure
		return {}, false, binding_failure
	}
	if descriptor.state != .Open || descriptor.handle.session != state.session ||
	   request.scope.document_id != completion.Document_ID(descriptor.document_identity) ||
	   request.scope.buffer_id != completion.Buffer_ID(descriptor.buffer_identity) ||
	   request.scope.document_revision != completion.Document_Revision(descriptor.canonical_revision) ||
	   request.scope.transmitted_revision != completion.Document_Revision(descriptor.transmitted_revision) ||
	   descriptor.transmitted_revision != descriptor.canonical_revision ||
	   request.scope.server_session_id != completion.Server_Session_ID(state.session.id) ||
	   request.scope.server_session_generation != completion.Server_Session_Generation(state.session.generation) ||
	   request.scope.document_binding_id != completion.Document_Binding_ID(state.binding.id) ||
	   request.scope.document_binding_generation != completion.Document_Binding_Generation(state.binding.generation) {
		return {}, false, completion_exchange_reject(state, .Stale_Generation)
	}
	text, text_ok, text_failure := document_synchronizer_text(synchronizer, state.binding)
	if !text_ok {
		state.latest_failure = text_failure
		return {}, false, text_failure
	}
	uri, uri_ok, uri_failure := document_synchronizer_uri(synchronizer, state.binding)
	if !uri_ok {
		state.latest_failure = uri_failure
		return {}, false, uri_failure
	}
	position, positioned, position_failure := byte_offset_to_position(
		text,
		request.cursor_byte,
		descriptor.position_encoding,
	)
	if !positioned {
		state.latest_failure = position_failure
		return {}, false, position_failure
	}
	if state.next_request_id <= 0 || state.table_generation == Request_Generation(0) {
		return {}, false, completion_exchange_reject(state, .Arithmetic_Overflow)
	}
	body, built := completion_request_body(state.next_request_id, uri, position, request, state.allocator)
	if !built {
		return {}, false, completion_exchange_reject(state, .Allocation)
	}
	if u64(len(body)) > state.limits.message_bytes {
		actual := u64(len(body))
		delete(body, state.allocator)
		return {}, false, completion_exchange_resource_reject(
			state,
			.Message_Bytes,
			state.limits.message_bytes,
			actual,
		)
	}
	completion_exchange_release_body(state)
	state.request = request
	state.request_id = {kind = .Integer, integer = state.next_request_id}
	state.next_request_id += 1
	state.request_state = .Queued
	state.deadline_ns = completion_exchange_deadline(now_ns, state.deadlines.request_ns)
	state.body = body
	return completion_exchange_view(state), true, {}
}

/* completion_exchange_send queues the prepared request on the exact process session. */
completion_exchange_send :: proc(
	exchange: ^Completion_Exchange,
	process: ^Process_Session,
) -> (bool, Failure_Context) {
	state := completion_exchange_state(exchange)
	if state == nil do return false, Failure_Context{code = .Closed}
	if state.request_state != .Queued {
		return false, completion_exchange_reject(state, .Invalid_Request)
	}
	matched, handle_failure := process_session_validate_handle(process, state.session)
	if !matched {
		state.latest_failure = handle_failure
		return false, handle_failure
	}
	sent, send_failure := process_session_send_frame(process, state.body)
	if !sent {
		state.latest_failure = send_failure
		return false, send_failure
	}
	state.request_state = .Sent
	return true, {}
}

/* completion_exchange_cancel publishes protocol cancellation and invalidates locally. */
completion_exchange_cancel :: proc(
	exchange: ^Completion_Exchange,
	process: ^Process_Session,
) -> (bool, Failure_Context) {
	state := completion_exchange_state(exchange)
	if state == nil do return false, Failure_Context{code = .Closed}
	if state.request_state != .Queued && state.request_state != .Sent {
		return false, completion_exchange_reject(state, .Invalid_Request)
	}
	if state.request_state == .Sent {
		matched, handle_failure := process_session_validate_handle(process, state.session)
		if !matched {
			state.latest_failure = handle_failure
			return false, handle_failure
		}
		body, built := completion_cancel_body(state.request_id.integer, context.temp_allocator)
		if !built {
			return false, completion_exchange_reject(state, .Allocation)
		}
		sent, send_failure := process_session_send_frame(process, body)
		if !sent {
			state.latest_failure = send_failure
			return false, send_failure
		}
	}
	state.request_state = .Cancelled
	state.deadline_ns = 0
	completion_exchange_release_body(state)
	return true, {}
}

/* completion_exchange_poll expires one active request without blocking. */
completion_exchange_poll :: proc(
	exchange: ^Completion_Exchange,
	now_ns: i64,
) -> (Request_State, bool, Failure_Context) {
	state := completion_exchange_state(exchange)
	if state == nil do return .Invalid, false, Failure_Context{code = .Closed}
	if state.request_state != .Queued && state.request_state != .Sent &&
	   state.request_state != .Cancelling {
		return state.request_state, true, {}
	}
	if now_ns < state.deadline_ns do return state.request_state, true, {}
	failure := completion_exchange_fail_request(state, .Timeout)
	failure.deadline = .Request
	state.latest_failure = failure
	state.request_state = .Timed_Out
	return state.request_state, true, failure
}

/* completion_exchange_fail contains one active transport or provider failure. */
completion_exchange_fail :: proc(
	exchange: ^Completion_Exchange,
	source: Failure_Context,
) -> (bool, Failure_Context) {
	state := completion_exchange_state(exchange)
	if state == nil do return false, Failure_Context{code = .Closed}
	if state.request_state != .Queued && state.request_state != .Sent &&
	   state.request_state != .Cancelling {
		return false, completion_exchange_reject(state, .Invalid_Request)
	}
	failure := source
	if failure.code == .None do failure.code = .Protocol
	failure.session = state.session
	failure.binding = state.binding
	failure.request_id = state.request_id
	state.latest_failure = failure
	state.request_state = .Failed
	state.deadline_ns = 0
	completion_exchange_release_body(state)
	return true, failure
}

/* completion_exchange_view borrows the exact current request and owned body. */
completion_exchange_current :: proc(
	exchange: ^Completion_Exchange,
) -> (Completion_Request_View, bool) {
	state := completion_exchange_state(exchange)
	if state == nil || state.request_state == .Invalid do return {}, false
	return completion_exchange_view(state), true
}

/* completion_exchange_inspect copies current request authority and failure state. */
completion_exchange_inspect :: proc(
	exchange: ^Completion_Exchange,
) -> (Completion_Exchange_Inspection, bool) {
	state := completion_exchange_state(exchange)
	if state == nil do return {}, false
	return {
		session = state.session,
		binding = state.binding,
		request_id = state.request_id,
		table_generation = state.table_generation,
		state = state.request_state,
		core_request_id = state.request.id,
		core_generation = state.request.generation,
		revision = state.request.scope.document_revision,
		payload_bytes = u64(len(state.body)),
		latest_failure = state.latest_failure,
	}, true
}

/* completion_exchange_close releases request storage exactly once. */
completion_exchange_close :: proc(exchange: ^Completion_Exchange) -> bool {
	state := completion_exchange_state(exchange)
	if state == nil do return false
	completion_exchange_release_body(state)
	allocator := state.allocator
	free(state, allocator)
	exchange^ = {}
	return true
}

@(private)
completion_exchange_state :: proc(exchange: ^Completion_Exchange) -> ^Completion_Exchange_State {
	if exchange == nil || exchange.state == nil do return nil
	return cast(^Completion_Exchange_State)exchange.state
}

@(private = "file")
completion_exchange_view :: proc(state: ^Completion_Exchange_State) -> Completion_Request_View {
	return {
		request = state.request,
		session = state.session,
		binding = state.binding,
		request_id = state.request_id,
		table_generation = state.table_generation,
		state = state.request_state,
		deadline_ns = state.deadline_ns,
		body = state.body,
	}
}

@(private)
completion_exchange_release_body :: proc(state: ^Completion_Exchange_State) {
	if state.body != nil do delete(state.body, state.allocator)
	state.body = nil
}

@(private = "file")
completion_request_body :: proc(
	id: i64,
	uri: string,
	position: LSP_Position,
	request: completion.Request,
	allocator: runtime.Allocator,
) -> ([]u8, bool) {
	Text_Document :: struct {uri: string}
	Context :: struct {
		trigger_kind:      u8 `json:"triggerKind"`,
		trigger_character: string `json:"triggerCharacter,omitempty"`,
	}
	Params :: struct {
		text_document: Text_Document `json:"textDocument"`,
		position:      LSP_Position,
		completion_context: Context `json:"context"`,
	}
	Message :: struct {jsonrpc: string, id: i64, method: string, params: Params}
	trigger_kind := u8(1)
	if request.trigger == .Trigger_Character do trigger_kind = 2
	if request.trigger == .Incomplete do trigger_kind = 3
	trigger := request.trigger_character
	message := Message {
		jsonrpc = "2.0",
		id = id,
		method = "textDocument/completion",
		params = {
			text_document = {uri = uri},
			position = position,
			completion_context = {
				trigger_kind = trigger_kind,
				trigger_character = completion.text_view(&trigger),
			},
		},
	}
	body, marshal_error := json.marshal(message, {}, allocator)
	return body, marshal_error == nil
}

@(private = "file")
completion_cancel_body :: proc(id: i64, allocator: runtime.Allocator) -> ([]u8, bool) {
	Params :: struct {id: i64}
	Message :: struct {jsonrpc, method: string, params: Params}
	message := Message{jsonrpc = "2.0", method = "$/cancelRequest", params = {id = id}}
	body, marshal_error := json.marshal(message, {}, allocator)
	return body, marshal_error == nil
}

@(private)
completion_exchange_reject :: proc(
	state: ^Completion_Exchange_State,
	code: Failure_Code,
) -> Failure_Context {
	state.latest_failure = {
		code = code,
		session = state.session,
		binding = state.binding,
		request_id = state.request_id,
	}
	return state.latest_failure
}

@(private = "file")
completion_exchange_resource_reject :: proc(
	state: ^Completion_Exchange_State,
	resource: Resource_Kind,
	limit, actual: u64,
) -> Failure_Context {
	result := completion_exchange_reject(state, .Resource_Limit)
	result.resource = resource
	result.limit = limit
	result.actual = actual
	state.latest_failure = result
	return result
}

@(private)
completion_exchange_fail_request :: proc(
	state: ^Completion_Exchange_State,
	code: Failure_Code,
) -> Failure_Context {
	failure := completion_exchange_reject(state, code)
	state.request_state = .Failed
	state.deadline_ns = 0
	completion_exchange_release_body(state)
	return failure
}

@(private = "file")
completion_exchange_deadline :: proc(now_ns, duration_ns: i64) -> i64 {
	if duration_ns <= 0 || now_ns > max(i64) - duration_ns do return max(i64)
	return now_ns + duration_ns
}
