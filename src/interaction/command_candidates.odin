// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "base:runtime"

/* Command_Candidate_Source owns borrowed-definition storage until candidate-session admission. */
Command_Candidate_Source :: struct {
	definition:  Candidate_Source_Definition,
	descriptors: []Candidate_Descriptor_Definition,
	fields:      []string,
	annotations: []Candidate_Annotation_Definition,
	text:        []u8,
	allocator:   runtime.Allocator,
}

/* command_candidate_source_build adapts one copied command catalog into canonical candidates. */
command_candidate_source_build :: proc(
	catalog: ^Command_Catalog,
	allocator := context.temp_allocator,
) -> (source: Command_Candidate_Source, ok: bool, failure: Candidate_Failure) {
	if catalog == nil || catalog.state == nil ||
	   catalog.registry_generation == Registry_Generation(0) ||
	   catalog.snapshot_generation == Snapshot_Generation(0) ||
	   allocator.procedure == nil {
		return {}, false, Candidate_Failure{code = .Invalid_Source}
	}
	if len(catalog.entries) > int(MAX_CANDIDATES) {
		return {}, false, Candidate_Failure {
			code = .Candidate_Limit,
			limit = u64(MAX_CANDIDATES),
			actual = u64(len(catalog.entries)),
		}
	}

	text_bytes := 0
	for entry in catalog.entries {
		binding_bytes, bindings_ok := command_candidate_binding_text_length(entry.bindings)
		if !bindings_ok {
			return {}, false, Candidate_Failure {
				code = .Invalid_Source,
				identity = command_candidate_identity(entry.metadata.handle),
			}
		}
		text_bytes += binding_bytes
		switch entry.availability {
		case .Available:
			text_bytes += len("available")
		case .Unavailable:
			text_bytes += len("unavailable: ") + len(entry.unavailable_reason)
		case .Invalid:
			return {}, false, Candidate_Failure {
				code = .Invalid_Source,
				identity = command_candidate_identity(entry.metadata.handle),
			}
		}
	}
	if u64(text_bytes) > MAX_CANDIDATE_TEXT_BYTES {
		return {}, false, Candidate_Failure {
			code = .Text_Limit,
			limit = MAX_CANDIDATE_TEXT_BYTES,
			actual = u64(text_bytes),
		}
	}

	source.allocator = allocator
	allocation_error: runtime.Allocator_Error
	source.descriptors, allocation_error = make(
		[]Candidate_Descriptor_Definition,
		len(catalog.entries),
		allocator,
	)
	if allocation_error != nil {
		command_candidate_source_close(&source)
		return {}, false, Candidate_Failure{code = .Persistent_Memory_Limit}
	}
	source.fields, allocation_error = make([]string, len(catalog.entries), allocator)
	if allocation_error != nil {
		command_candidate_source_close(&source)
		return {}, false, Candidate_Failure{code = .Persistent_Memory_Limit}
	}
	source.annotations, allocation_error = make(
		[]Candidate_Annotation_Definition,
		len(catalog.entries) * 4,
		allocator,
	)
	if allocation_error != nil {
		command_candidate_source_close(&source)
		return {}, false, Candidate_Failure{code = .Persistent_Memory_Limit}
	}
	source.text, allocation_error = make([]u8, text_bytes, allocator)
	if allocation_error != nil {
		command_candidate_source_close(&source)
		return {}, false, Candidate_Failure{code = .Persistent_Memory_Limit}
	}

	text_offset := 0
	for entry, index in catalog.entries {
		binding_start := text_offset
		text_offset = command_candidate_binding_text_write(entry.bindings, source.text, text_offset)
		availability_start := text_offset
		if entry.availability == .Available {
			text_offset = command_candidate_text_append(source.text, text_offset, "available")
		} else {
			text_offset = command_candidate_text_append(source.text, text_offset, "unavailable: ")
			text_offset = command_candidate_text_append(source.text, text_offset, entry.unavailable_reason)
		}
		source.fields[index] = entry.metadata.description
		annotation_offset := index * 4
		source.annotations[annotation_offset + 0] = {
			kind = .Binding,
			text = string(source.text[binding_start:availability_start]),
		}
		source.annotations[annotation_offset + 1] = {
			kind = .Provider,
			text = entry.metadata.provenance.provider,
		}
		source.annotations[annotation_offset + 2] = {
			kind = .Availability,
			text = string(source.text[availability_start:text_offset]),
		}
		source.annotations[annotation_offset + 3] = {
			kind = .Description,
			text = entry.metadata.description,
		}
		source.descriptors[index] = Candidate_Descriptor_Definition {
			identity = command_candidate_identity(entry.metadata.handle),
			label = entry.metadata.name,
			searchable_fields = source.fields[index:index + 1],
			annotations = source.annotations[annotation_offset:annotation_offset + 4],
			action = command_candidate_action(entry.metadata.handle),
			availability = entry.availability == .Available ? .Available : .Unavailable,
			durable_category = .Command,
			durable_key = entry.metadata.name,
		}
	}
	assert(text_offset == text_bytes)
	source.definition = Candidate_Source_Definition {
		kind = .Commands,
		scope_identity = u64(catalog.registry_generation),
		scope_generation = u64(catalog.snapshot_generation),
		source_generation = u64(catalog.snapshot_generation),
		descriptors = source.descriptors,
	}
	return source, true, {}
}

/* command_candidate_source_close releases temporary adapter storage. */
command_candidate_source_close :: proc(source: ^Command_Candidate_Source) -> bool {
	if source == nil || source.allocator.procedure == nil {
		return false
	}
	delete(source.text, source.allocator)
	delete(source.annotations, source.allocator)
	delete(source.fields, source.allocator)
	delete(source.descriptors, source.allocator)
	source^ = {}
	return true
}

/* command_candidate_action_handle reconstructs one checked command identity. */
command_candidate_action_handle :: proc(
	action: Candidate_Action,
) -> (command: Command_Handle, ok: bool) {
	if action.kind != .Invoke_Command || action.owner_generation == 0 ||
	   action.primary > u64(max(u16)) || action.secondary == 0 ||
	   action.secondary > u64(max(u32)) {
		return {}, false
	}
	return Command_Handle {
		registry_generation = Registry_Generation(action.owner_generation),
		slot = u16(action.primary),
		entry_generation = u32(action.secondary),
	}, true
}

@(private)
command_candidate_identity :: proc(command: Command_Handle) -> Candidate_Identity {
	return Candidate_Identity {
		kind = 1,
		primary = u64(command.slot) + 1,
		secondary = u64(command.entry_generation),
	}
}

@(private)
command_candidate_action :: proc(command: Command_Handle) -> Candidate_Action {
	return Candidate_Action {
		kind = .Invoke_Command,
		owner_generation = u64(command.registry_generation),
		primary = u64(command.slot),
		secondary = u64(command.entry_generation),
	}
}

@(private)
command_candidate_binding_text_length :: proc(bindings: []Key_Sequence) -> (int, bool) {
	if len(bindings) == 0 {
		return 0, true
	}
	length := 0
	for binding, index in bindings {
		binding_length := key_sequence_notation_length(binding)
		if binding_length < 0 {
			return 0, false
		}
		if index > 0 {
			length += len(", ")
		}
		length += binding_length
	}
	return length, true
}

@(private)
command_candidate_binding_text_write :: proc(
	bindings: []Key_Sequence,
	output: []u8,
	offset: int,
) -> int {
	if len(bindings) == 0 {
		return offset
	}
	cursor := offset
	for binding, index in bindings {
		if index > 0 {
			cursor = command_candidate_text_append(output, cursor, ", ")
		}
		text, written := key_sequence_notation(binding, output[cursor:])
		assert(written)
		cursor += len(text)
	}
	return cursor
}

@(private)
command_candidate_text_append :: proc(output: []u8, offset: int, value: string) -> int {
	copy(output[offset:], transmute([]u8)value)
	return offset + len(value)
}
