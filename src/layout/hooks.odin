// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

/* registry_hook_register retains one bounded callback without changing layout generation. */
registry_hook_register :: proc(
	registry: ^Registry,
	procedure: Hook_Procedure,
	user_data: rawptr = nil,
) -> (handle: Hook_Handle, ok: bool, failure: Failure_Context) {
	data := registry_data(registry)
	if data == nil || data.state != .Ready || procedure == nil {
		return {}, false, registry_failure(registry, .Register_Hook, .Invalid_Hook)
	}
	if data.notifying || data.processing_deferred {
		return {}, false, data_failure(data, .Register_Hook, .Busy)
	}
	if data.hook_count >= data.policy.layout_hooks || data.hook_count >= MAX_LAYOUT_HOOKS {
		failure = data_failure(data, .Register_Hook, .Hook_Limit)
		failure.maximum = u64(data.policy.layout_hooks)
		failure.actual = u64(data.hook_count) + 1
		return {}, false, failure
	}
	if data.next_hook_id == Hook_ID(0) || data.next_hook_id == Hook_ID(max(u64)) {
		return {}, false, data_failure(data, .Register_Hook, .Generation_Limit)
	}
	for &slot, index in data.hooks {
		if slot.live || slot.generation == max(u32) {
			continue
		}
		slot.live = true
		slot.hook_id = data.next_hook_id
		slot.generation += 1
		slot.procedure = procedure
		slot.user_data = user_data
		data.next_hook_id = Hook_ID(u64(data.next_hook_id) + 1)
		data.hook_count += 1
		return hook_handle(data, u16(index)), true, {}
	}
	failure = data_failure(data, .Register_Hook, .Hook_Limit)
	failure.maximum = u64(data.policy.layout_hooks)
	failure.actual = u64(data.hook_count) + 1
	return {}, false, failure
}

/* registry_hook_release removes one exact callback identity. */
registry_hook_release :: proc(
	registry: ^Registry,
	handle: ^Hook_Handle,
) -> (ok: bool, failure: Failure_Context) {
	data := registry_data(registry)
	if data == nil || data.state != .Ready || handle == nil {
		return false, registry_failure(registry, .Release_Hook, .Invalid_Hook)
	}
	if data.notifying || data.processing_deferred {
		return false, data_failure(data, .Release_Hook, .Busy)
	}
	slot, resolved := resolve_hook(data, handle^)
	if resolved.code != .None {
		return false, resolved
	}
	slot.live = false
	slot.hook_id = 0
	slot.procedure = nil
	slot.user_data = nil
	data.hook_count -= 1
	handle^ = {}
	return true, {}
}

/* registry_hook_stats returns exact hook and deferred-queue accounting. */
registry_hook_stats :: proc(
	registry: ^Registry,
) -> (stats: Hook_Stats, ok: bool, failure: Failure_Context) {
	data := registry_data(registry)
	if data == nil || data.state != .Ready {
		return {}, false, registry_failure(registry, .Inspect, .Invalid_Registry)
	}
	return Hook_Stats {
		hooks = data.hook_count,
		deferred = data.deferred_count,
		notifying = data.notifying,
		processing_deferred = data.processing_deferred,
		notification_rounds = data.notification_rounds,
		callback_calls = data.callback_calls,
		callback_failures = data.callback_failures,
		deferred_enqueued = data.deferred_enqueued,
		deferred_processed = data.deferred_processed,
		deferred_failures = data.deferred_failures,
	}, true, {}
}

/* registry_hook_failures copies the last contained callback and deferred failures. */
registry_hook_failures :: proc(
	registry: ^Registry,
) -> (callback, deferred: Failure_Context, ok: bool) {
	data := registry_data(registry)
	if data == nil || data.state != .Ready {
		return {}, {}, false
	}
	return data.last_hook_failure, data.last_deferred_failure, true
}

/* registry_defer_request copies one callback request into the bounded FIFO. */
registry_defer_request :: proc(
	ctx: ^Hook_Callback_Context,
	request: Deferred_Request,
) -> (sequence: Deferred_Sequence, ok: bool, failure: Failure_Context) {
	if ctx == nil || ctx.registry == nil {
		return 0, false, Failure_Context {
			code = .Invalid_Hook,
			operation = .Defer_Mutation,
		}
	}
	data := registry_data(ctx.registry)
	if data == nil || data.state != .Ready || !data.notifying ||
	   data.notification_snapshot == nil {
		return 0, false, registry_failure(ctx.registry, .Defer_Mutation, .Busy)
	}
	_, hook_failure := resolve_hook(data, ctx.hook)
	if hook_failure.code != .None {
		return 0, false, hook_failure
	}
	if !deferred_request_is_valid(data.notification_snapshot, request) {
		failure = data_failure(data, .Defer_Mutation, .Invalid_Deferred_Request)
		failure.pane = request.pane
		return 0, false, failure
	}
	if data.deferred_count >= data.policy.deferred_requests ||
	   data.deferred_count >= MAX_DEFERRED_REQUESTS {
		failure = data_failure(data, .Defer_Mutation, .Deferred_Limit)
		failure.maximum = u64(data.policy.deferred_requests)
		failure.actual = u64(data.deferred_count) + 1
		return 0, false, failure
	}
	if data.next_deferred_sequence == Deferred_Sequence(0) ||
	   data.next_deferred_sequence == Deferred_Sequence(max(u64)) {
		return 0, false, data_failure(data, .Defer_Mutation, .Generation_Limit)
	}
	queued := request
	queued.sequence = data.next_deferred_sequence
	data.next_deferred_sequence = Deferred_Sequence(u64(data.next_deferred_sequence) + 1)
	data.deferred[int(data.deferred_count)] = queued
	data.deferred_count += 1
	data.deferred_enqueued += 1
	return queued.sequence, true, {}
}

@(private)
registry_publish :: proc(registry: ^Registry, proposed: ^Registry_Data) {
	assert(registry != nil && proposed != nil)
	data := registry_data(registry)
	assert(data != nil && data.state == .Ready)
	data^ = proposed^
	registry_notify_publication(registry)
}

@(private)
registry_notify_publication :: proc(registry: ^Registry) {
	data := registry_data(registry)
	assert(data != nil && data.state == .Ready && !data.notifying)
	if data.hook_count == 0 {
		if !data.processing_deferred && data.deferred_count > 0 {
			registry_process_deferred(registry)
		}
		return
	}
	handle := current_layout_handle(data)
	snapshot, allocation_error := new(Snapshot, data.allocator)
	if allocation_error != nil {
		data.callback_failures += 1
		data.last_hook_failure = data_failure(data, .Notify_Hooks, .Persistent_Memory_Limit)
		return
	}
	defer free(snapshot, data.allocator)
	copied, snapshot_failure := registry_snapshot_into(registry, handle, snapshot)
	if !copied {
		data.callback_failures += 1
		data.last_hook_failure = snapshot_failure
		return
	}
	data.notifying = true
	data.notification_snapshot = snapshot
	data.notification_rounds += 1
	for &slot, index in data.hooks {
		if !slot.live || slot.procedure == nil {
			continue
		}
		handle := hook_handle(data, u16(index))
		callback_context := Hook_Callback_Context{registry = registry, hook = handle}
		data.callback_calls += 1
		if !slot.procedure(slot.user_data, handle, snapshot, &callback_context) {
			data.callback_failures += 1
			data.last_hook_failure = Failure_Context {
				code = .Callback_Failure,
				operation = .Notify_Hooks,
				layout = snapshot.handle,
				hook = handle,
			}
		}
	}
	data.notification_snapshot = nil
	data.notifying = false
	if !data.processing_deferred && data.deferred_count > 0 {
		registry_process_deferred(registry)
	}
}

@(private)
registry_process_deferred :: proc(registry: ^Registry) {
	data := registry_data(registry)
	assert(data != nil && !data.notifying && !data.processing_deferred)
	data.processing_deferred = true
	defer {
		current := registry_data(registry)
		if current != nil {
			current.processing_deferred = false
		}
	}
	for data.deferred_count > 0 {
		request := data.deferred[0]
		for index in 1 ..< int(data.deferred_count) {
			data.deferred[index - 1] = data.deferred[index]
		}
		data.deferred[int(data.deferred_count) - 1] = {}
		data.deferred_count -= 1
		data.deferred_processed += 1
		applied, apply_failure := registry_apply_deferred(registry, request)
		data = registry_data(registry)
		if !applied {
			data.deferred_failures += 1
			apply_failure.deferred_sequence = request.sequence
			data.last_deferred_failure = apply_failure
		}
	}
}

@(private)
registry_apply_deferred :: proc(
	registry: ^Registry,
	request: Deferred_Request,
) -> (ok: bool, failure: Failure_Context) {
	switch request.operation {
	case .Split_Below:
		_, ok, failure = registry_split_below(registry, request.pane)
	case .Split_Right:
		_, ok, failure = registry_split_right(registry, request.pane)
	case .Focus:
		_, ok, failure = registry_focus(registry, request.pane)
	case .Close:
		_, ok, failure = registry_close_pane(registry, request.pane)
	case .Keep_Only:
		_, ok, failure = registry_keep_only(registry, request.pane)
	case .Resize:
		_, ok, failure = registry_resize_pane(
			registry, request.pane, request.arrangement, request.delta,
		)
	case .Balance_Dimensions:
		_, ok, failure = registry_balance_panes(registry, request.expected)
	case .Balance_Areas:
		_, ok, failure = registry_balance_pane_areas(registry, request.expected)
	case .Set_Dedication:
		_, ok, failure = registry_pane_dedication_set(
			registry, request.pane, request.dedication,
		)
	case .Invalid:
		return false, Failure_Context {
			code = .Invalid_Deferred_Request,
			operation = .Defer_Mutation,
		}
	}
	return ok, failure
}

@(private)
deferred_request_is_valid :: proc(snapshot: ^Snapshot, request: Deferred_Request) -> bool {
	if snapshot == nil || request.sequence != Deferred_Sequence(0) ||
	   request.expected != snapshot.handle || request.pane.layout != snapshot.handle {
		return false
	}
	pane_found := false
	for index in 0 ..< int(snapshot.node_count) {
		node := snapshot.nodes[index]
		if node.kind == .Pane && node.pane == request.pane {
			pane_found = true
			break
		}
	}
	if !pane_found {
		return false
	}
	switch request.operation {
	case .Split_Below, .Split_Right, .Focus, .Close, .Keep_Only,
	     .Balance_Dimensions, .Balance_Areas:
		return true
	case .Resize:
		return (request.arrangement == .Above_Below || request.arrangement == .Left_Right) &&
		       (request.delta == -1 || request.delta == 1)
	case .Set_Dedication:
		return pane_dedication_is_valid(request.dedication)
	case .Invalid:
		return false
	}
	return false
}

@(private)
hook_handle :: proc(data: ^Registry_Data, index: u16) -> Hook_Handle {
	slot := &data.hooks[int(index)]
	assert(slot.live)
	return Hook_Handle {
		owner_id = data.owner_id,
		layout_id = data.layout_id,
		hook_id = slot.hook_id,
		slot = index,
		slot_generation = slot.generation,
	}
}

@(private)
resolve_hook :: proc(
	data: ^Registry_Data,
	handle: Hook_Handle,
) -> (slot: ^Hook_Slot, failure: Failure_Context) {
	if data == nil || handle.owner_id != data.owner_id || handle.layout_id != data.layout_id ||
	   handle.hook_id == Hook_ID(0) || int(handle.slot) >= MAX_LAYOUT_HOOKS {
		failure = data_failure(data, .Inspect, .Invalid_Hook)
		failure.hook = handle
		return nil, failure
	}
	slot = &data.hooks[int(handle.slot)]
	if !slot.live || slot.hook_id != handle.hook_id || slot.generation != handle.slot_generation {
		failure = data_failure(data, .Inspect, .Stale_Hook)
		failure.hook = handle
		return nil, failure
	}
	return slot, {}
}
