// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:unicode/utf8"

/* DEFAULT_EXTENSION_ANNOTATIONS_PER_CONTRIBUTOR is the initial owner-local annotation budget. */
DEFAULT_EXTENSION_ANNOTATIONS_PER_CONTRIBUTOR :: u16(64)
/* MAX_EXTENSION_ANNOTATIONS_PER_CONTRIBUTOR is the immutable owner-local annotation ceiling. */
MAX_EXTENSION_ANNOTATIONS_PER_CONTRIBUTOR :: u16(2_048)
/* MAX_EXTENSION_ANNOTATION_DETAIL_BYTES bounds one copied compact detail. */
MAX_EXTENSION_ANNOTATION_DETAIL_BYTES :: 1 * KIBIBYTE
/* MAX_EXTENSION_ANNOTATION_TARGET_BYTES bounds one lossless copied target identity. */
MAX_EXTENSION_ANNOTATION_TARGET_BYTES :: 1_280
/* DEFAULT_EXTENSION_ANNOTATION_COPY_BYTES is the initial complete generation budget. */
DEFAULT_EXTENSION_ANNOTATION_COPY_BYTES :: u64(256 * KIBIBYTE)
/* MAX_EXTENSION_ANNOTATION_COPY_BYTES is the immutable complete generation ceiling. */
MAX_EXTENSION_ANNOTATION_COPY_BYTES :: u64(4 * MEBIBYTE)

/* Extension_Annotation_Generation_ID identifies one immutable annotation projection. */
Extension_Annotation_Generation_ID :: distinct u64
/* Extension_Annotation_ID identifies one stable annotation within its contributor generation. */
Extension_Annotation_ID :: distinct u64

/* Extension_Annotation_Target_Family names every initial semantic target family. */
Extension_Annotation_Target_Family :: enum u8 {
	Invalid,
	Path,
	Diff_Unit,
	Revision,
	Revision_Range,
	Ref,
	Remote,
	Conflict,
	Sequence,
	Process,
}

/* Extension_Annotation_Target is one copied generation-bound semantic identity. */
Extension_Annotation_Target :: struct {
	family:     Extension_Annotation_Target_Family,
	generation: u64,
	identity:   [MAX_EXTENSION_ANNOTATION_TARGET_BYTES]u8,
	length:     u16,
}

/* Extension_Annotation_Observation binds a projection to one copied truth family. */
Extension_Annotation_Observation :: struct {
	family:     Extension_Observation_Family,
	repository: Repository_Context,
	generation: u64,
}

/* Extension_Annotation_Detail owns one bounded copied compact detail. */
Extension_Annotation_Detail :: struct {
	bytes:  [MAX_EXTENSION_ANNOTATION_DETAIL_BYTES]u8,
	length: u16,
}

/* Extension_Annotation_Severity classifies optional provider-owned diagnostics. */
Extension_Annotation_Severity :: enum u8 {
	None,
	Hint,
	Information,
	Warning,
	Error,
}

/* Extension_Annotation_Style names optional theme-backed semantics. */
Extension_Annotation_Style :: enum u8 {
	None,
	Normal,
	Muted,
	Identity,
	Active,
	Success,
	Warning,
	Alert,
	Information,
}

/* Extension_Annotation_Command_Reference identifies one admitted generation-owned command. */
Extension_Annotation_Command_Reference :: struct {
	present:      bool,
	contributor:  Contributor_Handle,
	contribution: Contribution_ID,
	identity:     Extension_Identity,
}

/* Extension_Annotation is one immutable provider-owned target projection. */
Extension_Annotation :: struct {
	id:            Extension_Annotation_ID,
	contribution:  Contribution_ID,
	identity:      Extension_Identity,
	target:        Extension_Annotation_Target,
	label_present: bool,
	label:         Extension_Label,
	detail:        Extension_Annotation_Detail,
	severity:      Extension_Annotation_Severity,
	style:         Extension_Annotation_Style,
	command:       Extension_Annotation_Command_Reference,
}

/* Extension_Annotation_Truncation records why one valid generation is incomplete. */
Extension_Annotation_Truncation :: enum u8 {
	Invalid,
	Complete,
	Annotation_Limit,
	Text_Limit,
	Provider_Limit,
}

/* Extension_Annotation_Generation is one complete observation-bound contributor projection. */
Extension_Annotation_Generation :: struct {
	contributor:          Contributor_Handle,
	contributor_identity: Contributor_Identity,
	generation:           Extension_Annotation_Generation_ID,
	observation:          Extension_Annotation_Observation,
	annotations:          []Extension_Annotation,
	truncation:           Extension_Annotation_Truncation,
}

/* Extension_Annotation_Limits bounds one complete provider-owned annotation generation. */
Extension_Annotation_Limits :: struct {
	annotations_per_contributor: u16,
	copy_bytes:                  u64,
}

/* DEFAULT_EXTENSION_ANNOTATION_LIMITS selects the initial bounded projection envelope. */
DEFAULT_EXTENSION_ANNOTATION_LIMITS :: Extension_Annotation_Limits {
	annotations_per_contributor = DEFAULT_EXTENSION_ANNOTATIONS_PER_CONTRIBUTOR,
	copy_bytes = DEFAULT_EXTENSION_ANNOTATION_COPY_BYTES,
}

/* MAX_EXTENSION_ANNOTATION_LIMITS records every immutable annotation ceiling. */
MAX_EXTENSION_ANNOTATION_LIMITS :: Extension_Annotation_Limits {
	annotations_per_contributor = MAX_EXTENSION_ANNOTATIONS_PER_CONTRIBUTOR,
	copy_bytes = MAX_EXTENSION_ANNOTATION_COPY_BYTES,
}

/* Extension_Annotation_Usage reports exact copied content in one generation. */
Extension_Annotation_Usage :: struct {
	annotations:       u32,
	label_bytes:       u64,
	detail_bytes:      u64,
	copy_bytes:        u64,
	command_references: u32,
	truncated:         bool,
}

/* Extension_Annotation_Failure_Code classifies expected projection rejection. */
Extension_Annotation_Failure_Code :: enum u16 {
	None,
	Invalid_Generation,
	Invalid_Annotation,
	Invalid_Target,
	Invalid_Observation,
	Invalid_Text,
	Invalid_Severity,
	Invalid_Style,
	Invalid_Command,
	Duplicate_Annotation,
	Stale_Contributor,
	Stale_Observation,
	Stale_Target,
	Annotation_Limit,
	Copy_Limit,
}

/* Extension_Annotation_Failure identifies one attributable bounded rejection. */
Extension_Annotation_Failure :: struct {
	code:       Extension_Annotation_Failure_Code,
	annotation: Extension_Annotation_ID,
	target:     Extension_Annotation_Target,
	index:      u32,
	limit:      u64,
	actual:     u64,
}

/* Extension_Annotation_Order_Key fixes contributor, target, then annotation ordering. */
Extension_Annotation_Order_Key :: struct {
	contributor: Contributor_Identity,
	target:      Extension_Annotation_Target,
	annotation:  Extension_Identity,
}

/* extension_annotation_detail_assign copies one checked optional compact detail. */
extension_annotation_detail_assign :: proc(detail: ^Extension_Annotation_Detail, value: string) -> bool {
	if detail == nil do return false
	detail^ = {}
	if len(value) > len(detail.bytes) || !utf8.valid_string(value) do return false
	copy(detail.bytes[:len(value)], transmute([]u8)value)
	detail.length = u16(len(value))
	return true
}

/* extension_annotation_target_assign copies one checked opaque semantic identity. */
extension_annotation_target_assign :: proc(
	target: ^Extension_Annotation_Target,
	family: Extension_Annotation_Target_Family,
	generation: u64,
	identity: []u8,
) -> bool {
	if target == nil do return false
	target^ = {}
	if family == .Invalid || generation == 0 || len(identity) == 0 || len(identity) > len(target.identity) {
		return false
	}
	target.family = family
	target.generation = generation
	copy(target.identity[:len(identity)], identity)
	target.length = u16(len(identity))
	return true
}

/* extension_annotation_limits_are_valid checks one policy against immutable ceilings. */
extension_annotation_limits_are_valid :: proc(limits: Extension_Annotation_Limits) -> bool {
	return limits.annotations_per_contributor > 0 &&
		limits.annotations_per_contributor <= MAX_EXTENSION_ANNOTATIONS_PER_CONTRIBUTOR &&
		limits.copy_bytes > 0 && limits.copy_bytes <= MAX_EXTENSION_ANNOTATION_COPY_BYTES
}

/* extension_annotation_target_is_valid checks one opaque semantic target descriptor. */
extension_annotation_target_is_valid :: proc(target: Extension_Annotation_Target) -> bool {
	return target.family != .Invalid && target.generation != 0 && target.length > 0 &&
		int(target.length) <= len(target.identity)
}

/* extension_annotation_observation_is_valid checks one exact copied observation binding. */
extension_annotation_observation_is_valid :: proc(observation: Extension_Annotation_Observation) -> bool {
	return observation.family <= .Process && repository_context_is_valid(observation.repository) &&
		observation.generation != 0
}

/* extension_annotation_generation_validate checks complete contributor publication atomicity. */
extension_annotation_generation_validate :: proc(
	generation: Extension_Annotation_Generation,
	limits := DEFAULT_EXTENSION_ANNOTATION_LIMITS,
) -> (usage: Extension_Annotation_Usage, failure: Extension_Annotation_Failure) {
	if !extension_annotation_limits_are_valid(limits) ||
	   !contributor_handle_is_valid(generation.contributor) ||
	   !contributor_identity_is_valid(generation.contributor_identity) ||
	   generation.generation == Extension_Annotation_Generation_ID(0) ||
	   generation.truncation == .Invalid {
		return {}, {code = .Invalid_Generation}
	}
	if !extension_annotation_observation_is_valid(generation.observation) {
		return {}, {code = .Invalid_Observation}
	}
	if len(generation.annotations) > int(limits.annotations_per_contributor) {
		return {}, {
			code = .Annotation_Limit,
			limit = u64(limits.annotations_per_contributor),
			actual = u64(len(generation.annotations)),
		}
	}
	usage.annotations = u32(len(generation.annotations))
	usage.copy_bytes = u64(size_of(Extension_Annotation_Generation)) +
		u64(len(generation.annotations) * size_of(Extension_Annotation))
	usage.truncated = generation.truncation != .Complete
	for annotation, index in generation.annotations {
		annotation_failure := extension_annotation_validate(annotation, generation.contributor)
		if annotation_failure.code != .None {
			annotation_failure.index = u32(index)
			return {}, annotation_failure
		}
		if annotation.target.generation != generation.observation.generation ||
		   !extension_annotation_target_supports_observation(annotation.target.family, generation.observation.family) {
			return {}, {
				code = .Stale_Target,
				annotation = annotation.id,
				target = annotation.target,
				index = u32(index),
			}
		}
		for prior in 0 ..< index {
			if generation.annotations[prior].id == annotation.id ||
			   generation.annotations[prior].identity == annotation.identity {
				return {}, {
					code = .Duplicate_Annotation,
					annotation = annotation.id,
					target = annotation.target,
					index = u32(index),
				}
			}
		}
		if annotation.label_present do usage.label_bytes += u64(annotation.label.length)
		usage.detail_bytes += u64(annotation.detail.length)
		if annotation.command.present do usage.command_references += 1
	}
	if usage.copy_bytes > limits.copy_bytes {
		return {}, {code = .Copy_Limit, limit = limits.copy_bytes, actual = usage.copy_bytes}
	}
	return usage, {}
}

/* extension_annotation_generation_matches_observation rejects stale repository truth. */
extension_annotation_generation_matches_observation :: proc(
	generation: Extension_Annotation_Generation,
	observation: Extension_Annotation_Observation,
) -> (bool, Extension_Annotation_Failure) {
	if !extension_annotation_observation_is_valid(observation) ||
	   generation.observation != observation {
		return false, {code = .Stale_Observation}
	}
	return true, {}
}

/* extension_annotation_generation_matches_contributor rejects replaced or disabled owners. */
extension_annotation_generation_matches_contributor :: proc(
	generation: Extension_Annotation_Generation,
	contributor: Contributor_Handle,
) -> (bool, Extension_Annotation_Failure) {
	if !contributor_handle_is_valid(contributor) || generation.contributor != contributor {
		return false, {code = .Stale_Contributor}
	}
	return true, {}
}

/* extension_annotation_matches_target rejects removed or replaced semantic targets. */
extension_annotation_matches_target :: proc(
	annotation: Extension_Annotation,
	target: Extension_Annotation_Target,
) -> (bool, Extension_Annotation_Failure) {
	if !extension_annotation_target_is_valid(target) || annotation.target != target {
		return false, {code = .Stale_Target, annotation = annotation.id, target = annotation.target}
	}
	return true, {}
}

/* extension_annotation_order_key returns the only admitted projection ordering input. */
extension_annotation_order_key :: proc(
	contributor: Contributor_Identity,
	annotation: Extension_Annotation,
) -> Extension_Annotation_Order_Key {
	return {contributor = contributor, target = annotation.target, annotation = annotation.identity}
}

/* extension_annotation_order_key_is_less orders contributor, target, then annotation identity. */
extension_annotation_order_key_is_less :: proc(a, b: Extension_Annotation_Order_Key) -> bool {
	a_copy, b_copy := a, b
	contributor_order := extension_annotation_bytes_compare(
		a_copy.contributor.bytes[:a_copy.contributor.length],
		b_copy.contributor.bytes[:b_copy.contributor.length],
	)
	if contributor_order != 0 do return contributor_order < 0
	if a.target.family != b.target.family do return a.target.family < b.target.family
	if a.target.generation != b.target.generation do return a.target.generation < b.target.generation
	a_target, b_target := a.target, b.target
	target_order := extension_annotation_bytes_compare(
		a_target.identity[:a_target.length],
		b_target.identity[:b_target.length],
	)
	if target_order != 0 do return target_order < 0
	return extension_annotation_bytes_compare(
		a_copy.annotation.bytes[:a_copy.annotation.length],
		b_copy.annotation.bytes[:b_copy.annotation.length],
	) < 0
}

/* extension_annotation_generation_invalidate drops every borrowed projection reference. */
extension_annotation_generation_invalidate :: proc(generation: ^Extension_Annotation_Generation) {
	if generation != nil do generation^ = {}
}

@(private)
extension_annotation_validate :: proc(
	annotation: Extension_Annotation,
	owner: Contributor_Handle,
) -> Extension_Annotation_Failure {
	failure := Extension_Annotation_Failure{annotation = annotation.id, target = annotation.target}
	if annotation.id == Extension_Annotation_ID(0) || annotation.contribution == Contribution_ID(0) ||
	   !extension_identity_is_valid(annotation.identity) {
		failure.code = .Invalid_Annotation
		return failure
	}
	if !extension_annotation_target_is_valid(annotation.target) {
		failure.code = .Invalid_Target
		return failure
	}
	if annotation.label_present {
		if !extension_label_is_valid(annotation.label) {
			failure.code = .Invalid_Text
			return failure
		}
	} else if annotation.label != (Extension_Label{}) {
		failure.code = .Invalid_Text
		return failure
	}
	if !extension_annotation_detail_is_valid(annotation.detail) {
		failure.code = .Invalid_Text
		return failure
	}
	if annotation.severity > .Error {
		failure.code = .Invalid_Severity
		return failure
	}
	if annotation.style > .Information {
		failure.code = .Invalid_Style
		return failure
	}
	if annotation.command.present {
		if !contributor_handle_is_valid(annotation.command.contributor) ||
		   annotation.command.contributor != owner ||
		   annotation.command.contribution == Contribution_ID(0) ||
		   !extension_identity_is_valid(annotation.command.identity) {
			failure.code = .Invalid_Command
			return failure
		}
	} else if annotation.command != (Extension_Annotation_Command_Reference{}) {
		failure.code = .Invalid_Command
		return failure
	}
	if !annotation.label_present && annotation.detail.length == 0 && annotation.severity == .None &&
	   annotation.style == .None && !annotation.command.present {
		failure.code = .Invalid_Annotation
		return failure
	}
	return {}
}

@(private)
extension_annotation_detail_is_valid :: proc(detail: Extension_Annotation_Detail) -> bool {
	if int(detail.length) > len(detail.bytes) do return false
	copy_value := detail
	return utf8.valid_string(string(copy_value.bytes[:copy_value.length]))
}

@(private)
extension_annotation_target_supports_observation :: proc(
	target: Extension_Annotation_Target_Family,
	observation: Extension_Observation_Family,
) -> bool {
	switch target {
	case .Path, .Diff_Unit:       return observation == .Status
	case .Revision, .Revision_Range: return observation == .History
	case .Ref, .Remote:           return observation == .Refs
	case .Conflict:               return observation == .Conflict || observation == .Sequence
	case .Sequence:               return observation == .Sequence
	case .Process:                return observation == .Process
	case .Invalid:                return false
	}
	return false
}

@(private)
extension_annotation_bytes_compare :: proc(a, b: []u8) -> int {
	count := min(len(a), len(b))
	for index in 0 ..< count {
		if a[index] < b[index] do return -1
		if a[index] > b[index] do return 1
	}
	if len(a) < len(b) do return -1
	if len(a) > len(b) do return 1
	return 0
}
