// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../interaction"
import "core:unicode"
import "core:unicode/utf8"

/* KEYMAP_PROFILE_SCHEMA_VERSION identifies the copied profile-catalog schema. */
KEYMAP_PROFILE_SCHEMA_VERSION :: u64(2)
/* MAX_KEYMAP_PROFILE_PROFILES bounds complete profiles in one copied catalog. */
MAX_KEYMAP_PROFILE_PROFILES :: u64(interaction.MAX_INTERACTION_PROFILES)
/* MAX_KEYMAP_PROFILE_STATES bounds all copied interaction-state definitions. */
MAX_KEYMAP_PROFILE_STATES :: u64(interaction.MAX_INTERACTION_STATES)
/* MAX_KEYMAP_PROFILE_MAPS bounds all copied map definitions in one catalog. */
MAX_KEYMAP_PROFILE_MAPS :: u64(interaction.MAX_INTERACTION_PROFILES * interaction.MAX_MAPS)
/* MAX_KEYMAP_PROFILE_BINDINGS bounds all copied scoped binding definitions. */
MAX_KEYMAP_PROFILE_BINDINGS :: u64(interaction.MAX_PROFILE_BINDING_SELECTORS)
/* MAX_KEYMAP_PROFILE_SELECTORS bounds all copied shared-continuity selectors. */
MAX_KEYMAP_PROFILE_SELECTORS :: u64(interaction.MAX_PROFILE_BINDING_SELECTORS)
/* MAX_KEYMAP_PROFILE_SURFACES bounds copied command-entry surfaces. */
MAX_KEYMAP_PROFILE_SURFACES :: u64(interaction.MAX_COMMAND_ENTRY_SURFACES)
/* MAX_KEYMAP_PROFILE_REMAPS bounds copied semantic remaps independently. */
MAX_KEYMAP_PROFILE_REMAPS :: MAX_KEYMAP_PROFILE_BINDINGS
/* MAX_KEYMAP_PROFILE_ORDERING bounds copied same-layer constraints. */
MAX_KEYMAP_PROFILE_ORDERING :: u64(MAX_KEYMAP_PROFILE_MAPS * interaction.MAX_ORDERING_CONSTRAINTS)
/* MAX_KEYMAP_PROFILE_STROKES bounds flattened copied binding sequences. */
MAX_KEYMAP_PROFILE_STROKES :: u64(MAX_KEYMAP_PROFILE_BINDINGS * interaction.MAX_SEQUENCE_STROKES)
/* MAX_KEYMAP_PROFILE_TEXT_BYTES bounds all copied UTF-8 catalog text. */
MAX_KEYMAP_PROFILE_TEXT_BYTES :: u64(interaction.MAX_PROFILE_CATALOG_BYTES)
/* MAX_KEYMAP_PROFILE_COPY_BYTES bounds the complete temporary copied catalog. */
MAX_KEYMAP_PROFILE_COPY_BYTES :: u64(interaction.MAX_PROFILE_CATALOG_BYTES)

/* KEYMAP_PROFILE_HEADER_RECORD_BYTES is the stable catalog envelope width. */
KEYMAP_PROFILE_HEADER_RECORD_BYTES :: u64(144)
/* KEYMAP_PROFILE_RECORD_BYTES is one stable complete-profile descriptor width. */
KEYMAP_PROFILE_RECORD_BYTES :: u64(88)
/* KEYMAP_STATE_RECORD_BYTES is one stable interaction-state descriptor width. */
KEYMAP_STATE_RECORD_BYTES :: u64(96)
/* KEYMAP_MAP_RECORD_BYTES is one stable map definition width. */
KEYMAP_MAP_RECORD_BYTES :: u64(200)
/* KEYMAP_BINDING_RECORD_BYTES is one stable scoped binding operation width. */
KEYMAP_BINDING_RECORD_BYTES :: u64(128)
/* KEYMAP_SELECTOR_RECORD_BYTES is one stable profile/state selector width. */
KEYMAP_SELECTOR_RECORD_BYTES :: u64(16)
/* KEYMAP_SURFACE_RECORD_BYTES is one stable command-entry surface width. */
KEYMAP_SURFACE_RECORD_BYTES :: u64(80)
/* KEYMAP_REMAP_RECORD_BYTES is one stable semantic remap width. */
KEYMAP_REMAP_RECORD_BYTES :: u64(80)
/* KEYMAP_ORDERING_RECORD_BYTES is one stable ordering constraint width. */
KEYMAP_ORDERING_RECORD_BYTES :: u64(16)
/* KEYMAP_STROKE_RECORD_BYTES is one stable normalized stroke width. */
KEYMAP_STROKE_RECORD_BYTES :: u64(24)

/* Keymap_Profile_Header_Record describes every copied catalog array and payload. */
Keymap_Profile_Header_Record :: struct {
	schema_version:       u64,
	record_bytes:         u64,
	registry_generation: u64,
	catalog_generation:  u64,
	active_profile_id:    u64,
	active_state_id:      u64,
	profile_count:        u64,
	state_count:          u64,
	map_count:            u64,
	binding_count:        u64,
	selector_count:       u64,
	surface_count:        u64,
	remap_count:          u64,
	ordering_count:       u64,
	stroke_count:         u64,
	text_bytes:           u64,
	reserved_0:           u64,
	reserved_1:           u64,
}

/* Keymap_Profile_Record identifies one profile and its contiguous states and maps. */
Keymap_Profile_Record :: struct {
	profile_id:           u64,
	profile_revision:     u64,
	first_state:          u64,
	state_count:          u64,
	initial_state_id:     u64,
	first_map:            u64,
	map_count:            u64,
	name_offset:          u64,
	name_bytes:           u64,
	text_fallback_offset: u64,
	text_fallback_bytes:  u64,
}

/* Keymap_State_Record describes one profile-owned interaction state policy. */
Keymap_State_Record :: struct {
	state_id:        u64,
	state_revision:  u64,
	admits_text_input: u64,
	admitted_effects: u64,
	name_offset:     u64,
	name_bytes:      u64,
	provider_offset: u64,
	provider_bytes:  u64,
	source_offset:   u64,
	source_bytes:    u64,
	location_offset: u64,
	location_bytes:  u64,
}

/* Keymap_Map_Record identifies one map and its contiguous child record ranges. */
Keymap_Map_Record :: struct {
	map_id:                   u64,
	map_revision:             u64,
	owner_id:                 u64,
	owner_generation:         u64,
	precedence:               u64,
	priority:                 i64,
	context_id:               u64,
	context_generation:       u64,
	context_owner_id:         u64,
	context_owner_generation: u64,
	unmatched_input_policy:    u64,
	first_binding:            u64,
	binding_count:            u64,
	first_remap:              u64,
	remap_count:              u64,
	first_ordering:           u64,
	ordering_count:           u64,
	name_offset:              u64,
	name_bytes:               u64,
	provider_offset:          u64,
	provider_bytes:           u64,
	source_offset:            u64,
	source_bytes:             u64,
	location_offset:          u64,
	location_bytes:           u64,
}

/* Keymap_Binding_Record describes one scoped operation and its copied sequence. */
Keymap_Binding_Record :: struct {
	operation:               u64,
	first_stroke:            u64,
	stroke_count:            u64,
	scope:                   u64,
	first_selector:          u64,
	selector_count:          u64,
	command_offset:          u64,
	command_bytes:           u64,
	protection_reason_offset: u64,
	protection_reason_bytes: u64,
	provider_offset:         u64,
	provider_bytes:          u64,
	source_offset:           u64,
	source_bytes:            u64,
	location_offset:         u64,
	location_bytes:          u64,
}

/* Keymap_Selector_Record names one exact profile/state compatibility target. */
Keymap_Selector_Record :: struct {
	profile_id: u64,
	state_id:   u64,
}

/* Keymap_Surface_Record describes one canonical-name command-entry presentation. */
Keymap_Surface_Record :: struct {
	surface_id:      u64,
	surface_revision: u64,
	name_offset:     u64,
	name_bytes:      u64,
	provider_offset: u64,
	provider_bytes:  u64,
	source_offset:   u64,
	source_bytes:    u64,
	location_offset: u64,
	location_bytes:  u64,
}

/* Keymap_Remap_Record describes one copied semantic command redirection. */
Keymap_Remap_Record :: struct {
	from_command_offset: u64,
	from_command_bytes:  u64,
	to_command_offset:   u64,
	to_command_bytes:    u64,
	provider_offset:     u64,
	provider_bytes:      u64,
	source_offset:       u64,
	source_bytes:        u64,
	location_offset:     u64,
	location_bytes:      u64,
}

/* Keymap_Ordering_Record declares one same-class map relation. */
Keymap_Ordering_Record :: struct {
	relation:     u64,
	other_map_id: u64,
}

/* Keymap_Stroke_Record is one pointer-free normalized logical key. */
Keymap_Stroke_Record :: struct {
	kind:      u64,
	modifiers: u64,
	scalar:    i64,
}

/* Keymap_Record_Failure_Code classifies copied catalog rejection. */
Keymap_Record_Failure_Code :: enum u16 {
	None,
	Unsupported_Schema,
	Invalid_Header,
	Invalid_Catalog,
	Profile_Limit,
	State_Limit,
	Map_Limit,
	Binding_Limit,
	Selector_Limit,
	Surface_Limit,
	Remap_Limit,
	Ordering_Limit,
	Stroke_Limit,
	Text_Limit,
	Copy_Limit,
	Size_Mismatch,
	Count_Mismatch,
	Invalid_Profile,
	Invalid_State,
	Invalid_Map,
	Invalid_Binding,
	Invalid_Selector,
	Invalid_Surface,
	Invalid_Remap,
	Invalid_Ordering,
	Invalid_Stroke,
	Invalid_Text,
}

/* Keymap_Record_Failure identifies the rejected record and applicable bound. */
Keymap_Record_Failure :: struct {
	code:   Keymap_Record_Failure_Code,
	index:  u64,
	limit:  u64,
	actual: u64,
}

/* keymap_profile_record_bytes validates quotas and returns the exact copied width. */
keymap_profile_record_bytes :: proc(
	profiles, states, maps, bindings, selectors, surfaces, remaps, ordering, strokes, text_bytes: u64,
) -> (bytes: u64, failure: Keymap_Record_Failure) {
	checks := [?]struct {actual, limit: u64, code: Keymap_Record_Failure_Code} {
		{profiles, MAX_KEYMAP_PROFILE_PROFILES, .Profile_Limit},
		{states, MAX_KEYMAP_PROFILE_STATES, .State_Limit},
		{maps, MAX_KEYMAP_PROFILE_MAPS, .Map_Limit},
		{bindings, MAX_KEYMAP_PROFILE_BINDINGS, .Binding_Limit},
		{selectors, MAX_KEYMAP_PROFILE_SELECTORS, .Selector_Limit},
		{surfaces, MAX_KEYMAP_PROFILE_SURFACES, .Surface_Limit},
		{remaps, MAX_KEYMAP_PROFILE_REMAPS, .Remap_Limit},
		{ordering, MAX_KEYMAP_PROFILE_ORDERING, .Ordering_Limit},
		{strokes, MAX_KEYMAP_PROFILE_STROKES, .Stroke_Limit},
		{text_bytes, MAX_KEYMAP_PROFILE_TEXT_BYTES, .Text_Limit},
	}
	for check in checks {
		if check.actual > check.limit || (check.code == .Profile_Limit && check.actual == 0) ||
		   (check.code == .State_Limit && check.actual == 0) ||
		   (check.code == .Map_Limit && check.actual == 0) ||
		   (check.code == .Surface_Limit && check.actual == 0) {
			return 0, {code = check.code, limit = check.limit, actual = check.actual}
		}
	}
	bytes = KEYMAP_PROFILE_HEADER_RECORD_BYTES + profiles * KEYMAP_PROFILE_RECORD_BYTES +
	        states * KEYMAP_STATE_RECORD_BYTES + maps * KEYMAP_MAP_RECORD_BYTES +
	        bindings * KEYMAP_BINDING_RECORD_BYTES + selectors * KEYMAP_SELECTOR_RECORD_BYTES +
	        surfaces * KEYMAP_SURFACE_RECORD_BYTES + remaps * KEYMAP_REMAP_RECORD_BYTES +
	        ordering * KEYMAP_ORDERING_RECORD_BYTES + strokes * KEYMAP_STROKE_RECORD_BYTES + text_bytes
	if bytes > MAX_KEYMAP_PROFILE_COPY_BYTES {
		return 0, {code = .Copy_Limit, limit = MAX_KEYMAP_PROFILE_COPY_BYTES, actual = bytes}
	}
	return bytes, {}
}

/* keymap_profile_records_validate rejects malformed copied catalogs before adaptation. */
keymap_profile_records_validate :: proc(
	header: Keymap_Profile_Header_Record,
	profiles: []Keymap_Profile_Record,
	states: []Keymap_State_Record,
	maps: []Keymap_Map_Record,
	bindings: []Keymap_Binding_Record,
	selectors: []Keymap_Selector_Record,
	surfaces: []Keymap_Surface_Record,
	remaps: []Keymap_Remap_Record,
	ordering: []Keymap_Ordering_Record,
	strokes: []Keymap_Stroke_Record,
	text: []byte,
) -> Keymap_Record_Failure {
	if header.schema_version != KEYMAP_PROFILE_SCHEMA_VERSION {
		return {code = .Unsupported_Schema, actual = header.schema_version}
	}
	if header.reserved_0 != 0 || header.reserved_1 != 0 || header.registry_generation == 0 ||
	   header.catalog_generation == 0 || header.active_profile_id == 0 || header.active_state_id == 0 {
		return {code = .Invalid_Header}
	}
	bytes, failure := keymap_profile_record_bytes(
		header.profile_count, header.state_count, header.map_count, header.binding_count,
		header.selector_count, header.surface_count, header.remap_count, header.ordering_count,
		header.stroke_count, header.text_bytes,
	)
	if failure.code != .None {
		return failure
	}
	if header.record_bytes != bytes {
		return {code = .Size_Mismatch, limit = bytes, actual = header.record_bytes}
	}
	if header.profile_count != u64(len(profiles)) || header.state_count != u64(len(states)) ||
	   header.map_count != u64(len(maps)) || header.binding_count != u64(len(bindings)) ||
	   header.selector_count != u64(len(selectors)) || header.surface_count != u64(len(surfaces)) ||
	   header.remap_count != u64(len(remaps)) || header.ordering_count != u64(len(ordering)) ||
	   header.stroke_count != u64(len(strokes)) || header.text_bytes != u64(len(text)) {
		return {code = .Count_Mismatch}
	}

	next_state, next_map: u64
	active_profile_found, active_state_found := false, false
	for profile, index in profiles {
		if profile.profile_id == 0 || profile.profile_revision == 0 || profile.initial_state_id == 0 ||
		   profile.first_state != next_state || profile.state_count == 0 ||
		   profile.state_count > u64(interaction.MAX_INTERACTION_STATES_PER_PROFILE) ||
		   !keymap_record_range_is_valid(profile.first_state, profile.state_count, header.state_count) ||
		   profile.first_map != next_map || profile.map_count == 0 ||
		   profile.map_count > u64(interaction.MAX_MAPS) ||
		   !keymap_record_range_is_valid(profile.first_map, profile.map_count, header.map_count) ||
		   !keymap_record_text_is_valid(text, profile.name_offset, profile.name_bytes, u64(interaction.MAX_IDENTITY_BYTES), false) ||
		   !keymap_record_text_is_valid(text, profile.text_fallback_offset, profile.text_fallback_bytes, u64(interaction.MAX_COMMAND_NAME_BYTES), false) {
			return {code = .Invalid_Profile, index = u64(index)}
		}
		for other, other_index in profiles {
			if other_index != index && other.profile_id == profile.profile_id {
				return {code = .Invalid_Profile, index = u64(index)}
			}
		}
		initial_found := false
		for state_index in profile.first_state ..< profile.first_state + profile.state_count {
			state := states[int(state_index)]
			if state.state_id == profile.initial_state_id {
				initial_found = true
			}
			if profile.profile_id == header.active_profile_id && state.state_id == header.active_state_id {
				active_state_found = true
			}
		}
		if !initial_found {
			return {code = .Invalid_Profile, index = u64(index)}
		}
		if profile.profile_id == header.active_profile_id {
			active_profile_found = true
		}
		next_state += profile.state_count
		next_map += profile.map_count
	}
	if next_state != header.state_count || next_map != header.map_count ||
	   !active_profile_found || !active_state_found {
		return {code = .Invalid_Catalog}
	}

	for state, index in states {
		if !keymap_state_record_is_valid(state, text) {
			return {code = .Invalid_State, index = u64(index)}
		}
		owner := keymap_profile_for_state(profiles, u64(index))
		for other_index in owner.first_state ..< owner.first_state + owner.state_count {
			if other_index != u64(index) && states[int(other_index)].state_id == state.state_id {
				return {code = .Invalid_State, index = u64(index)}
			}
		}
	}

	next_binding, next_remap, next_ordering: u64
	for map_record, index in maps {
		owner := keymap_profile_for_map(profiles, u64(index))
		if !keymap_map_record_is_valid(map_record, maps, owner, text) ||
		   map_record.first_binding != next_binding ||
		   map_record.binding_count > u64(interaction.MAX_BINDINGS_PER_MAP) ||
		   !keymap_record_range_is_valid(map_record.first_binding, map_record.binding_count, header.binding_count) ||
		   map_record.first_remap != next_remap ||
		   !keymap_record_range_is_valid(map_record.first_remap, map_record.remap_count, header.remap_count) ||
		   map_record.first_ordering != next_ordering ||
		   map_record.ordering_count > u64(interaction.MAX_ORDERING_CONSTRAINTS) ||
		   !keymap_record_range_is_valid(map_record.first_ordering, map_record.ordering_count, header.ordering_count) {
			return {code = .Invalid_Map, index = u64(index)}
		}
		for constraint_index in map_record.first_ordering ..< map_record.first_ordering + map_record.ordering_count {
			constraint := ordering[int(constraint_index)]
			if !keymap_ordering_record_is_valid(constraint, maps, owner) || constraint.other_map_id == map_record.map_id {
				return {code = .Invalid_Ordering, index = constraint_index}
			}
		}
		next_binding += map_record.binding_count
		next_remap += map_record.remap_count
		next_ordering += map_record.ordering_count
	}
	if next_binding != header.binding_count || next_remap != header.remap_count || next_ordering != header.ordering_count {
		return {code = .Count_Mismatch}
	}

	next_stroke, next_selector: u64
	for binding, index in bindings {
		if binding.first_stroke != next_stroke || binding.first_selector != next_selector ||
		   !keymap_binding_record_is_valid(binding, text) ||
		   !keymap_record_range_is_valid(binding.first_stroke, binding.stroke_count, header.stroke_count) ||
		   !keymap_record_range_is_valid(binding.first_selector, binding.selector_count, header.selector_count) {
			return {code = .Invalid_Binding, index = u64(index)}
		}
		for selector_index in binding.first_selector ..< binding.first_selector + binding.selector_count {
			if !keymap_selector_record_is_valid(selectors[int(selector_index)], profiles, states) {
				return {code = .Invalid_Selector, index = selector_index}
			}
		}
		next_stroke += binding.stroke_count
		next_selector += binding.selector_count
	}
	if next_stroke != header.stroke_count || next_selector != header.selector_count {
		return {code = .Count_Mismatch}
	}
	for surface, index in surfaces {
		if !keymap_surface_record_is_valid(surface, surfaces, text) {
			return {code = .Invalid_Surface, index = u64(index)}
		}
	}
	for remap, index in remaps {
		if !keymap_remap_record_is_valid(remap, text) {
			return {code = .Invalid_Remap, index = u64(index)}
		}
	}
	for stroke, index in strokes {
		if !keymap_stroke_record_is_valid(stroke) {
			return {code = .Invalid_Stroke, index = u64(index)}
		}
	}
	return {}
}

/* keymap_record_layout_is_valid verifies every copied ABI width. */
keymap_record_layout_is_valid :: proc() -> bool {
	return u64(size_of(Keymap_Profile_Header_Record)) == KEYMAP_PROFILE_HEADER_RECORD_BYTES &&
	       u64(size_of(Keymap_Profile_Record)) == KEYMAP_PROFILE_RECORD_BYTES &&
	       u64(size_of(Keymap_State_Record)) == KEYMAP_STATE_RECORD_BYTES &&
	       u64(size_of(Keymap_Map_Record)) == KEYMAP_MAP_RECORD_BYTES &&
	       u64(size_of(Keymap_Binding_Record)) == KEYMAP_BINDING_RECORD_BYTES &&
	       u64(size_of(Keymap_Selector_Record)) == KEYMAP_SELECTOR_RECORD_BYTES &&
	       u64(size_of(Keymap_Surface_Record)) == KEYMAP_SURFACE_RECORD_BYTES &&
	       u64(size_of(Keymap_Remap_Record)) == KEYMAP_REMAP_RECORD_BYTES &&
	       u64(size_of(Keymap_Ordering_Record)) == KEYMAP_ORDERING_RECORD_BYTES &&
	       u64(size_of(Keymap_Stroke_Record)) == KEYMAP_STROKE_RECORD_BYTES
}

@(private)
keymap_profile_for_state :: proc(profiles: []Keymap_Profile_Record, index: u64) -> Keymap_Profile_Record {
	for profile in profiles {
		if index >= profile.first_state && index < profile.first_state + profile.state_count {
			return profile
		}
	}
	return {}
}

@(private)
keymap_profile_for_map :: proc(profiles: []Keymap_Profile_Record, index: u64) -> Keymap_Profile_Record {
	for profile in profiles {
		if index >= profile.first_map && index < profile.first_map + profile.map_count {
			return profile
		}
	}
	return {}
}

@(private)
keymap_state_record_is_valid :: proc(record: Keymap_State_Record, text: []byte) -> bool {
	return record.state_id != 0 && record.state_revision != 0 && record.admits_text_input <= 1 &&
	       record.admitted_effects & ~u64(0x0f) == 0 &&
	       keymap_record_text_is_valid(text, record.name_offset, record.name_bytes, u64(interaction.MAX_IDENTITY_BYTES), false) &&
	       keymap_record_provenance_is_valid(text, record.provider_offset, record.provider_bytes, record.source_offset, record.source_bytes, record.location_offset, record.location_bytes)
}

@(private)
keymap_map_record_is_valid :: proc(record: Keymap_Map_Record, maps: []Keymap_Map_Record, owner: Keymap_Profile_Record, text: []byte) -> bool {
	if record.map_id == 0 || record.map_revision == 0 ||
	   record.precedence < u64(interaction.Precedence_Class.Protected_Recovery) ||
	   record.precedence > u64(interaction.Precedence_Class.Factory_Fallback) ||
	   record.unmatched_input_policy < u64(interaction.Unmatched_Input_Policy.Fallthrough) ||
	   record.unmatched_input_policy > u64(interaction.Unmatched_Input_Policy.Reject) ||
	   record.priority < i64(-2_147_483_648) || record.priority > i64(2_147_483_647) {
		return false
	}
	matches := 0
	for other_index in owner.first_map ..< owner.first_map + owner.map_count {
		if maps[int(other_index)].map_id == record.map_id {
			matches += 1
		}
	}
	if matches != 1 {
		return false
	}
	context_empty := record.context_id == 0 && record.context_generation == 0 && record.context_owner_id == 0 && record.context_owner_generation == 0
	context_complete := record.context_id != 0 && record.context_generation != 0 && record.context_owner_id != 0 && record.context_owner_generation != 0 && record.owner_id == record.context_owner_id && record.owner_generation == record.context_owner_generation
	return (context_empty || context_complete) &&
	       keymap_record_text_is_valid(text, record.name_offset, record.name_bytes, u64(interaction.MAX_IDENTITY_BYTES), false) &&
	       keymap_record_provenance_is_valid(text, record.provider_offset, record.provider_bytes, record.source_offset, record.source_bytes, record.location_offset, record.location_bytes)
}

@(private)
keymap_binding_record_is_valid :: proc(record: Keymap_Binding_Record, text: []byte) -> bool {
	if record.operation < u64(interaction.Binding_Operation.Bind) || record.operation > u64(interaction.Binding_Operation.Mask) ||
	   record.stroke_count == 0 || record.stroke_count > u64(interaction.MAX_SEQUENCE_STROKES) ||
	   record.scope < u64(interaction.Binding_Scope.Protected_Recovery) || record.scope > u64(interaction.Binding_Scope.State_Specific) ||
	   record.selector_count > u64(interaction.MAX_SHARED_BINDING_SELECTORS) {
		return false
	}
	selected := record.scope == u64(interaction.Binding_Scope.Shared_Continuity) ||
		record.scope == u64(interaction.Binding_Scope.State_Specific)
	protected := record.scope == u64(interaction.Binding_Scope.Protected_Recovery)
	if selected != (record.selector_count > 0) || protected != (record.protection_reason_bytes > 0) {
		return false
	}
	command_empty := record.operation == u64(interaction.Binding_Operation.Unbind) || record.operation == u64(interaction.Binding_Operation.Mask)
	return keymap_record_text_is_valid(text, record.command_offset, record.command_bytes, u64(interaction.MAX_COMMAND_NAME_BYTES), command_empty) &&
	       (command_empty == (record.command_bytes == 0)) &&
	       keymap_record_text_is_valid(text, record.protection_reason_offset, record.protection_reason_bytes, u64(interaction.MAX_PROTECTION_REASON_BYTES), !protected) &&
	       keymap_record_provenance_is_valid(text, record.provider_offset, record.provider_bytes, record.source_offset, record.source_bytes, record.location_offset, record.location_bytes)
}

@(private)
keymap_selector_record_is_valid :: proc(record: Keymap_Selector_Record, profiles: []Keymap_Profile_Record, states: []Keymap_State_Record) -> bool {
	for profile in profiles {
		if profile.profile_id == record.profile_id {
			for state_index in profile.first_state ..< profile.first_state + profile.state_count {
				if states[int(state_index)].state_id == record.state_id {
					return true
				}
			}
		}
	}
	return false
}

@(private)
keymap_surface_record_is_valid :: proc(record: Keymap_Surface_Record, surfaces: []Keymap_Surface_Record, text: []byte) -> bool {
	if record.surface_id == 0 || record.surface_id > u64(0xffff) || record.surface_revision == 0 ||
	   !keymap_record_text_is_valid(text, record.name_offset, record.name_bytes, u64(interaction.MAX_IDENTITY_BYTES), false) ||
	   !keymap_record_provenance_is_valid(text, record.provider_offset, record.provider_bytes, record.source_offset, record.source_bytes, record.location_offset, record.location_bytes) {
		return false
	}
	count := 0
	for other in surfaces {
		if other.surface_id == record.surface_id {
			count += 1
		}
	}
	return count == 1
}

@(private)
keymap_remap_record_is_valid :: proc(record: Keymap_Remap_Record, text: []byte) -> bool {
	from_valid := keymap_record_text_is_valid(text, record.from_command_offset, record.from_command_bytes, u64(interaction.MAX_COMMAND_NAME_BYTES), false)
	to_valid := keymap_record_text_is_valid(text, record.to_command_offset, record.to_command_bytes, u64(interaction.MAX_COMMAND_NAME_BYTES), false)
	return from_valid && to_valid && !keymap_record_text_equal(text, record.from_command_offset, record.from_command_bytes, record.to_command_offset, record.to_command_bytes) &&
	       keymap_record_provenance_is_valid(text, record.provider_offset, record.provider_bytes, record.source_offset, record.source_bytes, record.location_offset, record.location_bytes)
}

@(private)
keymap_ordering_record_is_valid :: proc(record: Keymap_Ordering_Record, maps: []Keymap_Map_Record, owner: Keymap_Profile_Record) -> bool {
	if record.relation < u64(interaction.Ordering_Relation.Before) || record.relation > u64(interaction.Ordering_Relation.After) || record.other_map_id == 0 {
		return false
	}
	for map_index in owner.first_map ..< owner.first_map + owner.map_count {
		if maps[int(map_index)].map_id == record.other_map_id {
			return true
		}
	}
	return false
}

@(private)
keymap_stroke_record_is_valid :: proc(record: Keymap_Stroke_Record) -> bool {
	if record.kind < u64(interaction.Logical_Key_Kind.Unicode_Scalar) || record.kind > u64(interaction.Logical_Key_Kind.F4) || record.modifiers & ~u64(0x1f) != 0 {
		return false
	}
	if record.kind == u64(interaction.Logical_Key_Kind.Unicode_Scalar) {
		value := rune(record.scalar)
		return i64(value) == record.scalar && utf8.valid_rune(value) && unicode.is_graphic(value)
	}
	return record.scalar == 0
}

@(private)
keymap_record_text_equal :: proc(text: []byte, first_offset, first_count, second_offset, second_count: u64) -> bool {
	if first_count != second_count {
		return false
	}
	for index in 0 ..< first_count {
		if text[int(first_offset + index)] != text[int(second_offset + index)] {
			return false
		}
	}
	return true
}

@(private)
keymap_record_provenance_is_valid :: proc(text: []byte, provider_offset, provider_bytes, source_offset, source_bytes, location_offset, location_bytes: u64) -> bool {
	return keymap_record_text_is_valid(text, provider_offset, provider_bytes, u64(interaction.MAX_SOURCE_BYTES), false) &&
	       keymap_record_text_is_valid(text, source_offset, source_bytes, u64(interaction.MAX_SOURCE_BYTES), false) &&
	       keymap_record_text_is_valid(text, location_offset, location_bytes, u64(interaction.MAX_LOCATION_BYTES), true)
}

@(private)
keymap_record_text_is_valid :: proc(text: []byte, offset, count, limit: u64, empty_allowed: bool) -> bool {
	if count > limit || (!empty_allowed && count == 0) || !keymap_record_range_is_valid(offset, count, u64(len(text))) {
		return false
	}
	return utf8.valid_string(string(text[int(offset):int(offset + count)]))
}

@(private)
keymap_record_range_is_valid :: proc(offset, count, total: u64) -> bool {
	return offset <= total && count <= total - offset
}
