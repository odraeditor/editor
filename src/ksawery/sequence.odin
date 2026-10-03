// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"

@(private)
Sequence_Observation_Data :: struct {
	descriptor: Sequence_Observation_Descriptor,
	conflicts:  [dynamic]Conflict_Target,
	paths:      [dynamic]u8,
	allocator:  runtime.Allocator,
}

/* repository_process_take_sequence parses one completed bounded sequence observation process. */
repository_process_take_sequence :: proc(
	process: ^Repository_Process,
	generation: Sequence_Generation,
	allocator := context.allocator,
) -> (Sequence_Observation, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || state.state != .Completed || state.request.kind != .Observe_Sequence ||
	   state.sequence_phase != .None {
		return {}, false, .Invalid_Request
	}
	return sequence_observation_open(
		state.request.repository,
		generation,
		state.sequence_source,
		state.output[:],
		state.request.sequence.limits,
		allocator,
	)
}

/* sequence_observation_open parses one bounded marker snapshot and porcelain-v2 status result. */
sequence_observation_open :: proc(
	repository: Repository_Context,
	generation: Sequence_Generation,
	source: Sequence_Source,
	output: []u8,
	limits := DEFAULT_SEQUENCE_LIMITS,
	allocator := context.allocator,
) -> (Sequence_Observation, bool, Failure_Code) {
	if allocator.procedure == nil || !repository_context_is_valid(repository) ||
	   generation == Sequence_Generation(0) || !sequence_source_is_valid(source, limits) ||
	   u64(len(output)) > limits.temporary_bytes {
		return {}, false, .Invalid_Request
	}
	state, allocation_error := new(Sequence_Observation_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.descriptor.repository = repository
	state.descriptor.generation = generation
	state.descriptor.kind = source.kind
	state.descriptor.origin = source.origin
	state.descriptor.current = source.current
	state.descriptor.target = source.target
	state.descriptor.step = source.step
	state.descriptor.metadata_bytes = source.metadata_bytes
	state.descriptor.temporary_bytes = u64(len(output))
	state.conflicts, allocation_error = make(
		[dynamic]Conflict_Target,
		0,
		int(min(limits.conflicts, 64)),
		allocator,
	)
	if allocation_error == nil {
		state.paths, allocation_error = make(
			[dynamic]u8,
			0,
			int(min(limits.path_bytes, u64(16 * KIBIBYTE))),
			allocator,
		)
	}
	if allocation_error != nil {
		sequence_observation_data_destroy(state)
		return {}, false, .Allocation
	}
	if failure := sequence_observation_parse(state, source, output, limits); failure != .None {
		sequence_observation_data_destroy(state)
		return {}, false, failure
	}
	state.descriptor.fingerprint = sequence_observation_fingerprint(state, source.marker_mask)
	state.descriptor.actions = {
		inspect = state.descriptor.state != .Inactive,
		refresh = true,
		return_to_status = true,
	}
	if !sequence_observation_descriptor_is_valid(state.descriptor, limits) {
		sequence_observation_data_destroy(state)
		return {}, false, .Parse
	}
	return Sequence_Observation{state = state}, true, .None
}

/* sequence_observation_descriptor returns copied immutable sequence metadata. */
sequence_observation_descriptor :: proc(
	observation: ^Sequence_Observation,
) -> (Sequence_Observation_Descriptor, bool) {
	state := sequence_observation_data(observation)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* sequence_observation_conflict_count reports the number of retained conflict targets. */
sequence_observation_conflict_count :: proc(observation: ^Sequence_Observation) -> (u32, bool) {
	state := sequence_observation_data(observation)
	if state == nil do return 0, false
	return u32(len(state.conflicts)), true
}

/* sequence_observation_conflict returns one copied semantic conflict target. */
sequence_observation_conflict :: proc(
	observation: ^Sequence_Observation,
	index: u32,
) -> (Conflict_Target, bool) {
	state := sequence_observation_data(observation)
	if state == nil || int(index) >= len(state.conflicts) do return {}, false
	return state.conflicts[int(index)], true
}

/* sequence_observation_conflict_path returns one borrowed path owned by the observation. */
sequence_observation_conflict_path :: proc(
	observation: ^Sequence_Observation,
	conflict: Conflict_Target,
) -> (string, bool) {
	state := sequence_observation_data(observation)
	if state == nil || conflict.id == Conflict_ID(0) || conflict.path.length == 0 do return "", false
	end := u64(conflict.path.offset) + u64(conflict.path.length)
	if end > u64(len(state.paths)) do return "", false
	return string(state.paths[conflict.path.offset:end]), true
}

/* sequence_observation_usage reports exact retained sequence observation ownership. */
sequence_observation_usage :: proc(observation: ^Sequence_Observation) -> (Sequence_Usage, bool) {
	state := sequence_observation_data(observation)
	if state == nil do return {}, false
	return Sequence_Usage {
		conflicts = u32(len(state.conflicts)),
		observed_conflicts = state.descriptor.observed_conflicts,
		path_bytes = u64(len(state.paths)),
		metadata_bytes = state.descriptor.metadata_bytes,
		temporary_bytes = state.descriptor.temporary_bytes,
		allocation_bytes = u64(size_of(Sequence_Observation_Data)) +
			u64(cap(state.conflicts)) * u64(size_of(Conflict_Target)) + u64(cap(state.paths)),
	}, true
}

/* sequence_observation_close releases every owned parsed sequence allocation. */
sequence_observation_close :: proc(observation: ^Sequence_Observation) {
	state := sequence_observation_data(observation)
	if state == nil do return
	sequence_observation_data_destroy(state)
	observation^ = {}
}

@(private)
sequence_observation_parse :: proc(
	state: ^Sequence_Observation_Data,
	source: Sequence_Source,
	output: []u8,
	limits: Sequence_Limits,
) -> Failure_Code {
	if source.kind == .None {
		state.descriptor.state = .Inactive
	} else if !source.supported || source.kind == .Other {
		state.descriptor.state = .Unsupported
	} else {
		state.descriptor.state = .Active
	}
	offset := 0
	for offset < len(output) {
		end := offset
		for end < len(output) && output[end] != 0 do end += 1
		if end == len(output) || end == offset do return .Parse
		record := output[offset:end]
		offset = end + 1
		if record[0] == '#' {
			if failure := sequence_observation_parse_header(state, record); failure != .None do return failure
			continue
		}
		if len(record) < 3 || record[0] != 'u' || record[1] != ' ' do continue
		if state.descriptor.observed_conflicts == max(u32) do return .Target_Limit
		state.descriptor.observed_conflicts += 1
		conflict, path, parsed := sequence_conflict_parse(record)
		if !parsed do return .Parse
		if u32(len(state.conflicts)) >= limits.conflicts ||
		   u64(len(state.paths)) + u64(len(path)) > limits.path_bytes {
			state.descriptor.state = .Truncated
			continue
		}
		conflict.id = Conflict_ID(len(state.conflicts) + 1)
		conflict.path = {offset = u32(len(state.paths)), length = u32(len(path))}
		if _, append_error := append(&state.paths, ..path); append_error != nil do return .Allocation
		if _, append_error := append(&state.conflicts, conflict); append_error != nil do return .Allocation
	}
	state.descriptor.conflict_count = u32(len(state.conflicts))
	state.descriptor.path_bytes = u64(len(state.paths))
	if state.descriptor.observed_conflicts > 0 {
		if state.descriptor.state == .Inactive {
			state.descriptor.kind = .Other
			state.descriptor.state = .Unsupported
		} else if state.descriptor.state == .Active {
			state.descriptor.state = .Conflicted
		}
	}
	return .None
}

@(private)
sequence_observation_parse_header :: proc(
	state: ^Sequence_Observation_Data,
	record: []u8,
) -> Failure_Code {
	prefix :: "# branch.oid "
	if len(record) < len(prefix) || string(record[:len(prefix)]) != prefix do return .None
	value := record[len(prefix):]
	if string(value) == "(initial)" {
		if state.descriptor.current != {} do return .Stale_Observation
		return .None
	}
	identity: Revision_Identity
	if !revision_identity_assign(&identity, string(value)) do return .Parse
	if state.descriptor.current != {} && state.descriptor.current != identity do return .Stale_Observation
	state.descriptor.current = identity
	return .None
}

@(private)
sequence_conflict_parse :: proc(record: []u8) -> (Conflict_Target, []u8, bool) {
	fields: [10][]u8
	offset := 0
	for field_index in 0 ..< len(fields) {
		end := offset
		for end < len(record) && record[end] != ' ' do end += 1
		if end == offset || end >= len(record) do return {}, nil, false
		fields[field_index] = record[offset:end]
		offset = end + 1
	}
	if string(fields[0]) != "u" || len(fields[1]) != 2 || offset >= len(record) do return {}, nil, false
	conflict := Conflict_Target {
		kind = sequence_conflict_kind(fields[1]),
		index = fields[1][0],
		worktree = fields[1][1],
	}
	if conflict.kind == .Invalid do return {}, nil, false
	stage_kinds := [3]Conflict_Index_Stage_Kind{.Base, .Current, .Applied}
	for stage_index in 0 ..< 3 {
		mode, mode_ok := sequence_mode_parse(fields[3 + stage_index])
		object, available, object_ok := sequence_object_parse(fields[7 + stage_index])
		if !mode_ok || !object_ok do return {}, nil, false
		conflict.stages[stage_index] = {
			kind = stage_kinds[stage_index],
			available = available,
			mode = mode,
			object = object,
		}
		if !available && mode != 0 do return {}, nil, false
	}
	return conflict, record[offset:], true
}

@(private)
sequence_conflict_kind :: proc(pair: []u8) -> Conflict_Kind {
	if len(pair) != 2 do return .Invalid
	switch string(pair) {
	case "UU": return .Both_Modified
	case "AA": return .Added_By_Both
	case "UD": return .Deleted_By_Them
	case "DU": return .Deleted_By_Us
	case "AU": return .Added_By_Us
	case "UA": return .Added_By_Them
	case "DD": return .Both_Deleted
	case: return .Other
	}
}

@(private)
sequence_mode_parse :: proc(data: []u8) -> (u32, bool) {
	if len(data) != 6 do return 0, false
	value: u32
	for byte in data {
		if byte < '0' || byte > '7' do return 0, false
		value = value * 8 + u32(byte - '0')
	}
	return value, true
}

@(private)
sequence_object_parse :: proc(data: []u8) -> (Revision_Identity, bool, bool) {
	all_zero := len(data) >= 40 && len(data) <= MAX_REVISION_ID_BYTES && len(data) % 2 == 0
	if all_zero {
		for byte in data {
			if byte != '0' {
				all_zero = false
				break
			}
		}
	}
	if all_zero do return {}, false, true
	identity: Revision_Identity
	if !revision_identity_assign(&identity, string(data)) do return {}, false, false
	return identity, true, true
}

@(private)
sequence_observation_fingerprint :: proc(
	state: ^Sequence_Observation_Data,
	marker_mask: u16,
) -> Sequence_Fingerprint {
	if state == nil do return Sequence_Fingerprint(0)
	descriptor := state.descriptor
	hash := u64(14_695_981_039_346_656_037)
	hash = (hash ~ u64(descriptor.kind)) * 1_099_511_628_211
	hash = (hash ~ u64(marker_mask)) * 1_099_511_628_211
	current := descriptor.current
	target := descriptor.target
	for value in current.bytes[:current.length] do hash = (hash ~ u64(value)) * 1_099_511_628_211
	for value in target.bytes[:target.length] do hash = (hash ~ u64(value)) * 1_099_511_628_211
	hash = (hash ~ u64(descriptor.step.position)) * 1_099_511_628_211
	hash = (hash ~ u64(descriptor.step.total)) * 1_099_511_628_211
	for conflict in state.conflicts {
		hash = (hash ~ u64(conflict.kind)) * 1_099_511_628_211
		hash = (hash ~ u64(conflict.index)) * 1_099_511_628_211
		hash = (hash ~ u64(conflict.worktree)) * 1_099_511_628_211
		end := int(conflict.path.offset + conflict.path.length)
		for value in state.paths[int(conflict.path.offset):end] do hash = (hash ~ u64(value)) * 1_099_511_628_211
		for stage in conflict.stages {
			hash = (hash ~ u64(stage.kind)) * 1_099_511_628_211
			hash = (hash ~ u64(stage.mode)) * 1_099_511_628_211
			object := stage.object
			for value in object.bytes[:object.length] do hash = (hash ~ u64(value)) * 1_099_511_628_211
		}
	}
	if hash == 0 do hash = 1
	return Sequence_Fingerprint(hash)
}

@(private)
sequence_observation_descriptor_is_valid :: proc(
	descriptor: Sequence_Observation_Descriptor,
	limits: Sequence_Limits,
) -> bool {
	if !repository_context_is_valid(descriptor.repository) || descriptor.generation == Sequence_Generation(0) ||
	   descriptor.kind == .Invalid || descriptor.origin == .Invalid || descriptor.fingerprint == Sequence_Fingerprint(0) ||
	   !sequence_step_is_valid(descriptor.step) || descriptor.conflict_count > descriptor.observed_conflicts ||
	   descriptor.conflict_count > limits.conflicts || descriptor.path_bytes > limits.path_bytes ||
	   descriptor.metadata_bytes > limits.metadata_bytes || descriptor.temporary_bytes > limits.temporary_bytes ||
	   !descriptor.actions.refresh || !descriptor.actions.return_to_status {
		return false
	}
	switch descriptor.state {
	case .Inactive:
		return descriptor.kind == .None && descriptor.conflict_count == 0 &&
		       descriptor.observed_conflicts == 0 && !descriptor.actions.inspect
	case .Active:
		return descriptor.kind != .None && descriptor.conflict_count == 0 && descriptor.actions.inspect
	case .Conflicted:
		return descriptor.kind != .None && descriptor.conflict_count > 0 && descriptor.actions.inspect
	case .Unsupported:
		return descriptor.kind != .None && descriptor.actions.inspect
	case .Truncated:
		return descriptor.kind != .None && descriptor.observed_conflicts > descriptor.conflict_count &&
		       descriptor.actions.inspect
	case .Invalid:
		return false
	}
	return false
}

@(private)
sequence_observation_data :: proc(observation: ^Sequence_Observation) -> ^Sequence_Observation_Data {
	if observation == nil || observation.state == nil do return nil
	return cast(^Sequence_Observation_Data)observation.state
}

@(private)
sequence_observation_data_destroy :: proc(state: ^Sequence_Observation_Data) {
	if state == nil do return
	if state.conflicts != nil do delete(state.conflicts)
	if state.paths != nil do delete(state.paths)
	free(state, state.allocator)
}
