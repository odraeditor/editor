// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../theme"
import "../ui"
import "core:fmt"
import "core:strings"
import "core:testing"

/* Verifies the copied inspection exposes selection, provider, renderer, policy, and rejection state. */
@(test)
theme_inspection_rows_cover_session_theme_state :: proc(t: ^testing.T) {
	registry: theme.Registry
	initialized, _ := theme.theme_registry_init_factory(&registry, 991)
	testing.expect(t, initialized)
	if !initialized do return
	defer theme.theme_registry_close(&registry)
	inspection, inspected, _ := theme.theme_registry_inspect(&registry)
	active, active_ok, _ := theme.theme_registry_definition(&registry, inspection.selection.active)
	fallback, fallback_ok, _ := theme.theme_registry_definition(&registry, inspection.selection.fallback)
	baseline, baseline_ok, _ := theme.theme_registry_definition(&registry, inspection.selection.baseline)
	provider, provider_ok, _ := theme.theme_registry_provider(&registry, active.descriptor.provider)
	profile_registry: ui.Presentation_Profile_Registry
	profiles_initialized, _ := ui.presentation_profile_registry_init(&profile_registry, 992)
	testing.expect(t, profiles_initialized)
	if !profiles_initialized do return
	defer ui.presentation_profile_registry_close(&profile_registry)
	profile_inspection, profiles_inspected, _ :=
		ui.presentation_profile_registry_inspect(&profile_registry)
	profile_scope := profile_inspection.scopes[0]
	active_profile, profile_found, _ := ui.presentation_profile_registry_record(
		&profile_registry,
		profile_scope.selected,
	)
	private_source, private_source_ok := ui.presentation_profile_text("/private/profile/provider")
	active_profile.definition.source = private_source
	testing.expect(t, inspected && active_ok && fallback_ok && baseline_ok && provider_ok &&
		profiles_inspected && profile_found && private_source_ok)
	if !inspected || !active_ok || !fallback_ok || !baseline_ok || !provider_ok ||
	   !profiles_inspected || !profile_found {
		return
	}
	state := Theme_Inspection_Workflow_State {
		inspection = inspection,
		active = active.descriptor,
		fallback = fallback.descriptor,
		baseline = baseline.descriptor,
		provider = provider,
		style_count = u16(len(active.styles)),
		ready = true,
		model_generation = 1,
	}
	copy(state.styles[:], active.styles)
	items, storage, built := theme_inspection_list_definitions(
		&state,
		profile_inspection,
		active_profile,
		session_theme_test_renderer(),
		context.temp_allocator,
	)
	testing.expect(t, built)
	if !built do return
	defer delete(items, context.temp_allocator)
	defer delete(storage, context.temp_allocator)
	testing.expect_value(t, len(items), THEME_INSPECTION_ROW_COUNT)
	testing.expect(t, strings.contains(items[0].text, "Selection: state=Factory"))
	testing.expect(t, strings.contains(items[1].text, "Wrocław Night [wroclaw-night]"))
	testing.expect(t, strings.contains(items[3].text, "terminal-default"))
	testing.expect(t, strings.contains(items[5].text, "kind=Factory state=Confirmed"))
	role_count_storage: [64]u8
	role_count := fmt.bprintf(role_count_storage[:], "current=%d", theme.CURRENT_STYLE_ROLE_COUNT)
	testing.expect(t, strings.contains(items[6].text, role_count))
	testing.expect(t, strings.contains(items[7].text, "Renderer: id=1"))
	testing.expect(t, strings.contains(items[8].text, "providers=1 definitions=5"))
	testing.expect(t, strings.contains(items[10].text, "operations-per-turn=64"))
	testing.expect(t, strings.contains(items[12].text, "code=None"))
	testing.expect(t, strings.contains(items[14].text, "role=Contextual_Information"))
	testing.expect(t, strings.contains(items[15].text, "contextual-information kind=Factory"))
	testing.expect(t, strings.contains(items[19].text, "degradation=Portable_Border"))
	testing.expect(t, strings.contains(items[20].text, "supported=true"))
	testing.expect(t, strings.contains(items[23].text, "code=None"))
	testing.expect(t, strings.contains(items[25].text, "Presentation slot Background:"))
	testing.expect(t, strings.contains(items[33].text, "Presentation slot Progress:"))
	testing.expect(t, strings.contains(items[33].text, "required=false available=false"))
	testing.expect(t, strings.contains(items[34].text, "Presentation slot Unavailable:"))
	testing.expect(t, !strings.contains(string(storage), "/private/profile/provider"))
	testing.expect(t, strings.contains(items[THEME_INSPECTION_STYLE_ROW_START].text, "Role Text_Normal:"))
	testing.expect(t, strings.contains(items[THEME_INSPECTION_STYLE_ROW_START].text, "foreground=#D6D6B3 -> default"))
	testing.expect(t, strings.contains(items[THEME_INSPECTION_STYLE_ROW_START + 26].text, "Role Syntax_Variable_Parameter:"))
}
