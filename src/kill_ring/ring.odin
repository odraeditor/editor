// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package kill_ring

import "base:runtime"
import "core:unicode/utf8"

@(private)
Entry :: struct {
	metadata: Entry_Metadata,
	text:     string,
	kill:     Kill_Context,
}

@(private)
Ring_State :: struct {
	ring_id:             Ring_ID,
	generation:          Generation,
	policy:              Policy,
	allocator:           runtime.Allocator,
	temporary_allocator: runtime.Allocator,
	entries:             []Entry,
	count:               int,
	next_entry_id:       Entry_ID,
	retained_text_bytes: u64,
	evicted_entries:     u64,
	pending:             bool,
	reserved_bytes:      u64,
}

@(private)
Reservation_State :: struct {
	ring:              ^Ring_State,
	candidate:         string,
	metadata:          Entry_Metadata,
	kill:              Kill_Context,
	evicted_entries:   int,
	coalesced:         bool,
	result_generation: Generation,
}

/* ring_init creates one empty bounded session ring with caller-owned allocators. */
ring_init :: proc(
	ring: ^Ring,
	ring_id: Ring_ID,
	allocators: Allocator_Set,
	policy := DEFAULT_POLICY,
) -> (ok: bool, failure: Failure_Context) {
	assert(ring != nil)
	assert(ring.state == nil, "kill ring is already initialized")
	if ring_id == Ring_ID(0) {
		return false, Failure_Context{code = .Invalid_Identity}
	}
	if policy_ok, policy_failure := policy_validate(policy); !policy_ok {
		return false, policy_failure
	}
	if allocators.persistent.procedure == nil {
		return false, Failure_Context{code = .Persistent_Memory_Limit, ring_id = ring_id}
	}
	if allocators.temporary.procedure == nil {
		return false, Failure_Context{code = .Temporary_Memory_Limit, ring_id = ring_id}
	}
	state, state_error := new(Ring_State, allocators.persistent)
	if state_error != nil {
		return false, Failure_Context{code = .Persistent_Memory_Limit, ring_id = ring_id}
	}
	entries, entries_error := make([]Entry, int(policy.retained_entries), allocators.persistent)
	if entries_error != nil {
		free(state, allocators.persistent)
		return false, Failure_Context{code = .Persistent_Memory_Limit, ring_id = ring_id}
	}
	state.ring_id = ring_id
	state.generation = Generation(1)
	state.policy = policy
	state.allocator = allocators.persistent
	state.temporary_allocator = allocators.temporary
	state.entries = entries
	state.next_entry_id = Entry_ID(1)
	ring.state = state
	return true, {}
}

/* ring_stats returns copied identity, generation, policy, and exact accounting. */
ring_stats :: proc(ring: ^Ring) -> (stats: Ring_Stats, ok: bool, failure: Failure_Context) {
	state, state_failure := ring_live_state(ring)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	newest := Entry_ID(0)
	if state.count > 0 {
		newest = state.entries[0].metadata.id
	}
	return Ring_Stats {
		ring_id = state.ring_id,
		generation = state.generation,
		newest = newest,
		policy = state.policy,
		usage = ring_usage(state),
	}, true, {}
}

/* admission_reserve copies and validates one complete entry before canonical mutation. */
admission_reserve :: proc(
	ring: ^Ring,
	reservation: ^Reservation,
	request: Admission_Request,
) -> (result: Reservation_Result, ok: bool, failure: Failure_Context) {
	assert(reservation != nil)
	assert(reservation.state == nil, "kill-ring reservation is already initialized")
	state, state_failure := ring_live_state(ring)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	if state.pending {
		return {}, false, ring_failure(state, .Pending_Reservation)
	}
	if request.expected_generation != state.generation {
		return {}, false, ring_generation_failure(state, request.expected_generation)
	}
	if request.cancelled {
		return {}, false, ring_failure(state, .Cancelled)
	}
	if request.kind == .Invalid {
		return {}, false, ring_failure(state, .Invalid_State)
	}
	if len(request.text) == 0 {
		return {}, false, ring_failure(state, .Empty_Text)
	}
	if !utf8.valid_string(request.text) {
		return {}, false, ring_failure(state, .Invalid_UTF8)
	}
	text_bytes := u64(len(request.text))
	if text_bytes > state.policy.entry_bytes {
		return {}, false, ring_limit_failure(state, .Entry_Bytes_Limit, .Entry_Bytes, state.policy.entry_bytes, text_bytes)
	}
	if text_bytes > state.policy.total_bytes {
		return {}, false, ring_limit_failure(state, .Total_Bytes_Limit, .Total_Bytes, state.policy.total_bytes, text_bytes)
	}
	coalesced := request.kind == .Kill && kill_is_compatible(state, request.kill)
	combined_bytes := text_bytes
	operations := u64(1)
	if coalesced {
		combined_bytes, ok = checked_add_u64(u64(len(state.entries[0].text)), text_bytes)
		if !ok || combined_bytes > state.policy.entry_bytes {
			return {}, false, ring_limit_failure(state, .Entry_Bytes_Limit, .Entry_Bytes, state.policy.entry_bytes, combined_bytes)
		}
		operations = state.entries[0].metadata.coalesced_operations + 1
		if operations > state.policy.coalesced_operations {
			return {}, false, ring_limit_failure(state, .Coalescence_Limit, .Coalesced_Operations, state.policy.coalesced_operations, operations)
		}
	}
	reserved, reserved_error := new(Reservation_State, state.temporary_allocator)
	if reserved_error != nil {
		return {}, false, ring_failure(state, .Temporary_Memory_Limit)
	}
	candidate, candidate_error := make([]byte, int(combined_bytes), state.allocator)
	if candidate_error != nil {
		free(reserved, state.temporary_allocator)
		return {}, false, ring_failure(state, .Persistent_Memory_Limit)
	}
	if coalesced && request.kill.direction == .Backward {
		copy(candidate, request.text)
		copy(candidate[len(request.text):], state.entries[0].text)
	} else if coalesced {
		copy(candidate, state.entries[0].text)
		copy(candidate[len(state.entries[0].text):], request.text)
	} else {
		copy(candidate, request.text)
	}
	evictions, eviction_ok := plan_evictions(state, combined_bytes, coalesced)
	if !eviction_ok {
		delete(candidate, state.allocator)
		free(reserved, state.temporary_allocator)
		return {}, false, ring_limit_failure(state, .Total_Bytes_Limit, .Total_Bytes, state.policy.total_bytes, combined_bytes)
	}
	result_generation := Generation(u64(state.generation) + 1)
	entry_id := state.next_entry_id
	if coalesced {
		entry_id = state.entries[0].metadata.id
	}
	reserved.ring = state
	reserved.candidate = string(candidate)
	reserved.metadata = Entry_Metadata {
		id = entry_id,
		byte_count = combined_bytes,
		admission_kind = request.kind,
		coalesced_operations = operations,
		generation = result_generation,
	}
	reserved.kill = request.kill
	reserved.evicted_entries = evictions
	reserved.coalesced = coalesced
	reserved.result_generation = result_generation
	state.pending = true
	state.reserved_bytes = combined_bytes + u64(size_of(Reservation_State))
	reservation.state = reserved
	return Reservation_Result {
		entry = reserved.metadata,
		result_generation = result_generation,
		evicted_entries = u64(evictions),
		coalesced = coalesced,
	}, true, {}
}

/* reservation_commit_reserved publishes one fully prepared admission without allocation. */
reservation_commit_reserved :: proc(reservation: ^Reservation) -> Reservation_Result {
	assert(reservation_is_valid(reservation))
	reserved := (^Reservation_State)(reservation.state)
	state := reserved.ring
	assert(state != nil && state.pending)
	for _ in 0 ..< reserved.evicted_entries {
		ring_evict_oldest(state)
	}
	if reserved.coalesced {
		entry := &state.entries[0]
		state.retained_text_bytes -= u64(len(entry.text))
		delete_string(entry.text, state.allocator)
		entry.text = reserved.candidate
		entry.metadata = reserved.metadata
		entry.kill = reserved.kill
	} else {
		for index := state.count; index > 0; index -= 1 {
			state.entries[index] = state.entries[index - 1]
		}
		state.entries[0] = Entry {
			metadata = reserved.metadata,
			text = reserved.candidate,
			kill = reserved.kill,
		}
		state.count += 1
		state.next_entry_id = Entry_ID(u64(state.next_entry_id) + 1)
	}
	state.retained_text_bytes += reserved.metadata.byte_count
	state.generation = reserved.result_generation
	state.evicted_entries += u64(reserved.evicted_entries)
	state.pending = false
	state.reserved_bytes = 0
	result := Reservation_Result {
		entry = reserved.metadata,
		result_generation = reserved.result_generation,
		evicted_entries = u64(reserved.evicted_entries),
		coalesced = reserved.coalesced,
	}
	reservation.state = nil
	free(reserved, state.temporary_allocator)
	return result
}

/* reservation_abort releases one unpublished admission without canonical mutation. */
reservation_abort :: proc(reservation: ^Reservation) -> (ok: bool, failure: Failure_Context) {
	if !reservation_is_valid(reservation) {
		return false, Failure_Context{code = .Invalid_State}
	}
	reserved := (^Reservation_State)(reservation.state)
	state := reserved.ring
	if state == nil || !state.pending {
		return false, Failure_Context{code = .Invalid_State}
	}
	delete_string(reserved.candidate, state.allocator)
	state.pending = false
	state.reserved_bytes = 0
	reservation.state = nil
	free(reserved, state.temporary_allocator)
	return true, {}
}

/* ring_inspect copies bounded newest-to-oldest entry metadata. */
ring_inspect :: proc(
	ring: ^Ring,
	request: Inspection_Request,
	allocator: runtime.Allocator,
) -> (inspection: Inspection, ok: bool, failure: Failure_Context) {
	state, state_failure := ring_live_state(ring)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	if request.expected_generation != state.generation {
		return {}, false, ring_generation_failure(state, request.expected_generation)
	}
	if request.entry_limit == 0 || request.entry_limit > state.policy.inspection_entries {
		return {}, false, ring_limit_failure(state, .Inspection_Limit, .Inspection_Entries, state.policy.inspection_entries, request.entry_limit)
	}
	count := min(int(request.entry_limit), state.count)
	entries, allocation_error := make([]Entry_Metadata, count, allocator)
	if allocation_error != nil {
		return {}, false, ring_failure(state, .Temporary_Memory_Limit)
	}
	for index in 0 ..< count {
		entries[index] = state.entries[index].metadata
	}
	return Inspection{ring_id = state.ring_id, generation = state.generation, entries = entries}, true, {}
}

/* inspection_release frees one copied metadata result with its destination allocator. */
inspection_release :: proc(inspection: ^Inspection, allocator: runtime.Allocator) {
	if inspection == nil {
		return
	}
	delete(inspection.entries, allocator)
	inspection^ = {}
}

/* entry_copy copies one exact retained entry subject to the supplied byte bound. */
entry_copy :: proc(
	ring: ^Ring,
	request: Entry_Copy_Request,
	allocator: runtime.Allocator,
) -> (copied: Entry_Copy, ok: bool, failure: Failure_Context) {
	state, state_failure := ring_live_state(ring)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	if request.expected_generation != state.generation {
		return {}, false, ring_generation_failure(state, request.expected_generation)
	}
	index := ring_find_entry(state, request.entry_id, state.policy.rotation_work)
	if index < 0 {
		return {}, false, ring_entry_failure(state, .Entry_Not_Found, request.entry_id)
	}
	entry := &state.entries[index]
	if request.byte_limit == 0 || entry.metadata.byte_count > request.byte_limit {
		return {}, false, ring_limit_failure(state, .Entry_Bytes_Limit, .Entry_Bytes, request.byte_limit, entry.metadata.byte_count)
	}
	text, allocation_error := clone_string(entry.text, allocator)
	if allocation_error != nil {
		return {}, false, ring_failure(state, .Temporary_Memory_Limit)
	}
	return Entry_Copy{metadata = entry.metadata, text = text}, true, {}
}

/* rotation_next copies the next retained entry without changing ring order or generation. */
rotation_next :: proc(
	ring: ^Ring,
	request: Rotation_Request,
	allocator: runtime.Allocator,
) -> (copied: Entry_Copy, ok: bool, failure: Failure_Context) {
	state, state_failure := ring_live_state(ring)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	if request.expected_generation != state.generation {
		return {}, false, ring_generation_failure(state, request.expected_generation)
	}
	if state.count == 0 {
		return {}, false, ring_failure(state, .Empty_Ring)
	}
	if request.work_limit == 0 || request.work_limit > state.policy.rotation_work {
		return {}, false, ring_limit_failure(state, .Rotation_Limit, .Rotation_Work, state.policy.rotation_work, request.work_limit)
	}
	index := ring_find_entry(state, request.current_entry, request.work_limit)
	if index < 0 {
		return {}, false, ring_entry_failure(state, .Entry_Not_Found, request.current_entry)
	}
	next := (index + 1) % state.count
	entry := &state.entries[next]
	if request.byte_limit == 0 || entry.metadata.byte_count > request.byte_limit {
		return {}, false, ring_limit_failure(state, .Entry_Bytes_Limit, .Entry_Bytes, request.byte_limit, entry.metadata.byte_count)
	}
	text, allocation_error := clone_string(entry.text, allocator)
	if allocation_error != nil {
		return {}, false, ring_failure(state, .Temporary_Memory_Limit)
	}
	return Entry_Copy{metadata = entry.metadata, text = text}, true, {}
}

/* entry_copy_release frees one copied entry with its destination allocator. */
entry_copy_release :: proc(copied: ^Entry_Copy, allocator: runtime.Allocator) {
	if copied == nil {
		return
	}
	delete_string(copied.text, allocator)
	copied^ = {}
}

/* ring_close releases an empty or settled ring and rejects a live reservation. */
ring_close :: proc(ring: ^Ring) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := ring_live_state(ring)
	if state_failure.code != .None {
		return false, state_failure
	}
	if state.pending {
		return false, ring_failure(state, .Pending_Reservation)
	}
	for index in 0 ..< state.count {
		delete_string(state.entries[index].text, state.allocator)
	}
	allocator := state.allocator
	delete(state.entries, allocator)
	ring.state = nil
	free(state, allocator)
	return true, {}
}

@(private)
ring_live_state :: proc(ring: ^Ring) -> (^Ring_State, Failure_Context) {
	if !ring_is_valid(ring) {
		return nil, Failure_Context{code = .Invalid_State}
	}
	return (^Ring_State)(ring.state), {}
}

@(private)
ring_usage :: proc(state: ^Ring_State) -> Resource_Usage {
	return Resource_Usage {
		retained_entries = u64(state.count),
		retained_text_bytes = state.retained_text_bytes,
		retained_bytes = u64(size_of(Ring_State)) +
			u64(len(state.entries)) * u64(size_of(Entry)) + state.retained_text_bytes,
		reserved_bytes = state.reserved_bytes,
		evicted_entries = state.evicted_entries,
	}
}

@(private)
kill_is_compatible :: proc(state: ^Ring_State, current: Kill_Context) -> bool {
	if state.count == 0 || current.sequence_id == 0 || current.event_sequence == 0 ||
		current.source_buffer_id == 0 || current.start > current.end ||
		current.direction == .Invalid {
		return false
	}
	newest := &state.entries[0]
	previous := newest.kill
	if newest.metadata.admission_kind != .Kill ||
		previous.sequence_id != current.sequence_id ||
		previous.source_buffer_id != current.source_buffer_id ||
		current.event_sequence != previous.event_sequence + 1 ||
		previous.direction != current.direction {
		return false
	}
	if current.direction == .Forward {
		return current.start == previous.start
	}
	return current.end == previous.start
}

@(private)
plan_evictions :: proc(state: ^Ring_State, candidate_bytes: u64, coalesced: bool) -> (int, bool) {
	count := state.count
	retained := state.retained_text_bytes
	if coalesced {
		retained -= u64(len(state.entries[0].text))
	} else {
		count += 1
	}
	retained += candidate_bytes
	evictions := 0
	minimum_count := 0
	if coalesced {
		minimum_count = 1
	}
	for count > int(state.policy.retained_entries) || retained > state.policy.total_bytes {
		oldest := state.count - 1 - evictions
		if oldest < minimum_count {
			return 0, false
		}
		retained -= u64(len(state.entries[oldest].text))
		count -= 1
		evictions += 1
	}
	return evictions, true
}

@(private)
ring_evict_oldest :: proc(state: ^Ring_State) {
	index := state.count - 1
	state.retained_text_bytes -= u64(len(state.entries[index].text))
	delete_string(state.entries[index].text, state.allocator)
	state.entries[index] = {}
	state.count -= 1
}

@(private)
ring_find_entry :: proc(state: ^Ring_State, entry_id: Entry_ID, work_limit: u64) -> int {
	limit := min(state.count, int(work_limit))
	for index in 0 ..< limit {
		if state.entries[index].metadata.id == entry_id {
			return index
		}
	}
	return -1
}

@(private)
ring_failure :: proc(state: ^Ring_State, code: Failure_Code) -> Failure_Context {
	return Failure_Context{code = code, ring_id = state.ring_id, generation = state.generation}
}

@(private)
ring_generation_failure :: proc(state: ^Ring_State, actual: Generation) -> Failure_Context {
	failure := ring_failure(state, .Stale_Generation)
	failure.actual = u64(actual)
	return failure
}

@(private)
ring_entry_failure :: proc(state: ^Ring_State, code: Failure_Code, entry_id: Entry_ID) -> Failure_Context {
	failure := ring_failure(state, code)
	failure.entry_id = entry_id
	return failure
}

@(private)
ring_limit_failure :: proc(state: ^Ring_State, code: Failure_Code, field: Policy_Field, maximum, actual: u64) -> Failure_Context {
	failure := ring_failure(state, code)
	failure.field = field
	failure.maximum = maximum
	failure.actual = actual
	return failure
}

@(private)
clone_string :: proc(contents: string, allocator: runtime.Allocator) -> (string, runtime.Allocator_Error) {
	bytes, allocation_error := make([]byte, len(contents), allocator)
	if allocation_error != nil {
		return "", allocation_error
	}
	copy(bytes, contents)
	return string(bytes), nil
}

@(private)
delete_string :: proc(contents: string, allocator: runtime.Allocator) {
	if len(contents) > 0 {
		delete(contents, allocator)
	}
}

@(private)
checked_add_u64 :: proc(left, right: u64) -> (u64, bool) {
	if right > max(u64) - left {
		return 0, false
	}
	return left + right, true
}
