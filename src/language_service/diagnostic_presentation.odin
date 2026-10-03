// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import "../ui"

/* proposal_project_diagnostics validates one service batch before shared UI projection. */
proposal_project_diagnostics :: proc(
	proposal: ^ui.Proposal,
	text_view: ui.Object_Handle,
	descriptor: Diagnostic_Batch_Descriptor,
	records: []Diagnostic_Record,
	owner_id: ui.Owner_ID,
	allocator := context.allocator,
) -> (count: u32, ok: bool, failure: ui.Failure) {
	if proposal == nil || descriptor.generation == Diagnostic_Generation(0) ||
	   descriptor.binding.id == Document_Binding_ID(0) ||
	   u64(descriptor.diagnostics) != u64(len(records)) || allocator.procedure == nil {
		return 0, false, diagnostic_presentation_failure()
	}
	projection, allocation_error := make([]ui.Diagnostic_Projection_Record, len(records), allocator)
	if allocation_error != nil {
		return 0, false, ui.Failure{operation = .Prepare, code = .Allocation}
	}
	defer delete(projection, allocator)
	for record, index in records {
		role, mapped := diagnostic_presentation_style(record.severity)
		if !mapped || record.binding != descriptor.binding ||
		   record.generation != descriptor.generation || record.id == Diagnostic_ID(0) ||
		   record.canonical_revision != descriptor.canonical_revision {
			return 0, false, diagnostic_presentation_failure()
		}
		projection[index] = {
			id = u64(record.id),
			source_revision = record.canonical_revision,
			start = record.range.start,
			end = record.range.end,
			point = record.point,
			style_role = role,
			precedence = ui.DIAGNOSTIC_PRECEDENCE_BASE + u16(5 - int(record.severity)),
		}
	}
	return ui.proposal_project_diagnostics(proposal, text_view, projection, owner_id)
}

@(private)
diagnostic_presentation_style :: proc(severity: Diagnostic_Severity) -> (ui.Style_Role, bool) {
	switch severity {
	case .Error:       return .Diagnostic_Error, true
	case .Warning:     return .Diagnostic_Warning, true
	case .Information: return .Diagnostic_Information, true
	case .Hint:        return .Diagnostic_Hint, true
	case .Invalid:     return .Invalid, false
	}
	return .Invalid, false
}

@(private)
diagnostic_presentation_failure :: proc() -> ui.Failure {
	return {operation = .Prepare, code = .Invalid_Decoration}
}
