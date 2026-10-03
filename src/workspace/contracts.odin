// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package workspace owns bounded persistent composition of validated Projects.
package workspace

import project "../project"
import "core:strings"
import "core:unicode/utf8"

/* FORMAT_VERSION identifies the initial Workspace record schema. */
FORMAT_VERSION :: u32(1)
/* MIN_WORKSPACES is the smallest admitted Workspace catalog capacity. */
MIN_WORKSPACES :: u32(16)
/* MAX_WORKSPACES is the largest validated Workspace catalog capacity. */
MAX_WORKSPACES :: u32(256)
/* DEFAULT_WORKSPACES is the measured initial Workspace catalog capacity. */
DEFAULT_WORKSPACES :: u32(32)
/* MIN_PROJECTS is the smallest persistent Workspace membership. */
MIN_PROJECTS :: u32(1)
/* MAX_PROJECTS is the largest validated Workspace membership. */
MAX_PROJECTS :: u32(256)
/* DEFAULT_PROJECTS is the measured initial Workspace membership capacity. */
DEFAULT_PROJECTS :: u32(32)
/* MAX_ID_BYTES bounds one filename-compatible Workspace identity. */
MAX_ID_BYTES :: u64(128)
/* MAX_NAME_BYTES bounds one Workspace display name. */
MAX_NAME_BYTES :: u64(1_024)
/* MIN_RECORD_BYTES is the smallest admitted retained Workspace record budget. */
MIN_RECORD_BYTES :: u64(64 * 1_024)
/* MAX_RECORD_BYTES is the largest validated retained Workspace record budget. */
MAX_RECORD_BYTES :: u64(64 * 1_024 * 1_024)
/* DEFAULT_RECORD_BYTES is the measured initial retained Workspace record budget. */
DEFAULT_RECORD_BYTES :: u64(8 * 1_024 * 1_024)

/* ID identifies one runtime Workspace slot. */
ID :: distinct u64
/* Generation rejects stale Workspace references after replacement. */
Generation :: distinct u64

/* Handle is a checked reference to one exact Workspace publication. */
Handle :: struct {
	owner:      project.Owner_Handle,
	id:         ID,
	generation: Generation,
}

/* Project_Reference_Proposal identifies one expected local Project generation. */
Project_Reference_Proposal :: struct {
	id:                  string,
	expected_generation: u64,
	root:                string,
}

/* Record_Proposal describes one complete ordered Workspace record. */
Record_Proposal :: struct {
	format_version: u32,
	id:             string,
	generation:     u64,
	name:           string,
	projects:       []Project_Reference_Proposal,
}

/* Descriptor is one copied Workspace summary. */
Descriptor :: struct {
	handle:        Handle,
	project_count: u32,
	missing_count: u32,
}

/* Policy_Field identifies one Workspace policy bound. */
Policy_Field :: enum u8 {
	Invalid,
	Workspaces,
	Projects,
	Record_Bytes,
}

/* Policy bounds Workspace catalogs, membership, and retained record bytes. */
Policy :: struct {
	workspaces:   u32,
	projects:     u32,
	record_bytes: u64,
}

/* DEFAULT_POLICY is the measured initial Workspace resource policy. */
DEFAULT_POLICY :: Policy {
	workspaces = DEFAULT_WORKSPACES,
	projects = DEFAULT_PROJECTS,
	record_bytes = DEFAULT_RECORD_BYTES,
}

/* Usage reports retained Workspace resources. */
Usage :: struct {
	workspaces:   u32,
	projects:     u32,
	record_bytes: u64,
}

/* Operation identifies the Workspace transition that produced a result. */
Operation :: enum u8 {
	None,
	Load,
	Persist,
	Enumerate,
	Resolve,
	Publish,
	Inspect,
	Close,
}

/* Failure_Code classifies Workspace rejection without partial publication. */
Failure_Code :: enum u16 {
	None,
	Invalid_Policy,
	Policy_Range,
	Invalid_Format,
	Invalid_Identity,
	Invalid_Generation,
	Invalid_Name,
	Invalid_Project_Reference,
	Invalid_Cardinality,
	Duplicate_Identity,
	Duplicate_Name,
	Duplicate_Project,
	Workspace_Limit,
	Project_Limit,
	Record_Byte_Limit,
	Stale_Generation,
	Missing_Project,
	Filesystem_Failure,
	Validation_Failure,
	Publication_Unresolved,
	Cancelled,
}

/* Failure_Context identifies the rejected Workspace object and resource bound. */
Failure_Context :: struct {
	code:      Failure_Code,
	operation: Operation,
	field:     Policy_Field,
	workspace: Handle,
	project:   project.Project_Handle,
	minimum:   u64,
	maximum:   u64,
	actual:    u64,
}

/* handle_is_valid reports whether a Workspace handle has nonzero checked identity. */
handle_is_valid :: proc(handle: Handle) -> bool {
	return project.owner_handle_is_valid(handle.owner) && handle.id != ID(0) &&
	       handle.generation != Generation(0)
}

/* policy_validate checks every Workspace resource bound. */
policy_validate :: proc(policy: Policy) -> (ok: bool, failure: Failure_Context) {
	checks := [?]struct {actual, minimum, maximum: u64, field: Policy_Field} {
		{u64(policy.workspaces), u64(MIN_WORKSPACES), u64(MAX_WORKSPACES), .Workspaces},
		{u64(policy.projects), u64(MIN_PROJECTS), u64(MAX_PROJECTS), .Projects},
		{policy.record_bytes, MIN_RECORD_BYTES, MAX_RECORD_BYTES, .Record_Bytes},
	}
	for check in checks {
		if check.actual < check.minimum || check.actual > check.maximum {
			return false, Failure_Context {
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

/* record_proposal_validate checks one complete Workspace record proposal. */
record_proposal_validate :: proc(
	proposal: Record_Proposal,
	policy: Policy = DEFAULT_POLICY,
) -> (ok: bool, failure: Failure_Context) {
	if policy_ok, policy_failure := policy_validate(policy); !policy_ok {
		return false, policy_failure
	}
	if proposal.format_version != FORMAT_VERSION {
		return false, Failure_Context{code = .Invalid_Format, operation = .Load}
	}
	if !identity_valid(proposal.id) {
		return false, Failure_Context{code = .Invalid_Identity, operation = .Load}
	}
	if proposal.generation == 0 {
		return false, Failure_Context{code = .Invalid_Generation, operation = .Load}
	}
	if !name_valid(proposal.name) {
		return false, Failure_Context{code = .Invalid_Name, operation = .Load}
	}
	if len(proposal.projects) < int(MIN_PROJECTS) || len(proposal.projects) > int(policy.projects) {
		return false, Failure_Context {
			code = .Invalid_Cardinality,
			operation = .Load,
			field = .Projects,
			minimum = u64(MIN_PROJECTS),
			maximum = u64(policy.projects),
			actual = u64(len(proposal.projects)),
		}
	}
	for left_index in 0 ..< len(proposal.projects) {
		left := proposal.projects[left_index]
		if !project_reference_valid(left) {
			return false, Failure_Context{code = .Invalid_Project_Reference, operation = .Load}
		}
		for right_index in left_index + 1 ..< len(proposal.projects) {
			if left.id == proposal.projects[right_index].id {
				return false, Failure_Context{code = .Duplicate_Project, operation = .Load}
			}
		}
	}
	return true, {}
}

@(private)
project_reference_valid :: proc(reference: Project_Reference_Proposal) -> bool {
	return identity_valid(reference.id) && reference.expected_generation > 0 &&
	       len(reference.root) > 0 && len(reference.root) <= project.MAX_DIRECTORY_PATH_STORAGE_BYTES &&
	       reference.root[0] == '/' && utf8.valid_string(reference.root) &&
	       strings.index_byte(reference.root, 0) < 0
}

@(private)
identity_valid :: proc(value: string) -> bool {
	if len(value) == 0 || u64(len(value)) > MAX_ID_BYTES || !utf8.valid_string(value) ||
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
name_valid :: proc(value: string) -> bool {
	return len(value) > 0 && u64(len(value)) <= MAX_NAME_BYTES && utf8.valid_string(value) &&
	       strings.index_byte(value, 0) < 0
}
