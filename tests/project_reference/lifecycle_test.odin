// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package project_reference

import "core:testing"
import "base:runtime"
import "core:mem"

lifecycle_test_policy :: proc() -> Lifecycle_Policy {
	return Lifecycle_Policy {
		projects = 8,
		workspaces = 4,
		workspace_members = 8,
		promotion_suppressions = 8,
	}
}

/* Ensures plain Dirs promote once and retain independent suppression state. */
@(test)
dirs_promote_and_suppress_independently :: proc(t: ^testing.T) {
	model, ready := lifecycle_model_init(lifecycle_test_policy())
	testing.expect(t, ready)
	defer lifecycle_model_deinit(&model)

	suppressed, suppression_failure := lifecycle_suppress(&model, "/work/plain")
	testing.expect(t, suppressed)
	testing.expect_value(t, suppression_failure.code, Lifecycle_Failure_Code.None)
	testing.expect(t, lifecycle_suppressed(&model, "/work/plain"))
	testing.expect(t, lifecycle_unsuppress(&model, "/work/plain"))

	project, promoted, promotion_failure := lifecycle_promote(
		&model,
		"project-one",
		"Project One",
		"/work/plain",
	)
	testing.expect(t, promoted)
	testing.expect_value(t, promotion_failure.code, Lifecycle_Failure_Code.None)
	descriptor, described := lifecycle_project_descriptor(&model, project)
	testing.expect(t, described)
	testing.expect_value(t, descriptor.root, "/work/plain")
	testing.expect_value(t, descriptor.trust, Trust.Untrusted)

	_, duplicate_ok, duplicate_failure := lifecycle_promote(
		&model,
		"project-two",
		"Project Two",
		"/work/plain",
	)
	testing.expect(t, !duplicate_ok)
	testing.expect_value(t, duplicate_failure.code, Lifecycle_Failure_Code.Duplicate_Project_Root)
	_, suppression_after_project := lifecycle_suppress(&model, "/work/plain")
	testing.expect_value(t, suppression_after_project.code, Lifecycle_Failure_Code.Project_Root)
	testing.expect(t, lifecycle_model_validate(&model))
}

/* Ensures Workspaces admit only distinct, currently registered Projects. */
@(test)
workspaces_require_distinct_live_projects :: proc(t: ^testing.T) {
	model, ready := lifecycle_model_init(lifecycle_test_policy())
	testing.expect(t, ready)
	defer lifecycle_model_deinit(&model)

	first, first_ok, _ := lifecycle_promote(&model, "first", "First", "/work/first")
	second, second_ok, _ := lifecycle_promote(&model, "second", "Second", "/work/second")
	testing.expect(t, first_ok)
	testing.expect(t, second_ok)

	one := [?]Lifecycle_Project_Handle{first}
	one_workspace, one_ok, one_failure := lifecycle_workspace_create(&model, "one", "One", one[:])
	testing.expect(t, one_ok)
	testing.expect_value(t, one_failure.code, Lifecycle_Failure_Code.None)
	one_descriptor, one_described := lifecycle_workspace_descriptor(&model, one_workspace)
	testing.expect(t, one_described)
	testing.expect_value(t, len(one_descriptor.members), 1)

	duplicate := [?]Lifecycle_Project_Handle{first, first}
	_, duplicate_ok, duplicate_failure := lifecycle_workspace_create(
		&model,
		"duplicate",
		"Duplicate",
		duplicate[:],
	)
	testing.expect(t, !duplicate_ok)
	testing.expect_value(t, duplicate_failure.code, Lifecycle_Failure_Code.Duplicate_Workspace_Member)

	members := [?]Lifecycle_Project_Handle{first, second}
	workspace, workspace_ok, _ := lifecycle_workspace_create(
		&model,
		"workspace",
		"Workspace",
		members[:],
	)
	testing.expect(t, workspace_ok)
	descriptor, described := lifecycle_workspace_descriptor(&model, workspace)
	testing.expect(t, described)
	testing.expect_value(t, len(descriptor.members), 2)
	testing.expect_value(t, descriptor.members[0], first)
	testing.expect_value(t, descriptor.members[1], second)
	testing.expect(t, lifecycle_model_validate(&model))
}

/* Ensures migration counts canonical roots and multi-root Workspaces exactly once. */
@(test)
migration_counts_roots_and_workspaces :: proc(t: ^testing.T) {
	first := [?]string{"/work/one"}
	second := [?]string{"/work/one", "/work/two"}
	invalid := [?]string{"relative"}
	sources := [?]Lifecycle_Legacy_Project {
		{valid = true, roots = first[:]},
		{valid = true, roots = second[:]},
		{valid = true, roots = invalid[:]},
		{valid = false},
	}
	summary, planned := lifecycle_plan_migration(sources[:], 8, 4)
	testing.expect(t, planned)
	testing.expect_value(t, summary.source_projects, 4)
	testing.expect_value(t, summary.target_projects, 2)
	testing.expect_value(t, summary.target_workspaces, 1)
	testing.expect_value(t, summary.rejected_sources, 2)

	_, capacity_ok := lifecycle_plan_migration(sources[:], 1, 1)
	testing.expect(t, !capacity_ok)
}

/* Ensures lifecycle allocation faults release every partial Project record. */
@(test)
allocation_faults_release_partial_state :: proc(t: ^testing.T) {
	for fail_after in 0 ..< 3 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Lifecycle_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		model, initialized := lifecycle_model_init(
			lifecycle_test_policy(),
			lifecycle_failing_allocator(&failing),
		)
		testing.expect(t, !initialized)
		lifecycle_model_deinit(&model)
		testing.expect_value(t, tracking.current_memory_allocated, 0)
		mem.tracking_allocator_destroy(&tracking)
	}

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Lifecycle_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = max(u64),
	}
	model, initialized := lifecycle_model_init(
		lifecycle_test_policy(),
		lifecycle_failing_allocator(&failing),
	)
	testing.expect(t, initialized)
	failing.fail_after = failing.successful_allocations + 1
	_, promoted, failure := lifecycle_promote(&model, "faulted", "Faulted", "/faulted")
	testing.expect(t, !promoted)
	testing.expect_value(t, failure.code, Lifecycle_Failure_Code.Allocation)
	testing.expect_value(t, model.project_count, 0)
	failing.fail_after = max(u64)
	lifecycle_model_deinit(&model)
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	mem.tracking_allocator_destroy(&tracking)
}

@(private)
Lifecycle_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
lifecycle_failing_allocator :: proc(data: ^Lifecycle_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = lifecycle_failing_allocator_proc, data = data}
}

@(private)
lifecycle_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location: runtime.Source_Code_Location,
) -> ([]byte, runtime.Allocator_Error) {
	allocator := cast(^Lifecycle_Failing_Allocator)allocator_data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after {
			return nil, .Out_Of_Memory
		}
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
