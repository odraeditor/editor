// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package package_catalog_interaction coordinates package catalog UI operations.
package package_catalog_interaction

import "core:unicode/utf8"

/* MAX_CANDIDATES bounds one copied package catalog candidate generation. */
MAX_CANDIDATES :: 64
/* MAX_TEXT_BYTES bounds copied identifiers, labels, and diagnostics. */
MAX_TEXT_BYTES :: 256

/* Operation identifies one stable package catalog semantic command. */
Operation :: enum u8 {
	Invalid,
	Catalog_List,
	Catalog_Add,
	Catalog_Disable,
	Catalog_Remove,
	Catalog_Refresh,
	Catalog_Search,
	Catalog_Describe,
	Manual_Acquire,
	Advisory_List,
	Curator_Validate,
	Catalog_Doctor,
	Package_List,
	Package_Discover,
	Package_Describe,
	Package_Install,
	Package_Enable,
	Package_Disable,
	Package_Update,
	Package_Rollback,
	Package_Remove,
	Package_Cleanup,
	Package_Doctor,
}

/* Phase identifies one exact interaction transition. */
Phase :: enum u8 {
	Idle,
	Prompting,
	Requesting,
	Selecting,
	Inspecting,
	Confirming,
	Applying,
	Completed,
	Failed,
	Cancelled,
}

/* Surface identifies an existing Odra presentation owner. */
Surface :: enum u8 {
	None,
	Prompt,
	Candidates,
	Results,
	Confirmation,
	Progress,
}

/* Candidate_Kind identifies the owner of one copied selection. */
Candidate_Kind :: enum u8 {
	Invalid,
	Catalog,
	Package,
	Manual_Source,
	Advisory,
	Curator_Record,
	Package_Release,
	Installed_Package,
}

/* Freshness keeps discovery state distinct from other trust dimensions. */
Freshness :: enum u8 {
	Unknown,
	Current,
	Offline,
	Stale,
	Failed,
	Blocked,
}

/* Curation_State describes one curator assertion, not execution authority. */
Curation_State :: enum u8 {
	Unknown,
	Admitted,
	Deprecated,
	Withdrawn,
	Quarantined,
	Uncurated,
}

/* Integrity_State describes exact content verification independently. */
Integrity_State :: enum u8 {
	Unknown,
	Verified,
	Conflict,
	Rejected,
}

/* Authority_State describes local capability policy independently. */
Authority_State :: enum u8 {
	Unknown,
	Required,
	Granted,
	Denied,
}

/* Installation_State describes package lifecycle state independently. */
Installation_State :: enum u8 {
	Unknown,
	Not_Installed,
	Prepared,
	Installed,
	Failed,
}

/* Activation_State describes runtime state independently. */
Activation_State :: enum u8 {
	Unknown,
	Inactive,
	Pending,
	Active,
	Failed,
}

/* Advisory_State describes trusted advisory impact independently. */
Advisory_State :: enum u8 {
	Unknown,
	Clear,
	Warning,
	Blocked,
	Quarantined,
}

/* Text stores one copied bounded UTF-8 value. */
Text :: struct {
	bytes:  [MAX_TEXT_BYTES]u8,
	length: u16,
}

/* Availability gives an unavailable operation one exact recovery action. */
Availability :: struct {
	available: bool,
	reason:    Text,
	recovery:  Text,
}

/* Candidate is one pointer-free generation-bound selection row. */
Candidate :: struct {
	id:                 Text,
	label:              Text,
	kind:               Candidate_Kind,
	record_generation:  u64,
	catalog_generation: u64,
	snapshot_id:        Text,
	freshness:          Freshness,
}

/* Candidate_List owns one copied bounded generation. */
Candidate_List :: struct {
	generation: u64,
	count:      u16,
	values:     [MAX_CANDIDATES]Candidate,
}

/* Confirmation binds one operation and selected record generation exactly. */
Confirmation :: struct {
	workflow_generation: u64,
	operation:           Operation,
	candidate_id:        Text,
	record_generation:   u64,
	catalog_generation:  u64,
	snapshot_id:         Text,
}

/* Inspection keeps trust, content, authority, and lifecycle facts separate. */
Inspection :: struct {
	subject_id:   Text,
	curation:     Curation_State,
	integrity:    Integrity_State,
	authority:    Authority_State,
	installation: Installation_State,
	activation:   Activation_State,
	advisory:     Advisory_State,
	freshness:    Freshness,
	detail:       Text,
}

/* Snapshot is one copied UI-independent workflow observation. */
Snapshot :: struct {
	generation:      u64,
	operation:       Operation,
	phase:           Phase,
	surface:         Surface,
	return_surface:  Surface,
	cancellable:     bool,
	progress:        u64,
	progress_total:  u64,
	message:         Text,
	failure:         Text,
	recovery:        Text,
	selected_index:  u16,
	selection_valid: bool,
	confirmation:    Confirmation,
	inspection:      Inspection,
}

/* Failure_Code identifies one rejected coordinator transition. */
Failure_Code :: enum u8 {
	None,
	Invalid_Request,
	Busy,
	Unavailable,
	Stale_Generation,
	Stale_Candidates,
	Stale_Confirmation,
	Invalid_Transition,
	Limit,
	Invalid_Text,
}

/* Failure reports a rejected transition without retaining borrowed data. */
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

/* text_string borrows only the initialized portion of copied text. */
text_string :: proc(value: ^Text) -> string {
	if value == nil || int(value.length) > len(value.bytes) do return ""
	return string(value.bytes[:int(value.length)])
}

/* text_equal compares copied text without borrowing transient storage. */
text_equal :: proc(left, right: Text) -> bool {
	if left.length != right.length do return false
	for index in 0 ..< int(left.length) {
		if left.bytes[index] != right.bytes[index] do return false
	}
	return true
}

/* availability_available returns the canonical admitted decision. */
availability_available :: proc() -> Availability {
	return Availability{available = true}
}

/* availability_unavailable copies one exact reason and recovery action. */
availability_unavailable :: proc(reason, recovery: string) -> (Availability, bool) {
	if len(reason) == 0 || len(recovery) == 0 do return {}, false
	reason_text, reason_ok := text_copy(reason)
	recovery_text, recovery_ok := text_copy(recovery)
	if !reason_ok || !recovery_ok do return {}, false
	return Availability{reason = reason_text, recovery = recovery_text}, true
}

/* candidate copies one exact bounded selection row. */
candidate :: proc(
	id, label: string,
	kind: Candidate_Kind,
	record_generation, catalog_generation: u64,
	snapshot_id: string,
	freshness: Freshness,
) -> (Candidate, bool) {
	if len(id) == 0 || len(label) == 0 || kind == .Invalid ||
	   record_generation == 0 || catalog_generation == 0 {
		return {}, false
	}
	id_text, id_ok := text_copy(id)
	label_text, label_ok := text_copy(label)
	snapshot_text, snapshot_ok := text_copy(snapshot_id)
	if !id_ok || !label_ok || !snapshot_ok do return {}, false
	return {
		id = id_text,
		label = label_text,
		kind = kind,
		record_generation = record_generation,
		catalog_generation = catalog_generation,
		snapshot_id = snapshot_text,
		freshness = freshness,
	}, true
}

/* inspection copies independent trust and lifecycle facts. */
inspection :: proc(
	subject_id: string,
	curation: Curation_State,
	integrity: Integrity_State,
	authority: Authority_State,
	installation: Installation_State,
	activation: Activation_State,
	advisory: Advisory_State,
	freshness: Freshness,
	detail: string,
) -> (Inspection, bool) {
	if len(subject_id) == 0 do return {}, false
	subject, subject_ok := text_copy(subject_id)
	detail_text, detail_ok := text_copy(detail)
	if !subject_ok || !detail_ok do return {}, false
	return {
		subject_id = subject,
		curation = curation,
		integrity = integrity,
		authority = authority,
		installation = installation,
		activation = activation,
		advisory = advisory,
		freshness = freshness,
		detail = detail_text,
	}, true
}

/* snapshot_active reports whether cancellation can still affect work. */
snapshot_active :: proc(snapshot: Snapshot) -> bool {
	return snapshot.phase == .Prompting || snapshot.phase == .Requesting ||
	       snapshot.phase == .Selecting || snapshot.phase == .Inspecting ||
	       snapshot.phase == .Confirming || snapshot.phase == .Applying
}

/* surface_uses_shared_owner rejects creation of a package-specific UI owner. */
surface_uses_shared_owner :: proc(surface: Surface) -> bool {
	return surface >= .Prompt && surface <= .Progress
}
