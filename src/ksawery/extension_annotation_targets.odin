// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

/* extension_annotation_target_from_path copies one exact Status path identity. */
extension_annotation_target_from_path :: proc(
	observation: Extension_Annotation_Observation,
	path: Path_Target,
) -> (Extension_Annotation_Target, bool) {
	if !extension_annotation_target_observation_matches(observation, .Status, u64(path.generation)) ||
	   !path_target_is_valid(path) {
		return {}, false
	}
	identity: [4]u8
	extension_annotation_u32_encode(identity[:], u32(path.path))
	return extension_annotation_target_copy(.Path, observation.generation, identity[:])
}

/* extension_annotation_target_from_diff_unit copies one exact semantic hunk identity. */
extension_annotation_target_from_diff_unit :: proc(
	observation: Extension_Annotation_Observation,
	unit: Diff_Unit_Target,
) -> (Extension_Annotation_Target, bool) {
	if !extension_annotation_target_observation_matches(observation, .Status, u64(unit.path.generation)) ||
	   !diff_unit_target_is_valid(unit) {
		return {}, false
	}
	identity: [17]u8
	extension_annotation_u32_encode(identity[0:4], u32(unit.path.path))
	extension_annotation_u64_encode(identity[4:12], u64(unit.source))
	identity[12] = u8(unit.layer)
	extension_annotation_u32_encode(identity[13:17], u32(unit.unit))
	return extension_annotation_target_copy(.Diff_Unit, observation.generation, identity[:])
}

/* extension_annotation_target_from_revision copies one exact History revision identity. */
extension_annotation_target_from_revision :: proc(
	observation: Extension_Annotation_Observation,
	revision: History_Target,
) -> (Extension_Annotation_Target, bool) {
	if !extension_annotation_target_observation_matches(observation, .History, u64(revision.generation)) ||
	   !history_target_is_valid(revision) {
		return {}, false
	}
	copy_value := revision.revision
	return extension_annotation_target_copy(
		.Revision,
		observation.generation,
		copy_value.bytes[:copy_value.length],
	)
}

/* extension_annotation_target_from_revision_range copies one exact ordered History range. */
extension_annotation_target_from_revision_range :: proc(
	observation: Extension_Annotation_Observation,
	revision_range: Revision_Range,
) -> (Extension_Annotation_Target, bool) {
	if !revision_range_is_valid(revision_range) ||
	   !extension_annotation_target_observation_matches(
		observation,
		.History,
		u64(revision_range.base.generation),
	) {
		return {}, false
	}
	base, target := revision_range.base.revision, revision_range.target.revision
	identity: [2 * MAX_REVISION_ID_BYTES + 2]u8
	identity[0] = base.length
	copy(identity[1:1 + int(base.length)], base.bytes[:base.length])
	cursor := 1 + int(base.length)
	identity[cursor] = target.length
	cursor += 1
	copy(identity[cursor:cursor + int(target.length)], target.bytes[:target.length])
	cursor += int(target.length)
	return extension_annotation_target_copy(.Revision_Range, observation.generation, identity[:cursor])
}

/* extension_annotation_target_from_ref copies one exact repository-bound Ref identity. */
extension_annotation_target_from_ref :: proc(
	observation: Extension_Annotation_Observation,
	reference: Ref_Identity,
) -> (Extension_Annotation_Target, bool) {
	if !ref_identity_is_valid(reference) || observation.repository != reference.repository ||
	   !extension_annotation_target_observation_matches(observation, .Refs, u64(reference.generation)) {
		return {}, false
	}
	name, object := reference.name, reference.object
	identity: [MAX_REF_NAME_BYTES + MAX_REVISION_ID_BYTES + 5]u8
	identity[0] = u8(reference.kind)
	extension_annotation_u16_encode(identity[1:3], name.length)
	copy(identity[3:3 + int(name.length)], name.bytes[:name.length])
	cursor := 3 + int(name.length)
	identity[cursor] = u8(reference.object_type)
	identity[cursor + 1] = object.length
	cursor += 2
	copy(identity[cursor:cursor + int(object.length)], object.bytes[:object.length])
	cursor += int(object.length)
	return extension_annotation_target_copy(.Ref, observation.generation, identity[:cursor])
}

/* extension_annotation_target_from_remote copies one exact repository-bound Remote identity. */
extension_annotation_target_from_remote :: proc(
	observation: Extension_Annotation_Observation,
	remote: Remote_Identity,
) -> (Extension_Annotation_Target, bool) {
	if !remote_identity_is_valid(remote) || observation.repository != remote.repository ||
	   !extension_annotation_target_observation_matches(observation, .Refs, u64(remote.generation)) {
		return {}, false
	}
	name := remote.name
	return extension_annotation_target_copy(.Remote, observation.generation, name.bytes[:name.length])
}

/* extension_annotation_target_from_conflict copies one exact sequence-bound conflict identity. */
extension_annotation_target_from_conflict :: proc(
	observation: Extension_Annotation_Observation,
	conflict: Conflict_Target_ID,
) -> (Extension_Annotation_Target, bool) {
	if (observation.family != .Conflict && observation.family != .Sequence) ||
	   !extension_annotation_observation_is_valid(observation) ||
	   !conflict_target_id_is_valid(conflict) || observation.generation != u64(conflict.sequence.generation) {
		return {}, false
	}
	identity: [12]u8
	extension_annotation_u64_encode(identity[0:8], u64(conflict.sequence.fingerprint))
	extension_annotation_u32_encode(identity[8:12], u32(conflict.conflict))
	return extension_annotation_target_copy(.Conflict, observation.generation, identity[:])
}

/* extension_annotation_target_from_sequence copies one exact sequence fingerprint. */
extension_annotation_target_from_sequence :: proc(
	observation: Extension_Annotation_Observation,
	sequence: Sequence_Target,
) -> (Extension_Annotation_Target, bool) {
	if !extension_annotation_target_observation_matches(observation, .Sequence, u64(sequence.generation)) ||
	   !sequence_target_is_valid(sequence) {
		return {}, false
	}
	identity: [8]u8
	extension_annotation_u64_encode(identity[:], u64(sequence.fingerprint))
	return extension_annotation_target_copy(.Sequence, observation.generation, identity[:])
}

/* extension_annotation_target_from_process copies one exact immutable Process row identity. */
extension_annotation_target_from_process :: proc(
	observation: Extension_Annotation_Observation,
	row: Process_Row_Descriptor,
) -> (Extension_Annotation_Target, bool) {
	if !extension_annotation_target_observation_matches(
		observation,
		.Process,
		observation.generation,
	) || row.id.operation == Repository_Operation_ID(0) ||
	   row.id.generation == Process_Record_Generation(0) || !repository_context_is_valid(row.repository) ||
	   row.repository != observation.repository {
		return {}, false
	}
	identity: [16]u8
	extension_annotation_u64_encode(identity[0:8], u64(row.id.operation))
	extension_annotation_u64_encode(identity[8:16], u64(row.id.generation))
	return extension_annotation_target_copy(.Process, observation.generation, identity[:])
}

@(private)
extension_annotation_target_observation_matches :: proc(
	observation: Extension_Annotation_Observation,
	family: Extension_Observation_Family,
	generation: u64,
) -> bool {
	return extension_annotation_observation_is_valid(observation) && observation.family == family &&
		observation.generation == generation
}

@(private)
extension_annotation_target_copy :: proc(
	family: Extension_Annotation_Target_Family,
	generation: u64,
	identity: []u8,
) -> (target: Extension_Annotation_Target, ok: bool) {
	ok = extension_annotation_target_assign(&target, family, generation, identity)
	return
}

@(private)
extension_annotation_u16_encode :: proc(destination: []u8, value: u16) {
	if len(destination) < 2 do return
	destination[0] = u8(value >> 8)
	destination[1] = u8(value)
}

@(private)
extension_annotation_u32_encode :: proc(destination: []u8, value: u32) {
	if len(destination) < 4 do return
	for index in 0 ..< 4 do destination[index] = u8(value >> u32((3 - index) * 8))
}

@(private)
extension_annotation_u64_encode :: proc(destination: []u8, value: u64) {
	if len(destination) < 8 do return
	for index in 0 ..< 8 do destination[index] = u8(value >> u64((7 - index) * 8))
}
