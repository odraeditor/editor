// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package gutter

import "base:runtime"

/* Marker_Generation_Proposal borrows one complete or pending provider publication. */
Marker_Generation_Proposal :: struct {
	id:                  Marker_Generation_ID,
	provider:            Provider_ID,
	provider_generation: Provider_Generation,
	complete:            bool,
	cancelled:           bool,
	markers:             []Marker,
}

/* Marker_Generation owns copied marker values and text until closed. */
Marker_Generation :: struct {
	id:                  Marker_Generation_ID,
	provider:            Provider_ID,
	provider_generation: Provider_Generation,
	complete:            bool,
	markers:             []Marker,
	storage:             []u8,
	retained_bytes:      u64,
	allocator:           runtime.Allocator,
}

/* Marker_Generation_View borrows one exact immutable store publication. */
Marker_Generation_View :: struct {
	id:                  Marker_Generation_ID,
	provider:            Provider_ID,
	provider_generation: Provider_Generation,
	complete:            bool,
	markers:             []Marker,
	retained_bytes:      u64,
}

/* Marker_Store owns one last-valid publication for one provider. */
Marker_Store :: struct {
	current:   Marker_Generation,
	allocator: runtime.Allocator,
	limits:    Limits,
}

/* marker_store_init creates one empty bounded publication owner. */
marker_store_init :: proc(
	store: ^Marker_Store,
	allocator := context.allocator,
	limits := DEFAULT_LIMITS,
) -> (bool, Failure_Context) {
	if store == nil || store.allocator.procedure != nil || allocator.procedure == nil ||
	   !limits_are_valid(limits) {
		return false, Failure_Context{operation = .Publish, code = .Invalid_Request}
	}
	store^ = Marker_Store{allocator = allocator, limits = limits}
	return true, {}
}

/* marker_store_publish atomically replaces one newer provider generation. */
marker_store_publish :: proc(
	store: ^Marker_Store,
	proposal: Marker_Generation_Proposal,
) -> (Marker_Generation_View, bool, Failure_Context) {
	if store == nil || store.allocator.procedure == nil {
		return {}, false, Failure_Context{operation = .Publish, code = .Invalid_Request}
	}
	if store.current.allocator.procedure != nil &&
	   (proposal.provider != store.current.provider ||
	    proposal.provider_generation != store.current.provider_generation ||
	    proposal.id <= store.current.id) {
		return {}, false, Failure_Context {
			operation = .Publish,
			code = .Stale_Generation,
			limit = u64(store.current.id) + 1,
			actual = u64(proposal.id),
		}
	}
	candidate, copied, copy_failure := marker_generation_copy(
		proposal,
		store.allocator,
		store.limits,
	)
	if !copied {
		copy_failure.operation = .Publish
		return {}, false, copy_failure
	}
	if store.current.allocator.procedure != nil do marker_generation_close(&store.current)
	store.current = candidate
	return marker_store_view(store)
}

/* marker_store_view borrows the current complete or incomplete publication. */
marker_store_view :: proc(store: ^Marker_Store) -> (Marker_Generation_View, bool, Failure_Context) {
	if store == nil || store.allocator.procedure == nil || store.current.allocator.procedure == nil {
		return {}, false, Failure_Context{operation = .Inspect, code = .Invalid_Generation}
	}
	return Marker_Generation_View {
		id = store.current.id,
		provider = store.current.provider,
		provider_generation = store.current.provider_generation,
		complete = store.current.complete,
		markers = store.current.markers,
		retained_bytes = store.current.retained_bytes,
	}, true, {}
}

/* marker_generation_view borrows one live copied publication. */
marker_generation_view :: proc(
	generation: ^Marker_Generation,
) -> (Marker_Generation_View, bool, Failure_Context) {
	if generation == nil || generation.allocator.procedure == nil {
		return {}, false, Failure_Context{operation = .Inspect, code = .Invalid_Generation}
	}
	return Marker_Generation_View {
		id = generation.id,
		provider = generation.provider,
		provider_generation = generation.provider_generation,
		complete = generation.complete,
		markers = generation.markers,
		retained_bytes = generation.retained_bytes,
	}, true, {}
}

/* marker_store_close releases the current publication and owner state. */
marker_store_close :: proc(store: ^Marker_Store) -> (bool, Failure_Context) {
	if store == nil || store.allocator.procedure == nil {
		return false, Failure_Context{operation = .Close, code = .Closed_View}
	}
	if store.current.allocator.procedure != nil do marker_generation_close(&store.current)
	store^ = {}
	return true, {}
}

/* marker_generation_copy admits and copies one immutable marker publication. */
marker_generation_copy :: proc(
	proposal: Marker_Generation_Proposal,
	allocator := context.allocator,
	limits := DEFAULT_LIMITS,
) -> (Marker_Generation, bool, Failure_Context) {
	if proposal.cancelled {
		return {}, false, Failure_Context{operation = .Copy, code = .Cancelled}
	}
	if allocator.procedure == nil || !limits_are_valid(limits) || proposal.id == 0 ||
	   proposal.provider == 0 || proposal.provider_generation == 0 {
		return {}, false, Failure_Context{operation = .Copy, code = .Invalid_Request}
	}
	if len(proposal.markers) > int(limits.markers_per_generation) {
		return {}, false, Failure_Context {
			operation = .Copy,
			code = .Marker_Limit,
			limit = u64(limits.markers_per_generation),
			actual = u64(len(proposal.markers)),
		}
	}
	storage_bytes: u64
	for marker, index in proposal.markers {
		if marker.provider != proposal.provider ||
		   marker.provider_generation != proposal.provider_generation ||
		   !marker_is_valid(marker, limits) {
			return {}, false, marker_failure(.Invalid_Marker, marker)
		}
		for prior in proposal.markers[:index] {
			if prior.id == marker.id do return {}, false, marker_failure(.Duplicate_Marker, marker)
		}
		storage_bytes += u64(len(marker.representation.value)) +
			u64(len(marker.representation.fallback)) + u64(len(marker.aggregation_label)) +
			u64(len(marker.detail))
		if storage_bytes > u64(limits.view_text_bytes) {
			return {}, false, Failure_Context {
				operation = .Copy,
				code = .Text_Limit,
				limit = u64(limits.view_text_bytes),
				actual = storage_bytes,
			}
		}
	}
	result := Marker_Generation {
		id = proposal.id,
		provider = proposal.provider,
		provider_generation = proposal.provider_generation,
		complete = proposal.complete,
		allocator = allocator,
	}
	allocation_error: runtime.Allocator_Error
	result.markers, allocation_error = make([]Marker, len(proposal.markers), allocator)
	if allocation_error == nil && storage_bytes > 0 {
		result.storage, allocation_error = make([]u8, int(storage_bytes), allocator)
	}
	if allocation_error != nil {
		marker_generation_close(&result)
		return {}, false, Failure_Context {
			operation = .Copy,
			code = .Allocation,
			actual = storage_bytes + u64(len(proposal.markers)) * u64(size_of(Marker)),
		}
	}
	cursor := 0
	for marker, index in proposal.markers {
		result.markers[index] = marker
		entry := &result.markers[index]
		entry.representation.value, cursor = generation_copy_text(result.storage, cursor, marker.representation.value)
		entry.representation.fallback, cursor = generation_copy_text(result.storage, cursor, marker.representation.fallback)
		entry.aggregation_label, cursor = generation_copy_text(result.storage, cursor, marker.aggregation_label)
		entry.detail, cursor = generation_copy_text(result.storage, cursor, marker.detail)
	}
	result.retained_bytes = u64(len(result.markers)) * u64(size_of(Marker)) + storage_bytes
	return result, true, {}
}

/* marker_generation_close releases one copied publication exactly once. */
marker_generation_close :: proc(generation: ^Marker_Generation) -> (bool, Failure_Context) {
	if generation == nil || generation.allocator.procedure == nil {
		return false, Failure_Context{operation = .Close, code = .Closed_View}
	}
	if generation.markers != nil do delete(generation.markers, generation.allocator)
	if generation.storage != nil do delete(generation.storage, generation.allocator)
	generation^ = {}
	return true, {}
}

@(private = "file")
generation_copy_text :: proc(storage: []u8, cursor: int, value: string) -> (string, int) {
	if len(value) == 0 do return "", cursor
	copy(storage[cursor:cursor + len(value)], transmute([]u8)value)
	return string(storage[cursor:cursor + len(value)]), cursor + len(value)
}

@(private = "file")
marker_failure :: proc(code: Failure_Code, marker: Marker) -> Failure_Context {
	return Failure_Context{operation = .Copy, code = code, lane = marker.lane, actual = u64(marker.id)}
}
