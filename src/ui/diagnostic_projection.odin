// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

/* DIAGNOSTIC_PRECEDENCE_BASE keeps diagnostics above syntax and below interactive overlays. */
DIAGNOSTIC_PRECEDENCE_BASE :: u16(1_000)

/* Diagnostic_Projection_Record is one semantic decoration borrowed for proposal preparation. */
Diagnostic_Projection_Record :: struct {
	id:              u64,
	source_revision: u64,
	start:           u64,
	end:             u64,
	point:           bool,
	style_role:      Style_Role,
	precedence:      u16,
}

/* proposal_project_diagnostics copies one exact semantic diagnostic generation. */
proposal_project_diagnostics :: proc(
	proposal: ^Proposal,
	text_view_handle: Object_Handle,
	records: []Diagnostic_Projection_Record,
	owner_id: Owner_ID,
) -> (count: u32, ok: bool, failure: Failure) {
	state := proposal_state(proposal)
	view, view_ok := resolve_view(state, text_view_handle)
	if state == nil || owner_id == Owner_ID(0) || !view_ok || view.kind != .Text_View ||
	   !view.text.present {
		return 0, false, generation_failure(state, .Prepare, .Invalid_Decoration)
	}
	if len(records) > len(state.decorations) - state.decoration_count {
		failure = generation_failure(state, .Prepare, .Decoration_Limit)
		failure.limit = u64(len(state.decorations))
		failure.actual = u64(state.decoration_count + len(records))
		return 0, false, failure
	}
	if u64(len(records)) > u64(max(u64)) - u64(state.next_object_id) {
		return 0, false, generation_failure(state, .Prepare, .Generation_Limit)
	}
	for record, index in records {
		if record.id == 0 || !resolve_style_role(state, record.style_role) ||
		   record.source_revision != view.text.revision ||
		   record.end < record.start || record.end > view.text.source_text_bytes ||
		   record.point != (record.start == record.end) ||
		   index > 0 && record.id <= records[index - 1].id {
			return 0, false, generation_failure(state, .Prepare, .Invalid_Decoration)
		}
	}

	start_count := state.decoration_count
	start_bytes := state.accounting.decoration_bytes
	start_object_id := state.next_object_id
	for record in records {
		_, added, add_failure := proposal_add_decoration(proposal, Decoration_Descriptor {
			owner_id = owner_id,
			kind = .Diagnostic,
			projection = view.projection,
			source_revision = record.source_revision,
			start = record.start,
			end = record.end,
			style_role = record.style_role,
			precedence = record.precedence,
		})
		if !added {
			for index in start_count ..< state.decoration_count do state.decorations[index] = {}
			state.decoration_count = start_count
			state.accounting.decoration_bytes = start_bytes
			state.next_object_id = start_object_id
			return 0, false, add_failure
		}
	}
	return u32(len(records)), true, {}
}
