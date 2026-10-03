// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor"
import "../interaction"
import "../kill_ring"
import "core:testing"

/* Verifies authorized region and ring inspection return only bounded copied values. */
@(test)
transfer_copies_region_ring_and_entry :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "alpha beta", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	execute_named(&fixture, "set-mark-command")
	for _ in 0 ..< 5 {
		execute_named(&fixture, "cursor-next-grapheme")
	}
	test_ring_admit(t, &fixture.kill_ring, "older")
	test_ring_admit(t, &fixture.kill_ring, "newest")
	capability := transfer_test_context(&fixture, {
		.Region_Inspection,
		.Ring_Inspection,
		.Entry_Text,
		.Semantic_Invocation,
	})
	scope, scoped, scope_failure := transfer_capability_scope(capability)
	testing.expectf(t, scoped, "scope failed with %v", scope_failure.transfer_code)
	if !scoped {
		return
	}

	region, inspected, inspect_failure := transfer_region_inspect(capability, scope)
	testing.expectf(t, inspected, "region failed with %v", inspect_failure.transfer_code)
	testing.expect_value(t, region.point.byte_offset, editor.Byte_Offset(5))
	testing.expect(t, region.mark_present && region.region_present && region.region_active)
	testing.expect_value(t, region.mark.byte_offset, editor.Byte_Offset(0))
	testing.expect_value(t, region.region_start, editor.Byte_Offset(0))
	testing.expect_value(t, region.region_end, editor.Byte_Offset(5))

	ring, ring_ok, ring_failure := transfer_ring_inspect(capability, scope, 2)
	testing.expectf(t, ring_ok, "ring failed with %v", ring_failure.code)
	if !ring_ok {
		return
	}
	testing.expect_value(t, len(ring.inspection.entries), 2)
	testing.expect_value(t, ring.inspection.entries[0].byte_count, u64(6))
	newest := ring.inspection.entries[0].id
	transfer_ring_summary_close(&ring, capability.native.temporary_allocator)

	entry, entry_ok, entry_failure := transfer_entry_text(
		capability,
		scope,
		newest,
		kill_ring.DEFAULT_ENTRY_BYTES,
	)
	testing.expectf(t, entry_ok, "entry failed with %v", entry_failure.code)
	if entry_ok {
		testing.expect_value(t, entry.entry.text, "newest")
		transfer_entry_text_close(&entry, capability.native.temporary_allocator)
	}

	region_only := capability
	region_only.access = {.Region_Inspection}
	region_scope, region_scoped, _ := transfer_capability_scope(region_only)
	testing.expect(t, region_scoped)
	_, denied, denied_failure := transfer_ring_inspect(region_only, region_scope, 1)
	testing.expect(t, !denied)
	testing.expect_value(t, denied_failure.transfer_code, Transfer_Failure_Code.Permission_Denied)

	cancelled := capability
	cancelled.native.cancelled = true
	_, cancelled_ok, cancelled_failure := transfer_capability_scope(cancelled)
	testing.expect(t, !cancelled_ok)
	testing.expect_value(t, cancelled_failure.code, Failure_Code.Cancelled)
}

/* Verifies every captured native identity rejects a mismatched or stale request. */
@(test)
transfer_rejects_stale_scope :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "scope", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	capability := transfer_test_context(&fixture, {.Region_Inspection})
	scope, scoped, _ := transfer_capability_scope(capability)
	testing.expect(t, scoped)
	if !scoped {
		return
	}

	wrong := scope
	wrong.editor_session_id = Editor_Session_ID(78)
	_, ok, failure := transfer_region_inspect(capability, wrong)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.transfer_code, Transfer_Failure_Code.Wrong_Editor)

	wrong = scope
	wrong.view.generation += 1
	_, ok, failure = transfer_region_inspect(capability, wrong)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.transfer_code, Transfer_Failure_Code.Wrong_View)

	wrong = scope
	wrong.buffer_id = editor.Buffer_ID(999)
	_, ok, failure = transfer_region_inspect(capability, wrong)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.transfer_code, Transfer_Failure_Code.Wrong_Buffer)

	wrong = scope
	wrong.revision = editor.Revision(1)
	_, ok, failure = transfer_region_inspect(capability, wrong)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.transfer_code, Transfer_Failure_Code.Stale_Revision)

	wrong = scope
	wrong.ring_id = kill_ring.Ring_ID(999)
	_, ok, failure = transfer_region_inspect(capability, wrong)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.transfer_code, Transfer_Failure_Code.Wrong_Ring)

	wrong = scope
	wrong.ring_generation = kill_ring.Generation(u64(scope.ring_generation) + 1)
	_, ok, failure = transfer_region_inspect(capability, wrong)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.transfer_code, Transfer_Failure_Code.Stale_Ring_Generation)

	wrong = scope
	wrong.command_registry_generation = interaction.Registry_Generation(99)
	_, ok, failure = transfer_region_inspect(capability, wrong)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.transfer_code, Transfer_Failure_Code.Stale_Command_Registry)

	execute_named(&fixture, "cursor-next-grapheme")
	_, ok, failure = transfer_region_inspect(capability, scope)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.transfer_code, Transfer_Failure_Code.Stale_View_State)
}

/* Verifies semantic invocation is whitelisted, scoped, and returns fresh identities. */
@(test)
transfer_invokes_allowed_commands :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "alpha", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	execute_named(&fixture, "set-mark-command")
	for _ in 0 ..< 5 {
		execute_named(&fixture, "cursor-next-grapheme")
	}
	capability := transfer_test_context(&fixture, {
		.Region_Inspection,
		.Ring_Inspection,
		.Entry_Text,
		.Semantic_Invocation,
	})
	scope, scoped, _ := transfer_capability_scope(capability)
	testing.expect(t, scoped)
	if !scoped {
		return
	}

	_, allowed, allowed_failure := transfer_command_invoke(
		capability,
		Transfer_Command_Request {
			expected_scope = scope,
			name = "cursor-next-grapheme",
		},
	)
	testing.expect(t, !allowed)
	testing.expect_value(t, allowed_failure.transfer_code, Transfer_Failure_Code.Command_Not_Allowed)

	result, invoked, invoke_failure := transfer_command_invoke(
		capability,
		Transfer_Command_Request {
			expected_scope = scope,
			name = "copy-region",
		},
	)
	testing.expectf(t, invoked, "copy invocation failed with %v", invoke_failure.code)
	if !invoked {
		return
	}
	testing.expect_value(t, result.native.completion, Native_Completion.Text_Retained)
	testing.expect(t, result.result_scope.ring_generation != scope.ring_generation)
	testing.expect_value(t, result.result_scope.revision, scope.revision)
	fresh_scope := result.result_scope
	transfer_command_result_close(&result)

	_, stale, stale_failure := transfer_region_inspect(capability, scope)
	testing.expect(t, !stale)
	testing.expect_value(t, stale_failure.transfer_code, Transfer_Failure_Code.Stale_Ring_Generation)
	region, fresh, fresh_failure := transfer_region_inspect(
		capability,
		fresh_scope,
	)
	testing.expectf(t, fresh, "fresh scope failed with %v", fresh_failure.transfer_code)
	if fresh {
		testing.expect_value(t, region.region_start, editor.Byte_Offset(0))
		testing.expect_value(t, region.region_end, editor.Byte_Offset(5))
	}
}

@(private = "file")
transfer_test_context :: proc(
	fixture: ^Native_Fixture,
	access: Transfer_Access_Set,
) -> Transfer_Capability_Context {
	native := native_request(fixture, {})
	native.history_store = &fixture.history
	native.kill_ring = &fixture.kill_ring
	native.kill_sequence_id = 1
	native.event_sequence = u64(native.transaction_id)
	native.yank_context = &fixture.yank_context
	return Transfer_Capability_Context {
		editor_session_id = Editor_Session_ID(77),
		access = access,
		native = native,
	}
}
