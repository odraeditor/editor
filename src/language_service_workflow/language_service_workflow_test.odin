// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service_workflow

import "../editor"
import "../editor_session"
import "../language"
import "../language_service"
import "../project"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

/* Verifies syntax ownership wins while service-only languages remain visible. */
@(test)
projects_language_context_without_presentation_ownership :: proc(t: ^testing.T) {
	odin, odin_ready := language.factory_bundle_registration(language.FACTORY_ODIN_BUNDLE_IDENTITY)
	testing.expect(t, odin_ready)
	if !odin_ready do return
	racket := language.Language_Identity {
		id = language.FACTORY_RACKET_LANGUAGE_ID,
		generation = language.FACTORY_LANGUAGE_GENERATION,
	}
	racket.name.length = u16(copy(racket.name.bytes[:], "racket"))
	service := Language_Service_Visible_Observation {
		present = true,
		language = racket,
		health = .Active,
	}
	syntax_projection := Language_Service_Workflow_Project_Language_Context(
		language.Language_Selection_Inspection {
			association = {language = odin.language},
			selection_generation = 7,
		},
		true,
		service,
	)
	testing.expect(t, syntax_projection.present)
	testing.expect_value(t, syntax_projection.language.id, language.FACTORY_ODIN_LANGUAGE_ID)
	testing.expect_value(t, syntax_projection.owner_generation, u64(7))
	testing.expect_value(t, syntax_projection.service_health, Language_Service_Workflow_Phase.Active)

	service_projection := Language_Service_Workflow_Project_Language_Context({}, false, service)
	testing.expect(t, service_projection.present)
	testing.expect_value(t, service_projection.language.id, language.FACTORY_RACKET_LANGUAGE_ID)
	testing.expect_value(
		t,
		service_projection.owner_generation,
		u64(language.FACTORY_LANGUAGE_GENERATION),
	)
}

/* Verifies an ordinary Dir cannot activate a retained Project language-service scope. */
@(test)
rejects_ordinary_dir_scope :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-language-dir-scope-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil {
		return
	}
	defer {
		os.remove_all(root)
		delete(root)
	}
	session: editor_session.Session
	session_handle, session_ready, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(9_000),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, session_ready)
	if !session_ready {
		return
	}
	defer editor_session.session_close(&session)
	created, project_ready, _ := editor_session.session_replace_project(
		&session,
		editor_session.Project_Update_Request {
			session = session_handle,
			project_id = project.Project_ID(9_010),
			name = "Retained Project",
			directories = []project.Directory_Proposal{{path = root, trust = .Trusted}},
			temporary = true,
		},
	)
	testing.expect(t, project_ready)
	if !project_ready {
		return
	}
	_, root_ready, _ := editor_session.session_roots_replace(
		&session,
		editor_session.Root_Replace_Request {
			session = session_handle,
			roots = []editor_session.Root_Proposal{{kind = .Dir, path = root}},
		},
	)
	testing.expect(t, root_ready)
	workflow: Language_Service_Workflow_State
	workflow_ready, _ := Language_Service_Workflow_Init(&workflow)
	testing.expect(t, workflow_ready)
	if !workflow_ready {
		return
	}
	defer Language_Service_Workflow_Close(&workflow)
	Language_Service_Workflow_Reconcile(
		&workflow,
		nil,
		&session,
		session_handle,
		context.temp_allocator,
	)
	testing.expect_value(t, len(workflow.sessions), 0)
	_, accessible, access_failure := editor_session.session_project_registry_access(
		&session,
		session_handle,
		created.active.handle,
	)
	testing.expect(t, !accessible)
	testing.expect_value(t, access_failure.code, editor_session.Failure_Code.Project_Scope)
}

/* Verifies maintained Odin and Racket services run and fail independently in one Project. */
@(test)
maintained_services_run_concurrently_and_fail_independently :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	root, root_error := os.make_directory_temp("", "odra-maintained-services-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	defer {
		os.remove_all(root)
		delete(root)
	}
	odin_path, odin_path_error := os.join_path({root, "main.odin"}, context.allocator)
	racket_path, racket_path_error := os.join_path({root, "main.rkt"}, context.allocator)
	marker_path, marker_path_error := os.join_path({root, "info.rkt"}, context.allocator)
	testing.expect(t, odin_path_error == nil && racket_path_error == nil && marker_path_error == nil)
	if odin_path_error != nil || racket_path_error != nil || marker_path_error != nil {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	defer {
		delete(odin_path)
		delete(racket_path)
		delete(marker_path)
	}
	testing.expect(t, os.write_entire_file(odin_path, "package main\n\nmain :: proc() {}\n") == nil)
	testing.expect(t, os.write_entire_file(racket_path, "#lang racket/base\n(define answer 42)\n") == nil)
	testing.expect(t, os.write_entire_file(marker_path, "#lang info\n") == nil)

	session: editor_session.Session
	session_handle, session_ready, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(9_002),
		editor_session.Allocator_Set {
			persistent = allocator,
			temporary = context.temp_allocator,
		},
	)
	syntax: ^Syntax_Workflow_State
	syntax_ready := false
	workflow: Language_Service_Workflow_State
	workflow_ready := false
	defer {
		if workflow_ready do Language_Service_Workflow_Close(&workflow)
		if syntax_ready do syntax_workflow_close(syntax)
		if syntax != nil do free(syntax, allocator)
		if session_ready do language_service_test_session_close(&session, session_handle)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
	testing.expect(t, session_ready)
	if !session_ready do return
	odin_entry, odin_opened, odin_open_failure := editor_session.session_open_path(
		&session,
		editor_session.Open_Path_Request {
			session = session_handle,
			path = odin_path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	racket_entry, racket_opened, racket_open_failure := editor_session.session_open_path(
		&session,
		editor_session.Open_Path_Request {
			session = session_handle,
			path = racket_path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expectf(t, odin_opened, "Odin document open failed: %v", odin_open_failure.code)
	testing.expectf(t, racket_opened, "Racket document open failed: %v", racket_open_failure.code)
	if !odin_opened || !racket_opened do return
	_, project_ready, project_failure := editor_session.session_replace_project(
		&session,
		editor_session.Project_Update_Request {
			session = session_handle,
			project_id = project.Project_ID(9_012),
			name = "Maintained Services",
			directories = []project.Directory_Proposal{{path = root, trust = .Trusted}},
			temporary = true,
		},
	)
	testing.expectf(t, project_ready, "concurrent Project failed: %v", project_failure.code)
	if !project_ready do return

	allocation_error: runtime.Allocator_Error
	syntax, allocation_error = new(Syntax_Workflow_State, allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	syntax_ready, _ = syntax_workflow_init(syntax, allocator)
	testing.expect(t, syntax_ready)
	if !syntax_ready do return
	workflow_ready, _ = Language_Service_Workflow_Init(&workflow, allocator)
	testing.expect(t, workflow_ready)
	if !workflow_ready do return
	configuration := transmute([]u8)(string(`{"languages":[],"schema":1,"selections":[],"services":[]}`))
	candidate, prepared := Language_Support_Workflow_Prepare(
		syntax,
		&workflow,
		configuration,
		1,
		allocator,
	)
	testing.expect(t, prepared)
	if !prepared do return
	published := Language_Support_Workflow_Publish(&candidate, syntax, &workflow)
	closed := Language_Support_Workflow_Candidate_Close(&candidate, &workflow)
	testing.expect(t, published && closed)
	if !published || !closed do return
	_, syntax_failure := syntax_workflow_reconcile(
		syntax,
		&session,
		session_handle,
		context.temp_allocator,
	)
	testing.expect_value(t, syntax_failure.code, editor_session.Failure_Code.None)
	_ = Language_Service_Workflow_Reconcile(
		&workflow,
		syntax,
		&session,
		session_handle,
		context.temp_allocator,
	)
	both_active := false
	for _ in 0 ..< 10_000 {
		_ = Language_Service_Workflow_Maintain(&workflow)
		odin_index, odin_found := maintained_service_session_index(
			&workflow,
			language.FACTORY_ODIN_LANGUAGE_ID,
		)
		racket_index, racket_found := maintained_service_session_index(
			&workflow,
			language.FACTORY_RACKET_LANGUAGE_ID,
		)
		if odin_found && racket_found && workflow.sessions[odin_index].phase == .Active &&
		   workflow.sessions[racket_index].phase == .Active {
			both_active = true
			break
		}
		time.sleep(time.Millisecond)
	}
	testing.expectf(t, both_active, "maintained services did not become concurrent: sessions=%d", len(workflow.sessions))
	if !both_active do return
	_ = Language_Service_Workflow_Reconcile(
		&workflow,
		syntax,
		&session,
		session_handle,
		context.temp_allocator,
	)
	odin_index, odin_found := maintained_service_session_index(
		&workflow,
		language.FACTORY_ODIN_LANGUAGE_ID,
	)
	racket_index, racket_found := maintained_service_session_index(
		&workflow,
		language.FACTORY_RACKET_LANGUAGE_ID,
	)
	testing.expect(t, odin_found && racket_found)
	if !odin_found || !racket_found do return
	testing.expect_value(t, len(workflow.sessions[odin_index].documents), 1)
	testing.expect_value(t, len(workflow.sessions[racket_index].documents), 1)

	odin_access, odin_accessible, _ := editor_session.session_entry_access(&session, odin_entry.entry)
	odin_borrow, odin_borrowed, _ := editor_session.entry_access_borrow(odin_access)
	racket_access, racket_accessible, _ := editor_session.session_entry_access(&session, racket_entry.entry)
	racket_borrow, racket_borrowed, _ := editor_session.entry_access_borrow(racket_access)
	testing.expect(t, odin_accessible && odin_borrowed && racket_accessible && racket_borrowed)
	if !odin_borrowed || !racket_borrowed do return
	inspected_buffers := [?]^editor.Buffer{odin_borrow.buffer, racket_borrow.buffer}
	for inspected_buffer in inspected_buffers {
		inspection: Language_Service_Inspection_Workflow_State
		captured := Language_Service_Inspection_Workflow_Capture(
			&inspection,
			&workflow,
			inspected_buffer,
			allocator,
			context.temp_allocator,
		)
		testing.expect(t, captured)
		if captured {
			testing.expect(t, strings.contains(inspection.rows[5], "total=2 active=2"))
			testing.expect(t, strings.contains(inspection.rows[1], "Odra maintained language support"))
		}
		Language_Service_Inspection_Workflow_Reset(&inspection)
	}

	racket_process, racket_process_ok := language_service.process_session_inspect(
		&workflow.sessions[racket_index].process,
	)
	testing.expect(t, racket_process_ok)
	if !racket_process_ok do return
	pid := fmt.aprintf("%d", racket_process.process.os_process_id, allocator = context.temp_allocator)
	killer, kill_start_error := os.process_start(os.Process_Desc {
		command = []string{"/bin/kill", "-9", pid},
	})
	testing.expect(t, kill_start_error == nil)
	if kill_start_error != nil do return
	kill_state, kill_wait_error := os.process_wait(killer)
	testing.expect(t, kill_wait_error == nil && kill_state.exited && kill_state.exit_code == 0)
	if kill_wait_error != nil || !kill_state.exited || kill_state.exit_code != 0 do return
	racket_failed := false
	for _ in 0 ..< 2_000 {
		_ = Language_Service_Workflow_Maintain(&workflow)
		if workflow.sessions[racket_index].phase == .Failed {
			racket_failed = true
			break
		}
		time.sleep(time.Millisecond)
	}
	testing.expect(t, racket_failed)
	testing.expect_value(t, workflow.sessions[odin_index].phase, Language_Service_Workflow_Phase.Active)
}

@(private)
maintained_service_session_index :: proc(
	workflow: ^Language_Service_Workflow_State,
	language_id: language.Language_ID,
) -> (int, bool) {
	if workflow == nil do return 0, false
	for owner, index in workflow.sessions {
		if owner.live && owner.language.id == language_id do return index, true
	}
	return 0, false
}

/* Verifies the application coordinator activates one data-defined trusted Project service. */
@(test)
coordinates_a_generic_fixture_process :: proc(t: ^testing.T) {
	root, root_error := os.get_absolute_path("tests/fixtures/ols", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer delete(root)
	path, path_error := os.join_path({root, "main.odin"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	server, server_error := os.get_absolute_path(
		"tests/fixtures/language-service-server.rkt",
		context.allocator,
	)
	testing.expect(t, server_error == nil)
	if server_error != nil do return
	defer delete(server)

	session: editor_session.Session
	session_handle, session_ready, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(9_001),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, session_ready)
	if !session_ready do return
	_, opened, open_failure := editor_session.session_open_path(
		&session,
		editor_session.Open_Path_Request {
			session = session_handle,
			path = path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expectf(t, opened, "fixture open failed: %v", open_failure.code)
	if !opened {
		editor_session.session_close(&session)
		return
	}
	directories := [1]project.Directory_Proposal{{path = root, trust = .Trusted}}
	_, project_ready, project_failure := editor_session.session_replace_project(
		&session,
		editor_session.Project_Update_Request {
			session = session_handle,
			project_id = project.Project_ID(9_011),
			name = "Language Service Fixture",
			directories = directories[:],
			temporary = true,
		},
	)
	testing.expectf(t, project_ready, "fixture Project failed: %v", project_failure.code)
	if !project_ready {
		language_service_test_session_close(&session, session_handle)
		return
	}

	syntax, syntax_allocation_error := new(Syntax_Workflow_State, context.allocator)
	testing.expect(t, syntax_allocation_error == nil)
	if syntax_allocation_error != nil {
		language_service_test_session_close(&session, session_handle)
		return
	}
	defer free(syntax, context.allocator)
	syntax_ready, syntax_failure := syntax_workflow_init(syntax)
	testing.expectf(t, syntax_ready, "syntax workflow failed: %v", syntax_failure.code)
	if !syntax_ready {
		language_service_test_session_close(&session, session_handle)
		return
	}
	defer syntax_workflow_close(syntax)
	_, syntax_reconcile_failure := syntax_workflow_reconcile(
		syntax,
		&session,
		session_handle,
		context.temp_allocator,
	)
	testing.expect_value(t, syntax_reconcile_failure.code, editor_session.Failure_Code.None)

	workflow: Language_Service_Workflow_State
	workflow_ready, workflow_failure := Language_Service_Workflow_Init(&workflow)
	testing.expectf(t, workflow_ready, "language service workflow failed: %v", workflow_failure.code)
	if !workflow_ready {
		language_service_test_session_close(&session, session_handle)
		return
	}
	defer Language_Service_Workflow_Close(&workflow)
	arguments := [2]string{server, "lsp"}
	languages := [1]string{"odin"}
	replacement, replaced, replacement_failure := language_service.provider_registry_replace(
		&workflow.registry,
		workflow.factory,
		language_service.Definition_Proposal {
			kind = .Native,
			name = "fixture-language-service",
			executable = "racket",
			arguments = arguments[:],
			root_policy = .Project_Membership,
			languages = languages[:],
			initialization_options = `{"profile":"fixture"}`,
			client_settings = `{"fixture":{"enabled":true}}`,
			feature_policy = {.Diagnostics},
			requested_capabilities = {
				.Initialize,
				.Shutdown,
				.Full_Synchronization,
				.Save_Notification,
				.Push_Diagnostics,
				.Log_Message,
			},
			preferred_encoding = .UTF_16,
			preferred_sync = .Full,
			limits = language_service.DEFAULT_LIMITS,
			deadlines = language_service.DEFAULT_DEADLINES,
			restart = language_service.DEFAULT_RESTART_POLICY,
		},
		language_service.Executable_Discovery{explicit_path = "/usr/bin/racket"},
	)
	testing.expectf(t, replaced, "fixture provider failed: %v", replacement_failure.code)
	catalog_ready := false
	if replaced {
		catalog_failure: language_service.Service_Catalog_Failure
		catalog_ready, catalog_failure = language_service_workflow_test_confirm_catalog(
			&workflow,
			replacement,
			"fixture-language-service",
			1,
			2,
		)
		testing.expectf(t, catalog_ready, "fixture catalog failed: %v", catalog_failure.code)
	}
	if replaced && catalog_ready {
		Language_Service_Workflow_Reconcile(
			&workflow,
			syntax,
			&session,
			session_handle,
			context.temp_allocator,
		)
		active := false
		for _ in 0 ..< 2_000 {
			Language_Service_Workflow_Maintain(&workflow)
			if len(workflow.sessions) == 1 && workflow.sessions[0].phase == .Active {
				active = true
				break
			}
			time.sleep(time.Millisecond)
		}
		phase := Language_Service_Workflow_Phase.None
		service_failure := language_service.Failure_Context{}
		if len(workflow.sessions) == 1 {
			phase = workflow.sessions[0].phase
			service_failure = workflow.sessions[0].latest_failure
		}
		standard_error: [4 * 1_024]u8
		standard_error_bytes := 0
		if len(workflow.sessions) == 1 && workflow.sessions[0].process.state != nil {
			standard_error_bytes, _ = language_service.process_session_copy_stderr(
				&workflow.sessions[0].process,
				standard_error[:],
			)
		}
		testing.expectf(
			t,
			active,
			"fixture service did not activate: sessions=%d phase=%v failure=%v resource=%v stderr=%q",
			len(workflow.sessions),
			phase,
			service_failure.code,
			service_failure.resource,
			string(standard_error[:standard_error_bytes]),
		)
		if active {
			testing.expect_value(t, workflow.sessions[0].definition, replacement)
			testing.expect_value(t, workflow.sessions[0].language.id, language.FACTORY_ODIN_LANGUAGE_ID)
			testing.expect_value(
				t,
				workflow.sessions[0].catalog_generation,
				language_service.Service_Catalog_Generation(2),
			)
			testing.expect_value(t, workflow.sessions[0].root, root)
			profile_messages_applied := false
			for _ in 0 ..< 2_000 {
				Language_Service_Workflow_Maintain(&workflow)
				profile_standard_error: [4 * 1_024]u8
				profile_standard_error_bytes, copied := language_service.process_session_copy_stderr(
					&workflow.sessions[0].process,
					profile_standard_error[:],
				)
				if copied {
					profile_log := string(profile_standard_error[:profile_standard_error_bytes])
					if strings.contains(profile_log, "initialization-options-applied") &&
					   strings.contains(profile_log, "settings-applied") {
						profile_messages_applied = true
						break
					}
				}
				time.sleep(time.Millisecond)
			}
			testing.expect(t, profile_messages_applied)
			Language_Service_Workflow_Reconcile(
				&workflow,
				syntax,
				&session,
				session_handle,
				context.temp_allocator,
			)
			testing.expectf(
				t,
				len(workflow.sessions[0].documents) == 1,
				"fixture document did not bind: failure=%v resource=%v",
				workflow.sessions[0].latest_failure.code,
				workflow.sessions[0].latest_failure.resource,
			)
			inspection, inspected := language_service.document_synchronizer_inspect(
				&workflow.sessions[0].synchronizer,
			)
			testing.expect(t, inspected)
			if inspected do testing.expect_value(t, inspection.documents, u32(1))
			if len(workflow.sessions[0].documents) == 1 {
				binding := workflow.sessions[0].documents[0].binding
				document_binding, bound, _ := language_service.document_synchronizer_binding(
					&workflow.sessions[0].synchronizer,
					binding,
				)
				uri, uri_ok, _ := language_service.document_synchronizer_uri(
					&workflow.sessions[0].synchronizer,
					binding,
				)
				testing.expect(t, bound && uri_ok)
				items := [2]language_service.Diagnostic_Item_Proposal {
					{
						start = {line = 0, character = 0},
						end = {line = 0, character = 7},
						has_severity = true,
						severity = .Warning,
						message = "package warning",
						source = "fixture",
						code = "W1",
						field_count = 7,
					},
					{
						start = {line = 2, character = 0},
						end = {line = 2, character = 4},
						has_severity = true,
						severity = .Error,
						message = "main error",
						source = "fixture",
						code = "E1",
						field_count = 7,
					},
				}
				_, published, publication_failure := language_service.diagnostic_store_publish(
					&workflow.sessions[0].diagnostics,
					&workflow.sessions[0].synchronizer,
					language_service.Diagnostic_Batch_Proposal {
						binding = binding,
						uri = uri,
						has_version = true,
						document_version = document_binding.document_version,
						items = items[:],
					},
				)
				testing.expectf(
					t,
					published,
					"fixture diagnostics failed: %v",
					publication_failure.code,
				)
				if published {
					source, source_ok, source_failure := Language_Service_Workflow_Diagnostic_Source(
						&workflow,
						41,
						context.temp_allocator,
					)
					testing.expectf(t, source_ok, "diagnostic source failed: %v", source_failure.code)
					if source_ok {
						testing.expect_value(t, len(source.source.definition.descriptors), 2)
						if len(source.source.definition.descriptors) == 2 {
							testing.expect_value(
								t,
								source.source.definition.descriptors[0].label,
								"main error",
							)
							entry, start, resolved := Language_Service_Workflow_Resolve_Diagnostic_Action(
								&workflow,
								source.source.definition.descriptors[0].action,
							)
							testing.expect(t, resolved)
							testing.expect_value(
								t,
								entry,
								workflow.sessions[0].documents[0].entry,
							)
							testing.expect_value(t, start, u64(14))
						}
						Language_Service_Diagnostic_Source_Close(&source)
					}
				}
			}
			stable_handle := workflow.sessions[0].handle
			stable_process, stable_process_ok := language_service.process_session_inspect(
				&workflow.sessions[0].process,
			)
			unchanged_catalog, unchanged_failure := language_service_workflow_test_confirm_catalog(
				&workflow,
				replacement,
				"fixture-language-service",
				2,
				3,
			)
			testing.expectf(t, unchanged_catalog, "unchanged catalog failed: %v", unchanged_failure.code)
			if unchanged_catalog {
				Language_Service_Workflow_Reconcile(
					&workflow,
					syntax,
					&session,
					session_handle,
					context.temp_allocator,
				)
				testing.expect_value(t, len(workflow.sessions), 1)
				if len(workflow.sessions) == 1 {
					retained_process, retained_process_ok := language_service.process_session_inspect(
						&workflow.sessions[0].process,
					)
					testing.expect(t, stable_process_ok && retained_process_ok)
					testing.expect_value(t, workflow.sessions[0].handle, stable_handle)
					testing.expect_value(
						t,
						workflow.sessions[0].catalog_generation,
						language_service.Service_Catalog_Generation(3),
					)
					if stable_process_ok && retained_process_ok {
						testing.expect_value(
							t,
							retained_process.process.os_process_id,
							stable_process.process.os_process_id,
						)
					}
				}
			}
			entry_access, accessible, _ := editor_session.session_active_entry_access(
				&session,
				session_handle,
			)
			entry, borrowed, _ := editor_session.entry_access_borrow(entry_access)
			testing.expect(t, accessible && borrowed)
			if borrowed {
				inspection_state: Language_Service_Inspection_Workflow_State
				captured := Language_Service_Inspection_Workflow_Capture(
					&inspection_state,
					&workflow,
					entry.buffer,
					context.allocator,
					context.temp_allocator,
				)
				testing.expect(t, captured)
				if captured {
					catalog: language_service.Service_Catalog_Inspection
					catalog_ok, _ := language_service.service_catalog_inspect(
						&workflow.catalog,
						&catalog,
					)
					testing.expect(t, catalog_ok)
					testing.expect_value(
						t,
						len(inspection_state.rows),
						LANGUAGE_SERVICE_INSPECTION_BASE_ROWS + int(catalog.definition_count) +
							int(catalog.selection_count) + int(catalog.conflict_count) + 1,
					)
					testing.expect(t, len(inspection_state.rows[0]) > 0)
					testing.expect(t, len(inspection_state.rows[8]) > 0)
					testing.expect(t, len(inspection_state.rows[18]) > 0)
				}
				Language_Service_Inspection_Workflow_Reset(&inspection_state)
			}

			arguments[1] = "crash"
			crash_definition, crash_selected, crash_failure := language_service.provider_registry_replace(
				&workflow.registry,
				replacement,
				language_service.Definition_Proposal {
					kind = .Native,
					name = "crashing-fixture-language-service",
					executable = "racket",
					arguments = arguments[:],
					root_policy = .Project_Membership,
					languages = languages[:],
					initialization_options = `{}`,
					client_settings = `{}`,
					feature_policy = {.Diagnostics},
					requested_capabilities = {
						.Initialize,
						.Shutdown,
						.Full_Synchronization,
						.Save_Notification,
						.Push_Diagnostics,
						.Log_Message,
					},
					preferred_encoding = .UTF_16,
					preferred_sync = .Full,
					limits = language_service.DEFAULT_LIMITS,
					deadlines = language_service.DEFAULT_DEADLINES,
					restart = language_service.DEFAULT_RESTART_POLICY,
				},
				language_service.Executable_Discovery{explicit_path = "/usr/bin/racket"},
			)
			testing.expectf(t, crash_selected, "crash provider failed: %v", crash_failure.code)
			crash_catalog_ready := false
			if crash_selected {
				catalog_failure: language_service.Service_Catalog_Failure
				crash_catalog_ready, catalog_failure = language_service_workflow_test_confirm_catalog(
					&workflow,
					crash_definition,
					"crashing-fixture-language-service",
					3,
					4,
				)
				testing.expectf(t, crash_catalog_ready, "crash catalog failed: %v", catalog_failure.code)
			}
			if crash_selected && crash_catalog_ready && borrowed {
				Language_Service_Workflow_Reconcile(
					&workflow,
					syntax,
					&session,
					session_handle,
					context.temp_allocator,
				)
				stats, stats_ok, _ := editor.buffer_stats(entry.buffer)
				testing.expect(t, stats_ok)
				failed := false
				for _ in 0 ..< 2_000 {
					Language_Service_Workflow_Maintain(&workflow)
					owner_index, owner_found := Language_Service_Workflow_Session_For_Buffer(
						&workflow,
						stats.buffer_id,
					)
					if owner_found && workflow.sessions[owner_index].phase == .Failed {
						process, process_ok := language_service.process_session_inspect(
							&workflow.sessions[owner_index].process,
						)
						if process_ok && process.process.state == .Reaped {
							failed = true
							break
						}
					}
					time.sleep(time.Millisecond)
				}
				testing.expect(t, failed)
				if failed {
					testing.expect_value(t, len(workflow.sessions), 2)
					fallback_retained := false
					for candidate in workflow.sessions {
						if candidate.phase == .Active && candidate.fallback &&
						   candidate.reconciliation == .Replacement_Fallback {
							fallback_retained = true
						}
					}
					testing.expect(t, fallback_retained)
					restarted, restart_failure := Language_Service_Workflow_Restart(
						&workflow,
						stats.buffer_id,
					)
					testing.expectf(t, restarted, "explicit restart failed: %v", restart_failure.code)
					if restarted {
						failed_again := false
						for _ in 0 ..< 2_000 {
							Language_Service_Workflow_Maintain(&workflow)
							owner_index, owner_found := Language_Service_Workflow_Session_For_Buffer(
								&workflow,
								stats.buffer_id,
							)
							if owner_found && workflow.sessions[owner_index].phase == .Failed {
								process, process_ok := language_service.process_session_inspect(
									&workflow.sessions[owner_index].process,
								)
								if process_ok && process.process.state == .Reaped {
									failed_again = true
									break
								}
							}
							time.sleep(time.Millisecond)
						}
						testing.expect(t, failed_again)
						if failed_again {
							_, repeated_failure := Language_Service_Workflow_Restart(
								&workflow,
								stats.buffer_id,
							)
							testing.expect_value(
								t,
								repeated_failure.code,
								language_service.Failure_Code.Restart_Exhausted,
							)
						}
					}
				}
			}
		}
	}
	active_project, project_inspected, project_inspection_failure :=
		editor_session.session_active_project(&session, session_handle)
	testing.expectf(
		t,
		project_inspected && active_project.active,
		"active Project inspection failed: %v",
		project_inspection_failure.code,
	)
	if project_inspected && active_project.active {
		untrusted_directories := [1]project.Directory_Proposal{{path = root, trust = .Untrusted}}
		_, revoked, revocation_failure := editor_session.session_replace_project(
			&session,
			editor_session.Project_Update_Request {
				session = session_handle,
				expected = active_project.descriptor.handle,
				project_id = active_project.descriptor.handle.id,
				name = "Language Service Fixture",
				directories = untrusted_directories[:],
				temporary = true,
			},
		)
		testing.expectf(t, revoked, "fixture trust revocation failed: %v", revocation_failure.code)
		if revoked {
			Language_Service_Workflow_Reconcile(
				&workflow,
				syntax,
				&session,
				session_handle,
				context.temp_allocator,
			)
			testing.expect_value(t, len(workflow.sessions), 0)
		}
	}
	Language_Service_Workflow_Close(&workflow)
	syntax_workflow_close(syntax)
	testing.expect(t, language_service_test_session_close(&session, session_handle))
}

@(private)
language_service_test_session_close :: proc(
	session: ^editor_session.Session,
	handle: editor_session.Session_Handle,
) -> bool {
	for _ in 0 ..< int(editor_session.MAX_LIVE_BUFFERS) {
		descriptors, copied, _ := editor_session.session_descriptors(session, handle)
		if !copied do return false
		if len(descriptors.descriptors) == 0 {
			editor_session.descriptor_batch_close(&descriptors)
			closed, _ := editor_session.session_close(session)
			return closed
		}
		entry := descriptors.descriptors[0].graph.entry
		editor_session.descriptor_batch_close(&descriptors)
		detached: editor_session.Detached_Entry
		_, detached_ok, _ := editor_session.session_entry_detach(session, entry, &detached)
		if !detached_ok do return false
		_, cleaned, _ := editor_session.detached_entry_cleanup(&detached)
		if !cleaned do return false
		released, _ := editor_session.detached_entry_release(&detached)
		if !released do return false
	}
	return false
}

@(private)
language_service_workflow_test_confirm_catalog :: proc(
	workflow: ^Language_Service_Workflow_State,
	selected: language_service.Definition_Handle,
	identity: string,
	expected, generation: language_service.Service_Catalog_Generation,
) -> (bool, language_service.Service_Catalog_Failure) {
	registration, registered := language.factory_bundle_registration(
		language.FACTORY_ODIN_BUNDLE_IDENTITY,
	)
	if !registered do return false, {code = .Invalid_Language}
	languages := [?]language.Language_Identity{registration.language}
	definitions := [?]language_service.Service_Catalog_Definition_Candidate {
		{
			definition = workflow.factory,
			identity = language_service.FACTORY_OLS_IDENTITY,
			languages = languages[:],
			source = .Factory,
			scope_kind = .Global,
			source_generation = 1,
			policy = {enabled = true, default_selection = true},
			provenance = "Odra factory OLS",
		},
		{
			definition = selected,
			identity = identity,
			languages = languages[:],
			source = .Personal,
			scope_kind = .Global,
			source_generation = language_service.Service_Source_Generation(generation),
			policy = {enabled = true, default_selection = true},
			provenance = "language service workflow fixture",
		},
	}
	confirmed, failure := language_service.service_catalog_confirm(
		&workflow.catalog,
		expected,
		{
			generation = generation,
			language_catalog_generation = 1,
			definitions = definitions[:],
		},
	)
	return confirmed, failure
}
