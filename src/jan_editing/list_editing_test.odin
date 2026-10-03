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

/* Verifies insertion, deletion, nesting, movement, and duplication preserve complete items. */
@(test)
list_editing_reorganizes_complete_items :: proc(t: ^testing.T) {
	list_test_expect_edit(t, "- Alpha\n", "- Beta\n- Alpha\n", .Insert_Before, .List_Item, 0, "Beta", .Unordered_Dash, 0, 0)
	list_test_expect_edit(t, "1. Alpha\n", "1. Alpha\n1. Beta\n", .Insert_After, .List_Item, 0, "Beta", .Ordered_Dot, 0, 0)
	list_test_expect_edit(t, "- term :: value\n", "- next :: other\n- term :: value\n", .Insert_Before, .List_Item, 0, "next :: other", .Descriptive, 0, 0)
	list_test_expect_edit(
		t,
		"- Alpha\n  continuation λ\n  - Child\n- Beta\n",
		"- Beta\n",
		.Delete_Item,
		.List_Item,
		0,
		"",
		.Invalid,
		0,
		0,
	)
	list_test_expect_edit(t, "  - Child\n", "- Child\n", .Promote_Item, .List_Item, 0, "", .Invalid, 0, 2)
	list_test_expect_edit(t, "- Parent\n  body\n", "  - Parent\n    body\n", .Demote_Item, .List_Item, 0, "", .Invalid, 0, 2)
	list_test_expect_edit(t, "- Alpha\n- Beta\n", "- Beta\n- Alpha\n", .Move_Down, .List_Item, 0, "", .Invalid, 0, 0)
	list_test_expect_edit(t, "- Alpha\n- Beta\n", "- Beta\n- Alpha\n", .Move_Up, .List_Item, 1, "", .Invalid, 0, 0)
	list_test_expect_edit(t, "- Alpha\n  body\n- Beta\n", "- Alpha\n  body\n- Alpha\n  body\n- Beta\n", .Duplicate_Item, .List_Item, 0, "", .Invalid, 0, 0)
}

/* Verifies sorting, marker selection, counters, indentation repair, and region conversion. */
@(test)
list_editing_changes_plain_list_representation :: proc(t: ^testing.T) {
	list_test_expect_edit(
		t,
		"- Zulu\n- Alpha\n",
		"- Alpha\n- Zulu\n",
		.Sort_Items,
		.Plain_List,
		0,
		"",
		.Invalid,
		0,
		0,
	)
	list_test_expect_edit(t, "- [X] Done λ\n", "+ [X] Done λ\n", .Select_Bullet, .List_Item, 0, "", .Unordered_Plus, 0, 0)
	list_test_expect_edit(t, "1. [@2] Alpha\n", "1. [@7] Alpha\n", .Set_Counter, .List_Item, 0, "", .Invalid, 7, 0)
	list_test_expect_edit(t, "- Alpha\n body\n", "- Alpha\n  body\n", .Repair_Indentation, .List_Item, 0, "", .Invalid, 0, 2)
	list_test_expect_edit(t, "Alpha\nBeta λ\n", "- Alpha\n- Beta λ\n", .Convert_Region, .Paragraph, 0, "", .Unordered_Dash, 0, 0)
}

/* Verifies stale, malformed, invalid, bounded, and allocation-failure rejection. */
@(test)
list_editing_rejects_unsafe_requests_without_retained_state :: proc(t: ^testing.T) {
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, "- Alpha\n", 981) do return
	defer list_test_fixture_close(&fixture)
	item, found := list_test_node(&fixture.analysis, .List_Item, 0)
	testing.expect(t, found)
	if !found do return
	plan: language.Jan_Rewrite_Plan
	request := list_test_request(fixture.scope, .Move_Up, item.id)
	planned, failure := list_edit_plan_prepare(&plan, &fixture.analysis, transmute([]u8)fixture.source, request)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.operation, Operation.Plan_List_Edit)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Target)

	request.scope.analysis.source_revision += 1
	planned, failure = list_edit_plan_prepare(&plan, &fixture.analysis, transmute([]u8)fixture.source, request)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Failure_Code.Stale)

	request = list_test_request(fixture.scope, .Insert_After, item.id)
	request.bullet = .Unordered_Dash
	request.text = "Beta"
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Visibility_Test_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = 0,
	}
	planned, failure = list_edit_plan_prepare(
		&plan,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		request,
		DEFAULT_LIMITS,
		context.allocator,
		visibility_test_failing_allocator(&failing),
	)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Failure_Code.Allocation_Failed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)

	malformed: List_Test_Fixture
	if !list_test_fixture_open(t, &malformed, "- Alpha\n  #+begin_src\n", 982) do return
	defer list_test_fixture_close(&malformed)
	malformed_item, malformed_found := list_test_node(&malformed.analysis, .List_Item, 0)
	testing.expect(t, malformed_found)
	if !malformed_found do return
	request = list_test_request(malformed.scope, .Delete_Item, malformed_item.id)
	planned, failure = list_edit_plan_prepare(
		&plan,
		&malformed.analysis,
		transmute([]u8)malformed.source,
		request,
	)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Failure_Code.Malformed)
}

@(private)
List_Test_Fixture :: struct {
	buffer:   editor.Buffer,
	owner:    language.Jan_Structural_Owner,
	analysis: language.Jan_Structural_Analysis,
	scope:    Scope,
	source:   string,
}

@(private = "file")
list_test_expect_edit :: proc(
	t: ^testing.T,
	source, expected: string,
	kind: List_Edit_Kind,
	target_kind: language.Jan_Node_Kind,
	ordinal: int,
	text: string,
	bullet: List_Bullet_Kind,
	counter: u32,
	indent_width: u8,
) {
	fixture: List_Test_Fixture
	id := u64(1_000 + int(kind) * 8 + ordinal)
	if !list_test_fixture_open(t, &fixture, source, id) do return
	defer list_test_fixture_close(&fixture)
	target, found := list_test_node(&fixture.analysis, target_kind, ordinal)
	testing.expect(t, found)
	if !found do return
	request := list_test_request(fixture.scope, kind, target.id)
	request.text = text
	request.bullet = bullet
	request.counter = counter
	request.indent_width = indent_width
	plan: language.Jan_Rewrite_Plan
	planned, failure := list_edit_plan_prepare(
		&plan,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		request,
	)
	testing.expectf(t, planned, "%v plan failed with %v", kind, failure.code)
	if !planned do return
	defer language.jan_rewrite_plan_close(&plan)
	testing.expect(t, list_test_publish_and_history(&fixture, &plan, expected))
}

@(private)
list_test_publish_and_history :: proc(
	fixture: ^List_Test_Fixture,
	plan: ^language.Jan_Rewrite_Plan,
	expected: string,
) -> bool {
	store: history.Store
	store_ok, _ := history.store_init(
		&store,
		71,
		fixture.scope.analysis.buffer_id,
		fixture.scope.analysis.source_revision,
		history.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	if !store_ok do return false
	defer history.store_close(&store)
	root: transaction.Transaction
	started, _ := transaction.transaction_begin(
		&root,
		71,
		71,
		&fixture.buffer,
		{kind = .Language_Tool, descriptor = "jan"},
		"jan-list-edit",
		transaction.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	if !started do return false
	applied, _ := transaction.transaction_apply_batch(&root, language.jan_rewrite_plan_transaction_batch(plan))
	tracked, _ := transaction.transaction_track_history(&root, &store)
	validated, _ := transaction.transaction_validate(&root)
	_, committed, _ := transaction.transaction_commit(&root)
	transaction.transaction_close(&root)
	if !applied || !tracked || !validated || !committed ||
	   !list_test_buffer_matches(&fixture.buffer, expected) {
		return false
	}
	_, undone, _ := transaction.transaction_history_navigate(
		&store,
		&fixture.buffer,
		.Undo,
		72,
		72,
		transaction.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	if !undone || !list_test_buffer_matches(&fixture.buffer, fixture.source) do return false
	_, redone, _ := transaction.transaction_history_navigate(
		&store,
		&fixture.buffer,
		.Redo,
		73,
		73,
		transaction.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	return redone && list_test_buffer_matches(&fixture.buffer, expected)
}

@(private)
list_test_fixture_open :: proc(t: ^testing.T, fixture: ^List_Test_Fixture, source: string, id: u64) -> bool {
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
	testing.expectf(t, buffer_ok && owner_ok && analysis_ok, "list fixture failed with %v", failure.code)
	return buffer_ok && owner_ok && analysis_ok
}

@(private)
list_test_fixture_close :: proc(fixture: ^List_Test_Fixture) {
	language.jan_structural_analysis_close(&fixture.analysis)
	language.jan_structural_owner_close(&fixture.owner)
	_, _ = editor.buffer_close(&fixture.buffer)
}

@(private = "file")
list_test_request :: proc(scope: Scope, kind: List_Edit_Kind, target_id: language.Jan_Node_ID) -> List_Edit_Request {
	return {operation_id = 51, scope = scope, kind = kind, target_id = target_id, rewrite_generation = 51}
}

@(private)
list_test_node :: proc(
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

@(private)
list_test_buffer_matches :: proc(buffer: ^editor.Buffer, expected: string) -> bool {
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
