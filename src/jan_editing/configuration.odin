// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "base:runtime"
import "core:unicode/utf8"

/* Startup_Visibility is the complete configurable initial projection policy. */
Startup_Visibility :: enum u8 {
	Invalid,
	Overview,
	Contents,
	Show_All,
}

/* Template_Context identifies syntax positions admitted for one expansion. */
Template_Context :: enum u8 {
	Invalid,
	Document,
	Heading,
	List,
	Drawer,
	Block,
	Table,
	Paragraph,
}

/* Completion_Kind is the closed Stage 2 source-syntax candidate inventory. */
Completion_Kind :: enum u8 {
	Invalid,
	Keyword,
	Task_State,
	Tag,
	Property,
	Link_Form,
	Target,
	Block_Name,
	Language,
	Header_Argument,
	File_Setting,
}

/* Preview_Selection names only already-admitted Stage 2 adapter capabilities. */
Preview_Selection :: enum u8 {
	Invalid,
	Source,
	Factory_Latex,
	Factory_Image,
}

/* Presentation_Configuration is copied display and hard-indentation policy. */
Presentation_Configuration :: struct {
	compose_markup:        bool,
	prettify_entities:     bool,
	visual_indent_width:   u8,
	number_headings:       bool,
	hard_indent_width:     u8,
}

/* Configured_Template is one copied source-only structure definition. */
Configured_Template :: struct {
	key:              string,
	template_context: Template_Context,
	source:           string,
}

/* Configured_Completion_Source is one named, typed, copied candidate provider. */
Configured_Completion_Source :: struct {
	name:       string,
	kind:       Completion_Kind,
	candidates: []string,
}

/* Editing_Configuration_Candidate is validated wholly before publication. */
Editing_Configuration_Candidate :: struct {
	generation:         Configuration_Generation,
	provider_generation: Provider_Generation,
	startup_visibility: Startup_Visibility,
	presentation:       Presentation_Configuration,
	templates:          []Configured_Template,
	completion_sources: []Configured_Completion_Source,
	latex_preview:      Preview_Selection,
	image_preview:      Preview_Selection,
}

/* Editing_Configuration_Descriptor exposes one immutable confirmed generation. */
Editing_Configuration_Descriptor :: struct {
	generation:          Configuration_Generation,
	provider_generation: Provider_Generation,
	startup_visibility:  Startup_Visibility,
	presentation:        Presentation_Configuration,
	template_count:      u16,
	completion_sources:  u16,
	retained_bytes:      u64,
	latex_preview:       Preview_Selection,
	image_preview:       Preview_Selection,
	factory_fallback:    bool,
}

/* Editing_Configuration owns one copied generation until replacement or close. */
Editing_Configuration :: struct {
	state: rawptr,
}

@(private)
Owned_Configured_Template :: struct {
	key:              []u8,
	template_context: Template_Context,
	source:           []u8,
}

@(private)
Owned_Configured_Completion_Source :: struct {
	name:       []u8,
	kind:       Completion_Kind,
	candidates: [][]u8,
}

@(private)
Editing_Configuration_State :: struct {
	descriptor: Editing_Configuration_Descriptor,
	templates:  []Owned_Configured_Template,
	sources:    []Owned_Configured_Completion_Source,
	allocator:  runtime.Allocator,
}

/* editing_configuration_init installs the immutable factory fallback generation. */
editing_configuration_init :: proc(
	configuration: ^Editing_Configuration,
	generation: Configuration_Generation,
	provider_generation: Provider_Generation,
	allocator := context.allocator,
) -> (bool, Failure) {
	if configuration == nil || configuration.state != nil ||
	   generation == Configuration_Generation(0) ||
	   provider_generation == Provider_Generation(0) || allocator.procedure == nil {
		return false, editing_failure(.Configure, .Invalid_Scope, {})
	}
	state, allocation_error := new(Editing_Configuration_State, allocator)
	if allocation_error != nil {
		return false, editing_failure(.Configure, .Allocation_Failed, {})
	}
	state^ = Editing_Configuration_State {
		descriptor = {
			generation = generation,
			provider_generation = provider_generation,
			startup_visibility = .Contents,
			presentation = editing_factory_presentation(),
			latex_preview = .Factory_Latex,
			image_preview = .Source,
			factory_fallback = true,
		},
		allocator = allocator,
	}
	configuration.state = state
	return true, {}
}

/* editing_configuration_publish validates and swaps one complete copied generation. */
editing_configuration_publish :: proc(
	configuration: ^Editing_Configuration,
	candidate: Editing_Configuration_Candidate,
	limits := DEFAULT_LIMITS,
) -> (descriptor: Editing_Configuration_Descriptor, ok: bool, failure: Failure) {
	current := editing_configuration_state(configuration)
	if current == nil || !limits_are_valid(limits) {
		return {}, false, editing_failure(.Configure, .Invalid_Scope, {})
	}
	if candidate.generation <= current.descriptor.generation ||
	   candidate.provider_generation == Provider_Generation(0) {
		return current.descriptor, false, editing_failure(.Configure, .Stale, {})
	}
	valid, retained_bytes, invalid_code := editing_configuration_candidate_validate(candidate, limits)
	if !valid {
		failure = editing_failure(.Configure, invalid_code, {})
		failure.limit = limits.configuration_bytes
		failure.actual = retained_bytes
		return current.descriptor, false, failure
	}
	next, copied := editing_configuration_copy(candidate, retained_bytes, current.allocator)
	if !copied {
		return current.descriptor, false, editing_failure(.Configure, .Allocation_Failed, {})
	}
	configuration.state = next
	editing_configuration_state_destroy(current)
	return next.descriptor, true, {}
}

/* editing_configuration_inspect copies current generation metadata. */
editing_configuration_inspect :: proc(configuration: ^Editing_Configuration) -> (Editing_Configuration_Descriptor, bool) {
	state := editing_configuration_state(configuration)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* editing_configuration_template borrows one confirmed template until replacement. */
editing_configuration_template :: proc(
	configuration: ^Editing_Configuration,
	index: int,
) -> (Configured_Template, bool) {
	state := editing_configuration_state(configuration)
	if state == nil || index < 0 || index >= len(state.templates) do return {}, false
	template := &state.templates[index]
	return {key = string(template.key), template_context = template.template_context, source = string(template.source)}, true
}

/* editing_configuration_completion_source borrows one confirmed source until replacement. */
editing_configuration_completion_source :: proc(
	configuration: ^Editing_Configuration,
	index: int,
) -> (Configured_Completion_Source, bool) {
	state := editing_configuration_state(configuration)
	if state == nil || index < 0 || index >= len(state.sources) do return {}, false
	owned := &state.sources[index]
	values := transmute([]string)owned.candidates
	return {name = string(owned.name), kind = owned.kind, candidates = values}, true
}

/* editing_configuration_close releases every copied configured value exactly. */
editing_configuration_close :: proc(configuration: ^Editing_Configuration) {
	if configuration == nil do return
	state := editing_configuration_state(configuration)
	if state != nil do editing_configuration_state_destroy(state)
	configuration.state = nil
}

/* editing_factory_presentation returns the maintained Stage 2 display policy. */
editing_factory_presentation :: proc() -> Presentation_Configuration {
	return {
		compose_markup = true,
		prettify_entities = true,
		visual_indent_width = 2,
		number_headings = false,
		hard_indent_width = 2,
	}
}

@(private)
editing_configuration_candidate_validate :: proc(
	candidate: Editing_Configuration_Candidate,
	limits: Limits,
) -> (bool, u64, Failure_Code) {
	if candidate.generation == Configuration_Generation(0) ||
	   candidate.provider_generation == Provider_Generation(0) ||
	   candidate.startup_visibility <= .Invalid || candidate.startup_visibility > .Show_All ||
	   !editing_presentation_is_valid(candidate.presentation) ||
	   !editing_preview_selection_is_valid(candidate.latex_preview, .Latex) ||
	   !editing_preview_selection_is_valid(candidate.image_preview, .Image) {
		return false, 0, .Malformed
	}
	if len(candidate.templates) > int(limits.templates) ||
	   len(candidate.completion_sources) > int(limits.completion_sources) {
		return false, u64(max(len(candidate.templates), len(candidate.completion_sources))), .Limited
	}
	retained: u64
	for template, index in candidate.templates {
		if template.template_context <= .Invalid || template.template_context > .Paragraph ||
		   !editing_configuration_text_is_valid(template.key, 96) ||
		   !editing_configuration_text_is_valid(template.source, 64 * 1_024) {
			return false, retained, .Malformed
		}
		for prior in candidate.templates[:index] {
			if prior.key == template.key do return false, retained, .Malformed
		}
		retained += u64(len(template.key) + len(template.source))
	}
	for source, index in candidate.completion_sources {
		if source.kind <= .Invalid || source.kind > .File_Setting ||
		   !editing_configuration_text_is_valid(source.name, 96) || len(source.candidates) == 0 ||
		   len(source.candidates) > int(limits.completion_candidates) {
			return false, retained, .Malformed
		}
		for prior in candidate.completion_sources[:index] {
			if prior.name == source.name do return false, retained, .Malformed
		}
		retained += u64(len(source.name))
		for value, value_index in source.candidates {
			if !editing_configuration_text_is_valid(value, 16 * 1_024) {
				return false, retained, .Malformed
			}
			for prior in source.candidates[:value_index] {
				if prior == value do return false, retained, .Malformed
			}
			retained += u64(len(value))
		}
	}
	if retained > limits.configuration_bytes do return false, retained, .Limited
	return true, retained, .None
}

@(private)
editing_configuration_copy :: proc(
	candidate: Editing_Configuration_Candidate,
	retained_bytes: u64,
	allocator: runtime.Allocator,
) -> (^Editing_Configuration_State, bool) {
	state, allocation_error := new(Editing_Configuration_State, allocator)
	if allocation_error != nil do return nil, false
	state^ = Editing_Configuration_State{allocator = allocator}
	state.descriptor = {
		generation = candidate.generation,
		provider_generation = candidate.provider_generation,
		startup_visibility = candidate.startup_visibility,
		presentation = candidate.presentation,
		template_count = u16(len(candidate.templates)),
		completion_sources = u16(len(candidate.completion_sources)),
		retained_bytes = retained_bytes,
		latex_preview = candidate.latex_preview,
		image_preview = candidate.image_preview,
		factory_fallback = len(candidate.templates) == 0 && len(candidate.completion_sources) == 0,
	}
	if len(candidate.templates) > 0 {
		state.templates, allocation_error = make([]Owned_Configured_Template, len(candidate.templates), allocator)
		if allocation_error != nil {
			editing_configuration_state_destroy(state)
			return nil, false
		}
		for template, index in candidate.templates {
			state.templates[index].template_context = template.template_context
			state.templates[index].key, allocation_error = editing_configuration_text_copy(template.key, allocator)
			if allocation_error == nil {
				state.templates[index].source, allocation_error = editing_configuration_text_copy(template.source, allocator)
			}
			if allocation_error != nil {
				editing_configuration_state_destroy(state)
				return nil, false
			}
		}
	}
	if len(candidate.completion_sources) > 0 {
		state.sources, allocation_error = make([]Owned_Configured_Completion_Source, len(candidate.completion_sources), allocator)
		if allocation_error != nil {
			editing_configuration_state_destroy(state)
			return nil, false
		}
		for source, index in candidate.completion_sources {
			state.sources[index].kind = source.kind
			state.sources[index].name, allocation_error = editing_configuration_text_copy(source.name, allocator)
			if allocation_error == nil {
				state.sources[index].candidates, allocation_error = make([][]u8, len(source.candidates), allocator)
			}
			if allocation_error != nil {
				editing_configuration_state_destroy(state)
				return nil, false
			}
			for value, value_index in source.candidates {
				state.sources[index].candidates[value_index], allocation_error = editing_configuration_text_copy(value, allocator)
				if allocation_error != nil {
					editing_configuration_state_destroy(state)
					return nil, false
				}
			}
		}
	}
	return state, true
}

@(private)
editing_configuration_text_copy :: proc(text: string, allocator: runtime.Allocator) -> ([]u8, runtime.Allocator_Error) {
	result, allocation_error := make([]u8, len(text), allocator)
	if allocation_error != nil do return nil, allocation_error
	copy(result, transmute([]u8)text)
	return result, nil
}

@(private)
editing_configuration_state_destroy :: proc(state: ^Editing_Configuration_State) {
	if state == nil do return
	for &template in state.templates {
		if template.key != nil do delete(template.key, state.allocator)
		if template.source != nil do delete(template.source, state.allocator)
	}
	if state.templates != nil do delete(state.templates, state.allocator)
	for &source in state.sources {
		if source.name != nil do delete(source.name, state.allocator)
		for value in source.candidates {
			if value != nil do delete(value, state.allocator)
		}
		if source.candidates != nil do delete(source.candidates, state.allocator)
	}
	if state.sources != nil do delete(state.sources, state.allocator)
	allocator := state.allocator
	free(state, allocator)
}

@(private)
editing_configuration_state :: proc(configuration: ^Editing_Configuration) -> ^Editing_Configuration_State {
	if configuration == nil || configuration.state == nil do return nil
	return cast(^Editing_Configuration_State)configuration.state
}

@(private)
editing_presentation_is_valid :: proc(presentation: Presentation_Configuration) -> bool {
	return presentation.visual_indent_width <= 16 && presentation.hard_indent_width > 0 &&
	       presentation.hard_indent_width <= 16
}

@(private)
editing_preview_selection_is_valid :: proc(selection: Preview_Selection, kind: Preview_Kind) -> bool {
	if selection == .Source do return true
	if kind == .Latex do return selection == .Factory_Latex
	if kind == .Image do return selection == .Factory_Image
	return false
}

@(private)
editing_configuration_text_is_valid :: proc(text: string, maximum: int) -> bool {
	if len(text) == 0 || len(text) > maximum || !utf8.valid_string(text) do return false
	for value in transmute([]u8)text {
		if value == 0 do return false
	}
	return true
}
