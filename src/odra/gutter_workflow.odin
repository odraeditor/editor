// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../editor"
import "../gutter"
import "../interaction"
import "../ui"
import editor_view "../view"
import "core:fmt"

@(private)
command_context_apply_gutter_command :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	route: command.Native_Route,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || buffer == nil || view_registry == nil {
		return {}, App_Failure{stage = .View_Snapshot}
	}
	if route == .Gutter_Inspect_Markers do return command_context_inspect_gutter_marker(commands)
	if route == .Gutter_Refresh_Markers do return command_context_restart_language_service(commands, buffer)
	if route == .Gutter_Invoke_Primary_Marker_Action {
		return command_context_invoke_gutter_marker_action(
			commands, buffer, view_registry, view, constraints,
		)
	}
	logical, logical_ok, logical_failure := editor_view.snapshot(view_registry, view)
	if !logical_ok {
		return {}, App_Failure{stage = .View_Snapshot, view = logical_failure}
	}
	policy := commands.gutter_policy
	if logical.gutter.overrides_default do policy = logical.gutter.policy

	if route == .Gutter_Inspect_Numbering {
		source := "default"
		if logical.gutter.overrides_default do source = "view"
		message := fmt.bprintf(
			commands.diagnostic[:],
			"Gutter numbering: mode=%s scope=%s side=%s visible=%s source=%s",
			gutter_numbering_mode_name(policy.mode),
			gutter_numbering_scope_name(policy.scope),
			gutter_side_name(policy.side),
			"yes" if policy.visible else "no",
			source,
		)
		commands.diagnostic_length = len(message)
		return Interaction_Result{changed = true}, {}
	}

	#partial switch route {
	case .Gutter_Toggle_Line_Numbers:
		policy.visible = !policy.visible
	case .Gutter_Cycle_Line_Number_Mode:
		switch policy.mode {
		case .None:     policy.mode = .Absolute
		case .Absolute: policy.mode = .Relative
		case .Relative: policy.mode = .Hybrid
		case .Hybrid:   policy.mode = .None
		case .Invalid:  return {}, App_Failure{stage = .View_Snapshot}
		}
	case .Gutter_Set_Line_Numbers_None:     policy.mode = .None
	case .Gutter_Set_Line_Numbers_Absolute: policy.mode = .Absolute
	case .Gutter_Set_Line_Numbers_Relative: policy.mode = .Relative
	case .Gutter_Set_Line_Numbers_Hybrid:   policy.mode = .Hybrid
	case .Gutter_Set_Numbering_Logical:
		policy.scope = .Logical
	case .Gutter_Set_Numbering_Visual:
		command_context_set_diagnostic(commands, "Visual Gutter numbering is unavailable")
		return Interaction_Result{changed = true}, {}
	case .Gutter_Toggle_Line_Number_Side:
		policy.side = .Right if policy.side == .Left else .Left
	case .Invalid, .Gutter_Inspect_Numbering, .Gutter_Inspect_Markers,
	     .Gutter_Refresh_Markers, .Gutter_Invoke_Primary_Marker_Action:
		return {}, App_Failure{stage = .Command_Dispatch}
	case:
		return {}, App_Failure{stage = .Command_Dispatch}
	}

	updated, update_failure := editor_view.set_gutter_policy(
		view_registry,
		view,
		policy,
		true,
	)
	if !updated {
		return {}, App_Failure{stage = .View_Snapshot, view = update_failure}
	}
	message := fmt.bprintf(
		commands.diagnostic[:],
		"Gutter numbering: mode=%s scope=%s side=%s visible=%s",
		gutter_numbering_mode_name(policy.mode),
		gutter_numbering_scope_name(policy.scope),
		gutter_side_name(policy.side),
		"yes" if policy.visible else "no",
	)
	commands.diagnostic_length = len(message)
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_inspect_gutter_marker :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	marker, index, available := gutter_inspection_current(commands.gutter_inspection)
	if !available {
		gutter_inspection_popup_dismiss(commands.gutter_inspection)
		popup_fallback_clear(&commands.popup_fallback)
		command_context_set_diagnostic(commands, "No semantic Gutter markers at the active line")
		return Interaction_Result{changed = true}, {}
	}
	if !gutter_inspection_popup_open(commands.gutter_inspection, marker, index) {
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	detail := string(marker.detail[:marker.detail_length])
	popup_fallback_clear(&commands.popup_fallback)
	presentation_profile, profile_ok, profile_failure :=
		command_context_contextual_presentation_profile(commands)
	if !profile_ok do return {}, profile_failure
	if popup_fallback_required(
		commands.renderer_profile,
		presentation_profile.definition.bounds,
	) {
		definition := presentation_profile.definition
		style_role, style_ok := ui.presentation_profile_definition_style(
			&definition,
			gutter_popup_style_slot(marker.role),
		)
		if !style_ok {
			return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Invalid_Style}}
		}
		prepared := popup_fallback_prepare(
			&commands.popup_fallback,
			GUTTER_POPUP_OWNER_ID,
			commands.gutter_inspection.popup_generation,
			detail,
			style_role,
			commands.persistent_allocator,
		)
		if !prepared {
			return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Allocation}}
		}
	}
	commands.gutter_inspection.next_index = (index + 1) % commands.gutter_inspection.marker_count
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_invoke_gutter_marker_action :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	marker, _, available := gutter_inspection_current(commands.gutter_inspection)
	if !available || !marker.actionable {
		command_context_set_diagnostic(commands, "No Gutter marker action at the active line")
		return Interaction_Result{changed = true}, {}
	}
	handle := interaction.Command_Handle {
		registry_generation = interaction.Registry_Generation(marker.action.registry_generation),
		slot = marker.action.slot,
		entry_generation = marker.action.entry_generation,
	}
	metadata, found, _ := interaction.command_metadata(commands.registry, handle)
	if !found || handle.registry_generation != commands.registry_generation {
		command_context_set_diagnostic(commands, "Gutter marker action is stale or unavailable")
		return Interaction_Result{changed = true}, {}
	}
	if action_route, native := command.native_route_decode(metadata.route);
	   native && action_route == .Gutter_Invoke_Primary_Marker_Action {
		command_context_set_diagnostic(commands, "Gutter marker action cannot invoke itself")
		return Interaction_Result{changed = true}, {}
	}
	return Interaction_Result{changed = true, deferred_command = handle}, {}
}

@(private)
gutter_numbering_mode_name :: proc(mode: gutter.Numbering_Mode) -> string {
	switch mode {
	case .None:     return "none"
	case .Absolute: return "absolute"
	case .Relative: return "relative"
	case .Hybrid:   return "hybrid"
	case .Invalid:  return "invalid"
	}
	return "invalid"
}

@(private)
gutter_numbering_scope_name :: proc(scope: gutter.Numbering_Scope) -> string {
	switch scope {
	case .Logical: return "logical"
	case .Visual:  return "visual"
	case .Invalid: return "invalid"
	}
	return "invalid"
}

@(private)
gutter_side_name :: proc(side: gutter.Side) -> string {
	switch side {
	case .Left:  return "left"
	case .Right: return "right"
	case .Invalid: return "invalid"
	}
	return "invalid"
}
