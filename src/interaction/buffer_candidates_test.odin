// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "../editor"
import "../editor_session"
import "../project"
import "core:mem"
import "core:os"
import "core:testing"

/* Verifies buffer adapters preserve exact rows, synthetic creation, Project scope, bounds, and teardown. */
@(test)
buffer_candidates_preserve_source_evidence :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-candidate-buffers-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {return}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	owned_directory, owned_directory_error := os.join_path({directory, "owned"}, context.allocator)
	external_directory, external_directory_error := os.join_path({directory, "external"}, context.allocator)
	testing.expect(t, owned_directory_error == nil && external_directory_error == nil)
	if owned_directory_error != nil || external_directory_error != nil {return}
	defer delete(owned_directory)
	defer delete(external_directory)
	testing.expect(t, os.make_directory(owned_directory) == nil)
	testing.expect(t, os.make_directory(external_directory) == nil)
	owned_path, owned_path_error := os.join_path({owned_directory, "owned.txt"}, context.allocator)
	external_path, external_path_error := os.join_path({external_directory, "external.txt"}, context.allocator)
	testing.expect(t, owned_path_error == nil && external_path_error == nil)
	if owned_path_error != nil || external_path_error != nil {return}
	defer delete(owned_path)
	defer delete(external_path)
	testing.expect(t, os.write_entire_file(owned_path, "owned") == nil)
	testing.expect(t, os.write_entire_file(external_path, "external") == nil)

	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(901),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {return}
	defer buffer_candidate_test_session_close(t, &session, handle)
	owned, owned_ok, _ := editor_session.session_open_path(
		&session,
		editor_session.Open_Path_Request {
			session = handle,
			path = owned_path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	external, external_ok, _ := editor_session.session_open_path(
		&session,
		editor_session.Open_Path_Request {
			session = handle,
			path = external_path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	notes, notes_ok, _ := editor_session.session_create_buffer(
		&session,
		editor_session.Create_Buffer_Request {
			session = handle,
			name = "notes",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, owned_ok && external_ok && notes_ok)
	if !owned_ok || !external_ok || !notes_ok {return}
	access, access_ok, _ := editor_session.session_entry_access(&session, notes.entry)
	borrow, borrow_ok, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, access_ok && borrow_ok)
	if borrow_ok {
		position, positioned, _ := editor.buffer_position(borrow.buffer, 0)
		_, _, changed, _ := editor.buffer_splice(
			borrow.buffer,
			editor.Splice{start = position, end = position, replacement = "draft"},
			context.temp_allocator,
		)
		testing.expect(t, positioned && changed)
		_, reconciled, _ := editor_session.entry_access_reconcile(access)
		testing.expect(t, reconciled)
	}
	directories := [1]project.Directory_Proposal{{path = owned_directory, trust = .Untrusted}}
	project_result, project_ok, _ := editor_session.session_replace_project(
		&session,
		editor_session.Project_Update_Request {
			session = handle,
			project_id = project.Project_ID(901),
			name = "Candidate Project",
			directories = directories[:],
			temporary = true,
		},
	)
	testing.expect(t, project_ok)
	if !project_ok {return}

	descriptors, descriptors_ok, _ := editor_session.session_descriptors(&session, handle)
	testing.expect(t, descriptors_ok)
	if !descriptors_ok {return}
	defer editor_session.descriptor_batch_close(&descriptors)
	classified, classified_ok, _ := editor_session.session_classify_project_buffers(
		&session,
		handle,
		project_result.active.handle,
	)
	testing.expect(t, classified_ok)
	if !classified_ok {return}
	defer editor_session.project_buffer_batch_close(&classified)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	general, general_ok, general_failure := session_buffer_candidate_source_build_query(
		&descriptors,
		"fresh",
		41,
		context.temp_allocator,
	)
	testing.expectf(t, general_ok, "general source failed with %v", general_failure.code)
	if !general_ok {return}
	defer buffer_candidate_source_close(&general)
	session_view: Candidate_Session
	_, admitted, admission_failure := candidate_session_init(
		&session_view,
		Candidate_Config {
			session_id = 41,
			limits = DEFAULT_CANDIDATE_LIMITS,
			persistent_allocator = allocator,
			temporary_allocator = context.temp_allocator,
		},
		general.definition,
		"fresh",
	)
	testing.expectf(t, admitted, "candidate admission failed with %v", admission_failure.code)
	if !admitted {return}
	view, viewed, _ := candidate_session_view(&session_view)
	testing.expect(t, viewed)
	testing.expect_value(t, len(view.rows), 1)
	if len(view.rows) == 1 {
		testing.expect_value(t, view.rows[0].label, "fresh")
		testing.expect_value(t, view.rows[0].availability, Candidate_Availability.Synthetic)
		testing.expect_value(t, view.rows[0].action.kind, Candidate_Action_Kind.Create_Buffer)
		testing.expect_value(t, view.rows[0].durable_category, Candidate_Durable_Category.None)
	}
	testing.expect_value(t, view.accounting.candidates, u32(4))
	testing.expect(t, view.accounting.annotation_bytes > 0)
	_, cancelled, _ := candidate_session_cancel(
		&session_view,
		Candidate_Request{session_id = view.session_id, session_generation = view.session_generation},
	)
	testing.expect(t, cancelled)
	_, moved, move_failure := candidate_session_move(
		&session_view,
		Candidate_Request{session_id = view.session_id, session_generation = view.session_generation + 1},
		1,
	)
	testing.expect(t, !moved)
	testing.expect_value(t, move_failure.code, Candidate_Failure_Code.Cancelled)
	_, closed, _ := candidate_session_close(&session_view)
	testing.expect(t, closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))

	exact, exact_ok, _ := session_buffer_candidate_source_build_query(
		&descriptors,
		"notes",
		42,
		context.temp_allocator,
	)
	testing.expect(t, exact_ok)
	if exact_ok {
		exact_session: Candidate_Session
		_, exact_admitted, _ := candidate_session_init(
			&exact_session,
			Candidate_Config {
				session_id = 42,
				limits = DEFAULT_CANDIDATE_LIMITS,
				persistent_allocator = allocator,
				temporary_allocator = context.temp_allocator,
			},
			exact.definition,
			"notes",
		)
		testing.expect(t, exact_admitted)
		if exact_admitted {
			exact_view, _, _ := candidate_session_view(&exact_session)
			testing.expect_value(t, len(exact_view.rows), 1)
			if len(exact_view.rows) == 1 {
				testing.expect_value(t, exact_view.rows[0].availability, Candidate_Availability.Available)
				testing.expect_value(t, exact_view.rows[0].action.kind, Candidate_Action_Kind.Activate_Buffer)
				testing.expect_value(t, len(exact_view.rows[0].annotations), 3)
				if len(exact_view.rows[0].annotations) == 3 {
					testing.expect_value(t, exact_view.rows[0].annotations[0].text, "non-file-backed")
					testing.expect_value(t, exact_view.rows[0].annotations[1].text, "modified")
					testing.expect_value(t, exact_view.rows[0].annotations[2].text, "non-file-backed")
				}
				testing.expect(t, buffer_candidate_action_graph_matches(exact_view.rows[0].action, descriptors.descriptors[0].graph))
				changed_graph := descriptors.descriptors[0].graph
				changed_graph.buffer_id += 1
				testing.expect(t, !buffer_candidate_action_graph_matches(exact_view.rows[0].action, changed_graph))
			}
			candidate_session_close(&exact_session)
		}
		buffer_candidate_source_close(&exact)
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))

	project_source, project_source_ok, project_source_failure := project_buffer_candidate_source_build_query(
		&descriptors,
		&classified,
		43,
		context.temp_allocator,
	)
	testing.expectf(t, project_source_ok, "Project source failed with %v", project_source_failure.code)
	if project_source_ok {
		defer buffer_candidate_source_close(&project_source)
		project_session: Candidate_Session
		_, project_admitted, _ := candidate_session_init(
			&project_session,
			Candidate_Config {
				session_id = 43,
				limits = DEFAULT_CANDIDATE_LIMITS,
				persistent_allocator = allocator,
				temporary_allocator = context.temp_allocator,
			},
			project_source.definition,
		)
		testing.expect(t, project_admitted)
		if project_admitted {
			project_view, _, _ := candidate_session_view(&project_session)
			testing.expect_value(t, project_view.source_kind, Candidate_Source_Kind.Project_Buffers)
			testing.expect_value(t, len(project_view.rows), 1)
			if len(project_view.rows) == 1 {
				testing.expect_value(t, project_view.rows[0].durable_category, Candidate_Durable_Category.Document)
				testing.expect(t, len(project_view.rows[0].durable_key) > 0)
			}
			_, stale, stale_failure := candidate_session_refresh(
				&project_session,
				Candidate_Request {
					session_id = project_view.session_id,
					session_generation = project_view.session_generation,
				},
				project_source.definition,
			)
			testing.expect(t, !stale)
			testing.expect_value(t, stale_failure.code, Candidate_Failure_Code.Stale_Source)
			candidate_session_close(&project_session)
		}
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	_ = owned
	_ = external
}

@(private)
buffer_candidate_test_session_close :: proc(
	t: ^testing.T,
	session: ^editor_session.Session,
	handle: editor_session.Session_Handle,
) {
	entries: [editor_session.MAX_LIVE_BUFFERS]editor_session.Entry_Handle
	count, copied, _ := editor_session.session_mru_entries(session, handle, entries[:])
	testing.expect(t, copied)
	if copied {
		for index in 0 ..< int(count) {
			detached: editor_session.Detached_Entry
			_, detached_ok, _ := editor_session.session_entry_detach(session, entries[index], &detached)
			testing.expect(t, detached_ok)
			if !detached_ok {continue}
			_, cleaned, _ := editor_session.detached_entry_cleanup(&detached)
			testing.expect(t, cleaned)
			if cleaned {
				released, _ := editor_session.detached_entry_release(&detached)
				testing.expect(t, released)
			}
		}
	}
	closed, _ := editor_session.session_close(session)
	testing.expect(t, closed)
}
