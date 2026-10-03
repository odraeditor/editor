// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../editor_session"
import "../package_catalog_interaction"
import "core:strings"
import "core:testing"

/* Verifies stable routes map to the supported runtime command set. */
@(test)
package_catalog_routes_map_to_runtime_operations :: proc(t: ^testing.T) {
	routes := [?]command.Native_Route {
		.Package_Catalog_List,
		.Package_Catalog_Add,
		.Package_Catalog_Disable,
		.Package_Catalog_Remove,
		.Package_Catalog_Refresh,
		.Package_Catalog_Search,
		.Package_Catalog_Describe,
		.Package_Manual_Acquire,
		.Package_Advisory_List,
		.Package_Curator_Validate,
		.Package_Catalog_Doctor,
		.Package_List,
		.Package_Discover,
		.Package_Describe,
		.Package_Install,
		.Package_Enable,
		.Package_Disable,
		.Package_Update,
		.Package_Rollback,
		.Package_Remove,
		.Package_Cleanup,
		.Package_Doctor,
	}
	for route in routes {
		operation, mapped := package_catalog_interaction_operation(route)
		testing.expect(t, mapped)
		testing.expect(t, operation != .Invalid)
		action, executable := package_catalog_runtime_action(operation)
		if route == .Package_Manual_Acquire || route == .Package_Advisory_List ||
		   route == .Package_Curator_Validate {
			testing.expect(t, !executable)
			testing.expect_value(t, action, command.Package_Catalog_Runtime_Action.Invalid)
		} else {
			testing.expect(t, executable)
			testing.expect(t, action != .Invalid)
		}
	}
	confirmed_actions := [?]command.Package_Catalog_Runtime_Action {
		.Add,
		.Remove,
		.Package_Enable,
		.Package_Update,
		.Package_Rollback,
		.Package_Remove,
		.Package_Cleanup,
	}
	for action in confirmed_actions {
		testing.expect(t, package_catalog_runtime_action_requires_confirmation(action))
	}
	direct_actions := [?]command.Package_Catalog_Runtime_Action {
		.Disable,
		.Refresh,
		.Package_Install,
		.Package_Disable,
	}
	for action in direct_actions {
		testing.expect(t, !package_catalog_runtime_action_requires_confirmation(action))
	}
}

/* Verifies user-facing failures are fixed redacted projections. */
@(test)
package_catalog_failures_are_actionable_and_redacted :: proc(t: ^testing.T) {
	workflow: package_catalog_interaction.Workflow
	commands := Command_Context{package_catalog_interaction_workflow = &workflow}
	started, started_ok, _ := package_catalog_interaction.workflow_begin(
		&workflow,
		.Catalog_Refresh,
		package_catalog_interaction.availability_available(),
	)
	testing.expect(t, started_ok)
	recorded := command_context_package_catalog_failure(
		&commands,
		started.generation,
		.Credential_Unavailable,
	)
	testing.expect(t, recorded)
	snapshot, present := package_catalog_interaction.workflow_snapshot(&workflow)
	testing.expect(t, present)
	failure_text := package_catalog_interaction.text_string(&snapshot.failure)
	recovery_text := package_catalog_interaction.text_string(&snapshot.recovery)
	testing.expect(t, strings.contains(failure_text, "credential"))
	testing.expect(t, strings.contains(recovery_text, "credential reference"))
	testing.expect(t, !strings.contains(failure_text, "token"))
	testing.expect(t, !strings.contains(recovery_text, "secret"))

	endpoint_reason, endpoint_recovery, endpoint_described :=
		package_catalog_failure_detail(.Endpoint_Unavailable)
	testing.expect(t, endpoint_described)
	testing.expect(t, strings.contains(endpoint_reason, "endpoint"))
	testing.expect(t, strings.contains(endpoint_recovery, "offline state"))
	partial_reason, partial_recovery, partial_described :=
		package_catalog_failure_detail(.Partial_Capability)
	testing.expect(t, partial_described)
	testing.expect(t, strings.contains(partial_reason, "not available"))
	testing.expect(t, strings.contains(partial_recovery, "select a source"))
}

/* Verifies close releases the heap-owned workflow and retained candidates. */
@(test)
package_catalog_workflow_close_releases_owned_state :: proc(t: ^testing.T) {
	workflow, allocation_error := new(package_catalog_interaction.Workflow, context.allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	runtime_workflow, runtime_allocation_error := new(
		Package_Catalog_Runtime_Workflow_State,
		context.allocator,
	)
	testing.expect(t, runtime_allocation_error == nil)
	if runtime_allocation_error != nil {
		free(workflow, context.allocator)
		return
	}
	commands := Command_Context {
		package_catalog_interaction_workflow = workflow,
		package_catalog_runtime_workflow = runtime_workflow,
		persistent_allocator = context.allocator,
	}
	started, started_ok, _ := package_catalog_interaction.workflow_begin(
		workflow,
		.Catalog_Search,
		package_catalog_interaction.availability_available(),
	)
	testing.expect(t, started_ok)
	requesting, submitted, _ := package_catalog_interaction.workflow_submit_prompt(
		workflow,
		started.generation,
	)
	testing.expect(t, submitted)
	candidate_value, candidate_ok := package_catalog_interaction.candidate(
		"org.example.package",
		"Example Package",
		.Package,
		2,
		4,
		"snapshot-restart",
		.Current,
	)
	testing.expect(t, candidate_ok)
	_, published, _ := package_catalog_interaction.workflow_publish_candidates(
		workflow,
		requesting.generation,
		7,
		[]package_catalog_interaction.Candidate{candidate_value},
	)
	testing.expect(t, published)
	close_failure := command_context_close(&commands)
	testing.expect_value(t, close_failure.stage, App_Stage.None)
	testing.expect(t, commands.package_catalog_interaction_workflow == nil)
	testing.expect(t, commands.package_catalog_runtime_workflow == nil)
}

/* Selecting a package candidate restores its owning view before the next phase. */
@(test)
package_catalog_selection_restores_return_entry :: proc(t: ^testing.T) {
	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(9_301),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized do return
	first, first_ok, _ := editor_session.session_create_buffer(
		&session,
		editor_session.Create_Buffer_Request {
			session = handle,
			name = "package-selection-owner",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	second, second_ok, _ := editor_session.session_create_buffer(
		&session,
		editor_session.Create_Buffer_Request {
			session = handle,
			name = "package-selection-other",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, first_ok && second_ok)
	if !first_ok || !second_ok do return
	entries := [2]editor_session.Entry_Handle{first.entry, second.entry}
	defer {
		for entry in entries {
			detached: editor_session.Detached_Entry
			_, detached_ok, _ := editor_session.session_entry_detach(&session, entry, &detached)
			testing.expect(t, detached_ok)
			if detached_ok {
				_, cleaned, _ := editor_session.detached_entry_cleanup(&detached)
				testing.expect(t, cleaned)
				if cleaned {
					released, _ := editor_session.detached_entry_release(&detached)
					testing.expect(t, released)
				}
			}
		}
		closed, _ := editor_session.session_close(&session)
		testing.expect(t, closed)
	}
	_, _, presented, _ := editor_session.session_present_ui(
		&session,
		handle,
		candidate_ui_visible_target().ui,
	)
	testing.expect(t, presented)
	commands := Command_Context {
		session_owner = &session,
		session_handle = handle,
		candidate_ui = {return_target = {kind = .Primary_View, entry = first.entry}},
	}
	failure := command_context_complete_package_catalog_selection(&commands)
	testing.expect_value(t, failure.stage, App_Stage.None)
	visible, visible_ok, _ := editor_session.session_visible_target(&session, handle)
	testing.expect(t, visible_ok)
	testing.expect_value(t, visible.kind, editor_session.Visible_Target_Kind.Primary_View)
	testing.expect_value(t, visible.entry, first.entry)
	testing.expect_value(t, commands.candidate_ui.return_target.kind, editor_session.Visible_Target_Kind.None)
}
