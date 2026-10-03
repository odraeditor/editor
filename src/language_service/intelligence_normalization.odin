// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import json "core:encoding/json"
import "core:unicode/utf8"

/* intelligence_response_normalize validates and copies one exact read-only response. */
intelligence_response_normalize :: proc(
	exchange: ^Intelligence_Exchange,
	synchronizer: ^Document_Synchronizer,
	message: ^Message,
	allocator := context.allocator,
) -> (Intelligence_Result, bool, Failure_Context) {
	state := intelligence_exchange_state(exchange)
	if state == nil do return {}, false, Failure_Context{code = .Closed}
	if state.request_state != .Sent || message == nil || message.closed ||
	   !message.record.has_id || message.record.id != state.request_id {
		return {}, false, intelligence_exchange_reject(state, .Stale_Generation)
	}
	if allocator.procedure == nil {
		return {}, false, intelligence_exchange_fail_request(state, .Allocation)
	}
	if message.record.kind != .Response {
		return {}, false, intelligence_exchange_fail_request(state, .Protocol)
	}
	descriptor, bound, binding_failure := document_synchronizer_binding(synchronizer, state.binding)
	if !bound {
		_, failure := intelligence_exchange_fail(exchange, binding_failure)
		return {}, false, failure
	}
	if descriptor.state != .Open || descriptor.handle.session != state.session ||
	   descriptor.document_identity != state.request.scope.document_identity ||
	   descriptor.buffer_identity != state.request.scope.buffer_identity ||
	   descriptor.canonical_revision != state.request.scope.canonical_revision ||
	   descriptor.transmitted_revision != descriptor.canonical_revision ||
	   descriptor.transmitted_revision != state.request.scope.transmitted_revision {
		return {}, false, intelligence_exchange_fail_request(state, .Stale_Generation)
	}
	text, text_ok, text_failure := document_synchronizer_text(synchronizer, state.binding)
	if !text_ok {
		_, failure := intelligence_exchange_fail(exchange, text_failure)
		return {}, false, failure
	}
	uri, uri_ok, uri_failure := document_synchronizer_uri(synchronizer, state.binding)
	if !uri_ok {
		_, failure := intelligence_exchange_fail(exchange, uri_failure)
		return {}, false, failure
	}
	value, parse_error := json.parse_bytes(message.body, .JSON, true, context.temp_allocator)
	if parse_error != .None {
		return {}, false, intelligence_exchange_fail_request(state, .Malformed_JSON)
	}
	defer json.destroy_value(value, context.temp_allocator)
	result_value, result_ok := intelligence_json_result(value)
	if !result_ok {
		return {}, false, intelligence_exchange_fail_request(state, .Protocol)
	}
	result := Intelligence_Result {
		descriptor = {
			request_id = state.request.id,
			request_generation = state.request.generation,
			result_generation = state.next_result_generation,
			kind = state.request.kind,
			scope = state.request.scope,
		},
		allocator = allocator,
	}
	if state.next_result_generation == Intelligence_Result_Generation(0) {
		return {}, false, intelligence_exchange_fail_request(state, .Arithmetic_Overflow)
	}
	normalized := false
	#partial switch state.request.kind {
	case .Hover:
		normalized = intelligence_normalize_hover(&result, result_value, state)
	case .Definition, .References:
		normalized = intelligence_normalize_locations(&result, result_value, text, uri, descriptor.position_encoding, state)
	case .Document_Symbols, .Workspace_Symbols:
		normalized = intelligence_normalize_symbols(&result, result_value, text, uri, descriptor.position_encoding, state)
	case .Signature_Help:
		normalized = intelligence_normalize_signatures(&result, result_value, state)
	case .Semantic_Tokens_Full, .Semantic_Tokens_Delta:
		normalized = intelligence_normalize_semantic_tokens(&result, result_value, text, state)
	case .Invalid:
	}
	if !normalized {
		intelligence_result_close(&result)
		if state.latest_failure.code == .None {
			intelligence_exchange_fail_request(state, .Protocol)
		}
		return {}, false, state.latest_failure
	}
	state.next_result_generation += 1
	state.request_state = .Completed
	state.deadline_ns = 0
	intelligence_exchange_release_body(state)
	state.latest_failure = {}
	return result, true, {}
}

@(private = "file")
intelligence_json_result :: proc(value: json.Value) -> (json.Value, bool) {
	object, object_ok := value.(json.Object)
	if !object_ok do return {}, false
	if _, partial := object["partialResultToken"]; partial do return {}, false
	result, present := object["result"]
	return result, present
}

@(private = "file")
intelligence_normalize_hover :: proc(
	output: ^Intelligence_Result,
	value: json.Value,
	state: ^Intelligence_Exchange_State,
) -> bool {
	if _, empty := value.(json.Null); empty do return true
	object, object_ok := value.(json.Object)
	if !object_ok do return intelligence_normalization_fail(state, .Protocol)
	if _, partial := object["partialResultToken"]; partial {
		return intelligence_normalization_fail(state, .Protocol)
	}
	contents, present := object["contents"]
	if !present do return intelligence_normalization_fail(state, .Protocol)
	blocks, allocation_error := make([dynamic]Intelligence_Hover_Block, 0, 4, output.allocator)
	if allocation_error != nil do return intelligence_normalization_fail(state, .Allocation)
	accepted := intelligence_hover_value_append(&blocks, contents)
	if !accepted {
		delete(blocks)
		return intelligence_normalization_fail(state, .Protocol)
	}
	if len(blocks) > int(state.limits.candidates) {
		delete(blocks)
		return intelligence_resource_fail(state, .Candidate, u64(state.limits.candidates), u64(len(blocks)))
	}
	for block in blocks {
		output.descriptor.copied_bytes += u64(block.text.length) + u64(block.language.length)
	}
	if output.descriptor.copied_bytes > state.limits.candidate_text_bytes {
		delete(blocks)
		return intelligence_resource_fail(state, .Candidate_Text_Bytes, state.limits.candidate_text_bytes, output.descriptor.copied_bytes)
	}
	output.hover = blocks[:]
	return true
}

@(private = "file")
intelligence_hover_value_append :: proc(
	blocks: ^[dynamic]Intelligence_Hover_Block,
	value: json.Value,
) -> bool {
	#partial switch content in value {
	case json.String:
		text, copied := intelligence_text_copy(string(content))
		if !copied do return false
		_, append_error := append(blocks, Intelligence_Hover_Block{text = text})
		return append_error == nil
	case json.Object:
		if value_field, present := content["value"]; present {
			body, body_ok := value_field.(json.String)
			if !body_ok do return false
			text, copied := intelligence_text_copy(string(body))
			if !copied do return false
			block := Intelligence_Hover_Block{text = text}
			if language_field, language_present := content["language"]; language_present {
				language, language_ok := language_field.(json.String)
				if !language_ok do return false
				block.language, copied = intelligence_text_copy(string(language))
				if !copied do return false
			} else if kind_field, kind_present := content["kind"]; kind_present {
				kind, kind_ok := kind_field.(json.String)
				if !kind_ok || (kind != "plaintext" && kind != "markdown") do return false
				block.markup = kind == "markdown"
			}
			_, append_error := append(blocks, block)
			return append_error == nil
		}
		return false
	case json.Array:
		for item in content {
			if !intelligence_hover_value_append(blocks, item) do return false
		}
		return true
	case:
		return false
	}
}

@(private = "file")
intelligence_normalize_locations :: proc(
	output: ^Intelligence_Result,
	value: json.Value,
	document_text, document_uri: string,
	encoding: Position_Encoding,
	state: ^Intelligence_Exchange_State,
) -> bool {
	locations, allocation_error := make([dynamic]Intelligence_Location, 0, 8, output.allocator)
	if allocation_error != nil do return intelligence_normalization_fail(state, .Allocation)
	if _, empty := value.(json.Null); !empty {
		#partial switch payload in value {
		case json.Array:
			if len(payload) > int(state.limits.candidates) {
				delete(locations)
				return intelligence_resource_fail(state, .Candidate, u64(state.limits.candidates), u64(len(payload)))
			}
			for item in payload {
				location, ok := intelligence_location_from_json(item, document_text, document_uri, encoding)
				if !ok {
					delete(locations)
					return intelligence_normalization_fail(state, .Protocol)
				}
				intelligence_location_append_unique(&locations, location)
			}
		case json.Object:
			location, ok := intelligence_location_from_json(payload, document_text, document_uri, encoding)
			if !ok {
				delete(locations)
				return intelligence_normalization_fail(state, .Protocol)
			}
			intelligence_location_append_unique(&locations, location)
		case:
			delete(locations)
			return intelligence_normalization_fail(state, .Protocol)
		}
	}
	for index in 0 ..< len(locations) do locations[index].id = u64(index + 1)
	output.locations = locations[:]
	return true
}

@(private = "file")
intelligence_location_from_json :: proc(
	value: json.Value,
	document_text, document_uri: string,
	encoding: Position_Encoding,
) -> (Intelligence_Location, bool) {
	object, object_ok := value.(json.Object)
	if !object_ok do return {}, false
	uri_key := "uri"
	range_key := "range"
	if _, target := object["targetUri"]; target {
		uri_key = "targetUri"
		range_key = "targetRange"
	}
	uri_value, uri_present := object[uri_key]
	range_value, range_present := object[range_key]
	uri_string, uri_ok := uri_value.(json.String)
	if !uri_present || !range_present || !uri_ok || !utf8.valid_string(string(uri_string)) do return {}, false
	uri, copied := intelligence_uri_copy(string(uri_string))
	if !copied do return {}, false
	range_result, range_ok := intelligence_range_from_json(
		range_value,
		document_text,
		string(uri_string) == document_uri,
		encoding,
	)
	if !range_ok do return {}, false
	result := Intelligence_Location{uri = uri, range = range_result}
	if selection_value, present := object["targetSelectionRange"]; present {
		result.selection_range, range_ok = intelligence_range_from_json(
			selection_value,
			document_text,
			string(uri_string) == document_uri,
			encoding,
		)
		if !range_ok do return {}, false
		result.selection_present = true
	}
	return result, true
}

@(private = "file")
intelligence_range_from_json :: proc(
	value: json.Value,
	document_text: string,
	current_document: bool,
	encoding: Position_Encoding,
) -> (Intelligence_Range, bool) {
	object, object_ok := value.(json.Object)
	if !object_ok do return {}, false
	start_value, start_present := object["start"]
	end_value, end_present := object["end"]
	start, start_ok := lsp_position_from_json(start_value)
	end, end_ok := lsp_position_from_json(end_value)
	if !start_present || !end_present || !start_ok || !end_ok ||
	   start.line > end.line || (start.line == end.line && start.character > end.character) {
		return {}, false
	}
	result := Intelligence_Range{start = start, end = end}
	if current_document {
		result.start_byte, start_ok, _ = position_to_byte_offset(document_text, start, encoding)
		result.end_byte, end_ok, _ = position_to_byte_offset(document_text, end, encoding)
		if !start_ok || !end_ok || result.end_byte < result.start_byte do return {}, false
		result.bytes_present = true
	}
	return result, true
}

@(private = "file")
intelligence_location_append_unique :: proc(
	locations: ^[dynamic]Intelligence_Location,
	candidate: Intelligence_Location,
) -> bool {
	for current in locations^ {
		current_uri := current.uri
		candidate_uri := candidate.uri
		if current.uri.length == candidate.uri.length && current.range.start == candidate.range.start &&
		   current.range.end == candidate.range.end &&
		   intelligence_uri_string(&current_uri) == intelligence_uri_string(&candidate_uri) {
			return true
		}
	}
	_, append_error := append(locations, candidate)
	return append_error == nil
}

@(private = "file")
intelligence_normalize_symbols :: proc(
	output: ^Intelligence_Result,
	value: json.Value,
	document_text, document_uri: string,
	encoding: Position_Encoding,
	state: ^Intelligence_Exchange_State,
) -> bool {
	symbols, allocation_error := make([dynamic]Intelligence_Symbol, 0, 16, output.allocator)
	if allocation_error != nil do return intelligence_normalization_fail(state, .Allocation)
	if _, empty := value.(json.Null); !empty {
		items, items_ok := value.(json.Array)
		if !items_ok {
			delete(symbols)
			return intelligence_normalization_fail(state, .Protocol)
		}
		if !intelligence_symbols_append(&symbols, items, 0, document_text, document_uri, encoding, state) {
			delete(symbols)
			return false
		}
	}
	output.symbols = symbols[:]
	return true
}

@(private = "file")
intelligence_symbols_append :: proc(
	symbols: ^[dynamic]Intelligence_Symbol,
	items: json.Array,
	parent_id: u64,
	document_text, document_uri: string,
	encoding: Position_Encoding,
	state: ^Intelligence_Exchange_State,
) -> bool {
	for item in items {
		if len(symbols^) >= int(state.limits.candidates) {
			return intelligence_resource_fail(state, .Candidate, u64(state.limits.candidates), u64(len(symbols^) + 1))
		}
		object, object_ok := item.(json.Object)
		if !object_ok do return intelligence_normalization_fail(state, .Protocol)
		if _, partial := object["partialResultToken"]; partial do return intelligence_normalization_fail(state, .Protocol)
		name_value, name_present := object["name"]
		kind_value, kind_present := object["kind"]
		name_string, name_ok := name_value.(json.String)
		kind_integer, kind_ok := kind_value.(json.Integer)
		if !name_present || !kind_present || !name_ok || !kind_ok ||
		   kind_integer < 1 || kind_integer > 26 || !utf8.valid_string(string(name_string)) {
			return intelligence_normalization_fail(state, .Protocol)
		}
		name, copied := intelligence_text_copy(string(name_string))
		if !copied do return intelligence_resource_fail(state, .Candidate_Text_Bytes, MAX_INTELLIGENCE_TEXT_BYTES, u64(len(name_string)))
		symbol := Intelligence_Symbol {
			id = u64(len(symbols^) + 1),
			parent_id = parent_id,
			name = name,
			kind = Intelligence_Symbol_Kind(kind_integer),
		}
		if location_value, location_present := object["location"]; location_present {
			symbol.location, copied = intelligence_location_from_json(location_value, document_text, document_uri, encoding)
			if !copied do return intelligence_normalization_fail(state, .Protocol)
		} else {
			range_value, range_present := object["range"]
			if !range_present do return intelligence_normalization_fail(state, .Protocol)
			symbol.location.uri, copied = intelligence_uri_copy(document_uri)
			if !copied do return intelligence_normalization_fail(state, .Protocol)
			symbol.location.range, copied = intelligence_range_from_json(range_value, document_text, true, encoding)
			if !copied do return intelligence_normalization_fail(state, .Protocol)
			if selection_value, selection_present := object["selectionRange"]; selection_present {
				symbol.location.selection_range, copied = intelligence_range_from_json(selection_value, document_text, true, encoding)
				if !copied do return intelligence_normalization_fail(state, .Protocol)
				symbol.location.selection_present = true
			}
		}
		symbol.location.id = symbol.id
		if detail_value, present := object["detail"]; present {
			detail, detail_ok := detail_value.(json.String)
			if !detail_ok do return intelligence_normalization_fail(state, .Protocol)
			symbol.detail, copied = intelligence_text_copy(string(detail))
			if !copied do return intelligence_resource_fail(state, .Candidate_Text_Bytes, MAX_INTELLIGENCE_TEXT_BYTES, u64(len(detail)))
		}
		if container_value, present := object["containerName"]; present {
			container, container_ok := container_value.(json.String)
			if !container_ok do return intelligence_normalization_fail(state, .Protocol)
			symbol.container, copied = intelligence_text_copy(string(container))
			if !copied do return intelligence_resource_fail(state, .Candidate_Text_Bytes, MAX_INTELLIGENCE_TEXT_BYTES, u64(len(container)))
		}
		if tags_value, present := object["tags"]; present {
			if tags, tags_ok := tags_value.(json.Array); tags_ok {
				for tag in tags {
					if numeric, ok := tag.(json.Integer); ok && numeric == 1 do symbol.deprecated = true
				}
			}
		}
		output_bytes := u64(symbol.name.length) + u64(symbol.detail.length) + u64(symbol.container.length)
		if output_bytes > state.limits.candidate_text_bytes do return intelligence_resource_fail(state, .Candidate_Text_Bytes, state.limits.candidate_text_bytes, output_bytes)
		_, append_error := append(symbols, symbol)
		if append_error != nil do return intelligence_normalization_fail(state, .Allocation)
		if children_value, present := object["children"]; present {
			children, children_ok := children_value.(json.Array)
			if !children_ok || !intelligence_symbols_append(symbols, children, symbol.id, document_text, document_uri, encoding, state) {
				return false
			}
		}
	}
	return true
}

@(private = "file")
intelligence_normalize_signatures :: proc(
	output: ^Intelligence_Result,
	value: json.Value,
	state: ^Intelligence_Exchange_State,
) -> bool {
	if _, empty := value.(json.Null); empty do return true
	object, object_ok := value.(json.Object)
	if !object_ok do return intelligence_normalization_fail(state, .Protocol)
	signatures_value, present := object["signatures"]
	signature_items, signatures_ok := signatures_value.(json.Array)
	if !present || !signatures_ok do return intelligence_normalization_fail(state, .Protocol)
	if len(signature_items) > int(state.limits.candidates) {
		return intelligence_resource_fail(state, .Candidate, u64(state.limits.candidates), u64(len(signature_items)))
	}
	signatures, allocation_error := make([]Intelligence_Signature, len(signature_items), output.allocator)
	if allocation_error != nil do return intelligence_normalization_fail(state, .Allocation)
	parameters, parameters_error := make([dynamic]Intelligence_Parameter, 0, min(len(signature_items) * 4, MAX_SIGNATURE_PARAMETERS), output.allocator)
	if parameters_error != nil {
		delete(signatures)
		return intelligence_normalization_fail(state, .Allocation)
	}
	for item, index in signature_items {
		signature_object, signature_ok := item.(json.Object)
		if !signature_ok {
			delete(signatures); delete(parameters)
			return intelligence_normalization_fail(state, .Protocol)
		}
		label_value, label_present := signature_object["label"]
		label_string, label_ok := label_value.(json.String)
		if !label_present || !label_ok {
			delete(signatures); delete(parameters)
			return intelligence_normalization_fail(state, .Protocol)
		}
		label, copied := intelligence_text_copy(string(label_string))
		if !copied {
			delete(signatures); delete(parameters)
			return intelligence_resource_fail(state, .Candidate_Text_Bytes, MAX_INTELLIGENCE_TEXT_BYTES, u64(len(label_string)))
		}
		signatures[index] = {id = u64(index + 1), label = label, first_parameter = u32(len(parameters))}
		if documentation_value, documentation_present := signature_object["documentation"]; documentation_present {
			documentation, documentation_ok := intelligence_documentation_text(documentation_value)
			if !documentation_ok {
				delete(signatures); delete(parameters)
				return intelligence_normalization_fail(state, .Protocol)
			}
			signatures[index].documentation, copied = intelligence_text_copy(documentation)
			if !copied {
				delete(signatures); delete(parameters)
				return intelligence_resource_fail(state, .Candidate_Text_Bytes, MAX_INTELLIGENCE_TEXT_BYTES, u64(len(documentation)))
			}
		}
		if parameters_value, parameters_present := signature_object["parameters"]; parameters_present {
			parameter_items, parameters_ok := parameters_value.(json.Array)
			if !parameters_ok || len(parameters) + len(parameter_items) > MAX_SIGNATURE_PARAMETERS {
				delete(signatures); delete(parameters)
				return intelligence_resource_fail(state, .Candidate, MAX_SIGNATURE_PARAMETERS, u64(len(parameters) + len(parameter_items)))
			}
			for parameter_value in parameter_items {
				parameter_object, parameter_ok := parameter_value.(json.Object)
				if !parameter_ok {
					delete(signatures); delete(parameters)
					return intelligence_normalization_fail(state, .Protocol)
				}
				parameter := Intelligence_Parameter{}
				parameter_label, parameter_label_present := parameter_object["label"]
				#partial switch label in parameter_label {
				case json.String:
					parameter.label, copied = intelligence_text_copy(string(label))
				case json.Array:
					if len(label) != 2 do copied = false
					if len(label) == 2 {
						start, start_ok := label[0].(json.Integer)
						end, end_ok := label[1].(json.Integer)
						copied = label_present && start_ok && end_ok && start >= 0 && end >= start && end <= i64(len(label_string))
						if copied do parameter.label, copied = intelligence_text_copy(string(label_string)[int(start):int(end)])
					}
				case:
					copied = false
				}
				if !parameter_label_present || !copied {
					delete(signatures); delete(parameters)
					return intelligence_normalization_fail(state, .Protocol)
				}
				if documentation_value, documentation_present := parameter_object["documentation"]; documentation_present {
					documentation, documentation_ok := intelligence_documentation_text(documentation_value)
					if !documentation_ok {
						delete(signatures); delete(parameters)
						return intelligence_normalization_fail(state, .Protocol)
					}
					parameter.documentation, copied = intelligence_text_copy(documentation)
					if !copied {
						delete(signatures); delete(parameters)
						return intelligence_resource_fail(state, .Candidate_Text_Bytes, MAX_INTELLIGENCE_TEXT_BYTES, u64(len(documentation)))
					}
				}
				_, append_error := append(&parameters, parameter)
				if append_error != nil {
					delete(signatures); delete(parameters)
					return intelligence_normalization_fail(state, .Allocation)
				}
			}
			signatures[index].parameter_count = u16(len(parameter_items))
		}
	}
	if active_value, active_signature_present := object["activeSignature"]; active_signature_present {
		active, ok := active_value.(json.Integer)
		if !ok || active < 0 || active >= i64(len(signatures)) {
			delete(signatures); delete(parameters)
			return intelligence_normalization_fail(state, .Protocol)
		}
		output.descriptor.active_signature = u32(active)
		output.descriptor.has_active_signature = true
	}
	if active_value, active_parameter_present := object["activeParameter"]; active_parameter_present {
		active, ok := active_value.(json.Integer)
		if !ok || active < 0 || active > i64(max(u32)) {
			delete(signatures); delete(parameters)
			return intelligence_normalization_fail(state, .Protocol)
		}
		output.descriptor.active_parameter = u32(active)
		output.descriptor.has_active_parameter = true
	}
	output.signatures = signatures
	output.parameters = parameters[:]
	return true
}

@(private = "file")
intelligence_documentation_text :: proc(value: json.Value) -> (string, bool) {
	#partial switch documentation in value {
	case json.String:
		return string(documentation), utf8.valid_string(string(documentation))
	case json.Object:
		value_field, present := documentation["value"]
		text, ok := value_field.(json.String)
		return string(text), present && ok && utf8.valid_string(string(text))
	case:
		return "", false
	}
}

@(private = "file")
intelligence_normalize_semantic_tokens :: proc(
	output: ^Intelligence_Result,
	value: json.Value,
	document_text: string,
	state: ^Intelligence_Exchange_State,
) -> bool {
	if _, empty := value.(json.Null); empty {
		if state.semantic_data != nil do clear(&state.semantic_data)
		state.semantic_result_id = {}
		return true
	}
	object, object_ok := value.(json.Object)
	if !object_ok do return intelligence_normalization_fail(state, .Protocol)
	if _, partial := object["partialResultToken"]; partial do return intelligence_normalization_fail(state, .Protocol)
	data, allocation_error := make([dynamic]u32, 0, len(state.semantic_data), output.allocator)
	if allocation_error != nil do return intelligence_normalization_fail(state, .Allocation)
	if data_value, present := object["data"]; present {
		items, items_ok := data_value.(json.Array)
		if !items_ok || !intelligence_semantic_data_append(&data, items, state) {
			delete(data)
			return false
		}
	} else if edits_value, edits_present := object["edits"]; edits_present {
		if state.request.kind != .Semantic_Tokens_Delta || state.semantic_result_id.length == 0 ||
		   state.semantic_result_id.length != state.request.previous_result_id.length ||
		   string(state.semantic_result_id.bytes[:int(state.semantic_result_id.length)]) !=
		   string(state.request.previous_result_id.bytes[:int(state.request.previous_result_id.length)]) {
			delete(data)
			return intelligence_normalization_fail(state, .Stale_Generation)
		}
		_, append_error := append(&data, ..state.semantic_data[:])
		if append_error != nil {
			delete(data)
			return intelligence_normalization_fail(state, .Allocation)
		}
		edits, edits_ok := edits_value.(json.Array)
		if !edits_ok || !intelligence_semantic_apply_edits(&data, edits, state) {
			delete(data)
			return false
		}
	} else {
		delete(data)
		return intelligence_normalization_fail(state, .Protocol)
	}
	if len(data) % 5 != 0 {
		delete(data)
		return intelligence_normalization_fail(state, .Protocol)
	}
	tokens, tokens_error := make([]Intelligence_Semantic_Token, len(data) / 5, output.allocator)
	if tokens_error != nil {
		delete(data)
		return intelligence_normalization_fail(state, .Allocation)
	}
	line, character := u32(0), u32(0)
	for index in 0 ..< len(tokens) {
		base := index * 5
		delta_line := data[base]
		delta_start := data[base + 1]
		if delta_line > max(u32) - line {
			delete(data); delete(tokens)
			return intelligence_normalization_fail(state, .Arithmetic_Overflow)
		}
		line += delta_line
		if delta_line == 0 {
			if delta_start > max(u32) - character {
				delete(data); delete(tokens)
				return intelligence_normalization_fail(state, .Arithmetic_Overflow)
			}
			character += delta_start
		} else {
			character = delta_start
		}
		length := data[base + 2]
		if length == 0 || length > max(u32) - character {
			delete(data); delete(tokens)
			return intelligence_normalization_fail(state, .Protocol)
		}
		start, start_ok, _ := position_to_byte_offset(document_text, {line = line, character = character}, state.capabilities.position_encoding)
		end, end_ok, _ := position_to_byte_offset(document_text, {line = line, character = character + length}, state.capabilities.position_encoding)
		if !start_ok || !end_ok || end <= start || index > 0 && start < tokens[index - 1].end_byte {
			delete(data); delete(tokens)
			return intelligence_normalization_fail(state, .Invalid_Range)
		}
		tokens[index] = {
			start_byte = start,
			end_byte = end,
			token_type = data[base + 3],
			modifiers = data[base + 4],
			provider_order = u32(index),
		}
	}
	result_id := Semantic_Result_ID{}
	if result_id_value, present := object["resultId"]; present {
		result_id_string, result_id_ok := result_id_value.(json.String)
		if !result_id_ok || len(result_id_string) == 0 || len(result_id_string) > MAX_INTELLIGENCE_RESULT_ID_BYTES {
			delete(data); delete(tokens)
			return intelligence_normalization_fail(state, .Protocol)
		}
		result_id.length = u16(len(result_id_string))
		copy(result_id.bytes[:len(result_id_string)], transmute([]u8)(string(result_id_string)))
	}
	if state.semantic_data != nil do delete(state.semantic_data)
	state.semantic_data = data
	state.semantic_result_id = result_id
	output.descriptor.result_id = result_id
	output.tokens = tokens
	return true
}

@(private = "file")
intelligence_semantic_data_append :: proc(
	data: ^[dynamic]u32,
	items: json.Array,
	state: ^Intelligence_Exchange_State,
) -> bool {
	if len(items) % 5 != 0 || len(items) > int(state.limits.candidates) * 5 {
		return intelligence_resource_fail(state, .Candidate, u64(state.limits.candidates), u64(len(items) / 5))
	}
	for item in items {
		integer, ok := item.(json.Integer)
		if !ok || integer < 0 || integer > i64(max(u32)) do return intelligence_normalization_fail(state, .Protocol)
		_, append_error := append(data, u32(integer))
		if append_error != nil do return intelligence_normalization_fail(state, .Allocation)
	}
	return true
}

@(private = "file")
intelligence_semantic_apply_edits :: proc(
	data: ^[dynamic]u32,
	edits: json.Array,
	state: ^Intelligence_Exchange_State,
) -> bool {
	last_start := i64(-1)
	for edit_value in edits {
		edit, edit_ok := edit_value.(json.Object)
		if !edit_ok do return intelligence_normalization_fail(state, .Protocol)
		start_value, start_present := edit["start"]
		delete_value, delete_present := edit["deleteCount"]
		start, start_ok := start_value.(json.Integer)
		delete_count, delete_ok := delete_value.(json.Integer)
		if !start_present || !delete_present || !start_ok || !delete_ok || start < 0 ||
		   delete_count < 0 || start < last_start || start > i64(len(data^)) ||
		   delete_count > i64(len(data^)) - start {
			return intelligence_normalization_fail(state, .Protocol)
		}
		last_start = start
		replacement, allocation_error := make([dynamic]u32, 0, 8, context.temp_allocator)
		if allocation_error != nil do return intelligence_normalization_fail(state, .Allocation)
		defer delete(replacement)
		if replacement_value, present := edit["data"]; present {
			items, items_ok := replacement_value.(json.Array)
			if !items_ok || !intelligence_semantic_data_append(&replacement, items, state) do return false
		}
		new_length := len(data^) - int(delete_count) + len(replacement)
		if new_length > int(state.limits.candidates) * 5 {
			return intelligence_resource_fail(state, .Candidate, u64(state.limits.candidates), u64(new_length / 5))
		}
		updated, updated_error := make([dynamic]u32, 0, new_length, state.allocator)
		if updated_error != nil do return intelligence_normalization_fail(state, .Allocation)
		_, first_error := append(&updated, ..data^[:int(start)])
		_, replacement_error := append(&updated, ..replacement[:])
		_, tail_error := append(&updated, ..data^[int(start + delete_count):])
		if first_error != nil || replacement_error != nil || tail_error != nil {
			delete(updated)
			return intelligence_normalization_fail(state, .Allocation)
		}
		delete(data^)
		data^ = updated
	}
	return true
}

@(private = "file")
intelligence_normalization_fail :: proc(state: ^Intelligence_Exchange_State, code: Failure_Code) -> bool {
	intelligence_exchange_fail_request(state, code)
	return false
}

@(private = "file")
intelligence_resource_fail :: proc(
	state: ^Intelligence_Exchange_State,
	resource: Resource_Kind,
	limit, actual: u64,
) -> bool {
	failure := intelligence_exchange_fail_request(state, .Resource_Limit)
	failure.resource = resource
	failure.limit = limit
	failure.actual = actual
	state.latest_failure = failure
	return false
}
