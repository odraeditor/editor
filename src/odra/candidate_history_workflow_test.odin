// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../hosting"
import "../interaction"
import "../project"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"

/* Verifies Project history is projected into ranking and releases all native ownership. */
@(test)
projects_successful_recency_without_persistence :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	commands := Command_Context {
		persistent_allocator = allocator,
		temporary_allocator = allocator,
	}
	initialized, init_failure := project.candidate_history_init(
		&commands.project_workflow.candidate_history,
		"",
		allocator,
	)
	testing.expectf(t, initialized, "candidate history init failed with %v", init_failure.code)
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	definitions := [2]interaction.Candidate_Descriptor_Definition {
		{
			identity = {kind = 1, primary = 1},
			label = "beta",
			action = {kind = .Invoke_Command, owner_generation = 1, primary = 1, secondary = 1},
			availability = .Available,
			durable_category = .Command,
			durable_key = "beta-command",
		},
		{
			identity = {kind = 1, primary = 2},
			label = "alpha",
			action = {kind = .Invoke_Command, owner_generation = 1, primary = 2, secondary = 1},
			availability = .Available,
			durable_category = .Command,
			durable_key = "alpha-command",
		},
	}
	testing.expect(t, command_context_candidate_history_record(
		&commands,
		.Command,
		"alpha-command",
	))
	source := interaction.Candidate_Source_Definition {
		kind = .Commands,
		scope_identity = 1,
		scope_generation = 1,
		source_generation = 1,
		descriptors = definitions[:],
	}
	command_context_candidate_history_rank_source(&commands, &source, {})
	testing.expect_value(t, source.descriptors[0].recency, u64(0))
	testing.expect_value(t, source.descriptors[1].recency, u64(1))

	session: interaction.Candidate_Session
	_, session_ok, session_failure := interaction.candidate_session_init(
		&session,
		interaction.Candidate_Config {
			session_id = 1,
			limits = interaction.DEFAULT_CANDIDATE_LIMITS,
			persistent_allocator = allocator,
			temporary_allocator = allocator,
		},
		source,
	)
	testing.expectf(t, session_ok, "ranked session init failed with %v", session_failure.code)
	if session_ok {
		view, viewed, view_failure := interaction.candidate_session_view(&session)
		testing.expectf(t, viewed, "ranked session view failed with %v", view_failure.code)
		if viewed && len(view.rows) == 2 {
			testing.expect_value(t, view.rows[0].label, "alpha")
		}
		_, _, _ = interaction.candidate_session_close(&session)
	}
	testing.expect(t, !command_context_candidate_history_flush(&commands))
	project.candidate_history_close(&commands.project_workflow.candidate_history)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies candidate, native-history, and Racket failures produce copied bounded diagnostics. */
@(test)
navigation_failures_give_bounded_diagnostics :: proc(t: ^testing.T) {
	commands: Command_Context
	command_context_candidate_failure_diagnostic(
		&commands,
		"Candidate query",
		interaction.Candidate_Failure {
			code = .Query_Limit,
			session_generation = 7,
			source_generation = 11,
			limit = 4096,
			actual = 4097,
		},
	)
	diagnostic := string(commands.diagnostic[:commands.diagnostic_length])
	testing.expect_value(t, diagnostic, "Candidate list could not be updated; prior results were preserved")
	testing.expect(t, commands.diagnostic_length <= len(commands.diagnostic))

	command_context_candidate_history_native_diagnostic(
		&commands,
		"publication retry",
		project.Candidate_History_Failure {
			code = .Retry_Exhausted,
			limit = 1,
			actual = 2,
		},
	)
	diagnostic = string(commands.diagnostic[:commands.diagnostic_length])
	testing.expect(t, strings.contains(diagnostic, "publication retry failed: Retry_Exhausted"))
	testing.expect(t, strings.contains(diagnostic, "navigation remains available"))

	command_context_candidate_history_host_diagnostic(
		&commands,
		"load",
		hosting.Failure_Context {
			code = .Racket_Exception,
			diagnostic = "callback budget exhausted",
		},
	)
	diagnostic = string(commands.diagnostic[:commands.diagnostic_length])
	testing.expect(t, strings.contains(diagnostic, "load failed: Racket_Exception"))
	testing.expect(t, strings.contains(diagnostic, "callback budget exhausted"))
	testing.expect(t, commands.diagnostic_length <= len(commands.diagnostic))
}

/* Verifies the coordinator publishes and reloads ordering through the real Racket boundary. */
@(test)
survives_owner_restart :: proc(t: ^testing.T) {
	state_root, root_error := os.make_directory_temp(
		"",
		"odra-candidate-navigation-acceptance-*",
		context.allocator,
	)
	testing.expect(t, root_error == nil)
	if root_error != nil {return}
	defer {
		os.remove_all(state_root)
		delete(state_root)
	}
	permissions_error := os.chmod(
		state_root,
		os.Permissions{.Read_User, .Write_User, .Execute_User},
	)
	testing.expect(t, permissions_error == nil)
	if permissions_error != nil {return}

	runtime: hosting.Runtime
	started, start_failure := hosting.runtime_start(&runtime)
	testing.expectf(t, started, "Racket runtime start failed: %s", start_failure.diagnostic)
	if !started {return}
	defer {
		stopped, stop_failure := hosting.runtime_shutdown(&runtime)
		testing.expectf(t, stopped, "Racket runtime shutdown failed: %s", stop_failure.diagnostic)
	}

	project_id := "candidate-acceptance"
	first := Command_Context {
		racket_runtime = &runtime,
		candidate_history_state_root = state_root,
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
	}
	initialized, init_failure := project.candidate_history_init(
		&first.project_workflow.candidate_history,
		project_id,
	)
	testing.expectf(t, initialized, "history init failed: %v", init_failure.code)
	if !initialized {return}
	first.project_workflow.candidate_history_persistence_ready =
		command_context_candidate_history_load(&first, project_id)
	testing.expect(t, first.project_workflow.candidate_history_persistence_ready)
	testing.expect(t, command_context_candidate_history_record(&first, .Command, "project-find-file"))
	testing.expect(t, command_context_candidate_history_record(&first, .Document, "/tmp/alpha.odin"))
	testing.expect(t, command_context_candidate_history_flush(&first))
	project.candidate_history_close(&first.project_workflow.candidate_history)

	second := Command_Context {
		racket_runtime = &runtime,
		candidate_history_state_root = state_root,
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
	}
	initialized, init_failure = project.candidate_history_init(
		&second.project_workflow.candidate_history,
		project_id,
	)
	testing.expectf(t, initialized, "restart history init failed: %v", init_failure.code)
	if !initialized {return}
	defer project.candidate_history_close(&second.project_workflow.candidate_history)
	loaded := command_context_candidate_history_load(&second, project_id)
	testing.expect(t, loaded)
	command_sequence, command_found := project.candidate_history_lookup(
		&second.project_workflow.candidate_history,
		.Command,
		"project-find-file",
	)
	document_sequence, document_found := project.candidate_history_lookup(
		&second.project_workflow.candidate_history,
		.Document,
		"/tmp/alpha.odin",
	)
	testing.expect(t, command_found)
	testing.expect(t, document_found)
	testing.expect_value(t, command_sequence, u64(1))
	testing.expect_value(t, document_sequence, u64(2))
	testing.expect(t, second.diagnostic_length == 0)
}
