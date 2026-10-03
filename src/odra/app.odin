// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../indentation"

import "../bridge"
import "../command"
import "../display"
import "../document"
import "../editor"
import "../editor_session"
import "../gutter"
import "../hosting"
import "../history"
import "../interaction"
import "../kill_ring"
import "../language"
import "../language_service"
import "../layout"
import "../package_catalog_interaction"
import "../status_bar"
import "../theme"
import terminal "../terminal"
import "../terminal_session"
import "../ui"
import editor_view "../view"
import "core:os"
import "core:time"

@(private)
ODRA_PREVIEW_BUNDLE :: bool(#config(ODRA_PREVIEW_BUNDLE, false))

@(private)
gutter_semantic_ui_style :: proc(role: gutter.Semantic_Role) -> ui.Style_Role {
	switch role {
	case .Background:          return .Gutter_Background
	case .Separator:           return .Gutter_Separator
	case .Current_Line_Number: return .Gutter_Line_Number_Current
	case .Diagnostic_Error:       return .Diagnostic_Error
	case .Diagnostic_Warning:     return .Diagnostic_Warning
	case .Diagnostic_Information: return .Diagnostic_Information
	case .Diagnostic_Hint:        return .Diagnostic_Hint
	case .Invalid, .Ordinary, .Line_Number, .Continuation, .Clipping,
	     .Stale, .Aggregate, .Unavailable:
		return .Gutter_Line_Number
	}
	return .Gutter_Line_Number
}

@(private)
gutter_view_row_definitions :: proc(
	view: gutter.View,
) -> (rows: [ui.MAX_TEXT_GUTTER_ROWS]ui.Text_Gutter_Row_Definition, count: int) {
	for row in view.rows {
		if count >= ui.MAX_TEXT_GUTTER_ROWS do break
		left := ""
		right := ""
		if row.left_bytes > 0 {
			left = string(view.text[row.left_offset:row.left_offset + u32(row.left_bytes)])
		}
		if row.right_bytes > 0 {
			right = string(view.text[row.right_offset:row.right_offset + u32(row.right_bytes)])
		}
		rows[count] = ui.Text_Gutter_Row_Definition {
			viewport_row = row.viewport_row,
			logical_line = row.logical_line,
			left_text = left,
			right_text = right,
			left_cells = row.left_cells,
			right_cells = row.right_cells,
			left_separator_bytes = row.left_separator_bytes,
			right_separator_bytes = row.right_separator_bytes,
			left_style_role = gutter_semantic_ui_style(row.left_role),
			right_style_role = gutter_semantic_ui_style(row.right_role),
			current = row.current,
		}
		count += 1
	}
	return
}

@(private)
status_segment_ui_style :: proc(role: status_bar.Semantic_Role) -> ui.Style_Role {
	switch role {
	case .Safety:          return .Status_Safety
	case .Buffer_Identity: return .Status_Identity
	case .Position:        return .Status_Position
	case .Alert:           return .Status_Alert
	case .Workspace:       return .Status_Workspace
	case .Project:         return .Status_Project
	case .Editing_Context: return .Status_Editing_Context
	case .Context:         return .Status_Project
	case .Invalid, .Ordinary, .Disabled:
		return .Status_Normal
	}
	return .Status_Normal
}

@(private)
status_view_style_spans :: proc(
	view: status_bar.View,
) -> (spans: [ui.MAX_STATUS_STYLE_SPANS]ui.Status_Style_Span, count: int) {
	for segment in view.segments {
		if count >= ui.MAX_STATUS_STYLE_SPANS do break
		spans[count] = ui.Status_Style_Span {
			start_byte = segment.start_byte,
			end_byte = segment.end_byte,
			style_role = status_segment_ui_style(segment.style_role),
		}
		count += 1
	}
	return
}

@(private)
status_view_segment_definitions :: proc(
	view: status_bar.View,
) -> (segments: [ui.MAX_STATUS_SEGMENTS]ui.Status_Segment_Definition, count: int) {
	for segment in view.segments {
		if count >= ui.MAX_STATUS_SEGMENTS do break
		segments[count] = ui.Status_Segment_Definition {
			identity = u64(segment.id),
			kind = u8(segment.kind),
			start_byte = segment.start_byte,
			end_byte = segment.end_byte,
			start_cell = segment.start_cell,
			end_cell = segment.end_cell,
			compact = segment.compact,
			truncated = segment.truncated,
			inspection_text = segment.inspection_text,
			primary_command = {
				registry_generation = segment.primary_command.registry_generation,
				slot = segment.primary_command.slot,
				entry_generation = segment.primary_command.entry_generation,
			},
			secondary_command = {
				registry_generation = segment.secondary_command.registry_generation,
				slot = segment.secondary_command.slot,
				entry_generation = segment.secondary_command.entry_generation,
			},
		}
		count += 1
	}
	return
}

@(private)
App_Stage :: enum u8 {
	None,
	Argument_Admission,
	Document_Prepare,
	Document_Inspect,
	Buffer_Init,
	History_Init,
	Session_Init,
	Session_Prepare,
	Session_Publish,
	Session_Access,
	Component_Access,
		Kill_Ring_Init,
		Language_Init,
		Completion,
	Document_Commit,
	View_Registry_Init,
	View_Create,
	Racket_Start,
	Configuration_Load,
	Capability_Registry_Init,
	Command_Registry_Init,
	Keymap_Activation,
	Terminal_Acquire,
	Terminal_Workflow,
	Clipboard_Close,
	Renderer_Init,
	View_Snapshot,
	Projection,
	Gutter,
	Status,
	Presentation,
	Input,
	Resize,
	UI,
	Theme_Init,
	Theme_Access,
	Theme_Close,
	Layout,
	Command_Resolution,
	Command_Dispatch,
	Prompt,
	Command_Shutdown,
	History_Close,
	Session_Close,
		Kill_Ring_Close,
		Language_Close,
	Document_Close,
	Terminal_Restore,
}

@(private)
App_Failure :: struct {
	stage:       App_Stage,
	argument_count: u64,
	document:    document.Failure_Context,
	clipboard:   terminal.Clipboard_Failure_Context,
	terminal:    terminal.Failure_Context,
	terminal_workflow_stage: Terminal_Workflow_Stage,
	terminal_session_failure: terminal_session.Failure_Record,
	display:     display.Failure_Context,
	gutter:      gutter.Failure_Context,
	status_bar:  status_bar.Failure_Context,
	editor:      editor.Failure_Context,
	view:        editor_view.Failure_Context,
	bridge:      bridge.Failure_Context,
	hosting:     hosting.Failure_Context,
	history:     history.Failure_Context,
	editor_session: editor_session.Failure_Context,
		kill_ring:   kill_ring.Failure_Context,
	language:    language.Failure,
	language_service: language_service.Failure_Context,
	prompt_failure: interaction.Prompt_Failure,
	candidate:   interaction.Candidate_Failure,
	interaction: interaction.Failure_Context,
	command:     command.Failure_Context,
	ui:          ui.Failure,
	theme:       theme.Failure,
	layout:      layout.Failure_Context,
}

@(private)
App_Runtime :: struct {
	editor_session_owner: editor_session.Session,
	editor_session_handle: editor_session.Session_Handle,
	kill_ring_store: kill_ring.Ring,
	racket_runtime: hosting.Runtime,
	capabilities: bridge.Buffer_Capability_Registry,
	transaction_capabilities: bridge.Transaction_Capability_Registry,
	interaction_generation: interaction.Generation_Activation,
	keymap_candidate: hosting.Keymap_Profile_Candidate,
	command_context: ^Command_Context,
	indentation_registry_owner: ^indentation.Registry,
	terminal_configuration_owner: ^Terminal_Configuration_State,
	gutter_inspection_owner: ^Gutter_Inspection_State,
	syntax_workflow_owner: ^Syntax_Workflow_State,
	language_service_owner: ^Language_Service_Workflow_State,
	completion_owner: ^Completion_Workflow_State,
	terminal_workflow_owner: ^Terminal_Workflow_State,
	recovery_workflow_owner: ^Recovery_Workflow_State,
	terminal_session: terminal.Session,
	clipboard_adapter: terminal.Clipboard_Adapter,
	renderer: terminal.Renderer,
	constraints: display.Viewport_Constraints,
	next_snapshot_id: u64,
	decoder: terminal.Decoder,
	pointer_events: interaction.Pointer_Event_Queue,
	platform_roots: hosting.Platform_Roots,
	session_initialized: bool,
	kill_ring_initialized: bool,
	racket_started: bool,
	capabilities_initialized: bool,
	transaction_capabilities_initialized: bool,
	interaction_generation_initialized: bool,
	keymap_candidate_loaded: bool,
	command_context_initialized: bool,
	gutter_registry_initialized: bool,
	terminal_acquired: bool,
	clipboard_open: bool,
	renderer_initialized: bool,
}

@(private)
run :: proc(arguments: []string) -> App_Failure {
	runtime, open_failure := app_runtime_open(arguments)
	if open_failure.stage != .None do return open_failure
	failure := app_runtime_loop(runtime)
	return app_runtime_close(runtime, failure)
}

@(private)
app_runtime_open :: #force_no_inline proc(arguments: []string) -> (runtime_result: ^App_Runtime, failure: App_Failure) {
	if argument_failure := startup_arguments_validate(arguments); argument_failure.stage != .None {
		return nil, argument_failure
	}
	runtime, runtime_allocation_error := new(App_Runtime, context.allocator)
	if runtime_allocation_error != nil {
		return nil, App_Failure {
			stage = .Session_Init,
			editor_session = {operation = .Initialize, code = .Persistent_Memory_Limit},
		}
	}
	opened := false
	defer if !opened do free(runtime, context.allocator)
	editor_session_handle, session_ok, session_failure := editor_session.session_init(
		&runtime.editor_session_owner,
		editor_session.Session_ID(1),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	if !session_ok {
		return nil, App_Failure{stage = .Session_Init, editor_session = session_failure}
	}
	runtime.session_initialized = true
	runtime.editor_session_handle = editor_session_handle
	startup_directory := len(arguments) == 1 && os.is_directory(arguments[0])
	if len(arguments) == 1 && !startup_directory {
		_, document_opened, open_failure := editor_session.session_open_path(
			&runtime.editor_session_owner,
			editor_session.Open_Path_Request {
				session = editor_session_handle,
				path = arguments[0],
				encoding = .UTF8,
				configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
			},
		)
		if !document_opened {
			editor_session.session_close(&runtime.editor_session_owner)
			runtime.session_initialized = false
			if open_failure.code == .Document_Failure {
				return nil, App_Failure {
					stage = .Document_Prepare,
					document = open_failure.document_failure,
					editor_session = open_failure,
				}
			}
			return nil, App_Failure{stage = .Session_Publish, editor_session = open_failure}
		}
	}
	defer {
		close_failure: App_Failure
		if !opened && runtime.session_initialized {
			close_failure = session_shutdown_close(&runtime.editor_session_owner, editor_session_handle)
		}
		if !opened && close_failure.stage != .None && failure.stage == .None {
			failure = close_failure
		}
	}
	if len(arguments) == 0 {
		target := startup_visible_target()
		_, _, presented, present_failure := editor_session.session_present_ui(
			&runtime.editor_session_owner,
			editor_session_handle,
			target.ui,
		)
		if !presented {
			return nil, App_Failure{stage = .Session_Access, editor_session = present_failure}
		}
	}
	kill_ring_ok, kill_ring_failure := kill_ring.ring_init(
		&runtime.kill_ring_store,
		kill_ring.Ring_ID(1),
		kill_ring.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	if !kill_ring_ok {
		return nil, App_Failure{stage = .Kill_Ring_Init, kill_ring = kill_ring_failure}
	}
	runtime.kill_ring_initialized = true
	defer {
		closed := true
		close_failure: kill_ring.Failure_Context
		if !opened && runtime.kill_ring_initialized {
			closed, close_failure = kill_ring.ring_close(&runtime.kill_ring_store)
		}
		if !opened && !closed && failure.stage == .None {
			failure = App_Failure{stage = .Kill_Ring_Close, kill_ring = close_failure}
		}
	}

	racket_ok: bool
	racket_failure: hosting.Failure_Context
	if ODRA_PREVIEW_BUNDLE {
		racket_ok, racket_failure = hosting.runtime_start_bundled(&runtime.racket_runtime)
	} else {
		racket_ok, racket_failure = hosting.runtime_start(&runtime.racket_runtime)
	}
	if !racket_ok {
		return nil, App_Failure{stage = .Racket_Start, hosting = racket_failure}
	}
	runtime.racket_started = true
	capabilities_ok, capabilities_failure := bridge.buffer_capability_registry_init(
		&runtime.capabilities,
		bridge.Registry_ID(1),
	)
	if !capabilities_ok {
		hosting.runtime_shutdown(&runtime.racket_runtime)
		runtime.racket_started = false
		return nil, App_Failure{stage = .Capability_Registry_Init, bridge = capabilities_failure}
	}
	runtime.capabilities_initialized = true
	transaction_capabilities_ok, transaction_capabilities_failure :=
		bridge.transaction_capability_registry_init(
			&runtime.transaction_capabilities,
			bridge.Registry_ID(2),
		)
	if !transaction_capabilities_ok {
		bridge.buffer_capability_registry_close(&runtime.capabilities)
		runtime.capabilities_initialized = false
		hosting.runtime_shutdown(&runtime.racket_runtime)
		runtime.racket_started = false
		return nil, App_Failure {
			stage = .Capability_Registry_Init,
			bridge = transaction_capabilities_failure,
		}
	}
	runtime.transaction_capabilities_initialized = true
	defer {
		transaction_closed := true
		transaction_close_failure: bridge.Failure_Context
		if !opened && runtime.transaction_capabilities_initialized {
			transaction_closed, transaction_close_failure =
				bridge.transaction_capability_registry_close(&runtime.transaction_capabilities)
		}
		if !opened && !transaction_closed && failure.stage == .None {
			failure = App_Failure {
				stage = .Command_Shutdown,
				bridge = transaction_close_failure,
			}
		}
		shutdown := true
		shutdown_failure: command.Failure_Context
		if !opened && runtime.racket_started && runtime.capabilities_initialized {
			shutdown, shutdown_failure = command.buffer_command_shutdown(
				&runtime.racket_runtime,
				&runtime.capabilities,
			)
		}
		if !opened && !shutdown && failure.stage == .None {
			failure = App_Failure{stage = .Command_Shutdown, command = shutdown_failure}
		}
	}
	platform_roots, platform_roots_ok, platform_roots_failure :=
		hosting.runtime_platform_roots(&runtime.racket_runtime, context.allocator)
	if !platform_roots_ok {
		return nil, App_Failure{stage = .Configuration_Load, hosting = platform_roots_failure}
	}
	defer if !opened do hosting.platform_roots_close(&platform_roots)
	home_directory := platform_roots.home
	projects_directory := platform_roots.legacy_projects
	lifecycle_configuration_root := platform_roots.configuration
	terminal_configuration_owner, terminal_configuration_allocation_error := new(
		Terminal_Configuration_State, context.allocator,
	)
	runtime.terminal_configuration_owner = terminal_configuration_owner
	if terminal_configuration_allocation_error != nil {
		return nil, App_Failure {
			stage = .Session_Init,
			editor_session = {operation = .Initialize, code = .Persistent_Memory_Limit},
		}
	}
	defer if !opened && runtime.terminal_configuration_owner != nil do free(
		runtime.terminal_configuration_owner, context.allocator,
	)
	startup_configuration, startup_configuration_allocation_error := make(
		[]u8,
		hosting.MAX_PERSONAL_CONFIGURATION_STARTUP_BYTES,
		context.allocator,
	)
	if startup_configuration_allocation_error != nil {
		return nil, App_Failure {
			stage = .Session_Init,
			editor_session = {operation = .Initialize, code = .Persistent_Memory_Limit},
		}
	}
	defer if !opened do delete(startup_configuration)
	startup_configuration_length, startup_configuration_loaded, startup_configuration_failure :=
		hosting.runtime_personal_configuration_startup(
			&runtime.racket_runtime,
			lifecycle_configuration_root,
			startup_configuration,
		)
	if !startup_configuration_loaded {
		return nil, App_Failure{stage = .Configuration_Load, hosting = startup_configuration_failure}
	}
	startup_configuration_state, startup_configuration_decoded :=
		app_runtime_decode_startup_configuration(
			runtime,
			startup_configuration[:int(startup_configuration_length)],
		)
	if !startup_configuration_decoded {
		return nil, App_Failure{stage = .Configuration_Load, hosting = {code = .Wrong_Result}}
	}
	registry_generation := interaction.Registry_Generation(
		startup_configuration_state.confirmed_generation,
	)
	if registry_generation == 0 {
		return nil, App_Failure{stage = .Configuration_Load, hosting = {code = .Wrong_Result}}
	}
	command_catalog, command_catalog_ok, command_catalog_failure :=
		hosting.runtime_load_command_catalog(
			&runtime.racket_runtime,
			registry_generation,
			context.allocator,
		)
	if !command_catalog_ok {
		return nil, App_Failure {
			stage = .Command_Registry_Init,
			hosting = command_catalog_failure,
		}
	}
	racket_command_definitions, definitions_ok :=
		hosting.command_catalog_candidate_definitions(&command_catalog)
	if !definitions_ok {
		hosting.command_catalog_candidate_close(&command_catalog)
		return nil, App_Failure{stage = .Command_Registry_Init}
	}
	commands_ok, commands_failure := command.built_in_command_registry_init(
		&runtime.interaction_generation.registry,
		registry_generation,
		context.allocator,
		racket_command_definitions,
	)
	hosting.command_catalog_candidate_close(&command_catalog)
	if !commands_ok {
		return nil, App_Failure{stage = .Command_Registry_Init, interaction = commands_failure}
	}
	active_interaction_context := interaction.Active_Context {
		identity = interaction.Context_Handle {
			id = interaction.Context_ID(1),
			generation = interaction.Context_Generation(1),
		},
	}
	keymap_candidate, keymap_loaded, keymap_load_failure := hosting.runtime_load_keymap_profile(
		&runtime.racket_runtime,
		u64(registry_generation),
		context.allocator,
	)
	runtime.keymap_candidate = keymap_candidate
	if !keymap_loaded {
		_, _ = interaction.command_registry_close(&runtime.interaction_generation.registry)
		return nil, App_Failure{stage = .Keymap_Activation, hosting = keymap_load_failure}
	}
	runtime.keymap_candidate_loaded = true
	defer if !opened && runtime.keymap_candidate_loaded do hosting.keymap_profile_candidate_close(&runtime.keymap_candidate)
	keymap_definition, keymap_adapted :=
		hosting.keymap_profile_candidate_catalog_definition(&runtime.keymap_candidate)
	if !keymap_adapted {
		_, _ = interaction.command_registry_close(&runtime.interaction_generation.registry)
		return nil, App_Failure{stage = .Keymap_Activation}
	}
	pair_ok, pair_failure := interaction.generation_activation_complete(
		&runtime.interaction_generation,
		registry_generation,
		keymap_definition,
		active_interaction_context,
		interaction.Context_ID(2),
		context.allocator,
	)
	if !pair_ok {
		_, _ = interaction.command_registry_close(&runtime.interaction_generation.registry)
		return nil, App_Failure{stage = .Keymap_Activation, interaction = pair_failure}
	}
	runtime.interaction_generation_initialized = true
	racket_activated, racket_activation_failure :=
		hosting.runtime_personal_generation_transition(
			&runtime.racket_runtime,
			1,
			u64(registry_generation),
		)
	if !racket_activated {
		_, _ = interaction.generation_activation_close(&runtime.interaction_generation)
		runtime.interaction_generation_initialized = false
		return nil, App_Failure{stage = .Keymap_Activation, hosting = racket_activation_failure}
	}
	defer {
		closed := true
		close_failure: interaction.Failure_Context
		if !opened && runtime.interaction_generation_initialized {
			closed, close_failure = interaction.generation_activation_close(&runtime.interaction_generation)
		}
		if !opened && !closed && failure.stage == .None {
			failure = App_Failure{stage = .Command_Shutdown, interaction = close_failure}
		}
	}
	keymap, keymap_active := interaction.profile_activation_snapshot(&runtime.interaction_generation.profile)
	if !keymap_active {
		return nil, App_Failure{stage = .Keymap_Activation}
	}
	candidate_history_state_root := platform_roots.state
	command_context_owner, command_context_allocation_error := new(Command_Context, context.allocator)
	runtime.command_context = command_context_owner
	if command_context_allocation_error != nil {
		return nil, App_Failure {
			stage = .Session_Init,
			editor_session = {operation = .Initialize, code = .Persistent_Memory_Limit},
		}
	}
	defer if !opened && runtime.command_context != nil do free(runtime.command_context, context.allocator)
	command_context := runtime.command_context
	indentation_registry_owner, indentation_registry_error := new(
		indentation.Registry,
		context.allocator,
	)
	if indentation_registry_error != nil {
		return nil, App_Failure{stage = .Session_Init}
	}
	runtime.indentation_registry_owner = indentation_registry_owner
	defer if !opened && runtime.indentation_registry_owner != nil {
		free(runtime.indentation_registry_owner, context.allocator)
		runtime.indentation_registry_owner = nil
	}
	command_context^ = Command_Context {
		session_owner = &runtime.editor_session_owner,
		session_handle = editor_session_handle,
		entry_configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		kill_ring = &runtime.kill_ring_store,
		racket_runtime = &runtime.racket_runtime,
		capabilities = &runtime.capabilities,
		transaction_capabilities = &runtime.transaction_capabilities,
		registry = &runtime.interaction_generation.registry,
		registry_generation = registry_generation,
		keymap = keymap,
		profile_activation = &runtime.interaction_generation.profile,
		interaction_generation = &runtime.interaction_generation,
		active_interaction_context = active_interaction_context,
		context_maps = &runtime.interaction_generation.context_maps,
		candidate_ui = {
			next_session_id = 1,
			next_source_generation = 1,
		},
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
		next_transaction_id = 1,
		next_undo_unit_id = 1,
		search = {
			next_query_id = 1,
			next_generation = 1,
			next_group = 1,
		},
		project_workflow = {next_project_id = 1},
		home_directory = home_directory,
		projects_directory = projects_directory,
		lifecycle_configuration_root = lifecycle_configuration_root,
		candidate_history_state_root = candidate_history_state_root,
		project_catalog_root = platform_roots.project_catalog,
		terminal_configuration = runtime.terminal_configuration_owner,
		grouping_started = time.tick_now(),
		grouping_continuity = 1,
		structural_capability_generation = 1,
		clipboard_workflow = {kill_sequence_id = 1},
		indentation_registry = indentation_registry_owner,
	}
	indentation_ready, _ := indentation.registry_init(indentation_registry_owner)
	if !indentation_ready {
		return nil, App_Failure{stage = .Session_Init}
	}
	package_catalog_workflow_owner, package_catalog_workflow_error := new(
		package_catalog_interaction.Workflow,
		context.allocator,
	)
	if package_catalog_workflow_error != nil {
		return nil, App_Failure {
			stage = .Session_Init,
			editor_session = {operation = .Initialize, code = .Persistent_Memory_Limit},
		}
	}
	command_context.package_catalog_interaction_workflow = package_catalog_workflow_owner
	defer if !opened && command_context.package_catalog_interaction_workflow != nil {
		free(command_context.package_catalog_interaction_workflow, context.allocator)
		command_context.package_catalog_interaction_workflow = nil
	}
	package_catalog_runtime_workflow_owner, package_catalog_runtime_workflow_error := new(
		Package_Catalog_Runtime_Workflow_State,
		context.allocator,
	)
	if package_catalog_runtime_workflow_error != nil {
		return nil, App_Failure {
			stage = .Session_Init,
			editor_session = {operation = .Initialize, code = .Persistent_Memory_Limit},
		}
	}
	command_context.package_catalog_runtime_workflow = package_catalog_runtime_workflow_owner
	defer if !opened && command_context.package_catalog_runtime_workflow != nil {
		free(command_context.package_catalog_runtime_workflow, context.allocator)
		command_context.package_catalog_runtime_workflow = nil
	}
	if !command_context_structural_state_init(command_context) {
		return nil, App_Failure{stage = .Session_Init}
	}
	defer if !opened do command_context_structural_state_close(command_context)
	gutter_inspection_owner, gutter_inspection_allocation_error :=
		new(Gutter_Inspection_State, context.allocator)
	runtime.gutter_inspection_owner = gutter_inspection_owner
	if gutter_inspection_allocation_error != nil {
		return nil, App_Failure{stage = .Gutter, gutter = {operation = .Inspect, code = .Allocation}}
	}
	defer if !opened && runtime.gutter_inspection_owner != nil do free(runtime.gutter_inspection_owner, context.allocator)
	command_context.gutter_inspection = runtime.gutter_inspection_owner
	status_registry_ok, status_registry_failure := status_bar.registry_init(
		&command_context.status_bar_registry,
		status_bar.Registry_ID(u64(editor_session_handle.session_id)),
		allocator = context.allocator,
	)
	if !status_registry_ok {
		return nil, App_Failure{stage = .Status, status_bar = {
			operation = .Factory,
			code = .Invalid_Request,
			limit = status_registry_failure.limit,
			actual = status_registry_failure.actual,
		}}
	}
	gutter_registry_ok, gutter_registry_failure := gutter.programmable_registry_init(
		&command_context.gutter_registry,
		context.allocator,
	)
	if !gutter_registry_ok {
		return nil, App_Failure{stage = .Gutter, gutter = gutter_registry_failure}
	}
	runtime.gutter_registry_initialized = true
	_ = product_module_workflow_init(command_context)
	defer {
		closed := true
		close_failure: gutter.Failure_Context
		if !opened && runtime.gutter_registry_initialized {
			closed, close_failure = gutter.programmable_registry_close(
				&command_context.gutter_registry,
			)
		}
		if !opened && !closed && failure.stage == .None {
			failure = App_Failure{stage = .Gutter, gutter = close_failure}
		}
	}
	command_context_apply_startup_configuration(
		command_context,
		startup_configuration_state,
		startup_configuration[:int(startup_configuration_length)],
	)
	command_context_apply_startup_gutter_provider(
		command_context,
		startup_configuration_state,
		startup_configuration[:int(startup_configuration_length)],
	)
	workflow_failure := app_runtime_initialize_workflows(
		runtime,
		command_context,
		startup_configuration_state,
		startup_configuration[:int(startup_configuration_length)],
	)
	if workflow_failure.stage != .None do return nil, workflow_failure
	recovery_owner, recovery_allocation_error := new(Recovery_Workflow_State, context.allocator)
	if recovery_allocation_error != nil {
		return nil, App_Failure {
			stage = .Session_Init,
			editor_session = {operation = .Initialize, code = .Persistent_Memory_Limit},
		}
	}
	runtime.recovery_workflow_owner = recovery_owner
	command_context.recovery_workflow = recovery_owner
	if !recovery_workflow_init(
		recovery_owner,
		command_context,
		platform_roots,
		startup_configuration_state.recovery_policy,
	) {
		return nil, App_Failure{stage = .Session_Init}
	}
	defer if !opened && runtime.recovery_workflow_owner != nil {
		recovery_workflow_close(runtime.recovery_workflow_owner, context.allocator)
		free(runtime.recovery_workflow_owner, context.allocator)
		runtime.recovery_workflow_owner = nil
		command_context.recovery_workflow = nil
	}
	defer if !opened && runtime.syntax_workflow_owner != nil do free(runtime.syntax_workflow_owner, context.allocator)
	defer if !opened && runtime.language_service_owner != nil do free(runtime.language_service_owner, context.allocator)
	defer if !opened && runtime.completion_owner != nil do free(runtime.completion_owner, context.allocator)
	defer if !opened && runtime.terminal_workflow_owner != nil do free(runtime.terminal_workflow_owner, context.allocator)
	defer {
		close_failure: App_Failure
		if !opened && runtime.command_context_initialized {
			close_failure = command_context_close(command_context)
		}
		if !opened && close_failure.stage != .None && failure.stage == .None {
			failure = close_failure
		}
	}
	defer {
		if !opened {
			interface_close_failure := app_runtime_discard_interface(runtime)
			if interface_close_failure.stage == .Terminal_Restore ||
			   (interface_close_failure.stage != .None && failure.stage == .None) {
				failure = interface_close_failure
			}
		}
	}
	interface_failure := app_runtime_initialize_interface(
		runtime,
		command_context,
		arguments,
		startup_directory,
	)
	if interface_failure.stage != .None do return nil, interface_failure
	defer if !opened && !runtime.command_context_initialized do command_context_feedback_close(command_context)
	runtime.platform_roots = platform_roots
	delete(startup_configuration)
	opened = true
	return runtime, {}
}

@(private)
app_runtime_initialize_interface :: #force_no_inline proc(
	runtime: ^App_Runtime,
	commands: ^Command_Context,
	arguments: []string,
	startup_directory: bool,
) -> (failure: App_Failure) {
	if runtime == nil || commands == nil {
		return App_Failure{stage = .Session_Init}
	}
	theme_ok, theme_failure := theme.theme_registry_init_factory(
		&commands.theme_registry,
		theme.Registry_ID(1),
		allocator = context.allocator,
	)
	if !theme_ok do return App_Failure{stage = .Theme_Init, theme = theme_failure}
	presentation_profiles_ok, presentation_profiles_failure :=
		ui.presentation_profile_registry_init(
			&commands.presentation_profiles,
			ui.Presentation_Profile_Registry_ID(1),
			allocator = context.allocator,
		)
	if !presentation_profiles_ok {
		code := ui.Failure_Code.Invalid_Registry
		if presentation_profiles_failure.code == .Allocation do code = .Allocation
		return App_Failure{stage = .UI, ui = {operation = .Initialize, code = code}}
	}
	feedback_scope, feedback_scoped, feedback_scope_failure :=
		ui.presentation_profile_registry_scope(
			&commands.presentation_profiles,
			.Contextual_Information,
		)
	if !feedback_scoped {
		return presentation_profile_app_failure(feedback_scope_failure)
	}
	if !command_context_feedback_init(commands, feedback_scope.selected) {
		return App_Failure{stage = .Presentation}
	}
	feedback_initialized := true
	defer if feedback_initialized && failure.stage != .None do command_context_feedback_close(commands)

	terminal_ok, terminal_failure := terminal.session_acquire(&runtime.terminal_session)
	if !terminal_ok {
		return App_Failure{stage = .Terminal_Acquire, terminal = terminal_failure}
	}
	runtime.terminal_acquired = true
	clipboard_ok, _ := terminal.clipboard_adapter_init(
		&runtime.clipboard_adapter,
		terminal.clipboard_default_config(),
		terminal.clipboard_osc52_transport(
			&runtime.terminal_session,
			terminal.clipboard_environment_detect(),
		),
	)
	runtime.clipboard_open = clipboard_ok
	if clipboard_ok do commands.clipboard_workflow.adapter = &runtime.clipboard_adapter
	geometry, _, geometry_ok, geometry_failure := terminal.session_geometry(&runtime.terminal_session)
	if !geometry_ok do return App_Failure{stage = .Resize, terminal = geometry_failure}
	runtime.constraints = constraints_from_geometry(geometry)
	renderer_ok, renderer_failure := terminal.renderer_init(
		&runtime.renderer,
		terminal.Renderer_Config {
			constraints = runtime.constraints,
			profile = display.terminal_unicode17_profile(),
			color = terminal.renderer_color_capability_detect(),
			icons = terminal.renderer_icon_profile_detect(),
			max_output_bytes = terminal.MAX_OUTPUT_BYTES,
			allocator = context.allocator,
		},
	)
	if !renderer_ok {
		return App_Failure{stage = .Renderer_Init, terminal = renderer_failure}
	}
	runtime.renderer_initialized = true
	runtime.next_snapshot_id = 1
	if startup_directory {
		_, startup_open_failure := command_context_open_project_directory(
			commands,
			arguments[0],
			runtime.constraints,
		)
		if startup_open_failure.stage != .None do return startup_open_failure
	}
	recovery_workflow_startup_context(commands.recovery_workflow, commands, arguments, startup_directory)
	failure = present_current_session(
		&runtime.editor_session_owner,
		runtime.editor_session_handle,
		&runtime.terminal_session,
		&runtime.renderer,
		runtime.constraints,
		&runtime.next_snapshot_id,
		commands,
	)
	if failure.stage == .None do feedback_initialized = false
	return
}

@(private)
app_runtime_discard_interface :: proc(runtime: ^App_Runtime) -> (failure: App_Failure) {
	if runtime == nil do return
	if runtime.renderer_initialized {
		terminal.renderer_close(&runtime.renderer)
		runtime.renderer_initialized = false
	}
	if runtime.clipboard_open {
		closed, close_failure := terminal.clipboard_adapter_close(&runtime.clipboard_adapter)
		if !closed {
			failure = App_Failure{stage = .Clipboard_Close, clipboard = close_failure}
		}
		runtime.clipboard_open = false
	}
	if runtime.terminal_acquired {
		restored, restore_failure := terminal.session_restore(&runtime.terminal_session)
		if !restored {
			failure = App_Failure{stage = .Terminal_Restore, terminal = restore_failure}
		}
		runtime.terminal_acquired = false
	}
	return
}

@(private)
app_runtime_decode_startup_configuration :: #force_no_inline proc(
	runtime: ^App_Runtime,
	input: []u8,
) -> (state: Personal_Configuration_Startup_State, ok: bool) {
	if runtime == nil || runtime.terminal_configuration_owner == nil do return {}, false
	terminal_configuration: Terminal_Configuration_State
	state, terminal_configuration, ok = personal_configuration_startup_decode(input)
	if !ok do return {}, false
	runtime.terminal_configuration_owner^ = terminal_configuration
	return state, true
}

@(private)
app_runtime_initialize_workflows :: #force_no_inline proc(
	runtime: ^App_Runtime,
	commands: ^Command_Context,
	startup_state: Personal_Configuration_Startup_State,
	startup_configuration: []u8,
) -> (failure: App_Failure) {
	if runtime == nil || commands == nil {
		return App_Failure{stage = .Session_Init}
	}
	initialized := false
	defer if !initialized do app_runtime_discard_workflows(runtime, commands)

	syntax_owner, syntax_allocation_error := new(Syntax_Workflow_State, context.allocator)
	runtime.syntax_workflow_owner = syntax_owner
	commands.syntax_workflow = syntax_owner
	if syntax_allocation_error != nil {
		return App_Failure {
			stage = .Language_Init,
			language = {operation = .Initialize, code = .Allocation},
		}
	}
	syntax_ok, syntax_failure := syntax_workflow_init(syntax_owner, context.allocator)
	if !syntax_ok {
		return App_Failure{stage = .Language_Init, language = syntax_failure}
	}

	language_service_owner, language_service_allocation_error := new(
		Language_Service_Workflow_State,
		context.allocator,
	)
	runtime.language_service_owner = language_service_owner
	commands.language_service_workflow = language_service_owner
	if language_service_allocation_error != nil {
		return App_Failure {
			stage = .Language_Init,
			language_service = {code = .Allocation},
		}
	}
	language_service_ok, language_service_failure := language_service_workflow_init(
		language_service_owner,
		context.allocator,
	)
	if !language_service_ok {
		return App_Failure{stage = .Language_Init, language_service = language_service_failure}
	}
	language_support_bytes, language_support_decoded := personal_configuration_language_support(
		startup_state,
		startup_configuration,
	)
	if !language_support_decoded do return App_Failure{stage = .Configuration_Load}
	language_support_candidate, language_support_prepared := language_support_workflow_prepare(
		syntax_owner,
		language_service_owner,
		language_support_bytes,
		startup_state.confirmed_generation,
		context.allocator,
	)
	if !language_support_prepared do return App_Failure{stage = .Language_Init}
	language_support_published := language_support_workflow_publish(
		&language_support_candidate,
		syntax_owner,
		language_service_owner,
	)
	language_support_workflow_candidate_close(
		&language_support_candidate,
		language_service_owner,
	)
	if !language_support_published do return App_Failure{stage = .Language_Init}

	completion_owner, completion_allocation_error := new(
		Completion_Workflow_State,
		context.allocator,
	)
	runtime.completion_owner = completion_owner
	commands.completion_workflow = completion_owner
	if completion_allocation_error != nil do return App_Failure{stage = .Completion}
	if !completion_workflow_init(
		completion_owner,
		commands.completion_configuration,
		context.allocator,
	) {
		return App_Failure{stage = .Completion}
	}

	terminal_workflow_owner, terminal_workflow_allocation_error := new(
		Terminal_Workflow_State,
		context.allocator,
	)
	runtime.terminal_workflow_owner = terminal_workflow_owner
	commands.terminal_workflow = terminal_workflow_owner
	if terminal_workflow_allocation_error != nil {
		return App_Failure{stage = .Terminal_Workflow}
	}
	terminal_workflow_ok, terminal_workflow_failure := terminal_workflow_init(
		terminal_workflow_owner,
		context.allocator,
	)
	if !terminal_workflow_ok do return app_terminal_workflow_failure(terminal_workflow_failure)
	terminal_configuration_applied, terminal_configuration_failure :=
		app_runtime_configure_terminal_workflow(commands)
	if !terminal_configuration_applied {
		return App_Failure {
			stage = .Terminal_Workflow,
			terminal_workflow_stage = .Initialize,
			terminal_session_failure = terminal_configuration_failure,
		}
	}

	runtime.command_context_initialized = true
	initialized = true
	return {}
}

@(private)
app_runtime_discard_workflows :: proc(runtime: ^App_Runtime, commands: ^Command_Context) {
	if runtime == nil || commands == nil do return
	if terminal_workflow_owner := runtime.terminal_workflow_owner; terminal_workflow_owner != nil {
		if terminal_workflow_owner.initialized do _, _ = terminal_workflow_close(terminal_workflow_owner)
		free(terminal_workflow_owner, context.allocator)
		runtime.terminal_workflow_owner = nil
		commands.terminal_workflow = nil
	}
	if completion_owner := runtime.completion_owner; completion_owner != nil {
		if completion_workflow_is_live(completion_owner) do completion_workflow_close(completion_owner)
		free(completion_owner, context.allocator)
		runtime.completion_owner = nil
		commands.completion_workflow = nil
	}
	if language_service_owner := runtime.language_service_owner; language_service_owner != nil {
		if language_service_workflow_is_live(language_service_owner) {
			language_service_workflow_close(language_service_owner)
		}
		free(language_service_owner, context.allocator)
		runtime.language_service_owner = nil
		commands.language_service_workflow = nil
	}
	if syntax_owner := runtime.syntax_workflow_owner; syntax_owner != nil {
		if syntax_workflow_is_live(syntax_owner) do _, _ = syntax_workflow_close(syntax_owner)
		free(syntax_owner, context.allocator)
		runtime.syntax_workflow_owner = nil
		commands.syntax_workflow = nil
	}
}

@(private)
app_runtime_configure_terminal_workflow :: #force_no_inline proc(
	commands: ^Command_Context,
) -> (bool, terminal_session.Failure_Record) {
	assert(
		commands != nil && commands.terminal_workflow != nil &&
			commands.terminal_configuration != nil,
	)
	configured, failure := terminal_session.registry_event_configure(
		&commands.terminal_workflow.registry,
		commands.terminal_configuration.global.limits,
	)
	if !configured do return false, failure
	return terminal_workflow_configure_attention(
		commands.terminal_workflow,
		commands.terminal_configuration.global.attention,
	)
}

@(private)
app_runtime_loop :: #force_no_inline proc(runtime: ^App_Runtime) -> (failure: App_Failure) {
	assert(runtime != nil)
	for {
		wait_milliseconds := u32(50)
		if runtime.pointer_events.count > 0 do wait_milliseconds = 0
		value, result, input_failure := terminal.session_read_byte(
			&runtime.terminal_session,
			wait_milliseconds,
		)
		switch result {
		case .Byte:
			exit, byte_failure := app_runtime_loop_byte(runtime, value)
			if byte_failure.stage != .None do return byte_failure
			if exit do return
		case .Resize:
			if resize_failure := app_runtime_loop_resize(runtime); resize_failure.stage != .None {
				return resize_failure
			}
		case .Idle:
			exit, idle_failure := app_runtime_loop_idle(runtime)
			if idle_failure.stage != .None do return idle_failure
			if exit do return
		case .Failure:
			return App_Failure{stage = .Input, terminal = input_failure}
		}
	}
}

@(private)
app_runtime_loop_byte :: #force_no_inline proc(
	runtime: ^App_Runtime,
	value: u8,
) -> (exit: bool, failure: App_Failure) {
	command_context := runtime.command_context
	pointer_context, _ := terminal.session_pointer_context(
		&runtime.terminal_session,
		interaction.Pointer_Root_Generation(u64(command_context.ui_root.generation)),
	)
	decoded := terminal.decoder_push(&runtime.decoder, value, pointer_context)
	if decoded.status != .Event do return false, {}
	dispatched: Interaction_Result
	dispatch_failure: App_Failure
	if decoded.input.kind == .Pointer {
		queue_result := interaction.pointer_event_queue_push(
			&runtime.pointer_events,
			decoded.input.pointer,
		)
		if queue_result == .Limit {
			dispatched, dispatch_failure = app_runtime_dispatch_pointer_turn(runtime)
			if dispatch_failure.stage == .None {
				queue_result = interaction.pointer_event_queue_push(
					&runtime.pointer_events,
					decoded.input.pointer,
				)
			}
		}
		if queue_result == .Invalid || queue_result == .Limit {
			interaction.pointer_event_queue_clear(&runtime.pointer_events)
			pointer_text_capture_clear(command_context)
			command_context_set_diagnostic(command_context, "Pointer input pressure limit reached")
			dispatched.changed = true
		} else if decoded.input.pointer.action == .Motion {
			if !dispatched.changed &&
			   (queue_result == .Coalesced || runtime.pointer_events.count == 1) {
				return false, {}
			}
			if runtime.pointer_events.count > 1 {
				motion_result, motion_failure := app_runtime_dispatch_pointer_turn(runtime)
				dispatched.changed = dispatched.changed || motion_result.changed
				dispatch_failure = motion_failure
			}
		} else {
			control_result, control_failure := app_runtime_dispatch_pointer_turn(runtime)
			dispatched.changed = dispatched.changed || control_result.changed
			dispatch_failure = control_failure
		}
	} else {
		dispatched, dispatch_failure = app_runtime_dispatch_pointer_turn(runtime)
		if dispatch_failure.stage == .None && runtime.pointer_events.count == 0 {
			pointer_changed := dispatched.changed
			ordinary, ordinary_failure := dispatch_session_input(
				command_context,
				&runtime.editor_session_owner,
				runtime.editor_session_handle,
				decoded.input,
				runtime.constraints,
			)
			dispatched = ordinary
			dispatched.changed = pointer_changed || ordinary.changed
			dispatch_failure = ordinary_failure
		}
	}
	if dispatch_failure.stage != .None do return false, dispatch_failure
	if dispatched.exit do return true, {}
	if dispatched.changed {
		recovery_workflow_step(command_context.recovery_workflow, command_context)
		failure = present_current_session(
			&runtime.editor_session_owner,
			runtime.editor_session_handle,
			&runtime.terminal_session,
			&runtime.renderer,
			runtime.constraints,
			&runtime.next_snapshot_id,
			command_context,
		)
	}
	return false, failure
}

@(private)
app_runtime_loop_resize :: #force_no_inline proc(runtime: ^App_Runtime) -> App_Failure {
	command_context := runtime.command_context
	interaction.pointer_event_queue_clear(&runtime.pointer_events)
	pointer_text_capture_clear(command_context)
	current, _, current_ok, current_failure := terminal.session_geometry(&runtime.terminal_session)
	if !current_ok do return App_Failure{stage = .Resize, terminal = current_failure}
	resized_constraints := constraints_from_geometry(current)
	if resized_constraints == runtime.constraints do return {}
	resized, resize_failure := terminal.renderer_resize(&runtime.renderer, resized_constraints)
	if !resized do return App_Failure{stage = .Resize, terminal = resize_failure}
	runtime.constraints = resized_constraints
	if layout_failure := command_context_layout_resize(
		command_context,
		runtime.constraints,
	); layout_failure.stage != .None {
		return layout_failure
	}
	return present_current_session(
		&runtime.editor_session_owner,
		runtime.editor_session_handle,
		&runtime.terminal_session,
		&runtime.renderer,
		runtime.constraints,
		&runtime.next_snapshot_id,
		command_context,
	)
}

@(private)
app_runtime_loop_idle :: #force_no_inline proc(
	runtime: ^App_Runtime,
) -> (exit: bool, failure: App_Failure) {
	command_context := runtime.command_context
	finished_input := terminal.decoder_finish(&runtime.decoder)
	if finished_input.status == .Event {
		dispatched, dispatch_failure := dispatch_session_input(
			command_context,
			&runtime.editor_session_owner,
			runtime.editor_session_handle,
			finished_input.input,
			runtime.constraints,
		)
		if dispatch_failure.stage != .None do return false, dispatch_failure
		if dispatched.exit do return true, {}
		if dispatched.changed {
			failure = present_current_session(
				&runtime.editor_session_owner,
				runtime.editor_session_handle,
				&runtime.terminal_session,
				&runtime.renderer,
				runtime.constraints,
				&runtime.next_snapshot_id,
				command_context,
			)
		}
		return false, failure
	}
	recovery_workflow_step(command_context.recovery_workflow, command_context)
	pointer_result, pointer_failure := app_runtime_dispatch_pointer_turn(runtime)
	if pointer_failure.stage != .None do return false, pointer_failure
	terminal_changed, terminals_ok, terminal_failure := terminal_workflow_refresh_all(
		command_context.terminal_workflow,
		&runtime.editor_session_owner,
	)
	if !terminals_ok do return false, app_terminal_workflow_failure(terminal_failure)
	terminal_exit_changed, terminal_exit_failure := command_context_reconcile_terminal_exits(
		command_context,
	)
	if terminal_exit_failure.stage != .None do return false, terminal_exit_failure
	terminal_workflow_deliver_events(command_context)
	product_module_changed := product_module_workflow_step(command_context)
	changed := pointer_result.changed || terminal_changed || terminal_exit_changed ||
	           product_module_changed || language_service_workflow_step(
		command_context,
		&runtime.editor_session_owner,
		runtime.editor_session_handle,
	)
	if changed {
		failure = present_current_session(
			&runtime.editor_session_owner,
			runtime.editor_session_handle,
			&runtime.terminal_session,
			&runtime.renderer,
			runtime.constraints,
			&runtime.next_snapshot_id,
			command_context,
		)
	}
	return false, failure
}

@(private)
app_runtime_dispatch_pointer_turn :: #force_no_inline proc(
	runtime: ^App_Runtime,
) -> (result: Interaction_Result, failure: App_Failure) {
	if runtime == nil || runtime.command_context == nil do return {}, App_Failure{stage = .Input}
	motion_count: u8
	for runtime.pointer_events.count > 0 {
		queued, available := interaction.pointer_event_queue_peek(&runtime.pointer_events)
		if !available do return result, App_Failure{stage = .Input}
		if queued.event.action == .Motion &&
		   motion_count >= interaction.MAX_POINTER_MOTION_PER_TURN {
			return result, {}
		}
		_, popped := interaction.pointer_event_queue_pop(&runtime.pointer_events)
		if !popped do return result, App_Failure{stage = .Input}
		dispatched, dispatch_failure := command_context_pointer_focus(
			runtime.command_context,
			&runtime.editor_session_owner,
			runtime.editor_session_handle,
			queued.event,
			queued.coalesced,
		)
		if dispatch_failure.stage != .None do return result, dispatch_failure
		result.changed = result.changed || dispatched.changed
		if queued.event.action == .Motion do motion_count += 1
	}
	return result, {}
}

@(private)
app_runtime_close :: #force_no_inline proc(runtime: ^App_Runtime, initial_failure: App_Failure) -> (failure: App_Failure) {
	if runtime == nil do return initial_failure
	failure = initial_failure
	if failure.stage == .None && runtime.recovery_workflow_owner != nil {
		recovery_workflow_clean_shutdown(runtime.recovery_workflow_owner)
	}
	interface_close_failure := app_runtime_discard_interface(runtime)
	if interface_close_failure.stage == .Terminal_Restore ||
	   (interface_close_failure.stage != .None && failure.stage == .None) {
		failure = interface_close_failure
	}
	if runtime.command_context_initialized {
		close_failure := command_context_close(runtime.command_context)
		if close_failure.stage != .None && failure.stage == .None do failure = close_failure
		runtime.command_context_initialized = false
	}
	if runtime.gutter_registry_initialized {
		closed, close_failure := gutter.programmable_registry_close(
			&runtime.command_context.gutter_registry,
		)
		if !closed && failure.stage == .None {
			failure = App_Failure{stage = .Gutter, gutter = close_failure}
		}
		runtime.gutter_registry_initialized = false
	}
	if runtime.language_service_owner != nil {
		free(runtime.language_service_owner, context.allocator)
		runtime.language_service_owner = nil
	}
	if runtime.completion_owner != nil {
		free(runtime.completion_owner, context.allocator)
		runtime.completion_owner = nil
	}
	if runtime.terminal_workflow_owner != nil {
		free(runtime.terminal_workflow_owner, context.allocator)
		runtime.terminal_workflow_owner = nil
	}
	if runtime.recovery_workflow_owner != nil {
		recovery_workflow_close(runtime.recovery_workflow_owner, context.allocator)
		free(runtime.recovery_workflow_owner, context.allocator)
		runtime.recovery_workflow_owner = nil
		if runtime.command_context != nil do runtime.command_context.recovery_workflow = nil
	}
	if runtime.syntax_workflow_owner != nil {
		free(runtime.syntax_workflow_owner, context.allocator)
		runtime.syntax_workflow_owner = nil
	}
	if runtime.gutter_inspection_owner != nil {
		free(runtime.gutter_inspection_owner, context.allocator)
		runtime.gutter_inspection_owner = nil
	}
	if runtime.command_context != nil {
		free(runtime.command_context, context.allocator)
		runtime.command_context = nil
	}
	if runtime.indentation_registry_owner != nil {
		free(runtime.indentation_registry_owner, context.allocator)
		runtime.indentation_registry_owner = nil
	}
	if runtime.terminal_configuration_owner != nil {
		free(runtime.terminal_configuration_owner, context.allocator)
		runtime.terminal_configuration_owner = nil
	}
	if runtime.interaction_generation_initialized {
		closed, close_failure := interaction.generation_activation_close(&runtime.interaction_generation)
		if !closed && failure.stage == .None {
			failure = App_Failure{stage = .Command_Shutdown, interaction = close_failure}
		}
		runtime.interaction_generation_initialized = false
	}
	if runtime.keymap_candidate_loaded {
		hosting.keymap_profile_candidate_close(&runtime.keymap_candidate)
		runtime.keymap_candidate_loaded = false
	}
	hosting.platform_roots_close(&runtime.platform_roots)
	if runtime.transaction_capabilities_initialized {
		closed, close_failure := bridge.transaction_capability_registry_close(
			&runtime.transaction_capabilities,
		)
		if !closed && failure.stage == .None {
			failure = App_Failure{stage = .Command_Shutdown, bridge = close_failure}
		}
		runtime.transaction_capabilities_initialized = false
	}
	if runtime.racket_started && runtime.capabilities_initialized {
		shutdown, shutdown_failure := command.buffer_command_shutdown(
			&runtime.racket_runtime,
			&runtime.capabilities,
		)
		if !shutdown && failure.stage == .None {
			failure = App_Failure{stage = .Command_Shutdown, command = shutdown_failure}
		}
		runtime.racket_started = false
		runtime.capabilities_initialized = false
	}
	if runtime.kill_ring_initialized {
		closed, close_failure := kill_ring.ring_close(&runtime.kill_ring_store)
		if !closed && failure.stage == .None {
			failure = App_Failure{stage = .Kill_Ring_Close, kill_ring = close_failure}
		}
		runtime.kill_ring_initialized = false
	}
	if runtime.session_initialized {
		close_failure := session_shutdown_close(
			&runtime.editor_session_owner,
			runtime.editor_session_handle,
		)
		if close_failure.stage != .None && failure.stage == .None do failure = close_failure
		runtime.session_initialized = false
	}
	free(runtime, context.allocator)
	return failure
}

@(private)
startup_arguments_validate :: proc(arguments: []string) -> App_Failure {
	if len(arguments) > 1 {
		return App_Failure {
			stage = .Argument_Admission,
			argument_count = u64(len(arguments)),
		}
	}
	return {}
}

@(private)
dispatch_session_deferred_command :: proc(
	commands: ^Command_Context,
	session_owner: ^editor_session.Session,
	session_handle: editor_session.Session_Handle,
	result: Interaction_Result,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if result.deferred_command.registry_generation == 0 do return result, {}
	deferred := result.deferred_command
	deferred_result, failure := dispatch_session_input(
		commands,
		session_owner,
		session_handle,
		{},
		constraints,
		deferred,
	)
	deferred_result.changed = true
	return deferred_result, failure
}

@(private)
dispatch_session_input :: #force_no_inline proc(
	commands: ^Command_Context,
	session_owner: ^editor_session.Session,
	session_handle: editor_session.Session_Handle,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
	direct_command: interaction.Command_Handle = {},
) -> (Interaction_Result, App_Failure) {
	if input.kind == .Pointer {
		return command_context_pointer_focus(
			commands,
			session_owner,
			session_handle,
			input.pointer,
		)
	}
	pointer_text_capture_clear(commands)
	if commands.prompt_workflow.mode != .None &&
	   command_context_input_is_protected_command_entry(input) {
		return command_context_recover_then_present_command_navigation(
			commands,
			session_owner,
			session_handle,
			constraints,
			true,
		)
	}
	if commands.prompt_workflow.mode == .Dir_Abandonment_Choice ||
	   commands.prompt_workflow.mode == .Project_Promote_Name ||
	   commands.prompt_workflow.mode == .Terminal_Rename ||
	   commands.prompt_workflow.mode == .Terminal_Exit_Choice ||
	   commands.prompt_workflow.mode == .Terminal_Kill_Choice ||
	   commands.prompt_workflow.mode == .Named_Location_Name ||
	   commands.prompt_workflow.mode == .Named_Slot_Input ||
	   commands.prompt_workflow.mode == .Named_Slot_Confirmation ||
	   commands.prompt_workflow.mode == .Result_Edit {
		return dispatch_prompt(commands, nil, nil, {}, input, constraints)
	}
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		session_owner,
		session_handle,
	)
	if !visible_ok {
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	if visible.kind == .UI_Root &&
	   command_context_ui_accepts_protected_command_entry(commands, visible, input) {
		return command_context_recover_then_present_command_navigation(
			commands,
			session_owner,
			session_handle,
			constraints,
			false,
		)
	}
	if visible.kind == .UI_Root {
		if visible.ui == startup_visible_target().ui {
			return dispatch_startup_list_input(commands, input, constraints)
		}
		if visible.ui == recovery_visible_target().ui {
			return dispatch_recovery_list_input(commands, input, constraints)
		}
		if visible.ui == buffer_inventory_visible_target().ui {
			return dispatch_buffer_inventory_list_input(commands, input, constraints)
		}
		if visible.ui == project_list_visible_target().ui {
			return dispatch_project_list_input(commands, input, constraints)
		}
		if visible.ui == keymap_inspection_visible_target().ui {
			return dispatch_keymap_inspection_list_input(commands, input, constraints)
		}
		if visible.ui == language_state_visible_target().ui {
			return dispatch_language_state_list_input(commands, input, constraints)
		}
		if visible.ui == language_service_inspection_visible_target().ui {
			return dispatch_language_service_inspection_list_input(commands, input, constraints)
		}
		if visible.ui == structural_state_visible_target().ui {
			return dispatch_structural_state_list_input(commands, input, constraints)
		}
		if visible.ui == theme_inspection_visible_target().ui {
			return dispatch_theme_inspection_list_input(commands, input, constraints)
		}
		if visible.ui == product_module_visible_target().ui {
			result, failure := product_module_workflow_dispatch_input(
				commands,
				input,
				constraints,
				direct_command,
			)
			if failure.stage != .None do return {}, failure
			return dispatch_session_deferred_command(
				commands,
				session_owner,
				session_handle,
				result,
				constraints,
			)
		}
		if visible.ui == candidate_ui_visible_target().ui {
			commands.diagnostic_length = 0
			result, failure := dispatch_candidate_ui_input(commands, input, constraints)
			if failure.stage != .None do return {}, failure
			return dispatch_session_deferred_command(
				commands,
				session_owner,
				session_handle,
				result,
				constraints,
			)
		}
		return {}, App_Failure{stage = .UI}
	}
	if visible.kind != .Primary_View {
		return {}, App_Failure{stage = .Session_Access}
	}
	if commands.context_pending.stroke_count == 0 && commands.pending.stroke_count == 0 {
		command_context_deactivate_context_map(commands, .Completed)
	}
	access, access_ok, access_failure := editor_session.session_active_entry_access(
		session_owner,
		session_handle,
	)
	if !access_ok {
		return {}, App_Failure{stage = .Session_Access, editor_session = access_failure}
	}
	entry, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
	if !borrowed {
		return {}, App_Failure{stage = .Session_Access, editor_session = borrow_failure}
	}
	command_context_bind_entry(commands, access.entry, entry)
	active_view, layout_failure := command_context_layout_active_view(
		commands,
		access.entry,
		entry.primary_view,
	)
	if layout_failure.stage != .None {
		return {}, layout_failure
	}
	result, dispatch_failure := dispatch_input(
		commands,
		entry.buffer,
		entry.view_registry,
		active_view,
		input,
		constraints,
		direct_command,
	)
	if dispatch_failure.stage != .None {
		return {}, dispatch_failure
	}
	if result.active_entry_closed {
	}
	if !result.active_entry_closed && result.changed &&
	   commands.candidate_ui.session.state != nil &&
	   commands.candidate_ui.return_target.kind == .Primary_View &&
	   !command_context_layout_is_live(commands) {
		candidate_layout_failure := command_context_layout_ensure(
			commands,
			entry.view_registry,
			active_view,
			constraints,
		)
		if candidate_layout_failure.stage != .None do return {}, candidate_layout_failure
	}
	if !result.active_entry_closed {
		_, reconciled, reconcile_failure := editor_session.entry_access_reconcile(access)
		if !reconciled {
			return {}, App_Failure{stage = .Session_Access, editor_session = reconcile_failure}
		}
	}
	deferred_result, deferred_failure := dispatch_session_deferred_command(
		commands,
		session_owner,
		session_handle,
		result,
		constraints,
	)
	if deferred_failure.stage != .None do return {}, deferred_failure
	result = deferred_result
	if darek_workflow_follow_active(commands) do result.changed = true
	return result, {}
}

@(private)
command_context_input_is_protected_command_entry :: proc(input: interaction.Input) -> bool {
	return input.kind == .Key && input.stroke.kind == .Unicode_Scalar &&
	       input.stroke.scalar == 'x' && input.stroke.modifiers == {.Meta}
}

@(private)
command_context_ui_accepts_protected_command_entry :: proc(
	commands: ^Command_Context,
	visible: editor_session.Visible_Target,
	input: interaction.Input,
) -> bool {
	if !command_context_input_is_protected_command_entry(input) do return false
	if visible.ui == startup_visible_target().ui ||
	   visible.ui == keymap_inspection_visible_target().ui ||
	   visible.ui == product_module_visible_target().ui {
		return false
	}
	if visible.ui != candidate_ui_visible_target().ui do return true
	view, viewed, _ := interaction.candidate_session_view(&commands.candidate_ui.session)
	return viewed && view.source_kind != .Commands
}

@(private)
command_context_recover_then_present_command_navigation :: proc(
	commands: ^Command_Context,
	session_owner: ^editor_session.Session,
	session_handle: editor_session.Session_Handle,
	constraints: display.Viewport_Constraints,
	prompt_active: bool,
) -> (Interaction_Result, App_Failure) {
	recovered: Interaction_Result
	attempts := 1
	if prompt_active do attempts = 2
	for _ in 0 ..< attempts {
		result, failure := dispatch_session_input(
			commands,
			session_owner,
			session_handle,
			interaction.Input {
				kind = .Key,
				stroke = {
					kind = .Unicode_Scalar,
					scalar = 'g',
					modifiers = {.Control},
				},
			},
			constraints,
		)
		if failure.stage != .None do return {}, failure
		recovered.changed = recovered.changed || result.changed
		if commands.prompt_workflow.mode == .None do break
	}
	if commands.prompt_workflow.mode != .None do return recovered, {}
	current, current_ok, current_failure := editor_session.session_visible_target(
		session_owner,
		session_handle,
	)
	if !current_ok {
		return {}, App_Failure{stage = .Session_Access, editor_session = current_failure}
	}
	if current.kind != .Primary_View do return recovered, {}
	access, access_ok, access_failure := editor_session.session_active_entry_access(
		session_owner,
		session_handle,
	)
	if !access_ok {
		return {}, App_Failure{stage = .Session_Access, editor_session = access_failure}
	}
	entry, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
	if !borrowed {
		return {}, App_Failure{stage = .Session_Access, editor_session = borrow_failure}
	}
	command_context_bind_entry(commands, access.entry, entry)
	result, present_failure := command_context_present_command_navigation(
		commands,
		entry.buffer,
		entry.view_registry,
		entry.primary_view,
		constraints,
	)
	_, reconciled, reconcile_failure := editor_session.entry_access_reconcile(access)
	if !reconciled {
		return {}, App_Failure{stage = .Session_Access, editor_session = reconcile_failure}
	}
	result.changed = result.changed || recovered.changed
	return result, present_failure
}

@(private)
present_current_session :: #force_no_inline proc(
	session_owner: ^editor_session.Session,
	session_handle: editor_session.Session_Handle,
	session: ^terminal.Session,
	renderer: ^terminal.Renderer,
	constraints: display.Viewport_Constraints,
	next_snapshot_id: ^u64,
	commands: ^Command_Context,
) -> (failure: App_Failure) {
	profile, profile_ok := terminal.renderer_ui_profile(renderer)
	if !profile_ok {
		return App_Failure{stage = .Presentation, terminal = {code = .Invalid_Renderer}}
	}
	transition_pending := commands != nil && commands.theme_transition.kind != .None
	if transition_pending {
		validated, validation_failure := command_context_theme_transition_validate(commands, profile)
		if !validated do return validation_failure
	}
	failure = present_current_session_content(
		session_owner,
		session_handle,
		session,
		renderer,
		constraints,
		next_snapshot_id,
		commands,
	)
	if failure.stage != .None {
		if transition_pending {
			command_context_theme_transition_abort(commands)
			_ = present_current_session_content(
				session_owner,
				session_handle,
				session,
				renderer,
				constraints,
				next_snapshot_id,
				commands,
			)
		}
		return
	}
	if commands != nil {
		commands.renderer_profile = profile
	}
	if transition_pending {
		_, committed, commit_failure := command_context_theme_transition_commit(commands)
		if !committed {
			_ = present_current_session_content(
				session_owner,
				session_handle,
				session,
				renderer,
				constraints,
				next_snapshot_id,
				commands,
			)
			return commit_failure
		}
	}
	return {}
}

@(private)
present_current_session_content :: proc(
	session_owner: ^editor_session.Session,
	session_handle: editor_session.Session_Handle,
	session: ^terminal.Session,
	renderer: ^terminal.Renderer,
	constraints: display.Viewport_Constraints,
	next_snapshot_id: ^u64,
	commands: ^Command_Context,
) -> App_Failure {
	if commands != nil && syntax_workflow_is_live(commands.syntax_workflow) {
		_, reconciliation_failure := syntax_workflow_reconcile(
			commands.syntax_workflow,
			session_owner,
			session_handle,
			context.temp_allocator,
		)
		if reconciliation_failure.code != .None {
			return App_Failure{stage = .Session_Access, editor_session = reconciliation_failure}
		}
		_, maintenance_failure := syntax_workflow_maintain(
			commands.syntax_workflow,
			session_owner,
			session_handle,
		)
		if maintenance_failure.code != .None {
			return App_Failure{stage = .Session_Access, editor_session = maintenance_failure}
		}
	}
	if commands != nil {
		_ = language_service_workflow_step(commands, session_owner, session_handle)
	}
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		session_owner,
		session_handle,
	)
	if !visible_ok {
		return App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	if visible.kind == .UI_Root {
		if visible.ui == startup_visible_target().ui {
			return present_startup_ui(commands, session, renderer, constraints)
		}
		if visible.ui == recovery_visible_target().ui {
			return present_recovery_ui(commands, session, renderer, constraints)
		}
		if visible.ui == buffer_inventory_visible_target().ui {
			return present_buffer_inventory_ui(commands, session, renderer, constraints)
		}
		if visible.ui == project_list_visible_target().ui {
			return present_project_list_ui(commands, session, renderer, constraints)
		}
		if visible.ui == keymap_inspection_visible_target().ui {
			return present_keymap_inspection_ui(commands, session, renderer, constraints)
		}
		if visible.ui == language_state_visible_target().ui {
			return present_language_state_ui(commands, session, renderer, constraints)
		}
		if visible.ui == language_service_inspection_visible_target().ui {
			return present_language_service_inspection_ui(commands, session, renderer, constraints)
		}
		if visible.ui == structural_state_visible_target().ui {
			return present_structural_state_ui(commands, session, renderer, constraints)
		}
		if visible.ui == theme_inspection_visible_target().ui {
			return present_theme_inspection_ui(commands, session, renderer, constraints)
		}
		if visible.ui == product_module_visible_target().ui {
			return present_product_module_ui(
				commands,
				session,
				renderer,
				constraints,
			)
		}
		if visible.ui == candidate_ui_visible_target().ui {
			if commands.candidate_ui.return_target.kind == .Primary_View {
				access, access_ok, access_failure := editor_session.session_entry_access(
					session_owner,
					commands.candidate_ui.return_target.entry,
				)
				if !access_ok {
					return App_Failure{stage = .Session_Access, editor_session = access_failure}
				}
				entry, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
				if !borrowed {
					return App_Failure{stage = .Session_Access, editor_session = borrow_failure}
				}
				if command_context_layout_is_live(commands) && commands.layout_entry != access.entry {
					if layout_failure := command_context_layout_replace_active(commands, access.entry);
					   layout_failure.stage != .None {
						return layout_failure
					}
				}
				command_context_bind_entry(commands, access.entry, entry)
				if command_context_layout_is_live(commands) {
					return present_current_layout(
						session_owner,
						session_handle,
						session,
						renderer,
						constraints,
						next_snapshot_id,
						commands,
					)
				}
			}
			return present_candidate_ui(commands, session, renderer, constraints)
		}
		return App_Failure{stage = .UI}
	}
	if visible.kind != .Primary_View {
		return App_Failure{stage = .Session_Access}
	}
	// A redraw must not cancel a partially entered contextual or base prefix.
	if commands.context_pending.stroke_count == 0 && commands.pending.stroke_count == 0 {
		command_context_deactivate_context_map(commands, .Completed)
	}
	access, access_ok, access_failure := editor_session.session_active_entry_access(
		session_owner,
		session_handle,
	)
	if !access_ok {
		return App_Failure{stage = .Session_Access, editor_session = access_failure}
	}
	entry, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
	if !borrowed {
		return App_Failure{stage = .Session_Access, editor_session = borrow_failure}
	}
	if command_context_layout_is_live(commands) && commands.layout_entry != access.entry {
		if layout_failure := command_context_layout_replace_active(
			commands,
			access.entry,
		); layout_failure.stage != .None {
			return layout_failure
		}
	}
	command_context_bind_entry(commands, access.entry, entry)
	if !command_context_layout_is_live(commands) {
		if layout_failure := command_context_layout_ensure(
			commands,
			entry.view_registry,
			entry.primary_view,
			constraints,
		); layout_failure.stage != .None {
			return layout_failure
		}
	}
	return present_current_layout(
		session_owner,
		session_handle,
		session,
		renderer,
		constraints,
		next_snapshot_id,
		commands,
	)
}

@(private)
command_context_bind_entry :: proc(
	commands: ^Command_Context,
	entry_handle: editor_session.Entry_Handle,
	entry: editor_session.Entry_Borrow,
) {
	commands.current_entry = entry_handle
	commands.document_owner = entry.document if entry.has_document else nil
	commands.history_store = entry.history_store
}

@(private)
session_shutdown_close :: proc(
	session: ^editor_session.Session,
	handle: editor_session.Session_Handle,
) -> App_Failure {
	for _ in 0 ..< int(editor_session.MAX_LIVE_BUFFERS) {
		visible, visible_ok, visible_failure := editor_session.session_visible_target(session, handle)
		if !visible_ok {
			return App_Failure{stage = .Session_Close, editor_session = visible_failure}
		}
		if visible.kind == .None {
			closed, close_failure := editor_session.session_close(session)
			if !closed {
				return App_Failure{stage = .Session_Close, editor_session = close_failure}
			}
			return {}
		}
		entry := visible.entry
		close_after_detach := false
		if visible.kind == .UI_Root {
			descriptors, copied, copy_failure := editor_session.session_descriptors(session, handle)
			if !copied {
				return App_Failure{stage = .Session_Close, editor_session = copy_failure}
			}
			if len(descriptors.descriptors) == 0 {
				editor_session.descriptor_batch_close(&descriptors)
				closed, close_failure := editor_session.session_close(session)
				if !closed {
					return App_Failure{stage = .Session_Close, editor_session = close_failure}
				}
				return {}
			}
			close_after_detach = len(descriptors.descriptors) == 1
			entry = descriptors.descriptors[0].graph.entry
			editor_session.descriptor_batch_close(&descriptors)
		} else if visible.kind != .Primary_View {
			return App_Failure {
				stage = .Session_Close,
				editor_session = {code = .Invalid_Visible_Target, operation = .Close},
			}
		}
		detached: editor_session.Detached_Entry
		detachment, detached_ok, detach_failure := editor_session.session_entry_detach(
			session,
			entry,
			&detached,
		)
		if !detached_ok {
			return App_Failure{stage = .Session_Close, editor_session = detach_failure}
		}
		_, cleaned, cleanup_failure := editor_session.detached_entry_cleanup(&detached)
		if !cleaned {
			return App_Failure{stage = .Session_Close, editor_session = cleanup_failure}
		}
		released, release_failure := editor_session.detached_entry_release(&detached)
		if !released {
			return App_Failure{stage = .Session_Close, editor_session = release_failure}
		}
		if close_after_detach || detachment.successor.kind == .None {
			closed, close_failure := editor_session.session_close(session)
			if !closed {
				return App_Failure{stage = .Session_Close, editor_session = close_failure}
			}
			return {}
		}
	}
	return App_Failure {
		stage = .Session_Close,
		editor_session = editor_session.Failure_Context {
			code = .Detach_Limit,
			operation = .Close,
			maximum = u64(editor_session.MAX_LIVE_BUFFERS),
		},
	}
}

@(private)
command_context_ui_registry :: proc(
	commands: ^Command_Context,
) -> (registry: ^ui.Registry, ok: bool, failure: App_Failure) {
	if commands == nil || commands.ui_registry.closed {
		return nil, false, App_Failure{stage = .UI}
	}
	if commands.ui_registry.state == nil {
		initialized, ui_failure := ui.registry_init(&commands.ui_registry, 1)
		if !initialized {
			return nil, false, App_Failure{stage = .UI, ui = ui_failure}
		}
		commands.ui_root = {}
	}
	return &commands.ui_registry, true, {}
}

@(private)
present_current_layout :: proc(
	session_owner: ^editor_session.Session,
	session_handle: editor_session.Session_Handle,
	session: ^terminal.Session,
	renderer: ^terminal.Renderer,
	constraints: display.Viewport_Constraints,
	next_snapshot_id: ^u64,
	commands: ^Command_Context,
) -> App_Failure {
	handle, handle_ok, handle_failure := layout.registry_handle(&commands.layout_registry)
	if !handle_ok {
		return App_Failure{stage = .Layout, layout = handle_failure}
	}
	layout_snapshot, layout_ok, layout_failure := layout.registry_snapshot(
		&commands.layout_registry,
		handle,
	)
	if !layout_ok {
		return App_Failure{stage = .Layout, layout = layout_failure}
	}
	visible_target, visible_target_ok, visible_target_failure := editor_session.session_visible_target(
		session_owner,
		session_handle,
	)
	if !visible_target_ok {
		return App_Failure{stage = .Session_Access, editor_session = visible_target_failure}
	}
	candidate_composition := visible_target == candidate_ui_visible_target() &&
		commands.candidate_ui.session.state != nil &&
		commands.candidate_ui.return_target.kind == .Primary_View
	content_rows: u32
	candidate_rows: u32
	rows_ok := false
	if candidate_composition {
		content_rows, candidate_rows, rows_ok = candidate_ui_editor_rows(
			commands,
			constraints,
			layout_snapshot.pane_count,
		)
	} else {
		content_rows, rows_ok = transient_input_content_rows(commands, constraints)
	}
	if !rows_ok {
		return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Invalid_Layout}}
	}
	layout_constraints := constraints
	layout_constraints.height_rows = content_rows
	desired_geometry := command_context_layout_geometry(commands, layout_constraints)
	if layout_snapshot.geometry_request != desired_geometry {
		if resize_failure := command_context_layout_resize(commands, layout_constraints);
		   resize_failure.stage != .None {
			return resize_failure
		}
		handle, handle_ok, handle_failure = layout.registry_handle(&commands.layout_registry)
		if !handle_ok do return App_Failure{stage = .Layout, layout = handle_failure}
		layout_snapshot, layout_ok, layout_failure = layout.registry_snapshot(
			&commands.layout_registry,
			handle,
		)
		if !layout_ok do return App_Failure{stage = .Layout, layout = layout_failure}
	}
	darek_workflow_shift_layout_snapshot(commands, &layout_snapshot)
	if layout_snapshot.geometry_state == .Insufficient {
		message := "Terminal geometry is insufficient. Resize, use C-x 0 or C-x 1, or exit."
		if commands.diagnostic_length > 0 {
			message = string(commands.diagnostic[:commands.diagnostic_length])
		}
		presented, presentation_failure := terminal.renderer_present_recovery(
			renderer,
			session,
			message,
		)
		if !presented {
			return App_Failure{stage = .Presentation, terminal = presentation_failure}
		}
		return {}
	}
	if layout_snapshot.geometry_state != .Operating && layout_snapshot.geometry_state != .Semantic {
		return App_Failure{stage = .Layout}
	}
	descriptors, descriptors_ok, descriptors_failure := editor_session.session_descriptors(
		session_owner,
		session_handle,
		context.temp_allocator,
	)
	if !descriptors_ok {
		return App_Failure{stage = .Session_Access, editor_session = descriptors_failure}
	}
	defer editor_session.descriptor_batch_close(&descriptors)
	if len(descriptors.descriptors) == 0 {
		return App_Failure{stage = .Session_Access}
	}
	ui_registry, ui_registry_ok, ui_registry_failure := command_context_ui_registry(commands)
	if !ui_registry_ok {
		return ui_registry_failure
	}
	ui_profile, ui_profile_ok := terminal.renderer_ui_profile(renderer)
	if !ui_profile_ok {
		return App_Failure{stage = .Presentation, terminal = {code = .Invalid_Renderer}}
	}
	proposal, proposal_ok, proposal_failure := ui.proposal_begin(ui_registry, commands.ui_root)
	if !proposal_ok {
		return App_Failure{stage = .UI, ui = proposal_failure}
	}
	defer if proposal.state != nil do ui.proposal_abort(&proposal)
	styles_ok, styles_failure := proposal_resolve_session_theme(&proposal, commands)
	if !styles_ok do return styles_failure
	bindings: [layout.MAX_LIVE_PANES]ui.Pane_Text_View_Binding
	pane_handles: [layout.MAX_LIVE_PANES]layout.Pane_Handle
	gutter_views: [layout.MAX_LIVE_PANES]gutter.View
	status_views: [layout.MAX_LIVE_PANES]status_bar.View
	status_session_context, status_session_ok := status_bar_session_context_prepare(
		session_owner,
		session_handle,
	)
	if !status_session_ok {
		return App_Failure{stage = .Status, status_bar = {operation = .Factory, code = .Invalid_Request}}
	}
	defer status_bar_session_context_close(&status_session_context)
	projections: [layout.MAX_LIVE_PANES]terminal.Text_Surface_Projection
	projection_for_pane: [layout.MAX_LIVE_PANES]int
	pane_has_text_projection: [layout.MAX_LIVE_PANES]bool
	display_snapshots: [layout.MAX_LIVE_PANES]display.Snapshot
	pane_count: int
	text_projection_count: int
	defer {
		for index in 0 ..< pane_count {
			gutter.view_close(&gutter_views[index])
			status_bar.view_close(&status_views[index])
			display.snapshot_close(&display_snapshots[index])
		}
	}
	active_view: editor_view.View_Handle
	active_registry: ^editor_view.Registry
	active_pane_index := -1
	active_projection_index := -1
	gutter_inspection_begin_frame(commands.gutter_inspection, candidate_composition)
	programmable_gutter, programmable_gutter_present, programmable_gutter_failure :=
		gutter.programmable_registry_turn_begin(&commands.gutter_registry)
	if !programmable_gutter_present && programmable_gutter_failure.code != .Invalid_Generation &&
	   programmable_gutter_failure.code != .Provider_Suspended {
		return App_Failure{stage = .Gutter, gutter = programmable_gutter_failure}
	}
	defer if programmable_gutter_present {
		ended, _ := gutter.programmable_registry_turn_end(&commands.gutter_registry)
		assert(ended, "programmable Gutter render turn failed to drain")
	}
	for node_index in 0 ..< int(layout_snapshot.node_count) {
		node := layout_snapshot.nodes[node_index]
		if node.kind != .Pane {
			continue
		}
		access, access_ok, access_failure := editor_session.session_entry_access(
			session_owner,
			node.entry,
		)
		if !access_ok {
			return App_Failure{stage = .Session_Access, editor_session = access_failure}
		}
		entry, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
		if !borrowed {
			return App_Failure{stage = .Session_Access, editor_session = borrow_failure}
		}
		descriptor: editor_session.Entry_Descriptor
		descriptor_found := false
		for candidate in descriptors.descriptors {
			if candidate.graph.entry == node.entry {
				descriptor = candidate
				descriptor_found = true
				break
			}
		}
		if !descriptor_found || descriptor.graph.buffer_id != node.buffer_id {
			return App_Failure{stage = .Session_Access}
		}
		if descriptor.kind == .Terminal {
			terminal_ref := terminal_session_ref(descriptor.terminal.ref)
			columns := u16(node.geometry.content.width)
			rows := u16(node.geometry.content.height)
			_, resized, resize_failure := terminal_workflow_resize(
				commands.terminal_workflow,
				terminal_ref,
				columns,
				rows,
			)
			if !resized do return app_terminal_workflow_failure(resize_failure)
			terminal_view, projected, terminal_failure := terminal_workflow_project_ui(
				commands.terminal_workflow,
				&proposal,
				terminal_ref,
				ui.Owner_ID(layout_snapshot.handle.owner_id),
				descriptor.selection_label,
			)
			if !projected do return app_terminal_workflow_failure(terminal_failure)
			bindings[pane_count] = ui.Pane_Text_View_Binding {
				pane = node.pane,
				view = terminal_view,
			}
			pane_handles[pane_count] = node.pane
			pane_count += 1
			if node.active {
				active_view = node.view
				active_registry = entry.view_registry
				active_pane_index = pane_count - 1
			}
			continue
		}
		logical, logical_ok, logical_failure := editor_view.snapshot(entry.view_registry, node.view)
		if !logical_ok {
			return App_Failure{stage = .View_Snapshot, view = logical_failure}
		}
		search_snapshot, search_ok, search_failure := editor_view.search_session_view(
			entry.view_registry,
			node.view,
		)
		if !search_ok {
			return App_Failure{stage = .View_Snapshot, view = search_failure}
		}
		query_replacement, query_ok, query_failure :=
			editor_view.query_replacement_session_view(entry.view_registry, node.view)
		if !query_ok {
			return App_Failure{stage = .View_Snapshot, view = query_failure}
		}
		projected_search := projected_search_snapshot(search_snapshot, query_replacement)
		ui_view, ui_view_ok, ui_view_failure := ui.proposal_project_editor_text_view(
			&proposal,
			entry.view_registry,
			node.view,
			entry.buffer,
			ui.Owner_ID(layout_snapshot.handle.owner_id),
			false,
			&projected_search,
			command_context_text_cursor_shape(commands),
		)
		if !ui_view_ok {
			return App_Failure{stage = .UI, ui = ui_view_failure}
		}
		stats, stats_ok, stats_failure := editor.buffer_stats(entry.buffer)
		if !stats_ok {
			return App_Failure{stage = .Gutter, editor = stats_failure}
		}
		line, line_ok, line_failure := editor.buffer_line_at_position(
			entry.buffer,
			logical.point_position,
		)
		if !line_ok {
			return App_Failure{stage = .Gutter, editor = line_failure}
		}
		gutter_policy := commands.gutter_policy
		if logical.gutter.overrides_default do gutter_policy = logical.gutter.policy
		diagnostic_generation, diagnostics_present :=
			language_service_workflow_gutter_diagnostics(
				commands.language_service_workflow,
				entry.buffer,
				commands.registry,
			)
		defer if diagnostic_generation.allocator.procedure != nil {
			gutter.marker_generation_close(&diagnostic_generation)
		}
		marker_cells_reserved: u32
		marker_cells_admitted := false
		gutter_available_cells := u32(node.geometry.content.width)
		gutter_request := gutter.Factory_Request {
			generation = gutter.Generation(next_snapshot_id^),
			available_cells = gutter_available_cells,
			minimum_text_cells = gutter.MIN_TEXT_CELLS,
			line_count = stats.line_feed_count + 1,
			viewport_rows = u32(node.geometry.content.height),
			cursor_logical_line = line.line_index,
			policy = gutter_policy,
			allocator = context.allocator,
			limits = gutter.DEFAULT_LIMITS,
		}
		gutter_geometry, gutter_geometry_ok, gutter_geometry_failure :=
			gutter.factory_geometry(gutter_request)
		if !gutter_geometry_ok {
			return App_Failure{stage = .Gutter, gutter = gutter_geometry_failure}
		}
		pane_constraints := display.Viewport_Constraints {
			width_cells = gutter_geometry.text_cells,
			height_rows = u32(node.geometry.content.height),
		}
		status_generation := status_bar.Generation(next_snapshot_id^)
		display_snapshot, projected, projection_failure := display.project_view(
			entry.buffer,
			entry.view_registry,
			node.view,
			display.Projection_Request {
				snapshot_id = display.Snapshot_ID(next_snapshot_id^),
				search = projected_search,
				view = logical,
				constraints = pane_constraints,
				profile = display.terminal_unicode17_profile(),
				limits = display.DEFAULT_RESOURCE_LIMITS,
				allocators = display.Allocator_Set {
					persistent = context.allocator,
					temporary = context.temp_allocator,
				},
			},
		)
		if !projected {
			return App_Failure{stage = .Projection, display = projection_failure}
		}
		display_snapshots[pane_count] = display_snapshot
		next_snapshot_id^ += 1
		display_view, display_view_ok, display_view_failure := display.snapshot_view(display_snapshot)
		if !display_view_ok {
			return App_Failure{stage = .Projection, display = display_view_failure}
		}
		semantic_content_present := display_view_has_gutter_indicators(display_view) ||
			(diagnostics_present && gutter_diagnostics_intersect_display(&diagnostic_generation, display_view))
		programmable_content_present := programmable_gutter_present &&
			gutter_programmable_intersects_display(programmable_gutter, display_view)
		if semantic_content_present do marker_cells_reserved += 2
		if programmable_content_present {
			marker_cells_reserved += gutter_programmable_reserved_cells(
				programmable_gutter,
				display_view,
			)
		}
		if marker_cells_reserved > 0 &&
		   u32(node.geometry.content.width) >= gutter.MIN_TEXT_CELLS + marker_cells_reserved {
			display.snapshot_close(&display_snapshot)
			display_snapshots[pane_count] = {}
			gutter_request.available_cells -= marker_cells_reserved
			marker_cells_admitted = true
			gutter_geometry, gutter_geometry_ok, gutter_geometry_failure =
				gutter.factory_geometry(gutter_request)
			if !gutter_geometry_ok {
				return App_Failure{stage = .Gutter, gutter = gutter_geometry_failure}
			}
			pane_constraints.width_cells = gutter_geometry.text_cells
			display_snapshot, projected, projection_failure = display.project_view(
				entry.buffer,
				entry.view_registry,
				node.view,
				display.Projection_Request {
					snapshot_id = display.Snapshot_ID(next_snapshot_id^),
					search = projected_search,
					view = logical,
					constraints = pane_constraints,
					profile = display.terminal_unicode17_profile(),
					limits = display.DEFAULT_RESOURCE_LIMITS,
					allocators = display.Allocator_Set {
						persistent = context.allocator,
						temporary = context.temp_allocator,
					},
				},
			)
			if !projected {
				return App_Failure{stage = .Projection, display = projection_failure}
			}
			display_snapshots[pane_count] = display_snapshot
			next_snapshot_id^ += 1
			display_view, display_view_ok, display_view_failure =
				display.snapshot_view(display_snapshot)
			if !display_view_ok {
				return App_Failure{stage = .Projection, display = display_view_failure}
			}
		}
		viewport_generation, viewport_indicators_present :=
			display_view_gutter_indicators(display_view)
		defer if viewport_generation.allocator.procedure != nil {
			gutter.marker_generation_close(&viewport_generation)
		}
		gutter_rows: [gutter.MAX_VISIBLE_ROWS]gutter.Visible_Row
		gutter_row_count: int
		for row in display_view.rows {
			if gutter_row_count >= len(gutter_rows) {
				return App_Failure{stage = .Gutter, gutter = {
					operation = .Factory,
					code = .Row_Limit,
					limit = gutter.MAX_VISIBLE_ROWS,
					actual = u64(len(display_view.rows)),
				}}
			}
			gutter_rows[gutter_row_count] = gutter.Visible_Row {
				viewport_row = u32(row.viewport_row),
				logical_line = u64(row.logical_line),
				has_content = row.has_content,
			}
			gutter_row_count += 1
		}
		gutter_request.rows = gutter_rows[:gutter_row_count]
		gutter_request.cursor_visible = display_view.cursor.visible
		gutter_request.cursor_viewport_row = u32(display_view.cursor.viewport_row)
		gutter_view, gutter_ok, gutter_failure := gutter.compose_factory(gutter_request)
		if !gutter_ok {
			return App_Failure{stage = .Gutter, gutter = gutter_failure}
		}
		defer if gutter_view.allocator.procedure != nil do gutter.view_close(&gutter_view)
		diagnostics_visible := diagnostics_present &&
			gutter_diagnostics_intersect_display(&diagnostic_generation, display_view)
		programmable_visible := programmable_gutter_present &&
			gutter_programmable_intersects_display(programmable_gutter, display_view)
		if diagnostics_visible || viewport_indicators_present || programmable_visible {
			publications: [3]gutter.Marker_Generation_View
			publication_count := 0
			if diagnostics_visible {
				publication, publication_ok, publication_failure :=
					gutter.marker_generation_view(&diagnostic_generation)
				if !publication_ok {
					return App_Failure{stage = .Gutter, gutter = publication_failure}
				}
				publications[publication_count] = publication
				publication_count += 1
			}
			if viewport_indicators_present {
				publication, publication_ok, publication_failure :=
					gutter.marker_generation_view(&viewport_generation)
				if !publication_ok {
					return App_Failure{stage = .Gutter, gutter = publication_failure}
				}
				publications[publication_count] = publication
				publication_count += 1
			}
			if programmable_visible {
				publications[publication_count] = programmable_gutter.publication
				publication_count += 1
			}
			semantic_lane := gutter.factory_semantic_lane(gutter_policy.side)
			lanes: [2]gutter.Lane_Definition
			lane_count := 0
			if diagnostics_visible || viewport_indicators_present {
				lanes[lane_count] = semantic_lane
				lane_count += 1
			}
			if programmable_visible {
				for lane in programmable_gutter.lanes {
					lanes[lane_count] = lane
					lane_count += 1
				}
			}
			resolved_markers, markers_ok, markers_failure := gutter.compose_markers(
				gutter.Marker_Composition_Request {
					generation = gutter_request.generation,
					lanes = lanes[:lane_count],
					publications = publications[:publication_count],
					rows = gutter_request.rows,
					buffer_revision = u64(stats.revision),
					view_identity = u64(logical.view_id),
					view_generation = logical.view_generation,
					projection_generation = u64(display_view.key.snapshot_id),
					allocator = context.allocator,
					limits = gutter.DEFAULT_LIMITS,
				},
			)
			if !markers_ok {
				return App_Failure{stage = .Gutter, gutter = markers_failure}
			}
			defer if resolved_markers.allocator.procedure != nil {
				gutter.resolved_marker_view_close(&resolved_markers)
			}
			if node.active && !candidate_composition {
				gutter_inspection_observe(
					commands.gutter_inspection,
					&resolved_markers,
					publications[:publication_count],
					u64(stats.revision),
					u64(logical.view_id),
					logical.view_generation,
					u64(display_view.key.snapshot_id),
					line.line_index,
					u64(logical.point_position.byte_offset),
				)
			}
			if marker_cells_admitted && (diagnostics_visible || viewport_indicators_present) {
				semantic_ok, semantic_failure := gutter.view_add_semantic_lane(
					&gutter_view,
					semantic_lane,
					&resolved_markers,
					gutter_request.rows,
					true,
				)
				if !semantic_ok {
					return App_Failure{stage = .Gutter, gutter = semantic_failure}
				}
			}
			if marker_cells_admitted && programmable_visible {
				for lane in programmable_gutter.lanes {
					lane_ok, lane_failure := gutter.view_add_marker_lane(
						&gutter_view,
						lane,
						&resolved_markers,
						gutter_request.rows,
						true,
					)
					if !lane_ok {
						return App_Failure{stage = .Gutter, gutter = lane_failure}
					}
				}
			}
		}
		gutter_ui_rows, gutter_ui_row_count := gutter_view_row_definitions(gutter_view)
		if gutter_ui_row_count > 0 {
			gutter_projected, gutter_projection_failure := ui.proposal_project_text_gutter(
				&proposal,
				ui_view,
				u64(gutter_view.generation),
				gutter_view.geometry.left_cells,
				gutter_view.geometry.right_cells,
				gutter_view.geometry.text_cells,
				gutter_ui_rows[:gutter_ui_row_count],
			)
			if !gutter_projected {
				return App_Failure{stage = .UI, ui = gutter_projection_failure}
			}
		}
		syntax_workflow_project_visible(
			commands.syntax_workflow,
			entry.buffer,
			display_snapshot,
			&proposal,
			ui_view,
			ui.Owner_ID(layout_snapshot.handle.owner_id),
		)
		language_service_observation := language_service_workflow_project_visible(
				commands.language_service_workflow,
				entry.buffer,
				&proposal,
				ui_view,
				ui.Owner_ID(layout_snapshot.handle.owner_id),
			)
		bindings[pane_count] = ui.Pane_Text_View_Binding {
			pane = node.pane,
			view = ui_view,
		}
		pane_handles[pane_count] = node.pane
		column, column_ok, column_failure := display.position_display_column(
			entry.buffer,
			logical.point_position,
			display.terminal_unicode17_profile(),
			logical.tab_width,
		)
		if !column_ok {
			return App_Failure{stage = .Status, display = column_failure}
		}
		status_label, status_context_label := status_bar_buffer_labels(
			descriptor,
			&status_session_context,
		)
		status_context, context_ok := status_bar_observe_pane_context(
			commands,
			&status_session_context,
			entry,
			descriptor,
			node,
			stats,
			status_generation,
			language_service_observation,
		)
		if !context_ok {
			return App_Failure{stage = .Status, status_bar = {operation = .Factory, code = .Invalid_Request}}
		}
		programmable_segments, programmable_count, programmable_ok :=
			status_bar_programmable_definitions(commands)
		if !programmable_ok {
			return App_Failure{stage = .Status, status_bar = {
				operation = .Factory,
				code = .Invalid_Request,
			}}
		}
		status_view, status_ok, status_failure := status_bar.compose_factory(status_bar.Factory_Request {
			generation = status_generation,
			width_cells = u32(node.geometry.status.width),
			buffer = status_bar.Buffer_Observation {
				generation = status_generation,
				identity = u64(stats.buffer_id),
				revision = u64(stats.revision),
				label = status_label,
				context_label = status_context_label,
				writable = true,
				modified = descriptor.modified,
				point_offset = u64(logical.point_position.byte_offset),
				text_bytes = stats.text_bytes,
				line = line.line_index + 1,
				line_count = stats.line_feed_count + 1,
				column = column + 1,
			},
			contextual = status_context,
			programmable = programmable_segments[:programmable_count],
			policy = commands.status_bar_policy,
			actions = status_bar_factory_actions(commands, status_context),
			profile = display.unicode17_profile(),
			allocator = context.allocator,
			limits = status_bar.DEFAULT_LIMITS,
		})
		if !status_ok {
			return App_Failure{stage = .Status, status_bar = status_failure}
		}
		status_views[pane_count] = status_view
		gutter_views[pane_count] = gutter_view
		gutter_view = {}
		projections[text_projection_count] = terminal.Text_Surface_Projection {
			snapshot = display_snapshot,
			logical = logical,
		}
		projection_for_pane[pane_count] = text_projection_count
		pane_has_text_projection[pane_count] = true
		text_projection_count += 1
		pane_count += 1
		if node.active {
			active_view = node.view
			active_registry = entry.view_registry
			active_pane_index = pane_count - 1
			active_projection_index = text_projection_count - 1
		}
	}
	if pane_count != int(layout_snapshot.pane_count) ||
	   active_view.view_id == editor_view.View_ID(0) || active_registry == nil {
		return App_Failure{stage = .Layout}
	}
	layout_projection, mapped, map_failure := ui.proposal_map_pane_layout(
		&proposal,
		layout_snapshot,
		bindings[:pane_count],
		ui_profile.id,
	)
	if !mapped {
		return App_Failure{stage = .UI, ui = map_failure}
	}
	base_root := layout_projection.root_node
	base_focus := layout_projection.focus_surface
	if darek_composition, darek_composed, darek_failure := proposal_compose_darek_panel(
		&proposal,
		commands,
		base_root,
		base_focus,
		layout_constraints,
		ui_profile.id,
	); !darek_composed {
		return App_Failure{stage = .UI, ui = darek_failure}
	} else if darek_composition.present {
		base_root = darek_composition.root_node
		base_focus = darek_composition.focus_surface
	}
	for index in 0 ..< pane_count {
		surface, surface_ok, surface_failure := ui.proposal_pane_surface(
			&proposal, pane_handles[index],
		)
		if !surface_ok {
			return App_Failure{stage = .UI, ui = surface_failure}
		}
		if !pane_has_text_projection[index] do continue
		projection_index := projection_for_pane[index]
		projections[projection_index].surface = surface
		status_spans, status_span_count := status_view_style_spans(status_views[index])
		status_segments, status_segment_count := status_view_segment_definitions(status_views[index])
		_, status_ok, status_failure := ui.proposal_project_pane_status(
			&proposal,
			surface,
			string(status_views[index].text),
			status_spans[:status_span_count],
			u64(status_views[index].generation),
			status_segments[:status_segment_count],
		)
		if !status_ok {
			return App_Failure{stage = .UI, ui = status_failure}
		}
	}
	completion_popup: Completion_Popup_Composition
	completion_popup_requested := !candidate_composition &&
		!prompt_mode_projects_input(commands.prompt_workflow.mode) &&
		active_projection_index >= 0 && completion_workflow_has_interaction(commands.completion_workflow)
	if completion_popup_requested {
		interactive_profile, interactive_ok, interactive_failure :=
			command_context_interactive_candidate_presentation_profile(commands)
		if !interactive_ok do return interactive_failure
		contextual_profile, contextual_ok, contextual_failure :=
			command_context_contextual_presentation_profile(commands)
		if !contextual_ok do return contextual_failure
		display_view, display_ok, display_failure := display.snapshot_view(
			projections[active_projection_index].snapshot,
		)
		if !display_ok {
			return App_Failure{stage = .Projection, display = display_failure}
		}
		popup, popup_ok, popup_failure := proposal_compose_completion_popup(
			&proposal,
			commands.completion_workflow,
			projections[active_projection_index].surface,
			projections[active_projection_index].logical.state_generation,
			display_view,
			gutter_views[active_pane_index],
			interactive_profile,
			contextual_profile,
			ui_profile,
		)
		if !popup_ok do return App_Failure{stage = .UI, ui = popup_failure}
		completion_popup = popup
	}
	gutter_popup: Gutter_Popup_Composition
	if !completion_popup_requested && !candidate_composition &&
	   !prompt_mode_projects_input(commands.prompt_workflow.mode) && active_projection_index >= 0 {
		presentation_profile: ui.Presentation_Profile_Record
		if commands.gutter_inspection.popup_open {
			profile_record, profile_ok, profile_failure :=
				command_context_contextual_presentation_profile(commands)
			if !profile_ok do return profile_failure
			presentation_profile = profile_record
		}
		popup, popup_ok, popup_failure := proposal_compose_gutter_popup(
			&proposal,
			commands.gutter_inspection,
			projections[active_projection_index].surface,
			projections[active_projection_index].logical.state_generation,
			gutter_views[active_pane_index],
			presentation_profile,
			ui_profile,
		)
		if !popup_ok do return App_Failure{stage = .UI, ui = popup_failure}
		gutter_popup = popup
	}
	input_surface: ui.Object_Handle
	candidate_presentation_generation: u64
	if candidate_composition {
		composition, composed, compose_failure := proposal_compose_candidate_ui(
			&proposal,
			commands,
			base_root,
			base_focus,
			constraints,
			content_rows,
			candidate_rows,
			ui_profile.id,
		)
		if !composed do return App_Failure{stage = .UI, ui = compose_failure}
		input_surface = composition.input_surface
		candidate_presentation_generation = composition.presentation_generation
	} else if prompt_mode_projects_input(commands.prompt_workflow.mode) {
		composition, composed, compose_failure := proposal_compose_transient_input(
			&proposal,
			commands,
			base_root,
			base_focus,
			constraints,
			ui_profile.id,
			active_registry,
			active_view,
		)
		if !composed do return App_Failure{stage = .UI, ui = compose_failure}
		input_surface = composition.input_surface
	} else if transient_feedback_projects_root_edge(commands) {
		if composed, compose_failure := proposal_compose_command_feedback(
			&proposal,
			commands,
			base_root,
			base_focus,
			constraints,
		); !composed {
			return App_Failure{stage = .UI, ui = compose_failure}
		}
	}
	root, published, publish_failure := ui.proposal_publish(ui_registry, &proposal, ui_profile)
	if !published {
		return App_Failure{stage = .UI, ui = publish_failure}
	}
	previous_root := commands.ui_root
	commands.ui_root = root
	pointer_capture_reconcile_root(commands, previous_root, root)
	if completion_popup.present {
		_, _ = popup_workflow_reconcile_root(&commands.popup_workflow, root)
		focus, focused, focus_failure := ui.registry_focus(ui_registry)
		if !focused do return App_Failure{stage = .UI, ui = focus_failure}
		if !focus.transient.active || focus.transient.popup != completion_popup.handle {
			captured, capture_failure := ui.registry_capture_transient_input(
				ui_registry,
				completion_popup.handle,
			)
			if !captured do return App_Failure{stage = .UI, ui = capture_failure}
		}
	} else if gutter_popup.present {
		focus, focused, focus_failure := ui.registry_focus(ui_registry)
		if !focused do return App_Failure{stage = .UI, ui = focus_failure}
		if !popup_workflow_activate(
			&commands.popup_workflow,
			root,
			gutter_popup.descriptor,
			focus,
		) {
			return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Invalid_Popup}}
		}
	} else {
		_, _ = popup_workflow_reconcile_root(&commands.popup_workflow, root)
	}
	if candidate_composition {
		captured, capture_failure := ui.registry_capture_focus(ui_registry, input_surface)
		if !captured do return App_Failure{stage = .UI, ui = capture_failure}
		commands.candidate_ui.next_presentation_generation = candidate_presentation_generation
	} else if prompt_mode_projects_input(commands.prompt_workflow.mode) {
		commands.prompt_workflow.focus_captured = false
		if capture_failure := command_context_capture_prompt_focus(commands, input_surface);
		   capture_failure.stage != .None {
			return capture_failure
		}
	}
	ui_snapshot, copied, copy_failure := ui.registry_snapshot(ui_registry, root, ui_profile)
	if !copied {
		return App_Failure{stage = .UI, ui = copy_failure}
	}
	defer ui.snapshot_close(&ui_snapshot)
	presented, presentation_failure := terminal.renderer_present_ui(
		renderer,
		session,
		terminal.UI_Presentation {
			root = &ui_snapshot,
			text_surfaces = projections[:text_projection_count],
		},
	)
	if !presented {
		return App_Failure{stage = .Presentation, terminal = presentation_failure}
	}
	return {}
}

@(private)
projected_search_snapshot :: proc(
	search_snapshot: editor_view.Search_Snapshot,
	query_replacement: editor_view.Query_Replacement_Snapshot,
) -> editor_view.Search_Snapshot {
	if !query_replacement.present {
		return search_snapshot
	}
	status := editor_view.Search_Status.Active
	if query_replacement.status == .Pending {
		status = .Pending
	} else if query_replacement.status == .Wrapped {
		status = .Wrapped
	}
	return editor_view.Search_Snapshot {
		present = true,
		interaction_generation = query_replacement.interaction_generation,
		source_revision = query_replacement.source_revision,
		direction = query_replacement.direction,
		kind = query_replacement.kind,
		scope = query_replacement.scope,
		status = status,
		query = query_replacement.pattern,
		last_successful_query = query_replacement.pattern,
		effective_case = query_replacement.effective_case,
		has_current = query_replacement.has_current,
		current_index = query_replacement.current_index,
		occurrences = query_replacement.occurrences,
		captures = query_replacement.captures,
		progress = query_replacement.progress,
	}
}

@(private)
present_current_view :: proc(
	buffer: ^editor.Buffer,
	registry: ^editor_view.Registry,
	handle: editor_view.View_Handle,
	session: ^terminal.Session,
	renderer: ^terminal.Renderer,
	constraints: display.Viewport_Constraints,
	next_snapshot_id: ^u64,
	commands: ^Command_Context = nil,
) -> App_Failure {
	content_rows, rows_ok := transient_input_content_rows(commands, constraints)
	if !rows_ok do return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Invalid_Layout}}
	content_constraints := constraints
	content_constraints.height_rows = content_rows
	logical, logical_ok, logical_failure := editor_view.snapshot(registry, handle)
	if !logical_ok {
		return App_Failure{stage = .View_Snapshot, view = logical_failure}
	}
	search_snapshot, search_ok, search_failure := editor_view.search_session_view(registry, handle)
	if !search_ok {
		return App_Failure{stage = .View_Snapshot, view = search_failure}
	}
	query_replacement, query_ok, query_failure :=
		editor_view.query_replacement_session_view(registry, handle)
	if !query_ok {
		return App_Failure{stage = .View_Snapshot, view = query_failure}
	}
	projected_search := projected_search_snapshot(search_snapshot, query_replacement)
	snapshot, projected, projection_failure := display.project_view(
		buffer,
		registry,
		handle,
		display.Projection_Request {
			snapshot_id = display.Snapshot_ID(next_snapshot_id^),
			search = projected_search,
			view = logical,
			constraints = content_constraints,
			profile = display.terminal_unicode17_profile(),
			limits = display.DEFAULT_RESOURCE_LIMITS,
			allocators = display.Allocator_Set {
				persistent = context.allocator,
				temporary = context.temp_allocator,
			},
		},
	)
	if !projected {
		return App_Failure{stage = .Projection, display = projection_failure}
	}
	defer display.snapshot_close(&snapshot)
	next_snapshot_id^ += 1
	ui_profile, ui_profile_ok := terminal.renderer_ui_profile(renderer)
	if !ui_profile_ok {
		return App_Failure{stage = .Presentation, terminal = {code = .Invalid_Renderer}}
	}
	local_ui_registry: ui.Registry
	ui_registry := &local_ui_registry
	local_ui_owned := false
	expected_root: ui.Root_Handle
	if commands != nil {
		registry, registry_ok, registry_failure := command_context_ui_registry(commands)
		if !registry_ok {
			return registry_failure
		}
		ui_registry = registry
		expected_root = commands.ui_root
	} else {
		initialized, ui_failure := ui.registry_init(ui_registry, 1)
		if !initialized {
			return App_Failure{stage = .UI, ui = ui_failure}
		}
		local_ui_owned = true
	}
	defer if local_ui_owned do ui.registry_close(&local_ui_registry)
	proposal, proposal_ok, proposal_failure := ui.proposal_begin(ui_registry, expected_root)
	if !proposal_ok {
		return App_Failure{stage = .UI, ui = proposal_failure}
	}
	defer if proposal.state != nil do ui.proposal_abort(&proposal)
	styles_ok, styles_failure := proposal_resolve_session_theme(&proposal, commands)
	if !styles_ok do return styles_failure
	ui_view, ui_view_ok, ui_view_failure := ui.proposal_project_editor_text_view(
		&proposal,
		registry,
		handle,
		buffer,
		ui.Owner_ID(logical.buffer_id),
		false,
		&projected_search,
		command_context_text_cursor_shape(commands),
	)
	if !ui_view_ok {
		return App_Failure{stage = .UI, ui = ui_view_failure}
	}
	if commands != nil {
		syntax_workflow_project_visible(
			commands.syntax_workflow,
			buffer,
			snapshot,
			&proposal,
			ui_view,
			ui.Owner_ID(logical.buffer_id),
		)
		_ = language_service_workflow_project_visible(
			commands.language_service_workflow,
			buffer,
			&proposal,
			ui_view,
			ui.Owner_ID(logical.buffer_id),
		)
	}
	surface, surface_ok, surface_failure := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = ui.Owner_ID(logical.buffer_id),
			view = ui_view,
			focusable = true,
			visible = true,
			required_profile = ui_profile.id,
			geometry = {
				height = i32(content_rows),
				width = i32(constraints.width_cells),
			},
		},
	)
	if !surface_ok {
		return App_Failure{stage = .UI, ui = surface_failure}
	}
	node, node_ok, node_failure := ui.proposal_add_surface_node(&proposal, surface)
	if !node_ok {
		return App_Failure{stage = .UI, ui = node_failure}
	}
	input_surface: ui.Object_Handle
	if commands != nil && prompt_mode_projects_input(commands.prompt_workflow.mode) {
		composition, composed, compose_failure := proposal_compose_transient_input(
			&proposal,
			commands,
			node,
			surface,
			constraints,
			ui_profile.id,
			registry,
			handle,
		)
		if !composed do return App_Failure{stage = .UI, ui = compose_failure}
		input_surface = composition.input_surface
	} else if commands != nil && transient_feedback_projects_root_edge(commands) {
		if composed, compose_failure := proposal_compose_command_feedback(
			&proposal,
			commands,
			node,
			surface,
			constraints,
		); !composed {
			return App_Failure{stage = .UI, ui = compose_failure}
		}
	} else if root_ok, root_failure := ui.proposal_set_root(&proposal, node, surface); !root_ok {
		return App_Failure{stage = .UI, ui = root_failure}
	}
	root, published, publish_failure := ui.proposal_publish(ui_registry, &proposal, ui_profile)
	if !published {
		return App_Failure{stage = .UI, ui = publish_failure}
	}
	if commands != nil {
		previous_root := commands.ui_root
		commands.ui_root = root
		pointer_capture_reconcile_root(commands, previous_root, root)
		if prompt_mode_projects_input(commands.prompt_workflow.mode) {
			commands.prompt_workflow.focus_captured = false
			if capture_failure := command_context_capture_prompt_focus(commands, input_surface);
			   capture_failure.stage != .None {
				return capture_failure
			}
		}
	}
	ui_snapshot, copied, copy_failure := ui.registry_snapshot(ui_registry, root, ui_profile)
	if !copied {
		return App_Failure{stage = .UI, ui = copy_failure}
	}
	defer ui.snapshot_close(&ui_snapshot)
	presentation := terminal.UI_Presentation {
		root = &ui_snapshot,
		text_surfaces = []terminal.Text_Surface_Projection {{
			surface = surface,
			snapshot = snapshot,
			logical = logical,
		}},
	}
	presented, presentation_failure := terminal.renderer_present_ui(
		renderer,
		session,
		presentation,
	)
	if !presented {
		return App_Failure{stage = .Presentation, terminal = presentation_failure}
	}
	return {}
}

@(private)
constraints_from_geometry :: proc(geometry: terminal.Geometry) -> display.Viewport_Constraints {
	return display.Viewport_Constraints {
		width_cells = min(geometry.width_cells, display.OPERATING_VIEWPORT_WIDTH_CELLS),
		height_rows = min(geometry.height_rows, display.OPERATING_VIEWPORT_HEIGHT_ROWS),
	}
}
