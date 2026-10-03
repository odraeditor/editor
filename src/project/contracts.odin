// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package project owns bounded Project identity, directory membership, and immutable snapshots.
package project

import "../document"
import "base:runtime"

/* KIBIBYTE is the binary byte unit used by Project resource policy. */
KIBIBYTE :: u64(1_024)
/* MEBIBYTE is 1,024 kibibytes. */
MEBIBYTE :: u64(1_024) * KIBIBYTE

/* MIN_CATALOG_PROJECTS is the smallest admitted catalog capacity. */
MIN_CATALOG_PROJECTS :: u32(16)
/* MAX_CATALOG_PROJECTS is the largest validated catalog capacity. */
MAX_CATALOG_PROJECTS :: u32(1_024)
/* DEFAULT_CATALOG_PROJECTS is the measured initial catalog capacity. */
DEFAULT_CATALOG_PROJECTS :: u32(128)
/* MIN_DIRECTORIES is the smallest admitted directory capacity per Project. */
MIN_DIRECTORIES :: u32(1)
/* MAX_DIRECTORIES is the largest validated directory capacity per Project. */
MAX_DIRECTORIES :: u32(256)
/* DEFAULT_DIRECTORIES is the measured initial directory capacity per Project. */
DEFAULT_DIRECTORIES :: u32(32)
/* MIN_NAME_BYTES is the smallest admitted Project-name bound. */
MIN_NAME_BYTES :: u64(64)
/* MAX_NAME_BYTES is the largest validated Project-name bound. */
MAX_NAME_BYTES :: u64(1_024)
/* DEFAULT_NAME_BYTES is the initial Project-name bound. */
DEFAULT_NAME_BYTES :: u64(256)
/* MAX_DURABLE_ID_BYTES bounds one filename-compatible registered Project identity. */
MAX_DURABLE_ID_BYTES :: u64(128)
/* MAX_DURABLE_ID_STORAGE_BYTES is fixed copied storage for one durable Project identity. */
MAX_DURABLE_ID_STORAGE_BYTES :: int(MAX_DURABLE_ID_BYTES)
/* MAX_NAME_STORAGE_BYTES is fixed copied storage for one validated Project name. */
MAX_NAME_STORAGE_BYTES :: int(MAX_NAME_BYTES)
/* MAX_DIRECTORY_PATH_STORAGE_BYTES is fixed copied storage under the document path ceiling. */
MAX_DIRECTORY_PATH_STORAGE_BYTES :: int(document.MAX_PATH_BYTES)
/* MIN_RETAINED_PATH_BYTES is the smallest aggregate active-Project path budget. */
MIN_RETAINED_PATH_BYTES :: 64 * KIBIBYTE
/* MAX_RETAINED_PATH_BYTES is the largest validated aggregate active-Project path budget. */
MAX_RETAINED_PATH_BYTES :: 16 * MEBIBYTE
/* DEFAULT_RETAINED_PATH_BYTES is the measured active-Project path budget. */
DEFAULT_RETAINED_PATH_BYTES :: 4 * MEBIBYTE
/* MIN_DESCRIPTOR_BATCH is the smallest admitted copied descriptor batch. */
MIN_DESCRIPTOR_BATCH :: u32(16)
/* MAX_DESCRIPTOR_BATCH is the largest validated copied descriptor batch. */
MAX_DESCRIPTOR_BATCH :: u32(4_096)
/* DEFAULT_DESCRIPTOR_BATCH is the initial copied descriptor batch bound. */
DEFAULT_DESCRIPTOR_BATCH :: u32(256)
/* MIN_FILE_CANDIDATES is the smallest admitted Project file-candidate capacity. */
MIN_FILE_CANDIDATES :: u32(256)
/* MAX_FILE_CANDIDATES is the largest validated Project file-candidate capacity. */
MAX_FILE_CANDIDATES :: u32(262_144)
/* DEFAULT_FILE_CANDIDATES is the initial Project file-candidate capacity. */
DEFAULT_FILE_CANDIDATES :: u32(65_536)
/* MIN_EXAMINED_ENTRIES is the smallest admitted reconciliation entry budget. */
MIN_EXAMINED_ENTRIES :: u32(1_024)
/* MAX_EXAMINED_ENTRIES is the largest validated reconciliation entry budget. */
MAX_EXAMINED_ENTRIES :: u32(1_048_576)
/* DEFAULT_EXAMINED_ENTRIES is the initial reconciliation entry budget. */
DEFAULT_EXAMINED_ENTRIES :: u32(262_144)
/* MIN_ENTRIES_PER_TURN is the smallest admitted incremental-work allowance. */
MIN_ENTRIES_PER_TURN :: u32(64)
/* MAX_ENTRIES_PER_TURN is the largest validated incremental-work allowance. */
MAX_ENTRIES_PER_TURN :: u32(8_192)
/* DEFAULT_ENTRIES_PER_TURN is the initial incremental-work allowance. */
DEFAULT_ENTRIES_PER_TURN :: u32(1_024)
/* MIN_DIRTY_MARKERS is the smallest admitted stale-directory marker capacity. */
MIN_DIRTY_MARKERS :: u32(16)
/* MAX_DIRTY_MARKERS is the largest validated stale-directory marker capacity. */
MAX_DIRTY_MARKERS :: u32(4_096)
/* DEFAULT_DIRTY_MARKERS is the initial stale-directory marker capacity. */
DEFAULT_DIRTY_MARKERS :: u32(256)
/* MIN_DIAGNOSTICS is the smallest admitted retained diagnostic capacity. */
MIN_DIAGNOSTICS :: u32(16)
/* MAX_DIAGNOSTICS is the largest validated retained diagnostic capacity. */
MAX_DIAGNOSTICS :: u32(1_024)
/* DEFAULT_DIAGNOSTICS is the initial retained diagnostic capacity. */
DEFAULT_DIAGNOSTICS :: u32(128)
/* MIN_DIAGNOSTIC_BYTES is the smallest admitted retained diagnostic byte budget. */
MIN_DIAGNOSTIC_BYTES :: 64 * KIBIBYTE
/* MAX_DIAGNOSTIC_BYTES is the largest validated retained diagnostic byte budget. */
MAX_DIAGNOSTIC_BYTES :: 8 * MEBIBYTE
/* DEFAULT_DIAGNOSTIC_BYTES is the initial retained diagnostic byte budget. */
DEFAULT_DIAGNOSTIC_BYTES :: 1 * MEBIBYTE

/* Owner_ID identifies the editor coordinator that owns one Project registry. */
Owner_ID :: distinct u64
/* Owner_Generation identifies one live coordinator generation. */
Owner_Generation :: distinct u64
/* Project_ID identifies one temporary or durable Project; zero is invalid. */
Project_ID :: distinct u64
/* Project_Generation identifies one immutable Project publication. */
Project_Generation :: distinct u64
/* Membership_ID identifies one directory relationship within a Project. */
Membership_ID :: distinct u64
/* Membership_Generation rejects stale references after membership slot reuse. */
Membership_Generation :: distinct u32
/* Observation_Generation identifies one complete filesystem observation. */
Observation_Generation :: distinct u64
/* File_Enumeration_Generation identifies one complete Project file-candidate projection. */
File_Enumeration_Generation :: distinct u64

/* Owner_Handle is a checked reference to one Project-registry owner generation. */
Owner_Handle :: struct {
	id:         Owner_ID,
	generation: Owner_Generation,
}

/* Project_Handle is a checked reference to one exact Project publication. */
Project_Handle :: struct {
	owner:      Owner_Handle,
	id:         Project_ID,
	generation: Project_Generation,
}

/* Membership_Handle is a checked reference to one exact directory relationship. */
Membership_Handle :: struct {
	project:    Project_Handle,
	id:         Membership_ID,
	slot:       u32,
	generation: Membership_Generation,
}

/* Trust_State records whether one Project-directory membership may contribute executable behavior. */
Trust_State :: enum u8 {
	Invalid,
	Untrusted,
	Trusted,
}

/* Restricted_Behavior names file-safe and executable directory capabilities. */
Restricted_Behavior :: enum u8 {
	Invalid,
	Read,
	Edit,
	Save,
	Search,
	Configuration,
	Tool,
	Process,
	Language_Service,
	Extension,
	Command_Definition,
	Keymap_Definition,
}

/* Availability records the latest bounded observation of one Project directory. */
Availability :: enum u8 {
	Unknown,
	Available,
	Unavailable,
	Stale,
}

/* Project_Name owns one bounded copied UTF-8 display name. */
Project_Name :: struct {
	bytes:  [MAX_NAME_STORAGE_BYTES]u8,
	length: u32,
}

/* Project_Durable_ID owns one copied registered Project identity; temporary Projects are empty. */
Project_Durable_ID :: struct {
	bytes:  [MAX_DURABLE_ID_STORAGE_BYTES]u8,
	length: u32,
}

/* Directory_Path owns one copied path under the existing document path ceiling. */
Directory_Path :: struct {
	bytes:  [MAX_DIRECTORY_PATH_STORAGE_BYTES]u8,
	length: u32,
}

/* Directory_Proposal describes one normalized membership before validation and publication. */
Directory_Proposal :: struct {
	path:  string,
	trust: Trust_State,
}

/* Snapshot_Request describes one complete replacement Project candidate. */
Snapshot_Request :: struct {
	owner:       Owner_Handle,
	project_id:  Project_ID,
	project_generation: Project_Generation,
	durable_id:  string,
	name:        string,
	directories: []Directory_Proposal,
	temporary:   bool,
}

/* Directory_Open_Resolution identifies one bounded catalog-matching outcome. */
Directory_Open_Resolution :: enum u8 {
	Invalid,
	Unregistered,
	Registered,
	Ambiguous,
}

/* Directory_Open_Request copies one normalized path and its catalog result. */
Directory_Open_Request :: struct {
	owner:                       Owner_Handle,
	expected:                    Project_Handle,
	expected_catalog_generation: u64,
	normalized_path:             string,
	matching_projects:           u32,
	snapshot:                    Snapshot_Request,
}

/* Directory_Open_Preparation owns an unpublished activation or ambiguity result. */
Directory_Open_Preparation :: struct {
	snapshot:                    Prepared_Snapshot,
	owner:                       Owner_Handle,
	expected:                    Project_Handle,
	expected_catalog_generation: u64,
	matching_projects:           u32,
	resolution:                  Directory_Open_Resolution,
}

/* Membership_Descriptor is one copied immutable directory relationship. */
Membership_Descriptor :: struct {
	handle:       Membership_Handle,
	path:         Directory_Path,
	trust:        Trust_State,
	availability: Availability,
}

/* Project_Descriptor is one copied immutable Project summary. */
Project_Descriptor :: struct {
	handle:                 Project_Handle,
	durable_id:             Project_Durable_ID,
	name:                   Project_Name,
	directory_count:        u32,
	trusted_directories:    u32,
	unavailable_directories: u32,
	temporary:              bool,
}

/* Descriptor_Batch owns copied Project membership descriptors until explicit close. */
Descriptor_Batch :: struct {
	state:       rawptr,
	descriptors: []Membership_Descriptor,
}

/* File_Candidate_Descriptor is one copied generation-bound regular-file candidate. */
File_Candidate_Descriptor :: struct {
	dir:              Dir_Handle,
	project:          Project_Handle,
	generation:       File_Enumeration_Generation,
	path:             string,
	membership_count: u32,
}

/* File_Candidate_Batch owns copied candidate descriptors and path storage. */
File_Candidate_Batch :: struct {
	state:       rawptr,
	dir:         Dir_Handle,
	project:     Project_Handle,
	generation:  File_Enumeration_Generation,
	descriptors: []File_Candidate_Descriptor,
}

/* File_Enumeration_Result reports one bounded traversal turn or complete publication. */
File_Enumeration_Result :: struct {
	dir:              Dir_Handle,
	project:          Project_Handle,
	generation:       File_Enumeration_Generation,
	processed_entries: u32,
	examined_entries: u32,
	candidate_count:  u32,
	complete:         bool,
	cancelled:        bool,
}

/* File_Enumerator owns one private incremental traversal until close. */
File_Enumerator :: struct {
	state:  rawptr,
	closed: bool,
}

/* Policy_Field identifies one Project policy field in validation diagnostics. */
Policy_Field :: enum u8 {
	Invalid,
	Catalog_Projects,
	Directories,
	Name_Bytes,
	Retained_Path_Bytes,
	Descriptor_Batch,
	File_Candidates,
	Examined_Entries,
	Entries_Per_Turn,
	Dirty_Markers,
	Diagnostics,
	Diagnostic_Bytes,
}

/* Policy contains every Project registry, copied-result, and incremental-work bound. */
Policy :: struct {
	catalog_projects:    u32,
	directories:         u32,
	name_bytes:          u64,
	retained_path_bytes: u64,
	descriptor_batch:    u32,
	file_candidates:     u32,
	examined_entries:    u32,
	entries_per_turn:    u32,
	dirty_markers:       u32,
	diagnostics:         u32,
	diagnostic_bytes:    u64,
}

/* DEFAULT_POLICY is the measured initial Project resource policy. */
DEFAULT_POLICY :: Policy {
	catalog_projects = DEFAULT_CATALOG_PROJECTS,
	directories = DEFAULT_DIRECTORIES,
	name_bytes = DEFAULT_NAME_BYTES,
	retained_path_bytes = DEFAULT_RETAINED_PATH_BYTES,
	descriptor_batch = DEFAULT_DESCRIPTOR_BATCH,
	file_candidates = DEFAULT_FILE_CANDIDATES,
	examined_entries = DEFAULT_EXAMINED_ENTRIES,
	entries_per_turn = DEFAULT_ENTRIES_PER_TURN,
	dirty_markers = DEFAULT_DIRTY_MARKERS,
	diagnostics = DEFAULT_DIAGNOSTICS,
	diagnostic_bytes = DEFAULT_DIAGNOSTIC_BYTES,
}

/* Resource_Usage reports exact retained Project counts and storage. */
Resource_Usage :: struct {
	projects:             u32,
	directories:          u32,
	trusted_directories:  u32,
	unavailable_directories: u32,
	retained_name_bytes:  u64,
	retained_path_bytes:  u64,
	registry_bytes:       u64,
	dirty_markers:        u32,
	diagnostics:          u32,
	diagnostic_bytes:     u64,
}

/* Reservation records the complete charge required before one Project publication. */
Reservation :: struct {
	projects:            u32,
	directories:         u32,
	name_bytes:          u64,
	path_bytes:          u64,
	registry_bytes:      u64,
	dirty_markers:       u32,
	diagnostics:         u32,
	diagnostic_bytes:    u64,
}

/* Ownership_State records which lifecycle owns one Project snapshot. */
Ownership_State :: enum u8 {
	Invalid,
	Private_Preparation,
	Published_Registry,
	Retired_Cleanup,
	Released,
}

/* Ownership_Snapshot is a copied account of one Project snapshot and its owner. */
Ownership_Snapshot :: struct {
	project:     Project_Handle,
	state:       Ownership_State,
	reservation: Reservation,
}

/* Operation identifies the Project transition that produced a result or failure. */
Operation :: enum u8 {
	None,
	Initialize,
	Prepare,
	Publish,
	Abort,
	Inspect,
	Find_Membership,
	Classify_Path,
	Replace_Membership,
	Project_Descriptors,
	Membership_Descriptors,
	Initialize_Observations,
	Mark_Dirty,
	Refresh,
	Reconcile,
	Observation_Descriptors,
	Initialize_File_Enumeration,
	Enumerate_Files,
	File_Candidates,
	Cleanup,
	Close,
	Prepare_Directory_Open,
	Publish_Directory_Open,
}

/* Failure_Code classifies expected Project rejection without partial publication. */
Failure_Code :: enum u16 {
	None,
	Invalid_Registry,
	Closed_Registry,
	Invalid_Owner,
	Wrong_Owner,
	Stale_Owner,
	Invalid_Project,
	Stale_Project,
	Invalid_Dir,
	Stale_Dir,
	Invalid_Membership,
	Stale_Membership,
	Invalid_Policy,
	Policy_Range,
	Policy_Relationship,
	Invalid_Name,
	Name_Limit,
	Invalid_Path,
	Path_Limit,
	Duplicate_Path,
	Directory_Limit,
	Retained_Path_Limit,
	Descriptor_Limit,
	File_Candidate_Limit,
	Examined_Entry_Limit,
	Filesystem_Failure,
	Dirty_Marker_Limit,
	Identity_Limit,
	Persistent_Memory_Limit,
	Temporary_Memory_Limit,
	Cancelled,
	Invariant_Violation,
	Stale_Catalog,
	Project_Switch_Unavailable,
	Invalid_Resolution,
}

/* Failure_Context identifies the rejected Project object and resource bound. */
Failure_Context :: struct {
	code:       Failure_Code,
	operation:  Operation,
	field:      Policy_Field,
	owner:      Owner_Handle,
	project:    Project_Handle,
	membership: Membership_Handle,
	minimum:    u64,
	maximum:    u64,
	actual:     u64,
}

/* Cleanup_Progress reports bounded deterministic Project release work. */
Cleanup_Progress :: struct {
	processed_directories: u32,
	remaining_directories: u32,
	released_bytes:        u64,
	complete:              bool,
	first_failure:         Failure_Context,
}

/* Allocator_Set supplies Project-retained and per-operation allocation domains. */
Allocator_Set :: struct {
	// The caller keeps this allocator alive until registry_close completes.
	persistent: runtime.Allocator,
	// The caller keeps this allocator alive for every Project operation.
	temporary: runtime.Allocator,
}

/* Registry is the opaque owner of Project identity, membership, and accounting. */
Registry :: struct {
	state:  rawptr,
	closed: bool,
}

/* Prepared_Snapshot privately owns one unpublished immutable Project candidate. */
Prepared_Snapshot :: struct {
	state: rawptr,
}

/* owner_handle_is_valid reports whether an owner handle has nonzero identity. */
owner_handle_is_valid :: proc(handle: Owner_Handle) -> bool {
	return handle.id != Owner_ID(0) && handle.generation != Owner_Generation(0)
}

/* project_handle_is_valid reports whether a Project handle has nonzero checked identity. */
project_handle_is_valid :: proc(handle: Project_Handle) -> bool {
	return owner_handle_is_valid(handle.owner) && handle.id != Project_ID(0) &&
	       handle.generation != Project_Generation(0)
}

/* membership_handle_is_valid reports whether a membership handle has nonzero checked identity. */
membership_handle_is_valid :: proc(handle: Membership_Handle) -> bool {
	return project_handle_is_valid(handle.project) && handle.id != Membership_ID(0) &&
	       handle.generation != Membership_Generation(0)
}

/* trust_allows_behavior enforces the restricted surface for one membership. */
trust_allows_behavior :: proc(trust: Trust_State, behavior: Restricted_Behavior) -> bool {
	switch behavior {
	case .Read, .Edit, .Save, .Search:
		return trust == .Untrusted || trust == .Trusted
	case .Configuration, .Tool, .Process, .Language_Service, .Extension,
	     .Command_Definition, .Keymap_Definition:
		return trust == .Trusted
	case .Invalid:
		return false
	}
	return false
}

/* project_name_text borrows validated text from one copied Project name. */
project_name_text :: proc(name: ^Project_Name) -> string {
	if name == nil || name.length > u32(len(name.bytes)) {
		return ""
	}
	return string(name.bytes[:name.length])
}

/* directory_path_text borrows validated text from one copied directory path. */
directory_path_text :: proc(path: ^Directory_Path) -> string {
	if path == nil || path.length > u32(len(path.bytes)) {
		return ""
	}
	return string(path.bytes[:path.length])
}

/* policy_validate checks every Project limit and cross-field relationship. */
policy_validate :: proc(policy: Policy) -> (ok: bool, failure: Failure_Context) {
	checks := [?]struct {actual, minimum, maximum: u64, field: Policy_Field} {
		{u64(policy.catalog_projects), u64(MIN_CATALOG_PROJECTS), u64(MAX_CATALOG_PROJECTS), .Catalog_Projects},
		{u64(policy.directories), u64(MIN_DIRECTORIES), u64(MAX_DIRECTORIES), .Directories},
		{policy.name_bytes, MIN_NAME_BYTES, MAX_NAME_BYTES, .Name_Bytes},
		{policy.retained_path_bytes, MIN_RETAINED_PATH_BYTES, MAX_RETAINED_PATH_BYTES, .Retained_Path_Bytes},
		{u64(policy.descriptor_batch), u64(MIN_DESCRIPTOR_BATCH), u64(MAX_DESCRIPTOR_BATCH), .Descriptor_Batch},
		{u64(policy.file_candidates), u64(MIN_FILE_CANDIDATES), u64(MAX_FILE_CANDIDATES), .File_Candidates},
		{u64(policy.examined_entries), u64(MIN_EXAMINED_ENTRIES), u64(MAX_EXAMINED_ENTRIES), .Examined_Entries},
		{u64(policy.entries_per_turn), u64(MIN_ENTRIES_PER_TURN), u64(MAX_ENTRIES_PER_TURN), .Entries_Per_Turn},
		{u64(policy.dirty_markers), u64(MIN_DIRTY_MARKERS), u64(MAX_DIRTY_MARKERS), .Dirty_Markers},
		{u64(policy.diagnostics), u64(MIN_DIAGNOSTICS), u64(MAX_DIAGNOSTICS), .Diagnostics},
		{policy.diagnostic_bytes, MIN_DIAGNOSTIC_BYTES, MAX_DIAGNOSTIC_BYTES, .Diagnostic_Bytes},
	}
	for check in checks {
		if check.actual < check.minimum || check.actual > check.maximum {
			return false, Failure_Context{
				code = .Policy_Range,
				field = check.field,
				minimum = check.minimum,
				maximum = check.maximum,
				actual = check.actual,
			}
		}
	}
	if policy.entries_per_turn > policy.examined_entries {
		return false, Failure_Context{
			code = .Policy_Relationship,
			field = .Entries_Per_Turn,
			maximum = u64(policy.examined_entries),
			actual = u64(policy.entries_per_turn),
		}
	}
	return true, {}
}
