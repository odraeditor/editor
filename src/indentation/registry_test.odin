// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package indentation

import "core:testing"

policy :: proc(width: u16, representation := Representation.Spaces, display := u16(8)) -> Policy {
	return {representation = representation, indent_width = width, display_tab_width = display}
}

/* Verifies every scope resolves in the specified precedence order. */
@(test)
resolution_uses_exact_scope_precedence :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	rules := [?]Rule_Candidate {
		{profile_id = 1, scope = .User_Global, matcher_kind = .None,
		 policy = policy(2), source_generation = 20},
		{profile_id = 1, scope = .Project, matcher_kind = .Project, matcher = "odra",
		 policy = policy(3), source_generation = 30},
		{profile_id = 1, scope = .File_Type, matcher_kind = .Filename_Suffix, matcher = ".odin",
		 policy = policy(4), source_generation = 40},
		{profile_id = 1, scope = .Language, matcher_kind = .Language, matcher = "odin",
		 policy = policy(5), source_generation = 50},
		{profile_id = 1, scope = .Buffer_Local, matcher_kind = .Buffer, buffer_id = 99,
		 policy = policy(6, .Tabs), source_generation = 60},
	}
	replaced, failure := registry_replace(&registry, {
		expected_generation = 1,
		proposed_generation = 2,
		factory_policy = policy(1),
		factory_source_generation = 10,
		rules = rules[:],
	})
	testing.expectf(t, replaced, "replacement failed with %v", failure.code)

	contexts := [?]Resolution_Context {
		{profile_id = 1, buffer_id = 1},
		{profile_id = 1, buffer_id = 1, project = "odra"},
		{profile_id = 1, buffer_id = 1, project = "odra", path = "/work/main.odin"},
		{profile_id = 1, buffer_id = 1, project = "odra", path = "/work/main.odin", language = "odin"},
		{profile_id = 1, buffer_id = 99, project = "odra", path = "/work/main.odin", language = "odin"},
	}
	expected := [?]Scope{.User_Global, .Project, .File_Type, .Language, .Buffer_Local}
	for resolution, index in contexts {
		effective, resolved, resolve_failure := resolve(&registry, resolution)
		testing.expectf(t, resolved, "resolution %d failed with %v", index, resolve_failure.code)
		if resolved {
			testing.expect_value(t, effective.scope, expected[index])
			testing.expect_value(t, effective.policy.indent_width, u16(index + 2))
			testing.expect_value(t, effective.configuration_generation, Generation(2))
		}
	}
}

/* Verifies exact filenames beat suffixes and longer suffixes beat shorter ones. */
@(test)
file_matchers_resolve_deterministically :: proc(t: ^testing.T) {
	registry: Registry
	_, _ = registry_init(&registry)
	rules := [?]Rule_Candidate {
		{profile_id = 1, scope = .File_Type, matcher_kind = .Filename_Suffix,
		 matcher = ".odin", policy = policy(2), source_generation = 2},
		{profile_id = 1, scope = .File_Type, matcher_kind = .Filename_Suffix,
		 matcher = ".test.odin", policy = policy(3), source_generation = 3},
		{profile_id = 1, scope = .File_Type, matcher_kind = .Exact_Filename,
		 matcher = "main.test.odin", policy = policy(4), source_generation = 4},
	}
	replaced, _ := registry_replace(&registry, {1, 2, DEFAULT_POLICY, 1, rules[:]})
	testing.expect(t, replaced)
	effective, resolved, _ := resolve(&registry, {
		profile_id = 1, buffer_id = 7, path = "C:\\work\\main.test.odin",
	})
	testing.expect(t, resolved)
	testing.expect_value(t, effective.policy.indent_width, u16(4))
	testing.expect_value(t, effective.matcher_kind, Matcher_Kind.Exact_Filename)
}

/* Verifies rejected replacements preserve the complete confirmed generation. */
@(test)
invalid_and_stale_replacements_preserve_confirmation :: proc(t: ^testing.T) {
	registry: Registry
	_, _ = registry_init(&registry)
	invalid := [?]Rule_Candidate {
		{profile_id = 1, scope = .Language, matcher_kind = .Language, matcher = "odin",
		 policy = {representation = .Spaces, indent_width = 0, display_tab_width = 4},
		 source_generation = 2},
	}
	replaced, failure := registry_replace(&registry, {1, 2, DEFAULT_POLICY, 1, invalid[:]})
	testing.expect(t, !replaced)
	testing.expect_value(t, failure.field, Failure_Field.Indent_Width)
	inspection, inspected, _ := registry_inspect(&registry)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.generation, Generation(1))
	testing.expect_value(t, inspection.rule_count, u16(0))

	replaced, failure = registry_replace(&registry, {2, 3, DEFAULT_POLICY, 1, nil})
	testing.expect(t, !replaced)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Generation)
	inspection, _, _ = registry_inspect(&registry)
	testing.expect_value(t, inspection.generation, Generation(1))
}

/* Verifies rules cannot leak between independent profile identities. */
@(test)
resolution_isolates_profiles :: proc(t: ^testing.T) {
	registry: Registry
	_, _ = registry_init(&registry)
	rules := [?]Rule_Candidate {
		{profile_id = 1, scope = .User_Global, matcher_kind = .None,
		 policy = policy(2), source_generation = 2},
		{profile_id = 2, scope = .User_Global, matcher_kind = .None,
		 policy = policy(8), source_generation = 3},
	}
	confirmed, _ := registry_replace(&registry, {1, 2, DEFAULT_POLICY, 1, rules[:]})
	testing.expect(t, confirmed)
	first, first_ok, _ := resolve(&registry, {profile_id = 1, buffer_id = 10})
	second, second_ok, _ := resolve(&registry, {profile_id = 2, buffer_id = 10})
	third, third_ok, _ := resolve(&registry, {profile_id = 3, buffer_id = 10})
	testing.expect(t, first_ok && second_ok && third_ok)
	testing.expect_value(t, first.policy.indent_width, u16(2))
	testing.expect_value(t, second.policy.indent_width, u16(8))
	testing.expect_value(t, third.scope, Scope.Factory)
}
