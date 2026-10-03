// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor_session"
import "../project"

@(private)
activate_test_project :: proc(
	ctx: Project_Command_Context,
	project_id: project.Project_ID,
	durable_id, name, root: string,
) -> bool {
	activation, activated, _ := editor_session.session_open_project_directory(
		ctx.session,
		editor_session.Project_Directory_Open_Request {
			session = ctx.handle,
			expected_catalog_generation = 1,
			actual_catalog_generation = 1,
			normalized_path = root,
			matching_projects = 1,
			project_id = project_id,
			project_generation = 1,
			durable_id = durable_id,
			name = name,
			trust = .Untrusted,
			temporary = false,
		},
	)
	if !activated {
		return false
	}
	_, projected, _ := editor_session.session_roots_replace(
		ctx.session,
		editor_session.Root_Replace_Request {
			session = ctx.handle,
			roots = []editor_session.Root_Proposal {{
				kind = .Project,
				path = root,
				project = activation.active.handle,
			}},
		},
	)
	return projected
}
