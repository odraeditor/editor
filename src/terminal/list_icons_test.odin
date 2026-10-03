// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_frontend

import "../ui"
import "core:testing"

/* Terminal list icon catalogs cover every admitted semantic role and fallback. */
@(test)
terminal_list_icon_catalogs_cover_semantic_roles :: proc(t: ^testing.T) {
	for value in int(ui.List_Icon_Role.Textual) ..= int(ui.List_Icon_Role.Keyword) {
		role := ui.List_Icon_Role(value)
		portable := renderer_list_icon(role, .Portable)
		rich := renderer_list_icon(role, .Nerd_Font)
		testing.expectf(t, len(portable) > 0, "missing portable icon for %v", role)
		testing.expectf(t, len(rich) > 0, "missing rich icon for %v", role)
	}
	testing.expect_value(t, renderer_list_icon(.Invalid, .Portable), "")
	testing.expect_value(t, renderer_list_icon(.Invalid, .Nerd_Font), "")
}
