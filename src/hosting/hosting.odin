// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package hosting owns the in-process Racket CS runtime lifecycle.
package hosting

import "../bridge"
import "../interaction"
import base_runtime "base:runtime"
import endian "core:encoding/endian"
import "core:fmt"
import "core:mem"
import "core:os"

@(private)
ODRA_RACKET_RUNTIME_LIBRARY :: #config(
	ODRA_RACKET_RUNTIME_LIBRARY,
	"../../.build/hosting/libodra_racket_runtime.a",
)

@(private)
ODRA_RACKET_COMMAND_SCENARIO :: i32(#config(ODRA_RACKET_COMMAND_SCENARIO, 0))
@(private)
ODRA_RACKET_HISTORY_POLICY_SCENARIO :: i32(#config(ODRA_RACKET_HISTORY_POLICY_SCENARIO, 0))
@(private)
ODRA_RACKET_DISPLAY_POLICY_SCENARIO :: i32(#config(ODRA_RACKET_DISPLAY_POLICY_SCENARIO, 0))
@(private)
ODRA_NATIVE_CONTRACT_SCHEMA_SCENARIO :: i32(#config(ODRA_NATIVE_CONTRACT_SCHEMA_SCENARIO, 0))

foreign import racket_runtime {ODRA_RACKET_RUNTIME_LIBRARY}

@(private, default_calling_convention="c")
foreign racket_runtime {
	odra_racket_runtime_start :: proc(
		schema: ^u8,
		schema_length: u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_start_with_resources :: proc(
		schema: ^u8,
		schema_length: u64,
		boot_directory: ^u8,
		boot_directory_length: u64,
		collects_directory: ^u8,
		collects_directory_length: u64,
		config_directory: ^u8,
		config_directory_length: u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_start_bundled :: proc(
		schema: ^u8,
		schema_length: u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_platform_roots :: proc(
		output: ^u8,
		output_capacity: u64,
		output_length: ^u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_call_scalar :: proc(
		scenario: i32,
		input: i64,
		output: ^i64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_command_request :: proc(
		scenario: i32,
		capability, buffer_id, revision: u64,
		start, end: ^u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_command_transform :: proc(
		scenario: i32,
		capability, buffer_id, revision, start, end: u64,
		input: ^u8,
		input_length: u64,
		result_start, result_end: ^u64,
		replacement: ^u8,
		replacement_capacity: u64,
		replacement_length: ^u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_load_keymap_profile :: proc(
		scenario: i32,
		registry_generation: u64,
		output: ^u8,
		output_capacity: u64,
		output_length: ^u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_load_command_catalog :: proc(
		scenario: i32,
		registry_generation: u64,
		output: ^u8,
		output_capacity: u64,
		output_length: ^u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_history_policy :: proc(
		scenario: i32,
		input: ^History_Policy_Record,
		output: ^History_Policy_Record,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_display_policy :: proc(
		scenario: i32,
		input: ^Display_Policy_Record,
		output: ^Display_Policy_Record,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_uppercase_line :: proc(
		scenario: i32,
		capability, buffer_id, revision, start, end: u64,
		input: ^u8,
		input_length: u64,
		result_start, result_end: ^u64,
		replacement: ^u8,
		replacement_capacity: u64,
		replacement_length: ^u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_transaction_probe :: proc(
		scenario: i32,
		token, command_id: u64,
		callback: Scoped_Capability_Callback_Procedure,
		user_data: rawptr,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_transaction_command :: proc(
		scenario: i32,
		token, command_id: u64,
		command_name: ^u8,
		command_name_length: u64,
		start, end: u64,
		callback: Scoped_Capability_Callback_Procedure,
		user_data: rawptr,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_personal_command :: proc(
		token, command_id: u64,
		command_name: ^u8,
		command_name_length: u64,
		document_path: ^u8,
		document_path_length: u64,
		project_root: ^u8,
		project_root_length: u64,
		candidate_selection: ^u8,
		candidate_selection_length: u64,
		route_generation, route_slot, revision, point: u64,
		region_present: i32,
		region_start, region_end, line_start, line_end, buffer_end, effects: u64,
		cancelled: i32,
		callback: Scoped_Capability_Callback_Procedure,
		user_data: rawptr,
		result: ^u8,
		result_capacity: u64,
		result_length: ^u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_transfer_probe :: proc(
		scenario: i32,
		token: u64,
		callback: Scoped_Capability_Callback_Procedure,
		user_data: rawptr,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_search_probe :: proc(
		scenario: i32,
		token: u64,
		callback: Scoped_Capability_Callback_Procedure,
		user_data: rawptr,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_buffer_session_probe :: proc(
		scenario: i32,
		token: u64,
		callback: Scoped_Capability_Callback_Procedure,
		user_data: rawptr,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_layout_probe :: proc(
		scenario: i32,
		token: u64,
		callback: Scoped_Capability_Callback_Procedure,
		user_data: rawptr,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_ui_role_probe :: proc(
		scenario: i32,
		token: u64,
		callback: Scoped_Capability_Callback_Procedure,
		user_data: rawptr,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_theme_probe :: proc(
		scenario: i32,
		token: u64,
		callback: Scoped_Capability_Callback_Procedure,
		user_data: rawptr,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_structural_probe :: proc(
		scenario: i32,
		token: u64,
		callback: Scoped_Capability_Callback_Procedure,
		user_data: rawptr,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_language_service_probe :: proc(
		scenario: i32,
		token: u64,
		callback: Scoped_Capability_Callback_Procedure,
		user_data: rawptr,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_result_probe :: proc(
		scenario: i32,
		token: u64,
		callback: Scoped_Capability_Callback_Procedure,
		user_data: rawptr,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_status_bar_probe :: proc(
		scenario: i32,
		token: u64,
		callback: Scoped_Capability_Callback_Procedure,
		user_data: rawptr,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_terminal_probe :: proc(
		scenario: i32,
		token: u64,
		callback: Scoped_Capability_Callback_Procedure,
		user_data: rawptr,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_project_directory_resolution :: proc(
		projects_directory: ^u8,
		projects_directory_length: u64,
		directory: ^u8,
		directory_length: u64,
		output: ^u8,
		output_capacity: u64,
		output_length: ^u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_project_catalog_resolution :: proc(
		configuration_root: ^u8,
		configuration_root_length: u64,
		output: ^u8,
		output_capacity: u64,
		output_length: ^u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_personal_configuration_startup :: proc(
		configuration_root: ^u8,
		configuration_root_length: u64,
		output: ^u8,
		output_capacity: u64,
		output_length: ^u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_personal_configuration_reload :: proc(
		configuration_root: ^u8,
		configuration_root_length: u64,
		expected_generation: u64,
		output: ^u8,
		output_capacity: u64,
		output_length: ^u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_provider_invoke :: proc(
		service: ^u8,
		service_length: u64,
		generation: u64,
		operation: u64,
		name: ^u8,
		name_length: u64,
		payload: ^u8,
		payload_length: u64,
		output: ^u8,
		output_capacity: u64,
		output_length: ^u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_personal_generation_transition :: proc(
		transition, generation: u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_project_promotion :: proc(
		configuration_root: ^u8,
		configuration_root_length: u64,
		directory: ^u8,
		directory_length: u64,
		name: ^u8,
		name_length: u64,
		output: ^u8,
		output_capacity: u64,
		output_length: ^u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_project_rename :: proc(
		configuration_root: ^u8,
		configuration_root_length: u64,
		directory: ^u8,
		directory_length: u64,
		name: ^u8,
		name_length: u64,
		generation: u64,
		output: ^u8,
		output_capacity: u64,
		output_length: ^u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_project_unregister :: proc(
		configuration_root: ^u8,
		configuration_root_length: u64,
		id: ^u8,
		id_length: u64,
		root: ^u8,
		root_length: u64,
		generation: u64,
		output: ^u8,
		output_capacity: u64,
		output_length: ^u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_promotion_suppression :: proc(
		configuration_root: ^u8,
		configuration_root_length: u64,
		directory: ^u8,
		directory_length: u64,
		action: u64,
		output: ^u8,
		output_capacity: u64,
		output_length: ^u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_workspace_command :: proc(
		configuration_root: ^u8,
		configuration_root_length: u64,
		request: ^u8,
		request_length: u64,
		output: ^u8,
		output_capacity: u64,
		output_length: ^u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_named_location_command :: proc(
		configuration_root: ^u8,
		configuration_root_length: u64,
		request: ^u8,
		request_length: u64,
		output: ^u8,
		output_capacity: u64,
		output_length: ^u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_named_slot_command :: proc(
		configuration_root: ^u8,
		configuration_root_length: u64,
		request: ^u8,
		request_length: u64,
		output: ^u8,
		output_capacity: u64,
		output_length: ^u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_package_catalog_command :: proc(
		configuration_root: ^u8,
		configuration_root_length: u64,
		request: ^u8,
		request_length: u64,
		output: ^u8,
		output_capacity: u64,
		output_length: ^u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_candidate_usage_load :: proc(
		state_root: ^u8,
		state_root_length: u64,
		project_id: ^u8,
		project_id_length: u64,
		output: ^u8,
		output_capacity: u64,
		output_length: ^u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_runtime_candidate_usage_publish :: proc(
		state_root: ^u8,
		state_root_length: u64,
		project_id: ^u8,
		project_id_length: u64,
		request: ^u8,
		request_length: u64,
		output: ^u8,
		output_capacity: u64,
		output_length: ^u64,
		diagnostic: ^u8,
		diagnostic_capacity: u64,
	) -> i32 ---
	odra_racket_scoped_capability_call :: proc(
		kind: Scoped_Capability_Kind,
		generation, token: u64,
		operation: i32,
		arg0, arg1: u64,
		input: ^u8,
		input_length: u64,
		output: ^u8,
		output_capacity: u64,
		output_length, value: ^u64,
		failure_code: ^u32,
		limit, actual: ^u64,
	) -> i32 ---
	odra_racket_runtime_stop  :: proc(diagnostic: ^u8, diagnostic_capacity: u64) -> i32 ---
}

@(private)
DIAGNOSTIC_CAPACITY :: 512

/* MAX_PROJECT_DIRECTORY_RESOLUTION_BYTES bounds one copied catalog match batch. */
MAX_PROJECT_DIRECTORY_RESOLUTION_BYTES :: 4 * 1024 * 1024
/* MAX_PROJECT_PROMOTION_BYTES bounds one copied promotion result and diagnostic. */
MAX_PROJECT_PROMOTION_BYTES :: 8 * 1024
/* MAX_WORKSPACE_COMMAND_BYTES bounds each copied Workspace request or result. */
MAX_WORKSPACE_COMMAND_BYTES :: 4 * 1024 * 1024
/* MAX_NAMED_LOCATION_COMMAND_BYTES bounds one copied named-location exchange. */
MAX_NAMED_LOCATION_COMMAND_BYTES :: 4 * 1024 * 1024
/* MAX_NAMED_SLOT_COMMAND_BYTES bounds one copied named-slot exchange. */
MAX_NAMED_SLOT_COMMAND_BYTES :: 4 * 1024 * 1024
/* MAX_PACKAGE_CATALOG_COMMAND_BYTES bounds one copied catalog exchange. */
MAX_PACKAGE_CATALOG_COMMAND_BYTES :: 256 * 1024
/* MAX_CANDIDATE_HISTORY_BYTES bounds one copied load or publication request. */
MAX_CANDIDATE_HISTORY_BYTES :: 8 * 1024 * 1024
/* MAX_PLATFORM_ROOTS_BYTES bounds one copied platform-root record. */
MAX_PLATFORM_ROOTS_BYTES :: 32 * 1024
/* MAX_PERSONAL_CONFIGURATION_STARTUP_BYTES bounds one copied personal init startup result. */
MAX_PERSONAL_CONFIGURATION_STARTUP_BYTES :: 256 * 1024

/* Platform_Roots_Platform identifies the path policy used at startup. */
Platform_Roots_Platform :: enum u64 {
	Invalid,
	Linux,
	Darwin,
	Windows,
}

/* Platform_Roots owns the resolved absolute paths copied from Racket. */
Platform_Roots :: struct {
	platform:         Platform_Roots_Platform,
	home:             string,
	configuration:    string,
	state:            string,
	cache:            string,
	package_data:     string,
	project_catalog:  string,
	legacy_projects:  string,
	storage:          []byte,
	allocator:        base_runtime.Allocator,
}

/* HISTORY_POLICY_FIELD_COUNT is the fixed complete global policy width. */
HISTORY_POLICY_FIELD_COUNT :: 13

/* Keymap_Profile_Candidate owns one validated copied profile until explicitly closed. */
Keymap_Profile_Candidate :: struct {
	state:  rawptr,
	closed: bool,
}

/* Keymap_Profile_View borrows immutable copied records from one live candidate. */
Keymap_Profile_View :: struct {
	header:    bridge.Keymap_Profile_Header_Record,
	profiles:  []bridge.Keymap_Profile_Record,
	states:    []bridge.Keymap_State_Record,
	maps:      []bridge.Keymap_Map_Record,
	bindings:  []bridge.Keymap_Binding_Record,
	selectors: []bridge.Keymap_Selector_Record,
	surfaces:  []bridge.Keymap_Surface_Record,
	remaps:    []bridge.Keymap_Remap_Record,
	ordering:  []bridge.Keymap_Ordering_Record,
	strokes:   []bridge.Keymap_Stroke_Record,
	text:      []byte,
}

@(private)
Keymap_Profile_Candidate_State :: struct {
	view:               Keymap_Profile_View,
	catalog_definition: interaction.Profile_Catalog_Definition,
	definition:         interaction.Profile_Definition,
	profiles:           []interaction.Profile_Definition,
	states:             []interaction.Interaction_State_Definition,
	maps:               []interaction.Map_Definition,
	bindings:           []interaction.Layered_Binding_Definition,
	selectors:          []interaction.Profile_State_Selector,
	surfaces:           []interaction.Command_Entry_Surface_Definition,
	remaps:             []interaction.Command_Remap_Definition,
	ordering:           []interaction.Ordering_Constraint,
	storage:            []byte,
	allocator:          base_runtime.Allocator,
}

/* Command_Catalog_Candidate owns one validated copied programmable catalog. */
Command_Catalog_Candidate :: struct {
	state:  rawptr,
	closed: bool,
}

/* Command_Catalog_View borrows immutable copied command records from one candidate. */
Command_Catalog_View :: struct {
	header:  bridge.Command_Catalog_Header_Record,
	records: []bridge.Command_Catalog_Record,
	text:    []byte,
}

@(private)
Command_Catalog_Candidate_State :: struct {
	view:        Command_Catalog_View,
	definitions: []interaction.Command_Definition,
	storage:     []byte,
	allocator:   base_runtime.Allocator,
}

/* History_Policy_Record is one caller-owned fixed-width policy transfer. */
History_Policy_Record :: struct {
	generation: u64,
	fields:     [HISTORY_POLICY_FIELD_COUNT]u64,
}

/* Display_Policy_Record is one caller-owned fixed-width display-policy transfer. */
Display_Policy_Record :: struct {
	generation:             u64,
	action_count:           u64,
	actions:                [32]u64,
	split_height_threshold: u64,
	split_width_threshold:  u64,
}

/*
State identifies one process-lifetime Racket runtime phase.
Starting and Stopping are synchronous transition states; Failed and Stopped are terminal.
*/
State :: enum u8 {
	Uninitialized,
	Starting,
	Ready,
	Failed,
	Stopping,
	Stopped,
}

/* Failure_Code distinguishes lifecycle, thread, reentrancy, Racket, and ABI failures. */
Failure_Code :: enum u8 {
	None,
	Invalid_State,
	Wrong_Thread,
	Reentrant_Call,
	Runtime_Unavailable,
	Racket_Exception,
	Command_Rejection,
	Wrong_Result,
}

/*
Failure_Context reports one checked boundary failure and its runtime phase.
Its diagnostic view is owned by Runtime and expires at the next operation.
*/
Failure_Context :: struct {
	code:       Failure_Code,
	phase:      State,
	diagnostic: string,
}

/*
Runtime is the single owner of the process Racket runtime lifecycle.
Its fields are implementation state and callers must not modify them directly.
*/
Runtime :: struct {
	phase:             State,
	owner_thread_id:   int,
	call_active:       bool,
	diagnostic:        [DIAGNOSTIC_CAPACITY]u8,
	diagnostic_length: u16,
}

/*
Runtime_Resource_Paths identifies explicit absolute Racket directories for
isolated packaging tests. Ordinary development and bundled production startup
use their dedicated entrypoints instead.
*/
Runtime_Resource_Paths :: struct {
	boot_directory:     string,
	collects_directory: string,
	config_directory:   string,
}

/* Inspection_Request is a checked byte range requested by the built-in Racket command. */
Inspection_Request :: struct {
	start: u64,
	end:   u64,
}

/* Replacement_Request identifies one returned range and copied replacement byte count. */
Replacement_Request :: struct {
	start:             u64,
	end:               u64,
	replacement_bytes: u64,
}

/*
runtime_start synchronously boots Racket CS and the repository-owned built-in module.
It accepts only a zero-value Runtime and leaves failures in the terminal Failed state.
*/
runtime_start :: proc(runtime: ^Runtime) -> (ok: bool, failure: Failure_Context) {
	return runtime_start_mode(runtime, .Configured, {})
}

/*
runtime_start_with_resources boots from explicit absolute paths for isolated
release fixtures. The adapter rejects empty, relative, parent-traversing, or
NUL-containing paths before Racket initialization.
*/
runtime_start_with_resources :: proc(
	runtime: ^Runtime,
	resources: Runtime_Resource_Paths,
) -> (ok: bool, failure: Failure_Context) {
	return runtime_start_mode(runtime, .Explicit, resources)
}

/*
runtime_start_bundled resolves resources from the Linux executable bundle. It
never consults the working directory, environment, source tree, or installed
Racket paths.
*/
runtime_start_bundled :: proc(runtime: ^Runtime) -> (ok: bool, failure: Failure_Context) {
	return runtime_start_mode(runtime, .Bundled, {})
}

@(private)
Runtime_Start_Mode :: enum u8 {
	Configured,
	Explicit,
	Bundled,
}

@(private)
runtime_start_mode :: proc(
	runtime: ^Runtime,
	mode: Runtime_Start_Mode,
	resources: Runtime_Resource_Paths,
) -> (ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if runtime.phase != .Uninitialized {
		set_diagnostic(runtime, "runtime_start requires the Uninitialized state")
		return false, failure_context(runtime, .Invalid_State)
	}

	runtime.phase = .Starting
	runtime.owner_thread_id = os.get_current_thread_id()
	clear_diagnostic(runtime)
	schema: [bridge.NATIVE_CONTRACT_SCHEMA_BYTES]u8
	encoded := bridge.native_contract_schema_encode(schema[:])
	assert(encoded)
	if ODRA_NATIVE_CONTRACT_SCHEMA_SCENARIO == 1 {
		schema[8] = schema[8] ~ 1
	}
	result: i32
	switch mode {
	case .Configured:
		result = odra_racket_runtime_start(
			raw_data(schema[:]),
			u64(len(schema)),
			raw_data(runtime.diagnostic[:]),
			DIAGNOSTIC_CAPACITY,
		)
	case .Explicit:
		result = odra_racket_runtime_start_with_resources(
			raw_data(schema[:]),
			u64(len(schema)),
			raw_data(transmute([]u8)resources.boot_directory),
			u64(len(resources.boot_directory)),
			raw_data(transmute([]u8)resources.collects_directory),
			u64(len(resources.collects_directory)),
			raw_data(transmute([]u8)resources.config_directory),
			u64(len(resources.config_directory)),
			raw_data(runtime.diagnostic[:]),
			DIAGNOSTIC_CAPACITY,
		)
	case .Bundled:
		result = odra_racket_runtime_start_bundled(
			raw_data(schema[:]),
			u64(len(schema)),
			raw_data(runtime.diagnostic[:]),
			DIAGNOSTIC_CAPACITY,
		)
	}
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if result != 0 {
		runtime.phase = .Failed
		return false, failure_context(runtime, adapter_failure_code(result))
	}

	runtime.phase = .Ready
	return true, {}
}

/*
runtime_shutdown synchronously quiesces the built-in module and releases Racket CS.
It accepts only Ready, rejects new lifecycle work while Stopping, and ends in Stopped.
*/
runtime_shutdown :: proc(runtime: ^Runtime) -> (ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if runtime.phase != .Ready {
		set_diagnostic(runtime, "runtime_shutdown requires the Ready state")
		return false, failure_context(runtime, .Invalid_State)
	}
	if os.get_current_thread_id() != runtime.owner_thread_id {
		return false, failure_context_message(
			runtime,
			.Wrong_Thread,
			"Racket runtime operation used the wrong owner thread",
		)
	}
	if runtime.call_active {
		set_diagnostic(runtime, "Racket runtime shutdown attempted during an active call")
		return false, failure_context(runtime, .Reentrant_Call)
	}

	runtime.phase = .Stopping
	clear_diagnostic(runtime)
	result := odra_racket_runtime_stop(raw_data(runtime.diagnostic[:]), DIAGNOSTIC_CAPACITY)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if result != 0 {
		runtime.phase = .Failed
		return false, failure_context(runtime, adapter_failure_code(result))
	}

	runtime.phase = .Stopped
	return true, {}
}

/*
runtime_call_scalar invokes the built-in checked scalar proof on the owner thread.
It rejects nested entry and returns a structured Racket or ABI failure without escaping.
*/
runtime_call_scalar :: proc(
	runtime: ^Runtime,
	input: i64,
) -> (result: i64, ok: bool, failure: Failure_Context) {
	return runtime_call_scalar_scenario(runtime, input, 0)
}

/*
runtime_command_inspection_request asks the built-in Racket command for one byte range.
The opaque capability and checked identity are scalar values, never native pointers.
*/
runtime_command_inspection_request :: proc(
	runtime: ^Runtime,
	capability, buffer_id, revision: u64,
) -> (request: Inspection_Request, ok: bool, failure: Failure_Context) {
	return runtime_command_inspection_request_scenario(
		runtime, capability, buffer_id, revision, ODRA_RACKET_COMMAND_SCENARIO,
	)
}

/*
runtime_command_transform gives Racket an owned byte copy and receives one copied request.
Replacement bytes are written into caller storage before the Racket call returns.
*/
runtime_command_transform :: proc(
	runtime: ^Runtime,
	capability, buffer_id, revision: u64,
	request: Inspection_Request,
	input: []byte,
	replacement: []byte,
) -> (result: Replacement_Request, ok: bool, failure: Failure_Context) {
	return runtime_command_transform_scenario(
		runtime,
		capability,
		buffer_id,
		revision,
		request,
		input,
		replacement,
		ODRA_RACKET_COMMAND_SCENARIO,
	)
}

/* runtime_load_keymap_profile copies and validates one complete Racket candidate. */
runtime_load_keymap_profile :: proc(
	runtime: ^Runtime,
	registry_generation: u64,
	allocator: base_runtime.Allocator,
) -> (candidate: Keymap_Profile_Candidate, ok: bool, failure: Failure_Context) {
	return runtime_load_keymap_profile_scenario(runtime, registry_generation, allocator, 0)
}

/* keymap_profile_candidate_view borrows records while the candidate remains live. */
keymap_profile_candidate_view :: proc(
	candidate: ^Keymap_Profile_Candidate,
) -> (view: Keymap_Profile_View, ok: bool) {
	if candidate == nil || candidate.closed || candidate.state == nil {
		return {}, false
	}
	state := cast(^Keymap_Profile_Candidate_State)candidate.state
	return state.view, true
}

/* keymap_profile_candidate_definition borrows the adapted native candidate. */
keymap_profile_candidate_definition :: proc(
	candidate: ^Keymap_Profile_Candidate,
) -> (definition: interaction.Profile_Definition, ok: bool) {
	if candidate == nil || candidate.closed || candidate.state == nil {
		return {}, false
	}
	state := cast(^Keymap_Profile_Candidate_State)candidate.state
	return state.definition, true
}

/* keymap_profile_candidate_catalog_definition borrows the complete adapted catalog. */
keymap_profile_candidate_catalog_definition :: proc(
	candidate: ^Keymap_Profile_Candidate,
) -> (definition: interaction.Profile_Catalog_Definition, ok: bool) {
	if candidate == nil || candidate.closed || candidate.state == nil {
		return {}, false
	}
	state := cast(^Keymap_Profile_Candidate_State)candidate.state
	return state.catalog_definition, true
}

/* keymap_profile_candidate_close deterministically releases copied profile storage. */
keymap_profile_candidate_close :: proc(candidate: ^Keymap_Profile_Candidate) {
	if candidate == nil || candidate.closed {
		return
	}
	state := cast(^Keymap_Profile_Candidate_State)candidate.state
	if state != nil {
		allocator := state.allocator
		keymap_profile_candidate_release_adaptation(state)
		if state.storage != nil {
			delete(state.storage, allocator)
		}
		free(state, allocator)
	}
	candidate.state = nil
	candidate.closed = true
}

/* runtime_load_command_catalog copies and validates one Racket command candidate. */
runtime_load_command_catalog :: proc(
	runtime: ^Runtime,
	registry_generation: interaction.Registry_Generation,
	allocator: base_runtime.Allocator,
) -> (candidate: Command_Catalog_Candidate, ok: bool, failure: Failure_Context) {
	return runtime_load_command_catalog_scenario(
		runtime,
		registry_generation,
		allocator,
		0,
	)
}

/* command_catalog_candidate_view borrows copied records while the candidate is live. */
command_catalog_candidate_view :: proc(
	candidate: ^Command_Catalog_Candidate,
) -> (view: Command_Catalog_View, ok: bool) {
	if candidate == nil || candidate.closed || candidate.state == nil {
		return {}, false
	}
	state := cast(^Command_Catalog_Candidate_State)candidate.state
	return state.view, true
}

/* command_catalog_candidate_definitions borrows adapted definitions for registration. */
command_catalog_candidate_definitions :: proc(
	candidate: ^Command_Catalog_Candidate,
) -> (definitions: []interaction.Command_Definition, ok: bool) {
	if candidate == nil || candidate.closed || candidate.state == nil {
		return nil, false
	}
	state := cast(^Command_Catalog_Candidate_State)candidate.state
	return state.definitions, true
}

/* command_catalog_candidate_close releases copied command catalog storage. */
command_catalog_candidate_close :: proc(candidate: ^Command_Catalog_Candidate) {
	if candidate == nil || candidate.closed {
		return
	}
	state := cast(^Command_Catalog_Candidate_State)candidate.state
	if state != nil {
		allocator := state.allocator
		if state.definitions != nil {
			delete(state.definitions, allocator)
		}
		if state.storage != nil {
			delete(state.storage, allocator)
		}
		free(state, allocator)
	}
	candidate.state = nil
	candidate.closed = true
}

/* runtime_history_policy_exchange copies one complete policy record through Racket. */
runtime_history_policy_exchange :: proc(
	runtime: ^Runtime,
	current: History_Policy_Record,
) -> (candidate: History_Policy_Record, ok: bool, failure: Failure_Context) {
	return runtime_history_policy_exchange_scenario(
		runtime,
		current,
		ODRA_RACKET_HISTORY_POLICY_SCENARIO,
	)
}

@(private)
runtime_history_policy_exchange_scenario :: proc(
	runtime: ^Runtime,
	current: History_Policy_Record,
	scenario: i32,
) -> (candidate: History_Policy_Record, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime history policy exchange requires the Ready state") {
		return {}, false, runtime_call_failure(runtime)
	}
	if current.generation == 0 {
		set_diagnostic(runtime, "runtime history policy exchange requires a policy generation")
		return {}, false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	input := current
	adapter_result := odra_racket_runtime_history_policy(
		scenario,
		&input,
		&candidate,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return {}, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	if candidate.generation != current.generation {
		set_diagnostic(runtime, "runtime history policy exchange returned a mismatched generation")
		return {}, false, failure_context(runtime, .Wrong_Result)
	}
	return candidate, true, {}
}

/* runtime_display_policy_exchange copies one complete display policy through Racket. */
runtime_display_policy_exchange :: proc(
	runtime: ^Runtime,
	current: Display_Policy_Record,
) -> (candidate: Display_Policy_Record, ok: bool, failure: Failure_Context) {
	return runtime_display_policy_exchange_scenario(
		runtime,
		current,
		ODRA_RACKET_DISPLAY_POLICY_SCENARIO,
	)
}

@(private)
runtime_display_policy_exchange_scenario :: proc(
	runtime: ^Runtime,
	current: Display_Policy_Record,
	scenario: i32,
) -> (candidate: Display_Policy_Record, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime display policy exchange requires the Ready state") {
		return {}, false, runtime_call_failure(runtime)
	}
	if current.generation == 0 {
		set_diagnostic(runtime, "runtime display policy exchange requires a policy generation")
		return {}, false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	input := current
	adapter_result := odra_racket_runtime_display_policy(
		scenario,
		&input,
		&candidate,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return {}, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	if candidate.generation != current.generation {
		set_diagnostic(runtime, "runtime display policy exchange returned a mismatched generation")
		return {}, false, failure_context(runtime, .Wrong_Result)
	}
	return candidate, true, {}
}

/*
runtime_uppercase_current_line invokes the rooted Racket command over copied UTF-8.
It returns only after replacement bytes have been copied into caller storage.
*/
runtime_uppercase_current_line :: proc(
	runtime: ^Runtime,
	capability, buffer_id, revision: u64,
	request: Inspection_Request,
	input: []byte,
	replacement: []byte,
) -> (result: Replacement_Request, ok: bool, failure: Failure_Context) {
	return runtime_uppercase_current_line_scenario(
		runtime,
		capability,
		buffer_id,
		revision,
		request,
		input,
		replacement,
		ODRA_RACKET_COMMAND_SCENARIO,
	)
}

/*
runtime_transaction_probe lends one opaque token to Racket for a synchronous command extent.
The callback and its user data remain caller-owned and are forgotten before return.
*/
runtime_transaction_probe :: proc(
	runtime: ^Runtime,
	scenario: i32,
	token, command_id: u64,
	callback: Scoped_Capability_Callback_Procedure,
	user_data: rawptr,
) -> (ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime transaction command requires the Ready state") {
		return false, runtime_call_failure(runtime)
	}
	if token == 0 || command_id == 0 || callback == nil {
		set_diagnostic(runtime, "runtime transaction command requires bounded callback identity")
		return false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_transaction_probe(
		scenario,
		token,
		command_id,
		callback,
		user_data,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	return true, {}
}

/* runtime_transaction_command invokes one facade-backed edit command. */
runtime_transaction_command :: proc(
	runtime: ^Runtime,
	scenario: i32,
	token, command_id, start, end: u64,
	command_name: string,
	callback: Scoped_Capability_Callback_Procedure,
	user_data: rawptr,
) -> (ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime transaction command requires the Ready state") {
		return false, runtime_call_failure(runtime)
	}
	if token == 0 || command_id == 0 || len(command_name) == 0 ||
	   start > end || callback == nil {
		set_diagnostic(runtime, "runtime transaction command requires checked scalar identity")
		return false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_transaction_command(
		scenario,
		token,
		command_id,
		raw_data(transmute([]u8)command_name),
		u64(len(command_name)),
		start,
		end,
		callback,
		user_data,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	return true, {}
}

/* runtime_personal_command invokes one generation-bound personal procedure. */
runtime_personal_command :: proc(
	runtime: ^Runtime,
	token, command_id: u64,
	command_name: string,
	document_path, project_root, candidate_selection: string,
	route_generation, route_slot, revision, point: u64,
	region_present: bool,
	region_start, region_end, line_start, line_end, buffer_end, effects: u64,
	cancelled: bool,
	callback: Scoped_Capability_Callback_Procedure,
	user_data: rawptr,
	result: []u8,
	result_length: ^u64,
) -> (ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime personal command requires the Ready state") {
		return false, runtime_call_failure(runtime)
	}
	if token == 0 || command_id == 0 || len(command_name) == 0 ||
	   route_generation == 0 || route_slot == 0 ||
	   point > buffer_end || line_start > line_end || line_end > buffer_end ||
	   (region_present && (region_start > region_end || region_end > buffer_end)) ||
	   callback == nil || len(result) == 0 || result_length == nil {
		set_diagnostic(runtime, "runtime personal command requires checked context identity")
		return false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_personal_command(
		token,
		command_id,
		raw_data(transmute([]u8)command_name),
		u64(len(command_name)),
		raw_data(transmute([]u8)document_path),
		u64(len(document_path)),
		raw_data(transmute([]u8)project_root),
		u64(len(project_root)),
		raw_data(transmute([]u8)candidate_selection),
		u64(len(candidate_selection)),
		route_generation,
		route_slot,
		revision,
		point,
		i32(region_present),
		region_start,
		region_end,
		line_start,
		line_end,
		buffer_end,
		effects,
		i32(cancelled),
		callback,
		user_data,
		raw_data(result),
		u64(len(result)),
		result_length,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	return true, {}
}

/*
runtime_transfer_probe lends one opaque token to Racket for one synchronous transfer turn.
The adapter forgets the callback and caller-owned data before this procedure returns.
*/
runtime_transfer_probe :: proc(
	runtime: ^Runtime,
	scenario: i32,
	token: u64,
	callback: Scoped_Capability_Callback_Procedure,
	user_data: rawptr,
) -> (ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime transfer command requires the Ready state") {
		return false, runtime_call_failure(runtime)
	}
	if token == 0 || callback == nil {
		set_diagnostic(runtime, "runtime transfer command requires bounded callback identity")
		return false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_transfer_probe(
		scenario,
		token,
		callback,
		user_data,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	return true, {}
}

/*
runtime_search_probe lends one opaque token to Racket for one synchronous search turn.
The adapter clears all callback state before this procedure returns.
*/
runtime_search_probe :: proc(
	runtime: ^Runtime,
	scenario: i32,
	token: u64,
	callback: Scoped_Capability_Callback_Procedure,
	user_data: rawptr,
) -> (ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime search command requires the Ready state") {
		return false, runtime_call_failure(runtime)
	}
	if token == 0 || callback == nil {
		set_diagnostic(runtime, "runtime search command requires bounded callback identity")
		return false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_search_probe(
		scenario,
		token,
		callback,
		user_data,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	return true, {}
}

/*
runtime_buffer_session_probe lends one opaque token for one synchronous session turn.
The adapter clears callback and caller-owned storage before this procedure returns.
*/
runtime_buffer_session_probe :: proc(
	runtime: ^Runtime,
	scenario: i32,
	token: u64,
	callback: Scoped_Capability_Callback_Procedure,
	user_data: rawptr,
) -> (ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime buffer session requires the Ready state") {
		return false, runtime_call_failure(runtime)
	}
	if token == 0 || callback == nil {
		set_diagnostic(runtime, "runtime buffer session requires bounded callback identity")
		return false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_buffer_session_probe(
		scenario,
		token,
		callback,
		user_data,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	return true, {}
}

/*
runtime_layout_probe lends one opaque token for one synchronous layout turn.
The adapter clears callback and caller-owned storage before this procedure returns.
*/
runtime_layout_probe :: proc(
	runtime: ^Runtime,
	scenario: i32,
	token: u64,
	callback: Scoped_Capability_Callback_Procedure,
	user_data: rawptr,
) -> (ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime layout capability requires the Ready state") {
		return false, runtime_call_failure(runtime)
	}
	if token == 0 || callback == nil {
		set_diagnostic(runtime, "runtime layout capability requires bounded callback identity")
		return false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_layout_probe(
		scenario,
		token,
		callback,
		user_data,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	return true, {}
}

/*
runtime_ui_role_probe lends one opaque token for one synchronous UI role turn.
The adapter clears callback and caller-owned storage before this procedure returns.
*/
runtime_ui_role_probe :: proc(
	runtime: ^Runtime,
	scenario: i32,
	token: u64,
	callback: Scoped_Capability_Callback_Procedure,
	user_data: rawptr,
) -> (ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime UI role capability requires the Ready state") {
		return false, runtime_call_failure(runtime)
	}
	if token == 0 || callback == nil {
		set_diagnostic(runtime, "runtime UI role capability requires bounded callback identity")
		return false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_ui_role_probe(
		scenario,
		token,
		callback,
		user_data,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	return true, {}
}

/*
runtime_theme_probe lends one opaque token for one synchronous theme turn.
The adapter clears callback and caller-owned storage before this procedure returns.
*/
runtime_theme_probe :: proc(
	runtime: ^Runtime,
	scenario: i32,
	token: u64,
	callback: Scoped_Capability_Callback_Procedure,
	user_data: rawptr,
) -> (ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime theme capability requires the Ready state") {
		return false, runtime_call_failure(runtime)
	}
	if token == 0 || callback == nil {
		set_diagnostic(runtime, "runtime theme capability requires bounded callback identity")
		return false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_theme_probe(
		scenario,
		token,
		callback,
		user_data,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	return true, {}
}

/*
runtime_structural_probe lends one opaque token for one synchronous structural turn.
The adapter clears callback and caller-owned storage before this procedure returns.
*/
runtime_structural_probe :: proc(
	runtime: ^Runtime,
	scenario: i32,
	token: u64,
	callback: Scoped_Capability_Callback_Procedure,
	user_data: rawptr,
) -> (ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime structural capability requires the Ready state") {
		return false, runtime_call_failure(runtime)
	}
	if token == 0 || callback == nil {
		set_diagnostic(runtime, "runtime structural capability requires bounded callback identity")
		return false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_structural_probe(
		scenario,
		token,
		callback,
		user_data,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	return true, {}
}

/*
runtime_language_service_probe lends one opaque token for one synchronous service turn.
The adapter clears callback and caller-owned storage before this procedure returns.
*/
runtime_language_service_probe :: proc(
	runtime: ^Runtime,
	scenario: i32,
	token: u64,
	callback: Scoped_Capability_Callback_Procedure,
	user_data: rawptr,
) -> (ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime language-service capability requires the Ready state") {
		return false, runtime_call_failure(runtime)
	}
	if token == 0 || callback == nil {
		set_diagnostic(runtime, "runtime language-service capability requires bounded callback identity")
		return false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_language_service_probe(
		scenario,
		token,
		callback,
		user_data,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	return true, {}
}

/*
runtime_result_probe lends one opaque token for one synchronous result-provider turn.
The adapter clears callback and caller-owned storage before this procedure returns.
*/
runtime_result_probe :: proc(
	runtime: ^Runtime,
	scenario: i32,
	token: u64,
	callback: Scoped_Capability_Callback_Procedure,
	user_data: rawptr,
) -> (ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime result capability requires the Ready state") {
		return false, runtime_call_failure(runtime)
	}
	if token == 0 || callback == nil {
		set_diagnostic(runtime, "runtime result capability requires bounded callback identity")
		return false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_result_probe(
		scenario,
		token,
		callback,
		user_data,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	return true, {}
}

/*
runtime_status_bar_probe lends one opaque token for one synchronous Status Bar provider turn.
The adapter clears callback and caller-owned storage before this procedure returns.
*/
runtime_status_bar_probe :: proc(
	runtime: ^Runtime,
	scenario: i32,
	token: u64,
	callback: Scoped_Capability_Callback_Procedure,
	user_data: rawptr,
) -> (ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime Status Bar capability requires the Ready state") {
		return false, runtime_call_failure(runtime)
	}
	if token == 0 || callback == nil {
		set_diagnostic(runtime, "runtime Status Bar capability requires bounded callback identity")
		return false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_status_bar_probe(
		scenario,
		token,
		callback,
		user_data,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	return true, {}
}

/*
runtime_terminal_probe lends one opaque token for one synchronous terminal facade turn.
The adapter clears callback and caller-owned storage before this procedure returns.
*/
runtime_terminal_probe :: proc(
	runtime: ^Runtime,
	scenario: i32,
	token: u64,
	callback: Scoped_Capability_Callback_Procedure,
	user_data: rawptr,
) -> (ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime terminal capability requires the Ready state") {
		return false, runtime_call_failure(runtime)
	}
	if token == 0 || callback == nil {
		set_diagnostic(runtime, "runtime terminal capability requires bounded callback identity")
		return false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_terminal_probe(
		scenario,
		token,
		callback,
		user_data,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	return true, {}
}

@(private)
runtime_uppercase_current_line_scenario :: proc(
	runtime: ^Runtime,
	capability, buffer_id, revision: u64,
	request: Inspection_Request,
	input: []byte,
	replacement: []byte,
	scenario: i32,
) -> (result: Replacement_Request, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime uppercase command requires the Ready state") {
		return {}, false, runtime_call_failure(runtime)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_uppercase_line(
		scenario,
		capability,
		buffer_id,
		revision,
		request.start,
		request.end,
		raw_data(input),
		u64(len(input)),
		&result.start,
		&result.end,
		raw_data(replacement),
		u64(len(replacement)),
		&result.replacement_bytes,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return {}, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	return result, true, {}
}

/* runtime_state returns the current synchronous lifecycle phase. */
runtime_state :: proc(runtime: ^Runtime) -> State {
	assert(runtime != nil)
	return runtime.phase
}

/*
runtime_diagnostic returns a Runtime-owned UTF-8 view of the latest lifecycle failure.
The view remains valid until the next operation on the same Runtime.
*/
runtime_diagnostic :: proc(runtime: ^Runtime) -> string {
	assert(runtime != nil)
	return string(runtime.diagnostic[:runtime.diagnostic_length])
}

/* runtime_platform_roots copies and decodes the single startup path policy. */
runtime_platform_roots :: proc(
	runtime: ^Runtime,
	allocator: base_runtime.Allocator,
) -> (roots: Platform_Roots, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime platform roots require the Ready state") {
		return {}, false, runtime_call_failure(runtime)
	}
	if allocator.procedure == nil {
		set_diagnostic(runtime, "runtime platform roots require persistent storage")
		return {}, false, failure_context(runtime, .Runtime_Unavailable)
	}
	storage, allocation_error := make([]byte, MAX_PLATFORM_ROOTS_BYTES, allocator)
	if allocation_error != nil {
		set_diagnostic(runtime, "runtime platform root allocation failed")
		return {}, false, failure_context(runtime, .Runtime_Unavailable)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	output_length: u64
	adapter_result := odra_racket_runtime_platform_roots(
		raw_data(storage),
		u64(len(storage)),
		&output_length,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		delete(storage, allocator)
		return {}, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	if output_length < 72 || output_length > u64(len(storage)) {
		delete(storage, allocator)
		set_diagnostic(runtime, "runtime platform roots returned an invalid copied width")
		return {}, false, failure_context(runtime, .Wrong_Result)
	}
	storage = storage[:int(output_length)]
	header: [9]u64
	for &value, index in header {
		value, ok = endian.get_u64(storage[index * 8:], .Little)
		if !ok {
			delete(storage, allocator)
			set_diagnostic(runtime, "runtime platform roots returned a truncated header")
			return {}, false, failure_context(runtime, .Wrong_Result)
		}
	}
	expected_platform := Platform_Roots_Platform.Invalid
	when ODIN_OS == .Linux do expected_platform = .Linux
	when ODIN_OS == .Darwin do expected_platform = .Darwin
	when ODIN_OS == .Windows do expected_platform = .Windows
	total := u64(72)
	for length in header[2:] {
		if length == 0 || length > 4096 || total > u64(len(storage)) - length {
			delete(storage, allocator)
			set_diagnostic(runtime, "runtime platform roots returned invalid path bounds")
			return {}, false, failure_context(runtime, .Wrong_Result)
		}
		total += length
	}
	if header[0] != 1 || header[1] != u64(expected_platform) || total != u64(len(storage)) {
		delete(storage, allocator)
		set_diagnostic(runtime, "runtime platform roots returned an incompatible schema")
		return {}, false, failure_context(runtime, .Wrong_Result)
	}
	offset := u64(72)
	paths: [7]string
	for &path, index in paths {
		length := header[index + 2]
		path = string(storage[int(offset):int(offset + length)])
		offset += length
	}
	return Platform_Roots {
		platform = expected_platform,
		home = paths[0],
		configuration = paths[1],
		state = paths[2],
		cache = paths[3],
		package_data = paths[4],
		project_catalog = paths[5],
		legacy_projects = paths[6],
		storage = storage,
		allocator = allocator,
	}, true, {}
}

/* platform_roots_close releases one copied startup path record. */
platform_roots_close :: proc(roots: ^Platform_Roots) -> bool {
	if roots == nil || len(roots.storage) == 0 || roots.allocator.procedure == nil do return false
	delete(roots.storage, roots.allocator)
	roots^ = {}
	return true
}

/*
runtime_project_directory_resolution copies one bounded exact-path catalog result.
The caller owns output and Racket retains neither input nor output storage.
*/
runtime_project_directory_resolution :: proc(
	runtime: ^Runtime,
	projects_directory, directory: string,
	output: []byte,
) -> (output_length: u64, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime Project directory resolution requires the Ready state") {
		return 0, false, runtime_call_failure(runtime)
	}
	if len(projects_directory) == 0 || len(directory) == 0 ||
	   len(output) < MAX_PROJECT_DIRECTORY_RESOLUTION_BYTES {
		set_diagnostic(runtime, "runtime Project directory resolution requires bounded copied storage")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_project_directory_resolution(
		raw_data(transmute([]u8)projects_directory),
		u64(len(projects_directory)),
		raw_data(transmute([]u8)directory),
		u64(len(directory)),
		raw_data(output),
		u64(len(output)),
		&output_length,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return 0, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	if output_length == 0 || output_length > u64(len(output)) {
		set_diagnostic(runtime, "runtime Project directory resolution returned an invalid copied width")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	return output_length, true, {}
}

/*
runtime_project_catalog_resolution copies one bounded validated global Project catalog.
The caller owns output and Racket retains neither input nor output storage.
*/
runtime_project_catalog_resolution :: proc(
	runtime: ^Runtime,
	configuration_root: string,
	output: []byte,
) -> (output_length: u64, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime Project catalog resolution requires the Ready state") {
		return 0, false, runtime_call_failure(runtime)
	}
	if len(configuration_root) == 0 || len(output) < MAX_PROJECT_DIRECTORY_RESOLUTION_BYTES {
		set_diagnostic(runtime, "runtime Project catalog resolution requires bounded copied storage")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_project_catalog_resolution(
		raw_data(transmute([]u8)configuration_root),
		u64(len(configuration_root)),
		raw_data(output),
		u64(len(output)),
		&output_length,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return 0, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	if output_length == 0 || output_length > u64(len(output)) {
		set_diagnostic(runtime, "runtime Project catalog resolution returned an invalid copied width")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	return output_length, true, {}
}

/*
runtime_personal_configuration_startup copies one bounded personal init.rkt startup result.
The caller owns output and Racket retains neither input nor output storage.
*/
runtime_personal_configuration_startup :: proc(
	runtime: ^Runtime,
	configuration_root: string,
	output: []byte,
) -> (output_length: u64, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime personal configuration startup requires the Ready state") {
		return 0, false, runtime_call_failure(runtime)
	}
	if len(configuration_root) == 0 || len(output) < MAX_PERSONAL_CONFIGURATION_STARTUP_BYTES {
		set_diagnostic(runtime, "runtime personal configuration startup requires bounded copied storage")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_personal_configuration_startup(
		raw_data(transmute([]u8)configuration_root),
		u64(len(configuration_root)),
		raw_data(output),
		u64(len(output)),
		&output_length,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return 0, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	if output_length < 48 || output_length > u64(len(output)) {
		set_diagnostic(runtime, "runtime personal configuration startup returned an invalid copied width")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	return output_length, true, {}
}

/* runtime_personal_configuration_reload prepares one fresh configuration candidate. */
runtime_personal_configuration_reload :: proc(
	runtime: ^Runtime,
	configuration_root: string,
	expected_generation: u64,
	output: []byte,
) -> (output_length: u64, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime personal configuration reload requires the Ready state") {
		return 0, false, runtime_call_failure(runtime)
	}
	if len(configuration_root) == 0 || expected_generation == 0 ||
	   len(output) < MAX_PERSONAL_CONFIGURATION_STARTUP_BYTES {
		set_diagnostic(runtime, "runtime personal configuration reload requires bounded copied storage")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_personal_configuration_reload(
		raw_data(transmute([]u8)configuration_root),
		u64(len(configuration_root)),
		expected_generation,
		raw_data(output),
		u64(len(output)),
		&output_length,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return 0, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	if output_length < 48 || output_length > u64(len(output)) {
		set_diagnostic(runtime, "runtime personal configuration reload returned an invalid copied width")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	return output_length, true, {}
}

/* runtime_provider_invoke evaluates one bounded semantic provider turn. */
runtime_provider_invoke :: proc(
	runtime: ^Runtime,
	service: string,
	generation, operation: u64,
	name: string,
	payload, output: []byte,
) -> (output_length: u64, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime provider invocation requires the Ready state") {
		return 0, false, runtime_call_failure(runtime)
	}
	if len(service) == 0 || len(output) == 0 {
		set_diagnostic(runtime, "runtime provider invocation requires a service and copied output storage")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_provider_invoke(
		raw_data(transmute([]u8)service),
		u64(len(service)),
		generation,
		operation,
		raw_data(transmute([]u8)name),
		u64(len(name)),
		raw_data(payload),
		u64(len(payload)),
		raw_data(output),
		u64(len(output)),
		&output_length,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return 0, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	if output_length > u64(len(output)) {
		set_diagnostic(runtime, "runtime provider invocation returned an invalid copied width")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	return output_length, true, {}
}
/* runtime_personal_generation_transition confirms or discards one prepared generation. */
runtime_personal_generation_transition :: proc(
	runtime: ^Runtime,
	transition, generation: u64,
) -> (ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime personal generation transition requires the Ready state") {
		return false, runtime_call_failure(runtime)
	}
	if transition == 0 || generation == 0 {
		set_diagnostic(runtime, "runtime personal generation transition requires checked identity")
		return false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_personal_generation_transition(
		transition,
		generation,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	return true, {}
}

/* runtime_project_promotion publishes one exact copied Dir promotion request. */
runtime_project_promotion :: proc(
	runtime: ^Runtime,
	configuration_root, directory, name: string,
	output: []byte,
) -> (output_length: u64, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime Project promotion requires the Ready state") {
		return 0, false, runtime_call_failure(runtime)
	}
	if len(configuration_root) == 0 || len(directory) == 0 || len(name) == 0 ||
	   len(output) < MAX_PROJECT_PROMOTION_BYTES {
		set_diagnostic(runtime, "runtime Project promotion requires bounded copied storage")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_project_promotion(
		raw_data(transmute([]u8)configuration_root),
		u64(len(configuration_root)),
		raw_data(transmute([]u8)directory),
		u64(len(directory)),
		raw_data(transmute([]u8)name),
		u64(len(name)),
		raw_data(output),
		u64(len(output)),
		&output_length,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return 0, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	if output_length < 32 || output_length > u64(len(output)) {
		set_diagnostic(runtime, "runtime Project promotion returned an invalid copied width")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	return output_length, true, {}
}

/* runtime_project_rename publishes one exact copied Project name replacement. */
runtime_project_rename :: proc(
	runtime: ^Runtime,
	configuration_root, directory, name: string,
	generation: u64,
	output: []byte,
) -> (output_length: u64, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime Project rename requires the Ready state") {
		return 0, false, runtime_call_failure(runtime)
	}
	if len(configuration_root) == 0 || len(directory) == 0 || len(name) == 0 ||
	   generation == 0 || len(output) < MAX_PROJECT_PROMOTION_BYTES {
		set_diagnostic(runtime, "runtime Project rename requires bounded copied storage")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_project_rename(
		raw_data(transmute([]u8)configuration_root), u64(len(configuration_root)),
		raw_data(transmute([]u8)directory), u64(len(directory)),
		raw_data(transmute([]u8)name), u64(len(name)), generation,
		raw_data(output), u64(len(output)), &output_length,
		raw_data(runtime.diagnostic[:]), DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return 0, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	if output_length < 32 || output_length > u64(len(output)) {
		set_diagnostic(runtime, "runtime Project rename returned an invalid copied width")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	return output_length, true, {}
}

/* runtime_project_unregister removes one exact global Project discovery reference. */
runtime_project_unregister :: proc(
	runtime: ^Runtime,
	configuration_root, id, root: string,
	generation: u64,
	output: []byte,
) -> (output_length: u64, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime Project unregister requires the Ready state") {
		return 0, false, runtime_call_failure(runtime)
	}
	if len(configuration_root) == 0 || len(id) == 0 || len(root) == 0 || generation == 0 ||
	   len(output) < MAX_PROJECT_PROMOTION_BYTES {
		set_diagnostic(runtime, "runtime Project unregister requires bounded copied storage")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_project_unregister(
		raw_data(transmute([]u8)configuration_root),
		u64(len(configuration_root)),
		raw_data(transmute([]u8)id),
		u64(len(id)),
		raw_data(transmute([]u8)root),
		u64(len(root)),
		generation,
		raw_data(output),
		u64(len(output)),
		&output_length,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return 0, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	if output_length < 32 || output_length > u64(len(output)) {
		set_diagnostic(runtime, "runtime Project unregister returned an invalid copied width")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	return output_length, true, {}
}

/* runtime_promotion_suppression inspects or updates one exact global Dir preference. */
runtime_promotion_suppression :: proc(
	runtime: ^Runtime,
	configuration_root, directory: string,
	action: u64,
	output: []byte,
) -> (output_length: u64, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime promotion suppression requires the Ready state") {
		return 0, false, runtime_call_failure(runtime)
	}
	if len(configuration_root) == 0 || len(directory) == 0 || action < 1 || action > 3 ||
	   len(output) < MAX_PROJECT_PROMOTION_BYTES {
		set_diagnostic(runtime, "runtime promotion suppression requires bounded copied storage")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_promotion_suppression(
		raw_data(transmute([]u8)configuration_root),
		u64(len(configuration_root)),
		raw_data(transmute([]u8)directory),
		u64(len(directory)),
		action,
		raw_data(output),
		u64(len(output)),
		&output_length,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return 0, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	if output_length < 40 || output_length > u64(len(output)) {
		set_diagnostic(runtime, "runtime promotion suppression returned an invalid copied width")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	return output_length, true, {}
}

/* runtime_workspace_command copies one bounded programmable Workspace exchange. */
runtime_workspace_command :: proc(
	runtime: ^Runtime,
	configuration_root: string,
	request, output: []byte,
) -> (output_length: u64, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime Workspace command requires the Ready state") {
		return 0, false, runtime_call_failure(runtime)
	}
	if len(configuration_root) == 0 || len(request) == 0 ||
	   len(request) > MAX_WORKSPACE_COMMAND_BYTES || len(output) < 88 {
		set_diagnostic(runtime, "runtime Workspace command requires bounded copied storage")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_workspace_command(
		raw_data(transmute([]u8)configuration_root),
		u64(len(configuration_root)),
		raw_data(request),
		u64(len(request)),
		raw_data(output),
		u64(len(output)),
		&output_length,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return 0, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	if output_length < 88 || output_length > u64(len(output)) {
		set_diagnostic(runtime, "runtime Workspace command returned an invalid copied width")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	return output_length, true, {}
}

/* runtime_named_location_command copies one bounded persistent location exchange. */
runtime_named_location_command :: proc(
	runtime: ^Runtime,
	configuration_root: string,
	request, output: []byte,
) -> (output_length: u64, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime named-location command requires the Ready state") {
		return 0, false, runtime_call_failure(runtime)
	}
	if len(configuration_root) == 0 || len(request) == 0 ||
	   len(request) > MAX_NAMED_LOCATION_COMMAND_BYTES || len(output) < 48 {
		set_diagnostic(runtime, "runtime named-location command requires bounded copied storage")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_named_location_command(
		raw_data(transmute([]u8)configuration_root),
		u64(len(configuration_root)),
		raw_data(request),
		u64(len(request)),
		raw_data(output),
		u64(len(output)),
		&output_length,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return 0, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	if output_length < 48 || output_length > u64(len(output)) {
		set_diagnostic(runtime, "runtime named-location command returned an invalid copied width")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	return output_length, true, {}
}

/* runtime_named_slot_command copies one bounded persistent slot exchange. */
runtime_named_slot_command :: proc(
	runtime: ^Runtime,
	configuration_root: string,
	request, output: []byte,
) -> (output_length: u64, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime named-slot command requires the Ready state") {
		return 0, false, runtime_call_failure(runtime)
	}
	if len(configuration_root) == 0 || len(request) == 0 ||
	   len(request) > MAX_NAMED_SLOT_COMMAND_BYTES || len(output) < 48 {
		set_diagnostic(runtime, "runtime named-slot command requires bounded copied storage")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_named_slot_command(
		raw_data(transmute([]u8)configuration_root),
		u64(len(configuration_root)),
		raw_data(request),
		u64(len(request)),
		raw_data(output),
		u64(len(output)),
		&output_length,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return 0, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	if output_length < 48 || output_length > u64(len(output)) {
		set_diagnostic(runtime, "runtime named-slot command returned an invalid copied width")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	return output_length, true, {}
}

/* runtime_package_catalog_command copies one bounded package-catalog exchange. */
runtime_package_catalog_command :: proc(
	runtime: ^Runtime,
	configuration_root: string,
	request, output: []byte,
) -> (output_length: u64, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime package-catalog command requires the Ready state") {
		return 0, false, runtime_call_failure(runtime)
	}
	if len(configuration_root) == 0 || len(request) == 0 ||
	   len(request) > MAX_PACKAGE_CATALOG_COMMAND_BYTES || len(output) < 56 {
		set_diagnostic(runtime, "runtime package-catalog command requires bounded copied storage")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_package_catalog_command(
		raw_data(transmute([]u8)configuration_root),
		u64(len(configuration_root)),
		raw_data(request),
		u64(len(request)),
		raw_data(output),
		u64(len(output)),
		&output_length,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return 0, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	if output_length < 56 || output_length > u64(len(output)) {
		set_diagnostic(runtime, "runtime package-catalog command returned an invalid copied width")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	return output_length, true, {}
}

/* runtime_candidate_usage_load copies one bounded Project history observation. */
runtime_candidate_usage_load :: proc(
	runtime: ^Runtime,
	state_root, project_id: string,
	output: []byte,
) -> (output_length: u64, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime candidate usage load requires the Ready state") {
		return 0, false, runtime_call_failure(runtime)
	}
	if len(state_root) == 0 || len(project_id) == 0 ||
	   len(output) < MAX_CANDIDATE_HISTORY_BYTES {
		set_diagnostic(runtime, "runtime candidate usage load requires bounded copied storage")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_candidate_usage_load(
		raw_data(transmute([]u8)state_root),
		u64(len(state_root)),
		raw_data(transmute([]u8)project_id),
		u64(len(project_id)),
		raw_data(output),
		u64(len(output)),
		&output_length,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return 0, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	if output_length < bridge.CANDIDATE_HISTORY_LOAD_HEADER_BYTES ||
	   output_length > u64(len(output)) {
		set_diagnostic(runtime, "runtime candidate usage load returned an invalid copied width")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	return output_length, true, {}
}

/* runtime_candidate_usage_publish persists one exact copied Project history snapshot. */
runtime_candidate_usage_publish :: proc(
	runtime: ^Runtime,
	state_root, project_id: string,
	request, output: []byte,
) -> (output_length: u64, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime candidate usage persistence requires the Ready state") {
		return 0, false, runtime_call_failure(runtime)
	}
	if len(state_root) == 0 || len(project_id) == 0 || len(request) == 0 ||
	   len(request) > MAX_CANDIDATE_HISTORY_BYTES ||
	   u64(len(output)) < bridge.CANDIDATE_HISTORY_PUBLICATION_BYTES {
		set_diagnostic(runtime, "runtime candidate usage persistence requires bounded copied storage")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_candidate_usage_publish(
		raw_data(transmute([]u8)state_root),
		u64(len(state_root)),
		raw_data(transmute([]u8)project_id),
		u64(len(project_id)),
		raw_data(request),
		u64(len(request)),
		raw_data(output),
		u64(len(output)),
		&output_length,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return 0, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	if output_length != bridge.CANDIDATE_HISTORY_PUBLICATION_BYTES {
		set_diagnostic(runtime, "runtime candidate usage persistence returned an invalid copied width")
		return 0, false, failure_context(runtime, .Wrong_Result)
	}
	return output_length, true, {}
}

@(private)
clear_diagnostic :: proc(runtime: ^Runtime) {
	runtime.diagnostic = {}
	runtime.diagnostic_length = 0
}

@(private)
set_diagnostic :: proc(runtime: ^Runtime, message: string) {
	clear_diagnostic(runtime)
	length := min(len(message), DIAGNOSTIC_CAPACITY - 1)
	copy(runtime.diagnostic[:length], transmute([]u8)message[:length])
	runtime.diagnostic_length = u16(length)
}

@(private)
diagnostic_length :: proc(diagnostic: []u8) -> u16 {
	for value, index in diagnostic {
		if value == 0 {
			return u16(index)
		}
	}
	return u16(len(diagnostic))
}

@(private)
runtime_load_command_catalog_scenario :: proc(
	runtime: ^Runtime,
	registry_generation: interaction.Registry_Generation,
	allocator: base_runtime.Allocator,
	scenario: i32,
) -> (candidate: Command_Catalog_Candidate, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime command catalog transfer requires the Ready state") {
		return {}, false, runtime_call_failure(runtime)
	}
	if registry_generation == interaction.Registry_Generation(0) || allocator.procedure == nil {
		set_diagnostic(runtime, "runtime command catalog transfer requires identity and storage")
		return {}, false, failure_context(runtime, .Runtime_Unavailable)
	}
	state, allocation_error := new(Command_Catalog_Candidate_State, allocator)
	if allocation_error != nil {
		set_diagnostic(runtime, "runtime command catalog state allocation failed")
		return {}, false, failure_context(runtime, .Runtime_Unavailable)
	}
	state.allocator = allocator
	state.storage, allocation_error = make(
		[]byte,
		int(bridge.MAX_COMMAND_CATALOG_COPY_BYTES),
		allocator,
	)
	if allocation_error != nil {
		free(state, allocator)
		set_diagnostic(runtime, "runtime command catalog storage allocation failed")
		return {}, false, failure_context(runtime, .Runtime_Unavailable)
	}

	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	output_length: u64
	adapter_result := odra_racket_runtime_load_command_catalog(
		scenario,
		u64(registry_generation),
		raw_data(state.storage),
		u64(len(state.storage)),
		&output_length,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		delete(state.storage, allocator)
		free(state, allocator)
		return {}, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	if output_length < bridge.COMMAND_CATALOG_HEADER_BYTES ||
	   output_length > bridge.MAX_COMMAND_CATALOG_COPY_BYTES {
		delete(state.storage, allocator)
		free(state, allocator)
		set_diagnostic(runtime, "runtime command catalog returned an invalid copied width")
		return {}, false, failure_context(runtime, .Wrong_Result)
	}
	state.storage = state.storage[:int(output_length)]
	if !command_catalog_candidate_parse(state, registry_generation) {
		delete(state.storage, allocator)
		free(state, allocator)
		set_diagnostic(runtime, "runtime command catalog returned malformed copied records")
		return {}, false, failure_context(runtime, .Wrong_Result)
	}
	if !command_catalog_candidate_adapt(state) {
		delete(state.storage, allocator)
		free(state, allocator)
		set_diagnostic(runtime, "runtime command catalog adaptation exceeded private storage")
		return {}, false, failure_context(runtime, .Runtime_Unavailable)
	}
	return Command_Catalog_Candidate{state = state}, true, {}
}

@(private)
command_catalog_candidate_parse :: proc(
	state: ^Command_Catalog_Candidate_State,
	expected_generation: interaction.Registry_Generation,
) -> bool {
	storage := state.storage
	header := (cast(^bridge.Command_Catalog_Header_Record)raw_data(storage))^
	expected_bytes, size_failure := bridge.command_catalog_record_bytes(
		header.command_count,
		header.text_bytes,
	)
	if size_failure.code != .None || expected_bytes != u64(len(storage)) ||
	   header.record_bytes != expected_bytes {
		return false
	}
	offset := bridge.COMMAND_CATALOG_HEADER_BYTES
	state.view.header = header
	state.view.records = mem.slice_ptr(
		cast(^bridge.Command_Catalog_Record)raw_data(storage[int(offset):]),
		int(header.command_count),
	)
	offset += header.command_count * bridge.COMMAND_CATALOG_RECORD_BYTES
	state.view.text = storage[int(offset):]
	failure := bridge.command_catalog_records_validate(
		header,
		state.view.records,
		state.view.text,
		expected_generation,
	)
	return failure.code == .None
}

@(private)
command_catalog_candidate_adapt :: proc(state: ^Command_Catalog_Candidate_State) -> bool {
	allocation_error: base_runtime.Allocator_Error
	state.definitions, allocation_error = make(
		[]interaction.Command_Definition,
		len(state.view.records),
		state.allocator,
	)
	if allocation_error != nil {
		return false
	}
	personal_slot: u16
	for record, index in state.view.records {
		dispatch_class := bridge.Command_Dispatch_Class(record.dispatch_class)
		provider := bridge.RACKET_INSPECTION_COMMAND_PROVIDER_ID
		if dispatch_class == .Transaction {
			provider = bridge.RACKET_TRANSACTION_COMMAND_PROVIDER_ID
		} else if dispatch_class == .Personal {
			provider = bridge.RACKET_PERSONAL_COMMAND_PROVIDER_ID
		} else if dispatch_class == .Ksawery_Extension {
			provider = bridge.RACKET_KSAWERY_COMMAND_PROVIDER_ID
		}
		provenance_provider := bridge.command_catalog_text(
			state.view.text,
			record.provider_offset,
			record.provider_bytes,
		)
		operation := u16(index + 1)
		if dispatch_class == .Personal {
			personal_slot += 1
			operation = personal_slot
		}
		state.definitions[index] = interaction.Command_Definition {
			name = bridge.command_catalog_text(
				state.view.text,
				record.name_offset,
				record.name_bytes,
			),
			route = {
				provider = provider,
				operation = operation,
			},
			implementation = .Racket,
			invocation = interaction.Invocation_Class(record.invocation),
			text_requirement = interaction.Text_Requirement(record.text_requirement),
			effects = transmute(interaction.Command_Effects)u8(record.effects),
			description = bridge.command_catalog_text(
				state.view.text,
				record.description_offset,
				record.description_bytes,
			),
			interactive = record.interactive == 1,
			requirements = transmute(interaction.Command_Requirements)u8(record.requirements),
			provenance = {
				provider = provenance_provider,
				source = bridge.command_catalog_text(
					state.view.text,
					record.source_offset,
					record.source_bytes,
				),
				location = bridge.command_catalog_text(
					state.view.text,
					record.location_offset,
					record.location_bytes,
				),
			},
		}
	}
	return true
}

@(private)
runtime_load_keymap_profile_scenario :: proc(
	runtime: ^Runtime,
	registry_generation: u64,
	allocator: base_runtime.Allocator,
	scenario: i32,
) -> (candidate: Keymap_Profile_Candidate, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime keymap profile transfer requires the Ready state") {
		return {}, false, runtime_call_failure(runtime)
	}
	if registry_generation == 0 || allocator.procedure == nil {
		set_diagnostic(runtime, "runtime keymap profile transfer requires identity and storage")
		return {}, false, failure_context(runtime, .Runtime_Unavailable)
	}
	state, allocation_error := new(Keymap_Profile_Candidate_State, allocator)
	if allocation_error != nil {
		set_diagnostic(runtime, "runtime keymap profile state allocation failed")
		return {}, false, failure_context(runtime, .Runtime_Unavailable)
	}
	state.allocator = allocator
	state.storage, allocation_error = make(
		[]byte,
		int(bridge.MAX_KEYMAP_PROFILE_COPY_BYTES),
		allocator,
	)
	if allocation_error != nil {
		free(state, allocator)
		set_diagnostic(runtime, "runtime keymap profile storage allocation failed")
		return {}, false, failure_context(runtime, .Runtime_Unavailable)
	}

	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	output_length: u64
	adapter_result := odra_racket_runtime_load_keymap_profile(
		scenario,
		registry_generation,
		raw_data(state.storage),
		u64(len(state.storage)),
		&output_length,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		delete(state.storage, allocator)
		free(state, allocator)
		return {}, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	if output_length < bridge.KEYMAP_PROFILE_HEADER_RECORD_BYTES ||
	   output_length > bridge.MAX_KEYMAP_PROFILE_COPY_BYTES {
		delete(state.storage, allocator)
		free(state, allocator)
		set_diagnostic(runtime, "runtime keymap profile returned an invalid copied width")
		return {}, false, failure_context(runtime, .Wrong_Result)
	}
	state.storage = state.storage[:int(output_length)]
	parsed, record_failure := keymap_profile_candidate_parse(state)
	if !parsed {
		delete(state.storage, allocator)
		free(state, allocator)
		diagnostic_storage: [192]u8
		set_diagnostic(
			runtime,
			fmt.bprintf(
				diagnostic_storage[:],
				"runtime keymap profile rejected copied records: code=%v index=%d limit=%d actual=%d",
				record_failure.code,
				record_failure.index,
				record_failure.limit,
				record_failure.actual,
			),
		)
		return {}, false, failure_context(runtime, .Wrong_Result)
	}
	adapted := keymap_profile_candidate_adapt(state)
	if !adapted {
		keymap_profile_candidate_release_adaptation(state)
		delete(state.storage, allocator)
		free(state, allocator)
		set_diagnostic(runtime, "runtime keymap profile adaptation exceeded private storage")
		return {}, false, failure_context(runtime, .Runtime_Unavailable)
	}
	if state.view.header.registry_generation != registry_generation {
		keymap_profile_candidate_release_adaptation(state)
		delete(state.storage, allocator)
		free(state, allocator)
		set_diagnostic(runtime, "runtime keymap profile returned a stale registry generation")
		return {}, false, failure_context(runtime, .Wrong_Result)
	}
	return Keymap_Profile_Candidate{state = state}, true, {}
}

@(private)
keymap_profile_candidate_parse :: proc(
	state: ^Keymap_Profile_Candidate_State,
) -> (ok: bool, failure: bridge.Keymap_Record_Failure) {
	storage := state.storage
	header := (cast(^bridge.Keymap_Profile_Header_Record)raw_data(storage))^
	expected_bytes, size_failure := bridge.keymap_profile_record_bytes(
		header.profile_count, header.state_count, header.map_count, header.binding_count,
		header.selector_count, header.surface_count, header.remap_count,
		header.ordering_count, header.stroke_count, header.text_bytes,
	)
	if size_failure.code != .None || expected_bytes != u64(len(storage)) ||
	   header.record_bytes != expected_bytes {
		if size_failure.code != .None {
			return false, size_failure
		}
		return false, {code = .Size_Mismatch, limit = expected_bytes, actual = u64(len(storage))}
	}

	offset := bridge.KEYMAP_PROFILE_HEADER_RECORD_BYTES
	state.view.header = header
	state.view.profiles = mem.slice_ptr(
		cast(^bridge.Keymap_Profile_Record)raw_data(storage[int(offset):]),
		int(header.profile_count),
	)
	offset += header.profile_count * bridge.KEYMAP_PROFILE_RECORD_BYTES
	state.view.states = mem.slice_ptr(
		cast(^bridge.Keymap_State_Record)raw_data(storage[int(offset):]),
		int(header.state_count),
	)
	offset += header.state_count * bridge.KEYMAP_STATE_RECORD_BYTES
	state.view.maps = mem.slice_ptr(
		cast(^bridge.Keymap_Map_Record)raw_data(storage[int(offset):]),
		int(header.map_count),
	)
	offset += header.map_count * bridge.KEYMAP_MAP_RECORD_BYTES
	if header.binding_count > 0 {
		state.view.bindings = mem.slice_ptr(
			cast(^bridge.Keymap_Binding_Record)raw_data(storage[int(offset):]),
			int(header.binding_count),
		)
	}
	offset += header.binding_count * bridge.KEYMAP_BINDING_RECORD_BYTES
	if header.selector_count > 0 {
		state.view.selectors = mem.slice_ptr(
			cast(^bridge.Keymap_Selector_Record)raw_data(storage[int(offset):]),
			int(header.selector_count),
		)
	}
	offset += header.selector_count * bridge.KEYMAP_SELECTOR_RECORD_BYTES
	state.view.surfaces = mem.slice_ptr(
		cast(^bridge.Keymap_Surface_Record)raw_data(storage[int(offset):]),
		int(header.surface_count),
	)
	offset += header.surface_count * bridge.KEYMAP_SURFACE_RECORD_BYTES
	if header.remap_count > 0 {
		state.view.remaps = mem.slice_ptr(
			cast(^bridge.Keymap_Remap_Record)raw_data(storage[int(offset):]),
			int(header.remap_count),
		)
	}
	offset += header.remap_count * bridge.KEYMAP_REMAP_RECORD_BYTES
	if header.ordering_count > 0 {
		state.view.ordering = mem.slice_ptr(
			cast(^bridge.Keymap_Ordering_Record)raw_data(storage[int(offset):]),
			int(header.ordering_count),
		)
	}
	offset += header.ordering_count * bridge.KEYMAP_ORDERING_RECORD_BYTES
	if header.stroke_count > 0 {
		state.view.strokes = mem.slice_ptr(
			cast(^bridge.Keymap_Stroke_Record)raw_data(storage[int(offset):]),
			int(header.stroke_count),
		)
	}
	offset += header.stroke_count * bridge.KEYMAP_STROKE_RECORD_BYTES
	state.view.text = storage[int(offset):int(offset + header.text_bytes)]
	failure = bridge.keymap_profile_records_validate(
		state.view.header,
		state.view.profiles,
		state.view.states,
		state.view.maps,
		state.view.bindings,
		state.view.selectors,
		state.view.surfaces,
		state.view.remaps,
		state.view.ordering,
		state.view.strokes,
		state.view.text,
	)
	return failure.code == .None, failure
}

@(private)
keymap_profile_candidate_adapt :: proc(state: ^Keymap_Profile_Candidate_State) -> bool {
	allocator := state.allocator
	allocation_error: base_runtime.Allocator_Error
	state.profiles, allocation_error = make(
		[]interaction.Profile_Definition,
		len(state.view.profiles),
		allocator,
	)
	if allocation_error != nil {
		return false
	}
	state.states, allocation_error = make(
		[]interaction.Interaction_State_Definition,
		len(state.view.states),
		allocator,
	)
	if allocation_error != nil {
		return false
	}
	state.maps, allocation_error = make([]interaction.Map_Definition, len(state.view.maps), allocator)
	if allocation_error != nil {
		return false
	}
	if len(state.view.bindings) > 0 {
		state.bindings, allocation_error = make(
			[]interaction.Layered_Binding_Definition,
			len(state.view.bindings),
			allocator,
		)
		if allocation_error != nil {
			return false
		}
	}
	if len(state.view.selectors) > 0 {
		state.selectors, allocation_error = make(
			[]interaction.Profile_State_Selector,
			len(state.view.selectors),
			allocator,
		)
		if allocation_error != nil {
			return false
		}
	}
	state.surfaces, allocation_error = make(
		[]interaction.Command_Entry_Surface_Definition,
		len(state.view.surfaces),
		allocator,
	)
	if allocation_error != nil {
		return false
	}
	if len(state.view.remaps) > 0 {
		state.remaps, allocation_error = make(
			[]interaction.Command_Remap_Definition,
			len(state.view.remaps),
			allocator,
		)
		if allocation_error != nil {
			return false
		}
	}
	if len(state.view.ordering) > 0 {
		state.ordering, allocation_error = make(
			[]interaction.Ordering_Constraint,
			len(state.view.ordering),
			allocator,
		)
		if allocation_error != nil {
			return false
		}
	}

	for record, index in state.view.selectors {
		state.selectors[index] = interaction.Profile_State_Selector {
			profile_id = interaction.Profile_ID(record.profile_id),
			state_id = interaction.Interaction_State_ID(record.state_id),
		}
	}
	for record, index in state.view.bindings {
		sequence: interaction.Key_Sequence
		sequence.stroke_count = u8(record.stroke_count)
		for stroke_offset in 0 ..< int(record.stroke_count) {
			stroke := state.view.strokes[int(record.first_stroke) + stroke_offset]
			sequence.strokes[stroke_offset] = interaction.Key_Stroke {
				kind = interaction.Logical_Key_Kind(stroke.kind),
				modifiers = transmute(interaction.Modifiers)u8(stroke.modifiers),
				scalar = rune(stroke.scalar),
			}
		}
		state.bindings[index] = interaction.Layered_Binding_Definition {
			sequence = sequence,
			command_name = keymap_profile_text(
				state.view.text,
				record.command_offset,
				record.command_bytes,
			),
			operation = interaction.Binding_Operation(record.operation),
			scope = interaction.Binding_Scope(record.scope),
			selectors = state.selectors[
				int(record.first_selector):int(record.first_selector + record.selector_count)
			],
			provenance = keymap_profile_provenance(
				state.view.text,
				record.provider_offset,
				record.provider_bytes,
				record.source_offset,
				record.source_bytes,
				record.location_offset,
				record.location_bytes,
				),
			protection_reason = keymap_profile_text(
				state.view.text,
				record.protection_reason_offset,
				record.protection_reason_bytes,
			),
		}
	}
	for record, index in state.view.remaps {
		state.remaps[index] = interaction.Command_Remap_Definition {
			from_command_name = keymap_profile_text(
				state.view.text,
				record.from_command_offset,
				record.from_command_bytes,
			),
			to_command_name = keymap_profile_text(
				state.view.text,
				record.to_command_offset,
				record.to_command_bytes,
			),
			provenance = keymap_profile_provenance(
				state.view.text,
				record.provider_offset,
				record.provider_bytes,
				record.source_offset,
				record.source_bytes,
				record.location_offset,
				record.location_bytes,
			),
		}
	}
	for record, index in state.view.ordering {
		state.ordering[index] = interaction.Ordering_Constraint {
			relation = interaction.Ordering_Relation(record.relation),
			other = interaction.Map_ID(record.other_map_id),
		}
	}
	for record, index in state.view.maps {
		state.maps[index] = interaction.Map_Definition {
			identity = interaction.Map_Identity {
				id = interaction.Map_ID(record.map_id),
				revision = interaction.Map_Revision(record.map_revision),
			},
			name = keymap_profile_text(state.view.text, record.name_offset, record.name_bytes),
			owner = interaction.Owner_Handle {
				id = interaction.Owner_ID(record.owner_id),
				generation = interaction.Owner_Generation(record.owner_generation),
			},
			precedence = interaction.Precedence_Class(record.precedence),
			priority = i32(record.priority),
			context_requirement = interaction.Context_Requirement {
				ctx = interaction.Context_Handle {
					id = interaction.Context_ID(record.context_id),
					generation = interaction.Context_Generation(record.context_generation),
				},
				owner = interaction.Owner_Handle {
					id = interaction.Owner_ID(record.context_owner_id),
					generation = interaction.Owner_Generation(record.context_owner_generation),
				},
			},
			bindings = state.bindings[
				int(record.first_binding):int(record.first_binding + record.binding_count)
			],
			remaps = state.remaps[int(record.first_remap):int(record.first_remap + record.remap_count)],
			ordering_constraints = state.ordering[
				int(record.first_ordering):int(record.first_ordering + record.ordering_count)
			],
			unmatched_input_policy = interaction.Unmatched_Input_Policy(record.unmatched_input_policy),
			provenance = keymap_profile_provenance(
				state.view.text,
				record.provider_offset,
				record.provider_bytes,
				record.source_offset,
				record.source_bytes,
				record.location_offset,
				record.location_bytes,
			),
		}
	}
	for record, index in state.view.states {
		state.states[index] = interaction.Interaction_State_Definition {
			identity = interaction.Interaction_State_Identity {
				id = interaction.Interaction_State_ID(record.state_id),
				revision = interaction.Interaction_State_Revision(record.state_revision),
			},
			name = keymap_profile_text(state.view.text, record.name_offset, record.name_bytes),
			admits_text_input = record.admits_text_input == 1,
			admitted_effects = transmute(interaction.Command_Effects)u8(record.admitted_effects),
			provenance = keymap_profile_provenance(
				state.view.text,
				record.provider_offset,
				record.provider_bytes,
				record.source_offset,
				record.source_bytes,
				record.location_offset,
				record.location_bytes,
			),
		}
	}
	for record, index in state.view.surfaces {
		state.surfaces[index] = interaction.Command_Entry_Surface_Definition {
			identity = interaction.Command_Entry_Surface_Identity {
				id = interaction.Command_Entry_Surface_ID(record.surface_id),
				revision = interaction.Command_Entry_Surface_Revision(record.surface_revision),
			},
			name = keymap_profile_text(state.view.text, record.name_offset, record.name_bytes),
			provenance = keymap_profile_provenance(
				state.view.text,
				record.provider_offset,
				record.provider_bytes,
				record.source_offset,
				record.source_bytes,
				record.location_offset,
				record.location_bytes,
			),
		}
	}
	header := state.view.header
	for record, index in state.view.profiles {
		state.profiles[index] = interaction.Profile_Definition {
			identity = interaction.Profile_Identity {
				id = interaction.Profile_ID(record.profile_id),
				revision = interaction.Profile_Revision(record.profile_revision),
			},
			name = keymap_profile_text(state.view.text, record.name_offset, record.name_bytes),
			states = state.states[
				int(record.first_state):int(record.first_state + record.state_count)
			],
			initial_state = interaction.Interaction_State_ID(record.initial_state_id),
			maps = state.maps[int(record.first_map):int(record.first_map + record.map_count)],
			text_fallback_name = keymap_profile_text(
				state.view.text,
				record.text_fallback_offset,
				record.text_fallback_bytes,
			),
		}
		if record.profile_id == header.active_profile_id {
			state.definition = state.profiles[index]
		}
	}
	state.catalog_definition = interaction.Profile_Catalog_Definition {
		generation = interaction.Profile_Catalog_Generation(header.catalog_generation),
		profiles = state.profiles,
		active_profile = interaction.Profile_ID(header.active_profile_id),
		active_state = interaction.Interaction_State_ID(header.active_state_id),
		surfaces = state.surfaces,
	}
	return true
}

@(private)
keymap_profile_candidate_release_adaptation :: proc(state: ^Keymap_Profile_Candidate_State) {
	allocator := state.allocator
	if state.ordering != nil {
		delete(state.ordering, allocator)
	}
	if state.remaps != nil {
		delete(state.remaps, allocator)
	}
	if state.bindings != nil {
		delete(state.bindings, allocator)
	}
	if state.surfaces != nil {
		delete(state.surfaces, allocator)
	}
	if state.selectors != nil {
		delete(state.selectors, allocator)
	}
	if state.maps != nil {
		delete(state.maps, allocator)
	}
	if state.states != nil {
		delete(state.states, allocator)
	}
	if state.profiles != nil {
		delete(state.profiles, allocator)
	}
	state.catalog_definition = {}
	state.definition = {}
	state.profiles = nil
	state.states = nil
	state.maps = nil
	state.bindings = nil
	state.selectors = nil
	state.surfaces = nil
	state.remaps = nil
	state.ordering = nil
}

@(private)
keymap_profile_provenance :: proc(
	text: []byte,
	provider_offset, provider_bytes, source_offset, source_bytes, location_offset, location_bytes: u64,
) -> interaction.Definition_Provenance {
	return interaction.Definition_Provenance {
		provider = keymap_profile_text(text, provider_offset, provider_bytes),
		source = keymap_profile_text(text, source_offset, source_bytes),
		location = keymap_profile_text(text, location_offset, location_bytes),
	}
}

@(private)
keymap_profile_text :: proc(text: []byte, offset, count: u64) -> string {
	return string(text[int(offset):int(offset + count)])
}

@(private)
runtime_call_scalar_scenario :: proc(
	runtime: ^Runtime,
	input: i64,
	scenario: i32,
) -> (result: i64, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if runtime.phase != .Ready {
		set_diagnostic(runtime, "runtime_call_scalar requires the Ready state")
		return 0, false, failure_context(runtime, .Invalid_State)
	}
	if os.get_current_thread_id() != runtime.owner_thread_id {
		return 0, false, failure_context_message(
			runtime,
			.Wrong_Thread,
			"Racket runtime operation used the wrong owner thread",
		)
	}
	if runtime.call_active {
		set_diagnostic(runtime, "reentrant Racket runtime call rejected")
		return 0, false, failure_context(runtime, .Reentrant_Call)
	}

	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_call_scalar(
		scenario,
		input,
		&result,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return 0, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	return result, true, {}
}

@(private)
runtime_command_inspection_request_scenario :: proc(
	runtime: ^Runtime,
	capability, buffer_id, revision: u64,
	scenario: i32,
) -> (request: Inspection_Request, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime command request requires the Ready state") {
		return {}, false, runtime_call_failure(runtime)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_command_request(
		scenario,
		capability,
		buffer_id,
		revision,
		&request.start,
		&request.end,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return {}, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	return request, true, {}
}

@(private)
runtime_command_transform_scenario :: proc(
	runtime: ^Runtime,
	capability, buffer_id, revision: u64,
	request: Inspection_Request,
	input: []byte,
	replacement: []byte,
	scenario: i32,
) -> (result: Replacement_Request, ok: bool, failure: Failure_Context) {
	assert(runtime != nil)
	if !runtime_call_is_allowed(runtime, "runtime command transform requires the Ready state") {
		return {}, false, runtime_call_failure(runtime)
	}
	runtime.call_active = true
	defer runtime.call_active = false
	clear_diagnostic(runtime)
	adapter_result := odra_racket_runtime_command_transform(
		scenario,
		capability,
		buffer_id,
		revision,
		request.start,
		request.end,
		raw_data(input),
		u64(len(input)),
		&result.start,
		&result.end,
		raw_data(replacement),
		u64(len(replacement)),
		&result.replacement_bytes,
		raw_data(runtime.diagnostic[:]),
		DIAGNOSTIC_CAPACITY,
	)
	runtime.diagnostic_length = diagnostic_length(runtime.diagnostic[:])
	if adapter_result != 0 {
		return {}, false, failure_context(runtime, adapter_failure_code(adapter_result))
	}
	return result, true, {}
}

@(private)
runtime_call_is_allowed :: proc(runtime: ^Runtime, invalid_state_diagnostic: string) -> bool {
	if runtime.phase != .Ready {
		set_diagnostic(runtime, invalid_state_diagnostic)
		return false
	}
	if os.get_current_thread_id() != runtime.owner_thread_id {
		return false
	}
	if runtime.call_active {
		set_diagnostic(runtime, "reentrant Racket runtime call rejected")
		return false
	}
	return true
}

@(private)
runtime_call_failure :: proc(runtime: ^Runtime) -> Failure_Context {
	if runtime.phase != .Ready {
		return failure_context(runtime, .Invalid_State)
	}
	if os.get_current_thread_id() != runtime.owner_thread_id {
		return failure_context_message(
			runtime,
			.Wrong_Thread,
			"Racket runtime operation used the wrong owner thread",
		)
	}
	return failure_context(runtime, .Reentrant_Call)
}

@(private)
adapter_failure_code :: proc(result: i32) -> Failure_Code {
	switch result {
	case 1:
		return .Invalid_State
	case 2:
		return .Runtime_Unavailable
	case 3:
		return .Wrong_Result
	case 4:
		return .Racket_Exception
	case 5:
		return .Command_Rejection
	case:
		return .Runtime_Unavailable
	}
}

@(private)
failure_context :: proc(runtime: ^Runtime, code: Failure_Code) -> Failure_Context {
	return Failure_Context {
		code = code,
		phase = runtime.phase,
		diagnostic = runtime_diagnostic(runtime),
	}
}

@(private)
failure_context_message :: proc(
	runtime: ^Runtime,
	code: Failure_Code,
	message: string,
) -> Failure_Context {
	return Failure_Context {
		code = code,
		phase = runtime.phase,
		diagnostic = message,
	}
}
