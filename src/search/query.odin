// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package search

import "base:runtime"
import "core:mem"
import "core:strings"
import "core:text/regex"
import regex_parser "core:text/regex/parser"
import regex_vm "core:text/regex/virtual_machine"
import "core:unicode"
import "core:unicode/utf8"

@(private)
Query_State :: struct {
	id:             Query_ID,
	kind:           Pattern_Kind,
	pattern:        []byte,
	pattern_runes:  u64,
	policy:         Policy,
	effective_case: Effective_Case,
	limits:         Limits,
	allocator:      runtime.Allocator,
	compiled_regex: regex.Regular_Expression,
	has_compiled_regex: bool,
	defined_capture_groups: u16,
}

/* limits_are_valid reports whether a limit set is internally consistent and admitted. */
limits_are_valid :: proc(limits: Limits) -> bool {
	return limits.pattern_bytes >= MIN_PATTERN_BYTES &&
		limits.pattern_bytes <= MAX_PATTERN_BYTES &&
		limits.scan_window_bytes >= MIN_SCAN_WINDOW_BYTES &&
		limits.scan_window_bytes <= MAX_SCAN_WINDOW_BYTES &&
		limits.scan_window_bytes >= limits.pattern_bytes &&
		limits.cancellation_bytes >= MIN_CANCELLATION_BYTES &&
		limits.cancellation_bytes <= MAX_CANCELLATION_BYTES &&
		limits.cancellation_bytes % limits.scan_window_bytes == 0 &&
		limits.retained_occurrences >= MIN_RETAINED_OCCURRENCES &&
		limits.retained_occurrences <= MAX_RETAINED_OCCURRENCES &&
		limits.temporary_bytes >= MIN_TEMPORARY_BYTES &&
		limits.temporary_bytes <= MAX_TEMPORARY_BYTES &&
		limits.scan_window_bytes + limits.match_span_bytes <= limits.temporary_bytes &&
		limits.capture_groups >= MIN_CAPTURE_GROUPS &&
		limits.capture_groups <= MAX_CAPTURE_GROUPS &&
		limits.match_span_bytes >= MIN_MATCH_SPAN_BYTES &&
		limits.match_span_bytes <= MAX_MATCH_SPAN_BYTES
}

/* query_init copies and admits one immutable UTF-8 pattern or leaves query unchanged. */
query_init :: proc(query: ^Query, config: Query_Config) -> (ok: bool, failure: Failure) {
	assert(query != nil)
	assert(query.state == nil, "query is already initialized")
	if config.id == Query_ID(0) {
		return false, Failure{code = .Invalid_Query_ID}
	}
	if config.kind != .Literal && config.kind != .Regular_Expression {
		return false, Failure{code = .Invalid_Pattern_Kind, query_id = config.id}
	}
	if config.policy.case_mode != .Smart && config.policy.case_mode != .Sensitive &&
	   config.policy.case_mode != .Insensitive {
		return false, Failure{code = .Invalid_Case_Mode, query_id = config.id}
	}
	if config.policy.boundary_mode != .Unrestricted &&
	   config.policy.boundary_mode != .Word &&
	   config.policy.boundary_mode != .Symbol {
		return false, Failure{code = .Invalid_Boundary_Mode, query_id = config.id}
	}
	if config.policy.whitespace_mode != .Exact &&
	   config.policy.whitespace_mode != .Flexible {
		return false, Failure{code = .Invalid_Whitespace_Mode, query_id = config.id}
	}
	if !limits_are_valid(config.limits) {
		return false, Failure{code = .Invalid_Limits, query_id = config.id}
	}
	if len(config.pattern) == 0 {
		return false, Failure{code = .Empty_Pattern, query_id = config.id}
	}
	if !utf8.valid_string(config.pattern) {
		return false, Failure {
			code = .Malformed_UTF8,
			query_id = config.id,
			actual = u64(len(config.pattern)),
		}
	}
	if u64(len(config.pattern)) > config.limits.pattern_bytes {
		return false, Failure {
			code = .Pattern_Limit,
			query_id = config.id,
			limit = config.limits.pattern_bytes,
			actual = u64(len(config.pattern)),
		}
	}
	if config.allocator.procedure == nil {
		return false, Failure{code = .Persistent_Memory_Limit, query_id = config.id}
	}
	effective := effective_case(config.pattern, config.policy.case_mode)
	compiled_regex: regex.Regular_Expression
	has_compiled_regex := false
	defined_capture_groups: u16
	if config.kind == .Regular_Expression {
		if config.temporary_allocator.procedure == nil {
			return false, Failure{code = .Temporary_Memory_Limit, query_id = config.id}
		}
		compile_arena: mem.Dynamic_Arena
		mem.dynamic_arena_init(
			&compile_arena,
			config.temporary_allocator,
			config.temporary_allocator,
		)
		defer mem.dynamic_arena_destroy(&compile_arena)
		flags: regex.Flags = {.Unicode, .Multiline}
		if effective == .Insensitive {
			flags += {.Case_Insensitive}
		}
		compile_pattern := config.pattern
		flexible_pattern: strings.Builder
		if config.policy.whitespace_mode == .Flexible {
			builder_ok := regexp_flexible_whitespace_pattern(
				&flexible_pattern,
				config.pattern,
				config.temporary_allocator,
			)
			if !builder_ok {
				return false, Failure{code = .Temporary_Memory_Limit, query_id = config.id}
			}
			defer strings.builder_destroy(&flexible_pattern)
			compile_pattern = strings.to_string(flexible_pattern)
		}
		compile_error: regex.Error
		compiled_regex, compile_error = regex.create(
			compile_pattern,
			flags,
			config.allocator,
			mem.dynamic_arena_allocator(&compile_arena),
		)
		if compile_error != nil {
			compile_failure := regex_compile_failure(config.id, compile_error)
			return false, compile_failure
		}
		has_compiled_regex = true
		defined_capture_groups = regex_defined_capture_groups(compiled_regex)
	}

	state, state_error := new(Query_State, config.allocator)
	if state_error != nil {
		if has_compiled_regex {
			regex.destroy(compiled_regex, config.allocator)
		}
		return false, Failure {
			code = .Persistent_Memory_Limit,
			query_id = config.id,
			actual = u64(size_of(Query_State)),
		}
	}
	pattern, pattern_error := make([]byte, len(config.pattern), config.allocator)
	if pattern_error != nil {
		if has_compiled_regex {
			regex.destroy(compiled_regex, config.allocator)
		}
		free(state, config.allocator)
		return false, Failure {
			code = .Persistent_Memory_Limit,
			query_id = config.id,
			actual = u64(len(config.pattern)),
		}
	}
	copy(pattern, config.pattern)
	state.id = config.id
	state.kind = config.kind
	state.pattern = pattern
	state.pattern_runes = u64(utf8.rune_count(config.pattern))
	state.policy = config.policy
	state.effective_case = effective
	state.limits = config.limits
	state.allocator = config.allocator
	state.compiled_regex = compiled_regex
	state.has_compiled_regex = has_compiled_regex
	state.defined_capture_groups = defined_capture_groups
	query.state = state
	return true, {}
}

/* query_view borrows one live query's immutable admitted values. */
query_view :: proc(query: ^Query) -> (view: Query_View, ok: bool, failure: Failure) {
	state := query_state(query)
	if state == nil {
		return {}, false, Failure{code = .Closed_Query}
	}
	regex_profile: Regex_Profile
	if state.has_compiled_regex {
		regex_profile = Regex_Profile {
			present = true,
			unicode = true,
			multiline = true,
			case_insensitive = state.effective_case == .Insensitive,
			shorthands = .ASCII,
			capture_groups = state.limits.capture_groups,
			defined_capture_groups = state.defined_capture_groups,
			maximum_match_span_bytes = state.limits.match_span_bytes,
			scan_window_bytes = state.limits.scan_window_bytes,
		}
	}
	return Query_View {
		id = state.id,
		kind = state.kind,
		pattern = string(state.pattern),
		pattern_runes = state.pattern_runes,
		policy = state.policy,
		effective_case = state.effective_case,
		limits = state.limits,
		regex = regex_profile,
	}, true, {}
}

@(private)
regex_defined_capture_groups :: proc(compiled: regex.Regular_Expression) -> u16 {
	iterator := regex_vm.Opcode_Iterator{code = compiled.program}
	maximum: u16
	for {
		opcode, program_counter, ok := regex_vm.iterate_opcodes(&iterator)
		if !ok {
			break
		}
		if opcode != .Save {
			continue
		}
		saved_slot := u16(compiled.program[program_counter + size_of(regex_vm.Opcode)])
		maximum = max(maximum, saved_slot / 2)
	}
	return maximum
}

@(private)
regexp_flexible_whitespace_pattern :: proc(
	builder: ^strings.Builder,
	pattern: string,
	allocator: runtime.Allocator,
) -> bool {
	_, builder_error := strings.builder_init(builder, 0, len(pattern), allocator)
	if builder_error != nil {
		return false
	}
	escaped := false
	in_class := false
	index := 0
	for index < len(pattern) {
		r, width := utf8.decode_rune_in_string(pattern[index:])
		if width <= 0 {
			return false
		}
		if escaped {
			if strings.write_string(builder, pattern[index:index + width]) != width {
				return false
			}
			escaped = false
			index += width
			continue
		}
		if r == '\\' {
			if strings.write_byte(builder, '\\') != 1 {
				return false
			}
			escaped = true
			index += width
			continue
		}
		if r == '[' {
			in_class = true
		} else if r == ']' && in_class {
			in_class = false
		}
		if !in_class && unicode.is_space(r) {
			if strings.write_string(builder, "\\s+") != 3 {
				return false
			}
			index += width
			for index < len(pattern) {
				next, next_width := utf8.decode_rune_in_string(pattern[index:])
				if next_width <= 0 || !unicode.is_space(next) {
					break
				}
				index += next_width
			}
			continue
		}
		if strings.write_string(builder, pattern[index:index + width]) != width {
			return false
		}
		index += width
	}
	return true
}

/* query_reuse classifies how a new literal query relates to a previous query. */
query_reuse :: proc(previous, current: ^Query) -> (reuse: Query_Reuse, ok: bool) {
	previous_view, previous_ok, _ := query_view(previous)
	current_view, current_ok, _ := query_view(current)
	if !previous_ok || !current_ok || previous_view.kind != .Literal ||
	   current_view.kind != .Literal ||
	   previous_view.effective_case != current_view.effective_case ||
	   previous_view.policy.boundary_mode != current_view.policy.boundary_mode ||
	   previous_view.policy.whitespace_mode != current_view.policy.whitespace_mode {
		return {}, false
	}
	common := common_utf8_prefix(previous_view.pattern, current_view.pattern)
	kind := Reuse_Kind.Related
	if common == 0 {
		kind = .None
	} else if previous_view.pattern == current_view.pattern {
		kind = .Identical
	} else if strings.has_prefix(current_view.pattern, previous_view.pattern) {
		kind = .Extended
	} else if strings.has_prefix(previous_view.pattern, current_view.pattern) {
		kind = .Shortened
	}
	return Query_Reuse{kind = kind, common_prefix_bytes = common}, true
}

/* query_close releases the copied pattern and invalidates its handle exactly once. */
query_close :: proc(query: ^Query) -> (ok: bool, failure: Failure) {
	state := query_state(query)
	if state == nil {
		return false, Failure{code = .Closed_Query}
	}
	allocator := state.allocator
	query_id := state.id
	if state.has_compiled_regex {
		regex.destroy(state.compiled_regex, allocator)
	}
	delete(state.pattern, allocator)
	query.state = nil
	free(state, allocator)
	return true, Failure{query_id = query_id}
}

@(private)
query_compiled_regex :: proc(query: ^Query) -> (compiled: regex.Regular_Expression, ok: bool) {
	state := query_state(query)
	if state == nil || !state.has_compiled_regex {
		return {}, false
	}
	return state.compiled_regex, true
}

@(private)
regex_compile_failure :: proc(query_id: Query_ID, compile_error: regex.Error) -> Failure {
	failure := Failure{query_id = query_id}
	switch outer in compile_error {
	case regex.Parser_Error:
		failure.code = .Regex_Parser_Error
		failure.diagnostic = regex_parser_diagnostic(outer)
	case regex.Compiler_Error:
		failure.code = .Regex_Compiler_Error
		switch outer {
		case .None:
			failure.diagnostic.kind = .Program_Too_Big
		case .Program_Too_Big:
			failure.diagnostic.kind = .Program_Too_Big
		case .Too_Many_Classes:
			failure.diagnostic.kind = .Too_Many_Classes
		case:
			failure.diagnostic.kind = .Program_Too_Big
		}
	case regex.Creation_Error:
		failure.code = .Regex_Parser_Error
		failure.diagnostic.kind = .Invalid_Token
	}
	return failure
}

@(private)
regex_parser_diagnostic :: proc(parser_error: regex_parser.Error) -> Regex_Diagnostic {
	diagnostic: Regex_Diagnostic
	switch specific in parser_error {
	case regex_parser.Expected_Token:
		diagnostic = {kind = .Expected_Token, byte_offset = regex_error_offset(specific.pos)}
	case regex_parser.Invalid_Repetition:
		diagnostic = {kind = .Invalid_Repetition, byte_offset = regex_error_offset(specific.pos)}
	case regex_parser.Invalid_Token:
		diagnostic = {kind = .Invalid_Token, byte_offset = regex_error_offset(specific.pos)}
	case regex_parser.Invalid_Unicode:
		diagnostic = {kind = .Invalid_Unicode, byte_offset = regex_error_offset(specific.pos)}
	case regex_parser.Too_Many_Capture_Groups:
		diagnostic = {kind = .Too_Many_Capture_Groups, byte_offset = regex_error_offset(specific.pos)}
	case regex_parser.Unexpected_EOF:
		diagnostic = {kind = .Unexpected_End, byte_offset = regex_error_offset(specific.pos)}
	}
	return diagnostic
}

@(private)
regex_error_offset :: proc(position: int) -> u64 {
	if position < 0 {
		return 0
	}
	return u64(position)
}

@(private)
query_state :: proc(query: ^Query) -> ^Query_State {
	if query == nil || query.state == nil {
		return nil
	}
	return (^Query_State)(query.state)
}

@(private)
effective_case :: proc(pattern: string, mode: Case_Mode) -> Effective_Case {
	if mode == .Sensitive {
		return .Sensitive
	}
	if mode == .Insensitive {
		return .Insensitive
	}
	for code_point in pattern {
		if unicode.is_upper(code_point) {
			return .Sensitive
		}
	}
	return .Insensitive
}

@(private)
common_utf8_prefix :: proc(first, second: string) -> u64 {
	limit := min(len(first), len(second))
	common := 0
	for common < limit && first[common] == second[common] {
		common += 1
	}
	for common > 0 && common < len(first) && first[common] & 0xc0 == 0x80 {
		common -= 1
	}
	return u64(common)
}
