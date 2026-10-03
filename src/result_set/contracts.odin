// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package result_set owns bounded session-local result generations and locations.
package result_set

import "../editor"
import "base:runtime"

MAX_RESULT_SETS :: u32(32)
MAX_RESULT_LOCATIONS :: u32(65_536)
MAX_RESULT_GROUPS :: u32(4_096)
MAX_RESULT_TEXT_BYTES :: u64(8 * 1_024 * 1_024)
MAX_RESULT_PREVIEW_BYTES :: u32(4 * 1_024)
MAX_RESULT_ANNOTATION_BYTES :: u32(1 * 1_024)
MAX_RESULT_TEMPORARY_BYTES :: u64(32 * 1_024 * 1_024)

Result_Set_ID :: distinct u64
Result_Set_Generation :: distinct u64
Source_ID :: distinct u64
Source_Generation :: distinct u64
Location_ID :: distinct u64
Group_ID :: distinct u64

Source_Kind :: enum u8 {
	Invalid,
	Active_Search,
	Language_Diagnostics,
	Language_Symbols,
	Language_Navigation,
	Project_Search,
	Programmable,
	Jan_Agenda,
	Jan_Formula_Trace,
	Test,
}

Completeness :: enum u8 {
	Invalid,
	Complete,
	Incomplete,
}

Edit_Capability :: enum u8 {
	Invalid,
	Read_Only,
	Single_Buffer,
	Multiple_Buffers,
}

Location :: struct {
	id:                Location_ID,
	group_id:          Group_ID,
	buffer_id:         editor.Buffer_ID,
	revision:          editor.Revision,
	start:             editor.Byte_Offset,
	end:               editor.Byte_Offset,
	source_identity:   u64,
	preview:           string,
	annotation:        string,
	preview_match_start: u32,
	preview_match_end:   u32,
	preview_match_present: bool,
}

Location_Definition :: struct {
	id:                Location_ID,
	group_id:          Group_ID,
	buffer_id:         editor.Buffer_ID,
	revision:          editor.Revision,
	start:             editor.Byte_Offset,
	end:               editor.Byte_Offset,
	source_identity:   u64,
	preview:           string,
	annotation:        string,
	preview_match_start: u32,
	preview_match_end:   u32,
	preview_match_present: bool,
}

Group :: struct {
	id:    Group_ID,
	label: string,
}

Group_Definition :: struct {
	id:    Group_ID,
	label: string,
}

Continuation :: struct {
	present: bool,
	provider: u64,
	cursor:   u64,
	limit:    u64,
}

Refresh_Descriptor :: struct {
	provider:          u64,
	query_identity:    u64,
	policy_generation: u64,
	scope_generation:  u64,
}

Source_Descriptor :: struct {
	id:         Source_ID,
	generation: Source_Generation,
	kind:       Source_Kind,
}

Source_Metadata :: struct {
	descriptor: string,
	values:     [8]u64,
}

Limits :: struct {
	sets:             u32,
	locations:        u32,
	groups:           u32,
	text_bytes:       u64,
	preview_bytes:    u32,
	annotation_bytes: u32,
	temporary_bytes:  u64,
}

DEFAULT_LIMITS :: Limits {
	sets = MAX_RESULT_SETS,
	locations = MAX_RESULT_LOCATIONS,
	groups = MAX_RESULT_GROUPS,
	text_bytes = MAX_RESULT_TEXT_BYTES,
	preview_bytes = MAX_RESULT_PREVIEW_BYTES,
	annotation_bytes = MAX_RESULT_ANNOTATION_BYTES,
	temporary_bytes = MAX_RESULT_TEMPORARY_BYTES,
}

Accounting :: struct {
	sets:             u32,
	locations:        u32,
	groups:           u32,
	preview_bytes:    u64,
	annotation_bytes: u64,
	group_label_bytes: u64,
	metadata_bytes:   u64,
	retained_bytes:   u64,
}

Publication :: struct {
	set_id:             Result_Set_ID,
	expected_generation: Result_Set_Generation,
	source:             Source_Descriptor,
	metadata:           Source_Metadata,
	completeness:       Completeness,
	continuation:       Continuation,
	refresh:            Refresh_Descriptor,
	edit_capability:    Edit_Capability,
	locations:          []Location_Definition,
	groups:             []Group_Definition,
	selected:           Location_ID,
	has_selection:      bool,
}

View :: struct {
	set_id:          Result_Set_ID,
	generation:      Result_Set_Generation,
	source:          Source_Descriptor,
	metadata:        Source_Metadata,
	completeness:    Completeness,
	continuation:    Continuation,
	refresh:         Refresh_Descriptor,
	edit_capability: Edit_Capability,
	locations:       []Location,
	groups:          []Group,
	selected_index:  u32,
	has_selection:   bool,
	accounting:      Accounting,
}

Movement :: enum u8 {
	Invalid,
	First,
	Previous,
	Next,
	Last,
}

Transition :: enum u8 {
	Invalid,
	Published,
	Replaced,
	Selected,
	No_Change,
	Closed,
}

Result :: struct {
	transition:    Transition,
	set_id:        Result_Set_ID,
	generation:    Result_Set_Generation,
	location_id:   Location_ID,
	selected_index: u32,
	has_selection: bool,
}

Failure_Code :: enum u8 {
	None,
	Invalid_Registry,
	Closed_Registry,
	Invalid_Publication,
	Invalid_Source,
	Invalid_Location,
	Invalid_Group,
	Duplicate_Identity,
	Stale_Generation,
	Set_Limit,
	Location_Limit,
	Group_Limit,
	Text_Limit,
	Preview_Limit,
	Annotation_Limit,
	Persistent_Memory_Limit,
	Set_Not_Found,
	No_Selection,
	Invalid_Movement,
	Arithmetic_Overflow,
}

Failure :: struct {
	code:       Failure_Code,
	set_id:     Result_Set_ID,
	generation: Result_Set_Generation,
	location_id: Location_ID,
	group_id:   Group_ID,
	limit:      u64,
	actual:     u64,
}

Config :: struct {
	limits:    Limits,
	allocator: runtime.Allocator,
}

Registry :: struct {
	state: rawptr,
}
