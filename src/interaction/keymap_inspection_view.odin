// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:fmt"

/* MAX_KEYMAP_INSPECTION_ROW_BYTES bounds one complete inspection presentation row. */
MAX_KEYMAP_INSPECTION_ROW_BYTES :: 4 * 1_024

/* keymap_help_record_text formats one effective binding for contextual help. */
keymap_help_record_text :: proc(
	record: Inspection_Record,
	catalog: ^Command_Catalog,
	output: []u8,
) -> string {
	if record.kind != .Binding do return keymap_inspection_record_text(record, nil, catalog, output)
	sequence: [MAX_KEY_SEQUENCE_NOTATION_BYTES]u8
	sequence_text, sequence_ok := key_sequence_notation(record.sequence, sequence[:])
	if !sequence_ok do sequence_text = "<invalid sequence>"
	description := ""
	if entry, found := command_catalog_entry(catalog, record.command); found {
		description = entry.metadata.description
	}
	return fmt.bprintf(output, "%s    %s    %s", sequence_text, record.command_name, description)
}

/* keymap_inspection_record_text formats one retained semantic inspection record. */
keymap_inspection_record_text :: proc(
	record: Inspection_Record,
	inspection: ^Inspection_Result,
	catalog: ^Command_Catalog,
	output: []u8,
) -> string {
	switch record.kind {
	case .Binding:
		sequence: [MAX_KEY_SEQUENCE_NOTATION_BYTES]u8
		sequence_text, sequence_ok := key_sequence_notation(record.sequence, sequence[:])
		if !sequence_ok {
			sequence_text = "<invalid sequence>"
		}
		availability, unavailable_reason := keymap_inspection_availability(catalog, record.command)
		selectors: [2 * 1_024]u8
		selector_text := keymap_inspection_selectors_text(record.selectors, selectors[:])
		if record.protected {
			return fmt.bprintf(
				output,
				"%s -> %s [%s; %s%s; protected] map %s@%d precedence %s priority %d scope %s profile %s@%d state %s@%d effects-admitted %v%s source %s/%s protection-reason %s",
				sequence_text,
				record.command_name,
				keymap_inspection_disposition_text(record.disposition),
				availability,
				unavailable_reason,
				record.map_name,
				record.map_identity.revision,
				keymap_inspection_precedence_text(record.precedence),
				record.priority,
				keymap_inspection_scope_text(record.binding_scope),
				record.profile_name,
				record.profile.revision,
				record.state_name,
				record.state.revision,
				record.effects_admitted,
				selector_text,
				record.provenance.provider,
				record.provenance.source,
				record.protection_reason,
			)
		}
		return fmt.bprintf(
			output,
			"%s -> %s [%s; %s%s] map %s@%d precedence %s priority %d scope %s profile %s@%d state %s@%d effects-admitted %v%s source %s/%s",
			sequence_text,
			record.command_name,
			keymap_inspection_disposition_text(record.disposition),
			availability,
			unavailable_reason,
			record.map_name,
			record.map_identity.revision,
			keymap_inspection_precedence_text(record.precedence),
			record.priority,
			keymap_inspection_scope_text(record.binding_scope),
			record.profile_name,
			record.profile.revision,
			record.state_name,
			record.state.revision,
			record.effects_admitted,
			selector_text,
			record.provenance.provider,
			record.provenance.source,
		)
	case .Remap:
		return fmt.bprintf(
			output,
			"remap %s -> %s [%s] map %s@%d precedence %s priority %d source %s/%s",
			record.original_command_name,
			record.remap_target_name,
			keymap_inspection_disposition_text(record.disposition),
			record.map_name,
			record.map_identity.revision,
			keymap_inspection_precedence_text(record.precedence),
			record.priority,
			record.provenance.provider,
			record.provenance.source,
		)
	case .Map:
		protection := ""
		if record.protected {
			protection = "; protected"
		}
		return fmt.bprintf(
			output,
			"map %s@%d [%s%s] precedence %s priority %d owner %d@%d source %s/%s",
			record.map_name,
			record.map_identity.revision,
			keymap_inspection_disposition_text(record.disposition),
			protection,
			keymap_inspection_precedence_text(record.precedence),
			record.priority,
			record.owner.id,
			record.owner.generation,
			record.provenance.provider,
			record.provenance.source,
		)
	case .Snapshot:
		pending: [MAX_KEY_SEQUENCE_NOTATION_BYTES]u8
		pending_text := "none"
		if inspection.pending.stroke_count > 0 {
			pending_text, _ = key_sequence_notation(
				Key_Sequence {
					strokes = inspection.pending.strokes,
					stroke_count = inspection.pending.stroke_count,
				},
				pending[:],
			)
		}
		return fmt.bprintf(
			output,
			"profile %d@%d registry %d snapshot %d catalog %d state %d@%d context %d@%d pending %s maps %d active %d bindings %d remaps %d bytes %d",
			inspection.snapshot.profile.id,
			inspection.snapshot.profile.revision,
			inspection.snapshot.registry_generation,
			inspection.snapshot.generation,
			inspection.catalog_generation,
			inspection.active_state.id,
			inspection.active_state.revision,
			inspection.snapshot.ctx.id,
			inspection.snapshot.ctx.generation,
			pending_text,
			inspection.usage.map_count,
			inspection.usage.active_map_count,
			inspection.usage.binding_count,
			inspection.usage.remap_count,
			inspection.usage.snapshot_bytes,
		)
	case .Catalog:
		return fmt.bprintf(
			output,
			"catalog %d [%s] active-profile %d@%d active-state %d@%d",
			record.catalog_generation,
			keymap_inspection_disposition_text(record.disposition),
			record.profile.id,
			record.profile.revision,
			record.state.id,
			record.state.revision,
		)
	case .Profile:
		return fmt.bprintf(
			output,
			"profile %s %d@%d [%s] catalog %d",
			record.profile_name,
			record.profile.id,
			record.profile.revision,
			keymap_inspection_disposition_text(record.disposition),
			record.catalog_generation,
		)
	case .State:
		return fmt.bprintf(
			output,
			"state %s %d@%d [%s] profile %s@%d text-input %v admitted-effects %v source %s/%s",
			record.state_name,
			record.state.id,
			record.state.revision,
			keymap_inspection_disposition_text(record.disposition),
			record.profile_name,
			record.profile.revision,
			record.state_admits_text_input,
			record.state_admitted_effects,
			record.provenance.provider,
			record.provenance.source,
		)
	case .Surface:
		availability, unavailable_reason := keymap_inspection_availability(catalog, record.command)
		return fmt.bprintf(
			output,
			"surface %s %d@%d [%s; %s%s] command %s effects-admitted %v source %s/%s",
			record.command_entry_surface_name,
			record.command_entry_surface.id,
			record.command_entry_surface.revision,
			keymap_inspection_disposition_text(record.disposition),
			availability,
			unavailable_reason,
			record.command_name,
			record.effects_admitted,
			record.provenance.provider,
			record.provenance.source,
		)
	case .Rejection:
		return fmt.bprintf(
			output,
			"rejected %v catalog %d profile %d@%d state %d@%d scope %s surface %d@%d map %d@%d context %d@%d owner %d@%d binding %d selector %d strokes %d limit %d actual %d",
			record.failure.code,
			record.failure.catalog_generation,
			record.failure.profile.id,
			record.failure.profile.revision,
			record.failure.state.id,
			record.failure.state.revision,
			keymap_inspection_scope_text(record.failure.binding_scope),
			record.failure.command_entry_surface.id,
			record.failure.command_entry_surface.revision,
			record.failure.map_identity.id,
			record.failure.map_identity.revision,
			record.failure.ctx.id,
			record.failure.ctx.generation,
			record.failure.owner.id,
			record.failure.owner.generation,
			record.failure.binding_index,
			record.failure.selector_index,
			record.failure.stroke_count,
			record.failure.limit,
			record.failure.actual,
		)
	case .Invalid:
		return "Invalid inspection record."
	}
	unreachable()
}

@(private)
keymap_inspection_scope_text :: proc(value: Binding_Scope) -> string {
	switch value {
	case .Protected_Recovery: return "protected-recovery"
	case .Shared_Continuity: return "shared-continuity"
	case .Profile_Specific: return "profile-specific"
	case .State_Specific: return "state-specific"
	case .Invalid: return "not-applicable"
	}
	unreachable()
}

@(private)
keymap_inspection_selectors_text :: proc(
	selectors: []Profile_State_Selector,
	output: []u8,
) -> string {
	if len(selectors) == 0 do return ""
	offset := 0
	prefix := fmt.bprintf(output[offset:], " selectors ")
	offset += len(prefix)
	for selector, index in selectors {
		separator := ""
		if index > 0 do separator = ","
		entry := fmt.bprintf(
			output[offset:],
			"%s%d/%d",
			separator,
			selector.profile_id,
			selector.state_id,
		)
		offset += len(entry)
	}
	return string(output[:offset])
}

@(private)
keymap_inspection_availability :: proc(
	catalog: ^Command_Catalog,
	command: Command_Handle,
) -> (string, string) {
	if catalog == nil || catalog.state == nil || command.registry_generation == Registry_Generation(0) {
		return "not applicable", ""
	}
	entry, found := command_catalog_entry(catalog, command)
	if !found {
		return "not registered", ""
	}
	if entry.availability == .Available {
		return "available", ""
	}
	return "unavailable: ", entry.unavailable_reason
}

@(private)
keymap_inspection_disposition_text :: proc(value: Inspection_Disposition) -> string {
	switch value {
	case .Effective: return "effective"
	case .Shadowed:  return "shadowed"
	case .Masked:    return "masked"
	case .Inactive:  return "inactive"
	case .Rejected:  return "rejected"
	case .Invalid:   return "invalid"
	}
	unreachable()
}

@(private)
keymap_inspection_precedence_text :: proc(value: Precedence_Class) -> string {
	switch value {
	case .Protected_Recovery:     return "protected-recovery"
	case .Transient_Interaction:  return "transient-interaction"
	case .Component_Tool:         return "component-tool"
	case .Buffer_Local:           return "buffer-local"
	case .Language_Context:       return "language-context"
	case .Project:                return "project"
	case .User_Global:            return "user-global"
	case .Profile_Base:           return "profile-base"
	case .Factory_Fallback:       return "factory-fallback"
	case .Invalid:                return "invalid"
	}
	unreachable()
}
