// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package filesystem owns bounded local resource observation and mutation mechanisms.
package filesystem

import "base:runtime"

/* MAX_PATH_BYTES bounds one admitted local path. */
MAX_PATH_BYTES :: u64(4_096)
@(private)
MAX_PATH_STORAGE_BYTES :: int(MAX_PATH_BYTES)
/* MAX_DIRECTORY_ENTRIES bounds one complete immediate-directory observation. */
MAX_DIRECTORY_ENTRIES :: u32(4_096)
/* MAX_COPY_BYTES bounds one local copy operation. */
MAX_COPY_BYTES :: u64(268_435_456)
/* MAX_COPY_ENTRIES bounds one recursive local copy operation. */
MAX_COPY_ENTRIES :: u32(16_384)
/* MAX_COPY_DEPTH bounds recursive directory traversal. */
MAX_COPY_DEPTH :: u16(64)
/* LOCAL_PROVIDER_ID identifies resources observed by the native local provider. */
LOCAL_PROVIDER_ID :: u64(1)

/* Allocator_Set supplies the allocation domains used by one observation. */
Allocator_Set :: struct {
	persistent: runtime.Allocator,
	temporary:  runtime.Allocator,
}

/* Resource_ID identifies one provider-scoped filesystem object across path changes. */
Resource_ID :: struct {
	provider: u64,
	device:   u64,
	inode:    u64,
}

/* Normalized_Path is a bounded copied absolute local path without mutation authority. */
Normalized_Path :: struct {
	bytes:  [MAX_PATH_STORAGE_BYTES]u8,
	length: int,
}

/* Entry_Kind classifies local children admitted to directory navigation. */
Entry_Kind :: enum u8 {
	Invalid,
	Regular_File,
	Directory,
}

/* Entry_Descriptor borrows one copied resource record from its owning batch. */
Entry_Descriptor :: struct {
	identity:         Resource_ID,
	name:             string,
	label:            string,
	path:             string,
	kind:             Entry_Kind,
	permissions:      u32,
	size_bytes:       i64,
	modified_seconds: i64,
}

/* Directory_Batch owns one complete bounded immediate-directory generation. */
Directory_Batch :: struct {
	directory:          Normalized_Path,
	directory_identity: Resource_ID,
	generation:         u64,
	descriptors:        []Entry_Descriptor,
	state:              rawptr,
}

/* Rename_Request identifies one observed child and its same-directory destination name. */
Rename_Request :: struct {
	identity: Resource_ID,
	from:     string,
	to:       string,
}

/* Rename_Outcome classifies one entry after a checked batch attempt. */
Rename_Outcome :: enum u8 {
	Invalid,
	Applied,
	Rolled_Back,
	Unapplied,
	Failed,
}

/* Rename_Result reports one input request without hiding partial application. */
Rename_Result :: struct {
	identity: Resource_ID,
	outcome:  Rename_Outcome,
}

/* Move_Request identifies one immediate child and an admitted root-relative destination. */
Move_Request :: struct {
	identity: Resource_ID,
	from:     string,
	to:       string,
}

/* Delete_Request identifies one observed immediate child proposed for permanent deletion. */
Delete_Request :: struct {
	identity: Resource_ID,
	name:     string,
	kind:     Entry_Kind,
}

/* Delete_Result reports permanent-delete recovery and the exact entry outcome. */
Delete_Result :: struct {
	identity:           Resource_ID,
	outcome:            Rename_Outcome,
	recovery_available: bool,
}

/* Creation_Kind selects one bounded local child type. */
Creation_Kind :: enum u8 {
	Invalid,
	Regular_File,
	Directory,
}

/* Creation_Request identifies one checked parent and collision-free child name. */
Creation_Request :: struct {
	parent_identity: Resource_ID,
	name:            string,
	kind:            Creation_Kind,
}

/* Creation_Result reports the exact newly observed local resource. */
Creation_Result :: struct {
	identity: Resource_ID,
	kind:     Creation_Kind,
}

/* Copy_Limits bounds byte, entry, and recursive path work. */
Copy_Limits :: struct {
	bytes:   u64,
	entries: u32,
	depth:   u16,
}

/* DEFAULT_COPY_LIMITS is the measured bounded local copy policy. */
DEFAULT_COPY_LIMITS :: Copy_Limits {
	bytes = MAX_COPY_BYTES,
	entries = MAX_COPY_ENTRIES,
	depth = MAX_COPY_DEPTH,
}

/* Copy_Request identifies one exact child and one checked absent destination. */
Copy_Request :: struct {
	source_parent_identity:      Resource_ID,
	source_identity:             Resource_ID,
	source_name:                 string,
	source_kind:                 Entry_Kind,
	destination_parent_identity: Resource_ID,
	destination_name:            string,
	limits:                      Copy_Limits,
}

/* Copy_Outcome reports successful or cleaned partial provider application. */
Copy_Outcome :: enum u8 {
	Invalid,
	Applied,
	Cleaned_Partial,
	Partial_Remains,
}

/* Copy_Durability reports the strongest completed durability boundary. */
Copy_Durability :: enum u8 {
	Unreported,
	File_Data_Synced,
	Best_Effort_Directory_Metadata,
}

/* Copy_Result reports bounded work and the exact destination outcome. */
Copy_Result :: struct {
	identity:   Resource_ID,
	outcome:    Copy_Outcome,
	durability: Copy_Durability,
	bytes:      u64,
	entries:    u32,
}

/* Entry_Move_Request identifies one exact child and one checked absent destination. */
Entry_Move_Request :: struct {
	source_parent_identity:      Resource_ID,
	source_identity:             Resource_ID,
	source_name:                 string,
	source_kind:                 Entry_Kind,
	destination_parent_identity: Resource_ID,
	destination_name:            string,
}

/* Entry_Move_Result reports the exact destination identity after one atomic rename. */
Entry_Move_Result :: struct {
	identity: Resource_ID,
	changed:  bool,
}

/* Operation identifies the filesystem operation that produced a failure. */
Operation :: enum u8 {
	None,
	Normalize_Path,
	Observe_Directory,
	Close_Directory_Observation,
	Apply_Rename_Batch,
	Apply_Move_Batch,
	Apply_Delete_Batch,
	Apply_Creation,
	Apply_Copy,
	Apply_Entry_Move,
}

/* Failure_Code classifies expected filesystem observation failures. */
Failure_Code :: enum u8 {
	None,
	Invalid_Arguments,
	Path_Empty,
	Path_Limit,
	Path_Malformed_UTF8,
	Path_Contains_Nul,
	Path_Normalization_Failed,
	Directory_Open_Failed,
	Metadata_Failed,
	Directory_Entry_Limit,
	Persistent_Memory_Limit,
	Directory_Changed,
	Source_Changed,
	Invalid_Name,
	Duplicate_Destination,
	Destination_Exists,
	Rename_Failed,
	Rollback_Failed,
	Destination_Parent_Missing,
	Cross_Device_Move,
	Recursive_Move,
	Recursive_Delete_Unavailable,
	Delete_Failed,
	Create_Failed,
	Copy_Byte_Limit,
	Copy_Entry_Limit,
	Copy_Depth_Limit,
	Copy_Failed,
	Copy_Durability_Failed,
	Partial_Cleanup_Failed,
}

/* Failure_Context reports one bounded filesystem failure without partial publication. */
Failure_Context :: struct {
	operation:     Operation,
	code:          Failure_Code,
	byte_offset:   u64,
	limit:         u64,
	actual:        u64,
	platform_code: i32,
}

/* resource_id_valid reports whether an identity names one provider-scoped resource. */
resource_id_valid :: proc(identity: Resource_ID) -> bool {
	return identity.provider != 0 && (identity.device != 0 || identity.inode != 0)
}

/* normalized_path_text borrows the complete copied path from one normalized value. */
normalized_path_text :: proc(normalized: ^Normalized_Path) -> string {
	if normalized == nil || normalized.length <= 0 || normalized.length > len(normalized.bytes) {
		return ""
	}
	return string(normalized.bytes[:normalized.length])
}
