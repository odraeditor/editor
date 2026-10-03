// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../hosting"
import "core:os"
import "core:testing"

/* verify_named_slot_commands covers typed persistence through the embedded runtime. */
@(private)
verify_named_slot_commands :: proc(t: ^testing.T, racket_runtime: ^hosting.Runtime) {
	root, root_error := os.make_directory_temp("", "odra-named-slot-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer {
		os.remove_all(root)
		delete(root)
	}
	permissions_error := os.chmod(root, os.Permissions{.Read_User, .Write_User, .Execute_User})
	testing.expect(t, permissions_error == nil)
	if permissions_error != nil do return

	integer, stored, store_failure := named_slot_store_integer(
		racket_runtime, root, "counter", -3, false, context.allocator,
	)
	testing.expectf(t, stored, "Integer store failed: %v", store_failure.code)
	if stored {
		testing.expect_value(t, len(integer.slots), 1)
		testing.expect_value(t, integer.slots[0].kind, Named_Slot_Kind.Integer)
		testing.expect_value(t, integer.slots[0].integer, i64(-3))
		named_slot_batch_close(&integer)
	}

	incremented, increment_ok, increment_failure := named_slot_increment_integer(
		racket_runtime, root, "counter", 8, context.allocator,
	)
	testing.expectf(t, increment_ok, "Integer increment failed: %v", increment_failure.code)
	if increment_ok {
		testing.expect_value(t, incremented.slots[0].integer, i64(5))
		named_slot_batch_close(&incremented)
	}

	conflict, conflict_ok, conflict_failure := named_slot_store_text(
		racket_runtime, root, "counter", "pięć", false, context.allocator,
	)
	testing.expect(t, !conflict_ok)
	testing.expect_value(t, conflict_failure.code, Failure_Code.Invalid_Request)
	testing.expect_value(t, conflict.conflict_kind, Named_Slot_Kind.Integer)
	if conflict.state != nil do named_slot_batch_close(&conflict)

	text, text_ok, text_failure := named_slot_store_text(
		racket_runtime, root, "counter", "pięć", true, context.allocator,
	)
	testing.expectf(t, text_ok, "Text replacement failed: %v", text_failure.code)
	if text_ok do named_slot_batch_close(&text)

	found, found_ok, found_failure := named_slot_lookup_text(
		racket_runtime, root, "counter", context.allocator,
	)
	testing.expectf(t, found_ok, "Text lookup failed: %v", found_failure.code)
	if found_ok {
		testing.expect_value(t, len(found.slots), 1)
		testing.expect_value(t, found.slots[0].text, "pięć")
		named_slot_batch_close(&found)
	}

	maximum, maximum_ok, _ := named_slot_store_integer(
		racket_runtime, root, "maximum", max(i64), false, context.allocator,
	)
	testing.expect(t, maximum_ok)
	if maximum_ok do named_slot_batch_close(&maximum)
	overflow, overflow_ok, overflow_failure := named_slot_increment_integer(
		racket_runtime, root, "maximum", 1, context.allocator,
	)
	testing.expect(t, !overflow_ok)
	testing.expect_value(t, overflow_failure.code, Failure_Code.Wrong_Result)
	if overflow.state != nil do named_slot_batch_close(&overflow)

	position, position_ok, position_failure := named_slot_store_position(
		racket_runtime,
		root,
		"position",
		"/tmp/źródło.odin",
		"źródło.odin",
		42,
		false,
		context.allocator,
	)
	testing.expectf(t, position_ok, "Position store failed: %v", position_failure.code)
	if position_ok {
		found_position := false
		for slot in position.slots {
			if slot.name == "position" {
				found_position = true
				testing.expect_value(t, slot.kind, Named_Slot_Kind.Position)
				testing.expect_value(t, slot.target, "/tmp/źródło.odin")
				testing.expect_value(t, slot.point, u64(42))
			}
		}
		testing.expect(t, found_position)
		named_slot_batch_close(&position)
	}

	layout_value := "ODRA-LAYOUT-1\nV\t1\t0\tL3RtcC9sYXlvdXQub2Rpbg=="
	layout_slot, layout_ok, layout_failure := named_slot_store_layout(
		racket_runtime, root, "layout", layout_value, false, context.allocator,
	)
	testing.expectf(t, layout_ok, "Layout store failed: %v", layout_failure.code)
	if layout_ok do named_slot_batch_close(&layout_slot)
	layout_found, found_layout, lookup_failure := named_slot_lookup_layout(
		racket_runtime, root, "layout", context.allocator,
	)
	testing.expectf(t, found_layout, "Layout lookup failed: %v", lookup_failure.code)
	if found_layout {
		testing.expect_value(t, len(layout_found.slots), 1)
		testing.expect_value(t, layout_found.slots[0].kind, Named_Slot_Kind.Layout)
		testing.expect_value(t, layout_found.slots[0].text, layout_value)
		named_slot_batch_close(&layout_found)
	}
}
