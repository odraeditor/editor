// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

import "../editor_session"
import "../view"

/* registry_init creates one single-pane layout from an existing live view. */
registry_init :: proc(
	registry: ^Registry,
	owner_id: Owner_ID,
	layout_id: Layout_ID,
	view_registry: ^view.Registry,
	root_view: view.View_Handle,
	geometry: Geometry_Request,
	policy := DEFAULT_POLICY,
	allocator := context.allocator,
	root_entry: editor_session.Entry_Handle = {},
) -> (ok: bool, failure: Failure_Context) {
	assert(registry != nil)
	registry^ = {}
	if owner_id == Owner_ID(0) {
		return false, Failure_Context{code = .Invalid_Owner, operation = .Initialize}
	}
	if layout_id == Layout_ID(0) || view_registry == nil {
		return false, Failure_Context{code = .Invalid_Layout, operation = .Initialize}
	}
	if !policy_is_valid(policy) || !geometry_request_is_valid(geometry) {
		return false, Failure_Context{code = .Invalid_Layout, operation = .Initialize}
	}
	if allocator.procedure == nil {
		return false, Failure_Context{code = .Persistent_Memory_Limit, operation = .Initialize}
	}
	view_state, view_ok, view_failure := view.snapshot(view_registry, root_view)
	if !view_ok {
		return false, Failure_Context {
			code = .View_Failure,
			operation = .Initialize,
			view_failure = view_failure,
		}
	}
	data, allocation_error := new(Registry_Data, allocator)
	if allocation_error != nil {
		return false, Failure_Context{code = .Persistent_Memory_Limit, operation = .Initialize}
	}
	root := Node_Ref{slot = 0, generation = 1}
	data.state = .Ready
	data.owner_id = owner_id
	data.layout_id = layout_id
	data.generation = Layout_Generation(1)
	data.next_node_id = Node_ID(2)
	data.next_pane_id = Pane_ID(2)
	data.root = root
	data.active = root
	data.mru_count = 1
	data.node_count = 1
	data.pane_count = 1
	data.view_registry = view_registry
	data.policy = policy
	data.geometry_request = geometry
	data.geometry_state = .Unmaterialized
	data.display_policy = DEFAULT_DISPLAY_POLICY
	data.display_policy_generation = Display_Policy_Generation(1)
	data.next_display_request_id = Display_Request_ID(1)
	data.next_hook_id = Hook_ID(1)
	data.next_deferred_sequence = Deferred_Sequence(1)
	data.storage_bytes = u64(size_of(Registry_Data))
	data.allocator = allocator
	data.mru[0] = root
	data.nodes[0] = Node_Slot {
		live = true,
		kind = .Pane,
		node_id = Node_ID(1),
		generation = 1,
		pane_id = Pane_ID(1),
		view = root_view,
		buffer_id = view_state.buffer_id,
		entry = root_entry,
	}
	if editor_session.entry_handle_is_valid(root_entry) {
		root_state := pane_buffer_state_from_view(root_entry, view_state)
		if !pane_buffer_state_is_valid(root_state) {
			free(data, allocator)
			return false, Failure_Context{code = .Invalid_Buffer_State, operation = .Initialize}
		}
		pane_history_touch(data, &data.nodes[0], root_state)
		buffer_list_touch(data, root_entry, view_state.buffer_id)
	}
	materialized, materialize_failure := geometry_materialize_data(
		data,
		geometry,
		.Operating,
		.Initialize,
		false,
	)
	if !materialized {
		free(data, allocator)
		return false, materialize_failure
	}
	registry.state = data
	return true, {}
}

/* registry_close releases layout-owned additional views and all layout storage. */
registry_close :: proc(registry: ^Registry) -> (ok: bool, failure: Failure_Context) {
	data := registry_data(registry)
	if data == nil || data.state != .Ready {
		return false, registry_failure(registry, .Teardown, .Invalid_Registry)
	}
	if data.notifying || data.processing_deferred {
		return false, registry_failure(registry, .Teardown, .Busy)
	}
	for &slot in data.nodes {
		if !slot.live || slot.kind != .Pane {
			continue
		}
		state, state_ok, state_failure := view.snapshot(data.view_registry, slot.view)
		if !state_ok {
			if state_failure.code == .Stale_View {
				continue
			}
			failure = registry_failure(registry, .Teardown, .View_Failure)
			failure.view_failure = state_failure
			return false, failure
		}
		if state.presentation_ownership != .Additional {
			continue
		}
		closable, close_failure := view.validate_close(data.view_registry, slot.view)
		if !closable {
			failure = registry_failure(registry, .Teardown, .View_Failure)
			failure.view_failure = close_failure
			return false, failure
		}
	}
	for &slot in data.nodes {
		if !slot.live || slot.kind != .Pane {
			continue
		}
		state, state_ok, state_failure := view.snapshot(data.view_registry, slot.view)
		if !state_ok {
			if state_failure.code == .Stale_View {
				continue
			}
			failure = registry_failure(registry, .Teardown, .View_Failure)
			failure.view_failure = state_failure
			return false, failure
		}
		if state.presentation_ownership == .Additional {
			handle := slot.view
			closed, close_failure := view.close(data.view_registry, &handle)
			if !closed {
				failure = registry_failure(registry, .Teardown, .View_Failure)
				failure.view_failure = close_failure
				return false, failure
			}
		}
	}
	data.state = .Closed
	allocator := data.allocator
	free(data, allocator)
	registry^ = Registry{closed = true}
	return true, {}
}

/* registry_handle returns the exact current layout generation. */
registry_handle :: proc(registry: ^Registry) -> (handle: Layout_Handle, ok: bool, failure: Failure_Context) {
	data := registry_data(registry)
	if data == nil || data.state != .Ready {
		return {}, false, registry_failure(registry, .Inspect, .Invalid_Registry)
	}
	return current_layout_handle(data), true, {}
}

/* registry_stats returns exact live occupancy and retained registry bytes. */
registry_stats :: proc(registry: ^Registry) -> (stats: Registry_Stats, ok: bool, failure: Failure_Context) {
	data := registry_data(registry)
	if data == nil || data.state != .Ready {
		return {}, false, registry_failure(registry, .Inspect, .Invalid_Registry)
	}
	soft_dedicated_panes, hard_dedicated_panes := registry_dedication_counts(data)
	return Registry_Stats {
		handle = current_layout_handle(data),
		node_count = data.node_count,
		pane_count = data.pane_count,
		partition_count = data.partition_count,
		storage_bytes = data.storage_bytes,
		geometry_work = data.geometry_work,
		history_entries = registry_history_entry_count(data),
		history_bytes = registry_history_bytes(data),
		buffer_list_entries = data.buffer_list_count,
		display_policy_generation = data.display_policy_generation,
		display_policy_actions = data.display_policy.action_count,
		soft_dedicated_panes = soft_dedicated_panes,
		hard_dedicated_panes = hard_dedicated_panes,
		hooks = data.hook_count,
		deferred_requests = data.deferred_count,
		notification_rounds = data.notification_rounds,
		callback_failures = data.callback_failures,
		deferred_failures = data.deferred_failures,
	}, true, {}
}

/* registry_snapshot copies the complete current tree in spatial preorder. */
registry_snapshot :: proc(
	registry: ^Registry,
	expected: Layout_Handle,
) -> (snapshot: Snapshot, ok: bool, failure: Failure_Context) {
	ok, failure = registry_snapshot_into(registry, expected, &snapshot)
	return
}

/* registry_snapshot_into copies the current tree into caller-owned storage. */
registry_snapshot_into :: proc(
	registry: ^Registry,
	expected: Layout_Handle,
	snapshot: ^Snapshot,
) -> (ok: bool, failure: Failure_Context) {
	if snapshot == nil {
		return false, registry_failure(registry, .Inspect, .Invalid_Registry)
	}
	data, resolved := resolve_layout(registry, expected, .Inspect)
	if resolved.code != .None {
		return false, resolved
	}
	if data.node_count > data.policy.snapshot_nodes ||
	   u64(size_of(Snapshot)) > data.policy.snapshot_bytes {
		failure = registry_failure(registry, .Inspect, .Snapshot_Limit)
		failure.maximum = min(u64(data.policy.snapshot_nodes), data.policy.snapshot_bytes)
		failure.actual = max(u64(data.node_count), u64(size_of(Snapshot)))
		return false, failure
	}
	snapshot.handle = current_layout_handle(data)
	snapshot.geometry_state = data.geometry_state
	snapshot.geometry_request = data.geometry_request
	snapshot.root_id = resolve_node(data, data.root)^.node_id
	snapshot.node_count = data.node_count
	snapshot.pane_count = data.pane_count
	snapshot.partition_count = data.partition_count
	snapshot.geometry_work = data.geometry_work
	snapshot.active_pane = pane_handle(data, data.active)
	index: int
	copy_snapshot_node(data, data.root, snapshot, &index)
	if index != int(data.node_count) {
		return false, registry_failure(registry, .Inspect, .Invalid_Topology)
	}
	return true, {}
}

@(private)
copy_snapshot_node :: proc(data: ^Registry_Data, ref: Node_Ref, snapshot: ^Snapshot, index: ^int) {
	slot := resolve_node(data, ref)
	assert(slot != nil && index^ < MAX_SNAPSHOT_NODES)
	descriptor := &snapshot.nodes[index^]
	index^ += 1
	descriptor.kind = slot.kind
	descriptor.node_id = slot.node_id
	descriptor.slot_generation = slot.generation
	descriptor.depth = slot.depth
	descriptor.arrangement = slot.arrangement
	descriptor.first_weight = slot.first_weight
	descriptor.second_weight = slot.second_weight
	descriptor.view = slot.view
	descriptor.buffer_id = slot.buffer_id
	descriptor.entry = slot.entry
	descriptor.dedication = slot.dedication
	descriptor.history_count = slot.history_count
	descriptor.history_generation = slot.history_generation
	descriptor.geometry = slot.geometry
	if parent := resolve_node(data, slot.parent); parent != nil {
		descriptor.parent_id = parent.node_id
	}
	if slot.kind == .Partition {
		descriptor.first_child_id = resolve_node(data, slot.first)^.node_id
		descriptor.second_child_id = resolve_node(data, slot.second)^.node_id
		copy_snapshot_node(data, slot.first, snapshot, index)
		copy_snapshot_node(data, slot.second, snapshot, index)
		return
	}
	descriptor.pane = pane_handle(data, ref)
	descriptor.active = ref == data.active
	descriptor.mru_rank = mru_rank(data, ref)
}

@(private)
mru_rank :: proc(data: ^Registry_Data, ref: Node_Ref) -> u16 {
	for candidate, index in data.mru[:data.mru_count] {
		if candidate == ref {
			return u16(index)
		}
	}
	return max(u16)
}

@(private)
policy_is_valid :: proc(policy: Policy) -> bool {
	return policy.live_panes > 0 && policy.live_panes <= MAX_LIVE_PANES &&
	       policy.partition_depth > 0 && policy.partition_depth <= MAX_PARTITION_DEPTH &&
	       policy.operating_content_rows >= SEMANTIC_CONTENT_ROWS &&
	       policy.operating_columns >= SEMANTIC_COLUMNS &&
	       policy.snapshot_nodes > 0 && policy.snapshot_nodes <= MAX_SNAPSHOT_NODES &&
	       policy.snapshot_bytes >= u64(size_of(Snapshot)) &&
	       policy.snapshot_bytes <= MAX_SNAPSHOT_BYTES &&
	       policy.prepared_bytes > 0 && policy.prepared_bytes <= MAX_PREPARED_TRANSACTION_BYTES &&
	       policy.geometry_work > 0 && policy.geometry_work <= MAX_GEOMETRY_WORK &&
	       policy.pane_history_entries > 0 && policy.pane_history_entries <= MAX_PANE_HISTORY_ENTRIES &&
	       policy.pane_history_bytes >= u64(policy.pane_history_entries) * u64(size_of(Pane_History_Entry)) &&
	       policy.pane_history_bytes <= MAX_PANE_HISTORY_BYTES &&
	       policy.total_history_bytes >= policy.pane_history_bytes * u64(policy.live_panes) &&
	       policy.total_history_bytes <= MAX_TOTAL_PANE_HISTORY_BYTES &&
	       policy.top_level_buffers > 0 && policy.top_level_buffers <= MAX_TOP_LEVEL_BUFFERS &&
	       policy.layout_hooks > 0 && policy.layout_hooks <= MAX_LAYOUT_HOOKS &&
	       policy.deferred_requests > 0 && policy.deferred_requests <= MAX_DEFERRED_REQUESTS
}

@(private)
geometry_request_is_valid :: proc(request: Geometry_Request) -> bool {
	return request.rows > 0 && request.columns > 0 &&
	       request.global_reserved_rows >= 0 && request.global_reserved_columns >= 0 &&
	       request.global_reserved_rows <= request.rows &&
	       request.global_reserved_columns <= request.columns
}

@(private)
current_layout_handle :: proc(data: ^Registry_Data) -> Layout_Handle {
	return Layout_Handle {
		owner_id = data.owner_id,
		layout_id = data.layout_id,
		generation = data.generation,
	}
}

@(private)
pane_handle :: proc(data: ^Registry_Data, ref: Node_Ref) -> Pane_Handle {
	slot := resolve_node(data, ref)
	assert(slot != nil && slot.kind == .Pane)
	return Pane_Handle {
		layout = current_layout_handle(data),
		pane_id = slot.pane_id,
		slot = ref.slot,
		slot_generation = ref.generation,
	}
}

@(private)
resolve_layout :: proc(
	registry: ^Registry,
	expected: Layout_Handle,
	operation: Operation,
) -> (data: ^Registry_Data, failure: Failure_Context) {
	data = registry_data(registry)
	if data == nil || data.state != .Ready {
		return nil, registry_failure(registry, operation, .Invalid_Registry)
	}
	if expected.owner_id != data.owner_id {
		return nil, registry_failure(registry, operation, .Wrong_Owner)
	}
	if expected.layout_id != data.layout_id || expected.layout_id == Layout_ID(0) {
		return nil, registry_failure(registry, operation, .Invalid_Layout)
	}
	if expected.generation != data.generation {
		return nil, registry_failure(registry, operation, .Stale_Layout)
	}
	if data.notifying && operation_is_mutation(operation) {
		return nil, registry_failure(registry, operation, .Busy)
	}
	return data, {}
}

@(private)
operation_is_mutation :: proc(operation: Operation) -> bool {
	switch operation {
	case .Materialize, .Split, .Resize, .Balance_Dimensions, .Balance_Areas,
	     .Focus, .Close, .Keep_Only, .Replace_Buffer, .Kill_Buffer,
	     .Record_History, .Purge_History, .Set_Dedication,
	     .Configure_Display_Policy, .Request_Display, .Display_Buffer:
		return true
	case .Invalid, .Initialize, .Inspect, .Inspect_Dedication, .Inspect_Display_Policy,
	     .Propose_Display, .Register_Hook, .Release_Hook, .Defer_Mutation,
	     .Notify_Hooks, .Teardown:
		return false
	}
	return false
}

@(private)
resolve_pane :: proc(
	data: ^Registry_Data,
	handle: Pane_Handle,
	operation: Operation,
) -> (slot: ^Node_Slot, ref: Node_Ref, failure: Failure_Context) {
	if handle.layout.owner_id != data.owner_id {
		return nil, {}, data_failure(data, operation, .Wrong_Owner)
	}
	if handle.layout.layout_id != data.layout_id || handle.pane_id == Pane_ID(0) ||
	   int(handle.slot) >= MAX_NODES {
		return nil, {}, data_failure(data, operation, .Invalid_Pane)
	}
	if handle.layout.generation != data.generation {
		return nil, {}, data_failure(data, operation, .Stale_Layout)
	}
	ref = Node_Ref{slot = handle.slot, generation = handle.slot_generation}
	slot = resolve_node(data, ref)
	if slot == nil || slot.kind != .Pane || slot.pane_id != handle.pane_id {
		failure = data_failure(data, operation, .Stale_Pane)
		failure.pane = handle
		return nil, {}, failure
	}
	return slot, ref, {}
}

@(private)
resolve_node :: proc(data: ^Registry_Data, ref: Node_Ref) -> ^Node_Slot {
	if data == nil || ref.generation == 0 || int(ref.slot) >= MAX_NODES {
		return nil
	}
	slot := &data.nodes[int(ref.slot)]
	if !slot.live || slot.generation != ref.generation {
		return nil
	}
	return slot
}

@(private)
registry_data :: proc(registry: ^Registry) -> ^Registry_Data {
	if registry == nil || registry.state == nil {
		return nil
	}
	return (^Registry_Data)(registry.state)
}

@(private)
registry_failure :: proc(registry: ^Registry, operation: Operation, code: Failure_Code) -> Failure_Context {
	data := registry_data(registry)
	if data == nil {
		return Failure_Context{code = code, operation = operation}
	}
	return data_failure(data, operation, code)
}

@(private)
data_failure :: proc(data: ^Registry_Data, operation: Operation, code: Failure_Code) -> Failure_Context {
	return Failure_Context {
		code = code,
		operation = operation,
		layout = current_layout_handle(data),
	}
}
