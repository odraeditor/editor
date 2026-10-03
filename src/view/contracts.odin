// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package view owns frontend-independent editor-view state and lifecycle.
package view

import "../editor"
import "../gutter"
import "../indentation"
import "../search"
import "base:runtime"

/* MAX_RETAINED_VIEWS bounds buffer-owned primary presentation records. */
MAX_RETAINED_VIEWS :: 1_024
/* MAX_ADDITIONAL_VIEWS bounds pane-owned presentation records. */
MAX_ADDITIONAL_VIEWS :: 128
/* MAX_VIEWS is the total hard capacity of one editor-view registry. */
MAX_VIEWS :: MAX_RETAINED_VIEWS + MAX_ADDITIONAL_VIEWS
/* DEFAULT_TAB_WIDTH is the resolved initial tab width in display columns. */
DEFAULT_TAB_WIDTH :: indentation.DEFAULT_DISPLAY_TAB_WIDTH
/* MAX_TAB_WIDTH bounds resolved tab expansion policy. */
MAX_TAB_WIDTH :: indentation.MAX_WIDTH
/* MAX_HIDDEN_RANGES bounds one view-local hidden-range projection. */
MAX_HIDDEN_RANGES :: u32(16_384)

/* Registry_ID identifies one editor-view registry; zero is invalid. */
Registry_ID :: distinct u32
/* View_ID identifies one editor view for the lifetime of its registry. */
View_ID :: distinct u64
/* Display_Profile_ID identifies one versioned display policy; zero is invalid. */
Display_Profile_ID :: distinct u64
/* Visibility_Generation identifies one exact view-local hidden-range state. */
Visibility_Generation :: distinct u64

/* Presentation_Ownership distinguishes retained primary state from pane-owned copies. */
Presentation_Ownership :: enum u8 {
	Invalid,
	Retained_Primary,
	Additional,
}

/* View_Handle is a checked non-pointer reference to one exact view generation. */
View_Handle :: struct {
	registry_id: Registry_ID,
	view_id:     View_ID,
	slot:        u16,
	generation:  u32,
}

/* Config contains the resolved frontend-independent policy admitted at creation. */
Config :: struct {
	indentation_policy: indentation.Policy,
	display_profile_id: Display_Profile_ID,
	gutter_policy:      gutter.Factory_Policy,
}

/* DEFAULT_CONFIG is the initial resolved editor-view policy. */
DEFAULT_CONFIG :: Config {
	indentation_policy = indentation.DEFAULT_POLICY,
	display_profile_id = Display_Profile_ID(1),
	gutter_policy = gutter.DEFAULT_FACTORY_POLICY,
}

/* Gutter_Presentation is one checked view-local line-number policy generation. */
Gutter_Presentation :: struct {
	policy:              gutter.Factory_Policy,
	generation:          u64,
	overrides_default:   bool,
}

/* Mark_Snapshot describes the buffer's optional retained mark. */
Mark_Snapshot :: struct {
	present:  bool,
	position: editor.Position,
}

/* Hidden_Range is one half-open canonical source interval supplied by a caller. */
Hidden_Range :: struct {
	start: editor.Position,
	end:   editor.Position,
}

/* Visibility_Update reports one accepted view-local hidden-range transition. */
Visibility_Update :: struct {
	generation:      Visibility_Generation,
	source_revision: editor.Revision,
	range_count:     u32,
	changed:         bool,
}

/* Visibility_Snapshot describes copied current ranges written to caller storage. */
Visibility_Snapshot :: struct {
	generation:      Visibility_Generation,
	source_revision: editor.Revision,
	range_count:     u32,
}

/* Point_Movement_Region_Action declares how one point move affects region state. */
Point_Movement_Region_Action :: enum u8 {
	Invalid,
	Preserve,
	Deactivate,
	Activate,
}

/* Search_Status reports the current incremental-search interaction state. */
Search_Status :: enum u8 {
	Inactive,
	Active,
	Failing,
	Pending,
	Wrapped,
}

/* Search_Presentation selects whether visible occurrences cover matches or complete lines. */
Search_Presentation :: enum u8 {
	Matches,
	Lines,
}

/* Search_Snapshot borrows one active session until the next view operation or close. */
Search_Snapshot :: struct {
	present:                  bool,
	interaction_generation:   u64,
	policy_generation:        search.Policy_Generation,
	source_revision:          editor.Revision,
	direction:                search.Direction,
	kind:                     search.Pattern_Kind,
	scope:                    search.Scope,
	status:                   Search_Status,
	presentation:             Search_Presentation,
	query:                    string,
	last_successful_query:    string,
	policy:                   search.Policy,
	limits:                   search.Limits,
	origin_point_position:    editor.Position,
	effective_case:           search.Effective_Case,
	has_current:              bool,
	current_index:            u32,
	occurrences:              []search.Occurrence,
	captures:                 []search.Capture,
	progress:                 search.Progress,
	usage:                    search.Usage,
}

/* Search_Update describes one complete checked session publication. */
Search_Update :: struct {
	interaction_generation: u64,
	policy_generation:      search.Policy_Generation,
	direction:              search.Direction,
	scope:                  search.Scope,
}

/* Query_Replacement_Group_ID identifies one uninterrupted semantic undo group. */
Query_Replacement_Group_ID :: distinct u64

/* Query_Replacement_Status reports the current progressive replacement state. */
Query_Replacement_Status :: enum u8 {
	Inactive,
	Awaiting_Response,
	Pending,
	Wrapped,
	Exhausted,
	Recomputation_Required,
}

/* Query_Replacement_Response records the transition that produced one session state. */
Query_Replacement_Response :: enum u8 {
	Invalid,
	Started,
	Continued,
	Skipped,
	Replaced,
	Recomputed,
}

/* Query_Replacement_Update describes one complete checked session publication. */
Query_Replacement_Update :: struct {
	interaction_generation: u64,
	policy_generation:      search.Policy_Generation,
	direction:              search.Direction,
	scope:                  search.Scope,
	semantic_group:         Query_Replacement_Group_ID,
	response:               Query_Replacement_Response,
	replacements:           u64,
	skips:                  u64,
}

/* Query_Replacement_Snapshot borrows one active session until the next view operation. */
Query_Replacement_Snapshot :: struct {
	present:                bool,
	interaction_generation: u64,
	policy_generation:      search.Policy_Generation,
	source_revision:        editor.Revision,
	observed_revision:      editor.Revision,
	source_text_bytes:      u64,
	observed_text_bytes:    u64,
	direction:              search.Direction,
	kind:                   search.Pattern_Kind,
	scope:                  search.Scope,
	status:                 Query_Replacement_Status,
	last_response:          Query_Replacement_Response,
	semantic_group:         Query_Replacement_Group_ID,
	pattern:                string,
	replacement:            string,
	search_policy:          search.Policy,
	search_limits:          search.Limits,
	replacement_policy:     search.Replacement_Policy,
	replacement_limits:     search.Replacement_Limits,
	effective_case:         search.Effective_Case,
	replacements:           u64,
	skips:                  u64,
	recomputations:         u64,
	has_current:            bool,
	current_index:          u32,
	occurrences:            []search.Occurrence,
	captures:               []search.Capture,
	progress:               search.Progress,
	usage:                  search.Usage,
}

/* Terminal_Viewport is one view-local retained terminal row and follow policy. */
Terminal_Viewport :: struct {
	top_row:                   u64,
	horizontal_display_column: u32,
	follow_tail:               bool,
}

/* Terminal_Copy_State is one view-local terminal copy-mode location and mark. */
Terminal_Copy_State :: struct {
	active:       bool,
	point_row:    u64,
	point_column: u32,
	mark_present: bool,
	mark_row:     u64,
	mark_column:  u32,
}

/* Terminal_Geometry is one checked PTY character-cell size. */
Terminal_Geometry :: struct {
	columns: u16,
	rows:    u16,
}

/* Terminal_View_State is the copied terminal attachment state of one view. */
Terminal_View_State :: struct {
	attached:          bool,
	viewport:          Terminal_Viewport,
	copy:              Terminal_Copy_State,
	geometry_authority: bool,
	geometry:          Terminal_Geometry,
}

/* Terminal_Geometry_Update reports one focus-driven authority transfer. */
Terminal_Geometry_Update :: struct {
	previous: View_Handle,
	current:  View_Handle,
	geometry: Terminal_Geometry,
	changed:  bool,
}

/* Snapshot combines one view's presentation with buffer selection at one revision. */
Snapshot :: struct {
	view_id:                   View_ID,
	view_generation:           u32,
	state_generation:          u64,
	selection_generation:      u64,
	buffer_id:                 editor.Buffer_ID,
	buffer_kind:               editor.Buffer_Kind,
	revision:                  editor.Revision,
	point_position:            editor.Position,
	effective_point_position:  editor.Position,
	mark:                      Mark_Snapshot,
	region_active:             bool,
	selection_shape:           editor.Selection_Shape,
	rectangle_column_policy:   editor.Rectangle_Column_Policy,
	overwrite_mode:             bool,
	desired_display_column:    u32,
	viewport_origin_position:  editor.Position,
	horizontal_display_column: u32,
	indentation_policy:        indentation.Effective_Policy,
	tab_width:                 u16,
	display_profile_id:        Display_Profile_ID,
	gutter:                    Gutter_Presentation,
	presentation_ownership:    Presentation_Ownership,
	visibility_generation:     Visibility_Generation,
	hidden_range_count:        u32,
	terminal:                  Terminal_View_State,
}

/* Transient_State reports whether one view owns interaction that must resolve before deactivation. */
Transient_State :: struct {
	active_preparation: bool,
	search:             bool,
	query_replacement:  bool,
}

/* Failure_Code classifies expected editor-view lifecycle and state failures. */
Failure_Code :: enum u16 {
	None,
	Invalid_Registry,
	Wrong_Registry,
	Invalid_View,
	Stale_View,
	Capacity_Limit,
	Retained_Primary_Exists,
	Additional_Required,
	Retained_Views,
	Invalid_Config,
	Invalid_Hidden_Range,
	Hidden_Range_Limit,
	Hidden_Range_Destination_Limit,
	Visibility_Generation_Limit,
	Terminal_View_Required,
	Invalid_Terminal_State,
	Geometry_Authority_Required,
	Persistent_Memory_Limit,
	State_Generation_Limit,
	Active_Preparation,
	Missing_Mark,
	Editor_Failure,
	Invalid_Search_Session,
	Stale_Search,
	Search_Failure,
	Invalid_Query_Replacement_Session,
	Stale_Query_Replacement,
}

/* Failure_Context identifies the rejected view, bound, and underlying editor failure. */
Failure_Context :: struct {
	code:            Failure_Code,
	registry_id:     Registry_ID,
	view_id:         View_ID,
	view_generation: u32,
	limit:           u64,
	actual:          u64,
	editor_failure:  editor.Failure_Context,
	search_failure:  search.Failure,
}

/* Registry_Stats reports bounded editor-view registry occupancy and storage. */
Registry_Stats :: struct {
	live_count:       u16,
	retained_count:   u16,
	additional_count: u16,
	capacity:         u16,
	storage_bytes:    u64,
}

@(private)
Registry_State :: enum u8 {
	Uninitialized,
	Ready,
	Closed,
}

@(private)
View_Slot :: struct {
	buffer:                    ^editor.Buffer,
	buffer_id:                 editor.Buffer_ID,
	buffer_kind:               editor.Buffer_Kind,
	view_id:                   View_ID,
	generation:                u32,
	state_generation:          u64,
	stored_point:              editor.Anchor,
	overwrite_mode:             bool,
	desired_display_column:    u32,
	viewport_origin:           editor.Anchor,
	horizontal_display_column: u32,
	indentation_policy:        indentation.Effective_Policy,
	display_profile_id:        Display_Profile_ID,
	gutter:                    Gutter_Presentation,
	presentation_ownership:    Presentation_Ownership,
	visibility:                Visibility_State,
	terminal:                  Terminal_View_State,
	live:                      bool,
	active_preparation:        bool,
	search_session:            Search_Session,
	query_replacement_session: Query_Replacement_Session,
}

@(private)
Visibility_State :: struct {
	generation:    Visibility_Generation,
	ranges:        []Hidden_Range_State,
	storage_bytes: u64,
}

@(private)
Hidden_Range_State :: struct {
	start: editor.Anchor,
	end:   editor.Anchor,
}

@(private)
Search_Session :: struct {
	active:                    bool,
	interaction_generation:    u64,
	policy_generation:         search.Policy_Generation,
	source_revision:           editor.Revision,
	direction:                 search.Direction,
	scope:                     search.Scope,
	status:                    Search_Status,
	presentation:              Search_Presentation,
	origin_point:              editor.Anchor,
	origin_viewport:           editor.Anchor,
	origin_horizontal_column:  u32,
	query:                     search.Query,
	match_result:              search.Result,
	has_match_result:          bool,
	last_successful_query:     []byte,
	progress:                  search.Progress,
	usage:                     search.Usage,
	allocator:                 runtime.Allocator,
}

@(private)
Query_Replacement_Session :: struct {
	active:                 bool,
	interaction_generation: u64,
	policy_generation:      search.Policy_Generation,
	source_revision:        editor.Revision,
	observed_revision:      editor.Revision,
	source_text_bytes:      u64,
	observed_text_bytes:    u64,
	direction:              search.Direction,
	kind:                   search.Pattern_Kind,
	scope:                  search.Scope,
	status:                 Query_Replacement_Status,
	last_response:          Query_Replacement_Response,
	semantic_group:         Query_Replacement_Group_ID,
	pattern:                []byte,
	replacement:            []byte,
	search_policy:          search.Policy,
	search_limits:          search.Limits,
	replacement_policy:     search.Replacement_Policy,
	replacement_limits:     search.Replacement_Limits,
	effective_case:         search.Effective_Case,
	replacements:           u64,
	skips:                  u64,
	recomputations:         u64,
	match_result:           search.Result,
	has_match_result:       bool,
	progress:               search.Progress,
	usage:                  search.Usage,
	allocator:              runtime.Allocator,
}

/*
Registry owns view slots and retained native buffer references behind checked handles.
Callers keep registered Buffer handle addresses stable until dependent views close.
*/
@(private)
Registry_Data :: struct {
	state:         Registry_State,
	registry_id:   Registry_ID,
	next_view_id:  View_ID,
	live_count:    u16,
	retained_count: u16,
	additional_count: u16,
	slots:         [MAX_VIEWS]View_Slot,
	allocator:     runtime.Allocator,
	storage_bytes: u64,
}

/* Registry is an opaque owner of one bounded editor-view registry allocation. */
Registry :: struct {
	state:  rawptr,
	closed: bool,
}

/* Logical_Region_Result selects the committed region outcome of one logical edit. */
Logical_Region_Result :: enum u8 {
	Invalid,
	Preserve,
	Deactivate,
	Activate,
}

/* Logical_Mark_Result selects how one committed logical edit resolves retained mark. */
Logical_Mark_Result :: enum u8 {
	Invalid,
	Preserve,
	Absent,
	Position,
}

/* Logical_Edit_Request describes one post-text point, region, and desired-column result. */
Logical_Edit_Request :: struct {
	buffer_id:              editor.Buffer_ID,
	base_revision:          editor.Revision,
	result_point_offset:    editor.Byte_Offset,
	desired_display_column: u32,
	region:                 Logical_Region_Result,
	mark:                   Logical_Mark_Result,
	result_mark_offset:     editor.Byte_Offset,
	selection_shape:        editor.Selection_Shape,
	rectangle_column_policy: editor.Rectangle_Column_Policy,
}

/* Logical_Commit_Result is the immutable logical view outcome of one committed edit. */
Logical_Commit_Result :: struct {
	present:                bool,
	view_id:                View_ID,
	view_generation:        u32,
	state_generation:       u64,
	buffer_id:              editor.Buffer_ID,
	result_revision:        editor.Revision,
	point_position:         editor.Position,
	mark:                   Mark_Snapshot,
	region_active:          bool,
	selection_shape:        editor.Selection_Shape,
	rectangle_column_policy: editor.Rectangle_Column_Policy,
	desired_display_column: u32,
}

/* Prepared_Logical_Edit is an opaque view-owned participant consumed by publish or abort. */
Prepared_Logical_Edit :: struct {
	state: rawptr,
}
