// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:mem"
import "core:testing"

@(test)
/* Verifies transient input projection copies values, choices, and focus. */
input_projection_copies_value_choices_and_focus :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(51), DEFAULT_RESOURCE_LIMITS, allocator)
	testing.expect(t, initialized)
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	proposal, prepared, _ := proposal_begin(&registry)
	_, style_ok, _ := proposal_add_style(&proposal, .Status_Active)
	choices := []Input_Choice_Definition {
		{id = 1, name = "Open", action = input_test_action(1, 7)},
		{id = 2, name = "Cancel", action = input_test_action(2, 7)},
	}
	view_handle, projected, projection_failure := proposal_project_input(
		&proposal,
		Input_Projection_Request {
			model = {owner_id = 9, model_id = 8, generation = 7},
			presentation_generation = 3,
			backing_generation = 7,
			cursor_offset = 5,
			viewport_bytes = 16,
			validation = .Valid,
		},
		"héllo",
		choices,
	)
	testing.expectf(t, projected, "projection failed: %v", projection_failure)
	surface, surface_ok, _ := proposal_add_surface(
		&proposal,
		Surface_Descriptor {
			owner_id = 9,
			view = view_handle,
			focusable = true,
			visible = true,
			required_profile = 1,
		},
	)
	node, node_ok, _ := proposal_add_surface_node(&proposal, surface)
	root_ok, _ := proposal_set_root(&proposal, node, surface)
	root, published, publish_failure := proposal_publish(&registry, &proposal, test_renderer())
	testing.expectf(t, published, "publish failed: %v", publish_failure)
	captured, capture_failure := registry_capture_focus(&registry, surface)
	testing.expectf(t, captured, "capture failed: %v", capture_failure)
	snapshot, copied, snapshot_failure := registry_snapshot(&registry, root, test_renderer(), allocator)
	testing.expectf(t, copied, "snapshot failed: %v", snapshot_failure)
	if copied {
		view, view_ok := snapshot_view(&snapshot)
		input, input_ok := snapshot_input_value(view, view.views[view_handle.slot])
		copied_choices, choices_ok := snapshot_input_choices(view, view.views[view_handle.slot])
		first, first_ok := snapshot_input_choice_name(view, copied_choices[0])
		second, second_ok := snapshot_input_choice_name(view, copied_choices[1])
		testing.expect(t, view_ok && input_ok && choices_ok && first_ok && second_ok)
		testing.expect_value(t, input, "héllo")
		testing.expect_value(t, first, "Open")
		testing.expect_value(t, second, "Cancel")
		testing.expect_value(t, view.accounting.input_bytes, u32(16))
		testing.expect_value(t, view.accounting.fixed_choices, u16(2))
		snapshot_close(&snapshot)
	}
	closed, close_failure := registry_close(&registry)
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	testing.expectf(t, prepared && style_ok && surface_ok && node_ok && root_ok && closed,
		"input root close failed: %v", close_failure)
	testing.expect_value(t, cleanup_bytes, i64(0))
}

@(test)
/* Ensures invalid boundaries and choices cannot partially replace prepared input. */
input_projection_rejects_invalid_boundaries :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(52))
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	proposal, prepared, _ := proposal_begin(&registry)
	testing.expect(t, prepared)
	request := Input_Projection_Request {
		model = {owner_id = 1, model_id = 2, generation = 3},
		presentation_generation = 1,
		backing_generation = 3,
		cursor_offset = 1,
		viewport_bytes = 8,
		validation = .Valid,
	}
	_, boundary_ok, boundary_failure := proposal_project_input(&proposal, request, "é")
	duplicate_choices := []Input_Choice_Definition {
		{id = 1, name = "One", action = input_test_action(1, 3)},
		{id = 1, name = "Two", action = input_test_action(2, 3)},
	}
	request.cursor_offset = 2
	_, duplicate_ok, duplicate_failure := proposal_project_input(
		&proposal,
		request,
		"é",
		duplicate_choices,
	)
	testing.expect(t, !boundary_ok && !duplicate_ok)
	testing.expect_value(t, boundary_failure.code, Failure_Code.Invalid_View)
	testing.expect_value(t, duplicate_failure.code, Failure_Code.Invalid_View)
	_, stats_ok, _ := registry_stats(&registry)
	testing.expect(t, !stats_ok)
	proposal_abort(&proposal)
}

@(private)
input_test_action :: proc(id, generation: u64) -> List_Action_Reference {
	return List_Action_Reference {
		owner_id = 1,
		action_id = List_Action_ID(id),
		generation = generation,
	}
}
