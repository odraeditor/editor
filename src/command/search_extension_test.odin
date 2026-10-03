// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor"
import "../kill_ring"
import "../search"
import "core:testing"

/* Verifies nearby textual and structural units are copied without buffer mutation. */
@(test)
search_extensions_copy_distinct_nearby_units :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, failure := editor.buffer_init(
		&buffer,
		401,
		"  alpha.beta  gamma",
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, initialized, "buffer init failed with %v", failure.code)
	if !initialized {
		return
	}
	defer editor.buffer_close(&buffer)
	before, _, _ := editor.buffer_stats(&buffer)
	textual, text_ok, text_failure := search_query_extend_nearby(
		&buffer,
		0,
		.Textual,
		.Literal,
		search.DEFAULT_PATTERN_BYTES,
		context.allocator,
		context.temp_allocator,
	)
	testing.expectf(t, text_ok, "text extension failed with %v", text_failure.code)
	if text_ok {
		testing.expect_value(t, textual.text, "alpha")
		search_query_extension_close(&textual)
	}
	structural, structural_ok, structural_failure := search_query_extend_nearby(
		&buffer,
		0,
		.Structural,
		.Literal,
		search.DEFAULT_PATTERN_BYTES,
		context.allocator,
		context.temp_allocator,
	)
	testing.expectf(t, structural_ok, "structural extension failed with %v", structural_failure.code)
	if structural_ok {
		testing.expect_value(t, structural.text, "alpha.beta")
		search_query_extension_close(&structural)
	}
	after, _, _ := editor.buffer_stats(&buffer)
	testing.expect_value(t, after.revision, before.revision)
	testing.expect_value(t, after.text_bytes, before.text_bytes)
}

/* Verifies transferred text is copied and escaped for expression queries. */
@(test)
search_extension_escapes_transferred_text :: proc(t: ^testing.T) {
	ring: kill_ring.Ring
	initialized, failure := kill_ring.ring_init(
		&ring,
		401,
		kill_ring.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, initialized, "ring init failed with %v", failure.code)
	if !initialized {
		return
	}
	defer kill_ring.ring_close(&ring)
	test_ring_admit(t, &ring, "alpha.beta+")
	before, _, _ := kill_ring.ring_stats(&ring)
	extension, available, extension_failure := search_query_extend_transfer(
		&ring,
		.Regular_Expression,
		search.DEFAULT_PATTERN_BYTES,
		context.allocator,
	)
	testing.expectf(t, available, "transfer extension failed with %v", extension_failure.code)
	if available {
		testing.expect_value(t, extension.text, "alpha\\.beta\\+")
		search_query_extension_close(&extension)
	}
	after, _, _ := kill_ring.ring_stats(&ring)
	testing.expect_value(t, after.generation, before.generation)
	testing.expect_value(t, after.newest, before.newest)
}

/* Verifies rejected extension limits leave no owned result. */
@(test)
search_extension_rejects_oversized_values :: proc(t: ^testing.T) {
	ring: kill_ring.Ring
	initialized, _ := kill_ring.ring_init(
		&ring,
		403,
		kill_ring.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer kill_ring.ring_close(&ring)
	test_ring_admit(t, &ring, "too-long")
	extension, available, failure := search_query_extend_transfer(
		&ring,
		.Literal,
		3,
		context.allocator,
	)
	testing.expect(t, !available)
	testing.expect_value(t, failure.code, Failure_Code.Kill_Ring_Failure)
	testing.expect_value(t, extension, Search_Query_Extension{})
}
