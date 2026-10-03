// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../display"
import "../editor"
import "../history"
import "../language"
import edit_transaction "../transaction"
import editor_view "../view"
import "core:strings"
import "core:testing"

@(private)
Structural_Editor_Test_Fixture :: struct {
	buffer:        editor.Buffer,
	source:        editor.Buffer_Snapshot,
	owner:         language.Tree_Sitter_Owner,
	views:         editor_view.Registry,
	view:          editor_view.View_Handle,
	second_view:   editor_view.View_Handle,
	history:       history.Store,
	analysis:      language.Structural_Scope,
	ctx:           Structural_Editor_Context,
	ready:         bool,
}

@(private)
structural_editor_test_open :: proc(
	t: ^testing.T,
	fixture: ^Structural_Editor_Test_Fixture,
	buffer_id: editor.Buffer_ID,
	contents: string,
) -> bool {
	fixture^ = {}
	buffer_ok, _ := editor.buffer_init(
		&fixture.buffer,
		buffer_id,
		contents,
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	source_ok, _ := editor.buffer_snapshot_open(&fixture.buffer, &fixture.source)
	owner_ok, _ := language.tree_sitter_owner_init(&fixture.owner, 3)
	query_ok, _ := language.tree_sitter_owner_compile_odin_query(&fixture.owner, 5)
	language_identity := language.Language_Identity{id = 1, generation = 1}
	provider := language.Provider_Handle {
		registry_id = 1,
		language_id = language_identity.id,
		provider_id = 1,
		provider_generation = 1,
	}
	parsed, parse_ok, _ := language.tree_sitter_owner_parse_snapshot(
		&fixture.owner,
		&fixture.source,
		language_identity,
		provider,
		7,
		11,
	)
	views_ok, _ := editor_view.registry_init(
		&fixture.views,
		editor_view.Registry_ID(u32(buffer_id)),
		context.allocator,
	)
	view_ok := false
	second_ok := false
	if views_ok {
		fixture.view, view_ok, _ = editor_view.create(&fixture.views, &fixture.buffer)
	}
	if view_ok {
		fixture.second_view, second_ok, _ = editor_view.clone_additional(
			&fixture.views,
			fixture.view,
		)
	}
	history_ok, _ := history.store_init(
		&fixture.history,
		history.Store_ID(u32(buffer_id)),
		buffer_id,
		0,
		history.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	ready := buffer_ok && source_ok && owner_ok && query_ok && parse_ok && views_ok &&
		view_ok && second_ok && history_ok
	testing.expect(t, ready)
	if !ready {
		return false
	}
	fixture.analysis = language.Structural_Scope {
		buffer_id = parsed.buffer_id,
		source_revision = parsed.source_revision,
		language = parsed.language,
		provider = parsed.provider,
		selection_generation = parsed.selection_generation,
		parser_generation = parsed.parser_generation,
		tree_generation = parsed.tree_generation,
	}
	fixture.ctx = Structural_Editor_Context {
		native = Native_Context {
			buffer = &fixture.buffer,
			view_registry = &fixture.views,
			view = fixture.view,
			profile = display.terminal_unicode17_profile(),
			constraints = display.Viewport_Constraints{width_cells = 20, height_rows = 4},
			temporary_allocator = context.temp_allocator,
			persistent_allocator = context.allocator,
			transaction_id = 100,
			undo_unit_id = 100,
			history_store = &fixture.history,
			history_grouping = history.Grouping_Context{kind = .Independent},
		},
		owner = &fixture.owner,
		source = &fixture.source,
		scope = fixture.analysis,
	}
	fixture.ready = true
	return true
}

@(private)
structural_editor_test_close :: proc(fixture: ^Structural_Editor_Test_Fixture) {
	if fixture == nil do return
	if fixture.second_view.view_id != editor_view.View_ID(0) {
		editor_view.close(&fixture.views, &fixture.second_view)
	}
	if fixture.view.view_id != editor_view.View_ID(0) {
		editor_view.close(&fixture.views, &fixture.view)
	}
	if fixture.ready {
		history.store_close(&fixture.history)
		editor_view.registry_close(&fixture.views)
		language.tree_sitter_owner_close(&fixture.owner)
		editor.buffer_snapshot_close(&fixture.source)
		editor.buffer_close(&fixture.buffer)
	}
	fixture^ = {}
}

@(private)
structural_editor_test_run :: proc(
	fixture: ^Structural_Editor_Test_Fixture,
	operation: language.Structural_Operation,
) -> (Structural_Editor_Result, bool, Failure_Context) {
	scope, scoped, scope_failure := structural_editor_scope(fixture.ctx)
	if !scoped do return {}, false, scope_failure
	return structural_editor_run(
		fixture.ctx,
		Structural_Editor_Request{expected_scope = scope, operation = operation},
	)
}

@(private)
structural_editor_test_text :: proc(buffer: ^editor.Buffer) -> string {
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	if !stats_ok do return ""
	bytes := make([]byte, int(stats.text_bytes), context.temp_allocator)
	defer delete(bytes, context.temp_allocator)
	_, inspected, _ := editor.buffer_inspect(buffer, 0, editor.Byte_Offset(stats.text_bytes), bytes)
	if !inspected do return ""
	result, _ := strings.clone_from_bytes(bytes, context.temp_allocator)
	return result
}

/* Verifies copied navigation targets publish checked points and boundary no-ops. */
@(test)
structural_navigation_handles_boundaries :: proc(t: ^testing.T) {
	contents := "package demo\nmain :: proc() {\n    alpha := 1\n    beta := 2\n}\n"
	fixture: Structural_Editor_Test_Fixture
	if !structural_editor_test_open(t, &fixture, 801, contents) do return
	defer structural_editor_test_close(&fixture)
	alpha_offset := editor.Byte_Offset(strings.index(contents, "alpha"))
	alpha, _, alpha_ok, _ := language.tree_sitter_owner_query_structure(
		&fixture.owner,
		&fixture.source,
		language.Structural_Request {
			operation = .Select,
			scope = fixture.analysis,
			point = alpha_offset,
			start = alpha_offset,
			end = alpha_offset,
		},
	)
	testing.expect(t, alpha_ok)
	if !alpha_ok do return
	start, _, _ := editor.buffer_position(&fixture.buffer, alpha.start)
	end, _, _ := editor.buffer_position(&fixture.buffer, alpha.end)
	editor_view.select_range(&fixture.views, fixture.view, start, end, 0)
	up, up_ok, up_failure := structural_editor_test_run(&fixture, .Up)
	testing.expectf(t, up_ok, "up failed with %v/%v", up_failure.structural_code, up_failure.language_code)
	if up_ok {
		logical, _, _ := editor_view.snapshot(&fixture.views, fixture.view)
		testing.expect_value(t, logical.point_position.byte_offset, up.target.start)
		testing.expect_value(t, logical.desired_display_column, u32(4))
		structural_editor_result_close(&up)
	}
	expanded := alpha
	for {
		kind := string(expanded.kind.bytes[:int(expanded.kind.length)])
		if kind == "block" do break
		next, _, next_ok, _ := language.tree_sitter_owner_query_structure(
			&fixture.owner,
			&fixture.source,
			language.Structural_Request {
				operation = .Select,
				scope = fixture.analysis,
				point = expanded.end,
				start = expanded.start,
				end = expanded.end,
				has_region = true,
			},
		)
		if !next_ok do break
		expanded = next
	}
	block_start, _, _ := editor.buffer_position(&fixture.buffer, expanded.start)
	block_end, _, _ := editor.buffer_position(&fixture.buffer, expanded.end)
	editor_view.select_range(&fixture.views, fixture.view, block_start, block_end, 0)
	down, down_ok, _ := structural_editor_test_run(&fixture, .Down)
	testing.expect(t, down_ok)
	if down_ok {
		first := down.target
		structural_editor_result_close(&down)
		first_start, _, _ := editor.buffer_position(&fixture.buffer, first.start)
		first_end, _, _ := editor.buffer_position(&fixture.buffer, first.end)
		editor_view.select_range(&fixture.views, fixture.view, first_start, first_end, 0)
		forward, forward_ok, _ := structural_editor_test_run(&fixture, .Forward)
		testing.expect(t, forward_ok)
		if forward_ok {
			testing.expect(t, forward.target.start > first.start)
			next_start, _, _ := editor.buffer_position(&fixture.buffer, forward.target.start)
			next_end, _, _ := editor.buffer_position(&fixture.buffer, forward.target.end)
			editor_view.select_range(&fixture.views, fixture.view, next_start, next_end, 0)
			back, back_ok, _ := structural_editor_test_run(&fixture, .Backward)
			testing.expect(t, back_ok)
			if back_ok {
				testing.expect_value(t, back.target.start, first.start)
				structural_editor_result_close(&back)
			}
			structural_editor_result_close(&forward)
		}
	}
	zero, _, _ := editor.buffer_position(&fixture.buffer, 0)
	editor_view.move_point(&fixture.views, fixture.view, zero, 0, .Deactivate)
	backward, backward_ok, _ := structural_editor_test_run(&fixture, .Backward)
	testing.expect(t, backward_ok)
	if backward_ok {
		testing.expect_value(t, backward.native.completion, Native_Completion.No_Op)
		structural_editor_result_close(&backward)
	}
}

/* Verifies structural selection expands, orders reversed regions, and shares canonical state. */
@(test)
structural_selection_syncs_views :: proc(t: ^testing.T) {
	contents := "package demo\nmain :: proc() {\n    alpha := 1\n}\n"
	fixture: Structural_Editor_Test_Fixture
	if !structural_editor_test_open(t, &fixture, 802, contents) do return
	defer structural_editor_test_close(&fixture)
	alpha_offset := editor.Byte_Offset(strings.index(contents, "alpha"))
	alpha, _, _ := editor.buffer_position(&fixture.buffer, alpha_offset)
	editor_view.move_point(&fixture.views, fixture.view, alpha, 4, .Deactivate)
	selected, selected_ok, _ := structural_editor_test_run(&fixture, .Select)
	testing.expect(t, selected_ok)
	if !selected_ok do return
	first := selected.target
	structural_editor_result_close(&selected)
	expanded, expanded_ok, _ := structural_editor_test_run(&fixture, .Select)
	testing.expect(t, expanded_ok)
	if expanded_ok {
		testing.expect(t, expanded.target.start <= first.start && expanded.target.end >= first.end)
		testing.expect(t, expanded.target.start != first.start || expanded.target.end != first.end)
		primary, _, _ := editor_view.snapshot(&fixture.views, fixture.view)
		secondary, _, _ := editor_view.snapshot(&fixture.views, fixture.second_view)
		testing.expect_value(t, primary.mark.position.byte_offset, expanded.target.start)
		testing.expect_value(t, primary.point_position.byte_offset, expanded.target.end)
		testing.expect_value(t, secondary.effective_point_position.byte_offset, expanded.target.end)
		testing.expect_value(t, secondary.point_position.byte_offset, editor.Byte_Offset(0))
		structural_editor_result_close(&expanded)
	}
	left, _, _ := editor.buffer_position(&fixture.buffer, first.start)
	right, _, _ := editor.buffer_position(&fixture.buffer, first.end)
	editor_view.set_mark(&fixture.views, fixture.view, right, true)
	editor_view.move_point(&fixture.views, fixture.view, left, 4, .Preserve)
	reversed, reversed_ok, _ := structural_editor_test_run(&fixture, .Select)
	testing.expect(t, reversed_ok)
	if reversed_ok {
		testing.expect(t, reversed.target.start <= first.start && reversed.target.end >= first.end)
		structural_editor_result_close(&reversed)
	}
}

/* Verifies definition selection resolves the top-level named declaration containing point. */
@(test)
definition_selects_current_top_level :: proc(t: ^testing.T) {
	contents := "package demo\nmain :: proc() {\n    value := 1\n}\n"
	fixture: Structural_Editor_Test_Fixture
	if !structural_editor_test_open(t, &fixture, 807, contents) do return
	defer structural_editor_test_close(&fixture)
	value_offset := editor.Byte_Offset(strings.index(contents, "value"))
	value, positioned, _ := editor.buffer_position(&fixture.buffer, value_offset)
	if !positioned do return
	editor_view.move_point(&fixture.views, fixture.view, value, 0, .Deactivate)
	selected, selected_ok, selected_failure := structural_editor_test_run(&fixture, .Definition)
	testing.expectf(t, selected_ok, "definition selection failed with %v", selected_failure.code)
	if !selected_ok do return
	defer structural_editor_result_close(&selected)
	testing.expect_value(t, selected.native.completion, Native_Completion.View_Changed)
	testing.expect_value(t, selected.target.start, editor.Byte_Offset(strings.index(contents, "main")))
	testing.expect_value(t, selected.target.end, editor.Byte_Offset(strings.index(contents, "}\n") + 1))
}

/* Verifies indentation is one reversible multi-splice transaction and undo unit. */
@(test)
structural_indentation_is_reversible :: proc(t: ^testing.T) {
	input := "package demo\nmain :: proc() {\nvalue := 1\nif value > 0 {\nvalue += 1\n}\n}\n"
	expected := "package demo\nmain :: proc() {\n    value := 1\n    if value > 0 {\n        value += 1\n    }\n}\n"
	fixture: Structural_Editor_Test_Fixture
	if !structural_editor_test_open(t, &fixture, 803, input) do return
	defer structural_editor_test_close(&fixture)
	start, _, _ := editor.buffer_position(&fixture.buffer, 0)
	end, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(len(input)))
	editor_view.select_range(&fixture.views, fixture.view, start, end, 0)
	indented, indent_ok, indent_failure := structural_editor_test_run(&fixture, .Indent)
	testing.expectf(t, indent_ok, "indent failed with %v/%v", indent_failure.structural_code, indent_failure.language_code)
	if !indent_ok do return
	testing.expect_value(t, indented.native.completion, Native_Completion.Buffer_Committed)
	testing.expect(t, len(indented.native.commit.splices) >= 3)
	actual := structural_editor_test_text(&fixture.buffer)
	testing.expect_value(t, actual, expected)
	delete(actual, context.temp_allocator)
	structural_editor_result_close(&indented)
	undo, undo_ok, _ := edit_transaction.transaction_history_navigate(
		&fixture.history,
		&fixture.buffer,
		.Undo,
		101,
		101,
		edit_transaction.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
		view_registry = &fixture.views,
		invoking_view = fixture.view,
	)
	testing.expect(t, undo_ok && undo.outcome == .Applied)
	undone := structural_editor_test_text(&fixture.buffer)
	testing.expect_value(t, undone, input)
	delete(undone, context.temp_allocator)
	redo, redo_ok, _ := edit_transaction.transaction_history_navigate(
		&fixture.history,
		&fixture.buffer,
		.Redo,
		102,
		102,
		edit_transaction.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
		view_registry = &fixture.views,
		invoking_view = fixture.view,
	)
	testing.expect(t, redo_ok && redo.outcome == .Applied)
	redone := structural_editor_test_text(&fixture.buffer)
	testing.expect_value(t, redone, expected)
	delete(redone, context.temp_allocator)
}

/* Verifies stale, cancellation, and temporary allocation rejection preserve canonical state. */
@(test)
structural_rejections_are_atomic :: proc(t: ^testing.T) {
	input := "package demo\nmain :: proc() {\nvalue := 1\n}\n"
	fixture: Structural_Editor_Test_Fixture
	if !structural_editor_test_open(t, &fixture, 804, input) do return
	defer structural_editor_test_close(&fixture)
	stale_scope, _, _ := structural_editor_scope(fixture.ctx)
	point, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(strings.index(input, "value")))
	editor_view.move_point(&fixture.views, fixture.view, point, 0)
	_, stale_ok, stale_failure := structural_editor_run(
		fixture.ctx,
		Structural_Editor_Request{expected_scope = stale_scope, operation = .Select},
	)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.structural_code, Structural_Editor_Failure_Code.Stale_Selection)
	before := structural_editor_test_text(&fixture.buffer)
	fixture.ctx.native.cancelled = true
	_, cancelled_ok, cancelled_failure := structural_editor_test_run(&fixture, .Indent)
	testing.expect(t, !cancelled_ok)
	testing.expect_value(t, cancelled_failure.code, Failure_Code.Cancelled)
	fixture.ctx.native.cancelled = false
	failing := Native_Failing_Allocator{backing = context.temp_allocator, fail_after = 0}
	fixture.ctx.native.temporary_allocator = native_failing_allocator(&failing)
	_, fault_ok, fault_failure := structural_editor_test_run(&fixture, .Indent)
	testing.expect(t, !fault_ok)
	testing.expect_value(t, fault_failure.language_code, language.Failure_Code.Allocation)
	fixture.ctx.native.temporary_allocator = context.temp_allocator
	history.store_close(&fixture.history)
	history.store_init(
		&fixture.history,
		804,
		804,
		1,
		history.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	_, conflict_ok, conflict_failure := structural_editor_test_run(&fixture, .Indent)
	testing.expect(t, !conflict_ok)
	testing.expect_value(
		t,
		conflict_failure.structural_code,
		Structural_Editor_Failure_Code.Transaction_Rejected,
	)
	after := structural_editor_test_text(&fixture.buffer)
	testing.expect_value(t, after, before)
	delete(before, context.temp_allocator)
	delete(after, context.temp_allocator)
}

/* Verifies syntax-error containment and line limits remain command-level no-publication paths. */
@(test)
syntax_errors_do_not_publish :: proc(t: ^testing.T) {
	error_input := "package demo\nmain :: proc() {\nvalue := (\nother := 1\n}\n"
	error_fixture: Structural_Editor_Test_Fixture
	if structural_editor_test_open(t, &error_fixture, 805, error_input) {
		start, _, _ := editor.buffer_position(&error_fixture.buffer, 0)
		end, _, _ := editor.buffer_position(
			&error_fixture.buffer,
			editor.Byte_Offset(len(error_input)),
		)
		editor_view.select_range(&error_fixture.views, error_fixture.view, start, end, 0)
		result, result_ok, _ := structural_editor_test_run(&error_fixture, .Indent)
		if result_ok do structural_editor_result_close(&result)
		actual := structural_editor_test_text(&error_fixture.buffer)
		testing.expect(t, strings.contains(actual, "\nvalue := (\n"))
		delete(actual, context.temp_allocator)
		structural_editor_test_close(&error_fixture)
	}
	lines := make([]byte, int(language.MAX_STRUCTURAL_INDENT_LINES) + 1)
	defer delete(lines)
	for &byte in lines do byte = '\n'
	limit_fixture: Structural_Editor_Test_Fixture
	if !structural_editor_test_open(t, &limit_fixture, 806, string(lines)) do return
	defer structural_editor_test_close(&limit_fixture)
	start, _, _ := editor.buffer_position(&limit_fixture.buffer, 0)
	end, _, _ := editor.buffer_position(&limit_fixture.buffer, editor.Byte_Offset(len(lines)))
	editor_view.select_range(&limit_fixture.views, limit_fixture.view, start, end, 0)
	_, limit_ok, limit_failure := structural_editor_test_run(&limit_fixture, .Indent)
	testing.expect(t, !limit_ok)
	testing.expect_value(t, limit_failure.language_code, language.Failure_Code.Line_Limit)
	stats, _, _ := editor.buffer_stats(&limit_fixture.buffer)
	testing.expect_value(t, stats.revision, editor.Revision(0))
}
