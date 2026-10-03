// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../history"
import "core:os"

@(private)
HISTORY_POLICY_SLOT_BITS :: 16
@(private)
HISTORY_POLICY_GENERATION_BITS :: 32
@(private)
HISTORY_POLICY_SLOT_MASK :: u64(0xffff)
@(private)
HISTORY_POLICY_GENERATION_MASK :: u64(0xffff_ffff)

/* history_policy_capability_registry_init initializes one fixed-capacity registry. */
history_policy_capability_registry_init :: proc(
	registry: ^History_Policy_Capability_Registry,
	registry_id: Registry_ID,
) -> (ok: bool, failure: Failure_Context) {
	assert(registry != nil)
	if registry.state != .Uninitialized || registry_id == Registry_ID(0) {
		return false, Failure_Context{code = .Invalid_Registry, registry_id = registry_id}
	}
	registry.state = .Ready
	registry.registry_id = registry_id
	return true, {}
}

/* history_policy_capability_registry_close closes an empty policy registry. */
history_policy_capability_registry_close :: proc(
	registry: ^History_Policy_Capability_Registry,
) -> (ok: bool, failure: Failure_Context) {
	assert(registry != nil)
	if registry.state != .Ready {
		return false, history_policy_registry_failure(registry, .Invalid_Registry)
	}
	if registry.live_count != 0 {
		failure = history_policy_registry_failure(registry, .Retained_Capabilities)
		failure.actual = u64(registry.live_count)
		return false, failure
	}
	registry.state = .Closed
	return true, {}
}

/* history_policy_capability_acquire binds one live store to the current owner thread. */
history_policy_capability_acquire :: proc(
	registry: ^History_Policy_Capability_Registry,
	store: ^history.Store,
) -> (
	capability: History_Policy_Capability,
	snapshot: history.Policy_Snapshot,
	ok: bool,
	failure: Failure_Context,
) {
	assert(registry != nil)
	if registry.state != .Ready {
		return {}, {}, false, history_policy_registry_failure(registry, .Invalid_Registry)
	}
	inspected, inspected_ok, history_failure := history.store_policy_inspect(store)
	if !inspected_ok {
		return {}, {}, false, history_policy_failure(registry, {}, history_failure)
	}
	stats, stats_ok, stats_failure := history.store_stats(store)
	if !stats_ok {
		return {}, {}, false, history_policy_failure(registry, {}, stats_failure)
	}
	for &slot, slot_index in registry.slots {
		if slot.live || slot.generation == max(u32) {
			continue
		}
		slot.generation += 1
		slot.store = store
		slot.store_id = stats.store_id
		slot.owner_thread_id = os.get_current_thread_id()
		slot.live = true
		registry.live_count += 1
		return history_policy_capability_encode(
			registry.registry_id,
			slot.generation,
			u16(slot_index),
		), inspected, true, {}
	}
	failure = history_policy_registry_failure(registry, .Capacity_Limit)
	failure.limit = MAX_HISTORY_POLICY_CAPABILITIES
	failure.actual = u64(registry.live_count) + 1
	return {}, {}, false, failure
}

/* history_policy_capability_release clears one exact-generation native authority. */
history_policy_capability_release :: proc(
	registry: ^History_Policy_Capability_Registry,
	capability: ^History_Policy_Capability,
) -> (ok: bool, failure: Failure_Context) {
	assert(registry != nil)
	assert(capability != nil)
	slot, resolve_failure := history_policy_capability_resolve(registry, capability^)
	if resolve_failure.code != .None {
		return false, resolve_failure
	}
	if slot.call_active {
		return false, history_policy_capability_failure(registry, capability^, .Reentrant_Call)
	}
	slot.store = nil
	slot.store_id = {}
	slot.owner_thread_id = 0
	slot.live = false
	assert(registry.live_count > 0)
	registry.live_count -= 1
	capability^ = {}
	return true, {}
}

/* history_policy_capability_inspect copies one complete live policy generation. */
history_policy_capability_inspect :: proc(
	registry: ^History_Policy_Capability_Registry,
	capability: History_Policy_Capability,
) -> (snapshot: history.Policy_Snapshot, ok: bool, failure: Failure_Context) {
	slot, entry_failure := history_policy_capability_enter(registry, capability)
	if entry_failure.code != .None {
		return {}, false, entry_failure
	}
	defer history_policy_capability_leave(slot)
	history_failure: history.Failure_Context
	snapshot, ok, history_failure = history.store_policy_inspect(slot.store)
	if !ok {
		return {}, false, history_policy_failure(registry, capability, history_failure)
	}
	return snapshot, true, {}
}

/* history_policy_capability_replace validates and atomically applies one copied request. */
history_policy_capability_replace :: proc(
	registry: ^History_Policy_Capability_Registry,
	capability: History_Policy_Capability,
	request: history.Policy_Replacement_Request,
) -> (result: history.Policy_Replacement_Result, ok: bool, failure: Failure_Context) {
	slot, entry_failure := history_policy_capability_enter(registry, capability)
	if entry_failure.code != .None {
		return {}, false, entry_failure
	}
	defer history_policy_capability_leave(slot)
	history_failure: history.Failure_Context
	result, ok, history_failure = history.store_policy_replace(slot.store, request)
	if !ok {
		return {}, false, history_policy_failure(registry, capability, history_failure)
	}
	return result, true, {}
}

@(private)
history_policy_capability_enter :: proc(
	registry: ^History_Policy_Capability_Registry,
	capability: History_Policy_Capability,
) -> (^History_Policy_Capability_Slot, Failure_Context) {
	slot, failure := history_policy_capability_resolve(registry, capability)
	if failure.code != .None {
		return nil, failure
	}
	if slot.call_active {
		return nil, history_policy_capability_failure(registry, capability, .Reentrant_Call)
	}
	slot.call_active = true
	return slot, {}
}

@(private)
history_policy_capability_leave :: proc(slot: ^History_Policy_Capability_Slot) {
	assert(slot != nil && slot.call_active)
	slot.call_active = false
}

@(private)
history_policy_capability_resolve :: proc(
	registry: ^History_Policy_Capability_Registry,
	capability: History_Policy_Capability,
) -> (slot: ^History_Policy_Capability_Slot, failure: Failure_Context) {
	if registry == nil || registry.state != .Ready {
		return nil, history_policy_registry_failure(registry, .Invalid_Registry)
	}
	value := u64(capability)
	registry_id := Registry_ID(value >> (HISTORY_POLICY_GENERATION_BITS + HISTORY_POLICY_SLOT_BITS))
	slot_number := value & HISTORY_POLICY_SLOT_MASK
	generation := u32((value >> HISTORY_POLICY_SLOT_BITS) & HISTORY_POLICY_GENERATION_MASK)
	if value == 0 || registry_id != registry.registry_id || slot_number == 0 ||
	   slot_number > MAX_HISTORY_POLICY_CAPABILITIES || generation == 0 {
		return nil, history_policy_capability_failure(registry, capability, .Invalid_Capability)
	}
	slot = &registry.slots[int(slot_number - 1)]
	if !slot.live || slot.generation != generation {
		return nil, history_policy_capability_failure(registry, capability, .Stale_Capability)
	}
	if os.get_current_thread_id() != slot.owner_thread_id {
		return nil, history_policy_capability_failure(registry, capability, .Wrong_Thread)
	}
	if !history.store_is_valid(slot.store) {
		return nil, history_policy_capability_failure(registry, capability, .Stale_Capability)
	}
	stats, stats_ok, history_failure := history.store_stats(slot.store)
	if !stats_ok || stats.store_id != slot.store_id {
		if !stats_ok {
			return nil, history_policy_failure(registry, capability, history_failure)
		}
		return nil, history_policy_capability_failure(registry, capability, .Stale_Capability)
	}
	return slot, {}
}

@(private)
history_policy_capability_encode :: proc(
	registry_id: Registry_ID,
	generation: u32,
	slot_index: u16,
) -> History_Policy_Capability {
	value := u64(registry_id) << (HISTORY_POLICY_GENERATION_BITS + HISTORY_POLICY_SLOT_BITS)
	value |= u64(generation) << HISTORY_POLICY_SLOT_BITS
	value |= u64(slot_index) + 1
	return History_Policy_Capability(value)
}

@(private)
history_policy_registry_failure :: proc(
	registry: ^History_Policy_Capability_Registry,
	code: Failure_Code,
) -> Failure_Context {
	registry_id: Registry_ID
	if registry != nil {
		registry_id = registry.registry_id
	}
	return Failure_Context{code = code, registry_id = registry_id}
}

@(private)
history_policy_capability_failure :: proc(
	registry: ^History_Policy_Capability_Registry,
	capability: History_Policy_Capability,
	code: Failure_Code,
) -> Failure_Context {
	result := history_policy_registry_failure(registry, code)
	result.history_capability = capability
	return result
}

@(private)
history_policy_failure :: proc(
	registry: ^History_Policy_Capability_Registry,
	capability: History_Policy_Capability,
	failure: history.Failure_Context,
) -> Failure_Context {
	code := Failure_Code.History_Failure
	#partial switch failure.code {
	case .Stale_Generation:
		code = .Stale_Generation
	case .Policy_Range:
		code = .Policy_Range
	case .Policy_Relationship:
		code = .Policy_Relationship
	case .Policy_Retention_Blocked:
		code = .Retention_Blocked
	case .Temporary_Memory_Limit:
		code = .Temporary_Memory_Limit
	case .Cancelled:
		code = .Cancelled
	}
	result := history_policy_capability_failure(registry, capability, code)
	result.history_code = failure.code
	result.policy_field = failure.field
	result.policy_generation = failure.policy_generation
	result.minimum = failure.minimum
	result.limit = failure.maximum
	result.actual = failure.actual
	return result
}
