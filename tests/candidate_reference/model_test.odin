// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package candidate_reference

import "core:mem"
import "core:testing"

/* Verifies order-independent components, match classes, recency, and stable ties. */
@(test)
filters_and_orders_stably :: proc(t: ^testing.T) {
	candidates := []Candidate {
		{
			identity = {kind = 1, primary = 3},
			label = "Project Alpha",
			folded_label = "project alpha",
			searchable_fields = []string{"command provider"},
			recency = 4,
		},
		{
			identity = {kind = 1, primary = 2},
			label = "Alpha Project",
			folded_label = "alpha project",
			recency = 8,
		},
		{
			identity = {kind = 1, primary = 1},
			label = "Other",
			folded_label = "other",
			searchable_fields = []string{"alpha project"},
			recency = 9,
		},
	}
	output: [3]Projection
	count, ok, failure := filter(candidates, "alpha project", output[:])
	testing.expectf(t, ok, "candidate oracle failed with %v", failure.code)
	testing.expect_value(t, count, 3)
	if count == 3 {
		testing.expect_value(t, output[0].candidate_index, 1)
		testing.expect_value(t, output[0].match_class, Match_Class.Exact_Label)
		testing.expect_value(t, output[1].candidate_index, 0)
		testing.expect_value(t, output[1].match_class, Match_Class.Prefix_Or_Boundary)
		testing.expect_value(t, output[2].candidate_index, 2)
		testing.expect_value(t, output[2].match_class, Match_Class.Literal)
	}
}

/* Verifies rejected queries and temporary work leave no retained allocations. */
@(test)
rejects_bounds_without_memory :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	candidates := []Candidate{{identity = {primary = 1}, label = "alpha", folded_label = "alpha"}}
	output: [1]Projection
	_, ok, _ := filter(candidates, "alpha", output[:], allocator)
	testing.expect(t, ok)
	malformed_bytes := []byte{0xff}
	_, malformed, malformed_failure := filter(
		candidates,
		transmute(string)malformed_bytes,
		output[:],
		allocator,
	)
	testing.expect(t, !malformed)
	testing.expect_value(t, malformed_failure.code, Failure_Code.Malformed_UTF8)
	_, limited, limit_failure := filter(
		candidates,
		"a b c d e f g h i",
		output[:],
		allocator,
	)
	testing.expect(t, !limited)
	testing.expect_value(t, limit_failure.code, Failure_Code.Component_Limit)
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	mem.tracking_allocator_destroy(&tracking)
}
