// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package indentation

import "core:strings"
import "core:unicode/utf8"

/* registry_init creates one confirmed factory generation. */
registry_init :: proc(
	registry: ^Registry,
	factory_policy := DEFAULT_POLICY,
	factory_source_generation := u64(1),
) -> (ok: bool, failure: Failure) {
	if registry == nil || registry.initialized {
		return false, {code = .Invalid_Registry}
	}
	if valid, policy_failure := policy_validate(factory_policy); !valid {
		return false, policy_failure
	}
	if factory_source_generation == 0 {
		return false, {code = .Invalid_Source_Generation, field = .Source_Generation}
	}
	registry^ = Registry {
		initialized = true,
		generation = Generation(1),
		factory_policy = factory_policy,
		factory_source_generation = factory_source_generation,
	}
	return true, {}
}

/* registry_replace validates and publishes one complete copied generation. */
registry_replace :: proc(
	registry: ^Registry,
	replacement: Replacement,
) -> (ok: bool, failure: Failure) {
	if registry == nil || !registry.initialized {
		return false, {code = .Invalid_Registry}
	}
	if replacement.expected_generation == Generation(0) ||
	   replacement.expected_generation != registry.generation {
		return registry_reject(
			registry,
			{code = .Stale_Generation, field = .Configuration_Generation,
			 actual = u64(replacement.expected_generation)},
		)
	}
	if registry.generation == Generation(max(u64)) {
		return registry_reject(
			registry,
			{code = .Generation_Limit, field = .Configuration_Generation,
			 limit = max(u64), actual = u64(registry.generation)},
		)
	}
	if replacement.proposed_generation != Generation(u64(registry.generation) + 1) {
		return registry_reject(
			registry,
			{code = .Invalid_Generation, field = .Configuration_Generation,
			 limit = u64(registry.generation) + 1,
			 actual = u64(replacement.proposed_generation)},
		)
	}
	if len(replacement.rules) > MAX_RULES {
		return registry_reject(
			registry,
			{code = .Rule_Limit, field = .Rules, limit = MAX_RULES,
			 actual = u64(len(replacement.rules))},
		)
	}
	if valid, policy_failure := policy_validate(replacement.factory_policy); !valid {
		return registry_reject(registry, policy_failure)
	}
	if replacement.factory_source_generation == 0 {
		return registry_reject(
			registry,
			{code = .Invalid_Source_Generation, field = .Source_Generation},
		)
	}

	copied: [MAX_RULES]Rule
	for candidate, index in replacement.rules {
		rule, copied_ok, copied_failure := rule_copy(candidate, u16(index))
		if !copied_ok do return registry_reject(registry, copied_failure)
		for previous_index in 0 ..< index {
			if rules_conflict(&copied[previous_index], &rule) {
				return registry_reject(
					registry,
					{code = .Duplicate_Rule, field = .Rules, rule_index = u16(index)},
				)
			}
		}
		copied[index] = rule
	}

	registry.generation = replacement.proposed_generation
	registry.factory_policy = replacement.factory_policy
	registry.factory_source_generation = replacement.factory_source_generation
	registry.rule_count = u16(len(replacement.rules))
	registry.rules = copied
	registry.latest_rejection = {}
	return true, {}
}

/* registry_inspect returns one copied generation without exposing registry storage. */
registry_inspect :: proc(registry: ^Registry) -> (inspection: Inspection, ok: bool, failure: Failure) {
	if registry == nil || !registry.initialized {
		return {}, false, {code = .Invalid_Registry}
	}
	return Inspection {
		generation = registry.generation,
		factory_policy = registry.factory_policy,
		factory_source_generation = registry.factory_source_generation,
		rule_count = registry.rule_count,
		rules = registry.rules,
		latest_rejection = registry.latest_rejection,
	}, true, {}
}

/* resolve copies the most specific matching policy for one buffer context. */
resolve :: proc(
	registry: ^Registry,
	resolution: Resolution_Context,
) -> (effective: Effective_Policy, ok: bool, failure: Failure) {
	if registry == nil || !registry.initialized {
		return {}, false, {code = .Invalid_Registry}
	}
	if resolution.profile_id == Profile_ID(0) || resolution.buffer_id == 0 ||
	   !context_text_is_valid(resolution.project) ||
	   !context_text_is_valid(resolution.language) ||
	   !context_text_is_valid(resolution.path) {
		return {}, false, {code = .Invalid_Context, field = .Context}
	}

	effective = Effective_Policy {
		policy = registry.factory_policy,
		scope = .Factory,
		matcher_kind = .None,
		source_generation = registry.factory_source_generation,
		configuration_generation = registry.generation,
		profile_id = resolution.profile_id,
	}
	best_precedence := scope_precedence(.Factory)
	best_specificity := 0
	for &rule in registry.rules[:registry.rule_count] {
		if rule.profile_id != resolution.profile_id {
			continue
		}
		matched, specificity := rule_matches(&rule, resolution)
		if !matched {
			continue
		}
		precedence := scope_precedence(rule.scope)
		if precedence < best_precedence ||
		   precedence == best_precedence && specificity <= best_specificity {
			continue
		}
		effective.policy = rule.policy
		effective.scope = rule.scope
		effective.matcher_kind = rule.matcher_kind
		effective.matcher = rule.matcher
		effective.source_generation = rule.source_generation
		best_precedence = precedence
		best_specificity = specificity
	}
	return effective, true, {}
}

/* effective_policy_is_valid validates one copied resolution. */
effective_policy_is_valid :: proc(effective: Effective_Policy) -> bool {
	valid := policy_is_valid(effective.policy)
	return valid && effective.scope != .Invalid && effective.matcher_kind != .Invalid &&
	       effective.source_generation > 0 &&
	       effective.configuration_generation != Generation(0) &&
	       effective.profile_id != Profile_ID(0)
}

/* policy_is_valid validates independent representation and width values. */
policy_is_valid :: proc(policy: Policy) -> bool {
	valid, _ := policy_validate(policy)
	return valid
}

/* matcher_text returns a read-only view over one copied matcher. */
matcher_text :: proc(matcher: ^Matcher_Text) -> string {
	if matcher == nil || matcher.length == 0 do return ""
	return string(matcher.bytes[:matcher.length])
}

@(private)
registry_reject :: proc(registry: ^Registry, failure: Failure) -> (bool, Failure) {
	registry.latest_rejection = failure
	return false, failure
}

@(private)
policy_validate :: proc(policy: Policy) -> (bool, Failure) {
	if policy.representation != .Tabs && policy.representation != .Spaces {
		return false, {code = .Invalid_Policy, field = .Representation}
	}
	if policy.indent_width == 0 || policy.indent_width > MAX_WIDTH {
		return false, {code = .Invalid_Policy, field = .Indent_Width,
			limit = u64(MAX_WIDTH), actual = u64(policy.indent_width)}
	}
	if policy.display_tab_width == 0 || policy.display_tab_width > MAX_WIDTH {
		return false, {code = .Invalid_Policy, field = .Display_Tab_Width,
			limit = u64(MAX_WIDTH), actual = u64(policy.display_tab_width)}
	}
	return true, {}
}

@(private)
rule_copy :: proc(candidate: Rule_Candidate, index: u16) -> (Rule, bool, Failure) {
	if candidate.profile_id == Profile_ID(0) {
		return {}, false, {code = .Invalid_Profile, field = .Profile, rule_index = index}
	}
	if candidate.scope < .User_Global || candidate.scope > .Buffer_Local {
		return {}, false, {code = .Invalid_Scope, field = .Scope, rule_index = index}
	}
	if candidate.source_generation == 0 {
		return {}, false, {code = .Invalid_Source_Generation,
			field = .Source_Generation, rule_index = index}
	}
	if valid, policy_failure := policy_validate(candidate.policy); !valid {
		policy_failure.rule_index = index
		return {}, false, policy_failure
	}
	if !rule_shape_is_valid(candidate) {
		return {}, false, {code = .Invalid_Matcher, field = .Matcher, rule_index = index}
	}
	matcher, matcher_ok := matcher_copy(candidate.matcher)
	if !matcher_ok {
		return {}, false, {code = .Invalid_Matcher, field = .Matcher,
			rule_index = index, limit = MAX_MATCHER_BYTES,
			actual = u64(len(candidate.matcher))}
	}
	return Rule {
		profile_id = candidate.profile_id,
		scope = candidate.scope,
		matcher_kind = candidate.matcher_kind,
		matcher = matcher,
		buffer_id = candidate.buffer_id,
		policy = candidate.policy,
		source_generation = candidate.source_generation,
	}, true, {}
}

@(private)
rule_shape_is_valid :: proc(candidate: Rule_Candidate) -> bool {
	#partial switch candidate.scope {
	case .User_Global:
		return candidate.matcher_kind == .None && len(candidate.matcher) == 0 && candidate.buffer_id == 0
	case .Project:
		return candidate.matcher_kind == .Project && matcher_source_is_valid(candidate.matcher) &&
		       candidate.buffer_id == 0
	case .File_Type:
		return (candidate.matcher_kind == .Exact_Filename ||
		        candidate.matcher_kind == .Filename_Suffix) &&
		       matcher_source_is_valid(candidate.matcher) && candidate.buffer_id == 0
	case .Language:
		return candidate.matcher_kind == .Language && matcher_source_is_valid(candidate.matcher) &&
		       candidate.buffer_id == 0
	case .Buffer_Local:
		return candidate.matcher_kind == .Buffer && len(candidate.matcher) == 0 && candidate.buffer_id != 0
	}
	return false
}

@(private)
matcher_source_is_valid :: proc(value: string) -> bool {
	return len(value) > 0 && len(value) <= MAX_MATCHER_BYTES &&
	       utf8.valid_string(value) && !strings.contains(value, "\x00")
}

@(private)
context_text_is_valid :: proc(value: string) -> bool {
	return utf8.valid_string(value) && !strings.contains(value, "\x00")
}

@(private)
matcher_copy :: proc(value: string) -> (Matcher_Text, bool) {
	if len(value) == 0 do return {}, true
	if !matcher_source_is_valid(value) do return {}, false
	result: Matcher_Text
	copy(result.bytes[:], transmute([]u8)value)
	result.length = u16(len(value))
	return result, true
}

@(private)
rules_conflict :: proc(left, right: ^Rule) -> bool {
	if left.profile_id != right.profile_id || left.scope != right.scope ||
	   left.matcher_kind != right.matcher_kind || left.buffer_id != right.buffer_id {
		return false
	}
	return matcher_text(&left.matcher) == matcher_text(&right.matcher)
}

@(private)
scope_precedence :: proc(scope: Scope) -> int {
	#partial switch scope {
	case .Factory:      return 0
	case .User_Global:  return 1
	case .Project:      return 2
	case .File_Type:    return 3
	case .Language:     return 4
	case .Buffer_Local: return 5
	}
	return -1
}

@(private)
rule_matches :: proc(rule: ^Rule, resolution: Resolution_Context) -> (bool, int) {
	matcher := matcher_text(&rule.matcher)
	#partial switch rule.scope {
	case .User_Global:
		return true, 0
	case .Project:
		return len(resolution.project) > 0 && resolution.project == matcher, len(matcher)
	case .File_Type:
		filename := path_basename(resolution.path)
		if rule.matcher_kind == .Exact_Filename {
			return len(filename) > 0 && filename == matcher, MAX_MATCHER_BYTES + len(matcher)
		}
		return len(filename) > 0 && strings.has_suffix(filename, matcher), len(matcher)
	case .Language:
		return len(resolution.language) > 0 && resolution.language == matcher, len(matcher)
	case .Buffer_Local:
		return resolution.buffer_id == rule.buffer_id, 0
	}
	return false, 0
}

@(private)
path_basename :: proc(path: string) -> string {
	start := 0
	for value, index in path {
		if value == '/' || value == '\\' do start = index + 1
	}
	return path[start:]
}
