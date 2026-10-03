// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "../search"
import "base:runtime"
import "core:slice"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

@(private)
Candidate_Descriptor_State :: struct {
	identity:          Candidate_Identity,
	label:             string,
	folded_label:      string,
	searchable_fields: []string,
	folded_fields:     []string,
	annotations:       []Candidate_Annotation,
	action:            Candidate_Action,
	availability:      Candidate_Availability,
	durable_category:  Candidate_Durable_Category,
	durable_key:       string,
	recency:           u64,
	label_highlight_start: u32,
	label_highlight_end:   u32,
	label_highlight_present: bool,
	allocator:         runtime.Allocator,
}

@(private)
Candidate_Component_State :: struct {
	text:          string,
	folded_text:   string,
	pattern:       search.Query,
	pattern_valid: bool,
	allocator:     runtime.Allocator,
}

@(private)
Candidate_Projection :: struct {
	descriptor_index: u32,
	match_class:      Candidate_Match_Class,
	recency:          u64,
	folded_label:     string,
	identity:         Candidate_Identity,
	source_order:     u32,
	preserve_source_order: bool,
}

@(private)
Candidate_Query_State :: struct {
	query:          string,
	components:     []Candidate_Component_State,
	projections:    []Candidate_Projection,
	rows:           []Candidate_Row,
	selected_row:   u32,
	has_selection:  bool,
	allocator:      runtime.Allocator,
}

@(private)
Candidate_State :: struct {
	session_id:         Candidate_Session_ID,
	generation:         Candidate_Session_Generation,
	source_kind:        Candidate_Source_Kind,
	scope_identity:     u64,
	scope_generation:   u64,
	source_generation:  u64,
	descriptors:        []Candidate_Descriptor_State,
	query:              Candidate_Query_State,
	accounting:         Candidate_Accounting,
	next_recency:       u64,
	cancelled:          bool,
	limits:             Candidate_Limits,
	persistent_allocator: runtime.Allocator,
	temporary_allocator:  runtime.Allocator,
}

/* candidate_limits_are_valid reports whether a limit set is internally consistent and admitted. */
candidate_limits_are_valid :: proc(limits: Candidate_Limits) -> bool {
	return limits.candidates > 0 && limits.candidates <= MAX_CANDIDATES &&
		limits.text_bytes > 0 && limits.text_bytes <= MAX_CANDIDATE_TEXT_BYTES &&
		limits.label_bytes > 0 && limits.label_bytes <= MAX_CANDIDATE_LABEL_BYTES &&
		limits.fields_per_candidate > 0 &&
		limits.fields_per_candidate <= MAX_CANDIDATE_FIELDS &&
		limits.annotations_per_candidate > 0 &&
		limits.annotations_per_candidate <= MAX_CANDIDATE_ANNOTATIONS &&
		limits.query_bytes > 0 && limits.query_bytes <= MAX_CANDIDATE_QUERY_BYTES &&
		limits.query_components > 0 &&
		limits.query_components <= MAX_CANDIDATE_QUERY_COMPONENTS &&
		limits.pattern_bytes > 0 &&
		limits.pattern_bytes <= MAX_CANDIDATE_PATTERN_BYTES &&
		limits.pattern_bytes <= limits.query_bytes &&
		limits.visible_rows > 0 && limits.visible_rows <= MAX_CANDIDATE_VISIBLE_ROWS &&
		limits.visible_rows <= limits.candidates &&
		limits.temporary_bytes > 0 &&
		limits.temporary_bytes <= MAX_CANDIDATE_TEMPORARY_BYTES &&
		limits.refreshes_per_turn == MAX_CANDIDATE_REFRESHES_PER_TURN
}

/* candidate_identity_is_valid reports whether one source-owned opaque identity is nonzero. */
candidate_identity_is_valid :: proc(identity: Candidate_Identity) -> bool {
	return identity.kind != 0 && (identity.primary != 0 || identity.secondary != 0)
}

/* candidate_session_init copies one complete source and publishes its initial projection atomically. */
candidate_session_init :: proc(
	session: ^Candidate_Session,
	config: Candidate_Config,
	source: Candidate_Source_Definition,
	query := "",
) -> (result: Candidate_Result, ok: bool, failure: Candidate_Failure) {
	assert(session != nil)
	assert(session.state == nil, "candidate session is already initialized")
	if config.session_id == Candidate_Session_ID(0) ||
	   !candidate_limits_are_valid(config.limits) ||
	   config.persistent_allocator.procedure == nil ||
	   config.temporary_allocator.procedure == nil {
		return {}, false, Candidate_Failure {
			code = .Invalid_Config,
			session_id = config.session_id,
		}
	}
	state, built, build_failure := candidate_state_build(
		config,
		source,
		query,
		{},
		nil,
		Candidate_Session_Generation(1),
	)
	if !built {
		return {}, false, build_failure
	}
	session.state = state
	return candidate_result(state, .Changed), true, {}
}

/* candidate_session_view borrows one immutable normalized projection until the next session operation. */
candidate_session_view :: proc(
	session: ^Candidate_Session,
) -> (view: Candidate_View, ok: bool, failure: Candidate_Failure) {
	state := candidate_state(session)
	if state == nil {
		return {}, false, Candidate_Failure{code = .Closed_Session}
	}
	return Candidate_View {
		session_id = state.session_id,
		session_generation = state.generation,
		source_kind = state.source_kind,
		scope_identity = state.scope_identity,
		scope_generation = state.scope_generation,
		source_generation = state.source_generation,
		query = state.query.query,
		rows = state.query.rows,
		selected_row = state.query.selected_row,
		has_selection = state.query.has_selection,
		cancelled = state.cancelled,
		accounting = state.accounting,
	}, true, {}
}

/* candidate_session_set_query atomically replaces matching and ranking for one checked generation. */
candidate_session_set_query :: proc(
	session: ^Candidate_Session,
	request: Candidate_Request,
	query: string,
) -> (result: Candidate_Result, ok: bool, failure: Candidate_Failure) {
	state, resolved, resolve_failure := candidate_resolve(session, request)
	if !resolved {
		return {}, false, resolve_failure
	}
	if state.cancelled {
		return {}, false, candidate_failure(state, .Cancelled)
	}
	next, built, build_failure := candidate_query_build(state, query, {})
	if !built {
		return {}, false, build_failure
	}
	candidate_query_destroy(&state.query)
	state.query = next
	state.generation += 1
	candidate_accounting_query(state)
	return candidate_result(state, .Changed), true, {}
}

/* candidate_session_move changes only the highlighted row for one checked generation. */
candidate_session_move :: proc(
	session: ^Candidate_Session,
	request: Candidate_Request,
	delta: i32,
) -> (result: Candidate_Result, ok: bool, failure: Candidate_Failure) {
	state, resolved, resolve_failure := candidate_resolve(session, request)
	if !resolved {
		return {}, false, resolve_failure
	}
	if state.cancelled {
		return {}, false, candidate_failure(state, .Cancelled)
	}
	if delta == 0 {
		return {}, false, candidate_failure(state, .Invalid_Movement)
	}
	if !state.query.has_selection || len(state.query.rows) == 0 {
		return {}, false, candidate_failure(state, .No_Selection)
	}
	current := i64(state.query.selected_row)
	next := clamp(current + i64(delta), i64(0), i64(len(state.query.rows) - 1))
	if next == current {
		return candidate_result(state, .No_Change), true, {}
	}
	state.query.selected_row = u32(next)
	state.generation += 1
	return candidate_result(state, .Changed), true, {}
}

/* candidate_session_refresh replaces one complete newer source generation without publishing partial state. */
candidate_session_refresh :: proc(
	session: ^Candidate_Session,
	request: Candidate_Request,
	source: Candidate_Source_Definition,
) -> (result: Candidate_Result, ok: bool, failure: Candidate_Failure) {
	state, resolved, resolve_failure := candidate_resolve(session, request)
	if !resolved {
		return {}, false, resolve_failure
	}
	if state.cancelled {
		return {}, false, candidate_failure(state, .Cancelled)
	}
	if source.kind != state.source_kind || source.scope_identity != state.scope_identity ||
	   source.source_generation <= state.source_generation {
		return {}, false, Candidate_Failure {
			code = .Stale_Source,
			session_id = state.session_id,
			session_generation = state.generation,
			source_generation = source.source_generation,
			actual = source.source_generation,
			limit = state.source_generation + 1,
		}
	}
	config := Candidate_Config {
		session_id = state.session_id,
		limits = state.limits,
		persistent_allocator = state.persistent_allocator,
		temporary_allocator = state.temporary_allocator,
	}
	selected := candidate_selected_identity(state)
	next, built, build_failure := candidate_state_build(
		config,
		source,
		state.query.query,
		selected,
		state,
		state.generation + 1,
	)
	if !built {
		return {}, false, build_failure
	}
	session.state = next
	candidate_state_destroy(state)
	return candidate_result(next, .Refreshed), true, {}
}

/* candidate_session_record_success updates bounded process-local recency after one checked action succeeds. */
candidate_session_record_success :: proc(
	session: ^Candidate_Session,
	request: Candidate_Request,
	identity: Candidate_Identity,
) -> (result: Candidate_Result, ok: bool, failure: Candidate_Failure) {
	state, resolved, resolve_failure := candidate_resolve(session, request)
	if !resolved {
		return {}, false, resolve_failure
	}
	if state.cancelled {
		return {}, false, candidate_failure(state, .Cancelled)
	}
	index := candidate_descriptor_find(state.descriptors, identity)
	if index < 0 {
		failure = candidate_failure(state, .Invalid_Identity)
		failure.identity = identity
		return {}, false, failure
	}
	recencies, allocation_error := make(
		[]u64,
		len(state.descriptors),
		state.temporary_allocator,
	)
	if allocation_error != nil {
		return {}, false, candidate_failure(state, .Temporary_Memory_Limit)
	}
	defer delete(recencies, state.temporary_allocator)
	for descriptor, descriptor_index in state.descriptors {
		recencies[descriptor_index] = descriptor.recency
	}
	next_recency := state.next_recency
	if next_recency == max(u64) {
		renormalized, renormalize_failure := candidate_recencies_renormalize(state, recencies)
		if !renormalized {
			return {}, false, renormalize_failure
		}
		next_recency = u64(len(recencies)) + 1
	}
	recencies[index] = next_recency
	next_recency += 1
	next, built, build_failure := candidate_query_build(
		state,
		state.query.query,
		identity,
		recencies,
	)
	if !built {
		return {}, false, build_failure
	}
	for &descriptor, descriptor_index in state.descriptors {
		descriptor.recency = recencies[descriptor_index]
	}
	state.next_recency = next_recency
	candidate_query_destroy(&state.query)
	state.query = next
	state.generation += 1
	candidate_accounting_query(state)
	return candidate_result(state, .Changed), true, {}
}

/* candidate_session_cancel closes interaction semantics without invoking or recording an action. */
candidate_session_cancel :: proc(
	session: ^Candidate_Session,
	request: Candidate_Request,
) -> (result: Candidate_Result, ok: bool, failure: Candidate_Failure) {
	state, resolved, resolve_failure := candidate_resolve(session, request)
	if !resolved {
		return {}, false, resolve_failure
	}
	if state.cancelled {
		return candidate_result(state, .No_Change), true, {}
	}
	state.cancelled = true
	state.generation += 1
	return candidate_result(state, .Cancelled), true, {}
}

/* candidate_session_close releases every copied source, pattern, projection, and query allocation. */
candidate_session_close :: proc(
	session: ^Candidate_Session,
) -> (result: Candidate_Result, ok: bool, failure: Candidate_Failure) {
	state := candidate_state(session)
	if state == nil {
		return {}, false, Candidate_Failure{code = .Closed_Session}
	}
	result = candidate_result(state, .Closed)
	session.state = nil
	candidate_state_destroy(state)
	return result, true, {}
}

@(private)
candidate_state_build :: proc(
	config: Candidate_Config,
	source: Candidate_Source_Definition,
	query: string,
	selected: Candidate_Identity,
	previous: ^Candidate_State,
	generation: Candidate_Session_Generation,
) -> (state: ^Candidate_State, ok: bool, failure: Candidate_Failure) {
	failure = candidate_source_validate(config, source)
	if failure.code != .None {
		return nil, false, failure
	}
	state_error: runtime.Allocator_Error
	state, state_error = new(Candidate_State, config.persistent_allocator)
	if state_error != nil {
		return nil, false, Candidate_Failure {
			code = .Persistent_Memory_Limit,
			session_id = config.session_id,
			actual = u64(size_of(Candidate_State)),
		}
	}
	state.session_id = config.session_id
	state.generation = generation
	state.source_kind = source.kind
	state.scope_identity = source.scope_identity
	state.scope_generation = source.scope_generation
	state.source_generation = source.source_generation
	state.limits = config.limits
	state.persistent_allocator = config.persistent_allocator
	state.temporary_allocator = config.temporary_allocator
	state.descriptors, state_error = make(
		[]Candidate_Descriptor_State,
		len(source.descriptors),
		config.persistent_allocator,
	)
	if state_error != nil {
		candidate_state_destroy(state)
		return nil, false, candidate_failure(state, .Persistent_Memory_Limit)
	}
	for definition, index in source.descriptors {
		descriptor, copied, copy_failure := candidate_descriptor_copy(
			definition,
			config,
			source.source_generation,
		)
		if !copied {
			candidate_state_destroy(state)
			return nil, false, copy_failure
		}
		if previous != nil {
			previous_index := candidate_descriptor_find(previous.descriptors, definition.identity)
			if previous_index >= 0 {
				descriptor.recency = max(
					descriptor.recency,
					previous.descriptors[previous_index].recency,
				)
			}
		}
		state.descriptors[index] = descriptor
		state.accounting.candidates += 1
		state.accounting.label_bytes += u64(len(descriptor.label))
		for field in descriptor.searchable_fields {
			state.accounting.searchable_bytes += u64(len(field))
		}
		for annotation in descriptor.annotations {
			state.accounting.annotation_bytes += u64(len(annotation.text))
		}
		state.accounting.durable_key_bytes += u64(len(descriptor.durable_key))
		if descriptor.recency == max(u64) {
			state.next_recency = max(u64)
		} else {
			state.next_recency = max(state.next_recency, descriptor.recency + 1)
		}
	}
	if state.next_recency == 0 {
		state.next_recency = 1
	}
	state.query, ok, failure = candidate_query_build(state, query, selected)
	if !ok {
		candidate_state_destroy(state)
		return nil, false, failure
	}
	candidate_accounting_query(state)
	return state, true, {}
}

@(private)
candidate_source_validate :: proc(
	config: Candidate_Config,
	source: Candidate_Source_Definition,
) -> Candidate_Failure {
	failure := Candidate_Failure {
		session_id = config.session_id,
		source_generation = source.source_generation,
	}
	if source.kind == .Invalid || source.scope_identity == 0 ||
	   source.scope_generation == 0 || source.source_generation == 0 {
		failure.code = .Invalid_Source
		return failure
	}
	if len(source.descriptors) > int(config.limits.candidates) {
		failure.code = .Candidate_Limit
		failure.limit = u64(config.limits.candidates)
		failure.actual = u64(len(source.descriptors))
		return failure
	}
	total_text: u64
	for definition, index in source.descriptors {
		if !candidate_identity_is_valid(definition.identity) {
			failure.code = .Invalid_Identity
			failure.identity = definition.identity
			return failure
		}
		for other in source.descriptors[:index] {
			if other.identity == definition.identity {
				failure.code = .Duplicate_Identity
				failure.identity = definition.identity
				return failure
			}
		}
		if len(definition.label) == 0 || !utf8.valid_string(definition.label) {
			failure.code = .Malformed_UTF8
			failure.identity = definition.identity
			failure.actual = u64(len(definition.label))
			return failure
		}
		if len(definition.label) > int(config.limits.label_bytes) {
			failure.code = .Label_Limit
			failure.identity = definition.identity
			failure.limit = u64(config.limits.label_bytes)
			failure.actual = u64(len(definition.label))
			return failure
		}
		if len(definition.searchable_fields) > int(config.limits.fields_per_candidate) {
			failure.code = .Field_Limit
			failure.identity = definition.identity
			failure.limit = u64(config.limits.fields_per_candidate)
			failure.actual = u64(len(definition.searchable_fields))
			return failure
		}
		if len(definition.annotations) > int(config.limits.annotations_per_candidate) {
			failure.code = .Annotation_Limit
			failure.identity = definition.identity
			failure.limit = u64(config.limits.annotations_per_candidate)
			failure.actual = u64(len(definition.annotations))
			return failure
		}
		if definition.action.kind == .Invalid || definition.action.owner_generation == 0 ||
		   definition.availability == .Invalid {
			failure.code = .Invalid_Source
			failure.identity = definition.identity
			return failure
		}
		if (definition.durable_category == .None) != (len(definition.durable_key) == 0) ||
		   !utf8.valid_string(definition.durable_key) {
			failure.code = .Invalid_Source
			failure.identity = definition.identity
			return failure
		}
		total_text += u64(len(definition.label))
		total_text += u64(len(definition.durable_key))
		for field in definition.searchable_fields {
			if !utf8.valid_string(field) {
				failure.code = .Malformed_UTF8
				failure.identity = definition.identity
				failure.actual = u64(len(field))
				return failure
			}
			total_text += u64(len(field))
		}
		for annotation in definition.annotations {
			if annotation.kind == .Invalid || !utf8.valid_string(annotation.text) {
				failure.code = .Malformed_UTF8
				failure.identity = definition.identity
				failure.actual = u64(len(annotation.text))
				return failure
			}
			total_text += u64(len(annotation.text))
		}
		if total_text > config.limits.text_bytes {
			failure.code = .Text_Limit
			failure.limit = config.limits.text_bytes
			failure.actual = total_text
			return failure
		}
	}
	return {}
}

@(private)
candidate_descriptor_copy :: proc(
	definition: Candidate_Descriptor_Definition,
	config: Candidate_Config,
	source_generation: u64,
) -> (descriptor: Candidate_Descriptor_State, ok: bool, failure: Candidate_Failure) {
	descriptor.allocator = config.persistent_allocator
	descriptor.identity = definition.identity
	descriptor.action = definition.action
	descriptor.availability = definition.availability
	descriptor.durable_category = definition.durable_category
	descriptor.recency = definition.recency
	copy_error: runtime.Allocator_Error
	descriptor.label, copy_error = strings.clone(definition.label, descriptor.allocator)
	if copy_error != nil {
		candidate_descriptor_destroy(&descriptor)
		return {}, false, Candidate_Failure {
			code = .Persistent_Memory_Limit,
			source_generation = source_generation,
			identity = definition.identity,
		}
	}
	descriptor.durable_key, copy_error = strings.clone(definition.durable_key, descriptor.allocator)
	if copy_error != nil {
		candidate_descriptor_destroy(&descriptor)
		return {}, false, Candidate_Failure {
			code = .Persistent_Memory_Limit,
			source_generation = source_generation,
			identity = definition.identity,
		}
	}
	descriptor.folded_label, copy_error = strings.to_lower(definition.label, descriptor.allocator)
	if copy_error != nil {
		candidate_descriptor_destroy(&descriptor)
		return {}, false, Candidate_Failure {
			code = .Persistent_Memory_Limit,
			source_generation = source_generation,
			identity = definition.identity,
		}
	}
	descriptor.searchable_fields, copy_error = make(
		[]string,
		len(definition.searchable_fields),
		descriptor.allocator,
	)
	if copy_error != nil {
		candidate_descriptor_destroy(&descriptor)
		return {}, false, Candidate_Failure {
			code = .Persistent_Memory_Limit,
			source_generation = source_generation,
			identity = definition.identity,
		}
	}
	descriptor.folded_fields, copy_error = make(
		[]string,
		len(definition.searchable_fields),
		descriptor.allocator,
	)
	if copy_error != nil {
		candidate_descriptor_destroy(&descriptor)
		return {}, false, Candidate_Failure {
			code = .Persistent_Memory_Limit,
			source_generation = source_generation,
			identity = definition.identity,
		}
	}
	for field, index in definition.searchable_fields {
		descriptor.searchable_fields[index], copy_error = strings.clone(field, descriptor.allocator)
		if copy_error != nil {
			candidate_descriptor_destroy(&descriptor)
			return {}, false, Candidate_Failure {
				code = .Persistent_Memory_Limit,
				source_generation = source_generation,
				identity = definition.identity,
			}
		}
		descriptor.folded_fields[index], copy_error = strings.to_lower(field, descriptor.allocator)
		if copy_error != nil {
			candidate_descriptor_destroy(&descriptor)
			return {}, false, Candidate_Failure {
				code = .Persistent_Memory_Limit,
				source_generation = source_generation,
				identity = definition.identity,
			}
		}
	}
	descriptor.annotations, copy_error = make(
		[]Candidate_Annotation,
		len(definition.annotations),
		descriptor.allocator,
	)
	if copy_error != nil {
		candidate_descriptor_destroy(&descriptor)
		return {}, false, Candidate_Failure {
			code = .Persistent_Memory_Limit,
			source_generation = source_generation,
			identity = definition.identity,
		}
	}
	for annotation, index in definition.annotations {
		owned, annotation_error := strings.clone(annotation.text, descriptor.allocator)
		if annotation_error != nil {
			candidate_descriptor_destroy(&descriptor)
			return {}, false, Candidate_Failure {
				code = .Persistent_Memory_Limit,
				source_generation = source_generation,
				identity = definition.identity,
			}
		}
		descriptor.annotations[index] = Candidate_Annotation {
			kind = annotation.kind,
			text = owned,
		}
	}
	if definition.label_highlight_present {
		if definition.label_highlight_start >= definition.label_highlight_end ||
		   definition.label_highlight_end > u32(len(definition.label)) ||
		   !utf8.valid_string(definition.label[:definition.label_highlight_start]) ||
		   !utf8.valid_string(definition.label[:definition.label_highlight_end]) {
			candidate_descriptor_destroy(&descriptor)
			return {}, false, Candidate_Failure {
				code = .Invalid_Source,
				source_generation = source_generation,
				identity = definition.identity,
			}
		}
		descriptor.label_highlight_start = definition.label_highlight_start
		descriptor.label_highlight_end = definition.label_highlight_end
		descriptor.label_highlight_present = true
	}
	return descriptor, true, {}
}

@(private)
candidate_query_build :: proc(
	state: ^Candidate_State,
	query: string,
	selected: Candidate_Identity,
	recencies: []u64 = nil,
) -> (next: Candidate_Query_State, ok: bool, failure: Candidate_Failure) {
	assert(len(recencies) == 0 || len(recencies) == len(state.descriptors))
	if !utf8.valid_string(query) {
		return {}, false, Candidate_Failure {
			code = .Malformed_UTF8,
			session_id = state.session_id,
			session_generation = state.generation,
			actual = u64(len(query)),
		}
	}
	if len(query) > int(state.limits.query_bytes) {
		return {}, false, Candidate_Failure {
			code = .Query_Limit,
			session_id = state.session_id,
			session_generation = state.generation,
			limit = u64(state.limits.query_bytes),
			actual = u64(len(query)),
		}
	}
	next.allocator = state.persistent_allocator
	query_error: runtime.Allocator_Error
	next.query, query_error = strings.clone(query, next.allocator)
	if query_error != nil {
		candidate_query_destroy(&next)
		return {}, false, candidate_failure(state, .Persistent_Memory_Limit)
	}
	fields, fields_error := strings.fields(next.query, state.temporary_allocator)
	if fields_error != nil {
		candidate_query_destroy(&next)
		return {}, false, candidate_failure(state, .Temporary_Memory_Limit)
	}
	defer delete(fields, state.temporary_allocator)
	if len(fields) > int(state.limits.query_components) {
		candidate_query_destroy(&next)
		failure = candidate_failure(state, .Component_Limit)
		failure.limit = u64(state.limits.query_components)
		failure.actual = u64(len(fields))
		return {}, false, failure
	}
	next.components, query_error = make(
		[]Candidate_Component_State,
		len(fields),
		next.allocator,
	)
	if query_error != nil {
		candidate_query_destroy(&next)
		return {}, false, candidate_failure(state, .Persistent_Memory_Limit)
	}
	for field, index in fields {
		component, built, component_failure := candidate_component_build(state, field, index)
		if !built {
			candidate_query_destroy(&next)
			return {}, false, component_failure
		}
		next.components[index] = component
	}
	next.projections, query_error = make(
		[]Candidate_Projection,
		len(state.descriptors),
		next.allocator,
	)
	if query_error != nil {
		candidate_query_destroy(&next)
		return {}, false, candidate_failure(state, .Persistent_Memory_Limit)
	}
	count := 0
	for descriptor, index in state.descriptors {
		descriptor_pointer := &state.descriptors[index]
		match_class := Candidate_Match_Class.Empty
		matched := descriptor.action.kind == .Open_Command_Prompt
		match_failure: Candidate_Failure
		if !matched {
			match_class, matched, match_failure = candidate_descriptor_match(
				state,
				descriptor_pointer,
				next.query,
				next.components,
			)
		}
		if match_failure.code != .None {
			candidate_query_destroy(&next)
			return {}, false, match_failure
		}
		if !matched {
			continue
		}
		if count >= int(state.limits.visible_rows) {
			candidate_query_destroy(&next)
			failure = candidate_failure(state, .Visible_Row_Limit)
			failure.limit = u64(state.limits.visible_rows)
			failure.actual = u64(count + 1)
			return {}, false, failure
		}
		recency := descriptor.recency
		if len(recencies) > 0 {
			recency = recencies[index]
		}
		next.projections[count] = Candidate_Projection {
			descriptor_index = u32(index),
			match_class = match_class,
			recency = recency,
			folded_label = descriptor.folded_label,
			identity = descriptor.identity,
			source_order = u32(index),
			preserve_source_order = state.source_kind == .Results,
		}
		count += 1
	}
	next.projections = next.projections[:count]
	slice.sort_by(next.projections, candidate_projection_less)
	next.rows, query_error = make([]Candidate_Row, count, next.allocator)
	if query_error != nil {
		candidate_query_destroy(&next)
		return {}, false, candidate_failure(state, .Persistent_Memory_Limit)
	}
	for projection, index in next.projections {
		descriptor := &state.descriptors[projection.descriptor_index]
		next.rows[index] = Candidate_Row {
			identity = descriptor.identity,
			label = descriptor.label,
			annotations = descriptor.annotations,
			action = descriptor.action,
			availability = descriptor.availability,
			durable_category = descriptor.durable_category,
			durable_key = descriptor.durable_key,
			match_class = projection.match_class,
			recency = projection.recency,
			label_highlight_start = descriptor.label_highlight_start,
			label_highlight_end = descriptor.label_highlight_end,
			label_highlight_present = descriptor.label_highlight_present,
		}
		if selected != (Candidate_Identity{}) && descriptor.identity == selected {
			next.selected_row = u32(index)
			next.has_selection = true
		}
	}
	if count > 0 && !next.has_selection {
		next.selected_row = 0
		next.has_selection = true
	}
	return next, true, {}
}

@(private)
candidate_component_build :: proc(
	state: ^Candidate_State,
	text: string,
	index: int,
) -> (component: Candidate_Component_State, ok: bool, failure: Candidate_Failure) {
	component.allocator = state.persistent_allocator
	copy_error: runtime.Allocator_Error
	component.text, copy_error = strings.clone(text, component.allocator)
	if copy_error != nil {
		candidate_component_destroy(&component)
		return {}, false, candidate_failure(state, .Persistent_Memory_Limit)
	}
	component.folded_text, copy_error = strings.to_lower(text, component.allocator)
	if copy_error != nil {
		candidate_component_destroy(&component)
		return {}, false, candidate_failure(state, .Persistent_Memory_Limit)
	}
	if len(text) > int(state.limits.pattern_bytes) {
		return component, true, {}
	}
	initialized, search_failure := search.query_init(
		&component.pattern,
		search.Query_Config {
			id = search.Query_ID(index + 1),
			kind = .Regular_Expression,
			pattern = text,
			policy = search.Policy{case_mode = .Insensitive, boundary_mode = .Unrestricted, whitespace_mode = .Exact, wrap = false},
			limits = search.DEFAULT_LIMITS,
			allocator = state.persistent_allocator,
			temporary_allocator = state.temporary_allocator,
		},
	)
	if initialized {
		component.pattern_valid = true
		return component, true, {}
	}
	if search_failure.code == .Regex_Parser_Error ||
	   search_failure.code == .Regex_Compiler_Error ||
	   search_failure.code == .Pattern_Limit {
		return component, true, {}
	}
	candidate_component_destroy(&component)
	code := Candidate_Failure_Code.Persistent_Memory_Limit
	if search_failure.code == .Temporary_Memory_Limit {
		code = .Temporary_Memory_Limit
	}
	return {}, false, candidate_failure(state, code)
}

@(private)
candidate_descriptor_match :: proc(
	state: ^Candidate_State,
	descriptor: ^Candidate_Descriptor_State,
	query: string,
	components: []Candidate_Component_State,
) -> (match_class: Candidate_Match_Class, matched: bool, failure: Candidate_Failure) {
	if len(components) == 0 {
		return .Empty, true, {}
	}
	if strings.equal_fold(descriptor.label, query) {
		return .Exact_Label, true, {}
	}
	match_class = .Prefix_Or_Boundary
	for &component in components {
		component_class, component_matched, component_failure := candidate_component_match(
			state,
			descriptor,
			&component,
		)
		if component_failure.code != .None {
			return .Invalid, false, component_failure
		}
		if !component_matched {
			return .Invalid, false, {}
		}
		if component_class > match_class {
			match_class = component_class
		}
	}
	return match_class, true, {}
}

@(private)
candidate_component_match :: proc(
	state: ^Candidate_State,
	descriptor: ^Candidate_Descriptor_State,
	component: ^Candidate_Component_State,
) -> (match_class: Candidate_Match_Class, matched: bool, failure: Candidate_Failure) {
	if candidate_contains_at_boundary(descriptor.folded_label, component.folded_text) {
		return .Prefix_Or_Boundary, true, {}
	}
	if strings.contains(descriptor.folded_label, component.folded_text) {
		return .Literal, true, {}
	}
	for field in descriptor.folded_fields {
		if strings.contains(field, component.folded_text) {
			return .Literal, true, {}
		}
	}
	if !component.pattern_valid {
		return .Invalid, false, {}
	}
	pattern_matched, pattern_failure := candidate_pattern_matches(
		state,
		&component.pattern,
		descriptor.label,
	)
	if pattern_failure.code != .None {
		return .Invalid, false, pattern_failure
	}
	if pattern_matched {
		return .Pattern, true, {}
	}
	for field in descriptor.searchable_fields {
		pattern_matched, pattern_failure = candidate_pattern_matches(state, &component.pattern, field)
		if pattern_failure.code != .None {
			return .Invalid, false, pattern_failure
		}
		if pattern_matched {
			return .Pattern, true, {}
		}
	}
	return .Invalid, false, {}
}

@(private)
candidate_pattern_matches :: proc(
	state: ^Candidate_State,
	pattern: ^search.Query,
	text: string,
) -> (matched: bool, failure: Candidate_Failure) {
	captures: [search.MAX_CAPTURE_GROUPS][2]int
	_, regex_matched, search_failure := search.regex_match_contiguous(
		pattern,
		text,
		captures[:],
		state.temporary_allocator,
	)
	if search_failure.code == .None {
		return regex_matched, {}
	}
	failure = candidate_failure(state, .Temporary_Memory_Limit)
	failure.actual = search_failure.actual
	failure.limit = search_failure.limit
	return false, failure
}

@(private)
candidate_contains_at_boundary :: proc(text, component: string) -> bool {
	offset := 0
	for offset <= len(text) {
		index := strings.index(text[offset:], component)
		if index < 0 {
			return false
		}
		start := offset + index
		if start == 0 {
			return true
		}
		previous, _ := utf8.decode_last_rune(text[:start])
		if unicode.is_space(previous) || previous == '-' || previous == '_' ||
		   previous == '/' || previous == '.' || previous == ':' {
			return true
		}
		_, width := utf8.decode_rune(text[start:])
		offset = start + max(width, 1)
	}
	return false
}

@(private)
candidate_projection_less :: proc(left, right: Candidate_Projection) -> bool {
	if left.preserve_source_order && right.preserve_source_order &&
	   left.source_order != right.source_order {
		return left.source_order < right.source_order
	}
	if left.match_class != right.match_class {
		return left.match_class < right.match_class
	}
	if left.recency != right.recency {
		return left.recency > right.recency
	}
	if left.folded_label != right.folded_label {
		return strings.compare(left.folded_label, right.folded_label) < 0
	}
	if left.identity.kind != right.identity.kind {
		return left.identity.kind < right.identity.kind
	}
	if left.identity.primary != right.identity.primary {
		return left.identity.primary < right.identity.primary
	}
	return left.identity.secondary < right.identity.secondary
}

@(private)
candidate_resolve :: proc(
	session: ^Candidate_Session,
	request: Candidate_Request,
) -> (state: ^Candidate_State, ok: bool, failure: Candidate_Failure) {
	state = candidate_state(session)
	if state == nil {
		return nil, false, Candidate_Failure {
			code = .Closed_Session,
			session_id = request.session_id,
			session_generation = request.session_generation,
		}
	}
	if request.session_id != state.session_id ||
	   request.session_generation != state.generation {
		return nil, false, Candidate_Failure {
			code = .Stale_Session,
			session_id = request.session_id,
			session_generation = request.session_generation,
			source_generation = state.source_generation,
			limit = u64(state.generation),
			actual = u64(request.session_generation),
		}
	}
	return state, true, {}
}

@(private)
candidate_selected_identity :: proc(state: ^Candidate_State) -> Candidate_Identity {
	if state == nil || !state.query.has_selection ||
	   state.query.selected_row >= u32(len(state.query.rows)) {
		return {}
	}
	return state.query.rows[state.query.selected_row].identity
}

@(private)
candidate_result :: proc(
	state: ^Candidate_State,
	transition: Candidate_Transition,
) -> Candidate_Result {
	result := Candidate_Result {
		transition = transition,
		session_id = state.session_id,
		session_generation = state.generation,
		selected_row = state.query.selected_row,
		has_selection = state.query.has_selection,
	}
	if result.has_selection {
		result.identity = state.query.rows[result.selected_row].identity
	}
	return result
}

@(private)
candidate_failure :: proc(
	state: ^Candidate_State,
	code: Candidate_Failure_Code,
) -> Candidate_Failure {
	if state == nil {
		return Candidate_Failure{code = code}
	}
	return Candidate_Failure {
		code = code,
		session_id = state.session_id,
		session_generation = state.generation,
		source_generation = state.source_generation,
	}
}

@(private)
candidate_accounting_query :: proc(state: ^Candidate_State) {
	state.accounting.query_bytes = u32(len(state.query.query))
	state.accounting.query_components = u8(len(state.query.components))
	state.accounting.filtered_indices = u32(len(state.query.projections))
}

@(private)
candidate_descriptor_find :: proc(
	descriptors: []Candidate_Descriptor_State,
	identity: Candidate_Identity,
) -> int {
	for descriptor, index in descriptors {
		if descriptor.identity == identity {
			return index
		}
	}
	return -1
}

@(private)
candidate_recencies_renormalize :: proc(
	state: ^Candidate_State,
	recencies: []u64,
) -> (ok: bool, failure: Candidate_Failure) {
	projections, allocation_error := make(
		[]Candidate_Projection,
		len(state.descriptors),
		state.temporary_allocator,
	)
	if allocation_error != nil {
		return false, candidate_failure(state, .Temporary_Memory_Limit)
	}
	defer delete(projections, state.temporary_allocator)
	for descriptor, index in state.descriptors {
		projections[index] = Candidate_Projection {
			descriptor_index = u32(index),
			match_class = .Empty,
			recency = recencies[index],
			folded_label = descriptor.folded_label,
			identity = descriptor.identity,
		}
	}
	slice.sort_by(projections, candidate_projection_less)
	next := u64(len(projections))
	for projection in projections {
		recencies[projection.descriptor_index] = next
		next -= 1
	}
	return true, {}
}

@(private)
candidate_query_destroy :: proc(query: ^Candidate_Query_State) {
	if query == nil || query.allocator.procedure == nil {
		return
	}
	for &component in query.components {
		candidate_component_destroy(&component)
	}
	if query.components != nil {
		delete(query.components, query.allocator)
	}
	if query.projections != nil {
		delete(query.projections, query.allocator)
	}
	if query.rows != nil {
		delete(query.rows, query.allocator)
	}
	if len(query.query) > 0 {
		delete(query.query, query.allocator)
	}
	query^ = {}
}

@(private)
candidate_component_destroy :: proc(component: ^Candidate_Component_State) {
	if component == nil || component.allocator.procedure == nil {
		return
	}
	if component.pattern.state != nil {
		_, _ = search.query_close(&component.pattern)
	}
	if len(component.folded_text) > 0 {
		delete(component.folded_text, component.allocator)
	}
	if len(component.text) > 0 {
		delete(component.text, component.allocator)
	}
	component^ = {}
}

@(private)
candidate_descriptor_destroy :: proc(descriptor: ^Candidate_Descriptor_State) {
	if descriptor == nil || descriptor.allocator.procedure == nil {
		return
	}
	for field in descriptor.folded_fields {
		if len(field) > 0 {
			delete(field, descriptor.allocator)
		}
	}
	for field in descriptor.searchable_fields {
		if len(field) > 0 {
			delete(field, descriptor.allocator)
		}
	}
	for annotation in descriptor.annotations {
		if len(annotation.text) > 0 {
			delete(annotation.text, descriptor.allocator)
		}
	}
	if descriptor.folded_fields != nil {
		delete(descriptor.folded_fields, descriptor.allocator)
	}
	if descriptor.searchable_fields != nil {
		delete(descriptor.searchable_fields, descriptor.allocator)
	}
	if descriptor.annotations != nil {
		delete(descriptor.annotations, descriptor.allocator)
	}
	if len(descriptor.folded_label) > 0 {
		delete(descriptor.folded_label, descriptor.allocator)
	}
	if len(descriptor.label) > 0 {
		delete(descriptor.label, descriptor.allocator)
	}
	if len(descriptor.durable_key) > 0 {
		delete(descriptor.durable_key, descriptor.allocator)
	}
	descriptor^ = {}
}

@(private)
candidate_state_destroy :: proc(state: ^Candidate_State) {
	if state == nil {
		return
	}
	allocator := state.persistent_allocator
	candidate_query_destroy(&state.query)
	for &descriptor in state.descriptors {
		candidate_descriptor_destroy(&descriptor)
	}
	if state.descriptors != nil {
		delete(state.descriptors, allocator)
	}
	free(state, allocator)
}

@(private)
candidate_state :: proc(session: ^Candidate_Session) -> ^Candidate_State {
	if session == nil || session.state == nil {
		return nil
	}
	return (^Candidate_State)(session.state)
}
