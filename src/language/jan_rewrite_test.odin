// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "base:runtime"
import "core:testing"

import "../editor"
import "../history"
import "../transaction"

/* Verifies a node-owned rewrite minimizes its splice and publishes as one transaction. */
@(test)
jan_rewrite_plan_minimizes_and_admits_atomic_transaction :: proc(t: ^testing.T) {
	source_text := "# comment\n* READY Heading\nBody\n"
	source := transmute([]u8)source_text
	scope := jan_incremental_test_scope(0, 19)
	owner: Jan_Structural_Owner
	initialized, _ := jan_structural_owner_init(&owner, 13)
	testing.expect(t, initialized)
	if !initialized do return
	defer jan_structural_owner_close(&owner)
	analysis, analyzed, failure := jan_structural_owner_analyze(&owner, source, scope)
	testing.expectf(t, analyzed, "Jan analysis failed with %v", failure.code)
	if !analyzed do return
	defer jan_structural_analysis_close(&analysis)
	heading, found := jan_rewrite_test_node(&analysis, .Heading)
	testing.expect(t, found)
	if !found do return

	plan: Jan_Rewrite_Plan
	planned, plan_failure := jan_rewrite_plan_prepare(
		&plan,
		&analysis,
		source,
		1,
		[]Jan_Rewrite_Request{{
			node_id = heading.id,
			range = heading.range,
			replacement = "* DONE Heading\nBody\n",
		}},
	)
	testing.expectf(t, planned, "Jan rewrite planning failed with %v", plan_failure.code)
	if !planned do return
	defer jan_rewrite_plan_close(&plan)
	edits := jan_rewrite_plan_edits(&plan)
	testing.expect_value(t, len(edits), 1)
	testing.expect_value(t, edits[0].range.start, editor.Byte_Offset(12))
	testing.expect_value(t, edits[0].range.end, editor.Byte_Offset(17))
	replacement, replacement_ok := jan_rewrite_plan_replacement(&plan, edits[0])
	testing.expect(t, replacement_ok)
	testing.expect_value(t, replacement, "DONE")

	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		scope.buffer_id,
		source_text,
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, buffer_ok)
	if !buffer_ok do return
	defer editor.buffer_close(&buffer)
	root: transaction.Multibuffer_Transaction
	admitted, admission_failure := jan_rewrite_plan_admit(
		&plan,
		&buffer,
		&root,
		100,
		100,
		"jan-rewrite",
		transaction.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, admitted, "Jan transaction admission failed with %v", admission_failure.code)
	if !admitted do return
	_, committed, commit_failure := transaction.multibuffer_commit(&root)
	testing.expectf(t, committed, "Jan transaction commit failed with %v", commit_failure.code)
	transaction.multibuffer_close(&root)
	testing.expect(t, jan_rewrite_test_buffer_matches(&buffer, "# comment\n* DONE Heading\nBody\n"))
}

/* Verifies overlap, stale scope, no-op, and transaction conflicts reject before publication. */
@(test)
jan_rewrite_plan_rejects_unsafe_candidates :: proc(t: ^testing.T) {
	source_text := "* Heading\nBody *bold*.\n"
	source := transmute([]u8)source_text
	scope := jan_incremental_test_scope(0, 19)
	owner: Jan_Structural_Owner
	initialized, _ := jan_structural_owner_init(&owner, 13)
	testing.expect(t, initialized)
	if !initialized do return
	defer jan_structural_owner_close(&owner)
	analysis, analyzed, _ := jan_structural_owner_analyze(&owner, source, scope)
	testing.expect(t, analyzed)
	if !analyzed do return
	defer jan_structural_analysis_close(&analysis)
	heading, heading_found := jan_rewrite_test_node(&analysis, .Heading)
	bold, bold_found := jan_rewrite_test_node(&analysis, .Bold_Markup)
	testing.expect(t, heading_found && bold_found)
	if !heading_found || !bold_found do return

	plan: Jan_Rewrite_Plan
	planned, failure := jan_rewrite_plan_prepare(
		&plan,
		&analysis,
		source,
		1,
		[]Jan_Rewrite_Request{
			{node_id = heading.id, range = heading.range, replacement = "* Changed\nBody plain.\n"},
			{node_id = bold.id, range = bold.range, replacement = "*strong*"},
		},
	)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Jan_Failure_Code.Invalid_Rewrite)
	if planned {
		jan_rewrite_plan_close(&plan)
	}

	planned, failure = jan_rewrite_plan_prepare(
		&plan,
		&analysis,
		source,
		2,
		[]Jan_Rewrite_Request{{
			node_id = bold.id,
			range = bold.range,
			replacement = string(source[int(bold.range.start):int(bold.range.end)]),
		}},
	)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Jan_Failure_Code.Invalid_Rewrite)

	stale_range := bold.range
	stale_range.scope.source_revision = 1
	planned, failure = jan_rewrite_plan_prepare(
		&plan,
		&analysis,
		source,
		3,
		[]Jan_Rewrite_Request{{node_id = bold.id, range = stale_range, replacement = "*strong*"}},
	)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Jan_Failure_Code.Stale)

	planned, failure = jan_rewrite_plan_prepare(
		&plan,
		&analysis,
		source,
		3,
		[]Jan_Rewrite_Request{{node_id = 0, range = heading.range, replacement = "* Changed\n"}},
	)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Jan_Failure_Code.Invalid_Node)

	tiny_limits := DEFAULT_JAN_RESOURCE_LIMITS
	tiny_limits.rewrite_bytes = 1
	planned, failure = jan_rewrite_plan_prepare(
		&plan,
		&analysis,
		source,
		3,
		[]Jan_Rewrite_Request{{node_id = bold.id, range = bold.range, replacement = "*strong*"}},
		tiny_limits,
	)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Jan_Failure_Code.Limited)

	planned, failure = jan_rewrite_plan_prepare(
		&plan,
		&analysis,
		source,
		3,
		[]Jan_Rewrite_Request{{node_id = bold.id, range = bold.range, replacement = "*strong*"}},
		DEFAULT_JAN_RESOURCE_LIMITS,
		runtime.Allocator{},
	)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Jan_Failure_Code.Allocation_Failed)

	one_splice_limits := DEFAULT_JAN_RESOURCE_LIMITS
	one_splice_limits.rewrite_splices = 1
	planned, failure = jan_rewrite_plan_prepare(
		&plan,
		&analysis,
		source,
		3,
		[]Jan_Rewrite_Request{
			{node_id = heading.id, range = heading.range, replacement = "* Changed\nBody *bold*.\n"},
			{node_id = bold.id, range = bold.range, replacement = "*strong*"},
		},
		one_splice_limits,
	)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Jan_Failure_Code.Limited)

	planned, failure = jan_rewrite_plan_prepare(
		&plan,
		&analysis,
		source,
		4,
		[]Jan_Rewrite_Request{{node_id = bold.id, range = bold.range, replacement = "*strong*"}},
	)
	testing.expectf(t, planned, "valid plan failed with %v", failure.code)
	if !planned do return
	defer jan_rewrite_plan_close(&plan)
	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		scope.buffer_id,
		source_text,
		editor.Allocator_Set {persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, buffer_ok)
	if !buffer_ok do return
	defer editor.buffer_close(&buffer)
	rejected_root: transaction.Multibuffer_Transaction
	rejected_limits := transaction.DEFAULT_LIMITS
	rejected_limits.splices = 0
	admitted, admission_failure := jan_rewrite_plan_admit(
		&plan,
		&buffer,
		&rejected_root,
		199,
		199,
		"jan-rewrite",
		transaction.Allocator_Set {persistent = context.allocator, temporary = context.temp_allocator},
		rejected_limits,
	)
	testing.expect(t, !admitted)
	testing.expect_value(t, admission_failure.code, Jan_Failure_Code.Invalid_Rewrite)
	if transaction.multibuffer_transaction_is_valid(&rejected_root) {
		transaction.multibuffer_close(&rejected_root)
	}
	position, _, _ := editor.buffer_position(&buffer, 0)
	_, _, published, _ := editor.buffer_splice(
		&buffer,
		editor.Splice{start = position, end = position, replacement = "!"},
		context.temp_allocator,
	)
	testing.expect(t, published)
	root: transaction.Multibuffer_Transaction
	admitted, admission_failure = jan_rewrite_plan_admit(
		&plan,
		&buffer,
		&root,
		200,
		200,
		"jan-rewrite",
		transaction.Allocator_Set {persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, !admitted)
	testing.expect_value(t, admission_failure.code, Jan_Failure_Code.Stale)
	testing.expect(t, jan_rewrite_test_buffer_matches(&buffer, "!* Heading\nBody *bold*.\n"))
}

/* Verifies representative Jan forms publish together and remain undoable and redoable. */
@(test)
jan_rewrite_plan_preserves_unowned_bytes_through_history :: proc(t: ^testing.T) {
	source_text := ":PROPERTIES:\n:Owner: Ada\n:END:\n- one\n| a | b |\nText *bold*.\n* TODO Heading\n"
	expected := ":PROPERTIES:\n:Owner: Bea\n:END:\n- two\n| A | b |\nText *strong*.\n* DONE Heading\n"
	source := transmute([]u8)source_text
	scope := jan_incremental_test_scope(0, 19)
	owner: Jan_Structural_Owner
	initialized, _ := jan_structural_owner_init(&owner, 13)
	testing.expect(t, initialized)
	if !initialized do return
	defer jan_structural_owner_close(&owner)
	analysis, analyzed, _ := jan_structural_owner_analyze(&owner, source, scope)
	testing.expect(t, analyzed)
	if !analyzed do return
	defer jan_structural_analysis_close(&analysis)
	property, property_ok := jan_rewrite_test_node(&analysis, .Node_Property)
	item, item_ok := jan_rewrite_test_node(&analysis, .List_Item)
	row, row_ok := jan_rewrite_test_node(&analysis, .Table_Row)
	markup, markup_ok := jan_rewrite_test_node(&analysis, .Bold_Markup)
	heading, heading_ok := jan_rewrite_test_node(&analysis, .Heading)
	testing.expect(t, property_ok && item_ok && row_ok && markup_ok && heading_ok)
	if !property_ok || !item_ok || !row_ok || !markup_ok || !heading_ok do return

	plan: Jan_Rewrite_Plan
	planned, failure := jan_rewrite_plan_prepare(
		&plan,
		&analysis,
		source,
		10,
		[]Jan_Rewrite_Request{
			{node_id = property.id, range = property.range, replacement = ":Owner: Bea\n"},
			{node_id = item.id, range = item.range, replacement = "- two\n"},
			{node_id = row.id, range = row.range, replacement = "| A | b |\n"},
			{node_id = markup.id, range = markup.range, replacement = "*strong*"},
			{node_id = heading.id, range = heading.range, replacement = "* DONE Heading\n"},
		},
	)
	testing.expectf(t, planned, "representative rewrite failed with %v", failure.code)
	if !planned do return
	defer jan_rewrite_plan_close(&plan)
	descriptor, described := jan_rewrite_plan_descriptor(&plan)
	testing.expect(t, described)
	testing.expect_value(t, descriptor.splice_count, u32(5))

	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		scope.buffer_id,
		source_text,
		editor.Allocator_Set {persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, buffer_ok)
	if !buffer_ok do return
	defer editor.buffer_close(&buffer)
	store: history.Store
	store_ok, _ := history.store_init(
		&store,
		10,
		scope.buffer_id,
		scope.source_revision,
		history.Allocator_Set {persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, store_ok)
	if !store_ok do return
	defer history.store_close(&store)
	root: transaction.Transaction
	started, transaction_failure := transaction.transaction_begin(
		&root,
		10,
		10,
		&buffer,
		{kind = .Language_Tool, descriptor = "jan"},
		"jan-rewrite",
		transaction.Allocator_Set {persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, started, "transaction begin failed with %v", transaction_failure.code)
	if !started do return
	applied: bool
	applied, transaction_failure = transaction.transaction_apply_batch(
		&root,
		jan_rewrite_plan_transaction_batch(&plan),
	)
	testing.expectf(t, applied, "rewrite batch failed with %v", transaction_failure.code)
	tracked: bool
	tracked, transaction_failure = transaction.transaction_track_history(&root, &store)
	testing.expectf(t, tracked, "rewrite history failed with %v", transaction_failure.code)
	validated: bool
	validated, transaction_failure = transaction.transaction_validate(&root)
	testing.expectf(t, validated, "rewrite validation failed with %v", transaction_failure.code)
	committed: bool
	_, committed, transaction_failure = transaction.transaction_commit(&root)
	testing.expectf(t, committed, "rewrite commit failed with %v", transaction_failure.code)
	transaction.transaction_close(&root)
	testing.expect(t, jan_rewrite_test_buffer_matches(&buffer, expected))
	_, undone, undo_failure := transaction.transaction_history_navigate(
		&store,
		&buffer,
		.Undo,
		11,
		11,
		transaction.Allocator_Set {persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, undone, "rewrite undo failed with %v", undo_failure.code)
	testing.expect(t, jan_rewrite_test_buffer_matches(&buffer, source_text))
	_, redone, redo_failure := transaction.transaction_history_navigate(
		&store,
		&buffer,
		.Redo,
		12,
		12,
		transaction.Allocator_Set {persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, redone, "rewrite redo failed with %v", redo_failure.code)
	testing.expect(t, jan_rewrite_test_buffer_matches(&buffer, expected))
}

@(private = "file")
jan_rewrite_test_node :: proc(
	analysis: ^Jan_Structural_Analysis,
	kind: Jan_Node_Kind,
) -> (Jan_Node_Record, bool) {
	for node in jan_structural_analysis_nodes(analysis) {
		if node.kind == kind do return node, true
	}
	return {}, false
}

@(private = "file")
jan_rewrite_test_buffer_matches :: proc(buffer: ^editor.Buffer, expected: string) -> bool {
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
