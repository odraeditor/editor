// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "../editor"
import "../search"
import editor_view "../view"
import "core:testing"

@(test)
/* Verifies text projection copies exact revisioned editor state and source mapping. */
text_view_copies_revisioned_state :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		601,
		"00 needle 11 needle 22",
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	view_registry: editor_view.Registry
	view_registry_ok, _ := editor_view.registry_init(&view_registry, 601, context.allocator)
	view_handle, view_created, _ := editor_view.create(&view_registry, &buffer)
	testing.expect(t, view_registry_ok && view_created)
	if !view_registry_ok || !view_created {
		if view_registry_ok do editor_view.registry_close(&view_registry)
		editor.buffer_close(&buffer)
		return
	}
	mark, _, _ := editor.buffer_position(&buffer, 1)
	viewport, _, _ := editor.buffer_position(&buffer, 0)
	mark_set, _ := editor_view.set_mark(&view_registry, view_handle, mark)
	viewport_set, _ := editor_view.set_viewport(&view_registry, view_handle, viewport, 3)
	policy_set, _ := editor_view.set_layout_policy(&view_registry, view_handle, 12, 8, 3)
	search_ready := text_test_publish_search(&view_registry, view_handle, &buffer, "needle")
	testing.expect(t, mark_set && viewport_set && policy_set && search_ready)

	registry: Registry
	registry_ok, _ := registry_init(&registry, 601)
	proposal, proposal_ok, _ := proposal_begin(&registry)
	_, normal_style_ok, _ := proposal_add_style(&proposal, .Text_Normal)
	_, region_style_ok, _ := proposal_add_style(&proposal, .Text_Region, {.Reverse})
	_, search_style_ok, _ := proposal_add_style(&proposal, .Text_Search_Current, {.Underline})
	text_view, projected, projection_failure := proposal_project_editor_text_view(
		&proposal,
		&view_registry,
		view_handle,
		&buffer,
		601,
		false,
		nil,
		.Underline,
	)
	surface, surface_ok, _ := proposal_add_surface(
		&proposal,
		Surface_Descriptor {
			owner_id = 601,
			view = text_view,
			focusable = true,
			visible = true,
			required_profile = 1,
		},
	)
	node, node_ok, _ := proposal_add_surface_node(&proposal, surface)
	root_set, _ := proposal_set_root(&proposal, node, surface)
	root, published, publish_failure := proposal_publish(
		&registry,
		&proposal,
		text_test_renderer(),
	)
	snapshot, copied, snapshot_failure := registry_snapshot(
		&registry,
		root,
		text_test_renderer(),
	)
	state, viewed := snapshot_view(&snapshot)

	testing.expectf(t, projected, "text projection failed with %v", projection_failure.code)
	testing.expectf(t, published, "text publication failed with %v", publish_failure.code)
	testing.expectf(t, copied, "text snapshot failed with %v", snapshot_failure.code)
	testing.expect(
		t,
		registry_ok && proposal_ok && normal_style_ok && region_style_ok && search_style_ok &&
		surface_ok && node_ok && root_set && viewed,
	)
	if viewed && len(state.views) == 1 && len(state.projections) == 1 {
		view := state.views[0]
		projection := state.projections[0]
		testing.expect_value(t, view.kind, Visual_Kind.Text_View)
		testing.expect(t, view.text.present && view.text.region_active)
		testing.expect_value(t, view.text.source.registry_id, u32(601))
		testing.expect_value(t, view.text.source.view_id, u64(view_handle.view_id))
		testing.expect_value(t, view.text.source.view_generation, view_handle.generation)
		testing.expect_value(t, view.text.buffer_id, u64(601))
		testing.expect_value(t, view.text.revision, u64(0))
		testing.expect_value(t, view.text.source_text_bytes, u64(22))
		testing.expect_value(t, view.text.mark, u64(1))
		testing.expect_value(t, view.text.viewport_origin, u64(0))
		testing.expect_value(t, view.text.horizontal_display_column, u32(3))
		testing.expect_value(t, view.text.desired_display_column, u32(12))
		testing.expect_value(t, view.text.tab_width, u16(8))
		testing.expect_value(t, view.text.display_profile_id, u64(3))
		testing.expect_value(t, view.text.cursor_shape, Text_Cursor_Shape.Underline)
		testing.expect_value(
			t,
			view.text.presentation_ownership,
			Text_Presentation_Ownership.Retained_Primary,
		)
		testing.expect(t, view.text.search.present && view.text.search.has_current)
		testing.expect_value(t, view.text.search.status, Text_Search_Status.Active)
		testing.expect_value(t, view.text.search.match_count, u32(2))
		testing.expect_value(t, view.text.search.current_start, u64(3))
		testing.expect_value(t, view.text.search.current_end, u64(9))
		testing.expect_value(t, projection.model.owner_id, Owner_ID(601))
		testing.expect_value(t, projection.model.model_id, Model_ID(601))
		testing.expect_value(t, projection.model.generation, Model_Generation(1))
		testing.expect_value(t, projection.byte_count, u64(size_of(Text_View_State)))
	}

	if copied do snapshot_close(&snapshot)
	if registry_ok do registry_close(&registry)
	editor_view.close(&view_registry, &view_handle)
	editor_view.registry_close(&view_registry)
	editor.buffer_close(&buffer)
}

@(test)
/* editor_text_view_projection_rejects_stale_source_without_proposal_mutation. */
stale_text_view_leaves_proposal_unchanged :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		602,
		"abc",
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	view_registry: editor_view.Registry
	view_registry_ok, _ := editor_view.registry_init(&view_registry, 602, context.allocator)
	view_handle, view_created, _ := editor_view.create(&view_registry, &buffer)
	stale := view_handle
	view_closed, _ := editor_view.close(&view_registry, &view_handle)

	registry: Registry
	registry_ok, _ := registry_init(&registry, 602)
	proposal, proposal_ok, _ := proposal_begin(&registry)
	_, projected, failure := proposal_project_editor_text_view(
		&proposal,
		&view_registry,
		stale,
		&buffer,
		602,
	)
	state := proposal_state(&proposal)

	testing.expect(
		t,
		initialized && view_registry_ok && view_created && view_closed && registry_ok && proposal_ok,
	)
	testing.expect(t, !projected)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Text_View)
	testing.expect_value(t, failure.source_view_id, u64(stale.view_id))
	testing.expect_value(t, failure.source_view_generation, stale.generation)
	testing.expect(t, state != nil)
	if state != nil {
		testing.expect_value(t, state.projection_count, 0)
		testing.expect_value(t, state.view_count, 0)
		testing.expect_value(t, state.accounting.projection_bytes, u64(0))
	}

	proposal_abort(&proposal)
	registry_close(&registry)
	editor_view.registry_close(&view_registry)
	editor.buffer_close(&buffer)
}

@(private)
text_test_publish_search :: proc(
	registry: ^editor_view.Registry,
	handle: editor_view.View_Handle,
	buffer: ^editor.Buffer,
	pattern: string,
) -> bool {
	query: search.Query
	query_ok, _ := search.query_init(
		&query,
		search.Query_Config {
			id = 1,
			kind = .Literal,
			pattern = pattern,
			policy = search.DEFAULT_POLICY,
			limits = search.DEFAULT_LIMITS,
			allocator = context.allocator,
		},
	)
	if !query_ok {
		return false
	}
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(buffer, &snapshot)
	if !opened {
		search.query_close(&query)
		return false
	}
	stats, _, _ := editor.buffer_snapshot_stats(&snapshot)
	result: search.Result
	searched, _ := search.literal_search(
		&result,
		&snapshot,
		&query,
		search.Request {
			scope = search.Scope {
				buffer_id = stats.buffer_id,
				revision = stats.revision,
				start = 0,
				end = editor.Byte_Offset(stats.text_bytes),
			},
			origin = 0,
			direction = .Forward,
			generation = 1,
		},
		nil,
		search.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	editor.buffer_snapshot_close(&snapshot)
	if !searched {
		search.query_close(&query)
		return false
	}
	published, _ := editor_view.search_session_publish(
		registry,
		handle,
		editor_view.Search_Update {
			interaction_generation = 1,
			policy_generation = 1,
			direction = .Forward,
			scope = search.Scope {
				buffer_id = stats.buffer_id,
				revision = stats.revision,
				start = 0,
				end = editor.Byte_Offset(stats.text_bytes),
			},
		},
		&query,
		&result,
	)
	if !published {
		if query.state != nil do search.query_close(&query)
		if result.state != nil do search.result_close(&result)
	}
	return published
}

@(private)
text_test_renderer :: proc() -> Renderer_Profile {
	return Renderer_Profile {
		id = 1,
		capabilities = {
			.Cell_Geometry,
			.Clipping,
			.Unicode_Profile,
			.Text_Cursor,
			.Input_Cursor,
			.Semantic_Attributes,
			.Atomic_Generation,
			.Full_Redraw,
		},
		unicode_profile = 17,
		max_rows = 80,
		max_columns = 240,
		max_cells = 19_200,
		attributes = {.Bold, .Dim, .Underline, .Reverse},
	}
}
