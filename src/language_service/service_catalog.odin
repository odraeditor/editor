// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import language "../language"
import "base:runtime"
import "core:strings"
import "core:unicode/utf8"

/* Service_Catalog owns one atomically replaceable resolution snapshot. */
Service_Catalog :: struct {
	state:  rawptr,
	closed: bool,
}

@(private)
Service_Catalog_State :: struct {
	catalog_id:          Service_Catalog_ID,
	catalog_generation:  Service_Catalog_Generation,
	language_generation: language.Language_Catalog_Generation,
	registry:            Registry_Handle,
	definition_count:    u16,
	selection_count:     u16,
	source_count:        u16,
	conflict_count:      u16,
	participant_count:   u16,
	definitions:         [MAX_SERVICE_CATALOG_DEFINITIONS]Service_Definition_Descriptor,
	selections:          [MAX_SERVICE_CATALOG_SELECTIONS]Service_Explicit_Selection,
	sources:             [MAX_SERVICE_CATALOG_SOURCES]Service_Source_Record,
	conflicts:           [MAX_SERVICE_CATALOG_CONFLICTS]Service_Conflict_Record,
	participants:        [MAX_SERVICE_CONFLICT_PARTICIPANTS]Service_Conflict_Participant,
	latest_rejection:    Service_Catalog_Failure,
	allocator:           runtime.Allocator,
}

/* service_catalog_init creates one empty checked service catalog. */
service_catalog_init :: proc(
	catalog: ^Service_Catalog,
	catalog_id: Service_Catalog_ID,
	registry: Registry_Handle,
	allocator := context.allocator,
) -> (ok: bool, failure: Service_Catalog_Failure) {
	if catalog == nil || catalog_id == Service_Catalog_ID(0) ||
	   registry.id == Registry_ID(0) || registry.generation == Registry_Generation(0) {
		return false, service_catalog_failure(.Invalid_Catalog)
	}
	catalog^ = {}
	if allocator.procedure == nil do return false, service_catalog_failure(.Allocation)
	state, allocation_error := new(Service_Catalog_State, allocator)
	if allocation_error != nil do return false, service_catalog_failure(.Allocation)
	state^ = Service_Catalog_State {
		catalog_id = catalog_id,
		registry = registry,
		allocator = allocator,
	}
	catalog.state = state
	return true, {}
}

/* service_catalog_close releases the confirmed snapshot exactly once. */
service_catalog_close :: proc(
	catalog: ^Service_Catalog,
) -> (ok: bool, failure: Service_Catalog_Failure) {
	state := service_catalog_state(catalog)
	if state == nil do return false, service_catalog_failure(.Invalid_Catalog)
	allocator := state.allocator
	free(state, allocator)
	catalog^ = Service_Catalog{closed = true}
	return true, {}
}

/* service_catalog_clone copies one complete snapshot for prepared publication. */
service_catalog_clone :: proc(
	source, destination: ^Service_Catalog,
	allocator := context.allocator,
) -> (ok: bool, failure: Service_Catalog_Failure) {
	current := service_catalog_state(source)
	if current == nil || destination == nil || destination == source {
		return false, service_catalog_failure(.Invalid_Catalog)
	}
	destination^ = {}
	if allocator.procedure == nil {
		return false, service_catalog_failure(.Allocation)
	}
	next, allocation_error := new(Service_Catalog_State, allocator)
	if allocation_error != nil {
		return false, service_catalog_failure(.Allocation)
	}
	next^ = current^
	next.allocator = allocator
	destination.state = next
	return true, {}
}

/* service_catalog_confirm validates and publishes one complete catalog atomically. */
service_catalog_confirm :: proc(
	catalog: ^Service_Catalog,
	expected: Service_Catalog_Generation,
	candidate: Service_Catalog_Candidate,
	inspection: ^Service_Catalog_Inspection = nil,
) -> (ok: bool, failure: Service_Catalog_Failure) {
	current := service_catalog_state(catalog)
	if current == nil {
		if inspection != nil do inspection^ = {}
		return false, service_catalog_failure(.Invalid_Catalog)
	}
	if expected != current.catalog_generation {
		failure = service_catalog_failure(.Stale_Generation, .Catalog_Generation)
		failure.limit = u64(current.catalog_generation)
		failure.actual = u64(expected)
		current.latest_rejection = failure
		service_catalog_inspection_write(current, inspection)
		return false, failure
	}
	if candidate.generation == Service_Catalog_Generation(0) ||
	   candidate.language_catalog_generation == language.Language_Catalog_Generation(0) {
		failure = service_catalog_failure(.Invalid_Generation, .Catalog_Generation)
		current.latest_rejection = failure
		service_catalog_inspection_write(current, inspection)
		return false, failure
	}
	if candidate.generation <= current.catalog_generation {
		failure = service_catalog_failure(.Stale_Generation, .Catalog_Generation)
		failure.limit = u64(current.catalog_generation) + 1
		failure.actual = u64(candidate.generation)
		current.latest_rejection = failure
		service_catalog_inspection_write(current, inspection)
		return false, failure
	}
	if len(candidate.definitions) > MAX_SERVICE_CATALOG_DEFINITIONS {
		failure = service_catalog_failure(.Definition_Limit, .Definitions)
		failure.limit = MAX_SERVICE_CATALOG_DEFINITIONS
		failure.actual = u64(len(candidate.definitions))
		current.latest_rejection = failure
		service_catalog_inspection_write(current, inspection)
		return false, failure
	}
	if len(candidate.selections) > MAX_SERVICE_CATALOG_SELECTIONS {
		failure = service_catalog_failure(.Selection_Limit, .Selections)
		failure.limit = MAX_SERVICE_CATALOG_SELECTIONS
		failure.actual = u64(len(candidate.selections))
		current.latest_rejection = failure
		service_catalog_inspection_write(current, inspection)
		return false, failure
	}

	next, allocation_error := new(Service_Catalog_State, current.allocator)
	if allocation_error != nil {
		failure = service_catalog_failure(.Allocation)
		current.latest_rejection = failure
		service_catalog_inspection_write(current, inspection)
		return false, failure
	}
	next^ = Service_Catalog_State {
		catalog_id = current.catalog_id,
		catalog_generation = candidate.generation,
		language_generation = candidate.language_catalog_generation,
		registry = current.registry,
		allocator = current.allocator,
	}

	accepted := true
	for definition, index in candidate.definitions {
		descriptor, copied, copy_failure := service_catalog_definition_copy(
			definition,
			u16(index),
			candidate.language_catalog_generation,
			current.registry,
		)
		if !copied {
			failure = copy_failure
			accepted = false
			break
		}
		next.definitions[index] = descriptor
		next.definition_count += 1
	}
	if accepted do service_catalog_sort_definitions(next)
	if accepted {
		failure = service_catalog_definition_conflicts(next)
		accepted = failure.code == .None
	}
	if accepted {
		failure = service_catalog_collect_sources(next)
		accepted = failure.code == .None
	}
	if accepted {
		failure = service_catalog_collect_package_conflicts(next)
		accepted = failure.code == .None
	}
	if accepted {
		for selection, index in candidate.selections {
			descriptor, copied, copy_failure := service_catalog_selection_copy(
				selection,
				u16(index),
				candidate.language_catalog_generation,
			)
			if !copied {
				failure = copy_failure
				accepted = false
				break
			}
			next.selections[index] = descriptor
			next.selection_count += 1
		}
	}
	if accepted do service_catalog_sort_selections(next)
	if accepted {
		failure = service_catalog_selection_conflicts(next)
		accepted = failure.code == .None
	}
	if accepted {
		failure = service_catalog_collect_selection_sources(next)
		accepted = failure.code == .None
	}
	if accepted {
		failure = service_catalog_validate_defaults(next)
		accepted = failure.code == .None
	}
	if accepted {
		failure = service_catalog_validate_explicit_selections(next)
		accepted = failure.code == .None
	}
	if !accepted {
		free(next, current.allocator)
		current.latest_rejection = failure
		service_catalog_inspection_write(current, inspection)
		return false, failure
	}

	old := current
	catalog.state = next
	free(old, next.allocator)
	service_catalog_inspection_write(next, inspection)
	return true, {}
}

/* service_catalog_inspect returns one complete pointer-free catalog copy. */
service_catalog_inspect :: proc(
	catalog: ^Service_Catalog,
	inspection: ^Service_Catalog_Inspection,
) -> (ok: bool, failure: Service_Catalog_Failure) {
	state := service_catalog_state(catalog)
	if state == nil || inspection == nil {
		if inspection != nil do inspection^ = {}
		return false, service_catalog_failure(.Invalid_Catalog)
	}
	service_catalog_inspection_write(state, inspection)
	return true, {}
}

/* service_catalog_resolve selects one service for a trusted language/root pair. */
service_catalog_resolve :: proc(
	catalog: ^Service_Catalog,
	query: Service_Resolution_Query,
) -> (trace: Service_Resolution_Trace, ok: bool, failure: Service_Catalog_Failure) {
	state := service_catalog_state(catalog)
	if state == nil do return {}, false, service_catalog_failure(.Invalid_Catalog)
	return service_catalog_resolve_state(state, query, false)
}

/* service_catalog_restore_factory resolves factory policy only for one query scope. */
service_catalog_restore_factory :: proc(
	catalog: ^Service_Catalog,
	query: Service_Resolution_Query,
) -> (trace: Service_Resolution_Trace, ok: bool, failure: Service_Catalog_Failure) {
	state := service_catalog_state(catalog)
	if state == nil do return {}, false, service_catalog_failure(.Invalid_Catalog)
	return service_catalog_resolve_state(state, query, true)
}

/* service_identity_text_view borrows text from one copied catalog record. */
service_identity_text_view :: proc(value: ^Service_Identity_Text) -> string {
	return service_identity_string(value)
}

/* service_scope_text_view borrows text from one copied catalog record. */
service_scope_text_view :: proc(value: ^Service_Scope_Text) -> string {
	return service_scope_text_string(value)
}

/* service_provenance_text_view borrows text from one copied catalog record. */
service_provenance_text_view :: proc(value: ^Service_Provenance_Text) -> string {
	if value == nil || value.length > MAX_SERVICE_PROVENANCE_BYTES do return ""
	return string(value.bytes[:value.length])
}

@(private)
service_catalog_resolve_state :: proc(
	state: ^Service_Catalog_State,
	query: Service_Resolution_Query,
	factory_only: bool,
) -> (trace: Service_Resolution_Trace, ok: bool, failure: Service_Catalog_Failure) {
	trace = Service_Resolution_Trace {
		catalog_id = state.catalog_id,
		catalog_generation = state.catalog_generation,
		language = query.language,
		project_scope = service_scope_text_copy(query.project_membership),
		resolved_root = service_root_text_copy(query.resolved_root),
	}
	if !service_language_valid(query.language, state.language_generation) {
		return trace, false, service_catalog_failure(.Invalid_Language, .Languages)
	}
	if len(query.resolved_root) == 0 || len(query.resolved_root) > int(DEFAULT_LIMITS.root_bytes) ||
	   !utf8.valid_string(query.resolved_root) || strings.index_byte(query.resolved_root, 0) >= 0 {
		return trace, false, service_catalog_failure(.Invalid_Scope, .Scope)
	}
	if len(query.project_membership) == 0 || !query.project_trusted {
		trace.state = .Untrusted_Project
		return trace, false, service_catalog_failure(.No_Selection)
	}
	language_reference := service_language_reference(query.language)

	if !factory_only {
		selection, selected := service_catalog_explicit_selection(
			state,
			language_reference,
			query.project_membership,
		)
		if selected {
			definition, found := service_catalog_effective_definition(
				state,
				service_identity_string(&selection.service_identity),
				language_reference,
				query.project_membership,
				false,
			)
			if !found || !definition.policy.enabled {
				trace.state = .Invalid_Explicit_Selection
				trace.explicit_selection = selection
				return trace, false, service_catalog_failure(.Invalid_Explicit_Selection, .Selections)
			}
			kind := Service_Selection_Kind.Explicit_Personal
			if selection.scope.source == .Project do kind = .Explicit_Project
			service_catalog_trace_select(&trace, definition, kind, selection)
			service_catalog_trace_counts(&trace, state, query, factory_only)
			return trace, true, {}
		}
	}

	best_default: ^Service_Definition_Descriptor
	best_precedence: u8
	default_count: u16
	sole: ^Service_Definition_Descriptor
	effective_count: u16
	for index in 0 ..< int(state.definition_count) {
		definition := &state.definitions[index]
		if factory_only && definition.scope.source != .Factory do continue
		if !service_catalog_definition_applies(definition, query.project_membership, true) ||
		   !service_catalog_definition_has_language(definition, language_reference) {
			continue
		}
		effective, found := service_catalog_effective_definition(
			state,
			service_identity_string(&definition.identity),
			language_reference,
			query.project_membership,
			factory_only,
		)
		if !found || effective.definition != definition.definition || !definition.policy.enabled do continue
		effective_count += 1
		sole = definition
		if definition.policy.default_selection {
			precedence := service_catalog_source_precedence(definition.scope.source)
			if best_default == nil || precedence > best_precedence {
				best_default = definition
				best_precedence = precedence
				default_count = 1
			} else if precedence == best_precedence {
				default_count += 1
			}
		}
	}
	if best_default != nil && default_count == 1 {
		kind := Service_Selection_Kind.Unique_Default
		if factory_only do kind = .Factory_Restoration
		service_catalog_trace_select(&trace, best_default, kind, {})
		service_catalog_trace_counts(&trace, state, query, factory_only)
		return trace, true, {}
	}
	if effective_count == 1 {
		kind := Service_Selection_Kind.Sole_Candidate
		if factory_only do kind = .Factory_Restoration
		service_catalog_trace_select(&trace, sole, kind, {})
		service_catalog_trace_counts(&trace, state, query, factory_only)
		return trace, true, {}
	}
	trace.state = .Absent
	if effective_count > 1 do trace.state = .Ambiguous
	service_catalog_trace_counts(&trace, state, query, factory_only)
	return trace, false, service_catalog_failure(.No_Selection)
}

@(private)
service_catalog_definition_copy :: proc(
	candidate: Service_Catalog_Definition_Candidate,
	definition_index: u16,
	language_generation: language.Language_Catalog_Generation,
	registry: Registry_Handle,
) -> (descriptor: Service_Definition_Descriptor, ok: bool, failure: Service_Catalog_Failure) {
	failure = service_catalog_definition_validate(candidate, definition_index, language_generation, registry)
	if failure.code != .None do return {}, false, failure
	descriptor.definition = candidate.definition
	descriptor.identity = service_identity_text_copy(candidate.identity)
	descriptor.language_count = u16(len(candidate.languages))
	for language_identity, index in candidate.languages {
		descriptor.languages[index] = {
			id = language_identity.id,
			generation = language_identity.generation,
		}
	}
	descriptor.scope = Service_Source_Scope {
		source = candidate.source,
		kind = candidate.scope_kind,
		name = service_scope_text_copy(candidate.scope),
	}
	descriptor.source_generation = candidate.source_generation
	descriptor.policy = candidate.policy
	descriptor.provenance = service_provenance_text_copy(candidate.provenance)
	return descriptor, true, {}
}

@(private)
service_catalog_definition_validate :: proc(
	candidate: Service_Catalog_Definition_Candidate,
	definition_index: u16,
	language_generation: language.Language_Catalog_Generation,
	registry: Registry_Handle,
) -> Service_Catalog_Failure {
	if candidate.definition.registry != registry || candidate.definition.id == Definition_ID(0) ||
	   candidate.definition.generation == Definition_Generation(0) {
		failure := service_catalog_failure(.Invalid_Definition, .Definitions, candidate.source, candidate.source_generation)
		failure.definition_index = definition_index
		return failure
	}
	if !service_identity_valid(candidate.identity) {
		code := Service_Catalog_Failure_Code.Invalid_Definition
		if len(candidate.identity) > MAX_SERVICE_IDENTITY_BYTES do code = .Identity_Limit
		failure := service_catalog_failure(code, .Identity, candidate.source, candidate.source_generation)
		failure.definition_index = definition_index
		failure.limit = MAX_SERVICE_IDENTITY_BYTES
		failure.actual = u64(len(candidate.identity))
		return failure
	}
	if !service_source_scope_valid(candidate.source, candidate.scope_kind, candidate.scope) {
		failure := service_catalog_failure(.Invalid_Scope, .Scope, candidate.source, candidate.source_generation)
		failure.definition_index = definition_index
		failure.limit = MAX_SERVICE_SCOPE_BYTES
		failure.actual = u64(len(candidate.scope))
		return failure
	}
	if candidate.source_generation == Service_Source_Generation(0) {
		failure := service_catalog_failure(.Invalid_Generation, .Source_Generation, candidate.source)
		failure.definition_index = definition_index
		return failure
	}
	if len(candidate.languages) == 0 || len(candidate.languages) > MAX_LANGUAGE_IDENTITIES {
		failure := service_catalog_failure(.Language_Limit, .Languages, candidate.source, candidate.source_generation)
		failure.definition_index = definition_index
		failure.limit = MAX_LANGUAGE_IDENTITIES
		failure.actual = u64(len(candidate.languages))
		return failure
	}
	for value, index in candidate.languages {
		if !service_language_valid(value, language_generation) {
			failure := service_catalog_failure(.Invalid_Language, .Languages, candidate.source, candidate.source_generation)
			failure.definition_index = definition_index
			failure.actual = u64(index)
			return failure
		}
		for previous in 0 ..< index {
			if value == candidate.languages[previous] {
				failure := service_catalog_failure(.Invalid_Language, .Languages, candidate.source, candidate.source_generation)
				failure.definition_index = definition_index
				failure.actual = u64(index)
				return failure
			}
		}
	}
	if len(candidate.provenance) == 0 || len(candidate.provenance) > MAX_SERVICE_PROVENANCE_BYTES ||
	   !utf8.valid_string(candidate.provenance) || strings.index_byte(candidate.provenance, 0) >= 0 {
		failure := service_catalog_failure(.Provenance_Limit, .Provenance, candidate.source, candidate.source_generation)
		failure.definition_index = definition_index
		failure.limit = MAX_SERVICE_PROVENANCE_BYTES
		failure.actual = u64(len(candidate.provenance))
		return failure
	}
	return {}
}

@(private)
service_catalog_selection_copy :: proc(
	candidate: Service_Explicit_Selection_Candidate,
	selection_index: u16,
	language_generation: language.Language_Catalog_Generation,
) -> (descriptor: Service_Explicit_Selection, ok: bool, failure: Service_Catalog_Failure) {
	if !service_language_valid(candidate.language, language_generation) ||
	   !service_identity_valid(candidate.service_identity) ||
	   candidate.source_generation == Service_Source_Generation(0) ||
	   (candidate.source != .Personal && candidate.source != .Project) ||
	   !service_source_scope_valid(candidate.source, candidate.scope_kind, candidate.scope) {
		failure = service_catalog_failure(.Invalid_Explicit_Selection, .Selections, candidate.source, candidate.source_generation)
		failure.selection_index = selection_index
		return {}, false, failure
	}
	descriptor = Service_Explicit_Selection {
		language = {id = candidate.language.id, generation = candidate.language.generation},
		service_identity = service_identity_text_copy(candidate.service_identity),
		scope = {
			source = candidate.source,
			kind = candidate.scope_kind,
			name = service_scope_text_copy(candidate.scope),
		},
		source_generation = candidate.source_generation,
	}
	return descriptor, true, {}
}

@(private)
service_catalog_definition_conflicts :: proc(state: ^Service_Catalog_State) -> Service_Catalog_Failure {
	for left_index in 0 ..< int(state.definition_count) {
		left := &state.definitions[left_index]
		for right_index in left_index + 1 ..< int(state.definition_count) {
			right := &state.definitions[right_index]
			if left.scope.source != right.scope.source ||
			   service_scope_text_string(&left.scope.name) != service_scope_text_string(&right.scope.name) ||
			   service_identity_string(&left.identity) != service_identity_string(&right.identity) {
				continue
			}
			failure := service_catalog_failure(.Duplicate_Identity, .Identity, right.scope.source, right.source_generation)
			failure.definition_index = u16(right_index)
			return failure
		}
	}
	return {}
}

@(private)
service_catalog_selection_conflicts :: proc(state: ^Service_Catalog_State) -> Service_Catalog_Failure {
	for left_index in 0 ..< int(state.selection_count) {
		left := &state.selections[left_index]
		for right_index in left_index + 1 ..< int(state.selection_count) {
			right := &state.selections[right_index]
			if left.scope.source == right.scope.source && left.scope.kind == right.scope.kind &&
			   service_scope_text_string(&left.scope.name) == service_scope_text_string(&right.scope.name) &&
			   left.language == right.language {
				failure := service_catalog_failure(.Invalid_Explicit_Selection, .Selections, right.scope.source, right.source_generation)
				failure.selection_index = u16(right_index)
				return failure
			}
		}
	}
	return {}
}

@(private)
service_catalog_collect_sources :: proc(state: ^Service_Catalog_State) -> Service_Catalog_Failure {
	for index in 0 ..< int(state.definition_count) {
		definition := &state.definitions[index]
		failure := service_catalog_add_source(state, definition.scope, definition.source_generation)
		if failure.code != .None do return failure
	}
	return {}
}

@(private)
service_catalog_collect_selection_sources :: proc(state: ^Service_Catalog_State) -> Service_Catalog_Failure {
	for index in 0 ..< int(state.selection_count) {
		selection := &state.selections[index]
		failure := service_catalog_add_source(state, selection.scope, selection.source_generation)
		if failure.code != .None do return failure
	}
	return {}
}

@(private)
service_catalog_add_source :: proc(
	state: ^Service_Catalog_State,
	scope: Service_Source_Scope,
	generation: Service_Source_Generation,
) -> Service_Catalog_Failure {
	scope_copy := scope
	for index in 0 ..< int(state.source_count) {
		source := &state.sources[index]
		if source.scope.source == scope.source && source.scope.kind == scope.kind &&
		   service_scope_text_string(&source.scope.name) == service_scope_text_string(&scope_copy.name) {
			if source.generation != generation {
				return service_catalog_failure(.Invalid_Generation, .Source_Generation, scope.source, generation)
			}
			return {}
		}
	}
	if state.source_count >= MAX_SERVICE_CATALOG_SOURCES {
		failure := service_catalog_failure(.Definition_Limit, .Source_Generation, scope.source, generation)
		failure.limit = MAX_SERVICE_CATALOG_SOURCES
		failure.actual = u64(state.source_count) + 1
		return failure
	}
	state.sources[state.source_count] = Service_Source_Record {
		scope = scope,
		generation = generation,
		accepted = true,
	}
	state.source_count += 1
	return {}
}

@(private)
service_catalog_collect_package_conflicts :: proc(state: ^Service_Catalog_State) -> Service_Catalog_Failure {
	for left_index in 0 ..< int(state.definition_count) {
		left := &state.definitions[left_index]
		if left.scope.source != .Package do continue
		identity := service_identity_string(&left.identity)
		if service_catalog_conflict_for_identity(state, identity) >= 0 do continue
		has_conflict := false
		for right_index in left_index + 1 ..< int(state.definition_count) {
			right := &state.definitions[right_index]
			if right.scope.source == .Package && service_identity_string(&right.identity) == identity &&
			   service_scope_text_string(&right.scope.name) != service_scope_text_string(&left.scope.name) {
				has_conflict = true
				break
			}
		}
		if !has_conflict do continue
		if state.conflict_count >= MAX_SERVICE_CATALOG_CONFLICTS {
			return service_catalog_failure(.Conflict_Limit, .Conflicts, .Package, left.source_generation)
		}
		first := state.participant_count
		for candidate_index in 0 ..< int(state.definition_count) {
			candidate := &state.definitions[candidate_index]
			if candidate.scope.source != .Package || service_identity_string(&candidate.identity) != identity do continue
			if state.participant_count >= MAX_SERVICE_CONFLICT_PARTICIPANTS {
				return service_catalog_failure(.Conflict_Limit, .Conflicts, .Package, candidate.source_generation)
			}
			state.participants[state.participant_count] = Service_Conflict_Participant {
				definition = candidate.definition,
				scope = candidate.scope,
				source_generation = candidate.source_generation,
			}
			state.participant_count += 1
		}
		fallback, fallback_found := service_catalog_effective_definition_by_identity(state, identity, "", false, true)
		fallback_handle: Definition_Handle
		if fallback_found do fallback_handle = fallback.definition
		state.conflicts[state.conflict_count] = Service_Conflict_Record {
			kind = .Package_Identity,
			identity = left.identity,
			participants = {first = u32(first), count = u32(state.participant_count - first)},
			fallback = fallback_handle,
		}
		state.conflict_count += 1
	}
	return {}
}

@(private)
service_catalog_validate_defaults :: proc(state: ^Service_Catalog_State) -> Service_Catalog_Failure {
	for definition_index in 0 ..< int(state.definition_count) {
		definition := &state.definitions[definition_index]
		for language_identity in definition.languages[:definition.language_count] {
			failure := service_catalog_default_conflict(state, language_identity, "")
			if failure.code != .None do return failure
			for source_index in 0 ..< int(state.source_count) {
				source := &state.sources[source_index]
				if source.scope.source != .Project do continue
				failure = service_catalog_default_conflict(
					state,
					language_identity,
					service_scope_text_string(&source.scope.name),
				)
				if failure.code != .None do return failure
			}
		}
	}
	return {}
}

@(private)
service_catalog_default_conflict :: proc(
	state: ^Service_Catalog_State,
	language_reference: Service_Language_Reference,
	project_scope: string,
) -> Service_Catalog_Failure {
	best_precedence: u8
	best_count: u16
	best_source := Service_Contribution_Source.Invalid
	best_generation := Service_Source_Generation(0)
	for index in 0 ..< int(state.definition_count) {
		definition := &state.definitions[index]
		if !definition.policy.enabled || !definition.policy.default_selection ||
		   !service_catalog_definition_has_language(definition, language_reference) ||
		   !service_catalog_definition_applies(definition, project_scope, len(project_scope) > 0) {
			continue
		}
		effective, found := service_catalog_effective_definition(
			state,
			service_identity_string(&definition.identity),
			language_reference,
			project_scope,
			false,
		)
		if !found || effective.definition != definition.definition do continue
		precedence := service_catalog_source_precedence(definition.scope.source)
		if precedence > best_precedence {
			best_precedence = precedence
			best_count = 1
			best_source = definition.scope.source
			best_generation = definition.source_generation
		} else if precedence == best_precedence {
			best_count += 1
		}
	}
	if best_count > 1 {
		return service_catalog_failure(.Ambiguous_Default, .Default_Policy, best_source, best_generation)
	}
	return {}
}

@(private)
service_catalog_validate_explicit_selections :: proc(state: ^Service_Catalog_State) -> Service_Catalog_Failure {
	for index in 0 ..< int(state.selection_count) {
		selection := &state.selections[index]
		project_scope := ""
		if selection.scope.source == .Project do project_scope = service_scope_text_string(&selection.scope.name)
		definition, found := service_catalog_effective_definition(
			state,
			service_identity_string(&selection.service_identity),
			selection.language,
			project_scope,
			false,
		)
		if !found || !definition.policy.enabled {
			failure := service_catalog_failure(.Invalid_Explicit_Selection, .Selections, selection.scope.source, selection.source_generation)
			failure.selection_index = u16(index)
			return failure
		}
	}
	for source_index in 0 ..< int(state.source_count) {
		source := &state.sources[source_index]
		if source.scope.source != .Project do continue
		project_scope := service_scope_text_string(&source.scope.name)
		for selection_index in 0 ..< int(state.selection_count) {
			personal := &state.selections[selection_index]
			if personal.scope.source != .Personal do continue
			_, has_project := service_catalog_project_selection(state, personal.language, project_scope)
			if has_project do continue
			definition, found := service_catalog_effective_definition(
				state,
				service_identity_string(&personal.service_identity),
				personal.language,
				project_scope,
				false,
			)
			if !found || !definition.policy.enabled {
				return service_catalog_failure(.Invalid_Explicit_Selection, .Selections, .Project, source.generation)
			}
		}
	}
	return {}
}

@(private)
service_catalog_effective_definition :: proc(
	state: ^Service_Catalog_State,
	identity: string,
	language_reference: Service_Language_Reference,
	project_scope: string,
	factory_only: bool,
) -> (definition: ^Service_Definition_Descriptor, ok: bool) {
	result, found := service_catalog_effective_definition_by_identity(
		state,
		identity,
		project_scope,
		factory_only,
		false,
	)
	if !found || !service_catalog_definition_has_language(result, language_reference) do return nil, false
	return result, true
}

@(private)
service_catalog_effective_definition_by_identity :: proc(
	state: ^Service_Catalog_State,
	identity, project_scope: string,
	factory_only, exclude_packages: bool,
) -> (definition: ^Service_Definition_Descriptor, ok: bool) {
	best_precedence: u8
	for index in 0 ..< int(state.definition_count) {
		candidate := &state.definitions[index]
		if service_identity_string(&candidate.identity) != identity ||
		   (factory_only && candidate.scope.source != .Factory) ||
		   (exclude_packages && candidate.scope.source == .Package) ||
		   !service_catalog_definition_applies(candidate, project_scope, len(project_scope) > 0) ||
		   service_catalog_definition_conflicted(state, candidate.definition) {
			continue
		}
		precedence := service_catalog_source_precedence(candidate.scope.source)
		if definition == nil || precedence > best_precedence {
			definition = candidate
			best_precedence = precedence
			ok = true
		}
	}
	return
}

@(private)
service_catalog_definition_conflicted :: proc(
	state: ^Service_Catalog_State,
	handle: Definition_Handle,
) -> bool {
	for index in 0 ..< int(state.participant_count) {
		if state.participants[index].definition == handle do return true
	}
	return false
}

@(private)
service_catalog_conflict_for_identity :: proc(state: ^Service_Catalog_State, identity: string) -> int {
	for index in 0 ..< int(state.conflict_count) {
		if service_identity_string(&state.conflicts[index].identity) == identity do return index
	}
	return -1
}

@(private)
service_catalog_explicit_selection :: proc(
	state: ^Service_Catalog_State,
	language_reference: Service_Language_Reference,
	project_scope: string,
) -> (selection: Service_Explicit_Selection, ok: bool) {
	if project, found := service_catalog_project_selection(state, language_reference, project_scope); found {
		return project, true
	}
	for index in 0 ..< int(state.selection_count) {
		candidate := &state.selections[index]
		if candidate.scope.source == .Personal && candidate.language == language_reference {
			return candidate^, true
		}
	}
	return {}, false
}

@(private)
service_catalog_project_selection :: proc(
	state: ^Service_Catalog_State,
	language_reference: Service_Language_Reference,
	project_scope: string,
) -> (selection: Service_Explicit_Selection, ok: bool) {
	for index in 0 ..< int(state.selection_count) {
		candidate := &state.selections[index]
		if candidate.scope.source == .Project && candidate.language == language_reference &&
		   service_scope_text_string(&candidate.scope.name) == project_scope {
			return candidate^, true
		}
	}
	return {}, false
}

@(private)
service_catalog_definition_has_language :: proc(
	definition: ^Service_Definition_Descriptor,
	language_reference: Service_Language_Reference,
) -> bool {
	for candidate in definition.languages[:definition.language_count] {
		if candidate == language_reference do return true
	}
	return false
}

@(private)
service_catalog_definition_applies :: proc(
	definition: ^Service_Definition_Descriptor,
	project_scope: string,
	project_trusted: bool,
) -> bool {
	return definition.scope.source != .Project ||
		(project_trusted && len(project_scope) > 0 &&
		 service_scope_text_string(&definition.scope.name) == project_scope)
}

@(private)
service_catalog_trace_select :: proc(
	trace: ^Service_Resolution_Trace,
	definition: ^Service_Definition_Descriptor,
	kind: Service_Selection_Kind,
	explicit: Service_Explicit_Selection,
) {
	trace.selected = definition.definition
	trace.selected_identity = definition.identity
	trace.kind = kind
	trace.state = .Selected
	trace.explicit_selection = explicit
}

@(private)
service_catalog_trace_counts :: proc(
	trace: ^Service_Resolution_Trace,
	state: ^Service_Catalog_State,
	query: Service_Resolution_Query,
	factory_only: bool,
) {
	for index in 0 ..< int(state.definition_count) {
		definition := &state.definitions[index]
		if factory_only && definition.scope.source != .Factory do continue
		if !service_catalog_definition_applies(definition, query.project_membership, query.project_trusted) ||
		   !service_catalog_definition_has_language(definition, service_language_reference(query.language)) {
			continue
		}
		trace.considered += 1
		if service_catalog_definition_conflicted(state, definition.definition) {
			trace.conflicted += 1
			continue
		}
		effective, found := service_catalog_effective_definition(
			state,
			service_identity_string(&definition.identity),
			service_language_reference(query.language),
			query.project_membership,
			factory_only,
		)
		if !found || effective.definition != definition.definition {
			trace.shadowed += 1
			continue
		}
		if definition.policy.enabled do trace.enabled += 1
	}
}

@(private)
service_catalog_sort_definitions :: proc(state: ^Service_Catalog_State) {
	for index in 1 ..< int(state.definition_count) {
		candidate := state.definitions[index]
		position := index
		for position > 0 && service_catalog_definition_less(candidate, state.definitions[position - 1]) {
			state.definitions[position] = state.definitions[position - 1]
			position -= 1
		}
		state.definitions[position] = candidate
	}
}

@(private)
service_catalog_definition_less :: proc(left, right: Service_Definition_Descriptor) -> bool {
	left_copy := left
	right_copy := right
	left_precedence := service_catalog_source_precedence(left.scope.source)
	right_precedence := service_catalog_source_precedence(right.scope.source)
	if left_precedence != right_precedence do return left_precedence > right_precedence
	left_identity := service_identity_string(&left_copy.identity)
	right_identity := service_identity_string(&right_copy.identity)
	if left_identity != right_identity do return strings.compare(left_identity, right_identity) < 0
	left_scope := service_scope_text_string(&left_copy.scope.name)
	right_scope := service_scope_text_string(&right_copy.scope.name)
	if left_scope != right_scope do return strings.compare(left_scope, right_scope) < 0
	if left.source_generation != right.source_generation do return left.source_generation < right.source_generation
	return left.definition.id < right.definition.id
}

@(private)
service_catalog_sort_selections :: proc(state: ^Service_Catalog_State) {
	for index in 1 ..< int(state.selection_count) {
		candidate := state.selections[index]
		position := index
		for position > 0 && service_catalog_selection_less(candidate, state.selections[position - 1]) {
			state.selections[position] = state.selections[position - 1]
			position -= 1
		}
		state.selections[position] = candidate
	}
}

@(private)
service_catalog_selection_less :: proc(left, right: Service_Explicit_Selection) -> bool {
	left_copy := left
	right_copy := right
	left_precedence := service_catalog_source_precedence(left.scope.source)
	right_precedence := service_catalog_source_precedence(right.scope.source)
	if left_precedence != right_precedence do return left_precedence > right_precedence
	if left.language.id != right.language.id do return left.language.id < right.language.id
	left_scope := service_scope_text_string(&left_copy.scope.name)
	right_scope := service_scope_text_string(&right_copy.scope.name)
	if left_scope != right_scope do return strings.compare(left_scope, right_scope) < 0
	left_identity := service_identity_string(&left_copy.service_identity)
	right_identity := service_identity_string(&right_copy.service_identity)
	return strings.compare(left_identity, right_identity) < 0
}

@(private)
service_catalog_inspection_write :: proc(
	state: ^Service_Catalog_State,
	inspection: ^Service_Catalog_Inspection,
) {
	if state == nil || inspection == nil do return
	inspection^ = Service_Catalog_Inspection {
		catalog_id = state.catalog_id,
		catalog_generation = state.catalog_generation,
		language_generation = state.language_generation,
		definition_count = state.definition_count,
		selection_count = state.selection_count,
		source_count = state.source_count,
		conflict_count = state.conflict_count,
		participant_count = state.participant_count,
		latest_rejection = state.latest_rejection,
	}
	copy(inspection.definitions[:state.definition_count], state.definitions[:state.definition_count])
	copy(inspection.selections[:state.selection_count], state.selections[:state.selection_count])
	copy(inspection.sources[:state.source_count], state.sources[:state.source_count])
	copy(inspection.conflicts[:state.conflict_count], state.conflicts[:state.conflict_count])
	copy(inspection.participants[:state.participant_count], state.participants[:state.participant_count])
}

@(private)
service_catalog_state :: proc(catalog: ^Service_Catalog) -> ^Service_Catalog_State {
	if catalog == nil || catalog.state == nil || catalog.closed do return nil
	return cast(^Service_Catalog_State)catalog.state
}

@(private)
service_source_scope_valid :: proc(
	source: Service_Contribution_Source,
	kind: Service_Scope_Kind,
	scope: string,
) -> bool {
	if len(scope) > MAX_SERVICE_SCOPE_BYTES || !utf8.valid_string(scope) || strings.index_byte(scope, 0) >= 0 {
		return false
	}
	switch source {
	case .Factory, .Personal:
		return kind == .Global && len(scope) == 0
	case .Package:
		return kind == .Package && len(scope) > 0
	case .Project:
		return kind == .Project_Membership && len(scope) > 0
	case .Invalid:
		return false
	}
	return false
}

@(private)
service_language_valid :: proc(
	value: language.Language_Identity,
	generation: language.Language_Catalog_Generation,
) -> bool {
	return value.id != language.Language_ID(0) &&
		value.generation != language.Language_Generation(0) &&
		u64(value.generation) == u64(generation) && value.name.length > 0 &&
		value.name.length <= language.MAX_LANGUAGE_NAME_BYTES
}

@(private)
service_language_reference :: proc(value: language.Language_Identity) -> Service_Language_Reference {
	return {id = value.id, generation = value.generation}
}

@(private)
service_identity_valid :: proc(value: string) -> bool {
	if len(value) == 0 || len(value) > MAX_SERVICE_IDENTITY_BYTES || !utf8.valid_string(value) do return false
	for byte, index in transmute([]u8)value {
		if index == 0 {
			if byte < 'a' || byte > 'z' do return false
		} else if (byte < 'a' || byte > 'z') && (byte < '0' || byte > '9') && byte != '-' {
			return false
		}
	}
	return true
}

@(private)
service_catalog_source_precedence :: proc(source: Service_Contribution_Source) -> u8 {
	switch source {
	case .Project:
		return 4
	case .Personal:
		return 3
	case .Package:
		return 2
	case .Factory:
		return 1
	case .Invalid:
		return 0
	}
	return 0
}

@(private)
service_identity_text_copy :: proc(value: string) -> Service_Identity_Text {
	result: Service_Identity_Text
	result.length = u16(copy(result.bytes[:], transmute([]u8)value))
	return result
}

@(private)
service_scope_text_copy :: proc(value: string) -> Service_Scope_Text {
	result: Service_Scope_Text
	result.length = u16(copy(result.bytes[:], transmute([]u8)value))
	return result
}

@(private)
service_provenance_text_copy :: proc(value: string) -> Service_Provenance_Text {
	result: Service_Provenance_Text
	result.length = u16(copy(result.bytes[:], transmute([]u8)value))
	return result
}

@(private)
service_root_text_copy :: proc(value: string) -> Service_Root_Text {
	result: Service_Root_Text
	result.length = u16(copy(result.bytes[:], transmute([]u8)value))
	return result
}

@(private)
service_identity_string :: proc(value: ^Service_Identity_Text) -> string {
	if value == nil do return ""
	return string(value.bytes[:value.length])
}

@(private)
service_scope_text_string :: proc(value: ^Service_Scope_Text) -> string {
	if value == nil do return ""
	return string(value.bytes[:value.length])
}

@(private)
service_catalog_failure :: proc(
	code: Service_Catalog_Failure_Code,
	field := Service_Catalog_Field.None,
	source := Service_Contribution_Source.Invalid,
	source_generation := Service_Source_Generation(0),
) -> Service_Catalog_Failure {
	return Service_Catalog_Failure {
		code = code,
		field = field,
		source = source,
		source_generation = source_generation,
	}
}
