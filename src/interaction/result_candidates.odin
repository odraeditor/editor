// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "../result_set"
import "base:runtime"
import "core:slice"

@(private)
Result_Candidate_Order :: struct {
	location_index:       u32,
	group:                result_set.Group_ID,
	start:                u64,
	end:                  u64,
	id:                   result_set.Location_ID,
	location_line_width:  int,
	location_column_width: int,
	tabular_location:     bool,
}

/* Result_Candidate_Source owns one temporary adapter over a borrowed result generation. */
Result_Candidate_Source :: struct {
	definition:  Candidate_Source_Definition,
	descriptors: []Candidate_Descriptor_Definition,
	annotations: []Candidate_Annotation_Definition,
	labels:      []u8,
	locations:   []u8,
	allocator:   runtime.Allocator,
}

/* result_candidate_source_build projects one result generation without becoming its owner. */
result_candidate_source_build :: proc(
	view: result_set.View,
	source_generation: u64,
	allocator := context.temp_allocator,
) -> (source: Result_Candidate_Source, ok: bool, failure: Candidate_Failure) {
	if view.set_id == result_set.Result_Set_ID(0) ||
	   view.generation == result_set.Result_Set_Generation(0) ||
	   source_generation == 0 || allocator.procedure == nil {
		return {}, false, Candidate_Failure{code = .Invalid_Source}
	}
	if len(view.locations) > int(MAX_CANDIDATES) {
		return {}, false, Candidate_Failure{code = .Candidate_Limit,
			limit = u64(MAX_CANDIDATES), actual = u64(len(view.locations))}
	}
	source.allocator = allocator
	allocation_error: runtime.Allocator_Error
	source.descriptors, allocation_error = make([]Candidate_Descriptor_Definition, len(view.locations), allocator)
	if allocation_error != nil do return result_candidate_source_allocation_failure(&source)
	source.annotations, allocation_error = make([]Candidate_Annotation_Definition, len(view.locations) * 2, allocator)
	if allocation_error != nil do return result_candidate_source_allocation_failure(&source)
	order, order_error := make([]Result_Candidate_Order, len(view.locations), allocator)
	if order_error != nil do return result_candidate_source_allocation_failure(&source)
	defer delete(order, allocator)
	for location, index in view.locations {
		order[index] = {
			location_index = u32(index), group = location.group_id,
			start = u64(location.start), end = u64(location.end), id = location.id,
		}
	}
	slice.sort_by(order, result_candidate_order_less)
	location_bytes, locations_ok := result_candidate_location_layout(view, order)
	if !locations_ok {
		result_candidate_source_close(&source)
		return {}, false, Candidate_Failure{code = .Invalid_Source}
	}
	label_bytes := 0
	for location in view.locations {
		label := location.preview
		if len(label) == 0 do label = view.metadata.descriptor
		if len(label) == 0 || len(label) > max(int) - label_bytes {
			result_candidate_source_close(&source)
			return {}, false, Candidate_Failure{code = .Invalid_Source}
		}
		label_bytes += len(label)
	}
	source.labels, allocation_error = make([]u8, label_bytes, allocator)
	if allocation_error != nil do return result_candidate_source_allocation_failure(&source)
	source.locations, allocation_error = make([]u8, location_bytes, allocator)
	if allocation_error != nil do return result_candidate_source_allocation_failure(&source)
	annotation_count := 0
	label_cursor := 0
	location_cursor := 0
	for ordered, index in order {
		location := view.locations[ordered.location_index]
		label := location.preview
		if len(label) == 0 do label = view.metadata.descriptor
		copy(source.labels[label_cursor:], transmute([]u8)label)
		for &value in source.labels[label_cursor:label_cursor + len(label)] {
			if value == '\t' do value = ' '
		}
		label = string(source.labels[label_cursor:label_cursor + len(label)])
		label_cursor += len(label)
		annotation_start := annotation_count
		if location.group_id != result_set.Group_ID(0) {
			group_label := ""
			for group in view.groups {
				if group.id == location.group_id {
					group_label = group.label
					break
				}
			}
			if len(group_label) == 0 {
				result_candidate_source_close(&source)
				return {}, false, Candidate_Failure{code = .Invalid_Source}
			}
			source.annotations[annotation_count] = {kind = .Document_Path, text = group_label}
			annotation_count += 1
		}
		if len(location.annotation) > 0 {
			annotation := location.annotation
			if ordered.tabular_location {
				line, column, _ := result_candidate_location_parts(location.annotation)
				location_start := location_cursor
				for location_cursor - location_start < ordered.location_line_width - len(line) {
					source.locations[location_cursor] = '0'
					location_cursor += 1
				}
				copy(source.locations[location_cursor:], transmute([]u8)line)
				location_cursor += len(line)
				source.locations[location_cursor] = ':'
				location_cursor += 1
				column_start := location_cursor
				for location_cursor - column_start < ordered.location_column_width - len(column) {
					source.locations[location_cursor] = '0'
					location_cursor += 1
				}
				copy(source.locations[location_cursor:], transmute([]u8)column)
				location_cursor += len(column)
				annotation = string(source.locations[location_start:location_cursor])
			}
			source.annotations[annotation_count] = {kind = .Location, text = annotation}
			annotation_count += 1
		}
		annotations := source.annotations[annotation_start:annotation_count]
		source.descriptors[index] = {
			identity = {kind = 13, primary = u64(view.set_id), secondary = u64(location.id)},
			label = label,
			annotations = annotations,
			action = {
				kind = .Visit_Result,
				owner_generation = u64(view.generation),
				primary = u64(view.set_id),
				secondary = u64(location.id),
				graph_identity = {u64(location.buffer_id), u64(location.revision),
					u64(location.start), u64(location.end), location.source_identity,
					u64(view.source.id)},
			},
			availability = .Available,
			label_highlight_start = location.preview_match_start,
			label_highlight_end = location.preview_match_end,
			label_highlight_present = location.preview_match_present,
		}
	}
	source.definition = {
		kind = .Results,
		scope_identity = u64(view.set_id),
		scope_generation = u64(view.generation),
		source_generation = source_generation,
		descriptors = source.descriptors,
	}
	return source, true, {}
}

@(private)
result_candidate_location_layout :: proc(
	view: result_set.View,
	order: []Result_Candidate_Order,
) -> (location_bytes: int, ok: bool) {
	group_start := 0
	for group_start < len(order) {
		group_end := group_start + 1
		for group_end < len(order) && order[group_end].group == order[group_start].group {
			group_end += 1
		}
		line_width, column_width := 0, 0
		tabular := true
		for ordered in order[group_start:group_end] {
			location := view.locations[ordered.location_index]
			line, column, location_ok := result_candidate_location_parts(location.annotation)
			if !location_ok {
				tabular = false
				break
			}
			line_width = max(line_width, len(line))
			column_width = max(column_width, len(column))
		}
		for index in group_start ..< group_end {
			annotation_bytes := 0
			if tabular {
				order[index].location_line_width = line_width
				order[index].location_column_width = column_width
				order[index].tabular_location = true
				annotation_bytes = line_width + 1 + column_width
			}
			if annotation_bytes > max(int) - location_bytes do return 0, false
			location_bytes += annotation_bytes
		}
		group_start = group_end
	}
	return location_bytes, true
}

@(private)
result_candidate_location_parts :: proc(location: string) -> (line, column: string, ok: bool) {
	separator := -1
	for value, index in location {
		if value != ':' do continue
		if separator >= 0 do return "", "", false
		separator = index
	}
	if separator <= 0 || separator >= len(location) - 1 do return "", "", false
	line = location[:separator]
	column = location[separator + 1:]
	for value in line do if value < '0' || value > '9' do return "", "", false
	for value in column do if value < '0' || value > '9' do return "", "", false
	return line, column, true
}

@(private)
result_candidate_order_less :: proc(left, right: Result_Candidate_Order) -> bool {
	if left.group != right.group do return left.group < right.group
	if left.start != right.start do return left.start < right.start
	if left.end != right.end do return left.end < right.end
	return left.id < right.id
}

/* result_candidate_source_close releases temporary projection storage. */
result_candidate_source_close :: proc(source: ^Result_Candidate_Source) -> bool {
	if source == nil || source.allocator.procedure == nil do return false
	delete(source.annotations, source.allocator)
	delete(source.descriptors, source.allocator)
	delete(source.labels, source.allocator)
	delete(source.locations, source.allocator)
	source^ = {}
	return true
}

@(private)
result_candidate_source_allocation_failure :: proc(
	source: ^Result_Candidate_Source,
) -> (Result_Candidate_Source, bool, Candidate_Failure) {
	result_candidate_source_close(source)
	return {}, false, Candidate_Failure{code = .Persistent_Memory_Limit}
}
