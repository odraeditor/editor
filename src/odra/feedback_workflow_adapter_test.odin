// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../feedback"
import "../feedback_routing"
import "../feedback_workflow"
import "../interaction"
import "../ui"
import "core:testing"

/* Verifies editor feedback keeps public status text separate from diagnostic detail. */
@(test)
editor_feedback_projects_human_status :: proc(t: ^testing.T) {
	commands: Command_Context
	commands.persistent_allocator = context.allocator
	commands.temporary_allocator = context.temp_allocator
	ready := command_context_feedback_init(&commands, feedback_test_profile())
	testing.expect(t, ready)
	if !ready do return
	defer command_context_feedback_close(&commands)

	command_context_set_channel_diagnostic(
		&commands,
		.Package,
		"Package catalog is unavailable",
		feedback.Severity.Error,
		"transport=Timeout endpoint=https://catalog.invalid",
		.Required,
		.History,
	)
	content, role, visible, root_edge := command_feedback_content(&commands)
	testing.expect(t, visible && root_edge)
	testing.expect_value(t, content, "Package catalog is unavailable")
	testing.expect_value(t, role, ui.Style_Role.Status_Alert)
	projection, projected := command_context_feedback_projection(&commands)
	testing.expect(t, projected)
	if projected {
		testing.expect_value(t, feedback_routing.projection_content(&projection), content)
	}
	package_publication := commands.feedback_state.publications[int(feedback_workflow.Channel.Package) - 1]
	dismissed, _ := feedback_workflow.workflow_dismiss(
		&commands.feedback_state.workflow,
		package_publication,
	)
	testing.expect(t, dismissed)
	commands.diagnostic_length = 0
	_, progress_published := command_context_publish_progress(&commands, {
		state = .Running,
		measurement = .Determinate,
		current = 1,
		total = 3,
		phase = "buffers",
		message = "Marked operations",
	})
	testing.expect(t, progress_published)
	content, role, visible, root_edge = command_feedback_content(&commands)
	testing.expect(t, visible && root_edge)
	testing.expect_value(t, content, "Marked operations (1/3 buffers)")
	testing.expect_value(t, role, ui.Style_Role.Status_Active)
}

/* Verifies all maintained action families resolve only through the current command registry. */
@(test)
editor_feedback_actions_resolve_registered_commands :: proc(t: ^testing.T) {
	definitions := command.built_in_base_command_definitions()
	registry: interaction.Command_Registry
	registry_ready, registry_failure := interaction.command_registry_init(
		&registry,
		1,
		definitions[:],
		context.allocator,
	)
	testing.expectf(t, registry_ready, "command registry failed with %v", registry_failure.code)
	if !registry_ready do return
	defer interaction.command_registry_close(&registry)

	commands := Command_Context {
		registry = &registry,
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
	}
	ready := command_context_feedback_init(&commands, feedback_test_profile())
	testing.expect(t, ready)
	if !ready do return
	defer command_context_feedback_close(&commands)

	actions := [5]feedback_workflow.Action_Definition {
		{id = 1, kind = .Inspect, command = "keyboard-quit"},
		{id = 2, kind = .Retry, command = "keyboard-quit"},
		{id = 3, kind = .Cancel, command = "keyboard-quit"},
		{id = 4, kind = .Open_Source, command = "keyboard-quit"},
		{id = 5, kind = .Show_Log, command = "keyboard-quit"},
	}
	for action in actions {
		single := [1]feedback_workflow.Action_Definition{action}
		_, published := command_context_publish_feedback(
			&commands,
			.Package,
			"Package catalog action available",
			actions = single[:],
		)
		testing.expect(t, published)
		_, resolved := command_context_resolve_feedback_action(&commands, .Package, action.id)
		testing.expectf(t, resolved, "%v action did not resolve", action.kind)
	}
}

@(private)
feedback_test_profile :: proc() -> ui.Presentation_Profile_Handle {
	return {
		registry_id = 1,
		role = .Contextual_Information,
		profile_id = 1,
		profile_generation = 1,
	}
}
