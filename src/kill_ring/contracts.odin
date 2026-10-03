// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package kill_ring owns bounded session text retention and transfer ordering.
package kill_ring

import "base:runtime"

/* KIBIBYTE is the binary byte unit used by kill-ring policy. */
KIBIBYTE :: u64(1024)
/* MEBIBYTE is 1,024 kibibytes. */
MEBIBYTE :: u64(1024) * KIBIBYTE

/* MIN_RETAINED_ENTRIES is the smallest admitted ring capacity. */
MIN_RETAINED_ENTRIES :: u64(16)
/* MAX_RETAINED_ENTRIES is the measured largest admitted ring capacity. */
MAX_RETAINED_ENTRIES :: u64(4_096)
/* DEFAULT_RETAINED_ENTRIES is the measured initial ring capacity. */
DEFAULT_RETAINED_ENTRIES :: u64(60)
/* MIN_ENTRY_BYTES is the smallest configurable per-entry byte ceiling. */
MIN_ENTRY_BYTES :: 4 * KIBIBYTE
/* MAX_ENTRY_BYTES is the measured largest per-entry byte ceiling. */
MAX_ENTRY_BYTES :: 12 * MEBIBYTE
/* DEFAULT_ENTRY_BYTES is the initial per-entry byte ceiling. */
DEFAULT_ENTRY_BYTES :: MAX_ENTRY_BYTES
/* MIN_TOTAL_BYTES is the smallest configurable retained-text ceiling. */
MIN_TOTAL_BYTES :: 1 * MEBIBYTE
/* MAX_TOTAL_BYTES is the measured largest retained-text ceiling. */
MAX_TOTAL_BYTES :: 256 * MEBIBYTE
/* DEFAULT_TOTAL_BYTES is the initial retained-text ceiling. */
DEFAULT_TOTAL_BYTES :: MAX_TOTAL_BYTES
/* MIN_COALESCED_OPERATIONS is the smallest consecutive-kill ceiling. */
MIN_COALESCED_OPERATIONS :: u64(16)
/* MAX_COALESCED_OPERATIONS is the measured largest consecutive-kill ceiling. */
MAX_COALESCED_OPERATIONS :: u64(10_000)
/* DEFAULT_COALESCED_OPERATIONS is the initial consecutive-kill ceiling. */
DEFAULT_COALESCED_OPERATIONS :: MAX_COALESCED_OPERATIONS
/* MIN_INSPECTION_ENTRIES is the smallest copied inspection bound. */
MIN_INSPECTION_ENTRIES :: u64(1)
/* MAX_INSPECTION_ENTRIES is the measured largest copied inspection bound. */
MAX_INSPECTION_ENTRIES :: u64(256)
/* DEFAULT_INSPECTION_ENTRIES is the initial copied inspection bound. */
DEFAULT_INSPECTION_ENTRIES :: MAX_INSPECTION_ENTRIES
/* MIN_ROTATION_WORK is the smallest allowed rotation search bound. */
MIN_ROTATION_WORK :: u64(16)
/* MAX_ROTATION_WORK is the measured largest rotation search bound. */
MAX_ROTATION_WORK :: u64(4_096)
/* DEFAULT_ROTATION_WORK is the initial rotation search bound. */
DEFAULT_ROTATION_WORK :: MAX_ROTATION_WORK
/* MIN_TEMPORARY_BYTES is the smallest transfer preparation budget. */
MIN_TEMPORARY_BYTES :: 1 * MEBIBYTE
/* MAX_TEMPORARY_BYTES is the largest transfer preparation budget. */
MAX_TEMPORARY_BYTES :: 256 * MEBIBYTE
/* DEFAULT_TEMPORARY_BYTES admits three complete default-size preparation copies. */
DEFAULT_TEMPORARY_BYTES :: 64 * MEBIBYTE
/* MIN_CANCELLATION_BYTES is the smallest copied-byte cancellation interval. */
MIN_CANCELLATION_BYTES :: 64 * KIBIBYTE
/* MAX_CANCELLATION_BYTES is the largest copied-byte cancellation interval. */
MAX_CANCELLATION_BYTES :: 4 * MEBIBYTE
/* DEFAULT_CANCELLATION_BYTES is the initial copied-byte cancellation interval. */
DEFAULT_CANCELLATION_BYTES :: 256 * KIBIBYTE

/* Ring_ID identifies one live session ring; zero is invalid. */
Ring_ID :: distinct u64
/* Entry_ID identifies one immutable admitted entry; zero is invalid. */
Entry_ID :: distinct u64
/* Generation identifies one complete canonical ring ordering. */
Generation :: distinct u64

/* Admission_Kind identifies why text enters the ring. */
Admission_Kind :: enum u8 {
	Invalid,
	Copy,
	Kill,
	External,
}

/* Kill_Direction determines directional coalescence order. */
Kill_Direction :: enum u8 {
	Invalid,
	Forward,
	Backward,
}

/* Policy_Field identifies one rejected policy dimension. */
Policy_Field :: enum u8 {
	Invalid,
	Retained_Entries,
	Entry_Bytes,
	Total_Bytes,
	Coalesced_Operations,
	Inspection_Entries,
	Rotation_Work,
	Temporary_Bytes,
	Cancellation_Bytes,
}

/* Policy contains every retained-storage and bounded-work limit. */
Policy :: struct {
	retained_entries:     u64,
	entry_bytes:          u64,
	total_bytes:          u64,
	coalesced_operations: u64,
	inspection_entries:   u64,
	rotation_work:        u64,
	temporary_bytes:      u64,
	cancellation_bytes:   u64,
}

/* DEFAULT_POLICY is the measured initial kill-ring policy. */
DEFAULT_POLICY :: Policy {
	retained_entries = DEFAULT_RETAINED_ENTRIES,
	entry_bytes = DEFAULT_ENTRY_BYTES,
	total_bytes = DEFAULT_TOTAL_BYTES,
	coalesced_operations = DEFAULT_COALESCED_OPERATIONS,
	inspection_entries = DEFAULT_INSPECTION_ENTRIES,
	rotation_work = DEFAULT_ROTATION_WORK,
	temporary_bytes = DEFAULT_TEMPORARY_BYTES,
	cancellation_bytes = DEFAULT_CANCELLATION_BYTES,
}

/* Allocator_Set supplies retained ring storage and per-operation reservation storage. */
Allocator_Set :: struct {
	// The caller keeps this allocator alive until ring_close returns.
	persistent: runtime.Allocator,
	// The caller keeps this allocator alive for every ring operation.
	temporary:  runtime.Allocator,
}

/* Kill_Context carries semantic continuity without depending on time or command names. */
Kill_Context :: struct {
	sequence_id:     u64,
	event_sequence:  u64,
	source_buffer_id: u64,
	start:           u64,
	end:             u64,
	direction:       Kill_Direction,
}

/* Admission_Request proposes one complete copied UTF-8 value against an exact generation. */
Admission_Request :: struct {
	expected_generation: Generation,
	kind:                Admission_Kind,
	text:                string,
	kill:                Kill_Context,
	cancelled:           bool,
}

/* Entry_Metadata is a copied pointer-free description of one retained entry. */
Entry_Metadata :: struct {
	id:                   Entry_ID,
	byte_count:           u64,
	admission_kind:       Admission_Kind,
	coalesced_operations: u64,
	generation:           Generation,
}

/* Resource_Usage reports canonical and provisionally reserved ring storage. */
Resource_Usage :: struct {
	retained_entries:   u64,
	retained_text_bytes: u64,
	retained_bytes:     u64,
	reserved_bytes:     u64,
	evicted_entries:    u64,
}

/* Ring_Stats reports exact identity, ordering generation, policy, and accounting. */
Ring_Stats :: struct {
	ring_id:    Ring_ID,
	generation: Generation,
	newest:     Entry_ID,
	policy:     Policy,
	usage:      Resource_Usage,
}

/* Reservation_Result describes a complete admission without publishing it. */
Reservation_Result :: struct {
	entry:             Entry_Metadata,
	result_generation: Generation,
	evicted_entries:   u64,
	coalesced:         bool,
}

/* Inspection_Request asks for bounded newest-to-oldest copied metadata. */
Inspection_Request :: struct {
	expected_generation: Generation,
	entry_limit:         u64,
}

/* Inspection owns copied entry metadata and exposes no internal storage. */
Inspection :: struct {
	ring_id:    Ring_ID,
	generation: Generation,
	entries:    []Entry_Metadata,
}

/* Entry_Copy_Request asks for one bounded copied immutable entry. */
Entry_Copy_Request :: struct {
	expected_generation: Generation,
	entry_id:            Entry_ID,
	byte_limit:          u64,
}

/* Entry_Copy owns one caller-allocated UTF-8 entry copy. */
Entry_Copy :: struct {
	metadata: Entry_Metadata,
	text:     string,
}

/* Rotation_Request selects the entry following one exact retained entry without reordering. */
Rotation_Request :: struct {
	expected_generation: Generation,
	current_entry:      Entry_ID,
	work_limit:         u64,
	byte_limit:         u64,
}

/* Failure_Code classifies expected ring rejection without changing canonical state. */
Failure_Code :: enum u16 {
	None,
	Invalid_Identity,
	Invalid_State,
	Invalid_Policy,
	Policy_Range,
	Policy_Relationship,
	Stale_Generation,
	Invalid_UTF8,
	Empty_Text,
	Empty_Ring,
	Entry_Not_Found,
	Entry_Bytes_Limit,
	Total_Bytes_Limit,
	Coalescence_Limit,
	Inspection_Limit,
	Rotation_Limit,
	Persistent_Memory_Limit,
	Temporary_Memory_Limit,
	Pending_Reservation,
	Cancelled,
}

/* Failure_Context identifies the rejected ring state and violated bound. */
Failure_Context :: struct {
	code:       Failure_Code,
	field:      Policy_Field,
	ring_id:    Ring_ID,
	generation: Generation,
	entry_id:   Entry_ID,
	minimum:    u64,
	maximum:    u64,
	actual:     u64,
}

/* Ring is an opaque owner of one session kill ring. */
Ring :: struct {
	state: rawptr,
}

/* Reservation owns one complete unpublished ring admission. */
Reservation :: struct {
	state: rawptr,
}

/* ring_is_valid reports whether a handle owns live ring state. */
ring_is_valid :: proc(ring: ^Ring) -> bool {
	return ring != nil && ring.state != nil
}

/* reservation_is_valid reports whether a handle owns an unpublished admission. */
reservation_is_valid :: proc(reservation: ^Reservation) -> bool {
	return reservation != nil && reservation.state != nil
}

/* policy_validate checks every field and cross-field relationship without mutation. */
policy_validate :: proc(policy: Policy) -> (ok: bool, failure: Failure_Context) {
	checks := [8]struct {value, minimum, maximum: u64, field: Policy_Field} {
		{policy.retained_entries, MIN_RETAINED_ENTRIES, MAX_RETAINED_ENTRIES, .Retained_Entries},
		{policy.entry_bytes, MIN_ENTRY_BYTES, MAX_ENTRY_BYTES, .Entry_Bytes},
		{policy.total_bytes, MIN_TOTAL_BYTES, MAX_TOTAL_BYTES, .Total_Bytes},
		{policy.coalesced_operations, MIN_COALESCED_OPERATIONS, MAX_COALESCED_OPERATIONS, .Coalesced_Operations},
		{policy.inspection_entries, MIN_INSPECTION_ENTRIES, MAX_INSPECTION_ENTRIES, .Inspection_Entries},
		{policy.rotation_work, MIN_ROTATION_WORK, MAX_ROTATION_WORK, .Rotation_Work},
		{policy.temporary_bytes, MIN_TEMPORARY_BYTES, MAX_TEMPORARY_BYTES, .Temporary_Bytes},
		{policy.cancellation_bytes, MIN_CANCELLATION_BYTES, MAX_CANCELLATION_BYTES, .Cancellation_Bytes},
	}
	for check in checks {
		if check.value < check.minimum || check.value > check.maximum {
			return false, Failure_Context {
				code = .Policy_Range,
				field = check.field,
				minimum = check.minimum,
				maximum = check.maximum,
				actual = check.value,
			}
		}
	}
	if policy.entry_bytes > policy.total_bytes {
		return false, Failure_Context {
			code = .Policy_Relationship,
			field = .Entry_Bytes,
			maximum = policy.total_bytes,
			actual = policy.entry_bytes,
		}
	}
	if policy.entry_bytes > policy.temporary_bytes / 3 {
		return false, Failure_Context {
			code = .Policy_Relationship,
			field = .Temporary_Bytes,
			minimum = policy.entry_bytes * 3,
			actual = policy.temporary_bytes,
		}
	}
	return true, {}
}
