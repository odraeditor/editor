// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package display

import "../editor"
import editor_view "../view"
import "core:testing"
import "core:unicode/utf8"

@(private)
PROJECTION_PROPERTY_CASES :: 96

/* Verifies randomized hybrid snapshots preserve bounds, ordering, accounting, and mappings. */
@(test)
properties_hold_for_unicode_inputs :: proc(t: ^testing.T) {
	seed := u64(0x4f44_5241_5052_4f4a)
	tokens := [?]string{"a", "z", "é", "e\u0301", "界", "🙂", "\t", "\n", "\u0007"}
	for case_index in 0 ..< PROJECTION_PROPERTY_CASES {
		text_storage: [4_096]u8
		text_bytes := 0
		token_count := 1 + int(projection_random_next(&seed) % 180)
		for _ in 0 ..< token_count {
			token := tokens[int(projection_random_next(&seed) % u64(len(tokens)))]
			if text_bytes + len(token) > len(text_storage) {
				break
			}
			text_bytes += copy(text_storage[text_bytes:], token)
		}
		fixture: Projection_Fixture
		ready := projection_fixture_init(
			t,
			&fixture,
			u64(1_000 + case_index),
			string(text_storage[:text_bytes]),
		)
		if !ready {
			return
		}
		width := u32(1 + projection_random_next(&seed) % 40)
		height := u32(1 + projection_random_next(&seed) % 8)
		horizontal := u32(projection_random_next(&seed) % 20)
		origin, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(0))
		viewport_ok, _ := editor_view.set_viewport(
			&fixture.registry,
			fixture.handle,
			origin,
			horizontal,
		)
		testing.expect(t, viewport_ok)
		logical, logical_ok, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
		request := projection_request(
			u64(2_000 + case_index),
			logical,
			Viewport_Constraints{width_cells = width, height_rows = height},
		)
		snapshot, projected, failure := project(&fixture.buffer, request)
		testing.expectf(
			t,
			logical_ok && projected,
			"case %d projection failed with %v",
			case_index,
			failure.code,
		)
		if logical_ok && projected {
			projection_expect_invariants(t, snapshot, logical, request)
			snapshot_close(&snapshot)
		}
		projection_fixture_close(&fixture)
	}
}

@(private)
projection_expect_invariants :: proc(
	t: ^testing.T,
	snapshot: Snapshot,
	logical: editor_view.Snapshot,
	request: Projection_Request,
) {
	result, viewed, _ := snapshot_view(snapshot)
	testing.expect(t, viewed)
	if !viewed {
		return
	}
	testing.expect_value(t, len(result.rows), int(request.constraints.height_rows))
	testing.expect(t, utf8.valid_string(result.text))
	testing.expect(t, result.accounting.retained_bytes <= request.limits.derived_bytes)
	expected_retained := result.accounting.owner_bytes + result.accounting.text_bytes +
	                     result.accounting.row_bytes + result.accounting.run_bytes +
	                     result.accounting.boundary_bytes + result.accounting.checkpoint_bytes
	testing.expect_value(t, result.accounting.retained_bytes, expected_retained)
	testing.expect_value(t, result.accounting.text_bytes, u64(len(result.text)))
	testing.expect_value(
		t,
		result.accounting.row_bytes,
		u64(len(result.rows)) * u64(size_of(Display_Row)),
	)
	testing.expect_value(
		t,
		result.accounting.run_bytes,
		u64(len(result.runs)) * u64(size_of(Text_Run)),
	)
	testing.expect_value(
		t,
		result.accounting.boundary_bytes,
		u64(len(result.boundaries)) * u64(size_of(Boundary_Map)),
	)
	testing.expect_value(
		t,
		result.accounting.checkpoint_bytes,
		u64(len(result.checkpoints)) * u64(size_of(Line_Checkpoint)),
	)
	compatible, compatibility_failure := snapshot_is_compatible(
		snapshot,
		logical,
		request.constraints,
		request.profile,
	)
	testing.expectf(t, compatible, "snapshot compatibility failed with %v", compatibility_failure.code)

	previous_source := editor.Byte_Offset(0)
	has_previous_source := false
	for row, row_index in result.rows {
		testing.expect_value(t, row.viewport_row, Display_Row_Index(row_index))
		testing.expect(t, u64(row.visible_cells) <= u64(request.constraints.width_cells))
		testing.expect(t, u64(row.first_run) + u64(row.run_count) <= u64(len(result.runs)))
		testing.expect(
			t,
			u64(row.first_boundary) + u64(row.boundary_count) <= u64(len(result.boundaries)),
		)
		if !row.has_content {
			testing.expect_value(t, row.run_count, u32(0))
			testing.expect_value(t, row.boundary_count, u32(0))
			continue
		}
		previous_column := row.visible_start
		for boundary_index in 0 ..< row.boundary_count {
			boundary := result.boundaries[row.first_boundary + boundary_index]
			testing.expect(t, boundary.display_column >= previous_column)
			testing.expect(
				t,
				u64(boundary.display_column) <=
				u64(row.visible_start) + u64(request.constraints.width_cells),
			)
			if has_previous_source {
				testing.expect(t, boundary.source_byte_offset >= previous_source)
			}
			position := editor.Position {
				buffer_id = result.key.buffer_id,
				revision = result.key.buffer_revision,
				byte_offset = boundary.source_byte_offset,
			}
			display_position, mapped, _ := snapshot_source_to_display(snapshot, position)
			testing.expect(t, mapped)
			if mapped {
				round_trip, reversed, _ := snapshot_display_to_source(snapshot, display_position)
				testing.expect(t, reversed)
				if reversed {
					testing.expect_value(t, round_trip, position)
				}
			}
			previous_column = boundary.display_column
			previous_source = boundary.source_byte_offset
			has_previous_source = true
		}
	}
	for run in result.runs {
		testing.expect(t, u64(run.text_offset) + u64(run.text_bytes) <= u64(len(result.text)))
		testing.expect(t, run.cell_count <= request.constraints.width_cells)
	}
}

@(private)
projection_random_next :: proc(seed: ^u64) -> u64 {
	value := seed^
	value ~= value << 13
	value ~= value >> 7
	value ~= value << 17
	seed^ = value
	return value
}
