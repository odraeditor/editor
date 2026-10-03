// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import "base:runtime"
import "core:mem"
import "core:testing"
import "core:time"

@(private)
FIXTURE_PATH :: "tests/fixtures/language-service-server.rkt"

@(private)
fixture_command :: proc(mode: string, argument := "") -> [4]string {
	return {"racket", FIXTURE_PATH, mode, argument}
}

@(private)
poll_until_frame_or_failure :: proc(session: ^Process_Session, now: ^i64) -> Process_Poll {
	result: Process_Poll
	for _ in 0 ..< 1_000 {
		result, _ = process_session_poll(session, now^)
		if result.frame_ready || result.health == .Failed || result.health == .Stopped do return result
		time.sleep(time.Millisecond)
		now^ += i64(time.Millisecond)
	}
	return result
}

/* Verifies an external fixture round trip across fragmented nonblocking IO. */
@(test)
fixture_round_trip_contains_fragmented_io :: proc(t: ^testing.T) {
	command_storage := fixture_command("echo-fragment")
	command := command_storage[:3]
	session, started, failure := process_session_start(test_process_request(command), 1)
	testing.expectf(t, started, "fixture start failed with %v", failure.code)
	if !started do return
	defer process_session_close(&session)

	confirmed, confirmation_failure := process_session_confirm_initialized(
		&session,
		Capability_Values{position_encoding = .UTF_16, synchronization_mode = .Full},
	)
	testing.expectf(t, confirmed, "fixture initialization failed with %v", confirmation_failure.code)
	body := transmute([]u8)(string(`{"jsonrpc":"2.0","id":7,"method":"fixture/ping"}`))
	queued, queue_failure := process_session_send_frame(&session, body)
	testing.expectf(t, queued, "fixture request failed with %v", queue_failure.code)
	queued_inspection, inspected := process_session_inspect(&session)
	testing.expect(t, inspected)
	testing.expect_value(t, queued_inspection.usage.queue_depth, u32(1))
	testing.expect(t, queued_inspection.usage.queue_bytes > u64(len(body)))
	now := i64(1)
	poll := poll_until_frame_or_failure(&session, &now)
	testing.expect_value(t, poll.health, Health.Active)
	testing.expect(t, poll.frame_ready)
	drained_inspection, drained_inspected := process_session_inspect(&session)
	testing.expect(t, drained_inspected)
	testing.expect_value(t, drained_inspection.usage.queue_depth, u32(0))
	testing.expect_value(t, drained_inspection.usage.queue_bytes, u64(0))

	frame, taken, frame_failure := process_session_take_frame(&session)
	testing.expectf(t, taken, "fixture frame failed with %v", frame_failure.code)
	if taken {
		message, decoded, decode_failure := message_decode(frame.body)
		testing.expectf(t, decoded, "fixture message failed with %v", decode_failure.code)
		if decoded {
			testing.expect_value(t, message.record.kind, Message_Kind.Request)
			testing.expect_value(t, message.record.id.integer, i64(7))
			message_close(&message)
		}
		frame_close(&frame)
	}
}

/* Verifies external malformed JSON and oversized protocol output are contained. */
@(test)
fixture_contains_malformed_and_excessive_output :: proc(t: ^testing.T) {
	malformed_storage := fixture_command("malformed-json")
	malformed, started, failure := process_session_start(test_process_request(malformed_storage[:3]), 1)
	testing.expectf(t, started, "malformed fixture start failed with %v", failure.code)
	if started {
		now := i64(1)
		poll := poll_until_frame_or_failure(&malformed, &now)
		testing.expect(t, poll.frame_ready)
		frame, taken, _ := process_session_take_frame(&malformed)
		testing.expect(t, taken)
		if taken {
			_, decoded, decode_failure := message_decode(frame.body)
			testing.expect(t, !decoded)
			testing.expect_value(t, decode_failure.code, Failure_Code.Malformed_JSON)
			frame_close(&frame)
		}
		process_session_close(&malformed)
	}

	limits := DEFAULT_LIMITS
	limits.message_bytes = 64
	request := test_process_request(nil)
	oversized_storage := fixture_command("oversized", "65")
	request.command = oversized_storage[:]
	request.limits = limits
	oversized, oversized_started, oversized_failure := process_session_start(request, 1)
	testing.expectf(t, oversized_started, "oversized fixture start failed with %v", oversized_failure.code)
	if oversized_started {
		now := i64(1)
		poll := poll_until_frame_or_failure(&oversized, &now)
		testing.expect_value(t, poll.health, Health.Failed)
		testing.expect_value(t, poll.failure.code, Failure_Code.Resource_Limit)
		testing.expect_value(t, poll.failure.resource, Resource_Kind.Message_Bytes)
		process_session_close(&oversized)
	}

	flood_limits := DEFAULT_LIMITS
	flood_limits.message_bytes = 64
	flood_limits.buffered_stream_bytes = 256
	flood_limits.queue_bytes = 64
	flood_limits.synchronization_bytes = 64
	flood_request := test_process_request(nil)
	flood_storage := fixture_command("flood")
	flood_request.command = flood_storage[:3]
	flood_request.limits = flood_limits
	flood, flood_started, flood_failure := process_session_start(flood_request, 1)
	testing.expectf(t, flood_started, "flood fixture start failed with %v", flood_failure.code)
	if flood_started {
		now := i64(1)
		poll := poll_until_frame_or_failure(&flood, &now)
		testing.expect_value(t, poll.health, Health.Failed)
		testing.expect(t, poll.failure.code == .Protocol || poll.failure.code == .Resource_Limit)
		process_session_close(&flood)
	}
}

/* Verifies process crash status, bounded stderr, and exact child reaping. */
@(test)
fixture_contains_crash_and_reaps_child :: proc(t: ^testing.T) {
	command_storage := fixture_command("crash")
	session, started, failure := process_session_start(test_process_request(command_storage[:3]), 1)
	testing.expectf(t, started, "crash fixture start failed with %v", failure.code)
	if !started do return
	defer process_session_close(&session)

	now := i64(1)
	poll := poll_until_frame_or_failure(&session, &now)
	for _ in 0 ..< 100 {
		if poll.process_exited do break
		time.sleep(time.Millisecond)
		now += i64(time.Millisecond)
		poll, _ = process_session_poll(&session, now)
	}
	testing.expect_value(t, poll.health, Health.Failed)
	testing.expect(t, poll.process_exited)
	testing.expect_value(t, poll.exit_status, i32(23))
	standard_error: [64]u8
	count, copied := process_session_copy_stderr(&session, standard_error[:])
	testing.expect(t, copied)
	testing.expect_value(t, string(standard_error[:count]), "fixture-crash")
	inspection, inspected := process_session_inspect(&session)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.process.state, Process_State.Reaped)
	stale := inspection.session.handle
	restarted, restart_failure := process_session_restart(&session, now)
	testing.expectf(t, restarted, "fixture restart failed with %v", restart_failure.code)
	valid, stale_failure := process_session_validate_handle(&session, stale)
	testing.expect(t, !valid)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Generation)
	current, current_inspected := process_session_inspect(&session)
	testing.expect(t, current_inspected)
	valid, stale_failure = process_session_validate_handle(&session, current.session.handle)
	testing.expect(t, valid)
	testing.expect_value(t, stale_failure.code, Failure_Code.None)
}

/* Verifies generated fragments preserve complete framing and exact cleanup. */
@(test)
generated_framing_matches_copied_bodies :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	decoder, opened, failure := frame_decoder_open(DEFAULT_LIMITS, allocator)
	testing.expectf(t, opened, "decoder open failed with %v", failure.code)
	if !opened {
		mem.tracking_allocator_destroy(&tracking)
		return
	}

	for length in 1 ..= 128 {
		body := make([]u8, length)
		for &value, index in body do value = u8('a' + index % 26)
		header_storage: [64]u8
		header := fmt_frame_header(header_storage[:], length)
		framed := make([dynamic]u8, 0, len(header) + len(body))
		_, _ = append(&framed, ..header)
		_, _ = append(&framed, ..body)
		offset := 0
		for offset < len(framed) {
			chunk := min(len(framed) - offset, 1 + (length + offset) % 11)
			_, accepted, push_failure := frame_decoder_push(&decoder, framed[offset:offset + chunk])
			testing.expectf(t, accepted, "fragment rejected with %v", push_failure.code)
			offset += chunk
		}
		frame, taken, take_failure := frame_decoder_take(&decoder)
		testing.expectf(t, taken, "generated frame failed with %v", take_failure.code)
		if taken {
			testing.expect_value(t, string(frame.body), string(body))
			frame_close(&frame)
		}
		delete(framed)
		delete(body)
	}
	frame_decoder_close(&decoder)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

@(private)
fmt_frame_header :: proc(storage: []u8, length: int) -> []u8 {
	text := "Content-Length: "
	copy(storage, transmute([]u8)text)
	offset := len(text)
	digits: [20]u8
	digit_count := 0
	remaining := length
	for remaining > 0 {
		digits[digit_count] = u8('0' + remaining % 10)
		digit_count += 1
		remaining /= 10
	}
	for index in 0 ..< digit_count do storage[offset + index] = digits[digit_count - index - 1]
	offset += digit_count
	copy(storage[offset:], transmute([]u8)(string("\r\n\r\n")))
	return storage[:offset + 4]
}

@(private)
Containment_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
containment_failing_allocator :: proc(data: ^Containment_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = containment_failing_allocator_proc, data = data}
}

@(private)
containment_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	allocator := cast(^Containment_Failing_Allocator)allocator_data
	if mode == .Alloc || mode == .Resize || mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after do return nil, runtime.Allocator_Error.Out_Of_Memory
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

/* Verifies every startup allocation fault releases all successfully owned state. */
@(test)
process_start_allocation_faults_clean_up_exactly :: proc(t: ^testing.T) {
	command := [?]string{"/bin/sh", "-c", "cat"}
	for fail_after in 0 ..< 16 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Containment_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		session, started, failure := process_session_start(
			test_process_request(command[:]),
			1,
			containment_failing_allocator(&failing),
		)
		if started {
			process_session_close(&session)
		} else {
			testing.expect_value(t, failure.code, Failure_Code.Allocation)
		}
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}
