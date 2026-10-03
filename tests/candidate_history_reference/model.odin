// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package candidate_history_reference provides an independent bounded usage-history model.
package candidate_history_reference

import "core:strings"
import "core:unicode/utf8"
import "base:runtime"

MAX_PROJECT_ID_BYTES :: 128
SELECTED_ENTRIES :: 1_024
SELECTED_KEY_BYTES :: 4 * 1_024
SELECTED_MODULE_BYTES :: 8 * 1_024 * 1_024
SELECTED_SEQUENCE_CEILING :: u64(9_223_372_036_854_775_807)
SELECTED_DIRTY_GENERATIONS :: 1
SELECTED_FLUSH_EVENTS :: 16
SELECTED_RETRIES :: 1
SELECTED_CALLBACKS :: 8

Category :: enum u8 {
	Invalid,
	Command,
	Document,
	Project_File,
}

Entry :: struct {
	category: Category,
	key:      string,
	sequence: u64,
	live:     bool,
}

Limits :: struct {
	entries:          int,
	key_bytes:        int,
	module_bytes:     int,
	sequence_ceiling: u64,
	dirty_generations: int,
	flush_events:     int,
	retries:          int,
	callbacks:        int,
}

DEFAULT_LIMITS :: Limits {
	entries = SELECTED_ENTRIES,
	key_bytes = SELECTED_KEY_BYTES,
	module_bytes = SELECTED_MODULE_BYTES,
	sequence_ceiling = SELECTED_SEQUENCE_CEILING,
	dirty_generations = SELECTED_DIRTY_GENERATIONS,
	flush_events = SELECTED_FLUSH_EVENTS,
	retries = SELECTED_RETRIES,
	callbacks = SELECTED_CALLBACKS,
}

State :: struct {
	project_id:         string,
	entries:            []Entry,
	active_count:       int,
	generation:         u64,
	next_sequence:      u64,
	dirty_generation:   u64,
	events_since_flush: int,
	retry_count:        int,
	limits:             Limits,
	allocator:          runtime.Allocator,
}

Failure_Code :: enum u8 {
	None,
	Invalid_State,
	Invalid_Project,
	Invalid_Category,
	Invalid_Key,
	Entry_Limit,
	Module_Limit,
	Sequence_Limit,
	Stale_Generation,
	Retry_Exhausted,
	Allocation,
}

Failure :: struct {
	code:   Failure_Code,
	limit:  u64,
	actual: u64,
}

state_init :: proc(
	project_id: string,
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
) -> (state: State, ok: bool, failure: Failure) {
	if !project_id_valid(project_id) {
		return {}, false, Failure{code = .Invalid_Project, limit = MAX_PROJECT_ID_BYTES, actual = u64(len(project_id))}
	}
	if !limits_valid(limits) || allocator.procedure == nil {
		return {}, false, Failure{code = .Invalid_State}
	}
	owned_id, id_error := strings.clone(project_id, allocator)
	if id_error != nil {
		return {}, false, Failure{code = .Allocation}
	}
	entries, entries_error := make([]Entry, limits.entries, allocator)
	if entries_error != nil {
		delete(owned_id, allocator)
		return {}, false, Failure{code = .Allocation}
	}
	return State {
		project_id = owned_id,
		entries = entries,
		generation = 1,
		next_sequence = 1,
		limits = limits,
		allocator = allocator,
	}, true, {}
}

state_destroy :: proc(state: ^State) {
	if state == nil {
		return
	}
	for &entry in state.entries {
		if entry.live {
			delete(entry.key, state.allocator)
		}
	}
	if state.entries != nil {
		delete(state.entries, state.allocator)
	}
	if len(state.project_id) > 0 {
		delete(state.project_id, state.allocator)
	}
	state^ = {}
}

record_success :: proc(
	state: ^State,
	category: Category,
	key: string,
) -> (sequence: u64, ok: bool, failure: Failure) {
	if !state_ready(state) {
		return 0, false, Failure{code = .Invalid_State}
	}
	if !category_valid(category) {
		return 0, false, Failure{code = .Invalid_Category}
	}
	if !key_valid(category, key, state.limits.key_bytes) {
		return 0, false, Failure{code = .Invalid_Key, limit = u64(state.limits.key_bytes), actual = u64(len(key))}
	}
	if state.next_sequence >= state.limits.sequence_ceiling {
		if !renormalize(state) {
			return 0, false, Failure{code = .Sequence_Limit, limit = state.limits.sequence_ceiling, actual = state.next_sequence}
		}
	}
	index := find_entry(state, category, key)
	if index < 0 {
		owned_key, key_error := strings.clone(key, state.allocator)
		if key_error != nil {
			return 0, false, Failure{code = .Allocation}
		}
		index = find_free_entry(state)
		if index < 0 {
			index = least_recent_entry(state)
		}
		entry := &state.entries[index]
		if entry.live {
			delete(entry.key, state.allocator)
		} else {
			state.active_count += 1
		}
		entry^ = Entry{category = category, key = owned_key, live = true}
	}
	sequence = state.next_sequence
	state.entries[index].sequence = sequence
	state.next_sequence += 1
	state.dirty_generation += 1
	state.events_since_flush = min(state.events_since_flush + 1, state.limits.flush_events)
	return sequence, true, {}
}

lookup :: proc(state: ^State, category: Category, key: string) -> (u64, bool) {
	index := find_entry(state, category, key)
	if index < 0 {
		return 0, false
	}
	return state.entries[index].sequence, true
}

canonical_indices :: proc(state: ^State, output: []int) -> (count: int, ok: bool) {
	if !state_ready(state) || len(output) < state.active_count {
		return 0, false
	}
	for entry, index in state.entries {
		if entry.live {
			output[count] = index
			count += 1
		}
	}
	sort_indices(state, output[:count], false)
	return count, true
}

estimated_module_bytes :: proc(state: ^State) -> (bytes: u64, ok: bool) {
	if !state_ready(state) {
		return 0, false
	}
	bytes = 192 + u64(len(state.project_id))
	for entry in state.entries {
		if !entry.live {
			continue
		}
		entry_bytes := u64(96 + len(entry.key))
		if bytes > u64(state.limits.module_bytes) - min(entry_bytes, u64(state.limits.module_bytes)) {
			return bytes + entry_bytes, false
		}
		bytes += entry_bytes
	}
	return bytes, bytes <= u64(state.limits.module_bytes)
}

flush_due :: proc(state: ^State) -> bool {
	return state_ready(state) && state.dirty_generation > 0 &&
	       state.events_since_flush >= state.limits.flush_events
}

mark_flushed :: proc(
	state: ^State,
	expected_dirty_generation: u64,
	published_generation: u64,
) -> (ok: bool, failure: Failure) {
	if !state_ready(state) {
		return false, Failure{code = .Invalid_State}
	}
	if state.dirty_generation == 0 || expected_dirty_generation != state.dirty_generation ||
	   published_generation != state.generation + 1 {
		return false, Failure{code = .Stale_Generation}
	}
	state.generation = published_generation
	state.dirty_generation = 0
	state.events_since_flush = 0
	state.retry_count = 0
	return true, {}
}

note_flush_failure :: proc(state: ^State) -> (retry: bool, failure: Failure) {
	if !state_ready(state) {
		return false, Failure{code = .Invalid_State}
	}
	if state.retry_count >= state.limits.retries {
		return false, Failure{code = .Retry_Exhausted, limit = u64(state.limits.retries), actual = u64(state.retry_count + 1)}
	}
	state.retry_count += 1
	return true, {}
}

@(private)
renormalize :: proc(state: ^State) -> bool {
	if state.active_count + 2 >= int(state.limits.sequence_ceiling) {
		return false
	}
	indices, indices_error := make([]int, state.active_count, context.temp_allocator)
	if indices_error != nil {
		return false
	}
	defer delete(indices, context.temp_allocator)
	count := 0
	for entry, index in state.entries {
		if entry.live {
			indices[count] = index
			count += 1
		}
	}
	sort_indices(state, indices, true)
	for index, order in indices {
		state.entries[order].sequence = u64(index + 1)
	}
	state.next_sequence = u64(state.active_count + 1)
	return true
}

@(private)
find_entry :: proc(state: ^State, category: Category, key: string) -> int {
	if !state_ready(state) {
		return -1
	}
	for entry, index in state.entries {
		if entry.live && entry.category == category && entry.key == key {
			return index
		}
	}
	return -1
}

@(private)
find_free_entry :: proc(state: ^State) -> int {
	for entry, index in state.entries {
		if !entry.live {
			return index
		}
	}
	return -1
}

@(private)
least_recent_entry :: proc(state: ^State) -> int {
	selected := -1
	for entry, index in state.entries {
		if !entry.live {
			continue
		}
		if selected < 0 || ascending_less(entry, state.entries[selected]) {
			selected = index
		}
	}
	return selected
}

@(private)
ascending_less :: proc(left, right: Entry) -> bool {
	if left.sequence != right.sequence {
		return left.sequence < right.sequence
	}
	if left.category != right.category {
		return left.category < right.category
	}
	return strings.compare(left.key, right.key) < 0
}

@(private)
canonical_less :: proc(left, right: Entry) -> bool {
	if left.sequence != right.sequence {
		return left.sequence > right.sequence
	}
	if left.category != right.category {
		return left.category < right.category
	}
	return strings.compare(left.key, right.key) < 0
}

@(private)
sort_indices :: proc(state: ^State, indices: []int, ascending: bool) {
	for index in 1 ..< len(indices) {
		current := indices[index]
		position := index
		for position > 0 {
			previous := indices[position - 1]
			before := canonical_less(state.entries[current], state.entries[previous])
			if ascending {
				before = ascending_less(state.entries[current], state.entries[previous])
			}
			if !before {
				break
			}
			indices[position] = previous
			position -= 1
		}
		indices[position] = current
	}
}

@(private)
state_ready :: proc(state: ^State) -> bool {
	return state != nil && len(state.project_id) > 0 && state.entries != nil &&
	       state.generation > 0 && state.next_sequence > 0 && limits_valid(state.limits)
}

@(private)
limits_valid :: proc(limits: Limits) -> bool {
	return limits.entries > 0 && limits.key_bytes > 0 && limits.module_bytes > 0 &&
	       limits.sequence_ceiling > u64(limits.entries + 2) &&
	       limits.dirty_generations == 1 && limits.flush_events > 0 &&
	       limits.retries >= 0 && limits.callbacks > 0
}

@(private)
project_id_valid :: proc(project_id: string) -> bool {
	if len(project_id) == 0 || len(project_id) > MAX_PROJECT_ID_BYTES || !utf8.valid_string(project_id) {
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
category_valid :: proc(category: Category) -> bool {
	return category == .Command || category == .Document || category == .Project_File
}

@(private)
key_valid :: proc(category: Category, key: string, limit: int) -> bool {
	if len(key) == 0 || len(key) > limit || !utf8.valid_string(key) || strings.contains(key, "\x00") {
		return false
	}
	if category == .Document || category == .Project_File {
		return key[0] == '/'
	}
	return category == .Command
}
