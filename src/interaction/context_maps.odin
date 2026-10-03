// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "base:runtime"

/* MAX_CONTEXT_MAPS bounds simultaneously active language, component, and transient maps. */
MAX_CONTEXT_MAPS :: 8
/* MAX_CONTEXT_BINDINGS bounds one contextual interaction grammar. */
MAX_CONTEXT_BINDINGS :: 128

/* Context_Map_End records why one checked contextual owner left the active stack. */
Context_Map_End :: enum u8 {
	Invalid,
	Completed,
	Cancelled,
	Invalidated,
}

/* Context_Map_Definition borrows one bounded contextual grammar during activation. */
Context_Map_Definition :: struct {
	identity:              Map_Identity,
	name:                  string,
	owner_id:              Owner_ID,
	precedence:            Precedence_Class,
	priority:              i32,
	bindings:              []Binding_Definition,
	text_fallback_name:    string,
	unmatched_input_policy: Unmatched_Input_Policy,
}

/* Context_Map_Handle identifies one exact active owner and context generation. */
Context_Map_Handle :: struct {
	identity: Map_Identity,
	ctx:      Context_Handle,
	owner:    Owner_Handle,
	slot:     u8,
}

/* Context_Map_Result reports one activation or terminal lifecycle transition. */
Context_Map_Result :: struct {
	handle: Context_Map_Handle,
	end:    Context_Map_End,
}

/* Context_Pending_State owns one unresolved sequence in one contextual map. */
Context_Pending_State :: struct {
	context_generation: Context_Generation,
	owner:              Owner_Handle,
	map_identity:       Map_Identity,
	strokes:            [MAX_SEQUENCE_STROKES]Key_Stroke,
	stroke_count:       u8,
}

/* Context_Map_Stats reports active occupancy and the current checked generation. */
Context_Map_Stats :: struct {
	ctx:          Context_Handle,
	active_maps: u8,
	storage_bytes: u64,
}

/* Context_Map_Stack owns bounded compiled language, component, and transient maps. */
Context_Map_Stack :: struct {
	state: rawptr,
}

@(private)
Context_Map_State :: struct {
	active:                 bool,
	handle:                 Context_Map_Handle,
	name:                   [MAX_IDENTITY_BYTES]u8,
	name_count:             u16,
	precedence:             Precedence_Class,
	priority:               i32,
	unmatched_input_policy: Unmatched_Input_Policy,
	binding_count:          u8,
	bindings:               [MAX_CONTEXT_BINDINGS]Compiled_Binding,
	text_fallback:          Command_Handle,
	has_text_fallback:      bool,
}

@(private)
Context_Map_Stack_State :: struct {
	context_id:       Context_ID,
	context_generation: Context_Generation,
	registry:         ^Registry_Data,
	registry_generation: Registry_Generation,
	owner_generations: [MAX_CONTEXT_MAPS]Owner_Generation,
	maps:             [MAX_CONTEXT_MAPS]Context_Map_State,
	order:            [MAX_CONTEXT_MAPS]u8,
	active_count:     u8,
	allocator:        runtime.Allocator,
}

/* context_map_stack_init creates one empty checked contextual-map owner. */
context_map_stack_init :: proc(
	stack: ^Context_Map_Stack,
	context_id: Context_ID,
	registry: ^Command_Registry,
	allocator := context.allocator,
) -> (ok: bool, failure: Failure_Context) {
	assert(stack != nil)
	assert(stack.state == nil, "context map stack is already initialized")
	registry_state := registry_data(registry)
	if context_id == Context_ID(0) || registry_state == nil || registry_state.state != .Ready {
		return false, registry_failure(registry, .Invalid_Registry)
	}
	if allocator.procedure == nil {
		return false, Failure_Context {
			code = .Persistent_Memory_Limit,
			actual = u64(size_of(Context_Map_Stack_State)),
		}
	}
	state, allocation_error := new(Context_Map_Stack_State, allocator)
	if allocation_error != nil {
		return false, Failure_Context {
			code = .Persistent_Memory_Limit,
			actual = u64(size_of(Context_Map_Stack_State)),
		}
	}
	state.context_id = context_id
	state.context_generation = 1
	state.registry = registry_state
	state.registry_generation = registry_state.generation
	state.allocator = allocator
	stack.state = state
	return true, {}
}

/* context_map_activate validates, copies, orders, and publishes one contextual map. */
context_map_activate :: proc(
	stack: ^Context_Map_Stack,
	definition: Context_Map_Definition,
	context_pending: ^Context_Pending_State,
	base_pending: ^Pending_State,
) -> (result: Context_Map_Result, ok: bool, failure: Failure_Context) {
	assert(context_pending != nil)
	assert(base_pending != nil)
	state := context_map_stack_state(stack)
	if state == nil || state.registry == nil || state.registry.state != .Ready {
		return {}, false, Failure_Context{code = .Invalid_Context}
	}
	if state.registry.generation != state.registry_generation {
		return {}, false, Failure_Context {
			code = .Stale_Registry,
			registry_generation = state.registry_generation,
		}
	}
	if !context_map_definition_valid(definition) {
		return {}, false, Failure_Context {
			code = .Invalid_Context_Map,
			map_identity = definition.identity,
		}
	}
	if state.active_count >= MAX_CONTEXT_MAPS {
		return {}, false, Failure_Context {
			code = .Context_Map_Limit,
			limit = MAX_CONTEXT_MAPS,
			actual = u64(state.active_count) + 1,
		}
	}
	for active in state.maps {
		if active.active && (active.handle.identity.id == definition.identity.id ||
		   active.handle.owner.id == definition.owner_id) {
			return {}, false, Failure_Context {
				code = .Invalid_Context_Map,
				map_identity = definition.identity,
				owner = active.handle.owner,
			}
		}
	}

	slot := -1
	for candidate, index in state.maps {
		if !candidate.active {
			slot = index
			break
		}
	}
	assert(slot >= 0)
	candidate: Context_Map_State
	copy(candidate.name[:len(definition.name)], transmute([]u8)definition.name)
	candidate.name_count = u16(len(definition.name))
	candidate.precedence = definition.precedence
	candidate.priority = definition.priority
	candidate.unmatched_input_policy = definition.unmatched_input_policy
	for binding, binding_index in definition.bindings {
		if binding.stroke_count == 0 || binding.stroke_count > MAX_SEQUENCE_STROKES {
			return {}, false, Failure_Context {
				code = .Sequence_Limit,
				binding_index = u32(binding_index),
				limit = MAX_SEQUENCE_STROKES,
				actual = u64(binding.stroke_count),
			}
		}
		sequence := Key_Sequence{strokes = binding.strokes, stroke_count = binding.stroke_count}
		if !sequence_valid(sequence) {
			return {}, false, Failure_Context {
				code = .Invalid_Binding,
				binding_index = u32(binding_index),
			}
		}
		for protected in protected_binding_catalog() {
			if key_sequences_overlap(sequence, protected.sequence) {
				return {}, false, Failure_Context {
					code = .Protected_Binding,
					map_identity = definition.identity,
					binding_index = u32(binding_index),
					stroke_count = sequence.stroke_count,
				}
			}
		}
		command, found, lookup_failure := lookup_command_data(state.registry, binding.command_name)
		if !found {
			lookup_failure.binding_index = u32(binding_index)
			return {}, false, lookup_failure
		}
		candidate.bindings[binding_index] = Compiled_Binding {
			strokes = binding.strokes,
			stroke_count = binding.stroke_count,
			command = command,
		}
		candidate.binding_count += 1
	}
	context_binding_sort(candidate.bindings[:candidate.binding_count])
	for index in 1 ..< int(candidate.binding_count) {
		previous := candidate.bindings[index - 1]
		current := candidate.bindings[index]
		comparison := sequence_compare(previous, current)
		if comparison == 0 || sequence_prefix(previous, current) {
			return {}, false, Failure_Context {
				code = .Ambiguous_Binding,
				binding_index = u32(index),
			}
		}
	}
	if definition.unmatched_input_policy == .Text_Input {
		fallback, found, lookup_failure := lookup_command_data(
			state.registry,
			definition.text_fallback_name,
		)
		if !found {
			return {}, false, lookup_failure
		}
		entry, entry_ok := resolve_command(state.registry, fallback)
		assert(entry_ok)
		if entry.invocation != .Text_Input || entry.text_requirement != .Required {
			return {}, false, Failure_Context{code = .Invalid_Text_Fallback, command = fallback}
		}
		candidate.text_fallback = fallback
		candidate.has_text_fallback = true
	}
	if conflict := context_map_conflict(state, &candidate); conflict.code != .None {
		conflict.map_identity = definition.identity
		return {}, false, conflict
	}

	next_context_generation := Context_Generation(u64(state.context_generation) + 1)
	next_owner_generation := Owner_Generation(u64(state.owner_generations[slot]) + 1)
	if next_context_generation == Context_Generation(0) || next_owner_generation == Owner_Generation(0) {
		return {}, false, Failure_Context{code = .Generation_Limit}
	}
	state.context_generation = next_context_generation
	state.owner_generations[slot] = next_owner_generation
	candidate.handle = Context_Map_Handle {
		identity = definition.identity,
		ctx = Context_Handle{id = state.context_id, generation = next_context_generation},
		owner = Owner_Handle{id = definition.owner_id, generation = next_owner_generation},
		slot = u8(slot),
	}
	candidate.active = true
	state.maps[slot] = candidate
	state.active_count += 1
	context_map_rebuild_order(state)
	context_pending^ = {}
	pending_clear(base_pending)
	return Context_Map_Result{handle = candidate.handle}, true, {}
}

/* context_map_end removes one exact owner and clears generation-bound pending input. */
context_map_end :: proc(
	stack: ^Context_Map_Stack,
	handle: Context_Map_Handle,
	end: Context_Map_End,
	context_pending: ^Context_Pending_State,
	base_pending: ^Pending_State,
) -> (result: Context_Map_Result, ok: bool, failure: Failure_Context) {
	assert(context_pending != nil)
	assert(base_pending != nil)
	state := context_map_stack_state(stack)
	if state == nil || end == .Invalid || int(handle.slot) >= MAX_CONTEXT_MAPS {
		return {}, false, Failure_Context{code = .Invalid_Context}
	}
	active := &state.maps[handle.slot]
	if !active.active || active.handle != handle {
		code := Failure_Code.Stale_Owner
		if !owner_handle_valid(handle.owner) {
			code = .Invalid_Owner
		}
		return {}, false, Failure_Context {
			code = code,
			ctx = handle.ctx,
			owner = handle.owner,
			map_identity = handle.identity,
		}
	}
	next_generation := Context_Generation(u64(state.context_generation) + 1)
	if next_generation == Context_Generation(0) {
		return {}, false, Failure_Context{code = .Generation_Limit}
	}
	active^ = {}
	state.active_count -= 1
	state.context_generation = next_generation
	context_map_rebuild_order(state)
	context_pending^ = {}
	pending_clear(base_pending)
	return Context_Map_Result{handle = handle, end = end}, true, {}
}

/* context_map_owner_invalidate closes one active owner without accepting completion. */
context_map_owner_invalidate :: proc(
	stack: ^Context_Map_Stack,
	owner: Owner_Handle,
	context_pending: ^Context_Pending_State,
	base_pending: ^Pending_State,
) -> (result: Context_Map_Result, ok: bool, failure: Failure_Context) {
	state := context_map_stack_state(stack)
	if state == nil || !owner_handle_valid(owner) {
		return {}, false, Failure_Context{code = .Invalid_Owner, owner = owner}
	}
	for active in &state.maps {
		if active.active && active.handle.owner == owner {
			return context_map_end(
				stack,
				active.handle,
				.Invalidated,
				context_pending,
				base_pending,
			)
		}
	}
	return {}, false, Failure_Context{code = .Stale_Owner, owner = owner}
}

/* resolve_contextual_input routes active context maps before the global snapshot. */
resolve_contextual_input :: proc(
	stack: ^Context_Map_Stack,
	snapshot: ^Resolution_Snapshot,
	registry_generation: Registry_Generation,
	context_pending: ^Context_Pending_State,
	base_pending: ^Pending_State,
	input: Input,
) -> (resolution: Resolution, failure: Failure_Context) {
	assert(context_pending != nil)
	assert(base_pending != nil)
	state := context_map_stack_state(stack)
	if state == nil {
		return Resolution{kind = .Rejected}, Failure_Context{code = .Invalid_Context}
	}
	if state.registry_generation != registry_generation || state.registry.generation != registry_generation {
		return Resolution{kind = .Rejected}, Failure_Context {
			code = .Stale_Registry,
			registry_generation = registry_generation,
		}
	}
	if !input_is_valid(input) {
		return Resolution{kind = .Rejected}, Failure_Context {
			code = input_failure_code(input),
			limit = MAX_TEXT_BYTES,
			actual = u64(len(input.text)),
		}
	}
	protected, protected_match, protected_failure := resolve_protected_input(
		snapshot,
		registry_generation,
		input,
	)
	if protected_failure.code != .None {
		return Resolution{kind = .Rejected}, protected_failure
	}
	if protected_match {
		context_pending^ = {}
		pending_clear(base_pending)
		return protected, {}
	}
	if context_pending.stroke_count > 0 {
		active := context_map_find_pending_owner(state, context_pending)
		if active == nil {
			context_pending^ = {}
			return Resolution{kind = .Rejected}, Failure_Context {
				code = .Stale_Owner,
				owner = context_pending.owner,
				map_identity = context_pending.map_identity,
			}
		}
		prior := context_pending^
		resolved, _, pending_failure := context_map_resolve_one(active, context_pending, input)
		if pending_failure.code == .None && resolved.kind == .Unbound &&
		   active.unmatched_input_policy == .Fallthrough {
			for index in 0 ..< int(prior.stroke_count) {
				resolved, pending_failure = resolve_input(
					snapshot,
					registry_generation,
					base_pending,
					Input{kind = .Key, stroke = prior.strokes[index]},
				)
				if pending_failure.code != .None || resolved.kind != .Pending {
					return resolved, pending_failure
				}
			}
			return resolve_input(snapshot, registry_generation, base_pending, input)
		}
		return resolved, pending_failure
	}
	if base_pending.stroke_count > 0 {
		return resolve_input(snapshot, registry_generation, base_pending, input)
	}
	for order_index in 0 ..< int(state.active_count) {
		active := &state.maps[state.order[order_index]]
		resolved, owns_input, map_failure := context_map_try_resolve(active, context_pending, input)
		if map_failure.code != .None || owns_input {
			if resolved.kind != .Unbound {
				pending_clear(base_pending)
			}
			return resolved, map_failure
		}
	}
	context_pending^ = {}
	return resolve_input(snapshot, registry_generation, base_pending, input)
}

/* resolve_protected_input resolves one exact protected logical stroke before contextual maps. */
resolve_protected_input :: proc(
	snapshot: ^Resolution_Snapshot,
	registry_generation: Registry_Generation,
	input: Input,
) -> (resolution: Resolution, matched: bool, failure: Failure_Context) {
	data := snapshot_data(snapshot)
	if data == nil || data.state != .Ready {
		return {}, false, {}
	}
	if registry_generation != data.registry_generation {
		return Resolution{kind = .Rejected}, false, Failure_Context {
			code = .Stale_Registry,
			registry_generation = registry_generation,
			snapshot_generation = data.generation,
		}
	}
	if input.kind != .Key {
		return {}, false, {}
	}
	query := Compiled_Binding {
		strokes = {0 = input.stroke},
		stroke_count = 1,
	}
	if !data.layered {
		binding, _ := find_sequence(data, query)
		if binding == nil {
			return {}, false, {}
		}
		entry, entry_ok := resolve_command(data.registry, binding.command)
		if !entry_ok {
			return Resolution{kind = .Rejected}, false, Failure_Context {
				code = .Invalid_Command,
				registry_generation = data.registry_generation,
				snapshot_generation = data.generation,
			}
		}
		for protected in protected_binding_catalog() {
			if key_sequences_overlap(
				Key_Sequence{strokes = query.strokes, stroke_count = query.stroke_count},
				protected.sequence,
			) && entry_name(entry) == protected.command_name {
				return Resolution{kind = .Command, command = binding.command}, true, {}
			}
		}
		return {}, false, {}
	}
	for compiled_map in &data.layered_maps {
		if !compiled_map.active || compiled_map.identity.id != PROTECTED_RECOVERY_MAP_ID {
			continue
		}
		start := int(compiled_map.binding_start)
		end := start + int(compiled_map.binding_count)
		for binding_index in start ..< end {
			binding := &data.layered_bindings[binding_index]
			if sequence_compare(binding.compiled, query) == 0 {
				return Resolution {
					kind = .Command,
					command = binding.compiled.command,
				}, true, {}
			}
		}
		return {}, false, {}
	}
	return {}, false, {}
}

/* context_map_stats reports exact fixed storage and active occupancy. */
context_map_stats :: proc(stack: ^Context_Map_Stack) -> (stats: Context_Map_Stats, ok: bool) {
	state := context_map_stack_state(stack)
	if state == nil {
		return {}, false
	}
	return Context_Map_Stats {
		ctx = Context_Handle{id = state.context_id, generation = state.context_generation},
		active_maps = state.active_count,
		storage_bytes = u64(size_of(Context_Map_Stack_State)),
	}, true
}

/* context_map_handle_is_valid reports whether a handle has complete nonzero identity. */
context_map_handle_is_valid :: proc(handle: Context_Map_Handle) -> bool {
	return map_identity_valid(handle.identity) && context_handle_valid(handle.ctx) &&
		owner_handle_valid(handle.owner) && int(handle.slot) < MAX_CONTEXT_MAPS
}

/* context_map_handle_is_active reports whether the stack still owns one exact handle. */
context_map_handle_is_active :: proc(
	stack: ^Context_Map_Stack,
	handle: Context_Map_Handle,
) -> bool {
	state := context_map_stack_state(stack)
	if state == nil || !context_map_handle_is_valid(handle) {
		return false
	}
	active := &state.maps[handle.slot]
	return active.active && active.handle == handle
}

/* context_map_stack_close invalidates all owners and releases fixed stack storage. */
context_map_stack_close :: proc(stack: ^Context_Map_Stack) -> (ok: bool, failure: Failure_Context) {
	state := context_map_stack_state(stack)
	if state == nil {
		return false, Failure_Context{code = .Invalid_Context}
	}
	allocator := state.allocator
	stack.state = nil
	free(state, allocator)
	return true, {}
}

@(private)
context_map_try_resolve :: proc(
	active: ^Context_Map_State,
	pending: ^Context_Pending_State,
	input: Input,
) -> (resolution: Resolution, owns_input: bool, failure: Failure_Context) {
	if input.kind == .Text_Commit {
		switch active.unmatched_input_policy {
		case .Fallthrough: return Resolution{kind = .Unbound}, false, {}
		case .Text_Input:
			assert(active.has_text_fallback)
			return Resolution{kind = .Command, command = active.text_fallback, text = input.text}, true, {}
		case .Reject:
			return Resolution{kind = .Rejected}, true, context_map_rejected_failure(active)
		case .Invalid:
			return Resolution{kind = .Rejected}, true, Failure_Context{code = .Invalid_Context_Map}
		}
	}
	return context_map_resolve_one(active, pending, input)
}

@(private)
context_map_resolve_one :: proc(
	active: ^Context_Map_State,
	pending: ^Context_Pending_State,
	input: Input,
) -> (resolution: Resolution, owns_input: bool, failure: Failure_Context) {
	if input.kind != .Key {
		return context_map_try_resolve(active, pending, input)
	}
	if pending.stroke_count >= MAX_SEQUENCE_STROKES {
		pending^ = {}
		return Resolution{kind = .Rejected}, true, Failure_Context {
			code = .Sequence_Limit,
			limit = MAX_SEQUENCE_STROKES,
			actual = u64(MAX_SEQUENCE_STROKES) + 1,
		}
	}
	query := Compiled_Binding {
		strokes = pending.strokes,
		stroke_count = pending.stroke_count + 1,
	}
	query.strokes[pending.stroke_count] = input.stroke
	exact, prefix := context_map_find_sequence(active, query)
	if exact != nil {
		pending^ = {}
		return Resolution{kind = .Command, command = exact.command}, true, {}
	}
	if prefix {
		pending.context_generation = active.handle.ctx.generation
		pending.owner = active.handle.owner
		pending.map_identity = active.handle.identity
		pending.strokes = query.strokes
		pending.stroke_count = query.stroke_count
		return Resolution{kind = .Pending}, true, {}
	}
	pending^ = {}
	switch active.unmatched_input_policy {
	case .Fallthrough:
		return Resolution{kind = .Unbound}, false, {}
	case .Text_Input:
		if len(input.text) > 0 {
			assert(active.has_text_fallback)
			return Resolution{kind = .Command, command = active.text_fallback, text = input.text}, true, {}
		}
		return Resolution{kind = .Rejected}, true, context_map_rejected_failure(active)
	case .Reject:
		return Resolution{kind = .Rejected}, true, context_map_rejected_failure(active)
	case .Invalid:
		return Resolution{kind = .Rejected}, true, Failure_Context{code = .Invalid_Context_Map}
	}
	unreachable()
}

@(private)
context_map_find_sequence :: proc(
	active: ^Context_Map_State,
	query: Compiled_Binding,
) -> (exact: ^Compiled_Binding, prefix: bool) {
	for index in 0 ..< int(active.binding_count) {
		binding := &active.bindings[index]
		comparison := sequence_compare(binding^, query)
		if comparison == 0 {
			return binding, false
		}
		if sequence_prefix(query, binding^) {
			return nil, true
		}
	}
	return nil, false
}

@(private)
context_map_find_pending_owner :: proc(
	state: ^Context_Map_Stack_State,
	pending: ^Context_Pending_State,
) -> ^Context_Map_State {
	for index in 0 ..< MAX_CONTEXT_MAPS {
		active := &state.maps[index]
		if active.active && active.handle.owner == pending.owner &&
		   active.handle.identity == pending.map_identity &&
		   active.handle.ctx.generation == pending.context_generation {
			return active
		}
	}
	return nil
}

@(private)
context_map_conflict :: proc(
	state: ^Context_Map_Stack_State,
	candidate: ^Context_Map_State,
) -> Failure_Context {
	for map_index in 0 ..< MAX_CONTEXT_MAPS {
		active := &state.maps[map_index]
		if !active.active || active.precedence != candidate.precedence ||
		   active.priority != candidate.priority {
			continue
		}
		for existing_index in 0 ..< int(active.binding_count) {
			existing := active.bindings[existing_index]
			for proposed_index in 0 ..< int(candidate.binding_count) {
				proposed := candidate.bindings[proposed_index]
				if sequence_equal(existing, proposed) || sequence_prefix(existing, proposed) ||
				   sequence_prefix(proposed, existing) {
					return Failure_Context{code = .Ordering_Conflict}
				}
			}
		}
	}
	return {}
}

@(private)
context_map_rebuild_order :: proc(state: ^Context_Map_Stack_State) {
	count := 0
	for slot in 0 ..< MAX_CONTEXT_MAPS {
		active := &state.maps[slot]
		if !active.active {
			continue
		}
		insert := count
		for insert > 0 {
			previous_slot := state.order[insert - 1]
			if !context_map_less(active, &state.maps[previous_slot]) {
				break
			}
			state.order[insert] = previous_slot
			insert -= 1
		}
		state.order[insert] = u8(slot)
		count += 1
	}
	for index in count ..< MAX_CONTEXT_MAPS {
		state.order[index] = 0
	}
}

@(private)
context_map_less :: proc(left, right: ^Context_Map_State) -> bool {
	if left.precedence != right.precedence {
		return left.precedence < right.precedence
	}
	if left.priority != right.priority {
		return left.priority > right.priority
	}
	return left.handle.identity.id < right.handle.identity.id
}

@(private)
context_binding_sort :: proc(bindings: []Compiled_Binding) {
	for index in 1 ..< len(bindings) {
		value := bindings[index]
		cursor := index
		for cursor > 0 && sequence_compare(value, bindings[cursor - 1]) < 0 {
			bindings[cursor] = bindings[cursor - 1]
			cursor -= 1
		}
		bindings[cursor] = value
	}
}

@(private)
context_map_definition_valid :: proc(definition: Context_Map_Definition) -> bool {
	if !map_identity_valid(definition.identity) ||
	   !valid_bounded_text(definition.name, MAX_IDENTITY_BYTES, false) ||
	   definition.owner_id == Owner_ID(0) ||
	   (definition.precedence != .Transient_Interaction &&
	    definition.precedence != .Component_Tool &&
	    definition.precedence != .Language_Context) ||
	   len(definition.bindings) == 0 || len(definition.bindings) > MAX_CONTEXT_BINDINGS {
		return false
	}
	switch definition.unmatched_input_policy {
	case .Fallthrough, .Reject:
		return len(definition.text_fallback_name) == 0
	case .Text_Input:
		return valid_bounded_text(definition.text_fallback_name, MAX_COMMAND_NAME_BYTES, false)
	case .Invalid:
		return false
	}
	return false
}

@(private)
context_map_rejected_failure :: proc(active: ^Context_Map_State) -> Failure_Context {
	return Failure_Context {
		code = .Context_Input_Rejected,
		ctx = active.handle.ctx,
		owner = active.handle.owner,
		map_identity = active.handle.identity,
	}
}

@(private)
context_map_stack_state :: proc(stack: ^Context_Map_Stack) -> ^Context_Map_Stack_State {
	if stack == nil || stack.state == nil {
		return nil
	}
	return cast(^Context_Map_Stack_State)stack.state
}
