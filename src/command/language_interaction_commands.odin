// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../interaction"

/* LANGUAGE_SUPPORT_COMMAND_COUNT excludes the three pre-existing service commands. */
LANGUAGE_SUPPORT_COMMAND_COUNT :: 21

/* language_support_command_definitions returns the extensible language command surface. */
language_support_command_definitions :: proc() -> [LANGUAGE_SUPPORT_COMMAND_COUNT]interaction.Command_Definition {
	return {
		language_document_command_definition(.Language_Show_Hover, "language-show-hover", {.View, .Lifecycle}, "Show copied language hover content at point."),
		language_document_command_definition(.Language_Go_To_Definition, "language-go-to-definition", {.View, .Lifecycle}, "Visit a selected definition and retain the prior location."),
		language_document_command_definition(.Language_Find_References, "language-find-references", {.View, .Lifecycle}, "Present references through the shared result surface."),
		language_document_command_definition(.Language_Document_Symbols, "language-document-symbols", {.View, .Lifecycle}, "Present document symbols through the shared candidate surface."),
		language_document_command_definition(.Language_Workspace_Symbols, "language-workspace-symbols", {.View, .Lifecycle}, "Query workspace symbols through the shared candidate surface."),
		language_document_command_definition(.Language_Signature_Help, "language-signature-help", {.View, .Lifecycle}, "Show copied callable signatures at point."),
		language_document_command_definition(.Language_Rename, "language-rename", {.Buffer, .View, .Lifecycle, .Text_Mutation}, "Preview and atomically apply one checked workspace rename."),
		language_document_command_definition(.Language_Format_Buffer, "language-format-buffer", {.Buffer, .View, .Lifecycle, .Text_Mutation}, "Format the active document as one checked transaction."),
		language_document_command_definition(.Language_Format_Region, "language-format-region", {.Buffer, .View, .Lifecycle, .Text_Mutation}, "Format the active region as one checked transaction.", {.Active_Buffer, .Active_Document, .Active_Region}),
		language_document_command_definition(.Language_Code_Actions, "language-code-actions", {.Buffer, .View, .Lifecycle, .Text_Mutation}, "Select and apply one checked language code action."),
		language_factory_command_definition(.Describe_Language_Bundle, "describe-language-bundle", "Inspect one installed or factory language bundle and its lifecycle."),
		language_factory_command_definition(.Language_Support_Doctor, "language-support-doctor", "Diagnose language selectors, providers, artifacts, executables, trust, and recovery."),
		language_factory_command_definition(.Language_Bundle_List, "language-bundle-list", "List factory and installed language bundles with exact states."),
		language_factory_command_definition(.Language_Bundle_Search, "language-bundle-search", "Search confirmed language bundle catalog snapshots."),
		language_factory_command_definition(.Language_Bundle_Install, "language-bundle-install", "Resolve, review, verify, and install one exact language bundle candidate."),
		language_factory_command_definition(.Language_Bundle_Enable, "language-bundle-enable", "Review authority and prepare atomic language bundle activation."),
		language_factory_command_definition(.Language_Bundle_Disable, "language-bundle-disable", "Deactivate language bundle contributions while preserving installed artifacts."),
		language_factory_command_definition(.Language_Bundle_Update, "language-bundle-update", "Prepare and activate one compatible language bundle update."),
		language_factory_command_definition(.Language_Bundle_Rollback, "language-bundle-rollback", "Restore the retained prior confirmed language bundle version."),
		language_factory_command_definition(.Language_Bundle_Remove, "language-bundle-remove", "Deactivate and remove an unrequired installed language bundle."),
		language_factory_command_definition(.Language_Bundle_Refresh_Catalogs, "language-bundle-refresh-catalogs", "Refresh configured language bundle catalogs without changing installed state."),
	}
}

@(private)
language_document_command_definition :: proc(
	route: Native_Route,
	name: string,
	effects: interaction.Command_Effects,
	description: string,
	requirements: interaction.Command_Requirements = {.Active_Buffer, .Active_Document},
) -> interaction.Command_Definition {
	definition := native_definition(route, name, effects, description, requirements)
	definition.provenance = interaction.Definition_Provenance {
		provider = "odra-language",
		source = "src/command/language_interaction_commands.odin",
	}
	return definition
}

@(private)
language_factory_command_definition :: proc(
	route: Native_Route,
	name: string,
	description: string,
) -> interaction.Command_Definition {
	definition := native_definition(route, name, {.Lifecycle}, description, {})
	definition.provenance = interaction.Definition_Provenance {
		provider = "odra-language-factory",
		source = "src/command/language_interaction_commands.odin",
	}
	return definition
}
