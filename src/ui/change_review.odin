// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

/* proposal_project_change_review decorates one checked range by semantic change kind. */
proposal_project_change_review :: proc(
	proposal: ^Proposal,
	text_view: Object_Handle,
	owner: Owner_ID,
	revision, start, end: u64,
	kind: Change_Review_Kind,
	priority: u16,
) -> (bool, Failure) {
	role := Style_Role.Invalid
	#partial switch kind {
	case .Rename: role = .Text_Search_Current
	case .Move: role = .Diagnostic_Normal
	case .Delete, .Conflict: role = .Diagnostic_Rejected
	}
	if role == .Invalid {
		return false, generation_failure(proposal_state(proposal), .Prepare, .Invalid_Decoration)
	}
	return proposal_project_text_decoration(
		proposal, text_view, owner, revision, start, end, role, priority,
	)
}
