// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../interaction"
import "../display"
import "../ui"
import "base:runtime"
import "core:mem"
import "core:strings"
import "core:testing"

@(test)
/* Ensures every source row survives projection and model selection remains authoritative. */
lists_keep_rows_and_selection :: proc(t: ^testing.T) {
	command_annotations := []interaction.Candidate_Annotation {
		{kind = .Binding, text = "M-x"},
		{kind = .Provider, text = "native"},
		{kind = .Availability, text = "available"},
		{kind = .Description, text = "Run command"},
	}
	buffer_annotations := []interaction.Candidate_Annotation {
		{kind = .Document_Path, text = "/tmp/a.txt"},
		{kind = .Modified_State, text = "modified"},
		{kind = .Generic, text = "file"},
	}
	file_annotations := []interaction.Candidate_Annotation {
		{kind = .Project_Member, text = "member"},
	}
	theme_annotations := []interaction.Candidate_Annotation {
		{kind = .Generic, text = "wroclaw-night"},
		{kind = .Provider, text = "odra-factory"},
		{kind = .Availability, text = "active, fallback"},
	}
	diagnostic_annotations := []interaction.Candidate_Annotation {
		{kind = .Severity, text = "error"},
		{kind = .Location, text = "/tmp/main.odin"},
	}
	result_annotations := []interaction.Candidate_Annotation {
		{kind = .Document_Path, text = "src/main.odin"},
		{kind = .Location, text = "12:7"},
	}
	status_annotations := []interaction.Candidate_Annotation {
		{kind = .Generic, text = "Odin language context"},
	}
	slot_annotations := []interaction.Candidate_Annotation {
		{kind = .Description, text = "make_task(\"Review\")"},
	}
	cases := []struct {
		name:        string,
		source:      interaction.Candidate_Source_Kind,
		label:       string,
		annotations: []interaction.Candidate_Annotation,
		expected:    string,
	} {
		{"commands", .Commands, "execute", command_annotations, "execute  [M-x]  Run command"},
		{"session buffers", .Session_Buffers, "a.txt", buffer_annotations, "a.txt  [/tmp/a.txt]  [modified]  file"},
		{"Project buffers", .Project_Buffers, "a.txt", buffer_annotations, "a.txt  [/tmp/a.txt]  [modified]  file"},
		{"Project files", .Project_Files, "src/main.odin", file_annotations, "src/main.odin  [member]"},
		{"Dir files", .Dir_Files, "src/main.odin", nil, "src/main.odin"},
		{"themes", .Themes, "Wrocław Night", theme_annotations, "Wrocław Night  [wroclaw-night]  [odra-factory]  active, fallback"},
		{"named slots", .Named_Slots, "signature", slot_annotations,
			"signature    make_task(\"Review\")"},
		{"diagnostics", .Language_Diagnostics, "unknown name", diagnostic_annotations,
			"unknown name  [error]  /tmp/main.odin"},
		{"results", .Results, "make_task(\"Review\")", result_annotations,
			"src/main.odin  12:7   make_task(\"Review\")"},
		{"Status Bar segments", .Status_Segments, "(Odin)", status_annotations,
			"(Odin)   Odin language context"},
		{"package catalogs", .Package_Catalogs, "odra-official", status_annotations,
			"odra-official   Odin language context"},
		{"packages", .Packages, "odra.rot13@0.1.0", status_annotations,
			"odra.rot13@0.1.0   Odin language context"},
		{"package catalog diagnostics", .Package_Catalog_Diagnostics,
			"Registrations: 1", nil, "Registrations: 1"},
	}
	for test_case, case_index in cases {
		_ = test_case.name
			row := interaction.Candidate_Row {
				identity = {kind = u16(case_index + 1), primary = 11, secondary = 12},
				label = test_case.label,
				annotations = test_case.annotations,
				action = {kind = .Open_Document, owner_generation = 4, primary = 5},
				availability = .Available,
			}
			if test_case.source == .Results {
				row.label_highlight_start = 11
				row.label_highlight_end = 17
				row.label_highlight_present = true
			} else if test_case.source == .Named_Slots {
				row.action.kind = .Select_Named_Slot
			}
			view := interaction.Candidate_View {
				session_id = interaction.Candidate_Session_ID(70 + case_index),
				session_generation = 9,
				source_kind = test_case.source,
				scope_identity = 2,
				scope_generation = 3,
				source_generation = 4,
				rows = []interaction.Candidate_Row{row},
				selected_row = 0,
				has_selection = true,
			}
			registry: ui.Registry
			initialized, _ := ui.registry_init(&registry, ui.Registry_ID(70 + case_index))
			testing.expect(t, initialized)
			if !initialized do return
			defer ui.registry_close(&registry)
			proposal, prepared, _ := ui.proposal_begin(&registry)
			_, normal_ok, _ := ui.proposal_add_style(&proposal, .List_Normal)
			_, current_ok, _ := ui.proposal_add_style(&proposal, .List_Current)
			_, emphasis_ok, _ := ui.proposal_add_style(&proposal, .List_Emphasis, {.Bold})
			_, search_ok, _ := ui.proposal_add_style(&proposal, .Text_Search_Current, {.Underline})
			list, projected, projection_failure := proposal_project_candidate_list(
				&proposal,
				view,
				8,
				context.temp_allocator,
			)
			testing.expectf(t, projected, "candidate projection failed: %v", projection_failure)
			surface, surface_ok, _ := ui.proposal_add_surface(
				&proposal,
				ui.Surface_Descriptor {
					owner_id = ui.Owner_ID(view.session_id),
					view = list,
					focusable = true,
					visible = true,
					required_profile = 1,
				},
			)
			node, node_ok, _ := ui.proposal_add_surface_node(&proposal, surface)
			root_ok, _ := ui.proposal_set_root(&proposal, node, surface)
			root, published, publish_failure := ui.proposal_publish(
				&registry,
				&proposal,
				candidate_ui_test_renderer(),
			)
			testing.expectf(t, published, "candidate publish failed: %v", publish_failure)
			snapshot, copied, _ := ui.registry_snapshot(
				&registry,
				root,
				candidate_ui_test_renderer(),
			)
				if copied {
				state, state_ok := ui.snapshot_view(&snapshot)
				items, items_ok := ui.snapshot_list_items(state, state.views[list.slot])
				text, text_ok := ui.snapshot_list_item_text(state, items[0])
				resolved, index, action_ok := candidate_ui_action_row(view, items[0].action)
				testing.expect(t, state_ok && items_ok && text_ok && action_ok)
				testing.expect_value(t, state.views[list.slot].list.position.selection_owner, ui.Selection_Owner.Model)
				testing.expect_value(t, text, test_case.expected)
				testing.expect_value(t, index, u32(0))
					testing.expect_value(t, resolved.identity, row.identity)
					if test_case.source == .Results {
						testing.expect_value(t, items[0].style_span_count, u8(2))
						testing.expect_value(t, items[0].style_spans[0].start_byte, u32(0))
						testing.expect_value(t, items[0].style_spans[0].end_byte, u32(19))
						testing.expect_value(t, items[0].style_spans[0].style_role, ui.Style_Role.List_Emphasis)
						testing.expect_value(t, items[0].style_spans[1].start_byte, u32(33))
						testing.expect_value(t, items[0].style_spans[1].end_byte, u32(39))
						testing.expect_value(t, items[0].style_spans[1].style_role, ui.Style_Role.Text_Search_Current)
					} else if test_case.source == .Named_Slots {
						testing.expect_value(t, items[0].style_span_count, u8(1))
						testing.expect_value(t, items[0].style_spans[0].start_byte, u32(13))
						testing.expect_value(t, items[0].style_spans[0].end_byte, u32(32))
						testing.expect_value(t, items[0].style_spans[0].style_role, ui.Style_Role.List_Emphasis)
					}
					ui.snapshot_close(&snapshot)
				}
				testing.expect(t, prepared && normal_ok && current_ok && emphasis_ok && search_ok && surface_ok && node_ok && root_ok && copied)
	}
}

@(test)
/* Named slot previews share one value column derived from the widest visible name. */
named_slot_candidate_rows_align_value_previews :: proc(t: ^testing.T) {
	preview := []interaction.Candidate_Annotation{{kind = .Description, text = "value"}}
	view := interaction.Candidate_View {
		source_kind = .Named_Slots,
		rows = []interaction.Candidate_Row {
			{label = "a", annotations = preview},
			{label = "signature", annotations = preview},
		},
	}
	columns, columns_ok := candidate_ui_named_slot_columns(view)
	testing.expect(t, columns_ok)
	storage: [64]u8
	row, row_ok := candidate_ui_named_slot_row_write(view.rows[0], columns, storage[:])
	testing.expect(t, row_ok)
	testing.expect_value(t, row, "a            value")
}

@(test)
/* Status Bar candidate sources reject stale roots and presentation generations. */
status_source_requires_ui_generation :: proc(t: ^testing.T) {
	root := ui.Root_Handle{registry_id = 7, generation = 11}
	commands := Command_Context {
		status_bar_interaction = {
			active = true,
			source_root = root,
			presentation_generation = 13,
		},
	}
	view := interaction.Candidate_View {
		source_kind = .Status_Segments,
		scope_identity = 7,
		scope_generation = 11,
		source_generation = 13,
	}
	testing.expect(t, status_bar_candidate_source_is_current(&commands, view))
	view.source_generation = 14
	testing.expect(t, !status_bar_candidate_source_is_current(&commands, view))
	view.source_generation = 13
	view.scope_generation = 12
	testing.expect(t, !status_bar_candidate_source_is_current(&commands, view))
	status_bar_interaction_reset(&commands.status_bar_interaction)
	view.scope_generation = 11
	testing.expect(t, !status_bar_candidate_source_is_current(&commands, view))
}

/* Verifies numeric result locations preserve source-provided decimal alignment. */
@(test)
result_rows_align_location_context :: proc(t: ^testing.T) {
	short := interaction.Candidate_Row{
		identity = {kind = 1, primary = 1},
		label = "tasks := []Task{}",
		annotations = []interaction.Candidate_Annotation{{kind = .Location, text = "06:02"}},
		action = {kind = .Visit_Result, owner_generation = 1, primary = 1, secondary = 1},
		availability = .Available,
	}
	long := interaction.Candidate_Row{
		identity = {kind = 1, primary = 2},
		label = "fmt.printf()",
		annotations = []interaction.Candidate_Annotation{{kind = .Location, text = "19:60"}},
		action = {kind = .Visit_Result, owner_generation = 1, primary = 1, secondary = 2},
		availability = .Available,
	}
	view := interaction.Candidate_View{
		session_id = 1, session_generation = 1, source_kind = .Results,
		scope_identity = 1, scope_generation = 1, source_generation = 1,
		rows = []interaction.Candidate_Row{short, long}, selected_row = 0, has_selection = true,
	}
	columns, columns_ok := candidate_ui_result_columns(view)
	testing.expect(t, columns_ok)
	short_size, short_size_ok := candidate_ui_result_row_size(short, columns)
	long_size, long_size_ok := candidate_ui_result_row_size(long, columns)
	short_storage, long_storage: [128]u8
	short_text, short_ok := candidate_ui_result_row_write(short, columns, short_storage[:short_size])
	long_text, long_ok := candidate_ui_result_row_write(long, columns, long_storage[:long_size])
	testing.expect(t, short_size_ok && long_size_ok && short_ok && long_ok)
	testing.expect_value(t, short_text, "06:02   tasks := []Task{}")
	testing.expect_value(t, long_text, "19:60   fmt.printf()")
}

/* Verifies result sets with descriptive metadata retain their generic presentation. */
@(test)
result_rows_keep_metadata :: proc(t: ^testing.T) {
	annotations := []interaction.Candidate_Annotation {
		{kind = .Location, text = "function  outer"},
	}
	rows := []interaction.Candidate_Row {
		{label = "inner", annotations = annotations, availability = .Available},
	}
	view := interaction.Candidate_View {
		session_id = 1, session_generation = 1, source_kind = .Results,
		scope_identity = 1, scope_generation = 1, source_generation = 1,
		rows = rows, selected_row = 0, has_selection = true,
	}
	columns, columns_ok := candidate_ui_result_columns(view)
	testing.expect(t, columns_ok)
	testing.expect(t, !columns.tabular_location)
	storage: [64]u8
	text, formatted := candidate_ui_result_row_write(rows[0], columns, storage[:])
	testing.expect(t, formatted)
	testing.expect_value(t, text, "function  outer   inner")
}

/* Filesystem rows keep compact columns, responsive removal, and semantic spans. */
@(test)
filesystem_rows_show_compact_metadata :: proc(t: ^testing.T) {
	directory_annotations := []interaction.Candidate_Annotation {
		{kind = .Filesystem_Permissions, text = "drwxr-xr-x"},
		{kind = .Filesystem_Size, text = "2 KiB"},
		{kind = .Filesystem_Modified, text = "19 hours ago"},
	}
	file_annotations := []interaction.Candidate_Annotation {
		{kind = .Filesystem_Permissions, text = "-rw-r--r--"},
		{kind = .Filesystem_Size, text = "1 KiB"},
		{kind = .Filesystem_Modified, text = "Aug 21 10:49"},
	}
	rows := []interaction.Candidate_Row {
		{label = "src/", annotations = directory_annotations},
		{label = "README.md", annotations = file_annotations},
	}
	view := interaction.Candidate_View {
		session_id = 88,
		session_generation = 1,
		source_kind = .Filesystem_Entries,
		scope_identity = 1,
		scope_generation = 1,
		source_generation = 1,
		rows = rows,
		selected_row = 0,
		has_selection = true,
	}
	wide, wide_ok := candidate_ui_filesystem_columns(view, 80)
	permission_only, permission_ok := candidate_ui_filesystem_columns(view, 21)
	label_only, label_ok := candidate_ui_filesystem_columns(view, 20)
	storage: [80]u8
	text, text_ok := candidate_ui_filesystem_row_write(rows[0], wide, storage[:])
	spans, span_count, spans_ok := candidate_ui_filesystem_row_style_spans(rows[0], wide)
	testing.expect(t, wide_ok && permission_ok && label_ok && text_ok && spans_ok)
	testing.expect(t, wide.permissions && wide.size && wide.modified)
	testing.expect(t, permission_only.permissions && !permission_only.size && !permission_only.modified)
	testing.expect(t, !label_only.permissions && !label_only.size && !label_only.modified)
	testing.expect_value(t, text, "src/       drwxr-xr-x  2 KiB  19 hours ago")
	testing.expect_value(t, span_count, u8(13))
	testing.expect_value(t, spans[0].style_role, ui.Style_Role.Filesystem_Directory)
	testing.expect_value(t, spans[2].style_role, ui.Style_Role.Filesystem_Permission_Read)
	testing.expect_value(t, spans[3].style_role, ui.Style_Role.Filesystem_Permission_Write)
	testing.expect_value(t, spans[4].style_role, ui.Style_Role.Filesystem_Permission_Execute)
	testing.expect_value(t, spans[12].style_role, ui.Style_Role.Filesystem_Metadata)
}

@(test)
/* command_candidate_rows_align_optional_bindings_and_hide_internal_metadata. */
command_rows_align_bindings :: proc(t: ^testing.T) {
	bound_annotations := []interaction.Candidate_Annotation {
		{kind = .Binding, text = "M-x"},
		{kind = .Provider, text = "native"},
		{kind = .Availability, text = "available"},
		{kind = .Description, text = "Bound description"},
	}
	unbound_annotations := []interaction.Candidate_Annotation {
		{kind = .Binding, text = ""},
		{kind = .Provider, text = "racket"},
		{kind = .Availability, text = "available"},
		{kind = .Description, text = "Unbound description"},
	}
	rows := []interaction.Candidate_Row {
		{
			identity = {kind = 1, primary = 1},
			label = "short",
			annotations = bound_annotations,
			action = {kind = .Invoke_Command, owner_generation = 1, primary = 1},
			availability = .Available,
		},
		{
			identity = {kind = 1, primary = 2},
			label = "long-command",
			annotations = unbound_annotations,
			action = {kind = .Invoke_Command, owner_generation = 1, primary = 2},
			availability = .Available,
		},
	}
	view := interaction.Candidate_View {
		session_id = 301,
		session_generation = 1,
		source_kind = .Commands,
		scope_identity = 1,
		scope_generation = 1,
		source_generation = 1,
		rows = rows,
		selected_row = 0,
		has_selection = true,
	}
	registry: ui.Registry
	initialized, _ := ui.registry_init(&registry, 301)
	testing.expect(t, initialized)
	if !initialized do return
	defer ui.registry_close(&registry)
	proposal, prepared, _ := ui.proposal_begin(&registry)
	defer if proposal.state != nil do ui.proposal_abort(&proposal)
	_, normal_ok, _ := ui.proposal_add_style(&proposal, .List_Normal)
	_, current_ok, _ := ui.proposal_add_style(&proposal, .List_Current)
	_, emphasis_ok, _ := ui.proposal_add_style(&proposal, .List_Emphasis, {.Bold})
	list, projected, _ := proposal_project_candidate_list(
		&proposal, view, 2, context.temp_allocator,
	)
	surface, surface_ok, _ := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = 301,
			view = list,
			focusable = true,
			visible = true,
			required_profile = 1,
			geometry = {height = 2, width = 80},
		},
	)
	node, node_ok, _ := ui.proposal_add_surface_node(&proposal, surface)
	root_ok, _ := ui.proposal_set_root(&proposal, node, surface)
	root, published, _ := ui.proposal_publish(&registry, &proposal, candidate_ui_test_renderer())
	snapshot, copied, _ := ui.registry_snapshot(&registry, root, candidate_ui_test_renderer())
	testing.expect(t, prepared && normal_ok && current_ok && emphasis_ok && projected &&
		surface_ok && node_ok && root_ok && published && copied)
	if !copied do return
	defer ui.snapshot_close(&snapshot)
	state, state_ok := ui.snapshot_view(&snapshot)
	items, items_ok := ui.snapshot_list_items(state, state.views[list.slot])
	bound, bound_ok := ui.snapshot_list_item_text(state, items[0])
	unbound, unbound_ok := ui.snapshot_list_item_text(state, items[1])
	testing.expect(t, state_ok && items_ok && bound_ok && unbound_ok)
	testing.expect_value(t, bound, "short         [M-x]  Bound description")
	testing.expect_value(t, unbound, "long-command         Unbound description")
	testing.expect_value(t, items[0].emphasis_bytes, u32(len("short")))
	testing.expect_value(t, items[1].emphasis_bytes, u32(len("long-command")))
}

@(test)
/* candidate_composition_places_prompt_and_rows_below_the_displaced_editor_status. */
panel_places_rows_below_status :: proc(t: ^testing.T) {
	annotations := [3][4]interaction.Candidate_Annotation_Definition {
		{{kind = .Binding, text = "C-a"}, {kind = .Provider, text = "native"},
			{kind = .Availability, text = "available"}, {kind = .Description, text = "Alpha"}},
		{{kind = .Binding, text = ""}, {kind = .Provider, text = "native"},
			{kind = .Availability, text = "available"}, {kind = .Description, text = "Beta"}},
		{{kind = .Binding, text = "C-g"}, {kind = .Provider, text = "native"},
			{kind = .Availability, text = "available"}, {kind = .Description, text = "Gamma"}},
	}
	descriptors: [3]interaction.Candidate_Descriptor_Definition
	labels := [3]string{"alpha", "beta", "gamma"}
	for &descriptor, index in descriptors {
		descriptor = {
			identity = {kind = 1, primary = u64(index + 1)},
			label = labels[index],
			annotations = annotations[index][:],
			action = {kind = .Invoke_Command, owner_generation = 1, primary = u64(index + 1)},
			availability = .Available,
		}
	}
	session: interaction.Candidate_Session
	_, session_ok, _ := interaction.candidate_session_init(
		&session,
		interaction.Candidate_Config {
			session_id = 401,
			limits = interaction.DEFAULT_CANDIDATE_LIMITS,
			persistent_allocator = context.allocator,
			temporary_allocator = context.temp_allocator,
		},
		interaction.Candidate_Source_Definition {
			kind = .Commands,
			scope_identity = 1,
			scope_generation = 1,
			source_generation = 1,
			descriptors = descriptors[:],
		},
	)
	testing.expect(t, session_ok)
	if !session_ok do return
	defer interaction.candidate_session_close(&session)
	commands := Command_Context {
		candidate_ui = {
			session = session,
			return_target = {kind = .Primary_View},
			next_presentation_generation = 1,
		},
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
	}
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 12}
	editor_rows, candidate_rows, rows_ok := candidate_ui_editor_rows(&commands, constraints, 1)
	testing.expect(t, rows_ok)
	testing.expect_value(t, editor_rows, u32(8))
	testing.expect_value(t, candidate_rows, u32(3))
	registry: ui.Registry
	initialized, _ := ui.registry_init(&registry, 401)
	testing.expect(t, initialized)
	if !initialized do return
	defer ui.registry_close(&registry)
	proposal, prepared, _ := ui.proposal_begin(&registry)
	defer if proposal.state != nil do ui.proposal_abort(&proposal)
	_, normal_ok, _ := ui.proposal_add_style(&proposal, .List_Normal)
	_, current_ok, _ := ui.proposal_add_style(&proposal, .List_Current)
	_, emphasis_ok, _ := ui.proposal_add_style(&proposal, .List_Emphasis, {.Bold})
	_, status_normal_ok, _ := ui.proposal_add_style(&proposal, .Status_Normal)
	_, status_active_ok, _ := ui.proposal_add_style(&proposal, .Status_Active)
	base_view, base_view_ok, _ := ui.proposal_project_list_view(
		&proposal,
		ui.List_Projection_Request {
			model = {owner_id = 7, model_id = 7, generation = 1},
			position = {presentation_generation = 1, selection_owner = .View,
				current_item = 0, viewport_items = editor_rows},
		},
		[]ui.List_Item_Definition {{id = 1, text = "editor", action = {owner_id = 7, action_id = 1, generation = 1}}},
	)
	base_surface, base_surface_ok, _ := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = 7,
			view = base_view,
			focusable = true,
			visible = true,
			required_profile = 1,
			geometry = {height = i32(editor_rows), width = 80},
		},
	)
	base_node, base_node_ok, _ := ui.proposal_add_surface_node(&proposal, base_surface)
	_, base_status_ok, _ := ui.proposal_add_status(
		&proposal,
		ui.Status_Region_Descriptor {
			owner_id = 7,
			placement = .Attached,
			surface = base_surface,
			rows = 2,
			geometry = {row = i32(editor_rows - 2), height = 2, width = 80},
			style_role = .Status_Normal,
		},
		"editor status",
	)
	composition, composed, compose_failure := proposal_compose_candidate_ui(
		&proposal,
		&commands,
		base_node,
		base_surface,
		constraints,
		editor_rows,
		candidate_rows,
		1,
	)
	testing.expectf(t, composed, "candidate composition failed: %v", compose_failure.code)
	if !composed do return
	root, published, publish_failure := ui.proposal_publish(&registry, &proposal, candidate_ui_test_renderer())
	testing.expectf(t, published, "candidate publication failed: %v", publish_failure.code)
	if !published do return
	captured, capture_failure := ui.registry_capture_focus(&registry, composition.input_surface)
	testing.expectf(t, captured, "candidate focus failed: %v", capture_failure.code)
	snapshot, copied, copy_failure := ui.registry_snapshot(&registry, root, candidate_ui_test_renderer())
	testing.expectf(t, copied, "candidate snapshot failed: %v", copy_failure.code)
	testing.expect(t, prepared && normal_ok && current_ok && emphasis_ok && status_normal_ok &&
		status_active_ok && base_view_ok && base_surface_ok && base_node_ok && base_status_ok &&
		composed && published && captured && copied)
	if !copied do return
	defer ui.snapshot_close(&snapshot)
	state, state_ok := ui.snapshot_view(&snapshot)
	testing.expect(t, state_ok)
	if !state_ok do return
	testing.expect_value(t, state.surfaces[base_surface.slot].geometry.height, i32(8))
	testing.expect_value(t, state.surfaces[composition.input_surface.slot].geometry.row, i32(8))
	list_row_found := false
	for surface in state.surfaces {
		if surface.owner_id == CANDIDATE_UI_OWNER_ID && surface.view !=
		   state.surfaces[composition.input_surface.slot].view {
			testing.expect_value(t, surface.geometry.row, i32(9))
			testing.expect_value(t, surface.geometry.height, i32(3))
			list_row_found = true
		}
	}
	testing.expect(t, list_row_found)
	testing.expect_value(t, state.status_regions[0].geometry.row, i32(6))
	testing.expect_value(t, state.status_regions[1].geometry.row, i32(8))
	testing.expect_value(t, state.focus.target, composition.input_surface)

	too_small := display.Viewport_Constraints{width_cells = 80, height_rows = 4}
	_, _, small_ok := candidate_ui_editor_rows(&commands, too_small, 1)
	testing.expect(t, !small_ok)
	minimum := display.Viewport_Constraints{width_cells = 80, height_rows = 5}
	minimum_editor_rows, minimum_candidate_rows, minimum_ok :=
		candidate_ui_editor_rows(&commands, minimum, 1)
	testing.expect(t, minimum_ok)
	testing.expect_value(t, minimum_editor_rows, u32(4))
	testing.expect_value(t, minimum_candidate_rows, u32(0))
	commands.candidate_ui.session = {}
}

@(test)
/* candidate_panel_height_caps_header_and_rows_at_half_the_viewport. */
panel_caps_at_half_viewport :: proc(t: ^testing.T) {
	testing.expect_value(t, candidate_ui_candidate_row_limit(16), u32(7))
	testing.expect_value(t, candidate_ui_candidate_row_limit(15), u32(6))
	testing.expect_value(t, candidate_ui_candidate_row_limit(4), u32(1))
	testing.expect_value(t, candidate_ui_candidate_row_limit(2), u32(0))
}

@(test)
/* Verifies input roots preserve Unicode, focus geometry, and resource accounting. */
list_input_keeps_focus_geometry :: proc(t: ^testing.T) {
	sources := []interaction.Candidate_Source_Kind {
		.Commands,
		.Session_Buffers,
		.Project_Buffers,
		.Project_Files,
		.Dir_Files,
		.Projects,
		.Workspaces,
		.Named_Locations,
		.Named_Slots,
		.Language_Diagnostics,
		.Results,
		.Status_Segments,
		.Package_Catalogs,
		.Packages,
		.Package_Catalog_Diagnostics,
		.Personal_Command_Results,
	}
	for source, source_index in sources {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		allocator := mem.tracking_allocator(&tracking)
		registry: ui.Registry
		initialized, _ := ui.registry_init(
			&registry,
			ui.Registry_ID(90 + source_index),
			ui.DEFAULT_RESOURCE_LIMITS,
			allocator,
		)
		testing.expect(t, initialized)
		if !initialized {
			mem.tracking_allocator_destroy(&tracking)
			return
		}
		rows: [17]interaction.Candidate_Row
		command_available := []interaction.Candidate_Annotation {
			{kind = .Binding, text = "M-x"},
			{kind = .Provider, text = "native"},
			{kind = .Availability, text = "available"},
			{kind = .Description, text = "Run λ"},
		}
		command_unavailable := []interaction.Candidate_Annotation {
			{kind = .Binding, text = "M-x"},
			{kind = .Provider, text = "native"},
			{kind = .Availability, text = "unavailable: λ blocked"},
			{kind = .Description, text = "Run λ"},
		}
		buffer_annotations := []interaction.Candidate_Annotation {
			{kind = .Document_Path, text = "/tmp/λ"},
			{kind = .Modified_State, text = "modified"},
			{kind = .Generic, text = "file"},
		}
		file_annotations := []interaction.Candidate_Annotation {{
			kind = .Project_Member,
			text = "λ member",
		}}
		slot_annotations := []interaction.Candidate_Annotation {{
			kind = .Description,
			text = "Text slot",
		}}
		diagnostic_annotations := []interaction.Candidate_Annotation {
			{kind = .Severity, text = "warning"},
			{kind = .Location, text = "/tmp/λ.odin"},
		}
		for &row, index in rows {
			row = {
				identity = {kind = u16(index + 1), primary = u64(index + 10)},
				label = "λ界🙂 candidate",
				action = {kind = .Open_Document, owner_generation = 7, primary = u64(index + 1)},
				availability = .Available,
			}
			if source == .Named_Locations {
				row.action.kind = .Visit_Location
			} else if source == .Named_Slots {
				row.action.kind = .Select_Named_Slot
			} else if source == .Results {
				row.action.kind = .Visit_Result
			} else if source == .Package_Catalogs || source == .Packages ||
			          source == .Package_Catalog_Diagnostics {
				row.action.kind = .Select_Package_Catalog
			} else if source == .Personal_Command_Results {
				row.action.kind = .Open_Command_Candidate
			}
			switch source {
			case .Commands:
				row.annotations = command_available
			case .Session_Buffers, .Project_Buffers:
				row.annotations = buffer_annotations
			case .Project_Files, .Projects, .Workspaces, .Named_Locations:
				row.annotations = file_annotations
			case .Named_Slots:
				row.annotations = slot_annotations
			case .Dir_Files:
			case .Language_Diagnostics:
				row.annotations = diagnostic_annotations
			case .Results:
				row.annotations = diagnostic_annotations[1:]
			case .Status_Segments, .Package_Catalogs, .Packages:
				row.annotations = slot_annotations
			case .Invalid, .Themes, .Interaction_Profiles, .Test, .Filesystem_Entries,
			     .Package_Catalog_Diagnostics, .Personal_Command_Results:
			}
		}
		if source == .Commands {
			rows[12].annotations = command_unavailable
			rows[12].availability = .Unavailable
		}
		candidate := interaction.Candidate_View {
			session_id = interaction.Candidate_Session_ID(200 + source_index),
			session_generation = 9,
			source_kind = source,
			scope_identity = 2,
			scope_generation = 3,
			source_generation = 4,
			query = "λ界🙂",
			rows = rows[:],
			selected_row = 12,
			has_selection = true,
		}
		proposal, prepared, _ := ui.proposal_begin(&registry)
		_, normal_ok, _ := ui.proposal_add_style(&proposal, .List_Normal)
		_, current_ok, _ := ui.proposal_add_style(&proposal, .List_Current, {.Reverse})
		_, emphasis_ok, _ := ui.proposal_add_style(&proposal, .List_Emphasis, {.Bold})
		_, status_ok, _ := ui.proposal_add_style(&proposal, .Status_Active, {.Bold})
		list_view, list_ok, _ := proposal_project_candidate_list(
			&proposal,
			candidate,
			4,
			allocator,
		)
		input_view, input_ok, _ := ui.proposal_project_input(
			&proposal,
			ui.Input_Projection_Request {
				model = {owner_id = 8, model_id = 9, generation = 10},
				presentation_generation = 9,
				backing_generation = 9,
				cursor_offset = 9,
				first_visible_byte = 2,
				viewport_bytes = 8,
				validation = .Valid,
			},
			candidate.query,
		)
		list_surface, list_surface_ok, _ := ui.proposal_add_surface(
			&proposal,
			ui.Surface_Descriptor {
				owner_id = 8,
				view = list_view,
				focusable = true,
				visible = true,
				required_profile = 1,
				geometry = {height = 4, width = 40},
			},
		)
		input_surface, input_surface_ok, _ := ui.proposal_add_surface(
			&proposal,
			ui.Surface_Descriptor {
				owner_id = 8,
				view = input_view,
				focusable = true,
				visible = true,
				required_profile = 1,
				geometry = {row = 4, column = 10, height = 1, width = 30},
			},
		)
		list_node, list_node_ok, _ := ui.proposal_add_surface_node(&proposal, list_surface)
		input_node, input_node_ok, _ := ui.proposal_add_surface_node(&proposal, input_surface)
		root_node, split_ok, _ := ui.proposal_add_split(
			&proposal,
			list_node,
			input_node,
			.Above_Below,
			4,
			1,
		)
		_, status_region_ok, _ := ui.proposal_add_status(
			&proposal,
			ui.Status_Region_Descriptor {
				owner_id = 8,
				placement = .Root_Edge,
				rows = 1,
				geometry = {row = 4, height = 1, width = 40},
				style_role = .Status_Active,
				active = true,
			},
			"Candidates ",
		)
		root_ok, _ := ui.proposal_set_root(&proposal, root_node, list_surface)
		root, published, publish_failure := ui.proposal_publish(
			&registry,
			&proposal,
			candidate_ui_test_renderer(),
		)
		testing.expectf(
			t,
			list_ok && input_ok && list_surface_ok && input_surface_ok && list_node_ok &&
			input_node_ok && split_ok && status_region_ok && root_ok,
			"candidate root preparation failed for source %v",
			source,
		)
		testing.expectf(t, published, "candidate root publish failed: %v", publish_failure)
		captured, _ := ui.registry_capture_focus(&registry, input_surface)
		snapshot, copied, _ := ui.registry_snapshot(
			&registry,
			root,
			candidate_ui_test_renderer(),
			allocator,
		)
		if copied {
			state, state_ok := ui.snapshot_view(&snapshot)
			input, input_value_ok := ui.snapshot_input_value(state, state.views[input_view.slot])
			items, items_ok := ui.snapshot_list_items(state, state.views[list_view.slot])
			selected, selected_ok := ui.snapshot_list_item_text(state, items[12])
			status_text, status_text_ok := ui.snapshot_status_content(state, state.status_regions[0])
			testing.expect(t, state_ok && input_value_ok && items_ok && selected_ok && status_text_ok)
			testing.expect_value(t, input, candidate.query)
			if source == .Commands {
				testing.expect(t, strings.contains(selected, "Run λ"))
				testing.expect(t, !strings.contains(selected, "native"))
				testing.expect(t, !strings.contains(selected, "unavailable"))
			} else {
				testing.expect(t, strings.contains(selected, "λ"))
			}
			testing.expect_value(t, status_text, "Candidates ")
			testing.expect_value(t, state.views[list_view.slot].list.position.first_visible_item, u32(9))
			testing.expect_value(t, state.focus.target, input_surface)
			testing.expect_value(t, state.accounting.list_items, u32(17))
			testing.expect_value(t, state.accounting.input_bytes, u32(9))
			testing.expect_value(t, state.surfaces[input_surface.slot].geometry.row, i32(4))
			ui.snapshot_close(&snapshot)
		}
		return_surface, released, _ := ui.registry_release_focus(&registry)
		closed, _ := ui.registry_close(&registry)
		cleanup_bytes := tracking.current_memory_allocated
		mem.tracking_allocator_destroy(&tracking)
		testing.expect(
			t,
			prepared && normal_ok && current_ok && emphasis_ok && status_ok && list_ok && input_ok &&
			list_surface_ok && input_surface_ok && list_node_ok && input_node_ok &&
			split_ok && status_region_ok && root_ok && published && captured && copied &&
			released && closed,
		)
		testing.expect_value(t, return_surface, list_surface)
		testing.expect_value(t, cleanup_bytes, i64(0))
	}
}

@(test)
/* Ensures stale bounds and allocation faults cannot partially replace a candidate list. */
list_rejects_stale_and_alloc_faults :: proc(t: ^testing.T) {
	registry: ui.Registry
	initialized, _ := ui.registry_init(&registry, 98)
	testing.expect(t, initialized)
	if !initialized do return
	defer ui.registry_close(&registry)
	proposal, prepared, _ := ui.proposal_begin(&registry)
	_, normal_ok, _ := ui.proposal_add_style(&proposal, .List_Normal)
	_, current_ok, _ := ui.proposal_add_style(&proposal, .List_Current)
	row := interaction.Candidate_Row {
		identity = {kind = 1, primary = 2},
		label = "candidate",
		action = {kind = .Open_Document, owner_generation = 1, primary = 1},
		availability = .Available,
	}
	view := interaction.Candidate_View {
		session_id = 1,
		session_generation = 0,
		source_kind = .Commands,
		scope_identity = 2,
		scope_generation = 3,
		source_generation = 4,
		rows = []interaction.Candidate_Row{row},
		selected_row = 0,
		has_selection = true,
	}
	_, stale_ok, stale_failure := proposal_project_candidate_list(
		&proposal, view, 1, context.temp_allocator,
	)
	view.session_generation = 1
	_, zero_ok, zero_failure := proposal_project_candidate_list(
		&proposal, view, 0, context.temp_allocator,
	)
	_, overflow_ok, overflow_failure := proposal_project_candidate_list(
		&proposal, view, ui.MAX_LIST_ITEMS + 1, context.temp_allocator,
	)
	failing := Candidate_UI_Failing_Allocator {
		backing = context.temp_allocator,
		fail_after = 0,
	}
	_, allocation_ok, allocation_failure := proposal_project_candidate_list(
		&proposal,
		view,
		1,
		candidate_ui_failing_allocator(&failing),
	)
	testing.expect(t, prepared && normal_ok && current_ok)
	testing.expect(t, !stale_ok && !zero_ok && !overflow_ok && !allocation_ok)
	testing.expect_value(t, stale_failure.code, ui.Failure_Code.Invalid_List_View)
	testing.expect_value(t, zero_failure.code, ui.Failure_Code.Invalid_List_View)
	testing.expect_value(t, overflow_failure.code, ui.Failure_Code.Invalid_List_View)
	testing.expect_value(t, allocation_failure.code, ui.Failure_Code.Allocation)
	_, active_ok, _ := ui.registry_stats(&registry)
	testing.expect(t, !active_ok)
	ui.proposal_abort(&proposal)
}

@(private)
candidate_ui_test_renderer :: proc() -> ui.Renderer_Profile {
	return ui.Renderer_Profile {
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

@(private)
Candidate_UI_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
candidate_ui_failing_allocator :: proc(data: ^Candidate_UI_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = candidate_ui_failing_allocator_proc, data = data}
}

@(private)
candidate_ui_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := cast(^Candidate_UI_Failing_Allocator)allocator_data
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
