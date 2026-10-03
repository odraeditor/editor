// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "base:runtime"

/* MAX_ROLE_PROVIDERS bounds all built-in and package providers in one session. */
MAX_ROLE_PROVIDERS :: 64
/* MAX_ROLE_PROVIDER_NAME_BYTES bounds one copied provider name. */
MAX_ROLE_PROVIDER_NAME_BYTES :: 96
/* MAX_ROLE_PACKAGE_NAME_BYTES bounds one copied package identity. */
MAX_ROLE_PACKAGE_NAME_BYTES :: 256
/* MAX_ROLE_COMMAND_NAME_BYTES bounds one copied admitted command. */
MAX_ROLE_COMMAND_NAME_BYTES :: 96
/* MAX_ROLE_PROPOSAL_BYTES bounds one copied package-owned proposal. */
MAX_ROLE_PROPOSAL_BYTES :: MAX_SNAPSHOT_BYTES
/* MAX_ROLE_CALLBACKS_PER_TURN bounds admitted provider callbacks in one turn. */
MAX_ROLE_CALLBACKS_PER_TURN :: 256
/* INITIAL_ROLE_COUNT is the accepted current visible-consumer role set. */
INITIAL_ROLE_COUNT :: 7

/* Role identifies one accepted current visible-consumer replacement boundary. */
Role :: enum u8 {
	Invalid,
	Startup,
	Buffer_Menu,
	Candidate_Navigation,
	Project_Inventory,
	Keymap_Inspection,
	Transient_Input,
	Status,
}

/* Role_Provider_Kind distinguishes native fallbacks from package providers. */
Role_Provider_Kind :: enum u8 {
	Invalid,
	Built_In,
	Package,
}

/* Role_Provider_State is the checked lifecycle state of one provider. */
Role_Provider_State :: enum u8 {
	Invalid,
	Registered,
	Confirmed,
	Rejected,
	Failed,
	Closed,
}

/* Role_Registry_Operation identifies one rejected registry action. */
Role_Registry_Operation :: enum u8 {
	Invalid,
	Initialize,
	Inspect,
	Register,
	Fallback,
	Propose,
	Activate,
	Replace,
	Rollback,
	Fail,
	Teardown,
}

/* Role_Failure_Code classifies expected role registry rejection. */
Role_Failure_Code :: enum u16 {
	None,
	Invalid_Registry,
	Closed_Registry,
	Invalid_Session,
	Invalid_Role,
	Invalid_Provider,
	Stale_Provider,
	Provider_Limit,
	Provider_Name_Limit,
	Package_Name_Limit,
	Duplicate_Provider,
	Stale_Scope,
	Provider_Not_Package,
	Provider_Not_Registered,
	Provider_Not_Confirmed,
	Provider_Not_Active,
	Renderer_Incompatible,
	Stale_Root,
	Proposal_Limit,
	Callback_Budget,
	Focus_Effect,
	Layout_Effect,
	Command_Name_Limit,
	Command_Not_Admitted,
	Generation_Limit,
	Allocation,
}

/* Role_Session_ID identifies one editor session; zero is invalid. */
Role_Session_ID :: distinct u64
/* Role_Session_Generation identifies one exact editor session lifetime. */
Role_Session_Generation :: distinct u64
/* Role_Registry_Generation identifies one exact provider selection snapshot. */
Role_Registry_Generation :: distinct u64
/* Role_Provider_ID identifies one provider for the session lifetime. */
Role_Provider_ID :: distinct u64
/* Role_Provider_Generation identifies one exact provider lifecycle state. */
Role_Provider_Generation :: distinct u64

/* Role_Provider_Handle is one checked pointer-free provider identity. */
Role_Provider_Handle :: struct {
	session_id:         Role_Session_ID,
	session_generation: Role_Session_Generation,
	role:               Role,
	provider_id:        Role_Provider_ID,
	provider_generation: Role_Provider_Generation,
}

/* Role_Scope observes one exact active provider and confirmed fallback. */
Role_Scope :: struct {
	session_id:         Role_Session_ID,
	session_generation: Role_Session_Generation,
	registry_generation: Role_Registry_Generation,
	role:               Role,
	active:             Role_Provider_Handle,
	fallback:           Role_Provider_Handle,
}

/* Role_Provider_View borrows copied provider text until the next registry mutation. */
Role_Provider_View :: struct {
	handle:             Role_Provider_Handle,
	kind:               Role_Provider_Kind,
	state:              Role_Provider_State,
	name:               string,
	package_name:       string,
	required_capabilities: Renderer_Capabilities,
	confirmed_root:     Root_Generation,
	proposal_bytes:     u64,
	callback_budget:    u16,
	command_name:       string,
}

/* Role_Provider_Proposal is one complete checked package activation request. */
Role_Provider_Proposal :: struct {
	expected_scope:       Role_Scope,
	provider:             Role_Provider_Handle,
	expected_root:        Root_Handle,
	renderer:             Renderer_Profile,
	proposal_bytes:       u64,
	callback_budget:      u16,
	changes_focus:        bool,
	changes_layout:       bool,
	command_name:         string,
}

/* Role_Activation_Outcome copies the exact previous and selected providers. */
Role_Activation_Outcome :: struct {
	scope:              Role_Scope,
	previous:           Role_Provider_Handle,
	provider:           Role_Provider_Handle,
	confirmed_root:     Root_Generation,
	changed:            bool,
	fallback_selected:  bool,
}

/* Role_Registry_Stats reports exact session generations and occupancy. */
Role_Registry_Stats :: struct {
	session_id:          Role_Session_ID,
	session_generation:  Role_Session_Generation,
	registry_generation: Role_Registry_Generation,
	live_providers:      u16,
	package_providers:   u16,
}

/* Role_Failure reports one rejected role registry operation. */
Role_Failure :: struct {
	operation: Role_Registry_Operation,
	code:      Role_Failure_Code,
	role:      Role,
	provider:  Role_Provider_Handle,
	limit:     u64,
	actual:    u64,
}

/* Role_Registry owns one session-scoped provider selection registry. */
Role_Registry :: struct {
	state:  rawptr,
	closed: bool,
}

@(private)
Role_Provider_Slot :: struct {
	handle:                Role_Provider_Handle,
	kind:                  Role_Provider_Kind,
	state:                 Role_Provider_State,
	required_capabilities: Renderer_Capabilities,
	confirmed_root:        Root_Generation,
	proposal_bytes:        u64,
	callback_budget:       u16,
	command_name_bytes:    u16,
	command_name:          [MAX_ROLE_COMMAND_NAME_BYTES]u8,
	name_bytes:            u16,
	package_bytes:         u16,
	name:                  [MAX_ROLE_PROVIDER_NAME_BYTES]u8,
	package_name:          [MAX_ROLE_PACKAGE_NAME_BYTES]u8,
	live:                  bool,
}

@(private)
Role_Selection :: struct {
	active:   Role_Provider_Handle,
	fallback: Role_Provider_Handle,
}

@(private)
Role_Registry_State :: struct {
	session_id:          Role_Session_ID,
	session_generation:  Role_Session_Generation,
	registry_generation: Role_Registry_Generation,
	next_provider_id:    Role_Provider_ID,
	live_count:          u16,
	package_count:       u16,
	providers:           [MAX_ROLE_PROVIDERS]Role_Provider_Slot,
	selections:          [INITIAL_ROLE_COUNT]Role_Selection,
	allocator:           runtime.Allocator,
}

/* role_registry_init creates seven confirmed built-in providers for one session. */
role_registry_init :: proc(
	registry: ^Role_Registry,
	session_id: Role_Session_ID,
	session_generation: Role_Session_Generation,
	allocator := context.allocator,
) -> (ok: bool, failure: Role_Failure) {
	if registry == nil {
		return false, role_failure(.Initialize, .Invalid_Registry)
	}
	registry^ = {}
	if session_id == Role_Session_ID(0) ||
	   session_generation == Role_Session_Generation(0) {
		return false, role_failure(.Initialize, .Invalid_Session)
	}
	if allocator.procedure == nil {
		return false, role_failure(.Initialize, .Allocation)
	}
	state, allocation_error := new(Role_Registry_State, allocator)
	if allocation_error != nil {
		return false, role_failure(.Initialize, .Allocation)
	}
	state^ = Role_Registry_State {
		session_id = session_id,
		session_generation = session_generation,
		registry_generation = 1,
		next_provider_id = 1,
		allocator = allocator,
	}
	for role_value in 1..=INITIAL_ROLE_COUNT {
		role := Role(role_value)
		handle, registered := role_register_builtin(state, role, role_builtin_name(role))
		if !registered {
			free(state, allocator)
			return false, role_failure(.Initialize, .Invalid_Role, role)
		}
		state.selections[role_value - 1] = Role_Selection {
			active = handle,
			fallback = handle,
		}
	}
	registry.state = state
	return true, {}
}

/* role_registry_close releases all provider storage and invalidates the session. */
role_registry_close :: proc(registry: ^Role_Registry) -> (ok: bool, failure: Role_Failure) {
	state := role_registry_state(registry)
	if state == nil {
		return false, role_failure(.Teardown, .Invalid_Registry)
	}
	for &slot in state.providers {
		if slot.live {
			slot = {}
		}
	}
	allocator := state.allocator
	free(state, allocator)
	registry^ = Role_Registry{closed = true}
	return true, {}
}

/* role_registry_scope copies the active and built-in fallback generations. */
role_registry_scope :: proc(
	registry: ^Role_Registry,
	role: Role,
) -> (scope: Role_Scope, ok: bool, failure: Role_Failure) {
	state := role_registry_state(registry)
	if state == nil {
		return {}, false, role_failure(.Inspect, .Invalid_Registry, role)
	}
	if !role_is_valid(role) {
		return {}, false, role_failure(.Inspect, .Invalid_Role, role)
	}
	selection := state.selections[role_index(role)]
	return Role_Scope {
		session_id = state.session_id,
		session_generation = state.session_generation,
		registry_generation = state.registry_generation,
		role = role,
		active = selection.active,
		fallback = selection.fallback,
	}, true, {}
}

/* role_registry_provider borrows one exact copied provider descriptor. */
role_registry_provider :: proc(
	registry: ^Role_Registry,
	handle: Role_Provider_Handle,
) -> (provider: Role_Provider_View, ok: bool, failure: Role_Failure) {
	state := role_registry_state(registry)
	if state == nil {
		return {}, false, role_failure(.Inspect, .Invalid_Registry, handle.role, handle)
	}
	slot, resolve_failure := role_provider_resolve(state, handle)
	if resolve_failure.code != .None {
		return {}, false, resolve_failure
	}
	return role_provider_view(slot), true, {}
}

/* role_registry_provider_by_id borrows one provider from a checked role identity. */
role_registry_provider_by_id :: proc(
	registry: ^Role_Registry,
	role: Role,
	provider_id: Role_Provider_ID,
) -> (provider: Role_Provider_View, ok: bool, failure: Role_Failure) {
	state := role_registry_state(registry)
	if state == nil {
		return {}, false, role_failure(.Inspect, .Invalid_Registry, role)
	}
	if !role_is_valid(role) || provider_id == Role_Provider_ID(0) {
		return {}, false, role_failure(.Inspect, .Invalid_Provider, role)
	}
	for &slot in state.providers {
		if slot.live && slot.handle.role == role && slot.handle.provider_id == provider_id {
			return role_provider_view(&slot), true, {}
		}
	}
	return {}, false, role_failure(.Inspect, .Stale_Provider, role)
}

/* role_registry_register_package copies one inactive package provider. */
role_registry_register_package :: proc(
	registry: ^Role_Registry,
	role: Role,
	name, package_name: string,
	required_capabilities: Renderer_Capabilities,
) -> (provider: Role_Provider_Handle, ok: bool, failure: Role_Failure) {
	state := role_registry_state(registry)
	if state == nil {
		return {}, false, role_failure(.Register, .Invalid_Registry, role)
	}
	if !role_is_valid(role) {
		return {}, false, role_failure(.Register, .Invalid_Role, role)
	}
	if len(name) == 0 || len(name) > MAX_ROLE_PROVIDER_NAME_BYTES {
		failure = role_failure(.Register, .Provider_Name_Limit, role)
		failure.limit = MAX_ROLE_PROVIDER_NAME_BYTES
		failure.actual = u64(len(name))
		return {}, false, failure
	}
	if len(package_name) == 0 || len(package_name) > MAX_ROLE_PACKAGE_NAME_BYTES {
		failure = role_failure(.Register, .Package_Name_Limit, role)
		failure.limit = MAX_ROLE_PACKAGE_NAME_BYTES
		failure.actual = u64(len(package_name))
		return {}, false, failure
	}
	for &slot in state.providers {
		if slot.live && slot.handle.role == role &&
		   role_slot_name(&slot) == name && role_slot_package(&slot) == package_name {
			return {}, false, role_failure(.Register, .Duplicate_Provider, role, slot.handle)
		}
	}
	if state.live_count >= MAX_ROLE_PROVIDERS {
		failure = role_failure(.Register, .Provider_Limit, role)
		failure.limit = MAX_ROLE_PROVIDERS
		failure.actual = u64(state.live_count) + 1
		return {}, false, failure
	}
	if state.next_provider_id == Role_Provider_ID(0) ||
	   state.registry_generation == Role_Registry_Generation(max(u64)) {
		return {}, false, role_failure(.Register, .Generation_Limit, role)
	}
	for &slot in state.providers {
		if slot.live {
			continue
		}
		provider = Role_Provider_Handle {
			session_id = state.session_id,
			session_generation = state.session_generation,
			role = role,
			provider_id = state.next_provider_id,
			provider_generation = 1,
		}
		state.next_provider_id += 1
		slot.handle = provider
		slot.kind = .Package
		slot.state = .Registered
		slot.required_capabilities = required_capabilities
		slot.name_bytes = u16(copy(slot.name[:], transmute([]u8)name))
		slot.package_bytes = u16(copy(slot.package_name[:], transmute([]u8)package_name))
		slot.live = true
		state.live_count += 1
		state.package_count += 1
		state.registry_generation += 1
		return provider, true, {}
	}
	return {}, false, role_failure(.Register, .Provider_Limit, role)
}

/* role_registry_select_fallback restores the confirmed built-in provider. */
role_registry_select_fallback :: proc(
	registry: ^Role_Registry,
	role: Role,
) -> (scope: Role_Scope, changed: bool, failure: Role_Failure) {
	state := role_registry_state(registry)
	if state == nil {
		return {}, false, role_failure(.Fallback, .Invalid_Registry, role)
	}
	if !role_is_valid(role) {
		return {}, false, role_failure(.Fallback, .Invalid_Role, role)
	}
	selection := &state.selections[role_index(role)]
	if selection.active != selection.fallback {
		if state.registry_generation == Role_Registry_Generation(max(u64)) {
			return {}, false, role_failure(.Fallback, .Generation_Limit, role)
		}
		selection.active = selection.fallback
		state.registry_generation += 1
		changed = true
	}
	current_scope, ok, scope_failure := role_registry_scope(registry, role)
	if !ok {
		return {}, false, scope_failure
	}
	return current_scope, changed, {}
}

/* role_registry_confirm_package validates a complete proposal before confirmation. */
role_registry_confirm_package :: proc(
	registry: ^Role_Registry,
	ui_registry: ^Registry,
	proposal: Role_Provider_Proposal,
) -> (provider: Role_Provider_Handle, ok: bool, failure: Role_Failure) {
	state := role_registry_state(registry)
	if state == nil {
		return {}, false, role_failure(.Propose, .Invalid_Registry, proposal.provider.role)
	}
	slot, validated, validation_failure := role_validate_package_proposal(
		state,
		ui_registry,
		proposal,
		.Registered,
		.Propose,
	)
	if !validated {
		return {}, false, validation_failure
	}
	if slot.handle.provider_generation == Role_Provider_Generation(max(u64)) ||
	   state.registry_generation == Role_Registry_Generation(max(u64)) {
		return {}, false, role_failure(.Propose, .Generation_Limit, proposal.provider.role)
	}
	slot.handle.provider_generation += 1
	slot.state = .Confirmed
	slot.confirmed_root = proposal.expected_root.generation
	slot.proposal_bytes = proposal.proposal_bytes
	slot.callback_budget = proposal.callback_budget
	slot.command_name_bytes = u16(copy(
		slot.command_name[:],
		transmute([]u8)proposal.command_name,
	))
	state.registry_generation += 1
	return slot.handle, true, {}
}

/* role_registry_activate_package atomically selects one confirmed generation. */
role_registry_activate_package :: proc(
	registry: ^Role_Registry,
	ui_registry: ^Registry,
	expected_scope: Role_Scope,
	provider: Role_Provider_Handle,
	renderer: Renderer_Profile,
) -> (outcome: Role_Activation_Outcome, ok: bool, failure: Role_Failure) {
	state := role_registry_state(registry)
	if state == nil {
		return {}, false, role_failure(.Activate, .Invalid_Registry, provider.role, provider)
	}
	if !role_scope_matches(state, expected_scope) {
		return {}, false, role_failure(.Activate, .Stale_Scope, provider.role, provider)
	}
	slot, resolve_failure := role_provider_resolve(state, provider)
	if resolve_failure.code != .None {
		resolve_failure.operation = .Activate
		return {}, false, resolve_failure
	}
	if slot.kind != .Package {
		return {}, false, role_failure(.Activate, .Provider_Not_Package, provider.role, provider)
	}
	if slot.state != .Confirmed {
		return {}, false, role_failure(.Activate, .Provider_Not_Confirmed, provider.role, provider)
	}
	root, root_ok, _ := registry_handle(ui_registry)
	if !root_ok || root.generation != slot.confirmed_root {
		return {}, false, role_failure(.Activate, .Stale_Root, provider.role, provider)
	}
	if !renderer_profile_is_valid(renderer) ||
	   !role_renderer_supports(renderer, slot.required_capabilities) {
		return {}, false, role_failure(.Activate, .Renderer_Incompatible, provider.role, provider)
	}
	selection := &state.selections[role_index(provider.role)]
	previous := selection.active
	if previous != provider {
		if state.registry_generation == Role_Registry_Generation(max(u64)) {
			return {}, false, role_failure(.Activate, .Generation_Limit, provider.role, provider)
		}
		selection.active = provider
		state.registry_generation += 1
	}
	scope, scoped, scope_failure := role_registry_scope(registry, provider.role)
	if !scoped {
		return {}, false, scope_failure
	}
	return Role_Activation_Outcome {
		scope = scope,
		previous = previous,
		provider = provider,
		confirmed_root = slot.confirmed_root,
		changed = previous != provider,
	}, true, {}
}

/* role_registry_replace_package validates and selects one provider in one mutation. */
role_registry_replace_package :: proc(
	registry: ^Role_Registry,
	ui_registry: ^Registry,
	proposal: Role_Provider_Proposal,
) -> (outcome: Role_Activation_Outcome, ok: bool, failure: Role_Failure) {
	state := role_registry_state(registry)
	if state == nil {
		return {}, false, role_failure(.Replace, .Invalid_Registry, proposal.provider.role)
	}
	slot, validated, validation_failure := role_validate_package_proposal(
		state,
		ui_registry,
		proposal,
		.Confirmed,
		.Replace,
	)
	if !validated {
		return {}, false, validation_failure
	}
	if slot.handle.provider_generation == Role_Provider_Generation(max(u64)) ||
	   state.registry_generation == Role_Registry_Generation(max(u64)) {
		return {}, false, role_failure(.Replace, .Generation_Limit, proposal.provider.role)
	}
	selection := &state.selections[role_index(proposal.provider.role)]
	previous := selection.active
	slot.handle.provider_generation += 1
	slot.state = .Confirmed
	slot.confirmed_root = proposal.expected_root.generation
	slot.proposal_bytes = proposal.proposal_bytes
	slot.callback_budget = proposal.callback_budget
	slot.command_name_bytes = u16(copy(
		slot.command_name[:],
		transmute([]u8)proposal.command_name,
	))
	selection.active = slot.handle
	state.registry_generation += 1
	scope, scoped, scope_failure := role_registry_scope(registry, proposal.provider.role)
	if !scoped {
		return {}, false, scope_failure
	}
	return Role_Activation_Outcome {
		scope = scope,
		previous = previous,
		provider = slot.handle,
		confirmed_root = slot.confirmed_root,
		changed = previous != slot.handle,
	}, true, {}
}

/* role_registry_command_is_admitted checks one active provider-owned command. */
role_registry_command_is_admitted :: proc(
	registry: ^Role_Registry,
	provider: Role_Provider_Handle,
	command_name: string,
) -> (ok: bool, failure: Role_Failure) {
	state := role_registry_state(registry)
	if state == nil {
		return false, role_failure(.Inspect, .Invalid_Registry, provider.role, provider)
	}
	slot, resolve_failure := role_provider_resolve(state, provider)
	if resolve_failure.code != .None {
		return false, resolve_failure
	}
	selection := state.selections[role_index(provider.role)]
	if selection.active != provider {
		return false, role_failure(.Inspect, .Provider_Not_Active, provider.role, provider)
	}
	if len(command_name) == 0 || command_name != role_slot_command(slot) {
		return false, role_failure(.Inspect, .Command_Not_Admitted, provider.role, provider)
	}
	return true, {}
}

/* role_registry_rollback selects the built-in fallback for one exact scope. */
role_registry_rollback :: proc(
	registry: ^Role_Registry,
	expected_scope: Role_Scope,
) -> (outcome: Role_Activation_Outcome, ok: bool, failure: Role_Failure) {
	state := role_registry_state(registry)
	if state == nil {
		return {}, false, role_failure(.Rollback, .Invalid_Registry, expected_scope.role)
	}
	if !role_scope_matches(state, expected_scope) {
		return {}, false, role_failure(.Rollback, .Stale_Scope, expected_scope.role)
	}
	selection := &state.selections[role_index(expected_scope.role)]
	previous := selection.active
	scope, changed, fallback_failure := role_registry_select_fallback(registry, expected_scope.role)
	if fallback_failure.code != .None {
		fallback_failure.operation = .Rollback
		return {}, false, fallback_failure
	}
	return Role_Activation_Outcome {
		scope = scope,
		previous = previous,
		provider = scope.active,
		confirmed_root = Root_Generation(0),
		changed = changed,
		fallback_selected = true,
	}, true, {}
}

/* role_registry_teardown_package closes one provider and restores fallback if active. */
role_registry_teardown_package :: proc(
	registry: ^Role_Registry,
	expected_scope: Role_Scope,
	provider: Role_Provider_Handle,
) -> (outcome: Role_Activation_Outcome, ok: bool, failure: Role_Failure) {
	state := role_registry_state(registry)
	if state == nil {
		return {}, false, role_failure(.Teardown, .Invalid_Registry, provider.role, provider)
	}
	if !role_scope_matches(state, expected_scope) {
		return {}, false, role_failure(.Teardown, .Stale_Scope, provider.role, provider)
	}
	slot, resolve_failure := role_provider_resolve(state, provider)
	if resolve_failure.code != .None {
		resolve_failure.operation = .Teardown
		return {}, false, resolve_failure
	}
	if slot.kind != .Package {
		return {}, false, role_failure(.Teardown, .Provider_Not_Package, provider.role, provider)
	}
	if state.registry_generation == Role_Registry_Generation(max(u64)) {
		return {}, false, role_failure(.Teardown, .Generation_Limit, provider.role, provider)
	}
	selection := &state.selections[role_index(provider.role)]
	previous := selection.active
	fallback_selected := previous == provider
	if fallback_selected {
		selection.active = selection.fallback
	}
	slot^ = {}
	assert(state.live_count > 0 && state.package_count > 0)
	state.live_count -= 1
	state.package_count -= 1
	state.registry_generation += 1
	scope, scoped, scope_failure := role_registry_scope(registry, provider.role)
	if !scoped {
		return {}, false, scope_failure
	}
	return Role_Activation_Outcome {
		scope = scope,
		previous = previous,
		provider = scope.active,
		changed = fallback_selected,
		fallback_selected = fallback_selected,
	}, true, {}
}

/* role_registry_fail_package contains failure and restores the confirmed fallback. */
role_registry_fail_package :: proc(
	registry: ^Role_Registry,
	expected_scope: Role_Scope,
	provider: Role_Provider_Handle,
) -> (outcome: Role_Activation_Outcome, ok: bool, failure: Role_Failure) {
	state := role_registry_state(registry)
	if state == nil {
		return {}, false, role_failure(.Fail, .Invalid_Registry, provider.role, provider)
	}
	if !role_scope_matches(state, expected_scope) {
		return {}, false, role_failure(.Fail, .Stale_Scope, provider.role, provider)
	}
	slot, resolve_failure := role_provider_resolve(state, provider)
	if resolve_failure.code != .None {
		resolve_failure.operation = .Fail
		return {}, false, resolve_failure
	}
	if slot.kind != .Package {
		return {}, false, role_failure(.Fail, .Provider_Not_Package, provider.role, provider)
	}
	if slot.handle.provider_generation == Role_Provider_Generation(max(u64)) ||
	   state.registry_generation == Role_Registry_Generation(max(u64)) {
		return {}, false, role_failure(.Fail, .Generation_Limit, provider.role, provider)
	}
	selection := &state.selections[role_index(provider.role)]
	previous := selection.active
	slot.handle.provider_generation += 1
	slot.state = .Failed
	if previous.provider_id == provider.provider_id {
		selection.active = selection.fallback
	}
	state.registry_generation += 1
	scope, scoped, scope_failure := role_registry_scope(registry, provider.role)
	if !scoped {
		return {}, false, scope_failure
	}
	return Role_Activation_Outcome {
		scope = scope,
		previous = previous,
		provider = scope.active,
		changed = previous != scope.active,
		fallback_selected = true,
	}, true, {}
}

/* role_registry_stats copies exact session provider accounting. */
role_registry_stats :: proc(
	registry: ^Role_Registry,
) -> (stats: Role_Registry_Stats, ok: bool, failure: Role_Failure) {
	state := role_registry_state(registry)
	if state == nil {
		return {}, false, role_failure(.Inspect, .Invalid_Registry)
	}
	return Role_Registry_Stats {
		session_id = state.session_id,
		session_generation = state.session_generation,
		registry_generation = state.registry_generation,
		live_providers = state.live_count,
		package_providers = state.package_count,
	}, true, {}
}

@(private)
role_register_builtin :: proc(
	state: ^Role_Registry_State,
	role: Role,
	name: string,
) -> (handle: Role_Provider_Handle, ok: bool) {
	if state == nil || !role_is_valid(role) || state.live_count >= MAX_ROLE_PROVIDERS {
		return {}, false
	}
	for &slot in state.providers {
		if slot.live {
			continue
		}
		handle = Role_Provider_Handle {
			session_id = state.session_id,
			session_generation = state.session_generation,
			role = role,
			provider_id = state.next_provider_id,
			provider_generation = 1,
		}
		state.next_provider_id += 1
		slot.handle = handle
		slot.kind = .Built_In
		slot.state = .Confirmed
		slot.name_bytes = u16(copy(slot.name[:], transmute([]u8)name))
		slot.package_bytes = u16(copy(slot.package_name[:], "odra"))
		slot.live = true
		state.live_count += 1
		return handle, true
	}
	return {}, false
}

@(private)
role_provider_resolve :: proc(
	state: ^Role_Registry_State,
	handle: Role_Provider_Handle,
) -> (slot: ^Role_Provider_Slot, failure: Role_Failure) {
	if state == nil {
		return nil, role_failure(.Inspect, .Invalid_Registry, handle.role, handle)
	}
	if handle.session_id != state.session_id ||
	   handle.session_generation != state.session_generation {
		return nil, role_failure(.Inspect, .Invalid_Session, handle.role, handle)
	}
	if !role_is_valid(handle.role) || handle.provider_id == Role_Provider_ID(0) ||
	   handle.provider_generation == Role_Provider_Generation(0) {
		return nil, role_failure(.Inspect, .Invalid_Provider, handle.role, handle)
	}
	for &candidate in state.providers {
		if candidate.live && candidate.handle.provider_id == handle.provider_id {
			if candidate.handle != handle {
				return nil, role_failure(.Inspect, .Stale_Provider, handle.role, handle)
			}
			return &candidate, {}
		}
	}
	return nil, role_failure(.Inspect, .Stale_Provider, handle.role, handle)
}

@(private)
role_provider_view :: proc(slot: ^Role_Provider_Slot) -> Role_Provider_View {
	assert(slot != nil && slot.live)
	return Role_Provider_View {
		handle = slot.handle,
		kind = slot.kind,
		state = slot.state,
		name = role_slot_name(slot),
		package_name = role_slot_package(slot),
		required_capabilities = slot.required_capabilities,
		confirmed_root = slot.confirmed_root,
		proposal_bytes = slot.proposal_bytes,
		callback_budget = slot.callback_budget,
		command_name = role_slot_command(slot),
	}
}

@(private)
role_validate_package_proposal :: proc(
	state: ^Role_Registry_State,
	ui_registry: ^Registry,
	proposal: Role_Provider_Proposal,
	expected_state: Role_Provider_State,
	operation: Role_Registry_Operation,
) -> (slot: ^Role_Provider_Slot, ok: bool, failure: Role_Failure) {
	if !role_scope_matches(state, proposal.expected_scope) {
		return nil, false, role_failure(
			operation,
			.Stale_Scope,
			proposal.provider.role,
			proposal.provider,
		)
	}
	resolved_slot, resolve_failure := role_provider_resolve(state, proposal.provider)
	if resolve_failure.code != .None {
		resolve_failure.operation = operation
		return nil, false, resolve_failure
	}
	if resolved_slot.kind != .Package {
		return nil, false, role_failure(
			operation,
			.Provider_Not_Package,
			proposal.provider.role,
			proposal.provider,
		)
	}
	if resolved_slot.state != expected_state {
		return nil, false, role_failure(
			operation,
			.Provider_Not_Registered,
			proposal.provider.role,
			proposal.provider,
		)
	}
	root, root_ok, _ := registry_handle(ui_registry)
	if !root_ok || root != proposal.expected_root {
		return nil, false, role_failure(
			operation,
			.Stale_Root,
			proposal.provider.role,
			proposal.provider,
		)
	}
	if !renderer_profile_is_valid(proposal.renderer) ||
	   !role_renderer_supports(proposal.renderer, resolved_slot.required_capabilities) {
		return nil, false, role_failure(
			operation,
			.Renderer_Incompatible,
			proposal.provider.role,
			proposal.provider,
		)
	}
	if proposal.proposal_bytes == 0 || proposal.proposal_bytes > MAX_ROLE_PROPOSAL_BYTES {
		failure = role_failure(
			operation,
			.Proposal_Limit,
			proposal.provider.role,
			proposal.provider,
		)
		failure.limit = MAX_ROLE_PROPOSAL_BYTES
		failure.actual = proposal.proposal_bytes
		return nil, false, failure
	}
	if proposal.callback_budget == 0 ||
	   proposal.callback_budget > MAX_ROLE_CALLBACKS_PER_TURN {
		failure = role_failure(
			operation,
			.Callback_Budget,
			proposal.provider.role,
			proposal.provider,
		)
		failure.limit = MAX_ROLE_CALLBACKS_PER_TURN
		failure.actual = u64(proposal.callback_budget)
		return nil, false, failure
	}
	if proposal.changes_focus {
		return nil, false, role_failure(
			operation,
			.Focus_Effect,
			proposal.provider.role,
			proposal.provider,
		)
	}
	if proposal.changes_layout {
		return nil, false, role_failure(
			operation,
			.Layout_Effect,
			proposal.provider.role,
			proposal.provider,
		)
	}
	if len(proposal.command_name) > MAX_ROLE_COMMAND_NAME_BYTES {
		failure = role_failure(
			operation,
			.Command_Name_Limit,
			proposal.provider.role,
			proposal.provider,
		)
		failure.limit = MAX_ROLE_COMMAND_NAME_BYTES
		failure.actual = u64(len(proposal.command_name))
		return nil, false, failure
	}
	return resolved_slot, true, {}
}

@(private)
role_scope_matches :: proc(state: ^Role_Registry_State, expected: Role_Scope) -> bool {
	if state == nil || !role_is_valid(expected.role) {
		return false
	}
	selection := state.selections[role_index(expected.role)]
	return expected.session_id == state.session_id &&
	       expected.session_generation == state.session_generation &&
	       expected.registry_generation == state.registry_generation &&
	       expected.active == selection.active && expected.fallback == selection.fallback
}

@(private)
role_renderer_supports :: proc(
	renderer: Renderer_Profile,
	required: Renderer_Capabilities,
) -> bool {
	return required & renderer.capabilities == required
}

@(private)
role_slot_name :: proc(slot: ^Role_Provider_Slot) -> string {
	return string(slot.name[:slot.name_bytes])
}

@(private)
role_slot_package :: proc(slot: ^Role_Provider_Slot) -> string {
	return string(slot.package_name[:slot.package_bytes])
}

@(private)
role_slot_command :: proc(slot: ^Role_Provider_Slot) -> string {
	return string(slot.command_name[:slot.command_name_bytes])
}

@(private)
role_registry_state :: proc(registry: ^Role_Registry) -> ^Role_Registry_State {
	if registry == nil || registry.state == nil || registry.closed {
		return nil
	}
	return cast(^Role_Registry_State)registry.state
}

@(private)
role_is_valid :: proc(role: Role) -> bool {
	return role >= .Startup && role <= .Status
}

@(private)
role_index :: proc(role: Role) -> int {
	assert(role_is_valid(role))
	return int(role) - 1
}

@(private)
role_builtin_name :: proc(role: Role) -> string {
	switch role {
	case .Startup:
		return "built-in startup UI"
	case .Buffer_Menu:
		return "built-in Buffer Menu UI"
	case .Candidate_Navigation:
		return "built-in candidate navigation UI"
	case .Project_Inventory:
		return "built-in Project inventory UI"
	case .Keymap_Inspection:
		return "built-in keymap inspection UI"
	case .Transient_Input:
		return "built-in transient input UI"
	case .Status:
		return "built-in status UI"
	case .Invalid:
		return ""
	}
	return ""
}

@(private)
role_failure :: proc(
	operation: Role_Registry_Operation,
	code: Role_Failure_Code,
	role: Role = .Invalid,
	provider: Role_Provider_Handle = {},
) -> Role_Failure {
	return Role_Failure {
		operation = operation,
		code = code,
		role = role,
		provider = provider,
	}
}
