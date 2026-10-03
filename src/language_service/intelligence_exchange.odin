// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import "base:runtime"
import json "core:encoding/json"

/* Intelligence_Exchange owns one cancellable read-only query at a time. */
Intelligence_Exchange :: struct {
	state: rawptr,
}

/* Intelligence_Request_View borrows one exact queued or sent request body. */
Intelligence_Request_View :: struct {
	request:          Intelligence_Request,
	request_id:       Request_ID,
	table_generation: Request_Generation,
	state:            Request_State,
	deadline_ns:      i64,
	body:             []u8,
}

/* Intelligence_Exchange_Inspection copies current request authority and failure. */
Intelligence_Exchange_Inspection :: struct {
	session:           Session_Handle,
	binding:           Document_Binding_Handle,
	request_id:        Request_ID,
	table_generation:  Request_Generation,
	state:             Request_State,
	query_kind:        Intelligence_Query_Kind,
	request_generation: Intelligence_Request_Generation,
	result_generation: Intelligence_Result_Generation,
	payload_bytes:     u64,
	latest_failure:    Failure_Context,
}

@(private)
Intelligence_Exchange_State :: struct {
	session:            Session_Handle,
	binding:            Document_Binding_Handle,
	capabilities:       Capability_Values,
	limits:             Service_Limits,
	deadlines:          Deadline_Policy,
	next_request_id:    i64,
	table_generation:   Request_Generation,
	next_result_generation: Intelligence_Result_Generation,
	request:            Intelligence_Request,
	request_id:         Request_ID,
	request_state:      Request_State,
	deadline_ns:        i64,
	body:               []u8,
	semantic_data:      [dynamic]u32,
	semantic_result_id: Semantic_Result_ID,
	latest_failure:     Failure_Context,
	allocator:          runtime.Allocator,
}

/* intelligence_exchange_init binds one adapter to an exact session and document. */
intelligence_exchange_init :: proc(
	exchange: ^Intelligence_Exchange,
	session: Session_Handle,
	binding: Document_Binding_Handle,
	capabilities: Capability_Values,
	limits := DEFAULT_LIMITS,
	deadlines := DEFAULT_DEADLINES,
	allocator := context.allocator,
) -> (bool, Failure_Context) {
	if exchange == nil do return false, Failure_Context{code = .Invalid_Input}
	exchange^ = {}
	if !session_handle_valid(session) || binding.session != session ||
	   binding.id == Document_Binding_ID(0) || binding.generation == Document_Binding_Generation(0) ||
	   !service_limits_valid(limits) || !deadline_policy_valid(deadlines) ||
	   allocator.procedure == nil {
		return false, Failure_Context{code = .Invalid_Input, session = session, binding = binding}
	}
	state, allocation_error := new(Intelligence_Exchange_State, allocator)
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
		next_result_generation = 1,
		allocator = allocator,
	}
	exchange.state = state
	return true, {}
}

/* intelligence_exchange_prepare validates capability and synchronization before encoding. */
intelligence_exchange_prepare :: proc(
	exchange: ^Intelligence_Exchange,
	synchronizer: ^Document_Synchronizer,
	request: Intelligence_Request,
	now_ns: i64,
) -> (Intelligence_Request_View, bool, Failure_Context) {
	state := intelligence_exchange_state(exchange)
	if state == nil do return {}, false, Failure_Context{code = .Closed}
	request_value := request
	if !intelligence_request_is_valid(&request_value) ||
	   state.request_state == .Queued || state.request_state == .Sent ||
	   state.request_state == .Cancelling {
		return {}, false, intelligence_exchange_reject(state, .Invalid_Request)
	}
	if !intelligence_capability_available(state.capabilities, request.kind) {
		return {}, false, intelligence_exchange_reject(state, .Unsupported_Capability)
	}
	if request.kind == .Semantic_Tokens_Delta && !state.capabilities.semantic_tokens.delta {
		return {}, false, intelligence_exchange_reject(state, .Unsupported_Capability)
	}
	descriptor, bound, binding_failure := document_synchronizer_binding(synchronizer, state.binding)
	if !bound {
		state.latest_failure = binding_failure
		return {}, false, binding_failure
	}
	if descriptor.state != .Open || descriptor.handle.session != state.session ||
	   request.scope.session != state.session || request.scope.binding != state.binding ||
	   request.scope.document_identity != descriptor.document_identity ||
	   request.scope.buffer_identity != descriptor.buffer_identity ||
	   request.scope.canonical_revision != descriptor.canonical_revision ||
	   request.scope.transmitted_revision != descriptor.transmitted_revision ||
	   descriptor.transmitted_revision != descriptor.canonical_revision ||
	   request.scope.provider_generation != state.session.provider.generation ||
	   request.scope.service_generation != state.session.generation {
		return {}, false, intelligence_exchange_reject(state, .Stale_Generation)
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
		request.byte_offset,
		descriptor.position_encoding,
	)
	if !positioned {
		state.latest_failure = position_failure
		return {}, false, position_failure
	}
	if state.next_request_id <= 0 || state.table_generation == Request_Generation(0) {
		return {}, false, intelligence_exchange_reject(state, .Arithmetic_Overflow)
	}
	body, built := intelligence_request_body(
		state.next_request_id,
		uri,
		position,
		request,
		state.allocator,
	)
	if !built do return {}, false, intelligence_exchange_reject(state, .Allocation)
	if u64(len(body)) > state.limits.message_bytes {
		actual := u64(len(body))
		delete(body, state.allocator)
		failure := intelligence_exchange_reject(state, .Resource_Limit)
		failure.resource = .Message_Bytes
		failure.limit = state.limits.message_bytes
		failure.actual = actual
		state.latest_failure = failure
		return {}, false, failure
	}
	intelligence_exchange_release_body(state)
	state.request = request
	state.request_id = {kind = .Integer, integer = state.next_request_id}
	state.next_request_id += 1
	state.request_state = .Queued
	state.deadline_ns = intelligence_deadline(now_ns, state.deadlines.request_ns)
	state.body = body
	return intelligence_exchange_view(state), true, {}
}

/* intelligence_exchange_send queues the prepared request on the exact process. */
intelligence_exchange_send :: proc(
	exchange: ^Intelligence_Exchange,
	process: ^Process_Session,
) -> (bool, Failure_Context) {
	state := intelligence_exchange_state(exchange)
	if state == nil do return false, Failure_Context{code = .Closed}
	if state.request_state != .Queued {
		return false, intelligence_exchange_reject(state, .Invalid_Request)
	}
	matched, failure := process_session_validate_handle(process, state.session)
	if !matched {
		state.latest_failure = failure
		return false, failure
	}
	sent, send_failure := process_session_send_frame(process, state.body)
	if !sent {
		state.latest_failure = send_failure
		return false, send_failure
	}
	state.request_state = .Sent
	return true, {}
}

/* intelligence_exchange_mark_sent advances a queued request for transport-independent adapters. */
intelligence_exchange_mark_sent :: proc(exchange: ^Intelligence_Exchange) -> (bool, Failure_Context) {
	state := intelligence_exchange_state(exchange)
	if state == nil do return false, Failure_Context{code = .Closed}
	if state.request_state != .Queued {
		return false, intelligence_exchange_reject(state, .Invalid_Request)
	}
	state.request_state = .Sent
	return true, {}
}

/* intelligence_exchange_cancel publishes cancellation when sent and invalidates locally. */
intelligence_exchange_cancel :: proc(
	exchange: ^Intelligence_Exchange,
	process: ^Process_Session,
) -> (bool, Failure_Context) {
	state := intelligence_exchange_state(exchange)
	if state == nil do return false, Failure_Context{code = .Closed}
	if state.request_state != .Queued && state.request_state != .Sent {
		return false, intelligence_exchange_reject(state, .Invalid_Request)
	}
	if state.request_state == .Sent {
		matched, failure := process_session_validate_handle(process, state.session)
		if !matched {
			state.latest_failure = failure
			return false, failure
		}
		body, built := intelligence_cancel_body(state.request_id.integer, context.temp_allocator)
		if !built do return false, intelligence_exchange_reject(state, .Allocation)
		sent, send_failure := process_session_send_frame(process, body)
		if !sent {
			state.latest_failure = send_failure
			return false, send_failure
		}
	}
	state.request_state = .Cancelled
	state.deadline_ns = 0
	intelligence_exchange_release_body(state)
	return true, {}
}

/* intelligence_exchange_cancel_local invalidates one queued or sent request without transport. */
intelligence_exchange_cancel_local :: proc(exchange: ^Intelligence_Exchange) -> (bool, Failure_Context) {
	state := intelligence_exchange_state(exchange)
	if state == nil do return false, Failure_Context{code = .Closed}
	if state.request_state != .Queued && state.request_state != .Sent {
		return false, intelligence_exchange_reject(state, .Invalid_Request)
	}
	state.request_state = .Cancelled
	state.deadline_ns = 0
	intelligence_exchange_release_body(state)
	return true, {}
}

/* intelligence_exchange_poll expires one active request without blocking. */
intelligence_exchange_poll :: proc(
	exchange: ^Intelligence_Exchange,
	now_ns: i64,
) -> (Request_State, bool, Failure_Context) {
	state := intelligence_exchange_state(exchange)
	if state == nil do return .Invalid, false, Failure_Context{code = .Closed}
	if state.request_state != .Queued && state.request_state != .Sent &&
	   state.request_state != .Cancelling {
		return state.request_state, true, {}
	}
	if now_ns < state.deadline_ns do return state.request_state, true, {}
	failure := intelligence_exchange_fail_request(state, .Timeout)
	failure.deadline = .Request
	state.latest_failure = failure
	state.request_state = .Timed_Out
	return state.request_state, true, failure
}

/* intelligence_exchange_fail contains one active server or transport failure. */
intelligence_exchange_fail :: proc(
	exchange: ^Intelligence_Exchange,
	source: Failure_Context,
) -> (bool, Failure_Context) {
	state := intelligence_exchange_state(exchange)
	if state == nil do return false, Failure_Context{code = .Closed}
	if state.request_state != .Queued && state.request_state != .Sent &&
	   state.request_state != .Cancelling {
		return false, intelligence_exchange_reject(state, .Invalid_Request)
	}
	failure := source
	if failure.code == .None do failure.code = .Protocol
	failure.session = state.session
	failure.binding = state.binding
	failure.request_id = state.request_id
	state.latest_failure = failure
	state.request_state = .Failed
	state.deadline_ns = 0
	intelligence_exchange_release_body(state)
	return true, failure
}

/* intelligence_exchange_current borrows the exact current request. */
intelligence_exchange_current :: proc(exchange: ^Intelligence_Exchange) -> (Intelligence_Request_View, bool) {
	state := intelligence_exchange_state(exchange)
	if state == nil || state.request_state == .Invalid do return {}, false
	return intelligence_exchange_view(state), true
}

/* intelligence_exchange_inspect copies request authority and failure state. */
intelligence_exchange_inspect :: proc(exchange: ^Intelligence_Exchange) -> (Intelligence_Exchange_Inspection, bool) {
	state := intelligence_exchange_state(exchange)
	if state == nil do return {}, false
	return Intelligence_Exchange_Inspection {
		session = state.session,
		binding = state.binding,
		request_id = state.request_id,
		table_generation = state.table_generation,
		state = state.request_state,
		query_kind = state.request.kind,
		request_generation = state.request.generation,
		result_generation = state.next_result_generation,
		payload_bytes = u64(len(state.body)),
		latest_failure = state.latest_failure,
	}, true
}

/* intelligence_exchange_close releases request and semantic-delta storage exactly once. */
intelligence_exchange_close :: proc(exchange: ^Intelligence_Exchange) -> bool {
	state := intelligence_exchange_state(exchange)
	if state == nil do return false
	intelligence_exchange_release_body(state)
	if state.semantic_data != nil do delete(state.semantic_data)
	allocator := state.allocator
	free(state, allocator)
	exchange^ = {}
	return true
}

@(private)
intelligence_exchange_state :: proc(exchange: ^Intelligence_Exchange) -> ^Intelligence_Exchange_State {
	if exchange == nil || exchange.state == nil do return nil
	return cast(^Intelligence_Exchange_State)exchange.state
}

@(private)
intelligence_exchange_fail_request :: proc(
	state: ^Intelligence_Exchange_State,
	code: Failure_Code,
) -> Failure_Context {
	failure := intelligence_exchange_reject(state, code)
	state.request_state = .Failed
	state.deadline_ns = 0
	intelligence_exchange_release_body(state)
	return failure
}

@(private)
intelligence_exchange_reject :: proc(
	state: ^Intelligence_Exchange_State,
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
intelligence_exchange_view :: proc(state: ^Intelligence_Exchange_State) -> Intelligence_Request_View {
	return {
		request = state.request,
		request_id = state.request_id,
		table_generation = state.table_generation,
		state = state.request_state,
		deadline_ns = state.deadline_ns,
		body = state.body,
	}
}

@(private)
intelligence_exchange_release_body :: proc(state: ^Intelligence_Exchange_State) {
	if state.body != nil do delete(state.body, state.allocator)
	state.body = nil
}

@(private = "file")
intelligence_capability_available :: proc(
	values: Capability_Values,
	kind: Intelligence_Query_Kind,
) -> bool {
	switch kind {
	case .Hover:
		return .Hover in values.capabilities
	case .Definition:
		return .Definition in values.capabilities
	case .References:
		return .References in values.capabilities
	case .Document_Symbols:
		return .Document_Symbols in values.capabilities
	case .Workspace_Symbols:
		return .Workspace_Symbols in values.capabilities
	case .Signature_Help:
		return .Signature_Help in values.capabilities
	case .Semantic_Tokens_Full, .Semantic_Tokens_Delta:
		return .Semantic_Tokens in values.capabilities
	case .Invalid:
		return false
	}
	return false
}

@(private = "file")
intelligence_request_body :: proc(
	id: i64,
	uri: string,
	position: LSP_Position,
	request: Intelligence_Request,
	allocator: runtime.Allocator,
) -> ([]u8, bool) {
	Text_Document :: struct {uri: string}
	Document_Params :: struct {text_document: Text_Document `json:"textDocument"`}
	Position_Params :: struct {
		text_document: Text_Document `json:"textDocument"`,
		position: LSP_Position,
	}
	Reference_Context :: struct {include_declaration: bool `json:"includeDeclaration"`}
	Reference_Params :: struct {
		text_document: Text_Document `json:"textDocument"`,
		position: LSP_Position,
		reference_context: Reference_Context `json:"context"`,
	}
	Workspace_Params :: struct {query: string}
	Delta_Params :: struct {
		text_document: Text_Document `json:"textDocument"`,
		previous_result_id: string `json:"previousResultId"`,
	}
	Position_Message :: struct {jsonrpc: string, id: i64, method: string, params: Position_Params}
	Document_Message :: struct {jsonrpc: string, id: i64, method: string, params: Document_Params}
	Reference_Message :: struct {jsonrpc: string, id: i64, method: string, params: Reference_Params}
	Workspace_Message :: struct {jsonrpc: string, id: i64, method: string, params: Workspace_Params}
	Delta_Message :: struct {jsonrpc: string, id: i64, method: string, params: Delta_Params}
	method := intelligence_method(request.kind)
	if method == "" do return nil, false
	if request.kind == .Document_Symbols || request.kind == .Semantic_Tokens_Full {
		body, marshal_error := json.marshal(Document_Message {
			jsonrpc = "2.0", id = id, method = method,
			params = {text_document = {uri = uri}},
		}, {}, allocator)
		return body, marshal_error == nil
	}
	if request.kind == .Workspace_Symbols {
		query := request.query
		body, marshal_error := json.marshal(Workspace_Message {
			jsonrpc = "2.0", id = id, method = method,
			params = {query = intelligence_text_string(&query)},
		}, {}, allocator)
		return body, marshal_error == nil
	}
	if request.kind == .References {
		body, marshal_error := json.marshal(Reference_Message {
			jsonrpc = "2.0", id = id, method = method,
			params = {
				text_document = {uri = uri},
				position = position,
				reference_context = {include_declaration = request.include_declaration},
			},
		}, {}, allocator)
		return body, marshal_error == nil
	}
	if request.kind == .Semantic_Tokens_Delta {
		previous_result_id := request.previous_result_id
		body, marshal_error := json.marshal(Delta_Message {
			jsonrpc = "2.0", id = id, method = method,
			params = {
				text_document = {uri = uri},
				previous_result_id = string(previous_result_id.bytes[:int(previous_result_id.length)]),
			},
		}, {}, allocator)
		return body, marshal_error == nil
	}
	body, marshal_error := json.marshal(Position_Message {
		jsonrpc = "2.0", id = id, method = method,
		params = {text_document = {uri = uri}, position = position},
	}, {}, allocator)
	return body, marshal_error == nil
}

@(private)
intelligence_method :: proc(kind: Intelligence_Query_Kind) -> string {
	switch kind {
	case .Hover: return "textDocument/hover"
	case .Definition: return "textDocument/definition"
	case .References: return "textDocument/references"
	case .Document_Symbols: return "textDocument/documentSymbol"
	case .Workspace_Symbols: return "workspace/symbol"
	case .Signature_Help: return "textDocument/signatureHelp"
	case .Semantic_Tokens_Full: return "textDocument/semanticTokens/full"
	case .Semantic_Tokens_Delta: return "textDocument/semanticTokens/full/delta"
	case .Invalid:
	}
	return ""
}

@(private = "file")
intelligence_cancel_body :: proc(id: i64, allocator: runtime.Allocator) -> ([]u8, bool) {
	Params :: struct {id: i64}
	Message :: struct {jsonrpc, method: string, params: Params}
	body, marshal_error := json.marshal(
		Message{jsonrpc = "2.0", method = "$/cancelRequest", params = {id = id}},
		{},
		allocator,
	)
	return body, marshal_error == nil
}

@(private = "file")
intelligence_deadline :: proc(now_ns, duration_ns: i64) -> i64 {
	if duration_ns <= 0 || now_ns > max(i64) - duration_ns do return max(i64)
	return now_ns + duration_ns
}
