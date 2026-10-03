// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../editor"
import "../language"
import "../view"
import "core:testing"

/* Verifies visible heading, hierarchy, sibling, and subtree destinations. */
@(test)
navigation_resolves_outline_destinations :: proc(t: ^testing.T) {
	source_text := "* Alpha\nbody\n** Beta\n*** Gamma\n** Delta\n* Epsilon\n"
	fixture, ready := navigation_test_fixture_open(t, source_text)
	if !ready do return
	defer navigation_test_fixture_close(&fixture)
	scope := navigation_test_scope(&fixture)

	next := navigation_test_resolve(t, &fixture, scope, .Next_Visible_Heading, 0, nil)
	testing.expect_value(t, next.position.byte_offset, editor.Byte_Offset(13))
	parent := navigation_test_resolve(t, &fixture, scope, .Parent_Heading, 25, nil)
	testing.expect_value(t, parent.position.byte_offset, editor.Byte_Offset(13))
	child := navigation_test_resolve(t, &fixture, scope, .First_Child_Heading, 1, nil)
	testing.expect_value(t, child.position.byte_offset, editor.Byte_Offset(13))
	sibling := navigation_test_resolve(t, &fixture, scope, .Next_Same_Level_Heading, 14, nil)
	testing.expect_value(t, sibling.position.byte_offset, editor.Byte_Offset(31))
	previous := navigation_test_resolve(t, &fixture, scope, .Previous_Same_Level_Heading, 34, nil)
	testing.expect_value(t, previous.position.byte_offset, editor.Byte_Offset(13))
	end := navigation_test_resolve(t, &fixture, scope, .Subtree_End, 14, nil)
	testing.expect_value(t, end.position.byte_offset, editor.Byte_Offset(31))

	hidden := [1]view.Hidden_Range{navigation_test_hidden(fixture.scope, 13, 24)}
	visible := navigation_test_resolve(t, &fixture, scope, .Next_Visible_Heading, 0, hidden[:])
	testing.expect_value(t, visible.position.byte_offset, editor.Byte_Offset(31))
}

/* Verifies canonical destinations for Stage 2 structural element families. */
@(test)
navigation_resolves_structural_families :: proc(t: ^testing.T) {
	source_text := string(
		"* Outline\n" +
		"- item\n" +
		"| a | b |\n" +
		":LOGBOOK:\nentry\n:END:\n" +
		"#+begin_quote\nbody\n#+end_quote\n",
	)
	fixture, ready := navigation_test_fixture_open(t, source_text)
	if !ready do return
	defer navigation_test_fixture_close(&fixture)
	scope := navigation_test_scope(&fixture)

	item := navigation_test_resolve(t, &fixture, scope, .Next_List_Item, 0, nil)
	testing.expect_value(t, item.target.kind, Target_Kind.List_Item)
	row := navigation_test_resolve(t, &fixture, scope, .Next_Table_Row, 0, nil)
	testing.expect_value(t, row.target.kind, Target_Kind.Table_Row)
	drawer := navigation_test_resolve(t, &fixture, scope, .Next_Drawer, 0, nil)
	testing.expect_value(t, drawer.target.kind, Target_Kind.Drawer)
	block := navigation_test_resolve(t, &fixture, scope, .Next_Block, 0, nil)
	testing.expect_value(t, block.target.kind, Target_Kind.Block)
	footnote_fixture, footnote_ready := navigation_test_fixture_open(t, "[fn:note] Definition\n")
	if !footnote_ready do return
	defer navigation_test_fixture_close(&footnote_fixture)
	footnote_scope := navigation_test_scope(&footnote_fixture)
	footnote := navigation_test_resolve(
		t,
		&footnote_fixture,
		footnote_scope,
		.Previous_Footnote,
		editor.Byte_Offset(len(footnote_fixture.source)),
		nil,
	)
	testing.expect_value(t, footnote.target.kind, Target_Kind.Footnote)
	structural := navigation_test_resolve(t, &fixture, scope, .Next_Structural_Element, 0, nil)
	testing.expect(t, structural.position.byte_offset > 0)
}

/* Verifies stale, invalid, malformed, bounded, and missing destinations reject safely. */
@(test)
navigation_rejects_unsafe_destinations :: proc(t: ^testing.T) {
	fixture, ready := navigation_test_fixture_open(t, "* One\n#+begin_unterminated\nbody\n")
	if !ready do return
	defer navigation_test_fixture_close(&fixture)
	scope := navigation_test_scope(&fixture)

	request := navigation_test_request(scope, .Next_Visible_Heading, 0, nil)
	request.scope.analysis.source_revision += 1
	request.point.revision += 1
	_, ok, failure := navigation_resolve(&fixture.analysis, u64(len(fixture.source)), request)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Stale)

	request = navigation_test_request(scope, .Next_Visible_Heading, editor.Byte_Offset(len(fixture.source)), nil)
	result: Navigation_Result
	result, ok, _ = navigation_resolve(&fixture.analysis, u64(len(fixture.source)), request)
	testing.expect(t, ok)
	testing.expect_value(t, result.status, Navigation_Status.No_Target)

	malformed := navigation_test_request(scope, .Next_Block, 0, nil)
	_, ok, failure = navigation_resolve(&fixture.analysis, u64(len(fixture.source)), malformed)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Malformed)

	bounded, bounded_ready := navigation_test_fixture_open(t, "* One\n* Two\n* Three\n")
	if !bounded_ready do return
	defer navigation_test_fixture_close(&bounded)
	limits := DEFAULT_LIMITS
	limits.semantic_targets = 1
	request = navigation_test_request(
		navigation_test_scope(&bounded),
		.Next_Visible_Heading,
		0,
		nil,
	)
	_, ok, failure = navigation_resolve(
		&bounded.analysis,
		u64(len(bounded.source)),
		request,
		limits,
	)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Limited)
}

@(private = "file")
Navigation_Test_Fixture :: struct {
	owner:    language.Jan_Structural_Owner,
	analysis: language.Jan_Structural_Analysis,
	scope:    language.Jan_Analysis_Scope,
	source:   string,
}

@(private = "file")
navigation_test_fixture_open :: proc(
	t: ^testing.T,
	source: string,
) -> (fixture: Navigation_Test_Fixture, ok: bool) {
	fixture.source = source
	fixture.scope = editing_test_scope(701, 1).analysis
	fixture.scope.configuration = language.jan_factory_configuration(1).identity
	initialized, initialize_failure := language.jan_structural_owner_init(&fixture.owner, 1)
	testing.expectf(t, initialized, "owner initialization failed with %v", initialize_failure.code)
	if !initialized do return fixture, false
	analysis: language.Jan_Structural_Analysis
	analyzed: bool
	analysis, analyzed, initialize_failure = language.jan_structural_owner_analyze(
		&fixture.owner,
		transmute([]u8)source,
		fixture.scope,
	)
	testing.expectf(t, analyzed, "analysis failed with %v", initialize_failure.code)
	if !analyzed {
		language.jan_structural_owner_close(&fixture.owner)
		return fixture, false
	}
	fixture.analysis = analysis
	return fixture, true
}

@(private = "file")
navigation_test_fixture_close :: proc(fixture: ^Navigation_Test_Fixture) {
	language.jan_structural_analysis_close(&fixture.analysis)
	language.jan_structural_owner_close(&fixture.owner)
}

@(private = "file")
navigation_test_scope :: proc(fixture: ^Navigation_Test_Fixture) -> Scope {
	scope := editing_test_scope(fixture.scope.buffer_id, fixture.scope.source_revision)
	scope.analysis = fixture.scope
	return scope
}

@(private = "file")
navigation_test_request :: proc(
	scope: Scope,
	kind: Navigation_Kind,
	offset: editor.Byte_Offset,
	hidden: []view.Hidden_Range,
) -> Navigation_Request {
	return {
		scope = scope,
		kind = kind,
		point = {
			buffer_id = scope.analysis.buffer_id,
			revision = scope.analysis.source_revision,
			byte_offset = offset,
		},
		hidden_ranges = hidden,
	}
}

@(private = "file")
navigation_test_resolve :: proc(
	t: ^testing.T,
	fixture: ^Navigation_Test_Fixture,
	scope: Scope,
	kind: Navigation_Kind,
	offset: editor.Byte_Offset,
	hidden: []view.Hidden_Range,
) -> Navigation_Result {
	result, ok, failure := navigation_resolve(
		&fixture.analysis,
		u64(len(fixture.source)),
		navigation_test_request(scope, kind, offset, hidden),
	)
	testing.expectf(t, ok, "navigation failed with %v", failure.code)
	testing.expect_value(t, result.status, Navigation_Status.Resolved)
	return result
}

@(private = "file")
navigation_test_hidden :: proc(
	scope: language.Jan_Analysis_Scope,
	start, end: editor.Byte_Offset,
) -> view.Hidden_Range {
	return {
		start = {buffer_id = scope.buffer_id, revision = scope.source_revision, byte_offset = start},
		end = {buffer_id = scope.buffer_id, revision = scope.source_revision, byte_offset = end},
	}
}
