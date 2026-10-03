// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:fmt"
import "core:mem"
import "core:testing"
import "core:time"

/* Verifies catalogs copy metadata, active bindings, and contextual availability. */
@(test)
command_catalog_projects_interactive_commands :: proc(t: ^testing.T) {
	definitions := [4]Command_Definition {
		command_catalog_test_definition("alpha-command", true, {}),
		command_catalog_test_definition("beta-command", true, {.Active_Region}),
		command_catalog_test_definition("hidden-command", false, {}),
		{
			name = "insert-text",
			route = test_command_route("insert-text"),
			implementation = .Native,
			invocation = .Text_Input,
			text_requirement = .Required,
			description = "Insert test text.",
		},
	}
	registry: Command_Registry
	registry_ok, registry_failure := command_registry_init(
		&registry,
		1,
		definitions[:],
		context.allocator,
	)
	testing.expectf(t, registry_ok, "registry failed with %v", registry_failure.code)
	if !registry_ok {
		return
	}
	bindings := [2]Binding_Definition {
		command_catalog_test_binding('a', "alpha-command"),
		command_catalog_test_binding('h', "hidden-command"),
	}
	snapshot: Resolution_Snapshot
	snapshot_ok, snapshot_failure := snapshot_compile(
		&snapshot,
		&registry,
		1,
		Keymap_Definition {
			registry_generation = 1,
			bindings = bindings[:],
			text_fallback_name = "insert-text",
		},
		context.allocator,
	)
	testing.expectf(t, snapshot_ok, "snapshot failed with %v", snapshot_failure.code)
	if !snapshot_ok {
		command_registry_close(&registry)
		return
	}
	catalog, catalog_ok, catalog_failure := command_catalog_build(
		&registry,
		&snapshot,
		Command_Catalog_Context{active_buffer = true},
		context.allocator,
	)
	testing.expectf(t, catalog_ok, "catalog failed with %v", catalog_failure.code)
	if !catalog_ok {
		snapshot_close(&snapshot)
		command_registry_close(&registry)
		return
	}
	testing.expect_value(t, len(catalog.entries), 2)
	if len(catalog.entries) == 2 {
		alpha := catalog.entries[0]
		beta := catalog.entries[1]
		testing.expect_value(t, alpha.metadata.name, "alpha-command")
		testing.expect_value(t, alpha.metadata.provenance.provider, "test-provider")
		testing.expect_value(t, alpha.metadata.provenance.source, "command-catalog-test")
		testing.expect_value(t, alpha.availability, Command_Availability.Available)
		testing.expect_value(t, len(alpha.bindings), 1)
		if len(alpha.bindings) == 1 {
			testing.expect_value(t, alpha.bindings[0].stroke_count, u8(1))
			testing.expect_value(t, alpha.bindings[0].strokes[0].scalar, rune('a'))
		}
		testing.expect_value(t, beta.metadata.name, "beta-command")
		testing.expect_value(t, beta.availability, Command_Availability.Unavailable)
		testing.expect_value(t, beta.unavailable_reason, "Requires an active region.")
		testing.expect_value(t, len(beta.bindings), 0)
	}

	snapshot_closed, _ := snapshot_close(&snapshot)
	registry_closed, _ := command_registry_close(&registry)
	testing.expect(t, snapshot_closed && registry_closed)
	testing.expect_value(t, catalog.entries[0].metadata.name, "alpha-command")
	testing.expect(t, command_catalog_close(&catalog))
}

/* Verifies catalog construction rejects a snapshot from another registry. */
@(test)
command_catalog_rejects_registry_mismatch :: proc(t: ^testing.T) {
	definitions := [2]Command_Definition {
		command_catalog_test_definition("alpha-command", true, {}),
		{
			name = "insert-text",
			route = test_command_route("insert-text"),
			implementation = .Native,
			invocation = .Text_Input,
			text_requirement = .Required,
		},
	}
	first, second: Command_Registry
	first_ok, _ := command_registry_init(&first, 1, definitions[:], context.allocator)
	second_ok, _ := command_registry_init(&second, 2, definitions[:], context.allocator)
	testing.expect(t, first_ok && second_ok)
	if !first_ok || !second_ok {
		return
	}
	defer command_registry_close(&second)
	bindings := [1]Binding_Definition{command_catalog_test_binding('a', "alpha-command")}
	snapshot: Resolution_Snapshot
	snapshot_ok, _ := snapshot_compile(
		&snapshot,
		&first,
		1,
		Keymap_Definition {
			registry_generation = 1,
			bindings = bindings[:],
			text_fallback_name = "insert-text",
		},
		context.allocator,
	)
	testing.expect(t, snapshot_ok)
	if !snapshot_ok {
		command_registry_close(&first)
		return
	}
	defer {
		snapshot_close(&snapshot)
		command_registry_close(&first)
	}
	_, catalog_ok, catalog_failure := command_catalog_build(
		&second,
		&snapshot,
		Command_Catalog_Context{},
		context.allocator,
	)
	testing.expect(t, !catalog_ok)
	testing.expect_value(t, catalog_failure.code, Failure_Code.Stale_Registry)
}

/* Verifies command navigation reports state-rejected mutation without hiding commands. */
@(test)
applies_interaction_state_admission :: proc(t: ^testing.T) {
	definitions := [3]Command_Definition {
		command_catalog_test_definition("navigate-command", true, {}),
		{
			name = "mutate-command",
			route = test_command_route("mutate-command"),
			implementation = .Native,
			invocation = .Ordinary,
			text_requirement = .Prohibited,
			effects = {.Buffer, .View, .Text_Mutation},
			description = "Mutate test text.",
			interactive = true,
			provenance = Definition_Provenance {
				provider = "test-provider",
				source = "command-catalog-test",
			},
		},
		{
			name = "insert-text",
			route = test_command_route("insert-text"),
			implementation = .Native,
			invocation = .Text_Input,
			text_requirement = .Required,
			effects = {.Buffer, .View, .Text_Mutation},
		},
	}
	registry: Command_Registry
	registry_ok, _ := command_registry_init(&registry, 3, definitions[:], context.allocator)
	testing.expect(t, registry_ok)
	if !registry_ok {
		return
	}
	bindings := [2]Binding_Definition {
		command_catalog_test_binding('n', "navigate-command"),
		command_catalog_test_binding('m', "mutate-command"),
	}
	snapshot: Resolution_Snapshot
	snapshot_ok, _ := snapshot_compile(
		&snapshot,
		&registry,
		3,
		Keymap_Definition {
			registry_generation = 3,
			bindings = bindings[:],
			text_fallback_name = "insert-text",
		},
		context.allocator,
	)
	testing.expect(t, snapshot_ok)
	if !snapshot_ok {
		command_registry_close(&registry)
		return
	}
	defer {
		snapshot_close(&snapshot)
		command_registry_close(&registry)
	}
	catalog, built, failure := command_catalog_build(
		&registry,
		&snapshot,
		Command_Catalog_Context {
			active_buffer = true,
			profile = {id = 1, revision = 1},
			state = {id = 2, revision = 1},
			admitted_effects = {.Buffer, .View, .Lifecycle},
			command_entry_surface = {id = 1, revision = 1},
		},
		context.allocator,
	)
	testing.expectf(t, built, "state-aware catalog failed with %v", failure.code)
	if !built {
		return
	}
	defer command_catalog_close(&catalog)
	testing.expect_value(t, catalog.command_entry_surface.id, Command_Entry_Surface_ID(1))
	testing.expect_value(t, len(catalog.entries), 2)
	if len(catalog.entries) == 2 {
		testing.expect_value(t, catalog.entries[0].metadata.name, "mutate-command")
		testing.expect_value(t, catalog.entries[0].availability, Command_Availability.Unavailable)
		testing.expect_value(
			t,
			catalog.entries[0].unavailable_reason,
			"Unavailable in the active interaction state.",
		)
		testing.expect_value(t, catalog.entries[1].metadata.name, "navigate-command")
		testing.expect_value(t, catalog.entries[1].availability, Command_Availability.Available)
	}
}

/* Verifies catalog allocation failures release every privately retained byte. */
@(test)
allocation_failures_are_atomic_and_released :: proc(t: ^testing.T) {
	definitions := [2]Command_Definition {
		command_catalog_test_definition("alpha-command", true, {}),
		{
			name = "insert-text",
			route = test_command_route("insert-text"),
			implementation = .Native,
			invocation = .Text_Input,
			text_requirement = .Required,
		},
	}
	registry: Command_Registry
	registry_ok, _ := command_registry_init(&registry, 1, definitions[:], context.allocator)
	testing.expect(t, registry_ok)
	if !registry_ok {
		return
	}
	bindings := [1]Binding_Definition{command_catalog_test_binding('a', "alpha-command")}
	snapshot: Resolution_Snapshot
	snapshot_ok, _ := snapshot_compile(
		&snapshot,
		&registry,
		1,
		Keymap_Definition {
			registry_generation = 1,
			bindings = bindings[:],
			text_fallback_name = "insert-text",
		},
		context.allocator,
	)
	testing.expect(t, snapshot_ok)
	if !snapshot_ok {
		command_registry_close(&registry)
		return
	}
	defer {
		snapshot_close(&snapshot)
		command_registry_close(&registry)
	}
	failures, successes: u32
	for fail_after in 0 ..< 8 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Resolver_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		catalog, built, failure := command_catalog_build(
			&registry,
			&snapshot,
			Command_Catalog_Context{active_buffer = true},
			resolver_failing_allocator(&failing),
		)
		if built {
			successes += 1
			testing.expect(t, command_catalog_close(&catalog))
		} else {
			failures += 1
			testing.expect_value(t, failure.code, Failure_Code.Persistent_Memory_Limit)
		}
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
	testing.expect(t, failures > 0 && successes > 0)
}

/* Verifies the accepted 1,024-entry catalog projection gate on the reference host. */
@(test)
projects_ordinary_capacity_within_latency_gate :: proc(t: ^testing.T) {
	COMMAND_COUNT :: 1_024
	definitions: [COMMAND_COUNT + 1]Command_Definition
	name_storage: [COMMAND_COUNT][32]u8
	bindings: [COMMAND_COUNT]Binding_Definition
	for index in 0 ..< COMMAND_COUNT {
		name := fmt.bprintf(name_storage[index][:], "command-%04d", index)
		definitions[index] = command_catalog_test_definition(name, true, {})
		bindings[index] = command_catalog_test_binding(rune(0x4e00 + index), name)
	}
	definitions[COMMAND_COUNT] = Command_Definition {
		name = "insert-text",
		route = test_command_route("insert-text"),
		implementation = .Native,
		invocation = .Text_Input,
		text_requirement = .Required,
	}
	registry: Command_Registry
	registry_ok, registry_failure := command_registry_init(
		&registry,
		1,
		definitions[:],
		context.allocator,
	)
	testing.expectf(t, registry_ok, "registry failed with %v", registry_failure.code)
	if !registry_ok {
		return
	}
	snapshot: Resolution_Snapshot
	snapshot_ok, snapshot_failure := snapshot_compile(
		&snapshot,
		&registry,
		1,
		Keymap_Definition {
			registry_generation = 1,
			bindings = bindings[:],
			text_fallback_name = "insert-text",
		},
		context.allocator,
	)
	testing.expectf(t, snapshot_ok, "snapshot failed with %v", snapshot_failure.code)
	if !snapshot_ok {
		command_registry_close(&registry)
		return
	}
	defer {
		snapshot_close(&snapshot)
		command_registry_close(&registry)
	}
	started := time.tick_now()
	catalog, catalog_ok, catalog_failure := command_catalog_build(
		&registry,
		&snapshot,
		Command_Catalog_Context{active_buffer = true},
		context.allocator,
	)
	elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
	testing.expectf(t, catalog_ok, "catalog failed with %v", catalog_failure.code)
	if !catalog_ok {
		return
	}
	defer command_catalog_close(&catalog)
	testing.expect_value(t, len(catalog.entries), COMMAND_COUNT)
	testing.expectf(t, elapsed_ns < 5_000_000, "catalog projection took %d ns", elapsed_ns)
}

/* Verifies terminal-only commands expose a concise contextual availability reason. */
@(test)
command_catalog_requires_active_terminal_context :: proc(t: ^testing.T) {
	metadata := Command_Metadata {
		name = "terminal-send-return",
		interactive = true,
		requirements = {.Active_Buffer, .Active_Terminal},
	}
	availability, reason := command_catalog_availability(
		metadata,
		Command_Catalog_Context{active_buffer = true},
	)
	testing.expect_value(t, availability, Command_Availability.Unavailable)
	testing.expect_value(t, reason, "Requires an active terminal.")
	availability, reason = command_catalog_availability(
		metadata,
		Command_Catalog_Context{active_buffer = true, active_terminal = true},
	)
	testing.expect_value(t, availability, Command_Availability.Available)
	testing.expect_value(t, reason, "")
}

@(private)
command_catalog_test_definition :: proc(
	name: string,
	interactive: bool,
	requirements: Command_Requirements,
) -> Command_Definition {
	return Command_Definition {
		name = name,
		route = test_command_route(name),
		implementation = .Native,
		invocation = .Ordinary,
		text_requirement = .Prohibited,
		description = "Catalog test command.",
		interactive = interactive,
		requirements = requirements,
		provenance = Definition_Provenance {
			provider = "test-provider",
			source = "command-catalog-test",
		},
	}
}

@(private)
command_catalog_test_binding :: proc(value: rune, name: string) -> Binding_Definition {
	return Binding_Definition {
		strokes = {0 = Key_Stroke{kind = .Unicode_Scalar, scalar = value}},
		stroke_count = 1,
		command_name = name,
	}
}
