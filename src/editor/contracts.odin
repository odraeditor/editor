// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package editor owns canonical buffer state and atomic splice publication.
package editor

import "base:runtime"

/* KIBIBYTE is the binary byte unit used by editor limits. */
KIBIBYTE :: u64(1024)
/* MEBIBYTE is 1,024 kibibytes. */
MEBIBYTE :: u64(1024) * KIBIBYTE
/* GIBIBYTE is 1,024 mebibytes. */
GIBIBYTE :: u64(1024) * MEBIBYTE

/* MAX_BUFFER_BYTES is the default maximum canonical buffer size. */
MAX_BUFFER_BYTES :: 1 * GIBIBYTE
/* MAX_REPLACEMENT_BYTES is the default maximum replacement size per splice. */
MAX_REPLACEMENT_BYTES :: 256 * MEBIBYTE
/* MAX_PERSISTENT_BYTES is the default persistent-allocation budget per buffer. */
MAX_PERSISTENT_BYTES :: 2 * GIBIBYTE
/* MAX_UNDO_BYTES is the default budget for one committed undo record. */
MAX_UNDO_BYTES :: 1 * GIBIBYTE
/* MAX_TEMPORARY_BYTES is the default scratch-allocation budget per operation. */
MAX_TEMPORARY_BYTES :: 512 * MEBIBYTE
/* MAX_INSPECTION_BYTES is the default maximum range copied by one inspection. */
MAX_INSPECTION_BYTES :: 16 * MEBIBYTE
/* MAX_SPLICE_NODES is the default bound on node work for one splice. */
MAX_SPLICE_NODES :: u64(262_144)
/* MAX_RECLAIM_STEP_NODES bounds deferred reclamation work per maintenance step. */
MAX_RECLAIM_STEP_NODES :: u64(4_096)
/* MAX_RECLAIM_QUEUE_NODES bounds nodes awaiting deferred reclamation. */
MAX_RECLAIM_QUEUE_NODES :: u64(262_144)
/* MAX_ANCHORS is the default maximum number of persistent locations per buffer. */
MAX_ANCHORS :: u32(1_000_000)

/* Buffer_ID identifies one live buffer; zero is invalid. */
Buffer_ID :: distinct u64
/* Revision identifies a committed version of a buffer. */
Revision :: distinct u64
/* Byte_Offset addresses a UTF-8 boundary in canonical buffer text. */
Byte_Offset :: distinct u64

/* Buffer_Kind distinguishes editable canonical text from read-only projections. */
Buffer_Kind :: enum u8 {
	Invalid,
	Text,
	Terminal_Projection,
}

/* Position binds a byte offset to the buffer identity and revision it came from. */
Position :: struct {
	buffer_id:   Buffer_ID,
	revision:    Revision,
	byte_offset: Byte_Offset,
}

/* Limits collects hard memory, size, and work bounds for one buffer. */
Limits :: struct {
	buffer_bytes:             u64,
	replacement_bytes:        u64,
	persistent_bytes:         u64,
	undo_bytes:               u64,
	temporary_bytes:          u64,
	inspection_bytes:         u64,
	splice_nodes:             u64,
	reclaim_step_nodes:       u64,
	reclaim_queue_nodes:      u64,
	anchors:                  u32,
}

/* DEFAULT_LIMITS is the production default bound set for a buffer. */
DEFAULT_LIMITS :: Limits {
	buffer_bytes = MAX_BUFFER_BYTES,
	replacement_bytes = MAX_REPLACEMENT_BYTES,
	persistent_bytes = MAX_PERSISTENT_BYTES,
	undo_bytes = MAX_UNDO_BYTES,
	temporary_bytes = MAX_TEMPORARY_BYTES,
	inspection_bytes = MAX_INSPECTION_BYTES,
	splice_nodes = MAX_SPLICE_NODES,
	reclaim_step_nodes = MAX_RECLAIM_STEP_NODES,
	reclaim_queue_nodes = MAX_RECLAIM_QUEUE_NODES,
	anchors = MAX_ANCHORS,
}

/*
Allocator_Set supplies persistent and per-operation allocation domains.
The caller must keep both allocators live for the lifetimes stated on the fields.
*/
Allocator_Set :: struct {
	// The caller keeps this allocator alive until buffer_close returns.
	persistent: runtime.Allocator,
	// The caller keeps this allocator alive for the duration of one operation.
	temporary:  runtime.Allocator,
}

/* Buffer is an opaque handle to canonical editor state. Initialize it once and close it once. */
Buffer :: struct {
	state: rawptr,
}

/*
Buffer_Snapshot is one retained immutable buffer revision.
Initialize it with buffer_snapshot_open and release it exactly once with
buffer_snapshot_close. Its text remains readable after later edits or buffer closure.
*/
Buffer_Snapshot :: distinct [5]uintptr

/* Buffer_Snapshot_Stats identifies the exact retained revision and its shared rope storage. */
Buffer_Snapshot_Stats :: struct {
	buffer_id:              Buffer_ID,
	revision:               Revision,
	text_bytes:             u64,
	shared_persistent_bytes: u64,
	pending_reclamation:    u64,
}

/* Anchor_Affinity selects which side of text inserted at the anchor retains it. */
Anchor_Affinity :: enum u8 {
	Invalid,
	Left,
	Right,
}

/* Anchor_Deletion_Policy selects the outcome when deletion consumes an anchor. */
Anchor_Deletion_Policy :: enum u8 {
	Invalid,
	Collapse,
	Invalidate,
}

/* Anchor is a checked persistent location owned by one live buffer. */
Anchor :: struct {
	buffer_id:  Buffer_ID,
	slot:       u32,
	generation: u32,
}

/* Anchor_Stats reports bounded persistent-anchor occupancy and owned storage. */
Anchor_Stats :: struct {
	live_count:    u32,
	slot_count:    u32,
	capacity:      u32,
	storage_bytes: u64,
	slot_bytes:    u64,
}

/* Selection_Mark_Snapshot describes one optional buffer-owned mark. */
Selection_Mark_Snapshot :: struct {
	present:  bool,
	position: Position,
}

/* Selection_Shape identifies how canonical point and mark derive selected text ranges. */
Selection_Shape :: enum u8 {
	Linear,
	Rectangle,
}

/* Rectangle_Column_Policy identifies the logical text column model for a rectangle. */
Rectangle_Column_Policy :: enum u8 {
	Grapheme,
}

/* Selection_Snapshot is one immutable buffer-owned point, mark, activation, and shape value. */
Selection_Snapshot :: struct {
	buffer_id:            Buffer_ID,
	revision:             Revision,
	generation:           u64,
	point_position:       Position,
	mark:                 Selection_Mark_Snapshot,
	region_active:        bool,
	shape:                Selection_Shape,
	rectangle_column_policy: Rectangle_Column_Policy,
}

/* Selection_Region_Action declares how a point publication affects region activation. */
Selection_Region_Action :: enum u8 {
	Invalid,
	Preserve,
	Deactivate,
	Activate,
}

/* Selection_Mark_Result declares how a reserved logical edit resolves buffer mark. */
Selection_Mark_Result :: enum u8 {
	Invalid,
	Preserve,
	Absent,
	Position,
}

/* Buffer_Stats reports the current revision, rope shape, and accounted storage. */
Buffer_Stats :: struct {
	buffer_id:           Buffer_ID,
	kind:                Buffer_Kind,
	read_only:           bool,
	revision:            Revision,
	text_bytes:          u64,
	line_feed_count:     u64,
	tree_height:         u32,
	node_count:          u64,
	chunk_count:         u64,
	persistent_bytes:    u64,
	pending_reclamation: u64,
}

/* Buffer_Line binds one logical line range to a current buffer revision. */
Buffer_Line :: struct {
	buffer_id:    Buffer_ID,
	revision:     Revision,
	line_index:   u64,
	start:        Byte_Offset,
	content_end:  Byte_Offset,
	next_start:   Byte_Offset,
}

/* Splice replaces the half-open range [start, end) with replacement UTF-8 text. */
Splice :: struct {
	start:       Position,
	end:         Position,
	replacement: string,
}

/* Splice_Reservation records the validated size, memory, and work budget for a splice. */
Splice_Reservation :: struct {
	result_bytes:       u64,
	removed_bytes:      u64,
	undo_bytes:         u64,
	persistent_bytes:   u64,
	temporary_bytes:    u64,
	node_work:          u64,
}

/*
Validated_Splice is a checked splice tied to one buffer revision.
Its replacement view is borrowed from the original Splice and must outlive preparation.
*/
Validated_Splice :: struct {
	buffer_id:    Buffer_ID,
	base_revision: Revision,
	start:        Byte_Offset,
	end:          Byte_Offset,
	replacement:  string,
	reservation:  Splice_Reservation,
}

@(private)
/*
Prepared_Splice is an opaque, buffer-owned publication candidate.
The caller must release it with prepared_splice_abort unless an internal publication consumes it.
*/
Prepared_Splice :: struct {
	state: rawptr,
}

/* Working_Revision_ID identifies one private revision lifetime; zero is invalid. */
Working_Revision_ID :: distinct u64

/*
Working_Position addresses one UTF-8 boundary in a specific private revision generation.
It cannot be used as a confirmed Position or after another private edit advances the generation.
*/
Working_Position :: struct {
	buffer_id:           Buffer_ID,
	base_revision:       Revision,
	working_revision_id: Working_Revision_ID,
	generation:          u64,
	byte_offset:         Byte_Offset,
}

/* Working_Splice replaces a range in the current private working revision. */
Working_Splice :: struct {
	start:       Working_Position,
	end:         Working_Position,
	replacement: string,
}

/*
Working_Revision is an opaque private buffer revision.
The owner must abort it unless a reserved publication operation consumes it.
*/
Working_Revision :: struct {
	state: rawptr,
}

/*
Working_Revision_Savepoint retains one immutable private root for later rollback.
It is tied to one working-revision identity and must be restored or discarded exactly once.
*/
Working_Revision_Savepoint :: distinct [6]uintptr

/* Working_Revision_Stats reports private identity, generation, and text size. */
Working_Revision_Stats :: struct {
	buffer_id:           Buffer_ID,
	base_revision:       Revision,
	working_revision_id: Working_Revision_ID,
	generation:          u64,
	text_bytes:          u64,
}

/*
Working_Publication_Splice describes one normalized base-relative anchor transform.
The transaction coordinator validates ordering and reconstruction before reserved publication.
*/
Working_Publication_Splice :: struct {
	start:          Byte_Offset,
	end:            Byte_Offset,
	inserted_bytes: u64,
}

/*
Change_Set describes one committed replacement.
Its text view is owned by the buffer and expires at the next successful splice or close.
*/
Change_Set :: struct {
	// Text views are owned by the buffer and remain valid until its next
	// successful splice or close.
	buffer_id:        Buffer_ID,
	base_revision:    Revision,
	result_revision:  Revision,
	start:            Byte_Offset,
	removed_bytes:    u64,
	replacement_text: string,
}

/*
Undo_Record contains the text needed to reverse one committed replacement.
Its text views are owned by the buffer and expire at the next successful splice or close.
*/
Undo_Record :: struct {
	// Text views are owned by the buffer and remain valid until its next
	// successful splice or close.
	buffer_id:       Buffer_ID,
	base_revision:   Revision,
	result_revision: Revision,
	start:           Byte_Offset,
	removed_text:    string,
	inserted_text:   string,
}

/* Failure_Code classifies expected editor failures without changing canonical state. */
Failure_Code :: enum u16 {
	None,
	Closed_Buffer,
	Wrong_Buffer_Kind,
	Read_Only_Buffer,
	Wrong_Buffer,
	Stale_Revision,
	Mismatched_Revision,
	Reversed_Range,
	Out_Of_Range,
	Mid_Encoding_Offset,
	Malformed_UTF8,
	Buffer_Limit,
	Replacement_Limit,
	Persistent_Memory_Limit,
	Undo_Memory_Limit,
	Temporary_Memory_Limit,
	Inspection_Limit,
	Anchor_Limit,
	Invalid_Anchor,
	Missing_Mark,
	Selection_Generation_Limit,
	Work_Limit,
	Cancelled,
}

/* Failure_Context locates an expected failure and reports the violated bound when relevant. */
Failure_Context :: struct {
	code:      Failure_Code,
	buffer_id: Buffer_ID,
	revision:  Revision,
	start:     Byte_Offset,
	end:       Byte_Offset,
	limit:     u64,
	actual:    u64,
}

@(private)
limits_are_valid :: proc(limits: Limits) -> bool {
	return limits.buffer_bytes > 0 &&
	       limits.replacement_bytes <= limits.buffer_bytes &&
	       limits.persistent_bytes >= limits.buffer_bytes &&
	       limits.undo_bytes <= limits.persistent_bytes &&
	       limits.temporary_bytes > 0 &&
	       limits.inspection_bytes > 0 &&
	       limits.inspection_bytes <= limits.buffer_bytes &&
	       limits.splice_nodes > 0 &&
	       limits.reclaim_step_nodes > 0 &&
	       limits.reclaim_step_nodes <= limits.reclaim_queue_nodes &&
	       limits.anchors > 0 &&
	       limits.anchors <= MAX_ANCHORS
}

/*
position_make constructs a position for a nonzero buffer identity.
It does not check the offset against live text; use buffer_position for that validation.
*/
position_make :: proc(
	buffer_id: Buffer_ID,
	revision: Revision,
	byte_offset: Byte_Offset,
) -> (position: Position, ok: bool) {
	if buffer_id == Buffer_ID(0) {
		return {}, false
	}

	return Position {
		buffer_id = buffer_id,
		revision = revision,
		byte_offset = byte_offset,
	}, true
}
