// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package darek

import "../filesystem"
import "core:strings"
import "core:unicode/utf8"

/* instance_set_hidden_visible changes dot-entry projection without filesystem authority. */
instance_set_hidden_visible :: proc(
	instance: ^Instance,
	visible: bool,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil do return false, false, instance_failure(instance, .Visibility, .Invalid_Instance)
	if state.show_hidden == visible do return false, true, {}
	state.show_hidden = visible
	instance_reconcile_visible_selection(state)
	return true, true, {}
}

/* instance_set_ignored_visible changes provider-identified ignored-entry projection. */
instance_set_ignored_visible :: proc(
	instance: ^Instance,
	visible: bool,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil do return false, false, instance_failure(instance, .Visibility, .Invalid_Instance)
	if state.show_ignored == visible do return false, true, {}
	state.show_ignored = visible
	instance_reconcile_visible_selection(state)
	return true, true, {}
}

/* instance_set_version_control_visible changes copied VCS decoration projection. */
instance_set_version_control_visible :: proc(
	instance: ^Instance,
	visible: bool,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil do return false, false, instance_failure(instance, .Visibility, .Invalid_Instance)
	if state.show_version_control == visible do return false, true, {}
	state.show_version_control = visible
	return true, true, {}
}

/* instance_set_diagnostics_visible changes copied diagnostic decoration projection. */
instance_set_diagnostics_visible :: proc(
	instance: ^Instance,
	visible: bool,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil do return false, false, instance_failure(instance, .Visibility, .Invalid_Instance)
	if state.show_diagnostics == visible do return false, true, {}
	state.show_diagnostics = visible
	return true, true, {}
}

/* instance_set_name_filter copies one bounded substring filter and preserves visible identity. */
instance_set_name_filter :: proc(
	instance: ^Instance,
	filter: string,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil do return false, false, instance_failure(instance, .Visibility, .Invalid_Instance)
	if len(filter) > MAX_FILTER_BYTES || !utf8.valid_string(filter) || strings.index_byte(filter, 0) >= 0 {
		failure = state_failure(state, .Visibility, .Invalid_Node)
		failure.limit = MAX_FILTER_BYTES
		failure.actual = u64(len(filter))
		return false, false, failure
	}
	current := string(state.filter[:state.filter_length])
	if current == filter do return false, true, {}
	state.filter_length = copy(state.filter[:], transmute([]u8)filter)
	instance_reconcile_visible_selection(state)
	state.first_visible = 0
	return true, true, {}
}

/* instance_set_sort_mode changes deterministic sibling order and refreshes the selected scope. */
instance_set_sort_mode :: proc(
	instance: ^Instance,
	mode: Sort_Mode,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil || mode == .Invalid {
		return false, false, instance_failure(instance, .Visibility, .Invalid_Instance)
	}
	if state.sort_mode == mode do return false, true, {}
	previous := state.sort_mode
	state.sort_mode = mode
	selected := instance_selected_index(state)
	if selected >= 0 {
		if state.nodes[selected].kind == .Directory || state.nodes[selected].kind == .Project {
			if state.nodes[selected].children == .Expanded {
				_, refreshed, refresh_failure := instance_refresh_selected(instance)
				if !refreshed {
					state.sort_mode = previous
					return false, false, refresh_failure
				}
			}
		} else {
			_, refreshed, refresh_failure := instance_refresh_containing_directory(instance)
			if !refreshed {
				state.sort_mode = previous
				return false, false, refresh_failure
			}
		}
	}
	return true, true, {}
}

/* instance_publish_annotations atomically replaces copied provider decoration data. */
instance_publish_annotations :: proc(
	instance: ^Instance,
	generation: Provider_Generation,
	annotations: []Node_Annotation,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil || generation == Provider_Generation(0) ||
	   generation <= state.annotation_generation || len(annotations) > len(state.nodes) {
		return false, false, instance_failure(instance, .Publish, .Invalid_Generation)
	}
	for annotation, index in annotations {
		if !filesystem.resource_id_valid(annotation.resource) ||
		   annotation.provider_generation == Provider_Generation(0) {
			return false, false, state_failure(state, .Publish, .Invalid_Node)
		}
		for previous in annotations[:index] {
			if previous.resource == annotation.resource {
				return false, false, state_failure(state, .Publish, .Duplicate_Node)
			}
		}
	}
	sources, allocation_error := make([]Node_Source, len(state.nodes), state.allocator)
	if allocation_error != nil do return false, false, state_failure(state, .Publish, .Allocation)
	defer delete(sources, state.allocator)
	changed = state.annotation_generation != generation
	for node, index in state.nodes {
		sources[index] = node_source(node)
		sources[index].ignored = false
		sources[index].version_control = .None
		sources[index].diagnostic = .None
		for annotation in annotations {
			if annotation.resource != node.resource do continue
			sources[index].ignored = annotation.ignored
			sources[index].version_control = annotation.version_control
			sources[index].diagnostic = annotation.diagnostic
			break
		}
	}
	published, publish_failure := instance_publish_sources(
		state, sources, state.selected, state.has_selection,
	)
	if !published do return false, false, publish_failure
	state.annotation_generation = generation
	instance_reconcile_visible_selection(state)
	return changed, true, {}
}

/* instance_set_watch_enabled changes one provider-owned bounded watch lifecycle. */
instance_set_watch_enabled :: proc(
	instance: ^Instance,
	enabled: bool,
	provider_generation: Provider_Generation,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil || (enabled && provider_generation == Provider_Generation(0)) {
		return false, false, instance_failure(instance, .Visibility, .Invalid_Instance)
	}
	if state.watch_enabled == enabled && (!enabled || state.watch_provider_generation == provider_generation) {
		return false, true, {}
	}
	if state.watch_generation == max(u64) {
		return false, false, state_failure(state, .Visibility, .Invalid_Generation)
	}
	state.watch_enabled = enabled
	state.watch_provider_generation = provider_generation if enabled else Provider_Generation(0)
	state.watch_status = .Watching if enabled else .Disabled
	state.watch_pending_hints = 0
	state.watch_generation += 1
	return true, true, {}
}

/* instance_observe_watch_hint coalesces bounded provider hints into refresh work. */
instance_observe_watch_hint :: proc(
	instance: ^Instance,
	provider_generation: Provider_Generation,
	hint: Watch_Hint,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil || !state.watch_enabled || hint == .Invalid ||
	   provider_generation != state.watch_provider_generation {
		return false, false, instance_failure(instance, .Refresh, .Stale_Generation)
	}
	if state.watch_pending_hints >= MAX_WATCH_HINTS {
		failure = state_failure(state, .Refresh, .Node_Limit)
		failure.limit = u64(MAX_WATCH_HINTS)
		failure.actual = u64(state.watch_pending_hints) + 1
		state.watch_status = .Refresh_Required
		return false, false, failure
	}
	state.watch_pending_hints += 1
	state.watch_status = .Refresh_Required
	return true, true, {}
}

/* instance_reconcile_watch replaces one complete selected subtree after watcher hints. */
instance_reconcile_watch :: proc(
	instance: ^Instance,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil || !state.watch_enabled {
		return false, false, instance_failure(instance, .Refresh, .Invalid_Instance)
	}
	if state.watch_status != .Refresh_Required do return false, true, {}
	if state.watch_generation == max(u64) {
		return false, false, state_failure(state, .Refresh, .Invalid_Generation)
	}
	selected := instance_selected_index(state)
	if selected < 0 do return false, false, state_failure(state, .Refresh, .Node_Not_Found)
	if state.nodes[selected].kind == .Directory || state.nodes[selected].kind == .Project {
		if state.nodes[selected].children == .Expanded {
			changed, ok, failure = instance_refresh_selected(instance)
		} else {
			changed, ok = false, true
		}
	} else {
		changed, ok, failure = instance_refresh_containing_directory(instance)
	}
	if !ok do return changed, false, failure
	state = instance_state(instance)
	state.watch_pending_hints = 0
	state.watch_status = .Watching
	state.watch_generation += 1
	return changed, true, {}
}

@(private)
instance_node_policy_visible :: proc(state: ^Instance_State, index: int) -> bool {
	if state == nil || index < 0 || index >= len(state.nodes) do return false
	project_index := instance_selected_project_root_index(state)
	project_id := Node_ID(0)
	if project_index >= 0 do project_id = state.nodes[project_index].handle.id
	if state.current_project_only && !node_belongs_to_project(state, state.nodes[index], project_id) do return false
	current := index
	for current >= 0 {
		node := state.nodes[current]
		if (!state.show_hidden && node.hidden) || (!state.show_ignored && node.ignored) do return false
		if node.parent == Node_ID(0) do break
		current = instance_find_node(state, node.parent)
	}
	return true
}

@(private)
instance_node_visible :: proc(state: ^Instance_State, index: int) -> bool {
	if !instance_node_policy_visible(state, index) do return false
	filter := string(state.filter[:state.filter_length])
	if len(filter) == 0 do return true
	node := state.nodes[index]
	if node.parent == Node_ID(0) || strings.contains(node.label, filter) do return true
	if node.kind != .Directory && node.kind != .Project do return false
	end := instance_subtree_end(state, index)
	for descendant in index + 1 ..< end {
		if instance_node_policy_visible(state, descendant) &&
		   strings.contains(state.nodes[descendant].label, filter) {
			return true
		}
	}
	return false
}

@(private)
instance_reconcile_visible_selection :: proc(state: ^Instance_State) {
	if state == nil || len(state.nodes) == 0 do return
	selected := instance_selected_index(state)
	if selected >= 0 && instance_node_visible(state, selected) {
		instance_keep_selected_visible(state, selected)
		return
	}
	for selected >= 0 && state.nodes[selected].parent != Node_ID(0) {
		selected = instance_find_node(state, state.nodes[selected].parent)
		if selected >= 0 && instance_node_visible(state, selected) {
			state.selected = state.nodes[selected].handle.id
			instance_keep_selected_visible(state, selected)
			return
		}
	}
	for node, index in state.nodes {
		if instance_node_visible(state, index) {
			state.selected = node.handle.id
			state.has_selection = true
			instance_keep_selected_visible(state, index)
			return
		}
	}
	state.has_selection = false
	state.selected = Node_ID(0)
	state.first_visible = 0
}
