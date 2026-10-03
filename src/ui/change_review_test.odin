// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "../editor"
import editor_view "../view"
import "core:testing"

/* Verifies staged change kinds remain semantic and use the shared decoration path. */
@(test)
change_reviews_project_semantic_ranges :: proc(t: ^testing.T) {
	registry: Registry
	registry_ok, _ := registry_init(&registry, 73)
	testing.expect(t, registry_ok)
	if !registry_ok do return
	defer registry_close(&registry)
	proposal, proposal_ok, _ := proposal_begin(&registry)
	testing.expect(t, proposal_ok)
	if !proposal_ok do return
	defer if proposal.state != nil do proposal_abort(&proposal)
	_, _, _ = proposal_add_style(&proposal, .Text_Normal)
	_, _, _ = proposal_add_style(&proposal, .Text_Search_Current)
	_, _, _ = proposal_add_style(&proposal, .Diagnostic_Normal)
	_, _, _ = proposal_add_style(&proposal, .Diagnostic_Rejected)
	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(&buffer, 731, "alpha\nbeta\n", {persistent = context.allocator, temporary = context.temp_allocator})
	testing.expect(t, buffer_ok)
	if !buffer_ok do return
	defer editor.buffer_close(&buffer)
	views: editor_view.Registry
	views_ok, _ := editor_view.registry_init(&views, 732, context.allocator)
	view, view_ok, _ := editor_view.create(&views, &buffer)
	testing.expect(t, views_ok && view_ok)
	if !views_ok || !view_ok do return
	defer { editor_view.close(&views, &view); editor_view.registry_close(&views) }
	text_view, text_ok, _ := proposal_project_editor_text_view(&proposal, &views, view, &buffer, 1)
	testing.expect(t, text_ok)
	kinds := [?]Change_Review_Kind{.Rename, .Move, .Delete, .Conflict}
	for kind, index in kinds {
		projected, failure := proposal_project_change_review(
			&proposal, text_view, 2, 0, u64(index), u64(index + 1), kind, 100,
		)
		testing.expectf(t, projected, "change review failed: %v", failure.code)
	}
}
