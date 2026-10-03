// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_frontend

import "core:os"
import "core:strings"
import "../ui"

/* renderer_icon_profile_detect selects the configured terminal glyph catalog. */
renderer_icon_profile_detect :: proc() -> Icon_Profile {
	value := os.get_env("ODRA_ICON_PROFILE", context.temp_allocator)
	if strings.equal_fold(value, "portable") do return .Portable
	return .Nerd_Font
}

@(private)
renderer_tree_icon :: proc(role: ui.Tree_Icon_Role, profile: Icon_Profile) -> string {
	if profile == .Nerd_Font {
		switch role {
		case .Project: return "󰏗"
		case .Directory_Open, .Directory_Special_Open: return ""
		case .Directory_Closed, .Directory_Special_Closed: return ""
		case .File_Source: return ""
		case .File_Documentation: return "󰈙"
		case .File_Configuration: return ""
		case .File_Version_Control: return "󰊢"
		case .Failure: return ""
		case .File, .Invalid: return ""
		}
	}
	switch role {
	case .Project: return "◆"
	case .Directory_Open, .Directory_Special_Open: return "▾"
	case .Directory_Closed, .Directory_Special_Closed: return "▸"
	case .File_Source: return "λ"
	case .File_Documentation: return "≡"
	case .File_Configuration: return "⚙"
	case .File_Version_Control: return "±"
	case .Failure: return "!"
	case .File, .Invalid: return "·"
	}
	return "·"
}
