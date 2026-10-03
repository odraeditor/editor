// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:testing"

/* Verifies Visual operators resolve immediately against the canonical active selection. */
@(test)
modal_visual_operator_uses_active_selection :: proc(t: ^testing.T) {
	registry: Command_Registry
	activation: Profile_Activation
	request: Modal_Navigation_Request
	if !modal_navigation_fixture_init(t, &registry, &activation, &request) do return
	defer command_registry_close(&registry)
	defer profile_activation_close(&activation)
	activation.active_state.name = "Visual Character"
	operator_request := modal_operator_test_request(request)
	operator_request.input = modal_navigation_test_input('d', "d")
	operation, composed, failure := modal_operator_compose(
		&activation, operator_request,
	)
	testing.expectf(t, composed, "visual operator failed with %v", failure.code)
	testing.expect_value(t, operation.disposition, Modal_Operator_Disposition.Ready)
	testing.expect_value(t, operation.operator, Modal_Operator_Kind.Delete)
	testing.expect_value(t, operation.target, Modal_Operator_Target_Kind.Active_Selection)
}

/* Verifies operators compose movement, doubled-line, text-object, and checked counts. */
@(test)
modal_operators_compose_bounded_targets :: proc(t: ^testing.T) {
	registry: Command_Registry
	activation: Profile_Activation
	navigation: Modal_Navigation_Request
	if !modal_navigation_fixture_init(t, &registry, &activation, &navigation) do return
	defer command_registry_close(&registry)
	defer profile_activation_close(&activation)
	request := modal_operator_test_request(navigation)

	modal_operator_test_pending(t, &activation, &request, '2')
	modal_operator_test_pending(t, &activation, &request, 'd')
	modal_operator_test_pending(t, &activation, &request, '3')
	request.input = modal_navigation_test_input('w', "w")
	result, composed, failure := modal_operator_compose(&activation, request)
	testing.expectf(t, composed, "counted movement target failed with %v", failure.code)
	testing.expect_value(t, result.disposition, Modal_Operator_Disposition.Ready)
	testing.expect_value(t, result.operator, Modal_Operator_Kind.Delete)
	testing.expect_value(t, result.target, Modal_Operator_Target_Kind.Next_Word_Start)
	testing.expect_value(t, result.count, u64(6))
	testing.expect(t, result.count_explicit)
	testing.expect_value(t, result.capture.buffer_revision, request.buffer_revision)

	modal_operator_test_pending(t, &activation, &request, 'c')
	request.input = modal_navigation_test_input('c', "c")
	result, composed, failure = modal_operator_compose(&activation, request)
	testing.expectf(t, composed, "doubled-line target failed with %v", failure.code)
	testing.expect_value(t, result.operator, Modal_Operator_Kind.Change)
	testing.expect_value(t, result.target, Modal_Operator_Target_Kind.Line)

	modal_operator_test_pending(t, &activation, &request, 'y')
	modal_operator_test_pending(t, &activation, &request, 'a')
	request.input = modal_navigation_test_input('p', "p")
	result, composed, failure = modal_operator_compose(&activation, request)
	testing.expectf(t, composed, "paragraph text object failed with %v", failure.code)
	testing.expect_value(t, result.operator, Modal_Operator_Kind.Yank)
	testing.expect_value(t, result.target, Modal_Operator_Target_Kind.Around_Paragraph)

	modal_operator_test_pending(t, &activation, &request, '>')
	modal_operator_test_pending(t, &activation, &request, 'g')
	request.input = modal_navigation_test_input('g', "g")
	result, composed, failure = modal_operator_compose(&activation, request)
	testing.expectf(t, composed, "buffer target failed with %v", failure.code)
	testing.expect_value(t, result.operator, Modal_Operator_Kind.Indent)
	testing.expect_value(t, result.target, Modal_Operator_Target_Kind.Buffer_Start)

	modal_operator_test_pending(t, &activation, &request, 'd')
	request.input = Input{kind = .Key, stroke = Key_Stroke{kind = .Down}}
	result, composed, failure = modal_operator_compose(&activation, request)
	testing.expectf(t, composed, "logical movement target failed with %v", failure.code)
	testing.expect_value(t, result.target, Modal_Operator_Target_Kind.Next_Line)
}

/* Verifies character targets, repeats, cancellation, and stale rejection are atomic. */
@(test)
modal_operators_capture_targets_and_reject_atomically :: proc(t: ^testing.T) {
	registry: Command_Registry
	activation: Profile_Activation
	navigation: Modal_Navigation_Request
	if !modal_navigation_fixture_init(t, &registry, &activation, &navigation) do return
	defer command_registry_close(&registry)
	defer profile_activation_close(&activation)
	request := modal_operator_test_request(navigation)

	modal_operator_test_pending(t, &activation, &request, 'd')
	modal_operator_test_pending(t, &activation, &request, 'f')
	request.input = modal_navigation_test_input('🙂', "🙂")
	result, composed, failure := modal_operator_compose(&activation, request)
	testing.expectf(t, composed, "Unicode character target failed with %v", failure.code)
	testing.expect_value(t, result.target, Modal_Operator_Target_Kind.Character_Target)
	testing.expect_value(t, result.character_target, Modal_Character_Target_Kind.Find_Next)
	testing.expect_value(t, modal_operator_result_text(&result), "🙂")

	confirmed, confirm_failure := profile_activation_modal_character_search_confirm(
		&activation,
		navigation,
		.Find_Next,
		"q",
	)
	testing.expectf(t, confirmed, "repeat fixture failed with %v", confirm_failure.code)
	modal_operator_test_pending(t, &activation, &request, 'y')
	request.input = modal_navigation_test_input(',', ",")
	result, composed, failure = modal_operator_compose(&activation, request)
	testing.expectf(t, composed, "opposite character repeat failed with %v", failure.code)
	testing.expect_value(t, result.target, Modal_Operator_Target_Kind.Repeat_Character_Target)
	testing.expect_value(t, result.character_target, Modal_Character_Target_Kind.Find_Previous)
	testing.expect_value(t, modal_operator_result_text(&result), "q")

	modal_operator_test_pending(t, &activation, &request, '<')
	request.input = Input{kind = .Key, stroke = Key_Stroke{kind = .Escape}}
	result, composed, failure = modal_operator_compose(&activation, request)
	testing.expectf(t, composed, "operator cancellation failed with %v", failure.code)
	testing.expect_value(t, result.disposition, Modal_Operator_Disposition.Cancelled)
	pending, _ := profile_activation_modal_pending_inspect(&activation)
	testing.expect_value(t, pending, Modal_Pending_State{})

	modal_operator_test_pending(t, &activation, &request, 'd')
	request.buffer_revision += 1
	request.input = modal_navigation_test_input('w', "w")
	_, composed, failure = modal_operator_compose(&activation, request)
	testing.expect(t, !composed)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Context)
	pending, _ = profile_activation_modal_pending_inspect(&activation)
	testing.expect_value(t, pending, Modal_Pending_State{})

	request.buffer_revision -= 1
	modal_operator_test_pending(t, &activation, &request, 'd')
	request.input = modal_navigation_test_input('c', "c")
	_, composed, failure = modal_operator_compose(&activation, request)
	testing.expect(t, !composed)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Input)
	pending, _ = profile_activation_modal_pending_inspect(&activation)
	testing.expect_value(t, pending, Modal_Pending_State{})
}

/* Verifies one bounded named slot applies only to the next compatible operation. */
@(test)
modal_named_slots_compose_with_transfer_operations :: proc(t: ^testing.T) {
	registry: Command_Registry
	activation: Profile_Activation
	navigation: Modal_Navigation_Request
	if !modal_navigation_fixture_init(t, &registry, &activation, &navigation) do return
	defer command_registry_close(&registry)
	defer profile_activation_close(&activation)
	request := modal_operator_test_request(navigation)

	modal_operator_test_pending(t, &activation, &request, '"')
	request.input = modal_navigation_test_input('a', "a")
	result, composed, failure := modal_operator_compose(&activation, request)
	testing.expectf(t, composed, "named slot capture failed with %v", failure.code)
	testing.expect_value(t, result.disposition, Modal_Operator_Disposition.Pending)
	pending, pending_ok := profile_activation_modal_pending_inspect(&activation)
	testing.expect(t, pending_ok)
	if pending_ok {
		testing.expect_value(t, pending.kind, Modal_Pending_Kind.Named_Slot)
		testing.expect_value(t, string(pending.named_slot[:pending.named_slot_length]), "a")
	}
	modal_operator_test_pending(t, &activation, &request, 'd')
	request.input = modal_navigation_test_input('w', "w")
	result, composed, failure = modal_operator_compose(&activation, request)
	testing.expectf(t, composed, "named delete failed with %v", failure.code)
	testing.expect_value(t, result.operator, Modal_Operator_Kind.Delete)
	testing.expect_value(t, result.target, Modal_Operator_Target_Kind.Next_Word_Start)
	testing.expect_value(t, modal_operator_result_named_slot(&result), "a")

	modal_operator_test_pending(t, &activation, &request, '2')
	modal_operator_test_pending(t, &activation, &request, '"')
	request.input = modal_navigation_test_input('b', "b")
	result, composed, failure = modal_operator_compose(&activation, request)
	testing.expectf(t, composed, "named source capture failed with %v", failure.code)
	request.input = modal_navigation_test_input('p', "p")
	result, composed, failure = modal_operator_compose(&activation, request)
	testing.expectf(t, composed, "named insertion failed with %v", failure.code)
	testing.expect_value(t, result.target, Modal_Operator_Target_Kind.Named_Slot_After)
	testing.expect_value(t, modal_operator_result_named_slot(&result), "b")
	testing.expect_value(t, result.count, u64(2))

	modal_operator_test_pending(t, &activation, &request, '"')
	request.input = modal_navigation_test_input('c', "c")
	_, composed, failure = modal_operator_compose(&activation, request)
	testing.expectf(t, composed, "named cancellation setup failed with %v", failure.code)
	request.input = Input{kind = .Key, stroke = Key_Stroke{kind = .Escape}}
	result, composed, failure = modal_operator_compose(&activation, request)
	testing.expectf(t, composed, "named cancellation failed with %v", failure.code)
	testing.expect_value(t, result.disposition, Modal_Operator_Disposition.Cancelled)
	pending, _ = profile_activation_modal_pending_inspect(&activation)
	testing.expect_value(t, pending, Modal_Pending_State{})
}

@(private)
modal_operator_test_request :: proc(request: Modal_Navigation_Request) -> Modal_Operator_Request {
	return Modal_Operator_Request {
		profile = request.profile,
		state = request.state,
		catalog_generation = request.catalog_generation,
		snapshot_generation = request.snapshot_generation,
		ctx = request.ctx,
		view_identity = request.view_identity,
		view_generation = request.view_generation,
		buffer_identity = request.buffer_identity,
		buffer_revision = request.buffer_revision,
	}
}

@(private)
modal_operator_test_pending :: proc(
	t: ^testing.T,
	activation: ^Profile_Activation,
	request: ^Modal_Operator_Request,
	value: rune,
) {
	request.input = modal_navigation_test_input(value, "")
	result, composed, failure := modal_operator_compose(activation, request^)
	testing.expectf(t, composed, "operator input %c failed with %v", value, failure.code)
	testing.expect_value(t, result.disposition, Modal_Operator_Disposition.Pending)
}
