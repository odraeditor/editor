// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_computation

import "core:slice"
import "core:unicode/utf8"

/* MAX_SOURCE_EDIT_BYTES bounds one focused source body. */
MAX_SOURCE_EDIT_BYTES :: u64(16 * 1_024 * 1_024)
/* MAX_NOWEB_DEFINITIONS bounds one admitted expansion catalog. */
MAX_NOWEB_DEFINITIONS :: u16(4_096)
/* MAX_NOWEB_NAME_BYTES bounds one copied named source, call, or result identity. */
MAX_NOWEB_NAME_BYTES :: 128
/* MAX_TANGLE_RESOURCE_BYTES bounds one copied provider resource key. */
MAX_TANGLE_RESOURCE_BYTES :: 1_024

/* Source_Edit_State identifies one focused edit lifecycle. */
Source_Edit_State :: enum u8 {
	Invalid,
	Open,
	Published,
	Aborted,
}

/* Source_Edit is one exact-revision relationship between a focused body and owner. */
Source_Edit :: struct {
	operation_id:       Operation_ID,
	scope:              Scope,
	owner:              Semantic_Target,
	body_start:         u64,
	body_end:           u64,
	original_body_hash: u64,
	indent:             Argument_Key,
	state:              Source_Edit_State,
}

/* Source_Edit_Publication is one complete owner-only whole-source candidate. */
Source_Edit_Publication :: struct {
	operation_id:    Operation_ID,
	scope:           Scope,
	owner_node_id:   u64,
	replacement_start: u64,
	replacement_end:   u64,
	byte_count:      u64,
	complete:        bool,
}

/* Noweb_Definition_Kind distinguishes named source, call, and result text. */
Noweb_Definition_Kind :: enum u8 {
	Invalid,
	Source,
	Call,
	Result,
}

/* Noweb_Source identifies deterministic definition precedence. */
Noweb_Source :: enum u8 {
	Invalid,
	Factory_Library,
	User_Library,
	Workspace_Library,
	Project_Library,
	Document,
}

/* Noweb_Definition is borrowed source text from an explicitly admitted catalog. */
Noweb_Definition :: struct {
	identity:  string,
	body:      string,
	separator: string,
	kind:      Noweb_Definition_Kind,
	source:    Noweb_Source,
	order:     u16,
	additive:  bool,
	admitted:  bool,
}

/* Noweb_Trace is one copied reference-chain entry. */
Noweb_Trace :: struct {
	identity: Argument_Key,
	depth:    u16,
	kind:     Noweb_Definition_Kind,
	source:   Noweb_Source,
}

/* Noweb_Expansion reports one complete copied expansion. */
Noweb_Expansion :: struct {
	definition_count: u16,
	reference_count:  u32,
	trace_count:      u16,
	byte_count:       u64,
	complete:         bool,
}

/* Tangle_Collision_Policy controls existing unrelated resources. */
Tangle_Collision_Policy :: enum u8 {
	Invalid,
	Reject,
	Replace_Owned,
	Overwrite,
}

/* Tangle_Resource is a copied provider-owned target identity. */
Tangle_Resource :: struct {
	provider: u64,
	key:      [MAX_TANGLE_RESOURCE_BYTES]u8,
	length:   u16,
}

/* Existing_Tangle_Resource reports collision ownership without exposing bytes. */
Existing_Tangle_Resource :: struct {
	resource:         Tangle_Resource,
	exists:           bool,
	generated_by_jan: bool,
}

/* Tangle_Block is borrowed fully expanded content for one selected block. */
Tangle_Block :: struct {
	operation_id: Operation_ID,
	scope:        Scope,
	owner:        Semantic_Target,
	resource:     Tangle_Resource,
	content:      string,
	shebang:      string,
	comment_prefix: string,
	mode:         u32,
	order:        u32,
	comments:     bool,
	padding:      bool,
	policy:       Tangle_Collision_Policy,
}

/* Tangle_Target is one staged complete resource candidate. */
Tangle_Target :: struct {
	resource:      Tangle_Resource,
	offset:        u64,
	byte_count:    u64,
	content_hash:  u64,
	block_count:   u32,
	mode:          u32,
	overwrite:     bool,
	complete:      bool,
}

/* Tangle_Outcome attributes one source block to one staged target. */
Tangle_Outcome :: struct {
	operation_id: Operation_ID,
	node_id:      u64,
	target_index: u32,
	staged:       bool,
}

/* Tangle_Plan describes a complete multi-resource staged extraction. */
Tangle_Plan :: struct {
	descriptor:    Extraction_Descriptor,
	target_count:  u32,
	staged_bytes:  u64,
	outcome_count: u32,
	complete:      bool,
}

/* tangle_resource_copy creates one bounded provider resource identity. */
tangle_resource_copy :: proc(provider: u64, key: string) -> (Tangle_Resource, bool) {
	resource: Tangle_Resource
	if provider == 0 || len(key) == 0 || len(key) > len(resource.key) || !utf8.valid_string(key) do return {}, false
	resource.provider = provider
	resource.length = u16(copy(resource.key[:], key))
	return resource, true
}

/* tangle_resource_text borrows one copied target key. */
tangle_resource_text :: proc(resource: Tangle_Resource) -> string {
	if resource.provider == 0 || resource.length == 0 || int(resource.length) > len(resource.key) do return ""
	value := resource
	return string(value.key[:value.length])
}

/* open_source_edit copies and deindents one exact source-block body. */
open_source_edit :: proc(
	operation_id: Operation_ID,
	scope: Scope,
	owner: Semantic_Target,
	body_start, body_end: u64,
	indent: string,
	source: string,
	focused: []u8,
) -> (Source_Edit, string, bool, Failure) {
	indent_key, indent_ok := source_indent_copy(indent)
	if operation_id == Operation_ID(0) || !scope_is_valid(scope) || !semantic_target_is_valid(owner, scope) ||
	   scope.source_bytes != u64(len(source)) || body_start < u64(owner.range.start) ||
	   body_end > u64(owner.range.end) || body_start > body_end || body_end - body_start > MAX_SOURCE_EDIT_BYTES ||
	   !indent_ok {
		return {}, "", false, extraction_failure(operation_id, .Invalid_Request, .Target)
	}
	body := source[body_start:body_end]
	required, valid := deindented_size(body, indent)
	if !valid || required > len(focused) do return {}, "", false, extraction_failure(operation_id, .Limited, .Limit)
	written := copy_deindented(focused, body, indent)
	return {
		operation_id = operation_id,
		scope = scope,
		owner = owner,
		body_start = body_start,
		body_end = body_end,
		original_body_hash = extraction_hash(body),
		indent = indent_key,
		state = .Open,
	}, string(focused[:written]), true, {}
}

/* publish_source_edit revalidates the owner and returns one whole-source candidate. */
publish_source_edit :: proc(
	edit: ^Source_Edit,
	confirmed_scope: Scope,
	confirmed_owner: Semantic_Target,
	current_source: string,
	edited_body: string,
	output: []u8,
) -> (Source_Edit_Publication, string, bool, Failure) {
	if edit == nil || edit.state != .Open || edit.scope != confirmed_scope || edit.owner != confirmed_owner ||
	   confirmed_scope.source_bytes != u64(len(current_source)) || edit.body_start > edit.body_end ||
	   edit.body_end > u64(len(current_source)) ||
	   extraction_hash(current_source[edit.body_start:edit.body_end]) != edit.original_body_hash {
		return {}, "", false, extraction_failure(0, .Stale, .Target)
	}
	indent := argument_key_text(&edit.indent)
	indented_size := len(edited_body) + source_line_prefix_count(edited_body) * len(indent)
	required := len(current_source) - int(edit.body_end - edit.body_start) + indented_size
	if required > len(output) || u64(indented_size) > MAX_SOURCE_EDIT_BYTES {
		return {}, "", false, extraction_failure(edit.operation_id, .Allocation_Failed, .Limit)
	}
	cursor := copy(output, current_source[:edit.body_start])
	cursor += copy_indented(output[cursor:], edited_body, indent)
	cursor += copy(output[cursor:], current_source[edit.body_end:])
	edit.state = .Published
	publication := Source_Edit_Publication {
		operation_id = edit.operation_id,
		scope = confirmed_scope,
		owner_node_id = u64(confirmed_owner.node_id),
		replacement_start = edit.body_start,
		replacement_end = edit.body_end,
		byte_count = u64(cursor),
		complete = true,
	}
	return publication, string(output[:cursor]), true, {}
}

/* abort_source_edit closes a focused edit without constructing a source candidate. */
abort_source_edit :: proc(edit: ^Source_Edit) -> bool {
	if edit == nil || edit.state != .Open do return false
	edit.state = .Aborted
	return true
}

/* expand_noweb expands compatible references from explicitly admitted definitions. */
expand_noweb :: proc(
	root: string,
	definitions: []Noweb_Definition,
	output: []u8,
	trace: []Noweb_Trace,
	limits := DEFAULT_LIMITS,
) -> (Noweb_Expansion, string, bool, Failure) {
	if len(definitions) == 0 || len(definitions) > int(MAX_NOWEB_DEFINITIONS) ||
	   len(trace) == 0 || len(output) == 0 {
		return {}, "", false, extraction_failure(0, .Limited, .Limit)
	}
	for definition in definitions {
		if !noweb_definition_is_valid(definition) do return {}, "", false, extraction_failure(0, .Malformed, .Dependency)
	}
	cursor, trace_count, reference_count := 0, 0, u32(0)
	ok, code := expand_noweb_text(root, "", "", definitions, output, &cursor, trace, &trace_count,
		&reference_count, 0, limits)
	if !ok do return {definition_count = u16(len(definitions)), reference_count = reference_count,
	                         trace_count = u16(trace_count), byte_count = u64(cursor)},
	                        "", false, extraction_failure(0, code, .Dependency)
	return {definition_count = u16(len(definitions)), reference_count = reference_count,
	        trace_count = u16(trace_count), byte_count = u64(cursor), complete = true},
	       string(output[:cursor]), true, {}
}

/* plan_tangle validates all blocks and stages every target before publication. */
plan_tangle :: proc(
	blocks: []Tangle_Block,
	existing: []Existing_Tangle_Resource,
	staging: []u8,
	targets: []Tangle_Target,
	outcomes: []Tangle_Outcome,
	cancelled: bool,
	limits := DEFAULT_LIMITS,
) -> (Tangle_Plan, bool, Failure) {
	if cancelled do return {}, false, extraction_failure(0, .Cancelled, .Resource)
	if len(blocks) == 0 || len(blocks) > int(limits.executable_targets) || len(targets) < len(blocks) ||
	   len(outcomes) < len(blocks) || len(staging) == 0 {
		return {}, false, extraction_failure(0, .Limited, .Limit)
	}
	ordered := make([]Tangle_Block, len(blocks), context.temp_allocator)
	if ordered == nil do return {}, false, extraction_failure(0, .Allocation_Failed, .Limit)
	copy(ordered, blocks)
	slice.sort_by(ordered, tangle_block_less)
	for block in ordered {
		if !tangle_block_is_valid(block) do return {}, false, extraction_failure(block.operation_id, .Malformed, .Resource)
	}
	target_count, outcome_count, cursor := 0, 0, 0
	for block in ordered {
		target_index := -1
		for target, index in targets[:target_count] do if tangle_resource_equal(target.resource, block.resource) {
			target_index = index
			break
		}
		if target_index < 0 {
			if target_count >= int(limits.generated_files) do return {}, false, extraction_failure(block.operation_id, .Limited, .Limit)
			exists, owned := tangle_existing_state(existing, block.resource)
			if exists && (block.policy == .Reject || (block.policy == .Replace_Owned && !owned)) {
				return {}, false, extraction_failure(block.operation_id, .Conflict, .Resource)
			}
			targets[target_count] = {resource = block.resource, offset = u64(cursor), mode = block.mode,
			                         overwrite = exists, complete = false}
			target_index = target_count
			target_count += 1
		} else if targets[target_index].mode != block.mode {
			return {}, false, extraction_failure(block.operation_id, .Conflict, .Resource)
		}
		target := &targets[target_index]
		if target.block_count == 0 && len(block.shebang) > 0 {
			if !tangle_write(&cursor, staging, block.shebang) || !tangle_write(&cursor, staging, "\n") {
				return {}, false, extraction_failure(block.operation_id, .Limited, .Limit)
			}
		}
		if block.comments {
			if !tangle_write(&cursor, staging, block.comment_prefix) ||
			   !tangle_write(&cursor, staging, "Jan source node ") ||
			   !tangle_write_u64(&cursor, staging, u64(block.owner.node_id)) ||
			   !tangle_write(&cursor, staging, "\n") {
				return {}, false, extraction_failure(block.operation_id, .Limited, .Limit)
			}
		}
		if !tangle_write(&cursor, staging, block.content) do return {}, false, extraction_failure(block.operation_id, .Limited, .Limit)
		if block.padding && !tangle_write(&cursor, staging, "\n") do return {}, false, extraction_failure(block.operation_id, .Limited, .Limit)
		target.block_count += 1
		target.byte_count = u64(cursor) - target.offset
		if target.byte_count > limits.output_bytes || u64(cursor) > limits.retained_output_bytes {
			return {}, false, extraction_failure(block.operation_id, .Limited, .Limit)
		}
		outcomes[outcome_count] = {operation_id = block.operation_id, node_id = u64(block.owner.node_id),
		                           target_index = u32(target_index), staged = true}
		outcome_count += 1
	}
	for &target in targets[:target_count] {
		target.content_hash = extraction_hash(string(staging[target.offset:target.offset + target.byte_count]))
		target.complete = true
	}
	plan := Tangle_Plan {
		descriptor = {operation_id = blocks[0].operation_id, scope = blocks[0].scope,
		              target_count = u32(len(blocks)), resource_count = u32(target_count),
		              byte_count = u64(cursor), complete = true},
		target_count = u32(target_count),
		staged_bytes = u64(cursor),
		outcome_count = u32(outcome_count),
		complete = true,
	}
	return plan, true, {}
}

@(private)
source_indent_copy :: proc(indent: string) -> (Argument_Key, bool) {
	if len(indent) > MAX_ARGUMENT_KEY_BYTES do return {}, false
	for value in transmute([]u8)indent do if value != ' ' && value != '\t' do return {}, false
	key: Argument_Key
	key.length = u8(copy(key.bytes[:], indent))
	return key, true
}

@(private)
deindented_size :: proc(body, indent: string) -> (int, bool) {
	if len(indent) == 0 do return len(body), true
	required, line_start := 0, true
	for _, index in transmute([]u8)body {
		if line_start {
			if index + len(indent) > len(body) || body[index:index + len(indent)] != indent do return 0, false
			required -= len(indent)
			line_start = false
		}
		required += 1
		if body[index] == '\n' do line_start = true
	}
	return required, true
}

@(private)
copy_deindented :: proc(output: []u8, body, indent: string) -> int {
	cursor, source_cursor := 0, 0
	for source_cursor < len(body) {
		if len(indent) > 0 do source_cursor += len(indent)
		line_end := source_cursor
		for line_end < len(body) && body[line_end] != '\n' do line_end += 1
		cursor += copy(output[cursor:], body[source_cursor:line_end])
		if line_end < len(body) {
			output[cursor] = '\n'
			cursor += 1
			line_end += 1
		}
		source_cursor = line_end
	}
	return cursor
}

@(private)
source_line_prefix_count :: proc(body: string) -> int {
	if len(body) == 0 do return 0
	count := 1
	for value, index in transmute([]u8)body do if value == '\n' && index + 1 < len(body) do count += 1
	return count
}

@(private)
copy_indented :: proc(output: []u8, body, indent: string) -> int {
	cursor, line_start := 0, true
	for value in transmute([]u8)body {
		if line_start {
			cursor += copy(output[cursor:], indent)
			line_start = false
		}
		output[cursor] = value
		cursor += 1
		if value == '\n' do line_start = true
	}
	return cursor
}

@(private)
noweb_definition_is_valid :: proc(definition: Noweb_Definition) -> bool {
	return len(definition.identity) > 0 && len(definition.identity) <= MAX_NOWEB_NAME_BYTES &&
	       utf8.valid_string(definition.identity) && utf8.valid_string(definition.body) &&
	       utf8.valid_string(definition.separator) && definition.kind != .Invalid &&
	       definition.source != .Invalid && (definition.source == .Document || definition.admitted)
}

@(private)
expand_noweb_text :: proc(
	text, arguments, prefix: string,
	definitions: []Noweb_Definition,
	output: []u8,
	cursor: ^int,
	trace: []Noweb_Trace,
	trace_count: ^int,
	reference_count: ^u32,
	depth: u16,
	limits: Limits,
) -> (bool, Failure_Code) {
	if depth > limits.graph_depth do return false, .Limited
	index := 0
	for index < len(text) {
		if index + 2 <= len(text) && text[index:index + 2] == "<<" {
			closing := index + 2
			for closing + 2 <= len(text) && text[closing:closing + 2] != ">>" do closing += 1
			if closing + 2 > len(text) do return false, .Malformed
			reference := text[index + 2:closing]
			name, reference_arguments, parsed := noweb_reference_parse(reference)
			if !parsed do return false, .Malformed
			definition_indexes: [MAX_NOWEB_DEFINITIONS]int
			matched, selected_source := 0, Noweb_Source.Invalid
			for definition, definition_index in definitions {
				if definition.identity != name do continue
				if definition.source > selected_source {
					matched = 0
					selected_source = definition.source
				}
				if definition.source == selected_source {
					definition_indexes[matched] = definition_index
					matched += 1
				}
			}
			if matched == 0 do return false, .Unavailable
			for match_index in 0 ..< matched do if matched > 1 && !definitions[definition_indexes[match_index]].additive do return false, .Conflict
			for match_index in 1 ..< matched {
				position := match_index
				for position > 0 && definitions[definition_indexes[position]].order < definitions[definition_indexes[position - 1]].order {
					definition_indexes[position], definition_indexes[position - 1] = definition_indexes[position - 1], definition_indexes[position]
					position -= 1
				}
			}
			for match_index in 1 ..< matched do if definitions[definition_indexes[match_index]].order == definitions[definition_indexes[match_index - 1]].order do return false, .Conflict
			if trace_count^ >= len(trace) do return false, .Limited
			for prior in trace[:trace_count^] {
				prior_identity := prior.identity
				if argument_key_text(&prior_identity) == name do return false, .Cycle
			}
			identity, copied := argument_key_copy(name)
			if !copied do return false, .Limited
			local_prefix := noweb_line_prefix(text, index)
			combined_prefix: [MAX_ARGUMENT_VALUE_BYTES]u8
			combined_length := copy(combined_prefix[:], prefix)
			if combined_length + len(local_prefix) > len(combined_prefix) do return false, .Limited
			combined_length += copy(combined_prefix[combined_length:], local_prefix)
			continuation_prefix := string(combined_prefix[:combined_length])
			for match_index in 0 ..< matched {
				definition := definitions[definition_indexes[match_index]]
				trace[trace_count^] = {identity = identity, depth = depth, kind = definition.kind, source = definition.source}
				trace_count^ += 1
				reference_count^ += 1
				if match_index > 0 && !noweb_copy_text(definition.separator, continuation_prefix, output, cursor) do return false, .Limited
				expanded, failure_code := expand_noweb_text(definition.body, reference_arguments, continuation_prefix, definitions, output, cursor,
					trace, trace_count, reference_count, depth + 1, limits)
				if !expanded do return false, failure_code
				trace_count^ -= 1
			}
			index = closing + 2
			continue
		}
		if index + len("$arguments") <= len(text) && text[index:index + len("$arguments")] == "$arguments" {
			if !noweb_copy_text(arguments, prefix, output, cursor) do return false, .Limited
			index += len("$arguments")
			continue
		}
		if cursor^ >= len(output) do return false, .Limited
		output[cursor^] = text[index]
		cursor^ += 1
		if text[index] == '\n' && index + 1 < len(text) && len(prefix) > 0 {
			if cursor^ + len(prefix) > len(output) do return false, .Limited
			cursor^ += copy(output[cursor^:], prefix)
		}
		index += 1
	}
	return true, .None
}

@(private)
noweb_reference_parse :: proc(reference: string) -> (string, string, bool) {
	if len(reference) == 0 do return "", "", false
	for value, index in transmute([]u8)reference {
		if value == '(' {
			if reference[len(reference) - 1] != ')' || index == 0 do return "", "", false
			return reference[:index], reference[index + 1:len(reference) - 1], true
		}
	}
	return reference, "", true
}

@(private)
noweb_copy_text :: proc(text, prefix: string, output: []u8, cursor: ^int) -> bool {
	for value, index in transmute([]u8)text {
		if cursor^ >= len(output) do return false
		output[cursor^] = value
		cursor^ += 1
		if value == '\n' && index + 1 < len(text) && len(prefix) > 0 {
			if cursor^ + len(prefix) > len(output) do return false
			cursor^ += copy(output[cursor^:], prefix)
		}
	}
	return true
}

@(private)
noweb_line_prefix :: proc(text: string, reference_start: int) -> string {
	line_start := reference_start
	for line_start > 0 && text[line_start - 1] != '\n' do line_start -= 1
	for value in transmute([]u8)text[line_start:reference_start] do if value != ' ' && value != '\t' do return ""
	return text[line_start:reference_start]
}

@(private)
tangle_block_less :: proc(left, right: Tangle_Block) -> bool {
	left_key := tangle_resource_text(left.resource)
	right_key := tangle_resource_text(right.resource)
	if left.resource.provider != right.resource.provider do return left.resource.provider < right.resource.provider
	if left_key != right_key do return left_key < right_key
	if left.order != right.order do return left.order < right.order
	return left.owner.range.start < right.owner.range.start
}

@(private)
tangle_block_is_valid :: proc(block: Tangle_Block) -> bool {
	return block.operation_id != Operation_ID(0) && scope_is_valid(block.scope) &&
	       semantic_target_is_valid(block.owner, block.scope) && tangle_resource_text(block.resource) != "" &&
	       len(block.content) > 0 && utf8.valid_string(block.content) && utf8.valid_string(block.shebang) &&
	       utf8.valid_string(block.comment_prefix) && (!block.comments || len(block.comment_prefix) > 0) &&
	       block.policy != .Invalid
}

@(private)
tangle_resource_equal :: proc(left, right: Tangle_Resource) -> bool {
	return left.provider == right.provider && tangle_resource_text(left) == tangle_resource_text(right)
}

@(private)
tangle_existing_state :: proc(existing: []Existing_Tangle_Resource, resource: Tangle_Resource) -> (bool, bool) {
	for candidate in existing do if tangle_resource_equal(candidate.resource, resource) do return candidate.exists, candidate.generated_by_jan
	return false, false
}

@(private)
tangle_write :: proc(cursor: ^int, output: []u8, text: string) -> bool {
	if cursor^ + len(text) > len(output) do return false
	cursor^ += copy(output[cursor^:], text)
	return true
}

@(private)
tangle_write_u64 :: proc(cursor: ^int, output: []u8, value: u64) -> bool {
	digits: [20]u8
	count := 0
	remaining := value
	if remaining == 0 {
		digits[0] = '0'
		count = 1
	} else {
		for remaining > 0 {
			digits[count] = u8(remaining % 10) + '0'
			remaining /= 10
			count += 1
		}
	}
	if cursor^ + count > len(output) do return false
	for index in 0 ..< count {
		output[cursor^ + index] = digits[count - index - 1]
	}
	cursor^ += count
	return true
}

@(private)
extraction_hash :: proc(text: string) -> u64 {
	hash := u64(14_695_981_039_346_656_037)
	for value in transmute([]u8)text {
		hash = hash ~ u64(value)
		hash *= 1_099_511_628_211
	}
	return hash
}

@(private)
extraction_failure :: proc(operation_id: Operation_ID, code: Failure_Code, field: Failure_Field) -> Failure {
	return {operation_id = operation_id, kind = .Extract, code = code, field = field}
}
