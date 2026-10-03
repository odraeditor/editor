// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:testing"

/* Verifies every admitted action has a complete normalized physical shape. */
@(test)
pointer_events_admit_supported_actions :: proc(t: ^testing.T) {
	cases := [?]struct {
		name:   string,
		action: Pointer_Action,
		button: Pointer_Button,
	}{
		{name = "press", action = .Press, button = .Primary},
		{name = "release", action = .Release, button = .Secondary},
		{name = "motion", action = .Motion, button = .Middle},
		{name = "wheel-up", action = .Wheel, button = .Wheel_Up},
		{name = "wheel-down", action = .Wheel, button = .Wheel_Down},
		{name = "cancel", action = .Cancel, button = .None},
	}
	for fixture in cases {
		event := pointer_test_event(fixture.action, fixture.button)
		testing.expectf(t, pointer_event_is_valid(event), "%s event was rejected", fixture.name)
		testing.expectf(
			t,
			input_is_valid(Input{kind = .Pointer, pointer = event}),
			"%s input was rejected",
			fixture.name,
		)
	}
}

/* Verifies missing identity, capability, coordinates, and action shape reject. */
@(test)
pointer_events_reject_malformed_input :: proc(t: ^testing.T) {
	valid := pointer_test_event(.Press, .Primary)
	cases := [?]struct {
		name:  string,
		event: Pointer_Event,
	}{
		{name = "missing-frontend", event = valid},
		{name = "missing-source", event = valid},
		{name = "missing-root", event = valid},
		{name = "missing-geometry", event = valid},
		{name = "missing-sequence", event = valid},
		{name = "invalid-space", event = valid},
		{name = "row-limit", event = valid},
		{name = "column-limit", event = valid},
		{name = "missing-action-capability", event = valid},
		{name = "missing-modifier-capability", event = valid},
		{name = "wrong-wheel-button", event = valid},
		{name = "wrong-motion-button", event = valid},
		{name = "modified-cancel", event = valid},
	}
	cases[0].event.frontend = 0
	cases[1].event.source = 0
	cases[2].event.root_generation = 0
	cases[3].event.geometry_generation = 0
	cases[4].event.sequence = 0
	cases[5].event.coordinate_space = .Invalid
	cases[6].event.row = MAX_POINTER_COORDINATE + 1
	cases[7].event.column = MAX_POINTER_COORDINATE + 1
	cases[8].event.capabilities -= {.Press}
	cases[9].event.modifiers = {.Shift}
	cases[9].event.capabilities -= {.Modifiers}
	cases[10].event.action = .Wheel
	cases[11].event.action = .Motion
	cases[11].event.button = .None
	cases[12].event.action = .Cancel
	cases[12].event.button = .None
	cases[12].event.modifiers = {.Control}
	for fixture in cases {
		testing.expectf(
			t,
			!pointer_event_is_valid(fixture.event),
			"%s event was admitted",
			fixture.name,
		)
	}
}

/* Verifies sequence continuity is scoped to one source and observed geometry. */
@(test)
pointer_events_check_exact_source_order :: proc(t: ^testing.T) {
	previous := pointer_test_event(.Press, .Primary)
	current := pointer_test_event(.Motion, .Primary)
	current.sequence = 18
	testing.expect(t, pointer_event_follows(previous, current))

	cases := [?]struct {
		name:  string,
		event: Pointer_Event,
	}{
		{name = "gap", event = current},
		{name = "frontend-change", event = current},
		{name = "source-change", event = current},
		{name = "root-change", event = current},
		{name = "geometry-change", event = current},
	}
	cases[0].event.sequence = 19
	cases[1].event.frontend = 8
	cases[2].event.source = 9
	cases[3].event.root_generation = 12
	cases[4].event.geometry_generation = 13
	for fixture in cases {
		testing.expectf(
			t,
			!pointer_event_follows(previous, fixture.event),
			"%s event followed incompatible state",
			fixture.name,
		)
	}
	previous.sequence = Pointer_Sequence(max(u64))
	current.sequence = 1
	testing.expect(t, !pointer_event_follows(previous, current))
}

/* Verifies normalized input kinds cannot retain another kind's payload. */
@(test)
pointer_input_rejects_mixed_payloads :: proc(t: ^testing.T) {
	event := pointer_test_event(.Press, .Primary)
	key := Input{kind = .Key, stroke = {kind = .Enter}}
	text := Input{kind = .Text_Commit, text = "x"}
	pointer := Input{kind = .Pointer, pointer = event}
	testing.expect(t, input_is_valid(key) && input_is_valid(text) && input_is_valid(pointer))

	key.pointer = event
	text.pointer = event
	pointer.stroke = {kind = .Enter}
	testing.expect(t, !input_is_valid(key))
	testing.expect(t, !input_is_valid(text))
	testing.expect(t, !input_is_valid(pointer))
}

/* Verifies compatible motion keeps only the newest position and exact sequence gap. */
@(test)
pointer_queue_coalesces_only_compatible_motion :: proc(t: ^testing.T) {
	queue: Pointer_Event_Queue
	first := pointer_test_event(.Motion, .Primary)
	second := first
	second.column += 1
	second.sequence += 1
	third := second
	third.column += 1
	third.sequence += 1

	testing.expect_value(t, pointer_event_queue_push(&queue, first), Pointer_Queue_Result.Queued)
	testing.expect_value(t, pointer_event_queue_push(&queue, second), Pointer_Queue_Result.Coalesced)
	testing.expect_value(t, pointer_event_queue_push(&queue, third), Pointer_Queue_Result.Coalesced)
	testing.expect_value(t, queue.count, u8(1))
	queued, popped := pointer_event_queue_pop(&queue)
	testing.expect(t, popped)
	testing.expect_value(t, queued.event, third)
	testing.expect_value(t, queued.coalesced, u16(2))
	previous := first
	previous.sequence -= 1
	testing.expect(t, pointer_event_follows_after(previous, queued.event, queued.coalesced))
}

/* Verifies modifier, target, and control transitions remain distinct. */
@(test)
pointer_queue_preserves_incompatible_and_control_events :: proc(t: ^testing.T) {
	queue: Pointer_Event_Queue
	motion := pointer_test_event(.Motion, .Primary)
	modified := motion
	modified.modifiers = {.Shift}
	modified.sequence += 1
	retargeted := modified
	retargeted.root_generation += 1
	retargeted.sequence += 1
	release := retargeted
	release.action = .Release
	release.sequence += 1
	cancel := release
	cancel.action = .Cancel
	cancel.button = .None
	cancel.modifiers = {}
	cancel.sequence += 1

	testing.expect_value(t, pointer_event_queue_push(&queue, motion), Pointer_Queue_Result.Queued)
	testing.expect_value(t, pointer_event_queue_push(&queue, modified), Pointer_Queue_Result.Queued)
	testing.expect_value(t, pointer_event_queue_push(&queue, retargeted), Pointer_Queue_Result.Queued)
	testing.expect_value(t, pointer_event_queue_push(&queue, release), Pointer_Queue_Result.Queued)
	testing.expect_value(t, pointer_event_queue_push(&queue, cancel), Pointer_Queue_Result.Queued)
	testing.expect_value(t, queue.count, u8(5))
	expected_events := [?]Pointer_Event{motion, modified, retargeted, release, cancel}
	for expected in expected_events {
		queued, popped := pointer_event_queue_pop(&queue)
		testing.expect(t, popped)
		testing.expect_value(t, queued.event, expected)
		testing.expect_value(t, queued.coalesced, u16(0))
	}
}

/* Verifies queue and coalescing ceilings reject without mutating retained input. */
@(test)
pointer_queue_limits_are_atomic :: proc(t: ^testing.T) {
	queue: Pointer_Event_Queue
	for index in 0..<MAX_QUEUED_POINTER_EVENTS {
		event := pointer_test_event(.Press, .Primary)
		event.sequence = Pointer_Sequence(index + 1)
		testing.expect_value(t, pointer_event_queue_push(&queue, event), Pointer_Queue_Result.Queued)
	}
	retained := queue
	overflow := pointer_test_event(.Release, .Primary)
	overflow.sequence = Pointer_Sequence(MAX_QUEUED_POINTER_EVENTS + 1)
	testing.expect_value(t, pointer_event_queue_push(&queue, overflow), Pointer_Queue_Result.Limit)
	testing.expect_value(t, queue, retained)

	pointer_event_queue_clear(&queue)
	motion := pointer_test_event(.Motion, .Primary)
	testing.expect_value(t, pointer_event_queue_push(&queue, motion), Pointer_Queue_Result.Queued)
	for _ in 0..<MAX_COALESCED_POINTER_MOTION {
		motion.sequence += 1
		testing.expect_value(t, pointer_event_queue_push(&queue, motion), Pointer_Queue_Result.Coalesced)
	}
	retained = queue
	motion.sequence += 1
	testing.expect_value(t, pointer_event_queue_push(&queue, motion), Pointer_Queue_Result.Limit)
	testing.expect_value(t, queue, retained)
}

@(private)
pointer_test_event :: proc(action: Pointer_Action, button: Pointer_Button) -> Pointer_Event {
	return Pointer_Event {
		frontend = 7,
		source = 8,
		action = action,
		button = button,
		coordinate_space = .Cell,
		row = 22,
		column = 79,
		root_generation = 10,
		geometry_generation = 11,
		sequence = 17,
		capabilities = {
			.Press,
			.Release,
			.Motion,
			.Wheel,
			.Cancellation,
			.Modifiers,
			.Cell_Coordinates,
		},
	}
}
