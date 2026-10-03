// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../interaction"

/* JAN_OUTPUT_COMMAND_COUNT is the complete Output and Integration public catalog. */
JAN_OUTPUT_COMMAND_COUNT :: 31

/* jan_output_command_definitions returns every public Output and Integration identity. */
jan_output_command_definitions :: proc() -> [JAN_OUTPUT_COMMAND_COUNT]interaction.Command_Definition {
	return {
		jan_output_view_definition(.Jan_Export, "jan-export", "Open the Jan export dispatcher for the active document."),
		jan_output_view_definition(.Jan_Export_Region, "jan-export-region", "Export the active checked Jan region."),
		jan_output_view_definition(.Jan_Export_Plain_Text, "jan-export-plain-text", "Export with the factory plain-text backend."),
		jan_output_view_definition(.Jan_Export_Html, "jan-export-html", "Export with the factory HTML backend."),
		jan_output_view_definition(.Jan_Export_Markdown, "jan-export-markdown", "Export with the factory Markdown backend."),
		jan_output_view_definition(.Jan_Export_Normalized_Jan, "jan-export-normalized-jan", "Export normalized Jan source."),
		jan_output_view_definition(.Jan_Export_Beamer, "jan-export-beamer", "Export through the optional Beamer adapter."),
		jan_output_view_definition(.Jan_Export_Latex, "jan-export-latex", "Export through the optional LaTeX adapter."),
		jan_output_view_definition(.Jan_Export_Pdf, "jan-export-pdf", "Export through the optional PDF adapter."),
		jan_output_view_definition(.Jan_Export_Odt, "jan-export-odt", "Export through the optional ODT adapter."),
		jan_output_view_definition(.Jan_Export_Texinfo, "jan-export-texinfo", "Export through the optional Texinfo adapter."),
		jan_output_view_definition(.Jan_Export_Info, "jan-export-info", "Export through the optional Info adapter."),
		jan_output_view_definition(.Jan_Export_Man_Page, "jan-export-man-page", "Export through the optional man-page adapter."),
		jan_output_view_definition(.Jan_Export_ICalendar, "jan-export-icalendar", "Export through the optional iCalendar adapter."),
		jan_output_edit_definition(.Jan_Citation_Insert, "jan-citation-insert", "Insert one resolved citation candidate."),
		jan_output_view_definition(.Jan_Citation_Follow, "jan-citation-follow", "Follow one resolved citation through its admitted provider."),
		jan_output_edit_definition(.Jan_Bibliography_Insert, "jan-bibliography-insert", "Insert one checked bibliography declaration."),
		jan_output_lifecycle_definition(.Jan_Publish, "jan-publish", "Publish one explicit Jan target."),
		jan_output_lifecycle_definition(.Jan_Publish_Project, "jan-publish-project", "Publish one configured Jan project."),
		jan_output_lifecycle_definition(.Jan_Publish_All, "jan-publish-all", "Publish every explicitly selected Jan project."),
		jan_output_lifecycle_definition(.Jan_Protocol_Handle, "jan-protocol-handle", "Handle one authenticated external Jan protocol request."),
		jan_output_view_definition(.Jan_Help_At_Point, "jan-help-at-point", "Show Jan help for the syntax or workflow at point."),
		jan_output_edit_definition(.Jan_Encrypt_Subtree, "jan-encrypt-subtree", "Encrypt the current subtree through an admitted provider."),
		jan_output_edit_definition(.Jan_Decrypt_Subtree, "jan-decrypt-subtree", "Decrypt the current subtree through an admitted provider."),
		jan_output_lifecycle_definition(.Jan_Mobile_Push, "jan-mobile-push", "Push one checked Jan synchronization manifest."),
		jan_output_edit_definition(.Jan_Mobile_Pull, "jan-mobile-pull", "Pull and apply one non-conflicting Jan synchronization manifest."),
		jan_output_edit_definition(.Jan_Mobile_Reconcile, "jan-mobile-reconcile", "Reconcile an explicit Jan synchronization conflict."),
		jan_output_edit_definition(.Jan_Dynamic_Block_Update, "jan-dynamic-block-update", "Update the current dynamic block from one checked provider candidate."),
		jan_output_global_definition(.Jan_Provider_Status, "jan-provider-status", "Inspect Jan provider availability and authority boundaries."),
		jan_output_global_definition(.Jan_Extension_Status, "jan-extension-status", "Inspect the active Jan extension generation."),
		jan_output_global_definition(.Jan_Output_Status, "jan-output-status", "Inspect Jan output capabilities, backends, limits, and providers."),
	}
}

@(private)
jan_output_view_definition :: proc(route: Native_Route, name, description: string) -> interaction.Command_Definition {
	return native_definition(route, name, {.View, .Lifecycle}, description)
}

@(private)
jan_output_lifecycle_definition :: proc(route: Native_Route, name, description: string) -> interaction.Command_Definition {
	return native_definition(route, name, {.View, .Lifecycle}, description)
}

@(private)
jan_output_global_definition :: proc(route: Native_Route, name, description: string) -> interaction.Command_Definition {
	return native_definition(route, name, {.View, .Lifecycle}, description, {})
}

@(private)
jan_output_edit_definition :: proc(route: Native_Route, name, description: string) -> interaction.Command_Definition {
	return native_definition(route, name, {.Buffer, .View, .Lifecycle, .Text_Mutation}, description)
}
