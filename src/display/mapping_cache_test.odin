// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package display

import "../editor"
import editor_view "../view"
import "core:testing"

/* Verifies every retained mapping round-trips between exact source and display boundaries. */
@(test)
projection_mappings_round_trip_exact_boundaries :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 71, "\t界e\u0301\n🙂x")
	if !ready {
		return
	}
	defer projection_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	snapshot, projected, failure := project(
		&fixture.buffer,
		projection_request(11, logical, Viewport_Constraints{width_cells = 12, height_rows = 3}),
	)
	testing.expectf(t, projected, "projection failed with %v", failure.code)
	if !projected {
		return
	}
	defer snapshot_close(&snapshot)
	result, _, _ := snapshot_view(snapshot)
	for row in result.rows {
		for boundary_index in 0 ..< row.boundary_count {
			boundary := result.boundaries[row.first_boundary + boundary_index]
			source := editor.Position {
				buffer_id = result.key.buffer_id,
				revision = result.key.buffer_revision,
				byte_offset = boundary.source_byte_offset,
			}
			display_position, mapped, map_failure := snapshot_source_to_display(snapshot, source)
			testing.expectf(t, mapped, "source %d failed with %v", source.byte_offset, map_failure.code)
			if !mapped {
				continue
			}
			round_trip, reversed, reverse_failure := snapshot_display_to_source(
				snapshot,
				display_position,
			)
			testing.expectf(t, reversed, "display %v failed with %v", display_position, reverse_failure.code)
			if reversed {
				testing.expect_value(t, round_trip, source)
			}
		}
	}
	_, interior_mapped, interior_failure := snapshot_display_to_source(
		snapshot,
		Display_Position{viewport_row = 0, column = 1},
	)
	testing.expect(t, !interior_mapped)
	testing.expect_value(t, interior_failure.code, Failure_Code.Mapping_Miss)
}

/* Verifies snapshot compatibility rejects changed view state, geometry, and revisions. */
@(test)
projection_snapshot_compatibility_is_exact :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 73, "compatibility")
	if !ready {
		return
	}
	defer projection_fixture_close(&fixture)
	constraints := Viewport_Constraints{width_cells = 16, height_rows = 2}
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	snapshot, projected, _ := project(
		&fixture.buffer,
		projection_request(12, logical, constraints),
	)
	testing.expect(t, projected)
	if !projected {
		return
	}
	defer snapshot_close(&snapshot)
	compatible, _ := snapshot_is_compatible(snapshot, logical, constraints, terminal_unicode17_profile())
	testing.expect(t, compatible)
	_, geometry_failure := snapshot_is_compatible(
		snapshot,
		logical,
		Viewport_Constraints{width_cells = 15, height_rows = 2},
		terminal_unicode17_profile(),
	)
	testing.expect_value(t, geometry_failure.code, Failure_Code.Incompatible_Snapshot)

	origin, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(0))
	viewport_ok, _ := editor_view.set_viewport(&fixture.registry, fixture.handle, origin, 1)
	testing.expect(t, viewport_ok)
	changed_view, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	_, state_failure := snapshot_is_compatible(
		snapshot,
		changed_view,
		constraints,
		terminal_unicode17_profile(),
	)
	testing.expect_value(t, state_failure.code, Failure_Code.Incompatible_Snapshot)

	start, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(0))
	end, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(1))
	_, _, published, _ := editor.buffer_splice(
		&fixture.buffer,
		editor.Splice{start = start, end = end, replacement = "C"},
		context.temp_allocator,
	)
	testing.expect(t, published)
	current_view, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	_, revision_failure := snapshot_is_compatible(
		snapshot,
		current_view,
		constraints,
		terminal_unicode17_profile(),
	)
	testing.expect_value(t, revision_failure.code, Failure_Code.Stale_Snapshot)
}

/* Verifies cached long-line replay reduces bounded source work and supports invalidation. */
@(test)
cache_reuses_and_invalidates_checkpoints :: proc(t: ^testing.T) {
	long_line: [20_000]u8
	for &value in long_line {
		value = 'x'
	}
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 75, string(long_line[:]))
	if !ready {
		return
	}
	defer projection_fixture_close(&fixture)
	origin, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(0))
	first_viewport, _ := editor_view.set_viewport(&fixture.registry, fixture.handle, origin, 7_900)
	testing.expect(t, first_viewport)
	first_logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	cache: Projection_Cache
	cache_ready, cache_failure := projection_cache_init(
		&cache,
		first_logical,
		terminal_unicode17_profile(),
		context.allocator,
	)
	testing.expectf(t, cache_ready, "cache initialization failed with %v", cache_failure.code)
	if !cache_ready {
		return
	}
	defer projection_cache_close(&cache)
	first, first_ok, first_failure := project_cached(
		&fixture.buffer,
		projection_request(13, first_logical, Viewport_Constraints{width_cells = 80, height_rows = 1}),
		&cache,
	)
	testing.expectf(t, first_ok, "first cached projection failed with %v", first_failure.code)
	if !first_ok {
		return
	}
	first_result, _, _ := snapshot_view(first)
	first_source_bytes := first_result.accounting.source_bytes_examined
	snapshot_close(&first)

	second_viewport, _ := editor_view.set_viewport(&fixture.registry, fixture.handle, origin, 8_000)
	testing.expect(t, second_viewport)
	second_logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	warm, warm_ok, warm_failure := project_cached(
		&fixture.buffer,
		projection_request(14, second_logical, Viewport_Constraints{width_cells = 80, height_rows = 1}),
		&cache,
	)
	testing.expectf(t, warm_ok, "warm projection failed with %v", warm_failure.code)
	if !warm_ok {
		return
	}
	warm_result, _, _ := snapshot_view(warm)
	warm_source_bytes := warm_result.accounting.source_bytes_examined
	snapshot_close(&warm)
	cold, cold_ok, cold_failure := project(
		&fixture.buffer,
		projection_request(15, second_logical, Viewport_Constraints{width_cells = 80, height_rows = 1}),
	)
	testing.expectf(t, cold_ok, "cold projection failed with %v", cold_failure.code)
	if !cold_ok {
		return
	}
	cold_result, _, _ := snapshot_view(cold)
	cold_source_bytes := cold_result.accounting.source_bytes_examined
	snapshot_close(&cold)
	testing.expect(t, first_source_bytes > 0)
	testing.expect(t, warm_source_bytes < cold_source_bytes)

	stats, stats_ok, _ := projection_cache_stats(&cache)
	testing.expect(t, stats_ok && stats.valid)
	testing.expect(t, stats.checkpoint_count > 1)
	invalidated, _ := projection_cache_invalidate_line(
		&cache,
		second_logical.buffer_id,
		second_logical.revision,
		Logical_Line_Index(0),
	)
	testing.expect(t, invalidated)
	invalidated_stats, _, _ := projection_cache_stats(&cache)
	testing.expect(t, !invalidated_stats.valid)
	testing.expect_value(t, invalidated_stats.checkpoint_count, u32(0))
}

/* Verifies tiny checkpoint limits retain the newest bounded replay positions. */
@(test)
cache_replaces_oldest_at_capacity :: proc(t: ^testing.T) {
	long_line: [2_000]u8
	for &value in long_line {
		value = 'x'
	}
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 76, string(long_line[:]))
	if !ready {
		return
	}
	defer projection_fixture_close(&fixture)
	origin, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(0))
	viewport_ok, _ := editor_view.set_viewport(&fixture.registry, fixture.handle, origin, 1_500)
	testing.expect(t, viewport_ok)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	limits := DEFAULT_RESOURCE_LIMITS
	limits.checkpoints = 2
	cache: Projection_Cache
	cache_ready, cache_failure := projection_cache_init(
		&cache,
		logical,
		terminal_unicode17_profile(),
		context.allocator,
		limits,
	)
	testing.expectf(t, cache_ready, "cache initialization failed with %v", cache_failure.code)
	if !cache_ready {
		return
	}
	defer projection_cache_close(&cache)
	request := projection_request(
		17,
		logical,
		Viewport_Constraints{width_cells = 80, height_rows = 1},
	)
	request.limits = limits
	snapshot, projected, failure := project_cached(&fixture.buffer, request, &cache)
	testing.expectf(t, projected, "bounded projection failed with %v", failure.code)
	if !projected {
		return
	}
	defer snapshot_close(&snapshot)
	result, viewed, _ := snapshot_view(snapshot)
	testing.expect(t, viewed)
	testing.expect_value(t, len(result.checkpoints), 2)
	testing.expect(t, result.checkpoints[0].source_byte_offset < result.checkpoints[1].source_byte_offset)
	stats, stats_ok, _ := projection_cache_stats(&cache)
	testing.expect(t, stats_ok && stats.valid)
	testing.expect_value(t, stats.checkpoint_count, u32(2))
	testing.expect_value(t, stats.capacity, u32(2))
}

/* Verifies one view cannot consume another view's checkpoint cache. */
@(test)
projection_cache_rejects_a_different_view :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 77, "two views")
	if !ready {
		return
	}
	defer projection_fixture_close(&fixture)
	first_logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	cache: Projection_Cache
	cache_ready, _ := projection_cache_init(
		&cache,
		first_logical,
		terminal_unicode17_profile(),
		context.allocator,
	)
	testing.expect(t, cache_ready)
	if !cache_ready {
		return
	}
	defer projection_cache_close(&cache)
	second, second_ok, _ := editor_view.clone_additional(&fixture.registry, fixture.handle)
	testing.expect(t, second_ok)
	if !second_ok {
		return
	}
	defer editor_view.close(&fixture.registry, &second)
	second_logical, _, _ := editor_view.snapshot(&fixture.registry, second)
	_, projected, failure := project_cached(
		&fixture.buffer,
		projection_request(16, second_logical, Viewport_Constraints{width_cells = 12, height_rows = 1}),
		&cache,
	)
	testing.expect(t, !projected)
	testing.expect_value(t, failure.code, Failure_Code.Wrong_View)
}
