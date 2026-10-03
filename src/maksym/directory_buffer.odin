// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package maksym

import "../filesystem"
import "base:runtime"
import "core:slice"
import "core:strings"

@(private)
Directory_Buffer_State :: struct {
	batch:             filesystem.Directory_Batch,
	selected_identity: filesystem.Resource_ID,
	has_selection:     bool,
	sort_order:        Sort_Order,
	details:           Details_Mode,
	allocator:         runtime.Allocator,
}

/* directory_buffer_open adopts one complete filesystem observation. */
directory_buffer_open :: proc(
	buffer: ^Directory_Buffer,
	batch: ^filesystem.Directory_Batch,
	allocator := context.allocator,
) -> (bool, Failure_Context) {
	if buffer == nil || batch == nil || batch.state == nil || batch.generation == 0 ||
	   !filesystem.resource_id_valid(batch.directory_identity) ||
	   len(filesystem.normalized_path_text(&batch.directory)) == 0 || allocator.procedure == nil {
		return false, Failure_Context{operation = .Open_Directory_Buffer, code = .Invalid_Arguments}
	}
	if buffer.state != nil {
		return false, Failure_Context{operation = .Open_Directory_Buffer, code = .Already_Open}
	}
	state, allocation_error := new(Directory_Buffer_State, allocator)
	if allocation_error != nil {
		return false, Failure_Context{
			operation = .Open_Directory_Buffer,
			code = .Persistent_Memory_Limit,
		}
	}
	state.batch = batch^
	batch^ = {}
	state.sort_order = .Directories_First
	state.details = .Full
	state.allocator = allocator
	if len(state.batch.descriptors) > 0 {
		state.selected_identity = state.batch.descriptors[0].identity
		state.has_selection = true
	}
	buffer.state = state
	return true, {}
}

/* directory_buffer_view borrows the current complete immutable generation. */
directory_buffer_view :: proc(buffer: ^Directory_Buffer) -> (Directory_View, bool, Failure_Context) {
	state, failure := directory_buffer_resolve(buffer, .Inspect_Directory_Buffer)
	if failure.code != .None do return {}, false, failure
	selected_index := -1
	if state.has_selection {
		selected_index = directory_buffer_find(state, state.selected_identity)
		if selected_index < 0 {
			return {}, false, Failure_Context{
				operation = .Inspect_Directory_Buffer,
				code = .Entry_Not_Found,
				generation = state.batch.generation,
				resource = state.selected_identity,
			}
		}
	}
	return Directory_View {
		directory = filesystem.normalized_path_text(&state.batch.directory),
		directory_identity = state.batch.directory_identity,
		generation = state.batch.generation,
		entries = state.batch.descriptors,
		has_selection = state.has_selection,
		selected_index = selected_index,
		selected_identity = state.selected_identity,
		sort_order = state.sort_order,
		details = state.details,
	}, true, {}
}

/* directory_buffer_select selects one exact resource from the current generation. */
directory_buffer_select :: proc(
	buffer: ^Directory_Buffer,
	identity: filesystem.Resource_ID,
) -> (bool, Failure_Context) {
	state, failure := directory_buffer_resolve(buffer, .Select_Entry)
	if failure.code != .None do return false, failure
	if !filesystem.resource_id_valid(identity) || directory_buffer_find(state, identity) < 0 {
		return false, Failure_Context{
			operation = .Select_Entry,
			code = .Entry_Not_Found,
			generation = state.batch.generation,
			resource = identity,
		}
	}
	state.selected_identity = identity
	state.has_selection = true
	return true, {}
}

/* directory_buffer_move changes selection by one bounded row delta. */
directory_buffer_move :: proc(
	buffer: ^Directory_Buffer,
	delta: i32,
) -> (Movement_Result, bool, Failure_Context) {
	state, failure := directory_buffer_resolve(buffer, .Move_Selection)
	if failure.code != .None do return {}, false, failure
	if !state.has_selection || len(state.batch.descriptors) == 0 || delta == 0 {
		return {}, true, {}
	}
	previous := directory_buffer_find(state, state.selected_identity)
	if previous < 0 {
		return {}, false, Failure_Context{
			operation = .Move_Selection,
			code = .Entry_Not_Found,
			generation = state.batch.generation,
			resource = state.selected_identity,
		}
	}
	next := clamp(previous + int(delta), 0, len(state.batch.descriptors) - 1)
	state.selected_identity = state.batch.descriptors[next].identity
	return Movement_Result {
		previous_index = previous,
		selected_index = next,
		changed = next != previous,
	}, true, {}
}

/* directory_buffer_toggle_details switches between full and simplified projections. */
directory_buffer_toggle_details :: proc(
	buffer: ^Directory_Buffer,
) -> (Details_Mode, bool, Failure_Context) {
	state, failure := directory_buffer_resolve(buffer, .Toggle_Details)
	if failure.code != .None do return .Invalid, false, failure
	state.details = .Simplified if state.details == .Full else .Full
	return state.details, true, {}
}

/* directory_buffer_cycle_sort advances the bounded factory sort policy. */
directory_buffer_cycle_sort :: proc(
	buffer: ^Directory_Buffer,
) -> (Sort_Order, bool, Failure_Context) {
	state, failure := directory_buffer_resolve(buffer, .Cycle_Sort)
	if failure.code != .None do return .Invalid, false, failure
	state.sort_order = .Name if state.sort_order == .Directories_First else .Directories_First
	directory_buffer_sort(state)
	return state.sort_order, true, {}
}

/* directory_buffer_refresh adopts a newer observation of the same directory. */
directory_buffer_refresh :: proc(
	buffer: ^Directory_Buffer,
	batch: ^filesystem.Directory_Batch,
) -> (bool, Failure_Context) {
	state, failure := directory_buffer_resolve(buffer, .Refresh_Directory_Buffer)
	if failure.code != .None do return false, failure
	if batch == nil || batch.state == nil || batch.generation == 0 {
		return false, Failure_Context{operation = .Refresh_Directory_Buffer, code = .Invalid_Arguments}
	}
	if batch.generation <= state.batch.generation {
		return false, Failure_Context{
			operation = .Refresh_Directory_Buffer,
			code = .Invalid_Generation,
			generation = batch.generation,
		}
	}
	if batch.directory_identity != state.batch.directory_identity {
		return false, Failure_Context{
			operation = .Refresh_Directory_Buffer,
			code = .Directory_Changed,
			generation = batch.generation,
			resource = batch.directory_identity,
		}
	}
	selection := state.selected_identity
	has_selection := state.has_selection
	old_batch := state.batch
	state.batch = batch^
	batch^ = {}
	directory_buffer_sort(state)
	state.has_selection = false
	state.selected_identity = {}
	if has_selection && directory_buffer_find(state, selection) >= 0 {
		state.selected_identity = selection
		state.has_selection = true
	} else if len(state.batch.descriptors) > 0 {
		state.selected_identity = state.batch.descriptors[0].identity
		state.has_selection = true
	}
	closed, close_failure := filesystem.directory_batch_close(&old_batch)
	assert(closed && close_failure.code == .None)
	return true, {}
}

@(private)
directory_buffer_sort :: proc(state: ^Directory_Buffer_State) {
	if state == nil do return
	if state.sort_order == .Directories_First {
		slice.sort_by(state.batch.descriptors, proc(left, right: filesystem.Entry_Descriptor) -> bool {
			if left.kind != right.kind do return left.kind == .Directory
			return strings.compare(left.name, right.name) < 0
		})
		return
	}
	slice.sort_by(state.batch.descriptors, proc(left, right: filesystem.Entry_Descriptor) -> bool {
		return strings.compare(left.name, right.name) < 0
	})
}

/* directory_buffer_close releases the owned filesystem generation. */
directory_buffer_close :: proc(buffer: ^Directory_Buffer) -> (bool, Failure_Context) {
	state, failure := directory_buffer_resolve(buffer, .Close_Directory_Buffer)
	if failure.code != .None do return false, failure
	closed, filesystem_failure := filesystem.directory_batch_close(&state.batch)
	if !closed {
		return false, Failure_Context{
			operation = .Close_Directory_Buffer,
			code = .Filesystem_Failure,
			generation = state.batch.generation,
			filesystem_failure = filesystem_failure,
		}
	}
	allocator := state.allocator
	free(state, allocator)
	buffer.state = nil
	return true, {}
}

@(private)
directory_buffer_resolve :: proc(
	buffer: ^Directory_Buffer,
	operation: Operation,
) -> (^Directory_Buffer_State, Failure_Context) {
	if buffer == nil || buffer.state == nil {
		return nil, Failure_Context{operation = operation, code = .Closed_Buffer}
	}
	return cast(^Directory_Buffer_State)buffer.state, {}
}

@(private)
directory_buffer_find :: proc(state: ^Directory_Buffer_State, identity: filesystem.Resource_ID) -> int {
	if state == nil || !filesystem.resource_id_valid(identity) do return -1
	for descriptor, index in state.batch.descriptors {
		if descriptor.identity == identity do return index
	}
	return -1
}
