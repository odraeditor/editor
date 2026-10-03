// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui_reference

import "core:testing"

/* Ensures complete roots publish composition and status as one generation. */
@(test)
root_publishes_composition_and_status :: proc(t: ^testing.T) {
	model: Model
	proposal := proposal_init(0)
	text, text_node, text_ok, _ := proposal_add_surface(&proposal, .Text)
	list, list_node, list_ok, _ := proposal_add_surface(&proposal, .List, true, .View)
	input, input_node, input_ok, _ := proposal_add_surface(&proposal, .Input)
	left, left_ok, _ := proposal_add_split(&proposal, text_node, list_node, .Left_Right)
	root, root_ok, _ := proposal_add_split(&proposal, left, input_node, .Above_Below)
	_, attached_ok, _ := proposal_add_status(&proposal, .Attached, text)
	_, edge_ok, _ := proposal_add_status(&proposal, .Root_Edge, 0)
	set_ok, _ := proposal_set_root(&proposal, root, text)
	generation, published, _ := model_publish(&model, &proposal)

	testing.expect(
		t,
		text_ok && list_ok && input_ok && left_ok && root_ok && attached_ok &&
		edge_ok && set_ok && published,
	)
	testing.expect_value(t, generation, u64(1))
	testing.expect_value(t, model.active.surface_count, u16(3))
	testing.expect_value(t, model.active.node_count, u16(5))
	testing.expect_value(t, model.active.status_count, u16(2))
	testing.expect_value(t, model.focus, Handle{id = text, generation = 1})
	testing.expect(t, list != 0 && input != 0 && model_validate(&model))
}

/* Ensures invalid replacement leaves the confirmed UI generation unchanged. */
@(test)
bad_replacement_keeps_generation :: proc(t: ^testing.T) {
	model: Model
	first := proposal_init(0)
	surface, node, _, _ := proposal_add_surface(&first, .Text)
	_, _ = proposal_set_root(&first, node, surface)
	_, published, _ := model_publish(&model, &first)

	invalid := proposal_init(model.generation)
	_, invalid_node, _, _ := proposal_add_surface(&invalid, .Text)
	invalid.root_node = invalid_node
	invalid.focus_surface = 99
	before := model
	_, replaced, failure := model_publish(&model, &invalid)

	testing.expect(t, published && !replaced)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Proposal)
	testing.expect_value(t, model.generation, before.generation)
	testing.expect_value(t, model.focus, before.focus)
	testing.expect_value(t, model.active.surface_count, before.active.surface_count)
	testing.expect(t, model_validate(&model))
}

/* Ensures list selection updates only through its semantic owner. */
@(test)
list_selection_respects_semantic_owner :: proc(t: ^testing.T) {
	model: Model
	proposal := proposal_init(0)
	model_list, model_node, _, _ := proposal_add_surface(&proposal, .List, true, .Model)
	view_list, view_node, _, _ := proposal_add_surface(&proposal, .List, true, .View)
	root, _, _ := proposal_add_split(&proposal, model_node, view_node, .Left_Right)
	_, _ = proposal_set_root(&proposal, root, model_list)
	_, _, _ = model_publish(&model, &proposal)
	model_handle, _ := model_surface_handle(&model, model_list)
	view_handle, _ := model_surface_handle(&model, view_list)
	model_selected, _ := model_select_list_item(&model, model_handle, 7)
	view_selected, _ := model_select_list_item(&model, view_handle, 11)
	model_surface, model_ok := model_inspect_surface(&model, model_handle)
	view_surface, view_ok := model_inspect_surface(&model, view_handle)

	testing.expect(t, model_selected && view_selected && model_ok && view_ok)
	testing.expect_value(t, model_surface.model_current, i32(7))
	testing.expect_value(t, model_surface.view_current, i32(-1))
	testing.expect_value(t, view_surface.model_current, i32(-1))
	testing.expect_value(t, view_surface.view_current, i32(11))
	testing.expect(t, model_validate(&model))
}

/* Ensures captured focus returns to its owner or a checked safe fallback. */
@(test)
focus_capture_restores_return_or_safe_fallback :: proc(t: ^testing.T) {
	model: Model
	proposal := proposal_init(0)
	primary, primary_node, _, _ := proposal_add_surface(&proposal, .Text)
	fallback, fallback_node, _, _ := proposal_add_surface(&proposal, .Text)
	input, input_node, _, _ := proposal_add_surface(&proposal, .Input)
	texts, _, _ := proposal_add_split(&proposal, primary_node, fallback_node, .Left_Right)
	root, _, _ := proposal_add_split(&proposal, texts, input_node, .Above_Below)
	_, _ = proposal_set_root(&proposal, root, primary)
	_, _, _ = model_publish(&model, &proposal)
	primary_handle, _ := model_surface_handle(&model, primary)
	fallback_handle, _ := model_surface_handle(&model, fallback)
	input_handle, _ := model_surface_handle(&model, input)

	captured, _ := model_capture_focus(&model, input_handle)
	return_disabled, _ := model_set_surface_available(&model, primary_handle, false)
	restored, released, _ := model_release_focus(&model)

	testing.expect(t, captured && return_disabled && released)
	testing.expect_value(t, restored, fallback_handle)
	testing.expect_value(t, model.focus, fallback_handle)
	testing.expect(t, !model.capture.active && model_validate(&model))
}

/* Ensures replacement cannot reuse object handles from an earlier generation. */
@(test)
replacement_rejects_prior_handles :: proc(t: ^testing.T) {
	model: Model
	first := proposal_init(0)
	first_surface, first_node, _, _ := proposal_add_surface(&first, .Text)
	_, _ = proposal_set_root(&first, first_node, first_surface)
	_, _, _ = model_publish(&model, &first)
	stale, _ := model_surface_handle(&model, first_surface)

	second := proposal_init(model.generation)
	second_surface, second_node, _, _ := proposal_add_surface(&second, .Text)
	_, _ = proposal_set_root(&second, second_node, second_surface)
	_, replaced, _ := model_publish(&model, &second)
	stale_focused, stale_failure := model_focus_surface(&model, stale)
	current, current_ok := model_surface_handle(&model, second_surface)

	testing.expect(t, replaced && !stale_focused && current_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Invalid_Handle)
	testing.expect_value(t, current.generation, u64(2))
	testing.expect(t, model_validate(&model))
}

/* Ensures teardown invalidates the root, focus, and every derived handle. */
@(test)
teardown_invalidates_root_focus_and_handles :: proc(t: ^testing.T) {
	model: Model
	proposal := proposal_init(0)
	surface, node, _, _ := proposal_add_surface(&proposal, .Text)
	_, _ = proposal_set_root(&proposal, node, surface)
	_, _, _ = model_publish(&model, &proposal)
	handle, _ := model_surface_handle(&model, surface)
	torn_down := model_teardown(&model)
	_, inspected := model_inspect_surface(&model, handle)

	testing.expect(t, torn_down && !inspected)
	testing.expect_value(t, model.generation, u64(2))
	testing.expect(t, !model.root_active)
	testing.expect_value(t, model.focus, Handle{})
	testing.expect_value(t, model.active.surface_count, u16(0))
	testing.expect(t, !model_teardown(&model))
	testing.expect_value(t, model.generation, u64(2))
}

/* Ensures popup replacement and dismissal preserve editor focus. */
@(test)
popup_replaces_without_moving_focus :: proc(t: ^testing.T) {
	model: Model
	first := proposal_init(0)
	source, source_node, _, _ := proposal_add_surface(&first, .Text)
	content, _, _ := proposal_add_popup_surface(&first, .Text)
	popup_id, popup_ok, _ := proposal_add_popup(
		&first,
		Popup {
			generation = 1,
			owner_id = 9,
			owner_generation = 3,
			anchor_kind = .Gutter_Marker,
			anchor_surface_id = source,
			anchor_generation = 12,
			content_surface_id = content,
			content_generation = 4,
			behavior = .Informational,
		},
	)
	_, _ = proposal_set_root(&first, source_node, source)
	_, published, _ := model_publish(&model, &first)
	handle, handle_ok := model_popup_handle(&model, popup_id)
	inspected, inspect_ok := model_inspect_popup(&model, handle)

	second := proposal_init(model.generation)
	second_source, second_node, _, _ := proposal_add_surface(&second, .Text)
	second_content, _, _ := proposal_add_popup_surface(&second, .Text)
	_, replaced_popup, _ := proposal_add_popup(
		&second,
		Popup {
			generation = 2,
			owner_id = 9,
			owner_generation = 4,
			anchor_kind = .Gutter_Marker,
			anchor_surface_id = second_source,
			anchor_generation = 13,
			content_surface_id = second_content,
			content_generation = 5,
			behavior = .Informational,
		},
	)
	_, _ = proposal_set_root(&second, second_node, second_source)
	_, replaced, _ := model_publish(&model, &second)
	_, stale_visible := model_inspect_popup(&model, handle)

	dismissed := proposal_init(model.generation)
	dismissed_source, dismissed_node, _, _ := proposal_add_surface(&dismissed, .Text)
	_, _ = proposal_set_root(&dismissed, dismissed_node, dismissed_source)
	_, dismissed_ok, _ := model_publish(&model, &dismissed)
	_, popup_after_dismiss := model_popup_handle(&model, 1)

	testing.expect(
		t,
		popup_ok && published && handle_ok && inspect_ok && replaced_popup && replaced &&
		!stale_visible && dismissed_ok && !popup_after_dismiss,
	)
	testing.expect_value(t, inspected.generation, u64(1))
	testing.expect_value(t, model.focus.id, dismissed_source)
	testing.expect_value(t, model.active.popup_count, u16(0))
	testing.expect(t, model_validate(&model))
}

/* Ensures popup publication rejects excessive, stale, or incoherent evidence. */
@(test)
popup_rejects_bad_evidence :: proc(t: ^testing.T) {
	model: Model
	proposal := proposal_init(0)
	source, source_node, _, _ := proposal_add_surface(&proposal, .Text)
	content, _, _ := proposal_add_popup_surface(&proposal, .Text)
	valid := Popup {
		generation = 1,
		owner_id = 1,
		owner_generation = 1,
		anchor_kind = .Cursor,
		anchor_surface_id = source,
		anchor_generation = 1,
		content_surface_id = content,
		content_generation = 1,
		behavior = .Informational,
	}
	_, first_ok, _ := proposal_add_popup(&proposal, valid)
	_, second_ok, capacity_failure := proposal_add_popup(&proposal, valid)
	_, _ = proposal_set_root(&proposal, source_node, source)
	_, published, _ := model_publish(&model, &proposal)

	stale := proposal_init(0)
	stale_source, stale_node, _, _ := proposal_add_surface(&stale, .Text)
	_, _ = proposal_set_root(&stale, stale_node, stale_source)
	_, stale_ok, stale_failure := model_publish(&model, &stale)

	invalid := proposal_init(model.generation)
	invalid_source, invalid_node, _, _ := proposal_add_surface(&invalid, .Text)
	invalid_content, _, _ := proposal_add_popup_surface(&invalid, .Text)
	invalid_popup := valid
	invalid_popup.anchor_surface_id = invalid_source
	invalid_popup.content_surface_id = invalid_content
	invalid_popup.owner_generation = 0
	_, invalid_ok, invalid_failure := proposal_add_popup(&invalid, invalid_popup)
	_, _ = proposal_set_root(&invalid, invalid_node, invalid_source)

	testing.expect(t, first_ok && !second_ok && published && !stale_ok && !invalid_ok)
	testing.expect_value(t, capacity_failure.code, Failure_Code.Capacity)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Generation)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Invalid_Proposal)
	testing.expect_value(t, model.generation, u64(1))
	testing.expect(t, model_validate(&model))
}
