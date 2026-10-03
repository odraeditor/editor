// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package display_projection_tests

import "../../src/display"
import "../../src/editor"
import "../../src/view"
import "core:testing"

/* Verifies two views project independently and old display snapshots reject a committed edit. */
@(test)
two_views_project_one_edit :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(301),
		"first\nsecond\nthird",
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, buffer_ok)
	if !buffer_ok {
		return
	}
	registry: view.Registry
	registry_ok, _ := view.registry_init(&registry, view.Registry_ID(301), context.allocator)
	first, first_ok, _ := view.create(&registry, &buffer)
	second, second_ok, _ := view.clone_additional(&registry, first)
	testing.expect(t, registry_ok && first_ok && second_ok)
	if !registry_ok || !first_ok || !second_ok {
		if registry_ok {
			view.registry_close(&registry)
		}
		editor.buffer_close(&buffer)
		return
	}
	defer {
		view.close(&registry, &second)
		view.close(&registry, &first)
		view.registry_close(&registry)
		editor.buffer_close(&buffer)
	}
	second_origin, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(6))
	second_viewport, _ := view.set_viewport(&registry, second, second_origin, 1)
	testing.expect(t, second_viewport)
	first_logical, _, _ := view.snapshot(&registry, first)
	second_logical, _, _ := view.snapshot(&registry, second)
	constraints := display.Viewport_Constraints{width_cells = 12, height_rows = 2}
	first_display, first_projected, _ := display.project(
		&buffer,
		display_request(1, first_logical, constraints),
	)
	second_display, second_projected, _ := display.project(
		&buffer,
		display_request(2, second_logical, constraints),
	)
	testing.expect(t, first_projected && second_projected)
	if !first_projected || !second_projected {
		if first_projected {
			display.snapshot_close(&first_display)
		}
		if second_projected {
			display.snapshot_close(&second_display)
		}
		return
	}
	first_result, _, _ := display.snapshot_view(first_display)
	second_result, _, _ := display.snapshot_view(second_display)
	testing.expect_value(t, first_result.text, "firstsecond")
	testing.expect_value(t, second_result.text, "econdhird")

	start, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(0))
	_, _, published, _ := editor.buffer_splice(
		&buffer,
		editor.Splice{start = start, end = start, replacement = "X"},
		context.temp_allocator,
	)
	testing.expect(t, published)
	current_first, _, _ := view.snapshot(&registry, first)
	current_second, _, _ := view.snapshot(&registry, second)
	_, stale_failure := display.snapshot_is_compatible(
		first_display,
		current_first,
		constraints,
		display.terminal_unicode17_profile(),
	)
	testing.expect_value(t, stale_failure.code, display.Failure_Code.Stale_Snapshot)
	display.snapshot_close(&first_display)
	display.snapshot_close(&second_display)

	updated_first, updated_first_ok, _ := display.project(
		&buffer,
		display_request(3, current_first, constraints),
	)
	updated_second, updated_second_ok, _ := display.project(
		&buffer,
		display_request(4, current_second, constraints),
	)
	testing.expect(t, updated_first_ok && updated_second_ok)
	if updated_first_ok {
		updated, _, _ := display.snapshot_view(updated_first)
		testing.expect_value(t, updated.text, "Xfirstsecond")
		display.snapshot_close(&updated_first)
	}
	if updated_second_ok {
		updated, _, _ := display.snapshot_view(updated_second)
		testing.expect_value(t, updated.text, "econdhird")
		display.snapshot_close(&updated_second)
	}
}

@(private)
display_request :: proc(
	id: u64,
	logical: view.Snapshot,
	constraints: display.Viewport_Constraints,
) -> display.Projection_Request {
	return display.Projection_Request {
		snapshot_id = display.Snapshot_ID(id),
		view = logical,
		constraints = constraints,
		profile = display.terminal_unicode17_profile(),
		limits = display.DEFAULT_RESOURCE_LIMITS,
		allocators = display.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	}
}
