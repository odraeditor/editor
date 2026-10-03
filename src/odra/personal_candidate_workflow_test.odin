// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../editor"
import "../editor_session"
import "../interaction"
import editor_view "../view"
import "core:encoding/endian"
import "core:os"
import "core:testing"

@(private)
personal_candidate_workflow_test_payload :: proc(
	path: string,
	start, end: u64,
	action := interaction.Personal_Candidate_Action.Navigate,
	allocator := context.allocator,
) -> []u8 {
	title := "Roman relations: Ada Lovelace"
	query := "Ada"
	identity := "ada"
	label := "Ada Lovelace"
	search := "mathematician computing"
	texts := [6]string {title, query, identity, label, search, path}
	string_bytes := 0
	for text in texts do string_bytes += len(text)
	result := make(
		[]u8,
		interaction.PERSONAL_CANDIDATE_RESULT_HEADER_BYTES +
			interaction.PERSONAL_CANDIDATE_RESULT_RECORD_BYTES + string_bytes,
		allocator,
	)
	string_start := interaction.PERSONAL_CANDIDATE_RESULT_HEADER_BYTES +
		interaction.PERSONAL_CANDIDATE_RESULT_RECORD_BYTES
	spans: [12]u64
	cursor := 0
	for text, index in texts {
		spans[index * 2] = u64(cursor)
		spans[index * 2 + 1] = u64(len(text))
		copy(result[string_start + cursor:], transmute([]u8)text)
		cursor += len(text)
	}
	header := [8]u64 {
		interaction.PERSONAL_CANDIDATE_RESULT_SCHEMA,
		7,
		1,
		interaction.PERSONAL_CANDIDATE_RESULT_RECORD_BYTES,
		spans[2],
		spans[3],
		u64(string_bytes),
		u64(len(title)),
	}
	for field, index in header {
		assert(endian.put_u64(result[index * 8:], .Little, field))
	}
	record := [12]u64 {
		spans[4], spans[5], spans[6], spans[7],
		spans[8], spans[9], spans[10], spans[11],
		start, end, 1, u64(action),
	}
	for field, index in record {
		assert(endian.put_u64(
			result[interaction.PERSONAL_CANDIDATE_RESULT_HEADER_BYTES + index * 8:],
			.Little,
			field,
		))
	}
	return result
}

/* Verifies resumed candidates reject a changed source before package execution. */
@(test)
personal_candidate_resume_rejects_a_stale_source :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp(
		"", "odra-personal-resume-*", context.allocator,
	)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path, path_error := os.join_path({directory, "notes.org"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "Ada") == nil)

	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		9_503,
		{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer session_shutdown_close(&session, handle)
	opened, opened_ok, _ := command.buffer_session_find_file(
		command.Buffer_Session_Context {
			session = &session,
			handle = handle,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
		path,
	)
	testing.expect(t, opened_ok)
	if !opened_ok do return
	commands := personal_candidate_workflow_test_context(&session, handle)
	commands.next_transaction_id = 1
	commands.next_undo_unit_id = 1
	payload := personal_candidate_workflow_test_payload(
		path, 0, 3, .Resume,
	)
	_, present_failure := command_context_present_personal_candidates(
		&commands, payload, {}, {width_cells = 80, height_rows = 24},
	)
	delete(payload)
	testing.expect_value(t, present_failure.stage, App_Stage.None)
	access, accessible, _ := editor_session.session_entry_access(&session, opened.entry)
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, accessible && borrowed)
	if !borrowed do return
	position, positioned, _ := editor.buffer_position(entry.buffer, editor.Byte_Offset(3))
	testing.expect(t, positioned)
	if !positioned do return
	_, _, changed, _ := editor.buffer_splice(
		entry.buffer,
		editor.Splice{start = position, end = position, replacement = "!"},
		context.temp_allocator,
	)
	testing.expect(t, changed)
	view, viewed, _ := interaction.candidate_session_view(&commands.candidate_ui.session)
	testing.expect(t, viewed)
	if !viewed do return
	result, failure := command_context_activate_personal_candidate(&commands, view)
	testing.expect(t, result.changed && failure.stage == .None)
	testing.expect_value(
		t,
		string(commands.diagnostic[:commands.diagnostic_length]),
		"Candidate target is stale",
	)
	visible, visible_ok, _ := editor_session.session_visible_target(&session, handle)
	testing.expect(t, visible_ok)
	if visible_ok {
		testing.expect_value(t, visible.kind, editor_session.Visible_Target_Kind.Primary_View)
		testing.expect_value(t, visible.entry, opened.entry)
	}
}

@(private)
personal_candidate_workflow_test_context :: proc(
	session: ^editor_session.Session,
	handle: editor_session.Session_Handle,
) -> Command_Context {
	return Command_Context {
		session_owner = session,
		session_handle = handle,
		entry_configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
		candidate_ui = {
			next_session_id = 1,
			next_source_generation = 1,
		},
	}
}

/* Verifies command candidate cancellation restores the initiating editor entry. */
@(test)
personal_candidate_cancellation_restores_the_source :: proc(t: ^testing.T) {
	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		9_501,
		{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer session_shutdown_close(&session, handle)
	created, created_ok, _ := editor_session.session_create_buffer(
		&session,
		{
			session = handle,
			name = "roman-source",
			initial_contents = "source remains unchanged",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, created_ok)
	if !created_ok do return
	commands := personal_candidate_workflow_test_context(&session, handle)
	payload := personal_candidate_workflow_test_payload("/tmp/ada.org", 0, 1)
	result, failure := command_context_present_personal_candidates(
		&commands, payload, {}, {width_cells = 80, height_rows = 24},
	)
	delete(payload)
	testing.expect(t, result.changed && failure.stage == .None)
	view, viewed, _ := interaction.candidate_session_view(&commands.candidate_ui.session)
	testing.expect(t, viewed)
	if viewed {
		testing.expect_value(t, view.source_kind, interaction.Candidate_Source_Kind.Personal_Command_Results)
		testing.expect_value(t, view.query, "Ada")
		prompt_storage: [interaction.MAX_CANDIDATE_PROMPT_LABEL_BYTES]u8
		prompt, prompt_ok := personal_candidate_workflow_prompt_label(
			&commands,
			view,
			prompt_storage[:],
		)
		testing.expect(t, prompt_ok)
		if prompt_ok do testing.expect_value(t, prompt, "Roman relations: Ada Lovelace 1/1 Filter: ")
	}
	left, leave_failure := command_context_leave_personal_candidates(&commands)
	testing.expect(t, left.changed && leave_failure.stage == .None)
	visible, visible_ok, _ := editor_session.session_visible_target(&session, handle)
	testing.expect(t, visible_ok)
	if visible_ok {
		testing.expect_value(t, visible.kind, editor_session.Visible_Target_Kind.Primary_View)
		testing.expect_value(t, visible.entry, created.entry)
	}
	testing.expect(t, commands.personal_candidate_workflow.payload == nil)
}

/* Verifies one direct navigation result opens its document without a selector. */
@(test)
personal_navigation_result_opens_the_exact_document :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp(
		"", "odra-personal-navigation-*", context.allocator,
	)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path, path_error := os.join_path({directory, "daily.org"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "Daily note\n") == nil)

	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		9_504,
		{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer session_shutdown_close(&session, handle)
	origin, created_ok, _ := editor_session.session_create_buffer(
		&session,
		{
			session = handle,
			name = "roman-origin",
			initial_contents = "origin",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, created_ok)
	if !created_ok do return
	commands := personal_candidate_workflow_test_context(&session, handle)
	payload := personal_candidate_workflow_test_payload(
		path, 0, 0, .Navigate_Direct,
	)
	result, failure := command_context_present_personal_candidates(
		&commands, payload, {}, {width_cells = 80, height_rows = 24},
	)
	delete(payload)
	testing.expect(t, result.changed && failure.stage == .None)
	visible, visible_ok, _ := editor_session.session_visible_target(&session, handle)
	testing.expect(t, visible_ok)
	if visible_ok {
		testing.expect_value(t, visible.kind, editor_session.Visible_Target_Kind.Primary_View)
		testing.expect(t, visible.entry != origin.entry)
	}
	testing.expect_value(
		t,
		string(commands.diagnostic[:commands.diagnostic_length]),
		"Opened Ada Lovelace",
	)
	testing.expect(t, commands.personal_candidate_workflow.payload == nil)
	testing.expect(t, commands.candidate_ui.session.state == nil)
}

/* Verifies candidate activation visits the exact copied range without source mutation. */
@(test)
personal_candidate_activation_opens_the_exact_source_range :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp(
		"",
		"odra-personal-candidate-*",
		context.allocator,
	)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path, path_error := os.join_path({directory, "ada.org"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	contents := "zero\nAda Lovelace\n"
	testing.expect(t, os.write_entire_file(path, contents) == nil)

	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		9_502,
		{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer session_shutdown_close(&session, handle)
	origin, created_ok, _ := editor_session.session_create_buffer(
		&session,
		{
			session = handle,
			name = "roman-origin",
			initial_contents = "origin",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, created_ok)
	if !created_ok do return
	commands := personal_candidate_workflow_test_context(&session, handle)
	destination, destination_ok, _ := command.buffer_session_find_file(
		command.Buffer_Session_Context {
			session = &session,
			handle = handle,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
		path,
	)
	testing.expect(t, destination_ok)
	if !destination_ok do return
	destination_access, destination_accessible, _ := editor_session.session_entry_access(
		&session,
		destination.entry,
	)
	destination_entry, destination_borrowed, _ := editor_session.entry_access_borrow(destination_access)
	testing.expect(t, destination_accessible && destination_borrowed)
	if !destination_borrowed do return
	mark, mark_ok, _ := editor.buffer_position(destination_entry.buffer, editor.Byte_Offset(17))
	testing.expect(t, mark_ok)
	if !mark_ok do return
	marked, _ := editor_view.set_mark(
		destination_entry.view_registry,
		destination_entry.primary_view,
		mark,
		true,
	)
	testing.expect(t, marked)
	_, origin_activated, _ := editor_session.session_activate(&session, origin.entry)
	testing.expect(t, origin_activated)
	if !origin_activated do return
	payload := personal_candidate_workflow_test_payload(path, 5, 17)
	_, present_failure := command_context_present_personal_candidates(
		&commands, payload, {}, {width_cells = 80, height_rows = 24},
	)
	delete(payload)
	testing.expect_value(t, present_failure.stage, App_Stage.None)
	view, viewed, _ := interaction.candidate_session_view(&commands.candidate_ui.session)
	testing.expect(t, viewed)
	if !viewed do return
	activated, activation_failure := command_context_activate_personal_candidate(&commands, view)
	testing.expect(t, activated.changed && activation_failure.stage == .None)
	visible, visible_ok, _ := editor_session.session_visible_target(&session, handle)
	testing.expect(t, visible_ok)
	if visible_ok {
		testing.expect_value(t, visible.kind, editor_session.Visible_Target_Kind.Primary_View)
		access, accessible, _ := editor_session.session_entry_access(&session, visible.entry)
		entry, borrowed, _ := editor_session.entry_access_borrow(access)
		testing.expect(t, accessible && borrowed)
		if borrowed {
			selection, selected, _ := editor.buffer_selection_snapshot(entry.buffer)
			testing.expect(t, selected)
			if selected {
				testing.expect_value(t, selection.point_position.byte_offset, editor.Byte_Offset(5))
				testing.expect(t, !selection.mark.present && !selection.region_active)
			}
		}
	}
	testing.expect_value(
		t,
		string(commands.diagnostic[:commands.diagnostic_length]),
		"Opened Ada Lovelace",
	)
	stored, read_error := os.read_entire_file(path, context.allocator)
	testing.expect(t, read_error == nil)
	if read_error == nil {
		defer delete(stored)
		testing.expect_value(t, string(stored), contents)
	}
}
