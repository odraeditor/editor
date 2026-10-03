// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package search

import "../editor"
import "base:runtime"
import regex_common "core:text/regex/common"

/* MIN_PATTERN_BYTES is the smallest admitted nonempty search pattern. */
MIN_PATTERN_BYTES :: u64(1)
/* MAX_PATTERN_BYTES is the largest pattern admitted by an explicit policy. */
MAX_PATTERN_BYTES :: u64(64 * 1_024)
/* DEFAULT_PATTERN_BYTES is the measured factory bound for one search pattern. */
DEFAULT_PATTERN_BYTES :: u64(4 * 1_024)
/* MIN_SCAN_WINDOW_BYTES is the smallest admitted rope scan turn. */
MIN_SCAN_WINDOW_BYTES :: u64(64 * 1_024)
/* MAX_SCAN_WINDOW_BYTES is the largest admitted rope scan turn. */
MAX_SCAN_WINDOW_BYTES :: u64(16 * 1_024 * 1_024)
/* DEFAULT_SCAN_WINDOW_BYTES is the measured factory rope scan turn. */
DEFAULT_SCAN_WINDOW_BYTES :: u64(64 * 1_024)
/* MIN_CANCELLATION_BYTES is the smallest admitted cancellation interval. */
MIN_CANCELLATION_BYTES :: u64(64 * 1_024)
/* MAX_CANCELLATION_BYTES is the largest admitted cancellation interval. */
MAX_CANCELLATION_BYTES :: u64(4 * 1_024 * 1_024)
/* DEFAULT_CANCELLATION_BYTES is the measured factory cancellation interval. */
DEFAULT_CANCELLATION_BYTES :: u64(256 * 1_024)
/* MIN_RETAINED_OCCURRENCES is the smallest admitted nearby-result capacity. */
MIN_RETAINED_OCCURRENCES :: u32(64)
/* MAX_RETAINED_OCCURRENCES is the largest admitted nearby-result capacity. */
MAX_RETAINED_OCCURRENCES :: u32(65_536)
/* DEFAULT_RETAINED_OCCURRENCES is the measured factory nearby-result capacity. */
DEFAULT_RETAINED_OCCURRENCES :: u32(256)
/* MIN_TEMPORARY_BYTES is the smallest admitted per-search temporary budget. */
MIN_TEMPORARY_BYTES :: u64(4 * 1_024 * 1_024)
/* MAX_TEMPORARY_BYTES is the largest admitted per-search temporary budget. */
MAX_TEMPORARY_BYTES :: u64(1_024 * 1_024 * 1_024)
/* DEFAULT_TEMPORARY_BYTES is the measured factory per-search temporary budget. */
DEFAULT_TEMPORARY_BYTES :: u64(16 * 1_024 * 1_024)
/* MAX_CAPTURE_GROUPS records the standard-library regex capture ceiling. */
MAX_CAPTURE_GROUPS :: u16(regex_common.MAX_CAPTURE_GROUPS)
/* MIN_CAPTURE_GROUPS preserves the stable minimum expression capability. */
MIN_CAPTURE_GROUPS :: u16(10)
/* MIN_MATCH_SPAN_BYTES is the smallest configurable regex window overlap. */
MIN_MATCH_SPAN_BYTES :: u64(4 * 1_024)
/* MAX_MATCH_SPAN_BYTES is the largest admitted regex window overlap. */
MAX_MATCH_SPAN_BYTES :: u64(16 * 1_024 * 1_024)
/* DEFAULT_MATCH_SPAN_BYTES bounds one factory regex match across rope windows. */
DEFAULT_MATCH_SPAN_BYTES :: u64(64 * 1_024)
/* MIN_REPLACEMENT_TEMPLATE_BYTES permits an empty template for deletion. */
MIN_REPLACEMENT_TEMPLATE_BYTES :: u64(0)
/* MAX_REPLACEMENT_TEMPLATE_BYTES is the largest admitted replacement input. */
MAX_REPLACEMENT_TEMPLATE_BYTES :: u64(64 * 1_024)
/* DEFAULT_REPLACEMENT_TEMPLATE_BYTES is the factory replacement-input bound. */
DEFAULT_REPLACEMENT_TEMPLATE_BYTES :: u64(4 * 1_024)
/* MIN_EXPANDED_REPLACEMENT_BYTES is the smallest configurable expansion ceiling. */
MIN_EXPANDED_REPLACEMENT_BYTES :: u64(4 * 1_024)
/* MAX_EXPANDED_REPLACEMENT_BYTES matches the editor's per-splice ceiling. */
MAX_EXPANDED_REPLACEMENT_BYTES :: u64(editor.MAX_REPLACEMENT_BYTES)
/* DEFAULT_EXPANDED_REPLACEMENT_BYTES bounds one factory expansion. */
DEFAULT_EXPANDED_REPLACEMENT_BYTES :: u64(16 * 1_024 * 1_024)
/* MIN_REPLACEMENT_TEMPORARY_BYTES is the smallest expansion scratch budget. */
MIN_REPLACEMENT_TEMPORARY_BYTES :: u64(4 * 1_024)
/* MAX_REPLACEMENT_TEMPORARY_BYTES matches the editor operation scratch ceiling. */
MAX_REPLACEMENT_TEMPORARY_BYTES :: u64(editor.MAX_TEMPORARY_BYTES)
/* DEFAULT_REPLACEMENT_TEMPORARY_BYTES bounds factory expansion scratch storage. */
DEFAULT_REPLACEMENT_TEMPORARY_BYTES :: u64(16 * 1_024 * 1_024)

/* Query_ID identifies one admitted immutable pattern; zero is invalid. */
Query_ID :: distinct u64
/* Search_Generation distinguishes resumable work and cancellation lifetimes. */
Search_Generation :: distinct u64
/* Policy_Generation identifies one complete configurable search policy. */
Policy_Generation :: distinct u64

/* Pattern_Kind selects literal or standard-library regular-expression matching. */
Pattern_Kind :: enum u8 {
	Invalid,
	Literal,
	Regular_Expression,
}

/* Direction selects the nearest occurrence before or after an origin. */
Direction :: enum u8 {
	Invalid,
	Forward,
	Backward,
}

/* Case_Mode selects smart, forced-sensitive, or forced-insensitive matching. */
Case_Mode :: enum u8 {
	Invalid,
	Smart,
	Sensitive,
	Insensitive,
}

/* Effective_Case reports the concrete case behavior selected for one query. */
Effective_Case :: enum u8 {
	Invalid,
	Sensitive,
	Insensitive,
}

/* Boundary_Mode selects unrestricted, word-boundary, or symbol-boundary matching. */
Boundary_Mode :: enum u8 {
	Invalid,
	Unrestricted,
	Word,
	Symbol,
}

/* Whitespace_Mode selects exact or normalized nonempty whitespace matching. */
Whitespace_Mode :: enum u8 {
	Invalid,
	Exact,
	Flexible,
}

/* Reuse_Kind classifies safe structural reuse between two admitted literal queries. */
Reuse_Kind :: enum u8 {
	None,
	Identical,
	Extended,
	Shortened,
	Related,
}

/* Outcome classifies one complete or resumable search turn. */
Outcome :: enum u8 {
	Invalid,
	Matched,
	No_Match,
	Incomplete,
	Cancelled,
}

/* Failure_Code classifies expected admission, lifecycle, revision, and resource failures. */
Failure_Code :: enum u8 {
	None,
	Closed_Query,
	Closed_Result,
	Invalid_Query_ID,
	Invalid_Generation,
	Invalid_Pattern_Kind,
	Invalid_Direction,
	Invalid_Case_Mode,
	Invalid_Boundary_Mode,
	Invalid_Whitespace_Mode,
	Empty_Pattern,
	Malformed_UTF8,
	Pattern_Limit,
	Invalid_Limits,
	Wrong_Buffer,
	Stale_Revision,
	Invalid_Scope,
	Out_Of_Range,
	Work_Limit,
	Persistent_Memory_Limit,
	Temporary_Memory_Limit,
	Capture_Limit,
	Match_Span_Limit,
	Regex_Parser_Error,
	Regex_Compiler_Error,
	Closed_Replacement_Template,
	Closed_Replacement_Expansion,
	Closed_Snapshot,
	Invalid_Case_Preservation,
	Replacement_Template_Limit,
	Malformed_Replacement_Template,
	Capture_Reference,
	Expansion_Limit,
	Arithmetic_Overflow,
}

/* Regex_Diagnostic_Kind classifies checked standard-library compile failures. */
Regex_Diagnostic_Kind :: enum u8 {
	None,
	Expected_Token,
	Invalid_Repetition,
	Invalid_Token,
	Invalid_Unicode,
	Too_Many_Capture_Groups,
	Unexpected_End,
	Program_Too_Big,
	Too_Many_Classes,
}

/* Regex_Diagnostic reports a parser byte position or a compiler bound failure. */
Regex_Diagnostic :: struct {
	kind:        Regex_Diagnostic_Kind,
	byte_offset: u64,
}

/* Failure reports the relevant identity, bound, and observed value for one failure. */
Failure :: struct {
	code:       Failure_Code,
	buffer_id:  editor.Buffer_ID,
	revision:   editor.Revision,
	query_id:   Query_ID,
	limit:      u64,
	actual:     u64,
	diagnostic: Regex_Diagnostic,
}

/* Limits bounds one query, scan turn, regex span, retained result, and temporary arena. */
Limits :: struct {
	pattern_bytes:       u64,
	scan_window_bytes:   u64,
	cancellation_bytes:  u64,
	retained_occurrences: u32,
	temporary_bytes:     u64,
	capture_groups:      u16,
	match_span_bytes:    u64,
}

/* DEFAULT_LIMITS is the measured factory bound set for literal search. */
DEFAULT_LIMITS :: Limits {
	pattern_bytes = DEFAULT_PATTERN_BYTES,
	scan_window_bytes = DEFAULT_SCAN_WINDOW_BYTES,
	cancellation_bytes = DEFAULT_CANCELLATION_BYTES,
	retained_occurrences = DEFAULT_RETAINED_OCCURRENCES,
	temporary_bytes = DEFAULT_TEMPORARY_BYTES,
	capture_groups = MAX_CAPTURE_GROUPS,
	match_span_bytes = DEFAULT_MATCH_SPAN_BYTES,
}

/* Regex_Shorthand_Mode states how character-class shorthands are interpreted. */
Regex_Shorthand_Mode :: enum u8 {
	Invalid,
	ASCII,
}

/* Regex_Profile exposes the fixed adapter flags and admitted resource bounds. */
Regex_Profile :: struct {
	present:                  bool,
	unicode:                  bool,
	multiline:                bool,
	case_insensitive:         bool,
	shorthands:               Regex_Shorthand_Mode,
	capture_groups:           u16,
	defined_capture_groups:   u16,
	maximum_match_span_bytes: u64,
	scan_window_bytes:        u64,
}

/* Policy selects configurable search behavior independently from resource limits. */
Policy :: struct {
	case_mode:       Case_Mode,
	boundary_mode:   Boundary_Mode,
	whitespace_mode: Whitespace_Mode,
	wrap:            bool,
}

/* DEFAULT_POLICY applies smart case and permits explicit wrapped navigation. */
DEFAULT_POLICY :: Policy {
	case_mode = .Smart,
	boundary_mode = .Unrestricted,
	whitespace_mode = .Exact,
	wrap = true,
}

/* Case_Preservation selects whether insensitive matches shape replacement case. */
Case_Preservation :: enum u8 {
	Invalid,
	None,
	Smart,
}

/* Replacement_Policy controls case adaptation independently from search policy. */
Replacement_Policy :: struct {
	case_preservation: Case_Preservation,
}

/* DEFAULT_REPLACEMENT_POLICY preserves recognizable insensitive-match case shapes. */
DEFAULT_REPLACEMENT_POLICY :: Replacement_Policy {case_preservation = .Smart}

/* Replacement_Limits bounds copied template, expanded output, and scratch bytes. */
Replacement_Limits :: struct {
	template_bytes:  u64,
	expanded_bytes:  u64,
	temporary_bytes: u64,
}

/* DEFAULT_REPLACEMENT_LIMITS supplies the factory replacement resource bounds. */
DEFAULT_REPLACEMENT_LIMITS :: Replacement_Limits {
	template_bytes = DEFAULT_REPLACEMENT_TEMPLATE_BYTES,
	expanded_bytes = DEFAULT_EXPANDED_REPLACEMENT_BYTES,
	temporary_bytes = DEFAULT_REPLACEMENT_TEMPORARY_BYTES,
}

/* Replacement_Usage accounts for source reads, output bytes, and peak scratch storage. */
Replacement_Usage :: struct {
	source_bytes:         u64,
	expanded_bytes:       u64,
	temporary_peak_bytes: u64,
}

/* Scope identifies one half-open byte range in one immutable buffer revision. */
Scope :: struct {
	buffer_id: editor.Buffer_ID,
	revision:  editor.Revision,
	start:     editor.Byte_Offset,
	end:       editor.Byte_Offset,
}

/* Capture identifies one participating regex group in the occurrence revision. */
Capture :: struct {
	group: u16,
	start: editor.Byte_Offset,
	end:   editor.Byte_Offset,
}

/* Occurrence identifies one match and its flattened capture range. */
Occurrence :: struct {
	buffer_id:    editor.Buffer_ID,
	revision:     editor.Revision,
	start:        editor.Byte_Offset,
	end:          editor.Byte_Offset,
	first_capture: u32,
	capture_count: u16,
}

/* Usage accounts for logical work, physical reads, retained values, and temporary memory. */
Usage :: struct {
	logical_bytes:       u64,
	read_bytes:          u64,
	scan_turns:          u64,
	cancellation_checks: u64,
	retained_occurrences: u32,
	retained_captures:   u32,
	temporary_peak_bytes: u64,
}

/* Progress identifies the next resumable offset and completed traversal state. */
Progress :: struct {
	next_offset: editor.Byte_Offset,
	wrapped:     bool,
	complete:    bool,
}

/* Request describes one bounded search turn and borrows no pattern text. */
Request :: struct {
	scope:                   Scope,
	origin:                  editor.Byte_Offset,
	direction:               Direction,
	generation:              Search_Generation,
	wrap_already_attempted:  bool,
}

/* Query_Config supplies copied pattern data and persistent and compile allocation domains. */
Query_Config :: struct {
	id:        Query_ID,
	kind:      Pattern_Kind,
	pattern:   string,
	policy:    Policy,
	limits:    Limits,
	allocator: runtime.Allocator,
	temporary_allocator: runtime.Allocator,
}

/* Allocator_Set supplies copied-result and per-turn temporary allocation domains. */
Allocator_Set :: struct {
	// The caller keeps this allocator alive until result_close returns.
	persistent: runtime.Allocator,
	// The caller keeps this allocator alive only for the search call.
	temporary:  runtime.Allocator,
}

/* Query_View borrows immutable query data until query_close. */
Query_View :: struct {
	id:             Query_ID,
	kind:           Pattern_Kind,
	pattern:        string,
	pattern_runes:  u64,
	policy:         Policy,
	effective_case: Effective_Case,
	limits:         Limits,
	regex:          Regex_Profile,
}

/* Replacement_Template_Config supplies copied text, policy, limits, and ownership. */
Replacement_Template_Config :: struct {
	text:      string,
	policy:    Replacement_Policy,
	limits:    Replacement_Limits,
	allocator: runtime.Allocator,
}

/* Replacement_Template_View borrows one admitted template until it is closed. */
Replacement_Template_View :: struct {
	query_id:               Query_ID,
	pattern_kind:           Pattern_Kind,
	text:                   string,
	policy:                 Replacement_Policy,
	limits:                 Replacement_Limits,
	defined_capture_groups: u16,
	has_uppercase_literal:  bool,
}

/* Replacement_Template owns copied validated replacement input. */
Replacement_Template :: struct {
	state: rawptr,
}

/* Replacement_Expansion_View borrows expanded UTF-8 text until it is closed. */
Replacement_Expansion_View :: struct {
	text:    string,
	adapted: bool,
	usage:   Replacement_Usage,
}

/* Replacement_Expansion owns one occurrence-specific expanded value. */
Replacement_Expansion :: struct {
	state: rawptr,
}

/* Query_Reuse reports the shared UTF-8 prefix and safe reuse relation. */
Query_Reuse :: struct {
	kind:                Reuse_Kind,
	common_prefix_bytes: u64,
}

/* Query is an opaque owner of one copied, admitted search pattern. */
Query :: struct {
	state: rawptr,
}

/* Result_View borrows occurrence and capture arrays until result_close. */
Result_View :: struct {
	outcome:       Outcome,
	scope:         Scope,
	has_current:   bool,
	current_index: u32,
	occurrences:   []Occurrence,
	captures:      []Capture,
	progress:      Progress,
	usage:         Usage,
}

/* Result is an opaque owner of copied occurrence and capture records. */
Result :: struct {
	state: rawptr,
}

/* Cancellation carries generation-scoped cooperative cancellation state. */
Cancellation :: struct {
	generation: Search_Generation,
	requested:  bool,
}
