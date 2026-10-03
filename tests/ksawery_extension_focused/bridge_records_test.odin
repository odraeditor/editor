// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_extension_focused

import bridge "../../src/ksawery_bridge"
import ksawery "../../src/ksawery"
import "core:testing"

/* Copies the default native policy into its pointer-free bridge representation. */
extension_bridge_limits :: proc() -> bridge.Ksawery_Extension_Limits_Record {
	limits := ksawery.DEFAULT_EXTENSION_RESOURCE_LIMITS
	return {
		contributors = u64(limits.contributors),
		contributions_per_contributor = u64(limits.contributions_per_contributor),
		total_contributions = u64(limits.total_contributions),
		declaration_bytes = limits.declaration_bytes,
		observation_bytes = limits.observation_bytes,
		result_bytes = limits.result_bytes,
		provider_value_bytes = limits.provider_value_bytes,
		diagnostic_bytes = limits.diagnostic_bytes,
		turn_deadline_ns = u64(limits.turn_deadline_ns),
		custodian_memory_bytes = limits.custodian_memory_bytes,
		callbacks_per_turn = u64(limits.callbacks_per_turn),
		nesting_depth = u64(limits.nesting_depth),
		retained_native_bytes = limits.retained_native_bytes,
		temporary_native_bytes = limits.temporary_native_bytes,
	}
}

/* Verifies complete contributor records are fixed, bounded, and generation-checked. */
@(test)
extension_bridge_records_are_bounded_and_versioned :: proc(t: ^testing.T) {
	identity :: "personal.repository-tools"
	label :: "Repository tools"
	provenance :: "/tmp/config/ksawery.rkt"
	contribution_identity :: "status.ahead-behind"
	text_value :: identity + label + provenance + contribution_identity
	text := transmute([]u8)(string(text_value))
	contributor := bridge.Ksawery_Extension_Contributor_Record {
		contributor_id = 7,
		contributor_generation = 11,
		origin = u64(ksawery.Contributor_Origin.Personal),
		lifecycle = u64(ksawery.Contributor_Lifecycle.Active),
		identity_bytes = u64(len(identity)),
		label_offset = u64(len(identity)),
		label_bytes = u64(len(label)),
		provenance_offset = u64(len(identity) + len(label)),
		provenance_bytes = u64(len(provenance)),
		authorities = 0x03,
		contribution_count = 1,
	}
	contribution := bridge.Ksawery_Extension_Contribution_Record {
		contribution_id = 13,
		kind = u64(ksawery.Contribution_Kind.Status_Section),
		required_observations = 0x01,
		requested_authorities = 0x03,
		identity_offset = u64(len(identity) + len(label) + len(provenance)),
		identity_bytes = u64(len(contribution_identity)),
	}
	contributors := [?]bridge.Ksawery_Extension_Contributor_Record {contributor}
	contributions := [?]bridge.Ksawery_Extension_Contribution_Record {contribution}
	limits := [?]bridge.Ksawery_Extension_Limits_Record {extension_bridge_limits()}
	header := bridge.Ksawery_Extension_Header_Record {
		schema_version = bridge.KSAWERY_EXTENSION_SCHEMA_VERSION,
		api_version = u64(ksawery.EXTENSION_API_VERSION),
		registry_generation = 17,
		contributor_count = 1,
		contribution_count = 1,
		text_bytes = u64(len(text)),
		limits_count = 1,
	}
	header.record_bytes, _ = bridge.ksawery_extension_record_bytes(1, 1, u64(len(text)))
	testing.expect(t, bridge.ksawery_extension_record_layout_is_valid())
	failure := bridge.ksawery_extension_records_validate(
		header, contributors[:], contributions[:], limits[:], text, 17)
	testing.expect_value(t, failure.code, bridge.Ksawery_Extension_Record_Failure_Code.None)
	stale := header
	stale.registry_generation += 1
	failure = bridge.ksawery_extension_records_validate(
		stale, contributors[:], contributions[:], limits[:], text, 17)
	testing.expect_value(t, failure.code, bridge.Ksawery_Extension_Record_Failure_Code.Stale_Generation)
}

/* Verifies copied scopes reject stale shape, excess flags, and missing targets. */
@(test)
extension_bridge_scopes_fail_closed :: proc(t: ^testing.T) {
	repository_value := "/tmp/odra-ksawery-extension-bridge"
	repository := transmute([]u8)repository_value
	scope := bridge.Ksawery_Extension_Scope_Record {
		schema_version = bridge.KSAWERY_EXTENSION_SCHEMA_VERSION,
		turn_id = 1,
		contributor_id = 2,
		contributor_generation = 3,
		repository_bytes = u64(len(repository)),
		repository_generation = 4,
		worktree_generation = 5,
		observation_generation = 6,
		surface = u64(ksawery.Extension_Surface.Status),
		surface_generation = 7,
		selection_generation = 8,
		target_kind = u64(ksawery.Extension_Target_Kind.Path),
		target_generation = 6,
		target_identity = 9,
		capability_generation = 10,
		owner_thread = 11,
		deadline_ns = u64(ksawery.DEFAULT_EXTENSION_TURN_DEADLINE_NS),
		callback_budget = u64(ksawery.DEFAULT_EXTENSION_CALLBACKS_PER_TURN),
	}
	testing.expect(t, bridge.ksawery_extension_scope_record_is_valid(scope, repository))
	invalid := scope
	invalid.target_identity = 0
	testing.expect(t, !bridge.ksawery_extension_scope_record_is_valid(invalid, repository))
	invalid = scope
	invalid.flags = 0x10
	testing.expect(t, !bridge.ksawery_extension_scope_record_is_valid(invalid, repository))
}
