// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package theme

import "../ui"
import "core:math"

/* FACTORY_PROVIDER_NAME identifies the maintained repository-owned provider. */
FACTORY_PROVIDER_NAME :: "odra-factory"
/* FACTORY_PROVENANCE identifies the maintained source of factory definitions. */
FACTORY_PROVENANCE :: "src/theme/factory.odin"
/* WROCLAW_SUNRISE_IDENTITY is the muted solarized light factory identity. */
WROCLAW_SUNRISE_IDENTITY :: "wroclaw-sunrise"
/* WROCLAW_MORNING_IDENTITY is the bright clear light factory identity. */
WROCLAW_MORNING_IDENTITY :: "wroclaw-morning"
/* WROCLAW_SUNSET_IDENTITY is the warm golden-hour light factory identity. */
WROCLAW_SUNSET_IDENTITY :: "wroclaw-sunset"
/* WROCLAW_NIGHT_IDENTITY is the maintained dark fallback identity. */
WROCLAW_NIGHT_IDENTITY :: "wroclaw-night"
/* TERMINAL_DEFAULT_IDENTITY is the color-minimal safe baseline identity. */
TERMINAL_DEFAULT_IDENTITY :: "terminal-default"
/* FACTORY_MINIMUM_CONTRAST is the maintained normal-text legibility threshold. */
FACTORY_MINIMUM_CONTRAST :: 4.5

@(private)
Factory_Palette :: struct {
	background:   ui.SRGB_Color,
	foreground:   ui.SRGB_Color,
	muted:        ui.SRGB_Color,
	red:          ui.SRGB_Color,
	green:        ui.SRGB_Color,
	yellow:       ui.SRGB_Color,
	blue:         ui.SRGB_Color,
	magenta:      ui.SRGB_Color,
	cyan:         ui.SRGB_Color,
	selection_bg: ui.SRGB_Color,
}

/* factory_style_matrix returns all five complete maintained role mappings. */
factory_style_matrix :: proc() -> [FACTORY_DEFINITION_COUNT][CURRENT_STYLE_ROLE_COUNT]ui.Style_Definition {
	styles: [FACTORY_DEFINITION_COUNT][CURRENT_STYLE_ROLE_COUNT]ui.Style_Definition
	styles[0] = factory_color_styles(Factory_Palette {
		background = rgb(0xB0, 0xDE, 0xF3),
		foreground = rgb(0x1A, 0x20, 0x2C),
		muted = rgb(0x52, 0x5A, 0x5E),
		red = rgb(0x7C, 0x54, 0x4B),
		green = rgb(0x1E, 0x40, 0x51),
		yellow = rgb(0x65, 0x43, 0x3A),
		blue = rgb(0x3C, 0x59, 0x85),
		magenta = rgb(0x46, 0x5E, 0x8B),
		cyan = rgb(0x2C, 0x60, 0x80),
		selection_bg = rgb(0x1E, 0x40, 0x51),
	})
	styles[1] = factory_color_styles(Factory_Palette {
		background = rgb(0xF7, 0xFD, 0xFD),
		foreground = rgb(0x1A, 0x1F, 0x25),
		muted = rgb(0x68, 0x70, 0x6F),
		red = rgb(0x81, 0x40, 0x22),
		green = rgb(0x53, 0x59, 0x1E),
		yellow = rgb(0x6C, 0x58, 0x11),
		blue = rgb(0x33, 0x5A, 0xA7),
		magenta = rgb(0x4C, 0x5C, 0x92),
		cyan = rgb(0x30, 0x74, 0xA9),
		selection_bg = rgb(0x2B, 0x3C, 0x67),
	})
	styles[2] = factory_color_styles(Factory_Palette {
		background = rgb(0xF3, 0xEB, 0xDD),
		foreground = rgb(0x11, 0x13, 0x0E),
		muted = rgb(0x6A, 0x68, 0x66),
		red = rgb(0x83, 0x44, 0x0A),
		green = rgb(0x47, 0x28, 0x0C),
		yellow = rgb(0x6C, 0x49, 0x01),
		blue = rgb(0x37, 0x46, 0x70),
		magenta = rgb(0x57, 0x43, 0x80),
		cyan = rgb(0x6C, 0x5E, 0x97),
		selection_bg = rgb(0x49, 0x3E, 0x61),
	})
	styles[3] = factory_color_styles(Factory_Palette {
		background = rgb(0x1A, 0x1B, 0x26),
		foreground = rgb(0xD6, 0xD6, 0xB3),
		muted = rgb(0x84, 0x85, 0x87),
		red = rgb(0xB4, 0x77, 0x45),
		green = rgb(0xB2, 0xA4, 0x4B),
		yellow = rgb(0xBF, 0xBB, 0x40),
		blue = rgb(0x59, 0x81, 0xE3),
		magenta = rgb(0x78, 0xA0, 0xFA),
		cyan = rgb(0x51, 0xB6, 0xF5),
		selection_bg = rgb(0xD5, 0x92, 0x4F),
	})
	styles[4] = factory_terminal_default_styles()
	return styles
}

/* factory_definition_proposals borrows a caller-owned maintained style matrix. */
factory_definition_proposals :: proc(
	styles: ^[FACTORY_DEFINITION_COUNT][CURRENT_STYLE_ROLE_COUNT]ui.Style_Definition,
) -> [FACTORY_DEFINITION_COUNT]Definition_Proposal {
	assert(styles != nil)
	return [FACTORY_DEFINITION_COUNT]Definition_Proposal {
		{
			identity = WROCLAW_SUNRISE_IDENTITY,
			display_name = "Wrocław Sunrise",
			provider_name = FACTORY_PROVIDER_NAME,
			provenance = FACTORY_PROVENANCE,
			styles = styles[0][:],
		},
		{
			identity = WROCLAW_MORNING_IDENTITY,
			display_name = "Wrocław Morning",
			provider_name = FACTORY_PROVIDER_NAME,
			provenance = FACTORY_PROVENANCE,
			styles = styles[1][:],
		},
		{
			identity = WROCLAW_SUNSET_IDENTITY,
			display_name = "Wrocław Sunset",
			provider_name = FACTORY_PROVIDER_NAME,
			provenance = FACTORY_PROVENANCE,
			styles = styles[2][:],
		},
		{
			identity = WROCLAW_NIGHT_IDENTITY,
			display_name = "Wrocław Night",
			provider_name = FACTORY_PROVIDER_NAME,
			provenance = FACTORY_PROVENANCE,
			styles = styles[3][:],
		},
		{
			identity = TERMINAL_DEFAULT_IDENTITY,
			display_name = "Terminal Default",
			provider_name = FACTORY_PROVIDER_NAME,
			provenance = FACTORY_PROVENANCE,
			styles = styles[4][:],
		},
	}
}

/* theme_registry_init_factory creates the complete maintained session registry. */
theme_registry_init_factory :: proc(
	registry: ^Registry,
	registry_id: Registry_ID,
	limits := DEFAULT_RESOURCE_LIMITS,
	allocator := context.allocator,
) -> (ok: bool, failure: Failure) {
	styles := factory_style_matrix()
	proposals := factory_definition_proposals(&styles)
	return theme_registry_init(
		registry,
		registry_id,
		proposals[:],
		WROCLAW_NIGHT_IDENTITY,
		TERMINAL_DEFAULT_IDENTITY,
		limits,
		allocator,
	)
}

/* factory_fallback_styles returns the complete maintained startup definition. */
factory_fallback_styles :: proc() -> [CURRENT_STYLE_ROLE_COUNT]ui.Style_Definition {
	styles := factory_style_matrix()
	return styles[3]
}

/* factory_definition_contrast_is_valid checks every effective text color pair. */
factory_definition_contrast_is_valid :: proc(proposal: Definition_Proposal) -> bool {
	if proposal.identity == TERMINAL_DEFAULT_IDENTITY {
		for style in proposal.styles {
			if style.foreground.present || style.background.present {
				return false
			}
		}
		return true
	}
	for style in proposal.styles {
		if !style.foreground.present || !style.background.present ||
		   srgb_contrast_ratio(style.foreground.color, style.background.color) <
		   FACTORY_MINIMUM_CONTRAST {
			return false
		}
	}
	return true
}

/* srgb_contrast_ratio returns the WCAG relative-luminance contrast ratio. */
srgb_contrast_ratio :: proc(foreground, background: ui.SRGB_Color) -> f64 {
	foreground_luminance := srgb_relative_luminance(foreground)
	background_luminance := srgb_relative_luminance(background)
	lighter := max(foreground_luminance, background_luminance)
	darker := min(foreground_luminance, background_luminance)
	return (lighter + 0.05) / (darker + 0.05)
}

@(private)
factory_color_styles :: proc(
	palette: Factory_Palette,
) -> [CURRENT_STYLE_ROLE_COUNT]ui.Style_Definition {
	styles: [CURRENT_STYLE_ROLE_COUNT]ui.Style_Definition
	selected_foreground := palette.background
	set_style(&styles, .Text_Normal, palette.foreground, palette.background)
	set_style(&styles, .Text_Region, selected_foreground, palette.selection_bg, {.Bold})
	set_style(&styles, .Text_Search_Current, selected_foreground, palette.selection_bg, {.Bold, .Underline})
	set_style(&styles, .List_Normal, palette.foreground, palette.background)
	set_style(&styles, .List_Current, selected_foreground, palette.selection_bg)
	set_style(&styles, .List_Emphasis, palette.cyan, palette.background, {.Bold})
	set_style(&styles, .Filesystem_Directory, palette.cyan, palette.background, {.Bold})
	set_style(&styles, .Filesystem_Permission_Read, palette.yellow, palette.background)
	set_style(&styles, .Filesystem_Permission_Write, palette.red, palette.background)
	set_style(&styles, .Filesystem_Permission_Execute, palette.green, palette.background)
	set_style(&styles, .Filesystem_Metadata, palette.muted, palette.background, {.Dim})
	set_style(&styles, .List_Mark_Save, palette.green, palette.background, {.Bold})
	set_style(&styles, .List_Mark_Kill, palette.red, palette.background, {.Bold})
	set_style(&styles, .Status_Normal, palette.muted, palette.background)
	set_style(&styles, .Status_Active, palette.muted, palette.background)
	set_style(&styles, .Status_Safety, palette.red, palette.background, {.Bold})
	set_style(&styles, .Status_Identity, palette.yellow, palette.background, {.Bold})
	set_style(&styles, .Status_Position, palette.cyan, palette.background)
	set_style(&styles, .Status_Alert, palette.red, palette.background, {.Bold, .Underline})
	set_style(&styles, .Status_Workspace, palette.cyan, palette.background, {.Bold})
	set_style(&styles, .Status_Project, palette.blue, palette.background)
	set_style(&styles, .Status_Editing_Context, palette.magenta, palette.background)
	set_style(&styles, .Tree_Project, palette.blue, palette.background, {.Bold})
	set_style(&styles, .Tree_Directory, palette.cyan, palette.background, {.Bold})
	set_style(&styles, .Tree_Directory_Special, palette.yellow, palette.background, {.Bold})
	set_style(&styles, .Tree_File, palette.foreground, palette.background)
	set_style(&styles, .Tree_File_Source, palette.blue, palette.background)
	set_style(&styles, .Tree_File_Documentation, palette.green, palette.background)
	set_style(&styles, .Tree_File_Configuration, palette.magenta, palette.background)
	set_style(&styles, .Tree_File_Version_Control, palette.yellow, palette.background)
	set_style(&styles, .Tree_Hierarchy, palette.muted, palette.background, {.Dim})
	set_style(&styles, .Tree_Inactive, palette.muted, palette.background, {.Dim})
	set_style(&styles, .Tree_Loading, palette.yellow, palette.background)
	set_style(&styles, .Tree_Failure, palette.red, palette.background, {.Bold})
	set_style(&styles, .Tree_Destructive, palette.red, palette.background, {.Underline})
	set_style(&styles, .Gutter_Background, palette.muted, palette.background, {.Dim})
	set_style(&styles, .Gutter_Line_Number, palette.muted, palette.background, {.Dim})
	set_style(&styles, .Gutter_Line_Number_Current, palette.cyan, palette.background, {.Bold})
	set_style(&styles, .Gutter_Separator, palette.muted, palette.background, {.Dim})
	set_style(&styles, .Diagnostic_Normal, palette.yellow, palette.background)
	set_style(&styles, .Diagnostic_Rejected, palette.red, palette.background, {.Bold, .Underline})
	set_style(&styles, .Syntax_Attribute, palette.yellow, palette.background)
	set_style(&styles, .Syntax_Boolean, palette.yellow, palette.background)
	set_style(&styles, .Syntax_Comment, palette.muted, palette.background, {.Dim})
	set_style(&styles, .Syntax_Constant, palette.cyan, palette.background)
	set_style(&styles, .Syntax_Constructor, palette.magenta, palette.background)
	set_style(&styles, .Syntax_Function, palette.blue, palette.background)
	set_style(&styles, .Syntax_Function_Builtin, palette.cyan, palette.background)
	set_style(&styles, .Syntax_Keyword, palette.magenta, palette.background, {.Bold})
	set_style(&styles, .Syntax_Label, palette.red, palette.background)
	set_style(&styles, .Syntax_Number, palette.yellow, palette.background)
	set_style(&styles, .Syntax_Operator, palette.foreground, palette.background)
	set_style(&styles, .Syntax_Punctuation, palette.muted, palette.background)
	set_style(&styles, .Syntax_String, palette.green, palette.background)
	set_style(&styles, .Syntax_Type, palette.cyan, palette.background)
	set_style(&styles, .Syntax_Variable, palette.foreground, palette.background)
	set_style(&styles, .Syntax_Variable_Parameter, palette.red, palette.background)
	set_style(&styles, .Diagnostic_Error, palette.red, palette.background, {.Bold, .Underline})
	set_style(&styles, .Diagnostic_Warning, palette.yellow, palette.background, {.Underline})
	set_style(&styles, .Diagnostic_Information, palette.blue, palette.background, {.Reverse})
	set_style(&styles, .Diagnostic_Hint, palette.muted, palette.background, {.Dim})
	set_style(&styles, .Popup_Background, selected_foreground, palette.selection_bg)
	set_style(&styles, .Popup_Content, selected_foreground, palette.selection_bg)
	set_style(&styles, .Popup_Border, selected_foreground, palette.selection_bg, {.Bold})
	set_style(&styles, .Popup_Diagnostic, selected_foreground, palette.selection_bg, {.Bold, .Underline})
	set_style(&styles, .Popup_Unavailable, selected_foreground, palette.selection_bg, {.Dim})
	return styles
}

@(private)
factory_terminal_default_styles :: proc() -> [CURRENT_STYLE_ROLE_COUNT]ui.Style_Definition {
	styles: [CURRENT_STYLE_ROLE_COUNT]ui.Style_Definition
	for &style, index in styles do style.role = ui.Style_Role(index + 1)
	styles[role_index(.Text_Region)].attributes = {.Reverse}
	styles[role_index(.Text_Search_Current)].attributes = {.Reverse, .Underline}
	styles[role_index(.List_Current)].attributes = {.Reverse}
	styles[role_index(.List_Emphasis)].attributes = {.Bold}
	styles[role_index(.Filesystem_Directory)].attributes = {.Bold}
	styles[role_index(.Filesystem_Permission_Write)].attributes = {.Bold}
	styles[role_index(.Filesystem_Permission_Execute)].attributes = {.Underline}
	styles[role_index(.Filesystem_Metadata)].attributes = {.Dim}
	styles[role_index(.List_Mark_Save)].attributes = {.Bold}
	styles[role_index(.List_Mark_Kill)].attributes = {.Underline}
	styles[role_index(.Status_Safety)].attributes = {.Bold}
	styles[role_index(.Status_Identity)].attributes = {.Bold}
	styles[role_index(.Status_Position)].attributes = {.Dim}
	styles[role_index(.Status_Alert)].attributes = {.Bold, .Underline}
	styles[role_index(.Status_Workspace)].attributes = {.Bold}
	styles[role_index(.Status_Project)].attributes = {.Underline}
	styles[role_index(.Status_Editing_Context)].attributes = {.Dim}
	styles[role_index(.Tree_Project)].attributes = {.Bold}
	styles[role_index(.Tree_Directory)].attributes = {.Bold}
	styles[role_index(.Tree_Directory_Special)].attributes = {.Bold, .Underline}
	styles[role_index(.Tree_File_Documentation)].attributes = {.Underline}
	styles[role_index(.Tree_File_Configuration)].attributes = {.Bold}
	styles[role_index(.Tree_File_Version_Control)].attributes = {.Dim}
	styles[role_index(.Tree_Hierarchy)].attributes = {.Dim}
	styles[role_index(.Tree_Inactive)].attributes = {.Dim}
	styles[role_index(.Tree_Loading)].attributes = {.Bold}
	styles[role_index(.Tree_Failure)].attributes = {.Bold, .Underline}
	styles[role_index(.Tree_Destructive)].attributes = {.Underline}
	styles[role_index(.Gutter_Background)].attributes = {.Dim}
	styles[role_index(.Gutter_Line_Number)].attributes = {.Dim}
	styles[role_index(.Gutter_Line_Number_Current)].attributes = {.Bold}
	styles[role_index(.Gutter_Separator)].attributes = {.Dim}
	styles[role_index(.Diagnostic_Rejected)].attributes = {.Bold, .Underline}
	styles[role_index(.Diagnostic_Error)].attributes = {.Bold, .Underline}
	styles[role_index(.Diagnostic_Warning)].attributes = {.Underline}
	styles[role_index(.Diagnostic_Information)].attributes = {.Reverse}
	styles[role_index(.Diagnostic_Hint)].attributes = {.Dim}
	styles[role_index(.Syntax_Comment)].attributes = {.Dim}
	styles[role_index(.Syntax_Keyword)].attributes = {.Bold}
	styles[role_index(.Popup_Border)].attributes = {.Bold}
	styles[role_index(.Popup_Diagnostic)].attributes = {.Bold, .Underline}
	styles[role_index(.Popup_Unavailable)].attributes = {.Dim}
	return styles
}

@(private)
set_style :: proc(
	styles: ^[CURRENT_STYLE_ROLE_COUNT]ui.Style_Definition,
	role: ui.Style_Role,
	foreground, background: ui.SRGB_Color,
	attributes: ui.Style_Attributes = {},
) {
	styles[role_index(role)] = ui.Style_Definition {
		role = role,
		foreground = {present = true, color = foreground},
		background = {present = true, color = background},
		attributes = attributes,
	}
}

@(private)
role_index :: proc(role: ui.Style_Role) -> int {
	return int(role) - 1
}

@(private)
rgb :: proc(red, green, blue: u8) -> ui.SRGB_Color {
	return ui.SRGB_Color{red = red, green = green, blue = blue}
}

@(private)
srgb_relative_luminance :: proc(color: ui.SRGB_Color) -> f64 {
	return 0.2126 * srgb_linear_channel(color.red) +
		0.7152 * srgb_linear_channel(color.green) +
		0.0722 * srgb_linear_channel(color.blue)
}

@(private)
srgb_linear_channel :: proc(channel: u8) -> f64 {
	value := f64(channel) / 255.0
	if value <= 0.04045 do return value / 12.92
	return math.pow((value + 0.055) / 1.055, 2.4)
}
