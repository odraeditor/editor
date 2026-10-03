// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package darek

import "../filesystem"
import "base:runtime"

@(private)
Instance_State :: struct {
	id:                  Instance_ID,
	generation:          Instance_Generation,
	node_generation:     Node_Generation,
	task_generation:     Task_Generation,
	selection_generation: Selection_Generation,
	root:                Root_Descriptor,
	root_path:           filesystem.Normalized_Path,
	workspace_id:        []u8,
	nodes:               []Node_Descriptor,
	selected:            Node_ID,
	has_selection:       bool,
	first_visible:       u32,
	viewport_nodes:      u32,
	visible:             bool,
	panel_side:          Panel_Side,
	panel_width:         u32,
	panel_normal_width:  u32,
	panel_extra_width:   bool,
	panel_width_locked:  bool,
	directory_compression: bool,
	current_project_only: bool,
	show_hidden:         bool,
	show_ignored:        bool,
	show_version_control: bool,
	show_diagnostics:    bool,
	sort_mode:           Sort_Mode,
	filter:              [MAX_FILTER_BYTES]u8,
	filter_length:       int,
	preview_enabled:     bool,
	preview_target:      Node_ID,
	preview_task:        Task_Generation,
	follow_enabled:      bool,
	follow_observed:     u64,
	follow_task:         Task_Generation,
	watch_enabled:       bool,
	watch_status:        Watch_Status,
	watch_generation:    u64,
	watch_pending_hints: u32,
	watch_provider_generation: Provider_Generation,
	annotation_generation: Provider_Generation,
	symbol_generation:   Provider_Generation,
	policy:              Policy,
	allocator:           runtime.Allocator,
	retained_text:       []u8,
	next_node_id:        Node_ID,
}

/* instance_open creates one empty visible Darek lifecycle over a checked root. */
instance_open :: proc(
	instance: ^Instance,
	config: Config,
	root: Root_Request,
) -> (ok: bool, failure: Failure_Context) {
	if instance == nil || instance.state != nil || instance.closed {
		return false, Failure_Context{operation = .Open, code = .Invalid_Instance}
	}
	if config.id == Instance_ID(0) || config.generation == Instance_Generation(0) ||
	   !policy_is_valid(config.policy) || config.allocator.procedure == nil {
		return false, Failure_Context{operation = .Open, code = .Invalid_Config}
	}
	root_descriptor, normalized, root_ok := root_validate(root, config.allocator)
	if !root_ok {
		return false, Failure_Context {
			operation = .Open,
			code = .Invalid_Root,
			instance_id = config.id,
			instance_generation = config.generation,
		}
	}
	state, allocation_error := new(Instance_State, config.allocator)
	if allocation_error != nil {
		return false, Failure_Context{operation = .Open, code = .Allocation}
	}
	state^ = Instance_State {
		id = config.id,
		generation = config.generation,
		task_generation = Task_Generation(1),
		selection_generation = Selection_Generation(1),
		root = root_descriptor,
		root_path = normalized,
		viewport_nodes = 1,
		visible = true,
		panel_side = .Left,
		panel_width = DEFAULT_PANEL_WIDTH,
		panel_normal_width = DEFAULT_PANEL_WIDTH,
		sort_mode = .Name_Ascending,
		show_version_control = true,
		show_diagnostics = true,
		watch_status = .Disabled,
		next_node_id = Node_ID(1),
		policy = config.policy,
		allocator = config.allocator,
	}
	state.root.path = filesystem.normalized_path_text(&state.root_path)
	if state.root.mode == .Workspace {
		state.workspace_id, allocation_error = make([]u8, len(root.workspace.id), config.allocator)
		if allocation_error != nil {
			free(state, config.allocator)
			return false, Failure_Context{operation = .Open, code = .Allocation}
		}
		copy(state.workspace_id, transmute([]u8)root.workspace.id)
		state.root.workspace.id = string(state.workspace_id)
	}
	instance.state = state
	return true, {}
}

/* instance_inspect borrows one complete current Darek state. */
instance_inspect :: proc(
	instance: ^Instance,
) -> (view: Instance_View, usage: Usage, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil {
		return {}, {}, false, instance_failure(instance, .Inspect, .Invalid_Instance)
	}
	return Instance_View {
		id = state.id,
		generation = state.generation,
		node_generation = state.node_generation,
		task_generation = state.task_generation,
		root = state.root,
		nodes = state.nodes,
		selected = state.selected,
		has_selection = state.has_selection,
		first_visible = state.first_visible,
		viewport_nodes = state.viewport_nodes,
		visible = state.visible,
		panel_side = state.panel_side,
		selection_generation = state.selection_generation,
		preview = {
			enabled = state.preview_enabled,
			selection_generation = state.selection_generation,
			task_generation = state.preview_task,
			target = state.preview_target,
		},
		follow = {
			enabled = state.follow_enabled,
			observed_generation = state.follow_observed,
			task_generation = state.follow_task,
		},
		watch = {
			enabled = state.watch_enabled,
			status = state.watch_status,
			generation = state.watch_generation,
			pending_hints = state.watch_pending_hints,
			provider_generation = state.watch_provider_generation,
		},
		annotation_generation = state.annotation_generation,
		symbol_generation = state.symbol_generation,
		panel = {
			side = state.panel_side,
			width = state.panel_width,
			extra_width = state.panel_extra_width,
			width_locked = state.panel_width_locked,
			directory_compression = state.directory_compression,
			current_project_only = state.current_project_only,
			show_hidden = state.show_hidden,
			show_ignored = state.show_ignored,
			show_version_control = state.show_version_control,
			show_diagnostics = state.show_diagnostics,
			sort_mode = state.sort_mode,
			filter = string(state.filter[:state.filter_length]),
		},
	}, Usage {
		nodes = u32(len(state.nodes)),
		retained_bytes = u64(len(state.retained_text)),
		allocation_bytes = u64(size_of(Instance_State)) +
			u64(len(state.nodes) * size_of(Node_Descriptor)) + u64(len(state.retained_text)),
	}, true, {}
}

/* instance_set_visible retains admitted state while changing panel visibility. */
instance_set_visible :: proc(
	instance: ^Instance,
	visible: bool,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil {
		return false, false, instance_failure(instance, .Visibility, .Invalid_Instance)
	}
	if state.visible == visible do return false, true, {}
	state.visible = visible
	return true, true, {}
}

/* instance_close releases every instance-owned observation exactly once. */
instance_close :: proc(instance: ^Instance) -> (ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil {
		return false, instance_failure(instance, .Close, .Invalid_Instance)
	}
	allocator := state.allocator
	if state.workspace_id != nil do delete(state.workspace_id, allocator)
	if state.retained_text != nil do delete(state.retained_text, allocator)
	if state.nodes != nil do delete(state.nodes, allocator)
	free(state, allocator)
	instance^ = Instance{closed = true}
	return true, {}
}

@(private)
instance_state :: proc(instance: ^Instance) -> ^Instance_State {
	if instance == nil || instance.state == nil || instance.closed do return nil
	return cast(^Instance_State)instance.state
}

@(private)
instance_failure :: proc(
	instance: ^Instance,
	operation: Operation,
	code: Failure_Code,
) -> Failure_Context {
	failure := Failure_Context{operation = operation, code = code}
	state := instance_state(instance)
	if state != nil {
		failure.instance_id = state.id
		failure.instance_generation = state.generation
		failure.node_generation = state.node_generation
	}
	return failure
}

@(private)
root_validate :: proc(
	request: Root_Request,
	allocator: runtime.Allocator,
) -> (descriptor: Root_Descriptor, normalized: filesystem.Normalized_Path, ok: bool) {
	switch request.mode {
	case .Directory:
		if !filesystem.resource_id_valid(request.resource) do return {}, {}, false
		normalized_ok, _ := filesystem.path_normalize(request.path, &normalized, allocator)
		if !normalized_ok do return {}, {}, false
		descriptor = Root_Descriptor{mode = .Directory, resource = request.resource}
		return descriptor, normalized, true
	case .Project:
		if request.project.id == 0 || request.project.generation == 0 do return {}, {}, false
		return Root_Descriptor{mode = .Project, project = request.project}, {}, true
	case .Workspace:
		if len(request.workspace.id) == 0 || request.workspace.generation == 0 ||
		   request.workspace.root_generation == 0 {
			return {}, {}, false
		}
		return Root_Descriptor{mode = .Workspace, workspace = request.workspace}, {}, true
	case .Invalid:
		return {}, {}, false
	}
	return {}, {}, false
}
