// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package syntax_workflow

import "../editor"
import "../editor_session"
import "../language"
import "core:os"
import "core:testing"

/* Verifies web variants and HTML child regions flow through the real workflow. */
@(test)
factory_web_workflow_routes_variants_and_injections :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-web-syntax-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	jsx_path := syntax_test_path(t, directory, "component.jsx")
	tsx_path := syntax_test_path(t, directory, "component.tsx")
	html_path := syntax_test_path(t, directory, "index.html")
	defer {
		delete(jsx_path)
		delete(tsx_path)
		delete(html_path)
	}
	testing.expect(t, os.write_entire_file(jsx_path, "export const View = () => <main>Hello</main>;\n") == nil)
	testing.expect(t, os.write_entire_file(tsx_path, "export const View = (): JSX.Element => <main>Hello</main>;\n") == nil)
	testing.expect(t, os.write_entire_file(
		html_path,
		"<main><script>const ready = true;</script><style>main { color: red; }</style></main>\n",
	) == nil)

	session: editor_session.Session
	handle, session_ok, _ := editor_session.session_init(
		&session,
		9_301,
		{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, session_ok)
	if !session_ok do return
	workflow, workflow_error := new(Syntax_Workflow_State, context.allocator)
	testing.expect(t, workflow_error == nil)
	if workflow_error != nil {
		_ = syntax_workflow_test_session_close(&session, handle)
		return
	}
	defer free(workflow, context.allocator)
	initialized, _ := Syntax_Workflow_Init(workflow)
	testing.expect(t, initialized)
	if !initialized {
		_ = syntax_workflow_test_session_close(&session, handle)
		return
	}
	paths := [?]string{jsx_path, tsx_path, html_path}
	entries: [3]editor_session.Entry_Handle
	for path, index in paths {
		opened, opened_ok, _ := editor_session.session_open_path(
			&session,
			{
				session = handle,
				path = path,
				encoding = .UTF8,
				configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
			},
		)
		testing.expect(t, opened_ok)
		if opened_ok do entries[index] = opened.entry
	}
	_, _ = Syntax_Workflow_Reconcile(workflow, &session, handle)
	_, _ = Syntax_Workflow_Maintain(workflow, &session, handle)

	expected_bundles := [?]string {
		language.FACTORY_JAVASCRIPT_JSX_IDENTITY,
		language.FACTORY_TYPESCRIPT_TSX_IDENTITY,
		language.FACTORY_HTML_BUNDLE_IDENTITY,
	}
	for entry_handle, index in entries {
		access, accessed, _ := editor_session.session_entry_access(&session, entry_handle)
		borrow, borrowed, _ := editor_session.entry_access_borrow(access)
		testing.expect(t, accessed && borrowed)
		if !borrowed do continue
		stats, stats_ok, _ := editor.buffer_stats(borrow.buffer)
		entry_index, found := Syntax_Workflow_Find_Buffer(workflow, stats.buffer_id)
		testing.expect(t, stats_ok && found)
		if found do testing.expect_value(t, workflow.entries[entry_index].bundle_identity, expected_bundles[index])
	}

	html_access, html_accessed, _ := editor_session.session_entry_access(&session, entries[2])
	html_borrow, html_borrowed, _ := editor_session.entry_access_borrow(html_access)
	testing.expect(t, html_accessed && html_borrowed)
	if html_borrowed {
		inspection, inspected := Syntax_Workflow_Inspect_Analysis(workflow, html_borrow.buffer)
		testing.expect(t, inspected)
		testing.expect_value(t, inspection.injections.region_count, u16(2))
		javascript_found := false
		css_found := false
		for region in inspection.injections.regions[:inspection.injections.region_count] {
			javascript_found = javascript_found || region.language_identity.id == language.FACTORY_JAVASCRIPT_LANGUAGE_ID
			css_found = css_found || region.language_identity.id == language.FACTORY_CSS_LANGUAGE_ID
		}
		testing.expect(t, javascript_found && css_found)
		css_registry, css_registry_found := syntax_workflow_provider_registry(
			workflow,
			language.FACTORY_CSS_LANGUAGE_ID,
		)
		testing.expect(t, css_registry_found)
		if css_registry_found {
			before, selected, _ := language.provider_registry_selection(&css_registry.registry)
			_, disabled, _ := language.provider_registry_disable(&css_registry.registry, before)
			testing.expect(t, selected && disabled)
			_, _ = Syntax_Workflow_Reconcile(workflow, &session, handle)
			contained, contained_ok := Syntax_Workflow_Inspect_Analysis(workflow, html_borrow.buffer)
			testing.expect(t, contained_ok)
			testing.expect_value(t, contained.selection.selection.state, language.Selection_State.Factory)
			testing.expect_value(t, contained.injections.region_count, u16(1))
			testing.expect_value(t, contained.injections.skipped_missing_child, u16(1))
			testing.expect_value(
				t,
				contained.injections.regions[0].language_identity.id,
				language.FACTORY_JAVASCRIPT_LANGUAGE_ID,
			)
		}
	}
	closed, _ := Syntax_Workflow_Close(workflow)
	testing.expect(t, closed)
	testing.expect(t, syntax_workflow_test_session_close(&session, handle))
}
