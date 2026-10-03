// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../layout"
import "core:os"

@(private)
DISPLAY_POLICY_SLOT_BITS :: 16
@(private)
DISPLAY_POLICY_GENERATION_BITS :: 32
@(private)
DISPLAY_POLICY_SLOT_MASK :: u64(0xffff)
@(private)
DISPLAY_POLICY_GENERATION_MASK :: u64(0xffff_ffff)

/* display_policy_capability_registry_init initializes one fixed-capacity registry. */
display_policy_capability_registry_init :: proc(
	registry: ^Display_Policy_Capability_Registry,
	registry_id: Registry_ID,
) -> (ok: bool, failure: Failure_Context) {
	assert(registry != nil)
	if registry.state != .Uninitialized || registry_id == Registry_ID(0) {
		return false, display_policy_registry_failure(registry, .Invalid_Registry)
	}
	registry.state = .Ready
	registry.registry_id = registry_id
	return true, {}
}

/* display_policy_capability_registry_close closes an empty policy registry. */
display_policy_capability_registry_close :: proc(
	registry: ^Display_Policy_Capability_Registry,
) -> (ok: bool, failure: Failure_Context) {
	assert(registry != nil)
	if registry.state != .Ready {
		return false, display_policy_registry_failure(registry, .Invalid_Registry)
	}
	if registry.live_count != 0 {
		failure = display_policy_registry_failure(registry, .Retained_Capabilities)
		failure.actual = u64(registry.live_count)
		return false, failure
	}
	registry.state = .Closed
	return true, {}
}

/* display_policy_capability_acquire binds one live layout to the current owner thread. */
display_policy_capability_acquire :: proc(
	registry: ^Display_Policy_Capability_Registry,
	layout_registry: ^layout.Registry,
) -> (
	capability: Display_Policy_Capability,
	snapshot: layout.Display_Policy_Snapshot,
	ok: bool,
	failure: Failure_Context,
) {
	assert(registry != nil)
	if registry.state != .Ready {
		return {}, {}, false, display_policy_registry_failure(registry, .Invalid_Registry)
	}
	handle, handled, layout_failure := layout.registry_handle(layout_registry)
	if !handled {
		return {}, {}, false, display_policy_failure(registry, {}, layout_failure)
	}
	inspected, inspected_ok, inspect_failure := layout.registry_display_policy_snapshot(
		layout_registry,
		handle,
	)
	if !inspected_ok {
		return {}, {}, false, display_policy_failure(registry, {}, inspect_failure)
	}
	for &slot, slot_index in registry.slots {
		if slot.live || slot.generation == max(u32) {
			continue
		}
		slot.generation += 1
		slot.registry = layout_registry
		slot.owner_id = handle.owner_id
		slot.layout_id = handle.layout_id
		slot.owner_thread_id = os.get_current_thread_id()
		slot.live = true
		registry.live_count += 1
		return display_policy_capability_encode(
			registry.registry_id,
			slot.generation,
			u16(slot_index),
		), inspected, true, {}
	}
	failure = display_policy_registry_failure(registry, .Capacity_Limit)
	failure.limit = MAX_DISPLAY_POLICY_CAPABILITIES
	failure.actual = u64(registry.live_count) + 1
	return {}, {}, false, failure
}

/* display_policy_capability_release clears one exact-generation native authority. */
display_policy_capability_release :: proc(
	registry: ^Display_Policy_Capability_Registry,
	capability: ^Display_Policy_Capability,
) -> (ok: bool, failure: Failure_Context) {
	assert(registry != nil)
	assert(capability != nil)
	slot, resolve_failure := display_policy_capability_resolve(registry, capability^)
	if resolve_failure.code != .None {
		return false, resolve_failure
	}
	if slot.call_active {
		return false, display_policy_capability_failure(registry, capability^, .Reentrant_Call)
	}
	slot.registry = nil
	slot.owner_id = {}
	slot.layout_id = {}
	slot.owner_thread_id = 0
	slot.live = false
	assert(registry.live_count > 0)
	registry.live_count -= 1
	capability^ = {}
	return true, {}
}

/* display_policy_capability_inspect copies one complete live policy generation. */
display_policy_capability_inspect :: proc(
	registry: ^Display_Policy_Capability_Registry,
	capability: Display_Policy_Capability,
) -> (snapshot: layout.Display_Policy_Snapshot, ok: bool, failure: Failure_Context) {
	slot, entry_failure := display_policy_capability_enter(registry, capability)
	if entry_failure.code != .None {
		return {}, false, entry_failure
	}
	defer display_policy_capability_leave(slot)
	handle, handled, layout_failure := layout.registry_handle(slot.registry)
	if !handled {
		return {}, false, display_policy_failure(registry, capability, layout_failure)
	}
	snapshot, ok, layout_failure = layout.registry_display_policy_snapshot(slot.registry, handle)
	if !ok {
		return {}, false, display_policy_failure(registry, capability, layout_failure)
	}
	return snapshot, true, {}
}

/* display_policy_capability_replace validates and atomically applies one copied request. */
display_policy_capability_replace :: proc(
	registry: ^Display_Policy_Capability_Registry,
	capability: Display_Policy_Capability,
	expected_generation: layout.Display_Policy_Generation,
	policy: layout.Display_Policy,
) -> (snapshot: layout.Display_Policy_Snapshot, ok: bool, failure: Failure_Context) {
	slot, entry_failure := display_policy_capability_enter(registry, capability)
	if entry_failure.code != .None {
		return {}, false, entry_failure
	}
	defer display_policy_capability_leave(slot)
	handle, handled, layout_failure := layout.registry_handle(slot.registry)
	if !handled {
		return {}, false, display_policy_failure(registry, capability, layout_failure)
	}
	snapshot, ok, layout_failure = layout.registry_display_policy_replace(
		slot.registry,
		layout.Display_Policy_Replacement_Request {
			layout = handle,
			expected_generation = expected_generation,
			policy = policy,
		},
	)
	if !ok {
		return {}, false, display_policy_failure(registry, capability, layout_failure)
	}
	return snapshot, true, {}
}

@(private)
display_policy_capability_enter :: proc(
	registry: ^Display_Policy_Capability_Registry,
	capability: Display_Policy_Capability,
) -> (^Display_Policy_Capability_Slot, Failure_Context) {
	slot, failure := display_policy_capability_resolve(registry, capability)
	if failure.code != .None {
		return nil, failure
	}
	if slot.call_active {
		return nil, display_policy_capability_failure(registry, capability, .Reentrant_Call)
	}
	slot.call_active = true
	return slot, {}
}

@(private)
display_policy_capability_leave :: proc(slot: ^Display_Policy_Capability_Slot) {
	assert(slot != nil && slot.call_active)
	slot.call_active = false
}

@(private)
display_policy_capability_resolve :: proc(
	registry: ^Display_Policy_Capability_Registry,
	capability: Display_Policy_Capability,
) -> (slot: ^Display_Policy_Capability_Slot, failure: Failure_Context) {
	if registry == nil || registry.state != .Ready {
		return nil, display_policy_registry_failure(registry, .Invalid_Registry)
	}
	value := u64(capability)
	registry_id := Registry_ID(value >> (DISPLAY_POLICY_GENERATION_BITS + DISPLAY_POLICY_SLOT_BITS))
	slot_number := value & DISPLAY_POLICY_SLOT_MASK
	generation := u32((value >> DISPLAY_POLICY_SLOT_BITS) & DISPLAY_POLICY_GENERATION_MASK)
	if value == 0 || registry_id != registry.registry_id || slot_number == 0 ||
	   slot_number > MAX_DISPLAY_POLICY_CAPABILITIES || generation == 0 {
		return nil, display_policy_capability_failure(registry, capability, .Invalid_Capability)
	}
	slot = &registry.slots[int(slot_number - 1)]
	if !slot.live || slot.generation != generation {
		return nil, display_policy_capability_failure(registry, capability, .Stale_Capability)
	}
	if os.get_current_thread_id() != slot.owner_thread_id {
		return nil, display_policy_capability_failure(registry, capability, .Wrong_Thread)
	}
	handle, handled, layout_failure := layout.registry_handle(slot.registry)
	if !handled {
		return nil, display_policy_failure(registry, capability, layout_failure)
	}
	if handle.owner_id != slot.owner_id || handle.layout_id != slot.layout_id {
		return nil, display_policy_capability_failure(registry, capability, .Stale_Capability)
	}
	return slot, {}
}

@(private)
display_policy_capability_encode :: proc(
	registry_id: Registry_ID,
	generation: u32,
	slot_index: u16,
) -> Display_Policy_Capability {
	value := u64(registry_id) << (DISPLAY_POLICY_GENERATION_BITS + DISPLAY_POLICY_SLOT_BITS)
	value |= u64(generation) << DISPLAY_POLICY_SLOT_BITS
	value |= u64(slot_index) + 1
	return Display_Policy_Capability(value)
}

@(private)
display_policy_registry_failure :: proc(
	registry: ^Display_Policy_Capability_Registry,
	code: Failure_Code,
) -> Failure_Context {
	registry_id: Registry_ID
	if registry != nil {
		registry_id = registry.registry_id
	}
	return Failure_Context{code = code, registry_id = registry_id}
}

@(private)
display_policy_capability_failure :: proc(
	registry: ^Display_Policy_Capability_Registry,
	capability: Display_Policy_Capability,
	code: Failure_Code,
) -> Failure_Context {
	result := display_policy_registry_failure(registry, code)
	result.display_capability = capability
	return result
}

@(private)
display_policy_failure :: proc(
	registry: ^Display_Policy_Capability_Registry,
	capability: Display_Policy_Capability,
	failure: layout.Failure_Context,
) -> Failure_Context {
	code := Failure_Code.Layout_Failure
	#partial switch failure.code {
	case .Stale_Display_Policy:
		code = .Stale_Generation
	case .Invalid_Display_Policy, .Invalid_Display_Action, .Display_Action_Limit:
		code = .Malformed_Record
	}
	result := display_policy_capability_failure(registry, capability, code)
	result.layout_code = failure.code
	result.layout_failure = failure
	result.display_policy_generation = failure.display_policy_generation
	result.limit = failure.maximum
	result.actual = failure.actual
	return result
}
