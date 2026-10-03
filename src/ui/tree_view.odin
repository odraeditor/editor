// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:unicode/utf8"

/* MAX_TREE_DEPTH bounds one visible tree projection independently of composition depth. */
MAX_TREE_DEPTH :: 64

/* proposal_project_tree_view copies one checked visible preorder tree generation. */
proposal_project_tree_view :: proc(
	proposal: ^Proposal,
	request: Tree_Projection_Request,
	nodes: []Tree_Node_Definition,
) -> (handle: Object_Handle, ok: bool, failure: Failure) {
	state := proposal_state(proposal)
	if state == nil || request.model.owner_id == Owner_ID(0) ||
	   request.model.model_id == Model_ID(0) || request.model.generation == Model_Generation(0) ||
	   len(nodes) > int(max(u32)) {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Tree_View)
	}
	node_count := u32(len(nodes))
	tree_state := Tree_View_State {
		present = true,
		node_offset = u32(state.tree_node_count),
		node_count = node_count,
		position = request.position,
	}
	if !tree_view_state_is_valid(tree_state) {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Tree_View)
	}
	if state.projection_count >= len(state.projections) || state.view_count >= len(state.views) {
		return {}, false, generation_failure(state, .Prepare, .View_Limit)
	}
	if len(nodes) > len(state.tree_nodes) - state.tree_node_count {
		failure = generation_failure(state, .Prepare, .Tree_Node_Limit)
		failure.limit = u64(state.registry.limits.tree_nodes)
		failure.actual = u64(state.tree_node_count) + u64(len(nodes))
		return {}, false, failure
	}
	if !resolve_style_role(state, .List_Normal) || !resolve_style_role(state, .List_Current) {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Style)
	}
	text_bytes: u64
	for node, index in nodes {
		indent_depth := node.indent_depth
		if indent_depth == 0 && node.depth > 0 do indent_depth = node.depth
		if node.id == Tree_Node_ID(0) || node.depth > MAX_TREE_DEPTH ||
		   indent_depth > node.depth || (!node.expandable && node.expanded) ||
		   !list_action_reference_is_valid(node.action) {
			failure = generation_failure(state, .Prepare, .Invalid_Tree_Node)
			failure.actual = u64(index)
			return {}, false, failure
		}
		for previous in nodes[:index] {
			if previous.id == node.id {
				failure = generation_failure(state, .Prepare, .Duplicate_Tree_Node)
				failure.actual = u64(index)
				return {}, false, failure
			}
		}
		if node.depth == 0 {
			if node.parent != Tree_Node_ID(0) {
				return {}, false, generation_failure(state, .Prepare, .Invalid_Tree_Node)
			}
		} else if !tree_parent_precedes(nodes[:index], node.parent, node.depth) {
			failure = generation_failure(state, .Prepare, .Invalid_Tree_Node)
			failure.actual = u64(index)
			return {}, false, failure
		}
		if !utf8.valid_string(node.text) || len(node.text) == 0 || len(node.text) > int(max(u32)) {
			failure = generation_failure(state, .Prepare, .Malformed_Tree_Text)
			failure.actual = u64(index)
			return {}, false, failure
		}
		if !utf8.valid_string(node.icon) || len(node.icon) > MAX_TREE_ICON_BYTES {
			failure = generation_failure(state, .Prepare, .Malformed_Tree_Text)
			failure.actual = u64(index)
			return {}, false, failure
		}
		if node.icon_role > .Failure ||
		   (node.icon_style_role != .Invalid && !style_role_is_valid(node.icon_style_role)) {
			return {}, false, generation_failure(state, .Prepare, .Invalid_Style)
		}
		if node.style_span_count > MAX_LIST_ITEM_STYLE_SPANS {
			return {}, false, generation_failure(state, .Prepare, .Invalid_Style)
		}
		previous_end := u32(0)
		for span_index in 0 ..< int(node.style_span_count) {
			span := node.style_spans[span_index]
			if span.start_byte < previous_end || span.start_byte >= span.end_byte ||
			   span.end_byte > u32(len(node.text)) || !style_role_is_valid(span.style_role) ||
			   !utf8.valid_string(node.text[:int(span.start_byte)]) ||
			   !utf8.valid_string(node.text[:int(span.end_byte)]) ||
			   !resolve_style_role(state, span.style_role) {
				return {}, false, generation_failure(state, .Prepare, .Invalid_Style)
			}
			previous_end = span.end_byte
		}
		if u64(len(node.text) + len(node.icon)) > max(u64) - text_bytes {
			return {}, false, generation_failure(state, .Prepare, .Checked_Integer_Overflow)
		}
		text_bytes += u64(len(node.text) + len(node.icon))
	}
	descriptor_bytes := u64(len(nodes)) * u64(size_of(Tree_Node_Descriptor))
	if text_bytes > max(u64) - descriptor_bytes {
		return {}, false, generation_failure(state, .Prepare, .Checked_Integer_Overflow)
	}
	projection_bytes := descriptor_bytes + text_bytes
	if projection_bytes > state.registry.limits.projection_bytes - state.accounting.projection_bytes {
		failure = generation_failure(state, .Prepare, .Projection_Limit)
		failure.limit = state.registry.limits.projection_bytes
		failure.actual = state.accounting.projection_bytes + projection_bytes
		return {}, false, failure
	}
	if text_bytes > u64(max(int)) - u64(len(state.tree_content)) {
		return {}, false, generation_failure(state, .Prepare, .Checked_Integer_Overflow)
	}
	temporary_bytes := u64(len(state.tree_content)) * 2 + text_bytes
	if temporary_bytes > state.registry.limits.temporary_bytes {
		failure = generation_failure(state, .Prepare, .Temporary_Memory_Limit)
		failure.limit = state.registry.limits.temporary_bytes
		failure.actual = temporary_bytes
		return {}, false, failure
	}
	content, allocation_error := make(
		[]u8, len(state.tree_content) + int(text_bytes), state.allocator,
	)
	if allocation_error != nil {
		return {}, false, generation_failure(state, .Prepare, .Allocation)
	}
	copy(content, state.tree_content)
	projection, projection_ok := next_handle(state, state.projection_count)
	view, view_ok := next_handle(state, state.view_count)
	assert(projection_ok && view_ok)
	content_offset := len(state.tree_content)
	for node, index in nodes {
		indent_depth := node.indent_depth
		if indent_depth == 0 && node.depth > 0 do indent_depth = node.depth
		copy(content[content_offset:], transmute([]u8)node.text)
		icon_offset := content_offset + len(node.text)
		copy(content[icon_offset:], transmute([]u8)node.icon)
		state.tree_nodes[state.tree_node_count + index] = Tree_Node_Descriptor {
			projection = projection,
			id = node.id,
			parent = node.parent,
			text_offset = u64(content_offset),
			text_bytes = u32(len(node.text)),
			icon_offset = u64(icon_offset),
			icon_bytes = u8(len(node.icon)),
			icon_role = node.icon_role,
			icon_style_role = node.icon_style_role,
			depth = node.depth,
			indent_depth = indent_depth,
			expandable = node.expandable,
			expanded = node.expanded,
			action = node.action,
			style_spans = node.style_spans,
			style_span_count = node.style_span_count,
		}
		content_offset += len(node.text) + len(node.icon)
	}
	if state.tree_content != nil do delete(state.tree_content, state.allocator)
	state.tree_content = content
	state.projections[state.projection_count] = Projection_Descriptor {
		handle = projection,
		model = request.model,
		byte_count = projection_bytes,
		item_count = node_count,
		read_only = request.read_only,
	}
	state.projection_count += 1
	state.views[state.view_count] = Visual_View_Descriptor {
		handle = view,
		kind = .Tree_View,
		projection = projection,
		read_only = request.read_only,
		tree = tree_state,
	}
	state.view_count += 1
	state.tree_node_count += len(nodes)
	state.accounting.projection_bytes += projection_bytes
	state.accounting.tree_nodes = u32(state.tree_node_count)
	state.accounting.temporary_peak_bytes = max(
		state.accounting.temporary_peak_bytes, temporary_bytes,
	)
	return view, true, {}
}

/* snapshot_tree_nodes borrows every visible node owned by one tree view. */
snapshot_tree_nodes :: proc(
	snapshot: Snapshot_View,
	view: Visual_View_Descriptor,
) -> (nodes: []Tree_Node_Descriptor, ok: bool) {
	if view.kind != .Tree_View || !tree_view_state_is_valid(view.tree) ||
	   int(view.handle.slot) >= len(snapshot.views) || snapshot.views[view.handle.slot] != view {
		return nil, false
	}
	start := int(view.tree.node_offset)
	count := int(view.tree.node_count)
	if start > len(snapshot.tree_nodes) || count > len(snapshot.tree_nodes) - start {
		return nil, false
	}
	return snapshot.tree_nodes[start:start + count], true
}

/* snapshot_tree_visible_nodes borrows the clipped tree viewport. */
snapshot_tree_visible_nodes :: proc(
	snapshot: Snapshot_View,
	view: Visual_View_Descriptor,
) -> (nodes: []Tree_Node_Descriptor, ok: bool) {
	all, all_ok := snapshot_tree_nodes(snapshot, view)
	if !all_ok do return nil, false
	first := int(view.tree.position.first_visible_item)
	visible := min(int(view.tree.position.viewport_items), len(all) - first)
	return all[first:first + visible], true
}

/* snapshot_tree_node_text borrows one checked UTF-8 node label. */
snapshot_tree_node_text :: proc(
	snapshot: Snapshot_View,
	node: Tree_Node_Descriptor,
) -> (text: string, ok: bool) {
	if node.id == Tree_Node_ID(0) || node.text_offset > u64(len(snapshot.tree_content)) ||
	   u64(node.text_bytes) > u64(len(snapshot.tree_content)) - node.text_offset {
		return "", false
	}
	start := int(node.text_offset)
	return string(snapshot.tree_content[start:start + int(node.text_bytes)]), true
}

/* snapshot_tree_node_icon borrows one checked optional text icon. */
snapshot_tree_node_icon :: proc(
	snapshot: Snapshot_View,
	node: Tree_Node_Descriptor,
) -> (icon: string, ok: bool) {
	if node.id == Tree_Node_ID(0) || node.icon_offset > u64(len(snapshot.tree_content)) ||
	   u64(node.icon_bytes) > u64(len(snapshot.tree_content)) - node.icon_offset {
		return "", false
	}
	start := int(node.icon_offset)
	return string(snapshot.tree_content[start:start + int(node.icon_bytes)]), true
}

@(private)
tree_parent_precedes :: proc(
	nodes: []Tree_Node_Definition,
	parent: Tree_Node_ID,
	depth: u16,
) -> bool {
	if parent == Tree_Node_ID(0) || depth == 0 do return false
	for node in nodes {
		if node.id == parent {
			return node.expandable && node.expanded && node.depth + 1 == depth
		}
	}
	return false
}

@(private)
tree_view_matches_projection :: proc(
	generation: ^Generation_State,
	tree: Tree_View_State,
	projection: ^Projection_Descriptor,
) -> bool {
	if generation == nil || projection == nil || !tree_view_state_is_valid(tree) ||
	   projection.item_count != tree.node_count {
		return false
	}
	start := int(tree.node_offset)
	count := int(tree.node_count)
	if start > generation.tree_node_count || count > generation.tree_node_count - start {
		return false
	}
	text_bytes: u64
	nodes := generation.tree_nodes[start:start + count]
	for node, index in nodes {
		if node.projection != projection.handle || node.id == Tree_Node_ID(0) ||
		   node.depth > MAX_TREE_DEPTH || (!node.expandable && node.expanded) ||
		   !list_action_reference_is_valid(node.action) ||
		   node.text_offset > u64(len(generation.tree_content)) ||
		   u64(node.text_bytes) > u64(len(generation.tree_content)) - node.text_offset ||
		   node.icon_offset > u64(len(generation.tree_content)) ||
		   u64(node.icon_bytes) > u64(len(generation.tree_content)) - node.icon_offset ||
		   node.indent_depth > node.depth {
			return false
		}
		if node.depth == 0 {
			if node.parent != Tree_Node_ID(0) do return false
		} else if !tree_descriptor_parent_precedes(nodes[:index], node) {
			return false
		}
		for previous in nodes[:index] {
			if previous.id == node.id do return false
		}
		text_bytes += u64(node.text_bytes) + u64(node.icon_bytes)
	}
	return projection.byte_count ==
		u64(count) * u64(size_of(Tree_Node_Descriptor)) + text_bytes
}

@(private)
tree_descriptor_parent_precedes :: proc(
	nodes: []Tree_Node_Descriptor,
	node: Tree_Node_Descriptor,
) -> bool {
	if node.parent == Tree_Node_ID(0) || node.depth == 0 do return false
	for parent in nodes {
		if parent.id == node.parent {
			return parent.expandable && parent.expanded && parent.depth + 1 == node.depth
		}
	}
	return false
}
