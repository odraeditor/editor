// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package maksym

import "../filesystem"
import "base:runtime"
import "core:fmt"
import "core:time"

@(private)
MAKSYM_PERMISSION_BYTES :: 10
@(private)
MAKSYM_SIZE_BYTES :: 16
@(private)
MAKSYM_MODIFIED_BYTES :: 11

@(private)
Projection_State :: struct {
	directory_identity: filesystem.Resource_ID,
	generation:         u64,
	text:               string,
	header_end:         u64,
	rows:               []Projection_Row,
	has_selection:      bool,
	selected_index:     int,
	allocator:          runtime.Allocator,
}

/* projection_build creates one complete immutable textual rendering. */
projection_build :: proc(
	projection: ^Projection,
	directory: Directory_View,
	config: Projection_Config,
) -> (bool, Failure_Context) {
	if projection == nil || projection.state != nil || directory.generation == 0 ||
	   len(directory.directory) == 0 ||
	   !filesystem.resource_id_valid(directory.directory_identity) ||
	   config.allocator.procedure == nil || config.text_bytes == 0 ||
	   config.text_bytes > MAX_PROJECTION_BYTES ||
	   (directory.has_selection &&
	   (directory.selected_index < 0 || directory.selected_index >= len(directory.entries))) {
		return false, Failure_Context{operation = .Build_Projection, code = .Invalid_Arguments}
	}
	header_bytes := u64(len(directory.directory) + 2)
	if header_bytes > config.text_bytes {
		return false, Failure_Context{
			operation = .Build_Projection,
			code = .Projection_Limit,
			generation = directory.generation,
		}
	}
	text_bytes := header_bytes
	permission_storage: [MAKSYM_PERMISSION_BYTES]u8
	size_storage: [MAKSYM_SIZE_BYTES]u8
	modified_storage: [MAKSYM_MODIFIED_BYTES]u8
	for entry in directory.entries {
		if !filesystem.resource_id_valid(entry.identity) || len(entry.name) == 0 ||
		   entry.kind == .Invalid {
			return false, Failure_Context{operation = .Build_Projection, code = .Invalid_Arguments}
		}
		metadata_bytes := u64(0)
		if directory.details == .Full {
			permissions := projection_permission_text(entry, permission_storage[:])
			size := projection_size_text(entry.size_bytes, size_storage[:])
			modified := projection_modified_text(entry.modified_seconds, modified_storage[:])
			if len(permissions) == 0 || len(size) == 0 || len(modified) == 0 {
				return false, Failure_Context{operation = .Build_Projection, code = .Invalid_Arguments}
			}
			metadata_bytes = u64(len(permissions) + 2 + MAKSYM_SIZE_BYTES + 2 + len(modified) + 2)
		}
		suffix_bytes := u64(2) if entry.kind == .Directory else u64(1)
		if u64(len(entry.name)) > config.text_bytes - min(text_bytes, config.text_bytes) ||
		   metadata_bytes > config.text_bytes - min(text_bytes, config.text_bytes) ||
		   suffix_bytes > config.text_bytes - min(text_bytes + metadata_bytes + u64(len(entry.name)), config.text_bytes) {
			return false, Failure_Context{
				operation = .Build_Projection,
				code = .Projection_Limit,
				generation = directory.generation,
			}
		}
		text_bytes += metadata_bytes + u64(len(entry.name)) + suffix_bytes
	}
	state, state_error := new(Projection_State, config.allocator)
	if state_error != nil {
		return false, Failure_Context{operation = .Build_Projection, code = .Persistent_Memory_Limit}
	}
	state.allocator = config.allocator
	text_storage, text_error := make([]u8, int(text_bytes), config.allocator)
	if text_error != nil {
		projection_state_release(state)
		return false, Failure_Context{operation = .Build_Projection, code = .Persistent_Memory_Limit}
	}
	state.text = string(text_storage)
	state.rows, state_error = make([]Projection_Row, len(directory.entries), config.allocator)
	if state_error != nil {
		projection_state_release(state)
		return false, Failure_Context{operation = .Build_Projection, code = .Persistent_Memory_Limit}
	}
	offset := copy(text_storage, transmute([]u8)directory.directory)
	text_storage[offset] = ':'
	offset += 1
	text_storage[offset] = '\n'
	offset += 1
	state.header_end = u64(offset)
	for entry, index in directory.entries {
		row_start := offset
		if directory.details == .Full {
			permissions := projection_permission_text(entry, permission_storage[:])
			size := projection_size_text(entry.size_bytes, size_storage[:])
			modified := projection_modified_text(entry.modified_seconds, modified_storage[:])
			offset += copy(text_storage[offset:], transmute([]u8)permissions)
			offset += copy(text_storage[offset:], "  ")
			for _ in 0 ..< MAKSYM_SIZE_BYTES - len(size) {
				text_storage[offset] = ' '
				offset += 1
			}
			offset += copy(text_storage[offset:], transmute([]u8)size)
			offset += copy(text_storage[offset:], "  ")
			offset += copy(text_storage[offset:], transmute([]u8)modified)
			offset += copy(text_storage[offset:], "  ")
		}
		name_start := offset
		offset += copy(text_storage[offset:], transmute([]u8)entry.name)
		name_end := offset
		if entry.kind == .Directory {
			text_storage[offset] = '/'
			offset += 1
		}
		text_storage[offset] = '\n'
		offset += 1
		state.rows[index] = Projection_Row {
			identity = entry.identity,
			kind = entry.kind,
			line_index = u64(index + 1),
			row_start = u64(row_start),
			name_start = u64(name_start),
			name_end = u64(name_end),
			row_end = u64(offset),
		}
	}
	state.directory_identity = directory.directory_identity
	state.generation = directory.generation
	state.has_selection = directory.has_selection
	state.selected_index = directory.selected_index
	projection.state = state
	return true, {}
}

@(private)
projection_permission_text :: proc(entry: filesystem.Entry_Descriptor, output: []u8) -> string {
	if len(output) < MAKSYM_PERMISSION_BYTES do return ""
	output[0] = 'd' if entry.kind == .Directory else '-'
	flags := [9]u32{8, 7, 6, 5, 4, 3, 2, 1, 0}
	marks := [3]u8{'r', 'w', 'x'}
	for flag, index in flags {
		output[index + 1] = marks[index % 3] if entry.permissions & (u32(1) << flag) != 0 else '-'
	}
	return string(output[:MAKSYM_PERMISSION_BYTES])
}

@(private)
projection_size_text :: proc(size_bytes: i64, output: []u8) -> string {
	if size_bytes < 0 || len(output) < MAKSYM_SIZE_BYTES do return ""
	bytes := u64(size_bytes)
	if bytes < 1_024 do return fmt.bprintf(output, "%d B", bytes)
	units := [5]string{"KiB", "MiB", "GiB", "TiB", "PiB"}
	value := bytes
	unit := 0
	for value >= 1_024 && unit < len(units) - 1 {
		value = (value + 512) / 1_024
		unit += 1
	}
	return fmt.bprintf(output, "%d %s", value, units[unit - 1])
}

@(private)
projection_modified_text :: proc(modified_seconds: i64, output: []u8) -> string {
	if len(output) < MAKSYM_MODIFIED_BYTES do return ""
	modified := time.unix(modified_seconds, 0)
	year, month, day := time.date(modified)
	if month < .January || month > .December do return ""
	return fmt.bprintf(output, "%04d-%02d-%02d", year, int(month), day)
}

/* projection_view borrows one complete immutable rendering. */
projection_view :: proc(projection: ^Projection) -> (Projection_View, bool, Failure_Context) {
	if projection == nil || projection.state == nil {
		return {}, false, Failure_Context{operation = .Inspect_Projection, code = .Closed_Buffer}
	}
	state := cast(^Projection_State)projection.state
	return Projection_View {
		directory_identity = state.directory_identity,
		generation = state.generation,
		text = state.text,
		header_end = state.header_end,
		rows = state.rows,
		has_selection = state.has_selection,
		selected_index = state.selected_index,
	}, true, {}
}

/* projection_close releases one immutable rendering. */
projection_close :: proc(projection: ^Projection) -> (bool, Failure_Context) {
	if projection == nil || projection.state == nil {
		return false, Failure_Context{operation = .Close_Projection, code = .Closed_Buffer}
	}
	projection_state_release(cast(^Projection_State)projection.state)
	projection.state = nil
	return true, {}
}

@(private)
projection_state_release :: proc(state: ^Projection_State) {
	if state == nil do return
	allocator := state.allocator
	delete(state.rows, allocator)
	delete(state.text, allocator)
	free(state, allocator)
}
