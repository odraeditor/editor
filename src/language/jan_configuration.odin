// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../editor"

/* JAN_CONFIGURATION_VALUE_BYTES bounds one copied configuration name. */
JAN_CONFIGURATION_VALUE_BYTES :: 64

/* JAN_CONFIGURATION_VALUES bounds each confirmed configuration name set. */
JAN_CONFIGURATION_VALUES :: 16

/* Jan_File_Local_Setting_Policy controls recognition without granting effects. */
Jan_File_Local_Setting_Policy :: enum u8 {
	Invalid,
	Ignore,
	Recognize,
}

/* Jan_Emphasis_Boundary_Policy selects the baseline delimiter rules. */
Jan_Emphasis_Boundary_Policy :: enum u8 {
	Invalid,
	Org_Compatible,
}

/* Jan_Regular_Expression_Dialect identifies source-owned expression syntax. */
Jan_Regular_Expression_Dialect :: enum u8 {
	Invalid,
	Org_Compatible,
}

/* Jan_Configuration_Value is one bounded copied syntax name. */
Jan_Configuration_Value :: struct {
	bytes:  [JAN_CONFIGURATION_VALUE_BYTES]u8,
	length: u16,
}

/* Jan_Configuration_Value_List is one fixed-capacity confirmed name set. */
Jan_Configuration_Value_List :: struct {
	values: [JAN_CONFIGURATION_VALUES]Jan_Configuration_Value,
	count:  u8,
}

/* Jan_Configuration is one copied configuration candidate or generation. */
Jan_Configuration :: struct {
	identity:                  Jan_Configuration_Identity,
	task_keywords:             Jan_Configuration_Value_List,
	link_schemes:              Jan_Configuration_Value_List,
	entities:                  Jan_Configuration_Value_List,
	block_names:               Jan_Configuration_Value_List,
	tag_case_sensitive:        bool,
	property_case_sensitive:   bool,
	property_inheritance:      bool,
	radio_links:               bool,
	emphasis_boundaries:       Jan_Emphasis_Boundary_Policy,
	file_local_settings:       Jan_File_Local_Setting_Policy,
	regular_expression_dialect: Jan_Regular_Expression_Dialect,
}

/* jan_factory_configuration returns the complete native Jan baseline policy. */
jan_factory_configuration :: proc(generation: Jan_Configuration_Generation) -> Jan_Configuration {
	configuration := Jan_Configuration {
		tag_case_sensitive = true,
		property_case_sensitive = false,
		property_inheritance = true,
		radio_links = true,
		emphasis_boundaries = .Org_Compatible,
		file_local_settings = .Recognize,
		regular_expression_dialect = .Org_Compatible,
	}
	task_keywords := [5]string{"TODO", "NEXT", "WAIT", "DONE", "CANCELLED"}
	for value in task_keywords {
		assert(jan_configuration_list_append(&configuration.task_keywords, value))
	}
	link_schemes := [6]string{"file", "http", "https", "id", "custom-id", "mailto"}
	for value in link_schemes {
		assert(jan_configuration_list_append(&configuration.link_schemes, value))
	}
	entities := [6]string{"alpha", "beta", "gamma", "lambda", "pi", "nbsp"}
	for value in entities {
		assert(jan_configuration_list_append(&configuration.entities, value))
	}
	block_names := [11]string{
		"center", "quote", "src", "example", "export", "comment", "verse",
		"ascii", "html", "latex", "table",
	}
	for value in block_names {
		assert(jan_configuration_list_append(&configuration.block_names, value))
	}
	assert(jan_configuration_confirm(&configuration, generation))
	return configuration
}

/* jan_configuration_list_clear prepares one bounded list for replacement. */
jan_configuration_list_clear :: proc(values: ^Jan_Configuration_Value_List) -> bool {
	if values == nil do return false
	values^ = {}
	return true
}

/* jan_configuration_list_append copies one non-empty syntax name. */
jan_configuration_list_append :: proc(
	values: ^Jan_Configuration_Value_List,
	value: string,
) -> bool {
	if values == nil || len(value) == 0 || len(value) > JAN_CONFIGURATION_VALUE_BYTES ||
	   values.count >= JAN_CONFIGURATION_VALUES {
		return false
	}
	entry := &values.values[values.count]
	entry.length = u16(copy(entry.bytes[:], value))
	values.count += 1
	return true
}

/* jan_configuration_confirm validates and identifies an atomic generation. */
jan_configuration_confirm :: proc(
	configuration: ^Jan_Configuration,
	generation: Jan_Configuration_Generation,
) -> bool {
	if configuration == nil || generation == Jan_Configuration_Generation(0) ||
	   !jan_configuration_policy_is_valid(configuration^) {
		return false
	}
	configuration.identity.generation = generation
	configuration.identity.digest = jan_configuration_digest(configuration^)
	return true
}

/* jan_configuration_is_valid checks policy, generation, and content digest. */
jan_configuration_is_valid :: proc(configuration: Jan_Configuration) -> bool {
	return configuration.identity.generation != Jan_Configuration_Generation(0) &&
		jan_configuration_policy_is_valid(configuration) &&
		configuration.identity.digest == jan_configuration_digest(configuration)
}

@(private)
jan_configuration_policy_is_valid :: proc(configuration: Jan_Configuration) -> bool {
	return jan_configuration_list_is_valid(configuration.task_keywords) &&
		jan_configuration_list_is_valid(configuration.link_schemes) &&
		jan_configuration_list_is_valid(configuration.entities) &&
		jan_configuration_list_is_valid(configuration.block_names) &&
		configuration.task_keywords.count > 0 &&
		configuration.link_schemes.count > 0 &&
		configuration.emphasis_boundaries == .Org_Compatible &&
		configuration.file_local_settings >= .Ignore &&
		configuration.file_local_settings <= .Recognize &&
		configuration.regular_expression_dialect == .Org_Compatible
}

@(private)
jan_configuration_list_is_valid :: proc(values: Jan_Configuration_Value_List) -> bool {
	if values.count > JAN_CONFIGURATION_VALUES do return false
	for left_index in 0 ..< int(values.count) {
		left := values.values[left_index]
		if left.length == 0 || left.length > JAN_CONFIGURATION_VALUE_BYTES do return false
		for right_index in left_index + 1 ..< int(values.count) {
			if jan_configuration_value_matches(values.values[right_index], left.bytes[:left.length]) {
				return false
			}
		}
	}
	return true
}

@(private)
jan_configuration_digest :: proc(configuration: Jan_Configuration) -> (digest: [32]u8) {
	states := [4]u64{
		14695981039346656037,
		1099511628211,
		7809847782465536322,
		965930312949666949,
	}
	for lane in 0 ..< len(states) {
		state := states[lane]
		state = jan_configuration_hash_byte(state, u8(configuration.tag_case_sensitive))
		state = jan_configuration_hash_byte(state, u8(configuration.property_case_sensitive))
		state = jan_configuration_hash_byte(state, u8(configuration.property_inheritance))
		state = jan_configuration_hash_byte(state, u8(configuration.radio_links))
		state = jan_configuration_hash_byte(state, u8(configuration.emphasis_boundaries))
		state = jan_configuration_hash_byte(state, u8(configuration.file_local_settings))
		state = jan_configuration_hash_byte(state, u8(configuration.regular_expression_dialect))
		lists := [4]Jan_Configuration_Value_List{
			configuration.task_keywords,
			configuration.link_schemes,
			configuration.entities,
			configuration.block_names,
		}
		for list in lists {
			state = jan_configuration_hash_byte(state, list.count)
			for value_index in 0 ..< int(list.count) {
				value := list.values[value_index]
				state = jan_configuration_hash_byte(state, u8(value.length))
				for byte in value.bytes[:value.length] do state = jan_configuration_hash_byte(state, byte)
			}
		}
		for byte_index in 0 ..< 8 {
			digest[lane * 8 + byte_index] = u8(state >> u64(byte_index * 8))
		}
	}
	return
}

@(private)
jan_configuration_hash_byte :: proc(state: u64, value: u8) -> u64 {
	return (state ~ u64(value)) * 1099511628211
}

@(private)
jan_configuration_value_matches :: proc(value: Jan_Configuration_Value, candidate: []u8) -> bool {
	if int(value.length) != len(candidate) do return false
	for index in 0 ..< len(candidate) do if value.bytes[index] != candidate[index] do return false
	return true
}

@(private)
jan_configuration_value_matches_folded :: proc(value: Jan_Configuration_Value, candidate: []u8) -> bool {
	if int(value.length) != len(candidate) do return false
	for index in 0 ..< len(candidate) {
		left := value.bytes[index]
		right := candidate[index]
		if left >= 'A' && left <= 'Z' do left += 'a' - 'A'
		if right >= 'A' && right <= 'Z' do right += 'a' - 'A'
		if left != right do return false
	}
	return true
}

@(private)
jan_configuration_list_contains :: proc(
	values: Jan_Configuration_Value_List,
	candidate: []u8,
	folded := false,
) -> bool {
	for index in 0 ..< int(values.count) {
		if folded {
			if jan_configuration_value_matches_folded(values.values[index], candidate) do return true
		} else if jan_configuration_value_matches(values.values[index], candidate) {
			return true
		}
	}
	return false
}

@(private)
jan_classify_configured_syntax :: proc(
	state: ^Jan_Structural_Analysis_State,
	source: []u8,
	configuration: Jan_Configuration,
	limits: Jan_Resource_Limits,
) -> bool {
	if state == nil do return false
	original_count := len(state.nodes)
	for node_index in 0 ..< original_count {
		node := state.nodes[node_index]
		if node.kind != .Paragraph do continue
		if !jan_classify_embedded_registered_links(state, node, source, configuration, limits) {
			return false
		}
		if configuration.radio_links &&
		   !jan_classify_radio_links(state, node, source, original_count, limits) {
			return false
		}
	}
	return true
}

@(private)
jan_classify_heading_attributes :: proc(
	state: ^Jan_Structural_Analysis_State,
	node_id: Jan_Node_ID,
	source: []u8,
	marker_end, line_end: u32,
	configuration: Jan_Configuration,
	limits: Jan_Resource_Limits,
) -> bool {
	if !jan_append_boolean_attribute(
		state, node_id, "tag-case-sensitive", marker_end, line_end,
		configuration.tag_case_sensitive, limits,
	) {
		return false
	}
	cursor := marker_end
	for cursor < line_end && (source[cursor] == ' ' || source[cursor] == '\t') do cursor += 1
	word_end := cursor
	for word_end < line_end && source[word_end] != ' ' && source[word_end] != '\t' do word_end += 1
	if word_end > cursor && jan_configuration_list_contains(
		configuration.task_keywords,
		source[cursor:word_end],
	) {
		if !jan_structural_append_attribute(
			state, node_id, .Text, "task-state", cursor, word_end,
			source[cursor:word_end], limits,
		) {
			return false
		}
		cursor = word_end
		for cursor < line_end && (source[cursor] == ' ' || source[cursor] == '\t') do cursor += 1
	}
	if cursor + 4 <= line_end && source[cursor] == '[' && source[cursor + 1] == '#' &&
	   source[cursor + 3] == ']' {
		if !jan_structural_append_attribute(
			state, node_id, .Text, "priority", cursor + 2, cursor + 3,
			source[cursor + 2:cursor + 3], limits,
		) {
			return false
		}
	}
	end := line_end
	for end > marker_end && (source[end - 1] == ' ' || source[end - 1] == '\t') do end -= 1
	if end <= marker_end || source[end - 1] != ':' do return true
	start := end - 1
	for start > marker_end && source[start - 1] != ' ' && source[start - 1] != '\t' do start -= 1
	if start >= end || source[start] != ':' do return true
	tag_start := start + 1
	for cursor = tag_start; cursor < end; cursor += 1 {
		if source[cursor] != ':' do continue
		if cursor > tag_start && !jan_structural_append_attribute(
			state, node_id, .Text, "tag", tag_start, cursor,
			source[tag_start:cursor], limits,
		) {
			return false
		}
		tag_start = cursor + 1
	}
	return true
}

@(private)
jan_classify_property_attributes :: proc(
	state: ^Jan_Structural_Analysis_State,
	node_id: Jan_Node_ID,
	start, end: u32,
	configuration: Jan_Configuration,
	limits: Jan_Resource_Limits,
) -> bool {
	if !jan_append_boolean_attribute(
		state, node_id, "case-sensitive", start, end,
		configuration.property_case_sensitive, limits,
	) {
		return false
	}
	return jan_append_boolean_attribute(
		state, node_id, "inherited", start, end,
		configuration.property_inheritance, limits,
	)
}

@(private)
jan_classify_keyword_attributes :: proc(
	state: ^Jan_Structural_Analysis_State,
	node_id: Jan_Node_ID,
	source: []u8,
	key_start, key_end: u32,
	configuration: Jan_Configuration,
	limits: Jan_Resource_Limits,
) -> bool {
	key := source[key_start:key_end]
	if configuration.file_local_settings == .Recognize && jan_keyword_is_file_local(key) {
		if !jan_structural_append_attribute(
			state, node_id, .Boolean, "file-local-setting", key_start, key_end,
			transmute([]u8)(string("true")), limits,
		) {
			return false
		}
	}
	if jan_ascii_contains_folded(key, "regexp") || jan_ascii_contains_folded(key, "match") {
		if !jan_structural_append_attribute(
			state, node_id, .Regular_Expression, "regular-expression-dialect",
			key_start, key_end, transmute([]u8)(string("org-compatible")), limits,
		) {
			return false
		}
	}
	return true
}

@(private)
jan_keyword_is_file_local :: proc(key: []u8) -> bool {
	candidates := [12]string{
		"todo", "seq_todo", "typ_todo", "tags", "filetags", "property",
		"columns", "link", "macro", "options", "startup", "bind",
	}
	for candidate in candidates {
		if jan_ascii_equal_folded(key, candidate) do return true
	}
	return false
}

@(private)
jan_classify_entity_attributes :: proc(
	state: ^Jan_Structural_Analysis_State,
	node_id: Jan_Node_ID,
	source: []u8,
	start, end: u32,
	configuration: Jan_Configuration,
	limits: Jan_Resource_Limits,
) -> bool {
	name_start := min(start + 1, end)
	name_end := end
	if name_end >= name_start + 2 && source[name_end - 2] == '{' && source[name_end - 1] == '}' {
		name_end -= 2
	}
	if !jan_structural_append_attribute(
		state, node_id, .Text, "name", name_start, name_end,
		source[name_start:name_end], limits,
	) {
		return false
	}
	configured := jan_configuration_list_contains(configuration.entities, source[name_start:name_end])
	return jan_append_boolean_attribute(state, node_id, "configured", start, end, configured, limits)
}

@(private)
jan_classify_link_attributes :: proc(
	state: ^Jan_Structural_Analysis_State,
	node_id: Jan_Node_ID,
	source: []u8,
	start, end: u32,
	configuration: Jan_Configuration,
	limits: Jan_Resource_Limits,
) -> bool {
	cursor := start
	if cursor < end && source[cursor] == '<' do cursor += 1
	if cursor + 1 < end && source[cursor] == '[' && source[cursor + 1] == '[' do cursor += 2
	scheme_end := cursor
	for scheme_end < end && source[scheme_end] != ':' && source[scheme_end] != ']' &&
	    source[scheme_end] != '>' {
		scheme_end += 1
	}
	if scheme_end >= end || source[scheme_end] != ':' do return true
	if !jan_structural_append_attribute(
		state, node_id, .Text, "scheme", cursor, scheme_end,
		source[cursor:scheme_end], limits,
	) {
		return false
	}
	registered := jan_configuration_list_contains(
		configuration.link_schemes,
		source[cursor:scheme_end],
		true,
	)
	return jan_append_boolean_attribute(state, node_id, "registered", start, end, registered, limits)
}

@(private)
jan_classify_markup_attributes :: proc(
	state: ^Jan_Structural_Analysis_State,
	node_id: Jan_Node_ID,
	source: []u8,
	start, end: u32,
	configuration: Jan_Configuration,
	limits: Jan_Resource_Limits,
) -> bool {
	valid := configuration.emphasis_boundaries == .Org_Compatible &&
		(start == 0 || jan_markup_outer_boundary(source[start - 1])) &&
		(end == u32(len(source)) || jan_markup_outer_boundary(source[end]))
	return jan_append_boolean_attribute(state, node_id, "boundary-valid", start, end, valid, limits)
}

@(private)
jan_markup_outer_boundary :: proc(value: u8) -> bool {
	return value == ' ' || value == '\t' || value == '\r' || value == '\n' ||
		value == '(' || value == ')' || value == '[' || value == ']' ||
		value == '{' || value == '}' || value == '<' || value == '>' ||
		value == ',' || value == '.' || value == ':' || value == ';' ||
		value == '!' || value == '?'
}

@(private)
jan_classify_block_attributes :: proc(
	state: ^Jan_Structural_Analysis_State,
	node_id: Jan_Node_ID,
	source: []u8,
	start, end: u32,
	configuration: Jan_Configuration,
	limits: Jan_Resource_Limits,
) -> bool {
	line_end := jan_structural_line_end(source, start, end)
	name_start := start
	for name_start < line_end && source[name_start] != '_' && source[name_start] != ':' do name_start += 1
	if name_start >= line_end do return true
	name_start += 1
	for name_start < line_end && (source[name_start] == ' ' || source[name_start] == '\t') do name_start += 1
	name_end := name_start
	for name_end < line_end && source[name_end] != ' ' && source[name_end] != '\t' &&
	    source[name_end] != '\r' && source[name_end] != '\n' {
		name_end += 1
	}
	if name_end == name_start do return true
	if !jan_structural_append_attribute(
		state, node_id, .Text, "block-name", name_start, name_end,
		source[name_start:name_end], limits,
	) {
		return false
	}
	configured := jan_configuration_list_contains(
		configuration.block_names,
		source[name_start:name_end],
		true,
	)
	return jan_append_boolean_attribute(state, node_id, "configured", start, end, configured, limits)
}

@(private)
jan_classify_embedded_registered_links :: proc(
	state: ^Jan_Structural_Analysis_State,
	plain: Jan_Node_Record,
	source: []u8,
	configuration: Jan_Configuration,
	limits: Jan_Resource_Limits,
) -> bool {
	start := u32(plain.range.start)
	end := u32(plain.range.end)
	for cursor := start; cursor < end; cursor += 1 {
		if cursor > start && jan_ascii_identifier_byte(source[cursor - 1]) do continue
		scheme_end := cursor
		for scheme_end < end && jan_ascii_scheme_byte(source[scheme_end]) do scheme_end += 1
		if scheme_end == cursor || scheme_end >= end || source[scheme_end] != ':' ||
		   !jan_configuration_list_contains(configuration.link_schemes, source[cursor:scheme_end], true) {
			continue
		}
		link_end := scheme_end + 1
		for link_end < end && source[link_end] != ' ' && source[link_end] != '\t' &&
		    source[link_end] != '\r' && source[link_end] != '\n' {
			link_end += 1
		}
		if link_end == scheme_end + 1 do continue
		if jan_classified_node_exists(state.nodes[:], .Plain_Link, cursor, link_end) {
			cursor = link_end - 1
			continue
		}
		node_id, appended := jan_append_classified_node(
			state, plain, .Plain_Link, "plain-link", cursor, link_end, limits,
		)
		if !appended do return false
		if !jan_classify_link_attributes(
			state, node_id, source, cursor, link_end, configuration, limits,
		) {
			return false
		}
		cursor = link_end - 1
	}
	return true
}

@(private)
jan_classify_radio_links :: proc(
	state: ^Jan_Structural_Analysis_State,
	plain: Jan_Node_Record,
	source: []u8,
	original_count: int,
	limits: Jan_Resource_Limits,
) -> bool {
	plain_start := u32(plain.range.start)
	plain_end := u32(plain.range.end)
	for target_index in 0 ..< original_count {
		target := state.nodes[target_index]
		if target.kind != .Radio_Target do continue
		target_start := u32(target.range.start)
		target_end := u32(target.range.end)
		if target_end < target_start + 6 do continue
		needle := source[target_start + 3:target_end - 3]
		if len(needle) == 0 || len(needle) > int(plain_end - plain_start) do continue
		for offset in 0 ..= int(plain_end - plain_start) - len(needle) {
			match_start := plain_start + u32(offset)
			if match_start > plain_start && source[match_start - 1] == '\\' do continue
			matches := true
			for byte_index in 0 ..< len(needle) {
				if source[match_start + u32(byte_index)] != needle[byte_index] {
					matches = false
					break
				}
			}
			if !matches do continue
			match_end := match_start + u32(len(needle))
			if jan_range_overlaps_kind(
				state.nodes[:original_count],
				.Radio_Target,
				match_start,
				match_end,
			) || jan_classified_node_exists(
				state.nodes[:],
				.Radio_Link,
				match_start,
				match_end,
			) {
				continue
			}
			_, appended := jan_append_classified_node(
				state, plain, .Radio_Link, "radio-link", match_start,
				match_end, limits,
			)
			if !appended do return false
		}
	}
	return true
}

@(private)
jan_classified_node_exists :: proc(
	nodes: []Jan_Node_Record,
	kind: Jan_Node_Kind,
	start, end: u32,
) -> bool {
	for node in nodes {
		if node.kind == kind && u32(node.range.start) == start && u32(node.range.end) == end {
			return true
		}
	}
	return false
}

@(private)
jan_range_overlaps_kind :: proc(
	nodes: []Jan_Node_Record,
	kind: Jan_Node_Kind,
	start, end: u32,
) -> bool {
	for node in nodes {
		if node.kind == kind && start < u32(node.range.end) && end > u32(node.range.start) {
			return true
		}
	}
	return false
}

@(private)
jan_append_classified_node :: proc(
	state: ^Jan_Structural_Analysis_State,
	parent: Jan_Node_Record,
	kind: Jan_Node_Kind,
	label: string,
	start, end: u32,
	limits: Jan_Resource_Limits,
) -> (Jan_Node_ID, bool) {
	if state == nil || len(state.nodes) >= int(limits.nodes) ||
	   parent.inline_depth >= limits.inline_depth {
		return 0, false
	}
	node := Jan_Node_Record {
		id = Jan_Node_ID(len(state.nodes) + 1),
		parent_id = parent.id,
		layer = .Inline,
		kind = kind,
		structural_depth = parent.structural_depth,
		inline_depth = parent.inline_depth + 1,
		range = {
			scope = state.scope,
			start = editor.Byte_Offset(start),
			end = editor.Byte_Offset(end),
		},
	}
	node.kind_text.length = u16(copy(node.kind_text.bytes[:], label))
	if _, append_error := append(&state.nodes, node); append_error != nil do return 0, false
	state.usage.inline_depth = max(state.usage.inline_depth, node.inline_depth)
	return node.id, true
}

@(private)
jan_append_boolean_attribute :: proc(
	state: ^Jan_Structural_Analysis_State,
	node_id: Jan_Node_ID,
	name: string,
	start, end: u32,
	value: bool,
	limits: Jan_Resource_Limits,
) -> bool {
	text := transmute([]u8)(string("false"))
	if value do text = transmute([]u8)(string("true"))
	return jan_structural_append_attribute(state, node_id, .Boolean, name, start, end, text, limits)
}

@(private)
jan_ascii_equal_folded :: proc(left: []u8, right: string) -> bool {
	if len(left) != len(right) do return false
	for index in 0 ..< len(left) {
		left_byte := left[index]
		right_byte := right[index]
		if left_byte >= 'A' && left_byte <= 'Z' do left_byte += 'a' - 'A'
		if right_byte >= 'A' && right_byte <= 'Z' do right_byte += 'a' - 'A'
		if left_byte != right_byte do return false
	}
	return true
}

@(private)
jan_ascii_identifier_byte :: proc(value: u8) -> bool {
	return value >= 'A' && value <= 'Z' || value >= 'a' && value <= 'z' ||
		value >= '0' && value <= '9' || value == '_' || value == '-'
}

@(private)
jan_ascii_scheme_byte :: proc(value: u8) -> bool {
	return value >= 'A' && value <= 'Z' || value >= 'a' && value <= 'z' ||
		value >= '0' && value <= '9' || value == '+' || value == '.' || value == '-'
}
