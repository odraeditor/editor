// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_frontend

import "../theme"
import "../ui"
import "core:testing"

/* Verifies every factory role lowers deterministically across all color profiles. */
@(test)
theme_styles_lower_across_profiles :: proc(t: ^testing.T) {
	definitions := theme.factory_style_matrix()
	for styles in definitions {
		for style in styles {
			for capability_value in int(ui.Renderer_Color_Capability.Monochrome) ..=
			                             int(ui.Renderer_Color_Capability.True_Color) {
				capability := ui.Renderer_Color_Capability(capability_value)
				lowered := terminal_style_lower(style, capability)
				testing.expect_value(t, lowered.attributes, style.attributes)
				switch capability {
				case .Monochrome:
					testing.expect_value(t, lowered.foreground.kind, Terminal_Color_Kind.Default)
					testing.expect_value(t, lowered.background.kind, Terminal_Color_Kind.Default)
				case .Basic_16:
					expected := Terminal_Color_Kind.Basic
					if !style.foreground.present do expected = .Default
					testing.expect_value(t, lowered.foreground.kind, expected)
					expected = .Basic
					if !style.background.present do expected = .Default
					testing.expect_value(t, lowered.background.kind, expected)
				case .Indexed_256:
					expected := Terminal_Color_Kind.Indexed
					if !style.foreground.present do expected = .Default
					testing.expect_value(t, lowered.foreground.kind, expected)
					expected = .Indexed
					if !style.background.present do expected = .Default
					testing.expect_value(t, lowered.background.kind, expected)
				case .True_Color:
					expected := Terminal_Color_Kind.RGB
					if !style.foreground.present do expected = .Default
					testing.expect_value(t, lowered.foreground.kind, expected)
					expected = .RGB
					if !style.background.present do expected = .Default
					testing.expect_value(t, lowered.background.kind, expected)
				}
			}
		}
	}
}
