// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_extension_focused

import ksawery "../../src/ksawery"
import "core:testing"

/* Builds one complete valid contributor declaration for contract tests. */
extension_contracts_declaration :: proc() -> (
	ksawery.Contributor_Declaration,
	[2]ksawery.Contribution_Declaration,
) {
	identity: ksawery.Contributor_Identity
	_ = ksawery.contributor_identity_assign(&identity, "personal.repository-tools")
	label: ksawery.Extension_Label
	_ = ksawery.extension_label_assign(&label, "Repository tools")
	provenance: ksawery.Contributor_Provenance
	_ = ksawery.contributor_provenance_assign(&provenance, .Personal, "/tmp/config/ksawery.rkt")
	status_identity, command_identity: ksawery.Extension_Identity
	_ = ksawery.extension_identity_assign(&status_identity, "status.ahead-behind")
	_ = ksawery.extension_identity_assign(&command_identity, "command.sync")
	contributions := [2]ksawery.Contribution_Declaration {
		{
			id = 1,
			identity = status_identity,
			kind = .Status_Section,
			required_observations = {.Status},
			requested_authority = {.Inspect, .Present},
		},
		{
			id = 2,
			identity = command_identity,
			kind = .Command,
			required_observations = {.Status, .Refs},
			requested_authority = {.Inspect, .Invoke_Declared_Command},
		},
	}
	declaration := ksawery.Contributor_Declaration {
		identity = identity,
		display_name = label,
		provenance = provenance,
		generation = 1,
		api_version = ksawery.EXTENSION_API_VERSION,
		limits = ksawery.DEFAULT_EXTENSION_RESOURCE_LIMITS,
		contributions = contributions[:],
	}
	return declaration, contributions
}

/* Verifies zero values fail closed while the measured resource policies remain valid. */
@(test)
extension_contract_zero_values_fail_closed :: proc(t: ^testing.T) {
	testing.expect(t, !ksawery.contributor_handle_is_valid({}))
	testing.expect(t, !ksawery.contribution_declaration_is_valid({}))
	testing.expect(t, !ksawery.contributor_declaration_is_valid({}))
	testing.expect(t, !ksawery.extension_turn_scope_is_valid({}, ksawery.DEFAULT_EXTENSION_RESOURCE_LIMITS))
	testing.expect(t, ksawery.extension_resource_limits_are_valid(ksawery.DEFAULT_EXTENSION_RESOURCE_LIMITS))
	testing.expect(t, ksawery.extension_resource_limits_are_valid(ksawery.MAX_EXTENSION_RESOURCE_LIMITS))
}

/* Verifies copied contributor metadata is bounded, UTF-8, and stable by value. */
@(test)
extension_contract_metadata_is_copied_and_bounded :: proc(t: ^testing.T) {
	identity: ksawery.Contributor_Identity
	testing.expect(t, ksawery.contributor_identity_assign(&identity, "personal.repository-tools"))
	testing.expect(t, !ksawery.contributor_identity_assign(&identity, "Personal Tools"))
	label: ksawery.Extension_Label
	testing.expect(t, ksawery.extension_label_assign(&label, "Narzędzia repozytorium"))
	provenance: ksawery.Contributor_Provenance
	testing.expect(t, ksawery.contributor_provenance_assign(&provenance, .Personal, "/tmp/config/ksawery.rkt"))
	testing.expect(t, !ksawery.contributor_provenance_assign(&provenance, .Invalid, "unknown"))
}

/* Verifies declarations are complete and reject duplicate owner-local identities. */
@(test)
extension_contract_declarations_are_atomic :: proc(t: ^testing.T) {
	declaration, contributions := extension_contracts_declaration()
	testing.expect(t, ksawery.contributor_declaration_is_valid(declaration))
	contributions[1].id = contributions[0].id
	declaration.contributions = contributions[:]
	testing.expect(t, !ksawery.contributor_declaration_is_valid(declaration))
	declaration, contributions = extension_contracts_declaration()
	contributions[1].identity = contributions[0].identity
	declaration.contributions = contributions[:]
	testing.expect(t, !ksawery.contributor_declaration_is_valid(declaration))
}

/* Verifies lifecycle transitions cannot activate or revive incomplete generations. */
@(test)
extension_contract_lifecycle_is_closed :: proc(t: ^testing.T) {
	testing.expect(t, ksawery.contributor_lifecycle_transition_is_valid(.Loaded, .Prepared))
	testing.expect(t, ksawery.contributor_lifecycle_transition_is_valid(.Prepared, .Confirmed))
	testing.expect(t, ksawery.contributor_lifecycle_transition_is_valid(.Confirmed, .Active))
	testing.expect(t, ksawery.contributor_lifecycle_transition_is_valid(.Active, .Replaced))
	testing.expect(t, ksawery.contributor_lifecycle_transition_is_valid(.Replaced, .Closed))
	testing.expect(t, !ksawery.contributor_lifecycle_transition_is_valid(.Loaded, .Active))
	testing.expect(t, !ksawery.contributor_lifecycle_transition_is_valid(.Rejected, .Active))
	testing.expect(t, !ksawery.contributor_lifecycle_transition_is_valid(.Closed, .Loaded))
}

/* Verifies capabilities expire across turn, generation, authority, and thread changes. */
@(test)
extension_contract_capabilities_are_scoped :: proc(t: ^testing.T) {
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, "/tmp/odra-ksawery-extension-contracts"))
	handle := ksawery.Contributor_Handle {contributor = 7, generation = 11}
	scope := ksawery.Extension_Turn_Scope {
		turn = 13,
		contributor = handle,
		repository = repository,
		repository_generation = 17,
		worktree_generation = 19,
		observation_generation = 23,
		surface = .Status,
		surface_generation = 29,
		selection_generation = 31,
		target = {kind = .Path, generation = 23, identity = 37},
		capability_generation = 41,
		owner_thread = 43,
		deadline_ns = ksawery.DEFAULT_EXTENSION_TURN_DEADLINE_NS,
		callback_budget = ksawery.DEFAULT_EXTENSION_CALLBACKS_PER_TURN,
		mutation_available = true,
	}
	capability := ksawery.Extension_Capability {
		turn = scope.turn,
		contributor = handle,
		generation = scope.capability_generation,
		owner_thread = scope.owner_thread,
		authorities = {.Inspect, .Request_Core_Action},
	}
	testing.expect(t, ksawery.extension_turn_scope_is_valid(scope, ksawery.DEFAULT_EXTENSION_RESOURCE_LIMITS))
	testing.expect(t, ksawery.extension_turn_scope_matches(scope, scope))
	testing.expect(t, ksawery.extension_capability_is_current(capability, scope, 43, .Inspect))
	testing.expect(t, !ksawery.extension_capability_is_current(capability, scope, 47, .Inspect))
	testing.expect(t, !ksawery.extension_capability_is_current(capability, scope, 43, .Present))
	stale := scope
	stale.capability_generation += 1
	testing.expect(t, !ksawery.extension_turn_scope_matches(scope, stale))
	testing.expect(t, !ksawery.extension_capability_is_current(capability, stale, 43, .Inspect))
	stale = scope
	stale.observation_generation += 1
	testing.expect(t, !ksawery.extension_turn_scope_matches(scope, stale))
}

/* Verifies usage admission accounts for every retained and temporary byte family. */
@(test)
extension_contract_usage_respects_selected_limits :: proc(t: ^testing.T) {
	limits := ksawery.DEFAULT_EXTENSION_RESOURCE_LIMITS
	usage := ksawery.Extension_Usage {
		contributions = u32(limits.contributions_per_contributor),
		declaration_bytes = limits.declaration_bytes,
		observation_bytes = limits.observation_bytes,
		result_bytes = limits.result_bytes,
		provider_value_bytes = limits.provider_value_bytes,
		diagnostic_bytes = limits.diagnostic_bytes,
		retained_native_bytes = limits.retained_native_bytes,
		temporary_native_bytes = limits.temporary_native_bytes,
	}
	testing.expect(t, ksawery.extension_usage_within_limits(usage, limits))
	usage.result_bytes += 1
	testing.expect(t, !ksawery.extension_usage_within_limits(usage, limits))
}
