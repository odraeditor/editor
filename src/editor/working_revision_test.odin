// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor

import "core:mem"
import "core:testing"

/* Verifies private read-your-writes visibility and abort cleanup. */
@(test)
reads_private_writes_without_publishing :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)

	buffer: Buffer
	initialized, _ := buffer_init(
		&buffer,
		Buffer_ID(81),
		"a🙂b",
		Allocator_Set {
			persistent = mem.tracking_allocator(&tracking),
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}

	working, opened, _ := buffer_working_revision_open(&buffer)
	testing.expect(t, opened)
	start, start_ok, _ := working_revision_position(&working, Byte_Offset(1))
	end, end_ok, _ := working_revision_position(&working, Byte_Offset(5))
	testing.expect(t, start_ok && end_ok)
	applied, apply_failure := working_revision_splice(
		&working,
		Working_Splice{start = start, end = end, replacement = "λ"},
		context.temp_allocator,
	)
	testing.expect(t, applied)
	testing.expect_value(t, apply_failure.code, Failure_Code.None)

	_, stale_ok, stale_failure := working_revision_inspect(&working, start, end, nil)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Revision)
	expect_working_text(t, &working, "aλb")
	expect_confirmed_text(t, &buffer, Revision(0), "a🙂b")

	aborted, abort_failure := working_revision_abort(&working)
	testing.expect(t, aborted)
	testing.expect_value(t, abort_failure.code, Failure_Code.None)
	testing.expect(t, !working_revision_is_valid(&working))
	expect_confirmed_text(t, &buffer, Revision(0), "a🙂b")
	closed, _ := buffer_close(&buffer)
	testing.expect(t, closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies that working positions cannot cross private identities or UTF-8 boundaries. */
@(test)
positions_are_identity_and_generation_checked :: proc(t: ^testing.T) {
	first: Buffer
	second: Buffer
	first_initialized, _ := buffer_init(
		&first,
		Buffer_ID(82),
		"abc",
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	second_initialized, _ := buffer_init(
		&second,
		Buffer_ID(83),
		"xyz",
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, first_initialized && second_initialized)
	if !first_initialized || !second_initialized {
		if first_initialized {
			buffer_close(&first)
		}
		if second_initialized {
			buffer_close(&second)
		}
		return
	}

	first_working, first_opened, _ := buffer_working_revision_open(&first)
	second_working, second_opened, _ := buffer_working_revision_open(&second)
	testing.expect(t, first_opened && second_opened)
	first_start, _, _ := working_revision_position(&first_working, Byte_Offset(0))
	second_end, _, _ := working_revision_position(&second_working, Byte_Offset(1))
	wrong_ok, wrong_failure := working_revision_splice(
		&first_working,
		Working_Splice{start = first_start, end = second_end, replacement = "q"},
		context.temp_allocator,
	)
	testing.expect(t, !wrong_ok)
	testing.expect_value(t, wrong_failure.code, Failure_Code.Wrong_Buffer)

	unicode_buffer: Buffer
	unicode_initialized, _ := buffer_init(
		&unicode_buffer,
		Buffer_ID(84),
		"a🙂b",
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, unicode_initialized)
	if unicode_initialized {
		unicode_working, unicode_opened, _ := buffer_working_revision_open(&unicode_buffer)
		testing.expect(t, unicode_opened)
		_, boundary_ok, boundary_failure := working_revision_position(&unicode_working, Byte_Offset(2))
		testing.expect(t, !boundary_ok)
		testing.expect_value(t, boundary_failure.code, Failure_Code.Mid_Encoding_Offset)
		working_revision_abort(&unicode_working)
		buffer_close(&unicode_buffer)
	}
	working_revision_abort(&second_working)
	working_revision_abort(&first_working)
	buffer_close(&second)
	buffer_close(&first)
}

/* Verifies that reserved publication consumes one private root and advances once. */
@(test)
publish_advances_revision_once :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)

	buffer: Buffer
	initialized, _ := buffer_init(
		&buffer,
		Buffer_ID(85),
		"abc",
		Allocator_Set {
			persistent = mem.tracking_allocator(&tracking),
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	working, opened, _ := buffer_working_revision_open(&buffer)
	testing.expect(t, opened)
	start, _, _ := working_revision_position(&working, Byte_Offset(1))
	applied, _ := working_revision_splice(
		&working,
		Working_Splice{start = start, end = start, replacement = "X"},
		context.temp_allocator,
	)
	testing.expect(t, applied)
	result_revision := working_revision_publish_reserved(
		&working,
		[]Working_Publication_Splice{{
			start = Byte_Offset(1),
			end = Byte_Offset(1),
			inserted_bytes = 1,
		}},
	)
	testing.expect_value(t, result_revision, Revision(1))
	testing.expect(t, !working_revision_is_valid(&working))
	expect_confirmed_text(t, &buffer, Revision(1), "aXbc")
	closed, _ := buffer_close(&buffer)
	testing.expect(t, closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(private)
expect_working_text :: proc(t: ^testing.T, working: ^Working_Revision, expected: string) {
	start, start_ok, _ := working_revision_position(working, Byte_Offset(0))
	end, end_ok, _ := working_revision_position(working, Byte_Offset(len(expected)))
	testing.expect(t, start_ok && end_ok)
	observed := make([]byte, len(expected))
	defer delete(observed)
	_, inspected, failure := working_revision_inspect(working, start, end, observed)
	testing.expect(t, inspected)
	testing.expect_value(t, failure.code, Failure_Code.None)
	testing.expect_value(t, string(observed), expected)
}

@(private)
expect_confirmed_text :: proc(t: ^testing.T, buffer: ^Buffer, revision: Revision, expected: string) {
	stats, stats_ok, _ := buffer_stats(buffer)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.revision, revision)
	testing.expect_value(t, stats.text_bytes, u64(len(expected)))
	observed := make([]byte, len(expected))
	defer delete(observed)
	_, inspected, failure := buffer_inspect(
		buffer,
		Byte_Offset(0),
		Byte_Offset(len(expected)),
		observed,
	)
	testing.expect(t, inspected)
	testing.expect_value(t, failure.code, Failure_Code.None)
	testing.expect_value(t, string(observed), expected)
}
