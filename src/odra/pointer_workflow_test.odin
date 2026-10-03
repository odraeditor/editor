// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../display"
import "../editor"
import "../editor_session"
import "../interaction"
import "../layout"
import "../product_module"
import "../terminal_emulator"
import "../terminal_session"
import "../ui"
import editor_view "../view"
import "base:runtime"
import "core:strings"
import "core:testing"
import "core:time"

pointer_darek_selection_operation: product_module.Operation
pointer_darek_invoked_context_actions: bool
pointer_maksym_selection_operation: product_module.Operation

@(test)
/* Plans one semantic owner transfer and rejects Darek padding without an item. */
pointer_semantic_focus_plan_preserves_one_owner :: proc(t: ^testing.T) {
	acquire, acquire_ok := pointer_semantic_focus_plan(false, false, true, true)
	release, release_ok := pointer_semantic_focus_plan(true, true, false, false)
	retained, retained_ok := pointer_semantic_focus_plan(true, false, true, true)
	surface, surface_ok := pointer_semantic_focus_plan(false, false, false, false)
	_, padding_ok := pointer_semantic_focus_plan(true, false, false, true)

	testing.expect(t, acquire_ok && acquire.acquire_darek && !acquire.release_darek)
	testing.expect_value(t, acquire.target, Pointer_Semantic_Focus_Owner.Darek)
	testing.expect(t, release_ok && release.release_darek && !release.acquire_darek)
	testing.expect_value(t, release.target, Pointer_Semantic_Focus_Owner.Pane)
	testing.expect(t, retained_ok && !retained.release_darek && !retained.acquire_darek)
	testing.expect_value(t, retained.previous, Pointer_Semantic_Focus_Owner.Darek)
	testing.expect(t, surface_ok && !surface.release_darek && !surface.acquire_darek)
	testing.expect_value(t, surface.target, Pointer_Semantic_Focus_Owner.Surface)
	testing.expect(t, !padding_ok)
}

@(test)
/* Admits Darek item focus only from the exact current model and presentation generation. */
pointer_darek_focus_requires_current_semantic_hit :: proc(t: ^testing.T) {
	commands := Command_Context{}
	commands.product_module_workflow.workspace_hierarchy_available = true
	commands.product_module_workflow.tree_projection = {
		definitions = []ui.Tree_Node_Definition {{
			id = 11,
			action = {
				owner_id = PRODUCT_MODULE_DAREK_UI_OWNER_ID,
				action_id = 11,
				generation = 7,
			},
		}},
		visible = true,
		generation = 7,
	}
	surface_handle := ui.Object_Handle {
		registry_id = 1,
		object_id = 2,
		root_generation = 3,
		slot = 0,
		slot_generation = 1,
	}
	surfaces := [1]ui.Surface_Descriptor {{
		handle = surface_handle,
		owner_id = PRODUCT_MODULE_DAREK_UI_OWNER_ID,
		visible = true,
		focusable = true,
	}}
	snapshot := ui.Snapshot_View{surfaces = surfaces[:]}
	hit := ui.Hit_Result {
		kind = .Content,
		surface = surface_handle,
		item = {
			kind = .Tree,
			projection = {registry_id = 1, object_id = 3, root_generation = 3, slot = 0, slot_generation = 1},
			model = {
				owner_id = PRODUCT_MODULE_DAREK_UI_OWNER_ID,
				model_id = PRODUCT_MODULE_DAREK_UI_MODEL_ID,
				generation = 7,
			},
			item_id = 11,
			action = {
				owner_id = PRODUCT_MODULE_DAREK_UI_OWNER_ID,
				action_id = 11,
				generation = 7,
			},
			presentation_generation = 7,
			projection_index = 0,
		},
	}

	testing.expect(t, pointer_hit_is_darek_surface(&commands, snapshot, hit))
	testing.expect(t, pointer_hit_is_current_darek_item(&commands, hit))
	hit.item.model.generation = 6
	testing.expect(t, !pointer_hit_is_current_darek_item(&commands, hit))
	hit.item.model.generation = 7
	hit.item.presentation_generation = 6
	testing.expect(t, !pointer_hit_is_current_darek_item(&commands, hit))
	hit.item.presentation_generation = 7
	hit.item.action.generation = 6
	testing.expect(t, !pointer_hit_is_current_darek_item(&commands, hit))
	hit.item.action.generation = 7
	hit.item.action.action_id = 12
	testing.expect(t, !pointer_hit_is_current_darek_item(&commands, hit))
	hit.item.action.action_id = 11
	hit.item.projection_index = 1
	testing.expect(t, !pointer_hit_is_current_darek_item(&commands, hit))
	hit.item.projection_index = 0
	hit.kind = .Surface
	testing.expect(t, !pointer_hit_is_current_darek_item(&commands, hit))
}

@(test)
/* Selects one exact Darek row through the module boundary without activation. */
pointer_darek_selection_uses_exact_module_row :: proc(t: ^testing.T) {
	pointer_darek_selection_operation = .Invalid
	commands := Command_Context{}
	commands.product_module_workflow.workspace_hierarchy_available = true
	commands.product_module_workflow.workspace_hierarchy_runtime = {
		descriptor = {call = pointer_darek_selection_test_call},
		instance = u64(uintptr(&commands)),
		lifecycle = .Active,
	}
	commands.product_module_workflow.tree_projection = {
		definitions = []ui.Tree_Node_Definition {{id = 11}, {id = 22}},
		position = {current_item = 0, presentation_generation = 7},
		visible = true,
		generation = 7,
	}

	result, failure := command_context_pointer_select_darek_item(&commands, 22, 1, {})
	stale_result, stale_failure := command_context_pointer_select_darek_item(
		&commands, 11, 1, {},
	)

	testing.expect(t, result.changed && failure.stage == .None)
	testing.expect_value(t, pointer_darek_selection_operation, product_module.Operation.Select)
	testing.expect_value(t, commands.product_module_workflow.tree_projection.position.current_item, i32(1))
	testing.expect(t, !stale_result.changed)
	testing.expect_value(t, stale_failure.stage, App_Stage.Command_Dispatch)
}

@(test)
/* Selects the exact Darek row before requesting its contextual command surface. */
pointer_darek_context_actions_select_before_invocation :: proc(t: ^testing.T) {
	pointer_darek_selection_operation = .Invalid
	pointer_darek_invoked_context_actions = false
	definitions := [1]interaction.Command_Definition {{
		name = "darek-context-actions",
		route = {provider = 1, operation = 1},
		implementation = .Native,
		invocation = .Ordinary,
		text_requirement = .Prohibited,
		effects = {.View, .Lifecycle},
		description = "List commands applicable to the selected Darek node.",
		interactive = true,
		provenance = {provider = "test", source = "pointer-workflow"},
	}}
	registry: interaction.Command_Registry
	registered, registry_failure := interaction.command_registry_init(
		&registry, 1, definitions[:], context.allocator,
	)
	testing.expectf(t, registered, "Darek context command registry failed with %v", registry_failure.code)
	if !registered do return
	defer interaction.command_registry_close(&registry)
	commands := Command_Context {
		registry = &registry,
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
	}
	commands.product_module_workflow.workspace_hierarchy_available = true
	commands.product_module_workflow.workspace_hierarchy_runtime = {
		descriptor = {call = pointer_darek_selection_test_call},
		instance = u64(uintptr(&commands)),
		lifecycle = .Active,
	}
	commands.product_module_workflow.tree_projection = {
		definitions = []ui.Tree_Node_Definition {{id = 11}, {id = 22}},
		position = {current_item = 0, presentation_generation = 7},
		visible = true,
		generation = 7,
	}

	result, failure := command_context_pointer_present_darek_actions(
		&commands, 22, 1, {},
	)

	testing.expect(t, result.changed && failure.stage == .None)
	testing.expect_value(t, commands.product_module_workflow.tree_projection.position.current_item, i32(1))
	testing.expect(t, pointer_darek_invoked_context_actions)
}

/* pointer_darek_selection_test_call provides the Darek pointer test module. */
pointer_darek_selection_test_call :: proc "c" (
	instance: u64,
	operation: product_module.Operation,
	input: ^u8,
	input_length: u64,
	_: ^u8,
	_: u64,
	output_length: ^u64,
) -> product_module.Status {
	context = runtime.default_context()
	if output_length != nil do output_length^ = 0
	pointer_darek_selection_operation = operation
	if instance == 0 || input == nil {
		return .Invalid_Argument
	}
	commands := (^Command_Context)(uintptr(instance))
	if operation == .Invoke {
		header_bytes :: size_of(product_module.Invocation_Request_Header)
		if input_length < u64(header_bytes) do return .Invalid_Argument
		header := (^product_module.Invocation_Request_Header)(rawptr(input))
		if header.schema_version != product_module.INVOCATION_REQUEST_SCHEMA_VERSION ||
		   header.name_length != u32(input_length - u64(header_bytes)) {
			return .Invalid_Argument
		}
		name := string(([^]u8)(rawptr(input))[header_bytes:int(input_length)])
		pointer_darek_invoked_context_actions = name == "darek-context-actions"
		return .Ok if pointer_darek_invoked_context_actions else .Unavailable
	}
	if operation != .Select || input_length != u64(size_of(product_module.Selection_Request)) {
		return .Invalid_Argument
	}
	request := (^product_module.Selection_Request)(rawptr(input))
	if request.schema_version != product_module.UI_TREE_PANEL_SCHEMA_VERSION ||
	   request.item_id == 0 {
		return .Invalid_Argument
	}
	projection := &commands.product_module_workflow.tree_projection
	for definition, index in projection.definitions {
		if u64(definition.id) == request.item_id {
			projection.position.current_item = i32(index)
			projection.generation += 1
			projection.position.presentation_generation = projection.generation
			return .Ok
		}
	}
	return .Stale
}

@(test)
/* Selects Maksym only from exact current model, action, and projection evidence. */
pointer_maksym_selection_uses_exact_module_row :: proc(t: ^testing.T) {
	pointer_maksym_selection_operation = .Invalid
	commands := Command_Context{}
	commands.product_module_workflow.active = true
	commands.product_module_workflow.active_role = .File_Management
	commands.product_module_workflow.file_management_available = true
	commands.product_module_workflow.file_management_runtime = {
		descriptor = {call = pointer_maksym_selection_test_call},
		instance = u64(uintptr(&commands)),
		lifecycle = .Active,
	}
	commands.product_module_workflow.projection = {
		definitions = []ui.List_Item_Definition {
			{id = 1, passive = true},
			{
				id = 44,
				action = {owner_id = 99, action_id = 44, generation = 7},
			},
		},
		position = {current_item = 0, presentation_generation = 7, selection_owner = .Model},
		generation = 7,
	}
	hit := ui.Semantic_Item_Hit {
		kind = .List,
		model = {
			owner_id = PRODUCT_MODULE_UI_OWNER_ID,
			model_id = PRODUCT_MODULE_UI_MODEL_ID,
			generation = 7,
		},
		item_id = 44,
		action = {owner_id = 99, action_id = 44, generation = 7},
		presentation_generation = 7,
		projection_index = 1,
	}

	testing.expect(t, pointer_hit_is_current_maksym_item(&commands, hit))
	stale := hit
	stale.projection_index = 0
	testing.expect(t, !pointer_hit_is_current_maksym_item(&commands, stale))
	stale = hit
	stale.action.action_id = 45
	testing.expect(t, !pointer_hit_is_current_maksym_item(&commands, stale))
	stale = hit
	stale.model.generation = 6
	testing.expect(t, !pointer_hit_is_current_maksym_item(&commands, stale))

	result, failure := command_context_pointer_select_maksym_item(&commands, hit, {})
	testing.expect(t, result.changed && failure.stage == .None)
	testing.expect_value(t, pointer_maksym_selection_operation, product_module.Operation.Select)
	testing.expect_value(t, commands.product_module_workflow.projection.position.current_item, i32(1))
	testing.expect(t, !pointer_hit_is_current_maksym_item(&commands, hit))
}

/* pointer_maksym_selection_test_call provides the Maksym pointer test module. */
pointer_maksym_selection_test_call :: proc "c" (
	instance: u64,
	operation: product_module.Operation,
	input: ^u8,
	input_length: u64,
	_: ^u8,
	_: u64,
	output_length: ^u64,
) -> product_module.Status {
	context = runtime.default_context()
	if output_length != nil do output_length^ = 0
	pointer_maksym_selection_operation = operation
	if instance == 0 || operation != .Select || input == nil ||
	   input_length != u64(size_of(product_module.Selection_Request)) {
		return .Invalid_Argument
	}
	commands := (^Command_Context)(uintptr(instance))
	request := (^product_module.Selection_Request)(rawptr(input))
	if request.schema_version != product_module.UI_LIST_SCHEMA_VERSION || request.item_id == 0 {
		return .Invalid_Argument
	}
	projection := &commands.product_module_workflow.projection
	for definition, index in projection.definitions {
		if u64(definition.id) != request.item_id do continue
		projection.position.current_item = i32(index)
		projection.generation += 1
		projection.position.presentation_generation = projection.generation
		for &current in projection.definitions do current.action.generation = projection.generation
		return .Ok
	}
	return .Stale
}

@(test)
/* Focuses another pane from its attached non-text status region. */
pointer_focuses_pane_from_status :: proc(t: ^testing.T) {
	fixture: Pointer_Focus_Test_Fixture
	if !pointer_focus_test_init(t, &fixture) do return
	defer pointer_focus_test_close(t, &fixture)
	target, target_ok := pointer_focus_test_target(t, &fixture, fixture.second)
	if !target_ok do return

	result, failure := command_context_pointer_focus(
		&fixture.commands,
		&fixture.session,
		fixture.handle,
		pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column),
	)
	visible, visible_ok, _ := editor_session.session_visible_target(
		&fixture.session,
		fixture.handle,
	)
	layout_handle, layout_ok, _ := layout.registry_handle(&fixture.commands.layout_registry)
	after, snapshot_ok, _ := layout.registry_snapshot(&fixture.commands.layout_registry, layout_handle)
	active, active_ok := command_context_layout_active_node(&after)

	testing.expect(t, result.changed && failure.stage == .None)
	testing.expect(t, visible_ok && layout_ok && snapshot_ok && active_ok)
	testing.expect_value(t, visible.entry, fixture.second)
	testing.expect_value(t, active.entry, fixture.second)
	testing.expect_value(t, fixture.commands.layout_entry, fixture.second)
	testing.expect_value(t, fixture.commands.current_entry, fixture.second)
}

@(test)
/* Preserves the prior semantic owner when Darek release cannot be admitted. */
pointer_focus_release_failure_is_atomic :: proc(t: ^testing.T) {
	fixture: Pointer_Focus_Test_Fixture
	if !pointer_focus_test_init(t, &fixture) do return
	defer pointer_focus_test_close(t, &fixture)
	target, target_ok := pointer_focus_test_target(t, &fixture, fixture.second)
	if !target_ok do return
	fixture.commands.product_module_workflow.tree_projection = {
		visible = true,
		focused = true,
		generation = 1,
	}
	fixture.commands.product_module_workflow.workspace_hierarchy_available = true

	result, failure := command_context_pointer_focus(
		&fixture.commands,
		&fixture.session,
		fixture.handle,
		pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column),
	)
	visible, visible_ok, _ := editor_session.session_visible_target(
		&fixture.session,
		fixture.handle,
	)
	layout_handle, layout_ok, _ := layout.registry_handle(&fixture.commands.layout_registry)
	after, snapshot_ok, _ := layout.registry_snapshot(&fixture.commands.layout_registry, layout_handle)
	active, active_ok := command_context_layout_active_node(&after)

	testing.expect(t, !result.changed)
	testing.expect_value(t, failure.stage, App_Stage.Command_Dispatch)
	testing.expect(t, visible_ok && layout_ok && snapshot_ok && active_ok)
	testing.expect_value(t, visible.entry, fixture.first)
	testing.expect_value(t, active.entry, fixture.first)
	testing.expect(t, fixture.commands.product_module_workflow.tree_projection.focused)
}

@(test)
/* Rejects stale or unsupported input without changing confirmed pane focus. */
pointer_rejects_stale_and_unsupported :: proc(t: ^testing.T) {
	fixture: Pointer_Focus_Test_Fixture
	if !pointer_focus_test_init(t, &fixture) do return
	defer pointer_focus_test_close(t, &fixture)
	target, target_ok := pointer_focus_test_target(t, &fixture, fixture.second)
	if !target_ok do return

	_, first_failure := command_context_pointer_focus(
		&fixture.commands,
		&fixture.session,
		fixture.handle,
		pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column),
	)
	_, stale_failure := command_context_pointer_focus(
		&fixture.commands,
		&fixture.session,
		fixture.handle,
		pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column),
	)
	malformed := pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column)
	malformed.capabilities = {.Cell_Coordinates}
	_, malformed_failure := command_context_pointer_focus(
		&fixture.commands,
		&fixture.session,
		fixture.handle,
		malformed,
	)
	release := pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column)
	release.action = .Release
	release.capabilities += {.Release}
	release_result, release_failure := command_context_pointer_focus(
		&fixture.commands,
		&fixture.session,
		fixture.handle,
		release,
	)
	visible, visible_ok, _ := editor_session.session_visible_target(
		&fixture.session,
		fixture.handle,
	)
	layout_handle, layout_ok, _ := layout.registry_handle(&fixture.commands.layout_registry)
	after, snapshot_ok, _ := layout.registry_snapshot(&fixture.commands.layout_registry, layout_handle)
	active, active_ok := command_context_layout_active_node(&after)

	testing.expect_value(t, first_failure.stage, App_Stage.None)
	testing.expect_value(t, stale_failure.stage, App_Stage.Layout)
	testing.expect_value(t, stale_failure.layout.code, layout.Failure_Code.Stale_Layout)
	testing.expect_value(t, malformed_failure.stage, App_Stage.Input)
	testing.expect(t, !release_result.changed && release_failure.stage == .None)
	testing.expect(t, visible_ok && layout_ok && snapshot_ok && active_ok)
	testing.expect_value(t, visible.entry, fixture.second)
	testing.expect_value(t, active.entry, fixture.second)
}

@(test)
/* Focuses another text pane and places point at the mapped canonical boundary. */
pointer_click_focuses_and_places_text_point :: proc(t: ^testing.T) {
	fixture: Pointer_Focus_Test_Fixture
	if !pointer_focus_test_init(t, &fixture, "first", "\t界e\u0301") do return
	defer pointer_focus_test_close(t, &fixture)
	target, target_ok := pointer_focus_test_content_target(t, &fixture, fixture.second, 0, 5)
	if !target_ok do return

	result, failure := command_context_pointer_focus(
		&fixture.commands,
		&fixture.session,
		fixture.handle,
		pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column),
	)
	node, node_ok := pointer_focus_test_layout_node(&fixture, fixture.second)
	access, access_ok, _ := editor_session.session_entry_access(&fixture.session, fixture.second)
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	logical, logical_ok, _ := editor_view.snapshot(entry.view_registry, node.view)

	testing.expect(t, result.changed && failure.stage == .None)
	testing.expect(t, node_ok && access_ok && borrowed && logical_ok)
	if logical_ok {
		testing.expect_value(t, logical.point_position.byte_offset, editor.Byte_Offset(4))
		testing.expect_value(t, logical.desired_display_column, u32(6))
		testing.expect(t, !logical.region_active)
	}
}

@(test)
/* Deactivates the ordinary region while retaining mark and canonical buffer revision. */
pointer_click_retains_mark_without_edit_history :: proc(t: ^testing.T) {
	fixture: Pointer_Focus_Test_Fixture
	if !pointer_focus_test_init(t, &fixture, "alpha", "second") do return
	defer pointer_focus_test_close(t, &fixture)
	node, node_ok := pointer_focus_test_layout_node(&fixture, fixture.first)
	if !node_ok do return
	access, access_ok, _ := editor_session.session_entry_access(&fixture.session, fixture.first)
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	if !access_ok || !borrowed do return
	point, _, _ := editor.buffer_position(entry.buffer, 4)
	mark, _, _ := editor.buffer_position(entry.buffer, 1)
	point_ok, _ := editor_view.set_point(entry.view_registry, node.view, point)
	mark_ok, _ := editor_view.set_mark(entry.view_registry, node.view, mark, true)
	testing.expect(t, point_ok && mark_ok)
	if !point_ok || !mark_ok do return
	if !pointer_focus_test_publish_ui(t, &fixture) do return
	target, target_ok := pointer_focus_test_content_target(t, &fixture, fixture.first, 0, 2)
	if !target_ok do return
	before, _, _ := editor.buffer_stats(entry.buffer)

	result, failure := command_context_pointer_focus(
		&fixture.commands,
		&fixture.session,
		fixture.handle,
		pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column),
	)
	after, _, _ := editor.buffer_stats(entry.buffer)
	logical, logical_ok, _ := editor_view.snapshot(entry.view_registry, node.view)

	testing.expect(t, result.changed && failure.stage == .None && logical_ok)
	testing.expect_value(t, after.revision, before.revision)
	if logical_ok {
		testing.expect_value(t, logical.point_position.byte_offset, editor.Byte_Offset(2))
		testing.expect(t, logical.mark.present)
		testing.expect_value(t, logical.mark.position.byte_offset, editor.Byte_Offset(1))
		testing.expect(t, !logical.region_active)
	}
}

@(test)
/* Captures forward and reverse drags as the ordinary active linear region. */
pointer_drag_selects_canonical_buffer_range :: proc(t: ^testing.T) {
	fixtures := [?]struct {
		name:         string,
		press_column: u32,
		drag_column:  u32,
		mark:         editor.Byte_Offset,
		point:        editor.Byte_Offset,
	} {
		{"forward", 1, 5, 1, 5},
		{"reverse", 5, 1, 5, 1},
	}
	for drag_fixture in fixtures {
		fixture: Pointer_Focus_Test_Fixture
		if !pointer_focus_test_init(t, &fixture, "abcdef", "second") do continue
		node, node_ok := pointer_focus_test_layout_node(&fixture, fixture.first)
		target, target_ok := pointer_focus_test_content_target(
			t,
			&fixture,
			fixture.first,
			0,
			drag_fixture.press_column,
		)
		if !node_ok || !target_ok {
			pointer_focus_test_close(t, &fixture)
			continue
		}
		press := pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column)
		press_result, press_failure := command_context_pointer_focus(
			&fixture.commands,
			&fixture.session,
			fixture.handle,
			press,
		)
		if !pointer_focus_test_publish_ui(t, &fixture) {
			pointer_focus_test_close(t, &fixture)
			continue
		}
		drag_column := target.column - drag_fixture.press_column + drag_fixture.drag_column
		motion := pointer_focus_test_transition(press, .Motion, .Primary, target.row, drag_column, 2)
		motion.root_generation = interaction.Pointer_Root_Generation(fixture.commands.ui_root.generation)
		drag_result, drag_failure := command_context_pointer_focus(
			&fixture.commands,
			&fixture.session,
			fixture.handle,
			motion,
		)
		if !pointer_focus_test_publish_ui(t, &fixture) {
			pointer_focus_test_close(t, &fixture)
			continue
		}
		release := pointer_focus_test_transition(motion, .Release, .Primary, target.row, drag_column, 3)
		release.root_generation = interaction.Pointer_Root_Generation(fixture.commands.ui_root.generation)
		release_result, release_failure := command_context_pointer_focus(
			&fixture.commands,
			&fixture.session,
			fixture.handle,
			release,
		)
		access, access_ok, _ := editor_session.session_entry_access(&fixture.session, fixture.first)
		entry, borrowed, _ := editor_session.entry_access_borrow(access)
		logical, logical_ok, _ := editor_view.snapshot(entry.view_registry, node.view)

		testing.expectf(t, press_result.changed && press_failure.stage == .None, "%s press failed", drag_fixture.name)
		testing.expectf(t, drag_result.changed && drag_failure.stage == .None, "%s motion failed", drag_fixture.name)
		testing.expectf(t, !release_result.changed && release_failure.stage == .None, "%s release failed", drag_fixture.name)
		testing.expect(t, access_ok && borrowed && logical_ok)
		if logical_ok {
			testing.expect_value(t, logical.mark.position.byte_offset, drag_fixture.mark)
			testing.expect_value(t, logical.point_position.byte_offset, drag_fixture.point)
			testing.expect(t, logical.region_active)
			start := min(logical.mark.position.byte_offset, logical.point_position.byte_offset)
			end := max(logical.mark.position.byte_offset, logical.point_position.byte_offset)
			selected: [16]u8
			copied, inspected, _ := editor.buffer_inspect(entry.buffer, start, end, selected[:])
			testing.expect(t, inspected)
			if inspected {
				testing.expect_value(t, string(selected[:copied]), "bcde")
			}
		}
		testing.expect(t, !fixture.commands.pointer_text_capture.active)
		pointer_focus_test_close(t, &fixture)
	}
}

@(test)
/* Clamps a captured drag that crosses a separator and neighboring pane. */
pointer_drag_cannot_select_neighboring_pane_text :: proc(t: ^testing.T) {
	fixture: Pointer_Focus_Test_Fixture
	if !pointer_focus_test_init(t, &fixture, "left pane", "abcdef") do return
	defer pointer_focus_test_close(t, &fixture)
	node, node_ok := pointer_focus_test_layout_node(&fixture, fixture.second)
	target, target_ok := pointer_focus_test_content_target(t, &fixture, fixture.second, 0, 3)
	if !node_ok || !target_ok do return
	press := pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column)
	_, press_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, press,
	)
	motion := pointer_focus_test_transition(press, .Motion, .Primary, target.row, 0, 2)
	_, motion_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, motion,
	)
	release := pointer_focus_test_transition(motion, .Release, .Primary, target.row, 0, 3)
	_, release_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, release,
	)
	access, access_ok, _ := editor_session.session_entry_access(&fixture.session, fixture.second)
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	logical, logical_ok, _ := editor_view.snapshot(entry.view_registry, node.view)

	testing.expect(t, press_failure.stage == .None && motion_failure.stage == .None)
	testing.expect(t, release_failure.stage == .None && access_ok && borrowed && logical_ok)
	if logical_ok {
		testing.expect_value(t, logical.mark.position.byte_offset, editor.Byte_Offset(3))
		testing.expect_value(t, logical.point_position.byte_offset, editor.Byte_Offset(0))
		selected: [8]u8
		copied, inspected, _ := editor.buffer_inspect(entry.buffer, 0, 3, selected[:])
		testing.expect(t, inspected)
		if inspected do testing.expect_value(t, string(selected[:copied]), "abc")
	}
}

@(test)
/* Rejects snapshot allocation failure before publishing focus, point, or capture. */
pointer_click_projection_failure_is_atomic :: proc(t: ^testing.T) {
	fixture: Pointer_Focus_Test_Fixture
	if !pointer_focus_test_init(t, &fixture, "first", "second") do return
	defer pointer_focus_test_close(t, &fixture)
	target, target_ok := pointer_focus_test_content_target(t, &fixture, fixture.second, 0, 2)
	if !target_ok do return
	fixture.commands.temporary_allocator = runtime.Allocator {
		procedure = pointer_test_failing_allocator_proc,
	}

	result, failure := command_context_pointer_focus(
		&fixture.commands,
		&fixture.session,
		fixture.handle,
		pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column),
	)
	visible, visible_ok, _ := editor_session.session_visible_target(&fixture.session, fixture.handle)

	testing.expect(t, !result.changed)
	testing.expect_value(t, failure.stage, App_Stage.UI)
	testing.expect(t, visible_ok)
	testing.expect_value(t, visible.entry, fixture.first)
	testing.expect(t, !fixture.commands.pointer_text_capture.active)
	fixture.commands.temporary_allocator = context.temp_allocator
}

@(test)
/* Updates only the selected view point while sharing one canonical buffer region. */
pointer_drag_distinguishes_same_buffer_views :: proc(t: ^testing.T) {
	fixture: Pointer_Focus_Test_Fixture
	if !pointer_focus_test_init(t, &fixture, "abcdef", "", true) do return
	defer pointer_focus_test_close(t, &fixture)
	handle, handle_ok, _ := layout.registry_handle(&fixture.commands.layout_registry)
	snapshot, snapshot_ok, _ := layout.registry_snapshot(&fixture.commands.layout_registry, handle)
	panes: [2]layout.Node_Descriptor
	pane_count: int
	if handle_ok && snapshot_ok {
		for node in snapshot.nodes[:snapshot.node_count] {
			if node.kind == .Pane && pane_count < len(panes) {
				panes[pane_count] = node
				pane_count += 1
			}
		}
	}
	testing.expect_value(t, pane_count, 2)
	if pane_count != 2 do return
	testing.expect_value(t, panes[0].entry, panes[1].entry)
	testing.expect(t, panes[0].view != panes[1].view)
	target, target_ok := pointer_focus_test_content_target_pane(t, &fixture, panes[1].pane, 0, 1)
	if !target_ok do return
	press := pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column)
	_, press_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, press,
	)
	motion := pointer_focus_test_transition(press, .Motion, .Primary, target.row, target.column + 3, 2)
	_, motion_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, motion,
	)
	release := pointer_focus_test_transition(motion, .Release, .Primary, target.row, target.column + 3, 3)
	_, release_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, release,
	)
	access, access_ok, _ := editor_session.session_entry_access(&fixture.session, fixture.first)
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	first, first_ok, _ := editor_view.snapshot(entry.view_registry, panes[0].view)
	second, second_ok, _ := editor_view.snapshot(entry.view_registry, panes[1].view)

	testing.expect(t, press_failure.stage == .None && motion_failure.stage == .None)
	testing.expect(t, release_failure.stage == .None && access_ok && borrowed)
	testing.expect(t, first_ok && second_ok)
	if first_ok && second_ok {
		testing.expect_value(t, first.point_position.byte_offset, editor.Byte_Offset(6))
		testing.expect_value(t, first.effective_point_position.byte_offset, editor.Byte_Offset(4))
		testing.expect_value(t, second.point_position.byte_offset, editor.Byte_Offset(4))
		testing.expect(t, first.region_active && second.region_active)
		testing.expect_value(t, second.mark.position.byte_offset, editor.Byte_Offset(1))
	}
}

@(test)
/* Ends capture on cancellation and leaves a zero-distance click inactive. */
pointer_capture_cancels_and_releases_without_empty_region :: proc(t: ^testing.T) {
	fixture: Pointer_Focus_Test_Fixture
	if !pointer_focus_test_init(t, &fixture, "alpha", "second") do return
	defer pointer_focus_test_close(t, &fixture)
	node, node_ok := pointer_focus_test_layout_node(&fixture, fixture.first)
	target, target_ok := pointer_focus_test_content_target(t, &fixture, fixture.first, 0, 2)
	if !node_ok || !target_ok do return
	press := pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column)
	_, press_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, press,
	)
	cancel := pointer_focus_test_transition(press, .Cancel, .None, target.row, target.column, 2)
	_, cancel_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, cancel,
	)
	access, access_ok, _ := editor_session.session_entry_access(&fixture.session, fixture.first)
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	logical, logical_ok, _ := editor_view.snapshot(entry.view_registry, node.view)

	testing.expect(t, press_failure.stage == .None && cancel_failure.stage == .None)
	testing.expect(t, access_ok && borrowed && logical_ok)
	testing.expect(t, !fixture.commands.pointer_text_capture.active)
	if logical_ok {
		testing.expect_value(t, logical.point_position.byte_offset, editor.Byte_Offset(2))
		testing.expect(t, !logical.region_active)
	}
}

@(test)
/* Accepts an exact sequence gap represented by compatible native motion coalescing. */
pointer_capture_accepts_coalesced_motion :: proc(t: ^testing.T) {
	fixture: Pointer_Focus_Test_Fixture
	if !pointer_focus_test_init(t, &fixture, "abcdef", "second") do return
	defer pointer_focus_test_close(t, &fixture)
	target, target_ok := pointer_focus_test_content_target(t, &fixture, fixture.first, 0, 1)
	if !target_ok do return
	press := pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column)
	_, press_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, press,
	)
	motion := pointer_focus_test_transition(
		press, .Motion, .Primary, target.row, target.column + 3, 4,
	)
	result, motion_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, motion, 2,
	)

	testing.expect(t, press_failure.stage == .None && motion_failure.stage == .None)
	testing.expect(t, result.changed && fixture.commands.pointer_text_capture.active)
	testing.expect_value(t, fixture.commands.pointer_text_capture.last_sequence, motion.sequence)
	testing.expect_value(t, fixture.commands.pointer_text_capture.event_count, u32(4))
}

@(test)
/* Ends over-budget capture without publishing another selection transition. */
pointer_capture_event_limit_is_contained :: proc(t: ^testing.T) {
	fixture: Pointer_Focus_Test_Fixture
	if !pointer_focus_test_init(t, &fixture, "abcdef", "second") do return
	defer pointer_focus_test_close(t, &fixture)
	target, target_ok := pointer_focus_test_content_target(t, &fixture, fixture.first, 0, 1)
	if !target_ok do return
	press := pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column)
	_, press_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, press,
	)
	fixture.commands.pointer_text_capture.event_count = MAX_POINTER_CAPTURE_EVENTS
	motion := pointer_focus_test_transition(
		press, .Motion, .Primary, target.row, target.column + 3, 2,
	)
	result, motion_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, motion,
	)

	testing.expect(t, press_failure.stage == .None && motion_failure.stage == .None)
	testing.expect(t, !result.changed && !fixture.commands.pointer_text_capture.active)
	testing.expect_value(
		t,
		string(fixture.commands.diagnostic[:fixture.commands.diagnostic_length]),
		"Pointer capture limit reached",
	)
}

@(test)
/* Bounds capture by monotonic duration independently of event frequency. */
pointer_capture_duration_is_bounded :: proc(t: ^testing.T) {
	started := time.tick_now()
	testing.expect(t, !pointer_capture_limit_reached(
		started,
		1,
		0,
		time.tick_add(started, 29 * time.Second),
	))
	testing.expect(t, pointer_capture_limit_reached(
		started,
		1,
		0,
		time.tick_add(started, 30 * time.Second),
	))
}

@(test)
/* Generates every visible linear range while preserving the unrelated pane state. */
pointer_selection_generated_ranges_are_semantic :: proc(t: ^testing.T) {
	fixture: Pointer_Focus_Test_Fixture
	if !pointer_focus_test_init(t, &fixture, "abcdef", "unchanged") do return
	defer pointer_focus_test_close(t, &fixture)
	first_node, first_node_ok := pointer_focus_test_layout_node(&fixture, fixture.first)
	second_node, second_node_ok := pointer_focus_test_layout_node(&fixture, fixture.second)
	first_access, first_access_ok, _ := editor_session.session_entry_access(&fixture.session, fixture.first)
	first_entry, first_borrowed, _ := editor_session.entry_access_borrow(first_access)
	second_access, second_access_ok, _ := editor_session.session_entry_access(&fixture.session, fixture.second)
	second_entry, second_borrowed, _ := editor_session.entry_access_borrow(second_access)
	second_before, second_before_ok, _ := editor_view.snapshot(second_entry.view_registry, second_node.view)
	second_stats_before, second_stats_ok, _ := editor.buffer_stats(second_entry.buffer)
	if !first_node_ok || !second_node_ok || !first_access_ok || !first_borrowed ||
	   !second_access_ok || !second_borrowed || !second_before_ok || !second_stats_ok {
		return
	}
	sequence := u64(1)
	for origin in u32(0) ..= 6 {
		for destination in u32(0) ..= 6 {
			if !pointer_focus_test_publish_ui(t, &fixture) do return
			target, target_ok := pointer_focus_test_content_target(
				t, &fixture, fixture.first, 0, origin,
			)
			if !target_ok do return
			press := pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column)
			press.sequence = interaction.Pointer_Sequence(sequence)
			motion := pointer_focus_test_transition(
				press,
				.Motion,
				.Primary,
				target.row,
				target.column - origin + destination,
				sequence + 1,
			)
			release := pointer_focus_test_transition(
				motion,
				.Release,
				.Primary,
				motion.row,
				motion.column,
				sequence + 2,
			)
			_, press_failure := command_context_pointer_focus(
				&fixture.commands, &fixture.session, fixture.handle, press,
			)
			_, motion_failure := command_context_pointer_focus(
				&fixture.commands, &fixture.session, fixture.handle, motion,
			)
			_, release_failure := command_context_pointer_focus(
				&fixture.commands, &fixture.session, fixture.handle, release,
			)
			logical, logical_ok, _ := editor_view.snapshot(first_entry.view_registry, first_node.view)
			testing.expect(t, press_failure.stage == .None && motion_failure.stage == .None)
			testing.expect(t, release_failure.stage == .None && logical_ok)
			if logical_ok {
				testing.expect_value(t, logical.point_position.byte_offset, editor.Byte_Offset(destination))
				if origin == destination {
					testing.expect(t, !logical.region_active)
				} else {
					testing.expect(t, logical.region_active)
					testing.expect_value(t, logical.mark.position.byte_offset, editor.Byte_Offset(origin))
				}
			}
			sequence += 3
		}
	}
	second_after, second_after_ok, _ := editor_view.snapshot(second_entry.view_registry, second_node.view)
	second_stats_after, second_after_stats_ok, _ := editor.buffer_stats(second_entry.buffer)
	testing.expect(t, second_after_ok && second_after_stats_ok)
	if second_after_ok && second_after_stats_ok {
		testing.expect_value(t, second_after.point_position, second_before.point_position)
		testing.expect_value(t, second_after.mark, second_before.mark)
		testing.expect_value(t, second_stats_after.revision, second_stats_before.revision)
		testing.expect_value(t, second_stats_after.text_bytes, second_stats_before.text_bytes)
	}
}

@(private)
Pointer_Invalidation_Case :: enum u8 {
	Root_Replacement,
	Pane_Closure,
	Stale_Geometry,
	Malformed_Coordinate,
}

@(test)
/* Generates lifecycle and malformed invalidations without changing unrelated text state. */
pointer_selection_generated_invalidations_are_atomic :: proc(t: ^testing.T) {
	cases := [?]Pointer_Invalidation_Case {
		.Root_Replacement,
		.Pane_Closure,
		.Stale_Geometry,
		.Malformed_Coordinate,
	}
	for invalidation in cases {
		fixture: Pointer_Focus_Test_Fixture
		if !pointer_focus_test_init(t, &fixture, "abcdef", "unchanged") do continue
		target_node, node_ok := pointer_focus_test_layout_node(&fixture, fixture.first)
		target, target_ok := pointer_focus_test_content_target(t, &fixture, fixture.first, 0, 2)
		other_node, other_node_ok := pointer_focus_test_layout_node(&fixture, fixture.second)
		other_access, other_access_ok, _ := editor_session.session_entry_access(
			&fixture.session, fixture.second,
		)
		other_entry, other_borrowed, _ := editor_session.entry_access_borrow(other_access)
		other_before, other_before_ok, _ := editor_view.snapshot(other_entry.view_registry, other_node.view)
		other_stats_before, other_stats_ok, _ := editor.buffer_stats(other_entry.buffer)
		if !node_ok || !target_ok || !other_node_ok || !other_access_ok || !other_borrowed ||
		   !other_before_ok || !other_stats_ok {
			pointer_focus_test_close(t, &fixture)
			continue
		}
		press := pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column)
		_, press_failure := command_context_pointer_focus(
			&fixture.commands, &fixture.session, fixture.handle, press,
		)
		motion := pointer_focus_test_transition(
			press, .Motion, .Primary, target.row, target.column + 2, 2,
		)
		switch invalidation {
		case .Root_Replacement:
			if pointer_focus_test_publish_ui(t, &fixture, false) {
				motion.root_generation = interaction.Pointer_Root_Generation(fixture.commands.ui_root.generation)
			}
		case .Pane_Closure:
			_, closed, _ := layout.registry_close_pane(
				&fixture.commands.layout_registry, target_node.pane,
			)
			if closed && pointer_focus_test_publish_ui(t, &fixture) {
				motion.root_generation = interaction.Pointer_Root_Generation(fixture.commands.ui_root.generation)
			}
		case .Stale_Geometry:
			motion.geometry_generation += 1
		case .Malformed_Coordinate:
			motion.column = interaction.MAX_POINTER_COORDINATE + 1
		}
		result, motion_failure := command_context_pointer_focus(
			&fixture.commands, &fixture.session, fixture.handle, motion,
		)
		other_after, other_after_ok, _ := editor_view.snapshot(other_entry.view_registry, other_node.view)
		other_stats_after, other_after_stats_ok, _ := editor.buffer_stats(other_entry.buffer)
		testing.expect_value(t, press_failure.stage, App_Stage.None)
		testing.expect(t, !result.changed && motion_failure.stage != .None)
		testing.expect(t, !fixture.commands.pointer_text_capture.active)
		testing.expect(t, other_after_ok && other_after_stats_ok)
		if other_after_ok && other_after_stats_ok {
			testing.expect_value(t, other_after.point_position, other_before.point_position)
			testing.expect_value(t, other_after.mark, other_before.mark)
			testing.expect_value(t, other_stats_after.revision, other_stats_before.revision)
			testing.expect_value(t, other_stats_after.text_bytes, other_stats_before.text_bytes)
		}
		pointer_focus_test_close(t, &fixture)
	}
}

@(test)
/* Invalidates capture when keyboard-owned view state changes between pointer events. */
pointer_capture_rejects_interleaved_view_mutation :: proc(t: ^testing.T) {
	fixture: Pointer_Focus_Test_Fixture
	if !pointer_focus_test_init(t, &fixture, "alpha", "second") do return
	defer pointer_focus_test_close(t, &fixture)
	node, node_ok := pointer_focus_test_layout_node(&fixture, fixture.first)
	target, target_ok := pointer_focus_test_content_target(t, &fixture, fixture.first, 0, 1)
	if !node_ok || !target_ok do return
	press := pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column)
	_, press_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, press,
	)
	access, access_ok, _ := editor_session.session_entry_access(&fixture.session, fixture.first)
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	keyboard_point, _, _ := editor.buffer_position(entry.buffer, 3)
	keyboard_moved, _ := editor_view.move_point(
		entry.view_registry, node.view, keyboard_point, 3, .Deactivate,
	)
	motion := pointer_focus_test_transition(press, .Motion, .Primary, target.row, target.column + 3, 2)
	_, motion_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, motion,
	)
	logical, logical_ok, _ := editor_view.snapshot(entry.view_registry, node.view)

	testing.expect(t, press_failure.stage == .None)
	testing.expect(t, access_ok && borrowed && keyboard_moved && logical_ok)
	testing.expect_value(t, motion_failure.stage, App_Stage.View_Snapshot)
	testing.expect(t, !fixture.commands.pointer_text_capture.active)
	if logical_ok {
		testing.expect_value(t, logical.point_position.byte_offset, editor.Byte_Offset(3))
		testing.expect(t, !logical.region_active)
	}
}

@(test)
/* Selects exact retained shell text locally without forwarding bytes to the PTY. */
pointer_terminal_selects_retained_text_locally :: proc(t: ^testing.T) {
	fixture, allocation_error := new(Pointer_Terminal_Test_Fixture, context.allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	defer free(fixture, context.allocator)
	if !pointer_terminal_test_init(
		t,
		fixture,
		"printf 'alpha\\r\\nbeta'; sleep 30",
		"alpha",
		false,
	) {
		return
	}
	defer pointer_terminal_test_close(t, fixture)
	target, target_ok := pointer_terminal_test_target(t, fixture, 0, 0)
	if !target_ok do return
	before, recorded, _ := terminal_session.registry_record(
		&fixture.workflow.registry, fixture.opened.terminal,
	)
	if !recorded do return

	first := pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column)
	first_result, first_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, first,
	)
	testing.expect(t, first_result.changed && first_failure.stage == .None)
	testing.expect(t, !fixture.workflow.pointer_capture.active)
	if !pointer_terminal_test_publish_ui(t, fixture) do return
	target, target_ok = pointer_terminal_test_target(t, fixture, 0, 0)
	if !target_ok do return

	press := pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column)
	press_result, press_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, press,
	)
	testing.expect(t, press_result.changed && press_failure.stage == .None)
	testing.expect(t, fixture.workflow.pointer_capture.active)
	testing.expect_value(t, fixture.workflow.pointer_capture.route, terminal_session.Mouse_Route.Local)
	if !pointer_terminal_test_publish_ui(t, fixture) do return
	motion := pointer_focus_test_transition(press, .Motion, .Primary, target.row, target.column + 4, 2)
	motion.root_generation = interaction.Pointer_Root_Generation(fixture.commands.ui_root.generation)
	motion_result, motion_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, motion,
	)
	testing.expect(t, motion_result.changed && motion_failure.stage == .None)
	if !pointer_terminal_test_publish_ui(t, fixture) do return
	release := pointer_focus_test_transition(motion, .Release, .Primary, target.row, target.column + 4, 3)
	release.root_generation = interaction.Pointer_Root_Generation(fixture.commands.ui_root.generation)
	release_result, release_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, release,
	)
	testing.expect(t, !release_result.changed && release_failure.stage == .None)
	testing.expect(t, !fixture.workflow.pointer_capture.active)

	entry := terminal_workflow_entry_record(&fixture.workflow, fixture.opened.terminal)
	testing.expect(t, entry != nil)
	if entry == nil do return
	selection: [16]u8
	copied, copied_ok, copy_failure := terminal_session.registry_copy_mode_copy_selection(
		&fixture.workflow.registry,
		fixture.opened.terminal,
		entry.copy_mode,
		selection[:],
	)
	testing.expectf(t, copied_ok, "terminal pointer copy failed with %v", copy_failure.code)
	if copied_ok {
		testing.expect_value(t, string(selection[:int(copied.copied_bytes)]), "alpha")
	}
	after, after_recorded, _ := terminal_session.registry_record(
		&fixture.workflow.registry, fixture.opened.terminal,
	)
	testing.expect(t, after_recorded)
	if after_recorded {
		testing.expect_value(
			t,
			after.process.resources.queued_input_bytes + after.process.resources.total_input_bytes,
			before.process.resources.queued_input_bytes + before.process.resources.total_input_bytes,
		)
	}
}

@(test)
/* Routes child mouse gestures, preserves Shift selection, and clears capture on exit. */
pointer_terminal_routes_child_and_cleans_exit :: proc(t: ^testing.T) {
	fixture, allocation_error := new(Pointer_Terminal_Test_Fixture, context.allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	defer free(fixture, context.allocator)
	if !pointer_terminal_test_init(
		t,
		fixture,
		"printf '\\033[?1049h\\033[?1000h\\033[?1002h\\033[?1006hFULL'; sleep 1",
		"FULL",
		true,
	) {
		return
	}
	defer pointer_terminal_test_close(t, fixture)
	target, target_ok := pointer_terminal_test_target(t, fixture, 0, 0)
	if !target_ok do return

	first := pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column)
	first_result, first_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, first,
	)
	testing.expect(t, first_result.changed && first_failure.stage == .None)
	testing.expect(t, !fixture.workflow.pointer_capture.active)
	if !pointer_terminal_test_publish_ui(t, fixture) do return
	target, target_ok = pointer_terminal_test_target(t, fixture, 0, 0)
	if !target_ok do return

	press := pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column)
	_, press_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, press,
	)
	testing.expect_value(t, press_failure.stage, App_Stage.None)
	testing.expect(t, fixture.workflow.pointer_capture.active)
	testing.expect_value(t, fixture.workflow.pointer_capture.route, terminal_session.Mouse_Route.Child)
	motion := pointer_focus_test_transition(press, .Motion, .Primary, target.row, target.column + 1, 2)
	_, motion_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, motion,
	)
	release := pointer_focus_test_transition(motion, .Release, .Primary, target.row, target.column + 1, 3)
	_, release_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, release,
	)
	testing.expect(t, motion_failure.stage == .None && release_failure.stage == .None)
	testing.expect(t, !fixture.workflow.pointer_capture.active)
	child_record, child_recorded, _ := terminal_session.registry_record(
		&fixture.workflow.registry, fixture.opened.terminal,
	)
	testing.expect(t, child_recorded)
	if !child_recorded do return
	child_input_bytes := child_record.process.resources.queued_input_bytes +
		child_record.process.resources.total_input_bytes
	testing.expect(t, child_input_bytes > 0)

	shift_press := pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column)
	shift_press.modifiers = {.Shift}
	shift_press.capabilities += {.Modifiers}
	_, shift_press_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, shift_press,
	)
	testing.expect_value(t, shift_press_failure.stage, App_Stage.None)
	testing.expect_value(t, fixture.workflow.pointer_capture.route, terminal_session.Mouse_Route.Local)
	shift_motion := pointer_focus_test_transition(
		shift_press, .Motion, .Primary, target.row, target.column + 3, 2,
	)
	_, shift_motion_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, shift_motion,
	)
	shift_release := pointer_focus_test_transition(
		shift_motion, .Release, .Primary, target.row, target.column + 3, 3,
	)
	_, shift_release_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, shift_release,
	)
	testing.expect(t, shift_motion_failure.stage == .None && shift_release_failure.stage == .None)
	shift_record, shift_recorded, _ := terminal_session.registry_record(
		&fixture.workflow.registry, fixture.opened.terminal,
	)
	testing.expect(t, shift_recorded)
	if shift_recorded {
		testing.expect_value(
			t,
			shift_record.process.resources.queued_input_bytes +
				shift_record.process.resources.total_input_bytes,
			child_input_bytes,
		)
	}

	final_press := pointer_focus_test_event(fixture.commands.ui_root, target.row, target.column)
	_, final_failure := command_context_pointer_focus(
		&fixture.commands, &fixture.session, fixture.handle, final_press,
	)
	testing.expect_value(t, final_failure.stage, App_Stage.None)
	testing.expect(t, fixture.workflow.pointer_capture.active)
	exited := false
	for _ in 0 ..< 2_000 {
		state, refreshed, _ := terminal_workflow_refresh(
			&fixture.workflow, &fixture.session, fixture.opened.terminal,
		)
		if refreshed && state.lifecycle == .Exited {
			exited = true
			break
		}
		time.sleep(time.Millisecond)
	}
	testing.expect(t, exited)
	testing.expect(t, !fixture.workflow.pointer_capture.active)
	layout_handle, handle_ok, _ := layout.registry_handle(&fixture.commands.layout_registry)
	layout_before_close, snapshot_ok, _ := layout.registry_snapshot(
		&fixture.commands.layout_registry, layout_handle,
	)
	terminal_pane: layout.Pane_Handle
	if handle_ok && snapshot_ok {
		for node in layout_before_close.nodes[:layout_before_close.node_count] {
			if node.kind == .Pane && node.entry == fixture.opened.entry {
				terminal_pane = node.pane
				break
			}
		}
	}
	closed, pane_closed, _ := layout.registry_close_pane(
		&fixture.commands.layout_registry, terminal_pane,
	)
	testing.expect(t, handle_ok && snapshot_ok && pane_closed)
	if pane_closed {
		after_close, after_close_ok, _ := layout.registry_snapshot(
			&fixture.commands.layout_registry, closed.layout,
		)
		testing.expect(t, after_close_ok)
		if after_close_ok {
			testing.expect_value(t, after_close.pane_count, u16(1))
			testing.expect_value(t, after_close.nodes[0].entry, fixture.initial)
		}
	}
	disposed, dispose_failure := terminal_workflow_dispose(
		&fixture.workflow, fixture.opened.terminal,
	)
	testing.expectf(t, disposed, "terminal disposal failed at %v", dispose_failure.stage)
	stats, inspected, _ := terminal_session.registry_inspect(&fixture.workflow.registry)
	testing.expect(t, inspected)
	if inspected do testing.expect_value(t, stats.session_count, u16(0))
}

@(private)
Pointer_Terminal_Test_Fixture :: struct {
	session:  editor_session.Session,
	handle:   editor_session.Session_Handle,
	commands: Command_Context,
	workflow: Terminal_Workflow_State,
	initial:  editor_session.Entry_Handle,
	opened:   Terminal_Open_Result,
}

@(private)
pointer_terminal_test_init :: proc(
	t: ^testing.T,
	fixture: ^Pointer_Terminal_Test_Fixture,
	script, expected_text: string,
	require_mouse_tracking: bool,
) -> bool {
	handle, session_ok, session_failure := editor_session.session_init(
		&fixture.session,
		9_812,
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, session_ok, "terminal session initialization failed with %v", session_failure.code)
	if !session_ok do return false
	fixture.handle = handle
	initial, initial_ok, _ := editor_session.session_create_buffer(
		&fixture.session,
		{
			session = handle,
			name = "notes",
			initial_contents = "keep",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, initial_ok)
	if !initial_ok do return false
	fixture.initial = initial.entry
	_, activated, _ := editor_session.session_activate(&fixture.session, fixture.initial)
	access, access_ok, _ := editor_session.session_entry_access(&fixture.session, fixture.initial)
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, activated && access_ok && borrowed)
	if !activated || !access_ok || !borrowed do return false
	fixture.commands = Command_Context {
		session_owner = &fixture.session,
		session_handle = fixture.handle,
		current_entry = fixture.initial,
		layout_entry = fixture.initial,
		terminal_workflow = &fixture.workflow,
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
	}
	command_context_bind_entry(&fixture.commands, fixture.initial, entry)
	ensure_failure := command_context_layout_ensure(
		&fixture.commands,
		entry.view_registry,
		entry.primary_view,
		{width_cells = 80, height_rows = 24},
	)
	testing.expect_value(t, ensure_failure.stage, App_Stage.None)
	if ensure_failure.stage != .None do return false
	workflow_ok, workflow_failure := terminal_workflow_init(&fixture.workflow)
	testing.expectf(t, workflow_ok, "terminal workflow initialization failed at %v", workflow_failure.stage)
	if !workflow_ok do return false
	opened, opened_ok, open_failure := terminal_workflow_open(
		&fixture.workflow,
		&fixture.session,
		fixture.handle,
		&fixture.commands.layout_registry,
		terminal_workflow_test_request(.Other_Pane, []string{"-c", script}),
	)
	testing.expectf(t, opened_ok, "terminal workflow open failed at %v", open_failure.stage)
	if !opened_ok do return false
	fixture.opened = opened

	ready := false
	for _ in 0 ..< 2_000 {
		_, _, _ = terminal_workflow_refresh(&fixture.workflow, &fixture.session, opened.terminal)
		text, copied, _ := terminal_workflow_copy_screen(
			&fixture.workflow, opened.terminal, terminal_session.DEFAULT_LIMITS.copied_text_bytes,
		)
		text_ready := copied && strings.contains(string(text), expected_text)
		if text != nil do delete(text, fixture.workflow.allocator)
		tracking_ready := !require_mouse_tracking
		if require_mouse_tracking {
			record, recorded, _ := terminal_session.registry_record(&fixture.workflow.registry, opened.terminal)
			if recorded {
				mouse, mouse_ok := terminal_emulator.mouse_state(record.emulator)
				tracking_ready = mouse_ok == .OK && mouse.tracking
			}
		}
		if text_ready && tracking_ready {
			ready = true
			break
		}
		time.sleep(time.Millisecond)
	}
	testing.expect(t, ready)
	if !ready do return false
	layout_handle, handle_ok, _ := layout.registry_handle(&fixture.commands.layout_registry)
	snapshot, snapshot_ok, _ := layout.registry_snapshot(&fixture.commands.layout_registry, layout_handle)
	if !handle_ok || !snapshot_ok do return false
	initial_pane: layout.Pane_Handle
	for node in snapshot.nodes[:snapshot.node_count] {
		if node.kind == .Pane && node.entry == fixture.initial {
			initial_pane = node.pane
			break
		}
	}
	_, focused, _ := layout.registry_focus(&fixture.commands.layout_registry, initial_pane)
	_, activated, _ = editor_session.session_activate(&fixture.session, fixture.initial)
	testing.expect(t, focused && activated)
	if !focused || !activated do return false
	command_context_bind_entry(&fixture.commands, fixture.initial, entry)
	fixture.commands.current_entry = fixture.initial
	fixture.commands.layout_entry = fixture.initial
	return pointer_terminal_test_publish_ui(t, fixture)
}

@(private)
pointer_terminal_test_publish_ui :: proc(
	t: ^testing.T,
	fixture: ^Pointer_Terminal_Test_Fixture,
	reconcile_capture: bool = true,
) -> bool {
	profile := pointer_focus_test_renderer()
	if fixture.commands.ui_registry.state == nil {
		initialized, init_failure := ui.registry_init(&fixture.commands.ui_registry, 9_812)
		testing.expectf(t, initialized, "terminal UI initialization failed with %v", init_failure.code)
		if !initialized do return false
	}
	previous_root := fixture.commands.ui_root
	proposal, prepared, _ := ui.proposal_begin(&fixture.commands.ui_registry, previous_root)
	if !prepared do return false
	defer if proposal.state != nil do ui.proposal_abort(&proposal)
	_, style_ok, _ := ui.proposal_add_style(&proposal, .Text_Normal)
	layout_handle, handle_ok, _ := layout.registry_handle(&fixture.commands.layout_registry)
	source, snapshot_ok, _ := layout.registry_snapshot(&fixture.commands.layout_registry, layout_handle)
	if !style_ok || !handle_ok || !snapshot_ok do return false
	bindings: [layout.MAX_LIVE_PANES]ui.Pane_Text_View_Binding
	binding_count: int
	for node in source.nodes[:source.node_count] {
		if node.kind != .Pane do continue
		view: ui.Object_Handle
		projected := false
		if node.entry == fixture.opened.entry {
			_, resized, resize_failure := terminal_workflow_resize(
				&fixture.workflow,
				fixture.opened.terminal,
				u16(node.geometry.content.width),
				u16(node.geometry.content.height),
			)
			testing.expectf(t, resized, "terminal resize failed at %v", resize_failure.stage)
			if !resized do return false
			view, projected, _ = terminal_workflow_project_ui(
				&fixture.workflow, &proposal, fixture.opened.terminal, 9_812, "terminal",
			)
		} else {
			access, access_ok, _ := editor_session.session_entry_access(&fixture.session, node.entry)
			entry, borrowed, _ := editor_session.entry_access_borrow(access)
			if !access_ok || !borrowed do return false
			view, projected, _ = ui.proposal_project_editor_text_view(
				&proposal, entry.view_registry, node.view, entry.buffer, 9_812,
			)
		}
		if !projected do return false
		bindings[binding_count] = {pane = node.pane, view = view}
		binding_count += 1
	}
	_, mapped, _ := ui.proposal_map_pane_layout(
		&proposal, source, bindings[:binding_count], profile.id,
	)
	if !mapped do return false
	root, published, publish_failure := ui.proposal_publish(
		&fixture.commands.ui_registry, &proposal, profile,
	)
	testing.expectf(t, published, "terminal UI publication failed with %v", publish_failure.code)
	if !published do return false
	fixture.commands.ui_root = root
	if reconcile_capture do pointer_capture_reconcile_root(&fixture.commands, previous_root, root)
	fixture.commands.renderer_profile = profile
	return true
}

@(private)
pointer_terminal_test_target :: proc(
	t: ^testing.T,
	fixture: ^Pointer_Terminal_Test_Fixture,
	local_row, local_column: u32,
) -> (Pointer_Focus_Test_Target, bool) {
	snapshot, copied, failure := ui.registry_snapshot(
		&fixture.commands.ui_registry,
		fixture.commands.ui_root,
		fixture.commands.renderer_profile,
	)
	testing.expectf(t, copied, "terminal UI snapshot failed with %v", failure.code)
	if !copied do return {}, false
	defer ui.snapshot_close(&snapshot)
	view, viewed := ui.snapshot_view(&snapshot)
	if !viewed do return {}, false
	for surface in view.surfaces {
		if surface.pane.entry_id != u64(fixture.opened.entry.entry_id) ||
		   surface.pane.entry_generation != fixture.opened.entry.generation {
			continue
		}
		if local_row >= u32(surface.geometry.height) || local_column >= u32(surface.geometry.width) {
			return {}, false
		}
		return {
			row = u32(surface.geometry.row) + local_row,
			column = u32(surface.geometry.column) + local_column,
		}, true
	}
	return {}, false
}

@(private)
pointer_terminal_test_close :: proc(t: ^testing.T, fixture: ^Pointer_Terminal_Test_Fixture) {
	close_failure := command_context_close(&fixture.commands)
	testing.expect_value(t, close_failure.stage, App_Stage.None)
	shutdown_failure := session_shutdown_close(&fixture.session, fixture.handle)
	testing.expect_value(t, shutdown_failure.stage, App_Stage.None)
	fixture.handle = {}
}

@(private)
Pointer_Focus_Test_Fixture :: struct {
	session:  editor_session.Session,
	handle:   editor_session.Session_Handle,
	commands: Command_Context,
	first:    editor_session.Entry_Handle,
	second:   editor_session.Entry_Handle,
}

@(private)
Pointer_Focus_Test_Target :: struct {
	row:    u32,
	column: u32,
}

@(private)
pointer_focus_test_init :: proc(
	t: ^testing.T,
	fixture: ^Pointer_Focus_Test_Fixture,
	first_text := "",
	second_text := "",
	second_uses_first := false,
) -> bool {
	handle, session_ok, session_failure := editor_session.session_init(
		&fixture.session,
		9_811,
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, session_ok, "session initialization failed with %v", session_failure.code)
	if !session_ok do return false
	fixture.handle = handle
	first, first_ok, _ := editor_session.session_create_buffer(
		&fixture.session,
		editor_session.Create_Buffer_Request {
			session = handle,
			name = "first",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	second, second_ok, _ := editor_session.session_create_buffer(
		&fixture.session,
		editor_session.Create_Buffer_Request {
			session = handle,
			name = "second",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, first_ok && second_ok)
	if !first_ok || !second_ok do return false
	fixture.first = first.entry
	fixture.second = second.entry
	if !pointer_focus_test_set_text(t, &fixture.session, fixture.first, first_text) ||
	   !pointer_focus_test_set_text(t, &fixture.session, fixture.second, second_text) {
		return false
	}
	_, activated, _ := editor_session.session_activate(&fixture.session, fixture.first)
	testing.expect(t, activated)
	if !activated do return false
	access, access_ok, _ := editor_session.session_entry_access(&fixture.session, fixture.first)
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, access_ok && borrowed)
	if !access_ok || !borrowed do return false
	fixture.commands = Command_Context {
		session_owner = &fixture.session,
		session_handle = handle,
		current_entry = fixture.first,
		layout_entry = fixture.first,
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
	}
	command_context_bind_entry(&fixture.commands, fixture.first, entry)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	ensure_failure := command_context_layout_ensure(
		&fixture.commands,
		entry.view_registry,
		entry.primary_view,
		constraints,
	)
	testing.expect_value(t, ensure_failure.stage, App_Stage.None)
	if ensure_failure.stage != .None do return false
	layout_handle, handle_ok, _ := layout.registry_handle(&fixture.commands.layout_registry)
	before, snapshot_ok, _ := layout.registry_snapshot(&fixture.commands.layout_registry, layout_handle)
	if !handle_ok || !snapshot_ok do return false
	split, split_ok, _ := layout.registry_split_right(
		&fixture.commands.layout_registry,
		before.active_pane,
	)
	if !split_ok do return false
	if !second_uses_first {
		_, replaced, _ := layout.registry_replace_pane_buffer(
			&fixture.commands.layout_registry,
			split.created,
			&fixture.session,
			fixture.second,
		)
		if !replaced do return false
	}
	return pointer_focus_test_publish_ui(t, fixture)
}

@(private)
pointer_focus_test_publish_ui :: proc(
	t: ^testing.T,
	fixture: ^Pointer_Focus_Test_Fixture,
	reconcile_capture: bool = true,
) -> bool {
	profile := pointer_focus_test_renderer()
	if fixture.commands.ui_registry.state == nil {
		initialized, init_failure := ui.registry_init(&fixture.commands.ui_registry, 9_811)
		testing.expectf(t, initialized, "UI initialization failed with %v", init_failure.code)
		if !initialized do return false
	}
	previous_root := fixture.commands.ui_root
	proposal, prepared, _ := ui.proposal_begin(&fixture.commands.ui_registry, previous_root)
	if !prepared do return false
	defer if proposal.state != nil do ui.proposal_abort(&proposal)
	_, text_style, _ := ui.proposal_add_style(&proposal, .Text_Normal)
	_, status_style, _ := ui.proposal_add_style(&proposal, .Status_Normal, {.Reverse})
	_, active_style, _ := ui.proposal_add_style(&proposal, .Status_Active, {.Reverse, .Bold})
	layout_handle, handle_ok, _ := layout.registry_handle(&fixture.commands.layout_registry)
	source, snapshot_ok, _ := layout.registry_snapshot(&fixture.commands.layout_registry, layout_handle)
	if !text_style || !status_style || !active_style || !handle_ok || !snapshot_ok do return false
	bindings: [layout.MAX_LIVE_PANES]ui.Pane_Text_View_Binding
	binding_count: int
	for node in source.nodes[:source.node_count] {
		if node.kind != .Pane do continue
		access, access_ok, _ := editor_session.session_entry_access(&fixture.session, node.entry)
		entry, borrowed, _ := editor_session.entry_access_borrow(access)
		if !access_ok || !borrowed do return false
		view, projected, _ := ui.proposal_project_editor_text_view(
			&proposal,
			entry.view_registry,
			node.view,
			entry.buffer,
			9_811,
		)
		if !projected do return false
		bindings[binding_count] = {pane = node.pane, view = view}
		binding_count += 1
	}
	_, mapped, _ := ui.proposal_map_pane_layout(
		&proposal,
		source,
		bindings[:binding_count],
		profile.id,
	)
	if !mapped do return false
	for node in source.nodes[:source.node_count] {
		if node.kind != .Pane do continue
		surface, surface_ok, _ := ui.proposal_pane_surface(&proposal, node.pane)
		if !surface_ok do return false
		_, status_ok, _ := ui.proposal_project_pane_status(&proposal, surface, "pointer status")
		if !status_ok do return false
	}
	root, published, publish_failure := ui.proposal_publish(
		&fixture.commands.ui_registry,
		&proposal,
		profile,
	)
	testing.expectf(t, published, "UI publication failed with %v", publish_failure.code)
	if !published do return false
	fixture.commands.ui_root = root
	if reconcile_capture do pointer_capture_reconcile_root(&fixture.commands, previous_root, root)
	fixture.commands.renderer_profile = profile
	return true
}

@(private)
pointer_focus_test_target :: proc(
	t: ^testing.T,
	fixture: ^Pointer_Focus_Test_Fixture,
	entry: editor_session.Entry_Handle,
) -> (Pointer_Focus_Test_Target, bool) {
	snapshot, copied, failure := ui.registry_snapshot(
		&fixture.commands.ui_registry,
		fixture.commands.ui_root,
		fixture.commands.renderer_profile,
	)
	testing.expectf(t, copied, "UI snapshot failed with %v", failure.code)
	if !copied do return {}, false
	defer ui.snapshot_close(&snapshot)
	view, viewed := ui.snapshot_view(&snapshot)
	if !viewed do return {}, false
	for status in view.status_regions {
		for surface in view.surfaces {
			if surface.handle != status.surface || surface.pane.entry_id != u64(entry.entry_id) {
				continue
			}
			return Pointer_Focus_Test_Target {
				row = u32(status.geometry.row),
				column = u32(status.geometry.column),
			}, true
		}
	}
	return {}, false
}

@(private)
pointer_focus_test_content_target :: proc(
	t: ^testing.T,
	fixture: ^Pointer_Focus_Test_Fixture,
	entry: editor_session.Entry_Handle,
	local_row, local_column: u32,
) -> (Pointer_Focus_Test_Target, bool) {
	snapshot, copied, failure := ui.registry_snapshot(
		&fixture.commands.ui_registry,
		fixture.commands.ui_root,
		fixture.commands.renderer_profile,
	)
	testing.expectf(t, copied, "UI snapshot failed with %v", failure.code)
	if !copied do return {}, false
	defer ui.snapshot_close(&snapshot)
	view, viewed := ui.snapshot_view(&snapshot)
	if !viewed do return {}, false
	for surface in view.surfaces {
		if surface.pane.entry_id != u64(entry.entry_id) do continue
		if local_row >= u32(surface.geometry.height) || local_column >= u32(surface.geometry.width) {
			return {}, false
		}
		return Pointer_Focus_Test_Target {
			row = u32(surface.geometry.row) + local_row,
			column = u32(surface.geometry.column) + local_column,
		}, true
	}
	return {}, false
}

@(private)
pointer_focus_test_content_target_pane :: proc(
	t: ^testing.T,
	fixture: ^Pointer_Focus_Test_Fixture,
	pane: layout.Pane_Handle,
	local_row, local_column: u32,
) -> (Pointer_Focus_Test_Target, bool) {
	snapshot, copied, failure := ui.registry_snapshot(
		&fixture.commands.ui_registry,
		fixture.commands.ui_root,
		fixture.commands.renderer_profile,
	)
	testing.expectf(t, copied, "UI snapshot failed with %v", failure.code)
	if !copied do return {}, false
	defer ui.snapshot_close(&snapshot)
	view, viewed := ui.snapshot_view(&snapshot)
	if !viewed do return {}, false
	for surface in view.surfaces {
		if surface.pane.pane_id != u64(pane.pane_id) ||
		   surface.pane.pane_generation != pane.slot_generation {
			continue
		}
		if local_row >= u32(surface.geometry.height) || local_column >= u32(surface.geometry.width) {
			return {}, false
		}
		return Pointer_Focus_Test_Target {
			row = u32(surface.geometry.row) + local_row,
			column = u32(surface.geometry.column) + local_column,
		}, true
	}
	return {}, false
}

@(private)
pointer_focus_test_layout_node :: proc(
	fixture: ^Pointer_Focus_Test_Fixture,
	entry: editor_session.Entry_Handle,
) -> (layout.Node_Descriptor, bool) {
	handle, handle_ok, _ := layout.registry_handle(&fixture.commands.layout_registry)
	snapshot, snapshot_ok, _ := layout.registry_snapshot(&fixture.commands.layout_registry, handle)
	if !handle_ok || !snapshot_ok do return {}, false
	for node in snapshot.nodes[:snapshot.node_count] {
		if node.kind == .Pane && node.entry == entry do return node, true
	}
	return {}, false
}

@(private)
pointer_focus_test_set_text :: proc(
	t: ^testing.T,
	session: ^editor_session.Session,
	entry_handle: editor_session.Entry_Handle,
	text: string,
) -> bool {
	if len(text) == 0 do return true
	access, access_ok, _ := editor_session.session_entry_access(session, entry_handle)
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	if !access_ok || !borrowed do return false
	position, position_ok, _ := editor.buffer_position(entry.buffer, 0)
	if !position_ok do return false
	_, _, published, failure := editor.buffer_splice(
		entry.buffer,
		editor.Splice{start = position, end = position, replacement = text},
		context.temp_allocator,
	)
	testing.expectf(t, published, "fixture text failed with %v", failure.code)
	return published
}

@(private)
pointer_focus_test_event :: proc(
	root: ui.Root_Handle,
	row, column: u32,
) -> interaction.Pointer_Event {
	return interaction.Pointer_Event {
		frontend = 1,
		source = 1,
		action = .Press,
		button = .Primary,
		coordinate_space = .Cell,
		row = row,
		column = column,
		root_generation = interaction.Pointer_Root_Generation(root.generation),
		geometry_generation = 1,
		sequence = 1,
		capabilities = {.Press, .Cell_Coordinates},
	}
}

@(private)
pointer_focus_test_transition :: proc(
	previous: interaction.Pointer_Event,
	action: interaction.Pointer_Action,
	button: interaction.Pointer_Button,
	row, column: u32,
	sequence: u64,
) -> interaction.Pointer_Event {
	capabilities := interaction.Pointer_Capabilities{.Cell_Coordinates}
	if previous.modifiers != {} do capabilities += {.Modifiers}
	switch action {
	case .Motion:
		capabilities += {.Motion}
	case .Release:
		capabilities += {.Release}
	case .Cancel:
		capabilities += {.Cancellation}
	case .Press:
		capabilities += {.Press}
	case .Wheel:
		capabilities += {.Wheel}
	case .Invalid:
	}
	return interaction.Pointer_Event {
		frontend = previous.frontend,
		source = previous.source,
		action = action,
		button = button,
		modifiers = previous.modifiers,
		coordinate_space = .Cell,
		row = row,
		column = column,
		root_generation = previous.root_generation,
		geometry_generation = previous.geometry_generation,
		sequence = interaction.Pointer_Sequence(sequence),
		capabilities = capabilities,
	}
}

@(private)
pointer_test_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	_ = allocator_data
	_ = mode
	_ = size
	_ = alignment
	_ = old_memory
	_ = old_size
	_ = location
	return nil, .Out_Of_Memory
}

@(private)
pointer_focus_test_renderer :: proc() -> ui.Renderer_Profile {
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
		max_rows = 24,
		max_columns = 80,
		max_cells = 1_920,
		attributes = {.Bold, .Dim, .Underline, .Reverse},
	}
}

@(private)
pointer_focus_test_close :: proc(t: ^testing.T, fixture: ^Pointer_Focus_Test_Fixture) {
	close_failure := command_context_close(&fixture.commands)
	testing.expect_value(t, close_failure.stage, App_Stage.None)
	shutdown_failure := session_shutdown_close(&fixture.session, fixture.handle)
	testing.expect_value(t, shutdown_failure.stage, App_Stage.None)
	fixture.handle = {}
}
