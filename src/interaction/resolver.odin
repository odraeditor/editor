// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "base:runtime"
import "core:slice"
import "core:unicode"
import "core:unicode/utf8"

@(private)
Registry_State :: enum u8 {
	Invalid,
	Ready,
	Closed,
}

@(private)
Snapshot_State :: enum u8 {
	Invalid,
	Ready,
	Closed,
}

@(private)
Command_Entry :: struct {
	name:             [MAX_COMMAND_NAME_BYTES]u8,
	name_count:       u8,
	description:      [MAX_COMMAND_DESCRIPTION_BYTES]u8,
	description_count: u16,
	handle:           Command_Handle,
	route:            Command_Route,
	implementation:   Implementation_Class,
	invocation:       Invocation_Class,
	text_requirement: Text_Requirement,
	effects:          Command_Effects,
	interactive:      bool,
	requirements:     Command_Requirements,
	provenance:       Compiled_Provenance,
}

@(private)
Registry_Data :: struct {
	state:           Registry_State,
	generation:      Registry_Generation,
	command_count:   u16,
	retained_maps:   u16,
	allocator:       runtime.Allocator,
	storage_bytes:   u64,
	entries:         [MAX_COMMANDS]Command_Entry,
}

@(private)
Compiled_Binding :: struct {
	strokes:      [MAX_SEQUENCE_STROKES]Key_Stroke,
	stroke_count: u8,
	command:      Command_Handle,
}

@(private)
Snapshot_Data :: struct {
	state:                Snapshot_State,
	generation:           Snapshot_Generation,
	registry:             ^Registry_Data,
	registry_generation:  Registry_Generation,
	profile:              Profile_Identity,
	ctx:                  Context_Handle,
	map_count:            u16,
	active_map_count:     u16,
	inspection_limit:     u16,
	layered:              bool,
	layered_maps:         []Compiled_Map,
	layered_bindings:     []Layered_Compiled_Binding,
	layered_remaps:       []Compiled_Remap,
	layered_trie_nodes:   []Compiled_Trie_Node,
	binding_count:        u16,
	text_fallback:        Command_Handle,
	cancellation_command: Command_Handle,
	has_cancellation:     bool,
	allocator:            runtime.Allocator,
	storage_bytes:        u64,
	bindings:             [MAX_BINDINGS]Compiled_Binding,
}

/* command_registry_init copies and confirms one immutable command generation. */
command_registry_init :: proc(
	registry: ^Command_Registry,
	generation: Registry_Generation,
	definitions: []Command_Definition,
	allocator: runtime.Allocator,
) -> (ok: bool, failure: Failure_Context) {
	assert(registry != nil)
	if registry.state != nil || registry.closed || generation == Registry_Generation(0) {
		return false, Failure_Context{code = .Invalid_Registry, registry_generation = generation}
	}
	if allocator.procedure == nil {
		return false, Failure_Context {
			code = .Persistent_Memory_Limit,
			registry_generation = generation,
			limit = u64(size_of(Registry_Data)),
			actual = u64(size_of(Registry_Data)),
		}
	}
	if len(definitions) == 0 || len(definitions) > MAX_COMMANDS {
		return false, Failure_Context {
			code = .Command_Limit,
			registry_generation = generation,
			limit = MAX_COMMANDS,
			actual = u64(len(definitions)),
		}
	}

	data, allocation_error := new(Registry_Data, allocator)
	if allocation_error != nil {
		return false, Failure_Context {
			code = .Persistent_Memory_Limit,
			registry_generation = generation,
			limit = u64(size_of(Registry_Data)),
			actual = u64(size_of(Registry_Data)),
		}
	}
	data.state = .Ready
	data.generation = generation
	data.allocator = allocator
	data.storage_bytes = u64(size_of(Registry_Data))

	for definition, definition_index in definitions {
		failure = validate_command_definition(definition, generation)
		if failure.code != .None {
			free(data, allocator)
			return false, failure
		}
		for existing_index in 0 ..< definition_index {
			if entry_name(&data.entries[existing_index]) == definition.name {
				free(data, allocator)
				return false, Failure_Context {
					code = .Duplicate_Command,
					registry_generation = generation,
					actual = u64(definition_index),
				}
			}
			if command_route_is_valid(definition.route) &&
			   data.entries[existing_index].route == definition.route {
				free(data, allocator)
				return false, Failure_Context {
					code = .Duplicate_Route,
					registry_generation = generation,
					actual = u64(definition_index),
				}
			}
		}
		entry := &data.entries[definition_index]
		copy(entry.name[:len(definition.name)], transmute([]u8)definition.name)
		entry.name_count = u8(len(definition.name))
		copy(entry.description[:len(definition.description)], transmute([]u8)definition.description)
		entry.description_count = u16(len(definition.description))
		entry.handle = Command_Handle {
			registry_generation = generation,
			slot = u16(definition_index),
			entry_generation = 1,
		}
		entry.route = definition.route
		entry.implementation = definition.implementation
		entry.invocation = definition.invocation
		entry.text_requirement = definition.text_requirement
		entry.effects = definition.effects
		entry.interactive = definition.interactive
		entry.requirements = definition.requirements
		if command_provenance_present(definition.provenance) {
			copy_provenance(&entry.provenance, definition.provenance)
		}
		data.command_count += 1
	}

	registry.state = data
	return true, {}
}

/* command_registry_close releases an unreferenced registry and invalidates its handle. */
command_registry_close :: proc(
	registry: ^Command_Registry,
) -> (ok: bool, failure: Failure_Context) {
	assert(registry != nil)
	data := registry_data(registry)
	if data == nil || data.state != .Ready {
		return false, registry_failure(registry, .Invalid_Registry)
	}
	if data.retained_maps != 0 {
		return false, Failure_Context {
			code = .Retained_Snapshot,
			registry_generation = data.generation,
			limit = 0,
			actual = u64(data.retained_maps),
		}
	}
	data.state = .Closed
	allocator := data.allocator
	free(data, allocator)
	registry.state = nil
	registry.closed = true
	return true, {}
}

/* command_registry_stats reports confirmed occupancy and exact owned storage. */
command_registry_stats :: proc(
	registry: ^Command_Registry,
) -> (stats: Registry_Stats, ok: bool, failure: Failure_Context) {
	data := registry_data(registry)
	if data == nil || data.state != .Ready {
		return {}, false, registry_failure(registry, .Invalid_Registry)
	}
	return Registry_Stats {
		generation = data.generation,
		command_count = data.command_count,
		storage_bytes = data.storage_bytes,
	}, true, {}
}

/* command_lookup resolves one bounded UTF-8 name in the confirmed registry. */
command_lookup :: proc(
	registry: ^Command_Registry,
	name: string,
) -> (handle: Command_Handle, ok: bool, failure: Failure_Context) {
	data := registry_data(registry)
	if data == nil || data.state != .Ready {
		return {}, false, registry_failure(registry, .Invalid_Registry)
	}
	if !valid_bounded_text(name, MAX_COMMAND_NAME_BYTES, false) {
		return {}, false, Failure_Context {
			code = .Invalid_Name,
			registry_generation = data.generation,
			limit = MAX_COMMAND_NAME_BYTES,
			actual = u64(len(name)),
		}
	}
	for entry_index in 0 ..< int(data.command_count) {
		entry := &data.entries[entry_index]
		if entry_name(entry) == name {
			return entry.handle, true, {}
		}
	}
	return {}, false, Failure_Context {
		code = .Unknown_Command,
		registry_generation = data.generation,
	}
}

/* command_metadata validates a handle and returns registry-owned immutable metadata. */
command_metadata :: proc(
	registry: ^Command_Registry,
	handle: Command_Handle,
) -> (metadata: Command_Metadata, ok: bool, failure: Failure_Context) {
	data := registry_data(registry)
	if data == nil || data.state != .Ready {
		return {}, false, registry_failure(registry, .Invalid_Registry)
	}
	entry, entry_ok := resolve_command(data, handle)
	if !entry_ok {
		return {}, false, Failure_Context {
			code = .Invalid_Command,
			registry_generation = data.generation,
			command = handle,
		}
	}
	return Command_Metadata {
		handle = entry.handle,
		name = entry_name(entry),
		route = entry.route,
		implementation = entry.implementation,
		invocation = entry.invocation,
		text_requirement = entry.text_requirement,
		effects = entry.effects,
		description = entry_description(entry),
		interactive = entry.interactive,
		requirements = entry.requirements,
		provenance = command_entry_provenance(entry),
	}, true, {}
}

/* snapshot_compile privately validates, sorts, and atomically activates one keymap. */
snapshot_compile :: proc(
	snapshot: ^Resolution_Snapshot,
	registry: ^Command_Registry,
	generation: Snapshot_Generation,
	definition: Keymap_Definition,
	allocator: runtime.Allocator,
) -> (ok: bool, failure: Failure_Context) {
	assert(snapshot != nil)
	registry_state := registry_data(registry)
	if registry_state == nil || registry_state.state != .Ready {
		return false, registry_failure(registry, .Invalid_Registry)
	}
	if snapshot.closed || generation == Snapshot_Generation(0) {
		return false, Failure_Context {
			code = .Invalid_Snapshot,
			registry_generation = registry_state.generation,
			snapshot_generation = generation,
		}
	}
	current := snapshot_data(snapshot)
	if current != nil && current.generation == generation {
		return false, Failure_Context {
			code = .Generation_Limit,
			registry_generation = registry_state.generation,
			snapshot_generation = generation,
		}
	}
	if definition.registry_generation != registry_state.generation {
		return false, Failure_Context {
			code = .Stale_Registry,
			registry_generation = definition.registry_generation,
			snapshot_generation = generation,
		}
	}
	retained_without_current := registry_state.retained_maps
	if current != nil && current.registry == registry_state {
		assert(retained_without_current > 0)
		retained_without_current -= 1
	}
	if retained_without_current >= MAX_ACTIVE_SNAPSHOTS {
		return false, Failure_Context {
			code = .Snapshot_Limit,
			registry_generation = registry_state.generation,
			snapshot_generation = generation,
			limit = MAX_ACTIVE_SNAPSHOTS,
			actual = u64(retained_without_current) + 1,
		}
	}
	if len(definition.bindings) > MAX_BINDINGS {
		return false, Failure_Context {
			code = .Binding_Limit,
			registry_generation = registry_state.generation,
			snapshot_generation = generation,
			limit = MAX_BINDINGS,
			actual = u64(len(definition.bindings)),
		}
	}
	encoded_bytes := u64(len(definition.text_fallback_name))
	for binding in definition.bindings {
		encoded_bytes += u64(binding.stroke_count) * u64(size_of(Key_Stroke))
		encoded_bytes += u64(len(binding.command_name))
	}
	if encoded_bytes > MAX_KEYMAP_BYTES {
		return false, Failure_Context {
			code = .Keymap_Memory_Limit,
			registry_generation = registry_state.generation,
			snapshot_generation = generation,
			limit = MAX_KEYMAP_BYTES,
			actual = encoded_bytes,
		}
	}
	if allocator.procedure == nil || u64(size_of(Snapshot_Data)) > MAX_KEYMAP_BYTES {
		return false, Failure_Context {
			code = .Keymap_Memory_Limit,
			registry_generation = registry_state.generation,
			snapshot_generation = generation,
			limit = MAX_KEYMAP_BYTES,
			actual = u64(size_of(Snapshot_Data)),
		}
	}

	candidate, allocation_error := new(Snapshot_Data, allocator)
	if allocation_error != nil {
		return false, Failure_Context {
			code = .Persistent_Memory_Limit,
			registry_generation = registry_state.generation,
			snapshot_generation = generation,
			limit = MAX_KEYMAP_BYTES,
			actual = u64(size_of(Snapshot_Data)),
		}
	}
	candidate.state = .Ready
	candidate.generation = generation
	candidate.registry = registry_state
	candidate.registry_generation = registry_state.generation
	candidate.profile = Profile_Identity {
		id = Profile_ID(1),
		revision = Profile_Revision(1),
	}
	candidate.ctx = Context_Handle {
		id = Context_ID(1),
		generation = Context_Generation(generation),
	}
	candidate.map_count = 1
	candidate.active_map_count = 1
	candidate.inspection_limit = MAX_INSPECTION_ALTERNATIVES
	candidate.allocator = allocator
	candidate.storage_bytes = u64(size_of(Snapshot_Data))

	fallback, fallback_ok, fallback_failure := lookup_command_data(
		registry_state,
		definition.text_fallback_name,
	)
	if !fallback_ok {
		free(candidate, allocator)
		fallback_failure.code = .Missing_Text_Fallback
		fallback_failure.snapshot_generation = generation
		return false, fallback_failure
	}
	fallback_entry, fallback_entry_ok := resolve_command(registry_state, fallback)
	assert(fallback_entry_ok)
	if fallback_entry.invocation != .Text_Input ||
	   fallback_entry.text_requirement != .Required ||
	   fallback_entry.implementation != .Native {
		free(candidate, allocator)
		return false, Failure_Context {
			code = .Invalid_Text_Fallback,
			registry_generation = registry_state.generation,
			snapshot_generation = generation,
			command = fallback,
		}
	}
	candidate.text_fallback = fallback

	for binding, binding_index in definition.bindings {
		if binding.stroke_count == 0 || binding.stroke_count > MAX_SEQUENCE_STROKES {
			free(candidate, allocator)
			return false, Failure_Context {
				code = .Sequence_Limit,
				registry_generation = registry_state.generation,
				snapshot_generation = generation,
				binding_index = u32(binding_index),
				limit = MAX_SEQUENCE_STROKES,
				actual = u64(binding.stroke_count),
			}
		}
		for stroke_index in 0 ..< int(binding.stroke_count) {
			stroke := binding.strokes[stroke_index]
			if !key_stroke_is_valid(stroke) {
				free(candidate, allocator)
				return false, Failure_Context {
					code = .Invalid_Binding,
					registry_generation = registry_state.generation,
					snapshot_generation = generation,
					binding_index = u32(binding_index),
				}
			}
		}
		command, command_ok, command_failure := lookup_command_data(
			registry_state,
			binding.command_name,
		)
		if !command_ok {
			free(candidate, allocator)
			command_failure.snapshot_generation = generation
			command_failure.binding_index = u32(binding_index)
			return false, command_failure
		}
		entry, entry_ok := resolve_command(registry_state, command)
		assert(entry_ok)
		compiled := &candidate.bindings[binding_index]
		compiled.strokes = binding.strokes
		compiled.stroke_count = binding.stroke_count
		compiled.command = command
		candidate.binding_count += 1
		if entry.invocation == .Cancellation {
			if binding.stroke_count != 1 || candidate.has_cancellation {
				free(candidate, allocator)
				return false, Failure_Context {
					code = .Invalid_Binding,
					registry_generation = registry_state.generation,
					snapshot_generation = generation,
					binding_index = u32(binding_index),
				}
			}
			candidate.cancellation_command = command
			candidate.has_cancellation = true
		}
	}

	slice.sort_by(candidate.bindings[:candidate.binding_count], binding_less)
	for index in 1 ..< int(candidate.binding_count) {
		previous := candidate.bindings[index - 1]
		current_binding := candidate.bindings[index]
		if sequence_equal(previous, current_binding) {
			free(candidate, allocator)
			return false, Failure_Context {
				code = .Duplicate_Binding,
				registry_generation = registry_state.generation,
				snapshot_generation = generation,
				binding_index = u32(index),
			}
		}
		if sequence_prefix(previous, current_binding) {
			free(candidate, allocator)
			return false, Failure_Context {
				code = .Ambiguous_Binding,
				registry_generation = registry_state.generation,
				snapshot_generation = generation,
				binding_index = u32(index),
			}
		}
	}

	registry_state.retained_maps += 1
	snapshot.state = candidate
	if current != nil {
		release_snapshot_data(current)
	}
	return true, {}
}

/* snapshot_close releases compiled storage and invalidates the snapshot handle. */
snapshot_close :: proc(
	snapshot: ^Resolution_Snapshot,
) -> (ok: bool, failure: Failure_Context) {
	assert(snapshot != nil)
	data := snapshot_data(snapshot)
	if data == nil || data.state != .Ready {
		return false, snapshot_failure(snapshot, .Invalid_Snapshot)
	}
	generation := data.generation
	registry_generation := data.registry_generation
	snapshot.state = nil
	snapshot.closed = true
	release_snapshot_data(data)
	return true, Failure_Context {
		registry_generation = registry_generation,
		snapshot_generation = generation,
	}
}

/* snapshot_stats reports immutable compiled-map occupancy and exact storage. */
snapshot_stats :: proc(
	snapshot: ^Resolution_Snapshot,
) -> (stats: Snapshot_Stats, ok: bool, failure: Failure_Context) {
	data := snapshot_data(snapshot)
	if data == nil || data.state != .Ready {
		return {}, false, snapshot_failure(snapshot, .Invalid_Snapshot)
	}
	return Snapshot_Stats {
		generation = data.generation,
		registry_generation = data.registry_generation,
		binding_count = data.binding_count,
		storage_bytes = data.storage_bytes,
		profile = data.profile,
		ctx = data.ctx,
		map_count = data.map_count,
		active_map_count = data.active_map_count,
	}, true, {}
}

/* resolve_input resolves one event without allocation and updates bounded pending state. */
resolve_input :: proc(
	snapshot: ^Resolution_Snapshot,
	registry_generation: Registry_Generation,
	pending: ^Pending_State,
	input: Input,
) -> (resolution: Resolution, failure: Failure_Context) {
	assert(pending != nil)
	data := snapshot_data(snapshot)
	if data == nil || data.state != .Ready {
		return Resolution{kind = .Rejected}, snapshot_failure(snapshot, .Invalid_Snapshot)
	}
	base_failure := Failure_Context {
		registry_generation = registry_generation,
		snapshot_generation = data.generation,
	}
	if registry_generation != data.registry_generation {
		base_failure.code = .Stale_Registry
		return Resolution{kind = .Rejected}, base_failure
	}
	if pending.stroke_count > 0 && pending.snapshot_generation != data.generation {
		pending^ = {}
		base_failure.code = .Stale_Snapshot
		return Resolution{kind = .Rejected}, base_failure
	}
	if !input_is_valid(input) {
		base_failure.code = input_failure_code(input)
		base_failure.limit = MAX_TEXT_BYTES
		base_failure.actual = u64(len(input.text))
		return Resolution{kind = .Rejected}, base_failure
	}

	if input.kind == .Text_Commit {
		if data.layered {
			policy, compiled_map := layered_unmatched_input_policy(data)
			switch policy {
			case .Reject:
				return Resolution{kind = .Rejected}, layered_input_rejected_failure(data, compiled_map)
			case .Fallthrough:
				return Resolution{kind = .Unbound}, {}
			case .Text_Input:
			case .Invalid:
				unreachable()
			}
		}
		return Resolution {
			kind = .Command,
			command = data.text_fallback,
			text = input.text,
		}, {}
	}

	if data.has_cancellation {
		cancel_binding, cancel_ok := exact_single_stroke(data, input.stroke)
		if cancel_ok && resolved_command(data, cancel_binding.command) == data.cancellation_command {
			pending^ = {}
			return Resolution{kind = .Command, command = cancel_binding.command}, {}
		}
	}

	had_pending := pending.stroke_count > 0
	if pending.stroke_count >= MAX_SEQUENCE_STROKES {
		pending^ = {}
		base_failure.code = .Sequence_Limit
		base_failure.limit = MAX_SEQUENCE_STROKES
		base_failure.actual = u64(MAX_SEQUENCE_STROKES) + 1
		return Resolution{kind = .Rejected}, base_failure
	}
	query := Compiled_Binding {
		strokes = pending.strokes,
		stroke_count = pending.stroke_count + 1,
	}
	query.strokes[pending.stroke_count] = input.stroke

	exact, prefix, masked := find_active_sequence(data, query)
	if masked {
		pending^ = {}
		return Resolution{kind = .Unbound}, {}
	}
	if exact != nil {
		pending^ = {}
		return Resolution{kind = .Command, command = resolved_command(data, exact.command)}, {}
	}
	if prefix {
		pending.snapshot_generation = data.generation
		pending.strokes = query.strokes
		pending.stroke_count = query.stroke_count
		return Resolution{kind = .Pending}, {}
	}
	pending^ = {}
	if !had_pending && len(input.text) > 0 {
		if data.layered {
			policy, compiled_map := layered_unmatched_input_policy(data)
			switch policy {
			case .Reject:
				return Resolution{kind = .Rejected}, layered_input_rejected_failure(data, compiled_map)
			case .Fallthrough:
				return Resolution{kind = .Unbound}, {}
			case .Text_Input:
			case .Invalid:
				unreachable()
			}
		}
		return Resolution {
			kind = .Command,
			command = data.text_fallback,
			text = input.text,
		}, {}
	}
	return Resolution{kind = .Unbound}, {}
}

@(private)
layered_input_rejected_failure :: proc(
	data: ^Snapshot_Data,
	compiled_map: ^Compiled_Map,
) -> Failure_Context {
	assert(compiled_map != nil)
	return Failure_Context {
		code = .Context_Input_Rejected,
		registry_generation = data.registry_generation,
		snapshot_generation = data.generation,
		profile = data.profile,
		ctx = data.ctx,
		owner = compiled_map.owner,
		map_identity = compiled_map.identity,
	}
}

/* pending_clear clears one pending sequence without touching a snapshot or editor state. */
pending_clear :: proc(pending: ^Pending_State) {
	assert(pending != nil)
	pending^ = {}
}

@(private)
validate_command_definition :: proc(
	definition: Command_Definition,
	generation: Registry_Generation,
) -> Failure_Context {
	if !valid_bounded_text(definition.name, MAX_COMMAND_NAME_BYTES, false) {
		return Failure_Context {
			code = .Invalid_Name,
			registry_generation = generation,
			limit = MAX_COMMAND_NAME_BYTES,
			actual = u64(len(definition.name)),
		}
	}
	if !valid_bounded_text(definition.description, MAX_COMMAND_DESCRIPTION_BYTES, true) {
		return Failure_Context {
			code = .Invalid_Description,
			registry_generation = generation,
			limit = MAX_COMMAND_DESCRIPTION_BYTES,
			actual = u64(len(definition.description)),
		}
	}
	if definition.implementation == .Invalid {
		return Failure_Context{code = .Invalid_Implementation, registry_generation = generation}
	}
	if !command_route_is_valid(definition.route) {
		return Failure_Context{code = .Invalid_Route, registry_generation = generation}
	}
	if definition.invocation == .Invalid {
		return Failure_Context{code = .Invalid_Command, registry_generation = generation}
	}
	if definition.text_requirement == .Invalid {
		return Failure_Context{code = .Invalid_Text_Requirement, registry_generation = generation}
	}
	if definition.invocation == .Text_Input && definition.text_requirement != .Required {
		return Failure_Context{code = .Invalid_Text_Requirement, registry_generation = generation}
	}
	if definition.invocation == .Cancellation && definition.text_requirement != .Prohibited {
		return Failure_Context{code = .Invalid_Text_Requirement, registry_generation = generation}
	}
	if definition.interactive && !provenance_valid(definition.provenance) {
		return Failure_Context{code = .Invalid_Provenance, registry_generation = generation}
	}
	if command_provenance_present(definition.provenance) && !provenance_valid(definition.provenance) {
		return Failure_Context{code = .Invalid_Provenance, registry_generation = generation}
	}
	return {}
}

/* command_route_is_valid reports whether a provider assigned a nonzero route. */
command_route_is_valid :: proc(route: Command_Route) -> bool {
	return route.provider != Command_Provider_ID(0) && route.operation != 0
}

@(private)
command_provenance_present :: proc(provenance: Definition_Provenance) -> bool {
	return len(provenance.provider) != 0 || len(provenance.source) != 0 || len(provenance.location) != 0
}

@(private)
valid_bounded_text :: proc(value: string, limit: int, empty_allowed: bool) -> bool {
	return (empty_allowed || len(value) > 0) && len(value) <= limit && utf8.valid_string(value)
}

@(private)
key_stroke_is_valid :: proc(stroke: Key_Stroke) -> bool {
	if stroke.kind == .Invalid {
		return false
	}
	if stroke.kind == .Unicode_Scalar {
		return utf8.valid_rune(stroke.scalar) && unicode.is_graphic(stroke.scalar)
	}
	return stroke.scalar == rune(0)
}

@(private)
input_is_valid :: proc(input: Input) -> bool {
	if len(input.text) > MAX_TEXT_BYTES || !utf8.valid_string(input.text) {
		return false
	}
	switch input.kind {
	case .Key:
		return key_stroke_is_valid(input.stroke) && input.pointer == Pointer_Event{}
	case .Text_Commit:
		return len(input.text) > 0 && input.stroke == Key_Stroke{} && input.pointer == Pointer_Event{}
	case .Pointer:
		return len(input.text) == 0 && input.stroke == Key_Stroke{} &&
			pointer_event_is_valid(input.pointer)
	case .Invalid:
		return false
	}
	return false
}

@(private)
input_failure_code :: proc(input: Input) -> Failure_Code {
	if len(input.text) > MAX_TEXT_BYTES {
		return .Text_Limit
	}
	if !utf8.valid_string(input.text) {
		return .Malformed_Text
	}
	return .Invalid_Input
}

@(private)
registry_data :: proc(registry: ^Command_Registry) -> ^Registry_Data {
	if registry == nil || registry.state == nil || registry.closed {
		return nil
	}
	return (^Registry_Data)(registry.state)
}

@(private)
snapshot_data :: proc(snapshot: ^Resolution_Snapshot) -> ^Snapshot_Data {
	if snapshot == nil || snapshot.state == nil || snapshot.closed {
		return nil
	}
	return (^Snapshot_Data)(snapshot.state)
}

@(private)
registry_failure :: proc(registry: ^Command_Registry, code: Failure_Code) -> Failure_Context {
	data := registry_data(registry)
	generation := Registry_Generation(0)
	if data != nil {
		generation = data.generation
	}
	return Failure_Context{code = code, registry_generation = generation}
}

@(private)
snapshot_failure :: proc(snapshot: ^Resolution_Snapshot, code: Failure_Code) -> Failure_Context {
	data := snapshot_data(snapshot)
	if data == nil {
		return Failure_Context{code = code}
	}
	return Failure_Context {
		code = code,
		registry_generation = data.registry_generation,
		snapshot_generation = data.generation,
	}
}

@(private)
entry_name :: proc(entry: ^Command_Entry) -> string {
	return string(entry.name[:entry.name_count])
}

@(private)
entry_description :: proc(entry: ^Command_Entry) -> string {
	return string(entry.description[:entry.description_count])
}

@(private)
command_entry_provenance :: proc(entry: ^Command_Entry) -> Definition_Provenance {
	return Definition_Provenance {
		provider = string(entry.provenance.provider[:entry.provenance.provider_count]),
		source = string(entry.provenance.source[:entry.provenance.source_count]),
		location = string(entry.provenance.location[:entry.provenance.location_count]),
	}
}

@(private)
resolve_command :: proc(
	data: ^Registry_Data,
	handle: Command_Handle,
) -> (^Command_Entry, bool) {
	if handle.registry_generation != data.generation ||
	   handle.entry_generation != 1 || handle.slot >= data.command_count {
		return nil, false
	}
	entry := &data.entries[handle.slot]
	return entry, entry.handle == handle
}

@(private)
lookup_command_data :: proc(
	data: ^Registry_Data,
	name: string,
) -> (Command_Handle, bool, Failure_Context) {
	if !valid_bounded_text(name, MAX_COMMAND_NAME_BYTES, false) {
		return {}, false, Failure_Context {
			code = .Invalid_Name,
			registry_generation = data.generation,
			limit = MAX_COMMAND_NAME_BYTES,
			actual = u64(len(name)),
		}
	}
	for entry_index in 0 ..< int(data.command_count) {
		entry := &data.entries[entry_index]
		if entry_name(entry) == name {
			return entry.handle, true, {}
		}
	}
	return {}, false, Failure_Context {
		code = .Unknown_Command,
		registry_generation = data.generation,
	}
}

@(private)
release_snapshot_data :: proc(data: ^Snapshot_Data) {
	assert(data != nil && data.state == .Ready)
	assert(data.registry != nil && data.registry.retained_maps > 0)
	data.registry.retained_maps -= 1
	data.state = .Closed
	allocator := data.allocator
	if data.layered_bindings != nil {
		delete(data.layered_bindings, allocator)
	}
	if data.layered_remaps != nil {
		delete(data.layered_remaps, allocator)
	}
	if data.layered_trie_nodes != nil {
		delete(data.layered_trie_nodes, allocator)
	}
	if data.layered_maps != nil {
		delete(data.layered_maps, allocator)
	}
	free(data, allocator)
}

@(private)
resolved_command :: proc(data: ^Snapshot_Data, command: Command_Handle) -> Command_Handle {
	if data.layered {
		return layered_remapped_command(data, command)
	}
	return command
}

@(private)
find_active_sequence :: proc(
	data: ^Snapshot_Data,
	query: Compiled_Binding,
) -> (exact: ^Compiled_Binding, prefix, masked: bool) {
	if data.layered {
		layered_exact, layered_prefix, layered_masked := layered_find_sequence(data, query)
		return layered_exact, layered_prefix, layered_masked
	}
	exact, prefix = find_sequence(data, query)
	return exact, prefix, false
}

@(private)
binding_less :: proc(left, right: Compiled_Binding) -> bool {
	return sequence_compare(left, right) < 0
}

@(private)
sequence_compare :: proc(left, right: Compiled_Binding) -> int {
	shared := min(left.stroke_count, right.stroke_count)
	for index in 0 ..< int(shared) {
		comparison := stroke_compare(left.strokes[index], right.strokes[index])
		if comparison != 0 {
			return comparison
		}
	}
	if left.stroke_count < right.stroke_count {
		return -1
	}
	if left.stroke_count > right.stroke_count {
		return 1
	}
	return 0
}

@(private)
stroke_compare :: proc(left, right: Key_Stroke) -> int {
	if left.kind != right.kind {
		return int(left.kind) - int(right.kind)
	}
	if left.scalar != right.scalar {
		if left.scalar < right.scalar {
			return -1
		}
		return 1
	}
	return int(transmute(u8)left.modifiers) - int(transmute(u8)right.modifiers)
}

@(private)
sequence_equal :: proc(left, right: Compiled_Binding) -> bool {
	return sequence_compare(left, right) == 0
}

@(private)
sequence_prefix :: proc(prefix, value: Compiled_Binding) -> bool {
	if prefix.stroke_count >= value.stroke_count {
		return false
	}
	for index in 0 ..< int(prefix.stroke_count) {
		if prefix.strokes[index] != value.strokes[index] {
			return false
		}
	}
	return true
}

@(private)
find_sequence :: proc(
	data: ^Snapshot_Data,
	query: Compiled_Binding,
) -> (exact: ^Compiled_Binding, prefix: bool) {
	low := 0
	high := int(data.binding_count)
	for low < high {
		middle := low + (high - low) / 2
		if sequence_compare(data.bindings[middle], query) < 0 {
			low = middle + 1
		} else {
			high = middle
		}
	}
	if low >= int(data.binding_count) {
		return nil, false
	}
	binding := &data.bindings[low]
	comparison := sequence_compare(binding^, query)
	if comparison == 0 {
		return binding, false
	}
	return nil, sequence_prefix(query, binding^)
}

@(private)
exact_single_stroke :: proc(
	data: ^Snapshot_Data,
	stroke: Key_Stroke,
) -> (^Compiled_Binding, bool) {
	query := Compiled_Binding{stroke_count = 1}
	query.strokes[0] = stroke
	binding, _, masked := find_active_sequence(data, query)
	if masked {
		return nil, false
	}
	return binding, binding != nil
}
