// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:mem"
import "core:testing"
import "core:time"

/* Verifies copied inspection of winners, shadows, masks, remaps, and protected entries. */
@(test)
keymap_explains_active_profile :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(301), context.allocator)
	if !ready {
		return
	}

	factory_bindings := [?]Layered_Binding_Definition {
		layered_binding('a', "cursor-previous-grapheme", .Bind),
		layered_binding('d', "cursor-previous-grapheme", .Bind),
	}
	user_bindings := [?]Layered_Binding_Definition {
		layered_binding('a', "request-editor-exit", .Bind),
	}
	component_bindings := [?]Layered_Binding_Definition {
		layered_binding('b', "", .Mask),
		layered_binding('c', "cursor-previous-grapheme", .Bind),
	}
	inactive_bindings := [?]Layered_Binding_Definition {
		layered_binding('e', "cursor-previous-grapheme", .Bind),
	}
	remaps := [?]Command_Remap_Definition {{
		from_command_name = "cursor-previous-grapheme",
		to_command_name = "uppercase-current-line",
		provenance = layered_test_provenance(),
	}}
	maps := [?]Map_Definition {
		layered_map(1, "factory", .Factory_Fallback, 0, factory_bindings[:]),
		layered_map(2, "user", .User_Global, 0, user_bindings[:]),
		layered_map(3, "component", .Component_Tool, 0, component_bindings[:]),
		layered_map(4, "inactive", .Buffer_Local, 0, inactive_bindings[:]),
	}
	maps[2].remaps = remaps[:]
	inactive_owner := Owner_Handle{id = Owner_ID(44), generation = Owner_Generation(1)}
	maps[3].owner = inactive_owner
	maps[3].context_requirement = Context_Requirement {
		ctx = Context_Handle{id = Context_ID(41), generation = Context_Generation(1)},
		owner = inactive_owner,
	}
	profile := layered_profile(31, maps[:])
	activation: Profile_Activation
	profile_activation_init(&activation)
	pending: Pending_State
	published, failure := profile_activation_replace(
		&activation,
		&registry,
		profile,
		Active_Context {
			identity = Context_Handle{id = Context_ID(41), generation = Context_Generation(1)},
		},
		&pending,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, published, "profile activation failed: %v", failure.code)
	if !published {
		command_registry_close(&registry)
		return
	}

	sequence_result, inspected, inspect_failure := keymap_inspect(
		&registry,
		&activation,
		&pending,
		Inspection_Query{kind = .Sequence, sequence = scalar_sequence('a')},
		context.allocator,
	)
	testing.expectf(t, inspected, "sequence inspection failed: %v", inspect_failure.code)
	if inspected {
		testing.expect_value(t, len(sequence_result.records), 2)
		if len(sequence_result.records) == 2 {
			testing.expect_value(t, sequence_result.records[0].map_name, "user")
			testing.expect_value(t, sequence_result.records[0].command_name, "request-editor-exit")
			testing.expect_value(t, sequence_result.records[0].disposition, Inspection_Disposition.Effective)
			testing.expect_value(t, sequence_result.records[1].map_name, "factory")
			testing.expect_value(t, sequence_result.records[1].disposition, Inspection_Disposition.Shadowed)
		}
		testing.expect(t, inspection_result_close(&sequence_result))
	}

	mask_result, mask_inspected, _ := keymap_inspect(
		&registry,
		&activation,
		&pending,
		Inspection_Query{kind = .Sequence, sequence = scalar_sequence('b')},
		context.allocator,
	)
	if mask_inspected {
		testing.expect_value(t, len(mask_result.records), 1)
		if len(mask_result.records) == 1 {
			testing.expect_value(t, mask_result.records[0].disposition, Inspection_Disposition.Masked)
			testing.expect_value(t, mask_result.records[0].operation, Binding_Operation.Mask)
		}
		inspection_result_close(&mask_result)
	}

	command_result, command_inspected, _ := keymap_inspect(
		&registry,
		&activation,
		&pending,
		Inspection_Query {
			kind = .Command,
			command_name = "cursor-previous-grapheme",
			include_inactive = true,
		},
		context.allocator,
	)
	if command_inspected {
		binding_count := 0
		remap_count := 0
		inactive_count := 0
		for record in command_result.records {
			switch record.kind {
			case .Binding:
				binding_count += 1
				if record.disposition == .Inactive {
					inactive_count += 1
				}
			case .Remap:
				remap_count += 1
				testing.expect_value(t, record.original_command_name, "cursor-previous-grapheme")
				testing.expect_value(t, record.remap_target_name, "uppercase-current-line")
			case .Invalid, .Map, .Snapshot, .Catalog, .Profile, .State, .Surface, .Rejection:
			}
		}
		testing.expect_value(t, binding_count, 4)
		testing.expect_value(t, remap_count, 1)
		testing.expect_value(t, inactive_count, 1)
		inspection_result_close(&command_result)
	}

	map_result, map_inspected, _ := keymap_inspect(
		&registry,
		&activation,
		&pending,
		Inspection_Query{kind = .Map, map_id = Map_ID(3)},
		context.allocator,
	)
	if map_inspected {
		testing.expect_value(t, len(map_result.records), 4)
		if len(map_result.records) > 0 {
			testing.expect_value(t, map_result.records[0].kind, Inspection_Record_Kind.Map)
			testing.expect_value(t, map_result.records[0].map_name, "component")
		}
		inspection_result_close(&map_result)
	}

	active_maps, maps_inspected, _ := keymap_inspect(
		&registry,
		&activation,
		&pending,
		Inspection_Query{kind = .Active_Maps},
		context.allocator,
	)
	if maps_inspected {
		testing.expect_value(t, len(active_maps.records), 4)
		testing.expect_value(t, active_maps.usage.map_count, u16(5))
		testing.expect_value(t, active_maps.usage.active_map_count, u16(4))
		inspection_result_close(&active_maps)
	}

	pending = Pending_State {
		snapshot_generation = activation.generation,
		strokes = {0 = control_key('x')},
		stroke_count = 1,
	}
	snapshot_result, snapshot_inspected, _ := keymap_inspect(
		&registry,
		&activation,
		&pending,
		Inspection_Query{kind = .Snapshot},
		context.allocator,
	)
	if snapshot_inspected {
		testing.expect_value(t, snapshot_result.snapshot.generation, Snapshot_Generation(1))
		testing.expect_value(t, snapshot_result.snapshot.registry_generation, Registry_Generation(301))
		testing.expect_value(t, snapshot_result.pending.stroke_count, u8(1))
		testing.expect_value(t, snapshot_result.usage.inspection_records, u16(1))
		inspection_result_close(&snapshot_result)
	}

	profile_activation_replace(
		&activation,
		&registry,
		profile,
		layered_active_context(41),
		&pending,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	rejection_result, rejection_inspected, _ := keymap_inspect(
		&registry,
		&activation,
		&pending,
		Inspection_Query{kind = .Latest_Rejection},
		context.allocator,
	)
	if rejection_inspected {
		testing.expect_value(t, len(rejection_result.records), 1)
		if len(rejection_result.records) == 1 {
			testing.expect_value(t, rejection_result.records[0].kind, Inspection_Record_Kind.Rejection)
			testing.expect_value(t, rejection_result.records[0].failure.code, Failure_Code.Stale_Profile)
		}
		inspection_result_close(&rejection_result)
	}

	protected_result, protected_inspected, _ := keymap_inspect(
		&registry,
		&activation,
		&pending,
		Inspection_Query{kind = .Sequence, sequence = protected_control_sequence('g')},
		context.allocator,
	)
	testing.expect(t, protected_inspected)
	if !protected_inspected {
		profile_activation_close(&activation)
		command_registry_close(&registry)
		return
	}
	testing.expect_value(t, len(protected_result.records), 1)
	if len(protected_result.records) == 1 {
		testing.expect(t, protected_result.records[0].protected)
		testing.expect_value(t, protected_result.records[0].command_name, "keyboard-quit")
		testing.expect(t, len(protected_result.records[0].protection_reason) > 0)
	}
	profile_activation_close(&activation)
	command_registry_close(&registry)
	if len(protected_result.records) == 1 {
		testing.expect_value(t, protected_result.records[0].map_name, "protected-recovery")
		testing.expect_value(t, protected_result.records[0].provenance.provider, "native")
	}
	testing.expect(t, inspection_result_close(&protected_result))
}

/* Verifies catalog inspection copies profile, state, scope, selectors, admission, and surfaces. */
@(test)
compatibility_explains_profile_states :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(305), context.allocator)
	if !ready do return
	defer command_registry_close(&registry)
	fixture: Profile_Compatibility_Fixture
	profile_compatibility_fixture_prepare_buildable(&fixture)
	activation: Profile_Activation
	profile_activation_init(&activation)
	pending: Pending_State
	published, publish_failure := profile_activation_replace_catalog(
		&activation,
		&registry,
		fixture.catalog,
		layered_active_context(1),
		&pending,
		DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, published, "catalog activation failed: %v", publish_failure.code)
	if !published do return

	compatibility, inspected, inspect_failure := keymap_inspect(
		&registry,
		&activation,
		&pending,
		Inspection_Query{kind = .Compatibility},
		context.allocator,
	)
	testing.expectf(t, inspected, "compatibility inspection failed: %v", inspect_failure.code)
	if !inspected {
		profile_activation_close(&activation)
		return
	}
	testing.expect_value(t, len(compatibility.records), 7)
	testing.expect_value(t, compatibility.catalog_generation, Profile_Catalog_Generation(1))
	testing.expect_value(t, compatibility.active_state.id, Interaction_State_ID(1))
	profile_records, state_records, inactive_records, surface_records := 0, 0, 0, 0
	for record in compatibility.records {
		switch record.kind {
		case .Profile:
			profile_records += 1
			if record.profile.id == Profile_ID(2) {
				testing.expect_value(t, record.profile_name, "synthetic")
				testing.expect_value(t, record.disposition, Inspection_Disposition.Inactive)
			}
		case .State:
			state_records += 1
			if record.state.id == Interaction_State_ID(2) {
				testing.expect_value(t, record.state_name, "synthetic-navigation")
				testing.expect(t, !record.state_admits_text_input)
			}
		case .Surface:
			surface_records += 1
			testing.expect_value(t, record.command_entry_surface_name, "extended-command")
		case .Catalog, .Snapshot:
		case .Invalid, .Binding, .Remap, .Map, .Rejection:
		}
		if record.disposition == .Inactive do inactive_records += 1
	}
	testing.expect_value(t, profile_records, 2)
	testing.expect_value(t, state_records, 2)
	testing.expect_value(t, inactive_records, 2)
	testing.expect_value(t, surface_records, 1)

	shared, shared_inspected, _ := keymap_inspect(
		&registry,
		&activation,
		&pending,
		Inspection_Query{kind = .Sequence, sequence = scalar_sequence('b')},
		context.allocator,
	)
	testing.expect(t, shared_inspected)
	if shared_inspected {
		testing.expect_value(t, len(shared.records), 1)
		if len(shared.records) == 1 {
			record := shared.records[0]
			testing.expect_value(t, record.binding_scope, Binding_Scope.Shared_Continuity)
			testing.expect_value(t, record.profile_name, "direct")
			testing.expect_value(t, record.state_name, "direct-editing")
			testing.expect(t, record.effects_admitted)
			testing.expect_value(t, len(record.selectors), 2)
		}
	}

	command_result, command_inspected, _ := keymap_inspect(
		&registry,
		&activation,
		&pending,
		Inspection_Query{kind = .Command, command_name = "cursor-previous-grapheme"},
		context.allocator,
	)
	testing.expect(t, command_inspected)
	if command_inspected {
		testing.expect_value(t, len(command_result.records), 2)
		if len(command_result.records) == 2 {
			testing.expect_value(t, command_result.records[1].kind, Inspection_Record_Kind.Surface)
			testing.expect_value(t, command_result.records[1].command_name, "cursor-previous-grapheme")
			testing.expect(t, command_result.records[1].effects_admitted)
		}
	}

	closed, close_failure := profile_activation_close(&activation)
	testing.expectf(t, closed, "activation close failed: %v", close_failure.code)
	if shared_inspected && len(shared.records) == 1 {
		testing.expect_value(t, shared.records[0].profile_name, "direct")
		testing.expect_value(t, len(shared.records[0].selectors), 2)
		testing.expect(t, inspection_result_close(&shared))
	}
	if command_inspected do testing.expect(t, inspection_result_close(&command_result))
	testing.expect_value(t, compatibility.records[5].state_name, "synthetic-navigation")
	testing.expect(t, inspection_result_close(&compatibility))
}

/* Verifies rejected shared candidates retain exact copied compatibility context. */
@(test)
compatibility_copies_rejection_context :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(306), context.allocator)
	if !ready do return
	defer command_registry_close(&registry)
	fixture: Profile_Compatibility_Fixture
	profile_compatibility_fixture_prepare_buildable(&fixture)
	activation: Profile_Activation
	profile_activation_init(&activation)
	defer profile_activation_close(&activation)
	pending: Pending_State
	published, _ := profile_activation_replace_catalog(
		&activation,
		&registry,
		fixture.catalog,
		layered_active_context(1),
		&pending,
		DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expect(t, published)
	if !published do return
	before_snapshot, before_ok := profile_activation_snapshot(&activation)
	before, before_stats_ok, _ := snapshot_stats(before_snapshot)
	testing.expect(t, before_ok && before_stats_ok)

	fixture.catalog.generation = 2
	fixture.direct_bindings[1].command_name = "uppercase-current-line"
	_, rejected := profile_activation_replace_catalog(
		&activation,
		&registry,
		fixture.catalog,
		layered_active_context(1),
		&pending,
		DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expect_value(t, rejected.code, Failure_Code.Incompatible_Shared_Binding)
	testing.expect_value(t, rejected.catalog_generation, Profile_Catalog_Generation(2))
	testing.expect_value(t, rejected.profile.id, Profile_ID(2))
	testing.expect_value(t, rejected.state.id, Interaction_State_ID(2))
	testing.expect_value(t, rejected.binding_scope, Binding_Scope.Shared_Continuity)
	testing.expect_value(t, rejected.selector_index, u32(1))

	result, inspected, inspect_failure := keymap_inspect(
		&registry,
		&activation,
		&pending,
		Inspection_Query{kind = .Latest_Rejection},
		context.allocator,
	)
	testing.expectf(t, inspected, "rejection inspection failed: %v", inspect_failure.code)
	if inspected {
		testing.expect_value(t, len(result.records), 1)
		if len(result.records) == 1 {
			record := result.records[0]
			testing.expect_value(t, record.catalog_generation, Profile_Catalog_Generation(2))
			testing.expect_value(t, record.profile_name, "synthetic")
			testing.expect_value(t, record.state_name, "synthetic-navigation")
			testing.expect_value(t, record.failure.binding_scope, Binding_Scope.Shared_Continuity)
		}
		testing.expect(t, inspection_result_close(&result))
	}
	after_snapshot, after_ok := profile_activation_snapshot(&activation)
	after, after_stats_ok, _ := snapshot_stats(after_snapshot)
	testing.expect(t, after_ok && after_stats_ok)
	testing.expect_value(t, after.generation, before.generation)
	testing.expect_value(t, after.storage_bytes, before.storage_bytes)
}

/* Verifies copied selectors and text clean up across every inspection allocation fault. */
@(test)
compatibility_alloc_faults_keep_activation :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	failing := Resolver_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = max(u64),
	}
	allocator := resolver_failing_allocator(&failing)
	registry, ready := layered_test_registry(t, Registry_Generation(307), allocator)
	if !ready do return
	fixture: Profile_Compatibility_Fixture
	profile_compatibility_fixture_prepare_buildable(&fixture)
	activation: Profile_Activation
	profile_activation_init(&activation)
	pending: Pending_State
	published, _ := profile_activation_replace_catalog(
		&activation,
		&registry,
		fixture.catalog,
		layered_active_context(1),
		&pending,
		DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		DEFAULT_RESOLUTION_POLICY,
		allocator,
	)
	testing.expect(t, published)
	if !published {
		command_registry_close(&registry)
		return
	}
	baseline := tracking.current_memory_allocated
	completed := false
	for fail_offset in 0 ..< 12 {
		failing.fail_after = failing.successful_allocations + u64(fail_offset)
		result, inspected, failure := keymap_inspect(
			&registry,
			&activation,
			&pending,
			Inspection_Query{kind = .Sequence, sequence = scalar_sequence('b')},
			allocator,
		)
		if inspected {
			completed = true
			testing.expect_value(t, len(result.records), 1)
			testing.expect_value(t, len(result.records[0].selectors), 2)
			testing.expect(t, inspection_result_close(&result))
			break
		}
		testing.expect_value(t, failure.code, Failure_Code.Persistent_Memory_Limit)
		testing.expect_value(t, tracking.current_memory_allocated, baseline)
	}
	testing.expect(t, completed)
	failing.fail_after = max(u64)
	profile, state, selected := profile_activation_selection(&activation)
	testing.expect(t, selected)
	testing.expect_value(t, profile.id, Profile_ID(1))
	testing.expect_value(t, state.identity.id, Interaction_State_ID(1))
	profile_activation_close(&activation)
	command_registry_close(&registry)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies maximum generated membership rejects one oversized projection without state loss. */
@(test)
compatibility_bounds_catalog_projection :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(308), context.allocator)
	if !ready do return
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
	defer profile_activation_close(&activation)
	pending: Pending_State
	policy := DEFAULT_RESOLUTION_POLICY
	policy.max_inspection_alternatives = 64
	published, _ := profile_activation_replace_catalog(
		&activation,
		&registry,
		catalog,
		layered_active_context(1),
		&pending,
		DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		policy,
		context.allocator,
	)
	testing.expect(t, published)
	if !published do return
	started := time.tick_now()
	_, inspected, failure := keymap_inspect(
		&registry,
		&activation,
		&pending,
		Inspection_Query{kind = .Compatibility},
		context.allocator,
	)
	elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
	testing.expect(t, !inspected)
	testing.expect_value(t, failure.code, Failure_Code.Inspection_Limit)
	testing.expect_value(t, failure.limit, u64(policy.max_inspection_alternatives))
	testing.expect_value(t, failure.actual, u64(67))
	testing.expectf(t, elapsed_ns < 15_000_000, "bounded inspection exceeded gate: %d ns", elapsed_ns)
	profile, state, selected := profile_activation_selection(&activation)
	testing.expect(t, selected)
	testing.expect_value(t, profile.id, Profile_ID(MAX_INTERACTION_PROFILES))
	testing.expect_value(t, state.identity.id, Interaction_State_ID(1))
}

/* Verifies invalid selectors and inspection allocation failures are contained. */
@(test)
keymap_rejects_bad_queries_and_alloc :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(302), context.allocator)
	if !ready {
		return
	}
	defer command_registry_close(&registry)
	bindings := [?]Layered_Binding_Definition {
		layered_binding('a', "cursor-previous-grapheme", .Bind),
	}
	maps := [?]Map_Definition {
		layered_map(51, "factory", .Factory_Fallback, 0, bindings[:]),
	}
	activation: Profile_Activation
	profile_activation_init(&activation)
	defer profile_activation_close(&activation)
	pending: Pending_State
	published, _ := profile_activation_replace(
		&activation,
		&registry,
		layered_profile(51, maps[:]),
		layered_active_context(51),
		&pending,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	if !published {
		return
	}

	_, inspected, failure := keymap_inspect(
		&registry,
		&activation,
		&pending,
		Inspection_Query{kind = .Invalid},
		context.allocator,
	)
	testing.expect(t, !inspected)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Input)

	failing := Resolver_Failing_Allocator{backing = context.allocator, fail_after = 0}
	_, inspected, failure = keymap_inspect(
		&registry,
		&activation,
		&pending,
		Inspection_Query{kind = .Snapshot},
		resolver_failing_allocator(&failing),
	)
	testing.expect(t, !inspected)
	testing.expect_value(t, failure.code, Failure_Code.Persistent_Memory_Limit)
}

/* Verifies configured inspection bounds reject excess alternatives without replacing state. */
@(test)
keymap_enforces_alternative_limit :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(303), context.allocator)
	if !ready {
		return
	}
	defer command_registry_close(&registry)
	factory_bindings := [?]Layered_Binding_Definition {
		layered_binding('a', "cursor-previous-grapheme", .Bind),
	}
	user_bindings := [?]Layered_Binding_Definition {
		layered_binding('a', "request-editor-exit", .Bind),
	}
	maps := [?]Map_Definition {
		layered_map(61, "factory", .Factory_Fallback, 0, factory_bindings[:]),
		layered_map(62, "user", .User_Global, 0, user_bindings[:]),
	}
	policy := DEFAULT_RESOLUTION_POLICY
	policy.max_inspection_alternatives = 1
	activation: Profile_Activation
	profile_activation_init(&activation)
	defer profile_activation_close(&activation)
	pending: Pending_State
	published, publish_failure := profile_activation_replace(
		&activation,
		&registry,
		layered_profile(61, maps[:]),
		layered_active_context(61),
		&pending,
		policy,
		context.allocator,
	)
	testing.expectf(t, published, "bounded profile failed: %v", publish_failure.code)
	if !published {
		return
	}
	before_snapshot, before_active := profile_activation_snapshot(&activation)
	testing.expect(t, before_active)
	before, before_ok, _ := snapshot_stats(before_snapshot)
	testing.expect(t, before_ok)

	_, inspected, failure := keymap_inspect(
		&registry,
		&activation,
		&pending,
		Inspection_Query{kind = .Sequence, sequence = scalar_sequence('a')},
		context.allocator,
	)
	testing.expect(t, !inspected)
	testing.expect_value(t, failure.code, Failure_Code.Inspection_Limit)
	testing.expect_value(t, failure.limit, u64(1))
	testing.expect_value(t, failure.actual, u64(2))
	after_snapshot, after_active := profile_activation_snapshot(&activation)
	testing.expect(t, after_active)
	after, after_ok, _ := snapshot_stats(after_snapshot)
	testing.expect(t, after_ok)
	testing.expect_value(t, after.generation, before.generation)
	testing.expect_value(t, after.storage_bytes, before.storage_bytes)
}

/* Verifies the default inspection bound covers profiles larger than the former fixed draft. */
@(test)
keymap_inspects_complete_admitted_profile :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(305), context.allocator)
	if !ready {
		return
	}
	defer command_registry_close(&registry)
	bindings: [2][80]Layered_Binding_Definition
	maps: [2]Map_Definition
	for map_index in 0 ..< len(maps) {
		for binding_index in 0 ..< len(bindings[map_index]) {
			bindings[map_index][binding_index] = layered_binding(
				rune(0x5000 + map_index * len(bindings[map_index]) + binding_index),
				"cursor-previous-grapheme",
				.Bind,
			)
		}
		maps[map_index] = layered_map(
			u64(80 + map_index),
			"complete-inspection",
			Precedence_Class(int(Precedence_Class.Factory_Fallback) + map_index),
			0,
			bindings[map_index][:],
		)
	}
	activation: Profile_Activation
	profile_activation_init(&activation)
	defer profile_activation_close(&activation)
	pending: Pending_State
	published, publish_failure := profile_activation_replace(
		&activation,
		&registry,
		layered_profile(80, maps[:]),
		layered_active_context(80),
		&pending,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, published, "large profile failed: %v", publish_failure.code)
	if !published do return
	result, inspected, failure := keymap_inspect(
		&registry,
		&activation,
		&pending,
		Inspection_Query{kind = .Bindings},
		context.allocator,
	)
	testing.expectf(t, inspected, "complete inspection failed: %v", failure.code)
	if !inspected do return
	defer inspection_result_close(&result)
	testing.expectf(t, len(result.records) > 128, "expected more than 128 records, got %d", len(result.records))
}

/* Verifies every inspection allocation is recoverable and copied storage is released. */
@(test)
keymap_alloc_faults_release_storage :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	failing := Resolver_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = max(u64),
	}
	allocator := resolver_failing_allocator(&failing)
	registry, ready := layered_test_registry(t, Registry_Generation(304), allocator)
	if !ready {
		return
	}
	bindings := [?]Layered_Binding_Definition {
		layered_binding('a', "cursor-previous-grapheme", .Bind),
	}
	maps := [?]Map_Definition {
		layered_map(71, "fault", .Factory_Fallback, 0, bindings[:]),
	}
	activation: Profile_Activation
	profile_activation_init(&activation)
	pending: Pending_State
	published, publish_failure := profile_activation_replace(
		&activation,
		&registry,
		layered_profile(71, maps[:]),
		layered_active_context(71),
		&pending,
		DEFAULT_RESOLUTION_POLICY,
		allocator,
	)
	testing.expectf(t, published, "fault profile failed: %v", publish_failure.code)
	if !published {
		command_registry_close(&registry)
		return
	}

	completed := false
	for fail_offset in 0 ..< 8 {
		failing.fail_after = failing.successful_allocations + u64(fail_offset)
		result, inspected, failure := keymap_inspect(
			&registry,
			&activation,
			&pending,
			Inspection_Query{kind = .Sequence, sequence = scalar_sequence('a')},
			allocator,
		)
		if inspected {
			completed = true
			testing.expect(t, inspection_result_close(&result))
			break
		}
		testing.expect_value(t, failure.code, Failure_Code.Persistent_Memory_Limit)
	}
	testing.expect(t, completed)
	failing.fail_after = max(u64)
	profile_activation_close(&activation)
	command_registry_close(&registry)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}
