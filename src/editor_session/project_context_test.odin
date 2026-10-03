// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor_session

import "../project"
import "core:mem"
import "core:os"
import "core:testing"

/* Verifies active Project replacement publishes through checked generations. */
@(test)
session_replaces_project_by_generation :: proc(t: ^testing.T) {
	session: Session
	handle, initialized, init_failure := session_init(
		&session,
		Session_ID(501),
		test_session_allocators(),
	)
	testing.expect(t, initialized)
	testing.expect_value(t, init_failure.code, Failure_Code.None)
	if !initialized {
		return
	}

	empty, inspected, inspect_failure := session_active_project(&session, handle)
	testing.expect(t, inspected)
	testing.expect_value(t, inspect_failure.code, Failure_Code.None)
	testing.expect(t, !empty.active)
	testing.expect_value(t, empty.usage.projects, u32(0))

	directories := [2]project.Directory_Proposal {
		{path = "/tmp/odra-session-project", trust = .Untrusted},
		{path = "/tmp/odra-session-project/nested", trust = .Trusted},
	}
	created, created_ok, create_failure := session_replace_project(
		&session,
		Project_Update_Request {
			session = handle,
			project_id = project.Project_ID(71),
			name = "Temporary Project",
			directories = directories[:],
			temporary = true,
		},
	)
	testing.expect(t, created_ok)
	testing.expect_value(t, create_failure.code, Failure_Code.None)
	if !created_ok {
		session_close(&session)
		return
	}
	testing.expect(t, created.previous == (project.Project_Handle{}))
	testing.expect_value(t, created.active.handle.generation, project.Project_Generation(1))
	testing.expect_value(t, created.active.directory_count, u32(2))
	testing.expect(t, created.active.temporary)
	testing.expect_value(t, project.project_name_text(&created.active.name), "Temporary Project")
	registry_access, registry_access_ok, registry_access_failure := session_project_registry_access(
		&session,
		handle,
		created.active.handle,
	)
	testing.expect(t, registry_access_ok)
	testing.expect_value(t, registry_access_failure.code, Failure_Code.None)
	registry, borrowed, borrow_failure := project_registry_access_borrow(registry_access)
	testing.expect(t, borrowed)
	testing.expect_value(t, borrow_failure.code, Failure_Code.None)
	if borrowed {
		usage, usage_ok := project.registry_usage(registry)
		testing.expect(t, usage_ok)
		testing.expect_value(t, usage.projects, u32(1))
	}

	batch, listed, list_failure := session_project_memberships(
		&session,
		handle,
		created.active.handle,
	)
	testing.expect(t, listed)
	testing.expect_value(t, list_failure.code, Failure_Code.None)
	if listed {
		testing.expect_value(t, len(batch.descriptors), 2)
		testing.expect_value(
			t,
			project.directory_path_text(&batch.descriptors[1].path),
			"/tmp/odra-session-project/nested",
		)
		project.descriptor_batch_close(&batch)
	}

	_, stale_ok, stale_failure := session_replace_project(
		&session,
		Project_Update_Request {
			session = handle,
			project_id = project.Project_ID(71),
			name = "Rejected",
			directories = directories[:1],
			temporary = true,
		},
	)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Project_Failure)
	testing.expect_value(t, stale_failure.project_failure.code, project.Failure_Code.Stale_Project)

	replacement_directories := [1]project.Directory_Proposal {
		{path = "/tmp/odra-session-project/nested", trust = .Trusted},
	}
	replaced, replaced_ok, replace_failure := session_replace_project(
		&session,
		Project_Update_Request {
			session = handle,
			expected = created.active.handle,
			project_id = project.Project_ID(71),
			name = "Temporary Project",
			directories = replacement_directories[:],
			temporary = true,
		},
	)
	testing.expect(t, replaced_ok)
	testing.expect_value(t, replace_failure.code, Failure_Code.None)
	if replaced_ok {
		testing.expect_value(t, replaced.previous, created.active.handle)
		testing.expect_value(t, replaced.active.handle.generation, project.Project_Generation(2))
		testing.expect_value(t, replaced.active.directory_count, u32(1))
	}
	_, old_borrowed, old_borrow_failure := project_registry_access_borrow(registry_access)
	testing.expect(t, !old_borrowed)
	testing.expect_value(t, old_borrow_failure.code, Failure_Code.Project_Failure)
	testing.expect_value(t, old_borrow_failure.project_failure.code, project.Failure_Code.Stale_Project)

	stale_batch, old_listed, old_list_failure := session_project_memberships(
		&session,
		handle,
		created.active.handle,
	)
	_ = stale_batch
	testing.expect(t, !old_listed)
	testing.expect_value(t, old_list_failure.code, Failure_Code.Project_Failure)
	testing.expect_value(t, old_list_failure.project_failure.code, project.Failure_Code.Stale_Project)

	closed, close_failure := session_close(&session)
	testing.expect(t, closed)
	testing.expect_value(t, close_failure.code, Failure_Code.None)
}

/* Ensures Project replacement does not take ownership of live buffers. */
@(test)
project_replacement_keeps_live_buffer_ownership :: proc(t: ^testing.T) {
	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(502), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	resources, resources_ok := test_resources_init(t, 502, "owned by the buffer graph")
	if !resources_ok {
		session_close(&session)
		return
	}
	entry, published := test_publish_resources(t, &session, handle, "retained", &resources)
	if !published {
		test_resources_close(&resources)
		session_close(&session)
		return
	}
	usage_before, usage_before_ok, _ := session_usage(&session, handle)
	testing.expect(t, usage_before_ok)

	directories := [1]project.Directory_Proposal {
		{path = "/tmp/odra-session-ownership", trust = .Untrusted},
	}
	_, updated, update_failure := session_replace_project(
		&session,
		Project_Update_Request {
			session = handle,
			project_id = project.Project_ID(72),
			name = "Ownership",
			directories = directories[:],
			temporary = true,
		},
	)
	testing.expect(t, updated)
	testing.expect_value(t, update_failure.code, Failure_Code.None)
	usage_after, usage_after_ok, _ := session_usage(&session, handle)
	testing.expect(t, usage_after_ok)
	testing.expect_value(t, usage_after.live_buffers, usage_before.live_buffers)
	testing.expect_value(t, usage_after.live_documents, usage_before.live_documents)
	testing.expect_value(t, usage_after.canonical_text_bytes, usage_before.canonical_text_bytes)
	_, accessible, access_failure := session_entry_access(&session, entry)
	testing.expect(t, accessible)
	testing.expect_value(t, access_failure.code, Failure_Code.None)

	test_detach_release(t, &session, entry)
	closed, _ := session_close(&session)
	testing.expect(t, closed)
}
/* Ensures active Project teardown releases session-owned storage. */
@(test)
project_teardown_releases_session_bytes :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	session: Session
	handle, initialized, _ := session_init(
		&session,
		Session_ID(503),
		Allocator_Set {persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	directories := [2]project.Directory_Proposal {
		{path = "/tmp/odra-session-cleanup/one", trust = .Untrusted},
		{path = "/tmp/odra-session-cleanup/two", trust = .Untrusted},
	}
	_, updated, _ := session_replace_project(
		&session,
		Project_Update_Request {
			session = handle,
			project_id = project.Project_ID(73),
			name = "Cleanup",
			directories = directories[:],
			temporary = true,
		},
	)
	testing.expect(t, updated)
	closed, close_failure := session_close(&session)
	testing.expect(t, closed)
	testing.expect_value(t, close_failure.code, Failure_Code.None)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Ensures invalid Project policy rolls session initialization back completely. */
@(test)
bad_project_policy_rolls_back_init :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	invalid_policy := project.DEFAULT_POLICY
	invalid_policy.directories = 0
	session: Session
	_, initialized, failure := session_init(
		&session,
		Session_ID(504),
		Allocator_Set {persistent = allocator, temporary = context.temp_allocator},
		DEFAULT_POLICY,
		invalid_policy,
	)
	testing.expect(t, !initialized)
	testing.expect_value(t, failure.code, Failure_Code.Project_Failure)
	testing.expect_value(t, failure.project_failure.code, project.Failure_Code.Policy_Range)
	testing.expect(t, session.state == nil)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies Project paths are copied, overlap is deduplicated, and removal is tracked. */
@(test)
classification_tracks_overlap_and_removal :: proc(
	t: ^testing.T,
) {
	workspace, workspace_error := os.make_directory_temp("", "odra-project-classification-*", context.allocator)
	testing.expect(t, workspace_error == nil)
	if workspace_error != nil {
		return
	}
	defer {
		os.remove_all(workspace)
		delete(workspace)
	}
	owned, owned_error := os.join_path({workspace, "owned"}, context.allocator)
	nested, nested_error := os.join_path({owned, "nested"}, context.allocator)
	external, external_error := os.join_path({workspace, "external"}, context.allocator)
	replacement, replacement_error := os.join_path({workspace, "replacement"}, context.allocator)
	testing.expect(t, owned_error == nil && nested_error == nil && external_error == nil && replacement_error == nil)
	if owned_error != nil || nested_error != nil || external_error != nil || replacement_error != nil {
		return
	}
	defer {
		delete(replacement)
		delete(external)
		delete(nested)
		delete(owned)
	}
	testing.expect(t, os.make_directory(owned) == nil)
	testing.expect(t, os.make_directory(nested) == nil)
	testing.expect(t, os.make_directory(external) == nil)
	testing.expect(t, os.make_directory(replacement) == nil)
	owned_path, owned_path_error := os.join_path({nested, "owned.txt"}, context.allocator)
	external_path, external_path_error := os.join_path({external, "external.txt"}, context.allocator)
	testing.expect(t, owned_path_error == nil && external_path_error == nil)
	if owned_path_error != nil || external_path_error != nil {
		return
	}
	defer {
		delete(external_path)
		delete(owned_path)
	}
	testing.expect(t, os.write_entire_file(owned_path, "owned") == nil)
	testing.expect(t, os.write_entire_file(external_path, "external") == nil)

	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(505), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	owned_result, owned_opened, _ := session_open_path(
		&session,
		Open_Path_Request {
			session = handle,
			path = owned_path,
			encoding = .UTF8,
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	external_result, external_opened, _ := session_open_path(
		&session,
		Open_Path_Request {
			session = handle,
			path = external_path,
			encoding = .UTF8,
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	unassociated_result, unassociated_created, _ := session_create_buffer(
		&session,
		Create_Buffer_Request {
			session = handle,
			name = "notes",
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, owned_opened && external_opened && unassociated_created)
	if !owned_opened || !external_opened || !unassociated_created {
		return
	}

	directories := [2]project.Directory_Proposal {
		{path = owned, trust = .Untrusted},
		{path = nested, trust = .Untrusted},
	}
	created, created_ok, _ := session_replace_project(
		&session,
		Project_Update_Request {
			session = handle,
			project_id = project.Project_ID(74),
			name = "Classification",
			directories = directories[:],
			temporary = true,
		},
	)
	testing.expect(t, created_ok)
	if !created_ok {
		return
	}

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	batch, classified, classify_failure := session_classify_project_buffers(
		&session,
		handle,
		created.active.handle,
		mem.tracking_allocator(&tracking),
	)
	testing.expect(t, classified)
	testing.expect_value(t, classify_failure.code, Failure_Code.None)
	if classified {
		testing.expect_value(t, len(batch.descriptors), 3)
		testing.expect_value(t, len(batch.memberships), 2)
		owned_seen, external_seen, unassociated_seen := false, false, false
		for descriptor in batch.descriptors {
			switch descriptor.graph.entry {
			case owned_result.entry:
				owned_seen = true
				testing.expect_value(t, descriptor.normalized_path, owned_path)
				testing.expect_value(t, descriptor.scope, Project_Buffer_Scope.Project_Owned)
				testing.expect_value(t, descriptor.membership_count, u32(2))
			case external_result.entry:
				external_seen = true
				testing.expect_value(t, descriptor.normalized_path, external_path)
				testing.expect_value(t, descriptor.scope, Project_Buffer_Scope.External)
				testing.expect_value(t, descriptor.membership_count, u32(0))
			case unassociated_result.entry:
				unassociated_seen = true
				testing.expect_value(t, descriptor.normalized_path, "")
				testing.expect_value(t, descriptor.scope, Project_Buffer_Scope.Unassociated)
			}
		}
		testing.expect(t, owned_seen && external_seen && unassociated_seen)
		testing.expect(t, tracking.current_memory_allocated > 0)
		closed := project_buffer_batch_close(&batch)
		testing.expect(t, closed)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	}
	mem.tracking_allocator_destroy(&tracking)

	replacement_directories := [1]project.Directory_Proposal {
		{path = replacement, trust = .Untrusted},
	}
	replaced, replaced_ok, _ := session_replace_project(
		&session,
		Project_Update_Request {
			session = handle,
			expected = created.active.handle,
			project_id = project.Project_ID(74),
			name = "Classification",
			directories = replacement_directories[:],
			temporary = true,
		},
	)
	testing.expect(t, replaced_ok)
	if replaced_ok {
		_, stale_classified, stale_failure := session_classify_project_buffers(
			&session,
			handle,
			created.active.handle,
		)
		testing.expect(t, !stale_classified)
		testing.expect_value(t, stale_failure.code, Failure_Code.Project_Failure)
		after, after_classified, _ := session_classify_project_buffers(
			&session,
			handle,
			replaced.active.handle,
		)
		testing.expect(t, after_classified)
		if after_classified {
			owned_now_external := false
			for descriptor in after.descriptors {
				if descriptor.graph.entry == owned_result.entry {
					owned_now_external = descriptor.scope == .External &&
					                     descriptor.normalized_path == owned_path
				}
			}
			testing.expect(t, owned_now_external)
			project_buffer_batch_close(&after)
		}
	}

	entries: [3]Entry_Handle
	entry_count, entries_ok, _ := session_mru_entries(&session, handle, entries[:])
	testing.expect(t, entries_ok)
	for index in 0 ..< int(entry_count) {
		test_detach_release(t, &session, entries[index])
	}
	closed, _ := session_close(&session)
	testing.expect(t, closed)
}
