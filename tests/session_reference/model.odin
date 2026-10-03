// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package session_reference provides a simple contiguous oracle for editor-session lifecycle tests.
package session_reference

import "base:runtime"
import "core:strings"
import "core:unicode/utf8"

/* Handle identifies one model slot generation; zero fields are invalid. */
Handle :: struct {
	id:         u64,
	generation: u64,
}

/* Failure_Code classifies rejected model operations without partial mutation. */
Failure_Code :: enum u8 {
	None,
	Invalid_Model,
	Invalid_Handle,
	Capacity,
	Invalid_Text,
	Label_Collision,
	Path_Collision,
	Invalid_State,
	Allocation,
}

/* Failure reports the rejected model operation and affected handle. */
Failure :: struct {
	code:   Failure_Code,
	handle: Handle,
}

/* Close_Authority records whether modified canonical text may be discarded. */
Close_Authority :: enum u8 {
	None,
	Discard_Modified,
}

/* Close_Outcome distinguishes admission from the final detached state. */
Close_Outcome :: enum u8 {
	Ready,
	Discard_Required,
	Closed,
}

/* Descriptor is a borrowed immutable view of one live model entry. */
Descriptor :: struct {
	handle:      Handle,
	label:       string,
	associated:  bool,
	modified:    bool,
	active:      bool,
	text_bytes:  u64,
}

@(private)
Entry :: struct {
	handle:        Handle,
	identity_text: string,
	associated:    bool,
	modified:      bool,
	text_bytes:    u64,
	live:          bool,
}

/* Model owns a fixed-capacity contiguous session oracle and its label strings. */
Model :: struct {
	entries:   []Entry,
	mru_slots: []int,
	mru_count: int,
	live_count: int,
	active:    Handle,
	allocator: runtime.Allocator,
}

/* model_init allocates one empty fixed-capacity oracle. */
model_init :: proc(capacity: int, allocator := context.allocator) -> (model: Model, ok: bool) {
	if capacity <= 0 || allocator.procedure == nil {
		return {}, false
	}
	entries, entries_error := make([]Entry, capacity, allocator)
	if entries_error != nil {
		return {}, false
	}
	mru_slots, mru_error := make([]int, capacity, allocator)
	if mru_error != nil {
		delete(entries, allocator)
		return {}, false
	}
	return Model {
		entries = entries,
		mru_slots = mru_slots,
		allocator = allocator,
	}, true
}

/* model_deinit releases every model-owned label and contiguous allocation. */
model_deinit :: proc(model: ^Model) {
	if model == nil {
		return
	}
	for index in 0 ..< len(model.entries) {
		entry := &model.entries[index]
		if entry.live && len(entry.identity_text) > 0 {
			delete(entry.identity_text, model.allocator)
		}
	}
	if model.mru_slots != nil {
		delete(model.mru_slots, model.allocator)
	}
	if model.entries != nil {
		delete(model.entries, model.allocator)
	}
	model^ = {}
}

/* model_create publishes one named unassociated entry and activates it. */
model_create :: proc(
	model: ^Model,
	name: string,
	text_bytes: u64 = 0,
) -> (handle: Handle, ok: bool, failure: Failure) {
	if !model_ready(model) {
		return {}, false, Failure{code = .Invalid_Model}
	}
	if !identity_text_is_valid(name) {
		return {}, false, Failure{code = .Invalid_Text}
	}
	if model_find_label(model, name).id != 0 {
		return {}, false, Failure{code = .Label_Collision}
	}
	return model_publish(model, name, false, text_bytes)
}

/* model_open reuses an associated path or publishes and activates one new entry. */
model_open :: proc(
	model: ^Model,
	normalized_path: string,
	text_bytes: u64 = 0,
) -> (handle: Handle, reused: bool, ok: bool, failure: Failure) {
	if !model_ready(model) {
		return {}, false, false, Failure{code = .Invalid_Model}
	}
	if !identity_text_is_valid(normalized_path) {
		return {}, false, false, Failure{code = .Invalid_Text}
	}
	path_handle := model_find_path(model, normalized_path)
	if path_handle.id != 0 {
		activated, activate_failure := model_activate(model, path_handle)
		return path_handle, true, activated, activate_failure
	}
	if model_find_label(model, normalized_path).id != 0 {
		return {}, false, false, Failure{code = .Label_Collision}
	}
	published_handle, published, publish_failure := model_publish(
		model,
		normalized_path,
		true,
		text_bytes,
	)
	return published_handle, false, published, publish_failure
}

/* model_associate replaces one unassociated label with a unique normalized path. */
model_associate :: proc(
	model: ^Model,
	handle: Handle,
	normalized_path: string,
) -> (ok: bool, failure: Failure) {
	entry, valid := model_entry(model, handle)
	if !valid {
		return false, Failure{code = .Invalid_Handle, handle = handle}
	}
	if entry.associated {
		return false, Failure{code = .Invalid_State, handle = handle}
	}
	if !identity_text_is_valid(normalized_path) {
		return false, Failure{code = .Invalid_Text, handle = handle}
	}
	path_owner := model_find_path(model, normalized_path)
	if path_owner.id != 0 && path_owner != handle {
		return false, Failure{code = .Path_Collision, handle = handle}
	}
	label_owner := model_find_label(model, normalized_path)
	if label_owner.id != 0 && label_owner != handle {
		return false, Failure{code = .Label_Collision, handle = handle}
	}
	owned, allocation_error := strings.clone(normalized_path, model.allocator)
	if allocation_error != nil {
		return false, Failure{code = .Allocation, handle = handle}
	}
	delete(entry.identity_text, model.allocator)
	entry.identity_text = owned
	entry.associated = true
	return true, {}
}

/* model_activate makes one checked entry active and moves it to the MRU front. */
model_activate :: proc(model: ^Model, handle: Handle) -> (ok: bool, failure: Failure) {
	entry, valid := model_entry(model, handle)
	if !valid {
		return false, Failure{code = .Invalid_Handle, handle = handle}
	}
	slot := int(handle.id - 1)
	mru_promote(model, slot)
	model.active = entry.handle
	return true, {}
}

/* model_set_modified changes only the explicit dirty marker of one live entry. */
model_set_modified :: proc(
	model: ^Model,
	handle: Handle,
	modified: bool,
) -> (ok: bool, failure: Failure) {
	entry, valid := model_entry(model, handle)
	if !valid {
		return false, Failure{code = .Invalid_Handle, handle = handle}
	}
	entry.modified = modified
	return true, {}
}

/* model_assess_close checks dirty admission without changing model state. */
model_assess_close :: proc(
	model: ^Model,
	handle: Handle,
) -> (outcome: Close_Outcome, ok: bool, failure: Failure) {
	entry, valid := model_entry(model, handle)
	if !valid {
		return {}, false, Failure{code = .Invalid_Handle, handle = handle}
	}
	if entry.modified {
		return .Discard_Required, true, {}
	}
	return .Ready, true, {}
}

/* model_close_checked requires explicit authority before discarding modified text. */
model_close_checked :: proc(
	model: ^Model,
	handle: Handle,
	authority: Close_Authority = .None,
) -> (outcome: Close_Outcome, successor: Handle, closed: bool, failure: Failure) {
	assessment, assessed, assess_failure := model_assess_close(model, handle)
	if !assessed {
		return {}, {}, false, assess_failure
	}
	if assessment == .Discard_Required && authority != .Discard_Modified {
		return .Discard_Required, {}, false, {}
	}
	detached_successor, detached, detach_failure := model_close(model, handle)
	if !detached {
		return {}, {}, false, detach_failure
	}
	return .Closed, detached_successor, true, {}
}

/* model_close detaches one checked entry and returns the current successor. */
model_close :: proc(
	model: ^Model,
	handle: Handle,
) -> (successor: Handle, ok: bool, failure: Failure) {
	entry, valid := model_entry(model, handle)
	if !valid {
		return {}, false, Failure{code = .Invalid_Handle, handle = handle}
	}
	slot := int(handle.id - 1)
	mru_remove(model, slot)
	if len(entry.identity_text) > 0 {
		delete(entry.identity_text, model.allocator)
	}
	generation := entry.handle.generation
	entry^ = Entry{handle = Handle{generation = generation}}
	model.live_count -= 1
	if model.active == handle {
		if model.mru_count > 0 {
			model.active = model.entries[model.mru_slots[0]].handle
		} else {
			model.active = {}
		}
	}
	return model.active, true, {}
}

/* model_find_label returns the exact live selection-label owner or an invalid handle. */
model_find_label :: proc(model: ^Model, label: string) -> Handle {
	if !model_ready(model) {
		return {}
	}
	for entry in model.entries {
		if entry.live && entry.identity_text == label {
			return entry.handle
		}
	}
	return {}
}

/* model_find_path returns the exact associated path owner or an invalid handle. */
model_find_path :: proc(model: ^Model, path: string) -> Handle {
	if !model_ready(model) {
		return {}
	}
	for entry in model.entries {
		if entry.live && entry.associated && entry.identity_text == path {
			return entry.handle
		}
	}
	return {}
}

/* model_inspect copies one descriptor for a checked live handle. */
model_inspect :: proc(model: ^Model, handle: Handle) -> (descriptor: Descriptor, ok: bool) {
	entry, valid := model_entry(model, handle)
	if !valid {
		return {}, false
	}
	return Descriptor {
		handle = entry.handle,
		label = entry.identity_text,
		associated = entry.associated,
		modified = entry.modified,
		active = model.active == entry.handle,
		text_bytes = entry.text_bytes,
	}, true
}

/* model_mru_handle returns one checked handle by MRU position. */
model_mru_handle :: proc(model: ^Model, position: int) -> (handle: Handle, ok: bool) {
	if !model_ready(model) || position < 0 || position >= model.mru_count {
		return {}, false
	}
	return model.entries[model.mru_slots[position]].handle, true
}

/* model_active returns the current handle or zero when the model is empty. */
model_active :: proc(model: ^Model) -> Handle {
	if model == nil {
		return {}
	}
	return model.active
}

/* model_live_count returns the number of published entries. */
model_live_count :: proc(model: ^Model) -> int {
	if model == nil {
		return 0
	}
	return model.live_count
}

/* model_validate checks identity, uniqueness, activation, and MRU invariants. */
model_validate :: proc(model: ^Model) -> bool {
	if !model_ready(model) || model.live_count < 0 || model.live_count > len(model.entries) ||
	   model.mru_count != model.live_count {
		return false
	}
	live_count := 0
	for left_index in 0 ..< len(model.entries) {
		left := &model.entries[left_index]
		if !left.live {
			continue
		}
		live_count += 1
		if left.handle.id != u64(left_index + 1) || left.handle.generation == 0 ||
		   !identity_text_is_valid(left.identity_text) {
			return false
		}
		seen_in_mru := 0
		for position in 0 ..< model.mru_count {
			if model.mru_slots[position] == left_index {
				seen_in_mru += 1
			}
		}
		if seen_in_mru != 1 {
			return false
		}
		for right_index in left_index + 1 ..< len(model.entries) {
			right := &model.entries[right_index]
			if right.live && left.identity_text == right.identity_text {
				return false
			}
			if right.live && left.associated && right.associated &&
			   left.identity_text == right.identity_text {
				return false
			}
		}
	}
	if live_count != model.live_count {
		return false
	}
	for position in 0 ..< model.mru_count {
		slot := model.mru_slots[position]
		if slot < 0 || slot >= len(model.entries) || !model.entries[slot].live {
			return false
		}
	}
	if model.live_count == 0 {
		return model.active == Handle{}
	}
	active, valid := model_entry(model, model.active)
	return valid && active.handle == model.entries[model.mru_slots[0]].handle
}

@(private)
model_publish :: proc(
	model: ^Model,
	identity_text: string,
	associated: bool,
	text_bytes: u64,
) -> (handle: Handle, ok: bool, failure: Failure) {
	slot := model_free_slot(model)
	if slot < 0 {
		return {}, false, Failure{code = .Capacity}
	}
	entry := &model.entries[slot]
	if entry.handle.generation == max(u64) {
		return {}, false, Failure{code = .Capacity}
	}
	owned, allocation_error := strings.clone(identity_text, model.allocator)
	if allocation_error != nil {
		return {}, false, Failure{code = .Allocation}
	}
	handle = Handle {
		id = u64(slot + 1),
		generation = entry.handle.generation + 1,
	}
	entry^ = Entry {
		handle = handle,
		identity_text = owned,
		associated = associated,
		text_bytes = text_bytes,
		live = true,
	}
	model.live_count += 1
	mru_promote(model, slot)
	model.active = handle
	return handle, true, {}
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
model_free_slot :: proc(model: ^Model) -> int {
	for index in 0 ..< len(model.entries) {
		if !model.entries[index].live {
			return index
		}
	}
	return -1
}

@(private)
mru_promote :: proc(model: ^Model, slot: int) {
	mru_remove(model, slot)
	for position := model.mru_count; position > 0; position -= 1 {
		model.mru_slots[position] = model.mru_slots[position - 1]
	}
	model.mru_slots[0] = slot
	model.mru_count += 1
}

@(private)
mru_remove :: proc(model: ^Model, slot: int) {
	position := -1
	for index in 0 ..< model.mru_count {
		if model.mru_slots[index] == slot {
			position = index
			break
		}
	}
	if position < 0 {
		return
	}
	for index in position ..< model.mru_count - 1 {
		model.mru_slots[index] = model.mru_slots[index + 1]
	}
	model.mru_count -= 1
}

@(private)
model_ready :: proc(model: ^Model) -> bool {
	return model != nil && model.entries != nil && model.mru_slots != nil &&
	       len(model.entries) == len(model.mru_slots) && model.allocator.procedure != nil
}

@(private)
identity_text_is_valid :: proc(text: string) -> bool {
	return len(text) > 0 && utf8.valid_string(text) && strings.index_byte(text, 0) < 0
}
