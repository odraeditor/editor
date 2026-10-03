// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:mem"
import "core:testing"

/* Verifies layered precedence, masks, remaps, prefixes, and retained shadows. */
@(test)
layered_snapshot_resolves_the_highest_active_map :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(101), context.allocator)
	if !ready {
		return
	}
	defer command_registry_close(&registry)

	shared := layered_binding('a', "cursor-previous-grapheme", .Bind)
	factory_bindings := [?]Layered_Binding_Definition {
		shared,
		layered_binding('d', "cursor-previous-grapheme", .Bind),
		layered_sequence_binding(
			Key_Sequence {
				strokes = {0 = control_key('x'), 1 = scalar_key('u')},
				stroke_count = 2,
			},
			"uppercase-current-line",
			.Bind,
		),
	}
	user_bindings := [?]Layered_Binding_Definition {
		layered_binding('a', "request-editor-exit", .Bind),
	}
	component_bindings := [?]Layered_Binding_Definition {
		layered_binding('b', "", .Mask),
		layered_binding('c', "cursor-previous-grapheme", .Bind),
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
	}
	maps[2].remaps = remaps[:]
	profile := layered_profile(1, maps[:])
	snapshot: Resolution_Snapshot
	compiled, failure := profile_snapshot_compile(
		&snapshot,
		&registry,
		Snapshot_Generation(1),
		profile,
		layered_active_context(1),
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, compiled, "layered compilation failed: %v", failure.code)
	if !compiled {
		return
	}
	defer snapshot_close(&snapshot)

	exit_command, exit_ok, _ := command_lookup(&registry, "request-editor-exit")
	uppercase, uppercase_ok, _ := command_lookup(&registry, "uppercase-current-line")
	testing.expect(t, exit_ok && uppercase_ok)

	pending: Pending_State
	resolved, resolve_failure := resolve_input(
		&snapshot,
		Registry_Generation(101),
		&pending,
		key_input(scalar_key('a')),
	)
	testing.expect_value(t, resolve_failure.code, Failure_Code.None)
	testing.expect_value(t, resolved.kind, Resolution_Kind.Command)
	testing.expect_value(t, resolved.command, exit_command)

	resolved, _ = resolve_input(
		&snapshot,
		Registry_Generation(101),
		&pending,
		key_input(scalar_key('b')),
	)
	testing.expect_value(t, resolved.kind, Resolution_Kind.Unbound)

	resolved, _ = resolve_input(
		&snapshot,
		Registry_Generation(101),
		&pending,
		key_input(scalar_key('c')),
	)
	testing.expect_value(t, resolved.kind, Resolution_Kind.Command)
	testing.expect_value(t, resolved.command, uppercase)
	resolved, _ = resolve_input(
		&snapshot,
		Registry_Generation(101),
		&pending,
		key_input(scalar_key('d')),
	)
	testing.expect_value(t, resolved.kind, Resolution_Kind.Command)
	testing.expect_value(t, resolved.command, uppercase)

	resolved, _ = resolve_input(
		&snapshot,
		Registry_Generation(101),
		&pending,
		key_input(control_key('x')),
	)
	testing.expect_value(t, resolved.kind, Resolution_Kind.Pending)

	data := snapshot_data(&snapshot)
	testing.expect(t, data != nil && data.layered)
	if data != nil {
		testing.expect_value(t, data.map_count, u16(4))
		testing.expect_value(t, data.active_map_count, u16(4))
		testing.expect_value(t, layered_definition_count(data, scalar_sequence('a')), 2)
	}
}

/* Verifies explicit same-class order is deterministic and cycles are rejected atomically. */
@(test)
layered_snapshot_enforces_declared_map_order :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(102), context.allocator)
	if !ready {
		return
	}
	defer command_registry_close(&registry)
	left_bindings := [?]Layered_Binding_Definition {
		layered_binding('a', "cursor-previous-grapheme", .Bind),
	}
	right_bindings := [?]Layered_Binding_Definition {
		layered_binding('a', "request-editor-exit", .Bind),
	}
	left_before_right := [?]Ordering_Constraint{{relation = .Before, other = Map_ID(12)}}
	maps := [?]Map_Definition {
		layered_map(11, "left", .User_Global, 0, left_bindings[:]),
		layered_map(12, "right", .User_Global, 0, right_bindings[:]),
	}
	maps[0].ordering_constraints = left_before_right[:]
	snapshot: Resolution_Snapshot
	compiled, failure := profile_snapshot_compile(
		&snapshot,
		&registry,
		Snapshot_Generation(2),
		layered_profile(2, maps[:]),
		layered_active_context(2),
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, compiled, "ordered profile failed: %v", failure.code)
	if !compiled {
		return
	}
	defer snapshot_close(&snapshot)

	left_command, found, _ := command_lookup(&registry, "cursor-previous-grapheme")
	testing.expect(t, found)
	pending: Pending_State
	resolved, _ := resolve_input(
		&snapshot,
		Registry_Generation(102),
		&pending,
		key_input(scalar_key('a')),
	)
	testing.expect_value(t, resolved.command, left_command)

	right_before_left := [?]Ordering_Constraint{{relation = .Before, other = Map_ID(11)}}
	maps[1].ordering_constraints = right_before_left[:]
	before, _, _ := snapshot_stats(&snapshot)
	replaced, cycle_failure := profile_snapshot_compile(
		&snapshot,
		&registry,
		Snapshot_Generation(3),
		layered_profile(3, maps[:]),
		layered_active_context(3),
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expect(t, !replaced)
	testing.expect_value(t, cycle_failure.code, Failure_Code.Ordering_Cycle)
	after, _, _ := snapshot_stats(&snapshot)
	testing.expect_value(t, after.generation, before.generation)
}

/* Verifies collisions, exact-prefix ambiguity, stale owners, and protected overlap fail. */
@(test)
layered_snapshot_rejects_invalid_composition :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(103), context.allocator)
	if !ready {
		return
	}
	defer command_registry_close(&registry)

	shared_left := [?]Layered_Binding_Definition {
		layered_binding('a', "cursor-previous-grapheme", .Bind),
	}
	shared_right := [?]Layered_Binding_Definition {
		layered_binding('a', "request-editor-exit", .Bind),
	}
	collision_maps := [?]Map_Definition {
		layered_map(21, "one", .Project, 7, shared_left[:]),
		layered_map(22, "two", .Project, 7, shared_right[:]),
	}
	expect_layered_compile_failure(
		t,
		&registry,
		layered_profile(4, collision_maps[:]),
		layered_active_context(4),
		Failure_Code.Ordering_Conflict,
	)

	prefix_bindings := [?]Layered_Binding_Definition {
		layered_binding('a', "cursor-previous-grapheme", .Bind),
		layered_sequence_binding(
			Key_Sequence {
				strokes = {0 = scalar_key('a'), 1 = scalar_key('b')},
				stroke_count = 2,
			},
			"request-editor-exit",
			.Bind,
		),
	}
	prefix_maps := [?]Map_Definition {
		layered_map(23, "prefix", .Project, 8, prefix_bindings[:]),
	}
	expect_layered_compile_failure(
		t,
		&registry,
		layered_profile(5, prefix_maps[:]),
		layered_active_context(5),
		Failure_Code.Ambiguous_Binding,
	)

	owner_bindings := [?]Layered_Binding_Definition {
		layered_binding('z', "cursor-previous-grapheme", .Bind),
	}
	owner_maps := [?]Map_Definition {
		layered_map(24, "owned", .Component_Tool, 0, owner_bindings[:]),
	}
	owner_maps[0].owner = Owner_Handle{id = Owner_ID(9), generation = Owner_Generation(1)}
	owner_maps[0].context_requirement = Context_Requirement {
		ctx = Context_Handle{id = Context_ID(6), generation = Context_Generation(6)},
		owner = owner_maps[0].owner,
	}
	stale_owners := [?]Owner_Handle{{id = Owner_ID(9), generation = Owner_Generation(2)}}
	expect_layered_compile_failure(
		t,
		&registry,
		layered_profile(6, owner_maps[:]),
		Active_Context {
			identity = Context_Handle{id = Context_ID(6), generation = Context_Generation(6)},
			owners = stale_owners[:],
		},
		Failure_Code.Stale_Owner,
	)

	protected_maps := [?]Map_Definition {
		layered_map(25, "recovery", .Protected_Recovery, 0, shared_left[:]),
		layered_map(26, "ordinary", .User_Global, 0, shared_right[:]),
	}
	expect_layered_compile_failure(
		t,
		&registry,
		layered_profile(7, protected_maps[:]),
		layered_active_context(7),
		Failure_Code.Protected_Binding,
	)
}

/* Verifies replace and unbind derive one map before immutable compilation. */
@(test)
map_operations_precede_resolution :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(104), context.allocator)
	if !ready {
		return
	}
	defer command_registry_close(&registry)
	bindings := [?]Layered_Binding_Definition {
		layered_binding('a', "cursor-previous-grapheme", .Bind),
		layered_binding('a', "request-editor-exit", .Replace),
		layered_binding('b', "uppercase-current-line", .Bind),
		layered_binding('b', "", .Unbind),
	}
	maps := [?]Map_Definition {
		layered_map(31, "derived", .Profile_Base, 0, bindings[:]),
	}
	snapshot: Resolution_Snapshot
	compiled, failure := profile_snapshot_compile(
		&snapshot,
		&registry,
		Snapshot_Generation(8),
		layered_profile(8, maps[:]),
		layered_active_context(8),
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, compiled, "derived map failed: %v", failure.code)
	if !compiled {
		return
	}
	defer snapshot_close(&snapshot)
	exit_command, found, _ := command_lookup(&registry, "request-editor-exit")
	testing.expect(t, found)
	pending: Pending_State
	resolved, _ := resolve_input(
		&snapshot,
		Registry_Generation(104),
		&pending,
		key_input(scalar_key('a')),
	)
	testing.expect_value(t, resolved.kind, Resolution_Kind.Command)
	testing.expect_value(t, resolved.command, exit_command)
	resolved, _ = resolve_input(
		&snapshot,
		Registry_Generation(104),
		&pending,
		key_input(scalar_key('b')),
	)
	testing.expect_value(t, resolved.kind, Resolution_Kind.Unbound)
}

/* Verifies a higher-precedence prefix owns input before a lower exact binding. */
@(test)
higher_layer_prefix_shadows_lower_exact_binding :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(107), context.allocator)
	if !ready {
		return
	}
	defer command_registry_close(&registry)
	higher_bindings := [?]Layered_Binding_Definition {
		layered_sequence_binding(
			Key_Sequence {
				strokes = {0 = control_key('x'), 1 = scalar_key('u')},
				stroke_count = 2,
			},
			"uppercase-current-line",
			.Bind,
		),
	}
	lower_bindings := [?]Layered_Binding_Definition {
		layered_sequence_binding(
			Key_Sequence {strokes = {0 = control_key('x')}, stroke_count = 1},
			"request-editor-exit",
			.Bind,
		),
	}
	maps := [?]Map_Definition {
		layered_map(32, "higher", .User_Global, 0, higher_bindings[:]),
		layered_map(33, "lower", .Factory_Fallback, 0, lower_bindings[:]),
	}
	snapshot: Resolution_Snapshot
	compiled, failure := profile_snapshot_compile(
		&snapshot,
		&registry,
		Snapshot_Generation(14),
		layered_profile(14, maps[:]),
		layered_active_context(14),
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, compiled, "prefix profile failed: %v", failure.code)
	if !compiled {
		return
	}
	defer snapshot_close(&snapshot)
	pending: Pending_State
	first, _ := resolve_input(
		&snapshot,
		Registry_Generation(107),
		&pending,
		key_input(control_key('x')),
	)
	testing.expect_value(t, first.kind, Resolution_Kind.Pending)
	second, _ := resolve_input(
		&snapshot,
		Registry_Generation(107),
		&pending,
		key_input(scalar_key('u')),
	)
	testing.expect_value(t, second.kind, Resolution_Kind.Command)
}

/* Verifies generated layered lookups match a small precedence oracle. */
@(test)
generated_resolution_matches_oracle :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(105), context.allocator)
	if !ready {
		return
	}
	defer command_registry_close(&registry)
	map_bindings: [4][32]Layered_Binding_Definition
	maps: [4]Map_Definition
	for map_index in 0 ..< len(maps) {
		for binding_index in 0 ..< len(map_bindings[map_index]) {
			value := rune(0x4e00 + binding_index)
			command_name := "cursor-previous-grapheme"
			if map_index == 0 && binding_index % 3 == 0 {
				command_name = "uppercase-current-line"
			}
			map_bindings[map_index][binding_index] = layered_binding(value, command_name, .Bind)
		}
		maps[map_index] = layered_map(
			u64(40 + map_index),
			"generated",
			Precedence_Class(int(Precedence_Class.Language_Context) + map_index),
			0,
			map_bindings[map_index][:],
		)
	}
	snapshot: Resolution_Snapshot
	compiled, failure := profile_snapshot_compile(
		&snapshot,
		&registry,
		Snapshot_Generation(9),
		layered_profile(9, maps[:]),
		layered_active_context(9),
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, compiled, "generated profile failed: %v", failure.code)
	if !compiled {
		return
	}
	defer snapshot_close(&snapshot)
	left, left_ok, _ := command_lookup(&registry, "cursor-previous-grapheme")
	uppercase, uppercase_ok, _ := command_lookup(&registry, "uppercase-current-line")
	testing.expect(t, left_ok && uppercase_ok)
	for binding_index in 0 ..< 32 {
		pending: Pending_State
		resolved, resolve_failure := resolve_input(
			&snapshot,
			Registry_Generation(105),
			&pending,
			key_input(scalar_key(rune(0x4e00 + binding_index))),
		)
		expected := left
		if binding_index % 3 == 0 {
			expected = uppercase
		}
		testing.expect_value(t, resolve_failure.code, Failure_Code.None)
		testing.expect_value(t, resolved.kind, Resolution_Kind.Command)
		testing.expect_value(t, resolved.command, expected)
	}
}

/* Verifies allocator faults preserve the prior generation and cleanup exact storage. */
@(test)
layered_snapshot_faults_keep_prior_generation :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	failing := Resolver_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = max(u64),
	}
	allocator := resolver_failing_allocator(&failing)
	registry, ready := layered_test_registry(t, Registry_Generation(106), allocator)
	if !ready {
		return
	}
	bindings := [?]Layered_Binding_Definition {
		layered_binding('a', "cursor-previous-grapheme", .Bind),
	}
	maps := [?]Map_Definition {
		layered_map(51, "fault", .Factory_Fallback, 0, bindings[:]),
	}
	snapshot: Resolution_Snapshot
	compiled, failure := profile_snapshot_compile(
		&snapshot,
		&registry,
		Snapshot_Generation(10),
		layered_profile(10, maps[:]),
		layered_active_context(10),
		DEFAULT_RESOLUTION_POLICY,
		allocator,
	)
	testing.expectf(t, compiled, "initial profile failed: %v", failure.code)
	if !compiled {
		command_registry_close(&registry)
		return
	}
	before, before_ok, _ := snapshot_stats(&snapshot)
	testing.expect(t, before_ok)
	for fail_offset in 0 ..< 4 {
		failing.fail_after = failing.successful_allocations + u64(fail_offset)
		replaced, replacement_failure := profile_snapshot_compile(
			&snapshot,
			&registry,
			Snapshot_Generation(11 + fail_offset),
			layered_profile(u64(11 + fail_offset), maps[:]),
			layered_active_context(u64(11 + fail_offset)),
			DEFAULT_RESOLUTION_POLICY,
			allocator,
		)
		testing.expect(t, !replaced)
		testing.expect_value(t, replacement_failure.code, Failure_Code.Persistent_Memory_Limit)
		after, after_ok, _ := snapshot_stats(&snapshot)
		testing.expect(t, after_ok)
		testing.expect_value(t, after.generation, before.generation)
		testing.expect_value(t, after.storage_bytes, before.storage_bytes)
	}
	failing.fail_after = max(u64)
	snapshot_closed, _ := snapshot_close(&snapshot)
	registry_closed, _ := command_registry_close(&registry)
	testing.expect(t, snapshot_closed && registry_closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(private)
layered_test_registry :: proc(
	t: ^testing.T,
	generation: Registry_Generation,
	allocator: mem.Allocator,
) -> (registry: Command_Registry, ready: bool) {
	definitions := base_command_definitions()
	failure: Failure_Context
	ready, failure = command_registry_init(&registry, generation, definitions[:], allocator)
	testing.expectf(t, ready, "registry initialization failed: %v", failure.code)
	return registry, ready
}

@(private)
layered_test_provenance :: proc() -> Definition_Provenance {
	return Definition_Provenance {
		provider = "test",
		source = "layered-resolver-test",
	}
}

@(private)
scalar_sequence :: proc(value: rune) -> Key_Sequence {
	return Key_Sequence {
		strokes = {0 = scalar_key(value)},
		stroke_count = 1,
	}
}

@(private)
layered_binding :: proc(
	value: rune,
	command_name: string,
	operation: Binding_Operation,
) -> Layered_Binding_Definition {
	return layered_sequence_binding(scalar_sequence(value), command_name, operation)
}

@(private)
layered_sequence_binding :: proc(
	sequence: Key_Sequence,
	command_name: string,
	operation: Binding_Operation,
) -> Layered_Binding_Definition {
	return Layered_Binding_Definition {
		sequence = sequence,
		command_name = command_name,
		operation = operation,
		provenance = layered_test_provenance(),
	}
}

@(private)
layered_map :: proc(
	id: u64,
	name: string,
	precedence: Precedence_Class,
	priority: i32,
	bindings: []Layered_Binding_Definition,
) -> Map_Definition {
	return Map_Definition {
		identity = Map_Identity{id = Map_ID(id), revision = Map_Revision(1)},
		name = name,
		precedence = precedence,
		priority = priority,
		bindings = bindings,
		unmatched_input_policy = .Fallthrough,
		provenance = layered_test_provenance(),
	}
}

@(private)
layered_profile :: proc(id: u64, maps: []Map_Definition) -> Profile_Definition {
	return Profile_Definition {
		identity = Profile_Identity{id = Profile_ID(id), revision = Profile_Revision(1)},
		name = "test-profile",
		maps = maps,
		text_fallback_name = "insert-text",
	}
}

@(private)
layered_active_context :: proc(id: u64) -> Active_Context {
	return Active_Context {
		identity = Context_Handle{id = Context_ID(id), generation = Context_Generation(id)},
	}
}

@(private)
expect_layered_compile_failure :: proc(
	t: ^testing.T,
	registry: ^Command_Registry,
	profile: Profile_Definition,
	active_context: Active_Context,
	expected: Failure_Code,
) {
	snapshot: Resolution_Snapshot
	compiled, failure := profile_snapshot_compile(
		&snapshot,
		registry,
		Snapshot_Generation(100 + u64(profile.identity.id)),
		profile,
		active_context,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expect(t, !compiled)
	testing.expect_value(t, failure.code, expected)
	if compiled {
		snapshot_close(&snapshot)
	}
}

@(private)
layered_definition_count :: proc(data: ^Snapshot_Data, sequence: Key_Sequence) -> int {
	query := Compiled_Binding {
		strokes = sequence.strokes,
		stroke_count = sequence.stroke_count,
	}
	count := 0
	for compiled_map in data.layered_maps {
		start := int(compiled_map.binding_start)
		end := start + int(compiled_map.binding_count)
		for binding in data.layered_bindings[start:end] {
			if sequence_compare(binding.compiled, query) == 0 {
				count += 1
			}
		}
	}
	return count
}
