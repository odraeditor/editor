// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../bridge"
import "../editor_session"
import "../hosting"
import "../project"
import "base:runtime"
import endian "core:encoding/endian"

/* Workspace_Command_Completion classifies one programmable composition result. */
Workspace_Command_Completion :: enum u8 {
	Invalid,
	Created,
	Opened,
	Updated,
	Listed,
	Inspected,
	Project_Added,
	Project_Removed,
	Project_Reordered,
	Workspace_Removed,
	Unavailable_Members,
	Dirty_Protection_Required,
}

/* Workspace_Member_State mirrors one durable Project-reference resolution. */
Workspace_Member_State :: enum u8 {
	Invalid,
	Ready,
	Missing,
	Unavailable,
	Conflict,
	Stale,
}

/* Workspace_Command_Descriptor is one copied durable Workspace summary. */
Workspace_Command_Descriptor :: struct {
	id:            string,
	generation:    u64,
	name:          string,
	member_offset: u32,
	member_count:  u32,
}

/* Workspace_Command_Member is one copied Project resolution and diagnostic. */
Workspace_Command_Member :: struct {
	workspace_index:   u32,
	state:             Workspace_Member_State,
	project_id:        project.Project_ID,
	project_generation: project.Project_Generation,
	durable_id:        string,
	name:              string,
	root:              string,
	trust:             project.Trust_State,
	diagnostic:        string,
}

/* Workspace_Command_Batch owns copied records and text until explicit close. */
Workspace_Command_Batch :: struct {
	state:       rawptr,
	descriptors: []Workspace_Command_Descriptor,
	members:     []Workspace_Command_Member,
	diagnostic:  string,
	publication: u64,
}

/* Workspace_Command_Result reports copied records and optional active publication. */
Workspace_Command_Result :: struct {
	completion: Workspace_Command_Completion,
	batch:      Workspace_Command_Batch,
	activation: editor_session.Workspace_Activation_Result,
}

@(private)
Workspace_Command_Batch_State :: struct {
	storage:     []byte,
	descriptors: []Workspace_Command_Descriptor,
	members:     []Workspace_Command_Member,
	allocator:   runtime.Allocator,
}

/* workspace_create persists and activates the current ordered Project root set. */
workspace_create :: proc(
	ctx: Project_Command_Context,
	racket_runtime: ^hosting.Runtime,
	configuration_root, name: string,
) -> (result: Workspace_Command_Result, ok: bool, failure: Failure_Context) {
	return workspace_command_run(ctx, racket_runtime, configuration_root, .Create, "", 0, name, "", true)
}

/* workspace_open resolves and activates one durable Workspace identity. */
workspace_open :: proc(
	ctx: Project_Command_Context,
	racket_runtime: ^hosting.Runtime,
	configuration_root, id: string,
) -> (result: Workspace_Command_Result, ok: bool, failure: Failure_Context) {
	return workspace_command_run(ctx, racket_runtime, configuration_root, .Open, id, 0, "", "", true)
}

/* workspace_update persists and activates an explicit next composition generation. */
workspace_update :: proc(
	ctx: Project_Command_Context,
	racket_runtime: ^hosting.Runtime,
	configuration_root, id: string,
	expected_generation: u64,
	name: string,
) -> (result: Workspace_Command_Result, ok: bool, failure: Failure_Context) {
	return workspace_command_run(
		ctx, racket_runtime, configuration_root, .Update,
		id, expected_generation, name, "", true,
	)
}

/* workspace_add_project persists one selected Project into one durable Workspace. */
workspace_add_project :: proc(
	ctx: Project_Command_Context,
	racket_runtime: ^hosting.Runtime,
	configuration_root, id: string,
	expected_generation: u64,
	project_root: string,
) -> (result: Workspace_Command_Result, ok: bool, failure: Failure_Context) {
	return workspace_command_run(
		ctx, racket_runtime, configuration_root, .Add_Project,
		id, expected_generation, "", project_root, true,
	)
}

/* workspace_remove_project removes one selected Project from one durable Workspace. */
workspace_remove_project :: proc(
	ctx: Project_Command_Context,
	racket_runtime: ^hosting.Runtime,
	configuration_root, id: string,
	expected_generation: u64,
	project_root: string,
) -> (result: Workspace_Command_Result, ok: bool, failure: Failure_Context) {
	return workspace_command_run(
		ctx, racket_runtime, configuration_root, .Remove_Project,
		id, expected_generation, "", project_root, true,
	)
}

/* workspace_move_project publishes one checked neighboring member exchange. */
workspace_move_project :: proc(
	ctx: Project_Command_Context,
	racket_runtime: ^hosting.Runtime,
	configuration_root, id: string,
	expected_generation: u64,
	project_root: string,
	earlier: bool,
) -> (result: Workspace_Command_Result, ok: bool, failure: Failure_Context) {
	action := bridge.Workspace_Command_Action.Move_Project_Down
	if earlier do action = .Move_Project_Up
	return workspace_command_run(
		ctx, racket_runtime, configuration_root, action,
		id, expected_generation, "", project_root, true,
	)
}

/* workspace_unregister removes one durable Workspace from the global catalog. */
workspace_unregister :: proc(
	ctx: Project_Command_Context,
	racket_runtime: ^hosting.Runtime,
	configuration_root, id: string,
	expected_generation: u64,
) -> (result: Workspace_Command_Result, ok: bool, failure: Failure_Context) {
	return workspace_command_run(
		ctx, racket_runtime, configuration_root, .Unregister,
		id, expected_generation, "", "", false,
	)
}

/* workspace_list copies the deterministic durable Workspace catalog. */
workspace_list :: proc(
	ctx: Project_Command_Context,
	racket_runtime: ^hosting.Runtime,
	configuration_root: string,
) -> (result: Workspace_Command_Result, ok: bool, failure: Failure_Context) {
	return workspace_command_run(ctx, racket_runtime, configuration_root, .List, "", 0, "", "", false)
}

/* workspace_inspect copies one durable Workspace and all member resolutions. */
workspace_inspect :: proc(
	ctx: Project_Command_Context,
	racket_runtime: ^hosting.Runtime,
	configuration_root, id: string,
) -> (result: Workspace_Command_Result, ok: bool, failure: Failure_Context) {
	return workspace_command_run(ctx, racket_runtime, configuration_root, .Inspect, id, 0, "", "", false)
}

/* workspace_command_batch_close releases one copied Workspace result. */
workspace_command_batch_close :: proc(batch: ^Workspace_Command_Batch) -> bool {
	if batch == nil || batch.state == nil {
		return false
	}
	state := (^Workspace_Command_Batch_State)(batch.state)
	allocator := state.allocator
	if state.members != nil {
		delete(state.members, allocator)
	}
	if state.descriptors != nil {
		delete(state.descriptors, allocator)
	}
	if state.storage != nil {
		delete(state.storage, allocator)
	}
	free(state, allocator)
	batch^ = {}
	return true
}

@(private)
workspace_command_run :: proc(
	ctx: Project_Command_Context,
	racket_runtime: ^hosting.Runtime,
	configuration_root: string,
	action: bridge.Workspace_Command_Action,
	id: string,
	expected_generation: u64,
	name: string,
	project_root: string,
	activate: bool,
) -> (result: Workspace_Command_Result, ok: bool, failure: Failure_Context) {
	if !project_command_context_is_valid(ctx) || racket_runtime == nil ||
	   len(configuration_root) == 0 || action == .Invalid {
		return {}, false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	roots, roots_ok, roots_failure := editor_session.session_roots(ctx.session, ctx.handle)
	if !roots_ok {
		return {}, false, buffer_session_failure(ctx.command, roots_failure)
	}
	defer editor_session.root_batch_close(&roots)
	request_roots: [int(editor_session.MAX_SESSION_ROOTS)]string
	request_root_count := 0
	if action == .Create || action == .Update {
		if len(roots.descriptors) < 1 {
			return {}, false, Failure_Context{code = .Project_Scope_Required, command = ctx.command}
		}
		for root in roots.descriptors {
			if root.kind != .Project {
				return {}, false, Failure_Context{code = .Project_Scope_Required, command = ctx.command}
			}
		}
		for root, index in roots.descriptors {
			request_roots[index] = root.path
		}
		request_root_count = len(roots.descriptors)
	} else if action == .Add_Project || action == .Remove_Project ||
	          action == .Move_Project_Up || action == .Move_Project_Down {
		if len(project_root) == 0 {
			return {}, false, Failure_Context{code = .Invalid_Request, command = ctx.command}
		}
		request_roots[0] = project_root
		request_root_count = 1
	}
	request, encoded := workspace_request_encode(
		action, expected_generation, id, name, request_roots[:request_root_count],
		ctx.temporary_allocator,
	)
	if !encoded {
		return {}, false, Failure_Context{code = .Temporary_Memory_Limit, command = ctx.command}
	}
	defer delete(request, ctx.temporary_allocator)
	output, output_error := make([]byte, int(bridge.MAX_WORKSPACE_COMMAND_BYTES), ctx.temporary_allocator)
	if output_error != nil {
		return {}, false, Failure_Context{code = .Temporary_Memory_Limit, command = ctx.command}
	}
	defer delete(output, ctx.temporary_allocator)
	output_length, transferred, transfer_failure := hosting.runtime_workspace_command(
		racket_runtime, configuration_root, request, output,
	)
	if !transferred {
		return {}, false, hosting_failure_context(
			Failure_Context{command = ctx.command}, transfer_failure,
		)
	}
	batch, decoded := workspace_result_decode(
		output[:int(output_length)], action, ctx.persistent_allocator,
	)
	if !decoded {
		return {}, false, Failure_Context{code = .Wrong_Result, command = ctx.command}
	}
	result.batch = batch
	if len(batch.descriptors) == 0 && action != .List && action != .Unregister {
		failure = Failure_Context{code = .Workspace_Rejected, command = ctx.command}
		workspace_command_batch_close(&result.batch)
		return {}, false, failure
	}
	if !activate {
		result.completion = .Listed if action == .List else .Workspace_Removed if action == .Unregister else .Inspected
		return result, true, {}
	}
	descriptor := &batch.descriptors[0]
	proposals, proposal_error := make(
		[]editor_session.Workspace_Project_Proposal,
		int(descriptor.member_count),
		ctx.temporary_allocator,
	)
	if proposal_error != nil {
		workspace_command_batch_close(&result.batch)
		return {}, false, Failure_Context{code = .Temporary_Memory_Limit, command = ctx.command}
	}
	defer delete(proposals, ctx.temporary_allocator)
	unavailable: u32
	ready_count := 0
	for index in 0 ..< int(descriptor.member_count) {
		member := &batch.members[int(descriptor.member_offset) + index]
		if member.state != .Ready {
			unavailable += 1
			continue
		}
		proposals[ready_count] = editor_session.Workspace_Project_Proposal {
			project_id = member.project_id,
			project_generation = member.project_generation,
			durable_id = member.durable_id,
			name = member.name,
			root = member.root,
			trust = member.trust,
		}
		ready_count += 1
	}
	prepared: editor_session.Workspace_Activation_Preparation
	prepared_ok, prepare_failure := editor_session.session_prepare_workspace_activation(
		ctx.session,
		editor_session.Workspace_Activation_Proposal {
			session = ctx.handle,
			expected_root_set = roots.generation,
			id = descriptor.id,
			generation = descriptor.generation,
			name = descriptor.name,
			projects = proposals[:ready_count],
			unavailable_members = unavailable,
		},
		&prepared,
	)
	if !prepared_ok {
		workspace_command_batch_close(&result.batch)
		return {}, false, buffer_session_failure(ctx.command, prepare_failure)
	}
	if prepared.outcome == .Unavailable_Members {
		result.completion = .Unavailable_Members
		return result, true, {}
	}
	if prepared.outcome == .Dirty_Protection_Required {
		editor_session.session_abort_workspace_activation(&prepared)
		result.completion = .Dirty_Protection_Required
		return result, true, {}
	}
	activation, admitted, admit_failure := editor_session.session_admit_workspace_activation(
		ctx.session, &prepared,
	)
	if !admitted {
		editor_session.session_abort_workspace_activation(&prepared)
		workspace_command_batch_close(&result.batch)
		return {}, false, buffer_session_failure(ctx.command, admit_failure)
	}
	result.activation = activation
	switch action {
	case .Create: result.completion = .Created
	case .Open: result.completion = .Opened
	case .Update: result.completion = .Updated
	case .Add_Project: result.completion = .Project_Added
	case .Remove_Project: result.completion = .Project_Removed
	case .Move_Project_Up, .Move_Project_Down: result.completion = .Project_Reordered
	case .List, .Inspect, .Unregister, .Invalid:
		result.completion = .Invalid
	}
	return result, true, {}
}

@(private)
workspace_request_encode :: proc(
	action: bridge.Workspace_Command_Action,
	expected_generation: u64,
	id, name: string,
	roots: []string,
	allocator: runtime.Allocator,
) -> ([]byte, bool) {
	length := int(bridge.WORKSPACE_REQUEST_HEADER_BYTES) + len(id) + len(name)
	for root in roots {
		length += 8 + len(root)
	}
	if u64(length) > bridge.MAX_WORKSPACE_COMMAND_BYTES {
		return nil, false
	}
	request, request_error := make([]byte, length, allocator)
	if request_error != nil {
		return nil, false
	}
	values := [?]u64 {
		bridge.WORKSPACE_COMMAND_SCHEMA_VERSION,
		u64(action),
		expected_generation,
		u64(len(id)),
		u64(len(name)),
		u64(len(roots)),
	}
	offset := 0
	for value in values {
		written := endian.put_u64(request[offset:], .Little, value)
		assert(written)
		offset += 8
	}
	copy(request[offset:], transmute([]u8)id)
	offset += len(id)
	copy(request[offset:], transmute([]u8)name)
	offset += len(name)
	for root in roots {
		written := endian.put_u64(request[offset:], .Little, u64(len(root)))
		assert(written)
		offset += 8
		copy(request[offset:], transmute([]u8)root)
		offset += len(root)
	}
	assert(offset == len(request))
	return request, true
}

@(private)
workspace_result_decode :: proc(
	input: []byte,
	action: bridge.Workspace_Command_Action,
	allocator: runtime.Allocator,
) -> (batch: Workspace_Command_Batch, ok: bool) {
	if len(input) < int(bridge.WORKSPACE_RESULT_HEADER_BYTES) {
		return {}, false
	}
	header_values: [11]u64
	for &value, index in header_values {
		read_ok: bool
		value, read_ok = endian.get_u64(input[index * 8:], .Little)
		if !read_ok {
			return {}, false
		}
	}
	if header_values[0] != bridge.WORKSPACE_COMMAND_SCHEMA_VERSION ||
	   header_values[1] != u64(action) || header_values[2] > 1 ||
	   header_values[3] > bridge.MAX_WORKSPACE_RESULT_RECORDS ||
	   header_values[4] > bridge.MAX_WORKSPACE_MEMBER_RECORDS {
		return {}, false
	}
	required, admitted := bridge.workspace_result_bytes(
		header_values[3], header_values[4], header_values[6],
	)
	if !admitted || required != u64(len(input)) {
		return {}, false
	}
	state, state_error := new(Workspace_Command_Batch_State, allocator)
	if state_error != nil {
		return {}, false
	}
	state.allocator = allocator
	state.storage, state_error = make([]byte, len(input), allocator)
	if state_error != nil {
		free(state, allocator)
		return {}, false
	}
	copy(state.storage, input)
	state.descriptors, state_error = make([]Workspace_Command_Descriptor, int(header_values[3]), allocator)
	if state_error != nil {
		workspace_batch_state_destroy(state)
		return {}, false
	}
	state.members, state_error = make([]Workspace_Command_Member, int(header_values[4]), allocator)
	if state_error != nil {
		workspace_batch_state_destroy(state)
		return {}, false
	}
	record_offset := int(bridge.WORKSPACE_RESULT_HEADER_BYTES)
	member_offset := record_offset + len(state.descriptors) * int(bridge.WORKSPACE_DESCRIPTOR_RECORD_BYTES)
	text_offset := member_offset + len(state.members) * int(bridge.WORKSPACE_MEMBER_RECORD_BYTES)
	text := state.storage[text_offset:]
	for &descriptor, index in state.descriptors {
		values, values_ok := workspace_record_words(state.storage, record_offset + index * 56, 7)
		if !values_ok || values[5] + values[6] > u64(len(state.members)) {
			workspace_batch_state_destroy(state)
			return {}, false
		}
		descriptor.id, values_ok = workspace_text(text, values[0], values[1])
		if !values_ok {
			workspace_batch_state_destroy(state)
			return {}, false
		}
		descriptor.generation = values[2]
		descriptor.name, values_ok = workspace_text(text, values[3], values[4])
		if !values_ok || descriptor.generation == 0 {
			workspace_batch_state_destroy(state)
			return {}, false
		}
		descriptor.member_offset = u32(values[5])
		descriptor.member_count = u32(values[6])
	}
	for &member, index in state.members {
		values, values_ok := workspace_record_words(state.storage, member_offset + index * 104, 13)
		if !values_ok || values[0] >= u64(len(state.descriptors)) || values[1] < 1 || values[1] > 5 {
			workspace_batch_state_destroy(state)
			return {}, false
		}
		member.workspace_index = u32(values[0])
		member.state = Workspace_Member_State(values[1])
		member.project_id = project.Project_ID(values[2])
		member.project_generation = project.Project_Generation(values[3])
		member.durable_id, values_ok = workspace_text(text, values[4], values[5])
		if !values_ok {workspace_batch_state_destroy(state); return {}, false}
		member.name, values_ok = workspace_text(text, values[6], values[7])
		if !values_ok {workspace_batch_state_destroy(state); return {}, false}
		member.root, values_ok = workspace_text(text, values[8], values[9])
		if !values_ok || values[10] > 2 {workspace_batch_state_destroy(state); return {}, false}
		member.trust = project.Trust_State(values[10])
		member.diagnostic, values_ok = workspace_text(text, values[11], values[12])
		if !values_ok {workspace_batch_state_destroy(state); return {}, false}
	}
	diagnostic, diagnostic_ok := workspace_text(text, header_values[8], header_values[9])
	if !diagnostic_ok {
		workspace_batch_state_destroy(state)
		return {}, false
	}
	batch = Workspace_Command_Batch {
		state = state,
		descriptors = state.descriptors,
		members = state.members,
		diagnostic = diagnostic,
		publication = header_values[5],
	}
	return batch, true
}

@(private)
workspace_record_words :: proc(storage: []byte, offset, count: int) -> (values: [13]u64, ok: bool) {
	if count < 0 || count > len(values) || offset < 0 || offset + count * 8 > len(storage) {
		return {}, false
	}
	for index in 0 ..< count {
		values[index], ok = endian.get_u64(storage[offset + index * 8:], .Little)
		if !ok {
			return {}, false
		}
	}
	return values, true
}

@(private)
workspace_text :: proc(storage: []byte, offset, length: u64) -> (string, bool) {
	if offset > u64(len(storage)) || length > u64(len(storage)) - offset {
		return "", false
	}
	return string(storage[int(offset):int(offset + length)]), true
}

@(private)
workspace_batch_state_destroy :: proc(state: ^Workspace_Command_Batch_State) {
	if state == nil {
		return
	}
	allocator := state.allocator
	if state.members != nil {delete(state.members, allocator)}
	if state.descriptors != nil {delete(state.descriptors, allocator)}
	if state.storage != nil {delete(state.storage, allocator)}
	free(state, allocator)
}
