// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package language_formatter owns formatter definitions, selection, execution proposals, and inspection.
package language_formatter

import "../language"
import "core:unicode/utf8"

MAX_FORMATTERS :: 64
MAX_FORMATTER_LANGUAGES :: language.MAX_LANGUAGES
MAX_ARGUMENTS :: 32
MAX_ENVIRONMENT :: 32
MAX_IDENTITY_BYTES :: 96
MAX_NAME_BYTES :: 128
MAX_SCOPE_BYTES :: 256
MAX_PATH_BYTES :: 4 * 1_024
MAX_ARGUMENT_BYTES :: 1_024
MAX_ENVIRONMENT_BYTES :: 2 * 1_024
MAX_PROVENANCE_BYTES :: 256
MAX_VERSION_TEXT_BYTES :: 256

Formatter_ID :: distinct u64
Formatter_Generation :: distinct u64
Catalog_ID :: distinct u64
Catalog_Generation :: distinct u64
Source_Generation :: distinct u64
Profile_Generation :: distinct u64

Formatter_Kind :: enum u8 {Invalid, LSP, External}
Formatter_Scope :: enum u8 {Invalid, Document, Range}
Formatter_Scopes :: bit_set[Formatter_Scope; u8]
Input_Mode :: enum u8 {Invalid, Standard_Input, Temporary_File}
Output_Mode :: enum u8 {Invalid, Standard_Output, Temporary_File}
Root_Policy :: enum u8 {Invalid, Project_Membership, Workspace_Folder}
Availability :: enum u8 {Unknown, Available, Unavailable, Changed, Rejected, Failed}
Contribution_Source :: enum u8 {Invalid, Factory, Package, Personal, Project}
Scope_Kind :: enum u8 {Invalid, Global, Package, Project_Membership}
Selection_Kind :: enum u8 {None, Explicit_Project, Explicit_Personal, Unique_Default, Sole_Candidate}

Failure_Code :: enum u16 {
	None,
	Invalid_Input,
	Invalid_Definition,
	Invalid_Catalog,
	Invalid_Selection,
	Duplicate_Identity,
	Ambiguous_Selection,
	No_Selection,
	Stale_Generation,
	Unsupported_Scope,
	Unavailable,
	Untrusted_Root,
	Outside_Root,
	Version_Mismatch,
	Spawn,
	Pipe,
	Timeout,
	Exit_Failure,
	Output_Limit,
	Malformed_Output,
	Stale_Revision,
	Overlapping_Edit,
	Resource_Limit,
	Allocation,
	Cancelled,
	Closed,
}

Resource_Kind :: enum u8 {
	None,
	Formatter,
	Language,
	Argument,
	Environment,
	Input_Bytes,
	Output_Bytes,
	Edit,
	Temporary_Bytes,
	Retained_Bytes,
}

Identity_Text :: struct {bytes: [MAX_IDENTITY_BYTES]u8, length: u16}
Name_Text :: struct {bytes: [MAX_NAME_BYTES]u8, length: u16}
Scope_Text :: struct {bytes: [MAX_SCOPE_BYTES]u8, length: u16}
Path_Text :: struct {bytes: [MAX_PATH_BYTES]u8, length: u16}
Argument_Text :: struct {bytes: [MAX_ARGUMENT_BYTES]u8, length: u16}
Environment_Text :: struct {bytes: [MAX_ENVIRONMENT_BYTES]u8, length: u16}
Provenance_Text :: struct {bytes: [MAX_PROVENANCE_BYTES]u8, length: u16}
Version_Text :: struct {bytes: [MAX_VERSION_TEXT_BYTES]u8, length: u16}

Language_Reference :: struct {
	id: language.Language_ID,
	generation: language.Language_Generation,
}

Formatter_Handle :: struct {
	catalog_id: Catalog_ID,
	catalog_generation: Catalog_Generation,
	id: Formatter_ID,
	generation: Formatter_Generation,
}

Formatter_Limits :: struct {
	input_bytes:     u64,
	output_bytes:    u64,
	edits:           u32,
	temporary_bytes: u64,
	retained_bytes:  u64,
	timeout_ns:      i64,
}

DEFAULT_LIMITS :: Formatter_Limits {
	input_bytes = 64 * 1_024 * 1_024,
	output_bytes = 64 * 1_024 * 1_024,
	edits = 100_000,
	temporary_bytes = 128 * 1_024 * 1_024,
	retained_bytes = 128 * 1_024 * 1_024,
	timeout_ns = 10_000_000_000,
}

Version_Probe_Proposal :: struct {
	arguments:      []string,
	expected_exact: string,
}

Version_Probe :: struct {
	arguments:      [MAX_ARGUMENTS]Argument_Text,
	argument_count: u8,
	expected_exact: Version_Text,
}

Source_Scope :: struct {
	source: Contribution_Source,
	kind: Scope_Kind,
	name: Scope_Text,
}

Executable_Profile :: struct {
	generation:         Profile_Generation,
	configured:         Path_Text,
	resolved:           Path_Text,
	probe:              Version_Probe,
	availability:       Availability,
	discovered_version: Version_Text,
	provenance:         Provenance_Text,
}

Formatter_Proposal :: struct {
	identity:          string,
	name:              string,
	languages:         []language.Language_Identity,
	kind:              Formatter_Kind,
	executable:        string,
	arguments:         []string,
	environment:       []string,
	input_mode:        Input_Mode,
	output_mode:       Output_Mode,
	scopes:            Formatter_Scopes,
	root_policy:       Root_Policy,
	limits:            Formatter_Limits,
	version_probe:     Version_Probe_Proposal,
	source:            Contribution_Source,
	scope_kind:        Scope_Kind,
	scope:             string,
	source_generation: Source_Generation,
	default_selection: bool,
	provenance:        string,
}

Formatter_Record :: struct {
	handle:            Formatter_Handle,
	identity:          Identity_Text,
	name:              Name_Text,
	languages:         [MAX_FORMATTER_LANGUAGES]Language_Reference,
	language_count:    u16,
	kind:              Formatter_Kind,
	arguments:         [MAX_ARGUMENTS]Argument_Text,
	argument_count:    u8,
	environment:       [MAX_ENVIRONMENT]Environment_Text,
	environment_count: u8,
	input_mode:        Input_Mode,
	output_mode:       Output_Mode,
	scopes:            Formatter_Scopes,
	root_policy:       Root_Policy,
	limits:            Formatter_Limits,
	scope:             Source_Scope,
	source_generation: Source_Generation,
	default_selection: bool,
	profile:           Executable_Profile,
	provenance:        Provenance_Text,
}

Selection_Proposal :: struct {
	language:           language.Language_Identity,
	formatter_identity: string,
	source:             Contribution_Source,
	scope_kind:         Scope_Kind,
	scope:              string,
	source_generation:  Source_Generation,
}

Selection_Record :: struct {
	language:           Language_Reference,
	formatter_identity: Identity_Text,
	scope:              Source_Scope,
	source_generation:  Source_Generation,
}

Catalog_Proposal :: struct {
	generation:  Catalog_Generation,
	definitions: []Formatter_Proposal,
	selections:  []Selection_Proposal,
}

Resolution_Query :: struct {
	language:           language.Language_Identity,
	project_membership: string,
	project_trusted:    bool,
}

Selection_Result :: struct {
	language:     language.Language_Identity,
	formatter:    Formatter_Handle,
	kind:         Selection_Kind,
	availability: Availability,
}

Catalog_Inspection :: struct {
	id:             Catalog_ID,
	generation:     Catalog_Generation,
	definitions:    u16,
	selections:     u16,
	retained_bytes: u64,
	latest_failure: Failure,
}

Failure :: struct {
	code:      Failure_Code,
	resource:  Resource_Kind,
	formatter: Formatter_Handle,
	limit:     u64,
	actual:    u64,
}

Catalog :: struct {state: rawptr}

formatter_limits_valid :: proc(limits: Formatter_Limits) -> bool {
	return limits.input_bytes > 0 && limits.input_bytes <= DEFAULT_LIMITS.input_bytes &&
		limits.output_bytes > 0 && limits.output_bytes <= DEFAULT_LIMITS.output_bytes &&
		limits.edits > 0 && limits.edits <= DEFAULT_LIMITS.edits &&
		limits.temporary_bytes > 0 && limits.temporary_bytes <= DEFAULT_LIMITS.temporary_bytes &&
		limits.retained_bytes > 0 && limits.retained_bytes <= DEFAULT_LIMITS.retained_bytes &&
		limits.timeout_ns > 0 && limits.timeout_ns <= DEFAULT_LIMITS.timeout_ns
}

formatter_handle_valid :: proc(handle: Formatter_Handle) -> bool {
	return handle.catalog_id != Catalog_ID(0) && handle.catalog_generation != Catalog_Generation(0) &&
		handle.id != Formatter_ID(0) && handle.generation != Formatter_Generation(0)
}

text_view :: proc(value: ^$T) -> string {
	if value == nil || int(value.length) > len(value.bytes) do return ""
	return string(value.bytes[:int(value.length)])
}

@(private)
copy_text :: proc(value: string, output: ^$T, allow_empty := false) -> bool {
	if output == nil || (!allow_empty && len(value) == 0) || len(value) > len(output.bytes) ||
	   !utf8.valid_string(value) {
		return false
	}
	output.length = u16(len(value))
	copy(output.bytes[:len(value)], transmute([]u8)value)
	return true
}

@(private)
language_reference :: proc(value: language.Language_Identity) -> Language_Reference {
	return {id = value.id, generation = value.generation}
}

@(private)
language_valid :: proc(value: language.Language_Identity) -> bool {
	return value.id != language.Language_ID(0) && value.generation != language.Language_Generation(0) &&
		value.name.length > 0 && int(value.name.length) <= len(value.name.bytes)
}
