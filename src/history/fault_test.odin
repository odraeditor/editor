// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package history

import "../editor"
import "base:runtime"
import "core:mem"
import "core:testing"

/* Verifies every record-reservation allocation failure preserves topology and releases storage. */
@(test)
record_reservation_faults_leave_no_partial_unit :: proc(t: ^testing.T) {
	saw_success := false
	for failure_offset in 0 ..< 16 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		backing := mem.tracking_allocator(&tracking)
		failing := History_Failing_Allocator {
			backing = backing,
			fail_after = max(u64),
		}
		allocator := history_failing_allocator(&failing)
		store: Store
		initialized, _ := store_init(
			&store,
			Store_ID(u64(failure_offset + 1)),
			editor.Buffer_ID(90),
			editor.Revision(0),
			Allocator_Set{persistent = allocator, temporary = allocator},
		)
		testing.expect(t, initialized)
		if !initialized {
			mem.tracking_allocator_destroy(&tracking)
			continue
		}
		failing.fail_after = failing.successful_allocations + u64(failure_offset)
		edits := [1]Edit_Payload {{
			start = editor.Byte_Offset(1),
			end = editor.Byte_Offset(2),
			replacement_text = "X",
			removed_text = "b",
		}}
		reservation: Reservation
		reserved, reserve_failure := record_reserve(
			&store,
			&reservation,
			Record_Input {
				source_transaction_id = Source_Transaction_ID(1),
				source_undo_unit_id = Source_Undo_Unit_ID(1),
				buffer_id = editor.Buffer_ID(90),
				base_revision = editor.Revision(0),
				result_revision = editor.Revision(1),
				edits = edits[:],
				origin = .Built_In,
				origin_descriptor = "fault-test",
				command = "replace",
			},
		)
		if reserved {
			saw_success = true
			aborted, _ := reservation_abort(&reservation)
			testing.expect(t, aborted)
		} else {
			testing.expect(t, reserve_failure.code == .Persistent_Memory_Limit ||
			                  reserve_failure.code == .Temporary_Memory_Limit)
		}
		stats, stats_ok, _ := store_stats(&store)
		testing.expect(t, stats_ok)
		testing.expect_value(t, stats.usage.retained_nodes, u64(1))
		testing.expect_value(t, stats.usage.retained_records, u64(0))
		closed, _ := store_close(&store)
		testing.expect(t, closed)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
		if saw_success {
			break
		}
	}
	testing.expect(t, saw_success)
}

/* Verifies every linked-set allocation failure aborts all participants and link storage. */
@(test)
reservation_faults_leave_no_partial_link :: proc(t: ^testing.T) {
	saw_success := false
	for failure_offset in 0 ..< 32 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		backing := mem.tracking_allocator(&tracking)
		failing := History_Failing_Allocator{backing = backing, fail_after = max(u64)}
		allocator := history_failing_allocator(&failing)
		first: Store
		second: Store
		first_ok, _ := store_init(
			&first,
			Store_ID(500 + failure_offset * 2),
			editor.Buffer_ID(501),
			editor.Revision(0),
			Allocator_Set{persistent = allocator, temporary = allocator},
		)
		second_ok, _ := store_init(
			&second,
			Store_ID(501 + failure_offset * 2),
			editor.Buffer_ID(502),
			editor.Revision(0),
			Allocator_Set{persistent = allocator, temporary = allocator},
		)
		testing.expect(t, first_ok && second_ok)
		if !first_ok || !second_ok {
			mem.tracking_allocator_destroy(&tracking)
			continue
		}
		failing.fail_after = failing.successful_allocations + u64(failure_offset)
		first_edit := [1]Edit_Payload{{replacement_text = "A", removed_text = "a"}}
		second_edit := [1]Edit_Payload{{replacement_text = "B", removed_text = "b"}}
		reservation: Multibuffer_Reservation
		reserved, failure := multibuffer_record_reserve(
			&reservation,
			[]Multibuffer_Record_Input {
				{store = &first, record = fault_link_record(editor.Buffer_ID(501), first_edit[:])},
				{store = &second, record = fault_link_record(editor.Buffer_ID(502), second_edit[:])},
			},
		)
		if reserved {
			saw_success = true
			aborted, _ := multibuffer_reservation_abort(&reservation)
			testing.expect(t, aborted)
		} else {
			testing.expect(t, failure.code == .Persistent_Memory_Limit || failure.code == .Temporary_Memory_Limit)
		}
		first_stats, _, _ := store_stats(&first)
		second_stats, _, _ := store_stats(&second)
		testing.expect_value(t, first_stats.usage.retained_nodes, u64(1))
		testing.expect_value(t, second_stats.usage.retained_nodes, u64(1))
		testing.expect_value(t, first_stats.usage.retained_links, u64(0))
		store_close(&second)
		store_close(&first)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
		if saw_success {
			break
		}
	}
	testing.expect(t, saw_success)
}

/* Verifies inspection and selective-plan allocation failures retain exact store state. */
@(test)
history_faults_release_temporary_storage :: proc(t: ^testing.T) {
	for operation in 0 ..< 2 {
		saw_success := false
		for failure_offset in 0 ..< 16 {
			tracking: mem.Tracking_Allocator
			mem.tracking_allocator_init(&tracking, context.allocator)
			backing := mem.tracking_allocator(&tracking)
			failing := History_Failing_Allocator{backing = backing, fail_after = max(u64)}
			allocator := history_failing_allocator(&failing)
			store: Store
			initialized, _ := store_init(
				&store,
				Store_ID(u64(operation * 100 + failure_offset + 20)),
				editor.Buffer_ID(91),
				editor.Revision(0),
				Allocator_Set{persistent = allocator, temporary = allocator},
			)
			testing.expect(t, initialized)
			if !initialized {
				mem.tracking_allocator_destroy(&tracking)
				continue
			}
			edits := [1]Edit_Payload {{
				start = editor.Byte_Offset(1),
				end = editor.Byte_Offset(2),
				replacement_text = "X",
				removed_text = "b",
			}}
			reservation: Reservation
			reserved, _ := record_reserve(&store, &reservation, Record_Input {
				source_transaction_id = Source_Transaction_ID(1),
				source_undo_unit_id = Source_Undo_Unit_ID(1),
				buffer_id = editor.Buffer_ID(91),
				base_revision = editor.Revision(0),
				result_revision = editor.Revision(1),
				edits = edits[:],
				origin = .Built_In,
				origin_descriptor = "fault-test",
				command = "replace",
			})
			testing.expect(t, reserved)
			if reserved {
				reservation_commit_reserved(&reservation, editor.Revision(1))
			}
			before, _, _ := store_stats(&store)
			baseline := tracking.current_memory_allocated
			failing.fail_after = failing.successful_allocations + u64(failure_offset)
			if operation == 0 {
				inspection, ok, failure := store_inspect(
					&store,
					Inspection_Request {
						buffer_id = before.buffer_id,
						current_revision = before.current_revision,
						active_node = before.active_node,
						policy_generation = before.policy_generation,
						result_limit = 8,
						traversal_limit = 8,
					},
					allocator,
				)
				if ok {
					saw_success = true
					inspection_release(&inspection, allocator)
				} else {
					testing.expect_value(t, failure.code, Failure_Code.Temporary_Memory_Limit)
				}
			} else {
				plan, ok, failure := selective_prepare(&store, Selective_Request {
					buffer_id = before.buffer_id,
					current_revision = before.current_revision,
					active_node = before.active_node,
					target_unit = Unit_ID(1),
					policy_generation = before.policy_generation,
					analysis_operations = 32,
				})
				if ok {
					saw_success = true
					selective_plan_release(&plan)
				} else {
					testing.expect_value(t, failure.code, Failure_Code.Temporary_Memory_Limit)
				}
			}
			after, _, _ := store_stats(&store)
			testing.expect_value(t, after, before)
			testing.expect_value(t, tracking.current_memory_allocated, baseline)
			closed, _ := store_close(&store)
			testing.expect(t, closed)
			testing.expect_value(t, tracking.current_memory_allocated, i64(0))
			mem.tracking_allocator_destroy(&tracking)
			if saw_success {
				break
			}
		}
		testing.expect(t, saw_success)
	}
}

@(private = "file")
History_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private = "file")
history_failing_allocator :: proc(data: ^History_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = history_failing_allocator_proc, data = data}
}

@(private = "file")
history_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := (^History_Failing_Allocator)(allocator_data)
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize || mode == .Resize_Non_Zeroed {
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

@(private = "file")
fault_link_record :: proc(buffer_id: editor.Buffer_ID, edits: []Edit_Payload) -> Record_Input {
	return Record_Input {
		source_transaction_id = Source_Transaction_ID(700),
		source_undo_unit_id = Source_Undo_Unit_ID(700),
		buffer_id = buffer_id,
		base_revision = editor.Revision(0),
		result_revision = editor.Revision(1),
		edits = edits,
		origin = .Built_In,
		origin_descriptor = "fault-test",
		command = "linked-edit",
	}
}
