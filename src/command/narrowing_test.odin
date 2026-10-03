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

/* Verifies region narrowing is view-local and reversible. */
@(test)
narrowing_projects_one_view_and_widen_restores_it :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "zero one two", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	second, second_ok, _ := editor_view.clone_additional(&fixture.view_registry, fixture.view)
	testing.expect(t, second_ok)
	if !second_ok do return
	defer editor_view.close(&fixture.view_registry, &second)

	mark, _, _ := editor.buffer_position(&fixture.buffer, 5)
	point, _, _ := editor.buffer_position(&fixture.buffer, 8)
	marked, _ := editor_view.select_range(
		&fixture.view_registry,
		fixture.view,
		mark,
		point,
		3,
	)
	testing.expect(t, marked)
	narrowed, narrow_ok, narrow_failure := execute_named(&fixture, "narrow-to-region")
	testing.expectf(t, narrow_ok, "narrow failed with %v", narrow_failure.code)
	testing.expect_value(t, narrowed.completion, Native_Completion.View_Changed)
	expect_native_state(t, &fixture, 8, 3, 0, "zero one two")

	ranges: [2]editor_view.Hidden_Range
	visibility, copied, copy_failure := editor_view.visibility_copy_ranges(
		&fixture.view_registry,
		fixture.view,
		ranges[:],
	)
	testing.expectf(t, copied, "visibility copy failed with %v", copy_failure.code)
	testing.expect_value(t, visibility.range_count, u32(2))
	testing.expect_value(t, ranges[0].start.byte_offset, editor.Byte_Offset(0))
	testing.expect_value(t, ranges[0].end.byte_offset, editor.Byte_Offset(5))
	testing.expect_value(t, ranges[1].start.byte_offset, editor.Byte_Offset(8))
	testing.expect_value(t, ranges[1].end.byte_offset, editor.Byte_Offset(12))
	other, other_ok, _ := editor_view.visibility_copy_ranges(&fixture.view_registry, second, nil)
	testing.expect(t, other_ok)
	testing.expect_value(t, other.range_count, u32(0))

	widened, widen_ok, widen_failure := execute_named(&fixture, "widen")
	testing.expectf(t, widen_ok, "widen failed with %v", widen_failure.code)
	testing.expect_value(t, widened.completion, Native_Completion.View_Changed)
	complete, complete_ok, _ := editor_view.visibility_copy_ranges(
		&fixture.view_registry,
		fixture.view,
		nil,
	)
	testing.expect(t, complete_ok)
	testing.expect_value(t, complete.range_count, u32(0))
}

/* Verifies narrowing rejects absent regions and accepts a complete-buffer region. */
@(test)
narrowing_requires_a_nonempty_region :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "text", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	_, narrowed, failure := execute_named(&fixture, "narrow-to-region")
	testing.expect(t, !narrowed)
	testing.expect_value(t, failure.code, Failure_Code.Region_Unavailable)

	start, _, _ := editor.buffer_position(&fixture.buffer, 0)
	end, _, _ := editor.buffer_position(&fixture.buffer, 4)
	selected, _ := editor_view.select_range(
		&fixture.view_registry,
		fixture.view,
		start,
		end,
		4,
	)
	testing.expect(t, selected)
	result, full_ok, full_failure := execute_named(&fixture, "narrow-to-region")
	testing.expectf(t, full_ok, "full narrowing failed with %v", full_failure.code)
	testing.expect_value(t, result.completion, Native_Completion.View_Changed)
	visibility, copied, _ := editor_view.visibility_copy_ranges(
		&fixture.view_registry,
		fixture.view,
		nil,
	)
	testing.expect(t, copied)
	testing.expect_value(t, visibility.range_count, u32(0))
}

/* Verifies definition narrowing uses the structural owner without changing buffer state. */
@(test)
narrowing_definition_projects_the_structural_target :: proc(t: ^testing.T) {
	contents := "package demo\nmain :: proc() {\n    value := 1\n}\n"
	fixture: Structural_Editor_Test_Fixture
	if !structural_editor_test_open(t, &fixture, 808, contents) do return
	defer structural_editor_test_close(&fixture)
	definitions := native_command_definitions()
	registry: interaction.Command_Registry
	ready, registry_failure := interaction.command_registry_init(
		&registry,
		interaction.Registry_Generation(33),
		definitions[:],
		context.allocator,
	)
	testing.expectf(t, ready, "narrowing registry setup failed with %v", registry_failure.code)
	if !ready do return
	defer interaction.command_registry_close(&registry)
	handle, found, _ := interaction.command_lookup(&registry, "narrow-to-definition")
	testing.expect(t, found)
	if !found do return
	value_offset := editor.Byte_Offset(strings.index(contents, "value"))
	value, positioned, _ := editor.buffer_position(&fixture.buffer, value_offset)
	if !positioned do return
	editor_view.move_point(&fixture.views, fixture.view, value, 0, .Deactivate)
	request := fixture.ctx.native
	request.registry = &registry
	request.command = handle
	request.language_owner = &fixture.owner
	request.language_source = &fixture.source
	request.structural_scope = fixture.analysis
	result, narrowed, narrow_failure := native_command_execute(request)
	testing.expectf(t, narrowed, "definition narrowing failed with %v", narrow_failure.code)
	if !narrowed do return
	defer native_result_close(&result)
	testing.expect_value(t, result.completion, Native_Completion.View_Changed)
	ranges: [2]editor_view.Hidden_Range
	visibility, copied, copy_failure := editor_view.visibility_copy_ranges(
		&fixture.views,
		fixture.view,
		ranges[:],
	)
	testing.expectf(t, copied, "definition visibility copy failed with %v", copy_failure.code)
	testing.expect_value(t, visibility.range_count, u32(2))
	testing.expect_value(
		t,
		ranges[0].end.byte_offset,
		editor.Byte_Offset(strings.index(contents, "main")),
	)
	testing.expect_value(
		t,
		ranges[1].start.byte_offset,
		editor.Byte_Offset(strings.index(contents, "}\n") + 1),
	)
	secondary, secondary_ok, _ := editor_view.visibility_copy_ranges(
		&fixture.views,
		fixture.second_view,
		nil,
	)
	testing.expect(t, secondary_ok)
	testing.expect_value(t, secondary.range_count, u32(0))
	stats, stats_ok, _ := editor.buffer_stats(&fixture.buffer)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.revision, editor.Revision(0))
}
