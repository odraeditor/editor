// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package indentation

import "core:encoding/endian"

/* ENCODED_SCHEMA_VERSION identifies copied indentation configuration batches. */
ENCODED_SCHEMA_VERSION :: u64(1)
/* ENCODED_HEADER_BYTES bounds the fixed indentation configuration header. */
ENCODED_HEADER_BYTES :: 40
/* ENCODED_RULE_BYTES bounds one fixed scoped rule record. */
ENCODED_RULE_BYTES :: 72

/* registry_prepare_encoded decodes and validates one replacement without publishing it. */
registry_prepare_encoded :: proc(
	registry: ^Registry,
	payload: []u8,
	factory_source_generation: u64,
	candidate: ^Registry,
) -> (ok: bool, failure: Failure) {
	if registry == nil || candidate == nil || !registry.initialized {
		return false, {code = .Invalid_Registry}
	}
	if len(payload) < ENCODED_HEADER_BYTES || factory_source_generation == 0 {
		return configuration_reject()
	}
	schema, schema_ok := configuration_word(payload, 0)
	representation_value, representation_ok := configuration_word(payload, 8)
	indent_width, indent_width_ok := configuration_word(payload, 16)
	display_tab_width, display_tab_width_ok := configuration_word(payload, 24)
	rule_count, rule_count_ok := configuration_word(payload, 32)
	if !schema_ok || !representation_ok || !indent_width_ok || !display_tab_width_ok ||
	   !rule_count_ok || schema != ENCODED_SCHEMA_VERSION || rule_count > MAX_RULES ||
	   rule_count > u64((len(payload) - ENCODED_HEADER_BYTES) / ENCODED_RULE_BYTES) {
		return configuration_reject()
	}
	factory_policy, factory_policy_ok := configuration_policy(
		representation_value,
		indent_width,
		display_tab_width,
	)
	if !factory_policy_ok do return configuration_reject()

	rules: [MAX_RULES]Rule_Candidate
	offset := ENCODED_HEADER_BYTES
	for index in 0 ..< int(rule_count) {
		if offset > len(payload) - ENCODED_RULE_BYTES do return configuration_reject()
		profile_id, profile_ok := configuration_word(payload, offset)
		scope_value, scope_word_ok := configuration_word(payload, offset + 8)
		matcher_kind_value, matcher_kind_word_ok := configuration_word(payload, offset + 16)
		buffer_id, buffer_ok := configuration_word(payload, offset + 24)
		rule_representation, rule_representation_ok := configuration_word(payload, offset + 32)
		rule_indent_width, rule_indent_width_ok := configuration_word(payload, offset + 40)
		rule_display_tab_width, rule_display_tab_width_ok := configuration_word(payload, offset + 48)
		source_generation, source_generation_ok := configuration_word(payload, offset + 56)
		matcher_length, matcher_length_ok := configuration_word(payload, offset + 64)
		if !profile_ok || !scope_word_ok || !matcher_kind_word_ok || !buffer_ok ||
		   !rule_representation_ok || !rule_indent_width_ok || !rule_display_tab_width_ok ||
		   !source_generation_ok || !matcher_length_ok || matcher_length > MAX_MATCHER_BYTES {
			return configuration_reject()
		}
		offset += ENCODED_RULE_BYTES
		if matcher_length > u64(len(payload) - offset) do return configuration_reject()
		matcher_end := offset + int(matcher_length)
		policy, policy_ok := configuration_policy(
			rule_representation,
			rule_indent_width,
			rule_display_tab_width,
		)
		scope, scope_ok := configuration_scope(scope_value)
		matcher_kind, matcher_kind_ok := configuration_matcher_kind(matcher_kind_value)
		if !policy_ok || !scope_ok || !matcher_kind_ok do return configuration_reject()
		rules[index] = Rule_Candidate {
			profile_id = Profile_ID(profile_id),
			scope = scope,
			matcher_kind = matcher_kind,
			matcher = string(payload[offset:matcher_end]),
			buffer_id = buffer_id,
			policy = policy,
			source_generation = source_generation,
		}
		offset = matcher_end
	}
	if offset != len(payload) || registry.generation == Generation(max(u64)) {
		return configuration_reject()
	}
	candidate^ = registry^
	return registry_replace(
		candidate,
		{
			expected_generation = registry.generation,
			proposed_generation = Generation(u64(registry.generation) + 1),
			factory_policy = factory_policy,
			factory_source_generation = factory_source_generation,
			rules = rules[:int(rule_count)],
		},
	)
}

@(private)
configuration_word :: proc(input: []u8, offset: int) -> (u64, bool) {
	if offset < 0 || len(input) < offset + 8 do return 0, false
	return endian.get_u64(input[offset:], .Little)
}

@(private)
configuration_policy :: proc(
	representation_value, indent_width, display_tab_width: u64,
) -> (policy: Policy, ok: bool) {
	representation: Representation
	switch representation_value {
	case 1: representation = .Tabs
	case 2: representation = .Spaces
	case: return {}, false
	}
	if indent_width > u64(max(u16)) || display_tab_width > u64(max(u16)) {
		return {}, false
	}
	policy = {
		representation = representation,
		indent_width = u16(indent_width),
		display_tab_width = u16(display_tab_width),
	}
	return policy, policy_is_valid(policy)
}

@(private)
configuration_scope :: proc(value: u64) -> (Scope, bool) {
	switch value {
	case 2: return .User_Global, true
	case 3: return .Project, true
	case 4: return .File_Type, true
	case 5: return .Language, true
	case 6: return .Buffer_Local, true
	}
	return .Invalid, false
}

@(private)
configuration_matcher_kind :: proc(value: u64) -> (Matcher_Kind, bool) {
	switch value {
	case 1: return .None, true
	case 2: return .Project, true
	case 3: return .Exact_Filename, true
	case 4: return .Filename_Suffix, true
	case 5: return .Language, true
	case 6: return .Buffer, true
	}
	return .Invalid, false
}

@(private)
configuration_reject :: proc() -> (bool, Failure) {
	return false, {code = .Invalid_Encoding, field = .Configuration_Encoding}
}
