// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package result_set

import "../editor"
import "../search"
import editor_view "../view"
import "core:testing"

/* Ensures materialized search results retain query policy and active selection. */
@(test)
materialization_keeps_query_and_selection :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(&buffer, 8, "....alpha.....alpha.", editor.Allocator_Set{
		persistent = context.allocator, temporary = context.temp_allocator})
	testing.expect(t, initialized)
	if !initialized do return
	defer editor.buffer_close(&buffer)
	registry: Registry
	registry_init(&registry, Config{limits = DEFAULT_LIMITS, allocator = context.allocator})
	occurrences := []search.Occurrence {
		{buffer_id = 8, revision = 0, start = 4, end = 9},
		{buffer_id = 8, revision = 0, start = 14, end = 19},
	}
	snapshot := editor_view.Search_Snapshot {
		present = true,
		interaction_generation = 5,
		policy_generation = 3,
		source_revision = 0,
		direction = .Forward,
		kind = .Literal,
		scope = search.Scope{buffer_id = 8, revision = 0, start = 0, end = 20},
		query = "alpha",
		policy = search.Policy{case_mode = .Sensitive, boundary_mode = .Word,
			whitespace_mode = .Flexible, wrap = false},
		limits = search.DEFAULT_LIMITS,
		has_current = true,
		current_index = 1,
		occurrences = occurrences,
		progress = search.Progress{next_offset = 20, complete = true},
	}
	result, materialized, failure := search_materialize(&registry, snapshot,
		Search_Materialization_Config{set_id = 4, source_id = 9, buffer = &buffer,
			allocator = context.allocator})
	testing.expectf(t, materialized, "materialization failed with %v", failure.code)
	testing.expect_value(t, result.location_id, Location_ID(15))
	view, viewed, _ := registry_view(&registry, 4)
	testing.expect(t, viewed)
	testing.expect_value(t, view.metadata.descriptor, "alpha")
	testing.expect_value(t, view.metadata.values[2], u64(search.Boundary_Mode.Word))
	testing.expect_value(t, view.completeness, Completeness.Complete)
	testing.expect_value(t, view.locations[1].revision, editor.Revision(0))
	testing.expect_value(t, view.locations[1].preview, "....alpha.....alpha.")
	testing.expect_value(t, view.locations[1].annotation, "1:15")
	testing.expect_value(t, view.locations[1].preview_match_start, u32(14))
	testing.expect_value(t, view.locations[1].preview_match_end, u32(19))
	testing.expect(t, view.locations[1].preview_match_present)
	registry_close(&registry)
}

/* Ensures result metadata reports whether the underlying search can continue. */
@(test)
materialization_exposes_continuation :: proc(t: ^testing.T) {
	text: [100]u8
	for &value in text do value = 'x'
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(&buffer, 1, string(text[:]), editor.Allocator_Set{
		persistent = context.allocator, temporary = context.temp_allocator})
	testing.expect(t, initialized)
	if !initialized do return
	defer editor.buffer_close(&buffer)
	registry: Registry
	registry_init(&registry, Config{limits = DEFAULT_LIMITS, allocator = context.allocator})
	snapshot := editor_view.Search_Snapshot {
		present = true, interaction_generation = 1, policy_generation = 1,
		source_revision = 0, direction = .Forward, kind = .Literal,
		scope = search.Scope{buffer_id = 1, revision = 0, start = 0, end = 100},
		query = "x", policy = search.DEFAULT_POLICY, limits = search.DEFAULT_LIMITS,
		progress = search.Progress{next_offset = 64, complete = false},
	}
	_, materialized, _ := search_materialize(&registry, snapshot,
		Search_Materialization_Config{set_id = 1, source_id = 1, buffer = &buffer,
			allocator = context.allocator})
	testing.expect(t, materialized)
	view, _, _ := registry_view(&registry, 1)
	testing.expect_value(t, view.completeness, Completeness.Incomplete)
	testing.expect(t, view.continuation.present)
	testing.expect_value(t, view.continuation.cursor, u64(64))
	registry_close(&registry)
}

/* Ensures displayed columns count Unicode scalars rather than encoded bytes. */
@(test)
materialization_reports_unicode_columns :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(&buffer, 3, "żółw alpha\n", editor.Allocator_Set{
		persistent = context.allocator, temporary = context.temp_allocator})
	testing.expect(t, initialized)
	if !initialized do return
	defer editor.buffer_close(&buffer)
	registry: Registry
	registry_init(&registry, Config{limits = DEFAULT_LIMITS, allocator = context.allocator})
	defer registry_close(&registry)
	occurrences := []search.Occurrence{{buffer_id = 3, revision = 0, start = 8, end = 13}}
	snapshot := editor_view.Search_Snapshot{
		present = true, interaction_generation = 1, policy_generation = 1,
		source_revision = 0, direction = .Forward, kind = .Literal,
		scope = {buffer_id = 3, revision = 0, start = 0, end = 14},
		query = "alpha", policy = search.DEFAULT_POLICY, limits = search.DEFAULT_LIMITS,
		occurrences = occurrences, progress = {next_offset = 14, complete = true},
	}
	_, materialized, failure := search_materialize(&registry, snapshot,
		Search_Materialization_Config{set_id = 1, source_id = 1, buffer = &buffer,
			allocator = context.allocator})
	testing.expectf(t, materialized, "materialization failed with %v", failure.code)
	view, viewed, _ := registry_view(&registry, 1)
	testing.expect(t, viewed)
	if viewed {
		testing.expect_value(t, view.locations[0].annotation, "1:6")
		testing.expect_value(t, view.locations[0].preview_match_start, u32(8))
	}
}
