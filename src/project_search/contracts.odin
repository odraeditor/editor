// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package project_search owns provider-neutral bounded Project text-search contracts.
package project_search

import project_core "../project"
import "../search"
import "base:runtime"

/* KIBIBYTE is the byte multiplier used by Project search resource limits. */
KIBIBYTE :: u64(1_024)
/* MEBIBYTE is the larger byte multiplier used by Project search resource limits. */
MEBIBYTE :: u64(1_024) * KIBIBYTE

/* MAX_ROOTS is the largest admitted root set for one Project search. */
MAX_ROOTS :: u32(256)
/* MAX_FILTER_PATTERNS is the largest admitted include or exclude pattern set. */
MAX_FILTER_PATTERNS :: u32(256)
/* MAX_FILTER_PATTERN_BYTES bounds one include or exclude pattern. */
MAX_FILTER_PATTERN_BYTES :: u64(4 * KIBIBYTE)
/* MAX_FILES is the largest admitted file set for one Project search. */
MAX_FILES :: u32(262_144)
/* MAX_EXAMINED_ENTRIES is the largest admitted filesystem traversal. */
MAX_EXAMINED_ENTRIES :: u32(1_048_576)
/* MAX_MATCHES is the largest admitted retained match set. */
MAX_MATCHES :: u32(262_144)
/* MAX_FILE_BYTES is the largest admitted source file. */
MAX_FILE_BYTES :: u64(64 * MEBIBYTE)
/* MAX_TOTAL_READ_BYTES bounds cumulative source reads for one request. */
MAX_TOTAL_READ_BYTES :: u64(4 * 1_024 * MEBIBYTE)
/* MAX_RETAINED_BYTES bounds persistent provider memory for one request. */
MAX_RETAINED_BYTES :: u64(128 * MEBIBYTE)
/* MAX_TEMPORARY_BYTES bounds transient provider memory for one request. */
MAX_TEMPORARY_BYTES :: u64(128 * MEBIBYTE)
/* MAX_FILES_PER_TURN bounds cooperative file work before yielding. */
MAX_FILES_PER_TURN :: u32(256)
/* MAX_ENTRIES_PER_TURN bounds cooperative traversal work before yielding. */
MAX_ENTRIES_PER_TURN :: u32(8_192)
/* MAX_READ_BYTES_PER_TURN bounds cooperative I/O work before yielding. */
MAX_READ_BYTES_PER_TURN :: u64(16 * MEBIBYTE)
/* MAX_CANCELLATION_BYTES bounds bytes read between cancellation checks. */
MAX_CANCELLATION_BYTES :: u64(256 * KIBIBYTE)

/* Request_ID identifies one admitted Project search request; zero is invalid. */
Request_ID :: distinct u64
/* Request_Generation distinguishes replacement and cancellation lifetimes. */
Request_Generation :: distinct u64
/* Provider_ID identifies one Project search provider instance; zero is invalid. */
Provider_ID :: distinct u64
/* Provider_Generation distinguishes provider instance lifetimes. */
Provider_Generation :: distinct u64
/* Result_Generation identifies one published result generation. */
Result_Generation :: distinct u64
/* File_ID identifies one file admitted by the active request. */
File_ID :: distinct u64

/* Hidden_Policy selects whether hidden filesystem entries are searched. */
Hidden_Policy :: enum u8 {
	Invalid,
	Exclude,
	Include,
}

/* Ignore_Policy selects whether provider ignore rules are respected. */
Ignore_Policy :: enum u8 {
	Invalid,
	Respect,
	Include_Ignored,
}

/* Binary_Policy selects whether binary-looking files are searched. */
Binary_Policy :: enum u8 {
	Invalid,
	Exclude,
	Include,
}

/* Lifecycle reports the explicit Project search provider state. */
Lifecycle :: enum u8 {
	Invalid,
	Prepared,
	Running,
	Complete,
	Cancelled,
	Failed,
	Closed,
}

/* Completeness distinguishes terminal complete results from bounded partial results. */
Completeness :: enum u8 {
	Invalid,
	Complete,
	Incomplete,
}

/* Failure_Code classifies Project search admission, resource, and lifecycle failures. */
Failure_Code :: enum u8 {
	None,
	Invalid_Request,
	Invalid_Project,
	Stale_Project,
	Invalid_Root,
	Stale_Membership,
	Duplicate_Root,
	Root_Limit,
	Invalid_Pattern,
	Pattern_Limit,
	Invalid_Search_Policy,
	Invalid_File_Policy,
	Filter_Limit,
	Invalid_Limits,
	File_Limit,
	Match_Limit,
	File_Byte_Limit,
	Read_Byte_Limit,
	Retained_Memory_Limit,
	Temporary_Memory_Limit,
	Filesystem,
	Malformed_UTF8,
	Binary_File,
	Invalid_Expression,
	Stale_Fingerprint,
	Stale_Generation,
	Cancelled,
	Closed,
	Arithmetic_Overflow,
}

/* Root binds one normalized search root to exact Project membership authority. */
Root :: struct {
	membership: project_core.Membership_Handle,
	path:       project_core.Directory_Path,
}

/* Policy combines shared text matching with explicit Project file policies. */
Policy :: struct {
	search:           search.Policy,
	hidden:           Hidden_Policy,
	ignored:          Ignore_Policy,
	binary:           Binary_Policy,
	include_patterns: []string,
	exclude_patterns: []string,
}

/* Limits bounds roots, traversal, I/O, retained results, and cooperative work. */
Limits :: struct {
	roots:               u32,
	filter_patterns:     u32,
	filter_pattern_bytes: u64,
	files:               u32,
	examined_entries:    u32,
	matches:             u32,
	file_bytes:          u64,
	total_read_bytes:    u64,
	retained_bytes:      u64,
	temporary_bytes:     u64,
	files_per_turn:      u32,
	entries_per_turn:    u32,
	read_bytes_per_turn: u64,
	cancellation_bytes:  u64,
}

/* DEFAULT_LIMITS is the measured factory bound set for Project text search. */
DEFAULT_LIMITS :: Limits {
	roots = 32,
	filter_patterns = 64,
	filter_pattern_bytes = 1 * KIBIBYTE,
	files = 65_536,
	examined_entries = 262_144,
	matches = 65_536,
	file_bytes = 16 * MEBIBYTE,
	total_read_bytes = 1_024 * MEBIBYTE,
	retained_bytes = 64 * MEBIBYTE,
	temporary_bytes = 32 * MEBIBYTE,
	files_per_turn = 64,
	entries_per_turn = 1_024,
	read_bytes_per_turn = 16 * MEBIBYTE,
	cancellation_bytes = 64 * KIBIBYTE,
}

/* Request is one immutable provider-neutral Project text search request. */
Request :: struct {
	id:                  Request_ID,
	generation:          Request_Generation,
	provider:            Provider_ID,
	provider_generation: Provider_Generation,
	project:             project_core.Project_Handle,
	query_id:            search.Query_ID,
	pattern_kind:        search.Pattern_Kind,
	pattern:             string,
	policy:              Policy,
	search_limits:       search.Limits,
	limits:              Limits,
	roots:               []Root,
	continuation:        Continuation,
}

/* Source_Fingerprint preserves source identity for safe navigation and refresh. */
Source_Fingerprint :: struct {
	present:              bool,
	device:               u64,
	inode:                u64,
	size:                 u64,
	modified_seconds:     i64,
	modified_nanoseconds: i32,
}

/* Match is one source-backed Project result with byte and display coordinates. */
Match :: struct {
	id:          u64,
	file:        File_ID,
	root:        project_core.Membership_Handle,
	path:        string,
	fingerprint: Source_Fingerprint,
	start:       u64,
	end:         u64,
	line:        u64,
	column:      u64,
	preview:     string,
	preview_match_start: u32,
	preview_match_end:   u32,
}

/* Progress exposes bounded traversal and matching progress. */
Progress :: struct {
	roots_completed: u32,
	entries_examined: u32,
	files_examined:  u32,
	files_searched:  u32,
	bytes_read:      u64,
	matches:         u32,
	cancellation_checks: u64,
}

/* Continuation identifies the next bounded Project search work position. */
Continuation :: struct {
	present:    bool,
	root_index: u32,
	file_index: u64,
	byte_offset: u64,
}

/* Usage reports retained, transient, I/O, and work consumption. */
Usage :: struct {
	retained_bytes:       u64,
	temporary_peak_bytes: u64,
	read_bytes:           u64,
	files:                u32,
	matches:              u32,
	work_items:           u64,
}

/* Inspection exposes provider identity, lifecycle, progress, and resource state. */
Inspection :: struct {
	request_id:          Request_ID,
	request_generation:  Request_Generation,
	provider:            Provider_ID,
	provider_generation: Provider_Generation,
	project:             project_core.Project_Handle,
	result_generation:   Result_Generation,
	lifecycle:           Lifecycle,
	completeness:        Completeness,
	progress:            Progress,
	continuation:        Continuation,
	usage:               Usage,
}

/* Cancellation records one generation-scoped cancellation request. */
Cancellation :: struct {
	generation: Request_Generation,
	requested:  bool,
}

/* Failure preserves the authority and bound relevant to one failed request. */
Failure :: struct {
	code:               Failure_Code,
	request_id:         Request_ID,
	request_generation: Request_Generation,
	project:            project_core.Project_Handle,
	membership:         project_core.Membership_Handle,
	file:               File_ID,
	limit:              u64,
	actual:             u64,
}

/* Provider owns the identity and lifecycle of one Project search instance. */
Provider :: struct {
	id:         Provider_ID,
	generation: Provider_Generation,
	lifecycle:  Lifecycle,
}

/* Allocator_Set separates provider-owned state from per-turn scratch storage. */
Allocator_Set :: struct {
	persistent: runtime.Allocator,
	temporary:  runtime.Allocator,
}

/* Native_Provider owns one bounded maintained Project search lifecycle. */
Native_Provider :: struct {
	state: rawptr,
}

/* Native_View borrows the current provider generation until its next mutation. */
Native_View :: struct {
	inspection: Inspection,
	request:    Request,
	matches:    []Match,
}

/* request_is_valid checks complete provider-neutral Project search admission. */
request_is_valid :: proc(request: Request) -> bool {
	if request.id == Request_ID(0) || request.generation == Request_Generation(0) ||
	   request.provider == Provider_ID(0) || request.provider_generation == Provider_Generation(0) ||
	   !project_core.project_handle_is_valid(request.project) || request.query_id == search.Query_ID(0) ||
	   (request.pattern_kind != .Literal && request.pattern_kind != .Regular_Expression) ||
	   len(request.pattern) == 0 ||
	   u64(len(request.pattern)) > request.search_limits.pattern_bytes ||
	   !search.limits_are_valid(request.search_limits) ||
	   !search_policy_is_valid(request.policy.search) || !policy_is_valid(request.policy, request.limits) ||
	   !limits_are_valid(request.limits) || len(request.roots) == 0 ||
	   request.search_limits.scan_window_bytes > request.limits.cancellation_bytes ||
	   request.search_limits.temporary_bytes + request.limits.file_bytes > request.limits.temporary_bytes ||
	   len(request.roots) > int(request.limits.roots) {
		return false
	}
	for root, index in request.roots {
		if !project_core.membership_handle_is_valid(root.membership) ||
		   root.membership.project != request.project || root.path.length == 0 {
			return false
		}
		for prior in 0 ..< index do if request.roots[prior].membership == root.membership do return false
	}
	return true
}

/* policy_is_valid checks explicit matching and filesystem selection policies. */
policy_is_valid :: proc(policy: Policy, limits := DEFAULT_LIMITS) -> bool {
	if !limits_are_valid(limits) || !search_policy_is_valid(policy.search) ||
	   policy.hidden == .Invalid || policy.ignored == .Invalid || policy.binary == .Invalid ||
	   len(policy.include_patterns) + len(policy.exclude_patterns) > int(limits.filter_patterns) {
		return false
	}
	for pattern in policy.include_patterns do if len(pattern) == 0 || u64(len(pattern)) > limits.filter_pattern_bytes do return false
	for pattern in policy.exclude_patterns do if len(pattern) == 0 || u64(len(pattern)) > limits.filter_pattern_bytes do return false
	return true
}

/* limits_are_valid checks every Project search resource bound. */
limits_are_valid :: proc(limits: Limits) -> bool {
	return limits.roots > 0 && limits.roots <= MAX_ROOTS &&
		limits.filter_patterns > 0 && limits.filter_patterns <= MAX_FILTER_PATTERNS &&
		limits.filter_pattern_bytes > 0 && limits.filter_pattern_bytes <= MAX_FILTER_PATTERN_BYTES &&
		limits.files > 0 && limits.files <= MAX_FILES &&
		limits.examined_entries >= limits.files && limits.examined_entries <= MAX_EXAMINED_ENTRIES &&
		limits.matches > 0 && limits.matches <= MAX_MATCHES &&
		limits.file_bytes > 0 && limits.file_bytes <= MAX_FILE_BYTES &&
		limits.total_read_bytes >= limits.file_bytes && limits.total_read_bytes <= MAX_TOTAL_READ_BYTES &&
		limits.retained_bytes > 0 && limits.retained_bytes <= MAX_RETAINED_BYTES &&
		limits.temporary_bytes > 0 && limits.temporary_bytes <= MAX_TEMPORARY_BYTES &&
		limits.files_per_turn > 0 && limits.files_per_turn <= MAX_FILES_PER_TURN &&
		limits.entries_per_turn > 0 && limits.entries_per_turn <= MAX_ENTRIES_PER_TURN &&
		limits.read_bytes_per_turn >= limits.file_bytes &&
		limits.read_bytes_per_turn > 0 && limits.read_bytes_per_turn <= MAX_READ_BYTES_PER_TURN &&
		limits.cancellation_bytes > 0 && limits.cancellation_bytes <= MAX_CANCELLATION_BYTES
}

/* source_fingerprint_is_valid checks navigable source identity metadata. */
source_fingerprint_is_valid :: proc(fingerprint: Source_Fingerprint) -> bool {
	return fingerprint.present && fingerprint.modified_nanoseconds >= 0 &&
		fingerprint.modified_nanoseconds < 1_000_000_000
}

/* match_is_valid checks one match against its immutable request authority. */
match_is_valid :: proc(match: Match, request: Request) -> bool {
	return request_is_valid(request) && match.id != 0 && match.file != File_ID(0) &&
		match.root.project == request.project && len(match.path) > 0 &&
		source_fingerprint_is_valid(match.fingerprint) && match.start <= match.end &&
		match.end <= match.fingerprint.size
}

/* cancellation_request marks the exact active request generation cancelled. */
cancellation_request :: proc(cancellation: ^Cancellation, generation: Request_Generation) -> bool {
	if cancellation == nil || generation == Request_Generation(0) || cancellation.generation != generation do return false
	cancellation.requested = true
	return true
}

/* cancellation_is_requested reports cancellation only for the exact generation. */
cancellation_is_requested :: proc(cancellation: ^Cancellation, generation: Request_Generation) -> bool {
	return cancellation != nil && generation != Request_Generation(0) &&
		cancellation.generation == generation && cancellation.requested
}

/* provider_transition applies one admitted explicit lifecycle transition. */
provider_transition :: proc(provider: ^Provider, expected: Lifecycle, next: Lifecycle) -> bool {
	if provider == nil || provider.id == Provider_ID(0) || provider.generation == Provider_Generation(0) ||
	   provider.lifecycle != expected {
		return false
	}
	allowed := expected == .Prepared && next == .Running ||
		expected == .Running && (next == .Complete || next == .Cancelled || next == .Failed) ||
		(expected == .Complete || expected == .Cancelled || expected == .Failed) && next == .Closed
	if !allowed do return false
	provider.lifecycle = next
	return true
}

@(private)
search_policy_is_valid :: proc(policy: search.Policy) -> bool {
	return policy.case_mode != .Invalid && policy.boundary_mode != .Invalid &&
		policy.whitespace_mode != .Invalid
}
