// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../editor"
import "../language_bundle"
import "core:strings"
import "core:unicode/utf8"

/* MAX_SYNTAX_PROVIDER_IDENTITY_BYTES bounds a copied provider identity. */
MAX_SYNTAX_PROVIDER_IDENTITY_BYTES :: 96
/* MAX_SYNTAX_ARTIFACT_PATH_BYTES bounds a copied absolute artifact path. */
MAX_SYNTAX_ARTIFACT_PATH_BYTES :: 4 * KIBIBYTE
/* MAX_SYNTAX_ENTRYPOINT_BYTES bounds a copied native grammar symbol. */
MAX_SYNTAX_ENTRYPOINT_BYTES :: 128
/* MAX_SYNTAX_CAPTURE_NAME_BYTES bounds one copied query capture name. */
MAX_SYNTAX_CAPTURE_NAME_BYTES :: 128
/* MAX_SYNTAX_QUERY_ARTIFACTS bounds query kinds contributed by one provider. */
MAX_SYNTAX_QUERY_ARTIFACTS :: 3
/* MAX_SYNTAX_CAPTURE_MAPPINGS bounds semantic mappings contributed by one provider. */
MAX_SYNTAX_CAPTURE_MAPPINGS :: 256

/* Syntax_Provider_Status reports preparation without exposing native values. */
Syntax_Provider_Status :: enum u8 {
	Invalid,
	Prepared,
	Loaded,
	Failed,
	Closed,
}

/* Syntax_Query_Kind identifies one data-only Tree-sitter query purpose. */
Syntax_Query_Kind :: enum u8 {
	Invalid,
	Highlights,
	Injections,
	Local_Symbols,
}

/* Syntax_Structural_Role is stable structure independent from presentation. */
Syntax_Structural_Role :: enum u8 {
	None,
	Declaration,
	Definition,
	Reference,
	Scope,
	Container,
	Name,
	Body,
}

/* Syntax_Provider_Resource_Profile may tighten, but never raise, native limits. */
Syntax_Provider_Resource_Profile :: struct {
	query_bytes:     u64,
	captures:        u32,
	spans:           u32,
	temporary_bytes: u64,
	work_bytes:      u64,
}

/* Syntax_Native_Authority records the complete native-grammar trust decision. */
Syntax_Native_Authority :: struct {
	factory_artifact:    bool,
	trusted_publisher:   bool,
	trusted_source:      bool,
	user_confirmed:      bool,
	native_grammar_grant: bool,
}

/* Syntax_Provider_Cancel_Proc is polled without retaining its borrowed state. */
Syntax_Provider_Cancel_Proc :: proc "odin" (user_data: rawptr) -> bool

/* Syntax_Provider_Cancellation supplies bounded synchronous cancellation. */
Syntax_Provider_Cancellation :: struct {
	user_data: rawptr,
	check:     Syntax_Provider_Cancel_Proc,
}

/* Syntax_Grammar_Artifact_Proposal points at one immutable verified artifact. */
Syntax_Grammar_Artifact_Proposal :: struct {
	path:                    string,
	digest:                  [32]u8,
	size:                    u64,
	platform:                language_bundle.Bundle_Platform,
	architecture:            language_bundle.Bundle_Architecture,
	entrypoint:              string,
	minimum_abi:             u32,
	maximum_abi:             u32,
	minimum_language_version: u32,
	maximum_language_version: u32,
}

/* Syntax_Query_Artifact_Proposal identifies one immutable query artifact. */
Syntax_Query_Artifact_Proposal :: struct {
	kind:       Syntax_Query_Kind,
	path:       string,
	digest:     [32]u8,
	size:       u64,
	generation: Query_Generation,
}

/* Syntax_Capture_Mapping_Proposal maps query data to stable Odra semantics. */
Syntax_Capture_Mapping_Proposal :: struct {
	capture:         string,
	role:            Syntax_Role,
	structural_role: Syntax_Structural_Role,
	precedence:      u16,
}

/* Syntax_Provider_Proposal is the pointer-free syntax provider input. */
Syntax_Provider_Proposal :: struct {
	identity: string,
	language: Language_Identity,
	grammar:  Syntax_Grammar_Artifact_Proposal,
	queries:  []Syntax_Query_Artifact_Proposal,
	mappings: []Syntax_Capture_Mapping_Proposal,
	resources: Syntax_Provider_Resource_Profile,
	authority: Syntax_Native_Authority,
}

/* Syntax_Provider_Text owns one bounded provider identity. */
Syntax_Provider_Text :: struct {
	bytes:  [MAX_SYNTAX_PROVIDER_IDENTITY_BYTES]u8,
	length: u16,
}

/* Syntax_Artifact_Path owns one bounded absolute artifact path. */
Syntax_Artifact_Path :: struct {
	bytes:  [MAX_SYNTAX_ARTIFACT_PATH_BYTES]u8,
	length: u16,
}

/* Syntax_Entrypoint owns one bounded native grammar symbol. */
Syntax_Entrypoint :: struct {
	bytes:  [MAX_SYNTAX_ENTRYPOINT_BYTES]u8,
	length: u16,
}

/* Syntax_Capture_Name owns one bounded query capture name. */
Syntax_Capture_Name :: struct {
	bytes:  [MAX_SYNTAX_CAPTURE_NAME_BYTES]u8,
	length: u16,
}

/* Syntax_Grammar_Artifact is the copied verified native grammar contract. */
Syntax_Grammar_Artifact :: struct {
	path:                    Syntax_Artifact_Path,
	digest:                  [32]u8,
	size:                    u64,
	platform:                language_bundle.Bundle_Platform,
	architecture:            language_bundle.Bundle_Architecture,
	entrypoint:              Syntax_Entrypoint,
	minimum_abi:             u32,
	maximum_abi:             u32,
	minimum_language_version: u32,
	maximum_language_version: u32,
}

/* Syntax_Query_Artifact is one copied immutable query contract. */
Syntax_Query_Artifact :: struct {
	kind:       Syntax_Query_Kind,
	path:       Syntax_Artifact_Path,
	digest:     [32]u8,
	size:       u64,
	generation: Query_Generation,
}

/* Syntax_Capture_Mapping maps one owned capture to stable semantics. */
Syntax_Capture_Mapping :: struct {
	capture:         Syntax_Capture_Name,
	role:            Syntax_Role,
	structural_role: Syntax_Structural_Role,
	precedence:      u16,
}

/* Syntax_Structural_Projection is one copied named-node provider role. */
Syntax_Structural_Projection :: struct {
	start:           editor.Byte_Offset,
	end:             editor.Byte_Offset,
	role:            Syntax_Structural_Role,
	provider:        Provider_Handle,
	source_revision: editor.Revision,
}

/* Syntax_Provider_Record owns every manifest-derived value needed by loading. */
Syntax_Provider_Record :: struct {
	identity:   Syntax_Provider_Text,
	language:   Language_Identity,
	grammar:    Syntax_Grammar_Artifact,
	queries:    [MAX_SYNTAX_QUERY_ARTIFACTS]Syntax_Query_Artifact,
	query_count: u8,
	mappings:   [MAX_SYNTAX_CAPTURE_MAPPINGS]Syntax_Capture_Mapping,
	mapping_count: u16,
	resources:  Syntax_Provider_Resource_Profile,
	authority:  Syntax_Native_Authority,
}

/* Syntax_Provider_Inspection is copied state without pointers or library handles. */
Syntax_Provider_Inspection :: struct {
	status:             Syntax_Provider_Status,
	identity:           Syntax_Provider_Text,
	language:           Language_Identity,
	grammar_digest:     [32]u8,
	grammar_abi:        u32,
	language_version:   u32,
	query_count:        u8,
	mapping_count:      u16,
	query_bytes:        u64,
	parser_ready:       bool,
	library_owned:      bool,
	latest_failure:     Failure,
}

/* syntax_provider_prepare validates and copies one immutable provider record. */
syntax_provider_prepare :: proc(
	proposal: Syntax_Provider_Proposal,
) -> (record: Syntax_Provider_Record, ok: bool, failure: Failure) {
	if !syntax_contract_text_valid(proposal.identity, MAX_SYNTAX_PROVIDER_IDENTITY_BYTES) ||
	   !language_identity_is_valid(proposal.language) {
		return {}, false, syntax_provider_contract_failure(.Invalid_Provider)
	}
	if !syntax_grammar_proposal_valid(proposal.grammar) {
		return {}, false, syntax_provider_contract_failure(.Invalid_Grammar_Artifact)
	}
	if len(proposal.queries) > MAX_SYNTAX_QUERY_ARTIFACTS {
		return {}, false, syntax_provider_limit_failure(.Query_Limit, MAX_SYNTAX_QUERY_ARTIFACTS, len(proposal.queries))
	}
	if len(proposal.mappings) > MAX_SYNTAX_CAPTURE_MAPPINGS {
		return {}, false, syntax_provider_limit_failure(.Capture_Limit, MAX_SYNTAX_CAPTURE_MAPPINGS, len(proposal.mappings))
	}
	if !syntax_resource_profile_valid(proposal.resources) {
		return {}, false, syntax_provider_contract_failure(.Invalid_Resource_Profile)
	}

	record.identity = syntax_provider_text_copy(proposal.identity)
	record.language = proposal.language
	record.grammar = syntax_grammar_copy(proposal.grammar)
	record.resources = proposal.resources
	record.authority = proposal.authority
	for query, index in proposal.queries {
		if !syntax_query_proposal_valid(query) {
			return {}, false, syntax_provider_contract_failure(.Invalid_Query_Artifact)
		}
		for prior in 0 ..< index {
			if proposal.queries[prior].kind == query.kind {
				return {}, false, syntax_provider_contract_failure(.Duplicate_Query_Kind)
			}
		}
		record.queries[index] = syntax_query_copy(query)
	}
	record.query_count = u8(len(proposal.queries))
	for mapping, index in proposal.mappings {
		if !syntax_mapping_proposal_valid(mapping) {
			return {}, false, syntax_provider_contract_failure(.Invalid_Capture_Mapping)
		}
		for prior in 0 ..< index {
			if proposal.mappings[prior].capture == mapping.capture {
				return {}, false, syntax_provider_contract_failure(.Duplicate_Capture_Mapping)
			}
		}
		record.mappings[index] = syntax_mapping_copy(mapping)
	}
	record.mapping_count = u16(len(proposal.mappings))
	return record, true, {}
}

/* syntax_native_authority_granted requires a factory artifact or complete user trust. */
syntax_native_authority_granted :: proc(authority: Syntax_Native_Authority) -> bool {
	return authority.native_grammar_grant &&
		(authority.factory_artifact ||
		 (authority.trusted_publisher && authority.trusted_source && authority.user_confirmed))
}

/* syntax_provider_text_view borrows the populated provider identity bytes. */
syntax_provider_text_view :: proc(value: ^Syntax_Provider_Text) -> string {
	if value == nil do return ""
	return string(value.bytes[:value.length])
}

/* syntax_artifact_path_view borrows the populated artifact path bytes. */
syntax_artifact_path_view :: proc(value: ^Syntax_Artifact_Path) -> string {
	if value == nil do return ""
	return string(value.bytes[:value.length])
}

/* syntax_entrypoint_view borrows the populated native symbol bytes. */
syntax_entrypoint_view :: proc(value: ^Syntax_Entrypoint) -> string {
	if value == nil do return ""
	return string(value.bytes[:value.length])
}

/* syntax_capture_name_view borrows the populated capture name bytes. */
syntax_capture_name_view :: proc(value: ^Syntax_Capture_Name) -> string {
	if value == nil do return ""
	return string(value.bytes[:value.length])
}

@(private)
syntax_grammar_proposal_valid :: proc(value: Syntax_Grammar_Artifact_Proposal) -> bool {
	return syntax_contract_path_valid(value.path) && syntax_digest_present(value.digest) &&
		value.size > 0 && value.size <= language_bundle.MAX_ARTIFACT_BYTES &&
		value.platform != .Invalid && value.architecture != .Invalid &&
		syntax_contract_text_valid(value.entrypoint, MAX_SYNTAX_ENTRYPOINT_BYTES) &&
		strings.has_prefix(value.entrypoint, "tree_sitter_") &&
		value.minimum_abi > 0 && value.minimum_abi <= value.maximum_abi &&
		value.minimum_language_version > 0 &&
		value.minimum_language_version <= value.maximum_language_version
}

@(private)
syntax_query_proposal_valid :: proc(value: Syntax_Query_Artifact_Proposal) -> bool {
	return value.kind >= .Highlights && value.kind <= .Local_Symbols &&
		syntax_contract_path_valid(value.path) && syntax_digest_present(value.digest) &&
		value.size > 0 && value.size <= MAX_QUERY_BYTES && value.generation != Query_Generation(0)
}

@(private)
syntax_mapping_proposal_valid :: proc(value: Syntax_Capture_Mapping_Proposal) -> bool {
	return syntax_contract_text_valid(value.capture, MAX_SYNTAX_CAPTURE_NAME_BYTES) &&
		syntax_role_is_valid(value.role) && value.structural_role >= .None &&
		value.structural_role <= .Body
}

@(private)
syntax_resource_profile_valid :: proc(value: Syntax_Provider_Resource_Profile) -> bool {
	return value.query_bytes > 0 && value.query_bytes <= MAX_QUERY_BYTES &&
		value.captures > 0 && value.captures <= MAX_CAPTURES &&
		value.spans > 0 && value.spans <= MAX_SYNTAX_SPANS &&
		value.temporary_bytes > 0 && value.temporary_bytes <= MAX_TEMPORARY_BYTES &&
		value.work_bytes > 0 && value.work_bytes <= REFRESH_WORK_BYTES
}

@(private)
syntax_contract_text_valid :: proc(value: string, maximum: int) -> bool {
	return len(value) > 0 && len(value) <= maximum && utf8.valid_string(value) &&
		strings.index_byte(value, 0) < 0
}

@(private)
syntax_contract_path_valid :: proc(value: string) -> bool {
	return syntax_contract_text_valid(value, int(MAX_SYNTAX_ARTIFACT_PATH_BYTES)) && value[0] == '/'
}

@(private)
syntax_digest_present :: proc(value: [32]u8) -> bool {
	for byte in value do if byte != 0 do return true
	return false
}

@(private)
syntax_provider_text_copy :: proc(value: string) -> Syntax_Provider_Text {
	result: Syntax_Provider_Text
	copy(result.bytes[:], value)
	result.length = u16(len(value))
	return result
}

@(private)
syntax_artifact_path_copy :: proc(value: string) -> Syntax_Artifact_Path {
	result: Syntax_Artifact_Path
	copy(result.bytes[:], value)
	result.length = u16(len(value))
	return result
}

@(private)
syntax_entrypoint_copy :: proc(value: string) -> Syntax_Entrypoint {
	result: Syntax_Entrypoint
	copy(result.bytes[:], value)
	result.length = u16(len(value))
	return result
}

@(private)
syntax_capture_name_copy :: proc(value: string) -> Syntax_Capture_Name {
	result: Syntax_Capture_Name
	copy(result.bytes[:], value)
	result.length = u16(len(value))
	return result
}

@(private)
syntax_grammar_copy :: proc(value: Syntax_Grammar_Artifact_Proposal) -> Syntax_Grammar_Artifact {
	return Syntax_Grammar_Artifact {
		path = syntax_artifact_path_copy(value.path),
		digest = value.digest,
		size = value.size,
		platform = value.platform,
		architecture = value.architecture,
		entrypoint = syntax_entrypoint_copy(value.entrypoint),
		minimum_abi = value.minimum_abi,
		maximum_abi = value.maximum_abi,
		minimum_language_version = value.minimum_language_version,
		maximum_language_version = value.maximum_language_version,
	}
}

@(private)
syntax_query_copy :: proc(value: Syntax_Query_Artifact_Proposal) -> Syntax_Query_Artifact {
	return Syntax_Query_Artifact {
		kind = value.kind,
		path = syntax_artifact_path_copy(value.path),
		digest = value.digest,
		size = value.size,
		generation = value.generation,
	}
}

@(private)
syntax_mapping_copy :: proc(value: Syntax_Capture_Mapping_Proposal) -> Syntax_Capture_Mapping {
	return Syntax_Capture_Mapping {
		capture = syntax_capture_name_copy(value.capture),
		role = value.role,
		structural_role = value.structural_role,
		precedence = value.precedence,
	}
}

@(private)
syntax_provider_contract_failure :: proc(code: Failure_Code) -> Failure {
	return Failure {operation = .Prepare_Provider, code = code}
}

@(private)
syntax_provider_limit_failure :: proc(code: Failure_Code, limit, actual: int) -> Failure {
	return Failure {operation = .Prepare_Provider, code = code, limit = u64(limit), actual = u64(actual)}
}
