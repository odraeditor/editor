// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import "../command"
import "../display"
import "../interaction"
import "../ksawery"
import "../product_module"
import "../ui"
import "base:runtime"
import "core:time"
import "core:unicode/utf8"

Module_Instance :: struct {
	commands: Command_Context,
	workflow: Ksawery_Workflow_State,
}

@(export)
odra_product_module_entrypoint :: proc "c" (
	descriptor: ^product_module.Descriptor,
	descriptor_size: u64,
) -> product_module.Status {
	if descriptor == nil || descriptor_size != size_of(product_module.Descriptor) {
		return .Invalid_Argument
	}
	value: product_module.Descriptor
	value.struct_size = size_of(product_module.Descriptor)
	value.abi_minimum = product_module.ABI_VERSION
	value.abi_maximum = product_module.ABI_VERSION
	value.role = .Source_Control
	value.identity_length = u16(copy(value.identity[:], "odra.ksawery"))
	value.version_length = u16(copy(value.version[:], "1.0.0"))
	value.open = module_open
	value.call = module_call
	value.close = module_close
	descriptor^ = value
	return .Ok
}

@(private)
module_open :: proc "c" (
	host_call: product_module.Host_Call,
	capability: u64,
	instance: ^u64,
) -> product_module.Status {
	context = runtime.default_context()
	if host_call == nil || capability == 0 || instance == nil do return .Invalid_Argument
	state := new(Module_Instance)
	if state == nil do return .Failed
	state.commands.host = {call = host_call, capability = capability}
	state.commands.persistent_allocator = context.allocator
	state.commands.temporary_allocator = context.temp_allocator
	state.commands.grouping_started = time.tick_now()
	state.commands.ksawery_workflow = &state.workflow
	state.workflow.allocator = context.allocator
	if !ksawery_extension_provider_registry_init(&state.workflow.extension_registry, context.allocator) {
		free(state)
		return .Failed
	}
	instance^ = u64(uintptr(state))
	return .Ok
}

@(private)
module_call :: proc "c" (
	instance: u64,
	operation: product_module.Operation,
	input: ^u8,
	input_length: u64,
	output: ^u8,
	output_capacity: u64,
	output_length: ^u64,
) -> product_module.Status {
	context = runtime.default_context()
	if instance == 0 || output_length == nil || input_length > product_module.MAX_CALL_BYTES ||
	   output_capacity > product_module.MAX_CALL_BYTES {
		return .Invalid_Argument
	}
	output_length^ = 0
	state := (^Module_Instance)(uintptr(instance))
	input_bytes: []u8
	if input_length > 0 {
		if input == nil do return .Invalid_Argument
		input_bytes = ([^]u8)(input)[:int(input_length)]
	}
	_ = output
	switch operation {
	case .Activate:
		return module_activate(state, input_bytes)
	case .Invoke:
		return module_invoke(state, input_bytes)
	case .Input:
		return module_input(state, input_bytes)
	case .Select:
		return module_select(state, input_bytes)
	case .Configure:
		return module_configure(state, input_bytes)
	case .Step:
		if !state.workflow.active do return .Unavailable
		changed := ksawery_workflow_step(&state.commands)
		if output_capacity > 0 {
			if output == nil do return .Invalid_Argument
			output^ = 1 if changed else 0
			output_length^ = 1
		}
		return .Ok
	case .Inspect:
		if !state.workflow.active do return .Unavailable
		next_snapshot_id := u64(1)
		failure := present_ksawery_status_ui(
			&state.commands,
			display.Viewport_Constraints{width_cells = 120, height_rows = 40},
			&next_snapshot_id,
		)
		if failure.stage != .None do return .Failed
		return .Ok
	case .Deactivate:
		return module_deactivate(state, true)
	case .Invalid:
		return .Invalid_Argument
	}
	return .Invalid_Argument
}

@(private)
module_configure :: proc(state: ^Module_Instance, request_bytes: []u8) -> product_module.Status {
	if state == nil || len(request_bytes) < size_of(product_module.Configuration_Request_Header) {
		return .Invalid_Argument
	}
	header := (^product_module.Configuration_Request_Header)(raw_data(request_bytes))
	if header.schema_version != product_module.CONFIGURATION_REQUEST_SCHEMA_VERSION ||
	   header.disposition == .Invalid ||
	   header.generation == 0 ||
	   header.payload_length != u64(len(request_bytes) - size_of(product_module.Configuration_Request_Header)) {
		return .Invalid_Argument
	}
	payload := request_bytes[size_of(product_module.Configuration_Request_Header):]
	registry := &state.workflow.extension_registry
	if header.disposition == .Rejected {
		if len(payload) != 0 do return .Invalid_Argument
		state.commands.personal_configuration.status = .Rejected
		state.commands.personal_configuration.rejected_generation = header.generation
		if state.workflow.active do command_context_set_diagnostic(
			&state.commands, "Personal command reload rejected; active generation preserved",
		)
		return .Ok
	}
	if header.disposition == .Removed || len(payload) == 0 {
		removed, _ := ksawery_extension_provider_remove(registry, header.generation)
		if registry.active != nil && !removed do return .Failed
	} else {
		candidate, prepared, _ := ksawery_extension_provider_prepare(
			registry,
			payload,
			header.generation,
		)
		if !prepared do return .Failed
		defer if candidate.data != nil do ksawery_extension_provider_candidate_close(&candidate)
		if !ksawery_extension_provider_candidate_confirm(&candidate) do return .Failed
		activated, _ := ksawery_extension_provider_activate(registry, &candidate)
		if !activated do return .Failed
	}
	state.commands.personal_configuration.status = .Confirmed
	state.commands.personal_configuration.confirmed_generation = header.generation
	state.commands.personal_configuration.rejected_generation = 0
	if state.workflow.active do command_context_set_diagnostic(&state.commands, "Personal commands reloaded")
	module_refresh_extensions(state)
	return .Ok
}

@(private)
module_refresh_extensions :: proc(state: ^Module_Instance) {
	if state == nil do return
	workflow := &state.workflow
	registry := &workflow.extension_registry
	host := &state.commands.host
	allocator := state.commands.temporary_allocator
	if workflow.observation.state != nil {
		_ = ksawery_extension_status_refresh(registry, host, &workflow.observation, allocator)
		diff := &workflow.diff if workflow.diff.state != nil else nil
		_ = ksawery_extension_annotations_refresh_status(
			registry, host, &workflow.observation, diff, allocator,
		)
	}
	if workflow.history.state != nil {
		_ = ksawery_extension_annotations_refresh_history(registry, host, &workflow.history, allocator)
	}
	if workflow.refs.state != nil {
		_ = ksawery_extension_annotations_refresh_refs(registry, host, &workflow.refs, allocator)
	}
	if workflow.sequence.state != nil {
		_ = ksawery_extension_annotations_refresh_sequence(registry, host, &workflow.sequence, allocator)
	}
	workflow.extension_status = ksawery_extension_status_generation(registry)
}

@(private)
module_activate :: proc(state: ^Module_Instance, repository_path: []u8) -> product_module.Status {
	if state == nil || state.workflow.active || len(repository_path) == 0 do return .Invalid_Argument
	repository: ksawery.Repository_Context
	if !ksawery.repository_context_assign(&repository, string(repository_path)) {
		return .Invalid_Argument
	}
	request := ksawery.Process_Request {
		kind = .Observe_Status,
		repository = repository,
		limits = ksawery.DEFAULT_PROCESS_LIMITS,
	}
	process, started, _ := ksawery.repository_process_start(
		request,
		ksawery_workflow_now(&state.commands),
		state.commands.persistent_allocator,
	)
	if !started do return .Unavailable
	coordinator: Ksawery_Process_Coordinator
	if !ksawery_process_coordinator_init(
		&coordinator,
		repository,
		ksawery.DEFAULT_PROCESS_RECORD_LIMITS,
		state.commands.persistent_allocator,
	) {
		ksawery.repository_process_close(&process)
		return .Failed
	}
	recorded, _ := ksawery_process_observation_begin(
		&coordinator,
		&process,
		1,
		{
			kind = .Status,
			target_kind = .Repository,
			title = "Repository Status",
			target = ksawery.repository_context_string(&repository),
			phase_detail = "Reading repository status",
			refreshing = true,
		},
		ksawery_workflow_now(&state.commands),
	)
	if !recorded {
		ksawery.repository_process_close(&process)
		ksawery_process_coordinator_close(&coordinator)
		return .Failed
	}
	session, presented := host_session_request(
		&state.commands.host,
		.Present_Surface,
		0,
		0,
		"source-control.status",
	)
	if !presented {
		ksawery.repository_process_close(&process)
		ksawery_process_coordinator_close(&coordinator)
		return .Unavailable
	}
	extension_registry := state.workflow.extension_registry
	state.workflow = {
		active = true,
		allocator = state.commands.persistent_allocator,
		extension_registry = extension_registry,
		previous = session.target,
		repository = repository,
		process = process,
		process_coordinator = coordinator,
		pending = .Observe,
		generation = 1,
		next_action = 1,
		next_commit = 1,
		next_fetch = 1,
		next_push = 1,
		next_branch = 1,
		next_tag = 1,
		next_merge = 1,
		next_rebase = 1,
		next_revision_sequence = 1,
		next_bisect = 1,
		next_conflict_resolution = 1,
		conflict_assistance_request = 1,
		conflict_assistance_selection_generation = 1,
		next_raw_command = 1,
		next_raw_confirmation = 1,
		next_confirmation = 1,
		next_push_confirmation = 1,
		next_branch_confirmation = 1,
		next_tag_confirmation = 1,
		next_merge_confirmation = 1,
		next_rebase_confirmation = 1,
		next_revision_sequence_confirmation = 1,
		next_bisect_confirmation = 1,
		next_conflict_confirmation = 1,
		next_extension_command_request = 1,
		next_extension_command_confirmation = 1,
	}
	return .Ok
}

@(private)
module_invoke :: proc(state: ^Module_Instance, request_bytes: []u8) -> product_module.Status {
	if state == nil || !state.workflow.active || len(request_bytes) == 0 do return .Invalid_Argument
	if len(request_bytes) >= size_of(product_module.Invocation_Request_Header) {
		header := (^product_module.Invocation_Request_Header)(raw_data(request_bytes))
		if header.schema_version == product_module.INVOCATION_REQUEST_SCHEMA_VERSION {
			if header.provider == 0 || header.operation == 0 || header.name_length == 0 ||
			   int(header.name_length) != len(request_bytes) - size_of(product_module.Invocation_Request_Header) {
				return .Invalid_Argument
			}
			metadata: interaction.Command_Metadata
			metadata.name = string(request_bytes[size_of(product_module.Invocation_Request_Header):])
			metadata.route = {
				provider = interaction.Command_Provider_ID(header.provider),
				operation = header.operation,
			}
			_, failure := dispatch_ksawery_status_input(&state.commands, {}, &metadata)
			if failure.stage != .None do return .Failed
			return .Ok
		}
	}
	command_name := string(request_bytes)
	direct_route := command.Contextual_Route.Invalid
	switch command_name {
	case "ksawery-bisect-start":     direct_route = .Ksawery_Bisect_Start
	case "ksawery-provider-disable": direct_route = .Ksawery_Provider_Disable
	case "ksawery-stashes":          direct_route = .Ksawery_Stashes
	case "ksawery-worktrees":        direct_route = .Ksawery_Worktrees
	case "ksawery-blame":            direct_route = .Ksawery_Blame
	case "ksawery-reflog":           direct_route = .Ksawery_Reflog
	case "ksawery-sequence":         direct_route = .Ksawery_Sequence
	case:
	}
	if direct_route != .Invalid {
		metadata: interaction.Command_Metadata
		metadata.name = command_name
		metadata.route = command.contextual_route(direct_route)
		_, failure := dispatch_ksawery_status_input(&state.commands, {}, &metadata)
		if failure.stage != .None do return .Failed
		return .Ok
	}
	input, mapped := module_command_input(command_name)
	if !mapped do return .Unavailable
	_, failure := dispatch_ksawery_status_input(&state.commands, input)
	if failure.stage != .None do return .Failed
	return .Ok
}

@(private)
module_input :: proc(state: ^Module_Instance, request_bytes: []u8) -> product_module.Status {
	if state == nil || !state.workflow.active ||
	   len(request_bytes) < size_of(product_module.Input_Request_Header) {
		return .Invalid_Argument
	}
	header := (^product_module.Input_Request_Header)(raw_data(request_bytes))
	if header.schema_version != product_module.INPUT_REQUEST_SCHEMA_VERSION ||
	   int(header.text_length) != len(request_bytes) - size_of(product_module.Input_Request_Header) {
		return .Invalid_Argument
	}
	input: interaction.Input
	character_storage: [4]u8
	switch header.kind {
	case .Key:
		if header.key_kind <= .Invalid || header.key_kind > .Escape || header.text_length != 0 {
			return .Invalid_Argument
		}
		input = {
			kind = .Key,
			stroke = {
				kind = interaction.Logical_Key_Kind(header.key_kind),
				scalar = rune(header.scalar),
				modifiers = transmute(interaction.Modifiers)header.modifiers,
			},
		}
		if input.stroke.kind == .Unicode_Scalar && input.stroke.modifiers == {} {
			encoded, count := utf8.encode_rune(input.stroke.scalar)
			if count <= 0 || count > len(character_storage) do return .Invalid_Argument
			copy(character_storage[:count], encoded[:count])
			input.text = string(character_storage[:count])
		}
	case .Text_Commit:
		if header.key_kind != .Invalid || header.modifiers != 0 || header.scalar != 0 ||
		   header.text_length == 0 {
			return .Invalid_Argument
		}
		input.kind = .Text_Commit
		input.text = string(request_bytes[size_of(product_module.Input_Request_Header):])
	case .Invalid:
		return .Invalid_Argument
	}
	result: Interaction_Result
	failure: App_Failure
	if state.commands.prompt_workflow.mode == .Ksawery_Discard_Choice {
		result, failure = dispatch_ksawery_discard_prompt(&state.commands, input)
	} else {
		result, failure = dispatch_ksawery_status_input(&state.commands, input)
	}
	_ = result
	if failure.stage != .None do return .Failed
	return .Ok
}

@(private)
module_select :: proc(state: ^Module_Instance, request_bytes: []u8) -> product_module.Status {
	if state == nil || !state.workflow.active ||
	   len(request_bytes) != size_of(product_module.Selection_Request) {
		return .Invalid_Argument
	}
	request := (^product_module.Selection_Request)(raw_data(request_bytes))
	if request.schema_version != product_module.UI_LIST_SCHEMA_VERSION || request.item_id == 0 {
		return .Invalid_Argument
	}
	if !ksawery_workflow_select_ui_item(&state.workflow, ui.List_Item_ID(request.item_id)) {
		return .Unavailable
	}
	return .Ok
}

@(private)
module_command_input :: proc(command_name: string) -> (interaction.Input, bool) {
	key: rune
	switch command_name {
	case "component-previous-row": return {kind = .Key, stroke = {kind = .Up}}, true
	case "component-next-row": return {kind = .Key, stroke = {kind = .Down}}, true
	case "component-complete-current": return {kind = .Key, stroke = {kind = .Tab}}, true
	case "component-activate-current": return {kind = .Key, stroke = {kind = .Enter}}, true
	case "component-close": key = 'q'
	case "result-refresh": key = 'g'
	case "ksawery-mark": key = '*'
	case "ksawery-unmark": key = '-'
	case "ksawery-clear-marks": key = '0'
	case "ksawery-stage": key = 's'
	case "ksawery-unstage": key = 'u'
	case "ksawery-discard": key = 'k'
	case "ksawery-commit": key = 'c'
	case "ksawery-amend": key = 'A'
	case "ksawery-fixup": key = 'F'
	case "ksawery-sequence": key = 'o'
	case "ksawery-history": key = 'h'
	case "ksawery-history-next-page": key = 'f'
	case "ksawery-refs": key = 'b'
	case "ksawery-processes": key = '$'
	case "ksawery-providers": key = 'v'
	case "ksawery-provider-reload": key = 'L'
	case "ksawery-raw-command": key = '!'
	case "ksawery-fetch": key = '&'
	case "ksawery-push": key = 'p'
	case "ksawery-branch-create": key = 'n'
	case "ksawery-branch-switch": key = 'S'
	case "ksawery-branch-rename": key = 'R'
	case "ksawery-branch-delete": key = 'D'
	case "ksawery-tag-create": key = 't'
	case "ksawery-tag-delete": key = 'T'
	case "ksawery-merge-fast-forward": key = '='
	case "ksawery-merge": key = 'i'
	case "ksawery-merge-no-fast-forward": key = 'I'
	case "ksawery-merge-continue": key = '>'
	case "ksawery-merge-abort": key = 'X'
	case "ksawery-rebase": key = 'e'
	case "ksawery-rebase-autosquash": key = 'E'
	case "ksawery-rebase-continue": key = ']'
	case "ksawery-rebase-skip": key = ';'
	case "ksawery-rebase-abort": key = 'Z'
	case "ksawery-sequence-mark": key = 'a'
	case "ksawery-sequence-unmark": key = 'U'
	case "ksawery-cherry-pick": key = 'P'
	case "ksawery-cherry-pick-continue": key = '{'
	case "ksawery-cherry-pick-skip": key = 'l'
	case "ksawery-cherry-pick-abort": key = 'Y'
	case "ksawery-revert": key = 'V'
	case "ksawery-revert-continue": key = '}'
	case "ksawery-revert-skip": key = 'j'
	case "ksawery-revert-abort": key = 'Q'
	case "ksawery-bisect-good": key = 'G'
	case "ksawery-bisect-bad": key = 'B'
	case "ksawery-bisect-start": key = '?'
	case "ksawery-bisect-skip": key = '|'
	case "ksawery-bisect-reset": key = '~'
	case "ksawery-conflict-mark-resolved": key = 'x'
	case "ksawery-conflict-assist": key = 'H'
	case "ksawery-conflict-use-base": key = '1'
	case "ksawery-conflict-use-current": key = '2'
	case "ksawery-conflict-use-applied": key = '3'
	case "ksawery-conflict-delete": key = 'K'
	case:
		return {}, false
	}
	return {kind = .Key, stroke = {kind = .Unicode_Scalar, scalar = key}}, true
}

@(private)
module_deactivate :: proc(state: ^Module_Instance, reusable: bool) -> product_module.Status {
	if state == nil do return .Invalid_Argument
	command_context_end_prompt(&state.commands)
	restored := true
	if state.workflow.active {
		_, restored = host_session_request(
			&state.commands.host,
			.Restore_Target,
			state.workflow.previous,
			0,
			"",
		)
		ksawery_workflow_close(&state.workflow)
	} else if state.workflow.extension_registry.allocator.procedure != nil &&
	          !state.workflow.extension_registry.closed {
		if !ksawery_extension_provider_registry_close(&state.workflow.extension_registry) {
			return .Failed
		}
	}
	state.workflow.allocator = state.commands.persistent_allocator
	state.commands.ksawery_workflow = &state.workflow
	if reusable && !ksawery_extension_provider_registry_init(
		&state.workflow.extension_registry,
		state.commands.persistent_allocator,
	) {
		return .Failed
	}
	return .Ok if restored else .Failed
}

@(private)
module_close :: proc "c" (instance: u64) -> product_module.Status {
	context = runtime.default_context()
	if instance == 0 do return .Invalid_Argument
	state := (^Module_Instance)(uintptr(instance))
	status := module_deactivate(state, false)
	free(state)
	return status
}
