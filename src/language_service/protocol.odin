// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import "base:runtime"
import json "core:encoding/json"
import "core:unicode/utf8"

/* Message_Kind identifies one admitted JSON-RPC 2.0 message shape. */
Message_Kind :: enum u8 {
	Invalid,
	Request,
	Notification,
	Response,
	Error_Response,
}

/* Capability_Values copies the bounded initialize-result values used by the client. */
Capability_Values :: struct {
	capabilities:        Capabilities,
	position_encoding:   Position_Encoding,
	synchronization_mode: Synchronization_Mode,
	completion:          Completion_Capability_Values,
	semantic_tokens:      Semantic_Token_Capability_Values,
}

/* Unknown_Method_Action defines contained handling for an unimplemented method. */
Unknown_Method_Action :: enum u8 {
	Handled,
	Reply_Method_Not_Found,
	Ignore_And_Record,
}

/* Message_Record is one copied pointer-free JSON-RPC envelope and capability view. */
Message_Record :: struct {
	kind:         Message_Kind,
	id:           Request_ID,
	has_id:       bool,
	method:       Name_Text,
	body_bytes:   u64,
	json_depth:   u16,
	capabilities: Capability_Values,
}

/* Message owns one copied validated JSON body until message_close. */
Message :: struct {
	record:    Message_Record,
	body:      []u8,
	allocator: runtime.Allocator,
	closed:    bool,
}

/* message_decode validates strict JSON-RPC and copies its body and envelope. */
message_decode :: proc(
	body: []u8,
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
) -> (Message, bool, Failure_Context) {
	if allocator.procedure == nil || !service_limits_valid(limits) ||
	   len(body) == 0 || u64(len(body)) > limits.message_bytes ||
	   !utf8.valid_string(string(body)) {
		return {}, false, Failure_Context{
			code = .Invalid_Input,
			resource = .Message_Bytes,
			limit = limits.message_bytes,
			actual = u64(len(body)),
		}
	}
	depth, depth_ok := json_depth(body, limits.json_depth)
	if !depth_ok {
		return {}, false, Failure_Context{
			code = .Malformed_JSON,
			resource = .JSON_Depth,
			limit = u64(limits.json_depth),
			actual = u64(depth),
		}
	}
	owned, allocation_error := make([]u8, len(body), allocator)
	if allocation_error != nil {
		return {}, false, Failure_Context{code = .Allocation, resource = .Message_Bytes, actual = u64(len(body))}
	}
	copy(owned, body)
	value, parse_error := json.parse_bytes(owned, .JSON, true, context.temp_allocator)
	if parse_error != .None {
		delete(owned, allocator)
		return {}, false, Failure_Context{code = .Malformed_JSON}
	}
	defer json.destroy_value(value, context.temp_allocator)
	record, record_ok, failure := message_record(value, u64(len(body)), depth)
	if !record_ok {
		delete(owned, allocator)
		return {}, false, failure
	}
	return Message{record = record, body = owned, allocator = allocator}, true, {}
}

/* message_close releases one copied JSON body exactly once. */
message_close :: proc(message: ^Message) -> bool {
	if message == nil || message.closed || message.allocator.procedure == nil do return false
	if message.body != nil do delete(message.body, message.allocator)
	message^ = Message{closed = true}
	return true
}

/* message_method_is compares one copied method without exposing envelope storage. */
message_method_is :: proc(message: ^Message, expected: string) -> bool {
	return message != nil && !message.closed && method_matches(message.record.method, expected)
}

/* unknown_method_action selects the required response for one admitted envelope. */
unknown_method_action :: proc(record: Message_Record) -> Unknown_Method_Action {
	if record.kind != .Request && record.kind != .Notification do return .Handled
	if method_matches(record.method, "textDocument/publishDiagnostics") ||
	   method_matches(record.method, "window/logMessage") ||
	   method_matches(record.method, "$/cancelRequest") {
		return .Handled
	}
	if record.kind == .Request do return .Reply_Method_Not_Found
	return .Ignore_And_Record
}

@(private = "file")
message_record :: proc(
	value: json.Value,
	body_bytes: u64,
	depth: u16,
) -> (Message_Record, bool, Failure_Context) {
	object, object_ok := value.(json.Object)
	if !object_ok do return {}, false, Failure_Context{code = .Protocol}
	version_value, version_present := object["jsonrpc"]
	if !version_present do return {}, false, Failure_Context{code = .Protocol}
	version, version_ok := version_value.(json.String)
	if !version_ok || string(version) != "2.0" {
		return {}, false, Failure_Context{code = .Protocol}
	}

	record := Message_Record{body_bytes = body_bytes, json_depth = depth}
	if id_value, present := object["id"]; present {
		record.has_id = true
		id, id_ok := request_id_from_json(id_value)
		if !id_ok do return {}, false, Failure_Context{code = .Invalid_Request}
		record.id = id
	}
	method_present := false
	if method_value, present := object["method"]; present {
		method, method_ok := method_value.(json.String)
		if !method_ok do return {}, false, Failure_Context{code = .Protocol}
		copied, copied_ok := name_text_from_string(string(method))
		if !copied_ok do return {}, false, Failure_Context{code = .Resource_Limit, resource = .Message_Bytes, limit = MAX_NAME_BYTES, actual = u64(len(method))}
		record.method = copied
		method_present = true
	}
	_, result_present := object["result"]
	_, error_present := object["error"]
	if method_present {
		if result_present || error_present do return {}, false, Failure_Context{code = .Protocol}
		record.kind = .Request if record.has_id else .Notification
	} else {
		if !record.has_id || result_present == error_present {
			return {}, false, Failure_Context{code = .Protocol}
		}
		record.kind = .Error_Response if error_present else .Response
	}
	record.capabilities = capability_values(object)
	return record, true, {}
}

@(private = "file")
request_id_from_json :: proc(value: json.Value) -> (Request_ID, bool) {
	#partial switch id in value {
	case json.Integer:
		return Request_ID{kind = .Integer, integer = i64(id)}, true
	case json.String:
		if len(id) == 0 || len(id) > MAX_REQUEST_ID_TEXT_BYTES do return {}, false
		text := Request_ID_Text{length = u16(len(id))}
		copy(text.bytes[:len(id)], transmute([]u8)(string(id)))
		return Request_ID{kind = .Text, text = text}, true
	case json.Null:
		return {}, true
	case:
		return {}, false
	}
}

@(private)
name_text_from_string :: proc(value: string) -> (Name_Text, bool) {
	if len(value) == 0 || len(value) > MAX_NAME_BYTES || !utf8.valid_string(value) {
		return {}, false
	}
	result := Name_Text{length = u16(len(value))}
	copy(result.bytes[:len(value)], transmute([]u8)value)
	return result, true
}

@(private = "file")
method_matches :: proc(method: Name_Text, expected: string) -> bool {
	local := method
	return int(local.length) == len(expected) &&
		string(local.bytes[:int(local.length)]) == expected
}

@(private = "file")
capability_values :: proc(object: json.Object) -> Capability_Values {
	values := Capability_Values {
		capabilities = {.Initialize, .Shutdown, .Cancellation, .Push_Diagnostics, .Log_Message},
		position_encoding = .UTF_16,
	}
	result_value, result_present := object["result"]
	if !result_present do return values
	result, result_ok := result_value.(json.Object)
	if !result_ok do return values
	capability_value, capability_present := result["capabilities"]
	if !capability_present do return values
	capability_object, capability_ok := capability_value.(json.Object)
	if !capability_ok do return values
	if position_value, present := capability_object["positionEncoding"]; present {
		if position, ok := position_value.(json.String); ok {
			switch string(position) {
			case "utf-8":
				values.position_encoding = .UTF_8
			case "utf-16":
				values.position_encoding = .UTF_16
			case "utf-32":
				values.position_encoding = .UTF_32
			}
		}
	}
	if sync_value, present := capability_object["textDocumentSync"]; present {
		change := i64(0)
		#partial switch sync in sync_value {
		case json.Integer:
			change = i64(sync)
		case json.Object:
			if change_value, ok := sync["change"]; ok {
				if integer, integer_ok := change_value.(json.Integer); integer_ok do change = i64(integer)
			}
		}
		switch change {
		case 1:
			values.synchronization_mode = .Full
			values.capabilities += {.Full_Synchronization, .Save_Notification}
		case 2:
			values.synchronization_mode = .Incremental
			values.capabilities += {.Incremental_Synchronization, .Save_Notification}
		}
	}
	if completion_value, present := capability_object["completionProvider"]; present {
		if completion_object, ok := completion_value.(json.Object); ok {
			values.completion.available = true
			values.capabilities += {.Completion}
			if resolve_value, resolve_present := completion_object["resolveProvider"]; resolve_present {
				if resolve, resolve_ok := resolve_value.(json.Boolean); resolve_ok {
					values.completion.resolve = bool(resolve)
				}
			}
			if trigger_value, trigger_present := completion_object["triggerCharacters"]; trigger_present {
				if triggers, triggers_ok := trigger_value.(json.Array); triggers_ok {
					for trigger in triggers {
						if int(values.completion.trigger_count) >= MAX_COMPLETION_TRIGGER_CHARACTERS {
							break
						}
						text, text_ok := trigger.(json.String)
						if !text_ok || len(text) == 0 || len(text) > MAX_COMPLETION_TRIGGER_BYTES ||
						   !utf8.valid_string(string(text)) {
							continue
						}
						index := int(values.completion.trigger_count)
						values.completion.trigger_characters[index].length = u8(len(text))
						copy(
							values.completion.trigger_characters[index].bytes[:len(text)],
							transmute([]u8)(string(text)),
						)
						values.completion.trigger_count += 1
					}
				}
			}
		}
	}
	capability_boolean_or_object(capability_object, "hoverProvider", .Hover, &values.capabilities)
	capability_boolean_or_object(capability_object, "definitionProvider", .Definition, &values.capabilities)
	capability_boolean_or_object(capability_object, "referencesProvider", .References, &values.capabilities)
	capability_boolean_or_object(capability_object, "documentSymbolProvider", .Document_Symbols, &values.capabilities)
	capability_boolean_or_object(capability_object, "workspaceSymbolProvider", .Workspace_Symbols, &values.capabilities)
	capability_boolean_or_object(capability_object, "signatureHelpProvider", .Signature_Help, &values.capabilities)
	if semantic_value, present := capability_object["semanticTokensProvider"]; present {
		if semantic_object, ok := semantic_value.(json.Object); ok {
			values.capabilities += {.Semantic_Tokens}
			values.semantic_tokens.available = true
			if legend_value, legend_present := semantic_object["legend"]; legend_present {
				if legend, legend_ok := legend_value.(json.Object); legend_ok {
					if types_value, types_present := legend["tokenTypes"]; types_present {
						if types, types_ok := types_value.(json.Array); types_ok {
							for token_type in types {
								if values.semantic_tokens.token_count >= MAX_SEMANTIC_TOKEN_TYPES do break
								name, name_ok := token_type.(json.String)
								if !name_ok do continue
								copied, copied_ok := name_text_from_string(string(name))
								if !copied_ok do continue
								values.semantic_tokens.token_types[values.semantic_tokens.token_count] = copied
								values.semantic_tokens.token_count += 1
							}
						}
					}
				}
			}
			if full_value, full_present := semantic_object["full"]; full_present {
				if full_object, full_ok := full_value.(json.Object); full_ok {
					if delta_value, delta_present := full_object["delta"]; delta_present {
						if delta, delta_ok := delta_value.(json.Boolean); delta_ok {
							values.semantic_tokens.delta = bool(delta)
						}
					}
				}
			}
		}
	}
	return values
}

@(private = "file")
capability_boolean_or_object :: proc(
	object: json.Object,
	name: string,
	capability: Capability,
	values: ^Capabilities,
) {
	value, present := object[name]
	if !present do return
	#partial switch provider in value {
	case json.Boolean:
		if bool(provider) do values^ += {capability}
	case json.Object:
		values^ += {capability}
	case:
	}
}

@(private = "file")
json_depth :: proc(input: []u8, limit: u16) -> (u16, bool) {
	stack: [64]u8
	depth := 0
	maximum := 0
	in_string := false
	escaped := false
	for character in input {
		if in_string {
			if escaped {
				escaped = false
			} else if character == '\\' {
				escaped = true
			} else if character == '"' {
				in_string = false
			}
			continue
		}
		if character == '"' {
			in_string = true
			continue
		}
		if character == '{' || character == '[' {
			if depth >= int(limit) || depth >= len(stack) do return u16(depth + 1), false
			stack[depth] = character
			depth += 1
			maximum = max(maximum, depth)
		} else if character == '}' || character == ']' {
			if depth == 0 do return u16(maximum), false
			expected := byte('{') if character == '}' else byte('[')
			if stack[depth - 1] != expected do return u16(maximum), false
			depth -= 1
		}
	}
	return u16(maximum), !in_string && !escaped && depth == 0
}
