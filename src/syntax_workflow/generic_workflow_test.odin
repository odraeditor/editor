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

@(test)
/* generic_workflow_copies_injections_and_invalidates_replacement verifies lifecycle integration. */
generic_workflow_copies_injections_and_invalidates_replacement :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-generic-syntax-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path := syntax_test_path(t, directory, "generic.odin")
	defer delete(path)
	contents := "package generic\nmain :: proc() {}\n"
	testing.expect(t, os.write_entire_file(path, contents) == nil)

	session: editor_session.Session
	handle, session_ok, _ := editor_session.session_init(
		&session,
		9_201,
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
	if !opened_ok {
		_, _ = Syntax_Workflow_Close(workflow)
		_ = syntax_workflow_test_session_close(&session, handle)
		return
	}
	access, accessed, _ := editor_session.session_entry_access(&session, opened.entry)
	borrow, borrowed, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, accessed && borrowed)
	if !borrowed {
		_, _ = Syntax_Workflow_Close(workflow)
		_ = syntax_workflow_test_session_close(&session, handle)
		return
	}
	_, _ = Syntax_Workflow_Reconcile(workflow, &session, handle)
	_, _ = Syntax_Workflow_Maintain(workflow, &session, handle)
	stats, stats_ok, _ := editor.buffer_stats(borrow.buffer)
	testing.expect(t, stats_ok)
	index, found := Syntax_Workflow_Find_Buffer(workflow, stats.buffer_id)
	testing.expect(t, found)
	if !found do return
	entry := &workflow.entries[index]
	testing.expect_value(t, entry.inspection.analysis_status, language.Analysis_Status.Current)

	candidates := [1]Injection_Candidate {{
		identity = 41,
		start = 0,
		end = 7,
		language_id = language.FACTORY_JAN_LANGUAGE_ID,
		priority = 100,
	}}
	composed, compose_failure := Syntax_Workflow_Compose_Injections(
		workflow,
		stats.buffer_id,
		candidates[:],
	)
	testing.expectf(t, composed, "workflow injection failed with %v", compose_failure.code)
	inspection, inspected := Syntax_Workflow_Inspect_Analysis(workflow, borrow.buffer)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.injections.region_count, u16(1))
	testing.expect_value(t, inspection.injections.source_revision, stats.revision)
	testing.expect_value(
		t,
		inspection.injections.regions[0].language_identity.id,
		language.FACTORY_JAN_LANGUAGE_ID,
	)
	original_priority := inspection.injections.regions[0].priority
	inspection.injections.regions[0].priority = 0
	confirmed, confirmed_ok := Syntax_Workflow_Inspect_Analysis(workflow, borrow.buffer)
	testing.expect(t, confirmed_ok)
	testing.expect_value(t, confirmed.injections.regions[0].priority, original_priority)

	confirmed_revision := entry.inspection.confirmed_revision
	entry.inspection.confirmed_revision += 1
	_, stale_failure := Syntax_Workflow_Compose_Injections(workflow, stats.buffer_id, candidates[:])
	testing.expect_value(t, stale_failure.code, Injection_Failure_Code.Invalid_Request)
	testing.expect_value(t, entry.injections.generation, confirmed.injections.generation)
	entry.inspection.confirmed_revision = confirmed_revision

	empty, empty_failure := Syntax_Workflow_Compose_Injections(
		workflow,
		stats.buffer_id,
		nil,
	)
	testing.expectf(t, empty, "empty composition failed with %v", empty_failure.code)
	empty_inspection, empty_inspected := Syntax_Workflow_Inspect_Analysis(workflow, borrow.buffer)
	testing.expect(t, empty_inspected)
	testing.expect_value(t, empty_inspection.injections.region_count, u16(0))
	testing.expect(t, empty_inspection.injections.generation > confirmed.injections.generation)

	composed, _ = Syntax_Workflow_Compose_Injections(workflow, stats.buffer_id, candidates[:])
	testing.expect(t, composed)
	replacement_definition := syntax_factory_provider_definition()
	replacement_definition.name = "generic-workflow-replacement"
	registry, registry_found := syntax_workflow_provider_registry(
		workflow,
		language.FACTORY_ODIN_LANGUAGE_ID,
	)
	testing.expect(t, registry_found)
	if registry_found {
		replacement, registered, _ := language.provider_registry_register_native(
			&registry.registry,
			replacement_definition,
		)
		confirmed_provider, provider_confirmed, _ := language.provider_registry_confirm_native(
			&registry.registry,
			replacement,
		)
		before, selected, _ := language.provider_registry_selection(&registry.registry)
		_, replaced, _ := language.provider_registry_replace(
			&registry.registry,
			before,
			confirmed_provider,
		)
		testing.expect(t, registered && provider_confirmed && selected && replaced)
		_, _ = Syntax_Workflow_Reconcile(workflow, &session, handle)
		testing.expect_value(t, entry.injections.generation, Injection_Generation(0))
		testing.expect_value(t, len(entry.injections.regions), 0)
	}

	_, _ = Syntax_Workflow_Maintain(workflow, &session, handle)
	composed, _ = Syntax_Workflow_Compose_Injections(workflow, stats.buffer_id, candidates[:])
	testing.expect(t, composed)
	closed, close_failure := Syntax_Workflow_Close(workflow)
	testing.expect(t, closed)
	testing.expect_value(t, close_failure.code, language.Failure_Code.None)
	testing.expect(t, !workflow.entries[index].live)
	testing.expect_value(t, workflow.entries[index].injections.generation, Injection_Generation(0))
	testing.expect(t, syntax_workflow_test_session_close(&session, handle))
}
