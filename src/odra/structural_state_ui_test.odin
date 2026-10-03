// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../language"
import editor_view "../view"
import "core:strings"
import "core:testing"

/* Verifies structural inspection copies every active identity, result, limit, and rejection. */
@(test)
structural_list_reports_copied_state :: proc(t: ^testing.T) {
	kind: language.Structural_Node_Kind
	kind.length = u16(copy(kind.bytes[:], "procedure"))
	scope := language.Structural_Scope {
		buffer_id = 71,
		source_revision = 9,
		language = {id = 1, generation = 2},
		provider = {
			registry_id = 3,
			language_id = 1,
			provider_id = 4,
			provider_generation = 5,
		},
		selection_generation = 6,
		parser_generation = 7,
		tree_generation = 8,
	}
	state := Structural_State_Workflow_State {
		available = true,
		scope = scope,
		logical = editor_view.Snapshot {
			view_id = 11,
			view_generation = 12,
			selection_generation = 13,
			point_position = {byte_offset = 21},
			mark = {present = true, position = {byte_offset = 15}},
			region_active = true,
		},
		command_state = command.Structural_Capability_State {
			last_target = {scope = scope, start = 14, end = 31, kind = kind, depth = 2},
			plan_start = 10,
			plan_end = 40,
			plan_edit_count = 3,
			last_operation = .Select,
			last_completion = .View_Changed,
			last_changed = true,
			usage = {
				visited_nodes = 18,
				visited_depth = 3,
				indent_lines = 2,
				prepared_bytes = 8,
				temporary_bytes = 256,
			},
			latest_failure = {
				code = .Capability_Failure,
				structural_code = .Stale_Analysis,
				revision = 9,
				limit = 8,
				actual = 9,
			},
		},
		capability_generation = 14,
		ready = true,
		model_generation = 1,
	}
	message := "analysis changed"
	copy(state.command_state.diagnostic[:], transmute([]u8)message)
	state.command_state.diagnostic_length = u16(len(message))
	items, storage, built := structural_state_list_definitions(&state, context.allocator)
	testing.expect(t, built)
	if !built do return
	defer delete(items)
	defer delete(storage)
	testing.expect_value(t, len(items), STRUCTURAL_STATE_ROW_COUNT)
	testing.expect(t, strings.contains(items[0].text, "available=true"))
	testing.expect(t, strings.contains(items[1].text, "buffer=71 revision=9"))
	testing.expect(t, strings.contains(items[4].text, "indentation=4 spaces"))
	testing.expect(t, strings.contains(items[5].text, "point=21 mark=15"))
	testing.expect(t, strings.contains(items[6].text, "kind=procedure range=14..31"))
	testing.expect(t, strings.contains(items[9].text, "nodes=18 depth=3"))
	testing.expect(t, strings.contains(items[11].text, "inspection=1048576"))
	testing.expect(t, strings.contains(items[12].text, "analysis changed"))
}

/* Verifies the shared list position remains bounded across structural inspection movement. */
@(test)
structural_state_list_navigation_is_bounded :: proc(t: ^testing.T) {
	state := Structural_State_Workflow_State {
		ready = true,
		model_generation = 1,
	}
	prepared, _ := structural_state_workflow_prepare(&state, 4)
	testing.expect(t, prepared)
	_, moved, _ := structural_state_workflow_move(&state, -1)
	testing.expect(t, moved)
	testing.expect_value(t, state.position.current_item, i32(0))
	for _ in 0 ..< STRUCTURAL_STATE_ROW_COUNT + 2 {
		_, _, _ = structural_state_workflow_move(&state, 1)
	}
	testing.expect_value(t, state.position.current_item, i32(STRUCTURAL_STATE_ROW_COUNT - 1))
}
