// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "core:mem"
import "core:strings"
import "core:testing"

/* Verifies configured generations copy values and replace factory state atomically. */
@(test)
editing_configuration_copies_complete_generations :: proc(t: ^testing.T) {
	configuration: Editing_Configuration
	initialized, failure := editing_configuration_init(&configuration, 1, 1)
	testing.expectf(t, initialized, "factory configuration failed with %v", failure.code)
	if !initialized do return
	defer editing_configuration_close(&configuration)
	factory, _ := editing_configuration_inspect(&configuration)
	testing.expect(t, factory.factory_fallback)
	template_copy, copy_error := strings.clone("#+begin_note\n\n#+end_note\n", context.allocator)
	testing.expect(t, copy_error == nil)
	if copy_error != nil do return
	defer delete(template_copy)
	template_text := transmute([]u8)template_copy
	values := []string{"READY", "DONE"}
	templates := []Configured_Template{{key = "note", template_context = .Block, source = string(template_text)}}
	sources := []Configured_Completion_Source{{name = "team-states", kind = .Task_State, candidates = values}}
	candidate := editing_test_configuration_candidate(2, 2, templates, sources)
	descriptor: Editing_Configuration_Descriptor
	published: bool
	descriptor, published, failure = editing_configuration_publish(&configuration, candidate)
	testing.expectf(t, published, "configured generation failed with %v", failure.code)
	testing.expect_value(t, descriptor.template_count, u16(1))
	testing.expect_value(t, descriptor.completion_sources, u16(1))
	template_text[0] = '!'
	confirmed_template, found := editing_configuration_template(&configuration, 0)
	testing.expect(t, found)
	testing.expect_value(t, confirmed_template.source, "#+begin_note\n\n#+end_note\n")
}

/* Verifies stale, conflicting, and over-limit candidates retain the confirmed generation. */
@(test)
editing_configuration_rejects_without_partial_publication :: proc(t: ^testing.T) {
	configuration: Editing_Configuration
	initialized, _ := editing_configuration_init(&configuration, 7, 7)
	testing.expect(t, initialized)
	if !initialized do return
	defer editing_configuration_close(&configuration)
	templates := []Configured_Template{
		{key = "same", template_context = .Block, source = "#+begin_a\n#+end_a\n"},
		{key = "same", template_context = .Drawer, source = ":A:\n:END:\n"},
	}
	candidate := editing_test_configuration_candidate(8, 8, templates, nil)
	_, published, failure := editing_configuration_publish(&configuration, candidate)
	testing.expect(t, !published)
	testing.expect_value(t, failure.code, Failure_Code.Malformed)
	confirmed, _ := editing_configuration_inspect(&configuration)
	testing.expect_value(t, confirmed.generation, Configuration_Generation(7))
	limited := DEFAULT_LIMITS
	limited.templates = 1
	unique := []Configured_Template{
		{key = "one", template_context = .Document, source = "* One\n"},
		{key = "two", template_context = .Document, source = "* Two\n"},
	}
	candidate = editing_test_configuration_candidate(9, 9, unique, nil)
	_, published, failure = editing_configuration_publish(&configuration, candidate, limited)
	testing.expect(t, !published)
	testing.expect_value(t, failure.code, Failure_Code.Limited)
	confirmed, _ = editing_configuration_inspect(&configuration)
	testing.expect_value(t, confirmed.generation, Configuration_Generation(7))
}

/* Verifies every retained configuration allocation can fail without leaking or replacing factory state. */
@(test)
editing_configuration_allocation_faults_preserve_factory :: proc(t: ^testing.T) {
	for fail_after in 0 ..< 6 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Visibility_Test_Failing_Allocator{
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after + 1),
		}
		configuration: Editing_Configuration
		initialized, _ := editing_configuration_init(
			&configuration,
			1,
			1,
			visibility_test_failing_allocator(&failing),
		)
		if !initialized {
			testing.expect_value(t, tracking.current_memory_allocated, i64(0))
			mem.tracking_allocator_destroy(&tracking)
			continue
		}
		templates := []Configured_Template{{key = "note", template_context = .Block, source = "#+begin_note\n#+end_note\n"}}
		values := []string{"READY", "DONE"}
		sources := []Configured_Completion_Source{{name = "states", kind = .Task_State, candidates = values}}
		candidate := editing_test_configuration_candidate(2, 2, templates, sources)
		_, published, failure := editing_configuration_publish(&configuration, candidate)
		if !published do testing.expect_value(t, failure.code, Failure_Code.Allocation_Failed)
		descriptor, _ := editing_configuration_inspect(&configuration)
		if !published do testing.expect_value(t, descriptor.generation, Configuration_Generation(1))
		editing_configuration_close(&configuration)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

@(private)
editing_test_configuration_candidate :: proc(
	generation: Configuration_Generation,
	provider_generation: Provider_Generation,
	templates: []Configured_Template,
	sources: []Configured_Completion_Source,
) -> Editing_Configuration_Candidate {
	return {
		generation = generation,
		provider_generation = provider_generation,
		startup_visibility = .Overview,
		presentation = editing_factory_presentation(),
		templates = templates,
		completion_sources = sources,
		latex_preview = .Factory_Latex,
		image_preview = .Source,
	}
}
