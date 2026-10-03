// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../interaction"
import "core:testing"

/* Verifies every semantic language operation is registered with its exact command contract. */
@(test)
language_operations_have_explicit_contracts :: proc(t: ^testing.T) {
	cases := [?]struct {
		name:         string,
		effects:      interaction.Command_Effects,
		requirements: interaction.Command_Requirements,
	} {
		{"language-show-hover", {.View, .Lifecycle}, {.Active_Buffer, .Active_Document}},
		{"language-go-to-definition", {.View, .Lifecycle}, {.Active_Buffer, .Active_Document}},
		{"language-find-references", {.View, .Lifecycle}, {.Active_Buffer, .Active_Document}},
		{"language-document-symbols", {.View, .Lifecycle}, {.Active_Buffer, .Active_Document}},
		{"language-workspace-symbols", {.View, .Lifecycle}, {.Active_Buffer, .Active_Document}},
		{"language-signature-help", {.View, .Lifecycle}, {.Active_Buffer, .Active_Document}},
		{"language-rename", {.Buffer, .View, .Lifecycle, .Text_Mutation}, {.Active_Buffer, .Active_Document}},
		{"language-format-buffer", {.Buffer, .View, .Lifecycle, .Text_Mutation}, {.Active_Buffer, .Active_Document}},
		{"language-format-region", {.Buffer, .View, .Lifecycle, .Text_Mutation}, {.Active_Buffer, .Active_Document, .Active_Region}},
		{"language-code-actions", {.Buffer, .View, .Lifecycle, .Text_Mutation}, {.Active_Buffer, .Active_Document}},
	}
	definitions := native_command_definitions()
	for test_case in cases {
		definition, found := language_test_definition(definitions[:], test_case.name)
		testing.expectf(t, found, "missing language command %s", test_case.name)
		if !found do continue
		testing.expect_value(t, definition.effects, test_case.effects)
		testing.expect_value(t, definition.requirements, test_case.requirements)
		testing.expect_value(t, definition.provenance.provider, "odra-language")
		testing.expect_value(t, definition.provenance.source, "src/command/language_interaction_commands.odin")
		testing.expect_value(t, definition.implementation, interaction.Implementation_Class.Native)
		testing.expect(t, definition.interactive)
	}
}

/* Verifies bundle recovery commands are factory-owned and state-independent. */
@(test)
language_bundle_recovery_commands_are_factory_owned :: proc(t: ^testing.T) {
	names := [?]string {
		"describe-language-bundle",
		"language-support-doctor",
		"language-bundle-list",
		"language-bundle-search",
		"language-bundle-install",
		"language-bundle-enable",
		"language-bundle-disable",
		"language-bundle-update",
		"language-bundle-rollback",
		"language-bundle-remove",
		"language-bundle-refresh-catalogs",
	}
	definitions := native_command_definitions()
	for name in names {
		definition, found := language_test_definition(definitions[:], name)
		testing.expectf(t, found, "missing factory recovery command %s", name)
		if !found do continue
		testing.expect_value(t, definition.effects, interaction.Command_Effects{.Lifecycle})
		testing.expect_value(t, definition.requirements, interaction.Command_Requirements{})
		testing.expect_value(t, definition.provenance.provider, "odra-language-factory")
		testing.expect_value(t, definition.provenance.source, "src/command/language_interaction_commands.odin")
		testing.expect_value(t, definition.implementation, interaction.Implementation_Class.Native)
		testing.expect(t, definition.interactive)
	}
}

/* Verifies service inspection commands use language provenance and document availability. */
@(test)
language_service_commands_use_language_provenance :: proc(t: ^testing.T) {
	names := [?]string {
		"describe-language-support",
		"describe-language-service",
		"restart-language-service",
	}
	definitions := native_command_definitions()
	for name in names {
		definition, found := language_test_definition(definitions[:], name)
		testing.expectf(t, found, "missing language service command %s", name)
		if !found do continue
		testing.expect_value(t, definition.requirements, interaction.Command_Requirements{.Active_Buffer, .Active_Document})
		testing.expect_value(t, definition.provenance.provider, "odra-language")
		testing.expect_value(t, definition.provenance.source, "src/command/language_interaction_commands.odin")
	}
}

@(private)
language_test_definition :: proc(
	definitions: []interaction.Command_Definition,
	name: string,
) -> (interaction.Command_Definition, bool) {
	for definition in definitions {
		if definition.name == name do return definition, true
	}
	return {}, false
}
