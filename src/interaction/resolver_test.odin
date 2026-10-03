// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "base:runtime"
import "core:mem"
import "core:testing"

/* Verifies registry identities, copied metadata, limits, and retained-map cleanup. */
@(test)
command_registry_owns_one_checked_generation :: proc(t: ^testing.T) {
	definitions := base_command_definitions()
	registry: Command_Registry
	ready, failure := command_registry_init(
		&registry,
		Registry_Generation(7),
		definitions[:],
		context.allocator,
	)
	testing.expect_value(t, failure.code, Failure_Code.None)
	testing.expect(t, ready)
	if !ready {
		return
	}

	stats, stats_ok, _ := command_registry_stats(&registry)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.generation, Registry_Generation(7))
	testing.expect_value(t, stats.command_count, u16(len(definitions)))
	testing.expect(t, stats.storage_bytes > 0)

	insert, found, _ := command_lookup(&registry, "insert-text")
	testing.expect(t, found)
	metadata, metadata_ok, _ := command_metadata(&registry, insert)
	testing.expect(t, metadata_ok)
	testing.expect_value(t, metadata.name, "insert-text")
	testing.expect_value(t, metadata.invocation, Invocation_Class.Text_Input)
	testing.expect_value(t, metadata.text_requirement, Text_Requirement.Required)

	stale := insert
	stale.registry_generation = Registry_Generation(8)
	_, stale_ok, stale_failure := command_metadata(&registry, stale)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Invalid_Command)

	closed, close_failure := command_registry_close(&registry)
	testing.expect(t, closed)
	testing.expect_value(t, close_failure.code, Failure_Code.None)
}

/* Verifies exact, prefix, fallback, cancellation, discard, and stale-state outcomes. */
@(test)
compiled_snapshot_resolves_bounded_input :: proc(t: ^testing.T) {
	registry, snapshot, ready := make_resolver_fixture(t)
	if !ready {
		return
	}
	defer close_resolver_fixture(t, &registry, &snapshot)

	left, left_ok, _ := command_lookup(&registry, "cursor-previous-grapheme")
	insert, insert_ok, _ := command_lookup(&registry, "insert-text")
	uppercase, uppercase_ok, _ := command_lookup(&registry, "uppercase-current-line")
	cancel, cancel_ok, _ := command_lookup(&registry, "cancel-pending-input")
	testing.expect(t, left_ok && insert_ok && uppercase_ok && cancel_ok)

	pending: Pending_State
	resolved, failure := resolve_input(
		&snapshot,
		Registry_Generation(7),
		&pending,
		key_input(special_key(.Left)),
	)
	testing.expect_value(t, failure.code, Failure_Code.None)
	testing.expect_value(t, resolved.kind, Resolution_Kind.Command)
	testing.expect_value(t, resolved.command, left)

	resolved, _ = resolve_input(
		&snapshot,
		Registry_Generation(7),
		&pending,
		key_input(control_key('x')),
	)
	testing.expect_value(t, resolved.kind, Resolution_Kind.Pending)
	testing.expect_value(t, pending.stroke_count, u8(1))
	resolved, _ = resolve_input(
		&snapshot,
		Registry_Generation(7),
		&pending,
		key_input(scalar_key('u')),
	)
	testing.expect_value(t, resolved.kind, Resolution_Kind.Command)
	testing.expect_value(t, resolved.command, uppercase)
	testing.expect_value(t, pending.stroke_count, u8(0))

	resolved, _ = resolve_input(
		&snapshot,
		Registry_Generation(7),
		&pending,
		Input{kind = .Key, stroke = scalar_key('q'), text = "q"},
	)
	testing.expect_value(t, resolved.kind, Resolution_Kind.Command)
	testing.expect_value(t, resolved.command, insert)
	testing.expect_value(t, resolved.text, "q")

	resolve_input(
		&snapshot,
		Registry_Generation(7),
		&pending,
		key_input(control_key('x')),
	)
	resolved, _ = resolve_input(
		&snapshot,
		Registry_Generation(7),
		&pending,
		Input{kind = .Key, stroke = scalar_key('q'), text = "q"},
	)
	testing.expect_value(t, resolved.kind, Resolution_Kind.Unbound)
	testing.expect_value(t, pending.stroke_count, u8(0))

	resolve_input(
		&snapshot,
		Registry_Generation(7),
		&pending,
		key_input(control_key('x')),
	)
	resolved, _ = resolve_input(
		&snapshot,
		Registry_Generation(7),
		&pending,
		key_input(control_key('g')),
	)
	testing.expect_value(t, resolved.kind, Resolution_Kind.Command)
	testing.expect_value(t, resolved.command, cancel)
	testing.expect_value(t, pending.stroke_count, u8(0))

	resolved, failure = resolve_input(
		&snapshot,
		Registry_Generation(8),
		&pending,
		key_input(special_key(.Left)),
	)
	testing.expect_value(t, resolved.kind, Resolution_Kind.Rejected)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Registry)

	pending.snapshot_generation = Snapshot_Generation(8)
	pending.stroke_count = 1
	resolved, failure = resolve_input(
		&snapshot,
		Registry_Generation(7),
		&pending,
		key_input(scalar_key('u')),
	)
	testing.expect_value(t, resolved.kind, Resolution_Kind.Rejected)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Snapshot)
	testing.expect_value(t, pending.stroke_count, u8(0))
}

/* Verifies invalid candidate maps preserve the previously confirmed snapshot. */
@(test)
snapshot_activation_is_atomic :: proc(t: ^testing.T) {
	registry, snapshot, ready := make_resolver_fixture(t)
	if !ready {
		return
	}
	defer close_resolver_fixture(t, &registry, &snapshot)

	before, before_ok, _ := snapshot_stats(&snapshot)
	testing.expect(t, before_ok)
	body := base_bindings()
	ambiguous := [2]Binding_Definition {
		body[1],
		{
			strokes = {
				0 = control_key('x'),
				1 = scalar_key('u'),
				2 = scalar_key('z'),
			},
			stroke_count = 3,
			command_name = "request-editor-exit",
		},
	}
	activated, failure := snapshot_compile(
		&snapshot,
		&registry,
		Snapshot_Generation(2),
		Keymap_Definition {
			registry_generation = Registry_Generation(7),
			bindings = ambiguous[:],
			text_fallback_name = "insert-text",
		},
		context.allocator,
	)
	testing.expect(t, !activated)
	testing.expect_value(t, failure.code, Failure_Code.Ambiguous_Binding)
	after, after_ok, _ := snapshot_stats(&snapshot)
	testing.expect(t, after_ok)
	testing.expect_value(t, after.generation, before.generation)
	testing.expect_value(t, after.binding_count, before.binding_count)

	second: Resolution_Snapshot
	second_ready, second_failure := snapshot_compile(
		&second,
		&registry,
		Snapshot_Generation(3),
		Keymap_Definition {
			registry_generation = Registry_Generation(7),
			bindings = body[:],
			text_fallback_name = "insert-text",
		},
		context.allocator,
	)
	testing.expect(t, !second_ready)
	testing.expect_value(t, second_failure.code, Failure_Code.Snapshot_Limit)
}

/* Verifies compiled lookup matches a simple bounded reference model. */
@(test)
compiled_resolution_matches_reference_model :: proc(t: ^testing.T) {
	definitions := base_command_definitions()
	registry: Command_Registry
	ready, _ := command_registry_init(
		&registry,
		Registry_Generation(31),
		definitions[:],
		context.allocator,
	)
	testing.expect(t, ready)
	if !ready {
		return
	}

	bindings: [64]Binding_Definition
	for &binding, index in bindings {
		binding.strokes[0] = scalar_key(rune(0x4e00 + index))
		binding.stroke_count = 1
		binding.command_name = "cursor-previous-grapheme"
	}
	definition := Keymap_Definition {
		registry_generation = Registry_Generation(31),
		bindings = bindings[:],
		text_fallback_name = "insert-text",
	}
	snapshot: Resolution_Snapshot
	compiled, compile_failure := snapshot_compile(
		&snapshot,
		&registry,
		Snapshot_Generation(41),
		definition,
		context.allocator,
	)
	testing.expectf(
		t,
		compiled,
		"snapshot compilation failed: %v at binding %d",
		compile_failure.code,
		compile_failure.binding_index,
	)
	if !compiled {
		command_registry_close(&registry)
		return
	}

	state := u64(0x5eed)
	for _ in 0 ..< 2_048 {
		state = state * 6_364_136_223_846_793_005 + 1
		value := rune(0x4df0 + state % 112)
		text := ""
		if state & 1 == 1 {
			text = "t"
		}
		input := Input{kind = .Key, stroke = scalar_key(value), text = text}
		pending: Pending_State
		actual, actual_failure := resolve_input(
			&snapshot,
			Registry_Generation(31),
			&pending,
			input,
		)
		expected := reference_single_stroke(definition, input)
		testing.expect_value(t, actual_failure.code, Failure_Code.None)
		testing.expect_value(t, actual.kind, expected)
	}

	snapshot_close(&snapshot)
	command_registry_close(&registry)
}

/* Verifies allocation failures and normal shutdown release all owned storage. */
@(test)
registry_and_snapshot_failures_leave_no_storage :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	failing := Resolver_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = 0,
	}
	definitions := base_command_definitions()
	registry: Command_Registry
	ready, failure := command_registry_init(
		&registry,
		Registry_Generation(51),
		definitions[:],
		resolver_failing_allocator(&failing),
	)
	testing.expect(t, !ready)
	testing.expect_value(t, failure.code, Failure_Code.Persistent_Memory_Limit)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))

	failing.fail_after = max(u64)
	ready, _ = command_registry_init(
		&registry,
		Registry_Generation(51),
		definitions[:],
		resolver_failing_allocator(&failing),
	)
	testing.expect(t, ready)
	if !ready {
		return
	}
	snapshot: Resolution_Snapshot
	bindings := base_bindings()
	failing.fail_after = failing.successful_allocations
	compiled, compile_failure := snapshot_compile(
		&snapshot,
		&registry,
		Snapshot_Generation(61),
		Keymap_Definition {
			registry_generation = Registry_Generation(51),
			bindings = bindings[:],
			text_fallback_name = "insert-text",
		},
		resolver_failing_allocator(&failing),
	)
	testing.expect(t, !compiled)
	testing.expect_value(t, compile_failure.code, Failure_Code.Persistent_Memory_Limit)

	failing.fail_after = max(u64)
	compiled, _ = snapshot_compile(
		&snapshot,
		&registry,
		Snapshot_Generation(61),
		Keymap_Definition {
			registry_generation = Registry_Generation(51),
			bindings = bindings[:],
			text_fallback_name = "insert-text",
		},
		resolver_failing_allocator(&failing),
	)
	testing.expect(t, compiled)
	retained_closed, retained_failure := command_registry_close(&registry)
	testing.expect(t, !retained_closed)
	testing.expect_value(t, retained_failure.code, Failure_Code.Retained_Snapshot)
	snapshot_closed, _ := snapshot_close(&snapshot)
	registry_closed, _ := command_registry_close(&registry)
	testing.expect(t, snapshot_closed && registry_closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(private)
base_command_definitions :: proc() -> [8]Command_Definition {
	return {
		{
			name = "insert-text",
			route = test_command_route("insert-text"),
			implementation = .Native,
			invocation = .Text_Input,
			text_requirement = .Required,
			effects = {.Buffer, .View, .Text_Mutation},
			description = "Insert committed text.",
		},
		{
			name = "cursor-previous-grapheme",
			route = test_command_route("cursor-previous-grapheme"),
			implementation = .Native,
			invocation = .Ordinary,
			text_requirement = .Prohibited,
			effects = {.View},
			description = "Move to the previous grapheme.",
		},
		{
			name = "uppercase-current-line",
			route = test_command_route("uppercase-current-line"),
			implementation = .Racket,
			invocation = .Ordinary,
			text_requirement = .Prohibited,
			effects = {.Buffer, .View, .Text_Mutation},
			description = "Uppercase the current line.",
		},
		{
			name = "request-editor-exit",
			route = test_command_route("request-editor-exit"),
			implementation = .Native,
			invocation = .Ordinary,
			text_requirement = .Prohibited,
			effects = {.Lifecycle},
			description = "Request orderly editor exit.",
		},
		{
			name = "cancel-pending-input",
			route = test_command_route("cancel-pending-input"),
			implementation = .Native,
			invocation = .Cancellation,
			text_requirement = .Prohibited,
			effects = {},
			description = "Cancel pending input.",
		},
		{
			name = "unused-command",
			route = test_command_route("unused-command"),
			implementation = .Native,
			invocation = .Ordinary,
			text_requirement = .Optional,
			effects = {},
			description = "Remain available for registry checks.",
		},
		{
			name = "keyboard-quit",
			route = test_command_route("keyboard-quit"),
			implementation = .Native,
			invocation = .Cancellation,
			text_requirement = .Prohibited,
			effects = {.View},
			description = "Recover from active interaction state.",
		},
		{
			name = "execute-extended-command",
			route = test_command_route("execute-extended-command"),
			implementation = .Native,
			invocation = .Ordinary,
			text_requirement = .Prohibited,
			effects = {.Lifecycle},
			description = "Open interactive command navigation.",
		},
	}
}

@(private)
base_bindings :: proc() -> [4]Binding_Definition {
	return {
		{
			strokes = {0 = special_key(.Left)},
			stroke_count = 1,
			command_name = "cursor-previous-grapheme",
		},
		{
			strokes = {0 = control_key('x'), 1 = scalar_key('u')},
			stroke_count = 2,
			command_name = "uppercase-current-line",
		},
		{
			strokes = {0 = control_key('x'), 1 = scalar_key('x')},
			stroke_count = 2,
			command_name = "request-editor-exit",
		},
		{
			strokes = {0 = control_key('g')},
			stroke_count = 1,
			command_name = "cancel-pending-input",
		},
	}
}

@(private)
make_resolver_fixture :: proc(
	t: ^testing.T,
) -> (registry: Command_Registry, snapshot: Resolution_Snapshot, ok: bool) {
	definitions := base_command_definitions()
	registry_ok, registry_failure := command_registry_init(
		&registry,
		Registry_Generation(7),
		definitions[:],
		context.allocator,
	)
	testing.expect_value(t, registry_failure.code, Failure_Code.None)
	testing.expect(t, registry_ok)
	if !registry_ok {
		return {}, {}, false
	}
	bindings := base_bindings()
	snapshot_ok, snapshot_failure := snapshot_compile(
		&snapshot,
		&registry,
		Snapshot_Generation(1),
		Keymap_Definition {
			registry_generation = Registry_Generation(7),
			bindings = bindings[:],
			text_fallback_name = "insert-text",
		},
		context.allocator,
	)
	testing.expect_value(t, snapshot_failure.code, Failure_Code.None)
	testing.expect(t, snapshot_ok)
	if !snapshot_ok {
		command_registry_close(&registry)
		return {}, {}, false
	}
	return registry, snapshot, true
}

@(private)
close_resolver_fixture :: proc(
	t: ^testing.T,
	registry: ^Command_Registry,
	snapshot: ^Resolution_Snapshot,
) {
	snapshot_closed, _ := snapshot_close(snapshot)
	registry_closed, _ := command_registry_close(registry)
	testing.expect(t, snapshot_closed && registry_closed)
}

@(private)
special_key :: proc(kind: Logical_Key_Kind) -> Key_Stroke {
	return Key_Stroke{kind = kind}
}

@(private)
scalar_key :: proc(value: rune) -> Key_Stroke {
	return Key_Stroke{kind = .Unicode_Scalar, scalar = value}
}

@(private)
control_key :: proc(value: rune) -> Key_Stroke {
	return Key_Stroke {
		kind = .Unicode_Scalar,
		scalar = value,
		modifiers = {.Control},
	}
}

@(private)
key_input :: proc(stroke: Key_Stroke) -> Input {
	return Input{kind = .Key, stroke = stroke}
}

@(private)
reference_single_stroke :: proc(
	definition: Keymap_Definition,
	input: Input,
) -> Resolution_Kind {
	for binding in definition.bindings {
		if binding.stroke_count == 1 && binding.strokes[0] == input.stroke {
			return .Command
		}
	}
	if len(input.text) > 0 {
		return .Command
	}
	return .Unbound
}

@(private)
Resolver_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
resolver_failing_allocator :: proc(data: ^Resolver_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator {
		procedure = resolver_failing_allocator_proc,
		data = data,
	}
}

@(private)
resolver_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := (^Resolver_Failing_Allocator)(allocator_data)
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after {
			return nil, .Out_Of_Memory
		}
		allocator.successful_allocations += 1
	}
	return allocator.backing.procedure(
		allocator.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}
