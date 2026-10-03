// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package theme_equivalence

import theme "../../src/theme"
import ui "../../src/ui"
import reference "../theme_reference"
import "core:testing"

/* Cross-checks production theme lifecycle against the independent model. */
@(test)
lifecycle_matches_theme_model :: proc(t: ^testing.T) {
	registry: theme.Registry
	initialized, failure := theme.theme_registry_init_factory(&registry, 77)
	testing.expectf(t, initialized, "production init failed with %v", failure.code)
	if !initialized do return
	defer theme.theme_registry_close(&registry)
	model, model_initialized, model_failure := reference.model_init()
	testing.expectf(t, model_initialized, "reference init failed with %v", model_failure.code)
	if !model_initialized do return
	defer reference.model_close(&model)
	expect_equivalent(t, &registry, &model)

	styles := complete_styles()
	proposal := theme.Definition_Proposal {
		identity = "equivalence-theme",
		display_name = "Equivalence Theme",
		provider_name = "equivalence-provider",
		provenance = "tests/theme_equivalence/equivalence_test.odin",
		styles = styles[:],
	}
	model_proposal := reference.Proposal {
		provider_key = 2,
		identity_key = 20,
		identity_bytes = u16(len(proposal.identity)),
		display_name_bytes = u16(len(proposal.display_name)),
		provider_name_bytes = u16(len(proposal.provider_name)),
		provenance_bytes = u16(len(proposal.provenance)),
		style_count = reference.CURRENT_STYLE_ROLES,
		retained_bytes = u32(theme.definition_proposal_bytes(proposal)),
	}
	production_scope, _, _ := theme.theme_registry_selection(&registry)
	production_proposed, production_proposed_ok, _ := theme.theme_registry_propose(
		&registry, production_scope.registry_generation, proposal,
	)
	reference_proposed, reference_proposed_ok, _ := reference.model_propose(&model, model_proposal)
	testing.expect(t, production_proposed_ok && reference_proposed_ok)
	expect_equivalent(t, &registry, &model)

	production_scope, _, _ = theme.theme_registry_selection(&registry)
	production_confirmed, production_confirmed_ok, _ := theme.theme_registry_confirm(
		&registry, production_scope.registry_generation, production_proposed,
	)
	reference_confirmed, reference_confirmed_ok, _ := reference.model_confirm(
		&model, model.state.selection.registry_generation, reference_proposed,
	)
	testing.expect(t, production_confirmed_ok && reference_confirmed_ok)
	expect_equivalent(t, &registry, &model)

	production_scope, _, _ = theme.theme_registry_selection(&registry)
	production_selected, production_selected_ok, _ := theme.theme_registry_select(
		&registry, production_scope, production_confirmed,
	)
	reference_selected, reference_selected_ok, _ := reference.model_select(
		&model, model.state.selection.selection_generation, reference_confirmed,
	)
	testing.expect(t, production_selected_ok && reference_selected_ok)
	expect_equivalent(t, &registry, &model)

	proposal.display_name = "Equivalence Theme Revised"
	production_replaced, _, production_replaced_ok, _ := theme.theme_registry_replace(
		&registry, production_selected, production_confirmed, proposal,
	)
	reference_replaced, _, reference_replaced_ok, _ := reference.model_replace(
		&model,
		reference_selected.selection_generation,
		reference_confirmed,
		u32(theme.definition_proposal_bytes(proposal)),
	)
	testing.expect(t, production_replaced_ok && reference_replaced_ok)
	expect_equivalent(t, &registry, &model)

	production_restored, production_restored_ok, _ := theme.theme_registry_restore(
		&registry, production_replaced,
	)
	reference_restored, reference_restored_ok, _ := reference.model_restore_fallback(
		&model, reference_replaced.selection_generation,
	)
	testing.expect(t, production_restored_ok && reference_restored_ok)
	expect_equivalent(t, &registry, &model)

	_, production_disabled_ok, _ := theme.theme_registry_select_baseline(
		&registry, production_restored,
	)
	_, reference_disabled_ok, _ := reference.model_disable(
		&model, reference_restored.selection_generation,
	)
	testing.expect(t, production_disabled_ok && reference_disabled_ok)
	expect_equivalent(t, &registry, &model)
}

@(private)
expect_equivalent :: proc(t: ^testing.T, registry: ^theme.Registry, model: ^reference.Model) {
	selection, selected, failure := theme.theme_registry_selection(registry)
	inspection, inspected, _ := theme.theme_registry_inspect(registry)
	testing.expectf(t, selected && inspected, "production inspection failed with %v", failure.code)
	testing.expect(t, reference.model_valid(model))
	if !selected || !inspected || !reference.model_valid(model) do return
	testing.expect_value(
		t,
		u64(selection.registry_generation),
		model.state.selection.registry_generation,
	)
	testing.expect_value(
		t,
		u64(selection.selection_generation),
		model.state.selection.selection_generation,
	)
	testing.expect_value(t, u16(selection.active.definition_id), model.state.selection.active.id)
	testing.expect_value(
		t,
		u64(selection.active.definition_generation),
		model.state.selection.active.generation,
	)
	testing.expect_value(t, inspection.usage.providers, model.state.provider_count)
	testing.expect_value(t, inspection.usage.definitions, model.state.definition_count)
}

@(private)
complete_styles :: proc() -> [theme.CURRENT_STYLE_ROLE_COUNT]ui.Style_Definition {
	styles: [theme.CURRENT_STYLE_ROLE_COUNT]ui.Style_Definition
	for &style, index in styles do style.role = ui.Style_Role(index + 1)
	styles[int(ui.Style_Role.Text_Region) - 1].attributes = {.Reverse}
	styles[int(ui.Style_Role.Diagnostic_Rejected) - 1].attributes = {.Bold}
	styles[int(ui.Style_Role.Diagnostic_Error) - 1].attributes = {.Bold, .Underline}
	styles[int(ui.Style_Role.Diagnostic_Warning) - 1].attributes = {.Underline}
	styles[int(ui.Style_Role.Diagnostic_Information) - 1].attributes = {.Reverse}
	styles[int(ui.Style_Role.Diagnostic_Hint) - 1].attributes = {.Dim}
	return styles
}
