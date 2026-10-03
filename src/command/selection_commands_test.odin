// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor"
import "../interaction"
import editor_view "../view"
import "core:strings"
import "core:testing"

/* Verifies word selection is Unicode-safe, active, and leaves canonical text unchanged. */
@(test)
select_word_publishes_unicode_range :: proc(t: ^testing.T) {
	contents := "-- Żółć_42, next"
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, contents, context.allocator) do return
	defer native_fixture_close(t, &fixture)
	offset := editor.Byte_Offset(strings.index(contents, "Żółć"))
	position, positioned, _ := editor.buffer_position(&fixture.buffer, offset)
	if !positioned do return
	editor_view.set_point(&fixture.view_registry, fixture.view, position)
	before, before_ok, _ := editor.buffer_stats(&fixture.buffer)
	result, executed, failure := execute_named(&fixture, "select-word")
	after, after_ok, _ := editor.buffer_stats(&fixture.buffer)
	selection, selected, _ := editor_view.snapshot(&fixture.view_registry, fixture.view)
	testing.expectf(t, executed, "word selection failed with %v", failure.code)
	testing.expect(t, before_ok && after_ok && selected)
	if selected {
		testing.expect(t, selection.region_active && selection.mark.present)
		testing.expect_value(t, selection.mark.position.byte_offset, offset)
		testing.expect_value(t, selection.point_position.byte_offset, editor.Byte_Offset(strings.index(contents, ",")))
	}
	testing.expect_value(t, result.completion, Native_Completion.View_Changed)
	testing.expect_value(t, after.revision, before.revision)
}

/* Verifies separator selection prefers the following word and empty lines remain unchanged. */
@(test)
select_word_prefers_next_word :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "alpha, beta\n---", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	separator, _, _ := editor.buffer_position(&fixture.buffer, 5)
	editor_view.set_point(&fixture.view_registry, fixture.view, separator)
	result, selected, failure := execute_named(&fixture, "select-word")
	testing.expectf(t, selected, "separator selection failed with %v", failure.code)
	testing.expect_value(t, result.completion, Native_Completion.View_Changed)
	selection, selection_ok, _ := editor_view.snapshot(&fixture.view_registry, fixture.view)
	if selection_ok {
		testing.expect_value(t, selection.mark.position.byte_offset, editor.Byte_Offset(7))
		testing.expect_value(t, selection.point_position.byte_offset, editor.Byte_Offset(11))
	}
	line, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(len("alpha, beta\n")))
	editor_view.clear_mark(&fixture.view_registry, fixture.view)
	editor_view.set_point(&fixture.view_registry, fixture.view, line)
	result, selected, failure = execute_named(&fixture, "select-word")
	testing.expectf(t, selected, "wordless line failed with %v", failure.code)
	testing.expect_value(t, result.completion, Native_Completion.No_Op)
}

/* Verifies paragraph and buffer selection retain exact canonical line boundaries. */
@(test)
select_paragraph_and_buffer_publish_exact_ranges :: proc(t: ^testing.T) {
	contents := "one\ntwo\n\nthree\n"
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, contents, context.allocator) do return
	defer native_fixture_close(t, &fixture)
	point, _, _ := editor.buffer_position(&fixture.buffer, 2)
	editor_view.set_point(&fixture.view_registry, fixture.view, point)
	result, selected, failure := execute_named(&fixture, "select-paragraph")
	testing.expectf(t, selected, "paragraph selection failed with %v", failure.code)
	testing.expect_value(t, result.completion, Native_Completion.View_Changed)
	selection, selection_ok, _ := editor_view.snapshot(&fixture.view_registry, fixture.view)
	if selection_ok {
		testing.expect_value(t, selection.mark.position.byte_offset, editor.Byte_Offset(0))
		testing.expect_value(t, selection.point_position.byte_offset, editor.Byte_Offset(8))
	}
	result, selected, failure = execute_named(&fixture, "select-buffer")
	testing.expectf(t, selected, "buffer selection failed with %v", failure.code)
	testing.expect_value(t, result.completion, Native_Completion.View_Changed)
	selection, selection_ok, _ = editor_view.snapshot(&fixture.view_registry, fixture.view)
	if selection_ok {
		testing.expect_value(t, selection.mark.position.byte_offset, editor.Byte_Offset(0))
		testing.expect_value(t, selection.point_position.byte_offset, editor.Byte_Offset(len(contents)))
	}
}

/* Verifies an empty buffer still receives an active empty range. */
@(test)
select_buffer_activates_empty_range :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	result, selected, failure := execute_named(&fixture, "select-buffer")
	testing.expectf(t, selected, "empty buffer selection failed with %v", failure.code)
	testing.expect_value(t, result.completion, Native_Completion.View_Changed)
	selection, selection_ok, _ := editor_view.snapshot(&fixture.view_registry, fixture.view)
	if selection_ok {
		testing.expect(t, selection.region_active && selection.mark.present)
		testing.expect_value(t, selection.mark.position.byte_offset, editor.Byte_Offset(0))
		testing.expect_value(t, selection.point_position.byte_offset, editor.Byte_Offset(0))
	}
}

/* Verifies selection commands are named native entries and definition selection noops without analysis. */
@(test)
selection_definition_needs_analysis :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "alpha", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	names := [?]string {
		"select-word",
		"select-paragraph",
		"select-buffer",
		"select-definition",
		"pop-selection-location",
	}
	for name in names {
		handle, found, _ := interaction.command_lookup(&fixture.command_registry, name)
		metadata, described, _ := interaction.command_metadata(&fixture.command_registry, handle)
		testing.expect(t, found && described)
		if found && described {
			testing.expect(t, metadata.interactive)
			testing.expect_value(t, metadata.effects, interaction.Command_Effects{.View})
		}
	}
	result, selected, failure := execute_named(&fixture, "select-definition")
	testing.expectf(t, selected, "definition selection failed with %v", failure.code)
	testing.expect_value(t, result.completion, Native_Completion.No_Op)
}

/* Verifies return history restores prior states newest first and skips stale records. */
@(test)
pop_selection_restores_history :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "alpha beta", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	first, first_ok, _ := execute_named(&fixture, "select-word")
	testing.expect(t, first_ok)
	second_point, _, _ := editor.buffer_position(&fixture.buffer, 6)
	editor_view.clear_mark(&fixture.view_registry, fixture.view)
	editor_view.set_point(&fixture.view_registry, fixture.view, second_point)
	second, second_ok, second_failure := execute_named(&fixture, "select-word")
	testing.expectf(t, second_ok, "second selection failed with %v", second_failure.code)
	testing.expect_value(t, first.completion, Native_Completion.View_Changed)
	testing.expect_value(t, second.completion, Native_Completion.View_Changed)
	before, before_ok, _ := editor.buffer_stats(&fixture.buffer)
	result, restored, failure := execute_named(&fixture, "pop-selection-location")
	testing.expectf(t, restored, "first return failed with %v", failure.code)
	testing.expect_value(t, result.completion, Native_Completion.View_Changed)
	selection, selection_ok, _ := editor_view.snapshot(&fixture.view_registry, fixture.view)
	if selection_ok {
		testing.expect_value(t, selection.point_position.byte_offset, editor.Byte_Offset(6))
		testing.expect(t, !selection.mark.present && !selection.region_active)
	}
	result, restored, failure = execute_named(&fixture, "pop-selection-location")
	testing.expectf(t, restored, "second return failed with %v", failure.code)
	testing.expect_value(t, result.completion, Native_Completion.View_Changed)
	selection, selection_ok, _ = editor_view.snapshot(&fixture.view_registry, fixture.view)
	if selection_ok {
		testing.expect_value(t, selection.point_position.byte_offset, editor.Byte_Offset(0))
	}
	stale := Location_State {
		buffer_id = editor.Buffer_ID(81),
		revision = editor.Revision(99),
		point = {
			buffer_id = editor.Buffer_ID(81),
			revision = editor.Revision(99),
			byte_offset = 3,
		},
	}
	testing.expect(t, location_history_push(&fixture.location_history, stale))
	result, restored, failure = execute_named(&fixture, "pop-selection-location")
	after, after_ok, _ := editor.buffer_stats(&fixture.buffer)
	testing.expectf(t, restored, "stale return failed with %v", failure.code)
	testing.expect_value(t, result.completion, Native_Completion.No_Op)
	testing.expect(t, before_ok && after_ok)
	testing.expect_value(t, after.revision, before.revision)
}
