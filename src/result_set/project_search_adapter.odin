// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package result_set

import "../editor"
import "../project_search"
import "base:runtime"
import "core:fmt"

/* Project_Search_Materialization_Config identifies one replaceable Project result set. */
Project_Search_Materialization_Config :: struct {
	set_id:              Result_Set_ID,
	expected_generation: Result_Set_Generation,
	source_id:           Source_ID,
	allocator:           runtime.Allocator,
}

/* project_search_materialize copies Project matches into the common result model. */
project_search_materialize :: proc(
	registry: ^Registry,
	provider: ^project_search.Native_Provider,
	config: Project_Search_Materialization_Config,
) -> (Result, bool, Failure) {
	view, viewed, _ := project_search.native_provider_view(provider)
	if !viewed || config.set_id == Result_Set_ID(0) || config.source_id == Source_ID(0) ||
	   config.allocator.procedure == nil ||
	   (view.inspection.lifecycle != .Complete && view.inspection.lifecycle != .Cancelled) {
		return {}, false, Failure{code = .Invalid_Publication, set_id = config.set_id}
	}
	definitions, definitions_error := make([]Location_Definition, len(view.matches), config.allocator)
	if definitions_error != nil {
		return {}, false, Failure{code = .Persistent_Memory_Limit, set_id = config.set_id}
	}
	defer delete(definitions, config.allocator)
	groups, groups_error := make([]Group_Definition, len(view.matches), config.allocator)
	if groups_error != nil {
		return {}, false, Failure{code = .Persistent_Memory_Limit, set_id = config.set_id}
	}
	defer delete(groups, config.allocator)
	annotations, annotations_error := make([]u8, len(view.matches) * 64, config.allocator)
	if annotations_error != nil {
		return {}, false, Failure{code = .Persistent_Memory_Limit, set_id = config.set_id}
	}
	defer delete(annotations, config.allocator)
	group_count := 0
	annotation_cursor := 0
	previous_path := ""
	group_id: Group_ID
	for match, index in view.matches {
		if index == 0 || match.path != previous_path {
			group_count += 1
			group_id = Group_ID(group_count)
			groups[group_count - 1] = {id = group_id, label = match.path}
			previous_path = match.path
		}
		annotation := fmt.bprintf(annotations[annotation_cursor:], "%d:%d", match.line, match.column)
		annotation_cursor += len(annotation)
		definitions[index] = {
			id = Location_ID(match.id),
			group_id = group_id,
			buffer_id = editor.Buffer_ID(match.file),
			revision = editor.Revision(view.inspection.result_generation),
			start = editor.Byte_Offset(match.start),
			end = editor.Byte_Offset(match.end),
			source_identity = match.id,
			preview = match.preview,
			annotation = annotation,
			preview_match_start = match.preview_match_start,
			preview_match_end = match.preview_match_end,
			preview_match_present = match.preview_match_start < match.preview_match_end &&
				match.preview_match_end <= u32(len(match.preview)),
		}
	}
	completeness := Completeness.Complete
	continuation: Continuation
	if view.inspection.completeness == .Incomplete {
		completeness = .Incomplete
		continuation = {present = true, provider = u64(view.inspection.provider),
			cursor = view.inspection.continuation.file_index,
			limit = u64(view.request.limits.files)}
	}
	return registry_publish(registry, Publication{
		set_id = config.set_id,
		expected_generation = config.expected_generation,
		source = {id = config.source_id,
			generation = Source_Generation(view.inspection.result_generation),
			kind = .Project_Search},
		metadata = {descriptor = view.request.pattern,
			values = {u64(view.request.pattern_kind), u64(view.request.policy.search.case_mode),
				u64(view.request.policy.search.boundary_mode),
				u64(view.request.policy.search.whitespace_mode),
				u64(view.request.project.id), u64(view.request.project.generation),
				u64(view.inspection.provider), u64(view.inspection.provider_generation)}},
		completeness = completeness,
		continuation = continuation,
		refresh = {provider = u64(view.inspection.provider), query_identity = u64(view.request.query_id),
			policy_generation = u64(view.request.generation),
			scope_generation = u64(view.request.project.generation)},
		edit_capability = .Read_Only,
		locations = definitions,
		groups = groups[:group_count],
	})
}
