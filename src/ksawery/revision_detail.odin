// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"

@(private)
Revision_Comparison_Data :: struct {
	paths:     [dynamic]Revision_Changed_Path,
	storage:   [dynamic]u8,
	diff:      [dynamic]u8,
	allocator: runtime.Allocator,
}

@(private)
Revision_Detail_Data :: struct {
	request:    Revision_Detail_Request,
	descriptor: Revision_Detail_Descriptor,
	metadata:   [dynamic]u8,
	comparison: Revision_Comparison_Data,
	allocator:  runtime.Allocator,
}

@(private)
Revision_Range_Observation_Data :: struct {
	request:    Revision_Range_Request,
	descriptor: Revision_Range_Observation_Descriptor,
	summaries:  [dynamic]Revision_Range_Summary,
	storage:    [dynamic]u8,
	comparison: Revision_Comparison_Data,
	allocator:  runtime.Allocator,
}

/* revision_detail_open parses bounded metadata and an explicit-parent comparison for one exact revision. */
revision_detail_open :: proc(
	repository: Repository_Context,
	request: Revision_Detail_Request,
	metadata: []u8,
	comparison: []u8,
	comparison_truncated: bool,
	allocator := context.allocator,
) -> (Revision_Detail, bool, Failure_Code) {
	if allocator.procedure == nil || !repository_context_is_valid(repository) ||
	   !revision_detail_request_is_valid(request) ||
	   u64(len(comparison)) > request.limits.changed_path_bytes + request.limits.diff_bytes {
		return {}, false, .Invalid_Request
	}
	state, allocation_error := new(Revision_Detail_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = request
	state.metadata, allocation_error = make(
		[dynamic]u8,
		0,
		int(min(request.limits.metadata_bytes, 16 * KIBIBYTE)),
		allocator,
	)
	if allocation_error == nil {
		allocation_error = revision_comparison_data_init(
			&state.comparison,
			request.limits.changed_paths,
			request.limits.changed_path_bytes,
			request.limits.diff_bytes,
			allocator,
		)
	}
	if allocation_error != nil {
		revision_detail_data_destroy(state)
		return {}, false, .Allocation
	}
	failure := revision_detail_parse_metadata(state, repository, metadata)
	if failure == .None {
		failure = revision_comparison_data_parse(
			&state.comparison,
			comparison,
			request.limits.changed_path_bytes,
			request.limits.diff_bytes,
			comparison_truncated,
		)
	}
	if failure != .None {
		revision_detail_data_destroy(state)
		return {}, false, failure
	}
	state.descriptor.changed_paths = u32(len(state.comparison.paths))
	state.descriptor.metadata_bytes = u64(len(state.metadata))
	state.descriptor.changed_path_bytes = u64(len(state.comparison.storage))
	state.descriptor.diff_bytes = u64(len(state.comparison.diff))
	state.descriptor.temporary_bytes = state.descriptor.metadata_bytes +
	                                   state.descriptor.changed_path_bytes + state.descriptor.diff_bytes
	state.descriptor.truncated = comparison_truncated
	if !revision_detail_descriptor_is_valid(state.descriptor, request.limits) {
		revision_detail_data_destroy(state)
		return {}, false, .Parse
	}
	return Revision_Detail{state = state}, true, .None
}

/* revision_detail_descriptor returns copied immutable revision-detail metadata. */
revision_detail_descriptor :: proc(detail: ^Revision_Detail) -> (Revision_Detail_Descriptor, bool) {
	state := revision_detail_data(detail)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* revision_detail_text returns borrowed result-owned metadata text. */
revision_detail_text :: proc(detail: ^Revision_Detail, reference: Revision_Text_Ref) -> ([]u8, bool) {
	state := revision_detail_data(detail)
	if state == nil || !revision_text_ref_is_valid(reference, u64(len(state.metadata))) do return nil, false
	end := int(u64(reference.offset) + u64(reference.length))
	return state.metadata[int(reference.offset):end], true
}

/* revision_detail_changed_path returns one copied changed-path summary in source order. */
revision_detail_changed_path :: proc(detail: ^Revision_Detail, ordinal: u32) -> (Revision_Changed_Path, bool) {
	state := revision_detail_data(detail)
	if state == nil || ordinal >= u32(len(state.comparison.paths)) do return {}, false
	return state.comparison.paths[ordinal], true
}

/* revision_detail_changed_path_text returns borrowed result-owned changed-path text. */
revision_detail_changed_path_text :: proc(
	detail: ^Revision_Detail,
	reference: Revision_Text_Ref,
) -> ([]u8, bool) {
	state := revision_detail_data(detail)
	if state == nil || !revision_text_ref_is_valid(reference, u64(len(state.comparison.storage))) do return nil, false
	end := int(u64(reference.offset) + u64(reference.length))
	return state.comparison.storage[int(reference.offset):end], true
}

/* revision_detail_diff returns borrowed bounded read-only comparison bytes. */
revision_detail_diff :: proc(detail: ^Revision_Detail) -> ([]u8, bool) {
	state := revision_detail_data(detail)
	if state == nil do return nil, false
	return state.comparison.diff[:], true
}

/* revision_detail_usage reports exact retained detail resources. */
revision_detail_usage :: proc(detail: ^Revision_Detail) -> (Revision_Inspection_Usage, bool) {
	state := revision_detail_data(detail)
	if state == nil do return {}, false
	return Revision_Inspection_Usage {
		parents = u32(state.descriptor.parent_count),
		changed_paths = u32(len(state.comparison.paths)),
		metadata_bytes = u64(len(state.metadata)),
		message_bytes = state.descriptor.message_bytes,
		signature_bytes = state.descriptor.signature_bytes,
		changed_path_bytes = u64(len(state.comparison.storage)),
		diff_bytes = u64(len(state.comparison.diff)),
		temporary_bytes = state.descriptor.temporary_bytes,
		allocation_bytes = u64(size_of(Revision_Detail_Data)) + u64(cap(state.metadata)) +
		                   revision_comparison_data_allocation_bytes(&state.comparison),
	}, true
}

/* revision_detail_is_current rejects a detail after its exact History generation or parent relation is stale. */
revision_detail_is_current :: proc(detail: ^Revision_Detail, observation: ^History_Observation) -> bool {
	state := revision_detail_data(detail)
	if state == nil do return false
	_, current, _ := revision_detail_request_revalidate(observation, state.request)
	return current
}

/* revision_detail_close releases every owned detail allocation. */
revision_detail_close :: proc(detail: ^Revision_Detail) {
	state := revision_detail_data(detail)
	if state == nil do return
	revision_detail_data_destroy(state)
	detail^ = {}
}

/* revision_range_observation_open parses bounded summaries and a base-to-target comparison. */
revision_range_observation_open :: proc(
	repository: Repository_Context,
	request: Revision_Range_Request,
	summary: []u8,
	comparison: []u8,
	comparison_truncated: bool,
	allocator := context.allocator,
) -> (Revision_Range_Observation, bool, Failure_Code) {
	if allocator.procedure == nil || !repository_context_is_valid(repository) ||
	   !revision_range_request_is_valid(request) ||
	   u64(len(comparison)) > request.limits.changed_path_bytes + request.limits.diff_bytes {
		return {}, false, .Invalid_Request
	}
	state, allocation_error := new(Revision_Range_Observation_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.request = request
	state.summaries, allocation_error = make(
		[dynamic]Revision_Range_Summary,
		0,
		int(min(request.limits.revisions, 32)),
		allocator,
	)
	if allocation_error == nil {
		state.storage, allocation_error = make(
			[dynamic]u8,
			0,
			int(min(request.limits.summary_bytes, 16 * KIBIBYTE)),
			allocator,
		)
	}
	if allocation_error == nil {
		allocation_error = revision_comparison_data_init(
			&state.comparison,
			request.limits.changed_paths,
			request.limits.changed_path_bytes,
			request.limits.diff_bytes,
			allocator,
		)
	}
	if allocation_error != nil {
		revision_range_observation_data_destroy(state)
		return {}, false, .Allocation
	}
	failure := revision_range_observation_parse_summary(state, summary)
	if failure == .None {
		failure = revision_comparison_data_parse(
			&state.comparison,
			comparison,
			request.limits.changed_path_bytes,
			request.limits.diff_bytes,
			comparison_truncated,
		)
	}
	if failure != .None {
		revision_range_observation_data_destroy(state)
		return {}, false, failure
	}
	state.descriptor = {
		repository = repository,
		range = request.range,
		revision_count = u32(len(state.summaries)),
		changed_paths = u32(len(state.comparison.paths)),
		summary_bytes = u64(len(state.storage)),
		changed_path_bytes = u64(len(state.comparison.storage)),
		diff_bytes = u64(len(state.comparison.diff)),
		temporary_bytes = u64(len(state.storage)) + u64(len(state.comparison.storage)) +
		                  u64(len(state.comparison.diff)),
		truncated = comparison_truncated,
	}
	if !revision_range_observation_descriptor_is_valid(state.descriptor, request.limits) {
		revision_range_observation_data_destroy(state)
		return {}, false, .Parse
	}
	return Revision_Range_Observation{state = state}, true, .None
}

/* revision_range_observation_descriptor returns copied immutable range metadata. */
revision_range_observation_descriptor :: proc(
	observation: ^Revision_Range_Observation,
) -> (Revision_Range_Observation_Descriptor, bool) {
	state := revision_range_observation_data(observation)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* revision_range_observation_summary returns one copied exact range summary. */
revision_range_observation_summary :: proc(
	observation: ^Revision_Range_Observation,
	ordinal: u32,
) -> (Revision_Range_Summary, bool) {
	state := revision_range_observation_data(observation)
	if state == nil || ordinal >= u32(len(state.summaries)) do return {}, false
	return state.summaries[ordinal], true
}

/* revision_range_observation_text returns borrowed result-owned range-summary text. */
revision_range_observation_text :: proc(
	observation: ^Revision_Range_Observation,
	reference: Revision_Text_Ref,
) -> ([]u8, bool) {
	state := revision_range_observation_data(observation)
	if state == nil || !revision_text_ref_is_valid(reference, u64(len(state.storage))) do return nil, false
	end := int(u64(reference.offset) + u64(reference.length))
	return state.storage[int(reference.offset):end], true
}

/* revision_range_observation_changed_path returns one copied range changed-path summary. */
revision_range_observation_changed_path :: proc(
	observation: ^Revision_Range_Observation,
	ordinal: u32,
) -> (Revision_Changed_Path, bool) {
	state := revision_range_observation_data(observation)
	if state == nil || ordinal >= u32(len(state.comparison.paths)) do return {}, false
	return state.comparison.paths[ordinal], true
}

/* revision_range_observation_changed_path_text returns borrowed range changed-path text. */
revision_range_observation_changed_path_text :: proc(
	observation: ^Revision_Range_Observation,
	reference: Revision_Text_Ref,
) -> ([]u8, bool) {
	state := revision_range_observation_data(observation)
	if state == nil || !revision_text_ref_is_valid(reference, u64(len(state.comparison.storage))) do return nil, false
	end := int(u64(reference.offset) + u64(reference.length))
	return state.comparison.storage[int(reference.offset):end], true
}

/* revision_range_observation_diff returns borrowed bounded base-to-target comparison bytes. */
revision_range_observation_diff :: proc(observation: ^Revision_Range_Observation) -> ([]u8, bool) {
	state := revision_range_observation_data(observation)
	if state == nil do return nil, false
	return state.comparison.diff[:], true
}

/* revision_range_observation_usage reports exact retained range resources. */
revision_range_observation_usage :: proc(
	observation: ^Revision_Range_Observation,
) -> (Revision_Inspection_Usage, bool) {
	state := revision_range_observation_data(observation)
	if state == nil do return {}, false
	return Revision_Inspection_Usage {
		range_revisions = u32(len(state.summaries)),
		changed_paths = u32(len(state.comparison.paths)),
		summary_bytes = u64(len(state.storage)),
		changed_path_bytes = u64(len(state.comparison.storage)),
		diff_bytes = u64(len(state.comparison.diff)),
		temporary_bytes = state.descriptor.temporary_bytes,
		allocation_bytes = u64(size_of(Revision_Range_Observation_Data)) +
		                   u64(cap(state.summaries)) * u64(size_of(Revision_Range_Summary)) + u64(cap(state.storage)) +
		                   revision_comparison_data_allocation_bytes(&state.comparison),
	}, true
}

/* revision_range_observation_is_current rejects a range after its History generation becomes stale. */
revision_range_observation_is_current :: proc(
	observation: ^Revision_Range_Observation,
	history: ^History_Observation,
) -> bool {
	state := revision_range_observation_data(observation)
	if state == nil do return false
	current, _ := revision_range_request_revalidate(history, state.request)
	return current
}

/* revision_range_observation_close releases every owned range allocation. */
revision_range_observation_close :: proc(observation: ^Revision_Range_Observation) {
	state := revision_range_observation_data(observation)
	if state == nil do return
	revision_range_observation_data_destroy(state)
	observation^ = {}
}

@(private)
revision_detail_parse_metadata :: proc(
	state: ^Revision_Detail_Data,
	repository: Repository_Context,
	output: []u8,
) -> Failure_Code {
	if state == nil || len(output) == 0 || output[0] != 0x1e do return .Parse
	cursor := 1
	fields: [12][]u8
	for field_index in 0 ..< len(fields) {
		field, next, found := revision_take_nul_field(output, cursor)
		if !found do return .Parse
		fields[field_index] = field
		cursor = next
	}
	if cursor < len(output) && output[cursor] == '\n' do cursor += 1
	if cursor != len(output) do return .Parse
	if !revision_identity_assign(&state.descriptor.target.revision, string(fields[0])) ||
	   state.descriptor.target.revision != state.request.target.revision {
		return .Parse
	}
	state.descriptor.repository = repository
	state.descriptor.target.generation = state.request.target.generation
	state.descriptor.parent = state.request.parent
	if failure := revision_detail_parse_parents(state, fields[1]); failure != .None do return failure
	if !revision_parent_choice_matches(state.request.parent, state.descriptor.parents[:int(state.descriptor.parent_count)]) {
		return .Revision_Unavailable
	}
	if u64(len(fields[9])) > state.request.limits.message_bytes ||
	   u64(len(fields[11])) > state.request.limits.signature_bytes {
		return .Output_Limit
	}
	status, status_valid := revision_signature_status_parse(fields[10])
	if !status_valid || (status == .Unavailable && len(fields[11]) != 0) do return .Parse
	state.descriptor.signature_status = status
	references := [8]^Revision_Text_Ref {
		&state.descriptor.author_name,
		&state.descriptor.author_email,
		&state.descriptor.authored_at,
		&state.descriptor.committer_name,
		&state.descriptor.committer_email,
		&state.descriptor.committed_at,
		&state.descriptor.subject,
		&state.descriptor.message,
	}
	values := [8][]u8 {
		fields[2], fields[3], fields[4], fields[5], fields[6], fields[7], fields[8], fields[9],
	}
	for index in 0 ..< len(references) {
		if failure := revision_detail_append_text(state, references[index], values[index]); failure != .None do return failure
	}
	if status != .Unavailable {
		if failure := revision_detail_append_text(state, &state.descriptor.signature, fields[11]); failure != .None do return failure
	}
	state.descriptor.message_bytes = u64(len(fields[9]))
	state.descriptor.signature_bytes = u64(len(fields[11]))
	return .None
}

@(private)
revision_detail_parse_parents :: proc(state: ^Revision_Detail_Data, field: []u8) -> Failure_Code {
	if state == nil do return .Invalid_Request
	cursor := 0
	for cursor < len(field) {
		if state.descriptor.parent_count >= state.request.limits.parents do return .Parent_Limit
		end := cursor
		for end < len(field) && field[end] != ' ' do end += 1
		if end == cursor || !revision_identity_assign(&state.descriptor.parents[state.descriptor.parent_count], string(field[cursor:end])) {
			return .Parse
		}
		state.descriptor.parent_count += 1
		if end == len(field) do break
		cursor = end + 1
		if cursor == len(field) do return .Parse
	}
	return .None
}

@(private)
revision_detail_append_text :: proc(
	state: ^Revision_Detail_Data,
	reference: ^Revision_Text_Ref,
	text: []u8,
) -> Failure_Code {
	if state == nil || reference == nil || u64(len(state.metadata)) + u64(len(text)) > state.request.limits.metadata_bytes {
		return .Output_Limit
	}
	reference^ = {offset = u32(len(state.metadata)), length = u32(len(text))}
	if len(text) == 0 do return .None
	_, allocation_error := append(&state.metadata, ..text)
	if allocation_error != nil do return .Allocation
	return .None
}

@(private)
revision_range_observation_parse_summary :: proc(
	state: ^Revision_Range_Observation_Data,
	output: []u8,
) -> Failure_Code {
	if state == nil do return .Invalid_Request
	cursor := 0
	for cursor < len(output) {
		if output[cursor] != 0x1e do return .Parse
		cursor += 1
		identity_text, next, found := revision_take_nul_field(output, cursor)
		if !found do return .Parse
		cursor = next
		subject: []u8
		subject, next, found = revision_take_nul_field(output, cursor)
		if !found do return .Parse
		cursor = next
		if cursor < len(output) && output[cursor] == '\n' do cursor += 1
		if u32(len(state.summaries)) >= state.request.limits.revisions do return .Output_Limit
		summary: Revision_Range_Summary
		if !revision_identity_assign(&summary.revision, string(identity_text)) do return .Parse
		if u64(len(state.storage)) + u64(len(subject)) > state.request.limits.summary_bytes {
			return .Output_Limit
		}
		summary.subject = {offset = u32(len(state.storage)), length = u32(len(subject))}
		if len(subject) > 0 {
			_, allocation_error := append(&state.storage, ..subject)
			if allocation_error != nil do return .Allocation
		}
		if !revision_range_summary_is_valid(summary, u64(len(state.storage))) do return .Parse
		_, allocation_error := append(&state.summaries, summary)
		if allocation_error != nil do return .Allocation
	}
	return .None
}

@(private)
revision_comparison_data_init :: proc(
	state: ^Revision_Comparison_Data,
	paths: u32,
	path_bytes, diff_bytes: u64,
	allocator: runtime.Allocator,
) -> runtime.Allocator_Error {
	if state == nil || allocator.procedure == nil do return runtime.Allocator_Error{}
	state.allocator = allocator
	paths_storage, allocation_error := make([dynamic]Revision_Changed_Path, 0, int(min(paths, 32)), allocator)
	state.paths = paths_storage
	if allocation_error == nil {
		path_storage, storage_error := make([dynamic]u8, 0, int(min(path_bytes, 16 * KIBIBYTE)), allocator)
		state.storage = path_storage
		allocation_error = storage_error
	}
	if allocation_error == nil {
		diff_storage, diff_error := make([dynamic]u8, 0, int(min(diff_bytes, 64 * KIBIBYTE)), allocator)
		state.diff = diff_storage
		allocation_error = diff_error
	}
	return allocation_error
}

@(private)
revision_comparison_data_parse :: proc(
	state: ^Revision_Comparison_Data,
	output: []u8,
	path_bytes, diff_bytes: u64,
	truncated: bool,
) -> Failure_Code {
	if state == nil || u64(len(output)) > path_bytes + diff_bytes do return .Invalid_Request
	if truncated do return .None
	cursor := 0
	for cursor < len(output) {
		if revision_bytes_have_prefix(output[cursor:], transmute([]u8)(string("diff --git "))) {
			if u64(len(output) - cursor) > diff_bytes do return .Output_Limit
			_, allocation_error := append(&state.diff, ..output[cursor:])
			if allocation_error != nil do return .Allocation
			return .None
		}
		if output[cursor] == 0 {
			cursor += 1
			continue
		}
		if output[cursor] != ':' do return .Parse
		header, next, found := revision_take_nul_field(output, cursor)
		if !found do return .Parse
		cursor = next
		kind, copied, parsed := revision_raw_change_kind(header)
		if !parsed do return .Parse
		original: []u8
		path: []u8
		if copied {
			original, next, found = revision_take_nul_field(output, cursor)
			if !found do return .Parse
			cursor = next
		}
		path, next, found = revision_take_nul_field(output, cursor)
		if !found || len(path) == 0 do return .Parse
		cursor = next
		entry := Revision_Changed_Path{kind = kind}
		if copied {
			if len(original) == 0 do return .Parse
			if failure := revision_comparison_data_append_text(state, &entry.original_path, original, path_bytes); failure != .None {
				return failure
			}
		}
		if failure := revision_comparison_data_append_text(state, &entry.path, path, path_bytes); failure != .None {
			return failure
		}
		if !revision_changed_path_is_valid(entry, u64(len(state.storage))) do return .Parse
		_, allocation_error := append(&state.paths, entry)
		if allocation_error != nil do return .Allocation
	}
	return .None
}

@(private)
revision_comparison_data_append_text :: proc(
	state: ^Revision_Comparison_Data,
	reference: ^Revision_Text_Ref,
	text: []u8,
	limit: u64,
) -> Failure_Code {
	if state == nil || reference == nil || u64(len(state.storage)) + u64(len(text)) > limit {
		return .Output_Limit
	}
	reference^ = {offset = u32(len(state.storage)), length = u32(len(text))}
	_, allocation_error := append(&state.storage, ..text)
	if allocation_error != nil do return .Allocation
	return .None
}

@(private)
revision_raw_change_kind :: proc(header: []u8) -> (Revision_Change_Kind, bool, bool) {
	if len(header) < 3 || header[0] != ':' do return .Invalid, false, false
	last_space := -1
	for index in 0 ..< len(header) {
		if header[index] == ' ' do last_space = index
	}
	if last_space < 1 || last_space + 1 >= len(header) do return .Invalid, false, false
	switch header[last_space + 1] {
	case 'A': return .Added, false, true
	case 'C': return .Copied, true, true
	case 'D': return .Deleted, false, true
	case 'M': return .Modified, false, true
	case 'R': return .Renamed, true, true
	case 'T': return .Type_Changed, false, true
	case 'U': return .Unmerged, false, true
	}
	return .Invalid, false, false
}

@(private)
revision_signature_status_parse :: proc(value: []u8) -> (Revision_Signature_Status, bool) {
	if len(value) != 1 do return .Invalid, false
	switch value[0] {
	case 'N': return .Unavailable, true
	case 'G': return .Good, true
	case 'B': return .Bad, true
	case 'U': return .Untrusted, true
	case 'X', 'Y': return .Expired, true
	case 'R': return .Revoked, true
	case 'E', '?': return .Unknown, true
	}
	return .Invalid, false
}

@(private)
revision_take_nul_field :: proc(output: []u8, cursor: int) -> ([]u8, int, bool) {
	if cursor < 0 || cursor >= len(output) do return nil, cursor, false
	for end in cursor ..< len(output) {
		if output[end] == 0 do return output[cursor:end], end + 1, true
	}
	return nil, cursor, false
}

@(private)
revision_bytes_have_prefix :: proc(content, prefix: []u8) -> bool {
	if len(prefix) > len(content) do return false
	for index in 0 ..< len(prefix) {
		if content[index] != prefix[index] do return false
	}
	return true
}

@(private)
revision_comparison_data_allocation_bytes :: proc(state: ^Revision_Comparison_Data) -> u64 {
	if state == nil do return 0
	return u64(cap(state.paths)) * u64(size_of(Revision_Changed_Path)) +
	       u64(cap(state.storage)) + u64(cap(state.diff))
}

@(private)
revision_detail_data :: proc(detail: ^Revision_Detail) -> ^Revision_Detail_Data {
	if detail == nil || detail.state == nil do return nil
	return cast(^Revision_Detail_Data)detail.state
}

@(private)
revision_range_observation_data :: proc(
	observation: ^Revision_Range_Observation,
) -> ^Revision_Range_Observation_Data {
	if observation == nil || observation.state == nil do return nil
	return cast(^Revision_Range_Observation_Data)observation.state
}

@(private)
revision_detail_data_destroy :: proc(state: ^Revision_Detail_Data) {
	if state == nil do return
	delete(state.metadata)
	revision_comparison_data_destroy(&state.comparison)
	free(state, state.allocator)
}

@(private)
revision_range_observation_data_destroy :: proc(state: ^Revision_Range_Observation_Data) {
	if state == nil do return
	delete(state.summaries)
	delete(state.storage)
	revision_comparison_data_destroy(&state.comparison)
	free(state, state.allocator)
}

@(private)
revision_comparison_data_destroy :: proc(state: ^Revision_Comparison_Data) {
	if state == nil do return
	delete(state.paths)
	delete(state.storage)
	delete(state.diff)
	state^ = {}
}
