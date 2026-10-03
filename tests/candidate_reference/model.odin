// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package candidate_reference provides an allocation-visible contiguous candidate oracle.
package candidate_reference

import "core:slice"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

MAX_QUERY_BYTES :: 4 * 1_024
MAX_QUERY_COMPONENTS :: 8

Identity :: struct {
	kind:      u16,
	primary:   u64,
	secondary: u64,
}

Candidate :: struct {
	identity:          Identity,
	label:             string,
	folded_label:      string,
	searchable_fields: []string,
	recency:           u64,
}

Match_Class :: enum u8 {
	Invalid,
	Exact_Label,
	Prefix_Or_Boundary,
	Literal,
	Pattern,
	Empty,
}

Projection :: struct {
	candidate_index: int,
	match_class:     Match_Class,
	recency:         u64,
	folded_label:    string,
	identity:        Identity,
}

Failure_Code :: enum u8 {
	None,
	Malformed_UTF8,
	Query_Limit,
	Component_Limit,
	Output_Limit,
	Allocation,
}

Failure :: struct {
	code:   Failure_Code,
	limit:  u64,
	actual: u64,
}

filter :: proc(
	candidates: []Candidate,
	query: string,
	output: []Projection,
	allocator := context.temp_allocator,
) -> (count: int, ok: bool, failure: Failure) {
	if !utf8.valid_string(query) {
		return 0, false, Failure{code = .Malformed_UTF8, actual = u64(len(query))}
	}
	if len(query) > MAX_QUERY_BYTES {
		return 0, false, Failure {
			code = .Query_Limit,
			limit = MAX_QUERY_BYTES,
			actual = u64(len(query)),
		}
	}
	if len(candidates) > len(output) {
		return 0, false, Failure {
			code = .Output_Limit,
			limit = u64(len(output)),
			actual = u64(len(candidates)),
		}
	}
	if allocator.procedure == nil {
		return 0, false, Failure{code = .Allocation}
	}
	folded_query, fold_error := strings.to_lower(query, allocator)
	if fold_error != nil {
		return 0, false, Failure{code = .Allocation}
	}
	defer delete(folded_query, allocator)
	components, fields_error := strings.fields(folded_query, allocator)
	if fields_error != nil {
		return 0, false, Failure{code = .Allocation}
	}
	defer delete(components, allocator)
	if len(components) > MAX_QUERY_COMPONENTS {
		return 0, false, Failure {
			code = .Component_Limit,
			limit = MAX_QUERY_COMPONENTS,
			actual = u64(len(components)),
		}
	}
	for candidate, candidate_index in candidates {
		match_class, matched := candidate_match(candidate, query, components)
		if !matched {
			continue
		}
		output[count] = Projection {
			candidate_index = candidate_index,
			match_class = match_class,
			recency = candidate.recency,
			folded_label = candidate.folded_label,
			identity = candidate.identity,
		}
		count += 1
	}
	slice.sort_by(output[:count], projection_less)
	return count, true, {}
}

candidate_match :: proc(
	candidate: Candidate,
	query: string,
	components: []string,
) -> (match_class: Match_Class, matched: bool) {
	if len(components) == 0 {
		return .Empty, true
	}
	if strings.equal_fold(candidate.label, query) {
		return .Exact_Label, true
	}
	match_class = .Prefix_Or_Boundary
	for component in components {
		component_class, component_matched := component_match(candidate, component)
		if !component_matched {
			return .Invalid, false
		}
		if component_class > match_class {
			match_class = component_class
		}
	}
	return match_class, true
}

@(private)
component_match :: proc(
	candidate: Candidate,
	component: string,
) -> (match_class: Match_Class, matched: bool) {
	if contains_at_boundary(candidate.folded_label, component) {
		return .Prefix_Or_Boundary, true
	}
	if strings.contains(candidate.folded_label, component) {
		return .Literal, true
	}
	for field in candidate.searchable_fields {
		if strings.contains(field, component) {
			return .Literal, true
		}
	}
	return .Invalid, false
}

@(private)
contains_at_boundary :: proc(text, component: string) -> bool {
	offset := 0
	for offset <= len(text) {
		index := strings.index(text[offset:], component)
		if index < 0 {
			return false
		}
		start := offset + index
		if start == 0 {
			return true
		}
		previous_start := start - 1
		for previous_start > 0 && text[previous_start] & 0xc0 == 0x80 {
			previous_start -= 1
		}
		previous, _ := utf8.decode_last_rune(text[:start])
		if unicode.is_space(previous) || previous == '-' || previous == '_' ||
		   previous == '/' || previous == '.' || previous == ':' {
			return true
		}
		_, width := utf8.decode_rune(text[start:])
		offset = start + max(width, 1)
	}
	return false
}

@(private)
projection_less :: proc(left, right: Projection) -> bool {
	if left.match_class != right.match_class {
		return left.match_class < right.match_class
	}
	if left.recency != right.recency {
		return left.recency > right.recency
	}
	if left.folded_label != right.folded_label {
		return strings.compare(left.folded_label, right.folded_label) < 0
	}
	if left.identity.kind != right.identity.kind {
		return left.identity.kind < right.identity.kind
	}
	if left.identity.primary != right.identity.primary {
		return left.identity.primary < right.identity.primary
	}
	return left.identity.secondary < right.identity.secondary
}
