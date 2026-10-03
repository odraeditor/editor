// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package language_bundle owns immutable language-support bundle contracts.
package language_bundle

import "base:runtime"
import "core:unicode/utf8"

BUNDLE_FORMAT_VERSION :: u16(1)
MAX_IDENTITY_BYTES :: 96
MAX_DISPLAY_NAME_BYTES :: 128
MAX_DESCRIPTION_BYTES :: 4 * 1_024
MAX_PUBLISHER_BYTES :: 128
MAX_SOURCE_BYTES :: 128
MAX_PROVENANCE_BYTES :: 256
MAX_PATH_BYTES :: 4 * 1_024
MAX_ARTIFACT_BYTES :: u64(1) << 40
MAX_DEPENDENCIES :: 256
MAX_ARTIFACTS :: 1_024
MAX_CONTRIBUTIONS :: 640
MAX_TARGETS :: 16
MAX_AUTHORITIES :: 6
MAX_CONTRIBUTION_REFERENCES :: 8_192

Bundle_Version :: struct {
	major:       u32,
	minor:       u32,
	patch:       u32,
	pre_release: Identity_Text,
}

Bundle_Version_Proposal :: struct {
	major:       u32,
	minor:       u32,
	patch:       u32,
	pre_release: string,
}

Bundle_API_Range :: struct {
	minimum: Bundle_Version,
	maximum: Bundle_Version,
}

Bundle_API_Range_Proposal :: struct {
	minimum: Bundle_Version_Proposal,
	maximum: Bundle_Version_Proposal,
}

Bundle_Platform :: enum u8 {
	Invalid,
	Darwin,
	Linux,
	Windows,
}

Bundle_Architecture :: enum u8 {
	Invalid,
	Aarch64,
	X86_64,
}

Bundle_Target :: struct {
	platform:     Bundle_Platform,
	architecture: Bundle_Architecture,
}

Bundle_Authority :: enum u8 {
	Invalid,
	Racket_Extension,
	External_Process,
	Project_Read,
	Project_Write,
	Network_Acquisition,
	Native_Grammar,
}

Bundle_Artifact_Kind :: enum u8 {
	Invalid,
	Data,
	Documentation,
	Executable,
	License,
	Manifest,
	Query,
	Racket_Module,
	Tree_Sitter_Grammar,
}

Bundle_Contribution_Kind :: enum u8 {
	Invalid,
	Command,
	Formatter,
	Keymap,
	Language,
	Service,
	Syntax_Provider,
}

Bundle_Failure_Code :: enum u16 {
	None,
	Invalid_Candidate,
	Unsupported_Format,
	Invalid_Field,
	Invalid_Version_Range,
	Invalid_Path,
	Duplicate_Identity,
	Unknown_Reference,
	Self_Dependency,
	Limit,
	Allocation,
	Closed_Candidate,
	Malformed_Encoding,
	Stale_Generation,
	Reentrant_Preparation,
}

Bundle_Field :: enum u8 {
	None,
	Format_Version,
	Identity,
	Display_Name,
	Version,
	API_Range,
	Description,
	Publisher,
	Source,
	Provenance,
	Targets,
	Dependencies,
	Authorities,
	Contributions,
	Artifacts,
	Path,
	Digest,
	Entrypoint,
	References,
}

Bundle_Failure :: struct {
	code:               Bundle_Failure_Code,
	field:              Bundle_Field,
	limit:              u64,
	actual:             u64,
	dependency_index:   u16,
	artifact_index:     u16,
	contribution_index: u16,
}

Identity_Text :: struct {
	bytes:  [MAX_IDENTITY_BYTES]u8,
	length: u16,
}

Display_Name_Text :: struct {
	bytes:  [MAX_DISPLAY_NAME_BYTES]u8,
	length: u16,
}

Description_Text :: struct {
	bytes:  [MAX_DESCRIPTION_BYTES]u8,
	length: u16,
}

Publisher_Text :: struct {
	bytes:  [MAX_PUBLISHER_BYTES]u8,
	length: u16,
}

Source_Text :: struct {
	bytes:  [MAX_SOURCE_BYTES]u8,
	length: u16,
}

Provenance_Text :: struct {
	bytes:  [MAX_PROVENANCE_BYTES]u8,
	length: u16,
}

Path_Text :: struct {
	bytes:  [MAX_PATH_BYTES]u8,
	length: u16,
}

Record_Range :: struct {
	start: u16,
	count: u16,
}

Bundle_Dependency_Proposal :: struct {
	identity:    string,
	minimum:     Bundle_Version_Proposal,
	maximum:     Bundle_Version_Proposal,
	optional:    bool,
	facets:      []Bundle_Contribution_Kind,
	targets:     []Bundle_Target,
}

Bundle_Artifact_Proposal :: struct {
	identity:  string,
	kind:      Bundle_Artifact_Kind,
	path:      string,
	digest:    [32]u8,
	size:      u64,
	targets:   []Bundle_Target,
	authority: Bundle_Authority,
}

Bundle_Contribution_Proposal :: struct {
	kind:         Bundle_Contribution_Kind,
	identity:     string,
	languages:    []string,
	artifacts:    []string,
	dependencies: []string,
	authorities:  []Bundle_Authority,
}

Bundle_Proposal :: struct {
	format_version: u16,
	identity:       string,
	display_name:   string,
	version:        Bundle_Version_Proposal,
	api_range:      Bundle_API_Range_Proposal,
	description:    string,
	publisher:      string,
	source:         string,
	provenance:     string,
	targets:        []Bundle_Target,
	dependencies:   []Bundle_Dependency_Proposal,
	authorities:    []Bundle_Authority,
	contributions:  []Bundle_Contribution_Proposal,
	artifacts:      []Bundle_Artifact_Proposal,
	entrypoint:     string,
}

Bundle_Dependency_Record :: struct {
	identity:  Identity_Text,
	minimum:   Bundle_Version,
	maximum:   Bundle_Version,
	optional:  bool,
	facet_mask: u16,
	targets:     [MAX_TARGETS]Bundle_Target,
	target_count: u8,
}

Bundle_Artifact_Record :: struct {
	identity:  Identity_Text,
	kind:      Bundle_Artifact_Kind,
	path:      Path_Text,
	digest:    [32]u8,
	size:      u64,
	targets:   [MAX_TARGETS]Bundle_Target,
	target_count: u8,
	authority: Bundle_Authority,
}

Bundle_Contribution_Record :: struct {
	kind:         Bundle_Contribution_Kind,
	identity:     Identity_Text,
	languages:    Record_Range,
	artifacts:    Record_Range,
	dependencies: Record_Range,
	authority_mask: u8,
}

Bundle_Record :: struct {
	format_version: u16,
	identity:       Identity_Text,
	display_name:   Display_Name_Text,
	version:        Bundle_Version,
	api_range:      Bundle_API_Range,
	description:    Description_Text,
	publisher:      Publisher_Text,
	source:         Source_Text,
	provenance:     Provenance_Text,
	targets:        [MAX_TARGETS]Bundle_Target,
	target_count:   u8,
	authority_mask: u8,
	dependency_count:   u16,
	artifact_count:     u16,
	contribution_count: u16,
	entrypoint: Path_Text,
}

Bundle_Candidate :: struct {
	state:  rawptr,
	closed: bool,
}

@(private)
Bundle_Candidate_State :: struct {
	bundle:        Bundle_Record,
	dependencies: [MAX_DEPENDENCIES]Bundle_Dependency_Record,
	artifacts:     [MAX_ARTIFACTS]Bundle_Artifact_Record,
	contributions: [MAX_CONTRIBUTIONS]Bundle_Contribution_Record,
	language_references:   [MAX_CONTRIBUTION_REFERENCES]Identity_Text,
	artifact_references:   [MAX_CONTRIBUTION_REFERENCES]Identity_Text,
	dependency_references: [MAX_CONTRIBUTION_REFERENCES]Identity_Text,
	language_reference_count:   u16,
	artifact_reference_count:   u16,
	dependency_reference_count: u16,
	allocator: runtime.Allocator,
}

bundle_candidate_prepare :: proc(
	proposal: Bundle_Proposal,
	allocator := context.allocator,
) -> (candidate: Bundle_Candidate, ok: bool, failure: Bundle_Failure) {
	if allocator.procedure == nil {
		return {}, false, bundle_failure(.Allocation)
	}
	failure = bundle_proposal_validate(proposal)
	if failure.code != .None do return {}, false, failure
	state, allocation_error := new(Bundle_Candidate_State, allocator)
	if allocation_error != nil do return {}, false, bundle_failure(.Allocation)
	state^ = Bundle_Candidate_State{allocator = allocator}
	if !bundle_state_copy(state, proposal) {
		free(state, allocator)
		return {}, false, bundle_failure(.Invalid_Candidate)
	}
	candidate.state = state
	return candidate, true, {}
}

bundle_candidate_close :: proc(candidate: ^Bundle_Candidate) -> (bool, Bundle_Failure) {
	if candidate == nil || candidate.state == nil || candidate.closed {
		return false, bundle_failure(.Closed_Candidate)
	}
	state := cast(^Bundle_Candidate_State)candidate.state
	allocator := state.allocator
	free(state, allocator)
	candidate^ = Bundle_Candidate{closed = true}
	return true, {}
}

bundle_candidate_bundle :: proc(candidate: ^Bundle_Candidate) -> (^Bundle_Record, bool) {
	state := bundle_candidate_state(candidate)
	if state == nil do return nil, false
	return &state.bundle, true
}

bundle_candidate_dependency :: proc(candidate: ^Bundle_Candidate, index: int) -> (^Bundle_Dependency_Record, bool) {
	state := bundle_candidate_state(candidate)
	if state == nil || index < 0 || index >= int(state.bundle.dependency_count) do return nil, false
	return &state.dependencies[index], true
}

bundle_candidate_artifact :: proc(candidate: ^Bundle_Candidate, index: int) -> (^Bundle_Artifact_Record, bool) {
	state := bundle_candidate_state(candidate)
	if state == nil || index < 0 || index >= int(state.bundle.artifact_count) do return nil, false
	return &state.artifacts[index], true
}

bundle_candidate_contribution :: proc(candidate: ^Bundle_Candidate, index: int) -> (^Bundle_Contribution_Record, bool) {
	state := bundle_candidate_state(candidate)
	if state == nil || index < 0 || index >= int(state.bundle.contribution_count) do return nil, false
	return &state.contributions[index], true
}

identity_text_view :: proc(value: ^Identity_Text) -> string {
	if value == nil do return ""
	return string(value.bytes[:value.length])
}

path_text_view :: proc(value: ^Path_Text) -> string {
	if value == nil do return ""
	return string(value.bytes[:value.length])
}

provenance_text_view :: proc(value: ^Provenance_Text) -> string {
	if value == nil do return ""
	return string(value.bytes[:value.length])
}

bundle_api_compatible :: proc(bundle: ^Bundle_Record, api: Bundle_Version_Proposal) -> bool {
	if bundle == nil || !version_proposal_valid(api) do return false
	return version_lte_record_proposal(bundle.api_range.minimum, api) &&
		version_lte_proposal_record(api, bundle.api_range.maximum)
}

@(private)
bundle_candidate_state :: proc(candidate: ^Bundle_Candidate) -> ^Bundle_Candidate_State {
	if candidate == nil || candidate.state == nil || candidate.closed do return nil
	return cast(^Bundle_Candidate_State)candidate.state
}

@(private)
bundle_proposal_validate :: proc(proposal: Bundle_Proposal) -> Bundle_Failure {
	if proposal.format_version != BUNDLE_FORMAT_VERSION {
		return bundle_failure(.Unsupported_Format, .Format_Version, u64(BUNDLE_FORMAT_VERSION), u64(proposal.format_version))
	}
	if !identity_valid(proposal.identity) do return bundle_failure(.Invalid_Field, .Identity)
	if !text_valid(proposal.display_name, MAX_DISPLAY_NAME_BYTES, false) do return bundle_failure(.Limit, .Display_Name, MAX_DISPLAY_NAME_BYTES, u64(len(proposal.display_name)))
	if !version_proposal_valid(proposal.version) do return bundle_failure(.Invalid_Field, .Version)
	if !version_proposal_valid(proposal.api_range.minimum) ||
	   !version_proposal_valid(proposal.api_range.maximum) ||
	   !version_lte_proposal(proposal.api_range.minimum, proposal.api_range.maximum) {
		return bundle_failure(.Invalid_Version_Range, .API_Range)
	}
	if !text_valid(proposal.description, MAX_DESCRIPTION_BYTES, false) do return bundle_failure(.Limit, .Description, MAX_DESCRIPTION_BYTES, u64(len(proposal.description)))
	if !text_valid(proposal.publisher, MAX_PUBLISHER_BYTES, false) do return bundle_failure(.Limit, .Publisher, MAX_PUBLISHER_BYTES, u64(len(proposal.publisher)))
	if !text_valid(proposal.source, MAX_SOURCE_BYTES, false) do return bundle_failure(.Limit, .Source, MAX_SOURCE_BYTES, u64(len(proposal.source)))
	if !text_valid(proposal.provenance, MAX_PROVENANCE_BYTES, false) do return bundle_failure(.Limit, .Provenance, MAX_PROVENANCE_BYTES, u64(len(proposal.provenance)))
	if !targets_valid(proposal.targets) do return bundle_failure(.Invalid_Field, .Targets, MAX_TARGETS, u64(len(proposal.targets)))
	if len(proposal.dependencies) > MAX_DEPENDENCIES do return bundle_failure(.Limit, .Dependencies, MAX_DEPENDENCIES, u64(len(proposal.dependencies)))
	if len(proposal.artifacts) > MAX_ARTIFACTS do return bundle_failure(.Limit, .Artifacts, MAX_ARTIFACTS, u64(len(proposal.artifacts)))
	if len(proposal.contributions) > MAX_CONTRIBUTIONS do return bundle_failure(.Limit, .Contributions, MAX_CONTRIBUTIONS, u64(len(proposal.contributions)))
	if !authorities_valid(proposal.authorities) do return bundle_failure(.Invalid_Field, .Authorities, MAX_AUTHORITIES, u64(len(proposal.authorities)))
	language_references, artifact_references, dependency_references := 0, 0, 0
	for dependency, index in proposal.dependencies {
		if !dependency_valid(dependency, proposal.identity, proposal.targets) {
			failure := bundle_failure(.Invalid_Field, .Dependencies)
			failure.dependency_index = u16(index)
			return failure
		}
		for prior in 0 ..< index {
			if dependency.identity == proposal.dependencies[prior].identity {
				return bundle_failure(.Duplicate_Identity, .Dependencies)
			}
		}
	}
	for artifact, index in proposal.artifacts {
		if !artifact_valid(artifact, proposal.authorities, proposal.targets) {
			failure := bundle_failure(.Invalid_Field, .Artifacts)
			failure.artifact_index = u16(index)
			return failure
		}
		for prior in 0 ..< index {
			if artifact.identity == proposal.artifacts[prior].identity {
				return bundle_failure(.Duplicate_Identity, .Artifacts)
			}
		}
	}
	for contribution, index in proposal.contributions {
		language_references += len(contribution.languages)
		artifact_references += len(contribution.artifacts)
		dependency_references += len(contribution.dependencies)
		if !contribution_valid(contribution, proposal) {
			failure := bundle_failure(.Unknown_Reference, .Contributions)
			failure.contribution_index = u16(index)
			return failure
		}
		for prior in 0 ..< index {
			prior_value := proposal.contributions[prior]
			if contribution.kind == prior_value.kind && contribution.identity == prior_value.identity {
				return bundle_failure(.Duplicate_Identity, .Contributions)
			}
		}
	}
	if language_references > MAX_CONTRIBUTION_REFERENCES ||
	   artifact_references > MAX_CONTRIBUTION_REFERENCES ||
	   dependency_references > MAX_CONTRIBUTION_REFERENCES {
		return bundle_failure(.Limit, .References, MAX_CONTRIBUTION_REFERENCES, u64(max(language_references, artifact_references, dependency_references)))
	}
	if len(proposal.entrypoint) > 0 {
		if !path_valid(proposal.entrypoint) do return bundle_failure(.Invalid_Path, .Entrypoint)
		found := false
		for artifact in proposal.artifacts {
			if artifact.kind == .Racket_Module && artifact.path == proposal.entrypoint {
				found = true
				break
			}
		}
		if !found do return bundle_failure(.Unknown_Reference, .Entrypoint)
	}
	return {}
}

@(private)
bundle_state_copy :: proc(state: ^Bundle_Candidate_State, proposal: Bundle_Proposal) -> bool {
	state.bundle.format_version = proposal.format_version
	copy_identity(&state.bundle.identity, proposal.identity)
	copy_text(state.bundle.display_name.bytes[:], &state.bundle.display_name.length, proposal.display_name)
	copy_version(&state.bundle.version, proposal.version)
	copy_version(&state.bundle.api_range.minimum, proposal.api_range.minimum)
	copy_version(&state.bundle.api_range.maximum, proposal.api_range.maximum)
	copy_text(state.bundle.description.bytes[:], &state.bundle.description.length, proposal.description)
	copy_text(state.bundle.publisher.bytes[:], &state.bundle.publisher.length, proposal.publisher)
	copy_text(state.bundle.source.bytes[:], &state.bundle.source.length, proposal.source)
	copy_text(state.bundle.provenance.bytes[:], &state.bundle.provenance.length, proposal.provenance)
	copy(state.bundle.targets[:], proposal.targets)
	state.bundle.target_count = u8(len(proposal.targets))
	state.bundle.authority_mask = authority_mask(proposal.authorities)
	state.bundle.dependency_count = u16(len(proposal.dependencies))
	state.bundle.artifact_count = u16(len(proposal.artifacts))
	state.bundle.contribution_count = u16(len(proposal.contributions))
	if len(proposal.entrypoint) > 0 do copy_text(state.bundle.entrypoint.bytes[:], &state.bundle.entrypoint.length, proposal.entrypoint)
	for source, index in proposal.dependencies {
		destination := &state.dependencies[index]
		copy_identity(&destination.identity, source.identity)
		copy_version(&destination.minimum, source.minimum)
		copy_version(&destination.maximum, source.maximum)
		destination.optional = source.optional
		for facet in source.facets do destination.facet_mask |= contribution_mask(facet)
		copy(destination.targets[:], source.targets)
		destination.target_count = u8(len(source.targets))
	}
	for source, index in proposal.artifacts {
		destination := &state.artifacts[index]
		copy_identity(&destination.identity, source.identity)
		destination.kind = source.kind
		copy_text(destination.path.bytes[:], &destination.path.length, source.path)
		destination.digest = source.digest
		destination.size = source.size
		copy(destination.targets[:], source.targets)
		destination.target_count = u8(len(source.targets))
		destination.authority = source.authority
	}
	for source, index in proposal.contributions {
		destination := &state.contributions[index]
		destination.kind = source.kind
		copy_identity(&destination.identity, source.identity)
		destination.languages = copy_references(state.language_references[:], &state.language_reference_count, source.languages)
		destination.artifacts = copy_references(state.artifact_references[:], &state.artifact_reference_count, source.artifacts)
		destination.dependencies = copy_references(state.dependency_references[:], &state.dependency_reference_count, source.dependencies)
		destination.authority_mask = authority_mask(source.authorities)
	}
	return true
}

@(private)
copy_references :: proc(destination: []Identity_Text, count: ^u16, values: []string) -> Record_Range {
	result := Record_Range{start = count^, count = u16(len(values))}
	for value in values {
		copy_identity(&destination[count^], value)
		count^ += 1
	}
	return result
}

@(private)
copy_identity :: proc(destination: ^Identity_Text, value: string) {
	copy_text(destination.bytes[:], &destination.length, value)
}

@(private)
copy_version :: proc(destination: ^Bundle_Version, value: Bundle_Version_Proposal) {
	destination.major = value.major
	destination.minor = value.minor
	destination.patch = value.patch
	if len(value.pre_release) > 0 do copy_identity(&destination.pre_release, value.pre_release)
}

@(private)
copy_text :: proc(destination: []u8, length: ^u16, value: string) {
	copy(destination, transmute([]u8)value)
	length^ = u16(len(value))
}

@(private)
dependency_valid :: proc(
	value: Bundle_Dependency_Proposal,
	owner: string,
	bundle_targets: []Bundle_Target,
) -> bool {
	if !identity_valid(value.identity) || value.identity == owner ||
	   !version_proposal_valid(value.minimum) || !version_proposal_valid(value.maximum) ||
	   !version_lte_proposal(value.minimum, value.maximum) || len(value.facets) > 6 ||
	   (len(value.targets) > 0 && !targets_valid(value.targets)) {
		return false
	}
	for facet, index in value.facets {
		if facet == .Invalid do return false
		for prior in 0 ..< index do if facet == value.facets[prior] do return false
	}
	for target in value.targets {
		present := false
		for bundle_target in bundle_targets do if target == bundle_target {present = true; break}
		if !present do return false
	}
	return true
}

@(private)
artifact_valid :: proc(
	value: Bundle_Artifact_Proposal,
	authorities: []Bundle_Authority,
	bundle_targets: []Bundle_Target,
) -> bool {
	if !identity_valid(value.identity) || value.kind == .Invalid || !path_valid(value.path) ||
	   !targets_valid(value.targets) || value.size > MAX_ARTIFACT_BYTES {
		return false
	}
	for target in value.targets {
		present := false
		for bundle_target in bundle_targets do if target == bundle_target {present = true; break}
		if !present do return false
	}
	if value.authority != .Invalid && !authority_present(authorities, value.authority) do return false
	return true
}

@(private)
contribution_valid :: proc(value: Bundle_Contribution_Proposal, proposal: Bundle_Proposal) -> bool {
	if value.kind == .Invalid || !identity_valid(value.identity) ||
	   !identity_list_valid(value.languages) || !identity_list_valid(value.artifacts) ||
	   !identity_list_valid(value.dependencies) || !authorities_valid(value.authorities) {
		return false
	}
	for identity in value.artifacts {
		found := false
		for artifact in proposal.artifacts do if identity == artifact.identity {found = true; break}
		if !found do return false
	}
	for identity in value.dependencies {
		found := false
		for dependency in proposal.dependencies do if identity == dependency.identity {found = true; break}
		if !found do return false
	}
	for authority in value.authorities do if !authority_present(proposal.authorities, authority) do return false
	return true
}

@(private)
identity_list_valid :: proc(values: []string) -> bool {
	for value, index in values {
		if !identity_valid(value) do return false
		for prior in 0 ..< index do if value == values[prior] do return false
	}
	return true
}

@(private)
targets_valid :: proc(values: []Bundle_Target) -> bool {
	if len(values) == 0 || len(values) > MAX_TARGETS do return false
	for value, index in values {
		if value.platform == .Invalid || value.architecture == .Invalid do return false
		for prior in 0 ..< index do if value == values[prior] do return false
	}
	return true
}

@(private)
authorities_valid :: proc(values: []Bundle_Authority) -> bool {
	if len(values) > MAX_AUTHORITIES do return false
	for value, index in values {
		if value == .Invalid do return false
		for prior in 0 ..< index do if value == values[prior] do return false
	}
	return true
}

@(private)
authority_present :: proc(values: []Bundle_Authority, expected: Bundle_Authority) -> bool {
	for value in values do if value == expected do return true
	return false
}

@(private)
authority_mask :: proc(values: []Bundle_Authority) -> u8 {
	result: u8
	for value in values do result |= u8(1) << (u8(value) - 1)
	return result
}

@(private)
contribution_mask :: proc(value: Bundle_Contribution_Kind) -> u16 {
	return u16(1) << (u16(value) - 1)
}

@(private)
identity_valid :: proc(value: string) -> bool {
	if !text_valid(value, MAX_IDENTITY_BYTES, false) do return false
	separator := true
	for byte in transmute([]u8)value {
		alphanumeric := (byte >= 'a' && byte <= 'z') || (byte >= '0' && byte <= '9')
		if alphanumeric {
			separator = false
		} else if (byte == '.' || byte == '-') && !separator {
			separator = true
		} else {
			return false
		}
	}
	return !separator
}

@(private)
path_valid :: proc(value: string) -> bool {
	if !text_valid(value, MAX_PATH_BYTES, false) do return false
	bytes := transmute([]u8)value
	if bytes[0] == '/' || bytes[0] == '\\' || (len(bytes) > 1 && bytes[1] == ':') do return false
	segment_length := 0
	segment_dots := 0
	for byte in bytes {
		if byte == '\\' || byte == 0 do return false
		if byte == '/' {
			if segment_length == 0 || segment_length == segment_dots && segment_dots <= 2 do return false
			segment_length, segment_dots = 0, 0
		} else {
			segment_length += 1
			if byte == '.' do segment_dots += 1
		}
	}
	return segment_length > 0 && !(segment_length == segment_dots && segment_dots <= 2)
}

@(private)
text_valid :: proc(value: string, maximum: int, empty: bool) -> bool {
	return (empty || len(value) > 0) && len(value) <= maximum && utf8.valid_string(value)
}

@(private)
version_proposal_valid :: proc(value: Bundle_Version_Proposal) -> bool {
	if len(value.pre_release) == 0 do return true
	if len(value.pre_release) > MAX_IDENTITY_BYTES || !utf8.valid_string(value.pre_release) do return false
	segment_length := 0
	for byte in transmute([]u8)value.pre_release {
		alphanumeric := (byte >= 'a' && byte <= 'z') ||
			(byte >= 'A' && byte <= 'Z') || (byte >= '0' && byte <= '9')
		if alphanumeric || byte == '-' {
			segment_length += 1
		} else if byte == '.' && segment_length > 0 {
			segment_length = 0
		} else {
			return false
		}
	}
	return segment_length > 0
}

@(private)
version_lte_proposal :: proc(left, right: Bundle_Version_Proposal) -> bool {
	if left.major != right.major do return left.major < right.major
	if left.minor != right.minor do return left.minor < right.minor
	if left.patch != right.patch do return left.patch < right.patch
	if left.pre_release == right.pre_release do return true
	if len(left.pre_release) == 0 do return false
	if len(right.pre_release) == 0 do return true
	return left.pre_release < right.pre_release
}

@(private)
version_lte_record_proposal :: proc(left: Bundle_Version, right: Bundle_Version_Proposal) -> bool {
	return version_lte_proposal(version_record_proposal(left), right)
}

@(private)
version_lte_proposal_record :: proc(left: Bundle_Version_Proposal, right: Bundle_Version) -> bool {
	return version_lte_proposal(left, version_record_proposal(right))
}

@(private)
version_record_proposal :: proc(value: Bundle_Version) -> Bundle_Version_Proposal {
	pre_release := value.pre_release
	return Bundle_Version_Proposal {
		major = value.major,
		minor = value.minor,
		patch = value.patch,
		pre_release = identity_text_view(&pre_release),
	}
}

@(private)
bundle_failure :: proc(
	code: Bundle_Failure_Code,
	field := Bundle_Field.None,
	limit := u64(0),
	actual := u64(0),
) -> Bundle_Failure {
	return Bundle_Failure{code = code, field = field, limit = limit, actual = actual}
}
