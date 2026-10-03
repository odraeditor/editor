// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package darek

import "../filesystem"
import "../project"
import "../ui"
import "base:runtime"
import "core:path/filepath"
import "core:slice"
import "core:strings"

LOCAL_PROVIDER :: Provider_ID(1)

@(private)
Node_Source :: struct {
	id:                  Node_ID,
	parent:              Node_ID,
	provider_id:         Provider_ID,
	provider_generation: Provider_Generation,
	kind:                Node_Kind,
	project:             project.Project_Handle,
	resource:            filesystem.Resource_ID,
	label:               string,
	path:                string,
	depth:               u16,
	children:            Child_State,
	actions:             Action_Roles,
	hidden:              bool,
	ignored:             bool,
	version_control:     Version_Control_State,
	diagnostic:          Diagnostic_State,
	symbol_id:           u64,
	source_revision:     u64,
	start:               u64,
	end:                 u64,
}

/* instance_publish_project_roots publishes one checked Project or Workspace root set. */
instance_publish_project_roots :: proc(
	instance: ^Instance,
	roots: []Project_Root_Source,
) -> (ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil {
		return false, instance_failure(instance, .Publish, .Invalid_Instance)
	}
	if (state.root.mode != .Project && state.root.mode != .Workspace) || len(roots) == 0 ||
	   (state.root.mode == .Project && len(roots) != 1) || len(roots) > int(state.policy.nodes) {
		return false, instance_failure(instance, .Publish, .Invalid_Root)
	}
	count := 0
	for root, index in roots {
		if !project.project_handle_is_valid(root.project) || len(root.label) == 0 ||
		   len(root.path) == 0 || root.provider_generation == Provider_Generation(0) ||
		   (root.available && !filesystem.resource_id_valid(root.resource)) {
			return false, instance_failure(instance, .Publish, .Invalid_Root)
		}
		for previous in roots[:index] {
			if previous.project == root.project {
				return false, instance_failure(instance, .Publish, .Duplicate_Node)
			}
		}
		count += 1
		existing := instance_find_project_root(state, root.project)
		if existing >= 0 && root.available && state.nodes[existing].resource == root.resource &&
		   state.nodes[existing].children == .Expanded {
			end := instance_subtree_end(state, existing)
			count += end - existing - 1
		}
	}
	if count > int(state.policy.nodes) {
		failure = state_failure(state, .Publish, .Node_Limit)
		failure.limit = u64(state.policy.nodes)
		failure.actual = u64(count)
		return false, failure
	}
	sources, allocation_error := make([]Node_Source, count, state.allocator)
	if allocation_error != nil do return false, state_failure(state, .Publish, .Allocation)
	defer delete(sources, state.allocator)
	next_id := state.next_node_id
	write := 0
	for root in roots {
		existing := instance_find_project_root(state, root.project)
		id := Node_ID(0)
		children := Child_State.Unavailable
		if root.available do children = .Collapsed
		if existing >= 0 {
			id = state.nodes[existing].handle.id
			if root.available && state.nodes[existing].resource == root.resource {
				children = state.nodes[existing].children
			}
		}
		if id == Node_ID(0) {
			if next_id == Node_ID(max(u64)) {
				return false, state_failure(state, .Publish, .Invalid_Generation)
			}
			id = next_id
			next_id = Node_ID(u64(next_id) + 1)
		}
		sources[write] = Node_Source {
			id = id,
			provider_id = LOCAL_PROVIDER,
			provider_generation = root.provider_generation,
			kind = .Project,
			project = root.project,
			resource = root.resource,
			label = root.label,
			path = root.path,
			children = children,
			actions = {.Structure, .Visit, .Collapse} if root.available else {},
		}
		write += 1
		if existing >= 0 && children == .Expanded {
			end := instance_subtree_end(state, existing)
			for node in state.nodes[existing + 1:end] {
				sources[write] = node_source(node)
				write += 1
			}
		}
	}
	selected := state.selected
	selected_present := false
	for source in sources {
		if source.id == selected {
			selected_present = true
			break
		}
	}
	if !selected_present do selected = sources[0].id
	published, publish_failure := instance_publish_sources(state, sources, selected, true)
	if !published do return false, publish_failure
	state.next_node_id = next_id
	return true, {}
}

/* instance_publish_local_root publishes one collapsed local directory root. */
instance_publish_local_root :: proc(
	instance: ^Instance,
) -> (ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil {
		return false, instance_failure(instance, .Publish, .Invalid_Instance)
	}
	if state.root.mode != .Directory || !filesystem.resource_id_valid(state.root.resource) ||
	   len(state.root.path) == 0 {
		return false, instance_failure(instance, .Publish, .Invalid_Root)
	}
	if state.node_generation != Node_Generation(0) {
		return false, instance_failure(instance, .Publish, .Invalid_Generation)
	}
	root_id := state.next_node_id
	sources := []Node_Source {{
		id = root_id,
		provider_id = LOCAL_PROVIDER,
		provider_generation = 1,
		kind = .Directory,
		resource = state.root.resource,
		label = filepath.base(state.root.path),
		path = state.root.path,
		children = .Collapsed,
		actions = {.Structure, .Visit, .Collapse},
	}}
	ok, failure = instance_publish_sources(state, sources, root_id, true)
	if ok do state.next_node_id = Node_ID(u64(root_id) + 1)
	return ok, failure
}

/* instance_expand_roots populates every available top-level root. */
instance_expand_roots :: proc(
	instance: ^Instance,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil {
		return false, false, instance_failure(instance, .Expand, .Invalid_Instance)
	}
	root_count := 0
	for node in state.nodes {
		if node.parent == Node_ID(0) && (node.kind == .Directory || node.kind == .Project) {
			root_count += 1
		}
	}
	if root_count == 0 {
		return false, false, instance_failure(instance, .Expand, .Node_Not_Found)
	}
	roots, allocation_error := make([]Node_ID, root_count, state.allocator)
	if allocation_error != nil do return false, false, state_failure(state, .Expand, .Allocation)
	defer delete(roots, state.allocator)
	write := 0
	for node in state.nodes {
		if node.parent == Node_ID(0) && (node.kind == .Directory || node.kind == .Project) {
			roots[write] = node.handle.id
			write += 1
		}
	}
	for root in roots {
		index := instance_find_node(state, root)
		if index < 0 {
			return changed, false, state_failure(state, .Expand, .Node_Not_Found)
		}
		if state.nodes[index].children != .Collapsed do continue
		expanded, expanded_ok, expand_failure := instance_expand_at(state, index, .Expand)
		if !expanded_ok do return changed, false, expand_failure
		changed = changed || expanded
	}
	return changed, true, {}
}

/* instance_toggle_selected expands or collapses the selected structural node. */
instance_toggle_selected :: proc(
	instance: ^Instance,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil {
		return false, false, instance_failure(instance, .Expand, .Invalid_Instance)
	}
	selected_index := instance_selected_index(state)
	if selected_index < 0 {
		return false, false, instance_failure(instance, .Expand, .Node_Not_Found)
	}
	selected := state.nodes[selected_index]
	if selected.kind != .Directory && selected.kind != .Project {
		return false, true, {}
	}
	if selected.children == .Expanded {
		return instance_collapse_at(state, selected_index)
	}
	if selected.children != .Collapsed && selected.children != .Failed &&
	   selected.children != .Unavailable {
		return false, false, instance_failure(instance, .Expand, .Invalid_Node)
	}
	return instance_expand_at(state, selected_index, .Expand)
}

/* instance_refresh_selected replaces the selected expanded directory observation. */
instance_refresh_selected :: proc(
	instance: ^Instance,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil {
		return false, false, instance_failure(instance, .Refresh, .Invalid_Instance)
	}
	selected_index := instance_selected_index(state)
	if selected_index < 0 {
		return false, false, instance_failure(instance, .Refresh, .Node_Not_Found)
	}
	if (state.nodes[selected_index].kind != .Directory && state.nodes[selected_index].kind != .Project) ||
	   state.nodes[selected_index].children != .Expanded {
		return false, true, {}
	}
	return instance_replace_children(state, selected_index, .Refresh)
}

/* instance_refresh_containing_directory refreshes the selected node's visible parent generation. */
instance_refresh_containing_directory :: proc(
	instance: ^Instance,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil {
		return false, false, instance_failure(instance, .Refresh, .Invalid_Instance)
	}
	selected_index := instance_selected_index(state)
	if selected_index < 0 {
		return false, false, instance_failure(instance, .Refresh, .Node_Not_Found)
	}
	selected := state.nodes[selected_index]
	if selected.parent == Node_ID(0) {
		if selected.kind != .Directory && selected.kind != .Project do return false, true, {}
		return instance_replace_children(state, selected_index, .Refresh)
	}
	for node, index in state.nodes {
		if node.handle.id != selected.parent do continue
		if node.kind != .Directory && node.kind != .Project {
			return false, false, instance_failure(instance, .Refresh, .Invalid_Parent)
		}
		return instance_replace_children(state, index, .Refresh)
	}
	return false, false, instance_failure(instance, .Refresh, .Node_Not_Found)
}

/* instance_move_visible moves selection in bounded visible preorder. */
instance_move_visible :: proc(
	instance: ^Instance,
	delta: i32,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil {
		return false, false, instance_failure(instance, .Navigate, .Invalid_Instance)
	}
	current := instance_selected_index(state)
	if current < 0 {
		return false, false, instance_failure(instance, .Navigate, .Node_Not_Found)
	}
	if delta == 0 do return false, true, {}
	visible: [MAX_NODES]int
	visible_count := 0
	current_visible := -1
	for _, index in state.nodes {
		if !instance_node_visible(state, index) do continue
		visible[visible_count] = index
		if index == current do current_visible = visible_count
		visible_count += 1
	}
	if current_visible < 0 || visible_count == 0 {
		return false, false, state_failure(state, .Navigate, .Node_Not_Found)
	}
	target_visible := clamp(current_visible + int(delta), 0, visible_count - 1)
	target := visible[target_visible]
	if target == current do return false, true, {}
	if !instance_advance_selection(state) {
		return false, false, state_failure(state, .Navigate, .Invalid_Generation)
	}
	state.selected = state.nodes[target].handle.id
	instance_keep_selected_visible(state, target)
	return true, true, {}
}

/* instance_select_node selects one exact node in the current published generation. */
instance_select_node :: proc(
	instance: ^Instance,
	id: Node_ID,
) -> (selected: bool, changed: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil do return false, false, instance_failure(instance, .Navigate, .Invalid_Instance)
	if id == Node_ID(0) do return false, false, state_failure(state, .Navigate, .Invalid_Node)
	index := instance_find_node(state, id)
	if index < 0 {
		return false, false, instance_failure(instance, .Navigate, .Stale_Generation)
	}
	if !instance_node_visible(state, index) {
		return false, false, state_failure(state, .Navigate, .Invalid_Node)
	}
	changed = state.selected != id
	if changed && !instance_advance_selection(state) {
		return false, false, state_failure(state, .Navigate, .Invalid_Generation)
	}
	state.selected = id
	state.has_selection = true
	instance_keep_selected_visible(state, index)
	return true, changed, {}
}

/* instance_move_sibling moves among visible nodes with the same parent. */
instance_move_sibling :: proc(
	instance: ^Instance,
	delta: i32,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil {
		return false, false, instance_failure(instance, .Navigate, .Invalid_Instance)
	}
	current := instance_selected_index(state)
	if current < 0 {
		return false, false, instance_failure(instance, .Navigate, .Node_Not_Found)
	}
	if delta == 0 do return false, true, {}
	step := 1 if delta > 0 else -1
	remaining := int(delta) if delta > 0 else -int(delta)
	parent := state.nodes[current].parent
	for index := current + step; index >= 0 && index < len(state.nodes); index += step {
		if state.nodes[index].parent != parent || !instance_node_visible(state, index) do continue
		remaining -= 1
		if remaining == 0 {
			if !instance_advance_selection(state) {
				return false, false, state_failure(state, .Navigate, .Invalid_Generation)
			}
			state.selected = state.nodes[index].handle.id
			instance_keep_selected_visible(state, index)
			return true, true, {}
		}
	}
	return false, true, {}
}

/* instance_move_parent selects the current visible parent. */
instance_move_parent :: proc(
	instance: ^Instance,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil {
		return false, false, instance_failure(instance, .Navigate, .Invalid_Instance)
	}
	current := instance_selected_index(state)
	if current < 0 {
		return false, false, instance_failure(instance, .Navigate, .Node_Not_Found)
	}
	parent := state.nodes[current].parent
	if parent == Node_ID(0) do return false, true, {}
	parent_index := instance_find_node(state, parent)
	if parent_index < 0 {
		return false, false, instance_failure(instance, .Navigate, .Invalid_Parent)
	}
	if !instance_advance_selection(state) {
		return false, false, state_failure(state, .Navigate, .Invalid_Generation)
	}
	state.selected = parent
	instance_keep_selected_visible(state, parent_index)
	return true, true, {}
}

/* instance_move_project moves selection among ordered top-level Project roots. */
instance_move_project :: proc(
	instance: ^Instance,
	delta: i32,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil {
		return false, false, instance_failure(instance, .Navigate, .Invalid_Instance)
	}
	current := instance_selected_project_root_index(state)
	if current < 0 do return false, false, instance_failure(instance, .Navigate, .Node_Not_Found)
	if delta == 0 do return false, true, {}
	step := 1 if delta > 0 else -1
	remaining := int(delta) if delta > 0 else -int(delta)
	for index := current + step; index >= 0 && index < len(state.nodes); index += step {
		if state.nodes[index].parent != Node_ID(0) || state.nodes[index].kind != .Project ||
		   !instance_node_visible(state, index) {
			continue
		}
		remaining -= 1
		if remaining == 0 {
			if !instance_advance_selection(state) {
				return false, false, state_failure(state, .Navigate, .Invalid_Generation)
			}
			state.selected = state.nodes[index].handle.id
			instance_keep_selected_visible(state, index)
			return true, true, {}
		}
	}
	return false, true, {}
}

/* instance_reveal_path expands only target ancestry and selects the exact node. */
instance_reveal_path :: proc(
	instance: ^Instance,
	path: string,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil || len(path) == 0 {
		return false, false, instance_failure(instance, .Navigate, .Invalid_Instance)
	}
	normalized: filesystem.Normalized_Path
	if normalized_ok, _ := filesystem.path_normalize(path, &normalized, state.allocator); !normalized_ok {
		return false, false, state_failure(state, .Navigate, .Invalid_Node)
	}
	target_path := filesystem.normalized_path_text(&normalized)
	changed = false
	for _ in 0 ..< int(state.policy.depth) + 1 {
		ancestor := -1
		ancestor_bytes := -1
		for node, index in state.nodes {
			if node.path == target_path {
				if state.selected != node.handle.id {
					if !instance_advance_selection(state) {
						return changed, false, state_failure(state, .Navigate, .Invalid_Generation)
					}
					state.selected = node.handle.id
					instance_keep_selected_visible(state, index)
					changed = true
				}
				return changed, true, {}
			}
			if node.kind != .Directory && node.kind != .Project do continue
			if len(node.path) >= len(target_path) || !strings.has_prefix(target_path, node.path) do continue
			separator := len(node.path)
			if node.path[len(node.path) - 1] != '/' && target_path[separator] != '/' do continue
			if len(node.path) > ancestor_bytes {
				ancestor = index
				ancestor_bytes = len(node.path)
			}
		}
		if ancestor < 0 do return changed, false, state_failure(state, .Navigate, .Node_Not_Found)
		if state.nodes[ancestor].children == .Expanded {
			return changed, false, state_failure(state, .Navigate, .Node_Not_Found)
		}
		if state.nodes[ancestor].children != .Collapsed {
			return changed, false, state_failure(state, .Navigate, .Invalid_Node)
		}
		state.selected = state.nodes[ancestor].handle.id
		expanded, expanded_ok, expand_failure := instance_replace_children(state, ancestor, .Expand)
		if !expanded_ok do return changed, false, expand_failure
		changed = changed || expanded
	}
	return changed, false, state_failure(state, .Navigate, .Depth_Limit)
}

/* instance_collapse_projects collapses a checked subset of top-level Project roots. */
instance_collapse_projects :: proc(
	instance: ^Instance,
	scope: Project_Collapse_Scope,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil || scope == .Invalid {
		return false, false, instance_failure(instance, .Expand, .Invalid_Instance)
	}
	current := instance_selected_project_root_index(state)
	if current < 0 do return false, false, instance_failure(instance, .Expand, .Node_Not_Found)
	current_id := state.nodes[current].handle.id
	remove_count := 0
	collapse_count := 0
	for node, index in state.nodes {
		if node.parent != Node_ID(0) || node.kind != .Project || node.children != .Expanded do continue
		collapse := scope == .All ||
			(scope == .Current && node.handle.id == current_id) ||
			(scope == .Others && node.handle.id != current_id)
		if collapse {
			collapse_count += 1
			remove_count += instance_subtree_end(state, index) - index - 1
		}
	}
	if collapse_count == 0 do return false, true, {}
	sources, allocation_error := make([]Node_Source, len(state.nodes) - remove_count, state.allocator)
	if allocation_error != nil do return false, false, state_failure(state, .Expand, .Allocation)
	defer delete(sources, state.allocator)
	write := 0
	for index := 0; index < len(state.nodes); {
		node := state.nodes[index]
		collapse := node.parent == Node_ID(0) && node.kind == .Project &&
			(scope == .All || (scope == .Current && node.handle.id == current_id) ||
			 (scope == .Others && node.handle.id != current_id))
		source := node_source(node)
		if collapse do source.children = .Collapsed
		sources[write] = source
		write += 1
		if collapse {
			index = instance_subtree_end(state, index)
		} else {
			index += 1
		}
	}
	selected := state.selected
	selected_present := false
	for source in sources {
		if source.id == selected {
			selected_present = true
			break
		}
	}
	if !selected_present do selected = current_id
	published, publish_failure := instance_publish_sources(state, sources, selected, true)
	return published, published, publish_failure
}

/* instance_resize_viewport changes clipping state without changing hierarchy. */
instance_resize_viewport :: proc(
	instance: ^Instance,
	viewport_nodes: u32,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil || viewport_nodes == 0 || viewport_nodes > state.policy.nodes {
		return false, false, instance_failure(instance, .Navigate, .Invalid_Node)
	}
	if state.viewport_nodes == viewport_nodes do return false, true, {}
	state.viewport_nodes = viewport_nodes
	instance_keep_selected_visible(state, instance_selected_index(state))
	return true, true, {}
}

/* instance_selected_target borrows the selected canonical filesystem target. */
instance_selected_target :: proc(
	instance: ^Instance,
) -> (node: Node_Descriptor, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil {
		return {}, false, instance_failure(instance, .Inspect, .Invalid_Instance)
	}
	index := instance_selected_index(state)
	if index < 0 {
		return {}, false, instance_failure(instance, .Inspect, .Node_Not_Found)
	}
	return state.nodes[index], true, {}
}

/* instance_selected_project_root borrows the containing visible Project root. */
instance_selected_project_root :: proc(
	instance: ^Instance,
) -> (node: Node_Descriptor, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil {
		return {}, false, instance_failure(instance, .Inspect, .Invalid_Instance)
	}
	index := instance_selected_project_root_index(state)
	if index < 0 {
		return {}, false, instance_failure(instance, .Inspect, .Node_Not_Found)
	}
	return state.nodes[index], true, {}
}

/* tree_projection_build copies one generic UI tree generation from Darek state. */
tree_projection_build :: proc(
	projection: ^Tree_Projection,
	instance: ^Instance,
	allocator := context.allocator,
) -> (ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if projection == nil || projection.state != nil || state == nil ||
	   allocator.procedure == nil || state.node_generation == Node_Generation(0) {
		return false, instance_failure(instance, .Inspect, .Invalid_Instance)
	}
	owner, owner_error := new(Tree_Projection_State, allocator)
	if owner_error != nil {
		return false, instance_failure(instance, .Inspect, .Allocation)
	}
	owner.allocator = allocator
	project_index := instance_selected_project_root_index(state)
	project_id := Node_ID(0)
	if project_index >= 0 do project_id = state.nodes[project_index].handle.id
	visible_count := 0
	for _, index in state.nodes {
		if instance_node_visible(state, index) do visible_count += 1
	}
	owner.nodes, owner_error = make([]ui.Tree_Node_Definition, visible_count, allocator)
	if owner_error != nil {
		free(owner, allocator)
		return false, instance_failure(instance, .Inspect, .Allocation)
	}
	write := 0
	current_node := -1
	for node, index in state.nodes {
		if !instance_node_visible(state, index) do continue
		depth := node.depth
		if state.directory_compression {
			depth = instance_compressed_depth(state, index)
		}
		owner.nodes[write] = ui.Tree_Node_Definition {
			id = ui.Tree_Node_ID(node.handle.id),
			parent = ui.Tree_Node_ID(node.parent),
			text = node.label,
			icon_role = instance_node_icon_role(state, node),
			icon_style_role = instance_node_style_role(state, node),
			depth = node.depth,
			indent_depth = depth,
			expandable = node.children == .Collapsed || node.children == .Expanded,
			expanded = node.children == .Expanded,
			action = {
				owner_id = ui.Owner_ID(state.id),
				action_id = ui.List_Action_ID(node.handle.id),
				generation = u64(state.node_generation),
			},
		}
		role := instance_node_style_role(state, node)
		if role != .Invalid && index != instance_selected_index(state) {
			owner.nodes[write].style_spans[0] = {
				start_byte = 0,
				end_byte = u32(len(node.label)),
				style_role = role,
			}
			owner.nodes[write].style_span_count = 1
		}
		if node.handle.id == state.selected do current_node = write
		write += 1
	}
	owner.instance_id = state.id
	owner.node_generation = state.node_generation
	owner.current_node = i32(current_node)
	owner.first_visible = min(state.first_visible, u32(max(visible_count - 1, 0)))
	owner.viewport_nodes = state.viewport_nodes
	projection.state = owner
	return true, {}
}

@(private)
instance_node_icon_role :: proc(state: ^Instance_State, node: Node_Descriptor) -> ui.Tree_Icon_Role {
	if state.show_diagnostics && node.diagnostic == .Error ||
	   state.show_version_control && node.version_control == .Conflicted {
		return .Failure
	}
	if state.show_version_control && node.version_control != .None && node.version_control != .Clean do return .File_Version_Control
	if node.children == .Unavailable || node.children == .Failed do return .Failure
	switch node.kind {
	case .Project: return .Project
	case .Directory:
		special := node.label == "src" || node.label == "docs" || node.label == "test" ||
			node.label == "tests" || node.label == "config"
		if special do return .Directory_Special_Open if node.children == .Expanded else .Directory_Special_Closed
		return .Directory_Open if node.children == .Expanded else .Directory_Closed
	case .File:
		extension := filepath.ext(node.label)
		if extension == ".md" || extension == ".txt" || extension == ".org" do return .File_Documentation
		if extension == ".toml" || extension == ".json" || extension == ".yaml" ||
		   extension == ".yml" || node.label == "Makefile" {
			return .File_Configuration
		}
		if node.label == ".gitignore" || node.label == ".gitattributes" do return .File_Version_Control
		if extension == ".odin" || extension == ".rkt" || extension == ".go" ||
		   extension == ".rs" || extension == ".c" || extension == ".h" ||
		   extension == ".py" || extension == ".js" || extension == ".ts" ||
		   extension == ".tsx" {
			return .File_Source
		}
		return .File
	case .Symbol: return .File_Source
	case .Invalid:
		return .File
	}
	return .File
}

@(private)
instance_node_style_role :: proc(state: ^Instance_State, node: Node_Descriptor) -> ui.Style_Role {
	if state.show_diagnostics && node.diagnostic == .Error ||
	   state.show_version_control && node.version_control == .Conflicted {
		return .Tree_Failure
	}
	if state.show_diagnostics && node.diagnostic == .Warning do return .Tree_Inactive
	if state.show_version_control && node.version_control != .None && node.version_control != .Clean do return .Tree_File_Version_Control
	if node.ignored do return .Tree_Inactive
	if node.children == .Unavailable || node.children == .Failed do return .Tree_Failure
	switch node.kind {
	case .Project: return .Tree_Project
	case .Directory:
		if node.label == "src" || node.label == "docs" || node.label == "test" ||
		   node.label == "tests" || node.label == "config" {
			return .Tree_Directory_Special
		}
		return .Tree_Directory
	case .File:
		extension := filepath.ext(node.label)
		if extension == ".md" || extension == ".txt" || extension == ".org" {
			return .Tree_File_Documentation
		}
		if extension == ".toml" || extension == ".json" || extension == ".yaml" ||
		   extension == ".yml" || node.label == "Makefile" {
			return .Tree_File_Configuration
		}
		if node.label == ".gitignore" || node.label == ".gitattributes" {
			return .Tree_File_Version_Control
		}
		if extension == ".odin" || extension == ".rkt" || extension == ".go" ||
		   extension == ".rs" || extension == ".c" || extension == ".h" ||
		   extension == ".py" || extension == ".js" || extension == ".ts" ||
		   extension == ".tsx" {
			return .Tree_File_Source
		}
		return .Tree_File
	case .Symbol: return .Tree_File_Source
	case .Invalid:
		return .Tree_Inactive
	}
	return .Tree_Inactive
}

@(private)
instance_compressed_depth :: proc(state: ^Instance_State, index: int) -> u16 {
	if state == nil || index < 0 || index >= len(state.nodes) do return 0
	node := state.nodes[index]
	depth := node.depth
	parent_id := node.parent
	for parent_id != Node_ID(0) {
		parent_index := instance_find_node(state, parent_id)
		if parent_index < 0 do break
		parent := state.nodes[parent_index]
		child_count := 0
		for candidate in state.nodes {
			if candidate.parent == parent.handle.id do child_count += 1
		}
		if parent.kind == .Directory && child_count == 1 && depth > 0 do depth -= 1
		parent_id = parent.parent
	}
	return depth
}

/* tree_projection_view borrows one generic UI projection. */
tree_projection_view :: proc(
	projection: ^Tree_Projection,
) -> (view: Tree_Projection_View, ok: bool) {
	state := tree_projection_state(projection)
	if state == nil do return {}, false
	return Tree_Projection_View {
		instance_id = state.instance_id,
		node_generation = state.node_generation,
		nodes = state.nodes,
		current_node = state.current_node,
		first_visible = state.first_visible,
		viewport_nodes = state.viewport_nodes,
	}, true
}

/* tree_projection_close releases one copied generic tree definition generation. */
tree_projection_close :: proc(projection: ^Tree_Projection) -> bool {
	state := tree_projection_state(projection)
	if state == nil do return false
	allocator := state.allocator
	delete(state.nodes, allocator)
	free(state, allocator)
	projection^ = {}
	return true
}

@(private)
Tree_Projection_State :: struct {
	instance_id:     Instance_ID,
	node_generation: Node_Generation,
	nodes:           []ui.Tree_Node_Definition,
	current_node:    i32,
	first_visible:   u32,
	viewport_nodes:  u32,
	allocator:       runtime.Allocator,
}

@(private)
tree_projection_state :: proc(projection: ^Tree_Projection) -> ^Tree_Projection_State {
	if projection == nil || projection.state == nil do return nil
	return cast(^Tree_Projection_State)projection.state
}

@(private)
instance_expand_at :: proc(
	state: ^Instance_State,
	index: int,
	operation: Operation,
) -> (changed, ok: bool, failure: Failure_Context) {
	return instance_replace_children(state, index, operation)
}

@(private)
instance_replace_children :: proc(
	state: ^Instance_State,
	index: int,
	operation: Operation,
) -> (changed, ok: bool, failure: Failure_Context) {
	selected := state.nodes[index]
	batch, observed, filesystem_failure := filesystem.directory_observe(
		selected.path,
		u64(state.node_generation) + 1,
		{persistent = state.allocator, temporary = context.temp_allocator},
		true,
	)
	if !observed {
		failure = state_failure(state, operation, .Filesystem_Failure)
		failure.filesystem_failure = filesystem_failure
		failure.node = selected.handle.id
		return false, false, failure
	}
	defer filesystem.directory_batch_close(&batch)
	if batch.directory_identity != selected.resource {
		return false, false, state_failure(state, operation, .Invalid_Node)
	}
	if state.sort_mode == .Name_Descending {
		slice.sort_by(batch.descriptors, directory_entry_descending)
	}
	remove_end := index + 1
	for remove_end < len(state.nodes) && state.nodes[remove_end].depth > selected.depth {
		remove_end += 1
	}
	new_count := len(state.nodes) - (remove_end - index - 1) + len(batch.descriptors)
	if new_count > int(state.policy.nodes) {
		failure = state_failure(state, operation, .Node_Limit)
		failure.limit = u64(state.policy.nodes)
		failure.actual = u64(new_count)
		return false, false, failure
	}
	sources, allocation_error := make([]Node_Source, new_count, state.allocator)
	if allocation_error != nil do return false, false, state_failure(state, operation, .Allocation)
	defer delete(sources, state.allocator)
	write := 0
	for old in state.nodes[:index] {
		sources[write] = node_source(old)
		write += 1
	}
	parent_source := node_source(selected)
	parent_source.children = .Expanded
	parent_source.provider_generation = Provider_Generation(batch.generation)
	sources[write] = parent_source
	write += 1
	next_id := state.next_node_id
	for entry in batch.descriptors {
		kind := Node_Kind.File
		children := Child_State.Leaf
		actions: Action_Roles = {.Visit}
		if entry.kind == .Directory {
			kind = .Directory
			children = .Collapsed
			actions = {.Structure, .Visit, .Collapse}
		}
		id := instance_reconciled_child_id(state, index, remove_end, entry.identity)
		if id == Node_ID(0) {
			if next_id == Node_ID(max(u64)) {
				return false, false, state_failure(state, operation, .Invalid_Generation)
			}
			id = next_id
			next_id = Node_ID(u64(next_id) + 1)
		}
		sources[write] = Node_Source {
			id = id,
			parent = selected.handle.id,
			provider_id = LOCAL_PROVIDER,
			provider_generation = Provider_Generation(batch.generation),
			kind = kind,
			project = selected.project,
			resource = entry.identity,
			label = entry.name,
			path = entry.path,
			depth = selected.depth + 1,
			children = children,
			actions = actions,
			hidden = len(entry.name) > 0 && entry.name[0] == '.',
		}
		for old in state.nodes[index + 1:remove_end] {
			if old.resource != entry.identity do continue
			sources[write].ignored = old.ignored
			sources[write].version_control = old.version_control
			sources[write].diagnostic = old.diagnostic
			break
		}
		write += 1
	}
	for old in state.nodes[remove_end:] {
		sources[write] = node_source(old)
		write += 1
	}
	selected_id := state.selected
	selected_resource := selected.resource
	if old_selected := instance_selected_index(state); old_selected > index && old_selected < remove_end {
		selected_resource = state.nodes[old_selected].resource
		selected_id = Node_ID(0)
	}
	published, publish_failure := instance_publish_sources_reconcile(
		state, sources, selected_id, selected_resource,
	)
	if !published do return false, false, publish_failure
	state.next_node_id = next_id
	return true, true, {}
}

@(private)
instance_collapse_at :: proc(
	state: ^Instance_State,
	index: int,
) -> (changed, ok: bool, failure: Failure_Context) {
	selected := state.nodes[index]
	remove_end := index + 1
	for remove_end < len(state.nodes) && state.nodes[remove_end].depth > selected.depth {
		remove_end += 1
	}
	if remove_end == index + 1 do return false, true, {}
	sources, allocation_error := make(
		[]Node_Source, len(state.nodes) - (remove_end - index - 1), state.allocator,
	)
	if allocation_error != nil do return false, false, state_failure(state, .Expand, .Allocation)
	defer delete(sources, state.allocator)
	write := 0
	for old in state.nodes[:index] {
		sources[write] = node_source(old)
		write += 1
	}
	parent := node_source(selected)
	parent.children = .Collapsed
	sources[write] = parent
	write += 1
	for old in state.nodes[remove_end:] {
		sources[write] = node_source(old)
		write += 1
	}
	selected_id := state.selected
	if old_selected := instance_selected_index(state); old_selected > index && old_selected < remove_end {
		selected_id = selected.handle.id
	}
	published, publish_failure := instance_publish_sources(state, sources, selected_id, true)
	return published, published, publish_failure
}

@(private)
instance_publish_sources_reconcile :: proc(
	state: ^Instance_State,
	sources: []Node_Source,
	selected_id: Node_ID,
	selected_resource: filesystem.Resource_ID,
) -> (bool, Failure_Context) {
	reconciled := selected_id
	if reconciled == Node_ID(0) && filesystem.resource_id_valid(selected_resource) {
		for source in sources {
			if source.resource == selected_resource {
				reconciled = source.id
				break
			}
		}
	}
	if reconciled == Node_ID(0) && len(sources) > 0 do reconciled = sources[0].id
	return instance_publish_sources(state, sources, reconciled, len(sources) > 0)
}

@(private)
instance_publish_sources :: proc(
	state: ^Instance_State,
	sources: []Node_Source,
	selected: Node_ID,
	has_selection: bool,
) -> (bool, Failure_Context) {
	if state == nil || len(sources) == 0 || len(sources) > int(state.policy.nodes) ||
	   state.node_generation == Node_Generation(max(u64)) ||
	   state.task_generation == Task_Generation(max(u64)) ||
	   state.selection_generation == Selection_Generation(max(u64)) {
		return false, state_failure(state, .Publish, .Invalid_Generation)
	}
	text_bytes: u64
	for source, index in sources {
		if source.id == Node_ID(0) || source.kind == .Invalid || source.children == .Invalid ||
		   source.depth > state.policy.depth ||
		   (!filesystem.resource_id_valid(source.resource) && source.children != .Unavailable) ||
		   len(source.label) == 0 || len(source.path) == 0 {
			failure := state_failure(state, .Publish, .Invalid_Node)
			failure.actual = u64(index)
			return false, failure
		}
		for previous in sources[:index] {
			if previous.id == source.id {
				return false, state_failure(state, .Publish, .Duplicate_Node)
			}
		}
		if source.parent == Node_ID(0) {
			if source.depth != 0 {
				return false, state_failure(state, .Publish, .Invalid_Parent)
			}
		} else if !source_parent_precedes(sources[:index], source) {
			return false, state_failure(state, .Publish, .Invalid_Parent)
		}
		text_bytes += u64(len(source.label) + len(source.path))
	}
	if text_bytes > state.policy.retained_bytes {
		failure := state_failure(state, .Publish, .Retained_Byte_Limit)
		failure.limit = state.policy.retained_bytes
		failure.actual = text_bytes
		return false, failure
	}
	nodes, nodes_error := make([]Node_Descriptor, len(sources), state.allocator)
	if nodes_error != nil do return false, state_failure(state, .Publish, .Allocation)
	text, text_error := make([]u8, int(text_bytes), state.allocator)
	if text_error != nil {
		delete(nodes, state.allocator)
		return false, state_failure(state, .Publish, .Allocation)
	}
	next_generation := Node_Generation(u64(state.node_generation) + 1)
	offset := 0
	selected_found := false
	for source, index in sources {
		label_start := offset
		offset += copy(text[offset:], transmute([]u8)source.label)
		path_start := offset
		offset += copy(text[offset:], transmute([]u8)source.path)
		nodes[index] = Node_Descriptor {
			handle = {
				instance_id = state.id,
				instance_generation = state.generation,
				node_generation = next_generation,
				id = source.id,
			},
			parent = source.parent,
			provider_id = source.provider_id,
			provider_generation = source.provider_generation,
			kind = source.kind,
			project = source.project,
			resource = source.resource,
			label = string(text[label_start:path_start]),
			path = string(text[path_start:offset]),
			depth = source.depth,
			children = source.children,
			actions = source.actions,
			hidden = source.hidden,
			ignored = source.ignored,
			version_control = source.version_control,
			diagnostic = source.diagnostic,
			symbol_id = source.symbol_id,
			source_revision = source.source_revision,
			start = source.start,
			end = source.end,
		}
		if source.id == selected do selected_found = true
	}
	if has_selection && !selected_found {
		delete(text, state.allocator)
		delete(nodes, state.allocator)
		return false, state_failure(state, .Publish, .Node_Not_Found)
	}
	if state.retained_text != nil do delete(state.retained_text, state.allocator)
	if state.nodes != nil do delete(state.nodes, state.allocator)
	state.nodes = nodes
	state.retained_text = text
	state.node_generation = next_generation
	state.task_generation = Task_Generation(u64(state.task_generation) + 1)
	state.selection_generation = Selection_Generation(u64(state.selection_generation) + 1)
	state.selected = selected
	state.has_selection = has_selection
	instance_keep_selected_visible(state, instance_selected_index(state))
	return true, {}
}

@(private)
source_parent_precedes :: proc(sources: []Node_Source, source: Node_Source) -> bool {
	if source.parent == Node_ID(0) || source.depth == 0 do return false
	for parent in sources {
		if parent.id == source.parent {
			return (parent.kind == .Directory || parent.kind == .Project ||
				(parent.kind == .File || parent.kind == .Symbol) && source.kind == .Symbol) &&
				parent.children == .Expanded &&
				parent.depth + 1 == source.depth
		}
	}
	return false
}

@(private)
node_source :: proc(node: Node_Descriptor) -> Node_Source {
	return Node_Source {
		id = node.handle.id,
		parent = node.parent,
		provider_id = node.provider_id,
		provider_generation = node.provider_generation,
		kind = node.kind,
		project = node.project,
		resource = node.resource,
		label = node.label,
		path = node.path,
		depth = node.depth,
		children = node.children,
		actions = node.actions,
		hidden = node.hidden,
		ignored = node.ignored,
		version_control = node.version_control,
		diagnostic = node.diagnostic,
		symbol_id = node.symbol_id,
		source_revision = node.source_revision,
		start = node.start,
		end = node.end,
	}
}

@(private)
instance_find_project_root :: proc(state: ^Instance_State, handle: project.Project_Handle) -> int {
	if state == nil || !project.project_handle_is_valid(handle) do return -1
	for node, index in state.nodes {
		if node.parent == Node_ID(0) && node.kind == .Project && node.project == handle {
			return index
		}
	}
	return -1
}

@(private)
instance_subtree_end :: proc(state: ^Instance_State, index: int) -> int {
	if state == nil || index < 0 || index >= len(state.nodes) do return index
	end := index + 1
	for end < len(state.nodes) && state.nodes[end].depth > state.nodes[index].depth {
		end += 1
	}
	return end
}

@(private)
instance_reconciled_child_id :: proc(
	state: ^Instance_State,
	parent_index, remove_end: int,
	resource: filesystem.Resource_ID,
) -> Node_ID {
	parent_depth := state.nodes[parent_index].depth
	for node in state.nodes[parent_index + 1:remove_end] {
		if node.depth == parent_depth + 1 && node.resource == resource do return node.handle.id
	}
	return Node_ID(0)
}

@(private)
instance_find_node :: proc(state: ^Instance_State, id: Node_ID) -> int {
	if state == nil || id == Node_ID(0) do return -1
	for node, index in state.nodes {
		if node.handle.id == id do return index
	}
	return -1
}

@(private)
instance_selected_index :: proc(state: ^Instance_State) -> int {
	if state == nil || !state.has_selection do return -1
	return instance_find_node(state, state.selected)
}

@(private)
instance_selected_project_root_index :: proc(state: ^Instance_State) -> int {
	index := instance_selected_index(state)
	if index < 0 do return -1
	for state.nodes[index].parent != Node_ID(0) {
		index = instance_find_node(state, state.nodes[index].parent)
		if index < 0 do return -1
	}
	if state.nodes[index].kind != .Project do return -1
	return index
}

@(private)
instance_keep_selected_visible :: proc(state: ^Instance_State, index: int) {
	if state == nil || index < 0 || state.viewport_nodes == 0 do return
	current: u32
	found := false
	for _, candidate in state.nodes {
		if !instance_node_visible(state, candidate) do continue
		if candidate == index {
			found = true
			break
		}
		current += 1
	}
	if !found do return
	if current < state.first_visible do state.first_visible = current
	end := u64(state.first_visible) + u64(state.viewport_nodes)
	if u64(current) >= end do state.first_visible = current - state.viewport_nodes + 1
}

@(private)
directory_entry_descending :: proc(left, right: filesystem.Entry_Descriptor) -> bool {
	if left.kind != right.kind do return left.kind == .Directory
	return strings.compare(left.label, right.label) > 0
}

@(private)
state_failure :: proc(
	state: ^Instance_State,
	operation: Operation,
	code: Failure_Code,
) -> Failure_Context {
	if state == nil do return Failure_Context{operation = operation, code = code}
	return Failure_Context {
		operation = operation,
		code = code,
		instance_id = state.id,
		instance_generation = state.generation,
		node_generation = state.node_generation,
	}
}
