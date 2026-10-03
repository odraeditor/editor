// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:testing"

/* Verifies the exact accepted recovery catalog is injected and resolves before ordinary maps. */
@(test)
recovery_catalog_is_complete :: proc(t: ^testing.T) {
	catalog := protected_binding_catalog()
	testing.expect_value(t, len(catalog), PROTECTED_RECOVERY_BINDING_COUNT)
	testing.expect_value(t, catalog[0].command_name, "keyboard-quit")
	testing.expect_value(t, catalog[1].command_name, "execute-extended-command")
	testing.expect(t, len(catalog[0].reason) > 0 && len(catalog[1].reason) > 0)
	testing.expect_value(t, catalog[0].provenance.provider, "native")

	registry, ready := layered_test_registry(t, Registry_Generation(301), context.allocator)
	if !ready {
		return
	}
	defer command_registry_close(&registry)
	ordinary_bindings := [?]Layered_Binding_Definition {
		layered_binding('a', "cursor-previous-grapheme", .Bind),
	}
	maps := [?]Map_Definition {
		layered_map(301, "factory", .Factory_Fallback, 0, ordinary_bindings[:]),
	}
	snapshot: Resolution_Snapshot
	compiled, failure := profile_snapshot_compile(
		&snapshot,
		&registry,
		Snapshot_Generation(1),
		layered_profile(301, maps[:]),
		layered_active_context(301),
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, compiled, "protected profile failed: %v", failure.code)
	if !compiled {
		return
	}
	defer snapshot_close(&snapshot)
	stats, stats_ok, _ := snapshot_stats(&snapshot)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.map_count, u16(2))
	testing.expect_value(t, stats.binding_count, u16(3))

	quit, quit_ok, _ := command_lookup(&registry, "keyboard-quit")
	navigator, navigator_ok, _ := command_lookup(&registry, "execute-extended-command")
	testing.expect(t, quit_ok && navigator_ok)
	pending: Pending_State
	quit_resolution, quit_failure := resolve_input(
		&snapshot,
		Registry_Generation(301),
		&pending,
		key_input(catalog[0].sequence.strokes[0]),
	)
	testing.expect_value(t, quit_failure.code, Failure_Code.None)
	testing.expect_value(t, quit_resolution.command, quit)
	navigator_resolution, navigator_failure := resolve_input(
		&snapshot,
		Registry_Generation(301),
		&pending,
		key_input(catalog[1].sequence.strokes[0]),
	)
	testing.expect_value(t, navigator_failure.code, Failure_Code.None)
	testing.expect_value(t, navigator_resolution.command, navigator)

	data := snapshot_data(&snapshot)
	testing.expect(t, data != nil && len(data.layered_maps) == 2)
	if data != nil {
		protected_map := &data.layered_maps[0]
		testing.expect_value(t, protected_map.identity.id, PROTECTED_RECOVERY_MAP_ID)
		testing.expect_value(t, protected_map.precedence, Precedence_Class.Protected_Recovery)
		for index in int(protected_map.binding_start) ..<
		             int(protected_map.binding_start) + int(protected_map.binding_count) {
			testing.expect(t, data.layered_bindings[index].protection_reason_count > 0)
		}
	}
}

/* Verifies ordinary definitions cannot occupy, prefix, remap, or impersonate recovery policy. */
@(test)
recovery_rejects_external_overrides :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(302), context.allocator)
	if !ready {
		return
	}
	defer command_registry_close(&registry)
	catalog := protected_binding_catalog()

	exact_bindings := [?]Layered_Binding_Definition {{
		sequence = catalog[0].sequence,
		command_name = "cursor-previous-grapheme",
		operation = .Bind,
		provenance = layered_test_provenance(),
	}}
	exact_maps := [?]Map_Definition {
		layered_map(311, "exact", .User_Global, 0, exact_bindings[:]),
	}
	expect_layered_compile_failure(
		t,
		&registry,
		layered_profile(311, exact_maps[:]),
		layered_active_context(311),
		.Protected_Binding,
	)

	prefix_sequence := Key_Sequence {
		strokes = {
			0 = catalog[0].sequence.strokes[0],
			1 = scalar_key('a'),
		},
		stroke_count = 2,
	}
	prefix_bindings := [?]Layered_Binding_Definition {{
		sequence = prefix_sequence,
		command_name = "cursor-previous-grapheme",
		operation = .Bind,
		provenance = layered_test_provenance(),
	}}
	prefix_maps := [?]Map_Definition {
		layered_map(312, "prefix", .User_Global, 0, prefix_bindings[:]),
	}
	expect_layered_compile_failure(
		t,
		&registry,
		layered_profile(312, prefix_maps[:]),
		layered_active_context(312),
		.Protected_Binding,
	)

	remaps := [?]Command_Remap_Definition {{
		from_command_name = "keyboard-quit",
		to_command_name = "cursor-previous-grapheme",
		provenance = layered_test_provenance(),
	}}
	ordinary_bindings := [?]Layered_Binding_Definition {
		layered_binding('a', "cursor-previous-grapheme", .Bind),
	}
	remap_maps := [?]Map_Definition {
		layered_map(313, "remap", .User_Global, 0, ordinary_bindings[:]),
	}
	remap_maps[0].remaps = remaps[:]
	expect_layered_compile_failure(
		t,
		&registry,
		layered_profile(313, remap_maps[:]),
		layered_active_context(313),
		.Protected_Binding,
	)

	reserved_maps := [?]Map_Definition {
		layered_map(314, "reserved", .Protected_Recovery, 0, ordinary_bindings[:]),
	}
	expect_layered_compile_failure(
		t,
		&registry,
		layered_profile(314, reserved_maps[:]),
		layered_active_context(314),
		.Protected_Binding,
	)
}

/* Verifies unsupported protected strokes reject activation before allocating a candidate. */
@(test)
recovery_requires_logical_strokes :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(303), context.allocator)
	if !ready {
		return
	}
	defer command_registry_close(&registry)
	bindings := [?]Layered_Binding_Definition {
		layered_binding('a', "cursor-previous-grapheme", .Bind),
	}
	maps := [?]Map_Definition {
		layered_map(321, "factory", .Factory_Fallback, 0, bindings[:]),
	}
	policy := DEFAULT_RESOLUTION_POLICY
	policy.frontend.meta_modified_unicode = false
	snapshot: Resolution_Snapshot
	compiled, failure := profile_snapshot_compile(
		&snapshot,
		&registry,
		Snapshot_Generation(1),
		layered_profile(321, maps[:]),
		layered_active_context(321),
		policy,
		context.allocator,
	)
	testing.expect(t, !compiled)
	testing.expect_value(t, failure.code, Failure_Code.Unsupported_Protected_Input)
	testing.expect_value(t, failure.binding_index, u32(1))
	testing.expect(t, snapshot.state == nil)
}

/* Verifies transient and component maps cannot intercept a protected recovery sequence. */
@(test)
recovery_rejects_map_interception :: proc(t: ^testing.T) {
	fixture, ready := context_map_test_fixture_init(t, context.allocator)
	if !ready {
		return
	}
	defer context_map_test_fixture_close(t, &fixture)
	catalog := protected_binding_catalog()
	bindings := [1]Binding_Definition {{
		strokes = catalog[0].sequence.strokes,
		stroke_count = catalog[0].sequence.stroke_count,
		command_name = "context-cancel",
	}}
	_, activated, failure := context_map_activate(
		&fixture.stack,
		context_test_map(
			331,
			431,
			.Transient_Interaction,
			0,
			.Reject,
			bindings[:],
			"",
		),
		&fixture.context_pending,
		&fixture.base_pending,
	)
	testing.expect(t, !activated)
	testing.expect_value(t, failure.code, Failure_Code.Protected_Binding)
}
