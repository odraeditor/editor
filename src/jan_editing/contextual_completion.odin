// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../editor"
import "../language"
import "base:runtime"
import "core:unicode/utf8"

@(private) FACTORY_COMPLETION_KEYWORDS := [?]string{"#+title:", "#+author:", "#+options:"}
@(private) FACTORY_COMPLETION_TASK_STATES := [?]string{"TODO", "DONE"}
@(private) FACTORY_COMPLETION_TAGS := [?]string{"work", "note"}
@(private) FACTORY_COMPLETION_PROPERTIES := [?]string{"ID", "CUSTOM_ID"}
@(private) FACTORY_COMPLETION_LINK_FORMS := [?]string{"file:", "https:", "id:"}
@(private) FACTORY_COMPLETION_TARGETS := [?]string{"<<target>>", "<<<radio-target>>>"}
@(private) FACTORY_COMPLETION_BLOCK_NAMES := [?]string{"src", "example", "quote", "comment"}
@(private) FACTORY_COMPLETION_LANGUAGES := [?]string{"odin", "racket", "go", "rust", "typescript"}
@(private) FACTORY_COMPLETION_HEADER_ARGUMENTS := [?]string{":results", ":exports", ":tangle"}
@(private) FACTORY_COMPLETION_FILE_SETTINGS := [?]string{"#+startup:", "#+property:", "#+language:"}

/* Completion_Candidate_ID identifies one candidate within one immutable result. */
Completion_Candidate_ID :: distinct u16

/* Contextual_Completion_Request binds one syntax family to exact source and configuration. */
Contextual_Completion_Request :: struct {
	operation_id:     Operation_ID,
	scope:            Scope,
	point:            editor.Byte_Offset,
	kind:             Completion_Kind,
	cancel_requested: ^bool,
}

/* Completion_Candidate is one copied source-only insertion proposal. */
Completion_Candidate :: struct {
	id:                     Completion_Candidate_ID,
	kind:                   Completion_Kind,
	provider:               string,
	text:                   string,
	replacement:            language.Jan_Source_Range,
	owner_id:               language.Jan_Node_ID,
	configuration_generation: Configuration_Generation,
	provider_generation:    Provider_Generation,
	factory:                 bool,
}

/* Completion_Result_Descriptor reports exact identity and bounded accounting. */
Completion_Result_Descriptor :: struct {
	operation_id:             Operation_ID,
	scope:                    Scope,
	kind:                     Completion_Kind,
	candidate_count:          u16,
	factory_candidates:       u16,
	configured_candidates:    u16,
	retained_bytes:           u64,
}

/* Completion_Result owns copied candidates until explicit close. */
Completion_Result :: struct {
	state: rawptr,
}

@(private)
Owned_Completion_Candidate :: struct {
	value:    Completion_Candidate,
	provider: []u8,
	text:     []u8,
}

@(private)
Completion_Result_State :: struct {
	descriptor: Completion_Result_Descriptor,
	candidates: []Owned_Completion_Candidate,
	views:      []Completion_Candidate,
	allocator:  runtime.Allocator,
}

/* contextual_completion_prepare composes factory and configured syntax candidates. */
contextual_completion_prepare :: proc(
	result: ^Completion_Result,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	configuration: ^Editing_Configuration,
	request: Contextual_Completion_Request,
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (descriptor: Completion_Result_Descriptor, ok: bool, failure: Failure) {
	if result == nil || result.state != nil || analysis == nil || configuration == nil ||
	   request.operation_id == Operation_ID(0) || !scope_is_valid(request.scope) ||
	   request.kind <= .Invalid || request.kind > .File_Setting ||
	   u64(request.point) > u64(len(source)) || !utf8.valid_string(string(source)) ||
	   !limits_are_valid(limits) || allocator.procedure == nil || temporary_allocator.procedure == nil {
		return {}, false, editing_failure(.Complete, .Invalid_Scope, request.scope)
	}
	if request.cancel_requested != nil && request.cancel_requested^ {
		return {}, false, editing_failure(.Complete, .Cancelled, request.scope)
	}
	config_descriptor, configured := editing_configuration_inspect(configuration)
	if !configured || config_descriptor.generation != request.scope.configuration_generation ||
	   config_descriptor.provider_generation != request.scope.provider_generation {
		return {}, false, editing_failure(.Complete, .Stale, request.scope)
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != u64(len(source)) || len(nodes) == 0 ||
	   nodes[0].range.scope != request.scope.analysis {
		return {}, false, editing_failure(.Complete, .Stale, request.scope)
	}
	replacement := contextual_completion_replacement_range(source, request.scope.analysis, request.point)
	owner, owner_found := contextual_completion_replacement_owner(nodes, replacement)
	if !owner_found || !contextual_completion_kind_admitted(source, request.point, request.kind, owner.kind) {
		return {}, false, editing_failure(.Complete, .Unavailable, request.scope)
	}
	entries, entries_error := make(
		[dynamic]Owned_Completion_Candidate,
		0,
		min(int(limits.completion_candidates), 32),
		temporary_allocator,
	)
	if entries_error != nil {
		return {}, false, editing_failure(.Complete, .Allocation_Failed, request.scope)
	}
	defer contextual_completion_entries_destroy(entries[:], temporary_allocator)
	factory_count: u16
	for value in contextual_completion_factory_values(request.kind) {
		if !contextual_completion_entry_append(
			&entries,
			request,
			replacement,
			owner.id,
			"odra-factory",
			value,
			true,
			limits,
			temporary_allocator,
		) {
			return {}, false, contextual_completion_limit_or_allocation_failure(request, entries, limits)
		}
		factory_count += 1
	}
	configured_count: u16
	for source_index in 0 ..< int(config_descriptor.completion_sources) {
		provider, found := editing_configuration_completion_source(configuration, source_index)
		if !found || provider.kind != request.kind do continue
		if !contextual_completion_source_fits(entries[:], provider, limits) do continue
		for value in provider.candidates {
			if contextual_completion_contains(entries[:], value) do continue
			if !contextual_completion_entry_append(
				&entries,
				request,
				replacement,
				owner.id,
				provider.name,
				value,
				false,
				limits,
				temporary_allocator,
			) {
				return {}, false, contextual_completion_limit_or_allocation_failure(request, entries, limits)
			}
			configured_count += 1
		}
	}
	state, state_error := new(Completion_Result_State, allocator)
	if state_error != nil {
		return {}, false, editing_failure(.Complete, .Allocation_Failed, request.scope)
	}
	state^ = Completion_Result_State{allocator = allocator}
	state.candidates, state_error = make([]Owned_Completion_Candidate, len(entries), allocator)
	if state_error == nil do state.views, state_error = make([]Completion_Candidate, len(entries), allocator)
	if state_error != nil {
		completion_result_state_destroy(state)
		return {}, false, editing_failure(.Complete, .Allocation_Failed, request.scope)
	}
	retained: u64
	for &entry, index in entries {
		state.candidates[index].value = entry.value
		state.candidates[index].provider, state_error = contextual_completion_text_copy(string(entry.provider), allocator)
		if state_error == nil {
			state.candidates[index].text, state_error = contextual_completion_text_copy(string(entry.text), allocator)
		}
		if state_error != nil {
			completion_result_state_destroy(state)
			return {}, false, editing_failure(.Complete, .Allocation_Failed, request.scope)
		}
		state.candidates[index].value.provider = string(state.candidates[index].provider)
		state.candidates[index].value.text = string(state.candidates[index].text)
		state.views[index] = state.candidates[index].value
		retained += u64(len(entry.provider) + len(entry.text))
	}
	state.descriptor = {
		operation_id = request.operation_id,
		scope = request.scope,
		kind = request.kind,
		candidate_count = u16(len(entries)),
		factory_candidates = factory_count,
		configured_candidates = configured_count,
		retained_bytes = retained,
	}
	result.state = state
	return state.descriptor, true, {}
}

/* completion_result_candidates borrows copied candidates until explicit close. */
completion_result_candidates :: proc(result: ^Completion_Result) -> []Completion_Candidate {
	state := completion_result_state(result)
	if state == nil do return nil
	return state.views
}

/* completion_result_close releases all copied provider and candidate text. */
completion_result_close :: proc(result: ^Completion_Result) {
	if result == nil do return
	state := completion_result_state(result)
	if state != nil do completion_result_state_destroy(state)
	result.state = nil
}

/* completion_candidate_plan_prepare inserts one candidate through a checked source owner. */
completion_candidate_plan_prepare :: proc(
	plan: ^language.Jan_Rewrite_Plan,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	candidate: Completion_Candidate,
	rewrite_generation: language.Jan_Rewrite_Generation,
	allocator := context.allocator,
) -> (bool, Failure) {
	if plan == nil || analysis == nil || candidate.id == Completion_Candidate_ID(0) ||
	   candidate.owner_id == language.Jan_Node_ID(0) ||
	   candidate.configuration_generation == Configuration_Generation(0) ||
	   candidate.provider_generation == Provider_Generation(0) ||
	   rewrite_generation == language.Jan_Rewrite_Generation(0) ||
	   !utf8.valid_string(candidate.text) {
		return false, editing_failure(.Complete, .Invalid_Target, {})
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	owner, found := navigation_node_by_id(nodes, candidate.owner_id)
	if !found || owner.range.scope != candidate.replacement.scope ||
	   candidate.replacement.start < owner.range.start || candidate.replacement.end > owner.range.end ||
	   u64(owner.range.end) > u64(len(source)) {
		return false, editing_failure(.Complete, .Stale, {})
	}
	replacement_bytes := int(owner.range.end - owner.range.start) -
		int(candidate.replacement.end - candidate.replacement.start) + len(candidate.text)
	replacement, allocation_error := make([]u8, replacement_bytes, allocator)
	if allocation_error != nil do return false, editing_failure(.Complete, .Allocation_Failed, {})
	defer delete(replacement, allocator)
	left := int(candidate.replacement.start - owner.range.start)
	copy(replacement[:left], source[int(owner.range.start):int(candidate.replacement.start)])
	copy(replacement[left:left + len(candidate.text)], transmute([]u8)candidate.text)
	copy(replacement[left + len(candidate.text):], source[int(candidate.replacement.end):int(owner.range.end)])
	requests := []language.Jan_Rewrite_Request{{
		node_id = owner.id,
		range = owner.range,
		replacement = string(replacement),
	}}
	planned, jan_failure := language.jan_rewrite_plan_prepare(
		plan,
		analysis,
		source,
		rewrite_generation,
		requests,
		allocator = allocator,
	)
	if !planned do return false, contextual_completion_failure_from_language(jan_failure)
	return true, {}
}

@(private)
contextual_completion_factory_values :: proc(kind: Completion_Kind) -> []string {
	switch kind {
	case .Keyword:         return FACTORY_COMPLETION_KEYWORDS[:]
	case .Task_State:      return FACTORY_COMPLETION_TASK_STATES[:]
	case .Tag:             return FACTORY_COMPLETION_TAGS[:]
	case .Property:        return FACTORY_COMPLETION_PROPERTIES[:]
	case .Link_Form:       return FACTORY_COMPLETION_LINK_FORMS[:]
	case .Target:          return FACTORY_COMPLETION_TARGETS[:]
	case .Block_Name:      return FACTORY_COMPLETION_BLOCK_NAMES[:]
	case .Language:        return FACTORY_COMPLETION_LANGUAGES[:]
	case .Header_Argument: return FACTORY_COMPLETION_HEADER_ARGUMENTS[:]
	case .File_Setting:    return FACTORY_COMPLETION_FILE_SETTINGS[:]
	case .Invalid:
	}
	return nil
}

@(private)
contextual_completion_kind_admitted :: proc(
	source: []u8,
	point: editor.Byte_Offset,
	kind: Completion_Kind,
	owner_kind: language.Jan_Node_Kind,
) -> bool {
	line_start := int(point)
	for line_start > 0 && source[line_start - 1] != '\n' do line_start -= 1
	prefix := source[line_start:int(point)]
	switch kind {
	case .Keyword, .File_Setting:
		return len(prefix) >= 2 && prefix[0] == '#' && prefix[1] == '+'
	case .Task_State:
		return owner_kind == .Heading || contextual_completion_heading_prefix(prefix)
	case .Tag:
		return owner_kind == .Heading || (len(prefix) > 0 && prefix[len(prefix) - 1] == ':')
	case .Property:
		return owner_kind == .Node_Property || owner_kind == .Property_Drawer
	case .Link_Form:
		return owner_kind == .Regular_Link || owner_kind == .Plain_Link ||
		       (len(prefix) >= 2 && prefix[len(prefix) - 2] == '[' && prefix[len(prefix) - 1] == '[')
	case .Target:
		return owner_kind == .Paragraph || owner_kind == .Target || owner_kind == .Radio_Target
	case .Block_Name:
		return len(prefix) >= 8 && string(prefix[:8]) == "#+begin_"
	case .Language:
		return owner_kind == .Source_Block || contextual_completion_prefix_contains(prefix, "#+begin_src")
	case .Header_Argument:
		return owner_kind == .Source_Block || contextual_completion_prefix_contains(prefix, "#+begin_src")
	case .Invalid:
	}
	return false
}

@(private)
contextual_completion_prefix_contains :: proc(prefix: []u8, needle: string) -> bool {
	if len(prefix) < len(needle) do return false
	for index in 0 ..= len(prefix) - len(needle) {
		if string(prefix[index:index + len(needle)]) == needle do return true
	}
	return false
}

@(private)
contextual_completion_heading_prefix :: proc(prefix: []u8) -> bool {
	index := 0
	for index < len(prefix) && prefix[index] == '*' do index += 1
	return index > 0 && index < len(prefix) && prefix[index] == ' '
}

@(private)
contextual_completion_owner :: proc(
	nodes: []language.Jan_Node_Record,
	point: editor.Byte_Offset,
) -> (language.Jan_Node_Record, bool) {
	selected: language.Jan_Node_Record
	found := false
	for node in nodes {
		if point < node.range.start || point > node.range.end do continue
		if !found || node.range.end - node.range.start < selected.range.end - selected.range.start {
			selected = node
			found = true
		}
	}
	return selected, found
}

@(private)
contextual_completion_replacement_owner :: proc(
	nodes: []language.Jan_Node_Record,
	replacement: language.Jan_Source_Range,
) -> (language.Jan_Node_Record, bool) {
	selected: language.Jan_Node_Record
	found := false
	for node in nodes {
		if node.range.start > replacement.start || node.range.end < replacement.end do continue
		if !found || node.range.end - node.range.start < selected.range.end - selected.range.start {
			selected = node
			found = true
		}
	}
	return selected, found
}

@(private)
contextual_completion_replacement_range :: proc(
	source: []u8,
	scope: language.Jan_Analysis_Scope,
	point: editor.Byte_Offset,
) -> language.Jan_Source_Range {
	start := int(point)
	for start > 0 {
		value := source[start - 1]
		if value == ' ' || value == '\t' || value == '\n' || value == '[' || value == ':' do break
		start -= 1
	}
	return {scope = scope, start = editor.Byte_Offset(start), end = point}
}

@(private)
contextual_completion_entry_append :: proc(
	entries: ^[dynamic]Owned_Completion_Candidate,
	request: Contextual_Completion_Request,
	replacement: language.Jan_Source_Range,
	owner_id: language.Jan_Node_ID,
	provider, text: string,
	factory: bool,
	limits: Limits,
	allocator: runtime.Allocator,
) -> bool {
	if len(entries^) >= int(limits.completion_candidates) do return false
	retained := len(provider) + len(text)
	for entry in entries^ do retained += len(entry.provider) + len(entry.text)
	if u64(retained) > limits.completion_bytes do return false
	provider_copy, allocation_error := contextual_completion_text_copy(provider, allocator)
	if allocation_error != nil do return false
	text_copy, text_error := contextual_completion_text_copy(text, allocator)
	if text_error != nil {
		delete(provider_copy, allocator)
		return false
	}
	entry := Owned_Completion_Candidate{
		value = {
			id = Completion_Candidate_ID(len(entries^) + 1),
			kind = request.kind,
			provider = string(provider_copy),
			text = string(text_copy),
			replacement = replacement,
			owner_id = owner_id,
			configuration_generation = request.scope.configuration_generation,
			provider_generation = request.scope.provider_generation,
			factory = factory,
		},
		provider = provider_copy,
		text = text_copy,
	}
	if _, append_error := append(entries, entry); append_error != nil {
		delete(provider_copy, allocator)
		delete(text_copy, allocator)
		return false
	}
	return true
}

@(private)
contextual_completion_contains :: proc(entries: []Owned_Completion_Candidate, text: string) -> bool {
	for entry in entries {
		if string(entry.text) == text do return true
	}
	return false
}

@(private)
contextual_completion_source_fits :: proc(
	entries: []Owned_Completion_Candidate,
	provider: Configured_Completion_Source,
	limits: Limits,
) -> bool {
	count := len(entries)
	retained: u64
	for entry in entries do retained += u64(len(entry.provider) + len(entry.text))
	for value in provider.candidates {
		if contextual_completion_contains(entries, value) do continue
		count += 1
		retained += u64(len(provider.name) + len(value))
	}
	return count <= int(limits.completion_candidates) && retained <= limits.completion_bytes
}

@(private)
contextual_completion_limit_or_allocation_failure :: proc(
	request: Contextual_Completion_Request,
	entries: [dynamic]Owned_Completion_Candidate,
	limits: Limits,
) -> Failure {
	if len(entries) >= int(limits.completion_candidates) {
		failure := editing_failure(.Complete, .Limited, request.scope)
		failure.limit = u64(limits.completion_candidates)
		failure.actual = u64(len(entries)) + 1
		return failure
	}
	retained: u64
	for entry in entries do retained += u64(len(entry.provider) + len(entry.text))
	if retained >= limits.completion_bytes {
		failure := editing_failure(.Complete, .Limited, request.scope)
		failure.limit = limits.completion_bytes
		failure.actual = retained + 1
		return failure
	}
	return editing_failure(.Complete, .Allocation_Failed, request.scope)
}

@(private)
contextual_completion_entries_destroy :: proc(entries: []Owned_Completion_Candidate, allocator: runtime.Allocator) {
	for entry in entries {
		if entry.provider != nil do delete(entry.provider, allocator)
		if entry.text != nil do delete(entry.text, allocator)
	}
}

@(private)
contextual_completion_text_copy :: proc(text: string, allocator: runtime.Allocator) -> ([]u8, runtime.Allocator_Error) {
	result, allocation_error := make([]u8, len(text), allocator)
	if allocation_error != nil do return nil, allocation_error
	copy(result, transmute([]u8)text)
	return result, nil
}

@(private)
completion_result_state :: proc(result: ^Completion_Result) -> ^Completion_Result_State {
	if result == nil || result.state == nil do return nil
	return cast(^Completion_Result_State)result.state
}

@(private)
completion_result_state_destroy :: proc(state: ^Completion_Result_State) {
	if state == nil do return
	for &candidate in state.candidates {
		if candidate.provider != nil do delete(candidate.provider, state.allocator)
		if candidate.text != nil do delete(candidate.text, state.allocator)
	}
	if state.candidates != nil do delete(state.candidates, state.allocator)
	if state.views != nil do delete(state.views, state.allocator)
	allocator := state.allocator
	free(state, allocator)
}

@(private)
contextual_completion_failure_from_language :: proc(jan: language.Jan_Failure) -> Failure {
	code := Failure_Code.Invalid_Target
	#partial switch jan.code {
	case .Stale, .Incomplete: code = .Stale
	case .Limited: code = .Limited
	case .Allocation_Failed: code = .Allocation_Failed
	case .Malformed: code = .Malformed
	case .Cancelled: code = .Cancelled
	}
	return {operation = .Complete, code = code, limit = jan.limit, actual = jan.actual}
}
