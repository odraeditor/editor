// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import "../ksawery"
import "../ui"
import "core:fmt"
import "core:unicode/utf8"

/* Ksawery_Extension_Annotation_Selection retains semantic identity, never a row. */
Ksawery_Extension_Annotation_Selection :: struct {
	valid:                  bool,
	contributor:            ksawery.Contributor_Identity,
	annotation:             ksawery.Extension_Annotation_ID,
	target:                 ksawery.Extension_Annotation_Target,
	observation_family:     ksawery.Extension_Observation_Family,
	observation_generation: u64,
}

/* ksawery_extension_annotation_visible_row_count counts current target-local projections. */
ksawery_extension_annotation_visible_row_count :: proc(
	generation: ^ksawery.Extension_Annotation_Generation,
	observation: ksawery.Extension_Annotation_Observation,
) -> int {
	if !ksawery_extension_annotation_generation_is_visible(generation, observation) do return 0
	return len(generation.annotations)
}

/* ksawery_extension_annotation_append_target appends deterministic metadata after one target. */
ksawery_extension_annotation_append_target :: proc(
	rows: []ui.List_Item_Definition,
	storage: []u8,
	write: ^int,
	generation: ^ksawery.Extension_Annotation_Generation,
	observation: ksawery.Extension_Annotation_Observation,
	target: ksawery.Extension_Annotation_Target,
	selection: Ksawery_Extension_Annotation_Selection,
) -> (current_row: i32, complete: bool) {
	current_row = -1
	if write == nil do return -1, false
	if !ksawery_extension_annotation_generation_is_visible(generation, observation) do return -1, true
	for annotation, ordinal in generation.annotations {
		if annotation.target != target do continue
		if write^ >= len(rows) do return current_row, false
		row := write^
		label := ksawery_extension_annotation_label(annotation)
		offset := row * KSAWERY_LIST_ROW_BYTES
		copy(storage[offset:offset + len(label)], transmute([]u8)label)
		rows[row] = {
			id = ksawery_extension_annotation_ui_id(observation.family, u32(ordinal)),
			text = string(storage[offset:offset + len(label)]),
			passive = !annotation.command.present,
			emphasis_bytes = u32(len(label)),
			emphasis_style = ksawery_extension_annotation_style_role(annotation),
		}
		if annotation.command.present {
			rows[row].action = {
				owner_id = KSAWERY_UI_OWNER_ID,
				action_id = KSAWERY_LIST_SELECT_ACTION,
				generation = KSAWERY_UI_TARGET_GENERATION,
			}
		}
		if ksawery_extension_annotation_selection_matches(selection, generation^, annotation) {
			current_row = i32(row)
		}
		write^ += 1
	}
	return current_row, true
}

/* ksawery_extension_annotation_select_ui_item resolves one row to exact semantic identity. */
ksawery_extension_annotation_select_ui_item :: proc(
	generation: ^ksawery.Extension_Annotation_Generation,
	observation: ksawery.Extension_Annotation_Observation,
	id: ui.List_Item_ID,
	selection: ^Ksawery_Extension_Annotation_Selection,
) -> bool {
	if selection == nil || !ksawery_extension_annotation_generation_is_visible(generation, observation) {
		return false
	}
	for annotation, ordinal in generation.annotations {
		if ksawery_extension_annotation_ui_id(observation.family, u32(ordinal)) == id &&
		   annotation.command.present {
			selection^ = {
				valid = true,
				contributor = generation.contributor_identity,
				annotation = annotation.id,
				target = annotation.target,
				observation_family = observation.family,
				observation_generation = observation.generation,
			}
			return true
		}
	}
	return false
}

/* ksawery_extension_annotation_selected_command resolves one admitted target-local command. */
ksawery_extension_annotation_selected_command :: proc(
	generation: ^ksawery.Extension_Annotation_Generation,
	selection: Ksawery_Extension_Annotation_Selection,
) -> (string, bool) {
	if generation == nil || !selection.valid ||
	   selection.contributor != generation.contributor_identity ||
	   selection.observation_family != generation.observation.family ||
	   selection.observation_generation != generation.observation.generation {
		return "", false
	}
	for &annotation in generation.annotations {
		if annotation.id != selection.annotation || annotation.target != selection.target ||
		   !annotation.command.present {
			continue
		}
		identity := &annotation.command.identity
		return string(identity.bytes[:identity.length]), true
	}
	return "", false
}

/* ksawery_extension_annotation_active_context resolves the current visible repository surface. */
ksawery_extension_annotation_active_context :: proc(
	state: ^Ksawery_Workflow_State,
) -> (
	generation: ^ksawery.Extension_Annotation_Generation,
	observation: ksawery.Extension_Annotation_Observation,
	ok: bool,
) {
	if state == nil do return nil, {}, false
	family: ksawery.Extension_Observation_Family
	switch state.view_mode {
	case .Status:   family = .Status
	case .History:  family = .History
	case .Refs:     family = .Refs
	case .Sequence: family = .Sequence
	case .Conflict: family = .Conflict
	case .Process:  family = .Process
	case .Provider_Inspection, .Revision_Detail, .Revision_Range, .Inspection_Workflow,
	     .Inspection_Input, .Inspection_Confirmation, .Resource, .Commit_Message,
	     .Raw_Command_Input, .Raw_Command_Confirmation,
	     .Amend_Confirmation, .Push_Confirmation, .Branch_Name,
	     .Branch_Confirmation, .Tag_Name, .Tag_Confirmation,
	     .Merge_Confirmation, .Rebase_Confirmation,
	     .Revision_Sequence_Confirmation, .Bisect_Confirmation,
	     .Conflict_Confirmation, .Extension_Command, .Status_Command_Dispatcher:
		return nil, {}, false
	}
	switch family {
	case .Status:
		descriptor, described := ksawery.status_observation_descriptor(&state.observation)
		if !described do return nil, {}, false
		observation = {family = family, repository = descriptor.repository, generation = u64(descriptor.generation)}
	case .History:
		descriptor, described := ksawery.history_observation_descriptor(&state.history)
		if !described do return nil, {}, false
		observation = {family = family, repository = descriptor.repository, generation = u64(descriptor.generation)}
	case .Refs:
		descriptor, described := ksawery.ref_observation_descriptor(&state.refs)
		if !described do return nil, {}, false
		observation = {family = family, repository = descriptor.repository, generation = u64(descriptor.generation)}
	case .Sequence, .Conflict:
		descriptor, described := ksawery.sequence_observation_descriptor(&state.sequence)
		if !described do return nil, {}, false
		observation = {family = family, repository = descriptor.repository, generation = u64(descriptor.generation)}
	case .Process:
		records := ksawery_workflow_process_records(state)
		_, described := ksawery.process_surface_descriptor(records)
		if !described do return nil, {}, false
		observation = {
			family = family,
			repository = state.repository,
			generation = ksawery_extension_process_annotation_generation(records),
		}
	}
	generation = ksawery_extension_annotation_generation(&state.extension_registry, family)
	if !ksawery_extension_annotation_generation_is_visible(generation, observation) {
		return nil, {}, false
	}
	return generation, observation, true
}

/* ksawery_extension_annotation_reconcile_selection drops view-local or stale selections. */
ksawery_extension_annotation_reconcile_selection :: proc(state: ^Ksawery_Workflow_State) {
	if state == nil || !state.extension_annotation_selection.valid do return
	generation, _, ready := ksawery_extension_annotation_active_context(state)
	if !ready {
		state.extension_annotation_selection = {}
		return
	}
	_, selected := ksawery_extension_annotation_selected_command(
		generation, state.extension_annotation_selection,
	)
	if !selected do state.extension_annotation_selection = {}
}

@(private)
ksawery_extension_annotation_generation_is_visible :: proc(
	generation: ^ksawery.Extension_Annotation_Generation,
	observation: ksawery.Extension_Annotation_Observation,
) -> bool {
	if generation == nil do return false
	_, failure := ksawery.extension_annotation_generation_validate(generation^)
	if failure.code != .None do return false
	matched, _ := ksawery.extension_annotation_generation_matches_observation(
		generation^, observation,
	)
	return matched
}

@(private)
ksawery_extension_annotation_selection_matches :: proc(
	selection: Ksawery_Extension_Annotation_Selection,
	generation: ksawery.Extension_Annotation_Generation,
	annotation: ksawery.Extension_Annotation,
) -> bool {
	return selection.valid && selection.contributor == generation.contributor_identity &&
		selection.annotation == annotation.id && selection.target == annotation.target &&
		selection.observation_family == generation.observation.family &&
		selection.observation_generation == generation.observation.generation
}

@(private)
ksawery_extension_annotation_label :: proc(annotation: ksawery.Extension_Annotation) -> string {
	identity := annotation.identity
	label := string(identity.bytes[:identity.length])
	if annotation.label_present {
		label_copy := annotation.label
		label = string(label_copy.bytes[:label_copy.length])
	}
	detail_copy := annotation.detail
	if detail_copy.length > 0 {
		label = fmt.tprintf("%s: %s", label, string(detail_copy.bytes[:detail_copy.length]))
	}
	label = fmt.tprintf("  [%s]", label)
	if len(label) <= KSAWERY_LIST_ROW_BYTES do return label
	end := KSAWERY_LIST_ROW_BYTES - 3
	for end > 0 && !utf8.rune_start(label[end]) do end -= 1
	return fmt.tprintf("%s...", label[:end])
}

@(private)
ksawery_extension_annotation_style_role :: proc(
	annotation: ksawery.Extension_Annotation,
) -> ui.Style_Role {
	switch annotation.severity {
	case .Error:       return .Diagnostic_Error
	case .Warning:     return .Diagnostic_Warning
	case .Information: return .Diagnostic_Information
	case .Hint:        return .Diagnostic_Hint
	case .None:
	}
	switch annotation.style {
	case .Normal:      return .List_Normal
	case .Muted:       return .Filesystem_Metadata
	case .Identity:    return .Status_Identity
	case .Active:      return .Status_Active
	case .Success:     return .List_Mark_Save
	case .Warning:     return .Diagnostic_Warning
	case .Alert:       return .Status_Alert
	case .Information: return .Diagnostic_Information
	case .None:        return .List_Normal
	}
	return .List_Normal
}

@(private)
ksawery_extension_annotation_ui_id :: proc(
	family: ksawery.Extension_Observation_Family,
	ordinal: u32,
) -> ui.List_Item_ID {
	return ui.List_Item_ID(
		0xA200_0000_0000_0000 | (u64(family) << 48) | u64(ordinal) + 1,
	)
}
