// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"

@(private)
Ref_Observation_Data :: struct {
	descriptor: Ref_Observation_Descriptor,
	references: [dynamic]Ref_Identity,
	remotes: [dynamic]Remote_Identity,
	tracking: [dynamic]Tracking_Relationship,
	allocator: runtime.Allocator,
}

@(private)
Ref_Tracking_Pending :: struct {
	local_index: u32,
	upstream: Ref_Name,
	state: Tracking_State,
	ahead: u32,
	behind: u32,
}

/* repository_process_take_refs parses one completed bounded Ref observation process. */
repository_process_take_refs :: proc(
	process: ^Repository_Process,
	generation: Ref_Generation,
	allocator := context.allocator,
) -> (Ref_Observation, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || state.state != .Completed || state.request.kind != .Observe_Refs ||
	   state.ref_phase != .None {
		return {}, false, .Invalid_Request
	}
	return ref_observation_open(
		state.request.repository,
		generation,
		state.ref_output[:],
		state.remote_output[:],
		state.output[:],
		state.request.refs.limits,
		allocator,
	)
}

/* ref_observation_open parses complete bounded Ref, Remote, and HEAD process output. */
ref_observation_open :: proc(
	repository: Repository_Context,
	generation: Ref_Generation,
	ref_output: []u8,
	remote_output: []u8,
	head_output: []u8,
	limits := DEFAULT_REF_LIMITS,
	allocator := context.allocator,
) -> (Ref_Observation, bool, Failure_Code) {
	if allocator.procedure == nil || !repository_context_is_valid(repository) || generation == Ref_Generation(0) ||
	   !ref_limits_are_valid(limits) || u64(len(ref_output)) + u64(len(remote_output)) + u64(len(head_output)) >
		limits.temporary_bytes {
		return {}, false, .Invalid_Request
	}
	state, allocation_error := new(Ref_Observation_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.descriptor.repository = repository
	state.descriptor.generation = generation
	state.references, allocation_error = make([dynamic]Ref_Identity, 0, int(min(limits.entries, 64)), allocator)
	if allocation_error == nil {
		state.remotes, allocation_error = make([dynamic]Remote_Identity, 0, int(min(limits.remotes, 32)), allocator)
	}
	if allocation_error == nil {
		state.tracking, allocation_error = make([dynamic]Tracking_Relationship, 0, int(min(limits.entries, 64)), allocator)
	}
	if allocation_error != nil {
		ref_observation_data_destroy(state)
		return {}, false, .Allocation
	}
	pending, pending_error := make([dynamic]Ref_Tracking_Pending, 0, int(min(limits.entries, 64)), allocator)
	if pending_error != nil {
		ref_observation_data_destroy(state)
		return {}, false, .Allocation
	}
	defer delete(pending)

	head_branch: Ref_Identity
	if failure := ref_observation_parse_refs(state, &pending, ref_output, limits, &head_branch); failure != .None {
		ref_observation_data_destroy(state)
		return {}, false, failure
	}
	if failure := ref_observation_parse_remotes(state, remote_output, limits); failure != .None {
		ref_observation_data_destroy(state)
		return {}, false, failure
	}
	if failure := ref_observation_resolve_tracking(state, pending[:]); failure != .None {
		ref_observation_data_destroy(state)
		return {}, false, failure
	}
	if failure := ref_observation_assign_head(state, head_branch, head_output); failure != .None {
		ref_observation_data_destroy(state)
		return {}, false, failure
	}
	state.descriptor.local_branch_count = ref_observation_count_kind(state, .Local_Branch)
	state.descriptor.remote_tracking_count = ref_observation_count_kind(state, .Remote_Tracking_Branch)
	state.descriptor.tag_count = ref_observation_count_kind(state, .Tag)
	state.descriptor.remote_count = u32(len(state.remotes))
	state.descriptor.tracking_relationships = u32(len(state.tracking))
	state.descriptor.temporary_bytes = u64(len(ref_output)) + u64(len(remote_output)) + u64(len(head_output))
	if state.descriptor.state == .Invalid do state.descriptor.state = .Available
	if !ref_observation_descriptor_is_valid(state.descriptor, limits) {
		ref_observation_data_destroy(state)
		return {}, false, .Parse
	}
	return Ref_Observation{state = state}, true, .None
}

/* ref_observation_descriptor returns copied immutable Ref metadata. */
ref_observation_descriptor :: proc(observation: ^Ref_Observation) -> (Ref_Observation_Descriptor, bool) {
	state := ref_observation_data(observation)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* ref_observation_ref_count reports the number of retained exact Git refs. */
ref_observation_ref_count :: proc(observation: ^Ref_Observation) -> (u32, bool) {
	state := ref_observation_data(observation)
	if state == nil do return 0, false
	return u32(len(state.references)), true
}

/* ref_observation_ref returns one copied exact Git ref identity. */
ref_observation_ref :: proc(observation: ^Ref_Observation, index: u32) -> (Ref_Identity, bool) {
	state := ref_observation_data(observation)
	if state == nil || int(index) >= len(state.references) do return {}, false
	return state.references[int(index)], true
}

/* ref_observation_remote_count reports the number of retained configured remotes. */
ref_observation_remote_count :: proc(observation: ^Ref_Observation) -> (u32, bool) {
	state := ref_observation_data(observation)
	if state == nil do return 0, false
	return u32(len(state.remotes)), true
}

/* ref_observation_remote returns one copied exact configured remote identity. */
ref_observation_remote :: proc(observation: ^Ref_Observation, index: u32) -> (Remote_Identity, bool) {
	state := ref_observation_data(observation)
	if state == nil || int(index) >= len(state.remotes) do return {}, false
	return state.remotes[int(index)], true
}

/* ref_observation_tracking returns one copied exact local tracking relationship. */
ref_observation_tracking :: proc(observation: ^Ref_Observation, index: u32) -> (Tracking_Relationship, bool) {
	state := ref_observation_data(observation)
	if state == nil || int(index) >= len(state.tracking) do return {}, false
	return state.tracking[int(index)], true
}

/* ref_observation_usage reports exact retained Ref observation ownership. */
ref_observation_usage :: proc(observation: ^Ref_Observation) -> (Ref_Usage, bool) {
	state := ref_observation_data(observation)
	if state == nil do return {}, false
	return Ref_Usage {
		entries = u32(len(state.references)),
		local_branches = state.descriptor.local_branch_count,
		remote_tracking = state.descriptor.remote_tracking_count,
		tags = state.descriptor.tag_count,
		remotes = u32(len(state.remotes)),
		tracking_relationships = u32(len(state.tracking)),
		metadata_bytes = state.descriptor.metadata_bytes,
		temporary_bytes = state.descriptor.temporary_bytes,
		allocation_bytes = u64(size_of(Ref_Observation_Data)) +
			u64(cap(state.references)) * u64(size_of(Ref_Identity)) +
			u64(cap(state.remotes)) * u64(size_of(Remote_Identity)) +
			u64(cap(state.tracking)) * u64(size_of(Tracking_Relationship)),
	}, true
}

/* ref_observation_close releases every owned parsed Ref allocation. */
ref_observation_close :: proc(observation: ^Ref_Observation) {
	state := ref_observation_data(observation)
	if state == nil do return
	ref_observation_data_destroy(state)
	observation^ = {}
}

@(private)
ref_observation_parse_refs :: proc(
	state: ^Ref_Observation_Data,
	pending: ^[dynamic]Ref_Tracking_Pending,
	output: []u8,
	limits: Ref_Limits,
	head_branch: ^Ref_Identity,
) -> Failure_Code {
	if state == nil || pending == nil || head_branch == nil do return .Invalid_Request
	offset := 0
	for offset < len(output) {
		fields: [6][]u8
		for field_index in 0 ..< len(fields) {
			end := offset
			for end < len(output) && output[end] != 0 do end += 1
			if end == len(output) do return .Parse
			fields[field_index] = output[offset:end]
			offset = end + 1
		}
		if offset >= len(output) || output[offset] != '\n' do return .Parse
		offset += 1
		identity, parsed := ref_observation_parse_identity(
			state.descriptor.repository,
			state.descriptor.generation,
			fields[0],
			fields[1],
			fields[2],
		)
		if !parsed do return .Parse
		if u32(len(state.references)) >= limits.entries {
			state.descriptor.state = .Truncated
			continue
		}
		if _, append_error := append(&state.references, identity); append_error != nil do return .Allocation
		if string(fields[5]) == "*" {
			if identity.kind != .Local_Branch || head_branch^ != {} do return .Parse
			head_branch^ = identity
		}
		if identity.kind == .Local_Branch {
			relationship, relationship_parsed := ref_observation_tracking_pending(u32(len(state.references) - 1), fields[3], fields[4])
			if !relationship_parsed do return .Parse
			if _, append_error := append(pending, relationship); append_error != nil do return .Allocation
		}
	}
	return .None
}

@(private)
ref_observation_parse_identity :: proc(
	repository: Repository_Context,
	generation: Ref_Generation,
	name_data, object_data, type_data: []u8,
) -> (Ref_Identity, bool) {
	name := string(name_data)
	kind := ref_observation_kind_from_name(name)
	object_type := ref_observation_object_type(string(type_data))
	identity := Ref_Identity {repository = repository, generation = generation, kind = kind, object_type = object_type}
	if !ref_name_assign(&identity.name, name) || !revision_identity_assign(&identity.object, string(object_data)) {
		return {}, false
	}
	return identity, ref_identity_is_valid(identity)
}

@(private)
ref_observation_parse_remotes :: proc(
	state: ^Ref_Observation_Data,
	output: []u8,
	limits: Ref_Limits,
) -> Failure_Code {
	if state == nil do return .Invalid_Request
	offset := 0
	for offset < len(output) {
		end := offset
		for end < len(output) && output[end] != '\n' do end += 1
		if end == offset do return .Parse
		if u32(len(state.remotes)) >= limits.remotes {
			state.descriptor.state = .Truncated
			offset = end + 1
			continue
		}
		remote := Remote_Identity {repository = state.descriptor.repository, generation = state.descriptor.generation}
		if !remote_name_assign(&remote.name, string(output[offset:end])) || !remote_identity_is_valid(remote) {
			return .Parse
		}
		if _, append_error := append(&state.remotes, remote); append_error != nil do return .Allocation
		offset = end + 1
	}
	return .None
}

@(private)
ref_observation_resolve_tracking :: proc(
	state: ^Ref_Observation_Data,
	pending: []Ref_Tracking_Pending,
) -> Failure_Code {
	if state == nil do return .Invalid_Request
	for candidate in pending {
		if int(candidate.local_index) >= len(state.references) do return .Parse
		relationship := Tracking_Relationship {
			local = state.references[int(candidate.local_index)],
			state = candidate.state,
			ahead = candidate.ahead,
			behind = candidate.behind,
		}
		if candidate.state != .Missing && candidate.state != .Unavailable {
			upstream, found := ref_observation_find_ref_by_name(state, candidate.upstream)
			if found {
				relationship.upstream = upstream
			} else {
				relationship.state = .Unavailable
				relationship.ahead = 0
				relationship.behind = 0
			}
		}
		if !tracking_relationship_is_valid(relationship) do return .Parse
		if _, append_error := append(&state.tracking, relationship); append_error != nil do return .Allocation
	}
	return .None
}

@(private)
ref_observation_assign_head :: proc(
	state: ^Ref_Observation_Data,
	symbolic: Ref_Identity,
	output: []u8,
) -> Failure_Code {
	if state == nil do return .Invalid_Request
	identity, present := ref_observation_head_identity(output)
	if symbolic != {} {
		if !present || symbolic.object != identity do return .Parse
		state.descriptor.head = {state = .Symbolic, branch = symbolic, object = identity}
		return .None
	}
	if present {
		state.descriptor.head = {state = .Detached, object = identity}
		return .None
	}
	if len(state.references) != 0 do return .Parse
	state.descriptor.state = .Unborn
	state.descriptor.head = {state = .Unborn}
	return .None
}

@(private)
ref_observation_tracking_pending :: proc(
	local_index: u32,
	upstream_data, track_data: []u8,
) -> (Ref_Tracking_Pending, bool) {
	pending := Ref_Tracking_Pending {local_index = local_index}
	if len(upstream_data) == 0 {
		pending.state = .Missing
		return pending, true
	}
	if !ref_name_assign(&pending.upstream, string(upstream_data)) do return {}, false
	if len(track_data) == 0 {
		pending.state = .Equal
		return pending, true
	}
	state, ahead, behind, parsed := ref_observation_tracking_state(track_data)
	if !parsed do return {}, false
	pending.state = state
	pending.ahead = ahead
	pending.behind = behind
	return pending, true
}

@(private)
ref_observation_tracking_state :: proc(data: []u8) -> (Tracking_State, u32, u32, bool) {
	if len(data) == 0 do return .Unavailable, 0, 0, true
	offset := 0
	if offset >= len(data) || data[offset] != '[' || data[len(data) - 1] != ']' do return .Invalid, 0, 0, false
	offset += 1
	ahead: u32
	behind: u32
	for offset < len(data) - 1 {
		if ref_observation_has_text(data[offset:], "ahead ") {
			offset += len("ahead ")
			value, next, parsed := ref_observation_parse_u32(data, offset)
			if !parsed do return .Invalid, 0, 0, false
			ahead = value
			offset = next
		} else if ref_observation_has_text(data[offset:], "behind ") {
			offset += len("behind ")
			value, next, parsed := ref_observation_parse_u32(data, offset)
			if !parsed do return .Invalid, 0, 0, false
			behind = value
			offset = next
		} else {
			return .Invalid, 0, 0, false
		}
		if offset == len(data) - 1 do break
		if offset + 2 >= len(data) || data[offset] != ',' || data[offset + 1] != ' ' do return .Invalid, 0, 0, false
		offset += 2
	}
	if ahead > 0 && behind > 0 do return .Diverged, ahead, behind, true
	if ahead > 0 do return .Ahead, ahead, 0, true
	if behind > 0 do return .Behind, 0, behind, true
	return .Equal, 0, 0, true
}

@(private)
ref_observation_parse_u32 :: proc(data: []u8, offset: int) -> (u32, int, bool) {
	if offset >= len(data) || data[offset] < '0' || data[offset] > '9' do return 0, offset, false
	value: u32
	cursor := offset
	for cursor < len(data) && data[cursor] >= '0' && data[cursor] <= '9' {
		if value > (max(u32) - u32(data[cursor] - '0')) / 10 do return 0, cursor, false
		value = value * 10 + u32(data[cursor] - '0')
		cursor += 1
	}
	return value, cursor, true
}

@(private)
ref_observation_head_identity :: proc(output: []u8) -> (Revision_Identity, bool) {
	if len(output) == 0 do return {}, false
	if output[len(output) - 1] != '\n' do return {}, false
	identity: Revision_Identity
	return identity, revision_identity_assign(&identity, string(output[:len(output) - 1]))
}

@(private)
ref_observation_kind_from_name :: proc(name: string) -> Ref_Kind {
	if ref_name_has_prefix(name, "refs/heads/") do return .Local_Branch
	if ref_name_has_prefix(name, "refs/remotes/") do return .Remote_Tracking_Branch
	if ref_name_has_prefix(name, "refs/tags/") do return .Tag
	return .Invalid
}

@(private)
ref_observation_object_type :: proc(text: string) -> Ref_Object_Type {
	switch text {
	case "commit": return .Commit
	case "tag": return .Tag
	case "tree": return .Tree
	case "blob": return .Blob
	case: return .Invalid
	}
}

@(private)
ref_observation_find_ref_by_name :: proc(
	state: ^Ref_Observation_Data,
	name: Ref_Name,
) -> (Ref_Identity, bool) {
	if state == nil || !ref_name_is_valid(name) do return {}, false
	for identity in state.references {
		if identity.name == name do return identity, true
	}
	return {}, false
}

@(private)
ref_observation_count_kind :: proc(state: ^Ref_Observation_Data, kind: Ref_Kind) -> u32 {
	if state == nil do return 0
	count: u32
	for identity in state.references {
		if identity.kind == kind do count += 1
	}
	return count
}

@(private)
ref_observation_has_text :: proc(data: []u8, prefix: string) -> bool {
	return len(data) >= len(prefix) && string(data[:len(prefix)]) == prefix
}

@(private)
ref_observation_data :: proc(observation: ^Ref_Observation) -> ^Ref_Observation_Data {
	if observation == nil || observation.state == nil do return nil
	return cast(^Ref_Observation_Data)observation.state
}

@(private)
ref_observation_data_destroy :: proc(state: ^Ref_Observation_Data) {
	if state == nil do return
	delete(state.references)
	delete(state.remotes)
	delete(state.tracking)
	free(state, state.allocator)
}
