// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import document "../document"
import "../editor"
import "../transaction"
import "base:runtime"
import json "core:encoding/json"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"

/* workspace_edit_normalize_rename validates one rename response as a complete checked proposal. */
workspace_edit_normalize_rename :: proc(
	edit_context: Workspace_Edit_Context,
	response: []u8,
	allocator := context.allocator,
) -> (Workspace_Edit_Proposal, bool, Workspace_Edit_Failure) {
	root, value, parsed, failure := workspace_edit_response_result(response)
	if !parsed do return {}, false, failure
	defer json.destroy_value(root, context.temp_allocator)
	return workspace_edit_normalize(edit_context, value, .Rename, allocator)
}

/* workspace_edit_normalize_code_action validates one selected action's edit proposal. */
workspace_edit_normalize_code_action :: proc(
	edit_context: Workspace_Edit_Context,
	response: []u8,
	action_index: u32,
	allocator := context.allocator,
) -> (Workspace_Edit_Proposal, bool, Workspace_Edit_Failure) {
	root, value, parsed, failure := workspace_edit_response_result(response)
	if !parsed do return {}, false, failure
	defer json.destroy_value(root, context.temp_allocator)
	actions, actions_ok := value.(json.Array)
	if !actions_ok || int(action_index) >= len(actions) {
		return {}, false, Workspace_Edit_Failure{code = .Malformed_Response, index = action_index}
	}
	action, action_ok := actions[action_index].(json.Object)
	if !action_ok do return {}, false, Workspace_Edit_Failure{code = .Malformed_Response, index = action_index}
	edit, present := action["edit"]
	if !present do return {}, false, Workspace_Edit_Failure{code = .Unsupported_Operation, index = action_index}
	return workspace_edit_normalize(edit_context, edit, .Code_Action, allocator)
}

/* workspace_edit_normalize accepts only copied, bounded text and local file proposals. */
workspace_edit_normalize :: proc(
	edit_context: Workspace_Edit_Context,
	value: json.Value,
	origin: Workspace_Edit_Origin,
	allocator := context.allocator,
) -> (Workspace_Edit_Proposal, bool, Workspace_Edit_Failure) {
	if !workspace_edit_context_valid(edit_context) || origin == .Invalid || allocator.procedure == nil {
		return {}, false, Workspace_Edit_Failure{code = .Invalid_Input}
	}
	object, object_ok := value.(json.Object)
	if !object_ok do return {}, false, Workspace_Edit_Failure{code = .Invalid_Workspace_Edit}
	changes, has_changes := object["changes"]
	document_changes, has_document_changes := object["documentChanges"]
	if has_changes == has_document_changes {
		return {}, false, Workspace_Edit_Failure{code = .Invalid_Workspace_Edit}
	}
	state, opened := workspace_edit_state_open(origin, allocator)
	if !opened do return {}, false, Workspace_Edit_Failure{code = .Allocation}
	accepted := true
	failure := Workspace_Edit_Failure{}
	if has_changes {
		change_map, map_ok := changes.(json.Object)
		if !map_ok {
			workspace_edit_state_destroy(state)
			return {}, false, Workspace_Edit_Failure{code = .Invalid_Workspace_Edit}
		}
		for uri, edit_list in change_map {
			target := workspace_document_find(edit_context.documents, uri)
			if target == nil {
				accepted = false
				failure = {code = .Invalid_Document}
				break
			}
		accepted, failure = workspace_text_edits_append(state, edit_context, target, edit_list, false, 0)
			if !accepted do break
		}
	} else {
		entries, entries_ok := document_changes.(json.Array)
		if !entries_ok {
			workspace_edit_state_destroy(state)
			return {}, false, Workspace_Edit_Failure{code = .Invalid_Workspace_Edit}
		}
		for entry, index in entries {
			entry_object, entry_ok := entry.(json.Object)
			if !entry_ok {
				accepted = false
				failure = {code = .Invalid_Workspace_Edit, index = u32(index)}
				break
			}
			if text_document, text_present := entry_object["textDocument"]; text_present {
				document_object, document_ok := text_document.(json.Object)
				uri_value, uri_present := document_object["uri"]
				version_value, version_present := document_object["version"]
				edits_value, edits_present := entry_object["edits"]
				uri, uri_ok := uri_value.(json.String)
				if !document_ok || !uri_present || !version_present || !edits_present || !uri_ok {
					accepted = false
					failure = {code = .Invalid_Document, index = u32(index)}
					break
				}
				target := workspace_document_find(edit_context.documents, string(uri))
				if target == nil {
					accepted = false
					failure = {code = .Invalid_Document, index = u32(index)}
					break
				}
				has_version := false
				version := i64(0)
				#partial switch version_payload in version_value {
				case json.Integer:
					has_version = true
					version = i64(version_payload)
				case json.Null:
				case:
					accepted = false
					failure = {code = .Invalid_Document, index = u32(index)}
				}
				if !accepted do break
				accepted, failure = workspace_text_edits_append(state, edit_context, target, edits_value, has_version, version)
				if !accepted {
					failure.index = u32(index)
					break
				}
			} else {
				accepted, failure = workspace_file_operation_append(state, edit_context, entry_object)
				if !accepted {
					failure.index = u32(index)
					break
				}
			}
		}
	}
	if !accepted {
		workspace_edit_state_destroy(state)
		return {}, false, failure
	}
	accepted, failure = workspace_edit_finalize(state, edit_context)
	if !accepted {
		workspace_edit_state_destroy(state)
		return {}, false, failure
	}
	command := "rename-symbol" if origin == .Rename else "apply-code-action"
	return {
		edit = {
			origin = {kind = .Language_Tool, descriptor = "language-service-workspace-edit"},
			command = command,
			snapshots = state.snapshots[:],
			edits = state.edits[:],
		},
		operations = state.operations[:],
		preview = state.preview,
		state = state,
	}, true, {}
}

@(private)
workspace_edit_response_result :: proc(response: []u8) -> (json.Value, json.Value, bool, Workspace_Edit_Failure) {
	value, parse_error := json.parse_bytes(response, .JSON, true, context.temp_allocator)
	if parse_error != .None do return {}, {}, false, Workspace_Edit_Failure{code = .Malformed_Response}
	object, object_ok := value.(json.Object)
	if !object_ok {
		json.destroy_value(value, context.temp_allocator)
		return {}, {}, false, Workspace_Edit_Failure{code = .Malformed_Response}
	}
	result, present := object["result"]
	if !present {
		json.destroy_value(value, context.temp_allocator)
		return {}, {}, false, Workspace_Edit_Failure{code = .Malformed_Response}
	}
	return value, result, true, {}
}

@(private)
workspace_edit_state_open :: proc(origin: Workspace_Edit_Origin, allocator: runtime.Allocator) -> (^Workspace_Edit_Proposal_State, bool) {
	state, allocation_error := new(Workspace_Edit_Proposal_State, allocator)
	if allocation_error != nil do return nil, false
	state.allocator = allocator
	state.preview.origin = origin
	state.snapshots, allocation_error = make([dynamic]transaction.Proposal_Snapshot, 0, 4, allocator)
	if allocation_error == nil do state.edits, allocation_error = make([dynamic]transaction.Proposal_Edit, 0, 4, allocator)
	if allocation_error == nil do state.splices, allocation_error = make([dynamic][dynamic]transaction.Base_Splice, 0, 4, allocator)
	if allocation_error == nil do state.replacements, allocation_error = make([dynamic]string, 0, 8, allocator)
	if allocation_error == nil do state.operations, allocation_error = make([dynamic]Workspace_File_Operation, 0, 4, allocator)
	if allocation_error == nil do state.owned_paths, allocation_error = make([dynamic]string, 0, 8, allocator)
	if allocation_error != nil {
		workspace_edit_state_destroy(state)
		return nil, false
	}
	return state, true
}

@(private)
workspace_text_edits_append :: proc(
	state: ^Workspace_Edit_Proposal_State,
	edit_context: Workspace_Edit_Context,
	target: ^Workspace_Document_Target,
	value: json.Value,
	has_version: bool,
	version: i64,
) -> (bool, Workspace_Edit_Failure) {
	if !workspace_document_valid(target, edit_context) do return false, Workspace_Edit_Failure{code = .Invalid_Document}
	if has_version && (!target.has_protocol_version || version != target.protocol_version) {
		return false, Workspace_Edit_Failure{code = .Version_Mismatch}
	}
	stats, stats_ok, _ := editor.buffer_stats(target.buffer)
	if !stats_ok || stats.buffer_id != target.buffer_id || stats.revision != target.base_revision ||
	   stats.text_bytes != u64(len(target.text)) {
		return false, Workspace_Edit_Failure{code = .Stale_Revision}
	}
	items, items_ok := value.(json.Array)
	if !items_ok do return false, Workspace_Edit_Failure{code = .Invalid_Workspace_Edit}
	if u64(state.preview.text_edits) + u64(len(items)) > u64(edit_context.limits.text_edits) {
		return false, Workspace_Edit_Failure{code = .Resource_Limit, resource = .Text_Edit, limit = u64(edit_context.limits.text_edits), actual = u64(state.preview.text_edits) + u64(len(items))}
	}
	participant := workspace_participant_find(state, target.buffer_id)
	if participant < 0 {
		if u64(len(state.snapshots)) + 1 > u64(edit_context.limits.documents) {
			return false, Workspace_Edit_Failure{code = .Resource_Limit, resource = .Document, limit = u64(edit_context.limits.documents), actual = u64(len(state.snapshots)) + 1}
		}
		_, append_error := append(&state.snapshots, transaction.Proposal_Snapshot {
			buffer = target.buffer,
			buffer_id = target.buffer_id,
			base_revision = target.base_revision,
		})
		if append_error != nil do return false, Workspace_Edit_Failure{code = .Allocation}
		batch, allocation_error := make([dynamic]transaction.Base_Splice, 0, len(items), state.allocator)
		if allocation_error != nil do return false, Workspace_Edit_Failure{code = .Allocation}
		_, append_error = append(&state.splices, batch)
		if append_error != nil {
			delete(batch)
			return false, Workspace_Edit_Failure{code = .Allocation}
		}
		participant = len(state.snapshots) - 1
	}
	batch := &state.splices[participant]
	for item in items {
		item_object, item_ok := item.(json.Object)
		if !item_ok do return false, Workspace_Edit_Failure{code = .Invalid_Workspace_Edit}
		range_value, range_present := item_object["range"]
		new_text_value, text_present := item_object["newText"]
		new_text, text_ok := new_text_value.(json.String)
		if !range_present || !text_present || !text_ok || !utf8.valid_string(string(new_text)) {
			return false, Workspace_Edit_Failure{code = .Invalid_Workspace_Edit}
		}
		start, end, range_ok := workspace_edit_range(target.text, range_value, edit_context.position_encoding)
		if !range_ok do return false, Workspace_Edit_Failure{code = .Invalid_Workspace_Edit}
		replacement_bytes := state.preview.replacement_bytes + u64(len(new_text))
		if replacement_bytes > edit_context.limits.replacement_bytes {
			return false, Workspace_Edit_Failure{code = .Resource_Limit, resource = .Replacement_Bytes, limit = edit_context.limits.replacement_bytes, actual = replacement_bytes}
		}
		replacement, allocation_error := strings.clone(string(new_text), state.allocator)
		if allocation_error != nil do return false, Workspace_Edit_Failure{code = .Allocation}
		_, append_error := append(&state.replacements, replacement)
		if append_error != nil {
			delete(replacement, state.allocator)
			return false, Workspace_Edit_Failure{code = .Allocation}
		}
		start_position, start_ok := editor.position_make(target.buffer_id, target.base_revision, editor.Byte_Offset(start))
		end_position, end_ok := editor.position_make(target.buffer_id, target.base_revision, editor.Byte_Offset(end))
		if !start_ok || !end_ok do return false, Workspace_Edit_Failure{code = .Invalid_Document}
		_, append_error = append(batch, transaction.Base_Splice {start = start_position, end = end_position, replacement = replacement})
		if append_error != nil do return false, Workspace_Edit_Failure{code = .Allocation}
		state.preview.text_edits += 1
		state.preview.replacement_bytes = replacement_bytes
	}
	return true, {}
}

@(private)
workspace_file_operation_append :: proc(
	state: ^Workspace_Edit_Proposal_State,
	edit_context: Workspace_Edit_Context,
	object: json.Object,
) -> (bool, Workspace_Edit_Failure) {
	if u64(len(state.operations)) >= u64(edit_context.limits.file_operations) {
		return false, Workspace_Edit_Failure{code = .Resource_Limit, resource = .File_Operation, limit = u64(edit_context.limits.file_operations), actual = u64(len(state.operations)) + 1}
	}
	kind_value, kind_present := object["kind"]
	kind, kind_ok := kind_value.(json.String)
	if !kind_present || !kind_ok do return false, Workspace_Edit_Failure{code = .Unsupported_Operation}
	operation := Workspace_File_Operation{}
	switch string(kind) {
	case "create":
		uri, uri_ok := workspace_edit_string_field(object, "uri")
		if !uri_ok || !workspace_edit_options_safe(object, false) do return false, Workspace_Edit_Failure{code = .Unsupported_Operation}
		destination := workspace_resource_find(edit_context, uri)
		if destination == nil || destination.exists_on_disk || destination.kind != .Regular_File {
			return false, Workspace_Edit_Failure{code = .Filesystem_Preflight}
		}
		operation.kind = .Create
		destination_path, ok, failure := workspace_path_clone(state, destination.path)
		if !ok do return false, failure
		operation.destination_path = destination_path
		state.preview.created_files += 1
	case "rename":
		old_uri, old_ok := workspace_edit_string_field(object, "oldUri")
		new_uri, new_ok := workspace_edit_string_field(object, "newUri")
		if !old_ok || !new_ok || !workspace_edit_options_safe(object, false) do return false, Workspace_Edit_Failure{code = .Unsupported_Operation}
		source := workspace_resource_find(edit_context, old_uri)
		destination := workspace_resource_find(edit_context, new_uri)
		if source == nil || destination == nil || !source.exists_on_disk || destination.exists_on_disk ||
		   source.kind != .Regular_File || destination.kind != .Regular_File {
			return false, Workspace_Edit_Failure{code = .Filesystem_Preflight}
		}
		operation.kind = .Rename
		source_path, ok, failure := workspace_path_clone(state, source.path)
		if !ok do return false, failure
		destination_path: string
		destination_path, ok, failure = workspace_path_clone(state, destination.path)
		if !ok do return false, failure
		operation.source_path = source_path
		operation.destination_path = destination_path
		operation.source_inode = source.disk_inode
		operation.source_kind = source.kind
		state.preview.renamed_files += 1
	case "delete":
		uri, uri_ok := workspace_edit_string_field(object, "uri")
		if !uri_ok || !workspace_edit_options_safe(object, true) do return false, Workspace_Edit_Failure{code = .Unsupported_Operation}
		source := workspace_resource_find(edit_context, uri)
		if source == nil || !source.exists_on_disk || source.kind != .Regular_File {
			return false, Workspace_Edit_Failure{code = .Filesystem_Preflight}
		}
		operation.kind = .Delete
		source_path, ok, failure := workspace_path_clone(state, source.path)
		if !ok do return false, failure
		operation.source_path = source_path
		operation.source_inode = source.disk_inode
		operation.source_kind = source.kind
		state.preview.deleted_files += 1
	case:
		return false, Workspace_Edit_Failure{code = .Unsupported_Operation}
	}
	_, append_error := append(&state.operations, operation)
	if append_error != nil do return false, Workspace_Edit_Failure{code = .Allocation}
	return true, {}
}

@(private)
workspace_edit_finalize :: proc(
	state: ^Workspace_Edit_Proposal_State,
	edit_context: Workspace_Edit_Context,
) -> (bool, Workspace_Edit_Failure) {
	for index in 0..<len(state.splices) {
		batch := &state.splices[index]
		slice.sort_by(batch[:], workspace_splice_less)
		for edit_index in 1..<len(batch) {
			previous := batch[edit_index - 1]
			current := batch[edit_index]
			if current.start.byte_offset < previous.end.byte_offset ||
			   (current.start.byte_offset == previous.start.byte_offset && current.end.byte_offset == previous.end.byte_offset) {
				return false, Workspace_Edit_Failure{code = .Overlapping_Edit, resource = .Text_Edit, index = u32(edit_index)}
			}
		}
		_, append_error := append(&state.edits, transaction.Proposal_Edit {
			buffer_id = state.snapshots[index].buffer_id,
			base_revision = state.snapshots[index].base_revision,
			batch = batch[:],
		})
		if append_error != nil do return false, Workspace_Edit_Failure{code = .Allocation}
	}
	for operation, index in state.operations {
		for previous in state.operations[:index] {
			if workspace_operations_conflict(previous, operation) {
				return false, Workspace_Edit_Failure{code = .Duplicate_Resource, resource = .File_Operation, index = u32(index)}
			}
		}
	}
	state.preview.documents = u32(len(state.snapshots))
	retained := u64(cap(state.snapshots)) * u64(size_of(transaction.Proposal_Snapshot)) +
		u64(cap(state.edits)) * u64(size_of(transaction.Proposal_Edit)) +
		u64(cap(state.operations)) * u64(size_of(Workspace_File_Operation)) + state.preview.replacement_bytes
	if retained > edit_context.limits.retained_bytes {
		return false, Workspace_Edit_Failure{code = .Resource_Limit, resource = .Retained_Bytes, limit = edit_context.limits.retained_bytes, actual = retained}
	}
	if len(state.snapshots) == 0 && len(state.operations) == 0 {
		return false, Workspace_Edit_Failure{code = .Invalid_Workspace_Edit}
	}
	return true, {}
}

@(private)
workspace_edit_context_valid :: proc(edit_context: Workspace_Edit_Context) -> bool {
	if !edit_context.project_trusted || edit_context.membership == "" || edit_context.root == "" ||
	   edit_context.position_encoding == .Invalid || !workspace_edit_limits_valid(edit_context.limits) ||
	   len(edit_context.documents) > int(edit_context.limits.documents) ||
	   len(edit_context.resources) > MAX_WORKSPACE_EDIT_OPERATIONS {
		return false
	}
	normalized: document.Normalized_Path
	ok, _ := document.path_normalize(edit_context.root, &normalized, context.temp_allocator)
	return ok && document.normalized_path_text(&normalized) == edit_context.root
}

@(private)
workspace_document_valid :: proc(target: ^Workspace_Document_Target, edit_context: Workspace_Edit_Context) -> bool {
	return target != nil && target.buffer != nil && target.buffer_id != editor.Buffer_ID(0) &&
		len(target.uri) > 0 && len(target.uri) <= MAX_WORKSPACE_EDIT_URI_BYTES && utf8.valid_string(target.uri) &&
		utf8.valid_string(target.text) && workspace_path_in_root(target.path, edit_context.root)
}

@(private)
workspace_document_find :: proc(targets: []Workspace_Document_Target, uri: string) -> ^Workspace_Document_Target {
	for index in 0..<len(targets) do if targets[index].uri == uri do return &targets[index]
	return nil
}

@(private)
workspace_resource_find :: proc(edit_context: Workspace_Edit_Context, uri: string) -> ^Workspace_Resource_Target {
	for index in 0..<len(edit_context.resources) {
		target := &edit_context.resources[index]
		if target.uri == uri && workspace_path_in_root(target.path, edit_context.root) do return target
	}
	return nil
}

@(private)
workspace_path_in_root :: proc(path, root: string) -> bool {
	if len(path) == 0 || len(path) > MAX_WORKSPACE_EDIT_PATH_BYTES || !utf8.valid_string(path) do return false
	normalized: document.Normalized_Path
	ok, _ := document.path_normalize(path, &normalized, context.temp_allocator)
	if !ok do return false
	value := document.normalized_path_text(&normalized)
	return value == path && (value == root ||
		(len(value) > len(root) && strings.has_prefix(value, root) && value[len(root)] == '/'))
}

@(private)
workspace_participant_find :: proc(state: ^Workspace_Edit_Proposal_State, buffer_id: editor.Buffer_ID) -> int {
	for snapshot, index in state.snapshots do if snapshot.buffer_id == buffer_id do return index
	return -1
}

@(private)
workspace_edit_range :: proc(text: string, value: json.Value, encoding: Position_Encoding) -> (u64, u64, bool) {
	object, object_ok := value.(json.Object)
	if !object_ok do return 0, 0, false
	start_value, start_present := object["start"]
	end_value, end_present := object["end"]
	if !start_present || !end_present do return 0, 0, false
	start_position, start_ok := lsp_position_from_json(start_value)
	end_position, end_ok := lsp_position_from_json(end_value)
	if !start_ok || !end_ok do return 0, 0, false
	start, start_converted, _ := position_to_byte_offset(text, start_position, encoding)
	end, end_converted, _ := position_to_byte_offset(text, end_position, encoding)
	return start, end, start_converted && end_converted && start <= end
}

@(private)
workspace_edit_string_field :: proc(object: json.Object, name: string) -> (string, bool) {
	value, present := object[name]
	text, ok := value.(json.String)
	return string(text), present && ok && len(text) > 0 && utf8.valid_string(string(text))
}

@(private)
workspace_edit_options_safe :: proc(object: json.Object, deleting: bool) -> bool {
	value, present := object["options"]
	if !present do return true
	options, options_ok := value.(json.Object)
	if !options_ok do return false
	fields := [?]string{"overwrite", "ignoreIfExists", "ignoreIfNotExists", "recursive"}
	for field in fields {
		candidate, field_present := options[field]
		if !field_present do continue
		flag, flag_ok := candidate.(json.Boolean)
		if !flag_ok || bool(flag) do return false
		if field == "recursive" && !deleting do return false
	}
	return true
}

@(private)
workspace_path_clone :: proc(state: ^Workspace_Edit_Proposal_State, value: string) -> (string, bool, Workspace_Edit_Failure) {
	path, allocation_error := strings.clone(value, state.allocator)
	if allocation_error != nil do return "", false, Workspace_Edit_Failure{code = .Allocation}
	_, append_error := append(&state.owned_paths, path)
	if append_error != nil {
		delete(path, state.allocator)
		return "", false, Workspace_Edit_Failure{code = .Allocation}
	}
	return path, true, {}
}

@(private)
workspace_splice_less :: proc(left, right: transaction.Base_Splice) -> bool {
	if left.start.byte_offset != right.start.byte_offset do return left.start.byte_offset < right.start.byte_offset
	return left.end.byte_offset < right.end.byte_offset
}

@(private)
workspace_operations_conflict :: proc(left, right: Workspace_File_Operation) -> bool {
	return (left.source_path != "" && (left.source_path == right.source_path || left.source_path == right.destination_path)) ||
		(left.destination_path != "" && (left.destination_path == right.source_path || left.destination_path == right.destination_path))
}
