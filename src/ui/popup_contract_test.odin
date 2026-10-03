// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:testing"

@(test)
/* Verifies complete information policy fits the reusable popup record. */
admits_complete_information_policy :: proc(t: ^testing.T) {
	descriptor := popup_contract_test_descriptor()

	testing.expect(t, popup_descriptor_shape_is_valid(descriptor))
	testing.expect_value(t, descriptor.placement_count, u8(2))
	testing.expect_value(t, descriptor.behavior, Popup_Behavior.Informational)
	testing.expect_value(t, descriptor.input_policy, Popup_Input_Policy.Preserve_Source_Focus)
}

@(test)
/* Ensures focus, bounds, and ordering remain coherent across popup policy. */
rejects_incoherent_focus_bounds_and_order :: proc(t: ^testing.T) {
	interactive_focus := popup_contract_test_descriptor()
	interactive_focus.input_policy = .Transfer_Focus

	invalid_bounds := popup_contract_test_descriptor()
	invalid_bounds.bounds.maximum_columns = invalid_bounds.bounds.minimum_columns - 1

	duplicate_placement := popup_contract_test_descriptor()
	duplicate_placement.placements[1] = duplicate_placement.placements[0]

	testing.expect(t, !popup_descriptor_shape_is_valid(interactive_focus))
	testing.expect(t, !popup_descriptor_shape_is_valid(invalid_bounds))
	testing.expect(t, !popup_descriptor_shape_is_valid(duplicate_placement))
}

@(test)
/* Ensures zero or unselected capacities violate bounded popup policy. */
popup_limits_reject_zero_or_unselected_capacity :: proc(t: ^testing.T) {
	testing.expect(t, resource_limits_are_valid(DEFAULT_RESOURCE_LIMITS))

	without_popups := DEFAULT_RESOURCE_LIMITS
	without_popups.live_popups = 0
	testing.expect(t, !resource_limits_are_valid(without_popups))

	over_content := DEFAULT_RESOURCE_LIMITS
	over_content.popup_content_bytes = MAX_POPUP_CONTENT_BYTES + 1
	testing.expect(t, !resource_limits_are_valid(over_content))
}

@(private)
popup_contract_test_descriptor :: proc() -> Popup_Descriptor {
	source := popup_contract_test_handle(1, 0)
	content := popup_contract_test_handle(2, 1)
	descriptor := Popup_Descriptor {
		id = 7,
		generation = 3,
		owner_id = 11,
		owner_generation = 5,
		anchor = {
			kind = .Gutter_Marker,
			source_surface = source,
			owner_id = 13,
			source_id = 17,
			source_generation = 19,
			start = 21,
			end = 21,
			presentation_generation = 19,
			viewport_row = 3,
			viewport_column = 4,
			height_rows = 1,
			width_columns = 8,
		},
		content_surface = content,
		content_generation = 23,
		placements = {.Above, .Below, .Invalid, .Invalid},
		placement_count = 2,
		bounds = {
			minimum_rows = 1,
			minimum_columns = 8,
			preferred_rows = 4,
			preferred_columns = 48,
			maximum_rows = 12,
			maximum_columns = 96,
		},
		padding_rows = 1,
		padding_columns = 1,
		border = true,
		clipping = .Wrap,
		behavior = .Informational,
		input_policy = .Preserve_Source_Focus,
		dismissal = {.Explicit_Cancel, .Anchor_Invalidation, .Generation_Replacement},
		fallback = .Compact_Feedback,
		required_profile = 1,
		content_bytes = 1_024,
		action_count = 2,
	}
	popup_test_attach_presentation_profile(&descriptor)
	return descriptor
}

/* popup_test_attach_presentation_profile supplies one complete factory-equivalent test profile. */
popup_test_attach_presentation_profile :: proc(descriptor: ^Popup_Descriptor) {
	assert(descriptor != nil)
	name, _ := presentation_profile_text("popup-test")
	source, _ := presentation_profile_text("ui-tests")
	descriptor.presentation_profile = {
		handle = {
			registry_id = 9_001,
			role = .Contextual_Information,
			profile_id = Presentation_Profile_ID(descriptor.id),
			profile_generation = Presentation_Profile_Generation(descriptor.generation),
		},
		definition = {
			name = name,
			source = source,
			kind = .Factory,
			role = .Contextual_Information,
			mappings = {
				0 = {slot = .Background, style_role = .Popup_Background},
				1 = {slot = .Border, style_role = .Popup_Border},
				2 = {slot = .Title, style_role = .Popup_Border},
				3 = {slot = .Content, style_role = .Popup_Content},
				4 = {slot = .Selection, style_role = .List_Emphasis},
				5 = {slot = .Annotation, style_role = .Popup_Diagnostic},
				6 = {slot = .Separator, style_role = .Popup_Border},
				7 = {slot = .Action, style_role = .List_Emphasis},
				8 = {slot = .Unavailable, style_role = .Popup_Unavailable},
				9 = {slot = .Attention, style_role = .Popup_Diagnostic},
			},
			mapping_count = 10,
			margin_rows = descriptor.margin_rows,
			margin_columns = descriptor.margin_columns,
			padding_rows = descriptor.padding_rows,
			padding_columns = descriptor.padding_columns,
			border = .Single if descriptor.border else .None,
			bounds = descriptor.bounds,
			clipping = descriptor.clipping,
			popup_fallback = descriptor.fallback,
			degradation = .Portable_Border,
			required_capabilities = {.Cell_Geometry, .Clipping},
			configurable = true,
		},
	}
}

@(private)
popup_contract_test_handle :: proc(id: u64, slot: u32) -> Object_Handle {
	return Object_Handle {
		registry_id = 1,
		object_id = Object_ID(id),
		root_generation = 1,
		slot = slot,
		slot_generation = 1,
	}
}
