// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package gutter

import "base:runtime"
import "core:unicode/utf8"

/* MAX_PROGRAMMABLE_PROVIDERS admits one personal provider in the initial delivery. */
MAX_PROGRAMMABLE_PROVIDERS :: u8(1)
/* MAX_PROGRAMMABLE_LANES_PER_PROVIDER bounds one copied provider definition. */
MAX_PROGRAMMABLE_LANES_PER_PROVIDER :: u8(1)
/* MAX_PROGRAMMABLE_MARKERS_PER_PROVIDER bounds one copied provider publication. */
MAX_PROGRAMMABLE_MARKERS_PER_PROVIDER :: u16(256)
/* MAX_PROGRAMMABLE_IDENTITY_BYTES bounds provider-scoped machine identities. */
MAX_PROGRAMMABLE_IDENTITY_BYTES :: 64
/* MAX_PROGRAMMABLE_PROVIDER_NAME_BYTES bounds one inspectable display name. */
MAX_PROGRAMMABLE_PROVIDER_NAME_BYTES :: 128
/* MAX_PROGRAMMABLE_PACKAGE_NAME_BYTES bounds one package identity. */
MAX_PROGRAMMABLE_PACKAGE_NAME_BYTES :: 64
/* MAX_PROGRAMMABLE_COMMAND_NAME_BYTES bounds one action identity at the bridge. */
MAX_PROGRAMMABLE_COMMAND_NAME_BYTES :: 128
/* MAX_PROGRAMMABLE_DETAIL_BYTES bounds one inspectable marker detail. */
MAX_PROGRAMMABLE_DETAIL_BYTES :: 512
/* MAX_PROGRAMMABLE_TEXT_BYTES bounds provider metadata and marker text. */
MAX_PROGRAMMABLE_TEXT_BYTES :: 128 * 1_024
/* PROGRAMMABLE_PROVIDER_ID identifies the sole admitted personal provider owner. */
PROGRAMMABLE_PROVIDER_ID :: Provider_ID(1_024)
/* PROGRAMMABLE_LANE_ID_BASE starts the reserved personal lane identity range. */
PROGRAMMABLE_LANE_ID_BASE :: Lane_ID(1_024)

/* Programmable_Lane_Proposal borrows one complete personal lane declaration. */
Programmable_Lane_Proposal :: struct {
	identity:      string,
	side:          Side,
	order:         i16,
	attachments:   Attachment_Kinds,
	width_policy:  Width_Policy,
	minimum_cells: u16,
	maximum_cells: u16,
	alignment:     Alignment,
	visibility:    Visibility_Policy,
	collision:     Collision_Policy,
	priority:      u16,
	style_role:    Semantic_Role,
	separator:     Representation,
}

/* Programmable_Marker_Proposal borrows one provider-scoped logical marker. */
Programmable_Marker_Proposal :: struct {
	identity:          string,
	lane_index:        u8,
	logical_line:      u64,
	style_role:        Semantic_Role,
	priority:          u16,
	representation:    Representation,
	aggregation_label: string,
	detail:            string,
	actions:           [MAX_ACTIONS_PER_MARKER]Command_Reference,
	action_count:      u8,
	stale:             bool,
}

/* Programmable_Provider_Proposal borrows one complete immutable generation. */
Programmable_Provider_Proposal :: struct {
	definition_generation: Provider_Generation,
	marker_generation:     Marker_Generation_ID,
	name:                  string,
	package_name:          string,
	complete:              bool,
	cancelled:             bool,
	lanes:                 []Programmable_Lane_Proposal,
	markers:               []Programmable_Marker_Proposal,
}

/* Programmable_Provider_State identifies checked provider lifecycle state. */
Programmable_Provider_State :: enum u8 {
	Invalid,
	Prepared,
	Confirmed,
	Active,
	Suspended,
	Failed,
	Removed,
}

/* Programmable_Provider_Descriptor is one copied inspectable provider owner. */
Programmable_Provider_Descriptor :: struct {
	provider:              Provider_ID,
	definition_generation: Provider_Generation,
	marker_generation:     Marker_Generation_ID,
	state:                 Programmable_Provider_State,
	name:                  string,
	package_name:          string,
	lane_count:            u8,
	marker_count:          u16,
	complete:              bool,
	retained_bytes:        u64,
}

@(private)
Programmable_Provider_Data :: struct {
	descriptor: Programmable_Provider_Descriptor,
	lanes:      [MAX_PROGRAMMABLE_LANES_PER_PROVIDER]Lane_Definition,
	markers:    Marker_Store,
	storage:    []u8,
	allocator:  runtime.Allocator,
}

/* Programmable_Provider_Candidate owns one prepared generation until activation or discard. */
Programmable_Provider_Candidate :: struct {
	data:                         ^Programmable_Provider_Data,
	expected_registry_generation: u64,
	confirmed:                    bool,
	allocator:                    runtime.Allocator,
}

/* Programmable_Provider_View borrows one active provider during one admitted turn. */
Programmable_Provider_View :: struct {
	descriptor:  Programmable_Provider_Descriptor,
	lanes:       []Lane_Definition,
	publication: Marker_Generation_View,
}

/* Programmable_Registry owns one last-valid personal provider generation. */
Programmable_Registry :: struct {
	active:              ^Programmable_Provider_Data,
	generation:          u64,
	active_turns:        u16,
	latest_failure:      Failure_Context,
	allocator:           runtime.Allocator,
	closed:              bool,
}

/* programmable_registry_init creates one empty bounded provider owner. */
programmable_registry_init :: proc(
	registry: ^Programmable_Registry,
	allocator := context.allocator,
) -> (bool, Failure_Context) {
	if registry == nil || registry.allocator.procedure != nil || registry.closed ||
	   allocator.procedure == nil {
		return false, Failure_Context{operation = .Prepare, code = .Invalid_Request}
	}
	registry^ = Programmable_Registry{generation = 1, allocator = allocator}
	return true, {}
}

/* programmable_registry_prepare copies and validates one complete candidate. */
programmable_registry_prepare :: proc(
	registry: ^Programmable_Registry,
	expected_generation: u64,
	proposal: Programmable_Provider_Proposal,
) -> (candidate: Programmable_Provider_Candidate, ok: bool, failure: Failure_Context) {
	if !programmable_registry_is_open(registry) || expected_generation != registry.generation {
		return {}, false, programmable_registry_reject(
			registry,
			Failure_Context {
				operation = .Prepare,
				code = .Stale_Generation,
				limit = registry_generation(registry),
				actual = expected_generation,
			},
		)
	}
	if registry.active_turns > 0 {
		return {}, false, programmable_registry_reject(registry, Failure_Context {
			operation = .Prepare,
			code = .Active_Turn,
			limit = 0,
			actual = u64(registry.active_turns),
		})
	}
	data, prepared, prepare_failure := programmable_provider_prepare(
		proposal,
		registry.allocator,
	)
	if !prepared do return {}, false, programmable_registry_reject(registry, prepare_failure)
	data.descriptor.state = .Prepared
	return Programmable_Provider_Candidate {
		data = data,
		expected_registry_generation = expected_generation,
		allocator = registry.allocator,
	}, true, {}
}

/* programmable_provider_candidate_confirm marks one complete candidate ready to publish. */
programmable_provider_candidate_confirm :: proc(
	candidate: ^Programmable_Provider_Candidate,
) -> (bool, Failure_Context) {
	if candidate == nil || candidate.data == nil || candidate.allocator.procedure == nil ||
	   candidate.confirmed || candidate.data.descriptor.state != .Prepared {
		return false, Failure_Context{operation = .Activate, code = .Invalid_Request}
	}
	candidate.confirmed = true
	candidate.data.descriptor.state = .Confirmed
	return true, {}
}

/* programmable_registry_activate atomically replaces the last-valid provider. */
programmable_registry_activate :: proc(
	registry: ^Programmable_Registry,
	candidate: ^Programmable_Provider_Candidate,
) -> (bool, Failure_Context) {
	if !programmable_registry_is_open(registry) || candidate == nil || candidate.data == nil ||
	   !candidate.confirmed || candidate.expected_registry_generation != registry.generation ||
	   registry.active_turns > 0 {
		code := Failure_Code.Invalid_Request
		if registry != nil && registry.active_turns > 0 do code = .Active_Turn
		return false, programmable_registry_reject(
			registry,
			Failure_Context{operation = .Activate, code = code, actual = registry_active_turns(registry)},
		)
	}
	prior := registry.active
	registry.active = candidate.data
	registry.active.descriptor.state = .Active
	registry.generation += 1
	registry.latest_failure = {}
	candidate^ = {}
	if prior != nil do programmable_provider_data_close(prior)
	return true, {}
}

/* programmable_registry_suspend hides one active provider without releasing it. */
programmable_registry_suspend :: proc(
	registry: ^Programmable_Registry,
	expected_generation: u64,
) -> (bool, Failure_Context) {
	if !programmable_registry_is_open(registry) || registry.active == nil ||
	   expected_generation != registry.generation || registry.active_turns > 0 {
		return false, programmable_registry_reject(
			registry,
			Failure_Context{operation = .Suspend, code = .Invalid_Request},
		)
	}
	registry.active.descriptor.state = .Suspended
	registry.generation += 1
	return true, {}
}

/* programmable_registry_resume restores one retained suspended provider. */
programmable_registry_resume :: proc(
	registry: ^Programmable_Registry,
	expected_generation: u64,
) -> (bool, Failure_Context) {
	if !programmable_registry_is_open(registry) || registry.active == nil ||
	   registry.active.descriptor.state != .Suspended ||
	   expected_generation != registry.generation || registry.active_turns > 0 {
		return false, programmable_registry_reject(
			registry,
			Failure_Context{operation = .Activate, code = .Invalid_Request},
		)
	}
	registry.active.descriptor.state = .Active
	registry.generation += 1
	return true, {}
}

/* programmable_registry_fail records a candidate failure and preserves active data. */
programmable_registry_fail :: proc(
	registry: ^Programmable_Registry,
	failure: Failure_Context,
) -> (bool, Failure_Context) {
	if !programmable_registry_is_open(registry) || failure.code == .None {
		return false, Failure_Context{operation = .Prepare, code = .Invalid_Request}
	}
	registry.latest_failure = failure
	if registry.active != nil && registry.active.descriptor.state == .Active {
		registry.active.descriptor.state = .Failed
	}
	return true, {}
}

/* programmable_registry_remove releases only the personal provider generation. */
programmable_registry_remove :: proc(
	registry: ^Programmable_Registry,
	expected_generation: u64,
) -> (bool, Failure_Context) {
	if !programmable_registry_is_open(registry) || expected_generation != registry.generation ||
	   registry.active_turns > 0 {
		return false, programmable_registry_reject(
			registry,
			Failure_Context{operation = .Remove, code = .Invalid_Request},
		)
	}
	if registry.active != nil {
		registry.active.descriptor.state = .Removed
		programmable_provider_data_close(registry.active)
		registry.active = nil
	}
	registry.generation += 1
	registry.latest_failure = {}
	return true, {}
}

/* programmable_registry_turn_begin borrows active immutable data for one render turn. */
programmable_registry_turn_begin :: proc(
	registry: ^Programmable_Registry,
) -> (view: Programmable_Provider_View, ok: bool, failure: Failure_Context) {
	if !programmable_registry_is_open(registry) || registry.active == nil {
		return {}, false, Failure_Context{operation = .Inspect, code = .Invalid_Generation}
	}
	if registry.active.descriptor.state == .Suspended {
		return {}, false, Failure_Context{operation = .Inspect, code = .Provider_Suspended}
	}
	publication, publication_ok, publication_failure := marker_store_view(&registry.active.markers)
	if !publication_ok do return {}, false, publication_failure
	registry.active_turns += 1
	return Programmable_Provider_View {
		descriptor = registry.active.descriptor,
		lanes = registry.active.lanes[:registry.active.descriptor.lane_count],
		publication = publication,
	}, true, {}
}

/* programmable_registry_turn_end releases one admitted immutable borrow. */
programmable_registry_turn_end :: proc(registry: ^Programmable_Registry) -> (bool, Failure_Context) {
	if !programmable_registry_is_open(registry) || registry.active_turns == 0 {
		return false, Failure_Context{operation = .Inspect, code = .Invalid_Request}
	}
	registry.active_turns -= 1
	return true, {}
}

/* programmable_registry_inspect copies lifecycle, limits, usage, and failure state. */
programmable_registry_inspect :: proc(
	registry: ^Programmable_Registry,
) -> (descriptor: Programmable_Provider_Descriptor, generation: u64,
	active_turns: u16, latest_failure: Failure_Context, ok: bool) {
	if !programmable_registry_is_open(registry) do return {}, 0, 0, {}, false
	if registry.active != nil do descriptor = registry.active.descriptor
	return descriptor, registry.generation, registry.active_turns, registry.latest_failure, true
}

/* programmable_provider_candidate_close discards one unactivated candidate exactly once. */
programmable_provider_candidate_close :: proc(
	candidate: ^Programmable_Provider_Candidate,
) -> (bool, Failure_Context) {
	if candidate == nil || candidate.data == nil || candidate.allocator.procedure == nil {
		return false, Failure_Context{operation = .Close, code = .Closed_View}
	}
	programmable_provider_data_close(candidate.data)
	candidate^ = {}
	return true, {}
}

/* programmable_registry_close drains and releases one complete provider registry. */
programmable_registry_close :: proc(registry: ^Programmable_Registry) -> (bool, Failure_Context) {
	if !programmable_registry_is_open(registry) || registry.active_turns > 0 {
		return false, Failure_Context {
			operation = .Close,
			code = .Active_Turn,
			actual = registry_active_turns(registry),
		}
	}
	allocator := registry.allocator
	if registry.active != nil do programmable_provider_data_close(registry.active)
	registry^ = Programmable_Registry{allocator = allocator, closed = true}
	return true, {}
}

@(private)
programmable_provider_prepare :: proc(
	proposal: Programmable_Provider_Proposal,
	allocator: runtime.Allocator,
) -> (^Programmable_Provider_Data, bool, Failure_Context) {
	failure, valid := programmable_provider_proposal_validate(proposal)
	if !valid do return nil, false, failure
	data, allocation_error := new(Programmable_Provider_Data, allocator)
	if allocation_error != nil {
		return nil, false, Failure_Context{operation = .Prepare, code = .Allocation}
	}
	data.allocator = allocator
	defer if data != nil do programmable_provider_data_close(data)
	storage_bytes := len(proposal.name) + len(proposal.package_name)
	for lane in proposal.lanes {
		storage_bytes += len(lane.separator.value) + len(lane.separator.fallback)
	}
	data.storage, allocation_error = make([]u8, storage_bytes, allocator)
	if allocation_error != nil {
		return nil, false, Failure_Context {
			operation = .Prepare, code = .Allocation, actual = u64(storage_bytes),
		}
	}
	cursor := 0
	data.descriptor = {
		provider = PROGRAMMABLE_PROVIDER_ID,
		definition_generation = proposal.definition_generation,
		marker_generation = proposal.marker_generation,
		state = .Prepared,
		lane_count = u8(len(proposal.lanes)),
		marker_count = u16(len(proposal.markers)),
		complete = proposal.complete,
	}
	data.descriptor.name, cursor = programmable_copy_text(data.storage, cursor, proposal.name)
	data.descriptor.package_name, cursor = programmable_copy_text(
		data.storage,
		cursor,
		proposal.package_name,
	)
	for source, index in proposal.lanes {
		lane := &data.lanes[index]
		lane^ = {
			id = PROGRAMMABLE_LANE_ID_BASE + Lane_ID(index),
			provider = PROGRAMMABLE_PROVIDER_ID,
			provider_generation = proposal.definition_generation,
			side = source.side,
			order = source.order,
			attachments = source.attachments,
			width_policy = source.width_policy,
			minimum_cells = source.minimum_cells,
			maximum_cells = source.maximum_cells,
			alignment = source.alignment,
			visibility = source.visibility,
			collision = source.collision,
			priority = source.priority,
			style_role = source.style_role,
			separator = source.separator,
		}
		lane.separator.value, cursor = programmable_copy_text(
			data.storage,
			cursor,
			source.separator.value,
		)
		lane.separator.fallback, cursor = programmable_copy_text(
			data.storage,
			cursor,
			source.separator.fallback,
		)
	}
	store_ok, store_failure := marker_store_init(&data.markers, allocator, DEFAULT_LIMITS)
	if !store_ok do return nil, false, store_failure
	markers: [MAX_PROGRAMMABLE_MARKERS_PER_PROVIDER]Marker
	for source, index in proposal.markers {
		markers[index] = {
			id = Marker_ID(index + 1),
			provider = PROGRAMMABLE_PROVIDER_ID,
			provider_generation = proposal.definition_generation,
			lane = PROGRAMMABLE_LANE_ID_BASE + Lane_ID(source.lane_index),
			attachment = {
				kind = .Logical_Line,
				logical_line = source.logical_line,
				buffer_revision = 0,
			},
			style_role = source.style_role,
			priority = source.priority,
			representation = source.representation,
			aggregation_label = source.aggregation_label,
			detail = source.detail,
			actions = source.actions,
			action_count = source.action_count,
			stale = source.stale,
		}
	}
	publication, published, publish_failure := marker_store_publish(
		&data.markers,
		Marker_Generation_Proposal {
			id = proposal.marker_generation,
			provider = PROGRAMMABLE_PROVIDER_ID,
			provider_generation = proposal.definition_generation,
			complete = proposal.complete,
			markers = markers[:len(proposal.markers)],
		},
	)
	if !published do return nil, false, publish_failure
	data.descriptor.retained_bytes = u64(size_of(Programmable_Provider_Data)) +
		u64(len(data.storage)) + publication.retained_bytes
	result := data
	data = nil
	return result, true, {}
}

@(private)
programmable_provider_proposal_validate :: proc(
	proposal: Programmable_Provider_Proposal,
) -> (Failure_Context, bool) {
	if proposal.cancelled {
		return Failure_Context{operation = .Prepare, code = .Cancelled}, false
	}
	if proposal.definition_generation == 0 || proposal.marker_generation == 0 ||
	   !proposal.complete || len(proposal.lanes) == 0 ||
	   len(proposal.lanes) > int(MAX_PROGRAMMABLE_LANES_PER_PROVIDER) ||
	   len(proposal.markers) > int(MAX_PROGRAMMABLE_MARKERS_PER_PROVIDER) ||
	   !programmable_display_text_is_valid(proposal.name, MAX_PROGRAMMABLE_PROVIDER_NAME_BYTES, false) ||
	   !programmable_identity_is_valid(proposal.package_name, MAX_PROGRAMMABLE_PACKAGE_NAME_BYTES) {
		return Failure_Context{operation = .Prepare, code = .Invalid_Request}, false
	}
	text_bytes := len(proposal.name) + len(proposal.package_name)
	for lane, index in proposal.lanes {
		if !programmable_identity_is_valid(lane.identity, MAX_PROGRAMMABLE_IDENTITY_BYTES) {
			return Failure_Context{operation = .Prepare, code = .Invalid_Lane}, false
		}
		for prior in proposal.lanes[:index] {
			if prior.identity == lane.identity {
				return Failure_Context{operation = .Prepare, code = .Duplicate_Lane}, false
			}
		}
		definition := Lane_Definition {
			id = PROGRAMMABLE_LANE_ID_BASE + Lane_ID(index),
			provider = PROGRAMMABLE_PROVIDER_ID,
			provider_generation = proposal.definition_generation,
			side = lane.side,
			order = lane.order,
			attachments = lane.attachments,
			width_policy = lane.width_policy,
			minimum_cells = lane.minimum_cells,
			maximum_cells = lane.maximum_cells,
			alignment = lane.alignment,
			visibility = lane.visibility,
			collision = lane.collision,
			priority = lane.priority,
			style_role = lane.style_role,
			separator = lane.separator,
		}
		if !lane_definition_is_valid(definition) {
			return Failure_Context{operation = .Prepare, code = .Invalid_Lane}, false
		}
		text_bytes += len(lane.separator.value) + len(lane.separator.fallback)
	}
	for marker, index in proposal.markers {
		if marker.lane_index >= u8(len(proposal.lanes)) ||
		   !programmable_identity_is_valid(marker.identity, MAX_PROGRAMMABLE_IDENTITY_BYTES) ||
		   len(marker.detail) > MAX_PROGRAMMABLE_DETAIL_BYTES ||
		   marker.action_count > MAX_ACTIONS_PER_MARKER {
			return Failure_Context{operation = .Prepare, code = .Invalid_Marker}, false
		}
		for prior in proposal.markers[:index] {
			if prior.identity == marker.identity {
				return Failure_Context{operation = .Prepare, code = .Duplicate_Marker}, false
			}
		}
		candidate := Marker {
			id = Marker_ID(index + 1),
			provider = PROGRAMMABLE_PROVIDER_ID,
			provider_generation = proposal.definition_generation,
			lane = PROGRAMMABLE_LANE_ID_BASE + Lane_ID(marker.lane_index),
			attachment = {kind = .Logical_Line, logical_line = marker.logical_line},
			style_role = marker.style_role,
			priority = marker.priority,
			representation = marker.representation,
			aggregation_label = marker.aggregation_label,
			detail = marker.detail,
			actions = marker.actions,
			action_count = marker.action_count,
			stale = marker.stale,
		}
		if !marker_is_valid(candidate) {
			return Failure_Context{operation = .Prepare, code = .Invalid_Marker}, false
		}
		text_bytes += len(marker.identity) + len(marker.representation.value) +
			len(marker.representation.fallback) + len(marker.aggregation_label) + len(marker.detail)
	}
	if text_bytes > MAX_PROGRAMMABLE_TEXT_BYTES {
		return Failure_Context {
			operation = .Prepare,
			code = .Text_Limit,
			limit = MAX_PROGRAMMABLE_TEXT_BYTES,
			actual = u64(text_bytes),
		}, false
	}
	return {}, true
}

@(private)
programmable_provider_data_close :: proc(data: ^Programmable_Provider_Data) {
	if data == nil || data.allocator.procedure == nil do return
	allocator := data.allocator
	if data.markers.allocator.procedure != nil do marker_store_close(&data.markers)
	if data.storage != nil do delete(data.storage, allocator)
	free(data, allocator)
}

@(private)
programmable_copy_text :: proc(storage: []u8, cursor: int, value: string) -> (string, int) {
	if len(value) == 0 do return "", cursor
	copy(storage[cursor:cursor + len(value)], transmute([]u8)value)
	return string(storage[cursor:cursor + len(value)]), cursor + len(value)
}

@(private)
programmable_identity_is_valid :: proc(value: string, maximum: int) -> bool {
	if len(value) == 0 || len(value) > maximum || !utf8.valid_string(value) do return false
	for byte, index in transmute([]u8)value {
		valid := (byte >= 'a' && byte <= 'z') || (byte >= '0' && byte <= '9') || byte == '-'
		if !valid || (byte == '-' && (index == 0 || index == len(value) - 1)) do return false
	}
	return true
}

@(private)
programmable_display_text_is_valid :: proc(value: string, maximum: int, empty_allowed: bool) -> bool {
	if (!empty_allowed && len(value) == 0) || len(value) > maximum || !utf8.valid_string(value) {
		return false
	}
	for rune in value {
		if rune < 32 || (rune >= 127 && rune <= 159) do return false
	}
	return true
}

@(private)
programmable_registry_is_open :: proc(registry: ^Programmable_Registry) -> bool {
	return registry != nil && registry.allocator.procedure != nil && !registry.closed
}

@(private)
programmable_registry_reject :: proc(
	registry: ^Programmable_Registry,
	failure: Failure_Context,
) -> Failure_Context {
	if programmable_registry_is_open(registry) do registry.latest_failure = failure
	return failure
}

@(private)
registry_generation :: proc(registry: ^Programmable_Registry) -> u64 {
	if registry == nil do return 0
	return registry.generation
}

@(private)
registry_active_turns :: proc(registry: ^Programmable_Registry) -> u64 {
	if registry == nil do return 0
	return u64(registry.active_turns)
}
