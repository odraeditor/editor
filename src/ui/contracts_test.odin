// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:testing"

@(test)
/* Ensures default resource ceilings match the selected evidence. */
default_resource_policy_matches_evidence :: proc(t: ^testing.T) {
	testing.expect(t, resource_limits_are_valid(DEFAULT_RESOURCE_LIMITS))
	testing.expect_value(t, DEFAULT_RESOURCE_LIMITS.live_surfaces, u16(128))
	testing.expect_value(t, DEFAULT_RESOURCE_LIMITS.composition_nodes, u16(255))
	testing.expect_value(t, DEFAULT_RESOURCE_LIMITS.live_popups, u16(1))
	testing.expect_value(t, DEFAULT_RESOURCE_LIMITS.popup_content_bytes, u64(64 * KIBIBYTE))
	testing.expect_value(t, DEFAULT_RESOURCE_LIMITS.popup_actions, u16(16))
	testing.expect_value(t, DEFAULT_RESOURCE_LIMITS.projection_bytes, u64(32 * MEBIBYTE))
}

@(test)
/* Ensures renderer profiles require every initial capability. */
profile_requires_initial_capabilities :: proc(t: ^testing.T) {
	profile := Renderer_Profile {
		id = Renderer_Profile_ID(1),
		capabilities = {
			.Cell_Geometry,
			.Clipping,
			.Unicode_Profile,
			.Text_Cursor,
			.Input_Cursor,
			.Semantic_Attributes,
			.Atomic_Generation,
			.Full_Redraw,
		},
		unicode_profile = 17,
		max_rows = 80,
		max_columns = 240,
		max_cells = 19_200,
		attributes = {.Bold, .Dim, .Underline, .Reverse},
	}
	testing.expect(t, renderer_profile_is_valid(profile))
	profile.capabilities -= {.Atomic_Generation}
	testing.expect(t, !renderer_profile_is_valid(profile))
}

@(test)
/* Ensures list selection remains owned by the model rather than the view. */
visual_contract_preserves_list_selection_owner :: proc(t: ^testing.T) {
	model_list := Visual_View_Descriptor {
		kind = .List_View,
		list = {
			present = true,
			item_count = 16,
			position = {
				presentation_generation = 1,
				selection_owner = .Model,
				current_item = 3,
				viewport_items = 16,
			},
		},
	}
	view_list := model_list
	view_list.list.position.selection_owner = .View
	invalid_list := model_list
	invalid_list.list.position.selection_owner = .None

	testing.expect(t, visual_contract_is_valid(model_list))
	testing.expect(t, visual_contract_is_valid(view_list))
	testing.expect(t, !visual_contract_is_valid(invalid_list))
}

@(test)
/* Ensures input and choice growth cannot exceed measured ceilings. */
input_contract_rejects_unmeasured_growth :: proc(t: ^testing.T) {
	input := Visual_View_Descriptor {
		kind = .Input,
		input = {
			present = true,
			presentation_generation = 1,
			backing_generation = 1,
			value_bytes = u32(MAX_INPUT_BYTES),
			cursor_offset = u32(MAX_INPUT_BYTES),
			first_visible_byte = 1,
			viewport_bytes = u32(MAX_INPUT_BYTES),
			validation = .Valid,
			choice_count = MAX_FIXED_CHOICES,
		},
	}
	testing.expect(t, visual_contract_is_valid(input))
	input.input.value_bytes += 1
	testing.expect(t, !visual_contract_is_valid(input))
}
