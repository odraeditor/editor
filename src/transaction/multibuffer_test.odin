// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"
import "../history"
import "core:mem"
import "core:testing"

/* Verifies deterministic all-buffer publication and one shared commit identity. */
@(test)
commit_publishes_one_ordered_shared_result :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	first := test_buffer_open(t, &tracking, editor.Buffer_ID(701), "one")
	second := test_buffer_open(t, &tracking, editor.Buffer_ID(702), "two")
	third := test_buffer_open(t, &tracking, editor.Buffer_ID(703), "three")
	root := test_multibuffer_begin(
		t,
		[]^editor.Buffer{&third, &first, &second},
		&tracking,
		Transaction_ID(700),
	)
	apply_whole_buffer_batch(t, &root, &first, "ONE")
	apply_whole_buffer_batch(t, &root, &second, "TWO")
	apply_whole_buffer_batch(t, &root, &third, "THREE")
	expect_confirmed_text(t, &first, editor.Revision(0), "one")
	expect_confirmed_text(t, &second, editor.Revision(0), "two")
	expect_confirmed_text(t, &third, editor.Revision(0), "three")

	validated, validation_failure := multibuffer_validate(&root)
	testing.expectf(t, validated, "validation failed with %v", validation_failure.code)
	result, committed, commit_failure := multibuffer_commit(&root)
	testing.expectf(t, committed, "commit failed with %v", commit_failure.code)
	testing.expect_value(t, result.transaction_id, Transaction_ID(700))
	testing.expect_value(t, result.undo_unit_id, Undo_Unit_ID(700))
	testing.expect_value(t, result.usage.buffer_participants, u64(3))
	testing.expect_value(t, len(result.buffers), 3)
	testing.expect_value(t, result.buffers[0].buffer_id, editor.Buffer_ID(701))
	testing.expect_value(t, result.buffers[1].buffer_id, editor.Buffer_ID(702))
	testing.expect_value(t, result.buffers[2].buffer_id, editor.Buffer_ID(703))
	for buffer_result in result.buffers {
		testing.expect_value(t, buffer_result.base_revision, editor.Revision(0))
		testing.expect_value(t, buffer_result.result_revision, editor.Revision(1))
		testing.expect_value(t, len(buffer_result.splices), 1)
	}
	expect_confirmed_text(t, &first, editor.Revision(1), "ONE")
	expect_confirmed_text(t, &second, editor.Revision(1), "TWO")
	expect_confirmed_text(t, &third, editor.Revision(1), "THREE")

	closed, close_failure := multibuffer_close(&root)
	testing.expectf(t, closed, "close failed with %v", close_failure.code)
	editor.buffer_close(&third)
	editor.buffer_close(&second)
	editor.buffer_close(&first)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies transaction publication finalizes one linked history unit and keeps later work separate. */
@(test)
commit_reserves_complete_linked_history :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	first := test_buffer_open(t, &tracking, editor.Buffer_ID(751), "one")
	second := test_buffer_open(t, &tracking, editor.Buffer_ID(752), "two")
	first_history: history.Store
	second_history: history.Store
	first_initialized, _ := history.store_init(
		&first_history,
		history.Store_ID(751),
		editor.Buffer_ID(751),
		editor.Revision(0),
		history.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	second_initialized, _ := history.store_init(
		&second_history,
		history.Store_ID(752),
		editor.Buffer_ID(752),
		editor.Revision(0),
		history.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, first_initialized && second_initialized)
	root := test_multibuffer_begin(
		t,
		[]^editor.Buffer{&second, &first},
		&tracking,
		Transaction_ID(750),
	)
	tracked, track_failure := multibuffer_track_history(
		&root,
		[]^history.Store{&second_history, &first_history},
	)
	testing.expectf(t, tracked, "history attachment failed with %v", track_failure.code)
	apply_whole_buffer_batch(t, &root, &first, "ONE")
	apply_whole_buffer_batch(t, &root, &second, "TWO")
	validated, validation_failure := multibuffer_validate(&root)
	testing.expectf(t, validated, "linked validation failed with %v", validation_failure.code)
	_, committed, commit_failure := multibuffer_commit(&root)
	testing.expectf(t, committed, "linked commit failed with %v", commit_failure.code)
	first_stats, _, _ := history.store_stats(&first_history)
	second_stats, _, _ := history.store_stats(&second_history)
	testing.expect_value(t, first_stats.current_revision, editor.Revision(1))
	testing.expect_value(t, second_stats.current_revision, editor.Revision(1))
	linked_first_node := first_stats.active_node
	participants: [2]history.Link_Participant
	link, inspected, inspect_failure := history.link_inspect(
		&first_history,
		linked_first_node,
		participants[:],
	)
	testing.expectf(t, inspected, "linked history inspection failed with %v", inspect_failure.code)
	testing.expect_value(t, link.id, history.Link_ID(750))
	testing.expect_value(t, link.participants[0].buffer_id, editor.Buffer_ID(751))
	testing.expect_value(t, link.participants[1].buffer_id, editor.Buffer_ID(752))
	multibuffer_close(&root)

	_, navigated, navigate_failure := transaction_multibuffer_history_navigate(
		[]^history.Store{&second_history, &first_history},
		[]^editor.Buffer{&first, &second},
		.Undo,
		0,
		Transaction_ID(751),
		Undo_Unit_ID(751),
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, navigated, "linked undo failed with %v", navigate_failure.code)
	expect_confirmed_text(t, &first, editor.Revision(2), "one")
	expect_confirmed_text(t, &second, editor.Revision(2), "two")
	_, incomplete_ok, incomplete_failure := transaction_multibuffer_history_navigate(
		[]^history.Store{&first_history},
		[]^editor.Buffer{&first},
		.Redo,
		0,
		Transaction_ID(752),
		Undo_Unit_ID(752),
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, !incomplete_ok)
	testing.expect_value(t, incomplete_failure.history_failure.code, history.Failure_Code.Incomplete_Participant_Set)
	expect_confirmed_text(t, &first, editor.Revision(2), "one")
	expect_confirmed_text(t, &second, editor.Revision(2), "two")
	_, navigated, navigate_failure = transaction_multibuffer_history_navigate(
		[]^history.Store{&first_history, &second_history},
		[]^editor.Buffer{&second, &first},
		.Redo,
		0,
		Transaction_ID(753),
		Undo_Unit_ID(753),
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, navigated, "linked redo failed with %v", navigate_failure.code)
	expect_confirmed_text(t, &first, editor.Revision(3), "ONE")
	expect_confirmed_text(t, &second, editor.Revision(3), "TWO")
	compensation_link, compensated, compensation_failure := transaction_multibuffer_history_selective_undo(
		[]^history.Store{&second_history, &first_history},
		[]^editor.Buffer{&first, &second},
		history.Link_ID(750),
		1_024,
		Transaction_ID(756),
		Undo_Unit_ID(756),
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, compensated, "linked selective undo failed with %v", compensation_failure.code)
	testing.expect_value(t, compensation_link, history.Link_ID(756))
	expect_confirmed_text(t, &first, editor.Revision(4), "one")
	expect_confirmed_text(t, &second, editor.Revision(4), "two")
	_, navigated, navigate_failure = transaction_multibuffer_history_navigate(
		[]^history.Store{&first_history, &second_history},
		[]^editor.Buffer{&first, &second},
		.Undo,
		0,
		Transaction_ID(757),
		Undo_Unit_ID(757),
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, navigated, "compensation undo failed with %v", navigate_failure.code)
	expect_confirmed_text(t, &first, editor.Revision(5), "ONE")
	expect_confirmed_text(t, &second, editor.Revision(5), "TWO")
	_, navigated, navigate_failure = transaction_multibuffer_history_navigate(
		[]^history.Store{&first_history, &second_history},
		[]^editor.Buffer{&first, &second},
		.Undo,
		0,
		Transaction_ID(758),
		Undo_Unit_ID(758),
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, navigated, "linked branch setup undo failed with %v", navigate_failure.code)
	expect_confirmed_text(t, &first, editor.Revision(6), "one")
	expect_confirmed_text(t, &second, editor.Revision(6), "two")
	alternate := test_multibuffer_begin(
		t,
		[]^editor.Buffer{&first, &second},
		&tracking,
		Transaction_ID(759),
	)
	multibuffer_track_history(&alternate, []^history.Store{&first_history, &second_history})
	apply_whole_buffer_batch(t, &alternate, &first, "uno")
	apply_whole_buffer_batch(t, &alternate, &second, "dos")
	multibuffer_validate(&alternate)
	multibuffer_commit(&alternate)
	multibuffer_close(&alternate)
	expect_confirmed_text(t, &first, editor.Revision(7), "uno")
	expect_confirmed_text(t, &second, editor.Revision(7), "dos")
	_, navigated, navigate_failure = transaction_multibuffer_history_navigate(
		[]^history.Store{&second_history, &first_history},
		[]^editor.Buffer{&second, &first},
		.Select_Branch,
		history.Link_ID(750),
		Transaction_ID(760),
		Undo_Unit_ID(760),
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, navigated, "linked branch selection failed with %v", navigate_failure.code)
	expect_confirmed_text(t, &first, editor.Revision(8), "ONE")
	expect_confirmed_text(t, &second, editor.Revision(8), "TWO")

	independent: Transaction
	started, _ := transaction_begin(
		&independent,
		Transaction_ID(761),
		Undo_Unit_ID(761),
		&first,
		Origin{kind = .Built_In, descriptor = "test"},
		"independent",
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, started)
	transaction_track_history(&independent, &first_history)
	start, _, _ := editor.buffer_position(&first, editor.Byte_Offset(0))
	end, _, _ := editor.buffer_position(&first, editor.Byte_Offset(3))
	transaction_apply_batch(&independent, []Base_Splice{{start = start, end = end, replacement = "solo"}})
	transaction_validate(&independent)
	transaction_commit(&independent)
	transaction_close(&independent)
	first_stats, _, _ = history.store_stats(&first_history)
	_, active_is_linked, _ := history.link_inspect(&first_history, first_stats.active_node, participants[:])
	testing.expect(t, !active_is_linked)
	_, retained_link_ok, _ := history.link_inspect(&first_history, linked_first_node, participants[:])
	testing.expect(t, retained_link_ok)

	closed, close_failure := history.multibuffer_stores_close(
		[]^history.Store{&first_history, &second_history},
	)
	testing.expectf(t, closed, "linked history close failed with %v", close_failure.code)
	editor.buffer_close(&second)
	editor.buffer_close(&first)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies generated linked commits, cancellation, undo, redo, and exact teardown. */
@(test)
generated_history_preserves_participants :: proc(t: ^testing.T) {
	replacements := [4][2]string {
		{"A", "B"},
		{"lambda", "racket"},
		{"żółć", "Odra"},
		{"🙂", "λ"},
	}
	for case_index in 0 ..< 16 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		allocator := mem.tracking_allocator(&tracking)
		first_id := editor.Buffer_ID(800 + case_index * 2)
		second_id := editor.Buffer_ID(801 + case_index * 2)
		first := test_buffer_open(t, &tracking, first_id, "a")
		second := test_buffer_open(t, &tracking, second_id, "b")
		first_history: history.Store
		second_history: history.Store
		history.store_init(
			&first_history,
			history.Store_ID(800 + case_index * 2),
			first_id,
			editor.Revision(0),
			history.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
		)
		history.store_init(
			&second_history,
			history.Store_ID(801 + case_index * 2),
			second_id,
			editor.Revision(0),
			history.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
		)
		transaction_id := Transaction_ID(800 + case_index)
		root := test_multibuffer_begin(t, []^editor.Buffer{&second, &first}, &tracking, transaction_id)
		multibuffer_track_history(&root, []^history.Store{&first_history, &second_history})
		choice := replacements[case_index % len(replacements)]
		apply_whole_buffer_batch(t, &root, &first, choice[0])
		apply_whole_buffer_batch(t, &root, &second, choice[1])
		validated, _ := multibuffer_validate(&root)
		testing.expect(t, validated)
		if case_index % 4 == 0 {
			multibuffer_request_cancel(&root)
			_, committed, failure := multibuffer_commit(&root)
			testing.expect(t, !committed)
			testing.expect_value(t, failure.code, Failure_Code.Cancelled)
			expect_confirmed_text(t, &first, editor.Revision(0), "a")
			expect_confirmed_text(t, &second, editor.Revision(0), "b")
			first_stats, _, _ := history.store_stats(&first_history)
			second_stats, _, _ := history.store_stats(&second_history)
			testing.expect_value(t, first_stats.usage.retained_nodes, u64(1))
			testing.expect_value(t, second_stats.usage.retained_nodes, u64(1))
			multibuffer_close(&root)
			history.store_close(&second_history)
			history.store_close(&first_history)
		} else {
			multibuffer_commit(&root)
			multibuffer_close(&root)
			expect_confirmed_text(t, &first, editor.Revision(1), choice[0])
			expect_confirmed_text(t, &second, editor.Revision(1), choice[1])
			_, undone, undo_failure := transaction_multibuffer_history_navigate(
				[]^history.Store{&first_history, &second_history},
				[]^editor.Buffer{&second, &first},
				.Undo,
				0,
				Transaction_ID(900 + case_index),
				Undo_Unit_ID(900 + case_index),
				Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
			)
			testing.expectf(t, undone, "generated undo case %d failed with %v/%v editor=%v actual=%d", case_index, undo_failure.code, undo_failure.history_failure.code, undo_failure.editor_failure.code, undo_failure.editor_failure.actual)
			expect_confirmed_text(t, &first, editor.Revision(2), "a")
			expect_confirmed_text(t, &second, editor.Revision(2), "b")
			_, redone, redo_failure := transaction_multibuffer_history_navigate(
				[]^history.Store{&second_history, &first_history},
				[]^editor.Buffer{&first, &second},
				.Redo,
				0,
				Transaction_ID(1_000 + case_index),
				Undo_Unit_ID(1_000 + case_index),
				Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
			)
			testing.expectf(t, redone, "generated redo case %d failed with %v/%v", case_index, redo_failure.code, redo_failure.history_failure.code)
			expect_confirmed_text(t, &first, editor.Revision(3), choice[0])
			expect_confirmed_text(t, &second, editor.Revision(3), choice[1])
			history.multibuffer_stores_close([]^history.Store{&first_history, &second_history})
		}
		editor.buffer_close(&second)
		editor.buffer_close(&first)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

/* Verifies per-buffer sequential reads stay private until the complete set commits. */
@(test)
multibuffer_sequential_edits_read_private_writes :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	first := test_buffer_open(t, &tracking, editor.Buffer_ID(711), "ab")
	second := test_buffer_open(t, &tracking, editor.Buffer_ID(712), "xy")
	root := test_multibuffer_begin(
		t,
		[]^editor.Buffer{&first, &second},
		&tracking,
		Transaction_ID(710),
	)
	one, one_ok, _ := multibuffer_position(&root, editor.Buffer_ID(711), editor.Byte_Offset(1))
	testing.expect(t, one_ok)
	applied, apply_failure := multibuffer_splice(
		&root,
		editor.Buffer_ID(711),
		editor.Working_Splice{start = one, end = one, replacement = "X"},
	)
	testing.expectf(t, applied, "first private splice failed with %v", apply_failure.code)
	start, _, _ := multibuffer_position(&root, editor.Buffer_ID(711), editor.Byte_Offset(0))
	end, _, _ := multibuffer_position(&root, editor.Buffer_ID(711), editor.Byte_Offset(3))
	observed: [3]byte
	_, inspected, inspect_failure := multibuffer_inspect(
		&root,
		editor.Buffer_ID(711),
		start,
		end,
		observed[:],
	)
	testing.expectf(t, inspected, "private inspection failed with %v", inspect_failure.code)
	testing.expect_value(t, string(observed[:]), "aXb")
	apply_whole_buffer_batch(t, &root, &second, "XY")
	expect_confirmed_text(t, &first, editor.Revision(0), "ab")
	expect_confirmed_text(t, &second, editor.Revision(0), "xy")
	multibuffer_validate(&root)
	multibuffer_commit(&root)
	expect_confirmed_text(t, &first, editor.Revision(1), "aXb")
	expect_confirmed_text(t, &second, editor.Revision(1), "XY")
	multibuffer_close(&root)
	editor.buffer_close(&second)
	editor.buffer_close(&first)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies one participant rejection aborts private work across the complete set. */
@(test)
participant_failure_aborts_the_complete_set :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	first := test_buffer_open(t, &tracking, editor.Buffer_ID(721), "one")
	second := test_buffer_open(t, &tracking, editor.Buffer_ID(722), "two")
	root := test_multibuffer_begin(
		t,
		[]^editor.Buffer{&first, &second},
		&tracking,
		Transaction_ID(720),
	)
	apply_whole_buffer_batch(t, &root, &first, "ONE")
	second_start, _, _ := editor.buffer_position(&second, editor.Byte_Offset(0))
	second_end, _, _ := editor.buffer_position(&second, editor.Byte_Offset(3))
	applied, apply_failure := multibuffer_apply_batch(
		&root,
		editor.Buffer_ID(722),
		[]Base_Splice{{start = second_end, end = second_start, replacement = "TWO"}},
	)
	testing.expect(t, !applied)
	testing.expect_value(t, apply_failure.code, Failure_Code.Reversed_Range)
	expect_confirmed_text(t, &first, editor.Revision(0), "one")
	expect_confirmed_text(t, &second, editor.Revision(0), "two")
	multibuffer_close(&root)
	editor.buffer_close(&second)
	editor.buffer_close(&first)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Injects rejection before each publication reservation boundary and observes no partial set. */
@(test)
publication_faults_abort_all_participants :: proc(t: ^testing.T) {
	for fault_index in 0 ..< 3 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		first := test_buffer_open(t, &tracking, editor.Buffer_ID(731), "a")
		second := test_buffer_open(t, &tracking, editor.Buffer_ID(732), "b")
		third := test_buffer_open(t, &tracking, editor.Buffer_ID(733), "c")
		root := test_multibuffer_begin(
			t,
			[]^editor.Buffer{&first, &second, &third},
			&tracking,
			Transaction_ID(730 + fault_index),
		)
		apply_whole_buffer_batch(t, &root, &first, "A")
		apply_whole_buffer_batch(t, &root, &second, "B")
		apply_whole_buffer_batch(t, &root, &third, "C")
		validated, failure := multibuffer_validate_before(&root, u64(fault_index))
		testing.expect(t, !validated)
		testing.expect_value(t, failure.code, Failure_Code.Persistent_Memory_Limit)
		expect_confirmed_text(t, &first, editor.Revision(0), "a")
		expect_confirmed_text(t, &second, editor.Revision(0), "b")
		expect_confirmed_text(t, &third, editor.Revision(0), "c")
		multibuffer_close(&root)
		editor.buffer_close(&third)
		editor.buffer_close(&second)
		editor.buffer_close(&first)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

/* Verifies duplicate identities and participant bounds fail before private state opens. */
@(test)
participant_set_is_complete_and_unique :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	first := test_buffer_open(t, &tracking, editor.Buffer_ID(741), "a")
	duplicate := test_buffer_open(t, &tracking, editor.Buffer_ID(741), "b")
	root: Multibuffer_Transaction
	started, duplicate_failure := multibuffer_begin(
		&root,
		Transaction_ID(740),
		Undo_Unit_ID(740),
		[]^editor.Buffer{&first, &duplicate},
		Origin{kind = .Built_In, descriptor = "test"},
		"duplicate",
		Allocator_Set {
			persistent = mem.tracking_allocator(&tracking),
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, !started)
	testing.expect_value(t, duplicate_failure.code, Failure_Code.Invalid_Identity)
	limits := DEFAULT_LIMITS
	limits.buffer_participants = 1
	limit_failure: Failure_Context
	started, limit_failure = multibuffer_begin(
		&root,
		Transaction_ID(741),
		Undo_Unit_ID(741),
		[]^editor.Buffer{&first, &duplicate},
		Origin{kind = .Built_In, descriptor = "test"},
		"limited",
		Allocator_Set {
			persistent = mem.tracking_allocator(&tracking),
			temporary = context.temp_allocator,
		},
		limits,
	)
	testing.expect(t, !started)
	testing.expect_value(t, limit_failure.code, Failure_Code.Participant_Limit)
	editor.buffer_close(&duplicate)
	editor.buffer_close(&first)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(private)
test_multibuffer_begin :: proc(
	t: ^testing.T,
	buffers: []^editor.Buffer,
	tracking: ^mem.Tracking_Allocator,
	transaction_id: Transaction_ID,
) -> Multibuffer_Transaction {
	root: Multibuffer_Transaction
	started, failure := multibuffer_begin(
		&root,
		transaction_id,
		Undo_Unit_ID(u64(transaction_id)),
		buffers,
		Origin{kind = .Built_In, descriptor = "test"},
		"multibuffer-test",
		Allocator_Set {
			persistent = mem.tracking_allocator(tracking),
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, started, "multibuffer begin failed with %v", failure.code)
	return root
}

@(private)
apply_whole_buffer_batch :: proc(
	t: ^testing.T,
	root: ^Multibuffer_Transaction,
	buffer: ^editor.Buffer,
	replacement: string,
) {
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	testing.expect(t, stats_ok)
	start, _, _ := editor.buffer_position(buffer, editor.Byte_Offset(0))
	end, _, _ := editor.buffer_position(buffer, editor.Byte_Offset(stats.text_bytes))
	applied, failure := multibuffer_apply_batch(
		root,
		stats.buffer_id,
		[]Base_Splice{{start = start, end = end, replacement = replacement}},
	)
	testing.expectf(t, applied, "batch for buffer %d failed with %v", stats.buffer_id, failure.code)
}
