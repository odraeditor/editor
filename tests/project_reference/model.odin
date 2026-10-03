// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package project_reference provides contiguous oracles for Project membership and resolution.
package project_reference

import "base:runtime"
import "core:strings"
import "core:unicode/utf8"

Handle :: struct {
	id:         u64,
	generation: u64,
}

Trust :: enum u8 {
	Untrusted,
	Trusted,
}

Failure_Code :: enum u8 {
	None,
	Invalid_Model,
	Invalid_Handle,
	Capacity,
	Invalid_Path,
	Duplicate_Path,
	Allocation,
}

Failure :: struct {
	code:   Failure_Code,
	handle: Handle,
}

Descriptor :: struct {
	handle: Handle,
	path:   string,
	trust:  Trust,
}

@(private)
Entry :: struct {
	handle: Handle,
	path:   string,
	trust:  Trust,
	live:   bool,
}

Model :: struct {
	entries:    []Entry,
	live_count: int,
	generation: u64,
	allocator:  runtime.Allocator,
}

model_init :: proc(capacity: int, allocator := context.allocator) -> (model: Model, ok: bool) {
	if capacity <= 0 || allocator.procedure == nil {
		return {}, false
	}
	entries, allocation_error := make([]Entry, capacity, allocator)
	if allocation_error != nil {
		return {}, false
	}
	return Model{entries = entries, generation = 1, allocator = allocator}, true
}

model_deinit :: proc(model: ^Model) {
	if model == nil {
		return
	}
	for &entry in model.entries {
		if entry.live && len(entry.path) > 0 {
			delete(entry.path, model.allocator)
		}
	}
	if model.entries != nil {
		delete(model.entries, model.allocator)
	}
	model^ = {}
}

model_add :: proc(
	model: ^Model,
	path: string,
	trust: Trust = .Untrusted,
) -> (handle: Handle, ok: bool, failure: Failure) {
	if !model_ready(model) {
		return {}, false, Failure{code = .Invalid_Model}
	}
	if !path_is_valid(path) {
		return {}, false, Failure{code = .Invalid_Path}
	}
	if model_find_exact(model, path).id != 0 {
		return {}, false, Failure{code = .Duplicate_Path}
	}
	for index in 0 ..< len(model.entries) {
		entry := &model.entries[index]
		if entry.live {
			continue
		}
		owned_path, allocation_error := strings.clone(path, model.allocator)
		if allocation_error != nil {
			return {}, false, Failure{code = .Allocation}
		}
		generation := entry.handle.generation + 1
		if generation == 0 {
			delete(owned_path, model.allocator)
			return {}, false, Failure{code = .Capacity}
		}
		handle = Handle{id = u64(index + 1), generation = generation}
		entry^ = Entry{handle = handle, path = owned_path, trust = trust, live = true}
		model.live_count += 1
		model.generation += 1
		return handle, true, {}
	}
	return {}, false, Failure{code = .Capacity}
}

model_remove :: proc(model: ^Model, handle: Handle) -> (ok: bool, failure: Failure) {
	entry, valid := model_entry(model, handle)
	if !valid {
		return false, Failure{code = .Invalid_Handle, handle = handle}
	}
	delete(entry.path, model.allocator)
	generation := entry.handle.generation
	entry^ = Entry{handle = Handle{generation = generation}}
	model.live_count -= 1
	model.generation += 1
	return true, {}
}

model_set_trust :: proc(
	model: ^Model,
	handle: Handle,
	trust: Trust,
) -> (ok: bool, failure: Failure) {
	entry, valid := model_entry(model, handle)
	if !valid {
		return false, Failure{code = .Invalid_Handle, handle = handle}
	}
	entry.trust = trust
	model.generation += 1
	return true, {}
}

model_find_exact :: proc(model: ^Model, path: string) -> Handle {
	if !model_ready(model) {
		return {}
	}
	for entry in model.entries {
		if entry.live && entry.path == path {
			return entry.handle
		}
	}
	return {}
}

model_containing :: proc(
	model: ^Model,
	path: string,
	results: []Handle,
) -> (count: int, ok: bool) {
	if !model_ready(model) || !path_is_valid(path) {
		return 0, false
	}
	for entry in model.entries {
		if !entry.live || !path_contains(entry.path, path) {
			continue
		}
		if count >= len(results) {
			return count, false
		}
		results[count] = entry.handle
		count += 1
	}
	return count, true
}

model_descriptor :: proc(
	model: ^Model,
	handle: Handle,
) -> (descriptor: Descriptor, ok: bool) {
	entry, valid := model_entry(model, handle)
	if !valid {
		return {}, false
	}
	return Descriptor{handle = entry.handle, path = entry.path, trust = entry.trust}, true
}

model_live_count :: proc(model: ^Model) -> int {
	if !model_ready(model) {
		return 0
	}
	return model.live_count
}

model_generation :: proc(model: ^Model) -> u64 {
	if !model_ready(model) {
		return 0
	}
	return model.generation
}

model_validate :: proc(model: ^Model) -> bool {
	if !model_ready(model) || model.generation == 0 {
		return false
	}
	live_count := 0
	for left_index in 0 ..< len(model.entries) {
		left := model.entries[left_index]
		if !left.live {
			continue
		}
		if !path_is_valid(left.path) || left.handle.id != u64(left_index + 1) ||
		   left.handle.generation == 0 {
			return false
		}
		live_count += 1
		for right_index in left_index + 1 ..< len(model.entries) {
			right := model.entries[right_index]
			if right.live && left.path == right.path {
				return false
			}
		}
	}
	return live_count == model.live_count
}

path_contains :: proc(directory, candidate: string) -> bool {
	if directory == "/" {
		return strings.has_prefix(candidate, "/")
	}
	if candidate == directory {
		return true
	}
	return len(candidate) > len(directory) && strings.has_prefix(candidate, directory) &&
	       candidate[len(directory)] == '/'
}

@(private)
model_ready :: proc(model: ^Model) -> bool {
	return model != nil && model.entries != nil && model.allocator.procedure != nil
}

@(private)
model_entry :: proc(model: ^Model, handle: Handle) -> (^Entry, bool) {
	if !model_ready(model) || handle.id == 0 || handle.generation == 0 ||
	   handle.id > u64(len(model.entries)) {
		return nil, false
	}
	entry := &model.entries[int(handle.id - 1)]
	return entry, entry.live && entry.handle == handle
}

@(private)
path_is_valid :: proc(path: string) -> bool {
	return len(path) > 0 && path[0] == '/' && utf8.valid_string(path) &&
	       strings.index_byte(path, 0) < 0
}
