// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:mem"
import "core:testing"

/* Verifies selected compatibility limits remain aligned with the resource study. */
@(test)
policy_matches_resource_evidence :: proc(t: ^testing.T) {
	policy := DEFAULT_PROFILE_COMPATIBILITY_POLICY
	testing.expect(t, profile_compatibility_policy_valid(policy))
	testing.expect_value(t, policy.max_profiles, u16(32))
	testing.expect_value(t, policy.max_states_per_profile, u16(16))
	testing.expect_value(t, policy.max_total_states, u16(512))
	testing.expect_value(t, policy.max_shared_selectors, u16(64))
	testing.expect_value(t, policy.max_total_selectors, u32(65_536))
	testing.expect_value(t, policy.max_command_entry_surfaces, u16(8))
	testing.expect_value(t, policy.max_catalog_bytes, u64(32 * 1_024 * 1_024))

	invalid := policy
	invalid.max_profiles = 0
	testing.expect(t, !profile_compatibility_policy_valid(invalid))
	invalid = policy
	invalid.max_shared_selectors = MAX_SHARED_BINDING_SELECTORS + 1
	testing.expect(t, !profile_compatibility_policy_valid(invalid))
	invalid = policy
	invalid.max_catalog_bytes = MAX_PROFILE_CATALOG_BYTES + 1
	testing.expect(t, !profile_compatibility_policy_valid(invalid))
}

/* Verifies one direct consumer and synthetic compatibility target validate together. */
@(test)
catalog_accepts_scoped_profiles :: proc(t: ^testing.T) {
	fixture: Profile_Compatibility_Fixture
	profile_compatibility_fixture_init(&fixture)
	usage, failure := profile_catalog_definition_validate(fixture.catalog)
	testing.expect_value(t, failure.code, Failure_Code.None)
	testing.expect_value(t, usage.profile_count, u16(2))
	testing.expect_value(t, usage.state_count, u16(2))
	testing.expect_value(t, usage.scoped_binding_count, u32(3))
	testing.expect_value(t, usage.shared_selector_count, u32(2))
	testing.expect_value(t, usage.command_entry_surface_count, u16(1))
	testing.expect(t, usage.definition_bytes > 0)
	testing.expect_value(t, usage.retained_bytes, u64(0))
	testing.expect_value(t, usage.temporary_peak_bytes, u64(0))
}

/* Verifies state policy admits declared effects without inferring key behavior. */
@(test)
interaction_state_admission_is_effect_explicit :: proc(t: ^testing.T) {
	fixture: Profile_Compatibility_Fixture
	profile_compatibility_fixture_init(&fixture)
	direct := fixture.direct_states[0]
	navigation := fixture.navigation_states[0]
	testing.expect(t, direct.admits_text_input)
	testing.expect(t, interaction_state_admits(direct, {.View}))
	testing.expect(t, interaction_state_admits(direct, {.Buffer, .Text_Mutation}))
	testing.expect(t, !navigation.admits_text_input)
	testing.expect(t, interaction_state_admits(navigation, {.View}))
	testing.expect(t, !interaction_state_admits(navigation, {.Text_Mutation}))
	testing.expect(t, !interaction_state_admits(navigation, {.View, .Text_Mutation}))
}

/* Verifies validated catalogs own every retained definition and release it exactly once. */
@(test)
catalog_owns_validated_definitions :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(301), context.allocator)
	if !ready {
		return
	}
	defer command_registry_close(&registry)

	fixture: Profile_Compatibility_Fixture
	profile_compatibility_fixture_prepare_buildable(&fixture)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	catalog, built, failure := profile_catalog_build(
		&registry,
		fixture.catalog,
		DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		mem.tracking_allocator(&tracking),
	)
	testing.expectf(t, built, "catalog build failed with %v", failure.code)
	if built {
		fixture.profiles[0].name = "mutated-source"
		fixture.direct_bindings[0].command_name = "unused-command"
		owned, viewed := profile_catalog_definition(&catalog)
		testing.expect(t, viewed)
		if viewed {
			testing.expect_value(t, owned.profiles[0].name, "direct")
			testing.expect_value(t, owned.profiles[0].maps[0].bindings[0].command_name, "insert-text")
			testing.expect_value(t, owned.profiles[1].name, "synthetic")
		}
		usage, usage_ok := profile_catalog_usage(&catalog)
		testing.expect(t, usage_ok)
		testing.expect(t, usage.definition_bytes > 0)
		testing.expect(t, usage.retained_bytes > usage.definition_bytes)
		testing.expect_value(t, usage.temporary_peak_bytes, usage.retained_bytes)
		testing.expect(t, profile_catalog_close(&catalog))
		testing.expect(t, !profile_catalog_close(&catalog))
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies one incompatible shared target rejects the complete catalog. */
@(test)
catalog_rejects_shared_effects_atomically :: proc(t: ^testing.T) {
	definitions := base_command_definitions()
	definitions[1].effects += {.Text_Mutation}
	registry: Command_Registry
	ready, registry_failure := command_registry_init(
		&registry,
		Registry_Generation(302),
		definitions[:],
		context.allocator,
	)
	testing.expectf(t, ready, "registry failed with %v", registry_failure.code)
	if !ready {
		return
	}
	defer command_registry_close(&registry)

	fixture: Profile_Compatibility_Fixture
	profile_compatibility_fixture_prepare_buildable(&fixture)

	_, built, failure := profile_catalog_build(&registry, fixture.catalog)
	testing.expect(t, !built)
	testing.expect_value(t, failure.code, Failure_Code.Incompatible_Shared_Binding)
	testing.expect_value(t, failure.profile.id, Profile_ID(2))
	testing.expect_value(t, failure.state.id, Interaction_State_ID(2))
	testing.expect_value(t, failure.selector_index, u32(1))
}

/* Verifies every catalog allocation fault releases all partially owned storage. */
@(test)
catalog_alloc_faults_are_atomic :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(303), context.allocator)
	if !ready {
		return
	}
	defer command_registry_close(&registry)
	fixture: Profile_Compatibility_Fixture
	profile_compatibility_fixture_prepare_buildable(&fixture)

	failures, successes: u32
	for fail_after in 0 ..< 12 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Resolver_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		catalog, built, failure := profile_catalog_build(
			&registry,
			fixture.catalog,
			DEFAULT_PROFILE_COMPATIBILITY_POLICY,
			resolver_failing_allocator(&failing),
		)
		if built {
			successes += 1
			testing.expect(t, profile_catalog_close(&catalog))
		} else {
			failures += 1
			testing.expect_value(t, failure.code, Failure_Code.Persistent_Memory_Limit)
		}
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
	testing.expect(t, failures > 0 && successes > 0)
}

/* Verifies invalid, duplicate, stale, scoped, selector, surface, and bound failures. */
@(test)
catalog_rejects_bad_compatibility :: proc(t: ^testing.T) {
	fixture: Profile_Compatibility_Fixture
	profile_compatibility_fixture_init(&fixture)

	invalid_generation := fixture.catalog
	invalid_generation.generation = 0
	_, failure := profile_catalog_definition_validate(invalid_generation)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Profile_Catalog)

	duplicate_profiles := fixture.catalog
	fixture.direct_bindings[1].scope = .Profile_Specific
	fixture.direct_bindings[1].selectors = nil
	duplicate_profiles.profiles[1].identity.id = duplicate_profiles.profiles[0].identity.id
	_, failure = profile_catalog_definition_validate(duplicate_profiles)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Profile)
	profile_compatibility_fixture_init(&fixture)

	stale_state := fixture.catalog
	stale_state.profiles[0].states[0].identity.revision = 0
	_, failure = profile_catalog_definition_validate(stale_state)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Interaction_State)
	profile_compatibility_fixture_init(&fixture)

	missing_initial := fixture.catalog
	missing_initial.profiles[0].initial_state = Interaction_State_ID(999)
	_, failure = profile_catalog_definition_validate(missing_initial)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Interaction_State)
	profile_compatibility_fixture_init(&fixture)

	invalid_scope := fixture.catalog
	invalid_scope.profiles[0].maps[0].bindings[0].scope = .Invalid
	_, failure = profile_catalog_definition_validate(invalid_scope)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Binding_Scope)
	profile_compatibility_fixture_init(&fixture)

	profile_specific_selectors := fixture.catalog
	profile_specific_selectors.profiles[0].maps[0].bindings[0].selectors =
		fixture.shared_selectors[:1]
	_, failure = profile_catalog_definition_validate(profile_specific_selectors)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Binding_Scope)
	profile_compatibility_fixture_init(&fixture)

	unknown_selector := fixture.catalog
	fixture.shared_selectors[1].state_id = Interaction_State_ID(999)
	_, failure = profile_catalog_definition_validate(unknown_selector)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Shared_Selector)
	profile_compatibility_fixture_init(&fixture)

	duplicate_selector := fixture.catalog
	fixture.shared_selectors[1] = fixture.shared_selectors[0]
	_, failure = profile_catalog_definition_validate(duplicate_selector)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Shared_Selector)
	profile_compatibility_fixture_init(&fixture)

	invalid_surface := fixture.catalog
	invalid_surface.surfaces[0].identity.revision = 0
	_, failure = profile_catalog_definition_validate(invalid_surface)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Command_Entry_Surface)
	profile_compatibility_fixture_init(&fixture)

	limited := DEFAULT_PROFILE_COMPATIBILITY_POLICY
	limited.max_profiles = 1
	_, failure = profile_catalog_definition_validate(fixture.catalog, limited)
	testing.expect_value(t, failure.code, Failure_Code.Profile_Catalog_Limit)

	limited = DEFAULT_PROFILE_COMPATIBILITY_POLICY
	limited.max_catalog_bytes = 1
	_, failure = profile_catalog_definition_validate(fixture.catalog, limited)
	testing.expect_value(t, failure.code, Failure_Code.Profile_Catalog_Memory_Limit)
}

/* Verifies the maximum generated identity space and allocation-free validation path. */
@(test)
catalog_validates_limits_without_state :: proc(t: ^testing.T) {
	profiles: [MAX_INTERACTION_PROFILES]Profile_Definition
	states: [MAX_INTERACTION_STATES]Interaction_State_Definition
	surface := profile_compatibility_surface()
	for profile_index in 0 ..< MAX_INTERACTION_PROFILES {
		state_start := profile_index * MAX_INTERACTION_STATES_PER_PROFILE
		for state_offset in 0 ..< MAX_INTERACTION_STATES_PER_PROFILE {
			state_index := state_start + state_offset
			states[state_index] = profile_compatibility_state(
				u64(state_index + 1),
				"generated-state",
				state_offset == 0,
			)
		}
		profiles[profile_index] = Profile_Definition {
			identity = {
				id = Profile_ID(profile_index + 1),
				revision = Profile_Revision(1),
			},
			name = "generated-profile",
			states = states[state_start:state_start + MAX_INTERACTION_STATES_PER_PROFILE],
			initial_state = Interaction_State_ID(state_start + 1),
			text_fallback_name = "insert-text",
		}
	}
	catalog := Profile_Catalog_Definition {
		generation = 1,
		profiles = profiles[:],
		active_profile = 1,
		active_state = 1,
		surfaces = []Command_Entry_Surface_Definition{surface},
	}

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	before := tracking.current_memory_allocated
	usage, failure := profile_catalog_definition_validate(catalog)
	after := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	testing.expect_value(t, failure.code, Failure_Code.None)
	testing.expect_value(t, usage.profile_count, u16(MAX_INTERACTION_PROFILES))
	testing.expect_value(t, usage.state_count, u16(MAX_INTERACTION_STATES))
	testing.expect_value(t, before, after)
}

@(private)
Profile_Compatibility_Fixture :: struct {
	catalog:           Profile_Catalog_Definition,
	profiles:          [2]Profile_Definition,
	direct_states:     [1]Interaction_State_Definition,
	navigation_states: [1]Interaction_State_Definition,
	direct_maps:       [1]Map_Definition,
	synthetic_maps:    [1]Map_Definition,
	direct_bindings:   [3]Layered_Binding_Definition,
	shared_selectors:  [2]Profile_State_Selector,
	surfaces:          [1]Command_Entry_Surface_Definition,
}

@(private)
profile_compatibility_fixture_init :: proc(fixture: ^Profile_Compatibility_Fixture) {
	fixture^ = {}
	fixture.direct_states[0] = profile_compatibility_state(1, "direct-editing", true)
	fixture.navigation_states[0] = profile_compatibility_state(2, "synthetic-navigation", false)
	fixture.shared_selectors = {
		{profile_id = 1, state_id = 1},
		{profile_id = 2, state_id = 2},
	}
	fixture.direct_bindings = {
		{
			command_name = "insert-text",
			operation = .Bind,
			scope = .Profile_Specific,
			provenance = profile_compatibility_provenance(),
		},
		{
			command_name = "cursor-next-grapheme",
			operation = .Bind,
			scope = .Shared_Continuity,
			selectors = fixture.shared_selectors[:],
			provenance = profile_compatibility_provenance(),
		},
		{
			command_name = "keyboard-quit",
			operation = .Bind,
			scope = .Protected_Recovery,
			provenance = profile_compatibility_provenance(),
			protection_reason = "bounded recovery",
		},
	}
	fixture.direct_maps[0] = Map_Definition {
		identity = {id = 1, revision = 1},
		name = "direct-base",
		precedence = .Profile_Base,
		bindings = fixture.direct_bindings[:],
		unmatched_input_policy = .Text_Input,
		provenance = profile_compatibility_provenance(),
	}
	fixture.profiles = {
		{
			identity = {id = 1, revision = 1},
			name = "direct",
			states = fixture.direct_states[:],
			initial_state = 1,
			maps = fixture.direct_maps[:],
			text_fallback_name = "insert-text",
		},
		{
			identity = {id = 2, revision = 1},
			name = "synthetic",
			states = fixture.navigation_states[:],
			initial_state = 2,
			text_fallback_name = "insert-text",
		},
	}
	fixture.surfaces[0] = profile_compatibility_surface()
	fixture.catalog = Profile_Catalog_Definition {
		generation = 1,
		profiles = fixture.profiles[:],
		active_profile = 1,
		active_state = 1,
		surfaces = fixture.surfaces[:],
	}
}

@(private)
profile_compatibility_fixture_prepare_buildable :: proc(fixture: ^Profile_Compatibility_Fixture) {
	profile_compatibility_fixture_init(fixture)
	fixture.direct_bindings[0].sequence = scalar_sequence('a')
	fixture.direct_bindings[1].sequence = scalar_sequence('b')
	fixture.direct_bindings[1].command_name = "cursor-previous-grapheme"
	fixture.direct_maps[0].bindings = fixture.direct_bindings[:2]
	fixture.synthetic_maps[0] = Map_Definition {
		identity = {id = 2, revision = 1},
		name = "synthetic-base",
		precedence = .Profile_Base,
		unmatched_input_policy = .Reject,
		provenance = profile_compatibility_provenance(),
	}
	fixture.profiles[1].maps = fixture.synthetic_maps[:]
}

@(private)
profile_compatibility_state :: proc(
	id: u64,
	name: string,
	editing: bool,
) -> Interaction_State_Definition {
	effects: Command_Effects = {.Buffer, .View, .Lifecycle}
	if editing do effects += {.Text_Mutation}
	return Interaction_State_Definition {
		identity = {id = Interaction_State_ID(id), revision = 1},
		name = name,
		admits_text_input = editing,
		admitted_effects = effects,
		provenance = profile_compatibility_provenance(),
	}
}

@(private)
profile_compatibility_surface :: proc() -> Command_Entry_Surface_Definition {
	return Command_Entry_Surface_Definition {
		identity = {id = 1, revision = 1},
		name = "extended-command",
		provenance = profile_compatibility_provenance(),
	}
}

@(private)
profile_compatibility_provenance :: proc() -> Definition_Provenance {
	return Definition_Provenance {
		provider = "native",
		source = "profile compatibility test",
	}
}
