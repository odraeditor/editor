// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

import "../editor"
import "../editor_session"
import "../view"
import "core:testing"

/* Verifies active replacement restores pane-local state and publishes both histories. */
@(test)
replacement_restores_redisplay_state :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_501) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)

	handle, _, _ := registry_handle(&fixture.registry)
	initial, _, _ := registry_snapshot(&fixture.registry, handle)
	_, activated, _ := editor_session.session_activate(&fixture.session, fixture.second.entry)
	replaced, replace_ok, replace_failure := registry_replace_pane_buffer(
		&fixture.registry,
		initial.active_pane,
		&fixture.session,
		fixture.second.entry,
	)
	testing.expect(t, activated && replace_ok)
	testing.expect_value(t, replace_failure.code, Failure_Code.None)
	if !replace_ok {
		return
	}
	testing.expect_value(t, replaced.previous_entry, fixture.first.entry)
	testing.expect_value(t, replaced.entry, fixture.second.entry)
	second_state, second_state_ok, _ := view.snapshot(fixture.views, replaced.view)
	testing.expect(t, second_state_ok)
	testing.expect_value(t, second_state.effective_point_position.byte_offset, editor.Byte_Offset(5))

	_, activated, _ = editor_session.session_activate(&fixture.session, fixture.first.entry)
	restored, restored_ok, restored_failure := registry_replace_pane_buffer(
		&fixture.registry,
		replaced.pane,
		&fixture.session,
		fixture.first.entry,
	)
	testing.expect(t, activated && restored_ok)
	testing.expect_value(t, restored_failure.code, Failure_Code.None)
	if !restored_ok {
		return
	}
	first_state, first_state_ok, _ := view.snapshot(fixture.views, restored.view)
	testing.expect(t, first_state_ok)
	testing.expect_value(t, first_state.effective_point_position.byte_offset, editor.Byte_Offset(4))
	testing.expect_value(t, first_state.viewport_origin_position.byte_offset, editor.Byte_Offset(2))
	history, history_ok, _ := registry_pane_history_snapshot(&fixture.registry, restored.pane)
	testing.expect(t, history_ok)
	testing.expect_value(t, history.count, u16(2))
	testing.expect_value(t, history.entries[0].state.entry, fixture.first.entry)
	testing.expect_value(t, history.entries[1].state.entry, fixture.second.entry)
	list, list_ok, _ := registry_buffer_list_snapshot(&fixture.registry, restored.layout)
	testing.expect(t, list_ok)
	testing.expect_value(t, list.count, u16(2))
	testing.expect_value(t, list.entries[0].entry, fixture.first.entry)
}

/* Verifies inactive replacement chooses retained primaries and pane-owned additional views. */
@(test)
pane_buffer_replacement_manages_primary :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_511) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)

	handle, _, _ := registry_handle(&fixture.registry)
	initial, _, _ := registry_snapshot(&fixture.registry, handle)
	split, split_ok, _ := registry_split_right(&fixture.registry, initial.active_pane)
	testing.expect(t, split_ok)
	if !split_ok {
		return
	}
	replaced, replace_ok, _ := registry_replace_pane_buffer(
		&fixture.registry,
		split.created,
		&fixture.session,
		fixture.second.entry,
	)
	testing.expect(t, replace_ok)
	if !replace_ok {
		return
	}
	second_state, second_ok, _ := view.snapshot(fixture.views, replaced.view)
	testing.expect(t, second_ok)
	testing.expect_value(t, second_state.presentation_ownership, view.Presentation_Ownership.Retained_Primary)
	stats, stats_ok, _ := view.registry_stats(fixture.views)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.additional_count, u16(0))

	restored, restored_ok, _ := registry_replace_pane_buffer(
		&fixture.registry,
		replaced.pane,
		&fixture.session,
		fixture.first.entry,
	)
	testing.expect(t, restored_ok)
	if !restored_ok {
		return
	}
	additional_state, additional_ok, _ := view.snapshot(fixture.views, restored.view)
	testing.expect(t, additional_ok)
	testing.expect_value(t, additional_state.presentation_ownership, view.Presentation_Ownership.Additional)
	stats, stats_ok, _ = view.registry_stats(fixture.views)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.additional_count, u16(1))
}

@(private)
Replacement_Test_Fixture :: struct {
	session:  editor_session.Session,
	handle:   editor_session.Session_Handle,
	first:    editor_session.Admission_Result,
	second:   editor_session.Admission_Result,
	third:    editor_session.Admission_Result,
	views:    ^view.Registry,
	registry: Registry,
}

@(private)
replacement_test_fixture_init :: proc(
	t: ^testing.T,
	fixture: ^Replacement_Test_Fixture,
	id: u64,
	persistent := context.allocator,
) -> bool {
	handle, initialized, _ := editor_session.session_init(
		&fixture.session,
		editor_session.Session_ID(id),
		editor_session.Allocator_Set {
			persistent = persistent,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return false
	}
	fixture.handle = handle
	fixture.first, initialized, _ = editor_session.session_create_buffer(
		&fixture.session,
		editor_session.Create_Buffer_Request {
			session = handle,
			name = "first",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	if initialized {
		initialized = replacement_test_prepare_entry(
			&fixture.session,
			fixture.first.entry,
			"abcdef",
			4,
			2,
		)
	}
	if initialized {
		fixture.second, initialized, _ = editor_session.session_create_buffer(
			&fixture.session,
			editor_session.Create_Buffer_Request {
				session = handle,
				name = "second",
				configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
			},
		)
	}
	if initialized {
		initialized = replacement_test_prepare_entry(
			&fixture.session,
			fixture.second.entry,
			"uvwxyz",
			5,
			1,
		)
	}
	if initialized {
		fixture.third, initialized, _ = editor_session.session_create_buffer(
			&fixture.session,
			editor_session.Create_Buffer_Request {
				session = handle,
				name = "third",
				configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
			},
		)
	}
	if initialized {
		initialized = replacement_test_prepare_entry(
			&fixture.session,
			fixture.third.entry,
			"third!",
			3,
			0,
		)
	}
	if initialized {
		_, initialized, _ = editor_session.session_activate(&fixture.session, fixture.first.entry)
	}
	access: editor_session.Entry_Access
	borrow: editor_session.Entry_Borrow
	if initialized {
		access, initialized, _ = editor_session.session_entry_access(
			&fixture.session,
			fixture.first.entry,
		)
	}
	if initialized {
		borrow, initialized, _ = editor_session.entry_access_borrow(access)
	}
	if initialized {
		fixture.views = borrow.view_registry
		initialized, _ = registry_init(
			&fixture.registry,
			Owner_ID(id),
			Layout_ID(id),
			borrow.view_registry,
			borrow.primary_view,
			Geometry_Request{rows = 24, columns = 80},
			allocator = persistent,
			root_entry = fixture.first.entry,
		)
	}
	testing.expect(t, initialized)
	return initialized
}

@(private)
replacement_test_prepare_entry :: proc(
	session: ^editor_session.Session,
	entry: editor_session.Entry_Handle,
	text: string,
	point_offset, viewport_offset: u64,
) -> bool {
	access, accessed, _ := editor_session.session_entry_access(session, entry)
	if !accessed {
		return false
	}
	borrow, borrowed, _ := editor_session.entry_access_borrow(access)
	if !borrowed {
		return false
	}
	start, start_ok, _ := editor.buffer_position(borrow.buffer, 0)
	if !start_ok {
		return false
	}
	_, _, changed, _ := editor.buffer_splice(
		borrow.buffer,
		editor.Splice{start = start, end = start, replacement = text},
		context.temp_allocator,
	)
	point, point_ok, _ := editor.buffer_position(borrow.buffer, editor.Byte_Offset(point_offset))
	viewport, viewport_ok, _ := editor.buffer_position(
		borrow.buffer,
		editor.Byte_Offset(viewport_offset),
	)
	point_set, _ := view.set_point(borrow.view_registry, borrow.primary_view, point)
	viewport_set, _ := view.set_viewport(borrow.view_registry, borrow.primary_view, viewport, 0)
	_, reconciled, _ := editor_session.entry_access_reconcile(access)
	return changed && point_ok && viewport_ok && point_set && viewport_set && reconciled
}

@(private)
replacement_test_fixture_close :: proc(t: ^testing.T, fixture: ^Replacement_Test_Fixture) {
	if fixture.registry.state != nil {
		closed, _ := registry_close(&fixture.registry)
		testing.expect(t, closed)
	}
	replacement_test_close_entry(t, &fixture.session, fixture.third.entry)
	replacement_test_close_entry(t, &fixture.session, fixture.second.entry)
	replacement_test_close_entry(t, &fixture.session, fixture.first.entry)
	closed, _ := editor_session.session_close(&fixture.session)
	testing.expect(t, closed)
}

@(private)
replacement_test_close_entry :: proc(
	t: ^testing.T,
	session: ^editor_session.Session,
	entry: editor_session.Entry_Handle,
) {
	_, live, _ := editor_session.session_entry_access(session, entry)
	if !live {
		return
	}
	_, closed, _ := editor_session.session_close_buffer(
		session,
		editor_session.Close_Buffer_Request {
			entry = entry,
			authority = .Discard_Modified,
		},
	)
	testing.expect(t, closed)
}
