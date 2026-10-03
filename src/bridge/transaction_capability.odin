// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../editor"
import edit_transaction "../transaction"
import "base:runtime"
import "core:os"

@(private)
TRANSACTION_SLOT_BITS :: 16
@(private)
TRANSACTION_GENERATION_BITS :: 32
@(private)
TRANSACTION_SLOT_MASK :: u64(0xffff)
@(private)
TRANSACTION_GENERATION_MASK :: u64(0xffff_ffff)

/* transaction_capability_registry_init initializes a fixed-capacity registry. */
transaction_capability_registry_init :: proc(
	registry: ^Transaction_Capability_Registry,
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

/* transaction_capability_registry_close closes an empty registry. */
transaction_capability_registry_close :: proc(
	registry: ^Transaction_Capability_Registry,
) -> (ok: bool, failure: Failure_Context) {
	assert(registry != nil)
	if registry.state != .Ready {
		return false, transaction_registry_failure(registry, .Invalid_Registry)
	}
	if registry.live_count != 0 {
		failure = transaction_registry_failure(registry, .Retained_Capabilities)
		failure.actual = u64(registry.live_count)
		return false, failure
	}
	registry.state = .Closed
	return true, {}
}

/* transaction_capability_acquire binds one building root to this thread and command. */
transaction_capability_acquire :: proc(
	registry: ^Transaction_Capability_Registry,
	transaction: ^edit_transaction.Transaction,
	buffer: ^editor.Buffer,
	command_id: u64,
) -> (capability: Transaction_Capability, ok: bool, failure: Failure_Context) {
	assert(registry != nil)
	if registry.state != .Ready {
		return {}, false, transaction_registry_failure(registry, .Invalid_Registry)
	}
	if transaction == nil || buffer == nil || command_id == 0 {
		return {}, false, transaction_registry_failure(registry, .Invalid_Capability)
	}
	stats, stats_ok, transaction_failure := edit_transaction.transaction_stats(transaction)
	if !stats_ok || stats.lifecycle != .Building {
		return {}, false, transaction_capability_transaction_failure(registry, {}, transaction_failure)
	}
	buffer_stats, buffer_ok, editor_failure := editor.buffer_stats(buffer)
	if !buffer_ok {
		return {}, false, transaction_capability_editor_failure(registry, {}, editor_failure)
	}
	if stats.buffer_id != buffer_stats.buffer_id || stats.base_revision != buffer_stats.revision {
		return {}, false, transaction_registry_failure(registry, .Wrong_Transaction)
	}
	for &slot, slot_index in registry.slots {
		if slot.live || slot.generation == max(u32) {
			continue
		}
		slot.generation += 1
		slot.transaction = transaction
		slot.buffer = buffer
		slot.transaction_id = stats.transaction_id
		slot.command_id = command_id
		slot.owner_thread_id = os.get_current_thread_id()
		slot.live = true
		registry.live_count += 1
		return transaction_capability_encode(
			registry.registry_id,
			slot.generation,
			u16(slot_index),
		), true, {}
	}
	failure = transaction_registry_failure(registry, .Capacity_Limit)
	failure.limit = MAX_TRANSACTION_CAPABILITIES
	failure.actual = u64(registry.live_count) + 1
	return {}, false, failure
}

/* transaction_capability_release ends dynamic extent and invalidates the token. */
transaction_capability_release :: proc(
	registry: ^Transaction_Capability_Registry,
	capability: ^Transaction_Capability,
) -> (ok: bool, failure: Failure_Context) {
	assert(registry != nil)
	assert(capability != nil)
	slot, resolve_failure := transaction_capability_resolve(registry, capability^, 0, false, false)
	if resolve_failure.code != .None {
		return false, resolve_failure
	}
	if slot.call_active {
		return false, transaction_capability_failure(registry, capability^, .Reentrant_Call)
	}
	if slot.nested_count != 0 {
		edit_transaction.transaction_abort(slot.transaction)
		slot.nested = {}
		slot.nested_count = 0
	}
	slot.transaction = nil
	slot.buffer = nil
	slot.transaction_id = {}
	slot.command_id = 0
	slot.owner_thread_id = 0
	slot.live = false
	assert(registry.live_count > 0)
	registry.live_count -= 1
	capability^ = {}
	return true, {}
}

/* transaction_capability_inspect copies private read-your-writes text. */
transaction_capability_inspect :: proc(
	registry: ^Transaction_Capability_Registry,
	capability: Transaction_Capability,
	command_id, start, end: u64,
	destination: []byte,
) -> (copied: u64, ok: bool, failure: Failure_Context) {
	slot, entry_failure := transaction_capability_enter(registry, capability, command_id)
	if entry_failure.code != .None {
		return 0, false, entry_failure
	}
	defer transaction_capability_leave(slot)
	start_position, start_ok, start_failure := edit_transaction.transaction_position(
		slot.transaction,
		editor.Byte_Offset(start),
	)
	if !start_ok {
		return 0, false, transaction_capability_transaction_failure(registry, capability, start_failure)
	}
	end_position, end_ok, end_failure := edit_transaction.transaction_position(
		slot.transaction,
		editor.Byte_Offset(end),
	)
	if !end_ok {
		return 0, false, transaction_capability_transaction_failure(registry, capability, end_failure)
	}
	transaction_failure: edit_transaction.Failure_Context
	copied, ok, transaction_failure = edit_transaction.transaction_inspect(
		slot.transaction,
		start_position,
		end_position,
		destination,
	)
	if !ok {
		return 0, false, transaction_capability_transaction_failure(registry, capability, transaction_failure)
	}
	return copied, true, {}
}

/* transaction_capability_apply_batch validates copied records and submits one base batch. */
transaction_capability_apply_batch :: proc(
	registry: ^Transaction_Capability_Registry,
	capability: Transaction_Capability,
	command_id: u64,
	records: []Transaction_Edit_Record,
	replacements: []byte,
	temporary_allocator: runtime.Allocator,
) -> (ok: bool, failure: Failure_Context) {
	slot, entry_failure := transaction_capability_enter(registry, capability, command_id)
	if entry_failure.code != .None {
		return false, entry_failure
	}
	defer transaction_capability_leave(slot)
	batch, allocation_error := make([]edit_transaction.Base_Splice, len(records), temporary_allocator)
	if allocation_error != nil {
		failure = transaction_capability_failure(registry, capability, .Temporary_Memory_Limit)
		failure.actual = u64(len(records)) * u64(size_of(edit_transaction.Base_Splice))
		return false, failure
	}
	defer delete(batch, temporary_allocator)
	for record, index in records {
		replacement_end, addition_ok := checked_add(record.replacement_offset, record.replacement_bytes)
		if record.start > record.end || !addition_ok || replacement_end > u64(len(replacements)) {
			return false, transaction_capability_failure(registry, capability, .Malformed_Record)
		}
		start, start_ok, start_failure := editor.buffer_position(
			slot.buffer,
			editor.Byte_Offset(record.start),
		)
		if !start_ok {
			return false, transaction_capability_editor_failure(registry, capability, start_failure)
		}
		end, end_ok, end_failure := editor.buffer_position(
			slot.buffer,
			editor.Byte_Offset(record.end),
		)
		if !end_ok {
			return false, transaction_capability_editor_failure(registry, capability, end_failure)
		}
		batch[index] = edit_transaction.Base_Splice {
			start = start,
			end = end,
			replacement = string(replacements[record.replacement_offset:replacement_end]),
		}
	}
	applied, transaction_failure := edit_transaction.transaction_apply_batch(slot.transaction, batch)
	if !applied {
		return false, transaction_capability_transaction_failure(registry, capability, transaction_failure)
	}
	return true, {}
}

/* transaction_capability_splice applies one current-private-revision edit. */
transaction_capability_splice :: proc(
	registry: ^Transaction_Capability_Registry,
	capability: Transaction_Capability,
	command_id, start, end: u64,
	replacement: string,
) -> (ok: bool, failure: Failure_Context) {
	slot, entry_failure := transaction_capability_enter(registry, capability, command_id)
	if entry_failure.code != .None {
		return false, entry_failure
	}
	defer transaction_capability_leave(slot)
	start_position, start_ok, start_failure := edit_transaction.transaction_position(slot.transaction, editor.Byte_Offset(start))
	if !start_ok {
		return false, transaction_capability_transaction_failure(registry, capability, start_failure)
	}
	end_position, end_ok, end_failure := edit_transaction.transaction_position(slot.transaction, editor.Byte_Offset(end))
	if !end_ok {
		return false, transaction_capability_transaction_failure(registry, capability, end_failure)
	}
	applied, transaction_failure := edit_transaction.transaction_splice(
		slot.transaction,
		editor.Working_Splice{start = start_position, end = end_position, replacement = replacement},
	)
	if !applied {
		return false, transaction_capability_transaction_failure(registry, capability, transaction_failure)
	}
	return true, {}
}

/* transaction_capability_nested_begin creates one checked nested savepoint. */
transaction_capability_nested_begin :: proc(
	registry: ^Transaction_Capability_Registry,
	capability: Transaction_Capability,
	command_id: u64,
	origin: edit_transaction.Origin,
	command: string,
) -> (nested: Nested_Transaction_Capability, ok: bool, failure: Failure_Context) {
	slot, entry_failure := transaction_capability_enter(registry, capability, command_id)
	if entry_failure.code != .None {
		return {}, false, entry_failure
	}
	defer transaction_capability_leave(slot)
	if u64(slot.nested_count) >= MAX_TRANSACTION_NESTING {
		failure = transaction_capability_failure(registry, capability, .Capacity_Limit)
		failure.limit = MAX_TRANSACTION_NESTING
		return {}, false, failure
	}
	handle, begun, transaction_failure := edit_transaction.transaction_nested_begin(
		slot.transaction,
		origin,
		command,
	)
	if !begun {
		return {}, false, transaction_capability_transaction_failure(registry, capability, transaction_failure)
	}
	index := slot.nested_count
	slot.nested[index] = handle
	slot.nested_count += 1
	value := (u64(slot.generation) << 32) | (u64(index) + 1)
	return Nested_Transaction_Capability(value), true, {}
}

/* transaction_capability_nested_finish consumes the current top nested command. */
transaction_capability_nested_finish :: proc(
	registry: ^Transaction_Capability_Registry,
	capability: Transaction_Capability,
	command_id: u64,
	nested: Nested_Transaction_Capability,
	disposition: edit_transaction.Nested_Failure_Disposition,
	succeeded: bool,
) -> (ok: bool, failure: Failure_Context) {
	slot, entry_failure := transaction_capability_enter(registry, capability, command_id)
	if entry_failure.code != .None {
		return false, entry_failure
	}
	defer transaction_capability_leave(slot)
	value := u64(nested)
	index := value & 0xffff_ffff
	if value >> 32 != u64(slot.generation) || index == 0 || index != u64(slot.nested_count) {
		return false, transaction_capability_failure(registry, capability, .Stale_Capability)
	}
	handle := &slot.nested[index - 1]
	transaction_failure: edit_transaction.Failure_Context
	if succeeded {
		ok, transaction_failure = edit_transaction.transaction_nested_succeed(slot.transaction, handle)
	} else {
		ok, transaction_failure = edit_transaction.transaction_nested_fail(slot.transaction, handle, disposition)
	}
	if !ok {
		return false, transaction_capability_transaction_failure(registry, capability, transaction_failure)
	}
	slot.nested_count -= 1
	return true, {}
}

/* transaction_capability_request_abort cooperatively cancels the root. */
transaction_capability_request_abort :: proc(
	registry: ^Transaction_Capability_Registry,
	capability: Transaction_Capability,
	command_id: u64,
) -> (ok: bool, failure: Failure_Context) {
	slot, entry_failure := transaction_capability_enter(registry, capability, command_id)
	if entry_failure.code != .None {
		return false, entry_failure
	}
	defer transaction_capability_leave(slot)
	requested, transaction_failure := edit_transaction.transaction_request_cancel(slot.transaction)
	if !requested {
		return false, transaction_capability_transaction_failure(registry, capability, transaction_failure)
	}
	return true, {}
}

@(private)
transaction_capability_enter :: proc(
	registry: ^Transaction_Capability_Registry,
	capability: Transaction_Capability,
	command_id: u64,
) -> (^Transaction_Capability_Slot, Failure_Context) {
	slot, failure := transaction_capability_resolve(registry, capability, command_id, true, true)
	if failure.code != .None {
		return nil, failure
	}
	if slot.call_active {
		return nil, transaction_capability_failure(registry, capability, .Reentrant_Call)
	}
	slot.call_active = true
	return slot, {}
}

@(private)
transaction_capability_leave :: proc(slot: ^Transaction_Capability_Slot) {
	assert(slot != nil && slot.call_active)
	slot.call_active = false
}

@(private)
transaction_capability_resolve :: proc(
	registry: ^Transaction_Capability_Registry,
	capability: Transaction_Capability,
	command_id: u64,
	check_command: bool,
	check_transaction: bool,
) -> (slot: ^Transaction_Capability_Slot, failure: Failure_Context) {
	if registry == nil || registry.state != .Ready {
		return nil, transaction_registry_failure(registry, .Invalid_Registry)
	}
	value := u64(capability)
	registry_id := Registry_ID(value >> (TRANSACTION_GENERATION_BITS + TRANSACTION_SLOT_BITS))
	slot_number := value & TRANSACTION_SLOT_MASK
	generation := u32((value >> TRANSACTION_SLOT_BITS) & TRANSACTION_GENERATION_MASK)
	if value == 0 || registry_id != registry.registry_id || slot_number == 0 ||
	   slot_number > MAX_TRANSACTION_CAPABILITIES || generation == 0 {
		return nil, transaction_capability_failure(registry, capability, .Invalid_Capability)
	}
	slot = &registry.slots[int(slot_number - 1)]
	if !slot.live || slot.generation != generation {
		return nil, transaction_capability_failure(registry, capability, .Stale_Capability)
	}
	if os.get_current_thread_id() != slot.owner_thread_id {
		return nil, transaction_capability_failure(registry, capability, .Wrong_Thread)
	}
	if check_command && command_id != slot.command_id {
		return nil, transaction_capability_failure(registry, capability, .Wrong_Command)
	}
	if check_transaction {
		stats, stats_ok, transaction_failure := edit_transaction.transaction_stats(slot.transaction)
		if !stats_ok || stats.transaction_id != slot.transaction_id || stats.lifecycle != .Building {
			failure = transaction_capability_transaction_failure(registry, capability, transaction_failure)
			failure.code = .Wrong_Transaction
			return nil, failure
		}
	}
	return slot, {}
}

@(private)
transaction_capability_encode :: proc(
	registry_id: Registry_ID,
	generation: u32,
	slot_index: u16,
) -> Transaction_Capability {
	value := u64(registry_id) << (TRANSACTION_GENERATION_BITS + TRANSACTION_SLOT_BITS)
	value |= u64(generation) << TRANSACTION_SLOT_BITS
	value |= u64(slot_index) + 1
	return Transaction_Capability(value)
}

@(private)
transaction_registry_failure :: proc(
	registry: ^Transaction_Capability_Registry,
	code: Failure_Code,
) -> Failure_Context {
	registry_id: Registry_ID
	if registry != nil {
		registry_id = registry.registry_id
	}
	return Failure_Context{code = code, registry_id = registry_id}
}

@(private)
transaction_capability_failure :: proc(
	registry: ^Transaction_Capability_Registry,
	capability: Transaction_Capability,
	code: Failure_Code,
) -> Failure_Context {
	result := transaction_registry_failure(registry, code)
	result.capability = Buffer_Capability(capability)
	return result
}

@(private)
transaction_capability_transaction_failure :: proc(
	registry: ^Transaction_Capability_Registry,
	capability: Transaction_Capability,
	failure: edit_transaction.Failure_Context,
) -> Failure_Context {
	result := transaction_capability_failure(registry, capability, .Transaction_Failure)
	result.transaction_code = failure.code
	result.editor_code = failure.editor_failure.code
	result.limit = failure.limit
	result.actual = failure.actual
	return result
}

@(private)
transaction_capability_editor_failure :: proc(
	registry: ^Transaction_Capability_Registry,
	capability: Transaction_Capability,
	failure: editor.Failure_Context,
) -> Failure_Context {
	result := transaction_capability_failure(registry, capability, .Editor_Failure)
	result.editor_code = failure.code
	result.limit = failure.limit
	result.actual = failure.actual
	return result
}

@(private)
checked_add :: proc(left, right: u64) -> (u64, bool) {
	if right > max(u64) - left {
		return 0, false
	}
	return left + right, true
}
