// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor"
import "../history"
import "../interaction"
import "../kill_ring"
import editor_view "../view"
import "core:mem"
import "core:testing"

@(private = "file")
TRANSFER_RANDOM_SEED :: u64(0x6f6472617472616e)
@(private = "file")
TRANSFER_OPERATIONS :: 192
@(private = "file")
MODEL_TEXT_BYTES :: 512
@(private = "file")
MODEL_RING_ENTRIES :: int(kill_ring.DEFAULT_RETAINED_ENTRIES)
@(private = "file")
MODEL_ENTRY_BYTES :: 64

@(private = "file")
Transfer_Model_Buffer :: struct {
	bytes:  [MODEL_TEXT_BYTES]byte,
	length: int,
}

@(private = "file")
Transfer_Model_Entry :: struct {
	bytes:  [MODEL_ENTRY_BYTES]byte,
	length: int,
}

@(private = "file")
Transfer_Model_Ring :: struct {
	entries: [MODEL_RING_ENTRIES]Transfer_Model_Entry,
	count:   int,
}

/* Verifies generated two-buffer transfer sequences against contiguous text and ring models. */
@(test)
cross_buffer_transfer_matches_oracle :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	first: Native_Fixture
	if !native_fixture_init(t, &first, "alpha", allocator) {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	second: Native_Fixture
	if !native_fixture_init(t, &second, "beta", allocator) {
		native_fixture_close(t, &first)
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	first_model := transfer_model_buffer("alpha")
	second_model := transfer_model_buffer("beta")
	ring_model: Transfer_Model_Ring
	random := TRANSFER_RANDOM_SEED
	passed := true
	for operation in 0 ..< TRANSFER_OPERATIONS {
		value := transfer_next_random(&random)
		fixture := &first
		model := &first_model
		if value & 1 == 1 {
			fixture = &second
			model = &second_model
		}
		choice := (value >> 8) % 100
		if choice < 68 && model.length > 0 {
			start := int((value >> 16) % u64(model.length))
			length := 1 + int((value >> 32) % 3)
			end := min(model.length, start + length)
			if !transfer_set_region(t, fixture, start, end) {
				passed = false
				break
			}
			command_name := "copy-region"
			if choice >= 24 && choice < 48 {
				command_name = "kill-region"
			} else if choice >= 48 {
				command_name = "delete-region"
			}
			result, executed, failure := transfer_execute(
				fixture,
				command_name,
				&first.kill_ring,
				u64(operation + 1),
			)
			if !executed {
				testing.expectf(t, false, "operation %d %s failed with %v", operation, command_name, failure.code)
				passed = false
				break
			}
			native_result_close(&result)
			if command_name == "copy-region" || command_name == "kill-region" {
				transfer_model_ring_admit(&ring_model, model.bytes[start:end])
			}
			if command_name != "copy-region" {
				transfer_model_splice(model, start, end, nil)
			}
		} else if ring_model.count > 0 &&
			model.length + ring_model.entries[0].length <= MODEL_TEXT_BYTES {
			point := int((value >> 16) % u64(model.length + 1))
			if !transfer_set_point(t, fixture, point) {
				passed = false
				break
			}
			result, executed, failure := transfer_execute(
				fixture,
				"yank",
				&first.kill_ring,
				u64(operation + 1),
			)
			if !executed {
				testing.expectf(t, false, "operation %d yank failed with %v", operation, failure.code)
				passed = false
				break
			}
			native_result_close(&result)
			entry := &ring_model.entries[0]
			transfer_model_splice(model, point, point, entry.bytes[:entry.length])
		}
		if !transfer_expect_model(t, &first, &first_model) ||
			!transfer_expect_model(t, &second, &second_model) ||
			!transfer_expect_ring_model(t, &first.kill_ring, &ring_model) {
			passed = false
			break
		}
	}
	testing.expect(t, passed)
	native_fixture_close(t, &second)
	native_fixture_close(t, &first)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies cancellation rejects before a reserved transfer can alter any participant. */
@(test)
cancelled_transfer_preserves_state :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "cancel", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	transfer_set_region(t, &fixture, 0, 6)
	before_ring, _, _ := kill_ring.ring_stats(&fixture.kill_ring)
	handle, found, _ := interaction.command_lookup(&fixture.command_registry, "kill-region")
	testing.expect(t, found)
	request := native_request(&fixture, handle)
	request.history_store = &fixture.history
	request.kill_ring = &fixture.kill_ring
	request.kill_sequence_id = 1
	request.event_sequence = 1
	request.yank_context = &fixture.yank_context
	request.cancelled = true
	_, executed, failure := native_command_execute(request)
	testing.expect(t, !executed)
	testing.expect_value(t, failure.code, Failure_Code.Cancelled)
	after_ring, _, _ := kill_ring.ring_stats(&fixture.kill_ring)
	testing.expect_value(t, after_ring, before_ring)
	expect_native_state(t, &fixture, 6, 6, 0, "cancel")
	history_stats, _, _ := history.store_stats(&fixture.history)
	testing.expect_value(t, history_stats.usage.retained_nodes, u64(1))
}

@(private = "file")
transfer_execute :: proc(
	fixture: ^Native_Fixture,
	name: string,
	ring: ^kill_ring.Ring,
	event_sequence: u64,
) -> (Native_Result, bool, Failure_Context) {
	handle, found, lookup_failure := interaction.command_lookup(&fixture.command_registry, name)
	if !found {
		return {}, false, Failure_Context{code = .Invalid_Command, interaction_code = lookup_failure.code}
	}
	request := native_request(fixture, handle)
	request.history_store = &fixture.history
	request.history_grouping = history.Grouping_Context{kind = .Independent}
	request.kill_ring = ring
	request.kill_sequence_id = event_sequence
	request.event_sequence = event_sequence
	request.yank_context = &fixture.yank_context
	return native_command_execute(request)
}

@(private = "file")
transfer_set_region :: proc(t: ^testing.T, fixture: ^Native_Fixture, start, end: int) -> bool {
	start_position, start_ok, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(start))
	end_position, end_ok, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(end))
	marked, _ := editor_view.set_mark(&fixture.view_registry, fixture.view, start_position, true)
	moved, _ := editor_view.move_point(&fixture.view_registry, fixture.view, end_position, u32(end), .Preserve)
	testing.expect(t, start_ok && end_ok && marked && moved)
	return start_ok && end_ok && marked && moved
}

@(private = "file")
transfer_set_point :: proc(t: ^testing.T, fixture: ^Native_Fixture, offset: int) -> bool {
	position, position_ok, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(offset))
	moved, _ := editor_view.move_point(&fixture.view_registry, fixture.view, position, u32(offset), .Deactivate)
	testing.expect(t, position_ok && moved)
	return position_ok && moved
}

@(private = "file")
transfer_model_buffer :: proc(text: string) -> Transfer_Model_Buffer {
	model: Transfer_Model_Buffer
	copy(model.bytes[:], text)
	model.length = len(text)
	return model
}

@(private = "file")
transfer_model_splice :: proc(model: ^Transfer_Model_Buffer, start, end: int, replacement: []byte) {
	result: [MODEL_TEXT_BYTES]byte
	inserted_end := start + len(replacement)
	copy(result[:start], model.bytes[:start])
	copy(result[start:inserted_end], replacement)
	copy(result[inserted_end:], model.bytes[end:model.length])
	model.bytes = result
	model.length = model.length - (end - start) + len(replacement)
}

@(private = "file")
transfer_model_ring_admit :: proc(ring: ^Transfer_Model_Ring, text: []byte) {
	limit := min(ring.count, MODEL_RING_ENTRIES - 1)
	for index := limit; index > 0; index -= 1 {
		ring.entries[index] = ring.entries[index - 1]
	}
	ring.entries[0] = {}
	copy(ring.entries[0].bytes[:], text)
	ring.entries[0].length = len(text)
	ring.count = min(ring.count + 1, MODEL_RING_ENTRIES)
}

@(private = "file")
transfer_expect_model :: proc(t: ^testing.T, fixture: ^Native_Fixture, model: ^Transfer_Model_Buffer) -> bool {
	stats, stats_ok, _ := editor.buffer_stats(&fixture.buffer)
	if !stats_ok || stats.text_bytes != u64(model.length) {
		testing.expect(t, false)
		return false
	}
	observed := make([]byte, model.length, context.temp_allocator)
	defer delete(observed, context.temp_allocator)
	_, inspected, _ := editor.buffer_inspect(&fixture.buffer, 0, editor.Byte_Offset(model.length), observed)
	equal := inspected && string(observed) == string(model.bytes[:model.length])
	testing.expect(t, equal)
	return equal
}

@(private = "file")
transfer_expect_ring_model :: proc(t: ^testing.T, ring: ^kill_ring.Ring, model: ^Transfer_Model_Ring) -> bool {
	stats, stats_ok, _ := kill_ring.ring_stats(ring)
	if !stats_ok || stats.usage.retained_entries != u64(model.count) {
		testing.expect(t, false)
		return false
	}
	if model.count == 0 {
		return true
	}
	inspection, inspected, _ := kill_ring.ring_inspect(
		ring,
		kill_ring.Inspection_Request {
			expected_generation = stats.generation,
			entry_limit = u64(model.count),
		},
		context.temp_allocator,
	)
	if !inspected {
		testing.expect(t, false)
		return false
	}
	defer kill_ring.inspection_release(&inspection, context.temp_allocator)
	for entry, index in inspection.entries {
		copied, copied_ok, _ := kill_ring.entry_copy(
			ring,
			kill_ring.Entry_Copy_Request {
				expected_generation = stats.generation,
				entry_id = entry.id,
				byte_limit = stats.policy.entry_bytes,
			},
			context.temp_allocator,
		)
		if !copied_ok {
			return false
		}
		expected := &model.entries[index]
		equal := copied.text == string(expected.bytes[:expected.length])
		kill_ring.entry_copy_release(&copied, context.temp_allocator)
		if !equal {
			testing.expect(t, false)
			return false
		}
	}
	return true
}

@(private = "file")
transfer_next_random :: proc(state: ^u64) -> u64 {
	state^ = state^ * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407
	return state^
}
