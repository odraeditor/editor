// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:strings"

/* MIN_REF_ENTRIES is the smallest admitted Ref entry capacity. */
MIN_REF_ENTRIES :: u32(16)
/* MAX_REF_ENTRIES is the immutable Ref entry capacity ceiling. */
MAX_REF_ENTRIES :: u32(4_096)
/* DEFAULT_REF_ENTRIES is the measured initial Ref entry capacity. */
DEFAULT_REF_ENTRIES :: u32(256)
/* MAX_REF_NAME_BYTES bounds one copied complete Git ref name. */
MAX_REF_NAME_BYTES :: 1_024
/* MIN_REF_METADATA_BYTES is the smallest admitted aggregate Ref metadata budget. */
MIN_REF_METADATA_BYTES :: u64(16 * KIBIBYTE)
/* MAX_REF_METADATA_BYTES is the immutable aggregate Ref metadata ceiling. */
MAX_REF_METADATA_BYTES :: u64(4 * MEBIBYTE)
/* DEFAULT_REF_METADATA_BYTES is the measured initial Ref metadata budget. */
DEFAULT_REF_METADATA_BYTES :: u64(512 * KIBIBYTE)
/* MIN_REF_TEMPORARY_BYTES is the smallest admitted temporary Ref parser budget. */
MIN_REF_TEMPORARY_BYTES :: u64(512 * KIBIBYTE)
/* MAX_REF_TEMPORARY_BYTES is the immutable temporary Ref parser ceiling. */
MAX_REF_TEMPORARY_BYTES :: u64(16 * MEBIBYTE)
/* DEFAULT_REF_TEMPORARY_BYTES is the measured initial temporary Ref parser budget. */
DEFAULT_REF_TEMPORARY_BYTES :: u64(4 * MEBIBYTE)
/* MAX_REMOTE_ENTRIES is the immutable configured-remote capacity ceiling. */
MAX_REMOTE_ENTRIES :: u32(512)
/* DEFAULT_REMOTE_ENTRIES is the measured initial configured-remote capacity. */
DEFAULT_REMOTE_ENTRIES :: u32(32)
/* MAX_REMOTE_NAME_BYTES bounds one copied configured remote name. */
MAX_REMOTE_NAME_BYTES :: 256

/* Ref_Generation identifies one immutable Ref observation. */
Ref_Generation :: distinct u64

/* Ref_Name owns one complete bounded Git ref name. */
Ref_Name :: struct {
	bytes:  [MAX_REF_NAME_BYTES]u8,
	length: u16,
}

/* Remote_Name owns one bounded configured remote name. */
Remote_Name :: struct {
	bytes:  [MAX_REMOTE_NAME_BYTES]u8,
	length: u16,
}

/* Ref_Kind distinguishes the admitted Git ref categories. */
Ref_Kind :: enum u8 {
	Invalid,
	Local_Branch,
	Remote_Tracking_Branch,
	Tag,
}

/* Ref_Object_Type identifies the resolved Git object category of one Ref. */
Ref_Object_Type :: enum u8 {
	Invalid,
	Commit,
	Tag,
	Tree,
	Blob,
}

/* Ref_Identity binds one exact complete Git ref to one immutable observation. */
Ref_Identity :: struct {
	repository:  Repository_Context,
	generation:  Ref_Generation,
	kind:        Ref_Kind,
	name:        Ref_Name,
	object:      Revision_Identity,
	object_type: Ref_Object_Type,
}

/* Remote_Identity binds one configured remote name to one immutable observation. */
Remote_Identity :: struct {
	repository: Repository_Context,
	generation: Ref_Generation,
	name:       Remote_Name,
}

/* Head_State distinguishes symbolic, detached, and unborn repository HEAD state. */
Head_State :: enum u8 {
	Invalid,
	Unborn,
	Symbolic,
	Detached,
}

/* Head_Observation records one checked symbolic or detached HEAD identity. */
Head_Observation :: struct {
	state:  Head_State,
	branch: Ref_Identity,
	object: Revision_Identity,
}

/* Tracking_State identifies one observed ahead and behind relationship. */
Tracking_State :: enum u8 {
	Invalid,
	Missing,
	Equal,
	Ahead,
	Behind,
	Diverged,
	Unavailable,
}

/* Tracking_Relationship binds one local branch to one observed upstream state. */
Tracking_Relationship :: struct {
	local:    Ref_Identity,
	upstream: Ref_Identity,
	state:    Tracking_State,
	ahead:    u32,
	behind:   u32,
}

/* Ref_Limits bounds one parsed Ref observation and its temporary parser work. */
Ref_Limits :: struct {
	entries:         u32,
	remotes:         u32,
	metadata_bytes:  u64,
	temporary_bytes: u64,
}

/* DEFAULT_REF_LIMITS selects the measured initial Ref resource envelope. */
DEFAULT_REF_LIMITS :: Ref_Limits {
	entries = DEFAULT_REF_ENTRIES,
	remotes = DEFAULT_REMOTE_ENTRIES,
	metadata_bytes = DEFAULT_REF_METADATA_BYTES,
	temporary_bytes = DEFAULT_REF_TEMPORARY_BYTES,
}

/* Ref_Request describes one bounded complete Ref observation. */
Ref_Request :: struct {
	limits: Ref_Limits,
}

/* Ref_Observation_State distinguishes unborn, complete, and truncated Ref observations. */
Ref_Observation_State :: enum u8 {
	Invalid,
	Unborn,
	Available,
	Truncated,
}

/* Ref_Observation owns one parsed immutable Ref result. */
Ref_Observation :: struct {
	state: rawptr,
}

/* Ref_Observation_Descriptor reports one bounded immutable Ref summary. */
Ref_Observation_Descriptor :: struct {
	repository:               Repository_Context,
	generation:               Ref_Generation,
	state:                    Ref_Observation_State,
	head:                     Head_Observation,
	local_branch_count:       u32,
	remote_tracking_count:    u32,
	tag_count:                u32,
	remote_count:             u32,
	tracking_relationships:   u32,
	metadata_bytes:           u64,
	temporary_bytes:          u64,
}

/* Ref_Item_Kind distinguishes the selectable semantic Ref surface rows. */
Ref_Item_Kind :: enum u8 {
	Invalid,
	Head,
	Ref,
	Remote,
}

/* Ref_Item_ID identifies one semantic Ref surface object without rendered-row authority. */
Ref_Item_ID :: struct {
	kind:   Ref_Item_Kind,
	reference: Ref_Identity,
	remote: Remote_Identity,
}

/* Ref_Selection owns Ref surface navigation and one optional exact marked ref. */
Ref_Selection :: struct {
	generation: Ref_Generation,
	current:    Ref_Item_ID,
	marked:     Ref_Identity,
}

/* Ref_Usage reports exact retained Ref observation ownership. */
Ref_Usage :: struct {
	entries:               u32,
	local_branches:        u32,
	remote_tracking:       u32,
	tags:                  u32,
	remotes:               u32,
	tracking_relationships: u32,
	metadata_bytes:        u64,
	temporary_bytes:       u64,
	allocation_bytes:      u64,
}

/* ref_name_assign copies one complete bounded Git ref name. */
ref_name_assign :: proc(name: ^Ref_Name, text: string) -> bool {
	if name == nil do return false
	name^ = {}
	if !ref_name_text_is_valid(text) do return false
	copy(name.bytes[:len(text)], transmute([]u8)text)
	name.length = u16(len(text))
	return true
}

/* ref_name_is_valid checks one copied complete Git ref name. */
ref_name_is_valid :: proc(name: Ref_Name) -> bool {
	if name.length == 0 || int(name.length) > len(name.bytes) do return false
	copy := name
	for index in 0 ..< int(copy.length) {
		if copy.bytes[index] == 0 || copy.bytes[index] == '\n' || copy.bytes[index] == '\r' do return false
	}
	return true
}

/* ref_name_string returns one borrowed complete checked Git ref name. */
ref_name_string :: proc(name: ^Ref_Name) -> string {
	if name == nil || !ref_name_is_valid(name^) do return ""
	return string(name.bytes[:int(name.length)])
}

/* remote_name_assign copies one bounded configured remote name. */
remote_name_assign :: proc(name: ^Remote_Name, text: string) -> bool {
	if name == nil do return false
	name^ = {}
	if !remote_name_text_is_valid(text) do return false
	copy(name.bytes[:len(text)], transmute([]u8)text)
	name.length = u16(len(text))
	return true
}

/* remote_name_is_valid checks one copied configured remote name. */
remote_name_is_valid :: proc(name: Remote_Name) -> bool {
	if name.length == 0 || int(name.length) > len(name.bytes) do return false
	copy := name
	for index in 0 ..< int(copy.length) {
		if copy.bytes[index] == 0 || copy.bytes[index] == '\n' || copy.bytes[index] == '\r' do return false
	}
	return true
}

/* remote_name_string returns one borrowed checked configured remote name. */
remote_name_string :: proc(name: ^Remote_Name) -> string {
	if name == nil || !remote_name_is_valid(name^) do return ""
	return string(name.bytes[:int(name.length)])
}

/* ref_identity_is_valid checks one complete exact observation-bound Git ref. */
ref_identity_is_valid :: proc(identity: Ref_Identity) -> bool {
	if !repository_context_is_valid(identity.repository) || identity.generation == Ref_Generation(0) ||
	   !ref_name_is_valid(identity.name) || !revision_identity_is_valid(identity.object) {
		return false
	}
	copy := identity
	text := ref_name_string(&copy.name)
	switch identity.kind {
	case .Local_Branch:
		return ref_name_has_prefix(text, "refs/heads/") && identity.object_type == .Commit
	case .Remote_Tracking_Branch:
		return ref_name_has_prefix(text, "refs/remotes/") && identity.object_type == .Commit
	case .Tag:
		return ref_name_has_prefix(text, "refs/tags/") && identity.object_type != .Invalid
	case .Invalid:
		return false
	}
	return false
}

/* remote_identity_is_valid checks one exact configured remote identity. */
remote_identity_is_valid :: proc(identity: Remote_Identity) -> bool {
	return repository_context_is_valid(identity.repository) && identity.generation != Ref_Generation(0) &&
	       remote_name_is_valid(identity.name)
}

/* head_observation_is_valid checks one complete symbolic, detached, or unborn HEAD state. */
head_observation_is_valid :: proc(head: Head_Observation) -> bool {
	switch head.state {
	case .Unborn:
		return head.branch == {} && head.object == {}
	case .Symbolic:
		return ref_identity_is_valid(head.branch) && head.branch.kind == .Local_Branch &&
		       revision_identity_is_valid(head.object) && head.object == head.branch.object
	case .Detached:
		return head.branch == {} && revision_identity_is_valid(head.object)
	case .Invalid:
		return false
	}
	return false
}

/* tracking_relationship_is_valid checks one exact local and remote-tracking relationship. */
tracking_relationship_is_valid :: proc(relationship: Tracking_Relationship) -> bool {
	if !ref_identity_is_valid(relationship.local) || relationship.local.kind != .Local_Branch {
		return false
	}
	if relationship.state == .Missing || relationship.state == .Unavailable {
		return relationship.upstream == {} && relationship.ahead == 0 && relationship.behind == 0
	}
	if !ref_identity_is_valid(relationship.upstream) || relationship.upstream.kind != .Remote_Tracking_Branch ||
	   relationship.local.repository != relationship.upstream.repository ||
	   relationship.local.generation != relationship.upstream.generation {
		return false
	}
	switch relationship.state {
	case .Equal:
		return relationship.ahead == 0 && relationship.behind == 0
	case .Ahead:
		return relationship.ahead > 0 && relationship.behind == 0
	case .Behind:
		return relationship.ahead == 0 && relationship.behind > 0
	case .Diverged:
		return relationship.ahead > 0 && relationship.behind > 0
	case .Invalid, .Missing, .Unavailable:
		return false
	}
	return false
}

/* ref_limits_are_valid checks the complete selected Ref resource envelope. */
ref_limits_are_valid :: proc(limits: Ref_Limits) -> bool {
	return limits.entries >= MIN_REF_ENTRIES && limits.entries <= MAX_REF_ENTRIES &&
	       limits.remotes <= MAX_REMOTE_ENTRIES &&
	       limits.metadata_bytes >= MIN_REF_METADATA_BYTES && limits.metadata_bytes <= MAX_REF_METADATA_BYTES &&
	       limits.temporary_bytes >= MIN_REF_TEMPORARY_BYTES && limits.temporary_bytes <= MAX_REF_TEMPORARY_BYTES &&
	       limits.metadata_bytes <= limits.temporary_bytes
}

/* ref_request_is_valid admits one bounded Ref observation request. */
ref_request_is_valid :: proc(request: Ref_Request) -> bool {
	return ref_limits_are_valid(request.limits)
}

/* ref_observation_descriptor_is_valid checks one immutable bounded Ref summary. */
ref_observation_descriptor_is_valid :: proc(
	descriptor: Ref_Observation_Descriptor,
	limits := DEFAULT_REF_LIMITS,
) -> bool {
	if !repository_context_is_valid(descriptor.repository) || descriptor.generation == Ref_Generation(0) ||
	   !ref_limits_are_valid(limits) {
		return false
	}
	entries := descriptor.local_branch_count + descriptor.remote_tracking_count + descriptor.tag_count
	if entries < descriptor.local_branch_count || entries < descriptor.remote_tracking_count || entries < descriptor.tag_count {
		return false
	}
	switch descriptor.state {
	case .Unborn:
		return descriptor.head.state == .Unborn && entries == 0 && descriptor.remote_count <= limits.remotes &&
		       descriptor.tracking_relationships == 0 && descriptor.metadata_bytes == 0 &&
		       descriptor.temporary_bytes <= limits.temporary_bytes
	case .Available, .Truncated:
		return head_observation_is_valid(descriptor.head) && descriptor.head.state != .Unborn &&
		       entries <= limits.entries && descriptor.remote_count <= limits.remotes &&
		       descriptor.tracking_relationships <= descriptor.local_branch_count &&
		       descriptor.metadata_bytes <= limits.metadata_bytes && descriptor.temporary_bytes <= limits.temporary_bytes
	case .Invalid:
		return false
	}
	return false
}

/* ref_item_id_is_valid checks one semantic Ref surface row identity. */
ref_item_id_is_valid :: proc(item: Ref_Item_ID) -> bool {
	switch item.kind {
	case .Head:
		return ref_identity_is_valid(item.reference) && item.reference.kind == .Local_Branch && item.remote == {}
	case .Ref:
		return ref_identity_is_valid(item.reference) && item.remote == {}
	case .Remote:
		return item.reference == {} && remote_identity_is_valid(item.remote)
	case .Invalid:
		return false
	}
	return false
}

/* ref_selection_is_valid checks session-local Ref selection ownership without a live observation. */
ref_selection_is_valid :: proc(selection: Ref_Selection) -> bool {
	if selection.generation == Ref_Generation(0) do return false
	if selection.current != {} &&
	   (!ref_item_id_is_valid(selection.current) ||
	    (selection.current.reference != {} && selection.current.reference.generation != selection.generation) ||
	    (selection.current.remote != {} && selection.current.remote.generation != selection.generation)) {
		return false
	}
	return selection.marked == {} ||
	       (ref_identity_is_valid(selection.marked) && selection.marked.generation == selection.generation)
}

/* ref_usage_is_valid checks retained Ref ownership against one admitted observation summary. */
ref_usage_is_valid :: proc(
	usage: Ref_Usage,
	descriptor: Ref_Observation_Descriptor,
	limits := DEFAULT_REF_LIMITS,
) -> bool {
	if !ref_observation_descriptor_is_valid(descriptor, limits) || usage.entries != descriptor.local_branch_count +
	   descriptor.remote_tracking_count + descriptor.tag_count || usage.local_branches != descriptor.local_branch_count ||
	   usage.remote_tracking != descriptor.remote_tracking_count || usage.tags != descriptor.tag_count ||
	   usage.remotes != descriptor.remote_count || usage.tracking_relationships != descriptor.tracking_relationships {
		return false
	}
	return usage.metadata_bytes == descriptor.metadata_bytes && usage.temporary_bytes == descriptor.temporary_bytes &&
	       usage.allocation_bytes >= usage.metadata_bytes
}

@(private)
ref_name_text_is_valid :: proc(text: string) -> bool {
	return len(text) > 0 && len(text) <= MAX_REF_NAME_BYTES && strings.index_byte(text, 0) < 0 &&
	       strings.index_byte(text, '\n') < 0 && strings.index_byte(text, '\r') < 0 &&
	       ref_name_has_prefix(text, "refs/")
}

@(private)
remote_name_text_is_valid :: proc(text: string) -> bool {
	return len(text) > 0 && len(text) <= MAX_REMOTE_NAME_BYTES && strings.index_byte(text, 0) < 0 &&
	       strings.index_byte(text, '\n') < 0 && strings.index_byte(text, '\r') < 0
}

@(private)
ref_name_has_prefix :: proc(text, prefix: string) -> bool {
	return len(text) > len(prefix) && len(text) >= len(prefix) && text[:len(prefix)] == prefix
}
