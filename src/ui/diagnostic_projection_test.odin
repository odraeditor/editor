// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:testing"

/* Verifies normalized severities, overlapping ranges, and point anchors remain exact. */
@(test)
diagnostics_project_as_decorations :: proc(t: ^testing.T) {
	registry: Registry
	proposal: Proposal
	text_view, ready := syntax_projection_test_prepare(&registry, &proposal, DEFAULT_RESOURCE_LIMITS)
	testing.expect(t, ready)
	if !ready do return
	defer registry_close(&registry)
	roles := [?]Style_Role {
		.Diagnostic_Error,
		.Diagnostic_Warning,
		.Diagnostic_Information,
		.Diagnostic_Hint,
	}
	for role in roles {
		_, style_ok, _ := proposal_add_style(&proposal, role, {.Underline})
		testing.expect(t, style_ok)
	}
	records := [3]Diagnostic_Projection_Record {
		{id = 1, source_revision = 3, start = 0, end = 5,
			style_role = .Diagnostic_Warning, precedence = DIAGNOSTIC_PRECEDENCE_BASE + 3},
		{id = 2, source_revision = 3, start = 2, end = 5,
			style_role = .Diagnostic_Error, precedence = DIAGNOSTIC_PRECEDENCE_BASE + 4},
		{id = 3, source_revision = 3, start = 5, end = 5, point = true,
			style_role = .Diagnostic_Hint, precedence = DIAGNOSTIC_PRECEDENCE_BASE},
	}
	count, projected, failure := proposal_project_diagnostics(
		&proposal, text_view, records[:], 704,
	)
	testing.expectf(t, projected, "diagnostic projection failed with %v", failure.code)
	testing.expect_value(t, count, u32(3))
	state := proposal_state(&proposal)
	if state != nil && state.decoration_count == 3 {
		testing.expect_value(t, state.decorations[0].kind, Decoration_Kind.Diagnostic)
		testing.expect_value(t, state.decorations[0].style_role, Style_Role.Diagnostic_Warning)
		testing.expect_value(t, state.decorations[1].style_role, Style_Role.Diagnostic_Error)
		testing.expect(t, state.decorations[1].precedence > state.decorations[0].precedence)
		testing.expect_value(t, state.decorations[2].start, state.decorations[2].end)
	}
	proposal_abort(&proposal)
}

/* Verifies stale or malformed diagnostic generations reject without partial UI state. */
@(test)
stale_diagnostics_reject_atomically :: proc(t: ^testing.T) {
	registry: Registry
	proposal: Proposal
	text_view, ready := syntax_projection_test_prepare(&registry, &proposal, DEFAULT_RESOURCE_LIMITS)
	if !ready do return
	defer registry_close(&registry)
	defer proposal_abort(&proposal)
	_, _, _ = proposal_add_style(&proposal, .Diagnostic_Error, {.Underline})
	records := [1]Diagnostic_Projection_Record {{
		id = 1, source_revision = 2, start = 0, end = 3,
		style_role = .Diagnostic_Error, precedence = DIAGNOSTIC_PRECEDENCE_BASE + 4,
	}}
	_, projected, failure := proposal_project_diagnostics(
		&proposal, text_view, records[:], 704,
	)
	testing.expect(t, !projected)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Decoration)
	state := proposal_state(&proposal)
	if state != nil do testing.expect_value(t, state.decoration_count, 0)
}
