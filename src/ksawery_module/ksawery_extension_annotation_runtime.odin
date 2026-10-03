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

/* KSAWERY_ANNOTATION_OBSERVATION_HEADER_BYTES is the fixed copied observation header width. */
KSAWERY_ANNOTATION_OBSERVATION_HEADER_BYTES :: 64
/* KSAWERY_ANNOTATION_OBSERVATION_TARGET_BYTES is one fixed semantic target width. */
KSAWERY_ANNOTATION_OBSERVATION_TARGET_BYTES :: 40
/* KSAWERY_ANNOTATION_PROPOSAL_HEADER_BYTES is the fixed provider proposal header width. */
KSAWERY_ANNOTATION_PROPOSAL_HEADER_BYTES :: 120
/* KSAWERY_ANNOTATION_PROPOSAL_RECORD_BYTES is one fixed annotation record width. */
KSAWERY_ANNOTATION_PROPOSAL_RECORD_BYTES :: 152
/* MAX_KSAWERY_ANNOTATION_OBSERVATION_TARGETS bounds one copied target set. */
MAX_KSAWERY_ANNOTATION_OBSERVATION_TARGETS :: 4_096

/* Ksawery_Extension_Annotation_Data owns one complete decoded provider generation. */
Ksawery_Extension_Annotation_Data :: struct {
	generation:  ksawery.Extension_Annotation_Generation,
	annotations: []ksawery.Extension_Annotation,
	input_bytes: u64,
	allocator:   runtime.Allocator,
}

/* ksawery_extension_annotation_refresh evaluates and atomically publishes one target set. */
ksawery_extension_annotation_refresh :: proc(
	registry: ^Ksawery_Extension_Provider_Registry,
	host: ^Host_Context,
	observation: ksawery.Extension_Annotation_Observation,
	targets: []ksawery.Extension_Annotation_Target,
	allocator: runtime.Allocator,
) -> bool {
	if !ksawery_extension_provider_registry_is_open(registry) || registry.active == nil ||
	   !registry.active.enabled || host == nil || allocator.procedure == nil ||
	   !ksawery.extension_annotation_observation_is_valid(observation) {
		return false
	}
	input, encoded := ksawery_extension_annotation_observation_encode(
		observation, targets, allocator,
	)
	if !encoded {
		ksawery_extension_annotation_omit(registry.active, observation.family)
		_ = ksawery_extension_provider_reject(registry, .Allocation, .Publish)
		return false
	}
	defer delete(input, allocator)
	registry.active.inspection.usage.observation_bytes = u64(len(input))
	if u64(len(input)) > registry.active.limits.observation_bytes {
		ksawery_extension_annotation_omit(registry.active, observation.family)
		_ = ksawery_extension_provider_reject(registry, .Observation_Limit, .Publish)
		return false
	}
	scope := ksawery.Extension_Turn_Scope {
		turn = ksawery.Extension_Turn_ID(observation.generation),
		contributor = registry.active.inspection.handle,
		repository = observation.repository,
		repository_generation = ksawery.Repository_Generation(observation.generation),
		worktree_generation = ksawery.Worktree_Generation(observation.generation),
		observation_generation = ksawery.Observation_Generation(observation.generation),
		surface = ksawery_extension_annotation_surface(observation.family),
		surface_generation = ksawery.Extension_Surface_Generation(observation.generation),
		selection_generation = 1,
		capability_generation = 1,
		owner_thread = u64(os.get_current_thread_id()),
		deadline_ns = registry.active.limits.turn_deadline_ns,
		callback_budget = registry.active.limits.callbacks_per_turn,
	}
	capability, began, _ := ksawery_extension_provider_turn_begin(
		registry, scope, {.Inspect, .Present},
	)
	if !began {
		ksawery_extension_annotation_omit(registry.active, observation.family)
		return false
	}
	defer ksawery_extension_provider_turn_end(registry)
	authorized, _ := ksawery_extension_provider_authorize(
		registry, capability, registry.active.active_scope, scope.owner_thread,
		.Present, 0, 0,
	)
	if !authorized {
		ksawery_extension_annotation_omit(registry.active, observation.family)
		return false
	}
	output, allocation_error := make(
		[]u8,
		int(ksawery.DEFAULT_EXTENSION_ANNOTATION_COPY_BYTES),
		allocator,
	)
	if allocation_error != nil {
		ksawery_extension_annotation_omit(registry.active, observation.family)
		_ = ksawery_extension_provider_reject(registry, .Allocation, .Publish)
		return false
	}
	defer delete(output, allocator)
	output_length, projected := host_provider_invoke(
		host, "source-control.annotation-projection", 0, 0, "", input, output,
	)
	registry.active.inspection.usage.result_bytes = output_length
	if !projected {
		ksawery_extension_annotation_omit(registry.active, observation.family)
		_ = ksawery_extension_provider_reject(registry, .Provider_Exception, .Publish)
		return false
	}
	if output_length == 0 {
		ksawery_extension_annotation_omit(registry.active, observation.family)
		return true
	}
	return ksawery_extension_annotation_publish(
		registry, output[:int(output_length)], observation, targets,
	)
}

/* ksawery_extension_annotation_publish decodes and atomically replaces one family. */
ksawery_extension_annotation_publish :: proc(
	registry: ^Ksawery_Extension_Provider_Registry,
	input: []u8,
	observation: ksawery.Extension_Annotation_Observation,
	targets: []ksawery.Extension_Annotation_Target,
) -> bool {
	if !ksawery_extension_provider_registry_is_open(registry) || registry.active == nil ||
	   !registry.active.enabled || !ksawery.extension_annotation_observation_is_valid(observation) {
		return false
	}
	if len(input) == 0 {
		ksawery_extension_annotation_omit(registry.active, observation.family)
		return true
	}
	input_bytes := u64(len(input))
	if input_bytes > registry.active.limits.result_bytes ||
	   input_bytes > registry.active.limits.provider_value_bytes {
		ksawery_extension_annotation_omit(registry.active, observation.family)
		code := ksawery.Extension_Failure_Code.Result_Limit
		if input_bytes > registry.active.limits.provider_value_bytes do code = .Provider_Value_Limit
		_ = ksawery_extension_provider_reject(registry, code, .Publish)
		return false
	}
	candidate, decoded := ksawery_extension_annotation_decode(
		registry.active, input, observation, targets, registry.allocator,
	)
	if !decoded {
		ksawery_extension_annotation_omit(registry.active, observation.family)
		_ = ksawery_extension_provider_reject(registry, .Invalid_Declaration, .Publish)
		return false
	}
	candidate.input_bytes = input_bytes
	index := int(observation.family)
	prior := registry.active.annotations[index]
	prior_bytes := ksawery_extension_annotation_data_bytes(prior)
	candidate_bytes := ksawery_extension_annotation_data_bytes(candidate)
	retained := registry.active.inspection.usage.retained_native_bytes
	assert(prior_bytes <= retained)
	base_retained := retained - prior_bytes
	if base_retained > registry.active.limits.retained_native_bytes ||
	   candidate_bytes > registry.active.limits.retained_native_bytes - base_retained {
		ksawery_extension_annotation_data_close(candidate)
		ksawery_extension_annotation_omit(registry.active, observation.family)
		_ = ksawery_extension_provider_reject(registry, .Memory_Limit, .Publish)
		return false
	}
	registry.active.annotations[index] = candidate
	registry.active.inspection.usage.retained_native_bytes = base_retained + candidate_bytes
	registry.active.inspection.usage.provider_value_bytes =
		ksawery_extension_annotation_provider_value_bytes(registry.active)
	if prior != nil do ksawery_extension_annotation_data_close(prior)
	return true
}

/* ksawery_extension_annotation_generation returns only one current enabled family. */
ksawery_extension_annotation_generation :: proc(
	registry: ^Ksawery_Extension_Provider_Registry,
	family: ksawery.Extension_Observation_Family,
) -> ^ksawery.Extension_Annotation_Generation {
	if !ksawery_extension_provider_registry_is_open(registry) || registry.active == nil ||
	   !registry.active.enabled || family > .Process {
		return nil
	}
	data := registry.active.annotations[int(family)]
	if data == nil do return nil
	return &data.generation
}

@(private)
ksawery_extension_annotation_observation_encode :: proc(
	observation: ksawery.Extension_Annotation_Observation,
	targets: []ksawery.Extension_Annotation_Target,
	allocator: runtime.Allocator,
) -> ([]u8, bool) {
	if !ksawery.extension_annotation_observation_is_valid(observation) ||
	   len(targets) > MAX_KSAWERY_ANNOTATION_OBSERVATION_TARGETS || allocator.procedure == nil {
		return nil, false
	}
	observation_copy := observation
	repository := ksawery.repository_context_string(&observation_copy.repository)
	identity_bytes := 0
	for target, index in targets {
		if !ksawery.extension_annotation_target_is_valid(target) ||
		   target.generation != observation.generation ||
		   !ksawery_extension_annotation_family_matches(target.family, observation.family) {
			return nil, false
		}
		for prior in 0 ..< index {
			if targets[prior] == target do return nil, false
		}
		identity_bytes += int(target.length)
	}
	record_bytes := KSAWERY_ANNOTATION_OBSERVATION_HEADER_BYTES +
		len(targets) * KSAWERY_ANNOTATION_OBSERVATION_TARGET_BYTES
	total := record_bytes + len(repository) + identity_bytes
	input, allocation_error := make([]u8, total, allocator)
	if allocation_error != nil do return nil, false
	cursor := record_bytes
	repository_offset := cursor
	copy(input[cursor:], transmute([]u8)repository)
	cursor += len(repository)
	header := [?]u64 {
		1, u64(total), u64(len(targets)), u64(observation.family),
		observation.generation, u64(repository_offset), u64(len(repository)), 0,
	}
	ksawery_extension_annotation_put_words(input, 0, header[:])
	for target, index in targets {
		base := KSAWERY_ANNOTATION_OBSERVATION_HEADER_BYTES +
			index * KSAWERY_ANNOTATION_OBSERVATION_TARGET_BYTES
		record := [?]u64 {
			u64(target.family), target.generation, u64(cursor), u64(target.length), 0,
		}
		ksawery_extension_annotation_put_words(input, base, record[:])
		target_copy := target
		copy(input[cursor:], target_copy.identity[:target_copy.length])
		cursor += int(target.length)
	}
	return input, true
}

@(private)
ksawery_extension_annotation_decode :: proc(
	provider: ^Ksawery_Extension_Provider_Data,
	input: []u8,
	observation: ksawery.Extension_Annotation_Observation,
	targets: []ksawery.Extension_Annotation_Target,
	allocator: runtime.Allocator,
) -> (^Ksawery_Extension_Annotation_Data, bool) {
	if provider == nil || len(input) < KSAWERY_ANNOTATION_PROPOSAL_HEADER_BYTES do return nil, false
	header: [15]u64
	for &value, index in header do value = ksawery_extension_annotation_word(input, index * 8)
	annotation_count := header[2]
	if header[0] != 1 || header[1] != u64(len(input)) ||
	   annotation_count > u64(ksawery.DEFAULT_EXTENSION_ANNOTATIONS_PER_CONTRIBUTOR) ||
	   header[3] != u64(provider.inspection.handle.generation) || header[4] == 0 ||
	   header[5] != u64(observation.family) || header[6] != observation.generation ||
	   header[7] == 0 || header[7] > u64(ksawery.Extension_Annotation_Truncation.Provider_Limit) ||
	   header[13] != 0 || header[14] != 0 {
		return nil, false
	}
	record_bytes := u64(KSAWERY_ANNOTATION_PROPOSAL_HEADER_BYTES) +
		annotation_count * KSAWERY_ANNOTATION_PROPOSAL_RECORD_BYTES
	if record_bytes > u64(len(input)) do return nil, false
	repository, repository_ok := ksawery_extension_annotation_text(
		input, header[8], header[9], record_bytes, u64(ksawery.MAX_REPOSITORY_CONTEXT_BYTES), false,
	)
	contributor, contributor_ok := ksawery_extension_annotation_text(
		input, header[10], header[11], record_bytes, u64(ksawery.MAX_EXTENSION_IDENTITY_BYTES), false,
	)
	identity_copy := provider.inspection.identity
	observation_copy := observation
	if !repository_ok || !contributor_ok || header[12] != 0 ||
	   repository != ksawery.repository_context_string(&observation_copy.repository) ||
	   contributor != string(identity_copy.bytes[:identity_copy.length]) {
		return nil, false
	}
	data, allocation_error := new(Ksawery_Extension_Annotation_Data, allocator)
	if allocation_error != nil do return nil, false
	data.allocator = allocator
	defer if data != nil do ksawery_extension_annotation_data_close(data)
	data.annotations, allocation_error = make(
		[]ksawery.Extension_Annotation, int(annotation_count), allocator,
	)
	if allocation_error != nil do return nil, false
	for annotation_index in 0 ..< int(annotation_count) {
		base := KSAWERY_ANNOTATION_PROPOSAL_HEADER_BYTES +
			annotation_index * KSAWERY_ANNOTATION_PROPOSAL_RECORD_BYTES
		id := ksawery.Extension_Annotation_ID(ksawery_extension_annotation_word(input, base))
		contribution := ksawery.Contribution_ID(ksawery_extension_annotation_word(input, base + 8))
		target_family := ksawery_extension_annotation_word(input, base + 16)
		target_generation := ksawery_extension_annotation_word(input, base + 24)
		target_identity, target_ok := ksawery_extension_annotation_bytes(
			input,
			ksawery_extension_annotation_word(input, base + 32),
			ksawery_extension_annotation_word(input, base + 40),
			record_bytes,
			u64(ksawery.MAX_EXTENSION_ANNOTATION_TARGET_BYTES),
			false,
		)
		identity, identity_ok := ksawery_extension_annotation_text(
			input,
			ksawery_extension_annotation_word(input, base + 48),
			ksawery_extension_annotation_word(input, base + 56),
			record_bytes,
			u64(ksawery.MAX_EXTENSION_IDENTITY_BYTES),
			false,
		)
		label, label_ok := ksawery_extension_annotation_text(
			input,
			ksawery_extension_annotation_word(input, base + 64),
			ksawery_extension_annotation_word(input, base + 72),
			record_bytes,
			u64(ksawery.MAX_EXTENSION_LABEL_BYTES),
			true,
		)
		detail, detail_ok := ksawery_extension_annotation_text(
			input,
			ksawery_extension_annotation_word(input, base + 80),
			ksawery_extension_annotation_word(input, base + 88),
			record_bytes,
			u64(ksawery.MAX_EXTENSION_ANNOTATION_DETAIL_BYTES),
			true,
		)
		severity := ksawery_extension_annotation_word(input, base + 96)
		style := ksawery_extension_annotation_word(input, base + 104)
		command, command_ok := ksawery_extension_annotation_text(
			input,
			ksawery_extension_annotation_word(input, base + 112),
			ksawery_extension_annotation_word(input, base + 120),
			record_bytes,
			u64(ksawery.MAX_EXTENSION_IDENTITY_BYTES),
			true,
		)
		flags := ksawery_extension_annotation_word(input, base + 128)
		if !target_ok || !identity_ok || !label_ok || !detail_ok || !command_ok ||
		   target_family == 0 || target_family > u64(ksawery.Extension_Annotation_Target_Family.Process) ||
		   target_generation != observation.generation || severity > u64(ksawery.Extension_Annotation_Severity.Error) ||
		   style > u64(ksawery.Extension_Annotation_Style.Information) || flags & ~u64(3) != 0 ||
		   (flags & 1 != 0) != (len(label) > 0) || (flags & 2 != 0) != (len(command) > 0) ||
		   ksawery_extension_annotation_word(input, base + 136) != 0 ||
		   ksawery_extension_annotation_word(input, base + 144) != 0 ||
		   !ksawery_extension_annotation_contribution_is(
			provider, contribution, observation.family,
		) {
			return nil, false
		}
		annotation := &data.annotations[annotation_index]
		annotation.id = id
		annotation.contribution = contribution
		annotation.severity = ksawery.Extension_Annotation_Severity(severity)
		annotation.style = ksawery.Extension_Annotation_Style(style)
		if !ksawery.extension_identity_assign(&annotation.identity, identity) ||
		   !ksawery.extension_annotation_target_assign(
			&annotation.target,
			ksawery.Extension_Annotation_Target_Family(target_family),
			target_generation,
			target_identity,
		) || !ksawery_extension_annotation_target_is_exposed(annotation.target, targets) ||
		   !ksawery.extension_annotation_detail_assign(&annotation.detail, detail) {
			return nil, false
		}
		if len(label) > 0 {
			annotation.label_present = true
			if !ksawery.extension_label_assign(&annotation.label, label) do return nil, false
		}
		if len(command) > 0 {
			command_contribution, found := ksawery_extension_annotation_command_contribution(
				provider, command, observation.family,
			)
			if !found || !ksawery.extension_identity_assign(&annotation.command.identity, command) {
				return nil, false
			}
			annotation.command.present = true
			annotation.command.contributor = provider.inspection.handle
			annotation.command.contribution = command_contribution
		}
	}
	data.generation = {
		contributor = provider.inspection.handle,
		contributor_identity = provider.inspection.identity,
		generation = ksawery.Extension_Annotation_Generation_ID(header[4]),
		observation = observation,
		annotations = data.annotations,
		truncation = ksawery.Extension_Annotation_Truncation(header[7]),
	}
	_, failure := ksawery.extension_annotation_generation_validate(data.generation)
	if failure.code != .None do return nil, false
	result := data
	data = nil
	return result, true
}

@(private)
ksawery_extension_annotation_contribution_is :: proc(
	provider: ^Ksawery_Extension_Provider_Data,
	id: ksawery.Contribution_ID,
	family: ksawery.Extension_Observation_Family,
) -> bool {
	for contribution in provider.contributions {
		observation := u64(1) << u64(family)
		inspect_authority := u64(1) << u64(ksawery.Extension_Authority.Inspect)
		present_authority := u64(1) << u64(ksawery.Extension_Authority.Present)
		if contribution.contribution_id == u64(id) &&
		   contribution.kind == u64(ksawery.Contribution_Kind.Annotation) &&
		   contribution.required_observations & observation != 0 &&
		   contribution.requested_authorities & inspect_authority != 0 &&
		   contribution.requested_authorities & present_authority != 0 {
			return true
		}
	}
	return false
}

@(private)
ksawery_extension_annotation_command_contribution :: proc(
	provider: ^Ksawery_Extension_Provider_Data,
	identity: string,
	family: ksawery.Extension_Observation_Family,
) -> (ksawery.Contribution_ID, bool) {
	for contribution in provider.contributions {
		if contribution.kind != u64(ksawery.Contribution_Kind.Command) do continue
		observation := u64(1) << u64(family)
		invoke_authority := u64(1) << u64(ksawery.Extension_Authority.Invoke_Declared_Command)
		if contribution.required_observations & observation == 0 ||
		   contribution.requested_authorities & invoke_authority == 0 {
			continue
		}
		text := bridge.ksawery_extension_text(
			provider.text, contribution.identity_offset, contribution.identity_bytes,
		)
		if string(text) == identity do return ksawery.Contribution_ID(contribution.contribution_id), true
	}
	return 0, false
}

@(private)
ksawery_extension_annotation_target_is_exposed :: proc(
	target: ksawery.Extension_Annotation_Target,
	targets: []ksawery.Extension_Annotation_Target,
) -> bool {
	for candidate in targets {
		if candidate == target do return true
	}
	return false
}

@(private)
ksawery_extension_annotation_family_matches :: proc(
	target: ksawery.Extension_Annotation_Target_Family,
	observation: ksawery.Extension_Observation_Family,
) -> bool {
	switch target {
	case .Path, .Diff_Unit:            return observation == .Status
	case .Revision, .Revision_Range:   return observation == .History
	case .Ref, .Remote:                return observation == .Refs
	case .Conflict:                    return observation == .Conflict || observation == .Sequence
	case .Sequence:                    return observation == .Sequence
	case .Process:                     return observation == .Process
	case .Invalid:                     return false
	}
	return false
}

@(private)
ksawery_extension_annotation_surface :: proc(
	family: ksawery.Extension_Observation_Family,
) -> ksawery.Extension_Surface {
	switch family {
	case .Status:   return .Status
	case .History:  return .History
	case .Refs:     return .Refs
	case .Sequence: return .Sequence
	case .Conflict: return .Conflict
	case .Process:  return .Process
	}
	return .Invalid
}

@(private)
ksawery_extension_annotation_bytes :: proc(
	input: []u8,
	offset, length, minimum_offset, maximum: u64,
	allow_empty: bool,
) -> ([]u8, bool) {
	if length == 0 do return nil, allow_empty && offset == 0
	if length > maximum || offset < minimum_offset || offset > u64(len(input)) ||
	   length > u64(len(input)) - offset {
		return nil, false
	}
	return input[int(offset):int(offset + length)], true
}

@(private)
ksawery_extension_annotation_text :: proc(
	input: []u8,
	offset, length, minimum_offset, maximum: u64,
	allow_empty: bool,
) -> (string, bool) {
	bytes, ok := ksawery_extension_annotation_bytes(
		input, offset, length, minimum_offset, maximum, allow_empty,
	)
	if !ok do return "", false
	return string(bytes), true
}

@(private)
ksawery_extension_annotation_word :: proc(input: []u8, offset: int) -> u64 {
	value, ok := endian.get_u64(input[offset:], .Little)
	assert(ok)
	return value
}

@(private)
ksawery_extension_annotation_put_words :: proc(input: []u8, offset: int, values: []u64) {
	for value, index in values do assert(endian.put_u64(input[offset + index * 8:], .Little, value))
}

/* ksawery_extension_annotation_data_close releases one owned decoded annotation generation. */
ksawery_extension_annotation_data_close :: proc(data: ^Ksawery_Extension_Annotation_Data) {
	if data == nil do return
	allocator := data.allocator
	delete(data.annotations, allocator)
	free(data, allocator)
}

@(private)
ksawery_extension_annotation_data_bytes :: proc(data: ^Ksawery_Extension_Annotation_Data) -> u64 {
	if data == nil do return 0
	return u64(
		size_of(Ksawery_Extension_Annotation_Data) +
		len(data.annotations) * size_of(ksawery.Extension_Annotation),
	)
}

@(private)
ksawery_extension_annotation_provider_value_bytes :: proc(
	provider: ^Ksawery_Extension_Provider_Data,
) -> u64 {
	if provider == nil do return 0
	result: u64
	for data in provider.annotations {
		if data != nil do result += data.input_bytes
	}
	return result
}

@(private)
ksawery_extension_annotation_omit :: proc(
	provider: ^Ksawery_Extension_Provider_Data,
	family: ksawery.Extension_Observation_Family,
) {
	if provider == nil || family > .Process do return
	index := int(family)
	data := provider.annotations[index]
	data_bytes := ksawery_extension_annotation_data_bytes(data)
	assert(data_bytes <= provider.inspection.usage.retained_native_bytes)
	provider.inspection.usage.retained_native_bytes -= data_bytes
	if data != nil do ksawery_extension_annotation_data_close(data)
	provider.annotations[index] = nil
	provider.inspection.usage.provider_value_bytes =
		ksawery_extension_annotation_provider_value_bytes(provider)
}

@(private)
ksawery_extension_annotations_omit_all :: proc(provider: ^Ksawery_Extension_Provider_Data) {
	if provider == nil do return
	for family in ksawery.Extension_Observation_Family {
		ksawery_extension_annotation_omit(provider, family)
	}
}
