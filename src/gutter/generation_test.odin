// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package gutter

import "core:testing"

@(private = "file")
generation_test_marker :: proc(id: Marker_ID, line: u64, detail := "diagnostic") -> Marker {
	return Marker {
		id = id,
		provider = 7,
		provider_generation = 3,
		lane = 11,
		attachment = {
			kind = .Logical_Line,
			logical_line = line,
			buffer_revision = 9,
		},
		style_role = .Diagnostic_Error,
		priority = 100,
		representation = {kind = .Glyph, value = "●", fallback = "E"},
		aggregation_label = "E",
		detail = detail,
	}
}

@(test)
/* marker_generations_copy_bounded_values_and_release_exactly_once. */
generations_copy_and_release_once :: proc(t: ^testing.T) {
	markers := [2]Marker{generation_test_marker(1, 2), generation_test_marker(2, 8, "warning")}
	generation, copied, failure := marker_generation_copy(Marker_Generation_Proposal {
		id = 4,
		provider = 7,
		provider_generation = 3,
		complete = true,
		markers = markers[:],
	})
	testing.expectf(t, copied, "generation copy failed: %v", failure.code)
	if !copied do return
	markers[0].detail = "changed"
	testing.expect_value(t, generation.markers[0].detail, "diagnostic")
	testing.expect(t, generation.complete && generation.retained_bytes > 0)
	closed, close_failure := marker_generation_close(&generation)
	testing.expectf(t, closed, "generation close failed: %v", close_failure.code)
	closed, close_failure = marker_generation_close(&generation)
	testing.expect(t, !closed)
	testing.expect_value(t, close_failure.code, Failure_Code.Closed_View)
}

@(test)
/* marker_generations_reject_invalid_duplicate_stale_and_cancelled_input. */
generations_reject_bad_updates :: proc(t: ^testing.T) {
	duplicate := [2]Marker{generation_test_marker(1, 2), generation_test_marker(1, 3)}
	_, copied, failure := marker_generation_copy(Marker_Generation_Proposal {
		id = 1, provider = 7, provider_generation = 3, complete = true, markers = duplicate[:],
	})
	testing.expect(t, !copied)
	testing.expect_value(t, failure.code, Failure_Code.Duplicate_Marker)

	invalid := generation_test_marker(2, 4)
	invalid.attachment.kind = .Display_Row
	_, copied, failure = marker_generation_copy(Marker_Generation_Proposal {
		id = 2, provider = 7, provider_generation = 3, markers = []Marker{invalid},
	})
	testing.expect(t, !copied)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Marker)

	_, copied, failure = marker_generation_copy(Marker_Generation_Proposal {
		id = 3, provider = 7, provider_generation = 3, cancelled = true,
	})
	testing.expect(t, !copied)
	testing.expect_value(t, failure.code, Failure_Code.Cancelled)
}

@(test)
/* marker_generations_retain_explicit_incomplete_publications. */
generations_keep_incomplete_publish :: proc(t: ^testing.T) {
	generation, copied, _ := marker_generation_copy(Marker_Generation_Proposal {
		id = 9,
		provider = 7,
		provider_generation = 3,
		complete = false,
		markers = []Marker{generation_test_marker(1, 1)},
	})
	testing.expect(t, copied)
	if copied {
		testing.expect(t, !generation.complete)
		marker_generation_close(&generation)
	}
}

@(test)
/* marker_store_rejects_late_updates_and_preserves_the_last_valid_generation. */
store_keeps_last_valid_generation :: proc(t: ^testing.T) {
	store: Marker_Store
	initialized, _ := marker_store_init(&store)
	testing.expect(t, initialized)
	if !initialized do return
	defer marker_store_close(&store)
	first, published, _ := marker_store_publish(&store, Marker_Generation_Proposal {
		id = 2,
		provider = 7,
		provider_generation = 3,
		complete = true,
		markers = []Marker{generation_test_marker(1, 2)},
	})
	testing.expect(t, published)
	testing.expect_value(t, first.id, Marker_Generation_ID(2))
	failure: Failure_Context
	_, published, failure = marker_store_publish(&store, Marker_Generation_Proposal {
		id = 1,
		provider = 7,
		provider_generation = 3,
		complete = true,
		markers = []Marker{generation_test_marker(2, 3)},
	})
	testing.expect(t, !published)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Generation)
	retained, retained_ok, _ := marker_store_view(&store)
	testing.expect(t, retained_ok)
	testing.expect_value(t, retained.id, Marker_Generation_ID(2))
	testing.expect_value(t, retained.markers[0].id, Marker_ID(1))
}
