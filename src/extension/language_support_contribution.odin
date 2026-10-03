// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package extension owns package contribution metadata and discovery classification.
package extension

import "base:runtime"
import "core:strings"
import "core:unicode/utf8"

/* MAX_PACKAGE_IDENTITY_BYTES bounds one stable package identity. */
MAX_PACKAGE_IDENTITY_BYTES :: 96
/* MAX_PACKAGE_PROVENANCE_BYTES bounds one copied package provenance description. */
MAX_PACKAGE_PROVENANCE_BYTES :: 256
/* MAX_LANGUAGE_IDENTITY_BYTES bounds one affected language identity. */
MAX_LANGUAGE_IDENTITY_BYTES :: 96
/* MAX_AFFECTED_LANGUAGES bounds one package's discovery identities. */
MAX_AFFECTED_LANGUAGES :: 16
/* MAX_LANGUAGE_SUPPORT_PAYLOAD_BYTES bounds one inert contribution payload. */
MAX_LANGUAGE_SUPPORT_PAYLOAD_BYTES :: 128 * 1_024
/* MAX_PACKAGE_EXECUTABLE_ARTIFACT_BYTES bounds one package-owned executable path. */
MAX_PACKAGE_EXECUTABLE_ARTIFACT_BYTES :: 1_024

/* Package_Generation identifies one exact package contribution generation. */
Package_Generation :: distinct u64

/* Contribution_Facet classifies one declared editor contribution for discovery. */
Contribution_Facet :: enum u8 {
	Invalid,
	Language,
	Language_Service,
	Syntax,
	Formatter,
	Commands,
	Theme,
}

/* Contribution_Facets collects independent transverse contribution classifications. */
Contribution_Facets :: bit_set[Contribution_Facet]

/* Package_Platform identifies one supported operating-system family. */
Package_Platform :: enum u8 {
	Invalid,
	Linux,
	Darwin,
	Windows,
}

/* Package_Platforms collects supported operating-system families. */
Package_Platforms :: bit_set[Package_Platform]

/* Package_Architecture identifies one supported machine architecture. */
Package_Architecture :: enum u8 {
	Invalid,
	X86_64,
	AArch64,
}

/* Package_Architectures collects supported machine architectures. */
Package_Architectures :: bit_set[Package_Architecture]

/* Package_Authority identifies one required editor or operating-system authority. */
Package_Authority :: enum u8 {
	Invalid,
	Inspect,
	Filesystem_Read,
	Process,
	Environment,
}

/* Package_Authorities collects independently reviewed package authorities. */
Package_Authorities :: bit_set[Package_Authority]

/* Package_Contribution_Failure_Code classifies one rejected package payload. */
Package_Contribution_Failure_Code :: enum u8 {
	None,
	Invalid_Proposal,
	Identity,
	Generation,
	Payload,
	Facet,
	Affected_Language,
	Platform,
	Architecture,
	Authority,
	Executable_Artifact,
	Provenance,
	Allocation,
}

/* Package_Contribution_Failure retains bounded rejection context. */
Package_Contribution_Failure :: struct {
	code:   Package_Contribution_Failure_Code,
	index:  u16,
	limit:  u64,
	actual: u64,
}

/* Package_Identity_Text is one copied stable package identity. */
Package_Identity_Text :: struct {
	bytes:  [MAX_PACKAGE_IDENTITY_BYTES]u8,
	length: u16,
}

/* Language_Identity_Text is one copied affected language identity. */
Language_Identity_Text :: struct {
	bytes:  [MAX_LANGUAGE_IDENTITY_BYTES]u8,
	length: u16,
}

/* Package_Provenance_Text is one copied package provenance description. */
Package_Provenance_Text :: struct {
	bytes:  [MAX_PACKAGE_PROVENANCE_BYTES]u8,
	length: u16,
}

/* Package_Language_Support_Proposal borrows one complete inert package payload. */
Package_Language_Support_Proposal :: struct {
	package_identity:    string,
	generation:          Package_Generation,
	payload:             []u8,
	facets:              []Contribution_Facet,
	affected_languages:  []string,
	platforms:           []Package_Platform,
	architectures:       []Package_Architecture,
	authorities:         []Package_Authority,
	executable_artifact: string,
	provenance:          string,
}

/* Package_Language_Support_Descriptor is one pointer-free discovery record. */
Package_Language_Support_Descriptor :: struct {
	package_identity:    Package_Identity_Text,
	generation:          Package_Generation,
	facets:              Contribution_Facets,
	affected_languages:  [MAX_AFFECTED_LANGUAGES]Language_Identity_Text,
	affected_language_count: u8,
	platforms:           Package_Platforms,
	architectures:       Package_Architectures,
	authorities:         Package_Authorities,
	executable_artifact: [MAX_PACKAGE_EXECUTABLE_ARTIFACT_BYTES]u8,
	executable_artifact_length: u16,
	provenance:          Package_Provenance_Text,
}

/* Package_Language_Support_Candidate owns one validated but inactive payload. */
Package_Language_Support_Candidate :: struct {
	descriptor: Package_Language_Support_Descriptor,
	payload:    []u8,
	allocator:  runtime.Allocator,
	live:       bool,
}

/* package_language_support_prepare validates and owns one inert package contribution. */
package_language_support_prepare :: proc(
	proposal: Package_Language_Support_Proposal,
	allocator := context.allocator,
) -> (candidate: Package_Language_Support_Candidate, ok: bool, failure: Package_Contribution_Failure) {
	if allocator.procedure == nil {
		return {}, false, {code = .Allocation}
	}
	if !package_text_valid(proposal.package_identity, MAX_PACKAGE_IDENTITY_BYTES, false) {
		return {}, false, {code = .Identity, limit = MAX_PACKAGE_IDENTITY_BYTES, actual = u64(len(proposal.package_identity))}
	}
	if proposal.generation == 0 {
		return {}, false, {code = .Generation}
	}
	if len(proposal.payload) == 0 || len(proposal.payload) > MAX_LANGUAGE_SUPPORT_PAYLOAD_BYTES {
		return {}, false, {code = .Payload, limit = MAX_LANGUAGE_SUPPORT_PAYLOAD_BYTES, actual = u64(len(proposal.payload))}
	}
	if !package_text_valid(proposal.provenance, MAX_PACKAGE_PROVENANCE_BYTES, false) {
		return {}, false, {code = .Provenance, limit = MAX_PACKAGE_PROVENANCE_BYTES, actual = u64(len(proposal.provenance))}
	}

	descriptor := Package_Language_Support_Descriptor {
		package_identity = package_identity_copy(proposal.package_identity),
		generation = proposal.generation,
		provenance = package_provenance_copy(proposal.provenance),
	}
	for facet, index in proposal.facets {
		if facet == .Invalid || facet in descriptor.facets {
			return {}, false, {code = .Facet, index = u16(index)}
		}
		descriptor.facets += {facet}
	}
	if card(descriptor.facets) == 0 ||
	   (.Language not_in descriptor.facets && .Language_Service not_in descriptor.facets) {
		return {}, false, {code = .Facet}
	}
	if len(proposal.affected_languages) == 0 || len(proposal.affected_languages) > MAX_AFFECTED_LANGUAGES {
		return {}, false, {code = .Affected_Language, limit = MAX_AFFECTED_LANGUAGES, actual = u64(len(proposal.affected_languages))}
	}
	for identity, index in proposal.affected_languages {
		if !package_text_valid(identity, MAX_LANGUAGE_IDENTITY_BYTES, false) {
			return {}, false, {code = .Affected_Language, index = u16(index)}
		}
		for prior in 0 ..< index {
			if identity == proposal.affected_languages[prior] {
				return {}, false, {code = .Affected_Language, index = u16(index)}
			}
		}
		descriptor.affected_languages[index] = language_identity_copy(identity)
		descriptor.affected_language_count += 1
	}
	package_sort_language_identities(&descriptor)
	for platform, index in proposal.platforms {
		if platform == .Invalid || platform in descriptor.platforms {
			return {}, false, {code = .Platform, index = u16(index)}
		}
		descriptor.platforms += {platform}
	}
	if card(descriptor.platforms) == 0 do return {}, false, {code = .Platform}
	for architecture, index in proposal.architectures {
		if architecture == .Invalid || architecture in descriptor.architectures {
			return {}, false, {code = .Architecture, index = u16(index)}
		}
		descriptor.architectures += {architecture}
	}
	if card(descriptor.architectures) == 0 do return {}, false, {code = .Architecture}
	for authority, index in proposal.authorities {
		if authority == .Invalid || authority in descriptor.authorities {
			return {}, false, {code = .Authority, index = u16(index)}
		}
		descriptor.authorities += {authority}
	}
	if .Inspect not_in descriptor.authorities ||
	   (.Language_Service in descriptor.facets && .Process not_in descriptor.authorities) {
		return {}, false, {code = .Authority}
	}
	if len(proposal.executable_artifact) > 0 {
		if !package_absolute_path_valid(proposal.executable_artifact) {
			return {}, false, {code = .Executable_Artifact}
		}
		if .Filesystem_Read not_in descriptor.authorities || .Process not_in descriptor.authorities {
			return {}, false, {code = .Authority}
		}
		copy(descriptor.executable_artifact[:], transmute([]u8)proposal.executable_artifact)
		descriptor.executable_artifact_length = u16(len(proposal.executable_artifact))
	}
	payload, allocation_error := make([]u8, len(proposal.payload), allocator)
	if allocation_error != nil do return {}, false, {code = .Allocation}
	copy(payload, proposal.payload)
	candidate = {
		descriptor = descriptor,
		payload = payload,
		allocator = allocator,
		live = true,
	}
	return candidate, true, {}
}

/* package_language_support_close releases one prepared contribution exactly once. */
package_language_support_close :: proc(candidate: ^Package_Language_Support_Candidate) -> bool {
	if candidate == nil || !candidate.live || candidate.allocator.procedure == nil do return false
	delete(candidate.payload, candidate.allocator)
	candidate^ = {}
	return true
}

/* package_language_support_discovery copies inert facets without activating the payload. */
package_language_support_discovery :: proc(
	candidate: ^Package_Language_Support_Candidate,
) -> (Package_Language_Support_Descriptor, bool) {
	if candidate == nil || !candidate.live do return {}, false
	return candidate.descriptor, true
}

/* package_identity_text_view borrows one copied package identity. */
package_identity_text_view :: proc(value: ^Package_Identity_Text) -> string {
	if value == nil || value.length > MAX_PACKAGE_IDENTITY_BYTES do return ""
	return string(value.bytes[:value.length])
}

/* language_identity_text_view borrows one copied affected language identity. */
language_identity_text_view :: proc(value: ^Language_Identity_Text) -> string {
	if value == nil || value.length > MAX_LANGUAGE_IDENTITY_BYTES do return ""
	return string(value.bytes[:value.length])
}

/* package_executable_artifact_view borrows the package-owned artifact path. */
package_executable_artifact_view :: proc(value: ^Package_Language_Support_Descriptor) -> string {
	if value == nil || value.executable_artifact_length > len(value.executable_artifact) do return ""
	return string(value.executable_artifact[:value.executable_artifact_length])
}

/* package_provenance_text_view borrows one copied package provenance description. */
package_provenance_text_view :: proc(value: ^Package_Provenance_Text) -> string {
	if value == nil || value.length > MAX_PACKAGE_PROVENANCE_BYTES do return ""
	return string(value.bytes[:value.length])
}

@(private)
package_text_valid :: proc(value: string, maximum: int, empty: bool) -> bool {
	return len(value) <= maximum && (empty || len(value) > 0) && utf8.valid_string(value) &&
		strings.index_byte(value, 0) < 0
}

@(private)
package_absolute_path_valid :: proc(value: string) -> bool {
	return package_text_valid(value, len(Package_Language_Support_Descriptor{}.executable_artifact), false) &&
		strings.has_prefix(value, "/")
}

@(private)
package_identity_copy :: proc(value: string) -> Package_Identity_Text {
	result: Package_Identity_Text
	copy(result.bytes[:], transmute([]u8)value)
	result.length = u16(len(value))
	return result
}

@(private)
language_identity_copy :: proc(value: string) -> Language_Identity_Text {
	result: Language_Identity_Text
	copy(result.bytes[:], transmute([]u8)value)
	result.length = u16(len(value))
	return result
}

@(private)
package_provenance_copy :: proc(value: string) -> Package_Provenance_Text {
	result: Package_Provenance_Text
	copy(result.bytes[:], transmute([]u8)value)
	result.length = u16(len(value))
	return result
}

@(private)
package_sort_language_identities :: proc(descriptor: ^Package_Language_Support_Descriptor) {
	for right in 1 ..< int(descriptor.affected_language_count) {
		left := right
		for left > 0 && language_identity_text_view(&descriptor.affected_languages[left]) <
		                    language_identity_text_view(&descriptor.affected_languages[left - 1]) {
			descriptor.affected_languages[left], descriptor.affected_languages[left - 1] =
				descriptor.affected_languages[left - 1], descriptor.affected_languages[left]
			left -= 1
		}
	}
}
