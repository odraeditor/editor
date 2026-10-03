// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "../project"
import "base:runtime"
import "core:strings"

/* Root_File_Candidate_Source owns borrowed-definition storage until session admission. */
Root_File_Candidate_Source :: struct {
	definition:   Candidate_Source_Definition,
	descriptors:  []Candidate_Descriptor_Definition,
	labels:       []string,
	member_paths: []string,
	fields:       []string,
	annotations:  []Candidate_Annotation_Definition,
	allocator:    runtime.Allocator,
}

/* Project_File_Candidate_Source preserves the existing Project adapter API. */
Project_File_Candidate_Source :: Root_File_Candidate_Source

/* project_file_candidate_source_build adapts one complete Project file generation. */
project_file_candidate_source_build :: proc(
	batch: ^project.File_Candidate_Batch,
	memberships: []project.Membership_Descriptor,
	allocator := context.temp_allocator,
) -> (source: Project_File_Candidate_Source, ok: bool, failure: Candidate_Failure) {
	if batch == nil {
		return {}, false, Candidate_Failure{code = .Invalid_Source}
	}
	return project_file_candidate_source_build_generation(
		batch,
		memberships,
		u64(batch.generation),
		allocator,
	)
}

/* project_file_candidate_source_build_generation assigns one monotonic replacement generation. */
project_file_candidate_source_build_generation :: proc(
	batch: ^project.File_Candidate_Batch,
	memberships: []project.Membership_Descriptor,
	source_generation: u64,
	allocator := context.temp_allocator,
) -> (source: Project_File_Candidate_Source, ok: bool, failure: Candidate_Failure) {
	if batch == nil || batch.state == nil ||
	   !project.project_handle_is_valid(batch.project) ||
	   batch.generation == project.File_Enumeration_Generation(0) ||
	   source_generation == 0 || len(memberships) == 0 || allocator.procedure == nil {
		return {}, false, Candidate_Failure{code = .Invalid_Source}
	}
	if len(batch.descriptors) > int(MAX_CANDIDATES) {
		return {}, false, Candidate_Failure {
			code = .Candidate_Limit,
			limit = u64(MAX_CANDIDATES),
			actual = u64(len(batch.descriptors)),
		}
	}
	for descriptor in memberships {
		if descriptor.handle.project != batch.project ||
		   !project.membership_handle_is_valid(descriptor.handle) {
			return {}, false, Candidate_Failure{code = .Invalid_Source}
		}
	}

	source.allocator = allocator
	allocation_error: runtime.Allocator_Error
	source.descriptors, allocation_error = make(
		[]Candidate_Descriptor_Definition,
		len(batch.descriptors),
		allocator,
	)
	if allocation_error != nil {
		project_file_candidate_source_close(&source)
		return {}, false, Candidate_Failure{code = .Persistent_Memory_Limit}
	}
	source.labels, allocation_error = make([]string, len(batch.descriptors), allocator)
	if allocation_error != nil {
		project_file_candidate_source_close(&source)
		return {}, false, Candidate_Failure{code = .Persistent_Memory_Limit}
	}
	source.member_paths, allocation_error = make([]string, len(batch.descriptors), allocator)
	if allocation_error != nil {
		project_file_candidate_source_close(&source)
		return {}, false, Candidate_Failure{code = .Persistent_Memory_Limit}
	}
	source.fields, allocation_error = make([]string, len(batch.descriptors), allocator)
	if allocation_error != nil {
		project_file_candidate_source_close(&source)
		return {}, false, Candidate_Failure{code = .Persistent_Memory_Limit}
	}
	source.annotations, allocation_error = make(
		[]Candidate_Annotation_Definition,
		len(batch.descriptors),
		allocator,
	)
	if allocation_error != nil {
		project_file_candidate_source_close(&source)
		return {}, false, Candidate_Failure{code = .Persistent_Memory_Limit}
	}

	for descriptor, index in batch.descriptors {
		if descriptor.project != batch.project || descriptor.generation != batch.generation ||
		   len(descriptor.path) == 0 {
			project_file_candidate_source_close(&source)
			return {}, false, Candidate_Failure{code = .Invalid_Source}
		}
		label, member_path, membership_count := project_file_candidate_relative_label(
			descriptor.path,
			memberships,
		)
		if len(label) == 0 || len(member_path) == 0 ||
		   membership_count != descriptor.membership_count {
			project_file_candidate_source_close(&source)
			return {}, false, Candidate_Failure{code = .Invalid_Source}
		}
		source.labels[index] = label
		source.member_paths[index] = member_path
		source.fields[index] = descriptor.path
	}

	for descriptor, index in batch.descriptors {
		annotation_count := 0
		if project_file_candidate_label_is_ambiguous(source.labels, index) {
			source.annotations[index] = Candidate_Annotation_Definition {
				kind = .Project_Member,
				text = source.member_paths[index],
			}
			annotation_count = 1
		}
		source.descriptors[index] = Candidate_Descriptor_Definition {
			identity = project_file_candidate_identity(descriptor.path),
			label = source.labels[index],
			searchable_fields = source.fields[index:index + 1],
			annotations = source.annotations[index:index + annotation_count],
			action = project_file_candidate_action(descriptor),
			availability = .Available,
			durable_category = .Project_File,
			durable_key = descriptor.path,
		}
	}
	projected_text_bytes: u64
	for definition in source.descriptors {
		projected_text_bytes += u64(len(definition.label))
		if len(definition.annotations) > 0 {
			projected_text_bytes += u64(len("  [") + len(definition.annotations[0].text) + len("]"))
		}
		if projected_text_bytes > MAX_CANDIDATE_TEXT_BYTES {
			project_file_candidate_source_close(&source)
			return {}, false, Candidate_Failure {
				code = .Text_Limit,
				limit = MAX_CANDIDATE_TEXT_BYTES,
				actual = projected_text_bytes,
			}
		}
	}
	source.definition = Candidate_Source_Definition {
		kind = .Project_Files,
		scope_identity = u64(batch.project.id),
		scope_generation = u64(batch.project.generation),
		source_generation = source_generation,
		descriptors = source.descriptors,
	}
	return source, true, {}
}

/* dir_file_candidate_source_build adapts one ordinary-Dir file generation. */
dir_file_candidate_source_build :: proc(
	batch: ^project.File_Candidate_Batch,
	root_path: string,
	allocator := context.temp_allocator,
) -> (source: Root_File_Candidate_Source, ok: bool, failure: Candidate_Failure) {
	if batch == nil {
		return {}, false, Candidate_Failure{code = .Invalid_Source}
	}
	return dir_file_candidate_source_build_generation(
		batch,
		root_path,
		u64(batch.generation),
		allocator,
	)
}

/* dir_file_candidate_source_build_generation assigns one monotonic Dir replacement generation. */
dir_file_candidate_source_build_generation :: proc(
	batch: ^project.File_Candidate_Batch,
	root_path: string,
	source_generation: u64,
	allocator := context.temp_allocator,
) -> (source: Root_File_Candidate_Source, ok: bool, failure: Candidate_Failure) {
	if batch == nil || batch.state == nil || !project.dir_handle_is_valid(batch.dir) ||
	   batch.project != (project.Project_Handle{}) || batch.generation == project.File_Enumeration_Generation(0) ||
	   source_generation == 0 || len(root_path) == 0 || allocator.procedure == nil {
		return {}, false, Candidate_Failure{code = .Invalid_Source}
	}
	if len(batch.descriptors) > int(MAX_CANDIDATES) {
		return {}, false, Candidate_Failure {
			code = .Candidate_Limit,
			limit = u64(MAX_CANDIDATES),
			actual = u64(len(batch.descriptors)),
		}
	}
	source.allocator = allocator
	allocation_error: runtime.Allocator_Error
	source.descriptors, allocation_error = make([]Candidate_Descriptor_Definition, len(batch.descriptors), allocator)
	if allocation_error != nil {
		project_file_candidate_source_close(&source)
		return {}, false, Candidate_Failure{code = .Persistent_Memory_Limit}
	}
	source.labels, allocation_error = make([]string, len(batch.descriptors), allocator)
	if allocation_error != nil {
		project_file_candidate_source_close(&source)
		return {}, false, Candidate_Failure{code = .Persistent_Memory_Limit}
	}
	source.fields, allocation_error = make([]string, len(batch.descriptors), allocator)
	if allocation_error != nil {
		project_file_candidate_source_close(&source)
		return {}, false, Candidate_Failure{code = .Persistent_Memory_Limit}
	}
	for descriptor, index in batch.descriptors {
		if descriptor.dir != batch.dir || descriptor.project != (project.Project_Handle{}) ||
		   descriptor.generation != batch.generation || descriptor.membership_count != 1 ||
		   !project_file_candidate_path_contains(root_path, descriptor.path) {
			project_file_candidate_source_close(&source)
			return {}, false, Candidate_Failure{code = .Invalid_Source}
		}
		label := descriptor.path[1:] if root_path == "/" else descriptor.path[len(root_path) + 1:]
		if len(label) == 0 {
			project_file_candidate_source_close(&source)
			return {}, false, Candidate_Failure{code = .Invalid_Source}
		}
		source.labels[index] = label
		source.fields[index] = descriptor.path
		source.descriptors[index] = Candidate_Descriptor_Definition {
			identity = project_file_candidate_identity(descriptor.path),
			label = label,
			searchable_fields = source.fields[index:index + 1],
			action = dir_file_candidate_action(descriptor),
			availability = .Available,
			durable_category = .Project_File,
			durable_key = descriptor.path,
		}
	}
	source.definition = Candidate_Source_Definition {
		kind = .Dir_Files,
		scope_identity = u64(batch.dir.id),
		scope_generation = u64(batch.dir.generation),
		source_generation = source_generation,
		descriptors = source.descriptors,
	}
	return source, true, {}
}

/* project_file_candidate_source_close releases temporary adapter storage. */
project_file_candidate_source_close :: proc(source: ^Project_File_Candidate_Source) -> bool {
	if source == nil || source.allocator.procedure == nil {
		return false
	}
	delete(source.annotations, source.allocator)
	delete(source.fields, source.allocator)
	delete(source.member_paths, source.allocator)
	delete(source.labels, source.allocator)
	delete(source.descriptors, source.allocator)
	source^ = {}
	return true
}

/* project_file_candidate_action_matches revalidates one exact observed Project file. */
project_file_candidate_action_matches :: proc(
	action: Candidate_Action,
	descriptor: project.File_Candidate_Descriptor,
) -> bool {
	path_identity := project_file_candidate_identity(descriptor.path)
	return action.kind == .Open_Document &&
	       action.owner_generation == u64(descriptor.project.generation) &&
	       action.primary == u64(descriptor.project.id) &&
	       action.secondary == u64(descriptor.generation) &&
	       action.graph_identity[0] == u64(descriptor.project.owner.id) &&
	       action.graph_identity[1] == u64(descriptor.project.owner.generation) &&
	       action.graph_identity[2] == u64(descriptor.project.id) &&
	       action.graph_identity[3] == u64(descriptor.project.generation) &&
	       action.graph_identity[4] == u64(descriptor.generation) &&
	       action.graph_identity[5] == path_identity.secondary
}

/* dir_file_candidate_action_matches revalidates one exact observed Dir file. */
dir_file_candidate_action_matches :: proc(
	action: Candidate_Action,
	descriptor: project.File_Candidate_Descriptor,
) -> bool {
	path_identity := project_file_candidate_identity(descriptor.path)
	return action.kind == .Open_Document &&
	       action.owner_generation == u64(descriptor.dir.generation) &&
	       action.primary == u64(descriptor.dir.id) &&
	       action.secondary == u64(descriptor.generation) &&
	       action.graph_identity[0] == u64(descriptor.dir.owner.id) &&
	       action.graph_identity[1] == u64(descriptor.dir.owner.generation) &&
	       action.graph_identity[2] == u64(descriptor.dir.id) &&
	       action.graph_identity[3] == u64(descriptor.dir.generation) &&
	       action.graph_identity[4] == u64(descriptor.generation) &&
	       action.graph_identity[5] == path_identity.secondary
}

@(private)
project_file_candidate_relative_label :: proc(
	path: string,
	memberships: []project.Membership_Descriptor,
) -> (label, member_path: string, membership_count: u32) {
	for &descriptor in memberships {
		root := project.directory_path_text(&descriptor.path)
		if !project_file_candidate_path_contains(root, path) {
			continue
		}
		membership_count += 1
		if len(root) > len(member_path) ||
		   (len(root) == len(member_path) && strings.compare(root, member_path) < 0) {
			member_path = root
		}
	}
	if len(member_path) == 0 {
		return "", "", membership_count
	}
	if member_path == "/" {
		return path[1:], member_path, membership_count
	}
	return path[len(member_path) + 1:], member_path, membership_count
}

@(private)
project_file_candidate_path_contains :: proc(root, path: string) -> bool {
	if root == "/" {
		return len(path) > 1 && path[0] == '/'
	}
	return len(path) > len(root) && strings.has_prefix(path, root) && path[len(root)] == '/'
}

@(private)
project_file_candidate_label_is_ambiguous :: proc(labels: []string, index: int) -> bool {
	for label, other_index in labels {
		if other_index != index && label == labels[index] {
			return true
		}
	}
	return false
}

@(private)
project_file_candidate_identity :: proc(path: string) -> Candidate_Identity {
	return Candidate_Identity {
		kind = 4,
		primary = project_file_candidate_hash(path, 14_695_981_039_346_656_037),
		secondary = project_file_candidate_hash(path, 10_995_116_282_11),
	}
}

@(private)
project_file_candidate_hash :: proc(path: string, seed: u64) -> u64 {
	hash := seed
	for byte in transmute([]u8)path {
		hash = (hash ~ u64(byte)) * 1_099_511_628_211
	}
	return hash if hash != 0 else 1
}

@(private)
project_file_candidate_action :: proc(
	descriptor: project.File_Candidate_Descriptor,
) -> Candidate_Action {
	path_identity := project_file_candidate_identity(descriptor.path)
	return Candidate_Action {
		kind = .Open_Document,
		owner_generation = u64(descriptor.project.generation),
		primary = u64(descriptor.project.id),
		secondary = u64(descriptor.generation),
		graph_identity = {
			u64(descriptor.project.owner.id),
			u64(descriptor.project.owner.generation),
			u64(descriptor.project.id),
			u64(descriptor.project.generation),
			u64(descriptor.generation),
			path_identity.secondary,
		},
	}
}

@(private)
dir_file_candidate_action :: proc(
	descriptor: project.File_Candidate_Descriptor,
) -> Candidate_Action {
	path_identity := project_file_candidate_identity(descriptor.path)
	return Candidate_Action {
		kind = .Open_Document,
		owner_generation = u64(descriptor.dir.generation),
		primary = u64(descriptor.dir.id),
		secondary = u64(descriptor.generation),
		graph_identity = {
			u64(descriptor.dir.owner.id),
			u64(descriptor.dir.owner.generation),
			u64(descriptor.dir.id),
			u64(descriptor.dir.generation),
			u64(descriptor.generation),
			path_identity.secondary,
		},
	}
}
