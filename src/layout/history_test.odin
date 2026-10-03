// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

import "../editor"
import "../editor_session"
import "../view"
import "core:testing"

/* Verifies root history admission, independent split copies, and recency updates. */
@(test)
histories_copy_then_evolve_independently :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	root_entry := history_test_entry(1, 0)
	ready := history_test_registry(20_401, root_entry, &buffer, &views, &root_view, &registry)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer geometry_test_close(&buffer, &views, &root_view, &registry)

	handle, _, _ := registry_handle(&registry)
	initial, _, _ := registry_snapshot(&registry, handle)
	root_history, root_ok, _ := registry_pane_history_snapshot(&registry, initial.active_pane)
	buffer_list, list_ok, _ := registry_buffer_list_snapshot(&registry, handle)
	testing.expect(t, root_ok && list_ok)
	testing.expect_value(t, root_history.count, u16(1))
	testing.expect_value(t, root_history.entries[0].state.entry, root_entry)
	testing.expect_value(t, buffer_list.count, u16(1))
	testing.expect_value(t, buffer_list.entries[0].entry, root_entry)

	split, split_ok, _ := registry_split_right(&registry, initial.active_pane)
	testing.expect(t, split_ok)
	if !split_ok {
		return
	}
	original_history, original_ok, _ := registry_pane_history_snapshot(&registry, split.original)
	created_history, created_ok, _ := registry_pane_history_snapshot(&registry, split.created)
	testing.expect(t, original_ok && created_ok)
	testing.expect_value(t, original_history.generation, created_history.generation)
	testing.expect_value(t, original_history.count, created_history.count)
	testing.expect_value(t, original_history.entries, created_history.entries)

	second := history_test_state(history_test_entry(2, 1), editor.Buffer_ID(20_402), 7, 3)
	recorded, recorded_ok, _ := registry_pane_history_record(&registry, split.created, second)
	testing.expect(t, recorded_ok)
	if !recorded_ok {
		return
	}
	after, _, _ := registry_snapshot(&registry, recorded)
	original := snapshot_pane(&after, split.original.pane_id)
	created := snapshot_pane(&after, split.created.pane_id)
	original_history, original_ok, _ = registry_pane_history_snapshot(&registry, original.pane)
	created_history, created_ok, _ = registry_pane_history_snapshot(&registry, created.pane)
	testing.expect(t, original_ok && created_ok)
	testing.expect_value(t, original_history.count, u16(1))
	testing.expect_value(t, created_history.count, u16(2))
	testing.expect_value(t, created_history.entries[0].state, second)
	testing.expect_value(t, created_history.entries[1].state.entry, root_entry)
	buffer_list, list_ok, _ = registry_buffer_list_snapshot(&registry, recorded)
	testing.expect(t, list_ok)
	testing.expect_value(t, buffer_list.count, u16(2))
	testing.expect_value(t, buffer_list.entries[0].entry, second.entry)
}

/* Verifies bounded history eviction, duplicate update, and previous-buffer lookup. */
@(test)
history_capacity_evicts_and_deduplicates :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	root_entry := history_test_entry(1, 0)
	policy := DEFAULT_POLICY
	policy.pane_history_entries = 2
	ready := history_test_registry(
		20_411,
		root_entry,
		&buffer,
		&views,
		&root_view,
		&registry,
		policy,
	)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer geometry_test_close(&buffer, &views, &root_view, &registry)

	handle, _, _ := registry_handle(&registry)
	initial, _, _ := registry_snapshot(&registry, handle)
	second := history_test_state(history_test_entry(2, 1), editor.Buffer_ID(20_412), 4, 2)
	second_ok: bool
	handle, second_ok, _ = registry_pane_history_record(&registry, initial.active_pane, second)
	testing.expect(t, second_ok)
	after_second, _, _ := registry_snapshot(&registry, handle)
	pane := after_second.active_pane
	third := history_test_state(history_test_entry(3, 2), editor.Buffer_ID(20_413), 9, 5)
	third_ok: bool
	handle, third_ok, _ = registry_pane_history_record(&registry, pane, third)
	testing.expect(t, third_ok)
	after_third, _, _ := registry_snapshot(&registry, handle)
	pane = after_third.active_pane
	history, history_ok, _ := registry_pane_history_snapshot(&registry, pane)
	testing.expect(t, history_ok)
	testing.expect_value(t, history.count, u16(2))
	testing.expect_value(t, history.entries[0].state, third)
	testing.expect_value(t, history.entries[1].state, second)
	_, root_found, _ := registry_pane_history_previous(&registry, pane, editor.Buffer_ID(20_413))
	testing.expect(t, root_found)

	second.stored_point.byte_offset = editor.Byte_Offset(11)
	updated_ok: bool
	handle, updated_ok, _ = registry_pane_history_record(&registry, pane, second)
	testing.expect(t, updated_ok)
	updated_snapshot, _, _ := registry_snapshot(&registry, handle)
	history, history_ok, _ = registry_pane_history_snapshot(&registry, updated_snapshot.active_pane)
	testing.expect(t, history_ok)
	testing.expect_value(t, history.count, u16(2))
	testing.expect_value(t, history.entries[0].state, second)
	testing.expect_value(t, history.entries[1].state, third)
}

/* Verifies global purge removes stale references and rejects displayed buffers atomically. */
@(test)
history_purge_covers_all_panes :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	root_entry := history_test_entry(1, 0)
	ready := history_test_registry(20_421, root_entry, &buffer, &views, &root_view, &registry)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer geometry_test_close(&buffer, &views, &root_view, &registry)

	handle, _, _ := registry_handle(&registry)
	initial, _, _ := registry_snapshot(&registry, handle)
	second := history_test_state(history_test_entry(2, 1), editor.Buffer_ID(20_422), 2, 1)
	recorded: bool
	handle, recorded, _ = registry_pane_history_record(&registry, initial.active_pane, second)
	testing.expect(t, recorded)
	after_record, _, _ := registry_snapshot(&registry, handle)
	split, split_ok, _ := registry_split_below(&registry, after_record.active_pane)
	testing.expect(t, split_ok)
	if !split_ok {
		return
	}
	purged, purge_ok, _ := registry_pane_history_purge(
		&registry,
		split.layout,
		second.entry,
		second.buffer_id,
	)
	testing.expect(t, purge_ok)
	if !purge_ok {
		return
	}
	after_purge, _, _ := registry_snapshot(&registry, purged)
	for node in after_purge.nodes[:after_purge.node_count] {
		if node.kind != .Pane {
			continue
		}
		history, history_ok, _ := registry_pane_history_snapshot(&registry, node.pane)
		testing.expect(t, history_ok)
		testing.expect_value(t, history.count, u16(1))
		testing.expect_value(t, history.entries[0].state.entry, root_entry)
	}
	list, list_ok, _ := registry_buffer_list_snapshot(&registry, purged)
	testing.expect(t, list_ok)
	testing.expect_value(t, list.count, u16(1))

	before := after_purge
	_, displayed_ok, displayed_failure := registry_pane_history_purge(
		&registry,
		purged,
		root_entry,
		editor.Buffer_ID(20_421),
	)
	current, current_ok, _ := registry_snapshot(&registry, purged)
	testing.expect(t, !displayed_ok && current_ok)
	testing.expect_value(t, displayed_failure.code, Failure_Code.Buffer_Displayed)
	testing.expect_value(t, current, before)
}

@(private)
history_test_entry :: proc(entry_id: u64, slot: u32) -> editor_session.Entry_Handle {
	return editor_session.Entry_Handle {
		registry = editor_session.Registry_Handle {
			session = editor_session.Session_Handle {
				session_id = editor_session.Session_ID(77),
				generation = editor_session.Session_Generation(1),
			},
			generation = editor_session.Registry_Generation(1),
		},
		entry_id = editor_session.Entry_ID(entry_id),
		slot = slot,
		generation = 1,
	}
}

@(private)
history_test_state :: proc(
	entry: editor_session.Entry_Handle,
	buffer_id: editor.Buffer_ID,
	point, viewport: u64,
) -> Pane_Buffer_State {
	return Pane_Buffer_State {
		entry = entry,
		buffer_id = buffer_id,
		stored_point = editor.Position {
			buffer_id = buffer_id,
			revision = editor.Revision(1),
			byte_offset = editor.Byte_Offset(point),
		},
		viewport_start = editor.Position {
			buffer_id = buffer_id,
			revision = editor.Revision(1),
			byte_offset = editor.Byte_Offset(viewport),
		},
		horizontal_display_column = 3,
		desired_display_column = 5,
	}
}

@(private)
history_test_registry :: proc(
	id: u64,
	root_entry: editor_session.Entry_Handle,
	buffer: ^editor.Buffer,
	views: ^view.Registry,
	root_view: ^view.View_Handle,
	registry: ^Registry,
	policy := DEFAULT_POLICY,
) -> bool {
	buffer_ok, _ := editor.buffer_init(
		buffer,
		editor.Buffer_ID(id),
		"history",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	views_ok, _ := view.registry_init(views, view.Registry_ID(u32(id)), context.allocator)
	created_view, root_ok, _ := view.create(views, buffer)
	root_view^ = created_view
	registry_ok, _ := registry_init(
		registry,
		Owner_ID(id),
		Layout_ID(id),
		views,
		root_view^,
		Geometry_Request{rows = 24, columns = 80},
		policy,
		context.allocator,
		root_entry,
	)
	return buffer_ok && views_ok && root_ok && registry_ok
}
