// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package core_tests

import "../../src/editor"
import "../reference"
import "core:mem"
import "core:strings"
import "core:testing"

/* Ensures one accepted splice advances once and emits its exact record. */
@(test)
splices_advance_and_match_records :: proc(t: ^testing.T) {
	verify_published_case(t, "a🙂bc\n", 1, 1, "X", "aX🙂bc\n")
	verify_published_case(t, "a🙂bc\n", 1, 5, "", "abc\n")
	verify_published_case(t, "a🙂bc\n", 1, 5, "λ", "aλbc\n")
}

/* Cross-checks deterministic splice traces against the independent model. */
@(test)
publish_sequences_match_model :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)

	model, _, model_ok := reference.model_init("alpha🙂omega\n")
	testing.expect(t, model_ok)
	if !model_ok {
		return
	}
	defer reference.model_deinit(&model)

	buffer: editor.Buffer
	initialized, init_failure := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(1),
		reference.model_text(&model),
		editor.Allocator_Set {
			persistent = mem.tracking_allocator(&tracking),
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, initialized, "buffer initialization failed with %v", init_failure.code)
	if !initialized {
		return
	}

	generator := reference.generator_init(0x4f44_5241_0000_0004)
	for operation_index in 0 ..< 256 {
		base_text := strings.clone(reference.model_text(&model))
		operation := reference.generator_next(&generator, &model)
		model_splice, model_splice_ok := reference.operation_splice(&model, operation)
		testing.expectf(t, model_splice_ok, "operation %d could not be materialized", operation_index)
		if !model_splice_ok {
			delete(base_text)
			editor.buffer_close(&buffer)
			return
		}

		start, start_ok, _ := editor.buffer_position(&buffer, editor.Byte_Offset(operation.start))
		end, end_ok, _ := editor.buffer_position(&buffer, editor.Byte_Offset(operation.end))
		testing.expect(t, start_ok && end_ok)
		splice := editor.Splice {
			start = start,
			end = end,
			replacement = operation.replacement,
		}
		change_set, undo_record, published, publish_failure := editor.buffer_splice(
			&buffer,
			splice,
			context.temp_allocator,
		)
		testing.expectf(t, published, "operation %d failed with %v", operation_index, publish_failure.code)
		if !published {
			delete(base_text)
			editor.buffer_close(&buffer)
			return
		}

		_, model_applied := reference.model_splice(&model, model_splice)
		testing.expect(t, model_applied)
		expected := reference.model_text(&model)
		expect_buffer_revision_and_text(
			t,
			&buffer,
			editor.Revision(operation_index + 1),
			expected,
		)
		expect_records_reconstruct_transition(t, base_text, expected, change_set, undo_record)

		stale_change, stale_undo, stale_ok, stale_failure := editor.buffer_splice(
			&buffer,
			splice,
			context.temp_allocator,
		)
		testing.expect(t, !stale_ok)
		testing.expect_value(t, stale_failure.code, editor.Failure_Code.Stale_Revision)
		testing.expect_value(t, stale_change, editor.Change_Set{})
		testing.expect_value(t, stale_undo, editor.Undo_Record{})
		expect_buffer_revision_and_text(
			t,
			&buffer,
			editor.Revision(operation_index + 1),
			expected,
		)
		delete(base_text)
	}

	closed, close_failure := editor.buffer_close(&buffer)
	testing.expect(t, closed)
	testing.expect_value(t, close_failure.code, editor.Failure_Code.None)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Ensures invalid publication requests leave confirmed text and revision unchanged. */
@(test)
rejected_publish_keeps_state :: proc(t: ^testing.T) {
	limits := editor.DEFAULT_LIMITS
	limits.buffer_bytes = 3
	limits.replacement_bytes = 3
	limits.inspection_bytes = 3
	expect_publication_failure(
		t,
		limits,
		"abc",
		0,
		0,
		"x",
		false,
		editor.Failure_Code.Buffer_Limit,
	)

	replacement_limits := editor.DEFAULT_LIMITS
	replacement_limits.replacement_bytes = 1
	expect_publication_failure(
		t,
		replacement_limits,
		"abc",
		0,
		0,
		"xy",
		false,
		editor.Failure_Code.Replacement_Limit,
	)

	undo_limits := editor.DEFAULT_LIMITS
	undo_limits.undo_bytes = 1
	expect_publication_failure(
		t,
		undo_limits,
		"abc",
		0,
		2,
		"",
		false,
		editor.Failure_Code.Undo_Memory_Limit,
	)

	expect_publication_failure(
		t,
		editor.DEFAULT_LIMITS,
		"abc",
		0,
		1,
		"x",
		true,
		editor.Failure_Code.Cancelled,
	)

	closed_buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&closed_buffer,
		editor.Buffer_ID(53),
		"abc",
		test_allocators(),
	)
	testing.expect(t, initialized)
	start, _, _ := editor.buffer_position(&closed_buffer, editor.Byte_Offset(0))
	end, _, _ := editor.buffer_position(&closed_buffer, editor.Byte_Offset(1))
	closed, _ := editor.buffer_close(&closed_buffer)
	testing.expect(t, closed)
	_, _, published, failure := editor.buffer_splice(
		&closed_buffer,
		editor.Splice{start = start, end = end, replacement = "x"},
		context.temp_allocator,
	)
	testing.expect(t, !published)
	testing.expect_value(t, failure.code, editor.Failure_Code.Closed_Buffer)
}

/* Ensures persistent faults before publication produce neither transitions nor leaks. */
@(test)
persistent_faults_leave_no_transition :: proc(t: ^testing.T) {
	for fail_offset in 0 ..= 3 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = max(u64),
		}
		buffer: editor.Buffer
		initialized, _ := editor.buffer_init(
			&buffer,
			editor.Buffer_ID(55),
			"abc",
			editor.Allocator_Set {
				persistent = failing_allocator(&failing),
				temporary = context.temp_allocator,
			},
		)
		testing.expect(t, initialized)
		if !initialized {
			mem.tracking_allocator_destroy(&tracking)
			continue
		}

		failing.fail_after = failing.successful_allocations + u64(fail_offset)
		start, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(0))
		end, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(1))
		_, _, published, failure := editor.buffer_splice(
			&buffer,
			editor.Splice{start = start, end = end, replacement = "x"},
			context.temp_allocator,
		)
		if fail_offset < 3 {
			testing.expect(t, !published)
			testing.expect_value(t, failure.code, editor.Failure_Code.Persistent_Memory_Limit)
			expect_buffer_revision_and_text(t, &buffer, editor.Revision(0), "abc")
		} else {
			testing.expect(t, published)
			testing.expect_value(t, failure.code, editor.Failure_Code.None)
			expect_buffer_revision_and_text(t, &buffer, editor.Revision(1), "xbc")
		}

		closed, _ := editor.buffer_close(&buffer)
		testing.expect(t, closed)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

/* Ensures temporary faults abort before publication and release scratch storage. */
@(test)
temp_faults_release_scratch :: proc(t: ^testing.T) {
	contents := make([]byte, 5_000)
	defer delete(contents)
	for &value in contents {
		value = 'a'
	}

	for fail_offset in 0 ..= 3 {
		persistent_tracking: mem.Tracking_Allocator
		temporary_tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&persistent_tracking, context.allocator)
		mem.tracking_allocator_init(&temporary_tracking, context.allocator)
		failing_temporary := Failing_Allocator {
			backing = mem.tracking_allocator(&temporary_tracking),
			fail_after = u64(fail_offset),
		}
		buffer: editor.Buffer
		initialized, _ := editor.buffer_init(
			&buffer,
			editor.Buffer_ID(57),
			string(contents),
			editor.Allocator_Set {
				persistent = mem.tracking_allocator(&persistent_tracking),
				temporary = context.temp_allocator,
			},
		)
		testing.expect(t, initialized)
		if !initialized {
			mem.tracking_allocator_destroy(&temporary_tracking)
			mem.tracking_allocator_destroy(&persistent_tracking)
			continue
		}

		start, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(4_095))
		end, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(4_097))
		_, _, published, failure := editor.buffer_splice(
			&buffer,
			editor.Splice{start = start, end = end, replacement = "x"},
			failing_allocator(&failing_temporary),
		)
		if fail_offset < 3 {
			testing.expect(t, !published)
			testing.expect_value(t, failure.code, editor.Failure_Code.Temporary_Memory_Limit)
			expect_buffer_revision_and_text(t, &buffer, editor.Revision(0), string(contents))
		} else {
			testing.expect(t, published)
			testing.expect_value(t, failure.code, editor.Failure_Code.None)
		}

		editor.buffer_close(&buffer)
		testing.expect_value(t, temporary_tracking.current_memory_allocated, i64(0))
		testing.expect_value(t, persistent_tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&temporary_tracking)
		mem.tracking_allocator_destroy(&persistent_tracking)
	}
}

@(private)
verify_published_case :: proc(
	t: ^testing.T,
	base: string,
	start_offset, end_offset: u64,
	replacement, expected: string,
) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(51),
		base,
		test_allocators(),
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}

	start, start_ok, _ := editor.buffer_position(&buffer, editor.Byte_Offset(start_offset))
	end, end_ok, _ := editor.buffer_position(&buffer, editor.Byte_Offset(end_offset))
	testing.expect(t, start_ok && end_ok)
	splice := editor.Splice{start = start, end = end, replacement = replacement}
	change_set, undo_record, published, failure := editor.buffer_splice(
		&buffer,
		splice,
		context.temp_allocator,
	)
	testing.expect(t, published)
	testing.expect_value(t, failure.code, editor.Failure_Code.None)
	testing.expect_value(t, failure.revision, editor.Revision(1))
	if published {
		expect_buffer_revision_and_text(t, &buffer, editor.Revision(1), expected)
		expect_records_reconstruct_transition(t, base, expected, change_set, undo_record)
	}

	_, _, stale_ok, stale_failure := editor.buffer_splice(
		&buffer,
		splice,
		context.temp_allocator,
	)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, editor.Failure_Code.Stale_Revision)
	expect_buffer_revision_and_text(t, &buffer, editor.Revision(1), expected)
	closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, closed)
}

@(private)
expect_records_reconstruct_transition :: proc(
	t: ^testing.T,
	base, expected: string,
	change_set: editor.Change_Set,
	undo_record: editor.Undo_Record,
) {
	testing.expect_value(t, change_set.buffer_id, undo_record.buffer_id)
	testing.expect_value(t, change_set.base_revision, undo_record.base_revision)
	testing.expect_value(t, change_set.result_revision, undo_record.result_revision)
	testing.expect_value(t, change_set.start, undo_record.start)
	testing.expect_value(t, change_set.replacement_text, undo_record.inserted_text)

	reconstructed := apply_record(
		base,
		u64(change_set.start),
		change_set.removed_bytes,
		change_set.replacement_text,
	)
	testing.expect_value(t, reconstructed, expected)
	delete(reconstructed)
	reversed := apply_record(
		expected,
		u64(undo_record.start),
		u64(len(undo_record.inserted_text)),
		undo_record.removed_text,
	)
	testing.expect_value(t, reversed, base)
	delete(reversed)
}

@(private)
expect_publication_failure :: proc(
	t: ^testing.T,
	limits: editor.Limits,
	base: string,
	start_offset, end_offset: u64,
	replacement: string,
	cancelled: bool,
	expected_failure: editor.Failure_Code,
) {
	buffer: editor.Buffer
	initialized, init_failure := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(59),
		base,
		test_allocators(),
		limits,
	)
	testing.expectf(t, initialized, "buffer initialization failed with %v", init_failure.code)
	if !initialized {
		return
	}
	start, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(start_offset))
	end, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(end_offset))
	change_set, undo_record, published, failure := editor.buffer_splice(
		&buffer,
		editor.Splice{start = start, end = end, replacement = replacement},
		context.temp_allocator,
		cancelled,
	)
	testing.expect(t, !published)
	testing.expect_value(t, failure.code, expected_failure)
	testing.expect_value(t, change_set, editor.Change_Set{})
	testing.expect_value(t, undo_record, editor.Undo_Record{})
	expect_buffer_revision_and_text(t, &buffer, editor.Revision(0), base)
	closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, closed)
}

@(private)
expect_buffer_revision_and_text :: proc(
	t: ^testing.T,
	buffer: ^editor.Buffer,
	expected_revision: editor.Revision,
	expected_text: string,
) {
	stats, stats_ok, stats_failure := editor.buffer_stats(buffer)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats_failure.code, editor.Failure_Code.None)
	testing.expect_value(t, stats.revision, expected_revision)
	testing.expect_value(t, stats.text_bytes, u64(len(expected_text)))
	expect_buffer_text(t, buffer, expected_text)
}
