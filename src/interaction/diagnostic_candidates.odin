// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "../language_service"
import "base:runtime"
import "core:slice"

/* Diagnostic_Candidate_Document binds one copied generation to its checked editor location. */
Diagnostic_Candidate_Document :: struct {
	batch:     ^language_service.Diagnostic_Batch_Copy,
	path:      string,
	buffer_id: u64,
}

/* Diagnostic_Candidate_Request selects one active-buffer or active-Project scope generation. */
Diagnostic_Candidate_Request :: struct {
	scope_identity:    u64,
	scope_generation:  u64,
	source_generation: u64,
	documents:         []Diagnostic_Candidate_Document,
}

/* Diagnostic_Candidate_Location is one copied checked navigation target. */
Diagnostic_Candidate_Location :: struct {
	binding:            language_service.Document_Binding_Handle,
	diagnostic_generation: language_service.Diagnostic_Generation,
	diagnostic_id:      language_service.Diagnostic_ID,
	canonical_revision: u64,
	buffer_id:          u64,
	start:              u64,
	end:                u64,
	path:               string,
}

/* Diagnostic_Candidate_Source owns borrowed-definition adapters until candidate admission. */
Diagnostic_Candidate_Source :: struct {
	definition:  Candidate_Source_Definition,
	descriptors: []Candidate_Descriptor_Definition,
	fields:      []string,
	annotations: []Candidate_Annotation_Definition,
	locations:   []Diagnostic_Candidate_Location,
	allocator:   runtime.Allocator,
}

@(private)
Diagnostic_Candidate_Seed :: struct {
	document: int,
	record:   int,
	severity: language_service.Diagnostic_Severity,
	path:     string,
	start:    u64,
	id:       language_service.Diagnostic_ID,
}

/* diagnostic_candidate_source_build copies one ordered complete diagnostic source generation. */
diagnostic_candidate_source_build :: proc(
	request: Diagnostic_Candidate_Request,
	allocator := context.temp_allocator,
) -> (source: Diagnostic_Candidate_Source, ok: bool, failure: Candidate_Failure) {
	if request.scope_identity == 0 || request.scope_generation == 0 ||
	   request.source_generation == 0 || len(request.documents) == 0 ||
	   allocator.procedure == nil {
		return {}, false, Candidate_Failure{code = .Invalid_Source}
	}
	total := 0
	for document in request.documents {
		if !diagnostic_candidate_document_is_valid(document) {
			return {}, false, Candidate_Failure{code = .Invalid_Source}
		}
		total += len(document.batch.records)
		if total > int(MAX_CANDIDATES) {
			return {}, false, Candidate_Failure{code = .Candidate_Limit,
				limit = u64(MAX_CANDIDATES), actual = u64(total)}
		}
	}
	source.allocator = allocator
	allocation_error: runtime.Allocator_Error
	source.descriptors, allocation_error = make([]Candidate_Descriptor_Definition, total, allocator)
	if allocation_error != nil do return diagnostic_candidate_source_allocation_failure(&source)
	source.fields, allocation_error = make([]string, total * 4, allocator)
	if allocation_error != nil do return diagnostic_candidate_source_allocation_failure(&source)
	source.annotations, allocation_error = make([]Candidate_Annotation_Definition, total * 2, allocator)
	if allocation_error != nil do return diagnostic_candidate_source_allocation_failure(&source)
	source.locations, allocation_error = make([]Diagnostic_Candidate_Location, total, allocator)
	if allocation_error != nil do return diagnostic_candidate_source_allocation_failure(&source)
	seeds, seed_error := make([]Diagnostic_Candidate_Seed, total, allocator)
	if seed_error != nil do return diagnostic_candidate_source_allocation_failure(&source)
	defer delete(seeds, allocator)
	seed_index := 0
	for document, document_index in request.documents {
		for record, record_index in document.batch.records {
			seeds[seed_index] = {document = document_index, record = record_index,
				severity = record.severity, path = document.path, start = record.range.start,
				id = record.id}
			seed_index += 1
		}
	}
	slice.sort_by(seeds, diagnostic_candidate_seed_less)
	text_bytes := u64(0)
	for seed, index in seeds {
		document := request.documents[seed.document]
		record := document.batch.records[seed.record]
		message := language_service.diagnostic_record_text(document.batch, record.message)
		source_text := language_service.diagnostic_record_text(document.batch, record.source)
		code := language_service.diagnostic_record_text(document.batch, record.code)
		severity := diagnostic_candidate_severity_text(record.severity)
		if len(message) == 0 || len(severity) == 0 {
			diagnostic_candidate_source_close(&source)
			return {}, false, Candidate_Failure{code = .Invalid_Source}
		}
		field_base := index * 4
		source.fields[field_base] = document.path
		source.fields[field_base + 1] = source_text
		source.fields[field_base + 2] = code
		source.fields[field_base + 3] = severity
		annotation_base := index * 2
		source.annotations[annotation_base] = {kind = .Severity, text = severity}
		source.annotations[annotation_base + 1] = {kind = .Location, text = document.path}
		location := Diagnostic_Candidate_Location {
			binding = record.binding, diagnostic_generation = record.generation,
			diagnostic_id = record.id, canonical_revision = record.canonical_revision,
			buffer_id = document.buffer_id, start = record.range.start, end = record.range.end,
			path = document.path,
		}
		source.locations[index] = location
		source.descriptors[index] = {
			identity = diagnostic_candidate_identity(location), label = message,
			searchable_fields = source.fields[field_base:field_base + 4],
			annotations = source.annotations[annotation_base:annotation_base + 2],
			action = diagnostic_candidate_action(location, request.source_generation),
			availability = .Available,
		}
		text_bytes += u64(len(message) + len(document.path) + len(source_text) + len(code) + len(severity) * 2)
		if text_bytes > MAX_CANDIDATE_TEXT_BYTES {
			diagnostic_candidate_source_close(&source)
			return {}, false, Candidate_Failure{code = .Text_Limit,
				limit = MAX_CANDIDATE_TEXT_BYTES, actual = text_bytes}
		}
	}
	source.definition = {kind = .Language_Diagnostics,
		scope_identity = request.scope_identity, scope_generation = request.scope_generation,
		source_generation = request.source_generation, descriptors = source.descriptors}
	return source, true, {}
}

/* diagnostic_candidate_source_close releases temporary adapter storage. */
diagnostic_candidate_source_close :: proc(source: ^Diagnostic_Candidate_Source) -> bool {
	if source == nil || source.allocator.procedure == nil do return false
	delete(source.locations, source.allocator)
	delete(source.annotations, source.allocator)
	delete(source.fields, source.allocator)
	delete(source.descriptors, source.allocator)
	source^ = {}
	return true
}

/* diagnostic_candidate_action_matches revalidates one exact current navigation target. */
diagnostic_candidate_action_matches :: proc(
	action: Candidate_Action,
	location: Diagnostic_Candidate_Location,
	source_generation: u64,
) -> bool {
	return action.kind == .Navigate_Diagnostic && action.owner_generation == source_generation &&
		action.primary == location.buffer_id && action.secondary == location.canonical_revision &&
		action.graph_identity[0] == u64(location.binding.id) &&
		action.graph_identity[1] == u64(location.binding.generation) &&
		action.graph_identity[2] == u64(location.diagnostic_generation) &&
		action.graph_identity[3] == u64(location.diagnostic_id) &&
		action.graph_identity[4] == location.start && action.graph_identity[5] == location.end
}

@(private)
diagnostic_candidate_document_is_valid :: proc(document: Diagnostic_Candidate_Document) -> bool {
	if document.batch == nil || document.buffer_id == 0 || len(document.path) == 0 ||
	   document.batch.descriptor.generation == language_service.Diagnostic_Generation(0) ||
	   int(document.batch.descriptor.diagnostics) != len(document.batch.records) {
		return false
	}
	for record in document.batch.records {
		if record.binding != document.batch.descriptor.binding ||
		   record.generation != document.batch.descriptor.generation ||
		   record.canonical_revision != document.batch.descriptor.canonical_revision {
			return false
		}
	}
	return true
}

@(private)
diagnostic_candidate_seed_less :: proc(left, right: Diagnostic_Candidate_Seed) -> bool {
	if left.severity != right.severity do return left.severity < right.severity
	if left.path != right.path do return left.path < right.path
	if left.start != right.start do return left.start < right.start
	return left.id < right.id
}

@(private)
diagnostic_candidate_severity_text :: proc(severity: language_service.Diagnostic_Severity) -> string {
	switch severity {
	case .Error: return "error"
	case .Warning: return "warning"
	case .Information: return "information"
	case .Hint: return "hint"
	case .Invalid:
	}
	return ""
}

@(private)
diagnostic_candidate_identity :: proc(location: Diagnostic_Candidate_Location) -> Candidate_Identity {
	return {kind = 6,
		primary = u64(location.diagnostic_generation),
		secondary = (u64(location.binding.id) << 32) ~ u64(location.diagnostic_id)}
}

@(private)
diagnostic_candidate_action :: proc(
	location: Diagnostic_Candidate_Location,
	source_generation: u64,
) -> Candidate_Action {
	return {kind = .Navigate_Diagnostic, owner_generation = source_generation,
		primary = location.buffer_id, secondary = location.canonical_revision,
		graph_identity = {u64(location.binding.id), u64(location.binding.generation),
			u64(location.diagnostic_generation), u64(location.diagnostic_id),
			location.start, location.end}}
}

@(private)
diagnostic_candidate_source_allocation_failure :: proc(
	source: ^Diagnostic_Candidate_Source,
) -> (Diagnostic_Candidate_Source, bool, Candidate_Failure) {
	diagnostic_candidate_source_close(source)
	return {}, false, Candidate_Failure{code = .Persistent_Memory_Limit}
}
