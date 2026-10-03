// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_extension_focused

import ksawery "../../src/ksawery"
import odra "../../src/ksawery_module"
import "base:runtime"
import "core:encoding/endian"
import "core:mem"
import "core:testing"

ANNOTATION_TEST_REPOSITORY :: "/tmp/odra-ksawery-extension"
ANNOTATION_TEST_CONTRIBUTOR :: "personal.repository-tools"
ANNOTATION_TEST_TARGET :: "refs/heads/main"
ANNOTATION_TEST_IDENTITY :: "annotation.protected"
ANNOTATION_TEST_LABEL :: "Protected"
ANNOTATION_TEST_DETAIL :: "Requires review"
ANNOTATION_TEST_COMMAND :: "command.open-history"

/* Builds one contributor with an annotation and its admitted command. */
annotation_provider_batch :: proc() -> [dynamic]u8 {
	label :: "Repository tools"
	provenance :: "/tmp/config/odra/init.rkt"
	annotation_identity :: "annotations.repository-policy"
	command_identity :: ANNOTATION_TEST_COMMAND
	text := ANNOTATION_TEST_CONTRIBUTOR + label + provenance + annotation_identity + command_identity
	record_bytes := 96 + 128 + 2 * 64 + 112 + len(text)
	annotation_offset := len(ANNOTATION_TEST_CONTRIBUTOR) + len(label) + len(provenance)
	command_offset := annotation_offset + len(annotation_identity)
	words := [?]u64 {
		1, u64(record_bytes), 1, 2, 1, 2, u64(len(text)), 0, 1, 0, 0, 0,
		1, 5, 2, 1,
		0, u64(len(ANNOTATION_TEST_CONTRIBUTOR)),
		u64(len(ANNOTATION_TEST_CONTRIBUTOR)), u64(len(label)),
		u64(len(ANNOTATION_TEST_CONTRIBUTOR) + len(label)), u64(len(provenance)),
		7, 0, 2, 0, 0, 0,
		7, 4, 0, 0x3f, 3, u64(annotation_offset), u64(len(annotation_identity)), 0,
		9, 1, 0, 0x3f, 5, u64(command_offset), u64(len(command_identity)), 0,
		8, 16, 128, 1 * 1_024 * 1_024, 1 * 1_024 * 1_024,
		1 * 1_024 * 1_024, 256 * 1_024, 4 * 1_024, 250_000_000,
		32 * 1_024 * 1_024, 64, 1, 32 * 1_024 * 1_024, 32 * 1_024 * 1_024,
	}
	result, allocation_error := make([dynamic]u8, record_bytes)
	assert(allocation_error == nil)
	for value, index in words do assert(endian.put_u64(result[index * 8:], .Little, value))
	copy(result[len(words) * 8:], transmute([]u8)text)
	return result
}

/* Opens the exact annotation contributor used by native publication tests. */
annotation_provider_registry :: proc(
	registry: ^odra.Ksawery_Extension_Provider_Registry,
	allocator: runtime.Allocator = context.allocator,
) -> bool {
	if !odra.ksawery_extension_provider_registry_init(registry, allocator) do return false
	batch := annotation_provider_batch()
	defer delete(batch)
	candidate, prepared, _ := odra.ksawery_extension_provider_prepare(registry, batch[:], 2)
	if !prepared do return false
	defer if candidate.data != nil do odra.ksawery_extension_provider_candidate_close(&candidate)
	if !odra.ksawery_extension_provider_candidate_confirm(&candidate) do return false
	activated, _ := odra.ksawery_extension_provider_activate(registry, &candidate)
	return activated
}

annotation_publication_observation :: proc(generation: u64 = 13) -> ksawery.Extension_Annotation_Observation {
	repository: ksawery.Repository_Context
	assert(ksawery.repository_context_assign(&repository, ANNOTATION_TEST_REPOSITORY))
	return {.Refs, repository, generation}
}

annotation_publication_target :: proc(
	identity: string = ANNOTATION_TEST_TARGET,
	generation: u64 = 13,
) -> ksawery.Extension_Annotation_Target {
	target: ksawery.Extension_Annotation_Target
	assert(ksawery.extension_annotation_target_assign(
		&target, .Ref, generation, transmute([]u8)identity,
	))
	return target
}

/* Builds one exact copied annotation proposal for native decoding. */
annotation_proposal_batch :: proc(generation: u64 = 11) -> [dynamic]u8 {
	record_bytes := 120 + 152
	text := ANNOTATION_TEST_REPOSITORY + ANNOTATION_TEST_CONTRIBUTOR + ANNOTATION_TEST_TARGET +
		ANNOTATION_TEST_IDENTITY + ANNOTATION_TEST_LABEL + ANNOTATION_TEST_DETAIL + ANNOTATION_TEST_COMMAND
	total := record_bytes + len(text)
	cursor := record_bytes
	repository_offset := cursor
	cursor += len(ANNOTATION_TEST_REPOSITORY)
	contributor_offset := cursor
	cursor += len(ANNOTATION_TEST_CONTRIBUTOR)
	target_offset := cursor
	cursor += len(ANNOTATION_TEST_TARGET)
	identity_offset := cursor
	cursor += len(ANNOTATION_TEST_IDENTITY)
	label_offset := cursor
	cursor += len(ANNOTATION_TEST_LABEL)
	detail_offset := cursor
	cursor += len(ANNOTATION_TEST_DETAIL)
	command_offset := cursor
	words := [?]u64 {
		1, u64(total), 1, 5, generation, 2, 13, 1,
		u64(repository_offset), u64(len(ANNOTATION_TEST_REPOSITORY)),
		u64(contributor_offset), u64(len(ANNOTATION_TEST_CONTRIBUTOR)), 0, 0, 0,
		1, 7, 5, 13,
		u64(target_offset), u64(len(ANNOTATION_TEST_TARGET)),
		u64(identity_offset), u64(len(ANNOTATION_TEST_IDENTITY)),
		u64(label_offset), u64(len(ANNOTATION_TEST_LABEL)),
		u64(detail_offset), u64(len(ANNOTATION_TEST_DETAIL)),
		3, 7, u64(command_offset), u64(len(ANNOTATION_TEST_COMMAND)), 3, 0, 0,
	}
	result, allocation_error := make([dynamic]u8, total)
	assert(allocation_error == nil)
	for value, index in words do assert(endian.put_u64(result[index * 8:], .Little, value))
	copy(result[record_bytes:], transmute([]u8)text)
	return result
}

/* Verifies atomic replacement, target admission, commands, and failed-closed omission. */
@(test)
extension_annotation_publication_is_atomic_and_target_bound :: proc(t: ^testing.T) {
	registry: odra.Ksawery_Extension_Provider_Registry
	opened := annotation_provider_registry(&registry)
	testing.expect(t, opened)
	if !opened do return
	defer odra.ksawery_extension_provider_registry_close(&registry)
	observation := annotation_publication_observation()
	targets := [1]ksawery.Extension_Annotation_Target{annotation_publication_target()}
	proposal := annotation_proposal_batch()
	defer delete(proposal)
	testing.expect(t, odra.ksawery_extension_annotation_publish(
		&registry, proposal[:], observation, targets[:],
	))
	published := odra.ksawery_extension_annotation_generation(&registry, .Refs)
	testing.expect(t, published != nil)
	if published == nil do return
	testing.expect_value(t, published.generation, ksawery.Extension_Annotation_Generation_ID(11))
	testing.expect_value(t, len(published.annotations), 1)
	testing.expect_value(t, published.annotations[0].target, targets[0])
	testing.expect_value(t, published.annotations[0].severity, ksawery.Extension_Annotation_Severity.Warning)
	testing.expect(t, published.annotations[0].command.present)
	command := &published.annotations[0].command.identity
	testing.expect_value(t, string(command.bytes[:command.length]), ANNOTATION_TEST_COMMAND)
	inspection, inspected := odra.ksawery_extension_provider_inspect(&registry)
	testing.expect(t, inspected)
	retained := inspection.usage.retained_native_bytes

	replacement := annotation_proposal_batch(12)
	defer delete(replacement)
	testing.expect(t, odra.ksawery_extension_annotation_publish(
		&registry, replacement[:], observation, targets[:],
	))
	published = odra.ksawery_extension_annotation_generation(&registry, .Refs)
	testing.expect(t, published != nil)
	if published == nil do return
	testing.expect_value(t, published.generation, ksawery.Extension_Annotation_Generation_ID(12))
	inspection, inspected = odra.ksawery_extension_provider_inspect(&registry)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.usage.retained_native_bytes, retained)

	removed := [1]ksawery.Extension_Annotation_Target {
		annotation_publication_target("refs/heads/removed"),
	}
	testing.expect(t, !odra.ksawery_extension_annotation_publish(
		&registry, proposal[:], observation, removed[:],
	))
	testing.expect(t, odra.ksawery_extension_annotation_generation(&registry, .Refs) == nil)

	stale := observation
	stale.generation += 1
	testing.expect(t, !odra.ksawery_extension_annotation_publish(
		&registry, proposal[:], stale, targets[:],
	))
	testing.expect(t, odra.ksawery_extension_annotation_generation(&registry, .Refs) == nil)
}

/* Verifies undeclared commands, empty projections, and disablement cannot retain annotations. */
@(test)
extension_annotation_publication_omits_invalid_and_disabled_state :: proc(t: ^testing.T) {
	registry: odra.Ksawery_Extension_Provider_Registry
	opened := annotation_provider_registry(&registry)
	testing.expect(t, opened)
	if !opened do return
	defer odra.ksawery_extension_provider_registry_close(&registry)
	observation := annotation_publication_observation()
	targets := [1]ksawery.Extension_Annotation_Target{annotation_publication_target()}
	proposal := annotation_proposal_batch()
	defer delete(proposal)
	command_offset := len(proposal) - len(ANNOTATION_TEST_COMMAND)
	copy(proposal[command_offset:], transmute([]u8)(string("command.open-mystery")))
	testing.expect(t, !odra.ksawery_extension_annotation_publish(
		&registry, proposal[:], observation, targets[:],
	))
	testing.expect(t, odra.ksawery_extension_annotation_generation(&registry, .Refs) == nil)

	valid := annotation_proposal_batch()
	defer delete(valid)
	testing.expect(t, odra.ksawery_extension_annotation_publish(
		&registry, valid[:], observation, targets[:],
	))
	testing.expect(t, odra.ksawery_extension_annotation_publish(
		&registry, nil, observation, targets[:],
	))
	testing.expect(t, odra.ksawery_extension_annotation_generation(&registry, .Refs) == nil)
	testing.expect(t, odra.ksawery_extension_annotation_publish(
		&registry, valid[:], observation, targets[:],
	))
	inspection, inspected := odra.ksawery_extension_provider_inspect(&registry)
	testing.expect(t, inspected)
	if !inspected do return
	disabled, _ := odra.ksawery_extension_provider_disable(&registry, inspection.handle)
	testing.expect(t, disabled)
	testing.expect(t, odra.ksawery_extension_annotation_generation(&registry, .Refs) == nil)
}

/* Verifies annotation and contributor ownership release every tracked native byte. */
@(test)
extension_annotation_publication_cleanup_releases_all_native_state :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	registry: odra.Ksawery_Extension_Provider_Registry
	opened := annotation_provider_registry(&registry, allocator)
	testing.expect(t, opened)
	if !opened {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	observation := annotation_publication_observation()
	targets := [1]ksawery.Extension_Annotation_Target{annotation_publication_target()}
	proposal := annotation_proposal_batch()
	testing.expect(t, odra.ksawery_extension_annotation_publish(
		&registry, proposal[:], observation, targets[:],
	))
	testing.expect(t, odra.ksawery_extension_provider_registry_close(&registry))
	delete(proposal)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}
