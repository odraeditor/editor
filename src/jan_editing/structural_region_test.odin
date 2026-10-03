// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../language"
import "core:mem"
import "core:testing"

/* Verifies complete targets are copied, source-ordered, planned, and published atomically. */
@(test)
structural_regions_publish_complete_multi_element_rewrites :: proc(t: ^testing.T) {
	source := ":NOTES:\nold\n:END:\n#+begin_quote\nbody\n#+end_quote\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 1_401) do return
	defer list_test_fixture_close(&fixture)
	drawer, drawer_found := list_test_node(&fixture.analysis, .Drawer, 0)
	block, block_found := list_test_node(&fixture.analysis, .Quote_Block, 0)
	testing.expect(t, drawer_found && block_found)
	if !drawer_found || !block_found do return
	input := [2]Target{navigation_target(block), navigation_target(drawer)}
	region: Structural_Region
	descriptor, prepared, failure := structural_region_prepare(
		&region,
		&fixture.analysis,
		u64(len(source)),
		81,
		fixture.scope,
		input[:],
	)
	testing.expectf(t, prepared, "region failed with %v", failure.code)
	if !prepared do return
	defer structural_region_close(&region)
	testing.expect_value(t, descriptor.target_count, u32(2))
	testing.expect(t, descriptor.retained_bytes > u64(size_of(Structural_Region_State)))
	owned := structural_region_targets(&region)
	testing.expect_value(t, owned[0].node_id, drawer.id)
	testing.expect_value(t, owned[1].node_id, block.id)
	input[0] = {}
	testing.expect_value(t, owned[1].node_id, block.id)

	replacements := [2]string{
		":NOTES:\nnew\n:END:\n",
		"#+begin_quote\nchanged λ\n#+end_quote\n",
	}
	plan: language.Jan_Rewrite_Plan
	planned, plan_failure := structural_region_plan_prepare(
		&plan,
		&region,
		&fixture.analysis,
		transmute([]u8)source,
		82,
		replacements[:],
	)
	testing.expectf(t, planned, "region plan failed with %v", plan_failure.code)
	if !planned do return
	defer language.jan_rewrite_plan_close(&plan)
	testing.expect(t, list_test_publish_and_history(
		&fixture,
		&plan,
		":NOTES:\nnew\n:END:\n#+begin_quote\nchanged λ\n#+end_quote\n",
	))
}

/* Verifies partial, overlapping, stale, malformed, and overflowing target sets reject first. */
@(test)
structural_regions_reject_incomplete_target_sets_atomically :: proc(t: ^testing.T) {
	source := "* Heading\n#+begin_quote\nbody\n#+end_quote\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 1_402) do return
	defer list_test_fixture_close(&fixture)
	heading, heading_found := list_test_node(&fixture.analysis, .Heading, 0)
	block, block_found := list_test_node(&fixture.analysis, .Quote_Block, 0)
	testing.expect(t, heading_found && block_found)
	if !heading_found || !block_found do return
	region: Structural_Region
	overlapping := [2]Target{navigation_target(heading), navigation_target(block)}
	_, prepared, failure := structural_region_prepare(
		&region,
		&fixture.analysis,
		u64(len(source)),
		83,
		fixture.scope,
		overlapping[:],
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Target)
	testing.expect(t, !structural_region_is_valid(&region))

	partial := [1]Target{navigation_target(block)}
	partial[0].range.end -= 1
	_, prepared, failure = structural_region_prepare(
		&region,
		&fixture.analysis,
		u64(len(source)),
		84,
		fixture.scope,
		partial[:],
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Target)

	stale := [1]Target{navigation_target(block)}
	stale[0].range.scope.source_revision += 1
	_, prepared, failure = structural_region_prepare(
		&region,
		&fixture.analysis,
		u64(len(source)),
		85,
		fixture.scope,
		stale[:],
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Stale)

	tiny := DEFAULT_LIMITS
	tiny.semantic_targets = 1
	_, prepared, failure = structural_region_prepare(
		&region,
		&fixture.analysis,
		u64(len(source)),
		86,
		fixture.scope,
		overlapping[:],
		tiny,
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Limited)
	testing.expect_value(t, failure.limit, u64(1))
	testing.expect_value(t, failure.actual, u64(2))

	malformed: List_Test_Fixture
	malformed_source := "#+begin_note\nbody\n"
	if !list_test_fixture_open(t, &malformed, malformed_source, 1_403) do return
	defer list_test_fixture_close(&malformed)
	malformed_block, malformed_found := list_test_node(&malformed.analysis, .Special_Block, 0)
	testing.expect(t, malformed_found)
	if !malformed_found do return
	malformed_targets := [1]Target{navigation_target(malformed_block)}
	_, prepared, failure = structural_region_prepare(
		&region,
		&malformed.analysis,
		u64(len(malformed_source)),
		87,
		malformed.scope,
		malformed_targets[:],
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Malformed)
}

/* Verifies each persistent region allocation can fail without leaking ownership. */
@(test)
structural_region_allocation_faults_release_state :: proc(t: ^testing.T) {
	source := ":NOTES:\nbody\n:END:\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 1_404) do return
	defer list_test_fixture_close(&fixture)
	drawer, found := list_test_node(&fixture.analysis, .Drawer, 0)
	testing.expect(t, found)
	if !found do return
	targets := [1]Target{navigation_target(drawer)}
	for fail_after in 0 ..< 2 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Visibility_Test_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		region: Structural_Region
		_, prepared, failure := structural_region_prepare(
			&region,
			&fixture.analysis,
			u64(len(source)),
			Operation_ID(90 + fail_after),
			fixture.scope,
			targets[:],
			allocator = visibility_test_failing_allocator(&failing),
		)
		testing.expect(t, !prepared)
		testing.expect_value(t, failure.code, Failure_Code.Allocation_Failed)
		testing.expect(t, !structural_region_is_valid(&region))
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}
