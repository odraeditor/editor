// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../document"
import "../editor_session"
import "../interaction"
import "../layout"
import "../product_module"
import "../ui"
import "core:path/filepath"

@(private) DAREK_MIN_EDITOR_COLUMNS :: u32(20)
@(private) PRODUCT_MODULE_DAREK_UI_OWNER_ID :: ui.Owner_ID(0x4F44_5241_4441_5245)
@(private) PRODUCT_MODULE_DAREK_UI_MODEL_ID :: ui.Model_ID(1)

@(private)
Darek_Composition :: struct {
	present:       bool,
	root_node:     ui.Object_Handle,
	focus_surface: ui.Object_Handle,
	tree_surface:  ui.Object_Handle,
}

@(private)
darek_workflow_is_visible :: proc(commands: ^Command_Context) -> bool {
	return commands != nil && commands.product_module_workflow.workspace_hierarchy_available &&
		commands.product_module_workflow.tree_projection.visible
}

@(private)
darek_workflow_is_focused :: proc(commands: ^Command_Context) -> bool {
	return darek_workflow_is_visible(commands) && commands.product_module_workflow.tree_projection.focused
}

@(private)
command_context_pointer_select_darek_item :: proc(
	commands: ^Command_Context,
	item_id: u64,
	projection_index: u32,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || item_id == 0 ||
	   !product_module_workflow_role_available(commands, .Workspace_Hierarchy) {
		return {}, {stage = .Command_Dispatch}
	}
	projection := &commands.product_module_workflow.tree_projection
	index := int(projection_index)
	if !projection.visible || projection.generation == 0 || index < 0 ||
	   index >= len(projection.definitions) ||
	   u64(projection.definitions[index].id) != item_id {
		return {}, {stage = .Command_Dispatch}
	}
	result, failure := product_module_workflow_select_role(
		commands,
		.Workspace_Hierarchy,
		item_id,
		product_module.UI_TREE_PANEL_SCHEMA_VERSION,
		constraints,
	)
	if failure.stage != .None do return result, failure
	current := int(projection.position.current_item)
	if current < 0 || current >= len(projection.definitions) ||
	   u64(projection.definitions[current].id) != item_id {
		return {}, {stage = .Command_Dispatch}
	}
	result.changed = true
	return result, {}
}

@(private)
command_context_pointer_present_darek_actions :: proc(
	commands: ^Command_Context,
	item_id: u64,
	projection_index: u32,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	selection, selection_failure := command_context_pointer_select_darek_item(
		commands, item_id, projection_index, constraints,
	)
	if selection_failure.stage != .None do return selection, selection_failure
	handle, found, lookup_failure := interaction.command_lookup(commands.registry, "darek-context-actions")
	if !found do return selection, {stage = .Command_Resolution, interaction = lookup_failure}
	metadata, described, metadata_failure := interaction.command_metadata(commands.registry, handle)
	if !described do return selection, {stage = .Command_Dispatch, interaction = metadata_failure}
	result, failure := product_module_workflow_invoke_role(
		commands, .Workspace_Hierarchy, metadata, constraints,
	)
	result.changed = result.changed || selection.changed
	return result, failure
}

@(private)
darek_workflow_reserved_columns :: proc(commands: ^Command_Context, constraints: display.Viewport_Constraints) -> u32 {
	if !darek_workflow_is_visible(commands) || constraints.width_cells <= DAREK_MIN_EDITOR_COLUMNS + 1 do return 0
	return min(commands.product_module_workflow.tree_projection.panel_width, constraints.width_cells - DAREK_MIN_EDITOR_COLUMNS)
}

@(private)
darek_workflow_shift_layout_snapshot :: proc(commands: ^Command_Context, snapshot: ^layout.Snapshot) {
	if commands == nil || snapshot == nil || commands.product_module_workflow.tree_projection.panel_edge != .Left do return
	columns := u32(snapshot.geometry_request.global_reserved_columns)
	if columns == 0 do return
	for index in 0 ..< int(snapshot.node_count) {
		snapshot.nodes[index].geometry.outer.column += i32(columns)
		snapshot.nodes[index].geometry.content.column += i32(columns)
		snapshot.nodes[index].geometry.status.column += i32(columns)
		snapshot.nodes[index].geometry.separator.column += i32(columns)
	}
}

@(private)
darek_workflow_active_project_directory :: proc(commands: ^Command_Context) -> (string, bool) {
	if commands == nil || commands.session_owner == nil do return "", false
	active, active_ok, _ := editor_session.session_active_project(commands.session_owner, commands.session_handle)
	if !active_ok || !active.active do return "", false
	roots, roots_ok, _ := editor_session.session_roots(commands.session_owner, commands.session_handle)
	if !roots_ok do return "", false
	defer editor_session.root_batch_close(&roots)
	for root in roots.descriptors {
		if root.kind == .Project && root.project == active.descriptor.handle do return root.path, true
	}
	return "", false
}

@(private)
darek_workflow_initial_directory :: proc(commands: ^Command_Context) -> string {
	if path, ok := darek_workflow_active_project_directory(commands); ok do return path
	if commands != nil && commands.document_owner != nil {
		status, inspected, _ := document.document_status(commands.document_owner)
		if inspected && status.has_target do return filepath.dir(status.target_path)
	}
	return commands.home_directory if commands != nil else ""
}

@(private)
command_context_open_darek_directory :: proc(commands: ^Command_Context, path: string, _: display.Viewport_Constraints, _: interaction.Command_Handle = {}) -> (Interaction_Result, App_Failure) {
	return product_module_workflow_activate_workspace_hierarchy_directory(commands, path)
}

@(private)
command_context_open_darek_projects :: proc(commands: ^Command_Context, workspace_context: bool, _: display.Viewport_Constraints, _: interaction.Command_Handle = {}) -> (Interaction_Result, App_Failure) {
	return product_module_workflow_activate_workspace_hierarchy_projects(commands, workspace_context)
}

@(private)
command_context_open_darek_context :: proc(commands: ^Command_Context, constraints: display.Viewport_Constraints, command_handle: interaction.Command_Handle = {}) -> (Interaction_Result, App_Failure) {
	if commands != nil && commands.session_owner != nil {
		workspace, workspace_ok, _ := editor_session.session_active_workspace(commands.session_owner, commands.session_handle)
		if workspace_ok && workspace.active do return command_context_open_darek_projects(commands, true, constraints, command_handle)
		active, active_ok, _ := editor_session.session_active_project(commands.session_owner, commands.session_handle)
		if active_ok && active.active do return command_context_open_darek_projects(commands, false, constraints, command_handle)
	}
	return command_context_open_darek_directory(commands, darek_workflow_initial_directory(commands), constraints, command_handle)
}

@(private)
command_context_begin_darek_directory :: proc(commands: ^Command_Context, command_handle: interaction.Command_Handle) -> (Interaction_Result, App_Failure) {
	return filesystem_path_navigation_begin(commands, .Darek_Show_Directory, command_handle, initial_directory = darek_workflow_initial_directory(commands), darek_mode = true)
}

@(private)
command_context_dispatch_darek_route :: proc(commands: ^Command_Context, route: command.Native_Route, constraints: display.Viewport_Constraints, command_handle: interaction.Command_Handle) -> (Interaction_Result, App_Failure) {
	if route == .Darek_Show_Directory do return command_context_begin_darek_directory(commands, command_handle)
	if route == .Darek_Show_Current_Project do return command_context_open_darek_projects(commands, false, constraints, command_handle)
	module_runtime := product_module_workflow_runtime(commands, .Workspace_Hierarchy)
	if module_runtime == nil || module_runtime.lifecycle != .Active ||
	   commands.product_module_workflow.tree_projection.generation == 0 {
		if route == .Darek_Toggle || route == .Darek_Select || route == .Darek_Focus_Toggle {
			return command_context_open_darek_context(commands, constraints, command_handle)
		}
		return command_context_darek_unavailable(commands)
	}
	metadata, found, failure := interaction.command_metadata(commands.registry, command_handle)
	if !found do return {}, {stage = .Command_Dispatch, interaction = failure}
	return product_module_workflow_invoke_role(commands, .Workspace_Hierarchy, metadata, constraints)
}

@(private)
command_context_darek_unavailable :: proc(commands: ^Command_Context) -> (Interaction_Result, App_Failure) {
	command_context_set_diagnostic(commands, "Darek is unavailable")
	return {changed = true}, {}
}

@(private)
darek_workflow_follow_active :: proc(commands: ^Command_Context) -> bool {
	if commands == nil || commands.document_owner == nil ||
	   commands.context_pending.stroke_count > 0 {
		return false
	}
	runtime := product_module_workflow_runtime(commands, .Workspace_Hierarchy)
	if runtime == nil || runtime.lifecycle != .Active do return false
	status, inspected, _ := document.document_status(commands.document_owner)
	if !inspected || !status.has_target || len(status.target_path) == 0 do return false
	changed: [1]u8
	written, stepped, _ := product_module.call(
		runtime, .Step, transmute([]u8)status.target_path, changed[:],
	)
	return stepped && written == 1 && changed[0] == 1
}

@(private)
proposal_compose_darek_panel :: proc(proposal: ^ui.Proposal, commands: ^Command_Context, base_root, base_focus: ui.Object_Handle, constraints: display.Viewport_Constraints, profile: ui.Renderer_Profile_ID) -> (composition: Darek_Composition, ok: bool, failure: ui.Failure) {
	composition = {root_node = base_root, focus_surface = base_focus}
	width := darek_workflow_reserved_columns(commands, constraints)
	if width == 0 do return composition, true, {}
	projection := &commands.product_module_workflow.tree_projection
	tree_view, projected, projection_failure := ui.proposal_project_tree_view(proposal, {model = {owner_id = PRODUCT_MODULE_DAREK_UI_OWNER_ID, model_id = PRODUCT_MODULE_DAREK_UI_MODEL_ID, generation = ui.Model_Generation(projection.generation)}, position = projection.position, read_only = true}, projection.definitions)
	if !projected do return {}, false, projection_failure
	tree_surface, surfaced, surface_failure := ui.proposal_add_surface(proposal, {owner_id = PRODUCT_MODULE_DAREK_UI_OWNER_ID, view = tree_view, focusable = true, visible = true, required_profile = profile, geometry = {height = i32(constraints.height_rows - 1), width = i32(width)}})
	if !surfaced do return {}, false, surface_failure
	leaf, leaf_ok, leaf_failure := ui.proposal_add_surface_node(proposal, tree_surface)
	if !leaf_ok do return {}, false, leaf_failure
	panel, panel_ok, panel_failure := ui.proposal_add_panel(proposal, leaf, projection.panel_edge, width)
	if !panel_ok do return {}, false, panel_failure
	remaining := u64(max(u32(1), constraints.width_cells - width))
	root: ui.Object_Handle
	root_ok: bool
	root_failure: ui.Failure
	if projection.panel_edge == .Right {
		root, root_ok, root_failure = ui.proposal_add_split(proposal, base_root, panel, .Left_Right, remaining, u64(width))
	} else {
		root, root_ok, root_failure = ui.proposal_add_split(proposal, panel, base_root, .Left_Right, u64(width), remaining)
	}
	if !root_ok do return {}, false, root_failure
	focus := tree_surface if projection.focused else base_focus
	if set_ok, set_failure := ui.proposal_set_root(proposal, root, focus); !set_ok do return {}, false, set_failure
	return {present = true, root_node = root, focus_surface = focus, tree_surface = tree_surface}, true, {}
}

@(private)
darek_workflow_close :: proc(commands: ^Command_Context) {
	if commands == nil do return
	runtime := product_module_workflow_runtime(commands, .Workspace_Hierarchy)
	if runtime != nil && runtime.lifecycle == .Active do _, _, _ = product_module.call(runtime, .Deactivate, nil, nil)
	product_module_tree_projection_close(&commands.product_module_workflow.tree_projection, commands.persistent_allocator)
}

@(private)
command_context_sync_darek_map :: proc(commands: ^Command_Context) -> App_Failure {
	bindings: [interaction.MAX_CONTEXT_BINDINGS]interaction.Binding_Definition
	count := 0
	command_context_add_prompt_binding(bindings[:], &count, darek_focus_toggle_sequence(), "darek-focus-toggle")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('n', {}), "darek-next-node")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('p', {}), "darek-previous-node")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_special(.Down), "darek-next-node")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_special(.Up), "darek-previous-node")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('n', {.Alt}), "darek-next-sibling")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('p', {.Alt}), "darek-previous-sibling")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('j', {.Control}), "darek-next-project")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('k', {.Control}), "darek-previous-project")
	command_context_add_prompt_binding(bindings[:], &count, darek_modified_special(.Up, {.Alt}), "darek-move-project-up")
	command_context_add_prompt_binding(bindings[:], &count, darek_modified_special(.Down, {.Alt}), "darek-move-project-down")
	command_context_add_prompt_binding(bindings[:], &count, darek_project_sequence('a'), "darek-project-add")
	command_context_add_prompt_binding(bindings[:], &count, darek_project_sequence('d'), "darek-project-remove")
	command_context_add_prompt_binding(bindings[:], &count, darek_project_sequence('r'), "darek-project-rename")
	command_context_add_prompt_binding(bindings[:], &count, darek_project_collapse_sequence('c'), "darek-project-collapse")
	command_context_add_prompt_binding(bindings[:], &count, darek_project_collapse_sequence('o'), "darek-project-collapse-others")
	command_context_add_prompt_binding(bindings[:], &count, darek_project_collapse_sequence('a'), "darek-collapse-all-projects")
	command_context_add_prompt_binding(bindings[:], &count, darek_workspace_sequence('s'), "darek-workspace-switch")
	command_context_add_prompt_binding(bindings[:], &count, darek_workspace_sequence('n'), "darek-workspace-next")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('H', {.Alt}), "darek-root-parent")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('L', {.Alt}), "darek-root-current-directory")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('u', {}), "darek-parent-node")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_special(.Tab), "darek-structure-action")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_special(.Enter), "darek-visit-action")
	command_context_add_prompt_binding(bindings[:], &count, darek_open_sequence('o'), "darek-open")
	command_context_add_prompt_binding(bindings[:], &count, darek_open_sequence('v'), "darek-open-split-below")
	command_context_add_prompt_binding(bindings[:], &count, darek_open_sequence('h'), "darek-open-split-right")
	command_context_add_prompt_binding(bindings[:], &count, darek_open_sequence('c'), "darek-open-and-hide")
	command_context_add_prompt_binding(bindings[:], &count, darek_open_sequence('r'), "darek-open-mru-pane")
	command_context_add_prompt_binding(bindings[:], &count, darek_open_sequence('x'), "darek-open-external")
	command_context_add_prompt_binding(bindings[:], &count, darek_resource_sequence('c', 'f'), "darek-create-file")
	command_context_add_prompt_binding(bindings[:], &count, darek_resource_sequence('c', 'd'), "darek-create-directory")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('R', {}), "darek-rename-node")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('m', {}), "darek-move-node")
	command_context_add_prompt_binding(bindings[:], &count, darek_resource_sequence('y', 'f'), "darek-copy-node")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('d', {}), "darek-delete-node")
	command_context_add_prompt_binding(bindings[:], &count, darek_resource_sequence('y', 'a'), "darek-copy-absolute-path")
	command_context_add_prompt_binding(bindings[:], &count, darek_resource_sequence('y', 'r'), "darek-copy-project-relative-path")
	command_context_add_prompt_binding(bindings[:], &count, darek_resource_sequence('y', 'p'), "darek-copy-project-root")
	command_context_add_prompt_binding(bindings[:], &count, darek_resource_sequence('y', 'n'), "darek-copy-name")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('h', {}), "darek-collapse-or-parent")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('h', {.Alt}), "darek-collapse-or-parent")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('l', {}), "darek-structure-action")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('l', {.Alt}), "darek-structure-action")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_special(.Left), "darek-collapse-or-parent")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_special(.Right), "darek-structure-action")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('H', {}), "darek-collapse-parent")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('r', {}), "darek-refresh")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('g', {}), "darek-refresh")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('P', {}), "darek-toggle-peek")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('N', {.Alt}), "darek-other-pane-next-line")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('P', {.Alt}), "darek-other-pane-previous-line")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_special(.Next), "darek-other-pane-next-page")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_special(.Prior), "darek-other-pane-previous-page")
	command_context_add_prompt_binding(bindings[:], &count, darek_resource_sequence('t', 'f'), "darek-toggle-file-follow")
	command_context_add_prompt_binding(bindings[:], &count, darek_resource_sequence('t', 'h'), "darek-toggle-hidden-files")
	command_context_add_prompt_binding(bindings[:], &count, darek_resource_sequence('t', 'i'), "darek-toggle-vcs-ignored")
	command_context_add_prompt_binding(bindings[:], &count, darek_resource_sequence('t', 'a'), "darek-toggle-file-watch")
	command_context_add_prompt_binding(bindings[:], &count, darek_resource_sequence('t', 'g'), "darek-toggle-vcs-decorations")
	command_context_add_prompt_binding(bindings[:], &count, darek_resource_sequence('t', 'd'), "darek-toggle-vcs-decorations")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('s', {}), "darek-select-sort")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('/', {}), "darek-filter")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('!', {}), "darek-shell-command")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('!', {.Alt}), "darek-shell-command-project")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('m', {.Alt}), "darek-bulk-actions")
	command_context_add_prompt_binding(bindings[:], &count, darek_modified_special(.Enter, {.Alt}), "darek-context-actions")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('<', {}), "darek-decrease-width")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('>', {}), "darek-increase-width")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('=', {}), "darek-fit-width")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('W', {}), "darek-toggle-extra-width")
	command_context_add_prompt_binding(bindings[:], &count, darek_resource_sequence('t', 'w'), "darek-toggle-width-lock")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('?', {}), "darek-help")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('?', {.Control}), "darek-help-advanced")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_special(.Backspace), "darek-help-advanced")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('q', {}), "darek-hide")
	command_context_add_prompt_binding(bindings[:], &count, command_context_prompt_scalar('Q', {}), "darek-close")
	return command_context_sync_context_map(commands, 3_030, 4_030, "darek-tree-panel", .Fallthrough, "", bindings[:count])
}

@(private)
darek_modified_special :: proc(
	kind: interaction.Logical_Key_Kind,
	modifiers: interaction.Modifiers,
) -> interaction.Key_Sequence {
	sequence: interaction.Key_Sequence
	sequence.stroke_count = 1
	sequence.strokes[0] = {kind = kind, modifiers = modifiers}
	return sequence
}

@(private)
darek_project_sequence :: proc(action: rune) -> interaction.Key_Sequence {
	sequence: interaction.Key_Sequence
	sequence.stroke_count = 3
	sequence.strokes[0] = {kind = .Unicode_Scalar, scalar = 'c', modifiers = {.Control}}
	sequence.strokes[1] = {kind = .Unicode_Scalar, scalar = 'p', modifiers = {.Control}}
	sequence.strokes[2] = {kind = .Unicode_Scalar, scalar = action}
	return sequence
}

@(private)
darek_project_collapse_sequence :: proc(action: rune) -> interaction.Key_Sequence {
	sequence := darek_project_sequence('c')
	sequence.stroke_count = 4
	sequence.strokes[3] = {kind = .Unicode_Scalar, scalar = action}
	return sequence
}

@(private)
darek_focus_toggle_sequence :: proc() -> interaction.Key_Sequence {
	sequence: interaction.Key_Sequence
	sequence.stroke_count = 3
	sequence.strokes[0] = {kind = .Unicode_Scalar, scalar = 'x', modifiers = {.Control}}
	sequence.strokes[1] = {kind = .Unicode_Scalar, scalar = 't'}
	sequence.strokes[2] = {kind = .Unicode_Scalar, scalar = 'o'}
	return sequence
}

@(private)
darek_resource_sequence :: proc(prefix, action: rune) -> interaction.Key_Sequence {
	sequence: interaction.Key_Sequence
	sequence.stroke_count = 2
	sequence.strokes[0] = {kind = .Unicode_Scalar, scalar = prefix}
	sequence.strokes[1] = {kind = .Unicode_Scalar, scalar = action}
	return sequence
}

@(private)
darek_workspace_sequence :: proc(action: rune) -> interaction.Key_Sequence {
	sequence: interaction.Key_Sequence
	sequence.stroke_count = 3
	sequence.strokes[0] = {kind = .Unicode_Scalar, scalar = 'c', modifiers = {.Control}}
	sequence.strokes[1] = {kind = .Unicode_Scalar, scalar = 'w', modifiers = {.Control}}
	sequence.strokes[2] = {kind = .Unicode_Scalar, scalar = action}
	return sequence
}

@(private)
darek_open_sequence :: proc(action: rune) -> interaction.Key_Sequence {
	sequence: interaction.Key_Sequence
	sequence.stroke_count = 2
	sequence.strokes[0] = {kind = .Unicode_Scalar, scalar = 'o'}
	sequence.strokes[1] = {kind = .Unicode_Scalar, scalar = action}
	return sequence
}
