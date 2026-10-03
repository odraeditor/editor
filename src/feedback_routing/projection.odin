// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package feedback_routing

import "../feedback"
import "../ui"
import "core:fmt"

/* registry_route_and_project resolves and projects one immutable feedback generation. */
registry_route_and_project :: proc(
	registry: ^Registry,
	record: feedback.Record,
	frontend: Frontend_Context,
) -> (Routed_Presentation, bool, Failure) {
	resolution, resolved, resolve_failure := registry_resolve(registry, record, frontend)
	if !resolved do return {}, false, resolve_failure
	result := Routed_Presentation{resolution = resolution}
	if resolution.suppressed do return result, true, {}
	state := registry_state(registry)
	for selected in resolution.destinations[:resolution.destination_count] {
		destination_index := configuration_destination_index(&state.active, selected.selected)
		if destination_index < 0 {
			return {}, false, registry_reject(state, Failure{operation = .Project, code = .Missing_Destination, destination = selected.selected})
		}
		destination := state.active.destinations[destination_index]
		projection_index := configuration_projection_index(&state.active, destination.projection)
		if projection_index < 0 {
			return {}, false, registry_reject(state, Failure{operation = .Project, code = .Missing_Projection, destination = destination.id, projection = destination.projection})
		}
		projected, projected_ok, project_failure := project_record(
			record,
			destination,
			state.active.projections[projection_index],
			frontend,
			selected.degraded,
		)
		if !projected_ok do return {}, false, registry_reject(state, project_failure)
		result.projections[result.projection_count] = projected
		result.projection_count += 1
	}
	return result, true, {}
}

/* project_record formats one record for one already selected destination. */
project_record :: proc(
	record: feedback.Record,
	destination: Destination,
	definition: Projection_Definition,
	frontend: Frontend_Context,
	degraded := false,
) -> (Projection, bool, Failure) {
	if destination.projection != definition.id || record.id == feedback.Record_ID(0) ||
	   definition.maximum_bytes == 0 || destination.content_bytes == 0 {
		return {}, false, Failure{operation = .Project, code = .Invalid_Projection, destination = destination.id, projection = definition.id}
	}
	projection := Projection {
		record_id = record.id,
		record_generation = record.generation,
		destination = destination.id,
		destination_generation = destination.generation,
		projection = definition.id,
		projection_generation = definition.generation,
		profile = destination.profile,
		style_role = projection_style(definition, record),
		focus = destination.focus,
		dismissal = destination.dismissal,
		capacity = destination.capacity,
		severity = record.severity,
		attention = record.attention,
		action_count = u8(len(record.actions)),
		degraded = degraded,
	}
	limit := min(int(definition.maximum_bytes), int(destination.content_bytes), len(projection.content))
	if limit <= 0 {
		return {}, false, Failure{operation = .Project, code = .Projection_Overflow, destination = destination.id, projection = definition.id}
	}
	if definition.textual_severity || frontend.color == .Monochrome {
		projection_append(&projection, severity_prefix(record.severity), limit)
	}
	if definition.include_title do projection_append(&projection, record.title, limit)
	if definition.include_message && len(record.message) > 0 {
		if projection.content_bytes > 0 do projection_append(&projection, ": ", limit)
		projection_append(&projection, record.message, limit)
	}
	if definition.include_progress && record.kind == .Progress {
		projection_append(&projection, " (", limit)
		if record.progress.measurement == .Determinate {
			numeric: [64]u8
			projection_append(&projection, fmt.bprintf(numeric[:], "%d/%d", record.progress.current, record.progress.total), limit)
		}
		if len(record.progress.phase) > 0 {
			if record.progress.measurement == .Determinate do projection_append(&projection, " ", limit)
			projection_append(&projection, record.progress.phase, limit)
		}
		projection_append(&projection, ")", limit)
	}
	if definition.include_actions && len(record.actions) > 0 {
		action_text: [64]u8
		projection_append(&projection, fmt.bprintf(action_text[:], " [%d actions]", len(record.actions)), limit)
	}
	if definition.include_source {
		source_text: [64]u8
		projection_append(&projection, fmt.bprintf(source_text[:], " [source %d]", record.source.id), limit)
	}
	if projection.truncated && projection.content_bytes >= 3 {
		copy(projection.content[projection.content_bytes - 3:projection.content_bytes], "...")
	}
	return projection, true, {}
}

@(private)
projection_append :: proc(projection: ^Projection, value: string, limit: int) {
	if projection == nil || len(value) == 0 do return
	remaining := limit - int(projection.content_bytes)
	if remaining <= 0 {
		projection.truncated = true
		return
	}
	copied := copy(projection.content[projection.content_bytes:limit], transmute([]u8)value)
	projection.content_bytes += u16(copied)
	projection.truncated = projection.truncated || copied < len(value)
}

@(private)
severity_prefix :: proc(severity: feedback.Severity) -> string {
	switch severity {
	case .Information: return "[info] "
	case .Warning: return "[warning] "
	case .Error: return "[error] "
	case .Invalid: return "[unknown] "
	}
	return "[unknown] "
}

@(private)
projection_style :: proc(definition: Projection_Definition, record: feedback.Record) -> ui.Style_Role {
	if record.attention == .Required do return definition.attention_role
	if record.kind == .Progress && !feedback.record_is_terminal(record) do return definition.progress_role
	switch record.severity {
	case .Information: return definition.information_role
	case .Warning: return definition.warning_role
	case .Error: return definition.error_role
	case .Invalid: return .Diagnostic_Rejected
	}
	return .Diagnostic_Rejected
}
