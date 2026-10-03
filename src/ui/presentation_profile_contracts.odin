// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

/* MAX_PRESENTATION_PROFILES bounds all confirmed profiles in one registry. */
MAX_PRESENTATION_PROFILES :: 16
/* MAX_PRESENTATION_PROFILE_MAPPINGS bounds semantic chrome slots per profile. */
MAX_PRESENTATION_PROFILE_MAPPINGS :: 16
/* MAX_PRESENTATION_PROFILE_TEXT_BYTES bounds copied identity and provenance text. */
MAX_PRESENTATION_PROFILE_TEXT_BYTES :: 96
/* MAX_PRESENTATION_PROFILE_FALLBACK_DEPTH bounds deterministic fallback traversal. */
MAX_PRESENTATION_PROFILE_FALLBACK_DEPTH :: 4
/* MAX_PRESENTATION_PROFILE_INSET_CELLS bounds each logical margin or padding axis. */
MAX_PRESENTATION_PROFILE_INSET_CELLS :: 8
/* PRESENTATION_PROFILE_ROLE_COUNT is the accepted current consumer-role count. */
PRESENTATION_PROFILE_ROLE_COUNT :: 2
/* PRESENTATION_CHROME_SLOT_COUNT is the complete shared chrome-slot vocabulary. */
PRESENTATION_CHROME_SLOT_COUNT :: 11

/* Presentation_Profile_Registry_ID identifies one registry lifetime; zero is invalid. */
Presentation_Profile_Registry_ID :: distinct u64
/* Presentation_Profile_Registry_Generation identifies one exact registry snapshot. */
Presentation_Profile_Registry_Generation :: distinct u64
/* Presentation_Profile_ID identifies one profile for the registry lifetime. */
Presentation_Profile_ID :: distinct u64
/* Presentation_Profile_Generation identifies one exact immutable profile definition. */
Presentation_Profile_Generation :: distinct u64

/* Presentation_Profile_Role identifies one semantic profile-selection boundary. */
Presentation_Profile_Role :: enum u8 {
	Invalid,
	Contextual_Information,
	Interactive_Candidates,
}

/* Presentation_Profile_Kind records maintained or future extension provenance. */
Presentation_Profile_Kind :: enum u8 {
	Invalid,
	Factory,
	Package,
	Personal,
}

/* Presentation_Chrome_Slot identifies one shared semantic chrome mapping. */
Presentation_Chrome_Slot :: enum u8 {
	Invalid,
	Background,
	Border,
	Title,
	Content,
	Selection,
	Annotation,
	Separator,
	Action,
	Progress,
	Unavailable,
	Attention,
}

/* Presentation_Chrome_Slots is one bounded required-slot set. */
Presentation_Chrome_Slots :: bit_set[Presentation_Chrome_Slot; u16]

/* Presentation_Profile_Border declares frontend-independent border intent. */
Presentation_Profile_Border :: enum u8 {
	Invalid,
	None,
	Single,
}

/* Presentation_Profile_Degradation declares the first unsupported-capability response. */
Presentation_Profile_Degradation :: enum u8 {
	Invalid,
	Reject,
	Portable_Border,
	Separator,
	Compact_Feedback,
}

/* Presentation_Profile_Operation identifies one checked registry action. */
Presentation_Profile_Operation :: enum u8 {
	Invalid,
	Initialize,
	Inspect,
	Register,
	Select,
	Replace,
	Restore,
	Disable,
	Teardown,
}

/* Presentation_Profile_Failure_Code classifies expected profile rejection. */
Presentation_Profile_Failure_Code :: enum u16 {
	None,
	Invalid_Registry,
	Closed_Registry,
	Invalid_Identity,
	Invalid_Role,
	Invalid_Profile,
	Invalid_Kind,
	Invalid_Mapping,
	Missing_Required_Slot,
	Duplicate_Slot,
	Duplicate_Profile,
	Profile_Limit,
	Mapping_Limit,
	Text_Limit,
	Inset_Limit,
	Invalid_Dimensions,
	Invalid_Fallback,
	Fallback_Cycle,
	Fallback_Depth,
	Renderer_Incompatible,
	Stale_Scope,
	Stale_Profile,
	Generation_Limit,
	Protected_Role,
	Allocation,
}

/* Presentation_Profile_Text is one fixed copied identity or provenance value. */
Presentation_Profile_Text :: struct {
	bytes:      [MAX_PRESENTATION_PROFILE_TEXT_BYTES]u8,
	byte_count: u8,
}

/* Presentation_Profile_Handle is one checked pointer-free profile identity. */
Presentation_Profile_Handle :: struct {
	registry_id:        Presentation_Profile_Registry_ID,
	role:               Presentation_Profile_Role,
	profile_id:         Presentation_Profile_ID,
	profile_generation: Presentation_Profile_Generation,
}

/* Presentation_Profile_Mapping maps one shared slot to one semantic style role. */
Presentation_Profile_Mapping :: struct {
	slot:       Presentation_Chrome_Slot,
	style_role: Style_Role,
}

/* Presentation_Profile_Definition is one complete fixed copied profile proposal. */
Presentation_Profile_Definition :: struct {
	name:                  Presentation_Profile_Text,
	source:                Presentation_Profile_Text,
	kind:                  Presentation_Profile_Kind,
	role:                  Presentation_Profile_Role,
	mappings:              [MAX_PRESENTATION_PROFILE_MAPPINGS]Presentation_Profile_Mapping,
	mapping_count:          u8,
	margin_rows:           u8,
	margin_columns:        u8,
	padding_rows:          u8,
	padding_columns:       u8,
	border:                Presentation_Profile_Border,
	bounds:                Popup_Dimension_Bounds,
	clipping:              Popup_Clipping_Policy,
	popup_fallback:        Popup_Fallback_Policy,
	degradation:           Presentation_Profile_Degradation,
	required_capabilities: Renderer_Capabilities,
	fallback:              Presentation_Profile_Handle,
	configurable:          bool,
}

/* Presentation_Profile_Record copies one exact confirmed profile generation. */
Presentation_Profile_Record :: struct {
	handle:     Presentation_Profile_Handle,
	definition: Presentation_Profile_Definition,
}

/* Presentation_Profile_Scope observes one exact role selection generation. */
Presentation_Profile_Scope :: struct {
	registry_id:        Presentation_Profile_Registry_ID,
	registry_generation: Presentation_Profile_Registry_Generation,
	role:               Presentation_Profile_Role,
	selected:           Presentation_Profile_Handle,
	factory:            Presentation_Profile_Handle,
}

/* Presentation_Profile_Selection copies one checked requested and resolved outcome. */
Presentation_Profile_Selection :: struct {
	scope:             Presentation_Profile_Scope,
	previous:          Presentation_Profile_Handle,
	requested:         Presentation_Profile_Handle,
	selected:          Presentation_Profile_Handle,
	changed:           bool,
	fallback_selected: bool,
	fallback_depth:    u8,
}

/* Presentation_Profile_Limits contains one explicit registry resource policy. */
Presentation_Profile_Limits :: struct {
	profiles:       u16,
	mappings:       u16,
	text_bytes:     u64,
	fallback_depth: u8,
	inset_cells:    u8,
}

/* DEFAULT_PRESENTATION_PROFILE_LIMITS is the initial bounded registry policy. */
DEFAULT_PRESENTATION_PROFILE_LIMITS :: Presentation_Profile_Limits {
	profiles = MAX_PRESENTATION_PROFILES,
	mappings = MAX_PRESENTATION_PROFILE_MAPPINGS,
	text_bytes = MAX_PRESENTATION_PROFILE_TEXT_BYTES,
	fallback_depth = MAX_PRESENTATION_PROFILE_FALLBACK_DEPTH,
	inset_cells = MAX_PRESENTATION_PROFILE_INSET_CELLS,
}

/* Presentation_Profile_Stats reports exact registry occupancy and generation. */
Presentation_Profile_Stats :: struct {
	registry_id:         Presentation_Profile_Registry_ID,
	registry_generation: Presentation_Profile_Registry_Generation,
	live_profiles:       u16,
	factory_profiles:    u16,
	package_profiles:    u16,
	personal_profiles:   u16,
	retained_bytes:      u64,
}

/* Presentation_Profile_Failure reports one rejected profile operation. */
Presentation_Profile_Failure :: struct {
	operation:      Presentation_Profile_Operation,
	code:           Presentation_Profile_Failure_Code,
	role:           Presentation_Profile_Role,
	profile:        Presentation_Profile_Handle,
	slot:           Presentation_Chrome_Slot,
	limit:          u64,
	actual:         u64,
	fallback_depth: u8,
}

/* Presentation_Profile_Inspection is one immutable copied registry snapshot. */
Presentation_Profile_Inspection :: struct {
	stats:          Presentation_Profile_Stats,
	scopes:         [PRESENTATION_PROFILE_ROLE_COUNT]Presentation_Profile_Scope,
	profiles:       [MAX_PRESENTATION_PROFILES]Presentation_Profile_Record,
	profile_count:  u16,
	last_rejection: Presentation_Profile_Failure,
}

/* Presentation_Profile_Registry owns bounded profile definitions and selections. */
Presentation_Profile_Registry :: struct {
	state:  rawptr,
	closed: bool,
}

/* presentation_profile_text copies one valid bounded UTF-8 text value. */
presentation_profile_text :: proc(value: string) -> (text: Presentation_Profile_Text, ok: bool) {
	if len(value) == 0 || len(value) > MAX_PRESENTATION_PROFILE_TEXT_BYTES {
		return {}, false
	}
	text.byte_count = u8(copy(text.bytes[:], transmute([]u8)value))
	return text, true
}

/* presentation_profile_text_view borrows the populated bytes of one copied value. */
presentation_profile_text_view :: proc(text: ^Presentation_Profile_Text) -> string {
	if text == nil || text.byte_count == 0 || int(text.byte_count) > len(text.bytes) {
		return ""
	}
	return string(text.bytes[:text.byte_count])
}

/* presentation_profile_required_slots returns the mandatory mappings for one role. */
presentation_profile_required_slots :: proc(role: Presentation_Profile_Role) -> Presentation_Chrome_Slots {
	switch role {
	case .Contextual_Information:
		return {.Background, .Border, .Content, .Unavailable, .Attention}
	case .Interactive_Candidates:
		return {
			.Background,
			.Border,
			.Content,
			.Selection,
			.Annotation,
			.Unavailable,
			.Attention,
		}
	case .Invalid:
		return {}
	}
	return {}
}

/* presentation_profile_definition_style resolves one exact semantic chrome slot. */
presentation_profile_definition_style :: proc(
	definition: ^Presentation_Profile_Definition,
	slot: Presentation_Chrome_Slot,
) -> (role: Style_Role, ok: bool) {
	if definition == nil || slot == .Invalid {
		return {}, false
	}
	for mapping in definition.mappings[:definition.mapping_count] {
		if mapping.slot == slot {
			return mapping.style_role, true
		}
	}
	return {}, false
}

/* presentation_profile_record_is_valid checks one complete copied generation. */
presentation_profile_record_is_valid :: proc(record: Presentation_Profile_Record) -> bool {
	definition := record.definition
	return record.handle.registry_id != Presentation_Profile_Registry_ID(0) &&
		record.handle.profile_id != Presentation_Profile_ID(0) &&
		record.handle.profile_generation != Presentation_Profile_Generation(0) &&
		record.handle.role == record.definition.role &&
		presentation_profile_definition_shape_failure(&definition).code == .None
}

/* presentation_profile_matches_popup checks profile-owned popup policy fields. */
presentation_profile_matches_popup :: proc(
	record: Presentation_Profile_Record,
	descriptor: Popup_Descriptor,
) -> bool {
	definition := record.definition
	expected_role := Presentation_Profile_Role.Contextual_Information
	if descriptor.behavior == .Interactive do expected_role = .Interactive_Candidates
	return presentation_profile_record_is_valid(record) &&
		definition.role == expected_role &&
		descriptor.bounds == definition.bounds &&
		descriptor.margin_rows == definition.margin_rows &&
		descriptor.margin_columns == definition.margin_columns &&
		descriptor.padding_rows == definition.padding_rows &&
		descriptor.padding_columns == definition.padding_columns &&
		descriptor.border == (definition.border == .Single) &&
		descriptor.clipping == definition.clipping &&
		descriptor.fallback == definition.popup_fallback
}

@(private)
presentation_profile_role_is_valid :: proc(role: Presentation_Profile_Role) -> bool {
	return role > .Invalid && int(role) <= PRESENTATION_PROFILE_ROLE_COUNT
}

@(private)
presentation_profile_kind_is_valid :: proc(kind: Presentation_Profile_Kind) -> bool {
	return kind > .Invalid && kind <= .Personal
}

@(private)
presentation_profile_limits_are_valid :: proc(limits: Presentation_Profile_Limits) -> bool {
	return limits.profiles > 0 && limits.profiles <= MAX_PRESENTATION_PROFILES &&
	       limits.mappings > 0 && limits.mappings <= MAX_PRESENTATION_PROFILE_MAPPINGS &&
	       limits.text_bytes > 0 && limits.text_bytes <= MAX_PRESENTATION_PROFILE_TEXT_BYTES &&
	       limits.fallback_depth > 0 &&
	       limits.fallback_depth <= MAX_PRESENTATION_PROFILE_FALLBACK_DEPTH &&
	       limits.inset_cells > 0 && limits.inset_cells <= MAX_PRESENTATION_PROFILE_INSET_CELLS
}

@(private)
presentation_profile_bounds_are_valid :: proc(bounds: Popup_Dimension_Bounds) -> bool {
	return bounds.minimum_rows > 0 && bounds.minimum_columns > 0 &&
	       bounds.preferred_rows >= bounds.minimum_rows &&
	       bounds.preferred_columns >= bounds.minimum_columns &&
	       bounds.maximum_rows >= bounds.preferred_rows &&
	       bounds.maximum_columns >= bounds.preferred_columns
}

@(private)
presentation_profile_definition_shape_failure :: proc(
	definition: ^Presentation_Profile_Definition,
	limits := DEFAULT_PRESENTATION_PROFILE_LIMITS,
) -> Presentation_Profile_Failure {
	failure := Presentation_Profile_Failure{operation = .Register}
	if definition == nil {
		failure.code = .Invalid_Profile
		return failure
	}
	failure.role = definition.role
	if !presentation_profile_limits_are_valid(limits) {
		failure.code = .Invalid_Profile
		return failure
	}
	if !presentation_profile_role_is_valid(definition.role) {
		failure.code = .Invalid_Role
		return failure
	}
	if !presentation_profile_kind_is_valid(definition.kind) {
		failure.code = .Invalid_Kind
		return failure
	}
	if definition.name.byte_count == 0 || u64(definition.name.byte_count) > limits.text_bytes ||
	   definition.source.byte_count == 0 || u64(definition.source.byte_count) > limits.text_bytes {
		failure.code = .Text_Limit
		failure.limit = limits.text_bytes
		failure.actual = max(u64(definition.name.byte_count), u64(definition.source.byte_count))
		return failure
	}
	if definition.mapping_count == 0 || u16(definition.mapping_count) > limits.mappings {
		failure.code = .Mapping_Limit
		failure.limit = u64(limits.mappings)
		failure.actual = u64(definition.mapping_count)
		return failure
	}
	seen: Presentation_Chrome_Slots
	for mapping in definition.mappings[:definition.mapping_count] {
		if mapping.slot == .Invalid || int(mapping.slot) > PRESENTATION_CHROME_SLOT_COUNT ||
		   mapping.style_role == .Invalid {
			failure.code = .Invalid_Mapping
			failure.slot = mapping.slot
			return failure
		}
		if mapping.slot in seen {
			failure.code = .Duplicate_Slot
			failure.slot = mapping.slot
			return failure
		}
		seen += {mapping.slot}
	}
	for slot in presentation_profile_required_slots(definition.role) {
		if slot not_in seen {
			failure.code = .Missing_Required_Slot
			failure.slot = slot
			return failure
		}
	}
	if definition.margin_rows > limits.inset_cells ||
	   definition.margin_columns > limits.inset_cells ||
	   definition.padding_rows > limits.inset_cells ||
	   definition.padding_columns > limits.inset_cells {
		failure.code = .Inset_Limit
		failure.limit = u64(limits.inset_cells)
		failure.actual = max(
			u64(definition.margin_rows),
			u64(definition.margin_columns),
			u64(definition.padding_rows),
			u64(definition.padding_columns),
		)
		return failure
	}
	if definition.border == .Invalid || definition.clipping == .Invalid ||
	   definition.popup_fallback == .Invalid ||
	   definition.degradation == .Invalid {
		failure.code = .Invalid_Profile
		return failure
	}
	if !presentation_profile_bounds_are_valid(definition.bounds) {
		failure.code = .Invalid_Dimensions
		return failure
	}
	if definition.kind == .Factory {
		if definition.fallback != (Presentation_Profile_Handle{}) {
			failure.code = .Invalid_Fallback
			return failure
		}
	} else if definition.fallback == (Presentation_Profile_Handle{}) {
		failure.code = .Invalid_Fallback
		return failure
	}
	return {}
}
