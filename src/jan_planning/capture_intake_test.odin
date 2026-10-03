// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_planning

import "core:mem"
import "core:testing"

import "../editor"
import "../language"
import "../transaction"

/* Verifies capture expands admitted values, supports preview editing, and finalizes once. */
@(test)
capture_intake_expands_edits_and_finalizes :: proc(t: ^testing.T) {
	source_text := "* Inbox\n"
	source := transmute([]u8)source_text
	scope, analysis, owner, target, ready := capture_intake_test_document(t, 401, source)
	if !ready do return
	defer language.jan_structural_owner_close(&owner)
	defer language.jan_structural_analysis_close(&analysis)
	resource, resource_ok := resource_identity_copy(7, "notes/inbox.org")
	testing.expect(t, resource_ok)
	values := [2]Capture_Value{
		{kind = .Prompt, key = "title", value = "Review capture", admitted = true, sensitive = true},
		{kind = .Selection, key = "selection", value = "Context\n", admitted = true},
	}
	request := Capture_Request{
		operation_id = 61,
		resource = resource,
		scope = scope,
		target = target,
		template = {
			identity = "task",
			key = 't',
			label = "Task",
			entry_kind = .Task,
			source_kind = .Literal,
			source = "** TODO %{title}\n%{selection}%?",
			required_capabilities = {.Prompt, .Selection},
			position = .Cursor,
			applicable = true,
			input_limit = 1_024,
			output_limit = 4_096,
		},
		values = values[:],
		rewrite_generation = 61,
	}
	session: Capture_Session
	descriptor, prepared, failure := capture_session_prepare(&session, request)
	testing.expectf(t, prepared, "capture preparation failed with %v", failure.code)
	if !prepared do return
	defer capture_session_close(&session)
	testing.expect_value(t, descriptor.lifecycle, Capture_Lifecycle.Previewing)
	testing.expect_value(t, descriptor.sensitive_values, u16(1))
	text, text_ok := capture_session_text(&session)
	testing.expect(t, text_ok)
	testing.expect_value(t, text, "** TODO Review capture\nContext\n")
	testing.expect_value(t, descriptor.cursor_byte, u64(len(text)))
	editing: bool
	editing, failure = capture_session_begin_edit(&session)
	testing.expectf(t, editing, "capture edit failed with %v", failure.code)
	replaced: bool
	descriptor, replaced, failure = capture_session_replace_text(&session, "** TODO Edited\n")
	testing.expectf(t, replaced, "capture replacement failed with %v", failure.code)
	testing.expect_value(t, descriptor.lifecycle, Capture_Lifecycle.Editing)
	plan: language.Jan_Rewrite_Plan
	finalized: bool
	descriptor, finalized, failure = capture_session_finalize_prepare(&session, &plan, &analysis, source)
	testing.expectf(t, finalized, "capture finalization failed with %v", failure.code)
	if finalized {
		defer language.jan_rewrite_plan_close(&plan)
		testing.expect_value(t, descriptor.lifecycle, Capture_Lifecycle.Finalized)
		testing.expect(t, capture_intake_test_commit(&plan, scope, source_text, "* Inbox\n** TODO Edited\n"))
	}
	aborted: bool
	_, aborted = capture_session_abort(&session)
	testing.expect(t, !aborted)
}

/* Verifies capture abort, capability admission, generated sources, bounds, and allocation cleanup. */
@(test)
capture_intake_abort_and_faults_leave_no_publication :: proc(t: ^testing.T) {
	scope := planning_test_scope()
	resource, _ := resource_identity_copy(7, "notes/inbox.jan")
	request := capture_intake_test_request(scope, planning_test_target(scope), resource)
	values := [1]Capture_Value{{kind = .Prompt, key = "title", value = "Captured", admitted = true}}
	request.values = values[:]
	request.template.source_kind = .Generator
	request.template.generator_admitted = false
	session: Capture_Session
	_, prepared, failure := capture_session_prepare(&session, request)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Request)
	request.template.generator_admitted = true
	request.values[0].kind = .Clipboard
	_, prepared, failure = capture_session_prepare(&session, request)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Unavailable)
	request.values[0].kind = .Prompt
	descriptor: Capture_Session_Descriptor
	descriptor, prepared, failure = capture_session_prepare(&session, request)
	testing.expectf(t, prepared, "generated capture failed with %v", failure.code)
	if prepared {
		aborted: bool
		descriptor, aborted = capture_session_abort(&session)
		testing.expect(t, aborted)
		testing.expect_value(t, descriptor.lifecycle, Capture_Lifecycle.Aborted)
		_, text_ok := capture_session_text(&session)
		testing.expect(t, !text_ok)
		capture_session_close(&session)
	}

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Planning_Test_Failing_Allocator{backing = mem.tracking_allocator(&tracking), fail_after = 0}
	fault_session: Capture_Session
	_, prepared, failure = capture_session_prepare(
		&fault_session,
		request,
		planning_test_failing_allocator(&failing),
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Allocation_Failed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies attachment effects stay behind public owners and expose exact recovery state. */
@(test)
attachment_intake_requires_public_owners_and_recovers :: proc(t: ^testing.T) {
	scope := planning_test_scope()
	source, _ := resource_identity_copy(7, "incoming/image.png")
	destination, _ := resource_identity_copy(7, "attachments/image.png")
	request := Attachment_Request{
		operation_id = 62,
		action = .Copy,
		directory_source = .Stable_Identifier,
		scope = scope,
		owner = planning_test_target(scope),
		source = source,
		destination = destination,
		provider_admitted = true,
		symlink_supported = true,
		maksym_admitted = true,
		repository_admitted = true,
		expected_bytes = 128,
		attachment_limit = 8,
	}
	plan, planned, failure := attachment_effect_plan_prepare(request)
	testing.expectf(t, planned, "attachment plan failed with %v", failure.code)
	testing.expect(t, plan.resource_effect && plan.resource_mutation && plan.document_link_change)
	record, prepared := attachment_workflow_prepare(plan)
	testing.expect(t, prepared)
	advanced: bool
	record, advanced, failure = attachment_workflow_advance(record, plan, .Resource_Commit)
	testing.expectf(t, advanced, "resource commit failed with %v", failure.code)
	testing.expect_value(t, record.state, Attachment_Workflow_State.Resource_Committed)
	record, advanced, failure = attachment_workflow_advance(record, plan, .Document_Fail)
	testing.expect(t, advanced)
	testing.expect_value(t, record.state, Attachment_Workflow_State.Recovery_Required)
	testing.expect_value(t, failure.code, Failure_Code.Recovery_Required)
	record, advanced, failure = attachment_workflow_advance(record, plan, .Rollback_Resource)
	testing.expectf(t, advanced, "resource rollback failed with %v", failure.code)
	testing.expect_value(t, record.state, Attachment_Workflow_State.Rolled_Back)

	request.repository_recording = true
	repository_plan: Attachment_Effect_Plan
	repository_ok: bool
	repository_plan, repository_ok, failure = attachment_effect_plan_prepare(request)
	testing.expectf(t, repository_ok, "repository attachment plan failed with %v", failure.code)
	repository_record, repository_prepared := attachment_workflow_prepare(repository_plan)
	testing.expect(t, repository_prepared)
	repository_record, advanced, failure = attachment_workflow_advance(repository_record, repository_plan, .Resource_Commit)
	testing.expectf(t, advanced, "repository resource commit failed with %v", failure.code)
	repository_record, advanced, failure = attachment_workflow_advance(repository_record, repository_plan, .Document_Commit)
	testing.expectf(t, advanced, "repository document commit failed with %v", failure.code)
	testing.expect_value(t, repository_record.state, Attachment_Workflow_State.Repository_Pending)
	repository_record, advanced, failure = attachment_workflow_advance(repository_record, repository_plan, .Repository_Fail)
	testing.expect(t, advanced)
	testing.expect_value(t, repository_record.state, Attachment_Workflow_State.Completed)
	testing.expect_value(t, failure.code, Failure_Code.Partial)
	testing.expect_value(t, failure.committed, u32(2))
	request.repository_admitted = false
	_, planned, failure = attachment_effect_plan_prepare(request)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Failure_Code.Unavailable)
	request.repository_recording = false
	request.repository_admitted = true

	request.action = .Open
	request.repository_recording = false
	open_plan, open_ok, _ := attachment_effect_plan_prepare(request)
	testing.expect(t, open_ok && open_plan.resource_effect && !open_plan.resource_mutation)
	open_record, _ := attachment_workflow_prepare(open_plan)
	open_record, advanced, failure = attachment_workflow_advance(open_record, open_plan, .Resource_Commit)
	testing.expectf(t, advanced, "attachment open failed with %v", failure.code)
	testing.expect_value(t, open_record.state, Attachment_Workflow_State.Completed)

	request.action = .Reveal
	request.maksym_admitted = false
	_, planned, failure = attachment_effect_plan_prepare(request)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Failure_Code.Unavailable)
	request.action = .Symbolic_Link
	request.maksym_admitted = true
	request.symlink_supported = false
	_, planned, failure = attachment_effect_plan_prepare(request)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Failure_Code.Unavailable)
	request.action = .Synchronize
	request.symlink_supported = true
	request.provider_admitted = false
	_, planned, failure = attachment_effect_plan_prepare(request)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Failure_Code.Unavailable)
}

/* Verifies attachment links appear only after resources and rename/delete exact references. */
@(test)
attachment_intake_updates_only_confirmed_links :: proc(t: ^testing.T) {
	attachment_intake_test_link_change(t, .Copy, "* Assets\n", "* Assets\n[[attachment:attachments/new.png]]\n")
	attachment_intake_test_link_change(
		t,
		.Rename,
		"* Assets\n[[attachment:attachments/old.png]]\n",
		"* Assets\n[[attachment:attachments/new.png]]\n",
	)
	attachment_intake_test_link_change(
		t,
		.Delete,
		"* Assets\n[[attachment:attachments/old.png]]\n",
		"* Assets\n",
	)
}

/* Verifies RSS and Atom provider results are copied, deduplicated, retained, and capturable. */
@(test)
feed_intake_is_explicit_bounded_and_copied :: proc(t: ^testing.T) {
	request := capture_intake_test_feed_request()
	entries := [4]Feed_Entry_Candidate{
		{identity = "old", title = "Old", link = "https://example.test/old"},
		{identity = "one", title = "One", link = "https://example.test/one", summary = "First", published = 1},
		{identity = "one", title = "Duplicate", link = "https://example.test/duplicate", published = 2},
		{identity = "two", title = "Two", link = "https://example.test/two", summary = "Second", published = 3},
	}
	retained := [1]string{"old"}
	snapshot: Feed_Refresh_Snapshot
	descriptor, prepared, failure := feed_refresh_snapshot_prepare(&snapshot, request, entries[:], retained[:])
	testing.expectf(t, prepared, "feed refresh failed with %v", failure.code)
	if !prepared do return
	defer feed_refresh_snapshot_close(&snapshot)
	testing.expect_value(t, descriptor.entry_count, u32(2))
	testing.expect_value(t, descriptor.duplicate_count, u32(2))
	testing.expect_value(t, descriptor.retained_count, u32(3))
	entry, found := feed_refresh_entry(&snapshot, 0)
	testing.expect(t, found)
	testing.expect_value(t, entry.identity, "one")
	testing.expect_value(t, entry.title, "One")
	values: [3]Capture_Value
	value_count, projected := feed_entry_capture_values(entry, values[:])
	testing.expect(t, projected)
	testing.expect_value(t, value_count, 3)
	testing.expect_value(t, values[1].kind, Capture_Value_Kind.Link)
	testing.expect_value(t, values[1].value, "https://example.test/one")
	identity, identity_ok := feed_refresh_retained_identity(&snapshot, 2)
	testing.expect(t, identity_ok)
	testing.expect_value(t, identity, "old")
	request.entry_limit = 1
	truncated_snapshot: Feed_Refresh_Snapshot
	truncated_descriptor, truncated_ok, truncated_failure := feed_refresh_snapshot_prepare(
		&truncated_snapshot,
		request,
		entries[:],
		retained[:],
	)
	testing.expectf(t, truncated_ok, "truncated feed refresh failed with %v", truncated_failure.code)
	if truncated_ok {
		testing.expect(t, truncated_descriptor.truncated)
		testing.expect_value(t, truncated_descriptor.entry_count, u32(1))
		feed_refresh_snapshot_close(&truncated_snapshot)
	}

	request.reason = .Document_Open
	blocked: Feed_Refresh_Snapshot
	_, prepared, failure = feed_refresh_snapshot_prepare(&blocked, request, entries[:], retained[:])
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Request)
	request.reason = .Scheduled
	request.cancel_requested = true
	_, prepared, failure = feed_refresh_snapshot_prepare(&blocked, request, entries[:], retained[:])
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Cancelled)
}

/* Verifies feed retention conflicts, allocation faults, and close release every owned byte. */
@(test)
feed_intake_faults_and_cleanup_are_contained :: proc(t: ^testing.T) {
	request := capture_intake_test_feed_request()
	entries := [1]Feed_Entry_Candidate{{identity = "one", title = "One", link = "https://example.test/one"}}
	duplicate_retained := [2]string{"old", "old"}
	snapshot: Feed_Refresh_Snapshot
	_, prepared, failure := feed_refresh_snapshot_prepare(&snapshot, request, entries[:], duplicate_retained[:])
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Conflict)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	_, prepared, failure = feed_refresh_snapshot_prepare(&snapshot, request, entries[:], nil, allocator)
	testing.expectf(t, prepared, "tracked feed refresh failed with %v", failure.code)
	if prepared do feed_refresh_snapshot_close(&snapshot)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)

	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Planning_Test_Failing_Allocator{backing = mem.tracking_allocator(&tracking), fail_after = 0}
	_, prepared, failure = feed_refresh_snapshot_prepare(
		&snapshot,
		request,
		entries[:],
		nil,
		planning_test_failing_allocator(&failing),
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Allocation_Failed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

@(private = "file")
capture_intake_test_request :: proc(scope: Scope, target: Semantic_Target, resource: Resource_Identity) -> Capture_Request {
	return {
		operation_id = 63,
		resource = resource,
		scope = scope,
		target = target,
		template = {
			identity = "generated-task",
			key = 'g',
			label = "Generated task",
			entry_kind = .Task,
			source_kind = .Literal,
			source = "* TODO %{title}",
			required_capabilities = {.Prompt},
			position = .End,
			applicable = true,
			input_limit = 1_024,
			output_limit = 4_096,
		},
		rewrite_generation = 63,
	}
}

@(private = "file")
capture_intake_test_feed_request :: proc() -> Feed_Refresh_Request {
	return {
		operation_id = 64,
		source = {
			identity = "news",
			endpoint = "https://example.test/feed.xml",
			format = .Atom,
			credential_reference = "credentials/news",
			retention_limit = 3,
		},
		reason = .Explicit,
		provider_admitted = true,
		entry_limit = 4,
		copied_text_limit = 16_384,
	}
}

@(private = "file")
attachment_intake_test_link_change :: proc(
	t: ^testing.T,
	action: Attachment_Action,
	source_text, expected: string,
) {
	source_bytes := transmute([]u8)source_text
	scope, analysis, owner, target, ready := capture_intake_test_document(t, 402 + editor.Buffer_ID(action), source_bytes)
	if !ready do return
	defer language.jan_structural_owner_close(&owner)
	defer language.jan_structural_analysis_close(&analysis)
	source_resource, _ := resource_identity_copy(7, "attachments/old.png")
	destination_resource, _ := resource_identity_copy(7, "attachments/new.png")
	request := Attachment_Request{
		operation_id = 65 + Operation_ID(action),
		action = action,
		directory_source = .Explicit,
		scope = scope,
		owner = target,
		source = source_resource,
		destination = destination_resource,
		provider_admitted = true,
		symlink_supported = true,
		maksym_admitted = true,
		repository_admitted = true,
		expected_bytes = 128,
		attachment_limit = 8,
	}
	blocked_plan: language.Jan_Rewrite_Plan
	planned, failure := attachment_link_plan_prepare(
		&blocked_plan,
		&analysis,
		source_bytes,
		request,
		false,
		66,
	)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Failure_Code.Confirmation_Required)
	plan: language.Jan_Rewrite_Plan
	planned, failure = attachment_link_plan_prepare(&plan, &analysis, source_bytes, request, true, 66)
	testing.expectf(t, planned, "attachment link plan failed with %v", failure.code)
	if planned {
		defer language.jan_rewrite_plan_close(&plan)
		testing.expect(t, capture_intake_test_commit(&plan, scope, source_text, expected))
	}
}

@(private = "file")
capture_intake_test_document :: proc(
	t: ^testing.T,
	buffer_id: editor.Buffer_ID,
	source: []u8,
) -> (Scope, language.Jan_Structural_Analysis, language.Jan_Structural_Owner, Semantic_Target, bool) {
	scope := planning_test_scope()
	scope.source_bytes = u64(len(source))
	scope.analysis.buffer_id = buffer_id
	scope.analysis.source_revision = 0
	scope.analysis.configuration = language.jan_factory_configuration(1).identity
	owner: language.Jan_Structural_Owner
	initialized, _ := language.jan_structural_owner_init(&owner, scope.analysis.parser_generation)
	testing.expect(t, initialized)
	if !initialized do return scope, {}, owner, {}, false
	analysis, analyzed, failure := language.jan_structural_owner_analyze(&owner, source, scope.analysis)
	testing.expectf(t, analyzed, "capture analysis failed with %v", failure.code)
	if !analyzed {
		language.jan_structural_owner_close(&owner)
		return scope, {}, {}, {}, false
	}
	for node in language.jan_structural_analysis_nodes(&analysis) {
		if node.kind == .Heading do return scope, analysis, owner, {node_id = node.id, kind = node.kind, range = node.range}, true
	}
	language.jan_structural_analysis_close(&analysis)
	language.jan_structural_owner_close(&owner)
	return scope, {}, {}, {}, false
}

@(private = "file")
capture_intake_test_commit :: proc(
	plan: ^language.Jan_Rewrite_Plan,
	scope: Scope,
	source_text, expected: string,
) -> bool {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		scope.analysis.buffer_id,
		source_text,
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	if !initialized do return false
	defer editor.buffer_close(&buffer)
	root: transaction.Multibuffer_Transaction
	admitted, _ := language.jan_rewrite_plan_admit(
		plan,
		&buffer,
		&root,
		83,
		83,
		"jan-capture-intake",
		transaction.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	if !admitted do return false
	_, committed, _ := transaction.multibuffer_commit(&root)
	transaction.multibuffer_close(&root)
	if !committed do return false
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(&buffer, &snapshot)
	if !opened do return false
	defer editor.buffer_snapshot_close(&snapshot)
	actual, allocation_error := make([]u8, len(expected), context.temp_allocator)
	if allocation_error != nil do return false
	defer delete(actual, context.temp_allocator)
	copied, read_ok, _ := editor.buffer_snapshot_read(&snapshot, 0, actual)
	return read_ok && copied == u64(len(expected)) && string(actual) == expected
}
