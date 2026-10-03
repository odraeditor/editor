// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_formatter

import "../language"
import "base:runtime"

@(private)
Catalog_State :: struct {
	id:             Catalog_ID,
	generation:     Catalog_Generation,
	definitions:    [dynamic]Formatter_Record,
	selections:     [dynamic]Selection_Record,
	latest_failure: Failure,
	allocator:      runtime.Allocator,
}

catalog_init :: proc(catalog: ^Catalog, id: Catalog_ID, allocator := context.allocator) -> (bool, Failure) {
	if catalog == nil || id == Catalog_ID(0) || allocator.procedure == nil do return false, Failure{code = .Invalid_Input}
	catalog^ = {}
	state, allocation_error := new(Catalog_State, allocator)
	if allocation_error != nil do return false, Failure{code = .Allocation}
	state^ = {id = id, allocator = allocator}
	catalog.state = state
	return true, {}
}

catalog_publish :: proc(catalog: ^Catalog, proposal: Catalog_Proposal) -> (Catalog_Generation, bool, Failure) {
	state := catalog_state(catalog)
	if state == nil do return 0, false, Failure{code = .Closed}
	if proposal.generation == Catalog_Generation(0) || proposal.generation <= state.generation {
		return 0, false, catalog_fail(state, .Stale_Generation)
	}
	if len(proposal.definitions) > MAX_FORMATTERS || len(proposal.selections) > MAX_FORMATTER_LANGUAGES {
		return 0, false, catalog_fail(state, .Invalid_Catalog)
	}
	definitions, definitions_error := make([dynamic]Formatter_Record, 0, len(proposal.definitions), state.allocator)
	if definitions_error != nil do return 0, false, catalog_fail(state, .Allocation)
	defer if definitions != nil do delete(definitions)
	selections, selections_error := make([dynamic]Selection_Record, 0, len(proposal.selections), state.allocator)
	if selections_error != nil do return 0, false, catalog_fail(state, .Allocation)
	defer if selections != nil do delete(selections)

	for candidate, index in proposal.definitions {
		record: Formatter_Record
		copied, failure := formatter_record_copy(&record, state.id, proposal.generation, Formatter_ID(index + 1), candidate)
		if !copied {
			state.latest_failure = failure
			return 0, false, failure
		}
		for previous_index in 0..<len(definitions) {
			previous := &definitions[previous_index]
			if text_view(&previous.identity) == text_view(&record.identity) &&
			   previous.scope.source == record.scope.source && previous.scope.kind == record.scope.kind &&
			   text_view(&previous.scope.name) == text_view(&record.scope.name) {
				return 0, false, catalog_fail(state, .Duplicate_Identity)
			}
		}
		_, append_error := append(&definitions, record)
		if append_error != nil do return 0, false, catalog_fail(state, .Allocation)
	}
	for candidate in proposal.selections {
		record: Selection_Record
		if !selection_record_copy(&record, candidate) do return 0, false, catalog_fail(state, .Invalid_Selection)
		for previous_index in 0..<len(selections) {
			previous := &selections[previous_index]
			if previous.language == record.language && previous.scope.source == record.scope.source &&
			   previous.scope.kind == record.scope.kind && text_view(&previous.scope.name) == text_view(&record.scope.name) {
				return 0, false, catalog_fail(state, .Invalid_Selection)
			}
		}
		_, append_error := append(&selections, record)
		if append_error != nil do return 0, false, catalog_fail(state, .Allocation)
	}

	if state.definitions != nil do delete(state.definitions)
	if state.selections != nil do delete(state.selections)
	state.definitions = definitions
	state.selections = selections
	state.generation = proposal.generation
	state.latest_failure = {}
	definitions = nil
	selections = nil
	return state.generation, true, {}
}

catalog_resolve :: proc(catalog: ^Catalog, query: Resolution_Query) -> (Selection_Result, bool, Failure) {
	state := catalog_state(catalog)
	if state == nil do return {}, false, Failure{code = .Closed}
	if !language_valid(query.language) do return {}, false, catalog_fail(state, .Invalid_Selection)
	if query.project_trusted && query.project_membership == "" do return {}, false, catalog_fail(state, .Invalid_Selection)

	best := -1
	best_source := Contribution_Source.Invalid
	kind := Selection_Kind.None
	for selection_index in 0..<len(state.selections) {
		selection := &state.selections[selection_index]
		if selection.language != language_reference(query.language) || !scope_applies(&selection.scope, query) do continue
		for definition_index in 0..<len(state.definitions) {
			definition := &state.definitions[definition_index]
			if text_view(&definition.identity) != text_view(&selection.formatter_identity) ||
			   !formatter_supports_language(definition, query.language) || !scope_applies(&definition.scope, query) {
				continue
			}
			if selection.scope.source > best_source {
				best = definition_index
				best_source = selection.scope.source
				kind = .Explicit_Project if selection.scope.source == .Project else .Explicit_Personal
			} else if selection.scope.source == best_source {
				return {}, false, catalog_fail(state, .Ambiguous_Selection)
			}
		}
	}
	if best < 0 {
		candidate_count := 0
		default_count := 0
		for definition_index in 0..<len(state.definitions) {
			definition := &state.definitions[definition_index]
			if !formatter_supports_language(definition, query.language) || !scope_applies(&definition.scope, query) do continue
			if definition.scope.source > best_source {
				best_source = definition.scope.source
				candidate_count = 1
				default_count = 1 if definition.default_selection else 0
				best = definition_index
			} else if definition.scope.source == best_source {
				candidate_count += 1
				if definition.default_selection {
					default_count += 1
					best = definition_index
				}
			}
		}
		if default_count == 1 {
			kind = .Unique_Default
		} else if default_count > 1 || candidate_count > 1 {
			return {}, false, catalog_fail(state, .Ambiguous_Selection)
		} else if candidate_count == 1 {
			kind = .Sole_Candidate
		}
	}
	if best < 0 do return {}, false, catalog_fail(state, .No_Selection)
	definition := &state.definitions[best]
	return {
		language = query.language,
		formatter = definition.handle,
		kind = kind,
		availability = definition.profile.availability,
	}, true, {}
}

catalog_definition :: proc(catalog: ^Catalog, handle: Formatter_Handle) -> (Formatter_Record, bool, Failure) {
	state := catalog_state(catalog)
	if state == nil do return {}, false, Failure{code = .Closed}
	if handle.catalog_id != state.id || handle.catalog_generation != state.generation {
		return {}, false, catalog_fail(state, .Stale_Generation)
	}
	for index in 0..<len(state.definitions) {
		if state.definitions[index].handle == handle do return state.definitions[index], true, {}
	}
	return {}, false, catalog_fail(state, .Invalid_Definition)
}

catalog_confirm_profile :: proc(
	catalog: ^Catalog,
	handle: Formatter_Handle,
	profile_generation: Profile_Generation,
	availability: Availability,
	resolved_path := "",
	version := "",
	provenance := "",
) -> (bool, Failure) {
	state := catalog_state(catalog)
	if state == nil do return false, Failure{code = .Closed}
	if profile_generation == Profile_Generation(0) || availability == .Unknown ||
	   handle.catalog_id != state.id || handle.catalog_generation != state.generation {
		return false, catalog_fail(state, .Stale_Generation)
	}
	for index in 0..<len(state.definitions) {
		record := &state.definitions[index]
		if record.handle != handle do continue
		if profile_generation <= record.profile.generation do return false, catalog_fail(state, .Stale_Generation)
		if availability == .Available && (resolved_path == "" || version == "") {
			return false, catalog_fail(state, .Invalid_Definition)
		}
		if text_view(&record.profile.probe.expected_exact) != "" &&
		   version != text_view(&record.profile.probe.expected_exact) {
			record.profile.generation = profile_generation
			record.profile.availability = .Changed
			copy_text(version, &record.profile.discovered_version, true)
			return false, catalog_fail(state, .Version_Mismatch)
		}
		next := record.profile
		next.generation = profile_generation
		next.availability = availability
		if !copy_text(resolved_path, &next.resolved, true) || !copy_text(version, &next.discovered_version, true) ||
		   !copy_text(provenance, &next.provenance, true) {
			return false, catalog_fail(state, .Invalid_Definition)
		}
		record.profile = next
		return true, {}
	}
	return false, catalog_fail(state, .Invalid_Definition)
}

catalog_inspect :: proc(catalog: ^Catalog) -> (Catalog_Inspection, bool) {
	state := catalog_state(catalog)
	if state == nil do return {}, false
	return {
		id = state.id,
		generation = state.generation,
		definitions = u16(len(state.definitions)),
		selections = u16(len(state.selections)),
		retained_bytes = u64(cap(state.definitions)) * u64(size_of(Formatter_Record)) +
			u64(cap(state.selections)) * u64(size_of(Selection_Record)),
		latest_failure = state.latest_failure,
	}, true
}

catalog_close :: proc(catalog: ^Catalog) -> bool {
	state := catalog_state(catalog)
	if state == nil do return false
	if state.definitions != nil do delete(state.definitions)
	if state.selections != nil do delete(state.selections)
	allocator := state.allocator
	free(state, allocator)
	catalog^ = {}
	return true
}

@(private)
catalog_state :: proc(catalog: ^Catalog) -> ^Catalog_State {
	if catalog == nil || catalog.state == nil do return nil
	return cast(^Catalog_State)catalog.state
}

@(private)
formatter_record_copy :: proc(
	record: ^Formatter_Record,
	catalog_id: Catalog_ID,
	generation: Catalog_Generation,
	id: Formatter_ID,
	proposal: Formatter_Proposal,
) -> (bool, Failure) {
	if record == nil || proposal.kind == .Invalid || proposal.source == .Invalid ||
	   proposal.source_generation == Source_Generation(0) || len(proposal.languages) == 0 ||
	   len(proposal.languages) > MAX_FORMATTER_LANGUAGES || len(proposal.arguments) > MAX_ARGUMENTS ||
	   len(proposal.environment) > MAX_ENVIRONMENT || card(proposal.scopes) == 0 ||
	   proposal.root_policy == .Invalid || !formatter_limits_valid(proposal.limits) ||
	   !source_scope_valid(proposal.source, proposal.scope_kind, proposal.scope) ||
	   (proposal.kind == .External && (proposal.executable == "" || proposal.input_mode == .Invalid ||
	   proposal.output_mode == .Invalid)) {
		return false, Failure{code = .Invalid_Definition}
	}
	record^ = {
		handle = {catalog_id = catalog_id, catalog_generation = generation, id = id, generation = Formatter_Generation(generation)},
		kind = proposal.kind,
		input_mode = proposal.input_mode,
		output_mode = proposal.output_mode,
		scopes = proposal.scopes,
		root_policy = proposal.root_policy,
		limits = proposal.limits,
		scope = {source = proposal.source, kind = proposal.scope_kind},
		source_generation = proposal.source_generation,
		default_selection = proposal.default_selection,
		profile = {availability = .Unknown},
	}
	if !copy_text(proposal.identity, &record.identity) || !copy_text(proposal.name, &record.name) ||
	   !copy_text(proposal.scope, &record.scope.name, proposal.scope_kind == .Global) ||
	   !copy_text(proposal.provenance, &record.provenance) {
		return false, Failure{code = .Invalid_Definition}
	}
	for selected_language, index in proposal.languages {
		if !language_valid(selected_language) do return false, Failure{code = .Invalid_Definition}
		record.languages[index] = language_reference(selected_language)
	}
	record.language_count = u16(len(proposal.languages))
	for argument, index in proposal.arguments {
		if !copy_text(argument, &record.arguments[index]) do return false, Failure{code = .Invalid_Definition}
	}
	record.argument_count = u8(len(proposal.arguments))
	for entry, index in proposal.environment {
		if !copy_text(entry, &record.environment[index]) do return false, Failure{code = .Invalid_Definition}
	}
	record.environment_count = u8(len(proposal.environment))
	if proposal.kind == .External && !copy_text(proposal.executable, &record.profile.configured) {
		return false, Failure{code = .Invalid_Definition}
	}
	if len(proposal.version_probe.arguments) > MAX_ARGUMENTS {
		return false, Failure{code = .Invalid_Definition}
	}
	for argument, index in proposal.version_probe.arguments {
		if !copy_text(argument, &record.profile.probe.arguments[index]) do return false, Failure{code = .Invalid_Definition}
	}
	record.profile.probe.argument_count = u8(len(proposal.version_probe.arguments))
	if !copy_text(proposal.version_probe.expected_exact, &record.profile.probe.expected_exact, true) {
		return false, Failure{code = .Invalid_Definition}
	}
	return true, {}
}

@(private)
selection_record_copy :: proc(record: ^Selection_Record, proposal: Selection_Proposal) -> bool {
	if record == nil || !language_valid(proposal.language) || proposal.formatter_identity == "" ||
	   proposal.source_generation == Source_Generation(0) ||
	   (proposal.source != .Personal && proposal.source != .Project) ||
	   !source_scope_valid(proposal.source, proposal.scope_kind, proposal.scope) {
		return false
	}
	record^ = {
		language = language_reference(proposal.language),
		scope = {source = proposal.source, kind = proposal.scope_kind},
		source_generation = proposal.source_generation,
	}
	return copy_text(proposal.formatter_identity, &record.formatter_identity) &&
		copy_text(proposal.scope, &record.scope.name, proposal.scope_kind == .Global)
}

@(private)
source_scope_valid :: proc(source: Contribution_Source, kind: Scope_Kind, name: string) -> bool {
	switch source {
	case .Invalid:
		return false
	case .Factory, .Personal:
		return kind == .Global && name == ""
	case .Package:
		return kind == .Package && name != ""
	case .Project:
		return kind == .Project_Membership && name != ""
	}
	return false
}

@(private)
scope_applies :: proc(scope: ^Source_Scope, query: Resolution_Query) -> bool {
	if scope == nil do return false
	switch scope.kind {
	case .Invalid:
		return false
	case .Global, .Package:
		return true
	case .Project_Membership:
		return query.project_trusted && text_view(&scope.name) == query.project_membership
	}
	return false
}

@(private)
formatter_supports_language :: proc(record: ^Formatter_Record, selected: language.Language_Identity) -> bool {
	if record == nil do return false
	for index in 0..<int(record.language_count) {
		if record.languages[index] == language_reference(selected) do return true
	}
	return false
}

@(private)
catalog_fail :: proc(state: ^Catalog_State, code: Failure_Code) -> Failure {
	state.latest_failure = {code = code}
	return state.latest_failure
}
