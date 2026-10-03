// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package completion

import "core:testing"

/* Verifies explicit and identifier queries use Unicode-aware boundaries. */
@(test)
query_derives_unicode_identifier_range :: proc(t: ^testing.T) {
	text := "call café_value"
	query, derived, failure := query_derive(text, u64(len(text)), .Identifier)
	testing.expectf(t, derived, "query derivation failed: %v", failure.code)
	if !derived do return
	testing.expect_value(t, query.range, Byte_Range{start = 5, end = u64(len(text))})
	testing.expect_value(t, text_view(&query.text), "café_value")
	testing.expect_value(t, query.grapheme_count, u16(10))
}

/* Verifies trigger characters produce an empty query after committed text. */
@(test)
query_validates_server_trigger_character :: proc(t: ^testing.T) {
	trigger, _ := text_copy(".")
	query, derived, _ := query_derive("value.", 6, .Trigger_Character, trigger)
	testing.expect(t, derived)
	if derived {
		testing.expect_value(t, query.range, Byte_Range{start = 6, end = 6})
		testing.expect_value(t, query.grapheme_count, u16(0))
	}
	_, stale, failure := query_derive("value:", 6, .Trigger_Character, trigger)
	testing.expect(t, !stale)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Request)
}

/* Verifies compatible typing and backspace update one retained query range. */
@(test)
completion_query_reconciles_edits_inside_range :: proc(t: ^testing.T) {
	base := "prefix"
	query, derived, _ := query_derive(base, 6, .Identifier)
	testing.expect(t, derived)
	if !derived do return
	next, compatible, _ := query_reconcile_edit(
		query,
		base,
		"prefix_",
		Query_Edit{start = 6, end = 6, replacement = "_"},
	)
	testing.expect(t, compatible)
	if compatible {
		testing.expect_value(t, next.range, Byte_Range{start = 0, end = 7})
		testing.expect_value(t, text_view(&next.text), "prefix_")
	}
	back: Query_Context
	back, compatible, _ = query_reconcile_edit(
		next,
		"prefix_",
		"prefix",
		Query_Edit{start = 6, end = 7},
	)
	testing.expect(t, compatible)
	if compatible do testing.expect_value(t, text_view(&back.text), "prefix")
}

/* Verifies edits outside the query and malformed splices are stale. */
@(test)
query_rejects_incompatible_document_edit :: proc(t: ^testing.T) {
	query, derived, _ := query_derive("one value", 9, .Identifier)
	testing.expect(t, derived)
	if !derived do return
	_, compatible, failure := query_reconcile_edit(
		query,
		"one value",
		"two value",
		Query_Edit{start = 0, end = 3, replacement = "two"},
	)
	testing.expect(t, !compatible)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Request)
	_, compatible, failure = query_reconcile_edit(
		query,
		"one value",
		"one value!",
		Query_Edit{start = 9, end = 9, replacement = "?"},
	)
	testing.expect(t, !compatible)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Request)
}

/* Verifies query storage rejects oversized prefixes without truncation. */
@(test)
completion_query_bounds_copied_prefix :: proc(t: ^testing.T) {
	storage: [MAX_COMPLETION_TEXT_BYTES + 1]u8
	for &value in storage do value = 'a'
	_, derived, failure := query_derive(string(storage[:]), u64(len(storage)), .Identifier)
	testing.expect(t, !derived)
	testing.expect_value(t, failure.code, Failure_Code.Text_Limit)
}
