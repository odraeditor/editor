// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_planning

import "core:mem"
import "core:strings"
import "core:testing"

import "../editor"
import "../language"
import "../transaction"

/* Verifies level, file, Project, Workspace, path, recent, and predicate constraints compose. */
@(test)
refile_candidates_apply_every_constraint :: proc(t: ^testing.T) {
	scope := planning_test_scope()
	resource, resource_ok := resource_identity_copy(7, "notes/projects.jan")
	other, other_ok := resource_identity_copy(7, "notes/archive.jan")
	testing.expect(t, resource_ok && other_ok)
	candidates := []Refile_Target_Candidate{
		{resource = resource, scope = scope, target = planning_test_target(scope), level = 2,
		 project_id = 11, workspace_id = 13, path = "notes/projects.jan", recent_rank = 1,
		 predicate_admitted = true},
		{resource = other, scope = scope, target = planning_test_target(scope), level = 3,
		 project_id = 11, workspace_id = 13, path = "notes/archive.jan", recent_rank = 2,
		 predicate_admitted = true},
	}
	output: [2]Refile_Target_Candidate
	count, filtered, failure := refile_candidates_filter(
		candidates,
		{
			minimum_level = 2,
			maximum_level = 2,
			resource = resource,
			project_id = 11,
			workspace_id = 13,
			path_prefix = "notes/",
			recent_limit = 1,
			require_predicate = true,
		},
		output[:],
	)
	testing.expectf(t, filtered, "candidate filtering failed with %v", failure.code)
	testing.expect_value(t, count, 1)
	testing.expect_value(t, output[0].level, u16(2))
}

/* Verifies same-document move and copy are one checked source transaction. */
@(test)
same_document_refile_moves_and_copies_complete_subtrees :: proc(t: ^testing.T) {
	modes := [2]Refile_Mode{.Move, .Copy}
	for mode in modes {
		source_text := "* Source\nBody\n** Child\n* Destination\n"
		source := transmute([]u8)source_text
		scope := refile_test_scope(301, u64(len(source)))
		owner: language.Jan_Structural_Owner
		initialized, _ := language.jan_structural_owner_init(&owner, scope.analysis.parser_generation)
		testing.expect(t, initialized)
		if !initialized do continue
		analysis, analyzed, analysis_failure := language.jan_structural_owner_analyze(&owner, source, scope.analysis)
		testing.expectf(t, analyzed, "same-document analysis failed with %v", analysis_failure.code)
		if !analyzed {
			language.jan_structural_owner_close(&owner)
			continue
		}
		headings: [4]language.Jan_Node_Record
		heading_count := refile_test_headings(&analysis, headings[:])
		testing.expect_value(t, heading_count, 3)
		if heading_count != 3 {
			language.jan_structural_analysis_close(&analysis)
			language.jan_structural_owner_close(&owner)
			continue
		}
		resource, _ := resource_identity_copy(7, "notes.jan")
		request := Refile_Request{
			operation_id = 51,
			mode = mode,
			source_resource = resource,
			destination_resource = resource,
			source_scope = scope,
			destination_scope = scope,
			source_target = refile_test_target(headings[0]),
			destination_target = refile_test_target(headings[2]),
			destination_level = 1,
			rewrite_generation = 51,
		}
		plan: language.Jan_Rewrite_Plan
		planned, failure := same_document_refile_plan_prepare(&plan, &analysis, source, request)
		testing.expectf(t, planned, "same-document refile failed with %v", failure.code)
		if planned {
			expected := "* Destination\n** Source\nBody\n*** Child\n"
			if mode == .Copy {
				expected = "* Source\nBody\n** Child\n* Destination\n** Source\nBody\n*** Child\n"
			}
			testing.expect(t, refile_test_commit_one(&plan, scope, source_text, expected))
			language.jan_rewrite_plan_close(&plan)
		}
		language.jan_structural_analysis_close(&analysis)
		language.jan_structural_owner_close(&owner)
	}
}

/* Verifies open-buffer cross-document moves publish atomically and reject stale revisions. */
@(test)
cross_document_refile_is_atomic_and_revision_checked :: proc(t: ^testing.T) {
	source_text := "* Source\nBody\n"
	destination_text := "* Destination\n"
	source_bytes := transmute([]u8)source_text
	destination_bytes := transmute([]u8)destination_text
	source_scope := refile_test_scope(311, u64(len(source_bytes)))
	destination_scope := refile_test_scope(312, u64(len(destination_bytes)))
	source_owner, destination_owner: language.Jan_Structural_Owner
	source_owner_ok, _ := language.jan_structural_owner_init(&source_owner, source_scope.analysis.parser_generation)
	destination_owner_ok, _ := language.jan_structural_owner_init(&destination_owner, destination_scope.analysis.parser_generation)
	testing.expect(t, source_owner_ok && destination_owner_ok)
	if !source_owner_ok || !destination_owner_ok do return
	defer language.jan_structural_owner_close(&source_owner)
	defer language.jan_structural_owner_close(&destination_owner)
	source_analysis, source_ok, _ := language.jan_structural_owner_analyze(&source_owner, source_bytes, source_scope.analysis)
	destination_analysis, destination_ok, _ := language.jan_structural_owner_analyze(&destination_owner, destination_bytes, destination_scope.analysis)
	testing.expect(t, source_ok && destination_ok)
	if !source_ok || !destination_ok do return
	defer language.jan_structural_analysis_close(&source_analysis)
	defer language.jan_structural_analysis_close(&destination_analysis)
	source_heading, source_found := refile_test_first_heading(&source_analysis)
	destination_heading, destination_found := refile_test_first_heading(&destination_analysis)
	testing.expect(t, source_found && destination_found)
	if !source_found || !destination_found do return
	source_resource, _ := resource_identity_copy(7, "source.jan")
	destination_resource, _ := resource_identity_copy(7, "destination.jan")
	request := Refile_Request{
		operation_id = 52,
		mode = .Move,
		source_resource = source_resource,
		destination_resource = destination_resource,
		source_scope = source_scope,
		destination_scope = destination_scope,
		source_target = refile_test_target(source_heading),
		destination_target = refile_test_target(destination_heading),
		destination_level = 1,
		rewrite_generation = 52,
	}
	plan: Cross_Document_Refile_Plan
	planned, failure := cross_document_refile_plan_prepare(
		&plan,
		&source_analysis,
		&destination_analysis,
		source_bytes,
		destination_bytes,
		request,
	)
	testing.expectf(t, planned, "cross-document plan failed with %v", failure.code)
	if !planned do return
	defer cross_document_refile_plan_close(&plan)
	testing.expect(t, refile_test_commit_two(
		&plan,
		source_scope,
		destination_scope,
		source_text,
		destination_text,
		"",
		"* Destination\n** Source\nBody\n",
		false,
	))
	testing.expect(t, !refile_test_commit_two(
		&plan,
		source_scope,
		destination_scope,
		source_text,
		destination_text,
		"",
		"",
		true,
	))
	copy_request := request
	copy_request.operation_id = 56
	copy_request.mode = .Copy
	copy_plan: Cross_Document_Refile_Plan
	planned, failure = cross_document_refile_plan_prepare(
		&copy_plan,
		&source_analysis,
		&destination_analysis,
		source_bytes,
		destination_bytes,
		copy_request,
	)
	testing.expectf(t, planned, "cross-document copy plan failed with %v", failure.code)
	if planned {
		testing.expect(t, refile_test_commit_two(
			&copy_plan,
			source_scope,
			destination_scope,
			source_text,
			destination_text,
			source_text,
			"* Destination\n** Source\nBody\n",
			false,
		))
		cross_document_refile_plan_close(&copy_plan)
	}
}

/* Verifies recoverable publication never hides a committed duplicate or invents completion. */
@(test)
refile_publication_preserves_exact_recovery_state :: proc(t: ^testing.T) {
	source_resource, _ := resource_identity_copy(7, "source.jan")
	destination_resource, _ := resource_identity_copy(7, "archive.jan")
	descriptor := Cross_Document_Refile_Descriptor{
		operation_id = 53,
		mode = .Move,
		source_resource = source_resource,
		destination_resource = destination_resource,
		source_scope = refile_test_scope(321, 32),
		destination_scope = refile_test_scope(322, 32),
		payload_fingerprint = 99,
		payload_bytes = 32,
		source_mutation = true,
		destination_mutation = true,
	}
	record, prepared := refile_publication_prepare(descriptor)
	testing.expect(t, prepared)
	advanced: bool
	failure: Failure
	record, advanced, failure = refile_publication_advance(record, .Destination_Commit)
	testing.expectf(t, advanced, "destination publication failed with %v", failure.code)
	testing.expect_value(t, record.state, Refile_Publication_State.Destination_Committed)
	record, advanced, failure = refile_publication_advance(record, .Source_Fail)
	testing.expect(t, advanced)
	testing.expect_value(t, record.state, Refile_Publication_State.Recovery_Required)
	testing.expect_value(t, failure.code, Failure_Code.Recovery_Required)
	testing.expect_value(t, failure.committed, u32(1))
	record, advanced, failure = refile_publication_advance(record, .Rollback_Destination)
	testing.expectf(t, advanced, "rollback failed with %v", failure.code)
	testing.expect_value(t, record.state, Refile_Publication_State.Rolled_Back)
	testing.expect(t, !record.destination_committed && !record.source_removed)

	copy_descriptor := descriptor
	copy_descriptor.operation_id = 54
	copy_descriptor.mode = .Copy
	copy_record, _ := refile_publication_prepare(copy_descriptor)
	copy_record, advanced, _ = refile_publication_advance(copy_record, .Destination_Commit)
	testing.expect(t, advanced)
	testing.expect_value(t, copy_record.state, Refile_Publication_State.Completed)
}

/* Verifies internal archive tags, source metadata, visibility, and allocation containment. */
@(test)
archive_workflows_remain_inspectable_and_no_loss :: proc(t: ^testing.T) {
	source_text := "* TODO Finished\nBody\n"
	source := transmute([]u8)source_text
	scope := refile_test_scope(331, u64(len(source)))
	owner: language.Jan_Structural_Owner
	initialized, _ := language.jan_structural_owner_init(&owner, scope.analysis.parser_generation)
	testing.expect(t, initialized)
	if !initialized do return
	defer language.jan_structural_owner_close(&owner)
	analysis, analyzed, _ := language.jan_structural_owner_analyze(&owner, source, scope.analysis)
	testing.expect(t, analyzed)
	if !analyzed do return
	defer language.jan_structural_analysis_close(&analysis)
	heading, found := refile_test_first_heading(&analysis)
	testing.expect(t, found)
	if !found do return
	request := Internal_Archive_Request{
		operation_id = 55,
		scope = scope,
		target = refile_test_target(heading),
		archived = true,
		rewrite_generation = 55,
	}
	plan: language.Jan_Rewrite_Plan
	planned, failure := internal_archive_plan_prepare(&plan, &analysis, source, request)
	testing.expectf(t, planned, "internal archive plan failed with %v", failure.code)
	if planned {
		testing.expect(t, refile_test_commit_one(
			&plan,
			scope,
			source_text,
			"* TODO Finished :ARCHIVE:\nBody\n",
		))
		language.jan_rewrite_plan_close(&plan)
	}
	resource, _ := resource_identity_copy(7, "notes/projects.jan")
	origin := Archive_Origin{
		resource = resource,
		node_id = heading.id,
		parent_node_id = 1,
		source_revision = scope.analysis.source_revision,
		sibling_index = 3,
	}
	metadata, metadata_ok := archive_origin_metadata_format(origin)
	testing.expect(t, metadata_ok)
	metadata_text := archive_metadata_text(&metadata)
	testing.expect(t, strings.contains(metadata_text, ":JAN_ARCHIVE_SOURCE: notes/projects.jan"))
	visit_resource, visit_ok := archive_origin_resource(origin)
	testing.expect(t, visit_ok && refile_resource_equal(visit_resource, resource))
	archived_payload, payload_ok, _ := archive_payload_add_metadata(source, request.target, origin, context.temp_allocator)
	testing.expect(t, payload_ok)
	archived_target := request.target
	archived_target.range.end = editor.Byte_Offset(len(archived_payload))
	restored_payload, restored_ok, _ := archive_payload_remove_metadata(
		transmute([]u8)archived_payload,
		archived_target,
		origin,
		context.temp_allocator,
	)
	testing.expect(t, restored_ok)
	testing.expect_value(t, restored_payload, source_text)
	testing.expect(t, archive_content_visible(true, true))
	testing.expect(t, !archive_content_visible(true, false))
	combined, combined_changed, combined_ok, _ := internal_archive_rewrite(
		"* Finished :project:\n",
		true,
		context.temp_allocator,
	)
	testing.expect(t, combined_changed && combined_ok)
	testing.expect_value(t, combined, "* Finished :project:ARCHIVE:\n")
	tag_restored, tag_restored_changed, tag_restored_ok, _ := internal_archive_rewrite(
		combined,
		false,
		context.temp_allocator,
	)
	testing.expect(t, tag_restored_changed && tag_restored_ok)
	testing.expect_value(t, tag_restored, "* Finished :project:\n")

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Planning_Test_Failing_Allocator{backing = mem.tracking_allocator(&tracking), fail_after = 0}
	fault_plan: language.Jan_Rewrite_Plan
	planned, failure = internal_archive_plan_prepare(
		&fault_plan,
		&analysis,
		source,
		request,
		planning_test_failing_allocator(&failing),
		planning_test_failing_allocator(&failing),
	)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Failure_Code.Allocation_Failed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

@(private = "file")
refile_test_scope :: proc(buffer_id: editor.Buffer_ID, source_bytes: u64) -> Scope {
	scope := planning_test_scope()
	scope.source_bytes = source_bytes
	scope.analysis.buffer_id = buffer_id
	scope.analysis.source_revision = 0
	scope.analysis.configuration = language.jan_factory_configuration(1).identity
	return scope
}

@(private = "file")
refile_test_target :: proc(node: language.Jan_Node_Record) -> Semantic_Target {
	return {node_id = node.id, kind = node.kind, range = node.range}
}

@(private = "file")
refile_test_first_heading :: proc(analysis: ^language.Jan_Structural_Analysis) -> (language.Jan_Node_Record, bool) {
	for node in language.jan_structural_analysis_nodes(analysis) {
		if node.kind == .Heading do return node, true
	}
	return {}, false
}

@(private = "file")
refile_test_headings :: proc(analysis: ^language.Jan_Structural_Analysis, output: []language.Jan_Node_Record) -> int {
	count := 0
	for node in language.jan_structural_analysis_nodes(analysis) {
		if node.kind != .Heading do continue
		if count >= len(output) do break
		output[count] = node
		count += 1
	}
	return count
}

@(private = "file")
refile_test_commit_one :: proc(
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
		81,
		81,
		"jan-refile",
		transaction.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	if !admitted do return false
	_, committed, _ := transaction.multibuffer_commit(&root)
	transaction.multibuffer_close(&root)
	return committed && refile_test_buffer_equals(&buffer, expected)
}

@(private = "file")
refile_test_commit_two :: proc(
	plan: ^Cross_Document_Refile_Plan,
	source_scope, destination_scope: Scope,
	source_text, destination_text, expected_source, expected_destination: string,
	stale_source: bool,
) -> bool {
	source_buffer, destination_buffer: editor.Buffer
	source_ok, _ := editor.buffer_init(
		&source_buffer,
		source_scope.analysis.buffer_id,
		source_text,
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	destination_ok, _ := editor.buffer_init(
		&destination_buffer,
		destination_scope.analysis.buffer_id,
		destination_text,
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	if !source_ok || !destination_ok do return false
	defer editor.buffer_close(&source_buffer)
	defer editor.buffer_close(&destination_buffer)
	if stale_source {
		start, _, _ := editor.buffer_position(&source_buffer, 0)
		end, _, _ := editor.buffer_position(&source_buffer, 0)
		_, _, _ , _ = editor.buffer_splice(
			&source_buffer,
			{start = start, end = end, replacement = " "},
			context.temp_allocator,
		)
	}
	root: transaction.Multibuffer_Transaction
	admitted, _ := cross_document_refile_admit(
		plan,
		&source_buffer,
		&destination_buffer,
		&root,
		82,
		82,
		transaction.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	if !admitted {
		if transaction.multibuffer_transaction_is_valid(&root) do transaction.multibuffer_close(&root)
		return false
	}
	_, committed, _ := transaction.multibuffer_commit(&root)
	transaction.multibuffer_close(&root)
	return committed && refile_test_buffer_equals(&source_buffer, expected_source) &&
	       refile_test_buffer_equals(&destination_buffer, expected_destination)
}

@(private = "file")
refile_test_buffer_equals :: proc(buffer: ^editor.Buffer, expected: string) -> bool {
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(buffer, &snapshot)
	if !opened do return false
	defer editor.buffer_snapshot_close(&snapshot)
	actual, allocation_error := make([]u8, len(expected), context.temp_allocator)
	if allocation_error != nil do return false
	defer delete(actual, context.temp_allocator)
	copied, read_ok, _ := editor.buffer_snapshot_read(&snapshot, 0, actual)
	return read_ok && copied == u64(len(expected)) && string(actual) == expected
}
