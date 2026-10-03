// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package document owns local target identity, persistence state, and bounded file I/O.
package document

import "../editor"
import "base:runtime"

/* KIBIBYTE is the binary byte unit used by document limits. */
KIBIBYTE :: u64(1024)
/* MEBIBYTE is 1,024 kibibytes. */
MEBIBYTE :: u64(1024) * KIBIBYTE

/* MAX_FILE_BYTES is the maximum encoded file admitted by the first lifecycle. */
MAX_FILE_BYTES :: 256 * MEBIBYTE
/* MAX_PATH_BYTES is the maximum UTF-8 byte length of one associated path. */
MAX_PATH_BYTES :: u64(4_096)
@(private)
MAX_PATH_STORAGE_BYTES :: int(MAX_PATH_BYTES)
/* MAX_DIAGNOSTIC_BYTES bounds one rendered document diagnostic. */
MAX_DIAGNOSTIC_BYTES :: u64(4_096)
/* IO_CHUNK_BYTES is the bounded buffer size for streaming file operations. */
IO_CHUNK_BYTES :: u64(64) * KIBIBYTE
/* MAX_ACTIVE_OPERATIONS permits one document operation in the first lifecycle. */
MAX_ACTIVE_OPERATIONS :: u32(1)
/* MAX_SAVE_SNAPSHOTS permits one stable save snapshot in the first lifecycle. */
MAX_SAVE_SNAPSHOTS :: u32(1)
/* MAX_TEMPORARY_NAME_ATTEMPTS bounds exclusive save-file name selection. */
MAX_TEMPORARY_NAME_ATTEMPTS :: u32(16)
/* MAX_INTERRUPTED_IO_RETRIES bounds retries that transfer no bytes. */
MAX_INTERRUPTED_IO_RETRIES :: u32(16)

/* Document_ID identifies one live document; zero is invalid. */
Document_ID :: distinct u64

/* Encoding_Policy selects the explicit external text encoding. */
Encoding_Policy :: enum u8 {
	Invalid,
	UTF8,
}

/* Persistence_State reports the relation between one buffer and its target. */
Persistence_State :: enum u8 {
	Invalid,
	Unassociated,
	Unmaterialized,
	Clean,
	Modified,
	Saving,
	Closed,
}

/* Open_Kind classifies the accepted zero-or-one-path startup result. */
Open_Kind :: enum u8 {
	Invalid,
	Unassociated,
	Unmaterialized,
	Materialized,
}

/* Operation identifies the document operation that produced a result or failure. */
Operation :: enum u8 {
	None,
	Normalize_Path,
	Prepare_Open,
	Inspect_Prepared_Open,
	Commit_Open,
	Abort_Open,
	Inspect_Status,
	Close,
	Prepare_Save,
	Publish_Save,
	Abort_Save,
	Prepare_Association,
	Publish_Association,
	Abort_Association,
	Prepare_Relocation,
	Publish_Relocation,
	Abort_Relocation,
}

/* Prepared_Relocation owns one checked replacement path until publish or abort. */
Prepared_Relocation :: struct {
	state: rawptr,
}

/* Normalized_Path is a bounded copied absolute local path with no filesystem authority. */
Normalized_Path :: struct {
	bytes:  [MAX_PATH_STORAGE_BYTES]u8,
	length: int,
}

/* Publication_State distinguishes target replacement from confirmed directory durability. */
Publication_State :: enum u8 {
	Invalid,
	Not_Published,
	Published_Durable,
	Published_Durability_Uncertain,
}

/* Failure_Code classifies expected document failures without partial publication. */
Failure_Code :: enum u16 {
	None,
	Invalid_Document,
	Invalid_Document_ID,
	Invalid_Buffer_ID,
	Invalid_Encoding,
	Invalid_Limits,
	Closed_Document,
	Operation_In_Progress,
	Invalid_Preparation,
	Path_Required,
	Path_Not_Allowed,
	Path_Empty,
	Path_Limit,
	Path_Malformed_UTF8,
	Path_Contains_Nul,
	Parent_Not_Found,
	Parent_Not_Directory,
	Parent_Inaccessible,
	Target_Is_Symbolic_Link,
	Target_Not_Regular,
	Target_Inaccessible,
	Target_Changed,
	File_Limit,
	Malformed_UTF8,
	Metadata_Failed,
	Open_Failed,
	Read_Failed,
	Snapshot_Failed,
	Temporary_Name_Limit,
	Create_Failed,
	Permission_Failed,
	Write_Failed,
	File_Sync_Failed,
	Close_Failed,
	Rename_Failed,
	Directory_Open_Failed,
	Directory_Sync_Failed,
	Cleanup_Failed,
	Unexpected_End_Of_File,
	Persistent_Memory_Limit,
	Temporary_Memory_Limit,
	Work_Limit,
	Cancelled,
}

/* Limits collects hard size, memory, retry, and concurrency bounds for one document. */
Limits :: struct {
	file_bytes:                 u64,
	path_bytes:                 u64,
	diagnostic_bytes:           u64,
	io_chunk_bytes:             u64,
	active_operations:          u32,
	save_snapshots:             u32,
	temporary_name_attempts:    u32,
	interrupted_io_retries:     u32,
}

/* DEFAULT_LIMITS is the production bound set for the first local-document lifecycle. */
DEFAULT_LIMITS :: Limits {
	file_bytes = MAX_FILE_BYTES,
	path_bytes = MAX_PATH_BYTES,
	diagnostic_bytes = MAX_DIAGNOSTIC_BYTES,
	io_chunk_bytes = IO_CHUNK_BYTES,
	active_operations = MAX_ACTIVE_OPERATIONS,
	save_snapshots = MAX_SAVE_SNAPSHOTS,
	temporary_name_attempts = MAX_TEMPORARY_NAME_ATTEMPTS,
	interrupted_io_retries = MAX_INTERRUPTED_IO_RETRIES,
}

/*
Allocator_Set supplies the persistent and temporary allocation domains.
The caller keeps both allocator procedures live until the owning operation or
document releases its storage.
*/
Allocator_Set :: struct {
	persistent: runtime.Allocator,
	temporary:  runtime.Allocator,
}

/* File_Identity identifies one observed Linux filesystem object. */
File_Identity :: struct {
	device: u64,
	inode:  u64,
}

/* External_Observation records bounded metadata without granting mutation authority. */
External_Observation :: struct {
	exists:               bool,
	identity:             File_Identity,
	encoded_bytes:        u64,
	modified_seconds:     i64,
	modified_nanoseconds: i32,
	mode:                 u32,
}

/* Open_Request describes one zero-or-one-path local-document preparation. */
Open_Request :: struct {
	document_id: Document_ID,
	buffer_id:   editor.Buffer_ID,
	has_path:    bool,
	path:        string,
	encoding:    Encoding_Policy,
}

/*
Open_View borrows the accepted path and exact decoded bytes from Prepared_Open.
Both string views expire when the preparation is committed or aborted.
*/
Open_View :: struct {
	document_id: Document_ID,
	buffer_id:   editor.Buffer_ID,
	kind:        Open_Kind,
	encoding:    Encoding_Policy,
	path:        string,
	contents:    string,
	observation: External_Observation,
}

/* Document_Status reports immutable lifecycle state for one live document. */
Document_Status :: struct {
	document_id:       Document_ID,
	buffer_id:         editor.Buffer_ID,
	persistence:       Persistence_State,
	encoding:          Encoding_Policy,
	has_target:        bool,
	materialized:      bool,
	has_saved_revision: bool,
	saved_revision:    editor.Revision,
	observation:       External_Observation,
	// target_path is borrowed from the document and expires when it closes.
	target_path:       string,
}

/* Save_Result reports the exact revision and publication boundary reached by one explicit save. */
Save_Result :: struct {
	document_id:              Document_ID,
	buffer_id:                editor.Buffer_ID,
	saved_revision:           editor.Revision,
	publication:              Publication_State,
	external_change_observed: bool,
	observation:              External_Observation,
}

/* Failure_Context locates an expected failure and reports violated bounds when relevant. */
Failure_Context :: struct {
	code:          Failure_Code,
	operation:     Operation,
	document_id:   Document_ID,
	buffer_id:     editor.Buffer_ID,
	byte_offset:   u64,
	limit:         u64,
	actual:        u64,
	platform_code: i32,
	publication:   Publication_State,
}

/* Prepared_Open owns a private open candidate until commit or abort consumes it. */
Prepared_Open :: struct {
	state: rawptr,
}

/* Prepared_Save owns one explicit immutable save snapshot until publish or abort consumes it. */
Prepared_Save :: struct {
	state: rawptr,
}

/*
Prepared_Association privately owns one validated target name until first-save
publication or abort consumes it. It does not alter observable document state.
*/
Prepared_Association :: struct {
	state: rawptr,
}

/* Document is an opaque owner of one buffer association and optional local target. */
Document :: struct {
	state: rawptr,
}

@(private)
limits_are_valid :: proc(limits: Limits) -> bool {
	return limits.file_bytes > 0 &&
	       limits.file_bytes <= MAX_FILE_BYTES &&
	       limits.path_bytes > 0 &&
	       limits.path_bytes <= MAX_PATH_BYTES &&
	       limits.diagnostic_bytes > 0 &&
	       limits.diagnostic_bytes <= MAX_DIAGNOSTIC_BYTES &&
	       limits.io_chunk_bytes > 0 &&
	       limits.io_chunk_bytes <= limits.file_bytes &&
	       limits.io_chunk_bytes <= IO_CHUNK_BYTES &&
	       limits.active_operations == MAX_ACTIVE_OPERATIONS &&
	       limits.save_snapshots == MAX_SAVE_SNAPSHOTS &&
	       limits.temporary_name_attempts > 0 &&
	       limits.temporary_name_attempts <= MAX_TEMPORARY_NAME_ATTEMPTS &&
	       limits.interrupted_io_retries > 0 &&
	       limits.interrupted_io_retries <= MAX_INTERRUPTED_IO_RETRIES
}
