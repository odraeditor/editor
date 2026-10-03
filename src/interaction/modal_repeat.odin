// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

/* MAX_MODAL_REPEAT_TEXT_BYTES bounds retained inserted text independently from command input. */
MAX_MODAL_REPEAT_TEXT_BYTES :: 1_024

/* Modal_Repeat_Kind classifies the retained semantic change. */
Modal_Repeat_Kind :: enum u8 {
	Invalid,
	Command,
	Operator,
	Insert_Session,
}

/* Modal_Repeat_Record retains one bounded semantic change without raw input events. */
Modal_Repeat_Record :: struct {
	valid:               bool,
	kind:                Modal_Repeat_Kind,
	operation:           Command_Handle,
	entry_operation:     Command_Handle,
	profile:             Profile_Identity,
	catalog_generation:  Profile_Catalog_Generation,
	snapshot_generation: Snapshot_Generation,
	operator:            Modal_Operator_Kind,
	target:              Modal_Operator_Target_Kind,
	character_target:    Modal_Character_Target_Kind,
	count:               u64,
	count_explicit:      bool,
	selection_shape:     Modal_Visual_Kind,
	replace_text:        bool,
	text:                [MAX_MODAL_REPEAT_TEXT_BYTES]u8,
	text_length:         u16,
	target_text:         [MAX_MODAL_PENDING_TEXT_BYTES]u8,
	target_text_length:  u8,
	named_slot:          [MAX_MODAL_PENDING_TEXT_BYTES]u8,
	named_slot_length:   u8,
}

/* Modal_Repeat_State owns one committed record and one in-progress insert session. */
Modal_Repeat_State :: struct {
	record:          Modal_Repeat_Record,
	pending_active:  bool,
	pending_changed: bool,
	pending_kind:    Modal_Repeat_Kind,
	pending_entry:   Command_Handle,
	pending_profile: Profile_Identity,
	pending_catalog_generation: Profile_Catalog_Generation,
	pending_snapshot_generation: Snapshot_Generation,
	pending_replace_text: bool,
}

/* modal_repeat_clear forgets committed and in-progress semantic changes. */
modal_repeat_clear :: proc(state: ^Modal_Repeat_State) {
	if state != nil do state^ = {}
}

/* modal_repeat_inspect copies the committed semantic change. */
modal_repeat_inspect :: proc(state: ^Modal_Repeat_State) -> (Modal_Repeat_Record, bool) {
	if state == nil || !state.record.valid do return {}, false
	return state.record, true
}

/* modal_repeat_record publishes one complete non-insert semantic change. */
modal_repeat_record :: proc(state: ^Modal_Repeat_State, record: Modal_Repeat_Record) -> bool {
	if state == nil || !modal_repeat_record_is_valid(record) do return false
	state.record = record
	state.record.valid = true
	state.pending_active = false
	state.pending_changed = false
	state.pending_kind = .Invalid
	state.pending_entry = {}
	return true
}

/* modal_repeat_insert_begin starts a bounded insert or change session. */
modal_repeat_insert_begin :: proc(
	state: ^Modal_Repeat_State,
	record: Modal_Repeat_Record,
	changed: bool = false,
) -> bool {
	if state == nil || record.kind != .Insert_Session && record.kind != .Operator ||
	   record.profile.id == Profile_ID(0) ||
	   record.catalog_generation == Profile_Catalog_Generation(0) ||
	   record.snapshot_generation == Snapshot_Generation(0) {
		return false
	}
	state.pending_active = true
	state.pending_changed = changed
	state.pending_kind = record.kind
	state.pending_entry = record.entry_operation
	state.pending_profile = record.profile
	state.pending_catalog_generation = record.catalog_generation
	state.pending_snapshot_generation = record.snapshot_generation
	state.pending_replace_text = record.replace_text
	if changed {
		state.record = record
		state.record.valid = true
	}
	return true
}

/* modal_repeat_insert_append appends one admitted text payload to the active session. */
modal_repeat_insert_append :: proc(
	state: ^Modal_Repeat_State,
	operation: Command_Handle,
	text: string,
	replace_text: bool,
) -> bool {
	if state == nil || !state.pending_active || len(text) == 0 ||
	   operation.registry_generation == Registry_Generation(0) ||
	   (state.pending_changed &&
	    u64(state.record.text_length) + u64(len(text)) > MAX_MODAL_REPEAT_TEXT_BYTES) ||
	   (!state.pending_changed && u64(len(text)) > MAX_MODAL_REPEAT_TEXT_BYTES) {
		return false
	}
	if !state.pending_changed {
		state.record = Modal_Repeat_Record {
			valid = true,
			kind = state.pending_kind,
			operation = operation,
			entry_operation = state.pending_entry,
			profile = state.pending_profile,
			catalog_generation = state.pending_catalog_generation,
			snapshot_generation = state.pending_snapshot_generation,
			count = 1,
			replace_text = state.pending_replace_text || replace_text,
		}
	}
	start := int(state.record.text_length)
	copy(state.record.text[start:], transmute([]u8)text)
	state.record.text_length += u16(len(text))
	state.record.operation = operation
	state.record.replace_text = state.record.replace_text || replace_text
	state.pending_changed = true
	return true
}

/* modal_repeat_insert_finish commits a changed session and discards empty entry. */
modal_repeat_insert_finish :: proc(state: ^Modal_Repeat_State) -> bool {
	if state == nil || !state.pending_active do return false
	state.pending_active = false
	state.pending_changed = false
	state.pending_kind = .Invalid
	state.pending_entry = {}
	return true
}

/* modal_repeat_record_text returns the retained inserted or replacement text. */
modal_repeat_record_text :: proc(record: ^Modal_Repeat_Record) -> string {
	if record == nil || record.text_length == 0 do return ""
	return string(record.text[:record.text_length])
}

/* modal_repeat_record_named_slot returns the retained named-slot identity. */
modal_repeat_record_named_slot :: proc(record: ^Modal_Repeat_Record) -> string {
	if record == nil || record.named_slot_length == 0 do return ""
	return string(record.named_slot[:record.named_slot_length])
}

@(private)
modal_repeat_record_is_valid :: proc(record: Modal_Repeat_Record) -> bool {
	if record.kind == .Invalid || record.operation.registry_generation == Registry_Generation(0) ||
	   record.profile.id == Profile_ID(0) ||
	   record.catalog_generation == Profile_Catalog_Generation(0) ||
	   record.snapshot_generation == Snapshot_Generation(0) ||
	   record.count == 0 || record.count > MAX_MODAL_COUNT ||
	   record.text_length > MAX_MODAL_REPEAT_TEXT_BYTES ||
	   record.target_text_length > MAX_MODAL_PENDING_TEXT_BYTES ||
	   record.named_slot_length > MAX_MODAL_PENDING_TEXT_BYTES {
		return false
	}
	if record.kind == .Operator && record.operator == .None do return false
	return true
}
