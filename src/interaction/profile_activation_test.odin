// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:testing"
import "core:time"
import "core:mem"

/* Verifies atomic activation, rollback, stale rejection, and pending invalidation. */
@(test)
replaces_only_complete_newer_candidates :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(201), context.allocator)
	if !ready {
		return
	}
	defer command_registry_close(&registry)

	bindings := [?]Layered_Binding_Definition {
		layered_binding('a', "cursor-previous-grapheme", .Bind),
	}
	maps := [?]Map_Definition {
		layered_map(1, "factory", .Factory_Fallback, 0, bindings[:]),
	}
	profile := layered_profile(21, maps[:])
	activation: Profile_Activation
	profile_activation_init(&activation)
	pending := Pending_State {
		snapshot_generation = Snapshot_Generation(99),
		stroke_count = 1,
	}
	published, failure := profile_activation_replace(
		&activation,
		&registry,
		profile,
		layered_active_context(1),
		&pending,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, published, "initial activation failed: %v", failure.code)
	testing.expect_value(t, pending.stroke_count, u8(0))
	active, active_ok := profile_activation_snapshot(&activation)
	testing.expect(t, active_ok)
	if active_ok {
		stats, stats_ok, _ := snapshot_stats(active)
		testing.expect(t, stats_ok)
		testing.expect_value(t, stats.generation, Snapshot_Generation(1))
	}

	pending.stroke_count = 1
	pending.snapshot_generation = Snapshot_Generation(1)
	_, failure = profile_activation_replace(
		&activation,
		&registry,
		profile,
		layered_active_context(1),
		&pending,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Profile)
	testing.expect_value(t, pending.stroke_count, u8(1))

	invalid_profile := profile
	invalid_profile.identity.revision = Profile_Revision(2)
	invalid_profile.maps = nil
	_, failure = profile_activation_replace(
		&activation,
		&registry,
		invalid_profile,
		layered_active_context(1),
		&pending,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expect_value(t, failure.code, Failure_Code.Map_Limit)
	testing.expect_value(t, pending.stroke_count, u8(1))
	active, active_ok = profile_activation_snapshot(&activation)
	if active_ok {
		stats, _, _ := snapshot_stats(active)
		testing.expect_value(t, stats.generation, Snapshot_Generation(1))
		testing.expect_value(t, stats.profile.revision, Profile_Revision(1))
	}

	profile.identity.revision = Profile_Revision(2)
	failing := Resolver_Failing_Allocator {
		backing = context.allocator,
		fail_after = 0,
	}
	_, failure = profile_activation_replace(
		&activation,
		&registry,
		profile,
		layered_active_context(1),
		&pending,
		DEFAULT_RESOLUTION_POLICY,
		resolver_failing_allocator(&failing),
	)
	testing.expect_value(t, failure.code, Failure_Code.Persistent_Memory_Limit)
	testing.expect_value(t, pending.stroke_count, u8(1))
	active, active_ok = profile_activation_snapshot(&activation)
	if active_ok {
		stats, _, _ := snapshot_stats(active)
		testing.expect_value(t, stats.generation, Snapshot_Generation(1))
	}

	published, failure = profile_activation_replace(
		&activation,
		&registry,
		profile,
		layered_active_context(1),
		&pending,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, published, "replacement activation failed: %v", failure.code)
	testing.expect_value(t, pending.stroke_count, u8(0))
	testing.expect_value(t, profile_activation_last_rejection(&activation).code, Failure_Code.None)
	active, active_ok = profile_activation_snapshot(&activation)
	if active_ok {
		stats, _, _ := snapshot_stats(active)
		testing.expect_value(t, stats.generation, Snapshot_Generation(2))
		testing.expect_value(t, stats.profile.revision, Profile_Revision(2))
	}
	for revision in 3 ..= 10 {
		profile.identity.revision = Profile_Revision(revision)
		pending.stroke_count = 1
		pending.snapshot_generation = activation.generation
		published, failure = profile_activation_replace(
			&activation,
			&registry,
			profile,
			layered_active_context(1),
			&pending,
			DEFAULT_RESOLUTION_POLICY,
			context.allocator,
		)
		testing.expectf(t, published, "repeated activation %d failed: %v", revision, failure.code)
		testing.expect_value(t, pending.stroke_count, u8(0))
	}
	active, active_ok = profile_activation_snapshot(&activation)
	if active_ok {
		stats, _, _ := snapshot_stats(active)
		testing.expect_value(t, stats.generation, Snapshot_Generation(10))
		testing.expect_value(t, stats.profile.revision, Profile_Revision(10))
	}

	closed, close_failure := profile_activation_close(&activation)
	testing.expectf(t, closed, "activation close failed: %v", close_failure.code)
	_, active_ok = profile_activation_snapshot(&activation)
	testing.expect(t, !active_ok)
}

/* Verifies repeated modal catalog replacement remains bounded and releases owned storage. */
@(test)
modal_replacement_is_bounded_and_released :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(204), context.allocator)
	if !ready do return
	defer command_registry_close(&registry)
	fixture: Profile_Compatibility_Fixture
	profile_compatibility_fixture_prepare_buildable(&fixture)
	fixture.profiles[1].name = "modal"
	fixture.navigation_states[0].name = "Normal"
	fixture.catalog.active_profile = 2
	fixture.catalog.active_state = 2
	active_context := layered_active_context(1)
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	activation: Profile_Activation
	profile_activation_init(&activation)
	pending: Pending_State
	published, failure := profile_activation_replace_catalog(
		&activation,
		&registry,
		fixture.catalog,
		active_context,
		&pending,
		DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		DEFAULT_RESOLUTION_POLICY,
		allocator,
	)
	testing.expectf(t, published, "initial modal catalog failed with %v", failure.code)
	if !published {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	baseline_bytes := tracking.current_memory_allocated
	peak_bytes := tracking.peak_memory_allocated
	for generation in 2 ..= 129 {
		modal_request := Modal_Pending_Request {
			kind = .Count,
			profile = fixture.profiles[1].identity,
			state = fixture.navigation_states[0].identity,
			catalog_generation = fixture.catalog.generation,
			snapshot_generation = activation.generation,
			ctx = active_context.identity,
			view_identity = 7,
			view_generation = 1,
			buffer_identity = 11,
			buffer_revision = u64(generation),
			sequence = scalar_sequence('9'),
			text = "9",
			count = 9,
		}
		started, pending_failure := profile_activation_modal_pending_begin(
			&activation,
			modal_request,
		)
		testing.expectf(t, started, "modal pending generation %d failed with %v", generation, pending_failure.code)
		pending.snapshot_generation = activation.generation
		pending.stroke_count = 1
		fixture.catalog.generation = Profile_Catalog_Generation(generation)
		published, failure = profile_activation_replace_catalog(
			&activation,
			&registry,
			fixture.catalog,
			active_context,
			&pending,
			DEFAULT_PROFILE_COMPATIBILITY_POLICY,
			DEFAULT_RESOLUTION_POLICY,
			allocator,
		)
		testing.expectf(t, published, "modal replacement %d failed with %v", generation, failure.code)
		testing.expect_value(t, pending.stroke_count, u8(0))
		modal_pending, inspected := profile_activation_modal_pending_inspect(&activation)
		testing.expect(t, inspected)
		testing.expect_value(t, modal_pending, Modal_Pending_State{})
		testing.expect_value(t, tracking.current_memory_allocated, baseline_bytes)
		peak_bytes = max(peak_bytes, tracking.peak_memory_allocated)
	}

	pending.snapshot_generation = activation.generation
	pending.stroke_count = 1
	fixture.catalog.generation += 1
	prior_profile, prior_state, selected := profile_activation_selection(&activation)
	failing := Resolver_Failing_Allocator {backing = allocator, fail_after = 0}
	_, failure = profile_activation_replace_catalog(
		&activation,
		&registry,
		fixture.catalog,
		active_context,
		&pending,
		DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		DEFAULT_RESOLUTION_POLICY,
		resolver_failing_allocator(&failing),
	)
	testing.expect_value(t, failure.code, Failure_Code.Persistent_Memory_Limit)
	testing.expect_value(t, pending.stroke_count, u8(1))
	profile, state, retained := profile_activation_selection(&activation)
	testing.expect(t, selected && retained)
	testing.expect_value(t, profile, prior_profile)
	testing.expect_value(t, state.identity, prior_state.identity)
	testing.expect_value(t, tracking.current_memory_allocated, baseline_bytes)
	testing.expect(t, peak_bytes >= baseline_bytes)
	closed, close_failure := profile_activation_close(&activation)
	testing.expectf(t, closed, "modal activation close failed with %v", close_failure.code)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies catalog activation isolates inactive bindings and projects explicit continuity. */
@(test)
publishes_one_selected_profile_and_state :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(202), context.allocator)
	if !ready {
		return
	}
	defer command_registry_close(&registry)

	fixture: Profile_Compatibility_Fixture
	profile_compatibility_fixture_init(&fixture)
	fixture.direct_bindings[0].sequence = scalar_sequence('a')
	fixture.direct_bindings[1].sequence = scalar_sequence('b')
	fixture.direct_bindings[1].command_name = "cursor-previous-grapheme"
	fixture.direct_maps[0].bindings = fixture.direct_bindings[:2]
	fixture.synthetic_maps[0] = Map_Definition {
		identity = fixture.direct_maps[0].identity,
		name = "synthetic-base",
		precedence = .Profile_Base,
		unmatched_input_policy = .Reject,
		provenance = profile_compatibility_provenance(),
	}
	fixture.profiles[1].maps = fixture.synthetic_maps[:]

	activation: Profile_Activation
	profile_activation_init(&activation)
	pending: Pending_State
	published, failure := profile_activation_replace_catalog(
		&activation,
		&registry,
		fixture.catalog,
		layered_active_context(1),
		&pending,
		DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, published, "direct catalog activation failed with %v", failure.code)
	if !published {
		return
	}
	profile, state, selected := profile_activation_selection(&activation)
	testing.expect(t, selected)
	testing.expect_value(t, profile.id, Profile_ID(1))
	testing.expect_value(t, state.identity.id, Interaction_State_ID(1))
	testing.expect_value(t, state.name, "direct-editing")
	insert_text, insert_found, _ := command_lookup(&registry, "insert-text")
	navigation, navigation_found, _ := command_lookup(&registry, "cursor-previous-grapheme")
	mutation, mutation_found, _ := command_lookup(&registry, "uppercase-current-line")
	testing.expect(t, insert_found && navigation_found && mutation_found)
	insert_admitted, _ := profile_activation_command_admit(&activation, &registry, insert_text)
	navigation_admitted, _ := profile_activation_command_admit(&activation, &registry, navigation)
	mutation_admitted, _ := profile_activation_command_admit(&activation, &registry, mutation)
	testing.expect(t, insert_admitted && navigation_admitted && mutation_admitted)

	fixture.catalog.generation = 2
	fixture.catalog.active_profile = 2
	fixture.catalog.active_state = 2
	pending.stroke_count = 1
	pending.snapshot_generation = activation.generation
	failing := Resolver_Failing_Allocator {
		backing = context.allocator,
		fail_after = 0,
	}
	_, failure = profile_activation_replace_catalog(
		&activation,
		&registry,
		fixture.catalog,
		layered_active_context(1),
		&pending,
		DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		DEFAULT_RESOLUTION_POLICY,
		resolver_failing_allocator(&failing),
	)
	testing.expect_value(t, failure.code, Failure_Code.Persistent_Memory_Limit)
	testing.expect_value(t, pending.stroke_count, u8(1))
	profile, state, selected = profile_activation_selection(&activation)
	testing.expect(t, selected)
	testing.expect_value(t, profile.id, Profile_ID(1))
	testing.expect_value(t, state.identity.id, Interaction_State_ID(1))
	published, failure = profile_activation_replace_catalog(
		&activation,
		&registry,
		fixture.catalog,
		layered_active_context(1),
		&pending,
		DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, published, "synthetic catalog activation failed with %v", failure.code)
	testing.expect_value(t, pending.stroke_count, u8(0))
	profile, state, selected = profile_activation_selection(&activation)
	testing.expect(t, selected)
	testing.expect_value(t, profile.id, Profile_ID(2))
	testing.expect_value(t, state.identity.id, Interaction_State_ID(2))
	insert_rejection, mutation_rejection: Failure_Context
	insert_admitted, insert_rejection = profile_activation_command_admit(
		&activation,
		&registry,
		insert_text,
	)
	navigation_admitted, _ = profile_activation_command_admit(&activation, &registry, navigation)
	mutation_admitted, mutation_rejection = profile_activation_command_admit(
		&activation,
		&registry,
		mutation,
	)
	testing.expect(t, !insert_admitted && navigation_admitted && !mutation_admitted)
	testing.expect_value(t, insert_rejection.code, Failure_Code.Command_Effect_Rejected)
	testing.expect_value(t, mutation_rejection.code, Failure_Code.Command_Effect_Rejected)
	testing.expect_value(t, mutation_rejection.profile.id, Profile_ID(2))
	testing.expect_value(t, mutation_rejection.state.id, Interaction_State_ID(2))

	snapshot, snapshot_ok := profile_activation_snapshot(&activation)
	testing.expect(t, snapshot_ok)
	if snapshot_ok {
		resolution_pending: Pending_State
		resolved, resolve_failure := resolve_input(
			snapshot,
			Registry_Generation(202),
			&resolution_pending,
			key_input(scalar_key('a')),
		)
		testing.expect_value(t, resolve_failure.code, Failure_Code.None)
		testing.expect_value(t, resolved.kind, Resolution_Kind.Unbound)
		resolved, resolve_failure = resolve_input(
			snapshot,
			Registry_Generation(202),
			&resolution_pending,
			Input{kind = .Key, stroke = scalar_key('x'), text = "x"},
		)
		testing.expect_value(t, resolve_failure.code, Failure_Code.Context_Input_Rejected)
		testing.expect_value(t, resolved.kind, Resolution_Kind.Rejected)
		resolved, resolve_failure = resolve_input(
			snapshot,
			Registry_Generation(202),
			&resolution_pending,
			key_input(scalar_key('b')),
		)
		testing.expect_value(t, resolve_failure.code, Failure_Code.None)
		testing.expect_value(t, resolved.kind, Resolution_Kind.Command)
	}

	pending.stroke_count = 1
	pending.snapshot_generation = activation.generation
	_, failure = profile_activation_replace_catalog(
		&activation,
		&registry,
		fixture.catalog,
		layered_active_context(1),
		&pending,
		DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Profile_Catalog)
	testing.expect_value(t, pending.stroke_count, u8(1))
	profile, state, selected = profile_activation_selection(&activation)
	testing.expect(t, selected)
	testing.expect_value(t, profile.id, Profile_ID(2))
	testing.expect_value(t, state.identity.id, Interaction_State_ID(2))

	closed, close_failure := profile_activation_close(&activation)
	testing.expectf(t, closed, "catalog activation close failed with %v", close_failure.code)
}

/* Verifies maximum profile membership activates one selected definition within the gate. */
@(test)
selects_from_generated_catalog_capacity :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(203), context.allocator)
	if !ready {
		return
	}
	defer command_registry_close(&registry)

	profiles: [MAX_INTERACTION_PROFILES]Profile_Definition
	states: [MAX_INTERACTION_PROFILES]Interaction_State_Definition
	maps: [MAX_INTERACTION_PROFILES]Map_Definition
	for index in 0 ..< MAX_INTERACTION_PROFILES {
		states[index] = Interaction_State_Definition {
			identity = {id = 1, revision = 1},
			name = "generated-editing",
			admits_text_input = true,
			admitted_effects = {.Buffer, .View, .Lifecycle, .Text_Mutation},
			provenance = layered_test_provenance(),
		}
		maps[index] = Map_Definition {
			identity = {id = 1, revision = 1},
			name = "generated-base",
			precedence = .Profile_Base,
			unmatched_input_policy = .Text_Input,
			provenance = layered_test_provenance(),
		}
		profiles[index] = Profile_Definition {
			identity = {id = Profile_ID(index + 1), revision = 1},
			name = "generated-profile",
			states = states[index:index + 1],
			initial_state = 1,
			maps = maps[index:index + 1],
			text_fallback_name = "insert-text",
		}
	}
	surfaces := [1]Command_Entry_Surface_Definition {{
		identity = {id = 1, revision = 1},
		name = "extended-command",
		provenance = layered_test_provenance(),
	}}
	catalog := Profile_Catalog_Definition {
		generation = 1,
		profiles = profiles[:],
		active_profile = MAX_INTERACTION_PROFILES,
		active_state = 1,
		surfaces = surfaces[:],
	}
	activation: Profile_Activation
	profile_activation_init(&activation)
	pending: Pending_State
	started := time.tick_now()
	published, failure := profile_activation_replace_catalog(
		&activation,
		&registry,
		catalog,
		layered_active_context(1),
		&pending,
		DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
	testing.expectf(t, published, "generated activation failed with %v", failure.code)
	testing.expectf(t, elapsed_ns < 15_000_000, "generated activation exceeded gate: %d ns", elapsed_ns)
	if published {
		profile, state, selected := profile_activation_selection(&activation)
		testing.expect(t, selected)
		testing.expect_value(t, profile.id, Profile_ID(MAX_INTERACTION_PROFILES))
		testing.expect_value(t, state.identity.id, Interaction_State_ID(1))
	}
	closed, close_failure := profile_activation_close(&activation)
	testing.expectf(t, closed, "generated activation close failed with %v", close_failure.code)
}
