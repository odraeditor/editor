// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_frontend

import "../ui"
import "core:testing"

/* Terminal icon catalogs retain semantic coverage and a portable fallback. */
@(test)
terminal_tree_icon_catalogs_cover_darek_roles :: proc(t: ^testing.T) {
	roles := []ui.Tree_Icon_Role {
		.Project,
		.Directory_Open,
		.Directory_Closed,
		.Directory_Special_Open,
		.Directory_Special_Closed,
		.File,
		.File_Source,
		.File_Documentation,
		.File_Configuration,
		.File_Version_Control,
		.Failure,
	}
	for role in roles {
		portable := renderer_tree_icon(role, .Portable)
		rich := renderer_tree_icon(role, .Nerd_Font)
		testing.expectf(t, len(portable) > 0, "missing portable icon for %v", role)
		testing.expectf(t, len(rich) > 0, "missing rich icon for %v", role)
		testing.expect(t, len(portable) <= ui.MAX_TREE_ICON_BYTES)
		testing.expect(t, len(rich) <= ui.MAX_TREE_ICON_BYTES)
	}
}
