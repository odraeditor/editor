// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package completion

import "core:testing"

/* Verifies named composition changes publish atomically and preserve the last valid scope. */
@(test)
config_selects_named_composition :: proc(t: ^testing.T) {
	registry: Role_Registry
	initialized, _ := registry_init(&registry, 801)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)

	provider, provider_ok, _ := registry_register(
		&registry,
		test_definition("alternate-provider", .Provider),
	)
	policy, policy_ok, _ := registry_register(
		&registry,
		test_definition("alternate-policy", .Policy),
	)
	presentation, presentation_ok, _ := registry_register(
		&registry,
		test_definition("alternate-presentation", .Presentation),
	)
	scope, scoped, _ := registry_scope(&registry)
	configuration := factory_configuration()
	configuration.provider = provider.definition.name
	configuration.policy = policy.definition.name
	configuration.presentation = presentation.definition.name
	selected, configured, failure := registry_configure(&registry, scope, configuration)
	testing.expectf(t, provider_ok && policy_ok && presentation_ok && scoped && configured,
		"configuration failed with %v", failure.code)
	testing.expect_value(t, selected.selections[0].selected, provider.handle)
	testing.expect_value(t, selected.selections[1].selected, policy.handle)
	testing.expect_value(t, selected.selections[2].selected, presentation.handle)

	missing, _ := name_copy("missing-policy")
	invalid := configuration
	invalid.policy = missing
	_, rejected, rejected_failure := registry_configure(&registry, selected, invalid)
	after, inspected, _ := registry_scope(&registry)
	testing.expect(t, !rejected && inspected)
	testing.expect_value(t, rejected_failure.code, Failure_Code.Stale_Implementation)
	testing.expect_value(t, after, selected)
}

/* Verifies factory policy and limits are complete, configurable, and inspected by controllers. */
@(test)
config_controls_invocation_policy :: proc(t: ^testing.T) {
	configuration := factory_configuration()
	testing.expect(t, factory_configuration_is_valid(configuration))
	configuration.session.minimum_identifier_graphemes = 3
	configuration.session.filter.subsequence = false
	configuration.limits.candidates = 32
	testing.expect(t, factory_configuration_is_valid(configuration))

	registry: Role_Registry
	controller: Controller
	initialized, _ := registry_init(&registry, 811, configuration.limits)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	scope, _, _ := registry_scope(&registry)
	configured_scope, configured, _ := registry_configure(&registry, scope, configuration)
	controller_ok, _ := controller_init(
		&controller,
		812,
		1,
		configured_scope,
		configuration.limits,
		context.allocator,
		configuration.session,
	)
	testing.expect(t, configured && controller_ok)
	if controller_ok {
		defer controller_close(&controller)
		request := controller_request(813, 1, 3, configured_scope)
		started, start_failure := controller_start(&controller, 814, 1, request, configured_scope)
		inspection, inspected, _ := controller_inspect(&controller)
		testing.expect(t, started && inspected)
		testing.expect_value(t, start_failure.code, Failure_Code.None)
		testing.expect_value(t, inspection.policy, configuration.session)
	}

	disabled := configuration
	disabled.enabled = false
	disabled_scope, disabled_ok, _ := registry_configure(&registry, configured_scope, disabled)
	testing.expect(t, disabled_ok)
	testing.expect(t, !disabled_scope.enabled)

	invalid := configuration
	invalid.session.minimum_identifier_graphemes = 0
	testing.expect(t, !factory_configuration_is_valid(invalid))
}
