// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../search"

/* MAX_SEARCH_COMMAND_NAME_BYTES bounds one copied semantic command name. */
MAX_SEARCH_COMMAND_NAME_BYTES :: u64(96)
/* MAX_SEARCH_REQUEST_PATTERN_BYTES mirrors the admitted native pattern ceiling. */
MAX_SEARCH_REQUEST_PATTERN_BYTES :: u64(search.MAX_PATTERN_BYTES)
/* MAX_SEARCH_REQUEST_REPLACEMENT_BYTES mirrors the admitted template ceiling. */
MAX_SEARCH_REQUEST_REPLACEMENT_BYTES :: u64(search.MAX_REPLACEMENT_TEMPLATE_BYTES)
/* MAX_SEARCH_INSPECTION_OCCURRENCES bounds one copied programmable response. */
MAX_SEARCH_INSPECTION_OCCURRENCES :: u64(search.DEFAULT_RETAINED_OCCURRENCES)
/* MAX_SEARCH_INSPECTION_CAPTURES bounds flattened captures in one copied response. */
MAX_SEARCH_INSPECTION_CAPTURES :: u64(
	search.DEFAULT_RETAINED_OCCURRENCES * u32(search.MAX_CAPTURE_GROUPS + 1),
)
/* MAX_SEARCH_INSPECTION_TEXT_BYTES bounds copied session strings. */
MAX_SEARCH_INSPECTION_TEXT_BYTES :: u64(
	2 * search.MAX_PATTERN_BYTES + search.MAX_REPLACEMENT_TEMPLATE_BYTES,
)

/* SEARCH_SCOPE_RECORD_BYTES is the stable scalar identity width. */
SEARCH_SCOPE_RECORD_BYTES :: u64(96)
/* SEARCH_POLICY_RECORD_BYTES is the stable complete policy width. */
SEARCH_POLICY_RECORD_BYTES :: u64(248)
/* SEARCH_OCCURRENCE_RECORD_BYTES is one copied occurrence width. */
SEARCH_OCCURRENCE_RECORD_BYTES :: u64(48)
/* SEARCH_CAPTURE_RECORD_BYTES is one copied capture width. */
SEARCH_CAPTURE_RECORD_BYTES :: u64(24)
/* SEARCH_SESSION_HEADER_BYTES precedes copied arrays and text. */
SEARCH_SESSION_HEADER_BYTES :: u64(568)
/* SEARCH_COMMAND_REQUEST_HEADER_BYTES precedes copied command text. */
SEARCH_COMMAND_REQUEST_HEADER_BYTES :: u64(264)
/* SEARCH_COMMAND_RESULT_RECORD_BYTES is one copied invocation result width. */
SEARCH_COMMAND_RESULT_RECORD_BYTES :: u64(256)

/* Search_Operation identifies one admitted synchronous search callback request. */
Search_Operation :: enum i32 {
	Scope = 1,
	Policy = 2,
	Session = 3,
	Invoke = 4,
}

/* Search_Scope_Record is the pointer-free authority and state identity snapshot. */
Search_Scope_Record :: struct {
	editor_session_id:           u64,
	access:                      u64,
	view_registry_id:            u64,
	view_id:                     u64,
	view_generation:             u64,
	view_state_generation:       u64,
	buffer_id:                   u64,
	revision:                    u64,
	command_registry_generation: u64,
	session_kind:                u64,
	interaction_generation:      u64,
	policy_generation:           u64,
}

/* Search_Policy_Record is one copied complete configurable policy. */
Search_Policy_Record :: struct {
	scope:                       Search_Scope_Record,
	case_mode:                   u64,
	boundary_mode:               u64,
	whitespace_mode:             u64,
	wrap:                        u64,
	pattern_bytes:               u64,
	scan_window_bytes:           u64,
	cancellation_bytes:          u64,
	retained_occurrences:        u64,
	search_temporary_bytes:      u64,
	capture_groups:              u64,
	match_span_bytes:            u64,
	case_preservation:           u64,
	template_bytes:              u64,
	expanded_bytes:              u64,
	replacement_temporary_bytes: u64,
	replace_all_matches:         u64,
	replace_all_text_bytes:      u64,
	replace_all_temporary_bytes: u64,
	replace_all_analysis_bytes:  u64,
}

/* Search_Occurrence_Record is one copied revisioned occurrence. */
Search_Occurrence_Record :: struct {
	buffer_id:     u64,
	revision:      u64,
	start:         u64,
	end:           u64,
	first_capture: u64,
	capture_count: u64,
}

/* Search_Capture_Record is one copied participating capture. */
Search_Capture_Record :: struct {
	group: u64,
	start: u64,
	end:   u64,
}

/* Search_Session_Header_Record describes all variable copied session payloads. */
Search_Session_Header_Record :: struct {
	scope:                       Search_Scope_Record,
	present:                     u64,
	session_kind:                u64,
	direction:                   u64,
	pattern_kind:                u64,
	search_scope_buffer_id:      u64,
	search_scope_revision:       u64,
	search_scope_start:          u64,
	search_scope_end:            u64,
	search_status:               u64,
	query_status:                u64,
	last_response:               u64,
	semantic_group:              u64,
	pattern_bytes:               u64,
	successful_pattern_bytes:    u64,
	replacement_bytes:           u64,
	case_mode:                   u64,
	boundary_mode:               u64,
	whitespace_mode:             u64,
	wrap:                        u64,
	limit_pattern_bytes:         u64,
	limit_scan_window_bytes:     u64,
	limit_cancellation_bytes:    u64,
	limit_retained_occurrences:  u64,
	limit_temporary_bytes:       u64,
	limit_capture_groups:        u64,
	limit_match_span_bytes:      u64,
	case_preservation:           u64,
	limit_template_bytes:        u64,
	limit_expanded_bytes:        u64,
	limit_replacement_temporary: u64,
	effective_case:              u64,
	source_revision:             u64,
	observed_revision:           u64,
	source_text_bytes:           u64,
	observed_text_bytes:         u64,
	replacements:                u64,
	skips:                       u64,
	recomputations:              u64,
	has_current:                 u64,
	current_index:               u64,
	current:                     Search_Occurrence_Record,
	progress_next_offset:        u64,
	progress_wrapped:            u64,
	progress_complete:           u64,
	usage_logical_bytes:         u64,
	usage_read_bytes:            u64,
	usage_scan_turns:            u64,
	usage_cancellation_checks:   u64,
	usage_retained_occurrences:  u64,
	usage_retained_captures:     u64,
	usage_temporary_peak_bytes:  u64,
	occurrence_count:            u64,
	capture_count:               u64,
	text_bytes:                  u64,
}

/* Search_Command_Request_Header_Record describes copied invocation payload lengths. */
Search_Command_Request_Header_Record :: struct {
	direction:              u64,
	incremental_turn:       u64,
	query_action:           u64,
	query_id:               u64,
	search_generation:      u64,
	semantic_group:         u64,
	scope_buffer_id:        u64,
	scope_revision:         u64,
	scope_start:            u64,
	scope_end:              u64,
	cancellation_requested: u64,
	command_name_bytes:     u64,
	pattern_bytes:          u64,
	replacement_bytes:      u64,
	case_mode:              u64,
	boundary_mode:          u64,
	whitespace_mode:        u64,
	wrap:                   u64,
	pattern_limit:          u64,
	scan_window_limit:      u64,
	cancellation_limit:     u64,
	occurrence_limit:       u64,
	search_temporary_limit: u64,
	capture_limit:          u64,
	match_span_limit:       u64,
	case_preservation:      u64,
	template_limit:         u64,
	expanded_limit:         u64,
	replacement_temporary_limit: u64,
	replace_all_matches:    u64,
	replace_all_text:       u64,
	replace_all_temporary:  u64,
	replace_all_analysis:   u64,
}

/* Search_Command_Result_Record contains no retained native ownership. */
Search_Command_Result_Record :: struct {
	scope:                        Search_Scope_Record,
	completion:                   u64,
	changed:                      u64,
	query_status:                 u64,
	replacements:                 u64,
	skips:                        u64,
	finished:                     u64,
	replacement_source_bytes:     u64,
	replacement_expanded_bytes:   u64,
	replacement_temporary_bytes:  u64,
	replace_all_matches:          u64,
	replace_all_captures:         u64,
	replace_all_analysis_bytes:   u64,
	replace_all_source_bytes:     u64,
	replace_all_removed_bytes:    u64,
	replace_all_expanded_bytes:   u64,
	replace_all_transaction_bytes: u64,
	replace_all_search_turns:     u64,
	replace_all_cancellation_checks: u64,
	continuation_code:            u64,
	continuation_search_code:     u64,
}

/* search_session_record_bytes validates quotas and exact copied response width. */
search_session_record_bytes :: proc(
	occurrences, captures, text_bytes: u64,
) -> (bytes: u64, ok: bool) {
	if occurrences > MAX_SEARCH_INSPECTION_OCCURRENCES ||
	   captures > MAX_SEARCH_INSPECTION_CAPTURES || text_bytes > MAX_SEARCH_INSPECTION_TEXT_BYTES {
		return 0, false
	}
	return SEARCH_SESSION_HEADER_BYTES + occurrences * SEARCH_OCCURRENCE_RECORD_BYTES +
	       captures * SEARCH_CAPTURE_RECORD_BYTES + text_bytes, true
}

/* search_command_request_bytes validates copied command payload lengths. */
search_command_request_bytes :: proc(
	command_name_bytes, pattern_bytes, replacement_bytes: u64,
) -> (bytes: u64, ok: bool) {
	if command_name_bytes == 0 || command_name_bytes > MAX_SEARCH_COMMAND_NAME_BYTES ||
	   pattern_bytes > MAX_SEARCH_REQUEST_PATTERN_BYTES ||
	   replacement_bytes > MAX_SEARCH_REQUEST_REPLACEMENT_BYTES {
		return 0, false
	}
	return SEARCH_COMMAND_REQUEST_HEADER_BYTES + command_name_bytes + pattern_bytes +
	       replacement_bytes, true
}

/* search_record_layout_is_valid verifies every C and Racket ABI width. */
search_record_layout_is_valid :: proc() -> bool {
	return u64(size_of(Search_Scope_Record)) == SEARCH_SCOPE_RECORD_BYTES &&
	       u64(size_of(Search_Policy_Record)) == SEARCH_POLICY_RECORD_BYTES &&
	       u64(size_of(Search_Occurrence_Record)) == SEARCH_OCCURRENCE_RECORD_BYTES &&
	       u64(size_of(Search_Capture_Record)) == SEARCH_CAPTURE_RECORD_BYTES &&
	       u64(size_of(Search_Session_Header_Record)) == SEARCH_SESSION_HEADER_BYTES &&
	       u64(size_of(Search_Command_Request_Header_Record)) ==
	           SEARCH_COMMAND_REQUEST_HEADER_BYTES &&
	       u64(size_of(Search_Command_Result_Record)) == SEARCH_COMMAND_RESULT_RECORD_BYTES
}
