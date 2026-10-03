// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import completion "../completion"
import project_core "../project"
import "core:mem"
import "core:strings"
import "core:testing"

@(private)
completion_test_prepare_sent :: proc(
	t: ^testing.T,
	registry: ^project_core.Registry,
	synchronizer: ^Document_Synchronizer,
	exchange: ^Completion_Exchange,
	seed: u64,
) -> bool {
	session := synchronization_test_session(seed)
	binding, ready := completion_test_synchronizer(t, registry, synchronizer, session, seed + 11)
	if !ready || !completion_test_ack_open(synchronizer) do return false
	initialized, failure := completion_exchange_init(
		exchange,
		session,
		binding,
		completion_test_capabilities(),
	)
	testing.expectf(t, initialized, "exchange init failed: %v", failure.code)
	if !initialized do return false
	request := completion_test_request(session, binding)
	_, prepared, prepare_failure := completion_exchange_prepare(exchange, synchronizer, request, 1)
	testing.expectf(t, prepared, "completion prepare failed: %v", prepare_failure.code)
	if !prepared do return false
	state := completion_exchange_state(exchange)
	state.request_state = .Sent
	return true
}

/* Verifies list responses normalize semantic fields, edits, and rejected items. */
@(test)
completion_response_normalizes_list_items :: proc(t: ^testing.T) {
	registry: project_core.Registry
	synchronizer: Document_Synchronizer
	exchange: Completion_Exchange
	ready := completion_test_prepare_sent(t, &registry, &synchronizer, &exchange, 821)
	if !ready do return
	defer project_core.registry_close(&registry)
	defer document_synchronizer_close(&synchronizer)
	defer completion_exchange_close(&exchange)

	response_text := `{"jsonrpc":"2.0","id":1,"result":{"isIncomplete":true,"items":[{"label":"alpha","labelDetails":{"detail":"(value)","description":"fixture"},"kind":3,"tags":[1],"detail":"callable detail","documentation":{"kind":"markdown","value":"**alpha**"},"sortText":"01","filterText":"al","textEdit":{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":1}},"newText":"alpha()"},"additionalTextEdits":[{"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":0}},"newText":"use alpha\n"}],"data":{"token":7}},{"kind":3}]}}`
	message, decoded, decode_failure := message_decode(transmute([]u8)response_text)
	testing.expectf(t, decoded, "response decode failed: %v", decode_failure.code)
	if !decoded do return
	defer message_close(&message)
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)

	owner, normalized, failure := completion_response_normalize(
		&exchange,
		&synchronizer,
		&message,
		allocator,
	)
	testing.expectf(t, normalized, "response normalization failed: %v", failure.code)
	if !normalized {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	testing.expect_value(t, owner.batch.disposition, completion.Batch_Disposition.Incomplete)
	testing.expect_value(t, owner.batch.item_count, u16(1))
	testing.expect_value(t, owner.batch.rejected_item_count, u16(1))
	candidate := &owner.batch.items[0]
	testing.expect_value(t, candidate.kind, completion.Candidate_Kind.Callable)
	testing.expect_value(t, candidate.availability, completion.Candidate_Availability.Deprecated)
	testing.expect_value(t, completion.text_view(&candidate.label), "alpha")
	testing.expect_value(t, completion.text_view(&candidate.label_detail), "(value)")
	testing.expect_value(t, completion.text_view(&candidate.description), "fixture")
	testing.expect_value(t, completion.text_view(&candidate.insertion_text), "alpha()")
	testing.expect_value(t, candidate.primary_edit.range, completion.Byte_Range{start = 0, end = 1})
	testing.expect_value(t, candidate.additional_edit_count, u8(1))
	testing.expect_value(t, candidate.documentation_format, completion.Documentation_Format.Markdown)
	testing.expect_value(t, completion.detail_view(&candidate.documentation), "**alpha**")
	testing.expect(t, strings.contains(completion.resolve_token_view(&candidate.resolve_token), `"token":7`))
	inspection, inspected := completion_exchange_inspect(&exchange)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.state, Request_State.Completed)
	testing.expect_value(t, inspection.payload_bytes, u64(0))
	testing.expect(t, completion_batch_owner_close(&owner))
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies item defaults provide an exact replacement range for textEditText. */
@(test)
completion_response_applies_item_defaults :: proc(t: ^testing.T) {
	registry: project_core.Registry
	synchronizer: Document_Synchronizer
	exchange: Completion_Exchange
	ready := completion_test_prepare_sent(t, &registry, &synchronizer, &exchange, 853)
	if !ready do return
	defer project_core.registry_close(&registry)
	defer document_synchronizer_close(&synchronizer)
	defer completion_exchange_close(&exchange)

	response_text := `{"jsonrpc":"2.0","id":1,"result":{"itemDefaults":{"editRange":{"start":{"line":0,"character":0},"end":{"line":0,"character":1}}},"items":[{"label":"atom","textEditText":"atom"}]}}`
	message, decoded, _ := message_decode(transmute([]u8)response_text)
	testing.expect(t, decoded)
	if !decoded do return
	defer message_close(&message)
	owner, normalized, failure := completion_response_normalize(&exchange, &synchronizer, &message)
	testing.expectf(t, normalized, "default normalization failed: %v", failure.code)
	if !normalized do return
	defer completion_batch_owner_close(&owner)
	testing.expect_value(t, owner.batch.item_count, u16(1))
	candidate := &owner.batch.items[0]
	testing.expect(t, candidate.has_primary_edit)
	testing.expect_value(t, candidate.primary_edit.range, completion.Byte_Range{start = 0, end = 1})
	testing.expect_value(t, completion.text_view(&candidate.primary_edit.new_text), "atom")
}

/* Verifies null results remain valid empty batches and stale replies are rejected. */
@(test)
completion_response_contains_empty :: proc(t: ^testing.T) {
	registry: project_core.Registry
	synchronizer: Document_Synchronizer
	exchange: Completion_Exchange
	ready := completion_test_prepare_sent(t, &registry, &synchronizer, &exchange, 881)
	if !ready do return
	defer project_core.registry_close(&registry)
	defer document_synchronizer_close(&synchronizer)
	defer completion_exchange_close(&exchange)

	stale_text := `{"jsonrpc":"2.0","id":2,"result":[]}`
	stale, decoded, _ := message_decode(transmute([]u8)stale_text)
	testing.expect(t, decoded)
	if decoded {
		_, normalized, failure := completion_response_normalize(&exchange, &synchronizer, &stale)
		testing.expect(t, !normalized)
		testing.expect_value(t, failure.code, Failure_Code.Stale_Generation)
		message_close(&stale)
	}

	empty_text := `{"jsonrpc":"2.0","id":1,"result":null}`
	empty: Message
	empty, decoded, _ = message_decode(transmute([]u8)empty_text)
	testing.expect(t, decoded)
	if !decoded do return
	defer message_close(&empty)
	owner, normalized, failure := completion_response_normalize(&exchange, &synchronizer, &empty)
	testing.expectf(t, normalized, "empty normalization failed: %v", failure.code)
	if !normalized do return
	defer completion_batch_owner_close(&owner)
	testing.expect_value(t, owner.batch.disposition, completion.Batch_Disposition.Complete)
	testing.expect_value(t, owner.batch.item_count, u16(0))
}

/* Verifies an exact protocol error fails and releases the active request. */
@(test)
completion_response_contains_protocol_error :: proc(t: ^testing.T) {
	registry: project_core.Registry
	synchronizer: Document_Synchronizer
	exchange: Completion_Exchange
	ready := completion_test_prepare_sent(t, &registry, &synchronizer, &exchange, 907)
	if !ready do return
	defer project_core.registry_close(&registry)
	defer document_synchronizer_close(&synchronizer)
	defer completion_exchange_close(&exchange)

	error_text := `{"jsonrpc":"2.0","id":1,"error":{"code":-32603,"message":"fixture failure"}}`
	message, decoded, _ := message_decode(transmute([]u8)error_text)
	testing.expect(t, decoded)
	if !decoded do return
	defer message_close(&message)
	_, normalized, failure := completion_response_normalize(&exchange, &synchronizer, &message)
	testing.expect(t, !normalized)
	testing.expect_value(t, failure.code, Failure_Code.Protocol)
	inspection, inspected := completion_exchange_inspect(&exchange)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.state, Request_State.Failed)
	testing.expect_value(t, inspection.payload_bytes, u64(0))
}
