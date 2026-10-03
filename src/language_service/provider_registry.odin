// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import "base:runtime"
import json "core:encoding/json"
import "core:strings"
import "core:unicode/utf8"

/* Executable_Discovery supplies the only paths admitted during controlled lookup. */
Executable_Discovery :: struct {
	explicit_path:       string,
	package_artifact:    string,
	distributed_artifact: string,
	search_path:         string,
}

/* Executable_Resolution_View borrows the latest registry-owned discovery state. */
Executable_Resolution_View :: struct {
	availability: Executable_Availability,
	source:       Executable_Source,
	path:         string,
}

/* Definition_Proposal borrows one complete data-only service definition. */
Definition_Proposal :: struct {
	kind:                   Provider_Kind,
	name:                   string,
	executable:             string,
	package_artifact:       string,
	distributed_artifact:   string,
	arguments:              []string,
	environment:            []string,
	root_policy:            Root_Policy,
	root:                   string,
	root_markers:           []string,
	languages:              []string,
	initialization_options: string,
	client_settings:        string,
	feature_policy:         Service_Features,
	requested_capabilities: Capabilities,
	preferred_encoding:     Position_Encoding,
	preferred_sync:         Synchronization_Mode,
	limits:                 Service_Limits,
	deadlines:              Deadline_Policy,
	restart:                Restart_Policy,
}

/* Definition_View borrows immutable registry-owned definition data. */
Definition_View :: struct {
	definition:             Service_Definition,
	provider:               Provider_Descriptor,
	root_policy:            Root_Policy,
	name:                   string,
	executable:             string,
	package_artifact:       string,
	distributed_artifact:   string,
	resolved_executable:    string,
	executable_availability: Executable_Availability,
	executable_source:       Executable_Source,
	arguments:              []string,
	environment:            []string,
	root:                   string,
	root_markers:           []string,
	languages:              []string,
	initialization_options: string,
	client_settings:        string,
	feature_policy:         Service_Features,
}

/* Registry_Inspection is one pointer-free provider registry state snapshot. */
Registry_Inspection :: struct {
	handle:               Registry_Handle,
	selection_generation: u64,
	factory:              Definition_Handle,
	active:               Definition_Handle,
	usage:                Resource_Usage,
	latest_failure:       Failure_Context,
}

/* Provider_Registry owns immutable definitions and one active selection. */
Provider_Registry :: struct {
	state: rawptr,
}

@(private)
Definition_Owner :: struct {
	definition:          Service_Definition,
	provider:            Provider_Descriptor,
	root_policy:         Root_Policy,
	name:                string,
	executable:          string,
	package_artifact:    string,
	distributed_artifact: string,
	resolved_executable: string,
	executable_availability: Executable_Availability,
	executable_source:    Executable_Source,
	arguments:           []string,
	environment:         []string,
	root:                string,
	root_markers:        []string,
	languages:           []string,
	initialization_options: string,
	client_settings:        string,
	live:                 bool,
}

@(private)
Provider_Registry_State :: struct {
	handle:               Registry_Handle,
	definitions:          [dynamic]Definition_Owner,
	factory:              Definition_Handle,
	active:               Definition_Handle,
	selection_generation: u64,
	next_definition_id:   Definition_ID,
	next_provider_id:     Provider_ID,
	usage:                Resource_Usage,
	limits:               Service_Limits,
	latest_failure:       Failure_Context,
	allocator:            runtime.Allocator,
}

/* provider_registry_init creates one empty checked native definition registry. */
provider_registry_init :: proc(
	registry: ^Provider_Registry,
	handle: Registry_Handle,
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
) -> (bool, Failure_Context) {
	if registry == nil do return false, Failure_Context{code = .Invalid_Input}
	registry^ = {}
	if handle.id == Registry_ID(0) || handle.generation == Registry_Generation(0) ||
	   allocator.procedure == nil || !service_limits_valid(limits) {
		return false, Failure_Context{code = .Invalid_Input}
	}
	state, allocation_error := new(Provider_Registry_State, allocator)
	if allocation_error != nil do return false, Failure_Context{code = .Allocation}
	definitions, definitions_error := make(
		[dynamic]Definition_Owner,
		0,
		int(limits.service_definitions),
		allocator,
	)
	if definitions_error != nil {
		free(state, allocator)
		return false, Failure_Context{code = .Allocation, resource = .Definition}
	}
	state^ = Provider_Registry_State{
		handle = handle,
		definitions = definitions,
		next_definition_id = Definition_ID(1),
		next_provider_id = Provider_ID(1),
		limits = limits,
		allocator = allocator,
	}
	state.usage.retained_bytes = u64(size_of(Provider_Registry_State)) +
		u64(cap(state.definitions)) * u64(size_of(Definition_Owner))
	registry.state = state
	return true, {}
}

/* provider_registry_close releases every copied definition and invalidates all handles. */
provider_registry_close :: proc(registry: ^Provider_Registry) -> bool {
	state := provider_registry_state(registry)
	if state == nil do return false
	for &owner in state.definitions do definition_owner_close(&owner, state.allocator)
	delete(state.definitions)
	free(state, state.allocator)
	registry^ = {}
	return true
}

/* provider_registry_propose validates and copies one inactive definition atomically. */
provider_registry_propose :: proc(
	registry: ^Provider_Registry,
	proposal: Definition_Proposal,
) -> (Definition_Handle, bool, Failure_Context) {
	state := provider_registry_state(registry)
	if state == nil do return {}, false, Failure_Context{code = .Closed}
	failure := definition_proposal_validate(proposal, state.limits)
	if failure.code != .None {
		state.latest_failure = failure
		return {}, false, failure
	}
	if state.usage.service_definitions >= u32(state.limits.service_definitions) ||
	   state.usage.providers >= u32(state.limits.providers) {
		failure = Failure_Context{code = .Resource_Limit, resource = .Definition, limit = u64(state.limits.service_definitions), actual = u64(state.usage.service_definitions) + 1}
		state.latest_failure = failure
		return {}, false, failure
	}
	if state.next_definition_id == Definition_ID(0) || state.next_provider_id == Provider_ID(0) {
		failure = Failure_Context{code = .Arithmetic_Overflow}
		state.latest_failure = failure
		return {}, false, failure
	}

	owner, copied, copy_failure := definition_owner_copy(state, proposal)
	if !copied {
		state.latest_failure = copy_failure
		return {}, false, copy_failure
	}
	stored, store_failure := provider_registry_store_owner(state, owner)
	if !stored {
		definition_owner_close(&owner, state.allocator)
		failure = store_failure
		state.latest_failure = failure
		return {}, false, failure
	}
	state.next_definition_id += Definition_ID(1)
	state.next_provider_id += Provider_ID(1)
	state.usage.service_definitions += 1
	state.usage.providers += 1
	state.usage.retained_bytes += definition_owner_retained_bytes(&owner)
	return owner.definition.handle, true, {}
}

/* provider_registry_confirm confirms one exact admitted definition generation. */
provider_registry_confirm :: proc(
	registry: ^Provider_Registry,
	handle: Definition_Handle,
) -> (bool, Failure_Context) {
	state := provider_registry_state(registry)
	owner, failure := provider_registry_resolve(state, handle)
	if failure.code != .None do return false, failure
	if owner.provider.state != .Admitted {
		failure = Failure_Context{code = .Invalid_Provider, definition = handle, provider = owner.provider.handle}
		state.latest_failure = failure
		return false, failure
	}
	owner.provider.state = .Confirmed
	return true, {}
}

/* provider_registry_discard_definition removes one unselected non-factory definition. */
provider_registry_discard_definition :: proc(
	registry: ^Provider_Registry,
	handle: Definition_Handle,
) -> (bool, Failure_Context) {
	state := provider_registry_state(registry)
	owner, failure := provider_registry_resolve(state, handle)
	if failure.code != .None do return false, failure
	if handle == state.factory || handle == state.active || owner.provider.state == .Selected {
		failure = Failure_Context {
			code = .Invalid_Provider,
			definition = handle,
			provider = owner.provider.handle,
		}
		state.latest_failure = failure
		return false, failure
	}
	provider_registry_discard(state, owner)
	return true, {}
}

/* provider_registry_select atomically selects one exact confirmed definition. */
provider_registry_select :: proc(
	registry: ^Provider_Registry,
	handle: Definition_Handle,
) -> (bool, Failure_Context) {
	state := provider_registry_state(registry)
	owner, failure := provider_registry_resolve(state, handle)
	if failure.code != .None do return false, failure
	if owner.provider.state != .Confirmed && owner.provider.state != .Selected {
		failure = Failure_Context{code = .Invalid_Provider, definition = handle, provider = owner.provider.handle}
		state.latest_failure = failure
		return false, failure
	}
	if state.active == handle do return true, {}
	if active_owner, active_failure := provider_registry_resolve(state, state.active); active_failure.code == .None {
		active_owner.provider.state = .Confirmed
	}
	owner.provider.state = .Selected
	state.active = handle
	state.selection_generation += 1
	return true, {}
}

/* provider_registry_disable disables one exact provider and clears it if active. */
provider_registry_disable :: proc(
	registry: ^Provider_Registry,
	handle: Provider_Handle,
) -> (bool, Failure_Context) {
	state := provider_registry_state(registry)
	owner, failure := provider_registry_resolve(state, handle.definition)
	if failure.code != .None do return false, failure
	if owner.provider.handle != handle || owner.provider.state == .Disabled {
		failure = Failure_Context{code = .Invalid_Provider, provider = handle}
		state.latest_failure = failure
		return false, failure
	}
	owner.provider.state = .Disabled
	if state.active == handle.definition {
		state.active = {}
		state.selection_generation += 1
	}
	return true, {}
}

/* provider_registry_restore_factory atomically restores the maintained definition. */
provider_registry_restore_factory :: proc(registry: ^Provider_Registry) -> (bool, Failure_Context) {
	state := provider_registry_state(registry)
	if state == nil do return false, Failure_Context{code = .Closed}
	owner, failure := provider_registry_resolve(state, state.factory)
	if failure.code != .None do return false, failure
	if owner.provider.state == .Disabled do owner.provider.state = .Confirmed
	return provider_registry_select(registry, state.factory)
}

/* provider_registry_replace validates and discovers a replacement before publication. */
provider_registry_replace :: proc(
	registry: ^Provider_Registry,
	expected: Definition_Handle,
	proposal: Definition_Proposal,
	discovery: Executable_Discovery,
) -> (Definition_Handle, bool, Failure_Context) {
	state := provider_registry_state(registry)
	if state == nil do return {}, false, Failure_Context{code = .Closed}
	if state.active != expected {
		failure := Failure_Context{code = .Stale_Generation, definition = expected}
		state.latest_failure = failure
		return {}, false, failure
	}
	handle, proposed, failure := provider_registry_propose(registry, proposal)
	if !proposed do return {}, false, failure
	owner, _ := provider_registry_resolve(state, handle)
	confirmed, confirm_failure := provider_registry_confirm(registry, handle)
	if !confirmed {
		provider_registry_discard(state, owner)
		return {}, false, confirm_failure
	}
	resolution, discovered, discovery_failure := provider_registry_revalidate_executable(
		registry,
		handle,
		discovery,
	)
	if !discovered || resolution.availability == .Unavailable {
		provider_registry_discard(state, owner)
		return {}, false, discovery_failure
	}
	selected, select_failure := provider_registry_select(registry, handle)
	if !selected {
		provider_registry_discard(state, owner)
		return {}, false, select_failure
	}
	return handle, true, {}
}

/* provider_registry_discover_executable returns one owned canonical executable path. */
provider_registry_discover_executable :: proc(
	registry: ^Provider_Registry,
	handle: Definition_Handle,
	discovery: Executable_Discovery,
) -> (string, bool, Failure_Context) {
	state := provider_registry_state(registry)
	owner, failure := provider_registry_resolve(state, handle)
	if failure.code != .None do return "", false, failure
	resolved, _, discovered := discover_executable_controlled(
		owner.executable,
		discovery,
		state.limits.executable_bytes,
		state.allocator,
	)
	if !discovered {
		failure = Failure_Context{code = .Executable_Not_Found, definition = handle, provider = owner.provider.handle}
		state.latest_failure = failure
		return "", false, failure
	}
	return resolved, true, {}
}

/* provider_registry_revalidate_executable refreshes availability before process start. */
provider_registry_revalidate_executable :: proc(
	registry: ^Provider_Registry,
	handle: Definition_Handle,
	discovery: Executable_Discovery,
) -> (Executable_Resolution_View, bool, Failure_Context) {
	state := provider_registry_state(registry)
	owner, failure := provider_registry_resolve(state, handle)
	if failure.code != .None do return {}, false, failure
	resolved, source, discovered := discover_executable_controlled(
		owner.executable,
		discovery,
		state.limits.executable_bytes,
		state.allocator,
	)
	if !discovered {
		if len(owner.resolved_executable) > 0 {
			state.usage.retained_bytes -= u64(len(owner.resolved_executable))
			delete(owner.resolved_executable, state.allocator)
			owner.resolved_executable = ""
		}
		owner.executable_availability = .Unavailable
		owner.executable_source = .Invalid
		failure = Failure_Context{
			code = .Executable_Not_Found,
			definition = handle,
			provider = owner.provider.handle,
		}
		state.latest_failure = failure
		return Executable_Resolution_View{availability = .Unavailable}, true, failure
	}
	availability := Executable_Availability.Available
	if len(owner.resolved_executable) > 0 && owner.resolved_executable != resolved {
		availability = .Changed
	}
	if len(owner.resolved_executable) > 0 {
		state.usage.retained_bytes -= u64(len(owner.resolved_executable))
		delete(owner.resolved_executable, state.allocator)
	}
	owner.resolved_executable = resolved
	owner.executable_availability = availability
	owner.executable_source = source
	state.usage.retained_bytes += u64(len(resolved))
	return Executable_Resolution_View{
		availability = availability,
		source = source,
		path = owner.resolved_executable,
	}, true, {}
}

/* provider_registry_definition returns one immutable borrowed definition view. */
provider_registry_definition :: proc(
	registry: ^Provider_Registry,
	handle: Definition_Handle,
) -> (Definition_View, bool, Failure_Context) {
	state := provider_registry_state(registry)
	owner, failure := provider_registry_resolve(state, handle)
	if failure.code != .None do return {}, false, failure
	return Definition_View{
		definition = owner.definition,
		provider = owner.provider,
		root_policy = owner.root_policy,
		name = owner.name,
		executable = owner.executable,
		package_artifact = owner.package_artifact,
		distributed_artifact = owner.distributed_artifact,
		resolved_executable = owner.resolved_executable,
		executable_availability = owner.executable_availability,
		executable_source = owner.executable_source,
		arguments = owner.arguments,
		environment = owner.environment,
		root = owner.root,
		root_markers = owner.root_markers,
		languages = owner.languages,
		initialization_options = owner.initialization_options,
		client_settings = owner.client_settings,
		feature_policy = owner.definition.feature_policy,
	}, true, {}
}

/* provider_registry_provider_handle resolves one exact provider identity. */
provider_registry_provider_handle :: proc(
	registry: ^Provider_Registry,
	id: Provider_ID,
	generation: Provider_Generation,
) -> (Provider_Handle, bool, Failure_Context) {
	state := provider_registry_state(registry)
	if state == nil do return {}, false, Failure_Context{code = .Closed}
	if id == Provider_ID(0) || generation == Provider_Generation(0) {
		return {}, false, Failure_Context{code = .Invalid_Provider}
	}
	for &owner in state.definitions {
		if owner.live && owner.provider.handle.id == id && owner.provider.handle.generation == generation {
			return owner.provider.handle, true, {}
		}
	}
	return {}, false, Failure_Context{code = .Stale_Generation}
}

/* provider_registry_inspect copies current pointer-free registry state. */
provider_registry_inspect :: proc(registry: ^Provider_Registry) -> (Registry_Inspection, bool) {
	state := provider_registry_state(registry)
	if state == nil do return {}, false
	return Registry_Inspection{
		handle = state.handle,
		selection_generation = state.selection_generation,
		factory = state.factory,
		active = state.active,
		usage = state.usage,
		latest_failure = state.latest_failure,
	}, true
}

@(private)
provider_registry_state :: proc(registry: ^Provider_Registry) -> ^Provider_Registry_State {
	if registry == nil || registry.state == nil do return nil
	return (^Provider_Registry_State)(registry.state)
}

@(private)
provider_registry_resolve :: proc(
	state: ^Provider_Registry_State,
	handle: Definition_Handle,
) -> (^Definition_Owner, Failure_Context) {
	if state == nil do return nil, Failure_Context{code = .Closed}
	if handle.registry != state.handle || handle.id == Definition_ID(0) ||
	   handle.generation == Definition_Generation(0) {
		return nil, Failure_Context{code = .Stale_Generation, definition = handle}
	}
	for &owner in state.definitions {
		if owner.live && owner.definition.handle == handle do return &owner, {}
	}
	return nil, Failure_Context{code = .Stale_Generation, definition = handle}
}

@(private = "file")
definition_proposal_validate :: proc(proposal: Definition_Proposal, maxima: Service_Limits) -> Failure_Context {
	if proposal.kind != .Factory && proposal.kind != .Native && proposal.kind != .Programmable {
		return Failure_Context{code = .Invalid_Provider}
	}
	if !service_limits_valid(proposal.limits) || !deadline_policy_valid(proposal.deadlines) ||
	   proposal.limits.service_definitions > maxima.service_definitions ||
	   proposal.limits.providers > maxima.providers ||
	   proposal.restart.automatic_restarts > DEFAULT_RESTART_POLICY.automatic_restarts ||
	   proposal.restart.stability_ns <= 0 || proposal.restart.stability_ns > proposal.deadlines.restart_stability_ns {
		return Failure_Context{code = .Invalid_Definition}
	}
	if !registry_text_valid(proposal.name, MAX_NAME_BYTES, false) ||
	   !registry_text_valid(proposal.executable, int(proposal.limits.executable_bytes), false) ||
	   !executable_reference_valid(proposal.executable) {
		return Failure_Context{code = .Invalid_Definition}
	}
	if !registry_text_valid(proposal.package_artifact, int(proposal.limits.executable_bytes), true) ||
	   !registry_text_valid(proposal.distributed_artifact, int(proposal.limits.executable_bytes), true) {
		return Failure_Context{code = .Invalid_Definition}
	}
	if proposal.root_policy != .Project_Membership && proposal.root_policy != .Workspace_Folder {
		return Failure_Context{code = .Invalid_Definition}
	}
	if !registry_text_valid(proposal.root, int(proposal.limits.root_bytes), true) || len(proposal.languages) == 0 ||
	   len(proposal.languages) > MAX_LANGUAGE_IDENTITIES ||
	   (proposal.preferred_encoding != .UTF_8 && proposal.preferred_encoding != .UTF_16) ||
	   (proposal.preferred_sync != .Full && proposal.preferred_sync != .Incremental) {
		return Failure_Context{code = .Invalid_Definition}
	}
	if !service_feature_policy_valid(proposal.feature_policy, proposal.requested_capabilities) {
		return Failure_Context{code = .Invalid_Definition}
	}
	if !service_root_markers_valid(proposal.root_markers, proposal.limits) {
		return Failure_Context{code = .Invalid_Definition, resource = .Root_Bytes}
	}
	argument_bytes: u64
	for value in proposal.arguments {
		if !registry_text_valid(value, int(proposal.limits.argument_bytes), true) do return Failure_Context{code = .Invalid_Definition}
		argument_bytes += u64(len(value))
	}
	if len(proposal.arguments) > int(proposal.limits.arguments) || argument_bytes > proposal.limits.argument_bytes {
		return Failure_Context{code = .Resource_Limit, resource = .Argument, limit = u64(proposal.limits.arguments), actual = u64(len(proposal.arguments))}
	}
	environment_bytes: u64
	for value in proposal.environment {
		if !registry_text_valid(value, int(proposal.limits.environment_bytes), false) || strings.index_byte(value, '=') <= 0 {
			return Failure_Context{code = .Invalid_Definition}
		}
		environment_bytes += u64(len(value))
	}
	for value, index in proposal.environment {
		separator := strings.index_byte(value, '=')
		for prior in 0 ..< index {
			prior_separator := strings.index_byte(proposal.environment[prior], '=')
			if value[:separator] == proposal.environment[prior][:prior_separator] {
				return Failure_Context{code = .Invalid_Definition, resource = .Environment}
			}
		}
	}
	if len(proposal.environment) > int(proposal.limits.environment_entries) || environment_bytes > proposal.limits.environment_bytes {
		return Failure_Context{code = .Resource_Limit, resource = .Environment, limit = u64(proposal.limits.environment_entries), actual = u64(len(proposal.environment))}
	}
	for language, index in proposal.languages {
		if !registry_text_valid(language, MAX_NAME_BYTES, false) do return Failure_Context{code = .Invalid_Definition}
		for prior in 0 ..< index {
			if proposal.languages[prior] == language do return Failure_Context{code = .Invalid_Definition}
		}
	}
	if u64(len(proposal.initialization_options)) > proposal.limits.options_bytes -
	   min(u64(len(proposal.client_settings)), proposal.limits.options_bytes) ||
	   !registry_json_value_valid(proposal.initialization_options, proposal.limits.options_bytes) ||
	   !registry_json_value_valid(proposal.client_settings, proposal.limits.options_bytes) {
		return Failure_Context{code = .Malformed_JSON, resource = .Option_Bytes}
	}
	return {}
}

@(private = "file")
definition_owner_copy :: proc(
	state: ^Provider_Registry_State,
	proposal: Definition_Proposal,
) -> (Definition_Owner, bool, Failure_Context) {
	owner := Definition_Owner{root_policy = proposal.root_policy, live = true}
	allocation_error: runtime.Allocator_Error
	owner.name, allocation_error = strings.clone(proposal.name, state.allocator)
	if allocation_error == nil do owner.executable, allocation_error = strings.clone(proposal.executable, state.allocator)
	if allocation_error == nil do owner.package_artifact, allocation_error = strings.clone(proposal.package_artifact, state.allocator)
	if allocation_error == nil do owner.distributed_artifact, allocation_error = strings.clone(proposal.distributed_artifact, state.allocator)
	if allocation_error == nil do owner.arguments, allocation_error = registry_clone_strings(proposal.arguments, state.allocator)
	if allocation_error == nil do owner.environment, allocation_error = registry_clone_strings(proposal.environment, state.allocator)
	if allocation_error == nil do owner.root, allocation_error = strings.clone(proposal.root, state.allocator)
	if allocation_error == nil do owner.root_markers, allocation_error = registry_clone_strings(proposal.root_markers, state.allocator)
	if allocation_error == nil do owner.languages, allocation_error = registry_clone_strings(proposal.languages, state.allocator)
	if allocation_error == nil do owner.initialization_options, allocation_error = strings.clone(proposal.initialization_options, state.allocator)
	if allocation_error == nil do owner.client_settings, allocation_error = strings.clone(proposal.client_settings, state.allocator)
	if allocation_error != nil {
		definition_owner_close(&owner, state.allocator)
		return {}, false, Failure_Context{code = .Allocation, resource = .Definition}
	}
	definition_handle := Definition_Handle{
		registry = state.handle,
		id = state.next_definition_id,
		generation = Definition_Generation(1),
	}
	provider_handle := Provider_Handle{
		definition = definition_handle,
		id = state.next_provider_id,
		generation = Provider_Generation(1),
	}
	name, _ := registry_name_text(proposal.name)
	owner.definition = Service_Definition{
		handle = definition_handle,
		name = name,
		root_policy = proposal.root_policy,
		feature_policy = proposal.feature_policy,
		requested_capabilities = proposal.requested_capabilities,
		preferred_encoding = proposal.preferred_encoding,
		preferred_sync = proposal.preferred_sync,
		limits = proposal.limits,
		deadlines = proposal.deadlines,
		restart = proposal.restart,
	}
	owner.provider = Provider_Descriptor{
		handle = provider_handle,
		kind = proposal.kind,
		state = .Admitted,
		name = name,
		capabilities = proposal.requested_capabilities,
	}
	return owner, true, {}
}

@(private = "file")
definition_owner_close :: proc(owner: ^Definition_Owner, allocator: runtime.Allocator) {
	if owner == nil || !owner.live do return
	delete(owner.name, allocator)
	delete(owner.executable, allocator)
	delete(owner.package_artifact, allocator)
	delete(owner.distributed_artifact, allocator)
	if len(owner.resolved_executable) > 0 do delete(owner.resolved_executable, allocator)
	for value in owner.arguments do delete(value, allocator)
	if owner.arguments != nil do delete(owner.arguments, allocator)
	for value in owner.environment do delete(value, allocator)
	if owner.environment != nil do delete(owner.environment, allocator)
	delete(owner.root, allocator)
	for value in owner.root_markers do delete(value, allocator)
	if owner.root_markers != nil do delete(owner.root_markers, allocator)
	for value in owner.languages do delete(value, allocator)
	if owner.languages != nil do delete(owner.languages, allocator)
	delete(owner.initialization_options, allocator)
	delete(owner.client_settings, allocator)
	owner^ = {}
}

@(private)
provider_registry_discard :: proc(state: ^Provider_Registry_State, owner: ^Definition_Owner) {
	if state == nil || owner == nil || !owner.live do return
	retained := definition_owner_retained_bytes(owner)
	definition_owner_close(owner, state.allocator)
	state.usage.service_definitions -= 1
	state.usage.providers -= 1
	state.usage.retained_bytes -= retained
}

@(private = "file")
provider_registry_store_owner :: proc(
	state: ^Provider_Registry_State,
	owner: Definition_Owner,
) -> (bool, Failure_Context) {
	for &slot in state.definitions {
		if !slot.live {
			slot = owner
			return true, {}
		}
	}
	if len(state.definitions) >= cap(state.definitions) {
		return false, Failure_Context{
			code = .Resource_Limit,
			resource = .Definition,
			limit = u64(state.limits.service_definitions),
			actual = u64(len(state.definitions)) + 1,
		}
	}
	_, append_error := append(&state.definitions, owner)
	if append_error != nil do return false, Failure_Context{code = .Allocation, resource = .Definition}
	return true, {}
}

@(private = "file")
definition_owner_retained_bytes :: proc(owner: ^Definition_Owner) -> u64 {
	if owner == nil || !owner.live do return 0
	result := u64(len(owner.name) + len(owner.executable) + len(owner.package_artifact) +
		len(owner.distributed_artifact) + len(owner.resolved_executable) +
		len(owner.root) + len(owner.initialization_options) + len(owner.client_settings))
	result += u64(len(owner.arguments) + len(owner.environment) + len(owner.root_markers) + len(owner.languages)) * u64(size_of(string))
	for value in owner.arguments do result += u64(len(value))
	for value in owner.environment do result += u64(len(value))
	for value in owner.root_markers do result += u64(len(value))
	for value in owner.languages do result += u64(len(value))
	return result
}

@(private = "file")
registry_text_valid :: proc(value: string, maximum: int, empty_ok: bool) -> bool {
	return (empty_ok || len(value) > 0) && len(value) <= maximum &&
		utf8.valid_string(value) && strings.index_byte(value, 0) < 0 &&
		strings.index_byte(value, '\n') < 0 && strings.index_byte(value, '\r') < 0
}

@(private = "file")
registry_json_value_valid :: proc(value: string, maximum: u64) -> bool {
	if len(value) == 0 do return true
	if u64(len(value)) > maximum || !utf8.valid_string(value) do return false
	parsed, parse_error := json.parse_string(value, .JSON, true, context.temp_allocator)
	if parse_error != .None do return false
	json.destroy_value(parsed, context.temp_allocator)
	return true
}

@(private = "file")
registry_name_text :: proc(value: string) -> (Name_Text, bool) {
	if !registry_text_valid(value, MAX_NAME_BYTES, false) do return {}, false
	result := Name_Text{length = u16(len(value))}
	copy(result.bytes[:len(value)], transmute([]u8)value)
	return result, true
}

@(private = "file")
registry_clone_strings :: proc(
	values: []string,
	allocator: runtime.Allocator,
) -> ([]string, runtime.Allocator_Error) {
	owned, allocation_error := make([]string, len(values), allocator)
	if allocation_error != nil do return nil, allocation_error
	for value, index in values {
		owned[index], allocation_error = strings.clone(value, allocator)
		if allocation_error != nil {
			for previous in 0 ..< index do delete(owned[previous], allocator)
			delete(owned, allocator)
			return nil, allocation_error
		}
	}
	return owned, nil
}
