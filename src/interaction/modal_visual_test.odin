// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:testing"

/* Verifies bounded visual endpoint intent updates only in one exact active context. */
@(test)
modal_visual_state_rejects_stale_context :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(821), context.allocator)
	if !ready do return
	defer command_registry_close(&registry)
	provenance := layered_test_provenance()
	states := [?]Interaction_State_Definition {{
		identity = {id = 3, revision = 1},
		name = "Visual Character",
		admitted_effects = {.Buffer, .View, .Lifecycle, .Text_Mutation},
		provenance = provenance,
	}}
	bindings := [?]Layered_Binding_Definition {
		layered_binding('h', "cursor-previous-grapheme", .Bind),
	}
	bindings[0].scope = .Profile_Specific
	maps := [?]Map_Definition {
		layered_map(1, "modal-base", .Profile_Base, 0, bindings[:]),
	}
	profiles := [?]Profile_Definition {{
		identity = {id = 2, revision = 1},
		name = "modal",
		states = states[:],
		initial_state = 3,
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
			active_state = 3,
			surfaces = surfaces[:],
		},
		active_context,
		&pending,
		DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, published, "modal visual activation failed with %v", failure.code)
	if !published do return
	request := Modal_Navigation_Request {
		profile = profiles[0].identity,
		state = states[0].identity,
		catalog_generation = 1,
		snapshot_generation = 1,
		ctx = active_context.identity,
		view_identity = 7,
		view_generation = 2,
		buffer_identity = 11,
		buffer_revision = 5,
		point_offset = 2,
	}
	started, start_failure := profile_activation_modal_visual_begin(
		&activation, request, .Character, 2, 2,
	)
	testing.expectf(t, started, "modal visual begin failed with %v", start_failure.code)
	visual, inspected := profile_activation_modal_visual_inspect(&activation)
	testing.expect(t, inspected)
	testing.expect_value(t, visual.kind, Modal_Visual_Kind.Character)
	testing.expect_value(t, visual.anchor_offset, u64(2))
	testing.expect_value(t, visual.cursor_offset, u64(2))

	updated, update_failure := profile_activation_modal_visual_update(&activation, request, 6)
	testing.expectf(t, updated, "modal visual update failed with %v", update_failure.code)
	visual, _ = profile_activation_modal_visual_inspect(&activation)
	testing.expect_value(t, visual.cursor_offset, u64(6))
	testing.expect(t, profile_activation_modal_visual_exchange(&activation))
	visual, _ = profile_activation_modal_visual_inspect(&activation)
	testing.expect_value(t, visual.anchor_offset, u64(6))
	testing.expect_value(t, visual.cursor_offset, u64(2))
	inspection, inspection_ok, inspection_failure := keymap_inspect(
		&registry,
		&activation,
		&pending,
		Inspection_Query{kind = .Snapshot},
		context.allocator,
	)
	testing.expectf(t, inspection_ok, "modal visual inspection failed with %v", inspection_failure.code)
	if inspection_ok {
		visual_copy, copied := inspection_result_modal_visual(&inspection)
		testing.expect(t, copied)
		testing.expect_value(t, visual_copy, visual)
		activation.modal_visual.cursor_offset = 9
		visual_copy, copied = inspection_result_modal_visual(&inspection)
		testing.expect(t, copied)
		testing.expect_value(t, visual_copy.cursor_offset, u64(2))
		testing.expect(t, inspection_result_close(&inspection))
		_, copied = inspection_result_modal_visual(&inspection)
		testing.expect(t, !copied)
		activation.modal_visual.cursor_offset = 2
	}

	stale := request
	stale.buffer_revision = 6
	_, update_failure = profile_activation_modal_visual_update(&activation, stale, 7)
	testing.expect_value(t, update_failure.code, Failure_Code.Stale_Context)
	_, inspected = profile_activation_modal_visual_inspect(&activation)
	testing.expect(t, !inspected)
}
