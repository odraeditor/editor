// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../editor"

@(private)
CAPABILITY_SLOT_BITS :: 16
@(private)
CAPABILITY_GENERATION_BITS :: 32
@(private)
CAPABILITY_SLOT_MASK :: u64(0xffff)
@(private)
CAPABILITY_GENERATION_MASK :: u64(0xffff_ffff)

/*
buffer_capability_registry_init initializes a zero-value fixed-capacity registry.
The nonzero registry identity becomes part of every capability it issues.
*/
buffer_capability_registry_init :: proc(
	registry: ^Buffer_Capability_Registry,
	registry_id: Registry_ID,
) -> (ok: bool, failure: Failure_Context) {
	assert(registry != nil)
	if registry.state != .Uninitialized || registry_id == Registry_ID(0) {
		return false, Failure_Context {
			code = .Invalid_Registry,
			registry_id = registry_id,
		}
	}
	registry.state = .Ready
	registry.registry_id = registry_id
	return true, {}
}

/*
buffer_capability_registry_close closes an empty registry and makes it terminal.
It rejects shutdown while any capability remains live.
*/
buffer_capability_registry_close :: proc(
	registry: ^Buffer_Capability_Registry,
) -> (ok: bool, failure: Failure_Context) {
	assert(registry != nil)
	if registry.state != .Ready {
		return false, registry_failure(registry, .Invalid_Registry)
	}
	if registry.live_count != 0 {
		failure = registry_failure(registry, .Retained_Capabilities)
		failure.limit = 0
		failure.actual = u64(registry.live_count)
		return false, failure
	}
	registry.state = .Closed
	return true, {}
}

/*
buffer_capability_acquire registers one live Odin buffer and returns a non-pointer token.
The returned identity is a value snapshot; callers must present it again for inspection.
*/
buffer_capability_acquire :: proc(
	registry: ^Buffer_Capability_Registry,
	buffer: ^editor.Buffer,
) -> (
	capability: Buffer_Capability,
	identity: Buffer_Identity,
	ok: bool,
	failure: Failure_Context,
) {
	assert(registry != nil)
	if registry.state != .Ready {
		return {}, {}, false, registry_failure(registry, .Invalid_Registry)
	}
	stats, stats_ok, stats_failure := editor.buffer_stats(buffer)
	if !stats_ok {
		return {}, {}, false, editor_failure_context(registry, {}, {}, stats_failure)
	}

	for &slot, slot_index in registry.slots {
		if slot.live || slot.generation == max(u32) {
			continue
		}
		slot.generation += 1
		slot.buffer = buffer
		slot.buffer_id = stats.buffer_id
		slot.live = true
		registry.live_count += 1
		capability = capability_encode(registry.registry_id, slot.generation, u16(slot_index))
		identity = Buffer_Identity {
			buffer_id = stats.buffer_id,
			revision = stats.revision,
			text_bytes = stats.text_bytes,
		}
		return capability, identity, true, {}
	}

	failure = registry_failure(registry, .Capacity_Limit)
	failure.limit = MAX_BUFFER_CAPABILITIES
	failure.actual = u64(registry.live_count) + 1
	return {}, {}, false, failure
}

/*
buffer_capability_release removes one exact-generation capability from its registry.
Success consumes the caller's token and releases no editor-owned buffer storage.
*/
buffer_capability_release :: proc(
	registry: ^Buffer_Capability_Registry,
	capability: ^Buffer_Capability,
) -> (ok: bool, failure: Failure_Context) {
	assert(registry != nil)
	assert(capability != nil)
	slot, resolve_failure := capability_resolve(registry, capability^)
	if resolve_failure.code != .None {
		return false, resolve_failure
	}
	slot.buffer = nil
	slot.buffer_id = {}
	slot.live = false
	assert(registry.live_count > 0)
	registry.live_count -= 1
	capability^ = {}
	return true, {}
}

/*
buffer_capability_inspect copies a revision-checked byte range into caller-owned storage.
It performs no allocation and never exposes the registered buffer pointer or rope storage.
*/
buffer_capability_inspect :: proc(
	registry: ^Buffer_Capability_Registry,
	capability: Buffer_Capability,
	buffer_id: editor.Buffer_ID,
	revision: editor.Revision,
	byte_range: Byte_Range,
	destination: []byte,
) -> (copied: u64, ok: bool, failure: Failure_Context) {
	assert(registry != nil)
	slot, resolve_failure := capability_resolve(registry, capability)
	if resolve_failure.code != .None {
		return 0, false, resolve_failure
	}
	failure_context := Failure_Context {
		registry_id = registry.registry_id,
		capability = capability,
		buffer_id = buffer_id,
		revision = revision,
		range = byte_range,
	}
	stats, stats_ok, stats_failure := editor.buffer_stats(slot.buffer)
	if !stats_ok {
		return 0, false, editor_failure_context(registry, capability, byte_range, stats_failure)
	}
	if buffer_id != slot.buffer_id || buffer_id != stats.buffer_id {
		failure_context.code = .Wrong_Buffer
		failure_context.actual = u64(stats.buffer_id)
		return 0, false, failure_context
	}
	if revision != stats.revision {
		failure_context.code = .Stale_Revision
		failure_context.actual = u64(stats.revision)
		return 0, false, failure_context
	}

	editor_failure: editor.Failure_Context
	copied, ok, editor_failure = editor.buffer_inspect(
		slot.buffer,
		byte_range.start,
		byte_range.end,
		destination,
	)
	if !ok {
		return 0, false, editor_failure_context(registry, capability, byte_range, editor_failure)
	}
	return copied, true, {}
}

@(private)
capability_encode :: proc(
	registry_id: Registry_ID,
	generation: u32,
	slot_index: u16,
) -> Buffer_Capability {
	assert(registry_id != Registry_ID(0))
	assert(generation != 0)
	assert(slot_index < MAX_BUFFER_CAPABILITIES)
	value := u64(registry_id) << (CAPABILITY_GENERATION_BITS + CAPABILITY_SLOT_BITS)
	value |= u64(generation) << CAPABILITY_SLOT_BITS
	value |= u64(slot_index) + 1
	return Buffer_Capability(value)
}

@(private)
capability_resolve :: proc(
	registry: ^Buffer_Capability_Registry,
	capability: Buffer_Capability,
) -> (slot: ^Buffer_Capability_Slot, failure: Failure_Context) {
	if registry.state != .Ready {
		return nil, registry_failure(registry, .Invalid_Registry)
	}
	value := u64(capability)
	if value == 0 {
		return nil, capability_failure(registry, capability, .Invalid_Capability)
	}
	registry_id := Registry_ID(value >> (CAPABILITY_GENERATION_BITS + CAPABILITY_SLOT_BITS))
	if registry_id != registry.registry_id {
		return nil, capability_failure(registry, capability, .Wrong_Registry)
	}
	slot_number := value & CAPABILITY_SLOT_MASK
	if slot_number == 0 || slot_number > MAX_BUFFER_CAPABILITIES {
		return nil, capability_failure(registry, capability, .Invalid_Capability)
	}
	generation := u32((value >> CAPABILITY_SLOT_BITS) & CAPABILITY_GENERATION_MASK)
	if generation == 0 {
		return nil, capability_failure(registry, capability, .Invalid_Capability)
	}
	slot = &registry.slots[int(slot_number - 1)]
	if !slot.live || slot.generation != generation {
		return nil, capability_failure(registry, capability, .Stale_Capability)
	}
	return slot, {}
}

@(private)
registry_failure :: proc(
	registry: ^Buffer_Capability_Registry,
	code: Failure_Code,
) -> Failure_Context {
	return Failure_Context {
		code = code,
		registry_id = registry.registry_id,
	}
}

@(private)
capability_failure :: proc(
	registry: ^Buffer_Capability_Registry,
	capability: Buffer_Capability,
	code: Failure_Code,
) -> Failure_Context {
	return Failure_Context {
		code = code,
		registry_id = registry.registry_id,
		capability = capability,
	}
}

@(private)
editor_failure_context :: proc(
	registry: ^Buffer_Capability_Registry,
	capability: Buffer_Capability,
	byte_range: Byte_Range,
	editor_failure: editor.Failure_Context,
) -> Failure_Context {
	code := Failure_Code.Editor_Failure
	switch editor_failure.code {
	case .Closed_Buffer:
		code = .Closed_Buffer
	case .Wrong_Buffer:
		code = .Wrong_Buffer
	case .Stale_Revision, .Mismatched_Revision:
		code = .Stale_Revision
	case .Reversed_Range:
		code = .Reversed_Range
	case .Out_Of_Range, .Mid_Encoding_Offset:
		code = .Out_Of_Range
	case .Inspection_Limit:
		code = .Inspection_Limit
	case .Malformed_UTF8:
		code = .Malformed_Text
	case .Temporary_Memory_Limit:
		code = .Temporary_Memory_Limit
	case .Cancelled:
		code = .Cancelled
	case .None,
	     .Wrong_Buffer_Kind,
	     .Read_Only_Buffer,
	     .Buffer_Limit,
	     .Replacement_Limit,
	     .Persistent_Memory_Limit,
	     .Undo_Memory_Limit,
	     .Anchor_Limit,
	     .Invalid_Anchor,
	     .Missing_Mark,
	     .Selection_Generation_Limit,
	     .Work_Limit:
		code = .Editor_Failure
	}
	return Failure_Context {
		code = code,
		registry_id = registry.registry_id,
		capability = capability,
		buffer_id = editor_failure.buffer_id,
		revision = editor_failure.revision,
		range = byte_range,
		limit = editor_failure.limit,
		actual = editor_failure.actual,
		editor_code = editor_failure.code,
	}
}
