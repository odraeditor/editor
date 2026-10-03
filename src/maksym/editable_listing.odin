// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package maksym

import "../filesystem"
import "base:runtime"
import "core:strings"
import "core:unicode/utf8"

@(private)
Editable_Listing_State :: struct {
	directory_identity: filesystem.Resource_ID,
	generation:         u64,
	names:              []Editable_Name,
	header_storage:     string,
	name_storage:       []string,
	prefix_storage:     []string,
	allocator:          runtime.Allocator,
}

@(private)
Rename_Plan_State :: struct {
	directory_identity: filesystem.Resource_ID,
	generation:         u64,
	changes:            []Rename_Change,
	storage:            []string,
	allocator:          runtime.Allocator,
}

/* editable_listing_open retains one immutable name baseline from a projection. */
editable_listing_open :: proc(
	listing: ^Editable_Listing,
	projection: Projection_View,
	allocator := context.allocator,
) -> (bool, Failure_Context) {
	if listing == nil || listing.state != nil || allocator.procedure == nil ||
	   projection.generation == 0 || projection.header_end == 0 ||
	   projection.header_end > u64(len(projection.text)) ||
	   !filesystem.resource_id_valid(projection.directory_identity) {
		return false, Failure_Context{operation = .Open_Editable_Listing, code = .Invalid_Arguments}
	}
	state, state_error := new(Editable_Listing_State, allocator)
	if state_error != nil {
		return false, Failure_Context{operation = .Open_Editable_Listing, code = .Persistent_Memory_Limit}
	}
	state.allocator = allocator
	state.directory_identity = projection.directory_identity
	state.generation = projection.generation
	state.header_storage, state_error = strings.clone(
		projection.text[:projection.header_end],
		allocator,
	)
	if state_error != nil {
		editable_listing_state_release(state)
		return false, Failure_Context{operation = .Open_Editable_Listing, code = .Persistent_Memory_Limit}
	}
	state.names, state_error = make([]Editable_Name, len(projection.rows), allocator)
	if state_error != nil {
		editable_listing_state_release(state)
		return false, Failure_Context{operation = .Open_Editable_Listing, code = .Persistent_Memory_Limit}
	}
	state.name_storage, state_error = make([]string, len(projection.rows), allocator)
	if state_error != nil {
		editable_listing_state_release(state)
		return false, Failure_Context{operation = .Open_Editable_Listing, code = .Persistent_Memory_Limit}
	}
	state.prefix_storage, state_error = make([]string, len(projection.rows), allocator)
	if state_error != nil {
		editable_listing_state_release(state)
		return false, Failure_Context{operation = .Open_Editable_Listing, code = .Persistent_Memory_Limit}
	}
	for row, index in projection.rows {
		if row.row_start > row.name_start || row.name_end <= row.name_start ||
		   row.name_end > row.row_end || row.row_end > u64(len(projection.text)) ||
		   !filesystem.resource_id_valid(row.identity) {
			editable_listing_state_release(state)
			return false, Failure_Context{operation = .Open_Editable_Listing, code = .Invalid_Arguments}
		}
		prefix, prefix_error := strings.clone(
			projection.text[row.row_start:row.name_start],
			allocator,
		)
		if prefix_error != nil {
			editable_listing_state_release(state)
			return false, Failure_Context{operation = .Open_Editable_Listing, code = .Persistent_Memory_Limit}
		}
		name, copy_error := strings.clone(projection.text[row.name_start:row.name_end], allocator)
		if copy_error != nil {
			if len(prefix) > 0 do delete(prefix, allocator)
			editable_listing_state_release(state)
			return false, Failure_Context{operation = .Open_Editable_Listing, code = .Persistent_Memory_Limit}
		}
		state.prefix_storage[index] = prefix
		state.name_storage[index] = name
		state.names[index] = {
			identity = row.identity,
			kind = row.kind,
			name = name,
			prefix_bytes = u64(len(prefix)),
		}
	}
	listing.state = state
	return true, {}
}

/* editable_listing_view borrows one immutable filename baseline. */
editable_listing_view :: proc(listing: ^Editable_Listing) -> (Editable_Listing_View, bool, Failure_Context) {
	if listing == nil || listing.state == nil {
		return {}, false, Failure_Context{operation = .Inspect_Editable_Listing, code = .Closed_Buffer}
	}
	state := cast(^Editable_Listing_State)listing.state
	return {
		directory_identity = state.directory_identity,
		generation = state.generation,
		header_bytes = u64(len(state.header_storage)),
		names = state.names,
	}, true, {}
}

/* editable_listing_calculate derives a complete checked rename plan from edited text. */
editable_listing_calculate :: proc(
	listing: ^Editable_Listing,
	edited: string,
	plan: ^Rename_Plan,
) -> (bool, Failure_Context) {
	if listing == nil || listing.state == nil || plan == nil || plan.state != nil || !utf8.valid_string(edited) {
		return false, Failure_Context{operation = .Calculate_Renames, code = .Invalid_Editable_Projection}
	}
	baseline := cast(^Editable_Listing_State)listing.state
	if !strings.has_prefix(edited, baseline.header_storage) {
		return false, Failure_Context{operation = .Calculate_Renames, code = .Invalid_Editable_Projection}
	}
	line_count := 0
	for byte in transmute([]u8)edited[len(baseline.header_storage):] do if byte == '\n' do line_count += 1
	if line_count != len(baseline.names) || (len(edited) > 0 && edited[len(edited) - 1] != '\n') {
		return false, Failure_Context{operation = .Calculate_Renames, code = .Invalid_Editable_Projection}
	}
	state, state_error := new(Rename_Plan_State, baseline.allocator)
	if state_error != nil {
		return false, Failure_Context{operation = .Calculate_Renames, code = .Persistent_Memory_Limit}
	}
	state.allocator = baseline.allocator
	state.directory_identity = baseline.directory_identity
	state.generation = baseline.generation
	state.changes, state_error = make([]Rename_Change, len(baseline.names), baseline.allocator)
	if state_error != nil {
		rename_plan_state_release(state)
		return false, Failure_Context{operation = .Calculate_Renames, code = .Persistent_Memory_Limit}
	}
	state.storage, state_error = make([]string, len(baseline.names), baseline.allocator)
	if state_error != nil {
		rename_plan_state_release(state)
		return false, Failure_Context{operation = .Calculate_Renames, code = .Persistent_Memory_Limit}
	}
	start := len(baseline.header_storage)
	change_count := 0
	for original, index in baseline.names {
		newline := strings.index_byte(edited[start:], '\n')
		if newline < 0 {
			rename_plan_state_release(state)
			return false, Failure_Context{operation = .Calculate_Renames, code = .Invalid_Editable_Projection}
		}
		end := start + newline
		prefix := baseline.prefix_storage[index]
		if len(edited[start:end]) < len(prefix) || !strings.has_prefix(edited[start:end], prefix) {
			rename_plan_state_release(state)
			return false, Failure_Context{operation = .Calculate_Renames, code = .Invalid_Editable_Projection}
		}
		name_start := start + len(prefix)
		name_end := end
		if original.kind == .Directory {
			if name_end <= name_start || edited[name_end - 1] != '/' {
				rename_plan_state_release(state)
				return false, Failure_Context{operation = .Calculate_Renames, code = .Invalid_Editable_Projection}
			}
			name_end -= 1
		}
		name := edited[name_start:name_end]
		if !editable_destination_valid(name) {
			rename_plan_state_release(state)
			return false, Failure_Context{operation = .Calculate_Renames, code = .Invalid_Name}
		}
		for prior_start in 0 ..< index {
			prior := state.storage[prior_start]
			if len(name) > 0 && len(prior) > 0 && prior == name {
				rename_plan_state_release(state)
				return false, Failure_Context{operation = .Calculate_Renames, code = .Duplicate_Destination}
			}
		}
		copied, copy_error := strings.clone(name, baseline.allocator)
		if copy_error != nil {
			rename_plan_state_release(state)
			return false, Failure_Context{operation = .Calculate_Renames, code = .Persistent_Memory_Limit}
		}
		state.storage[index] = copied
		if copied != original.name {
			kind := Change_Kind.Rename
			if len(copied) == 0 {
				kind = .Delete
			} else if strings.contains(copied, "/") {
				kind = .Move
			}
			state.changes[change_count] = {
				identity = original.identity,
				kind = kind,
				entry_kind = original.kind,
				from = original.name,
				to = copied,
				destructive = kind == .Delete,
				recovery_available = false,
			}
			change_count += 1
		}
		start = end + 1
	}
	state.changes = state.changes[:change_count]
	plan.state = state
	return true, {}
}

/* rename_plan_view borrows one complete calculated rename batch. */
rename_plan_view :: proc(plan: ^Rename_Plan) -> (Rename_Plan_View, bool, Failure_Context) {
	if plan == nil || plan.state == nil {
		return {}, false, Failure_Context{operation = .Calculate_Renames, code = .Invalid_Arguments}
	}
	state := cast(^Rename_Plan_State)plan.state
	return {directory_identity = state.directory_identity, generation = state.generation, changes = state.changes}, true, {}
}

rename_plan_close :: proc(plan: ^Rename_Plan) -> (bool, Failure_Context) {
	if plan == nil || plan.state == nil {
		return false, Failure_Context{operation = .Close_Rename_Plan, code = .Invalid_Arguments}
	}
	rename_plan_state_release(cast(^Rename_Plan_State)plan.state)
	plan.state = nil
	return true, {}
}

editable_listing_close :: proc(listing: ^Editable_Listing) -> (bool, Failure_Context) {
	if listing == nil || listing.state == nil {
		return false, Failure_Context{operation = .Close_Editable_Listing, code = .Invalid_Arguments}
	}
	editable_listing_state_release(cast(^Editable_Listing_State)listing.state)
	listing.state = nil
	return true, {}
}

@(private)
editable_destination_valid :: proc(name: string) -> bool {
	if len(name) == 0 do return true
	if len(name) > int(filesystem.MAX_PATH_BYTES) || !utf8.valid_string(name) ||
	   strings.index_byte(name, 0) >= 0 || name[0] == '/' {
		return false
	}
	segment_start := 0
	for byte, index in transmute([]u8)name {
		if byte != '/' do continue
		if !editable_destination_segment_valid(name[segment_start:index]) do return false
		segment_start = index + 1
	}
	return editable_destination_segment_valid(name[segment_start:])
}

@(private)
editable_destination_segment_valid :: proc(segment: string) -> bool {
	return len(segment) > 0 && segment != "." && segment != ".."
}

@(private)
editable_listing_state_release :: proc(state: ^Editable_Listing_State) {
	if state == nil do return
	allocator := state.allocator
	if len(state.header_storage) > 0 do delete(state.header_storage, allocator)
	for value in state.name_storage do if len(value) > 0 do delete(value, allocator)
	for value in state.prefix_storage do if len(value) > 0 do delete(value, allocator)
	delete(state.name_storage, allocator)
	delete(state.prefix_storage, allocator)
	delete(state.names, allocator)
	free(state, allocator)
}

@(private)
rename_plan_state_release :: proc(state: ^Rename_Plan_State) {
	if state == nil do return
	allocator := state.allocator
	for value in state.storage do if len(value) > 0 do delete(value, allocator)
	delete(state.storage, allocator)
	delete(state.changes, allocator)
	free(state, allocator)
}
