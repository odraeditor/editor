// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

import "../editor"
import "../view"
import "base:runtime"
import "core:testing"

@(private)
Hook_Test_State :: struct {
	calls:              u64,
	first_generation:   Layout_Generation,
	first_nodes:        u16,
	second_generation:  Layout_Generation,
	second_nodes:       u16,
	enqueue_once:       bool,
	enqueue_two:        bool,
	callback_succeeds:  bool,
	direct_reentrant_busy: bool,
	teardown_reentrant_busy: bool,
	second_enqueue_code: Failure_Code,
}

/* Verifies hooks share immutable generations and deferred requests publish afterward. */
@(test)
hooks_notify_before_fifo_deferred_mutations :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	ready := geometry_test_registry(21_001, 24, 80, &buffer, &views, &root_view, &registry)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer geometry_test_close(&buffer, &views, &root_view, &registry)

	first_state := Hook_Test_State{enqueue_once = true, callback_succeeds = true}
	second_state := Hook_Test_State{callback_succeeds = true}
	first, first_ok, _ := registry_hook_register(&registry, hook_test_callback, &first_state)
	second, second_ok, _ := registry_hook_register(&registry, hook_test_callback, &second_state)
	testing.expect(t, first_ok && second_ok)
	handle, _, _ := registry_handle(&registry)
	snapshot, _, _ := registry_snapshot(&registry, handle)
	_, changed, change_failure := registry_pane_dedication_set(
		&registry, snapshot.active_pane, .Soft,
	)
	testing.expectf(t, changed, "publication failed with %v", change_failure.code)

	final_handle, _, _ := registry_handle(&registry)
	final, final_ok, _ := registry_snapshot(&registry, final_handle)
	stats, stats_ok, _ := registry_hook_stats(&registry)
	testing.expect(t, final_ok && stats_ok)
	testing.expect_value(t, final.pane_count, u16(2))
	testing.expect_value(t, u64(final.handle.generation), u64(3))
	testing.expect_value(t, first_state.first_generation, Layout_Generation(2))
	testing.expect_value(t, second_state.first_generation, Layout_Generation(2))
	testing.expect_value(t, first_state.first_nodes, u16(1))
	testing.expect_value(t, second_state.first_nodes, u16(1))
	testing.expect_value(t, first_state.second_generation, Layout_Generation(3))
	testing.expect_value(t, second_state.second_generation, Layout_Generation(3))
	testing.expect(t, first_state.direct_reentrant_busy)
	testing.expect(t, first_state.teardown_reentrant_busy)
	testing.expect_value(t, stats.notification_rounds, u64(2))
	testing.expect_value(t, stats.callback_calls, u64(4))
	testing.expect_value(t, stats.deferred_enqueued, u64(1))
	testing.expect_value(t, stats.deferred_processed, u64(1))
	testing.expect_value(t, stats.deferred_failures, u64(0))

	first_released, _ := registry_hook_release(&registry, &first)
	second_released, _ := registry_hook_release(&registry, &second)
	testing.expect(t, first_released && second_released)
}

/* Verifies earlier deferred publications make later same-round requests stale. */
@(test)
hook_deferred_requests_revalidate_in_fifo_order :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	ready := geometry_test_registry(21_011, 24, 80, &buffer, &views, &root_view, &registry)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer geometry_test_close(&buffer, &views, &root_view, &registry)

	state := Hook_Test_State{enqueue_two = true, callback_succeeds = true}
	hook, registered, _ := registry_hook_register(&registry, hook_test_callback, &state)
	testing.expect(t, registered)
	handle, _, _ := registry_handle(&registry)
	snapshot, _, _ := registry_snapshot(&registry, handle)
	_, changed, _ := registry_pane_dedication_set(&registry, snapshot.active_pane, .Soft)
	testing.expect(t, changed)
	stats, stats_ok, _ := registry_hook_stats(&registry)
	_, deferred_failure, failures_ok := registry_hook_failures(&registry)
	testing.expect(t, stats_ok && failures_ok)
	testing.expect_value(t, stats.deferred_enqueued, u64(2))
	testing.expect_value(t, stats.deferred_processed, u64(2))
	testing.expect_value(t, stats.deferred_failures, u64(1))
	testing.expect_value(t, deferred_failure.code, Failure_Code.Stale_Layout)
	testing.expect_value(t, deferred_failure.deferred_sequence, Deferred_Sequence(2))
	registry_hook_release(&registry, &hook)
}

/* Verifies callback and capacity failures preserve the committed publication. */
@(test)
layout_hook_failures_are_contained_and_bounded :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	policy := DEFAULT_POLICY
	policy.layout_hooks = 1
	policy.deferred_requests = 1
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(21_021),
		"hooks",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	views_ok, _ := view.registry_init(&views, view.Registry_ID(21_021), context.allocator)
	created_view, root_ok, _ := view.create(&views, &buffer)
	root_view = created_view
	registry_ok, _ := registry_init(
		&registry,
		Owner_ID(21_021),
		Layout_ID(21_021),
		&views,
		root_view,
		Geometry_Request{rows = 24, columns = 80},
		policy,
	)
	ready := buffer_ok && views_ok && root_ok && registry_ok
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer geometry_test_close(&buffer, &views, &root_view, &registry)

	state := Hook_Test_State{enqueue_two = true, callback_succeeds = false}
	hook, registered, _ := registry_hook_register(&registry, hook_test_callback, &state)
	_, overflow_registered, overflow_failure := registry_hook_register(
		&registry, hook_test_callback, &state,
	)
	testing.expect(t, registered && !overflow_registered)
	testing.expect_value(t, overflow_failure.code, Failure_Code.Hook_Limit)
	handle, _, _ := registry_handle(&registry)
	snapshot, _, _ := registry_snapshot(&registry, handle)
	result, changed, _ := registry_pane_dedication_set(&registry, snapshot.active_pane, .Soft)
	testing.expect(t, changed)
	testing.expect_value(t, result.current, Pane_Dedication.Soft)
	testing.expect_value(t, state.second_enqueue_code, Failure_Code.Deferred_Limit)
	stats, _, _ := registry_hook_stats(&registry)
	callback_failure, _, _ := registry_hook_failures(&registry)
	testing.expect_value(t, stats.callback_failures, u64(2))
	testing.expect_value(t, callback_failure.code, Failure_Code.Callback_Failure)
	testing.expect_value(t, callback_failure.operation, Operation.Notify_Hooks)
	testing.expect(t, callback_failure.hook.hook_id != Hook_ID(0))
	registry_hook_release(&registry, &hook)
}

@(private)
hook_test_callback :: proc "c" (
	user_data: rawptr,
	hook: Hook_Handle,
	snapshot: ^Snapshot,
	ctx: ^Hook_Callback_Context,
) -> bool {
	context = runtime.default_context()
	state := (^Hook_Test_State)(user_data)
	assert(state != nil && snapshot != nil && ctx != nil && hook == ctx.hook)
	state.calls += 1
	if state.calls == 1 {
		state.first_generation = snapshot.handle.generation
		state.first_nodes = snapshot.node_count
		_, reentrant, reentrant_failure := registry_focus(ctx.registry, snapshot.active_pane)
		state.direct_reentrant_busy = !reentrant && reentrant_failure.code == .Busy
		closed, close_failure := registry_close(ctx.registry)
		state.teardown_reentrant_busy = !closed && close_failure.code == .Busy &&
		                                close_failure.operation == .Teardown
	} else if state.calls == 2 {
		state.second_generation = snapshot.handle.generation
		state.second_nodes = snapshot.node_count
	}
	if state.enqueue_once && state.calls == 1 {
		_, enqueued, _ := registry_defer_request(
			ctx,
			Deferred_Request {
				operation = .Split_Below,
				expected = snapshot.handle,
				pane = snapshot.active_pane,
			},
		)
		assert(enqueued)
	}
	if state.enqueue_two && state.calls == 1 {
		_, first_ok, _ := registry_defer_request(
			ctx,
			Deferred_Request {
				operation = .Split_Below,
				expected = snapshot.handle,
				pane = snapshot.active_pane,
			},
		)
		assert(first_ok)
		_, _, second_failure := registry_defer_request(
			ctx,
			Deferred_Request {
				operation = .Set_Dedication,
				expected = snapshot.handle,
				pane = snapshot.active_pane,
				dedication = .Hard,
			},
		)
		state.second_enqueue_code = second_failure.code
	}
	return state.callback_succeeds
}
