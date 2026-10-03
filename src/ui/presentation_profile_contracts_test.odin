// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:testing"

@(private="file")
contextual_profile_definition :: proc(
	kind := Presentation_Profile_Kind.Factory,
	fallback: Presentation_Profile_Handle = {},
) -> Presentation_Profile_Definition {
	name, _ := presentation_profile_text("contextual")
	source, _ := presentation_profile_text("odra")
	return {
		name = name,
		source = source,
		kind = kind,
		role = .Contextual_Information,
		mappings = {
			0 = {slot = .Background, style_role = .Popup_Background},
			1 = {slot = .Border, style_role = .Popup_Border},
			2 = {slot = .Content, style_role = .Popup_Content},
			3 = {slot = .Unavailable, style_role = .Popup_Unavailable},
			4 = {slot = .Attention, style_role = .Popup_Diagnostic},
		},
		mapping_count = 5,
		margin_columns = 1,
		border = .Single,
		bounds = {
			minimum_rows = 3,
			minimum_columns = 12,
			preferred_rows = 5,
			preferred_columns = 48,
			maximum_rows = 12,
			maximum_columns = 80,
		},
		clipping = .Clip,
		popup_fallback = .Compact_Feedback,
		degradation = .Portable_Border,
		required_capabilities = {.Cell_Geometry, .Clipping},
		fallback = fallback,
		configurable = true,
	}
}

/* Verifies the contextual factory definition is complete and fully copied. */
@(test)
profile_accepts_contextual_factory :: proc(t: ^testing.T) {
	definition := contextual_profile_definition()
	failure := presentation_profile_definition_shape_failure(&definition)
	content, content_ok := presentation_profile_definition_style(&definition, .Content)
	text := presentation_profile_text_view(&definition.name)

	testing.expect_value(t, failure.code, Presentation_Profile_Failure_Code.None)
	testing.expect(t, content_ok)
	testing.expect_value(t, content, Style_Role.Popup_Content)
	testing.expect_value(t, text, "contextual")
	testing.expect_value(
		t,
		presentation_profile_required_slots(.Contextual_Information),
		Presentation_Chrome_Slots{.Background, .Border, .Content, .Unavailable, .Attention},
	)
}

/* Verifies interactive candidates require selection and annotation chrome. */
@(test)
profile_accepts_candidate_factory :: proc(t: ^testing.T) {
	definition := presentation_profile_factory_definition(.Interactive_Candidates)
	failure := presentation_profile_definition_shape_failure(&definition)
	selection, selection_ok := presentation_profile_definition_style(&definition, .Selection)
	annotation, annotation_ok := presentation_profile_definition_style(&definition, .Annotation)

	testing.expect_value(t, failure.code, Presentation_Profile_Failure_Code.None)
	testing.expect(t, selection_ok && annotation_ok)
	testing.expect_value(t, selection, Style_Role.List_Current)
	testing.expect_value(t, annotation, Style_Role.List_Emphasis)
	testing.expect_value(t, definition.margin_columns, u8(0))
	testing.expect_value(
		t,
		presentation_profile_required_slots(.Interactive_Candidates),
		Presentation_Chrome_Slots {
			.Background,
			.Border,
			.Content,
			.Selection,
			.Annotation,
			.Unavailable,
			.Attention,
		},
	)
}

/* Verifies missing and duplicate mappings reject with the exact slot. */
@(test)
profile_rejects_incomplete_slots :: proc(t: ^testing.T) {
	missing := contextual_profile_definition()
	missing.mapping_count = 4
	missing_failure := presentation_profile_definition_shape_failure(&missing)

	duplicate := contextual_profile_definition()
	duplicate.mappings[4] = duplicate.mappings[3]
	duplicate_failure := presentation_profile_definition_shape_failure(&duplicate)

	testing.expect_value(
		t,
		missing_failure.code,
		Presentation_Profile_Failure_Code.Missing_Required_Slot,
	)
	testing.expect_value(t, missing_failure.slot, Presentation_Chrome_Slot.Attention)
	testing.expect_value(
		t,
		duplicate_failure.code,
		Presentation_Profile_Failure_Code.Duplicate_Slot,
	)
	testing.expect_value(t, duplicate_failure.slot, Presentation_Chrome_Slot.Unavailable)
}

/* Verifies dimensions, spacing, and fallback shape reject independently. */
@(test)
profile_rejects_bad_geometry :: proc(t: ^testing.T) {
	inset := contextual_profile_definition()
	inset.margin_columns = MAX_PRESENTATION_PROFILE_INSET_CELLS + 1
	inset_failure := presentation_profile_definition_shape_failure(&inset)

	dimensions := contextual_profile_definition()
	dimensions.bounds.maximum_columns = dimensions.bounds.minimum_columns - 1
	dimension_failure := presentation_profile_definition_shape_failure(&dimensions)

	fallback := contextual_profile_definition()
	fallback.fallback = {
		registry_id = 1,
		role = .Contextual_Information,
		profile_id = 1,
		profile_generation = 1,
	}
	fallback_failure := presentation_profile_definition_shape_failure(&fallback)

	testing.expect_value(t, inset_failure.code, Presentation_Profile_Failure_Code.Inset_Limit)
	testing.expect_value(
		t,
		dimension_failure.code,
		Presentation_Profile_Failure_Code.Invalid_Dimensions,
	)
	testing.expect_value(
		t,
		fallback_failure.code,
		Presentation_Profile_Failure_Code.Invalid_Fallback,
	)
}

/* Verifies bounded profile text rejects empty and excessive values. */
@(test)
profile_bounds_identity_text :: proc(t: ^testing.T) {
	_, empty_ok := presentation_profile_text("")
	oversized: [MAX_PRESENTATION_PROFILE_TEXT_BYTES + 1]u8
	_, oversized_ok := presentation_profile_text(string(oversized[:]))
	valid, valid_ok := presentation_profile_text("factory/contextual")

	testing.expect(t, !empty_ok && !oversized_ok && valid_ok)
	testing.expect_value(t, presentation_profile_text_view(&valid), "factory/contextual")
}
