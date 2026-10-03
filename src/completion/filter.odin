// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package completion

import "base:runtime"
import "core:slice"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

/* Match_Class orders one candidate's relationship to the current query. */
Match_Class :: enum u8 {
	Invalid,
	Exact,
	Case_Sensitive_Prefix,
	Case_Insensitive_Prefix,
	Subsequence,
}

/* Filter_Policy selects the bounded factory matching classes. */
Filter_Policy :: struct {
	case_sensitive_prefix:   bool,
	case_insensitive_prefix: bool,
	subsequence:             bool,
}

/* DEFAULT_FILTER_POLICY enables every initial deterministic match class. */
DEFAULT_FILTER_POLICY :: Filter_Policy {
	case_sensitive_prefix = true,
	case_insensitive_prefix = true,
	subsequence = true,
}

/* Projection_Item references one exact candidate in an immutable batch. */
Projection_Item :: struct {
	candidate_id: Candidate_ID,
	source_index: u16,
	match_class:  Match_Class,
	provider_order: u32,
	sort_text:    Text,
	label:        Text,
}

/* Projection owns one filtered and deterministically ordered candidate view. */
Projection :: struct {
	batch_id:         Batch_ID,
	batch_generation: Batch_Generation,
	generation:       Projection_Generation,
	query:            Text,
	items:            []Projection_Item,
	item_count:       u16,
	deduplicated:     u16,
	selected:         Candidate_ID,
	retained_bytes:   u64,
	allocator:        runtime.Allocator,
	closed:           bool,
}

/* projection_build filters one exact batch and preserves visible selection. */
projection_build :: proc(
	batch: ^Batch,
	request: ^Request,
	query: Query_Context,
	previous_selection := Candidate_ID(0),
	policy := DEFAULT_FILTER_POLICY,
	generation := Projection_Generation(1),
	allocator := context.allocator,
) -> (Projection, bool, Failure) {
	query_value := query
	if batch == nil || request == nil || !batch_is_valid(batch, request) ||
	   !query_context_is_valid(&query_value) || query.range.start != batch.query_range.start ||
	   query.range.end < query.range.start || generation == Projection_Generation(0) ||
	   allocator.procedure == nil {
		return {}, false, failure(.Update, .Invalid_State)
	}
	items, allocation_error := make([]Projection_Item, len(batch.items), allocator)
	if allocation_error != nil do return {}, false, failure(.Update, .Allocation)
	accepted := 0
	deduplicated := u32(0)
	query_storage := query.text
	query_text := text_view(&query_storage)
	for candidate, source_index in batch.items {
		duplicate := false
		candidate_value := candidate
		for earlier_index in 0 ..< source_index {
			if completion_candidates_equivalent(&candidate_value, &batch.items[earlier_index]) {
				duplicate = true
				break
			}
		}
		if duplicate {
			deduplicated += 1
			continue
		}
		filter := candidate.filter_text
		candidate_text := text_view(&filter)
		if candidate_text == "" {
			label := candidate.label
			candidate_text = text_view(&label)
		}
		match_class := completion_match_class(candidate_text, query_text, policy)
		if match_class == .Invalid do continue
		items[accepted] = {
			candidate_id = candidate.id,
			source_index = u16(source_index),
			match_class = match_class,
			provider_order = candidate.provenance.provider_order,
			sort_text = candidate.sort_text,
			label = candidate.label,
		}
		accepted += 1
	}
	items = items[:accepted]
	slice.sort_by(items, completion_projection_less)
	selected := Candidate_ID(0)
	for item in items {
		if item.candidate_id == previous_selection {
			selected = previous_selection
			break
		}
	}
	if selected == Candidate_ID(0) && len(items) > 0 do selected = items[0].candidate_id
	return Projection {
		batch_id = batch.id,
		batch_generation = batch.generation,
		generation = generation,
		query = query.text,
		items = items,
		item_count = u16(accepted),
		deduplicated = u16(min(deduplicated, u32(max(u16)))),
		selected = selected,
		retained_bytes = u64(len(items)) * u64(size_of(Projection_Item)),
		allocator = allocator,
	}, true, {}
}

/* projection_close releases one filtered projection exactly once. */
projection_close :: proc(projection: ^Projection) -> bool {
	if projection == nil || projection.closed || projection.allocator.procedure == nil do return false
	if projection.items != nil do delete(projection.items, projection.allocator)
	projection^ = Projection{closed = true}
	return true
}

@(private = "file")
completion_match_class :: proc(candidate, query: string, policy: Filter_Policy) -> Match_Class {
	if candidate == query do return .Exact
	if policy.case_sensitive_prefix && strings.has_prefix(candidate, query) {
		return .Case_Sensitive_Prefix
	}
	if policy.case_insensitive_prefix && completion_folded_prefix(candidate, query) {
		return .Case_Insensitive_Prefix
	}
	if policy.subsequence && completion_folded_subsequence(candidate, query) {
		return .Subsequence
	}
	return .Invalid
}

@(private = "file")
completion_folded_prefix :: proc(candidate, query: string) -> bool {
	candidate_index, query_index := 0, 0
	for query_index < len(query) {
		if candidate_index >= len(candidate) do return false
		candidate_rune, candidate_width := utf8.decode_rune(candidate[candidate_index:])
		query_rune, query_width := utf8.decode_rune(query[query_index:])
		if candidate_width <= 0 || query_width <= 0 ||
		   unicode.to_lower(candidate_rune) != unicode.to_lower(query_rune) {
			return false
		}
		candidate_index += candidate_width
		query_index += query_width
	}
	return true
}

@(private = "file")
completion_folded_subsequence :: proc(candidate, query: string) -> bool {
	if query == "" do return true
	candidate_index, query_index := 0, 0
	query_rune, query_width := utf8.decode_rune(query)
	if query_width <= 0 do return false
	for candidate_index < len(candidate) {
		candidate_rune, candidate_width := utf8.decode_rune(candidate[candidate_index:])
		if candidate_width <= 0 do return false
		candidate_index += candidate_width
		if unicode.to_lower(candidate_rune) != unicode.to_lower(query_rune) do continue
		query_index += query_width
		if query_index == len(query) do return true
		query_rune, query_width = utf8.decode_rune(query[query_index:])
		if query_width <= 0 do return false
	}
	return false
}

@(private = "file")
completion_projection_less :: proc(left, right: Projection_Item) -> bool {
	if left.match_class != right.match_class do return left.match_class < right.match_class
	left_sort := left.sort_text
	right_sort := right.sort_text
	left_text := text_view(&left_sort)
	right_text := text_view(&right_sort)
	if left_text == "" {
		left_label := left.label
		left_text = text_view(&left_label)
	}
	if right_text == "" {
		right_label := right.label
		right_text = text_view(&right_label)
	}
	if left_text != right_text do return left_text < right_text
	if left.provider_order != right.provider_order do return left.provider_order < right.provider_order
	return left.candidate_id < right.candidate_id
}

@(private = "file")
completion_candidates_equivalent :: proc(left, right: ^Candidate) -> bool {
	if left == nil || right == nil do return false
	left_value := left^
	right_value := right^
	left_value.id = 0
	right_value.id = 0
	left_value.provenance.provider_order = 0
	right_value.provenance.provider_order = 0
	return left_value == right_value
}
