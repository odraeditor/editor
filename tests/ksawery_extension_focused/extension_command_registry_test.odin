// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_extension_focused

import command "../../src/command"
import "../../src/ksawery_command"
import interaction "../../src/interaction"
import ksawery "../../src/ksawery"
import "core:mem"
import "core:testing"

/* Verifies extension actions enter the shared registry with stable provenance and routes. */
@(test)
extension_commands_use_the_shared_registry :: proc(t: ^testing.T) {
	choices: [2]ksawery.Extension_Command_Choice
	arguments: [3]ksawery.Extension_Command_Argument_Definition
	actions: [2]ksawery.Extension_Command_Action_Definition
	family := extension_command_test_family(&choices, &arguments, &actions)
	catalog: ksawery_command.Ksawery_Extension_Command_Catalog
	built, build_failure := ksawery_command.ksawery_extension_command_catalog_build(
		&catalog,
		73,
		[]ksawery_command.Ksawery_Extension_Command_Admission{{family = family, source = "modules/repository-tools.rkt"}},
		context.allocator,
	)
	testing.expectf(t, built, "extension catalog failed: %v", build_failure.code)
	if !built do return
	defer ksawery_command.ksawery_extension_command_catalog_close(&catalog)
	registry: interaction.Command_Registry
	ready, registry_failure := command.built_in_command_registry_init(
		&registry,
		73,
		context.allocator,
		racket_definitions = catalog.definitions,
	)
	testing.expectf(t, ready, "shared registry failed: %v", registry_failure.code)
	if !ready do return
	defer interaction.command_registry_close(&registry)
	handle, found, _ := interaction.command_lookup(
		&registry,
		"personal.repository-tools/family.review-ref/action.apply",
	)
	testing.expect(t, found)
	if !found do return
	metadata, inspected, _ := interaction.command_metadata(&registry, handle)
	testing.expect(t, inspected)
	if inspected {
		testing.expect_value(t, metadata.provenance.provider, "personal.repository-tools")
		testing.expect_value(t, metadata.provenance.source, "modules/repository-tools.rkt")
		testing.expect_value(t, metadata.provenance.location, "family.review-ref")
		testing.expect_value(t, metadata.effects, interaction.Command_Effects{.Lifecycle})
	}
	route, routed := ksawery_command.ksawery_extension_command_catalog_route(&catalog, metadata.route)
	testing.expect(t, routed)
	if routed {
		testing.expect_value(t, route.family, family.family)
		testing.expect_value(t, route.family_generation, family.generation)
		testing.expect_value(t, route.action, ksawery.Extension_Command_Action_ID(2))
	}
}

/* Verifies the navigator and one active component map discover the same extension command. */
@(test)
extension_commands_are_navigable_and_contextually_bound :: proc(t: ^testing.T) {
	choices: [2]ksawery.Extension_Command_Choice
	arguments: [3]ksawery.Extension_Command_Argument_Definition
	actions: [2]ksawery.Extension_Command_Action_Definition
	family := extension_command_test_family(&choices, &arguments, &actions)
	catalog: ksawery_command.Ksawery_Extension_Command_Catalog
	built, build_failure := ksawery_command.ksawery_extension_command_catalog_build(
		&catalog,
		97,
		[]ksawery_command.Ksawery_Extension_Command_Admission{{
			family = family,
			source = "modules/repository-tools.rkt",
		}},
		context.allocator,
	)
	testing.expectf(t, built, "extension catalog failed: %v", build_failure.code)
	if !built do return
	defer ksawery_command.ksawery_extension_command_catalog_close(&catalog)
	registry: interaction.Command_Registry
	ready, registry_failure := command.built_in_command_registry_init(
		&registry, 97, context.allocator, racket_definitions = catalog.definitions,
	)
	testing.expectf(t, ready, "shared registry failed: %v", registry_failure.code)
	if !ready do return
	defer interaction.command_registry_close(&registry)
	name := "personal.repository-tools/family.review-ref/action.apply"
	handle, found, _ := interaction.command_lookup(&registry, name)
	if !testing.expect(t, found) do return
	sequence := interaction.Key_Sequence {
		strokes = {0 = {kind = .Unicode_Scalar, scalar = 'x'}},
		stroke_count = 1,
	}
	owner := interaction.Owner_Handle{id = 41, generation = 1}
	bindings := [1]interaction.Layered_Binding_Definition {{
		sequence = sequence,
		command_name = name,
		operation = .Bind,
		provenance = {provider = "personal.repository-tools", source = "modules/repository-tools.rkt"},
	}}
	context_identity := interaction.Context_Handle{id = 43, generation = 1}
	maps := [1]interaction.Map_Definition {{
		identity = {id = 47, revision = 1},
		name = "repository-tools",
		owner = owner,
		precedence = .Component_Tool,
		context_requirement = {ctx = context_identity, owner = owner},
		bindings = bindings[:],
		unmatched_input_policy = .Fallthrough,
		provenance = {provider = "personal.repository-tools", source = "modules/repository-tools.rkt"},
	}}
	profile := interaction.Profile_Definition {
		identity = {id = 53, revision = 1},
		name = "extension-discovery",
		maps = maps[:],
		text_fallback_name = "insert-text",
	}
	owners := [1]interaction.Owner_Handle{owner}
	snapshot: interaction.Resolution_Snapshot
	compiled, compile_failure := interaction.profile_snapshot_compile(
		&snapshot,
		&registry,
		59,
		profile,
		{identity = context_identity, owners = owners[:]},
		interaction.DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, compiled, "contextual profile failed: %v", compile_failure.code)
	if !compiled do return
	defer interaction.snapshot_close(&snapshot)
	pending: interaction.Pending_State
	resolution, resolve_failure := interaction.resolve_input(
		&snapshot,
		97,
		&pending,
		{kind = .Key, stroke = sequence.strokes[0]},
	)
	testing.expect_value(t, resolve_failure.code, interaction.Failure_Code.None)
	testing.expect_value(t, resolution.kind, interaction.Resolution_Kind.Command)
	testing.expect_value(t, resolution.command, handle)
	navigator, navigator_ready, navigator_failure := interaction.command_catalog_build(
		&registry,
		&snapshot,
		{active_buffer = true},
		context.allocator,
	)
	testing.expectf(t, navigator_ready, "navigator catalog failed: %v", navigator_failure.code)
	if !navigator_ready do return
	defer interaction.command_catalog_close(&navigator)
	discovered := false
	for entry in navigator.entries {
		if entry.metadata.name != name do continue
		discovered = true
		testing.expect_value(t, entry.availability, interaction.Command_Availability.Available)
		testing.expect_value(t, len(entry.bindings), 1)
		if len(entry.bindings) == 1 do testing.expect_value(t, entry.bindings[0], sequence)
	}
	testing.expect(t, discovered)
}

/* Verifies duplicate stable identities reject the complete candidate generation. */
@(test)
extension_command_generations_reject_duplicate_identities :: proc(t: ^testing.T) {
	choices: [2]ksawery.Extension_Command_Choice
	arguments: [3]ksawery.Extension_Command_Argument_Definition
	actions: [2]ksawery.Extension_Command_Action_Definition
	family := extension_command_test_family(&choices, &arguments, &actions)
	catalog: ksawery_command.Ksawery_Extension_Command_Catalog
	built, failure := ksawery_command.ksawery_extension_command_catalog_build(
		&catalog,
		79,
		[]ksawery_command.Ksawery_Extension_Command_Admission{
			{family = family, source = "modules/first.rkt"},
			{family = family, source = "modules/second.rkt"},
		},
		context.allocator,
	)
	testing.expect(t, !built)
	testing.expect_value(t, failure.code, interaction.Failure_Code.Duplicate_Command)
	testing.expect_value(t, catalog.allocator.procedure, nil)
}

/* Verifies command-keymap collisions reject the complete candidate profile. */
@(test)
extension_command_keymap_conflicts_are_atomic :: proc(t: ^testing.T) {
	choices: [2]ksawery.Extension_Command_Choice
	arguments: [3]ksawery.Extension_Command_Argument_Definition
	actions: [2]ksawery.Extension_Command_Action_Definition
	family := extension_command_test_family(&choices, &arguments, &actions)
	catalog: ksawery_command.Ksawery_Extension_Command_Catalog
	built, _ := ksawery_command.ksawery_extension_command_catalog_build(
		&catalog,
		83,
		[]ksawery_command.Ksawery_Extension_Command_Admission{{family = family, source = "modules/repository-tools.rkt"}},
		context.allocator,
	)
	if !testing.expect(t, built) do return
	defer ksawery_command.ksawery_extension_command_catalog_close(&catalog)
	registry: interaction.Command_Registry
	ready, _ := command.built_in_command_registry_init(
		&registry, 83, context.allocator, racket_definitions = catalog.definitions,
	)
	if !testing.expect(t, ready) do return
	defer interaction.command_registry_close(&registry)
	sequence := interaction.Key_Sequence {
		strokes = {0 = {kind = .Unicode_Scalar, scalar = 'x'}},
		stroke_count = 1,
	}
	extension_bindings := [1]interaction.Layered_Binding_Definition {{
		sequence = sequence,
		command_name = "personal.repository-tools/family.review-ref/action.apply",
		operation = .Bind,
		provenance = {provider = "personal.repository-tools", source = "modules/repository-tools.rkt"},
	}}
	core_bindings := [1]interaction.Layered_Binding_Definition {{
		sequence = sequence,
		command_name = "request-editor-exit",
		operation = .Bind,
		provenance = {provider = "native", source = "focused-test"},
	}}
	maps := [2]interaction.Map_Definition {
		{
			identity = {id = 1, revision = 1},
			name = "extension",
			precedence = .Project,
			priority = 7,
			bindings = extension_bindings[:],
			unmatched_input_policy = .Fallthrough,
			provenance = {provider = "personal.repository-tools", source = "modules/repository-tools.rkt"},
		},
		{
			identity = {id = 2, revision = 1},
			name = "core",
			precedence = .Project,
			priority = 7,
			bindings = core_bindings[:],
			unmatched_input_policy = .Fallthrough,
			provenance = {provider = "native", source = "focused-test"},
		},
	}
	snapshot: interaction.Resolution_Snapshot
	compiled, failure := interaction.profile_snapshot_compile(
		&snapshot,
		&registry,
		1,
		{
			identity = {id = 1, revision = 1},
			name = "extension-conflict",
			maps = maps[:],
			text_fallback_name = "insert-text",
		},
		{identity = {id = 1, generation = 1}},
		interaction.DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expect(t, !compiled)
	testing.expect_value(t, failure.code, interaction.Failure_Code.Ordering_Conflict)
	testing.expect_value(t, snapshot.state, nil)
}

/* Verifies failed generations preserve the active catalog and release all memory. */
@(test)
extension_catalog_rolls_back_and_tears_down :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	choices: [2]ksawery.Extension_Command_Choice
	arguments: [3]ksawery.Extension_Command_Argument_Definition
	actions: [2]ksawery.Extension_Command_Action_Definition
	family := extension_command_test_family(&choices, &arguments, &actions)
	catalog: ksawery_command.Ksawery_Extension_Command_Catalog
	built, _ := ksawery_command.ksawery_extension_command_catalog_build(
		&catalog,
		89,
		[]ksawery_command.Ksawery_Extension_Command_Admission{{family = family, source = "modules/active.rkt"}},
		allocator,
	)
	if !testing.expect(t, built) {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	candidate: ksawery_command.Ksawery_Extension_Command_Catalog
	replaced, failure := ksawery_command.ksawery_extension_command_catalog_build(
		&candidate,
		90,
		[]ksawery_command.Ksawery_Extension_Command_Admission {
			{family = family, source = "modules/first.rkt"},
			{family = family, source = "modules/duplicate.rkt"},
		},
		allocator,
	)
	testing.expect(t, !replaced)
	testing.expect_value(t, failure.code, interaction.Failure_Code.Duplicate_Command)
	testing.expect_value(t, candidate.allocator.procedure, nil)
	route, retained := ksawery_command.ksawery_extension_command_catalog_route(
		&catalog, command.racket_route(.Ksawery_Extension, 1),
	)
	testing.expect(t, retained)
	if retained do testing.expect_value(t, route.family_generation, family.generation)
	ksawery_command.ksawery_extension_command_catalog_close(&catalog)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}
