// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package project

import "../document"
import "base:runtime"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"

/* MAX_CANDIDATE_HISTORY_ENTRIES bounds one registered Project usage record. */
MAX_CANDIDATE_HISTORY_ENTRIES :: u32(1_024)
/* MAX_CANDIDATE_HISTORY_KEY_BYTES bounds one stable command or path key. */
MAX_CANDIDATE_HISTORY_KEY_BYTES :: u32(document.MAX_PATH_BYTES)
/* MAX_CANDIDATE_HISTORY_MODULE_BYTES bounds one rendered Racket history module. */
MAX_CANDIDATE_HISTORY_MODULE_BYTES :: u64(8 * 1_024 * 1_024)
/* MAX_CANDIDATE_HISTORY_SEQUENCE is the admitted logical sequence ceiling. */
MAX_CANDIDATE_HISTORY_SEQUENCE :: u64(9_223_372_036_854_775_807)
/* MAX_CANDIDATE_HISTORY_DIRTY_GENERATIONS admits one latest dirty native state. */
MAX_CANDIDATE_HISTORY_DIRTY_GENERATIONS :: u8(1)
/* CANDIDATE_HISTORY_FLUSH_EVENTS bounds successful events before an action flush. */
CANDIDATE_HISTORY_FLUSH_EVENTS :: u8(16)
/* MAX_CANDIDATE_HISTORY_RETRIES admits one retry after a failed flush. */
MAX_CANDIDATE_HISTORY_RETRIES :: u8(1)
/* MAX_CANDIDATE_HISTORY_CALLBACKS bounds one load or publication exchange. */
MAX_CANDIDATE_HISTORY_CALLBACKS :: u8(8)
/* MAX_CANDIDATE_COMMAND_KEY_BYTES matches the factory command-name contract. */
MAX_CANDIDATE_COMMAND_KEY_BYTES :: u32(96)

/* Candidate_History_Category is the closed durable usage-identity category. */
Candidate_History_Category :: enum u8 {
	Invalid,
	Command,
	Document,
	Project_File,
	Project,
	Workspace,
}

/* Candidate_History_Failure_Code identifies bounded native history failures. */
Candidate_History_Failure_Code :: enum u8 {
	None,
	Invalid_Owner,
	Invalid_Project,
	Invalid_Category,
	Invalid_Key,
	Entry_Limit,
	Module_Limit,
	Sequence_Limit,
	Stale_Generation,
	Retry_Exhausted,
	Persistent_Memory_Limit,
}

/* Candidate_History_Failure carries bounded limit and generation context. */
Candidate_History_Failure :: struct {
	code:     Candidate_History_Failure_Code,
	limit:    u64,
	actual:   u64,
	expected: u64,
}

/* Candidate_History_Entry_Definition borrows one validated load proposal entry. */
Candidate_History_Entry_Definition :: struct {
	category: Candidate_History_Category,
	key:      string,
	sequence: u64,
}

/* Candidate_History_Descriptor is one immutable borrowed snapshot entry. */
Candidate_History_Descriptor :: struct {
	category: Candidate_History_Category,
	key:      string,
	sequence: u64,
}

/* Candidate_History_Usage accounts one owner and its copied stable keys. */
Candidate_History_Usage :: struct {
	entries:          u32,
	key_bytes:        u64,
	retained_bytes:   u64,
	dirty_generations: u8,
	retry_count:      u8,
}

/* Candidate_History is the opaque owner of one Project-scoped recency lookup. */
Candidate_History :: struct {
	state: rawptr,
}

/* Candidate_History_Batch owns one canonical copied publication snapshot. */
Candidate_History_Batch :: struct {
	state:            rawptr,
	project_id:       string,
	generation:       u64,
	next_sequence:    u64,
	dirty_generation: u64,
	entries:          []Candidate_History_Descriptor,
}

@(private)
Candidate_History_Key :: struct {
	category: Candidate_History_Category,
	key:      string,
}

@(private)
Candidate_History_Entry :: struct {
	category: Candidate_History_Category,
	key:      string,
	sequence: u64,
}

@(private)
Candidate_History_State :: struct {
	project_id:         string,
	entries:            [dynamic]Candidate_History_Entry,
	index:              map[Candidate_History_Key]int,
	generation:         u64,
	next_sequence:      u64,
	dirty_generation:   u64,
	events_since_flush: u8,
	retry_count:        u8,
	key_bytes:          u64,
	last_failure:       Candidate_History_Failure,
	allocator:          runtime.Allocator,
}

@(private)
Candidate_History_Batch_State :: struct {
	storage:     []u8,
	descriptors: []Candidate_History_Descriptor,
	allocator:   runtime.Allocator,
}

/* candidate_history_init creates empty durable or process-local history state. */
candidate_history_init :: proc(
	history: ^Candidate_History,
	project_id: string,
	allocator := context.allocator,
) -> (ok: bool, failure: Candidate_History_Failure) {
	assert(history != nil)
	history^ = {}
	if allocator.procedure == nil {
		return false, Candidate_History_Failure{code = .Persistent_Memory_Limit}
	}
	if len(project_id) > 0 && !candidate_history_project_id_is_valid(project_id) {
		return false, Candidate_History_Failure {
			code = .Invalid_Project,
			limit = MAX_DURABLE_ID_BYTES,
			actual = u64(len(project_id)),
		}
	}
	state, state_error := new(Candidate_History_State, allocator)
	if state_error != nil {
		return false, Candidate_History_Failure{code = .Persistent_Memory_Limit}
	}
	state.allocator = allocator
	if len(project_id) > 0 {
		state.project_id, state_error = strings.clone(project_id, allocator)
		if state_error != nil {
			free(state, allocator)
			return false, Candidate_History_Failure{code = .Persistent_Memory_Limit}
		}
	}
	state.entries, state_error = make(
		[dynamic]Candidate_History_Entry,
		0,
		int(MAX_CANDIDATE_HISTORY_ENTRIES),
		allocator,
	)
	if state_error != nil {
		candidate_history_state_release(state)
		return false, Candidate_History_Failure{code = .Persistent_Memory_Limit}
	}
	state.index, state_error = make(
		map[Candidate_History_Key]int,
		int(MAX_CANDIDATE_HISTORY_ENTRIES) * 2,
		allocator,
	)
	if state_error != nil {
		candidate_history_state_release(state)
		return false, Candidate_History_Failure{code = .Persistent_Memory_Limit}
	}
	state.next_sequence = 1
	history.state = state
	return true, {}
}

/* candidate_history_close releases every copied key and invalidates the owner. */
candidate_history_close :: proc(history: ^Candidate_History) {
	if history == nil || history.state == nil {
		return
	}
	candidate_history_state_release(candidate_history_state(history))
	history^ = {}
}

/* candidate_history_replace atomically admits one complete validated load generation. */
candidate_history_replace :: proc(
	history: ^Candidate_History,
	project_id: string,
	generation, next_sequence: u64,
	definitions: []Candidate_History_Entry_Definition,
) -> (ok: bool, failure: Candidate_History_Failure) {
	state := candidate_history_state(history)
	if state == nil {
		return false, Candidate_History_Failure{code = .Invalid_Owner}
	}
	if state.project_id != project_id || len(project_id) == 0 {
		return false, Candidate_History_Failure{code = .Invalid_Project}
	}
	if generation == 0 || next_sequence == 0 ||
	   next_sequence > MAX_CANDIDATE_HISTORY_SEQUENCE {
		return false, Candidate_History_Failure{code = .Stale_Generation}
	}
	if len(definitions) > int(MAX_CANDIDATE_HISTORY_ENTRIES) {
		return false, Candidate_History_Failure {
			code = .Entry_Limit,
			limit = u64(MAX_CANDIDATE_HISTORY_ENTRIES),
			actual = u64(len(definitions)),
		}
	}
	candidate: Candidate_History
	initialized, init_failure := candidate_history_init(&candidate, project_id, state.allocator)
	if !initialized {
		return false, init_failure
	}
	candidate_state := candidate_history_state(&candidate)
	candidate_state.generation = generation
	candidate_state.next_sequence = next_sequence
	for definition in definitions {
		if definition.sequence == 0 || definition.sequence >= next_sequence {
			candidate_history_close(&candidate)
			return false, Candidate_History_Failure{code = .Sequence_Limit, actual = definition.sequence}
		}
		added, add_failure := candidate_history_add_loaded(candidate_state, definition)
		if !added {
			candidate_history_close(&candidate)
			return false, add_failure
		}
	}
	old := history.state
	history.state = candidate.state
	candidate.state = nil
	candidate_history_state_release((^Candidate_History_State)(old))
	return true, {}
}

/* candidate_history_clear_loaded publishes usable empty ordering for a missing or rejected record. */
candidate_history_clear_loaded :: proc(
	history: ^Candidate_History,
) -> (ok: bool, failure: Candidate_History_Failure) {
	state := candidate_history_state(history)
	if state == nil {
		return false, Candidate_History_Failure{code = .Invalid_Owner}
	}
	candidate: Candidate_History
	initialized, init_failure := candidate_history_init(&candidate, state.project_id, state.allocator)
	if !initialized {
		return false, init_failure
	}
	old := history.state
	history.state = candidate.state
	candidate.state = nil
	candidate_history_state_release((^Candidate_History_State)(old))
	return true, {}
}

/* candidate_history_lookup returns Project-scoped recency without changing state. */
candidate_history_lookup :: proc(
	history: ^Candidate_History,
	category: Candidate_History_Category,
	key: string,
) -> (sequence: u64, found: bool) {
	state := candidate_history_state(history)
	if state == nil || !candidate_history_category_is_valid(category) {
		return 0, false
	}
	encoded := state.index[Candidate_History_Key{category = category, key = key}]
	if encoded <= 0 || encoded > len(state.entries) {
		return 0, false
	}
	entry := &state.entries[encoded - 1]
	if entry.category != category || entry.key != key {
		return 0, false
	}
	return entry.sequence, true
}

/* candidate_history_record_success records exactly one eligible successful action. */
candidate_history_record_success :: proc(
	history: ^Candidate_History,
	category: Candidate_History_Category,
	key: string,
) -> (sequence: u64, ok: bool, failure: Candidate_History_Failure) {
	state := candidate_history_state(history)
	if state == nil {
		return 0, false, Candidate_History_Failure{code = .Invalid_Owner}
	}
	if !candidate_history_category_is_valid(category) {
		return 0, false, Candidate_History_Failure{code = .Invalid_Category}
	}
	if !candidate_history_key_is_valid(category, key) {
		return 0, false, Candidate_History_Failure {
			code = .Invalid_Key,
			limit = candidate_history_key_limit(category),
			actual = u64(len(key)),
		}
	}
	if state.next_sequence >= MAX_CANDIDATE_HISTORY_SEQUENCE {
		if !candidate_history_renormalize(state) {
			return 0, false, Candidate_History_Failure {
				code = .Sequence_Limit,
				limit = MAX_CANDIDATE_HISTORY_SEQUENCE,
				actual = state.next_sequence,
			}
		}
	}
	identity := Candidate_History_Key{category = category, key = key}
	encoded := state.index[identity]
	if encoded == 0 {
		owned_key, key_error := strings.clone(key, state.allocator)
		if key_error != nil {
			return 0, false, Candidate_History_Failure{code = .Persistent_Memory_Limit}
		}
		if len(state.entries) >= int(MAX_CANDIDATE_HISTORY_ENTRIES) {
			index := candidate_history_least_recent(state)
			entry := &state.entries[index]
			delete_key(&state.index, Candidate_History_Key{category = entry.category, key = entry.key})
			state.key_bytes -= u64(len(entry.key))
			delete(entry.key, state.allocator)
			entry^ = Candidate_History_Entry{category = category, key = owned_key}
			encoded = index + 1
		} else {
			_, append_error := append(
				&state.entries,
				Candidate_History_Entry{category = category, key = owned_key},
			)
			if append_error != nil {
				delete(owned_key, state.allocator)
				return 0, false, Candidate_History_Failure{code = .Persistent_Memory_Limit}
			}
			encoded = len(state.entries)
		}
		state.key_bytes += u64(len(owned_key))
		state.index[Candidate_History_Key{category = category, key = owned_key}] = encoded
	}
	sequence = state.next_sequence
	state.entries[encoded - 1].sequence = sequence
	state.next_sequence += 1
	state.dirty_generation += 1
	state.events_since_flush = min(
		state.events_since_flush + 1,
		CANDIDATE_HISTORY_FLUSH_EVENTS,
	)
	state.last_failure = {}
	return sequence, true, {}
}

/* candidate_history_flush_due reports the bounded action threshold. */
candidate_history_flush_due :: proc(history: ^Candidate_History) -> bool {
	state := candidate_history_state(history)
	return state != nil && len(state.project_id) > 0 && state.dirty_generation > 0 &&
	       state.events_since_flush >= CANDIDATE_HISTORY_FLUSH_EVENTS
}

/* candidate_history_note_flush_failure preserves one dirty generation for one retry. */
candidate_history_note_flush_failure :: proc(
	history: ^Candidate_History,
) -> (retry: bool, failure: Candidate_History_Failure) {
	state := candidate_history_state(history)
	if state == nil {
		return false, Candidate_History_Failure{code = .Invalid_Owner}
	}
	if state.retry_count >= MAX_CANDIDATE_HISTORY_RETRIES {
		failure = Candidate_History_Failure {
			code = .Retry_Exhausted,
			limit = u64(MAX_CANDIDATE_HISTORY_RETRIES),
			actual = u64(state.retry_count) + 1,
		}
		state.last_failure = failure
		return false, failure
	}
	state.retry_count += 1
	return true, {}
}

/* candidate_history_mark_published clears dirty state after exact generation validation. */
candidate_history_mark_published :: proc(
	history: ^Candidate_History,
	expected_dirty_generation, published_generation: u64,
) -> (ok: bool, failure: Candidate_History_Failure) {
	state := candidate_history_state(history)
	if state == nil {
		return false, Candidate_History_Failure{code = .Invalid_Owner}
	}
	expected_publication := state.generation + 1
	if state.dirty_generation == 0 || expected_dirty_generation != state.dirty_generation ||
	   published_generation != expected_publication {
		return false, Candidate_History_Failure {
			code = .Stale_Generation,
			expected = expected_publication,
			actual = published_generation,
		}
	}
	state.generation = published_generation
	state.dirty_generation = 0
	state.events_since_flush = 0
	state.retry_count = 0
	state.last_failure = {}
	return true, {}
}

/* candidate_history_snapshot copies canonical persistence order and all stable keys. */
candidate_history_snapshot :: proc(
	history: ^Candidate_History,
	allocator := context.allocator,
) -> (batch: Candidate_History_Batch, ok: bool, failure: Candidate_History_Failure) {
	state := candidate_history_state(history)
	if state == nil || allocator.procedure == nil {
		return {}, false, Candidate_History_Failure{code = .Invalid_Owner}
	}
	batch_state, state_error := new(Candidate_History_Batch_State, allocator)
	if state_error != nil {
		return {}, false, Candidate_History_Failure{code = .Persistent_Memory_Limit}
	}
	batch_state.allocator = allocator
	batch_state.storage, state_error = make(
		[]u8,
		len(state.project_id) + int(state.key_bytes),
		allocator,
	)
	if state_error != nil {
		free(batch_state, allocator)
		return {}, false, Candidate_History_Failure{code = .Persistent_Memory_Limit}
	}
	batch_state.descriptors, state_error = make(
		[]Candidate_History_Descriptor,
		len(state.entries),
		allocator,
	)
	if state_error != nil {
		delete(batch_state.storage, allocator)
		free(batch_state, allocator)
		return {}, false, Candidate_History_Failure{code = .Persistent_Memory_Limit}
	}
	cursor := 0
	copy(batch_state.storage[cursor:], transmute([]u8)state.project_id)
	project_id := string(batch_state.storage[cursor:cursor + len(state.project_id)])
	cursor += len(state.project_id)
	for entry, index in state.entries {
		copy(batch_state.storage[cursor:], transmute([]u8)entry.key)
		key := string(batch_state.storage[cursor:cursor + len(entry.key)])
		cursor += len(entry.key)
		batch_state.descriptors[index] = Candidate_History_Descriptor {
			category = entry.category,
			key = key,
			sequence = entry.sequence,
		}
	}
	slice.sort_by(batch_state.descriptors, candidate_history_descriptor_canonical_less)
	return Candidate_History_Batch {
		state = batch_state,
		project_id = project_id,
		generation = state.generation,
		next_sequence = state.next_sequence,
		dirty_generation = state.dirty_generation,
		entries = batch_state.descriptors,
	}, true, {}
}

/* candidate_history_batch_close releases one copied publication snapshot. */
candidate_history_batch_close :: proc(batch: ^Candidate_History_Batch) {
	if batch == nil || batch.state == nil {
		return
	}
	candidate_history_batch_state_release((^Candidate_History_Batch_State)(batch.state))
	batch^ = {}
}

/* candidate_history_usage returns exact retained native storage. */
candidate_history_usage :: proc(
	history: ^Candidate_History,
) -> (usage: Candidate_History_Usage, ok: bool) {
	state := candidate_history_state(history)
	if state == nil {
		return {}, false
	}
	return Candidate_History_Usage {
		entries = u32(len(state.entries)),
		key_bytes = state.key_bytes,
		retained_bytes = u64(size_of(Candidate_History_State)) +
		                 u64(cap(state.entries)) * u64(size_of(Candidate_History_Entry)) +
		                 u64(cap(state.index)) * u64(size_of(Candidate_History_Key) + size_of(int)) +
		                 u64(len(state.project_id)) + state.key_bytes,
		dirty_generations = 1 if state.dirty_generation > 0 else 0,
		retry_count = state.retry_count,
	}, true
}

@(private)
candidate_history_add_loaded :: proc(
	state: ^Candidate_History_State,
	definition: Candidate_History_Entry_Definition,
) -> (ok: bool, failure: Candidate_History_Failure) {
	if !candidate_history_category_is_valid(definition.category) {
		return false, Candidate_History_Failure{code = .Invalid_Category}
	}
	if !candidate_history_key_is_valid(definition.category, definition.key) {
		return false, Candidate_History_Failure{code = .Invalid_Key}
	}
	identity := Candidate_History_Key{category = definition.category, key = definition.key}
	if state.index[identity] != 0 {
		return false, Candidate_History_Failure{code = .Invalid_Key}
	}
	owned_key, key_error := strings.clone(definition.key, state.allocator)
	if key_error != nil {
		return false, Candidate_History_Failure{code = .Persistent_Memory_Limit}
	}
	_, append_error := append(&state.entries, Candidate_History_Entry {
		category = definition.category,
		key = owned_key,
		sequence = definition.sequence,
	})
	if append_error != nil {
		delete(owned_key, state.allocator)
		return false, Candidate_History_Failure{code = .Persistent_Memory_Limit}
	}
	state.key_bytes += u64(len(owned_key))
	state.index[Candidate_History_Key{category = definition.category, key = owned_key}] =
		len(state.entries)
	return true, {}
}

@(private)
candidate_history_renormalize :: proc(state: ^Candidate_History_State) -> bool {
	indices, indices_error := make([]int, len(state.entries), context.temp_allocator)
	if indices_error != nil {
		return false
	}
	defer delete(indices, context.temp_allocator)
	for &index, position in indices {
		index = position
	}
	candidate_history_sort_indices(state, indices)
	for index, position in indices {
		state.entries[position].sequence = u64(index + 1)
	}
	state.next_sequence = u64(len(state.entries) + 1)
	return state.next_sequence < MAX_CANDIDATE_HISTORY_SEQUENCE
}

@(private)
candidate_history_least_recent :: proc(state: ^Candidate_History_State) -> int {
	selected := 0
	for entry, index in state.entries[1:] {
		actual_index := index + 1
		if candidate_history_ascending_less(entry, state.entries[selected]) {
			selected = actual_index
		}
	}
	return selected
}

@(private)
candidate_history_ascending_less :: proc(
	left, right: Candidate_History_Entry,
) -> bool {
	if left.sequence != right.sequence {
		return left.sequence < right.sequence
	}
	if left.category != right.category {
		return left.category < right.category
	}
	return strings.compare(left.key, right.key) < 0
}

@(private)
candidate_history_canonical_less :: proc(
	left, right: Candidate_History_Entry,
) -> bool {
	if left.sequence != right.sequence {
		return left.sequence > right.sequence
	}
	if left.category != right.category {
		return left.category < right.category
	}
	return strings.compare(left.key, right.key) < 0
}

@(private)
candidate_history_descriptor_canonical_less :: proc(
	left, right: Candidate_History_Descriptor,
) -> bool {
	if left.sequence != right.sequence {
		return left.sequence > right.sequence
	}
	if left.category != right.category {
		return left.category < right.category
	}
	return strings.compare(left.key, right.key) < 0
}

@(private)
candidate_history_sort_indices :: proc(state: ^Candidate_History_State, indices: []int) {
	for index in 1 ..< len(indices) {
		current := indices[index]
		position := index
		for position > 0 {
			previous := indices[position - 1]
			if !candidate_history_ascending_less(
				state.entries[current],
				state.entries[previous],
			) {
				break
			}
			indices[position] = previous
			position -= 1
		}
		indices[position] = current
	}
}

@(private)
candidate_history_category_is_valid :: proc(category: Candidate_History_Category) -> bool {
	return category == .Command || category == .Document || category == .Project_File ||
	       category == .Project || category == .Workspace
}

@(private)
candidate_history_key_limit :: proc(category: Candidate_History_Category) -> u64 {
	return u64(MAX_CANDIDATE_COMMAND_KEY_BYTES) if category == .Command else
	       u64(MAX_CANDIDATE_HISTORY_KEY_BYTES)
}

@(private)
candidate_history_key_is_valid :: proc(
	category: Candidate_History_Category,
	key: string,
) -> bool {
	limit := candidate_history_key_limit(category)
	if len(key) == 0 || u64(len(key)) > limit || !utf8.valid_string(key) || strings.contains(key, "\x00") {
		return false
	}
	if category == .Document || category == .Project_File {
		return key[0] == '/'
	}
	if category == .Project || category == .Workspace {
		return candidate_history_project_id_is_valid(key)
	}
	return category == .Command
}

@(private)
candidate_history_project_id_is_valid :: proc(project_id: string) -> bool {
	if len(project_id) == 0 || len(project_id) > int(MAX_DURABLE_ID_BYTES) || !utf8.valid_string(project_id) {
		return false
	}
	previous_hyphen := true
	for byte in transmute([]u8)project_id {
		if byte == '-' {
			if previous_hyphen {
				return false
			}
			previous_hyphen = true
			continue
		}
		if !(byte >= 'a' && byte <= 'z') && !(byte >= '0' && byte <= '9') {
			return false
		}
		previous_hyphen = false
	}
	return !previous_hyphen
}

@(private)
candidate_history_state :: proc(history: ^Candidate_History) -> ^Candidate_History_State {
	if history == nil || history.state == nil {
		return nil
	}
	return (^Candidate_History_State)(history.state)
}

@(private)
candidate_history_state_release :: proc(state: ^Candidate_History_State) {
	if state == nil {
		return
	}
	for &entry in state.entries {
		delete(entry.key, state.allocator)
	}
	if state.index != nil {
		delete(state.index)
	}
	if state.entries != nil {
		delete(state.entries)
	}
	if len(state.project_id) > 0 {
		delete(state.project_id, state.allocator)
	}
	allocator := state.allocator
	free(state, allocator)
}

@(private)
candidate_history_batch_state_release :: proc(state: ^Candidate_History_Batch_State) {
	if state == nil {
		return
	}
	if state.descriptors != nil {
		delete(state.descriptors, state.allocator)
	}
	if state.storage != nil {
		delete(state.storage, state.allocator)
	}
	allocator := state.allocator
	free(state, allocator)
}
