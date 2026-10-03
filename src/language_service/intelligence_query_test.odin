// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import project_core "../project"
import "base:runtime"
import "core:mem"
import "core:strings"
import "core:testing"

@(private)
intelligence_test_capabilities :: proc() -> Capability_Values {
	function_name, _ := name_text_from_string("function")
	variable_name, _ := name_text_from_string("variable")
	result := Capability_Values {
		capabilities = {
			.Initialize, .Shutdown, .Cancellation, .Hover, .Definition, .References,
			.Document_Symbols, .Workspace_Symbols, .Signature_Help, .Semantic_Tokens,
		},
		position_encoding = .UTF_16,
		synchronization_mode = .Incremental,
		semantic_tokens = {
			available = true,
			delta = true,
			token_count = 2,
		},
	}
	result.semantic_tokens.token_types[0] = function_name
	result.semantic_tokens.token_types[1] = variable_name
	return result
}

@(private)
intelligence_test_request :: proc(
	session: Session_Handle,
	binding: Document_Binding_Handle,
	kind: Intelligence_Query_Kind,
	generation: u64 = 1,
) -> Intelligence_Request {
	request := Intelligence_Request {
		id = Intelligence_Request_ID(generation),
		generation = Intelligence_Request_Generation(generation),
		kind = kind,
		scope = {
			session = session,
			binding = binding,
			document_identity = 41,
			buffer_identity = 43,
			canonical_revision = 1,
			transmitted_revision = 1,
			provider_generation = session.provider.generation,
			service_generation = session.generation,
		},
		byte_offset = 1,
		include_declaration = true,
	}
	if kind == .Workspace_Symbols {
		request.query, _ = intelligence_text_copy("fixture")
	}
	if kind == .Semantic_Tokens_Delta {
		request.previous_result_id.length = 2
		copy(request.previous_result_id.bytes[:2], "r1")
	}
	return request
}

@(private)
intelligence_test_prepare :: proc(
	t: ^testing.T,
	registry: ^project_core.Registry,
	synchronizer: ^Document_Synchronizer,
	exchange: ^Intelligence_Exchange,
	kind: Intelligence_Query_Kind,
	seed: u64,
	limits := DEFAULT_LIMITS,
	generation: u64 = 1,
) -> bool {
	session := synchronization_test_session(seed)
	binding, ready := completion_test_synchronizer(t, registry, synchronizer, session, seed + 7)
	if !ready || !completion_test_ack_open(synchronizer) do return false
	initialized, failure := intelligence_exchange_init(
		exchange,
		session,
		binding,
		intelligence_test_capabilities(),
		limits,
	)
	testing.expectf(t, initialized, "intelligence exchange init failed: %v", failure.code)
	if !initialized do return false
	request := intelligence_test_request(session, binding, kind, generation)
	view, prepared, prepare_failure := intelligence_exchange_prepare(exchange, synchronizer, request, 1)
	testing.expectf(t, prepared, "intelligence request prepare failed: %v", prepare_failure.code)
	if !prepared do return false
	testing.expect(t, strings.contains(string(view.body), intelligence_method(kind)))
	marked, mark_failure := intelligence_exchange_mark_sent(exchange)
	testing.expectf(t, marked, "intelligence request send transition failed: %v", mark_failure.code)
	return marked
}

@(private)
intelligence_test_response :: proc(
	t: ^testing.T,
	exchange: ^Intelligence_Exchange,
	synchronizer: ^Document_Synchronizer,
	body: string,
	allocator := context.allocator,
) -> (Intelligence_Result, bool, Failure_Context) {
	message, decoded, decode_failure := message_decode(transmute([]u8)body)
	testing.expectf(t, decoded, "intelligence response decode failed: %v", decode_failure.code)
	if !decoded do return {}, false, decode_failure
	defer message_close(&message)
	return intelligence_response_normalize(exchange, synchronizer, &message, allocator)
}

/* Verifies all read-only capabilities are negotiated and gate request methods independently. */
@(test)
intelligence_capabilities_gate_all_query_families :: proc(t: ^testing.T) {
	initialize := `{"jsonrpc":"2.0","id":1,"result":{"capabilities":{"hoverProvider":true,"definitionProvider":{},"referencesProvider":true,"documentSymbolProvider":{},"workspaceSymbolProvider":true,"signatureHelpProvider":{"triggerCharacters":["("]},"semanticTokensProvider":{"legend":{"tokenTypes":["function","variable"],"tokenModifiers":[]},"full":{"delta":true}}}}}`
	message, decoded, failure := message_decode(transmute([]u8)initialize)
	testing.expectf(t, decoded, "initialize response decode failed: %v", failure.code)
	if !decoded do return
	defer message_close(&message)
	values := message.record.capabilities
	negotiated_capabilities := [?]Capability {
		Capability.Hover,
		Capability.Definition,
		Capability.References,
		Capability.Document_Symbols,
		Capability.Workspace_Symbols,
		Capability.Signature_Help,
		Capability.Semantic_Tokens,
	}
	for capability in negotiated_capabilities {
		testing.expectf(t, capability in values.capabilities, "missing negotiated capability %v", capability)
	}
	testing.expect(t, values.semantic_tokens.available && values.semantic_tokens.delta)
	testing.expect_value(t, values.semantic_tokens.token_count, u16(2))

	session := synchronization_test_session(1_101)
	binding := Document_Binding_Handle{session = session, id = 1, generation = 1}
	exchange: Intelligence_Exchange
	initialized, _ := intelligence_exchange_init(&exchange, session, binding, Capability_Values{
		capabilities = {.Hover}, position_encoding = .UTF_16,
	})
	testing.expect(t, initialized)
	if !initialized do return
	defer intelligence_exchange_close(&exchange)
	request := intelligence_test_request(session, binding, .References)
	project_registry: project_core.Registry
	synchronizer: Document_Synchronizer
	_, ready := completion_test_synchronizer(t, &project_registry, &synchronizer, session, 1_109)
	if !ready do return
	defer project_core.registry_close(&project_registry)
	defer document_synchronizer_close(&synchronizer)
	testing.expect(t, completion_test_ack_open(&synchronizer))
	_, prepared, unsupported := intelligence_exchange_prepare(&exchange, &synchronizer, request, 1)
	testing.expect(t, !prepared)
	testing.expect_value(t, unsupported.code, Failure_Code.Unsupported_Capability)
}

/* Verifies empty hover plus copied multiple, duplicate, and external locations. */
@(test)
intelligence_normalizes_hover_locations_and_external_uris :: proc(t: ^testing.T) {
	{
		registry: project_core.Registry
		synchronizer: Document_Synchronizer
		exchange: Intelligence_Exchange
		if !intelligence_test_prepare(t, &registry, &synchronizer, &exchange, .Hover, 1_151) do return
		defer project_core.registry_close(&registry)
		defer document_synchronizer_close(&synchronizer)
		defer intelligence_exchange_close(&exchange)
		result, normalized, failure := intelligence_test_response(t, &exchange, &synchronizer, `{"jsonrpc":"2.0","id":1,"result":null}`)
		testing.expectf(t, normalized, "empty hover failed: %v", failure.code)
		if normalized {
			view, _ := intelligence_result_view(&result)
			testing.expect_value(t, len(view.hover), 0)
			testing.expect(t, intelligence_result_close(&result))
		}
	}
	{
		registry: project_core.Registry
		synchronizer: Document_Synchronizer
		exchange: Intelligence_Exchange
		if !intelligence_test_prepare(t, &registry, &synchronizer, &exchange, .References, 1_181) do return
		defer project_core.registry_close(&registry)
		defer document_synchronizer_close(&synchronizer)
		defer intelligence_exchange_close(&exchange)
		response := `{"jsonrpc":"2.0","id":1,"result":[{"uri":"file:///work/fixture/source.fixture","range":{"start":{"line":0,"character":0},"end":{"line":0,"character":1}}},{"uri":"file:///work/fixture/source.fixture","range":{"start":{"line":0,"character":0},"end":{"line":0,"character":1}}},{"uri":"file:///outside/other.fixture","range":{"start":{"line":7,"character":2},"end":{"line":7,"character":4}}}]}`
		result, normalized, failure := intelligence_test_response(t, &exchange, &synchronizer, response)
		testing.expectf(t, normalized, "location normalization failed: %v", failure.code)
		if normalized {
			view, _ := intelligence_result_view(&result)
			testing.expect_value(t, len(view.locations), 2)
			testing.expect(t, view.locations[0].range.bytes_present)
			testing.expect(t, !view.locations[1].range.bytes_present)
			external_uri := view.locations[1].uri
			testing.expect_value(t, intelligence_uri_string(&external_uri), "file:///outside/other.fixture")
			testing.expect(t, intelligence_result_close(&result))
		}
	}
}

/* Verifies symbols and signatures copy hierarchy, ranges, active state, and text. */
@(test)
intelligence_normalizes_symbols_and_signatures :: proc(t: ^testing.T) {
	{
		registry: project_core.Registry
		synchronizer: Document_Synchronizer
		exchange: Intelligence_Exchange
		if !intelligence_test_prepare(t, &registry, &synchronizer, &exchange, .Document_Symbols, 1_211) do return
		defer project_core.registry_close(&registry)
		defer document_synchronizer_close(&synchronizer)
		defer intelligence_exchange_close(&exchange)
		response := `{"jsonrpc":"2.0","id":1,"result":[{"name":"outer","detail":"proc","kind":12,"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":4}},"selectionRange":{"start":{"line":0,"character":0},"end":{"line":0,"character":1}},"children":[{"name":"value","kind":13,"range":{"start":{"line":0,"character":1},"end":{"line":0,"character":3}},"selectionRange":{"start":{"line":0,"character":1},"end":{"line":0,"character":3}}}]}]}`
		result, normalized, failure := intelligence_test_response(t, &exchange, &synchronizer, response)
		testing.expectf(t, normalized, "symbol normalization failed: %v", failure.code)
		if normalized {
			view, _ := intelligence_result_view(&result)
			testing.expect_value(t, len(view.symbols), 2)
			testing.expect_value(t, view.symbols[1].parent_id, view.symbols[0].id)
			testing.expect(t, intelligence_result_close(&result))
		}
	}
	{
		registry: project_core.Registry
		synchronizer: Document_Synchronizer
		exchange: Intelligence_Exchange
		if !intelligence_test_prepare(t, &registry, &synchronizer, &exchange, .Signature_Help, 1_241) do return
		defer project_core.registry_close(&registry)
		defer document_synchronizer_close(&synchronizer)
		defer intelligence_exchange_close(&exchange)
		response := `{"jsonrpc":"2.0","id":1,"result":{"signatures":[{"label":"call(value)","documentation":{"kind":"markdown","value":"Callable docs"},"parameters":[{"label":[5,10],"documentation":"Value docs"}]}],"activeSignature":0,"activeParameter":0}}`
		result, normalized, failure := intelligence_test_response(t, &exchange, &synchronizer, response)
		testing.expectf(t, normalized, "signature normalization failed: %v", failure.code)
		if normalized {
			view, _ := intelligence_result_view(&result)
			testing.expect_value(t, len(view.signatures), 1)
			testing.expect_value(t, len(view.parameters), 1)
			parameter := view.parameters[0].label
			testing.expect_value(t, intelligence_text_string(&parameter), "value")
			testing.expect(t, view.descriptor.has_active_signature && view.descriptor.has_active_parameter)
			testing.expect(t, intelligence_result_close(&result))
		}
	}
}

/* Verifies semantic full and delta results stay absolute, ordered, and non-overlapping. */
@(test)
intelligence_semantic_tokens_apply_delta_and_reject_overlap :: proc(t: ^testing.T) {
	registry: project_core.Registry
	synchronizer: Document_Synchronizer
	exchange: Intelligence_Exchange
	if !intelligence_test_prepare(t, &registry, &synchronizer, &exchange, .Semantic_Tokens_Full, 1_271) do return
	defer project_core.registry_close(&registry)
	defer document_synchronizer_close(&synchronizer)
	defer intelligence_exchange_close(&exchange)
	full, normalized, failure := intelligence_test_response(t, &exchange, &synchronizer, `{"jsonrpc":"2.0","id":1,"result":{"resultId":"r1","data":[0,0,1,0,0,0,1,2,1,0]}}`)
	testing.expectf(t, normalized, "semantic full normalization failed: %v", failure.code)
	if !normalized do return
	full_view, _ := intelligence_result_view(&full)
	testing.expect_value(t, len(full_view.tokens), 2)
	testing.expect_value(t, full_view.tokens[1].start_byte, u64(1))
	testing.expect_value(t, full_view.tokens[1].end_byte, u64(5))
	testing.expect(t, intelligence_result_close(&full))

	state := intelligence_exchange_state(&exchange)
	request := intelligence_test_request(state.session, state.binding, .Semantic_Tokens_Delta, 2)
	_, prepared, prepare_failure := intelligence_exchange_prepare(&exchange, &synchronizer, request, 10)
	testing.expectf(t, prepared, "semantic delta prepare failed: %v", prepare_failure.code)
	if !prepared do return
	marked, _ := intelligence_exchange_mark_sent(&exchange)
	testing.expect(t, marked)
	delta: Intelligence_Result
	delta, normalized, failure = intelligence_test_response(t, &exchange, &synchronizer, `{"jsonrpc":"2.0","id":2,"result":{"resultId":"r2","edits":[{"start":5,"deleteCount":5,"data":[0,3,1,1,0]}]}}`)
	testing.expectf(t, normalized, "semantic delta normalization failed: %v", failure.code)
	if normalized {
		delta_view, _ := intelligence_result_view(&delta)
		testing.expect_value(t, len(delta_view.tokens), 2)
		testing.expect_value(t, delta_view.tokens[1].start_byte, u64(5))
		testing.expect(t, intelligence_result_close(&delta))
	}

	request = intelligence_test_request(state.session, state.binding, .Semantic_Tokens_Full, 3)
	_, prepared, _ = intelligence_exchange_prepare(&exchange, &synchronizer, request, 20)
	marked, _ = intelligence_exchange_mark_sent(&exchange)
	testing.expect(t, prepared && marked)
	_, normalized, failure = intelligence_test_response(t, &exchange, &synchronizer, `{"jsonrpc":"2.0","id":3,"result":{"data":[0,0,2,0,0,0,1,1,1,0]}}`)
	testing.expect(t, !normalized)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Range)
}

/* Verifies stale, malformed, partial, excessive, cancellation, timeout, and server failures stay contained. */
@(test)
intelligence_contains_adversarial_lifecycle_and_results :: proc(t: ^testing.T) {
	{
		limits := DEFAULT_LIMITS
		limits.diagnostics_per_document = 1
		limits.diagnostics_per_project = 1
		limits.candidates = 1
		registry: project_core.Registry
		synchronizer: Document_Synchronizer
		exchange: Intelligence_Exchange
		if !intelligence_test_prepare(t, &registry, &synchronizer, &exchange, .Definition, 1_311, limits) do return
		defer project_core.registry_close(&registry)
		defer document_synchronizer_close(&synchronizer)
		defer intelligence_exchange_close(&exchange)
		stale_text := `{"jsonrpc":"2.0","id":2,"result":null}`
		stale, decoded, _ := message_decode(transmute([]u8)stale_text)
		testing.expect(t, decoded)
		if decoded {
			_, normalized, failure := intelligence_response_normalize(&exchange, &synchronizer, &stale)
			testing.expect(t, !normalized)
			testing.expect_value(t, failure.code, Failure_Code.Stale_Generation)
			message_close(&stale)
		}
		_, normalized, failure := intelligence_test_response(t, &exchange, &synchronizer, `{"jsonrpc":"2.0","id":1,"result":[{"uri":"file:///work/fixture/source.fixture","range":{"start":{"line":0,"character":0},"end":{"line":0,"character":1}}},{"uri":"file:///work/fixture/source.fixture","range":{"start":{"line":0,"character":1},"end":{"line":0,"character":3}}}]}`)
		testing.expect(t, !normalized)
		testing.expect_value(t, failure.code, Failure_Code.Resource_Limit)
	}
	{
		registry: project_core.Registry
		synchronizer: Document_Synchronizer
		exchange: Intelligence_Exchange
		if !intelligence_test_prepare(t, &registry, &synchronizer, &exchange, .Hover, 1_341) do return
		defer project_core.registry_close(&registry)
		defer document_synchronizer_close(&synchronizer)
		defer intelligence_exchange_close(&exchange)
		_, normalized, malformed := intelligence_test_response(t, &exchange, &synchronizer, `{"jsonrpc":"2.0","id":1,"result":{"contents":7}}`)
		testing.expect(t, !normalized)
		testing.expect_value(t, malformed.code, Failure_Code.Protocol)
	}
	{
		registry: project_core.Registry
		synchronizer: Document_Synchronizer
		exchange: Intelligence_Exchange
		if !intelligence_test_prepare(t, &registry, &synchronizer, &exchange, .References, 1_371) do return
		defer project_core.registry_close(&registry)
		defer document_synchronizer_close(&synchronizer)
		defer intelligence_exchange_close(&exchange)
		cancelled, _ := intelligence_exchange_cancel_local(&exchange)
		testing.expect(t, cancelled)
		inspection, _ := intelligence_exchange_inspect(&exchange)
		testing.expect_value(t, inspection.state, Request_State.Cancelled)
	}
	{
		registry: project_core.Registry
		synchronizer: Document_Synchronizer
		exchange: Intelligence_Exchange
		if !intelligence_test_prepare(t, &registry, &synchronizer, &exchange, .Hover, 1_401) do return
		defer project_core.registry_close(&registry)
		defer document_synchronizer_close(&synchronizer)
		defer intelligence_exchange_close(&exchange)
		current, _ := intelligence_exchange_current(&exchange)
		request_state, _, timeout := intelligence_exchange_poll(&exchange, current.deadline_ns)
		testing.expect_value(t, request_state, Request_State.Timed_Out)
		testing.expect_value(t, timeout.code, Failure_Code.Timeout)
	}
	{
		registry: project_core.Registry
		synchronizer: Document_Synchronizer
		exchange: Intelligence_Exchange
		if !intelligence_test_prepare(t, &registry, &synchronizer, &exchange, .Hover, 1_431) do return
		defer project_core.registry_close(&registry)
		defer document_synchronizer_close(&synchronizer)
		defer intelligence_exchange_close(&exchange)
		failed, failure := intelligence_exchange_fail(&exchange, Failure_Context{code = .Process_Exit})
		testing.expect(t, failed)
		testing.expect_value(t, failure.code, Failure_Code.Process_Exit)
	}
}

/* Verifies result ownership releases memory and allocation faults publish nothing. */
@(test)
intelligence_allocation_fault_and_cleanup_are_exact :: proc(t: ^testing.T) {
	registry: project_core.Registry
	synchronizer: Document_Synchronizer
	exchange: Intelligence_Exchange
	if !intelligence_test_prepare(t, &registry, &synchronizer, &exchange, .Hover, 1_461) do return
	defer project_core.registry_close(&registry)
	defer document_synchronizer_close(&synchronizer)
	defer intelligence_exchange_close(&exchange)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	tracked := mem.tracking_allocator(&tracking)
	result, normalized, failure := intelligence_test_response(t, &exchange, &synchronizer, `{"jsonrpc":"2.0","id":1,"result":{"contents":["alpha",{"language":"odin","value":"beta"}]}}`, tracked)
	testing.expectf(t, normalized, "tracked hover normalization failed: %v", failure.code)
	if normalized do testing.expect(t, intelligence_result_close(&result))
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)

	state := intelligence_exchange_state(&exchange)
	request := intelligence_test_request(state.session, state.binding, .Hover, 2)
	_, prepared, _ := intelligence_exchange_prepare(&exchange, &synchronizer, request, 10)
	marked, _ := intelligence_exchange_mark_sent(&exchange)
	testing.expect(t, prepared && marked)
	failing := Intelligence_Test_Failing_Allocator{backing = context.allocator}
	_, normalized, failure = intelligence_test_response(t, &exchange, &synchronizer, `{"jsonrpc":"2.0","id":2,"result":{"contents":["alpha"]}}`, intelligence_test_failing_allocator(&failing))
	testing.expect(t, !normalized)
	testing.expect_value(t, failure.code, Failure_Code.Allocation)
}

@(private)
Intelligence_Test_Failing_Allocator :: struct {
	backing: runtime.Allocator,
}

@(private)
intelligence_test_failing_allocator :: proc(data: ^Intelligence_Test_Failing_Allocator) -> runtime.Allocator {
	return {procedure = intelligence_test_failing_allocator_proc, data = data}
}

@(private)
intelligence_test_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	_ = allocator_data
	_ = size
	_ = alignment
	_ = old_memory
	_ = old_size
	_ = location
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize || mode == .Resize_Non_Zeroed {
		return nil, .Out_Of_Memory
	}
	return nil, nil
}
