// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package completion

import "core:testing"

/* test_scope returns one complete exact provider request scope. */
test_scope :: proc() -> Request_Scope {
	return {
		document_id = 1,
		buffer_id = 2,
		document_revision = 3,
		view_id = 4,
		view_generation = 5,
		language_id = 6,
		language_generation = 7,
		provider_id = 8,
		provider_generation = 9,
		server_session_id = 10,
		server_session_generation = 11,
		document_binding_id = 12,
		document_binding_generation = 13,
		transmitted_revision = 3,
	}
}

/* test_request returns one valid prepared request for package tests. */
test_request :: proc() -> Request {
	query, _ := text_copy("pri")
	return {
		id = 21,
		generation = 1,
		scope = test_scope(),
		cursor_byte = 14,
		query_range = {start = 11, end = 14},
		query = query,
		trigger = .Explicit,
		provider_capabilities = {
			.Explicit,
			.Identifier,
			.Trigger_Character,
			.Incomplete,
			.Resolve,
			.Additional_Edits,
			.Documentation,
		},
		state = .Prepared,
	}
}

/* test_candidate returns one valid normalized candidate for package tests. */
test_candidate :: proc(id: Candidate_ID) -> Candidate {
	label, _ := text_copy("print")
	insertion, _ := text_copy("print")
	return {
		id = id,
		kind = .Callable,
		availability = .Available,
		label = label,
		insertion_text = insertion,
		provenance = {provider_id = 8, provider_generation = 9},
		copied_bytes = 10,
	}
}

/* Verifies bounded copied text preserves useful empty values and exact content. */
@(test)
completion_contracts_copy_bounded_text :: proc(t: ^testing.T) {
	empty, empty_ok := text_copy("")
	value, value_ok := text_copy("callable")
	overflow_bytes: [MAX_COMPLETION_TEXT_BYTES + 1]u8
	_, overflow_ok := text_copy(string(overflow_bytes[:]))

	testing.expect(t, empty_ok && value_ok && !overflow_ok)
	testing.expect_value(t, text_view(&empty), "")
	testing.expect_value(t, text_view(&value), "callable")
}

/* Verifies requests reject missing generations, stale transmission, and invalid ranges. */
@(test)
completion_contracts_validate_request_scope :: proc(t: ^testing.T) {
	request := test_request()
	testing.expect(t, request_is_valid(&request))

	request.scope.transmitted_revision = 2
	testing.expect(t, !request_is_valid(&request))
	request = test_request()
	request.query_range = {start = 15, end = 14}
	testing.expect(t, !request_is_valid(&request))
	request = test_request()
	request.scope.provider_generation = 0
	testing.expect(t, !request_is_valid(&request))
	request = test_request()
	request.scope.document_revision = 0
	request.scope.transmitted_revision = 0
	testing.expect(t, request_is_valid(&request))
}

/* Verifies batches preserve stable candidate identity and exact request binding. */
@(test)
completion_contracts_validate_batch_identity :: proc(t: ^testing.T) {
	request := test_request()
	items := []Candidate{test_candidate(41)}
	batch := Batch {
		id = 31,
		generation = 1,
		request_id = request.id,
		request_generation = request.generation,
		scope = request.scope,
		request_cursor_byte = request.cursor_byte,
		query_range = request.query_range,
		disposition = .Complete,
		items = items,
		item_count = 1,
		copied_bytes = 10,
	}
	testing.expect(t, batch_is_valid(&batch, &request))

	batch.scope.document_revision = 4
	testing.expect(t, !batch_is_valid(&batch, &request))
	batch = {}
	testing.expect(t, !batch_is_valid(&batch, &request))
}

/* Verifies item edits and configured limits reject malformed values. */
@(test)
completion_contracts_validate_items_and_limits :: proc(t: ^testing.T) {
	candidate := test_candidate(42)
	testing.expect(t, candidate_is_valid(&candidate, test_scope()))
	candidate.has_primary_edit = true
	candidate.primary_edit.range = {start = 8, end = 7}
	testing.expect(t, !candidate_is_valid(&candidate, test_scope()))

	limits := DEFAULT_LIMITS
	testing.expect(t, limits_are_valid(limits))
	limits.candidates = MAX_COMPLETION_CANDIDATES + 1
	testing.expect(t, !limits_are_valid(limits))
}
