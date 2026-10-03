// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

/* proposal_project_text_decoration adds one checked semantic range to a text view. */
proposal_project_text_decoration :: proc(
	proposal: ^Proposal,
	text_view_handle: Object_Handle,
	owner_id: Owner_ID,
	source_revision, start, end: u64,
	role: Style_Role,
	precedence: u16,
) -> (bool, Failure) {
	state := proposal_state(proposal)
	view, view_ok := resolve_view(state, text_view_handle)
	if state == nil || owner_id == Owner_ID(0) || !view_ok || view.kind != .Text_View ||
	   !view.text.present || source_revision != view.text.revision || start >= end ||
	   end > view.text.source_text_bytes || !resolve_style_role(state, role) {
		return false, generation_failure(state, .Prepare, .Invalid_Decoration)
	}
	_, added, failure := proposal_add_decoration(
		proposal,
		Decoration_Descriptor {
			owner_id = owner_id,
			kind = .Text_Range,
			projection = view.projection,
			source_revision = source_revision,
			start = start,
			end = end,
			style_role = role,
			precedence = precedence,
		},
	)
	return added, failure
}
