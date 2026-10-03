// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package bridge owns checked capabilities that may cross the native boundary.
package bridge

import "../editor"
import "../history"
import "../layout"
import edit_transaction "../transaction"
import "base:runtime"

/* MAX_BUFFER_CAPABILITIES bounds the live buffer capabilities in one registry. */
MAX_BUFFER_CAPABILITIES :: 64
/* MAX_TRANSACTION_CAPABILITIES bounds command-scoped transaction access. */
MAX_TRANSACTION_CAPABILITIES :: 8
/* MAX_HISTORY_POLICY_CAPABILITIES bounds live global-policy authorities. */
MAX_HISTORY_POLICY_CAPABILITIES :: 8
/* MAX_DISPLAY_POLICY_CAPABILITIES bounds live layout-policy authorities. */
MAX_DISPLAY_POLICY_CAPABILITIES :: 8
/* MAX_TRANSACTION_NESTING mirrors the coordinator's admitted nesting depth. */
MAX_TRANSACTION_NESTING :: 32

/* Registry_ID identifies the registry that issued a capability; zero is invalid. */
Registry_ID :: distinct u16

/* Buffer_Capability is an opaque non-pointer token for one registered buffer. */
Buffer_Capability :: distinct u64
/* Transaction_Capability is an opaque dynamic-extent token for one root transaction. */
Transaction_Capability :: distinct u64
/* Nested_Transaction_Capability identifies one active nested command frame. */
Nested_Transaction_Capability :: distinct u64
/* History_Policy_Capability is an opaque dynamic-extent token for one history store. */
History_Policy_Capability :: distinct u64
/* Display_Policy_Capability is an opaque dynamic-extent token for one layout. */
Display_Policy_Capability :: distinct u64

/* Byte_Range identifies one half-open range in canonical UTF-8 byte coordinates. */
Byte_Range :: struct {
	start: editor.Byte_Offset,
	end:   editor.Byte_Offset,
}

/* Buffer_Identity is the bounded identity and revision captured at acquisition. */
Buffer_Identity :: struct {
	buffer_id:  editor.Buffer_ID,
	revision:   editor.Revision,
	text_bytes: u64,
}

/* Failure_Code classifies expected capability and inspection failures. */
Failure_Code :: enum u8 {
	None,
	Invalid_Registry,
	Wrong_Registry,
	Invalid_Capability,
	Stale_Capability,
	Capacity_Limit,
	Retained_Capabilities,
	Closed_Buffer,
	Wrong_Buffer,
	Stale_Revision,
	Stale_Generation,
	Reversed_Range,
	Out_Of_Range,
	Inspection_Limit,
	Malformed_Text,
	Temporary_Memory_Limit,
	Cancelled,
	Editor_Failure,
	Transaction_Failure,
	History_Failure,
	Layout_Failure,
	Policy_Range,
	Policy_Relationship,
	Retention_Blocked,
	Wrong_Thread,
	Reentrant_Call,
	Wrong_Command,
	Wrong_Transaction,
	Malformed_Record,
}

/* Failure_Context identifies the rejected capability, identity, range, and bound. */
Failure_Context :: struct {
	code:        Failure_Code,
	registry_id: Registry_ID,
	capability:  Buffer_Capability,
	history_capability: History_Policy_Capability,
	display_capability: Display_Policy_Capability,
	buffer_id:   editor.Buffer_ID,
	revision:    editor.Revision,
	range:       Byte_Range,
	minimum:     u64,
	limit:       u64,
	actual:      u64,
	editor_code: editor.Failure_Code,
	transaction_code: edit_transaction.Failure_Code,
	history_code: history.Failure_Code,
	layout_code: layout.Failure_Code,
	layout_failure: layout.Failure_Context,
	policy_field: history.Policy_Field,
	policy_generation: history.Policy_Generation,
	display_policy_generation: layout.Display_Policy_Generation,
}

/* Publication_Request supplies one checked root identity and its bounded allocation domains. */
Publication_Request :: struct {
	transaction_id:      edit_transaction.Transaction_ID,
	undo_unit_id:        edit_transaction.Undo_Unit_ID,
	origin:              edit_transaction.Origin,
	command:             string,
	persistent_allocator: runtime.Allocator,
	temporary_allocator:  runtime.Allocator,
	cancelled:            bool,
}

/* Publication_Result retains one checked committed transaction until explicitly closed. */
Publication_Result :: struct {
	transaction: edit_transaction.Transaction,
	commit:      edit_transaction.Commit_Result,
}

@(private)
Registry_State :: enum u8 {
	Uninitialized,
	Ready,
	Closed,
}

@(private)
Buffer_Capability_Slot :: struct {
	buffer:     ^editor.Buffer,
	buffer_id:  editor.Buffer_ID,
	generation: u32,
	live:       bool,
}

/*
Buffer_Capability_Registry owns the native references behind opaque capabilities.
Its fields are implementation state and callers must not modify them directly.
*/
Buffer_Capability_Registry :: struct {
	state:      Registry_State,
	registry_id: Registry_ID,
	live_count: u16,
	slots:      [MAX_BUFFER_CAPABILITIES]Buffer_Capability_Slot,
}

/* Transaction_Edit_Record is one copied base-relative splice descriptor. */
Transaction_Edit_Record :: struct {
	start:              u64,
	end:                u64,
	replacement_offset: u64,
	replacement_bytes:  u64,
}

@(private)
Transaction_Capability_Slot :: struct {
	transaction:    ^edit_transaction.Transaction,
	buffer:         ^editor.Buffer,
	transaction_id: edit_transaction.Transaction_ID,
	command_id:     u64,
	owner_thread_id: int,
	generation:     u32,
	live:           bool,
	call_active:    bool,
	nested_count:   u8,
	nested:         [MAX_TRANSACTION_NESTING]edit_transaction.Nested_Command,
}

/*
Transaction_Capability_Registry owns command-scoped references behind opaque tokens.
Its zero-value storage is fixed-capacity and retains no transaction after release.
*/
Transaction_Capability_Registry :: struct {
	state:       Registry_State,
	registry_id: Registry_ID,
	live_count:  u16,
	slots:       [MAX_TRANSACTION_CAPABILITIES]Transaction_Capability_Slot,
}

@(private)
History_Policy_Capability_Slot :: struct {
	store:           ^history.Store,
	store_id:        history.Store_ID,
	owner_thread_id: int,
	generation:      u32,
	live:            bool,
	call_active:     bool,
}

/*
History_Policy_Capability_Registry owns fixed-capacity dynamic-extent policy authority.
Release clears every native reference and allocates no registry storage.
*/
History_Policy_Capability_Registry :: struct {
	state:       Registry_State,
	registry_id: Registry_ID,
	live_count:  u16,
	slots:       [MAX_HISTORY_POLICY_CAPABILITIES]History_Policy_Capability_Slot,
}

@(private)
Display_Policy_Capability_Slot :: struct {
	registry:        ^layout.Registry,
	owner_id:        layout.Owner_ID,
	layout_id:       layout.Layout_ID,
	owner_thread_id: int,
	generation:      u32,
	live:            bool,
	call_active:     bool,
}

/*
Display_Policy_Capability_Registry owns fixed-capacity dynamic-extent policy authority.
Release clears every native reference and allocates no registry storage.
*/
Display_Policy_Capability_Registry :: struct {
	state:       Registry_State,
	registry_id: Registry_ID,
	live_count:  u16,
	slots:       [MAX_DISPLAY_POLICY_CAPABILITIES]Display_Policy_Capability_Slot,
}
