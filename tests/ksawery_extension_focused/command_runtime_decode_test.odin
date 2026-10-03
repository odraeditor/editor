// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_extension_focused

import bridge "../../src/ksawery_bridge"
import ksawery "../../src/ksawery"
import odra "../../src/ksawery_module"
import "core:encoding/endian"
import "core:mem"
import "core:testing"

/* Verifies one exact Racket family envelope becomes a validated native route. */
@(test)
extension_command_runtime_decodes_exact_active_family :: proc(t: ^testing.T) {
	provider: odra.Ksawery_Extension_Provider_Data
	provider.enabled = true
	provider.inspection.handle = {contributor = 1, generation = 5}
	testing.expect(t, ksawery.contributor_identity_assign(
		&provider.inspection.identity, "personal.repository-tools",
	))
	contributions := [1]bridge.Ksawery_Extension_Contribution_Record {{
		contribution_id = 7,
		kind = u64(ksawery.Contribution_Kind.Command_Family),
		required_observations = 1,
		requested_authorities = u64(1) << u64(ksawery.Extension_Authority.Request_Core_Action),
	}}
	provider.contributions = contributions[:]
	input := extension_command_runtime_test_family()
	data, decoded := odra.ksawery_extension_command_decode(
		&provider, input[:], 1, context.allocator,
	)
	testing.expect(t, decoded)
	if !decoded do return
	defer odra.ksawery_extension_command_data_close(data)
	testing.expect_value(t, data.action, ksawery.Extension_Command_Action_ID(1))
	testing.expect_value(t, data.family.contributor, provider.inspection.handle)
	testing.expect_value(t, data.family.contribution, ksawery.Contribution_ID(7))
	testing.expect_value(t, data.family.family, ksawery.Extension_Command_Family_ID(11))
	testing.expect_value(t, data.family.generation, ksawery.Extension_Command_Family_Generation_ID(17))
	testing.expect_value(t, len(data.family.arguments), 0)
	testing.expect_value(t, len(data.family.actions), 1)
	testing.expect_value(t, data.family.actions[0].core_operation, ksawery.Repository_Operation_Kind.Stage)
}

/* Verifies stale or undeclared runtime families fail closed without retained memory. */
@(test)
extension_command_runtime_rejects_stale_and_undeclared_families :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	provider: odra.Ksawery_Extension_Provider_Data
	provider.enabled = true
	provider.inspection.handle = {contributor = 1, generation = 5}
	testing.expect(t, ksawery.contributor_identity_assign(
		&provider.inspection.identity, "personal.repository-tools",
	))
	contributions := [1]bridge.Ksawery_Extension_Contribution_Record {{
		contribution_id = 7,
		kind = u64(ksawery.Contribution_Kind.Command_Family),
		required_observations = 1,
		requested_authorities = u64(1) << u64(ksawery.Extension_Authority.Request_Core_Action),
	}}
	provider.contributions = contributions[:]
	input := extension_command_runtime_test_family()
	assert(endian.put_u64(input[2 * 8:], .Little, 6))
	data, decoded := odra.ksawery_extension_command_decode(&provider, input[:], 1, allocator)
	testing.expect(t, !decoded && data == nil)
	assert(endian.put_u64(input[2 * 8:], .Little, 5))
	assert(endian.put_u64(input[6 * 8:], .Little, 2))
	data, decoded = odra.ksawery_extension_command_decode(&provider, input[:], 1, allocator)
	testing.expect(t, !decoded && data == nil)
	assert(endian.put_u64(input[6 * 8:], .Little, 1))
	data, decoded = odra.ksawery_extension_command_decode(&provider, input[:len(input) - 1], 1, allocator)
	testing.expect(t, !decoded && data == nil)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

@(private)
extension_command_runtime_test_family :: proc() -> [307]u8 {
	contributor := "personal.repository-tools"
	family_identity := "family.status"
	family_label := "Status tools"
	action_identity := "action.stage"
	action_label := "Stage"
	record_bytes := 144 + 96
	total := record_bytes + len(contributor) + len(family_identity) + len(family_label) +
		len(action_identity) + len(action_label)
	assert(total == 307)
	result: [307]u8
	cursor := record_bytes
	contributor_offset := cursor
	copy(result[cursor:], transmute([]u8)contributor)
	cursor += len(contributor)
	family_identity_offset := cursor
	copy(result[cursor:], transmute([]u8)family_identity)
	cursor += len(family_identity)
	family_label_offset := cursor
	copy(result[cursor:], transmute([]u8)family_label)
	cursor += len(family_label)
	action_identity_offset := cursor
	copy(result[cursor:], transmute([]u8)action_identity)
	cursor += len(action_identity)
	action_label_offset := cursor
	copy(result[cursor:], transmute([]u8)action_label)
	header := [?]u64 {
		1, u64(total), 5, 7, 11, 17, 1, 0, 1, 0, u64(total - record_bytes),
		u64(contributor_offset), u64(len(contributor)),
		u64(family_identity_offset), u64(len(family_identity)),
		u64(family_label_offset), u64(len(family_label)), 0,
	}
	for value, index in header do assert(endian.put_u64(result[index * 8:], .Little, value))
	action := [?]u64 {
		1,
		u64(ksawery.Extension_Authority.Request_Core_Action),
		1,
		u64(1) << u64(ksawery.Extension_Annotation_Target_Family.Path),
		u64(ksawery.Extension_Command_Operation_Requirement.Idle),
		1,
		1,
		u64(action_identity_offset),
		u64(len(action_identity)),
		u64(action_label_offset),
		u64(len(action_label)),
		u64(ksawery.Repository_Operation_Kind.Stage),
	}
	for value, index in action do assert(endian.put_u64(result[144 + index * 8:], .Little, value))
	return result
}
