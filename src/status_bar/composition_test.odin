// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package status_bar

import "../display"
import "base:runtime"
import "core:testing"

@(private = "file")
Composition_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private = "file")
composition_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	allocator := cast(^Composition_Failing_Allocator)allocator_data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after {
			return nil, .Out_Of_Memory
		}
		allocator.successful_allocations += 1
	}
	return allocator.backing.procedure(
		allocator.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}

@(private = "file")
composition_test_request :: proc(segments: []Segment_Definition, width: u32) -> Composition_Request {
	return Composition_Request {
		generation = Generation(1),
		width_cells = width,
		segments = segments,
		profile = display.unicode17_profile(),
		allocator = context.allocator,
		limits = DEFAULT_LIMITS,
	}
}

@(private = "file")
composition_test_segments :: proc() -> [4]Segment_Definition {
	return [4]Segment_Definition {
		{
			id = Segment_ID(1),
			kind = .Buffer_State,
			group = .Left,
			priority = 255,
			full_text = "--",
			required = true,
			style_role = .Safety,
		},
		{
			id = Segment_ID(2),
			kind = .Buffer_Identity,
			group = .Left,
			priority = 254,
			full_text = "main.odin",
			required = true,
			truncatable = true,
			style_role = .Buffer_Identity,
			inspection_text = "/work/main.odin",
		},
		{
			id = Segment_ID(3),
			kind = .Encoding,
			group = .Right,
			priority = 1,
			full_text = "UTF-8 LF",
			compact_text = "UTF-8",
			omittable = true,
			style_role = .Context,
		},
		{
			id = Segment_ID(4),
			kind = .Position,
			group = .Right,
			priority = 253,
			full_text = "23% (418,17)",
			compact_text = "23%",
			required = true,
			style_role = .Position,
		},
	}
}

@(test)
/* Verifies exact-width composition, stable grouping, and owned inspection text. */
status_composition_materializes_full_view :: proc(t: ^testing.T) {
	definitions := composition_test_segments()
	view, ok, failure := compose(composition_test_request(definitions[:], 40))
	testing.expect(t, ok)
	testing.expect_value(t, failure.code, Failure_Code.None)
	defer view_close(&view)
	testing.expect_value(t, view.accounting.text_cells, u32(40))
	testing.expect_value(t, len(view.segments), 4)
	testing.expect_value(
		t,
		string(view.text),
		"-- main.odin       UTF-8 LF 23% (418,17)",
	)
	testing.expect_value(t, view.segments[1].inspection_text, "/work/main.odin")
	testing.expect_value(t, view.segments[0].start_cell, u32(0))
	testing.expect_value(t, view.segments[3].end_cell, u32(40))
}

@(test)
/* Verifies compact and omitted forms precede truncation of required identity. */
status_composition_degrades_by_priority :: proc(t: ^testing.T) {
	definitions := composition_test_segments()
	view, ok, _ := compose(composition_test_request(definitions[:], 20))
	testing.expect(t, ok)
	defer view_close(&view)
	testing.expect_value(t, string(view.text), "-- main.odin     23%")
	testing.expect_value(t, len(view.segments), 3)
	testing.expect(t, view.segments[2].compact)
	testing.expect_value(t, view.segments[2].id, Segment_ID(4))
}

@(test)
/* Verifies required Unicode identity truncation preserves grapheme boundaries. */
status_composition_truncates_unicode_identity :: proc(t: ^testing.T) {
	definitions := [3]Segment_Definition {
		{
			id = Segment_ID(1), kind = .Buffer_State, group = .Left, priority = 255,
			full_text = "--", required = true, style_role = .Safety,
		},
		{
			id = Segment_ID(2), kind = .Buffer_Identity, group = .Left, priority = 254,
			full_text = "zażółć.odin", required = true, truncatable = true,
			style_role = .Buffer_Identity,
		},
		{
			id = Segment_ID(3), kind = .Position, group = .Right, priority = 253,
			full_text = "100%", required = true, style_role = .Position,
		},
	}
	view, ok, _ := compose(composition_test_request(definitions[:], 12))
	testing.expect(t, ok)
	defer view_close(&view)
	testing.expect_value(t, string(view.text), "-- zaż… 100%")
	testing.expect(t, view.segments[1].truncated)
}

@(test)
/* Verifies duplicate semantic identities are rejected before allocation. */
status_composition_rejects_duplicate_segments :: proc(t: ^testing.T) {
	definitions := composition_test_segments()
	definitions[1].id = definitions[0].id
	_, ok, failure := compose(composition_test_request(definitions[:], 40))
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Segment)
	testing.expect_value(t, failure.segment, Segment_ID(1))
}

@(test)
/* Verifies view ownership cannot be closed twice. */
status_composition_view_closes_once :: proc(t: ^testing.T) {
	definitions := composition_test_segments()
	view, ok, _ := compose(composition_test_request(definitions[:], 40))
	testing.expect(t, ok)
	closed, _ := view_close(&view)
	testing.expect(t, closed)
	closed_again, failure := view_close(&view)
	testing.expect(t, !closed_again)
	testing.expect_value(t, failure.code, Failure_Code.Closed_View)
}

@(test)
/* Verifies partial materialization is released when a later allocation fails. */
status_composition_contains_allocation_failure :: proc(t: ^testing.T) {
	definitions := composition_test_segments()
	failing := Composition_Failing_Allocator{backing = context.allocator, fail_after = 1}
	request := composition_test_request(definitions[:], 40)
	request.allocator = runtime.Allocator {
		procedure = composition_failing_allocator_proc,
		data = &failing,
	}
	_, ok, failure := compose(request)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Allocation)
}
