// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "core:testing"
import "../terminal_emulator"

@(test)
/* Verifies local override and negotiated child mouse routing. */
mouse_routing_respects_local_and_child_ownership :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	record, opened, _ := registry_open(
		&registry,
		test_open_request("mouse-routing", arguments = []string{"-c", "sleep 30"}),
	)
	testing.expect(t, opened)
	if !opened do return

	local, local_ok, local_failure := registry_route_mouse(
		&registry, record.ref, mouse_test_request(.Press, .Left), nil,
	)
	testing.expectf(t, local_ok, "local mouse failed with %v", local_failure.code)
	testing.expect_value(t, local.route, Mouse_Route.Local)
	testing.expect(t, !local.mouse_tracking)

	_ = terminal_emulator.write(
		record.emulator,
		transmute([]u8)(string("\x1b[?1000h\x1b[?1006h")),
	)
	child, child_ok, child_failure := registry_route_mouse(
		&registry, record.ref, mouse_test_request(.Press, .Left), nil,
	)
	testing.expectf(t, child_ok, "child mouse failed with %v", child_failure.code)
	testing.expect_value(t, child.route, Mouse_Route.Child)
	testing.expect(t, child.mouse_tracking)
	testing.expect(t, child.encoded_bytes > 0 && child.queued_bytes == child.encoded_bytes)
	motion, motion_ok, motion_failure := registry_route_mouse(
		&registry, record.ref, mouse_test_request(.Motion, .None), nil,
	)
	testing.expectf(t, motion_ok, "motion mouse failed with %v", motion_failure.code)
	testing.expect_value(t, motion.route, Mouse_Route.Child)
	testing.expect_value(t, motion.queued_bytes, u64(0))
	_ = terminal_emulator.write(record.emulator, transmute([]u8)(string("\x1b[?1002h")))
	drag, drag_ok, drag_failure := registry_route_mouse(
		&registry, record.ref, mouse_test_request(.Motion, .Left), nil,
	)
	testing.expectf(t, drag_ok, "drag mouse failed with %v", drag_failure.code)
	testing.expect_value(t, drag.route, Mouse_Route.Child)
	testing.expect(t, drag.queued_bytes > 0)

	shift_request := mouse_test_request(.Press, .Left)
	shift_request.modifiers = {.Shift}
	shifted, shifted_ok, shifted_failure := registry_route_mouse(
		&registry, record.ref, shift_request, nil,
	)
	testing.expectf(t, shifted_ok, "shift mouse failed with %v", shifted_failure.code)
	testing.expect_value(t, shifted.route, Mouse_Route.Local)
	testing.expect(t, shifted.mouse_tracking)
	testing.expect_value(t, shifted.queued_bytes, u64(0))

	wheel, wheel_ok, wheel_failure := registry_route_mouse(
		&registry, record.ref, mouse_test_request(.Press, .Wheel_Down), nil,
	)
	testing.expectf(t, wheel_ok, "wheel mouse failed with %v", wheel_failure.code)
	testing.expect_value(t, wheel.route, Mouse_Route.Child)
	testing.expect(t, wheel.queued_bytes > 0)
	resized, resize_failure := registry_resize(&registry, record.ref, 40, 10, 10, 20)
	testing.expectf(t, resized, "mouse resize failed with %v", resize_failure.code)
	resized_request := mouse_test_request(.Press, .Left)
	resized_request.x = 399
	resized_request.y = 199
	after_resize, after_resize_ok, after_resize_failure := registry_route_mouse(
		&registry, record.ref, resized_request, nil,
	)
	testing.expectf(t, after_resize_ok, "resized mouse failed with %v", after_resize_failure.code)
	testing.expect(t, after_resize.queued_bytes > 0)

	_ = terminal_emulator.write(record.emulator, transmute([]u8)(string("\x1b[?1000l\x1b[?1002l")))
	disabled, disabled_ok, _ := registry_route_mouse(
		&registry, record.ref, mouse_test_request(.Press, .Left), nil,
	)
	testing.expect(t, disabled_ok)
	testing.expect_value(t, disabled.route, Mouse_Route.Local)
	invalid_request := mouse_test_request(.Press, .Left)
	invalid_request.x = transmute(f32)u32(0x7fc00000)
	_, invalid_ok, invalid_failure := registry_route_mouse(
		&registry, record.ref, invalid_request, nil,
	)
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Invalid_Argument)
}

@(test)
/* Contains queue, lifecycle, ownership-race, and cross-session mouse failures. */
mouse_routing_contains_failure_and_session_boundaries :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil do _, _ = registry_close(&registry)
	limited_request := test_open_request(
		"mouse-limited",
		arguments = []string{"-c", "sleep 30"},
	)
	limited_request.process.limits.input_bytes = 1
	limited, limited_opened, limited_failure := registry_open(&registry, limited_request)
	testing.expectf(t, limited_opened, "limited terminal failed with %v", limited_failure.code)
	if !limited_opened do return
	isolated, isolated_opened, isolated_failure := registry_open(
		&registry,
		test_open_request("mouse-isolated", arguments = []string{"-c", "sleep 30"}),
	)
	testing.expectf(t, isolated_opened, "isolated terminal failed with %v", isolated_failure.code)
	if !isolated_opened do return
	_ = terminal_emulator.write(
		limited.emulator,
		transmute([]u8)(string("\x1b[?1000h\x1b[?1002h\x1b[?1006h")),
	)

	_, queued, queue_failure := registry_route_mouse(
		&registry, limited.ref, mouse_test_request(.Press, .Left), nil,
	)
	testing.expect(t, !queued)
	testing.expect_value(t, queue_failure.stage, Failure_Stage.Mouse)
	testing.expect_value(t, queue_failure.code, Failure_Code.Input_Limit)
	limited_record, limited_recorded, _ := registry_record(&registry, limited.ref)
	isolated_record, isolated_recorded, _ := registry_record(&registry, isolated.ref)
	testing.expect(t, limited_recorded && isolated_recorded)
	if limited_recorded do testing.expect_value(t, limited_record.process.resources.queued_input_bytes, u64(0))
	if isolated_recorded do testing.expect_value(t, isolated_record.process.resources.queued_input_bytes, u64(0))

	shifted := mouse_test_request(.Press, .Left)
	shifted.modifiers = {.Shift}
	local, local_ok, local_failure := registry_route_mouse(
		&registry, limited.ref, shifted, nil,
	)
	testing.expectf(t, local_ok, "Shift override failed with %v", local_failure.code)
	if local_ok do testing.expect_value(t, local.route, Mouse_Route.Local)

	_ = terminal_emulator.write(
		limited.emulator,
		transmute([]u8)(string("\x1b[?1000l\x1b[?1002l")),
	)
	after_disable, disabled_ok, disabled_failure := registry_route_mouse(
		&registry, limited.ref, mouse_test_request(.Motion, .Left), nil,
	)
	testing.expectf(t, disabled_ok, "ownership transition failed with %v", disabled_failure.code)
	if disabled_ok do testing.expect_value(t, after_disable.route, Mouse_Route.Local)

	stale := limited.ref
	stale.generation += 1
	_, stale_ok, stale_failure := registry_route_mouse(
		&registry, stale, mouse_test_request(.Press, .Left), nil,
	)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.stage, Failure_Stage.Mouse)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Reference)
	closed, close_failure := registry_close_session(&registry, limited.ref)
	testing.expectf(t, closed, "terminal close failed with %v", close_failure.code)
	_, closed_ok, closed_failure := registry_route_mouse(
		&registry, limited.ref, mouse_test_request(.Press, .Left), nil,
	)
	testing.expect(t, !closed_ok)
	testing.expect_value(t, closed_failure.stage, Failure_Stage.Mouse)
	testing.expect_value(t, closed_failure.code, Failure_Code.Stale_Reference)
}

@(test)
/* Verifies links stay inert until explicit validated activation. */
hyperlinks_require_explicit_safe_activation :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	record, opened, _ := registry_open(
		&registry,
		test_open_request("hyperlinks", arguments = []string{"-c", "sleep 30"}),
	)
	testing.expect(t, opened)
	if !opened do return

	_ = terminal_emulator.write(
		record.emulator,
		transmute([]u8)(string("\x1b]8;;https://example.com/path\x07link\x1b]8;;\x07\r")),
	)
	revision, projected, projection_failure := registry_project_render(&registry, record.ref)
	testing.expectf(t, projected, "link projection failed with %v", projection_failure.code)
	if projected {
		cells, allocation_error := make(
			[]Render_Cell, int(revision.cell_count), context.temp_allocator,
		)
		testing.expect(t, allocation_error == nil)
		if allocation_error == nil {
			defer delete(cells, context.temp_allocator)
			_, copied, _ := registry_copy_render_cells(&registry, record.ref, cells)
			testing.expect(t, copied)
			if copied do testing.expect(t, cells[0].hyperlink)
		}
	}

	target: [MAX_HYPERLINK_BYTES]u8
	control_click := mouse_test_request(.Press, .Left)
	control_click.modifiers = {.Control}
	linked, linked_ok, linked_failure := registry_route_mouse(
		&registry, record.ref, control_click, target[:],
	)
	testing.expectf(t, linked_ok, "link activation failed with %v", linked_failure.code)
	testing.expect_value(t, linked.route, Mouse_Route.Hyperlink)
	testing.expect_value(t, string(target[:int(linked.hyperlink_bytes)]), "https://example.com/path")
	testing.expect_value(t, linked.queued_bytes, u64(0))

	_ = terminal_emulator.write(
		record.emulator,
		transmute([]u8)(string("\x1b[2K\r\x1b]8;;javascript:alert(1)\x07bad\x1b]8;;\x07\r")),
	)
	_, unsafe_ok, unsafe_failure := registry_route_mouse(
		&registry, record.ref, control_click, target[:],
	)
	testing.expect(t, !unsafe_ok)
	testing.expect_value(t, unsafe_failure.code, Failure_Code.Hyperlink_Rejected)
}

@(test)
/* Verifies the initial hyperlink scheme and syntax allowlist. */
hyperlink_validation_rejects_unsafe_targets :: proc(t: ^testing.T) {
	cases := []struct {
		target: string,
		kind:   Hyperlink_Target_Kind,
		safe:   bool,
	} {
		{"https://example.com", .HTTPS, true},
		{"http://example.com/a", .HTTP, true},
		{"mailto:user@example.com", .Mailto, true},
		{"file:///tmp/example", .File, true},
		{"javascript:alert(1)", .Invalid, false},
		{"data:text/plain,bad", .Invalid, false},
		{"https://", .Invalid, false},
		{"https:///missing-host", .Invalid, false},
		{"https://example.com/a b", .Invalid, false},
		{"1bad:value", .Invalid, false},
	}
	for test_case in cases {
		kind, safe := hyperlink_target_kind(test_case.target)
		testing.expect_value(t, safe, test_case.safe)
		testing.expect_value(t, kind, test_case.kind)
	}
}

@(private)
mouse_test_request :: proc(action: Mouse_Action, button: Mouse_Button) -> Mouse_Request {
	return {action = action, button = button, x = 1, y = 1}
}
