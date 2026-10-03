// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package project owns checked target Dir and Project lifecycle contracts.
package project

import "core:strings"
import "core:unicode/utf8"

/* TARGET_PROJECT_FORMAT_VERSION identifies the local one-root Project schema. */
TARGET_PROJECT_FORMAT_VERSION :: u32(2)
/* TARGET_REFERENCE_FORMAT_VERSION identifies global Project discovery references. */
TARGET_REFERENCE_FORMAT_VERSION :: u32(1)
/* PROMOTION_SUPPRESSION_FORMAT_VERSION identifies the global prompt-preference schema. */
PROMOTION_SUPPRESSION_FORMAT_VERSION :: u32(1)
/* MIGRATION_FORMAT_VERSION identifies the explicit legacy migration journal schema. */
MIGRATION_FORMAT_VERSION :: u32(1)

/* MIN_PROMOTION_SUPPRESSIONS is the smallest admitted prompt-preference capacity. */
MIN_PROMOTION_SUPPRESSIONS :: u32(16)
/* MAX_PROMOTION_SUPPRESSIONS is the largest validated prompt-preference capacity. */
MAX_PROMOTION_SUPPRESSIONS :: u32(4_096)
/* DEFAULT_PROMOTION_SUPPRESSIONS is the measured initial prompt-preference capacity. */
DEFAULT_PROMOTION_SUPPRESSIONS :: u32(256)
/* MIN_MIGRATION_ENTRIES is the smallest admitted migration-journal capacity. */
MIN_MIGRATION_ENTRIES :: u32(16)
/* MAX_MIGRATION_ENTRIES is the largest validated migration-journal capacity. */
MAX_MIGRATION_ENTRIES :: u32(4_096)
/* DEFAULT_MIGRATION_ENTRIES is the initial migration-journal capacity. */
DEFAULT_MIGRATION_ENTRIES :: u32(256)
/* MIN_LIFECYCLE_RECORD_BYTES is the smallest admitted retained record budget. */
MIN_LIFECYCLE_RECORD_BYTES :: 64 * KIBIBYTE
/* MAX_LIFECYCLE_RECORD_BYTES is the largest validated retained record budget. */
MAX_LIFECYCLE_RECORD_BYTES :: 64 * MEBIBYTE
/* DEFAULT_LIFECYCLE_RECORD_BYTES is the measured initial retained record budget. */
DEFAULT_LIFECYCLE_RECORD_BYTES :: 8 * MEBIBYTE

/* Dir_ID identifies one ordinary root publication in an editor session. */
Dir_ID :: distinct u64
/* Dir_Generation rejects references after a root replacement or removal. */
Dir_Generation :: distinct u64

/* Dir_Handle is a checked reference to one ordinary session root. */
Dir_Handle :: struct {
	owner:      Owner_Handle,
	id:         Dir_ID,
	generation: Dir_Generation,
}

/* Local_Project_Proposal describes one complete one-root Project record. */
Local_Project_Proposal :: struct {
	format_version: u32,
	id:             string,
	generation:     u64,
	name:           string,
	root:           string,
	trust:          Trust_State,
}

/* Project_Discovery_Proposal describes one rebuildable global Project reference. */
Project_Discovery_Proposal :: struct {
	format_version:              u32,
	id:                          string,
	expected_project_generation: u64,
	root:                        string,
}

/* Promotion_Suppression_Proposal describes one global Dir prompt preference. */
Promotion_Suppression_Proposal :: struct {
	format_version: u32,
	generation:     u64,
	root:           string,
}

/* Migration_State classifies one explicit legacy conversion journal entry. */
Migration_State :: enum u8 {
	Invalid,
	Planned,
	Staged,
	Published,
	Rejected,
}

/* Migration_Proposal describes one source-preserving legacy conversion entry. */
Migration_Proposal :: struct {
	format_version: u32,
	generation:     u64,
	source_id:      string,
	source_path:    string,
	target_id:      string,
	state:          Migration_State,
}

/* Lifecycle_Policy_Field identifies one target lifecycle resource bound. */
Lifecycle_Policy_Field :: enum u8 {
	Invalid,
	Projects,
	Promotion_Suppressions,
	Migration_Entries,
	Record_Bytes,
}

/* Lifecycle_Policy bounds target Project discovery, preferences, and migration state. */
Lifecycle_Policy :: struct {
	projects:               u32,
	promotion_suppressions: u32,
	migration_entries:      u32,
	record_bytes:           u64,
}

/* DEFAULT_LIFECYCLE_POLICY is the measured target Project lifecycle policy. */
DEFAULT_LIFECYCLE_POLICY :: Lifecycle_Policy {
	projects = DEFAULT_CATALOG_PROJECTS,
	promotion_suppressions = DEFAULT_PROMOTION_SUPPRESSIONS,
	migration_entries = DEFAULT_MIGRATION_ENTRIES,
	record_bytes = DEFAULT_LIFECYCLE_RECORD_BYTES,
}

/* Lifecycle_Usage reports retained target Project lifecycle resources. */
Lifecycle_Usage :: struct {
	projects:               u32,
	promotion_suppressions: u32,
	migration_entries:      u32,
	record_bytes:           u64,
}

/* Lifecycle_Operation identifies the target Project lifecycle operation in a result. */
Lifecycle_Operation :: enum u8 {
	None,
	Inspect_Dir,
	Load_Local_Project,
	Persist_Local_Project,
	Load_Discovery,
	Persist_Discovery,
	Load_Suppression,
	Persist_Suppression,
	Remove_Suppression,
	Inventory_Legacy,
	Persist_Migration,
}

/* Lifecycle_Failure_Code classifies target Project lifecycle rejection. */
Lifecycle_Failure_Code :: enum u16 {
	None,
	Invalid_Policy,
	Policy_Range,
	Invalid_Dir,
	Invalid_Format,
	Invalid_Identity,
	Invalid_Generation,
	Invalid_Name,
	Invalid_Path,
	Invalid_Trust,
	Invalid_Migration_State,
	Project_Limit,
	Suppression_Limit,
	Migration_Limit,
	Record_Byte_Limit,
	Duplicate_Identity,
	Duplicate_Root,
	Stale_Generation,
	Conflicting_Local_Metadata,
	Filesystem_Failure,
	Validation_Failure,
	Publication_Unresolved,
	Cancelled,
}

/* Lifecycle_Failure_Context identifies the rejected target lifecycle value and bound. */
Lifecycle_Failure_Context :: struct {
	code:      Lifecycle_Failure_Code,
	operation: Lifecycle_Operation,
	field:     Lifecycle_Policy_Field,
	dir:       Dir_Handle,
	project:   Project_Handle,
	minimum:   u64,
	maximum:   u64,
	actual:    u64,
}

/* dir_handle_is_valid reports whether a Dir handle has nonzero checked identity. */
dir_handle_is_valid :: proc(handle: Dir_Handle) -> bool {
	return owner_handle_is_valid(handle.owner) && handle.id != Dir_ID(0) &&
	       handle.generation != Dir_Generation(0)
}

/* lifecycle_policy_validate checks every target Project lifecycle resource bound. */
lifecycle_policy_validate :: proc(
	policy: Lifecycle_Policy,
) -> (ok: bool, failure: Lifecycle_Failure_Context) {
	checks := [?]struct {actual, minimum, maximum: u64, field: Lifecycle_Policy_Field} {
		{u64(policy.projects), u64(MIN_CATALOG_PROJECTS), u64(MAX_CATALOG_PROJECTS), .Projects},
		{u64(policy.promotion_suppressions), u64(MIN_PROMOTION_SUPPRESSIONS), u64(MAX_PROMOTION_SUPPRESSIONS), .Promotion_Suppressions},
		{u64(policy.migration_entries), u64(MIN_MIGRATION_ENTRIES), u64(MAX_MIGRATION_ENTRIES), .Migration_Entries},
		{policy.record_bytes, MIN_LIFECYCLE_RECORD_BYTES, MAX_LIFECYCLE_RECORD_BYTES, .Record_Bytes},
	}
	for check in checks {
		if check.actual < check.minimum || check.actual > check.maximum {
			return false, Lifecycle_Failure_Context {
				code = .Policy_Range,
				field = check.field,
				minimum = check.minimum,
				maximum = check.maximum,
				actual = check.actual,
			}
		}
	}
	return true, {}
}

/* local_project_proposal_validate checks one complete target Project record. */
local_project_proposal_validate :: proc(
	proposal: Local_Project_Proposal,
) -> (ok: bool, failure: Lifecycle_Failure_Context) {
	if proposal.format_version != TARGET_PROJECT_FORMAT_VERSION {
		return false, Lifecycle_Failure_Context{code = .Invalid_Format, operation = .Load_Local_Project}
	}
	if !lifecycle_identity_valid(proposal.id) {
		return false, Lifecycle_Failure_Context{code = .Invalid_Identity, operation = .Load_Local_Project}
	}
	if proposal.generation == 0 {
		return false, Lifecycle_Failure_Context{code = .Invalid_Generation, operation = .Load_Local_Project}
	}
	if !lifecycle_name_valid(proposal.name) {
		return false, Lifecycle_Failure_Context{code = .Invalid_Name, operation = .Load_Local_Project}
	}
	if !lifecycle_path_valid(proposal.root) {
		return false, Lifecycle_Failure_Context{code = .Invalid_Path, operation = .Load_Local_Project}
	}
	if proposal.trust != .Untrusted && proposal.trust != .Trusted {
		return false, Lifecycle_Failure_Context{code = .Invalid_Trust, operation = .Load_Local_Project}
	}
	return true, {}
}

/* project_discovery_proposal_validate checks one global Project reference. */
project_discovery_proposal_validate :: proc(
	proposal: Project_Discovery_Proposal,
) -> (ok: bool, failure: Lifecycle_Failure_Context) {
	if proposal.format_version != TARGET_REFERENCE_FORMAT_VERSION {
		return false, Lifecycle_Failure_Context{code = .Invalid_Format, operation = .Load_Discovery}
	}
	if !lifecycle_identity_valid(proposal.id) {
		return false, Lifecycle_Failure_Context{code = .Invalid_Identity, operation = .Load_Discovery}
	}
	if proposal.expected_project_generation == 0 {
		return false, Lifecycle_Failure_Context{code = .Invalid_Generation, operation = .Load_Discovery}
	}
	if !lifecycle_path_valid(proposal.root) {
		return false, Lifecycle_Failure_Context{code = .Invalid_Path, operation = .Load_Discovery}
	}
	return true, {}
}

/* promotion_suppression_proposal_validate checks one global Dir prompt preference. */
promotion_suppression_proposal_validate :: proc(
	proposal: Promotion_Suppression_Proposal,
) -> (ok: bool, failure: Lifecycle_Failure_Context) {
	if proposal.format_version != PROMOTION_SUPPRESSION_FORMAT_VERSION {
		return false, Lifecycle_Failure_Context{code = .Invalid_Format, operation = .Load_Suppression}
	}
	if proposal.generation == 0 {
		return false, Lifecycle_Failure_Context{code = .Invalid_Generation, operation = .Load_Suppression}
	}
	if !lifecycle_path_valid(proposal.root) {
		return false, Lifecycle_Failure_Context{code = .Invalid_Path, operation = .Load_Suppression}
	}
	return true, {}
}

/* migration_proposal_validate checks one source-preserving migration journal entry. */
migration_proposal_validate :: proc(
	proposal: Migration_Proposal,
) -> (ok: bool, failure: Lifecycle_Failure_Context) {
	if proposal.format_version != MIGRATION_FORMAT_VERSION {
		return false, Lifecycle_Failure_Context{code = .Invalid_Format, operation = .Persist_Migration}
	}
	if proposal.generation == 0 {
		return false, Lifecycle_Failure_Context{code = .Invalid_Generation, operation = .Persist_Migration}
	}
	if !lifecycle_identity_valid(proposal.source_id) || !lifecycle_identity_valid(proposal.target_id) {
		return false, Lifecycle_Failure_Context{code = .Invalid_Identity, operation = .Persist_Migration}
	}
	if !lifecycle_path_valid(proposal.source_path) {
		return false, Lifecycle_Failure_Context{code = .Invalid_Path, operation = .Persist_Migration}
	}
	if proposal.state == .Invalid {
		return false, Lifecycle_Failure_Context{code = .Invalid_Migration_State, operation = .Persist_Migration}
	}
	return true, {}
}

@(private)
lifecycle_identity_valid :: proc(value: string) -> bool {
	if len(value) == 0 || u64(len(value)) > MAX_DURABLE_ID_BYTES || !utf8.valid_string(value) ||
	   strings.index_byte(value, 0) >= 0 {
		return false
	}
	for byte in transmute([]u8)value {
		if !((byte >= 'a' && byte <= 'z') || (byte >= '0' && byte <= '9') || byte == '-') {
			return false
		}
	}
	return value[0] != '-' && value[len(value) - 1] != '-' && strings.index(value, "--") < 0
}

@(private)
lifecycle_name_valid :: proc(value: string) -> bool {
	return len(value) > 0 && u64(len(value)) <= MAX_NAME_BYTES && utf8.valid_string(value) &&
	       strings.index_byte(value, 0) < 0
}

@(private)
lifecycle_path_valid :: proc(value: string) -> bool {
	return len(value) > 0 && len(value) <= MAX_DIRECTORY_PATH_STORAGE_BYTES && value[0] == '/' &&
	       utf8.valid_string(value) && strings.index_byte(value, 0) < 0
}
