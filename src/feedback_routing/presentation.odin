// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package feedback_routing

import "../feedback"

/* presentation_apply replaces one record's complete routed destination generation. */
presentation_apply :: proc(
	cache: ^Presentation_Cache,
	routed: Routed_Presentation,
) -> (bool, Failure) {
	if cache == nil || routed.resolution.record_id == feedback.Record_ID(0) ||
	   routed.resolution.record_generation == feedback.Record_Generation(0) {
		return false, Failure{operation = .Project, code = .Invalid_Projection}
	}
	candidate := cache^
	for item in candidate.items[:candidate.item_count] {
		if item.record_id == routed.resolution.record_id &&
		   routed.resolution.record_generation <= item.record_generation {
			return false, Failure{operation = .Project, code = .Stale_Generation, destination = item.destination}
		}
	}
	index := 0
	for index < int(candidate.item_count) {
		item := candidate.items[index]
		if item.record_id == routed.resolution.record_id &&
		   !routed_has_destination(routed, item.destination) {
			presentation_remove_at(&candidate, index)
			continue
		}
		index += 1
	}
	for projection_index in 0 ..< int(routed.projection_count) {
		projection := routed.projections[projection_index]
		if projection.capacity == 0 {
			return false, Failure{operation = .Project, code = .Invalid_Projection, destination = projection.destination}
		}
		existing := presentation_find(&candidate, projection.record_id, projection.destination)
		if existing >= 0 {
			candidate.items[existing] = projection
			continue
		}
		if presentation_destination_count(&candidate, projection.destination) >= projection.capacity {
			eviction := presentation_eviction_candidate(&candidate, projection)
			if eviction < 0 do continue
			candidate.items[eviction] = projection
			continue
		}
		if candidate.item_count >= MAX_PRESENTED_ITEMS {
			return false, Failure{operation = .Project, code = .Presentation_Limit, limit = MAX_PRESENTED_ITEMS, actual = u64(candidate.item_count) + 1}
		}
		candidate.items[candidate.item_count] = projection
		candidate.item_count += 1
	}
	candidate.generation += 1
	cache^ = candidate
	return true, {}
}

/* presentation_dismiss removes one item only for an admitted destination cause. */
presentation_dismiss :: proc(
	cache: ^Presentation_Cache,
	record: feedback.Record_ID,
	destination: Destination_ID,
	cause: Dismissal_Cause,
) -> (bool, Failure) {
	if cache == nil || cause == Dismissal_Cause(0) {
		return false, Failure{operation = .Project, code = .Dismissal_Rejected, destination = destination}
	}
	index := presentation_find(cache, record, destination)
	if index < 0 {
		return false, Failure{operation = .Project, code = .Invalid_Projection, destination = destination}
	}
	if cause not_in cache.items[index].dismissal {
		return false, Failure{operation = .Project, code = .Dismissal_Rejected, destination = destination}
	}
	presentation_remove_at(cache, index)
	cache.generation += 1
	return true, {}
}

/* presentation_frontend_lost removes items that admit frontend-loss dismissal. */
presentation_frontend_lost :: proc(cache: ^Presentation_Cache) -> u64 {
	if cache == nil do return 0
	removed: u64
	index := 0
	for index < int(cache.item_count) {
		if .Frontend_Loss in cache.items[index].dismissal {
			presentation_remove_at(cache, index)
			removed += 1
			continue
		}
		index += 1
	}
	if removed > 0 do cache.generation += 1
	return removed
}

@(private)
presentation_find :: proc(cache: ^Presentation_Cache, record: feedback.Record_ID, destination: Destination_ID) -> int {
	for item, index in cache.items[:cache.item_count] {
		if item.record_id == record && item.destination == destination do return index
	}
	return -1
}

@(private)
routed_has_destination :: proc(routed: Routed_Presentation, destination: Destination_ID) -> bool {
	for projection_index in 0 ..< int(routed.projection_count) {
		projection := routed.projections[projection_index]
		if projection.destination == destination do return true
	}
	return false
}

@(private)
presentation_remove_at :: proc(cache: ^Presentation_Cache, index: int) {
	for move_index := index; move_index + 1 < int(cache.item_count); move_index += 1 {
		cache.items[move_index] = cache.items[move_index + 1]
	}
	cache.item_count -= 1
	cache.items[cache.item_count] = {}
}

@(private)
presentation_destination_count :: proc(cache: ^Presentation_Cache, destination: Destination_ID) -> u16 {
	count: u16
	for item in cache.items[:cache.item_count] {
		if item.destination == destination do count += 1
	}
	return count
}

@(private)
presentation_eviction_candidate :: proc(cache: ^Presentation_Cache, incoming: Projection) -> int {
	candidate := -1
	candidate_priority: u8 = 255
	for item, index in cache.items[:cache.item_count] {
		if item.destination != incoming.destination do continue
		priority := presentation_priority(item)
		if candidate < 0 || priority < candidate_priority {
			candidate = index
			candidate_priority = priority
		}
	}
	if candidate < 0 || candidate_priority > presentation_priority(incoming) do return -1
	return candidate
}

@(private)
presentation_priority :: proc(projection: Projection) -> u8 {
	if projection.attention == .Required do return 4
	switch projection.severity {
	case .Error: return 3
	case .Warning: return 2
	case .Information: return 1
	case .Invalid: return 0
	}
	return 0
}
