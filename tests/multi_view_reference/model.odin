// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package multi_view_reference provides an independent contiguous oracle for
// buffer-owned selection and pane-owned presentation state.
package multi_view_reference

import "base:runtime"

Buffer_ID :: distinct u32
Pane_ID :: distinct u32

Failure_Code :: enum u8 {
	None,
	Invalid_Model,
	Invalid_Buffer,
	Invalid_Pane,
	Buffer_Capacity,
	Pane_Capacity,
	Invalid_Point,
}

Failure :: struct {
	code: Failure_Code,
}

Buffer_State :: struct {
	id:                   Buffer_ID,
	effective_point:      u64,
	mark:                 u64,
	mark_present:         bool,
	region_active:        bool,
	selection_generation: u64,
	live:                 bool,
}

Pane_State :: struct {
	id:                Pane_ID,
	buffer:            Buffer_ID,
	stored_point:      u64,
	viewport_start:    u64,
	viewport_column:   u32,
	desired_column:    u32,
	desired_present:   bool,
	live:              bool,
}

Model :: struct {
	buffers:       []Buffer_State,
	panes:         []Pane_State,
	buffer_count:  int,
	pane_count:    int,
	active_pane:   Pane_ID,
	next_buffer_id: u32,
	next_pane_id:   u32,
	allocator:      runtime.Allocator,
}

model_init :: proc(
	buffer_capacity, pane_capacity: int,
	allocator := context.allocator,
) -> (model: Model, ok: bool) {
	if buffer_capacity <= 0 || pane_capacity <= 0 || allocator.procedure == nil {
		return {}, false
	}
	buffers, buffer_error := make([]Buffer_State, buffer_capacity, allocator)
	if buffer_error != nil {
		return {}, false
	}
	panes, pane_error := make([]Pane_State, pane_capacity, allocator)
	if pane_error != nil {
		delete(buffers, allocator)
		return {}, false
	}
	return Model {
		buffers = buffers,
		panes = panes,
		next_buffer_id = 1,
		next_pane_id = 1,
		allocator = allocator,
	}, true
}

model_deinit :: proc(model: ^Model) {
	if model == nil {
		return
	}
	if model.panes != nil {
		delete(model.panes, model.allocator)
	}
	if model.buffers != nil {
		delete(model.buffers, model.allocator)
	}
	model^ = {}
}

model_add_buffer :: proc(
	model: ^Model,
	effective_point: u64,
	mark: u64 = 0,
	mark_present := false,
	region_active := false,
) -> (id: Buffer_ID, ok: bool, failure: Failure) {
	if !model_ready(model) {
		return {}, false, Failure{code = .Invalid_Model}
	}
	if model.buffer_count >= len(model.buffers) {
		return {}, false, Failure{code = .Buffer_Capacity}
	}
	if region_active && !mark_present {
		return {}, false, Failure{code = .Invalid_Point}
	}
	id = Buffer_ID(model.next_buffer_id)
	model.next_buffer_id += 1
	model.buffers[model.buffer_count] = Buffer_State {
		id = id,
		effective_point = effective_point,
		mark = mark,
		mark_present = mark_present,
		region_active = region_active,
		selection_generation = 1,
		live = true,
	}
	model.buffer_count += 1
	return id, true, {}
}

model_open_root :: proc(
	model: ^Model,
	buffer: Buffer_ID,
	viewport_start: u64 = 0,
	viewport_column: u32 = 0,
) -> (pane: Pane_ID, ok: bool, failure: Failure) {
	if !model_ready(model) || model.pane_count != 0 {
		return {}, false, Failure{code = .Invalid_Model}
	}
	buffer_state, buffer_ok := model_buffer(model, buffer)
	if !buffer_ok {
		return {}, false, Failure{code = .Invalid_Buffer}
	}
	pane = Pane_ID(model.next_pane_id)
	model.next_pane_id += 1
	model.panes[0] = Pane_State {
		id = pane,
		buffer = buffer,
		stored_point = buffer_state.effective_point,
		viewport_start = viewport_start,
		viewport_column = viewport_column,
		live = true,
	}
	model.pane_count = 1
	model.active_pane = pane
	return pane, true, {}
}

model_split_active :: proc(model: ^Model) -> (pane: Pane_ID, ok: bool, failure: Failure) {
	if !model_ready(model) || model.active_pane == Pane_ID(0) {
		return {}, false, Failure{code = .Invalid_Model}
	}
	if model.pane_count >= len(model.panes) {
		return {}, false, Failure{code = .Pane_Capacity}
	}
	active, active_ok := model_pane(model, model.active_pane)
	if !active_ok {
		return {}, false, Failure{code = .Invalid_Pane}
	}
	buffer, buffer_ok := model_buffer(model, active.buffer)
	if !buffer_ok {
		return {}, false, Failure{code = .Invalid_Buffer}
	}
	active.stored_point = buffer.effective_point
	pane = Pane_ID(model.next_pane_id)
	model.next_pane_id += 1
	copy := active^
	copy.id = pane
	model.panes[model.pane_count] = copy
	model.pane_count += 1
	return pane, true, {}
}

model_focus :: proc(model: ^Model, target: Pane_ID) -> (ok: bool, failure: Failure) {
	if !model_ready(model) || model.active_pane == Pane_ID(0) {
		return false, Failure{code = .Invalid_Model}
	}
	target_pane, target_ok := model_pane(model, target)
	if !target_ok {
		return false, Failure{code = .Invalid_Pane}
	}
	if target == model.active_pane {
		return true, {}
	}
	outgoing, outgoing_ok := model_pane(model, model.active_pane)
	if !outgoing_ok {
		return false, Failure{code = .Invalid_Pane}
	}
	outgoing_buffer, outgoing_buffer_ok := model_buffer(model, outgoing.buffer)
	target_buffer, target_buffer_ok := model_buffer(model, target_pane.buffer)
	if !outgoing_buffer_ok || !target_buffer_ok {
		return false, Failure{code = .Invalid_Buffer}
	}
	outgoing.stored_point = outgoing_buffer.effective_point
	model.active_pane = target
	target_buffer.effective_point = target_pane.stored_point
	target_buffer.selection_generation += 1
	return true, {}
}

model_set_effective_point :: proc(
	model: ^Model,
	buffer: Buffer_ID,
	point: u64,
) -> (ok: bool, failure: Failure) {
	state, valid := model_buffer(model, buffer)
	if !valid {
		return false, Failure{code = .Invalid_Buffer}
	}
	state.effective_point = point
	state.selection_generation += 1
	return true, {}
}

model_set_active_point :: proc(
	model: ^Model,
	point: u64,
	desired_column: u32,
) -> (ok: bool, failure: Failure) {
	if !model_ready(model) || model.active_pane == Pane_ID(0) {
		return false, Failure{code = .Invalid_Model}
	}
	pane, pane_ok := model_pane(model, model.active_pane)
	if !pane_ok {
		return false, Failure{code = .Invalid_Pane}
	}
	buffer, buffer_ok := model_buffer(model, pane.buffer)
	if !buffer_ok {
		return false, Failure{code = .Invalid_Buffer}
	}
	buffer.effective_point = point
	buffer.selection_generation += 1
	pane.stored_point = point
	pane.desired_column = desired_column
	pane.desired_present = true
	return true, {}
}

model_set_mark :: proc(
	model: ^Model,
	buffer: Buffer_ID,
	mark: u64,
	present, active: bool,
) -> (ok: bool, failure: Failure) {
	state, valid := model_buffer(model, buffer)
	if !valid {
		return false, Failure{code = .Invalid_Buffer}
	}
	if active && !present {
		return false, Failure{code = .Invalid_Point}
	}
	state.mark = mark
	state.mark_present = present
	state.region_active = active
	state.selection_generation += 1
	return true, {}
}

model_set_viewport :: proc(
	model: ^Model,
	pane: Pane_ID,
	start: u64,
	column: u32,
) -> (ok: bool, failure: Failure) {
	state, valid := model_pane(model, pane)
	if !valid {
		return false, Failure{code = .Invalid_Pane}
	}
	state.viewport_start = start
	state.viewport_column = column
	return true, {}
}

model_inspect_buffer :: proc(model: ^Model, id: Buffer_ID) -> (state: Buffer_State, ok: bool) {
	entry, valid := model_buffer(model, id)
	if !valid {
		return {}, false
	}
	return entry^, true
}

model_inspect_pane :: proc(model: ^Model, id: Pane_ID) -> (state: Pane_State, ok: bool) {
	entry, valid := model_pane(model, id)
	if !valid {
		return {}, false
	}
	return entry^, true
}

model_validate :: proc(model: ^Model) -> bool {
	if !model_ready(model) || model.buffer_count < 0 || model.pane_count < 0 ||
	   model.buffer_count > len(model.buffers) || model.pane_count > len(model.panes) {
		return false
	}
	for index in 0 ..< model.buffer_count {
		state := model.buffers[index]
		if !state.live || state.id == Buffer_ID(0) ||
		   (state.region_active && !state.mark_present) {
			return false
		}
	}
	for index in 0 ..< model.pane_count {
		state := model.panes[index]
		if !state.live || state.id == Pane_ID(0) {
			return false
		}
		_, buffer_ok := model_buffer(model, state.buffer)
		if !buffer_ok {
			return false
		}
		for other in index + 1 ..< model.pane_count {
			if model.panes[other].id == state.id {
				return false
			}
		}
	}
	if model.pane_count == 0 {
		return model.active_pane == Pane_ID(0)
	}
	_, active_ok := model_pane(model, model.active_pane)
	return active_ok
}

@(private)
model_ready :: proc(model: ^Model) -> bool {
	return model != nil && model.buffers != nil && model.panes != nil
}

@(private)
model_buffer :: proc(model: ^Model, id: Buffer_ID) -> (^Buffer_State, bool) {
	if !model_ready(model) || id == Buffer_ID(0) {
		return nil, false
	}
	for index in 0 ..< model.buffer_count {
		if model.buffers[index].live && model.buffers[index].id == id {
			return &model.buffers[index], true
		}
	}
	return nil, false
}

@(private)
model_pane :: proc(model: ^Model, id: Pane_ID) -> (^Pane_State, bool) {
	if !model_ready(model) || id == Pane_ID(0) {
		return nil, false
	}
	for index in 0 ..< model.pane_count {
		if model.panes[index].live && model.panes[index].id == id {
			return &model.panes[index], true
		}
	}
	return nil, false
}
