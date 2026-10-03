// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../layout"

/* LAYOUT_CAPABILITY_SCHEMA_VERSION identifies the first programmable layout ABI. */
LAYOUT_CAPABILITY_SCHEMA_VERSION :: u64(1)
/* MAX_LAYOUT_SNAPSHOT_NODES bounds one copied programmable layout snapshot. */
MAX_LAYOUT_SNAPSHOT_NODES :: u64(layout.MAX_SNAPSHOT_NODES)

/* LAYOUT_SCOPE_RECORD_BYTES is one copied capability authority snapshot. */
LAYOUT_SCOPE_RECORD_BYTES :: u64(64)
/* LAYOUT_SNAPSHOT_HEADER_BYTES precedes copied node records. */
LAYOUT_SNAPSHOT_HEADER_BYTES :: u64(192)
/* LAYOUT_NODE_RECORD_BYTES is one pointer-free copied layout node. */
LAYOUT_NODE_RECORD_BYTES :: u64(376)
/* LAYOUT_REQUEST_RECORD_BYTES is one generation-checked mutation request. */
LAYOUT_REQUEST_RECORD_BYTES :: u64(144)
/* LAYOUT_OUTCOME_RECORD_BYTES is one copied mutation outcome. */
LAYOUT_OUTCOME_RECORD_BYTES :: u64(224)

/* Layout_Capability_Operation identifies one admitted synchronous layout request. */
Layout_Capability_Operation :: enum i32 {
	Scope = 1,
	Snapshot = 2,
	Split_Below = 3,
	Split_Right = 4,
	Focus = 5,
	Close = 6,
	Keep_Only = 7,
	Resize = 8,
	Balance_Dimensions = 9,
	Balance_Areas = 10,
	Inspect_Dedication = 11,
	Set_Dedication = 12,
}

/* Layout_Scope_Record binds one capability to exact owner, layout, and pane generations. */
Layout_Scope_Record :: struct {
	schema_version:       u64,
	access:               u64,
	owner_id:             u64,
	layout_id:            u64,
	layout_generation:    u64,
	pane_id:              u64,
	pane_slot:            u64,
	pane_slot_generation: u64,
}

/* Layout_Snapshot_Header_Record describes one bounded copied node array. */
Layout_Snapshot_Header_Record :: struct {
	scope:                   Layout_Scope_Record,
	geometry_state:          u64,
	geometry_rows:           u64,
	geometry_columns:        u64,
	global_reserved_rows:    u64,
	global_reserved_columns: u64,
	root_id:                 u64,
	active_owner_id:         u64,
	active_layout_id:        u64,
	active_layout_generation: u64,
	active_pane_id:          u64,
	active_pane_slot:        u64,
	active_pane_slot_generation: u64,
	node_count:              u64,
	pane_count:              u64,
	partition_count:         u64,
	geometry_work:           u64,
}

/* Layout_Node_Record copies every public node field without native ownership. */
Layout_Node_Record :: struct {
	kind:                    u64,
	node_id:                 u64,
	slot_generation:         u64,
	parent_id:               u64,
	depth:                   u64,
	arrangement:             u64,
	first_child_id:          u64,
	second_child_id:         u64,
	first_weight:            u64,
	second_weight:           u64,
	pane_owner_id:           u64,
	pane_layout_id:          u64,
	pane_layout_generation:  u64,
	pane_id:                 u64,
	pane_slot:               u64,
	pane_slot_generation:    u64,
	view_registry_id:        u64,
	view_id:                 u64,
	view_generation:         u64,
	buffer_id:               u64,
	entry_session_id:        u64,
	entry_session_generation: u64,
	entry_registry_generation: u64,
	entry_id:                u64,
	entry_slot:              u64,
	entry_generation:        u64,
	dedication:              u64,
	history_count:           u64,
	history_generation:      u64,
	outer_row:               u64,
	outer_column:            u64,
	outer_height:            u64,
	outer_width:             u64,
	content_row:             u64,
	content_column:          u64,
	content_height:          u64,
	content_width:           u64,
	status_row:              u64,
	status_column:           u64,
	status_height:           u64,
	status_width:            u64,
	separator_row:           u64,
	separator_column:        u64,
	separator_height:        u64,
	separator_width:         u64,
	active:                  u64,
	mru_rank:                u64,
}

/* Layout_Request_Record carries one exact copied scope and target pane. */
Layout_Request_Record :: struct {
	expected_scope:             Layout_Scope_Record,
	operation:                  u64,
	pane_owner_id:              u64,
	pane_layout_id:             u64,
	pane_layout_generation:     u64,
	pane_id:                    u64,
	pane_slot:                  u64,
	pane_slot_generation:       u64,
	arrangement:                u64,
	delta:                      u64,
	dedication:                 u64,
}

/* Layout_Outcome_Record contains refreshed identities and no retained native state. */
Layout_Outcome_Record :: struct {
	scope:                      Layout_Scope_Record,
	primary_owner_id:           u64,
	primary_layout_id:          u64,
	primary_layout_generation:  u64,
	primary_pane_id:            u64,
	primary_pane_slot:          u64,
	primary_pane_slot_generation: u64,
	secondary_owner_id:         u64,
	secondary_layout_id:        u64,
	secondary_layout_generation: u64,
	secondary_pane_id:          u64,
	secondary_pane_slot:        u64,
	secondary_pane_slot_generation: u64,
	changed:                    u64,
	partition_id:               u64,
	arrangement:                u64,
	delta:                      u64,
	first_span:                 u64,
	second_span:                u64,
	previous_dedication:        u64,
	current_dedication:         u64,
}

/* layout_snapshot_record_bytes checks the copied node quota and response width. */
layout_snapshot_record_bytes :: proc(node_count: u64) -> (bytes: u64, ok: bool) {
	if node_count > MAX_LAYOUT_SNAPSHOT_NODES {
		return 0, false
	}
	return LAYOUT_SNAPSHOT_HEADER_BYTES + node_count * LAYOUT_NODE_RECORD_BYTES, true
}

/* layout_record_layout_is_valid verifies every C and Racket ABI width. */
layout_record_layout_is_valid :: proc() -> bool {
	return u64(size_of(Layout_Scope_Record)) == LAYOUT_SCOPE_RECORD_BYTES &&
	       u64(size_of(Layout_Snapshot_Header_Record)) == LAYOUT_SNAPSHOT_HEADER_BYTES &&
	       u64(size_of(Layout_Node_Record)) == LAYOUT_NODE_RECORD_BYTES &&
	       u64(size_of(Layout_Request_Record)) == LAYOUT_REQUEST_RECORD_BYTES &&
	       u64(size_of(Layout_Outcome_Record)) == LAYOUT_OUTCOME_RECORD_BYTES
}
