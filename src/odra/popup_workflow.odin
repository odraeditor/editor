// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../ui"

@(private)
Popup_Workflow_State :: struct {
	active:           bool,
	root:             ui.Root_Handle,
	popup:            ui.Object_Handle,
	popup_id:         ui.Popup_ID,
	popup_generation: ui.Popup_Generation,
	owner_id:         ui.Owner_ID,
	owner_generation: u64,
	source_focus:     ui.Object_Handle,
	dismissal:        ui.Popup_Dismissal_Policy,
}

@(private)
Popup_Dismissal_Event :: struct {
	dismissed:    bool,
	cause:        ui.Popup_Dismissal_Cause,
	root:         ui.Root_Handle,
	popup:        ui.Object_Handle,
	source_focus: ui.Object_Handle,
}

@(private)
popup_workflow_activate :: proc(
	state: ^Popup_Workflow_State,
	root: ui.Root_Handle,
	popup: ui.Popup_Descriptor,
	focus: ui.Focus_Descriptor,
) -> bool {
	if state == nil || root.registry_id == ui.Registry_ID(0) ||
	   root.generation == ui.Root_Generation(0) ||
	   popup.handle.registry_id != root.registry_id ||
	   popup.handle.root_generation != root.generation ||
	   popup.handle.object_id == ui.Object_ID(0) || popup.id == ui.Popup_ID(0) ||
	   popup.generation == ui.Popup_Generation(0) || popup.owner_id == ui.Owner_ID(0) ||
	   popup.owner_generation == 0 || popup.behavior != .Informational ||
	   popup.input_policy != .Preserve_Source_Focus || popup.dismissal == {} ||
	   popup.anchor.source_surface.object_id == ui.Object_ID(0) || focus.captured ||
	   focus.target != popup.anchor.source_surface {
		return false
	}
	if state.active {
		if root.registry_id != state.root.registry_id || root.generation <= state.root.generation {
			return false
		}
		if popup.id == state.popup_id && popup.generation <= state.popup_generation {
			return false
		}
	}
	state^ = Popup_Workflow_State {
		active = true,
		root = root,
		popup = popup.handle,
		popup_id = popup.id,
		popup_generation = popup.generation,
		owner_id = popup.owner_id,
		owner_generation = popup.owner_generation,
		source_focus = focus.target,
		dismissal = popup.dismissal,
	}
	return true
}

@(private)
popup_workflow_dismiss :: proc(
	state: ^Popup_Workflow_State,
	cause: ui.Popup_Dismissal_Cause,
	current_root: ui.Root_Handle,
) -> (event: Popup_Dismissal_Event, handled: bool) {
	if state == nil || !state.active || cause not_in state.dismissal ||
	   (current_root.generation != ui.Root_Generation(0) && current_root != state.root) {
		return {}, false
	}
	event = Popup_Dismissal_Event {
		dismissed = true,
		cause = cause,
		root = state.root,
		popup = state.popup,
		source_focus = state.source_focus,
	}
	state^ = {}
	return event, true
}

@(private)
popup_workflow_reconcile_root :: proc(
	state: ^Popup_Workflow_State,
	current_root: ui.Root_Handle,
) -> (event: Popup_Dismissal_Event, dismissed: bool) {
	if state == nil || !state.active || current_root == state.root {
		return {}, false
	}
	return popup_workflow_dismiss(state, .Generation_Replacement, {})
}

@(private)
popup_workflow_close :: proc(state: ^Popup_Workflow_State) {
	if state != nil do state^ = {}
}
