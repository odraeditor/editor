// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service_workflow

import "../editor"
import "../language"
import "../language_service"
import "../result_set"
import "core:fmt"

/* Language_Intelligence_Target maps one already-owned document URI into navigation state. */
Language_Intelligence_Target :: struct {
	uri:       string,
	buffer_id: editor.Buffer_ID,
	revision:  editor.Revision,
}

/* Language_Intelligence_Result_Config selects one replaceable shared result set. */
Language_Intelligence_Result_Config :: struct {
	set_id:              result_set.Result_Set_ID,
	expected_generation: result_set.Result_Set_Generation,
	source_id:           result_set.Source_ID,
	targets:             []Language_Intelligence_Target,
}

/* Language_Intelligence_Publish_Results copies navigation into the common result owner. */
Language_Intelligence_Publish_Results :: proc(
	registry: ^result_set.Registry,
	intelligence: ^language_service.Intelligence_Result,
	config: Language_Intelligence_Result_Config,
) -> (result_set.Result, bool, result_set.Failure) {
	view, viewed := language_service.intelligence_result_view(intelligence)
	if !viewed || registry == nil || config.set_id == result_set.Result_Set_ID(0) ||
	   config.source_id == result_set.Source_ID(0) || len(config.targets) == 0 ||
	   (view.descriptor.kind != .Definition && view.descriptor.kind != .References &&
	    view.descriptor.kind != .Document_Symbols && view.descriptor.kind != .Workspace_Symbols) {
		return {}, false, result_set.Failure{code = .Invalid_Publication, set_id = config.set_id}
	}
	location_count := len(view.locations)
	if view.descriptor.kind == .Document_Symbols || view.descriptor.kind == .Workspace_Symbols {
		location_count = len(view.symbols)
	}
	if location_count > int(result_set.MAX_RESULT_LOCATIONS) || len(config.targets) > int(result_set.MAX_RESULT_GROUPS) {
		return {}, false, result_set.Failure {
			code = .Location_Limit,
			set_id = config.set_id,
			limit = u64(result_set.MAX_RESULT_LOCATIONS),
			actual = u64(location_count),
		}
	}
	definitions, definitions_error := make([]result_set.Location_Definition, location_count, context.temp_allocator)
	if definitions_error != nil {
		return {}, false, result_set.Failure{code = .Persistent_Memory_Limit, set_id = config.set_id}
	}
	defer delete(definitions, context.temp_allocator)
	groups, groups_error := make([]result_set.Group_Definition, len(config.targets), context.temp_allocator)
	if groups_error != nil {
		return {}, false, result_set.Failure{code = .Persistent_Memory_Limit, set_id = config.set_id}
	}
	defer delete(groups, context.temp_allocator)
	annotations, annotations_error := make([dynamic]string, 0, location_count, context.temp_allocator)
	if annotations_error != nil {
		return {}, false, result_set.Failure{code = .Persistent_Memory_Limit, set_id = config.set_id}
	}
	defer {
		for annotation in annotations do delete(annotation, context.temp_allocator)
		delete(annotations)
	}
	for target, index in config.targets {
		if target.uri == "" || target.buffer_id == editor.Buffer_ID(0) || target.revision == editor.Revision(0) {
			return {}, false, result_set.Failure{code = .Invalid_Publication, set_id = config.set_id}
		}
		groups[index] = {id = result_set.Group_ID(index + 1), label = target.uri}
	}
	accepted := 0
	for ordinal in 0 ..< location_count {
		location := language_service.Intelligence_Location{}
		preview := "Language location"
		source_identity := u64(ordinal + 1)
		if view.descriptor.kind == .Document_Symbols || view.descriptor.kind == .Workspace_Symbols {
			symbol := view.symbols[ordinal]
			location = symbol.location
			preview = language_service.intelligence_text_string(&symbol.name)
			source_identity = symbol.id
		} else {
			location = view.locations[ordinal]
			source_identity = location.id
		}
		uri := language_service.intelligence_uri_string(&location.uri)
		target_index, target_found := language_intelligence_target_index(config.targets, uri)
		if !target_found || !location.range.bytes_present do continue
		annotation := fmt.aprintf(
			"%d:%d",
			location.range.start.line + 1,
			location.range.start.character + 1,
			allocator = context.temp_allocator,
		)
		if annotation == "" {
			return {}, false, result_set.Failure{code = .Persistent_Memory_Limit, set_id = config.set_id}
		}
		_, append_error := append(&annotations, annotation)
		if append_error != nil {
			delete(annotation, context.temp_allocator)
			return {}, false, result_set.Failure{code = .Persistent_Memory_Limit, set_id = config.set_id}
		}
		target := config.targets[target_index]
		definitions[accepted] = {
			id = result_set.Location_ID(source_identity),
			group_id = result_set.Group_ID(target_index + 1),
			buffer_id = target.buffer_id,
			revision = target.revision,
			start = editor.Byte_Offset(location.range.start_byte),
			end = editor.Byte_Offset(location.range.end_byte),
			source_identity = source_identity,
			preview = preview,
			annotation = annotation,
		}
		accepted += 1
	}
	if accepted == 0 && location_count > 0 {
		return {}, false, result_set.Failure{code = .Invalid_Location, set_id = config.set_id}
	}
	return result_set.registry_publish(registry, result_set.Publication {
		set_id = config.set_id,
		expected_generation = config.expected_generation,
		source = {
			id = config.source_id,
			generation = result_set.Source_Generation(view.descriptor.result_generation),
			kind = .Language_Symbols if view.descriptor.kind == .Document_Symbols ||
				view.descriptor.kind == .Workspace_Symbols else .Language_Navigation,
		},
		metadata = {
			descriptor = "Language symbols" if view.descriptor.kind == .Document_Symbols ||
				view.descriptor.kind == .Workspace_Symbols else "Language locations",
			values = [8]u64 {
				u64(view.descriptor.request_id),
				u64(view.descriptor.request_generation),
				u64(view.descriptor.result_generation),
				u64(view.descriptor.scope.service_generation),
				0, 0, 0, 0,
			},
		},
		completeness = .Complete,
		edit_capability = .Read_Only,
		locations = definitions[:accepted],
		groups = groups,
	})
}

/* Language_Intelligence_Popup_Text formats hover or signature data into caller storage. */
Language_Intelligence_Popup_Text :: proc(
	intelligence: ^language_service.Intelligence_Result,
	storage: []u8,
) -> (string, bool) {
	view, viewed := language_service.intelligence_result_view(intelligence)
	if !viewed || len(storage) == 0 do return "", false
	cursor := 0
	if view.descriptor.kind == .Hover {
		for &block in view.hover {
			if !language_intelligence_popup_append(storage, &cursor, language_service.intelligence_text_string(&block.text)) do return "", false
		}
	} else if view.descriptor.kind == .Signature_Help {
		for &signature in view.signatures {
			if !language_intelligence_popup_append(storage, &cursor, language_service.intelligence_text_string(&signature.label)) ||
			   !language_intelligence_popup_append(storage, &cursor, language_service.intelligence_text_string(&signature.documentation)) {
				return "", false
			}
		}
	} else {
		return "", false
	}
	return string(storage[:cursor]), cursor > 0
}

/* Language_Intelligence_Semantic_Projection maps negotiated tokens into syntax roles. */
Language_Intelligence_Semantic_Projection :: proc(
	intelligence: ^language_service.Intelligence_Result,
	capabilities: language_service.Capability_Values,
	snapshot: language.Syntax_Snapshot,
	storage: []language.Syntax_Span,
) -> (language.Syntax_Snapshot, []language.Syntax_Span, bool) {
	view, viewed := language_service.intelligence_result_view(intelligence)
	if !viewed || (view.descriptor.kind != .Semantic_Tokens_Full &&
	   view.descriptor.kind != .Semantic_Tokens_Delta) || len(view.tokens) > len(storage) ||
	   snapshot.generation == language.Syntax_Snapshot_Generation(0) ||
	   u64(snapshot.buffer_id) != view.descriptor.scope.buffer_identity ||
	   u64(snapshot.source_revision) != view.descriptor.scope.canonical_revision {
		return {}, nil, false
	}
	for token, index in view.tokens {
		role, mapped := language_intelligence_semantic_role(capabilities.semantic_tokens, token.token_type)
		if !mapped do return {}, nil, false
		storage[index] = {
			start = editor.Byte_Offset(token.start_byte),
			end = editor.Byte_Offset(token.end_byte),
			role = role,
			precedence = u16(min(token.provider_order + 1, u32(max(u16)))),
			provider = snapshot.provider,
			source_revision = snapshot.source_revision,
		}
	}
	result_snapshot := snapshot
	result_snapshot.span_count = u32(len(view.tokens))
	result_snapshot.usage.spans = u32(len(view.tokens))
	result_snapshot.usage.retained_span_bytes = u64(len(view.tokens)) * u64(size_of(language.Syntax_Span))
	return result_snapshot, storage[:len(view.tokens)], true
}

@(private = "file")
language_intelligence_popup_append :: proc(storage: []u8, cursor: ^int, value: string) -> bool {
	if cursor == nil do return false
	if value == "" do return true
	separator := 0
	if cursor^ > 0 do separator = 1
	if separator + len(value) > len(storage) - cursor^ do return false
	if separator == 1 {
		storage[cursor^] = '\n'
		cursor^ += 1
	}
	copy(storage[cursor^:cursor^ + len(value)], transmute([]u8)value)
	cursor^ += len(value)
	return true
}

@(private = "file")
language_intelligence_target_index :: proc(
	targets: []Language_Intelligence_Target,
	uri: string,
) -> (int, bool) {
	for target, index in targets do if target.uri == uri do return index, true
	return 0, false
}

@(private = "file")
language_intelligence_semantic_role :: proc(
	capability: language_service.Semantic_Token_Capability_Values,
	index: u32,
) -> (language.Syntax_Role, bool) {
	if index >= u32(capability.token_count) do return .Invalid, false
	name := capability.token_types[index]
	value := string(name.bytes[:int(name.length)])
	switch value {
	case "namespace", "type", "class", "enum", "interface", "struct", "typeParameter":
		return .Type, true
	case "parameter":
		return .Variable_Parameter, true
	case "variable", "property", "enumMember", "event":
		return .Variable, true
	case "function", "method", "macro":
		return .Function, true
	case "keyword", "modifier":
		return .Keyword, true
	case "comment":
		return .Comment, true
	case "string", "regexp":
		return .String, true
	case "number":
		return .Number, true
	case "operator", "decorator":
		return .Operator, true
	}
	return .Invalid, false
}
