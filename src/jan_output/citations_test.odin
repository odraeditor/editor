// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_output

import "core:strings"
import "core:testing"

/* Verifies selected processors resolve exact sources and produce stable cache keys. */
@(test)
citation_resolution_is_exact_complete_and_cacheable :: proc(t: ^testing.T) {
	request, processors, sources, references, entries := citation_test_resolution_request()
	request.sources = sources[:]
	request.references = references[:]
	request.entries = entries[:]
	resolutions: [2]Citation_Resolution
	diagnostics: [2]Citation_Diagnostic
	result, ok, _ := resolve_citations(request, processors[:], resolutions[:], diagnostics[:])
	testing.expect(t, ok)
	testing.expect(t, result.complete)
	testing.expect_value(t, result.processor_kind, Citation_Processor_Kind.Csl)
	testing.expect_value(t, result.reference_count, u16(2))
	testing.expect_value(t, resolutions[0].entry_index, u16(0))
	testing.expect_value(t, resolutions[1].entry_index, u16(1))
	testing.expect(t, citation_cache_key_matches(result.cache_key, result.cache_key))
	stale := result.cache_key
	stale.processor_generation += 1
	testing.expect(t, !citation_cache_key_matches(result.cache_key, stale))

	completions: [2]Citation_Completion
	count, completion_ok := complete_citation_keys("b", sources[:], entries[:], completions[:])
	testing.expect(t, completion_ok)
	testing.expect_value(t, count, u16(1))
	testing.expect_value(t, completions[0].key, "beta-2020")
	testing.expect_value(t, completions[0].source_revision, u64(13))
}

/* Verifies missing, duplicate, invalid, stale, and unavailable inputs stay isolated. */
@(test)
citation_resolution_rejects_invalid_source_sets :: proc(t: ^testing.T) {
	request, processors, sources, references, entries := citation_test_resolution_request()
	request.sources, request.references, request.entries = sources[:], references[:], entries[:]
	resolutions: [2]Citation_Resolution
	diagnostics: [2]Citation_Diagnostic

	references[1].key = "missing"
	request.references = references[:]
	_, ok, failure := resolve_citations(request, processors[:], resolutions[:], diagnostics[:])
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Missing)
	testing.expect_value(t, diagnostics[0].key, "missing")

	references[1].key = "beta-2020"
	entries[1].key = entries[0].key
	_, ok, failure = resolve_citations(request, processors[:], resolutions[:], diagnostics[:])
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Conflict)

	entries[1].key = "beta-2020"
	entries[1].valid = false
	_, ok, failure = resolve_citations(request, processors[:], resolutions[:], diagnostics[:])
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Malformed)

	entries[1].valid = true
	processors[0].state = .Unavailable
	_, ok, failure = resolve_citations(request, processors[:], resolutions[:], diagnostics[:])
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Unavailable)

	processors[0].state = .Available
	sources[1].resource_id = sources[0].resource_id
	request.sources = sources[:]
	_, ok, failure = resolve_citations(request, processors[:], resolutions[:], diagnostics[:])
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Conflict)
}

/* Verifies CSL variants, affixes, locale context, links, and HTML escaping. */
@(test)
csl_citations_render_by_backend_without_changing_source :: proc(t: ^testing.T) {
	_, _, _, references, entries := citation_test_resolution_request()
	resolutions := [2]Citation_Resolution {{reference_index = 0, entry_index = 0}, {reference_index = 1, entry_index = 1}}
	references[0].locator = "p. 3"
	references[0].prefix = "see "
	references[1].variant = .Narrative
	request := Citation_Render_Request {operation_id = 73, processor_kind = .Csl, backend = .Plain_Text,
		style_identity = "author-year", locale = "en-US", references = references[:], entries = entries[:],
		resolutions = resolutions[:], limits = DEFAULT_LIMITS}
	destination: [4_096]u8
	result, ok, _ := render_citations(request, destination[:])
	testing.expect(t, ok)
	testing.expect_value(t, result.citation_count, u16(2))
	text := string(destination[:int(result.byte_count)])
	testing.expect(t, strings.contains(text, "see (Zed & Co., 2024, p. 3)"))
	testing.expect(t, strings.contains(text, "Ada <Research> (2020)"))

	request.backend = .Html
	request.include_links = true
	result, ok, _ = render_citations(request, destination[:])
	testing.expect(t, ok)
	html := string(destination[:int(result.byte_count)])
	testing.expect(t, strings.contains(html, "Zed &amp; Co."))
	testing.expect(t, strings.contains(html, "Ada &lt;Research&gt;"))
	testing.expect(t, strings.contains(html, "href=\"https://example.test/alpha?a=1&amp;b=2\""))

	tiny: [8]u8
	_, limited_ok, failure := render_citations(request, tiny[:])
	testing.expect(t, !limited_ok)
	testing.expect_value(t, failure.code, Failure_Code.Limited)

	resolutions[1].entry_index = 7
	request.resolutions = resolutions[:]
	_, stale_ok, stale_failure := render_citations(request, destination[:])
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale)
}

/* Verifies LaTeX workflows require LaTeX context and escape keys and locators. */
@(test)
latex_citations_render_with_exact_adapter_context :: proc(t: ^testing.T) {
	_, _, _, references, entries := citation_test_resolution_request()
	references[0].key = "alpha_key"
	entries[0].key = "alpha_key"
	references[0].locator = "pp. 2_3"
	resolutions := [1]Citation_Resolution {{reference_index = 0, entry_index = 0}}
	request := Citation_Render_Request {operation_id = 75, processor_kind = .Latex, backend = .Latex,
		style_identity = "biblatex", style_resource_id = 19, style_revision = 23, locale = "en",
		references = references[:1], entries = entries[:], resolutions = resolutions[:], limits = DEFAULT_LIMITS}
	destination: [1_024]u8
	result, ok, _ := render_citations(request, destination[:])
	testing.expect(t, ok)
	testing.expect_value(t, string(destination[:int(result.byte_count)]), "\\cite[pp. 2\\_3]{alpha\\_key}")
	request.backend = .Html
	_, invalid_ok, failure := render_citations(request, destination[:])
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Request)
}

/* Verifies bibliography filters, stable sorting, placement, and backend rendering. */
@(test)
bibliography_plans_filter_sort_and_render_deterministically :: proc(t: ^testing.T) {
	_, _, _, _, entries := citation_test_resolution_request()
	request := Bibliography_Request {operation_id = 77, placement = .Document_End, sort = .Author,
		backend = .Markdown, style_identity = "author-year", locale = "en-US", limits = DEFAULT_LIMITS}
	selected: [2]u16
	plan, ok, _ := prepare_bibliography(request, entries[:], selected[:])
	testing.expect(t, ok)
	testing.expect_value(t, plan.selected_count, u16(2))
	testing.expect_value(t, entries[selected[0]].key, "beta-2020")
	destination: [4_096]u8
	result, render_ok, _ := render_bibliography(request, entries[:], selected[:], destination[:])
	testing.expect(t, render_ok)
	text := string(destination[:int(result.byte_count)])
	testing.expectf(t, strings.has_prefix(text, "- Ada <Research>. *Bounded Systems*. 2020."), "output=%q", text)

	request.minimum_year = 2021
	plan, ok, _ = prepare_bibliography(request, entries[:], selected[:])
	testing.expect(t, ok)
	testing.expect_value(t, plan.selected_count, u16(1))
	testing.expect_value(t, entries[selected[0]].key, "alpha-2024")
}

/* Verifies processor inspection exposes independent CSL and LaTeX availability. */
@(test)
citation_processor_availability_is_explicit :: proc(t: ^testing.T) {
	processors := citation_test_processors(37)
	processors[1].trusted = false
	records := citation_processor_inspection(processors[:], 37)
	testing.expect_value(t, records[0].state, Availability_State.Available)
	testing.expect_value(t, records[1].state, Availability_State.Unavailable)
}

@(private = "file")
citation_test_resolution_request :: proc() -> (
	Citation_Resolution_Request,
	[2]Citation_Processor_Descriptor,
	[2]Bibliography_Source,
	[2]Citation_Reference,
	[2]Bibliography_Entry,
) {
	scope := output_test_scope()
	processors := citation_test_processors(scope.provider_generation)
	sources := [2]Bibliography_Source {
		{resource_id = 7, resource_revision = 11, format = .Csl_Json},
		{resource_id = 9, resource_revision = 13, format = .Bibtex},
	}
	sources[0].digest[0] = 1
	sources[1].digest[0] = 2
	references := [2]Citation_Reference {
		{key = "alpha-2024", variant = .Parenthetical, source_start = 10, source_end = 20},
		{key = "beta-2020", variant = .Parenthetical, source_start = 30, source_end = 40},
	}
	entries := [2]Bibliography_Entry {
		{key = "alpha-2024", author = "Zed & Co.", title = "Exact Sources", year = 2024,
		 url = "https://example.test/alpha?a=1&b=2", source_index = 0, valid = true},
		{key = "beta-2020", author = "Ada <Research>", title = "Bounded Systems", year = 2020,
		 source_index = 1, valid = true},
	}
	request := Citation_Resolution_Request {operation_id = 71, scope = scope, processor_identity = "citeproc",
		processor_generation = scope.provider_generation, backend = .Plain_Text, style_identity = "author-year",
		limits = DEFAULT_LIMITS, explicit = true}
	request.source_digest[0] = 3
	request.reference_digest[0] = 5
	return request, processors, sources, references, entries
}

@(private = "file")
citation_test_processors :: proc(generation: Provider_Generation) -> [2]Citation_Processor_Descriptor {
	return {
		{identity = "citeproc", version = "test-1", generation = generation, kind = .Csl, state = .Available, trusted = true},
		{identity = "latex-citations", version = "test-1", generation = generation, kind = .Latex, state = .Available, trusted = true},
	}
}
