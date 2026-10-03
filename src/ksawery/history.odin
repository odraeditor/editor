// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"

@(private)
History_Observation_Data :: struct {
	descriptor: History_Observation_Descriptor,
	revisions:  [dynamic]Revision_Entry,
	storage:    [dynamic]u8,
	allocator:  runtime.Allocator,
}

/* repository_process_take_history parses one completed bounded History process result. */
repository_process_take_history :: proc(
	process: ^Repository_Process,
	generation: History_Generation,
	allocator := context.allocator,
) -> (History_Observation, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || state.request.kind != .Observe_History {
		return {}, false, .Invalid_Request
	}
	if state.state == .Failed {
		if state.failure == .Output_Limit do return {}, false, .History_Truncated
		if state.request.history.continuation != {} do return {}, false, .History_Continuation_Stale
		return {}, false, state.failure
	}
	if state.state != .Completed do return {}, false, .Invalid_Request
	return history_observation_open(
		state.request.repository,
		generation,
		state.output[:],
		state.request.history,
		allocator,
	)
}

/* history_observation_open parses one bounded first or continued exact-ancestry History result. */
history_observation_open :: proc(
	repository: Repository_Context,
	generation: History_Generation,
	output: []u8,
	request: History_Request,
	allocator := context.allocator,
) -> (History_Observation, bool, Failure_Code) {
	if allocator.procedure == nil || !repository_context_is_valid(repository) ||
	   generation == History_Generation(0) || !history_request_is_valid(request) ||
	   u64(len(output)) > request.limits.temporary_bytes {
		return {}, false, .Invalid_Request
	}
	state, allocation_error := new(History_Observation_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.descriptor.repository = repository
	state.descriptor.generation = generation
	if len(output) == 0 {
		if request.continuation != {} {
			history_observation_data_destroy(state)
			return {}, false, .History_Continuation_Stale
		}
		state.descriptor.state = .Unborn
		if !history_observation_descriptor_is_valid(state.descriptor, request.limits) {
			history_observation_data_destroy(state)
			return {}, false, .Parse
		}
		return History_Observation{state = state}, true, .None
	}
	state.revisions, allocation_error = make(
		[dynamic]Revision_Entry,
		0,
		int(min(request.limits.page_revisions, 64)),
		allocator,
	)
	if allocation_error != nil {
		history_observation_data_destroy(state)
		return {}, false, .Allocation
	}
	state.storage, allocation_error = make(
		[dynamic]u8,
		0,
		int(min(request.limits.metadata_bytes, 16 * KIBIBYTE)),
		allocator,
	)
	if allocation_error != nil {
		history_observation_data_destroy(state)
		return {}, false, .Allocation
	}
	failure := history_observation_parse(state, output, request)
	if failure != .None {
		history_observation_data_destroy(state)
		return {}, false, failure
	}
	state.descriptor.temporary_bytes = u64(len(output))
	if len(state.revisions) == 0 {
		state.descriptor.state = .Exhausted
		state.descriptor.head = request.continuation.head
	} else {
		state.descriptor.state = .Available
		state.descriptor.head = state.revisions[0].identity
		if request.continuation != {} do state.descriptor.head = request.continuation.head
	}
	state.descriptor.revision_count = u32(len(state.revisions))
	state.descriptor.metadata_bytes = u64(len(state.storage))
	state.descriptor.topology_bytes = history_topology_bytes_required(state.descriptor.revision_count)
	if !history_observation_descriptor_is_valid(state.descriptor, request.limits) {
		history_observation_data_destroy(state)
		return {}, false, .Parse
	}
	return History_Observation{state = state}, true, .None
}

/* history_observation_descriptor returns copied immutable History metadata. */
history_observation_descriptor :: proc(
	observation: ^History_Observation,
) -> (History_Observation_Descriptor, bool) {
	state := history_observation_data(observation)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* history_observation_revision_count reports the exact retained History page size. */
history_observation_revision_count :: proc(observation: ^History_Observation) -> (u32, bool) {
	state := history_observation_data(observation)
	if state == nil do return 0, false
	return u32(len(state.revisions)), true
}

/* history_observation_revision returns one copied exact revision in display order. */
history_observation_revision :: proc(
	observation: ^History_Observation,
	ordinal: u32,
) -> (Revision_Entry, bool) {
	state := history_observation_data(observation)
	if state == nil || ordinal >= u32(len(state.revisions)) do return {}, false
	return state.revisions[ordinal], true
}

/* history_observation_text returns borrowed copied metadata for one checked entry text reference. */
history_observation_text :: proc(
	observation: ^History_Observation,
	reference: History_Text_Ref,
) -> ([]u8, bool) {
	state := history_observation_data(observation)
	if state == nil || !history_text_ref_is_valid(reference, u64(len(state.storage))) do return nil, false
	end := u64(reference.offset) + u64(reference.length)
	return state.storage[int(reference.offset):int(end)], true
}

/* history_observation_usage reports exact retained revision and metadata ownership. */
history_observation_usage :: proc(observation: ^History_Observation) -> (History_Usage, bool) {
	state := history_observation_data(observation)
	if state == nil do return {}, false
	return History_Usage {
		revisions = u32(len(state.revisions)),
		parent_links = state.descriptor.parent_links,
		metadata_bytes = u64(len(state.storage)),
		message_bytes = state.descriptor.message_bytes,
		topology_bytes = state.descriptor.topology_bytes,
		temporary_bytes = state.descriptor.temporary_bytes,
		allocation_bytes = u64(size_of(History_Observation_Data)) +
		                   u64(cap(state.revisions)) * u64(size_of(Revision_Entry)) + u64(cap(state.storage)),
	}, true
}

/* history_observation_close releases every owned parsed History allocation. */
history_observation_close :: proc(observation: ^History_Observation) {
	state := history_observation_data(observation)
	if state == nil do return
	history_observation_data_destroy(state)
	observation^ = {}
}

@(private)
history_observation_parse :: proc(
	state: ^History_Observation_Data,
	output: []u8,
	request: History_Request,
) -> Failure_Code {
	if state == nil do return .Invalid_Request
	offset := 0
	records := u32(0)
	retained := u32(0)
	lookahead := false
	for offset < len(output) {
		if output[offset] != 0x1e do return .Parse
		offset += 1
		fields: [8][]u8
		for field_index in 0 ..< len(fields) {
			end := offset
			for end < len(output) && output[end] != 0 do end += 1
			if end == len(output) do return .Parse
			fields[field_index] = output[offset:end]
			offset = end + 1
		}
		if offset < len(output) && output[offset] == '\n' do offset += 1
		entry, parsed, failure := history_entry_parse(fields[:], request.limits)
		if !parsed do return failure
		if request.continuation != {} && records == 0 {
			if entry.identity != request.continuation.after do return .History_Continuation_Stale
			records += 1
			continue
		}
		if retained < request.limits.page_revisions {
			if append_failure := history_observation_append_entry(state, entry, fields[:], request.limits); append_failure != .None {
				return append_failure
			}
			retained += 1
		} else if !lookahead {
			lookahead = true
		} else {
			return .History_Limit
		}
		records += 1
	}
	if request.continuation != {} && records == 0 do return .History_Continuation_Stale
	if lookahead {
		if retained == 0 || request.continuation.skipped > max(u32) - retained {
			return .History_Limit
		}
		last := state.revisions[len(state.revisions) - 1].identity
		head := state.revisions[0].identity
		if request.continuation != {} do head = request.continuation.head
		state.descriptor.continuation = {
			head = head,
			after = last,
			skipped = request.continuation.skipped + retained,
		}
	}
	return .None
}

@(private)
history_entry_parse :: proc(
	fields: []([]u8),
	limits: History_Limits,
) -> (Revision_Entry, bool, Failure_Code) {
	if len(fields) != 8 do return {}, false, .Parse
	entry: Revision_Entry
	if !revision_identity_assign(&entry.identity, string(fields[0])) do return {}, false, .Parse
	if failure := history_entry_parse_parents(&entry, fields[1], limits); failure != .None {
		return {}, false, failure
	}
	if u64(len(fields[7])) > limits.message_bytes do return {}, false, .History_Message_Limit
	return entry, true, .None
}

@(private)
history_entry_parse_parents :: proc(
	entry: ^Revision_Entry,
	field: []u8,
	limits: History_Limits,
) -> Failure_Code {
	if entry == nil do return .Invalid_Request
	offset := 0
	for offset < len(field) {
		if entry.parent_count >= limits.parents do return .Parent_Limit
		end := offset
		for end < len(field) && field[end] != ' ' do end += 1
		if end == offset || !revision_identity_assign(&entry.parents[entry.parent_count], string(field[offset:end])) {
			return .Parse
		}
		entry.parent_count += 1
		if end == len(field) do break
		offset = end + 1
		if offset == len(field) do return .Parse
	}
	return .None
}

@(private)
history_observation_append_entry :: proc(
	state: ^History_Observation_Data,
	entry: Revision_Entry,
	fields: []([]u8),
	limits: History_Limits,
) -> Failure_Code {
	if state == nil || len(fields) != 8 || u32(len(state.revisions)) >= limits.page_revisions {
		return .History_Limit
	}
	stored := entry
	if failure := history_observation_append_text(state, &stored.author_name, fields[2], limits.metadata_bytes); failure != .None {
		return failure
	}
	if failure := history_observation_append_text(state, &stored.author_email, fields[3], limits.metadata_bytes); failure != .None {
		return failure
	}
	if failure := history_observation_append_text(state, &stored.authored_at, fields[4], limits.metadata_bytes); failure != .None {
		return failure
	}
	if failure := history_observation_append_text(state, &stored.committed_at, fields[5], limits.metadata_bytes); failure != .None {
		return failure
	}
	if failure := history_observation_append_text(state, &stored.subject, fields[6], limits.metadata_bytes); failure != .None {
		return failure
	}
	if failure := history_observation_append_text(state, &stored.message, fields[7], limits.metadata_bytes); failure != .None {
		return failure
	}
	if !revision_entry_is_valid(stored, u64(len(state.storage)), limits) do return .Parse
	_, allocation_error := append(&state.revisions, stored)
	if allocation_error != nil do return .Allocation
	state.descriptor.parent_links += u32(stored.parent_count)
	state.descriptor.message_bytes += u64(stored.message.length)
	return .None
}

@(private)
history_observation_append_text :: proc(
	state: ^History_Observation_Data,
	reference: ^History_Text_Ref,
	text: []u8,
	limit: u64,
) -> Failure_Code {
	if state == nil || reference == nil || u64(len(state.storage)) + u64(len(text)) > limit {
		return .History_Metadata_Limit
	}
	reference^ = {offset = u32(len(state.storage)), length = u32(len(text))}
	if len(text) == 0 do return .None
	_, allocation_error := append(&state.storage, ..text)
	if allocation_error != nil do return .Allocation
	return .None
}

@(private)
history_observation_data :: proc(observation: ^History_Observation) -> ^History_Observation_Data {
	if observation == nil || observation.state == nil do return nil
	return cast(^History_Observation_Data)observation.state
}

@(private)
history_observation_data_destroy :: proc(state: ^History_Observation_Data) {
	if state == nil do return
	delete(state.revisions)
	delete(state.storage)
	free(state, state.allocator)
}
