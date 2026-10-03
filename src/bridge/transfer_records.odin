// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

/* MAX_TRANSFER_INSPECTION_ENTRIES bounds one copied ring metadata response. */
MAX_TRANSFER_INSPECTION_ENTRIES :: u64(256)
/* MAX_TRANSFER_ENTRY_TEXT_BYTES bounds one copied retained-text response. */
MAX_TRANSFER_ENTRY_TEXT_BYTES :: u64(12 * 1024 * 1024)
/* TRANSFER_SCOPE_RECORD_BYTES is the stable scalar scope width across the native boundary. */
TRANSFER_SCOPE_RECORD_BYTES :: u64(88)
/* TRANSFER_REGION_RECORD_BYTES is the stable copied region-summary width. */
TRANSFER_REGION_RECORD_BYTES :: u64(128)
/* TRANSFER_RING_HEADER_BYTES is the stable copied ring-header width. */
TRANSFER_RING_HEADER_BYTES :: u64(104)
/* TRANSFER_RING_ENTRY_BYTES is the stable copied ring-entry width. */
TRANSFER_RING_ENTRY_BYTES :: u64(40)

/* Transfer_Operation identifies one admitted synchronous transfer callback request. */
Transfer_Operation :: enum i32 {
	Scope = 1,
	Region = 2,
	Ring = 3,
	Entry_Text = 4,
	Invoke = 5,
}

/* Transfer_Scope_Record is the pointer-free authority and state identity snapshot. */
Transfer_Scope_Record :: struct {
	editor_session_id:          u64,
	access:                     u64,
	view_registry_id:           u64,
	view_id:                    u64,
	view_generation:            u64,
	view_state_generation:      u64,
	buffer_id:                  u64,
	revision:                   u64,
	ring_id:                    u64,
	ring_generation:            u64,
	command_registry_generation: u64,
}

/* Transfer_Region_Record is one copied logical selection summary. */
Transfer_Region_Record :: struct {
	scope:         Transfer_Scope_Record,
	point:         u64,
	mark:          u64,
	region_start:  u64,
	region_end:    u64,
	flags:         u64,
}

/* Transfer_Ring_Header_Record precedes newest-to-oldest copied entry records. */
Transfer_Ring_Header_Record :: struct {
	scope:       Transfer_Scope_Record,
	entry_count: u64,
	flags:       u64,
}

/* Transfer_Ring_Entry_Record is one pointer-free retained-entry description. */
Transfer_Ring_Entry_Record :: struct {
	entry_id:             u64,
	byte_count:           u64,
	admission_kind:       u64,
	coalesced_operations: u64,
	generation:           u64,
}

/* transfer_ring_record_bytes validates occupancy and returns its exact copied byte width. */
transfer_ring_record_bytes :: proc(entry_count: u64) -> (bytes: u64, ok: bool) {
	if entry_count > MAX_TRANSFER_INSPECTION_ENTRIES {
		return 0, false
	}
	return TRANSFER_RING_HEADER_BYTES + entry_count * TRANSFER_RING_ENTRY_BYTES, true
}

/* transfer_record_layout_is_valid verifies the native ABI widths used by C and Racket. */
transfer_record_layout_is_valid :: proc() -> bool {
	return u64(size_of(Transfer_Scope_Record)) == TRANSFER_SCOPE_RECORD_BYTES &&
	       u64(size_of(Transfer_Region_Record)) == TRANSFER_REGION_RECORD_BYTES &&
	       u64(size_of(Transfer_Ring_Header_Record)) == TRANSFER_RING_HEADER_BYTES &&
	       u64(size_of(Transfer_Ring_Entry_Record)) == TRANSFER_RING_ENTRY_BYTES
}
