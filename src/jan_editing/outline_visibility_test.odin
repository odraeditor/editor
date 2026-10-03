// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../editor"
import "../language"
import "../view"
import "core:mem"
import "core:testing"

/* Verifies local and global outline states publish independently per view. */
@(test)
outline_visibility_publishes_independent_views :: proc(t: ^testing.T) {
	fixture: Outline_Visibility_Test_Fixture
	ready := outline_visibility_test_open(
		t,
		&fixture,
		"* Alpha\nbody\n** Beta\nchild\n*** Gamma\ndeep\n** Delta\nlast\n* Epsilon\n",
		801,
	)
	if !ready do return
	defer outline_visibility_test_close(t, &fixture)
	alpha, found := outline_visibility_test_heading(&fixture.analysis, 1, 0)
	testing.expect(t, found)
	if !found do return

	first_scope := outline_visibility_test_scope(&fixture, fixture.first)
	transition: Visibility_Transition
	descriptor, prepared, failure := outline_visibility_prepare(
		&transition,
		&fixture.registry,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		{
			operation_id = 21,
			scope = first_scope,
			kind = .Local,
			current = .Complete_Subtree,
			heading_id = alpha.id,
		},
	)
	testing.expectf(t, prepared, "local visibility failed with %v", failure.code)
	testing.expect_value(t, descriptor.next, Visibility_State.Heading_Only)
	published: bool
	_, published, failure = visibility_transition_publish(&transition, &fixture.registry)
	testing.expectf(t, published, "local visibility publication failed with %v", failure.code)

	first_snapshot, first_ok, _ := view.snapshot(&fixture.registry, fixture.first)
	second_snapshot, second_ok, _ := view.snapshot(&fixture.registry, fixture.second)
	testing.expect(t, first_ok && second_ok)
	testing.expect(t, first_snapshot.hidden_range_count > 0)
	testing.expect_value(t, second_snapshot.hidden_range_count, u32(0))

	second_scope := outline_visibility_test_scope(&fixture, fixture.second)
	global: Visibility_Transition
	descriptor, prepared, failure = outline_visibility_prepare(
		&global,
		&fixture.registry,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		{
			operation_id = 22,
			scope = second_scope,
			kind = .Global,
			current = .Invalid,
			selected = .Overview,
		},
	)
	testing.expectf(t, prepared, "startup visibility failed with %v", failure.code)
	testing.expect_value(t, descriptor.next, Visibility_State.Overview)
	_, published, failure = visibility_transition_publish(&global, &fixture.registry)
	testing.expectf(t, published, "startup visibility publication failed with %v", failure.code)
	second_snapshot, second_ok, _ = view.snapshot(&fixture.registry, fixture.second)
	testing.expect(t, second_ok)
	testing.expect(t, second_snapshot.hidden_range_count > 0)
}

/* Verifies direct-children ranges, minimum reveal, and revision transformation. */
@(test)
outline_visibility_reveals_targets_and_tracks_revisions :: proc(t: ^testing.T) {
	fixture: Outline_Visibility_Test_Fixture
	ready := outline_visibility_test_open(
		t,
		&fixture,
		"* Alpha\nbody\n** Beta\nchild\n*** Gamma\ndeep\n** Delta\nlast\n",
		802,
	)
	if !ready do return
	defer outline_visibility_test_close(t, &fixture)
	alpha, alpha_ok := outline_visibility_test_heading(&fixture.analysis, 1, 0)
	gamma, gamma_ok := outline_visibility_test_heading(&fixture.analysis, 3, 0)
	testing.expect(t, alpha_ok && gamma_ok)
	if !alpha_ok || !gamma_ok do return

	scope := outline_visibility_test_scope(&fixture, fixture.first)
	transition: Visibility_Transition
	_, prepared, failure := outline_visibility_prepare(
		&transition,
		&fixture.registry,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		{
			operation_id = 23,
			scope = scope,
			kind = .Local,
			current = .Heading_Only,
			selected = .Direct_Children,
			heading_id = alpha.id,
		},
	)
	testing.expectf(t, prepared, "direct children failed with %v", failure.code)
	published: bool
	_, published, failure = visibility_transition_publish(&transition, &fixture.registry)
	testing.expectf(t, published, "direct children publication failed with %v", failure.code)

	ranges: [16]view.Hidden_Range
	visibility, copied, _ := view.visibility_copy_ranges(
		&fixture.registry,
		fixture.first,
		ranges[:],
	)
	testing.expect(t, copied)
	testing.expect(t, visibility.range_count >= 2)

	scope = outline_visibility_test_scope(&fixture, fixture.first)
	target := navigation_target(gamma)
	update, revealed, reveal_failure := outline_visibility_reveal_target(
		&fixture.registry,
		scope,
		target,
		u64(len(fixture.source)),
	)
	testing.expectf(t, revealed, "target reveal failed with %v", reveal_failure.code)
	testing.expect(t, update.range_count < visibility.range_count)

	position, positioned, _ := editor.buffer_position(&fixture.buffer, 0)
	testing.expect(t, positioned)
	_, _, changed, _ := editor.buffer_splice(
		&fixture.buffer,
		{start = position, end = position, replacement = "Intro\n"},
		context.temp_allocator,
	)
	testing.expect(t, changed)
	visibility, copied, _ = view.visibility_copy_ranges(
		&fixture.registry,
		fixture.first,
		ranges[:],
	)
	testing.expect(t, copied)
	testing.expect_value(t, visibility.source_revision, editor.Revision(1))
}

/* Verifies invalid targets, stale views, malformed subtrees, and range limits reject. */
@(test)
outline_visibility_rejects_unsafe_candidates :: proc(t: ^testing.T) {
	fixture: Outline_Visibility_Test_Fixture
	ready := outline_visibility_test_open(
		t,
		&fixture,
		"* Alpha\n#+begin_unterminated\nbody\n",
		803,
	)
	if !ready do return
	defer outline_visibility_test_close(t, &fixture)
	alpha, found := outline_visibility_test_heading(&fixture.analysis, 1, 0)
	testing.expect(t, found)
	if !found do return
	scope := outline_visibility_test_scope(&fixture, fixture.first)
	transition: Visibility_Transition
	_, prepared, failure := outline_visibility_prepare(
		&transition,
		&fixture.registry,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		{
			operation_id = 24,
			scope = scope,
			kind = .Local,
			current = .Complete_Subtree,
			heading_id = alpha.id,
		},
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Malformed)

	scope.view_state_generation += 1
	_, prepared, failure = outline_visibility_prepare(
		&transition,
		&fixture.registry,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		{
			operation_id = 25,
			scope = scope,
			kind = .Global,
			selected = .Show_All,
		},
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Stale)
}

/* Verifies one drawer toggles independently without changing source or another view. */
@(test)
drawer_visibility_toggles_one_view_without_source_changes :: proc(t: ^testing.T) {
	fixture: Outline_Visibility_Test_Fixture
	ready := outline_visibility_test_open(
		t,
		&fixture,
		"* Alpha\n:PROPERTIES:\n:Owner: Ada\n:END:\n:NOTES:\none\n:END:\n",
		804,
	)
	if !ready do return
	defer outline_visibility_test_close(t, &fixture)
	drawer, found := outline_visibility_test_node(&fixture.analysis, .Property_Drawer, 0)
	testing.expect(t, found)
	if !found do return
	before, before_ok, _ := editor.buffer_stats(&fixture.buffer)
	testing.expect(t, before_ok)

	scope := outline_visibility_test_scope(&fixture, fixture.first)
	transition: Visibility_Transition
	descriptor, prepared, failure := drawer_visibility_prepare(
		&transition,
		&fixture.registry,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		{operation_id = 31, scope = scope, target_id = drawer.id},
	)
	testing.expectf(t, prepared, "drawer fold failed with %v", failure.code)
	testing.expect_value(t, descriptor.kind, Visibility_Kind.Drawer)
	testing.expect_value(t, descriptor.next, Visibility_State.Drawer_Folded)
	result: Visibility_Result
	published: bool
	result, published, failure = visibility_transition_publish(&transition, &fixture.registry)
	testing.expectf(t, published, "drawer fold publication failed with %v", failure.code)
	testing.expect_value(t, result.view.range_count, u32(1))

	first, first_ok, _ := view.snapshot(&fixture.registry, fixture.first)
	second, second_ok, _ := view.snapshot(&fixture.registry, fixture.second)
	testing.expect(t, first_ok && second_ok)
	testing.expect_value(t, first.hidden_range_count, u32(1))
	testing.expect_value(t, second.hidden_range_count, u32(0))

	scope = outline_visibility_test_scope(&fixture, fixture.first)
	descriptor, prepared, failure = drawer_visibility_prepare(
		&transition,
		&fixture.registry,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		{operation_id = 32, scope = scope, target_id = drawer.id},
	)
	testing.expectf(t, prepared, "drawer reveal failed with %v", failure.code)
	testing.expect_value(t, descriptor.next, Visibility_State.Drawer_Visible)
	result, published, failure = visibility_transition_publish(&transition, &fixture.registry)
	testing.expectf(t, published, "drawer reveal publication failed with %v", failure.code)
	testing.expect_value(t, result.view.range_count, u32(0))
	after, after_ok, _ := editor.buffer_stats(&fixture.buffer)
	testing.expect(t, after_ok)
	testing.expect_value(t, after.revision, before.revision)
	testing.expect_value(t, after.text_bytes, before.text_bytes)
}

/* Verifies invalid, stale, hidden, limited, and allocation-failed drawer toggles reject. */
@(test)
drawer_visibility_rejects_unsafe_candidates :: proc(t: ^testing.T) {
	fixture: Outline_Visibility_Test_Fixture
	ready := outline_visibility_test_open(
		t,
		&fixture,
		"* Alpha\n:NOTES:\none\n:END:\n:LOGBOOK:\ntwo\n:END:\n",
		805,
	)
	if !ready do return
	defer outline_visibility_test_close(t, &fixture)
	first_drawer, first_found := outline_visibility_test_node(&fixture.analysis, .Drawer, 0)
	second_drawer, second_found := outline_visibility_test_node(&fixture.analysis, .Drawer, 1)
	heading, heading_found := outline_visibility_test_node(&fixture.analysis, .Heading, 0)
	testing.expect(t, first_found && second_found && heading_found)
	if !first_found || !second_found || !heading_found do return

	scope := outline_visibility_test_scope(&fixture, fixture.first)
	transition: Visibility_Transition
	_, prepared, failure := drawer_visibility_prepare(
		&transition,
		&fixture.registry,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		{operation_id = 33, scope = scope, target_id = heading.id},
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Target)

	stale := scope
	stale.view_state_generation += 1
	_, prepared, failure = drawer_visibility_prepare(
		&transition,
		&fixture.registry,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		{operation_id = 34, scope = stale, target_id = first_drawer.id},
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Stale)

	hidden := outline_visibility_test_range(fixture.scope, first_drawer.range.start, first_drawer.range.end)
	_, hidden_ok, _ := view.visibility_replace(&fixture.registry, fixture.first, []view.Hidden_Range{hidden})
	testing.expect(t, hidden_ok)
	scope = outline_visibility_test_scope(&fixture, fixture.first)
	_, prepared, failure = drawer_visibility_prepare(
		&transition,
		&fixture.registry,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		{operation_id = 35, scope = scope, target_id = first_drawer.id},
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Hidden_Target)
	retained, retained_ok, _ := view.snapshot(&fixture.registry, fixture.first)
	testing.expect(t, retained_ok)
	testing.expect_value(t, retained.hidden_range_count, u32(1))
	_, cleared, _ := view.visibility_clear(&fixture.registry, fixture.first)
	testing.expect(t, cleared)

	scope = outline_visibility_test_scope(&fixture, fixture.first)
	_, prepared, failure = drawer_visibility_prepare(
		&transition,
		&fixture.registry,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		{operation_id = 36, scope = scope, target_id = first_drawer.id},
	)
	testing.expect(t, prepared)
	_, published, _ := visibility_transition_publish(&transition, &fixture.registry)
	testing.expect(t, published)
	limits := DEFAULT_LIMITS
	limits.hidden_ranges = 1
	scope = outline_visibility_test_scope(&fixture, fixture.first)
	_, prepared, failure = drawer_visibility_prepare(
		&transition,
		&fixture.registry,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		{operation_id = 37, scope = scope, target_id = second_drawer.id},
		limits,
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Limited)
	testing.expect_value(t, failure.limit, u64(1))
	testing.expect_value(t, failure.actual, u64(2))
	_, cleared, _ = view.visibility_clear(&fixture.registry, fixture.first)
	testing.expect(t, cleared)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Visibility_Test_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = 0,
	}
	scope = outline_visibility_test_scope(&fixture, fixture.first)
	_, prepared, failure = drawer_visibility_prepare(
		&transition,
		&fixture.registry,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		{operation_id = 38, scope = scope, target_id = first_drawer.id},
		DEFAULT_LIMITS,
		context.allocator,
		visibility_test_failing_allocator(&failing),
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Allocation_Failed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)

	malformed: Outline_Visibility_Test_Fixture
	malformed_ready := outline_visibility_test_open(
		t,
		&malformed,
		":LOGBOOK:\n#+begin_note\nbody\n:END:\n",
		806,
	)
	if !malformed_ready do return
	defer outline_visibility_test_close(t, &malformed)
	malformed_drawer, malformed_found := outline_visibility_test_node(
		&malformed.analysis,
		.Drawer,
		0,
	)
	testing.expect(t, malformed_found)
	if !malformed_found do return
	malformed_scope := outline_visibility_test_scope(&malformed, malformed.first)
	_, prepared, failure = drawer_visibility_prepare(
		&transition,
		&malformed.registry,
		&malformed.analysis,
		transmute([]u8)malformed.source,
		{operation_id = 39, scope = malformed_scope, target_id = malformed_drawer.id},
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Malformed)
}

@(private = "file")
Outline_Visibility_Test_Fixture :: struct {
	buffer:   editor.Buffer,
	registry: view.Registry,
	first:    view.View_Handle,
	second:   view.View_Handle,
	owner:    language.Jan_Structural_Owner,
	analysis: language.Jan_Structural_Analysis,
	scope:    language.Jan_Analysis_Scope,
	source:   string,
}

@(private = "file")
outline_visibility_test_open :: proc(
	t: ^testing.T,
	fixture: ^Outline_Visibility_Test_Fixture,
	source: string,
	id: u64,
) -> bool {
	fixture.source = source
	buffer_ok, _ := editor.buffer_init(
		&fixture.buffer,
		editor.Buffer_ID(id),
		source,
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	registry_ok, _ := view.registry_init(&fixture.registry, view.Registry_ID(id), context.allocator)
	first_ok, second_ok: bool
	if buffer_ok && registry_ok {
		fixture.first, first_ok, _ = view.create(&fixture.registry, &fixture.buffer)
		if first_ok {
			fixture.second, second_ok, _ = view.clone_additional(&fixture.registry, fixture.first)
		}
	}
	owner_ok, owner_failure := language.jan_structural_owner_init(&fixture.owner, 1)
	fixture.scope = editing_test_scope(editor.Buffer_ID(id), 0).analysis
	fixture.scope.configuration = language.jan_factory_configuration(1).identity
	analysis_ok := false
	if owner_ok {
		fixture.analysis, analysis_ok, owner_failure = language.jan_structural_owner_analyze(
			&fixture.owner,
			transmute([]u8)source,
			fixture.scope,
		)
	}
	testing.expectf(
		t,
		buffer_ok && registry_ok && first_ok && second_ok && owner_ok && analysis_ok,
		"outline fixture failed with %v",
		owner_failure.code,
	)
	return buffer_ok && registry_ok && first_ok && second_ok && owner_ok && analysis_ok
}

@(private = "file")
outline_visibility_test_close :: proc(t: ^testing.T, fixture: ^Outline_Visibility_Test_Fixture) {
	language.jan_structural_analysis_close(&fixture.analysis)
	language.jan_structural_owner_close(&fixture.owner)
	first_closed, _ := view.close(&fixture.registry, &fixture.first)
	second_closed, _ := view.close(&fixture.registry, &fixture.second)
	registry_closed, _ := view.registry_close(&fixture.registry)
	buffer_closed, _ := editor.buffer_close(&fixture.buffer)
	testing.expect(t, first_closed && second_closed && registry_closed && buffer_closed)
}

@(private = "file")
outline_visibility_test_scope :: proc(
	fixture: ^Outline_Visibility_Test_Fixture,
	handle: view.View_Handle,
) -> Scope {
	snapshot, ok, _ := view.snapshot(&fixture.registry, handle)
	assert(ok)
	scope := editing_test_scope(snapshot.buffer_id, snapshot.revision)
	scope.analysis = fixture.scope
	scope.view_handle = handle
	scope.view_state_generation = snapshot.state_generation
	scope.visibility_generation = snapshot.visibility_generation
	return scope
}

@(private = "file")
outline_visibility_test_heading :: proc(
	analysis: ^language.Jan_Structural_Analysis,
	depth: u16,
	ordinal: int,
) -> (language.Jan_Node_Record, bool) {
	seen: int
	for node in language.jan_structural_analysis_nodes(analysis) {
		if node.kind != .Heading || node.structural_depth != depth do continue
		if seen == ordinal do return node, true
		seen += 1
	}
	return {}, false
}

@(private = "file")
outline_visibility_test_node :: proc(
	analysis: ^language.Jan_Structural_Analysis,
	kind: language.Jan_Node_Kind,
	ordinal: int,
) -> (language.Jan_Node_Record, bool) {
	seen: int
	for node in language.jan_structural_analysis_nodes(analysis) {
		if node.kind != kind do continue
		if seen == ordinal do return node, true
		seen += 1
	}
	return {}, false
}

@(private = "file")
outline_visibility_test_range :: proc(
	scope: language.Jan_Analysis_Scope,
	start, end: editor.Byte_Offset,
) -> view.Hidden_Range {
	return {
		start = {buffer_id = scope.buffer_id, revision = scope.source_revision, byte_offset = start},
		end = {buffer_id = scope.buffer_id, revision = scope.source_revision, byte_offset = end},
	}
}
