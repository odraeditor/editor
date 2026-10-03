// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import ui "../../src/ui"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"

ORDINARY_PROFILES :: 4
DEMANDING_PROFILES :: ui.MAX_PRESENTATION_PROFILES
ORDINARY_REPLACEMENTS :: 64
DEMANDING_REPLACEMENTS :: 1_024
RENDERER_CHANGES :: 128
LATENCY_GATE_NS :: i64(1_000_000_000)
MEMORY_GATE_BYTES :: i64(1 * 1_024 * 1_024)

Profile :: struct {
	name:         string,
	profiles:     int,
	replacements: int,
}

main :: proc() {
	profiles := [?]Profile {
		{name = "ordinary", profiles = ORDINARY_PROFILES, replacements = ORDINARY_REPLACEMENTS},
		{name = "demanding", profiles = DEMANDING_PROFILES, replacements = DEMANDING_REPLACEMENTS},
	}
	passed := print_policy_evidence()
	for profile, index in profiles {
		passed = run_profile(profile, ui.Presentation_Profile_Registry_ID(index + 1)) && passed
	}
	if !passed {
		os.exit(1)
	}
}

print_policy_evidence :: proc() -> bool {
	valid := ui.MAX_PRESENTATION_PROFILES == 16 &&
		ui.MAX_PRESENTATION_PROFILE_MAPPINGS == 16 &&
		ui.MAX_PRESENTATION_PROFILE_TEXT_BYTES == 96 &&
		ui.MAX_PRESENTATION_PROFILE_FALLBACK_DEPTH == 4 &&
		ui.MAX_PRESENTATION_PROFILE_INSET_CELLS == 8 &&
		ui.PRESENTATION_PROFILE_ROLE_COUNT == 2 &&
		ui.PRESENTATION_CHROME_SLOT_COUNT == 11
	fmt.printf(
		"study=presentation-profile profile=policy valid=%v profiles=%d mappings=%d text_bytes=%d fallback_depth=%d inset_cells=%d roles=%d chrome_slots=%d ownership=copied-generational-registry inspection=bounded-value\n",
		valid,
		ui.MAX_PRESENTATION_PROFILES,
		ui.MAX_PRESENTATION_PROFILE_MAPPINGS,
		ui.MAX_PRESENTATION_PROFILE_TEXT_BYTES,
		ui.MAX_PRESENTATION_PROFILE_FALLBACK_DEPTH,
		ui.MAX_PRESENTATION_PROFILE_INSET_CELLS,
		ui.PRESENTATION_PROFILE_ROLE_COUNT,
		ui.PRESENTATION_CHROME_SLOT_COUNT,
	)
	return valid
}

run_profile :: proc(profile: Profile, identity: ui.Presentation_Profile_Registry_ID) -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	started := time.tick_now()

	registry: ui.Presentation_Profile_Registry
	initialized, _ := ui.presentation_profile_registry_init(
		&registry,
		identity,
		ui.DEFAULT_PRESENTATION_PROFILE_LIMITS,
		allocator,
	)
	valid := initialized
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	scope, scoped, _ := ui.presentation_profile_registry_scope(
		&registry,
		.Contextual_Information,
	)
	valid = scoped && valid
	factory := scope.factory
	registered: [ui.MAX_PRESENTATION_PROFILES - ui.PRESENTATION_PROFILE_ROLE_COUNT]ui.Presentation_Profile_Record
	registered_count: int
	for index in 0 ..< profile.profiles - ui.PRESENTATION_PROFILE_ROLE_COUNT {
		fallback := factory
		if index > 0 && index < ui.MAX_PRESENTATION_PROFILE_FALLBACK_DEPTH {
			fallback = registered[index - 1].handle
		}
		definition := resource_definition(index, fallback)
		record, added, _ := ui.presentation_profile_registry_register(&registry, definition)
		valid = added && valid
		if !added {
			break
		}
		registered[index] = record
		registered_count += 1
	}

	if registered_count > 0 {
		target := registered[0]
		for replacement_index in 0 ..< profile.replacements {
			current, current_ok, _ := ui.presentation_profile_registry_scope(
				&registry,
				.Contextual_Information,
			)
			definition := target.definition
			definition.padding_columns = u8(replacement_index % 2)
			replacement, _, replaced, _ := ui.presentation_profile_registry_replace(
				&registry,
				current,
				target.handle,
				definition,
			)
			valid = current_ok && replaced && valid
			if !replaced {
				break
			}
			target = replacement
		}
		registered[0] = target
	}

	for index in 0 ..< RENDERER_CHANGES {
		current, current_ok, _ := ui.presentation_profile_registry_scope(
			&registry,
			.Contextual_Information,
		)
		requested := factory
		if registered_count > 0 && index % 2 == 0 {
			requested = registered[0].handle
		}
		selection, selected, _ := ui.presentation_profile_registry_select(
			&registry,
			current,
			requested,
			resource_renderer(index % 2 == 0),
		)
		valid = current_ok && selected &&
			selection.scope.registry_generation != 0 && valid
	}

	overflow_code := ui.Presentation_Profile_Failure_Code.None
	if profile.profiles == ui.MAX_PRESENTATION_PROFILES {
		overflow := resource_definition(ui.MAX_PRESENTATION_PROFILES, factory)
		_, overflow_ok, overflow_failure := ui.presentation_profile_registry_register(
			&registry,
			overflow,
		)
		overflow_code = overflow_failure.code
		valid = !overflow_ok && overflow_code == .Profile_Limit && valid
	}

	inspection, inspected, _ := ui.presentation_profile_registry_inspect(&registry)
	retained_bytes := tracking.current_memory_allocated
	peak_bytes := tracking.peak_memory_allocated
	closed, _ := ui.presentation_profile_registry_close(&registry)
	cleanup_bytes := tracking.current_memory_allocated
	latency_ns := time.duration_nanoseconds(time.tick_since(started))
	valid = inspected && inspection.profile_count == u16(profile.profiles) &&
		inspection.stats.live_profiles == u16(profile.profiles) &&
		inspection.stats.retained_bytes == u64(retained_bytes) &&
		retained_bytes <= MEMORY_GATE_BYTES && peak_bytes <= MEMORY_GATE_BYTES &&
		latency_ns <= LATENCY_GATE_NS && closed && cleanup_bytes == 0 && valid
	mem.tracking_allocator_destroy(&tracking)

	fmt.printf(
		"study=presentation-profile profile=%s valid=%v profiles=%d replacements=%d renderer_changes=%d fallback_depth=%d retained_bytes=%d peak_bytes=%d memory_gate_bytes=%d latency_ns=%d latency_gate_ns=%d overflow=%s cleanup_bytes=%d\n",
		profile.name,
		valid,
		profile.profiles,
		profile.replacements,
		RENDERER_CHANGES,
		ui.MAX_PRESENTATION_PROFILE_FALLBACK_DEPTH,
		retained_bytes,
		peak_bytes,
		MEMORY_GATE_BYTES,
		latency_ns,
		LATENCY_GATE_NS,
		overflow_code,
		cleanup_bytes,
	)
	return valid
}

resource_definition :: proc(
	index: int,
	fallback: ui.Presentation_Profile_Handle,
) -> ui.Presentation_Profile_Definition {
	name_value := fmt.aprintf("profile-%02d", index)
	defer delete(name_value)
	name, _ := ui.presentation_profile_text(name_value)
	source, _ := ui.presentation_profile_text("resource-study")
	return {
		name = name,
		source = source,
		kind = .Package if index % 2 == 0 else .Personal,
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
			minimum_columns = 18,
			preferred_rows = 5,
			preferred_columns = 56,
			maximum_rows = 8,
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

resource_renderer :: proc(with_overlap: bool) -> ui.Renderer_Profile {
	capabilities := ui.Renderer_Capabilities {
		.Cell_Geometry,
		.Clipping,
		.Unicode_Profile,
		.Text_Cursor,
		.Input_Cursor,
		.Semantic_Attributes,
		.Atomic_Generation,
		.Full_Redraw,
	}
	if with_overlap {
		capabilities += {.Popup_Overlap}
	}
	return {
		id = 1,
		capabilities = capabilities,
		unicode_profile = 17,
		max_rows = 80,
		max_columns = 240,
		max_cells = 19_200,
		attributes = {.Bold, .Dim, .Underline, .Reverse},
	}
}
