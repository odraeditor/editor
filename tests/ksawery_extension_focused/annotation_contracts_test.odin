// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_extension_focused

import ksawery "../../src/ksawery"
import "core:testing"

annotation_contract_test_generation :: proc(
	annotations: ^[2]ksawery.Extension_Annotation,
) -> ksawery.Extension_Annotation_Generation {
	contributor_identity: ksawery.Contributor_Identity
	_ = ksawery.contributor_identity_assign(&contributor_identity, "personal.repository-tools")
	repository: ksawery.Repository_Context
	_ = ksawery.repository_context_assign(&repository, "/tmp/odra-ksawery-extension-annotations")
	first_identity, second_identity, command_identity: ksawery.Extension_Identity
	_ = ksawery.extension_identity_assign(&first_identity, "annotation.branch-policy")
	_ = ksawery.extension_identity_assign(&second_identity, "annotation.review")
	_ = ksawery.extension_identity_assign(&command_identity, "command.open-history")
	label: ksawery.Extension_Label
	_ = ksawery.extension_label_assign(&label, "Protected")
	detail: ksawery.Extension_Annotation_Detail
	_ = ksawery.extension_annotation_detail_assign(&detail, "Requires a reviewed update")
	handle := ksawery.Contributor_Handle{contributor = 1, generation = 5}
	target, second_target: ksawery.Extension_Annotation_Target
	_ = ksawery.extension_annotation_target_assign(&target, .Ref, 13, transmute([]u8)(string("refs/heads/main")))
	_ = ksawery.extension_annotation_target_assign(&second_target, .Ref, 13, transmute([]u8)(string("refs/heads/alpha")))
	annotations^ = [2]ksawery.Extension_Annotation {
		{
			id = 1,
			contribution = 7,
			identity = first_identity,
			target = target,
			label_present = true,
			label = label,
			detail = detail,
			severity = .Warning,
			style = .Alert,
			command = {
				present = true,
				contributor = handle,
				contribution = 11,
				identity = command_identity,
			},
		},
		{
			id = 2,
			contribution = 7,
			identity = second_identity,
			target = second_target,
			severity = .Information,
			style = .Information,
		},
	}
	return {
		contributor = handle,
		contributor_identity = contributor_identity,
		generation = 23,
		observation = {.Refs, repository, 13},
		annotations = annotations^[:],
		truncation = .Complete,
	}
}

/* Verifies annotation content and command references remain bounded and semantic. */
@(test)
extension_annotations_are_bounded_and_semantic :: proc(t: ^testing.T) {
	annotations: [2]ksawery.Extension_Annotation
	generation := annotation_contract_test_generation(&annotations)
	usage, failure := ksawery.extension_annotation_generation_validate(generation)
	testing.expect_value(t, failure.code, ksawery.Extension_Annotation_Failure_Code.None)
	testing.expect_value(t, usage.annotations, u32(2))
	testing.expect(t, usage.label_bytes > 0)
	testing.expect(t, usage.detail_bytes > 0)
	testing.expect_value(t, usage.command_references, u32(1))
	testing.expect(t, usage.copy_bytes <= ksawery.DEFAULT_EXTENSION_ANNOTATION_COPY_BYTES)
	testing.expect(t, !usage.truncated)
	testing.expect(t, ksawery.extension_annotation_limits_are_valid(ksawery.DEFAULT_EXTENSION_ANNOTATION_LIMITS))
	testing.expect(t, ksawery.extension_annotation_limits_are_valid(ksawery.MAX_EXTENSION_ANNOTATION_LIMITS))
}

/* Verifies projections bind to exact observation and target generations. */
@(test)
extension_annotations_reject_stale_observations_and_targets :: proc(t: ^testing.T) {
	annotations: [2]ksawery.Extension_Annotation
	generation := annotation_contract_test_generation(&annotations)
	matched, failure := ksawery.extension_annotation_generation_matches_observation(
		generation,
		generation.observation,
	)
	testing.expect(t, matched)
	testing.expect_value(t, failure.code, ksawery.Extension_Annotation_Failure_Code.None)
	owner_matched, owner_failure := ksawery.extension_annotation_generation_matches_contributor(
		generation,
		generation.contributor,
	)
	testing.expect(t, owner_matched)
	testing.expect_value(t, owner_failure.code, ksawery.Extension_Annotation_Failure_Code.None)
	stale_owner := generation.contributor
	stale_owner.generation += 1
	owner_matched, owner_failure = ksawery.extension_annotation_generation_matches_contributor(generation, stale_owner)
	testing.expect(t, !owner_matched)
	testing.expect_value(t, owner_failure.code, ksawery.Extension_Annotation_Failure_Code.Stale_Contributor)
	stale_observation := generation.observation
	stale_observation.generation += 1
	matched, failure = ksawery.extension_annotation_generation_matches_observation(generation, stale_observation)
	testing.expect(t, !matched)
	testing.expect_value(t, failure.code, ksawery.Extension_Annotation_Failure_Code.Stale_Observation)
	target_matched, target_failure := ksawery.extension_annotation_matches_target(
		annotations[0],
		annotations[0].target,
	)
	testing.expect(t, target_matched)
	stale_target := annotations[0].target
	stale_target.generation += 1
	target_matched, target_failure = ksawery.extension_annotation_matches_target(annotations[0], stale_target)
	testing.expect(t, !target_matched)
	testing.expect_value(t, target_failure.code, ksawery.Extension_Annotation_Failure_Code.Stale_Target)
}

/* Verifies duplicate identities and malformed content reject the complete generation. */
@(test)
extension_annotations_reject_partial_generations :: proc(t: ^testing.T) {
	annotations: [2]ksawery.Extension_Annotation
	generation := annotation_contract_test_generation(&annotations)
	annotations[1].id = annotations[0].id
	generation.annotations = annotations[:]
	_, failure := ksawery.extension_annotation_generation_validate(generation)
	testing.expect_value(t, failure.code, ksawery.Extension_Annotation_Failure_Code.Duplicate_Annotation)
	generation = annotation_contract_test_generation(&annotations)
	annotations[0].command.contributor.generation += 1
	generation.annotations = annotations[:]
	_, failure = ksawery.extension_annotation_generation_validate(generation)
	testing.expect_value(t, failure.code, ksawery.Extension_Annotation_Failure_Code.Invalid_Command)
	generation = annotation_contract_test_generation(&annotations)
	annotations[1].severity = .None
	annotations[1].style = .None
	generation.annotations = annotations[:]
	_, failure = ksawery.extension_annotation_generation_validate(generation)
	testing.expect_value(t, failure.code, ksawery.Extension_Annotation_Failure_Code.Invalid_Annotation)
}

/* Verifies ordering uses stable owner, target, and annotation identities only. */
@(test)
extension_annotations_have_deterministic_order :: proc(t: ^testing.T) {
	annotations: [2]ksawery.Extension_Annotation
	generation := annotation_contract_test_generation(&annotations)
	first_key := ksawery.extension_annotation_order_key(generation.contributor_identity, annotations[0])
	second_key := ksawery.extension_annotation_order_key(generation.contributor_identity, annotations[1])
	testing.expect(t, ksawery.extension_annotation_order_key_is_less(second_key, first_key))
	annotations[1].target = annotations[0].target
	_ = ksawery.extension_identity_assign(&annotations[1].identity, "annotation.alpha")
	second_key = ksawery.extension_annotation_order_key(generation.contributor_identity, annotations[1])
	testing.expect(t, ksawery.extension_annotation_order_key_is_less(second_key, first_key))
	alpha_contributor := generation.contributor_identity
	_ = ksawery.contributor_identity_assign(&alpha_contributor, "personal.alpha")
	alpha_key := ksawery.extension_annotation_order_key(alpha_contributor, annotations[0])
	testing.expect(t, ksawery.extension_annotation_order_key_is_less(alpha_key, first_key))
}

/* Verifies the annotation count and copied-byte policies reject oversized generations. */
@(test)
extension_annotations_enforce_generation_limits :: proc(t: ^testing.T) {
	annotations: [2]ksawery.Extension_Annotation
	generation := annotation_contract_test_generation(&annotations)
	over_limit: [65]ksawery.Extension_Annotation
	generation.annotations = over_limit[:]
	_, failure := ksawery.extension_annotation_generation_validate(generation)
	testing.expect_value(t, failure.code, ksawery.Extension_Annotation_Failure_Code.Annotation_Limit)
	testing.expect_value(t, failure.limit, u64(ksawery.DEFAULT_EXTENSION_ANNOTATIONS_PER_CONTRIBUTOR))

	generation = annotation_contract_test_generation(&annotations)
	limits := ksawery.Extension_Annotation_Limits {
		annotations_per_contributor = 2,
		copy_bytes = 1,
	}
	_, failure = ksawery.extension_annotation_generation_validate(generation, limits)
	testing.expect_value(t, failure.code, ksawery.Extension_Annotation_Failure_Code.Copy_Limit)
}

/* Verifies truncation is explicit and invalidation drops borrowed projection references. */
@(test)
extension_annotation_invalidation_clears_generation_state :: proc(t: ^testing.T) {
	annotations: [2]ksawery.Extension_Annotation
	generation := annotation_contract_test_generation(&annotations)
	generation.truncation = .Provider_Limit
	usage, failure := ksawery.extension_annotation_generation_validate(generation)
	testing.expect_value(t, failure.code, ksawery.Extension_Annotation_Failure_Code.None)
	testing.expect(t, usage.truncated)
	ksawery.extension_annotation_generation_invalidate(&generation)
	testing.expect_value(t, generation.generation, ksawery.Extension_Annotation_Generation_ID(0))
	testing.expect_value(t, len(generation.annotations), 0)
}
