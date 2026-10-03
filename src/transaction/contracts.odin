// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package transaction coordinates bounded atomic edits over editor-owned private revisions.
package transaction

import "../editor"
import "../history"
import editor_view "../view"
import "base:runtime"

/* KIBIBYTE is the binary byte unit used by transaction limits. */
KIBIBYTE :: u64(1024)
/* MEBIBYTE is 1,024 kibibytes. */
MEBIBYTE :: u64(1024) * KIBIBYTE
/* GIBIBYTE is 1,024 mebibytes. */
GIBIBYTE :: u64(1024) * MEBIBYTE

/* MAX_SPLICES is the default number of admitted edit operations. */
MAX_SPLICES :: u64(100_000)
/* MAX_TEXT_BYTES bounds inserted, removed, and rollback-retained text. */
MAX_TEXT_BYTES :: 1 * GIBIBYTE
/* MAX_TEMPORARY_BYTES bounds transaction scratch storage. */
MAX_TEMPORARY_BYTES :: 512 * MEBIBYTE
/* MAX_METADATA_BYTES bounds transaction metadata excluding retained text. */
MAX_METADATA_BYTES :: 16 * MEBIBYTE
/* MAX_ORIGIN_BYTES bounds one UTF-8 origin descriptor. */
MAX_ORIGIN_BYTES :: u64(256)
/* MAX_COMMAND_BYTES bounds one UTF-8 command identity. */
MAX_COMMAND_BYTES :: u64(256)
/* MAX_NESTED_COMMAND_DEPTH bounds active command composition depth. */
MAX_NESTED_COMMAND_DEPTH :: u64(32)
/* MAX_ACTIVE_SAVEPOINTS bounds retained rollback roots. */
MAX_ACTIVE_SAVEPOINTS :: u64(256)
/* MAX_LOGICAL_VIEW_PARTICIPANTS is the current initiating-view participant capacity. */
MAX_LOGICAL_VIEW_PARTICIPANTS :: u64(1)
/* MAX_BUFFER_PARTICIPANTS bounds one deterministic atomic publication set. */
MAX_BUFFER_PARTICIPANTS :: u64(10_000)
/* DEFAULT_CHECKPOINT_OPERATIONS bounds work between cancellation checks. */
DEFAULT_CHECKPOINT_OPERATIONS :: u64(1_024)

/* Transaction_ID identifies one root transaction; zero is invalid. */
Transaction_ID :: distinct u64
/* Undo_Unit_ID identifies the atomic history record associated with a commit; zero is invalid. */
Undo_Unit_ID :: distinct u64
/* Nested_Command is an opaque command-scoped handle that cannot commit a root transaction. */
Nested_Command :: distinct [4]u64

/* Nested_Failure_Disposition selects whether restored nested failure is handled by its caller. */
Nested_Failure_Disposition :: enum u8 {
	Invalid,
	Handled,
	Unhandled,
}

/* Nested_Command_Stats reports copied metadata and depth for one active nested command. */
Nested_Command_Stats :: struct {
	transaction_id: Transaction_ID,
	depth:          u64,
	origin:         Origin,
	command:        string,
}

/* Lifecycle is the explicit root transaction state machine. */
Lifecycle :: enum u8 {
	Invalid,
	Building,
	Validating,
	Ready,
	Publishing,
	Committed,
	Aborted,
	Closed,
}

/* Origin_Kind classifies diagnostic edit producers without granting authority. */
Origin_Kind :: enum u8 {
	Invalid,
	Built_In,
	Racket,
	Language_Tool,
	External_Proposal,
}

/* Origin describes an admitted producer with bounded UTF-8 diagnostic text. */
Origin :: struct {
	kind:        Origin_Kind,
	descriptor: string,
}

/* Limits collects independent resource bounds for one transaction. */
Limits :: struct {
	buffer_participants:   u64,
	splices:              u64,
	text_bytes:           u64,
	temporary_bytes:      u64,
	metadata_bytes:       u64,
	origin_bytes:         u64,
	command_bytes:        u64,
	nested_command_depth: u64,
	active_savepoints:    u64,
	logical_views:        u64,
	checkpoint_operations: u64,
}

/* DEFAULT_LIMITS is the production transaction profile. */
DEFAULT_LIMITS :: Limits {
	buffer_participants = MAX_BUFFER_PARTICIPANTS,
	splices = MAX_SPLICES,
	text_bytes = MAX_TEXT_BYTES,
	temporary_bytes = MAX_TEMPORARY_BYTES,
	metadata_bytes = MAX_METADATA_BYTES,
	origin_bytes = MAX_ORIGIN_BYTES,
	command_bytes = MAX_COMMAND_BYTES,
	nested_command_depth = MAX_NESTED_COMMAND_DEPTH,
	active_savepoints = MAX_ACTIVE_SAVEPOINTS,
	logical_views = MAX_LOGICAL_VIEW_PARTICIPANTS,
	checkpoint_operations = DEFAULT_CHECKPOINT_OPERATIONS,
}

/* Allocator_Set supplies persistent transaction storage and operation scratch storage. */
Allocator_Set :: struct {
	// The caller keeps this allocator alive until transaction_close returns.
	persistent: runtime.Allocator,
	// The caller keeps this allocator alive for every transaction operation.
	temporary:  runtime.Allocator,
}

/* Base_Splice is one edit expressed against a confirmed buffer revision. */
Base_Splice :: struct {
	start:       editor.Position,
	end:         editor.Position,
	replacement: string,
}

/* Normalized_Splice describes one owned committed transition in base coordinates. */
Normalized_Splice :: struct {
	start:            editor.Byte_Offset,
	end:              editor.Byte_Offset,
	replacement_text: string,
	removed_text:     string,
}

/* Resource_Usage reports bounded work and retained result storage. */
Resource_Usage :: struct {
	buffer_participants: u64,
	admitted_splices: u64,
	text_bytes:       u64,
	metadata_bytes:   u64,
	checkpoints:      u64,
	nested_commands:  u64,
	savepoints:       u64,
	logical_views:    u64,
}

/* Commit_Event is the immutable consolidated observer view of one committed root. */
Commit_Event :: struct {
	transaction_id: Transaction_ID,
	undo_unit_id:   Undo_Unit_ID,
	origin:         Origin,
	command:        string,
	buffer_id:      editor.Buffer_ID,
	base_revision:  editor.Revision,
	result_revision: editor.Revision,
	splices:        []Normalized_Splice,
	usage:          Resource_Usage,
	logical_view:   editor_view.Logical_Commit_Result,
}

/* Observer_Status reports post-commit delivery without changing commit success. */
Observer_Status :: enum u8 {
	Not_Invoked,
	Succeeded,
	Failed,
}

/* Commit_Observer_Procedure consumes a borrowed immutable event after publication. */
Commit_Observer_Procedure :: proc(user_data: rawptr, event: Commit_Event) -> bool

/* Commit_Observer supplies one contained synchronous post-commit consumer. */
Commit_Observer :: struct {
	procedure: Commit_Observer_Procedure,
	user_data: rawptr,
}

/* Commit_Result retains the event and its contained post-commit delivery status. */
Commit_Result :: struct {
	using event: Commit_Event,
	observer_status: Observer_Status,
}

/* Transaction_Stats reports lifecycle, identity, participant, and resource state. */
Transaction_Stats :: struct {
	transaction_id: Transaction_ID,
	undo_unit_id:   Undo_Unit_ID,
	lifecycle:      Lifecycle,
	buffer_id:      editor.Buffer_ID,
	base_revision:  editor.Revision,
	working_generation: u64,
	nesting_depth:     u64,
	active_savepoints: u64,
	usage:          Resource_Usage,
}

/* Failure_Code classifies expected transaction rejection before publication. */
Failure_Code :: enum u16 {
	None,
	Invalid_Identity,
	Invalid_Limits,
	Invalid_State,
	Invalid_Origin,
	Origin_Limit,
	Command_Limit,
	Nesting_Limit,
	Savepoint_Limit,
	Invalid_Nested_Command,
	Participant_Limit,
	Incomplete_Participant_Set,
	View_Failure,
	Wrong_Buffer,
	Stale_Revision,
	Mismatched_Revision,
	Reversed_Range,
	Out_Of_Range,
	Mid_Encoding_Offset,
	Malformed_UTF8,
	Overlapping_Batch,
	Ambiguous_Order,
	Splice_Limit,
	Text_Limit,
	Temporary_Memory_Limit,
	Metadata_Memory_Limit,
	Persistent_Memory_Limit,
	Work_Limit,
	Cancelled,
	Changeset_Mismatch,
	Reentrant_Mutation,
	History_Failure,
}

/* Failure_Context reports one expected failure and preserves editor detail when relevant. */
Failure_Context :: struct {
	code:           Failure_Code,
	transaction_id: Transaction_ID,
	buffer_id:      editor.Buffer_ID,
	base_revision:  editor.Revision,
	splice_index:   u64,
	limit:          u64,
	actual:         u64,
	editor_failure: editor.Failure_Context,
	view_failure:   editor_view.Failure_Context,
	history_failure: history.Failure_Context,
}

/* Transaction is an opaque root coordinator handle that must be closed exactly once. */
Transaction :: struct {
	state: rawptr,
}

/* Buffer_Commit_Result is one buffer's immutable contribution to a shared commit. */
Buffer_Commit_Result :: struct {
	buffer_id:       editor.Buffer_ID,
	base_revision:   editor.Revision,
	result_revision: editor.Revision,
	splices:         []Normalized_Splice,
}

/* Multibuffer_Commit_Event is one consolidated result in deterministic buffer order. */
Multibuffer_Commit_Event :: struct {
	transaction_id: Transaction_ID,
	undo_unit_id:   Undo_Unit_ID,
	origin:         Origin,
	command:        string,
	buffers:        []Buffer_Commit_Result,
	usage:          Resource_Usage,
}

/* Multibuffer_Observer_Procedure consumes a borrowed shared event after publication. */
Multibuffer_Observer_Procedure :: proc(user_data: rawptr, event: Multibuffer_Commit_Event) -> bool

/* Multibuffer_Observer supplies one contained synchronous post-commit consumer. */
Multibuffer_Observer :: struct {
	procedure: Multibuffer_Observer_Procedure,
	user_data: rawptr,
}

/* Multibuffer_Commit_Result retains the shared event and observer delivery status. */
Multibuffer_Commit_Result :: struct {
	using event: Multibuffer_Commit_Event,
	observer_status: Observer_Status,
}

/* Buffer_Commit_Event is a filtered view that preserves one shared commit identity. */
Buffer_Commit_Event :: struct {
	transaction_id: Transaction_ID,
	undo_unit_id:   Undo_Unit_ID,
	origin:         Origin,
	command:        string,
	buffer:         Buffer_Commit_Result,
	usage:          Resource_Usage,
}

/* Multibuffer_Transaction is an opaque root over a complete declared buffer set. */
Multibuffer_Transaction :: struct {
	state: rawptr,
}

/* Proposal_Snapshot declares one producer-observed confirmed buffer revision. */
Proposal_Snapshot :: struct {
	buffer:        ^editor.Buffer,
	buffer_id:     editor.Buffer_ID,
	base_revision: editor.Revision,
}

/* Proposal_Edit carries one complete base-relative batch for a declared snapshot. */
Proposal_Edit :: struct {
	buffer_id:     editor.Buffer_ID,
	base_revision: editor.Revision,
	batch:         []Base_Splice,
}

/* Edit_Proposal is one producer-neutral optimistic request over a complete participant set. */
Edit_Proposal :: struct {
	origin:    Origin,
	command:   string,
	snapshots: []Proposal_Snapshot,
	edits:     []Proposal_Edit,
}
