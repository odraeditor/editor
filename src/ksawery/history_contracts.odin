// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:strings"

/* MIN_HISTORY_PAGE_REVISIONS is the smallest admitted History page capacity. */
MIN_HISTORY_PAGE_REVISIONS :: u32(16)
/* MAX_HISTORY_PAGE_REVISIONS is the immutable History page capacity ceiling. */
MAX_HISTORY_PAGE_REVISIONS :: u32(2_048)
/* DEFAULT_HISTORY_PAGE_REVISIONS is the measured initial History page size. */
DEFAULT_HISTORY_PAGE_REVISIONS :: u32(128)
/* MIN_HISTORY_PARENTS is the smallest useful parent-relationship capacity. */
MIN_HISTORY_PARENTS :: u8(1)
/* MAX_HISTORY_PARENTS is the immutable parent-relationship capacity ceiling. */
MAX_HISTORY_PARENTS :: u8(16)
/* DEFAULT_HISTORY_PARENTS is the measured initial parent-relationship capacity. */
DEFAULT_HISTORY_PARENTS :: u8(16)
/* MIN_HISTORY_METADATA_BYTES is the smallest admitted retained History metadata budget. */
MIN_HISTORY_METADATA_BYTES :: u64(16 * KIBIBYTE)
/* MAX_HISTORY_METADATA_BYTES is the immutable retained History metadata ceiling. */
MAX_HISTORY_METADATA_BYTES :: u64(512 * KIBIBYTE)
/* DEFAULT_HISTORY_METADATA_BYTES is the measured initial retained History metadata budget. */
DEFAULT_HISTORY_METADATA_BYTES :: MAX_HISTORY_METADATA_BYTES
/* MIN_HISTORY_MESSAGE_BYTES is the smallest admitted one-revision message preview. */
MIN_HISTORY_MESSAGE_BYTES :: u64(256)
/* MAX_HISTORY_MESSAGE_BYTES is the immutable one-revision message preview ceiling. */
MAX_HISTORY_MESSAGE_BYTES :: u64(16 * KIBIBYTE)
/* DEFAULT_HISTORY_MESSAGE_BYTES is the measured initial one-revision message preview budget. */
DEFAULT_HISTORY_MESSAGE_BYTES :: MAX_HISTORY_MESSAGE_BYTES
/* MIN_HISTORY_TOPOLOGY_BYTES is the smallest admitted retained revision-topology budget. */
MIN_HISTORY_TOPOLOGY_BYTES :: u64(64 * KIBIBYTE)
/* MAX_HISTORY_TOPOLOGY_BYTES is the immutable retained revision-topology ceiling. */
MAX_HISTORY_TOPOLOGY_BYTES :: u64(8 * MEBIBYTE)
/* DEFAULT_HISTORY_TOPOLOGY_BYTES is the measured initial retained topology budget. */
DEFAULT_HISTORY_TOPOLOGY_BYTES :: u64(512 * KIBIBYTE)
/* MIN_HISTORY_TEMPORARY_BYTES is the smallest parser temporary-allocation budget. */
MIN_HISTORY_TEMPORARY_BYTES :: u64(512 * KIBIBYTE)
/* MAX_HISTORY_TEMPORARY_BYTES is the immutable parser temporary-allocation ceiling. */
MAX_HISTORY_TEMPORARY_BYTES :: u64(16 * MEBIBYTE)
/* DEFAULT_HISTORY_TEMPORARY_BYTES is the measured initial parser temporary budget. */
DEFAULT_HISTORY_TEMPORARY_BYTES :: u64(4 * MEBIBYTE)
/* MAX_REVISION_ID_BYTES admits a full current or future Git object identity. */
MAX_REVISION_ID_BYTES :: 128

/* History_Generation identifies one immutable History observation. */
History_Generation :: distinct u64

/* Revision_Identity owns one canonical full Git object identity. */
Revision_Identity :: struct {
	bytes:  [MAX_REVISION_ID_BYTES]u8,
	length: u8,
}

/* History_Text_Ref identifies bounded text owned by one History observation. */
History_Text_Ref :: struct {
	offset: u32,
	length: u32,
}

/* Revision_Entry describes one exact revision and its retained semantic metadata. */
Revision_Entry :: struct {
	identity:     Revision_Identity,
	parents:      [MAX_HISTORY_PARENTS]Revision_Identity,
	parent_count: u8,
	author_name:  History_Text_Ref,
	author_email: History_Text_Ref,
	authored_at:  History_Text_Ref,
	committed_at: History_Text_Ref,
	subject:      History_Text_Ref,
	message:      History_Text_Ref,
}

/* History_Continuation owns the exact observed ancestry anchor for the next page. */
History_Continuation :: struct {
	head:    Revision_Identity,
	after:   Revision_Identity,
	skipped: u32,
}

/* History_Limits bounds one parsed History page and its temporary parser work. */
History_Limits :: struct {
	page_revisions: u32,
	parents:        u8,
	metadata_bytes: u64,
	message_bytes:  u64,
	topology_bytes: u64,
	temporary_bytes: u64,
}

/* DEFAULT_HISTORY_LIMITS selects the measured initial History resource envelope. */
DEFAULT_HISTORY_LIMITS :: History_Limits {
	page_revisions = DEFAULT_HISTORY_PAGE_REVISIONS,
	parents = DEFAULT_HISTORY_PARENTS,
	metadata_bytes = DEFAULT_HISTORY_METADATA_BYTES,
	message_bytes = DEFAULT_HISTORY_MESSAGE_BYTES,
	topology_bytes = DEFAULT_HISTORY_TOPOLOGY_BYTES,
	temporary_bytes = DEFAULT_HISTORY_TEMPORARY_BYTES,
}

/* History_Request describes one bounded first or continued exact-ancestry observation. */
History_Request :: struct {
	limits:       History_Limits,
	continuation: History_Continuation,
}

/* History_State distinguishes an unborn repository from an available History page. */
History_State :: enum u8 {
	Invalid,
	Unborn,
	Exhausted,
	Available,
}

/* History_Observation owns one parsed immutable History result. */
History_Observation :: struct {
	state: rawptr,
}

/* History_Observation_Descriptor reports one bounded immutable History result. */
History_Observation_Descriptor :: struct {
	repository:       Repository_Context,
	generation:       History_Generation,
	state:            History_State,
	head:             Revision_Identity,
	revision_count:   u32,
	parent_links:     u32,
	metadata_bytes:   u64,
	message_bytes:    u64,
	topology_bytes:   u64,
	temporary_bytes:  u64,
	continuation:     History_Continuation,
}

/* History_Target identifies one exact revision in one immutable History observation. */
History_Target :: struct {
	generation: History_Generation,
	revision:   Revision_Identity,
}

/* History_Item_Kind distinguishes selectable revisions from their parent relationships. */
History_Item_Kind :: enum u8 {
	Invalid,
	Revision,
	Parent,
}

/* History_Item_ID identifies one semantic History row without using positional identity. */
History_Item_ID :: struct {
	kind:     History_Item_Kind,
	revision: History_Target,
	parent:   Revision_Identity,
}

/* History_Selection owns session-local History navigation and one optional exact mark. */
History_Selection :: struct {
	generation: History_Generation,
	current:    History_Item_ID,
	marked:     History_Target,
}

/* History_Usage reports exact retained History resources. */
History_Usage :: struct {
	revisions:        u32,
	parent_links:     u32,
	metadata_bytes:   u64,
	message_bytes:    u64,
	topology_bytes:   u64,
	temporary_bytes:  u64,
	allocation_bytes: u64,
}

/* revision_identity_assign copies one canonical full lowercase hexadecimal object identity. */
revision_identity_assign :: proc(identity: ^Revision_Identity, text: string) -> bool {
	if identity == nil do return false
	identity^ = {}
	if !revision_identity_text_is_valid(text) do return false
	copy(identity.bytes[:len(text)], transmute([]u8)text)
	identity.length = u8(len(text))
	return true
}

/* revision_identity_is_valid checks one copied canonical full object identity. */
revision_identity_is_valid :: proc(identity: Revision_Identity) -> bool {
	if identity.length < 40 || int(identity.length) > len(identity.bytes) || identity.length % 2 != 0 {
		return false
	}
	copy := identity
	for byte in copy.bytes[:copy.length] {
		if !revision_identity_hex_byte_is_valid(byte) do return false
	}
	return true
}

/* revision_identity_string returns one borrowed canonical full object identity. */
revision_identity_string :: proc(identity: ^Revision_Identity) -> string {
	if identity == nil || !revision_identity_is_valid(identity^) do return ""
	return string(identity.bytes[:identity.length])
}

/* history_continuation_is_valid admits an initial request or one complete exact anchor. */
history_continuation_is_valid :: proc(continuation: History_Continuation) -> bool {
	if continuation == {} do return true
	return revision_identity_is_valid(continuation.head) && revision_identity_is_valid(continuation.after) &&
	       continuation.skipped > 0
}

/* history_limits_are_valid checks the complete selected History resource envelope. */
history_limits_are_valid :: proc(limits: History_Limits) -> bool {
	return limits.page_revisions >= MIN_HISTORY_PAGE_REVISIONS &&
	       limits.page_revisions <= MAX_HISTORY_PAGE_REVISIONS &&
	       limits.parents >= MIN_HISTORY_PARENTS && limits.parents <= MAX_HISTORY_PARENTS &&
	       limits.metadata_bytes >= MIN_HISTORY_METADATA_BYTES &&
	       limits.metadata_bytes <= MAX_HISTORY_METADATA_BYTES &&
	       limits.message_bytes >= MIN_HISTORY_MESSAGE_BYTES &&
	       limits.message_bytes <= MAX_HISTORY_MESSAGE_BYTES &&
	       limits.topology_bytes >= MIN_HISTORY_TOPOLOGY_BYTES &&
	       limits.topology_bytes <= MAX_HISTORY_TOPOLOGY_BYTES &&
	       limits.temporary_bytes >= MIN_HISTORY_TEMPORARY_BYTES &&
	       limits.temporary_bytes <= MAX_HISTORY_TEMPORARY_BYTES &&
	       limits.message_bytes <= limits.metadata_bytes &&
	       history_topology_bytes_required(limits.page_revisions) <= limits.topology_bytes &&
	       limits.metadata_bytes + limits.topology_bytes <= limits.temporary_bytes
}

/* history_request_is_valid admits only a bounded initial or exactly anchored page request. */
history_request_is_valid :: proc(request: History_Request) -> bool {
	return history_limits_are_valid(request.limits) && history_continuation_is_valid(request.continuation)
}

/* history_target_is_valid checks one exact observation-bound revision identity. */
history_target_is_valid :: proc(target: History_Target) -> bool {
	return target.generation != History_Generation(0) && revision_identity_is_valid(target.revision)
}

/* history_item_id_is_valid checks one semantic revision or parent row identity. */
history_item_id_is_valid :: proc(item: History_Item_ID) -> bool {
	switch item.kind {
	case .Revision:
		return history_target_is_valid(item.revision) && item.parent == {}
	case .Parent:
		return history_target_is_valid(item.revision) && revision_identity_is_valid(item.parent)
	case .Invalid:
		return false
	}
	return false
}

/* history_selection_is_valid checks local selection ownership without requiring a live observation. */
history_selection_is_valid :: proc(selection: History_Selection) -> bool {
	if selection.generation == History_Generation(0) do return false
	if selection.current != {} &&
	   (!history_item_id_is_valid(selection.current) || selection.current.revision.generation != selection.generation) {
		return false
	}
	return selection.marked == {} ||
	       (history_target_is_valid(selection.marked) && selection.marked.generation == selection.generation)
}

/* revision_entry_is_valid checks one parsed revision against its owned text and parent budgets. */
revision_entry_is_valid :: proc(
	entry: Revision_Entry,
	metadata_bytes: u64,
	limits := DEFAULT_HISTORY_LIMITS,
) -> bool {
	if !history_limits_are_valid(limits) || !revision_identity_is_valid(entry.identity) ||
	   entry.parent_count > limits.parents {
		return false
	}
	for parent_index in 0 ..< int(entry.parent_count) {
		if !revision_identity_is_valid(entry.parents[parent_index]) do return false
	}
	for parent_index in int(entry.parent_count) ..< len(entry.parents) {
		if entry.parents[parent_index] != {} do return false
	}
	return history_text_ref_is_valid(entry.author_name, metadata_bytes) &&
	       history_text_ref_is_valid(entry.author_email, metadata_bytes) &&
	       history_text_ref_is_valid(entry.authored_at, metadata_bytes) &&
	       history_text_ref_is_valid(entry.committed_at, metadata_bytes) &&
	       history_text_ref_is_valid(entry.subject, metadata_bytes) &&
	       history_text_ref_is_valid(entry.message, metadata_bytes) &&
	       u64(entry.message.length) <= limits.message_bytes
}

/* history_observation_descriptor_is_valid checks one immutable bounded History summary. */
history_observation_descriptor_is_valid :: proc(
	descriptor: History_Observation_Descriptor,
	limits := DEFAULT_HISTORY_LIMITS,
) -> bool {
	if !repository_context_is_valid(descriptor.repository) ||
	   descriptor.generation == History_Generation(0) || !history_limits_are_valid(limits) {
		return false
	}
	switch descriptor.state {
	case .Unborn:
		return descriptor.head == {} && descriptor.revision_count == 0 && descriptor.parent_links == 0 &&
		       descriptor.metadata_bytes == 0 && descriptor.message_bytes == 0 &&
		       descriptor.topology_bytes == 0 && descriptor.temporary_bytes == 0 && descriptor.continuation == {}
	case .Exhausted:
		return revision_identity_is_valid(descriptor.head) && descriptor.revision_count == 0 &&
		       descriptor.parent_links == 0 && descriptor.metadata_bytes == 0 && descriptor.message_bytes == 0 &&
		       descriptor.topology_bytes == 0 && descriptor.temporary_bytes <= limits.temporary_bytes &&
		       descriptor.continuation == {}
	case .Available:
		return revision_identity_is_valid(descriptor.head) && descriptor.revision_count > 0 &&
		       descriptor.revision_count <= limits.page_revisions &&
		       descriptor.parent_links <= descriptor.revision_count * u32(limits.parents) &&
		       descriptor.metadata_bytes <= limits.metadata_bytes &&
		       descriptor.message_bytes <= descriptor.metadata_bytes &&
		       descriptor.message_bytes <= u64(descriptor.revision_count) * limits.message_bytes &&
		       descriptor.topology_bytes >= history_topology_bytes_required(descriptor.revision_count) &&
		       descriptor.topology_bytes <= limits.topology_bytes &&
		       descriptor.temporary_bytes <= limits.temporary_bytes &&
		       history_continuation_is_valid(descriptor.continuation)
	case .Invalid:
		return false
	}
	return false
}

@(private)
history_text_ref_is_valid :: proc(reference: History_Text_Ref, storage_bytes: u64) -> bool {
	end := u64(reference.offset) + u64(reference.length)
	return end >= u64(reference.offset) && end <= storage_bytes
}

@(private)
history_topology_bytes_required :: proc(revisions: u32) -> u64 {
	return u64(revisions) * u64(size_of(Revision_Entry))
}

@(private)
revision_identity_text_is_valid :: proc(text: string) -> bool {
	if len(text) < 40 || len(text) > MAX_REVISION_ID_BYTES || len(text) % 2 != 0 ||
	   strings.index_byte(text, 0) >= 0 {
		return false
	}
	for byte in transmute([]u8)text {
		if !revision_identity_hex_byte_is_valid(byte) do return false
	}
	return true
}

@(private)
revision_identity_hex_byte_is_valid :: proc(byte: u8) -> bool {
	return byte >= '0' && byte <= '9' || byte >= 'a' && byte <= 'f'
}
