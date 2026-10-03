// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../document"
import "../editor_session"

/* MAX_BUFFER_SESSION_DESCRIPTORS bounds one copied programmable inventory. */
MAX_BUFFER_SESSION_DESCRIPTORS :: u64(editor_session.DEFAULT_DESCRIPTOR_BATCH)
/* MAX_BUFFER_SESSION_LABEL_BYTES bounds aggregate copied labels in one response. */
MAX_BUFFER_SESSION_LABEL_BYTES :: u64(editor_session.DEFAULT_RETAINED_LABEL_BYTES)
/* MAX_BUFFER_SESSION_REQUEST_TEXT_BYTES bounds one copied name or local path. */
MAX_BUFFER_SESSION_REQUEST_TEXT_BYTES :: u64(max(
	editor_session.MAX_NAME_BYTES,
	document.MAX_PATH_BYTES,
))
/* MAX_BUFFER_SESSION_DECISIONS bounds one generation-bound marked request. */
MAX_BUFFER_SESSION_DECISIONS :: u64(editor_session.DEFAULT_INVENTORY_MARKS)
/* MAX_BUFFER_SESSION_MARKS bounds one copied semantic mark set. */
MAX_BUFFER_SESSION_MARKS :: u64(editor_session.DEFAULT_INVENTORY_MARKS)

/* BUFFER_SESSION_SCOPE_RECORD_BYTES is the stable pointer-free scope width. */
BUFFER_SESSION_SCOPE_RECORD_BYTES :: u64(144)
/* BUFFER_SESSION_USAGE_RECORD_BYTES is one scope plus exact aggregate accounting. */
BUFFER_SESSION_USAGE_RECORD_BYTES :: u64(248)
/* BUFFER_SESSION_DESCRIPTOR_HEADER_BYTES precedes descriptor and label arrays. */
BUFFER_SESSION_DESCRIPTOR_HEADER_BYTES :: u64(160)
/* BUFFER_SESSION_DESCRIPTOR_RECORD_BYTES is one pointer-free descriptor width. */
BUFFER_SESSION_DESCRIPTOR_RECORD_BYTES :: u64(168)
/* BUFFER_SESSION_REQUEST_HEADER_BYTES precedes copied text and decisions. */
BUFFER_SESSION_REQUEST_HEADER_BYTES :: u64(272)
/* BUFFER_SESSION_DECISION_RECORD_BYTES is one copied marked decision width. */
BUFFER_SESSION_DECISION_RECORD_BYTES :: u64(72)
/* BUFFER_SESSION_MARK_RECORD_BYTES is one copied semantic mark width. */
BUFFER_SESSION_MARK_RECORD_BYTES :: u64(56)
/* BUFFER_SESSION_OUTCOME_RECORD_BYTES is one complete copied operation outcome. */
BUFFER_SESSION_OUTCOME_RECORD_BYTES :: u64(328)

/* Buffer_Session_Operation identifies one admitted synchronous callback request. */
Buffer_Session_Operation :: enum i32 {
	Scope = 1,
	Usage = 2,
	Descriptors = 3,
	Descriptor = 4,
	Create = 5,
	Open = 6,
	Activate = 7,
	Save = 8,
	Kill = 9,
	Execute_Marks = 10,
}

/* Buffer_Session_Scope_Record is the complete copied authority snapshot. */
Buffer_Session_Scope_Record :: struct {
	editor_session_id:         u64,
	access:                    u64,
	session_id:                u64,
	session_generation:        u64,
	registry_generation:       u64,
	visible_kind:              u64,
	visible_entry_session_id:  u64,
	visible_entry_session_generation: u64,
	visible_entry_registry_generation: u64,
	visible_entry_id:          u64,
	visible_entry_slot:        u64,
	visible_entry_generation:  u64,
	visible_view_registry_id:  u64,
	visible_view_id:           u64,
	visible_view_generation:   u64,
	visible_ui_owner_id:       u64,
	visible_ui_model_id:       u64,
	visible_ui_generation:     u64,
}

/* Buffer_Session_Usage_Record is exact copied aggregate accounting. */
Buffer_Session_Usage_Record :: struct {
	scope:                    Buffer_Session_Scope_Record,
	live_buffers:             u64,
	live_documents:           u64,
	live_primary_views:       u64,
	activation_entries:       u64,
	canonical_text_bytes:     u64,
	retained_label_bytes:     u64,
	view_anchors:             u64,
	view_context_bytes:       u64,
	history_bytes:            u64,
	registry_bytes:           u64,
	outstanding_capabilities: u64,
	prepared_operations:      u64,
	detached_cleanup_entries: u64,
}

/* Buffer_Session_Descriptor_Header_Record describes copied variable arrays. */
Buffer_Session_Descriptor_Header_Record :: struct {
	scope:            Buffer_Session_Scope_Record,
	descriptor_count: u64,
	label_bytes:      u64,
}

/* Buffer_Session_Descriptor_Record is one pointer-free complete graph projection. */
Buffer_Session_Descriptor_Record :: struct {
	entry_session_id:          u64,
	entry_session_generation:  u64,
	entry_registry_generation: u64,
	entry_id:                  u64,
	entry_slot:                u64,
	entry_generation:          u64,
	buffer_id:                 u64,
	history_id:                u64,
	view_registry_id:          u64,
	view_id:                   u64,
	view_generation:           u64,
	has_document:              u64,
	document_id:               u64,
	label_offset:              u64,
	label_bytes:               u64,
	association:               u64,
	persistence:               u64,
	operation:                 u64,
	active:                    u64,
	modified:                  u64,
	activation_sequence:       u64,
}

/* Buffer_Session_Request_Header_Record describes one copied lifecycle request. */
Buffer_Session_Request_Header_Record :: struct {
	expected_scope:             Buffer_Session_Scope_Record,
	operation:                  u64,
	authority:                  u64,
	entry_session_id:           u64,
	entry_session_generation:   u64,
	entry_registry_generation:  u64,
	entry_id:                   u64,
	entry_slot:                 u64,
	entry_generation:           u64,
	mark_count:                 u64,
	reserved_0:                 u64,
	reserved_1:                 u64,
	reserved_2:                 u64,
	reserved_3:                 u64,
	reserved_4:                 u64,
	text_bytes:                 u64,
	decision_count:             u64,
}

/* Buffer_Session_Mark_Record identifies one exact entry and semantic operation. */
Buffer_Session_Mark_Record :: struct {
	entry_session_id:          u64,
	entry_session_generation:  u64,
	entry_registry_generation: u64,
	entry_id:                  u64,
	entry_slot:                u64,
	entry_generation:          u64,
	kind:                      u64,
}

/* Buffer_Session_Decision_Record identifies one copied marked decision and path. */
Buffer_Session_Decision_Record :: struct {
	entry_session_id:          u64,
	entry_session_generation:  u64,
	entry_registry_generation: u64,
	entry_id:                  u64,
	entry_slot:                u64,
	entry_generation:          u64,
	kind:                      u64,
	path_offset:               u64,
	path_bytes:                u64,
}

/* Buffer_Session_Outcome_Record contains no retained native ownership. */
Buffer_Session_Outcome_Record :: struct {
	scope:                      Buffer_Session_Scope_Record,
	completion:                 u64,
	entry_session_id:           u64,
	entry_session_generation:   u64,
	entry_registry_generation:  u64,
	entry_id:                   u64,
	entry_slot:                 u64,
	entry_generation:           u64,
	document_id:                u64,
	buffer_id:                  u64,
	saved_revision:             u64,
	publication:                u64,
	closure_outcome:            u64,
	modified:                   u64,
	last_buffer:                u64,
	marked_outcome:             u64,
	completed_saves:            u64,
	pending_saves:              u64,
	completed_kills:            u64,
	pending_kills:              u64,
	decision_entry_id:          u64,
	failed_entry_id:            u64,
	live_buffers:               u64,
	live_documents:             u64,
}

/* buffer_session_descriptor_record_bytes checks quotas and complete response width. */
buffer_session_descriptor_record_bytes :: proc(
	descriptor_count, label_bytes: u64,
) -> (bytes: u64, ok: bool) {
	if descriptor_count > MAX_BUFFER_SESSION_DESCRIPTORS ||
	   label_bytes > MAX_BUFFER_SESSION_LABEL_BYTES {
		return 0, false
	}
	return BUFFER_SESSION_DESCRIPTOR_HEADER_BYTES +
	       descriptor_count * BUFFER_SESSION_DESCRIPTOR_RECORD_BYTES + label_bytes, true
}

/* buffer_session_request_record_bytes checks copied text and decision quotas. */
buffer_session_request_record_bytes :: proc(
	text_bytes, mark_count, decision_count, decision_path_bytes: u64,
) -> (bytes: u64, ok: bool) {
	if text_bytes > MAX_BUFFER_SESSION_REQUEST_TEXT_BYTES ||
	   mark_count > MAX_BUFFER_SESSION_MARKS ||
	   decision_count > MAX_BUFFER_SESSION_DECISIONS ||
	   decision_path_bytes > MAX_BUFFER_SESSION_LABEL_BYTES {
		return 0, false
	}
	return BUFFER_SESSION_REQUEST_HEADER_BYTES + text_bytes +
	       mark_count * BUFFER_SESSION_MARK_RECORD_BYTES +
	       decision_count * BUFFER_SESSION_DECISION_RECORD_BYTES + decision_path_bytes, true
}

/* buffer_session_record_layout_is_valid verifies every C and Racket ABI width. */
buffer_session_record_layout_is_valid :: proc() -> bool {
	return u64(size_of(Buffer_Session_Scope_Record)) == BUFFER_SESSION_SCOPE_RECORD_BYTES &&
	       u64(size_of(Buffer_Session_Usage_Record)) == BUFFER_SESSION_USAGE_RECORD_BYTES &&
	       u64(size_of(Buffer_Session_Descriptor_Header_Record)) ==
	           BUFFER_SESSION_DESCRIPTOR_HEADER_BYTES &&
	       u64(size_of(Buffer_Session_Descriptor_Record)) ==
	           BUFFER_SESSION_DESCRIPTOR_RECORD_BYTES &&
	       u64(size_of(Buffer_Session_Request_Header_Record)) ==
	           BUFFER_SESSION_REQUEST_HEADER_BYTES &&
	       u64(size_of(Buffer_Session_Decision_Record)) ==
	           BUFFER_SESSION_DECISION_RECORD_BYTES &&
	       u64(size_of(Buffer_Session_Mark_Record)) == BUFFER_SESSION_MARK_RECORD_BYTES &&
	       u64(size_of(Buffer_Session_Outcome_Record)) == BUFFER_SESSION_OUTCOME_RECORD_BYTES
}
