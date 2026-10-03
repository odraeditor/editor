// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import "../editor"
import "../transaction"
import "base:runtime"

/* MAX_WORKSPACE_EDIT_DOCUMENTS bounds documents in one server response. */
MAX_WORKSPACE_EDIT_DOCUMENTS :: 256
/* MAX_WORKSPACE_EDIT_OPERATIONS bounds file operations in one server response. */
MAX_WORKSPACE_EDIT_OPERATIONS :: 1_024
/* MAX_WORKSPACE_EDIT_TEXT_EDITS bounds text edits in one server response. */
MAX_WORKSPACE_EDIT_TEXT_EDITS :: 100_000
/* MAX_WORKSPACE_EDIT_PATH_BYTES bounds one normalized filesystem path. */
MAX_WORKSPACE_EDIT_PATH_BYTES :: 4 * 1_024
/* MAX_WORKSPACE_EDIT_URI_BYTES bounds one normalized document URI. */
MAX_WORKSPACE_EDIT_URI_BYTES :: 8 * 1_024
/* MAX_WORKSPACE_EDIT_REPLACEMENT_BYTES bounds replacement text in one response. */
MAX_WORKSPACE_EDIT_REPLACEMENT_BYTES :: 64 * 1_024 * 1_024

/* Workspace_Edit_Origin identifies the language operation requesting an edit. */
Workspace_Edit_Origin :: enum u8 {Invalid, Rename, Code_Action}
/* Workspace_Resource_Kind distinguishes admitted filesystem resource types. */
Workspace_Resource_Kind :: enum u8 {Invalid, Regular_File, Directory}
/* Workspace_File_Operation_Kind identifies a checked filesystem mutation. */
Workspace_File_Operation_Kind :: enum u8 {Invalid, Create, Rename, Delete}

/* Workspace_Edit_Failure_Code identifies an exact normalization or commit failure. */
Workspace_Edit_Failure_Code :: enum u16 {
	None,
	Invalid_Input,
	Malformed_Response,
	Invalid_Workspace_Edit,
	Invalid_Document,
	Version_Mismatch,
	Stale_Revision,
	Overlapping_Edit,
	Duplicate_Resource,
	Unsupported_Operation,
	Untrusted_Project,
	Outside_Membership,
	Resource_Limit,
	Allocation,
	Filesystem_Preflight,
	Filesystem_Stage,
	Filesystem_Publish,
	Filesystem_Rollback,
	Filesystem_Cleanup,
	Transaction_Prepare,
	Transaction_Commit,
	Closed,
}

/* Workspace_Edit_Resource identifies the bounded resource that failed. */
Workspace_Edit_Resource :: enum u8 {
	None,
	Document,
	Text_Edit,
	File_Operation,
	Replacement_Bytes,
	Path_Bytes,
	URI_Bytes,
	Retained_Bytes,
}

/* Workspace_Edit_Limits bounds normalized response and retained state sizes. */
Workspace_Edit_Limits :: struct {
	documents:        u32,
	text_edits:       u32,
	file_operations:  u32,
	replacement_bytes: u64,
	retained_bytes:   u64,
}

/* DEFAULT_WORKSPACE_EDIT_LIMITS applies the maintained workspace-edit bounds. */
DEFAULT_WORKSPACE_EDIT_LIMITS :: Workspace_Edit_Limits {
	documents = MAX_WORKSPACE_EDIT_DOCUMENTS,
	text_edits = MAX_WORKSPACE_EDIT_TEXT_EDITS,
	file_operations = MAX_WORKSPACE_EDIT_OPERATIONS,
	replacement_bytes = MAX_WORKSPACE_EDIT_REPLACEMENT_BYTES,
	retained_bytes = 128 * 1_024 * 1_024,
}

/* Workspace_Document_Target is an exact caller-owned document admitted for one response. */
Workspace_Document_Target :: struct {
	uri:              string,
	path:             string,
	buffer:           ^editor.Buffer,
	buffer_id:        editor.Buffer_ID,
	base_revision:    editor.Revision,
	text:             string,
	protocol_version: i64,
	has_protocol_version: bool,
	exists_on_disk:   bool,
	disk_inode:       u128,
	resource_kind:    Workspace_Resource_Kind,
}

/* Workspace_Resource_Target admits a non-document resource endpoint by exact URI and path. */
Workspace_Resource_Target :: struct {
	uri:            string,
	path:           string,
	exists_on_disk: bool,
	disk_inode:     u128,
	kind:           Workspace_Resource_Kind,
}

/* Workspace_Edit_Context admits exact project, document, resource, and limit state. */
Workspace_Edit_Context :: struct {
	root:              string,
	membership:        string,
	project_trusted:   bool,
	position_encoding: Position_Encoding,
	documents:         []Workspace_Document_Target,
	resources:         []Workspace_Resource_Target,
	limits:            Workspace_Edit_Limits,
}

/* Workspace_File_Operation is one normalized checked filesystem mutation. */
Workspace_File_Operation :: struct {
	kind:             Workspace_File_Operation_Kind,
	source_path:      string,
	destination_path: string,
	source_inode:     u128,
	source_kind:      Workspace_Resource_Kind,
}

/* Workspace_Edit_Preview summarizes a proposal without borrowed values. */
Workspace_Edit_Preview :: struct {
	origin:            Workspace_Edit_Origin,
	documents:         u32,
	text_edits:        u32,
	created_files:     u32,
	renamed_files:     u32,
	deleted_files:     u32,
	replacement_bytes: u64,
}

/* Workspace_Edit_Failure reports an exact failed resource and bound. */
Workspace_Edit_Failure :: struct {
	code:       Workspace_Edit_Failure_Code,
	resource:   Workspace_Edit_Resource,
	index:      u32,
	limit:      u64,
	actual:     u64,
	transaction: transaction.Failure_Context,
}

/* Workspace_Edit_Proposal owns normalized edits until commit or close. */
Workspace_Edit_Proposal :: struct {
	edit:       transaction.Edit_Proposal,
	operations: []Workspace_File_Operation,
	preview:    Workspace_Edit_Preview,
	state:      rawptr,
}

/* Workspace_Edit_Commit_Result records published edits and cleanup status. */
Workspace_Edit_Commit_Result :: struct {
	transaction: transaction.Multibuffer_Commit_Result,
	preview:     Workspace_Edit_Preview,
	cleanup_failure: Workspace_Edit_Failure,
}

/* Workspace_Edit_Commit owns the reversible transaction after publication. */
Workspace_Edit_Commit :: struct {
	result:      Workspace_Edit_Commit_Result,
	transaction: transaction.Multibuffer_Transaction,
	closed:      bool,
}

/* Workspace_File_Metadata is copied preflight state for one resource. */
Workspace_File_Metadata :: struct {
	exists: bool,
	inode:  u128,
	kind:   Workspace_Resource_Kind,
}

/* Workspace_File_Stat_Procedure inspects one exact path without retaining it. */
Workspace_File_Stat_Procedure :: proc(user_data: rawptr, path: string) -> (Workspace_File_Metadata, bool)
/* Workspace_File_Rename_Procedure atomically moves one exact path. */
Workspace_File_Rename_Procedure :: proc(user_data: rawptr, from, to: string) -> bool
/* Workspace_File_Create_Procedure creates one empty regular file. */
Workspace_File_Create_Procedure :: proc(user_data: rawptr, path: string) -> bool
/* Workspace_File_Remove_Procedure removes one exact file or directory. */
Workspace_File_Remove_Procedure :: proc(user_data: rawptr, path: string) -> bool

/* Workspace_File_IO supplies injectable filesystem operations for commit. */
Workspace_File_IO :: struct {
	stat:      Workspace_File_Stat_Procedure,
	rename:    Workspace_File_Rename_Procedure,
	create:    Workspace_File_Create_Procedure,
	remove:    Workspace_File_Remove_Procedure,
	user_data: rawptr,
}

/* Workspace_Edit_Allocators separates retained proposal state from temporary work. */
Workspace_Edit_Allocators :: struct {
	persistent: runtime.Allocator,
	temporary:  runtime.Allocator,
}

/* Workspace_Edit_Proposal_State owns all normalized proposal allocations. */
Workspace_Edit_Proposal_State :: struct {
	snapshots:   [dynamic]transaction.Proposal_Snapshot,
	edits:       [dynamic]transaction.Proposal_Edit,
	splices:     [dynamic][dynamic]transaction.Base_Splice,
	replacements: [dynamic]string,
	operations:  [dynamic]Workspace_File_Operation,
	owned_paths: [dynamic]string,
	preview:     Workspace_Edit_Preview,
	allocator:   runtime.Allocator,
}

/* workspace_edit_limits_valid accepts only positive maintained upper bounds. */
workspace_edit_limits_valid :: proc(limits: Workspace_Edit_Limits) -> bool {
	return limits.documents > 0 && limits.documents <= MAX_WORKSPACE_EDIT_DOCUMENTS &&
		limits.text_edits > 0 && limits.text_edits <= MAX_WORKSPACE_EDIT_TEXT_EDITS &&
		limits.file_operations > 0 && limits.file_operations <= MAX_WORKSPACE_EDIT_OPERATIONS &&
		limits.replacement_bytes > 0 && limits.replacement_bytes <= MAX_WORKSPACE_EDIT_REPLACEMENT_BYTES &&
		limits.retained_bytes > 0
}

/* workspace_edit_proposal_close releases an uncommitted normalized proposal once. */
workspace_edit_proposal_close :: proc(proposal: ^Workspace_Edit_Proposal) -> bool {
	if proposal == nil || proposal.state == nil do return false
	workspace_edit_state_destroy(cast(^Workspace_Edit_Proposal_State)proposal.state)
	proposal^ = {}
	return true
}

@(private)
workspace_edit_state_destroy :: proc(state: ^Workspace_Edit_Proposal_State) {
	if state == nil do return
	allocator := state.allocator
	for replacement in state.replacements do delete(replacement, allocator)
	for path in state.owned_paths do delete(path, allocator)
	for &batch in state.splices do if batch != nil do delete(batch)
	if state.snapshots != nil do delete(state.snapshots)
	if state.edits != nil do delete(state.edits)
	if state.splices != nil do delete(state.splices)
	if state.replacements != nil do delete(state.replacements)
	if state.operations != nil do delete(state.operations)
	if state.owned_paths != nil do delete(state.owned_paths)
	free(state, allocator)
}
