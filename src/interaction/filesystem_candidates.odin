// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "../filesystem"
import "base:runtime"
import "core:fmt"
import "core:time"

@(private)
FILESYSTEM_PERMISSION_TEXT_BYTES :: 10
@(private)
FILESYSTEM_SIZE_TEXT_BYTES :: 16
@(private)
FILESYSTEM_MODIFIED_TEXT_BYTES :: 20
@(private)
FILESYSTEM_ANNOTATION_COUNT :: 3

/* Filesystem_Candidate_Source owns borrowed-definition storage until session admission. */
Filesystem_Candidate_Source :: struct {
	definition:          Candidate_Source_Definition,
	descriptors:         []Candidate_Descriptor_Definition,
	fields:              []string,
	annotations:         []Candidate_Annotation_Definition,
	permission_storage:  [][FILESYSTEM_PERMISSION_TEXT_BYTES]u8,
	size_storage:        [][FILESYSTEM_SIZE_TEXT_BYTES]u8,
	modified_storage:    [][FILESYSTEM_MODIFIED_TEXT_BYTES]u8,
	allocator:           runtime.Allocator,
}

/* filesystem_candidate_source_build adapts one immediate-directory observation. */
filesystem_candidate_source_build :: proc(
	batch: ^filesystem.Directory_Batch,
	allocator := context.temp_allocator,
) -> (source: Filesystem_Candidate_Source, ok: bool, failure: Candidate_Failure) {
	if batch == nil || batch.state == nil || batch.generation == 0 ||
	   len(filesystem.normalized_path_text(&batch.directory)) == 0 ||
	   len(batch.descriptors) > int(MAX_CANDIDATES) || allocator.procedure == nil {
		return {}, false, Candidate_Failure{code = .Invalid_Source}
	}
	source.allocator = allocator
	allocation_error: runtime.Allocator_Error
	source.descriptors, allocation_error = make(
		[]Candidate_Descriptor_Definition,
		len(batch.descriptors),
		allocator,
	)
	if allocation_error != nil {
		filesystem_candidate_source_close(&source)
		return {}, false, Candidate_Failure{code = .Persistent_Memory_Limit}
	}
	source.fields, allocation_error = make([]string, len(batch.descriptors), allocator)
	if allocation_error != nil {
		filesystem_candidate_source_close(&source)
		return {}, false, Candidate_Failure{code = .Persistent_Memory_Limit}
	}
	source.annotations, allocation_error = make(
		[]Candidate_Annotation_Definition,
		len(batch.descriptors) * FILESYSTEM_ANNOTATION_COUNT,
		allocator,
	)
	if allocation_error != nil {
		filesystem_candidate_source_close(&source)
		return {}, false, Candidate_Failure{code = .Persistent_Memory_Limit}
	}
	source.permission_storage, allocation_error = make(
		[][FILESYSTEM_PERMISSION_TEXT_BYTES]u8,
		len(batch.descriptors),
		allocator,
	)
	if allocation_error != nil {
		filesystem_candidate_source_close(&source)
		return {}, false, Candidate_Failure{code = .Persistent_Memory_Limit}
	}
	source.size_storage, allocation_error = make(
		[][FILESYSTEM_SIZE_TEXT_BYTES]u8,
		len(batch.descriptors),
		allocator,
	)
	if allocation_error != nil {
		filesystem_candidate_source_close(&source)
		return {}, false, Candidate_Failure{code = .Persistent_Memory_Limit}
	}
	source.modified_storage, allocation_error = make(
		[][FILESYSTEM_MODIFIED_TEXT_BYTES]u8,
		len(batch.descriptors),
		allocator,
	)
	if allocation_error != nil {
		filesystem_candidate_source_close(&source)
		return {}, false, Candidate_Failure{code = .Persistent_Memory_Limit}
	}
	reference_seconds := time.to_unix_seconds(time.now())
	for descriptor, index in batch.descriptors {
		if !filesystem.resource_id_valid(descriptor.identity) || len(descriptor.label) == 0 ||
		   len(descriptor.path) == 0 ||
		   descriptor.kind == .Invalid || descriptor.size_bytes < 0 {
			filesystem_candidate_source_close(&source)
			return {}, false, Candidate_Failure{code = .Invalid_Source}
		}
		permissions := filesystem_candidate_permission_text(
			descriptor.kind,
			descriptor.permissions,
			source.permission_storage[index][:],
		)
		size := filesystem_candidate_size_text(
			u64(descriptor.size_bytes),
			source.size_storage[index][:],
		)
		modified := filesystem_candidate_modified_text(
			descriptor.modified_seconds,
			reference_seconds,
			source.modified_storage[index][:],
		)
		if len(permissions) == 0 || len(size) == 0 || len(modified) == 0 {
			filesystem_candidate_source_close(&source)
			return {}, false, Candidate_Failure{code = .Invalid_Source}
		}
		annotation_offset := index * FILESYSTEM_ANNOTATION_COUNT
		source.annotations[annotation_offset] = {
			kind = .Filesystem_Permissions,
			text = permissions,
		}
		source.annotations[annotation_offset + 1] = {
			kind = .Filesystem_Size,
			text = size,
		}
		source.annotations[annotation_offset + 2] = {
			kind = .Filesystem_Modified,
			text = modified,
		}
		source.fields[index] = descriptor.name
		source.descriptors[index] = Candidate_Descriptor_Definition {
			identity = {
				kind = 8,
				primary = descriptor.identity.inode,
				secondary = descriptor.identity.device,
			},
			label = descriptor.label,
			searchable_fields = source.fields[index:index + 1],
			annotations = source.annotations[
				annotation_offset:annotation_offset + FILESYSTEM_ANNOTATION_COUNT
			],
			action = {
				kind = .Select_Path_Entry,
				owner_generation = batch.generation,
				primary = descriptor.identity.inode,
				secondary = descriptor.identity.device,
			},
			availability = .Available,
		}
	}
	scope_identity := filesystem_candidate_path_identity(
		filesystem.normalized_path_text(&batch.directory),
	)
	source.definition = Candidate_Source_Definition {
		kind = .Filesystem_Entries,
		scope_identity = scope_identity,
		scope_generation = batch.generation,
		source_generation = batch.generation,
		descriptors = source.descriptors,
	}
	return source, true, {}
}

/* filesystem_candidate_source_close releases temporary adapter storage. */
filesystem_candidate_source_close :: proc(source: ^Filesystem_Candidate_Source) -> bool {
	if source == nil || source.allocator.procedure == nil do return false
	delete(source.modified_storage, source.allocator)
	delete(source.size_storage, source.allocator)
	delete(source.permission_storage, source.allocator)
	delete(source.annotations, source.allocator)
	delete(source.fields, source.allocator)
	delete(source.descriptors, source.allocator)
	source^ = {}
	return true
}

/* candidate_filesystem_presentation returns the complete filesystem metadata tuple. */
candidate_filesystem_presentation :: proc(
	row: Candidate_Row,
) -> (permissions, size, modified: string, ok: bool) {
	if len(row.label) == 0 || len(row.annotations) != FILESYSTEM_ANNOTATION_COUNT {
		return "", "", "", false
	}
	for annotation in row.annotations {
		switch annotation.kind {
		case .Filesystem_Permissions:
			permissions = annotation.text
		case .Filesystem_Size:
			size = annotation.text
		case .Filesystem_Modified:
			modified = annotation.text
		case .Invalid, .Binding, .Provider, .Availability, .Description,
		     .Document_Path, .Modified_State, .Project_Member, .Generic,
		     .Severity, .Location:
			return "", "", "", false
		}
	}
	return permissions, size, modified,
		len(permissions) == FILESYSTEM_PERMISSION_TEXT_BYTES && len(size) > 0 && len(modified) > 0
}

@(private)
filesystem_candidate_permission_text :: proc(
	kind: filesystem.Entry_Kind,
	permissions: u32,
	output: []u8,
) -> string {
	if len(output) < FILESYSTEM_PERMISSION_TEXT_BYTES do return ""
	output[0] = 'd' if kind == .Directory else '-'
	flags := [9]u32{8, 7, 6, 5, 4, 3, 2, 1, 0}
	marks := [3]u8{'r', 'w', 'x'}
	for flag, index in flags {
		output[index + 1] = marks[index % 3] if permissions & (u32(1) << flag) != 0 else '-'
	}
	return string(output[:FILESYSTEM_PERMISSION_TEXT_BYTES])
}

@(private)
filesystem_candidate_size_text :: proc(bytes: u64, output: []u8) -> string {
	if len(output) < FILESYSTEM_SIZE_TEXT_BYTES do return ""
	if bytes < 1_024 do return fmt.bprintf(output, "%d B", bytes)
	units := [5]string{"KiB", "MiB", "GiB", "TiB", "PiB"}
	value := bytes
	unit := 0
	for value >= 1_024 && unit < len(units) - 1 {
		value = (value + 512) / 1_024
		unit += 1
	}
	return fmt.bprintf(output, "%d %s", value, units[unit - 1])
}

@(private)
filesystem_candidate_modified_text :: proc(
	modified_seconds, reference_seconds: i64,
	output: []u8,
) -> string {
	if len(output) < FILESYSTEM_MODIFIED_TEXT_BYTES do return ""
	age := reference_seconds - modified_seconds
	if age >= 0 && age < 60 do return "just now"
	if age >= 60 && age < 3_600 do return fmt.bprintf(output, "%d min ago", age / 60)
	if age >= 3_600 && age < 172_800 do return fmt.bprintf(output, "%d hours ago", age / 3_600)
	if age >= 172_800 && age < 2_592_000 do return fmt.bprintf(output, "%d days ago", age / 86_400)
	months := [12]string{"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}
	modified := time.unix(modified_seconds, 0)
	year, month, day := time.date(modified)
	reference_year := time.year(time.unix(reference_seconds, 0))
	if month < .January || month > .December do return ""
	if year == reference_year {
		hour, minute, _ := time.clock(modified)
		return fmt.bprintf(output, "%s %d %02d:%02d", months[int(month) - 1], day, hour, minute)
	}
	return fmt.bprintf(output, "%04d %s %d", year, months[int(month) - 1], day)
}

/* filesystem_candidate_action_entry resolves one exact observed entry. */
filesystem_candidate_action_entry :: proc(
	action: Candidate_Action,
	batch: ^filesystem.Directory_Batch,
) -> (filesystem.Entry_Descriptor, bool) {
	if batch == nil || batch.state == nil || action.kind != .Select_Path_Entry ||
	   action.owner_generation != batch.generation {
		return {}, false
	}
	identity := filesystem.Resource_ID {
		provider = filesystem.LOCAL_PROVIDER_ID,
		device = action.secondary,
		inode = action.primary,
	}
	descriptor, found := filesystem.directory_entry_find(batch, identity)
	if !found do return {}, false
	return descriptor, true
}

@(private)
filesystem_candidate_path_identity :: proc(path: string) -> u64 {
	hash := u64(10_995_116_282_11)
	for byte in transmute([]u8)path {
		hash = (hash ~ u64(byte)) * 1_099_511_628_211
	}
	return hash if hash != 0 else 1
}
