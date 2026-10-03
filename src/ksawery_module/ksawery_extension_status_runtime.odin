// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import bridge "../ksawery_bridge"
import "../ksawery"
import "base:runtime"
import "core:encoding/endian"
import "core:os"

/* KSAWERY_STATUS_OBSERVATION_HEADER_BYTES is the fixed copied observation header width. */
KSAWERY_STATUS_OBSERVATION_HEADER_BYTES :: 64
/* KSAWERY_STATUS_OBSERVATION_PATH_BYTES is one fixed copied Status path width. */
KSAWERY_STATUS_OBSERVATION_PATH_BYTES :: 32
/* KSAWERY_STATUS_PROPOSAL_HEADER_BYTES is the fixed provider proposal header width. */
KSAWERY_STATUS_PROPOSAL_HEADER_BYTES :: 104
/* KSAWERY_STATUS_PROPOSAL_SECTION_BYTES is one fixed contributed section width. */
KSAWERY_STATUS_PROPOSAL_SECTION_BYTES :: 96
/* KSAWERY_STATUS_PROPOSAL_ITEM_BYTES is one fixed contributed item width. */
KSAWERY_STATUS_PROPOSAL_ITEM_BYTES :: 128
/* KSAWERY_STATUS_PROPOSAL_METADATA_BYTES is one fixed contributed metadata width. */
KSAWERY_STATUS_PROPOSAL_METADATA_BYTES :: 40

/* Ksawery_Extension_Status_Data owns one complete decoded provider generation. */
Ksawery_Extension_Status_Data :: struct {
	generation: ksawery.Extension_Status_Generation,
	sections:   []ksawery.Extension_Status_Section,
	items:      []ksawery.Extension_Status_Item,
	metadata:   []ksawery.Extension_Status_Metadata,
	allocator:  runtime.Allocator,
}

/* ksawery_extension_status_refresh evaluates and atomically publishes one projection. */
ksawery_extension_status_refresh :: proc(
	registry: ^Ksawery_Extension_Provider_Registry,
	host: ^Host_Context,
	observation: ^ksawery.Status_Observation,
	allocator: runtime.Allocator,
) -> bool {
	if !ksawery_extension_provider_registry_is_open(registry) || registry.active == nil ||
	   !registry.active.enabled || host == nil || observation == nil ||
	   allocator.procedure == nil {
		return false
	}
	descriptor, described := ksawery.status_observation_descriptor(observation)
	if !described do return false
	input, encoded := ksawery_extension_status_observation_encode(observation, allocator)
	if !encoded {
		ksawery_extension_status_omit(registry.active)
		_ = ksawery_extension_provider_reject(registry, .Allocation, .Publish)
		return false
	}
	defer delete(input, allocator)
	registry.active.inspection.usage.observation_bytes = u64(len(input))
	if u64(len(input)) > registry.active.limits.observation_bytes {
		ksawery_extension_status_omit(registry.active)
		_ = ksawery_extension_provider_reject(registry, .Observation_Limit, .Publish)
		return false
	}
	scope := ksawery.Extension_Turn_Scope {
		turn = ksawery.Extension_Turn_ID(descriptor.generation),
		contributor = registry.active.inspection.handle,
		repository = descriptor.repository,
		repository_generation = ksawery.Repository_Generation(descriptor.generation),
		worktree_generation = ksawery.Worktree_Generation(descriptor.generation),
		observation_generation = descriptor.generation,
		surface = .Status,
		surface_generation = ksawery.Extension_Surface_Generation(descriptor.generation),
		selection_generation = 1,
		target = {},
		capability_generation = 1,
		owner_thread = u64(os.get_current_thread_id()),
		deadline_ns = registry.active.limits.turn_deadline_ns,
		callback_budget = registry.active.limits.callbacks_per_turn,
	}
	capability, began, _ := ksawery_extension_provider_turn_begin(
		registry, scope, {.Inspect, .Present},
	)
	if !began {
		ksawery_extension_status_omit(registry.active)
		return false
	}
	defer ksawery_extension_provider_turn_end(registry)
	authorized, _ := ksawery_extension_provider_authorize(
		registry, capability, registry.active.active_scope, scope.owner_thread,
		.Present, 0, 0,
	)
	if !authorized {
		ksawery_extension_status_omit(registry.active)
		return false
	}
	output, output_error := make([]u8, int(ksawery.DEFAULT_EXTENSION_STATUS_COPY_BYTES), allocator)
	if output_error != nil {
		ksawery_extension_status_omit(registry.active)
		_ = ksawery_extension_provider_reject(registry, .Allocation, .Publish)
		return false
	}
	defer delete(output, allocator)
	output_length, projected := host_provider_invoke(
		host, "source-control.status-projection", 0, 0, "", input, output,
	)
	registry.active.inspection.usage.result_bytes = output_length
	if !projected {
		ksawery_extension_status_omit(registry.active)
		_ = ksawery_extension_provider_reject(registry, .Provider_Exception, .Publish)
		return false
	}
	if output_length == 0 {
		ksawery_extension_status_omit(registry.active)
		return true
	}
	return ksawery_extension_status_publish(
		registry, output[:int(output_length)], descriptor,
	)
}

/* ksawery_extension_status_publish decodes and atomically replaces one publication. */
ksawery_extension_status_publish :: proc(
	registry: ^Ksawery_Extension_Provider_Registry,
	input: []u8,
	descriptor: ksawery.Observation_Descriptor,
) -> bool {
	if !ksawery_extension_provider_registry_is_open(registry) || registry.active == nil ||
	   !registry.active.enabled {
		return false
	}
	if len(input) == 0 {
		ksawery_extension_status_omit(registry.active)
		return true
	}
	input_bytes := u64(len(input))
	if input_bytes > registry.active.limits.result_bytes {
		ksawery_extension_status_omit(registry.active)
		_ = ksawery_extension_provider_reject(registry, .Result_Limit, .Publish)
		return false
	}
	if input_bytes > registry.active.limits.provider_value_bytes {
		ksawery_extension_status_omit(registry.active)
		_ = ksawery_extension_provider_reject(registry, .Provider_Value_Limit, .Publish)
		return false
	}
	candidate, decoded := ksawery_extension_status_decode(
		registry.active, input, descriptor, registry.allocator,
	)
	if !decoded {
		ksawery_extension_status_omit(registry.active)
		_ = ksawery_extension_provider_reject(registry, .Invalid_Declaration, .Publish)
		return false
	}
	candidate_bytes := ksawery_extension_status_data_bytes(candidate)
	prior := registry.active.status
	prior_bytes := ksawery_extension_status_data_bytes(prior)
	retained := registry.active.inspection.usage.retained_native_bytes
	assert(prior_bytes <= retained)
	base_retained := retained - prior_bytes
	if base_retained > registry.active.limits.retained_native_bytes ||
	   candidate_bytes > registry.active.limits.retained_native_bytes - base_retained {
		ksawery_extension_status_data_close(candidate)
		ksawery_extension_status_omit(registry.active)
		_ = ksawery_extension_provider_reject(registry, .Memory_Limit, .Publish)
		return false
	}
	registry.active.status = candidate
	registry.active.inspection.usage.provider_value_bytes = input_bytes
	registry.active.inspection.usage.retained_native_bytes = base_retained + candidate_bytes
	if prior != nil do ksawery_extension_status_data_close(prior)
	return true
}

/* ksawery_extension_status_generation returns only current enabled publication. */
ksawery_extension_status_generation :: proc(
	registry: ^Ksawery_Extension_Provider_Registry,
) -> ^ksawery.Extension_Status_Generation {
	if !ksawery_extension_provider_registry_is_open(registry) || registry.active == nil ||
	   !registry.active.enabled || registry.active.status == nil {
		return nil
	}
	return &registry.active.status.generation
}

@(private)
ksawery_extension_status_observation_encode :: proc(
	observation: ^ksawery.Status_Observation,
	allocator: runtime.Allocator,
) -> ([]u8, bool) {
	descriptor, described := ksawery.status_observation_descriptor(observation)
	path_count, counted := ksawery.status_observation_path_count(observation)
	if !described || !counted do return nil, false
	repository := ksawery.repository_context_string(&descriptor.repository)
	branch_copy := descriptor.branch
	branch := branch_copy.bytes[:branch_copy.length]
	text_bytes := len(repository) + len(branch)
	for index in 0 ..< path_count {
		path, found := ksawery.status_observation_path(observation, index)
		if !found do return nil, false
		path_text, copied := ksawery.status_observation_path_text(observation, path)
		if !copied do return nil, false
		text_bytes += len(path_text)
	}
	total := KSAWERY_STATUS_OBSERVATION_HEADER_BYTES + int(path_count) * KSAWERY_STATUS_OBSERVATION_PATH_BYTES + text_bytes
	input, allocation_error := make([]u8, total, allocator)
	if allocation_error != nil do return nil, false
	cursor := KSAWERY_STATUS_OBSERVATION_HEADER_BYTES + int(path_count) * KSAWERY_STATUS_OBSERVATION_PATH_BYTES
	repository_offset := cursor
	copy(input[cursor:], transmute([]u8)repository)
	cursor += len(repository)
	branch_offset := cursor
	copy(input[cursor:], branch)
	cursor += len(branch)
	header := [?]u64{
		1, u64(total), u64(path_count), u64(descriptor.generation),
		u64(repository_offset), u64(len(repository)), u64(branch_offset), u64(len(branch)),
	}
	ksawery_extension_status_put_words(input, 0, header[:])
	for index in 0 ..< path_count {
		path, _ := ksawery.status_observation_path(observation, index)
		path_text, _ := ksawery.status_observation_path_text(observation, path)
		base := KSAWERY_STATUS_OBSERVATION_HEADER_BYTES + int(index) * KSAWERY_STATUS_OBSERVATION_PATH_BYTES
		record := [?]u64{
			u64(path.id), u64(path.group), u64(cursor), u64(len(path_text)),
		}
		ksawery_extension_status_put_words(input, base, record[:])
		copy(input[cursor:], path_text)
		cursor += len(path_text)
	}
	return input, true
}

@(private)
ksawery_extension_status_decode :: proc(
	provider: ^Ksawery_Extension_Provider_Data,
	input: []u8,
	descriptor: ksawery.Observation_Descriptor,
	allocator: runtime.Allocator,
) -> (^Ksawery_Extension_Status_Data, bool) {
	if provider == nil || len(input) < KSAWERY_STATUS_PROPOSAL_HEADER_BYTES do return nil, false
	header: [13]u64
	for &word, index in header do word = ksawery_extension_status_word(input, index * 8)
	section_count, item_count, metadata_count := header[2], header[3], header[4]
	if header[0] != 1 || header[1] != u64(len(input)) || header[5] != 1 ||
	   header[6] != u64(provider.inspection.handle.generation) || header[7] == 0 ||
	   header[8] != u64(descriptor.generation) ||
	   section_count > u64(ksawery.DEFAULT_EXTENSION_STATUS_SECTIONS_PER_CONTRIBUTOR) ||
	   item_count > u64(ksawery.DEFAULT_EXTENSION_STATUS_ITEMS) ||
	   metadata_count > u64(ksawery.DEFAULT_EXTENSION_STATUS_METADATA) {
		return nil, false
	}
	record_bytes := u64(KSAWERY_STATUS_PROPOSAL_HEADER_BYTES) +
		section_count * KSAWERY_STATUS_PROPOSAL_SECTION_BYTES +
		item_count * KSAWERY_STATUS_PROPOSAL_ITEM_BYTES +
		metadata_count * KSAWERY_STATUS_PROPOSAL_METADATA_BYTES
	if record_bytes > u64(len(input)) do return nil, false
	repository, repository_ok := ksawery_extension_status_text(input, header[9], header[10], record_bytes, u64(ksawery.MAX_REPOSITORY_CONTEXT_BYTES), false)
	contributor_text, contributor_ok := ksawery_extension_status_text(input, header[11], header[12], record_bytes, u64(ksawery.MAX_EXTENSION_IDENTITY_BYTES), false)
	identity_copy := provider.inspection.identity
	repository_copy := descriptor.repository
	if !repository_ok || !contributor_ok || repository != ksawery.repository_context_string(&repository_copy) ||
	   contributor_text != string(identity_copy.bytes[:identity_copy.length]) {
		return nil, false
	}
	data, allocation_error := new(Ksawery_Extension_Status_Data, allocator)
	if allocation_error != nil do return nil, false
	data.allocator = allocator
	defer if data != nil do ksawery_extension_status_data_close(data)
	data.sections, allocation_error = make([]ksawery.Extension_Status_Section, int(section_count), allocator)
	if allocation_error == nil do data.items, allocation_error = make([]ksawery.Extension_Status_Item, int(item_count), allocator)
	if allocation_error == nil do data.metadata, allocation_error = make([]ksawery.Extension_Status_Metadata, int(metadata_count), allocator)
	if allocation_error != nil do return nil, false
	section_offset := KSAWERY_STATUS_PROPOSAL_HEADER_BYTES
	item_offset := section_offset + int(section_count) * KSAWERY_STATUS_PROPOSAL_SECTION_BYTES
	metadata_offset := item_offset + int(item_count) * KSAWERY_STATUS_PROPOSAL_ITEM_BYTES
	for metadata_index in 0 ..< int(metadata_count) {
		base := metadata_offset + metadata_index * KSAWERY_STATUS_PROPOSAL_METADATA_BYTES
		item_index := ksawery_extension_status_word(input, base)
		key, key_ok := ksawery_extension_status_text(input, ksawery_extension_status_word(input, base + 8), ksawery_extension_status_word(input, base + 16), record_bytes, u64(ksawery.MAX_EXTENSION_IDENTITY_BYTES), false)
		value, value_ok := ksawery_extension_status_text(input, ksawery_extension_status_word(input, base + 24), ksawery_extension_status_word(input, base + 32), record_bytes, u64(ksawery.MAX_EXTENSION_STATUS_METADATA_VALUE_BYTES), false)
		if item_index >= item_count || !key_ok || !value_ok ||
		   !ksawery.extension_identity_assign(&data.metadata[metadata_index].key, key) ||
		   !ksawery.extension_status_metadata_value_assign(&data.metadata[metadata_index].value, value) {
			return nil, false
		}
	}
	metadata_cursor: u64
	for item_index in 0 ..< int(item_count) {
		base := item_offset + item_index * KSAWERY_STATUS_PROPOSAL_ITEM_BYTES
		section_index := ksawery_extension_status_word(input, base + 8)
		identity, identity_ok := ksawery_extension_status_text(input, ksawery_extension_status_word(input, base + 16), ksawery_extension_status_word(input, base + 24), record_bytes, u64(ksawery.MAX_EXTENSION_IDENTITY_BYTES), false)
		text, text_ok := ksawery_extension_status_text(input, ksawery_extension_status_word(input, base + 32), ksawery_extension_status_word(input, base + 40), record_bytes, u64(ksawery.MAX_EXTENSION_STATUS_TEXT_BYTES), false)
		detail, detail_ok := ksawery_extension_status_text(input, ksawery_extension_status_word(input, base + 48), ksawery_extension_status_word(input, base + 56), record_bytes, u64(ksawery.MAX_EXTENSION_STATUS_TEXT_BYTES), true)
		style := ksawery_extension_status_word(input, base + 64)
		command, command_ok := ksawery_extension_status_text(input, ksawery_extension_status_word(input, base + 72), ksawery_extension_status_word(input, base + 80), record_bytes, u64(ksawery.MAX_EXTENSION_IDENTITY_BYTES), true)
		first_metadata := ksawery_extension_status_word(input, base + 88)
		metadata_entries := ksawery_extension_status_word(input, base + 96)
		if section_index >= section_count || !identity_ok || !text_ok || !detail_ok || !command_ok ||
		   style == 0 || style > u64(ksawery.Extension_Status_Style.Information) ||
		   metadata_entries > u64(ksawery.MAX_EXTENSION_STATUS_METADATA_PER_ITEM) ||
		   first_metadata != metadata_cursor || metadata_entries > metadata_count - first_metadata ||
		   ksawery_extension_status_word(input, base + 104) != 0 ||
		   ksawery_extension_status_word(input, base + 112) != 0 ||
		   ksawery_extension_status_word(input, base + 120) != 0 {
			return nil, false
		}
		for metadata_index in first_metadata ..< first_metadata + metadata_entries {
			metadata_base := metadata_offset + int(metadata_index) * KSAWERY_STATUS_PROPOSAL_METADATA_BYTES
			if ksawery_extension_status_word(input, metadata_base) != u64(item_index) do return nil, false
		}
		item := &data.items[item_index]
		item.id = ksawery.Extension_Status_Item_ID(ksawery_extension_status_word(input, base))
		if !ksawery.extension_identity_assign(&item.identity, identity) ||
		   !ksawery.extension_status_text_assign(&item.text, text) ||
		   !ksawery.extension_status_text_assign(&item.detail, detail, true) {
			return nil, false
		}
		item.style = ksawery.Extension_Status_Style(style)
		item.metadata = data.metadata[int(first_metadata):int(first_metadata + metadata_entries)]
		if len(command) > 0 {
			command_contribution, found := ksawery_extension_status_command_contribution(provider, command)
			if !found || !ksawery.extension_identity_assign(&item.command.identity, command) do return nil, false
			item.command.present = true
			item.command.contributor = provider.inspection.handle
			item.command.contribution = command_contribution
		}
		metadata_cursor += metadata_entries
	}
	if metadata_cursor != metadata_count do return nil, false
	item_cursor: u64
	for section_index in 0 ..< int(section_count) {
		base := section_offset + section_index * KSAWERY_STATUS_PROPOSAL_SECTION_BYTES
		contribution := ksawery.Contribution_ID(ksawery_extension_status_word(input, base))
		identity, identity_ok := ksawery_extension_status_text(input, ksawery_extension_status_word(input, base + 16), ksawery_extension_status_word(input, base + 24), record_bytes, u64(ksawery.MAX_EXTENSION_IDENTITY_BYTES), false)
		label, label_ok := ksawery_extension_status_text(input, ksawery_extension_status_word(input, base + 32), ksawery_extension_status_word(input, base + 40), record_bytes, u64(ksawery.MAX_EXTENSION_LABEL_BYTES), false)
		first_item := ksawery_extension_status_word(input, base + 48)
		section_items := ksawery_extension_status_word(input, base + 56)
		truncation := ksawery_extension_status_word(input, base + 64)
		visible := ksawery_extension_status_word(input, base + 72)
		if ksawery_extension_status_word(input, base + 8) != u64(section_index) ||
		   !ksawery_extension_status_contribution_is(provider, contribution, .Status_Section) ||
		   !identity_ok || !label_ok || first_item != item_cursor || section_items > item_count - first_item ||
		   section_items > u64(ksawery.DEFAULT_EXTENSION_STATUS_ITEMS_PER_SECTION) ||
		   truncation == 0 || truncation > u64(ksawery.Extension_Status_Truncation.Provider_Limit) ||
		   visible != (1 if section_items > 0 else 0) ||
		   ksawery_extension_status_word(input, base + 80) != 0 ||
		   ksawery_extension_status_word(input, base + 88) != 0 {
			return nil, false
		}
		for item_index in first_item ..< first_item + section_items {
			item_base := item_offset + int(item_index) * KSAWERY_STATUS_PROPOSAL_ITEM_BYTES
			if ksawery_extension_status_word(input, item_base + 8) != u64(section_index) do return nil, false
		}
		section := &data.sections[section_index]
		section.contributor = provider.inspection.handle
		section.contributor_identity = provider.inspection.identity
		section.contribution = contribution
		section.generation = ksawery.Extension_Status_Section_Generation(header[7])
		section.repository = descriptor.repository
		section.observation_generation = descriptor.generation
		section.items = data.items[int(first_item):int(first_item + section_items)]
		section.truncation = ksawery.Extension_Status_Truncation(truncation)
		if !ksawery.extension_identity_assign(&section.identity, identity) ||
		   !ksawery.extension_label_assign(&section.label, label) {
			return nil, false
		}
		item_cursor += section_items
	}
	if item_cursor != item_count do return nil, false
	data.generation = {
		contributor = provider.inspection.handle,
		contributor_identity = provider.inspection.identity,
		generation = ksawery.Extension_Status_Section_Generation(header[7]),
		repository = descriptor.repository,
		observation_generation = descriptor.generation,
		sections = data.sections,
	}
	_, failure := ksawery.extension_status_generation_validate(data.generation)
	if failure.code != .None do return nil, false
	result := data
	data = nil
	return result, true
}

@(private)
ksawery_extension_status_contribution_is :: proc(
	provider: ^Ksawery_Extension_Provider_Data,
	id: ksawery.Contribution_ID,
	kind: ksawery.Contribution_Kind,
) -> bool {
	for contribution in provider.contributions {
		status_observation := u64(1) << u64(ksawery.Extension_Observation_Family.Status)
		inspect_authority := u64(1) << u64(ksawery.Extension_Authority.Inspect)
		present_authority := u64(1) << u64(ksawery.Extension_Authority.Present)
		if contribution.contribution_id == u64(id) && contribution.kind == u64(kind) &&
		   contribution.required_observations & status_observation != 0 &&
		   contribution.requested_authorities & inspect_authority != 0 &&
		   contribution.requested_authorities & present_authority != 0 {
			return true
		}
	}
	return false
}

@(private)
ksawery_extension_status_command_contribution :: proc(
	provider: ^Ksawery_Extension_Provider_Data,
	identity: string,
) -> (ksawery.Contribution_ID, bool) {
	for contribution in provider.contributions {
		if contribution.kind != u64(ksawery.Contribution_Kind.Command) do continue
		status_observation := u64(1) << u64(ksawery.Extension_Observation_Family.Status)
		invoke_authority := u64(1) << u64(ksawery.Extension_Authority.Invoke_Declared_Command)
		if contribution.required_observations & status_observation == 0 ||
		   contribution.requested_authorities & invoke_authority == 0 {
			continue
		}
		text := bridge.ksawery_extension_text(provider.text, contribution.identity_offset, contribution.identity_bytes)
		if string(text) == identity do return ksawery.Contribution_ID(contribution.contribution_id), true
	}
	return 0, false
}

@(private)
ksawery_extension_status_text :: proc(
	input: []u8,
	offset, length, minimum_offset, maximum: u64,
	allow_empty: bool,
) -> (string, bool) {
	if length == 0 do return "", allow_empty && offset == 0
	if length > maximum || offset < minimum_offset || offset > u64(len(input)) ||
	   length > u64(len(input)) - offset {
		return "", false
	}
	return string(input[int(offset):int(offset + length)]), true
}

@(private)
ksawery_extension_status_word :: proc(input: []u8, offset: int) -> u64 {
	value, ok := endian.get_u64(input[offset:], .Little)
	assert(ok)
	return value
}

@(private)
ksawery_extension_status_put_words :: proc(input: []u8, offset: int, values: []u64) {
	for value, index in values do assert(endian.put_u64(input[offset + index * 8:], .Little, value))
}

/* ksawery_extension_status_data_close releases one owned decoded Status generation. */
ksawery_extension_status_data_close :: proc(data: ^Ksawery_Extension_Status_Data) {
	if data == nil do return
	allocator := data.allocator
	delete(data.sections, allocator)
	delete(data.items, allocator)
	delete(data.metadata, allocator)
	free(data, allocator)
}

@(private)
ksawery_extension_status_data_bytes :: proc(data: ^Ksawery_Extension_Status_Data) -> u64 {
	if data == nil do return 0
	return u64(
		size_of(Ksawery_Extension_Status_Data) +
		len(data.sections) * size_of(ksawery.Extension_Status_Section) +
		len(data.items) * size_of(ksawery.Extension_Status_Item) +
		len(data.metadata) * size_of(ksawery.Extension_Status_Metadata),
	)
}

@(private)
ksawery_extension_status_omit :: proc(provider: ^Ksawery_Extension_Provider_Data) {
	if provider == nil do return
	status_bytes := ksawery_extension_status_data_bytes(provider.status)
	assert(status_bytes <= provider.inspection.usage.retained_native_bytes)
	provider.inspection.usage.retained_native_bytes -= status_bytes
	provider.inspection.usage.provider_value_bytes = 0
	if provider.status != nil do ksawery_extension_status_data_close(provider.status)
	provider.status = nil
}
