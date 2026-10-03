// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../hosting"
import "../layout"
import "core:testing"

/* Verifies Racket inspects and mutates layouts through exact copied generations. */
@(private)
verify_racket_layout_capability :: proc(t: ^testing.T, runtime: ^hosting.Runtime) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "layout", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	registry: layout.Registry
	ready, ready_failure := layout.registry_init(
		&registry,
		layout.Owner_ID(901),
		layout.Layout_ID(902),
		&fixture.view_registry,
		fixture.view,
		layout.Geometry_Request{rows = 80, columns = 80},
	)
	testing.expectf(t, ready, "layout setup failed with %v", ready_failure.code)
	if !ready {
		return
	}
	defer layout.registry_close(&registry)

	capability, capability_ok := racket_layout_test_capability(&registry)
	testing.expect(t, capability_ok)
	if !capability_ok {
		return
	}
	for _ in 0 ..< 4 {
		_, inspected, inspect_failure := racket_layout_turn(runtime, capability, 0)
		testing.expectf(t, inspected, "repeated scope failed with %v", inspect_failure.code)
	}
	_, gc_ok, gc_failure := racket_layout_turn(runtime, capability, 2)
	testing.expectf(t, gc_ok, "forced GC failed with %v", gc_failure.code)
	_, snapshot_ok, snapshot_failure := racket_layout_turn(runtime, capability, 6)
	testing.expectf(t, snapshot_ok, "copied snapshot failed with %v", snapshot_failure.code)

	failure_scenarios := [?]struct{name: string, scenario: i32} {
		{"escaped-control", 1},
		{"cross-thread-control", 3},
		{"command-exception", 4},
		{"continuation-escape", 5},
	}
	for test_case in failure_scenarios {
		_, contained, contained_failure := racket_layout_turn(runtime, capability, test_case.scenario)
		testing.expectf(
			t,
			!contained,
			"%s layout scenario escaped with %v",
			test_case.name,
			contained_failure.code,
		)
	}

	composed, composed_ok, composed_failure := racket_layout_turn(runtime, capability, 7)
	testing.expectf(t, composed_ok, "Racket layout split failed with %v", composed_failure.code)
	if composed_ok {
		testing.expect_value(t, u64(composed.scope.layout_handle.generation), u64(2))
	}
	current, current_ok := racket_layout_test_capability(&registry)
	testing.expect(t, current_ok)
	if !current_ok {
		return
	}
	_, stale_ok, stale_failure := racket_layout_turn(runtime, current, 8)
	testing.expect(t, !stale_ok)
	testing.expect_value(
		t,
		stale_failure.layout_capability_code,
		Layout_Capability_Failure_Code.Wrong_Layout,
	)
	current, current_ok = racket_layout_test_capability(&registry)
	testing.expect(t, current_ok)
	if !current_ok {
		return
	}
	_, dedicated, dedication_failure := racket_layout_turn(runtime, current, 9)
	testing.expectf(t, dedicated, "Racket dedication failed with %v", dedication_failure.code)
	verify_racket_layout_hooks(t, runtime, &registry)

	current, current_ok = racket_layout_test_capability(&registry)
	testing.expect(t, current_ok)
	if !current_ok {
		return
	}
	inspection_only := current
	inspection_only.access = {.Inspect}
	inspection_only_scope, scoped, _ := layout_capability_scope(inspection_only)
	testing.expect(t, scoped)
	if scoped {
		_, permitted, permission_failure := layout_capability_request(
			&inspection_only,
			inspection_only_scope,
			.Split_Below,
			inspection_only_scope.pane,
		)
		testing.expect(t, !permitted)
		testing.expect_value(
			t,
			permission_failure.layout_capability_code,
			Layout_Capability_Failure_Code.Permission_Denied,
		)
	}
}

@(private)
verify_racket_layout_hooks :: proc(
	t: ^testing.T,
	runtime: ^hosting.Runtime,
	registry: ^layout.Registry,
) {
	deferred_hook: Racket_Layout_Hook
	initial_handle, _, _ := layout.registry_handle(registry)
	initial, _, _ := layout.registry_snapshot(registry, initial_handle)
	_, registered, register_failure := racket_layout_hook_register(
		runtime,
		registry,
		8,
		&deferred_hook,
	)
	testing.expectf(t, registered, "Racket deferred hook registration failed with %v", register_failure.code)
	if !registered {
		return
	}
	handle, _, _ := layout.registry_handle(registry)
	snapshot, _, _ := layout.registry_snapshot(registry, handle)
	_, dedicated, dedication_failure := layout.registry_pane_dedication_set(
		registry,
		snapshot.active_pane,
		.Hard,
	)
	testing.expectf(t, dedicated, "Racket hook trigger failed with %v", dedication_failure.code)
	current, _, _ := layout.registry_handle(registry)
	after, after_ok, _ := layout.registry_snapshot(registry, current)
	stats, stats_ok, _ := layout.registry_hook_stats(registry)
	_, deferred_failure, failures_ok := layout.registry_hook_failures(registry)
	testing.expect(t, after_ok && stats_ok && failures_ok)
	testing.expect_value(t, after.pane_count, initial.pane_count + 1)
	testing.expect_value(t, deferred_hook.calls, u64(2))
	testing.expect_value(t, deferred_hook.failures, u64(0))
	testing.expect_value(t, stats.notification_rounds, u64(2))
	testing.expect_value(t, stats.callback_calls, u64(2))
	testing.expect_value(t, stats.deferred_enqueued, u64(2))
	testing.expect_value(t, stats.deferred_processed, u64(2))
	testing.expect_value(t, stats.deferred_failures, u64(1))
	testing.expect_value(t, deferred_failure.code, layout.Failure_Code.Stale_Layout)
	released, release_failure := racket_layout_hook_release(&deferred_hook)
	testing.expectf(t, released, "Racket deferred hook release failed with %v", release_failure.code)

	exception_hook: Racket_Layout_Hook
	_, exception_registered, exception_register_failure := racket_layout_hook_register(
		runtime,
		registry,
		4,
		&exception_hook,
	)
	testing.expectf(
		t,
		exception_registered,
		"Racket exception hook registration failed with %v",
		exception_register_failure.code,
	)
	if !exception_registered {
		return
	}
	current, _, _ = layout.registry_handle(registry)
	after, _, _ = layout.registry_snapshot(registry, current)
	result, changed, change_failure := layout.registry_pane_dedication_set(
		registry,
		after.active_pane,
		.None,
	)
	testing.expectf(t, changed, "Racket exception hook trigger failed with %v", change_failure.code)
	testing.expect_value(t, result.current, layout.Pane_Dedication.None)
	callback_failure, _, _ := layout.registry_hook_failures(registry)
	testing.expect_value(t, exception_hook.calls, u64(1))
	testing.expect_value(t, exception_hook.failures, u64(1))
	testing.expect_value(t, exception_hook.last_failure.code, Failure_Code.Racket_Exception)
	testing.expect_value(t, callback_failure.code, layout.Failure_Code.Callback_Failure)
	released, release_failure = racket_layout_hook_release(&exception_hook)
	testing.expectf(t, released, "Racket exception hook release failed with %v", release_failure.code)
}

@(private)
racket_layout_test_capability :: proc(
	registry: ^layout.Registry,
) -> (capability: Layout_Capability_Context, ok: bool) {
	handle, handle_ok, _ := layout.registry_handle(registry)
	if !handle_ok {
		return {}, false
	}
	snapshot, snapshot_ok, _ := layout.registry_snapshot(registry, handle)
	if !snapshot_ok {
		return {}, false
	}
	return Layout_Capability_Context {
		registry = registry,
		access = {
			.Inspect,
			.Split_Below,
			.Split_Right,
			.Focus,
			.Close,
			.Keep_Only,
			.Resize,
			.Balance_Dimensions,
			.Balance_Areas,
			.Inspect_Dedication,
			.Set_Dedication,
		},
		layout_handle = handle,
		pane = snapshot.active_pane,
	}, true
}
