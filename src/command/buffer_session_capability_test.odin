// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor_session"
import "../interaction"
import "core:os"
import "core:testing"

/* Verifies copied inspection and lifecycle operations refresh exact session scope. */
@(test)
session_capability_composes_lifecycle :: proc(t: ^testing.T) {
	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(751),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	ctx := buffer_session_capability_test_context(&session, handle, {
		.Usage_Inspection,
		.Descriptor_Inspection,
		.Create,
		.Open,
		.Activate,
		.Save,
		.Kill,
	})
	scope, scoped, scope_failure := buffer_session_capability_scope(ctx)
	testing.expectf(t, scoped, "scope failed with %v", scope_failure.buffer_session_capability_code)
	if !scoped {
		return
	}
	initial, inspected, _ := buffer_session_usage_inspect(ctx, scope)
	testing.expect(t, inspected)
	testing.expect_value(t, initial.usage.live_buffers, u32(0))

	first, first_ok, _ := buffer_session_capability_create(ctx, scope, "first")
	testing.expect(t, first_ok)
	if !first_ok {
		return
	}
	_, stale_ok, stale_failure := buffer_session_usage_inspect(ctx, scope)
	testing.expect(t, !stale_ok)
	testing.expect_value(
		t,
		stale_failure.buffer_session_capability_code,
		Buffer_Session_Capability_Failure_Code.Stale_Visible_Target,
	)
	second, second_ok, _ := buffer_session_capability_create(ctx, first.scope, "second")
	testing.expect(t, second_ok)
	if !second_ok {
		return
	}

	descriptors, descriptors_ok, _ := buffer_session_descriptors_inspect(ctx, second.scope)
	testing.expect(t, descriptors_ok)
	if descriptors_ok {
		testing.expect_value(t, len(descriptors.descriptors), 2)
		testing.expect_value(t, descriptors.descriptors[0].selection_label, "second")
		editor_session.descriptor_batch_close(&descriptors)
	}
	first_copy, first_copy_ok, _ := buffer_session_descriptor_inspect(
		ctx,
		second.scope,
		first.operation.entry,
	)
	testing.expect(t, first_copy_ok)
	if first_copy_ok {
		testing.expect_value(t, first_copy.descriptor.selection_label, "first")
		buffer_descriptor_copy_close(&first_copy)
	}

	activated, activated_ok, _ := buffer_session_capability_activate(
		ctx,
		second.scope,
		first.operation.entry,
	)
	testing.expect(t, activated_ok)
	if !activated_ok {
		return
	}
	directory, directory_error := os.make_directory_temp("", "odra-buffer-capability-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return
	}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path, path_error := os.join_path({directory, "first.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil {
		return
	}
	defer delete(path)
	saved, saved_ok, save_failure := buffer_session_capability_save(
		ctx,
		activated.scope,
		first.operation.entry,
		path,
	)
	testing.expectf(t, saved_ok, "save failed with %v", save_failure.code)
	if !saved_ok {
		return
	}
	testing.expect(t, saved.save.publication == .Published_Durable ||
	                  saved.save.publication == .Published_Durability_Uncertain)

	killed_second, second_killed, _ := buffer_session_capability_kill(
		ctx,
		saved.scope,
		second.operation.entry,
	)
	testing.expect(t, second_killed)
	if !second_killed {
		return
	}
	_, stale_entry_ok, stale_entry_failure := buffer_session_descriptor_inspect(
		ctx,
		killed_second.scope,
		second.operation.entry,
	)
	testing.expect(t, !stale_entry_ok)
	testing.expect_value(
		t,
		stale_entry_failure.buffer_session_capability_code,
		Buffer_Session_Capability_Failure_Code.Descriptor_Not_Found,
	)
	killed_first, first_killed, _ := buffer_session_capability_kill(
		ctx,
		killed_second.scope,
		first.operation.entry,
	)
	testing.expect(t, first_killed)
	if first_killed {
		testing.expect(t, killed_first.kill.closure.last_buffer)
	}
	closed, _ := editor_session.session_close(&session)
	testing.expect(t, closed)
}

/* Verifies immutable permissions and editor, registry, and entry generations are checked. */
@(test)
session_capability_rejects_bad_scope :: proc(t: ^testing.T) {
	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(753),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	ctx := buffer_session_capability_test_context(&session, handle, {.Usage_Inspection})
	scope, scoped, _ := buffer_session_capability_scope(ctx)
	testing.expect(t, scoped)
	if !scoped {
		return
	}
	_, allowed, denied := buffer_session_descriptors_inspect(ctx, scope)
	testing.expect(t, !allowed)
	testing.expect_value(
		t,
		denied.buffer_session_capability_code,
		Buffer_Session_Capability_Failure_Code.Permission_Denied,
	)

	wrong := scope
	wrong.editor_session_id = Editor_Session_ID(999)
	_, allowed, denied = buffer_session_usage_inspect(ctx, wrong)
	testing.expect(t, !allowed)
	testing.expect_value(
		t,
		denied.buffer_session_capability_code,
		Buffer_Session_Capability_Failure_Code.Wrong_Editor,
	)
	wrong = scope
	wrong.registry.generation += 1
	_, allowed, denied = buffer_session_usage_inspect(ctx, wrong)
	testing.expect(t, !allowed)
	testing.expect_value(
		t,
		denied.buffer_session_capability_code,
		Buffer_Session_Capability_Failure_Code.Stale_Registry,
	)
	wrong = scope
	wrong.access = {.Descriptor_Inspection}
	_, allowed, denied = buffer_session_usage_inspect(ctx, wrong)
	testing.expect(t, !allowed)
	testing.expect_value(
		t,
		denied.buffer_session_capability_code,
		Buffer_Session_Capability_Failure_Code.Wrong_Authority,
	)
	closed, _ := editor_session.session_close(&session)
	testing.expect(t, closed)
}

/* Verifies copied semantic marks are checked and executed through the capability. */
@(test)
session_capability_executes_marks :: proc(t: ^testing.T) {
	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(755),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	first, first_ok, _ := editor_session.session_create_buffer(
		&session,
		editor_session.Create_Buffer_Request {
			session = handle,
			name = "first",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	second, second_ok, _ := editor_session.session_create_buffer(
		&session,
		editor_session.Create_Buffer_Request {
			session = handle,
			name = "second",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, first_ok && second_ok)
	if !first_ok || !second_ok {
		return
	}
	ctx := buffer_session_capability_test_context(
		&session,
		handle,
		{.Marked_Execution},
	)
	scope, scoped, _ := buffer_session_capability_scope(ctx)
	testing.expect(t, scoped)
	if !scoped {
		return
	}
	_, invalid_ok, invalid_failure := buffer_session_capability_execute_marks(
		ctx,
		scope,
		nil,
		nil,
	)
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Invalid_Request)
	marks := []Buffer_Marked_Entry {
		{entry = first.entry, kind = .Kill},
		{entry = second.entry, kind = .Kill},
	}
	executed, executed_ok, execute_failure := buffer_session_capability_execute_marks(
		ctx,
		scope,
		marks,
		nil,
	)
	testing.expectf(t, executed_ok, "marked execution failed with %v", execute_failure.code)
	if executed_ok {
		testing.expect_value(t, executed.execution.completed_kills, u32(2))
		testing.expect_value(t, executed.scope.visible.kind, editor_session.Visible_Target_Kind.None)
	}
	_, first_live, _ := editor_session.session_entry_access(&session, first.entry)
	_, second_live, _ := editor_session.session_entry_access(&session, second.entry)
	testing.expect(t, !first_live && !second_live)
	closed, _ := editor_session.session_close(&session)
	testing.expect(t, closed)
}

@(private)
buffer_session_capability_test_context :: proc(
	session: ^editor_session.Session,
	handle: editor_session.Session_Handle,
	access: Buffer_Session_Access_Set,
) -> Buffer_Session_Capability_Context {
	return Buffer_Session_Capability_Context {
		editor_session_id = Editor_Session_ID(751),
		access = access,
		buffer_session = Buffer_Session_Context {
			session = session,
			handle = handle,
			command = interaction.Command_Handle {
				registry_generation = 1,
				slot = 1,
				entry_generation = 1,
			},
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
		temporary_allocator = context.allocator,
	}
}
