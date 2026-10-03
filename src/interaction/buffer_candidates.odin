// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "../editor_session"
import "../project"
import "base:runtime"

/* Buffer_Candidate_Source owns borrowed-definition storage until session admission. */
Buffer_Candidate_Source :: struct {
	definition:  Candidate_Source_Definition,
	descriptors: []Candidate_Descriptor_Definition,
	fields:      []string,
	annotations: []Candidate_Annotation_Definition,
	allocator:   runtime.Allocator,
}

/* session_buffer_candidate_source_build adapts one complete editor-session inventory. */
session_buffer_candidate_source_build :: proc(
	batch: ^editor_session.Descriptor_Batch,
	allocator := context.temp_allocator,
) -> (source: Buffer_Candidate_Source, ok: bool, failure: Candidate_Failure) {
	if batch == nil || batch.state == nil || allocator.procedure == nil {
		return {}, false, Candidate_Failure{code = .Invalid_Source}
	}
	if len(batch.descriptors) == 0 {
		return {}, false, Candidate_Failure{code = .Invalid_Source}
	}
	first := batch.descriptors[0].graph.entry
	return buffer_candidate_source_build(
		batch.descriptors,
		nil,
		.Session_Buffers,
		u64(first.registry.session.session_id),
		u64(first.registry.session.generation),
		u64(first.registry.generation),
		"",
		allocator,
	)
}

/* session_buffer_candidate_source_build_query adds one unmatched synthetic name. */
session_buffer_candidate_source_build_query :: proc(
	batch: ^editor_session.Descriptor_Batch,
	query: string,
	source_generation: u64,
	allocator := context.temp_allocator,
) -> (source: Buffer_Candidate_Source, ok: bool, failure: Candidate_Failure) {
	if batch == nil || batch.state == nil || len(batch.descriptors) == 0 {
		return {}, false, Candidate_Failure{code = .Invalid_Source}
	}
	first := batch.descriptors[0].graph.entry
	synthetic := ""
	if buffer_candidate_name_is_synthetic(batch.descriptors, query) {synthetic = query}
	return buffer_candidate_source_build(
		batch.descriptors,
		nil,
		.Session_Buffers,
		u64(first.registry.session.session_id),
		u64(first.registry.session.generation),
		source_generation,
		synthetic,
		allocator,
	)
}

/* project_buffer_candidate_source_build adapts the complete Project-owned inventory subset. */
project_buffer_candidate_source_build :: proc(
	batch: ^editor_session.Descriptor_Batch,
	classified: ^editor_session.Project_Buffer_Batch,
	allocator := context.temp_allocator,
) -> (source: Buffer_Candidate_Source, ok: bool, failure: Candidate_Failure) {
	if batch == nil || batch.state == nil || classified == nil || classified.state == nil ||
	   !project.project_handle_is_valid(classified.project_handle) || allocator.procedure == nil {
		return {}, false, Candidate_Failure{code = .Invalid_Source}
	}
	return buffer_candidate_source_build(
		batch.descriptors,
		classified.descriptors,
		.Project_Buffers,
		u64(classified.project_handle.id),
		u64(classified.project_handle.generation),
		buffer_candidate_registry_generation(batch.descriptors),
		"",
		allocator,
	)
}

/* project_buffer_candidate_source_build_query adapts one refreshed Project subset generation. */
project_buffer_candidate_source_build_query :: proc(
	batch: ^editor_session.Descriptor_Batch,
	classified: ^editor_session.Project_Buffer_Batch,
	source_generation: u64,
	allocator := context.temp_allocator,
) -> (source: Buffer_Candidate_Source, ok: bool, failure: Candidate_Failure) {
	if batch == nil || batch.state == nil || classified == nil || classified.state == nil ||
	   !project.project_handle_is_valid(classified.project_handle) || allocator.procedure == nil {
		return {}, false, Candidate_Failure{code = .Invalid_Source}
	}
	return buffer_candidate_source_build(
		batch.descriptors,
		classified.descriptors,
		.Project_Buffers,
		u64(classified.project_handle.id),
		u64(classified.project_handle.generation),
		source_generation,
		"",
		allocator,
	)
}

/* buffer_candidate_source_close releases temporary adapter storage. */
buffer_candidate_source_close :: proc(source: ^Buffer_Candidate_Source) -> bool {
	if source == nil || source.allocator.procedure == nil {
		return false
	}
	delete(source.annotations, source.allocator)
	delete(source.fields, source.allocator)
	delete(source.descriptors, source.allocator)
	source^ = {}
	return true
}

/* buffer_candidate_action_entry reconstructs one checked live entry identity. */
buffer_candidate_action_entry :: proc(
	action: Candidate_Action,
	session: editor_session.Session_Handle,
) -> (entry: editor_session.Entry_Handle, ok: bool) {
	if action.kind != .Activate_Buffer || action.owner_generation == 0 ||
	   action.primary == 0 || action.secondary == 0 ||
	   !editor_session.session_handle_is_valid(session) {
		return {}, false
	}
	return editor_session.Entry_Handle {
		registry = {
			session = session,
			generation = editor_session.Registry_Generation(action.owner_generation),
		},
		entry_id = editor_session.Entry_ID(action.primary),
		slot = u32(action.secondary >> 32),
		generation = u32(action.secondary & 0xffff_ffff),
	}, true
}

/* buffer_candidate_action_graph_matches revalidates the complete captured object graph. */
buffer_candidate_action_graph_matches :: proc(
	action: Candidate_Action,
	graph: editor_session.Object_Graph_Identity,
) -> bool {
	entry, entry_ok := buffer_candidate_action_entry(action, graph.entry.registry.session)
	if !entry_ok || entry != graph.entry {return false}
	return action.graph_identity[0] == u64(graph.buffer_id) &&
	       action.graph_identity[1] == u64(graph.history_id) &&
	       action.graph_identity[2] == u64(graph.primary_view.registry_id) &&
	       action.graph_identity[3] == u64(graph.primary_view.view_id) &&
	       action.graph_identity[4] == u64(graph.primary_view.slot) << 32 | u64(graph.primary_view.generation) &&
	       (action.graph_identity[5] != 0) == graph.has_document &&
	       action.graph_identity[5] == u64(graph.document_id)
}

@(private)
buffer_candidate_source_build :: proc(
	descriptors: []editor_session.Entry_Descriptor,
	classified: []editor_session.Project_Buffer_Descriptor,
	kind: Candidate_Source_Kind,
	scope_identity, scope_generation, source_generation: u64,
	synthetic_name: string,
	allocator: runtime.Allocator,
) -> (source: Buffer_Candidate_Source, ok: bool, failure: Candidate_Failure) {
	project_scoped := kind == .Project_Buffers
	if (kind != .Session_Buffers && !project_scoped) || scope_identity == 0 ||
	   scope_generation == 0 || source_generation == 0 ||
	   (project_scoped && len(classified) != len(descriptors)) {
		return {}, false, Candidate_Failure{code = .Invalid_Source}
	}
	count := len(descriptors)
	if project_scoped {
		count = 0
		for descriptor in classified {
			if descriptor.scope == .Project_Owned {count += 1}
		}
	}
	if len(synthetic_name) > 0 {count += 1}
	if count > int(MAX_CANDIDATES) {
		return {}, false, Candidate_Failure {
			code = .Candidate_Limit,
			limit = u64(MAX_CANDIDATES),
			actual = u64(count),
		}
	}
	source.allocator = allocator
	allocation_error: runtime.Allocator_Error
	source.descriptors, allocation_error = make([]Candidate_Descriptor_Definition, count, allocator)
	if allocation_error != nil {
		buffer_candidate_source_close(&source)
		return {}, false, Candidate_Failure{code = .Persistent_Memory_Limit}
	}
	source.fields, allocation_error = make([]string, count, allocator)
	if allocation_error != nil {
		buffer_candidate_source_close(&source)
		return {}, false, Candidate_Failure{code = .Persistent_Memory_Limit}
	}
	source.annotations, allocation_error = make([]Candidate_Annotation_Definition, count * 3, allocator)
	if allocation_error != nil {
		buffer_candidate_source_close(&source)
		return {}, false, Candidate_Failure{code = .Persistent_Memory_Limit}
	}

	output_index := 0
	registry_generation := buffer_candidate_registry_generation(descriptors)
	if registry_generation == 0 {
		buffer_candidate_source_close(&source)
		return {}, false, Candidate_Failure{code = .Invalid_Source}
	}
	for descriptor, index in descriptors {
		if project_scoped && classified[index].scope != .Project_Owned {
			continue
		}
		entry := descriptor.graph.entry
		if u64(entry.registry.generation) != registry_generation {
			buffer_candidate_source_close(&source)
			return {}, false, Candidate_Failure{code = .Stale_Source}
		}
		associated := descriptor.association == .Document
		field_count := 0
		if associated {
			source.fields[output_index] = descriptor.selection_label
			field_count = 1
		}
		annotation_offset := output_index * 3
		source.annotations[annotation_offset + 0] = {
			kind = .Document_Path,
			text = descriptor.selection_label if associated else "non-file-backed",
		}
		source.annotations[annotation_offset + 1] = {
			kind = .Modified_State,
			text = "modified" if descriptor.modified else "unmodified",
		}
		source.annotations[annotation_offset + 2] = {
			kind = .Generic,
			text = "file-backed" if associated else "non-file-backed",
		}
		source.descriptors[output_index] = Candidate_Descriptor_Definition {
			identity = buffer_candidate_identity(entry),
			label = descriptor.selection_label,
			searchable_fields = source.fields[output_index:output_index + field_count],
			annotations = source.annotations[annotation_offset:annotation_offset + 3],
			action = buffer_candidate_action(descriptor.graph),
			availability = .Available,
			durable_category = .Document if associated else .None,
			durable_key = descriptor.selection_label if associated else "",
		}
		output_index += 1
	}
	if len(synthetic_name) > 0 {
		annotation_offset := output_index * 3
		source.annotations[annotation_offset + 0] = {kind = .Document_Path, text = "new buffer"}
		source.annotations[annotation_offset + 1] = {kind = .Modified_State, text = "unmodified"}
		source.annotations[annotation_offset + 2] = {kind = .Generic, text = "create"}
		hash := buffer_candidate_name_hash(synthetic_name)
		source.descriptors[output_index] = Candidate_Descriptor_Definition {
			identity = {kind = 3, primary = hash},
			label = synthetic_name,
			annotations = source.annotations[annotation_offset:annotation_offset + 3],
			action = {kind = .Create_Buffer, owner_generation = registry_generation, primary = hash},
			availability = .Synthetic,
		}
		output_index += 1
	}
	assert(output_index == count)
	source.definition = Candidate_Source_Definition {
		kind = kind,
		scope_identity = scope_identity,
		scope_generation = scope_generation,
		source_generation = source_generation,
		descriptors = source.descriptors,
	}
	return source, true, {}
}

@(private)
buffer_candidate_registry_generation :: proc(descriptors: []editor_session.Entry_Descriptor) -> u64 {
	if len(descriptors) == 0 {return 0}
	return u64(descriptors[0].graph.entry.registry.generation)
}

@(private)
buffer_candidate_name_is_synthetic :: proc(
	descriptors: []editor_session.Entry_Descriptor,
	query: string,
) -> bool {
	if len(query) == 0 || len(query) > int(editor_session.MAX_NAME_BYTES) {return false}
	for byte in transmute([]u8)query {
		if byte == 0 {return false}
	}
	for descriptor in descriptors {
		if descriptor.selection_label == query {return false}
	}
	return true
}

@(private)
buffer_candidate_name_hash :: proc(value: string) -> u64 {
	hash := u64(14_695_981_039_346_656_037)
	for byte in transmute([]u8)value {
		hash = (hash ~ u64(byte)) * 1_099_511_628_211
	}
	return hash if hash != 0 else 1
}

@(private)
buffer_candidate_identity :: proc(entry: editor_session.Entry_Handle) -> Candidate_Identity {
	return Candidate_Identity {
		kind = 2,
		primary = u64(entry.entry_id),
		secondary = u64(entry.slot) << 32 | u64(entry.generation),
	}
}

@(private)
buffer_candidate_action :: proc(graph: editor_session.Object_Graph_Identity) -> Candidate_Action {
	entry := graph.entry
	return Candidate_Action {
		kind = .Activate_Buffer,
		owner_generation = u64(entry.registry.generation),
		primary = u64(entry.entry_id),
		secondary = u64(entry.slot) << 32 | u64(entry.generation),
		graph_identity = {
			u64(graph.buffer_id),
			u64(graph.history_id),
			u64(graph.primary_view.registry_id),
			u64(graph.primary_view.view_id),
			u64(graph.primary_view.slot) << 32 | u64(graph.primary_view.generation),
			u64(graph.document_id),
		},
	}
}
