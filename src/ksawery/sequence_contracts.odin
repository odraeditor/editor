// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

/* MIN_SEQUENCE_CONFLICTS is the smallest admitted retained conflict capacity. */
MIN_SEQUENCE_CONFLICTS :: u32(1)
/* MAX_SEQUENCE_CONFLICTS is the immutable retained conflict capacity ceiling. */
MAX_SEQUENCE_CONFLICTS :: u32(16_384)
/* DEFAULT_SEQUENCE_CONFLICTS is the measured initial retained conflict capacity. */
DEFAULT_SEQUENCE_CONFLICTS :: u32(1_024)
/* MIN_SEQUENCE_PATH_BYTES is the smallest admitted aggregate conflict-path budget. */
MIN_SEQUENCE_PATH_BYTES :: u64(4 * KIBIBYTE)
/* MAX_SEQUENCE_PATH_BYTES is the immutable aggregate conflict-path ceiling. */
MAX_SEQUENCE_PATH_BYTES :: u64(4 * MEBIBYTE)
/* DEFAULT_SEQUENCE_PATH_BYTES is the measured initial conflict-path budget. */
DEFAULT_SEQUENCE_PATH_BYTES :: u64(256 * KIBIBYTE)
/* MIN_SEQUENCE_METADATA_BYTES is the smallest admitted sequence metadata budget. */
MIN_SEQUENCE_METADATA_BYTES :: u64(1 * KIBIBYTE)
/* MAX_SEQUENCE_METADATA_BYTES is the immutable sequence metadata ceiling. */
MAX_SEQUENCE_METADATA_BYTES :: u64(512 * KIBIBYTE)
/* DEFAULT_SEQUENCE_METADATA_BYTES is the measured initial sequence metadata budget. */
DEFAULT_SEQUENCE_METADATA_BYTES :: u64(64 * KIBIBYTE)
/* MIN_SEQUENCE_TEMPORARY_BYTES is the smallest admitted parser input budget. */
MIN_SEQUENCE_TEMPORARY_BYTES :: u64(64 * KIBIBYTE)
/* MAX_SEQUENCE_TEMPORARY_BYTES is the immutable parser input ceiling. */
MAX_SEQUENCE_TEMPORARY_BYTES :: u64(16 * MEBIBYTE)
/* DEFAULT_SEQUENCE_TEMPORARY_BYTES is the measured initial parser input budget. */
DEFAULT_SEQUENCE_TEMPORARY_BYTES :: u64(2 * MEBIBYTE)

/* Sequence_Generation identifies one immutable repository sequence observation. */
Sequence_Generation :: distinct u64
/* Sequence_Fingerprint identifies one observed sequence shape without positional authority. */
Sequence_Fingerprint :: distinct u64
/* Conflict_ID identifies one semantic conflict target inside one sequence observation. */
Conflict_ID :: distinct u32

/* Sequence_Kind identifies the observed Git sequencer family. */
Sequence_Kind :: enum u8 {
	Invalid,
	None,
	Merge,
	Rebase,
	Cherry_Pick,
	Revert,
	Bisect,
	Apply_Patches,
	Other,
}

/* Sequence_Origin distinguishes an externally adopted sequence from one associated with Odra. */
Sequence_Origin :: enum u8 {
	Invalid,
	External,
	Associated,
}

/* Sequence_Observation_State distinguishes inactive, usable, unsupported, and bounded results. */
Sequence_Observation_State :: enum u8 {
	Invalid,
	Inactive,
	Active,
	Conflicted,
	Unsupported,
	Truncated,
}

/* Sequence_Step reports exact progress only when both position and total are known. */
Sequence_Step :: struct {
	position: u32,
	total:    u32,
}

/* Conflict_Kind classifies the porcelain-v2 unmerged index pair. */
Conflict_Kind :: enum u8 {
	Invalid,
	Both_Modified,
	Added_By_Both,
	Deleted_By_Us,
	Deleted_By_Them,
	Added_By_Us,
	Added_By_Them,
	Both_Deleted,
	Other,
}

/* Conflict_Index_Stage_Kind identifies the three immutable unmerged index stages. */
Conflict_Index_Stage_Kind :: enum u8 {
	Invalid,
	Base,
	Current,
	Applied,
}

/* Conflict_Index_Stage reports one available object and mode from the Git index. */
Conflict_Index_Stage :: struct {
	kind:      Conflict_Index_Stage_Kind,
	available: bool,
	mode:      u32,
	object:    Revision_Identity,
}

/* Conflict_Target binds one copied conflict path and its exact index-stage identities. */
Conflict_Target :: struct {
	id:     Conflict_ID,
	path:   Path_Text_Ref,
	kind:   Conflict_Kind,
	index:  u8,
	worktree: u8,
	stages: [3]Conflict_Index_Stage,
}

/* Sequence_Action_Availability exposes only the read-only actions delivered by this slice. */
Sequence_Action_Availability :: struct {
	inspect:          bool,
	refresh:          bool,
	return_to_status: bool,
}

/* Sequence_Limits bounds retained conflicts, copied paths, metadata, and parser input. */
Sequence_Limits :: struct {
	conflicts:       u32,
	path_bytes:      u64,
	metadata_bytes:  u64,
	temporary_bytes: u64,
}

/* DEFAULT_SEQUENCE_LIMITS selects the measured initial sequence observation envelope. */
DEFAULT_SEQUENCE_LIMITS :: Sequence_Limits {
	conflicts = DEFAULT_SEQUENCE_CONFLICTS,
	path_bytes = DEFAULT_SEQUENCE_PATH_BYTES,
	metadata_bytes = DEFAULT_SEQUENCE_METADATA_BYTES,
	temporary_bytes = DEFAULT_SEQUENCE_TEMPORARY_BYTES,
}

/* Sequence_Source is the bounded marker snapshot paired with porcelain-v2 status output. */
Sequence_Source :: struct {
	kind:           Sequence_Kind,
	origin:         Sequence_Origin,
	marker_mask:    u16,
	current:        Revision_Identity,
	target:         Revision_Identity,
	step:           Sequence_Step,
	metadata_bytes: u64,
	supported:      bool,
}

/* Sequence_Request describes one bounded complete repository sequence observation. */
Sequence_Request :: struct {
	limits: Sequence_Limits,
}

/* Sequence_Observation owns one parsed immutable sequence result. */
Sequence_Observation :: struct {
	state: rawptr,
}

/* Sequence_Observation_Descriptor reports one bounded immutable sequence summary. */
Sequence_Observation_Descriptor :: struct {
	repository:         Repository_Context,
	generation:         Sequence_Generation,
	state:              Sequence_Observation_State,
	kind:               Sequence_Kind,
	origin:             Sequence_Origin,
	fingerprint:        Sequence_Fingerprint,
	current:            Revision_Identity,
	target:             Revision_Identity,
	step:               Sequence_Step,
	conflict_count:     u32,
	observed_conflicts: u32,
	path_bytes:         u64,
	metadata_bytes:     u64,
	temporary_bytes:    u64,
	actions:            Sequence_Action_Availability,
}

/* Sequence_Target binds an exact fingerprint to one immutable observation generation. */
Sequence_Target :: struct {
	generation:  Sequence_Generation,
	fingerprint: Sequence_Fingerprint,
}

/* Conflict_Target_ID binds one conflict to one exact immutable sequence observation. */
Conflict_Target_ID :: struct {
	sequence: Sequence_Target,
	conflict: Conflict_ID,
}

/* Sequence_Usage reports exact retained sequence observation ownership. */
Sequence_Usage :: struct {
	conflicts:          u32,
	observed_conflicts: u32,
	path_bytes:         u64,
	metadata_bytes:     u64,
	temporary_bytes:    u64,
	allocation_bytes:   u64,
}

/* sequence_step_is_valid admits unknown progress or one bounded one-based step. */
sequence_step_is_valid :: proc(step: Sequence_Step) -> bool {
	return step == {} || (step.position > 0 && step.total > 0 && step.position <= step.total)
}

/* sequence_limits_are_valid checks the complete selected sequence resource envelope. */
sequence_limits_are_valid :: proc(limits: Sequence_Limits) -> bool {
	return limits.conflicts >= MIN_SEQUENCE_CONFLICTS && limits.conflicts <= MAX_SEQUENCE_CONFLICTS &&
	       limits.path_bytes >= MIN_SEQUENCE_PATH_BYTES && limits.path_bytes <= MAX_SEQUENCE_PATH_BYTES &&
	       limits.metadata_bytes >= MIN_SEQUENCE_METADATA_BYTES &&
	       limits.metadata_bytes <= MAX_SEQUENCE_METADATA_BYTES &&
	       limits.temporary_bytes >= MIN_SEQUENCE_TEMPORARY_BYTES &&
	       limits.temporary_bytes <= MAX_SEQUENCE_TEMPORARY_BYTES
}

/* sequence_request_is_valid admits only a complete bounded observation request. */
sequence_request_is_valid :: proc(request: Sequence_Request) -> bool {
	return sequence_limits_are_valid(request.limits)
}

/* sequence_source_is_valid checks one self-consistent bounded marker snapshot. */
sequence_source_is_valid :: proc(source: Sequence_Source, limits := DEFAULT_SEQUENCE_LIMITS) -> bool {
	if !sequence_limits_are_valid(limits) || source.metadata_bytes > limits.metadata_bytes ||
	   !sequence_step_is_valid(source.step) {
		return false
	}
	if source.kind == .None {
		return source.origin == .External && source.marker_mask == 0 && source.current == {} &&
		       source.target == {} && source.step == {} && source.metadata_bytes == 0 && source.supported
	}
	if source.kind == .Invalid || source.origin == .Invalid || source.marker_mask == 0 do return false
	if source.current != {} && !revision_identity_is_valid(source.current) do return false
	if source.target != {} && !revision_identity_is_valid(source.target) do return false
	return source.kind == .Other || source.supported
}

/* sequence_target_is_valid checks one exact nonzero observation identity. */
sequence_target_is_valid :: proc(target: Sequence_Target) -> bool {
	return target.generation != Sequence_Generation(0) && target.fingerprint != Sequence_Fingerprint(0)
}

/* conflict_target_id_is_valid checks one exact nonzero conflict identity. */
conflict_target_id_is_valid :: proc(target: Conflict_Target_ID) -> bool {
	return sequence_target_is_valid(target.sequence) && target.conflict != Conflict_ID(0)
}
