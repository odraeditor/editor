// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package language_interaction coordinates language operations without owning UI surfaces.
package language_interaction

import "core:unicode/utf8"

/* MAX_TEXT_BYTES bounds copied operation, failure, and recovery messages. */
MAX_TEXT_BYTES :: 1_024

/* Operation identifies one semantic language interaction. */
Operation :: enum u8 {
	Invalid,
	Show_Hover,
	Go_To_Definition,
	Find_References,
	Document_Symbols,
	Workspace_Symbols,
	Signature_Help,
	Rename,
	Format_Buffer,
	Format_Region,
	Code_Actions,
	Describe_Bundle,
	Support_Doctor,
	Bundle_List,
	Bundle_Search,
	Bundle_Install,
	Bundle_Enable,
	Bundle_Disable,
	Bundle_Update,
	Bundle_Rollback,
	Bundle_Remove,
	Bundle_Refresh_Catalogs,
}

/* Operation_Class identifies the runtime authority required by an operation. */
Operation_Class :: enum u8 {
	Invalid,
	Service_Query,
	Checked_Edit,
	Factory_Inspection,
	Bundle_Management,
}

/* Phase identifies one exact interaction lifecycle state. */
Phase :: enum u8 {
	Idle,
	Prompting,
	Selecting,
	Requesting,
	Previewing,
	Confirming,
	Applying,
	Completed,
	Failed,
	Cancelled,
}

/* Surface identifies the existing shared owner that must present the current phase. */
Surface :: enum u8 {
	None,
	Prompt,
	Candidates,
	Popup,
	Results,
	Preview,
	Confirmation,
	Progress,
}

/* Health is the compact operation state projected into the Status Bar. */
Health :: enum u8 {
	Idle,
	Busy,
	Failed,
}

/* Text stores one copied bounded UTF-8 message. */
Text :: struct {
	bytes:  [MAX_TEXT_BYTES]u8,
	length: u16,
}

/* Availability describes whether an operation can start and how to recover when it cannot. */
Availability :: struct {
	available: bool,
	reason:    Text,
	recovery:  Text,
}

/* Begin_Request binds one operation to its exact availability decision. */
Begin_Request :: struct {
	operation:    Operation,
	availability: Availability,
}

/* Snapshot is one pointer-free copied interaction observation. */
Snapshot :: struct {
	generation:    u64,
	operation:     Operation,
	class:         Operation_Class,
	phase:         Phase,
	surface:       Surface,
	health:        Health,
	factory_owned: bool,
	cancellable:   bool,
	progress:      u64,
	progress_total: u64,
	message:       Text,
	failure:       Text,
	recovery:      Text,
}

/* Failure_Code identifies a rejected coordinator transition. */
Failure_Code :: enum u8 {
	None,
	Invalid_Request,
	Busy,
	Unavailable,
	Stale_Generation,
	Invalid_Transition,
	Generation_Limit,
	Invalid_Text,
}

/* Failure describes one rejected coordinator transition. */
Failure :: struct {
	code:       Failure_Code,
	operation:  Operation,
	generation: u64,
}

/* text_copy copies one bounded UTF-8 value. */
text_copy :: proc(value: string) -> (Text, bool) {
	if len(value) > MAX_TEXT_BYTES || !utf8.valid_string(value) do return {}, false
	result := Text{length = u16(len(value))}
	copy(result.bytes[:len(value)], transmute([]u8)value)
	return result, true
}

/* text_string borrows the initialized portion of copied text. */
text_string :: proc(value: ^Text) -> string {
	if value == nil || int(value.length) > len(value.bytes) do return ""
	return string(value.bytes[:int(value.length)])
}

/* availability_available returns the canonical available decision. */
availability_available :: proc() -> Availability {
	return Availability{available = true}
}

/* availability_unavailable copies an exact reason and recovery action. */
availability_unavailable :: proc(reason, recovery: string) -> (Availability, bool) {
	if len(reason) == 0 || len(recovery) == 0 do return {}, false
	reason_text, reason_ok := text_copy(reason)
	recovery_text, recovery_ok := text_copy(recovery)
	if !reason_ok || !recovery_ok do return {}, false
	return Availability{reason = reason_text, recovery = recovery_text}, true
}

/* snapshot_active reports whether cancellation can still affect the current operation. */
snapshot_active :: proc(snapshot: Snapshot) -> bool {
	return snapshot.phase == .Prompting || snapshot.phase == .Selecting ||
	       snapshot.phase == .Requesting || snapshot.phase == .Previewing ||
	       snapshot.phase == .Confirming || snapshot.phase == .Applying
}

/* surface_uses_shared_owner confirms that a surface is an adapter intent, not a new owner. */
surface_uses_shared_owner :: proc(surface: Surface) -> bool {
	return surface >= .Prompt && surface <= .Progress
}
