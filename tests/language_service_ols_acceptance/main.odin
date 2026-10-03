// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import completion "../../src/completion"
import editor "../../src/editor"
import history "../../src/history"
import service "../../src/language_service"
import project_core "../../src/project"
import transaction "../../src/transaction"
import ui "../../src/ui"
import editor_view "../../src/view"
import json "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:time"

Acceptance_Case :: struct {
	name:                string,
	command:             []string,
	root:                string,
	path:                string,
	language:            string,
	initial_text:        string,
	target_text:         string,
	replacement:         string,
	expect_echo:         bool,
	minimum_diagnostics: u32,
	expect_completion:   bool,
	completion_query:    string,
	completion_start:    u64,
	completion_cursor:   u64,
	completion_label:    string,
	provider:            service.Provider_Handle,
}

main :: proc() {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	passed := language_service_acceptance_run(allocator)
	retained := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	passed = passed && retained == 0
	fmt.printf(
		"acceptance=language-service passed=%t fixture=true ols=true completion=true retained_native_bytes=%d\n",
		passed,
		retained,
	)
	if !passed do os.exit(1)
}

language_service_acceptance_run :: proc(allocator: mem.Allocator) -> bool {
	fixture_root, fixture_root_error := os.get_absolute_path(
		"tests/fixtures/language-service-fixture",
		allocator,
	)
	if fixture_root_error != nil do return false
	defer delete(fixture_root, allocator)
	fixture_path, fixture_path_error := os.join_path({fixture_root, "source.fixture"}, allocator)
	if fixture_path_error != nil do return false
	defer delete(fixture_path, allocator)
	server_script, server_script_error := os.get_absolute_path(
		"tests/fixtures/language-service-server.rkt",
		allocator,
	)
	if server_script_error != nil do return false
	defer delete(server_script, allocator)
	ols_root, ols_root_error := os.get_absolute_path("tests/fixtures/ols", allocator)
	if ols_root_error != nil do return false
	defer delete(ols_root, allocator)
	ols_path, ols_path_error := os.join_path({ols_root, "main.odin"}, allocator)
	if ols_path_error != nil do return false
	defer delete(ols_path, allocator)

	registry: service.Provider_Registry
	registry_ready, _ := service.provider_registry_init(
		&registry,
		service.Registry_Handle{id = 1001, generation = 1},
		service.DEFAULT_LIMITS,
		allocator,
	)
	if !registry_ready do return false
	defer service.provider_registry_close(&registry)
	factory, factory_ready, _ := service.provider_registry_register_factory_ols(&registry)
	if !factory_ready do return false

	fixture_languages := [1]string{"fixture"}
	fixture_arguments := [2]string{server_script, "lsp"}
	fixture_definition := service.Definition_Proposal{
		kind = .Programmable,
		name = "fixture-language-server",
		executable = "racket",
		arguments = fixture_arguments[:],
		root_policy = .Project_Membership,
		root = fixture_root,
		languages = fixture_languages[:],
		initialization_options = `{}`,
		client_settings = `{}`,
		feature_policy = {.Diagnostics, .Completion},
		requested_capabilities = {
			.Initialize, .Shutdown, .Full_Synchronization, .Save_Notification,
			.Push_Diagnostics, .Log_Message, .Completion,
		},
		preferred_encoding = .UTF_16,
		preferred_sync = .Full,
		limits = service.DEFAULT_LIMITS,
		deadlines = service.DEFAULT_DEADLINES,
		restart = service.DEFAULT_RESTART_POLICY,
	}
	fixture_handle, fixture_ready, _ := service.provider_registry_replace(
		&registry,
		factory,
		fixture_definition,
		service.Executable_Discovery{search_path = "/usr/sbin"},
	)
	if !fixture_ready do return false
	fixture_view, fixture_viewed, _ := service.provider_registry_definition(&registry, fixture_handle)
	if !fixture_viewed do return false
	fixture_command, fixture_command_error := make(
		[]string,
		1 + len(fixture_view.arguments),
		allocator,
	)
	if fixture_command_error != nil do return false
	defer delete(fixture_command, allocator)
	fixture_command[0] = fixture_view.resolved_executable
	copy(fixture_command[1:], fixture_view.arguments)
	fixture_case := Acceptance_Case{
		name = "fixture",
		command = fixture_command,
		root = fixture_root,
		path = fixture_path,
		language = "fixture",
		initial_text = "alpha\n",
		target_text = "alpha\nbeta\n",
		replacement = "beta\n",
		expect_echo = true,
		minimum_diagnostics = 1,
		expect_completion = true,
		completion_query = "beta",
		completion_start = 6,
		completion_cursor = 10,
		completion_label = "alphaValue",
		provider = fixture_view.provider.handle,
	}
	if !language_service_acceptance_case(fixture_case, 1101, allocator) {
		fmt.eprintln("language-service acceptance failed: fixture")
		return false
	}

	restored, _ := service.provider_registry_restore_factory(&registry)
	if !restored do return false
	ols_executable, ols_found, _ := service.provider_registry_discover_executable(
		&registry,
		factory,
		service.Executable_Discovery{explicit_path = "/usr/sbin/ols"},
	)
	if !ols_found do return false
	defer delete(ols_executable, allocator)
	factory_view, factory_viewed, _ := service.provider_registry_definition(&registry, factory)
	if !factory_viewed do return false
	ols_command := [1]string{ols_executable}
	ols_case := Acceptance_Case{
		name = "ols",
		command = ols_command[:],
		root = ols_root,
		path = ols_path,
		language = "odin",
		initial_text = "package main\n\nmain :: proc() {}\n",
		target_text = "package main\n\nmain :: proc() {}\n\nother :: proc() {\n\tvalue := )\n}\n",
		replacement = "\nother :: proc() {\n\tvalue := )\n}\n",
		minimum_diagnostics = 1,
		expect_completion = true,
		completion_query = "main",
		completion_start = 8,
		completion_cursor = 12,
		provider = factory_view.provider.handle,
	}
	if !language_service_acceptance_case(ols_case, 1201, allocator) {
		fmt.eprintln("language-service acceptance failed: ols")
		return false
	}
	return true
}

language_service_acceptance_case :: proc(
	scenario: Acceptance_Case,
	seed: u64,
	allocator: mem.Allocator,
) -> bool {
	project_registry: project_core.Registry
	owner := project_core.Owner_Handle{id = project_core.Owner_ID(seed), generation = 1}
	project_ready, _ := project_core.registry_init(
		&project_registry,
		owner,
		project_core.DEFAULT_POLICY,
		project_core.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	if !project_ready do return language_service_acceptance_fail(scenario.name, "project registry")
	defer project_core.registry_close(&project_registry)
	directories := [1]project_core.Directory_Proposal{{path = scenario.root, trust = .Trusted}}
	prepared: project_core.Prepared_Snapshot
	prepared_ready, _ := project_core.registry_prepare_snapshot(
		&project_registry,
		project_core.Snapshot_Request{
			owner = owner,
			project_id = project_core.Project_ID(seed + 1),
			name = "Language Service Acceptance",
			directories = directories[:],
			temporary = true,
		},
		&prepared,
	)
	if !prepared_ready do return language_service_acceptance_fail(scenario.name, "project preparation")
	project_descriptor, published, _ := project_core.prepared_snapshot_publish(&project_registry, &prepared)
	if !published do return language_service_acceptance_fail(scenario.name, "project publication")
	memberships, copied, membership_failure := project_core.registry_membership_descriptors(
		&project_registry,
		project_descriptor.handle,
	)
	if !copied || len(memberships.descriptors) != 1 {
		fmt.eprintf(
			"language-service acceptance membership: copied=%t count=%d failure=%v\n",
			copied,
			len(memberships.descriptors),
			membership_failure.code,
		)
		if copied do project_core.descriptor_batch_close(&memberships)
		return language_service_acceptance_fail(scenario.name, "project membership")
	}
	defer project_core.descriptor_batch_close(&memberships)
	membership := memberships.descriptors[0].handle

	session_handle := service.Session_Handle{
		provider = scenario.provider,
		id = service.Session_ID(seed + 2),
		generation = 1,
	}
	process, started, _ := service.process_session_start(
		service.Process_Start_Request{
			handle = session_handle,
			command = scenario.command,
			working_directory = scenario.root,
			limits = service.DEFAULT_LIMITS,
			deadlines = service.DEFAULT_DEADLINES,
			restart = service.DEFAULT_RESTART_POLICY,
		},
		1,
		allocator,
	)
	if !started do return language_service_acceptance_fail(scenario.name, "process start")
	defer service.process_session_close(&process)

	uri := fmt.aprintf("file://%s", scenario.path, allocator = context.temp_allocator)
	root_uri := fmt.aprintf("file://%s", scenario.root, allocator = context.temp_allocator)
	encoded_root_uri, root_uri_error := json.marshal(root_uri, {}, context.temp_allocator)
	if root_uri_error != nil do return language_service_acceptance_fail(scenario.name, "root URI")
	initialize := fmt.aprintf(
		`{{"jsonrpc":"2.0","id":1,"method":"initialize","params":{{"rootUri":%s,"capabilities":{{}},"workspaceFolders":[{{"uri":%s,"name":"acceptance"}}]}}}}`,
		string(encoded_root_uri),
		string(encoded_root_uri),
		allocator = context.temp_allocator,
	)
	queued, _ := service.process_session_send_frame(&process, transmute([]u8)initialize)
	if !queued do return language_service_acceptance_fail(scenario.name, "initialize send")
	now := i64(1)
	capabilities, initialized := language_service_wait_response(&process, 1, &now)
	if !initialized || capabilities.synchronization_mode == .None {
		return language_service_acceptance_fail(scenario.name, "initialize response")
	}
	confirmed, _ := service.process_session_confirm_initialized(&process, capabilities)
	if !confirmed do return language_service_acceptance_fail(scenario.name, "initialize confirmation")
	initialized_body := transmute([]u8)(string(`{"jsonrpc":"2.0","method":"initialized","params":{}}`))
	initialized_queued, _ := service.process_session_send_frame(&process, initialized_body)
	if !initialized_queued do return language_service_acceptance_fail(scenario.name, "initialized send")

	languages := [1]string{scenario.language}
	synchronizer: service.Document_Synchronizer
	synchronizer_ready, _ := service.document_synchronizer_init(
		&synchronizer,
		&project_registry,
		service.Synchronizer_Request{
			session = session_handle,
			project = project_descriptor.handle,
			membership = membership,
			root_policy = .Project_Membership,
			languages = languages[:],
			capabilities = capabilities.capabilities,
			position_encoding = capabilities.position_encoding,
			synchronization_mode = capabilities.synchronization_mode,
			limits = service.DEFAULT_LIMITS,
		},
		allocator,
	)
	if !synchronizer_ready do return language_service_acceptance_fail(scenario.name, "synchronizer")
	defer service.document_synchronizer_close(&synchronizer)
	diagnostics: service.Diagnostic_Store
	diagnostics_ready, _ := service.diagnostic_store_init(
		&diagnostics,
		session_handle,
		service.DEFAULT_LIMITS,
		allocator,
	)
	if !diagnostics_ready do return language_service_acceptance_fail(scenario.name, "diagnostic store")
	defer service.diagnostic_store_close(&diagnostics)
	binding, opened, _ := service.document_synchronizer_open(
		&synchronizer,
		service.Document_Open_Request{
			document_identity = seed + 3,
			buffer_identity = seed + 4,
			canonical_revision = 1,
			path = scenario.path,
			uri = uri,
			language = scenario.language,
			text = scenario.initial_text,
		},
	)
	if !opened || !language_service_send_next(&synchronizer, &process) {
		return language_service_acceptance_fail(scenario.name, "open")
	}
	if scenario.expect_echo && !language_service_wait_text(&process, scenario.initial_text, &now) {
		return language_service_acceptance_fail(scenario.name, "open echo")
	}
	changed, _ := service.document_synchronizer_change(
		&synchronizer,
		service.Document_Change_Request{
			binding = binding,
			base_revision = 1,
			target_revision = 2,
			start = u64(len(scenario.initial_text)),
			end = u64(len(scenario.initial_text)),
			replacement = scenario.replacement,
			target_text = scenario.target_text,
		},
	)
	if !changed || !language_service_send_next(&synchronizer, &process) {
		return language_service_acceptance_fail(scenario.name, "change")
	}
	if scenario.expect_echo && !language_service_wait_text(&process, scenario.target_text, &now) {
		return language_service_acceptance_fail(scenario.name, "change echo")
	}
	if !language_service_wait_diagnostics(
		&process,
		&diagnostics,
		&synchronizer,
		binding,
		2,
		scenario.minimum_diagnostics,
		&now,
	) {
		return language_service_acceptance_fail(scenario.name, "diagnostics")
	}
	if scenario.expect_completion && !language_service_accept_completion(
		&process,
		&synchronizer,
		binding,
		session_handle,
		seed,
		scenario.completion_query,
		scenario.completion_start,
		scenario.completion_cursor,
		scenario.completion_label,
		scenario.initial_text,
		scenario.target_text,
		scenario.replacement,
		capabilities,
		&now,
		allocator,
	) {
		return language_service_acceptance_fail(scenario.name, "completion")
	}
	saved, _ := service.document_synchronizer_save(&synchronizer, binding, 2)
	if !saved || !language_service_send_next(&synchronizer, &process) {
		return language_service_acceptance_fail(scenario.name, "save")
	}
	closed, _ := service.document_synchronizer_close_document(&synchronizer, binding, 2)
	if !closed || !language_service_send_next(&synchronizer, &process) {
		return language_service_acceptance_fail(scenario.name, "close")
	}
	if shutting_down, _ := service.process_session_begin_shutdown(&process, now); !shutting_down {
		return language_service_acceptance_fail(scenario.name, "shutdown transition")
	}
	shutdown := transmute([]u8)(string(`{"jsonrpc":"2.0","id":2,"method":"shutdown","params":null}`))
	if shutdown_queued, _ := service.process_session_send_frame(&process, shutdown); !shutdown_queued {
		return language_service_acceptance_fail(scenario.name, "shutdown send")
	}
	_, shutdown_ready := language_service_wait_response(&process, 2, &now)
	if !shutdown_ready do return language_service_acceptance_fail(scenario.name, "shutdown response")
	exit_body := transmute([]u8)(string(`{"jsonrpc":"2.0","method":"exit","params":null}`))
	if exit_queued, _ := service.process_session_send_frame(&process, exit_body); !exit_queued {
		return language_service_acceptance_fail(scenario.name, "exit send")
	}
	for _ in 0 ..< 2_000 {
		poll, _ := service.process_session_poll(&process, now)
		if poll.health == .Stopped do return true
		if poll.health == .Failed {
			fmt.eprintf(
				"language-service shutdown failed: code=%v status=%d\n",
				poll.failure.code,
				poll.exit_status,
			)
			return language_service_acceptance_fail(scenario.name, "process failure")
		}
		time.sleep(time.Millisecond)
		now += i64(time.Millisecond)
	}
	return language_service_acceptance_fail(scenario.name, "shutdown timeout")
}

language_service_acceptance_fail :: proc(name, stage: string) -> bool {
	fmt.eprintf("language-service acceptance failed: %s: %s\n", name, stage)
	return false
}

language_service_send_next :: proc(
	synchronizer: ^service.Document_Synchronizer,
	process: ^service.Process_Session,
) -> bool {
	view, queued := service.document_synchronizer_peek(synchronizer)
	if !queued do return false
	sent, _ := service.process_session_send_frame(process, view.body)
	if !sent do return false
	return service.document_synchronizer_ack(synchronizer, view.record.generation)
}

language_service_wait_response :: proc(
	process: ^service.Process_Session,
	id: i64,
	now: ^i64,
) -> (service.Capability_Values, bool) {
	for _ in 0 ..< 10_000 {
		poll, _ := service.process_session_poll(process, now^)
		if poll.health == .Failed {
			inspection, inspected := service.process_session_inspect(process)
			standard_error: [4 * 1024]u8
			standard_error_count, _ := service.process_session_copy_stderr(process, standard_error[:])
			if inspected {
				fmt.eprintf(
					"language-service process failed: code=%v stderr=%q\n",
					inspection.failure.code,
					string(standard_error[:standard_error_count]),
				)
			}
			return {}, false
		}
		if poll.frame_ready {
			frame, taken, _ := service.process_session_take_frame(process)
			if taken {
				message, decoded, _ := service.message_decode(frame.body)
				service.frame_close(&frame)
				if decoded {
					matched := message.record.kind == .Response &&
						message.record.id.kind == .Integer && message.record.id.integer == id
					capabilities := message.record.capabilities
					service.message_close(&message)
					if matched do return capabilities, true
				}
			}
		}
		time.sleep(time.Millisecond)
		now^ += i64(time.Millisecond)
	}
	return {}, false
}

language_service_wait_text :: proc(
	process: ^service.Process_Session,
	expected: string,
	now: ^i64,
) -> bool {
	encoded, marshal_error := json.marshal(expected, {}, context.temp_allocator)
	if marshal_error != nil do return false
	for _ in 0 ..< 2_000 {
		poll, _ := service.process_session_poll(process, now^)
		if poll.health == .Failed do return false
		if poll.frame_ready {
			frame, taken, _ := service.process_session_take_frame(process)
			if taken {
				matched := strings.contains(string(frame.body), string(encoded))
				service.frame_close(&frame)
				if matched do return true
			}
		}
		time.sleep(time.Millisecond)
		now^ += i64(time.Millisecond)
	}
	return false
}

language_service_wait_diagnostics :: proc(
	process: ^service.Process_Session,
	diagnostics: ^service.Diagnostic_Store,
	synchronizer: ^service.Document_Synchronizer,
	binding: service.Document_Binding_Handle,
	revision: u64,
	minimum: u32,
	now: ^i64,
) -> bool {
	for _ in 0 ..< 10_000 {
		poll, _ := service.process_session_poll(process, now^)
		if poll.health == .Failed do return false
		if poll.frame_ready {
			frame, taken, _ := service.process_session_take_frame(process)
			if taken {
				message, decoded, _ := service.message_decode(frame.body)
				service.frame_close(&frame)
				if decoded {
					if service.message_method_is(&message, "textDocument/publishDiagnostics") {
						_, published, _ := service.diagnostic_store_publish_message(
							diagnostics,
							synchronizer,
							binding,
							revision,
							&message,
						)
						inspection, inspected := service.diagnostic_store_inspect(diagnostics)
						service.message_close(&message)
						if published && inspected && inspection.diagnostics >= minimum do return true
						continue
					}
					service.message_close(&message)
				}
			}
		}
		time.sleep(time.Millisecond)
		now^ += i64(time.Millisecond)
	}
	return false
}

language_service_accept_completion :: proc(
	process: ^service.Process_Session,
	synchronizer: ^service.Document_Synchronizer,
	binding: service.Document_Binding_Handle,
	session: service.Session_Handle,
	seed: u64,
	query_text: string,
	query_start: u64,
	cursor_byte: u64,
	expected_label: string,
	initial_text, target_text, replacement: string,
	capabilities: service.Capability_Values,
	now: ^i64,
	allocator: mem.Allocator,
) -> bool {
	if .Completion not_in capabilities.capabilities do return false
	query, query_ok := completion.text_copy(query_text)
	if !query_ok do return false
	provider_capabilities := completion.Capabilities{.Explicit, .Documentation}
	if capabilities.completion.resolve do provider_capabilities += {.Resolve}
	request := completion.Request {
		id = 1,
		generation = 1,
		scope = {
			document_id = completion.Document_ID(seed + 3),
			buffer_id = completion.Buffer_ID(seed + 4),
			document_revision = 2,
			view_id = 1,
			view_generation = 1,
			language_id = 1,
			language_generation = 1,
			provider_id = 1,
			provider_generation = 1,
			server_session_id = completion.Server_Session_ID(session.id),
			server_session_generation = completion.Server_Session_Generation(session.generation),
			document_binding_id = completion.Document_Binding_ID(binding.id),
			document_binding_generation = completion.Document_Binding_Generation(binding.generation),
			transmitted_revision = 2,
		},
		cursor_byte = cursor_byte,
		query_range = {start = query_start, end = cursor_byte},
		query = query,
		trigger = .Explicit,
		provider_capabilities = provider_capabilities,
		state = .Prepared,
	}
	roles: completion.Role_Registry
	roles_ready, _ := completion.registry_init(
		&roles,
		completion.Role_Registry_ID(seed + 20),
		completion.DEFAULT_LIMITS,
		allocator,
	)
	if !roles_ready do return false
	defer completion.registry_close(&roles)
	composition, scoped, _ := completion.registry_scope(&roles)
	if !scoped do return false
	configured, configured_ok, _ := completion.registry_configure(
		&roles,
		composition,
		completion.factory_configuration(),
	)
	if !configured_ok do return false
	provider := configured.selections[0].selected
	request.scope.provider_id = completion.Provider_ID(provider.implementation_id)
	request.scope.provider_generation = completion.Provider_Generation(
		provider.implementation_generation,
	)
	controller: completion.Controller
	controller_ready, _ := completion.controller_init(
		&controller,
		completion.Controller_ID(seed + 21),
		1,
		configured,
		completion.DEFAULT_LIMITS,
		allocator,
	)
	if !controller_ready do return false
	defer completion.controller_close(&controller)
	controller_started, start_failure := completion.controller_start(
		&controller,
		completion.Session_ID(seed + 22),
		1,
		request,
		configured,
	)
	controller_queued, queue_failure := completion.controller_queue(&controller)
	if !controller_started || !controller_queued {
		fmt.eprintf(
			"completion workflow controller start: started=%t start=%v queued=%t queue=%v provider=%d/%d\n",
			controller_started,
			start_failure.code,
			controller_queued,
			queue_failure.code,
			u64(request.scope.provider_id),
			u64(request.scope.provider_generation),
		)
		return false
	}
	exchange: service.Completion_Exchange
	initialized, _ := service.completion_exchange_init(
		&exchange,
		session,
		binding,
		capabilities,
		service.DEFAULT_LIMITS,
		service.DEFAULT_DEADLINES,
		allocator,
	)
	if !initialized do return false
	defer service.completion_exchange_close(&exchange)
	_, prepared, _ := service.completion_exchange_prepare(&exchange, synchronizer, request, now^)
	if !prepared do return false
	sent, _ := service.completion_exchange_send(&exchange, process)
	if !sent do return false
	controller_sent, _ := completion.controller_send(&controller)
	if !controller_sent {
		fmt.eprintln("completion workflow controller send")
		return false
	}
	for _ in 0 ..< 10_000 {
		poll, _ := service.process_session_poll(process, now^)
		if poll.health == .Failed do return false
		if poll.frame_ready {
			frame, taken, _ := service.process_session_take_frame(process)
			if taken {
				message, decoded, _ := service.message_decode(frame.body)
				service.frame_close(&frame)
				if decoded {
					owner, normalized, _ := service.completion_response_normalize(
						&exchange,
						synchronizer,
						&message,
						allocator,
					)
					service.message_close(&message)
					if normalized {
						valid := owner.batch.disposition != .Invalid
						if expected_label != "" {
							valid = valid && owner.batch.item_count == 1 &&
								completion.text_view(&owner.batch.items[0].label) == expected_label &&
								owner.batch.items[0].primary_edit.range == completion.Byte_Range{
									start = query_start,
									end = cursor_byte,
								} &&
								owner.batch.items[0].additional_edit_count == 1
						}
						published, publish_failure := completion.controller_publish(&controller, &owner.batch)
						accepted := published
						if accepted && expected_label != "" {
							accepted = language_completion_factory_workflow_accept(
								&controller,
								initial_text,
								target_text,
								replacement,
								request,
								seed,
								allocator,
							)
						}
						if !published {
							fmt.eprintf("completion workflow publication: %v\n", publish_failure.code)
						} else if !accepted {
							fmt.eprintln("completion workflow acceptance")
						}
						valid = valid && accepted
						service.completion_batch_owner_close(&owner)
						return valid
					}
				}
			}
		}
		time.sleep(time.Millisecond)
		now^ += i64(time.Millisecond)
	}
	return false
}

language_completion_factory_workflow_accept :: proc(
	controller: ^completion.Controller,
	initial_text, target_text, replacement: string,
	request: completion.Request,
	seed: u64,
	allocator: mem.Allocator,
) -> bool {
	fail := proc(stage: string) -> bool {
		fmt.eprintf("completion acceptance stage: %s\n", stage)
		return false
	}
	buffer: editor.Buffer
	buffer_ready, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(request.scope.buffer_id),
		initial_text,
		editor.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	if !buffer_ready do return fail("buffer")
	defer editor.buffer_close(&buffer)
	bootstrap: transaction.Transaction
	bootstrap_ready, _ := transaction.transaction_begin(
		&bootstrap,
		transaction.Transaction_ID(seed + 30),
		transaction.Undo_Unit_ID(seed + 30),
		&buffer,
		transaction.Origin{kind = .Built_In, descriptor = "completion-acceptance-bootstrap"},
		"completion-acceptance-bootstrap",
		transaction.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	if !bootstrap_ready do return fail("bootstrap")
	defer transaction.transaction_close(&bootstrap)
	end, positioned, _ := transaction.transaction_position(
		&bootstrap,
		editor.Byte_Offset(len(initial_text)),
	)
	spliced, _ := transaction.transaction_splice(
		&bootstrap,
		editor.Working_Splice{start = end, end = end, replacement = replacement},
	)
	validated, _ := transaction.transaction_validate(&bootstrap)
	_, committed, _ := transaction.transaction_commit(&bootstrap)
	if !positioned || !spliced || !validated || !committed ||
	   !language_completion_expect_buffer(&buffer, 1, target_text) {
		return fail("bootstrap commit")
	}
	if len(target_text) == 0 do return fail("bootstrap target")
	synchronized: transaction.Transaction
	synchronize_ready, _ := transaction.transaction_begin(
		&synchronized,
		transaction.Transaction_ID(seed + 29),
		transaction.Undo_Unit_ID(seed + 29),
		&buffer,
		transaction.Origin{kind = .Built_In, descriptor = "completion-acceptance-sync"},
		"completion-acceptance-sync",
		transaction.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	if !synchronize_ready do return fail("synchronize")
	defer transaction.transaction_close(&synchronized)
	last, last_ok, _ := transaction.transaction_position(
		&synchronized,
		editor.Byte_Offset(len(target_text) - 1),
	)
	after_last, after_last_ok, _ := transaction.transaction_position(
		&synchronized,
		editor.Byte_Offset(len(target_text)),
	)
	respliced, _ := transaction.transaction_splice(
		&synchronized,
		editor.Working_Splice {
			start = last,
			end = after_last,
			replacement = target_text[len(target_text) - 1:],
		},
	)
	revalidated, _ := transaction.transaction_validate(&synchronized)
	_, recommitted, _ := transaction.transaction_commit(&synchronized)
	if !last_ok || !after_last_ok || !respliced || !revalidated || !recommitted ||
	   !language_completion_expect_buffer(&buffer, 2, target_text) {
		return fail("synchronized revision")
	}
	views: editor_view.Registry
	views_ready, _ := editor_view.registry_init(
		&views,
		editor_view.Registry_ID(seed + 31),
		allocator,
	)
	if !views_ready do return fail("view registry")
	defer editor_view.registry_close(&views)
	view, view_ready, _ := editor_view.create(&views, &buffer)
	if !view_ready do return fail("view")
	defer editor_view.close(&views, &view)
	point, point_ready, _ := editor.buffer_position(
		&buffer,
		editor.Byte_Offset(request.cursor_byte),
	)
	point_set, _ := editor_view.set_point(&views, view, point)
	if !point_ready || !point_set do return fail("point")
	history_store: history.Store
	history_ready, _ := history.store_init(
		&history_store,
		history.Store_ID(seed + 32),
		editor.Buffer_ID(request.scope.buffer_id),
		2,
		history.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	if !history_ready do return fail("history")
	defer history.store_close(&history_store)

	profiles: ui.Presentation_Profile_Registry
	profiles_ready, _ := ui.presentation_profile_registry_init(
		&profiles,
		ui.Presentation_Profile_Registry_ID(seed + 33),
		allocator = allocator,
	)
	if !profiles_ready do return fail("profiles")
	defer ui.presentation_profile_registry_close(&profiles)
	profile_scope, profile_scoped, _ := ui.presentation_profile_registry_scope(
		&profiles,
		.Interactive_Candidates,
	)
	profile, profile_ready, _ := ui.presentation_profile_registry_record(
		&profiles,
		profile_scope.selected,
	)
	if !profile_scoped || !profile_ready do return fail("profile")
	ui_registry: ui.Registry
	ui_ready, _ := ui.registry_init(&ui_registry, ui.Registry_ID(seed + 34), allocator = allocator)
	if !ui_ready do return fail("ui registry")
	defer ui.registry_close(&ui_registry)
	proposal, proposal_ready, _ := ui.proposal_begin(&ui_registry)
	if !proposal_ready do return fail("proposal")
	defer if proposal.state != nil do ui.proposal_abort(&proposal)
	styles := [?]ui.Style_Role {
		.List_Normal,
		.List_Current,
		.List_Emphasis,
		.Syntax_String,
		.Syntax_Function,
		.Syntax_Constructor,
		.Syntax_Constant,
		.Syntax_Type,
		.Syntax_Label,
		.Syntax_Attribute,
		.Syntax_Keyword,
		.Popup_Background,
		.Popup_Border,
		.Popup_Content,
		.Popup_Diagnostic,
		.Popup_Unavailable,
	}
	for style in styles {
		_, added, _ := ui.proposal_add_style(&proposal, style)
		if !added do return fail("proposal style")
	}
	_, projected, projection_failure := completion.controller_project_candidates(
		controller,
		&proposal,
		completion.Presentation_Request {
			presentation_generation = 1,
			viewport_items = 5,
			row_bytes = 80,
			profile = profile,
		},
		allocator,
	)
	if !projected {
		inspection, inspected, _ := completion.controller_inspect(controller)
		fmt.eprintf(
			"completion projection: failure=%v inspected=%t state=%v candidates=%d filtered=%d selected=%d projection=%d batch=%d/%d\n",
			projection_failure.code,
			inspected,
			inspection.state,
			inspection.candidate_count,
			inspection.filtered_candidate_count,
			u64(inspection.selected_candidate),
			u64(inspection.projection_generation),
			u64(inspection.batch_id),
			u64(inspection.batch_generation),
		)
		return fail("projection")
	}

	scope, acceptance_scoped, _ := completion.controller_acceptance_scope(controller)
	if !acceptance_scoped do return fail("acceptance scope")
	logical, logical_ready, _ := editor_view.snapshot(&views, view)
	if !logical_ready do return fail("logical view")
	accepted, acceptance_ready, acceptance_failure := completion.controller_accept_candidate(
		controller,
		scope,
		completion.Acceptance_Target {
			buffer = &buffer,
			view_registry = &views,
			view = view,
			history_store = &history_store,
			transaction_id = transaction.Transaction_ID(seed + 35),
			undo_unit_id = transaction.Undo_Unit_ID(seed + 35),
			allocators = {
				persistent = allocator,
				temporary = context.temp_allocator,
			},
			transaction_limits = transaction.DEFAULT_LIMITS,
			desired_display_column = logical.desired_display_column,
			writable = true,
		},
	)
	if !acceptance_ready || accepted.result_revision != 3 {
		fmt.eprintf(
			"completion acceptance publish: accepted=%t revision=%d completion=%v transaction=%v\n",
			acceptance_ready,
			u64(accepted.result_revision),
			acceptance_failure.completion.code,
			acceptance_failure.transaction.code,
		)
		return fail("acceptance publish")
	}
	expected := "# completion\nalpha\nalpha_value\n"
	if !language_completion_expect_buffer(&buffer, 3, expected) do return fail("accepted text")
	_, undone, _ := transaction.transaction_history_navigate(
		&history_store,
		&buffer,
		.Undo,
		transaction.Transaction_ID(seed + 36),
		transaction.Undo_Unit_ID(seed + 36),
		transaction.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
		transaction.DEFAULT_LIMITS,
		&views,
		view,
	)
	if !undone || !language_completion_expect_buffer(&buffer, 4, target_text) do return fail("undo")
	_, redone, _ := transaction.transaction_history_navigate(
		&history_store,
		&buffer,
		.Redo,
		transaction.Transaction_ID(seed + 37),
		transaction.Undo_Unit_ID(seed + 37),
		transaction.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
		transaction.DEFAULT_LIMITS,
		&views,
		view,
	)
	return redone && language_completion_expect_buffer(&buffer, 5, expected)
}

language_completion_expect_buffer :: proc(
	buffer: ^editor.Buffer,
	revision: editor.Revision,
	expected: string,
) -> bool {
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	if !stats_ok || stats.revision != revision || stats.text_bytes != u64(len(expected)) {
		return false
	}
	text, allocation_error := make([]byte, len(expected))
	if allocation_error != nil do return false
	defer delete(text)
	copied, copied_ok, _ := editor.buffer_inspect(
		buffer,
		0,
		editor.Byte_Offset(len(expected)),
		text,
	)
	return copied_ok && copied == u64(len(expected)) && string(text) == expected
}
