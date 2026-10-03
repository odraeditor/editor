// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:testing"

/* Verifies exact modal transitions clear pending state only after publication. */
@(test)
modal_state_transition_is_atomic :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(801), context.allocator)
	if !ready do return
	defer command_registry_close(&registry)

	provenance := layered_test_provenance()
	states := [?]Interaction_State_Definition {
		{
			identity = {id = 1, revision = 1},
			name = "Normal",
			admitted_effects = {.Buffer, .View, .Lifecycle, .Text_Mutation},
			provenance = provenance,
		},
		{
			identity = {id = 2, revision = 1},
			name = "Insert",
			admits_text_input = true,
			admitted_effects = {.Buffer, .View, .Lifecycle, .Text_Mutation},
			provenance = provenance,
		},
	}
	bindings := [?]Layered_Binding_Definition {
		layered_binding('h', "cursor-previous-grapheme", .Bind),
	}
	bindings[0].scope = .Profile_Specific
	maps := [?]Map_Definition {
		layered_map(1, "modal-base", .Profile_Base, 0, bindings[:]),
	}
	profile := Profile_Definition {
		identity = {id = 2, revision = 1},
		name = "modal",
		states = states[:],
		initial_state = 1,
		maps = maps[:],
		text_fallback_name = "insert-text",
	}
	surfaces := [?]Command_Entry_Surface_Definition {{
		identity = {id = 1, revision = 1},
		name = "extended-command",
		provenance = provenance,
	}}
	catalog := Profile_Catalog_Definition {
		generation = 1,
		profiles = []Profile_Definition{profile},
		active_profile = 2,
		active_state = 1,
		surfaces = surfaces[:],
	}
	activation: Profile_Activation
	profile_activation_init(&activation)
	pending: Pending_State
	active_context := layered_active_context(1)
	published, failure := profile_activation_replace_catalog(
		&activation,
		&registry,
		catalog,
		active_context,
		&pending,
		DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, published, "modal activation failed with %v", failure.code)
	if !published do return
	defer profile_activation_close(&activation)

	pending_request := Modal_Pending_Request {
		kind = .Count,
		profile = profile.identity,
		state = states[0].identity,
		catalog_generation = 1,
		snapshot_generation = 1,
		ctx = active_context.identity,
		view_identity = 7,
		view_generation = 1,
		buffer_identity = 11,
		buffer_revision = 3,
		sequence = scalar_sequence('2'),
		text = "2",
		count = 2,
	}
	pending_started, pending_failure := profile_activation_modal_pending_begin(
		&activation,
		pending_request,
	)
	testing.expectf(t, pending_started, "modal pending state failed with %v", pending_failure.code)
	inspected_pending, inspected := profile_activation_modal_pending_inspect(&activation)
	testing.expect(t, inspected)
	testing.expect_value(t, inspected_pending.kind, Modal_Pending_Kind.Count)
	testing.expect_value(t, inspected_pending.stroke_count, u8(1))
	testing.expect_value(t, string(inspected_pending.text[:inspected_pending.text_length]), "2")

	pending.snapshot_generation = 1
	pending.stroke_count = 1
	request := State_Transition_Request {
		catalog_generation = 1,
		snapshot_generation = 1,
		profile = profile.identity,
		source = states[0].identity,
		target = states[1].identity,
	}
	transitioned, transition_failure := profile_activation_transition_state(
		&activation,
		&registry,
		request,
		active_context,
		&pending,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, transitioned, "modal state transition failed with %v", transition_failure.code)
	testing.expect_value(t, pending.stroke_count, u8(0))
	_, state, selected := profile_activation_selection(&activation)
	testing.expect(t, selected)
	testing.expect_value(t, state.identity, states[1].identity)
	inspected_pending, inspected = profile_activation_modal_pending_inspect(&activation)
	testing.expect(t, inspected)
	testing.expect_value(t, inspected_pending, Modal_Pending_State{})

	pending_request.state = states[1].identity
	pending_request.snapshot_generation = 2
	pending_request.kind = .Operator
	pending_request.sequence = scalar_sequence('d')
	pending_request.text = "d"
	pending_request.operator = .Delete
	pending_request.operator_stage = .Target
	pending_request.operator_count_explicit = true
	pending_started, pending_failure = profile_activation_modal_pending_begin(
		&activation,
		pending_request,
	)
	testing.expectf(t, pending_started, "second pending state failed with %v", pending_failure.code)
	inspection, inspection_ok, inspection_failure := keymap_inspect(
		&registry,
		&activation,
		&pending,
		Inspection_Query{kind = .Snapshot},
		context.allocator,
	)
	testing.expectf(t, inspection_ok, "modal inspection failed with %v", inspection_failure.code)
	if inspection_ok {
		copied_pending, copied := inspection_result_modal_pending(&inspection)
		testing.expect(t, copied)
		testing.expect_value(t, copied_pending.kind, Modal_Pending_Kind.Operator)
		testing.expect_value(t, string(copied_pending.text[:copied_pending.text_length]), "d")
		activation.modal_pending.text[0] = 'x'
		copied_pending, copied = inspection_result_modal_pending(&inspection)
		testing.expect(t, copied)
		testing.expect_value(t, string(copied_pending.text[:copied_pending.text_length]), "d")
		testing.expect(t, inspection_result_close(&inspection))
		_, copied = inspection_result_modal_pending(&inspection)
		testing.expect(t, !copied)
		activation.modal_pending.text[0] = 'd'
	}
	stale := request
	stale.target = states[0].identity
	_, transition_failure = profile_activation_transition_state(
		&activation,
		&registry,
		stale,
		active_context,
		&pending,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expect_value(t, transition_failure.code, Failure_Code.Stale_Interaction_State)
	_, state, selected = profile_activation_selection(&activation)
	testing.expect(t, selected)
	testing.expect_value(t, state.identity, states[1].identity)
	inspected_pending, _ = profile_activation_modal_pending_inspect(&activation)
	testing.expect_value(t, inspected_pending.kind, Modal_Pending_Kind.Operator)

	failing := Resolver_Failing_Allocator {backing = context.allocator, fail_after = 0}
	request.source = states[1].identity
	request.target = states[0].identity
	request.snapshot_generation = 2
	_, transition_failure = profile_activation_transition_state(
		&activation,
		&registry,
		request,
		active_context,
		&pending,
		DEFAULT_RESOLUTION_POLICY,
		resolver_failing_allocator(&failing),
	)
	testing.expect_value(t, transition_failure.code, Failure_Code.Persistent_Memory_Limit)
	_, state, selected = profile_activation_selection(&activation)
	testing.expect(t, selected)
	testing.expect_value(t, state.identity, states[1].identity)
	inspected_pending, _ = profile_activation_modal_pending_inspect(&activation)
	testing.expect_value(t, inspected_pending.kind, Modal_Pending_Kind.Operator)
}

/* Verifies profile selection resets to the target initial state and rejects staleness. */
@(test)
profile_selection_uses_exact_initial_state :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(802), context.allocator)
	if !ready do return
	defer command_registry_close(&registry)

	fixture: Profile_Compatibility_Fixture
	profile_compatibility_fixture_prepare_buildable(&fixture)
	activation: Profile_Activation
	profile_activation_init(&activation)
	pending: Pending_State
	active_context := layered_active_context(1)
	published, failure := profile_activation_replace_catalog(
		&activation,
		&registry,
		fixture.catalog,
		active_context,
		&pending,
		DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, published, "profile catalog activation failed with %v", failure.code)
	if !published do return
	defer profile_activation_close(&activation)

	request := Profile_Selection_Request {
		catalog_generation = 1,
		snapshot_generation = 1,
		target = fixture.profiles[1].identity,
	}
	selected, selection_failure := profile_activation_select_profile(
		&activation,
		&registry,
		request,
		active_context,
		&pending,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, selected, "profile selection failed with %v", selection_failure.code)
	profile, state, selection_ok := profile_activation_selection(&activation)
	testing.expect(t, selection_ok)
	testing.expect_value(t, profile, fixture.profiles[1].identity)
	testing.expect_value(t, state.identity, fixture.navigation_states[0].identity)

	_, selection_failure = profile_activation_select_profile(
		&activation,
		&registry,
		request,
		active_context,
		&pending,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expect_value(t, selection_failure.code, Failure_Code.Stale_Snapshot)
}
