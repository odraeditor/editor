// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor_session

import "../editor"
import "../project"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:testing"

/* Verifies Workspace activation publishes ordered Project roots and scoped registries. */
@(test)
activation_publishes_roots_and_registries :: proc(t: ^testing.T) {
	first, second, available := workspace_test_dirs(t)
	if !available {
		return
	}
	defer workspace_test_dirs_remove(first, second)
	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(801), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	members := workspace_test_members(first, second)
	prepared: Workspace_Activation_Preparation
	prepared_ok, prepare_failure := session_prepare_workspace_activation(
		&session,
		Workspace_Activation_Proposal {
			session = handle,
			expected_root_set = Root_Set_Generation(1),
			id = "wroclaw-work",
			generation = 3,
			name = "Wroclaw Work",
			projects = members[:],
		},
		&prepared,
	)
	testing.expect(t, prepared_ok)
	testing.expect_value(t, prepare_failure.code, Failure_Code.None)
	testing.expect_value(t, prepared.outcome, Workspace_Activation_Outcome.Ready)
	result, admitted, admit_failure := session_admit_workspace_activation(&session, &prepared)
	testing.expect(t, admitted)
	testing.expect_value(t, admit_failure.code, Failure_Code.None)
	if !admitted {
		session_abort_workspace_activation(&prepared)
		session_close(&session)
		return
	}
	testing.expect_value(t, workspace_id_text(&result.workspace.id), "wroclaw-work")
	testing.expect_value(t, workspace_name_text(&result.workspace.name), "Wroclaw Work")
	testing.expect_value(t, result.workspace.generation, u64(3))
	testing.expect_value(t, result.workspace.project_count, u32(2))

	roots, listed, _ := session_roots(&session, handle)
	testing.expect(t, listed)
	if listed {
		testing.expect_value(t, len(roots.descriptors), 2)
		testing.expect_value(t, roots.descriptors[0].path, first)
		testing.expect_value(t, roots.descriptors[1].path, second)
		for root, index in roots.descriptors {
			_, accessible, access_failure := session_project_registry_access(
				&session,
				handle,
				root.project,
			)
			testing.expect(t, accessible)
			testing.expect_value(t, access_failure.code, Failure_Code.None)
			memberships, memberships_ok, _ := session_project_memberships(&session, handle, root.project)
			testing.expect(t, memberships_ok)
			if memberships_ok {
				testing.expect_value(t, len(memberships.descriptors), 1)
				expected_trust := project.Trust_State.Trusted if index == 0 else project.Trust_State.Untrusted
				testing.expect_value(t, memberships.descriptors[0].trust, expected_trust)
				project.descriptor_batch_close(&memberships)
			}
		}
		root_batch_close(&roots)
	}
	snapshot, inspected, _ := session_active_workspace(&session, handle)
	testing.expect(t, inspected && snapshot.active)
	testing.expect_value(t, snapshot.descriptor.root_set, result.roots.generation)
	first_path, first_path_error := os.join_path({first, "first.odin"}, context.allocator)
	second_path, second_path_error := os.join_path({second, "second.odin"}, context.allocator)
	testing.expect(t, first_path_error == nil && second_path_error == nil)
	if first_path_error == nil && second_path_error == nil {
		defer delete(first_path)
		defer delete(second_path)
		testing.expect(t, os.write_entire_file(first_path, "package first\n") == nil)
		testing.expect(t, os.write_entire_file(second_path, "package second\n") == nil)
		second_entry, second_opened, _ := session_open_path(
			&session,
			Open_Path_Request {
				session = handle,
				path = second_path,
				encoding = .UTF8,
				configuration = DEFAULT_ENTRY_CONFIGURATION,
			},
		)
		testing.expect(t, second_opened)
		active, active_ok, _ := session_active_project(&session, handle)
		testing.expect(t, active_ok && active.active)
		if active_ok do testing.expect_value(t, active.descriptor.handle.id, members[1].project_id)
		first_entry, first_opened, _ := session_open_path(
			&session,
			Open_Path_Request {
				session = handle,
				path = first_path,
				encoding = .UTF8,
				configuration = DEFAULT_ENTRY_CONFIGURATION,
			},
		)
		testing.expect(t, first_opened)
		active, active_ok, _ = session_active_project(&session, handle)
		if active_ok do testing.expect_value(t, active.descriptor.handle.id, members[0].project_id)
		_, activated, _ := session_activate(&session, second_entry.entry)
		testing.expect(t, activated)
		active, active_ok, _ = session_active_project(&session, handle)
		if active_ok do testing.expect_value(t, active.descriptor.handle.id, members[1].project_id)
		_, second_closed, _ := session_close_buffer(
			&session,
			Close_Buffer_Request{entry = second_entry.entry},
		)
		_, first_closed, _ := session_close_buffer(
			&session,
			Close_Buffer_Request{entry = first_entry.entry},
		)
		testing.expect(t, second_closed && first_closed)
	}
	closed, close_failure := session_close(&session)
	testing.expect(t, closed)
	testing.expect_value(t, close_failure.code, Failure_Code.None)
}

/* Ensures one-member Workspaces retain the canonical Project shape. */
@(test)
test_workspace_activation_admits_one_project :: proc(t: ^testing.T) {
	first, second, available := workspace_test_dirs(t)
	if !available do return
	defer workspace_test_dirs_remove(first, second)
	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(806), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized do return
	defer session_close(&session)
	members := workspace_test_members(first, second)
	prepared: Workspace_Activation_Preparation
	prepared_ok, _ := session_prepare_workspace_activation(
		&session,
		Workspace_Activation_Proposal {
			session = handle,
			expected_root_set = Root_Set_Generation(1),
			id = "focused-work",
			generation = 1,
			name = "Focused Work",
			projects = members[:1],
		},
		&prepared,
	)
	testing.expect(t, prepared_ok)
	result, admitted, _ := session_admit_workspace_activation(&session, &prepared)
	testing.expect(t, admitted)
	testing.expect_value(t, result.workspace.project_count, u32(1))
	roots, listed, _ := session_roots(&session, handle)
	testing.expect(t, listed)
	if listed {
		defer root_batch_close(&roots)
		testing.expect_value(t, len(roots.descriptors), 1)
		testing.expect_value(t, roots.descriptors[0].path, first)
	}
}

/* Verifies the MRU query selects one exact recent entry without allocation. */
@(test)
recent_entry_selects_mru_without_alloc :: proc(t: ^testing.T) {
	first, second, available := workspace_test_dirs(t)
	if !available do return
	defer workspace_test_dirs_remove(first, second)
	external, external_error := os.make_directory_temp("", "odra-workspace-external-*", context.allocator)
	testing.expect(t, external_error == nil)
	if external_error != nil do return
	defer {
		os.remove_all(external)
		delete(external)
	}
	first_path, first_error := os.join_path({first, "first.odin"}, context.allocator)
	second_path, second_error := os.join_path({second, "second.odin"}, context.allocator)
	external_path, path_error := os.join_path({external, "outside.odin"}, context.allocator)
	testing.expect(t, first_error == nil && second_error == nil && path_error == nil)
	if first_error != nil || second_error != nil || path_error != nil do return
	defer {
		delete(external_path)
		delete(second_path)
		delete(first_path)
	}
	testing.expect(t, os.write_entire_file(first_path, "package first\n") == nil)
	testing.expect(t, os.write_entire_file(second_path, "package second\n") == nil)
	testing.expect(t, os.write_entire_file(external_path, "package outside\n") == nil)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	session: Session
	handle, initialized, _ := session_init(
		&session,
		Session_ID(807),
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	members := workspace_test_members(first, second)
	prepared: Workspace_Activation_Preparation
	prepared_ok, _ := session_prepare_workspace_activation(
		&session,
		Workspace_Activation_Proposal {
			session = handle,
			id = "recent-workspace",
			generation = 1,
			name = "Recent Workspace",
			projects = members[:],
		},
		&prepared,
	)
	testing.expect(t, prepared_ok)
	activation, admitted, _ := session_admit_workspace_activation(&session, &prepared)
	testing.expect(t, admitted)
	if !admitted {
		session_abort_workspace_activation(&prepared)
		session_close(&session)
		mem.tracking_allocator_destroy(&tracking)
		return
	}

	_, empty_found, empty_failure := session_workspace_recent_entry(
		&session,
		handle,
		activation.roots.generation,
	)
	testing.expect(t, !empty_found)
	testing.expect_value(t, empty_failure.code, Failure_Code.None)
	external_entry, external_opened, _ := session_open_path(
		&session,
		Open_Path_Request {
			session = handle,
			path = external_path,
			encoding = .UTF8,
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, external_opened)
	_, external_found, external_failure := session_workspace_recent_entry(
		&session,
		handle,
		activation.roots.generation,
	)
	testing.expect(t, !external_found)
	testing.expect_value(t, external_failure.code, Failure_Code.None)
	first_entry, first_opened, _ := session_open_path(
		&session,
		Open_Path_Request {
			session = handle,
			path = first_path,
			encoding = .UTF8,
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	second_entry, second_opened, _ := session_open_path(
		&session,
		Open_Path_Request {
			session = handle,
			path = second_path,
			encoding = .UTF8,
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, first_opened && second_opened)
	_, external_activated, _ := session_activate(&session, external_entry.entry)
	testing.expect(t, external_activated)
	allocation_before := tracking.current_memory_allocated
	recent, found, recent_failure := session_workspace_recent_entry(
		&session,
		handle,
		activation.roots.generation,
	)
	testing.expect(t, found)
	testing.expect_value(t, recent_failure.code, Failure_Code.None)
	testing.expect_value(t, recent, second_entry.entry)
	testing.expect_value(t, tracking.current_memory_allocated, allocation_before)
	_, first_activated, _ := session_activate(&session, first_entry.entry)
	testing.expect(t, first_activated)
	recent, found, _ = session_workspace_recent_entry(
		&session,
		handle,
		activation.roots.generation,
	)
	testing.expect(t, found)
	testing.expect_value(t, recent, first_entry.entry)

	_, stale_root_found, stale_root_failure := session_workspace_recent_entry(
		&session,
		handle,
		activation.roots.generation + Root_Set_Generation(1),
	)
	testing.expect(t, !stale_root_found)
	testing.expect_value(t, stale_root_failure.code, Failure_Code.Stale_Workspace)
	stale_handle := handle
	stale_handle.generation += Session_Generation(1)
	_, stale_session_found, stale_session_failure := session_workspace_recent_entry(
		&session,
		stale_handle,
		activation.roots.generation,
	)
	testing.expect(t, !stale_session_found)
	testing.expect_value(t, stale_session_failure.code, Failure_Code.Stale_Session)

	entries_to_close := [3]Entry_Handle {
		external_entry.entry,
		first_entry.entry,
		second_entry.entry,
	}
	for entry in entries_to_close {
		_, closed, _ := session_close_buffer(&session, Close_Buffer_Request{entry = entry})
		testing.expect(t, closed)
	}
	closed, close_failure := session_close(&session)
	testing.expect(t, closed)
	testing.expect_value(t, close_failure.code, Failure_Code.None)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Ensures recent-entry lookup never exceeds the configured live-buffer bound. */
@(test)
recent_entry_scans_live_buffer_limit :: proc(t: ^testing.T) {
	first, second, available := workspace_test_dirs(t)
	if !available do return
	defer workspace_test_dirs_remove(first, second)
	path, path_error := os.join_path({first, "oldest.odin"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "package oldest\n") == nil)
	policy := DEFAULT_POLICY
	policy.live_buffers = 16
	policy.live_documents = 16
	policy.inventory_marks = 16
	policy.detach_participants = 16
	session: Session
	handle, initialized, _ := session_init(
		&session,
		Session_ID(808),
		test_session_allocators(),
		policy,
	)
	testing.expect(t, initialized)
	if !initialized do return
	members := workspace_test_members(first, second)
	prepared: Workspace_Activation_Preparation
	prepared_ok, _ := session_prepare_workspace_activation(
		&session,
		Workspace_Activation_Proposal {
			session = handle,
			id = "bounded-workspace",
			generation = 1,
			name = "Bounded Workspace",
			projects = members[:1],
		},
		&prepared,
	)
	testing.expect(t, prepared_ok)
	activation, admitted, _ := session_admit_workspace_activation(&session, &prepared)
	testing.expect(t, admitted)
	owned, opened, _ := session_open_path(
		&session,
		Open_Path_Request {
			session = handle,
			path = path,
			encoding = .UTF8,
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, opened)
	entries: [16]Entry_Handle
	entries[0] = owned.entry
	for index in 1 ..< len(entries) {
		storage: [32]u8
		label := fmt.bprintf(storage[:], "unassociated-%02d", index)
		created, created_ok, _ := session_create_buffer(
			&session,
			Create_Buffer_Request {
				session = handle,
				name = label,
				configuration = DEFAULT_ENTRY_CONFIGURATION,
			},
		)
		testing.expect(t, created_ok)
		if !created_ok do return
		entries[index] = created.entry
	}
	usage, usage_ok, _ := session_usage(&session, handle)
	testing.expect(t, usage_ok)
	testing.expect_value(t, usage.live_buffers, policy.live_buffers)
	recent, found, recent_failure := session_workspace_recent_entry(
		&session,
		handle,
		activation.roots.generation,
	)
	testing.expect(t, found)
	testing.expect_value(t, recent_failure.code, Failure_Code.None)
	testing.expect_value(t, recent, owned.entry)
	for entry in entries {
		_, closed, _ := session_close_buffer(&session, Close_Buffer_Request{entry = entry})
		testing.expect(t, closed)
	}
	closed, _ := session_close(&session)
	testing.expect(t, closed)
}

/* Ensures unavailable members remain visible without mutating Workspace state. */
@(test)
activation_reports_missing_members :: proc(t: ^testing.T) {
	first, second, available := workspace_test_dirs(t)
	if !available {
		return
	}
	defer workspace_test_dirs_remove(first, second)
	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(802), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	members := workspace_test_members(first, second)
	prepared: Workspace_Activation_Preparation
	prepared_ok, _ := session_prepare_workspace_activation(
		&session,
		Workspace_Activation_Proposal {
			session = handle,
			id = "partial-workspace",
			generation = 1,
			name = "Partial Workspace",
			projects = members[:1],
			unavailable_members = 1,
		},
		&prepared,
	)
	testing.expect(t, prepared_ok)
	testing.expect_value(t, prepared.outcome, Workspace_Activation_Outcome.Unavailable_Members)
	testing.expect_value(t, prepared.project_count, u32(2))
	_, admitted, admit_failure := session_admit_workspace_activation(&session, &prepared)
	testing.expect(t, !admitted)
	testing.expect_value(t, admit_failure.code, Failure_Code.Unavailable_Workspace_Members)
	roots, listed, _ := session_roots(&session, handle)
	testing.expect(t, listed)
	if listed {
		testing.expect_value(t, len(roots.descriptors), 0)
		root_batch_close(&roots)
	}
	session_abort_workspace_activation(&prepared)
	closed, _ := session_close(&session)
	testing.expect(t, closed)
}

/* Ensures stale root generations are rejected and temporary state is released. */
@(test)
activation_revalidates_root_generation :: proc(t: ^testing.T) {
	first, second, available := workspace_test_dirs(t)
	if !available {
		return
	}
	defer workspace_test_dirs_remove(first, second)
	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(803), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	members := workspace_test_members(first, second)
	prepared: Workspace_Activation_Preparation
	prepared_ok, _ := session_prepare_workspace_activation(
		&session,
		Workspace_Activation_Proposal {
			session = handle,
			expected_root_set = Root_Set_Generation(1),
			id = "stale-workspace",
			generation = 1,
			name = "Stale Workspace",
			projects = members[:],
		},
		&prepared,
	)
	testing.expect(t, prepared_ok)
	_, replaced, _ := session_roots_replace(&session, Root_Replace_Request{session = handle})
	testing.expect(t, replaced)
	_, admitted, admit_failure := session_admit_workspace_activation(&session, &prepared)
	testing.expect(t, !admitted)
	testing.expect_value(t, admit_failure.code, Failure_Code.Stale_Workspace)
	session_abort_workspace_activation(&prepared)
	closed, _ := session_close(&session)
	testing.expect(t, closed)
}

/* Ensures dirty buffers require resolution before Workspace activation. */
@(test)
activation_requires_dirty_resolution :: proc(t: ^testing.T) {
	first, second, available := workspace_test_dirs(t)
	if !available {
		return
	}
	defer workspace_test_dirs_remove(first, second)
	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(804), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	created, created_ok, _ := session_create_buffer(
		&session,
		Create_Buffer_Request {
			session = handle,
			name = "workspace-draft",
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, created_ok)
	if !created_ok {
		session_close(&session)
		return
	}
	access, access_ok, _ := session_entry_access(&session, created.entry)
	borrow, borrowed, _ := entry_access_borrow(access)
	testing.expect(t, access_ok && borrowed)
	if borrowed {
		position, positioned, _ := editor.buffer_position(borrow.buffer, 0)
		_, _, changed, _ := editor.buffer_splice(
			borrow.buffer,
			editor.Splice{start = position, end = position, replacement = "draft"},
			context.temp_allocator,
		)
		testing.expect(t, positioned && changed)
		_, reconciled, _ := entry_access_reconcile(access)
		testing.expect(t, reconciled)
	}
	members := workspace_test_members(first, second)
	prepared: Workspace_Activation_Preparation
	prepared_ok, _ := session_prepare_workspace_activation(
		&session,
		Workspace_Activation_Proposal {
			session = handle,
			id = "protected-workspace",
			generation = 1,
			name = "Protected Workspace",
			projects = members[:],
		},
		&prepared,
	)
	testing.expect(t, prepared_ok)
	testing.expect_value(t, prepared.outcome, Workspace_Activation_Outcome.Dirty_Protection_Required)
	testing.expect_value(t, prepared.dirty_entries, u32(1))
	_, admitted, admit_failure := session_admit_workspace_activation(&session, &prepared)
	testing.expect(t, !admitted)
	testing.expect_value(t, admit_failure.code, Failure_Code.Dirty_Protection_Required)
	_, closed_buffer, _ := session_close_buffer(
		&session,
		Close_Buffer_Request{entry = created.entry, authority = .Discard_Modified},
	)
	testing.expect(t, closed_buffer)
	_, admitted, admit_failure = session_admit_workspace_activation(&session, &prepared)
	testing.expect(t, admitted)
	testing.expect_value(t, admit_failure.code, Failure_Code.None)
	closed, _ := session_close(&session)
	testing.expect(t, closed)
}

/* Ensures Project focus chooses the most specific overlapping root. */
@(test)
project_focus_prefers_specific_root :: proc(t: ^testing.T) {
	parent, parent_error := os.make_directory_temp("", "odra-workspace-overlap-*", context.allocator)
	testing.expect(t, parent_error == nil)
	if parent_error != nil do return
	defer {
		os.remove_all(parent)
		delete(parent)
	}
	nested, nested_error := os.join_path({parent, "nested"}, context.allocator)
	testing.expect(t, nested_error == nil)
	if nested_error != nil do return
	defer delete(nested)
	testing.expect(t, os.make_directory(nested) == nil)
	path, path_error := os.join_path({nested, "main.odin"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "package nested\n") == nil)

	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(805), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized do return
	members := [2]Workspace_Project_Proposal {
		{
			project_id = project.Project_ID(8_051),
			project_generation = project.Project_Generation(1),
			durable_id = "overlap-parent",
			name = "Overlap Parent",
			root = parent,
			trust = .Untrusted,
		},
		{
			project_id = project.Project_ID(8_052),
			project_generation = project.Project_Generation(1),
			durable_id = "overlap-nested",
			name = "Overlap Nested",
			root = nested,
			trust = .Trusted,
		},
	}
	prepared: Workspace_Activation_Preparation
	prepared_ok, _ := session_prepare_workspace_activation(
		&session,
		Workspace_Activation_Proposal {
			session = handle,
			id = "overlap",
			generation = 1,
			name = "Overlap",
			projects = members[:],
		},
		&prepared,
	)
	testing.expect(t, prepared_ok)
	activation, admitted, _ := session_admit_workspace_activation(&session, &prepared)
	testing.expect(t, admitted)
	opened, opened_ok, _ := session_open_path(
		&session,
		Open_Path_Request {
			session = handle,
			path = path,
			encoding = .UTF8,
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, opened_ok)
	recent, recent_found, recent_failure := session_workspace_recent_entry(
		&session,
		handle,
		activation.roots.generation,
	)
	testing.expect(t, recent_found)
	testing.expect_value(t, recent_failure.code, Failure_Code.None)
	testing.expect_value(t, recent, opened.entry)
	active, active_ok, _ := session_active_project(&session, handle)
	testing.expect(t, active_ok && active.active)
	if active_ok do testing.expect_value(t, active.descriptor.handle.id, members[1].project_id)
	if opened_ok {
		_, closed, _ := session_close_buffer(&session, Close_Buffer_Request{entry = opened.entry})
		testing.expect(t, closed)
	}
	closed, close_failure := session_close(&session)
	testing.expect(t, closed)
	testing.expect_value(t, close_failure.code, Failure_Code.None)
}

@(private)
workspace_test_members :: proc(first, second: string) -> [2]Workspace_Project_Proposal {
	return {
		{
			project_id = project.Project_ID(8_011),
			project_generation = project.Project_Generation(1),
			durable_id = "workspace-first",
			name = "Workspace First",
			root = first,
			trust = .Trusted,
		},
		{
			project_id = project.Project_ID(8_012),
			project_generation = project.Project_Generation(2),
			durable_id = "workspace-second",
			name = "Workspace Second",
			root = second,
			trust = .Untrusted,
		},
	}
}

@(private)
workspace_test_dirs :: proc(t: ^testing.T) -> (string, string, bool) {
	first, first_error := os.make_directory_temp("", "odra-workspace-first-*", context.allocator)
	testing.expect(t, first_error == nil)
	if first_error != nil {
		return "", "", false
	}
	second, second_error := os.make_directory_temp("", "odra-workspace-second-*", context.allocator)
	testing.expect(t, second_error == nil)
	if second_error != nil {
		os.remove_all(first)
		delete(first)
		return "", "", false
	}
	return first, second, true
}

@(private)
workspace_test_dirs_remove :: proc(first, second: string) {
	os.remove_all(first)
	os.remove_all(second)
	delete(first)
	delete(second)
}
