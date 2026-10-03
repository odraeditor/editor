// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "base:runtime"
import "core:testing"

/* Contextual inspection exposes direct help separately from complete sequences. */
@(test)
map_inspection_separates_help_modes :: proc(t: ^testing.T) {
	fixture, ready := context_map_test_fixture_init(t, context.allocator)
	if !ready do return
	defer context_map_test_fixture_close(t, &fixture)
	bindings := [2]Binding_Definition {
		context_test_binding(context_test_scalar('x'), "component-action"),
		context_test_binding(context_test_sequence('t', 'f'), "component-action"),
	}
	_, activated, activation_failure := context_map_activate(
		&fixture.stack,
		context_test_map(10, 100, .Component_Tool, 10, .Fallthrough, bindings[:], ""),
		&fixture.context_pending,
		&fixture.base_pending,
	)
	testing.expectf(t, activated, "context activation failed with %v", activation_failure.code)
	if !activated do return
	direct, direct_ok, direct_failure := context_map_inspect(
		&fixture.stack,
		10,
		false,
		context.allocator,
	)
	testing.expectf(t, direct_ok, "direct inspection failed with %v", direct_failure.code)
	if direct_ok {
		testing.expect_value(t, len(direct.records), 1)
		testing.expect_value(t, direct.records[0].map_name, "test-context-map")
		testing.expect_value(t, direct.records[0].sequence.stroke_count, u8(1))
		testing.expect(t, inspection_result_close(&direct))
	}
	complete, complete_ok, complete_failure := context_map_inspect(
		&fixture.stack,
		10,
		true,
		context.allocator,
	)
	testing.expectf(t, complete_ok, "complete inspection failed with %v", complete_failure.code)
	if complete_ok {
		testing.expect_value(t, len(complete.records), 2)
		has_sequence := false
		for record in complete.records do has_sequence = has_sequence || record.sequence.stroke_count == 2
		testing.expect(t, has_sequence)
		testing.expect(t, inspection_result_close(&complete))
	}
}

/* Language maps remain active below component and transient interaction. */
@(test)
language_context_maps_preserve_context_precedence :: proc(t: ^testing.T) {
	fixture, ready := context_map_test_fixture_init(t, context.allocator)
	if !ready do return
	defer context_map_test_fixture_close(t, &fixture)
	language_bindings := [1]Binding_Definition {
		context_test_binding(context_test_scalar('x'), "base-action"),
	}
	language, language_ok, language_failure := context_map_activate(
		&fixture.stack,
		context_test_map(
			8,
			80,
			.Language_Context,
			100,
			.Fallthrough,
			language_bindings[:],
			"",
		),
		&fixture.context_pending,
		&fixture.base_pending,
	)
	testing.expectf(t, language_ok, "language activation failed with %v", language_failure.code)
	if !language_ok do return

	component_bindings := [1]Binding_Definition {
		context_test_binding(context_test_scalar('x'), "component-action"),
	}
	component, component_ok, component_failure := context_map_activate(
		&fixture.stack,
		context_test_map(
			9,
			90,
			.Component_Tool,
			0,
			.Fallthrough,
			component_bindings[:],
			"",
		),
		&fixture.context_pending,
		&fixture.base_pending,
	)
	testing.expectf(t, component_ok, "component activation failed with %v", component_failure.code)
	if !component_ok do return

	resolved := context_test_resolve(t, &fixture, context_test_key_input('x'))
	context_test_expect_command(t, &fixture.registry, resolved, "component-action")
	_, ended, end_failure := context_map_end(
		&fixture.stack,
		component.handle,
		.Completed,
		&fixture.context_pending,
		&fixture.base_pending,
	)
	testing.expectf(t, ended, "component completion failed with %v", end_failure.code)
	resolved = context_test_resolve(t, &fixture, context_test_key_input('x'))
	context_test_expect_command(t, &fixture.registry, resolved, "base-action")
	testing.expect(t, context_map_handle_is_active(&fixture.stack, language.handle))
}

/* Contextual maps own precedence, fallthrough, text input, and checked lifecycle. */
@(test)
contextual_maps_route_input_by_active_owner :: proc(t: ^testing.T) {
	fixture, ready := context_map_test_fixture_init(t, context.allocator)
	if !ready {
		return
	}
	defer context_map_test_fixture_close(t, &fixture)

	component_bindings := [3]Binding_Definition {
		context_test_binding(context_test_scalar('x'), "component-action"),
		context_test_binding(context_test_scalar('j'), "component-action"),
		context_test_binding(context_test_special(.Tab), "component-action"),
	}
	component, component_ok, component_failure := context_map_activate(
		&fixture.stack,
		context_test_map(
			11,
			101,
			.Component_Tool,
			10,
			.Fallthrough,
			component_bindings[:],
			"",
		),
		&fixture.context_pending,
		&fixture.base_pending,
	)
	testing.expectf(t, component_ok, "component activation failed with %v", component_failure.code)

	transient_bindings := [1]Binding_Definition {
		context_test_binding(context_test_scalar('x'), "transient-action"),
	}
	transient, transient_ok, transient_failure := context_map_activate(
		&fixture.stack,
		context_test_map(
			12,
			102,
			.Transient_Interaction,
			10,
			.Fallthrough,
			transient_bindings[:],
			"",
		),
		&fixture.context_pending,
		&fixture.base_pending,
	)
	testing.expectf(t, transient_ok, "transient activation failed with %v", transient_failure.code)
	testing.expect(t, context_map_handle_is_active(&fixture.stack, component.handle))
	testing.expect(t, context_map_handle_is_active(&fixture.stack, transient.handle))

	resolved := context_test_resolve(t, &fixture, context_test_key_input('x'))
	context_test_expect_command(t, &fixture.registry, resolved, "transient-action")
	resolved = context_test_resolve(t, &fixture, context_test_key_input('j'))
	context_test_expect_command(t, &fixture.registry, resolved, "component-action")
	resolved = context_test_resolve(t, &fixture, context_test_key_input('b'))
	context_test_expect_command(t, &fixture.registry, resolved, "base-action")
	resolved = context_test_resolve(
		t,
		&fixture,
		Input{kind = .Key, stroke = Key_Stroke{kind = .Tab}},
	)
	context_test_expect_command(t, &fixture.registry, resolved, "component-action")

	_, ended, end_failure := context_map_end(
		&fixture.stack,
		transient.handle,
		.Completed,
		&fixture.context_pending,
		&fixture.base_pending,
	)
	testing.expectf(t, ended, "transient completion failed with %v", end_failure.code)
	resolved = context_test_resolve(t, &fixture, context_test_key_input('x'))
	context_test_expect_command(t, &fixture.registry, resolved, "component-action")

	_, ended, end_failure = context_map_end(
		&fixture.stack,
		component.handle,
		.Cancelled,
		&fixture.context_pending,
		&fixture.base_pending,
	)
	testing.expectf(t, ended, "component cancellation failed with %v", end_failure.code)
	testing.expect(t, !context_map_handle_is_active(&fixture.stack, component.handle))
	stats, stats_ok := context_map_stats(&fixture.stack)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.active_maps, u8(0))
}

/* Text and rejection policies consume input without entering the base map. */
@(test)
contextual_maps_enforce_unmatched_input_policy :: proc(t: ^testing.T) {
	fixture, ready := context_map_test_fixture_init(t, context.allocator)
	if !ready {
		return
	}
	defer context_map_test_fixture_close(t, &fixture)

	text_bindings := [3]Binding_Definition {
		context_test_binding(context_test_special(.Backspace), "prompt-delete"),
		context_test_binding(context_test_special(.Enter), "prompt-accept"),
		context_test_binding(context_test_control('c'), "context-cancel"),
	}
	text_map, activated, activation_failure := context_map_activate(
		&fixture.stack,
		context_test_map(
			21,
			201,
			.Transient_Interaction,
			0,
			.Text_Input,
			text_bindings[:],
			"prompt-text",
		),
		&fixture.context_pending,
		&fixture.base_pending,
	)
	testing.expectf(t, activated, "text map activation failed with %v", activation_failure.code)

	resolved := context_test_resolve(
		t,
		&fixture,
		Input{kind = .Text_Commit, text = "Żółć"},
	)
	context_test_expect_command(t, &fixture.registry, resolved, "prompt-text")
	testing.expect_value(t, resolved.text, "Żółć")
	left := context_test_special(.Left)
	left_failure: Failure_Context
	resolved, left_failure = resolve_contextual_input(
		&fixture.stack,
		&fixture.snapshot,
		1,
		&fixture.context_pending,
		&fixture.base_pending,
		Input{kind = .Key, stroke = left.strokes[0]},
	)
	testing.expect_value(t, resolved.kind, Resolution_Kind.Rejected)
	testing.expect_value(t, left_failure.code, Failure_Code.Context_Input_Rejected)

	_, ended, _ := context_map_end(
		&fixture.stack,
		text_map.handle,
		.Completed,
		&fixture.context_pending,
		&fixture.base_pending,
	)
	testing.expect(t, ended)
	reject_bindings := [1]Binding_Definition {
		context_test_binding(context_test_control('c'), "context-cancel"),
	}
	_, activated, activation_failure = context_map_activate(
		&fixture.stack,
		context_test_map(
			22,
			202,
			.Transient_Interaction,
			0,
			.Reject,
			reject_bindings[:],
			"",
		),
		&fixture.context_pending,
		&fixture.base_pending,
	)
	testing.expectf(t, activated, "reject map activation failed with %v", activation_failure.code)
	resolve_failure: Failure_Context
	resolved, resolve_failure = resolve_contextual_input(
		&fixture.stack,
		&fixture.snapshot,
		1,
		&fixture.context_pending,
		&fixture.base_pending,
		context_test_key_input('b'),
	)
	testing.expect_value(t, resolved.kind, Resolution_Kind.Rejected)
	testing.expect_value(t, resolve_failure.code, Failure_Code.Context_Input_Rejected)
}

/* A contextual prefix that does not complete is replayed through the base keymap. */
@(test)
pending_fallthrough_keeps_base_sequence :: proc(t: ^testing.T) {
	fixture, ready := context_map_test_fixture_init(t, context.allocator)
	if !ready do return
	defer context_map_test_fixture_close(t, &fixture)

	bindings := [1]Binding_Definition {
		context_test_binding(context_test_sequence('x', 'y'), "transient-action"),
	}
	_, activated, activation_failure := context_map_activate(
		&fixture.stack,
		context_test_map(25, 205, .Component_Tool, 0, .Fallthrough, bindings[:], ""),
		&fixture.context_pending,
		&fixture.base_pending,
	)
	testing.expectf(t, activated, "context activation failed with %v", activation_failure.code)

	resolved := context_test_resolve(
		t,
		&fixture,
		Input{kind = .Key, stroke = Key_Stroke{kind = .Unicode_Scalar, scalar = 'x'}},
	)
	testing.expect_value(t, resolved.kind, Resolution_Kind.Pending)
	resolved = context_test_resolve(
		t,
		&fixture,
		Input{kind = .Key, stroke = Key_Stroke{kind = .Unicode_Scalar, scalar = 'z'}},
	)
	context_test_expect_command(t, &fixture.registry, resolved, "base-action")
	testing.expect_value(t, fixture.context_pending.stroke_count, u8(0))
	testing.expect_value(t, fixture.base_pending.stroke_count, u8(0))
}

/* A base prefix retains its following stroke when a context map binds that stroke. */
@(test)
base_pending_sequence_keeps_its_owner :: proc(t: ^testing.T) {
	fixture, ready := context_map_test_fixture_init(t, context.allocator)
	if !ready do return
	defer context_map_test_fixture_close(t, &fixture)

	bindings := [1]Binding_Definition {
		context_test_binding(context_test_scalar('z'), "transient-action"),
	}
	_, activated, activation_failure := context_map_activate(
		&fixture.stack,
		context_test_map(26, 206, .Language_Context, 0, .Fallthrough, bindings[:], ""),
		&fixture.context_pending,
		&fixture.base_pending,
	)
	testing.expectf(t, activated, "context activation failed with %v", activation_failure.code)

	resolved := context_test_resolve(
		t,
		&fixture,
		Input{kind = .Key, stroke = Key_Stroke{kind = .Unicode_Scalar, scalar = 'x'}},
	)
	testing.expect_value(t, resolved.kind, Resolution_Kind.Pending)
	testing.expect_value(t, fixture.base_pending.stroke_count, u8(1))
	resolved = context_test_resolve(
		t,
		&fixture,
		Input{kind = .Key, stroke = Key_Stroke{kind = .Unicode_Scalar, scalar = 'z'}},
	)
	context_test_expect_command(t, &fixture.registry, resolved, "base-action")
	testing.expect_value(t, fixture.context_pending.stroke_count, u8(0))
	testing.expect_value(t, fixture.base_pending.stroke_count, u8(0))
}

/* Verifies a transient owner may override a direct-profile word stroke locally. */
@(test)
maps_override_word_stroke_locally :: proc(t: ^testing.T) {
	fixture, ready := context_map_test_fixture_init(t, context.allocator)
	if !ready do return
	defer context_map_test_fixture_close(t, &fixture)
	bindings := [1]Binding_Definition {
		context_test_binding(context_test_meta('f'), "transient-action"),
	}
	context_map, activated, activation_failure := context_map_activate(
		&fixture.stack,
		context_test_map(23, 203, .Transient_Interaction, 0, .Fallthrough, bindings[:], ""),
		&fixture.context_pending,
		&fixture.base_pending,
	)
	testing.expectf(t, activated, "transient activation failed with %v", activation_failure.code)
	input := Input{kind = .Key, stroke = context_test_meta('f').strokes[0]}
	resolved := context_test_resolve(t, &fixture, input)
	context_test_expect_command(t, &fixture.registry, resolved, "transient-action")
	_, ended, end_failure := context_map_end(
		&fixture.stack, context_map.handle, .Completed, &fixture.context_pending, &fixture.base_pending,
	)
	testing.expectf(t, ended, "transient completion failed with %v", end_failure.code)
	resolved = context_test_resolve(t, &fixture, input)
	context_test_expect_command(t, &fixture.registry, resolved, "base-action")
}

/* Verifies a transient owner may override a direct-profile page stroke locally. */
@(test)
maps_override_page_stroke_locally :: proc(t: ^testing.T) {
	fixture, ready := context_map_test_fixture_init(t, context.allocator)
	if !ready do return
	defer context_map_test_fixture_close(t, &fixture)
	bindings := [1]Binding_Definition {
		context_test_binding(context_test_special(.Next), "transient-action"),
	}
	context_map, activated, activation_failure := context_map_activate(
		&fixture.stack,
		context_test_map(24, 204, .Transient_Interaction, 0, .Fallthrough, bindings[:], ""),
		&fixture.context_pending,
		&fixture.base_pending,
	)
	testing.expectf(t, activated, "transient activation failed with %v", activation_failure.code)
	input := Input{kind = .Key, stroke = context_test_special(.Next).strokes[0]}
	resolved := context_test_resolve(t, &fixture, input)
	context_test_expect_command(t, &fixture.registry, resolved, "transient-action")
	_, ended, end_failure := context_map_end(
		&fixture.stack, context_map.handle, .Completed, &fixture.context_pending, &fixture.base_pending,
	)
	testing.expectf(t, ended, "transient completion failed with %v", end_failure.code)
	resolved = context_test_resolve(t, &fixture, input)
	testing.expect_value(t, resolved.kind, Resolution_Kind.Unbound)
}

/* Owner closure invalidates pending input and stale handles cannot affect successors. */
@(test)
contextual_map_owner_generations_are_checked :: proc(t: ^testing.T) {
	fixture, ready := context_map_test_fixture_init(t, context.allocator)
	if !ready {
		return
	}
	defer context_map_test_fixture_close(t, &fixture)

	sequence := context_test_sequence('x', 'y')
	bindings := [1]Binding_Definition {
		context_test_binding(sequence, "transient-action"),
	}
	first, activated, activation_failure := context_map_activate(
		&fixture.stack,
		context_test_map(
			31,
			301,
			.Transient_Interaction,
			0,
			.Reject,
			bindings[:],
			"",
		),
		&fixture.context_pending,
		&fixture.base_pending,
	)
	testing.expectf(t, activated, "first activation failed with %v", activation_failure.code)
	resolved := context_test_resolve(t, &fixture, context_test_key_input('x'))
	testing.expect_value(t, resolved.kind, Resolution_Kind.Pending)
	testing.expect_value(t, fixture.context_pending.stroke_count, u8(1))

	invalidated, invalidated_ok, invalidation_failure := context_map_owner_invalidate(
		&fixture.stack,
		first.handle.owner,
		&fixture.context_pending,
		&fixture.base_pending,
	)
	testing.expectf(t, invalidated_ok, "owner invalidation failed with %v", invalidation_failure.code)
	testing.expect_value(t, invalidated.end, Context_Map_End.Invalidated)
	testing.expect_value(t, fixture.context_pending.stroke_count, u8(0))

	second: Context_Map_Result
	second, activated, activation_failure = context_map_activate(
		&fixture.stack,
		context_test_map(
			31,
			301,
			.Transient_Interaction,
			0,
			.Reject,
			bindings[:],
			"",
		),
		&fixture.context_pending,
		&fixture.base_pending,
	)
	testing.expectf(t, activated, "second activation failed with %v", activation_failure.code)
	testing.expect(t, second.handle.owner.generation > first.handle.owner.generation)
	_, stale_ok, stale_failure := context_map_end(
		&fixture.stack,
		first.handle,
		.Completed,
		&fixture.context_pending,
		&fixture.base_pending,
	)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Owner)
	resolved = context_test_resolve(t, &fixture, context_test_key_input('x'))
	testing.expect_value(t, resolved.kind, Resolution_Kind.Pending)
}

/* Equal-priority overlap and allocation failure reject without publishing storage. */
@(test)
contextual_map_activation_is_atomic_and_bounded :: proc(t: ^testing.T) {
	fixture, ready := context_map_test_fixture_init(t, context.allocator)
	if !ready {
		return
	}
	defer context_map_test_fixture_close(t, &fixture)

	bindings := [1]Binding_Definition {
		context_test_binding(context_test_scalar('x'), "transient-action"),
	}
	_, activated, activation_failure := context_map_activate(
		&fixture.stack,
		context_test_map(41, 401, .Transient_Interaction, 7, .Fallthrough, bindings[:], ""),
		&fixture.context_pending,
		&fixture.base_pending,
	)
	testing.expectf(t, activated, "first overlap map failed with %v", activation_failure.code)
	_, activated, activation_failure = context_map_activate(
		&fixture.stack,
		context_test_map(42, 402, .Transient_Interaction, 7, .Fallthrough, bindings[:], ""),
		&fixture.context_pending,
		&fixture.base_pending,
	)
	testing.expect(t, !activated)
	testing.expect_value(t, activation_failure.code, Failure_Code.Ordering_Conflict)
	stats, stats_ok := context_map_stats(&fixture.stack)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.active_maps, u8(1))

	failing := Context_Map_Test_Failing_Allocator{backing = context.allocator}
	failed_stack: Context_Map_Stack
	initialized, init_failure := context_map_stack_init(
		&failed_stack,
		Context_ID(2),
		&fixture.registry,
		context_map_test_failing_allocator(&failing),
	)
	testing.expect(t, !initialized)
	testing.expect_value(t, init_failure.code, Failure_Code.Persistent_Memory_Limit)
	testing.expect_value(t, failing.calls, u64(1))
}

@(private)
Context_Map_Test_Fixture :: struct {
	registry:        Command_Registry,
	snapshot:        Resolution_Snapshot,
	stack:           Context_Map_Stack,
	context_pending: Context_Pending_State,
	base_pending:    Pending_State,
}

@(private)
context_map_test_fixture_init :: proc(
	t: ^testing.T,
	allocator: runtime.Allocator,
) -> (fixture: Context_Map_Test_Fixture, ok: bool) {
	definitions := [7]Command_Definition {
		context_test_command("base-action", .Ordinary),
		context_test_command("component-action", .Ordinary),
		context_test_command("transient-action", .Ordinary),
		context_test_command("prompt-delete", .Ordinary),
		context_test_command("prompt-accept", .Ordinary),
		context_test_command("context-cancel", .Cancellation),
		context_test_command("prompt-text", .Text_Input),
	}
	registry_ok, registry_failure := command_registry_init(&fixture.registry, 1, definitions[:], allocator)
	testing.expectf(t, registry_ok, "registry init failed with %v", registry_failure.code)
	if !registry_ok {
		return fixture, false
	}
	base_bindings := [4]Binding_Definition {
		context_test_binding(context_test_scalar('b'), "base-action"),
		context_test_binding(context_test_meta('f'), "base-action"),
		context_test_binding(context_test_sequence('x', 'z'), "base-action"),
		context_test_binding(context_test_special(.Tab), "base-action"),
	}
	snapshot_ok, snapshot_failure := snapshot_compile(
		&fixture.snapshot,
		&fixture.registry,
		1,
		Keymap_Definition {
			registry_generation = 1,
			bindings = base_bindings[:],
			text_fallback_name = "prompt-text",
		},
		allocator,
	)
	testing.expectf(t, snapshot_ok, "snapshot compile failed with %v", snapshot_failure.code)
	if !snapshot_ok {
		_, _ = command_registry_close(&fixture.registry)
		return fixture, false
	}
	stack_ok, stack_failure := context_map_stack_init(&fixture.stack, 1, &fixture.registry, allocator)
	testing.expectf(t, stack_ok, "context stack init failed with %v", stack_failure.code)
	if !stack_ok {
		_, _ = snapshot_close(&fixture.snapshot)
		_, _ = command_registry_close(&fixture.registry)
		return fixture, false
	}
	return fixture, true
}

@(private)
context_map_test_fixture_close :: proc(t: ^testing.T, fixture: ^Context_Map_Test_Fixture) {
	stack_closed, stack_failure := context_map_stack_close(&fixture.stack)
	testing.expectf(t, stack_closed, "context stack close failed with %v", stack_failure.code)
	snapshot_closed, snapshot_failure := snapshot_close(&fixture.snapshot)
	testing.expectf(t, snapshot_closed, "snapshot close failed with %v", snapshot_failure.code)
	registry_closed, registry_failure := command_registry_close(&fixture.registry)
	testing.expectf(t, registry_closed, "registry close failed with %v", registry_failure.code)
}

@(private)
context_test_command :: proc(name: string, invocation: Invocation_Class) -> Command_Definition {
	return Command_Definition {
		name = name,
		route = test_command_route(name),
		implementation = .Native,
		invocation = invocation,
		text_requirement = .Required if invocation == .Text_Input else .Prohibited,
		description = "Context map test command.",
	}
}

@(private)
context_test_map :: proc(
	map_id, owner_id: u64,
	precedence: Precedence_Class,
	priority: i32,
	policy: Unmatched_Input_Policy,
	bindings: []Binding_Definition,
	text_fallback_name: string,
) -> Context_Map_Definition {
	return Context_Map_Definition {
		identity = Map_Identity{id = Map_ID(map_id), revision = 1},
		name = "test-context-map",
		owner_id = Owner_ID(owner_id),
		precedence = precedence,
		priority = priority,
		bindings = bindings,
		text_fallback_name = text_fallback_name,
		unmatched_input_policy = policy,
	}
}

@(private)
context_test_binding :: proc(sequence: Key_Sequence, name: string) -> Binding_Definition {
	return Binding_Definition {
		strokes = sequence.strokes,
		stroke_count = sequence.stroke_count,
		command_name = name,
	}
}

@(private)
context_test_scalar :: proc(value: rune) -> Key_Sequence {
	sequence: Key_Sequence
	sequence.stroke_count = 1
	sequence.strokes[0] = Key_Stroke{kind = .Unicode_Scalar, scalar = value}
	return sequence
}

@(private)
context_test_control :: proc(value: rune) -> Key_Sequence {
	sequence := context_test_scalar(value)
	sequence.strokes[0].modifiers = {.Control}
	return sequence
}

@(private)
context_test_meta :: proc(value: rune) -> Key_Sequence {
	sequence := context_test_scalar(value)
	sequence.strokes[0].modifiers = {.Meta}
	return sequence
}

@(private)
context_test_special :: proc(kind: Logical_Key_Kind) -> Key_Sequence {
	sequence: Key_Sequence
	sequence.stroke_count = 1
	sequence.strokes[0] = Key_Stroke{kind = kind}
	return sequence
}

@(private)
context_test_sequence :: proc(first, second: rune) -> Key_Sequence {
	sequence: Key_Sequence
	sequence.stroke_count = 2
	sequence.strokes[0] = Key_Stroke{kind = .Unicode_Scalar, scalar = first}
	sequence.strokes[1] = Key_Stroke{kind = .Unicode_Scalar, scalar = second}
	return sequence
}

@(private)
context_test_key_input :: proc(value: rune) -> Input {
	encoded, count := context_test_encoded(value)
	return Input {
		kind = .Key,
		stroke = Key_Stroke{kind = .Unicode_Scalar, scalar = value},
		text = string(encoded[:count]),
	}
}

@(private)
context_test_encoded :: proc(value: rune) -> (encoded: [4]byte, count: int) {
	if value <= 0x7f {
		encoded[0] = byte(value)
		return encoded, 1
	}
	return encoded, 0
}

@(private)
context_test_resolve :: proc(
	t: ^testing.T,
	fixture: ^Context_Map_Test_Fixture,
	input: Input,
) -> Resolution {
	resolved, failure := resolve_contextual_input(
		&fixture.stack,
		&fixture.snapshot,
		1,
		&fixture.context_pending,
		&fixture.base_pending,
		input,
	)
	testing.expectf(t, failure.code == .None, "context resolution failed with %v", failure.code)
	return resolved
}

@(private)
context_test_expect_command :: proc(
	t: ^testing.T,
	registry: ^Command_Registry,
	resolution: Resolution,
	name: string,
) {
	testing.expect_value(t, resolution.kind, Resolution_Kind.Command)
	metadata, found, failure := command_metadata(registry, resolution.command)
	testing.expectf(t, found, "resolved command metadata failed with %v", failure.code)
	if found {
		testing.expect_value(t, metadata.name, name)
	}
}

@(private)
Context_Map_Test_Failing_Allocator :: struct {
	backing: runtime.Allocator,
	calls: u64,
}

@(private)
context_map_test_failing_allocator :: proc(data: ^Context_Map_Test_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = context_map_test_failing_allocator_proc, data = data}
}

@(private)
context_map_test_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	data := cast(^Context_Map_Test_Failing_Allocator)allocator_data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		data.calls += 1
		return nil, .Out_Of_Memory
	}
	return data.backing.procedure(
		data.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}
