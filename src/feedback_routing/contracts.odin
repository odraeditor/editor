// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package feedback_routing owns deterministic declarative routing and bounded
// presentation projections for immutable semantic feedback records.
package feedback_routing

import "../feedback"
import "../ui"

/* MAX_ROUTES bounds one configuration route table. */
MAX_ROUTES :: 32
/* MAX_DESTINATIONS bounds one configuration destination table. */
MAX_DESTINATIONS :: 16
/* MAX_PROJECTIONS bounds one configuration projection table. */
MAX_PROJECTIONS :: 16
/* MAX_ROUTE_DESTINATIONS bounds destinations contributed by one route. */
MAX_ROUTE_DESTINATIONS :: 4
/* MAX_RESOLVED_DESTINATIONS bounds deduplicated destinations per record. */
MAX_RESOLVED_DESTINATIONS :: 4
/* MAX_FALLBACK_DEPTH bounds deterministic fallback traversal. */
MAX_FALLBACK_DEPTH :: 4
/* MAX_NAME_BYTES bounds copied routing identities. */
MAX_NAME_BYTES :: 96
/* MAX_PROJECTION_BYTES bounds one projected presentation payload. */
MAX_PROJECTION_BYTES :: 1_024
/* MIN_PROJECTION_BYTES is the smallest admitted projection budget. */
MIN_PROJECTION_BYTES :: 32
/* MAX_PRESENTED_ITEMS bounds one frontend presentation cache. */
MAX_PRESENTED_ITEMS :: 64

/* Routing_Registry_ID identifies one routing registry. */
Routing_Registry_ID :: distinct u64
/* Routing_Registry_Generation identifies registry state replacement. */
Routing_Registry_Generation :: distinct u64
/* Configuration_Generation identifies one complete route configuration. */
Configuration_Generation :: distinct u64
/* Route_ID identifies one declarative route. */
Route_ID :: distinct u64
/* Route_Generation identifies one route revision. */
Route_Generation :: distinct u64
/* Destination_ID identifies one presentation destination. */
Destination_ID :: distinct u64
/* Destination_Generation identifies one destination revision. */
Destination_Generation :: distinct u64
/* Projection_ID identifies one semantic projection. */
Projection_ID :: distinct u64
/* Projection_Generation identifies one projection revision. */
Projection_Generation :: distinct u64

/* Text is one fixed copied routing identity. */
Text :: struct {
	bytes:      [MAX_NAME_BYTES]u8,
	byte_count: u8,
}

/* Policy_Layer defines protected-to-personal deterministic precedence. */
Policy_Layer :: enum u8 {
	Invalid,
	Safety,
	Factory,
	Package,
	User,
}

/* Route_Resolution controls evaluation after one matcher succeeds. */
Route_Resolution :: enum u8 {
	Invalid,
	Continue,
	Terminal,
	Suppress_Visible,
}

/* Destination_Kind selects one frontend-independent UI composition family. */
Destination_Kind :: enum u8 {
	Invalid,
	Status,
	Floating,
	Anchored_Detail,
	History,
	Diagnostic,
}

/* Focus_Policy describes destination focus behavior without changing registry state. */
Focus_Policy :: enum u8 {
	Invalid,
	Preserve,
	Transfer,
	None,
}

/* Dismissal_Cause names presentation-only lifecycle evidence. */
Dismissal_Cause :: enum u8 {
	Invalid,
	Explicit,
	Expiry,
	Replacement,
	Source_Closure,
	Frontend_Loss,
}

/* Dismissal_Policy is the bounded set of destination-owned dismissal causes. */
Dismissal_Policy :: bit_set[Dismissal_Cause; u8]

/* Content_Extent classifies bounded record content without matching raw text. */
Content_Extent :: enum u8 {
	Invalid,
	Compact,
	Expanded,
}

/* Matcher is one typed conjunctive feedback predicate. */
Matcher :: struct {
	match_class:      bool,
	class:            feedback.Semantic_Class,
	match_severity:   bool,
	severity:         feedback.Severity,
	match_source:     bool,
	source:           feedback.Source_ID,
	match_lifecycle:  bool,
	lifecycle:        feedback.Lifecycle_Policy,
	match_progress:   bool,
	progress:         feedback.Progress_State,
	match_attention:  bool,
	attention:        feedback.Attention,
	match_retention:  bool,
	retention:        feedback.Retention_Policy,
	match_actions:    bool,
	has_actions:      bool,
	match_extent:     bool,
	extent:           Content_Extent,
}

/* Route is one fixed copied declarative routing rule. */
Route :: struct {
	id:                Route_ID,
	generation:        Route_Generation,
	name:              Text,
	layer:             Policy_Layer,
	order:             i16,
	protected:         bool,
	enabled:           bool,
	matcher:           Matcher,
	resolution:        Route_Resolution,
	destinations:      [MAX_ROUTE_DESTINATIONS]Destination_ID,
	destination_count: u8,
}

/* Destination declares one bounded UI composition and fallback. */
Destination :: struct {
	id:                    Destination_ID,
	generation:            Destination_Generation,
	name:                  Text,
	kind:                  Destination_Kind,
	projection:            Projection_ID,
	fallback:              Destination_ID,
	required_capabilities: ui.Renderer_Capabilities,
	minimum_rows:          u16,
	minimum_columns:       u16,
	capacity:              u16,
	content_bytes:         u16,
	focus:                 Focus_Policy,
	dismissal:             Dismissal_Policy,
	profile:               ui.Presentation_Profile_Handle,
	inspectable:           bool,
}

/* Projection_Definition selects bounded semantic fields and style roles. */
Projection_Definition :: struct {
	id:                   Projection_ID,
	generation:           Projection_Generation,
	name:                 Text,
	maximum_bytes:        u16,
	include_title:        bool,
	include_message:      bool,
	include_progress:     bool,
	include_actions:      bool,
	include_source:       bool,
	textual_severity:     bool,
	information_role:     ui.Style_Role,
	warning_role:         ui.Style_Role,
	error_role:           ui.Style_Role,
	attention_role:       ui.Style_Role,
	progress_role:        ui.Style_Role,
}

/* Configuration_Proposal contains one complete copied route generation. */
Configuration_Proposal :: struct {
	generation:        Configuration_Generation,
	routes:            [MAX_ROUTES]Route,
	route_count:       u8,
	destinations:      [MAX_DESTINATIONS]Destination,
	destination_count: u8,
	projections:       [MAX_PROJECTIONS]Projection_Definition,
	projection_count:  u8,
}

/* Frontend_Context supplies checked capability and geometry observations. */
Frontend_Context :: struct {
	profile:              ui.Renderer_Profile_ID,
	capabilities:         ui.Renderer_Capabilities,
	color:                ui.Renderer_Color_Capability,
	rows:                 u32,
	columns:              u32,
	status_available:     bool,
	overlap_available:    bool,
	surface_available:    bool,
	diagnostic_available: bool,
}

/* Destination_Resolution records requested and fallback-selected identity. */
Destination_Resolution :: struct {
	requested:      Destination_ID,
	selected:       Destination_ID,
	fallback_depth: u8,
	degraded:       bool,
}

/* Resolution is one deterministic route result for an immutable record. */
Resolution :: struct {
	record_id:         feedback.Record_ID,
	record_generation: feedback.Record_Generation,
	configuration:     Configuration_Generation,
	destinations:      [MAX_RESOLVED_DESTINATIONS]Destination_Resolution,
	destination_count: u8,
	matched_routes:    [MAX_ROUTES]Route_ID,
	matched_count:     u8,
	evaluated_routes:  u8,
	suppressed:        bool,
}

/* Projection owns one fixed frontend-independent destination representation. */
Projection :: struct {
	record_id:              feedback.Record_ID,
	record_generation:      feedback.Record_Generation,
	destination:            Destination_ID,
	destination_generation: Destination_Generation,
	projection:             Projection_ID,
	projection_generation:  Projection_Generation,
	profile:                ui.Presentation_Profile_Handle,
	style_role:             ui.Style_Role,
	focus:                  Focus_Policy,
	dismissal:              Dismissal_Policy,
	capacity:               u16,
	severity:               feedback.Severity,
	attention:              feedback.Attention,
	content:                [MAX_PROJECTION_BYTES]u8,
	content_bytes:          u16,
	action_count:           u8,
	truncated:              bool,
	degraded:               bool,
}

/* Routed_Presentation combines one resolution with bounded destination projections. */
Routed_Presentation :: struct {
	resolution:       Resolution,
	projections:      [MAX_RESOLVED_DESTINATIONS]Projection,
	projection_count: u8,
}

/* Presentation_Cache retains one bounded last-visible generation per destination. */
Presentation_Cache :: struct {
	generation: u64,
	items:      [MAX_PRESENTED_ITEMS]Projection,
	item_count: u8,
}

/* Routing_Stats reports exact configuration occupancy and generation. */
Routing_Stats :: struct {
	registry_id:         Routing_Registry_ID,
	registry_generation: Routing_Registry_Generation,
	configuration:       Configuration_Generation,
	routes:              u8,
	destinations:        u8,
	projections:         u8,
	retained_bytes:      u64,
}

/* Operation identifies one checked routing action. */
Operation :: enum u8 {
	Invalid,
	Initialize,
	Reload,
	Resolve,
	Project,
	Inspect,
	Close,
}

/* Failure_Code classifies expected routing rejection. */
Failure_Code :: enum u16 {
	None,
	Invalid_Registry,
	Invalid_Identity,
	Invalid_Generation,
	Stale_Generation,
	Route_Limit,
	Destination_Limit,
	Projection_Limit,
	Invalid_Route,
	Invalid_Matcher,
	Invalid_Destination,
	Invalid_Projection,
	Invalid_Order,
	Duplicate_Identity,
	Missing_Destination,
	Missing_Projection,
	Invalid_Fallback,
	Fallback_Cycle,
	Fallback_Depth,
	Missing_Safety_Route,
	Protected_Route,
	No_Route,
	Unavailable_Destination,
	Projection_Overflow,
	Presentation_Limit,
	Dismissal_Rejected,
	Allocation,
}

/* Failure identifies one rejected routing operation and exact owner. */
Failure :: struct {
	operation:   Operation,
	code:        Failure_Code,
	route:       Route_ID,
	destination: Destination_ID,
	projection:  Projection_ID,
	limit:       u64,
	actual:      u64,
}

/* Routing_Inspection copies the active last-valid configuration and rejection. */
Routing_Inspection :: struct {
	stats:          Routing_Stats,
	configuration:  Configuration_Proposal,
	last_rejection: Failure,
}

/* Registry is an opaque owner of one last-valid routing configuration. */
Registry :: struct {
	state:  rawptr,
	closed: bool,
}

/* text_copy validates and copies one routing identity. */
text_copy :: proc(value: string) -> (text: Text, ok: bool) {
	if len(value) == 0 || len(value) > MAX_NAME_BYTES || !feedback.content_is_safe(value, MAX_NAME_BYTES) {
		return {}, false
	}
	text.byte_count = u8(copy(text.bytes[:], transmute([]u8)value))
	return text, true
}

/* text_view borrows the populated bytes of one copied identity. */
text_view :: proc(value: ^Text) -> string {
	if value == nil || value.byte_count == 0 || int(value.byte_count) > len(value.bytes) do return ""
	return string(value.bytes[:value.byte_count])
}

/* projection_content borrows the populated bytes of one projection. */
projection_content :: proc(projection: ^Projection) -> string {
	if projection == nil || int(projection.content_bytes) > len(projection.content) do return ""
	return string(projection.content[:projection.content_bytes])
}
