// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor_session

import "../project"
import "core:testing"

/* Dir abandonment keeps every decision generation checked and cancellation preserving. */
@(test)
coordinates_abandonment_outcomes :: proc(t: ^testing.T) {
	session: Session
	handle, initialized, _ := session_init(
		&session,
		Session_ID(4_101),
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer session_close(&session)
	_, published, _ := session_roots_replace(
		&session,
		Root_Replace_Request {
			session = handle,
			roots = []Root_Proposal{{kind = .Dir, path = "/tmp/odra-abandonment"}},
		},
	)
	testing.expect(t, published)
	root := abandonment_root(t, &session, handle)

	cancelled: Dir_Abandonment_Preparation
	prepared, _ := session_prepare_dir_abandonment(
		&session,
		handle,
		root,
		.Exit,
		false,
		&cancelled,
	)
	testing.expect(t, prepared)
	testing.expect_value(t, cancelled.outcome, Dir_Abandonment_Outcome.Decision_Required)
	testing.expect_value(t, dir_abandonment_path_text(&cancelled), "/tmp/odra-abandonment")
	admission, admitted, _ := session_admit_dir_abandonment(&session, &cancelled, .Cancel)
	testing.expect(t, admitted)
	testing.expect_value(t, admission, Dir_Abandonment_Admission.Cancelled)
	testing.expect_value(t, abandonment_root(t, &session, handle), root)

	declined: Dir_Abandonment_Preparation
	prepared, _ = session_prepare_dir_abandonment(
		&session,
		handle,
		root,
		.Remove_Root,
		false,
		&declined,
	)
	testing.expect(t, prepared)
	admission, admitted, _ = session_admit_dir_abandonment(&session, &declined, .Decline)
	testing.expect(t, admitted)
	testing.expect_value(t, admission, Dir_Abandonment_Admission.Continue)

	suppressed: Dir_Abandonment_Preparation
	prepared, _ = session_prepare_dir_abandonment(
		&session,
		handle,
		root,
		.Replace_Roots,
		true,
		&suppressed,
	)
	testing.expect(t, prepared)
	testing.expect_value(t, suppressed.outcome, Dir_Abandonment_Outcome.Ready)
	admission, admitted, _ = session_admit_dir_abandonment(&session, &suppressed, .Continue)
	testing.expect(t, admitted)
	testing.expect_value(t, admission, Dir_Abandonment_Admission.Continue)

	conversion: Dir_Abandonment_Preparation
	prepared, _ = session_prepare_dir_abandonment(
		&session,
		handle,
		root,
		.Exit,
		false,
		&conversion,
	)
	testing.expect(t, prepared)
	_, premature, premature_failure := session_admit_dir_abandonment(
		&session,
		&conversion,
		.Convert,
	)
	testing.expect(t, !premature)
	testing.expect_value(t, premature_failure.code, Failure_Code.Busy)

	activation, activated, activation_failure := session_open_project_directory(
		&session,
		Project_Directory_Open_Request {
			session = handle,
			expected_catalog_generation = 1,
			actual_catalog_generation = 1,
			normalized_path = "/tmp/odra-abandonment",
			matching_projects = 1,
			project_id = project.Project_ID(4_102),
			project_generation = project.Project_Generation(1),
			durable_id = "abandonment-project",
			name = "Abandonment",
			trust = .Untrusted,
			temporary = false,
		},
	)
	testing.expectf(t, activated, "Project activation failed: %v", activation_failure.code)
	if !activated {
		return
	}
	_, projected, projection_failure := session_roots_replace(
		&session,
		Root_Replace_Request {
			session = handle,
			roots = []Root_Proposal {{
				kind = .Project,
				path = "/tmp/odra-abandonment",
				project = activation.active.handle,
			}},
		},
	)
	testing.expectf(t, projected, "Project root failed: %v", projection_failure.code)
	admission, admitted, _ = session_admit_dir_abandonment(&session, &conversion, .Convert)
	testing.expect(t, admitted)
	testing.expect_value(t, admission, Dir_Abandonment_Admission.Continue)
}

/* Root replacement invalidates an outstanding ordinary-Dir abandonment authority. */
@(test)
dir_abandonment_rejects_stale_root_generation :: proc(t: ^testing.T) {
	session: Session
	handle, initialized, _ := session_init(
		&session,
		Session_ID(4_111),
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer session_close(&session)
	_, published, _ := session_roots_replace(
		&session,
		Root_Replace_Request {
			session = handle,
			roots = []Root_Proposal{{kind = .Dir, path = "/tmp/odra-stale-dir"}},
		},
	)
	testing.expect(t, published)
	root := abandonment_root(t, &session, handle)
	prepared: Dir_Abandonment_Preparation
	prepared_ok, _ := session_prepare_dir_abandonment(
		&session,
		handle,
		root,
		.Remove_Root,
		false,
		&prepared,
	)
	testing.expect(t, prepared_ok)
	_, replaced, _ := session_roots_replace(
		&session,
		Root_Replace_Request {
			session = handle,
			roots = []Root_Proposal{{kind = .Dir, path = "/tmp/odra-other-dir"}},
		},
	)
	testing.expect(t, replaced)
	_, admitted, failure := session_admit_dir_abandonment(&session, &prepared, .Decline)
	testing.expect(t, !admitted)
	testing.expect_value(t, failure.code, Failure_Code.Busy)
	session_abort_dir_abandonment(&prepared)
}

@(private)
abandonment_root :: proc(t: ^testing.T, session: ^Session, handle: Session_Handle) -> Root_Handle {
	roots, listed, failure := session_roots(session, handle)
	testing.expectf(t, listed, "Root inspection failed: %v", failure.code)
	if !listed || len(roots.descriptors) != 1 {
		if listed {
			root_batch_close(&roots)
		}
		return {}
	}
	result := roots.descriptors[0].handle
	root_batch_close(&roots)
	return result
}
