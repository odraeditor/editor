// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:unicode/utf8"

/* EXTENSION_API_VERSION is the first native Ksawery contribution contract. */
EXTENSION_API_VERSION :: u32(1)
/* DEFAULT_EXTENSION_CONTRIBUTORS is the initial contributor capacity per session. */
DEFAULT_EXTENSION_CONTRIBUTORS :: u16(8)
/* MAX_EXTENSION_CONTRIBUTORS is the immutable contributor ceiling per session. */
MAX_EXTENSION_CONTRIBUTORS :: u16(32)
/* MAX_ACTIVE_EXTENSION_GENERATIONS permits one active generation per contributor. */
MAX_ACTIVE_EXTENSION_GENERATIONS :: u16(MAX_EXTENSION_CONTRIBUTORS)
/* DEFAULT_EXTENSION_CONTRIBUTIONS_PER_CONTRIBUTOR is the initial owner-local capacity. */
DEFAULT_EXTENSION_CONTRIBUTIONS_PER_CONTRIBUTOR :: u16(16)
/* MAX_EXTENSION_CONTRIBUTIONS_PER_CONTRIBUTOR is the immutable owner-local ceiling. */
MAX_EXTENSION_CONTRIBUTIONS_PER_CONTRIBUTOR :: u16(64)
/* DEFAULT_EXTENSION_CONTRIBUTIONS is the initial aggregate contribution capacity. */
DEFAULT_EXTENSION_CONTRIBUTIONS :: u32(128)
/* MAX_EXTENSION_CONTRIBUTIONS is the immutable aggregate contribution ceiling. */
MAX_EXTENSION_CONTRIBUTIONS :: u32(2_048)
/* MAX_EXTENSION_IDENTITY_BYTES bounds one stable machine-readable identity. */
MAX_EXTENSION_IDENTITY_BYTES :: 96
/* MAX_EXTENSION_LABEL_BYTES bounds one copied public display label. */
MAX_EXTENSION_LABEL_BYTES :: 128
/* MAX_EXTENSION_PROVENANCE_BYTES bounds one copied source description. */
MAX_EXTENSION_PROVENANCE_BYTES :: 1 * KIBIBYTE
/* DEFAULT_EXTENSION_DECLARATION_BYTES is the initial complete-candidate budget. */
DEFAULT_EXTENSION_DECLARATION_BYTES :: 1 * MEBIBYTE
/* MAX_EXTENSION_DECLARATION_BYTES is the immutable complete-candidate ceiling. */
MAX_EXTENSION_DECLARATION_BYTES :: 8 * MEBIBYTE
/* DEFAULT_EXTENSION_OBSERVATION_BYTES is the initial copied-observation budget. */
DEFAULT_EXTENSION_OBSERVATION_BYTES :: 1 * MEBIBYTE
/* MAX_EXTENSION_OBSERVATION_BYTES is the immutable copied-observation ceiling. */
MAX_EXTENSION_OBSERVATION_BYTES :: 8 * MEBIBYTE
/* DEFAULT_EXTENSION_RESULT_BYTES is the initial copied-result budget. */
DEFAULT_EXTENSION_RESULT_BYTES :: 1 * MEBIBYTE
/* MAX_EXTENSION_RESULT_BYTES is the immutable copied-result ceiling. */
MAX_EXTENSION_RESULT_BYTES :: 8 * MEBIBYTE
/* DEFAULT_EXTENSION_PROVIDER_VALUE_BYTES is the initial opaque-value budget. */
DEFAULT_EXTENSION_PROVIDER_VALUE_BYTES :: 256 * KIBIBYTE
/* MAX_EXTENSION_PROVIDER_VALUE_BYTES is the immutable opaque-value ceiling. */
MAX_EXTENSION_PROVIDER_VALUE_BYTES :: 4 * MEBIBYTE
/* DEFAULT_EXTENSION_DIAGNOSTIC_BYTES is the initial public diagnostic budget. */
DEFAULT_EXTENSION_DIAGNOSTIC_BYTES :: 4 * KIBIBYTE
/* MAX_EXTENSION_DIAGNOSTIC_BYTES is the immutable public diagnostic ceiling. */
MAX_EXTENSION_DIAGNOSTIC_BYTES :: 64 * KIBIBYTE
/* DEFAULT_EXTENSION_TURN_DEADLINE_NS is the initial synchronous-turn deadline. */
DEFAULT_EXTENSION_TURN_DEADLINE_NS :: i64(250_000_000)
/* MAX_EXTENSION_TURN_DEADLINE_NS is the immutable synchronous-turn deadline. */
MAX_EXTENSION_TURN_DEADLINE_NS :: i64(2_000_000_000)
/* DEFAULT_EXTENSION_CUSTODIAN_MEMORY_BYTES is the initial Racket turn ceiling. */
DEFAULT_EXTENSION_CUSTODIAN_MEMORY_BYTES :: 32 * MEBIBYTE
/* MAX_EXTENSION_CUSTODIAN_MEMORY_BYTES is the immutable Racket turn ceiling. */
MAX_EXTENSION_CUSTODIAN_MEMORY_BYTES :: 128 * MEBIBYTE
/* DEFAULT_EXTENSION_CALLBACKS_PER_TURN is the initial native callback budget. */
DEFAULT_EXTENSION_CALLBACKS_PER_TURN :: u16(64)
/* MAX_EXTENSION_CALLBACKS_PER_TURN is the immutable native callback ceiling. */
MAX_EXTENSION_CALLBACKS_PER_TURN :: u16(256)
/* MAX_EXTENSION_NESTING_DEPTH prohibits reentrant provider turns. */
MAX_EXTENSION_NESTING_DEPTH :: u8(1)
/* MAX_EXTENSION_RETAINED_NATIVE_BYTES is the immutable live native-state ceiling. */
MAX_EXTENSION_RETAINED_NATIVE_BYTES :: 32 * MEBIBYTE
/* MAX_EXTENSION_TEMPORARY_NATIVE_BYTES is the immutable candidate-work ceiling. */
MAX_EXTENSION_TEMPORARY_NATIVE_BYTES :: 32 * MEBIBYTE

/* Contributor_ID identifies one extension owner for a Ksawery session lifetime. */
Contributor_ID :: distinct u64
/* Contributor_Generation identifies one immutable complete contribution candidate. */
Contributor_Generation :: distinct u64
/* Contribution_ID identifies one stable contribution within its contributor. */
Contribution_ID :: distinct u64
/* Extension_Turn_ID identifies one synchronous provider dynamic extent. */
Extension_Turn_ID :: distinct u64
/* Extension_Capability_Generation identifies one revocable scoped capability. */
Extension_Capability_Generation :: distinct u64
/* Repository_Generation identifies one exact admitted repository context state. */
Repository_Generation :: distinct u64
/* Worktree_Generation identifies one exact copied worktree observation state. */
Worktree_Generation :: distinct u64
/* Extension_Surface_Generation identifies one exact native presentation surface. */
Extension_Surface_Generation :: distinct u64
/* Extension_Selection_Generation identifies one exact semantic selection. */
Extension_Selection_Generation :: distinct u64

/* Contributor_Identity owns one stable machine-readable contributor identity. */
Contributor_Identity :: struct {
	bytes:  [MAX_EXTENSION_IDENTITY_BYTES]u8,
	length: u16,
}

/* Extension_Identity owns one stable contributor-local contribution identity. */
Extension_Identity :: struct {
	bytes:  [MAX_EXTENSION_IDENTITY_BYTES]u8,
	length: u16,
}

/* Extension_Label owns one bounded public display label. */
Extension_Label :: struct {
	bytes:  [MAX_EXTENSION_LABEL_BYTES]u8,
	length: u16,
}

/* Contributor_Origin distinguishes built-in, personal, and admitted package owners. */
Contributor_Origin :: enum u8 {
	Invalid,
	Built_In,
	Personal,
	Package,
}

/* Contributor_Provenance owns the bounded source identity shown by inspection. */
Contributor_Provenance :: struct {
	origin: Contributor_Origin,
	bytes:  [MAX_EXTENSION_PROVENANCE_BYTES]u8,
	length: u16,
}

/* Contribution_Kind identifies one declared Ksawery extension point. */
Contribution_Kind :: enum u8 {
	Invalid,
	Command,
	Keymap,
	Status_Section,
	Annotation,
	Command_Family,
	External_Operation,
	Conflict_Assistance,
	Provider_Role,
}

/* Provider_Role identifies one replaceable semantic responsibility. */
Provider_Role :: enum u8 {
	None,
	Conflict_Assistance,
}

/* Extension_Observation_Family identifies one copied repository truth family. */
Extension_Observation_Family :: enum u8 {
	Status,
	History,
	Refs,
	Sequence,
	Conflict,
	Process,
}

/* Extension_Observation_Families is one declared copied-observation set. */
Extension_Observation_Families :: bit_set[Extension_Observation_Family; u16]

/* Extension_Authority identifies one native operation exposed to a scoped turn. */
Extension_Authority :: enum u8 {
	Inspect,
	Present,
	Invoke_Declared_Command,
	Request_Core_Action,
	Submit_External_Operation,
	Assist_Conflict,
}

/* Extension_Authorities is one explicit non-owning native authority set. */
Extension_Authorities :: bit_set[Extension_Authority; u16]

/* Contributor_Lifecycle identifies one complete generation state. */
Contributor_Lifecycle :: enum u8 {
	Invalid,
	Loaded,
	Prepared,
	Confirmed,
	Active,
	Rejected,
	Replaced,
	Failed,
	Disabled,
	Retiring,
	Closed,
}

/* Extension_Surface identifies one Ksawery-owned semantic presentation context. */
Extension_Surface :: enum u8 {
	Invalid,
	Status,
	History,
	Refs,
	Sequence,
	Conflict,
	Process,
	Inspection,
}

/* Extension_Target_Kind identifies one copied semantic target family. */
Extension_Target_Kind :: enum u8 {
	None,
	Path,
	Revision,
	Revision_Range,
	Ref,
	Remote,
	Conflict,
	Sequence,
	Process,
}

/* Extension_Target identifies one exact generation-bound semantic target. */
Extension_Target :: struct {
	kind:       Extension_Target_Kind,
	generation: u64,
	identity:   u64,
}

/* Contributor_Handle identifies one exact contributor generation. */
Contributor_Handle :: struct {
	contributor: Contributor_ID,
	generation:  Contributor_Generation,
}

/* Extension_Resource_Limits selects one bounded contributor execution profile. */
Extension_Resource_Limits :: struct {
	contributors:                  u16,
	contributions_per_contributor: u16,
	total_contributions:           u32,
	declaration_bytes:             u64,
	observation_bytes:             u64,
	result_bytes:                  u64,
	provider_value_bytes:          u64,
	diagnostic_bytes:              u64,
	turn_deadline_ns:              i64,
	custodian_memory_bytes:        u64,
	callbacks_per_turn:            u16,
	nesting_depth:                 u8,
	retained_native_bytes:         u64,
	temporary_native_bytes:        u64,
}

/* DEFAULT_EXTENSION_RESOURCE_LIMITS is the measured initial provider policy. */
DEFAULT_EXTENSION_RESOURCE_LIMITS :: Extension_Resource_Limits {
	contributors = DEFAULT_EXTENSION_CONTRIBUTORS,
	contributions_per_contributor = DEFAULT_EXTENSION_CONTRIBUTIONS_PER_CONTRIBUTOR,
	total_contributions = DEFAULT_EXTENSION_CONTRIBUTIONS,
	declaration_bytes = DEFAULT_EXTENSION_DECLARATION_BYTES,
	observation_bytes = DEFAULT_EXTENSION_OBSERVATION_BYTES,
	result_bytes = DEFAULT_EXTENSION_RESULT_BYTES,
	provider_value_bytes = DEFAULT_EXTENSION_PROVIDER_VALUE_BYTES,
	diagnostic_bytes = DEFAULT_EXTENSION_DIAGNOSTIC_BYTES,
	turn_deadline_ns = DEFAULT_EXTENSION_TURN_DEADLINE_NS,
	custodian_memory_bytes = DEFAULT_EXTENSION_CUSTODIAN_MEMORY_BYTES,
	callbacks_per_turn = DEFAULT_EXTENSION_CALLBACKS_PER_TURN,
	nesting_depth = MAX_EXTENSION_NESTING_DEPTH,
	retained_native_bytes = MAX_EXTENSION_RETAINED_NATIVE_BYTES,
	temporary_native_bytes = MAX_EXTENSION_TEMPORARY_NATIVE_BYTES,
}

/* MAX_EXTENSION_RESOURCE_LIMITS records every immutable provider ceiling. */
MAX_EXTENSION_RESOURCE_LIMITS :: Extension_Resource_Limits {
	contributors = MAX_EXTENSION_CONTRIBUTORS,
	contributions_per_contributor = MAX_EXTENSION_CONTRIBUTIONS_PER_CONTRIBUTOR,
	total_contributions = MAX_EXTENSION_CONTRIBUTIONS,
	declaration_bytes = MAX_EXTENSION_DECLARATION_BYTES,
	observation_bytes = MAX_EXTENSION_OBSERVATION_BYTES,
	result_bytes = MAX_EXTENSION_RESULT_BYTES,
	provider_value_bytes = MAX_EXTENSION_PROVIDER_VALUE_BYTES,
	diagnostic_bytes = MAX_EXTENSION_DIAGNOSTIC_BYTES,
	turn_deadline_ns = MAX_EXTENSION_TURN_DEADLINE_NS,
	custodian_memory_bytes = MAX_EXTENSION_CUSTODIAN_MEMORY_BYTES,
	callbacks_per_turn = MAX_EXTENSION_CALLBACKS_PER_TURN,
	nesting_depth = MAX_EXTENSION_NESTING_DEPTH,
	retained_native_bytes = MAX_EXTENSION_RETAINED_NATIVE_BYTES,
	temporary_native_bytes = MAX_EXTENSION_TEMPORARY_NATIVE_BYTES,
}

/* Contribution_Declaration borrows one complete contributor-owned definition. */
Contribution_Declaration :: struct {
	id:                    Contribution_ID,
	identity:              Extension_Identity,
	kind:                  Contribution_Kind,
	provider_role:         Provider_Role,
	required_observations: Extension_Observation_Families,
	requested_authority:   Extension_Authorities,
}

/* Contributor_Declaration borrows one complete immutable candidate generation. */
Contributor_Declaration :: struct {
	identity:      Contributor_Identity,
	display_name:  Extension_Label,
	provenance:    Contributor_Provenance,
	generation:    Contributor_Generation,
	api_version:   u32,
	limits:        Extension_Resource_Limits,
	contributions: []Contribution_Declaration,
}

/* Extension_Turn_Scope is copied native truth valid for one dynamic extent. */
Extension_Turn_Scope :: struct {
	turn:                   Extension_Turn_ID,
	contributor:            Contributor_Handle,
	repository:             Repository_Context,
	repository_generation:  Repository_Generation,
	worktree_generation:    Worktree_Generation,
	observation_generation: Observation_Generation,
	surface:                Extension_Surface,
	surface_generation:     Extension_Surface_Generation,
	selection_generation:   Extension_Selection_Generation,
	target:                 Extension_Target,
	capability_generation:  Extension_Capability_Generation,
	owner_thread:           u64,
	deadline_ns:            i64,
	callback_budget:        u16,
	active_operation:       bool,
	mutation_available:     bool,
	truncated:              bool,
	private_content_omitted: bool,
}

/* Extension_Capability is an opaque non-owning handle for one scoped turn. */
Extension_Capability :: struct {
	turn:         Extension_Turn_ID,
	contributor:  Contributor_Handle,
	generation:   Extension_Capability_Generation,
	owner_thread: u64,
	authorities:  Extension_Authorities,
}

/* Extension_Usage reports exact contributor-owned bounded resources. */
Extension_Usage :: struct {
	contributions:        u32,
	declaration_bytes:    u64,
	observation_bytes:    u64,
	result_bytes:         u64,
	provider_value_bytes: u64,
	diagnostic_bytes:     u64,
	retained_native_bytes: u64,
	temporary_native_bytes: u64,
	turns:                u64,
	callbacks:            u64,
	failures:             u64,
}

/* Extension_Operation identifies one attributable lifecycle or turn action. */
Extension_Operation :: enum u8 {
	Invalid,
	Load,
	Prepare,
	Confirm,
	Activate,
	Replace,
	Reject,
	Disable,
	Begin_Turn,
	Publish,
	Inspect,
	Close,
}

/* Extension_Failure_Code classifies expected provider-boundary rejection. */
Extension_Failure_Code :: enum u16 {
	None,
	Invalid_Declaration,
	Incompatible_API,
	Duplicate_Contributor,
	Duplicate_Contribution,
	Contributor_Limit,
	Contribution_Limit,
	Declaration_Limit,
	Observation_Limit,
	Result_Limit,
	Provider_Value_Limit,
	Diagnostic_Limit,
	Authority_Unavailable,
	Invalid_Scope,
	Stale_Contributor,
	Stale_Repository,
	Stale_Observation,
	Stale_Surface,
	Stale_Selection,
	Stale_Capability,
	Wrong_Thread,
	Reentrant_Turn,
	Callback_Limit,
	Timeout,
	Memory_Limit,
	Provider_Exception,
	Allocation,
	Cleanup,
}

/* Extension_Failure is copied bounded metadata for one attributable failure. */
Extension_Failure :: struct {
	code:             Extension_Failure_Code,
	operation:        Extension_Operation,
	contributor:      Contributor_Handle,
	contribution:     Contribution_ID,
	limit:            u64,
	actual:           u64,
	diagnostic_bytes: u32,
	diagnostic_truncated: bool,
}

/* Contributor_Inspection is one copied generation lifecycle and usage summary. */
Contributor_Inspection :: struct {
	handle:              Contributor_Handle,
	identity:            Contributor_Identity,
	display_name:        Extension_Label,
	provenance:          Contributor_Provenance,
	lifecycle:           Contributor_Lifecycle,
	requested_authority: Extension_Authorities,
	contribution_count:  u32,
	provider_role_count: u16,
	usage:               Extension_Usage,
	latest_failure:      Extension_Failure,
	active_process:      Repository_Operation_ID,
}

/* contributor_identity_assign copies one validated stable identity. */
contributor_identity_assign :: proc(identity: ^Contributor_Identity, value: string) -> bool {
	if identity == nil do return false
	identity^ = {}
	if !extension_identity_text_is_valid(value) do return false
	copy(identity.bytes[:len(value)], transmute([]u8)value)
	identity.length = u16(len(value))
	return true
}

/* extension_identity_assign copies one validated contributor-local identity. */
extension_identity_assign :: proc(identity: ^Extension_Identity, value: string) -> bool {
	if identity == nil do return false
	identity^ = {}
	if !extension_identity_text_is_valid(value) do return false
	copy(identity.bytes[:len(value)], transmute([]u8)value)
	identity.length = u16(len(value))
	return true
}

/* extension_label_assign copies one validated public display label. */
extension_label_assign :: proc(label: ^Extension_Label, value: string) -> bool {
	if label == nil do return false
	label^ = {}
	if len(value) == 0 || len(value) > len(label.bytes) || !utf8.valid_string(value) do return false
	copy(label.bytes[:len(value)], transmute([]u8)value)
	label.length = u16(len(value))
	return true
}

/* contributor_provenance_assign copies one validated source identity. */
contributor_provenance_assign :: proc(
	provenance: ^Contributor_Provenance,
	origin: Contributor_Origin,
	value: string,
) -> bool {
	if provenance == nil do return false
	provenance^ = {}
	if origin == .Invalid || len(value) == 0 || len(value) > len(provenance.bytes) ||
	   !utf8.valid_string(value) {
		return false
	}
	provenance.origin = origin
	copy(provenance.bytes[:len(value)], transmute([]u8)value)
	provenance.length = u16(len(value))
	return true
}

/* contributor_handle_is_valid checks one exact nonzero generation identity. */
contributor_handle_is_valid :: proc(handle: Contributor_Handle) -> bool {
	return handle.contributor != Contributor_ID(0) && handle.generation != Contributor_Generation(0)
}

/* extension_resource_limits_are_valid checks one policy against immutable maxima. */
extension_resource_limits_are_valid :: proc(limits: Extension_Resource_Limits) -> bool {
	return limits.contributors > 0 && limits.contributors <= MAX_EXTENSION_CONTRIBUTORS &&
		limits.contributions_per_contributor > 0 &&
		limits.contributions_per_contributor <= MAX_EXTENSION_CONTRIBUTIONS_PER_CONTRIBUTOR &&
		limits.total_contributions > 0 && limits.total_contributions <= MAX_EXTENSION_CONTRIBUTIONS &&
		u32(limits.contributors) * u32(limits.contributions_per_contributor) >= limits.total_contributions &&
		limits.declaration_bytes > 0 && limits.declaration_bytes <= MAX_EXTENSION_DECLARATION_BYTES &&
		limits.observation_bytes > 0 && limits.observation_bytes <= MAX_EXTENSION_OBSERVATION_BYTES &&
		limits.result_bytes > 0 && limits.result_bytes <= MAX_EXTENSION_RESULT_BYTES &&
		limits.provider_value_bytes > 0 && limits.provider_value_bytes <= MAX_EXTENSION_PROVIDER_VALUE_BYTES &&
		limits.diagnostic_bytes > 0 && limits.diagnostic_bytes <= MAX_EXTENSION_DIAGNOSTIC_BYTES &&
		limits.turn_deadline_ns > 0 && limits.turn_deadline_ns <= MAX_EXTENSION_TURN_DEADLINE_NS &&
		limits.custodian_memory_bytes > 0 && limits.custodian_memory_bytes <= MAX_EXTENSION_CUSTODIAN_MEMORY_BYTES &&
		limits.callbacks_per_turn > 0 && limits.callbacks_per_turn <= MAX_EXTENSION_CALLBACKS_PER_TURN &&
		limits.nesting_depth == MAX_EXTENSION_NESTING_DEPTH &&
		limits.retained_native_bytes > 0 && limits.retained_native_bytes <= MAX_EXTENSION_RETAINED_NATIVE_BYTES &&
		limits.temporary_native_bytes > 0 && limits.temporary_native_bytes <= MAX_EXTENSION_TEMPORARY_NATIVE_BYTES
}

/* contribution_declaration_is_valid checks one complete owner-local definition. */
contribution_declaration_is_valid :: proc(declaration: Contribution_Declaration) -> bool {
	if declaration.id == Contribution_ID(0) || !extension_identity_is_valid(declaration.identity) ||
	   declaration.kind == .Invalid || declaration.requested_authority == {} {
		return false
	}
	if declaration.kind == .Provider_Role {
		return declaration.provider_role != .None
	}
	return declaration.provider_role == .None
}

/* contributor_declaration_is_valid checks one atomic candidate without copying it. */
contributor_declaration_is_valid :: proc(declaration: Contributor_Declaration) -> bool {
	if !contributor_identity_is_valid(declaration.identity) ||
	   !extension_label_is_valid(declaration.display_name) ||
	   !contributor_provenance_is_valid(declaration.provenance) ||
	   declaration.generation == Contributor_Generation(0) ||
	   declaration.api_version != EXTENSION_API_VERSION ||
	   !extension_resource_limits_are_valid(declaration.limits) ||
	   len(declaration.contributions) == 0 ||
	   len(declaration.contributions) > int(declaration.limits.contributions_per_contributor) {
		return false
	}
	for contribution, index in declaration.contributions {
		if !contribution_declaration_is_valid(contribution) do return false
		for prior in 0 ..< index {
			candidate := declaration.contributions[prior]
			if candidate.id == contribution.id || candidate.identity == contribution.identity do return false
		}
	}
	return true
}

/* contributor_lifecycle_transition_is_valid checks the closed generation graph. */
contributor_lifecycle_transition_is_valid :: proc(from, to: Contributor_Lifecycle) -> bool {
	switch from {
	case .Loaded:
		return to == .Prepared || to == .Rejected || to == .Closed
	case .Prepared:
		return to == .Confirmed || to == .Rejected || to == .Closed
	case .Confirmed:
		return to == .Active || to == .Rejected || to == .Closed
	case .Active:
		return to == .Replaced || to == .Failed || to == .Disabled || to == .Retiring || to == .Closed
	case .Rejected, .Replaced, .Failed, .Disabled:
		return to == .Retiring || to == .Closed
	case .Retiring:
		return to == .Closed
	case .Invalid, .Closed:
		return false
	}
	return false
}

/* extension_turn_scope_is_valid checks one copied synchronous dynamic extent. */
extension_turn_scope_is_valid :: proc(scope: Extension_Turn_Scope, limits: Extension_Resource_Limits) -> bool {
	return extension_resource_limits_are_valid(limits) && scope.turn != Extension_Turn_ID(0) &&
		contributor_handle_is_valid(scope.contributor) && repository_context_is_valid(scope.repository) &&
		scope.repository_generation != Repository_Generation(0) &&
		scope.worktree_generation != Worktree_Generation(0) &&
		scope.observation_generation != Observation_Generation(0) && scope.surface != .Invalid &&
		scope.surface_generation != Extension_Surface_Generation(0) &&
		scope.selection_generation != Extension_Selection_Generation(0) &&
		extension_target_is_valid(scope.target) &&
		scope.capability_generation != Extension_Capability_Generation(0) && scope.owner_thread != 0 &&
		scope.deadline_ns > 0 && scope.deadline_ns <= limits.turn_deadline_ns &&
		scope.callback_budget > 0 && scope.callback_budget <= limits.callbacks_per_turn
}

/* extension_capability_is_current checks authority and every revocable scope key. */
extension_capability_is_current :: proc(
	capability: Extension_Capability,
	scope: Extension_Turn_Scope,
	current_thread: u64,
	required: Extension_Authority,
) -> bool {
	return current_thread != 0 && current_thread == scope.owner_thread &&
		capability.turn == scope.turn && capability.contributor == scope.contributor &&
		capability.generation == scope.capability_generation && capability.owner_thread == current_thread &&
		required in capability.authorities
}

/* extension_turn_scope_matches checks every generation that can revoke publication. */
extension_turn_scope_matches :: proc(captured, current: Extension_Turn_Scope) -> bool {
	return captured.turn == current.turn && captured.contributor == current.contributor &&
		captured.repository == current.repository &&
		captured.repository_generation == current.repository_generation &&
		captured.worktree_generation == current.worktree_generation &&
		captured.observation_generation == current.observation_generation &&
		captured.surface == current.surface &&
		captured.surface_generation == current.surface_generation &&
		captured.selection_generation == current.selection_generation &&
		captured.target == current.target &&
		captured.capability_generation == current.capability_generation &&
		captured.owner_thread == current.owner_thread
}

/* extension_usage_within_limits checks exact retained and turn accounting. */
extension_usage_within_limits :: proc(usage: Extension_Usage, limits: Extension_Resource_Limits) -> bool {
	return extension_resource_limits_are_valid(limits) &&
		usage.contributions <= u32(limits.contributions_per_contributor) &&
		usage.declaration_bytes <= limits.declaration_bytes &&
		usage.observation_bytes <= limits.observation_bytes &&
		usage.result_bytes <= limits.result_bytes &&
		usage.provider_value_bytes <= limits.provider_value_bytes &&
		usage.diagnostic_bytes <= limits.diagnostic_bytes &&
		usage.retained_native_bytes <= limits.retained_native_bytes &&
		usage.temporary_native_bytes <= limits.temporary_native_bytes
}

/* contributor_inspection_is_valid checks one copied attributable summary. */
contributor_inspection_is_valid :: proc(inspection: Contributor_Inspection) -> bool {
	return contributor_handle_is_valid(inspection.handle) &&
		contributor_identity_is_valid(inspection.identity) &&
		extension_label_is_valid(inspection.display_name) &&
		contributor_provenance_is_valid(inspection.provenance) &&
		inspection.lifecycle != .Invalid &&
		inspection.contribution_count <= u32(MAX_EXTENSION_CONTRIBUTIONS_PER_CONTRIBUTOR) &&
		u32(inspection.provider_role_count) <= inspection.contribution_count &&
		extension_usage_within_limits(inspection.usage, MAX_EXTENSION_RESOURCE_LIMITS) &&
		u64(inspection.latest_failure.diagnostic_bytes) <= MAX_EXTENSION_DIAGNOSTIC_BYTES
}

@(private)
extension_identity_text_is_valid :: proc(value: string) -> bool {
	if len(value) == 0 || len(value) > MAX_EXTENSION_IDENTITY_BYTES || !utf8.valid_string(value) do return false
	for byte in transmute([]u8)value {
		if !(byte >= 'a' && byte <= 'z') && !(byte >= '0' && byte <= '9') &&
		   byte != '-' && byte != '.' && byte != '/' {
			return false
		}
	}
	return true
}

@(private)
contributor_identity_is_valid :: proc(identity: Contributor_Identity) -> bool {
	bytes := identity.bytes
	return identity.length > 0 && identity.length <= len(identity.bytes) &&
		extension_identity_text_is_valid(string(bytes[:int(identity.length)]))
}

@(private)
extension_identity_is_valid :: proc(identity: Extension_Identity) -> bool {
	bytes := identity.bytes
	return identity.length > 0 && identity.length <= len(identity.bytes) &&
		extension_identity_text_is_valid(string(bytes[:int(identity.length)]))
}

@(private)
extension_label_is_valid :: proc(label: Extension_Label) -> bool {
	bytes := label.bytes
	return label.length > 0 && label.length <= len(label.bytes) &&
		utf8.valid_string(string(bytes[:int(label.length)]))
}

@(private)
contributor_provenance_is_valid :: proc(provenance: Contributor_Provenance) -> bool {
	bytes := provenance.bytes
	return provenance.origin != .Invalid && provenance.length > 0 &&
		provenance.length <= len(provenance.bytes) &&
		utf8.valid_string(string(bytes[:int(provenance.length)]))
}

@(private)
extension_target_is_valid :: proc(target: Extension_Target) -> bool {
	if target.kind == .None do return target.generation == 0 && target.identity == 0
	return target.generation != 0 && target.identity != 0
}
