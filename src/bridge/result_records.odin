// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../result_set"

/* RESULT_CAPABILITY_SCHEMA_VERSION identifies the copied result-provider ABI. */
RESULT_CAPABILITY_SCHEMA_VERSION :: u64(1)
/* RESULT_SCOPE_RECORD_BYTES is one exact registry and result-generation scope. */
RESULT_SCOPE_RECORD_BYTES :: u64(48)
/* RESULT_PUBLICATION_HEADER_BYTES precedes copied locations, groups, and text. */
RESULT_PUBLICATION_HEADER_BYTES :: u64(264)
/* RESULT_VIEW_HEADER_BYTES precedes one copied immutable result view. */
RESULT_VIEW_HEADER_BYTES :: u64(336)
/* RESULT_LOCATION_RECORD_BYTES is one copied revision-aware location. */
RESULT_LOCATION_RECORD_BYTES :: u64(88)
/* RESULT_GROUP_RECORD_BYTES is one copied group identity and label range. */
RESULT_GROUP_RECORD_BYTES :: u64(24)
/* RESULT_MOVEMENT_REQUEST_BYTES carries one scope and semantic movement. */
RESULT_MOVEMENT_REQUEST_BYTES :: u64(56)
/* RESULT_OUTCOME_RECORD_BYTES is one copied publication or movement outcome. */
RESULT_OUTCOME_RECORD_BYTES :: u64(96)
/* MAX_RESULT_PROPOSAL_BYTES bounds one complete programmable publication. */
MAX_RESULT_PROPOSAL_BYTES :: u64(
	RESULT_PUBLICATION_HEADER_BYTES +
	u64(result_set.MAX_RESULT_LOCATIONS) * RESULT_LOCATION_RECORD_BYTES +
	u64(result_set.MAX_RESULT_GROUPS) * RESULT_GROUP_RECORD_BYTES +
	result_set.MAX_RESULT_TEXT_BYTES,
)
/* MAX_RESULT_INSPECTION_BYTES bounds one complete copied immutable view. */
MAX_RESULT_INSPECTION_BYTES :: u64(
	RESULT_VIEW_HEADER_BYTES +
	u64(result_set.MAX_RESULT_LOCATIONS) * RESULT_LOCATION_RECORD_BYTES +
	u64(result_set.MAX_RESULT_GROUPS) * RESULT_GROUP_RECORD_BYTES +
	result_set.MAX_RESULT_TEXT_BYTES,
)

/* Result_Capability_Operation identifies one admitted synchronous request. */
Result_Capability_Operation :: enum i32 {
	Scope = 1,
	Inspect = 2,
	Publish = 3,
	Move = 4,
}

/* Result_Capability_Access is the stable copied authority mask. */
Result_Capability_Access :: enum u64 {
	Inspect = 1,
	Publish = 2,
	Move = 4,
}

/* Result_Scope_Record binds a turn to one registry, set, and generation. */
Result_Scope_Record :: struct {
	schema_version:        u64,
	access:                u64,
	editor_session_id:     u64,
	set_id:                u64,
	set_generation:        u64,
	capability_generation: u64,
}

/* Result_Location_Record copies one location and its trailing text ranges. */
Result_Location_Record :: struct {
	id:                u64,
	group_id:          u64,
	buffer_id:         u64,
	revision:          u64,
	start:             u64,
	end:               u64,
	source_identity:   u64,
	preview_offset:    u64,
	preview_bytes:     u64,
	annotation_offset: u64,
	annotation_bytes:  u64,
}

/* Result_Group_Record copies one group and its trailing label range. */
Result_Group_Record :: struct {
	id:           u64,
	label_offset: u64,
	label_bytes:  u64,
}

/* Result_Publication_Header_Record describes one complete copied proposal. */
Result_Publication_Header_Record :: struct {
	expected_scope:          Result_Scope_Record,
	source_id:               u64,
	source_generation:       u64,
	source_kind:             u64,
	completeness:            u64,
	continuation_present:    u64,
	continuation_provider:   u64,
	continuation_cursor:     u64,
	continuation_limit:      u64,
	refresh_provider:        u64,
	refresh_query_identity:  u64,
	refresh_policy_generation: u64,
	refresh_scope_generation:  u64,
	edit_capability:         u64,
	selected_id:             u64,
	has_selection:           u64,
	location_count:          u64,
	group_count:             u64,
	descriptor_bytes:        u64,
	text_bytes:              u64,
	metadata_values:         [8]u64,
}

/* Result_Movement_Request_Record carries one checked semantic movement. */
Result_Movement_Request_Record :: struct {
	expected_scope: Result_Scope_Record,
	movement:       u64,
}

/* Result_Outcome_Record contains refreshed scope and no native ownership. */
Result_Outcome_Record :: struct {
	scope:          Result_Scope_Record,
	transition:     u64,
	set_id:         u64,
	generation:     u64,
	location_id:    u64,
	selected_index: u64,
	has_selection:  u64,
}

/* result_publication_record_bytes validates a complete proposal width. */
result_publication_record_bytes :: proc(locations, groups, text_bytes: u64) -> (u64, bool) {
	if locations > u64(result_set.MAX_RESULT_LOCATIONS) ||
	   groups > u64(result_set.MAX_RESULT_GROUPS) ||
	   text_bytes > result_set.MAX_RESULT_TEXT_BYTES {
		return 0, false
	}
	bytes := RESULT_PUBLICATION_HEADER_BYTES + locations * RESULT_LOCATION_RECORD_BYTES +
	         groups * RESULT_GROUP_RECORD_BYTES + text_bytes
	return bytes, bytes <= MAX_RESULT_PROPOSAL_BYTES
}

/* result_view_record_bytes validates a complete copied view width. */
result_view_record_bytes :: proc(locations, groups, text_bytes: u64) -> (u64, bool) {
	if locations > u64(result_set.MAX_RESULT_LOCATIONS) ||
	   groups > u64(result_set.MAX_RESULT_GROUPS) ||
	   text_bytes > result_set.MAX_RESULT_TEXT_BYTES {
		return 0, false
	}
	bytes := RESULT_VIEW_HEADER_BYTES + locations * RESULT_LOCATION_RECORD_BYTES +
	         groups * RESULT_GROUP_RECORD_BYTES + text_bytes
	return bytes, bytes <= MAX_RESULT_INSPECTION_BYTES
}

/* result_record_layout_is_valid verifies every fixed ABI width. */
result_record_layout_is_valid :: proc() -> bool {
	return u64(size_of(Result_Scope_Record)) == RESULT_SCOPE_RECORD_BYTES &&
	       u64(size_of(Result_Publication_Header_Record)) == RESULT_PUBLICATION_HEADER_BYTES &&
	       u64(size_of(Result_Location_Record)) == RESULT_LOCATION_RECORD_BYTES &&
	       u64(size_of(Result_Group_Record)) == RESULT_GROUP_RECORD_BYTES &&
	       u64(size_of(Result_Movement_Request_Record)) == RESULT_MOVEMENT_REQUEST_BYTES &&
	       u64(size_of(Result_Outcome_Record)) == RESULT_OUTCOME_RECORD_BYTES
}
