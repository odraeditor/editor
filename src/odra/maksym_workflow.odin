// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../document"
import "../interaction"
import "../product_module"
import "../ui"
import "core:path/filepath"

@(private)
Maksym_Open_Placement :: enum u8 {
	Current,
	Other_Pane,
	Below,
	Right,
}

@(private)
pointer_hit_is_current_maksym_item :: proc(
	commands: ^Command_Context,
	hit: ui.Semantic_Item_Hit,
) -> bool {
	if commands == nil || !commands.product_module_workflow.active ||
	   commands.product_module_workflow.active_role != .File_Management ||
	   hit.kind != .List || hit.item_id == 0 {
		return false
	}
	projection := &commands.product_module_workflow.projection
	index := int(hit.projection_index)
	if projection.generation == 0 || index < 0 || index >= len(projection.definitions) ||
	   hit.model.owner_id != PRODUCT_MODULE_UI_OWNER_ID ||
	   hit.model.model_id != PRODUCT_MODULE_UI_MODEL_ID ||
	   u64(hit.model.generation) != projection.generation ||
	   hit.presentation_generation != projection.generation {
		return false
	}
	definition := projection.definitions[index]
	return !definition.passive && u64(definition.id) == hit.item_id &&
	       definition.action.owner_id != 0 &&
	       definition.action.action_id == ui.List_Action_ID(hit.item_id) &&
	       definition.action.generation == projection.generation &&
	       hit.action == definition.action
}

@(private)
command_context_pointer_select_maksym_item :: proc(
	commands: ^Command_Context,
	hit: ui.Semantic_Item_Hit,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if !pointer_hit_is_current_maksym_item(commands, hit) {
		return {}, {stage = .Command_Dispatch}
	}
	result, failure := product_module_workflow_select_role(
		commands,
		.File_Management,
		hit.item_id,
		product_module.UI_LIST_SCHEMA_VERSION,
		constraints,
	)
	if failure.stage != .None do return result, failure
	projection := &commands.product_module_workflow.projection
	current := int(projection.position.current_item)
	if current < 0 || current >= len(projection.definitions) ||
	   u64(projection.definitions[current].id) != hit.item_id {
		return {}, {stage = .Command_Dispatch}
	}
	result.changed = true
	return result, {}
}

@(private)
command_context_open_maksym_directory :: proc(
	commands: ^Command_Context,
	path: string,
	_: Maksym_Open_Placement,
	_: display.Viewport_Constraints,
	_: interaction.Command_Handle = {},
	_: u64 = 0,
	_: bool = true,
	_: u8 = 0,
	_: u8 = 0,
	_: bool = true,
) -> (Interaction_Result, App_Failure) {
	return product_module_workflow_activate_file_management(commands, path)
}

@(private)
command_context_dispatch_maksym_route :: proc(
	commands: ^Command_Context,
	route: command.Native_Route,
	constraints: display.Viewport_Constraints,
	command_handle: interaction.Command_Handle,
) -> (Interaction_Result, App_Failure) {
	#partial switch route {
	case .Dir_Open, .Maksym_Open_Directory:
		return filesystem_path_navigation_begin(commands, .Find_File, command_handle, .Current, true)
	case .Maksym_Open_Directory_Other_Pane:
		return filesystem_path_navigation_begin(commands, .Find_File, command_handle, .Other_Pane, true)
	case .Maksym_Open_Directory_Below:
		return filesystem_path_navigation_begin(commands, .Find_File, command_handle, .Below, true)
	case .Maksym_Open_Directory_Right:
		return filesystem_path_navigation_begin(commands, .Find_File, command_handle, .Right, true)
	case .Maksym_Open_Containing_Directory, .Maksym_Open_Containing_Directory_Other_Pane:
		if commands.document_owner == nil {
			command_context_set_diagnostic(commands, "The active buffer has no containing directory")
			return {changed = true}, {}
		}
		status, inspected, _ := document.document_status(commands.document_owner)
		if !inspected || !status.has_target do return {}, {stage = .Document_Inspect}
		placement := Maksym_Open_Placement.Current
		if route == .Maksym_Open_Containing_Directory_Other_Pane do placement = .Other_Pane
		return command_context_open_maksym_directory(
			commands,
			filepath.dir(status.target_path),
			placement,
			constraints,
			command_handle,
		)
	case:
	}
	if commands.product_module_workflow.active_role != .File_Management ||
	   !commands.product_module_workflow.active {
		command_context_set_diagnostic(commands, "Maksym is unavailable")
		return {changed = true}, {}
	}
	metadata, found, metadata_failure := interaction.command_metadata(commands.registry, command_handle)
	if !found {
		return {}, {stage = .Command_Dispatch, interaction = metadata_failure}
	}
	return product_module_workflow_invoke(commands, metadata, constraints)
}
