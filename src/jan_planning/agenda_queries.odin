// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_planning

import "base:runtime"
import "core:strings"
import "core:text/regex"
import "core:unicode/utf8"

import "../language"

/* MAX_AGENDA_TAGS_PER_ENTRY bounds copied tag membership for one indexed entry. */
MAX_AGENDA_TAGS_PER_ENTRY :: 64
/* MAX_AGENDA_PROPERTIES_PER_ENTRY bounds copied properties for one indexed entry. */
MAX_AGENDA_PROPERTIES_PER_ENTRY :: 64
/* MAX_AGENDA_SORT_KEYS bounds deterministic sort precedence. */
MAX_AGENDA_SORT_KEYS :: 8
/* MAX_AGENDA_PREDICATES bounds one postfix combined or computed filter. */
MAX_AGENDA_PREDICATES :: 256
/* MAX_AGENDA_TEXT_BYTES bounds one copied entry field. */
MAX_AGENDA_TEXT_BYTES :: 64 * 1_024

/* Agenda_Source_State preserves unavailable and stale sources in an index generation. */
Agenda_Source_State :: enum u8 {
	Invalid,
	Confirmed,
	Stale,
	Unavailable,
	Failed,
}

/* Agenda_Entry_Kind identifies native and optional-provider rows uniformly. */
Agenda_Entry_Kind :: enum u8 {
	Invalid,
	Document,
	Diary,
	Calendar,
	Anniversary,
	Reminder,
	Extension,
}

/* Agenda_Property_Candidate is one borrowed indexed property fact. */
Agenda_Property_Candidate :: struct {
	name:  string,
	value: string,
}

/* Agenda_Entry_Candidate is one borrowed exact-source or typed-provider row. */
Agenda_Entry_Candidate :: struct {
	identity:             string,
	kind:                 Agenda_Entry_Kind,
	target:               Semantic_Target,
	has_target:           bool,
	category:             string,
	heading_path:         string,
	task_state:           string,
	finished:             bool,
	priority:             i16,
	tags:                 []string,
	properties:           []Agenda_Property_Candidate,
	scheduled:            i64,
	deadline:             i64,
	timestamp:            i64,
	time_of_day_minutes:  i16,
	warning:              bool,
	project:              string,
	stuck_project:        bool,
	clock_seconds:        u64,
	effort_seconds:       u64,
	column_text:          string,
	plain_text:           string,
	block_identity:       string,
	custom_identity:      string,
	provider_annotation:  string,
	archived:             bool,
}

/* Agenda_Source_Candidate is one bounded discovery result and its borrowed rows. */
Agenda_Source_Candidate :: struct {
	identity:                 string,
	kind:                     Source_Kind,
	state:                    Agenda_Source_State,
	failure_code:             Failure_Code,
	resource:                 Resource_Identity,
	document_revision:        u64,
	durable_version:          u64,
	baseline:                 language.Jan_Baseline_Identity,
	configuration_generation: Configuration_Generation,
	provider_generation:      Provider_Generation,
	discovery_depth:          u16,
	document_limit:           u32,
	discovered_documents:     u32,
	root_admitted:            bool,
	entries:                  []Agenda_Entry_Candidate,
}

/* Agenda_Index_Request binds discovery results to one immutable generation. */
Agenda_Index_Request :: struct {
	operation_id:             Operation_ID,
	generation:               u64,
	source_set:               Source_Set_ID,
	configuration_generation: Configuration_Generation,
	provider_generation:      Provider_Generation,
	sources:                  []Agenda_Source_Candidate,
	entry_limit:              u32,
	copied_text_limit:        u64,
	derived_state_limit:      u64,
	cancel_requested:         bool,
}

/* Agenda_Record_Range identifies one contiguous copied child range. */
Agenda_Record_Range :: struct {
	start: u32,
	count: u32,
}

/* Agenda_Source_Record borrows one copied discovery outcome until index close. */
Agenda_Source_Record :: struct {
	identity:                 string,
	kind:                     Source_Kind,
	state:                    Agenda_Source_State,
	failure_code:             Failure_Code,
	resource:                 Resource_Identity,
	document_revision:        u64,
	durable_version:          u64,
	baseline:                 language.Jan_Baseline_Identity,
	configuration_generation: Configuration_Generation,
	provider_generation:      Provider_Generation,
	discovery_depth:          u16,
	document_limit:           u32,
	discovered_documents:     u32,
	entries:                  Agenda_Record_Range,
}

/* Agenda_Property_Record borrows one copied indexed property until index close. */
Agenda_Property_Record :: struct {
	name:  string,
	value: string,
}

/* Agenda_Entry_Record borrows copied presentation and query facts until index close. */
Agenda_Entry_Record :: struct {
	identity:            string,
	kind:                Agenda_Entry_Kind,
	source_index:        u32,
	target:              Semantic_Target,
	has_target:          bool,
	category:            string,
	heading_path:        string,
	task_state:          string,
	finished:            bool,
	priority:            i16,
	tags:                Agenda_Record_Range,
	properties:          Agenda_Record_Range,
	scheduled:           i64,
	deadline:            i64,
	timestamp:           i64,
	time_of_day_minutes: i16,
	warning:             bool,
	project:             string,
	stuck_project:       bool,
	clock_seconds:       u64,
	effort_seconds:      u64,
	column_text:         string,
	plain_text:          string,
	block_identity:      string,
	custom_identity:     string,
	provider_annotation: string,
	archived:            bool,
}

/* Agenda_Index_Descriptor reports exact source and retained-state accounting. */
Agenda_Index_Descriptor :: struct {
	operation_id:             Operation_ID,
	generation:               u64,
	source_set:               Source_Set_ID,
	configuration_generation: Configuration_Generation,
	provider_generation:      Provider_Generation,
	source_count:             u32,
	confirmed_sources:        u32,
	stale_sources:            u32,
	unavailable_sources:      u32,
	failed_sources:           u32,
	indexed_entries:          u32,
	scanned_entries:          u32,
	copied_text_bytes:        u64,
	derived_state_bytes:      u64,
	truncated:                bool,
}

/* Agenda_Index owns one immutable revision-bound source and entry generation. */
Agenda_Index :: struct {
	state: rawptr,
}

@(private)
Agenda_Index_State :: struct {
	descriptor: Agenda_Index_Descriptor,
	sources:    []Agenda_Source_Record,
	entries:    []Agenda_Entry_Record,
	tags:       []string,
	properties: []Agenda_Property_Record,
	arena:      []u8,
	allocator:  runtime.Allocator,
}

/* Agenda_Query_Kind identifies every factory and provider query family. */
Agenda_Query_Kind :: enum u8 {
	Invalid,
	Daily,
	Weekly,
	Unfinished,
	Task,
	Tag,
	Property,
	Combined,
	Text,
	Regular_Expression,
	Project,
	Stuck_Project,
	Clock,
	Effort,
	Column,
	Block,
	Custom,
	Diary,
	Calendar,
	Anniversary,
	Reminder,
	Extension,
}

/* Agenda_Predicate_Kind identifies postfix Boolean query and filter operands. */
Agenda_Predicate_Kind :: enum u8 {
	Invalid,
	Task,
	Tag,
	Property,
	Text,
	Timestamp,
	Project,
	Stuck_Project,
	Clock,
	Effort,
	Entry_Kind,
	Not,
	And,
	Or,
}

/* Agenda_Predicate_Token is one bounded postfix Boolean token. */
Agenda_Predicate_Token :: struct {
	kind:       Agenda_Predicate_Kind,
	primary:    string,
	secondary:  string,
	start_time: i64,
	end_time:   i64,
	entry_kind: Agenda_Entry_Kind,
}

/* Agenda_Sort_Key identifies deterministic presentation ordering facts. */
Agenda_Sort_Key :: enum u8 {
	Invalid,
	Category,
	Time,
	Priority,
	Deadline,
	Scheduled,
	Task_State,
	Source_Order,
	Heading_Path,
	Clock,
	Effort,
}

/* Agenda_Sort_Spec selects one ascending or descending precedence key. */
Agenda_Sort_Spec :: struct {
	key:        Agenda_Sort_Key,
	descending: bool,
}

/* Agenda_Group_Key selects stable result grouping. */
Agenda_Group_Key :: enum u8 {
	None,
	Category,
	Project,
	Source,
	Day,
	Task_State,
}

/* Agenda_Prefix_Format selects one bounded deterministic row prefix. */
Agenda_Prefix_Format :: enum u8 {
	None,
	Category,
	Task_State,
	Priority,
	Time,
	Heading_Path,
}

/* Agenda_Property_Filter is one exact property name and optional value filter. */
Agenda_Property_Filter :: struct {
	name:  string,
	value: string,
}

/* Agenda_Query_Request binds one view to exact generations and bounded options. */
Agenda_Query_Request :: struct {
	operation_id:             Operation_ID,
	index_generation:         u64,
	configuration_generation: Configuration_Generation,
	query_dialect:            string,
	kind:                     Agenda_Query_Kind,
	primary:                  string,
	secondary:                string,
	start_time:               i64,
	end_time:                 i64,
	predicates:               []Agenda_Predicate_Token,
	required_tags:            []string,
	property_filters:         []Agenda_Property_Filter,
	computed_tag_filter:      []Agenda_Predicate_Token,
	sort:                     []Agenda_Sort_Spec,
	group_by:                 Agenda_Group_Key,
	time_grid:                bool,
	prefix_format:            Agenda_Prefix_Format,
	include_archived:         bool,
	result_limit:             u32,
	cancel_requested:         bool,
}

/* Agenda_Display_Text is one bounded pointer-free group or prefix value. */
Agenda_Display_Text :: struct {
	bytes:     [MAX_LABEL_BYTES]u8,
	length: u16,
	truncated: bool,
}

/* Agenda_Result_Row identifies one sorted indexed entry and its presentation facts. */
Agenda_Result_Row :: struct {
	entry_index: u32,
	group:       Agenda_Display_Text,
	prefix:      Agenda_Display_Text,
	time_grid:   bool,
}

/* Agenda_Query_Descriptor reports complete, truncated, and source-health counts. */
Agenda_Query_Descriptor :: struct {
	operation_id:        Operation_ID,
	index_generation:    u64,
	result_count:        u32,
	matched_count:       u32,
	indexed_sources:     u32,
	scanned_sources:     u32,
	stale_sources:       u32,
	unavailable_sources: u32,
	failed_sources:      u32,
	truncated:           bool,
	complete:            bool,
}

/* Agenda_Query_Result owns sorted row identities until close. */
Agenda_Query_Result :: struct {
	state: rawptr,
}

@(private)
Agenda_Query_State :: struct {
	descriptor: Agenda_Query_Descriptor,
	rows:       []Agenda_Result_Row,
	allocator:  runtime.Allocator,
}

/* Agenda_Cache_Key binds acceleration to exact index and configuration generations. */
Agenda_Cache_Key :: struct {
	index_generation:         u64,
	configuration_generation: Configuration_Generation,
	source_set:               Source_Set_ID,
	query_identity:           u64,
}

/* agenda_index_prepare copies one complete bounded source generation atomically. */
agenda_index_prepare :: proc(
	index: ^Agenda_Index,
	request: Agenda_Index_Request,
	allocator := context.allocator,
) -> (Agenda_Index_Descriptor, bool, Failure) {
	if index == nil || index.state != nil || !agenda_index_request_is_valid(request) || allocator.procedure == nil {
		return {}, false, agenda_failure(request.operation_id, .Invalid_Request, .Agenda)
	}
	if request.cancel_requested do return {}, false, agenda_failure(request.operation_id, .Cancelled, .Agenda)
	entry_count, tag_count, property_count := 0, 0, 0
	text_bytes: u64
	descriptor := Agenda_Index_Descriptor{
		operation_id = request.operation_id,
		generation = request.generation,
		source_set = request.source_set,
		configuration_generation = request.configuration_generation,
		provider_generation = request.provider_generation,
		source_count = u32(len(request.sources)),
	}
	for source, source_index in request.sources {
		valid, source_text, source_entries, source_tags, source_properties := agenda_source_candidate_measure(source, request)
		if !valid do return {}, false, agenda_failure(request.operation_id, .Malformed, .Source_Set)
		for prior in request.sources[:source_index] do if agenda_resource_equal(prior.resource, source.resource) {
			return {}, false, agenda_failure(request.operation_id, .Conflict, .Source_Set)
		}
		text_bytes += source_text
		entry_count += source_entries
		tag_count += source_tags
		property_count += source_properties
		if entry_count > int(request.entry_limit) {
			failure := agenda_failure(request.operation_id, .Limited, .Limit)
			failure.limit = u64(request.entry_limit)
			failure.actual = u64(entry_count)
			return {}, false, failure
		}
		descriptor.scanned_entries += u32(len(source.entries))
		switch source.state {
		case .Confirmed:   descriptor.confirmed_sources += 1
		case .Stale:       descriptor.stale_sources += 1
		case .Unavailable: descriptor.unavailable_sources += 1
		case .Failed:      descriptor.failed_sources += 1
		case .Invalid:     return {}, false, agenda_failure(request.operation_id, .Malformed, .Source_Set)
		}
	}
	if text_bytes > request.copied_text_limit {
		failure := agenda_failure(request.operation_id, .Limited, .Limit)
		failure.limit = request.copied_text_limit
		failure.actual = text_bytes
		return {}, false, failure
	}
	retained_bytes := text_bytes + u64(size_of(Agenda_Index_State)) +
	                  u64(len(request.sources) * size_of(Agenda_Source_Record)) +
	                  u64(entry_count * size_of(Agenda_Entry_Record)) +
	                  u64(tag_count * size_of(string)) +
	                  u64(property_count * size_of(Agenda_Property_Record))
	if retained_bytes > request.derived_state_limit {
		failure := agenda_failure(request.operation_id, .Limited, .Limit)
		failure.limit = request.derived_state_limit
		failure.actual = retained_bytes
		return {}, false, failure
	}
	state, allocation_error := new(Agenda_Index_State, allocator)
	if allocation_error != nil do return {}, false, agenda_failure(request.operation_id, .Allocation_Failed, .Agenda)
	state^ = Agenda_Index_State{allocator = allocator}
	state.sources, allocation_error = make([]Agenda_Source_Record, len(request.sources), allocator)
	if allocation_error == nil do state.entries, allocation_error = make([]Agenda_Entry_Record, entry_count, allocator)
	if allocation_error == nil do state.tags, allocation_error = make([]string, tag_count, allocator)
	if allocation_error == nil do state.properties, allocation_error = make([]Agenda_Property_Record, property_count, allocator)
	if allocation_error == nil && text_bytes > 0 do state.arena, allocation_error = make([]u8, int(text_bytes), allocator)
	if allocation_error != nil {
		agenda_index_state_close(state)
		return {}, false, agenda_failure(request.operation_id, .Allocation_Failed, .Agenda)
	}
	cursor, entry_cursor, tag_cursor, property_cursor := 0, 0, 0, 0
	for source, source_index in request.sources {
		entry_start := entry_cursor
		state.sources[source_index] = {
			identity = agenda_arena_copy(state.arena, &cursor, source.identity),
			kind = source.kind,
			state = source.state,
			failure_code = source.failure_code,
			resource = source.resource,
			document_revision = source.document_revision,
			durable_version = source.durable_version,
			baseline = source.baseline,
			configuration_generation = source.configuration_generation,
			provider_generation = source.provider_generation,
			discovery_depth = source.discovery_depth,
			document_limit = source.document_limit,
			discovered_documents = source.discovered_documents,
		}
		if source.state == .Confirmed {
			for entry in source.entries {
				tag_start, property_start := tag_cursor, property_cursor
				for tag in entry.tags {
					state.tags[tag_cursor] = agenda_arena_copy(state.arena, &cursor, tag)
					tag_cursor += 1
				}
				for property in entry.properties {
					state.properties[property_cursor] = {
						name = agenda_arena_copy(state.arena, &cursor, property.name),
						value = agenda_arena_copy(state.arena, &cursor, property.value),
					}
					property_cursor += 1
				}
				state.entries[entry_cursor] = agenda_entry_copy(
					entry,
					u32(source_index),
					{start = u32(tag_start), count = u32(tag_cursor - tag_start)},
					{start = u32(property_start), count = u32(property_cursor - property_start)},
					state.arena,
					&cursor,
				)
				entry_cursor += 1
			}
		}
		state.sources[source_index].entries = {start = u32(entry_start), count = u32(entry_cursor - entry_start)}
	}
	assert(cursor == len(state.arena) && entry_cursor == len(state.entries))
	descriptor.indexed_entries = u32(entry_cursor)
	descriptor.copied_text_bytes = text_bytes
	descriptor.derived_state_bytes = retained_bytes
	state.descriptor = descriptor
	index.state = state
	return descriptor, true, {}
}

/* agenda_index_descriptor reports one immutable generation without source text. */
agenda_index_descriptor :: proc(index: ^Agenda_Index) -> (Agenda_Index_Descriptor, bool) {
	state := agenda_index_state(index)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* agenda_index_source borrows one copied source result until index close. */
agenda_index_source :: proc(index: ^Agenda_Index, position: int) -> (Agenda_Source_Record, bool) {
	state := agenda_index_state(index)
	if state == nil || position < 0 || position >= len(state.sources) do return {}, false
	return state.sources[position], true
}

/* agenda_index_entry borrows one copied indexed entry until index close. */
agenda_index_entry :: proc(index: ^Agenda_Index, position: int) -> (Agenda_Entry_Record, bool) {
	state := agenda_index_state(index)
	if state == nil || position < 0 || position >= len(state.entries) do return {}, false
	return state.entries[position], true
}

/* agenda_index_entry_tags borrows the exact copied tag range until index close. */
agenda_index_entry_tags :: proc(index: ^Agenda_Index, entry: Agenda_Entry_Record) -> ([]string, bool) {
	state := agenda_index_state(index)
	start, count := int(entry.tags.start), int(entry.tags.count)
	if state == nil || start < 0 || count < 0 || start + count > len(state.tags) do return nil, false
	return state.tags[start:start + count], true
}

/* agenda_index_entry_properties borrows copied properties until index close. */
agenda_index_entry_properties :: proc(index: ^Agenda_Index, entry: Agenda_Entry_Record) -> ([]Agenda_Property_Record, bool) {
	state := agenda_index_state(index)
	start, count := int(entry.properties.start), int(entry.properties.count)
	if state == nil || start < 0 || count < 0 || start + count > len(state.properties) do return nil, false
	return state.properties[start:start + count], true
}

/* agenda_index_close releases copied sources, entries, query facts, and text exactly once. */
agenda_index_close :: proc(index: ^Agenda_Index) {
	state := agenda_index_state(index)
	if state == nil do return
	agenda_index_state_close(state)
	index.state = nil
}

/* agenda_query_prepare filters and stably sorts one exact index generation. */
agenda_query_prepare :: proc(
	result: ^Agenda_Query_Result,
	index: ^Agenda_Index,
	request: Agenda_Query_Request,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (Agenda_Query_Descriptor, bool, Failure) {
	index_state := agenda_index_state(index)
	if result == nil || result.state != nil || index_state == nil ||
	   !agenda_query_request_is_valid(request, index_state.descriptor) ||
	   allocator.procedure == nil || temporary_allocator.procedure == nil {
		return {}, false, agenda_failure(request.operation_id, .Invalid_Request, .Agenda)
	}
	if request.cancel_requested do return {}, false, agenda_failure(request.operation_id, .Cancelled, .Agenda)
	capacity := min(len(index_state.entries), int(request.result_limit))
	selected, allocation_error := make([]u32, capacity, temporary_allocator)
	if allocation_error != nil do return {}, false, agenda_failure(request.operation_id, .Allocation_Failed, .Agenda)
	defer delete(selected, temporary_allocator)
	selected_count, matched_count, selected_ok := 0, 0, false
	if request.kind == .Regular_Expression {
		selected_count, matched_count, selected_ok = agenda_regex_select(
			index_state,
			request,
			selected,
			allocator,
			temporary_allocator,
		)
	} else {
		selected_count, matched_count, selected_ok = agenda_select(index_state, request, selected)
	}
	if !selected_ok do return {}, false, agenda_failure(request.operation_id, .Malformed, .Agenda)
	if selected_count > 1 && len(request.sort) > 0 {
		scratch, scratch_error := make([]u32, selected_count, temporary_allocator)
		if scratch_error != nil do return {}, false, agenda_failure(request.operation_id, .Allocation_Failed, .Agenda)
		defer delete(scratch, temporary_allocator)
		agenda_rows_sort(selected[:selected_count], scratch, index_state, request.sort)
	}
	result_bytes := u64(size_of(Agenda_Query_State)) + u64(selected_count * size_of(Agenda_Result_Row))
	if result_bytes > MAX_DERIVED_STATE_BYTES {
		failure := agenda_failure(request.operation_id, .Limited, .Limit)
		failure.limit = MAX_DERIVED_STATE_BYTES
		failure.actual = result_bytes
		return {}, false, failure
	}
	state, state_error := new(Agenda_Query_State, allocator)
	if state_error != nil do return {}, false, agenda_failure(request.operation_id, .Allocation_Failed, .Agenda)
	state^ = Agenda_Query_State{allocator = allocator}
	state.rows, state_error = make([]Agenda_Result_Row, selected_count, allocator)
	if state_error != nil {
		agenda_query_state_close(state)
		return {}, false, agenda_failure(request.operation_id, .Allocation_Failed, .Agenda)
	}
	for entry_index, row_index in selected[:selected_count] {
		entry := index_state.entries[entry_index]
		state.rows[row_index] = {
			entry_index = entry_index,
			group = agenda_group_text(index_state, entry, request.group_by),
			prefix = agenda_prefix_text(entry, request.prefix_format),
			time_grid = request.time_grid && entry.time_of_day_minutes >= 0,
		}
	}
	index_descriptor := index_state.descriptor
	state.descriptor = {
		operation_id = request.operation_id,
		index_generation = request.index_generation,
		result_count = u32(selected_count),
		matched_count = u32(matched_count),
		indexed_sources = index_descriptor.confirmed_sources,
		scanned_sources = index_descriptor.source_count,
		stale_sources = index_descriptor.stale_sources,
		unavailable_sources = index_descriptor.unavailable_sources,
		failed_sources = index_descriptor.failed_sources,
		truncated = matched_count > selected_count,
		complete = matched_count <= selected_count && index_descriptor.stale_sources == 0 &&
		           index_descriptor.unavailable_sources == 0 && index_descriptor.failed_sources == 0,
	}
	result.state = state
	return state.descriptor, true, {}
}

/* agenda_query_descriptor reports result and source-health counts without row text. */
agenda_query_descriptor :: proc(result: ^Agenda_Query_Result) -> (Agenda_Query_Descriptor, bool) {
	state := agenda_query_state(result)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* agenda_query_row borrows one stable sorted row until result close. */
agenda_query_row :: proc(result: ^Agenda_Query_Result, position: int) -> (Agenda_Result_Row, bool) {
	state := agenda_query_state(result)
	if state == nil || position < 0 || position >= len(state.rows) do return {}, false
	return state.rows[position], true
}

/* agenda_display_text borrows one pointer-free result group or prefix. */
agenda_display_text :: proc(text: ^Agenda_Display_Text) -> string {
	if text == nil || int(text.length) > len(text.bytes) do return ""
	return string(text.bytes[:text.length])
}

/* agenda_query_close releases sorted row state exactly once. */
agenda_query_close :: proc(result: ^Agenda_Query_Result) {
	state := agenda_query_state(result)
	if state == nil do return
	agenda_query_state_close(state)
	result.state = nil
}

/* agenda_cache_key_is_current invalidates acceleration on any exact-generation change. */
agenda_cache_key_is_current :: proc(
	key: Agenda_Cache_Key,
	index: Agenda_Index_Descriptor,
	request: Agenda_Query_Request,
) -> bool {
	return key.query_identity != 0 && key.index_generation == index.generation &&
	       key.index_generation == request.index_generation &&
	       key.configuration_generation == index.configuration_generation &&
	       key.configuration_generation == request.configuration_generation &&
	       key.source_set == index.source_set
}

@(private)
agenda_index_request_is_valid :: proc(request: Agenda_Index_Request) -> bool {
	return request.operation_id != Operation_ID(0) && request.generation != 0 &&
	       request.source_set != Source_Set_ID(0) &&
	       request.configuration_generation != Configuration_Generation(0) &&
	       request.provider_generation != Provider_Generation(0) && len(request.sources) > 0 &&
	       len(request.sources) <= int(MAX_SOURCE_DOCUMENTS) && request.entry_limit > 0 &&
	       request.entry_limit <= MAX_AGENDA_ENTRIES && request.copied_text_limit > 0 &&
	       request.copied_text_limit <= MAX_COPIED_TEXT_BYTES && request.derived_state_limit > 0 &&
	       request.derived_state_limit <= MAX_DERIVED_STATE_BYTES
}

@(private)
agenda_source_candidate_measure :: proc(
	source: Agenda_Source_Candidate,
	request: Agenda_Index_Request,
) -> (bool, u64, int, int, int) {
	if !configuration_text_is_valid(source.identity, MAX_IDENTITY_BYTES) || source.kind == .Invalid ||
	   source.state == .Invalid || !resource_identity_is_valid(source.resource) ||
	   source.configuration_generation == Configuration_Generation(0) ||
	   source.provider_generation == Provider_Generation(0) || source.discovery_depth > 64 ||
	   source.document_limit == 0 || source.document_limit > MAX_SOURCE_DOCUMENTS ||
	   source.discovered_documents > source.document_limit || !source.root_admitted ||
	   !language.jan_baseline_identity_is_valid(source.baseline) {
		return false, 0, 0, 0, 0
	}
	if source.state == .Confirmed && source.failure_code != .None ||
	   source.state == .Stale && source.failure_code != .Stale ||
	   source.state == .Unavailable && source.failure_code != .Unavailable ||
	   source.state == .Failed && source.failure_code == .None {
		return false, 0, 0, 0, 0
	}
	if source.state == .Confirmed &&
	   (source.configuration_generation != request.configuration_generation ||
	    source.provider_generation != request.provider_generation ||
	    source.document_revision == 0 && source.durable_version == 0) {
		return false, 0, 0, 0, 0
	}
	if source.state != .Confirmed && len(source.entries) > 0 do return false, 0, 0, 0, 0
	text_bytes := u64(len(source.identity))
	entry_count, tag_count, property_count := 0, 0, 0
	for entry in source.entries {
		valid, entry_text := agenda_entry_candidate_measure(entry, source)
		if !valid do return false, 0, 0, 0, 0
		text_bytes += entry_text
		entry_count += 1
		tag_count += len(entry.tags)
		property_count += len(entry.properties)
	}
	return true, text_bytes, entry_count, tag_count, property_count
}

@(private)
agenda_entry_candidate_measure :: proc(entry: Agenda_Entry_Candidate, source: Agenda_Source_Candidate) -> (bool, u64) {
	if !configuration_text_is_valid(entry.identity, MAX_IDENTITY_BYTES) || entry.kind == .Invalid ||
	   !agenda_optional_identity_is_valid(entry.category) || len(entry.heading_path) > MAX_RESOURCE_BYTES ||
	   !utf8.valid_string(entry.heading_path) || !agenda_optional_identity_is_valid(entry.task_state) ||
	   !agenda_optional_identity_is_valid(entry.project) ||
	   !agenda_optional_identity_is_valid(entry.block_identity) ||
	   !agenda_optional_identity_is_valid(entry.custom_identity) ||
	   !agenda_entry_text_is_valid(entry.column_text) || !agenda_entry_text_is_valid(entry.plain_text) ||
	   !agenda_entry_text_is_valid(entry.provider_annotation) ||
	   len(entry.tags) > MAX_AGENDA_TAGS_PER_ENTRY ||
	   len(entry.properties) > MAX_AGENDA_PROPERTIES_PER_ENTRY ||
	   entry.time_of_day_minutes < -1 || entry.time_of_day_minutes >= 24 * 60 {
		return false, 0
	}
	if entry.has_target {
		if entry.kind != .Document || !semantic_target_is_valid(entry.target, agenda_scope_from_target(entry.target)) ||
		   u64(entry.target.range.scope.source_revision) != source.document_revision {
			return false, 0
		}
	} else if entry.kind == .Document {
		return false, 0
	}
	text_bytes := u64(len(entry.identity) + len(entry.category) + len(entry.heading_path) +
	                  len(entry.task_state) + len(entry.project) + len(entry.column_text) +
	                  len(entry.plain_text) + len(entry.block_identity) + len(entry.custom_identity) +
	                  len(entry.provider_annotation))
	for tag, index in entry.tags {
		if !configuration_text_is_valid(tag, MAX_IDENTITY_BYTES) do return false, 0
		for prior in entry.tags[:index] do if prior == tag do return false, 0
		text_bytes += u64(len(tag))
	}
	for property, index in entry.properties {
		if !configuration_text_is_valid(property.name, MAX_IDENTITY_BYTES) ||
		   len(property.value) > MAX_AGENDA_TEXT_BYTES || !utf8.valid_string(property.value) {
			return false, 0
		}
		for prior in entry.properties[:index] do if prior.name == property.name do return false, 0
		text_bytes += u64(len(property.name) + len(property.value))
	}
	return text_bytes <= MAX_COPIED_TEXT_BYTES, text_bytes
}

@(private)
agenda_scope_from_target :: proc(target: Semantic_Target) -> Scope {
	return {
		analysis = target.range.scope,
		source_bytes = u64(target.range.end),
		configuration_generation = 1,
		provider_generation = 1,
		source_set = 1,
	}
}

@(private)
agenda_entry_text_is_valid :: proc(text: string) -> bool {
	return len(text) <= MAX_AGENDA_TEXT_BYTES && utf8.valid_string(text)
}

@(private)
agenda_optional_identity_is_valid :: proc(text: string) -> bool {
	return len(text) <= MAX_IDENTITY_BYTES && utf8.valid_string(text)
}

@(private)
agenda_entry_copy :: proc(
	entry: Agenda_Entry_Candidate,
	source_index: u32,
	tags, properties: Agenda_Record_Range,
	arena: []u8,
	cursor: ^int,
) -> Agenda_Entry_Record {
	return {
		identity = agenda_arena_copy(arena, cursor, entry.identity),
		kind = entry.kind,
		source_index = source_index,
		target = entry.target,
		has_target = entry.has_target,
		category = agenda_arena_copy(arena, cursor, entry.category),
		heading_path = agenda_arena_copy(arena, cursor, entry.heading_path),
		task_state = agenda_arena_copy(arena, cursor, entry.task_state),
		finished = entry.finished,
		priority = entry.priority,
		tags = tags,
		properties = properties,
		scheduled = entry.scheduled,
		deadline = entry.deadline,
		timestamp = entry.timestamp,
		time_of_day_minutes = entry.time_of_day_minutes,
		warning = entry.warning,
		project = agenda_arena_copy(arena, cursor, entry.project),
		stuck_project = entry.stuck_project,
		clock_seconds = entry.clock_seconds,
		effort_seconds = entry.effort_seconds,
		column_text = agenda_arena_copy(arena, cursor, entry.column_text),
		plain_text = agenda_arena_copy(arena, cursor, entry.plain_text),
		block_identity = agenda_arena_copy(arena, cursor, entry.block_identity),
		custom_identity = agenda_arena_copy(arena, cursor, entry.custom_identity),
		provider_annotation = agenda_arena_copy(arena, cursor, entry.provider_annotation),
		archived = entry.archived,
	}
}

@(private)
agenda_query_request_is_valid :: proc(request: Agenda_Query_Request, index: Agenda_Index_Descriptor) -> bool {
	if request.operation_id == Operation_ID(0) || request.index_generation != index.generation ||
	   request.configuration_generation != index.configuration_generation || request.kind == .Invalid ||
	   !configuration_text_is_valid(request.query_dialect, MAX_IDENTITY_BYTES) ||
	   len(request.primary) > MAX_QUERY_BYTES || !utf8.valid_string(request.primary) ||
	   len(request.secondary) > MAX_QUERY_BYTES || !utf8.valid_string(request.secondary) ||
	   len(request.predicates) > MAX_AGENDA_PREDICATES ||
	   len(request.computed_tag_filter) > MAX_AGENDA_PREDICATES ||
	   len(request.required_tags) > MAX_AGENDA_TAGS_PER_ENTRY ||
	   len(request.property_filters) > MAX_AGENDA_PROPERTIES_PER_ENTRY ||
	   len(request.sort) > MAX_AGENDA_SORT_KEYS || request.result_limit == 0 ||
	   request.result_limit > MAX_AGENDA_ENTRIES {
		return false
	}
	for spec, index in request.sort {
		if spec.key == .Invalid do return false
		for prior in request.sort[:index] do if prior.key == spec.key do return false
	}
	for tag in request.required_tags do if !configuration_text_is_valid(tag, MAX_IDENTITY_BYTES) do return false
	for property in request.property_filters {
		if !configuration_text_is_valid(property.name, MAX_IDENTITY_BYTES) ||
		   len(property.value) > MAX_AGENDA_TEXT_BYTES || !utf8.valid_string(property.value) {
			return false
		}
	}
	if !agenda_predicate_tokens_are_valid(request.predicates) ||
	   !agenda_predicate_tokens_are_valid(request.computed_tag_filter) {
		return false
	}
	if (request.kind == .Daily || request.kind == .Weekly) && request.start_time > request.end_time do return false
	if request.kind == .Combined && len(request.predicates) == 0 do return false
	if agenda_query_requires_primary(request.kind) && len(request.primary) == 0 do return false
	return true
}

@(private)
agenda_query_requires_primary :: proc(kind: Agenda_Query_Kind) -> bool {
	return kind == .Task || kind == .Tag || kind == .Property || kind == .Text ||
	       kind == .Regular_Expression || kind == .Project || kind == .Block ||
	       kind == .Custom
}

@(private)
agenda_predicate_tokens_are_valid :: proc(tokens: []Agenda_Predicate_Token) -> bool {
	for token in tokens {
		if token.kind == .Invalid do return false
		if len(token.primary) > MAX_QUERY_BYTES || !utf8.valid_string(token.primary) ||
		   len(token.secondary) > MAX_QUERY_BYTES || !utf8.valid_string(token.secondary) {
			return false
		}
		if agenda_predicate_requires_primary(token.kind) && len(token.primary) == 0 do return false
		if token.kind == .Timestamp && token.start_time > token.end_time do return false
		if token.kind == .Entry_Kind && token.entry_kind == .Invalid do return false
	}
	return true
}

@(private)
agenda_predicate_requires_primary :: proc(kind: Agenda_Predicate_Kind) -> bool {
	return kind == .Task || kind == .Tag || kind == .Property ||
	       kind == .Text || kind == .Project
}

@(private)
agenda_select :: proc(state: ^Agenda_Index_State, request: Agenda_Query_Request, selected: []u32) -> (int, int, bool) {
	selected_count, matched_count := 0, 0
	for entry, index in state.entries {
		matched, valid := agenda_entry_matches(state, entry, request)
		if !valid do return 0, 0, false
		if !matched do continue
		matched_count += 1
		if selected_count < len(selected) {
			selected[selected_count] = u32(index)
			selected_count += 1
		}
	}
	return selected_count, matched_count, true
}

@(private)
agenda_regex_select :: proc(
	state: ^Agenda_Index_State,
	request: Agenda_Query_Request,
	selected: []u32,
	allocator, temporary_allocator: runtime.Allocator,
) -> (int, int, bool) {
	if len(request.primary) == 0 do return 0, 0, false
	compiled, compile_error := regex.create(request.primary, {.Unicode}, allocator, temporary_allocator)
	if compile_error != nil do return 0, 0, false
	defer regex.destroy_regex(compiled, allocator)
	selected_count, matched_count := 0, 0
	for entry, index in state.entries {
		if !agenda_entry_filters_match(state, entry, request) do continue
		capture, matched := regex.match(compiled, entry.plain_text, temporary_allocator, temporary_allocator)
		if capture.groups != nil do regex.destroy_capture(capture, temporary_allocator)
		if !matched do continue
		matched_count += 1
		if selected_count < len(selected) {
			selected[selected_count] = u32(index)
			selected_count += 1
		}
	}
	return selected_count, matched_count, true
}

@(private)
agenda_entry_matches :: proc(state: ^Agenda_Index_State, entry: Agenda_Entry_Record, request: Agenda_Query_Request) -> (bool, bool) {
	if !agenda_entry_filters_match(state, entry, request) do return false, true
	switch request.kind {
	case .Daily, .Weekly:
		return agenda_time_matches(entry, request.start_time, request.end_time), true
	case .Unfinished:
		return len(entry.task_state) > 0 && !entry.finished, true
	case .Task:
		return entry.task_state == request.primary, true
	case .Tag:
		return agenda_entry_has_tag(state, entry, request.primary), true
	case .Property:
		return agenda_entry_has_property(state, entry, request.primary, request.secondary), true
	case .Combined:
		return agenda_predicates_match(state, entry, request.predicates)
	case .Text:
		return len(request.primary) > 0 && strings.contains(entry.plain_text, request.primary), true
	case .Project:
		return entry.project == request.primary, true
	case .Stuck_Project:
		return entry.stuck_project && (len(request.primary) == 0 || entry.project == request.primary), true
	case .Clock:
		return entry.clock_seconds > 0, true
	case .Effort:
		return entry.effort_seconds > 0, true
	case .Column:
		return len(entry.column_text) > 0, true
	case .Block:
		return entry.block_identity == request.primary, true
	case .Custom:
		return entry.custom_identity == request.primary, true
	case .Diary:      return entry.kind == .Diary, true
	case .Calendar:   return entry.kind == .Calendar, true
	case .Anniversary:return entry.kind == .Anniversary, true
	case .Reminder:   return entry.kind == .Reminder, true
	case .Extension:  return entry.kind == .Extension, true
	case .Regular_Expression, .Invalid:
		return false, false
	}
	return false, false
}

@(private)
agenda_entry_filters_match :: proc(state: ^Agenda_Index_State, entry: Agenda_Entry_Record, request: Agenda_Query_Request) -> bool {
	if entry.archived && !request.include_archived do return false
	for tag in request.required_tags do if !agenda_entry_has_tag(state, entry, tag) do return false
	for property in request.property_filters do if !agenda_entry_has_property(state, entry, property.name, property.value) do return false
	if len(request.computed_tag_filter) > 0 {
		matched, valid := agenda_predicates_match(state, entry, request.computed_tag_filter)
		if !valid || !matched do return false
	}
	return true
}

@(private)
agenda_predicates_match :: proc(state: ^Agenda_Index_State, entry: Agenda_Entry_Record, tokens: []Agenda_Predicate_Token) -> (bool, bool) {
	if len(tokens) == 0 || len(tokens) > MAX_AGENDA_PREDICATES do return false, false
	stack: [MAX_AGENDA_PREDICATES]bool
	depth := 0
	for token in tokens {
		switch token.kind {
		case .Task, .Tag, .Property, .Text, .Timestamp, .Project, .Stuck_Project, .Clock, .Effort, .Entry_Kind:
			if depth >= len(stack) do return false, false
			value := false
			#partial switch token.kind {
			case .Task:          value = entry.task_state == token.primary
			case .Tag:           value = agenda_entry_has_tag(state, entry, token.primary)
			case .Property:      value = agenda_entry_has_property(state, entry, token.primary, token.secondary)
			case .Text:          value = len(token.primary) > 0 && strings.contains(entry.plain_text, token.primary)
			case .Timestamp:     value = agenda_time_matches(entry, token.start_time, token.end_time)
			case .Project:       value = entry.project == token.primary
			case .Stuck_Project: value = entry.stuck_project
			case .Clock:         value = entry.clock_seconds > 0
			case .Effort:        value = entry.effort_seconds > 0
			case .Entry_Kind:    value = entry.kind == token.entry_kind
			}
			stack[depth] = value
			depth += 1
		case .Not:
			if depth < 1 do return false, false
			stack[depth - 1] = !stack[depth - 1]
		case .And, .Or:
			if depth < 2 do return false, false
			right, left := stack[depth - 1], stack[depth - 2]
			depth -= 1
			stack[depth - 1] = left && right if token.kind == .And else left || right
		case .Invalid:
			return false, false
		}
	}
	return stack[0], depth == 1
}

@(private)
agenda_time_matches :: proc(entry: Agenda_Entry_Record, start_time, end_time: i64) -> bool {
	if start_time > end_time do return false
	return entry.timestamp != 0 && entry.timestamp >= start_time && entry.timestamp <= end_time ||
	       entry.scheduled != 0 && entry.scheduled >= start_time && entry.scheduled <= end_time ||
	       entry.deadline != 0 && entry.deadline >= start_time && entry.deadline <= end_time
}

@(private)
agenda_entry_has_tag :: proc(state: ^Agenda_Index_State, entry: Agenda_Entry_Record, name: string) -> bool {
	start, count := int(entry.tags.start), int(entry.tags.count)
	if len(name) == 0 || start + count > len(state.tags) do return false
	for tag in state.tags[start:start + count] do if tag == name do return true
	return false
}

@(private)
agenda_entry_has_property :: proc(state: ^Agenda_Index_State, entry: Agenda_Entry_Record, name, value: string) -> bool {
	start, count := int(entry.properties.start), int(entry.properties.count)
	if len(name) == 0 || start + count > len(state.properties) do return false
	for property in state.properties[start:start + count] {
		if property.name == name && (len(value) == 0 || property.value == value) do return true
	}
	return false
}

@(private)
agenda_rows_sort :: proc(rows, scratch: []u32, state: ^Agenda_Index_State, specs: []Agenda_Sort_Spec) {
	width := 1
	for width < len(rows) {
		start := 0
		for start < len(rows) {
			middle := min(start + width, len(rows))
			end := min(start + 2 * width, len(rows))
			left, right, output := start, middle, start
			for left < middle && right < end {
				if agenda_row_compare(rows[left], rows[right], state, specs) <= 0 {
					scratch[output] = rows[left]
					left += 1
				} else {
					scratch[output] = rows[right]
					right += 1
				}
				output += 1
			}
			for left < middle {
				scratch[output] = rows[left]
				left, output = left + 1, output + 1
			}
			for right < end {
				scratch[output] = rows[right]
				right, output = right + 1, output + 1
			}
			start = end
		}
		copy(rows, scratch[:len(rows)])
		width *= 2
	}
}

@(private)
agenda_row_compare :: proc(left_index, right_index: u32, state: ^Agenda_Index_State, specs: []Agenda_Sort_Spec) -> int {
	left, right := state.entries[left_index], state.entries[right_index]
	for spec in specs {
		comparison := agenda_entry_compare(left, right, spec.key)
		if comparison == 0 do continue
		return -comparison if spec.descending else comparison
	}
	if left.source_index != right.source_index do return -1 if left.source_index < right.source_index else 1
	return -1 if left_index < right_index else (1 if left_index > right_index else 0)
}

@(private)
agenda_entry_compare :: proc(left, right: Agenda_Entry_Record, key: Agenda_Sort_Key) -> int {
	switch key {
	case .Category:     return agenda_compare_strings(left.category, right.category)
	case .Time:         return agenda_compare_i64(left.timestamp, right.timestamp)
	case .Priority:     return agenda_compare_i64(i64(left.priority), i64(right.priority))
	case .Deadline:     return agenda_compare_i64(left.deadline, right.deadline)
	case .Scheduled:    return agenda_compare_i64(left.scheduled, right.scheduled)
	case .Task_State:   return agenda_compare_strings(left.task_state, right.task_state)
	case .Source_Order: return agenda_compare_i64(i64(left.source_index), i64(right.source_index))
	case .Heading_Path: return agenda_compare_strings(left.heading_path, right.heading_path)
	case .Clock:        return agenda_compare_u64(left.clock_seconds, right.clock_seconds)
	case .Effort:       return agenda_compare_u64(left.effort_seconds, right.effort_seconds)
	case .Invalid:      return 0
	}
	return 0
}

@(private)
agenda_group_text :: proc(state: ^Agenda_Index_State, entry: Agenda_Entry_Record, key: Agenda_Group_Key) -> Agenda_Display_Text {
	value := ""
	#partial switch key {
	case .Category:   value = entry.category
	case .Project:    value = entry.project
	case .Source:     value = state.sources[entry.source_index].identity
	case .Day:        return agenda_display_i64(entry.timestamp / 86_400)
	case .Task_State: value = entry.task_state
	}
	return agenda_display_copy(value)
}

@(private)
agenda_prefix_text :: proc(entry: Agenda_Entry_Record, format: Agenda_Prefix_Format) -> Agenda_Display_Text {
	value := ""
	#partial switch format {
	case .Category:     value = entry.category
	case .Task_State:   value = entry.task_state
	case .Priority:     return agenda_display_i64(i64(entry.priority))
	case .Time:         return agenda_display_time(entry.time_of_day_minutes)
	case .Heading_Path: value = entry.heading_path
	}
	return agenda_display_copy(value)
}

@(private)
agenda_display_copy :: proc(value: string) -> Agenda_Display_Text {
	result: Agenda_Display_Text
	result.length = u16(copy(result.bytes[:], value[:min(len(value), len(result.bytes))]))
	result.truncated = len(value) > len(result.bytes)
	return result
}

@(private)
agenda_display_i64 :: proc(value: i64) -> Agenda_Display_Text {
	buffer: [32]u8
	length := agenda_write_i64(buffer[:], value)
	return agenda_display_copy(string(buffer[:length]))
}

@(private)
agenda_display_time :: proc(minutes: i16) -> Agenda_Display_Text {
	if minutes < 0 do return {}
	buffer: [5]u8
	hour, minute := int(minutes) / 60, int(minutes) % 60
	buffer[0] = byte('0' + hour / 10)
	buffer[1] = byte('0' + hour % 10)
	buffer[2] = ':'
	buffer[3] = byte('0' + minute / 10)
	buffer[4] = byte('0' + minute % 10)
	return agenda_display_copy(string(buffer[:]))
}

@(private)
agenda_write_i64 :: proc(output: []u8, value: i64) -> int {
	negative := value < 0
	magnitude := u64(-(value + 1)) + 1 if negative else u64(value)
	temporary: [32]u8
	count := 0
	for {
		temporary[count] = byte('0' + magnitude % 10)
		count += 1
		magnitude /= 10
		if magnitude == 0 do break
	}
	position := 0
	if negative {
		output[position] = '-'
		position += 1
	}
	for index in 0 ..< count {
		output[position] = temporary[count - index - 1]
		position += 1
	}
	return position
}

@(private)
agenda_compare_strings :: proc(left, right: string) -> int {
	return -1 if left < right else (1 if left > right else 0)
}

@(private)
agenda_compare_i64 :: proc(left, right: i64) -> int {
	return -1 if left < right else (1 if left > right else 0)
}

@(private)
agenda_compare_u64 :: proc(left, right: u64) -> int {
	return -1 if left < right else (1 if left > right else 0)
}

@(private)
agenda_resource_equal :: proc(left, right: Resource_Identity) -> bool {
	if left.provider != right.provider || left.key.length != right.key.length do return false
	left_copy, right_copy := left, right
	return resource_identity_text(&left_copy) == resource_identity_text(&right_copy)
}

@(private)
agenda_arena_copy :: proc(arena: []u8, cursor: ^int, text: string) -> string {
	start := cursor^
	copy(arena[start:start + len(text)], text)
	cursor^ += len(text)
	return string(arena[start:cursor^])
}

@(private)
agenda_index_state :: proc(index: ^Agenda_Index) -> ^Agenda_Index_State {
	if index == nil || index.state == nil do return nil
	return cast(^Agenda_Index_State)index.state
}

@(private)
agenda_index_state_close :: proc(state: ^Agenda_Index_State) {
	if state == nil do return
	allocator := state.allocator
	if state.sources != nil do delete(state.sources, allocator)
	if state.entries != nil do delete(state.entries, allocator)
	if state.tags != nil do delete(state.tags, allocator)
	if state.properties != nil do delete(state.properties, allocator)
	if state.arena != nil do delete(state.arena, allocator)
	state^ = {}
	free(state, allocator)
}

@(private)
agenda_query_state :: proc(result: ^Agenda_Query_Result) -> ^Agenda_Query_State {
	if result == nil || result.state == nil do return nil
	return cast(^Agenda_Query_State)result.state
}

@(private)
agenda_query_state_close :: proc(state: ^Agenda_Query_State) {
	if state == nil do return
	allocator := state.allocator
	if state.rows != nil do delete(state.rows, allocator)
	state^ = {}
	free(state, allocator)
}

@(private)
agenda_failure :: proc(operation_id: Operation_ID, code: Failure_Code, field: Failure_Field) -> Failure {
	return {operation_id = operation_id, kind = .Agenda, code = code, field = field}
}
