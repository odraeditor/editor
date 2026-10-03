// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package maksym owns bounded directory-buffer state and editor-facing projections.
package maksym

import "../filesystem"
import "base:runtime"

/* Directory_Buffer owns one live Maksym directory generation. */
Directory_Buffer :: struct {
	state: rawptr,
}

/* MAX_PROJECTION_BYTES bounds one complete textual directory projection. */
MAX_PROJECTION_BYTES :: u64(32 * 1_024 * 1_024)

/* Projection owns one immutable textual rendering and its resource ranges. */
Projection :: struct {
	state: rawptr,
}

/* Editable_Listing owns one immutable filename baseline for ordinary text editing. */
Editable_Listing :: struct {
	state: rawptr,
}

/* MAX_TARGET_SET_MEMBERS bounds one complete marked-resource set. */
MAX_TARGET_SET_MEMBERS :: u32(4_096)

/* Target_Set_ID identifies one stable target-set owner. */
Target_Set_ID :: distinct u64

/* Target_Set_Generation invalidates stale target-set mutations. */
Target_Set_Generation :: distinct u64

/* Target_Set owns one ordered checked collection of resource identities. */
Target_Set :: struct {
	state: rawptr,
}

/* Target_Set_Snapshot owns one copied target-set inspection. */
Target_Set_Snapshot :: struct {
	state: rawptr,
}

/* Target_Set_Member identifies one ordered resource in a target set. */
Target_Set_Member :: struct {
	identity: filesystem.Resource_ID,
}

/* Target_Set_Config supplies identity, listing provenance, capacity, and storage policy. */
Target_Set_Config :: struct {
	id:                 Target_Set_ID,
	directory_identity: filesystem.Resource_ID,
	listing_generation: u64,
	member_limit:       u32,
	allocator:          runtime.Allocator,
}

/* Target_Set_View borrows or copies one complete target-set generation. */
Target_Set_View :: struct {
	id:                 Target_Set_ID,
	generation:         Target_Set_Generation,
	directory_identity: filesystem.Resource_ID,
	listing_generation: u64,
	members:            []Target_Set_Member,
	has_current:        bool,
	current_index:      int,
	member_limit:       u32,
}

/* Target_Set_Transition reports one checked membership change. */
Target_Set_Transition :: struct {
	generation: Target_Set_Generation,
	changed:    bool,
}

/* Target_Set_Movement reports one checked current-member transition. */
Target_Set_Movement :: struct {
	generation:     Target_Set_Generation,
	previous_index: int,
	current_index:  int,
	identity:       filesystem.Resource_ID,
	changed:        bool,
}

/* Rename_Plan owns one complete checked set of same-directory name changes. */
Rename_Plan :: struct {
	state: rawptr,
}

/* Projection_Row maps one visible line and filename range to stable resource identity. */
Projection_Row :: struct {
	identity:   filesystem.Resource_ID,
	kind:       filesystem.Entry_Kind,
	line_index: u64,
	row_start:  u64,
	name_start: u64,
	name_end:   u64,
	row_end:    u64,
}

/* Projection_View borrows one complete immutable textual directory rendering. */
Projection_View :: struct {
	directory_identity: filesystem.Resource_ID,
	generation:         u64,
	text:               string,
	header_end:         u64,
	rows:               []Projection_Row,
	has_selection:      bool,
	selected_index:     int,
}

/* Editable_Name binds one baseline filename to stable resource identity. */
Editable_Name :: struct {
	identity:     filesystem.Resource_ID,
	kind:         filesystem.Entry_Kind,
	name:         string,
	prefix_bytes: u64,
}

/* Editable_Listing_View borrows one immutable editable-session baseline. */
Editable_Listing_View :: struct {
	directory_identity: filesystem.Resource_ID,
	generation:         u64,
	header_bytes:       u64,
	names:              []Editable_Name,
}

/* Rename_Change records one checked name-only proposal without touching the filesystem. */
Rename_Change :: struct {
	identity: filesystem.Resource_ID,
	kind:     Change_Kind,
	entry_kind: filesystem.Entry_Kind,
	from:     string,
	to:       string,
	destructive: bool,
	recovery_available: bool,
}

/* Change_Kind classifies one calculated editable-listing proposal. */
Change_Kind :: enum u8 {
	Invalid,
	Rename,
	Move,
	Delete,
}

/* Rename_Plan_View borrows one complete calculated rename batch. */
Rename_Plan_View :: struct {
	directory_identity: filesystem.Resource_ID,
	generation:         u64,
	changes:            []Rename_Change,
}

/* Sort_Order selects the stable row ordering applied by Maksym. */
Sort_Order :: enum u8 {
	Invalid,
	Directories_First,
	Name,
}

/* Details_Mode selects whether metadata columns participate in the projection. */
Details_Mode :: enum u8 {
	Invalid,
	Full,
	Simplified,
}

/* Directory_View borrows one complete immutable directory-buffer generation. */
Directory_View :: struct {
	directory:          string,
	directory_identity: filesystem.Resource_ID,
	generation:         u64,
	entries:            []filesystem.Entry_Descriptor,
	has_selection:      bool,
	selected_index:     int,
	selected_identity:  filesystem.Resource_ID,
	sort_order:         Sort_Order,
	details:            Details_Mode,
}

/* Movement_Result reports one checked entry-selection transition. */
Movement_Result :: struct {
	previous_index: int,
	selected_index: int,
	changed:        bool,
}

/* Operation identifies the Maksym operation that produced a failure. */
Operation :: enum u8 {
	None,
	Open_Directory_Buffer,
	Inspect_Directory_Buffer,
	Refresh_Directory_Buffer,
	Select_Entry,
	Move_Selection,
	Toggle_Details,
	Cycle_Sort,
	Close_Directory_Buffer,
	Build_Projection,
	Inspect_Projection,
	Close_Projection,
	Open_Editable_Listing,
	Inspect_Editable_Listing,
	Calculate_Renames,
	Close_Rename_Plan,
	Close_Editable_Listing,
	Open_Target_Set,
	Replace_Target_Set,
	Reconcile_Target_Set,
	Mark_Target,
	Unmark_Target,
	Invert_Targets,
	Clear_Targets,
	Move_Current_Target,
	Inspect_Target_Set,
	Close_Target_Set_Snapshot,
	Close_Target_Set,
}

/* Failure_Code classifies expected directory-buffer failures. */
Failure_Code :: enum u8 {
	None,
	Invalid_Arguments,
	Already_Open,
	Closed_Buffer,
	Invalid_Generation,
	Directory_Changed,
	Entry_Not_Found,
	Filesystem_Failure,
	Persistent_Memory_Limit,
	Projection_Limit,
	Invalid_Editable_Projection,
	Invalid_Name,
	Duplicate_Destination,
	Invalid_Target_Set,
	Stale_Target_Set,
	Target_Set_Limit,
	Duplicate_Target,
}

/* Projection_Config supplies explicit storage policy for one rendering. */
Projection_Config :: struct {
	allocator: runtime.Allocator,
	text_bytes: u64,
}

/* default_projection_config returns the bounded factory projection policy. */
default_projection_config :: proc(allocator := context.allocator) -> Projection_Config {
	return Projection_Config{allocator = allocator, text_bytes = MAX_PROJECTION_BYTES}
}

/* Failure_Context reports one bounded Maksym failure without partial publication. */
Failure_Context :: struct {
	operation:          Operation,
	code:               Failure_Code,
	generation:         u64,
	resource:           filesystem.Resource_ID,
	filesystem_failure: filesystem.Failure_Context,
}
