// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../editor"
import "../display"
import "../gutter"
import "../interaction"
import "../language_service"

@(private)
language_service_workflow_gutter_diagnostics :: proc(
	workflow: ^Language_Service_Workflow_State,
	buffer: ^editor.Buffer,
	registry: ^interaction.Command_Registry,
	allocator := context.allocator,
) -> (gutter.Marker_Generation, bool) {
	if !language_service_workflow_is_live(workflow) || buffer == nil ||
	   allocator.procedure == nil {
		return {}, false
	}
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	if !stats_ok do return {}, false
	for &session in workflow.sessions {
		if !session.live do continue
		for binding in session.documents {
			if binding.buffer_id != stats.buffer_id do continue
			batch, copied, _ := language_service.diagnostic_store_copy(
				&session.diagnostics,
				binding.binding,
			)
			if !copied do return {}, false
			defer language_service.diagnostic_batch_copy_close(&batch)
			if batch.descriptor.canonical_revision != u64(stats.revision) ||
			   len(batch.records) == 0 {
				return {}, false
			}
			markers: [gutter.MAX_MARKERS_PER_GENERATION]gutter.Marker
			count := 0
			action := gutter_diagnostic_command_reference(registry)
			for record in batch.records {
				if count >= len(markers) do break
				position := editor.Position {
					buffer_id = stats.buffer_id,
					revision = stats.revision,
					byte_offset = editor.Byte_Offset(record.range.start),
				}
				line, line_ok, _ := editor.buffer_line_at_position(buffer, position)
				if !line_ok do continue
				role, glyph, fallback, priority := gutter_diagnostic_presentation(record.severity)
				marker := gutter.Marker {
					id = gutter.Marker_ID(record.id),
					provider = gutter.FACTORY_SEMANTIC_PROVIDER_ID,
					provider_generation = gutter.FACTORY_SEMANTIC_PROVIDER_GENERATION,
					lane = gutter.FACTORY_SEMANTIC_LANE_ID,
					attachment = {
						kind = .Logical_Line,
						logical_line = line.line_index,
						buffer_revision = u64(stats.revision),
					},
					style_role = role,
					priority = priority,
					representation = {kind = .Glyph, value = glyph, fallback = fallback},
					aggregation_label = fallback,
					detail = language_service.diagnostic_record_text(&batch, record.message),
				}
				if action.registry_generation != 0 {
					marker.actions[0] = action
					marker.action_count = 1
				}
				markers[count] = marker
				count += 1
			}
			if count == 0 do return {}, false
			generation, generation_ok, _ := gutter.marker_generation_copy(
				gutter.Marker_Generation_Proposal {
					id = gutter.Marker_Generation_ID(batch.descriptor.generation),
					provider = gutter.FACTORY_SEMANTIC_PROVIDER_ID,
					provider_generation = gutter.FACTORY_SEMANTIC_PROVIDER_GENERATION,
					complete = true,
					markers = markers[:count],
				},
				allocator,
			)
			return generation, generation_ok
		}
	}
	return {}, false
}

@(private)
gutter_diagnostics_intersect_display :: proc(
	generation: ^gutter.Marker_Generation,
	view: display.Snapshot_View,
) -> bool {
	if generation == nil || generation.allocator.procedure == nil do return false
	for marker in generation.markers {
		for row in view.rows {
			if marker.attachment.logical_line == u64(row.logical_line) do return true
		}
	}
	return false
}

@(private)
gutter_diagnostic_presentation :: proc(
	severity: language_service.Diagnostic_Severity,
) -> (gutter.Semantic_Role, string, string, u16) {
	switch severity {
	case .Error:       return .Diagnostic_Error, "●", "E", 400
	case .Warning:     return .Diagnostic_Warning, "▲", "W", 300
	case .Information: return .Diagnostic_Information, "●", "I", 200
	case .Hint:        return .Diagnostic_Hint, "·", "H", 100
	case .Invalid:     return .Unavailable, "?", "?", 0
	}
	return .Unavailable, "?", "?", 0
}

@(private)
gutter_diagnostic_command_reference :: proc(
	registry: ^interaction.Command_Registry,
) -> gutter.Command_Reference {
	if registry == nil do return {}
	handle, found, _ := interaction.command_lookup(registry, "list-language-diagnostics")
	if !found do return {}
	return {
		registry_generation = u64(handle.registry_generation),
		slot = handle.slot,
		entry_generation = handle.entry_generation,
	}
}
