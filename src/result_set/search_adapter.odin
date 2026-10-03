// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package result_set

import "../editor"
import editor_view "../view"
import "base:runtime"
import "core:fmt"
import "core:unicode/utf8"

SEARCH_RESULT_PREVIEW_BYTES :: u64(MAX_RESULT_PREVIEW_BYTES)

@(private)
Search_Result_Preview :: struct {
	start:       editor.Byte_Offset,
	end:         editor.Byte_Offset,
	line:        u64,
	column:      u64,
	match_start: u32,
	match_end:   u32,
	match_present: bool,
}

Search_Materialization_Config :: struct {
	set_id:              Result_Set_ID,
	expected_generation: Result_Set_Generation,
	source_id:           Source_ID,
	buffer:              ^editor.Buffer,
	allocator:           runtime.Allocator,
}

/* search_materialize publishes copied active-search locations without owning matching. */
search_materialize :: proc(
	registry: ^Registry,
	snapshot: editor_view.Search_Snapshot,
	config: Search_Materialization_Config,
) -> (Result, bool, Failure) {
	if !snapshot.present || snapshot.source_revision != snapshot.scope.revision ||
	   config.buffer == nil ||
	   config.source_id == Source_ID(0) || config.allocator.procedure == nil {
		return {}, false, Failure{code = .Invalid_Publication, set_id = config.set_id}
	}
	stats, stats_ok, _ := editor.buffer_stats(config.buffer)
	if !stats_ok || stats.buffer_id != snapshot.scope.buffer_id ||
	   stats.revision != snapshot.scope.revision {
		return {}, false, Failure{code = .Invalid_Publication, set_id = config.set_id}
	}
	definitions, allocation_error := make([]Location_Definition, len(snapshot.occurrences), config.allocator)
	if allocation_error != nil do return {}, false, Failure{code = .Persistent_Memory_Limit,
		set_id = config.set_id}
	defer delete(definitions, config.allocator)
	previews, previews_error := make([]Search_Result_Preview, len(snapshot.occurrences), config.allocator)
	if previews_error != nil do return {}, false, Failure{code = .Persistent_Memory_Limit,
		set_id = config.set_id}
	defer delete(previews, config.allocator)
	total_preview_bytes := u64(0)
	for occurrence, index in snapshot.occurrences {
		if occurrence.buffer_id != snapshot.scope.buffer_id || occurrence.revision != snapshot.scope.revision ||
		   occurrence.start < snapshot.scope.start || occurrence.end > snapshot.scope.end {
			return {}, false, Failure{code = .Invalid_Location, set_id = config.set_id}
		}
		position, positioned, _ := editor.buffer_position(config.buffer, occurrence.start)
		if !positioned {
			return {}, false, Failure{code = .Invalid_Location, set_id = config.set_id}
		}
		line, line_ok, _ := editor.buffer_line_at_position(config.buffer, position)
		if !line_ok || occurrence.end > line.content_end {
			return {}, false, Failure{code = .Invalid_Location, set_id = config.set_id}
		}
		column, column_ok := search_result_column(config.buffer, line.start, occurrence.start)
		if !column_ok {
			return {}, false, Failure{code = .Invalid_Location, set_id = config.set_id}
		}
		preview_start := line.start
		preview_end := line.content_end
		if u64(preview_end - preview_start) > SEARCH_RESULT_PREVIEW_BYTES {
			preview_start = occurrence.start
			preview_end = min(line.content_end, preview_start + editor.Byte_Offset(SEARCH_RESULT_PREVIEW_BYTES))
			for preview_end > preview_start {
				_, boundary_ok, _ := editor.buffer_position(config.buffer, preview_end)
				if boundary_ok do break
				preview_end -= 1
			}
		}
		preview_bytes := u64(preview_end - preview_start)
		if total_preview_bytes > MAX_RESULT_TEMPORARY_BYTES - preview_bytes {
			return {}, false, Failure{code = .Text_Limit, set_id = config.set_id,
				limit = MAX_RESULT_TEMPORARY_BYTES, actual = total_preview_bytes + preview_bytes}
		}
		total_preview_bytes += preview_bytes
		previews[index] = {
			start = preview_start,
			end = preview_end,
			line = line.line_index + 1,
			column = column,
			match_present = occurrence.end <= preview_end,
		}
		if previews[index].match_present && occurrence.start < occurrence.end {
			previews[index].match_start = u32(occurrence.start - preview_start)
			previews[index].match_end = u32(occurrence.end - preview_start)
		} else {
			previews[index].match_present = false
		}
	}
	preview_storage, preview_error := make([]u8, int(total_preview_bytes), config.allocator)
	if preview_error != nil do return {}, false, Failure{code = .Persistent_Memory_Limit,
		set_id = config.set_id}
	defer delete(preview_storage, config.allocator)
	annotation_storage, annotation_error := make([]u8, len(snapshot.occurrences) * 64, config.allocator)
	if annotation_error != nil do return {}, false, Failure{code = .Persistent_Memory_Limit,
		set_id = config.set_id}
	defer delete(annotation_storage, config.allocator)
	preview_cursor := 0
	annotation_cursor := 0
	for occurrence, index in snapshot.occurrences {
		preview := previews[index]
		preview_size := int(preview.end - preview.start)
		copied, copied_ok, _ := editor.buffer_inspect(
			config.buffer,
			preview.start,
			preview.end,
			preview_storage[preview_cursor:preview_cursor + preview_size],
		)
		if !copied_ok || copied != u64(preview_size) {
			return {}, false, Failure{code = .Invalid_Location, set_id = config.set_id}
		}
		preview_text := string(preview_storage[preview_cursor:preview_cursor + preview_size])
		annotation := fmt.bprintf(
			annotation_storage[annotation_cursor:],
			"%d:%d",
			preview.line,
			preview.column,
		)
		preview_cursor += preview_size
		annotation_cursor += len(annotation)
		definitions[index] = Location_Definition {
			id = Location_ID(u64(occurrence.start) + 1),
			buffer_id = occurrence.buffer_id,
			revision = occurrence.revision,
			start = occurrence.start,
			end = occurrence.end,
			source_identity = u64(index + 1),
			preview = preview_text,
			annotation = annotation,
			preview_match_start = preview.match_start,
			preview_match_end = preview.match_end,
			preview_match_present = preview.match_present,
		}
	}
	completeness := Completeness.Incomplete
	continuation := Continuation{present = true, provider = u64(config.source_id),
		cursor = u64(snapshot.progress.next_offset), limit = u64(snapshot.limits.retained_occurrences)}
	if snapshot.progress.complete {
		completeness = .Complete
		continuation = {}
	}
	metadata := Source_Metadata{descriptor = snapshot.query}
	metadata.values = {
		u64(snapshot.kind), u64(snapshot.policy.case_mode), u64(snapshot.policy.boundary_mode),
		u64(snapshot.policy.whitespace_mode), u64(1 if snapshot.policy.wrap else 0),
		u64(snapshot.direction), snapshot.interaction_generation, u64(snapshot.source_revision),
	}
	selected := Location_ID(0)
	has_selection := snapshot.has_current && int(snapshot.current_index) < len(definitions)
	if has_selection do selected = definitions[snapshot.current_index].id
	return registry_publish(registry, Publication {
		set_id = config.set_id,
		expected_generation = config.expected_generation,
		source = Source_Descriptor{id = config.source_id,
			generation = Source_Generation(snapshot.interaction_generation), kind = .Active_Search},
		metadata = metadata,
		completeness = completeness,
		continuation = continuation,
		refresh = Refresh_Descriptor{provider = u64(config.source_id),
			query_identity = snapshot.interaction_generation,
			policy_generation = u64(snapshot.policy_generation),
			scope_generation = u64(snapshot.source_revision)},
		edit_capability = .Single_Buffer,
		locations = definitions,
		selected = selected,
		has_selection = has_selection,
	})
}

@(private)
search_result_column :: proc(
	buffer: ^editor.Buffer,
	line_start, match_start: editor.Byte_Offset,
) -> (column: u64, ok: bool) {
	column = 1
	cursor := line_start
	storage: [4 * 1_024]u8
	for cursor < match_start {
		chunk_end := min(match_start, cursor + editor.Byte_Offset(len(storage)))
		for chunk_end > cursor {
			_, boundary_ok, _ := editor.buffer_position(buffer, chunk_end)
			if boundary_ok do break
			chunk_end -= 1
		}
		if chunk_end == cursor do return 0, false
		chunk_size := int(chunk_end - cursor)
		copied, copied_ok, _ := editor.buffer_inspect(
			buffer, cursor, chunk_end, storage[:chunk_size])
		if !copied_ok || copied != u64(chunk_size) do return 0, false
		bytes := storage[:chunk_size]
		byte_cursor := 0
		for byte_cursor < len(bytes) {
			_, width := utf8.decode_rune(bytes[byte_cursor:])
			if width <= 0 do return 0, false
			column += 1
			byte_cursor += width
		}
		cursor = chunk_end
	}
	return column, true
}
