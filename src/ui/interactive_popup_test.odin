// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:testing"

/* Verifies interactive popup capture preserves source focus through replacement and release. */
@(test)
captures_commands_without_moving_source_focus :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(79))
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)

	first, first_popup, first_source, first_ok, _ := publish_interactive_popup_test_root(
		&registry, {}, 51, 1, 71,
	)
	captured, capture_failure := registry_capture_transient_input(&registry, first_popup)
	testing.expectf(t, captured, "capture failed with %v", capture_failure.code)
	first_focus, first_focus_ok, _ := registry_focus(&registry)
	first_stats, first_stats_ok, _ := registry_stats(&registry)
	repeated, repeated_failure := registry_capture_transient_input(&registry, first_popup)
	focus_changed, focus_failure := registry_focus_surface(&registry, first_source)

	second, second_popup, second_source, second_ok, _ := publish_interactive_popup_test_root(
		&registry, first, 51, 2, 72,
	)
	second_focus, second_focus_ok, _ := registry_focus(&registry)
	_, stale_release, stale_release_failure := registry_release_transient_input(
		&registry, first_popup,
	)
	restored, released, release_failure := registry_release_transient_input(
		&registry, second_popup,
	)
	final_focus, final_focus_ok, _ := registry_focus(&registry)

	testing.expect(
		t,
		first_ok && first_focus_ok && first_stats_ok && !repeated && !focus_changed &&
		second_ok && second_focus_ok && !stale_release && released && final_focus_ok,
	)
	testing.expect(t, !first_focus.captured && first_focus.transient.active)
	testing.expect_value(t, first_focus.target, first_source)
	testing.expect(t, first_stats.focus_captured && first_stats.transient_input_captured)
	testing.expect_value(t, repeated_failure.code, Failure_Code.Transient_Input_Captured)
	testing.expect_value(t, focus_failure.code, Failure_Code.Focus_Captured)
	testing.expect_value(t, second.generation, Root_Generation(2))
	testing.expect(t, second_focus.transient.active)
	testing.expect_value(t, second_focus.transient.popup, second_popup)
	testing.expect_value(t, second_focus.transient.popup_generation, Popup_Generation(2))
	testing.expect_value(t, second_focus.target, second_source)
	testing.expect_value(t, stale_release_failure.code, Failure_Code.Invalid_Transient_Input)
	testing.expectf(t, released, "release failed with %v", release_failure.code)
	testing.expect_value(t, restored, second_source)
	testing.expect(t, !final_focus.captured && !final_focus.transient.active)
}

/* Verifies informational and focus-transfer popups cannot claim transient capture. */
@(test)
rejects_incompatible_input_policy :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(80))
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)

	_, informational, _, published, _ := publish_popup_test_root(&registry, {}, 53, 1, 73)
	captured, capture_failure := registry_capture_transient_input(&registry, informational)
	transfer := popup_contract_test_descriptor()
	transfer.behavior = .Interactive
	transfer.input_policy = .Transfer_Focus
	profile := presentation_profile_factory_definition(.Interactive_Candidates)
	transfer.bounds = profile.bounds
	transfer.margin_rows = profile.margin_rows
	transfer.margin_columns = profile.margin_columns
	transfer.padding_rows = profile.padding_rows
	transfer.padding_columns = profile.padding_columns
	transfer.border = profile.border == .Single
	transfer.clipping = profile.clipping
	transfer.fallback = profile.popup_fallback
	transfer.presentation_profile.handle.role = .Interactive_Candidates
	transfer.presentation_profile.definition = profile

	testing.expect(t, published && !captured)
	testing.expect_value(t, capture_failure.code, Failure_Code.Invalid_Transient_Input)
	testing.expect(t, popup_descriptor_shape_is_valid(transfer))
}

@(private)
publish_interactive_popup_test_root :: proc(
	registry: ^Registry,
	expected: Root_Handle,
	popup_id, popup_generation, content_generation: u64,
) -> (
	root: Root_Handle,
	popup, source: Object_Handle,
	ok: bool,
	failure: Failure,
) {
	proposal, prepared, begin_failure := proposal_begin(registry, expected)
	if !prepared do return {}, {}, {}, false, begin_failure
	defer if proposal.state != nil do proposal_abort(&proposal)
	_, text_style_ok, _ := proposal_add_style(&proposal, .Text_Normal)
	_, list_style_ok, _ := proposal_add_style(&proposal, .List_Normal)
	_, current_style_ok, _ := proposal_add_style(&proposal, .List_Current, {.Reverse})
	source_projection, source_projection_ok, _ := proposal_add_projection(
		&proposal,
		Model_Reference{owner_id = 1, model_id = 1, generation = 1},
		256,
	)
	source_view, source_view_ok, _ := proposal_add_view(
		&proposal,
		Visual_View_Descriptor{kind = .Text_View, projection = source_projection},
	)
	items := []List_Item_Definition {{
		id = 1,
		text = "print",
		action = {owner_id = 3, action_id = 1, generation = content_generation},
	}}
	content_view, content_view_ok, content_failure := proposal_project_list_view(
		&proposal,
		List_Projection_Request {
			model = {owner_id = 3, model_id = 2, generation = Model_Generation(content_generation)},
			position = {
				presentation_generation = content_generation,
				selection_owner = .Model,
				current_item = 0,
				viewport_items = 1,
			},
			read_only = true,
		},
		items,
	)
	if !content_view_ok do return {}, {}, {}, false, content_failure
	source_ok: bool
	source, source_ok, _ = proposal_add_surface(
		&proposal,
		Surface_Descriptor {
			owner_id = 1,
			view = source_view,
			focusable = true,
			visible = true,
			required_profile = 1,
			geometry = {row = 0, column = 0, height = 24, width = 80},
		},
	)
	content, content_ok, _ := proposal_add_surface(
		&proposal,
		Surface_Descriptor {
			owner_id = 3,
			view = content_view,
			focusable = false,
			visible = true,
			required_profile = 1,
		},
	)
	source_node, node_ok, _ := proposal_add_surface_node(&proposal, source)
	profile := presentation_profile_factory_definition(.Interactive_Candidates)
	descriptor := Popup_Descriptor {
		id = Popup_ID(popup_id),
		generation = Popup_Generation(popup_generation),
		owner_id = 3,
		owner_generation = popup_generation,
		anchor = {
			kind = .Surface,
			source_surface = source,
			owner_id = 1,
			source_id = u64(source.object_id),
			source_generation = u64(source.root_generation),
			start = 7,
			end = 7,
			presentation_generation = u64(source.root_generation),
			viewport_row = 7,
			viewport_column = 0,
			height_rows = 1,
			width_columns = 80,
		},
		content_surface = content,
		content_generation = content_generation,
		placements = {.Above, .Below, .Invalid, .Invalid},
		placement_count = 2,
		bounds = profile.bounds,
		margin_rows = profile.margin_rows,
		margin_columns = profile.margin_columns,
		padding_rows = profile.padding_rows,
		padding_columns = profile.padding_columns,
		border = profile.border == .Single,
		clipping = profile.clipping,
		behavior = .Interactive,
		input_policy = .Transient_Capture,
		dismissal = {
			.Explicit_Cancel,
			.Action_Completion,
			.Owner_Cancellation,
			.Owner_Teardown,
			.Anchor_Invalidation,
			.Generation_Replacement,
			.Focus_Loss,
			.Cursor_Movement,
		},
		fallback = profile.popup_fallback,
		required_profile = 1,
		presentation_profile = {
			handle = {
				registry_id = 1,
				role = .Interactive_Candidates,
				profile_id = 2,
				profile_generation = 1,
			},
			definition = profile,
		},
		content_bytes = 1,
		action_count = 1,
	}
	popup_ok: bool
	popup, popup_ok, failure = proposal_add_popup(&proposal, descriptor)
	root_ok, _ := proposal_set_root(&proposal, source_node, source)
	if !popup_ok do return {}, {}, {}, false, failure
	published: bool
	root, published, failure = proposal_publish(registry, &proposal, popup_test_renderer())
	return root, popup, source,
		text_style_ok && list_style_ok && current_style_ok && source_projection_ok &&
		source_view_ok && content_view_ok && source_ok && content_ok && node_ok &&
		root_ok && published,
		failure
}
