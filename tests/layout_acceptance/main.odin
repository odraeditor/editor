// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/command"
import "../../src/editor"
import "../../src/hosting"
import "../../src/layout"
import editor_view "../../src/view"
import "core:fmt"
import "core:mem"
import "core:os"

Acceptance_Result :: struct {
	composed:             bool,
	deferred_round:       bool,
	exception_contained:  bool,
	hooks_released:       bool,
	runtime_stopped:      bool,
	layout_closed:        bool,
	root_closed:          bool,
	views_closed:         bool,
	buffer_closed:        bool,
	final_generation:     layout.Layout_Generation,
	final_panes:          u16,
	notification_rounds:  u64,
	callback_failures:    u64,
	deferred_processed:   u64,
	deferred_failures:    u64,
	failure:              command.Failure_Context,
}

main :: proc() {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	result: Acceptance_Result
	layout_acceptance_run(allocator, &result)
	retained_native_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	passed := result.composed && result.deferred_round && result.exception_contained &&
	          result.hooks_released && result.runtime_stopped && result.layout_closed &&
	          result.root_closed && result.views_closed && result.buffer_closed &&
	          retained_native_bytes == 0
	fmt.printf(
		"acceptance=layout passed=%t composed=%t deferred_round=%t exception_contained=%t hooks_released=%t runtime_stopped=%t cleanup_complete=%t generation=%d panes=%d notification_rounds=%d callback_failures=%d deferred_processed=%d deferred_failures=%d retained_native_bytes=%d\n",
		passed,
		result.composed,
		result.deferred_round,
		result.exception_contained,
		result.hooks_released,
		result.runtime_stopped,
		result.layout_closed && result.root_closed && result.views_closed && result.buffer_closed,
		u64(result.final_generation),
		result.final_panes,
		result.notification_rounds,
		result.callback_failures,
		result.deferred_processed,
		result.deferred_failures,
		retained_native_bytes,
	)
	if !passed {
		fmt.eprintf(
			"acceptance=layout failure=%v layout=%v hosting=%v diagnostic=%q\n",
			result.failure.code,
			result.failure.layout_code,
			result.failure.hosting_code,
			result.failure.diagnostic,
		)
		os.exit(1)
	}
}

layout_acceptance_run :: proc(allocator: mem.Allocator, result: ^Acceptance_Result) {
	if result == nil {
		return
	}
	result^ = {}
	buffer: editor.Buffer
	buffer_ready, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(28_001),
		"layout acceptance",
		editor.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	if !buffer_ready {
		return
	}
	defer {
		result.buffer_closed, _ = editor.buffer_close(&buffer)
	}

	views: editor_view.Registry
	views_ready, _ := editor_view.registry_init(&views, editor_view.Registry_ID(28_001), allocator)
	if !views_ready {
		return
	}
	defer {
		result.views_closed, _ = editor_view.registry_close(&views)
	}
	root, root_ready, _ := editor_view.create(&views, &buffer)
	if !root_ready {
		return
	}
	defer {
		result.root_closed, _ = editor_view.close(&views, &root)
	}

	registry: layout.Registry
	layout_ready, layout_failure := layout.registry_init(
		&registry,
		layout.Owner_ID(28_001),
		layout.Layout_ID(28_001),
		&views,
		root,
		layout.Geometry_Request{rows = 80, columns = 160},
		layout.DEFAULT_POLICY,
		allocator,
	)
	if !layout_ready {
		result.failure = command.Failure_Context {
			code = .Layout_Failure,
			layout_code = layout_failure.code,
			layout_failure = layout_failure,
		}
		return
	}
	defer {
		result.layout_closed, _ = layout.registry_close(&registry)
	}

	runtime: hosting.Runtime
	runtime_ready, runtime_failure := hosting.runtime_start(&runtime)
	if !runtime_ready {
		result.failure = command.Failure_Context {
			code = .Runtime_Failure,
			hosting_code = runtime_failure.code,
			diagnostic = runtime_failure.diagnostic,
		}
		return
	}
	defer {
		result.runtime_stopped, _ = hosting.runtime_shutdown(&runtime)
	}

	capability, capability_ok := layout_acceptance_capability(&registry)
	if !capability_ok {
		return
	}
	_, result.composed, result.failure = command.racket_layout_turn(&runtime, capability, 7)
	if !result.composed {
		return
	}

	deferred_hook: command.Racket_Layout_Hook
	_, hook_ready, hook_failure := command.racket_layout_hook_register(
		&runtime,
		&registry,
		8,
		&deferred_hook,
	)
	if !hook_ready {
		result.failure = hook_failure
		return
	}
	handle, _, _ := layout.registry_handle(&registry)
	snapshot, _, _ := layout.registry_snapshot(&registry, handle)
	_, triggered, trigger_failure := layout.registry_pane_dedication_set(
		&registry,
		snapshot.active_pane,
		.Hard,
	)
	if !triggered {
		result.failure = command.Failure_Context {
			code = .Layout_Failure,
			layout_code = trigger_failure.code,
			layout_failure = trigger_failure,
		}
		command.racket_layout_hook_release(&deferred_hook)
		return
	}
	stats, stats_ok, _ := layout.registry_hook_stats(&registry)
	_, deferred_failure, failures_ok := layout.registry_hook_failures(&registry)
	result.deferred_round = stats_ok && failures_ok && deferred_hook.calls == 2 &&
	                        deferred_hook.failures == 0 && stats.deferred_processed == 2 &&
	                        stats.deferred_failures == 1 &&
	                        deferred_failure.code == .Stale_Layout
	deferred_released, deferred_release_failure :=
		command.racket_layout_hook_release(&deferred_hook)
	if !deferred_released {
		result.failure = deferred_release_failure
		return
	}

	exception_hook: command.Racket_Layout_Hook
	_, exception_ready, exception_failure := command.racket_layout_hook_register(
		&runtime,
		&registry,
		4,
		&exception_hook,
	)
	if !exception_ready {
		result.failure = exception_failure
		return
	}
	handle, _, _ = layout.registry_handle(&registry)
	snapshot, _, _ = layout.registry_snapshot(&registry, handle)
	_, exception_triggered, exception_trigger_failure := layout.registry_pane_dedication_set(
		&registry,
		snapshot.active_pane,
		.None,
	)
	callback_failure, _, callback_failure_ok := layout.registry_hook_failures(&registry)
	result.exception_contained = exception_triggered && callback_failure_ok &&
	                             exception_hook.calls == 1 && exception_hook.failures == 1 &&
	                             exception_hook.last_failure.code == .Racket_Exception &&
	                             callback_failure.code == .Callback_Failure
	if !exception_triggered {
		result.failure = command.Failure_Context {
			code = .Layout_Failure,
			layout_code = exception_trigger_failure.code,
			layout_failure = exception_trigger_failure,
		}
	}
	exception_released, exception_release_failure :=
		command.racket_layout_hook_release(&exception_hook)
	result.hooks_released = deferred_released && exception_released
	if !exception_released {
		result.failure = exception_release_failure
		return
	}

	handle, _, _ = layout.registry_handle(&registry)
	snapshot, _, _ = layout.registry_snapshot(&registry, handle)
	stats, _, _ = layout.registry_hook_stats(&registry)
	result.final_generation = snapshot.handle.generation
	result.final_panes = snapshot.pane_count
	result.notification_rounds = stats.notification_rounds
	result.callback_failures = stats.callback_failures
	result.deferred_processed = stats.deferred_processed
	result.deferred_failures = stats.deferred_failures
	return
}

layout_acceptance_capability :: proc(
	registry: ^layout.Registry,
) -> (capability: command.Layout_Capability_Context, ok: bool) {
	handle, handle_ok, _ := layout.registry_handle(registry)
	if !handle_ok {
		return {}, false
	}
	snapshot, snapshot_ok, _ := layout.registry_snapshot(registry, handle)
	if !snapshot_ok {
		return {}, false
	}
	return command.Layout_Capability_Context {
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
