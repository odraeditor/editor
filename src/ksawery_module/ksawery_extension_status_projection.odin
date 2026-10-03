// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import "../ksawery"
import "../ui"
import "core:fmt"
import "core:unicode/utf8"

/* KSAWERY_EXTENSION_STATUS_SECTION_CAPACITY bounds flattened presentation ordering. */
KSAWERY_EXTENSION_STATUS_SECTION_CAPACITY :: 512

/* Ksawery_Extension_Status_Selection retains semantic extension identity, never a row. */
Ksawery_Extension_Status_Selection :: struct {
	valid:                  bool,
	contributor:            ksawery.Contributor_Identity,
	section:                ksawery.Extension_Identity,
	item:                   ksawery.Extension_Status_Item_ID,
	observation_generation: ksawery.Observation_Generation,
}

@(private)
Ksawery_Extension_Status_Section_Reference :: struct {
	generation: u16,
	section:    u16,
}

/* ksawery_extension_status_visible_row_count counts one deterministic visible area. */
ksawery_extension_status_visible_row_count :: proc(
	generations: []ksawery.Extension_Status_Generation,
	descriptor: ksawery.Observation_Descriptor,
) -> int {
	references, count := ksawery_extension_status_ordered_sections(generations, descriptor)
	if count == 0 do return 0
	rows := 1
	for reference in references[:count] {
		section := generations[reference.generation].sections[reference.section]
		rows += 1 + len(section.items)
	}
	return rows
}

/* ksawery_extension_status_append appends Extensions after all core Status groups. */
ksawery_extension_status_append :: proc(
	rows: []ui.List_Item_Definition,
	storage: []u8,
	write: ^int,
	generations: []ksawery.Extension_Status_Generation,
	descriptor: ksawery.Observation_Descriptor,
	selection: Ksawery_Extension_Status_Selection,
) -> (current_row: i32, complete: bool) {
	if write == nil do return -1, false
	current_row = -1
	references, section_count := ksawery_extension_status_ordered_sections(generations, descriptor)
	if section_count == 0 do return -1, true
	if !ksawery_append_presented_label(
		rows,
		storage,
		write,
		ksawery_extension_status_section_ui_id(0),
		"Extensions",
		true,
		{surface = .Status, subject = .Section},
	) {
		return -1, false
	}
	item_ordinal: u32
	for reference, visible_section in references[:section_count] {
		generation := generations[reference.generation]
		section := generation.sections[reference.section]
		label_copy := section.label
		label := string(label_copy.bytes[:label_copy.length])
		if section.truncation != .Complete {
			label = fmt.tprintf("%s [truncated: %s]", label, ksawery_extension_status_truncation_label(section.truncation))
		}
		if !ksawery_append_presented_label(
			rows,
			storage,
			write,
			ksawery_extension_status_section_ui_id(u32(visible_section) + 1),
			ksawery_extension_status_bounded_label(label),
			true,
			{surface = .Status, subject = .Section},
		) {
			return current_row, false
		}
		for item in section.items {
			row := write^
			if !ksawery_extension_status_append_item(rows, storage, write, item, item_ordinal) {
				return current_row, false
			}
			if ksawery_extension_status_selection_matches(selection, generation, section, item) {
				current_row = i32(row)
			}
			item_ordinal += 1
		}
	}
	return current_row, true
}

/* ksawery_extension_status_select_ui_item resolves a row to exact semantic identity. */
ksawery_extension_status_select_ui_item :: proc(
	generations: []ksawery.Extension_Status_Generation,
	descriptor: ksawery.Observation_Descriptor,
	id: ui.List_Item_ID,
	selection: ^Ksawery_Extension_Status_Selection,
) -> bool {
	if selection == nil do return false
	references, section_count := ksawery_extension_status_ordered_sections(generations, descriptor)
	item_ordinal: u32
	for reference in references[:section_count] {
		generation := generations[reference.generation]
		section := generation.sections[reference.section]
		for item in section.items {
			if ksawery_extension_status_item_ui_id(item_ordinal) == id {
				selection^ = {
					valid = true,
					contributor = generation.contributor_identity,
					section = section.identity,
					item = item.id,
					observation_generation = descriptor.generation,
				}
				return true
			}
			item_ordinal += 1
		}
	}
	return false
}

/* ksawery_extension_status_selected_command resolves one admitted selected command. */
ksawery_extension_status_selected_command :: proc(
	generations: []ksawery.Extension_Status_Generation,
	descriptor: ksawery.Observation_Descriptor,
	selection: Ksawery_Extension_Status_Selection,
) -> (string, bool) {
	if !selection.valid || selection.observation_generation != descriptor.generation do return "", false
	for &generation in generations {
		if generation.repository != descriptor.repository ||
		   generation.observation_generation != descriptor.generation ||
		   generation.contributor_identity != selection.contributor {
			continue
		}
		for &section in generation.sections {
			if section.identity != selection.section do continue
			for &item in section.items {
				if item.id != selection.item || !item.command.present do continue
				identity := &item.command.identity
				return string(identity.bytes[:identity.length]), true
			}
		}
	}
	return "", false
}

@(private)
ksawery_extension_status_ordered_sections :: proc(
	generations: []ksawery.Extension_Status_Generation,
	descriptor: ksawery.Observation_Descriptor,
) -> (references: [KSAWERY_EXTENSION_STATUS_SECTION_CAPACITY]Ksawery_Extension_Status_Section_Reference, count: int) {
	for generation, generation_index in generations {
		if generation.repository != descriptor.repository ||
		   generation.observation_generation != descriptor.generation {
			continue
		}
		_, failure := ksawery.extension_status_generation_validate(generation)
		if failure.code != .None do continue
		for section, section_index in generation.sections {
			if !ksawery.extension_status_section_is_visible(section) do continue
			if count >= len(references) do return
			references[count] = {
				generation = u16(generation_index),
				section = u16(section_index),
			}
			count += 1
		}
	}
	for index in 1 ..< count {
		candidate := references[index]
		cursor := index
		for cursor > 0 && ksawery_extension_status_reference_is_less(candidate, references[cursor - 1], generations) {
			references[cursor] = references[cursor - 1]
			cursor -= 1
		}
		references[cursor] = candidate
	}
	return
}

@(private)
ksawery_extension_status_reference_is_less :: proc(
	a, b: Ksawery_Extension_Status_Section_Reference,
	generations: []ksawery.Extension_Status_Generation,
) -> bool {
	a_section := generations[a.generation].sections[a.section]
	b_section := generations[b.generation].sections[b.section]
	return ksawery.extension_status_order_key_is_less(
		ksawery.extension_status_order_key(a_section),
		ksawery.extension_status_order_key(b_section),
	)
}

@(private)
ksawery_extension_status_append_item :: proc(
	rows: []ui.List_Item_Definition,
	storage: []u8,
	write: ^int,
	item: ksawery.Extension_Status_Item,
	ordinal: u32,
) -> bool {
	if write == nil || write^ >= len(rows) do return false
	text_copy := item.text
	label := fmt.tprintf("  %s", string(text_copy.bytes[:text_copy.length]))
	label = ksawery_extension_status_bounded_label(label)
	offset := write^ * KSAWERY_LIST_ROW_BYTES
	copy(storage[offset:offset + len(label)], transmute([]u8)label)
	rows[write^] = {
		id = ksawery_extension_status_item_ui_id(ordinal),
		text = string(storage[offset:offset + len(label)]),
		passive = false,
		emphasis_bytes = u32(len(label)),
		emphasis_style = ksawery_extension_status_style_role(item.style),
		action = {
			owner_id = KSAWERY_UI_OWNER_ID,
			action_id = KSAWERY_LIST_SELECT_ACTION,
			generation = KSAWERY_UI_TARGET_GENERATION,
		},
	}
	write^ += 1
	return true
}

@(private)
ksawery_extension_status_selection_matches :: proc(
	selection: Ksawery_Extension_Status_Selection,
	generation: ksawery.Extension_Status_Generation,
	section: ksawery.Extension_Status_Section,
	item: ksawery.Extension_Status_Item,
) -> bool {
	return selection.valid &&
		selection.contributor == generation.contributor_identity &&
		selection.section == section.identity &&
		selection.item == item.id &&
		selection.observation_generation == generation.observation_generation
}

@(private)
ksawery_extension_status_style_role :: proc(style: ksawery.Extension_Status_Style) -> ui.Style_Role {
	switch style {
	case .Normal: return .List_Normal
	case .Muted: return .Filesystem_Metadata
	case .Identity: return .Status_Identity
	case .Active: return .Status_Active
	case .Success: return .List_Mark_Save
	case .Warning: return .Diagnostic_Warning
	case .Alert: return .Status_Alert
	case .Information: return .Diagnostic_Information
	case .Invalid: return .Diagnostic_Rejected
	}
	return .Diagnostic_Rejected
}

@(private)
ksawery_extension_status_truncation_label :: proc(truncation: ksawery.Extension_Status_Truncation) -> string {
	switch truncation {
	case .Item_Limit: return "item limit"
	case .Metadata_Limit: return "metadata limit"
	case .Text_Limit: return "text limit"
	case .Provider_Limit: return "provider limit"
	case .Complete: return "complete"
	case .Invalid: return "invalid"
	}
	return "invalid"
}

@(private)
ksawery_extension_status_bounded_label :: proc(label: string) -> string {
	if len(label) <= KSAWERY_LIST_ROW_BYTES do return label
	end := KSAWERY_LIST_ROW_BYTES - 3
	for end > 0 && !utf8.rune_start(label[end]) do end -= 1
	return fmt.tprintf("%s...", label[:end])
}

@(private)
ksawery_extension_status_section_ui_id :: proc(ordinal: u32) -> ui.List_Item_ID {
	return ui.List_Item_ID(0xA000_0000_0000_0000 | u64(ordinal) + 1)
}

@(private)
ksawery_extension_status_item_ui_id :: proc(ordinal: u32) -> ui.List_Item_ID {
	return ui.List_Item_ID(0xA100_0000_0000_0000 | u64(ordinal) + 1)
}
