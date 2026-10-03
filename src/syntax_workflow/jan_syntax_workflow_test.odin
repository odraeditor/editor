// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package syntax_workflow

import "../editor"
import "../editor_session"
import "../language"
import "../transaction"
import editor_view "../view"
import "base:runtime"
import "core:os"
import "core:testing"

/* Verifies factory Jan suffix parity, shared owners, explicit selection, and Odin isolation. */
@(test)
factory_jan_workflow_shares_one_language_contract :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-jan-factory-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	org_path := syntax_test_path(t, directory, "same.org")
	jan_path := syntax_test_path(t, directory, "same.jan")
	txt_path := syntax_test_path(t, directory, "explicit.txt")
	odin_path := syntax_test_path(t, directory, "main.odin")
	defer delete(org_path)
	defer delete(jan_path)
	defer delete(txt_path)
	defer delete(odin_path)
	contents := "#+title: Same\n* TODO Heading\nSee [[https://example.test][link]].\n"
	testing.expect(t, os.write_entire_file(org_path, contents) == nil)
	testing.expect(t, os.write_entire_file(jan_path, contents) == nil)
	testing.expect(t, os.write_entire_file(txt_path, contents) == nil)
	testing.expect(t, os.write_entire_file(odin_path, "package main\n") == nil)

	session: editor_session.Session
	handle, session_ok, _ := editor_session.session_init(
		&session,
		9_101,
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
	org, org_ok := jan_syntax_workflow_open(t, &session, handle, org_path)
	jan, jan_ok := jan_syntax_workflow_open(t, &session, handle, jan_path)
	txt, txt_ok := jan_syntax_workflow_open(t, &session, handle, txt_path)
	odin, odin_ok := jan_syntax_workflow_open(t, &session, handle, odin_path)
	if !org_ok || !jan_ok || !txt_ok || !odin_ok {
		_, _ = Syntax_Workflow_Close(workflow)
		_ = syntax_workflow_test_session_close(&session, handle)
		return
	}
	txt_access, txt_access_ok, _ := editor_session.session_entry_access(&session, txt.entry)
	txt_borrow, txt_borrowed, _ := editor_session.entry_access_borrow(txt_access)
	testing.expect(t, txt_access_ok && txt_borrowed)
	testing.expect(t, txt_borrowed && syntax_workflow_select_jan(workflow, txt_borrow.buffer))
	reconciled, reconcile_failure := Syntax_Workflow_Reconcile(workflow, &session, handle)
	testing.expectf(t, reconciled, "Jan reconciliation failed with %v", reconcile_failure.code)
	maintained, maintenance_failure := Syntax_Workflow_Maintain(workflow, &session, handle)
	testing.expectf(t, maintained, "Jan maintenance failed with %v", maintenance_failure.code)
	testing.expect_value(t, workflow.live_count, u16(4))

	org_id := syntax_test_buffer_id(t, &session, org.entry)
	jan_id := syntax_test_buffer_id(t, &session, jan.entry)
	txt_id := syntax_test_buffer_id(t, &session, txt.entry)
	odin_id := syntax_test_buffer_id(t, &session, odin.entry)
	org_index, org_selected := Syntax_Workflow_Find_Buffer(workflow, org_id)
	jan_index, jan_selected := Syntax_Workflow_Find_Buffer(workflow, jan_id)
	txt_index, txt_selected := Syntax_Workflow_Find_Buffer(workflow, txt_id)
	odin_index, odin_selected := Syntax_Workflow_Find_Buffer(workflow, odin_id)
	testing.expect(t, org_selected && jan_selected && txt_selected && odin_selected)
	if org_selected && jan_selected && txt_selected && odin_selected {
		org_entry := &workflow.entries[org_index]
		jan_entry := &workflow.entries[jan_index]
		txt_entry := &workflow.entries[txt_index]
		odin_entry := &workflow.entries[odin_index]
		testing.expect(t, syntax_workflow_entry_is_jan(org_entry))
		testing.expect(t, syntax_workflow_entry_is_jan(jan_entry))
		testing.expect(t, syntax_workflow_entry_is_jan(txt_entry))
		testing.expect(t, !syntax_workflow_entry_is_jan(odin_entry))
		testing.expect_value(t, org_entry.bundle_identity, language.FACTORY_JAN_BUNDLE_IDENTITY)
		testing.expect_value(t, jan_entry.bundle_identity, language.FACTORY_JAN_BUNDLE_IDENTITY)
		testing.expect_value(t, txt_entry.bundle_identity, language.FACTORY_JAN_BUNDLE_IDENTITY)
		testing.expect_value(t, odin_entry.bundle_identity, language.FACTORY_ODIN_BUNDLE_IDENTITY)
		testing.expect_value(t, org_entry.inspection.association.language, jan_entry.inspection.association.language)
		testing.expect_value(t, org_entry.inspection.selection, jan_entry.inspection.selection)
		testing.expect_value(t, txt_entry.inspection.association.source, language.Association_Source.Native_Request)
		testing.expect_value(t, odin_entry.inspection.association.language.id, language.FACTORY_ODIN_LANGUAGE_ID)
		testing.expect_value(t, org_entry.inspection.analysis_status, language.Analysis_Status.Current)
		testing.expect_value(t, odin_entry.inspection.analysis_status, language.Analysis_Status.Current)
		testing.expect(t, jan_syntax_workflow_equivalent_nodes(
			language.jan_structural_analysis_nodes(&org_entry.jan_analysis),
			language.jan_structural_analysis_nodes(&jan_entry.jan_analysis),
		))
		generation := org_entry.inspection.parse_snapshot.tree_generation
		org_access, org_access_ok, _ := editor_session.session_entry_access(&session, org.entry)
		org_borrow, org_borrowed, _ := editor_session.entry_access_borrow(org_access)
		testing.expect(t, org_access_ok && org_borrowed)
		if org_borrowed {
			additional, cloned, _ := editor_view.clone_additional(
				org_borrow.view_registry,
				org_borrow.primary_view,
			)
			testing.expect(t, cloned)
			if cloned {
				_, entry_reconciled, _ := editor_session.entry_access_reconcile(org_access)
				testing.expect(t, entry_reconciled)
				_, _ = Syntax_Workflow_Reconcile(workflow, &session, handle)
				testing.expect_value(t, workflow.live_count, u16(4))
				testing.expect_value(t, org_entry.inspection.parse_snapshot.tree_generation, generation)
				close_access, _, _ := editor_session.session_entry_access(&session, org.entry)
				close_borrow, close_borrowed, _ := editor_session.entry_access_borrow(close_access)
				if close_borrowed {
					_, _ = editor_view.close(close_borrow.view_registry, &additional)
					_, _, _ = editor_session.entry_access_reconcile(close_access)
				}
			}
		}
		jan_registration, _ := language.factory_bundle_registration(
			language.FACTORY_JAN_BUNDLE_IDENTITY,
		)
		jan_registration.provider.name = "test-jan-replacement"
		jan_provider_registry, registry_found := syntax_workflow_provider_registry(
			workflow,
			language.FACTORY_JAN_LANGUAGE_ID,
		)
		testing.expect(t, registry_found)
		if !registry_found do return
		replacement, registered, _ := language.provider_registry_register_native(
			&jan_provider_registry.registry,
			jan_registration.provider,
		)
		confirmed, confirmed_ok, _ := language.provider_registry_confirm_native(
			&jan_provider_registry.registry,
			replacement,
		)
		before, _, _ := language.provider_registry_selection(&jan_provider_registry.registry)
		_, replaced, _ := language.provider_registry_replace(
			&jan_provider_registry.registry,
			before,
			confirmed,
		)
		testing.expect(t, registered && confirmed_ok && replaced)
		odin_generation := odin_entry.inspection.parse_snapshot.tree_generation
		_, _ = Syntax_Workflow_Reconcile(workflow, &session, handle)
		testing.expect_value(t, org_entry.inspection.analysis_status, language.Analysis_Status.Pending)
		testing.expect_value(t, odin_entry.inspection.parse_snapshot.tree_generation, odin_generation)
		_, _ = Syntax_Workflow_Maintain(workflow, &session, handle)
		testing.expect_value(t, org_entry.inspection.analysis_status, language.Analysis_Status.Current)
	}

	_, activated, _ := editor_session.session_activate(&session, odin.entry)
	testing.expect(t, activated)
	_, closed_org, _ := editor_session.session_close_buffer(
		&session,
		{entry = org.entry, authority = .Discard_Modified},
	)
	testing.expect(t, closed_org)
	_, _ = Syntax_Workflow_Reconcile(workflow, &session, handle)
	testing.expect_value(t, workflow.live_count, u16(3))
	closed, close_failure := Syntax_Workflow_Close(workflow)
	testing.expect(t, closed)
	testing.expect_value(t, close_failure.code, language.Failure_Code.None)
	testing.expect(t, syntax_workflow_test_session_close(&session, handle))
}

/* Verifies Jan edits, configuration changes, malformed recovery, and stale rejection. */
@(test)
factory_jan_workflow_refreshes_exact_revisions :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-jan-refresh-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	jan_path := syntax_test_path(t, directory, "refresh.jan")
	defer delete(jan_path)
	testing.expect(t, os.write_entire_file(jan_path, "* TODO Heading\n#+begin_src odin\nmain :: proc() {}\n") == nil)
	session: editor_session.Session
	handle, session_ok, _ := editor_session.session_init(
		&session,
		9_102,
		{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, session_ok)
	if !session_ok do return
	workflow, workflow_error := new(Syntax_Workflow_State, context.allocator)
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
	opened, opened_ok := jan_syntax_workflow_open(t, &session, handle, jan_path)
	if !opened_ok {
		_, _ = Syntax_Workflow_Close(workflow)
		_ = syntax_workflow_test_session_close(&session, handle)
		return
	}
	_, _ = Syntax_Workflow_Reconcile(workflow, &session, handle)
	_, _ = Syntax_Workflow_Maintain(workflow, &session, handle)
	buffer_id := syntax_test_buffer_id(t, &session, opened.entry)
	index, selected := Syntax_Workflow_Find_Buffer(workflow, buffer_id)
	testing.expect(t, selected)
	access, access_ok, _ := editor_session.session_entry_access(&session, opened.entry)
	borrow, borrowed, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, access_ok && borrowed)
	if selected && borrowed {
		entry := &workflow.entries[index]
		testing.expect_value(t, entry.inspection.analysis_status, language.Analysis_Status.Current)
		testing.expect(t, len(language.jan_structural_analysis_recoveries(&entry.jan_analysis)) > 0)
		spans, queried, _ := language.jan_structural_analysis_query_spans(
			&entry.jan_analysis,
			0,
			entry.inspection.usage.retained_source_bytes,
			0,
			77,
		)
		testing.expect(t, queried)
		if queried {
			entry.syntax = spans
			entry.inspection.syntax_snapshot = spans.snapshot
		}
		initial_generation := entry.inspection.parse_snapshot.tree_generation
		edit: transaction.Transaction
		started, _ := transaction.transaction_begin(
			&edit,
			9_103,
			9_103,
			borrow.buffer,
			{kind = .Built_In, descriptor = "Jan syntax workflow test"},
			"insert-title",
			{persistent = context.allocator, temporary = context.temp_allocator},
		)
		testing.expect(t, started)
		if started {
			position, positioned, _ := transaction.transaction_position(&edit, 0)
			spliced, _ := transaction.transaction_splice(
				&edit,
				{start = position, end = position, replacement = "#+title: Changed\n"},
			)
			validated, _ := transaction.transaction_validate(&edit)
			observer := Syntax_Commit_Observer_Context{workflow = workflow, buffer = borrow.buffer}
			_, committed, _ := transaction.transaction_commit(
				&edit,
				Syntax_Workflow_Commit_Observer(&observer),
			)
			testing.expect(t, positioned && spliced && validated && committed)
			testing.expect_value(t, entry.inspection.analysis_status, language.Analysis_Status.Pending)
			testing.expect_value(t, entry.inspection.syntax_snapshot, language.Syntax_Snapshot{})
			_, _ = Syntax_Workflow_Maintain(workflow, &session, handle)
			testing.expect_value(t, entry.inspection.confirmed_revision, editor.Revision(1))
			testing.expect(t, entry.inspection.parse_snapshot.tree_generation > initial_generation)
			_, _ = transaction.transaction_close(&edit)
		}
		configuration := language.jan_factory_configuration(2)
		previous_selection := entry.inspection.selection_generation
		testing.expect(t, syntax_workflow_set_jan_configuration(workflow, configuration))
		testing.expect(t, entry.inspection.selection_generation > previous_selection)
		testing.expect_value(t, entry.inspection.analysis_status, language.Analysis_Status.Pending)
		_, _ = Syntax_Workflow_Maintain(workflow, &session, handle)
		testing.expect_value(t, entry.inspection.confirmed_revision, editor.Revision(1))
		testing.expect_value(t, entry.inspection.analysis_status, language.Analysis_Status.Current)
		testing.expect_value(t, entry.inspection.parse_snapshot.language.id, language.FACTORY_JAN_LANGUAGE_ID)
		large, large_error := make([]u8, 3 * 1024 * 1024, context.allocator)
		testing.expect(t, large_error == nil)
		if large_error == nil {
			defer delete(large)
			for byte_index in 0 ..< len(large) do large[byte_index] = 'x'
			limited: transaction.Transaction
			limited_started, _ := transaction.transaction_begin(
				&limited,
				9_104,
				9_104,
				borrow.buffer,
				{kind = .Built_In, descriptor = "Jan resource rejection test"},
				"insert-large-text",
				{persistent = context.allocator, temporary = context.temp_allocator},
			)
			testing.expect(t, limited_started)
			if limited_started {
				position, positioned, _ := transaction.transaction_position(&limited, 0)
				spliced, _ := transaction.transaction_splice(
					&limited,
					{start = position, end = position, replacement = string(large)},
				)
				validated, _ := transaction.transaction_validate(&limited)
				observer := Syntax_Commit_Observer_Context{workflow = workflow, buffer = borrow.buffer}
				_, committed, _ := transaction.transaction_commit(
					&limited,
					Syntax_Workflow_Commit_Observer(&observer),
				)
				testing.expect(t, positioned && spliced && validated && committed)
				_, _ = Syntax_Workflow_Maintain(workflow, &session, handle)
				testing.expect_value(t, entry.inspection.analysis_status, language.Analysis_Status.Failed)
				testing.expect_value(t, entry.inspection.latest_failure.code, language.Failure_Code.Work_Limit)
				testing.expect_value(t, entry.inspection.confirmed_revision, editor.Revision(1))
				testing.expect_value(t, entry.inspection.pending.kind, language.Work_Kind.Refresh)
				_, _ = transaction.transaction_close(&limited)
			}
		}
	}
	closed, _ := Syntax_Workflow_Close(workflow)
	testing.expect(t, closed)
	testing.expect(t, syntax_workflow_test_session_close(&session, handle))
}

/* Verifies partial dual-registry initialization contains allocator failure. */
@(test)
factory_jan_workflow_allocator_failure_is_atomic :: proc(t: ^testing.T) {
	failing := Jan_Syntax_Workflow_Failing_Allocator {
		backing = context.allocator,
		fail_after = 1,
	}
	workflow, workflow_error := new(Syntax_Workflow_State, context.allocator)
	testing.expect(t, workflow_error == nil)
	if workflow_error != nil do return
	defer free(workflow, context.allocator)
	initialized, failure := Syntax_Workflow_Init(
		workflow,
		jan_syntax_workflow_failing_allocator(&failing),
	)
	testing.expect(t, !initialized)
	testing.expect_value(t, failure.code, language.Failure_Code.Allocation)
	testing.expect_value(t, workflow.provider_registry_count, u16(0))
	for provider_registry in workflow.provider_registries {
		testing.expect(t, !provider_registry.live && provider_registry.registry.state == nil)
	}
	testing.expect(t, !Syntax_Workflow_Is_Live(workflow))
}

@(private = "file")
jan_syntax_workflow_open :: proc(
	t: ^testing.T,
	session: ^editor_session.Session,
	handle: editor_session.Session_Handle,
	path: string,
) -> (result: editor_session.Admission_Result, ok: bool) {
	failure: editor_session.Failure_Context
	result, ok, failure = editor_session.session_open_path(
		session,
		{
			session = handle,
			path = path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expectf(t, ok, "opening Jan fixture failed with %v", failure.code)
	return result, ok
}

@(private = "file")
jan_syntax_workflow_equivalent_nodes :: proc(
	left, right: []language.Jan_Node_Record,
) -> bool {
	if len(left) != len(right) do return false
	for node, index in left {
		candidate := right[index]
		if node.id != candidate.id || node.parent_id != candidate.parent_id ||
		   node.layer != candidate.layer || node.kind != candidate.kind ||
		   node.structural_depth != candidate.structural_depth ||
		   node.inline_depth != candidate.inline_depth ||
		   node.range.start != candidate.range.start || node.range.end != candidate.range.end ||
		   node.attribute_count != candidate.attribute_count {
			return false
		}
	}
	return true
}

@(private = "file")
Jan_Syntax_Workflow_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private = "file")
jan_syntax_workflow_failing_allocator :: proc(
	data: ^Jan_Syntax_Workflow_Failing_Allocator,
) -> runtime.Allocator {
	return runtime.Allocator{procedure = jan_syntax_workflow_failing_allocator_proc, data = data}
}

@(private = "file")
jan_syntax_workflow_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := cast(^Jan_Syntax_Workflow_Failing_Allocator)allocator_data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after do return nil, .Out_Of_Memory
		allocator.successful_allocations += 1
	}
	return allocator.backing.procedure(
		allocator.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}
