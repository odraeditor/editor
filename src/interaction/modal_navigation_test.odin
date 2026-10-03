// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:testing"

/* Verifies decimal counts compose, disambiguate zero, and reject overflow atomically. */
@(test)
modal_navigation_counts_are_checked_and_bounded :: proc(t: ^testing.T) {
	registry: Command_Registry
	activation: Profile_Activation
	request: Modal_Navigation_Request
	if !modal_navigation_fixture_init(t, &registry, &activation, &request) do return
	defer command_registry_close(&registry)
	defer profile_activation_close(&activation)
	inputs := [?]Input {
		modal_navigation_test_input('1', "1"),
		modal_navigation_test_input('2', "2"),
		modal_navigation_test_input('0', "0"),
	}
	for input in inputs {
		request.input = input
		result, composed, failure := modal_navigation_compose(&activation, request)
		testing.expectf(t, composed, "count composition failed with %v", failure.code)
		testing.expect_value(t, result.disposition, Modal_Navigation_Disposition.Pending)
	}
	pending, inspected := profile_activation_modal_pending_inspect(&activation)
	testing.expect(t, inspected)
	testing.expect_value(t, pending.count, u64(120))
	request.input = modal_navigation_test_input('h', "h")
	result, composed, failure := modal_navigation_compose(&activation, request)
	testing.expectf(t, composed, "count completion failed with %v", failure.code)
	testing.expect_value(t, result.disposition, Modal_Navigation_Disposition.Pass_Through)
	testing.expect_value(t, result.count, u64(120))
	testing.expect(t, profile_activation_modal_pending_cancel(&activation))
	request.input = modal_navigation_test_input('0', "0")
	result, composed, failure = modal_navigation_compose(&activation, request)
	testing.expectf(t, composed, "zero movement failed with %v", failure.code)
	testing.expect_value(t, result.disposition, Modal_Navigation_Disposition.Pass_Through)
	testing.expect_value(t, result.count, u64(1))

	for digit in "4294967296" {
		request.input = modal_navigation_test_input(digit, "")
		_, composed, failure = modal_navigation_compose(&activation, request)
		if failure.code != .None do break
	}
	testing.expect(t, !composed)
	testing.expect_value(t, failure.code, Failure_Code.Sequence_Limit)
	pending, _ = profile_activation_modal_pending_inspect(&activation)
	testing.expect_value(t, pending, Modal_Pending_State{})
	combined, combined_ok := modal_count_combine(12, 34)
	testing.expect(t, combined_ok)
	testing.expect_value(t, combined, u64(408))
	_, combined_ok = modal_count_combine(MAX_MODAL_COUNT, 2)
	testing.expect(t, !combined_ok)
}

/* Verifies character targets retain one repeatable same or opposite operation. */
@(test)
modal_character_targets_are_repeatable_and_revision_bound :: proc(t: ^testing.T) {
	registry: Command_Registry
	activation: Profile_Activation
	request: Modal_Navigation_Request
	if !modal_navigation_fixture_init(t, &registry, &activation, &request) do return
	defer command_registry_close(&registry)
	defer profile_activation_close(&activation)
	request.input = modal_navigation_test_input('2', "2")
	_, composed, _ := modal_navigation_compose(&activation, request)
	testing.expect(t, composed)
	request.input = modal_navigation_test_input('f', "f")
	result: Modal_Navigation_Result
	failure: Failure_Context
	result, composed, failure = modal_navigation_compose(&activation, request)
	testing.expectf(t, composed, "character prefix failed with %v", failure.code)
	testing.expect_value(t, result.disposition, Modal_Navigation_Disposition.Pending)
	request.input = modal_navigation_test_input('🙂', "🙂")
	result, composed, failure = modal_navigation_compose(&activation, request)
	testing.expectf(t, composed, "character target failed with %v", failure.code)
	testing.expect_value(t, result.disposition, Modal_Navigation_Disposition.Character_Target)
	testing.expect_value(t, result.count, u64(2))
	testing.expect_value(t, result.character_target, Modal_Character_Target_Kind.Find_Next)
	testing.expect_value(t, modal_navigation_result_text(&result), "🙂")
	confirmed, confirm_failure := profile_activation_modal_character_search_confirm(
		&activation,
		request,
		result.character_target,
		modal_navigation_result_text(&result),
	)
	testing.expectf(t, confirmed, "character search confirmation failed with %v", confirm_failure.code)
	retained, retained_ok := profile_activation_modal_character_search_inspect(&activation)
	testing.expect(t, retained_ok && retained.valid)
	testing.expect_value(t, string(retained.text[:retained.text_length]), "🙂")
	request.input = modal_navigation_test_input(';', ";")
	result, composed, failure = modal_navigation_compose(&activation, request)
	testing.expectf(t, composed, "same-direction repeat failed with %v", failure.code)
	testing.expect_value(t, result.disposition, Modal_Navigation_Disposition.Repeat_Character_Target)
	testing.expect_value(t, result.character_target, Modal_Character_Target_Kind.Find_Next)
	request.input = modal_navigation_test_input('3', "3")
	_, composed, _ = modal_navigation_compose(&activation, request)
	testing.expect(t, composed)
	request.input = modal_navigation_test_input(',', ",")
	result, composed, failure = modal_navigation_compose(&activation, request)
	testing.expectf(t, composed, "opposite-direction repeat failed with %v", failure.code)
	testing.expect_value(t, result.count, u64(3))
	testing.expect_value(t, result.character_target, Modal_Character_Target_Kind.Find_Previous)

	request.buffer_revision += 1
	request.input = modal_navigation_test_input(';', ";")
	_, composed, failure = modal_navigation_compose(&activation, request)
	testing.expect(t, !composed)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Context)
	retained, _ = profile_activation_modal_character_search_inspect(&activation)
	testing.expect(t, !retained.valid)
}

/* Verifies cancellation and stale pending contexts leave no partial composition. */
@(test)
modal_navigation_pending_state_cancels_atomically :: proc(t: ^testing.T) {
	registry: Command_Registry
	activation: Profile_Activation
	request: Modal_Navigation_Request
	if !modal_navigation_fixture_init(t, &registry, &activation, &request) do return
	defer command_registry_close(&registry)
	defer profile_activation_close(&activation)
	request.input = modal_navigation_test_input('9', "9")
	_, composed, _ := modal_navigation_compose(&activation, request)
	testing.expect(t, composed)
	request.input = Input{kind = .Key, stroke = Key_Stroke{kind = .Escape}}
	result: Modal_Navigation_Result
	failure: Failure_Context
	result, composed, failure = modal_navigation_compose(&activation, request)
	testing.expectf(t, composed, "cancellation failed with %v", failure.code)
	testing.expect_value(t, result.disposition, Modal_Navigation_Disposition.Cancelled)
	pending, _ := profile_activation_modal_pending_inspect(&activation)
	testing.expect_value(t, pending, Modal_Pending_State{})
	request.input = modal_navigation_test_input('4', "4")
	_, composed, _ = modal_navigation_compose(&activation, request)
	testing.expect(t, composed)
	request.view_identity += 1
	request.input = modal_navigation_test_input('h', "h")
	_, composed, failure = modal_navigation_compose(&activation, request)
	testing.expect(t, !composed)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Context)
	pending, _ = profile_activation_modal_pending_inspect(&activation)
	testing.expect_value(t, pending, Modal_Pending_State{})
}

@(private)
modal_navigation_fixture_init :: proc(
	t: ^testing.T,
	registry: ^Command_Registry,
	activation: ^Profile_Activation,
	request: ^Modal_Navigation_Request,
) -> bool {
	ready: bool
	registry^, ready = layered_test_registry(t, Registry_Generation(811), context.allocator)
	if !ready do return false
	provenance := layered_test_provenance()
	states := [?]Interaction_State_Definition {{
		identity = {id = 1, revision = 1},
		name = "Normal",
		admitted_effects = {.Buffer, .View, .Lifecycle, .Text_Mutation},
		provenance = provenance,
	}}
	bindings := [?]Layered_Binding_Definition {layered_binding('h', "cursor-previous-grapheme", .Bind)}
	bindings[0].scope = .Profile_Specific
	maps := [?]Map_Definition {layered_map(1, "modal-base", .Profile_Base, 0, bindings[:])}
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
	profile_activation_init(activation)
	pending: Pending_State
	active_context := layered_active_context(1)
	published, failure := profile_activation_replace_catalog(
		activation,
		registry,
		catalog,
		active_context,
		&pending,
		DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, published, "modal activation failed with %v", failure.code)
	if !published do return false
	request^ = Modal_Navigation_Request {
		profile = profile.identity,
		state = states[0].identity,
		catalog_generation = 1,
		snapshot_generation = 1,
		ctx = active_context.identity,
		view_identity = 7,
		view_generation = 1,
		buffer_identity = 11,
		buffer_revision = 0,
	}
	return true
}

@(private)
modal_navigation_test_input :: proc(value: rune, text: string) -> Input {
	return Input {
		kind = .Key,
		stroke = Key_Stroke{kind = .Unicode_Scalar, scalar = value},
		text = text,
	}
}
