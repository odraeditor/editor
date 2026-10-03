// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_extension_focused

import ksawery "../../src/ksawery"
import "core:testing"

annotation_target_test_repository :: proc() -> ksawery.Repository_Context {
	repository: ksawery.Repository_Context
	_ = ksawery.repository_context_assign(&repository, "/tmp/odra-ksawery-annotation-targets")
	return repository
}

annotation_target_test_revision :: proc(fill: u8) -> ksawery.Revision_Identity {
	identity: ksawery.Revision_Identity
	text: [40]u8
	for &byte in text do byte = fill
	_ = ksawery.revision_identity_assign(&identity, string(text[:]))
	return identity
}

/* Verifies Status path and diff-unit targets preserve exact native identities. */
@(test)
extension_annotation_maps_status_targets :: proc(t: ^testing.T) {
	observation := ksawery.Extension_Annotation_Observation {
		family = .Status,
		repository = annotation_target_test_repository(),
		generation = 7,
	}
	path := ksawery.Path_Target{generation = 7, path = 3}
	path_target, path_ready := ksawery.extension_annotation_target_from_path(observation, path)
	testing.expect(t, path_ready && ksawery.extension_annotation_target_is_valid(path_target))
	testing.expect_value(t, path_target.family, ksawery.Extension_Annotation_Target_Family.Path)
	unit := ksawery.Diff_Unit_Target {
		path = path,
		source = 11,
		layer = .Index,
		unit = 13,
	}
	unit_target, unit_ready := ksawery.extension_annotation_target_from_diff_unit(observation, unit)
	testing.expect(t, unit_ready && ksawery.extension_annotation_target_is_valid(unit_target))
	testing.expect_value(t, unit_target.family, ksawery.Extension_Annotation_Target_Family.Diff_Unit)
	testing.expect(t, path_target != unit_target)
	stale := observation
	stale.generation += 1
	_, path_ready = ksawery.extension_annotation_target_from_path(stale, path)
	testing.expect(t, !path_ready)
}

/* Verifies History revisions and ordered ranges copy full object identities. */
@(test)
extension_annotation_maps_history_targets :: proc(t: ^testing.T) {
	observation := ksawery.Extension_Annotation_Observation {
		family = .History,
		repository = annotation_target_test_repository(),
		generation = 17,
	}
	base := annotation_target_test_revision('a')
	target := annotation_target_test_revision('b')
	revision_target, revision_ready := ksawery.extension_annotation_target_from_revision(
		observation,
		{generation = 17, revision = target},
	)
	testing.expect(t, revision_ready && ksawery.extension_annotation_target_is_valid(revision_target))
	range_target, range_ready := ksawery.extension_annotation_target_from_revision_range(
		observation,
		{
			base = {generation = 17, revision = base},
			target = {generation = 17, revision = target},
		},
	)
	testing.expect(t, range_ready && ksawery.extension_annotation_target_is_valid(range_target))
	testing.expect_value(t, range_target.family, ksawery.Extension_Annotation_Target_Family.Revision_Range)
	testing.expect(t, revision_target != range_target)
}

/* Verifies Ref and Remote targets retain copied names and reject another repository. */
@(test)
extension_annotation_maps_ref_targets :: proc(t: ^testing.T) {
	repository := annotation_target_test_repository()
	observation := ksawery.Extension_Annotation_Observation{.Refs, repository, 23}
	name: ksawery.Ref_Name
	_ = ksawery.ref_name_assign(&name, "refs/heads/main")
	object := annotation_target_test_revision('c')
	reference := ksawery.Ref_Identity {
		repository = repository,
		generation = 23,
		kind = .Local_Branch,
		name = name,
		object = object,
		object_type = .Commit,
	}
	reference_target, reference_ready := ksawery.extension_annotation_target_from_ref(observation, reference)
	testing.expect(t, reference_ready && ksawery.extension_annotation_target_is_valid(reference_target))
	snapshot := reference_target
	reference.name.bytes[11] = 'x'
	testing.expect_value(t, reference_target, snapshot)
	remote_name: ksawery.Remote_Name
	_ = ksawery.remote_name_assign(&remote_name, "origin")
	remote := ksawery.Remote_Identity{repository = repository, generation = 23, name = remote_name}
	remote_target, remote_ready := ksawery.extension_annotation_target_from_remote(observation, remote)
	testing.expect(t, remote_ready && ksawery.extension_annotation_target_is_valid(remote_target))
	other_repository := repository
	other_repository.bytes[1] = 'x'
	observation.repository = other_repository
	_, remote_ready = ksawery.extension_annotation_target_from_remote(observation, remote)
	testing.expect(t, !remote_ready)
}

/* Verifies conflict, sequence, and Process records map without row coordinates. */
@(test)
extension_annotation_maps_operation_targets :: proc(t: ^testing.T) {
	repository := annotation_target_test_repository()
	sequence := ksawery.Sequence_Target{generation = 29, fingerprint = 31}
	sequence_observation := ksawery.Extension_Annotation_Observation{.Sequence, repository, 29}
	sequence_target, sequence_ready := ksawery.extension_annotation_target_from_sequence(
		sequence_observation,
		sequence,
	)
	testing.expect(t, sequence_ready && ksawery.extension_annotation_target_is_valid(sequence_target))
	conflict_target, conflict_ready := ksawery.extension_annotation_target_from_conflict(
		sequence_observation,
		{sequence = sequence, conflict = 2},
	)
	testing.expect(t, conflict_ready && ksawery.extension_annotation_target_is_valid(conflict_target))
	process_observation := ksawery.Extension_Annotation_Observation{.Process, repository, 37}
	row := ksawery.Process_Row_Descriptor {
		id = {operation = 41, generation = 43},
		repository = repository,
		observation_generation = 37,
	}
	process_target, process_ready := ksawery.extension_annotation_target_from_process(process_observation, row)
	testing.expect(t, process_ready && ksawery.extension_annotation_target_is_valid(process_target))
	testing.expect(t, sequence_target != conflict_target && conflict_target != process_target)
}
