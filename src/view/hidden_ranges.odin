// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package view

import "../editor"
import "base:runtime"

/* visibility_replace atomically installs one normalized hidden-range generation. */
visibility_replace :: proc(
	registry: ^Registry,
	handle: View_Handle,
	ranges: []Hidden_Range,
	temporary_allocator := context.temp_allocator,
) -> (update: Visibility_Update, ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return {}, false, slot_failure
	}
	if !prepare_mutation(registry, handle, slot) {
		return {}, false, mutation_failure(registry, handle, slot)
	}
	if slot.visibility.generation == Visibility_Generation(max(u64)) {
		return {}, false, view_failure(registry, handle, .Visibility_Generation_Limit)
	}
	if temporary_allocator.procedure == nil {
		return {}, false, view_failure(registry, handle, .Invalid_Config)
	}
	if u64(len(ranges)) > u64(MAX_HIDDEN_RANGES) {
		failure = view_failure(registry, handle, .Hidden_Range_Limit)
		failure.limit = u64(MAX_HIDDEN_RANGES)
		failure.actual = u64(len(ranges))
		return {}, false, failure
	}
	stats, stats_ok, stats_failure := editor.buffer_stats(slot.buffer)
	if !stats_ok {
		return {}, false, editor_failure_context(registry, handle, stats_failure)
	}

	candidates, candidate_error := make([]Hidden_Range, len(ranges), temporary_allocator)
	if candidate_error != nil {
		return {}, false, view_failure(registry, handle, .Persistent_Memory_Limit)
	}
	defer delete(candidates, temporary_allocator)
	for source_range, index in ranges {
		if !hidden_range_is_valid(source_range, stats) {
			return {}, false, view_failure(registry, handle, .Invalid_Hidden_Range)
		}
		candidates[index] = source_range
	}
	hidden_range_sort(candidates)
	normalized_count := hidden_range_normalize(candidates)

	data := registry_data(registry)
	assert(data != nil)
	prepared: []Hidden_Range_State
	prepared_bytes: u64
	if normalized_count > 0 {
		prepared_error: runtime.Allocator_Error
		prepared, prepared_error = make(
			[]Hidden_Range_State,
			normalized_count,
			data.allocator,
		)
		if prepared_error != nil {
			return {}, false, view_failure(registry, handle, .Persistent_Memory_Limit)
		}
		prepared_bytes = u64(normalized_count) * u64(size_of(Hidden_Range_State))
	}
	created_count: int
	for candidate, index in candidates[:normalized_count] {
		start, start_ok, start_failure := editor.buffer_anchor_create(
			slot.buffer,
			candidate.start,
			.Right,
			.Collapse,
		)
		if !start_ok {
			hidden_range_prepared_release(slot.buffer, prepared, created_count, false)
			if prepared != nil do delete(prepared, data.allocator)
			return {}, false, editor_failure_context(registry, handle, start_failure)
		}
		prepared[index].start = start
		end, end_ok, end_failure := editor.buffer_anchor_create(
			slot.buffer,
			candidate.end,
			.Left,
			.Collapse,
		)
		if !end_ok {
			hidden_range_prepared_release(slot.buffer, prepared, index + 1, true)
			if prepared != nil do delete(prepared, data.allocator)
			return {}, false, editor_failure_context(registry, handle, end_failure)
		}
		prepared[index].end = end
		created_count += 1
	}

	visibility_state_close(data, slot, slot.buffer)
	slot.visibility.ranges = prepared
	slot.visibility.storage_bytes = prepared_bytes
	if prepared_bytes > 0 do data.storage_bytes += prepared_bytes
	slot.visibility.generation = Visibility_Generation(
		u64(slot.visibility.generation) + 1,
	)
	slot.state_generation += 1
	return Visibility_Update {
		generation = slot.visibility.generation,
		source_revision = stats.revision,
		range_count = u32(normalized_count),
		changed = true,
	}, true, {}
}

/* visibility_clear releases all hidden ranges owned by one view. */
visibility_clear :: proc(
	registry: ^Registry,
	handle: View_Handle,
) -> (update: Visibility_Update, ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return {}, false, slot_failure
	}
	stats, stats_ok, stats_failure := editor.buffer_stats(slot.buffer)
	if !stats_ok {
		return {}, false, editor_failure_context(registry, handle, stats_failure)
	}
	if len(slot.visibility.ranges) == 0 {
		return Visibility_Update {
			generation = slot.visibility.generation,
			source_revision = stats.revision,
		}, true, {}
	}
	return visibility_replace(registry, handle, nil)
}

/* visibility_copy_ranges writes current normalized ranges into caller storage. */
visibility_copy_ranges :: proc(
	registry: ^Registry,
	handle: View_Handle,
	destination: []Hidden_Range,
) -> (snapshot: Visibility_Snapshot, ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return {}, false, slot_failure
	}
	stats, stats_ok, stats_failure := editor.buffer_stats(slot.buffer)
	if !stats_ok {
		return {}, false, editor_failure_context(registry, handle, stats_failure)
	}
	reconciled, reconcile_failure := visibility_reconcile(registry, handle, slot)
	if !reconciled {
		return {}, false, reconcile_failure
	}
	if len(destination) < len(slot.visibility.ranges) {
		failure = view_failure(registry, handle, .Hidden_Range_Destination_Limit)
		failure.limit = u64(len(destination))
		failure.actual = u64(len(slot.visibility.ranges))
		return {}, false, failure
	}
	for retained, index in slot.visibility.ranges {
		start, start_ok, start_failure := editor.buffer_anchor_resolve(slot.buffer, retained.start)
		if !start_ok {
			return {}, false, editor_failure_context(registry, handle, start_failure)
		}
		end, end_ok, end_failure := editor.buffer_anchor_resolve(slot.buffer, retained.end)
		if !end_ok {
			return {}, false, editor_failure_context(registry, handle, end_failure)
		}
		destination[index] = Hidden_Range{start = start, end = end}
	}
	return Visibility_Snapshot {
		generation = slot.visibility.generation,
		source_revision = stats.revision,
		range_count = u32(len(slot.visibility.ranges)),
	}, true, {}
}

/* visibility_position_is_hidden checks one exact current source position. */
visibility_position_is_hidden :: proc(
	registry: ^Registry,
	handle: View_Handle,
	position: editor.Position,
) -> (hidden: bool, ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, false, slot_failure
	}
	stats, stats_ok, stats_failure := editor.buffer_stats(slot.buffer)
	if !stats_ok {
		return false, false, editor_failure_context(registry, handle, stats_failure)
	}
	if position.buffer_id != stats.buffer_id || position.revision != stats.revision ||
	   u64(position.byte_offset) > stats.text_bytes {
		return false, false, view_failure(registry, handle, .Invalid_Hidden_Range)
	}
	reconciled, reconcile_failure := visibility_reconcile(registry, handle, slot)
	if !reconciled {
		return false, false, reconcile_failure
	}
	for retained in slot.visibility.ranges {
		start, _, _ := editor.buffer_anchor_resolve(slot.buffer, retained.start)
		end, _, _ := editor.buffer_anchor_resolve(slot.buffer, retained.end)
		if position.byte_offset >= start.byte_offset && position.byte_offset < end.byte_offset {
			return true, true, {}
		}
	}
	return false, true, {}
}

/* visibility_reveal_position removes only ranges containing one current position. */
visibility_reveal_position :: proc(
	registry: ^Registry,
	handle: View_Handle,
	position: editor.Position,
) -> (update: Visibility_Update, ok: bool, failure: Failure_Context) {
	return visibility_reveal(registry, handle, position, position, true)
}

/* visibility_reveal_range removes every hidden interval overlapping one range. */
visibility_reveal_range :: proc(
	registry: ^Registry,
	handle: View_Handle,
	start, end: editor.Position,
) -> (update: Visibility_Update, ok: bool, failure: Failure_Context) {
	return visibility_reveal(registry, handle, start, end, false)
}

@(private)
visibility_reveal :: proc(
	registry: ^Registry,
	handle: View_Handle,
	start, end: editor.Position,
	point_only: bool,
) -> (update: Visibility_Update, ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return {}, false, slot_failure
	}
	if !prepare_mutation(registry, handle, slot) {
		return {}, false, mutation_failure(registry, handle, slot)
	}
	if slot.visibility.generation == Visibility_Generation(max(u64)) {
		return {}, false, view_failure(registry, handle, .Visibility_Generation_Limit)
	}
	stats, stats_ok, stats_failure := editor.buffer_stats(slot.buffer)
	if !stats_ok {
		return {}, false, editor_failure_context(registry, handle, stats_failure)
	}
	if start.buffer_id != stats.buffer_id || end.buffer_id != stats.buffer_id ||
	   start.revision != stats.revision || end.revision != stats.revision ||
	   u64(start.byte_offset) > stats.text_bytes || u64(end.byte_offset) > stats.text_bytes ||
	   (!point_only && start.byte_offset > end.byte_offset) {
		return {}, false, view_failure(registry, handle, .Invalid_Hidden_Range)
	}
	reconciled, reconcile_failure := visibility_reconcile(registry, handle, slot)
	if !reconciled {
		return {}, false, reconcile_failure
	}
	write_index: int
	changed := false
	for retained in slot.visibility.ranges {
		retained_start, _, _ := editor.buffer_anchor_resolve(slot.buffer, retained.start)
		retained_end, _, _ := editor.buffer_anchor_resolve(slot.buffer, retained.end)
		overlaps := start.byte_offset < retained_end.byte_offset &&
		            end.byte_offset > retained_start.byte_offset
		if point_only {
			overlaps = start.byte_offset >= retained_start.byte_offset &&
			           start.byte_offset < retained_end.byte_offset
		}
		if overlaps {
			start_anchor := retained.start
			end_anchor := retained.end
			start_released, _ := editor.buffer_anchor_release(slot.buffer, &start_anchor)
			end_released, _ := editor.buffer_anchor_release(slot.buffer, &end_anchor)
			assert(start_released && end_released)
			changed = true
			continue
		}
		slot.visibility.ranges[write_index] = retained
		write_index += 1
	}
	slot.visibility.ranges = slot.visibility.ranges[:write_index]
	if changed {
		slot.visibility.generation = Visibility_Generation(
			u64(slot.visibility.generation) + 1,
		)
		slot.state_generation += 1
	}
	return Visibility_Update {
		generation = slot.visibility.generation,
		source_revision = stats.revision,
		range_count = u32(write_index),
		changed = changed,
	}, true, {}
}

@(private)
hidden_range_is_valid :: proc(source_range: Hidden_Range, stats: editor.Buffer_Stats) -> bool {
	return source_range.start.buffer_id == stats.buffer_id &&
	       source_range.end.buffer_id == stats.buffer_id &&
	       source_range.start.revision == stats.revision &&
	       source_range.end.revision == stats.revision &&
	       source_range.start.byte_offset < source_range.end.byte_offset &&
	       u64(source_range.end.byte_offset) <= stats.text_bytes
}

@(private)
hidden_range_sort :: proc(ranges: []Hidden_Range) {
	for index in 1 ..< len(ranges) {
		candidate := ranges[index]
		cursor := index
		for cursor > 0 {
			previous := ranges[cursor - 1]
			if previous.start.byte_offset < candidate.start.byte_offset ||
			   (previous.start.byte_offset == candidate.start.byte_offset &&
			    previous.end.byte_offset <= candidate.end.byte_offset) {
				break
			}
			ranges[cursor] = previous
			cursor -= 1
		}
		ranges[cursor] = candidate
	}
}

@(private)
hidden_range_normalize :: proc(ranges: []Hidden_Range) -> int {
	count: int
	for candidate in ranges {
		if count == 0 {
			ranges[0] = candidate
			count = 1
			continue
		}
		previous := &ranges[count - 1]
		if candidate.start.byte_offset <= previous.end.byte_offset {
			if candidate.end.byte_offset > previous.end.byte_offset {
				previous.end = candidate.end
			}
			continue
		}
		ranges[count] = candidate
		count += 1
	}
	return count
}

@(private)
hidden_range_prepared_release :: proc(
	buffer: ^editor.Buffer,
	ranges: []Hidden_Range_State,
	count: int,
	last_has_only_start: bool,
) {
	for index in 0 ..< count {
		start := ranges[index].start
		if start.buffer_id != editor.Buffer_ID(0) {
			released, _ := editor.buffer_anchor_release(buffer, &start)
			assert(released)
		}
		if last_has_only_start && index == count - 1 do continue
		end := ranges[index].end
		if end.buffer_id != editor.Buffer_ID(0) {
			released, _ := editor.buffer_anchor_release(buffer, &end)
			assert(released)
		}
	}
}

@(private)
visibility_reconcile :: proc(
	registry: ^Registry,
	handle: View_Handle,
	slot: ^View_Slot,
) -> (ok: bool, failure: Failure_Context) {
	collapsed := false
	for retained in slot.visibility.ranges {
		start, start_ok, start_failure := editor.buffer_anchor_resolve(slot.buffer, retained.start)
		if !start_ok {
			return false, editor_failure_context(registry, handle, start_failure)
		}
		end, end_ok, end_failure := editor.buffer_anchor_resolve(slot.buffer, retained.end)
		if !end_ok {
			return false, editor_failure_context(registry, handle, end_failure)
		}
		if start.byte_offset >= end.byte_offset do collapsed = true
	}
	if collapsed &&
	   (slot.visibility.generation == Visibility_Generation(max(u64)) ||
	    slot.state_generation == max(u64)) {
		return false, view_failure(registry, handle, .Visibility_Generation_Limit)
	}

	write_index: int
	changed := false
	for retained in slot.visibility.ranges {
		start, start_ok, start_failure := editor.buffer_anchor_resolve(slot.buffer, retained.start)
		if !start_ok {
			return false, editor_failure_context(registry, handle, start_failure)
		}
		end, end_ok, end_failure := editor.buffer_anchor_resolve(slot.buffer, retained.end)
		if !end_ok {
			return false, editor_failure_context(registry, handle, end_failure)
		}
		if start.byte_offset >= end.byte_offset {
			start_anchor := retained.start
			end_anchor := retained.end
			start_released, _ := editor.buffer_anchor_release(slot.buffer, &start_anchor)
			end_released, _ := editor.buffer_anchor_release(slot.buffer, &end_anchor)
			assert(start_released && end_released)
			changed = true
			continue
		}
		slot.visibility.ranges[write_index] = retained
		write_index += 1
	}
	if changed {
		slot.visibility.ranges = slot.visibility.ranges[:write_index]
		slot.visibility.generation = Visibility_Generation(
			u64(slot.visibility.generation) + 1,
		)
		slot.state_generation += 1
	}
	return true, {}
}

@(private)
visibility_state_validate :: proc(slot: ^View_Slot) -> (ok: bool, failure: editor.Failure_Context) {
	for retained in slot.visibility.ranges {
		_, start_ok, start_failure := editor.buffer_anchor_resolve(slot.buffer, retained.start)
		if !start_ok do return false, start_failure
		_, end_ok, end_failure := editor.buffer_anchor_resolve(slot.buffer, retained.end)
		if !end_ok do return false, end_failure
	}
	return true, {}
}

@(private)
visibility_state_close :: proc(data: ^Registry_Data, slot: ^View_Slot, buffer: ^editor.Buffer) {
	assert(data != nil && slot != nil)
	if editor.buffer_is_live(buffer) {
		for retained in slot.visibility.ranges {
			start := retained.start
			end := retained.end
			start_released, _ := editor.buffer_anchor_release(buffer, &start)
			end_released, _ := editor.buffer_anchor_release(buffer, &end)
			assert(start_released && end_released)
		}
	}
	if slot.visibility.ranges != nil {
		delete(slot.visibility.ranges, data.allocator)
		assert(data.storage_bytes >= slot.visibility.storage_bytes)
		data.storage_bytes -= slot.visibility.storage_bytes
	}
	generation := slot.visibility.generation
	slot.visibility = Visibility_State{generation = generation}
}
