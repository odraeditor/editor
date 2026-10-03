// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"
import "core:mem"
import "core:testing"

/* Verifies a complete current proposal prepares and publishes one shared commit. */
@(test)
revisioned_proposal_admits_full_current_batches :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	first := test_buffer_open(t, &tracking, editor.Buffer_ID(801), "abc")
	second := test_buffer_open(t, &tracking, editor.Buffer_ID(802), "xyz")
	first_batch := proposal_replacement_batch(&first, "ABC")
	second_batch := proposal_replacement_batch(&second, "XYZ")
	proposal := Edit_Proposal {
		origin = Origin{kind = .Language_Tool, descriptor = "language-tool"},
		command = "apply-workspace-edit",
		snapshots = []Proposal_Snapshot {
			{buffer = &second, buffer_id = editor.Buffer_ID(802), base_revision = editor.Revision(0)},
			{buffer = &first, buffer_id = editor.Buffer_ID(801), base_revision = editor.Revision(0)},
		},
		edits = []Proposal_Edit {
			{buffer_id = editor.Buffer_ID(802), base_revision = editor.Revision(0), batch = second_batch[:]},
			{buffer_id = editor.Buffer_ID(801), base_revision = editor.Revision(0), batch = first_batch[:]},
		},
	}
	root: Multibuffer_Transaction
	admitted, admission_failure := proposal_admit(
		&root,
		Transaction_ID(800),
		Undo_Unit_ID(800),
		proposal,
		Allocator_Set {
			persistent = mem.tracking_allocator(&tracking),
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, admitted, "proposal admission failed with %v", admission_failure.code)
	expect_confirmed_text(t, &first, editor.Revision(0), "abc")
	expect_confirmed_text(t, &second, editor.Revision(0), "xyz")
	result, committed, commit_failure := multibuffer_commit(&root)
	testing.expectf(t, committed, "proposal commit failed with %v", commit_failure.code)
	testing.expect_value(t, result.origin.kind, Origin_Kind.Language_Tool)
	testing.expect_value(t, result.origin.descriptor, "language-tool")
	testing.expect_value(t, len(result.buffers), 2)
	expect_confirmed_text(t, &first, editor.Revision(1), "ABC")
	expect_confirmed_text(t, &second, editor.Revision(1), "XYZ")
	multibuffer_close(&root)
	editor.buffer_close(&second)
	editor.buffer_close(&first)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies a stale snapshot conflicts before private participant state opens. */
@(test)
stale_proposal_is_not_retried_or_transformed :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(811), "abc")
	stale_batch := proposal_replacement_batch(&buffer, "ABC")
	intervening := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(819))
	zero, _, _ := transaction_position(&intervening, editor.Byte_Offset(0))
	transaction_splice(
		&intervening,
		editor.Working_Splice{start = zero, end = zero, replacement = "!"},
	)
	transaction_validate(&intervening)
	transaction_commit(&intervening)
	transaction_close(&intervening)

	root: Multibuffer_Transaction
	admitted, failure := proposal_admit(
		&root,
		Transaction_ID(810),
		Undo_Unit_ID(810),
		Edit_Proposal {
			origin = Origin{kind = .External_Proposal, descriptor = "background"},
			command = "stale-edit",
			snapshots = []Proposal_Snapshot{{
				buffer = &buffer,
				buffer_id = editor.Buffer_ID(811),
				base_revision = editor.Revision(0),
			}},
			edits = []Proposal_Edit{{
				buffer_id = editor.Buffer_ID(811),
				base_revision = editor.Revision(0),
				batch = stale_batch[:],
			}},
		},
		Allocator_Set {
			persistent = mem.tracking_allocator(&tracking),
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, !admitted)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Revision)
	testing.expect(t, !multibuffer_transaction_is_valid(&root))
	expect_confirmed_text(t, &buffer, editor.Revision(1), "!abc")
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies snapshots and edits must describe the same unique participant set. */
@(test)
proposal_rejects_incomplete_participant_sets :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	first := test_buffer_open(t, &tracking, editor.Buffer_ID(821), "a")
	second := test_buffer_open(t, &tracking, editor.Buffer_ID(822), "b")
	first_batch := proposal_replacement_batch(&first, "A")
	root: Multibuffer_Transaction
	admitted, failure := proposal_admit(
		&root,
		Transaction_ID(820),
		Undo_Unit_ID(820),
		Edit_Proposal {
			origin = Origin{kind = .Built_In, descriptor = "test"},
			command = "incomplete",
			snapshots = []Proposal_Snapshot {
				{buffer = &first, buffer_id = editor.Buffer_ID(821), base_revision = editor.Revision(0)},
				{buffer = &second, buffer_id = editor.Buffer_ID(822), base_revision = editor.Revision(0)},
			},
			edits = []Proposal_Edit{{
				buffer_id = editor.Buffer_ID(821),
				base_revision = editor.Revision(0),
				batch = first_batch[:],
			}},
		},
		Allocator_Set {
			persistent = mem.tracking_allocator(&tracking),
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, !admitted)
	testing.expect_value(t, failure.code, Failure_Code.Incomplete_Participant_Set)
	testing.expect(t, !multibuffer_transaction_is_valid(&root))
	expect_confirmed_text(t, &first, editor.Revision(0), "a")
	expect_confirmed_text(t, &second, editor.Revision(0), "b")
	editor.buffer_close(&second)
	editor.buffer_close(&first)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies origin metadata grants no alternate admission or publication behavior. */
@(test)
origins_obey_identical_atomic_failure_rules :: proc(t: ^testing.T) {
	origins := [4]Origin_Kind{.Built_In, .Racket, .Language_Tool, .External_Proposal}
	for origin, origin_index in origins {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		first := test_buffer_open(t, &tracking, editor.Buffer_ID(830 + origin_index * 2), "a")
		second := test_buffer_open(t, &tracking, editor.Buffer_ID(831 + origin_index * 2), "b")
		first_batch := proposal_replacement_batch(&first, "A")
		second_start, _, _ := editor.buffer_position(&second, editor.Byte_Offset(0))
		second_end, _, _ := editor.buffer_position(&second, editor.Byte_Offset(1))
		invalid_batch := [1]Base_Splice{{
			start = second_end,
			end = second_start,
			replacement = "B",
		}}
		root: Multibuffer_Transaction
		admitted, failure := proposal_admit(
			&root,
			Transaction_ID(830 + origin_index),
			Undo_Unit_ID(830 + origin_index),
			Edit_Proposal {
				origin = Origin{kind = origin, descriptor = "producer"},
				command = "atomic-failure",
				snapshots = []Proposal_Snapshot {
					{buffer = &first, buffer_id = editor.Buffer_ID(830 + origin_index * 2), base_revision = editor.Revision(0)},
					{buffer = &second, buffer_id = editor.Buffer_ID(831 + origin_index * 2), base_revision = editor.Revision(0)},
				},
				edits = []Proposal_Edit {
					{buffer_id = editor.Buffer_ID(830 + origin_index * 2), base_revision = editor.Revision(0), batch = first_batch[:]},
					{buffer_id = editor.Buffer_ID(831 + origin_index * 2), base_revision = editor.Revision(0), batch = invalid_batch[:]},
				},
			},
			Allocator_Set {
				persistent = mem.tracking_allocator(&tracking),
				temporary = context.temp_allocator,
			},
		)
		testing.expect(t, !admitted)
		testing.expect_value(t, failure.code, Failure_Code.Reversed_Range)
		expect_confirmed_text(t, &first, editor.Revision(0), "a")
		expect_confirmed_text(t, &second, editor.Revision(0), "b")
		if multibuffer_transaction_is_valid(&root) {
			multibuffer_close(&root)
		}
		editor.buffer_close(&second)
		editor.buffer_close(&first)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

@(private)
proposal_replacement_batch :: proc(
	buffer: ^editor.Buffer,
	replacement: string,
) -> [1]Base_Splice {
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	assert(stats_ok)
	start, start_ok, _ := editor.buffer_position(buffer, editor.Byte_Offset(0))
	end, end_ok, _ := editor.buffer_position(buffer, editor.Byte_Offset(stats.text_bytes))
	assert(start_ok && end_ok)
	return [1]Base_Splice{{start = start, end = end, replacement = replacement}}
}
