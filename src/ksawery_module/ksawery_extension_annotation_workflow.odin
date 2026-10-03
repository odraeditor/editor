// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import "../ksawery"
import "base:runtime"

/* ksawery_extension_annotations_refresh_status publishes current paths and loaded hunks. */
ksawery_extension_annotations_refresh_status :: proc(
	registry: ^Ksawery_Extension_Provider_Registry,
	host: ^Host_Context,
	status: ^ksawery.Status_Observation,
	diff: ^ksawery.Diff_Document,
	allocator: runtime.Allocator,
) -> bool {
	descriptor, described := ksawery.status_observation_descriptor(status)
	path_count, counted := ksawery.status_observation_path_count(status)
	if !described || !counted do return false
	unit_count: u32
	if diff != nil {
		if diff_descriptor, available := ksawery.diff_document_descriptor(diff); available {
			unit_count = diff_descriptor.unit_count
		}
	}
	targets, allocation_error := make(
		[]ksawery.Extension_Annotation_Target,
		int(path_count + unit_count),
		allocator,
	)
	if allocation_error != nil do return false
	defer delete(targets, allocator)
	observation := ksawery.Extension_Annotation_Observation {
		family = .Status,
		repository = descriptor.repository,
		generation = u64(descriptor.generation),
	}
	write := 0
	for ordinal in 0 ..< path_count {
		path, found := ksawery.status_observation_path(status, ordinal)
		if !found do return false
		target, mapped := ksawery.extension_annotation_target_from_path(
			observation,
			{generation = descriptor.generation, path = path.id},
		)
		if !mapped do return false
		targets[write] = target
		write += 1
	}
	if diff != nil {
		for ordinal in 0 ..< unit_count {
			unit, found := ksawery.diff_document_unit(diff, ordinal)
			if !found do return false
			target, mapped := ksawery.extension_annotation_target_from_diff_unit(
				observation, unit.target,
			)
			if !mapped do return false
			targets[write] = target
			write += 1
		}
	}
	return ksawery_extension_annotation_refresh(
		registry, host, observation, targets[:write], allocator,
	)
}

/* ksawery_extension_annotations_refresh_history publishes current revision identities. */
ksawery_extension_annotations_refresh_history :: proc(
	registry: ^Ksawery_Extension_Provider_Registry,
	host: ^Host_Context,
	history: ^ksawery.History_Observation,
	allocator: runtime.Allocator,
) -> bool {
	descriptor, described := ksawery.history_observation_descriptor(history)
	count, counted := ksawery.history_observation_revision_count(history)
	if !described || !counted do return false
	targets, allocation_error := make([]ksawery.Extension_Annotation_Target, int(count), allocator)
	if allocation_error != nil do return false
	defer delete(targets, allocator)
	observation := ksawery.Extension_Annotation_Observation {
		family = .History,
		repository = descriptor.repository,
		generation = u64(descriptor.generation),
	}
	for ordinal in 0 ..< count {
		revision, found := ksawery.history_observation_revision(history, ordinal)
		if !found do return false
		target, mapped := ksawery.extension_annotation_target_from_revision(
			observation,
			{generation = descriptor.generation, revision = revision.identity},
		)
		if !mapped do return false
		targets[ordinal] = target
	}
	return ksawery_extension_annotation_refresh(
		registry, host, observation, targets, allocator,
	)
}

/* ksawery_extension_annotations_refresh_refs publishes current Ref and Remote identities. */
ksawery_extension_annotations_refresh_refs :: proc(
	registry: ^Ksawery_Extension_Provider_Registry,
	host: ^Host_Context,
	refs: ^ksawery.Ref_Observation,
	allocator: runtime.Allocator,
) -> bool {
	descriptor, described := ksawery.ref_observation_descriptor(refs)
	ref_count, refs_counted := ksawery.ref_observation_ref_count(refs)
	remote_count, remotes_counted := ksawery.ref_observation_remote_count(refs)
	if !described || !refs_counted || !remotes_counted do return false
	targets, allocation_error := make(
		[]ksawery.Extension_Annotation_Target,
		int(ref_count + remote_count),
		allocator,
	)
	if allocation_error != nil do return false
	defer delete(targets, allocator)
	observation := ksawery.Extension_Annotation_Observation {
		family = .Refs,
		repository = descriptor.repository,
		generation = u64(descriptor.generation),
	}
	write := 0
	for ordinal in 0 ..< ref_count {
		reference, found := ksawery.ref_observation_ref(refs, ordinal)
		if !found do return false
		target, mapped := ksawery.extension_annotation_target_from_ref(observation, reference)
		if !mapped do return false
		targets[write] = target
		write += 1
	}
	for ordinal in 0 ..< remote_count {
		remote, found := ksawery.ref_observation_remote(refs, ordinal)
		if !found do return false
		target, mapped := ksawery.extension_annotation_target_from_remote(observation, remote)
		if !mapped do return false
		targets[write] = target
		write += 1
	}
	return ksawery_extension_annotation_refresh(
		registry, host, observation, targets[:write], allocator,
	)
}

/* ksawery_extension_annotations_refresh_sequence publishes sequence and conflict families. */
ksawery_extension_annotations_refresh_sequence :: proc(
	registry: ^Ksawery_Extension_Provider_Registry,
	host: ^Host_Context,
	sequence: ^ksawery.Sequence_Observation,
	allocator: runtime.Allocator,
) -> bool {
	descriptor, described := ksawery.sequence_observation_descriptor(sequence)
	conflict_count, counted := ksawery.sequence_observation_conflict_count(sequence)
	if !described || !counted do return false
	sequence_observation := ksawery.Extension_Annotation_Observation {
		family = .Sequence,
		repository = descriptor.repository,
		generation = u64(descriptor.generation),
	}
	sequence_targets: [1]ksawery.Extension_Annotation_Target
	sequence_target_count := 0
	sequence_target := ksawery.Sequence_Target {
		generation = descriptor.generation,
		fingerprint = descriptor.fingerprint,
	}
	if target, mapped := ksawery.extension_annotation_target_from_sequence(
		sequence_observation, sequence_target,
	); mapped {
		sequence_targets[0] = target
		sequence_target_count = 1
	}
	sequence_published := ksawery_extension_annotation_refresh(
		registry,
		host,
		sequence_observation,
		sequence_targets[:sequence_target_count],
		allocator,
	)
	conflict_targets, allocation_error := make(
		[]ksawery.Extension_Annotation_Target, int(conflict_count), allocator,
	)
	if allocation_error != nil do return false
	defer delete(conflict_targets, allocator)
	conflict_observation := sequence_observation
	conflict_observation.family = .Conflict
	for ordinal in 0 ..< conflict_count {
		conflict, found := ksawery.sequence_observation_conflict(sequence, ordinal)
		if !found do return false
		target, mapped := ksawery.extension_annotation_target_from_conflict(
			conflict_observation,
			{sequence = sequence_target, conflict = conflict.id},
		)
		if !mapped do return false
		conflict_targets[ordinal] = target
	}
	conflict_published := ksawery_extension_annotation_refresh(
		registry, host, conflict_observation, conflict_targets, allocator,
	)
	return sequence_published && conflict_published
}

/* ksawery_extension_annotations_refresh_process publishes one stable Process surface snapshot. */
ksawery_extension_annotations_refresh_process :: proc(
	registry: ^Ksawery_Extension_Provider_Registry,
	host: ^Host_Context,
	repository: ksawery.Repository_Context,
	records: []ksawery.Process_Record,
	allocator: runtime.Allocator,
) -> bool {
	surface, described := ksawery.process_surface_descriptor(records)
	if !described do return false
	generation := ksawery_extension_process_annotation_generation(records)
	observation := ksawery.Extension_Annotation_Observation {
		family = .Process,
		repository = repository,
		generation = generation,
	}
	targets, allocation_error := make(
		[]ksawery.Extension_Annotation_Target, int(surface.row_count), allocator,
	)
	if allocation_error != nil do return false
	defer delete(targets, allocator)
	for ordinal in 0 ..< surface.row_count {
		row, projected, _ := ksawery.process_surface_row(records, ordinal)
		if !projected do return false
		target, mapped := ksawery.extension_annotation_target_from_process(observation, row)
		if !mapped do return false
		targets[ordinal] = target
	}
	return ksawery_extension_annotation_refresh(
		registry, host, observation, targets, allocator,
	)
}

@(private)
ksawery_extension_process_annotation_generation :: proc(records: []ksawery.Process_Record) -> u64 {
	hash := u64(14_695_981_039_346_656_037)
	for &record in records {
		descriptor, described := ksawery.process_record_descriptor(&record)
		if !described do continue
		hash = (hash ~ u64(descriptor.operation)) * 1_099_511_628_211
		hash = (hash ~ u64(descriptor.generation)) * 1_099_511_628_211
	}
	if hash == 0 do hash = 1
	return hash
}
