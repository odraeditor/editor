// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package completion

import "core:mem"
import "core:testing"

@(private)
completion_filter_candidate :: proc(
	id: Candidate_ID,
	label_text: string,
	filter_text: string = "",
	sort_text: string = "",
	provider_order: u32 = 0,
) -> Candidate {
	label, _ := text_copy(label_text)
	filter, _ := text_copy(filter_text)
	sort, _ := text_copy(sort_text)
	return {
		id = id,
		kind = .Callable,
		availability = .Available,
		label = label,
		filter_text = filter,
		sort_text = sort,
		insertion_text = label,
		provenance = {provider_id = 8, provider_generation = 9, provider_order = provider_order},
		copied_bytes = u64(len(label_text) * 2 + len(filter_text) + len(sort_text)),
	}
}

@(private)
completion_filter_fixture :: proc(items: []Candidate, query_text: string) -> (Request, Batch, Query_Context) {
	request := test_request()
	request.cursor_byte = u64(len(query_text))
	request.query_range = {start = 0, end = request.cursor_byte}
	query, _ := text_copy(query_text)
	request.query = query
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
		item_count = u16(len(items)),
	}
	query_context := Query_Context {
		range = request.query_range,
		text = query,
		grapheme_count = u16(len(query_text)),
		trigger = .Identifier,
	}
	return request, batch, query_context
}

/* Verifies explicit match classes and deterministic ordering. */
@(test)
filter_orders_match_classes_and_provider_ties :: proc(t: ^testing.T) {
	items := []Candidate {
		completion_filter_candidate(1, "pXrYiZn", provider_order = 4),
		completion_filter_candidate(2, "Print", provider_order = 3),
		completion_filter_candidate(3, "pri", provider_order = 2),
		completion_filter_candidate(4, "private", sort_text = "02", provider_order = 1),
		completion_filter_candidate(5, "priority", sort_text = "01", provider_order = 0),
		completion_filter_candidate(6, "absent", provider_order = 5),
	}
	request, batch, query := completion_filter_fixture(items, "pri")
	projection, built, failure := projection_build(&batch, &request, query)
	testing.expectf(t, built, "projection failed: %v", failure.code)
	if !built do return
	defer projection_close(&projection)
	testing.expect_value(t, projection.item_count, u16(5))
	testing.expect_value(t, projection.items[0].candidate_id, Candidate_ID(3))
	testing.expect_value(t, projection.items[1].candidate_id, Candidate_ID(5))
	testing.expect_value(t, projection.items[2].candidate_id, Candidate_ID(4))
	testing.expect_value(t, projection.items[3].candidate_id, Candidate_ID(2))
	testing.expect_value(t, projection.items[4].candidate_id, Candidate_ID(1))
}

/* Verifies filterText participates while documentation and detail do not. */
@(test)
completion_filter_uses_only_filter_text_or_label :: proc(t: ^testing.T) {
	first := completion_filter_candidate(11, "display", "needle")
	second := completion_filter_candidate(12, "needleLabel")
	third := completion_filter_candidate(13, "other")
	third_detail, _ := detail_copy("needle")
	third.documentation = third_detail
	items := []Candidate{first, second, third}
	request, batch, query := completion_filter_fixture(items, "needle")
	projection, built, _ := projection_build(&batch, &request, query)
	testing.expect(t, built)
	if !built do return
	defer projection_close(&projection)
	testing.expect_value(t, projection.item_count, u16(2))
	testing.expect_value(t, projection.items[0].candidate_id, Candidate_ID(11))
}

/* Verifies exact semantic duplicates collapse while overload evidence remains distinct. */
@(test)
filter_deduplicates_only_equivalent_candidates :: proc(t: ^testing.T) {
	first := completion_filter_candidate(21, "print", provider_order = 0)
	duplicate := first
	duplicate.id = 22
	duplicate.provenance.provider_order = 1
	overload := completion_filter_candidate(23, "print", provider_order = 2)
	overload.detail, _ = detail_copy("different overload")
	items := []Candidate{first, duplicate, overload}
	request, batch, query := completion_filter_fixture(items, "pri")
	projection, built, _ := projection_build(&batch, &request, query)
	testing.expect(t, built)
	if !built do return
	defer projection_close(&projection)
	testing.expect_value(t, projection.item_count, u16(2))
	testing.expect_value(t, projection.deduplicated, u16(1))
}

/* Verifies local filtering preserves a visible identity and otherwise selects first. */
@(test)
completion_filter_preserves_stable_selection :: proc(t: ^testing.T) {
	items := []Candidate {
		completion_filter_candidate(31, "alpha", provider_order = 0),
		completion_filter_candidate(32, "alpine", provider_order = 1),
	}
	request, batch, query := completion_filter_fixture(items, "al")
	projection, built, _ := projection_build(&batch, &request, query, 32)
	testing.expect(t, built)
	if !built do return
	testing.expect_value(t, projection.selected, Candidate_ID(32))
	projection_close(&projection)
	projection, built, _ = projection_build(&batch, &request, query, 99)
	testing.expect(t, built)
	if built {
		testing.expect_value(t, projection.selected, Candidate_ID(31))
		projection_close(&projection)
	}
}

/* Verifies Unicode case folding and projection teardown release storage. */
@(test)
filter_folds_unicode_and_releases_projection :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	items := []Candidate{completion_filter_candidate(41, "CAFÉ")}
	request, batch, query := completion_filter_fixture(items, "café")
	projection, built, _ := projection_build(&batch, &request, query, allocator = allocator)
	testing.expect(t, built)
	if built do testing.expect(t, projection_close(&projection))
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}
