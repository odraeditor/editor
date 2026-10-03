// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "../project"
import "core:mem"
import "core:os"
import "core:testing"

/* Verifies Project-file adaptation preserves labels, members, identity, accounting, and cleanup. */
@(test)
preserve_complete_observation_identity :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-project-file-candidates-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil {return}
	defer {
		os.remove_all(root)
		delete(root)
	}
	first_root, first_root_error := os.join_path({root, "first"}, context.allocator)
	second_root, second_root_error := os.join_path({root, "second"}, context.allocator)
	first_source, first_source_error := os.join_path({first_root, "src"}, context.allocator)
	second_source, second_source_error := os.join_path({second_root, "src"}, context.allocator)
	first_path, first_path_error := os.join_path({first_source, "main.odin"}, context.allocator)
	second_path, second_path_error := os.join_path({second_source, "main.odin"}, context.allocator)
	readme_path, readme_path_error := os.join_path({first_root, "README.md"}, context.allocator)
	paths_ok := first_root_error == nil && second_root_error == nil &&
		first_source_error == nil && second_source_error == nil &&
		first_path_error == nil && second_path_error == nil && readme_path_error == nil
	testing.expect(t, paths_ok)
	if !paths_ok {return}
	defer {
		delete(readme_path)
		delete(second_path)
		delete(first_path)
		delete(second_source)
		delete(first_source)
		delete(second_root)
		delete(first_root)
	}
	testing.expect(t, os.make_directory(first_root) == nil)
	testing.expect(t, os.make_directory(second_root) == nil)
	testing.expect(t, os.make_directory(first_source) == nil)
	testing.expect(t, os.make_directory(second_source) == nil)
	testing.expect(t, os.write_entire_file(first_path, "package first") == nil)
	testing.expect(t, os.write_entire_file(second_path, "package second") == nil)
	testing.expect(t, os.write_entire_file(readme_path, "Project") == nil)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	project_handle := project.Project_Handle {
		owner = {id = 701, generation = 3},
		id = 702,
		generation = 4,
	}
	memberships := [2]project.Membership_Descriptor {
		project_file_candidate_test_membership(project_handle, 1, 0, first_root),
		project_file_candidate_test_membership(project_handle, 2, 1, second_root),
	}
	enumerator: project.File_Enumerator
	initialized, initialize_failure := project.file_enumerator_init(
		&enumerator,
		project_handle,
		memberships[:],
		project.DEFAULT_POLICY,
		project.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, initialized, "enumerator init failed with %v", initialize_failure.code)
	if !initialized {return}
	defer project.file_enumerator_close(&enumerator)
	result: project.File_Enumeration_Result
	for !result.complete {
		advanced: bool
		advance_failure: project.Failure_Context
		result, advanced, advance_failure = project.file_enumerator_advance(&enumerator, project_handle)
		testing.expectf(t, advanced, "enumeration failed with %v", advance_failure.code)
		if !advanced {return}
	}
	batch, copied, copy_failure := project.file_enumerator_candidates(&enumerator, project_handle)
	testing.expectf(t, copied, "candidate copy failed with %v", copy_failure.code)
	if !copied {return}
	defer project.file_candidate_batch_close(&batch)
	for fail_after in 0..<u64(5) {
		baseline := tracking.current_memory_allocated
		failing := Resolver_Failing_Allocator {
			backing = allocator,
			fail_after = fail_after,
		}
		faulted, fault_ok, fault_failure := project_file_candidate_source_build(
			&batch,
			memberships[:],
			resolver_failing_allocator(&failing),
		)
		testing.expect(t, !fault_ok)
		testing.expect_value(t, fault_failure.code, Candidate_Failure_Code.Persistent_Memory_Limit)
		if fault_ok {project_file_candidate_source_close(&faulted)}
		testing.expect_value(t, tracking.current_memory_allocated, baseline)
	}

	source, adapted, adapt_failure := project_file_candidate_source_build_generation(
		&batch,
		memberships[:],
		11,
		allocator,
	)
	testing.expectf(t, adapted, "candidate adaptation failed with %v", adapt_failure.code)
	if !adapted {return}
	defer project_file_candidate_source_close(&source)
	testing.expect_value(t, source.definition.kind, Candidate_Source_Kind.Project_Files)
	testing.expect_value(t, source.definition.scope_identity, u64(project_handle.id))
	testing.expect_value(t, source.definition.scope_generation, u64(project_handle.generation))
	testing.expect_value(t, source.definition.source_generation, u64(11))
	testing.expect_value(t, len(source.definition.descriptors), 3)

	session: Candidate_Session
	_, admitted, admission_failure := candidate_session_init(
		&session,
		Candidate_Config {
			session_id = 91,
			limits = DEFAULT_CANDIDATE_LIMITS,
			persistent_allocator = allocator,
			temporary_allocator = context.temp_allocator,
		},
		source.definition,
	)
	testing.expectf(t, admitted, "candidate admission failed with %v", admission_failure.code)
	if !admitted {return}
	view, viewed, view_failure := candidate_session_view(&session)
	testing.expectf(t, viewed, "candidate view failed with %v", view_failure.code)
	if viewed {
		testing.expect_value(t, view.accounting.candidates, u32(3))
		testing.expect(t, view.accounting.label_bytes > 0)
		testing.expect(t, view.accounting.searchable_bytes > 0)
		testing.expect(t, view.accounting.annotation_bytes > 0)
		testing.expect(t, view.accounting.durable_key_bytes > 0)
		ambiguous_count := 0
		readme_count := 0
		for row in view.rows {
			testing.expect_value(t, row.action.kind, Candidate_Action_Kind.Open_Document)
			testing.expect_value(t, row.durable_category, Candidate_Durable_Category.Project_File)
			testing.expect_value(t, row.durable_key[0], u8('/'))
			matched_action := false
			for descriptor in batch.descriptors {
				if descriptor.path == row.durable_key {
					matched_action = project_file_candidate_action_matches(row.action, descriptor)
					stale := descriptor
					stale.generation += 1
					testing.expect(t, !project_file_candidate_action_matches(row.action, stale))
					break
				}
			}
			testing.expect(t, matched_action)
			if row.label == "src/main.odin" {
				ambiguous_count += 1
				testing.expect_value(t, len(row.annotations), 1)
				if len(row.annotations) == 1 {
					testing.expect_value(t, row.annotations[0].kind, Candidate_Annotation_Kind.Project_Member)
					testing.expect(t, row.annotations[0].text == first_root || row.annotations[0].text == second_root)
				}
			} else if row.label == "README.md" {
				readme_count += 1
				testing.expect_value(t, len(row.annotations), 0)
			}
		}
		testing.expect_value(t, ambiguous_count, 2)
		testing.expect_value(t, readme_count, 1)
		selected_identity := view.rows[view.selected_row].identity
		replacement, replacement_ok, replacement_failure := project_file_candidate_source_build_generation(
			&batch,
			memberships[:],
			12,
			allocator,
		)
		testing.expectf(t, replacement_ok, "replacement adaptation failed with %v", replacement_failure.code)
		if replacement_ok {
			_, refreshed, refresh_failure := candidate_session_refresh(
				&session,
				Candidate_Request {
					session_id = view.session_id,
					session_generation = view.session_generation,
				},
				replacement.definition,
			)
			testing.expectf(t, refreshed, "replacement failed with %v", refresh_failure.code)
			if refreshed {
				refreshed_view, refreshed_ok, _ := candidate_session_view(&session)
				testing.expect(t, refreshed_ok)
				testing.expect_value(t, refreshed_view.source_generation, u64(12))
				testing.expect_value(t, refreshed_view.rows[refreshed_view.selected_row].identity, selected_identity)
				remaining, remaining_error := make(
					[]Candidate_Descriptor_Definition,
					len(replacement.descriptors) - 1,
					context.temp_allocator,
				)
				testing.expect(t, remaining_error == nil)
				if remaining_error == nil {
					remaining_count := 0
					for descriptor in replacement.descriptors {
						if descriptor.identity == selected_identity {continue}
						remaining[remaining_count] = descriptor
						remaining_count += 1
					}
					testing.expect_value(t, remaining_count, len(remaining))
					disappeared := replacement.definition
					disappeared.source_generation = 13
					disappeared.descriptors = remaining
					_, disappeared_ok, disappeared_failure := candidate_session_refresh(
						&session,
						Candidate_Request {
							session_id = refreshed_view.session_id,
							session_generation = refreshed_view.session_generation,
						},
						disappeared,
					)
					testing.expectf(t, disappeared_ok, "disappearance refresh failed with %v", disappeared_failure.code)
					if disappeared_ok {
						disappeared_view, _, _ := candidate_session_view(&session)
						testing.expect_value(t, len(disappeared_view.rows), 2)
						testing.expect(t, disappeared_view.rows[disappeared_view.selected_row].identity != selected_identity)
					}
					delete(remaining, context.temp_allocator)
				}
			}
			project_file_candidate_source_close(&replacement)
		}
	}
	current_view, current_ok, _ := candidate_session_view(&session)
	testing.expect(t, current_ok)
	if current_ok {
		_, cancelled, cancel_failure := candidate_session_cancel(
			&session,
			Candidate_Request {
				session_id = current_view.session_id,
				session_generation = current_view.session_generation,
			},
		)
		testing.expectf(t, cancelled, "candidate cancellation failed with %v", cancel_failure.code)
	}
	_, closed, close_failure := candidate_session_close(&session)
	testing.expectf(t, closed, "candidate close failed with %v", close_failure.code)
	project_file_candidate_source_close(&source)
	project.file_candidate_batch_close(&batch)
	project.file_enumerator_close(&enumerator)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies ordinary-Dir files use the same candidate session and exact action identity. */
@(test)
file_candidates_preserve_labels_and_identity :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-dir-candidates-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil {return}
	defer {
		os.remove_all(root)
		delete(root)
	}
	nested, nested_error := os.join_path({root, "src"}, context.allocator)
	path, path_error := os.join_path({nested, "main.odin"}, context.allocator)
	testing.expect(t, nested_error == nil && path_error == nil)
	if nested_error != nil || path_error != nil {return}
	defer {
		delete(path)
		delete(nested)
	}
	testing.expect(t, os.make_directory(nested) == nil)
	testing.expect(t, os.write_entire_file(path, "package main") == nil)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	dir := project.Dir_Handle {
		owner = {id = 711, generation = 3},
		id = 712,
		generation = 4,
	}
	enumerator: project.File_Enumerator
	initialized, _ := project.dir_file_enumerator_init(
		&enumerator,
		dir,
		root,
		project.DEFAULT_POLICY,
		project.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized {return}
	result: project.File_Enumeration_Result
	for !result.complete {
		advanced: bool
		result, advanced, _ = project.dir_file_enumerator_advance(&enumerator, dir)
		if !advanced {break}
	}
	batch, copied, _ := project.dir_file_enumerator_candidates(&enumerator, dir)
	testing.expect(t, copied)
	if copied {
		source, adapted, adapt_failure := dir_file_candidate_source_build(&batch, root, allocator)
		testing.expectf(t, adapted, "Dir candidate adaptation failed: %v", adapt_failure.code)
		if adapted {
			testing.expect_value(t, source.definition.kind, Candidate_Source_Kind.Dir_Files)
			testing.expect_value(t, source.definition.scope_identity, u64(dir.id))
			testing.expect_value(t, source.definition.scope_generation, u64(dir.generation))
			testing.expect_value(t, len(source.definition.descriptors), 1)
			if len(source.definition.descriptors) == 1 {
				descriptor := source.definition.descriptors[0]
				testing.expect_value(t, descriptor.label, "src/main.odin")
				testing.expect(t, dir_file_candidate_action_matches(descriptor.action, batch.descriptors[0]))
				stale := batch.descriptors[0]
				stale.dir.generation += 1
				testing.expect(t, !dir_file_candidate_action_matches(descriptor.action, stale))
			}
			project_file_candidate_source_close(&source)
		}
		project.file_candidate_batch_close(&batch)
	}
	project.file_enumerator_close(&enumerator)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(private)
project_file_candidate_test_membership :: proc(
	project_handle: project.Project_Handle,
	id: project.Membership_ID,
	slot: u32,
	path: string,
) -> project.Membership_Descriptor {
	result := project.Membership_Descriptor {
		handle = {
			project = project_handle,
			id = id,
			slot = slot,
			generation = 1,
		},
		trust = .Untrusted,
		availability = .Available,
	}
	result.path.length = u32(len(path))
	copy(result.path.bytes[:], path)
	return result
}
