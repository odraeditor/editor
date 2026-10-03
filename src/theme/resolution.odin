// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package theme

import "../ui"

/* Resolved_Presentation_Style copies one theme style for one chrome slot. */
Resolved_Presentation_Style :: struct {
	slot:  ui.Presentation_Chrome_Slot,
	style: ui.Style_Definition,
}

/* Resolved_Presentation_Profile is one complete theme-bound profile value. */
Resolved_Presentation_Profile :: struct {
	profile:     ui.Presentation_Profile_Handle,
	role:        ui.Presentation_Profile_Role,
	styles:      [ui.PRESENTATION_CHROME_SLOT_COUNT]Resolved_Presentation_Style,
	style_count: u8,
}

/* definition_resolve_ui copies one complete theme definition into a fresh UI proposal. */
definition_resolve_ui :: proc(
	proposal: ^ui.Proposal,
	styles: []ui.Style_Definition,
) -> (ok: bool, failure: ui.Failure) {
	if proposal == nil || len(styles) != CURRENT_STYLE_ROLE_COUNT {
		return false, ui.Failure {
			operation = .Prepare,
			code = .Invalid_Style,
			limit = CURRENT_STYLE_ROLE_COUNT,
			actual = u64(len(styles)),
		}
	}
	seen: [MAX_STYLES + 1]bool
	for style in styles {
		if !ui.style_definition_is_valid(style) {
			return false, ui.Failure{operation = .Prepare, code = .Invalid_Style}
		}
		index := int(style.role)
		if seen[index] {
			return false, ui.Failure{operation = .Prepare, code = .Invalid_Style}
		}
		seen[index] = true
	}
	for style in styles {
		_, added, add_failure := ui.proposal_add_style(
			proposal,
			style.role,
			style.attributes,
			style.foreground,
			style.background,
		)
		if !added do return false, add_failure
	}
	return true, {}
}

/* definition_resolve_presentation_profile binds profile slots to one complete theme. */
definition_resolve_presentation_profile :: proc(
	styles: []ui.Style_Definition,
	record: ui.Presentation_Profile_Record,
) -> (resolved: Resolved_Presentation_Profile, ok: bool, failure: ui.Failure) {
	if record.handle.registry_id == ui.Presentation_Profile_Registry_ID(0) ||
	   record.handle.profile_id == ui.Presentation_Profile_ID(0) ||
	   record.handle.profile_generation == ui.Presentation_Profile_Generation(0) ||
	   record.handle.role != record.definition.role ||
	   record.definition.mapping_count == 0 ||
	   int(record.definition.mapping_count) > len(record.definition.mappings) {
		return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_Style}
	}
	seen: ui.Presentation_Chrome_Slots
	resolved.profile = record.handle
	resolved.role = record.definition.role
	definition := record.definition
	for mapping in definition.mappings[:definition.mapping_count] {
		if mapping.slot == .Invalid || mapping.slot in seen {
			return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_Style}
		}
		style, found := style_for_role(styles, mapping.style_role)
		if !found || !ui.style_definition_is_valid(style) {
			return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_Style}
		}
		resolved.styles[resolved.style_count] = {slot = mapping.slot, style = style}
		resolved.style_count += 1
		seen += {mapping.slot}
	}
	for required in ui.presentation_profile_required_slots(record.definition.role) {
		if required not_in seen {
			return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_Style}
		}
	}
	return resolved, true, {}
}

/* resolved_presentation_profile_style finds one copied chrome-slot style. */
resolved_presentation_profile_style :: proc(
	resolved: ^Resolved_Presentation_Profile,
	slot: ui.Presentation_Chrome_Slot,
) -> (style: ui.Style_Definition, ok: bool) {
	if resolved == nil || slot == .Invalid {
		return {}, false
	}
	for entry in resolved.styles[:resolved.style_count] {
		if entry.slot == slot {
			return entry.style, true
		}
	}
	return {}, false
}
