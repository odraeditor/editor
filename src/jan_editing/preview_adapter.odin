// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../language"
import "base:runtime"

@(private)
Preview_Entry :: struct {
	descriptor: Preview_Descriptor,
	result:     []u8,
}

@(private)
Preview_Cache_State :: struct {
	generation: Preview_Cache_Generation,
	limits:     Limits,
	entries:    [dynamic]Preview_Entry,
	sequence:   u64,
	allocator:  runtime.Allocator,
}

/* preview_factory_adapter returns one fixed factory adapter identity. */
preview_factory_adapter :: proc(kind: Preview_Kind, generation: Provider_Generation) -> Preview_Adapter_Handle {
	if generation == Provider_Generation(0) do return {}
	switch kind {
	case .Latex: return {id = 1, generation = generation, kind = kind, available = true}
	case .Image: return {id = 2, generation = generation, kind = kind, available = true}
	case .Invalid:
	}
	return {}
}

/* preview_adapter_capability reports factory ownership and resource admission. */
preview_adapter_capability :: proc(adapter: Preview_Adapter_Handle) -> (Preview_Adapter_Capability, bool) {
	if !preview_adapter_is_valid(adapter) do return {}, false
	return {
		handle = adapter,
		class = .Factory_Adapter,
		requires_resource_admission = adapter.kind == .Image,
	}, true
}

/* preview_cache_init creates one bounded process-wide derived result owner. */
preview_cache_init :: proc(
	cache: ^Preview_Cache,
	generation: Preview_Cache_Generation,
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
) -> (bool, Failure) {
	if cache == nil || cache.state != nil || generation == Preview_Cache_Generation(0) ||
	   !limits_are_valid(limits) || allocator.procedure == nil {
		return false, editing_failure(.Request_Preview, .Invalid_Scope, {})
	}
	state, state_error := new(Preview_Cache_State, allocator)
	if state_error != nil do return false, editing_failure(.Request_Preview, .Allocation_Failed, {})
	state^ = Preview_Cache_State{generation = generation, limits = limits, allocator = allocator}
	state.entries, state_error = make([dynamic]Preview_Entry, 0, 8, allocator)
	if state_error != nil {
		free(state, allocator)
		return false, editing_failure(.Request_Preview, .Allocation_Failed, {})
	}
	cache.state = state
	return true, {}
}

/* preview_request_begin admits one asynchronous request without performing effects. */
preview_request_begin :: proc(
	cache: ^Preview_Cache,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	request: Preview_Request,
) -> (descriptor: Preview_Descriptor, ok: bool, failure: Failure) {
	state := preview_cache_state(cache)
	if state == nil || analysis == nil || request.request_id == Preview_Request_ID(0) ||
	   request.operation_id == Operation_ID(0) || !scope_is_valid(request.scope) ||
	   request.kind <= .Invalid || request.kind > .Image ||
	   request.range.scope != request.scope.analysis {
		return {}, false, editing_failure(.Request_Preview, .Invalid_Scope, request.scope)
	}
	if request.cancel_requested != nil && request.cancel_requested^ {
		return {}, false, editing_failure(.Request_Preview, .Cancelled, request.scope)
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != u64(len(source)) || len(nodes) == 0 ||
	   nodes[0].range.scope != request.scope.analysis {
		return {}, false, editing_failure(.Request_Preview, .Stale, request.scope)
	}
	target, found := navigation_node_by_id(nodes, request.target_id)
	if !found || target.range != request.range || !preview_target_matches(target, source, request.kind) {
		return {}, false, editing_failure(.Request_Preview, .Invalid_Target, request.scope)
	}
	state.sequence += 1
	descriptor = {
		request_id = request.request_id,
		operation_id = request.operation_id,
		scope = request.scope,
		target = navigation_target(target),
		kind = request.kind,
		status = .Source_Fallback,
		adapter = request.adapter,
		resource_generation = request.resource_generation,
		source_visible = true,
		sequence = state.sequence,
	}
	if !request.surface_supported || !preview_adapter_is_valid(request.adapter) ||
	   !request.adapter.available || request.adapter.kind != request.kind {
		return descriptor, true, {}
	}
	if request.adapter.generation != request.scope.provider_generation {
		return {}, false, editing_failure(.Request_Preview, .Stale, request.scope)
	}
	if request.kind == .Image && (!request.resource_admitted || request.resource_generation == 0) {
		return {}, false, editing_failure(.Request_Preview, .Unavailable, request.scope)
	}
	if preview_cache_find(state, request.request_id) >= 0 {
		return {}, false, editing_failure(.Request_Preview, .Invalid_Target, request.scope)
	}
	active := preview_cache_active_for_view(state, request.scope)
	if active >= u32(state.limits.active_previews_per_view) {
		failure = editing_failure(.Request_Preview, .Limited, request.scope)
		failure.limit = u64(state.limits.active_previews_per_view)
		failure.actual = u64(active) + 1
		return {}, false, failure
	}
	descriptor.status = .Pending
	entry := Preview_Entry{descriptor = descriptor}
	if _, append_error := append(&state.entries, entry); append_error != nil {
		return {}, false, editing_failure(.Request_Preview, .Allocation_Failed, request.scope)
	}
	return descriptor, true, {}
}

/* preview_result_publish copies one adapter result only when all identities remain exact. */
preview_result_publish :: proc(
	cache: ^Preview_Cache,
	request_id: Preview_Request_ID,
	current_scope: Scope,
	adapter_generation: Provider_Generation,
	resource_generation: u64,
	result: []u8,
) -> (descriptor: Preview_Descriptor, ok: bool, failure: Failure) {
	state := preview_cache_state(cache)
	if state == nil || request_id == Preview_Request_ID(0) || len(result) == 0 {
		return {}, false, editing_failure(.Publish_Preview, .Invalid_Target, current_scope)
	}
	index := preview_cache_find(state, request_id)
	if index < 0 {
		return {}, false, editing_failure(.Publish_Preview, .Invalid_Target, current_scope)
	}
	entry := &state.entries[index]
	if entry.descriptor.status != .Pending {
		return {}, false, editing_failure(.Publish_Preview, .Invalid_Target, current_scope)
	}
	if entry.descriptor.scope != current_scope ||
	   entry.descriptor.adapter.generation != adapter_generation ||
	   entry.descriptor.resource_generation != resource_generation {
		preview_entry_fallback(entry, state.allocator)
		return entry.descriptor, false, editing_failure(.Publish_Preview, .Stale, current_scope)
	}
	if u64(len(result)) > state.limits.preview_result_bytes {
		failure = editing_failure(.Publish_Preview, .Limited, current_scope)
		failure.limit = state.limits.preview_result_bytes
		failure.actual = u64(len(result))
		return {}, false, failure
	}
	copy_result, result_error := make([]u8, len(result), state.allocator)
	if result_error != nil {
		preview_entry_fallback(entry, state.allocator)
		return entry.descriptor, false, editing_failure(.Publish_Preview, .Allocation_Failed, current_scope)
	}
	copy(copy_result, result)
	needed := preview_cache_retained_result_bytes(state) + u64(len(copy_result))
	for needed > state.limits.preview_cache_bytes {
		victim := preview_cache_oldest_ready(state, request_id)
		if victim < 0 do break
		needed -= u64(len(state.entries[victim].result))
		preview_cache_remove(state, victim)
		index = preview_cache_find(state, request_id)
		entry = &state.entries[index]
	}
	if needed > state.limits.preview_cache_bytes {
		delete(copy_result, state.allocator)
		failure = editing_failure(.Publish_Preview, .Limited, current_scope)
		failure.limit = state.limits.preview_cache_bytes
		failure.actual = needed
		return {}, false, failure
	}
	entry.result = copy_result
	entry.descriptor.status = .Ready
	entry.descriptor.result_bytes = u64(len(copy_result))
	entry.descriptor.source_visible = false
	return entry.descriptor, true, {}
}

/* preview_request_fallback completes one request with exact visible source fallback. */
preview_request_fallback :: proc(
	cache: ^Preview_Cache,
	request_id: Preview_Request_ID,
) -> (Preview_Descriptor, bool) {
	state := preview_cache_state(cache)
	if state == nil do return {}, false
	index := preview_cache_find(state, request_id)
	if index < 0 do return {}, false
	preview_entry_fallback(&state.entries[index], state.allocator)
	return state.entries[index].descriptor, true
}

/* preview_cache_inspect copies one request descriptor. */
preview_cache_inspect :: proc(
	cache: ^Preview_Cache,
	request_id: Preview_Request_ID,
) -> (Preview_Descriptor, bool) {
	state := preview_cache_state(cache)
	if state == nil do return {}, false
	index := preview_cache_find(state, request_id)
	if index < 0 do return {}, false
	return state.entries[index].descriptor, true
}

/* preview_cache_result borrows copied result bytes until eviction or close. */
preview_cache_result :: proc(cache: ^Preview_Cache, request_id: Preview_Request_ID) -> ([]u8, bool) {
	state := preview_cache_state(cache)
	if state == nil do return nil, false
	index := preview_cache_find(state, request_id)
	if index < 0 || state.entries[index].descriptor.status != .Ready do return nil, false
	return state.entries[index].result, true
}

/* preview_cache_descriptor reports bounded active and retained ownership. */
preview_cache_descriptor :: proc(cache: ^Preview_Cache) -> (Preview_Cache_Descriptor, bool) {
	state := preview_cache_state(cache)
	if state == nil do return {}, false
	descriptor := Preview_Cache_Descriptor {
		generation = state.generation,
		entries = u32(len(state.entries)),
		retained_bytes = u64(size_of(Preview_Cache_State)) +
		                 u64(cap(state.entries)) * u64(size_of(Preview_Entry)) +
		                 preview_cache_retained_result_bytes(state),
	}
	for entry in state.entries {
		if entry.descriptor.status == .Pending do descriptor.active += 1
		if entry.descriptor.status == .Ready do descriptor.ready += 1
	}
	return descriptor, true
}

/* preview_cache_evict releases one copied or pending entry. */
preview_cache_evict :: proc(cache: ^Preview_Cache, request_id: Preview_Request_ID) -> bool {
	state := preview_cache_state(cache)
	if state == nil do return false
	index := preview_cache_find(state, request_id)
	if index < 0 do return false
	preview_cache_remove(state, index)
	return true
}

/* preview_cache_close releases all copied results and pending identities. */
preview_cache_close :: proc(cache: ^Preview_Cache) {
	state := preview_cache_state(cache)
	if state == nil do return
	for &entry in state.entries do if entry.result != nil do delete(entry.result, state.allocator)
	delete(state.entries)
	allocator := state.allocator
	state^ = {}
	free(state, allocator)
	cache.state = nil
}

@(private)
preview_adapter_is_valid :: proc(adapter: Preview_Adapter_Handle) -> bool {
	return adapter.id != Preview_Adapter_ID(0) &&
	       adapter.generation != Provider_Generation(0) &&
	       adapter.kind > .Invalid && adapter.kind <= .Image
}

@(private)
preview_target_matches :: proc(
	target: language.Jan_Node_Record,
	source: []u8,
	kind: Preview_Kind,
) -> bool {
	if kind == .Latex {
		return target.kind == .Latex_Fragment || target.kind == .Latex_Environment
	}
	if kind != .Image ||
	   (target.kind != .Plain_Link && target.kind != .Angle_Link && target.kind != .Regular_Link) {
		return false
	}
	text := source[int(target.range.start):int(target.range.end)]
	extensions := [6]string{".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"}
	for extension in extensions do if preview_ascii_contains_suffix(text, extension) do return true
	return false
}

@(private)
preview_ascii_contains_suffix :: proc(text: []u8, suffix: string) -> bool {
	if len(text) < len(suffix) do return false
	for start in 0 ..= len(text) - len(suffix) {
		matches := true
		for value, index in transmute([]u8)suffix {
			left := text[start + index]
			if left >= 'A' && left <= 'Z' do left += 'a' - 'A'
			if left != value {
				matches = false
				break
			}
		}
		if matches do return true
	}
	return false
}

@(private)
preview_cache_active_for_view :: proc(state: ^Preview_Cache_State, scope: Scope) -> u32 {
	active: u32
	for entry in state.entries {
		if entry.descriptor.status == .Pending &&
		   entry.descriptor.scope.view_handle == scope.view_handle {
			active += 1
		}
	}
	return active
}

@(private)
preview_cache_find :: proc(state: ^Preview_Cache_State, request_id: Preview_Request_ID) -> int {
	for entry, index in state.entries do if entry.descriptor.request_id == request_id do return index
	return -1
}

@(private)
preview_cache_retained_result_bytes :: proc(state: ^Preview_Cache_State) -> u64 {
	total: u64
	for entry in state.entries do total += u64(len(entry.result))
	return total
}

@(private)
preview_cache_oldest_ready :: proc(state: ^Preview_Cache_State, exclude: Preview_Request_ID) -> int {
	oldest := -1
	for entry, index in state.entries {
		if entry.descriptor.status != .Ready || entry.descriptor.request_id == exclude do continue
		if oldest < 0 || entry.descriptor.sequence < state.entries[oldest].descriptor.sequence do oldest = index
	}
	return oldest
}

@(private)
preview_entry_fallback :: proc(entry: ^Preview_Entry, allocator: runtime.Allocator) {
	if entry.result != nil do delete(entry.result, allocator)
	entry.result = nil
	entry.descriptor.status = .Source_Fallback
	entry.descriptor.result_bytes = 0
	entry.descriptor.source_visible = true
}

@(private)
preview_cache_remove :: proc(state: ^Preview_Cache_State, index: int) {
	if index < 0 || index >= len(state.entries) do return
	if state.entries[index].result != nil do delete(state.entries[index].result, state.allocator)
	for cursor in index + 1 ..< len(state.entries) do state.entries[cursor - 1] = state.entries[cursor]
	resize(&state.entries, len(state.entries) - 1)
}

@(private)
preview_cache_state :: proc(cache: ^Preview_Cache) -> ^Preview_Cache_State {
	if cache == nil || cache.state == nil do return nil
	return cast(^Preview_Cache_State)cache.state
}
