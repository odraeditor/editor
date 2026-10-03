// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

import "../view"

/* registry_split_below replaces the active pane with an above/below partition. */
registry_split_below :: proc(
	registry: ^Registry,
	source: Pane_Handle,
) -> (result: Split_Result, ok: bool, failure: Failure_Context) {
	return registry_split(registry, source, .Above_Below)
}

/* registry_split_right replaces the active pane with a left/right partition. */
registry_split_right :: proc(
	registry: ^Registry,
	source: Pane_Handle,
) -> (result: Split_Result, ok: bool, failure: Failure_Context) {
	return registry_split(registry, source, .Left_Right)
}

/* registry_focus synchronizes view points before publishing pane focus and MRU. */
registry_focus :: proc(
	registry: ^Registry,
	target: Pane_Handle,
) -> (result: Focus_Result, ok: bool, failure: Failure_Context) {
	data, resolved := resolve_layout(registry, target.layout, .Focus)
	if resolved.code != .None {
		return {}, false, resolved
	}
	_, target_ref, target_failure := resolve_pane(data, target, .Focus)
	if target_failure.code != .None {
		return {}, false, target_failure
	}
	if target_ref == data.active {
		return Focus_Result{layout = current_layout_handle(data), active = pane_handle(data, data.active)}, true, {}
	}
	if !prepared_state_fits(data) {
		return {}, false, prepared_failure(data, .Focus)
	}
	if data.generation == Layout_Generation(max(u64)) {
		return {}, false, data_failure(data, .Focus, .Generation_Limit)
	}
	proposed, prepared := prepared_state_copy(data, .Focus)
	if prepared.code != .None {
		return {}, false, prepared
	}
	defer prepared_state_release(proposed)
	proposed.generation = Layout_Generation(u64(data.generation) + 1)
	proposed.active = target_ref
	mru_promote(proposed, target_ref)
	if !validate_layout_state(proposed) {
		return {}, false, data_failure(data, .Focus, .Invalid_Topology)
	}
	outgoing := resolve_node(data, data.active)
	incoming := resolve_node(data, target_ref)
	assert(outgoing != nil && incoming != nil)
	transferred, view_failure := view.transfer_focus(data.view_registry, outgoing.view, incoming.view)
	if !transferred {
		return {}, false, layout_view_failure(data, .Focus, view_failure)
	}
	result = Focus_Result {
		layout = current_layout_handle(proposed),
		active = pane_handle(proposed, proposed.active),
	}
	registry_publish(registry, proposed)
	return result, true, {}
}

/* registry_close_pane removes the active non-final pane and promotes its MRU survivor. */
registry_close_pane :: proc(
	registry: ^Registry,
	target: Pane_Handle,
) -> (result: Focus_Result, ok: bool, failure: Failure_Context) {
	data, resolved := resolve_layout(registry, target.layout, .Close)
	if resolved.code != .None {
		return {}, false, resolved
	}
	target_slot, target_ref, target_failure := resolve_pane(data, target, .Close)
	if target_failure.code != .None {
		return {}, false, target_failure
	}
	if target_ref != data.active {
		failure = data_failure(data, .Close, .Invalid_Pane)
		failure.pane = target
		return {}, false, failure
	}
	if data.pane_count == 1 {
		failure = data_failure(data, .Close, .Final_Pane)
		failure.pane = target
		return {}, false, failure
	}
	if !prepared_state_fits(data) {
		return {}, false, prepared_failure(data, .Close)
	}
	if data.generation == Layout_Generation(max(u64)) {
		return {}, false, data_failure(data, .Close, .Generation_Limit)
	}
	proposed, prepared := prepared_state_copy(data, .Close)
	if prepared.code != .None {
		return {}, false, prepared
	}
	defer prepared_state_release(proposed)
	if !remove_pane_from_state(proposed, target_ref) {
		return {}, false, data_failure(data, .Close, .Invalid_Topology)
	}
	proposed.generation = Layout_Generation(u64(data.generation) + 1)
	materialized, materialize_failure := geometry_materialize_data(
		proposed,
		proposed.geometry_request,
		.External_Shrink,
		.Close,
		false,
	)
	if !materialized {
		return {}, false, materialize_failure
	}
	if !validate_layout_state(proposed) {
		return {}, false, data_failure(data, .Close, .Invalid_Topology)
	}
	target_view_state, target_view_ok, target_view_failure := view.snapshot(data.view_registry, target_slot.view)
	if !target_view_ok {
		return {}, false, layout_view_failure(data, .Close, target_view_failure)
	}
	if target_view_state.presentation_ownership == .Additional {
		close_ready, close_ready_failure := view.validate_close(data.view_registry, target_slot.view)
		if !close_ready {
			return {}, false, layout_view_failure(data, .Close, close_ready_failure)
		}
	}
	incoming := resolve_node(data, proposed.active)
	assert(incoming != nil)
	transferred, transfer_failure := view.transfer_focus(data.view_registry, target_slot.view, incoming.view)
	if !transferred {
		return {}, false, layout_view_failure(data, .Close, transfer_failure)
	}
	if target_view_state.presentation_ownership == .Additional {
		removed_view := target_slot.view
		closed, _ := view.close(data.view_registry, &removed_view)
		assert(closed)
	}
	result = Focus_Result {
		layout = current_layout_handle(proposed),
		active = pane_handle(proposed, proposed.active),
	}
	registry_publish(registry, proposed)
	return result, true, {}
}

@(private)
remove_pane_from_state :: proc(data: ^Registry_Data, target_ref: Node_Ref) -> bool {
	target := resolve_node(data, target_ref)
	if target == nil || target.kind != .Pane || data.pane_count <= 1 {
		return false
	}
	parent_ref := target.parent
	parent := resolve_node(data, parent_ref)
	if parent == nil || parent.kind != .Partition {
		return false
	}
	sibling_ref := parent.first
	if sibling_ref == target_ref {
		sibling_ref = parent.second
	} else if parent.second != target_ref {
		return false
	}
	grandparent_ref := parent.parent
	if parent_ref == data.root {
		data.root = sibling_ref
	} else if !replace_child(data, grandparent_ref, parent_ref, sibling_ref) {
		return false
	}
	sibling := resolve_node(data, sibling_ref)
	if sibling == nil {
		return false
	}
	sibling.parent = grandparent_ref
	if !decrement_subtree_depth(data, sibling_ref) {
		return false
	}
	clear_node(&data.nodes[int(target_ref.slot)])
	clear_node(&data.nodes[int(parent_ref.slot)])
	data.node_count -= 2
	data.pane_count -= 1
	data.partition_count -= 1
	mru_remove(data, target_ref)
	if data.mru_count == 0 {
		return false
	}
	data.active = data.mru[0]
	return true
}

/* registry_keep_only removes every pane except the active pane. */
registry_keep_only :: proc(
	registry: ^Registry,
	target: Pane_Handle,
) -> (result: Focus_Result, ok: bool, failure: Failure_Context) {
	data, resolved := resolve_layout(registry, target.layout, .Keep_Only)
	if resolved.code != .None {
		return {}, false, resolved
	}
	_, target_ref, target_failure := resolve_pane(data, target, .Keep_Only)
	if target_failure.code != .None {
		return {}, false, target_failure
	}
	if target_ref != data.active {
		failure = data_failure(data, .Keep_Only, .Invalid_Pane)
		failure.pane = target
		return {}, false, failure
	}
	if data.pane_count == 1 {
		return Focus_Result{layout = current_layout_handle(data), active = pane_handle(data, data.active)}, true, {}
	}
	if !prepared_state_fits(data) {
		return {}, false, prepared_failure(data, .Keep_Only)
	}
	if data.generation == Layout_Generation(max(u64)) {
		return {}, false, data_failure(data, .Keep_Only, .Generation_Limit)
	}
	proposed, prepared := prepared_state_copy(data, .Keep_Only)
	if prepared.code != .None {
		return {}, false, prepared
	}
	defer prepared_state_release(proposed)
	retained := proposed.nodes[int(target_ref.slot)]
	for &slot in proposed.nodes {
		clear_node(&slot)
	}
	retained.parent = {}
	retained.depth = 0
	retained.geometry = {}
	proposed.nodes[int(target_ref.slot)] = retained
	proposed.root = target_ref
	proposed.active = target_ref
	proposed.mru = {}
	proposed.mru[0] = target_ref
	proposed.mru_count = 1
	proposed.node_count = 1
	proposed.pane_count = 1
	proposed.partition_count = 0
	proposed.generation = Layout_Generation(u64(data.generation) + 1)
	materialized, materialize_failure := geometry_materialize_data(
		proposed,
		proposed.geometry_request,
		.External_Shrink,
		.Keep_Only,
		false,
	)
	if !materialized {
		return {}, false, materialize_failure
	}
	if !validate_layout_state(proposed) {
		return {}, false, data_failure(data, .Keep_Only, .Invalid_Topology)
	}
	additional: [MAX_LIVE_PANES]view.View_Handle
	additional_count: int
	for &slot in data.nodes {
		if !slot.live || slot.kind != .Pane || slot.pane_id == target.pane_id {
			continue
		}
		state, state_ok, state_failure := view.snapshot(data.view_registry, slot.view)
		if !state_ok {
			return {}, false, layout_view_failure(data, .Keep_Only, state_failure)
		}
		if state.presentation_ownership == .Additional {
			close_ready, close_ready_failure := view.validate_close(data.view_registry, slot.view)
			if !close_ready {
				return {}, false, layout_view_failure(data, .Keep_Only, close_ready_failure)
			}
			additional[additional_count] = slot.view
			additional_count += 1
		}
	}
	for handle in additional[:additional_count] {
		removed := handle
		closed, _ := view.close(data.view_registry, &removed)
		assert(closed)
	}
	result = Focus_Result {
		layout = current_layout_handle(proposed),
		active = pane_handle(proposed, proposed.active),
	}
	registry_publish(registry, proposed)
	return result, true, {}
}

@(private)
registry_split :: proc(
	registry: ^Registry,
	source: Pane_Handle,
	arrangement: Arrangement,
) -> (result: Split_Result, ok: bool, failure: Failure_Context) {
	data, resolved := resolve_layout(registry, source.layout, .Split)
	if resolved.code != .None {
		return {}, false, resolved
	}
	source_slot, source_ref, source_failure := resolve_pane(data, source, .Split)
	if source_failure.code != .None {
		return {}, false, source_failure
	}
	if source_ref != data.active || (arrangement != .Above_Below && arrangement != .Left_Right) {
		failure = data_failure(data, .Split, .Invalid_Pane)
		failure.pane = source
		return {}, false, failure
	}
	if !prepared_state_fits(data) {
		return {}, false, prepared_failure(data, .Split)
	}
	if data.pane_count >= data.policy.live_panes {
		failure = data_failure(data, .Split, .Pane_Limit)
		failure.maximum = u64(data.policy.live_panes)
		failure.actual = u64(data.pane_count) + 1
		return {}, false, failure
	}
	if source_slot.depth >= data.policy.partition_depth {
		failure = data_failure(data, .Split, .Depth_Limit)
		failure.maximum = u64(data.policy.partition_depth)
		failure.actual = u64(source_slot.depth) + 1
		return {}, false, failure
	}
	if data.generation == Layout_Generation(max(u64)) ||
	   u64(data.next_node_id) > max(u64) - 2 || u64(data.next_pane_id) == max(u64) {
		return {}, false, data_failure(data, .Split, .Generation_Limit)
	}
	proposed, prepared := prepared_state_copy(data, .Split)
	if prepared.code != .None {
		return {}, false, prepared
	}
	defer prepared_state_release(proposed)
	partition_ref, partition_ok := allocate_node(proposed)
	new_pane_ref, new_pane_ok := allocate_node(proposed)
	if !partition_ok || !new_pane_ok {
		failure = data_failure(data, .Split, .Pane_Limit)
		failure.maximum = MAX_NODES
		failure.actual = u64(data.node_count) + 2
		return {}, false, failure
	}
	partition_generation := proposed.nodes[int(partition_ref.slot)].generation
	new_pane_generation := proposed.nodes[int(new_pane_ref.slot)].generation
	previous_parent := source_slot.parent
	previous_depth := source_slot.depth
	proposed.nodes[int(partition_ref.slot)] = Node_Slot {
		live = true,
		kind = .Partition,
		node_id = proposed.next_node_id,
		generation = partition_generation,
		parent = previous_parent,
		depth = previous_depth,
		arrangement = arrangement,
		first = source_ref,
		second = new_pane_ref,
		first_weight = 1,
		second_weight = 1,
	}
	proposed.next_node_id = Node_ID(u64(proposed.next_node_id) + 1)
	proposed.nodes[int(new_pane_ref.slot)] = Node_Slot {
		live = true,
		kind = .Pane,
		node_id = proposed.next_node_id,
		generation = new_pane_generation,
		parent = partition_ref,
		depth = previous_depth + 1,
		pane_id = proposed.next_pane_id,
		view = source_slot.view,
		buffer_id = source_slot.buffer_id,
		entry = source_slot.entry,
		history = source_slot.history,
		history_count = source_slot.history_count,
		history_generation = source_slot.history_generation,
	}
	proposed.next_node_id = Node_ID(u64(proposed.next_node_id) + 1)
	proposed.next_pane_id = Pane_ID(u64(proposed.next_pane_id) + 1)
	proposed.nodes[int(source_ref.slot)].parent = partition_ref
	proposed.nodes[int(source_ref.slot)].depth = previous_depth + 1
	if source_ref == proposed.root {
		proposed.root = partition_ref
	} else if !replace_child(proposed, previous_parent, source_ref, partition_ref) {
		return {}, false, data_failure(data, .Split, .Invalid_Parent)
	}
	proposed.mru[int(proposed.mru_count)] = new_pane_ref
	proposed.mru_count += 1
	proposed.node_count += 2
	proposed.pane_count += 1
	proposed.partition_count += 1
	proposed.generation = Layout_Generation(u64(data.generation) + 1)
	materialized, materialize_failure := geometry_materialize_data(
		proposed,
		proposed.geometry_request,
		.Operating,
		.Split,
		false,
	)
	if !materialized {
		return {}, false, materialize_failure
	}
	if !validate_layout_state(proposed) {
		return {}, false, data_failure(data, .Split, .Invalid_Topology)
	}
	created_view, created_ok, created_failure := view.clone_additional(data.view_registry, source_slot.view)
	if !created_ok {
		return {}, false, layout_view_failure(data, .Split, created_failure)
	}
	proposed.nodes[int(new_pane_ref.slot)].view = created_view
	result = Split_Result {
		layout = current_layout_handle(proposed),
		original = pane_handle(proposed, source_ref),
		created = pane_handle(proposed, new_pane_ref),
	}
	registry_publish(registry, proposed)
	return result, true, {}
}

@(private)
allocate_node :: proc(data: ^Registry_Data) -> (ref: Node_Ref, ok: bool) {
	for &slot, index in data.nodes {
		if slot.live || slot.generation == max(u32) {
			continue
		}
		generation := slot.generation + 1
		slot = Node_Slot{live = true, generation = generation}
		return Node_Ref{slot = u16(index), generation = generation}, true
	}
	return {}, false
}

@(private)
clear_node :: proc(slot: ^Node_Slot) {
	generation := slot.generation
	slot^ = Node_Slot{generation = generation}
}

@(private)
replace_child :: proc(data: ^Registry_Data, parent_ref, old_child, new_child: Node_Ref) -> bool {
	parent := resolve_node(data, parent_ref)
	if parent == nil || parent.kind != .Partition {
		return false
	}
	if parent.first == old_child {
		parent.first = new_child
		return true
	}
	if parent.second == old_child {
		parent.second = new_child
		return true
	}
	return false
}

@(private)
decrement_subtree_depth :: proc(data: ^Registry_Data, ref: Node_Ref) -> bool {
	slot := resolve_node(data, ref)
	if slot == nil || slot.depth == 0 {
		return false
	}
	slot.depth -= 1
	if slot.kind == .Pane {
		return true
	}
	return decrement_subtree_depth(data, slot.first) && decrement_subtree_depth(data, slot.second)
}

@(private)
mru_promote :: proc(data: ^Registry_Data, ref: Node_Ref) {
	index := int(data.mru_count)
	for candidate, candidate_index in data.mru[:data.mru_count] {
		if candidate == ref {
			index = candidate_index
			break
		}
	}
	assert(index < int(data.mru_count))
	for index > 0 {
		data.mru[index] = data.mru[index - 1]
		index -= 1
	}
	data.mru[0] = ref
}

@(private)
mru_remove :: proc(data: ^Registry_Data, ref: Node_Ref) {
	write: int
	for candidate in data.mru[:data.mru_count] {
		if candidate != ref {
			data.mru[write] = candidate
			write += 1
		}
	}
	for index in write ..< int(data.mru_count) {
		data.mru[index] = {}
	}
	data.mru_count = u16(write)
}

@(private)
prepared_state_fits :: proc(data: ^Registry_Data) -> bool {
	return u64(size_of(Registry_Data)) <= data.policy.prepared_bytes
}

@(private)
prepared_state_copy :: proc(
	data: ^Registry_Data,
	operation: Operation,
) -> (proposed: ^Registry_Data, failure: Failure_Context) {
	if !prepared_state_fits(data) {
		return nil, prepared_failure(data, operation)
	}
	allocated, allocation_error := new(Registry_Data, data.allocator)
	if allocation_error != nil {
		return nil, prepared_failure(data, operation)
	}
	proposed = allocated
	proposed^ = data^
	return proposed, {}
}

@(private)
prepared_state_release :: proc(proposed: ^Registry_Data) {
	if proposed != nil {
		free(proposed, proposed.allocator)
	}
}

@(private)
prepared_failure :: proc(data: ^Registry_Data, operation: Operation) -> Failure_Context {
	failure := data_failure(data, operation, .Prepared_Memory_Limit)
	failure.maximum = data.policy.prepared_bytes
	failure.actual = u64(size_of(Registry_Data))
	return failure
}

@(private)
layout_view_failure :: proc(
	data: ^Registry_Data,
	operation: Operation,
	view_failure: view.Failure_Context,
) -> Failure_Context {
	failure := data_failure(data, operation, .View_Failure)
	failure.view_failure = view_failure
	return failure
}

@(private)
validate_layout_state :: proc(data: ^Registry_Data) -> bool {
	if data == nil || data.node_count == 0 || data.pane_count == 0 ||
	   data.node_count != data.pane_count + data.partition_count ||
	   data.mru_count != data.pane_count || !buffer_list_is_valid(data) ||
	   registry_history_bytes(data) > data.policy.total_history_bytes {
		return false
	}
	seen: [MAX_NODES]bool
	nodes: u16
	panes: u16
	partitions: u16
	if !validate_subtree(data, data.root, {}, 0, &seen, &nodes, &panes, &partitions) ||
	   nodes != data.node_count || panes != data.pane_count || partitions != data.partition_count {
		return false
	}
	active := resolve_node(data, data.active)
	if active == nil || active.kind != .Pane {
		return false
	}
	for candidate, index in data.mru[:data.mru_count] {
		slot := resolve_node(data, candidate)
		if slot == nil || slot.kind != .Pane {
			return false
		}
		for previous in data.mru[:index] {
			if previous == candidate {
				return false
			}
		}
	}
	return true
}

@(private)
validate_subtree :: proc(
	data: ^Registry_Data,
	ref: Node_Ref,
	parent: Node_Ref,
	depth: u16,
	seen: ^[MAX_NODES]bool,
	nodes, panes, partitions: ^u16,
) -> bool {
	slot := resolve_node(data, ref)
	if slot == nil || seen[int(ref.slot)] || slot.parent != parent || slot.depth != depth ||
	   slot.node_id == Node_ID(0) || depth > data.policy.partition_depth {
		return false
	}
	seen[int(ref.slot)] = true
	nodes^ += 1
	if slot.kind == .Pane {
		if slot.pane_id == Pane_ID(0) || slot.view.view_id == view.View_ID(0) ||
		   !pane_dedication_is_valid(slot.dedication) || !pane_history_is_valid(data, slot) {
			return false
		}
		panes^ += 1
		return true
	}
	if slot.kind != .Partition || slot.dedication != .None ||
	   (slot.arrangement != .Above_Below && slot.arrangement != .Left_Right) ||
	   slot.first_weight == 0 || slot.second_weight == 0 {
		return false
	}
	partitions^ += 1
	return validate_subtree(data, slot.first, ref, depth + 1, seen, nodes, panes, partitions) &&
	       validate_subtree(data, slot.second, ref, depth + 1, seen, nodes, panes, partitions)
}
