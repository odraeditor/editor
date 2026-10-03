// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package hosting

import "../bridge"
import "../editor"
import "../interaction"
import language_service "../language_service"
import edit_transaction "../transaction"
import base_runtime "base:runtime"
import endian "core:encoding/endian"
import "core:os"
import "core:strings"
import "core:testing"
import "core:thread"
import "core:time"

@(private)
PACKAGE_CATALOG_RUNTIME_TEST_SCENARIO :: i32(#config(ODRA_PACKAGE_CATALOG_RUNTIME_TEST_SCENARIO, 0))

@(private)
package_catalog_runtime_test_command :: proc(
	runtime: ^Runtime,
	root: string,
	action: u64,
	argument: string,
	confirmed: bool,
	output: []byte,
) -> (u64, bool, Failure_Context) {
	request: [40 + 4096]byte
	request_words := [?]u64{1, action, u64(len(argument)), 1 if confirmed else 0, 0}
	for value, index in request_words {
		if !endian.put_u64(request[index * 8:], .Little, value) do return 0, false, {}
	}
	copy(request[40:], transmute([]u8)argument)
	return runtime_package_catalog_command(
		runtime,
		root,
		request[:40 + len(argument)],
		output,
	)
}

@(private)
package_catalog_runtime_test_word :: proc(output: []byte, offset: int) -> u64 {
	value, ok := endian.get_u64(output[offset:], .Little)
	assert(ok)
	return value
}

@(private)
verify_package_catalog_runtime_boundary :: proc(t: ^testing.T, runtime: ^Runtime) {
	root_name := "package-catalog-runtime-default-state" if
		PACKAGE_CATALOG_RUNTIME_TEST_SCENARIO == 0 else
		"package-catalog-runtime-state"
	build_root, build_root_error := os.get_absolute_path(".build", context.allocator)
	defer delete(build_root)
	testing.expect(t, build_root_error == nil)
	if build_root_error != nil do return
	root, root_error := os.join_path({build_root, root_name}, context.allocator)
	defer delete(root)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	if PACKAGE_CATALOG_RUNTIME_TEST_SCENARIO != 2 {
		_ = os.remove_all(root)
		directory_error := os.make_directory(root)
		testing.expect(t, directory_error == nil)
		if directory_error != nil do return
	}
	defer if PACKAGE_CATALOG_RUNTIME_TEST_SCENARIO == 0 do os.remove_all(root)
	permissions_error := os.chmod(root, os.Permissions{.Read_User, .Write_User, .Execute_User})
	testing.expect(t, permissions_error == nil)
	if permissions_error != nil do return
	output: [MAX_PACKAGE_CATALOG_COMMAND_BYTES]byte
	if PACKAGE_CATALOG_RUNTIME_TEST_SCENARIO == 0 {
		output_length, transferred, transfer_failure := package_catalog_runtime_test_command(
			runtime, root, 1, "", false, output[:],
		)
		testing.expectf(t, transferred, "catalog list failed: %s", transfer_failure.diagnostic)
		if !transferred do return
		testing.expect(t, output_length >= 56)
		testing.expect_value(t, package_catalog_runtime_test_word(output[:], 16), u64(1))
		return
	}
	if PACKAGE_CATALOG_RUNTIME_TEST_SCENARIO == 2 {
		_, transferred, transfer_failure := package_catalog_runtime_test_command(
			runtime, root, 7, "org.example", false, output[:],
		)
		testing.expectf(t, transferred, "catalog restart search failed: %s", transfer_failure.diagnostic)
		if !transferred do return
		testing.expect_value(t, package_catalog_runtime_test_word(output[:], 32), u64(1))
		return
	}
	publication, publication_error := os.get_absolute_path(
		".build/package-catalog-runtime-fixture/publication",
		context.allocator,
	)
	testing.expect(t, publication_error == nil)
	if publication_error != nil do return
	defer delete(publication)
	output_length, transferred, transfer_failure := package_catalog_runtime_test_command(
		runtime,
		root,
		2,
		publication,
		false,
		output[:],
	)
	testing.expectf(
		t,
		transferred,
		"catalog preview failed: %s",
		transfer_failure.diagnostic,
	)
	if !transferred do return
	testing.expect(t, output_length >= 56)
	if output_length < 56 do return
	testing.expect_value(t, package_catalog_runtime_test_word(output[:], 0), u64(1))
	testing.expect_value(t, package_catalog_runtime_test_word(output[:], 16), u64(2))
	testing.expect(t, package_catalog_runtime_test_word(output[:], 40) > 0)

	output_length, transferred, transfer_failure = package_catalog_runtime_test_command(
		runtime, root, 3, publication, true, output[:],
	)
	testing.expectf(t, transferred, "catalog add failed: %s", transfer_failure.diagnostic)
	if !transferred do return
	testing.expect_value(t, package_catalog_runtime_test_word(output[:], 16), u64(1))
	testing.expect_value(t, package_catalog_runtime_test_word(output[:], 32), u64(1))

	output_length, transferred, transfer_failure = package_catalog_runtime_test_command(
		runtime, root, 7, "org.example", false, output[:],
	)
	testing.expectf(t, transferred, "catalog search failed: %s", transfer_failure.diagnostic)
	if !transferred do return
	testing.expect_value(t, package_catalog_runtime_test_word(output[:], 16), u64(1))
	testing.expect_value(t, package_catalog_runtime_test_word(output[:], 32), u64(1))
	identity_length := int(package_catalog_runtime_test_word(output[:], 40))
	detail_length := int(package_catalog_runtime_test_word(output[:], 48))
	detail := string(output[56 + identity_length:56 + identity_length + detail_length])
	testing.expectf(
		t,
		strings.contains(detail, "org.example.package@1.0.0"),
		"catalog search detail: %s",
		detail,
	)
}

/* Verifies enrollment and cross-process restart through one runtime process. */
@(test)
package_catalog_runtime_boundary_persists_confirmed_state :: proc(t: ^testing.T) {
	if PACKAGE_CATALOG_RUNTIME_TEST_SCENARIO == 0 do return
	runtime: Runtime
	started, start_failure := runtime_start(&runtime)
	testing.expectf(t, started, "runtime start failed: %s", start_failure.diagnostic)
	if !started do return
	defer runtime_shutdown(&runtime)
	verify_package_catalog_runtime_boundary(t, &runtime)
}

@(private)
verify_platform_roots_boundary :: proc(t: ^testing.T, runtime: ^Runtime) {
	roots, resolved, resolve_failure := runtime_platform_roots(runtime, context.allocator)
	testing.expectf(t, resolved, "platform roots failed: %s", resolve_failure.diagnostic)
	if !resolved do return
	defer platform_roots_close(&roots)

	expected_platform := Platform_Roots_Platform.Invalid
	when ODIN_OS == .Linux do expected_platform = .Linux
	when ODIN_OS == .Darwin do expected_platform = .Darwin
	when ODIN_OS == .Windows do expected_platform = .Windows
	testing.expect_value(t, roots.platform, expected_platform)
	paths := [?]string {
		roots.home,
		roots.configuration,
		roots.state,
		roots.cache,
		roots.package_data,
		roots.project_catalog,
		roots.legacy_projects,
	}
	for path in paths {
		testing.expect(t, len(path) > 0)
		testing.expect(t, os.is_absolute_path(path))
	}
}

@(private)
Named_Scenario :: struct {
	name:     string,
	scenario: i32,
}

@(private)
Keymap_Profile_Failing_Allocator :: struct {
	backing:                base_runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
keymap_profile_failing_allocator :: proc(
	state: ^Keymap_Profile_Failing_Allocator,
) -> base_runtime.Allocator {
	return base_runtime.Allocator{procedure = keymap_profile_failing_allocator_proc, data = state}
}

@(private)
keymap_profile_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: base_runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: base_runtime.Allocator_Error) {
	state := (^Keymap_Profile_Failing_Allocator)(allocator_data)
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		if state.successful_allocations >= state.fail_after {
			return nil, .Out_Of_Memory
		}
		state.successful_allocations += 1
	}
	return state.backing.procedure(
		state.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}

@(private)
Cross_Thread_Call_Result :: struct {
	runtime: ^Runtime,
	result:  i64,
	ok:      bool,
	failure: Failure_Context,
}

@(private)
Cross_Thread_Policy_Call_Result :: struct {
	runtime: ^Runtime,
	current: History_Policy_Record,
	ok:      bool,
	failure: Failure_Context,
}

@(private)
Cross_Thread_Keymap_Profile_Call_Result :: struct {
	runtime:   ^Runtime,
	allocator: base_runtime.Allocator,
	ok:        bool,
	failure:   Failure_Context,
}

@(private)
Theme_Capability_Probe :: struct {
	calls: u16,
}

@(private)
Cross_Thread_Theme_Call_Result :: struct {
	runtime: ^Runtime,
	probe:   ^Theme_Capability_Probe,
	ok:      bool,
	failure: Failure_Context,
}

@(private)
Structural_Capability_Probe :: struct {
	token: u64,
	calls: u64,
}

@(private)
Cross_Thread_Structural_Call_Result :: struct {
	runtime: ^Runtime,
	probe:   ^Structural_Capability_Probe,
	ok:      bool,
	failure: Failure_Context,
}

@(private)
Language_Service_Capability_Probe :: struct {
	token: u64,
	calls: u64,
}

@(private)
Cross_Thread_Language_Service_Call_Result :: struct {
	runtime: ^Runtime,
	probe:   ^Language_Service_Capability_Probe,
	ok:      bool,
	failure: Failure_Context,
}

@(private)
theme_capability_probe_callback :: proc "c" (
	user_data: rawptr,
	kind: Scoped_Capability_Kind,
	generation, token, domain_context: u64,
	operation: i32,
	arg0, arg1: u64,
	input: ^u8,
	input_length: u64,
	output: ^u8,
	output_capacity: u64,
	output_length, value: ^u64,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	probe := (^Theme_Capability_Probe)(user_data)
	if probe == nil || kind != .Theme || generation == 0 || token == 0 ||
	   domain_context != 0 || operation != i32(bridge.Theme_Capability_Operation.Scope) ||
	   arg0 != 0 || arg1 != 0 || input_length != 0 ||
	   output == nil || output_capacity != bridge.THEME_SCOPE_RECORD_BYTES ||
	   output_length == nil || value == nil || failure_code == nil ||
	   limit == nil || actual == nil {
		return 2
	}
	for &byte in ([^]u8)(output)[:int(output_capacity)] do byte = 0
	output_length^ = output_capacity
	value^ = 0
	failure_code^ = 0
	limit^ = 0
	actual^ = 0
	probe.calls += 1
	return 0
}

@(private)
cross_thread_theme_call :: proc(observed: ^Cross_Thread_Theme_Call_Result) {
	observed.ok, observed.failure = runtime_theme_probe(
		observed.runtime,
		0,
		441,
		theme_capability_probe_callback,
		observed.probe,
	)
}

@(private)
structural_capability_probe_callback :: proc "c" (
	user_data: rawptr,
	kind: Scoped_Capability_Kind,
	generation, token, domain_context: u64,
	operation: i32,
	arg0, arg1: u64,
	input: ^u8,
	input_length: u64,
	output: ^u8,
	output_capacity: u64,
	output_length, value: ^u64,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	probe := (^Structural_Capability_Probe)(user_data)
	if probe == nil || kind != .Structural || generation == 0 || token != probe.token ||
	   domain_context != 0 ||
	   operation != i32(bridge.Structural_Capability_Operation.Scope) ||
	   arg0 != 0 || arg1 != 0 || input_length != 0 || output == nil ||
	   output_capacity != bridge.STRUCTURAL_SCOPE_RECORD_BYTES || output_length == nil ||
	   value == nil || failure_code == nil || limit == nil || actual == nil {
		return 2
	}
	for &byte in ([^]u8)(output)[:int(output_capacity)] do byte = 0
	output_length^ = output_capacity
	value^ = 0
	failure_code^ = 0
	limit^ = 0
	actual^ = 0
	probe.calls += 1
	return 0
}

@(private)
cross_thread_structural_call :: proc(observed: ^Cross_Thread_Structural_Call_Result) {
	observed.ok, observed.failure = runtime_structural_probe(
		observed.runtime,
		0,
		observed.probe.token,
		structural_capability_probe_callback,
		observed.probe,
	)
}

@(private)
language_service_capability_probe_callback :: proc "c" (
	user_data: rawptr,
	kind: Scoped_Capability_Kind,
	generation, token, domain_context: u64,
	operation: i32,
	arg0, arg1: u64,
	input: ^u8,
	input_length: u64,
	output: ^u8,
	output_capacity: u64,
	output_length, value: ^u64,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	probe := (^Language_Service_Capability_Probe)(user_data)
	if probe == nil || kind != .Language_Service || generation == 0 || token != probe.token ||
	   domain_context != 0 ||
	   operation != i32(bridge.Language_Service_Capability_Operation.Scope) ||
	   arg0 != 0 || arg1 != 0 || input_length != 0 || output == nil ||
	   output_capacity != bridge.LANGUAGE_SERVICE_SCOPE_RECORD_BYTES || output_length == nil ||
	   value == nil || failure_code == nil || limit == nil || actual == nil {
		return 2
	}
	for &byte in ([^]u8)(output)[:int(output_capacity)] do byte = 0
	output_length^ = output_capacity
	value^ = 0
	failure_code^ = 0
	limit^ = 0
	actual^ = 0
	probe.calls += 1
	return 0
}

@(private)
cross_thread_language_service_call :: proc(observed: ^Cross_Thread_Language_Service_Call_Result) {
	observed.ok, observed.failure = runtime_language_service_probe(
		observed.runtime,
		0,
		observed.probe.token,
		language_service_capability_probe_callback,
		observed.probe,
	)
}

@(private)
cross_thread_call :: proc(observed: ^Cross_Thread_Call_Result) {
	observed.result, observed.ok, observed.failure = runtime_call_scalar(observed.runtime, 41)
}

@(private)
cross_thread_policy_call :: proc(observed: ^Cross_Thread_Policy_Call_Result) {
	_, observed.ok, observed.failure = runtime_history_policy_exchange(
		observed.runtime,
		observed.current,
	)
}

@(private)
cross_thread_keymap_profile_call :: proc(observed: ^Cross_Thread_Keymap_Profile_Call_Result) {
	candidate: Keymap_Profile_Candidate
	candidate, observed.ok, observed.failure = runtime_load_keymap_profile(
		observed.runtime,
		17,
		observed.allocator,
	)
	if observed.ok {
		keymap_profile_candidate_close(&candidate)
	}
}

@(private)
verify_keymap_profile_aggregate_counts :: proc(
	t: ^testing.T,
	view: Keymap_Profile_View,
	catalog: interaction.Profile_Catalog_Definition,
) {
	state_count := 0
	map_count := 0
	binding_count := 0
	selector_count := 0
	remap_count := 0
	ordering_count := 0
	stroke_count := 0
	for profile in catalog.profiles {
		state_count += len(profile.states)
		map_count += len(profile.maps)
		for map_definition in profile.maps {
			binding_count += len(map_definition.bindings)
			remap_count += len(map_definition.remaps)
			ordering_count += len(map_definition.ordering_constraints)
			for binding in map_definition.bindings {
				selector_count += len(binding.selectors)
				stroke_count += int(binding.sequence.stroke_count)
			}
		}
	}
	testing.expect_value(t, len(view.profiles), len(catalog.profiles))
	testing.expect_value(t, len(view.states), state_count)
	testing.expect_value(t, len(view.maps), map_count)
	testing.expect_value(t, len(view.bindings), binding_count)
	testing.expect_value(t, len(view.selectors), selector_count)
	testing.expect_value(t, len(view.surfaces), len(catalog.surfaces))
	testing.expect_value(t, len(view.remaps), remap_count)
	testing.expect_value(t, len(view.ordering), ordering_count)
	testing.expect_value(t, len(view.strokes), stroke_count)
}

/* Verifies lifecycle, exception, GC, thread, reentrancy, and shutdown containment. */
@(test)
runtime_boundary_contains_failures :: proc(t: ^testing.T) {
	runtime: Runtime

	_, called, call_failure := runtime_call_scalar(&runtime, 41)
	testing.expect(t, !called)
	testing.expect_value(t, call_failure.code, Failure_Code.Invalid_State)
	testing.expect_value(t, call_failure.phase, State.Uninitialized)

	started, start_failure := runtime_start(&runtime)
	testing.expectf(t, started, "runtime start failed: %s", start_failure.diagnostic)
	if !started {
		return
	}
	testing.expect_value(t, runtime_state(&runtime), State.Ready)
	verify_package_catalog_runtime_boundary(t, &runtime)
	verify_platform_roots_boundary(t, &runtime)

	profile_started := time.tick_now()
	profile_candidate, profile_ok, profile_failure := runtime_load_keymap_profile(
		&runtime,
		17,
		context.allocator,
	)
	profile_elapsed_ns := time.duration_nanoseconds(time.tick_since(profile_started))
	testing.expectf(t, profile_ok, "profile transfer failed: %s", profile_failure.diagnostic)
	testing.expectf(
		t,
		profile_elapsed_ns < 1_000_000_000,
		"profile transfer exceeded one second: %d ns",
		profile_elapsed_ns,
	)
	if profile_ok {
		profile, viewed := keymap_profile_candidate_view(&profile_candidate)
		testing.expect(t, viewed)
		if viewed {
			testing.expect_value(t, profile.header.schema_version, bridge.KEYMAP_PROFILE_SCHEMA_VERSION)
			testing.expect_value(t, profile.header.registry_generation, u64(17))
			testing.expect_value(t, profile.header.catalog_generation, u64(17))
			testing.expect_value(t, profile.header.active_profile_id, u64(1))
			testing.expect_value(t, profile.header.active_state_id, u64(1))
			testing.expect_value(t, len(profile.profiles), 2)
			testing.expect_value(t, len(profile.surfaces), 1)
			testing.expect(t, len(profile.strokes) >= len(profile.bindings))
			first := profile.bindings[0]
			testing.expect_value(t, first.scope, u64(interaction.Binding_Scope.Profile_Specific))
			testing.expect_value(
				t,
				string(profile.text[int(first.command_offset):int(first.command_offset + first.command_bytes)]),
				"cursor-previous-grapheme",
			)
			search_binding_found := false
			for search_binding in profile.bindings {
				command_start := int(search_binding.command_offset)
				command_end := int(search_binding.command_offset + search_binding.command_bytes)
				if string(profile.text[command_start:command_end]) != "isearch-forward" do continue
				search_source_start := int(search_binding.source_offset)
				search_source_end := int(search_binding.source_offset + search_binding.source_bytes)
				testing.expect_value(
					t,
					string(profile.text[search_source_start:search_source_end]),
					"search",
				)
				search_binding_found = true
				break
			}
			testing.expect(t, search_binding_found)
		}
		definition, adapted := keymap_profile_candidate_definition(&profile_candidate)
		testing.expect(t, adapted)
			if adapted {
			testing.expect_value(t, definition.identity.id, interaction.Profile_ID(1))
			testing.expect_value(t, definition.identity.revision, interaction.Profile_Revision(1))
			testing.expect_value(t, len(definition.states), 1)
			testing.expect_value(t, definition.initial_state, interaction.Interaction_State_ID(1))
				testing.expect_value(t, definition.states[0].name, "direct-editing")
				testing.expect(t, definition.states[0].admits_text_input)
				testing.expect_value(t, len(definition.maps), 3)
				testing.expect_value(t, definition.maps[0].name, "factory")
				testing.expect_value(t, definition.maps[1].name, "project")
				testing.expect_value(t, definition.maps[2].name, "direct-language-context")
				testing.expect_value(t, definition.maps[0].precedence, interaction.Precedence_Class.Factory_Fallback)
				testing.expect_value(t, definition.maps[1].precedence, interaction.Precedence_Class.Project)
				testing.expect_value(t, definition.maps[2].precedence, interaction.Precedence_Class.Language_Context)
			testing.expect_value(t, definition.maps[0].bindings[0].command_name, "cursor-previous-grapheme")
			testing.expect_value(t, definition.maps[0].bindings[0].scope, interaction.Binding_Scope.Profile_Specific)
		}
		catalog, catalog_adapted := keymap_profile_candidate_catalog_definition(&profile_candidate)
		testing.expect(t, catalog_adapted)
		if catalog_adapted {
			verify_keymap_profile_aggregate_counts(t, profile, catalog)
			testing.expect_value(t, catalog.generation, interaction.Profile_Catalog_Generation(17))
			testing.expect_value(t, catalog.active_profile, interaction.Profile_ID(1))
			testing.expect_value(t, catalog.active_state, interaction.Interaction_State_ID(1))
			testing.expect_value(t, len(catalog.profiles), 2)
			if len(catalog.profiles) == 2 {
				testing.expect_value(t, catalog.profiles[0].name, "direct")
				testing.expect_value(t, catalog.profiles[1].name, "modal")
				testing.expect_value(t, len(catalog.profiles[1].states), 6)
			}
			testing.expect_value(t, len(catalog.surfaces), 1)
			testing.expect_value(t, catalog.surfaces[0].name, "extended-command")
		}
		keymap_profile_candidate_close(&profile_candidate)
		_, viewed = keymap_profile_candidate_view(&profile_candidate)
		testing.expect(t, !viewed)
		keymap_profile_candidate_close(&profile_candidate)
	}

	command_candidate, command_ok, command_failure := runtime_load_command_catalog(
		&runtime,
		interaction.Registry_Generation(17),
		context.allocator,
	)
	testing.expectf(t, command_ok, "command catalog transfer failed: %s", command_failure.diagnostic)
	if command_ok {
		command_view, viewed := command_catalog_candidate_view(&command_candidate)
		testing.expect(t, viewed)
		if viewed {
			testing.expect_value(t, command_view.header.registry_generation, u64(17))
			testing.expect_value(t, command_view.header.catalog_generation, u64(17))
			testing.expect_value(t, len(command_view.records), 7)
		}
		definitions, adapted := command_catalog_candidate_definitions(&command_candidate)
		testing.expect(t, adapted)
		if adapted {
			testing.expect_value(t, len(definitions), 7)
			testing.expect_value(t, definitions[0].name, "describe-key")
			testing.expect_value(t, definitions[0].implementation, interaction.Implementation_Class.Racket)
			testing.expect_value(t, definitions[6].name, "uppercase-current-line")
			testing.expect_value(t, definitions[6].route.provider, bridge.RACKET_TRANSACTION_COMMAND_PROVIDER_ID)
		}
		command_catalog_candidate_close(&command_candidate)
		_, viewed = command_catalog_candidate_view(&command_candidate)
		testing.expect(t, !viewed)
		command_catalog_candidate_close(&command_candidate)
	}
	_, command_ok, command_failure = runtime_load_command_catalog_scenario(
		&runtime, interaction.Registry_Generation(17), context.allocator, 1,
	)
	testing.expect(t, !command_ok)
	testing.expect_value(t, command_failure.code, Failure_Code.Racket_Exception)
	command_catalog_malformed_scenarios := [?]Named_Scenario {
		{name = "invalid-schema", scenario = 2},
		{name = "duplicate-command", scenario = 3},
		{name = "invalid-capabilities", scenario = 4},
		{name = "excessive-command-count", scenario = 5},
		{name = "stale-registry", scenario = 6},
	}
	for test_case in command_catalog_malformed_scenarios {
		_, command_ok, command_failure = runtime_load_command_catalog_scenario(
			&runtime,
			interaction.Registry_Generation(17),
			context.allocator,
			test_case.scenario,
		)
		testing.expectf(t, !command_ok, "%s command catalog was accepted", test_case.name)
		testing.expectf(t, command_failure.code == .Wrong_Result, "%s command catalog returned the wrong failure", test_case.name)
	}
	extended_command_candidate, extended_command_ok, extended_command_failure :=
		runtime_load_command_catalog_scenario(
			&runtime,
			interaction.Registry_Generation(17),
			context.allocator,
			7,
		)
	testing.expectf(
		t,
		extended_command_ok,
		"extended command catalog transfer failed: %s",
		extended_command_failure.diagnostic,
	)
	if extended_command_ok {
		definitions, adapted := command_catalog_candidate_definitions(&extended_command_candidate)
		testing.expect(t, adapted)
		if adapted {
			testing.expect_value(t, len(definitions), 8)
			testing.expect_value(t, definitions[7].name, "test-lowercase-line")
		}
		command_catalog_candidate_close(&extended_command_candidate)
	}
	personal_command_candidate, personal_command_ok, personal_command_failure :=
		runtime_load_command_catalog_scenario(
			&runtime,
			interaction.Registry_Generation(17),
			context.allocator,
			8,
		)
	testing.expectf(
		t,
		personal_command_ok,
		"personal command catalog transfer failed: %s",
		personal_command_failure.diagnostic,
	)
	if personal_command_ok {
		definitions, adapted := command_catalog_candidate_definitions(&personal_command_candidate)
		testing.expect(t, adapted)
		if adapted {
			testing.expect_value(t, len(definitions), 8)
			personal := definitions[7]
			testing.expect_value(t, personal.name, "personal-normalize-heading")
			testing.expect_value(t, personal.route.provider, bridge.RACKET_PERSONAL_COMMAND_PROVIDER_ID)
			testing.expect_value(t, personal.route.operation, u16(1))
			testing.expect_value(t, personal.provenance.provider, "personal")
			testing.expect_value(t, personal.provenance.source, "modules/text.rkt")
			testing.expect_value(t, personal.provenance.location, "7:3")
		}
		command_catalog_candidate_close(&personal_command_candidate)
	}
	ksawery_command_candidate, ksawery_command_ok, ksawery_command_failure :=
		runtime_load_command_catalog_scenario(
			&runtime,
			interaction.Registry_Generation(17),
			context.allocator,
			9,
		)
	testing.expectf(
		t,
		ksawery_command_ok,
		"Ksawery command catalog transfer failed: %s",
		ksawery_command_failure.diagnostic,
	)
	if ksawery_command_ok {
		definitions, adapted := command_catalog_candidate_definitions(&ksawery_command_candidate)
		testing.expect(t, adapted)
		if adapted {
			testing.expect_value(t, len(definitions), 8)
			exts := definitions[7]
			testing.expect_value(t, exts.name, "personal.repository-tools/family.refs/action.push")
			testing.expect_value(t, exts.route.provider, bridge.RACKET_KSAWERY_COMMAND_PROVIDER_ID)
			testing.expect_value(t, exts.route.operation, u16(8))
			testing.expect_value(t, exts.provenance.provider, "personal.repository-tools")
			testing.expect_value(t, exts.provenance.source, "modules/repository-tools.rkt")
			testing.expect_value(t, exts.provenance.location, "family.refs")
		}
		command_catalog_candidate_close(&ksawery_command_candidate)
	}

	_, profile_ok, profile_failure = runtime_load_keymap_profile_scenario(
		&runtime, 17, context.allocator, 1,
	)
	testing.expect(t, !profile_ok)
	testing.expect_value(t, profile_failure.code, Failure_Code.Racket_Exception)
	malformed_scenarios := [?]Named_Scenario {
		{name = "invalid-batch", scenario = 2},
		{name = "oversized-batch", scenario = 3},
		{name = "invalid-schema", scenario = 5},
		{name = "stale-registry", scenario = 6},
		{name = "invalid-default-profile", scenario = 7},
		{name = "truncated-batch", scenario = 8},
	}
	for test_case in malformed_scenarios {
		_, profile_ok, profile_failure = runtime_load_keymap_profile_scenario(
			&runtime, 17, context.allocator, test_case.scenario,
		)
		testing.expectf(t, !profile_ok, "%s keymap profile was accepted", test_case.name)
		testing.expectf(t, profile_failure.code == .Wrong_Result, "%s keymap profile returned the wrong failure", test_case.name)
	}
	gc_candidate, gc_ok, gc_failure := runtime_load_keymap_profile_scenario(
		&runtime, 17, context.allocator, 4,
	)
	testing.expectf(t, gc_ok, "GC profile transfer failed: %s", gc_failure.diagnostic)
	if gc_ok {
		keymap_profile_candidate_close(&gc_candidate)
	}
	synthetic_candidate, synthetic_ok, synthetic_failure := runtime_load_keymap_profile_scenario(
		&runtime, 17, context.allocator, 9,
	)
	testing.expectf(t, synthetic_ok, "synthetic catalog transfer failed: %s", synthetic_failure.diagnostic)
	if synthetic_ok {
		synthetic_view, synthetic_viewed := keymap_profile_candidate_view(&synthetic_candidate)
		testing.expect(t, synthetic_viewed)
		if synthetic_viewed {
			testing.expect_value(t, len(synthetic_view.profiles), 2)
			testing.expect_value(t, len(synthetic_view.selectors), 2)
		}
		synthetic_catalog, synthetic_adapted := keymap_profile_candidate_catalog_definition(
			&synthetic_candidate,
		)
		testing.expect(t, synthetic_adapted)
		if synthetic_adapted {
			verify_keymap_profile_aggregate_counts(t, synthetic_view, synthetic_catalog)
			testing.expect_value(t, len(synthetic_catalog.profiles), 2)
			testing.expect_value(t, synthetic_catalog.profiles[1].name, "synthetic")
			testing.expect_value(t, synthetic_catalog.profiles[1].states[0].name, "synthetic-state")
			testing.expect_value(t, len(synthetic_catalog.profiles[0].maps[0].bindings[0].selectors), 2)
		}
		keymap_profile_candidate_close(&synthetic_candidate)
	}
	for fail_after in 0 ..< 7 {
		failing := Keymap_Profile_Failing_Allocator {
			backing = context.allocator,
			fail_after = u64(fail_after),
		}
		_, profile_ok, profile_failure = runtime_load_keymap_profile(
			&runtime,
			17,
			keymap_profile_failing_allocator(&failing),
		)
		testing.expectf(t, !profile_ok, "allocation fault %d unexpectedly passed", fail_after)
		testing.expect_value(t, profile_failure.code, Failure_Code.Runtime_Unavailable)
	}
	for _ in 0 ..< 8 {
		repeated_candidate, repeated_ok, repeated_failure := runtime_load_keymap_profile(
			&runtime,
			17,
			context.allocator,
		)
		testing.expectf(t, repeated_ok, "repeated transfer failed: %s", repeated_failure.diagnostic)
		if repeated_ok {
			keymap_profile_candidate_close(&repeated_candidate)
		}
	}
	runtime.call_active = true
	_, profile_ok, profile_failure = runtime_load_keymap_profile(
		&runtime, 17, context.allocator,
	)
	runtime.call_active = false
	testing.expect(t, !profile_ok)
	testing.expect_value(t, profile_failure.code, Failure_Code.Reentrant_Call)
	cross_profile := Cross_Thread_Keymap_Profile_Call_Result {
		runtime = &runtime,
		allocator = context.allocator,
	}
	cross_profile_thread := thread.create_and_start_with_poly_data(
		&cross_profile,
		cross_thread_keymap_profile_call,
	)
	testing.expect(t, cross_profile_thread != nil)
	if cross_profile_thread != nil {
		thread.join(cross_profile_thread)
		thread.destroy(cross_profile_thread)
		testing.expect(t, !cross_profile.ok)
		testing.expect_value(t, cross_profile.failure.code, Failure_Code.Wrong_Thread)
	}

	current_policy := History_Policy_Record{generation = 7}
	for index in 0..<HISTORY_POLICY_FIELD_COUNT {
		current_policy.fields[index] = u64(index + 1)
	}
	candidate_policy, policy_ok, policy_failure := runtime_history_policy_exchange(
		&runtime,
		current_policy,
	)
	testing.expectf(t, policy_ok, "history policy transfer failed: %s", policy_failure.diagnostic)
	if policy_ok {
		testing.expect_value(t, candidate_policy.generation, current_policy.generation)
		for index in 0..<HISTORY_POLICY_FIELD_COUNT {
			testing.expect_value(t, candidate_policy.fields[index], current_policy.fields[index])
		}
	}
	_, policy_ok, policy_failure = runtime_history_policy_exchange_scenario(
		&runtime, current_policy, 1,
	)
	testing.expect(t, !policy_ok)
	testing.expect_value(t, policy_failure.code, Failure_Code.Racket_Exception)
	_, policy_ok, policy_failure = runtime_history_policy_exchange_scenario(
		&runtime, current_policy, 2,
	)
	testing.expect(t, !policy_ok)
	testing.expect_value(t, policy_failure.code, Failure_Code.Wrong_Result)
	_, policy_ok, policy_failure = runtime_history_policy_exchange_scenario(
		&runtime, current_policy, 3,
	)
	testing.expectf(t, policy_ok, "forced-GC history policy transfer failed: %s", policy_failure.diagnostic)
	_, policy_ok, policy_failure = runtime_history_policy_exchange_scenario(
		&runtime, current_policy, 4,
	)
	testing.expect(t, !policy_ok)
	testing.expect_value(t, policy_failure.code, Failure_Code.Wrong_Result)

	current_display_policy := Display_Policy_Record {
		generation = 7,
		action_count = 4,
		split_height_threshold = 12,
		split_width_threshold = 40,
	}
	for action in 0..<current_display_policy.action_count {
		current_display_policy.actions[action] = action + 1
	}
	candidate_display_policy, display_policy_ok, display_policy_failure :=
		runtime_display_policy_exchange(&runtime, current_display_policy)
	testing.expectf(
		t,
		display_policy_ok,
		"display policy transfer failed: %s",
		display_policy_failure.diagnostic,
	)
	if display_policy_ok {
		testing.expect_value(t, candidate_display_policy, current_display_policy)
	}
	_, display_policy_ok, display_policy_failure = runtime_display_policy_exchange_scenario(
		&runtime, current_display_policy, 1,
	)
	testing.expect(t, !display_policy_ok)
	testing.expect_value(t, display_policy_failure.code, Failure_Code.Racket_Exception)
	_, display_policy_ok, display_policy_failure = runtime_display_policy_exchange_scenario(
		&runtime, current_display_policy, 2,
	)
	testing.expect(t, !display_policy_ok)
	testing.expect_value(t, display_policy_failure.code, Failure_Code.Wrong_Result)
	_, display_policy_ok, display_policy_failure = runtime_display_policy_exchange_scenario(
		&runtime, current_display_policy, 3,
	)
	testing.expectf(
		t,
		display_policy_ok,
		"forced-GC display policy transfer failed: %s",
		display_policy_failure.diagnostic,
	)
	_, display_policy_ok, display_policy_failure = runtime_display_policy_exchange_scenario(
		&runtime, current_display_policy, 4,
	)
	testing.expect(t, !display_policy_ok)
	testing.expect_value(t, display_policy_failure.code, Failure_Code.Wrong_Result)

	runtime.call_active = true
	_, policy_ok, policy_failure = runtime_history_policy_exchange(&runtime, current_policy)
	testing.expect(t, !policy_ok)
	testing.expect_value(t, policy_failure.code, Failure_Code.Reentrant_Call)
	runtime.call_active = false

	cross_thread_policy_result := Cross_Thread_Policy_Call_Result{
		runtime = &runtime,
		current = current_policy,
	}
	policy_worker := thread.create_and_start_with_poly_data(
		&cross_thread_policy_result,
		cross_thread_policy_call,
	)
	testing.expect(t, policy_worker != nil)
	if policy_worker != nil {
		thread.join(policy_worker)
		thread.destroy(policy_worker)
		testing.expect(t, !cross_thread_policy_result.ok)
		testing.expect_value(
			t,
			cross_thread_policy_result.failure.code,
			Failure_Code.Wrong_Thread,
		)
	}

	started, start_failure = runtime_start(&runtime)
	testing.expect(t, !started)
	testing.expect_value(t, start_failure.code, Failure_Code.Invalid_State)
	testing.expect_value(t, runtime_state(&runtime), State.Ready)

	result: i64
	result, called, call_failure = runtime_call_scalar(&runtime, 41)
	testing.expect(t, called)
	testing.expect_value(t, result, i64(42))

	_, called, call_failure = runtime_call_scalar(&runtime, max(i64))
	testing.expect(t, !called)
	testing.expect_value(t, call_failure.code, Failure_Code.Racket_Exception)
	testing.expect(t, len(call_failure.diagnostic) > 0)
	testing.expect_value(t, runtime_state(&runtime), State.Ready)

	_, called, call_failure = runtime_call_scalar_scenario(&runtime, 41, 1)
	testing.expect(t, !called)
	testing.expect_value(t, call_failure.code, Failure_Code.Racket_Exception)
	testing.expect(t, len(call_failure.diagnostic) > 0)

	_, called, call_failure = runtime_call_scalar_scenario(&runtime, 41, 2)
	testing.expect(t, !called)
	testing.expect_value(t, call_failure.code, Failure_Code.Wrong_Result)

	result, called, call_failure = runtime_call_scalar_scenario(&runtime, 41, 3)
	testing.expectf(t, called, "forced-GC call failed: %s", call_failure.diagnostic)
	testing.expect_value(t, result, i64(41))

	runtime.call_active = true
	_, called, call_failure = runtime_call_scalar(&runtime, 41)
	testing.expect(t, !called)
	testing.expect_value(t, call_failure.code, Failure_Code.Reentrant_Call)
	runtime.call_active = false

	cross_thread_result := Cross_Thread_Call_Result {runtime = &runtime}
	worker := thread.create_and_start_with_poly_data(&cross_thread_result, cross_thread_call)
	testing.expect(t, worker != nil)
	if worker != nil {
		thread.join(worker)
		thread.destroy(worker)
		testing.expect(t, !cross_thread_result.ok)
		testing.expect_value(t, cross_thread_result.failure.code, Failure_Code.Wrong_Thread)
		testing.expect_value(t, cross_thread_result.failure.phase, State.Ready)
	}

	runtime.call_active = true
	stopped, stop_failure := runtime_shutdown(&runtime)
	testing.expect(t, !stopped)
	testing.expect_value(t, stop_failure.code, Failure_Code.Reentrant_Call)
	testing.expect_value(t, runtime_state(&runtime), State.Ready)
	runtime.call_active = false

	result, called, call_failure = runtime_call_scalar(&runtime, 41)
	testing.expectf(t, called, "runtime did not recover after contained failures: %s", call_failure.diagnostic)
	testing.expect_value(t, result, i64(42))
	theme_probe: Theme_Capability_Probe
	theme_ok, theme_failure := runtime_theme_probe(
		&runtime,
		0,
		441,
		theme_capability_probe_callback,
		&theme_probe,
	)
	testing.expectf(t, theme_ok, "theme capability probe failed: %s", theme_failure.diagnostic)
	testing.expect_value(t, theme_probe.calls, u16(1))
	theme_failure_scenarios := [?]Named_Scenario {
		{name = "command-exception", scenario = 1},
		{name = "escaped-control", scenario = 2},
	}
	for test_case in theme_failure_scenarios {
		theme_ok, theme_failure = runtime_theme_probe(
			&runtime,
			test_case.scenario,
			441,
			theme_capability_probe_callback,
			&theme_probe,
		)
		testing.expectf(t, !theme_ok, "%s theme probe was accepted", test_case.name)
		testing.expectf(t, theme_failure.code == .Racket_Exception, "%s theme probe returned the wrong failure", test_case.name)
	}
	theme_ok, theme_failure = runtime_theme_probe(
		&runtime,
		0,
		441,
		theme_capability_probe_callback,
		&theme_probe,
	)
	testing.expectf(
		t,
		theme_ok,
		"theme capability did not recover after escape: %s",
		theme_failure.diagnostic,
	)
	testing.expect_value(t, theme_probe.calls, u16(2))
	cross_thread_theme := Cross_Thread_Theme_Call_Result {
		runtime = &runtime,
		probe = &theme_probe,
	}
	theme_worker := thread.create_and_start_with_poly_data(
		&cross_thread_theme,
		cross_thread_theme_call,
	)
	testing.expect(t, theme_worker != nil)
	if theme_worker != nil {
		thread.join(theme_worker)
		thread.destroy(theme_worker)
		testing.expect(t, !cross_thread_theme.ok)
		testing.expect_value(t, cross_thread_theme.failure.code, Failure_Code.Wrong_Thread)
	}
	runtime.call_active = true
	theme_ok, theme_failure = runtime_theme_probe(
		&runtime,
		0,
		441,
		theme_capability_probe_callback,
		&theme_probe,
	)
	testing.expect(t, !theme_ok)
	testing.expect_value(t, theme_failure.code, Failure_Code.Reentrant_Call)
	runtime.call_active = false
	theme_ok, theme_failure = runtime_theme_probe(
		&runtime,
		0,
		0,
		theme_capability_probe_callback,
		&theme_probe,
	)
	testing.expect(t, !theme_ok)
	testing.expect_value(t, theme_failure.code, Failure_Code.Wrong_Result)
	theme_ok, theme_failure = runtime_theme_probe(&runtime, 0, 441, nil, nil)
	testing.expect(t, !theme_ok)
	testing.expect_value(t, theme_failure.code, Failure_Code.Wrong_Result)
	verify_transaction_facade(t, &runtime)
	verify_transfer_facade(t, &runtime)
	verify_search_facade(t, &runtime)
	verify_buffer_session_facade(t, &runtime)
	verify_candidate_usage_facade(t, &runtime)
	verify_structural_facade(t, &runtime)
	verify_language_service_facade(t, &runtime)

	stopped, stop_failure = runtime_shutdown(&runtime)
	testing.expectf(t, stopped, "runtime shutdown failed: %s", stop_failure.diagnostic)
	testing.expect_value(t, runtime_state(&runtime), State.Stopped)

	_, called, call_failure = runtime_call_scalar(&runtime, 41)
	testing.expect(t, !called)
	testing.expect_value(t, call_failure.code, Failure_Code.Invalid_State)
	testing.expect_value(t, call_failure.phase, State.Stopped)

	stopped, stop_failure = runtime_shutdown(&runtime)
	testing.expect(t, !stopped)
	testing.expect_value(t, stop_failure.code, Failure_Code.Invalid_State)
	testing.expect_value(t, runtime_state(&runtime), State.Stopped)
}

/* Verifies absent load, exact publication, reload, and stale persistence containment. */
@(private)
verify_structural_facade :: proc(t: ^testing.T, runtime: ^Runtime) {
	probe := Structural_Capability_Probe{token = 447}
	called, failure := runtime_structural_probe(
		runtime,
		0,
		probe.token,
		structural_capability_probe_callback,
		&probe,
	)
	testing.expectf(t, called, "structural facade call failed: %s", failure.diagnostic)
	testing.expect_value(t, probe.calls, u64(1))

	called, failure = runtime_structural_probe(
		runtime,
		3,
		probe.token,
		structural_capability_probe_callback,
		&probe,
	)
	testing.expectf(t, called, "forced-GC structural call failed: %s", failure.diagnostic)
	testing.expect_value(t, probe.calls, u64(2))

	failure_scenarios := [?]Named_Scenario {
		{name = "command-exception", scenario = 1},
		{name = "escaped-control", scenario = 2},
		{name = "cross-thread-control", scenario = 4},
		{name = "continuation-escape", scenario = 5},
	}
	for test_case in failure_scenarios {
		called, failure = runtime_structural_probe(
			runtime,
			test_case.scenario,
			probe.token,
			structural_capability_probe_callback,
			&probe,
		)
		testing.expectf(t, !called, "%s structural probe was accepted", test_case.name)
		testing.expectf(t, failure.code == .Racket_Exception, "%s structural probe returned the wrong failure", test_case.name)
	}

	cross_thread_result := Cross_Thread_Structural_Call_Result {
		runtime = runtime,
		probe = &probe,
	}
	worker := thread.create_and_start_with_poly_data(
		&cross_thread_result,
		cross_thread_structural_call,
	)
	testing.expect(t, worker != nil)
	if worker != nil {
		thread.join(worker)
		thread.destroy(worker)
		testing.expect(t, !cross_thread_result.ok)
		testing.expect_value(t, cross_thread_result.failure.code, Failure_Code.Wrong_Thread)
	}

	runtime.call_active = true
	called, failure = runtime_structural_probe(
		runtime,
		0,
		probe.token,
		structural_capability_probe_callback,
		&probe,
	)
	testing.expect(t, !called)
	testing.expect_value(t, failure.code, Failure_Code.Reentrant_Call)
	runtime.call_active = false

	called, failure = runtime_structural_probe(
		runtime, 0, 0, structural_capability_probe_callback, &probe,
	)
	testing.expect(t, !called)
	testing.expect_value(t, failure.code, Failure_Code.Wrong_Result)
	called, failure = runtime_structural_probe(runtime, 0, probe.token, nil, nil)
	testing.expect(t, !called)
	testing.expect_value(t, failure.code, Failure_Code.Wrong_Result)

	called, failure = runtime_structural_probe(
		runtime,
		0,
		probe.token,
		structural_capability_probe_callback,
		&probe,
	)
	testing.expectf(t, called, "structural facade reload failed: %s", failure.diagnostic)
	testing.expect_value(t, probe.calls, u64(3))
}

/* Verifies scoped service authority, containment, and exact dynamic extent. */
@(private)
verify_language_service_facade :: proc(t: ^testing.T, runtime: ^Runtime) {
	probe := Language_Service_Capability_Probe{token = 449}
	called, failure := runtime_language_service_probe(
		runtime,
		0,
		probe.token,
		language_service_capability_probe_callback,
		&probe,
	)
	testing.expectf(t, called, "language-service facade call failed: %s", failure.diagnostic)
	testing.expect_value(t, probe.calls, u64(1))

	called, failure = runtime_language_service_probe(
		runtime,
		3,
		probe.token,
		language_service_capability_probe_callback,
		&probe,
	)
	testing.expectf(t, called, "forced-GC service call failed: %s", failure.diagnostic)
	testing.expect_value(t, probe.calls, u64(2))

	failure_scenarios := [?]Named_Scenario {
		{name = "host-exception", scenario = 1},
		{name = "escaped-control", scenario = 2},
		{name = "cross-thread-control", scenario = 4},
		{name = "continuation-escape", scenario = 5},
	}
	for test_case in failure_scenarios {
		called, failure = runtime_language_service_probe(
			runtime,
			test_case.scenario,
			probe.token,
			language_service_capability_probe_callback,
			&probe,
		)
		testing.expectf(t, !called, "%s language-service probe was accepted", test_case.name)
		testing.expectf(t, failure.code == .Racket_Exception, "%s language-service probe returned the wrong failure", test_case.name)
	}

	cross_thread_result := Cross_Thread_Language_Service_Call_Result {
		runtime = runtime,
		probe = &probe,
	}
	worker := thread.create_and_start_with_poly_data(
		&cross_thread_result,
		cross_thread_language_service_call,
	)
	testing.expect(t, worker != nil)
	if worker != nil {
		thread.join(worker)
		thread.destroy(worker)
		testing.expect(t, !cross_thread_result.ok)
		testing.expect_value(t, cross_thread_result.failure.code, Failure_Code.Wrong_Thread)
	}

	runtime.call_active = true
	called, failure = runtime_language_service_probe(
		runtime,
		0,
		probe.token,
		language_service_capability_probe_callback,
		&probe,
	)
	testing.expect(t, !called)
	testing.expect_value(t, failure.code, Failure_Code.Reentrant_Call)
	runtime.call_active = false

	called, failure = runtime_language_service_probe(
		runtime, 0, 0, language_service_capability_probe_callback, &probe,
	)
	testing.expect(t, !called)
	testing.expect_value(t, failure.code, Failure_Code.Wrong_Result)
	called, failure = runtime_language_service_probe(runtime, 0, probe.token, nil, nil)
	testing.expect(t, !called)
	testing.expect_value(t, failure.code, Failure_Code.Wrong_Result)

	called, failure = runtime_language_service_probe(
		runtime,
		0,
		probe.token,
		language_service_capability_probe_callback,
		&probe,
	)
	testing.expectf(t, called, "language-service facade reload failed: %s", failure.diagnostic)
	testing.expect_value(t, probe.calls, u64(3))

	registry: language_service.Provider_Registry
	registry_initialized, registry_failure := language_service.provider_registry_init(
		&registry,
		language_service.Registry_Handle{id = 457, generation = 1},
	)
	testing.expectf(t, registry_initialized, "provider registry init failed: %v", registry_failure.code)
	if registry_initialized {
		factory, factory_registered, factory_failure := language_service.provider_registry_register_factory_ols(&registry)
		testing.expectf(t, factory_registered, "factory registration failed: %v", factory_failure.code)
		capability := Language_Service_Provider_Capability{
			registry = &registry,
			token = 461,
			project_id = 463,
			project_generation = 1,
			membership_id = 467,
			membership_generation = 1,
			search_path = "/usr/sbin",
		}
		composed, composition_failure := runtime_language_service_probe(
			runtime,
			6,
			capability.token,
			language_service_provider_capability_callback,
			&capability,
		)
		testing.expectf(t, composed, "programmable provider composition failed: %s", composition_failure.diagnostic)
		inspection, inspected := language_service.provider_registry_inspect(&registry)
		testing.expect(t, inspected)
		if inspected {
			testing.expect_value(t, inspection.active, factory)
			testing.expect_value(t, inspection.usage.service_definitions, u32(3))
		}
		diagnostic_request, diagnostic_requested :=
			language_service_provider_capability_take_diagnostic_command(&capability)
		testing.expect(t, diagnostic_requested)
		if diagnostic_requested {
			testing.expect_value(t, diagnostic_request.command,
				bridge.Language_Service_Diagnostic_Command.List)
			testing.expect_value(t, diagnostic_request.diagnostic_generation, u64(17))
			testing.expect_value(t, diagnostic_request.source_generation, u64(19))
		}
		language_service.provider_registry_close(&registry)
	}
}

@(private)
verify_candidate_usage_facade :: proc(t: ^testing.T, runtime: ^Runtime) {
	state_root, root_error := os.make_directory_temp(
		"",
		"odra-candidate-usage-hosting-*",
		context.allocator,
	)
	testing.expect(t, root_error == nil)
	if root_error != nil {
		return
	}
	defer {
		os.remove_all(state_root)
		delete(state_root)
	}
	permissions_error := os.chmod(
		state_root,
		os.Permissions{.Read_User, .Write_User, .Execute_User},
	)
	testing.expect(t, permissions_error == nil)
	if permissions_error != nil {
		return
	}
	load_output, output_error := make(
		[]u8,
		MAX_CANDIDATE_HISTORY_BYTES,
		context.allocator,
	)
	testing.expect(t, output_error == nil)
	if output_error != nil {
		return
	}
	defer delete(load_output)
	project_id := "hosting-project"
	load_length, loaded, load_failure := runtime_candidate_usage_load(
		runtime,
		state_root,
		project_id,
		load_output,
	)
	testing.expectf(t, loaded, "candidate usage absent load failed: %s", load_failure.diagnostic)
	if loaded {
		testing.expect_value(t, load_length, bridge.CANDIDATE_HISTORY_LOAD_HEADER_BYTES)
		testing.expect_value(t, candidate_usage_test_word(load_output[0:]), u64(1))
		testing.expect_value(t, candidate_usage_test_word(load_output[8:]), u64(1))
	}
	keys := "project-find-file/tmp/alpha.odin"
	request_length, request_ok := bridge.candidate_history_publish_record_bytes(2, u64(len(keys)))
	testing.expect(t, request_ok)
	if !request_ok {
		return
	}
	request, request_error := make([]u8, int(request_length), context.allocator)
	testing.expect(t, request_error == nil)
	if request_error != nil {
		return
	}
	defer delete(request)
	fields := [?]u64{1, 1, 3, 2, u64(len(keys)), 0}
	for field, index in fields {
		_ = endian.put_u64(request[index * 8:], .Little, field)
	}
	entry_start := int(bridge.CANDIDATE_HISTORY_PUBLISH_HEADER_BYTES)
	first := [?]u64{1, 0, u64(len("project-find-file")), 2}
	second := [?]u64{2, u64(len("project-find-file")), u64(len("/tmp/alpha.odin")), 1}
	for field, index in first {
		_ = endian.put_u64(request[entry_start + index * 8:], .Little, field)
	}
	entry_start += int(bridge.CANDIDATE_HISTORY_ENTRY_RECORD_BYTES)
	for field, index in second {
		_ = endian.put_u64(request[entry_start + index * 8:], .Little, field)
	}
	key_start := int(bridge.CANDIDATE_HISTORY_PUBLISH_HEADER_BYTES +
	                 2 * bridge.CANDIDATE_HISTORY_ENTRY_RECORD_BYTES)
	copy(request[key_start:], transmute([]u8)keys)
	publication: [bridge.CANDIDATE_HISTORY_PUBLICATION_BYTES]u8
	publication_length, published, publish_failure := runtime_candidate_usage_publish(
		runtime,
		state_root,
		project_id,
		request,
		publication[:],
	)
	testing.expectf(t, published, "candidate usage publication failed: %s", publish_failure.diagnostic)
	if published {
		testing.expect_value(t, publication_length, bridge.CANDIDATE_HISTORY_PUBLICATION_BYTES)
		testing.expect_value(t, candidate_usage_test_word(publication[16:]), u64(1))
	}
	load_length, loaded, load_failure = runtime_candidate_usage_load(
		runtime,
		state_root,
		project_id,
		load_output,
	)
	testing.expectf(t, loaded, "candidate usage confirmed load failed: %s", load_failure.diagnostic)
	if loaded {
		testing.expect(t, load_length > bridge.CANDIDATE_HISTORY_LOAD_HEADER_BYTES)
		testing.expect_value(t, candidate_usage_test_word(load_output[8:]), u64(2))
		testing.expect_value(t, candidate_usage_test_word(load_output[16:]), u64(1))
		testing.expect_value(t, candidate_usage_test_word(load_output[32:]), u64(2))
	}
	_, published, publish_failure = runtime_candidate_usage_publish(
		runtime,
		state_root,
		project_id,
		request,
		publication[:],
	)
	testing.expect(t, !published)
	testing.expect_value(t, publish_failure.code, Failure_Code.Racket_Exception)
	testing.expect_value(t, runtime_state(runtime), State.Ready)
}

@(private)
candidate_usage_test_word :: proc(bytes: []u8) -> u64 {
	value, ok := endian.get_u64(bytes, .Little)
	assert(ok)
	return value
}

@(private)
Buffer_Session_Probe_Context :: struct {
	token: u64,
	calls: u32,
}

@(private)
buffer_session_probe_callback :: proc "c" (
	user_data: rawptr,
	kind: Scoped_Capability_Kind,
	generation, token, domain_context: u64,
	operation: i32,
	arg0, arg1: u64,
	input: ^u8,
	input_length: u64,
	output: ^u8,
	output_capacity: u64,
	output_length, value: ^u64,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	_ = arg0
	_ = arg1
	_ = input
	_ = input_length
	probe := (^Buffer_Session_Probe_Context)(user_data)
	if probe == nil || kind != .Buffer_Session || generation == 0 ||
	   domain_context != 0 || token != probe.token || output_length == nil || value == nil ||
	   failure_code == nil || limit == nil || actual == nil {
		return 2
	}
	required := bridge.BUFFER_SESSION_SCOPE_RECORD_BYTES
	if operation == i32(bridge.Buffer_Session_Operation.Descriptors) {
		required = bridge.BUFFER_SESSION_DESCRIPTOR_HEADER_BYTES
	} else if operation != i32(bridge.Buffer_Session_Operation.Scope) {
		failure_code^ = 1
		return 1
	}
	if output == nil || output_capacity < required {
		failure_code^ = 2
		limit^ = required
		actual^ = output_capacity
		return 1
	}
	bytes := ([^]u8)(output)[:required]
	for &value_byte in bytes {
		value_byte = 0
	}
	output_length^ = required
	value^ = 0
	failure_code^ = 0
	limit^ = 0
	actual^ = 0
	probe.calls += 1
	return 0
}

/* Verifies copied session batches survive GC and leave no callback retained. */
@(private)
verify_buffer_session_facade :: proc(t: ^testing.T, runtime: ^Runtime) {
	probe := Buffer_Session_Probe_Context{token = 991}
	called, call_failure := runtime_buffer_session_probe(
		runtime,
		0,
		probe.token,
		buffer_session_probe_callback,
		&probe,
	)
	testing.expectf(t, called, "buffer session facade failed: %s", call_failure.diagnostic)
	called, call_failure = runtime_buffer_session_probe(
		runtime,
		2,
		probe.token,
		buffer_session_probe_callback,
		&probe,
	)
	testing.expectf(t, called, "buffer session GC facade failed: %s", call_failure.diagnostic)
	called, call_failure = runtime_buffer_session_probe(
		runtime,
		6,
		probe.token,
		buffer_session_probe_callback,
		&probe,
	)
	testing.expectf(t, called, "buffer session batch facade failed: %s", call_failure.diagnostic)
	testing.expect_value(t, probe.calls, u32(4))
	failure_scenarios := [?]Named_Scenario {
		{name = "escaped-session", scenario = 1},
		{name = "cross-thread-session", scenario = 3},
		{name = "command-exception", scenario = 4},
		{name = "continuation-escape", scenario = 5},
	}
	for test_case in failure_scenarios {
		called, call_failure = runtime_buffer_session_probe(
			runtime,
			test_case.scenario,
			probe.token,
			buffer_session_probe_callback,
			&probe,
		)
		testing.expectf(t, !called, "%s buffer-session probe was accepted", test_case.name)
		testing.expectf(t, call_failure.code == .Racket_Exception, "%s buffer-session probe returned the wrong failure", test_case.name)
		called, call_failure = runtime_buffer_session_probe(
			runtime,
			0,
			probe.token,
			buffer_session_probe_callback,
			&probe,
		)
		testing.expectf(t, called, "callback cleanup failed: %s", call_failure.diagnostic)
	}
	runtime.call_active = true
	called, call_failure = runtime_buffer_session_probe(
		runtime,
		0,
		probe.token,
		buffer_session_probe_callback,
		&probe,
	)
	testing.expect(t, !called)
	testing.expect_value(t, call_failure.code, Failure_Code.Reentrant_Call)
	runtime.call_active = false
	called, call_failure = runtime_buffer_session_probe(runtime, 0, probe.token, nil, nil)
	testing.expect(t, !called)
	testing.expect_value(t, call_failure.code, Failure_Code.Wrong_Result)
}
@(private)
Transfer_Probe_Context :: struct {
	token:         u64,
	calls:         u64,
	probe_nested:  bool,
	nested_status: i32,
}

@(private)
transfer_probe_callback :: proc "c" (
	user_data: rawptr,
	kind: Scoped_Capability_Kind,
	generation, token, domain_context: u64,
	operation: i32,
	arg0, arg1: u64,
	input: ^u8,
	input_length: u64,
	output: ^u8,
	output_capacity: u64,
	output_length, value: ^u64,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	context = base_runtime.default_context()
	probe := (^Transfer_Probe_Context)(user_data)
	if probe == nil || kind != .Transfer || generation == 0 || domain_context != 0 ||
	   token != probe.token ||
	   operation != i32(bridge.Transfer_Operation.Scope) ||
	   arg0 != 0 || arg1 != 0 || input_length != 0 ||
	   output == nil || output_capacity != bridge.TRANSFER_SCOPE_RECORD_BYTES ||
	   output_length == nil || value == nil || failure_code == nil ||
	   limit == nil || actual == nil {
		return 2
	}
	if probe.probe_nested {
		probe.probe_nested = false
		probe.nested_status = odra_racket_scoped_capability_call(
			kind,
			generation,
			token,
			operation,
			arg0,
			arg1,
			input,
			input_length,
			output,
			output_capacity,
			output_length,
			value,
			failure_code,
			limit,
			actual,
		)
	}
	record := (^bridge.Transfer_Scope_Record)(output)
	record^ = bridge.Transfer_Scope_Record {
		editor_session_id = 19,
		access = 15,
		view_registry_id = 7,
		view_id = 11,
		view_generation = 3,
		view_state_generation = 29,
		buffer_id = 31,
		revision = 37,
		ring_id = 41,
		ring_generation = 43,
		command_registry_generation = 47,
	}
	output_length^ = bridge.TRANSFER_SCOPE_RECORD_BYTES
	value^ = 0
	failure_code^ = 0
	limit^ = 0
	actual^ = 0
	probe.calls += 1
	return 0
}

@(private)
Cross_Thread_Transfer_Call_Result :: struct {
	runtime: ^Runtime,
	probe:   ^Transfer_Probe_Context,
	ok:      bool,
	failure: Failure_Context,
}

@(private)
cross_thread_transfer_call :: proc(observed: ^Cross_Thread_Transfer_Call_Result) {
	observed.ok, observed.failure = runtime_transfer_probe(
		observed.runtime,
		0,
		observed.probe.token,
		transfer_probe_callback,
		observed.probe,
	)
}

/* Verifies copied transfer calls are dynamically scoped and contained by the adapter. */
@(private)
verify_transfer_facade :: proc(t: ^testing.T, runtime: ^Runtime) {
	probe := Transfer_Probe_Context{token = 77}
	called, failure := runtime_transfer_probe(
		runtime, 0, probe.token, transfer_probe_callback, &probe,
	)
	testing.expectf(t, called, "transfer facade call failed: %s", failure.diagnostic)
	testing.expect_value(t, probe.calls, u64(1))

	called, failure = runtime_transfer_probe(
		runtime, 2, probe.token, transfer_probe_callback, &probe,
	)
	testing.expectf(t, called, "forced-GC transfer call failed: %s", failure.diagnostic)
	testing.expect_value(t, probe.calls, u64(2))
	identity_scenarios := [?]Named_Scenario {
		{name = "wrong-domain", scenario = 12},
		{name = "wrong-generation", scenario = 13},
	}
	for test_case in identity_scenarios {
		called, failure = runtime_transfer_probe(
			runtime, test_case.scenario, probe.token, transfer_probe_callback, &probe,
		)
		testing.expectf(t, called, "%s transport identity probe failed: %s", test_case.name, failure.diagnostic)
	}
	testing.expect_value(t, probe.calls, u64(2))
	probe.probe_nested = true
	called, failure = runtime_transfer_probe(
		runtime, 0, probe.token, transfer_probe_callback, &probe,
	)
	testing.expectf(t, called, "nested transport probe failed: %s", failure.diagnostic)
	testing.expect_value(t, probe.nested_status, i32(2))
	testing.expect_value(t, probe.calls, u64(3))

	failure_scenarios := [?]Named_Scenario {
		{name = "escaped-session", scenario = 1},
		{name = "cross-thread-session", scenario = 3},
		{name = "command-exception", scenario = 4},
		{name = "continuation-escape", scenario = 5},
		{name = "undersized-output", scenario = 10},
		{name = "excessive-ring", scenario = 11},
	}
	for test_case in failure_scenarios {
		called, failure = runtime_transfer_probe(
			runtime, test_case.scenario, probe.token, transfer_probe_callback, &probe,
		)
		testing.expectf(t, !called, "%s transfer probe was accepted", test_case.name)
		testing.expectf(t, failure.code == .Racket_Exception, "%s transfer probe returned the wrong failure", test_case.name)
	}

	cross_thread_result := Cross_Thread_Transfer_Call_Result {
		runtime = runtime,
		probe = &probe,
	}
	worker := thread.create_and_start_with_poly_data(
		&cross_thread_result,
		cross_thread_transfer_call,
	)
	testing.expect(t, worker != nil)
	if worker != nil {
		thread.join(worker)
		thread.destroy(worker)
		testing.expect(t, !cross_thread_result.ok)
		testing.expect_value(t, cross_thread_result.failure.code, Failure_Code.Wrong_Thread)
	}

	runtime.call_active = true
	called, failure = runtime_transfer_probe(
		runtime, 0, probe.token, transfer_probe_callback, &probe,
	)
	testing.expect(t, !called)
	testing.expect_value(t, failure.code, Failure_Code.Reentrant_Call)
	runtime.call_active = false

	called, failure = runtime_transfer_probe(runtime, 0, 0, transfer_probe_callback, &probe)
	testing.expect(t, !called)
	testing.expect_value(t, failure.code, Failure_Code.Wrong_Result)

	called, failure = runtime_transfer_probe(runtime, 0, probe.token, nil, nil)
	testing.expect(t, !called)
	testing.expect_value(t, failure.code, Failure_Code.Wrong_Result)
	testing.expect_value(t, probe.calls, u64(3))
}

@(private)
Search_Probe_Context :: struct {
	token: u64,
	calls: u64,
}

@(private)
search_probe_callback :: proc "c" (
	user_data: rawptr,
	kind: Scoped_Capability_Kind,
	generation, token, domain_context: u64,
	operation: i32,
	arg0, arg1: u64,
	input: ^u8,
	input_length: u64,
	output: ^u8,
	output_capacity: u64,
	output_length, value: ^u64,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	context = base_runtime.default_context()
	probe := (^Search_Probe_Context)(user_data)
	if probe == nil || kind != .Search || generation == 0 || domain_context != 0 ||
	   token != probe.token ||
	   operation != i32(bridge.Search_Operation.Scope) || arg0 != 0 || arg1 != 0 ||
	   input_length != 0 || output == nil ||
	   output_capacity != bridge.SEARCH_SCOPE_RECORD_BYTES || output_length == nil ||
	   value == nil || failure_code == nil || limit == nil || actual == nil {
		return 2
	}
	record := ([^]u8)(output)[:int(output_capacity)]
	fields := [?]u64{101, 7, 3, 11, 13, 17, 19, 23, 29, 0, 31, 37}
	for field, index in fields {
		written := endian.put_u64(record[index * 8:], .Little, field)
		assert(written)
	}
	output_length^ = bridge.SEARCH_SCOPE_RECORD_BYTES
	value^ = 0
	failure_code^ = 0
	limit^ = 0
	actual^ = 0
	probe.calls += 1
	return 0
}

@(private)
Cross_Thread_Search_Call_Result :: struct {
	runtime: ^Runtime,
	probe:   ^Search_Probe_Context,
	ok:      bool,
	failure: Failure_Context,
}

@(private)
cross_thread_search_call :: proc(observed: ^Cross_Thread_Search_Call_Result) {
	observed.ok, observed.failure = runtime_search_probe(
		observed.runtime,
		0,
		observed.probe.token,
		search_probe_callback,
		observed.probe,
	)
}

/* Verifies search calls contain dynamic-extent, thread, and reentrancy failures. */
@(private)
verify_search_facade :: proc(t: ^testing.T, runtime: ^Runtime) {
	probe := Search_Probe_Context{token = 79}
	called, failure := runtime_search_probe(
		runtime,
		0,
		probe.token,
		search_probe_callback,
		&probe,
	)
	testing.expectf(t, called, "search facade call failed: %s", failure.diagnostic)
	testing.expect_value(t, probe.calls, u64(1))

	called, failure = runtime_search_probe(
		runtime,
		2,
		probe.token,
		search_probe_callback,
		&probe,
	)
	testing.expectf(t, called, "forced-GC search call failed: %s", failure.diagnostic)
	testing.expect_value(t, probe.calls, u64(2))

	failure_scenarios := [?]Named_Scenario {
		{name = "escaped-context", scenario = 1},
		{name = "cross-thread-context", scenario = 3},
		{name = "command-exception", scenario = 4},
		{name = "continuation-escape", scenario = 5},
		{name = "excessive-occurrences", scenario = 8},
		{name = "oversized-pattern", scenario = 12},
		{name = "invalid-direction", scenario = 13},
	}
	for test_case in failure_scenarios {
		called, failure = runtime_search_probe(
			runtime,
			test_case.scenario,
			probe.token,
			search_probe_callback,
			&probe,
		)
		testing.expectf(t, !called, "%s search probe was accepted", test_case.name)
		testing.expectf(t, failure.code == .Racket_Exception, "%s search probe returned the wrong failure", test_case.name)
	}

	cross_thread_result := Cross_Thread_Search_Call_Result {
		runtime = runtime,
		probe = &probe,
	}
	worker := thread.create_and_start_with_poly_data(
		&cross_thread_result,
		cross_thread_search_call,
	)
	testing.expect(t, worker != nil)
	if worker != nil {
		thread.join(worker)
		thread.destroy(worker)
		testing.expect(t, !cross_thread_result.ok)
		testing.expect_value(t, cross_thread_result.failure.code, Failure_Code.Wrong_Thread)
	}

	runtime.call_active = true
	called, failure = runtime_search_probe(
		runtime,
		0,
		probe.token,
		search_probe_callback,
		&probe,
	)
	testing.expect(t, !called)
	testing.expect_value(t, failure.code, Failure_Code.Reentrant_Call)
	runtime.call_active = false

	called, failure = runtime_search_probe(runtime, 0, 0, search_probe_callback, &probe)
	testing.expect(t, !called)
	testing.expect_value(t, failure.code, Failure_Code.Wrong_Result)
	called, failure = runtime_search_probe(runtime, 0, probe.token, nil, nil)
	testing.expect(t, !called)
	testing.expect_value(t, failure.code, Failure_Code.Wrong_Result)

	called, failure = runtime_search_probe(
		runtime,
		0,
		probe.token,
		search_probe_callback,
		&probe,
	)
	testing.expectf(t, called, "search facade reload failed: %s", failure.diagnostic)
	testing.expect_value(t, probe.calls, u64(3))
}

@(private)
Transaction_Probe_Context :: struct {
	registry:   ^bridge.Transaction_Capability_Registry,
	capability: bridge.Transaction_Capability,
}

@(private)
transaction_probe_callback :: proc "c" (
	user_data: rawptr,
	kind: Scoped_Capability_Kind,
	generation, token, command_id: u64,
	operation: i32,
	arg0, arg1: u64,
	input: ^u8,
	input_length: u64,
	output: ^u8,
	output_capacity: u64,
	output_length, value: ^u64,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	context = base_runtime.default_context()
	probe := (^Transaction_Probe_Context)(user_data)
	if probe == nil || kind != .Transaction || generation == 0 ||
	   token != u64(probe.capability) || output_length == nil ||
	   value == nil || failure_code == nil || limit == nil || actual == nil {
		return 2
	}
	output_length^ = 0
	value^ = 0
	failure_code^ = 0
	limit^ = 0
	actual^ = 0
	ok := false
	failure: bridge.Failure_Context
	switch operation {
	case 1:
		if output == nil || output_capacity > u64(max(int)) {
			return 2
		}
		destination := ([^]u8)(output)[:int(output_capacity)]
		copied: u64
		copied, ok, failure = bridge.transaction_capability_inspect(
			probe.registry,
			probe.capability,
			command_id,
			arg0,
			arg1,
			destination,
		)
		output_length^ = copied
	case 3:
		if (input == nil && input_length != 0) || input_length > u64(max(int)) {
			return 2
		}
		replacement := ""
		if input_length != 0 {
			replacement = string(([^]u8)(input)[:int(input_length)])
		}
		ok, failure = bridge.transaction_capability_splice(
			probe.registry,
			probe.capability,
			command_id,
			arg0,
			arg1,
			replacement,
		)
	case:
		return 2
	}
	if ok {
		return 0
	}
	failure_code^ = u32(edit_transaction.Failure_Code.Invalid_State)
	if failure.code == .Transaction_Failure {
		failure_code^ = u32(failure.transaction_code)
	}
	limit^ = failure.limit
	actual^ = failure.actual
	return 1
}

/* Verifies the embedded adapter forgets its callback and contains escaped facade use. */
@(private)
verify_transaction_facade :: proc(t: ^testing.T, runtime: ^Runtime) {
	buffer: editor.Buffer
	buffer_ready, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(91),
		"abc",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, buffer_ready)
	transaction: edit_transaction.Transaction
	transaction_ready, _ := edit_transaction.transaction_begin(
		&transaction,
		edit_transaction.Transaction_ID(91),
		edit_transaction.Undo_Unit_ID(91),
		&buffer,
		edit_transaction.Origin{kind = .Racket, descriptor = "hosting-test"},
		"transaction-probe",
		edit_transaction.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, transaction_ready)
	registry: bridge.Transaction_Capability_Registry
	bridge.transaction_capability_registry_init(&registry, bridge.Registry_ID(44))
	capability, acquired, _ := bridge.transaction_capability_acquire(
		&registry,
		&transaction,
		&buffer,
		901,
	)
	testing.expect(t, acquired)
	probe := Transaction_Probe_Context{registry = &registry, capability = capability}
	called, call_failure := runtime_transaction_probe(
		runtime,
		0,
		u64(capability),
		901,
		transaction_probe_callback,
		&probe,
	)
	testing.expectf(t, called, "transaction facade call failed: %s", call_failure.diagnostic)
	private: [3]byte
	_, inspected, _ := bridge.transaction_capability_inspect(
		&registry,
		capability,
		901,
		0,
		3,
		private[:],
	)
	testing.expect(t, inspected)
	testing.expect_value(t, string(private[:]), "aXc")

	called, call_failure = runtime_transaction_probe(
		runtime, 2, u64(capability), 901, transaction_probe_callback, &probe,
	)
	testing.expectf(t, called, "forced-GC facade call failed: %s", call_failure.diagnostic)
	called, call_failure = runtime_transaction_probe(
		runtime, 1, u64(capability), 901, transaction_probe_callback, &probe,
	)
	testing.expect(t, !called)
	testing.expect_value(t, call_failure.code, Failure_Code.Racket_Exception)
	called, call_failure = runtime_transaction_probe(
		runtime, 4, u64(capability), 901, transaction_probe_callback, &probe,
	)
	testing.expect(t, !called)
	testing.expect_value(t, call_failure.code, Failure_Code.Racket_Exception)
	called, call_failure = runtime_transaction_probe(
		runtime, 5, u64(capability), 901, transaction_probe_callback, &probe,
	)
	testing.expect(t, !called)
	testing.expect_value(t, call_failure.code, Failure_Code.Racket_Exception)
	called, call_failure = runtime_transaction_probe(
		runtime, 3, u64(capability), 901, transaction_probe_callback, &probe,
	)
	testing.expect(t, !called)
	testing.expect_value(t, call_failure.code, Failure_Code.Racket_Exception)
	called, call_failure = runtime_transaction_command(
		runtime,
		0,
		u64(capability),
		901,
		0,
		3,
		"uppercase-current-line",
		nil,
		nil,
	)
	testing.expect(t, !called)
	testing.expect_value(t, call_failure.code, Failure_Code.Wrong_Result)
	original_capability := probe.capability
	probe.capability = bridge.Transaction_Capability(u64(original_capability) + 1)
	called, call_failure = runtime_transaction_probe(
		runtime, 0, u64(original_capability), 901, transaction_probe_callback, &probe,
	)
	testing.expect(t, !called)
	testing.expect_value(t, call_failure.code, Failure_Code.Racket_Exception)
	probe.capability = original_capability

	bridge.transaction_capability_release(&registry, &capability)
	bridge.transaction_capability_registry_close(&registry)
	edit_transaction.transaction_abort(&transaction)
	edit_transaction.transaction_close(&transaction)
	editor.buffer_close(&buffer)
}
