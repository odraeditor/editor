// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../editor"
import "../history"
import "../language"
import "../transaction"
import "core:mem"
import "core:testing"

/* Verifies heading insertion, splitting, and text promotion are atomic and undoable. */
@(test)
heading_editing_inserts_splits_and_promotes_text :: proc(t: ^testing.T) {
	heading_test_expect_edit(t, "* A\n", "* B\n* A\n", .Insert_Before, .Heading, 0, "B", 0, 0)
	heading_test_expect_edit(t, "* A\n", "* A\n* B\n", .Insert_After, .Heading, 0, "B", 0, 0)
	heading_test_expect_edit(t, "* A\nbody\n", "* A\n** B\nbody\n", .Insert_Below, .Heading, 0, "B", 0, 0)
	heading_test_expect_edit(
		t,
		"* Alpha Beta\nbody\n",
		"* Alpha\n* Beta\nbody\n",
		.Split,
		.Heading,
		0,
		"",
		8,
		0,
	)
	heading_test_expect_edit(
		t,
		"Paragraph λ\n",
		"* Paragraph λ\n",
		.Promote_Text,
		.Paragraph,
		0,
		"",
		0,
		1,
	)
}

/* Verifies subtree level, sibling movement, clone, kill, and child sorting behavior. */
@(test)
heading_editing_reorganizes_complete_subtrees :: proc(t: ^testing.T) {
	heading_test_expect_edit(
		t,
		"** A\nbody\n*** B\nchild\n",
		"* A\nbody\n** B\nchild\n",
		.Promote_Heading,
		.Heading,
		0,
		"",
		0,
		0,
	)
	heading_test_expect_edit(
		t,
		"* A\nbody\n** B\nchild\n",
		"** A\nbody\n*** B\nchild\n",
		.Demote_Heading,
		.Heading,
		0,
		"",
		0,
		0,
	)
	heading_test_expect_edit(
		t,
		"* A\nbody\n* B\nother\n",
		"* B\nother\n* A\nbody\n",
		.Move_Up,
		.Heading,
		1,
		"",
		0,
		0,
	)
	heading_test_expect_edit(
		t,
		"* A\nbody\n* B\nother\n",
		"* B\nother\n* A\nbody\n",
		.Move_Down,
		.Heading,
		0,
		"",
		0,
		0,
	)
	heading_test_expect_edit(
		t,
		"* A\nbody\n* B\n",
		"* A\nbody\n* A\nbody\n* B\n",
		.Clone_Subtree,
		.Heading,
		0,
		"",
		0,
		0,
	)
	heading_test_expect_edit(
		t,
		"* A\nbody\n* B\nother\n",
		"* A\nbody\n",
		.Kill_Subtree,
		.Heading,
		1,
		"",
		0,
		0,
	)
	heading_test_expect_edit(
		t,
		"* Parent\nintro\n** Zulu\nz\n** Alpha\na\n",
		"* Parent\nintro\n** Alpha\na\n** Zulu\nz\n",
		.Sort_Children,
		.Heading,
		0,
		"",
		0,
		0,
	)
}

/* Verifies representable heading/list conversions and explicit copied subtree insertion. */
@(test)
heading_editing_converts_and_copies_subtrees :: proc(t: ^testing.T) {
	heading_test_expect_edit(t, "* Item\n", "- Item\n", .Heading_To_List_Item, .Heading, 0, "", 0, 0)
	heading_test_expect_edit(t, "- Item\n", "** Item\n", .List_Item_To_Heading, .List_Item, 0, "", 0, 2)

	fixture: Heading_Test_Fixture
	ready := heading_test_fixture_open(t, &fixture, "* Alpha\na\n* Beta\nb\n", 904)
	if !ready do return
	defer heading_test_fixture_close(&fixture)
	alpha, alpha_ok := heading_test_node(&fixture.analysis, .Heading, 0)
	beta, beta_ok := heading_test_node(&fixture.analysis, .Heading, 1)
	testing.expect(t, alpha_ok && beta_ok)
	if !alpha_ok || !beta_ok do return
	copy_state: Subtree_Copy
	descriptor, copied, failure := subtree_copy_prepare(
		&copy_state,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		31,
		fixture.scope,
		alpha.id,
	)
	testing.expectf(t, copied, "copy failed with %v", failure.code)
	if !copied do return
	defer subtree_copy_close(&copy_state)
	testing.expect_value(t, descriptor.target.node_id, alpha.id)
	copy_text, inspected := subtree_copy_text(&copy_state)
	testing.expect(t, inspected)
	testing.expect_value(t, copy_text, "* Alpha\na\n")
	plan: language.Jan_Rewrite_Plan
	planned: bool
	planned, failure = subtree_insert_plan_prepare(
		&plan,
		&copy_state,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		fixture.scope,
		beta.id,
		true,
		31,
	)
	testing.expectf(t, planned, "insert failed with %v", failure.code)
	if !planned do return
	defer language.jan_rewrite_plan_close(&plan)
	testing.expect(t, heading_test_publish_and_history(
		t,
		&fixture,
		&plan,
		"* Alpha\na\n* Beta\nb\n* Alpha\na\n",
	))
}

/* Verifies stale, malformed, nonrepresentable, and allocation failures retain no state. */
@(test)
heading_editing_rejects_unsafe_requests_and_releases_copy :: proc(t: ^testing.T) {
	fixture: Heading_Test_Fixture
	ready := heading_test_fixture_open(t, &fixture, "* A\n** B\n#+begin_unterminated\n", 905)
	if !ready do return
	defer heading_test_fixture_close(&fixture)
	parent, parent_ok := heading_test_node(&fixture.analysis, .Heading, 0)
	testing.expect(t, parent_ok)
	if !parent_ok do return

	plan: language.Jan_Rewrite_Plan
	request := heading_test_request(fixture.scope, .Promote_Heading, parent.id)
	planned: bool
	failure: Failure
	planned, failure = heading_edit_plan_prepare(
		&plan,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		request,
	)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Failure_Code.Malformed)

	stale := fixture.scope
	stale.analysis.source_revision += 1
	request = heading_test_request(stale, .Kill_Subtree, parent.id)
	planned, failure = heading_edit_plan_prepare(
		&plan,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		request,
	)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Failure_Code.Stale)

	clean: Heading_Test_Fixture
	clean_ready := heading_test_fixture_open(t, &clean, "* Clean\n", 906)
	if !clean_ready do return
	defer heading_test_fixture_close(&clean)
	clean_heading, clean_heading_ok := heading_test_node(&clean.analysis, .Heading, 0)
	testing.expect(t, clean_heading_ok)
	if !clean_heading_ok do return
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Visibility_Test_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = 0,
	}
	copy_state: Subtree_Copy
	copied: bool
	_, copied, failure = subtree_copy_prepare(
		&copy_state,
		&clean.analysis,
		transmute([]u8)clean.source,
		32,
		clean.scope,
		clean_heading.id,
		visibility_test_failing_allocator(&failing),
	)
	testing.expect(t, !copied)
	testing.expect_value(t, failure.code, Failure_Code.Allocation_Failed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)

	mem.tracking_allocator_init(&tracking, context.allocator)
	failing = {
		backing = mem.tracking_allocator(&tracking),
		fail_after = 0,
	}
	request = heading_test_request(clean.scope, .Insert_After, clean_heading.id)
	request.text = "Other"
	planned, failure = heading_edit_plan_prepare(
		&plan,
		&clean.analysis,
		transmute([]u8)clean.source,
		request,
		DEFAULT_LIMITS,
		context.allocator,
		visibility_test_failing_allocator(&failing),
	)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Failure_Code.Allocation_Failed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

@(private = "file")
Heading_Test_Fixture :: struct {
	buffer:   editor.Buffer,
	owner:    language.Jan_Structural_Owner,
	analysis: language.Jan_Structural_Analysis,
	scope:    Scope,
	source:   string,
}

@(private = "file")
heading_test_expect_edit :: proc(
	t: ^testing.T,
	source, expected: string,
	kind: Heading_Edit_Kind,
	target_kind: language.Jan_Node_Kind,
	ordinal: int,
	text: string,
	split: editor.Byte_Offset,
	level: u16,
) {
	fixture: Heading_Test_Fixture
	id := u64(920 + int(kind) * 4 + ordinal)
	if !heading_test_fixture_open(t, &fixture, source, id) do return
	defer heading_test_fixture_close(&fixture)
	target, found := heading_test_node(&fixture.analysis, target_kind, ordinal)
	testing.expect(t, found)
	if !found do return
	request := heading_test_request(fixture.scope, kind, target.id)
	request.text = text
	request.split_offset = split
	request.level = level
	plan: language.Jan_Rewrite_Plan
	planned, failure := heading_edit_plan_prepare(
		&plan,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		request,
	)
	testing.expectf(t, planned, "%v plan failed with %v", kind, failure.code)
	if !planned do return
	defer language.jan_rewrite_plan_close(&plan)
	testing.expect(t, heading_test_publish_and_history(t, &fixture, &plan, expected))
}

@(private = "file")
heading_test_publish_and_history :: proc(
	t: ^testing.T,
	fixture: ^Heading_Test_Fixture,
	plan: ^language.Jan_Rewrite_Plan,
	expected: string,
) -> bool {
	store: history.Store
	store_ok, _ := history.store_init(
		&store,
		91,
		fixture.scope.analysis.buffer_id,
		fixture.scope.analysis.source_revision,
		history.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	if !store_ok do return false
	defer history.store_close(&store)
	root: transaction.Transaction
	started, _ := transaction.transaction_begin(
		&root,
		91,
		91,
		&fixture.buffer,
		{kind = .Language_Tool, descriptor = "jan"},
		"jan-heading-edit",
		transaction.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	if !started do return false
	applied, _ := transaction.transaction_apply_batch(
		&root,
		language.jan_rewrite_plan_transaction_batch(plan),
	)
	tracked, _ := transaction.transaction_track_history(&root, &store)
	validated, _ := transaction.transaction_validate(&root)
	_, committed, _ := transaction.transaction_commit(&root)
	transaction.transaction_close(&root)
	if !applied || !tracked || !validated || !committed ||
	   !heading_test_buffer_matches(&fixture.buffer, expected) {
		return false
	}
	_, undone, _ := transaction.transaction_history_navigate(
		&store,
		&fixture.buffer,
		.Undo,
		92,
		92,
		transaction.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	if !undone || !heading_test_buffer_matches(&fixture.buffer, fixture.source) do return false
	_, redone, _ := transaction.transaction_history_navigate(
		&store,
		&fixture.buffer,
		.Redo,
		93,
		93,
		transaction.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	return redone && heading_test_buffer_matches(&fixture.buffer, expected)
}

@(private = "file")
heading_test_fixture_open :: proc(
	t: ^testing.T,
	fixture: ^Heading_Test_Fixture,
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
	owner_ok, failure := language.jan_structural_owner_init(&fixture.owner, 1)
	fixture.scope = editing_test_scope(editor.Buffer_ID(id), 0)
	fixture.scope.analysis.configuration = language.jan_factory_configuration(1).identity
	analysis_ok := false
	if owner_ok {
		fixture.analysis, analysis_ok, failure = language.jan_structural_owner_analyze(
			&fixture.owner,
			transmute([]u8)source,
			fixture.scope.analysis,
		)
	}
	testing.expectf(t, buffer_ok && owner_ok && analysis_ok, "heading fixture failed with %v", failure.code)
	return buffer_ok && owner_ok && analysis_ok
}

@(private = "file")
heading_test_fixture_close :: proc(fixture: ^Heading_Test_Fixture) {
	language.jan_structural_analysis_close(&fixture.analysis)
	language.jan_structural_owner_close(&fixture.owner)
	_, _ = editor.buffer_close(&fixture.buffer)
}

@(private = "file")
heading_test_request :: proc(
	scope: Scope,
	kind: Heading_Edit_Kind,
	target_id: language.Jan_Node_ID,
) -> Heading_Edit_Request {
	return {
		operation_id = 41,
		scope = scope,
		kind = kind,
		target_id = target_id,
		rewrite_generation = 41,
	}
}

@(private = "file")
heading_test_node :: proc(
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
heading_test_buffer_matches :: proc(buffer: ^editor.Buffer, expected: string) -> bool {
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(buffer, &snapshot)
	if !opened do return false
	defer editor.buffer_snapshot_close(&snapshot)
	stats, stats_ok, _ := editor.buffer_snapshot_stats(&snapshot)
	if !stats_ok || stats.text_bytes != u64(len(expected)) do return false
	actual, allocation_error := make([]u8, len(expected), context.temp_allocator)
	if allocation_error != nil do return false
	defer delete(actual, context.temp_allocator)
	copied, copied_ok, _ := editor.buffer_snapshot_read(&snapshot, 0, actual)
	return copied_ok && copied == u64(len(expected)) && string(actual) == expected
}
