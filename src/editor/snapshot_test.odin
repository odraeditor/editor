// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor

import "core:testing"

/* Verifies snapshot identity and bounded reads across rope leaves. */
@(test)
buffer_snapshots_read_exact_retained_revisions :: proc(t: ^testing.T) {
	contents: [8_209]byte
	for index in 0 ..< len(contents) {
		contents[index] = byte('a' + index % 26)
	}
	buffer: Buffer
	initialized, _ := buffer_init(
		&buffer,
		Buffer_ID(71),
		string(contents[:]),
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer buffer_close(&buffer)

	snapshot: Buffer_Snapshot
	opened, failure := buffer_snapshot_open(&buffer, &snapshot)
	testing.expectf(t, opened, "snapshot open failed with %v", failure.code)
	if !opened {
		return
	}
	defer buffer_snapshot_close(&snapshot)
	stats, stats_ok, _ := buffer_snapshot_stats(&snapshot)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.buffer_id, Buffer_ID(71))
	testing.expect_value(t, stats.revision, Revision(0))
	testing.expect_value(t, stats.text_bytes, u64(len(contents)))
	testing.expect(t, stats.shared_persistent_bytes > 0)

	actual: [193]byte
	copied, read_ok, read_failure := buffer_snapshot_read(&snapshot, Byte_Offset(4_050), actual[:])
	testing.expectf(t, read_ok, "snapshot read failed with %v", read_failure.code)
	testing.expect_value(t, copied, u64(len(actual)))
	testing.expect(t, string(actual[:]) == string(contents[4_050:4_050 + len(actual)]))
}

/* Verifies an older retained root survives both a concurrent edit and buffer closure. */
@(test)
buffer_snapshots_survive_edits_and_buffer_close :: proc(t: ^testing.T) {
	buffer: Buffer
	initialized, _ := buffer_init(
		&buffer,
		Buffer_ID(73),
		"old text",
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}

	snapshot: Buffer_Snapshot
	opened, _ := buffer_snapshot_open(&buffer, &snapshot)
	testing.expect(t, opened)
	if !opened {
		_, _ = buffer_close(&buffer)
		return
	}
	defer buffer_snapshot_close(&snapshot)

	start, _, _ := buffer_position(&buffer, Byte_Offset(0))
	end, _, _ := buffer_position(&buffer, Byte_Offset(3))
	_, _, published, _ := buffer_splice(
		&buffer,
		Splice{start = start, end = end, replacement = "new"},
		context.temp_allocator,
	)
	testing.expect(t, published)
	current, compared, compare_failure := buffer_snapshot_is_current(&buffer, &snapshot)
	testing.expectf(t, compared, "snapshot comparison failed with %v", compare_failure.code)
	testing.expect(t, !current)

	closed, _ := buffer_close(&buffer)
	testing.expect(t, closed)
	actual: [8]byte
	copied, read_ok, _ := buffer_snapshot_read(&snapshot, Byte_Offset(0), actual[:])
	testing.expect(t, read_ok)
	testing.expect_value(t, copied, u64(8))
	testing.expect(t, string(actual[:]) == "old text")
	_, compare_ok, closed_failure := buffer_snapshot_is_current(&buffer, &snapshot)
	testing.expect(t, !compare_ok)
	testing.expect_value(t, closed_failure.code, Failure_Code.Closed_Buffer)
}

/* Verifies closed and invalid snapshot operations fail without changing caller storage. */
@(test)
snapshots_reject_closed_handles :: proc(t: ^testing.T) {
	snapshot: Buffer_Snapshot
	_, stats_ok, stats_failure := buffer_snapshot_stats(&snapshot)
	testing.expect(t, !stats_ok)
	testing.expect_value(t, stats_failure.code, Failure_Code.Closed_Buffer)

	buffer: Buffer
	initialized, _ := buffer_init(
		&buffer,
		Buffer_ID(75),
		"abc",
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer buffer_close(&buffer)
	opened, _ := buffer_snapshot_open(&buffer, &snapshot)
	testing.expect(t, opened)
	if !opened {
		return
	}

	destination := [4]byte{0xaa, 0xaa, 0xaa, 0xaa}
	_, read_ok, read_failure := buffer_snapshot_read(&snapshot, Byte_Offset(4), destination[:])
	testing.expect(t, !read_ok)
	testing.expect_value(t, read_failure.code, Failure_Code.Out_Of_Range)
	testing.expect_value(t, destination, [4]byte{0xaa, 0xaa, 0xaa, 0xaa})

	closed, _ := buffer_snapshot_close(&snapshot)
	testing.expect(t, closed)
	closed_again, close_failure := buffer_snapshot_close(&snapshot)
	testing.expect(t, !closed_again)
	testing.expect_value(t, close_failure.code, Failure_Code.Closed_Buffer)
}
