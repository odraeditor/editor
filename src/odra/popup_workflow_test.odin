// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../display"
import "../interaction"
import "../ui"
import "core:testing"

/* Verifies informational popup replacement and dismissal preserve exact source-focus evidence. */
@(test)
preserves_focus_replaces_and_dismisses_once :: proc(t: ^testing.T) {
	state: Popup_Workflow_State
	first_root := popup_workflow_test_root(1)
	first_source := popup_workflow_test_handle(1, 1, 0)
	first := popup_workflow_test_descriptor(first_root, first_source, 7, 1)
	activated := popup_workflow_activate(
		&state,
		first_root,
		first,
		ui.Focus_Descriptor{target = first_source},
	)
	stale_replacement := popup_workflow_test_descriptor(first_root, first_source, 7, 1)
	stale_rejected := !popup_workflow_activate(
		&state,
		first_root,
		stale_replacement,
		ui.Focus_Descriptor{target = first_source},
	)
	second_root := popup_workflow_test_root(2)
	second_source := popup_workflow_test_handle(2, 1, 0)
	second := popup_workflow_test_descriptor(second_root, second_source, 7, 2)
	replaced := popup_workflow_activate(
		&state,
		second_root,
		second,
		ui.Focus_Descriptor{target = second_source},
	)
	event, dismissed := popup_workflow_dismiss(&state, .Explicit_Cancel, second_root)
	_, repeated := popup_workflow_dismiss(&state, .Explicit_Cancel, second_root)

	testing.expect(t, activated && stale_rejected && replaced && dismissed && !repeated)
	testing.expect(t, event.dismissed)
	testing.expect_value(t, event.cause, ui.Popup_Dismissal_Cause.Explicit_Cancel)
	testing.expect_value(t, event.root, second_root)
	testing.expect_value(t, event.popup, second.handle)
	testing.expect_value(t, event.source_focus, second_source)
	testing.expect(t, !state.active)
}

/* Verifies declared movement and stale-root policies dismiss without guessing focus. */
@(test)
popup_applies_invalidation_policy :: proc(t: ^testing.T) {
	state: Popup_Workflow_State
	root := popup_workflow_test_root(3)
	source := popup_workflow_test_handle(3, 1, 0)
	popup := popup_workflow_test_descriptor(root, source, 11, 1)
	popup.dismissal -= {.Cursor_Movement}
	activated := popup_workflow_activate(
		&state,
		root,
		popup,
		ui.Focus_Descriptor{target = source},
	)
	_, movement_dismissed := popup_workflow_dismiss(&state, .Cursor_Movement, root)
	stale_event, stale_dismissed := popup_workflow_reconcile_root(
		&state,
		popup_workflow_test_root(4),
	)
	closed_root := popup_workflow_test_root(5)
	closed_source := popup_workflow_test_handle(5, 1, 0)
	closed_popup := popup_workflow_test_descriptor(closed_root, closed_source, 12, 1)
	closure_activated := popup_workflow_activate(
		&state,
		closed_root,
		closed_popup,
		ui.Focus_Descriptor{target = closed_source},
	)
	closure_event, source_closed := popup_workflow_dismiss(
		&state,
		.Source_Closure,
		closed_root,
	)

	testing.expect(
		t,
		activated && !movement_dismissed && stale_dismissed && closure_activated && source_closed,
	)
	testing.expect_value(t, stale_event.cause, ui.Popup_Dismissal_Cause.Generation_Replacement)
	testing.expect_value(t, stale_event.source_focus, source)
	testing.expect_value(t, closure_event.cause, ui.Popup_Dismissal_Cause.Source_Closure)
	testing.expect_value(t, closure_event.source_focus, closed_source)
	testing.expect(t, !state.active)
}

/* Verifies protected keyboard cancellation dismisses a popup before ordinary quit handling. */
@(test)
protected_cancel_precedes_ordinary_keyboard_quit :: proc(t: ^testing.T) {
	fixture: Interaction_Fixture
	ready := interaction_fixture_init(t, &fixture, "stable")
	testing.expect(t, ready)
	if !ready do return
	defer interaction_fixture_close(&fixture)
	root := popup_workflow_test_root(9)
	source := popup_workflow_test_handle(9, 1, 0)
	popup := popup_workflow_test_descriptor(root, source, 17, 1)
	activated := popup_workflow_activate(
		&fixture.commands.popup_workflow,
		root,
		popup,
		ui.Focus_Descriptor{target = source},
	)
	fixture.commands.ui_root = root
	cancel := interaction.Input {
		kind = .Key,
		stroke = {
			kind = .Unicode_Scalar,
			scalar = 'g',
			modifiers = {.Control},
		},
	}
	first, first_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		cancel,
		display.Viewport_Constraints{width_cells = 20, height_rows = 4},
	)
	second, second_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		cancel,
		display.Viewport_Constraints{width_cells = 20, height_rows = 4},
	)

	testing.expect(t, activated)
	testing.expect(t, first.changed && !first.exit && first_failure.stage == .None)
	testing.expect(t, !second.changed && !second.exit && second_failure.stage == .None)
	testing.expect(t, !fixture.commands.popup_workflow.active)
}

@(private)
popup_workflow_test_root :: proc(generation: u64) -> ui.Root_Handle {
	return ui.Root_Handle{registry_id = 41, generation = ui.Root_Generation(generation)}
}

@(private)
popup_workflow_test_handle :: proc(
	generation, object_id: u64,
	slot: u32,
) -> ui.Object_Handle {
	return ui.Object_Handle {
		registry_id = 41,
		object_id = ui.Object_ID(object_id),
		root_generation = ui.Root_Generation(generation),
		slot = slot,
		slot_generation = 1,
	}
}

@(private)
popup_workflow_test_descriptor :: proc(
	root: ui.Root_Handle,
	source: ui.Object_Handle,
	id, generation: u64,
) -> ui.Popup_Descriptor {
	return ui.Popup_Descriptor {
		handle = popup_workflow_test_handle(u64(root.generation), 2, 0),
		id = ui.Popup_ID(id),
		generation = ui.Popup_Generation(generation),
		owner_id = 51,
		owner_generation = generation,
		anchor = {
			kind = .Surface,
			source_surface = source,
			owner_id = 51,
			source_id = u64(source.object_id),
			source_generation = u64(source.root_generation),
			presentation_generation = u64(source.root_generation),
			height_rows = 1,
			width_columns = 1,
		},
		content_surface = popup_workflow_test_handle(u64(root.generation), 3, 1),
		content_generation = generation,
		behavior = .Informational,
		input_policy = .Preserve_Source_Focus,
		dismissal = {
			.Explicit_Cancel,
			.Anchor_Invalidation,
			.Owner_Teardown,
			.Source_Closure,
			.Generation_Replacement,
			.Cursor_Movement,
			.Viewport_Movement,
		},
	}
}
