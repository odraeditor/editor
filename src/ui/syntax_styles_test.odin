// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:testing"

/* Verifies every renderer color profile is admitted and out-of-range values reject. */
@(test)
renderer_color_capability_is_explicit :: proc(t: ^testing.T) {
	profile := Renderer_Profile {
		id = 1,
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
	for capability_value in int(Renderer_Color_Capability.Monochrome) ..=
	                         int(Renderer_Color_Capability.True_Color) {
		profile.color = Renderer_Color_Capability(capability_value)
		testing.expect(t, renderer_profile_is_valid(profile))
	}
	profile.color = Renderer_Color_Capability(255)
	testing.expect(t, !renderer_profile_is_valid(profile))
}

/* Verifies the factory mapping covers every stable syntax role canonically. */
@(test)
factory_syntax_mapping_is_complete_and_readable :: proc(t: ^testing.T) {
	count := 0
	for role_value in int(Style_Role.Syntax_Attribute) ..= int(Style_Role.Syntax_Variable_Parameter) {
		definition, found := factory_style_definition(Style_Role(role_value))
		testing.expect(t, found)
		testing.expect(t, style_definition_is_valid(definition))
		testing.expect(t, definition.foreground.present)
		testing.expect(t, !definition.background.present)
		count += 1
	}
	testing.expect_value(t, count, FACTORY_SYNTAX_STYLE_COUNT)
	comment, _ := factory_style_definition(.Syntax_Comment)
	keyword, _ := factory_style_definition(.Syntax_Keyword)
	string_style, _ := factory_style_definition(.Syntax_String)
	testing.expect(t, comment.foreground != keyword.foreground)
	testing.expect(t, keyword.foreground != string_style.foreground)
}

/* Verifies inherited colors have one canonical zero representation. */
@(test)
srgb_color_rejects_invalid_inheritance :: proc(t: ^testing.T) {
	testing.expect(t, optional_srgb_color_is_valid({}))
	testing.expect(t, optional_srgb_color_is_valid({present = true, color = {red = 1}}))
	testing.expect(t, !optional_srgb_color_is_valid({color = {red = 1}}))
}
