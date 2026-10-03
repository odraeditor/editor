// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import "base:runtime"
import "core:unicode/utf8"

/* MAX_INTELLIGENCE_TEXT_BYTES bounds one copied display or query field. */
MAX_INTELLIGENCE_TEXT_BYTES :: 4 * 1_024
/* MAX_INTELLIGENCE_URI_BYTES bounds one copied result URI. */
MAX_INTELLIGENCE_URI_BYTES :: 8 * 1_024
/* MAX_INTELLIGENCE_RESULT_ID_BYTES bounds one copied semantic-token result identifier. */
MAX_INTELLIGENCE_RESULT_ID_BYTES :: 256
/* MAX_SIGNATURE_PARAMETERS bounds one copied signature parameter set. */
MAX_SIGNATURE_PARAMETERS :: 256

/* Intelligence_Request_ID identifies one provider-neutral read-only request. */
Intelligence_Request_ID :: distinct u64
/* Intelligence_Request_Generation identifies one exact request incarnation. */
Intelligence_Request_Generation :: distinct u64
/* Intelligence_Result_Generation identifies one complete copied result. */
Intelligence_Result_Generation :: distinct u64

/* Intelligence_Query_Kind names one generic read-only language query. */
Intelligence_Query_Kind :: enum u8 {
	Invalid,
	Hover,
	Definition,
	References,
	Document_Symbols,
	Workspace_Symbols,
	Signature_Help,
	Semantic_Tokens_Full,
	Semantic_Tokens_Delta,
}

/* Intelligence_Text stores one bounded copied UTF-8 field. */
Intelligence_Text :: struct {
	bytes:  [MAX_INTELLIGENCE_TEXT_BYTES]u8,
	length: u16,
}

/* Intelligence_URI stores one bounded copied URI. */
Intelligence_URI :: struct {
	bytes:  [MAX_INTELLIGENCE_URI_BYTES]u8,
	length: u16,
}

/* Semantic_Result_ID stores one bounded copied semantic-token result identifier. */
Semantic_Result_ID :: struct {
	bytes:  [MAX_INTELLIGENCE_RESULT_ID_BYTES]u8,
	length: u16,
}

/* Intelligence_Source_Scope binds a query to exact document and service generations. */
Intelligence_Source_Scope :: struct {
	session:               Session_Handle,
	binding:               Document_Binding_Handle,
	document_identity:     u64,
	buffer_identity:       u64,
	canonical_revision:    u64,
	transmitted_revision:  u64,
	provider_generation:   Provider_Generation,
	service_generation:    Session_Generation,
}

/* Intelligence_Request is one bounded provider-neutral read-only request. */
Intelligence_Request :: struct {
	id:                  Intelligence_Request_ID,
	generation:          Intelligence_Request_Generation,
	kind:                Intelligence_Query_Kind,
	scope:               Intelligence_Source_Scope,
	byte_offset:         u64,
	query:               Intelligence_Text,
	include_declaration: bool,
	previous_result_id:  Semantic_Result_ID,
}

/* Intelligence_Range retains protocol coordinates and any current byte projection. */
Intelligence_Range :: struct {
	start:          LSP_Position,
	end:            LSP_Position,
	start_byte:     u64,
	end_byte:       u64,
	bytes_present:  bool,
}

/* Intelligence_Location is one copied navigable location. */
Intelligence_Location :: struct {
	id:       u64,
	uri:      Intelligence_URI,
	range:    Intelligence_Range,
	selection_range: Intelligence_Range,
	selection_present: bool,
}

/* Intelligence_Hover_Block is one copied hover fragment. */
Intelligence_Hover_Block :: struct {
	text:     Intelligence_Text,
	language: Intelligence_Text,
	markup:   bool,
}

/* Intelligence_Symbol_Kind is the stable LSP-compatible symbol vocabulary. */
Intelligence_Symbol_Kind :: enum u8 {
	Invalid,
	File,
	Module,
	Namespace,
	Package,
	Class,
	Method,
	Property,
	Field,
	Constructor,
	Enum,
	Interface,
	Function,
	Variable,
	Constant,
	String,
	Number,
	Boolean,
	Array,
	Object,
	Key,
	Null,
	Enum_Member,
	Struct,
	Event,
	Operator,
	Type_Parameter,
}

/* Intelligence_Symbol is one copied flat symbol suitable for shared result owners. */
Intelligence_Symbol :: struct {
	id:           u64,
	parent_id:    u64,
	name:         Intelligence_Text,
	detail:       Intelligence_Text,
	container:    Intelligence_Text,
	kind:         Intelligence_Symbol_Kind,
	deprecated:   bool,
	location:     Intelligence_Location,
}

/* Intelligence_Parameter is one copied signature parameter. */
Intelligence_Parameter :: struct {
	label:         Intelligence_Text,
	documentation: Intelligence_Text,
}

/* Intelligence_Signature is one copied callable signature. */
Intelligence_Signature :: struct {
	id:             u64,
	label:          Intelligence_Text,
	documentation:  Intelligence_Text,
	first_parameter: u32,
	parameter_count: u16,
}

/* Intelligence_Semantic_Token is one absolute current-document semantic span. */
Intelligence_Semantic_Token :: struct {
	start_byte: u64,
	end_byte:   u64,
	token_type: u32,
	modifiers:  u32,
	provider_order: u32,
}

/* Intelligence_Result_Descriptor identifies one immutable copied publication. */
Intelligence_Result_Descriptor :: struct {
	request_id:          Intelligence_Request_ID,
	request_generation:  Intelligence_Request_Generation,
	result_generation:   Intelligence_Result_Generation,
	kind:                Intelligence_Query_Kind,
	scope:               Intelligence_Source_Scope,
	result_id:           Semantic_Result_ID,
	active_signature:    u32,
	active_parameter:    u32,
	has_active_signature: bool,
	has_active_parameter: bool,
	partial:             bool,
	copied_bytes:        u64,
}

/* Intelligence_Result owns normalized records until explicit closure. */
Intelligence_Result :: struct {
	descriptor: Intelligence_Result_Descriptor,
	locations: []Intelligence_Location,
	hover:     []Intelligence_Hover_Block,
	symbols:   []Intelligence_Symbol,
	signatures: []Intelligence_Signature,
	parameters: []Intelligence_Parameter,
	tokens:     []Intelligence_Semantic_Token,
	allocator:  runtime.Allocator,
	closed:     bool,
}

/* Intelligence_Result_View borrows one checked immutable result generation. */
Intelligence_Result_View :: struct {
	descriptor: Intelligence_Result_Descriptor,
	locations: []Intelligence_Location,
	hover:     []Intelligence_Hover_Block,
	symbols:   []Intelligence_Symbol,
	signatures: []Intelligence_Signature,
	parameters: []Intelligence_Parameter,
	tokens:     []Intelligence_Semantic_Token,
}

/* intelligence_text_copy copies one bounded UTF-8 field. */
intelligence_text_copy :: proc(value: string) -> (Intelligence_Text, bool) {
	if len(value) > MAX_INTELLIGENCE_TEXT_BYTES || !utf8.valid_string(value) do return {}, false
	result := Intelligence_Text{length = u16(len(value))}
	copy(result.bytes[:len(value)], transmute([]u8)value)
	return result, true
}

/* intelligence_text_string borrows the initialized part of one copied field. */
intelligence_text_string :: proc(value: ^Intelligence_Text) -> string {
	if value == nil || int(value.length) > len(value.bytes) do return ""
	return string(value.bytes[:int(value.length)])
}

/* intelligence_uri_copy copies one bounded URI. */
intelligence_uri_copy :: proc(value: string) -> (Intelligence_URI, bool) {
	if len(value) == 0 || len(value) > MAX_INTELLIGENCE_URI_BYTES || !utf8.valid_string(value) do return {}, false
	result := Intelligence_URI{length = u16(len(value))}
	copy(result.bytes[:len(value)], transmute([]u8)value)
	return result, true
}

/* intelligence_uri_string borrows the initialized part of one copied URI. */
intelligence_uri_string :: proc(value: ^Intelligence_URI) -> string {
	if value == nil || int(value.length) > len(value.bytes) do return ""
	return string(value.bytes[:int(value.length)])
}

/* intelligence_request_is_valid checks exact scope and kind-specific inputs. */
intelligence_request_is_valid :: proc(request: ^Intelligence_Request) -> bool {
	if request == nil || request.id == Intelligence_Request_ID(0) ||
	   request.generation == Intelligence_Request_Generation(0) ||
	   request.kind == .Invalid || !session_handle_valid(request.scope.session) ||
	   request.scope.binding.session != request.scope.session ||
	   request.scope.binding.id == Document_Binding_ID(0) ||
	   request.scope.binding.generation == Document_Binding_Generation(0) ||
	   request.scope.document_identity == 0 || request.scope.buffer_identity == 0 ||
	   request.scope.canonical_revision == 0 || request.scope.transmitted_revision == 0 ||
	   request.scope.provider_generation != request.scope.session.provider.generation ||
	   request.scope.service_generation != request.scope.session.generation ||
	   int(request.query.length) > len(request.query.bytes) ||
	   int(request.previous_result_id.length) > len(request.previous_result_id.bytes) {
		return false
	}
	if request.kind == .Workspace_Symbols do return request.query.length > 0
	if request.kind == .Semantic_Tokens_Delta do return request.previous_result_id.length > 0
	return request.query.length == 0
}

/* intelligence_result_view borrows one live immutable result. */
intelligence_result_view :: proc(result: ^Intelligence_Result) -> (Intelligence_Result_View, bool) {
	if result == nil || result.closed || result.allocator.procedure == nil ||
	   result.descriptor.result_generation == Intelligence_Result_Generation(0) {
		return {}, false
	}
	return Intelligence_Result_View {
		descriptor = result.descriptor,
		locations = result.locations,
		hover = result.hover,
		symbols = result.symbols,
		signatures = result.signatures,
		parameters = result.parameters,
		tokens = result.tokens,
	}, true
}

/* intelligence_result_close releases every normalized record exactly once. */
intelligence_result_close :: proc(result: ^Intelligence_Result) -> bool {
	if result == nil || result.closed || result.allocator.procedure == nil do return false
	if result.locations != nil do delete(result.locations, result.allocator)
	if result.hover != nil do delete(result.hover, result.allocator)
	if result.symbols != nil do delete(result.symbols, result.allocator)
	if result.signatures != nil do delete(result.signatures, result.allocator)
	if result.parameters != nil do delete(result.parameters, result.allocator)
	if result.tokens != nil do delete(result.tokens, result.allocator)
	result^ = Intelligence_Result{closed = true}
	return true
}
