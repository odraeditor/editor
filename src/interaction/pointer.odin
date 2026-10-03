// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

/* MAX_POINTER_COORDINATE bounds one normalized frontend cell coordinate. */
MAX_POINTER_COORDINATE :: u32(1_048_575)
/* MAX_QUEUED_POINTER_EVENTS bounds copied native pointer input awaiting dispatch. */
MAX_QUEUED_POINTER_EVENTS :: 32
/* MAX_POINTER_QUEUE_BYTES bounds the complete fixed native queue representation. */
MAX_POINTER_QUEUE_BYTES :: 4 * 1_024
/* MAX_COALESCED_POINTER_MOTION bounds skipped motion represented by one queue entry. */
MAX_COALESCED_POINTER_MOTION :: u16(64)
/* MAX_POINTER_MOTION_PER_TURN bounds semantic motion work before presentation. */
MAX_POINTER_MOTION_PER_TURN :: u8(1)

/* Pointer_Frontend_ID identifies one physical presentation backend. */
Pointer_Frontend_ID :: distinct u32

/* Pointer_Source_ID identifies one input source within a frontend. */
Pointer_Source_ID :: distinct u32

/* Pointer_Root_Generation identifies the UI root observed by one event. */
Pointer_Root_Generation :: distinct u64

/* Pointer_Geometry_Generation identifies the frontend geometry observed by one event. */
Pointer_Geometry_Generation :: distinct u64

/* Pointer_Sequence identifies one ordered event from a pointer source. */
Pointer_Sequence :: distinct u64

/* Pointer_Action classifies one normalized physical transition. */
Pointer_Action :: enum u8 {
	Invalid,
	Press,
	Release,
	Motion,
	Wheel,
	Cancel,
}

/* Pointer_Button identifies one normalized physical button or wheel direction. */
Pointer_Button :: enum u8 {
	None,
	Primary,
	Middle,
	Secondary,
	Wheel_Up,
	Wheel_Down,
}

/* Pointer_Modifier identifies one modifier independently of keymap encoding. */
Pointer_Modifier :: enum u8 {
	Shift,
	Control,
	Alt,
	Super,
}

/* Pointer_Modifiers is the normalized modifier set for one pointer event. */
Pointer_Modifiers :: bit_set[Pointer_Modifier; u8]

/* Pointer_Coordinate_Space declares the meaning of normalized coordinates. */
Pointer_Coordinate_Space :: enum u8 {
	Invalid,
	Cell,
}

/* Pointer_Capability describes one transition a frontend can report safely. */
Pointer_Capability :: enum u8 {
	Press,
	Release,
	Motion,
	Wheel,
	Cancellation,
	Modifiers,
	Cell_Coordinates,
}

/* Pointer_Capabilities is one frontend's admitted pointer feature set. */
Pointer_Capabilities :: bit_set[Pointer_Capability; u8]

/* Pointer_Event is one copied frontend-independent physical transition. */
Pointer_Event :: struct {
	frontend:            Pointer_Frontend_ID,
	source:              Pointer_Source_ID,
	action:              Pointer_Action,
	button:              Pointer_Button,
	modifiers:           Pointer_Modifiers,
	coordinate_space:    Pointer_Coordinate_Space,
	row:                 u32,
	column:              u32,
	root_generation:     Pointer_Root_Generation,
	geometry_generation: Pointer_Geometry_Generation,
	sequence:            Pointer_Sequence,
	capabilities:        Pointer_Capabilities,
}

/* Pointer_Queued_Event retains one event and exact compatible motion skipped before it. */
Pointer_Queued_Event :: struct {
	event:     Pointer_Event,
	coalesced: u16,
}

/* Pointer_Event_Queue is a fixed-capacity native queue with no allocator ownership. */
Pointer_Event_Queue :: struct {
	events: [MAX_QUEUED_POINTER_EVENTS]Pointer_Queued_Event,
	head:   u8,
	count:  u8,
}

#assert(size_of(Pointer_Event_Queue) <= MAX_POINTER_QUEUE_BYTES)

/* Pointer_Queue_Result reports whether an event was retained, coalesced, or rejected. */
Pointer_Queue_Result :: enum u8 {
	Invalid,
	Queued,
	Coalesced,
	Limit,
}

/* pointer_event_is_valid checks identity, capability, geometry, and action shape. */
pointer_event_is_valid :: proc(event: Pointer_Event) -> bool {
	if event.frontend == Pointer_Frontend_ID(0) || event.source == Pointer_Source_ID(0) ||
	   event.root_generation == Pointer_Root_Generation(0) ||
	   event.geometry_generation == Pointer_Geometry_Generation(0) ||
	   event.sequence == Pointer_Sequence(0) || event.coordinate_space != .Cell ||
	   .Cell_Coordinates not_in event.capabilities ||
	   event.row > MAX_POINTER_COORDINATE || event.column > MAX_POINTER_COORDINATE {
		return false
	}
	if event.modifiers != {} && .Modifiers not_in event.capabilities {
		return false
	}
	switch event.action {
	case .Press:
		return .Press in event.capabilities && pointer_button_is_physical(event.button)
	case .Release:
		return .Release in event.capabilities && pointer_button_is_physical(event.button)
	case .Motion:
		return .Motion in event.capabilities && pointer_button_is_physical(event.button)
	case .Wheel:
		return .Wheel in event.capabilities && pointer_button_is_wheel(event.button)
	case .Cancel:
		return .Cancellation in event.capabilities && event.button == .None && event.modifiers == {}
	case .Invalid:
		return false
	}
	return false
}

/* pointer_event_follows checks exact same-source ordering within one observed geometry. */
pointer_event_follows :: proc(previous, current: Pointer_Event) -> bool {
	return pointer_event_follows_after(previous, current, 0)
}

/* pointer_event_follows_after admits an exact gap accounted for by native coalescing. */
pointer_event_follows_after :: proc(
	previous, current: Pointer_Event,
	coalesced: u16,
) -> bool {
	if !pointer_event_is_valid(previous) || !pointer_event_is_valid(current) ||
	   (coalesced > 0 && current.action != .Motion) ||
	   previous.frontend != current.frontend || previous.source != current.source ||
	   previous.root_generation != current.root_generation ||
	   previous.geometry_generation != current.geometry_generation ||
	   previous.sequence == Pointer_Sequence(max(u64)) ||
	   u64(previous.sequence) > max(u64) - 1 - u64(coalesced) {
		return false
	}
	return u64(current.sequence) == u64(previous.sequence) + 1 + u64(coalesced)
}

/* pointer_event_queue_push retains control transitions and coalesces compatible motion. */
pointer_event_queue_push :: proc(
	queue: ^Pointer_Event_Queue,
	event: Pointer_Event,
) -> Pointer_Queue_Result {
	if queue == nil || !pointer_event_is_valid(event) do return .Invalid
	if queue.count > 0 {
		tail_index := (int(queue.head) + int(queue.count) - 1) % MAX_QUEUED_POINTER_EVENTS
		tail := &queue.events[tail_index]
		if pointer_motion_is_compatible(tail.event, event) {
			if tail.coalesced >= MAX_COALESCED_POINTER_MOTION do return .Limit
			tail.event = event
			tail.coalesced += 1
			return .Coalesced
		}
	}
	if int(queue.count) >= MAX_QUEUED_POINTER_EVENTS do return .Limit
	index := (int(queue.head) + int(queue.count)) % MAX_QUEUED_POINTER_EVENTS
	queue.events[index] = Pointer_Queued_Event{event = event}
	queue.count += 1
	return .Queued
}

/* pointer_event_queue_pop removes the oldest retained event without allocation. */
pointer_event_queue_pop :: proc(
	queue: ^Pointer_Event_Queue,
) -> (queued: Pointer_Queued_Event, ok: bool) {
	if queue == nil || queue.count == 0 do return {}, false
	queued = queue.events[queue.head]
	queue.events[queue.head] = {}
	queue.head = u8((int(queue.head) + 1) % MAX_QUEUED_POINTER_EVENTS)
	queue.count -= 1
	if queue.count == 0 do queue.head = 0
	return queued, true
}

/* pointer_event_queue_peek copies the oldest retained event without mutation. */
pointer_event_queue_peek :: proc(
	queue: ^Pointer_Event_Queue,
) -> (queued: Pointer_Queued_Event, ok: bool) {
	if queue == nil || queue.count == 0 do return {}, false
	return queue.events[queue.head], true
}

/* pointer_event_queue_clear releases every copied event idempotently. */
pointer_event_queue_clear :: proc(queue: ^Pointer_Event_Queue) {
	if queue != nil do queue^ = {}
}

@(private)
pointer_motion_is_compatible :: proc(previous, current: Pointer_Event) -> bool {
	return previous.action == .Motion && current.action == .Motion &&
	       previous.button == current.button && previous.modifiers == current.modifiers &&
	       previous.capabilities == current.capabilities &&
	       previous.coordinate_space == current.coordinate_space &&
	       pointer_event_follows(previous, current)
}

@(private)
pointer_button_is_physical :: proc(button: Pointer_Button) -> bool {
	return button == .Primary || button == .Middle || button == .Secondary
}

@(private)
pointer_button_is_wheel :: proc(button: Pointer_Button) -> bool {
	return button == .Wheel_Up || button == .Wheel_Down
}
