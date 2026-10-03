// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../language"
import "core:testing"

/* Verifies named references visit definitions and definitions visit references locally. */
@(test)
footnotes_visit_same_document_destinations :: proc(t: ^testing.T) {
	source := "* Notes\nSee [fn:note].\n\n[fn:note] Definition\n\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 2_101) do return
	defer list_test_fixture_close(&fixture)
	reference, reference_found := list_test_node(&fixture.analysis, .Named_Footnote_Reference, 0)
	definition, definition_found := list_test_node(&fixture.analysis, .Footnote_Definition, 0)
	testing.expect(t, reference_found && definition_found)
	if !reference_found || !definition_found do return
	resolution, resolved, failure := footnote_visit_local(
		&fixture.analysis,
		transmute([]u8)source,
		fixture.scope,
		reference.id,
	)
	testing.expectf(t, resolved, "reference visit failed with %v", failure.code)
	testing.expect_value(t, resolution.destination.node_id, definition.id)
	resolution, resolved, failure = footnote_visit_local(
		&fixture.analysis,
		transmute([]u8)source,
		fixture.scope,
		definition.id,
	)
	testing.expectf(t, resolved, "definition visit failed with %v", failure.code)
	testing.expect_value(t, resolution.destination.node_id, reference.id)
}

/* Verifies creation and inline normalization are one undoable source transaction. */
@(test)
footnotes_create_and_normalize_local_definitions :: proc(t: ^testing.T) {
	footnote_test_expect_edit(
		t,
		"See [fn:note].\n",
		"See [fn:note].\n[fn:note] Definition\n",
		.Create_Definition,
		.Invalid,
		0,
		"note",
		"Definition",
	)
	footnote_test_expect_edit(
		t,
		"Text [fn::Inline body].\n",
		"Text [fn:1].\n[fn:1] Inline body\n",
		.Normalize_Inline,
		.Anonymous_Footnote_Reference,
		0,
		"1",
		"",
	)
}

/* Verifies local labels renumber consistently and definitions move structurally. */
@(test)
footnotes_renumber_and_move_definitions :: proc(t: ^testing.T) {
	footnote_test_expect_edit(
		t,
		"See [fn:z] and [fn:a].\n[fn:a] A\n[fn:z] Z\n",
		"See [fn:1] and [fn:2].\n[fn:2] A\n[fn:1] Z\n",
		.Renumber_Local,
		.Invalid,
		0,
		"",
		"",
	)
	footnote_test_expect_edit(
		t,
		"* Notes\n[fn:a] A\n\n[fn:b] B\n\n",
		"* Notes\n[fn:b] B\n\n[fn:a] A\n\n",
		.Move_Definition_Up,
		.Footnote_Definition,
		1,
		"",
		"",
	)
}

/* Verifies external footnote resolution names its unavailable configured provider. */
@(test)
footnotes_keep_cross_resource_resolution_unavailable :: proc(t: ^testing.T) {
	record := footnote_cross_resource_availability()
	testing.expect_value(t, record.class, language.Jan_Availability_Class.Configured_Provider)
	testing.expect_value(t, record.owner, language.Jan_Stage.Export_Publishing_And_Integration)
	testing.expect(t, !record.available)
}

@(private)
footnote_test_expect_edit :: proc(
	t: ^testing.T,
	source, expected: string,
	kind: Footnote_Edit_Kind,
	target_kind: language.Jan_Node_Kind,
	ordinal: int,
	name, text: string,
) {
	fixture: List_Test_Fixture
	id := u64(2_200 + int(kind) * 8 + ordinal)
	if !list_test_fixture_open(t, &fixture, source, id) do return
	defer list_test_fixture_close(&fixture)
	target_id: language.Jan_Node_ID
	if target_kind != .Invalid {
		target, found := list_test_node(&fixture.analysis, target_kind, ordinal)
		testing.expect(t, found)
		if !found do return
		target_id = target.id
	}
	request := Footnote_Edit_Request {
		operation_id = 211,
		scope = fixture.scope,
		kind = kind,
		target_id = target_id,
		rewrite_generation = 211,
		name = name,
		text = text,
	}
	plan: language.Jan_Rewrite_Plan
	planned, failure := footnote_edit_plan_prepare(
		&plan,
		&fixture.analysis,
		transmute([]u8)source,
		request,
	)
	testing.expectf(t, planned, "%v footnote plan failed with %v", kind, failure.code)
	if !planned do return
	defer language.jan_rewrite_plan_close(&plan)
	testing.expect(t, list_test_publish_and_history(&fixture, &plan, expected))
}
