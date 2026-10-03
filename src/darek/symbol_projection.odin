// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package darek

import "../filesystem"

/* instance_publish_symbols replaces one file's copied language-owned symbol subtree. */
instance_publish_symbols :: proc(
	instance: ^Instance,
	expected_node_generation: Node_Generation,
	provider_generation: Provider_Generation,
	file_resource: filesystem.Resource_ID,
	file_path: string,
	source_revision: u64,
	symbols: []Symbol_Source,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil {
		return false, false, instance_failure(instance, .Publish, .Invalid_Instance)
	}
	if expected_node_generation == Node_Generation(0) ||
	   expected_node_generation != state.node_generation ||
	   provider_generation == Provider_Generation(0) ||
	   provider_generation <= state.symbol_generation {
		return false, false, state_failure(state, .Publish, .Stale_Generation)
	}
	if !filesystem.resource_id_valid(file_resource) || len(file_path) == 0 ||
	   len(symbols) > int(state.policy.nodes) {
		return false, false, state_failure(state, .Publish, .Invalid_Node)
	}
	file_index := -1
	for node, index in state.nodes {
		if node.kind == .File && node.resource == file_resource && node.path == file_path {
			file_index = index
			break
		}
	}
	if file_index < 0 do return false, false, state_failure(state, .Publish, .Stale_Generation)
	file := state.nodes[file_index]
	remove_end := instance_subtree_end(state, file_index)
	new_count := len(state.nodes) - (remove_end - file_index - 1) + len(symbols)
	if new_count > int(state.policy.nodes) {
		failure = state_failure(state, .Publish, .Node_Limit)
		failure.limit = u64(state.policy.nodes)
		failure.actual = u64(new_count)
		return false, false, failure
	}
	sources, allocation_error := make([]Node_Source, new_count, state.allocator)
	if allocation_error != nil do return false, false, state_failure(state, .Publish, .Allocation)
	defer delete(sources, state.allocator)
	write := 0
	for old in state.nodes[:file_index] {
		sources[write] = node_source(old)
		write += 1
	}
	file_source := node_source(file)
	file_source.children = .Expanded if len(symbols) > 0 else .Leaf
	file_source.actions = {.Structure, .Visit}
	sources[write] = file_source
	write += 1
	next_id := state.next_node_id
	for symbol, ordinal in symbols {
		if symbol.id == 0 || len(symbol.name) == 0 || symbol.end < symbol.start ||
		   u32(file.depth) + 1 + u32(symbol.hierarchy_depth) > u32(state.policy.depth) {
			return false, false, state_failure(state, .Publish, .Invalid_Node)
		}
		for previous in symbols[:ordinal] {
			if previous.id == symbol.id do return false, false, state_failure(state, .Publish, .Duplicate_Node)
		}
		parent := file.handle.id
		if symbol.parent_id != 0 {
			parent = Node_ID(0)
			for prior_index in 0 ..< ordinal {
				if symbols[prior_index].id == symbol.parent_id {
					parent = sources[file_index + 1 + prior_index].id
					break
				}
			}
			if parent == Node_ID(0) do return false, false, state_failure(state, .Publish, .Invalid_Parent)
		}
		id := Node_ID(0)
		for old in state.nodes[file_index + 1:remove_end] {
			if old.kind == .Symbol && old.symbol_id == symbol.id {
				id = old.handle.id
				break
			}
		}
		if id == Node_ID(0) {
			if next_id == Node_ID(max(u64)) {
				return false, false, state_failure(state, .Publish, .Invalid_Generation)
			}
			id = next_id
			next_id = Node_ID(u64(next_id) + 1)
		}
		has_children := false
		for candidate in symbols[ordinal + 1:] {
			if candidate.parent_id == symbol.id {
				has_children = true
				break
			}
		}
		sources[write] = Node_Source {
			id = id,
			parent = parent,
			provider_id = Provider_ID(2),
			provider_generation = provider_generation,
			kind = .Symbol,
			project = file.project,
			resource = file.resource,
			label = symbol.name,
			path = file.path,
			depth = file.depth + 1 + symbol.hierarchy_depth,
			children = .Expanded if has_children else .Leaf,
			actions = {.Visit},
			symbol_id = symbol.id,
			source_revision = source_revision,
			start = symbol.start,
			end = symbol.end,
		}
		write += 1
	}
	for old in state.nodes[remove_end:] {
		sources[write] = node_source(old)
		write += 1
	}
	selected := file.handle.id
	if current := instance_selected_index(state); current >= file_index && current < remove_end {
		selected_symbol := state.nodes[current].symbol_id
		for source in sources[file_index + 1:file_index + 1 + len(symbols)] {
			if source.symbol_id == selected_symbol {
				selected = source.id
				break
			}
		}
	} else {
		selected = state.selected
	}
	published, publish_failure := instance_publish_sources(state, sources, selected, true)
	if !published do return false, false, publish_failure
	state.next_node_id = next_id
	state.symbol_generation = provider_generation
	return true, true, {}
}
