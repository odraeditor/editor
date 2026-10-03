// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "base:runtime"

/* Profile_Activation owns the single replaceable global resolution snapshot. */
Profile_Activation :: struct {
	snapshot:        Resolution_Snapshot,
	catalog:         Profile_Catalog,
	generation:      Snapshot_Generation,
	catalog_generation: Profile_Catalog_Generation,
	active_profile:  Profile_Identity,
	active_state:    Interaction_State_Definition,
	modal_pending:   Modal_Pending_State,
	modal_character_search: Modal_Character_Search_State,
	modal_operator_execution: Modal_Operator_Execution_State,
	modal_visual:    Modal_Visual_State,
	latest_rejection: Failure_Context,
	ready:           bool,
	closed:          bool,
}

@(private)
Selected_Profile_Candidate :: struct {
	profile:   Profile_Definition,
	maps:      []Map_Definition,
	bindings:  []Layered_Binding_Definition,
	allocator: runtime.Allocator,
}

/* profile_activation_init prepares an empty global profile owner. */
profile_activation_init :: proc(activation: ^Profile_Activation) {
	assert(activation != nil)
	activation^ = Profile_Activation{ready = true}
}

/* profile_activation_replace compiles and atomically publishes one complete candidate. */
profile_activation_replace :: proc(
	activation: ^Profile_Activation,
	registry: ^Command_Registry,
	profile: Profile_Definition,
	active_context: Active_Context,
	pending: ^Pending_State,
	policy: Resolution_Policy,
	allocator: runtime.Allocator,
) -> (ok: bool, failure: Failure_Context) {
	assert(activation != nil)
	assert(pending != nil)
	if !activation.ready || activation.closed {
		failure.code = .Invalid_Snapshot
		activation.latest_rejection = failure
		return false, failure
	}
	if activation.generation != Snapshot_Generation(0) &&
	   activation.active_profile.id == profile.identity.id &&
	   profile.identity.revision <= activation.active_profile.revision {
		failure = Failure_Context {
			code = .Stale_Profile,
			profile = profile.identity,
			snapshot_generation = activation.generation,
		}
		activation.latest_rejection = failure
		return false, failure
	}
	next_generation := Snapshot_Generation(u64(activation.generation) + 1)
	if next_generation == Snapshot_Generation(0) {
		failure = Failure_Context {
			code = .Generation_Limit,
			profile = profile.identity,
			snapshot_generation = activation.generation,
		}
		activation.latest_rejection = failure
		return false, failure
	}
	published, compile_failure := profile_snapshot_compile(
		&activation.snapshot,
		registry,
		next_generation,
		profile,
		active_context,
		policy,
		allocator,
	)
	if !published {
		activation.latest_rejection = compile_failure
		return false, compile_failure
	}
	activation.generation = next_generation
	activation.active_profile = profile.identity
	activation.active_state = {}
	activation.modal_pending = {}
	activation.modal_operator_execution = {}
	activation.modal_character_search = {}
	activation.modal_visual = {}
	activation.catalog_generation = 0
	if activation.catalog.state != nil {
		assert(profile_catalog_close(&activation.catalog))
	}
	activation.latest_rejection = {}
	pending_clear(pending)
	return true, {}
}

/* profile_activation_replace_catalog validates, compiles, and publishes one selected catalog state. */
profile_activation_replace_catalog :: proc(
	activation: ^Profile_Activation,
	registry: ^Command_Registry,
	definition: Profile_Catalog_Definition,
	active_context: Active_Context,
	pending: ^Pending_State,
	compatibility_policy: Profile_Compatibility_Policy,
	resolution_policy: Resolution_Policy,
	allocator: runtime.Allocator,
) -> (ok: bool, failure: Failure_Context) {
	assert(activation != nil)
	assert(pending != nil)
	if !activation.ready || activation.closed {
		failure.code = .Invalid_Snapshot
		activation.latest_rejection = failure
		return false, failure
	}
	if activation.catalog_generation != Profile_Catalog_Generation(0) &&
	   definition.generation <= activation.catalog_generation {
		failure = Failure_Context {
			code = .Stale_Profile_Catalog,
			catalog_generation = definition.generation,
			snapshot_generation = activation.generation,
		}
		activation.latest_rejection = failure
		return false, failure
	}
	next_generation := Snapshot_Generation(u64(activation.generation) + 1)
	if next_generation == Snapshot_Generation(0) {
		failure = Failure_Context {
			code = .Generation_Limit,
			catalog_generation = definition.generation,
			snapshot_generation = activation.generation,
		}
		activation.latest_rejection = failure
		return false, failure
	}

	candidate_catalog, built, build_failure := profile_catalog_build(
		registry,
		definition,
		compatibility_policy,
		allocator,
	)
	if !built {
		activation.latest_rejection = build_failure
		return false, build_failure
	}
	owned_definition, viewed := profile_catalog_definition(&candidate_catalog)
	assert(viewed)
	selected_profile, selected_state, selected := profile_catalog_active_selection(owned_definition)
	if !selected {
		profile_catalog_close(&candidate_catalog)
		failure = Failure_Context {
			code = .Invalid_Interaction_State,
			catalog_generation = definition.generation,
			profile = {id = definition.active_profile},
			state = {id = definition.active_state},
		}
		activation.latest_rejection = failure
		return false, failure
	}
	projected, projected_ok, projection_failure := selected_profile_candidate_build(
		owned_definition,
		selected_profile,
		selected_state,
		allocator,
	)
	if !projected_ok {
		profile_catalog_close(&candidate_catalog)
		activation.latest_rejection = projection_failure
		return false, projection_failure
	}
	defer selected_profile_candidate_close(&projected)

	published, compile_failure := profile_snapshot_compile(
		&activation.snapshot,
		registry,
		next_generation,
		projected.profile,
		active_context,
		resolution_policy,
		allocator,
	)
	if !published {
		profile_catalog_close(&candidate_catalog)
		compile_failure.catalog_generation = definition.generation
		compile_failure.state = selected_state.identity
		activation.latest_rejection = compile_failure
		return false, compile_failure
	}

	if activation.catalog.state != nil {
		assert(profile_catalog_close(&activation.catalog))
	}
	activation.catalog = candidate_catalog
	activation.generation = next_generation
	activation.catalog_generation = owned_definition.generation
	activation.active_profile = selected_profile.identity
	activation.active_state = selected_state
	activation.modal_pending = {}
	activation.modal_operator_execution = {}
	activation.modal_character_search = {}
	activation.modal_visual = {}
	activation.latest_rejection = {}
	pending_clear(pending)
	return true, {}
}

/* profile_activation_snapshot returns the active immutable snapshot handle. */
profile_activation_snapshot :: proc(
	activation: ^Profile_Activation,
) -> (snapshot: ^Resolution_Snapshot, ok: bool) {
	if activation == nil || !activation.ready || activation.closed ||
	   activation.generation == Snapshot_Generation(0) {
		return nil, false
	}
	return &activation.snapshot, true
}

/* profile_activation_catalog returns the active immutable catalog definition. */
profile_activation_catalog :: proc(
	activation: ^Profile_Activation,
) -> (definition: Profile_Catalog_Definition, ok: bool) {
	if activation == nil || !activation.ready || activation.closed ||
	   activation.catalog_generation == Profile_Catalog_Generation(0) {
		return {}, false
	}
	return profile_catalog_definition(&activation.catalog)
}

/* profile_activation_command_entry_surface returns one checked active catalog surface. */
profile_activation_command_entry_surface :: proc(
	activation: ^Profile_Activation,
	name: string,
) -> (surface: Command_Entry_Surface_Definition, ok: bool) {
	definition, active := profile_activation_catalog(activation)
	if !active {
		return {}, false
	}
	for candidate in definition.surfaces {
		if candidate.name == name {
			return candidate, true
		}
	}
	return {}, false
}

/* profile_activation_selection returns the checked active profile and state. */
profile_activation_selection :: proc(
	activation: ^Profile_Activation,
) -> (profile: Profile_Identity, state: Interaction_State_Definition, ok: bool) {
	if activation == nil || !activation.ready || activation.closed ||
	   activation.catalog_generation == Profile_Catalog_Generation(0) {
		return {}, {}, false
	}
	return activation.active_profile, activation.active_state, true
}

/* profile_activation_transition_state atomically publishes one exact state. */
profile_activation_transition_state :: proc(
	activation: ^Profile_Activation,
	registry: ^Command_Registry,
	request: State_Transition_Request,
	active_context: Active_Context,
	pending: ^Pending_State,
	policy: Resolution_Policy,
	allocator: runtime.Allocator,
) -> (ok: bool, failure: Failure_Context) {
	assert(activation != nil)
	assert(pending != nil)
	if !activation.ready || activation.closed {
		failure = Failure_Context{code = .Invalid_Snapshot}
		activation.latest_rejection = failure
		return false, failure
	}
	if request.catalog_generation != activation.catalog_generation {
		failure = Failure_Context {
			code = .Stale_Profile_Catalog,
			catalog_generation = request.catalog_generation,
			snapshot_generation = request.snapshot_generation,
		}
		activation.latest_rejection = failure
		return false, failure
	}
	if request.snapshot_generation != activation.generation ||
	   request.profile != activation.active_profile ||
	   request.source != activation.active_state.identity {
		failure = Failure_Context {
			code = .Stale_Interaction_State,
			catalog_generation = activation.catalog_generation,
			snapshot_generation = request.snapshot_generation,
			profile = request.profile,
			state = request.source,
		}
		activation.latest_rejection = failure
		return false, failure
	}
	if request.target == request.source {
		failure = Failure_Context {
			code = .Invalid_Interaction_State,
			catalog_generation = activation.catalog_generation,
			snapshot_generation = activation.generation,
			profile = activation.active_profile,
			state = request.target,
		}
		activation.latest_rejection = failure
		return false, failure
	}
	definition, catalog_ok := profile_activation_catalog(activation)
	if !catalog_ok {
		failure = Failure_Context{code = .Invalid_Profile_Catalog}
		activation.latest_rejection = failure
		return false, failure
	}
	profile, state, selected := profile_catalog_exact_selection(
		definition,
		request.profile,
		request.target,
	)
	if !selected {
		failure = Failure_Context {
			code = .Invalid_Interaction_State,
			catalog_generation = activation.catalog_generation,
			snapshot_generation = activation.generation,
			profile = request.profile,
			state = request.target,
		}
		activation.latest_rejection = failure
		return false, failure
	}
	return profile_activation_publish_selection(
		activation,
		registry,
		definition,
		profile,
		state,
		active_context,
		pending,
		policy,
		allocator,
	)
}

/* profile_activation_select_profile atomically selects one profile initial state. */
profile_activation_select_profile :: proc(
	activation: ^Profile_Activation,
	registry: ^Command_Registry,
	request: Profile_Selection_Request,
	active_context: Active_Context,
	pending: ^Pending_State,
	policy: Resolution_Policy,
	allocator: runtime.Allocator,
) -> (ok: bool, failure: Failure_Context) {
	assert(activation != nil)
	assert(pending != nil)
	if !activation.ready || activation.closed {
		failure = Failure_Context{code = .Invalid_Snapshot}
		activation.latest_rejection = failure
		return false, failure
	}
	if request.catalog_generation != activation.catalog_generation {
		failure = Failure_Context {
			code = .Stale_Profile_Catalog,
			catalog_generation = request.catalog_generation,
			snapshot_generation = request.snapshot_generation,
			profile = request.target,
		}
		activation.latest_rejection = failure
		return false, failure
	}
	if request.snapshot_generation != activation.generation {
		failure = Failure_Context {
			code = .Stale_Snapshot,
			catalog_generation = activation.catalog_generation,
			snapshot_generation = request.snapshot_generation,
			profile = request.target,
		}
		activation.latest_rejection = failure
		return false, failure
	}
	definition, catalog_ok := profile_activation_catalog(activation)
	if !catalog_ok {
		failure = Failure_Context{code = .Invalid_Profile_Catalog}
		activation.latest_rejection = failure
		return false, failure
	}
	profile, found := profile_catalog_exact_profile(definition, request.target)
	if !found {
		failure = Failure_Context {
			code = .Invalid_Profile,
			catalog_generation = activation.catalog_generation,
			snapshot_generation = activation.generation,
			profile = request.target,
		}
		activation.latest_rejection = failure
		return false, failure
	}
	state, state_found := profile_definition_state(profile, profile.initial_state)
	if !state_found {
		failure = Failure_Context {
			code = .Invalid_Interaction_State,
			catalog_generation = activation.catalog_generation,
			snapshot_generation = activation.generation,
			profile = request.target,
			state = {id = profile.initial_state},
		}
		activation.latest_rejection = failure
		return false, failure
	}
	previous_profile := activation.active_profile
	published, publish_failure := profile_activation_publish_selection(
		activation,
		registry,
		definition,
		profile,
		state,
		active_context,
		pending,
		policy,
		allocator,
	)
	if published && request.target != previous_profile {
		activation.modal_character_search = {}
		activation.modal_visual = {}
	}
	return published, publish_failure
}

/* profile_activation_modal_pending_begin copies one exact transient interaction. */
profile_activation_modal_pending_begin :: proc(
	activation: ^Profile_Activation,
	request: Modal_Pending_Request,
) -> (ok: bool, failure: Failure_Context) {
	assert(activation != nil)
	failure = Failure_Context {
		catalog_generation = request.catalog_generation,
		snapshot_generation = request.snapshot_generation,
		profile = request.profile,
		state = request.state,
		ctx = request.ctx,
	}
	if !activation.ready || activation.closed {
		failure.code = .Invalid_Snapshot
		activation.latest_rejection = failure
		return false, failure
	}
	if request.catalog_generation != activation.catalog_generation ||
	   request.snapshot_generation != activation.generation ||
	   request.profile != activation.active_profile ||
	   request.state != activation.active_state.identity {
		failure.code = .Stale_Interaction_State
		activation.latest_rejection = failure
		return false, failure
	}
	snapshot := snapshot_data(&activation.snapshot)
	if snapshot == nil || snapshot.ctx != request.ctx {
		failure.code = .Stale_Context
		activation.latest_rejection = failure
		return false, failure
	}
	if request.kind == .None || request.view_identity == 0 || request.view_generation == 0 ||
	   request.buffer_identity == 0 ||
	   !sequence_valid(request.sequence) ||
	   len(request.text) > MAX_MODAL_PENDING_TEXT_BYTES ||
	   len(request.named_slot) > MAX_MODAL_PENDING_TEXT_BYTES ||
	   request.kind == .Count && request.count == 0 ||
	   request.kind == .Named_Slot && request.count == 0 ||
	   request.kind == .Command_Entry &&
	   (request.command_entry_surface.id == Command_Entry_Surface_ID(0) ||
	    request.command_entry_surface.revision == Command_Entry_Surface_Revision(0)) ||
	   request.kind == .Character_Target &&
	   (request.count == 0 || request.character_target == .None) ||
	   request.kind == .Operator &&
	   (request.count == 0 || request.operator == .None ||
	    request.operator_stage == .None ||
	    request.target_count > MAX_MODAL_COUNT ||
	    request.target_count_explicit && request.target_count == 0 ||
	    !request.target_count_explicit && request.target_count != 0 ||
	    request.operator_stage == .Character_Target &&
	    request.character_target == .None && request.operator != .Replace ||
	    request.operator_stage == .Text_Object && len(request.text) != 1) {
		failure.code = .Invalid_Input
		failure.limit = MAX_MODAL_PENDING_TEXT_BYTES
		failure.actual = u64(len(request.text))
		activation.latest_rejection = failure
		return false, failure
	}
	candidate := Modal_Pending_State {
		kind = request.kind,
		profile = request.profile,
		state = request.state,
		catalog_generation = request.catalog_generation,
		snapshot_generation = request.snapshot_generation,
		ctx = request.ctx,
		view_identity = request.view_identity,
		view_generation = request.view_generation,
		buffer_identity = request.buffer_identity,
		buffer_revision = request.buffer_revision,
		operator_origin = request.operator_origin,
		strokes = request.sequence.strokes,
		stroke_count = request.sequence.stroke_count,
		text_length = u8(len(request.text)),
		count = request.count,
		character_target = request.character_target,
		operator = request.operator,
		operator_stage = request.operator_stage,
		target_count = request.target_count,
		operator_count_explicit = request.operator_count_explicit,
		target_count_explicit = request.target_count_explicit,
		named_slot_length = u8(len(request.named_slot)),
		command_entry_surface = request.command_entry_surface,
	}
	copy(candidate.text[:], transmute([]u8)request.text)
	copy(candidate.named_slot[:], transmute([]u8)request.named_slot)
	activation.modal_pending = candidate
	activation.latest_rejection = {}
	return true, {}
}

/* profile_activation_modal_pending_cancel releases all transient modal state. */
profile_activation_modal_pending_cancel :: proc(activation: ^Profile_Activation) -> bool {
	if activation == nil || !activation.ready || activation.closed do return false
	activation.modal_pending = {}
	activation.modal_operator_execution = {}
	return true
}

/* profile_activation_modal_pending_inspect copies the retained transient state. */
profile_activation_modal_pending_inspect :: proc(
	activation: ^Profile_Activation,
) -> (pending: Modal_Pending_State, ok: bool) {
	if activation == nil || !activation.ready || activation.closed do return {}, false
	return activation.modal_pending, true
}

/* profile_activation_command_admit checks one registered command against active state policy. */
profile_activation_command_admit :: proc(
	activation: ^Profile_Activation,
	registry: ^Command_Registry,
	command: Command_Handle,
) -> (ok: bool, failure: Failure_Context) {
	if activation == nil || !activation.ready || activation.closed {
		return false, Failure_Context{code = .Invalid_Snapshot, command = command}
	}
	metadata, metadata_ok, metadata_failure := command_metadata(registry, command)
	if !metadata_ok {
		return false, metadata_failure
	}
	if activation.catalog_generation == Profile_Catalog_Generation(0) {
		return true, {}
	}
	if (metadata.invocation == .Text_Input && !activation.active_state.admits_text_input) ||
	   !interaction_state_admits(activation.active_state, metadata.effects) {
		return false, Failure_Context {
			code = .Command_Effect_Rejected,
			registry_generation = command.registry_generation,
			snapshot_generation = activation.generation,
			command = command,
			profile = activation.active_profile,
			catalog_generation = activation.catalog_generation,
			state = activation.active_state.identity,
		}
	}
	return true, {}
}

/* profile_activation_last_rejection returns the latest rejected candidate diagnostic. */
profile_activation_last_rejection :: proc(activation: ^Profile_Activation) -> Failure_Context {
	if activation == nil {
		return Failure_Context{code = .Invalid_Snapshot}
	}
	return activation.latest_rejection
}

/* profile_activation_close retires the active snapshot and closes the owner. */
profile_activation_close :: proc(
	activation: ^Profile_Activation,
) -> (ok: bool, failure: Failure_Context) {
	assert(activation != nil)
	if !activation.ready || activation.closed {
		return false, Failure_Context{code = .Invalid_Snapshot}
	}
	if activation.generation != Snapshot_Generation(0) {
		_, failure = snapshot_close(&activation.snapshot)
		if failure.code != .None {
			return false, failure
		}
	}
	if activation.catalog.state != nil {
		if !profile_catalog_close(&activation.catalog) {
			return false, Failure_Context{code = .Invalid_Profile_Catalog}
		}
	}
	activation.modal_pending = {}
	activation.modal_operator_execution = {}
	activation.modal_character_search = {}
	activation.modal_visual = {}
	activation.ready = false
	activation.closed = true
	return true, {}
}

@(private)
profile_activation_publish_selection :: proc(
	activation: ^Profile_Activation,
	registry: ^Command_Registry,
	definition: Profile_Catalog_Definition,
	profile: Profile_Definition,
	state: Interaction_State_Definition,
	active_context: Active_Context,
	pending: ^Pending_State,
	policy: Resolution_Policy,
	allocator: runtime.Allocator,
) -> (ok: bool, failure: Failure_Context) {
	next_generation := Snapshot_Generation(u64(activation.generation) + 1)
	if next_generation == Snapshot_Generation(0) {
		failure = Failure_Context {
			code = .Generation_Limit,
			catalog_generation = definition.generation,
			snapshot_generation = activation.generation,
			profile = profile.identity,
			state = state.identity,
		}
		activation.latest_rejection = failure
		return false, failure
	}
	projected, projected_ok, projection_failure := selected_profile_candidate_build(
		definition,
		profile,
		state,
		allocator,
	)
	if !projected_ok {
		activation.latest_rejection = projection_failure
		return false, projection_failure
	}
	defer selected_profile_candidate_close(&projected)
	published, compile_failure := profile_snapshot_compile(
		&activation.snapshot,
		registry,
		next_generation,
		projected.profile,
		active_context,
		policy,
		allocator,
	)
	if !published {
		compile_failure.catalog_generation = definition.generation
		compile_failure.state = state.identity
		activation.latest_rejection = compile_failure
		return false, compile_failure
	}
	activation.generation = next_generation
	activation.active_profile = profile.identity
	activation.active_state = state
	activation.modal_pending = {}
	activation.modal_operator_execution = {}
	activation.modal_visual = {}
	activation.latest_rejection = {}
	pending_clear(pending)
	return true, {}
}

@(private)
profile_catalog_exact_profile :: proc(
	definition: Profile_Catalog_Definition,
	identity: Profile_Identity,
) -> (profile: Profile_Definition, ok: bool) {
	for candidate in definition.profiles {
		if candidate.identity == identity do return candidate, true
	}
	return {}, false
}

@(private)
profile_definition_state :: proc(
	profile: Profile_Definition,
	state_id: Interaction_State_ID,
) -> (state: Interaction_State_Definition, ok: bool) {
	for candidate in profile.states {
		if candidate.identity.id == state_id do return candidate, true
	}
	return {}, false
}

@(private)
profile_catalog_exact_selection :: proc(
	definition: Profile_Catalog_Definition,
	profile_identity: Profile_Identity,
	state_identity: Interaction_State_Identity,
) -> (profile: Profile_Definition, state: Interaction_State_Definition, ok: bool) {
	selected_profile, profile_ok := profile_catalog_exact_profile(definition, profile_identity)
	if !profile_ok do return {}, {}, false
	for candidate in selected_profile.states {
		if candidate.identity == state_identity do return selected_profile, candidate, true
	}
	return {}, {}, false
}

@(private)
profile_catalog_active_selection :: proc(
	definition: Profile_Catalog_Definition,
) -> (profile: Profile_Definition, state: Interaction_State_Definition, ok: bool) {
	for candidate_profile in definition.profiles {
		if candidate_profile.identity.id != definition.active_profile {
			continue
		}
		for candidate_state in candidate_profile.states {
			if candidate_state.identity.id == definition.active_state {
				return candidate_profile, candidate_state, true
			}
		}
	}
	return {}, {}, false
}

@(private)
selected_profile_candidate_build :: proc(
	definition: Profile_Catalog_Definition,
	selected_profile: Profile_Definition,
	selected_state: Interaction_State_Definition,
	allocator: runtime.Allocator,
) -> (candidate: Selected_Profile_Candidate, ok: bool, failure: Failure_Context) {
	candidate.allocator = allocator
	if allocator.procedure == nil {
		return {}, false, Failure_Context {
			code = .Persistent_Memory_Limit,
			catalog_generation = definition.generation,
			profile = selected_profile.identity,
			state = selected_state.identity,
		}
	}
	binding_count := selected_profile_binding_count(
		definition,
		selected_profile,
		selected_state.identity,
	)
	allocation_error: runtime.Allocator_Error
	candidate.maps, allocation_error = make([]Map_Definition, len(selected_profile.maps), allocator)
	if allocation_error != nil {
		return {}, false, Failure_Context {
			code = .Persistent_Memory_Limit,
			catalog_generation = definition.generation,
			profile = selected_profile.identity,
			state = selected_state.identity,
		}
	}
	if binding_count > 0 {
		candidate.bindings, allocation_error = make([]Layered_Binding_Definition, binding_count, allocator)
		if allocation_error != nil {
			selected_profile_candidate_close(&candidate)
			return {}, false, Failure_Context {
				code = .Persistent_Memory_Limit,
				catalog_generation = definition.generation,
				profile = selected_profile.identity,
				state = selected_state.identity,
			}
		}
	}

	binding_offset := 0
	for selected_map, map_index in selected_profile.maps {
		candidate.maps[map_index] = selected_map
		if !selected_state.admits_text_input &&
		   candidate.maps[map_index].unmatched_input_policy == .Text_Input {
			candidate.maps[map_index].unmatched_input_policy = .Reject
		}
		start := binding_offset
		for binding in selected_map.bindings {
			if profile_binding_applies(binding, selected_profile.identity.id, selected_state.identity.id) {
				candidate.bindings[binding_offset] = binding
				binding_offset += 1
			}
		}
		for source_profile in definition.profiles {
			if source_profile.identity.id == selected_profile.identity.id {
				continue
			}
			for source_map in source_profile.maps {
				if source_map.identity.id != selected_map.identity.id {
					continue
				}
				for binding in source_map.bindings {
					if binding.scope == .Shared_Continuity && profile_binding_applies(
						binding,
						selected_profile.identity.id,
						selected_state.identity.id,
					) {
						candidate.bindings[binding_offset] = binding
						binding_offset += 1
					}
				}
			}
		}
		candidate.maps[map_index].bindings = candidate.bindings[start:binding_offset]
	}
	assert(binding_offset == binding_count)
	candidate.profile = selected_profile
	candidate.profile.maps = candidate.maps
	return candidate, true, {}
}

@(private)
selected_profile_binding_count :: proc(
	definition: Profile_Catalog_Definition,
	selected_profile: Profile_Definition,
	selected_state: Interaction_State_Identity,
) -> int {
	count := 0
	for selected_map in selected_profile.maps {
		for binding in selected_map.bindings {
			if profile_binding_applies(binding, selected_profile.identity.id, selected_state.id) {
				count += 1
			}
		}
		for source_profile in definition.profiles {
			if source_profile.identity.id == selected_profile.identity.id {
				continue
			}
			for source_map in source_profile.maps {
				if source_map.identity.id != selected_map.identity.id {
					continue
				}
				for binding in source_map.bindings {
					if binding.scope == .Shared_Continuity && profile_binding_applies(
						binding,
						selected_profile.identity.id,
						selected_state.id,
					) {
						count += 1
					}
				}
			}
		}
	}
	return count
}

@(private)
profile_binding_applies :: proc(
	binding: Layered_Binding_Definition,
	profile: Profile_ID,
	state: Interaction_State_ID,
) -> bool {
	switch binding.scope {
	case .Profile_Specific:
		return true
	case .State_Specific:
		for selector in binding.selectors {
			if selector.profile_id == profile && selector.state_id == state {
				return true
			}
		}
	case .Shared_Continuity:
		for selector in binding.selectors {
			if selector.profile_id == profile && selector.state_id == state {
				return true
			}
		}
	case .Protected_Recovery, .Invalid:
		return false
	}
	return false
}

@(private)
selected_profile_candidate_close :: proc(candidate: ^Selected_Profile_Candidate) {
	if candidate == nil {
		return
	}
	if candidate.bindings != nil do delete(candidate.bindings, candidate.allocator)
	if candidate.maps != nil do delete(candidate.maps, candidate.allocator)
	candidate^ = {}
}
