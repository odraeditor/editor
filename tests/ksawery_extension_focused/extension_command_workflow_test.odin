// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_extension_focused

import command "../../src/command"
import "../../src/ksawery_command"
import ksawery "../../src/ksawery"
import odra "../../src/ksawery_module"
import "core:encoding/endian"
import "core:testing"

/* Verifies checked mutation routing, one-shot confirmation, refresh, and result inspection. */
@(test)
extension_command_workflows_route_only_checked_core_actions :: proc(t: ^testing.T) {
	registry: odra.Ksawery_Extension_Provider_Registry
	if !testing.expect(t, odra.ksawery_extension_provider_registry_init(&registry)) do return
	defer odra.ksawery_extension_provider_registry_close(&registry)
	batch := extension_provider_batch(2, 5)
	defer delete(batch)
	authorities := u64(1 << u64(ksawery.Extension_Authority.Inspect) |
	                   1 << u64(ksawery.Extension_Authority.Request_Core_Action))
	assert(endian.put_u64(batch[22 * 8:], .Little, authorities))
	assert(endian.put_u64(batch[32 * 8:], .Little, authorities))
	candidate, prepared, _ := odra.ksawery_extension_provider_prepare(&registry, batch[:], 2)
	if !testing.expect(t, prepared) do return
	testing.expect(t, odra.ksawery_extension_provider_candidate_confirm(&candidate))
	activated, _ := odra.ksawery_extension_provider_activate(&registry, &candidate)
	if !testing.expect(t, activated) do return
	scope := extension_provider_scope(5)
	scope.surface = .Refs
	scope.target = {kind = .Ref, generation = 19, identity = 31}
	capability, began, _ := odra.ksawery_extension_provider_turn_begin(
		&registry, scope, {.Request_Core_Action},
	)
	if !testing.expect(t, began) do return
	defer if registry.active.turn_active do odra.ksawery_extension_provider_turn_end(&registry)
	current_scope := scope
	current_scope.capability_generation = capability.generation
	command_context := extension_command_workflow_test_context(current_scope)
	choices: [2]ksawery.Extension_Command_Choice
	arguments: [3]ksawery.Extension_Command_Argument_Definition
	actions: [2]ksawery.Extension_Command_Action_Definition
	family := extension_command_test_family(&choices, &arguments, &actions)
	values := [1]ksawery.Extension_Command_Argument_Value {{
		argument = 2,
		kind = .Closed_Choice,
		choice = 1,
	}}
	request := ksawery.Extension_Command_Request {
		id = 71,
		family = family.family,
		family_generation = family.generation,
		action = 2,
		command_context = command_context,
		arguments = values[:],
		confirmation = 73,
	}
	route := ksawery_command.Ksawery_Extension_Command_Route {
		route = command.racket_route(.Ksawery_Extension, 1),
		contributor = family.contributor,
		family = family.family,
		family_generation = family.generation,
		action = request.action,
	}
	workflow: odra.Ksawery_Extension_Command_Workflow
	stale_route := route
	stale_route.family_generation += 1
	_, stale_routed, stale_failure := odra.ksawery_extension_command_workflow_begin(
		&workflow, &registry, stale_route, family, request, command_context,
		capability, current_scope, scope.owner_thread, 1, 1, false,
	)
	testing.expect(t, !stale_routed)
	testing.expect_value(t, stale_failure.code, odra.Ksawery_Extension_Command_Workflow_Failure_Code.Stale_Route)
	_, busy_routed, busy_failure := odra.ksawery_extension_command_workflow_begin(
		&workflow, &registry, route, family, request, command_context,
		capability, current_scope, scope.owner_thread, 1, 1, true,
	)
	testing.expect(t, !busy_routed)
	testing.expect_value(t, busy_failure.code, odra.Ksawery_Extension_Command_Workflow_Failure_Code.Operation_Active)
	core_request, routed, route_failure := odra.ksawery_extension_command_workflow_begin(
		&workflow, &registry, route, family, request, command_context,
		capability, current_scope, scope.owner_thread, 1, 1, false,
	)
	testing.expectf(t, routed, "route failed: %v/%v/%v", route_failure.code,
		route_failure.contract.code, route_failure.extension.code)
	if !routed do return
	testing.expect_value(t, core_request.operation, ksawery.Repository_Operation_Kind.Push)
	testing.expect_value(t, len(core_request.arguments), 1)
	result := ksawery.Extension_Command_Result {
		request = request.id,
		family = request.family,
		family_generation = request.family_generation,
		action = request.action,
		status = .Completed,
		core_action_requested = true,
	}
	refreshed := command_context
	refreshed.repository_generation += 1
	refreshed.worktree_generation += 1
	completed, completion_failure := odra.ksawery_extension_command_workflow_complete(
		&workflow, result, refreshed, true,
	)
	testing.expectf(t, completed, "completion failed: %v", completion_failure.code)
	inspection, inspected := odra.ksawery_extension_command_workflow_inspect(&workflow)
	testing.expect(t, inspected)
	if inspected do testing.expect_value(t, inspection.request, request.id)

	testing.expect(t, odra.ksawery_extension_provider_turn_end(&registry))
	capability, began, _ = odra.ksawery_extension_provider_turn_begin(
		&registry, scope, {.Request_Core_Action},
	)
	if !testing.expect(t, began) do return
	current_scope = scope
	current_scope.capability_generation = capability.generation
	command_context.capability_generation = capability.generation
	request.id += 1
	request.command_context = command_context
	request.confirmation += 1
	_, second_routed, second_failure := odra.ksawery_extension_command_workflow_begin(
		&workflow, &registry, route, family, request, command_context,
		capability, current_scope, scope.owner_thread, 1, 1, false,
	)
	testing.expectf(t, second_routed, "second route failed: %v", second_failure.code)
	if !second_routed do return
	result.request = request.id
	refresh_failed, refresh_failure := odra.ksawery_extension_command_workflow_complete(
		&workflow, result, command_context, false,
	)
	testing.expect(t, !refresh_failed)
	testing.expect_value(t, refresh_failure.code, odra.Ksawery_Extension_Command_Workflow_Failure_Code.Refresh_Required)
	testing.expect(t, workflow.active)
	testing.expect(t, odra.ksawery_extension_command_workflow_abort(&workflow))
	testing.expect(t, !workflow.active)
	request.id += 1
	_, reused_routed, reused_failure := odra.ksawery_extension_command_workflow_begin(
		&workflow, &registry, route, family, request, command_context,
		capability, current_scope, scope.owner_thread, 1, 1, false,
	)
	testing.expect(t, !reused_routed)
	testing.expect_value(t, reused_failure.code, odra.Ksawery_Extension_Command_Workflow_Failure_Code.Confirmation_Reused)
}

/* Verifies external command authority remains distinct and requires refreshed completion. */
@(test)
extension_command_workflows_admit_only_checked_external_operations :: proc(t: ^testing.T) {
	registry: odra.Ksawery_Extension_Provider_Registry
	if !testing.expect(t, odra.ksawery_extension_provider_registry_init(&registry)) do return
	defer odra.ksawery_extension_provider_registry_close(&registry)
	batch := extension_provider_batch(2, 5)
	defer delete(batch)
	authorities := u64(1 << u64(ksawery.Extension_Authority.Inspect) |
	                   1 << u64(ksawery.Extension_Authority.Submit_External_Operation))
	assert(endian.put_u64(batch[22 * 8:], .Little, authorities))
	assert(endian.put_u64(batch[32 * 8:], .Little, authorities))
	candidate, prepared, _ := odra.ksawery_extension_provider_prepare(&registry, batch[:], 2)
	if !testing.expect(t, prepared) do return
	testing.expect(t, odra.ksawery_extension_provider_candidate_confirm(&candidate))
	activated, _ := odra.ksawery_extension_provider_activate(&registry, &candidate)
	if !testing.expect(t, activated) do return
	scope := extension_provider_scope(5)
	scope.surface = .Refs
	scope.target = {kind = .Ref, generation = 19, identity = 31}
	capability, began, _ := odra.ksawery_extension_provider_turn_begin(
		&registry, scope, {.Submit_External_Operation},
	)
	if !testing.expect(t, began) do return
	defer if registry.active.turn_active do odra.ksawery_extension_provider_turn_end(&registry)
	current_scope := registry.active.active_scope
	command_context := extension_command_workflow_test_context(current_scope)
	choices: [2]ksawery.Extension_Command_Choice
	arguments: [3]ksawery.Extension_Command_Argument_Definition
	actions: [2]ksawery.Extension_Command_Action_Definition
	family := extension_command_test_family(&choices, &arguments, &actions)
	actions[1].authority = .Submit_External_Operation
	actions[1].core_operation = .Invalid
	family.actions = actions[:]
	values := [1]ksawery.Extension_Command_Argument_Value {{
		argument = 2,
		kind = .Closed_Choice,
		choice = 1,
	}}
	request := ksawery.Extension_Command_Request {
		id = 81,
		family = family.family,
		family_generation = family.generation,
		action = 2,
		command_context = command_context,
		arguments = values[:],
		confirmation = 83,
	}
	route := ksawery_command.Ksawery_Extension_Command_Route {
		route = command.racket_route(.Ksawery_Extension, 1),
		contributor = family.contributor,
		family = family.family,
		family_generation = family.generation,
		action = request.action,
	}
	workflow: odra.Ksawery_Extension_Command_Workflow
	_, core_routed, core_failure := odra.ksawery_extension_command_workflow_begin(
		&workflow, &registry, route, family, request, command_context,
		capability, current_scope, scope.owner_thread, 1, 1, false,
	)
	testing.expect(t, !core_routed)
	testing.expect_value(
		t, core_failure.code,
		odra.Ksawery_Extension_Command_Workflow_Failure_Code.Core_Action_Rejected,
	)
	routed, route_failure := odra.ksawery_extension_command_workflow_begin_external(
		&workflow, &registry, route, family, request, command_context,
		capability, current_scope, scope.owner_thread, 1, 1, false,
	)
	testing.expectf(t, routed, "external route failed: %v", route_failure.code)
	if !routed do return
	testing.expect(t, workflow.external_operation)
	testing.expect_value(t, workflow.operation, ksawery.Repository_Operation_Kind.External_Operation)
	invalid_result := ksawery.Extension_Command_Result {
		request = request.id,
		family = request.family,
		family_generation = request.family_generation,
		action = request.action,
		status = .Completed,
		core_action_requested = true,
	}
	refreshed := command_context
	refreshed.repository_generation += 1
	refreshed.worktree_generation += 1
	completed, completion_failure := odra.ksawery_extension_command_workflow_complete(
		&workflow, invalid_result, refreshed, true,
	)
	testing.expect(t, !completed)
	testing.expect_value(
		t, completion_failure.code,
		odra.Ksawery_Extension_Command_Workflow_Failure_Code.Invalid_Result,
	)
	valid_result := invalid_result
	valid_result.core_action_requested = false
	valid_result.external_operation_requested = true
	completed, completion_failure = odra.ksawery_extension_command_workflow_complete(
		&workflow, valid_result, refreshed, true,
	)
	testing.expectf(t, completed, "external completion failed: %v", completion_failure.code)
	inspection, inspected := odra.ksawery_extension_command_workflow_inspect(&workflow)
	testing.expect(t, inspected)
	if inspected do testing.expect(t, inspection.external_operation_requested)
}

extension_command_workflow_test_context :: proc(
	scope: ksawery.Extension_Turn_Scope,
) -> ksawery.Extension_Command_Context {
	target: ksawery.Extension_Annotation_Target
	assert(ksawery.extension_annotation_target_assign(
		&target, .Ref, u64(scope.observation_generation),
		transmute([]u8)(string("refs/heads/main")),
	))
	return {
		contributor = scope.contributor,
		repository = scope.repository,
		repository_generation = scope.repository_generation,
		worktree_generation = scope.worktree_generation,
		observation = .Refs,
		observation_generation = u64(scope.observation_generation),
		surface = scope.surface,
		surface_generation = scope.surface_generation,
		selection_generation = u64(scope.selection_generation),
		target_present = true,
		target = target,
		operation_state = .Idle,
		mutation_available = true,
		capability_generation = scope.capability_generation,
		observation_truncated = scope.truncated,
		privacy_filtered = scope.private_content_omitted,
	}
}
