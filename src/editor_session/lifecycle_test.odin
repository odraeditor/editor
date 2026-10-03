// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor_session

import "../editor"
import "../history"
import editor_view "../view"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:testing"

/* Ensures rejected collisions retain caller resources and session accounting. */
@(test)
collision_rejection_keeps_resources :: proc(t: ^testing.T) {
	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(101), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	first, first_ok := test_resources_init(t, 101, "first")
	if !first_ok {
		session_close(&session)
		return
	}
	first_entry, published := test_publish_resources(t, &session, handle, "same", &first)
	if !published {
		test_resources_close(&first)
		session_close(&session)
		return
	}
	usage_before, usage_ok, _ := session_usage(&session, handle)
	testing.expect(t, usage_ok)

	second, second_ok := test_resources_init(t, 102, "second")
	if !second_ok {
		return
	}
	prepared: Prepared_Entry
	_, prepared_ok, prepare_failure := session_entry_prepare(
		&session,
		Entry_Prepare_Request {
			session = handle,
			kind = .Text,
			selection_label = "same",
			association = .Unassociated,
			resources = Entry_Resources {
				buffer = &second.buffer,
				history_store = &second.history_store,
				document = &second.document,
				has_document = true,
			},
			view_config = editor_view.DEFAULT_CONFIG,
		},
		&prepared,
	)
	testing.expect(t, !prepared_ok)
	testing.expect_value(t, prepare_failure.code, Failure_Code.Name_Collision)
	testing.expect(t, editor.buffer_is_live(&second.buffer))
	testing.expect(t, history.store_is_valid(&second.history_store))
	usage_after, usage_after_ok, _ := session_usage(&session, handle)
	testing.expect(t, usage_after_ok)
	testing.expect_value(t, usage_after, usage_before)
	test_resources_close(&second)
	test_detach_release(t, &session, first_entry)
	closed, _ := session_close(&session)
	testing.expect(t, closed)
}

/* Ensures abort and detach invalidate reservations and stale handles. */
@(test)
abort_detach_invalidate_reservations :: proc(t: ^testing.T) {
	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(103), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	aborted_resources, aborted_ok := test_resources_init(t, 103, "abort")
	if !aborted_ok {
		session_close(&session)
		return
	}
	prepared: Prepared_Entry
	_, prepared_ok, _ := session_entry_prepare(
		&session,
		test_prepare_request(handle, "abort", &aborted_resources),
		&prepared,
	)
	testing.expect(t, prepared_ok)
	_, close_ok_failure := session_close(&session)
	testing.expect_value(t, close_ok_failure.code, Failure_Code.Retained_Preparations)
	aborted, abort_failure := prepared_entry_abort(&prepared)
	testing.expect(t, aborted)
	testing.expect_value(t, abort_failure.code, Failure_Code.None)

	first, first_ok := test_resources_init(t, 104, "first")
	if !first_ok {
		session_close(&session)
		return
	}
	stale, first_published := test_publish_resources(t, &session, handle, "first", &first)
	if !first_published {
		return
	}
	test_detach_release(t, &session, stale)
	_, stale_ok, stale_failure := session_activate(&session, stale)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Entry)

	second, second_ok := test_resources_init(t, 105, "second")
	if !second_ok {
		return
	}
	replacement, second_published := test_publish_resources(t, &session, handle, "second", &second)
	testing.expect(t, second_published)
	if second_published {
		testing.expect_value(t, replacement.slot, stale.slot)
		testing.expect(t, replacement.generation != stale.generation)
		test_detach_release(t, &session, replacement)
	}
	usage, usage_ok, _ := session_usage(&session, handle)
	testing.expect(t, usage_ok)
	testing.expect_value(t, usage.live_buffers, u32(0))
	testing.expect_value(t, usage.canonical_text_bytes, u64(0))
	testing.expect_value(t, usage.history_bytes, u64(0))
	closed, _ := session_close(&session)
	testing.expect(t, closed)
}

/* Ensures initialization faults release every allocation before publication. */
@(test)
init_faults_release_allocator_bytes :: proc(t: ^testing.T) {
	for fail_after in 0 ..< 5 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Session_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		session: Session
		_, initialized, failure := session_init(
			&session,
			Session_ID(200 + fail_after),
			Allocator_Set {
				persistent = session_failing_allocator(&failing),
				temporary = context.temp_allocator,
			},
		)
		testing.expect(t, !initialized)
		testing.expect(t, failure.code == .Persistent_Memory_Limit || failure.code == .View_Failure)
		testing.expect(t, session.state == nil)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

/* Exercises permuted registry operations to preserve MRU order and exact teardown. */
@(test)
generated_registry_keeps_mru_and_teardown :: proc(t: ^testing.T) {
	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(301), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	entries: [16]Entry_Handle
	for ordinal in 0 ..< len(entries) {
		label_storage: [32]byte
		label := fmt.bprintf(label_storage[:], "generated-%02d", ordinal)
		resources, resources_ok := test_resources_init(t, u64(301 + ordinal), label)
		if !resources_ok {
			return
		}
		entry, published := test_publish_resources(t, &session, handle, label, &resources)
		if !published {
			test_resources_close(&resources)
			return
		}
		entries[ordinal] = entry
	}
	for step in 0 ..< 64 {
		index := (step * 7) % len(entries)
		activation, activated, activation_failure := session_activate(&session, entries[index])
		testing.expect(t, activated)
		testing.expect_value(t, activation_failure.code, Failure_Code.None)
		testing.expect_value(t, activation.visible.entry, entries[index])
	}
	for step in 0 ..< len(entries) {
		index := (step * 5) % len(entries)
		test_detach_release(t, &session, entries[index])
	}
	usage, usage_ok, _ := session_usage(&session, handle)
	testing.expect(t, usage_ok)
	testing.expect_value(t, usage.live_buffers, u32(0))
	testing.expect_value(t, usage.live_documents, u32(0))
	testing.expect_value(t, usage.canonical_text_bytes, u64(0))
	testing.expect_value(t, usage.retained_label_bytes, u64(0))
	testing.expect_value(t, usage.history_bytes, u64(0))
	closed, _ := session_close(&session)
	testing.expect(t, closed)
}

@(private)
Session_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
session_failing_allocator :: proc(data: ^Session_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = session_failing_allocator_proc, data = data}
}

@(private)
session_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := (^Session_Failing_Allocator)(allocator_data)
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after {
			return nil, .Out_Of_Memory
		}
		allocator.successful_allocations += 1
	}
	return allocator.backing.procedure(
		allocator.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}

@(private)
test_session_allocators :: proc() -> Allocator_Set {
	return Allocator_Set {
		persistent = context.allocator,
		temporary = context.temp_allocator,
	}
}

@(private)
test_prepare_request :: proc(
	handle: Session_Handle,
	label: string,
	resources: ^Test_Resources,
) -> Entry_Prepare_Request {
	return Entry_Prepare_Request {
		session = handle,
		kind = .Text,
		selection_label = label,
		association = .Unassociated,
		resources = Entry_Resources {
			buffer = &resources.buffer,
			history_store = &resources.history_store,
			document = &resources.document,
			has_document = true,
		},
		view_config = editor_view.DEFAULT_CONFIG,
	}
}

@(private)
test_publish_resources :: proc(
	t: ^testing.T,
	session: ^Session,
	handle: Session_Handle,
	label: string,
	resources: ^Test_Resources,
) -> (entry: Entry_Handle, ok: bool) {
	prepared: Prepared_Entry
	_, prepared_ok, prepare_failure := session_entry_prepare(
		session,
		test_prepare_request(handle, label, resources),
		&prepared,
	)
	testing.expect(t, prepared_ok)
	testing.expect_value(t, prepare_failure.code, Failure_Code.None)
	if !prepared_ok {
		return {}, false
	}
	result, published, publish_failure := prepared_entry_publish(&prepared)
	testing.expect(t, published)
	testing.expect_value(t, publish_failure.code, Failure_Code.None)
	return result.entry, published
}

@(private)
test_detach_release :: proc(t: ^testing.T, session: ^Session, entry: Entry_Handle) {
	detached: Detached_Entry
	_, detached_ok, detach_failure := session_entry_detach(session, entry, &detached)
	testing.expect(t, detached_ok)
	testing.expect_value(t, detach_failure.code, Failure_Code.None)
	if !detached_ok {
		return
	}
	_, cleaned, cleanup_failure := detached_entry_cleanup(&detached)
	testing.expect(t, cleaned)
	testing.expect_value(t, cleanup_failure.code, Failure_Code.None)
	if !cleaned {
		return
	}
	released, release_failure := detached_entry_release(&detached)
	testing.expect(t, released)
	testing.expect_value(t, release_failure.code, Failure_Code.None)
}
