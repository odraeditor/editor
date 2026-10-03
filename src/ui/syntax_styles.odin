// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

/* FACTORY_SYNTAX_STYLE_COUNT is the complete stable syntax-role mapping. */
FACTORY_SYNTAX_STYLE_COUNT :: 16

@(private)
factory_color :: proc(red, green, blue: u8) -> Optional_SRGB_Color {
	return Optional_SRGB_Color {
		present = true,
		color = SRGB_Color{red = red, green = green, blue = blue},
	}
}

/* factory_style_definition returns the maintained readable dark-background mapping. */
factory_style_definition :: proc(role: Style_Role) -> (Style_Definition, bool) {
	definition := Style_Definition{role = role}
	switch role {
	case .Text_Normal:
		return definition, true
	case .Syntax_Attribute:
		definition.foreground = factory_color(156, 220, 254)
	case .Syntax_Boolean:
		definition.foreground = factory_color(86, 156, 214)
	case .Syntax_Comment:
		definition.foreground = factory_color(106, 153, 85)
		definition.attributes = {.Dim}
	case .Syntax_Constant:
		definition.foreground = factory_color(79, 193, 255)
	case .Syntax_Constructor, .Syntax_Type:
		definition.foreground = factory_color(78, 201, 176)
	case .Syntax_Function:
		definition.foreground = factory_color(220, 220, 170)
	case .Syntax_Function_Builtin:
		definition.foreground = factory_color(220, 220, 170)
		definition.attributes = {.Bold}
	case .Syntax_Keyword:
		definition.foreground = factory_color(197, 134, 192)
	case .Syntax_Label:
		definition.foreground = factory_color(206, 145, 120)
	case .Syntax_Number:
		definition.foreground = factory_color(181, 206, 168)
	case .Syntax_Operator, .Syntax_Punctuation:
		definition.foreground = factory_color(212, 212, 212)
	case .Syntax_String:
		definition.foreground = factory_color(206, 145, 120)
	case .Syntax_Variable, .Syntax_Variable_Parameter:
		definition.foreground = factory_color(156, 220, 254)
	case .Invalid, .Text_Region, .Text_Search_Current, .List_Normal, .List_Current,
	     .List_Emphasis,
	     .Filesystem_Directory, .Filesystem_Permission_Read,
	     .Filesystem_Permission_Write, .Filesystem_Permission_Execute,
	     .Filesystem_Metadata,
	     .List_Mark_Save, .List_Mark_Kill, .Status_Normal, .Status_Active,
	     .Status_Safety, .Status_Identity, .Status_Position, .Status_Alert,
	     .Status_Workspace, .Status_Project, .Status_Editing_Context,
	     .Tree_Project, .Tree_Directory, .Tree_Directory_Special, .Tree_File,
	     .Tree_File_Source, .Tree_File_Documentation,
	     .Tree_File_Configuration, .Tree_File_Version_Control,
	     .Tree_Hierarchy, .Tree_Inactive, .Tree_Loading, .Tree_Failure,
	     .Tree_Destructive,
		     .Gutter_Background, .Gutter_Line_Number, .Gutter_Line_Number_Current,
		     .Gutter_Separator, .Popup_Background, .Popup_Content, .Popup_Border,
		     .Popup_Diagnostic, .Popup_Unavailable,
	     .Diagnostic_Normal, .Diagnostic_Rejected, .Diagnostic_Error,
	     .Diagnostic_Warning, .Diagnostic_Information, .Diagnostic_Hint:
		return {}, false
	}
	return definition, style_definition_is_valid(definition)
}

/* proposal_add_factory_syntax_styles installs every factory syntax definition. */
proposal_add_factory_syntax_styles :: proc(
	proposal: ^Proposal,
) -> (ok: bool, failure: Failure) {
	for role_value in int(Style_Role.Syntax_Attribute) ..= int(Style_Role.Syntax_Variable_Parameter) {
		definition, found := factory_style_definition(Style_Role(role_value))
		if !found {
			return false, generation_failure(proposal_state(proposal), .Prepare, .Invalid_Style)
		}
		_, added, add_failure := proposal_add_style(
			proposal,
			definition.role,
			definition.attributes,
			definition.foreground,
			definition.background,
		)
		if !added do return false, add_failure
	}
	return true, {}
}
