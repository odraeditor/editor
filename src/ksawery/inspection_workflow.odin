// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"
import "core:bytes"
import "core:strings"

@(private)
Inspection_Observation_Data :: struct {
	descriptor: Inspection_Observation_Descriptor,
	items:      [dynamic]Inspection_Item,
	detail:     [dynamic]u8,
	allocator:  runtime.Allocator,
}

/* repository_process_take_inspection_observation parses one completed family observation. */
repository_process_take_inspection_observation :: proc(
	process: ^Repository_Process,
	generation: Inspection_Generation,
	allocator := context.allocator,
) -> (Inspection_Observation, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || state.request.kind != .Inspection_Workflow ||
	   state.state != .Completed || generation == Inspection_Generation(0) {
		return {}, false, .Invalid_Request
	}
	request := state.request.inspection_workflow
	if request.action != .List && request.action != .Inspect && request.action != .Visit {
		return {}, false, .Invalid_Request
	}
	return inspection_observation_open(request, generation, state.output[:], allocator)
}

/* inspection_observation_open parses one bounded immutable family observation. */
inspection_observation_open :: proc(
	request: Inspection_Request,
	generation: Inspection_Generation,
	output: []u8,
	allocator := context.allocator,
) -> (Inspection_Observation, bool, Failure_Code) {
	if allocator.procedure == nil || !inspection_request_is_valid(request) ||
	   generation == Inspection_Generation(0) || u64(len(output)) > MAX_INSPECTION_OUTPUT_BYTES {
		return {}, false, .Invalid_Request
	}
	state, allocation_error := new(Inspection_Observation_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.descriptor = {
		repository = request.repository,
		status_generation = request.observation_generation,
		generation = generation,
		family = request.family,
		retained_bytes = u64(len(output)),
	}
	state.items, allocation_error = make([dynamic]Inspection_Item, 0, 32, allocator)
	if allocation_error != nil {
		inspection_observation_data_destroy(state)
		return {}, false, .Allocation
	}
	failure := inspection_observation_parse(state, request, output)
	if failure != .None {
		inspection_observation_data_destroy(state)
		return {}, false, failure
	}
	state.descriptor.item_count = u32(len(state.items))
	return Inspection_Observation{state = state}, true, .None
}

/* inspection_observation_descriptor returns copied immutable family metadata. */
inspection_observation_descriptor :: proc(
	observation: ^Inspection_Observation,
) -> (Inspection_Observation_Descriptor, bool) {
	state := inspection_observation_data(observation)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* inspection_observation_item returns one copied semantic family item. */
inspection_observation_item :: proc(
	observation: ^Inspection_Observation,
	index: u32,
) -> (Inspection_Item, bool) {
	state := inspection_observation_data(observation)
	if state == nil || index >= u32(len(state.items)) do return {}, false
	return state.items[int(index)], true
}

/* inspection_observation_target resolves one exact selectable item. */
inspection_observation_target :: proc(
	observation: ^Inspection_Observation,
	index: u32,
) -> (Inspection_Target, bool) {
	state := inspection_observation_data(observation)
	if state == nil || index >= u32(len(state.items)) do return {}, false
	item := state.items[int(index)]
	return {
		generation = state.descriptor.generation,
		item = item.id,
		identity = item.identity,
	}, true
}

/* inspection_request_revalidate binds one follow-up action to exact retained family evidence. */
inspection_request_revalidate :: proc(
	observation: ^Inspection_Observation,
	request: Inspection_Request,
) -> (bool, Failure_Code) {
	if !inspection_request_is_valid(request) do return false, .Invalid_Request
	if request.family_generation == Inspection_Generation(0) do return true, .None
	state := inspection_observation_data(observation)
	if state == nil || state.descriptor.repository != request.repository ||
	   state.descriptor.status_generation != request.observation_generation ||
	   state.descriptor.generation != request.family_generation ||
	   state.descriptor.family != request.family {
		return false, .Stale_Observation
	}
	if request.action == .Create || request.action == .Prune do return true, .None
	for item in state.items {
		if item.identity == request.target &&
		   ((request.family != .Stash && request.family != .Worktree) ||
		    item.secondary == request.evidence) {
			return true, .None
		}
	}
	return false, .Stale_Observation
}

/* inspection_observation_detail returns borrowed bounded detail output. */
inspection_observation_detail :: proc(
	observation: ^Inspection_Observation,
) -> ([]u8, bool) {
	state := inspection_observation_data(observation)
	if state == nil || len(state.detail) == 0 do return nil, false
	return state.detail[:], true
}

/* inspection_observation_close releases one owned family observation. */
inspection_observation_close :: proc(observation: ^Inspection_Observation) {
	if observation == nil do return
	state := inspection_observation_data(observation)
	if state != nil do inspection_observation_data_destroy(state)
	observation^ = {}
}

@(private)
inspection_observation_parse :: proc(
	state: ^Inspection_Observation_Data,
	request: Inspection_Request,
	output: []u8,
) -> Failure_Code {
	owned_request := request
	switch request.family {
	case .Stash, .Reflog:
		if request.action == .Inspect || request.action == .Visit {
			failure := inspection_observation_append_item(
				state,
				inspection_text_string(&owned_request.target),
				"Inspection",
				"",
			)
			if failure != .None do return failure
			return inspection_observation_copy_detail(state, output)
		}
		return inspection_observation_parse_triplets(state, output)
	case .Worktree:
		if request.action == .Visit {
			text := strings.trim_space(string(output))
			return inspection_observation_append_item(state, text, "Worktree", "")
		}
		return inspection_observation_parse_worktrees(state, output)
	case .Blame:
		if request.action == .Visit {
			failure := inspection_observation_append_item(
				state,
				inspection_text_string(&owned_request.target),
				"Revision",
				"",
			)
			if failure != .None do return failure
			return inspection_observation_copy_detail(state, output)
		}
		return inspection_observation_parse_blame(state, output)
	case .Invalid:
		return .Invalid_Request
	}
	return .Invalid_Request
}

@(private)
inspection_observation_copy_detail :: proc(
	state: ^Inspection_Observation_Data,
	output: []u8,
) -> Failure_Code {
	if state == nil || len(output) == 0 do return .Parse
	detail, allocation_error := make([dynamic]u8, len(output), state.allocator)
	if allocation_error != nil do return .Allocation
	state.detail = detail
	copy(state.detail[:], output)
	return .None
}

@(private)
inspection_observation_parse_triplets :: proc(
	state: ^Inspection_Observation_Data,
	output: []u8,
) -> Failure_Code {
	fields := bytes.split(output, []u8{0})
	defer delete(fields)
	for index := 0; index + 2 < len(fields); index += 3 {
		identity := strings.trim_space(string(fields[index]))
		secondary := strings.trim_space(string(fields[index + 1]))
		summary := strings.trim_space(string(fields[index + 2]))
		if len(identity) == 0 && len(secondary) == 0 && len(summary) == 0 do continue
		if failure := inspection_observation_append_item(state, identity, summary, secondary);
		   failure != .None {
			return failure
		}
	}
	return .None
}

@(private)
inspection_observation_parse_worktrees :: proc(
	state: ^Inspection_Observation_Data,
	output: []u8,
) -> Failure_Code {
	fields := bytes.split(output, []u8{0})
	defer delete(fields)
	path := ""
	head := ""
	branch := ""
	for field in fields {
		line := strings.trim_space(string(field))
		if len(line) == 0 {
			if failure := inspection_observation_append_worktree(state, path, head, branch);
			   failure != .None {
				return failure
			}
			path, head, branch = "", "", ""
			continue
		}
		if strings.has_prefix(line, "worktree ") {
			if len(path) > 0 {
				if failure := inspection_observation_append_worktree(state, path, head, branch);
				   failure != .None {
					return failure
				}
				path, head, branch = "", "", ""
			}
			path = line[len("worktree "):]
		} else if strings.has_prefix(line, "HEAD ") {
			head = line[len("HEAD "):]
		} else if strings.has_prefix(line, "branch ") {
			branch = line[len("branch "):]
		}
	}
	return inspection_observation_append_worktree(state, path, head, branch)
}

@(private)
inspection_observation_append_worktree :: proc(
	state: ^Inspection_Observation_Data,
	path, head, branch: string,
) -> Failure_Code {
	if len(path) == 0 do return .None
	summary := branch
	if len(summary) == 0 do summary = "detached"
	return inspection_observation_append_item(state, path, summary, head)
}

@(private)
inspection_observation_parse_blame :: proc(
	state: ^Inspection_Observation_Data,
	output: []u8,
) -> Failure_Code {
	lines := bytes.split(output, []u8{'\n'})
	defer delete(lines)
	identity := ""
	location := ""
	for line in lines {
		text := string(line)
		if len(text) > 0 && text[0] == '\t' && len(identity) > 0 {
			if failure := inspection_observation_append_item(state, identity, location, text[1:]);
			   failure != .None {
				return failure
			}
			identity, location = "", ""
			continue
		}
		first_space := strings.index_byte(text, ' ')
		if first_space != 40 && first_space != 64 do continue
		candidate := text[:first_space]
		if !revision_identity_text_is_valid(candidate) do continue
		identity = candidate
		location = strings.trim_space(text[first_space + 1:])
	}
	return .None
}

@(private)
inspection_observation_append_item :: proc(
	state: ^Inspection_Observation_Data,
	identity, summary, secondary: string,
) -> Failure_Code {
	if state == nil || len(state.items) >= int(MAX_INSPECTION_ITEMS) || len(identity) == 0 {
		return .Output_Limit
	}
	item := Inspection_Item{id = Inspection_Item_ID(len(state.items) + 1)}
	if !inspection_text_assign(&item.identity, identity) ||
	   (len(summary) > 0 && !inspection_text_assign(&item.summary, summary)) ||
	   (len(secondary) > 0 && !inspection_text_assign(&item.secondary, secondary)) {
		return .Parse
	}
	if _, append_error := append(&state.items, item); append_error != nil do return .Allocation
	return .None
}

@(private)
inspection_observation_data :: proc(observation: ^Inspection_Observation) -> ^Inspection_Observation_Data {
	if observation == nil || observation.state == nil do return nil
	return cast(^Inspection_Observation_Data)observation.state
}

@(private)
inspection_observation_data_destroy :: proc(state: ^Inspection_Observation_Data) {
	if state == nil do return
	if state.items != nil do delete(state.items)
	if state.detail != nil do delete(state.detail)
	allocator := state.allocator
	free(state, allocator)
}
