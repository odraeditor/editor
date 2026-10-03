// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../document"
import "../editor"

/* MAX_SYMBOLS bounds descriptors in one complete symbol generation. */
MAX_SYMBOLS :: u32(65_536)
/* MAX_SYMBOL_NAME_BYTES bounds one copied symbol name. */
MAX_SYMBOL_NAME_BYTES :: 512
/* MAX_SYMBOL_CONTAINER_BYTES bounds one copied containing-scope label. */
MAX_SYMBOL_CONTAINER_BYTES :: 1_024
/* MAX_SYMBOL_ANNOTATION_BYTES bounds one copied signature or annotation. */
MAX_SYMBOL_ANNOTATION_BYTES :: 4_096
/* MAX_SYMBOL_HIERARCHY_DEPTH bounds parent relationships in one generation. */
MAX_SYMBOL_HIERARCHY_DEPTH :: u16(128)
/* MAX_RETAINED_SYMBOL_BYTES bounds one retained symbol generation. */
MAX_RETAINED_SYMBOL_BYTES :: 32 * MEBIBYTE
/* MAX_SYMBOL_TEMPORARY_BYTES bounds one symbol query's temporary storage. */
MAX_SYMBOL_TEMPORARY_BYTES :: 64 * MEBIBYTE
/* MAX_SYMBOL_WORK_ITEMS bounds nodes or textual units visited by one query. */
MAX_SYMBOL_WORK_ITEMS :: u64(1_048_576)

/* GENERIC_SYMBOL_LANGUAGE_ID identifies the language-independent text fallback. */
GENERIC_SYMBOL_LANGUAGE_ID :: Language_ID(max(u32))
/* GENERIC_SYMBOL_PROVIDER_ID identifies the built-in language-independent symbol scanner. */
GENERIC_SYMBOL_PROVIDER_ID :: Provider_ID(max(u64))

/* Symbol_ID identifies one symbol within its source generation; zero is invalid. */
Symbol_ID :: distinct u64
/* Symbol_Request_Generation identifies one exact query request. */
Symbol_Request_Generation :: distinct u64
/* Symbol_Result_Generation identifies one complete immutable result generation. */
Symbol_Result_Generation :: distinct u64

/* Symbol_Name is one bounded copied canonical symbol name. */
Symbol_Name :: struct {
	bytes:  [MAX_SYMBOL_NAME_BYTES]u8,
	length: u16,
}

/* Symbol_Container is one bounded copied containing-scope label. */
Symbol_Container :: struct {
	bytes:  [MAX_SYMBOL_CONTAINER_BYTES]u8,
	length: u16,
}

/* Symbol_Annotation is one bounded copied provider-neutral annotation. */
Symbol_Annotation :: struct {
	bytes:  [MAX_SYMBOL_ANNOTATION_BYTES]u8,
	length: u16,
}

/* Symbol_Kind is the stable provider-neutral semantic symbol vocabulary. */
Symbol_Kind :: enum u8 {
	Invalid,
	File,
	Module,
	Namespace,
	Package,
	Type,
	Struct,
	Union,
	Enum,
	Interface,
	Trait,
	Function,
	Method,
	Constructor,
	Variable,
	Constant,
	Field,
	Property,
	Parameter,
	Label,
}

/* Symbol_Query_Scope_Kind identifies the bounded source requested by a query. */
Symbol_Query_Scope_Kind :: enum u8 {
	Invalid,
	Active_Buffer,
}

/* Symbol_Query_Scope binds a symbol request to one exact active buffer state. */
Symbol_Query_Scope :: struct {
	kind:                 Symbol_Query_Scope_Kind,
	buffer_id:            editor.Buffer_ID,
	document_id:          document.Document_ID,
	has_document:         bool,
	source_revision:      editor.Revision,
	language:             Language_Identity,
	provider:             Provider_Handle,
	selection_generation: Selection_Generation,
	request_generation:   Symbol_Request_Generation,
}

/* Symbol_Range is one exact revision-current navigable byte range. */
Symbol_Range :: struct {
	buffer_id:       editor.Buffer_ID,
	document_id:     document.Document_ID,
	has_document:    bool,
	source_revision: editor.Revision,
	start:           editor.Byte_Offset,
	end:             editor.Byte_Offset,
}

/* Symbol_Descriptor is one copied provider-neutral symbol observation. */
Symbol_Descriptor :: struct {
	id:                Symbol_ID,
	parent_id:         Symbol_ID,
	hierarchy_depth:   u16,
	provider:          Provider_Handle,
	result_generation: Symbol_Result_Generation,
	location:          Symbol_Range,
	name:              Symbol_Name,
	kind:              Symbol_Kind,
	container:         Symbol_Container,
	annotation:        Symbol_Annotation,
}

/* Symbol_Completeness reports whether a generation exhausted its exact scope. */
Symbol_Completeness :: enum u8 {
	Invalid,
	Complete,
	Incomplete,
}

/* Symbol_Usage reports retained, temporary, and logical query work. */
Symbol_Usage :: struct {
	symbols:         u32,
	retained_bytes:  u64,
	temporary_bytes: u64,
	work_items:      u64,
}

/* Symbol_Limits is the complete selected symbol-query resource policy. */
Symbol_Limits :: struct {
	symbols:          u32,
	name_bytes:       u16,
	container_bytes:  u16,
	annotation_bytes: u16,
	hierarchy_depth:  u16,
	retained_bytes:   u64,
	temporary_bytes:  u64,
	work_items:       u64,
}

/* DEFAULT_SYMBOL_LIMITS is the bounded maintained symbol-query policy. */
DEFAULT_SYMBOL_LIMITS :: Symbol_Limits {
	symbols = MAX_SYMBOLS,
	name_bytes = MAX_SYMBOL_NAME_BYTES,
	container_bytes = MAX_SYMBOL_CONTAINER_BYTES,
	annotation_bytes = MAX_SYMBOL_ANNOTATION_BYTES,
	hierarchy_depth = MAX_SYMBOL_HIERARCHY_DEPTH,
	retained_bytes = MAX_RETAINED_SYMBOL_BYTES,
	temporary_bytes = MAX_SYMBOL_TEMPORARY_BYTES,
	work_items = MAX_SYMBOL_WORK_ITEMS,
}

/* Symbol_Result_Descriptor identifies one immutable bounded publication. */
Symbol_Result_Descriptor :: struct {
	scope:        Symbol_Query_Scope,
	generation:   Symbol_Result_Generation,
	completeness: Symbol_Completeness,
	usage:        Symbol_Usage,
}

/* Symbol_Index is an opaque owner of one immutable symbol generation. */
Symbol_Index :: struct {
	state: rawptr,
}

/* Symbol_Index_View copies generation metadata without exposing retained storage. */
Symbol_Index_View :: struct {
	descriptor: Symbol_Result_Descriptor,
	symbols:    u32,
}

/* Generic_Symbol is one copied buffer-local symbol resolved without analysis. */
Generic_Symbol :: struct {
	location: Symbol_Range,
	name:     Symbol_Name,
}

/* Symbol_Provider_Inspection is copied registry state and performs no query. */
Symbol_Provider_Inspection :: struct {
	selection: Provider_Selection,
	provider:  Provider_Descriptor,
	available: bool,
}

/* symbol_kind_is_valid checks the stable provider-neutral kind vocabulary. */
symbol_kind_is_valid :: proc(kind: Symbol_Kind) -> bool {
	return kind >= .File && kind <= .Label
}

/* symbol_kind_label returns the stable user-facing label for one symbol kind. */
symbol_kind_label :: proc(kind: Symbol_Kind) -> string {
	switch kind {
	case .File:        return "file"
	case .Module:      return "module"
	case .Namespace:   return "namespace"
	case .Package:     return "package"
	case .Type:        return "type"
	case .Struct:      return "struct"
	case .Union:       return "union"
	case .Enum:        return "enum"
	case .Interface:   return "interface"
	case .Trait:       return "trait"
	case .Function:    return "function"
	case .Method:      return "method"
	case .Constructor: return "constructor"
	case .Variable:    return "variable"
	case .Constant:    return "constant"
	case .Field:       return "field"
	case .Property:    return "property"
	case .Parameter:   return "parameter"
	case .Label:       return "label"
	case .Invalid:     return ""
	}
	unreachable()
}

/* generic_symbol_scope creates the stable built-in text-fallback query identity. */
generic_symbol_scope :: proc(
	buffer_id: editor.Buffer_ID,
	document_id: document.Document_ID,
	has_document: bool,
	source_revision: editor.Revision,
	request_generation: Symbol_Request_Generation,
) -> Symbol_Query_Scope {
	name: Language_Name
	name.length = u16(copy(name.bytes[:], "plain-text"))
	language := Language_Identity {
		id = GENERIC_SYMBOL_LANGUAGE_ID,
		generation = 1,
		name = name,
	}
	return {
		kind = .Active_Buffer,
		buffer_id = buffer_id,
		document_id = document_id,
		has_document = has_document,
		source_revision = source_revision,
		language = language,
		provider = {
			registry_id = Registry_ID(max(u32)),
			language_id = language.id,
			provider_id = GENERIC_SYMBOL_PROVIDER_ID,
			provider_generation = 1,
		},
		selection_generation = 1,
		request_generation = request_generation,
	}
}

/* symbol_query_scope_is_valid checks one exact active-buffer query identity. */
symbol_query_scope_is_valid :: proc(scope: Symbol_Query_Scope) -> bool {
	if scope.kind != .Active_Buffer || scope.buffer_id == editor.Buffer_ID(0) ||
	   !language_identity_is_valid(scope.language) ||
	   scope.provider.provider_id == Provider_ID(0) ||
	   scope.provider.provider_generation == Provider_Generation(0) ||
	   scope.provider.language_id != scope.language.id ||
	   scope.selection_generation == Selection_Generation(0) ||
	   scope.request_generation == Symbol_Request_Generation(0) {
		return false
	}
	return scope.has_document == (scope.document_id != document.Document_ID(0))
}

/* symbol_range_is_valid checks one non-empty exact-revision byte range. */
symbol_range_is_valid :: proc(symbol_range: Symbol_Range, source_bytes: u64) -> bool {
	return symbol_range.buffer_id != editor.Buffer_ID(0) &&
		symbol_range.has_document == (symbol_range.document_id != document.Document_ID(0)) &&
		symbol_range.start < symbol_range.end && u64(symbol_range.end) <= source_bytes
}

/* symbol_descriptor_is_valid checks identity, hierarchy, text, and location bounds. */
symbol_descriptor_is_valid :: proc(
	descriptor: Symbol_Descriptor,
	scope: Symbol_Query_Scope,
	source_bytes: u64,
	limits := DEFAULT_SYMBOL_LIMITS,
) -> bool {
	if !symbol_query_scope_is_valid(scope) || !symbol_limits_are_valid(limits) ||
	   descriptor.id == Symbol_ID(0) || descriptor.provider != scope.provider ||
	   descriptor.result_generation == Symbol_Result_Generation(0) ||
	   !symbol_kind_is_valid(descriptor.kind) ||
	   descriptor.name.length == 0 || descriptor.name.length > limits.name_bytes ||
	   descriptor.container.length > limits.container_bytes ||
	   descriptor.annotation.length > limits.annotation_bytes ||
	   descriptor.hierarchy_depth > limits.hierarchy_depth ||
	   !symbol_range_is_valid(descriptor.location, source_bytes) {
		return false
	}
	if descriptor.location.buffer_id != scope.buffer_id ||
	   descriptor.location.document_id != scope.document_id ||
	   descriptor.location.has_document != scope.has_document ||
	   descriptor.location.source_revision != scope.source_revision {
		return false
	}
	return descriptor.parent_id == Symbol_ID(0) || descriptor.parent_id != descriptor.id
}

/* symbol_limits_are_valid checks nonzero selected bounds against hard ceilings. */
symbol_limits_are_valid :: proc(limits: Symbol_Limits) -> bool {
	return limits.symbols > 0 && limits.symbols <= MAX_SYMBOLS &&
		limits.name_bytes > 0 && limits.name_bytes <= MAX_SYMBOL_NAME_BYTES &&
		limits.container_bytes > 0 && limits.container_bytes <= MAX_SYMBOL_CONTAINER_BYTES &&
		limits.annotation_bytes > 0 && limits.annotation_bytes <= MAX_SYMBOL_ANNOTATION_BYTES &&
		limits.hierarchy_depth > 0 && limits.hierarchy_depth <= MAX_SYMBOL_HIERARCHY_DEPTH &&
		limits.retained_bytes > 0 && limits.retained_bytes <= MAX_RETAINED_SYMBOL_BYTES &&
		limits.temporary_bytes > 0 && limits.temporary_bytes <= MAX_SYMBOL_TEMPORARY_BYTES &&
		limits.work_items > 0 && limits.work_items <= MAX_SYMBOL_WORK_ITEMS
}

/* provider_registry_symbol_inspection copies active symbol capability state. */
provider_registry_symbol_inspection :: proc(
	registry: ^Provider_Registry,
) -> (inspection: Symbol_Provider_Inspection, ok: bool, failure: Failure) {
	selection, selected, selection_failure := provider_registry_selection(registry)
	if !selected {
		selection_failure.operation = .Inspect_Symbols
		return {}, false, selection_failure
	}
	if selection.active.provider_id == Provider_ID(0) {
		return Symbol_Provider_Inspection{selection = selection}, true, {}
	}
	provider, inspected, provider_failure := provider_registry_provider(registry, selection.active)
	if !inspected {
		provider_failure.operation = .Inspect_Symbols
		return {}, false, provider_failure
	}
	return Symbol_Provider_Inspection {
		selection = selection,
		provider = provider,
		available = provider.state == .Confirmed && .Symbols in provider.capabilities,
	}, true, {}
}
