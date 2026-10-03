// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../display"
import "../editor"
import editor_view "../view"
import "core:testing"

@(test)
/* Verifies point inference resolves word, line, paragraph, and buffer targets. */
semantic_targets_infer_word_line_paragraph_and_buffer :: proc(t: ^testing.T) {
	fixture: Semantic_Target_Test_Fixture
	if !semantic_target_fixture_init(t, &fixture, 801, "alpha beta\n\ngamma\n") do return
	defer semantic_target_fixture_close(&fixture)
	point, _, _ := editor.buffer_position(&fixture.buffer, 7)
	point_set, _ := editor_view.set_point(&fixture.registry, fixture.view, point)
	testing.expect(t, point_set)
	target_context := semantic_target_test_context(&fixture)

	word, word_ok, _ := semantic_target_resolve(target_context, .Word)
	testing.expect(t, word_ok)
	testing.expect_value(t, u64(word.start.byte_offset), u64(6))
	testing.expect_value(t, u64(word.end.byte_offset), u64(10))

	line, line_ok, _ := semantic_target_resolve(target_context, .Line)
	testing.expect(t, line_ok)
	testing.expect_value(t, u64(line.start.byte_offset), u64(0))
	testing.expect_value(t, u64(line.end.byte_offset), u64(11))

	paragraph, paragraph_ok, _ := semantic_target_resolve(target_context, .Paragraph)
	testing.expect(t, paragraph_ok)
	testing.expect_value(t, u64(paragraph.start.byte_offset), u64(0))
	testing.expect_value(t, u64(paragraph.end.byte_offset), u64(11))

	buffer, buffer_ok, _ := semantic_target_resolve(target_context, .Buffer)
	testing.expect(t, buffer_ok)
	testing.expect_value(t, u64(buffer.start.byte_offset), u64(0))
	testing.expect_value(t, u64(buffer.end.byte_offset), u64(18))
}

@(test)
/* Verifies explicit and active regions override inferred semantic targets. */
semantic_targets_prefer_explicit_and_active_regions :: proc(t: ^testing.T) {
	fixture: Semantic_Target_Test_Fixture
	if !semantic_target_fixture_init(t, &fixture, 802, "abcdef") do return
	defer semantic_target_fixture_close(&fixture)
	start, _, _ := editor.buffer_position(&fixture.buffer, 1)
	end, _, _ := editor.buffer_position(&fixture.buffer, 4)
	target_context := semantic_target_test_context(&fixture)
	target_context.explicit_range = {present = true, start = end, end = start, backward = true}
	explicit, explicit_ok, _ := semantic_target_resolve(target_context, .Word)
	testing.expect(t, explicit_ok)
	testing.expect_value(t, explicit.source, Semantic_Target_Source.Explicit_Range)
	testing.expect_value(t, u64(explicit.start.byte_offset), u64(1))
	testing.expect_value(t, u64(explicit.end.byte_offset), u64(4))

	target_context.explicit_range = {}
	marked, _ := editor.buffer_selection_set_mark(&fixture.buffer, start, true)
	moved, _ := editor.buffer_selection_move(&fixture.buffer, end, .Preserve)
	testing.expect(t, marked && moved)
	region, region_ok, _ := semantic_target_resolve(target_context, .Active_Region)
	testing.expect(t, region_ok)
	testing.expect_value(t, region.source, Semantic_Target_Source.Active_Selection)
	testing.expect_value(t, u64(region.start.byte_offset), u64(1))
	testing.expect_value(t, u64(region.end.byte_offset), u64(4))
}

@(test)
/* Verifies stale supplied context rejects before semantic target resolution. */
semantic_targets_reject_stale_supplied_context :: proc(t: ^testing.T) {
	fixture: Semantic_Target_Test_Fixture
	if !semantic_target_fixture_init(t, &fixture, 803, "node") do return
	defer semantic_target_fixture_close(&fixture)
	start, _, _ := editor.buffer_position(&fixture.buffer, 0)
	end, _, _ := editor.buffer_position(&fixture.buffer, 4)
	target_context := semantic_target_test_context(&fixture)
	target_context.context_generation = 9
	target_context.supplied = {
		present = true,
		kind = .Node,
		start = start,
		end = end,
		context_generation = 8,
	}
	_, resolved, failure := semantic_target_resolve(target_context, .Node)
	testing.expect(t, !resolved)
	testing.expect_value(t, failure.code, Semantic_Target_Failure_Code.Stale_Context)
	testing.expect_value(t, failure.expected, u64(9))
	testing.expect_value(t, failure.actual, u64(8))
	target_context.supplied.context_generation = 9
	target: Semantic_Target
	target, resolved, _ = semantic_target_resolve(target_context, .Node)
	testing.expect(t, resolved)
	testing.expect_value(t, target.source, Semantic_Target_Source.Supplied_Context)
}

@(test)
/* Verifies unavailable regions and stale explicit ranges reject safely. */
semantic_targets_reject_unavailable_regions_and_stale_explicit_ranges :: proc(t: ^testing.T) {
	fixture: Semantic_Target_Test_Fixture
	if !semantic_target_fixture_init(t, &fixture, 804, "target") do return
	defer semantic_target_fixture_close(&fixture)
	target_context := semantic_target_test_context(&fixture)
	_, region_ok, region_failure := semantic_target_resolve(target_context, .Active_Region)
	testing.expect(t, !region_ok)
	testing.expect_value(t, region_failure.code, Semantic_Target_Failure_Code.Unavailable)

	start, _, _ := editor.buffer_position(&fixture.buffer, 0)
	end, _, _ := editor.buffer_position(&fixture.buffer, 6)
	stale := start
	stale.revision = editor.Revision(u64(stale.revision) + 1)
	target_context.explicit_range = {present = true, start = stale, end = end}
	_, explicit_ok, explicit_failure := semantic_target_resolve(target_context, .Line)
	testing.expect(t, !explicit_ok)
	testing.expect_value(t, explicit_failure.code, Semantic_Target_Failure_Code.Stale_Context)
}

@(private)
Semantic_Target_Test_Fixture :: struct {
	buffer:   editor.Buffer,
	registry: editor_view.Registry,
	view:     editor_view.View_Handle,
	ready:    bool,
}

@(private)
semantic_target_fixture_init :: proc(
	t: ^testing.T,
	fixture: ^Semantic_Target_Test_Fixture,
	id: u64,
	text: string,
) -> bool {
	assert(fixture != nil)
	buffer_ok, buffer_failure := editor.buffer_init(
		&fixture.buffer,
		editor.Buffer_ID(id),
		text,
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, buffer_ok, "buffer initialization failed with %v", buffer_failure.code)
	if !buffer_ok do return false
	registry_ok, registry_failure := editor_view.registry_init(
		&fixture.registry,
		editor_view.Registry_ID(u32(id)),
		context.allocator,
	)
	testing.expectf(t, registry_ok, "view registry initialization failed with %v", registry_failure.code)
	if !registry_ok {
		editor.buffer_close(&fixture.buffer)
		return false
	}
	view, view_ok, view_failure := editor_view.create(&fixture.registry, &fixture.buffer)
	testing.expectf(t, view_ok, "view creation failed with %v", view_failure.code)
	if !view_ok {
		editor_view.registry_close(&fixture.registry)
		editor.buffer_close(&fixture.buffer)
		return false
	}
	fixture.view = view
	fixture.ready = true
	return true
}

@(private)
semantic_target_fixture_close :: proc(fixture: ^Semantic_Target_Test_Fixture) {
	if fixture == nil || !fixture.ready do return
	_, _ = editor_view.close(&fixture.registry, &fixture.view)
	_, _ = editor_view.registry_close(&fixture.registry)
	editor.buffer_close(&fixture.buffer)
	fixture^ = {}
}

@(private)
semantic_target_test_context :: proc(
	fixture: ^Semantic_Target_Test_Fixture,
) -> Semantic_Target_Context {
	return {
		buffer = &fixture.buffer,
		view_registry = &fixture.registry,
		view = fixture.view,
		profile = display.terminal_unicode17_profile(),
	}
}
