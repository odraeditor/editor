// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor_session

import "../project"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:testing"

/* Verifies Dir and Project roots publish in order as one atomic replacement. */
@(test)
roots_publish_checked_projections :: proc(t: ^testing.T) {
	workspace, workspace_error := os.make_directory_temp("", "odra-session-roots-*", context.allocator)
	testing.expect(t, workspace_error == nil)
	if workspace_error != nil {
		return
	}
	defer {
		os.remove_all(workspace)
		delete(workspace)
	}

	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(701), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	dir_result, dir_ok, dir_failure := session_roots_replace(
		&session,
		Root_Replace_Request {
			session = handle,
			roots = []Root_Proposal{{kind = .Dir, path = workspace}},
		},
	)
	testing.expect(t, dir_ok)
	testing.expect_value(t, dir_failure.code, Failure_Code.None)
	testing.expect_value(t, dir_result.root_count, u32(1))
	batch, listed, _ := session_roots(&session, handle)
	testing.expect(t, listed)
	if listed {
		testing.expect_value(t, len(batch.descriptors), 1)
		testing.expect_value(t, batch.descriptors[0].kind, Root_Kind.Dir)
		testing.expect_value(t, batch.descriptors[0].path, workspace)
		testing.expect(t, project.dir_handle_is_valid(batch.descriptors[0].dir))
		testing.expect_value(t, batch.descriptors[0].project, project.Project_Handle{})
		root_batch_close(&batch)
	}
	_, cleared, _ := session_roots_replace(
		&session,
		Root_Replace_Request{session = handle},
	)
	testing.expect(t, cleared)

	project_result, project_ok, _ := session_open_project_directory(
		&session,
		Project_Directory_Open_Request {
			session = handle,
			expected_catalog_generation = 31,
			actual_catalog_generation = 31,
			normalized_path = workspace,
			matching_projects = 1,
			project_id = project.Project_ID(17),
			project_generation = project.Project_Generation(1),
			durable_id = "root-project",
			name = "root-project",
			trust = .Untrusted,
			temporary = false,
		},
	)
	testing.expect(t, project_ok)
	if project_ok {
		published, published_ok, _ := session_roots_replace(
			&session,
			Root_Replace_Request {
				session = handle,
				roots = []Root_Proposal{{kind = .Project, path = workspace, project = project_result.active.handle}},
			},
		)
		testing.expect(t, published_ok)
		testing.expect(t, published.generation != dir_result.generation)
		project_batch, project_listed, _ := session_roots(&session, handle)
		testing.expect(t, project_listed)
		if project_listed {
			testing.expect_value(t, project_batch.descriptors[0].kind, Root_Kind.Project)
			testing.expect_value(t, project_batch.descriptors[0].project, project_result.active.handle)
			testing.expect_value(t, project_batch.descriptors[0].dir, project.Dir_Handle{})
			root_batch_close(&project_batch)
		}
	}
	closed, _ := session_close(&session)
	testing.expect(t, closed)
}

/* Ensures a Dir projection cannot retain Project-only authority. */
@(test)
dir_projection_revokes_backing_project_scope :: proc(t: ^testing.T) {
	workspace, workspace_error := os.make_directory_temp("", "odra-session-dir-scope-*", context.allocator)
	testing.expect(t, workspace_error == nil)
	if workspace_error != nil {
		return
	}
	defer {
		os.remove_all(workspace)
		delete(workspace)
	}
	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(704), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer session_close(&session)
	created, created_ok, _ := session_replace_project(
		&session,
		Project_Update_Request {
			session = handle,
			project_id = project.Project_ID(704),
			name = "Backing Project",
			directories = []project.Directory_Proposal{{path = workspace, trust = .Trusted}},
			temporary = true,
		},
	)
	testing.expect(t, created_ok)
	if !created_ok {
		return
	}
	access, accessible, _ := session_project_registry_access(&session, handle, created.active.handle)
	testing.expect(t, accessible)
	_, roots_ok, _ := session_roots_replace(
		&session,
		Root_Replace_Request {
			session = handle,
			roots = []Root_Proposal{{kind = .Dir, path = workspace}},
		},
	)
	testing.expect(t, roots_ok)
	active, inspected, _ := session_active_project(&session, handle)
	testing.expect(t, inspected)
	testing.expect(t, !active.active)
	_, borrowed, borrow_failure := project_registry_access_borrow(access)
	testing.expect(t, !borrowed)
	testing.expect_value(t, borrow_failure.code, Failure_Code.Project_Scope)
	_, listed, list_failure := session_project_memberships(&session, handle, created.active.handle)
	testing.expect(t, !listed)
	testing.expect_value(t, list_failure.code, Failure_Code.Project_Scope)
	_, classified, classify_failure := session_classify_project_buffers(
		&session,
		handle,
		created.active.handle,
	)
	testing.expect(t, !classified)
	testing.expect_value(t, classify_failure.code, Failure_Code.Project_Scope)
	_, _, scope_ok, scope_failure := session_active_project_buffer_scope(
		&session,
		handle,
		created.active.handle,
	)
	testing.expect(t, !scope_ok)
	testing.expect_value(t, scope_failure.code, Failure_Code.Project_Scope)
	_, replaced, replace_failure := session_replace_project(
		&session,
		Project_Update_Request {
			session = handle,
			expected = created.active.handle,
			project_id = created.active.handle.id,
			name = "Rejected",
			directories = []project.Directory_Proposal{{path = workspace, trust = .Trusted}},
			temporary = true,
		},
	)
	testing.expect(t, !replaced)
	testing.expect_value(t, replace_failure.code, Failure_Code.Project_Scope)
}

/* Ensures invalid, duplicate, and excessive root sets leave publication unchanged. */
@(test)
roots_reject_invalid_sets :: proc(t: ^testing.T) {
	workspace, workspace_error := os.make_directory_temp("", "odra-session-root-limits-*", context.allocator)
	testing.expect(t, workspace_error == nil)
	if workspace_error != nil {
		return
	}
	defer {
		os.remove_all(workspace)
		delete(workspace)
	}
	policy := DEFAULT_POLICY
	policy.session_roots = 2
	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(702), test_session_allocators(), policy)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	_, first_ok, _ := session_roots_replace(
		&session,
		Root_Replace_Request{session = handle, roots = []Root_Proposal{{kind = .Dir, path = workspace}}},
	)
	testing.expect(t, first_ok)
	duplicate := []Root_Proposal{{kind = .Dir, path = workspace}, {kind = .Dir, path = workspace}}
	_, duplicate_ok, duplicate_failure := session_roots_replace(
		&session,
		Root_Replace_Request{session = handle, roots = duplicate},
	)
	testing.expect(t, !duplicate_ok)
	testing.expect_value(t, duplicate_failure.code, Failure_Code.Duplicate_Root)
	over_limit := []Root_Proposal {
		{kind = .Dir, path = workspace},
		{kind = .Dir, path = workspace},
		{kind = .Dir, path = workspace},
	}
	_, limit_ok, limit_failure := session_roots_replace(
		&session,
		Root_Replace_Request{session = handle, roots = over_limit},
	)
	testing.expect(t, !limit_ok)
	testing.expect_value(t, limit_failure.code, Failure_Code.Root_Limit)
	_, invalid_ok, invalid_failure := session_roots_replace(
		&session,
		Root_Replace_Request{session = handle, roots = []Root_Proposal{{kind = .Project, path = workspace}}},
	)
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Project_Failure)
	batch, listed, _ := session_roots(&session, handle)
	testing.expect(t, listed)
	if listed {
		testing.expect_value(t, len(batch.descriptors), 1)
		testing.expect_value(t, batch.descriptors[0].kind, Root_Kind.Dir)
		root_batch_close(&batch)
	}
	closed, _ := session_close(&session)
	testing.expect(t, closed)
}

/* Ensures root teardown releases every session-owned allocation. */
@(test)
session_root_storage_releases_all_tracked_bytes :: proc(t: ^testing.T) {
	workspace, workspace_error := os.make_directory_temp("", "odra-session-root-cleanup-*", context.allocator)
	testing.expect(t, workspace_error == nil)
	if workspace_error != nil {
		return
	}
	defer {
		os.remove_all(workspace)
		delete(workspace)
	}
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	session: Session
	handle, initialized, _ := session_init(
		&session,
		Session_ID(703),
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if initialized {
		_, published, _ := session_roots_replace(
			&session,
			Root_Replace_Request{session = handle, roots = []Root_Proposal{{kind = .Dir, path = workspace}}},
		)
		testing.expect(t, published)
		closed, _ := session_close(&session)
		testing.expect(t, closed)
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies generated Dir replacements preserve complete ordered generations. */
@(test)
test_generated_dir_root_replacements :: proc(t: ^testing.T) {
	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(705), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized {return}
	defer session_close(&session)
	previous_generation := Root_Set_Generation(1)
	for iteration in 0 ..< 128 {
		count := iteration % 9
		storage: [8][128]u8
		proposals: [8]Root_Proposal
		for index in 0 ..< count {
			path := fmt.bprintf(
				storage[index][:],
				"/tmp/odra-generated-root-%03d-%02d",
				iteration,
				index,
			)
			proposals[index] = Root_Proposal{kind = .Dir, path = path}
		}
		published, published_ok, failure := session_roots_replace(
			&session,
			Root_Replace_Request{session = handle, roots = proposals[:count]},
		)
		testing.expectf(t, published_ok, "generated root replacement failed: %v", failure.code)
		if !published_ok {return}
		testing.expect(t, published.generation > previous_generation)
		testing.expect_value(t, published.root_count, u32(count))
		previous_generation = published.generation
		batch, listed, _ := session_roots(&session, handle)
		testing.expect(t, listed)
		if listed {
			testing.expect_value(t, len(batch.descriptors), count)
			for descriptor, index in batch.descriptors {
				testing.expect_value(t, descriptor.kind, Root_Kind.Dir)
				testing.expect_value(t, descriptor.path, proposals[index].path)
			}
			root_batch_close(&batch)
		}
	}
}

/* test_dir_root_replacement_fault_preserves_the_previous_generation. */
@(test)
root_fault_keeps_previous_generation :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	failing := Session_Failing_Allocator{backing = allocator, fail_after = max(u64)}
	session: Session
	handle, initialized, _ := session_init(
		&session,
		Session_ID(706),
		Allocator_Set {
			persistent = session_failing_allocator(&failing),
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if initialized {
		failing.fail_after = failing.successful_allocations
		_, published, failure := session_roots_replace(
			&session,
			Root_Replace_Request {
				session = handle,
				roots = []Root_Proposal{{kind = .Dir, path = "/tmp/odra-faulted-root"}},
			},
		)
		testing.expect(t, !published)
		testing.expect_value(t, failure.code, Failure_Code.Persistent_Memory_Limit)
		failing.fail_after = max(u64)
		batch, listed, _ := session_roots(&session, handle)
		testing.expect(t, listed)
		if listed {
			testing.expect_value(t, len(batch.descriptors), 0)
			root_batch_close(&batch)
		}
		closed, _ := session_close(&session)
		testing.expect(t, closed)
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}
