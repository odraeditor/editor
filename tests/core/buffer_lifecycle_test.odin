// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package core_tests

import "../../src/editor"
import "../reference"
import "base:runtime"
import "core:mem"
import "core:testing"

MIB :: u64(1024 * 1024)

/* Ensures initial UTF-8 content is preserved exactly at revision zero. */
@(test)
buffers_keep_utf8_exactly :: proc(t: ^testing.T) {
	for fixture in reference.FIXTURES {
		buffer: editor.Buffer
		initialized, failure := editor.buffer_init(
			&buffer,
			editor.Buffer_ID(7),
			fixture.text,
			test_allocators(),
		)
		testing.expectf(t, initialized, "fixture %s failed with %v", fixture.name, failure.code)
		if !initialized {
			continue
		}

		stats, stats_ok, stats_failure := editor.buffer_stats(&buffer)
		testing.expect(t, stats_ok)
		testing.expect_value(t, stats_failure.code, editor.Failure_Code.None)
		testing.expect_value(t, stats.buffer_id, editor.Buffer_ID(7))
		testing.expect_value(t, stats.revision, editor.Revision(0))
		testing.expect_value(t, stats.text_bytes, u64(len(fixture.text)))

		observed := make([]byte, len(fixture.text))
		copied, inspect_ok, inspect_failure := editor.buffer_inspect(
			&buffer,
			editor.Byte_Offset(0),
			editor.Byte_Offset(len(fixture.text)),
			observed,
		)
		testing.expect(t, inspect_ok)
		testing.expect_value(t, inspect_failure.code, editor.Failure_Code.None)
		testing.expect_value(t, copied, u64(len(fixture.text)))
		testing.expect_value(t, string(observed), fixture.text)
		delete(observed)

		closed, close_failure := editor.buffer_close(&buffer)
		testing.expect(t, closed)
		testing.expect_value(t, close_failure.code, editor.Failure_Code.None)
		testing.expect(t, !editor.buffer_is_live(&buffer))
	}
}

/* Ensures inspections expose bounded copies without lending rope storage. */
@(test)
inspection_does_not_lend_storage :: proc(t: ^testing.T) {
	limits := editor.DEFAULT_LIMITS
	limits.inspection_bytes = 4
	buffer: editor.Buffer
	initialized, failure := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(9),
		"a🙂bc",
		test_allocators(),
		limits,
	)
	testing.expect(t, initialized)
	testing.expect_value(t, failure.code, editor.Failure_Code.None)
	if !initialized {
		return
	}
	defer editor.buffer_close(&buffer)

	first: [4]byte
	_, first_ok, first_failure := editor.buffer_inspect(
		&buffer,
		editor.Byte_Offset(1),
		editor.Byte_Offset(5),
		first[:],
	)
	testing.expect(t, first_ok)
	testing.expect_value(t, first_failure.code, editor.Failure_Code.None)
	testing.expect_value(t, string(first[:]), "🙂")
	first[0] = 'x'

	second: [4]byte
	_, second_ok, _ := editor.buffer_inspect(
		&buffer,
		editor.Byte_Offset(1),
		editor.Byte_Offset(5),
		second[:],
	)
	testing.expect(t, second_ok)
	testing.expect_value(t, string(second[:]), "🙂")

	too_large: [5]byte
	_, limit_ok, limit_failure := editor.buffer_inspect(
		&buffer,
		editor.Byte_Offset(0),
		editor.Byte_Offset(5),
		too_large[:],
	)
	testing.expect(t, !limit_ok)
	testing.expect_value(t, limit_failure.code, editor.Failure_Code.Inspection_Limit)
	testing.expect_value(t, limit_failure.limit, u64(4))
	testing.expect_value(t, limit_failure.actual, u64(5))
}

/* Ensures positions reject split encodings and handles reject closed buffers. */
@(test)
positions_reject_mid_encoding_and_closed_buffers :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(11),
		"a🙂b",
		test_allocators(),
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}

	position, position_ok, position_failure := editor.buffer_position(&buffer, editor.Byte_Offset(1))
	testing.expect(t, position_ok)
	testing.expect_value(t, position_failure.code, editor.Failure_Code.None)
	testing.expect_value(t, position.buffer_id, editor.Buffer_ID(11))
	testing.expect_value(t, position.revision, editor.Revision(0))

	_, middle_ok, middle_failure := editor.buffer_position(&buffer, editor.Byte_Offset(2))
	testing.expect(t, !middle_ok)
	testing.expect_value(t, middle_failure.code, editor.Failure_Code.Mid_Encoding_Offset)

	_, range_ok, range_failure := editor.buffer_position(&buffer, editor.Byte_Offset(7))
	testing.expect(t, !range_ok)
	testing.expect_value(t, range_failure.code, editor.Failure_Code.Out_Of_Range)

	closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, closed)
	_, closed_ok, closed_failure := editor.buffer_position(&buffer, editor.Byte_Offset(0))
	testing.expect(t, !closed_ok)
	testing.expect_value(t, closed_failure.code, editor.Failure_Code.Closed_Buffer)
}

/* Ensures malformed or excessive initial text cannot create partial state. */
@(test)
init_rejects_bad_or_oversized_text :: proc(t: ^testing.T) {
	malformed_bytes := []byte{0xff}
	malformed: editor.Buffer
	malformed_ok, malformed_failure := editor.buffer_init(
		&malformed,
		editor.Buffer_ID(19),
		string(malformed_bytes),
		test_allocators(),
	)
	testing.expect(t, !malformed_ok)
	testing.expect_value(t, malformed_failure.code, editor.Failure_Code.Malformed_UTF8)

	text_limits := editor.DEFAULT_LIMITS
	text_limits.buffer_bytes = 4
	text_limits.replacement_bytes = 4
	text_limits.inspection_bytes = 4
	text_buffer: editor.Buffer
	text_ok, text_failure := editor.buffer_init(
		&text_buffer,
		editor.Buffer_ID(20),
		"abcde",
		test_allocators(),
		text_limits,
	)
	testing.expect(t, !text_ok)
	testing.expect_value(t, text_failure.code, editor.Failure_Code.Buffer_Limit)
	testing.expect_value(t, text_failure.limit, u64(4))
	testing.expect_value(t, text_failure.actual, u64(5))

	temporary_limits := editor.DEFAULT_LIMITS
	temporary_limits.temporary_bytes = 1
	temporary_buffer: editor.Buffer
	temporary_ok, temporary_failure := editor.buffer_init(
		&temporary_buffer,
		editor.Buffer_ID(21),
		"temporary budget",
		test_allocators(),
		temporary_limits,
	)
	testing.expect(t, !temporary_ok)
	testing.expect_value(t, temporary_failure.code, editor.Failure_Code.Temporary_Memory_Limit)

	persistent_limits := editor.DEFAULT_LIMITS
	persistent_limits.buffer_bytes = 1024
	persistent_limits.replacement_bytes = 1024
	persistent_limits.persistent_bytes = 1024
	persistent_limits.undo_bytes = 1024
	persistent_limits.inspection_bytes = 1024
	persistent_buffer: editor.Buffer
	persistent_ok, persistent_failure := editor.buffer_init(
		&persistent_buffer,
		editor.Buffer_ID(22),
		"persistent budget",
		test_allocators(),
		persistent_limits,
	)
	testing.expect(t, !persistent_ok)
	testing.expect_value(t, persistent_failure.code, editor.Failure_Code.Persistent_Memory_Limit)
}

/* Ensures persistent allocator faults leave no buffer-owned storage. */
@(test)
persistent_faults_leave_no_storage :: proc(t: ^testing.T) {
	for fail_after in 0 ..= 6 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		buffer: editor.Buffer
		initialized, failure := editor.buffer_init(
			&buffer,
			editor.Buffer_ID(13),
			"allocator fault",
			editor.Allocator_Set {
				persistent = failing_allocator(&failing),
				temporary = context.temp_allocator,
			},
		)

		if fail_after < 6 {
			testing.expect(t, !initialized)
			testing.expect_value(t, failure.code, editor.Failure_Code.Persistent_Memory_Limit)
		} else {
			testing.expect(t, initialized)
			if initialized {
				editor.buffer_close(&buffer)
			}
		}
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

/* Ensures temporary allocator faults release private and persistent state. */
@(test)
temp_faults_release_all_state :: proc(t: ^testing.T) {
	for fail_after in 0 ..= 2 {
		persistent_tracking: mem.Tracking_Allocator
		temporary_tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&persistent_tracking, context.allocator)
		mem.tracking_allocator_init(&temporary_tracking, context.allocator)
		failing_temporary := Failing_Allocator {
			backing = mem.tracking_allocator(&temporary_tracking),
			fail_after = u64(fail_after),
		}

		buffer: editor.Buffer
		initialized, failure := editor.buffer_init(
			&buffer,
			editor.Buffer_ID(15),
			"temporary fault",
			editor.Allocator_Set {
				persistent = mem.tracking_allocator(&persistent_tracking),
				temporary = failing_allocator(&failing_temporary),
			},
		)
		if fail_after < 2 {
			testing.expect(t, !initialized)
			testing.expect_value(t, failure.code, editor.Failure_Code.Temporary_Memory_Limit)
		} else {
			testing.expect(t, initialized)
			if initialized {
				editor.buffer_close(&buffer)
			}
		}
		testing.expect_value(t, persistent_tracking.current_memory_allocated, i64(0))
		testing.expect_value(t, temporary_tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&temporary_tracking)
		mem.tracking_allocator_destroy(&persistent_tracking)
	}
}

/* Guards the measured persistent-allocation target for large buffers. */
@(test)
hundred_mib_fits_memory_target :: proc(t: ^testing.T) {
	contents := make([]byte, 100 * int(MIB))
	defer delete(contents)
	for &value in contents {
		value = 'a'
	}

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	buffer: editor.Buffer
	initialized, failure := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(17),
		string(contents),
		editor.Allocator_Set {
			persistent = mem.tracking_allocator(&tracking),
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	testing.expect_value(t, failure.code, editor.Failure_Code.None)
	if !initialized {
		return
	}

	stats, stats_ok, _ := editor.buffer_stats(&buffer)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.text_bytes, 100 * MIB)
	testing.expect(t, stats.tree_height <= 8)
	testing.expect(t, stats.persistent_bytes <= 135 * MIB)
	closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(private)
Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
failing_allocator :: proc(data: ^Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator {
		procedure = failing_allocator_proc,
		data = data,
	}
}

@(private)
failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := (^Failing_Allocator)(allocator_data)
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize || mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after {
			return nil, .Out_Of_Memory
		}
		allocator.successful_allocations += 1
	}
	return allocator.backing.procedure(
		allocator.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}

@(private)
test_allocators :: proc() -> editor.Allocator_Set {
	return editor.Allocator_Set {
		persistent = context.allocator,
		temporary = context.temp_allocator,
	}
}
