// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package theme

import "../ui"
import "core:testing"

/* Verifies the accepted Theme MVP resource policy remains internally valid. */
@(test)
default_resource_policy_is_valid :: proc(t: ^testing.T) {
	testing.expect(t, resource_limits_are_valid(DEFAULT_RESOURCE_LIMITS))
	testing.expect_value(t, DEFAULT_RESOURCE_LIMITS.providers, u16(64))
	testing.expect_value(t, DEFAULT_RESOURCE_LIMITS.definitions, u16(64))
	testing.expect_value(t, DEFAULT_RESOURCE_LIMITS.retained_definition_bytes, u64(1 * MEBIBYTE))
	testing.expect_value(t, DEFAULT_RESOURCE_LIMITS.proposal_bytes, u64(64 * KIBIBYTE))
	testing.expect_value(t, DEFAULT_RESOURCE_LIMITS.preparation_bytes, u64(8 * MEBIBYTE))
}

/* Verifies machine identities and human-readable copied text have distinct rules. */
@(test)
theme_identity_contract_is_canonical :: proc(t: ^testing.T) {
	testing.expect(t, theme_identity_is_valid("wroclaw-night"))
	testing.expect(t, theme_identity_is_valid("terminal-default"))
	testing.expect(t, !theme_identity_is_valid("Wroclaw-Night"))
	testing.expect(t, !theme_identity_is_valid("-wroclaw-night"))
	testing.expect(t, !theme_identity_is_valid("wrocław-night"))
}

/* Verifies one complete role mapping is admitted and incomplete maps reject. */
@(test)
theme_requires_every_role_once :: proc(t: ^testing.T) {
	styles := complete_test_styles()
	proposal := test_definition_proposal(styles[:])
	valid, failure := definition_proposal_validate(proposal)
	testing.expectf(t, valid, "complete proposal failed with %v", failure.code)

	proposal.styles = styles[:len(styles) - 1]
	incomplete, incomplete_failure := definition_proposal_validate(proposal)
	testing.expect(t, !incomplete)
	testing.expect_value(t, incomplete_failure.code, Failure_Code.Incomplete_Style_Roles)
}

/* Verifies duplicate roles and lost monochrome distinctions reject completely. */
@(test)
definition_contract_rejects_duplicate :: proc(t: ^testing.T) {
	styles := complete_test_styles()
	proposal := test_definition_proposal(styles[:])
	styles[1].role = styles[0].role
	_, duplicate := definition_proposal_validate(proposal)
	testing.expect_value(t, duplicate.code, Failure_Code.Duplicate_Style_Role)

	styles = complete_test_styles()
	proposal.styles = styles[:]
	styles[int(ui.Style_Role.Text_Region) - 1].attributes = {}
	_, indistinguishable := definition_proposal_validate(proposal)
	testing.expect_value(t, indistinguishable.code, Failure_Code.Monochrome_Indistinguishable)
}

/* Verifies every stable failure code has a nonempty deterministic diagnostic. */
@(test)
failure_codes_have_stable_diagnostics :: proc(t: ^testing.T) {
	for code in Failure_Code {
		testing.expectf(t, len(failure_code_diagnostic(code)) > 0, "missing diagnostic for %v", code)
	}
}

@(private)
test_definition_proposal :: proc(styles: []ui.Style_Definition) -> Definition_Proposal {
	return Definition_Proposal {
		identity = "contract-test",
		display_name = "Contract Test",
		provider_name = "test-provider",
		provenance = "src/theme/contracts_test.odin",
		styles = styles,
	}
}

@(private)
complete_test_styles :: proc() -> [CURRENT_STYLE_ROLE_COUNT]ui.Style_Definition {
	styles: [CURRENT_STYLE_ROLE_COUNT]ui.Style_Definition
	for &style, index in styles {
		style.role = ui.Style_Role(index + 1)
	}
	styles[int(ui.Style_Role.Text_Region) - 1].attributes = {.Reverse}
	styles[int(ui.Style_Role.Diagnostic_Rejected) - 1].attributes = {.Bold}
	styles[int(ui.Style_Role.Diagnostic_Error) - 1].attributes = {.Bold, .Underline}
	styles[int(ui.Style_Role.Diagnostic_Warning) - 1].attributes = {.Underline}
	styles[int(ui.Style_Role.Diagnostic_Information) - 1].attributes = {.Reverse}
	styles[int(ui.Style_Role.Diagnostic_Hint) - 1].attributes = {.Dim}
	return styles
}
