// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package result_set

import "../language"
import "base:runtime"

/* Symbol_Materialization_Config identifies one replaceable symbol result set. */
Symbol_Materialization_Config :: struct {
	set_id:              Result_Set_ID,
	expected_generation: Result_Set_Generation,
	source_id:           Source_ID,
	allocator:           runtime.Allocator,
}

/* symbol_materialize copies one provider-neutral symbol index into the common result model. */
symbol_materialize :: proc(
	registry: ^Registry,
	index: ^language.Symbol_Index,
	config: Symbol_Materialization_Config,
) -> (Result, bool, Failure) {
	view, viewed, _ := language.symbol_index_view(index)
	if !viewed || config.set_id == Result_Set_ID(0) || config.source_id == Source_ID(0) ||
	   config.allocator.procedure == nil {
		return {}, false, Failure{code = .Invalid_Publication, set_id = config.set_id}
	}
	definitions, definitions_error := make(
		[]Location_Definition,
		int(view.symbols),
		config.allocator,
	)
	if definitions_error != nil {
		return {}, false, Failure{code = .Persistent_Memory_Limit, set_id = config.set_id}
	}
	defer delete(definitions, config.allocator)

	text_bytes := 0
	for ordinal in 0 ..< view.symbols {
		descriptor, described, _ := language.symbol_index_descriptor(index, ordinal)
		if !described {
			return {}, false, Failure{code = .Invalid_Publication, set_id = config.set_id}
		}
		annotation_bytes := symbol_result_annotation_bytes(&descriptor)
		if annotation_bytes > int(MAX_RESULT_ANNOTATION_BYTES) {
			annotation_bytes = int(MAX_RESULT_ANNOTATION_BYTES)
		}
		text_bytes += int(descriptor.name.length) + annotation_bytes
	}
	if u64(text_bytes) > MAX_RESULT_TEMPORARY_BYTES {
		return {}, false, Failure{code = .Text_Limit, set_id = config.set_id,
			limit = MAX_RESULT_TEMPORARY_BYTES, actual = u64(text_bytes)}
	}
	storage, storage_error := make([]u8, text_bytes, config.allocator)
	if storage_error != nil {
		return {}, false, Failure{code = .Persistent_Memory_Limit, set_id = config.set_id}
	}
	defer delete(storage, config.allocator)

	cursor := 0
	for ordinal in 0 ..< view.symbols {
		descriptor, described, _ := language.symbol_index_descriptor(index, ordinal)
		if !described {
			return {}, false, Failure{code = .Invalid_Publication, set_id = config.set_id}
		}
		name_bytes := int(descriptor.name.length)
		copy(storage[cursor:cursor + name_bytes], descriptor.name.bytes[:name_bytes])
		preview := string(storage[cursor:cursor + name_bytes])
		cursor += name_bytes
		annotation_start := cursor
		cursor = symbol_result_annotation_write(storage, cursor, &descriptor)
		annotation_end := min(cursor, annotation_start + int(MAX_RESULT_ANNOTATION_BYTES))
		cursor = annotation_end
		definitions[ordinal] = {
			id = Location_ID(descriptor.id),
			buffer_id = descriptor.location.buffer_id,
			revision = descriptor.location.source_revision,
			start = descriptor.location.start,
			end = descriptor.location.end,
			source_identity = u64(descriptor.id),
			preview = preview,
			annotation = string(storage[annotation_start:annotation_end]),
		}
	}

	selected: Location_ID
	has_selection := false
	if current, present, _ := registry_view(registry, config.set_id); present && current.has_selection {
		selected = current.locations[current.selected_index].id
		for definition in definitions {
			if definition.id == selected {
				has_selection = true
				break
			}
		}
	}
	completeness := Completeness.Complete
	continuation: Continuation
	if view.descriptor.completeness == .Incomplete {
		completeness = .Incomplete
		continuation = {
			present = true,
			provider = u64(view.descriptor.scope.provider.provider_id),
			cursor = u64(view.symbols),
			limit = u64(language.DEFAULT_SYMBOL_LIMITS.symbols),
		}
	}
	return registry_publish(registry, Publication {
		set_id = config.set_id,
		expected_generation = config.expected_generation,
		source = {
			id = config.source_id,
			generation = Source_Generation(view.descriptor.generation),
			kind = .Language_Symbols,
		},
		metadata = {descriptor = "Buffer symbols"},
		completeness = completeness,
		continuation = continuation,
		refresh = {
			provider = u64(view.descriptor.scope.provider.provider_id),
			query_identity = u64(view.descriptor.scope.buffer_id),
			policy_generation = u64(view.descriptor.scope.selection_generation),
			scope_generation = u64(view.descriptor.scope.source_revision),
		},
		edit_capability = .Read_Only,
		locations = definitions,
		selected = selected,
		has_selection = has_selection,
	})
}

@(private)
symbol_result_annotation_bytes :: proc(descriptor: ^language.Symbol_Descriptor) -> int {
	result := len(language.symbol_kind_label(descriptor.kind))
	if descriptor.container.length > 0 do result += 2 + int(descriptor.container.length)
	if descriptor.annotation.length > 0 do result += 2 + int(descriptor.annotation.length)
	return result
}

@(private)
symbol_result_annotation_write :: proc(
	storage: []u8,
	cursor: int,
	descriptor: ^language.Symbol_Descriptor,
) -> int {
	result := cursor
	limit := min(len(storage), result + int(MAX_RESULT_ANNOTATION_BYTES))
	result += copy(storage[result:limit], language.symbol_kind_label(descriptor.kind))
	if descriptor.container.length > 0 {
		result += copy(storage[result:limit], "  ")
		result += copy(storage[result:limit], descriptor.container.bytes[:int(descriptor.container.length)])
	}
	if descriptor.annotation.length > 0 {
		result += copy(storage[result:limit], "  ")
		result += copy(storage[result:limit], descriptor.annotation.bytes[:int(descriptor.annotation.length)])
	}
	return result
}
