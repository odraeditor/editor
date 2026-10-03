// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../bridge"
import "../display"
import "../document"
import "../editor"
import "../hosting"
import "../history"
import "../interaction"
import "../language"
import "../layout"
import "../search"
import edit_transaction "../transaction"
import editor_view "../view"
import "base:runtime"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"

@(private)
COMMAND_TEST_SCENARIO :: i32(#config(ODRA_RACKET_COMMAND_SCENARIO, 0))
@(private)
HISTORY_POLICY_TEST_SCENARIO :: i32(#config(ODRA_RACKET_HISTORY_POLICY_SCENARIO, 0))
@(private)
DISPLAY_POLICY_TEST_SCENARIO :: i32(#config(ODRA_RACKET_DISPLAY_POLICY_SCENARIO, 0))

/* Verifies the complete Ksawery command range survives contextual route decoding. */
@(test)
contextual_routes_decode_ksawery_range :: proc(t: ^testing.T) {
	routes := [6]Contextual_Route {
		Contextual_Route.Ksawery_Merge_Fast_Forward,
		Contextual_Route.Ksawery_Conflict_Delete,
		Contextual_Route.Ksawery_Providers,
		Contextual_Route.Ksawery_Provider_Reload,
		Contextual_Route.Ksawery_Provider_Disable,
		Contextual_Route.Ksawery_Raw_Command,
	}
	for expected in routes {
		decoded, ok := contextual_route_decode(contextual_route(expected))
		testing.expect(t, ok)
		testing.expect_value(t, decoded, expected)
	}
}

/* Verifies built-in activation rejects missing, duplicate, and incompatible routes. */
@(test)
registry_rejects_bad_route_contracts :: proc(t: ^testing.T) {
	definitions := test_built_in_command_definitions()

	missing := definitions
	missing[0].route = {}
	registry: interaction.Command_Registry
	ready, failure := built_in_command_registry_init(
		&registry,
		interaction.Registry_Generation(1),
		context.allocator,
		provided_definitions = missing[:],
	)
	testing.expect(t, !ready)
	testing.expect_value(t, failure.code, interaction.Failure_Code.Invalid_Route)

	duplicate := definitions
	duplicate[1].route = duplicate[0].route
	ready, failure = built_in_command_registry_init(
		&registry,
		interaction.Registry_Generation(1),
		context.allocator,
		provided_definitions = duplicate[:],
	)
	testing.expect(t, !ready)
	testing.expect_value(t, failure.code, interaction.Failure_Code.Duplicate_Route)

	incompatible := definitions
	incompatible[0].effects = {.Buffer}
	ready, failure = built_in_command_registry_init(
		&registry,
		interaction.Registry_Generation(1),
		context.allocator,
		provided_definitions = incompatible[:],
	)
	testing.expect(t, !ready)
	testing.expect_value(t, failure.code, interaction.Failure_Code.Invalid_Effects)

	failing := Native_Failing_Allocator{backing = context.allocator, fail_after = 0}
	ready, failure = built_in_command_registry_init(
		&registry,
		interaction.Registry_Generation(1),
		native_failing_allocator(&failing),
	)
	testing.expect(t, !ready)
	testing.expect_value(t, failure.code, interaction.Failure_Code.Persistent_Memory_Limit)
}

/* Verifies success and contained failures through isolated process-lifetime scenarios. */
@(test)
racket_command_publishes_one_revision :: proc(t: ^testing.T) {
	racket_runtime: hosting.Runtime
	started, start_failure := hosting.runtime_start(&racket_runtime)
	testing.expectf(t, started, "runtime start failed: %s", start_failure.diagnostic)
	if !started {
		return
	}

	buffer: editor.Buffer
	initialized, init_failure := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(9),
		"hello odra",
		test_allocators(),
	)
	testing.expect(t, initialized)
	testing.expect_value(t, init_failure.code, editor.Failure_Code.None)
	if !initialized {
		hosting.runtime_shutdown(&racket_runtime)
		return
	}

	registry: bridge.Buffer_Capability_Registry
	registry_ready, _ := bridge.buffer_capability_registry_init(&registry, bridge.Registry_ID(7))
	testing.expect(t, registry_ready)
	transaction_registry: bridge.Transaction_Capability_Registry
	transaction_registry_ready, _ := bridge.transaction_capability_registry_init(
		&transaction_registry,
		bridge.Registry_ID(8),
	)
	testing.expect(t, transaction_registry_ready)
	capability, identity, acquired, _ := bridge.buffer_capability_acquire(&registry, &buffer)
	testing.expect(t, acquired)

	if COMMAND_TEST_SCENARIO == 0 {
		verify_local_rejections(t, &racket_runtime, &registry, capability, identity)
		verify_stale_and_closed_capabilities(t, &racket_runtime, &registry, &buffer, identity)
		verify_racket_history_policy_configuration(t, &racket_runtime)
		verify_racket_display_policy_configuration(t, &racket_runtime)
		verify_racket_layout_capability(t, &racket_runtime)
		verify_racket_ui_role_capability(t, &racket_runtime)
		verify_racket_theme_capability(t, &racket_runtime)
		verify_racket_result_provider(t, &racket_runtime)
		verify_racket_status_bar_provider(t, &racket_runtime)
		verify_racket_terminal_capability(t, &racket_runtime)
		verify_structured_terminal_integration(t)
	}

	result: Command_Result
	executed := false
	command_failure: Failure_Context
	if COMMAND_TEST_SCENARIO <= 4 {
		result, executed, command_failure = buffer_command_run(
			&racket_runtime,
			&registry,
			capability,
			identity.buffer_id,
			identity.revision,
			context.allocator,
			context.temp_allocator,
			edit_transaction.Transaction_ID(1),
			edit_transaction.Undo_Unit_ID(1),
		)
	}

	expected_revision := editor.Revision(0)
	expected_text := "hello odra"
	switch COMMAND_TEST_SCENARIO {
	case 0, 4:
		testing.expectf(t, executed, "command failed with %v", command_failure.code)
		testing.expect_value(t, result.publication.commit.base_revision, editor.Revision(0))
		testing.expect_value(t, result.publication.commit.result_revision, editor.Revision(1))
		testing.expect_value(t, result.inspected_bytes, u64(4))
		testing.expect_value(t, result.replacement_bytes, u64(4))
		expected_revision = 1
		expected_text = "hello ODRA"
	case 1:
		testing.expect(t, !executed)
		testing.expect_value(t, command_failure.code, Failure_Code.Racket_Exception)
		testing.expect_value(t, command_failure.hosting_code, hosting.Failure_Code.Racket_Exception)
		testing.expect(t, len(command_failure.diagnostic) > 0)
	case 2:
		testing.expect(t, !executed)
		testing.expect_value(t, command_failure.code, Failure_Code.Wrong_Result)
	case 3:
		testing.expect(t, !executed)
		testing.expect_value(t, command_failure.code, Failure_Code.Malformed_Text)
		testing.expect_value(t, command_failure.editor_code, editor.Failure_Code.Malformed_UTF8)
	case 5, 6:
		// These scenarios exercise only the current-line command below.
	case:
		testing.expect(t, false)
	}
	expect_capability_text(
		t,
		&registry,
		capability,
		identity.buffer_id,
		expected_revision,
		expected_text,
	)
	command_result_close(&result)
	view_registry: editor_view.Registry
	view_registry_ready, _ := editor_view.registry_init(
		&view_registry,
		editor_view.Registry_ID(71),
		context.allocator,
	)
	view_handle, view_ready, _ := editor_view.create(&view_registry, &buffer)
	command_definitions := test_built_in_command_definitions()
	command_registry: interaction.Command_Registry
	commands_ready, _ := interaction.command_registry_init(
		&command_registry,
		interaction.Registry_Generation(19),
		command_definitions[:],
		context.allocator,
	)
	uppercase, uppercase_ready, _ := interaction.command_lookup(
		&command_registry,
		"uppercase-current-line",
	)
	undo, undo_ready, _ := interaction.command_lookup(&command_registry, "undo")
	testing.expect(
		t,
		view_registry_ready && view_ready && commands_ready && uppercase_ready && undo_ready,
	)
	if view_registry_ready && view_ready && commands_ready && uppercase_ready && undo_ready {
		if COMMAND_TEST_SCENARIO == 0 {
			verify_racket_keymap_activation(t, &racket_runtime, &command_registry, undo)
		}
		uppercase_request := Racket_Context {
			runtime = &racket_runtime,
			capabilities = &registry,
			transaction_capabilities = &transaction_registry,
			command_registry = &command_registry,
			command = uppercase,
			buffer = &buffer,
			view_registry = &view_registry,
			view = view_handle,
			profile = display.terminal_unicode17_profile(),
			constraints = display.Viewport_Constraints {
				width_cells = 80,
				height_rows = 24,
			},
			temporary_allocator = context.temp_allocator,
			persistent_allocator = context.allocator,
			transaction_id = edit_transaction.Transaction_ID(2),
			undo_unit_id = edit_transaction.Undo_Unit_ID(2),
		}
		if COMMAND_TEST_SCENARIO == 0 {
			verify_racket_local_rejections(t, uppercase_request)
		}
		uppercase_result, uppercase_ok, uppercase_failure := racket_command_execute(
			uppercase_request,
		)
		defer native_result_close(&uppercase_result)
		switch COMMAND_TEST_SCENARIO {
		case 0, 4:
			testing.expectf(t, uppercase_ok, "uppercase failed: %v", uppercase_failure.code)
			testing.expect_value(
				t,
				uppercase_result.completion,
				Native_Completion.Buffer_Committed,
			)
			expected_revision += 1
			expected_text = "HELLO ODRA"
		case 1:
			testing.expect(t, !uppercase_ok)
			testing.expect_value(t, uppercase_failure.code, Failure_Code.Racket_Exception)
		case 2, 5, 6:
			testing.expect(t, !uppercase_ok)
			testing.expect_value(t, uppercase_failure.code, Failure_Code.Wrong_Result)
		case 3:
			testing.expect(t, !uppercase_ok)
			testing.expect_value(t, uppercase_failure.code, Failure_Code.Malformed_Text)
		case:
			testing.expect(t, false)
		}
		expect_capability_text(
			t,
			&registry,
			capability,
			identity.buffer_id,
			expected_revision,
			expected_text,
		)
		if COMMAND_TEST_SCENARIO == 0 {
			verify_personal_command_execution(
				t,
				&racket_runtime,
				&registry,
				&transaction_registry,
			)
			verify_racket_line_cases(
				t,
				&racket_runtime,
				&registry,
				&transaction_registry,
				&command_registry,
				uppercase,
			)
			verify_composed_racket_transaction_fixtures(
				t,
				&racket_runtime,
				&transaction_registry,
			)
			verify_racket_transfer_facade(t, &racket_runtime)
			verify_racket_search_bridge(t, &racket_runtime)
			verify_racket_structural_bridge(t, &racket_runtime)
			verify_racket_structural_parity(t, &racket_runtime)
			verify_racket_buffer_session_facade(t, &racket_runtime)
		}
	}
	if view_ready {
		editor_view.close(&view_registry, &view_handle)
	}
	if view_registry_ready {
		editor_view.registry_close(&view_registry)
	}
	if commands_ready {
		interaction.command_registry_close(&command_registry)
	}
	transaction_registry_closed, transaction_registry_failure :=
		bridge.transaction_capability_registry_close(&transaction_registry)
	testing.expectf(
		t,
		transaction_registry_closed,
		"transaction registry close failed with %v",
		transaction_registry_failure.code,
	)
	if COMMAND_TEST_SCENARIO == 0 {
		verify_dir_root_commands(t)
		verify_project_directory_opening(t, &racket_runtime)
		verify_explicit_dir_promotion(t, &racket_runtime)
		verify_promotion_suppression_round_trip(t, &racket_runtime)
		verify_workspace_commands(t, &racket_runtime)
		verify_named_location_commands(t, &racket_runtime)
		verify_named_slot_commands(t, &racket_runtime)
	}

	// Racket may still retain the scalar wrapper, but live Odin capabilities block shutdown.
	runtime_stopped, stop_failure := buffer_command_shutdown(&racket_runtime, &registry)
	testing.expect(t, !runtime_stopped)
	testing.expect_value(t, stop_failure.bridge_code, bridge.Failure_Code.Retained_Capabilities)
	testing.expect_value(t, hosting.runtime_state(&racket_runtime), hosting.State.Ready)
	expect_capability_text(
		t,
		&registry,
		capability,
		identity.buffer_id,
		expected_revision,
		expected_text,
	)

	released, _ := bridge.buffer_capability_release(&registry, &capability)
	testing.expect(t, released)
	runtime_stopped, stop_failure = buffer_command_shutdown(&racket_runtime, &registry)
	testing.expectf(t, runtime_stopped, "runtime shutdown failed: %s", stop_failure.diagnostic)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, buffer_closed)
}

@(private)
verify_personal_command_execution :: proc(
	t: ^testing.T,
	racket_runtime: ^hosting.Runtime,
	capabilities: ^bridge.Buffer_Capability_Registry,
	transaction_capabilities: ^bridge.Transaction_Capability_Registry,
) {
	configuration_root, root_error := os.get_absolute_path(
		"tests/personal_commands/runtime/config/odra",
		context.allocator,
	)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer delete(configuration_root)
	startup: [hosting.MAX_PERSONAL_CONFIGURATION_STARTUP_BYTES]u8
	startup_length, configured, configuration_failure := hosting.runtime_personal_configuration_startup(
		racket_runtime,
		configuration_root,
		startup[:],
	)
	testing.expectf(
		t,
		configured,
		"personal configuration failed: %s",
		configuration_failure.diagnostic,
	)
	if !configured do return
	testing.expect(t, startup_length >= 72)
	confirmed_generation := u64(0)
	if startup_length >= 72 {
		confirmed_generation = read_little_u64(startup[:], 24)
		diagnostic_length := int(read_little_u64(startup[:], 40))
		diagnostic := ""
		if diagnostic_length > 0 && 72 + diagnostic_length <= int(startup_length) {
			diagnostic = string(startup[72:72 + diagnostic_length])
		}
		testing.expectf(
			t,
			read_little_u64(startup[:], 8) == 1,
			"personal startup rejected: %s",
			diagnostic,
		)
		testing.expect_value(t, read_little_u64(startup[:], 16), u64(2))
	}
	activated, activation_failure := hosting.runtime_personal_generation_transition(
		racket_runtime,
		1,
		confirmed_generation,
	)
	testing.expectf(
		t,
		activated,
		"personal generation activation failed: %s",
		activation_failure.diagnostic,
	)
	if !activated do return

	candidate, loaded, catalog_failure := hosting.runtime_load_command_catalog(
		racket_runtime,
		interaction.Registry_Generation(confirmed_generation),
		context.allocator,
	)
	testing.expectf(t, loaded, "personal catalog failed: %s", catalog_failure.diagnostic)
	if !loaded do return
	defer hosting.command_catalog_candidate_close(&candidate)
	definitions, definitions_ok := hosting.command_catalog_candidate_definitions(&candidate)
	testing.expect(t, definitions_ok)
	if !definitions_ok do return
	testing.expect_value(t, len(definitions), 16)
	if len(definitions) == 16 {
		testing.expect_value(t, definitions[7].name, "personal-uppercase-current-line")
	}

	registry: interaction.Command_Registry
	registry_ready, registry_failure := built_in_command_registry_init(
		&registry,
		interaction.Registry_Generation(confirmed_generation),
		context.allocator,
		definitions,
	)
	testing.expectf(t, registry_ready, "personal registry failed: %v", registry_failure.code)
	if !registry_ready do return
	defer interaction.command_registry_close(&registry)
	personal, found, lookup_failure := interaction.command_lookup(
		&registry,
		"personal-uppercase-current-line",
	)
	testing.expectf(t, found, "personal command lookup failed: %v", lookup_failure.code)
	if !found do return

	buffer: editor.Buffer
	buffer_ready, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(811),
		"hello αsk",
		test_allocators(),
	)
	testing.expect(t, buffer_ready)
	if !buffer_ready do return
	defer editor.buffer_close(&buffer)
	views: editor_view.Registry
	views_ready, _ := editor_view.registry_init(
		&views,
		editor_view.Registry_ID(811),
		context.allocator,
	)
	testing.expect(t, views_ready)
	if !views_ready do return
	defer editor_view.registry_close(&views)
	view, view_ready, _ := editor_view.create(&views, &buffer)
	testing.expect(t, view_ready)
	if !view_ready do return
	defer editor_view.close(&views, &view)

	result, executed, execution_failure := racket_command_execute(Racket_Context {
		runtime = racket_runtime,
		capabilities = capabilities,
		transaction_capabilities = transaction_capabilities,
		command_registry = &registry,
		command = personal,
		buffer = &buffer,
		view_registry = &views,
		view = view,
		profile = display.terminal_unicode17_profile(),
		constraints = {width_cells = 80, height_rows = 24},
		temporary_allocator = context.temp_allocator,
		persistent_allocator = context.allocator,
		transaction_id = edit_transaction.Transaction_ID(811),
		undo_unit_id = edit_transaction.Undo_Unit_ID(811),
	})
	defer native_result_close(&result)
	testing.expectf(
		t,
		executed,
		"personal command failed: %v/%v %s",
		execution_failure.code,
		execution_failure.hosting_code,
		execution_failure.diagnostic,
	)
	if executed {
		testing.expect_value(t, result.completion, Native_Completion.Buffer_Committed)
		testing.expect_value(t, result.commit.undo_unit_id, edit_transaction.Undo_Unit_ID(811))
		expect_buffer_and_view(t, &buffer, &views, view, 1, 10, "HELLO ΑSK")
	}

	request := Racket_Context {
		runtime = racket_runtime,
		capabilities = capabilities,
		transaction_capabilities = transaction_capabilities,
		command_registry = &registry,
		buffer = &buffer,
		view_registry = &views,
		view = view,
		profile = display.terminal_unicode17_profile(),
		constraints = {width_cells = 80, height_rows = 24},
		temporary_allocator = context.temp_allocator,
		persistent_allocator = context.allocator,
	}
	prepared_document: document.Prepared_Open
	prepared, prepare_failure := document.open_prepare(
		&prepared_document,
		document.Open_Request {
			document_id = document.Document_ID(811),
			buffer_id = editor.Buffer_ID(811),
			has_path = true,
			path = "/tmp/personal-context.org",
			encoding = .UTF8,
		},
		document.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, prepared, "document preparation failed: %v", prepare_failure.code)
	document_owner: document.Document
	if prepared {
		opened, open_failure := document.prepared_open_commit(
			&prepared_document,
			&document_owner,
			editor.Revision(1),
		)
		testing.expectf(t, opened, "document open failed: %v", open_failure.code)
		if opened {
			defer document.document_close(&document_owner)
			start, start_ok, _ := editor.buffer_position(&buffer, editor.Byte_Offset(6))
			end, end_ok, _ := editor.buffer_position(&buffer, editor.Byte_Offset(10))
			selected, select_failure := editor_view.select_range(&views, view, start, end, 4)
			testing.expectf(
				t,
				start_ok && end_ok && selected,
				"context selection failed: %v",
				select_failure.code,
			)
			context_command, context_found, _ := interaction.command_lookup(
				&registry,
				"personal-report-context",
			)
			testing.expect(t, context_found)
			if start_ok && end_ok && selected && context_found {
				request.command = context_command
				request.document = &document_owner
				request.transaction_id = 812
				request.undo_unit_id = 812
				context_result, context_ok, context_failure := racket_command_execute(request)
				testing.expectf(t, context_ok, "personal context failed: %v", context_failure.code)
				if context_ok {
					testing.expect_value(t, context_result.completion, Native_Completion.No_Op)
					testing.expect_value(
						t,
						hosting.runtime_diagnostic(racket_runtime),
						"/tmp/personal-context.org|10|ΑSK|",
					)
				}
				native_result_close(&context_result)
				request.personal_selection = "analytical-engine"
				request.transaction_id = 813
				request.undo_unit_id = 813
				selection_result, selection_ok, selection_failure := racket_command_execute(request)
				testing.expectf(t, selection_ok, "personal selection failed: %v", selection_failure.code)
				if selection_ok {
					testing.expect_value(
						t,
						hosting.runtime_diagnostic(racket_runtime),
						"/tmp/personal-context.org|10|ΑSK|analytical-engine",
					)
				}
				native_result_close(&selection_result)
				request.personal_selection = ""
			}
		}
	}

	no_op, no_op_found, _ := interaction.command_lookup(&registry, "personal-no-op")
	testing.expect(t, no_op_found)
	if no_op_found {
		request.command = no_op
		request.transaction_id = 812
		request.undo_unit_id = 812
		no_op_result, no_op_ok, no_op_failure := racket_command_execute(request)
		testing.expectf(t, no_op_ok, "personal no-op failed: %v", no_op_failure.code)
		testing.expect_value(t, no_op_result.completion, Native_Completion.No_Op)
		native_result_close(&no_op_result)
	}

	candidates, candidates_found, _ := interaction.command_lookup(&registry, "personal-candidates")
	testing.expect(t, candidates_found)
	if candidates_found {
		request.command = candidates
		request.transaction_id = 813
		request.undo_unit_id = 813
		candidate_result, candidate_ok, candidate_failure := racket_command_execute(request)
		testing.expectf(t, candidate_ok, "personal candidates failed: %v", candidate_failure.code)
		testing.expect(t, len(candidate_result.personal_result) > 0)
		if len(candidate_result.personal_result) > 0 {
			source, decoded, decode_failure := interaction.personal_candidate_source_decode(
				candidate_result.personal_result,
				1,
			)
			testing.expectf(t, decoded, "personal candidates did not decode: %v", decode_failure.code)
			if decoded {
				testing.expect_value(t, source.initial_query, "Ada")
				testing.expect_value(t, len(source.targets), 1)
				if len(source.targets) == 1 {
					testing.expect_value(t, source.targets[0].identity, "ada")
					testing.expect_value(t, source.targets[0].document_path, "/tmp/ada.org")
				}
				interaction.personal_candidate_source_close(&source)
			}
		}
		native_result_close(&candidate_result)
	}

	rejected, rejected_found, _ := interaction.command_lookup(&registry, "personal-reject")
	testing.expect(t, rejected_found)
	if rejected_found {
		request.command = rejected
		request.transaction_id = 813
		request.undo_unit_id = 813
		_, rejected_ok, rejected_failure := racket_command_execute(request)
		testing.expect(t, !rejected_ok)
		testing.expect_value(t, rejected_failure.code, Failure_Code.Command_Rejected)
		testing.expect_value(t, rejected_failure.hosting_code, hosting.Failure_Code.Command_Rejection)
	}

	failing_names := [?]string {
		"personal-exception",
		"personal-invalid-result",
		"personal-wrong-effect",
	}
	for name, index in failing_names {
		failed, failed_found, _ := interaction.command_lookup(&registry, name)
		testing.expect(t, failed_found)
		if !failed_found do continue
		request.command = failed
		request.transaction_id = edit_transaction.Transaction_ID(814 + index)
		request.undo_unit_id = edit_transaction.Undo_Unit_ID(814 + index)
		_, failed_ok, failed_failure := racket_command_execute(request)
		testing.expect(t, !failed_ok)
		testing.expect_value(t, failed_failure.code, Failure_Code.Racket_Exception)
	}

	partial, partial_found, _ := interaction.command_lookup(&registry, "personal-partial-reject")
	testing.expect(t, partial_found)
	if partial_found {
		request.command = partial
		request.transaction_id = 817
		request.undo_unit_id = 817
		_, partial_ok, partial_failure := racket_command_execute(request)
		testing.expect(t, !partial_ok)
		testing.expect_value(t, partial_failure.code, Failure_Code.Command_Rejected)
	}

	request.command = personal
	request.transaction_id = 818
	request.undo_unit_id = 818
	request.cancelled = true
	_, cancelled_ok, cancelled_failure := racket_command_execute(request)
	testing.expect(t, !cancelled_ok)
	testing.expect_value(t, cancelled_failure.code, Failure_Code.Cancelled)
	expect_buffer_and_view(t, &buffer, &views, view, 1, 10, "HELLO ΑSK")
}

@(private)
verify_racket_structural_bridge :: proc(t: ^testing.T, racket_runtime: ^hosting.Runtime) {
	contents := "package demo\nmain :: proc() {\n    alpha := 1\n}\n"
	fixture: Structural_Editor_Test_Fixture
	if !structural_editor_test_open(t, &fixture, 832, contents) do return
	defer structural_editor_test_close(&fixture)
	definitions := native_command_definitions()
	registry: interaction.Command_Registry
	ready, failure := interaction.command_registry_init(
		&registry,
		interaction.Registry_Generation(33),
		definitions[:],
		context.allocator,
	)
	testing.expectf(t, ready, "structural registry setup failed with %v", failure.code)
	if !ready do return
	defer interaction.command_registry_close(&registry)
	forward, found, _ := interaction.command_lookup(&registry, "structural-forward")
	testing.expect(t, found)
	if !found do return
	state: Structural_Capability_State
	capability := Structural_Capability_Context {
		editor_session_id = Editor_Session_ID(42),
		access = {.Inspect, .Forward, .Backward, .Up, .Down, .Select, .Indent},
		capability_generation = 8,
		editor = fixture.ctx,
		state = &state,
	}
	capability.editor.native.registry = &registry
	capability.editor.native.command = forward

	inspected, inspection_ok, inspection_failure := racket_structural_turn(
		racket_runtime,
		capability,
		16,
	)
	testing.expectf(
		t,
		inspection_ok,
		"programmable structural inspection failed with %v/%v",
		inspection_failure.structural_capability_code,
		inspection_failure.structural_code,
	)
	if inspection_ok {
		testing.expect_value(t, inspected.completion, Native_Completion.No_Op)
	}
	moved, move_ok, move_failure := racket_structural_turn(racket_runtime, capability, 10)
	testing.expectf(
		t,
		move_ok,
		"programmable structural movement failed with %v/%v",
		move_failure.structural_capability_code,
		move_failure.structural_code,
	)
	if move_ok {
		testing.expect_value(t, moved.completion, Native_Completion.View_Changed)
	}
	restricted := capability
	restricted.access = {.Inspect}
	_, allowed, access_failure := racket_structural_turn(racket_runtime, restricted, 10)
	testing.expect(t, !allowed)
	testing.expect_value(
		t,
		access_failure.structural_capability_code,
		Structural_Capability_Failure_Code.Permission_Denied,
	)
	containment_scenarios := [?]struct{name: string, scenario: i32} {
		{"malformed-request", 17},
		{"invalid-selector", 18},
		{"oversized-output", 19},
	}
	for test_case in containment_scenarios {
		_, contained, containment_failure := racket_structural_turn(
			racket_runtime,
			capability,
			test_case.scenario,
		)
		testing.expectf(t, !contained, "%s structural scenario escaped", test_case.name)
		testing.expectf(t, containment_failure.code == .Racket_Exception, "%s structural scenario returned the wrong failure", test_case.name)
	}
	_, stale_ok, stale_failure := racket_structural_turn(racket_runtime, capability, 20)
	testing.expect(t, !stale_ok)
	testing.expect_value(
		t,
		stale_failure.structural_capability_code,
		Structural_Capability_Failure_Code.Stale_Capability,
	)
	cancelled := capability
	cancelled.editor.native.cancelled = true
	_, cancelled_ok, cancelled_failure := racket_structural_turn(
		racket_runtime,
		cancelled,
		16,
	)
	testing.expect(t, !cancelled_ok)
	testing.expect_value(t, cancelled_failure.code, Failure_Code.Cancelled)
	_, reusable, reuse_failure := racket_structural_turn(racket_runtime, capability, 16)
	testing.expectf(t, reusable, "structural cleanup failed with %v", reuse_failure.code)
}

@(private)
Structural_Parity_Case :: struct {
	name:      string,
	operation: language.Structural_Operation,
	scenario:  i32,
}

@(private)
verify_racket_structural_parity :: proc(t: ^testing.T, racket_runtime: ^hosting.Runtime) {
	contents := "package demo\nmain :: proc() {\nvalue := 1\nif value > 0 {\nvalue += 1\n}\n}\n"
	definitions := native_command_definitions()
	registry: interaction.Command_Registry
	ready, failure := interaction.command_registry_init(
		&registry,
		interaction.Registry_Generation(34),
		definitions[:],
		context.allocator,
	)
	testing.expectf(t, ready, "structural parity registry failed with %v", failure.code)
	if !ready do return
	defer interaction.command_registry_close(&registry)
	forward, found, _ := interaction.command_lookup(&registry, "structural-forward")
	testing.expect(t, found)
	if !found do return
	cases := [?]Structural_Parity_Case {
		{name = "forward", operation = .Forward, scenario = 10},
		{name = "backward", operation = .Backward, scenario = 11},
		{name = "up", operation = .Up, scenario = 12},
		{name = "down", operation = .Down, scenario = 13},
		{name = "select", operation = .Select, scenario = 14},
		{name = "indent", operation = .Indent, scenario = 15},
	}
	for test_case in cases {
		native_fixture: Structural_Editor_Test_Fixture
		racket_fixture: Structural_Editor_Test_Fixture
		if !structural_editor_test_open(t, &native_fixture, 833, contents) do continue
		if !structural_editor_test_open(t, &racket_fixture, 833, contents) {
			structural_editor_test_close(&native_fixture)
			continue
		}
		structural_parity_prepare(&native_fixture, test_case.operation, contents)
		structural_parity_prepare(&racket_fixture, test_case.operation, contents)
		native_state: Structural_Capability_State
		racket_state: Structural_Capability_State
		native_capability := structural_parity_context(
			&native_fixture,
			&registry,
			forward,
			&native_state,
		)
		racket_capability := structural_parity_context(
			&racket_fixture,
			&registry,
			forward,
			&racket_state,
		)
		scope, scoped, _ := structural_capability_scope(native_capability)
		direct, direct_ok, direct_failure := structural_capability_invoke(
			native_capability,
			scope,
			test_case.operation,
		)
		programmed, programmed_ok, programmed_failure := racket_structural_turn(
			racket_runtime,
			racket_capability,
			test_case.scenario,
		)
		testing.expectf(t, scoped, "%s native scope failed", test_case.name)
		testing.expectf(
			t,
			direct_ok,
			"%s native command failed with %v/%v",
			test_case.name,
			direct_failure.structural_code,
			direct_failure.language_code,
		)
		testing.expectf(
			t,
			programmed_ok,
			"%s Racket command failed with %v/%v",
			test_case.name,
			programmed_failure.structural_code,
			programmed_failure.language_code,
		)
		if direct_ok && programmed_ok {
			testing.expectf(t, programmed.outcome == direct.outcome, "%s outcomes diverged", test_case.name)
			native_text := structural_editor_test_text(&native_fixture.buffer)
			racket_text := structural_editor_test_text(&racket_fixture.buffer)
			testing.expectf(t, racket_text == native_text, "%s text results diverged", test_case.name)
			delete(native_text, context.temp_allocator)
			delete(racket_text, context.temp_allocator)
		}
		if direct_ok do structural_capability_result_close(&direct)
		structural_editor_test_close(&racket_fixture)
		structural_editor_test_close(&native_fixture)
	}
}

@(private)
structural_parity_context :: proc(
	fixture: ^Structural_Editor_Test_Fixture,
	registry: ^interaction.Command_Registry,
	command: interaction.Command_Handle,
	state: ^Structural_Capability_State,
) -> Structural_Capability_Context {
	result := Structural_Capability_Context {
		editor_session_id = Editor_Session_ID(43),
		access = {.Inspect, .Forward, .Backward, .Up, .Down, .Select, .Indent},
		capability_generation = 9,
		editor = fixture.ctx,
		state = state,
	}
	result.editor.native.registry = registry
	result.editor.native.command = command
	return result
}

@(private)
structural_parity_prepare :: proc(
	fixture: ^Structural_Editor_Test_Fixture,
	operation: language.Structural_Operation,
	contents: string,
) {
	if operation == .Indent {
		start, _, _ := editor.buffer_position(&fixture.buffer, 0)
		end, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(len(contents)))
		editor_view.select_range(&fixture.views, fixture.view, start, end, 0)
		return
	}
	offset := editor.Byte_Offset(0)
	if operation == .Backward {
		offset = editor.Byte_Offset(len(contents))
	} else if operation == .Up || operation == .Select {
		offset = editor.Byte_Offset(strings.index(contents, "value := 1"))
	}
	position, _, _ := editor.buffer_position(&fixture.buffer, offset)
	editor_view.move_point(&fixture.views, fixture.view, position, 0, .Deactivate)
}

@(private)
verify_racket_transfer_facade :: proc(t: ^testing.T, racket_runtime: ^hosting.Runtime) {
	temporary_tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&temporary_tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&temporary_tracking)
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "alpha", context.allocator) {
		return
	}
	execute_named(&fixture, "set-mark-command")
	for _ in 0 ..< 5 {
		execute_named(&fixture, "cursor-next-grapheme")
	}
	test_ring_admit(t, &fixture.kill_ring, "seed")
	transfer := Transfer_Capability_Context {
		editor_session_id = Editor_Session_ID(88),
		access = {
			.Region_Inspection,
			.Ring_Inspection,
			.Entry_Text,
			.Semantic_Invocation,
		},
		native = native_request(&fixture, {}),
	}
	transfer.native.history_store = &fixture.history
	transfer.native.kill_ring = &fixture.kill_ring
	transfer.native.temporary_allocator = mem.tracking_allocator(&temporary_tracking)
	transfer.native.kill_sequence_id = 1
	transfer.native.event_sequence = u64(transfer.native.transaction_id)
	transfer.native.yank_context = &fixture.yank_context

	inspected, inspection_ok, inspection_failure := racket_transfer_turn(
		racket_runtime,
		transfer,
		6,
	)
	testing.expectf(t, inspection_ok, "transfer inspection failed with %v", inspection_failure.code)
	testing.expect_value(t, inspected.completion, Native_Completion.No_Op)

	copied, copy_ok, copy_failure := racket_transfer_turn(racket_runtime, transfer, 7)
	testing.expectf(t, copy_ok, "transfer composition failed with %v", copy_failure.code)
	if copy_ok {
		testing.expect_value(t, copied.completion, Native_Completion.Text_Retained)
		testing.expect(t, copied.scope.ring_generation != inspected.scope.ring_generation)
	}

	deactivated, deactivate_ok, deactivate_failure := racket_transfer_turn(
		racket_runtime,
		transfer,
		8,
	)
	testing.expectf(t, deactivate_ok, "transfer no-op composition failed with %v", deactivate_failure.code)
	if deactivate_ok {
		testing.expect_value(t, deactivated.completion, Native_Completion.No_Op)
	}

	_, rejected, rejection := racket_transfer_turn(racket_runtime, transfer, 9)
	testing.expect(t, !rejected)
	testing.expect_value(t, rejection.transfer_code, Transfer_Failure_Code.Command_Not_Allowed)

	_, reloaded, reload_failure := racket_transfer_turn(racket_runtime, transfer, 6)
	testing.expectf(t, reloaded, "reloaded transfer facade failed with %v", reload_failure.code)

	cancelled := transfer
	cancelled.native.cancelled = true
	_, cancellation_ok, cancellation_failure := racket_transfer_turn(
		racket_runtime,
		cancelled,
		6,
	)
	testing.expect(t, !cancellation_ok)
	testing.expect_value(t, cancellation_failure.code, Failure_Code.Cancelled)

	region_only := transfer
	region_only.access = {.Region_Inspection}
	_, authorized, authorization_failure := racket_transfer_turn(
		racket_runtime,
		region_only,
		6,
	)
	testing.expect(t, !authorized)
	testing.expect_value(
		t,
		authorization_failure.transfer_code,
		Transfer_Failure_Code.Permission_Denied,
	)

	native_fixture_close(t, &fixture)
	testing.expect_value(t, temporary_tracking.current_memory_allocated, i64(0))
}

@(private)
verify_racket_search_bridge :: proc(t: ^testing.T, racket_runtime: ^hosting.Runtime) {
	temporary_tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&temporary_tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&temporary_tracking)
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "one two one", context.allocator) {
		return
	}
	search_control := search_capability_test_context(&fixture, {
		.Policy_Inspection,
		.Session_Inspection,
		.Semantic_Invocation,
	})
	search_control.native.temporary_allocator = mem.tracking_allocator(&temporary_tracking)

	scoped, scope_ok, scope_failure := racket_search_turn(racket_runtime, search_control, 0)
	testing.expectf(t, scope_ok, "search scope bridge failed with %v", scope_failure.code)
	if scope_ok {
		testing.expect_value(t, scoped.scope.session_kind, Search_Session_Kind.None)
	}
	_, gc_ok, gc_failure := racket_search_turn(racket_runtime, search_control, 2)
	testing.expectf(t, gc_ok, "search forced-GC bridge failed with %v", gc_failure.code)
	_, inspection_ok, inspection_failure := racket_search_turn(racket_runtime, search_control, 6)
	testing.expectf(t, inspection_ok, "search copied inspection failed with %v", inspection_failure.code)
	_, configured_ok, configured_failure := racket_search_turn(
		racket_runtime,
		search_control,
		15,
	)
	testing.expectf(
		t,
		configured_ok,
		"configured search policy failed with %v",
		configured_failure.code,
	)

	invoked, invoke_ok, invoke_failure := racket_search_turn(racket_runtime, search_control, 7)
	testing.expectf(t, invoke_ok, "search command bridge failed with %v", invoke_failure.code)
	if invoke_ok {
		testing.expect_value(t, invoked.completion, Native_Completion.View_Changed)
		testing.expect_value(t, invoked.scope.session_kind, Search_Session_Kind.Incremental)
	}
	_, active_inspection_ok, active_inspection_failure := racket_search_turn(
		racket_runtime,
		search_control,
		6,
	)
	testing.expectf(
		t,
		active_inspection_ok,
		"active search inspection failed with %v",
		active_inspection_failure.code,
	)
	_, copied_lifetime_ok, copied_lifetime_failure := racket_search_turn(
		racket_runtime,
		search_control,
		11,
	)
	testing.expectf(
		t,
		copied_lifetime_ok,
		"copied search lifetime failed with %v",
		copied_lifetime_failure.code,
	)
	_, exception_ok, exception_failure := racket_search_turn(racket_runtime, search_control, 4)
	testing.expect(t, !exception_ok)
	testing.expect_value(t, exception_failure.code, Failure_Code.Racket_Exception)
	containment_scenarios := [?]struct{name: string, scenario: i32} {
		{"escaped-context", 1},
		{"continuation-escape", 5},
		{"excessive-occurrences", 8},
		{"oversized-pattern", 12},
	}
	for test_case in containment_scenarios {
		_, contained, containment_failure := racket_search_turn(
			racket_runtime,
			search_control,
			test_case.scenario,
		)
		testing.expectf(t, !contained, "%s search scenario was not contained", test_case.name)
		testing.expectf(
			t,
			containment_failure.code == .Racket_Exception,
			"%s search scenario returned %v",
			test_case.name,
			containment_failure.code,
		)
	}
	_, cancelled, cancellation_failure := racket_search_turn(racket_runtime, search_control, 9)
	testing.expect(t, !cancelled)
	testing.expect_value(t, cancellation_failure.code, Failure_Code.Cancelled)
	_, malformed, malformed_failure := racket_search_turn(racket_runtime, search_control, 13)
	testing.expect(t, !malformed)
	testing.expect_value(t, malformed_failure.code, Failure_Code.Invalid_Request)
	_, reusable, reuse_failure := racket_search_turn(racket_runtime, search_control, 6)
	testing.expectf(t, reusable, "search bridge cleanup failed with %v", reuse_failure.code)

	accepted, _ := incremental_search_accept(&fixture.view_registry, fixture.view)
	testing.expect(t, accepted)
	_, stale, stale_failure := racket_search_turn(racket_runtime, search_control, 14)
	testing.expect(t, !stale)
	testing.expect_value(t, stale_failure.code, Failure_Code.Search_Failure)
	testing.expect_value(t, stale_failure.search_code, search.Failure_Code.Invalid_Scope)

	replaced, replace_ok, replace_failure := racket_search_turn(
		racket_runtime,
		search_control,
		10,
	)
	testing.expectf(t, replace_ok, "nested search replacement failed with %v", replace_failure.code)
	if replace_ok {
		testing.expect_value(t, replaced.completion, Native_Completion.Buffer_Committed)
		testing.expect_value(t, replaced.scope.revision, editor.Revision(1))
	}
	native_fixture_close(t, &fixture)
	testing.expect_value(t, temporary_tracking.current_memory_allocated, i64(0))
}

@(private)
verify_racket_history_policy_configuration :: proc(t: ^testing.T, racket_runtime: ^hosting.Runtime) {
	store: history.Store
	store_ready, _ := history.store_init(
		&store,
		history.Store_ID(81),
		editor.Buffer_ID(81),
		editor.Revision(0),
		history.Allocator_Set{
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, store_ready)
	if !store_ready {
		return
	}
	registry: bridge.History_Policy_Capability_Registry
	registry_ready, _ := bridge.history_policy_capability_registry_init(
		&registry,
		bridge.Registry_ID(81),
	)
	testing.expect(t, registry_ready)
	capability, initial, acquired, _ := bridge.history_policy_capability_acquire(
		&registry,
		&store,
	)
	testing.expect(t, acquired)
	if !acquired {
		bridge.history_policy_capability_registry_close(&registry)
		history.store_close(&store)
		return
	}

	first, applied, failure := history_policy_apply_racket_configuration(
		racket_runtime,
		&registry,
		capability,
	)
	switch HISTORY_POLICY_TEST_SCENARIO {
	case 1:
		testing.expect(t, !applied)
		testing.expect_value(t, failure.code, Failure_Code.Racket_Exception)
		testing.expect_value(t, failure.hosting_code, hosting.Failure_Code.Racket_Exception)
	case 2, 4:
		testing.expect(t, !applied)
		testing.expect_value(t, failure.code, Failure_Code.Wrong_Result)
	case 7:
		testing.expect(t, !applied)
		testing.expect_value(t, failure.code, Failure_Code.Capability_Failure)
		testing.expect_value(t, failure.bridge_code, bridge.Failure_Code.Policy_Range)
		testing.expect_value(t, failure.history_code, history.Failure_Code.Policy_Range)
		testing.expect_value(t, failure.policy_field, history.Policy_Field.Global_Retained_Bytes)
		testing.expect_value(t, failure.minimum, history.MIN_GLOBAL_RETAINED_BYTES)
		testing.expect_value(t, failure.limit, history.MAX_GLOBAL_RETAINED_BYTES)
		testing.expect_value(t, failure.actual, u64(0))
	case 8:
		testing.expect(t, !applied)
		testing.expect_value(t, failure.code, Failure_Code.Capability_Failure)
		testing.expect_value(t, failure.bridge_code, bridge.Failure_Code.Policy_Relationship)
		testing.expect_value(t, failure.history_code, history.Failure_Code.Policy_Relationship)
		testing.expect_value(t, failure.policy_field, history.Policy_Field.Buffer_Retained_Bytes)
	case 0, 3, 5, 6:
		testing.expectf(t, applied, "history policy configuration failed with %v", failure.code)
		if applied {
			testing.expect_value(t, first.previous_generation, history.Policy_Generation(1))
			testing.expect_value(t, first.policy_generation, history.Policy_Generation(2))
			first_snapshot, first_inspected, _ := bridge.history_policy_capability_inspect(
				&registry,
				capability,
			)
			testing.expect(t, first_inspected)
			expected_inspection_nodes := initial.policy.inspection_nodes
			if HISTORY_POLICY_TEST_SCENARIO == 5 {
				expected_inspection_nodes += 1
			} else if HISTORY_POLICY_TEST_SCENARIO == 6 {
				expected_inspection_nodes = history.MIN_INSPECTION_NODES
			}
			testing.expect_value(
				t,
				first_snapshot.policy.inspection_nodes,
				expected_inspection_nodes,
			)

			second, reapplied, reapply_failure := history_policy_apply_racket_configuration(
				racket_runtime,
				&registry,
				capability,
			)
			testing.expectf(
				t,
				reapplied,
				"reloaded history policy failed with %v",
				reapply_failure.code,
			)
			if reapplied {
				testing.expect_value(t, second.previous_generation, history.Policy_Generation(2))
				testing.expect_value(t, second.policy_generation, history.Policy_Generation(3))
				second_snapshot, second_inspected, _ := bridge.history_policy_capability_inspect(
					&registry,
					capability,
				)
				testing.expect(t, second_inspected)
				if HISTORY_POLICY_TEST_SCENARIO == 5 {
					expected_inspection_nodes += 1
				}
				testing.expect_value(
					t,
					second_snapshot.policy.inspection_nodes,
					expected_inspection_nodes,
				)
			}
		}
	case:
		testing.expect(t, false)
	}
	if !applied {
		preserved, preserved_ok, _ := bridge.history_policy_capability_inspect(
			&registry,
			capability,
		)
		testing.expect(t, preserved_ok)
		testing.expect_value(t, preserved, initial)
	}

	released, _ := bridge.history_policy_capability_release(&registry, &capability)
	testing.expect(t, released)
	closed, _ := bridge.history_policy_capability_registry_close(&registry)
	testing.expect(t, closed)
	store_closed, _ := history.store_close(&store)
	testing.expect(t, store_closed)
}

@(private)
verify_racket_display_policy_configuration :: proc(t: ^testing.T, racket_runtime: ^hosting.Runtime) {
	buffer: editor.Buffer
	buffer_ready, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(82),
		"display policy",
		test_allocators(),
	)
	views: editor_view.Registry
	views_ready, _ := editor_view.registry_init(
		&views,
		editor_view.Registry_ID(82),
		context.allocator,
	)
	root_view, root_ready, _ := editor_view.create(&views, &buffer)
	layout_registry: layout.Registry
	layout_ready, _ := layout.registry_init(
		&layout_registry,
		layout.Owner_ID(82),
		layout.Layout_ID(82),
		&views,
		root_view,
		layout.Geometry_Request{rows = 24, columns = 80},
		layout.DEFAULT_POLICY,
		context.allocator,
	)
	testing.expect(t, buffer_ready && views_ready && root_ready && layout_ready)
	if !buffer_ready || !views_ready || !root_ready || !layout_ready {
		return
	}

	registry: bridge.Display_Policy_Capability_Registry
	registry_ready, _ := bridge.display_policy_capability_registry_init(
		&registry,
		bridge.Registry_ID(82),
	)
	capability, initial, acquired, _ := bridge.display_policy_capability_acquire(
		&registry,
		&layout_registry,
	)
	testing.expect(t, registry_ready && acquired)
	if !registry_ready || !acquired {
		layout.registry_close(&layout_registry)
		editor_view.close(&views, &root_view)
		editor_view.registry_close(&views)
		editor.buffer_close(&buffer)
		return
	}

	configured, applied, failure := display_policy_apply_racket_configuration(
		racket_runtime,
		&registry,
		capability,
	)
	switch DISPLAY_POLICY_TEST_SCENARIO {
	case 1:
		testing.expect(t, !applied)
		testing.expect_value(t, failure.code, Failure_Code.Racket_Exception)
	case 2, 4:
		testing.expect(t, !applied)
		testing.expect_value(t, failure.code, Failure_Code.Wrong_Result)
	case 6, 7, 8:
		testing.expect(t, !applied)
		testing.expect_value(t, failure.code, Failure_Code.Capability_Failure)
		testing.expect_value(t, failure.bridge_code, bridge.Failure_Code.Malformed_Record)
		testing.expect_value(t, failure.layout_code, layout.Failure_Code.Invalid_Display_Policy)
	case 0, 3, 5:
		testing.expectf(t, applied, "display policy configuration failed with %v", failure.code)
		if applied {
			testing.expect_value(t, configured.generation, layout.Display_Policy_Generation(2))
			if DISPLAY_POLICY_TEST_SCENARIO == 5 {
				testing.expect_value(t, configured.policy.action_count, u16(2))
				testing.expect_value(t, configured.policy.actions[0].kind, layout.Display_Action_Kind.Reuse_Least_Recent)
				testing.expect_value(t, configured.policy.actions[1].kind, layout.Display_Action_Kind.Split_Right)
				testing.expect_value(t, configured.policy.split_height_threshold, i32(16))
				testing.expect_value(t, configured.policy.split_width_threshold, i32(60))
			} else {
				testing.expect_value(t, configured.policy, initial.policy)
			}
		}
	case:
		testing.expect(t, false)
	}
	if !applied {
		preserved, preserved_ok, _ := bridge.display_policy_capability_inspect(
			&registry,
			capability,
		)
		testing.expect(t, preserved_ok)
		testing.expect_value(t, preserved, initial)
	}

	released, _ := bridge.display_policy_capability_release(&registry, &capability)
	closed, _ := bridge.display_policy_capability_registry_close(&registry)
	layout_closed, _ := layout.registry_close(&layout_registry)
	root_closed, _ := editor_view.close(&views, &root_view)
	views_closed, _ := editor_view.registry_close(&views)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, released && closed && layout_closed && root_closed && views_closed && buffer_closed)
}

@(private)
verify_composed_racket_transaction_fixtures :: proc(
	t: ^testing.T,
	racket_runtime: ^hosting.Runtime,
	registry: ^bridge.Transaction_Capability_Registry,
) {
	scenarios := [?]struct {
		name: string,
		scenario: i32,
		expected: string,
		mutation_count: u64,
		bridge_failure: bridge.Failure_Code,
		transaction_failure: edit_transaction.Failure_Code,
		validation_failure: edit_transaction.Failure_Code,
	} {
		{name = "batch-edit", scenario = 7, expected = "XbcY", mutation_count = 2},
		{name = "inspect-between-splices", scenario = 8, expected = "XZbcd", mutation_count = 2},
		{name = "nested-insert", scenario = 9, expected = "()abcd", mutation_count = 2},
		{name = "handled-child-rejection", scenario = 10, expected = "RKabcd", mutation_count = 3},
		{name = "inspect-only", scenario = 11, expected = "abcd"},
		{name = "out-of-range", scenario = 12, expected = "abcd", transaction_failure = .Out_Of_Range},
		{name = "cancelled", scenario = 13, expected = "abcd", validation_failure = .Cancelled},
		{name = "malformed-batch", scenario = 14, expected = "abcd", bridge_failure = .Malformed_Record},
		{name = "batch-limit", scenario = 15, expected = "abcd"},
	}
	for fixture, fixture_index in scenarios {
		buffer: editor.Buffer
		buffer_ready, _ := editor.buffer_init(
			&buffer,
			editor.Buffer_ID(100 + fixture_index),
			"abcd",
			test_allocators(),
		)
		testing.expectf(t, buffer_ready, "%s buffer did not initialize", fixture.name)
		transaction: edit_transaction.Transaction
		transaction_ready, _ := edit_transaction.transaction_begin(
			&transaction,
			edit_transaction.Transaction_ID(100 + fixture_index),
			edit_transaction.Undo_Unit_ID(100 + fixture_index),
			&buffer,
			edit_transaction.Origin{kind = .Racket, descriptor = "fixture"},
			"composed-fixture",
			edit_transaction.Allocator_Set {
				persistent = context.allocator,
				temporary = context.temp_allocator,
			},
		)
		testing.expectf(t, transaction_ready, "%s transaction did not initialize", fixture.name)
		command_id := u64(1000 + fixture_index)
		capability, acquired, _ := bridge.transaction_capability_acquire(
			registry,
			&transaction,
			&buffer,
			command_id,
		)
		testing.expectf(t, acquired, "%s capability was not acquired", fixture.name)
		call := Racket_Transaction_Call {
			registry = registry,
			capability = capability,
			temporary_allocator = context.temp_allocator,
		}
		called, call_failure := hosting.runtime_transaction_command(
			racket_runtime,
			fixture.scenario,
			u64(capability),
			command_id,
			0,
			4,
			"uppercase-current-line",
			racket_transaction_callback,
			&call,
		)
		testing.expectf(t, called, "%s fixture failed: %s", fixture.name, call_failure.diagnostic)
		testing.expectf(t, call.mutations == fixture.mutation_count, "%s fixture returned the wrong mutation count", fixture.name)
		if fixture.bridge_failure != .None {
			testing.expectf(t, call.failure.code == fixture.bridge_failure, "%s fixture returned the wrong bridge failure", fixture.name)
		} else if fixture.transaction_failure != .None {
			testing.expectf(t, call.failure.transaction_code == fixture.transaction_failure, "%s fixture returned the wrong transaction failure", fixture.name)
		} else {
			testing.expectf(t, call.failure.code == .None, "%s fixture returned an unexpected bridge failure", fixture.name)
		}
		observed := make([]u8, len(fixture.expected), context.temp_allocator)
		_, inspected, _ := bridge.transaction_capability_inspect(
			registry,
			capability,
			command_id,
			0,
			u64(len(fixture.expected)),
			observed,
		)
		testing.expectf(t, inspected, "%s fixture could not be inspected", fixture.name)
		testing.expectf(t, string(observed) == fixture.expected, "%s fixture returned the wrong text", fixture.name)
		delete(observed, context.temp_allocator)
		released, _ := bridge.transaction_capability_release(registry, &capability)
		testing.expectf(t, released, "%s fixture capability was not released", fixture.name)
		if fixture.validation_failure != .None {
			validated, validation_failure := edit_transaction.transaction_validate(&transaction)
			testing.expectf(t, !validated, "%s fixture unexpectedly validated", fixture.name)
			testing.expectf(t, validation_failure.code == fixture.validation_failure, "%s fixture returned the wrong validation failure", fixture.name)
		} else if fixture.mutation_count != 0 && fixture.bridge_failure == .None &&
		          fixture.transaction_failure == .None {
			validated, _ := edit_transaction.transaction_validate(&transaction)
			_, committed, _ := edit_transaction.transaction_commit(&transaction)
			testing.expectf(t, validated && committed, "%s fixture did not commit", fixture.name)
		} else {
			edit_transaction.transaction_abort(&transaction)
		}
		edit_transaction.transaction_close(&transaction)
		editor.buffer_close(&buffer)
	}
}

@(private)
verify_racket_keymap_activation :: proc(
	t: ^testing.T,
	racket_runtime: ^hosting.Runtime,
	command_registry: ^interaction.Command_Registry,
	undo: interaction.Command_Handle,
) {
	profile_activation: interaction.Profile_Activation
	interaction.profile_activation_init(&profile_activation)
	profile_pending := interaction.Pending_State {
		snapshot_generation = interaction.Snapshot_Generation(99),
		stroke_count = 1,
	}
	profile_reloaded, profile_reload_failure := racket_profile_reload(
		racket_runtime,
		command_registry,
		&profile_activation,
		interaction.Active_Context {
			identity = interaction.Context_Handle {
				id = interaction.Context_ID(1),
				generation = interaction.Context_Generation(1),
			},
		},
		&profile_pending,
		context.allocator,
	)
	testing.expectf(
		t,
		profile_reloaded,
		"profile reload failed: %v",
		profile_reload_failure.interaction_code,
	)
	if profile_reloaded {
		active, active_ok := interaction.profile_activation_snapshot(&profile_activation)
		testing.expect(t, active_ok)
		if active_ok {
			stats, stats_ok, _ := interaction.snapshot_stats(active)
			testing.expect(t, stats_ok)
			testing.expect_value(t, stats.generation, interaction.Snapshot_Generation(1))
		}
		catalog, catalog_ok := interaction.profile_activation_catalog(&profile_activation)
		testing.expect(t, catalog_ok)
		expected_binding_count := u16(0)
		expected_map_count := u16(0)
		if catalog_ok {
			testing.expect_value(t, catalog.active_profile, interaction.Profile_ID(1))
			testing.expect_value(t, catalog.active_state, interaction.Interaction_State_ID(1))
			testing.expect_value(t, len(catalog.profiles), 2)
			if len(catalog.profiles) == 2 {
				testing.expect_value(t, catalog.profiles[0].name, "direct")
				testing.expect_value(t, catalog.profiles[1].name, "modal")
			}
			for catalog_profile in catalog.profiles {
				if catalog_profile.identity.id != catalog.active_profile do continue
				expected_map_count = u16(len(catalog_profile.maps) + 1)
				expected_binding_count = interaction.PROTECTED_RECOVERY_BINDING_COUNT
				for map_definition in catalog_profile.maps {
					expected_binding_count += u16(len(map_definition.bindings))
				}
			}
			if active_ok {
				stats, stats_ok, _ := interaction.snapshot_stats(active)
				testing.expect(t, stats_ok)
				if stats_ok {
					testing.expect_value(t, stats.binding_count, expected_binding_count)
					testing.expect_value(t, stats.map_count, expected_map_count)
				}
			}
		}
		profile, state, selected := interaction.profile_activation_selection(&profile_activation)
		testing.expect(t, selected)
		testing.expect_value(t, profile.id, interaction.Profile_ID(1))
		testing.expect_value(t, state.name, "direct-editing")
		surface, surface_ok := interaction.profile_activation_command_entry_surface(
			&profile_activation,
			"extended-command",
		)
		testing.expect(t, surface_ok)
		if surface_ok {
			testing.expect_value(t, surface.identity.id, interaction.Command_Entry_Surface_ID(1))
		}
		testing.expect_value(t, profile_pending.stroke_count, u8(0))
		profile_pending.stroke_count = 1
		profile_pending.snapshot_generation = interaction.Snapshot_Generation(1)
		reloaded_again, repeated_failure := racket_profile_reload(
			racket_runtime,
			command_registry,
			&profile_activation,
			interaction.Active_Context {
				identity = interaction.Context_Handle {
					id = interaction.Context_ID(1),
					generation = interaction.Context_Generation(1),
				},
			},
			&profile_pending,
			context.allocator,
		)
		testing.expect(t, !reloaded_again)
		testing.expect_value(
			t,
			repeated_failure.interaction_code,
			interaction.Failure_Code.Stale_Profile_Catalog,
		)
		testing.expect_value(t, profile_pending.stroke_count, u8(1))
		active, active_ok = interaction.profile_activation_snapshot(&profile_activation)
		if active_ok {
			stats, _, _ := interaction.snapshot_stats(active)
			testing.expect_value(t, stats.generation, interaction.Snapshot_Generation(1))
		}
	}
	snapshot, activated := interaction.profile_activation_snapshot(&profile_activation)
	testing.expect(t, activated)
	if activated {
		_, stats_ok, _ := interaction.snapshot_stats(snapshot)
		testing.expect(t, stats_ok)
		set_mark, set_mark_ok, _ := interaction.command_lookup(command_registry, "set-mark-command")
		exchange, exchange_ok, _ := interaction.command_lookup(
			command_registry,
			"exchange-point-and-mark",
		)
		keyboard_quit, keyboard_quit_ok, _ := interaction.command_lookup(
			command_registry,
			"keyboard-quit",
		)
		testing.expect(t, set_mark_ok && exchange_ok && keyboard_quit_ok)
		pending: interaction.Pending_State
		mark_resolution, mark_failure := interaction.resolve_input(
			snapshot,
			interaction.Registry_Generation(19),
			&pending,
			interaction.Input {
				kind = .Key,
				stroke = interaction.Key_Stroke {
					kind = .Unicode_Scalar,
					scalar = ' ',
					modifiers = {.Control},
				},
			},
		)
		testing.expect_value(t, mark_failure.code, interaction.Failure_Code.None)
		testing.expect_value(t, mark_resolution.kind, interaction.Resolution_Kind.Command)
		testing.expect_value(t, mark_resolution.command, set_mark)
		quit_resolution, quit_failure := interaction.resolve_input(
			snapshot,
			interaction.Registry_Generation(19),
			&pending,
			interaction.Input {
				kind = .Key,
				stroke = interaction.Key_Stroke {
					kind = .Unicode_Scalar,
					scalar = 'g',
					modifiers = {.Control},
				},
			},
		)
		testing.expect_value(t, quit_failure.code, interaction.Failure_Code.None)
		testing.expect_value(t, quit_resolution.kind, interaction.Resolution_Kind.Command)
		testing.expect_value(t, quit_resolution.command, keyboard_quit)
		undo_aliases := [2]rune{'/', '_'}
		for scalar in undo_aliases {
			alias_resolution, alias_failure := interaction.resolve_input(
				snapshot,
				interaction.Registry_Generation(19),
				&pending,
				interaction.Input {
					kind = .Key,
					stroke = interaction.Key_Stroke {
						kind = .Unicode_Scalar,
						scalar = scalar,
						modifiers = {.Control},
					},
				},
			)
			testing.expect_value(t, alias_failure.code, interaction.Failure_Code.None)
			testing.expect_value(t, alias_resolution.kind, interaction.Resolution_Kind.Command)
			testing.expect_value(t, alias_resolution.command, undo)
		}
		first, first_failure := interaction.resolve_input(
			snapshot,
			interaction.Registry_Generation(19),
			&pending,
			interaction.Input {
				kind = .Key,
				stroke = interaction.Key_Stroke {
					kind = .Unicode_Scalar,
					scalar = 'x',
					modifiers = {.Control},
				},
			},
		)
		testing.expect_value(t, first_failure.code, interaction.Failure_Code.None)
		testing.expect_value(t, first.kind, interaction.Resolution_Kind.Pending)
		second, second_failure := interaction.resolve_input(
			snapshot,
			interaction.Registry_Generation(19),
			&pending,
			interaction.Input {
				kind = .Key,
				stroke = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = 'u'},
			},
		)
		testing.expect_value(t, second_failure.code, interaction.Failure_Code.None)
		testing.expect_value(t, second.kind, interaction.Resolution_Kind.Command)
		testing.expect_value(t, second.command, undo)
		_, _ = interaction.resolve_input(
			snapshot,
			interaction.Registry_Generation(19),
			&pending,
			interaction.Input {
				kind = .Key,
				stroke = interaction.Key_Stroke {
					kind = .Unicode_Scalar,
					scalar = 'x',
					modifiers = {.Control},
				},
			},
		)
		exchange_resolution, exchange_failure := interaction.resolve_input(
			snapshot,
			interaction.Registry_Generation(19),
			&pending,
			interaction.Input {
				kind = .Key,
				stroke = interaction.Key_Stroke {
					kind = .Unicode_Scalar,
					scalar = 'x',
					modifiers = {.Control},
				},
			},
		)
		testing.expect_value(t, exchange_failure.code, interaction.Failure_Code.None)
		testing.expect_value(t, exchange_resolution.kind, interaction.Resolution_Kind.Command)
		testing.expect_value(t, exchange_resolution.command, exchange)
	}
	catalog, catalog_ok := interaction.profile_activation_catalog(&profile_activation)
	if catalog_ok && len(catalog.profiles) == 2 {
		active_context := interaction.Active_Context {
			identity = interaction.Context_Handle {
				id = interaction.Context_ID(1),
				generation = interaction.Context_Generation(1),
			},
		}
		selected, selection_failure := interaction.profile_activation_select_profile(
			&profile_activation,
			command_registry,
			interaction.Profile_Selection_Request {
				catalog_generation = catalog.generation,
				snapshot_generation = profile_activation.generation,
				target = catalog.profiles[1].identity,
			},
			active_context,
			&profile_pending,
			interaction.DEFAULT_RESOLUTION_POLICY,
			context.allocator,
		)
		testing.expectf(t, selected, "modal selection failed: %v", selection_failure.code)
		modal_snapshot, modal_active := interaction.profile_activation_snapshot(&profile_activation)
		execute_extended, execute_found, _ := interaction.command_lookup(
			command_registry,
			"execute-extended-command",
		)
		testing.expect(t, modal_active && execute_found)
		if modal_active && execute_found {
			pending: interaction.Pending_State
			colon, colon_failure := interaction.resolve_input(
				modal_snapshot,
				execute_extended.registry_generation,
				&pending,
				interaction.Input {
					kind = .Key,
					stroke = {kind = .Unicode_Scalar, scalar = ':'},
				},
			)
			meta_x, meta_x_failure := interaction.resolve_input(
				modal_snapshot,
				execute_extended.registry_generation,
				&pending,
				interaction.Input {
					kind = .Key,
					stroke = {kind = .Unicode_Scalar, scalar = 'x', modifiers = {.Meta}},
				},
			)
			testing.expect_value(t, colon_failure.code, interaction.Failure_Code.None)
			testing.expect_value(t, meta_x_failure.code, interaction.Failure_Code.None)
			testing.expect_value(t, colon.kind, interaction.Resolution_Kind.Command)
			testing.expect_value(t, meta_x.kind, interaction.Resolution_Kind.Command)
			testing.expect_value(t, colon.command, execute_extended)
			testing.expect_value(t, meta_x.command, execute_extended)
		}
		_, alias_found, _ := interaction.command_lookup(command_registry, "w")
		testing.expect(t, !alias_found)
		native, native_found, _ := interaction.command_lookup(
			command_registry,
			"save-associated-document",
		)
		racket, racket_found, _ := interaction.command_lookup(
			command_registry,
			"uppercase-current-line",
		)
		testing.expect(t, native_found && racket_found)
		if native_found && racket_found {
			native_metadata, _, _ := interaction.command_metadata(command_registry, native)
			racket_metadata, _, _ := interaction.command_metadata(command_registry, racket)
			testing.expect_value(t, native_metadata.implementation, interaction.Implementation_Class.Native)
			testing.expect_value(t, racket_metadata.implementation, interaction.Implementation_Class.Racket)
		}
	}
	profile_closed, profile_close_failure := interaction.profile_activation_close(&profile_activation)
	testing.expectf(t, profile_closed, "profile close failed: %v", profile_close_failure.code)
}

@(private)
verify_racket_local_rejections :: proc(t: ^testing.T, request: Racket_Context) {
	cancelled := request
	cancelled.cancelled = true
	_, ok, failure := racket_command_execute(cancelled)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Cancelled)

	without_memory := request
	without_memory.temporary_allocator = runtime.nil_allocator()
	_, ok, failure = racket_command_execute(without_memory)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Temporary_Memory_Limit)
}

@(private)
verify_racket_line_cases :: proc(
	t: ^testing.T,
	racket_runtime: ^hosting.Runtime,
	capabilities: ^bridge.Buffer_Capability_Registry,
	transaction_capabilities: ^bridge.Transaction_Capability_Registry,
	command_registry: ^interaction.Command_Registry,
	uppercase: interaction.Command_Handle,
) {
	verify_racket_line_case(
		t,
		racket_runtime,
		capabilities,
		transaction_capabilities,
		command_registry,
		uppercase,
		editor.Buffer_ID(12),
		"straße λódź\n",
		"STRASSE ΛÓDŹ\n",
		.Buffer_Committed,
		1,
		15,
	)
	verify_racket_line_case(
		t,
		racket_runtime,
		capabilities,
		transaction_capabilities,
		command_registry,
		uppercase,
		editor.Buffer_ID(13),
		"\n",
		"\n",
		.No_Op,
		0,
		0,
	)
}

@(private)
verify_racket_line_case :: proc(
	t: ^testing.T,
	racket_runtime: ^hosting.Runtime,
	capabilities: ^bridge.Buffer_Capability_Registry,
	transaction_capabilities: ^bridge.Transaction_Capability_Registry,
	command_registry: ^interaction.Command_Registry,
	uppercase: interaction.Command_Handle,
	buffer_id: editor.Buffer_ID,
	input, expected: string,
	completion: Native_Completion,
	revision, cursor_offset: u64,
) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(&buffer, buffer_id, input, test_allocators())
	view_registry: editor_view.Registry
	registry_ready, _ := editor_view.registry_init(
		&view_registry,
		editor_view.Registry_ID(u32(buffer_id)),
		context.allocator,
	)
	view_handle, view_ready, _ := editor_view.create(&view_registry, &buffer)
	testing.expect(t, initialized && registry_ready && view_ready)
	if initialized && registry_ready && view_ready {
		result, ok, failure := racket_command_execute(Racket_Context {
			runtime = racket_runtime,
			capabilities = capabilities,
			transaction_capabilities = transaction_capabilities,
			command_registry = command_registry,
			command = uppercase,
			buffer = &buffer,
			view_registry = &view_registry,
			view = view_handle,
			profile = display.terminal_unicode17_profile(),
			constraints = display.Viewport_Constraints{width_cells = 80, height_rows = 24},
			temporary_allocator = context.temp_allocator,
			persistent_allocator = context.allocator,
			transaction_id = edit_transaction.Transaction_ID(u64(buffer_id)),
			undo_unit_id = edit_transaction.Undo_Unit_ID(u64(buffer_id)),
		})
		defer native_result_close(&result)
		testing.expectf(t, ok, "line command failed: %v", failure.code)
		testing.expect_value(t, result.completion, completion)
		expect_buffer_and_view(t, &buffer, &view_registry, view_handle, revision, cursor_offset, expected)
	}
	if view_ready {
		editor_view.close(&view_registry, &view_handle)
	}
	if registry_ready {
		editor_view.registry_close(&view_registry)
	}
	if initialized {
		editor.buffer_close(&buffer)
	}
}

@(private)
expect_buffer_and_view :: proc(
	t: ^testing.T,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	revision, cursor_offset: u64,
	expected: string,
) {
	logical, logical_ok, _ := editor_view.snapshot(view_registry, view)
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	testing.expect(t, logical_ok && stats_ok)
	testing.expect_value(t, u64(logical.revision), revision)
	testing.expect_value(t, u64(logical.point_position.byte_offset), cursor_offset)
	testing.expect_value(t, u64(stats.revision), revision)
	observed := make([]u8, int(stats.text_bytes), context.temp_allocator)
	defer delete(observed, context.temp_allocator)
	_, inspected, _ := editor.buffer_inspect(
		buffer,
		editor.Byte_Offset(0),
		editor.Byte_Offset(stats.text_bytes),
		observed,
	)
	testing.expect(t, inspected)
	testing.expect_value(t, string(observed), expected)
}

@(private)
verify_local_rejections :: proc(
	t: ^testing.T,
	racket_runtime: ^hosting.Runtime,
	registry: ^bridge.Buffer_Capability_Registry,
	capability: bridge.Buffer_Capability,
	identity: bridge.Buffer_Identity,
) {
	_, executed, failure := buffer_command_run(
		racket_runtime,
		registry,
		capability,
		editor.Buffer_ID(10),
		identity.revision,
		context.allocator,
		context.temp_allocator,
		edit_transaction.Transaction_ID(11),
		edit_transaction.Undo_Unit_ID(11),
	)
	testing.expect(t, !executed)
	testing.expect_value(t, failure.bridge_code, bridge.Failure_Code.Wrong_Buffer)

	_, executed, failure = buffer_command_run(
		racket_runtime,
		registry,
		capability,
		identity.buffer_id,
		editor.Revision(1),
		context.allocator,
		context.temp_allocator,
		edit_transaction.Transaction_ID(12),
		edit_transaction.Undo_Unit_ID(12),
	)
	testing.expect(t, !executed)
	testing.expect_value(t, failure.bridge_code, bridge.Failure_Code.Stale_Revision)

	_, executed, failure = buffer_command_run(
		racket_runtime,
		registry,
		capability,
		identity.buffer_id,
		identity.revision,
		context.allocator,
		context.temp_allocator,
		edit_transaction.Transaction_ID(13),
		edit_transaction.Undo_Unit_ID(13),
		true,
	)
	testing.expect(t, !executed)
	testing.expect_value(t, failure.code, Failure_Code.Cancelled)

	_, executed, failure = buffer_command_run(
		racket_runtime,
		registry,
		capability,
		identity.buffer_id,
		identity.revision,
		context.allocator,
		runtime.nil_allocator(),
		edit_transaction.Transaction_ID(14),
		edit_transaction.Undo_Unit_ID(14),
	)
	testing.expect(t, !executed)
	testing.expect_value(t, failure.code, Failure_Code.Temporary_Memory_Limit)

	expect_capability_text(
		t,
		registry,
		capability,
		identity.buffer_id,
		identity.revision,
		"hello odra",
	)
}

@(private)
verify_stale_and_closed_capabilities :: proc(
	t: ^testing.T,
	racket_runtime: ^hosting.Runtime,
	registry: ^bridge.Buffer_Capability_Registry,
	buffer: ^editor.Buffer,
	identity: bridge.Buffer_Identity,
) {
	transient, _, acquired, _ := bridge.buffer_capability_acquire(registry, buffer)
	testing.expect(t, acquired)
	stale := transient
	released, _ := bridge.buffer_capability_release(registry, &transient)
	testing.expect(t, released)
	_, executed, stale_failure := buffer_command_run(
		racket_runtime,
		registry,
		stale,
		identity.buffer_id,
		identity.revision,
		context.allocator,
		context.temp_allocator,
		edit_transaction.Transaction_ID(15),
		edit_transaction.Undo_Unit_ID(15),
	)
	testing.expect(t, !executed)
	testing.expect_value(t, stale_failure.bridge_code, bridge.Failure_Code.Stale_Capability)

	closed_buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&closed_buffer,
		editor.Buffer_ID(11),
		"hello odra",
		test_allocators(),
	)
	testing.expect(t, initialized)
	closed_capability: bridge.Buffer_Capability
	closed_identity: bridge.Buffer_Identity
	closed_capability, closed_identity, acquired, _ =
		bridge.buffer_capability_acquire(registry, &closed_buffer)
	testing.expect(t, acquired)
	closed, _ := editor.buffer_close(&closed_buffer)
	testing.expect(t, closed)
	closed_failure: Failure_Context
	_, executed, closed_failure = buffer_command_run(
		racket_runtime,
		registry,
		closed_capability,
		closed_identity.buffer_id,
		closed_identity.revision,
		context.allocator,
		context.temp_allocator,
		edit_transaction.Transaction_ID(16),
		edit_transaction.Undo_Unit_ID(16),
	)
	testing.expect(t, !executed)
	testing.expect_value(t, closed_failure.bridge_code, bridge.Failure_Code.Closed_Buffer)
	released, _ = bridge.buffer_capability_release(registry, &closed_capability)
	testing.expect(t, released)
}

@(private)
expect_capability_text :: proc(
	t: ^testing.T,
	registry: ^bridge.Buffer_Capability_Registry,
	capability: bridge.Buffer_Capability,
	buffer_id: editor.Buffer_ID,
	revision: editor.Revision,
	expected: string,
) {
	observed: [10]byte
	_, inspected, inspect_failure := bridge.buffer_capability_inspect(
		registry,
		capability,
		buffer_id,
		revision,
		bridge.Byte_Range {start = 0, end = 10},
		observed[:],
	)
	testing.expect(t, inspected)
	testing.expect_value(t, inspect_failure.code, bridge.Failure_Code.None)
	testing.expect_value(t, string(observed[:]), expected)
}

@(private)
test_allocators :: proc() -> editor.Allocator_Set {
	return editor.Allocator_Set {
		persistent = context.allocator,
		temporary = context.temp_allocator,
	}
}
