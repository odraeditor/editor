// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package theme

import "../ui"
import "core:testing"

/* Verifies every maintained theme resolves the complete contextual profile. */
@(test)
themes_resolve_presentation_profile :: proc(t: ^testing.T) {
	profiles: ui.Presentation_Profile_Registry
	initialized, _ := ui.presentation_profile_registry_init(&profiles, 901)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer ui.presentation_profile_registry_close(&profiles)
	scope, scoped, _ := ui.presentation_profile_registry_scope(
		&profiles,
		.Contextual_Information,
	)
	record, recorded, _ := ui.presentation_profile_registry_record(&profiles, scope.factory)
	testing.expect(t, scoped && recorded)
	if !scoped || !recorded {
		return
	}

	styles := factory_style_matrix()
	proposals := factory_definition_proposals(&styles)
	for proposal in proposals {
		resolved, resolved_ok, failure := definition_resolve_presentation_profile(
			proposal.styles,
			record,
		)
		testing.expectf(
			t,
			resolved_ok,
			"%s failed contextual profile resolution with %v",
			proposal.identity,
			failure.code,
		)
		if !resolved_ok {
			continue
		}
		testing.expect_value(t, resolved.style_count, u8(10))
		background, background_ok := resolved_presentation_profile_style(
			&resolved,
			.Background,
		)
		content, content_ok := resolved_presentation_profile_style(&resolved, .Content)
		border, border_ok := resolved_presentation_profile_style(&resolved, .Border)
		selection, selection_ok := resolved_presentation_profile_style(&resolved, .Selection)
		attention, attention_ok := resolved_presentation_profile_style(&resolved, .Attention)
		unavailable, unavailable_ok := resolved_presentation_profile_style(
			&resolved,
			.Unavailable,
		)
		testing.expect(
			t,
			background_ok && content_ok && border_ok && selection_ok && attention_ok &&
			unavailable_ok,
		)
		testing.expect_value(t, content.background, background.background)
		testing.expect(t, .Bold in border.attributes)
		testing.expect(t, .Underline in attention.attributes)
		testing.expect(t, .Dim in unavailable.attributes)
		if proposal.identity == TERMINAL_DEFAULT_IDENTITY {
			testing.expect(t, .Bold in selection.attributes)
		} else {
			testing.expect(t, selection.foreground.present)
			testing.expect(t, selection.foreground != content.foreground)
		}
	}
}

/* Verifies missing theme roles reject without a partial resolved profile. */
@(test)
presentation_profile_rejects_incomplete_theme :: proc(t: ^testing.T) {
	profiles: ui.Presentation_Profile_Registry
	initialized, _ := ui.presentation_profile_registry_init(&profiles, 902)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer ui.presentation_profile_registry_close(&profiles)
	scope, _, _ := ui.presentation_profile_registry_scope(&profiles, .Contextual_Information)
	record, _, _ := ui.presentation_profile_registry_record(&profiles, scope.factory)
	styles := factory_fallback_styles()
	resolved, resolved_ok, failure := definition_resolve_presentation_profile(
		styles[:CURRENT_STYLE_ROLE_COUNT - 1],
		record,
	)

	testing.expect(t, !resolved_ok)
	testing.expect_value(t, resolved, Resolved_Presentation_Profile{})
	testing.expect_value(t, failure.code, ui.Failure_Code.Invalid_Style)
}
