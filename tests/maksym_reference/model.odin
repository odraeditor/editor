// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package maksym_reference provides an independent oracle for directory projections.
package maksym_reference

import "core:strings"
import "core:unicode/utf8"

MAX_ENTRIES :: 16
MAX_NAME_BYTES :: 64

Resource_ID :: struct {
	provider: u64,
	scope:    u64,
	object:   u64,
}

Kind :: enum u8 {
	Invalid,
	Directory,
	Regular_File,
}

Sort_Order :: enum u8 {
	Invalid,
	Directories_First,
	Name,
}

Failure_Code :: enum u8 {
	None,
	Invalid_Model,
	Invalid_Generation,
	Invalid_Entry,
	Duplicate_Identity,
	Entry_Limit,
	Invalid_Editable_Projection,
	Duplicate_Destination,
}

Rename :: struct {
	resource: Resource_ID,
	kind:     Change_Kind,
	from:     string,
	to:       string,
}

Change_Kind :: enum u8 {
	Invalid,
	Rename,
	Move,
	Delete,
}

Entry :: struct {
	resource: Resource_ID,
	name:     string,
	kind:     Kind,
}

Definition :: struct {
	resource: Resource_ID,
	name:     string,
	kind:     Kind,
}

Model :: struct {
	entries:       [MAX_ENTRIES]Entry,
	count:         int,
	generation:    u64,
	sort_order:    Sort_Order,
	selected:      Resource_ID,
	has_selection: bool,
}

model_init :: proc(sort_order := Sort_Order.Directories_First) -> (Model, bool) {
	if sort_order == .Invalid {
		return {}, false
	}
	return Model{sort_order = sort_order}, true
}

model_close :: proc(model: ^Model) {
	if model != nil {
		model^ = {}
	}
}

model_publish :: proc(
	model: ^Model,
	generation: u64,
	definitions: []Definition,
) -> (bool, Failure_Code) {
	if !model_ready(model) {
		return false, .Invalid_Model
	}
	if generation == 0 || generation <= model.generation {
		return false, .Invalid_Generation
	}
	if len(definitions) > MAX_ENTRIES {
		return false, .Entry_Limit
	}
	candidate := model^
	candidate.count = 0
	candidate.generation = generation
	for definition, index in definitions {
		if !definition_valid(definition) {
			return false, .Invalid_Entry
		}
		for previous in definitions[:index] {
			if previous.resource == definition.resource {
				return false, .Duplicate_Identity
			}
		}
		candidate.entries[candidate.count] = Entry {
			resource = definition.resource,
			name = definition.name,
			kind = definition.kind,
		}
		candidate.count += 1
	}
	for index in candidate.count ..< MAX_ENTRIES {
		candidate.entries[index] = {}
	}
	model_sort(&candidate)
	if candidate.has_selection && model_find(&candidate, candidate.selected) < 0 {
		candidate.has_selection = false
		candidate.selected = {}
	}
	if !candidate.has_selection && candidate.count > 0 {
		candidate.selected = candidate.entries[0].resource
		candidate.has_selection = true
	}
	if candidate.count == 0 {
		candidate.selected = {}
		candidate.has_selection = false
	}
	if !model_validate(&candidate) {
		return false, .Invalid_Model
	}
	model^ = candidate
	return true, .None
}

model_select :: proc(model: ^Model, resource: Resource_ID) -> bool {
	if !model_validate(model) || model_find(model, resource) < 0 {
		return false
	}
	model.selected = resource
	model.has_selection = true
	return true
}

model_move :: proc(model: ^Model, delta: int) -> bool {
	if !model_validate(model) || !model.has_selection || delta == 0 {
		return false
	}
	current := model_find(model, model.selected)
	next := current + delta
	if current < 0 || next < 0 || next >= model.count {
		return false
	}
	model.selected = model.entries[next].resource
	return true
}

model_selected :: proc(model: ^Model) -> (Entry, bool) {
	if !model_validate(model) || !model.has_selection {
		return {}, false
	}
	index := model_find(model, model.selected)
	if index < 0 {
		return {}, false
	}
	return model.entries[index], true
}

model_validate :: proc(model: ^Model) -> bool {
	if !model_ready(model) || model.count < 0 || model.count > MAX_ENTRIES {
		return false
	}
	if model.generation == 0 {
		return model.count == 0 && !model.has_selection && model.selected == Resource_ID{}
	}
	for entry, index in model.entries[:model.count] {
		if !entry_valid(entry) {
			return false
		}
		for previous in model.entries[:index] {
			if previous.resource == entry.resource {
				return false
			}
		}
		if index > 0 && entry_less(model, entry, model.entries[index - 1]) {
			return false
		}
	}
	if model.count == 0 {
		return !model.has_selection && model.selected == Resource_ID{}
	}
	return model.has_selection && model_find(model, model.selected) >= 0
}

@(private)
model_ready :: proc(model: ^Model) -> bool {
	return model != nil && model.sort_order != .Invalid
}

@(private)
model_find :: proc(model: ^Model, resource: Resource_ID) -> int {
	if model == nil {
		return -1
	}
	for entry, index in model.entries[:model.count] {
		if entry.resource == resource {
			return index
		}
	}
	return -1
}

@(private)
model_sort :: proc(model: ^Model) {
	for index in 1 ..< model.count {
		cursor := index
		for cursor > 0 && entry_less(model, model.entries[cursor], model.entries[cursor - 1]) {
			model.entries[cursor], model.entries[cursor - 1] =
				model.entries[cursor - 1], model.entries[cursor]
			cursor -= 1
		}
	}
}

@(private)
entry_less :: proc(model: ^Model, left, right: Entry) -> bool {
	if model.sort_order == .Directories_First && left.kind != right.kind {
		return left.kind == .Directory
	}
	comparison := strings.compare(left.name, right.name)
	if comparison != 0 {
		return comparison < 0
	}
	if left.kind != right.kind {
		return left.kind < right.kind
	}
	if left.resource.provider != right.resource.provider {
		return left.resource.provider < right.resource.provider
	}
	if left.resource.scope != right.resource.scope {
		return left.resource.scope < right.resource.scope
	}
	return left.resource.object < right.resource.object
}

@(private)
definition_valid :: proc(definition: Definition) -> bool {
	return resource_valid(definition.resource) && definition.kind != .Invalid &&
	       len(definition.name) > 0 && len(definition.name) <= MAX_NAME_BYTES &&
	       utf8.valid_string(definition.name)
}

@(private)
entry_valid :: proc(entry: Entry) -> bool {
	return definition_valid(Definition{resource = entry.resource, name = entry.name, kind = entry.kind})
}

@(private)
resource_valid :: proc(resource: Resource_ID) -> bool {
	return resource.provider != 0 && resource.scope != 0 && resource.object != 0
}

/* model_calculate_renames independently derives one checked same-directory rename set. */
model_calculate_renames :: proc(
	model: ^Model,
	edited_names: []string,
	changes: ^[MAX_ENTRIES]Rename,
) -> (count: int, ok: bool, failure: Failure_Code) {
	if !model_validate(model) || changes == nil || len(edited_names) != model.count {
		return 0, false, .Invalid_Editable_Projection
	}
	for name, index in edited_names {
		if !editable_destination_valid(name) {
			return 0, false, .Invalid_Editable_Projection
		}
		for previous in edited_names[:index] {
			if len(name) > 0 && previous == name do return 0, false, .Duplicate_Destination
		}
	}
	count = 0
	for name, index in edited_names {
		if name == model.entries[index].name do continue
		changes[count] = Rename {
			resource = model.entries[index].resource,
			kind = .Delete if len(name) == 0 else (.Move if strings.contains(name, "/") else .Rename),
			from = model.entries[index].name,
			to = name,
		}
		count += 1
	}
	return count, true, .None
}

@(private)
editable_destination_valid :: proc(name: string) -> bool {
	if len(name) == 0 do return true
	if len(name) > MAX_NAME_BYTES || !utf8.valid_string(name) || name[0] == '/' do return false
	start := 0
	for byte, index in transmute([]u8)name {
		if byte != '/' do continue
		if index == start || name[start:index] == "." || name[start:index] == ".." do return false
		start = index + 1
	}
	return start < len(name) && name[start:] != "." && name[start:] != ".."
}
