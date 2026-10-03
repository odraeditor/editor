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

/* Builds one exact copied Status proposal for the focused native publication owner. */
extension_status_proposal_batch :: proc(section_generation: u64) -> [dynamic]u8 {
	repository :: "/tmp/odra-ksawery-extension"
	contributor :: "personal.repository-tools"
	section_identity :: "status.ahead-behind"
	section_label :: "Repository insight"
	item_identity :: "branch.ahead"
	item_text :: "Ahead 3"
	command_identity :: "command.open-history"
	metadata_key :: "revision.count"
	metadata_value :: "3"
	record_bytes :: 104 + 96 + 128 + 40
	text := repository + contributor + section_identity + section_label +
		item_identity + item_text + command_identity + metadata_key + metadata_value
	total := record_bytes + len(text)
	cursor := record_bytes
	repository_offset := cursor
	cursor += len(repository)
	contributor_offset := cursor
	cursor += len(contributor)
	section_identity_offset := cursor
	cursor += len(section_identity)
	section_label_offset := cursor
	cursor += len(section_label)
	item_identity_offset := cursor
	cursor += len(item_identity)
	item_text_offset := cursor
	cursor += len(item_text)
	command_identity_offset := cursor
	cursor += len(command_identity)
	metadata_key_offset := cursor
	cursor += len(metadata_key)
	metadata_value_offset := cursor
	words := [?]u64 {
		1, u64(total), 1, 1, 1, 1, 5, section_generation, 19,
		u64(repository_offset), u64(len(repository)),
		u64(contributor_offset), u64(len(contributor)),
		7, 0,
		u64(section_identity_offset), u64(len(section_identity)),
		u64(section_label_offset), u64(len(section_label)),
		0, 1, 1, 1, 0, 0,
		1, 0,
		u64(item_identity_offset), u64(len(item_identity)),
		u64(item_text_offset), u64(len(item_text)),
		0, 0, 6, u64(command_identity_offset), u64(len(command_identity)),
		0, 1, 0, 0, 0,
		0, u64(metadata_key_offset), u64(len(metadata_key)),
		u64(metadata_value_offset), u64(len(metadata_value)),
	}
	result, allocation_error := make([dynamic]u8, total)
	assert(allocation_error == nil)
	for value, index in words do assert(endian.put_u64(result[index * 8:], .Little, value))
	copy(result[record_bytes:], transmute([]u8)text)
	return result
}

/* Builds one contributor declaration with admitted Status and command identities. */
extension_status_provider_batch :: proc() -> [dynamic]u8 {
	identity :: "personal.repository-tools"
	label :: "Repository tools"
	provenance :: "/tmp/config/odra/init.rkt"
	status_identity :: "status.ahead-behind"
	command_identity :: "command.open-history"
	text := identity + label + provenance + status_identity + command_identity
	record_bytes := 96 + 128 + 2 * 64 + 112 + len(text)
	status_offset := len(identity) + len(label) + len(provenance)
	command_offset := status_offset + len(status_identity)
	words := [?]u64 {
		1, u64(record_bytes), 1, 2, 1, 2, u64(len(text)), 0, 1, 0, 0, 0,
		1, 5, 2, 1,
		0, u64(len(identity)), u64(len(identity)), u64(len(label)),
		u64(len(identity) + len(label)), u64(len(provenance)),
		7, 0, 2, 0, 0, 0,
		7, 3, 0, 1, 3, u64(status_offset), u64(len(status_identity)), 0,
		9, 1, 0, 1, 5, u64(command_offset), u64(len(command_identity)), 0,
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

/* Opens the exact active contributor used by focused Status publication tests. */
extension_status_provider_registry :: proc(
	registry: ^odra.Ksawery_Extension_Provider_Registry,
	allocator: runtime.Allocator = context.allocator,
) -> bool {
	if !odra.ksawery_extension_provider_registry_init(registry, allocator) do return false
	batch := extension_status_provider_batch()
	defer delete(batch)
	candidate, prepared, _ := odra.ksawery_extension_provider_prepare(registry, batch[:], 2)
	if !prepared do return false
	defer if candidate.data != nil do odra.ksawery_extension_provider_candidate_close(&candidate)
	if !odra.ksawery_extension_provider_candidate_confirm(&candidate) do return false
	activated, _ := odra.ksawery_extension_provider_activate(registry, &candidate)
	return activated
}

/* Verifies valid generations replace atomically and malformed publication is omitted. */
@(test)
extension_status_publication_replaces_and_fails_closed :: proc(t: ^testing.T) {
	registry: odra.Ksawery_Extension_Provider_Registry
	opened := extension_status_provider_registry(&registry)
	testing.expect(t, opened)
	if !opened do return
	defer odra.ksawery_extension_provider_registry_close(&registry)
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, "/tmp/odra-ksawery-extension"))
	descriptor := ksawery.Observation_Descriptor {
		repository = repository,
		generation = 19,
	}
	first := extension_status_proposal_batch(11)
	defer delete(first)
	testing.expect(t, odra.ksawery_extension_status_publish(&registry, first[:], descriptor))
	published := odra.ksawery_extension_status_generation(&registry)
	testing.expect(t, published != nil)
	if published == nil do return
	testing.expect_value(t, published.generation, ksawery.Extension_Status_Section_Generation(11))
	testing.expect(t, published.sections[0].items[0].command.present)
	command_identity := &published.sections[0].items[0].command.identity
	testing.expect_value(t,
		string(command_identity.bytes[:command_identity.length]), "command.open-history")
	inspection, inspected := odra.ksawery_extension_provider_inspect(&registry)
	testing.expect(t, inspected)
	first_retained := inspection.usage.retained_native_bytes

	replacement := extension_status_proposal_batch(12)
	defer delete(replacement)
	testing.expect(t, odra.ksawery_extension_status_publish(&registry, replacement[:], descriptor))
	published = odra.ksawery_extension_status_generation(&registry)
	testing.expect(t, published != nil)
	if published == nil do return
	testing.expect_value(t, published.generation, ksawery.Extension_Status_Section_Generation(12))
	inspection, inspected = odra.ksawery_extension_provider_inspect(&registry)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.usage.retained_native_bytes, first_retained)

	malformed := extension_status_proposal_batch(13)
	defer delete(malformed)
	metadata_offset :: 104 + 96 + 128
	assert(endian.put_u64(malformed[metadata_offset:], .Little, 2))
	testing.expect(t, !odra.ksawery_extension_status_publish(&registry, malformed[:], descriptor))
	testing.expect(t, odra.ksawery_extension_status_generation(&registry) == nil)
	inspection, inspected = odra.ksawery_extension_provider_inspect(&registry)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.latest_failure.code, ksawery.Extension_Failure_Code.Invalid_Declaration)
	testing.expect(t, inspection.usage.retained_native_bytes < first_retained)

	malformed_style := extension_status_proposal_batch(14)
	defer delete(malformed_style)
	item_style_offset :: 104 + 96 + 64
	assert(endian.put_u64(malformed_style[item_style_offset:], .Little, 99))
	testing.expect(t, !odra.ksawery_extension_status_publish(&registry, malformed_style[:], descriptor))
	testing.expect(t, odra.ksawery_extension_status_generation(&registry) == nil)
}

/* Verifies empty publication and contributor disablement hide extension Status state. */
@(test)
extension_status_publication_omits_empty_and_disabled_state :: proc(t: ^testing.T) {
	registry: odra.Ksawery_Extension_Provider_Registry
	opened := extension_status_provider_registry(&registry)
	testing.expect(t, opened)
	if !opened do return
	defer odra.ksawery_extension_provider_registry_close(&registry)
	repository: ksawery.Repository_Context
	_ = ksawery.repository_context_assign(&repository, "/tmp/odra-ksawery-extension")
	descriptor := ksawery.Observation_Descriptor {repository = repository, generation = 19}
	proposal := extension_status_proposal_batch(11)
	defer delete(proposal)
	testing.expect(t, odra.ksawery_extension_status_publish(&registry, proposal[:], descriptor))
	testing.expect(t, odra.ksawery_extension_status_publish(&registry, nil, descriptor))
	testing.expect(t, odra.ksawery_extension_status_generation(&registry) == nil)
	testing.expect(t, odra.ksawery_extension_status_publish(&registry, proposal[:], descriptor))
	inspection, inspected := odra.ksawery_extension_provider_inspect(&registry)
	testing.expect(t, inspected)
	if !inspected do return
	disabled, _ := odra.ksawery_extension_provider_disable(&registry, inspection.handle)
	testing.expect(t, disabled)
	testing.expect(t, odra.ksawery_extension_status_generation(&registry) == nil)
	disabled_inspection, disabled_inspected := odra.ksawery_extension_provider_inspect(&registry)
	testing.expect(t, disabled_inspected)
	testing.expect(t, disabled_inspection.usage.retained_native_bytes <
		inspection.usage.retained_native_bytes)
}

/* Verifies contributor and published Status ownership retain zero bytes at teardown. */
@(test)
extension_status_publication_cleanup_releases_all_native_state :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	registry: odra.Ksawery_Extension_Provider_Registry
	opened := extension_status_provider_registry(&registry, allocator)
	testing.expect(t, opened)
	if !opened {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	repository: ksawery.Repository_Context
	_ = ksawery.repository_context_assign(&repository, "/tmp/odra-ksawery-extension")
	descriptor := ksawery.Observation_Descriptor{repository = repository, generation = 19}
	proposal := extension_status_proposal_batch(11)
	testing.expect(t, odra.ksawery_extension_status_publish(&registry, proposal[:], descriptor))
	testing.expect(t, odra.ksawery_extension_provider_registry_close(&registry))
	delete(proposal)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}
