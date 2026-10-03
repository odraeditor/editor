// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

/* MIN_REVISION_DETAIL_PARENTS is the smallest representable parent capacity. */
MIN_REVISION_DETAIL_PARENTS :: u8(1)
/* MAX_REVISION_DETAIL_PARENTS is the immutable parent capacity ceiling. */
MAX_REVISION_DETAIL_PARENTS :: MAX_HISTORY_PARENTS
/* DEFAULT_REVISION_DETAIL_PARENTS is the initial parent capacity. */
DEFAULT_REVISION_DETAIL_PARENTS :: MAX_REVISION_DETAIL_PARENTS
/* MIN_REVISION_DETAIL_METADATA_BYTES is the smallest admitted metadata budget. */
MIN_REVISION_DETAIL_METADATA_BYTES :: u64(16 * KIBIBYTE)
/* MAX_REVISION_DETAIL_METADATA_BYTES is the immutable metadata ceiling. */
MAX_REVISION_DETAIL_METADATA_BYTES :: u64(512 * KIBIBYTE)
/* DEFAULT_REVISION_DETAIL_METADATA_BYTES is the initial metadata budget. */
DEFAULT_REVISION_DETAIL_METADATA_BYTES :: u64(256 * KIBIBYTE)
/* MIN_REVISION_DETAIL_MESSAGE_BYTES is the smallest admitted full-message budget. */
MIN_REVISION_DETAIL_MESSAGE_BYTES :: u64(256)
/* MAX_REVISION_DETAIL_MESSAGE_BYTES is the immutable full-message ceiling. */
MAX_REVISION_DETAIL_MESSAGE_BYTES :: u64(256 * KIBIBYTE)
/* DEFAULT_REVISION_DETAIL_MESSAGE_BYTES is the initial full-message budget. */
DEFAULT_REVISION_DETAIL_MESSAGE_BYTES :: u64(64 * KIBIBYTE)
/* MAX_REVISION_DETAIL_SIGNATURE_BYTES bounds retained signature information. */
MAX_REVISION_DETAIL_SIGNATURE_BYTES :: u64(64 * KIBIBYTE)
/* MIN_REVISION_CHANGED_PATHS is the smallest admitted changed-path capacity. */
MIN_REVISION_CHANGED_PATHS :: u32(16)
/* MAX_REVISION_CHANGED_PATHS is the immutable changed-path capacity ceiling. */
MAX_REVISION_CHANGED_PATHS :: u32(16_384)
/* DEFAULT_REVISION_CHANGED_PATHS is the initial changed-path capacity. */
DEFAULT_REVISION_CHANGED_PATHS :: u32(1_024)
/* MIN_REVISION_CHANGED_PATH_BYTES is the smallest changed-path text budget. */
MIN_REVISION_CHANGED_PATH_BYTES :: u64(16 * KIBIBYTE)
/* MAX_REVISION_CHANGED_PATH_BYTES is the immutable changed-path text ceiling. */
MAX_REVISION_CHANGED_PATH_BYTES :: u64(4 * MEBIBYTE)
/* DEFAULT_REVISION_CHANGED_PATH_BYTES is the initial changed-path text budget. */
DEFAULT_REVISION_CHANGED_PATH_BYTES :: u64(256 * KIBIBYTE)
/* MIN_REVISION_DETAIL_DIFF_BYTES is the smallest admitted read-only diff budget. */
MIN_REVISION_DETAIL_DIFF_BYTES :: MIN_DIFF_BYTES
/* MAX_REVISION_DETAIL_DIFF_BYTES is the immutable read-only diff ceiling. */
MAX_REVISION_DETAIL_DIFF_BYTES :: MAX_DIFF_BYTES
/* DEFAULT_REVISION_DETAIL_DIFF_BYTES is the initial read-only diff budget. */
DEFAULT_REVISION_DETAIL_DIFF_BYTES :: DEFAULT_DIFF_BYTES
/* MIN_REVISION_DETAIL_TEMPORARY_BYTES is the smallest parser-work budget. */
MIN_REVISION_DETAIL_TEMPORARY_BYTES :: u64(512 * KIBIBYTE)
/* MAX_REVISION_DETAIL_TEMPORARY_BYTES is the immutable parser-work ceiling. */
MAX_REVISION_DETAIL_TEMPORARY_BYTES :: u64(16 * MEBIBYTE)
/* DEFAULT_REVISION_DETAIL_TEMPORARY_BYTES is the initial parser-work budget. */
DEFAULT_REVISION_DETAIL_TEMPORARY_BYTES :: u64(2 * MEBIBYTE)

/* MIN_REVISION_RANGE_REVISIONS is the smallest nonempty range-summary capacity. */
MIN_REVISION_RANGE_REVISIONS :: u32(2)
/* MAX_REVISION_RANGE_REVISIONS is the immutable range-summary capacity ceiling. */
MAX_REVISION_RANGE_REVISIONS :: MAX_HISTORY_PAGE_REVISIONS
/* DEFAULT_REVISION_RANGE_REVISIONS is the initial range-summary capacity. */
DEFAULT_REVISION_RANGE_REVISIONS :: u32(1_024)
/* MIN_REVISION_RANGE_SUMMARY_BYTES is the smallest range-summary text budget. */
MIN_REVISION_RANGE_SUMMARY_BYTES :: u64(16 * KIBIBYTE)
/* MAX_REVISION_RANGE_SUMMARY_BYTES is the immutable range-summary text ceiling. */
MAX_REVISION_RANGE_SUMMARY_BYTES :: u64(4 * MEBIBYTE)
/* DEFAULT_REVISION_RANGE_SUMMARY_BYTES is the initial range-summary text budget. */
DEFAULT_REVISION_RANGE_SUMMARY_BYTES :: u64(256 * KIBIBYTE)
/* MIN_REVISION_RANGE_TEMPORARY_BYTES is the smallest range parser-work budget. */
MIN_REVISION_RANGE_TEMPORARY_BYTES :: u64(512 * KIBIBYTE)
/* MAX_REVISION_RANGE_TEMPORARY_BYTES is the immutable range parser-work ceiling. */
MAX_REVISION_RANGE_TEMPORARY_BYTES :: u64(16 * MEBIBYTE)
/* DEFAULT_REVISION_RANGE_TEMPORARY_BYTES is the initial range parser-work budget. */
DEFAULT_REVISION_RANGE_TEMPORARY_BYTES :: u64(2 * MEBIBYTE)

/* Revision_Text_Ref identifies bounded text owned by one revision inspection result. */
Revision_Text_Ref :: struct {
	offset: u32,
	length: u32,
}

/* Revision_Parent_Kind distinguishes an explicit parent from the empty-tree root comparison. */
Revision_Parent_Kind :: enum u8 {
	Invalid,
	Empty_Tree,
	Parent,
}

/* Revision_Parent_Choice selects the exact immutable base for one revision diff. */
Revision_Parent_Choice :: struct {
	kind:   Revision_Parent_Kind,
	parent: Revision_Identity,
}

/* Revision_Signature_Status retains Git signature information without treating it as authority. */
Revision_Signature_Status :: enum u8 {
	Invalid,
	Unavailable,
	Good,
	Bad,
	Unknown,
	Untrusted,
	Expired,
	Revoked,
}

/* Revision_Change_Kind identifies one immutable changed-path summary entry. */
Revision_Change_Kind :: enum u8 {
	Invalid,
	Added,
	Copied,
	Deleted,
	Modified,
	Renamed,
	Type_Changed,
	Unmerged,
}

/* Revision_Changed_Path describes one changed path and an optional source path. */
Revision_Changed_Path :: struct {
	kind:          Revision_Change_Kind,
	path:          Revision_Text_Ref,
	original_path: Revision_Text_Ref,
}

/* Revision_Detail_Limits bounds one exact revision inspection. */
Revision_Detail_Limits :: struct {
	parents:            u8,
	metadata_bytes:     u64,
	message_bytes:      u64,
	signature_bytes:    u64,
	changed_paths:      u32,
	changed_path_bytes: u64,
	diff_bytes:         u64,
	temporary_bytes:    u64,
}

/* DEFAULT_REVISION_DETAIL_LIMITS selects the initial revision-detail envelope. */
DEFAULT_REVISION_DETAIL_LIMITS :: Revision_Detail_Limits {
	parents = DEFAULT_REVISION_DETAIL_PARENTS,
	metadata_bytes = DEFAULT_REVISION_DETAIL_METADATA_BYTES,
	message_bytes = DEFAULT_REVISION_DETAIL_MESSAGE_BYTES,
	signature_bytes = MAX_REVISION_DETAIL_SIGNATURE_BYTES,
	changed_paths = DEFAULT_REVISION_CHANGED_PATHS,
	changed_path_bytes = DEFAULT_REVISION_CHANGED_PATH_BYTES,
	diff_bytes = DEFAULT_REVISION_DETAIL_DIFF_BYTES,
	temporary_bytes = DEFAULT_REVISION_DETAIL_TEMPORARY_BYTES,
}

/* Revision_Detail_Request identifies one exact History revision and an explicit diff base. */
Revision_Detail_Request :: struct {
	target: History_Target,
	parent: Revision_Parent_Choice,
	limits: Revision_Detail_Limits,
}

/* Revision_Detail_Descriptor reports one bounded immutable revision detail. */
Revision_Detail_Descriptor :: struct {
	repository:         Repository_Context,
	target:             History_Target,
	parent:             Revision_Parent_Choice,
	parents:            [MAX_REVISION_DETAIL_PARENTS]Revision_Identity,
	parent_count:       u8,
	author_name:        Revision_Text_Ref,
	author_email:       Revision_Text_Ref,
	authored_at:        Revision_Text_Ref,
	committer_name:     Revision_Text_Ref,
	committer_email:    Revision_Text_Ref,
	committed_at:       Revision_Text_Ref,
	subject:            Revision_Text_Ref,
	message:            Revision_Text_Ref,
	signature_status:   Revision_Signature_Status,
	signature:          Revision_Text_Ref,
	changed_paths:      u32,
	metadata_bytes:     u64,
	message_bytes:      u64,
	signature_bytes:    u64,
	changed_path_bytes: u64,
	diff_bytes:         u64,
	temporary_bytes:    u64,
	truncated:          bool,
}

/* Revision_Detail owns one parsed immutable revision inspection. */
Revision_Detail :: struct {
	state: rawptr,
}

/* Revision_Range_Endpoint identifies one exact endpoint in one History generation. */
Revision_Range_Endpoint :: struct {
	generation: History_Generation,
	revision:   Revision_Identity,
}

/* Revision_Range is an ordered immutable base-to-target comparison. */
Revision_Range :: struct {
	base:   Revision_Range_Endpoint,
	target: Revision_Range_Endpoint,
}

/* Revision_Range_Limits bounds one read-only range inspection. */
Revision_Range_Limits :: struct {
	revisions:          u32,
	summary_bytes:      u64,
	changed_paths:      u32,
	changed_path_bytes: u64,
	diff_bytes:         u64,
	temporary_bytes:    u64,
}

/* DEFAULT_REVISION_RANGE_LIMITS selects the initial range-inspection envelope. */
DEFAULT_REVISION_RANGE_LIMITS :: Revision_Range_Limits {
	revisions = DEFAULT_REVISION_RANGE_REVISIONS,
	summary_bytes = DEFAULT_REVISION_RANGE_SUMMARY_BYTES,
	changed_paths = DEFAULT_REVISION_CHANGED_PATHS,
	changed_path_bytes = DEFAULT_REVISION_CHANGED_PATH_BYTES,
	diff_bytes = DEFAULT_REVISION_DETAIL_DIFF_BYTES,
	temporary_bytes = DEFAULT_REVISION_RANGE_TEMPORARY_BYTES,
}

/* Revision_Range_Request identifies one checked ordered pair for read-only inspection. */
Revision_Range_Request :: struct {
	range:  Revision_Range,
	limits: Revision_Range_Limits,
}

/* Revision_Range_Summary describes one exact commit retained in a range observation. */
Revision_Range_Summary :: struct {
	revision: Revision_Identity,
	subject:  Revision_Text_Ref,
}

/* Revision_Range_Observation_Descriptor reports one bounded immutable range result. */
Revision_Range_Observation_Descriptor :: struct {
	repository:         Repository_Context,
	range:              Revision_Range,
	revision_count:     u32,
	changed_paths:      u32,
	summary_bytes:      u64,
	changed_path_bytes: u64,
	diff_bytes:         u64,
	temporary_bytes:    u64,
	truncated:          bool,
}

/* Revision_Range_Observation owns one parsed immutable range inspection. */
Revision_Range_Observation :: struct {
	state: rawptr,
}

/* Revision_Inspection_Kind selects one read-only inspection family. */
Revision_Inspection_Kind :: enum u8 {
	Invalid,
	Detail,
	Range,
}

/* Revision_Inspection_Request is one closed detail or range inspection request. */
Revision_Inspection_Request :: struct {
	kind:   Revision_Inspection_Kind,
	detail: Revision_Detail_Request,
	range:  Revision_Range_Request,
}

/* Revision_Inspection_State reports the terminal condition of one inspection result. */
Revision_Inspection_State :: enum u8 {
	Invalid,
	Available,
	Truncated,
	Failed,
}

/* Revision_Inspection_Usage reports exact retained revision-inspection resources. */
Revision_Inspection_Usage :: struct {
	parents:            u32,
	range_revisions:    u32,
	changed_paths:      u32,
	metadata_bytes:     u64,
	message_bytes:      u64,
	signature_bytes:    u64,
	summary_bytes:      u64,
	changed_path_bytes: u64,
	diff_bytes:         u64,
	temporary_bytes:    u64,
	allocation_bytes:   u64,
}

/* Revision_Inspection_Result_Descriptor reports one bounded inspection outcome. */
Revision_Inspection_Result_Descriptor :: struct {
	request: Revision_Inspection_Request,
	state:   Revision_Inspection_State,
	failure: Failure_Code,
	usage:   Revision_Inspection_Usage,
}

/* Revision_Inspection_Result owns one terminal revision-inspection outcome. */
Revision_Inspection_Result :: struct {
	state: rawptr,
}

/* revision_text_ref_is_valid checks one reference against its result-owned storage. */
revision_text_ref_is_valid :: proc(reference: Revision_Text_Ref, storage_bytes: u64) -> bool {
	end := u64(reference.offset) + u64(reference.length)
	return end >= u64(reference.offset) && end <= storage_bytes
}

/* revision_parent_choice_is_valid requires either the empty tree or one exact parent. */
revision_parent_choice_is_valid :: proc(choice: Revision_Parent_Choice) -> bool {
	switch choice.kind {
	case .Empty_Tree:
		return choice.parent == {}
	case .Parent:
		return revision_identity_is_valid(choice.parent)
	case .Invalid:
		return false
	}
	return false
}

/* revision_changed_path_is_valid checks an immutable changed-path summary entry. */
revision_changed_path_is_valid :: proc(path: Revision_Changed_Path, storage_bytes: u64) -> bool {
	if path.kind == .Invalid || !revision_text_ref_is_valid(path.path, storage_bytes) || path.path.length == 0 {
		return false
	}
	original_valid := revision_text_ref_is_valid(path.original_path, storage_bytes)
	switch path.kind {
	case .Copied, .Renamed:
		return original_valid && path.original_path.length > 0
	case .Added, .Deleted, .Modified, .Type_Changed, .Unmerged:
		return original_valid && path.original_path == {}
	case .Invalid:
		return false
	}
	return false
}

/* revision_detail_limits_are_valid checks the complete detail resource envelope. */
revision_detail_limits_are_valid :: proc(limits: Revision_Detail_Limits) -> bool {
	return limits.parents >= MIN_REVISION_DETAIL_PARENTS && limits.parents <= MAX_REVISION_DETAIL_PARENTS &&
	       limits.metadata_bytes >= MIN_REVISION_DETAIL_METADATA_BYTES &&
	       limits.metadata_bytes <= MAX_REVISION_DETAIL_METADATA_BYTES &&
	       limits.message_bytes >= MIN_REVISION_DETAIL_MESSAGE_BYTES &&
	       limits.message_bytes <= MAX_REVISION_DETAIL_MESSAGE_BYTES &&
	       limits.signature_bytes <= MAX_REVISION_DETAIL_SIGNATURE_BYTES &&
	       limits.message_bytes + limits.signature_bytes >= limits.message_bytes &&
	       limits.message_bytes + limits.signature_bytes <= limits.metadata_bytes &&
	       limits.changed_paths >= MIN_REVISION_CHANGED_PATHS && limits.changed_paths <= MAX_REVISION_CHANGED_PATHS &&
	       limits.changed_path_bytes >= MIN_REVISION_CHANGED_PATH_BYTES &&
	       limits.changed_path_bytes <= MAX_REVISION_CHANGED_PATH_BYTES &&
	       limits.diff_bytes >= MIN_REVISION_DETAIL_DIFF_BYTES && limits.diff_bytes <= MAX_REVISION_DETAIL_DIFF_BYTES &&
	       limits.temporary_bytes >= MIN_REVISION_DETAIL_TEMPORARY_BYTES &&
	       limits.temporary_bytes <= MAX_REVISION_DETAIL_TEMPORARY_BYTES &&
	       limits.metadata_bytes + limits.changed_path_bytes + limits.diff_bytes >= limits.metadata_bytes &&
	       limits.metadata_bytes + limits.changed_path_bytes + limits.diff_bytes <= limits.temporary_bytes
}

/* revision_detail_request_is_valid checks an exact target and an explicit diff-base choice. */
revision_detail_request_is_valid :: proc(request: Revision_Detail_Request) -> bool {
	return history_target_is_valid(request.target) && revision_parent_choice_is_valid(request.parent) &&
	       revision_detail_limits_are_valid(request.limits)
}

/* revision_detail_descriptor_is_valid checks one bounded immutable detail summary. */
revision_detail_descriptor_is_valid :: proc(
	descriptor: Revision_Detail_Descriptor,
	limits := DEFAULT_REVISION_DETAIL_LIMITS,
) -> bool {
	if !repository_context_is_valid(descriptor.repository) || !history_target_is_valid(descriptor.target) ||
	   !revision_parent_choice_is_valid(descriptor.parent) || !revision_detail_limits_are_valid(limits) ||
	   descriptor.parent_count > limits.parents || descriptor.changed_paths > limits.changed_paths ||
	   descriptor.metadata_bytes > limits.metadata_bytes || descriptor.message_bytes > limits.message_bytes ||
	   descriptor.signature_bytes > limits.signature_bytes || descriptor.changed_path_bytes > limits.changed_path_bytes ||
	   descriptor.diff_bytes > limits.diff_bytes || descriptor.temporary_bytes > limits.temporary_bytes ||
	   descriptor.message_bytes != u64(descriptor.message.length) ||
	   descriptor.signature_bytes != u64(descriptor.signature.length) ||
	   descriptor.metadata_bytes + descriptor.changed_path_bytes + descriptor.diff_bytes < descriptor.metadata_bytes ||
	   descriptor.metadata_bytes + descriptor.changed_path_bytes + descriptor.diff_bytes > descriptor.temporary_bytes {
		return false
	}
	for parent_index in 0 ..< int(descriptor.parent_count) {
		if !revision_identity_is_valid(descriptor.parents[parent_index]) do return false
	}
	for parent_index in int(descriptor.parent_count) ..< len(descriptor.parents) {
		if descriptor.parents[parent_index] != {} do return false
	}
	parents := descriptor.parents
	if !revision_parent_choice_matches(descriptor.parent, parents[:int(descriptor.parent_count)]) do return false
	references := [9]Revision_Text_Ref {
		descriptor.author_name,
		descriptor.author_email,
		descriptor.authored_at,
		descriptor.committer_name,
		descriptor.committer_email,
		descriptor.committed_at,
		descriptor.subject,
		descriptor.message,
		descriptor.signature,
	}
	for reference in references {
		if !revision_text_ref_is_valid(reference, descriptor.metadata_bytes) do return false
	}
	switch descriptor.signature_status {
	case .Unavailable:
		return descriptor.signature == {} && descriptor.signature_bytes == 0
	case .Good, .Bad, .Unknown, .Untrusted, .Expired, .Revoked:
		return descriptor.signature.length > 0
	case .Invalid:
		return false
	}
	return false
}

/* revision_range_endpoint_is_valid checks one exact History-bound endpoint. */
revision_range_endpoint_is_valid :: proc(endpoint: Revision_Range_Endpoint) -> bool {
	return endpoint.generation != History_Generation(0) && revision_identity_is_valid(endpoint.revision)
}

/* revision_range_is_valid requires two distinct exact endpoints from one History observation. */
revision_range_is_valid :: proc(range: Revision_Range) -> bool {
	return revision_range_endpoint_is_valid(range.base) && revision_range_endpoint_is_valid(range.target) &&
	       range.base.generation == range.target.generation && range.base.revision != range.target.revision
}

/* revision_range_limits_are_valid checks the complete range resource envelope. */
revision_range_limits_are_valid :: proc(limits: Revision_Range_Limits) -> bool {
	return limits.revisions >= MIN_REVISION_RANGE_REVISIONS && limits.revisions <= MAX_REVISION_RANGE_REVISIONS &&
	       limits.summary_bytes >= MIN_REVISION_RANGE_SUMMARY_BYTES &&
	       limits.summary_bytes <= MAX_REVISION_RANGE_SUMMARY_BYTES &&
	       limits.changed_paths >= MIN_REVISION_CHANGED_PATHS && limits.changed_paths <= MAX_REVISION_CHANGED_PATHS &&
	       limits.changed_path_bytes >= MIN_REVISION_CHANGED_PATH_BYTES &&
	       limits.changed_path_bytes <= MAX_REVISION_CHANGED_PATH_BYTES &&
	       limits.diff_bytes >= MIN_REVISION_DETAIL_DIFF_BYTES && limits.diff_bytes <= MAX_REVISION_DETAIL_DIFF_BYTES &&
	       limits.temporary_bytes >= MIN_REVISION_RANGE_TEMPORARY_BYTES &&
	       limits.temporary_bytes <= MAX_REVISION_RANGE_TEMPORARY_BYTES &&
	       limits.summary_bytes + limits.changed_path_bytes + limits.diff_bytes >= limits.summary_bytes &&
	       limits.summary_bytes + limits.changed_path_bytes + limits.diff_bytes <= limits.temporary_bytes
}

/* revision_range_request_is_valid checks one exact ordered read-only comparison request. */
revision_range_request_is_valid :: proc(request: Revision_Range_Request) -> bool {
	return revision_range_is_valid(request.range) && revision_range_limits_are_valid(request.limits)
}

/* revision_range_summary_is_valid checks one retained exact range summary entry. */
revision_range_summary_is_valid :: proc(summary: Revision_Range_Summary, storage_bytes: u64) -> bool {
	return revision_identity_is_valid(summary.revision) && revision_text_ref_is_valid(summary.subject, storage_bytes)
}

/* revision_range_observation_descriptor_is_valid checks one bounded immutable range summary. */
revision_range_observation_descriptor_is_valid :: proc(
	descriptor: Revision_Range_Observation_Descriptor,
	limits := DEFAULT_REVISION_RANGE_LIMITS,
) -> bool {
	return repository_context_is_valid(descriptor.repository) && revision_range_is_valid(descriptor.range) &&
	       revision_range_limits_are_valid(limits) && descriptor.revision_count <= limits.revisions &&
	       descriptor.changed_paths <= limits.changed_paths &&
	       descriptor.summary_bytes <= limits.summary_bytes && descriptor.changed_path_bytes <= limits.changed_path_bytes &&
	       descriptor.diff_bytes <= limits.diff_bytes && descriptor.temporary_bytes <= limits.temporary_bytes &&
	       descriptor.summary_bytes + descriptor.changed_path_bytes + descriptor.diff_bytes >= descriptor.summary_bytes &&
	       descriptor.summary_bytes + descriptor.changed_path_bytes + descriptor.diff_bytes <= descriptor.temporary_bytes
}

/* revision_inspection_request_is_valid admits exactly one closed read-only inspection family. */
revision_inspection_request_is_valid :: proc(request: Revision_Inspection_Request) -> bool {
	switch request.kind {
	case .Detail:
		return revision_detail_request_is_valid(request.detail) && request.range == {}
	case .Range:
		return request.detail == {} && revision_range_request_is_valid(request.range)
	case .Invalid:
		return false
	}
	return false
}

/* revision_inspection_usage_is_valid checks retained resources against the selected request family. */
revision_inspection_usage_is_valid :: proc(
	usage: Revision_Inspection_Usage,
	request: Revision_Inspection_Request,
) -> bool {
	if !revision_inspection_request_is_valid(request) do return false
	total := usage.metadata_bytes + usage.summary_bytes + usage.changed_path_bytes + usage.diff_bytes
	if total < usage.metadata_bytes || usage.allocation_bytes < total do return false
	switch request.kind {
	case .Detail:
		limits := request.detail.limits
		return usage.parents <= u32(limits.parents) && usage.range_revisions == 0 &&
		       usage.changed_paths <= limits.changed_paths && usage.metadata_bytes <= limits.metadata_bytes &&
		       usage.message_bytes <= limits.message_bytes && usage.signature_bytes <= limits.signature_bytes &&
		       usage.summary_bytes == 0 && usage.changed_path_bytes <= limits.changed_path_bytes &&
		       usage.diff_bytes <= limits.diff_bytes && usage.temporary_bytes <= limits.temporary_bytes &&
		       usage.message_bytes + usage.signature_bytes >= usage.message_bytes &&
		       usage.message_bytes + usage.signature_bytes <= usage.metadata_bytes && total <= usage.temporary_bytes
	case .Range:
		limits := request.range.limits
		return usage.parents == 0 && usage.range_revisions <= limits.revisions &&
		       usage.changed_paths <= limits.changed_paths && usage.metadata_bytes == 0 && usage.message_bytes == 0 &&
		       usage.signature_bytes == 0 && usage.summary_bytes <= limits.summary_bytes &&
		       usage.changed_path_bytes <= limits.changed_path_bytes && usage.diff_bytes <= limits.diff_bytes &&
		       usage.temporary_bytes <= limits.temporary_bytes && total <= usage.temporary_bytes
	case .Invalid:
		return false
	}
	return false
}

/* revision_inspection_result_descriptor_is_valid checks one terminal read-only inspection outcome. */
revision_inspection_result_descriptor_is_valid :: proc(
	descriptor: Revision_Inspection_Result_Descriptor,
) -> bool {
	if !revision_inspection_request_is_valid(descriptor.request) do return false
	switch descriptor.state {
	case .Available:
		return descriptor.failure == .None && revision_inspection_usage_is_valid(descriptor.usage, descriptor.request)
	case .Truncated:
		return descriptor.failure == .Output_Limit && revision_inspection_usage_is_valid(descriptor.usage, descriptor.request)
	case .Failed:
		return descriptor.failure != .None && descriptor.usage == {}
	case .Invalid:
		return false
	}
	return false
}

/* revision_detail_request_revalidate proves target, parent choice, and generation remain current. */
revision_detail_request_revalidate :: proc(
	observation: ^History_Observation,
	request: Revision_Detail_Request,
) -> (Revision_Entry, bool, Failure_Code) {
	if !revision_detail_request_is_valid(request) do return {}, false, .Invalid_Request
	descriptor, available := history_observation_descriptor(observation)
	if !available || descriptor.generation != request.target.generation do return {}, false, .Stale_Observation
	if descriptor.state != .Available do return {}, false, .Revision_Unavailable
	for ordinal in 0 ..< descriptor.revision_count {
		entry, found := history_observation_revision(observation, ordinal)
		if !found do return {}, false, .Revision_Unavailable
		if entry.identity != request.target.revision do continue
		if !revision_parent_choice_matches(request.parent, entry.parents[:int(entry.parent_count)]) {
			return {}, false, .Revision_Unavailable
		}
		return entry, true, .None
	}
	return {}, false, .Revision_Unavailable
}

/* revision_range_request_revalidate proves both exact endpoints remain in one current History observation. */
revision_range_request_revalidate :: proc(
	observation: ^History_Observation,
	request: Revision_Range_Request,
) -> (bool, Failure_Code) {
	if !revision_range_request_is_valid(request) do return false, .Invalid_Request
	descriptor, available := history_observation_descriptor(observation)
	if !available || descriptor.generation != request.range.base.generation do return false, .Stale_Observation
	if descriptor.state != .Available do return false, .Revision_Unavailable
	base_found := false
	target_found := false
	for ordinal in 0 ..< descriptor.revision_count {
		entry, found := history_observation_revision(observation, ordinal)
		if !found do return false, .Revision_Unavailable
		if entry.identity == request.range.base.revision do base_found = true
		if entry.identity == request.range.target.revision do target_found = true
	}
	if !base_found || !target_found do return false, .Revision_Unavailable
	return true, .None
}

/* revision_inspection_request_revalidate dispatches stale-generation checks for one closed inspection family. */
revision_inspection_request_revalidate :: proc(
	observation: ^History_Observation,
	request: Revision_Inspection_Request,
) -> (bool, Failure_Code) {
	if !revision_inspection_request_is_valid(request) do return false, .Invalid_Request
	switch request.kind {
	case .Detail:
		_, current, failure := revision_detail_request_revalidate(observation, request.detail)
		return current, failure
	case .Range:
		return revision_range_request_revalidate(observation, request.range)
	case .Invalid:
		return false, .Invalid_Request
	}
	return false, .Invalid_Request
}

@(private)
revision_parent_choice_matches :: proc(choice: Revision_Parent_Choice, parents: []Revision_Identity) -> bool {
	if !revision_parent_choice_is_valid(choice) do return false
	switch choice.kind {
	case .Empty_Tree:
		return len(parents) == 0
	case .Parent:
		for parent in parents {
			if parent == choice.parent do return true
		}
		return false
	case .Invalid:
		return false
	}
	return false
}
