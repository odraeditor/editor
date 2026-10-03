// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package result_set

import "../editor"
import "core:mem"
import "core:testing"

Test_Publication_Storage :: struct {
	groups: [1]Group_Definition,
	locations: [2]Location_Definition,
}

test_publication :: proc(storage: ^Test_Publication_Storage,
	set_id := Result_Set_ID(7), expected := Result_Set_Generation(0)) -> Publication {
	storage.groups = {{id = 1, label = "main.odin"}}
	storage.locations = {
		{id = 11, group_id = 1, buffer_id = editor.Buffer_ID(2), revision = 3,
			start = 4, end = 9, source_identity = 101, preview = "alpha", annotation = "1:5"},
		{id = 12, group_id = 1, buffer_id = editor.Buffer_ID(2), revision = 3,
			start = 14, end = 19, source_identity = 102, preview = "alpha", annotation = "2:5"},
	}
	return Publication{set_id = set_id, expected_generation = expected,
		source = Source_Descriptor{id = 3, generation = 4, kind = .Active_Search},
		completeness = .Complete, edit_capability = .Single_Buffer,
		refresh = Refresh_Descriptor{provider = 3, query_identity = 9, policy_generation = 2, scope_generation = 5},
		groups = storage.groups[:], locations = storage.locations[:],
		has_selection = true, selected = 11}
}

/* Ensures published result generations own immutable copies of provider data. */
@(test)
registry_publishes_copied_immutable_generations :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	registry: Registry
	ready, _ := registry_init(&registry, Config{limits = DEFAULT_LIMITS, allocator = allocator})
	testing.expect(t, ready)
	storage: Test_Publication_Storage
	proposal := test_publication(&storage)
	result, published, failure := registry_publish(&registry, proposal)
	testing.expectf(t, published, "publication failed with %v", failure.code)
	testing.expect_value(t, result.generation, Result_Set_Generation(1))
	view, viewed, _ := registry_view(&registry, 7)
	testing.expect(t, viewed)
	testing.expect_value(t, len(view.locations), 2)
	testing.expect_value(t, view.locations[view.selected_index].id, Location_ID(11))
	testing.expect_value(t, view.locations[0].preview, "alpha")
	proposal.locations[0].preview = "changed"
	view, _, _ = registry_view(&registry, 7)
	testing.expect_value(t, view.locations[0].preview, "alpha")
	closed, _ := registry_close(&registry)
	testing.expect(t, closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Ensures refresh retains selection when the logical result still exists. */
@(test)
registry_refresh_preserves_stable_selection :: proc(t: ^testing.T) {
	registry: Registry
	ready, _ := registry_init(&registry, Config{limits = DEFAULT_LIMITS, allocator = context.allocator})
	testing.expect(t, ready)
	first_storage: Test_Publication_Storage
	first := test_publication(&first_storage)
	_, published, _ := registry_publish(&registry, first)
	testing.expect(t, published)
	_, moved, _ := registry_move(&registry, 7, 1, .Last)
	testing.expect(t, moved)
	second_storage: Test_Publication_Storage
	second := test_publication(&second_storage, expected = 1)
	second.has_selection = false
	second.locations[0], second.locations[1] = second.locations[1], second.locations[0]
	result, refreshed, _ := registry_publish(&registry, second)
	testing.expect(t, refreshed)
	testing.expect_value(t, result.generation, Result_Set_Generation(2))
	testing.expect_value(t, result.location_id, Location_ID(12))
	testing.expect_value(t, result.selected_index, u32(0))
	registry_close(&registry)
}

/* Ensures navigation follows normalized location order rather than insertion order. */
@(test)
registry_navigation_uses_location_order :: proc(t: ^testing.T) {
	registry: Registry
	registry_init(&registry, Config{limits = DEFAULT_LIMITS, allocator = context.allocator})
	storage: Test_Publication_Storage
	registry_publish(&registry, test_publication(&storage))
	last, ok, _ := registry_move(&registry, 7, 1, .Last)
	testing.expect(t, ok)
	testing.expect_value(t, last.location_id, Location_ID(12))
	previous, previous_ok, _ := registry_move(&registry, 7, 1, .Previous)
	testing.expect(t, previous_ok)
	testing.expect_value(t, previous.location_id, Location_ID(11))
	first, first_ok, _ := registry_move(&registry, 7, 1, .First)
	testing.expect(t, first_ok)
	testing.expect_value(t, first.transition, Transition.No_Change)
	registry_close(&registry)
}

/* Ensures selection identifies one exact source location across duplicate text. */
@(test)
registry_selects_exact_location_identity :: proc(t: ^testing.T) {
	registry: Registry
	registry_init(&registry, Config{limits = DEFAULT_LIMITS, allocator = context.allocator})
	storage: Test_Publication_Storage
	registry_publish(&registry, test_publication(&storage))
	selected, selected_ok, _ := registry_select(&registry, 7, 1, 12)
	testing.expect(t, selected_ok)
	testing.expect_value(t, selected.location_id, Location_ID(12))
	_, missing_ok, missing_failure := registry_select(&registry, 7, 1, 99)
	testing.expect(t, !missing_ok)
	testing.expect_value(t, missing_failure.code, Failure_Code.Invalid_Location)
	registry_close(&registry)
}

/* Ensures stale, duplicate, and oversized result publications remain atomic. */
@(test)
rejects_invalid_resource_publications :: proc(t: ^testing.T) {
	limits := DEFAULT_LIMITS
	limits.locations = 1
	registry: Registry
	registry_init(&registry, Config{limits = limits, allocator = context.allocator})
	limit_storage: Test_Publication_Storage
	_, ok, failure := registry_publish(&registry, test_publication(&limit_storage))
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Location_Limit)
	registry_close(&registry)

	registry_init(&registry, Config{limits = DEFAULT_LIMITS, allocator = context.allocator})
	duplicate_storage: Test_Publication_Storage
	proposal := test_publication(&duplicate_storage)
	proposal.locations[1].id = proposal.locations[0].id
	_, ok, failure = registry_publish(&registry, proposal)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Duplicate_Identity)
	valid_storage: Test_Publication_Storage
	registry_publish(&registry, test_publication(&valid_storage))
	stale_storage: Test_Publication_Storage
	stale := test_publication(&stale_storage, expected = 9)
	_, ok, failure = registry_publish(&registry, stale)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Generation)
	registry_close(&registry)
}

/* Ensures registry accounting and closure agree with all owned allocations. */
@(test)
registry_reports_accounting_and_checked_close :: proc(t: ^testing.T) {
	registry: Registry
	registry_init(&registry, Config{limits = DEFAULT_LIMITS, allocator = context.allocator})
	storage: Test_Publication_Storage
	registry_publish(&registry, test_publication(&storage))
	usage, inspected, _ := registry_inspect(&registry)
	testing.expect(t, inspected)
	testing.expect_value(t, usage.sets, u32(1))
	testing.expect_value(t, usage.locations, u32(2))
	_, closed, _ := registry_close_set(&registry, 7, 1)
	testing.expect(t, closed)
	usage, _, _ = registry_inspect(&registry)
	testing.expect_value(t, usage.sets, u32(0))
	registry_close(&registry)
}
