// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import completion "../completion"
import "base:runtime"
import json "core:encoding/json"
import "core:unicode/utf8"

/* Completion_Batch_Owner owns one normalized batch until publication or closure. */
Completion_Batch_Owner :: struct {
	batch:     completion.Batch,
	allocator: runtime.Allocator,
	closed:    bool,
}

@(private)
Completion_Result_View :: struct {
	items:       json.Array,
	incomplete:  bool,
	defaults:    json.Object,
}

@(private)
Completion_Documentation_View :: struct {
	text:   string,
	format: completion.Documentation_Format,
}

/* completion_response_normalize validates and owns one exact completion response. */
completion_response_normalize :: proc(
	exchange: ^Completion_Exchange,
	synchronizer: ^Document_Synchronizer,
	message: ^Message,
	allocator := context.allocator,
) -> (Completion_Batch_Owner, bool, Failure_Context) {
	state := completion_exchange_state(exchange)
	if state == nil do return {}, false, Failure_Context{code = .Closed}
	if state.request_state != .Sent || message == nil || message.closed ||
	   !message.record.has_id || message.record.id != state.request_id {
		return {}, false, completion_exchange_reject(state, .Stale_Generation)
	}
	if allocator.procedure == nil {
		return {}, false, completion_exchange_fail_request(state, .Allocation)
	}
	if message.record.kind != .Response {
		return {}, false, completion_exchange_fail_request(state, .Protocol)
	}
	descriptor, bound, binding_failure := document_synchronizer_binding(synchronizer, state.binding)
	if !bound {
		_, failure := completion_exchange_fail(exchange, binding_failure)
		return {}, false, failure
	}
	if descriptor.state != .Open || descriptor.handle.session != state.session ||
	   completion.Document_Revision(descriptor.canonical_revision) != state.request.scope.document_revision ||
	   descriptor.transmitted_revision != descriptor.canonical_revision ||
	   completion.Document_Revision(descriptor.transmitted_revision) != state.request.scope.transmitted_revision {
		return {}, false, completion_exchange_fail_request(state, .Stale_Generation)
	}
	text, text_ok, text_failure := document_synchronizer_text(synchronizer, state.binding)
	if !text_ok {
		_, failure := completion_exchange_fail(exchange, text_failure)
		return {}, false, failure
	}
	value, parse_error := json.parse_bytes(message.body, .JSON, true, context.temp_allocator)
	if parse_error != .None {
		return {}, false, completion_exchange_fail_request(state, .Malformed_JSON)
	}
	defer json.destroy_value(value, context.temp_allocator)
	result, result_ok := completion_result_from_json(value)
	if !result_ok {
		return {}, false, completion_exchange_fail_request(state, .Protocol)
	}
	if len(result.items) > int(state.limits.candidates) {
		failure := completion_exchange_fail_request(state, .Resource_Limit)
		failure.resource = .Candidate
		failure.limit = u64(state.limits.candidates)
		failure.actual = u64(len(result.items))
		state.latest_failure = failure
		return {}, false, failure
	}
	capacity := min(len(result.items), completion.MAX_COMPLETION_CANDIDATES)
	items, allocation_error := make([]completion.Candidate, capacity, allocator)
	if allocation_error != nil {
		return {}, false, completion_exchange_fail_request(state, .Allocation)
	}
	accepted := 0
	rejected := u32(0)
	warnings := u32(0)
	copied_bytes := u64(0)
	for item_value, provider_order in result.items {
		if accepted >= capacity {
			rejected += 1
			continue
		}
		candidate, normalized, item_warnings := completion_candidate_from_json(
			item_value,
			result.defaults,
			text,
			descriptor.position_encoding,
			state.request,
			u32(provider_order),
		)
		warnings += item_warnings
		if !normalized || candidate.copied_bytes > state.limits.candidate_text_bytes ||
		   copied_bytes > state.limits.candidate_text_bytes - candidate.copied_bytes {
			rejected += 1
			continue
		}
		items[accepted] = candidate
		accepted += 1
		copied_bytes += candidate.copied_bytes
	}
	items = items[:accepted]
	if state.next_batch_id == completion.Batch_ID(0) ||
	   state.next_batch_generation == completion.Batch_Generation(0) {
		delete(items, allocator)
		return {}, false, completion_exchange_fail_request(state, .Arithmetic_Overflow)
	}
	batch := completion.Batch {
		id = state.next_batch_id,
		generation = state.next_batch_generation,
		request_id = state.request.id,
		request_generation = state.request.generation,
		scope = state.request.scope,
		request_cursor_byte = state.request.cursor_byte,
		query_range = state.request.query_range,
		disposition = .Incomplete if result.incomplete else .Complete,
		items = items,
		item_count = u16(accepted),
		rejected_item_count = u16(min(rejected, u32(max(u16)))),
		normalization_warning_count = u16(min(warnings, u32(max(u16)))),
		copied_bytes = copied_bytes,
	}
	if !completion.batch_is_valid(&batch, &state.request) {
		delete(items, allocator)
		return {}, false, completion_exchange_fail_request(state, .Protocol)
	}
	state.next_batch_id += 1
	state.next_batch_generation += 1
	state.request_state = .Completed
	state.deadline_ns = 0
	completion_exchange_release_body(state)
	state.latest_failure = {}
	return Completion_Batch_Owner{batch = batch, allocator = allocator}, true, {}
}

/* completion_batch_owner_close releases one normalized batch exactly once. */
completion_batch_owner_close :: proc(owner: ^Completion_Batch_Owner) -> bool {
	if owner == nil || owner.closed || owner.allocator.procedure == nil do return false
	if owner.batch.items != nil do delete(owner.batch.items, owner.allocator)
	owner^ = Completion_Batch_Owner{closed = true}
	return true
}

@(private = "file")
completion_result_from_json :: proc(value: json.Value) -> (Completion_Result_View, bool) {
	object, object_ok := value.(json.Object)
	if !object_ok do return {}, false
	result_value, result_present := object["result"]
	if !result_present do return {}, false
	#partial switch result in result_value {
	case json.Null:
		return {}, true
	case json.Array:
		return Completion_Result_View{items = result}, true
	case json.Object:
		items_value, items_present := result["items"]
		items, items_ok := items_value.(json.Array)
		if !items_present || !items_ok do return {}, false
		view := Completion_Result_View{items = items}
		if incomplete_value, present := result["isIncomplete"]; present {
			incomplete, ok := incomplete_value.(json.Boolean)
			if !ok do return {}, false
			view.incomplete = bool(incomplete)
		}
		if defaults_value, present := result["itemDefaults"]; present {
			defaults, ok := defaults_value.(json.Object)
			if !ok do return {}, false
			view.defaults = defaults
		}
		return view, true
	case:
		return {}, false
	}
}

@(private = "file")
completion_candidate_from_json :: proc(
	value: json.Value,
	defaults: json.Object,
	document_text: string,
	encoding: Position_Encoding,
	request: completion.Request,
	provider_order: u32,
) -> (completion.Candidate, bool, u32) {
	object, object_ok := value.(json.Object)
	if !object_ok do return {}, false, 0
	label_value, label_present := object["label"]
	label_string, label_ok := label_value.(json.String)
	if !label_present || !label_ok || len(label_string) == 0 || !utf8.valid_string(string(label_string)) {
		return {}, false, 0
	}
	label, copied := completion.text_copy(string(label_string))
	if !copied do return {}, false, 0
	candidate := completion.Candidate {
		id = completion.Candidate_ID(provider_order + 1),
		kind = .Textual,
		availability = .Available,
		label = label,
		provenance = {
			provider_id = request.scope.provider_id,
			provider_generation = request.scope.provider_generation,
			provider_order = provider_order,
		},
	}
	warnings := u32(0)
	if kind_value, present := object["kind"]; present {
		kind, ok := kind_value.(json.Integer)
		if ok {
			candidate.kind = completion_kind_from_lsp(i64(kind))
			if candidate.kind == .Invalid {
				candidate.kind = .Textual
				warnings += 1
			}
		} else {
			warnings += 1
		}
	}
	if deprecated_value, present := object["deprecated"]; present {
		if deprecated, ok := deprecated_value.(json.Boolean); ok && bool(deprecated) {
			candidate.availability = .Deprecated
		}
	}
	if tags_value, present := object["tags"]; present {
		if tags, ok := tags_value.(json.Array); ok {
			for tag in tags {
				if numeric, numeric_ok := tag.(json.Integer); numeric_ok && numeric == 1 {
					candidate.availability = .Deprecated
				}
			}
		}
	}
	if !completion_candidate_copy_optional_text(object, "filterText", &candidate.filter_text) ||
	   !completion_candidate_copy_optional_text(object, "sortText", &candidate.sort_text) ||
	   !completion_candidate_copy_optional_text(object, "insertText", &candidate.insertion_text) {
		return {}, false, warnings
	}
	if text_edit_text_value, present := object["textEditText"]; present {
		text_edit_text, ok := text_edit_text_value.(json.String)
		if !ok do return {}, false, warnings
		candidate.insertion_text, ok = completion.text_copy(string(text_edit_text))
		if !ok do return {}, false, warnings
	}
	if detail_value, present := object["detail"]; present {
		detail, ok := detail_value.(json.String)
		if !ok do return {}, false, warnings
		candidate.detail, ok = completion.detail_copy(string(detail))
		if !ok do return {}, false, warnings
	}
	if label_details_value, present := object["labelDetails"]; present {
		label_details, ok := label_details_value.(json.Object)
		if !ok do return {}, false, warnings
		if !completion_candidate_copy_optional_text(label_details, "detail", &candidate.label_detail) ||
		   !completion_candidate_copy_optional_text(label_details, "description", &candidate.description) {
			return {}, false, warnings
		}
	}
	if documentation_value, present := object["documentation"]; present {
		documentation, ok := completion_documentation_from_json(documentation_value)
		if !ok do return {}, false, warnings
		candidate.documentation, ok = completion.detail_copy(documentation.text)
		if !ok do return {}, false, warnings
		candidate.documentation_format = documentation.format
	}
	if data_value, present := object["data"]; present {
		data, marshal_error := json.marshal(data_value, {}, context.temp_allocator)
		if marshal_error != nil do return {}, false, warnings
		candidate.resolve_token, copied = completion.resolve_token_copy(string(data))
		if !copied do return {}, false, warnings
	}
	edit_value, has_edit := object["textEdit"]
	if has_edit {
		edit, new_text, edit_ok := completion_text_edit_from_json(edit_value, document_text, encoding)
		if !edit_ok do return {}, false, warnings
		candidate.primary_edit = edit
		candidate.has_primary_edit = true
		if new_text != "" {
			candidate.insertion_text, copied = completion.text_copy(new_text)
			if !copied do return {}, false, warnings
		}
	}
	if candidate.insertion_text.byte_count == 0 {
		candidate.insertion_text = candidate.label
	}
	if !has_edit && defaults != nil {
		if default_range_value, default_range_present := defaults["editRange"]; default_range_present {
			range, range_ok := completion_byte_range_from_json(default_range_value, document_text, encoding)
			if !range_ok do return {}, false, warnings
			candidate.primary_edit = {
				range = range,
				new_text = candidate.insertion_text,
			}
			candidate.has_primary_edit = true
		}
	}
	if additional_value, present := object["additionalTextEdits"]; present {
		additional, ok := additional_value.(json.Array)
		if !ok || len(additional) > completion.MAX_COMPLETION_ADDITIONAL_EDITS {
			return {}, false, warnings
		}
		for additional_edit_value, index in additional {
			edit, _, edit_ok := completion_text_edit_from_json(additional_edit_value, document_text, encoding)
			if !edit_ok do return {}, false, warnings
			candidate.additional_edits[index] = edit
		}
		candidate.additional_edit_count = u8(len(additional))
	}
	candidate.copied_bytes = completion_candidate_copied_bytes(&candidate)
	return candidate, completion.candidate_is_valid(&candidate, request.scope), warnings
}

@(private = "file")
completion_candidate_copy_optional_text :: proc(
	object: json.Object,
	field: string,
	destination: ^completion.Text,
) -> bool {
	value, present := object[field]
	if !present do return true
	text, ok := value.(json.String)
	if !ok || !utf8.valid_string(string(text)) do return false
	destination^, ok = completion.text_copy(string(text))
	return ok
}

@(private = "file")
completion_documentation_from_json :: proc(value: json.Value) -> (Completion_Documentation_View, bool) {
	#partial switch documentation in value {
	case json.String:
		return {text = string(documentation), format = .Plain_Text}, true
	case json.Object:
		kind_value, kind_present := documentation["kind"]
		text_value, text_present := documentation["value"]
		kind, kind_ok := kind_value.(json.String)
		text, text_ok := text_value.(json.String)
		if !kind_present || !text_present || !kind_ok || !text_ok do return {}, false
		format := completion.Documentation_Format.Plain_Text
		if string(kind) == "markdown" {
			format = .Markdown
		} else if string(kind) != "plaintext" {
			return {}, false
		}
		return {text = string(text), format = format}, true
	case:
		return {}, false
	}
}

@(private = "file")
completion_text_edit_from_json :: proc(
	value: json.Value,
	document_text: string,
	encoding: Position_Encoding,
) -> (completion.Text_Edit, string, bool) {
	object, object_ok := value.(json.Object)
	if !object_ok do return {}, "", false
	range_value, range_present := object["range"]
	new_text := ""
	if new_text_value, present := object["newText"]; present {
		text, ok := new_text_value.(json.String)
		if !ok do return {}, "", false
		new_text = string(text)
	}
	if !range_present {
		if replace_value, replace_present := object["replace"]; replace_present {
			range_value = replace_value
			range_present = true
		} else if insert_value, insert_present := object["insert"]; insert_present {
			range_value = insert_value
			range_present = true
		}
	}
	if !range_present do return {}, "", false
	range, range_ok := completion_byte_range_from_json(range_value, document_text, encoding)
	if !range_ok do return {}, "", false
	copied_text, copied := completion.text_copy(new_text)
	if !copied do return {}, "", false
	return completion.Text_Edit{range = range, new_text = copied_text}, new_text, true
}

@(private = "file")
completion_byte_range_from_json :: proc(
	value: json.Value,
	document_text: string,
	encoding: Position_Encoding,
) -> (completion.Byte_Range, bool) {
	object, object_ok := value.(json.Object)
	if !object_ok do return {}, false
	if replace_value, replace_present := object["replace"]; replace_present {
		object, object_ok = replace_value.(json.Object)
		if !object_ok do return {}, false
	} else if insert_value, insert_present := object["insert"]; insert_present {
		object, object_ok = insert_value.(json.Object)
		if !object_ok do return {}, false
	}
	start_value, start_present := object["start"]
	end_value, end_present := object["end"]
	start, start_ok := lsp_position_from_json(start_value)
	end, end_ok := lsp_position_from_json(end_value)
	if !start_present || !end_present || !start_ok || !end_ok do return {}, false
	start_byte, start_converted, _ := position_to_byte_offset(document_text, start, encoding)
	end_byte, end_converted, _ := position_to_byte_offset(document_text, end, encoding)
	if !start_converted || !end_converted || start_byte > end_byte do return {}, false
	return {start = start_byte, end = end_byte}, true
}

@(private = "file")
completion_kind_from_lsp :: proc(kind: i64) -> completion.Candidate_Kind {
	switch kind {
	case 1: return .Textual
	case 2, 3, 23: return .Callable
	case 4, 15: return .Construct
	case 5, 10: return .Field
	case 6, 11, 12, 16, 20, 21: return .Value
	case 7, 8, 13, 22, 25: return .Type
	case 9, 17, 18, 19: return .Module
	case 14, 24: return .Keyword
	case: return .Invalid
	}
}

@(private = "file")
completion_candidate_copied_bytes :: proc(candidate: ^completion.Candidate) -> u64 {
	if candidate == nil do return 0
	result := u64(candidate.label.byte_count) + u64(candidate.label_detail.byte_count) +
		u64(candidate.description.byte_count) + u64(candidate.filter_text.byte_count) +
		u64(candidate.sort_text.byte_count) + u64(candidate.insertion_text.byte_count) +
		u64(candidate.detail.byte_count) + u64(candidate.documentation.byte_count) +
		u64(candidate.resolve_token.byte_count) + u64(candidate.primary_edit.new_text.byte_count)
	for index in 0 ..< int(candidate.additional_edit_count) {
		result += u64(candidate.additional_edits[index].new_text.byte_count)
	}
	return result
}
