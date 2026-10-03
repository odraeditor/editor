// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_extension_focused

import ksawery "../../src/ksawery"
import "core:testing"

extension_status_test_section :: proc(
	items: ^[2]ksawery.Extension_Status_Item,
	metadata: ^[2]ksawery.Extension_Status_Metadata,
) -> ksawery.Extension_Status_Section {
	contributor_identity: ksawery.Contributor_Identity
	_ = ksawery.contributor_identity_assign(&contributor_identity, "personal.repository-tools")
	section_identity: ksawery.Extension_Identity
	_ = ksawery.extension_identity_assign(&section_identity, "status.ahead-behind")
	label: ksawery.Extension_Label
	_ = ksawery.extension_label_assign(&label, "Repository insight")
	repository: ksawery.Repository_Context
	_ = ksawery.repository_context_assign(&repository, "/tmp/odra-ksawery-extension-status")
	first_identity, second_identity: ksawery.Extension_Identity
	_ = ksawery.extension_identity_assign(&first_identity, "branch.ahead")
	_ = ksawery.extension_identity_assign(&second_identity, "branch.behind")
	command_identity: ksawery.Extension_Identity
	_ = ksawery.extension_identity_assign(&command_identity, "command.open-history")
	metadata_key, second_metadata_key: ksawery.Extension_Identity
	_ = ksawery.extension_identity_assign(&metadata_key, "revision.count")
	_ = ksawery.extension_identity_assign(&second_metadata_key, "revision.source")
	metadata_value, second_metadata_value: ksawery.Extension_Status_Metadata_Value
	_ = ksawery.extension_status_metadata_value_assign(&metadata_value, "3")
	_ = ksawery.extension_status_metadata_value_assign(&second_metadata_value, "upstream/main")
	metadata^ = [2]ksawery.Extension_Status_Metadata {
		{key = metadata_key, value = metadata_value},
		{key = second_metadata_key, value = second_metadata_value},
	}
	first_text, first_detail, second_text: ksawery.Extension_Status_Text
	_ = ksawery.extension_status_text_assign(&first_text, "Ahead 3")
	_ = ksawery.extension_status_text_assign(&first_detail, "Local commits not on upstream")
	_ = ksawery.extension_status_text_assign(&second_text, "Behind 1")
	handle := ksawery.Contributor_Handle{contributor = 1, generation = 5}
	items^ = [2]ksawery.Extension_Status_Item {
		{
			id = 1,
			identity = first_identity,
			text = first_text,
			detail = first_detail,
			style = .Warning,
			command = {
				present = true,
				contributor = handle,
				contribution = 9,
				identity = command_identity,
			},
			metadata = metadata^[:],
		},
		{id = 2, identity = second_identity, text = second_text, style = .Information},
	}
	return ksawery.Extension_Status_Section {
		contributor = handle,
		contributor_identity = contributor_identity,
		contribution = 7,
		identity = section_identity,
		generation = 11,
		repository = repository,
		observation_generation = 13,
		label = label,
		items = items^[:],
		truncation = .Complete,
	}
}

/* Verifies complete sections carry copied semantics and exact usage. */
@(test)
extension_status_sections_are_bounded_and_semantic :: proc(t: ^testing.T) {
	items: [2]ksawery.Extension_Status_Item
	metadata: [2]ksawery.Extension_Status_Metadata
	section := extension_status_test_section(&items, &metadata)
	usage, failure := ksawery.extension_status_section_validate(section)
	testing.expect_value(t, failure.code, ksawery.Extension_Status_Failure_Code.None)
	testing.expect_value(t, usage.sections, u16(1))
	testing.expect_value(t, usage.items, u32(2))
	testing.expect_value(t, usage.metadata, u32(2))
	testing.expect_value(t, usage.command_references, u32(1))
	testing.expect(t, usage.text_bytes > 0)
	testing.expect(t, usage.copy_bytes <= ksawery.DEFAULT_EXTENSION_STATUS_COPY_BYTES)
	testing.expect(t, !usage.truncated)
	testing.expect(t, ksawery.extension_status_section_is_visible(section))
	testing.expect(t, ksawery.extension_status_limits_are_valid(ksawery.DEFAULT_EXTENSION_STATUS_LIMITS))
	testing.expect(t, ksawery.extension_status_limits_are_valid(ksawery.MAX_EXTENSION_STATUS_LIMITS))
}

/* Verifies exact Status observation identity revokes stale projections. */
@(test)
extension_status_sections_bind_to_one_observation :: proc(t: ^testing.T) {
	items: [2]ksawery.Extension_Status_Item
	metadata: [2]ksawery.Extension_Status_Metadata
	section := extension_status_test_section(&items, &metadata)
	descriptor := ksawery.Observation_Descriptor {
		repository = section.repository,
		generation = section.observation_generation,
	}
	matched, failure := ksawery.extension_status_section_matches_observation(section, descriptor)
	testing.expect(t, matched)
	testing.expect_value(t, failure.code, ksawery.Extension_Status_Failure_Code.None)
	descriptor.generation += 1
	matched, failure = ksawery.extension_status_section_matches_observation(section, descriptor)
	testing.expect(t, !matched)
	testing.expect_value(t, failure.code, ksawery.Extension_Status_Failure_Code.Stale_Observation)
}

/* Verifies ordering ignores provider priority and follows stable identities only. */
@(test)
extension_status_sections_have_deterministic_order :: proc(t: ^testing.T) {
	items: [2]ksawery.Extension_Status_Item
	metadata: [2]ksawery.Extension_Status_Metadata
	first := extension_status_test_section(&items, &metadata)
	second := first
	_ = ksawery.extension_identity_assign(&second.identity, "status.divergence")
	first_key := ksawery.extension_status_order_key(first)
	second_key := ksawery.extension_status_order_key(second)
	testing.expect(t, ksawery.extension_status_order_key_is_less(first_key, second_key))
	_ = ksawery.contributor_identity_assign(&second.contributor_identity, "personal.alpha")
	second_key = ksawery.extension_status_order_key(second)
	testing.expect(t, ksawery.extension_status_order_key_is_less(second_key, first_key))
}

/* Verifies a contributor publishes all of its sections as one observation-bound generation. */
@(test)
extension_status_generations_are_complete_and_atomic :: proc(t: ^testing.T) {
	items: [2]ksawery.Extension_Status_Item
	metadata: [2]ksawery.Extension_Status_Metadata
	first := extension_status_test_section(&items, &metadata)
	second := first
	_ = ksawery.extension_identity_assign(&second.identity, "status.divergence")
	sections := [2]ksawery.Extension_Status_Section{first, second}
	generation := ksawery.Extension_Status_Generation {
		contributor = first.contributor,
		contributor_identity = first.contributor_identity,
		generation = first.generation,
		repository = first.repository,
		observation_generation = first.observation_generation,
		sections = sections[:],
	}
	usage, failure := ksawery.extension_status_generation_validate(generation)
	testing.expect_value(t, failure.code, ksawery.Extension_Status_Failure_Code.None)
	testing.expect_value(t, usage.sections, u16(2))
	testing.expect_value(t, usage.items, u32(4))
	sections[1].identity = sections[0].identity
	generation.sections = sections[:]
	_, failure = ksawery.extension_status_generation_validate(generation)
	testing.expect_value(t, failure.code, ksawery.Extension_Status_Failure_Code.Duplicate_Section)
	sections[1] = second
	sections[1].observation_generation += 1
	generation.sections = sections[:]
	_, failure = ksawery.extension_status_generation_validate(generation)
	testing.expect_value(t, failure.code, ksawery.Extension_Status_Failure_Code.Stale_Observation)
}

/* Verifies malformed, duplicate, and cross-generation commands fail closed. */
@(test)
extension_status_sections_reject_partial_generations :: proc(t: ^testing.T) {
	items: [2]ksawery.Extension_Status_Item
	metadata: [2]ksawery.Extension_Status_Metadata
	section := extension_status_test_section(&items, &metadata)
	items[1].id = items[0].id
	section.items = items[:]
	_, failure := ksawery.extension_status_section_validate(section)
	testing.expect_value(t, failure.code, ksawery.Extension_Status_Failure_Code.Duplicate_Item)
	section = extension_status_test_section(&items, &metadata)
	metadata[1].key = metadata[0].key
	items[0].metadata = metadata[:]
	section.items = items[:]
	_, failure = ksawery.extension_status_section_validate(section)
	testing.expect_value(t, failure.code, ksawery.Extension_Status_Failure_Code.Duplicate_Metadata)
	section = extension_status_test_section(&items, &metadata)
	items[0].command.contributor.generation += 1
	section.items = items[:]
	_, failure = ksawery.extension_status_section_validate(section)
	testing.expect_value(t, failure.code, ksawery.Extension_Status_Failure_Code.Invalid_Command)
	section = extension_status_test_section(&items, &metadata)
	items[0].style = .Invalid
	section.items = items[:]
	_, failure = ksawery.extension_status_section_validate(section)
	testing.expect_value(t, failure.code, ksawery.Extension_Status_Failure_Code.Invalid_Style)
}

/* Verifies empty and explicitly truncated projections remain inspectable but not visible. */
@(test)
extension_status_empty_and_truncated_sections_are_explicit :: proc(t: ^testing.T) {
	items: [2]ksawery.Extension_Status_Item
	metadata: [2]ksawery.Extension_Status_Metadata
	section := extension_status_test_section(&items, &metadata)
	section.items = nil
	section.truncation = .Provider_Limit
	usage, failure := ksawery.extension_status_section_validate(section)
	testing.expect_value(t, failure.code, ksawery.Extension_Status_Failure_Code.None)
	testing.expect(t, usage.truncated)
	testing.expect(t, !ksawery.extension_status_section_is_visible(section))
	section.truncation = .Invalid
	_, failure = ksawery.extension_status_section_validate(section)
	testing.expect_value(t, failure.code, ksawery.Extension_Status_Failure_Code.Invalid_Section)
}
