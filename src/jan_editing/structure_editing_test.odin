// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../language"
import "core:mem"
import "core:testing"

/* Verifies complete selection and fold ranges expose only a structure's body. */
@(test)
structure_editing_inspects_drawer_and_verbatim_block_bodies :: proc(t: ^testing.T) {
	source := ":NOTES:\nvalue λ\n:END:\n#+begin_src odin\nmain :: proc() {}\n#+end_src\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 1_201) do return
	defer list_test_fixture_close(&fixture)
	drawer, drawer_found := list_test_node(&fixture.analysis, .Drawer, 0)
	block, block_found := list_test_node(&fixture.analysis, .Source_Block, 0)
	testing.expect(t, drawer_found && block_found)
	if !drawer_found || !block_found do return
	drawer_inspection, drawer_ok, failure := structure_inspect(
		&fixture.analysis,
		transmute([]u8)source,
		fixture.scope,
		drawer.id,
	)
	testing.expectf(t, drawer_ok, "drawer inspection failed with %v", failure.code)
	testing.expect_value(t, drawer_inspection.target.kind, Target_Kind.Drawer)
	testing.expect(t, drawer_inspection.foldable)
	testing.expect_value(
		t,
		string(transmute([]u8)source[int(drawer_inspection.body.start):int(drawer_inspection.body.end)]),
		"value λ\n",
	)
	block_inspection, block_ok, block_failure := structure_inspect(
		&fixture.analysis,
		transmute([]u8)source,
		fixture.scope,
		block.id,
	)
	testing.expectf(t, block_ok, "block inspection failed with %v", block_failure.code)
	testing.expect_value(t, block_inspection.target.kind, Target_Kind.Block)
	testing.expect_value(t, block_inspection.selection, block.range)
	testing.expect_value(t, block_inspection.fold_range.start.byte_offset, block_inspection.body.start)
	testing.expect_value(t, block_inspection.fold_range.end.byte_offset, block_inspection.body.end)
	testing.expect_value(
		t,
		string(transmute([]u8)source[int(block_inspection.body.start):int(block_inspection.body.end)]),
		"main :: proc() {}\n",
	)
}

/* Verifies factory templates generate one agreed delimiter pair and preserve body bytes. */
@(test)
structure_editing_expands_factory_templates :: proc(t: ^testing.T) {
	structure_test_expect_edit(
		t,
		"Replace me λ\n",
		"#+begin_src odin :results none\nmain :: proc() {\n\tfmt.println(\"λ\")\n}\n#+end_src\n",
		.Expand_Template,
		.Paragraph,
		0,
		.Source_Block,
		"",
		"odin :results none",
		"main :: proc() {\n\tfmt.println(\"λ\")\n}\n",
	)
	structure_test_expect_edit(
		t,
		":OLD:\nbody\n:END:\n",
		":NOTES:\ntext\n:END:\n:OLD:\nbody\n:END:\n",
		.Insert_Before,
		.Drawer,
		0,
		.Drawer,
		"NOTES",
		"",
		"text\n",
	)
	structure_test_expect_edit(
		t,
		"#+begin_quote\nold\n#+end_quote\n",
		"#+begin_quote\nold\n#+end_quote\n#+begin_note audience\nverbatim * λ\n#+end_note\n",
		.Insert_After,
		.Quote_Block,
		0,
		.Special_Block,
		"note",
		"audience",
		"verbatim * λ\n",
	)
}

/* Verifies rename, move, and delete operate on complete structures atomically. */
@(test)
structure_editing_reorganizes_complete_structures :: proc(t: ^testing.T) {
	structure_test_expect_edit(
		t,
		"#+begin_note keep\nraw * λ\n#+end_note\n",
		"#+begin_warning keep\nraw * λ\n#+end_warning\n",
		.Rename,
		.Special_Block,
		0,
		.Invalid,
		"warning",
		"",
		"",
	)
	structure_test_expect_edit(
		t,
		":NOTES:\nraw\n:END:\n",
		":LOGBOOK:\nraw\n:END:\n",
		.Rename,
		.Drawer,
		0,
		.Invalid,
		"LOGBOOK",
		"",
		"",
	)
	structure_test_expect_edit(
		t,
		"#+begin_quote\nA\n#+end_quote\n#+begin_center\nB\n#+end_center\n",
		"#+begin_center\nB\n#+end_center\n#+begin_quote\nA\n#+end_quote\n",
		.Move_Down,
		.Quote_Block,
		0,
		.Invalid,
		"",
		"",
		"",
	)
	structure_test_expect_edit(
		t,
		":PROPERTIES:\n:ID: one\n:END:\nBody\n",
		"Body\n",
		.Delete,
		.Property_Drawer,
		0,
		.Invalid,
		"",
		"",
		"",
	)
}

/* Verifies malformed, stale, invalid-name, and allocation failures reject cleanly. */
@(test)
structure_editing_rejects_unsafe_requests :: proc(t: ^testing.T) {
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, "#+begin_note\nbody\n#+end_note\n", 1_202) do return
	defer list_test_fixture_close(&fixture)
	block, found := list_test_node(&fixture.analysis, .Special_Block, 0)
	testing.expect(t, found)
	if !found do return
	plan: language.Jan_Rewrite_Plan
	request := structure_test_request(fixture.scope, .Rename, block.id)
	request.name = "bad name"
	planned, failure := structure_edit_plan_prepare(&plan, &fixture.analysis, transmute([]u8)fixture.source, request)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Target)

	request = structure_test_request(fixture.scope, .Delete, block.id)
	request.scope.analysis.source_revision += 1
	planned, failure = structure_edit_plan_prepare(&plan, &fixture.analysis, transmute([]u8)fixture.source, request)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Failure_Code.Stale)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Visibility_Test_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = 0,
	}
	request = structure_test_request(fixture.scope, .Rename, block.id)
	request.name = "warning"
	planned, failure = structure_edit_plan_prepare(
		&plan,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		request,
		DEFAULT_LIMITS,
		context.allocator,
		visibility_test_failing_allocator(&failing),
	)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Failure_Code.Allocation_Failed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)

	malformed: List_Test_Fixture
	if !list_test_fixture_open(t, &malformed, "#+begin_note\nbody\n", 1_203) do return
	defer list_test_fixture_close(&malformed)
	malformed_block, malformed_found := list_test_node(&malformed.analysis, .Special_Block, 0)
	testing.expect(t, malformed_found)
	if !malformed_found do return
	_, inspected, inspect_failure := structure_inspect(
		&malformed.analysis,
		transmute([]u8)malformed.source,
		malformed.scope,
		malformed_block.id,
	)
	testing.expect(t, !inspected)
	testing.expect_value(t, inspect_failure.code, Failure_Code.Malformed)
}

/* Verifies structural editing delegates task and property semantics to Planning. */
@(test)
structure_editing_reports_linked_task_and_property_owners :: proc(t: ^testing.T) {
	records := structure_future_stage_availability()
	testing.expect_value(t, len(records), 2)
	for record in records {
		testing.expect_value(t, record.class, language.Jan_Availability_Class.Factory_Native)
		testing.expect_value(t, record.owner, language.Jan_Stage.Planning_And_Agenda)
		testing.expect(t, record.available)
	}
	testing.expect_value(
		t,
		string(records[0].capability.bytes[:records[0].capability.length]),
		"jan-task-planning",
	)
	testing.expect_value(
		t,
		string(records[1].capability.bytes[:records[1].capability.length]),
		"jan-property-operations",
	)
}

@(private = "file")
structure_test_expect_edit :: proc(
	t: ^testing.T,
	source, expected: string,
	kind: Structure_Edit_Kind,
	target_kind: language.Jan_Node_Kind,
	ordinal: int,
	template: Structure_Template_Kind,
	name, arguments, body: string,
) {
	fixture: List_Test_Fixture
	id := u64(1_300 + int(kind) * 8 + ordinal)
	if !list_test_fixture_open(t, &fixture, source, id) do return
	defer list_test_fixture_close(&fixture)
	target, found := list_test_node(&fixture.analysis, target_kind, ordinal)
	testing.expect(t, found)
	if !found do return
	request := structure_test_request(fixture.scope, kind, target.id)
	request.template = template
	request.name = name
	request.arguments = arguments
	request.body = body
	plan: language.Jan_Rewrite_Plan
	planned, failure := structure_edit_plan_prepare(
		&plan,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		request,
	)
	testing.expectf(t, planned, "%v plan failed with %v", kind, failure.code)
	if !planned do return
	defer language.jan_rewrite_plan_close(&plan)
	testing.expect(t, list_test_publish_and_history(&fixture, &plan, expected))
}

@(private = "file")
structure_test_request :: proc(
	scope: Scope,
	kind: Structure_Edit_Kind,
	target_id: language.Jan_Node_ID,
) -> Structure_Edit_Request {
	return {operation_id = 61, scope = scope, kind = kind, target_id = target_id, rewrite_generation = 61}
}
