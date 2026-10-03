// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

/* Process_Surface_State distinguishes a valid empty session from inspectable process records. */
Process_Surface_State :: enum u8 {
	Empty,
	Available,
}

/* Process_Navigation selects one ordered Process-row movement. */
Process_Navigation :: enum u8 {
	Previous,
	Next,
}

/* Process_Text_Field identifies copied public content in one exact process record. */
Process_Text_Field :: enum u8 {
	Invalid,
	Title,
	Target,
	Phase_Detail,
	Message,
	Output,
	Diagnostic,
}

/* Process_Row_ID identifies one exact immutable Process row. */
Process_Row_ID :: struct {
	operation:  Repository_Operation_ID,
	generation: Process_Record_Generation,
}

/* Process_Surface_Descriptor reports active-first bounded Process-row availability. */
Process_Surface_Descriptor :: struct {
	state:            Process_Surface_State,
	row_count:        u32,
	active_rows:      u8,
	retained_rows:    u32,
}

/* Process_Row_Descriptor projects bounded semantic summary fields without native authority. */
Process_Row_Descriptor :: struct {
	id:                     Process_Row_ID,
	repository:             Repository_Context,
	observation_generation: Observation_Generation,
	kind:                   Repository_Operation_Kind,
	lifecycle:              Repository_Process_Lifecycle,
	phase:                  Repository_Process_Phase,
	outcome:                Repository_Process_Outcome,
	target_kind:            Process_Target_Kind,
	progress:               Process_Progress,
	timing:                 Process_Record_Timing,
	active:                 bool,
	output_truncated:       bool,
	diagnostic_truncated:   bool,
	exit_status:            i32,
	exit_status_available:  bool,
	action_count:           u8,
}

/* Process_Selection owns one exact Process-row identity for session-local navigation. */
Process_Selection :: struct {
	current: Process_Row_ID,
}

/* Process_Detail_Descriptor projects bounded output metadata and checked record actions. */
Process_Detail_Descriptor :: struct {
	row:          Process_Row_Descriptor,
	content:      Process_Output_Descriptor,
	actions:      [MAX_PROCESS_ACTIONS]Process_Action_Descriptor,
	action_count: u8,
}

/* process_surface_descriptor validates and counts one bounded active-first Process source. */
process_surface_descriptor :: proc(records: []Process_Record) -> (Process_Surface_Descriptor, bool) {
	if len(records) > int(MAX_RETAINED_PROCESS_RECORDS) do return {}, false
	descriptor := Process_Surface_Descriptor{row_count = u32(len(records))}
	if len(records) == 0 {
		descriptor.state = .Empty
		return descriptor, true
	}
	descriptor.state = .Available
	for index in 0 ..< len(records) {
		record, described := process_record_descriptor(&records[index])
		if !described do return {}, false
		for previous in 0 ..< index {
			prior, prior_described := process_record_descriptor(&records[previous])
			if !prior_described || prior.operation == record.operation do return {}, false
		}
		if repository_process_lifecycle_is_terminal(record.lifecycle) {
			descriptor.retained_rows += 1
		} else {
			descriptor.active_rows += 1
			if descriptor.active_rows > 1 do return {}, false
		}
	}
	return descriptor, true
}

/* process_surface_row returns the active record first, then terminal records newest first. */
process_surface_row :: proc(
	records: []Process_Record,
	ordinal: u32,
) -> (Process_Row_Descriptor, bool, Failure_Code) {
	surface, valid := process_surface_descriptor(records)
	if !valid do return {}, false, .Invalid_Request
	if ordinal >= surface.row_count do return {}, false, .Action_Unavailable
	index, found := process_surface_record_index(records, surface, ordinal)
	if !found do return {}, false, .Cleanup
	record, described := process_record_descriptor(&records[index])
	if !described do return {}, false, .Cleanup
	return process_row_descriptor(record), true, .None
}

/* process_selection_begin selects the active row or newest retained row and admits an empty state. */
process_selection_begin :: proc(records: []Process_Record) -> (Process_Selection, bool) {
	surface, valid := process_surface_descriptor(records)
	if !valid do return {}, false
	if surface.state == .Empty do return {}, true
	row, projected, _ := process_surface_row(records, 0)
	if !projected do return {}, false
	return Process_Selection{current = row.id}, true
}

/* process_selection_is_current checks one exact immutable row or the valid empty state. */
process_selection_is_current :: proc(records: []Process_Record, selection: Process_Selection) -> bool {
	surface, valid := process_surface_descriptor(records)
	if !valid do return false
	if selection.current == {} do return surface.state == .Empty
	_, _, found, _ := process_surface_find_exact(records, selection.current)
	return found
}

/* process_selection_move moves once through active-first Process-row order. */
process_selection_move :: proc(
	records: []Process_Record,
	selection: Process_Selection,
	direction: Process_Navigation,
) -> (Process_Selection, bool, Failure_Code) {
	if !process_selection_is_current(records, selection) do return {}, false, .Process_Record_Stale
	surface, _ := process_surface_descriptor(records)
	if surface.state == .Empty do return selection, true, .None
	ordinal, found := process_surface_row_ordinal(records, selection.current)
	if !found do return {}, false, .Process_Record_Stale
	next := ordinal
	switch direction {
	case .Previous:
		if next > 0 do next -= 1
	case .Next:
		if next + 1 < surface.row_count do next += 1
	}
	row, projected, failure := process_surface_row(records, next)
	if !projected do return {}, false, failure
	return Process_Selection{current = row.id}, true, .None
}

/* process_selection_reconcile preserves stable operation identity across record replacement. */
process_selection_reconcile :: proc(
	records: []Process_Record,
	selection: Process_Selection,
) -> (Process_Selection, bool, Failure_Code) {
	surface, valid := process_surface_descriptor(records)
	if !valid do return {}, false, .Invalid_Request
	if surface.state == .Empty do return {}, true, .None
	if selection.current.operation != Repository_Operation_ID(0) {
		for index in 0 ..< len(records) {
			record, described := process_record_descriptor(&records[index])
			if !described do return {}, false, .Cleanup
			if record.operation == selection.current.operation {
				return Process_Selection {
					current = {operation = record.operation, generation = record.generation},
				}, true, .None
			}
		}
	}
	begin, begun := process_selection_begin(records)
	if !begun do return {}, false, .Cleanup
	return begin, true, .None
}

/* process_surface_detail projects one exact row's bounded content and checked actions. */
process_surface_detail :: proc(
	records: []Process_Record,
	selection: Process_Selection,
) -> (Process_Detail_Descriptor, bool, Failure_Code) {
	index, record, found, failure := process_surface_find_exact(records, selection.current)
	if !found do return {}, false, failure
	detail := Process_Detail_Descriptor {
		row = process_row_descriptor(record),
		content = record.content,
		action_count = record.action_count,
	}
	for action_index in 0 ..< int(record.action_count) {
		detail.actions[action_index] = record.actions[action_index]
	}
	_ = index
	return detail, true, .None
}

/* process_surface_text returns borrowed copied public content for one exact Process row. */
process_surface_text :: proc(
	records: []Process_Record,
	id: Process_Row_ID,
	field: Process_Text_Field,
) -> ([]u8, bool, Failure_Code) {
	index, record, found, failure := process_surface_find_exact(records, id)
	if !found do return nil, false, failure
	reference: Process_Text_Ref
	switch field {
	case .Title:
		reference = record.title
	case .Target:
		reference = record.target
	case .Phase_Detail:
		reference = record.phase_detail
	case .Message:
		reference = record.message
	case .Output:
		reference = record.content.output
	case .Diagnostic:
		reference = record.content.diagnostic
	case .Invalid:
		return nil, false, .Invalid_Request
	}
	content, available := process_record_text(&records[index], reference)
	if !available do return nil, false, .Cleanup
	return content, true, .None
}

/* process_surface_target returns one checked safe semantic target from immutable record content. */
process_surface_target :: proc(
	records: []Process_Record,
	id: Process_Row_ID,
) -> (Process_Target_Kind, []u8, bool, Failure_Code) {
	_, record, found, failure := process_surface_find_exact(records, id)
	if !found do return .None, nil, false, failure
	target, available, text_failure := process_surface_text(records, id, .Target)
	if !available do return .None, nil, false, text_failure
	return record.target_kind, target, true, .None
}

/* process_selection_action resolves one available action from an exact selected generation. */
process_selection_action :: proc(
	records: []Process_Record,
	selection: Process_Selection,
	kind: Process_Action_Kind,
) -> (Process_Action_Descriptor, bool, Failure_Code) {
	if kind == .Invalid do return {}, false, .Invalid_Request
	_, record, found, failure := process_surface_find_exact(records, selection.current)
	if !found do return {}, false, failure
	for index in 0 ..< int(record.action_count) {
		action := record.actions[index]
		if action.kind == kind && action.available do return action, true, .None
	}
	return {}, false, .Action_Unavailable
}

/* process_surface_action_is_current rejects actions from replaced, removed, or unavailable records. */
process_surface_action_is_current :: proc(
	records: []Process_Record,
	action: Process_Action_Descriptor,
) -> (bool, Failure_Code) {
	if action.kind == .Invalid || action.operation == Repository_Operation_ID(0) ||
	   action.generation == Process_Record_Generation(0) || !action.available {
		return false, .Invalid_Request
	}
	id := Process_Row_ID{operation = action.operation, generation = action.generation}
	_, record, found, failure := process_surface_find_exact(records, id)
	if !found do return false, failure
	for index in 0 ..< int(record.action_count) {
		if record.actions[index] == action do return true, .None
	}
	return false, .Action_Unavailable
}

@(private)
process_row_descriptor :: proc(record: Process_Record_Descriptor) -> Process_Row_Descriptor {
	return {
		id = {operation = record.operation, generation = record.generation},
		repository = record.repository,
		observation_generation = record.observation_generation,
		kind = record.kind,
		lifecycle = record.lifecycle,
		phase = record.phase,
		outcome = record.outcome,
		target_kind = record.target_kind,
		progress = record.progress,
		timing = record.timing,
		active = !repository_process_lifecycle_is_terminal(record.lifecycle),
		output_truncated = record.content.output_truncated,
		diagnostic_truncated = record.content.diagnostic_truncated,
		exit_status = record.content.exit_status,
		exit_status_available = record.content.exit_status_available,
		action_count = record.action_count,
	}
}

@(private)
process_surface_record_index :: proc(
	records: []Process_Record,
	surface: Process_Surface_Descriptor,
	ordinal: u32,
) -> (int, bool) {
	retained_ordinal := ordinal
	if surface.active_rows == 1 {
		if ordinal == 0 {
			for index in 0 ..< len(records) {
				record, described := process_record_descriptor(&records[index])
				if described && !repository_process_lifecycle_is_terminal(record.lifecycle) do return index, true
			}
			return 0, false
		}
		retained_ordinal -= 1
	}
	current: u32
	for offset in 0 ..< len(records) {
		index := len(records) - 1 - offset
		record, described := process_record_descriptor(&records[index])
		if !described do return 0, false
		if !repository_process_lifecycle_is_terminal(record.lifecycle) do continue
		if current == retained_ordinal do return index, true
		current += 1
	}
	return 0, false
}

@(private)
process_surface_row_ordinal :: proc(records: []Process_Record, wanted: Process_Row_ID) -> (u32, bool) {
	surface, valid := process_surface_descriptor(records)
	if !valid do return 0, false
	for ordinal in 0 ..< surface.row_count {
		row, projected, _ := process_surface_row(records, ordinal)
		if projected && row.id == wanted do return ordinal, true
	}
	return 0, false
}

@(private)
process_surface_find_exact :: proc(
	records: []Process_Record,
	wanted: Process_Row_ID,
) -> (int, Process_Record_Descriptor, bool, Failure_Code) {
	_, valid := process_surface_descriptor(records)
	if !valid do return 0, {}, false, .Invalid_Request
	if wanted.operation == Repository_Operation_ID(0) || wanted.generation == Process_Record_Generation(0) {
		return 0, {}, false, .Action_Unavailable
	}
	for index in 0 ..< len(records) {
		record, described := process_record_descriptor(&records[index])
		if !described do return 0, {}, false, .Cleanup
		if record.operation != wanted.operation do continue
		if record.generation != wanted.generation do return 0, {}, false, .Process_Record_Stale
		return index, record, true, .None
	}
	return 0, {}, false, .Process_Record_Stale
}
