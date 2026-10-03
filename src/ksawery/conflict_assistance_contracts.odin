// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:crypto/sha2"
import "core:unicode/utf8"

/* DEFAULT_CONFLICT_ASSISTANCE_PROVIDERS is the initial selectable provider budget. */
DEFAULT_CONFLICT_ASSISTANCE_PROVIDERS :: u16(8)
/* MAX_CONFLICT_ASSISTANCE_PROVIDERS is the immutable selectable provider ceiling. */
MAX_CONFLICT_ASSISTANCE_PROVIDERS :: u16(32)
/* MAX_CONFLICT_ASSISTANCE_PATH_BYTES bounds one copied conflict path. */
MAX_CONFLICT_ASSISTANCE_PATH_BYTES :: 4 * KIBIBYTE
/* MAX_CONFLICT_ASSISTANCE_GUIDANCE_BYTES bounds one copied guidance response. */
MAX_CONFLICT_ASSISTANCE_GUIDANCE_BYTES :: 32 * KIBIBYTE
/* DEFAULT_CONFLICT_ASSISTANCE_CONTENT_BYTES is the initial copied-side budget. */
DEFAULT_CONFLICT_ASSISTANCE_CONTENT_BYTES :: u64(1 * MEBIBYTE)
/* MAX_CONFLICT_ASSISTANCE_CONTENT_BYTES is the immutable copied-side ceiling. */
MAX_CONFLICT_ASSISTANCE_CONTENT_BYTES :: u64(4 * MEBIBYTE)
/* DEFAULT_CONFLICT_ASSISTANCE_COPY_BYTES is the initial complete-response budget. */
DEFAULT_CONFLICT_ASSISTANCE_COPY_BYTES :: u64(2 * MEBIBYTE)
/* MAX_CONFLICT_ASSISTANCE_COPY_BYTES is the immutable complete-response ceiling. */
MAX_CONFLICT_ASSISTANCE_COPY_BYTES :: u64(8 * MEBIBYTE)

/* Conflict_Assistance_Provider_ID identifies one semantic helper declaration. */
Conflict_Assistance_Provider_ID :: distinct u64
/* Conflict_Assistance_Provider_Generation identifies one immutable provider generation. */
Conflict_Assistance_Provider_Generation :: distinct u64
/* Conflict_Assistance_Selection_ID identifies one explicit role selection. */
Conflict_Assistance_Selection_ID :: distinct u64
/* Conflict_Assistance_Selection_Generation identifies one replaceable selection state. */
Conflict_Assistance_Selection_Generation :: distinct u64
/* Conflict_Assistance_Request_ID identifies one exact provider turn. */
Conflict_Assistance_Request_ID :: distinct u64

/* Conflict_Assistance_Index_Fingerprint identifies one complete staged-index snapshot. */
Conflict_Assistance_Index_Fingerprint :: struct {
	bytes: [32]u8,
}

BUILT_IN_CONFLICT_ASSISTANCE_PROVIDER_ID :: Conflict_Assistance_Provider_ID(1)
BUILT_IN_CONFLICT_ASSISTANCE_PROVIDER_GENERATION :: Conflict_Assistance_Provider_Generation(1)
BUILT_IN_CONFLICT_ASSISTANCE_SELECTION_ID :: Conflict_Assistance_Selection_ID(1)

/* Conflict_Assistance_Class names explicit conflict material and support boundaries. */
Conflict_Assistance_Class :: enum u8 {
	Invalid,
	Text,
	Binary,
	Rename,
	Delete,
	Type_Change,
	Submodule,
	Missing_Stage,
	Truncated,
	Unsupported,
}

/* Conflict_Assistance_Classes is one declared support or observed-class set. */
Conflict_Assistance_Classes :: bit_set[Conflict_Assistance_Class; u16]

ALL_CONFLICT_ASSISTANCE_CLASSES :: Conflict_Assistance_Classes {
	.Text,
	.Binary,
	.Rename,
	.Delete,
	.Type_Change,
	.Submodule,
	.Missing_Stage,
	.Truncated,
	.Unsupported,
}

/* Conflict_Assistance_Provider_Origin distinguishes the fallback from an extension. */
Conflict_Assistance_Provider_Origin :: enum u8 {
	Invalid,
	Built_In_No_Op,
	Extension,
}

/* Conflict_Assistance_Capability closes the provider response surface. */
Conflict_Assistance_Capability :: enum u8 {
	Present_Guidance,
	Open_Editor,
	Submit_External_Tool,
}

/* Conflict_Assistance_Capabilities is one declared response capability set. */
Conflict_Assistance_Capabilities :: bit_set[Conflict_Assistance_Capability; u8]

/* Conflict_Assistance_Provider_Lifecycle identifies one provider generation state. */
Conflict_Assistance_Provider_Lifecycle :: enum u8 {
	Invalid,
	Declared,
	Prepared,
	Confirmed,
	Active,
	Declined,
	Failed,
	Disabled,
	Replaced,
	Retiring,
	Closed,
}

/* Conflict_Assistance_Provider declares one replaceable semantic helper. */
Conflict_Assistance_Provider :: struct {
	origin:            Conflict_Assistance_Provider_Origin,
	contributor:       Contributor_Handle,
	contribution:      Contribution_ID,
	provider:          Conflict_Assistance_Provider_ID,
	generation:        Conflict_Assistance_Provider_Generation,
	identity:          Extension_Identity,
	label:             Extension_Label,
	supported_classes: Conflict_Assistance_Classes,
	capabilities:      Conflict_Assistance_Capabilities,
	lifecycle:         Conflict_Assistance_Provider_Lifecycle,
}

/* Conflict_Assistance_Provider_Reference copies one exact provider generation identity. */
Conflict_Assistance_Provider_Reference :: struct {
	origin:      Conflict_Assistance_Provider_Origin,
	contributor: Contributor_Handle,
	provider:    Conflict_Assistance_Provider_ID,
	generation:  Conflict_Assistance_Provider_Generation,
}

/* Conflict_Assistance_Path owns one bounded copied conflict path. */
Conflict_Assistance_Path :: struct {
	bytes:  [MAX_CONFLICT_ASSISTANCE_PATH_BYTES]u8,
	length: u16,
}

/* Conflict_Assistance_Target binds one conflict to exact repository and observation truth. */
Conflict_Assistance_Target :: struct {
	repository:             Repository_Context,
	repository_generation:  Repository_Generation,
	worktree_generation:    Worktree_Generation,
	observation_generation: Observation_Generation,
	conflict:               Conflict_Target_ID,
	kind:                   Conflict_Kind,
	classes:                Conflict_Assistance_Classes,
	path:                   Conflict_Assistance_Path,
}

/* Conflict_Assistance_Side_Kind names the four inspectable conflict materials. */
Conflict_Assistance_Side_Kind :: enum u8 {
	Invalid,
	Base,
	Current,
	Applied,
	Worktree,
}

/* Conflict_Assistance_Material_Kind describes one copied or explicitly absent side. */
Conflict_Assistance_Material_Kind :: enum u8 {
	Invalid,
	Missing,
	Text,
	Binary,
	Submodule,
	Omitted,
}

/* Conflict_Assistance_Content_Ref identifies bytes in one copied observation blob. */
Conflict_Assistance_Content_Ref :: struct {
	offset: u32,
	length: u32,
}

/* Conflict_Assistance_Side describes one exact copied index or worktree material. */
Conflict_Assistance_Side :: struct {
	kind:      Conflict_Assistance_Side_Kind,
	material:  Conflict_Assistance_Material_Kind,
	mode:      u32,
	object:    Revision_Identity,
	content:   Conflict_Assistance_Content_Ref,
	truncated: bool,
}

/* Conflict_Assistance_Observation borrows one complete copied exact Conflict payload. */
Conflict_Assistance_Observation :: struct {
	target:    Conflict_Assistance_Target,
	sides:     [4]Conflict_Assistance_Side,
	content:   []u8,
	truncated: bool,
}

/* Conflict_Assistance_Selection_Scope fixes deterministic role precedence. */
Conflict_Assistance_Selection_Scope :: enum u8 {
	Invalid,
	Built_In_Fallback,
	Global,
	Project,
	Repository,
	Session,
}

/* Conflict_Assistance_Selection records one confirmed provider choice or fallback. */
Conflict_Assistance_Selection :: struct {
	selection:     Conflict_Assistance_Selection_ID,
	generation:    Conflict_Assistance_Selection_Generation,
	scope:         Conflict_Assistance_Selection_Scope,
	scope_identity: Extension_Identity,
	repository:    Repository_Context,
	session:       u64,
	provider:      Conflict_Assistance_Provider_Reference,
	confirmed:     bool,
}

/* Conflict_Assistance_Request binds one selected provider to one exact Conflict target. */
Conflict_Assistance_Request :: struct {
	request:              Conflict_Assistance_Request_ID,
	selection_generation: Conflict_Assistance_Selection_Generation,
	provider:             Conflict_Assistance_Provider_Reference,
	target:               Conflict_Assistance_Target,
}

/* Conflict_Assistance_Guidance owns one bounded copied public response. */
Conflict_Assistance_Guidance :: struct {
	bytes:  [MAX_CONFLICT_ASSISTANCE_GUIDANCE_BYTES]u8,
	length: u16,
}

/* Conflict_Assistance_Tool_Access limits an admitted helper to inspection or worktree material. */
Conflict_Assistance_Tool_Access :: enum u8 {
	Invalid,
	Read_Only,
	Worktree_Only,
}

CONFLICT_ASSISTANCE_TOOL_REFRESH :: Extension_Observation_Families {
	.Status,
	.Sequence,
	.Conflict,
	.Process,
}

/* Conflict_Assistance_Tool_Plan binds an admitted external operation to one Conflict. */
Conflict_Assistance_Tool_Plan :: struct {
	request:  Conflict_Assistance_Request_ID,
	provider: Conflict_Assistance_Provider_Reference,
	target:   Conflict_Assistance_Target,
	access:   Conflict_Assistance_Tool_Access,
	operation: Extension_Operation_Plan,
}

/* Conflict_Assistance_Tool_Admission binds Process ownership to pre-tool core truth. */
Conflict_Assistance_Tool_Admission :: struct {
	request:       Conflict_Assistance_Request,
	operation:     Extension_Operation_Submission,
	access:        Conflict_Assistance_Tool_Access,
	index_before:  Conflict_Assistance_Index_Fingerprint,
}

/* Conflict_Assistance_Tool_Refresh_Evidence records mandatory post-tool core observations. */
Conflict_Assistance_Tool_Refresh_Evidence :: struct {
	repository:             Repository_Context,
	repository_generation:  Repository_Generation,
	worktree_generation:    Worktree_Generation,
	observation_generation: Observation_Generation,
	attempted:              Extension_Observation_Families,
	completed:              Extension_Observation_Families,
	target_checked:         bool,
	target_present:         bool,
	target:                 Conflict_Assistance_Target,
	index_after:            Conflict_Assistance_Index_Fingerprint,
}

/* Conflict_Assistance_Tool_Result retains Process evidence and core policy checks. */
Conflict_Assistance_Tool_Result :: struct {
	request:           Conflict_Assistance_Request_ID,
	provider:          Conflict_Assistance_Provider_Reference,
	target:            Conflict_Assistance_Target,
	operation:         Extension_Operation_Result,
	refresh_completed: bool,
	index_preserved:   bool,
	conflict_retained: bool,
}

/* Conflict_Assistance_Response_Kind closes provider output without core actions. */
Conflict_Assistance_Response_Kind :: enum u8 {
	Invalid,
	Declined,
	Guidance,
	Editor,
	External_Tool,
}

/* Conflict_Assistance_Response is one attributable provider proposal. */
Conflict_Assistance_Response :: struct {
	request:  Conflict_Assistance_Request_ID,
	provider: Conflict_Assistance_Provider_Reference,
	target:   Conflict_Assistance_Target,
	kind:     Conflict_Assistance_Response_Kind,
	guidance: Conflict_Assistance_Guidance,
	tool:     Conflict_Assistance_Tool_Plan,
}

/* Conflict_Assistance_Limits bounds providers and copied conflict material. */
Conflict_Assistance_Limits :: struct {
	providers:      u16,
	guidance_bytes: u64,
	content_bytes:  u64,
	copy_bytes:     u64,
}

/* DEFAULT_CONFLICT_ASSISTANCE_LIMITS selects the initial bounded helper envelope. */
DEFAULT_CONFLICT_ASSISTANCE_LIMITS :: Conflict_Assistance_Limits {
	providers = DEFAULT_CONFLICT_ASSISTANCE_PROVIDERS,
	guidance_bytes = 4 * KIBIBYTE,
	content_bytes = DEFAULT_CONFLICT_ASSISTANCE_CONTENT_BYTES,
	copy_bytes = DEFAULT_CONFLICT_ASSISTANCE_COPY_BYTES,
}

/* MAX_CONFLICT_ASSISTANCE_LIMITS records every immutable helper ceiling. */
MAX_CONFLICT_ASSISTANCE_LIMITS :: Conflict_Assistance_Limits {
	providers = MAX_CONFLICT_ASSISTANCE_PROVIDERS,
	guidance_bytes = MAX_CONFLICT_ASSISTANCE_GUIDANCE_BYTES,
	content_bytes = MAX_CONFLICT_ASSISTANCE_CONTENT_BYTES,
	copy_bytes = MAX_CONFLICT_ASSISTANCE_COPY_BYTES,
}

/* Conflict_Assistance_Usage reports exact copied helper occupancy. */
Conflict_Assistance_Usage :: struct {
	providers:       u16,
	selections:      u16,
	requests:        u64,
	sides:           u32,
	path_bytes:      u64,
	content_bytes:   u64,
	guidance_bytes:  u64,
	external_tools:  u64,
	copy_bytes:      u64,
	failures:        u64,
}

/* Conflict_Assistance_Failure_Code classifies bounded helper rejection. */
Conflict_Assistance_Failure_Code :: enum u16 {
	None,
	Invalid_Provider,
	Invalid_Contribution,
	Invalid_Target,
	Unsupported_Conflict,
	Invalid_Side,
	Invalid_Guidance,
	Invalid_Tool_Plan,
	Invalid_Lifecycle,
	Invalid_Selection,
	Invalid_Response,
	Stale_Contributor,
	Stale_Provider,
	Stale_Selection,
	Stale_Repository,
	Stale_Observation,
	Stale_Target,
	Provider_Limit,
	Guidance_Limit,
	Content_Limit,
	Copy_Limit,
	Provider_Declined,
	Provider_Exception,
	Tool_Unavailable,
	Index_Mutation_Prohibited,
	Core_Action_Prohibited,
	Allocation,
	Cleanup,
}

/* Conflict_Assistance_Failure retains attributable bounded rejection evidence. */
Conflict_Assistance_Failure :: struct {
	code:       Conflict_Assistance_Failure_Code,
	provider:   Conflict_Assistance_Provider_ID,
	request:    Conflict_Assistance_Request_ID,
	target:     Conflict_Target_ID,
	side:       Conflict_Assistance_Side_Kind,
	limit:      u64,
	actual:     u64,
}

/* conflict_assistance_path_assign copies one checked exact conflict path. */
conflict_assistance_path_assign :: proc(path: ^Conflict_Assistance_Path, value: string) -> bool {
	if path == nil do return false
	path^ = {}
	if len(value) == 0 || len(value) > len(path.bytes) || !utf8.valid_string(value) do return false
	for byte in transmute([]u8)value {
		if byte == 0 do return false
	}
	copy(path.bytes[:len(value)], transmute([]u8)value)
	path.length = u16(len(value))
	return true
}

/* conflict_assistance_guidance_assign copies one bounded public UTF-8 response. */
conflict_assistance_guidance_assign :: proc(
	guidance: ^Conflict_Assistance_Guidance,
	value: string,
) -> bool {
	if guidance == nil do return false
	guidance^ = {}
	if len(value) == 0 || len(value) > len(guidance.bytes) || !utf8.valid_string(value) do return false
	for byte in transmute([]u8)value {
		if byte == 0 do return false
	}
	copy(guidance.bytes[:len(value)], transmute([]u8)value)
	guidance.length = u16(len(value))
	return true
}

/* conflict_assistance_limits_are_valid checks the complete selected envelope. */
conflict_assistance_limits_are_valid :: proc(limits: Conflict_Assistance_Limits) -> bool {
	return limits.providers > 0 && limits.providers <= MAX_CONFLICT_ASSISTANCE_PROVIDERS &&
		limits.guidance_bytes > 0 && limits.guidance_bytes <= MAX_CONFLICT_ASSISTANCE_GUIDANCE_BYTES &&
		limits.content_bytes > 0 && limits.content_bytes <= MAX_CONFLICT_ASSISTANCE_CONTENT_BYTES &&
		limits.copy_bytes > 0 && limits.copy_bytes <= MAX_CONFLICT_ASSISTANCE_COPY_BYTES &&
		limits.copy_bytes >= limits.content_bytes
}

/* conflict_assistance_builtin_no_op_provider returns the immutable safe fallback. */
conflict_assistance_builtin_no_op_provider :: proc() -> Conflict_Assistance_Provider {
	identity: Extension_Identity
	label: Extension_Label
	assert(extension_identity_assign(&identity, "built-in.conflict-assistance.no-op"))
	assert(extension_label_assign(&label, "No conflict assistance"))
	return {
		origin = .Built_In_No_Op,
		provider = BUILT_IN_CONFLICT_ASSISTANCE_PROVIDER_ID,
		generation = BUILT_IN_CONFLICT_ASSISTANCE_PROVIDER_GENERATION,
		identity = identity,
		label = label,
		supported_classes = ALL_CONFLICT_ASSISTANCE_CLASSES,
		lifecycle = .Active,
	}
}

/* conflict_assistance_provider_reference copies one valid provider identity. */
conflict_assistance_provider_reference :: proc(
	provider: Conflict_Assistance_Provider,
) -> Conflict_Assistance_Provider_Reference {
	return {
		origin = provider.origin,
		contributor = provider.contributor,
		provider = provider.provider,
		generation = provider.generation,
	}
}

/* conflict_assistance_provider_validate checks one complete provider declaration. */
conflict_assistance_provider_validate :: proc(
	provider: Conflict_Assistance_Provider,
	declaration: Contribution_Declaration,
) -> Conflict_Assistance_Failure {
	failure := Conflict_Assistance_Failure{provider = provider.provider}
	if provider.origin == .Built_In_No_Op {
		if provider != conflict_assistance_builtin_no_op_provider() || declaration != {} {
			failure.code = .Invalid_Provider
		}
		return failure
	}
	if provider.origin != .Extension || !contributor_handle_is_valid(provider.contributor) ||
	   provider.contribution == Contribution_ID(0) || provider.provider == Conflict_Assistance_Provider_ID(0) ||
	   provider.provider == BUILT_IN_CONFLICT_ASSISTANCE_PROVIDER_ID ||
	   provider.generation == Conflict_Assistance_Provider_Generation(0) ||
	   !extension_identity_is_valid(provider.identity) || !extension_label_is_valid(provider.label) ||
	   !conflict_assistance_classes_are_valid(provider.supported_classes) || provider.capabilities == {} ||
	   provider.lifecycle == .Invalid {
		failure.code = .Invalid_Provider
		return failure
	}
	if !contribution_declaration_is_valid(declaration) || declaration.id != provider.contribution ||
	   declaration.kind != .Provider_Role || declaration.provider_role != .Conflict_Assistance ||
	   .Conflict not_in declaration.required_observations ||
	   .Sequence not_in declaration.required_observations ||
	   .Inspect not_in declaration.requested_authority ||
	   .Present not_in declaration.requested_authority ||
	   .Assist_Conflict not_in declaration.requested_authority ||
	   (.Submit_External_Tool in provider.capabilities &&
	    .Submit_External_Operation not_in declaration.requested_authority) {
		failure.code = .Invalid_Contribution
	}
	return failure
}

/* conflict_assistance_provider_lifecycle_transition_is_valid checks the closed graph. */
conflict_assistance_provider_lifecycle_transition_is_valid :: proc(
	from, to: Conflict_Assistance_Provider_Lifecycle,
) -> bool {
	switch from {
	case .Declared:
		return to == .Prepared || to == .Failed || to == .Disabled || to == .Closed
	case .Prepared:
		return to == .Confirmed || to == .Failed || to == .Disabled || to == .Closed
	case .Confirmed:
		return to == .Active || to == .Failed || to == .Disabled || to == .Closed
	case .Active:
		return to == .Declined || to == .Failed || to == .Disabled || to == .Replaced ||
			to == .Retiring || to == .Closed
	case .Declined, .Failed, .Disabled, .Replaced:
		return to == .Prepared || to == .Retiring || to == .Closed
	case .Retiring:
		return to == .Closed
	case .Invalid, .Closed:
		return false
	}
	return false
}

/* conflict_assistance_target_is_valid checks one exact copied Conflict scope. */
conflict_assistance_target_is_valid :: proc(target: Conflict_Assistance_Target) -> bool {
	return repository_context_is_valid(target.repository) &&
		target.repository_generation != Repository_Generation(0) &&
		target.worktree_generation != Worktree_Generation(0) &&
		target.observation_generation != Observation_Generation(0) &&
		conflict_target_id_is_valid(target.conflict) && target.kind != .Invalid &&
		conflict_assistance_classes_are_valid(target.classes) &&
		conflict_assistance_path_is_valid(target.path)
}

/* conflict_assistance_targets_match compares every revocable target key. */
conflict_assistance_targets_match :: proc(
	left, right: Conflict_Assistance_Target,
) -> bool {
	return left == right
}

/* conflict_assistance_observation_validate checks copied sides and exact byte bounds. */
conflict_assistance_observation_validate :: proc(
	observation: Conflict_Assistance_Observation,
	limits := DEFAULT_CONFLICT_ASSISTANCE_LIMITS,
) -> (usage: Conflict_Assistance_Usage, failure: Conflict_Assistance_Failure) {
	failure.target = observation.target.conflict
	if !conflict_assistance_limits_are_valid(limits) ||
	   !conflict_assistance_target_is_valid(observation.target) {
		failure.code = .Invalid_Target
		return
	}
	if u64(len(observation.content)) > limits.content_bytes {
		failure.code = .Content_Limit
		failure.limit = limits.content_bytes
		failure.actual = u64(len(observation.content))
		return
	}
	truncated := false
	for side, index in observation.sides {
		expected := Conflict_Assistance_Side_Kind(index + 1)
		if !conflict_assistance_side_is_valid(side, expected, observation.content) {
			failure.code = .Invalid_Side
			failure.side = side.kind
			return
		}
		if side.material != .Missing do usage.sides += 1
		if side.truncated do truncated = true
	}
	if observation.truncated != truncated ||
	   ((.Truncated in observation.target.classes) != observation.truncated) {
		failure.code = .Invalid_Target
		return
	}
	usage.path_bytes = u64(observation.target.path.length)
	usage.content_bytes = u64(len(observation.content))
	usage.copy_bytes = u64(size_of(Conflict_Assistance_Observation)) + usage.content_bytes
	if usage.copy_bytes > limits.copy_bytes {
		failure.code = .Copy_Limit
		failure.limit = limits.copy_bytes
		failure.actual = usage.copy_bytes
	}
	return
}

/* conflict_assistance_provider_supports checks an exact observed class set. */
conflict_assistance_provider_supports :: proc(
	provider: Conflict_Assistance_Provider,
	target: Conflict_Assistance_Target,
) -> bool {
	return conflict_assistance_provider_shape_is_valid(provider) &&
		conflict_assistance_target_is_valid(target) &&
		provider.lifecycle == .Active && target.classes - provider.supported_classes == {}
}

/* conflict_assistance_selection_is_valid checks one confirmed role choice. */
conflict_assistance_selection_is_valid :: proc(selection: Conflict_Assistance_Selection) -> bool {
	if selection.selection == Conflict_Assistance_Selection_ID(0) ||
	   selection.generation == Conflict_Assistance_Selection_Generation(0) ||
	   !conflict_assistance_provider_reference_is_valid(selection.provider) {
		return false
	}
	switch selection.scope {
	case .Built_In_Fallback:
		return selection.selection == BUILT_IN_CONFLICT_ASSISTANCE_SELECTION_ID &&
			selection.provider.origin == .Built_In_No_Op && !selection.confirmed &&
			selection.scope_identity == {} && selection.repository == {} && selection.session == 0
	case .Global:
		return selection.provider.origin == .Extension && selection.confirmed &&
			selection.scope_identity == {} && selection.repository == {} && selection.session == 0
	case .Project:
		return selection.provider.origin == .Extension && selection.confirmed &&
			extension_identity_is_valid(selection.scope_identity) &&
			selection.repository == {} && selection.session == 0
	case .Repository:
		return selection.provider.origin == .Extension && selection.confirmed &&
			selection.scope_identity == {} && repository_context_is_valid(selection.repository) &&
			selection.session == 0
	case .Session:
		return selection.provider.origin == .Extension && selection.confirmed &&
			selection.scope_identity == {} && selection.repository == {} && selection.session != 0
	case .Invalid:
		return false
	}
	return false
}

/* conflict_assistance_builtin_fallback_selection returns the immutable no-op choice. */
conflict_assistance_builtin_fallback_selection :: proc(
	generation: Conflict_Assistance_Selection_Generation,
) -> Conflict_Assistance_Selection {
	provider := conflict_assistance_builtin_no_op_provider()
	return {
		selection = BUILT_IN_CONFLICT_ASSISTANCE_SELECTION_ID,
		generation = generation,
		scope = .Built_In_Fallback,
		provider = conflict_assistance_provider_reference(provider),
	}
}

/* conflict_assistance_selection_precedes applies deterministic narrowest-scope precedence. */
conflict_assistance_selection_precedes :: proc(
	candidate, current: Conflict_Assistance_Selection,
) -> bool {
	if !conflict_assistance_selection_is_valid(candidate) do return false
	if !conflict_assistance_selection_is_valid(current) do return true
	if candidate.scope != current.scope do return candidate.scope > current.scope
	if candidate.generation != current.generation do return candidate.generation > current.generation
	return candidate.selection > current.selection
}

/* conflict_assistance_request_validate admits one selected current provider and target. */
conflict_assistance_request_validate :: proc(
	request: Conflict_Assistance_Request,
	provider: Conflict_Assistance_Provider,
	selection: Conflict_Assistance_Selection,
) -> Conflict_Assistance_Failure {
	failure := Conflict_Assistance_Failure {
		provider = request.provider.provider,
		request = request.request,
		target = request.target.conflict,
	}
	if request.request == Conflict_Assistance_Request_ID(0) ||
	   !conflict_assistance_target_is_valid(request.target) {
		failure.code = .Invalid_Target
		return failure
	}
	if !conflict_assistance_selection_is_valid(selection) ||
	   request.selection_generation != selection.generation {
		failure.code = .Stale_Selection
		return failure
	}
	reference := conflict_assistance_provider_reference(provider)
	if request.provider != reference || selection.provider != reference {
		failure.code = .Stale_Provider
		return failure
	}
	if !conflict_assistance_provider_supports(provider, request.target) {
		failure.code = .Unsupported_Conflict
	}
	return failure
}

/* conflict_assistance_tool_plan_validate checks one admitted target-bound external plan. */
conflict_assistance_tool_plan_validate :: proc(
	tool: Conflict_Assistance_Tool_Plan,
	request: Conflict_Assistance_Request,
	provider: Conflict_Assistance_Provider,
) -> Conflict_Assistance_Failure {
	failure := Conflict_Assistance_Failure {
		provider = provider.provider,
		request = request.request,
		target = request.target.conflict,
	}
	if .Submit_External_Tool not_in provider.capabilities ||
	   tool.request != request.request || tool.provider != request.provider ||
	   !conflict_assistance_targets_match(tool.target, request.target) {
		failure.code = .Invalid_Tool_Plan
		return failure
	}
	_, operation_failure := extension_operation_plan_validate(tool.operation)
	if operation_failure.code != .None || tool.operation.contributor != provider.contributor ||
	   tool.operation.refresh != CONFLICT_ASSISTANCE_TOOL_REFRESH ||
	   tool.operation.verifier.kind != .None {
		failure.code = .Invalid_Tool_Plan
		return failure
	}
	switch tool.access {
	case .Read_Only:
		if tool.operation.effect != .Read_Only do failure.code = .Invalid_Tool_Plan
	case .Worktree_Only:
		if tool.operation.effect != .Repository_Mutating do failure.code = .Invalid_Tool_Plan
	case .Invalid:
		failure.code = .Invalid_Tool_Plan
	}
	return failure
}

/* conflict_assistance_index_fingerprint_compute hashes one complete core-owned index listing. */
conflict_assistance_index_fingerprint_compute :: proc(
	fingerprint: ^Conflict_Assistance_Index_Fingerprint,
	bytes: []u8,
) -> bool {
	if fingerprint == nil do return false
	fingerprint^ = {}
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, bytes)
	sha2.final(&ctx, fingerprint.bytes[:])
	return conflict_assistance_index_fingerprint_is_valid(fingerprint^)
}

/* conflict_assistance_index_fingerprint_is_valid rejects absent index identity. */
conflict_assistance_index_fingerprint_is_valid :: proc(
	fingerprint: Conflict_Assistance_Index_Fingerprint,
) -> bool {
	for byte in fingerprint.bytes {
		if byte != 0 do return true
	}
	return false
}

/* conflict_assistance_tool_admission_validate checks one exact Process submission. */
conflict_assistance_tool_admission_validate :: proc(
	admission: Conflict_Assistance_Tool_Admission,
	tool: Conflict_Assistance_Tool_Plan,
	provider: Conflict_Assistance_Provider,
	selection: Conflict_Assistance_Selection,
	provider_declaration: Contribution_Declaration,
	operation_declaration: Contribution_Declaration,
	current_contributor: Contributor_Handle,
	current_repository: Repository_Context,
	current_repository_generation: Repository_Generation,
) -> Conflict_Assistance_Failure {
	failure := Conflict_Assistance_Failure {
		provider = admission.request.provider.provider,
		request = admission.request.request,
		target = admission.request.target.conflict,
	}
	request_failure := conflict_assistance_request_validate(
		admission.request,
		provider,
		selection,
	)
	if request_failure.code != .None do return request_failure
	provider_failure := conflict_assistance_provider_validate(provider, provider_declaration)
	if provider_failure.code != .None do return provider_failure
	tool_failure := conflict_assistance_tool_plan_validate(tool, admission.request, provider)
	if tool_failure.code != .None do return tool_failure
	if admission.access != tool.access || !conflict_assistance_index_fingerprint_is_valid(
		admission.index_before,
	) {
		failure.code = .Invalid_Tool_Plan
		return failure
	}
	expected_submission := Extension_Operation_Submission {
		request = Extension_Operation_Request_ID(u64(admission.request.request)),
		contributor = provider.contributor,
		contribution = tool.operation.contribution,
		repository = admission.request.target.repository,
		repository_generation = admission.request.target.repository_generation,
	}
	if admission.operation != expected_submission {
		failure.code = .Invalid_Tool_Plan
		return failure
	}
	_, operation_failure := extension_operation_submission_validate(
		admission.operation,
		tool.operation,
		operation_declaration,
		current_contributor,
		current_repository,
		current_repository_generation,
	)
	if operation_failure.code != .None {
		failure.code = conflict_assistance_operation_failure_code(operation_failure.code)
	}
	return failure
}

/* conflict_assistance_tool_result_validate enforces refresh and preserved core authority. */
conflict_assistance_tool_result_validate :: proc(
	result: Conflict_Assistance_Tool_Result,
	admission: Conflict_Assistance_Tool_Admission,
	tool: Conflict_Assistance_Tool_Plan,
	evidence: Conflict_Assistance_Tool_Refresh_Evidence,
) -> Conflict_Assistance_Failure {
	failure := Conflict_Assistance_Failure {
		provider = admission.request.provider.provider,
		request = admission.request.request,
		target = admission.request.target.conflict,
	}
	_, operation_failure := extension_operation_result_validate(
		result.operation,
		admission.operation.request,
		tool.operation,
	)
	if operation_failure.code != .None || result.request != admission.request.request ||
	   result.provider != admission.request.provider ||
	   !conflict_assistance_targets_match(result.target, admission.request.target) {
		failure.code = .Invalid_Response
		return failure
	}
	refresh_completed := conflict_assistance_tool_refresh_is_complete(admission, evidence)
	index_preserved := refresh_completed && evidence.index_after == admission.index_before
	conflict_retained := refresh_completed && evidence.target_present &&
		conflict_assistance_refreshed_target_matches(admission.request.target, evidence.target)
	if result.refresh_completed != refresh_completed ||
	   result.index_preserved != index_preserved ||
	   result.conflict_retained != conflict_retained {
		failure.code = .Invalid_Response
		return failure
	}
	if !refresh_completed {
		failure.code = .Stale_Observation
		return failure
	}
	if !index_preserved {
		failure.code = .Index_Mutation_Prohibited
		return failure
	}
	if !conflict_retained {
		failure.code = .Core_Action_Prohibited
	}
	return failure
}

/* conflict_assistance_tool_refresh_is_complete checks exact post-tool truth. */
conflict_assistance_tool_refresh_is_complete :: proc(
	admission: Conflict_Assistance_Tool_Admission,
	evidence: Conflict_Assistance_Tool_Refresh_Evidence,
) -> bool {
	shape_valid := evidence.target == {}
	if evidence.target_present {
		shape_valid = conflict_assistance_target_is_valid(evidence.target) &&
			evidence.target.repository == evidence.repository &&
			evidence.target.repository_generation == evidence.repository_generation &&
			evidence.target.worktree_generation == evidence.worktree_generation &&
			evidence.target.observation_generation == evidence.observation_generation
	}
	return evidence.repository == admission.request.target.repository &&
		evidence.repository_generation > admission.request.target.repository_generation &&
		evidence.worktree_generation > admission.request.target.worktree_generation &&
		evidence.observation_generation > admission.request.target.observation_generation &&
		evidence.attempted == CONFLICT_ASSISTANCE_TOOL_REFRESH &&
		evidence.completed == CONFLICT_ASSISTANCE_TOOL_REFRESH &&
		evidence.target_checked &&
		conflict_assistance_index_fingerprint_is_valid(evidence.index_after) &&
		shape_valid
}

/* conflict_assistance_response_validate checks one bounded authority-free proposal. */
conflict_assistance_response_validate :: proc(
	response: Conflict_Assistance_Response,
	request: Conflict_Assistance_Request,
	provider: Conflict_Assistance_Provider,
	limits := DEFAULT_CONFLICT_ASSISTANCE_LIMITS,
) -> (usage: Conflict_Assistance_Usage, failure: Conflict_Assistance_Failure) {
	failure = {
		provider = provider.provider,
		request = request.request,
		target = request.target.conflict,
	}
	if !conflict_assistance_limits_are_valid(limits) || response.request != request.request ||
	   response.provider != request.provider ||
	   !conflict_assistance_provider_supports(provider, request.target) {
		failure.code = .Invalid_Response
		return
	}
	if !conflict_assistance_targets_match(response.target, request.target) {
		failure.code = .Stale_Target
		return
	}
	switch response.kind {
	case .Declined:
		if response.guidance.length != 0 || response.tool.operation.plan != Extension_Operation_Plan_ID(0) {
			failure.code = .Invalid_Response
		}
	case .Guidance:
		if .Present_Guidance not_in provider.capabilities ||
		   !conflict_assistance_guidance_is_valid(response.guidance, limits) ||
		   response.tool.operation.plan != Extension_Operation_Plan_ID(0) {
			failure.code = .Invalid_Guidance
			return
		}
		usage.guidance_bytes = u64(response.guidance.length)
	case .Editor:
		if .Open_Editor not_in provider.capabilities || response.guidance.length != 0 ||
		   response.tool.operation.plan != Extension_Operation_Plan_ID(0) {
			failure.code = .Invalid_Response
		}
	case .External_Tool:
		if response.guidance.length != 0 {
			failure.code = .Invalid_Response
			return
		}
		failure = conflict_assistance_tool_plan_validate(response.tool, request, provider)
		if failure.code != .None do return
		usage.external_tools = 1
	case .Invalid:
		failure.code = .Invalid_Response
	}
	usage.copy_bytes = u64(size_of(Conflict_Assistance_Response)) + usage.guidance_bytes
	if failure.code == .None && usage.copy_bytes > limits.copy_bytes {
		failure.code = .Copy_Limit
		failure.limit = limits.copy_bytes
		failure.actual = usage.copy_bytes
	}
	return
}

/* conflict_assistance_usage_within_limits checks exact retained accounting. */
conflict_assistance_usage_within_limits :: proc(
	usage: Conflict_Assistance_Usage,
	limits: Conflict_Assistance_Limits,
) -> bool {
	return conflict_assistance_limits_are_valid(limits) && usage.providers <= limits.providers &&
		usage.guidance_bytes <= limits.guidance_bytes &&
		usage.content_bytes <= limits.content_bytes && usage.copy_bytes <= limits.copy_bytes
}

@(private)
conflict_assistance_classes_are_valid :: proc(classes: Conflict_Assistance_Classes) -> bool {
	return classes != {} && .Invalid not_in classes && classes - ALL_CONFLICT_ASSISTANCE_CLASSES == {}
}

@(private)
conflict_assistance_path_is_valid :: proc(path: Conflict_Assistance_Path) -> bool {
	if path.length == 0 || int(path.length) > len(path.bytes) do return false
	copy_value := path
	value := string(copy_value.bytes[:copy_value.length])
	if !utf8.valid_string(value) do return false
	for byte in transmute([]u8)value {
		if byte == 0 do return false
	}
	return true
}

@(private)
conflict_assistance_provider_reference_is_valid :: proc(
	reference: Conflict_Assistance_Provider_Reference,
) -> bool {
	if reference.provider == Conflict_Assistance_Provider_ID(0) ||
	   reference.generation == Conflict_Assistance_Provider_Generation(0) {
		return false
	}
	if reference.origin == .Built_In_No_Op {
		return reference.contributor == {} &&
			reference.provider == BUILT_IN_CONFLICT_ASSISTANCE_PROVIDER_ID &&
			reference.generation == BUILT_IN_CONFLICT_ASSISTANCE_PROVIDER_GENERATION
	}
	return reference.origin == .Extension && contributor_handle_is_valid(reference.contributor) &&
		reference.provider != BUILT_IN_CONFLICT_ASSISTANCE_PROVIDER_ID
}

@(private)
conflict_assistance_provider_shape_is_valid :: proc(
	provider: Conflict_Assistance_Provider,
) -> bool {
	if provider.origin == .Built_In_No_Op {
		return provider == conflict_assistance_builtin_no_op_provider()
	}
	return provider.origin == .Extension && contributor_handle_is_valid(provider.contributor) &&
		provider.contribution != Contribution_ID(0) &&
		provider.provider != Conflict_Assistance_Provider_ID(0) &&
		provider.provider != BUILT_IN_CONFLICT_ASSISTANCE_PROVIDER_ID &&
		provider.generation != Conflict_Assistance_Provider_Generation(0) &&
		extension_identity_is_valid(provider.identity) && extension_label_is_valid(provider.label) &&
		conflict_assistance_classes_are_valid(provider.supported_classes) &&
		provider.capabilities != {} && provider.lifecycle != .Invalid
}

@(private)
conflict_assistance_side_is_valid :: proc(
	side: Conflict_Assistance_Side,
	expected: Conflict_Assistance_Side_Kind,
	content: []u8,
) -> bool {
	if side.kind != expected || side.material == .Invalid do return false
	if side.material == .Missing {
		return side.mode == 0 && side.object == {} && side.content == {} && !side.truncated
	}
	if side.mode == 0 do return false
	if side.kind == .Worktree {
		if side.object != {} do return false
	} else if !revision_identity_is_valid(side.object) {
		return false
	}
	end := u64(side.content.offset) + u64(side.content.length)
	if end > u64(len(content)) do return false
	if side.material == .Omitted {
		return side.content.length == 0 && side.truncated
	}
	if side.truncated && side.content.length == 0 do return false
	if side.material == .Text {
		copy_content := content
		return utf8.valid_string(string(copy_content[side.content.offset:end]))
	}
	return side.material == .Binary || side.material == .Submodule
}

@(private)
conflict_assistance_guidance_is_valid :: proc(
	guidance: Conflict_Assistance_Guidance,
	limits: Conflict_Assistance_Limits,
) -> bool {
	if guidance.length == 0 || u64(guidance.length) > limits.guidance_bytes ||
	   int(guidance.length) > len(guidance.bytes) {
		return false
	}
	copy_value := guidance
	value := string(copy_value.bytes[:copy_value.length])
	if !utf8.valid_string(value) do return false
	for byte in transmute([]u8)value {
		if byte == 0 do return false
	}
	return true
}

@(private)
conflict_assistance_refreshed_target_matches :: proc(
	before, after: Conflict_Assistance_Target,
) -> bool {
	return conflict_assistance_target_is_valid(before) &&
		conflict_assistance_target_is_valid(after) &&
		after.repository == before.repository &&
		after.repository_generation > before.repository_generation &&
		after.worktree_generation > before.worktree_generation &&
		after.observation_generation > before.observation_generation &&
		after.conflict == before.conflict && after.path == before.path
}

@(private)
conflict_assistance_operation_failure_code :: proc(
	code: Extension_Operation_Failure_Code,
) -> Conflict_Assistance_Failure_Code {
	switch code {
	case .None:
		return .None
	case .Stale_Contributor:
		return .Stale_Contributor
	case .Stale_Repository:
		return .Stale_Repository
	case .Executable_Unavailable, .Process_Start:
		return .Tool_Unavailable
	case .Allocation:
		return .Allocation
	case .Invalid_Plan, .Invalid_Executable, .Invalid_Argument, .Invalid_Effect,
	     .Invalid_Refresh, .Invalid_Verifier, .Invalid_Environment,
	     .Invalid_Diagnostic_Policy, .Invalid_Process_Limits, .Invalid_Result,
	     .Stale_Plan, .Argument_Limit, .Argument_Bytes_Limit, .Output_Limit,
	     .Diagnostic_Limit, .Deadline_Limit, .Copy_Limit, .Contribution_Unavailable:
		return .Invalid_Tool_Plan
	}
	return .Invalid_Tool_Plan
}
