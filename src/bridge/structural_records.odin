// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../language"

/* STRUCTURAL_CAPABILITY_SCHEMA_VERSION identifies the structural command ABI. */
STRUCTURAL_CAPABILITY_SCHEMA_VERSION :: u64(2)
/* MAX_STRUCTURAL_TARGET_TEXT_BYTES bounds one copied grammar node-kind name. */
MAX_STRUCTURAL_TARGET_TEXT_BYTES :: u64(language.MAX_STRUCTURAL_NODE_KIND_BYTES)
/* MAX_STRUCTURAL_PLAN_EDITS bounds one copied indentation plan. */
MAX_STRUCTURAL_PLAN_EDITS :: u64(language.MAX_STRUCTURAL_INDENT_LINES)
/* MAX_STRUCTURAL_DIAGNOSTIC_BYTES bounds one copied contained rejection. */
MAX_STRUCTURAL_DIAGNOSTIC_BYTES :: u64(language.MAX_DIAGNOSTIC_BYTES)
/* MAX_STRUCTURAL_INSPECTION_BYTES bounds one complete copied structural response. */
MAX_STRUCTURAL_INSPECTION_BYTES :: u64(language.MAX_STRUCTURAL_INSPECTION_BYTES)

/* STRUCTURAL_SCOPE_RECORD_BYTES is one exact editor and analysis generation scope. */
STRUCTURAL_SCOPE_RECORD_BYTES :: u64(160)
/* STRUCTURAL_REQUEST_RECORD_BYTES is one exact operation request. */
STRUCTURAL_REQUEST_RECORD_BYTES :: u64(200)
/* STRUCTURAL_TARGET_RECORD_BYTES precedes one copied node-kind name. */
STRUCTURAL_TARGET_RECORD_BYTES :: u64(208)
/* STRUCTURAL_PLAN_RECORD_BYTES precedes copied indentation edits. */
STRUCTURAL_PLAN_RECORD_BYTES :: u64(224)
/* STRUCTURAL_INDENT_EDIT_RECORD_BYTES is one copied leading-whitespace edit. */
STRUCTURAL_INDENT_EDIT_RECORD_BYTES :: u64(32)
/* STRUCTURAL_USAGE_RECORD_BYTES is one complete bounded-work summary. */
STRUCTURAL_USAGE_RECORD_BYTES :: u64(40)
/* STRUCTURAL_OUTCOME_RECORD_BYTES is one refreshed command outcome. */
STRUCTURAL_OUTCOME_RECORD_BYTES :: u64(264)
/* STRUCTURAL_DIAGNOSTIC_RECORD_BYTES precedes one copied diagnostic message. */
STRUCTURAL_DIAGNOSTIC_RECORD_BYTES :: u64(112)

/* Structural_Capability_Operation identifies one admitted synchronous request. */
Structural_Capability_Operation :: enum i32 {
	Scope = 1,
	Inspect = 2,
	Forward = 3,
	Backward = 4,
	Up = 5,
	Down = 6,
	Select = 7,
	Indent = 8,
	Definition = 9,
}

/* Structural_Capability_Access names checked authority without native ownership. */
Structural_Capability_Access :: enum u64 {
	Inspect = 1,
	Forward = 2,
	Backward = 3,
	Up = 4,
	Down = 5,
	Select = 6,
	Indent = 7,
	Definition = 8,
}

/* Structural_Scope_Record binds one capability to exact editor and analysis state. */
Structural_Scope_Record :: struct {
	schema_version:              u64,
	access:                      u64,
	editor_session_id:           u64,
	view_registry_id:            u64,
	view_id:                     u64,
	view_generation:             u64,
	view_state_generation:       u64,
	buffer_id:                   u64,
	source_revision:             u64,
	selection_generation:        u64,
	language_id:                 u64,
	language_generation:         u64,
	provider_registry_id:        u64,
	provider_language_id:        u64,
	provider_id:                 u64,
	provider_generation:         u64,
	parser_generation:           u64,
	tree_generation:             u64,
	command_registry_generation: u64,
	capability_generation:       u64,
}

/* Structural_Request_Record carries one generation-checked point or region request. */
Structural_Request_Record :: struct {
	expected_scope: Structural_Scope_Record,
	operation:      u64,
	point:          u64,
	start:          u64,
	end:            u64,
	has_region:     u64,
}

/* Structural_Target_Record describes one copied named node and trailing kind text. */
Structural_Target_Record :: struct {
	scope:       Structural_Scope_Record,
	present:     u64,
	start:       u64,
	end:         u64,
	kind_offset: u64,
	kind_bytes:  u64,
	depth:       u64,
}

/* Structural_Usage_Record publishes exact bounded work for one operation. */
Structural_Usage_Record :: struct {
	visited_nodes:   u64,
	visited_depth:   u64,
	indent_lines:    u64,
	prepared_bytes:  u64,
	temporary_bytes: u64,
}

/* Structural_Plan_Record describes one exact copied indentation edit array. */
Structural_Plan_Record :: struct {
	scope:      Structural_Scope_Record,
	start:      u64,
	end:        u64,
	edit_count: u64,
	usage:      Structural_Usage_Record,
}

/* Structural_Indent_Edit_Record copies one leading-horizontal-whitespace replacement. */
Structural_Indent_Edit_Record :: struct {
	start:        u64,
	end:          u64,
	indent_level: u64,
	indent_bytes: u64,
}

/* Structural_Outcome_Record contains refreshed state and no retained native ownership. */
Structural_Outcome_Record :: struct {
	scope:          Structural_Scope_Record,
	operation:      u64,
	completion:     u64,
	changed:        u64,
	point:          u64,
	mark:           u64,
	region_active:  u64,
	transaction_id: u64,
	undo_unit_id:   u64,
	usage:          Structural_Usage_Record,
}

/* Structural_Diagnostic_Record copies one stable failure and bounded message. */
Structural_Diagnostic_Record :: struct {
	operation:             u64,
	failure_code:          u64,
	structural_code:       u64,
	language_code:         u64,
	buffer_id:             u64,
	view_id:               u64,
	expected_revision:     u64,
	actual_revision:       u64,
	expected_generation:   u64,
	actual_generation:     u64,
	limit:                 u64,
	actual:                u64,
	message_offset:        u64,
	message_bytes:         u64,
}

/* structural_target_record_bytes validates one copied target and kind width. */
structural_target_record_bytes :: proc(kind_bytes: u64) -> (bytes: u64, ok: bool) {
	if kind_bytes > MAX_STRUCTURAL_TARGET_TEXT_BYTES {
		return 0, false
	}
	bytes = STRUCTURAL_TARGET_RECORD_BYTES + kind_bytes
	return bytes, bytes <= MAX_STRUCTURAL_INSPECTION_BYTES
}

/* structural_plan_record_bytes validates one copied indentation plan width. */
structural_plan_record_bytes :: proc(edit_count: u64) -> (bytes: u64, ok: bool) {
	if edit_count > MAX_STRUCTURAL_PLAN_EDITS {
		return 0, false
	}
	bytes = STRUCTURAL_PLAN_RECORD_BYTES + edit_count * STRUCTURAL_INDENT_EDIT_RECORD_BYTES
	return bytes, bytes <= MAX_STRUCTURAL_INSPECTION_BYTES
}

/* structural_diagnostic_record_bytes validates one copied diagnostic width. */
structural_diagnostic_record_bytes :: proc(message_bytes: u64) -> (bytes: u64, ok: bool) {
	if message_bytes > MAX_STRUCTURAL_DIAGNOSTIC_BYTES {
		return 0, false
	}
	bytes = STRUCTURAL_DIAGNOSTIC_RECORD_BYTES + message_bytes
	return bytes, bytes <= MAX_STRUCTURAL_INSPECTION_BYTES
}

/* structural_inspection_record_bytes validates one complete copied inspection width. */
structural_inspection_record_bytes :: proc(
	edit_count, kind_bytes, message_bytes: u64,
) -> (bytes: u64, ok: bool) {
	if edit_count > MAX_STRUCTURAL_PLAN_EDITS ||
	   kind_bytes > MAX_STRUCTURAL_TARGET_TEXT_BYTES ||
	   message_bytes > MAX_STRUCTURAL_DIAGNOSTIC_BYTES {
		return 0, false
	}
	bytes = STRUCTURAL_SCOPE_RECORD_BYTES + STRUCTURAL_TARGET_RECORD_BYTES +
	        STRUCTURAL_PLAN_RECORD_BYTES + edit_count * STRUCTURAL_INDENT_EDIT_RECORD_BYTES +
	        STRUCTURAL_OUTCOME_RECORD_BYTES + STRUCTURAL_USAGE_RECORD_BYTES +
	        STRUCTURAL_DIAGNOSTIC_RECORD_BYTES + kind_bytes + message_bytes
	return bytes, bytes <= MAX_STRUCTURAL_INSPECTION_BYTES
}

/* structural_record_layout_is_valid verifies every C and Racket ABI width. */
structural_record_layout_is_valid :: proc() -> bool {
	return u64(size_of(Structural_Scope_Record)) == STRUCTURAL_SCOPE_RECORD_BYTES &&
	       u64(size_of(Structural_Request_Record)) == STRUCTURAL_REQUEST_RECORD_BYTES &&
	       u64(size_of(Structural_Target_Record)) == STRUCTURAL_TARGET_RECORD_BYTES &&
	       u64(size_of(Structural_Plan_Record)) == STRUCTURAL_PLAN_RECORD_BYTES &&
	       u64(size_of(Structural_Indent_Edit_Record)) ==
	           STRUCTURAL_INDENT_EDIT_RECORD_BYTES &&
	       u64(size_of(Structural_Usage_Record)) == STRUCTURAL_USAGE_RECORD_BYTES &&
	       u64(size_of(Structural_Outcome_Record)) == STRUCTURAL_OUTCOME_RECORD_BYTES &&
	       u64(size_of(Structural_Diagnostic_Record)) == STRUCTURAL_DIAGNOSTIC_RECORD_BYTES
}
