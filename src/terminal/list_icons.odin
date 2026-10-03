// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_frontend

import "../ui"

@(private)
renderer_list_icon :: proc(role: ui.List_Icon_Role, profile: Icon_Profile) -> string {
	if profile == .Nerd_Font {
		switch role {
		case .Textual:   return "󰉿 "
		case .Callable:  return "󰊕 "
		case .Construct: return "󰆧 "
		case .Value:     return "󰎠 "
		case .Type:      return "󰌗 "
		case .Module:    return "󰏗 "
		case .Field:     return "󰜢 "
		case .Keyword:   return "󰌋 "
		case .Invalid:   return ""
		}
	}
	switch role {
	case .Textual:   return "[text]    "
	case .Callable:  return "[call]    "
	case .Construct: return "[ctor]    "
	case .Value:     return "[value]   "
	case .Type:      return "[type]    "
	case .Module:    return "[module]  "
	case .Field:     return "[field]   "
	case .Keyword:   return "[keyword] "
	case .Invalid:   return ""
	}
	return ""
}
