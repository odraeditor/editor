// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "base:runtime"
import "core:strings"
import "core:unicode/utf8"

/* Language_Catalog_ID identifies one native catalog owner. */
Language_Catalog_ID :: distinct u32
/* Language_Catalog_Generation identifies one immutable catalog snapshot. */
Language_Catalog_Generation :: distinct u64
/* Language_Source_Generation identifies one exact contribution generation. */
Language_Source_Generation :: distinct u64

/* Language_Contribution_Source defines deterministic contribution precedence. */
Language_Contribution_Source :: enum u8 {
	Invalid,
	Factory,
	Package,
	Personal,
	Project,
}

/* Language_Selector_Kind identifies the association rule that matched. */
Language_Selector_Kind :: enum u8 {
	Invalid,
	Explicit,
	Exact_Filename,
	Filename_Suffix,
}

/* Language_Catalog_Failure_Code classifies one contained catalog rejection. */
Language_Catalog_Failure_Code :: enum u16 {
	None,
	Invalid_Catalog,
	Closed_Catalog,
	Invalid_Generation,
	Stale_Generation,
	Language_Limit,
	Selector_Limit,
	Identity_Limit,
	Display_Name_Limit,
	Scope_Limit,
	Provenance_Limit,
	Invalid_Identity,
	Invalid_Source,
	Invalid_Scope,
	Invalid_Exact_Filename,
	Invalid_Suffix,
	Duplicate_Identity,
	Duplicate_Selector,
	Ambiguous_Selector,
	Unknown_Language,
	No_Match,
	Generation_Limit,
	Allocation,
}

/* Language_Catalog_Field identifies the rejected bounded field. */
Language_Catalog_Field :: enum u8 {
	None,
	Catalog_Generation,
	Source_Generation,
	Languages,
	Selectors,
	Identity,
	Display_Name,
	Scope,
	Exact_Filename,
	Suffix,
	Provenance,
}

/* Language_Display_Name is one bounded copied user-facing name. */
Language_Display_Name :: struct {
	bytes:  [MAX_LANGUAGE_DISPLAY_NAME_BYTES]u8,
	length: u16,
}

/* Language_Scope_Text is one bounded copied contribution scope. */
Language_Scope_Text :: struct {
	bytes:  [MAX_LANGUAGE_SCOPE_BYTES]u8,
	length: u16,
}

/* Language_Definition_Candidate is borrowed only during atomic confirmation. */
Language_Definition_Candidate :: struct {
	language_id:       Language_ID,
	identity:          string,
	display_name:      string,
	source:            Language_Contribution_Source,
	scope:             string,
	source_generation: Language_Source_Generation,
	exact_filenames:   []string,
	suffixes:          []string,
	provenance:        string,
}

/* Language_Catalog_Candidate is one complete proposed immutable generation. */
Language_Catalog_Candidate :: struct {
	generation:  Language_Catalog_Generation,
	definitions: []Language_Definition_Candidate,
}

/* Language_Definition_Descriptor is one bounded copied confirmed definition. */
Language_Definition_Descriptor :: struct {
	language:           Language_Identity,
	display_name:       Language_Display_Name,
	source:             Language_Contribution_Source,
	scope:              Language_Scope_Text,
	source_generation:  Language_Source_Generation,
	exact_filenames:    [MAX_LANGUAGE_EXACT_FILENAMES]Association_Text,
	exact_filename_count: u8,
	suffixes:           [MAX_LANGUAGE_SUFFIXES]Association_Text,
	suffix_count:       u8,
	provenance:         Provenance_Text,
}

/* Language_Catalog_Failure is copied and never retains candidate storage. */
Language_Catalog_Failure :: struct {
	code:              Language_Catalog_Failure_Code,
	field:             Language_Catalog_Field,
	source:            Language_Contribution_Source,
	source_generation: Language_Source_Generation,
	definition_index:  u16,
	selector_index:    u16,
	limit:             u64,
	actual:            u64,
}

/* Language_Catalog_Association is one copied deterministic resolution trace. */
Language_Catalog_Association :: struct {
	catalog_id:         Language_Catalog_ID,
	catalog_generation: Language_Catalog_Generation,
	language:           Language_Identity,
	kind:               Language_Selector_Kind,
	selector:           Association_Text,
	source:             Language_Contribution_Source,
	scope:              Language_Scope_Text,
	source_generation:  Language_Source_Generation,
	shadowed:           u16,
}

/* Language_Catalog_Inspection is a complete copied bounded snapshot. */
Language_Catalog_Inspection :: struct {
	catalog_id:         Language_Catalog_ID,
	catalog_generation: Language_Catalog_Generation,
	definition_count:   u16,
	selector_count:     u16,
	definitions:        [MAX_LANGUAGES]Language_Definition_Descriptor,
	latest_rejection:   Language_Catalog_Failure,
}

/* Language_Catalog owns one atomically replaceable immutable snapshot. */
Language_Catalog :: struct {
	state:  rawptr,
	closed: bool,
}

@(private)
Language_Catalog_State :: struct {
	catalog_id:         Language_Catalog_ID,
	catalog_generation: Language_Catalog_Generation,
	next_language_id:   Language_ID,
	definition_count:   u16,
	selector_count:     u16,
	definitions:        [MAX_LANGUAGES]Language_Definition_Descriptor,
	latest_rejection:   Language_Catalog_Failure,
	allocator:          runtime.Allocator,
}

/* language_catalog_init creates one empty bounded catalog owner. */
language_catalog_init :: proc(
	catalog: ^Language_Catalog,
	catalog_id: Language_Catalog_ID,
	allocator := context.allocator,
) -> (ok: bool, failure: Language_Catalog_Failure) {
	if catalog == nil || catalog_id == Language_Catalog_ID(0) {
		return false, language_catalog_failure(.Invalid_Catalog)
	}
	catalog^ = {}
	if allocator.procedure == nil {
		return false, language_catalog_failure(.Allocation)
	}
	state, allocation_error := new(Language_Catalog_State, allocator)
	if allocation_error != nil {
		return false, language_catalog_failure(.Allocation)
	}
	state^ = Language_Catalog_State {
		catalog_id = catalog_id,
		next_language_id = 1,
		allocator = allocator,
	}
	catalog.state = state
	return true, {}
}

/* language_catalog_close releases the complete confirmed snapshot exactly once. */
language_catalog_close :: proc(
	catalog: ^Language_Catalog,
) -> (ok: bool, failure: Language_Catalog_Failure) {
	state := language_catalog_state(catalog)
	if state == nil {
		return false, language_catalog_failure(.Invalid_Catalog)
	}
	allocator := state.allocator
	free(state, allocator)
	catalog^ = Language_Catalog{closed = true}
	return true, {}
}

/* language_catalog_clone copies one complete snapshot for prepared publication. */
language_catalog_clone :: proc(
	source, destination: ^Language_Catalog,
	allocator := context.allocator,
) -> (ok: bool, failure: Language_Catalog_Failure) {
	current := language_catalog_state(source)
	if current == nil || destination == nil || destination == source {
		return false, language_catalog_failure(.Invalid_Catalog)
	}
	destination^ = {}
	if allocator.procedure == nil {
		return false, language_catalog_failure(.Allocation)
	}
	next, allocation_error := new(Language_Catalog_State, allocator)
	if allocation_error != nil {
		return false, language_catalog_failure(.Allocation)
	}
	next^ = current^
	next.allocator = allocator
	destination.state = next
	return true, {}
}

/* language_catalog_confirm validates and publishes one complete candidate atomically. */
language_catalog_confirm :: proc(
	catalog: ^Language_Catalog,
	expected: Language_Catalog_Generation,
	candidate: Language_Catalog_Candidate,
) -> (inspection: Language_Catalog_Inspection, ok: bool, failure: Language_Catalog_Failure) {
	current := language_catalog_state(catalog)
	if current == nil {
		return {}, false, language_catalog_failure(.Invalid_Catalog)
	}
	if expected != current.catalog_generation {
		failure = language_catalog_failure(.Stale_Generation, .Catalog_Generation)
		failure.limit = u64(current.catalog_generation)
		failure.actual = u64(expected)
		current.latest_rejection = failure
		return language_catalog_inspection(current), false, failure
	}
	if candidate.generation == Language_Catalog_Generation(0) {
		failure = language_catalog_failure(.Invalid_Generation, .Catalog_Generation)
		current.latest_rejection = failure
		return language_catalog_inspection(current), false, failure
	}
	if candidate.generation <= current.catalog_generation {
		failure = language_catalog_failure(.Stale_Generation, .Catalog_Generation)
		failure.limit = u64(current.catalog_generation) + 1
		failure.actual = u64(candidate.generation)
		current.latest_rejection = failure
		return language_catalog_inspection(current), false, failure
	}
	if len(candidate.definitions) > MAX_LANGUAGES {
		failure = language_catalog_failure(.Language_Limit, .Languages)
		failure.limit = MAX_LANGUAGES
		failure.actual = u64(len(candidate.definitions))
		current.latest_rejection = failure
		return language_catalog_inspection(current), false, failure
	}
	next, allocation_error := new(Language_Catalog_State, current.allocator)
	if allocation_error != nil {
		failure = language_catalog_failure(.Allocation)
		current.latest_rejection = failure
		return language_catalog_inspection(current), false, failure
	}
	next^ = Language_Catalog_State {
		catalog_id = current.catalog_id,
		catalog_generation = candidate.generation,
		next_language_id = current.next_language_id,
		allocator = current.allocator,
	}
	accepted := true
	for definition, index in candidate.definitions {
		descriptor, copied, copy_failure := language_catalog_definition_copy(
			definition,
			u16(index),
			candidate.generation,
		)
		if !copied {
			failure = copy_failure
			accepted = false
			break
		}
		next.definitions[index] = descriptor
		next.definition_count += 1
		next.selector_count += u16(descriptor.exact_filename_count) + u16(descriptor.suffix_count)
		if next.selector_count > MAX_LANGUAGE_ASSOCIATIONS {
			failure = language_catalog_failure(.Selector_Limit, .Selectors, definition.source, definition.source_generation)
			failure.definition_index = u16(index)
			failure.limit = MAX_LANGUAGE_ASSOCIATIONS
			failure.actual = u64(next.selector_count)
			accepted = false
			break
		}
	}
	if accepted {
		failure = language_catalog_conflict(next)
		accepted = failure.code == .None
	}
	if accepted {
		language_catalog_sort(next)
		accepted, failure = language_catalog_assign_identities(next, current)
	}
	if !accepted {
		free(next, current.allocator)
		current.latest_rejection = failure
		return language_catalog_inspection(current), false, failure
	}
	old := current
	catalog.state = next
	free(old, next.allocator)
	return language_catalog_inspection(next), true, {}
}

/* language_catalog_inspect returns a complete pointer-free catalog copy. */
language_catalog_inspect :: proc(
	catalog: ^Language_Catalog,
) -> (inspection: Language_Catalog_Inspection, ok: bool, failure: Language_Catalog_Failure) {
	state := language_catalog_state(catalog)
	if state == nil {
		return {}, false, language_catalog_failure(.Invalid_Catalog)
	}
	return language_catalog_inspection(state), true, {}
}

/* language_catalog_resolve associates one path or explicit admitted identity. */
language_catalog_resolve :: proc(
	catalog: ^Language_Catalog,
	target_path: string,
	explicit_identity := "",
	project_scope := "",
) -> (association: Language_Catalog_Association, ok: bool, failure: Language_Catalog_Failure) {
	state := language_catalog_state(catalog)
	if state == nil {
		return {}, false, language_catalog_failure(.Invalid_Catalog)
	}
	if state.catalog_generation == Language_Catalog_Generation(0) {
		return {}, false, language_catalog_failure(.No_Match)
	}
	if len(explicit_identity) > 0 {
		if !language_catalog_identity_valid(explicit_identity) {
			return {}, false, language_catalog_failure(.Unknown_Language, .Identity)
		}
		return language_catalog_resolve_explicit(state, explicit_identity, project_scope)
	}
	return language_catalog_resolve_path(state, target_path, project_scope)
}

@(private)
language_catalog_resolve_explicit :: proc(
	state: ^Language_Catalog_State,
	identity, project_scope: string,
) -> (association: Language_Catalog_Association, ok: bool, failure: Language_Catalog_Failure) {
	best_index := -1
	best_precedence: u8
	shadowed: u16
	for index in 0 ..< int(state.definition_count) {
		definition := &state.definitions[index]
		if language_name_string(&definition.language.name) != identity ||
		   !language_catalog_scope_applies(definition, project_scope) {
			continue
		}
		precedence := language_catalog_source_precedence(definition.source)
		if best_index < 0 || precedence > best_precedence {
			if best_index >= 0 do shadowed += 1
			best_index = index
			best_precedence = precedence
		} else if precedence == best_precedence {
			return {}, false, language_catalog_failure(
				.Ambiguous_Selector,
				.Identity,
				definition.source,
				definition.source_generation,
			)
		} else {
			shadowed += 1
		}
	}
	if best_index < 0 {
		return {}, false, language_catalog_failure(.Unknown_Language, .Identity)
	}
	definition := &state.definitions[best_index]
	selector := language_catalog_association_copy(identity)
	return language_catalog_association(state, definition, .Explicit, selector, shadowed), true, {}
}

@(private)
language_catalog_resolve_path :: proc(
	state: ^Language_Catalog_State,
	target_path, project_scope: string,
) -> (association: Language_Catalog_Association, ok: bool, failure: Language_Catalog_Failure) {
	basename := language_catalog_basename(target_path)
	best_index := -1
	best_kind := Language_Selector_Kind.Invalid
	best_selector := Association_Text{}
	best_precedence: u8
	best_specificity: u16
	shadowed: u16
	for index in 0 ..< int(state.definition_count) {
		definition := &state.definitions[index]
		if !language_catalog_scope_applies(definition, project_scope) do continue
		kind, selector, matched := language_catalog_definition_match(definition, basename, target_path)
		if !matched do continue
		precedence := language_catalog_source_precedence(definition.source)
		specificity := language_catalog_selector_specificity(kind, selector)
		if best_index < 0 || precedence > best_precedence ||
		   (precedence == best_precedence && specificity > best_specificity) {
			if best_index >= 0 do shadowed += 1
			best_index = index
			best_kind = kind
			best_selector = selector
			best_precedence = precedence
			best_specificity = specificity
		} else if precedence == best_precedence && specificity == best_specificity &&
		          definition.language.id != state.definitions[best_index].language.id {
			field := Language_Catalog_Field.Suffix
			if kind == .Exact_Filename do field = .Exact_Filename
			return {}, false, language_catalog_failure(
				.Ambiguous_Selector,
				field,
				definition.source,
				definition.source_generation,
			)
		} else {
			shadowed += 1
		}
	}
	if best_index < 0 {
		return {}, false, language_catalog_failure(.No_Match)
	}
	return language_catalog_association(
		state,
		&state.definitions[best_index],
		best_kind,
		best_selector,
		shadowed,
	), true, {}
}

@(private)
language_catalog_definition_copy :: proc(
	candidate: Language_Definition_Candidate,
	definition_index: u16,
	catalog_generation: Language_Catalog_Generation,
) -> (descriptor: Language_Definition_Descriptor, ok: bool, failure: Language_Catalog_Failure) {
	failure = language_catalog_definition_validate(candidate, definition_index)
	if failure.code != .None do return {}, false, failure
	descriptor.language.generation = Language_Generation(catalog_generation)
	descriptor.language.id = candidate.language_id
	descriptor.language.name = language_catalog_name_copy(candidate.identity)
	descriptor.display_name = language_catalog_display_name_copy(candidate.display_name)
	descriptor.source = candidate.source
	descriptor.scope = language_catalog_scope_copy(candidate.scope)
	descriptor.source_generation = candidate.source_generation
	descriptor.exact_filename_count = u8(len(candidate.exact_filenames))
	for value, index in candidate.exact_filenames {
		descriptor.exact_filenames[index] = language_catalog_association_copy(value)
	}
	descriptor.suffix_count = u8(len(candidate.suffixes))
	for value, index in candidate.suffixes {
		descriptor.suffixes[index] = language_catalog_association_copy(value)
	}
	descriptor.provenance = provenance_copy(candidate.provenance)
	return descriptor, true, {}
}

@(private)
language_catalog_definition_validate :: proc(
	candidate: Language_Definition_Candidate,
	definition_index: u16,
) -> Language_Catalog_Failure {
	if !language_catalog_identity_valid(candidate.identity) {
		code := Language_Catalog_Failure_Code.Invalid_Identity
		if len(candidate.identity) > MAX_LANGUAGE_NAME_BYTES do code = .Identity_Limit
		failure := language_catalog_failure(code, .Identity, candidate.source, candidate.source_generation)
		failure.definition_index = definition_index
		failure.limit = MAX_LANGUAGE_NAME_BYTES
		failure.actual = u64(len(candidate.identity))
		return failure
	}
	if candidate.language_id != Language_ID(0) && candidate.source != .Factory {
		failure := language_catalog_failure(.Invalid_Identity, .Identity, candidate.source, candidate.source_generation)
		failure.definition_index = definition_index
		return failure
	}
	if len(candidate.display_name) == 0 || len(candidate.display_name) > MAX_LANGUAGE_DISPLAY_NAME_BYTES ||
	   !utf8.valid_string(candidate.display_name) {
		failure := language_catalog_failure(.Display_Name_Limit, .Display_Name, candidate.source, candidate.source_generation)
		failure.definition_index = definition_index
		failure.limit = MAX_LANGUAGE_DISPLAY_NAME_BYTES
		failure.actual = u64(len(candidate.display_name))
		return failure
	}
	if language_catalog_source_precedence(candidate.source) == 0 {
		failure := language_catalog_failure(.Invalid_Source, .None, candidate.source, candidate.source_generation)
		failure.definition_index = definition_index
		return failure
	}
	if len(candidate.scope) > MAX_LANGUAGE_SCOPE_BYTES || !utf8.valid_string(candidate.scope) ||
	   strings.index_byte(candidate.scope, 0) >= 0 ||
	   (candidate.source == .Project && len(candidate.scope) == 0) {
		failure := language_catalog_failure(.Invalid_Scope, .Scope, candidate.source, candidate.source_generation)
		failure.definition_index = definition_index
		failure.limit = MAX_LANGUAGE_SCOPE_BYTES
		failure.actual = u64(len(candidate.scope))
		return failure
	}
	if candidate.source_generation == Language_Source_Generation(0) {
		failure := language_catalog_failure(.Invalid_Generation, .Source_Generation, candidate.source)
		failure.definition_index = definition_index
		return failure
	}
	if len(candidate.exact_filenames) > MAX_LANGUAGE_EXACT_FILENAMES ||
	   len(candidate.suffixes) > MAX_LANGUAGE_SUFFIXES ||
	   len(candidate.exact_filenames) + len(candidate.suffixes) > MAX_LANGUAGE_SELECTORS {
		failure := language_catalog_failure(.Selector_Limit, .Selectors, candidate.source, candidate.source_generation)
		failure.definition_index = definition_index
		failure.limit = MAX_LANGUAGE_SELECTORS
		failure.actual = u64(len(candidate.exact_filenames) + len(candidate.suffixes))
		return failure
	}
	for value, index in candidate.exact_filenames {
		if !language_catalog_exact_filename_valid(value) {
			failure := language_catalog_failure(.Invalid_Exact_Filename, .Exact_Filename, candidate.source, candidate.source_generation)
			failure.definition_index = definition_index
			failure.selector_index = u16(index)
			failure.limit = MAX_ASSOCIATION_BYTES
			failure.actual = u64(len(value))
			return failure
		}
		for previous in 0 ..< index {
			if value == candidate.exact_filenames[previous] {
				failure := language_catalog_failure(.Duplicate_Selector, .Exact_Filename, candidate.source, candidate.source_generation)
				failure.definition_index = definition_index
				failure.selector_index = u16(index)
				return failure
			}
		}
	}
	for value, index in candidate.suffixes {
		if !language_catalog_suffix_valid(value) {
			failure := language_catalog_failure(.Invalid_Suffix, .Suffix, candidate.source, candidate.source_generation)
			failure.definition_index = definition_index
			failure.selector_index = u16(index)
			failure.limit = MAX_ASSOCIATION_BYTES
			failure.actual = u64(len(value))
			return failure
		}
		for previous in 0 ..< index {
			if value == candidate.suffixes[previous] {
				failure := language_catalog_failure(.Duplicate_Selector, .Suffix, candidate.source, candidate.source_generation)
				failure.definition_index = definition_index
				failure.selector_index = u16(index)
				return failure
			}
		}
	}
	if len(candidate.provenance) == 0 || len(candidate.provenance) > MAX_PROVENANCE_BYTES ||
	   !utf8.valid_string(candidate.provenance) {
		failure := language_catalog_failure(.Provenance_Limit, .Provenance, candidate.source, candidate.source_generation)
		failure.definition_index = definition_index
		failure.limit = MAX_PROVENANCE_BYTES
		failure.actual = u64(len(candidate.provenance))
		return failure
	}
	return {}
}

@(private)
language_catalog_conflict :: proc(state: ^Language_Catalog_State) -> Language_Catalog_Failure {
	for left_index in 0 ..< int(state.definition_count) {
		left := &state.definitions[left_index]
		for right_index in left_index + 1 ..< int(state.definition_count) {
			right := &state.definitions[right_index]
		if left.source != right.source ||
		   language_scope_string(&left.scope) != language_scope_string(&right.scope) {
				continue
			}
			if language_name_string(&left.language.name) == language_name_string(&right.language.name) {
				failure := language_catalog_failure(.Duplicate_Identity, .Identity, left.source, left.source_generation)
				failure.definition_index = u16(right_index)
				return failure
			}
			for &left_selector in left.exact_filenames[:left.exact_filename_count] {
				for &right_selector in right.exact_filenames[:right.exact_filename_count] {
					if language_association_string(&left_selector) == language_association_string(&right_selector) {
						failure := language_catalog_failure(.Ambiguous_Selector, .Exact_Filename, left.source, left.source_generation)
						failure.definition_index = u16(right_index)
						return failure
					}
				}
			}
			for &left_selector in left.suffixes[:left.suffix_count] {
				for &right_selector in right.suffixes[:right.suffix_count] {
					if language_association_string(&left_selector) == language_association_string(&right_selector) {
						failure := language_catalog_failure(.Ambiguous_Selector, .Suffix, left.source, left.source_generation)
						failure.definition_index = u16(right_index)
						return failure
					}
				}
			}
		}
	}
	return {}
}

@(private)
language_catalog_assign_identities :: proc(
	next, current: ^Language_Catalog_State,
) -> (ok: bool, failure: Language_Catalog_Failure) {
	for index in 0 ..< int(next.definition_count) {
		definition := &next.definitions[index]
		name := language_name_string(&definition.language.name)
		id := definition.language.id
		for prior_index in 0 ..< int(current.definition_count) {
			prior := &current.definitions[prior_index]
			if language_name_string(&prior.language.name) == name {
				if id != Language_ID(0) && id != prior.language.id {
					return false, language_catalog_failure(.Invalid_Identity, .Identity)
				}
				id = prior.language.id
				break
			}
		}
		for assigned_index in 0 ..< index {
			assigned := &next.definitions[assigned_index]
			assigned_name := language_name_string(&assigned.language.name)
			if assigned_name == name {
				if id != Language_ID(0) && id != assigned.language.id {
					return false, language_catalog_failure(.Invalid_Identity, .Identity)
				}
				id = assigned.language.id
			} else if id != Language_ID(0) && id == assigned.language.id {
				return false, language_catalog_failure(.Invalid_Identity, .Identity)
			}
		}
		if id == Language_ID(0) {
			if next.next_language_id == Language_ID(0) {
				return false, language_catalog_failure(.Generation_Limit, .Identity)
			}
			id = next.next_language_id
		}
		if id >= next.next_language_id {
			if id == Language_ID(max(u32)) {
				next.next_language_id = 0
			} else {
				next.next_language_id = id + 1
			}
		}
		definition.language.id = id
	}
	return true, {}
}

@(private)
language_catalog_sort :: proc(state: ^Language_Catalog_State) {
	for index in 1 ..< int(state.definition_count) {
		candidate := state.definitions[index]
		position := index
		for position > 0 && language_catalog_definition_less(candidate, state.definitions[position - 1]) {
			state.definitions[position] = state.definitions[position - 1]
			position -= 1
		}
		state.definitions[position] = candidate
	}
}

@(private)
language_catalog_definition_less :: proc(left, right: Language_Definition_Descriptor) -> bool {
	left_copy := left
	right_copy := right
	left_precedence := language_catalog_source_precedence(left.source)
	right_precedence := language_catalog_source_precedence(right.source)
	if left_precedence != right_precedence do return left_precedence > right_precedence
	left_scope := language_scope_string(&left_copy.scope)
	right_scope := language_scope_string(&right_copy.scope)
	if left_scope != right_scope do return strings.compare(left_scope, right_scope) < 0
	left_name := language_name_string(&left_copy.language.name)
	right_name := language_name_string(&right_copy.language.name)
	if left_name != right_name do return strings.compare(left_name, right_name) < 0
	return left.source_generation < right.source_generation
}

@(private)
language_catalog_definition_match :: proc(
	definition: ^Language_Definition_Descriptor,
	basename, path: string,
) -> (kind: Language_Selector_Kind, selector: Association_Text, ok: bool) {
	for &candidate in definition.exact_filenames[:definition.exact_filename_count] {
		if language_association_string(&candidate) == basename {
			return .Exact_Filename, candidate, true
		}
	}
	best_length := 0
	for &candidate in definition.suffixes[:definition.suffix_count] {
		value := language_association_string(&candidate)
		if len(value) > best_length && language_catalog_has_suffix(path, value) {
			best_length = len(value)
			selector = candidate
			kind = .Filename_Suffix
			ok = true
		}
	}
	return
}

@(private)
language_catalog_selector_specificity :: proc(
	kind: Language_Selector_Kind,
	selector: Association_Text,
) -> u16 {
	if kind == .Exact_Filename do return u16(MAX_ASSOCIATION_BYTES + 1)
	return selector.length
}

@(private)
language_catalog_association :: proc(
	state: ^Language_Catalog_State,
	definition: ^Language_Definition_Descriptor,
	kind: Language_Selector_Kind,
	selector: Association_Text,
	shadowed: u16,
) -> Language_Catalog_Association {
	return Language_Catalog_Association {
		catalog_id = state.catalog_id,
		catalog_generation = state.catalog_generation,
		language = definition.language,
		kind = kind,
		selector = selector,
		source = definition.source,
		scope = definition.scope,
		source_generation = definition.source_generation,
		shadowed = shadowed,
	}
}

@(private)
language_catalog_inspection :: proc(state: ^Language_Catalog_State) -> Language_Catalog_Inspection {
	inspection := Language_Catalog_Inspection {
		catalog_id = state.catalog_id,
		catalog_generation = state.catalog_generation,
		definition_count = state.definition_count,
		selector_count = state.selector_count,
		latest_rejection = state.latest_rejection,
	}
	copy(inspection.definitions[:state.definition_count], state.definitions[:state.definition_count])
	return inspection
}

@(private)
language_catalog_state :: proc(catalog: ^Language_Catalog) -> ^Language_Catalog_State {
	if catalog == nil || catalog.state == nil || catalog.closed do return nil
	return cast(^Language_Catalog_State)catalog.state
}

@(private)
language_catalog_identity_valid :: proc(value: string) -> bool {
	if len(value) == 0 || len(value) > MAX_LANGUAGE_NAME_BYTES || !utf8.valid_string(value) do return false
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
language_catalog_exact_filename_valid :: proc(value: string) -> bool {
	return len(value) > 0 && len(value) <= MAX_ASSOCIATION_BYTES && utf8.valid_string(value) &&
		strings.index_byte(value, 0) < 0 && strings.index_byte(value, '/') < 0 &&
		strings.index_byte(value, '\\') < 0
}

@(private)
language_catalog_suffix_valid :: proc(value: string) -> bool {
	return language_catalog_exact_filename_valid(value) && len(value) > 1 && value[0] == '.'
}

@(private)
language_catalog_scope_applies :: proc(
	definition: ^Language_Definition_Descriptor,
	project_scope: string,
) -> bool {
	return definition.source != .Project ||
		(len(project_scope) > 0 && language_scope_string(&definition.scope) == project_scope)
}

@(private)
language_catalog_source_precedence :: proc(source: Language_Contribution_Source) -> u8 {
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
language_catalog_basename :: proc(path: string) -> string {
	start := 0
	for byte, index in transmute([]u8)path {
		if byte == '/' || byte == '\\' do start = index + 1
	}
	return path[start:]
}

@(private)
language_catalog_has_suffix :: proc(value, suffix: string) -> bool {
	return len(value) >= len(suffix) && value[len(value) - len(suffix):] == suffix
}

@(private)
language_catalog_name_copy :: proc(value: string) -> Language_Name {
	result: Language_Name
	result.length = u16(copy(result.bytes[:], transmute([]u8)value))
	return result
}

@(private)
language_catalog_display_name_copy :: proc(value: string) -> Language_Display_Name {
	result: Language_Display_Name
	result.length = u16(copy(result.bytes[:], transmute([]u8)value))
	return result
}

@(private)
language_catalog_scope_copy :: proc(value: string) -> Language_Scope_Text {
	result: Language_Scope_Text
	result.length = u16(copy(result.bytes[:], transmute([]u8)value))
	return result
}

@(private)
language_catalog_association_copy :: proc(value: string) -> Association_Text {
	result: Association_Text
	result.length = u16(copy(result.bytes[:], transmute([]u8)value))
	return result
}

@(private)
language_name_string :: proc(value: ^Language_Name) -> string {
	if value == nil do return ""
	return string(value.bytes[:value.length])
}

@(private)
language_scope_string :: proc(value: ^Language_Scope_Text) -> string {
	if value == nil do return ""
	return string(value.bytes[:value.length])
}

@(private)
language_association_string :: proc(value: ^Association_Text) -> string {
	if value == nil do return ""
	return string(value.bytes[:value.length])
}

@(private)
language_catalog_failure :: proc(
	code: Language_Catalog_Failure_Code,
	field := Language_Catalog_Field.None,
	source := Language_Contribution_Source.Invalid,
	source_generation := Language_Source_Generation(0),
) -> Language_Catalog_Failure {
	return Language_Catalog_Failure {
		code = code,
		field = field,
		source = source,
		source_generation = source_generation,
	}
}
