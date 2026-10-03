// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor

import "core:testing"

/* Verifies terminal projections are inspectable but reject every ordinary edit path. */
@(test)
terminal_projection_is_read_only :: proc(t: ^testing.T) {
	buffer: Buffer
	initialized, init_failure := buffer_init(
		&buffer,
		Buffer_ID(901),
		"prompt> ready",
		Allocator_Set {persistent = context.allocator, temporary = context.temp_allocator},
		DEFAULT_LIMITS,
		.Terminal_Projection,
	)
	testing.expectf(t, initialized, "terminal projection init failed with %v", init_failure.code)
	if !initialized do return
	defer {
		closed, _ := buffer_close(&buffer)
		testing.expect(t, closed)
	}
	stats, inspected, _ := buffer_stats(&buffer)
	testing.expect(t, inspected)
	testing.expect_value(t, stats.kind, Buffer_Kind.Terminal_Projection)
	start, _, _ := buffer_position(&buffer, 0)
	end, _, _ := buffer_position(&buffer, Byte_Offset(stats.text_bytes))
	_, _, changed, splice_failure := buffer_splice(
		&buffer,
		Splice {start = start, end = end, replacement = "edited"},
		context.temp_allocator,
	)
	testing.expect(t, !changed)
	testing.expect_value(t, splice_failure.code, Failure_Code.Read_Only_Buffer)
	_, working_opened, working_failure := buffer_working_revision_open(&buffer)
	testing.expect(t, !working_opened)
	testing.expect_value(t, working_failure.code, Failure_Code.Read_Only_Buffer)
}

/* Verifies editable buffers can publish and revoke a read-only mutation policy. */
@(test)
text_buffer_read_only_policy_is_reversible :: proc(t: ^testing.T) {
	buffer: Buffer
	initialized, _ := buffer_init(
		&buffer,
		Buffer_ID(904),
		"text",
		Allocator_Set {persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer buffer_close(&buffer)

	changed, set_ok, _ := buffer_read_only_set(&buffer, true)
	testing.expect(t, changed && set_ok)
	read_only, inspected, _ := buffer_read_only(&buffer)
	testing.expect(t, inspected && read_only)
	start, _, _ := buffer_position(&buffer, 0)
	_, _, spliced, splice_failure := buffer_splice(
		&buffer,
		Splice {start = start, end = start, replacement = "x"},
		context.temp_allocator,
	)
	testing.expect(t, !spliced)
	testing.expect_value(t, splice_failure.code, Failure_Code.Read_Only_Buffer)

	changed, set_ok, _ = buffer_read_only_set(&buffer, false)
	testing.expect(t, changed && set_ok)
	read_only, inspected, _ = buffer_read_only(&buffer)
	testing.expect(t, inspected && !read_only)
}

/* Verifies the projection owner can atomically replace copied text without an undo edit. */
@(test)
terminal_projection_owner_refreshes_text :: proc(t: ^testing.T) {
	buffer: Buffer
	initialized, _ := buffer_init(
		&buffer,
		Buffer_ID(902),
		"first",
		Allocator_Set {persistent = context.allocator, temporary = context.temp_allocator},
		DEFAULT_LIMITS,
		.Terminal_Projection,
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer buffer_close(&buffer)
	revision, replaced, replace_failure := buffer_projection_replace(
		&buffer,
		"second\n🙂",
		context.temp_allocator,
	)
	testing.expectf(t, replaced, "projection refresh failed with %v", replace_failure.code)
	testing.expect_value(t, revision, Revision(1))
	stats, stats_ok, _ := buffer_stats(&buffer)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.text_bytes, u64(len("second\n🙂")))
	bytes: [32]byte
	copied, copied_ok, _ := buffer_inspect(
		&buffer,
		0,
		Byte_Offset(stats.text_bytes),
		bytes[:],
	)
	testing.expect(t, copied_ok)
	testing.expect_value(t, string(bytes[:copied]), "second\n🙂")
}

/* Verifies projection authority cannot be applied to editable text buffers. */
@(test)
text_buffer_rejects_projection_refresh :: proc(t: ^testing.T) {
	buffer: Buffer
	initialized, _ := buffer_init(
		&buffer,
		Buffer_ID(903),
		"text",
		Allocator_Set {persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer buffer_close(&buffer)
	_, replaced, failure := buffer_projection_replace(&buffer, "projection", context.temp_allocator)
	testing.expect(t, !replaced)
	testing.expect_value(t, failure.code, Failure_Code.Wrong_Buffer_Kind)
}
