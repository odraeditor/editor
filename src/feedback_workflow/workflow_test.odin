// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package feedback_workflow

import "../feedback"
import "../feedback_routing"
import "../ui"
import "core:testing"

/* Verifies every maintained producer family enters one semantic workflow. */
@(test)
maintained_consumers_publish_through_one_workflow :: proc(t: ^testing.T) {
	workflow, ready := test_workflow(t)
	if !ready do return
	defer test_workflow_close(t, &workflow)
	channels := [6]Channel{.Command, .Save, .Recovery, .Language_Service, .Project, .Package}
	for channel in channels {
		publication, published, failure := workflow_publish_notification(&workflow, {
			channel = channel,
			class = .Information,
			severity = .Information,
			attention = .Ordinary,
			lifecycle = .Transient,
			retention = .None,
			visibility = .Public,
			message = channel_title(channel),
		})
		testing.expectf(t, published, "%v publication failed with %v", channel, failure.code)
		if published do testing.expect_value(t, publication.record_id, feedback.Record_ID(u64(channel)))
	}
	inspection, inspected, failure := workflow_inspect(&workflow)
	testing.expectf(t, inspected, "inspection failed with %v", failure.code)
	if inspected {
		testing.expect_value(t, inspection.feedback.usage.active_records, u64(6))
		testing.expect_value(t, inspection.routing.routes, u8(9))
		testing.expect_value(t, inspection.presentations, u8(1))
	}
}

/* Verifies long-operation generations replace status and retain the terminal outcome. */
@(test)
long_operation_progress_replaces_and_completes :: proc(t: ^testing.T) {
	workflow, ready := test_workflow(t)
	if !ready do return
	defer test_workflow_close(t, &workflow)
	first, published, failure := workflow_publish_progress(&workflow, {
		state = .Running,
		measurement = .Determinate,
		current = 1,
		total = 2,
		phase = "index",
		message = "Indexing Project",
	})
	testing.expectf(t, published, "running publication failed with %v", failure.code)
	completed: Publication
	completed, published, failure = workflow_publish_progress(&workflow, {
		state = .Succeeded,
		measurement = .Determinate,
		current = 2,
		total = 2,
		phase = "complete",
		message = "Project indexed",
	})
	testing.expectf(t, published, "completion publication failed with %v", failure.code)
	if published {
		testing.expect_value(t, completed.record_id, first.record_id)
		testing.expect(t, completed.record_generation > first.record_generation)
	}
	projection, present := workflow_status_projection(&workflow)
	testing.expect(t, present)
	if present {
		testing.expect_value(t, feedback_routing.projection_content(&projection), "Project indexed (2/2 complete)")
	}
	inspection, inspected, _ := workflow_inspect(&workflow)
	testing.expect(t, inspected)
	if inspected do testing.expect_value(t, inspection.feedback.usage.history_records, u64(1))
}

/* Verifies action commands remain unavailable without exact current authority. */
@(test)
workflow_actions_require_exact_record_authority :: proc(t: ^testing.T) {
	workflow, ready := test_workflow(t)
	if !ready do return
	defer test_workflow_close(t, &workflow)
	actions := []Action_Definition{{id = 1, kind = .Retry, command = "package-refresh", argument = "main"}}
	publication, published, failure := workflow_publish_notification(&workflow, {
		channel = .Package,
		class = .Warning,
		severity = .Warning,
		attention = .Ordinary,
		lifecycle = .Retained,
		retention = .History,
		visibility = .Public,
		message = "Package catalog is unavailable",
		detail = "endpoint-timeout",
		actions = actions,
	})
	testing.expectf(t, published, "action publication failed with %v", failure.code)
	if !published do return
	authority, resolved, resolve_failure := workflow_resolve_action(&workflow, publication, 1)
	testing.expectf(t, resolved, "action resolution failed with %v", resolve_failure.code)
	if resolved {
		testing.expect_value(t, authority.action.command, "package-refresh")
		feedback.action_authority_release(&authority, context.temp_allocator)
	}
	stale := publication
	stale.record_generation += 1
	_, resolved, _ = workflow_resolve_action(&workflow, stale, 1)
	testing.expect(t, !resolved)
}

/* Verifies dismissal removes active semantic and visible presentation state together. */
@(test)
workflow_dismissal_is_exact :: proc(t: ^testing.T) {
	workflow, ready := test_workflow(t)
	if !ready do return
	defer test_workflow_close(t, &workflow)
	publication, published, _ := workflow_publish_notification(&workflow, {
		channel = .Command,
		class = .Acknowledgement,
		severity = .Information,
		attention = .Ordinary,
		lifecycle = .Transient,
		retention = .None,
		visibility = .Public,
		message = "Saved",
	})
	testing.expect(t, published)
	dismissed, failure := workflow_dismiss(&workflow, publication)
	testing.expectf(t, dismissed, "dismissal failed with %v", failure.code)
	_, present := workflow_status_projection(&workflow)
	testing.expect(t, !present)
}

@(private)
test_workflow :: proc(t: ^testing.T) -> (workflow: Workflow, ready: bool) {
	profile := ui.Presentation_Profile_Handle {
		registry_id = 1,
		role = .Contextual_Information,
		profile_id = 1,
		profile_generation = 1,
	}
	failure: Failure
	ready, failure = workflow_init(
		&workflow,
		1,
		profile,
		{persistent = context.allocator, temporary = context.temp_allocator},
		status_frontend(),
	)
	testing.expectf(t, ready, "workflow init failed with %v", failure.code)
	return workflow, ready
}

@(private)
test_workflow_close :: proc(t: ^testing.T, workflow: ^Workflow) {
	closed, failure := workflow_close(workflow)
	testing.expectf(t, closed, "workflow close failed with %v", failure.code)
}
