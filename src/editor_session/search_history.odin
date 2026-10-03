// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor_session

import "../search"
import "core:unicode/utf8"

/* session_search_history_accept retains one accepted query by recency. */
session_search_history_accept :: proc(
	session: ^Session,
	handle: Session_Handle,
	kind: search.Pattern_Kind,
	pattern: string,
	policy: search.Policy,
) -> (ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect)
	if resolved_failure.code != .None {
		return false, resolved_failure
	}
	if !search_history_input_is_valid(kind, pattern, policy) {
		return false, session_failure(data, .Inspect, .Invalid_Policy)
	}
	if u64(len(pattern)) > DEFAULT_SEARCH_HISTORY_BYTES {
		failure = session_failure(data, .Inspect, .Persistent_Memory_Limit)
		failure.maximum = DEFAULT_SEARCH_HISTORY_BYTES
		failure.actual = u64(len(pattern))
		return false, failure
	}
	copied, copy_error := make([]u8, len(pattern), data.allocator)
	if copy_error != nil {
		return false, session_failure(data, .Inspect, .Persistent_Memory_Limit)
	}
	copy(copied, transmute([]u8)pattern)

	duplicate := -1
	for index in 0 ..< data.search_history_count {
		entry := &data.search_history_entries[index]
		if entry.kind == kind && string(entry.pattern) == pattern {
			duplicate = index
			break
		}
	}
	if duplicate >= 0 {
		search_history_remove(data, duplicate)
	}
	for data.search_history_count >= len(data.search_history_entries) ||
	    data.search_history_bytes + u64(len(copied)) > DEFAULT_SEARCH_HISTORY_BYTES {
		assert(data.search_history_count > 0)
		search_history_remove(data, data.search_history_count - 1)
	}
	for index := data.search_history_count; index > 0; index -= 1 {
		data.search_history_entries[index] = data.search_history_entries[index - 1]
	}
	data.search_history_entries[0] = Search_History_Entry {
		kind = kind,
		pattern = copied,
		policy = policy,
	}
	data.search_history_count += 1
	data.search_history_bytes += u64(len(copied))
	assert(session_search_history_validate(data))
	return true, {}
}

/* session_search_history_begin captures the live query before history recall. */
session_search_history_begin :: proc(
	session: ^Session,
	handle: Session_Handle,
	kind: search.Pattern_Kind,
	in_progress: string,
) -> (ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect)
	if resolved_failure.code != .None {
		return false, resolved_failure
	}
	if (kind != .Literal && kind != .Regular_Expression) ||
	   !utf8.valid_string(in_progress) ||
	   u64(len(in_progress)) > search.DEFAULT_PATTERN_BYTES {
		return false, session_failure(data, .Inspect, .Invalid_Policy)
	}
	copied, copy_error := make([]u8, len(in_progress), data.allocator)
	if copy_error != nil {
		return false, session_failure(data, .Inspect, .Persistent_Memory_Limit)
	}
	copy(copied, transmute([]u8)in_progress)
	delete(data.search_history_navigation.in_progress, data.allocator)
	data.search_history_navigation = Search_History_Navigation {
		active = true,
		kind = kind,
		cursor = -1,
		in_progress = copied,
	}
	assert(session_search_history_validate(data))
	return true, {}
}

/* session_search_history_older recalls the next compatible older query. */
session_search_history_older :: proc(
	session: ^Session,
	handle: Session_Handle,
) -> (recall: Search_History_Recall, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	navigation := &data.search_history_navigation
	if !navigation.active {
		return {}, false, session_failure(data, .Inspect, .Invalid_Policy)
	}
	for index := navigation.cursor + 1; index < data.search_history_count; index += 1 {
		entry := &data.search_history_entries[index]
		if entry.kind != navigation.kind {
			continue
		}
		navigation.cursor = index
		return search_history_recall(entry, false), true, {}
	}
	return {}, true, {}
}

/* session_search_history_newer recalls a newer query or restores live input. */
session_search_history_newer :: proc(
	session: ^Session,
	handle: Session_Handle,
) -> (recall: Search_History_Recall, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	navigation := &data.search_history_navigation
	if !navigation.active {
		return {}, false, session_failure(data, .Inspect, .Invalid_Policy)
	}
	if navigation.cursor < 0 {
		return {}, true, {}
	}
	for index := navigation.cursor - 1; index >= 0; index -= 1 {
		entry := &data.search_history_entries[index]
		if entry.kind != navigation.kind {
			continue
		}
		navigation.cursor = index
		return search_history_recall(entry, false), true, {}
	}
	navigation.cursor = -1
	return Search_History_Recall {
		present = true,
		restored_in_progress = true,
		descriptor = Search_History_Descriptor {
			kind = navigation.kind,
			pattern = string(navigation.in_progress),
		},
	}, true, {}
}

/* session_search_history_end releases navigation-only input. */
session_search_history_end :: proc(
	session: ^Session,
	handle: Session_Handle,
) -> (ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect)
	if resolved_failure.code != .None {
		return false, resolved_failure
	}
	delete(data.search_history_navigation.in_progress, data.allocator)
	data.search_history_navigation = {}
	assert(session_search_history_validate(data))
	return true, {}
}

/* session_search_history_descriptors copies compatible entries by recency. */
session_search_history_descriptors :: proc(
	session: ^Session,
	handle: Session_Handle,
	kind: search.Pattern_Kind,
	allocator := context.allocator,
) -> (batch: Search_History_Batch, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	if kind != .Literal && kind != .Regular_Expression {
		return {}, false, session_failure(data, .Inspect, .Invalid_Policy)
	}
	count := 0
	text_bytes := 0
	for index in 0 ..< data.search_history_count {
		entry := &data.search_history_entries[index]
		if entry.kind == kind {
			count += 1
			text_bytes += len(entry.pattern)
		}
	}
	state, state_error := new(Search_History_Batch_State, allocator)
	if state_error != nil {
		return {}, false, session_failure(data, .Inspect, .Persistent_Memory_Limit)
	}
	state.allocator = allocator
	state.descriptors, state_error = make([]Search_History_Descriptor, count, allocator)
	if state_error != nil {
		free(state, allocator)
		return {}, false, session_failure(data, .Inspect, .Persistent_Memory_Limit)
	}
	state.patterns, state_error = make([]u8, text_bytes, allocator)
	if state_error != nil {
		delete(state.descriptors, allocator)
		free(state, allocator)
		return {}, false, session_failure(data, .Inspect, .Persistent_Memory_Limit)
	}
	descriptor_index := 0
	text_offset := 0
	for index in 0 ..< data.search_history_count {
		entry := &data.search_history_entries[index]
		if entry.kind != kind {
			continue
		}
		copy(state.patterns[text_offset:], entry.pattern)
		state.descriptors[descriptor_index] = Search_History_Descriptor {
			kind = entry.kind,
			pattern = string(state.patterns[text_offset:text_offset + len(entry.pattern)]),
			policy = entry.policy,
		}
		text_offset += len(entry.pattern)
		descriptor_index += 1
	}
	batch.state = state
	batch.descriptors = state.descriptors
	return batch, true, {}
}

/* search_history_batch_close releases one copied history inspection. */
search_history_batch_close :: proc(batch: ^Search_History_Batch) -> bool {
	if batch == nil || batch.state == nil {
		return false
	}
	state := (^Search_History_Batch_State)(batch.state)
	delete(state.patterns, state.allocator)
	delete(state.descriptors, state.allocator)
	allocator := state.allocator
	free(state, allocator)
	batch^ = {}
	return true
}

@(private)
search_history_recall :: proc(entry: ^Search_History_Entry, restored: bool) -> Search_History_Recall {
	return Search_History_Recall {
		present = true,
		restored_in_progress = restored,
		descriptor = Search_History_Descriptor {
			kind = entry.kind,
			pattern = string(entry.pattern),
			policy = entry.policy,
		},
	}
}

@(private)
search_history_input_is_valid :: proc(
	kind: search.Pattern_Kind,
	pattern: string,
	policy: search.Policy,
) -> bool {
	return (kind == .Literal || kind == .Regular_Expression) &&
	       len(pattern) > 0 && utf8.valid_string(pattern) &&
	       u64(len(pattern)) <= search.DEFAULT_PATTERN_BYTES &&
	       (policy.case_mode == .Smart || policy.case_mode == .Sensitive ||
	        policy.case_mode == .Insensitive) &&
	       (policy.boundary_mode == .Unrestricted || policy.boundary_mode == .Word ||
	        policy.boundary_mode == .Symbol) &&
	       (policy.whitespace_mode == .Exact || policy.whitespace_mode == .Flexible)
}

@(private)
search_history_remove :: proc(data: ^Session_Data, index: int) {
	assert(data != nil && index >= 0 && index < data.search_history_count)
	entry := &data.search_history_entries[index]
	data.search_history_bytes -= u64(len(entry.pattern))
	delete(entry.pattern, data.allocator)
	for current := index; current + 1 < data.search_history_count; current += 1 {
		data.search_history_entries[current] = data.search_history_entries[current + 1]
	}
	data.search_history_count -= 1
	data.search_history_entries[data.search_history_count] = {}
}

@(private)
session_search_history_clear :: proc(data: ^Session_Data) {
	if data == nil {
		return
	}
	for data.search_history_count > 0 {
		search_history_remove(data, data.search_history_count - 1)
	}
	delete(data.search_history_navigation.in_progress, data.allocator)
	data.search_history_navigation = {}
}

@(private)
session_search_history_validate :: proc(data: ^Session_Data) -> bool {
	if data == nil || len(data.search_history_entries) != int(DEFAULT_SEARCH_HISTORY_ENTRIES) ||
	   data.search_history_count < 0 ||
	   data.search_history_count > len(data.search_history_entries) ||
	   data.search_history_bytes > DEFAULT_SEARCH_HISTORY_BYTES {
		return false
	}
	measured_bytes: u64
	for index in 0 ..< data.search_history_count {
		entry := &data.search_history_entries[index]
		if !search_history_input_is_valid(entry.kind, string(entry.pattern), entry.policy) {
			return false
		}
		measured_bytes += u64(len(entry.pattern))
		for previous in data.search_history_entries[:index] {
			if previous.kind == entry.kind && string(previous.pattern) == string(entry.pattern) {
				return false
			}
		}
	}
	for entry in data.search_history_entries[data.search_history_count:] {
		if entry.kind != .Invalid || entry.pattern != nil {
			return false
		}
	}
	if measured_bytes != data.search_history_bytes {
		return false
	}
	navigation := &data.search_history_navigation
	if !navigation.active {
		return navigation.kind == .Invalid && navigation.in_progress == nil
	}
	return (navigation.kind == .Literal || navigation.kind == .Regular_Expression) &&
	       navigation.cursor >= -1 && navigation.cursor < data.search_history_count &&
	       utf8.valid_string(string(navigation.in_progress)) &&
	       u64(len(navigation.in_progress)) <= search.DEFAULT_PATTERN_BYTES
}
