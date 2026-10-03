// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package status_bar owns bounded pane-local Status Bar observations and composition.
package status_bar

import "../display"
import "base:runtime"

/* MAX_SEGMENTS bounds factory and contributed segments in one Status Bar generation. */
MAX_SEGMENTS :: 32
/* MAX_SEGMENT_TEXT_BYTES bounds one full, compact, or inspection value. */
MAX_SEGMENT_TEXT_BYTES :: 4 * 1_024
/* MAX_VIEW_TEXT_BYTES bounds one composed UTF-8 Status Bar value. */
MAX_VIEW_TEXT_BYTES :: 16 * 1_024
/* MAX_STYLE_SPANS bounds semantic style runs in one composed Status Bar. */
MAX_STYLE_SPANS :: 64
/* MIN_REQUIRED_CELLS is the smallest width that can retain factory safety, identity, and position. */
MIN_REQUIRED_CELLS :: 10
/* MAX_CONTEXT_LABEL_BYTES bounds copied encoding, language, Project, and Workspace labels. */
MAX_CONTEXT_LABEL_BYTES :: 1_024
/* MAX_CONTEXT_DIAGNOSTIC_BYTES bounds one copied retained alert diagnostic. */
MAX_CONTEXT_DIAGNOSTIC_BYTES :: MAX_SEGMENT_TEXT_BYTES

/* Segment_ID identifies one stable semantic segment; zero is invalid. */
Segment_ID :: distinct u64
/* Generation identifies one immutable observation and presentation generation; zero is invalid. */
Generation :: distinct u64

/* Group selects the stable left or right Status Bar composition group. */
Group :: enum u8 {
	Invalid,
	Left,
	Right,
}

/* Segment_Kind identifies the factory meaning of one segment without owning its source state. */
Segment_Kind :: enum u8 {
	Invalid,
	Alert,
	Encoding,
	Client,
	Buffer_State,
	Remote,
	Pane_State,
	Frontend,
	Buffer_Identity,
	Position,
	Workspace,
	Project,
	Version_Control,
	Editing_Context,
	Miscellaneous,
}

/* Semantic_Role selects theme-owned presentation meaning without carrying palette values. */
Semantic_Role :: enum u8 {
	Invalid,
	Ordinary,
	Safety,
	Buffer_Identity,
	Position,
	Alert,
	Context,
	Workspace,
	Project,
	Editing_Context,
	Disabled,
}

/* Command_Reference identifies one registered semantic command without a callback. */
Command_Reference :: struct {
	registry_generation: u64,
	slot:                u16,
	entry_generation:    u32,
}

/* Position_Presentation selects one admitted factory position representation. */
Position_Presentation :: enum u8 {
	Invalid,
	Line_Column_Percentage,
	Line_Column,
	Byte_Offset,
}

/* Compact_Policy selects deterministic factory degradation behavior. */
Compact_Policy :: enum u8 {
	Invalid,
	Automatic,
	Prefer_Compact,
	Essential_Only,
}

/* Optional_Segment identifies one configurable non-required factory segment. */
Optional_Segment :: enum u8 {
	Encoding,
	Pane_State,
	Workspace,
	Project,
	Editing_Context,
}

/* Optional_Segments records the visible configurable factory segments. */
Optional_Segments :: bit_set[Optional_Segment; u8]

/* Factory_Policy is one complete copied presentation policy. */
Factory_Policy :: struct {
	configured: bool,
	position:   Position_Presentation,
	visible:    Optional_Segments,
	compact:    Compact_Policy,
}

/* Factory_Actions copies admitted command identities for factory-owned segments. */
Factory_Actions :: struct {
	alert:                    Command_Reference,
	buffer_identity:          Command_Reference,
	project:                  Command_Reference,
	project_inspection:       Command_Reference,
	workspace:                Command_Reference,
	editing_context:          Command_Reference,
	editing_context_secondary: Command_Reference,
}

/* DEFAULT_FACTORY_POLICY preserves the complete factory presentation. */
DEFAULT_FACTORY_POLICY :: Factory_Policy {
	configured = true,
	position = .Line_Column_Percentage,
	visible = {.Encoding, .Pane_State, .Workspace, .Project, .Editing_Context},
	compact = .Automatic,
}

/* Segment_Definition is one borrowed bounded input to Status Bar composition. */
Segment_Definition :: struct {
	id:                Segment_ID,
	kind:              Segment_Kind,
	group:             Group,
	priority:          u16,
	full_text:         string,
	compact_text:      string,
	required:          bool,
	omittable:         bool,
	truncatable:       bool,
	style_role:        Semantic_Role,
	inspection_text:   string,
	primary_command:   Command_Reference,
	secondary_command: Command_Reference,
}

/* Segment_View identifies one visible semantic range in a composed Status Bar view. */
Segment_View :: struct {
	id:                Segment_ID,
	kind:              Segment_Kind,
	group:             Group,
	style_role:        Semantic_Role,
	start_byte:        u32,
	end_byte:          u32,
	start_cell:        u32,
	end_cell:          u32,
	compact:           bool,
	truncated:         bool,
	inspection_text:   string,
	primary_command:   Command_Reference,
	secondary_command: Command_Reference,
}

/* Limits bounds one Status Bar composition request and retained view. */
Limits :: struct {
	segments:           u16,
	segment_text_bytes: u32,
	view_text_bytes:    u32,
	style_spans:        u16,
	work:               u32,
}

/* DEFAULT_LIMITS is the initial resource policy selected by the reference study. */
DEFAULT_LIMITS :: Limits {
	segments = MAX_SEGMENTS,
	segment_text_bytes = MAX_SEGMENT_TEXT_BYTES,
	view_text_bytes = MAX_VIEW_TEXT_BYTES,
	style_spans = MAX_STYLE_SPANS,
	work = MAX_SEGMENTS * MAX_SEGMENTS,
}

/* Accounting reports exact retained text, visible segments, and composition work. */
Accounting :: struct {
	text_bytes:       u32,
	text_cells:       u32,
	visible_segments: u16,
	work:             u32,
	retained_bytes:   u64,
}

/* View owns one immutable composed Status Bar generation until view_close. */
View :: struct {
	generation:      Generation,
	width_cells:     u32,
	text:            []u8,
	inspection_text: []u8,
	segments:        []Segment_View,
	accounting:      Accounting,
	allocator:       runtime.Allocator,
}

/* Composition_Request describes one complete borrowed Status Bar generation. */
Composition_Request :: struct {
	generation:  Generation,
	width_cells: u32,
	segments:    []Segment_Definition,
	profile:     display.Unicode_Profile,
	allocator:   runtime.Allocator,
	limits:      Limits,
}

/* Buffer_Observation copies factory buffer and pane position facts for one exact revision. */
Buffer_Observation :: struct {
	generation:    Generation,
	identity:      u64,
	revision:      u64,
	label:         string,
	context_label: string,
	writable:      bool,
	modified:      bool,
	point_offset:  u64,
	text_bytes:    u64,
	line:          u64,
	line_count:    u64,
	column:        u32,
}

/* Source_Stamp binds one copied contextual fact to its pane, buffer, owner, and presentation generation. */
Source_Stamp :: struct {
	presentation:    Generation,
	buffer_identity: u64,
	buffer_revision: u64,
	pane_identity:   u64,
	pane_generation: u64,
	owner_identity:  u64,
	owner_generation: u64,
}

/* Alert_Severity classifies retained pane-local attention without copying transient command feedback. */
Alert_Severity :: enum u8 {
	Invalid,
	Information,
	Warning,
	Error,
}

/* Language_Service_Health copies the bounded lifecycle state of an associated language service. */
Language_Service_Health :: enum u8 {
	None,
	Initializing,
	Active,
	Failed,
	Stopped,
}

/* Language_Operation_Health copies compact shared-operation health. */
Language_Operation_Health :: enum u8 {
	None,
	Busy,
	Failed,
}

/* Pane_Policy copies only exceptional pane-local policy that merits Status Bar presentation. */
Pane_Policy :: enum u8 {
	Ordinary,
	Soft_Dedicated,
	Hard_Dedicated,
	Read_Only,
}

/* Context_Label owns one bounded copied contextual display value. */
Context_Label :: struct {
	bytes:  [MAX_CONTEXT_LABEL_BYTES]u8,
	length: u32,
}

/* Context_Diagnostic owns one bounded copied retained alert explanation. */
Context_Diagnostic :: struct {
	bytes:  [MAX_CONTEXT_DIAGNOSTIC_BYTES]u8,
	length: u32,
}

/* Document_Context copies available document encoding state from the document owner. */
Document_Context :: struct {
	present:  bool,
	stamp:    Source_Stamp,
	encoding: Context_Label,
}

/* Alert_Context copies one retained bounded exceptional condition from its canonical owner. */
Alert_Context :: struct {
	present:    bool,
	stamp:      Source_Stamp,
	severity:   Alert_Severity,
	diagnostic: Context_Diagnostic,
}

/* Diagnostic_Context copies current exact-revision diagnostic totals. */
Diagnostic_Context :: struct {
	present:  bool,
	stamp:    Source_Stamp,
	errors:   u32,
	warnings: u32,
}

/* Language_Context copies language identity and associated service health. */
Language_Context :: struct {
	present:        bool,
	stamp:          Source_Stamp,
	name:           Context_Label,
	service_health: Language_Service_Health,
	operation_health: Language_Operation_Health,
}

/* Named_Context copies a bounded Project or Workspace display identity. */
Named_Context :: struct {
	present: bool,
	stamp:   Source_Stamp,
	name:    Context_Label,
}

/* Pane_Context copies exceptional policy for one exact pane generation. */
Pane_Context :: struct {
	present: bool,
	stamp:   Source_Stamp,
	policy:  Pane_Policy,
}

/* Interaction_Context copies the selected session profile and persistent state. */
Interaction_Context :: struct {
	present: bool,
	stamp:   Source_Stamp,
	profile: Context_Label,
	state:   Context_Label,
	modal:   bool,
}

/* Context_Observation is one coherent copied contextual input for a factory generation. */
Context_Observation :: struct {
	generation:      Generation,
	buffer_identity: u64,
	buffer_revision: u64,
	pane_identity:   u64,
	pane_generation: u64,
	document:        Document_Context,
	alert:           Alert_Context,
	diagnostics:     Diagnostic_Context,
	language:        Language_Context,
	interaction:     Interaction_Context,
	project:         Named_Context,
	workspace:       Named_Context,
	pane:            Pane_Context,
}

/* Factory_Request describes one core factory Status Bar composition. */
Factory_Request :: struct {
	generation:  Generation,
	width_cells: u32,
	buffer:      Buffer_Observation,
	contextual:  Context_Observation,
	programmable: []Segment_Definition,
	policy:      Factory_Policy,
	actions:     Factory_Actions,
	profile:     display.Unicode_Profile,
	allocator:   runtime.Allocator,
	limits:      Limits,
}

/* factory_policy_is_valid validates one complete admitted presentation policy. */
factory_policy_is_valid :: proc(policy: Factory_Policy) -> bool {
	return policy.configured && policy.position != .Invalid && policy.compact != .Invalid
}

/* Operation identifies the Status Bar action that rejected input. */
Operation :: enum u8 {
	Invalid,
	Validate,
	Compose,
	Factory,
	Close,
}

/* Failure_Code classifies expected Status Bar rejection. */
Failure_Code :: enum u8 {
	None,
	Invalid_Request,
	Invalid_Generation,
	Invalid_Segment,
	Segment_Limit,
	Text_Limit,
	Width_Insufficient,
	Work_Limit,
	Allocation,
	Closed_View,
}

/* Failure_Context reports one rejected Status Bar operation and violated bound. */
Failure_Context :: struct {
	operation: Operation,
	code:      Failure_Code,
	segment:   Segment_ID,
	limit:     u64,
	actual:    u64,
}

/* limits_are_valid checks one complete Status Bar resource policy. */
limits_are_valid :: proc(limits: Limits) -> bool {
	return limits.segments > 0 && limits.segments <= MAX_SEGMENTS &&
	       limits.segment_text_bytes > 0 && limits.segment_text_bytes <= MAX_SEGMENT_TEXT_BYTES &&
	       limits.view_text_bytes > 0 && limits.view_text_bytes <= MAX_VIEW_TEXT_BYTES &&
	       limits.style_spans > 0 && limits.style_spans <= MAX_STYLE_SPANS &&
	       limits.work >= u32(limits.segments) && limits.work <= MAX_SEGMENTS * MAX_SEGMENTS
}
