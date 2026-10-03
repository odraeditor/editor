// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../editor"
import "../layout"
import "../view"
import "core:testing"
import "core:thread"

@(private)
Display_Policy_Thread_Result :: struct {
	registry:   ^Display_Policy_Capability_Registry,
	capability: Display_Policy_Capability,
	ok:         bool,
	failure:    Failure_Context,
}

@(private)
display_policy_cross_thread_inspect :: proc(observed: ^Display_Policy_Thread_Result) {
	_, observed.ok, observed.failure = display_policy_capability_inspect(
		observed.registry,
		observed.capability,
	)
}

/* Verifies display-policy capabilities contain stale, thread, and policy failures. */
@(test)
display_policy_loses_released_authority :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	buffer_ready, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(72),
		"display policy",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	views: view.Registry
	views_ready, _ := view.registry_init(&views, view.Registry_ID(72), context.allocator)
	root_view, root_ready, _ := view.create(&views, &buffer)
	layout_registry: layout.Registry
	layout_ready, _ := layout.registry_init(
		&layout_registry,
		layout.Owner_ID(72),
		layout.Layout_ID(72),
		&views,
		root_view,
		layout.Geometry_Request{rows = 24, columns = 80},
		layout.DEFAULT_POLICY,
		context.allocator,
	)
	testing.expect(t, buffer_ready && views_ready && root_ready && layout_ready)
	if !buffer_ready || !views_ready || !root_ready || !layout_ready {
		return
	}

	registry: Display_Policy_Capability_Registry
	registry_ready, _ := display_policy_capability_registry_init(&registry, Registry_ID(72))
	capability, initial, acquired, acquire_failure := display_policy_capability_acquire(
		&registry,
		&layout_registry,
	)
	testing.expectf(t, registry_ready && acquired, "display policy acquire failed with %v", acquire_failure.code)
	if !registry_ready || !acquired {
		layout.registry_close(&layout_registry)
		view.close(&views, &root_view)
		view.registry_close(&views)
		editor.buffer_close(&buffer)
		return
	}

	configured := initial.policy
	configured.action_count = 2
	configured.actions = {}
	configured.actions[0].kind = .Reuse_Least_Recent
	configured.actions[1].kind = .Split_Right
	configured.split_width_threshold = 60
	replaced, replaced_ok, _ := display_policy_capability_replace(
		&registry,
		capability,
		initial.generation,
		configured,
	)
	testing.expect(t, replaced_ok)
	testing.expect_value(t, replaced.generation, layout.Display_Policy_Generation(2))

	_, stale_ok, stale_failure := display_policy_capability_replace(
		&registry,
		capability,
		initial.generation,
		configured,
	)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Generation)
	testing.expect_value(t, stale_failure.layout_code, layout.Failure_Code.Stale_Display_Policy)
	testing.expect_value(t, stale_failure.layout_failure.code, layout.Failure_Code.Stale_Display_Policy)
	testing.expect_value(t, stale_failure.layout_failure.operation, layout.Operation.Configure_Display_Policy)

	invalid := configured
	invalid.action_count = 0
	_, invalid_ok, invalid_failure := display_policy_capability_replace(
		&registry,
		capability,
		replaced.generation,
		invalid,
	)
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Malformed_Record)
	testing.expect_value(t, invalid_failure.layout_code, layout.Failure_Code.Invalid_Display_Policy)
	testing.expect_value(t, invalid_failure.layout_failure.code, layout.Failure_Code.Invalid_Display_Policy)

	cross_thread := Display_Policy_Thread_Result{registry = &registry, capability = capability}
	worker := thread.create_and_start_with_poly_data(&cross_thread, display_policy_cross_thread_inspect)
	testing.expect(t, worker != nil)
	if worker != nil {
		thread.join(worker)
		thread.destroy(worker)
		testing.expect(t, !cross_thread.ok)
		testing.expect_value(t, cross_thread.failure.code, Failure_Code.Wrong_Thread)
	}

	retained_close, retained_failure := display_policy_capability_registry_close(&registry)
	testing.expect(t, !retained_close)
	testing.expect_value(t, retained_failure.code, Failure_Code.Retained_Capabilities)
	old_capability := capability
	released, _ := display_policy_capability_release(&registry, &capability)
	testing.expect(t, released)
	_, stale_capability_ok, stale_capability_failure := display_policy_capability_inspect(
		&registry,
		old_capability,
	)
	testing.expect(t, !stale_capability_ok)
	testing.expect_value(t, stale_capability_failure.code, Failure_Code.Stale_Capability)
	closed, _ := display_policy_capability_registry_close(&registry)
	testing.expect(t, closed)
	layout_closed, _ := layout.registry_close(&layout_registry)
	root_closed, _ := view.close(&views, &root_view)
	views_closed, _ := view.registry_close(&views)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, layout_closed && root_closed && views_closed && buffer_closed)
}
