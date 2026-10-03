// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package project

import "core:fmt"
import "core:mem"
import "core:os"
import "core:testing"

/* Verifies overlap deduplication, deterministic publication, turns, cancellation, and stale rejection. */
@(test)
enumeration_is_bounded_and_generation_bound :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-project-files-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil {
		return
	}
	defer {
		os.remove_all(root)
		delete(root)
	}
	nested, nested_error := os.join_path({root, "nested"}, context.allocator)
	first, first_error := os.join_path({root, "zeta.txt"}, context.allocator)
	second, second_error := os.join_path({nested, "alpha.txt"}, context.allocator)
	hidden_directory, hidden_directory_error := os.join_path({root, ".odra"}, context.allocator)
	hidden_file, hidden_file_error := os.join_path({root, ".notes"}, context.allocator)
	hidden_child, hidden_child_error := os.join_path(
		{hidden_directory, "project.rkt"},
		context.allocator,
	)
	testing.expect(t, nested_error == nil && first_error == nil && second_error == nil &&
		hidden_directory_error == nil && hidden_file_error == nil && hidden_child_error == nil)
	if nested_error != nil || first_error != nil || second_error != nil ||
	   hidden_directory_error != nil || hidden_file_error != nil || hidden_child_error != nil {
		return
	}
	defer {
		delete(hidden_child)
		delete(hidden_file)
		delete(hidden_directory)
		delete(second)
		delete(first)
		delete(nested)
	}
	testing.expect(t, os.make_directory(nested) == nil)
	testing.expect(t, os.make_directory(hidden_directory) == nil)
	testing.expect(t, os.write_entire_file(first, "zeta") == nil)
	testing.expect(t, os.write_entire_file(second, "alpha") == nil)
	testing.expect(t, os.write_entire_file(hidden_file, "notes") == nil)
	testing.expect(t, os.write_entire_file(hidden_child, "#lang racket/base") == nil)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	project := Project_Handle{
		owner = Owner_Handle{id = 901, generation = 1},
		id = 902,
		generation = 1,
	}
	memberships := [2]Membership_Descriptor{
		test_membership_descriptor(project, 1, 0, root),
		test_membership_descriptor(project, 2, 1, nested),
	}
	policy := DEFAULT_POLICY
	policy.entries_per_turn = MIN_ENTRIES_PER_TURN
	enumerator: File_Enumerator
	initialized, initialize_failure := file_enumerator_init(
		&enumerator,
		project,
		memberships[:],
		policy,
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, initialized, "enumerator init failed: %v", initialize_failure.code)
	if initialized {
		result: File_Enumeration_Result
		for !result.complete {
			advanced: bool
			failure: Failure_Context
			result, advanced, failure = file_enumerator_advance(&enumerator, project)
			testing.expectf(t, advanced, "enumeration failed: %v", failure.code)
			if !advanced {
				break
			}
			testing.expect(t, result.processed_entries <= policy.entries_per_turn)
		}
		testing.expect_value(t, result.candidate_count, u32(2))
		batch, copied, copy_failure := file_enumerator_candidates(&enumerator, project)
		testing.expectf(t, copied, "candidate copy failed: %v", copy_failure.code)
		if copied {
			testing.expect_value(t, len(batch.descriptors), 2)
			testing.expect_value(t, batch.descriptors[0].path, second)
			testing.expect_value(t, batch.descriptors[0].membership_count, u32(2))
			testing.expect_value(t, batch.descriptors[1].path, first)
			testing.expect_value(t, batch.descriptors[1].membership_count, u32(1))
			file_candidate_batch_close(&batch)
		}
		stale := project
		stale.generation += 1
		_, stale_ok, stale_failure := file_enumerator_candidates(&enumerator, stale)
		testing.expect(t, !stale_ok)
		testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Project)
		file_enumerator_close(&enumerator)
	}

	cancelled: File_Enumerator
	initialized, _ = file_enumerator_init(
		&cancelled,
		project,
		memberships[:],
		policy,
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if initialized {
		result, advanced, _ := file_enumerator_advance(&cancelled, project, true)
		testing.expect(t, advanced && result.cancelled)
		_, copied, copy_failure := file_enumerator_candidates(&cancelled, project)
		testing.expect(t, !copied)
		testing.expect_value(t, copy_failure.code, Failure_Code.Invariant_Violation)
		file_enumerator_close(&cancelled)
	}
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies Project file overflow is explicit and never publishes a partial candidate batch. */
@(test)
enumeration_overflow_publishes_nothing :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-project-file-overflow-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil {return}
	defer {
		os.remove_all(root)
		delete(root)
	}
	for index in 0..<int(MIN_FILE_CANDIDATES) + 1 {
		name := fmt.aprintf("candidate-%03d.txt", index)
		path, path_error := os.join_path({root, name}, context.allocator)
		testing.expect(t, path_error == nil)
		if path_error == nil {
			testing.expect(t, os.write_entire_file(path, "candidate") == nil)
			delete(path)
		}
		delete(name)
	}

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	project := Project_Handle {
		owner = {id = 911, generation = 1},
		id = 912,
		generation = 1,
	}
	memberships := [1]Membership_Descriptor{test_membership_descriptor(project, 1, 0, root)}
	policy := DEFAULT_POLICY
	policy.file_candidates = MIN_FILE_CANDIDATES
	enumerator: File_Enumerator
	initialized, initialize_failure := file_enumerator_init(
		&enumerator,
		project,
		memberships[:],
		policy,
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, initialized, "enumerator init failed: %v", initialize_failure.code)
	if initialized {
		overflowed := false
		for !overflowed {
			_, advanced, failure := file_enumerator_advance(&enumerator, project)
			if !advanced {
				testing.expect_value(t, failure.code, Failure_Code.File_Candidate_Limit)
				testing.expect_value(t, failure.maximum, u64(MIN_FILE_CANDIDATES))
				testing.expect_value(t, failure.actual, u64(MIN_FILE_CANDIDATES) + 1)
				overflowed = true
			}
		}
		_, published, publication_failure := file_enumerator_candidates(&enumerator, project)
		testing.expect(t, !published)
		testing.expect_value(t, publication_failure.code, Failure_Code.Invariant_Violation)
		file_enumerator_close(&enumerator)
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies ordinary Dirs receive the same bounded deterministic file projection as Projects. */
@(test)
dir_enumeration_matches_candidate_behavior :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-dir-files-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil {return}
	defer {
		os.remove_all(root)
		delete(root)
	}
	nested, nested_error := os.join_path({root, "nested"}, context.allocator)
	first, first_error := os.join_path({root, "zeta.txt"}, context.allocator)
	second, second_error := os.join_path({nested, "alpha.txt"}, context.allocator)
	testing.expect(t, nested_error == nil && first_error == nil && second_error == nil)
	if nested_error != nil || first_error != nil || second_error != nil {return}
	defer {
		delete(second)
		delete(first)
		delete(nested)
	}
	testing.expect(t, os.make_directory(nested) == nil)
	testing.expect(t, os.write_entire_file(first, "zeta") == nil)
	testing.expect(t, os.write_entire_file(second, "alpha") == nil)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	dir := Dir_Handle {
		owner = {id = 921, generation = 1},
		id = 922,
		generation = 1,
	}
	enumerator: File_Enumerator
	initialized, initialize_failure := dir_file_enumerator_init(
		&enumerator,
		dir,
		root,
		DEFAULT_POLICY,
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, initialized, "Dir enumerator init failed: %v", initialize_failure.code)
	if initialized {
		result: File_Enumeration_Result
		for !result.complete {
			advanced: bool
			failure: Failure_Context
			result, advanced, failure = dir_file_enumerator_advance(&enumerator, dir)
			testing.expectf(t, advanced, "Dir enumeration failed: %v", failure.code)
			if !advanced {break}
		}
		testing.expect_value(t, result.dir, dir)
		testing.expect_value(t, result.project, Project_Handle{})
		batch, copied, copy_failure := dir_file_enumerator_candidates(&enumerator, dir)
		testing.expectf(t, copied, "Dir candidate copy failed: %v", copy_failure.code)
		if copied {
			testing.expect_value(t, batch.dir, dir)
			testing.expect_value(t, batch.project, Project_Handle{})
			testing.expect_value(t, len(batch.descriptors), 2)
			testing.expect_value(t, batch.descriptors[0].path, second)
			testing.expect_value(t, batch.descriptors[0].membership_count, u32(1))
			testing.expect_value(t, batch.descriptors[1].path, first)
			file_candidate_batch_close(&batch)
		}
		stale := dir
		stale.generation += 1
		_, stale_ok, stale_failure := dir_file_enumerator_candidates(&enumerator, stale)
		testing.expect(t, !stale_ok)
		testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Dir)
		file_enumerator_close(&enumerator)
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

@(private)
test_membership_descriptor :: proc(
	project: Project_Handle,
	id: Membership_ID,
	slot: u32,
	path: string,
) -> Membership_Descriptor {
	result := Membership_Descriptor{
		handle = Membership_Handle{
			project = project,
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
