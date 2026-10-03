// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_bundle

import "base:runtime"
import json "core:encoding/json"

LANGUAGE_BUNDLE_BRIDGE_SCHEMA :: i64(1)
MAX_LANGUAGE_BUNDLE_BYTES :: 2 * 1_024 * 1_024

Bundle_Bridge :: struct {
	generation: u64,
	preparing:  bool,
}

Bundle_Bridge_Candidate :: struct {
	bundle:          Bundle_Candidate,
	base_generation: u64,
	generation:      u64,
	live:            bool,
}

@(private)
Decoded_Dependency :: struct {
	facets:  [6]Bundle_Contribution_Kind,
	targets: [MAX_TARGETS]Bundle_Target,
}

@(private)
Decoded_Artifact :: struct {
	targets: [MAX_TARGETS]Bundle_Target,
}

bundle_bridge_prepare :: proc(
	bridge: ^Bundle_Bridge,
	input: []u8,
	expected_generation, proposed_generation: u64,
	allocator := context.allocator,
) -> (result: Bundle_Bridge_Candidate, ok: bool, failure: Bundle_Failure) {
	if bridge == nil do return {}, false, bundle_failure(.Invalid_Candidate)
	if bridge.preparing do return {}, false, bundle_failure(.Reentrant_Preparation)
	if expected_generation != bridge.generation || proposed_generation <= expected_generation {
		return {}, false, bundle_failure(
			.Stale_Generation, .None, bridge.generation, expected_generation,
		)
	}
	if len(input) == 0 || len(input) > MAX_LANGUAGE_BUNDLE_BYTES {
		return {}, false, bundle_failure(
			.Limit, .None, MAX_LANGUAGE_BUNDLE_BYTES, u64(len(input)),
		)
	}
	bridge.preparing = true
	defer bridge.preparing = false
	value, parse_error := json.parse_bytes(input, .JSON, true, context.temp_allocator)
	if parse_error != .None {
		json.destroy_value(value, context.temp_allocator)
		return {}, false, bundle_failure(.Malformed_Encoding)
	}
	defer json.destroy_value(value, context.temp_allocator)
	candidate, prepared, prepare_failure := decode_bundle_candidate(value, allocator)
	if !prepared do return {}, false, prepare_failure
	return Bundle_Bridge_Candidate {
		bundle = candidate,
		base_generation = expected_generation,
		generation = proposed_generation,
		live = true,
	}, true, {}
}

bundle_bridge_confirm :: proc(
	bridge: ^Bundle_Bridge,
	candidate: ^Bundle_Bridge_Candidate,
) -> (bool, Bundle_Failure) {
	if bridge == nil || candidate == nil || !candidate.live {
		return false, bundle_failure(.Invalid_Candidate)
	}
	if bridge.preparing do return false, bundle_failure(.Reentrant_Preparation)
	if bridge.generation != candidate.base_generation || candidate.generation <= bridge.generation {
		return false, bundle_failure(
			.Stale_Generation, .None, bridge.generation, candidate.base_generation,
		)
	}
	bridge.generation = candidate.generation
	return true, {}
}

bundle_bridge_candidate_close :: proc(
	candidate: ^Bundle_Bridge_Candidate,
) -> (bool, Bundle_Failure) {
	if candidate == nil || !candidate.live do return false, bundle_failure(.Closed_Candidate)
	closed, failure := bundle_candidate_close(&candidate.bundle)
	if !closed do return false, failure
	candidate^ = {}
	return true, {}
}

@(private)
decode_bundle_candidate :: proc(
	value: json.Value,
	allocator: runtime.Allocator,
) -> (Bundle_Candidate, bool, Bundle_Failure) {
	root, root_ok := value.(json.Object)
	if !root_ok || len(root) != 16 do return {}, false, bundle_failure(.Malformed_Encoding)
	schema, schema_ok := object_integer(root, "schema")
	format_version, format_ok := object_integer(root, "format-version")
	identity, identity_ok := object_string(root, "id")
	display_name, display_ok := object_string(root, "display-name")
	description, description_ok := object_string(root, "description")
	publisher, publisher_ok := object_string(root, "publisher")
	source, source_ok := object_string(root, "source")
	provenance, provenance_ok := object_string(root, "provenance")
	version_value, version_present := root["version"]
	api_value, api_present := root["api-range"]
	targets_value, targets_present := root["targets"]
	dependencies_value, dependencies_present := root["dependencies"]
	authorities_value, authorities_present := root["authorities"]
	contributions_value, contributions_present := root["contributions"]
	artifacts_value, artifacts_present := root["artifacts"]
	entrypoint_value, entrypoint_present := root["entrypoint"]
	if !schema_ok || schema != LANGUAGE_BUNDLE_BRIDGE_SCHEMA || !format_ok ||
	   !identity_ok || !display_ok || !description_ok || !publisher_ok || !source_ok ||
	   !provenance_ok || !version_present || !api_present || !targets_present ||
	   !dependencies_present || !authorities_present || !contributions_present ||
	   !artifacts_present || !entrypoint_present {
		return {}, false, bundle_failure(.Malformed_Encoding)
	}
	version, version_ok := decode_version(version_value)
	api_range, api_ok := decode_api_range(api_value)
	target_values, targets_ok := targets_value.(json.Array)
	dependency_values, dependencies_ok := dependencies_value.(json.Array)
	authority_values, authorities_ok := authorities_value.(json.Array)
	contribution_values, contributions_ok := contributions_value.(json.Array)
	artifact_values, artifacts_ok := artifacts_value.(json.Array)
	if !version_ok || !api_ok || !targets_ok || !dependencies_ok || !authorities_ok ||
	   !contributions_ok || !artifacts_ok || len(target_values) > MAX_TARGETS ||
	   len(dependency_values) > MAX_DEPENDENCIES || len(authority_values) > MAX_AUTHORITIES ||
	   len(contribution_values) > MAX_CONTRIBUTIONS || len(artifact_values) > MAX_ARTIFACTS {
		return {}, false, bundle_failure(.Malformed_Encoding)
	}
	targets: [MAX_TARGETS]Bundle_Target
	if !decode_targets(target_values, targets[:len(target_values)]) do return {}, false, bundle_failure(.Malformed_Encoding)
	authorities: [MAX_AUTHORITIES]Bundle_Authority
	if !decode_authorities(authority_values, authorities[:len(authority_values)]) do return {}, false, bundle_failure(.Malformed_Encoding)
	dependency_storage: [MAX_DEPENDENCIES]Decoded_Dependency
	dependencies: [MAX_DEPENDENCIES]Bundle_Dependency_Proposal
	for entry, index in dependency_values {
		decoded, decoded_ok := decode_dependency(entry, &dependency_storage[index])
		if !decoded_ok do return {}, false, bundle_failure(.Malformed_Encoding)
		dependencies[index] = decoded
	}
	artifact_storage: [MAX_ARTIFACTS]Decoded_Artifact
	artifacts: [MAX_ARTIFACTS]Bundle_Artifact_Proposal
	for entry, index in artifact_values {
		decoded, decoded_ok := decode_artifact(entry, &artifact_storage[index])
		if !decoded_ok do return {}, false, bundle_failure(.Malformed_Encoding)
		artifacts[index] = decoded
	}
	language_references: [MAX_CONTRIBUTION_REFERENCES]string
	artifact_references: [MAX_CONTRIBUTION_REFERENCES]string
	dependency_references: [MAX_CONTRIBUTION_REFERENCES]string
	contribution_authorities: [MAX_CONTRIBUTION_REFERENCES]Bundle_Authority
	language_count, artifact_count, dependency_count, authority_count := 0, 0, 0, 0
	contributions: [MAX_CONTRIBUTIONS]Bundle_Contribution_Proposal
	for entry, index in contribution_values {
		decoded, decoded_ok := decode_contribution(
			entry,
			language_references[:], &language_count,
			artifact_references[:], &artifact_count,
			dependency_references[:], &dependency_count,
			contribution_authorities[:], &authority_count,
		)
		if !decoded_ok do return {}, false, bundle_failure(.Malformed_Encoding)
		contributions[index] = decoded
	}
	entrypoint := ""
	#partial switch decoded_entrypoint in entrypoint_value {
	case json.String:
		entrypoint = string(decoded_entrypoint)
	case json.Null:
	case:
		return {}, false, bundle_failure(.Malformed_Encoding)
	}
	proposal := Bundle_Proposal {
		format_version = u16(format_version),
		identity = identity,
		display_name = display_name,
		version = version,
		api_range = api_range,
		description = description,
		publisher = publisher,
		source = source,
		provenance = provenance,
		targets = targets[:len(target_values)],
		dependencies = dependencies[:len(dependency_values)],
		authorities = authorities[:len(authority_values)],
		contributions = contributions[:len(contribution_values)],
		artifacts = artifacts[:len(artifact_values)],
		entrypoint = entrypoint,
	}
	return bundle_candidate_prepare(proposal, allocator)
}

@(private)
decode_version :: proc(value: json.Value) -> (Bundle_Version_Proposal, bool) {
	object, ok := value.(json.Object)
	if !ok || len(object) != 4 do return {}, false
	major, major_ok := object_integer(object, "major")
	minor, minor_ok := object_integer(object, "minor")
	patch, patch_ok := object_integer(object, "patch")
	pre_value, pre_present := object["pre-release"]
	if !major_ok || !minor_ok || !patch_ok || !pre_present ||
	   major < 0 || minor < 0 || patch < 0 ||
	   major > i64(max(u32)) || minor > i64(max(u32)) || patch > i64(max(u32)) {
		return {}, false
	}
	pre_release := ""
	#partial switch decoded_pre_release in pre_value {
	case json.String:
		pre_release = string(decoded_pre_release)
	case json.Null:
	case:
		return {}, false
	}
	return Bundle_Version_Proposal {
		major = u32(major), minor = u32(minor), patch = u32(patch),
		pre_release = pre_release,
	}, true
}

@(private)
decode_api_range :: proc(value: json.Value) -> (Bundle_API_Range_Proposal, bool) {
	object, ok := value.(json.Object)
	if !ok || len(object) != 2 do return {}, false
	minimum_value, minimum_present := object["minimum"]
	maximum_value, maximum_present := object["maximum"]
	if !minimum_present || !maximum_present do return {}, false
	minimum, minimum_ok := decode_version(minimum_value)
	maximum, maximum_ok := decode_version(maximum_value)
	return Bundle_API_Range_Proposal{minimum = minimum, maximum = maximum}, minimum_ok && maximum_ok
}

@(private)
decode_targets :: proc(values: json.Array, output: []Bundle_Target) -> bool {
	if len(values) != len(output) do return false
	for value, index in values {
		object, ok := value.(json.Object)
		if !ok || len(object) != 2 do return false
		platform_text, platform_ok := object_string(object, "platform")
		architecture_text, architecture_ok := object_string(object, "architecture")
		platform, platform_known := decode_platform(platform_text)
		architecture, architecture_known := decode_architecture(architecture_text)
		if !platform_ok || !architecture_ok || !platform_known || !architecture_known do return false
		output[index] = Bundle_Target{platform = platform, architecture = architecture}
	}
	return true
}

@(private)
decode_authorities :: proc(values: json.Array, output: []Bundle_Authority) -> bool {
	if len(values) != len(output) do return false
	for value, index in values {
		text_value, ok := value.(json.String)
		if !ok do return false
		authority, known := decode_authority(string(text_value))
		if !known do return false
		output[index] = authority
	}
	return true
}

@(private)
decode_dependency :: proc(value: json.Value, storage: ^Decoded_Dependency) -> (Bundle_Dependency_Proposal, bool) {
	object, ok := value.(json.Object)
	if !ok || len(object) != 6 do return {}, false
	identity, identity_ok := object_string(object, "id")
	minimum_value, minimum_present := object["minimum"]
	maximum_value, maximum_present := object["maximum"]
	optional_value, optional_present := object["optional"]
	facets_value, facets_present := object["facets"]
	targets_value, targets_present := object["targets"]
	optional, optional_ok := optional_value.(json.Boolean)
	facets, facets_ok := facets_value.(json.Array)
	targets, targets_ok := targets_value.(json.Array)
	if !identity_ok || !minimum_present || !maximum_present || !optional_present || !optional_ok ||
	   !facets_present || !facets_ok || !targets_present || !targets_ok ||
	   len(facets) > len(storage.facets) || len(targets) > MAX_TARGETS {
		return {}, false
	}
	minimum, minimum_ok := decode_version(minimum_value)
	maximum, maximum_ok := decode_version(maximum_value)
	if !minimum_ok || !maximum_ok || !decode_facets(facets, storage.facets[:len(facets)]) ||
	   !decode_targets(targets, storage.targets[:len(targets)]) {
		return {}, false
	}
	return Bundle_Dependency_Proposal {
		identity = identity, minimum = minimum, maximum = maximum,
		optional = bool(optional), facets = storage.facets[:len(facets)],
		targets = storage.targets[:len(targets)],
	}, true
}

@(private)
decode_artifact :: proc(value: json.Value, storage: ^Decoded_Artifact) -> (Bundle_Artifact_Proposal, bool) {
	object, ok := value.(json.Object)
	if !ok || len(object) != 7 do return {}, false
	identity, identity_ok := object_string(object, "id")
	kind_text, kind_ok := object_string(object, "kind")
	path, path_ok := object_string(object, "path")
	digest, digest_ok := object_string(object, "digest")
	size, size_ok := object_integer(object, "size")
	targets_value, targets_present := object["targets"]
	authority_value, authority_present := object["authority"]
	targets, targets_ok := targets_value.(json.Array)
	kind, kind_known := decode_artifact_kind(kind_text)
	if !identity_ok || !kind_ok || !kind_known || !path_ok || !digest_ok || !size_ok ||
	   size < 0 || !targets_present || !targets_ok || len(targets) > MAX_TARGETS ||
	   !authority_present || !decode_targets(targets, storage.targets[:len(targets)]) {
		return {}, false
	}
	digest_bytes, digest_decoded := decode_digest(digest)
	if !digest_decoded do return {}, false
	authority := Bundle_Authority.Invalid
	#partial switch decoded_authority in authority_value {
	case json.String:
		decoded, known := decode_authority(string(decoded_authority))
		if !known do return {}, false
		authority = decoded
	case json.Null:
	case:
		return {}, false
	}
	return Bundle_Artifact_Proposal {
		identity = identity, kind = kind, path = path, digest = digest_bytes,
		size = u64(size), targets = storage.targets[:len(targets)], authority = authority,
	}, true
}

@(private)
decode_contribution :: proc(
	value: json.Value,
	language_storage: []string, language_count: ^int,
	artifact_storage: []string, artifact_count: ^int,
	dependency_storage: []string, dependency_count: ^int,
	authority_storage: []Bundle_Authority, authority_count: ^int,
) -> (Bundle_Contribution_Proposal, bool) {
	object, ok := value.(json.Object)
	if !ok || len(object) != 6 do return {}, false
	kind_text, kind_ok := object_string(object, "kind")
	identity, identity_ok := object_string(object, "id")
	languages_value, languages_present := object["languages"]
	artifacts_value, artifacts_present := object["artifacts"]
	dependencies_value, dependencies_present := object["dependencies"]
	authorities_value, authorities_present := object["authorities"]
	languages, languages_ok := languages_value.(json.Array)
	artifacts, artifacts_ok := artifacts_value.(json.Array)
	dependencies, dependencies_ok := dependencies_value.(json.Array)
	authorities, authorities_ok := authorities_value.(json.Array)
	kind, kind_known := decode_contribution_kind(kind_text)
	if !kind_ok || !kind_known || !identity_ok || !languages_present || !languages_ok ||
	   !artifacts_present || !artifacts_ok || !dependencies_present || !dependencies_ok ||
	   !authorities_present || !authorities_ok {
		return {}, false
	}
	language_start := language_count^
	artifact_start := artifact_count^
	dependency_start := dependency_count^
	authority_start := authority_count^
	if !decode_string_references(languages, language_storage, language_count) ||
	   !decode_string_references(artifacts, artifact_storage, artifact_count) ||
	   !decode_string_references(dependencies, dependency_storage, dependency_count) ||
	   authority_count^ + len(authorities) > len(authority_storage) {
		return {}, false
	}
	for entry in authorities {
		text_value, text_ok := entry.(json.String)
		if !text_ok do return {}, false
		authority, known := decode_authority(string(text_value))
		if !known do return {}, false
		authority_storage[authority_count^] = authority
		authority_count^ += 1
	}
	return Bundle_Contribution_Proposal {
		kind = kind,
		identity = identity,
		languages = language_storage[language_start:language_count^],
		artifacts = artifact_storage[artifact_start:artifact_count^],
		dependencies = dependency_storage[dependency_start:dependency_count^],
		authorities = authority_storage[authority_start:authority_count^],
	}, true
}

@(private)
decode_string_references :: proc(values: json.Array, storage: []string, count: ^int) -> bool {
	if count^ + len(values) > len(storage) do return false
	for value in values {
		text_value, ok := value.(json.String)
		if !ok do return false
		storage[count^] = string(text_value)
		count^ += 1
	}
	return true
}

@(private)
decode_facets :: proc(values: json.Array, output: []Bundle_Contribution_Kind) -> bool {
	if len(values) != len(output) do return false
	for value, index in values {
		text_value, ok := value.(json.String)
		if !ok do return false
		facet, known := decode_contribution_kind(string(text_value))
		if !known do return false
		output[index] = facet
	}
	return true
}

@(private)
object_string :: proc(object: json.Object, name: string) -> (string, bool) {
	value, present := object[name]
	if !present do return "", false
	text, ok := value.(json.String)
	return string(text), ok
}

@(private)
object_integer :: proc(object: json.Object, name: string) -> (i64, bool) {
	value, present := object[name]
	if !present do return 0, false
	integer, ok := value.(json.Integer)
	return i64(integer), ok
}

@(private)
decode_platform :: proc(value: string) -> (Bundle_Platform, bool) {
	switch value {
	case "darwin": return .Darwin, true
	case "linux": return .Linux, true
	case "windows": return .Windows, true
	}
	return .Invalid, false
}

@(private)
decode_architecture :: proc(value: string) -> (Bundle_Architecture, bool) {
	switch value {
	case "aarch64": return .Aarch64, true
	case "x86-64": return .X86_64, true
	}
	return .Invalid, false
}

@(private)
decode_authority :: proc(value: string) -> (Bundle_Authority, bool) {
	switch value {
	case "racket-extension": return .Racket_Extension, true
	case "external-process": return .External_Process, true
	case "project-read": return .Project_Read, true
	case "project-write": return .Project_Write, true
	case "network-acquisition": return .Network_Acquisition, true
	case "native-grammar": return .Native_Grammar, true
	}
	return .Invalid, false
}

@(private)
decode_artifact_kind :: proc(value: string) -> (Bundle_Artifact_Kind, bool) {
	switch value {
	case "data": return .Data, true
	case "documentation": return .Documentation, true
	case "executable": return .Executable, true
	case "license": return .License, true
	case "manifest": return .Manifest, true
	case "query": return .Query, true
	case "racket-module": return .Racket_Module, true
	case "tree-sitter-grammar": return .Tree_Sitter_Grammar, true
	}
	return .Invalid, false
}

@(private)
decode_contribution_kind :: proc(value: string) -> (Bundle_Contribution_Kind, bool) {
	switch value {
	case "command": return .Command, true
	case "formatter": return .Formatter, true
	case "keymap": return .Keymap, true
	case "language": return .Language, true
	case "service": return .Service, true
	case "syntax-provider": return .Syntax_Provider, true
	}
	return .Invalid, false
}

@(private)
decode_digest :: proc(value: string) -> ([32]u8, bool) {
	result: [32]u8
	if len(value) != 64 do return result, false
	for index in 0 ..< 32 {
		high, high_ok := hexadecimal_nibble(value[index * 2])
		low, low_ok := hexadecimal_nibble(value[index * 2 + 1])
		if !high_ok || !low_ok do return {}, false
		result[index] = high << 4 | low
	}
	return result, true
}

@(private)
hexadecimal_nibble :: proc(value: u8) -> (u8, bool) {
	if value >= '0' && value <= '9' do return value - '0', true
	if value >= 'a' && value <= 'f' do return value - 'a' + 10, true
	return 0, false
}
