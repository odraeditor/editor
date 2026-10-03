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
import "../terminal_session"
import "../ui"
import editor_view "../view"
import "core:time"

@(private)
MAX_POINTER_CAPTURE_EVENTS :: u32(4_096)
@(private)
MAX_POINTER_CAPTURE_DURATION_NS :: i64(30 * time.Second)

@(private)
Pointer_Text_Capture :: struct {
	active:                    bool,
	frontend:                  interaction.Pointer_Frontend_ID,
	source:                    interaction.Pointer_Source_ID,
	button:                    interaction.Pointer_Button,
	root_generation:           interaction.Pointer_Root_Generation,
	geometry_generation:       interaction.Pointer_Geometry_Generation,
	last_sequence:             interaction.Pointer_Sequence,
	started_at:                time.Tick,
	event_count:               u32,
	registry:                  ^editor_view.Registry,
	view:                      editor_view.View_Handle,
	snapshot:                  display.Snapshot,
	origin_position:           editor.Position,
	content_row:               i32,
	content_column:            i32,
	view_state_generation:     u64,
	selection_generation:      u64,
	dragged:                   bool,
}

@(private)
Pointer_Terminal_Target :: struct {
	ref:   terminal_session.Session_Ref,
	entry: ^Terminal_Workflow_Entry,
}

@(private)
Pointer_Semantic_Focus_Owner :: enum u8 {
	Invalid,
	Pane,
	Darek,
	Surface,
}

@(private)
Pointer_Semantic_Focus_Plan :: struct {
	previous:       Pointer_Semantic_Focus_Owner,
	target:         Pointer_Semantic_Focus_Owner,
	release_darek:  bool,
	acquire_darek:  bool,
}

@(private)
command_context_pointer_focus :: proc(
	commands: ^Command_Context,
	session_owner: ^editor_session.Session,
	session_handle: editor_session.Session_Handle,
	event: interaction.Pointer_Event,
	coalesced_motion: u16 = 0,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || session_owner == nil ||
	   !interaction.pointer_event_is_valid(event) ||
	   (coalesced_motion > 0 && event.action != .Motion) {
		if commands != nil do pointer_text_capture_clear(commands)
		return {}, App_Failure{stage = .Input}
	}
	if event.action == .Cancel {
		if pointer_text_capture_matches_source(&commands.pointer_text_capture, event) {
			pointer_text_capture_clear(commands)
		} else if commands.terminal_workflow != nil &&
		          pointer_terminal_capture_matches_source(&commands.terminal_workflow.pointer_capture, event) {
			pointer_terminal_capture_clear(commands.terminal_workflow)
		}
		return {}, {}
	}
	if event.action == .Motion || event.action == .Release {
		if commands.terminal_workflow != nil && commands.terminal_workflow.pointer_capture.active {
			return command_context_pointer_terminal_capture_event(commands, event, coalesced_motion)
		}
		return command_context_pointer_text_capture_event(commands, event, coalesced_motion)
	}
	if event.action != .Press && event.action != .Wheel do return {}, {}
	pointer_text_capture_clear(commands)
	primary_press := event.action == .Press && event.button == .Primary
	if u64(event.root_generation) != u64(commands.ui_root.generation) {
		return {}, App_Failure {
			stage = .UI,
			ui = {
				operation = .Hit_Test,
				code = .Stale_Root,
				root = commands.ui_root,
			},
		}
	}
	allocator := commands.temporary_allocator
	if allocator.procedure == nil do allocator = context.temp_allocator
	snapshot, copied, copy_failure := ui.registry_snapshot(
		&commands.ui_registry,
		commands.ui_root,
		commands.renderer_profile,
		allocator,
	)
	if !copied do return {}, App_Failure{stage = .UI, ui = copy_failure}
	defer ui.snapshot_close(&snapshot)
	view, viewed := ui.snapshot_view(&snapshot)
	if !viewed do return {}, App_Failure{stage = .UI}
	hit, hit_ok, hit_failure := ui.snapshot_hit_test(
		view,
		ui.Hit_Request {
			root = commands.ui_root,
			row = i32(event.row),
			column = i32(event.column),
		},
	)
	if !hit_ok do return {}, App_Failure{stage = .UI, ui = hit_failure}
	if hit.kind == .Popup || hit.kind == .Background || !hit.focusable {
		return {}, {}
	}
	if view.focus.captured || view.focus.transient.active do return {}, {}
	darek_surface := pointer_hit_is_darek_surface(commands, view, hit)
	darek_item := darek_surface && pointer_hit_is_current_darek_item(commands, hit)
	focus_plan, focus_planned := pointer_semantic_focus_plan(
		darek_workflow_is_focused(commands),
		hit.pane.present,
		darek_item,
		darek_surface,
	)
	if !focus_planned do return {}, {}
	focus_constraints := display.Viewport_Constraints {
		width_cells = view.renderer.max_columns,
		height_rows = view.renderer.max_rows,
	}
	if darek_item && event.action == .Press &&
	   (event.button == .Primary || event.button == .Secondary) {
		focus_result: Interaction_Result
		if focus_plan.acquire_darek {
			focus_failure: App_Failure
			focus_result, focus_failure = command_context_pointer_set_darek_focus(
				commands, true, focus_constraints,
			)
			if focus_failure.stage != .None do return focus_result, focus_failure
		}
		selection_result: Interaction_Result
		selection_failure: App_Failure
		if event.button == .Secondary {
			selection_result, selection_failure = command_context_pointer_present_darek_actions(
				commands,
				hit.item.item_id,
				hit.item.projection_index,
				focus_constraints,
			)
		} else {
			selection_result, selection_failure = command_context_pointer_select_darek_item(
				commands,
				hit.item.item_id,
				hit.item.projection_index,
				focus_constraints,
			)
		}
		if selection_failure.stage != .None {
			if focus_plan.acquire_darek {
				_, restore_failure := command_context_pointer_set_darek_focus(
					commands, false, focus_constraints,
				)
				if restore_failure.stage != .None do return {}, restore_failure
			}
			return {}, selection_failure
		}
		selection_result.changed = selection_result.changed || focus_result.changed
		return selection_result, {}
	}
	if commands.product_module_workflow.active {
		if primary_press {
			surface, surface_ok, surface_failure := ui.registry_inspect_surface(&commands.ui_registry, hit.surface)
			if !surface_ok do return {}, App_Failure{stage = .UI, ui = surface_failure}
			if surface.owner_id == PRODUCT_MODULE_UI_OWNER_ID && int(hit.view.slot) < len(view.views) {
				visual := view.views[hit.view.slot]
				if visual.handle == hit.view && visual.kind == .List_View &&
				   pointer_hit_is_current_maksym_item(commands, hit.item) {
					darek_released := false
					darek_release_changed := false
					if focus_plan.release_darek {
						release_result, release_failure := command_context_pointer_set_darek_focus(
							commands, false, focus_constraints,
						)
						if release_failure.stage != .None do return {}, release_failure
						darek_released = true
						darek_release_changed = release_result.changed
					}
					result, selection_failure := command_context_pointer_select_maksym_item(
						commands, hit.item, focus_constraints,
					)
					if selection_failure.stage != .None {
						if darek_released {
							_, restore_failure := command_context_pointer_set_darek_focus(
								commands, true, focus_constraints,
							)
							if restore_failure.stage != .None do return {}, restore_failure
						}
						return {}, selection_failure
					}
					result.changed = result.changed || darek_release_changed
					return result, {}
				}
			}
		}
		return {}, {}
	}
	if hit.pane.present {
		text_hit: display.Text_Hit
		text_snapshot: display.Snapshot
		text_registry: ^editor_view.Registry
		text_view: editor_view.View_Handle
		text_mapped := false
		terminal_target: Pointer_Terminal_Target
		terminal_mapped := false
		if hit.kind == .Content && primary_press {
			text_failure: App_Failure
			text_hit, text_snapshot, text_registry, text_view, text_mapped, text_failure =
				command_context_pointer_text_hit(commands, hit)
			if text_failure.stage != .None do return {}, text_failure
		}
		if hit.kind == .Content && !text_mapped {
			terminal_failure: App_Failure
			terminal_target, terminal_mapped, terminal_failure =
				command_context_pointer_terminal_target(commands, hit)
			if terminal_failure.stage != .None do return {}, terminal_failure
		}
		defer if text_snapshot.state != nil do display.snapshot_close(&text_snapshot)
		if !primary_press && !terminal_mapped do return {}, {}
		if !hit.pane.active && !primary_press do return {}, {}
		darek_released := false
		darek_release_changed := false
		if focus_plan.release_darek {
			release_result, release_failure := command_context_pointer_set_darek_focus(
				commands, false, focus_constraints,
			)
			if release_failure.stage != .None do return {}, release_failure
			darek_released = true
			darek_release_changed = release_result.changed
		}
		result, focus_failure := command_context_pointer_focus_pane(
			commands,
			session_owner,
			session_handle,
			hit,
		)
		if focus_failure.stage != .None {
			if darek_released {
				_, restore_failure := command_context_pointer_set_darek_focus(
					commands, true, focus_constraints,
				)
				if restore_failure.stage != .None do return {}, restore_failure
			}
			return result, focus_failure
		}
		result.changed = result.changed || darek_release_changed
		if terminal_mapped {
			if !hit.pane.active do return result, {}
			terminal_result, terminal_failure := command_context_pointer_terminal_press(
				commands, terminal_target, hit, event,
			)
			terminal_result.changed = terminal_result.changed || result.changed
			return terminal_result, terminal_failure
		}
		if !text_mapped do return result, {}
		desired_column := u32(text_hit.span_start)
		if text_hit.affinity == .Trailing do desired_column = u32(text_hit.span_end)
		logical, logical_ok, logical_failure := editor_view.snapshot(text_registry, text_view)
		if !logical_ok {
			return {}, App_Failure{stage = .View_Snapshot, view = logical_failure}
		}
		desired_column += logical.horizontal_display_column
		moved, move_failure := editor_view.move_point(
			text_registry,
			text_view,
			text_hit.position,
			desired_column,
			.Deactivate,
		)
		if !moved do return {}, App_Failure{stage = .View_Snapshot, view = move_failure}
		confirmed, confirmed_ok, confirmed_failure := editor_view.snapshot(text_registry, text_view)
		if !confirmed_ok {
			return {}, App_Failure{stage = .View_Snapshot, view = confirmed_failure}
		}
		pointer_text_capture_begin(
			commands,
			event,
			text_registry,
			text_view,
			text_hit,
			&text_snapshot,
			confirmed,
		)
		result.changed = true
		return result, {}
	}
	if hit.surface.object_id == ui.Object_ID(0) do return {}, {}
	darek_released := false
	darek_release_changed := false
	if focus_plan.release_darek {
		release_result, release_failure := command_context_pointer_set_darek_focus(
			commands, false, focus_constraints,
		)
		if release_failure.stage != .None do return {}, release_failure
		darek_released = true
		darek_release_changed = release_result.changed
	}
	if view.focus.target == hit.surface {
		return Interaction_Result{changed = darek_release_changed}, {}
	}
	focused, focus_failure := ui.registry_focus_surface(&commands.ui_registry, hit.surface)
	if !focused {
		if darek_released {
			_, restore_failure := command_context_pointer_set_darek_focus(
				commands, true, focus_constraints,
			)
			if restore_failure.stage != .None do return {}, restore_failure
		}
		return {}, App_Failure{stage = .UI, ui = focus_failure}
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
pointer_semantic_focus_plan :: proc(
	darek_focused, pane_target, darek_item, darek_surface: bool,
) -> (plan: Pointer_Semantic_Focus_Plan, ok: bool) {
	plan.previous = .Darek if darek_focused else .Pane
	if darek_surface {
		if !darek_item do return {}, false
		plan.target = .Darek
		plan.acquire_darek = !darek_focused
		return plan, true
	}
	plan.target = .Pane if pane_target else .Surface
	plan.release_darek = darek_focused
	return plan, true
}

@(private)
pointer_hit_is_darek_surface :: proc(
	commands: ^Command_Context,
	snapshot: ui.Snapshot_View,
	hit: ui.Hit_Result,
) -> bool {
	if commands == nil || !darek_workflow_is_visible(commands) ||
	   hit.surface.object_id == ui.Object_ID(0) {
		return false
	}
	for surface in snapshot.surfaces {
		if surface.handle == hit.surface {
			return surface.owner_id == PRODUCT_MODULE_DAREK_UI_OWNER_ID
		}
	}
	return false
}

@(private)
pointer_hit_is_current_darek_item :: proc(
	commands: ^Command_Context,
	hit: ui.Hit_Result,
) -> bool {
	if commands == nil || hit.kind != .Content || hit.item.kind != .Tree ||
	   hit.item.item_id == 0 || hit.item.action.owner_id != PRODUCT_MODULE_DAREK_UI_OWNER_ID ||
	   u64(hit.item.action.action_id) != hit.item.item_id ||
	   hit.item.action.generation != hit.item.presentation_generation {
		return false
	}
	projection := &commands.product_module_workflow.tree_projection
	index := int(hit.item.projection_index)
	return projection.visible && projection.generation != 0 &&
	       hit.item.model.owner_id == PRODUCT_MODULE_DAREK_UI_OWNER_ID &&
	       hit.item.model.model_id == PRODUCT_MODULE_DAREK_UI_MODEL_ID &&
	       u64(hit.item.model.generation) == projection.generation &&
	       hit.item.presentation_generation == projection.generation &&
	       index >= 0 && index < len(projection.definitions) &&
	       u64(projection.definitions[index].id) == hit.item.item_id
}

@(private)
command_context_pointer_set_darek_focus :: proc(
	commands: ^Command_Context,
	focused: bool,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.registry == nil do return {}, {stage = .Command_Dispatch}
	if darek_workflow_is_focused(commands) == focused do return {}, {}
	command_name := "darek-select" if focused else "darek-focus-toggle"
	handle, found, lookup_failure := interaction.command_lookup(commands.registry, command_name)
	if !found {
		return {}, {stage = .Command_Resolution, interaction = lookup_failure}
	}
	metadata, metadata_ok, metadata_failure := interaction.command_metadata(commands.registry, handle)
	if !metadata_ok {
		return {}, {stage = .Command_Dispatch, interaction = metadata_failure}
	}
	result, failure := product_module_workflow_invoke_role(
		commands,
		.Workspace_Hierarchy,
		metadata,
		constraints,
	)
	if failure.stage != .None do return result, failure
	if darek_workflow_is_focused(commands) != focused {
		return {}, {stage = .Command_Dispatch}
	}
	result.changed = true
	return result, {}
}

@(private)
command_context_pointer_terminal_target :: proc(
	commands: ^Command_Context,
	hit: ui.Hit_Result,
) -> (target: Pointer_Terminal_Target, mapped: bool, failure: App_Failure) {
	if commands == nil || commands.session_owner == nil || commands.terminal_workflow == nil {
		return {}, false, App_Failure{stage = .Terminal_Workflow}
	}
	visual, visual_ok, visual_failure := ui.registry_inspect_view(&commands.ui_registry, hit.view)
	if !visual_ok do return {}, false, App_Failure{stage = .UI, ui = visual_failure}
	if visual.kind != .Terminal_View || !visual.terminal.present do return {}, false, {}
	layout_target, target_ok, target_failure := pointer_text_layout_target(commands, hit)
	if target_failure.stage != .None do return {}, false, target_failure
	if !target_ok do return {}, false, App_Failure{stage = .Layout}
	state, state_ok, state_failure := editor_session.session_terminal_buffer_state(
		commands.session_owner,
		layout_target.entry,
	)
	if !state_ok {
		return {}, false, App_Failure{stage = .Session_Access, editor_session = state_failure}
	}
	ref := terminal_session_ref(state.terminal)
	if u32(ref.id) != visual.terminal.session_id ||
	   u32(ref.generation) != visual.terminal.session_generation {
		return {}, false, App_Failure{stage = .Terminal_Workflow}
	}
	entry := terminal_workflow_entry_record(commands.terminal_workflow, ref)
	if entry == nil || entry.entry != layout_target.entry {
		return {}, false, App_Failure{stage = .Terminal_Workflow}
	}
	return Pointer_Terminal_Target{ref = ref, entry = entry}, true, {}
}

@(private)
command_context_pointer_terminal_press :: proc(
	commands: ^Command_Context,
	target: Pointer_Terminal_Target,
	hit: ui.Hit_Result,
	event: interaction.Pointer_Event,
) -> (Interaction_Result, App_Failure) {
	request, requested := pointer_terminal_mouse_request(
		target.entry,
		event,
		i64(hit.local_row),
		i64(hit.local_column),
	)
	if !requested do return {}, App_Failure{stage = .Terminal_Workflow}
	hyperlink: [terminal_session.MAX_HYPERLINK_BYTES]u8
	observation, routed, route_failure := terminal_session.registry_route_mouse(
		&commands.terminal_workflow.registry,
		target.ref,
		request,
		hyperlink[:],
	)
	if !routed do return {}, pointer_terminal_failure(route_failure)
	switch observation.route {
	case .Local:
		if event.action != .Press || event.button != .Primary do return {}, {}
		state := target.entry.copy_mode
		if !state.active {
			entered, enter_ok, enter_failure := terminal_session.registry_copy_mode_enter(
				&commands.terminal_workflow.registry,
				target.ref,
			)
			if !enter_ok do return {}, pointer_terminal_failure(enter_failure)
			state = entered.state
		}
		selected, selected_ok, select_failure := terminal_session.registry_copy_mode_select_pointer(
			&commands.terminal_workflow.registry,
			target.ref,
			state,
			{
				action = .Begin,
				viewport_row = i64(hit.local_row),
				column = i64(hit.local_column),
			},
		)
		if !selected_ok do return {}, pointer_terminal_failure(select_failure)
		target.entry.copy_mode = selected.state
		command_context_scroll_terminal_copy(commands, target.ref, selected.state)
		pointer_terminal_capture_begin(
			commands.terminal_workflow,
			target.ref,
			.Local,
			event,
			i32(event.row) - hit.local_row,
			i32(event.column) - hit.local_column,
		)
		return Interaction_Result{changed = true}, {}
	case .Child:
		if event.action == .Press {
			pointer_terminal_capture_begin(
				commands.terminal_workflow,
				target.ref,
				.Child,
				event,
				i32(event.row) - hit.local_row,
				i32(event.column) - hit.local_column,
			)
		}
		return {}, {}
	case .Hyperlink:
		return {}, {}
	case .Invalid:
		return {}, App_Failure{stage = .Terminal_Workflow}
	}
	return {}, App_Failure{stage = .Terminal_Workflow}
}

@(private)
command_context_pointer_terminal_capture_event :: proc(
	commands: ^Command_Context,
	event: interaction.Pointer_Event,
	coalesced_motion: u16,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.terminal_workflow == nil do return {}, App_Failure{stage = .Input}
	capture := &commands.terminal_workflow.pointer_capture
	if !pointer_terminal_capture_matches_source(capture, event) do return {}, {}
	if !pointer_terminal_capture_event_follows(capture, event, coalesced_motion) {
		pointer_terminal_capture_clear(commands.terminal_workflow)
		return {}, App_Failure{stage = .Input}
	}
	if pointer_capture_limit_reached(
		capture.started_at,
		capture.event_count,
		coalesced_motion,
		time.tick_now(),
	) {
		pointer_terminal_capture_clear(commands.terminal_workflow)
		command_context_set_diagnostic(commands, "Pointer capture limit reached")
		return {}, {}
	}
	if u64(event.root_generation) != u64(commands.ui_root.generation) {
		pointer_terminal_capture_clear(commands.terminal_workflow)
		return {}, App_Failure {
			stage = .UI,
			ui = {operation = .Hit_Test, code = .Stale_Root, root = commands.ui_root},
		}
	}
	entry := terminal_workflow_entry_record(commands.terminal_workflow, capture.terminal)
	if entry == nil {
		pointer_terminal_capture_clear(commands.terminal_workflow)
		return {}, App_Failure{stage = .Terminal_Workflow}
	}
	local_row := i64(event.row) - i64(capture.content_row)
	local_column := i64(event.column) - i64(capture.content_column)
	result: Interaction_Result
	if capture.route == .Local {
		selected, selected_ok, select_failure := terminal_session.registry_copy_mode_select_pointer(
			&commands.terminal_workflow.registry,
			capture.terminal,
			entry.copy_mode,
			{action = .Extend, viewport_row = local_row, column = local_column},
		)
		if !selected_ok {
			pointer_terminal_capture_clear(commands.terminal_workflow)
			return {}, pointer_terminal_failure(select_failure)
		}
		entry.copy_mode = selected.state
		command_context_scroll_terminal_copy(commands, capture.terminal, selected.state)
		result.changed = selected.changed
	} else if capture.route == .Child {
		request, requested := pointer_terminal_mouse_request(entry, event, local_row, local_column)
		if !requested {
			pointer_terminal_capture_clear(commands.terminal_workflow)
			return {}, App_Failure{stage = .Terminal_Workflow}
		}
		observation, routed, route_failure := terminal_session.registry_route_mouse(
			&commands.terminal_workflow.registry,
			capture.terminal,
			request,
			nil,
		)
		if !routed {
			pointer_terminal_capture_clear(commands.terminal_workflow)
			return {}, pointer_terminal_failure(route_failure)
		}
		if observation.route != .Child {
			pointer_terminal_capture_clear(commands.terminal_workflow)
			return {}, {}
		}
	} else {
		pointer_terminal_capture_clear(commands.terminal_workflow)
		return {}, App_Failure{stage = .Terminal_Workflow}
	}
	capture.last_sequence = event.sequence
	capture.event_count += 1 + u32(coalesced_motion)
	if event.action == .Release do pointer_terminal_capture_clear(commands.terminal_workflow)
	return result, {}
}

@(private)
pointer_terminal_mouse_request :: proc(
	entry: ^Terminal_Workflow_Entry,
	event: interaction.Pointer_Event,
	local_row, local_column: i64,
) -> (terminal_session.Mouse_Request, bool) {
	if entry == nil || entry.columns == 0 || entry.rows == 0 ||
	   entry.cell_width_pixels == 0 || entry.cell_height_pixels == 0 {
		return {}, false
	}
	if local_row < 0 || local_column < 0 || local_row >= i64(entry.rows) ||
	   local_column >= i64(entry.columns) {
		return {}, false
	}
	action := terminal_session.Mouse_Action.Invalid
	switch event.action {
	case .Press, .Wheel: action = .Press
	case .Release:       action = .Release
	case .Motion:        action = .Motion
	case .Invalid, .Cancel:
	}
	button := terminal_session.Mouse_Button.None
	switch event.button {
	case .Primary:    button = .Left
	case .Middle:     button = .Middle
	case .Secondary:  button = .Right
	case .Wheel_Up:   button = .Wheel_Up
	case .Wheel_Down: button = .Wheel_Down
	case .None:
	}
	if action == .Invalid || button == .None do return {}, false
	row := u64(local_row)
	column := u64(local_column)
	x := column * u64(entry.cell_width_pixels) + u64(entry.cell_width_pixels / 2)
	y := row * u64(entry.cell_height_pixels) + u64(entry.cell_height_pixels / 2)
	if x > u64(max(u32)) || y > u64(max(u32)) do return {}, false
	modifiers: terminal_session.Input_Modifiers
	if .Shift in event.modifiers do modifiers += {.Shift}
	if .Control in event.modifiers do modifiers += {.Control}
	if .Alt in event.modifiers do modifiers += {.Alt}
	if .Super in event.modifiers do modifiers += {.Super}
	return terminal_session.Mouse_Request {
		action = action,
		button = button,
		modifiers = modifiers,
		x = f32(x),
		y = f32(y),
	}, true
}

@(private)
pointer_terminal_capture_begin :: proc(
	workflow: ^Terminal_Workflow_State,
	ref: terminal_session.Session_Ref,
	route: terminal_session.Mouse_Route,
	event: interaction.Pointer_Event,
	content_row, content_column: i32,
) {
	if workflow == nil do return
	workflow.pointer_capture = Terminal_Pointer_Capture {
		active = true,
		route = route,
		frontend = event.frontend,
		source = event.source,
		button = event.button,
		root_generation = event.root_generation,
		geometry_generation = event.geometry_generation,
		last_sequence = event.sequence,
		started_at = time.tick_now(),
		event_count = 1,
		terminal = ref,
		content_row = content_row,
		content_column = content_column,
	}
}

@(private)
pointer_terminal_capture_matches_source :: proc(
	capture: ^Terminal_Pointer_Capture,
	event: interaction.Pointer_Event,
) -> bool {
	return capture != nil && capture.active && capture.frontend == event.frontend &&
	       capture.source == event.source
}

@(private)
pointer_terminal_capture_event_follows :: proc(
	capture: ^Terminal_Pointer_Capture,
	event: interaction.Pointer_Event,
	coalesced_motion: u16,
) -> bool {
	if !pointer_terminal_capture_matches_source(capture, event) ||
	   capture.button != event.button ||
	   capture.root_generation != event.root_generation ||
	   capture.geometry_generation != event.geometry_generation ||
	   capture.last_sequence == interaction.Pointer_Sequence(max(u64)) ||
	   u64(capture.last_sequence) > max(u64) - 1 - u64(coalesced_motion) {
		return false
	}
	return u64(event.sequence) == u64(capture.last_sequence) + 1 + u64(coalesced_motion)
}

@(private)
pointer_terminal_capture_clear :: proc(workflow: ^Terminal_Workflow_State) {
	if workflow != nil do workflow.pointer_capture = {}
}

@(private)
pointer_terminal_failure :: proc(failure: terminal_session.Failure_Record) -> App_Failure {
	return App_Failure {
		stage = .Terminal_Workflow,
		terminal_workflow_stage = .Input,
		terminal_session_failure = failure,
	}
}

@(private)
command_context_pointer_text_hit :: proc(
	commands: ^Command_Context,
	hit: ui.Hit_Result,
) -> (
	text_hit: display.Text_Hit,
	snapshot: display.Snapshot,
	registry: ^editor_view.Registry,
	view_handle: editor_view.View_Handle,
	mapped: bool,
	failure: App_Failure,
) {
	visual, visual_ok, visual_failure := ui.registry_inspect_view(&commands.ui_registry, hit.view)
	if !visual_ok do return {}, {}, nil, {}, false, App_Failure{stage = .UI, ui = visual_failure}
	if visual.kind != .Text_View || !visual.text.present do return {}, {}, nil, {}, false, {}
	text := visual.text
	target, target_ok, target_failure := pointer_text_layout_target(commands, hit)
	if target_failure.stage != .None do return {}, {}, nil, {}, false, target_failure
	if !target_ok do return {}, {}, nil, {}, false, {}
	access, access_ok, access_failure := editor_session.session_entry_access(
		commands.session_owner,
		target.entry,
	)
	if !access_ok {
		return {}, {}, nil, {}, false, App_Failure {
			stage = .Session_Access,
			editor_session = access_failure,
		}
	}
	entry, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
	if !borrowed {
		return {}, {}, nil, {}, false, App_Failure {
			stage = .Session_Access,
			editor_session = borrow_failure,
		}
	}
	logical, logical_ok, logical_failure := editor_view.snapshot(entry.view_registry, target.view)
	if !logical_ok {
		return {}, {}, nil, {}, false, App_Failure{stage = .View_Snapshot, view = logical_failure}
	}
	if !pointer_text_view_matches(text, logical, target.view) {
		return {}, {}, nil, {}, false, App_Failure{stage = .View_Snapshot}
	}
	left_cells: u32
	text_cells := u32(hit.geometry.width)
	if text.gutter.present {
		left_cells = u32(text.gutter.left_cells)
		text_cells = text.gutter.text_cells
	}
	if hit.local_row < 0 || hit.local_column < i32(left_cells) ||
	   hit.local_column >= i32(left_cells + text_cells) {
		return {}, {}, nil, {}, false, {}
	}
	persistent_allocator := commands.persistent_allocator
	if persistent_allocator.procedure == nil do persistent_allocator = context.allocator
	temporary_allocator := commands.temporary_allocator
	if temporary_allocator.procedure == nil do temporary_allocator = context.temp_allocator
	projection, projected, projection_failure := display.project_view(
		entry.buffer,
		entry.view_registry,
		target.view,
		display.Projection_Request {
			snapshot_id = display.Snapshot_ID(commands.ui_root.generation),
			view = logical,
			constraints = {
				width_cells = text_cells,
				height_rows = u32(hit.geometry.height),
			},
			profile = display.terminal_unicode17_profile(),
			limits = display.DEFAULT_RESOURCE_LIMITS,
			allocators = {
				persistent = persistent_allocator,
				temporary = temporary_allocator,
			},
		},
	)
	if !projected {
		return {}, {}, nil, {}, false, App_Failure{stage = .Projection, display = projection_failure}
	}
	resolved, resolved_ok, resolve_failure := display.snapshot_display_to_text_hit(
		projection,
		display.Display_Position {
			viewport_row = display.Display_Row_Index(hit.local_row),
			column = display.Display_Column(hit.local_column - i32(left_cells)),
		},
	)
	if !resolved_ok {
		display.snapshot_close(&projection)
		if resolve_failure.code == .Mapping_Miss do return {}, {}, nil, {}, false, {}
		return {}, {}, nil, {}, false, App_Failure{stage = .Projection, display = resolve_failure}
	}
	if !display.text_hit_is_valid(resolved) {
		display.snapshot_close(&projection)
		return {}, {}, nil, {}, false, App_Failure{stage = .Projection}
	}
	return resolved, projection, entry.view_registry, target.view, true, {}
}

@(private)
pointer_text_layout_target :: proc(
	commands: ^Command_Context,
	hit: ui.Hit_Result,
) -> (layout.Node_Descriptor, bool, App_Failure) {
	target_layout := layout.Layout_Handle {
		owner_id = layout.Owner_ID(hit.pane.layout_owner_id),
		layout_id = layout.Layout_ID(hit.pane.layout_id),
		generation = layout.Layout_Generation(hit.pane.layout_generation),
	}
	target_pane := layout.Pane_Handle {
		layout = target_layout,
		pane_id = layout.Pane_ID(hit.pane.pane_id),
		slot = hit.pane.pane_slot,
		slot_generation = hit.pane.pane_generation,
	}
	snapshot, snapshot_ok, snapshot_failure := layout.registry_snapshot(
		&commands.layout_registry,
		target_layout,
	)
	if !snapshot_ok {
		return {}, false, App_Failure{stage = .Layout, layout = snapshot_failure}
	}
	target, target_ok := pointer_layout_target(&snapshot, target_pane, hit.pane)
	return target, target_ok, {}
}

@(private)
pointer_text_view_matches :: proc(
	text: ui.Text_View_State,
	logical: editor_view.Snapshot,
	handle: editor_view.View_Handle,
) -> bool {
	return text.source.registry_id == u32(handle.registry_id) &&
	       text.source.view_id == u64(handle.view_id) &&
	       text.source.view_generation == handle.generation &&
	       text.source.state_generation == logical.state_generation &&
	       text.source.selection_generation == logical.selection_generation &&
	       text.buffer_id == u64(logical.buffer_id) && text.revision == u64(logical.revision) &&
	       text.viewport_origin == u64(logical.viewport_origin_position.byte_offset) &&
	       text.horizontal_display_column == logical.horizontal_display_column &&
	       text.tab_width == logical.tab_width &&
	       text.display_profile_id == u64(logical.display_profile_id)
}

@(private)
pointer_text_capture_begin :: proc(
	commands: ^Command_Context,
	event: interaction.Pointer_Event,
	registry: ^editor_view.Registry,
	view_handle: editor_view.View_Handle,
	hit: display.Text_Hit,
	snapshot: ^display.Snapshot,
	logical: editor_view.Snapshot,
) {
	assert(commands != nil && snapshot != nil && snapshot.state != nil)
	pointer_text_capture_clear(commands)
	commands.pointer_text_capture = Pointer_Text_Capture {
		active = true,
		frontend = event.frontend,
		source = event.source,
		button = event.button,
		root_generation = event.root_generation,
		geometry_generation = event.geometry_generation,
		last_sequence = event.sequence,
		started_at = time.tick_now(),
		event_count = 1,
		registry = registry,
		view = view_handle,
		snapshot = snapshot^,
		origin_position = hit.position,
		content_row = i32(event.row) - i32(hit.display.viewport_row),
		content_column = i32(event.column) - i32(hit.display.column),
		view_state_generation = logical.state_generation,
		selection_generation = logical.selection_generation,
	}
	snapshot^ = {}
}

@(private)
command_context_pointer_text_capture_event :: proc(
	commands: ^Command_Context,
	event: interaction.Pointer_Event,
	coalesced_motion: u16,
) -> (Interaction_Result, App_Failure) {
	capture := &commands.pointer_text_capture
	if !capture.active || !pointer_text_capture_matches_source(capture, event) do return {}, {}
	if !pointer_text_capture_event_follows(capture, event, coalesced_motion) {
		pointer_text_capture_clear(commands)
		return {}, App_Failure{stage = .Input}
	}
	if pointer_capture_limit_reached(
		capture.started_at,
		capture.event_count,
		coalesced_motion,
		time.tick_now(),
	) {
		pointer_text_capture_clear(commands)
		command_context_set_diagnostic(commands, "Pointer capture limit reached")
		return {}, {}
	}
	if u64(event.root_generation) != u64(commands.ui_root.generation) {
		pointer_text_capture_clear(commands)
		return {}, App_Failure {
			stage = .UI,
			ui = {operation = .Hit_Test, code = .Stale_Root, root = commands.ui_root},
		}
	}
	if !pointer_text_capture_view_is_visible(commands, capture) {
		pointer_text_capture_clear(commands)
		return {}, App_Failure{stage = .Layout}
	}
	logical, logical_ok, logical_failure := editor_view.snapshot(capture.registry, capture.view)
	if !logical_ok {
		pointer_text_capture_clear(commands)
		return {}, App_Failure{stage = .View_Snapshot, view = logical_failure}
	}
	if logical.state_generation != capture.view_state_generation ||
	   logical.selection_generation != capture.selection_generation ||
	   logical.buffer_id != capture.origin_position.buffer_id ||
	   logical.revision != capture.origin_position.revision {
		pointer_text_capture_clear(commands)
		return {}, App_Failure{stage = .View_Snapshot}
	}
	result, update_failure := pointer_text_capture_update(capture, event, logical)
	if update_failure.stage != .None {
		pointer_text_capture_clear(commands)
		return {}, update_failure
	}
	capture.last_sequence = event.sequence
	capture.event_count += 1 + u32(coalesced_motion)
	if event.action == .Release do pointer_text_capture_clear(commands)
	return result, {}
}

@(private)
pointer_text_capture_update :: proc(
	capture: ^Pointer_Text_Capture,
	event: interaction.Pointer_Event,
	logical: editor_view.Snapshot,
) -> (Interaction_Result, App_Failure) {
	local_row := i32(event.row) - capture.content_row
	local_column := i32(event.column) - capture.content_column
	hit: display.Text_Hit
	mapped := false
	mapping_failure: display.Failure_Context
	if local_row >= 0 && local_column >= 0 {
		hit, mapped, mapping_failure = display.snapshot_display_to_text_hit(
			capture.snapshot,
			display.Display_Position {
				viewport_row = display.Display_Row_Index(local_row),
				column = display.Display_Column(local_column),
			},
		)
		if !mapped && mapping_failure.code != .Mapping_Miss {
			return {}, App_Failure{stage = .Projection, display = mapping_failure}
		}
	}
	if !mapped {
		hit, mapped, mapping_failure = display.snapshot_clamp_display_to_text_hit(
			capture.snapshot,
			i64(local_row),
			i64(local_column),
		)
		if !mapped {
			if mapping_failure.code == .Mapping_Miss do return {}, {}
			return {}, App_Failure{stage = .Projection, display = mapping_failure}
		}
	}
	if hit.position.byte_offset == capture.origin_position.byte_offset {
		if !capture.dragged do return {}, {}
		moved, move_failure := editor_view.move_point(
			capture.registry,
			capture.view,
			hit.position,
			pointer_text_hit_desired_column(hit, logical),
			.Deactivate,
		)
		if !moved do return {}, App_Failure{stage = .View_Snapshot, view = move_failure}
		capture.dragged = false
	} else {
		desired_column := pointer_text_hit_desired_column(hit, logical)
		if capture.dragged && logical.region_active && logical.mark.present &&
		   logical.mark.position.byte_offset == capture.origin_position.byte_offset &&
		   logical.point_position.byte_offset == hit.position.byte_offset &&
		   logical.desired_display_column == desired_column {
			return {}, {}
		}
		selected, selection_failure := editor_view.select_range(
			capture.registry,
			capture.view,
			capture.origin_position,
			hit.position,
			desired_column,
		)
		if !selected {
			return {}, App_Failure{stage = .View_Snapshot, view = selection_failure}
		}
		capture.dragged = true
	}
	confirmed, confirmed_ok, confirmed_failure := editor_view.snapshot(
		capture.registry,
		capture.view,
	)
	if !confirmed_ok {
		return {}, App_Failure{stage = .View_Snapshot, view = confirmed_failure}
	}
	capture.view_state_generation = confirmed.state_generation
	capture.selection_generation = confirmed.selection_generation
	return Interaction_Result{changed = true}, {}
}

@(private)
pointer_text_hit_desired_column :: proc(
	hit: display.Text_Hit,
	logical: editor_view.Snapshot,
) -> u32 {
	column := u32(hit.span_start)
	if hit.affinity == .Trailing do column = u32(hit.span_end)
	return logical.horizontal_display_column + column
}

@(private)
pointer_text_capture_matches_source :: proc(
	capture: ^Pointer_Text_Capture,
	event: interaction.Pointer_Event,
) -> bool {
	return capture != nil && capture.active && capture.frontend == event.frontend &&
	       capture.source == event.source
}

@(private)
pointer_text_capture_event_follows :: proc(
	capture: ^Pointer_Text_Capture,
	event: interaction.Pointer_Event,
	coalesced_motion: u16,
) -> bool {
	if !pointer_text_capture_matches_source(capture, event) ||
	   capture.button != event.button ||
	   capture.root_generation != event.root_generation ||
	   capture.geometry_generation != event.geometry_generation ||
	   capture.last_sequence == interaction.Pointer_Sequence(max(u64)) ||
	   u64(capture.last_sequence) > max(u64) - 1 - u64(coalesced_motion) {
		return false
	}
	return u64(event.sequence) == u64(capture.last_sequence) + 1 + u64(coalesced_motion)
}

@(private)
pointer_capture_limit_reached :: proc(
	started_at: time.Tick,
	event_count: u32,
	coalesced_motion: u16,
	now: time.Tick,
) -> bool {
	event_work := u64(event_count) + 1 + u64(coalesced_motion)
	if event_work > u64(MAX_POINTER_CAPTURE_EVENTS) do return true
	elapsed := time.duration_nanoseconds(time.tick_diff(started_at, now))
	return elapsed < 0 || elapsed >= MAX_POINTER_CAPTURE_DURATION_NS
}

@(private)
pointer_text_capture_clear :: proc(commands: ^Command_Context) {
	if commands == nil do return
	pointer_terminal_capture_clear(commands.terminal_workflow)
	capture := &commands.pointer_text_capture
	if capture.snapshot.state != nil do display.snapshot_close(&capture.snapshot)
	capture^ = {}
}

@(private)
pointer_text_capture_view_is_visible :: proc(
	commands: ^Command_Context,
	capture: ^Pointer_Text_Capture,
) -> bool {
	if commands == nil || capture == nil || !capture.active do return false
	handle, handle_ok, _ := layout.registry_handle(&commands.layout_registry)
	if !handle_ok do return false
	snapshot, snapshot_ok, _ := layout.registry_snapshot(&commands.layout_registry, handle)
	if !snapshot_ok do return false
	for node in snapshot.nodes[:snapshot.node_count] {
		if node.kind == .Pane && node.view == capture.view do return true
	}
	return false
}

@(private)
pointer_capture_reconcile_root :: proc(
	commands: ^Command_Context,
	previous, current: ui.Root_Handle,
) {
	if commands == nil do return
	if previous.registry_id == ui.Registry_ID(0) || current.registry_id != previous.registry_id ||
	   current.generation == ui.Root_Generation(0) {
		pointer_text_capture_clear(commands)
		return
	}
	text_capture := &commands.pointer_text_capture
	if text_capture.active {
		if text_capture.root_generation != interaction.Pointer_Root_Generation(previous.generation) {
			pointer_text_capture_clear(commands)
			return
		}
		text_capture.root_generation = interaction.Pointer_Root_Generation(current.generation)
	}
	if commands.terminal_workflow == nil do return
	terminal_capture := &commands.terminal_workflow.pointer_capture
	if !terminal_capture.active do return
	if terminal_capture.root_generation != interaction.Pointer_Root_Generation(previous.generation) {
		pointer_terminal_capture_clear(commands.terminal_workflow)
		return
	}
	terminal_capture.root_generation = interaction.Pointer_Root_Generation(current.generation)
}

@(private)
command_context_pointer_focus_pane :: proc(
	commands: ^Command_Context,
	session_owner: ^editor_session.Session,
	session_handle: editor_session.Session_Handle,
	hit: ui.Hit_Result,
) -> (Interaction_Result, App_Failure) {
	if !command_context_layout_is_live(commands) {
		return {}, App_Failure{stage = .Layout}
	}
	target_layout := layout.Layout_Handle {
		owner_id = layout.Owner_ID(hit.pane.layout_owner_id),
		layout_id = layout.Layout_ID(hit.pane.layout_id),
		generation = layout.Layout_Generation(hit.pane.layout_generation),
	}
	target_pane := layout.Pane_Handle {
		layout = target_layout,
		pane_id = layout.Pane_ID(hit.pane.pane_id),
		slot = hit.pane.pane_slot,
		slot_generation = hit.pane.pane_generation,
	}
	before, snapshot_ok, snapshot_failure := layout.registry_snapshot(
		&commands.layout_registry,
		target_layout,
	)
	if !snapshot_ok do return {}, App_Failure{stage = .Layout, layout = snapshot_failure}
	target, target_ok := pointer_layout_target(&before, target_pane, hit.pane)
	if !target_ok do return {}, App_Failure{stage = .Layout}
	_, visible_ok, visible_failure := editor_session.session_visible_target(
		session_owner,
		session_handle,
	)
	if !visible_ok {
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	access, access_ok, access_failure := editor_session.session_entry_access(
		session_owner,
		target.entry,
	)
	if !access_ok {
		return {}, App_Failure{stage = .Session_Access, editor_session = access_failure}
	}
	entry, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
	if !borrowed {
		return {}, App_Failure{stage = .Session_Access, editor_session = borrow_failure}
	}
	activation_ok, activation_failure := editor_session.session_activation_validate(
		session_owner,
		target.entry,
	)
	if !activation_ok {
		return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
	}
	focus, focused, focus_failure := layout.registry_focus(
		&commands.layout_registry,
		target_pane,
	)
	if !focused do return {}, App_Failure{stage = .Layout, layout = focus_failure}
	activation, activated, activate_failure := editor_session.session_activate(
		session_owner,
		target.entry,
	)
	if !activated {
		rollback := before.active_pane
		rollback.layout = focus.layout
		_, rolled_back, rollback_failure := layout.registry_focus(
			&commands.layout_registry,
			rollback,
		)
		if !rolled_back {
			return {}, App_Failure{stage = .Layout, layout = rollback_failure}
		}
		return {}, App_Failure{stage = .Session_Access, editor_session = activate_failure}
	}
	command_context_bind_entry(commands, target.entry, entry)
	commands.layout_entry = target.entry
	return Interaction_Result {
		changed = focus.layout != before.handle || activation.changed,
	}, {}
}

@(private)
pointer_layout_target :: proc(
	snapshot: ^layout.Snapshot,
	pane: layout.Pane_Handle,
	state: ui.Pane_Surface_State,
) -> (layout.Node_Descriptor, bool) {
	for node in snapshot.nodes[:snapshot.node_count] {
		if node.kind != .Pane || node.pane != pane do continue
		if u64(node.entry.entry_id) != state.entry_id ||
		   node.entry.generation != state.entry_generation ||
		   u64(node.buffer_id) != state.buffer_id {
			return {}, false
		}
		return node, true
	}
	return {}, false
}
