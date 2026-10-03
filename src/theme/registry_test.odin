// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package theme

import "../ui"
import "core:mem"
import "core:testing"

/* Verifies five factory definitions bootstrap one fallback selection. */
@(test)
bootstrap_selects_exact_factory_fallback :: proc(t: ^testing.T) {
	registry, styles, proposals := test_registry()
	defer theme_registry_close(&registry)
	selection, selected, failure := theme_registry_selection(&registry)
	inspection, inspected, _ := theme_registry_inspect(&registry)

	testing.expectf(t, selected && inspected, "factory inspection failed with %v", failure.code)
	testing.expect_value(t, selection.active, selection.fallback)
	testing.expect(t, selection.baseline != selection.fallback)
	testing.expect_value(t, inspection.usage.providers, u16(1))
	testing.expect_value(t, inspection.usage.definitions, u16(FACTORY_DEFINITION_COUNT))
	_ = styles
	_ = proposals
}

/* Verifies proposal, confirmation, selection, and stale rejection are atomic. */
@(test)
admits_one_generation_checked_definition :: proc(t: ^testing.T) {
	registry, factory_styles, factory_proposals := test_registry()
	defer theme_registry_close(&registry)
	styles := complete_registry_test_styles()
	proposal := registry_test_proposal("custom-theme", "Custom Theme", "racket-test", styles[:])
	before, _, _ := theme_registry_selection(&registry)
	proposed, proposed_ok, _ := theme_registry_propose(&registry, before.registry_generation, proposal)
	after_proposal, _, _ := theme_registry_selection(&registry)
	confirmed, confirmed_ok, _ := theme_registry_confirm(
		&registry, after_proposal.registry_generation, proposed,
	)
	after_confirm, _, _ := theme_registry_selection(&registry)
	selected, selected_ok, _ := theme_registry_select(&registry, after_confirm, confirmed)
	_, stale_ok, stale := theme_registry_select(&registry, after_confirm, selected.fallback)

	testing.expect(t, proposed_ok && confirmed_ok && selected_ok && !stale_ok)
	testing.expect_value(t, selected.active, confirmed)
	testing.expect_value(t, stale.code, Failure_Code.Stale_Selection)
	_ = factory_styles
	_ = factory_proposals
}

/* Verifies replacement, rollback, and safe-baseline transitions stay complete. */
@(test)
replaces_rolls_back_and_selects_baseline :: proc(t: ^testing.T) {
	registry, factory_styles, factory_proposals := test_registry()
	defer theme_registry_close(&registry)
	styles := complete_registry_test_styles()
	proposal := registry_test_proposal("custom-theme", "Custom Theme", "racket-test", styles[:])
	initial, _, _ := theme_registry_selection(&registry)
	proposed, _, _ := theme_registry_propose(&registry, initial.registry_generation, proposal)
	proposed_scope, _, _ := theme_registry_selection(&registry)
	confirmed, _, _ := theme_registry_confirm(&registry, proposed_scope.registry_generation, proposed)
	confirmed_scope, _, _ := theme_registry_selection(&registry)
	selected, _, _ := theme_registry_select(&registry, confirmed_scope, confirmed)
	proposal.display_name = "Custom Theme Revised"
	replaced, replacement, replacement_ok, _ := theme_registry_replace(
		&registry, selected, confirmed, proposal,
	)
	rolled_back, rollback_ok, _ := theme_registry_restore(&registry, replaced)
	baseline, baseline_ok, _ := theme_registry_select_baseline(&registry, rolled_back)

	testing.expect(t, replacement_ok && rollback_ok && baseline_ok)
	testing.expect_value(t, replacement.definition_generation, confirmed.definition_generation + 1)
	testing.expect_value(t, rolled_back.active, rolled_back.fallback)
	testing.expect_value(t, baseline.active, baseline.baseline)
	_ = factory_styles
	_ = factory_proposals
}

/* Verifies active provider failure and teardown restore the maintained fallback. */
@(test)
provider_failure_and_close_restore_fallback :: proc(t: ^testing.T) {
	registry, factory_styles, factory_proposals := test_registry()
	defer theme_registry_close(&registry)
	styles := complete_registry_test_styles()
	proposal := registry_test_proposal("custom-theme", "Custom Theme", "racket-test", styles[:])
	initial, _, _ := theme_registry_selection(&registry)
	proposed, _, _ := theme_registry_propose(&registry, initial.registry_generation, proposal)
	proposal_scope, _, _ := theme_registry_selection(&registry)
	confirmed, _, _ := theme_registry_confirm(&registry, proposal_scope.registry_generation, proposed)
	confirmed_scope, _, _ := theme_registry_selection(&registry)
	selected, _, _ := theme_registry_select(&registry, confirmed_scope, confirmed)
	provider := Provider_Handle {
		registry_id = confirmed.registry_id,
		provider_id = confirmed.provider_id,
		provider_generation = confirmed.provider_generation,
	}
	failed_selection, failed, _ := theme_registry_fail_provider(&registry, selected, provider)
	inspection, inspected, _ := theme_registry_inspect(&registry)

	testing.expect(t, failed && inspected)
	testing.expect_value(t, failed_selection.active, failed_selection.fallback)
	testing.expect_value(t, failed_selection.state, Selection_State.Fallback_After_Failure)
	testing.expect_value(t, inspection.usage.definitions, u16(FACTORY_DEFINITION_COUNT))
	closed_selection, closed, _ := theme_registry_close_provider(&registry, failed_selection, provider)
	closed_inspection, closed_inspected, _ := theme_registry_inspect(&registry)
	testing.expect(t, closed && closed_inspected)
	testing.expect_value(t, closed_selection.active, closed_selection.fallback)
	testing.expect_value(t, closed_inspection.usage.providers, u16(1))
	_ = factory_styles
	_ = factory_proposals
}

/* Verifies exact accounting and allocator-owned teardown leave no retained bytes. */
@(test)
registry_accounting_and_cleanup_are_exact :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	registry: Registry
	styles: [FACTORY_DEFINITION_COUNT][CURRENT_STYLE_ROLE_COUNT]ui.Style_Definition
	proposals: [FACTORY_DEFINITION_COUNT]Definition_Proposal
	test_factory_proposals(&styles, &proposals)
	initialized, failure := theme_registry_init(
		&registry,
		91,
		proposals[:],
		"factory-night",
		"terminal-default",
		DEFAULT_RESOURCE_LIMITS,
		allocator,
	)
	testing.expectf(t, initialized, "tracked registry init failed with %v", failure.code)
	inspection, inspected, _ := theme_registry_inspect(&registry)
	expected_bytes: u64
	for proposal in proposals do expected_bytes += definition_proposal_bytes(proposal)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.usage.retained_definition_bytes, expected_bytes)
	closed, _ := theme_registry_close(&registry)
	testing.expect(t, closed)
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	mem.tracking_allocator_destroy(&tracking)

	failed_registry: Registry
	_, allocation_failure := theme_registry_init(
		&failed_registry,
		92,
		proposals[:],
		"factory-night",
		"terminal-default",
		DEFAULT_RESOURCE_LIMITS,
		{},
	)
	testing.expect_value(t, allocation_failure.code, Failure_Code.Invalid_Registry)
}

@(private)
test_registry :: proc() -> (
	Registry,
	[FACTORY_DEFINITION_COUNT][CURRENT_STYLE_ROLE_COUNT]ui.Style_Definition,
	[FACTORY_DEFINITION_COUNT]Definition_Proposal,
) {
	registry: Registry
	styles: [FACTORY_DEFINITION_COUNT][CURRENT_STYLE_ROLE_COUNT]ui.Style_Definition
	proposals: [FACTORY_DEFINITION_COUNT]Definition_Proposal
	test_factory_proposals(&styles, &proposals)
	ok, failure := theme_registry_init(
		&registry, 77, proposals[:], "factory-night", "terminal-default",
	)
	assert(ok, failure_code_diagnostic(failure.code))
	return registry, styles, proposals
}

@(private)
test_factory_proposals :: proc(
	styles: ^[FACTORY_DEFINITION_COUNT][CURRENT_STYLE_ROLE_COUNT]ui.Style_Definition,
	proposals: ^[FACTORY_DEFINITION_COUNT]Definition_Proposal,
) {
	identities := [?]string {
		"factory-sunrise",
		"factory-morning",
		"factory-sunset",
		"factory-night",
		"terminal-default",
	}
	display_names := [?]string {
		"Factory Sunrise",
		"Factory Morning",
		"Factory Sunset",
		"Factory Night",
		"Terminal Default",
	}
	for index in 0 ..< FACTORY_DEFINITION_COUNT {
		styles[index] = complete_registry_test_styles()
		proposals[index] = Definition_Proposal {
			identity = identities[index],
			display_name = display_names[index],
			provider_name = "factory-test",
			provenance = "src/theme/registry_test.odin",
			styles = styles[index][:],
		}
	}
}

@(private)
registry_test_proposal :: proc(
	identity, display_name, provider_name: string,
	styles: []ui.Style_Definition,
) -> Definition_Proposal {
	return Definition_Proposal {
		identity = identity,
		display_name = display_name,
		provider_name = provider_name,
		provenance = "src/theme/registry_test.odin",
		styles = styles,
	}
}

@(private)
complete_registry_test_styles :: proc() -> [CURRENT_STYLE_ROLE_COUNT]ui.Style_Definition {
	styles: [CURRENT_STYLE_ROLE_COUNT]ui.Style_Definition
	for &style, index in styles do style.role = ui.Style_Role(index + 1)
	styles[int(ui.Style_Role.Text_Region) - 1].attributes = {.Reverse}
	styles[int(ui.Style_Role.Diagnostic_Rejected) - 1].attributes = {.Bold}
	styles[int(ui.Style_Role.Diagnostic_Error) - 1].attributes = {.Bold, .Underline}
	styles[int(ui.Style_Role.Diagnostic_Warning) - 1].attributes = {.Underline}
	styles[int(ui.Style_Role.Diagnostic_Information) - 1].attributes = {.Reverse}
	styles[int(ui.Style_Role.Diagnostic_Hint) - 1].attributes = {.Dim}
	return styles
}
