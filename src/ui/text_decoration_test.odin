// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "../editor"
import editor_view "../view"
import "core:testing"

/* Verifies generic text decorations retain checked revision and range ownership. */
@(test)
text_decoration_projects_one_semantic_range :: proc(t: ^testing.T) {
	registry: Registry
	ok, _ := registry_init(&registry, 71)
	testing.expect(t, ok)
	if !ok do return
	defer registry_close(&registry)
	proposal, proposal_ok, _ := proposal_begin(&registry)
	testing.expect(t, proposal_ok)
	if !proposal_ok do return
	defer if proposal.state != nil do proposal_abort(&proposal)
	_, style_ok, _ := proposal_add_style(&proposal, .Text_Normal)
	_, current_ok, _ := proposal_add_style(&proposal, .List_Current, {.Reverse})
	testing.expect(t, style_ok && current_ok)
	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer, 711, "alpha\nbeta\n",
		{persistent = context.allocator, temporary = context.temp_allocator})
	testing.expect(t, buffer_ok)
	if !buffer_ok do return
	defer editor.buffer_close(&buffer)
	views: editor_view.Registry
	views_ok, _ := editor_view.registry_init(&views, 712, context.allocator)
	view, view_ok, _ := editor_view.create(&views, &buffer)
	testing.expect(t, views_ok && view_ok)
	if !views_ok || !view_ok do return
	defer {
		editor_view.close(&views, &view)
		editor_view.registry_close(&views)
	}
	text_view, projected, _ := proposal_project_editor_text_view(
		&proposal, &views, view, &buffer, 1)
	testing.expect(t, projected)
	if !projected do return
	decorated, decoration_failure := proposal_project_text_decoration(
		&proposal, text_view, 2, 0, 6, 11, .List_Current, 2_000)
	testing.expectf(t, decorated, "decoration failed: %v", decoration_failure.code)
}
