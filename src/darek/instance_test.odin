// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package darek

import "../filesystem"
import "base:runtime"
import "core:mem"
import "core:testing"

@(test)
/* instance_lifecycle_retains_checked_root_visibility_and_exact_cleanup. */
lifecycle_retains_checked_root_visibility :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, runtime.default_allocator())
	allocator := mem.tracking_allocator(&tracking)
	instance: Instance
	opened, open_failure := instance_open(
		&instance,
		Config{id = 1, generation = 1, policy = DEFAULT_POLICY, allocator = allocator},
		Root_Request {
			mode = .Directory,
			path = "/tmp/darek-root",
			resource = {provider = filesystem.LOCAL_PROVIDER_ID, device = 4, inode = 9},
		},
	)
	view, usage, inspected, _ := instance_inspect(&instance)
	hidden, hidden_ok, _ := instance_set_visible(&instance, false)
	placed, placed_ok, _ := instance_set_panel_side(&instance, .Right)
	width, widened, width_ok, _ := instance_adjust_panel_width(&instance, i32(PANEL_WIDTH_STEP))
	extra_width, extra_enabled, extra_changed, extra_ok, _ := instance_toggle_extra_width(&instance)
	locked, lock_changed, lock_ok, _ := instance_toggle_width_lock(&instance)
	hidden_view, _, hidden_inspected, _ := instance_inspect(&instance)
	closed, close_failure := instance_close(&instance)
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	testing.expectf(t, opened, "open failed with %v", open_failure.code)
	testing.expect(t, inspected && hidden && hidden_ok && hidden_inspected && closed)
	testing.expect(t, placed && placed_ok && widened && width_ok)
	testing.expect(t, extra_enabled && extra_changed && extra_ok && locked && lock_changed && lock_ok)
	testing.expect_value(t, width, DEFAULT_PANEL_WIDTH + PANEL_WIDTH_STEP)
	testing.expect_value(t, extra_width, EXTRA_PANEL_WIDTH)
	testing.expect_value(t, view.id, Instance_ID(1))
	testing.expect_value(t, view.root.mode, Root_Mode.Directory)
	testing.expect_value(t, view.root.path, "/tmp/darek-root")
	testing.expect(t, view.visible && !hidden_view.visible)
	testing.expect_value(t, hidden_view.panel.side, Panel_Side.Right)
	testing.expect(t, hidden_view.panel.extra_width && hidden_view.panel.width_locked)
	testing.expect_value(t, usage.nodes, u32(0))
	testing.expect_value(t, usage.retained_bytes, u64(0))
	testing.expect_value(t, close_failure.code, Failure_Code.None)
	testing.expect_value(t, cleanup_bytes, i64(0))
}

@(test)
/* instance_open_rejects_invalid_identity_policy_and_root_without_partial_state. */
open_rejects_invalid_identity_policy :: proc(t: ^testing.T) {
	instance: Instance
	config := Config {
		id = 1,
		generation = 1,
		policy = DEFAULT_POLICY,
		allocator = context.allocator,
	}
	invalid_root := Root_Request{mode = .Directory, path = "relative"}
	opened, failure := instance_open(&instance, config, invalid_root)
	_, _, inspected, inspect_failure := instance_inspect(&instance)
	testing.expect(t, !opened && !inspected)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Root)
	testing.expect_value(t, inspect_failure.code, Failure_Code.Invalid_Instance)
}
