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
import "core:os"
import "core:testing"

/* Verifies application syntax queries use only one adjacent logical-line halo. */
@(test)
visible_halo_tracks_adjacent_logical_lines :: proc(t: ^testing.T) {
	contents := "first-line\nvisible\nnext-line-longer\nlast\n"
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(9_000),
		contents,
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer editor.buffer_close(&buffer)
	stats, stats_ok, _ := editor.buffer_stats(&buffer)
	testing.expect(t, stats_ok)
	if !stats_ok do return

	halo := syntax_workflow_visible_halo(&buffer, stats, 11, 18)
	testing.expect_value(t, halo, u64(18))
	testing.expect(t, halo < language.MAX_VISIBLE_HALO_BYTES)
	testing.expect_value(t, syntax_workflow_visible_halo(&buffer, stats, 0, stats.text_bytes), u64(0))
}

/* Verifies maintained source files open their exact factory syntax providers. */
@(test)
catalog_opens_factory_syntax_providers :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-language-catalog-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	odin_path := syntax_test_path(t, directory, "main.odin")
	racket_path := syntax_test_path(t, directory, "main.rkt")
	go_path := syntax_test_path(t, directory, "main.go")
	rust_path := syntax_test_path(t, directory, "main.rs")
	defer delete(odin_path)
	defer delete(racket_path)
	defer delete(go_path)
	defer delete(rust_path)
	testing.expect(t, os.write_entire_file(odin_path, "package main\n") == nil)
	testing.expect(t, os.write_entire_file(racket_path, "#lang racket/base\n") == nil)
	testing.expect(t, os.write_entire_file(go_path, "package main\nfunc main() {}\n") == nil)
	testing.expect(t, os.write_entire_file(rust_path, "fn main() {}\n") == nil)

	session: editor_session.Session
	handle, session_ok, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(9_009),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, session_ok)
	if !session_ok do return
	defer syntax_workflow_test_session_close(&session, handle)
	odin, odin_ok, _ := editor_session.session_open_path(
		&session,
		editor_session.Open_Path_Request {
			session = handle,
			path = odin_path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	racket, racket_ok, _ := editor_session.session_open_path(
		&session,
		editor_session.Open_Path_Request {
			session = handle,
			path = racket_path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	go_entry, go_ok, _ := editor_session.session_open_path(
		&session,
		editor_session.Open_Path_Request {
			session = handle,
			path = go_path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	rust, rust_ok, _ := editor_session.session_open_path(
		&session,
		editor_session.Open_Path_Request {
			session = handle,
			path = rust_path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, odin_ok && racket_ok && go_ok && rust_ok)
	if !odin_ok || !racket_ok || !go_ok || !rust_ok do return

	workflow, workflow_error := new(Syntax_Workflow_State, context.allocator)
	testing.expect(t, workflow_error == nil)
	if workflow_error != nil do return
	defer free(workflow, context.allocator)
	initialized, _ := Syntax_Workflow_Init(workflow)
	testing.expect(t, initialized)
	if !initialized do return
	defer Syntax_Workflow_Close(workflow)
	reconciled, reconcile_failure := Syntax_Workflow_Reconcile(workflow, &session, handle)
	testing.expect(t, reconciled)
	testing.expect_value(t, reconcile_failure.code, editor_session.Failure_Code.None)

	odin_access, odin_accessible, _ := editor_session.session_entry_access(&session, odin.entry)
	odin_entry, odin_borrowed, _ := editor_session.entry_access_borrow(odin_access)
	racket_access, racket_accessible, _ := editor_session.session_entry_access(&session, racket.entry)
	racket_entry, racket_borrowed, _ := editor_session.entry_access_borrow(racket_access)
	go_access, go_accessible, _ := editor_session.session_entry_access(&session, go_entry.entry)
	go_borrow, go_borrowed, _ := editor_session.entry_access_borrow(go_access)
	rust_access, rust_accessible, _ := editor_session.session_entry_access(&session, rust.entry)
	rust_borrow, rust_borrowed, _ := editor_session.entry_access_borrow(rust_access)
	testing.expect(t, odin_accessible && odin_borrowed && racket_accessible && racket_borrowed && go_accessible && go_borrowed && rust_accessible && rust_borrowed)
	if !odin_borrowed || !racket_borrowed || !go_borrowed || !rust_borrowed do return
	odin_association, odin_recognized, _ := Syntax_Workflow_Entry_Language_Association(
		workflow,
		odin_entry,
	)
	racket_association, racket_recognized, _ := Syntax_Workflow_Entry_Language_Association(
		workflow,
		racket_entry,
	)
	go_association, go_recognized, _ := Syntax_Workflow_Entry_Language_Association(
		workflow,
		go_borrow,
	)
	rust_association, rust_recognized, _ := Syntax_Workflow_Entry_Language_Association(
		workflow,
		rust_borrow,
	)
	odin_buffer_id := syntax_test_buffer_id(t, &session, odin.entry)
	racket_buffer_id := syntax_test_buffer_id(t, &session, racket.entry)
	go_buffer_id := syntax_test_buffer_id(t, &session, go_entry.entry)
	rust_buffer_id := syntax_test_buffer_id(t, &session, rust.entry)
	odin_index, odin_has_parser := Syntax_Workflow_Find_Buffer(workflow, odin_buffer_id)
	racket_index, racket_has_parser := Syntax_Workflow_Find_Buffer(workflow, racket_buffer_id)
	go_index, go_has_parser := Syntax_Workflow_Find_Buffer(workflow, go_buffer_id)
	rust_index, rust_has_parser := Syntax_Workflow_Find_Buffer(workflow, rust_buffer_id)
	testing.expect(t, odin_recognized && racket_recognized && go_recognized && rust_recognized)
	testing.expect_value(t, odin_association.language.id, language.FACTORY_ODIN_LANGUAGE_ID)
	testing.expect_value(t, racket_association.language.id, language.FACTORY_RACKET_LANGUAGE_ID)
	testing.expect_value(t, go_association.language.id, language.FACTORY_GO_LANGUAGE_ID)
	testing.expect_value(t, rust_association.language.id, language.FACTORY_RUST_LANGUAGE_ID)
	testing.expect(t, odin_has_parser && workflow.entries[odin_index].owner_ready)
	if odin_has_parser {
		testing.expect_value(
			t,
			workflow.entries[odin_index].bundle_identity,
			language.FACTORY_ODIN_BUNDLE_IDENTITY,
		)
	}
	testing.expect(t, racket_has_parser && workflow.entries[racket_index].owner_ready)
	if racket_has_parser {
		testing.expect_value(
			t,
			workflow.entries[racket_index].bundle_identity,
			language.FACTORY_RACKET_BUNDLE_IDENTITY,
		)
	}
	testing.expect(t, go_has_parser && workflow.entries[go_index].owner_ready)
	if go_has_parser {
		testing.expect_value(
			t,
			workflow.entries[go_index].bundle_identity,
			language.FACTORY_GO_BUNDLE_IDENTITY,
		)
	}
	testing.expect(t, rust_has_parser && workflow.entries[rust_index].owner_ready)
	if rust_has_parser {
		testing.expect_value(
			t,
			workflow.entries[rust_index].bundle_identity,
			language.FACTORY_RUST_BUNDLE_IDENTITY,
		)
	}
	maintained, maintenance_failure := Syntax_Workflow_Maintain(workflow, &session, handle)
	testing.expectf(t, maintained, "factory syntax maintenance failed with %v", maintenance_failure.code)
	if maintained {
		testing.expect_value(t, workflow.entries[racket_index].inspection.analysis_status, language.Analysis_Status.Current)
		testing.expect_value(t, workflow.entries[go_index].inspection.analysis_status, language.Analysis_Status.Current)
		testing.expect_value(t, workflow.entries[rust_index].inspection.analysis_status, language.Analysis_Status.Current)
	}
}

/* Verifies only case-sensitive Odin document paths select the factory workflow. */
@(test)
selects_only_case_sensitive_odin_documents :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-syntax-selection-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	odin_path := syntax_test_path(t, directory, "main.odin")
	upper_path := syntax_test_path(t, directory, "main.ODIN")
	defer delete(odin_path)
	defer delete(upper_path)
	testing.expect(t, os.write_entire_file(odin_path, "package main\n") == nil)
	testing.expect(t, os.write_entire_file(upper_path, "package ignored\n") == nil)

	session: editor_session.Session
	handle, session_ok, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(9_001),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
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

	odin, odin_ok, _ := editor_session.session_open_path(
		&session,
		editor_session.Open_Path_Request {
			session = handle,
			path = odin_path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	upper, upper_ok, _ := editor_session.session_open_path(
		&session,
		editor_session.Open_Path_Request {
			session = handle,
			path = upper_path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, odin_ok && upper_ok)
	odin_buffer_id := syntax_test_buffer_id(t, &session, odin.entry)
	upper_buffer_id := syntax_test_buffer_id(t, &session, upper.entry)
	reconciled, reconcile_failure := Syntax_Workflow_Reconcile(workflow, &session, handle)
	_, odin_selected := Syntax_Workflow_Find_Buffer(workflow, odin_buffer_id)
	_, upper_selected := Syntax_Workflow_Find_Buffer(workflow, upper_buffer_id)
	testing.expect(t, reconciled)
	testing.expect_value(t, reconcile_failure.code, editor_session.Failure_Code.None)
	testing.expect_value(t, workflow.live_count, u16(1))
	testing.expect(t, odin_selected && !upper_selected)

	replacement_definition := syntax_factory_provider_definition()
	replacement_definition.name = "test-odin-replacement"
	odin_provider_registry, registry_found := syntax_workflow_provider_registry(
		workflow,
		language.FACTORY_ODIN_LANGUAGE_ID,
	)
	testing.expect(t, registry_found)
	if !registry_found do return
	replacement, registered, _ := language.provider_registry_register_native(
		&odin_provider_registry.registry,
		replacement_definition,
	)
	confirmed, confirmed_ok, _ := language.provider_registry_confirm_native(
		&odin_provider_registry.registry,
		replacement,
	)
	before_replace, _, _ := language.provider_registry_selection(&odin_provider_registry.registry)
	replaced, replaced_ok, _ := language.provider_registry_replace(
		&odin_provider_registry.registry,
		before_replace,
		confirmed,
	)
	_, _ = Syntax_Workflow_Reconcile(workflow, &session, handle)
	testing.expect(t, registered && confirmed_ok && replaced_ok)
	testing.expect_value(t, odin_provider_registry.selection.state, language.Selection_State.Replacement)
	odin_index, replacement_selected := Syntax_Workflow_Find_Buffer(workflow, odin_buffer_id)
	testing.expect(t, replacement_selected && workflow.entries[odin_index].owner_ready)

	restored_after_failure, failed_contained, _ := language.provider_registry_fail_active(
		&odin_provider_registry.registry,
		replaced,
		confirmed,
	)
	_, _ = Syntax_Workflow_Reconcile(workflow, &session, handle)
	testing.expect(t, failed_contained)
	testing.expect_value(t, restored_after_failure.state, language.Selection_State.Restored)
	testing.expect_value(t, odin_provider_registry.selection.state, language.Selection_State.Restored)
	disabled, disabled_ok, _ := language.provider_registry_disable(
		&odin_provider_registry.registry,
		restored_after_failure,
	)
	_, _ = Syntax_Workflow_Reconcile(workflow, &session, handle)
	testing.expect(t, disabled_ok)
	testing.expect(t, !workflow.entries[odin_index].owner_ready)
	testing.expect_value(t, workflow.entries[odin_index].inspection.analysis_status, language.Analysis_Status.Plain_Text)
	restored, restored_ok, _ := language.provider_registry_restore(&odin_provider_registry.registry, disabled)
	_, _ = Syntax_Workflow_Reconcile(workflow, &session, handle)
	testing.expect(t, restored_ok)
	testing.expect_value(t, restored.state, language.Selection_State.Restored)
	testing.expect(t, workflow.entries[odin_index].owner_ready)

	closed, close_failure := Syntax_Workflow_Close(workflow)
	testing.expect(t, closed)
	testing.expect_value(t, close_failure.code, language.Failure_Code.None)
	testing.expect(t, syntax_workflow_test_session_close(&session, handle))
}

/* Verifies simultaneous views share one buffer-owned syntax analysis lifecycle. */
@(test)
syntax_owner_spans_views_and_buffer :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-syntax-lifecycle-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	odin_path := syntax_test_path(t, directory, "shared.odin")
	text_path := syntax_test_path(t, directory, "plain.txt")
	defer delete(odin_path)
	defer delete(text_path)
	testing.expect(t, os.write_entire_file(odin_path, "package shared\n") == nil)
	testing.expect(t, os.write_entire_file(text_path, "plain\n") == nil)

	session: editor_session.Session
	handle, session_ok, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(9_002),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
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

	odin, odin_ok, _ := editor_session.session_open_path(
		&session,
		editor_session.Open_Path_Request {
			session = handle,
			path = odin_path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	text_entry, text_ok, _ := editor_session.session_open_path(
		&session,
		editor_session.Open_Path_Request {
			session = handle,
			path = text_path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, odin_ok && text_ok)
	odin_buffer_id := syntax_test_buffer_id(t, &session, odin.entry)
	_, _ = Syntax_Workflow_Reconcile(workflow, &session, handle)
	index, selected := Syntax_Workflow_Find_Buffer(workflow, odin_buffer_id)
	testing.expect(t, selected)
	testing.expect(t, selected && workflow.entries[index].owner_ready)

	access, access_ok, _ := editor_session.session_entry_access(&session, odin.entry)
	borrow, borrowed, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, access_ok && borrowed)
	additional: editor_view.View_Handle
	additional_ok: bool
	if borrowed {
		additional, additional_ok, _ = editor_view.clone_additional(
			borrow.view_registry,
			borrow.primary_view,
		)
		testing.expect(t, additional_ok)
		_, reconciled_entry, _ := editor_session.entry_access_reconcile(access)
		testing.expect(t, reconciled_entry)
	}
	_, _ = Syntax_Workflow_Reconcile(workflow, &session, handle)
	testing.expect_value(t, workflow.live_count, u16(1))
	if borrowed && additional.view_id != editor_view.View_ID(0) {
		close_access, close_access_ok, _ := editor_session.session_entry_access(&session, odin.entry)
		close_borrow, close_borrowed, _ := editor_session.entry_access_borrow(close_access)
		testing.expect(t, close_access_ok && close_borrowed)
		additional_closed, _ := editor_view.close(close_borrow.view_registry, &additional)
		testing.expect(t, additional_closed)
		_, reconciled_entry, _ := editor_session.entry_access_reconcile(close_access)
		testing.expect(t, reconciled_entry)
	}

	_, activated, _ := editor_session.session_activate(&session, text_entry.entry)
	testing.expect(t, activated)
	_, _ = Syntax_Workflow_Reconcile(workflow, &session, handle)
	testing.expect_value(t, workflow.live_count, u16(1))
	_, closed_buffer, _ := editor_session.session_close_buffer(
		&session,
		editor_session.Close_Buffer_Request {
			entry = odin.entry,
			authority = .Discard_Modified,
		},
	)
	testing.expect(t, closed_buffer)
	_, _ = Syntax_Workflow_Reconcile(workflow, &session, handle)
	testing.expect_value(t, workflow.live_count, u16(0))

	closed, _ := Syntax_Workflow_Close(workflow)
	testing.expect(t, closed)
	testing.expect(t, syntax_workflow_test_session_close(&session, handle))
}

/* Verifies initial refresh and post-commit incremental analysis stay on the exact buffer revision. */
@(test)
syntax_workflow_advances_analysis_on_commit :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-syntax-commit-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	odin_path := syntax_test_path(t, directory, "incremental.odin")
	defer delete(odin_path)
	testing.expect(t, os.write_entire_file(odin_path, "package main\nmain :: proc() {}\n") == nil)

	session: editor_session.Session
	handle, session_ok, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(9_003),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
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
		editor_session.Open_Path_Request {
			session = handle,
			path = odin_path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, opened_ok)
	access, access_ok, _ := editor_session.session_entry_access(&session, opened.entry)
	borrow, borrowed, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, access_ok && borrowed)
	if !opened_ok || !borrowed {
		_, _ = Syntax_Workflow_Close(workflow)
		_ = syntax_workflow_test_session_close(&session, handle)
		return
	}
	stats, stats_ok, _ := editor.buffer_stats(borrow.buffer)
	testing.expect(t, stats_ok)
	_, _ = Syntax_Workflow_Reconcile(workflow, &session, handle)
	index, selected := Syntax_Workflow_Find_Buffer(workflow, stats.buffer_id)
	testing.expect(t, selected)
	entry := &workflow.entries[index]
	refreshed := syntax_workflow_parse_current(
		workflow,
		entry,
		borrow.buffer,
		.Initial,
		language.INITIAL_WORK_BYTES,
	)
	testing.expect(t, refreshed)
	testing.expect_value(t, entry.inspection.confirmed_revision, editor.Revision(0))
	testing.expect_value(t, entry.inspection.analysis_status, language.Analysis_Status.Current)
	owner, source, structural_scope, structural_ready, structural_failure :=
		Syntax_Workflow_Structural_Context(workflow, borrow.buffer)
	testing.expectf(t, structural_ready, "structural context failed with %v", structural_failure.code)
	testing.expect(t, owner == &entry.owner)
	testing.expect(t, source == &entry.source)
	testing.expect_value(t, structural_scope.buffer_id, stats.buffer_id)
	testing.expect_value(t, structural_scope.source_revision, editor.Revision(0))
	testing.expect_value(
		t,
		structural_scope.tree_generation,
		entry.inspection.parse_snapshot.tree_generation,
	)
	initial_tree_generation := entry.inspection.parse_snapshot.tree_generation

	edit: transaction.Transaction
	started, begin_failure := transaction.transaction_begin(
		&edit,
		transaction.Transaction_ID(9_003),
		transaction.Undo_Unit_ID(9_003),
		borrow.buffer,
		transaction.Origin{kind = .Built_In, descriptor = "syntax workflow test"},
		"insert-comment",
		transaction.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, started, "transaction begin failed with %v", begin_failure.code)
	if started {
		start, start_ok, _ := transaction.transaction_position(&edit, editor.Byte_Offset(0))
		applied, apply_failure := transaction.transaction_splice(
			&edit,
			editor.Working_Splice{start = start, end = start, replacement = "// edited\n"},
		)
		validated, validation_failure := transaction.transaction_validate(&edit)
		observer_context := Syntax_Commit_Observer_Context {
			workflow = workflow,
			buffer = borrow.buffer,
		}
		result, committed, commit_failure := transaction.transaction_commit(
			&edit,
			Syntax_Workflow_Commit_Observer(&observer_context),
		)
		testing.expect(t, start_ok)
		testing.expectf(t, applied, "transaction splice failed with %v", apply_failure.code)
		testing.expectf(t, validated, "transaction validation failed with %v", validation_failure.code)
		testing.expectf(t, committed, "transaction commit failed with %v", commit_failure.code)
		testing.expect_value(t, result.observer_status, transaction.Observer_Status.Succeeded)
		testing.expect_value(t, entry.inspection.confirmed_revision, editor.Revision(0))
		testing.expect_value(t, entry.inspection.pending.kind, language.Work_Kind.Incremental)
		_, _, _, pending_structural, pending_failure :=
			Syntax_Workflow_Structural_Context(workflow, borrow.buffer)
		testing.expect(t, !pending_structural)
		testing.expect_value(
			t,
			pending_failure.code,
			language.Failure_Code.Structural_Capability_Unavailable,
		)
		maintained, maintenance_failure := Syntax_Workflow_Maintain(workflow, &session, handle)
		testing.expectf(t, maintained, "syntax maintenance failed with %v", maintenance_failure.code)
		testing.expect_value(t, entry.inspection.confirmed_revision, editor.Revision(1))
		testing.expect_value(t, entry.inspection.parse_snapshot.source_revision, editor.Revision(1))
		testing.expect(t, entry.inspection.parse_snapshot.tree_generation > initial_tree_generation)
		testing.expect_value(t, entry.inspection.analysis_status, language.Analysis_Status.Current)
		_, _, refreshed_scope, refreshed_structural, refreshed_failure :=
			Syntax_Workflow_Structural_Context(workflow, borrow.buffer)
		testing.expectf(
			t,
			refreshed_structural,
			"refreshed structural context failed with %v",
			refreshed_failure.code,
		)
		testing.expect_value(t, refreshed_scope.source_revision, editor.Revision(1))
		testing.expect(t, refreshed_scope.tree_generation > initial_tree_generation)

		second: transaction.Transaction
		second_started, _ := transaction.transaction_begin(
			&second,
			transaction.Transaction_ID(9_004),
			transaction.Undo_Unit_ID(9_004),
			borrow.buffer,
			transaction.Origin{kind = .Built_In, descriptor = "syntax failure test"},
			"insert-space",
			transaction.Allocator_Set {
				persistent = context.allocator,
				temporary = context.temp_allocator,
			},
		)
		testing.expect(t, second_started)
		if second_started {
			large_comment, large_comment_error := make([]u8, 9 * 1024 * 1024, context.allocator)
			testing.expect(t, large_comment_error == nil)
			if large_comment_error != nil {
				_, _ = transaction.transaction_close(&second)
			} else {
				defer delete(large_comment)
				pattern := transmute([]u8)string("value :: 1\n")
				cursor := 0
				for cursor < len(large_comment) {
					take := min(len(pattern), len(large_comment) - cursor)
					copy(large_comment[cursor:cursor + take], pattern[:take])
					cursor += take
				}
				second_start, _, _ := transaction.transaction_position(&second, editor.Byte_Offset(0))
				_, _ = transaction.transaction_splice(
					&second,
					editor.Working_Splice {
						start = second_start,
						end = second_start,
						replacement = string(large_comment),
					},
				)
				_, _ = transaction.transaction_validate(&second)
				second_context := Syntax_Commit_Observer_Context {
					workflow = workflow,
					buffer = borrow.buffer,
				}
				_, second_committed, _ := transaction.transaction_commit(
					&second,
					Syntax_Workflow_Commit_Observer(&second_context),
				)
				_, _ = Syntax_Workflow_Maintain(workflow, &session, handle)
				testing.expect(t, second_committed)
				testing.expect_value(t, entry.inspection.analysis_status, language.Analysis_Status.Failed)
				testing.expect_value(t, entry.inspection.latest_failure.code, language.Failure_Code.Work_Limit)
				testing.expect_value(t, entry.inspection.pending.kind, language.Work_Kind.Refresh)
				testing.expect_value(t, entry.inspection.confirmed_revision, editor.Revision(1))
				_, _, _, failed_structural, failed_structural_context :=
					Syntax_Workflow_Structural_Context(workflow, borrow.buffer)
				testing.expect(t, !failed_structural)
				testing.expect_value(
					t,
					failed_structural_context.code,
					language.Failure_Code.Work_Limit,
				)
				_, _ = Syntax_Workflow_Maintain(workflow, &session, handle)
				testing.expect_value(t, entry.inspection.analysis_status, language.Analysis_Status.Current)
				testing.expect_value(t, entry.inspection.confirmed_revision, editor.Revision(2))
				_, _, recovered_scope, recovered_structural, recovered_failure :=
					Syntax_Workflow_Structural_Context(workflow, borrow.buffer)
				testing.expectf(
					t,
					recovered_structural,
					"recovered structural context failed with %v",
					recovered_failure.code,
				)
				testing.expect_value(t, recovered_scope.source_revision, editor.Revision(2))
				_, _ = transaction.transaction_close(&second)
			}
		}
		closed, close_failure := transaction.transaction_close(&edit)
		testing.expectf(t, closed, "transaction close failed with %v", close_failure.code)
	}

	closed, _ := Syntax_Workflow_Close(workflow)
	testing.expect(t, closed)
	testing.expect(t, syntax_workflow_test_session_close(&session, handle))
}

@(private)
syntax_test_path :: proc(t: ^testing.T, directory, name: string) -> string {
	path, path_error := os.join_path({directory, name}, context.allocator)
	testing.expect(t, path_error == nil)
	return path
}

@(private)
syntax_test_buffer_id :: proc(
	t: ^testing.T,
	session: ^editor_session.Session,
	entry: editor_session.Entry_Handle,
) -> editor.Buffer_ID {
	access, access_ok, _ := editor_session.session_entry_access(session, entry)
	borrow, borrowed, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, access_ok && borrowed)
	if !borrowed do return 0
	stats, stats_ok, _ := editor.buffer_stats(borrow.buffer)
	testing.expect(t, stats_ok)
	return stats.buffer_id
}
