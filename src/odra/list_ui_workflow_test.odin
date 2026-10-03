// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../interaction"
import "../project"
import "../ui"
import "base:runtime"
import "core:strings"
import "core:testing"

/* Verifies copied language inspection fields project as bounded shared-UI rows. */
@(test)
language_rows_cover_provider_state :: proc(t: ^testing.T) {
	state := Language_State_Workflow_State {
		ready = true,
		next_model_generation = 4,
		inspection = {
			buffer_id = 31,
			document_id = 32,
			has_document = true,
			association = {
				language = {id = 1, generation = 2},
				source = .Factory_Filename_Suffix,
			},
			selection = {
				registry_id = 1,
				registry_generation = 3,
				state = .Factory,
				active = {provider_id = 4, provider_generation = 5},
				factory = {provider_id = 4, provider_generation = 5},
			},
			selection_generation = 6,
			confirmed_revision = 7,
			parser_lifecycle = .Ready,
			analysis_status = .Current,
			parse_snapshot = {
				source_revision = 7,
				provider = {provider_generation = 5},
				parser_generation = 8,
				tree_generation = 9,
				query_generation = 10,
			},
			syntax_snapshot = {generation = 11, source_revision = 7, span_count = 12},
			usage = {retained_source_bytes = 13, retained_tree_bytes = 14, captures = 15, spans = 12},
			latest_failure = {operation = .Publish_Syntax, code = .Span_Limit, limit = 16, actual = 17},
		},
		provider = {
			kind = .Factory,
			state = .Confirmed,
			grammar_abi = 14,
			capabilities = {.Initial_Parse, .Incremental_Parse, .Visible_Query, .Syntax_Roles},
		},
		provider_found = true,
	}
	copy(state.inspection.association.language.name.bytes[:], transmute([]u8)string("odin"))
	state.inspection.association.language.name.length = 4
	copy(state.inspection.association.value.bytes[:], transmute([]u8)string(".odin"))
	state.inspection.association.value.length = 5
	copy(state.provider.name.bytes[:], transmute([]u8)string("factory-odin-tree-sitter"))
	state.provider.name.length = 24
	copy(state.provider.parser_name.bytes[:], transmute([]u8)string("tree-sitter-odin"))
	state.provider.parser_name.length = 16
	copy(state.provider.provenance.bytes[:], transmute([]u8)string("pinned factory sources"))
	state.provider.provenance.length = 22
	testing.expect(t, language_state_workflow_advance_generation(&state))
	prepared, prepare_failure := language_state_workflow_prepare(&state, 8)
	testing.expectf(t, prepared, "language-state preparation failed with %v", prepare_failure.code)
	items, storage, projected := language_state_list_definitions(
		&state,
		ui.Renderer_Profile {
			id = 1,
			capabilities = {.Semantic_Attributes, .Full_Redraw},
			color = .True_Color,
			attributes = {.Bold, .Reverse},
		},
		context.temp_allocator,
	)
	testing.expect(t, projected)
	if projected {
		defer delete(items, context.temp_allocator)
		defer delete(storage, context.temp_allocator)
		testing.expect_value(t, len(items), LANGUAGE_STATE_ROW_COUNT)
		testing.expect(t, strings.contains(items[0].text, "Language: odin"))
		testing.expect(t, strings.contains(items[2].text, "factory-odin-tree-sitter"))
		testing.expect(t, strings.contains(items[4].text, "confirmed=7"))
		testing.expect(t, strings.contains(items[8].text, "True_Color"))
		testing.expect(t, strings.contains(items[10].text, "source=13 tree=14"))
		testing.expect(t, strings.contains(items[13].text, "Span_Limit"))
	}
}

@(private)
list_ui_test_project_handle :: proc(generation: project.Project_Generation) -> project.Project_Handle {
	return project.Project_Handle {
		owner = {id = 1, generation = 1},
		id = 7,
		generation = generation,
	}
}

@(private)
list_ui_test_project_name :: proc(text: string) -> project.Project_Name {
	name: project.Project_Name
	copy(name.bytes[:], transmute([]u8)text)
	name.length = u32(len(text))
	return name
}

@(private)
list_ui_test_directory_path :: proc(text: string) -> project.Directory_Path {
	path: project.Directory_Path
	copy(path.bytes[:], transmute([]u8)text)
	path.length = u32(len(text))
	return path
}

@(private)
list_ui_test_membership :: proc(
	id: project.Membership_ID,
	slot: u32,
	project_generation: project.Project_Generation,
	path: string,
) -> project.Membership_Descriptor {
	return project.Membership_Descriptor {
		handle = {
			project = list_ui_test_project_handle(project_generation),
			id = id,
			slot = slot,
			generation = 3,
		},
		path = list_ui_test_directory_path(path),
		trust = .Trusted,
		availability = .Available,
	}
}

@(test)
/* project_list_workflow_preserves_semantic_selection_across_refresh. */
project_list_keeps_selection_on_refresh :: proc(t: ^testing.T) {
	descriptors := [2]project.Membership_Descriptor {
		list_ui_test_membership(11, 0, 1, "/work/first"),
		list_ui_test_membership(12, 1, 1, "/work/second"),
	}
	sentinel: u8
	state := Project_Workflow_State {
		directory_candidates = {state = rawptr(&sentinel), descriptors = descriptors[:]},
		list_mode = .Inventory,
		list_project = {
			handle = list_ui_test_project_handle(1),
			name = list_ui_test_project_name("Odra"),
			directory_count = 2,
		},
		list_model_generation = 4,
		list_next_model_generation = 4,
	}
	prepared, prepare_failure := project_list_workflow_prepare(&state, 2)
	testing.expectf(t, prepared, "Project list preparation failed with %v", prepare_failure.code)
	items, storage, projected := project_list_definitions(&state, context.temp_allocator)
	testing.expect(t, projected)
	if projected {
		defer delete(items, context.temp_allocator)
		defer delete(storage, context.temp_allocator)
		testing.expect_value(t, len(items), 3)
		testing.expect(t, strings.contains(items[0].text, "Odra [local Project; one root]"))
		testing.expect(t, strings.contains(items[1].text, "/work/first"))
		testing.expect(t, strings.contains(items[2].text, "/work/second"))
		testing.expect_value(t, items[2].action.generation, u64(4))
	}
	moved, move_ok, move_failure := project_list_workflow_move(&state, 2)
	testing.expectf(t, moved && move_ok, "Project list move failed with %v", move_failure.code)
	testing.expect_value(t, state.list_current_membership.id, project.Membership_ID(12))

	refreshed := [2]project.Membership_Descriptor {
		list_ui_test_membership(12, 1, 2, "/work/second"),
		list_ui_test_membership(11, 0, 2, "/work/first"),
	}
	state.directory_candidates.descriptors = refreshed[:]
	testing.expect(t, project_list_workflow_advance_generation(&state))
	refreshed_ok, refresh_failure := project_list_workflow_prepare(&state, 1)
	testing.expectf(t, refreshed_ok, "Project list refresh failed with %v", refresh_failure.code)
	testing.expect_value(t, state.list_position.current_item, i32(1))
	testing.expect_value(
		t,
		state.list_current_membership.project.generation,
		project.Project_Generation(2),
	)
	previous_generation := state.list_model_generation
	project_list_workflow_reset(&state)
	testing.expect_value(t, state.list_next_model_generation, previous_generation)
	state.list_mode = .Inventory
	_, stale_failure := project_list_workflow_prepare(&state, 1)
	testing.expect_value(t, stale_failure.code, ui.Failure_Code.Invalid_List_View)
	testing.expect(t, project_list_workflow_advance_generation(&state))
	testing.expect_value(t, state.list_model_generation, previous_generation + 1)
	state.list_next_model_generation = max(u64)
	testing.expect(t, !project_list_workflow_advance_generation(&state))
}

@(test)
/* keymap_inspection_list_retains_records_empty_state_bounds_and_generations. */
keymap_list_keeps_records_and_bounds :: proc(t: ^testing.T) {
	records := [3]interaction.Inspection_Record {
		{
			kind = .Map,
			disposition = .Effective,
			map_identity = {id = 31, revision = 4},
			map_name = "project-tools",
			owner = {id = 41, generation = 2},
			precedence = .Project,
			priority = 7,
			provenance = {provider = "racket", source = "project/keymaps.rkt"},
		},
		{kind = .Snapshot},
		{
			kind = .Rejection,
			failure = {
				code = .Ambiguous_Binding,
				profile = {id = 5, revision = 2},
				map_identity = {id = 31, revision = 4},
				ctx = {id = 8, generation = 3},
			},
		},
	}
	sentinel: u8
	state := Keymap_Inspection_Workflow_State {
		inspection = {
			state = rawptr(&sentinel),
			records = records[:],
			snapshot = {
				generation = 13,
				registry_generation = 17,
				profile = {id = 5, revision = 2},
				ctx = {id = 8, generation = 3},
			},
			usage = {map_count = 3, active_map_count = 2, binding_count = 9},
		},
		catalog = {state = rawptr(&sentinel)},
		next_model_generation = 6,
	}
	testing.expect(t, keymap_inspection_workflow_advance_generation(&state))
	prepared, prepare_failure := keymap_inspection_workflow_prepare(&state, 2)
	testing.expectf(t, prepared, "inspection list preparation failed with %v", prepare_failure.code)
	items, storage, projected := keymap_inspection_list_definitions(&state, context.temp_allocator)
	testing.expect(t, projected)
	if projected {
		defer delete(items, context.temp_allocator)
		defer delete(storage, context.temp_allocator)
		testing.expect_value(t, len(items), 3)
		testing.expect(t, strings.contains(items[0].text, "map project-tools@4"))
		testing.expect(t, strings.contains(items[0].text, "source racket/project/keymaps.rkt"))
		testing.expect(t, strings.contains(items[1].text, "profile 5@2 registry 17 snapshot 13"))
		testing.expect(t, strings.contains(items[2].text, "rejected Ambiguous_Binding"))
		testing.expect_value(t, items[0].action.generation, u64(7))
	}
	moved, move_ok, move_failure := keymap_inspection_workflow_move(&state, 2)
	testing.expectf(t, moved && move_ok, "inspection list move failed with %v", move_failure.code)
	testing.expect_value(t, state.position.current_item, i32(2))
	old_generation := state.model_generation
	testing.expect(t, keymap_inspection_workflow_advance_generation(&state))
	testing.expect_value(t, state.model_generation, old_generation + 1)
	state.next_model_generation = max(u64)
	testing.expect(t, !keymap_inspection_workflow_advance_generation(&state))

	state.inspection.records = nil
	empty_items, empty_storage, empty_ok := keymap_inspection_list_definitions(
		&state,
		context.temp_allocator,
	)
	testing.expect(t, empty_ok)
	if empty_ok {
		defer delete(empty_items, context.temp_allocator)
		defer delete(empty_storage, context.temp_allocator)
		testing.expect_value(t, len(empty_items), 1)
		testing.expect_value(t, empty_items[0].text, "No matching keymap definitions.")
	}
	_, invalid_viewport_failure := keymap_inspection_workflow_prepare(
		&state,
		ui.MAX_LIST_ITEMS + 1,
	)
	testing.expect_value(t, invalid_viewport_failure.code, ui.Failure_Code.Invalid_List_View)
	_, _, allocation_ok := keymap_inspection_list_definitions(&state, runtime.Allocator{})
	testing.expect(t, !allocation_ok)
}

/* Verifies built-in help topics reuse the read-only inspection surface without registry state. */
@(test)
keymap_list_projects_bounded_help_topics :: proc(t: ^testing.T) {
	state := Keymap_Inspection_Workflow_State {
		presentation = .Help,
		next_model_generation = 2,
	}
	testing.expect(t, keymap_inspection_workflow_advance_generation(&state))
	prepared, prepare_failure := keymap_inspection_workflow_prepare(&state, 4)
	testing.expectf(t, prepared, "help list preparation failed with %v", prepare_failure.code)
	items, storage, projected := keymap_inspection_list_definitions(&state, context.temp_allocator)
	testing.expect(t, projected)
	if projected {
		defer delete(items, context.temp_allocator)
		defer delete(storage, context.temp_allocator)
		testing.expect_value(t, len(items), 11)
		testing.expect(t, strings.contains(items[0].text, "Odra Help"))
		testing.expect(t, strings.contains(items[3].text, "User Guide"))
		testing.expect(t, strings.contains(items[10].text, "C-h t"))
	}
	moved, move_ok, move_failure := keymap_inspection_workflow_move(&state, 10)
	testing.expectf(t, moved && move_ok, "help list move failed with %v", move_failure.code)
	testing.expect_value(t, state.position.current_item, i32(10))

	state.presentation = .Tutorial
	state.position = {}
	prepared, prepare_failure = keymap_inspection_workflow_prepare(&state, 4)
	testing.expectf(t, prepared, "tutorial preparation failed with %v", prepare_failure.code)
	items, storage, projected = keymap_inspection_list_definitions(&state, context.temp_allocator)
	testing.expect(t, projected)
	if projected {
		defer delete(items, context.temp_allocator)
		defer delete(storage, context.temp_allocator)
		testing.expect_value(t, len(items), 12)
		testing.expect(t, strings.contains(items[0].text, "Odra Tutorial"))
	}
}
