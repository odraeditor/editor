// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:testing"

/* Verifies command entry retains, exposes, claims, and rejects exact source context. */
@(test)
modal_command_entry_is_one_checked_transient :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(831), context.allocator)
	if !ready do return
	defer command_registry_close(&registry)
	provenance := layered_test_provenance()
	states := [?]Interaction_State_Definition {{
		identity = {id = 1, revision = 1},
		name = "Normal",
		admitted_effects = {.Buffer, .View, .Lifecycle, .Text_Mutation},
		provenance = provenance,
	}}
	bindings := [?]Layered_Binding_Definition {
		layered_binding(':', "execute-extended-command", .Bind),
	}
	bindings[0].scope = .Profile_Specific
	maps := [?]Map_Definition {
		layered_map(1, "modal-base", .Profile_Base, 0, bindings[:]),
	}
	profiles := [?]Profile_Definition {{
		identity = {id = 2, revision = 1},
		name = "modal",
		states = states[:],
		initial_state = 1,
		maps = maps[:],
		text_fallback_name = "insert-text",
	}}
	surfaces := [?]Command_Entry_Surface_Definition {{
		identity = {id = 1, revision = 1},
		name = "extended-command",
		provenance = provenance,
	}}
	activation: Profile_Activation
	profile_activation_init(&activation)
	defer profile_activation_close(&activation)
	pending: Pending_State
	active_context := layered_active_context(1)
	published, failure := profile_activation_replace_catalog(
		&activation,
		&registry,
		Profile_Catalog_Definition {
			generation = 1,
			profiles = profiles[:],
			active_profile = 2,
			active_state = 1,
			surfaces = surfaces[:],
		},
		active_context,
		&pending,
		DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, published, "modal activation failed with %v", failure.code)
	if !published do return
	request := Modal_Command_Entry_Request {
		profile = profiles[0].identity,
		state = states[0].identity,
		catalog_generation = 1,
		snapshot_generation = 1,
		ctx = active_context.identity,
		view_identity = 7,
		view_generation = 2,
		buffer_identity = 11,
		buffer_revision = 5,
		sequence = scalar_sequence(':'),
		surface = surfaces[0].identity,
	}
	started, start_failure := profile_activation_modal_command_entry_begin(&activation, request)
	testing.expectf(t, started, "command entry failed with %v", start_failure.code)
	retained, retained_ok := profile_activation_modal_pending_inspect(&activation)
	testing.expect(t, retained_ok)
	testing.expect_value(t, retained.kind, Modal_Pending_Kind.Command_Entry)
	testing.expect_value(t, retained.command_entry_surface, surfaces[0].identity)
	inspection, inspected, inspection_failure := keymap_inspect(
		&registry,
		&activation,
		&pending,
		Inspection_Query{kind = .Snapshot},
		context.allocator,
	)
	testing.expectf(t, inspected, "command entry inspection failed with %v", inspection_failure.code)
	if inspected {
		copy, copied := inspection_result_modal_pending(&inspection)
		testing.expect(t, copied)
		testing.expect_value(t, copy.command_entry_surface, surfaces[0].identity)
		testing.expect(t, inspection_result_close(&inspection))
	}
	claimed, claim_failure := profile_activation_modal_command_entry_claim(&activation, request)
	testing.expectf(t, claimed, "command entry claim failed with %v", claim_failure.code)
	retained, _ = profile_activation_modal_pending_inspect(&activation)
	testing.expect_value(t, retained, Modal_Pending_State{})

	_, _ = profile_activation_modal_command_entry_begin(&activation, request)
	stale := request
	stale.buffer_revision += 1
	claimed, claim_failure = profile_activation_modal_command_entry_claim(&activation, stale)
	testing.expect(t, !claimed)
	testing.expect_value(t, claim_failure.code, Failure_Code.Stale_Context)
	retained, _ = profile_activation_modal_pending_inspect(&activation)
	testing.expect_value(t, retained, Modal_Pending_State{})
}
