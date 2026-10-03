// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package gutter owns bounded frontend-independent Gutter geometry, marker
// admission, visible-row composition, and provider lifecycle.
package gutter

import "base:runtime"
import "core:unicode/utf8"

/* MAX_LANES bounds all admitted lanes in one composed TextView. */
MAX_LANES :: 16
/* MAX_LANES_PER_SIDE bounds independently ordered lanes on either side. */
MAX_LANES_PER_SIDE :: 8
/* MAX_VISIBLE_ROWS bounds one retained operating terminal Gutter view. */
MAX_VISIBLE_ROWS :: 80
/* MAX_ROW_TEXT_BYTES bounds one composed side of one visible row. */
MAX_ROW_TEXT_BYTES :: 256
/* MAX_VIEW_TEXT_BYTES bounds all copied Gutter text in one view. */
MAX_VIEW_TEXT_BYTES :: 64 * 1_024
/* MAX_REPRESENTATION_BYTES bounds one primary or fallback representation. */
MAX_REPRESENTATION_BYTES :: 64
/* MAX_MARKER_DETAIL_BYTES bounds one copied inspectable marker description. */
MAX_MARKER_DETAIL_BYTES :: 4 * 1_024
/* MAX_ACTIONS_PER_MARKER bounds semantic actions without callbacks. */
MAX_ACTIONS_PER_MARKER :: 4
/* MAX_MARKERS_PER_GENERATION bounds one immutable provider publication. */
MAX_MARKERS_PER_GENERATION :: 512
/* MAX_COLLISION_MEMBERS bounds inspectable markers at one lane coordinate. */
MAX_COLLISION_MEMBERS :: 16
/* MAX_COMPOSITION_WORK admits one dense programmable publication across one terminal view. */
MAX_COMPOSITION_WORK :: 64 * 1_024
/* MIN_TEXT_CELLS protects a usable text region under Gutter contraction. */
MIN_TEXT_CELLS :: u32(8)

/* Provider_ID identifies one semantic contributor; zero is invalid. */
Provider_ID :: distinct u64
/* Provider_Generation identifies one exact provider definition; zero is invalid. */
Provider_Generation :: distinct u64
/* Lane_ID identifies one provider-scoped lane; zero is invalid. */
Lane_ID :: distinct u64
/* Marker_ID identifies one provider-scoped marker; zero is invalid. */
Marker_ID :: distinct u64
/* Generation identifies one immutable composed Gutter view; zero is invalid. */
Generation :: distinct u64
/* Marker_Generation_ID identifies one immutable marker publication; zero is invalid. */
Marker_Generation_ID :: distinct u64

/* Side selects one independent Gutter edge around the text region. */
Side :: enum u8 {
	Invalid,
	Left,
	Right,
}

/* Attachment_Kind identifies the coordinate family admitted by a lane. */
Attachment_Kind :: enum u8 {
	Logical_Line,
	Display_Row,
}

/* Attachment_Kinds is the bounded set of coordinate families admitted by a lane. */
Attachment_Kinds :: bit_set[Attachment_Kind; u8]

/* Width_Policy selects deterministic lane width behavior. */
Width_Policy :: enum u8 {
	Invalid,
	Fixed,
	Automatic,
	Bounded_Automatic,
	Content_Presence,
}

/* Alignment selects placement inside one resolved lane width. */
Alignment :: enum u8 {
	Invalid,
	Left,
	Center,
	Right,
}

/* Visibility_Policy selects when an admitted lane participates in geometry. */
Visibility_Policy :: enum u8 {
	Invalid,
	Always,
	When_Content,
	Configured,
}

/* Collision_Policy selects deterministic marker presentation within one lane. */
Collision_Policy :: enum u8 {
	Invalid,
	Highest_Priority,
	Stack,
	Aggregate,
	Primary_With_Details,
}

/* Semantic_Role identifies Gutter meaning without physical colors or glyphs. */
Semantic_Role :: enum u8 {
	Invalid,
	Ordinary,
	Background,
	Separator,
	Line_Number,
	Current_Line_Number,
	Diagnostic_Error,
	Diagnostic_Warning,
	Diagnostic_Information,
	Diagnostic_Hint,
	Continuation,
	Clipping,
	Stale,
	Aggregate,
	Unavailable,
}

/* Numbering_Mode selects the factory logical line-number representation. */
Numbering_Mode :: enum u8 {
	Invalid,
	None,
	Absolute,
	Relative,
	Hybrid,
}

/* Numbering_Scope separates logical lines from reserved visual rows. */
Numbering_Scope :: enum u8 {
	Invalid,
	Logical,
	Visual,
}

/* Current_Line_Presentation selects the active-line number policy. */
Current_Line_Presentation :: enum u8 {
	Invalid,
	Absolute,
	Zero,
	Hidden,
}

/* Representation_Kind identifies one frontend-independent representation class. */
Representation_Kind :: enum u8 {
	Invalid,
	Text,
	Glyph,
	Icon,
}

/* Command_Reference identifies one registered semantic command without a callback. */
Command_Reference :: struct {
	registry_generation: u64,
	slot:                u16,
	entry_generation:    u32,
}

/* Representation borrows one bounded primary or fallback presentation value. */
Representation :: struct {
	kind:     Representation_Kind,
	value:    string,
	fallback: string,
}

/* Lane_Definition declares one checked provider-owned lane. */
Lane_Definition :: struct {
	id:             Lane_ID,
	provider:       Provider_ID,
	provider_generation: Provider_Generation,
	side:           Side,
	order:          i16,
	attachments:    Attachment_Kinds,
	width_policy:   Width_Policy,
	minimum_cells:  u16,
	maximum_cells:  u16,
	alignment:      Alignment,
	visibility:     Visibility_Policy,
	collision:      Collision_Policy,
	priority:       u16,
	style_role:     Semantic_Role,
	separator:      Representation,
}

/* Marker_Attachment identifies one logical line or ephemeral display row. */
Marker_Attachment :: struct {
	kind:               Attachment_Kind,
	logical_line:       u64,
	display_row:        u32,
	buffer_revision:    u64,
	view_identity:      u64,
	view_generation:    u32,
	projection_generation: u64,
}

/* Marker is one borrowed immutable provider-generation contribution. */
Marker :: struct {
	id:             Marker_ID,
	provider:       Provider_ID,
	provider_generation: Provider_Generation,
	lane:           Lane_ID,
	attachment:     Marker_Attachment,
	style_role:     Semantic_Role,
	priority:       u16,
	representation: Representation,
	aggregation_label: string,
	detail:         string,
	actions:        [MAX_ACTIONS_PER_MARKER]Command_Reference,
	action_count:   u8,
	stale:          bool,
}

/* Lane_Content_Observation supplies the measured visible content width for geometry. */
Lane_Content_Observation :: struct {
	lane:          Lane_ID,
	content_cells: u16,
	present:       bool,
}

/* Lane_Geometry is one resolved lane allocation within one side. */
Lane_Geometry :: struct {
	lane:          Lane_ID,
	side:          Side,
	order:         i16,
	start_cell:    u16,
	width_cells:   u16,
	visible:       bool,
	style_role:    Semantic_Role,
}

/* Geometry is one deterministic allocation around the remaining text region. */
Geometry :: struct {
	available_cells: u32,
	left_cells:      u16,
	right_cells:     u16,
	text_cells:      u32,
	lanes:           [MAX_LANES]Lane_Geometry,
	lane_count:      u8,
}

/* Geometry_Request borrows one complete bounded lane and content observation set. */
Geometry_Request :: struct {
	available_cells: u32,
	minimum_text_cells: u32,
	lanes:           []Lane_Definition,
	content:         []Lane_Content_Observation,
	limits:          Limits,
}

/* Row_View owns offsets into one composed Gutter View text allocation. */
Row_View :: struct {
	viewport_row:   u32,
	logical_line:   u64,
	left_offset:    u32,
	left_bytes:     u16,
	left_cells:     u16,
	right_offset:   u32,
	right_bytes:    u16,
	right_cells:    u16,
	left_separator_bytes:  u8,
	right_separator_bytes: u8,
	left_role:      Semantic_Role,
	right_role:     Semantic_Role,
	current:        bool,
}

/* View owns one immutable composed Gutter generation until view_close. */
View :: struct {
	generation: Generation,
	geometry:   Geometry,
	text:       []u8,
	rows:       []Row_View,
	accounting: Accounting,
	allocator:  runtime.Allocator,
}

/* Limits bounds one Gutter request and retained view. */
Limits :: struct {
	lanes:                u8,
	lanes_per_side:       u8,
	visible_rows:         u16,
	row_text_bytes:       u16,
	view_text_bytes:      u32,
	representation_bytes: u16,
	marker_detail_bytes:  u32,
	actions_per_marker:   u8,
	markers_per_generation: u16,
	work:                 u32,
}

/* DEFAULT_LIMITS is the initial operating Gutter resource policy. */
DEFAULT_LIMITS :: Limits {
	lanes = MAX_LANES,
	lanes_per_side = MAX_LANES_PER_SIDE,
	visible_rows = MAX_VISIBLE_ROWS,
	row_text_bytes = MAX_ROW_TEXT_BYTES,
	view_text_bytes = MAX_VIEW_TEXT_BYTES,
	representation_bytes = MAX_REPRESENTATION_BYTES,
	marker_detail_bytes = MAX_MARKER_DETAIL_BYTES,
	actions_per_marker = MAX_ACTIONS_PER_MARKER,
	markers_per_generation = MAX_MARKERS_PER_GENERATION,
	work = MAX_COMPOSITION_WORK,
}

/* Accounting reports exact visible lanes, rows, text, work, and retained bytes. */
Accounting :: struct {
	visible_lanes: u8,
	visible_rows:  u16,
	text_bytes:    u32,
	work:          u32,
	retained_bytes: u64,
}

/* Operation identifies the rejected Gutter operation. */
Operation :: enum u8 {
	None,
	Validate,
	Compose_Geometry,
	Factory,
	Project,
	Publish,
	Copy,
	Prepare,
	Activate,
	Suspend,
	Remove,
	Inspect,
	Close,
}

/* Failure_Code classifies expected Gutter rejection. */
Failure_Code :: enum u16 {
	None,
	Invalid_Request,
	Invalid_Generation,
	Invalid_Lane,
	Duplicate_Lane,
	Ambiguous_Order,
	Lane_Limit,
	Side_Limit,
	Width_Insufficient,
	Text_Limit,
	Row_Limit,
	Work_Limit,
	Unsupported_Scope,
	Malformed_Text,
	Invalid_Marker,
	Duplicate_Marker,
	Marker_Limit,
	Collision_Limit,
	Stale_Generation,
	Incomplete_Generation,
	Cancelled,
	Duplicate_Provider,
	Provider_Limit,
	Provider_Suspended,
	Active_Turn,
	Allocation,
	Closed_View,
}

/* Failure_Context reports one bounded Gutter rejection without native pointers. */
Failure_Context :: struct {
	operation: Operation,
	code:      Failure_Code,
	lane:      Lane_ID,
	limit:     u64,
	actual:    u64,
}

/* limits_are_valid checks one complete selected resource policy. */
limits_are_valid :: proc(limits: Limits) -> bool {
	return limits.lanes > 0 && limits.lanes <= MAX_LANES &&
		limits.lanes_per_side > 0 && limits.lanes_per_side <= MAX_LANES_PER_SIDE &&
		limits.lanes_per_side <= limits.lanes &&
		limits.visible_rows > 0 && limits.visible_rows <= MAX_VISIBLE_ROWS &&
		limits.row_text_bytes > 0 && limits.row_text_bytes <= MAX_ROW_TEXT_BYTES &&
		limits.view_text_bytes > 0 && limits.view_text_bytes <= MAX_VIEW_TEXT_BYTES &&
		limits.representation_bytes > 0 &&
		limits.representation_bytes <= MAX_REPRESENTATION_BYTES &&
		limits.marker_detail_bytes > 0 &&
		limits.marker_detail_bytes <= MAX_MARKER_DETAIL_BYTES &&
		limits.actions_per_marker > 0 &&
		limits.actions_per_marker <= MAX_ACTIONS_PER_MARKER &&
		limits.markers_per_generation > 0 &&
		limits.markers_per_generation <= MAX_MARKERS_PER_GENERATION &&
		limits.work > 0
}

/* representation_is_valid checks bounded UTF-8 and fallback semantics. */
representation_is_valid :: proc(value: Representation, limit := MAX_REPRESENTATION_BYTES) -> bool {
	if value.kind == .Invalid || len(value.value) == 0 || len(value.value) > int(limit) ||
	   !utf8.valid_string(value.value) || len(value.fallback) > int(limit) ||
	   !utf8.valid_string(value.fallback) {
		return false
	}
	return value.kind == .Text || len(value.fallback) > 0
}

/* lane_definition_is_valid checks one complete provider-owned lane declaration. */
lane_definition_is_valid :: proc(lane: Lane_Definition, limits := DEFAULT_LIMITS) -> bool {
	if !limits_are_valid(limits) || lane.id == Lane_ID(0) || lane.provider == Provider_ID(0) ||
	   lane.provider_generation == Provider_Generation(0) || lane.side == .Invalid ||
	   lane.attachments == {} || lane.width_policy == .Invalid || lane.alignment == .Invalid ||
	   lane.visibility == .Invalid || lane.collision == .Invalid || lane.style_role == .Invalid ||
	   lane.minimum_cells == 0 || lane.minimum_cells > lane.maximum_cells ||
	   lane.maximum_cells > limits.row_text_bytes {
		return false
	}
	if lane.width_policy == .Fixed && lane.minimum_cells != lane.maximum_cells {
		return false
	}
	if lane.separator.kind != .Invalid &&
	   !representation_is_valid(lane.separator, int(limits.representation_bytes)) {
		return false
	}
	return true
}

/* numbering_mode_is_valid checks one complete factory numbering mode. */
numbering_mode_is_valid :: proc(mode: Numbering_Mode) -> bool {
	return mode >= .None && mode <= .Hybrid
}

/* numbering_scope_is_valid checks one declared numbering coordinate family. */
numbering_scope_is_valid :: proc(scope: Numbering_Scope) -> bool {
	return scope == .Logical || scope == .Visual
}

/* marker_attachment_is_valid checks one exact logical or display coordinate. */
marker_attachment_is_valid :: proc(attachment: Marker_Attachment) -> bool {
	switch attachment.kind {
	case .Logical_Line:
		return attachment.view_identity == 0 &&
			attachment.view_generation == 0 && attachment.projection_generation == 0
	case .Display_Row:
		return attachment.view_identity > 0 && attachment.view_generation > 0 &&
			attachment.projection_generation > 0
	}
	return false
}

/* marker_is_valid checks one complete bounded provider contribution. */
marker_is_valid :: proc(marker: Marker, limits := DEFAULT_LIMITS) -> bool {
	if !limits_are_valid(limits) || marker.id == 0 || marker.provider == 0 ||
	   marker.provider_generation == 0 || marker.lane == 0 ||
	   marker.style_role == .Invalid || !marker_attachment_is_valid(marker.attachment) ||
	   !representation_is_valid(marker.representation, int(limits.representation_bytes)) ||
	   marker.action_count > limits.actions_per_marker ||
	   len(marker.aggregation_label) > int(limits.representation_bytes) ||
	   len(marker.detail) > int(limits.marker_detail_bytes) ||
	   !utf8.valid_string(marker.aggregation_label) || !utf8.valid_string(marker.detail) {
		return false
	}
	for index in 0 ..< int(marker.action_count) {
		action := marker.actions[index]
		if action.registry_generation == 0 || action.entry_generation == 0 do return false
	}
	return true
}
