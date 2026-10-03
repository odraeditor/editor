// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../editor"
import "core:testing"

/* Verifies rich items compose markup, entities, indentation, and heading numbers. */
@(test)
rich_presentation_projects_revision_bound_content :: proc(t: ^testing.T) {
	source := "* One\n** Two\nText *bold* \\alpha and =code=.\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 2_001) do return
	defer list_test_fixture_close(&fixture)
	request := rich_test_request(fixture.scope, u64(len(source)))
	presentation: Rich_Presentation
	descriptor, prepared, failure := rich_presentation_prepare(
		&presentation,
		&fixture.analysis,
		transmute([]u8)source,
		request,
	)
	testing.expectf(t, prepared, "rich presentation failed with %v", failure.code)
	if !prepared do return
	defer rich_presentation_close(&presentation)
	testing.expect_value(t, descriptor.generation, Rich_Presentation_Generation(7))
	testing.expect(t, !descriptor.source_fallback)
	testing.expect(t, rich_test_has_text(&presentation, .Composed_Markup, "bold"))
	testing.expect(t, rich_test_has_text(&presentation, .Composed_Markup, "code"))
	testing.expect(t, rich_test_has_text(&presentation, .Prettified_Entity, "α"))
	testing.expect(t, rich_test_has_text(&presentation, .Visual_Indent, "  "))
	testing.expect(t, rich_test_has_text(&presentation, .Heading_Number, "1 "))
	testing.expect(t, rich_test_has_text(&presentation, .Heading_Number, "1.1 "))
	fallback, copied := rich_presentation_source_fallback(&presentation)
	testing.expect(t, copied)
	testing.expect_value(t, fallback, source)
}

/* Verifies terminal projection retains exact editable source and semantic roles. */
@(test)
rich_presentation_uses_terminal_source_fallback :: proc(t: ^testing.T) {
	source := "* Heading\nText *bold* \\lambda.\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 2_002) do return
	defer list_test_fixture_close(&fixture)
	request := rich_test_request(fixture.scope, u64(len(source)))
	request.surface = .Terminal_Source
	presentation: Rich_Presentation
	descriptor, prepared, failure := rich_presentation_prepare(
		&presentation,
		&fixture.analysis,
		transmute([]u8)source,
		request,
	)
	testing.expectf(t, prepared, "terminal presentation failed with %v", failure.code)
	if !prepared do return
	defer rich_presentation_close(&presentation)
	testing.expect(t, descriptor.source_fallback)
	for item in rich_presentation_items(&presentation) {
		testing.expect_value(t, item.kind, Rich_Item_Kind.Source_Role)
	}
	fallback, copied := rich_presentation_source_fallback(&presentation)
	testing.expect(t, copied)
	testing.expect_value(t, fallback, source)
}

/* Verifies stale revisions and cancellation publish no projection. */
@(test)
rich_presentation_rejects_stale_or_cancelled_requests :: proc(t: ^testing.T) {
	source := "* Heading\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 2_003) do return
	defer list_test_fixture_close(&fixture)
	presentation: Rich_Presentation
	request := rich_test_request(fixture.scope, u64(len(source)))
	request.scope.analysis.source_revision += 1
	_, prepared, failure := rich_presentation_prepare(
		&presentation,
		&fixture.analysis,
		transmute([]u8)source,
		request,
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Stale)
	testing.expect_value(t, presentation.state, rawptr(nil))
	cancelled := true
	request = rich_test_request(fixture.scope, u64(len(source)))
	request.cancel_requested = &cancelled
	_, prepared, failure = rich_presentation_prepare(
		&presentation,
		&fixture.analysis,
		transmute([]u8)source,
		request,
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Cancelled)
}

@(private)
rich_test_request :: proc(scope: Scope, source_bytes: u64) -> Rich_Presentation_Request {
	return {
		operation_id = 201,
		generation = 7,
		scope = scope,
		visible_end = editor.Byte_Offset(source_bytes),
		surface = .Rich,
		compose_markup = true,
		prettify_entities = true,
		visual_indent_width = 2,
		number_headings = true,
	}
}

@(private)
rich_test_has_text :: proc(
	presentation: ^Rich_Presentation,
	kind: Rich_Item_Kind,
	expected: string,
) -> bool {
	for item in rich_presentation_items(presentation) {
		if item.kind != kind do continue
		text, ok := rich_presentation_item_text(presentation, item)
		if ok && text == expected do return true
	}
	return false
}
