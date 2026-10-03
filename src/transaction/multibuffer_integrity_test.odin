// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"
import "base:runtime"
import "core:mem"
import "core:testing"

@(private)
Multibuffer_Observer_Probe :: struct {
	transaction:     ^Multibuffer_Transaction,
	event:           Multibuffer_Commit_Event,
	filtered:        Buffer_Commit_Event,
	invoked:         bool,
	filtered_ok:     bool,
	reentrant_ok:    bool,
	reentrant_failure: Failure_Context,
}

/* Verifies one observer receives the shared event and filtered views preserve identity. */
@(test)
observer_receives_filterable_event :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	first := test_buffer_open(t, &tracking, editor.Buffer_ID(901), "a")
	second := test_buffer_open(t, &tracking, editor.Buffer_ID(902), "b")
	root := test_multibuffer_begin(
		t,
		[]^editor.Buffer{&second, &first},
		&tracking,
		Transaction_ID(900),
	)
	apply_whole_buffer_batch(t, &root, &first, "A")
	apply_whole_buffer_batch(t, &root, &second, "B")
	multibuffer_validate(&root)
	probe := Multibuffer_Observer_Probe{transaction = &root}
	result, committed, failure := multibuffer_commit(
		&root,
		Multibuffer_Observer{procedure = multibuffer_failing_observer, user_data = &probe},
	)
	testing.expectf(t, committed, "commit failed with %v", failure.code)
	testing.expect(t, probe.invoked)
	testing.expect(t, probe.filtered_ok)
	testing.expect_value(t, probe.event.transaction_id, Transaction_ID(900))
	testing.expect_value(t, probe.event.undo_unit_id, Undo_Unit_ID(900))
	testing.expect_value(t, probe.filtered.transaction_id, probe.event.transaction_id)
	testing.expect_value(t, probe.filtered.undo_unit_id, probe.event.undo_unit_id)
	testing.expect_value(t, probe.filtered.buffer.buffer_id, editor.Buffer_ID(902))
	testing.expect(t, !probe.reentrant_ok)
	testing.expect_value(t, probe.reentrant_failure.code, Failure_Code.Reentrant_Mutation)
	testing.expect_value(t, result.observer_status, Observer_Status.Failed)
	_, missing_ok := multibuffer_event_for_buffer(result.event, editor.Buffer_ID(999))
	testing.expect(t, !missing_ok)
	multibuffer_close(&root)
	editor.buffer_close(&second)
	editor.buffer_close(&first)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies cancellation before and after validation publishes no participant. */
@(test)
cancel_aborts_before_publication :: proc(t: ^testing.T) {
	cancel_phases := [2]bool{false, true}
	for cancel_ready in cancel_phases {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		first := test_buffer_open(t, &tracking, editor.Buffer_ID(911), "a")
		second := test_buffer_open(t, &tracking, editor.Buffer_ID(912), "b")
		cancel_offset := 1 if cancel_ready else 0
		root := test_multibuffer_begin(
			t,
			[]^editor.Buffer{&first, &second},
			&tracking,
			Transaction_ID(910 + cancel_offset),
		)
		apply_whole_buffer_batch(t, &root, &first, "A")
		apply_whole_buffer_batch(t, &root, &second, "B")
		if cancel_ready {
			validated, _ := multibuffer_validate(&root)
			testing.expect(t, validated)
		}
		requested, _ := multibuffer_request_cancel(&root)
		testing.expect(t, requested)
		if cancel_ready {
			_, committed, failure := multibuffer_commit(&root)
			testing.expect(t, !committed)
			testing.expect_value(t, failure.code, Failure_Code.Cancelled)
		} else {
			validated, failure := multibuffer_validate(&root)
			testing.expect(t, !validated)
			testing.expect_value(t, failure.code, Failure_Code.Cancelled)
		}
		expect_confirmed_text(t, &first, editor.Revision(0), "a")
		expect_confirmed_text(t, &second, editor.Revision(0), "b")
		closed, _ := multibuffer_close(&root)
		testing.expect(t, closed)
		closed_again, close_failure := multibuffer_close(&root)
		testing.expect(t, !closed_again)
		testing.expect_value(t, close_failure.code, Failure_Code.Invalid_State)
		editor.buffer_close(&second)
		editor.buffer_close(&first)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

/* Injects allocator failure across root and participant preparation without partial state. */
@(test)
alloc_faults_publish_no_partial_set :: proc(t: ^testing.T) {
	for fail_offset in 0 ..= 24 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Transaction_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = max(u64),
		}
		allocator := failing_allocator(&failing)
		first := integrity_buffer_open(t, allocator, editor.Buffer_ID(920), "a")
		second := integrity_buffer_open(t, allocator, editor.Buffer_ID(921), "b")
		third := integrity_buffer_open(t, allocator, editor.Buffer_ID(922), "c")
		failing.fail_after = failing.successful_allocations + u64(fail_offset)
		root: Multibuffer_Transaction
		started, _ := multibuffer_begin(
			&root,
			Transaction_ID(920 + fail_offset),
			Undo_Unit_ID(920 + fail_offset),
			[]^editor.Buffer{&first, &second, &third},
			Origin{kind = .Built_In, descriptor = "fault"},
			"fault",
			Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
		)
		if started {
			first_batch := proposal_replacement_batch(&first, "A")
			second_batch := proposal_replacement_batch(&second, "B")
			third_batch := proposal_replacement_batch(&third, "C")
			first_ok, _ := multibuffer_apply_batch(&root, editor.Buffer_ID(920), first_batch[:])
			second_ok := false
			third_ok := false
			if first_ok {
				second_ok, _ = multibuffer_apply_batch(&root, editor.Buffer_ID(921), second_batch[:])
			}
			if second_ok {
				third_ok, _ = multibuffer_apply_batch(&root, editor.Buffer_ID(922), third_batch[:])
			}
			if third_ok {
				validated, _ := multibuffer_validate(&root)
				if validated {
					multibuffer_commit(&root)
				}
			}
			multibuffer_close(&root)
		}
		first_stats, _, _ := editor.buffer_stats(&first)
		second_stats, _, _ := editor.buffer_stats(&second)
		third_stats, _, _ := editor.buffer_stats(&third)
		all_original := first_stats.revision == 0 && second_stats.revision == 0 && third_stats.revision == 0
		all_committed := first_stats.revision == 1 && second_stats.revision == 1 && third_stats.revision == 1
		testing.expect(t, all_original || all_committed)
		editor.buffer_close(&third)
		editor.buffer_close(&second)
		editor.buffer_close(&first)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

/* Exercises generated participant counts, input order, Unicode, and normalized results. */
@(test)
generated_cases_match_model :: proc(t: ^testing.T) {
	replacements := [4]string{"", "X", "λ", "🙂"}
	for case_index in 0 ..< 32 {
		participant_count := 2 + case_index % 5
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		buffers := make([]editor.Buffer, participant_count)
		buffer_pointers := make([]^editor.Buffer, participant_count)
		for index in 0 ..< participant_count {
			buffer_id := editor.Buffer_ID(1_000 + case_index * 8 + index)
			buffers[index] = test_buffer_open(t, &tracking, buffer_id, "abc")
			buffer_pointers[participant_count - index - 1] = &buffers[index]
		}
		root := test_multibuffer_begin(
			t,
			buffer_pointers,
			&tracking,
			Transaction_ID(1_000 + case_index),
		)
		for &buffer, index in buffers {
			replacement := replacements[(case_index + index) % len(replacements)]
			batch := proposal_replacement_batch(&buffer, replacement)
			stats, _, _ := editor.buffer_stats(&buffer)
			applied, failure := multibuffer_apply_batch(&root, stats.buffer_id, batch[:])
			testing.expectf(t, applied, "generated apply failed with %v", failure.code)
		}
		validated, validation_failure := multibuffer_validate(&root)
		testing.expectf(t, validated, "generated validate failed with %v", validation_failure.code)
		result, committed, commit_failure := multibuffer_commit(&root)
		testing.expectf(t, committed, "generated commit failed with %v", commit_failure.code)
		testing.expect_value(t, len(result.buffers), participant_count)
		for &buffer, index in buffers {
			replacement := replacements[(case_index + index) % len(replacements)]
			expect_confirmed_text(t, &buffer, editor.Revision(1), replacement)
		}
		multibuffer_close(&root)
		for &buffer in buffers {
			editor.buffer_close(&buffer)
		}
		delete(buffer_pointers)
		delete(buffers)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

@(private)
multibuffer_failing_observer :: proc(user_data: rawptr, event: Multibuffer_Commit_Event) -> bool {
	probe := (^Multibuffer_Observer_Probe)(user_data)
	probe.invoked = true
	probe.event = event
	probe.filtered, probe.filtered_ok = multibuffer_event_for_buffer(event, editor.Buffer_ID(902))
	probe.reentrant_ok, probe.reentrant_failure = multibuffer_close(probe.transaction)
	return false
}

@(private)
integrity_buffer_open :: proc(
	t: ^testing.T,
	allocator: runtime.Allocator,
	buffer_id: editor.Buffer_ID,
	contents: string,
) -> editor.Buffer {
	buffer: editor.Buffer
	initialized, failure := editor.buffer_init(
		&buffer,
		buffer_id,
		contents,
		editor.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, initialized, "buffer init failed with %v", failure.code)
	return buffer
}
