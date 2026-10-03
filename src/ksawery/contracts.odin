// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package ksawery owns bounded Git repository observations and session-scoped requests.
package ksawery

import "core:strings"

/* KIBIBYTE is the binary byte unit used by repository resource policy. */
KIBIBYTE :: u64(1_024)
/* MEBIBYTE is 1,024 kibibytes. */
MEBIBYTE :: u64(1_024) * KIBIBYTE

/* MAX_REPOSITORY_CONTEXT_BYTES bounds one copied absolute repository context. */
MAX_REPOSITORY_CONTEXT_BYTES :: 4 * KIBIBYTE
/* MAX_BRANCH_BYTES bounds one copied branch or detached revision label. */
MAX_BRANCH_BYTES :: 256
/* MIN_STATUS_PATHS is the smallest admitted Status path capacity. */
MIN_STATUS_PATHS :: u32(16)
/* MAX_STATUS_PATHS is the immutable Status path capacity ceiling. */
MAX_STATUS_PATHS :: u32(16_384)
/* DEFAULT_STATUS_PATHS is the initial measured Status path capacity. */
DEFAULT_STATUS_PATHS :: u32(1_024)
/* MIN_STATUS_PATH_BYTES is the smallest admitted aggregate Status path budget. */
MIN_STATUS_PATH_BYTES :: 16 * KIBIBYTE
/* MAX_STATUS_PATH_BYTES is the immutable aggregate Status path ceiling. */
MAX_STATUS_PATH_BYTES :: 4 * MEBIBYTE
/* DEFAULT_STATUS_PATH_BYTES is the initial measured Status path budget. */
DEFAULT_STATUS_PATH_BYTES :: 256 * KIBIBYTE
/* MIN_PROCESS_OUTPUT_BYTES is the smallest admitted Git stdout ceiling. */
MIN_PROCESS_OUTPUT_BYTES :: 64 * KIBIBYTE
/* MAX_PROCESS_OUTPUT_BYTES is the immutable Git stdout ceiling. */
MAX_PROCESS_OUTPUT_BYTES :: 4 * MEBIBYTE
/* DEFAULT_PROCESS_OUTPUT_BYTES is the initial measured Git stdout ceiling. */
DEFAULT_PROCESS_OUTPUT_BYTES :: 512 * KIBIBYTE
/* MIN_DIAGNOSTIC_BYTES is the smallest admitted retained Git diagnostic budget. */
MIN_DIAGNOSTIC_BYTES :: 4 * KIBIBYTE
/* MAX_DIAGNOSTIC_BYTES is the immutable retained Git diagnostic ceiling. */
MAX_DIAGNOSTIC_BYTES :: 512 * KIBIBYTE
/* DEFAULT_DIAGNOSTIC_BYTES is the initial retained Git diagnostic budget. */
DEFAULT_DIAGNOSTIC_BYTES :: 64 * KIBIBYTE
/* MIN_DIFF_BYTES is the smallest admitted expanded-detail budget. */
MIN_DIFF_BYTES :: 64 * KIBIBYTE
/* MAX_DIFF_BYTES is the immutable expanded-detail ceiling. */
MAX_DIFF_BYTES :: 4 * MEBIBYTE
/* DEFAULT_DIFF_BYTES is the initial expanded-detail budget. */
DEFAULT_DIFF_BYTES :: 512 * KIBIBYTE
/* MIN_PROCESS_TIMEOUT_NANOSECONDS is the smallest admitted Git request timeout. */
MIN_PROCESS_TIMEOUT_NANOSECONDS :: i64(100_000_000)
/* MAX_PROCESS_TIMEOUT_NANOSECONDS is the immutable Git request timeout ceiling. */
MAX_PROCESS_TIMEOUT_NANOSECONDS :: i64(30_000_000_000)
/* DEFAULT_PROCESS_TIMEOUT_NANOSECONDS is the initial Git request timeout. */
DEFAULT_PROCESS_TIMEOUT_NANOSECONDS :: i64(2_000_000_000)
/* DEFAULT_CANCELLATION_GRACE_NANOSECONDS bounds graceful process cancellation. */
DEFAULT_CANCELLATION_GRACE_NANOSECONDS :: i64(250_000_000)

/* Observation_Generation identifies one immutable Status observation. */
Observation_Generation :: distinct u64
/* Path_ID identifies one semantic path inside one observation. */
Path_ID :: distinct u32

/* Repository_Context owns one copied absolute local repository path. */
Repository_Context :: struct {
	bytes:  [MAX_REPOSITORY_CONTEXT_BYTES]u8,
	length: u32,
}

/* Branch_Label owns one copied bounded branch or detached revision label. */
Branch_Label :: struct {
	bytes:  [MAX_BRANCH_BYTES]u8,
	length: u16,
}

/* Change_Group identifies one primary Status section. */
Change_Group :: enum u8 {
	Invalid,
	Unmerged,
	Untracked,
	Unstaged,
	Staged,
}

/* Operation_State identifies an observed active Git sequence. */
Operation_State :: enum u8 {
	Unknown,
	Normal,
	Merging,
	Rebasing,
	Cherry_Picking,
	Reverting,
	Bisecting,
	Applying_Patches,
	Other_Sequence,
}

/* Path_Text_Ref identifies copied path bytes owned by an observation. */
Path_Text_Ref :: struct {
	offset: u32,
	length: u32,
}

/* Status_Path is one semantic changed path within an observation. */
Status_Path :: struct {
	id:       Path_ID,
	group:    Change_Group,
	text:     Path_Text_Ref,
	index:    u8,
	worktree: u8,
}

/* Observation_Descriptor is the bounded, immutable Status summary. */
Observation_Descriptor :: struct {
	repository:  Repository_Context,
	generation:  Observation_Generation,
	branch:       Branch_Label,
	operation:    Operation_State,
	path_count:   u32,
	path_bytes:   u64,
	diagnostic_bytes: u64,
}

/* Process_Limits bounds one noninteractive Git request and retained detail. */
Process_Limits :: struct {
	status_paths:          u32,
	status_path_bytes:     u64,
	stdout_bytes:          u64,
	diagnostic_bytes:      u64,
	diff_bytes:            u64,
	timeout_nanoseconds:   i64,
	cancellation_grace_ns: i64,
}

/* DEFAULT_PROCESS_LIMITS selects the measured initial repository envelope. */
DEFAULT_PROCESS_LIMITS :: Process_Limits {
	status_paths = DEFAULT_STATUS_PATHS,
	status_path_bytes = DEFAULT_STATUS_PATH_BYTES,
	stdout_bytes = DEFAULT_PROCESS_OUTPUT_BYTES,
	diagnostic_bytes = DEFAULT_DIAGNOSTIC_BYTES,
	diff_bytes = DEFAULT_DIFF_BYTES,
	timeout_nanoseconds = DEFAULT_PROCESS_TIMEOUT_NANOSECONDS,
	cancellation_grace_ns = DEFAULT_CANCELLATION_GRACE_NANOSECONDS,
}

/* Request_Kind selects one closed repository-process request family. */
Request_Kind :: enum u8 {
	Invalid,
	Observe_Status,
	Observe_Sequence,
	Observe_History,
	Observe_Refs,
	Observe_Remote_Configuration,
	Observe_Push_Configuration,
	Inspect_Revision_Detail_Metadata,
	Inspect_Revision_Detail_Comparison,
	Inspect_Revision_Range_Summary,
	Inspect_Revision_Range_Comparison,
	Inspect_Path,
	Stage_Path,
	Unstage_Path,
	Stage_Diff_Unit,
	Unstage_Diff_Unit,
	Stage_Group,
	Unstage_Group,
	Discard_Path,
	Commit_Normal,
	Fetch_Remote,
	Push_Remote,
	Branch_Local,
	Tag_Local,
	Merge_Repository,
	Rebase_Repository,
	Cherry_Pick_Repository,
	Revert_Repository,
	Bisect_Repository,
	Resolve_Conflict,
	Inspection_Workflow,
	External_Operation,
	Raw_Command,
}

/* Path_Target identifies one semantic Status path at one exact generation. */
Path_Target :: struct {
	generation: Observation_Generation,
	path:       Path_ID,
}

/* Process_Request describes one checked noninteractive Git request. */
Process_Request :: struct {
	kind:       Request_Kind,
	repository: Repository_Context,
	target:     Path_Target,
	sequence:   Sequence_Request,
	history:    History_Request,
	refs:       Ref_Request,
	inspection: Revision_Inspection_Request,
	inspection_workflow: Inspection_Request,
	limits:     Process_Limits,
}

/* Failure_Code identifies normal repository admission and observation failures. */
Failure_Code :: enum u8 {
	None,
	Invalid_Context,
	Invalid_Limits,
	Invalid_Request,
	Stale_Observation,
	Path_Unavailable,
	Action_Unavailable,
	Executable_Unavailable,
	Process_Failed,
	Output_Limit,
	Timeout,
	Cancelled,
	Parse,
	Diff_Unsupported,
	Diff_Truncated,
	Diff_Unit_Unavailable,
	Patch_Unavailable,
	Target_Duplicate,
	Target_Incompatible,
	Target_Overlap,
	Target_Limit,
	Confirmation_Required,
	Confirmation_Mismatch,
	Modified_Buffer,
	History_Unborn,
	Revision_Unavailable,
	History_Limit,
	Parent_Limit,
	Commit_Unavailable,
	Commit_Message_Invalid,
	History_Metadata_Limit,
	History_Message_Limit,
	History_Topology_Limit,
	History_Temporary_Limit,
	History_Continuation_Stale,
	History_Truncated,
	Ref_Unavailable,
	Remote_Unavailable,
	Ref_Limit,
	Remote_Limit,
	Ref_Metadata_Limit,
	Ref_Temporary_Limit,
	Ref_Truncated,
	Process_Record_Stale,
	Process_Record_Closed,
	Process_Record_Limit,
	Sensitive_Content,
	Presentation_Unavailable,
	Allocation,
	Cleanup,
}

/* repository_context_assign copies one validated absolute repository path. */
repository_context_assign :: proc(repository: ^Repository_Context, path: string) -> bool {
	if repository == nil {
		return false
	}
	repository^ = {}
	if !repository_path_is_valid(path) {
		return false
	}
	copy(repository.bytes[:len(path)], transmute([]u8)path)
	repository.length = u32(len(path))
	return true
}

/* repository_context_is_valid checks one copied absolute repository context. */
repository_context_is_valid :: proc(repository: Repository_Context) -> bool {
	if repository.length == 0 || repository.length > len(repository.bytes) || repository.bytes[0] != '/' {
		return false
	}
	for index in 0..<int(repository.length) {
		if repository.bytes[index] == 0 do return false
	}
	return true
}

/* repository_context_string returns the validated copied repository path. */
repository_context_string :: proc(repository: ^Repository_Context) -> string {
	if repository == nil || !repository_context_is_valid(repository^) {
		return ""
	}
	return string(repository.bytes[:repository.length])
}

/* branch_label_assign copies one bounded branch or detached revision label. */
branch_label_assign :: proc(label: ^Branch_Label, text: string) -> bool {
	if label == nil {
		return false
	}
	label^ = {}
	if len(text) == 0 || len(text) > len(label.bytes) || strings.index_byte(text, 0) >= 0 {
		return false
	}
	copy(label.bytes[:len(text)], transmute([]u8)text)
	label.length = u16(len(text))
	return true
}

/* branch_label_is_valid checks one copied branch or detached revision label. */
branch_label_is_valid :: proc(label: Branch_Label) -> bool {
	if label.length == 0 || label.length > len(label.bytes) {
		return false
	}
	for index in 0..<int(label.length) {
		if label.bytes[index] == 0 do return false
	}
	return true
}

/* process_limits_are_valid checks the complete bounded Git request envelope. */
process_limits_are_valid :: proc(limits: Process_Limits) -> bool {
	return limits.status_paths >= MIN_STATUS_PATHS && limits.status_paths <= MAX_STATUS_PATHS &&
	       limits.status_path_bytes >= MIN_STATUS_PATH_BYTES &&
	       limits.status_path_bytes <= MAX_STATUS_PATH_BYTES &&
	       limits.stdout_bytes >= MIN_PROCESS_OUTPUT_BYTES &&
	       limits.stdout_bytes <= MAX_PROCESS_OUTPUT_BYTES &&
	       limits.diagnostic_bytes >= MIN_DIAGNOSTIC_BYTES &&
	       limits.diagnostic_bytes <= MAX_DIAGNOSTIC_BYTES &&
	       limits.diff_bytes >= MIN_DIFF_BYTES && limits.diff_bytes <= MAX_DIFF_BYTES &&
	       limits.timeout_nanoseconds >= MIN_PROCESS_TIMEOUT_NANOSECONDS &&
	       limits.timeout_nanoseconds <= MAX_PROCESS_TIMEOUT_NANOSECONDS &&
	       limits.cancellation_grace_ns > 0 &&
	       limits.cancellation_grace_ns < limits.timeout_nanoseconds &&
	       limits.status_path_bytes <= limits.stdout_bytes &&
	       limits.diagnostic_bytes <= limits.stdout_bytes
}

/* path_target_is_valid checks one nonzero semantic path identity. */
path_target_is_valid :: proc(target: Path_Target) -> bool {
	return target.generation != Observation_Generation(0) && target.path != Path_ID(0)
}

/* process_request_is_valid admits only checked closed request shapes. */
process_request_is_valid :: proc(request: Process_Request) -> bool {
	if !repository_context_is_valid(request.repository) || !process_limits_are_valid(request.limits) {
		return false
	}
	switch request.kind {
	case .Observe_Status:
		return request.target == {} && request.sequence == {} && request.history == {} && request.refs == {} && request.inspection == {} && request.inspection_workflow == {}
	case .Observe_Sequence:
		return request.target == {} && sequence_request_is_valid(request.sequence) && request.history == {} &&
		       request.refs == {} && request.inspection == {} && request.inspection_workflow == {}
	case .Observe_History:
		return request.target == {} && request.sequence == {} && history_request_is_valid(request.history) && request.refs == {} && request.inspection == {} && request.inspection_workflow == {}
	case .Observe_Refs:
		return request.target == {} && request.sequence == {} && request.history == {} && ref_request_is_valid(request.refs) && request.inspection == {} && request.inspection_workflow == {}
	case .Observe_Remote_Configuration, .Observe_Push_Configuration, .Fetch_Remote, .Push_Remote, .Branch_Local, .Tag_Local,
	     .Merge_Repository, .Rebase_Repository, .Cherry_Pick_Repository, .Revert_Repository, .Bisect_Repository, .Resolve_Conflict,
	     .External_Operation, .Raw_Command:
		return request.target == {} && request.sequence == {} && request.history == {} && request.refs == {} && request.inspection == {} && request.inspection_workflow == {}
	case .Inspect_Revision_Detail_Metadata, .Inspect_Revision_Detail_Comparison:
		return request.target == {} && request.sequence == {} && request.history == {} && request.refs == {} && request.inspection.kind == .Detail &&
		       revision_inspection_request_is_valid(request.inspection) && request.inspection_workflow == {}
	case .Inspect_Revision_Range_Summary, .Inspect_Revision_Range_Comparison:
		return request.target == {} && request.sequence == {} && request.history == {} && request.refs == {} && request.inspection.kind == .Range &&
		       revision_inspection_request_is_valid(request.inspection) && request.inspection_workflow == {}
	case .Inspect_Path, .Stage_Path, .Unstage_Path, .Stage_Diff_Unit, .Unstage_Diff_Unit,
	     .Discard_Path:
		return path_target_is_valid(request.target) && request.sequence == {} && request.history == {} && request.refs == {} && request.inspection == {} && request.inspection_workflow == {}
	case .Stage_Group, .Unstage_Group:
		return request.target == {} && request.sequence == {} && request.history == {} && request.refs == {} && request.inspection == {} && request.inspection_workflow == {}
	case .Commit_Normal:
		return request.target == {} && request.sequence == {} && request.history == {} && request.refs == {} && request.inspection == {} && request.inspection_workflow == {}
	case .Inspection_Workflow:
		return request.target == {} && request.sequence == {} && request.history == {} && request.refs == {} &&
		       request.inspection == {} && inspection_request_is_valid(request.inspection_workflow) &&
		       request.repository == request.inspection_workflow.repository
	case .Invalid:
		return false
	}
	return false
}

/* observation_descriptor_is_valid checks bounded copied Status metadata. */
observation_descriptor_is_valid :: proc(
	descriptor: Observation_Descriptor,
	limits: Process_Limits,
) -> bool {
	return repository_context_is_valid(descriptor.repository) &&
	       descriptor.generation != Observation_Generation(0) &&
	       branch_label_is_valid(descriptor.branch) &&
	       descriptor.operation != .Unknown &&
	       descriptor.path_count <= limits.status_paths &&
	       descriptor.path_bytes <= limits.status_path_bytes &&
	       descriptor.diagnostic_bytes <= limits.diagnostic_bytes
}

@(private)
repository_path_is_valid :: proc(path: string) -> bool {
	return len(path) > 0 && u64(len(path)) <= MAX_REPOSITORY_CONTEXT_BYTES && path[0] == '/' &&
	       strings.index_byte(path, 0) < 0
}
