// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_output

import "core:strings"

/* MAX_CITATION_REFERENCES bounds one citation resolution and rendering pass. */
MAX_CITATION_REFERENCES :: 4_096
/* MAX_CITATION_ENTRIES bounds one admitted bibliography source set. */
MAX_CITATION_ENTRIES :: 4_096

/* Citation_Processor_Kind identifies one supported citation workflow. */
Citation_Processor_Kind :: enum u8 {
	Invalid,
	Csl,
	Latex,
}

/* Bibliography_Format identifies one admitted source representation. */
Bibliography_Format :: enum u8 {
	Invalid,
	Csl_Json,
	Bibtex,
}

/* Citation_Variant controls author and year placement. */
Citation_Variant :: enum u8 {
	Invalid,
	Parenthetical,
	Narrative,
	Suppress_Author,
	Author_Only,
}

/* Citation_Backend identifies one citation rendering context. */
Citation_Backend :: enum u8 {
	Invalid,
	Plain_Text,
	Html,
	Markdown,
	Latex,
}

/* Bibliography_Placement identifies the requested bibliography position. */
Bibliography_Placement :: enum u8 {
	Invalid,
	Document_End,
	At_Directive,
	Section,
}

/* Bibliography_Sort identifies deterministic entry order. */
Bibliography_Sort :: enum u8 {
	Invalid,
	Citation_Order,
	Key,
	Author,
	Year,
	Title,
}

/* Citation_Processor_Descriptor identifies one exact optional processor. */
Citation_Processor_Descriptor :: struct {
	identity:   string,
	version:    string,
	generation: Provider_Generation,
	kind:       Citation_Processor_Kind,
	state:      Tool_State,
	trusted:    bool,
}

/* Bibliography_Source identifies one exact admitted bibliography resource. */
Bibliography_Source :: struct {
	resource_id:       u64,
	resource_revision: u64,
	format:            Bibliography_Format,
	digest:            [32]u8,
}

/* Citation_Reference is one source-preserving citation request. */
Citation_Reference :: struct {
	key:          string,
	prefix:       string,
	suffix:       string,
	locator:      string,
	variant:      Citation_Variant,
	source_start: u64,
	source_end:   u64,
}

/* Bibliography_Entry is one normalized exact-source bibliography value. */
Bibliography_Entry :: struct {
	key:          string,
	author:       string,
	title:        string,
	container:    string,
	year:         i32,
	url:          string,
	source_index: u16,
	valid:        bool,
}

/* Citation_Resolution maps one reference to one normalized entry. */
Citation_Resolution :: struct {
	reference_index: u16,
	entry_index:     u16,
}

/* Citation_Diagnostic attributes one resolution failure without changing source. */
Citation_Diagnostic :: struct {
	code:          Failure_Code,
	key:           string,
	reference_index: u16,
	source_start:  u64,
	source_end:    u64,
}

/* Citation_Cache_Key binds retained output to all semantic inputs. */
Citation_Cache_Key :: struct {
	processor_generation: Provider_Generation,
	style_identity:       string,
	style_resource_id:    u64,
	style_revision:       u64,
	backend:              Citation_Backend,
	source_digest:        [32]u8,
	reference_digest:     [32]u8,
}

/* Citation_Resolution_Request selects one processor and exact source set. */
Citation_Resolution_Request :: struct {
	operation_id:       Operation_ID,
	scope:              Scope,
	processor_identity: string,
	processor_generation: Provider_Generation,
	backend:            Citation_Backend,
	style_identity:     string,
	style_resource_id:  u64,
	style_revision:     u64,
	sources:            []Bibliography_Source,
	references:         []Citation_Reference,
	entries:            []Bibliography_Entry,
	source_digest:      [32]u8,
	reference_digest:   [32]u8,
	limits:             Limits,
	explicit:           bool,
}

/* Citation_Resolution_Result reports one complete exact-version resolution. */
Citation_Resolution_Result :: struct {
	operation_id:     Operation_ID,
	processor_kind:  Citation_Processor_Kind,
	source_count:     u16,
	reference_count:  u16,
	entry_count:      u16,
	cache_key:        Citation_Cache_Key,
	complete:         bool,
}

/* Citation_Render_Request controls style, affixes, locale, links, and backend context. */
Citation_Render_Request :: struct {
	operation_id:      Operation_ID,
	processor_kind:   Citation_Processor_Kind,
	backend:           Citation_Backend,
	style_identity:    string,
	style_resource_id: u64,
	style_revision:    u64,
	locale:            string,
	global_prefix:     string,
	global_suffix:     string,
	include_links:     bool,
	references:        []Citation_Reference,
	entries:           []Bibliography_Entry,
	resolutions:       []Citation_Resolution,
	limits:            Limits,
}

/* Citation_Render_Result reports one complete bounded citation candidate. */
Citation_Render_Result :: struct {
	backend:        Citation_Backend,
	citation_count: u16,
	byte_count:     u64,
	complete:       bool,
}

/* Bibliography_Request controls placement, filtering, sorting, and rendering. */
Bibliography_Request :: struct {
	operation_id:       Operation_ID,
	placement:          Bibliography_Placement,
	sort:               Bibliography_Sort,
	backend:            Citation_Backend,
	style_identity:     string,
	locale:             string,
	key_prefix:         string,
	author_filter:      string,
	minimum_year:       i32,
	maximum_year:       i32,
	include_links:      bool,
	limits:             Limits,
}

/* Bibliography_Plan reports deterministic selected entry order. */
Bibliography_Plan :: struct {
	operation_id:  Operation_ID,
	placement:     Bibliography_Placement,
	selected_count: u16,
	complete:      bool,
}

/* Citation_Completion is one bounded completion handoff. */
Citation_Completion :: struct {
	key:             string,
	title:           string,
	source_resource: u64,
	source_revision: u64,
}

/* Citation_Processor_Inspection exposes factory adapter availability. */
Citation_Processor_Inspection :: struct {
	kind:       Citation_Processor_Kind,
	identity:   string,
	state:      Availability_State,
	generation: Provider_Generation,
}

/* resolve_citations validates exact sources and resolves every key without source mutation. */
resolve_citations :: proc(
	request: Citation_Resolution_Request,
	processors: []Citation_Processor_Descriptor,
	resolutions: []Citation_Resolution,
	diagnostics: []Citation_Diagnostic,
) -> (Citation_Resolution_Result, bool, Failure) {
	if request.operation_id == Operation_ID(0) || !scope_is_valid(request.scope) || !request.explicit ||
	   !limits_are_valid(request.limits) || !output_text_is_valid(request.processor_identity, MAX_IDENTITY_BYTES) ||
	   request.processor_generation == Provider_Generation(0) || len(request.sources) == 0 ||
	   request.backend == .Invalid || !output_text_is_valid(request.style_identity, MAX_IDENTITY_BYTES) ||
	   !((request.style_resource_id == 0 && request.style_revision == 0) ||
	     (request.style_resource_id != 0 && request.style_revision != 0)) ||
	   len(request.sources) > int(request.limits.included_resources) || len(request.references) == 0 ||
	   len(request.references) > MAX_CITATION_REFERENCES || len(request.entries) == 0 ||
	   len(request.entries) > MAX_CITATION_ENTRIES || len(resolutions) < len(request.references) ||
	   !citation_digest_is_present(request.source_digest) || !citation_digest_is_present(request.reference_digest) {
		return {}, false, citation_failure(request.operation_id, .Invalid_Request, .Citation)
	}
	processor_index := -1
	for processor, index in processors {
		if !citation_processor_is_valid(processor) do return {}, false, citation_failure(request.operation_id, .Malformed, .Citation)
		if processor.identity == request.processor_identity {
			if processor_index >= 0 do return {}, false, citation_failure(request.operation_id, .Conflict, .Citation)
			processor_index = index
		}
	}
	if processor_index < 0 || processors[processor_index].generation != request.processor_generation ||
	   processors[processor_index].state != .Available || !processors[processor_index].trusted {
		return {}, false, citation_failure(request.operation_id, .Unavailable, .Citation)
	}
	for source, index in request.sources {
		if !bibliography_source_is_valid(source) do return {}, false, citation_failure(request.operation_id, .Malformed, .Bibliography)
		for prior in request.sources[:index] do if prior.resource_id == source.resource_id {
			return {}, false, citation_failure(request.operation_id, .Conflict, .Bibliography)
		}
	}
	for entry, index in request.entries {
		if !bibliography_entry_is_valid(entry, len(request.sources)) {
			return {}, false, citation_failure(request.operation_id, .Malformed, .Bibliography)
		}
		for prior in request.entries[:index] do if prior.key == entry.key {
			return {}, false, citation_failure(request.operation_id, .Conflict, .Bibliography)
		}
	}
	for reference, reference_index in request.references {
		if !citation_reference_is_valid(reference, request.scope) {
			return {}, false, citation_failure(request.operation_id, .Malformed, .Citation)
		}
		entry_index := -1
		for entry, index in request.entries do if entry.key == reference.key {
			entry_index = index
			break
		}
		if entry_index < 0 {
			if len(diagnostics) > 0 do diagnostics[0] = {code = .Missing, key = reference.key,
				reference_index = u16(reference_index), source_start = reference.source_start, source_end = reference.source_end}
			return {}, false, citation_failure(request.operation_id, .Missing, .Citation)
		}
		resolutions[reference_index] = {reference_index = u16(reference_index), entry_index = u16(entry_index)}
	}
	cache_key := Citation_Cache_Key {processor_generation = request.processor_generation,
		style_identity = request.style_identity, style_resource_id = request.style_resource_id,
		style_revision = request.style_revision, backend = request.backend,
		source_digest = request.source_digest, reference_digest = request.reference_digest}
	return {operation_id = request.operation_id, processor_kind = processors[processor_index].kind,
		source_count = u16(len(request.sources)), reference_count = u16(len(request.references)),
		entry_count = u16(len(request.entries)), cache_key = cache_key, complete = true}, true, {}
}

/* citation_cache_key_matches requires exact semantic and version equality. */
citation_cache_key_matches :: proc(cached, requested: Citation_Cache_Key) -> bool {
	return cached == requested && cached.processor_generation != Provider_Generation(0) &&
	       output_text_is_valid(cached.style_identity, MAX_IDENTITY_BYTES) &&
	       cached.backend != .Invalid && citation_digest_is_present(cached.source_digest) &&
	       citation_digest_is_present(cached.reference_digest) &&
	       ((cached.style_resource_id == 0 && cached.style_revision == 0) ||
	        (cached.style_resource_id != 0 && cached.style_revision != 0))
}

/* render_citations renders one complete resolved citation sequence into caller-owned storage. */
render_citations :: proc(request: Citation_Render_Request, destination: []u8) -> (Citation_Render_Result, bool, Failure) {
	if !citation_render_request_is_valid(request) || len(destination) == 0 || u64(len(destination)) > request.limits.output_bytes {
		return {}, false, citation_failure(request.operation_id, .Invalid_Request, .Citation)
	}
	writer := Native_Writer {bytes = destination, encoding = .Utf_8}
	for resolution, index in request.resolutions {
		if int(resolution.reference_index) != index || int(resolution.entry_index) >= len(request.entries) {
			return {}, false, citation_failure(request.operation_id, .Stale, .Citation)
		}
		reference := request.references[index]
		entry := request.entries[resolution.entry_index]
		if !citation_reference_render_is_valid(reference) || !bibliography_entry_content_is_valid(entry) {
			return {}, false, citation_failure(request.operation_id, .Malformed, .Citation)
		}
		if index > 0 && !citation_write_text(&writer, request.backend, "; ") do return citation_render_limit_failure(request, writer)
		if !citation_write_text(&writer, request.backend, request.global_prefix) ||
		   !citation_write_text(&writer, request.backend, reference.prefix) ||
		   !render_citation_value(&writer, request, reference, entry) ||
		   !citation_write_text(&writer, request.backend, reference.suffix) ||
		   !citation_write_text(&writer, request.backend, request.global_suffix) {
			return citation_render_limit_failure(request, writer)
		}
	}
	return {backend = request.backend, citation_count = u16(len(request.resolutions)),
		byte_count = u64(writer.count), complete = true}, true, {}
}

/* prepare_bibliography selects and orders valid entries without rendering or publication. */
prepare_bibliography :: proc(request: Bibliography_Request, entries: []Bibliography_Entry, selected: []u16) -> (Bibliography_Plan, bool, Failure) {
	if request.operation_id == Operation_ID(0) || request.placement == .Invalid || request.sort == .Invalid ||
	   request.backend == .Invalid || !output_text_is_valid(request.style_identity, MAX_IDENTITY_BYTES) ||
	   !output_text_is_valid(request.locale, MAX_IDENTITY_BYTES) || !limits_are_valid(request.limits) ||
	   len(entries) == 0 || len(entries) > MAX_CITATION_ENTRIES || len(selected) < len(entries) ||
	   (request.maximum_year != 0 && request.minimum_year > request.maximum_year) {
		return {}, false, citation_failure(request.operation_id, .Invalid_Request, .Bibliography)
	}
	count := 0
	for entry, index in entries {
		if !bibliography_entry_content_is_valid(entry) do return {}, false, citation_failure(request.operation_id, .Malformed, .Bibliography)
		if len(request.key_prefix) > 0 && !strings.has_prefix(entry.key, request.key_prefix) do continue
		if len(request.author_filter) > 0 && !strings.contains(entry.author, request.author_filter) do continue
		if request.minimum_year != 0 && entry.year < request.minimum_year do continue
		if request.maximum_year != 0 && entry.year > request.maximum_year do continue
		selected[count] = u16(index)
		count += 1
	}
	if request.sort != .Citation_Order {
		for index in 1..<count {
			value := selected[index]
			cursor := index
			for cursor > 0 && bibliography_entry_less(entries[value], entries[selected[cursor - 1]], request.sort) {
				selected[cursor] = selected[cursor - 1]
				cursor -= 1
			}
			selected[cursor] = value
		}
	}
	return {operation_id = request.operation_id, placement = request.placement,
		selected_count = u16(count), complete = true}, true, {}
}

/* render_bibliography renders one deterministic selected bibliography. */
render_bibliography :: proc(request: Bibliography_Request, entries: []Bibliography_Entry, selected: []u16, destination: []u8) -> (Citation_Render_Result, bool, Failure) {
	if len(destination) == 0 || u64(len(destination)) > request.limits.output_bytes {
		return {}, false, citation_failure(request.operation_id, .Invalid_Request, .Bibliography)
	}
	plan, ok, failure := prepare_bibliography(request, entries, selected)
	if !ok do return {}, false, failure
	writer := Native_Writer {bytes = destination, encoding = .Utf_8}
	if request.backend == .Html && !writer_string(&writer, "<ol class=\"bibliography\">\n") do return citation_bibliography_limit_failure(request, writer)
	if request.backend == .Latex && !writer_string(&writer, "\\begin{thebibliography}{99}\n") do return citation_bibliography_limit_failure(request, writer)
	for selected_index in selected[:int(plan.selected_count)] {
		entry := entries[selected_index]
		if !render_bibliography_entry(&writer, request, entry) do return citation_bibliography_limit_failure(request, writer)
	}
	if request.backend == .Html && !writer_string(&writer, "</ol>\n") do return citation_bibliography_limit_failure(request, writer)
	if request.backend == .Latex && !writer_string(&writer, "\\end{thebibliography}\n") do return citation_bibliography_limit_failure(request, writer)
	return {backend = request.backend, citation_count = plan.selected_count,
		byte_count = u64(writer.count), complete = true}, true, {}
}

/* complete_citation_keys returns deterministic matching keys for completion UI handoff. */
complete_citation_keys :: proc(prefix: string, sources: []Bibliography_Source, entries: []Bibliography_Entry, output: []Citation_Completion) -> (u16, bool) {
	if len(prefix) > MAX_IDENTITY_BYTES || len(entries) > MAX_CITATION_ENTRIES do return 0, false
	for source, index in sources {
		if !bibliography_source_is_valid(source) do return 0, false
		for prior in sources[:index] do if prior.resource_id == source.resource_id do return 0, false
	}
	count := 0
	for entry in entries {
		if !entry.valid || int(entry.source_index) >= len(sources) do return 0, false
		if !strings.has_prefix(entry.key, prefix) do continue
		if count >= len(output) do return 0, false
		source := sources[entry.source_index]
		output[count] = {key = entry.key, title = entry.title,
			source_resource = source.resource_id, source_revision = source.resource_revision}
		count += 1
	}
	for index in 1..<count {
		value := output[index]
		cursor := index
		for cursor > 0 && strings.compare(value.key, output[cursor - 1].key) < 0 {
			output[cursor] = output[cursor - 1]
			cursor -= 1
		}
		output[cursor] = value
	}
	return u16(count), true
}

/* citation_processor_inspection reports CSL and LaTeX adapter availability independently. */
citation_processor_inspection :: proc(processors: []Citation_Processor_Descriptor, generation: Provider_Generation) -> [2]Citation_Processor_Inspection {
	records := [2]Citation_Processor_Inspection {
		{kind = .Csl, identity = "citeproc", state = .Unavailable},
		{kind = .Latex, identity = "latex-citations", state = .Unavailable},
	}
	for &record in records do for processor in processors {
		if processor.kind == record.kind && processor.identity == record.identity && processor.generation == generation &&
		   processor.state == .Available && processor.trusted {
			record.state = .Available
			record.generation = generation
			break
		}
	}
	return records
}

@(private)
citation_processor_is_valid :: proc(processor: Citation_Processor_Descriptor) -> bool {
	return output_text_is_valid(processor.identity, MAX_IDENTITY_BYTES) &&
	       output_text_is_valid(processor.version, MAX_SETTING_VALUE_BYTES) &&
	       processor.generation != Provider_Generation(0) && processor.kind != .Invalid && processor.state != .Invalid
}

@(private)
bibliography_source_is_valid :: proc(source: Bibliography_Source) -> bool {
	return source.resource_id != 0 && source.resource_revision != 0 && source.format != .Invalid && citation_digest_is_present(source.digest)
}

@(private)
bibliography_entry_is_valid :: proc(entry: Bibliography_Entry, source_count: int) -> bool {
	return bibliography_entry_content_is_valid(entry) && int(entry.source_index) < source_count
}

@(private)
bibliography_entry_content_is_valid :: proc(entry: Bibliography_Entry) -> bool {
	return entry.valid && output_text_is_valid(entry.key, MAX_IDENTITY_BYTES) && output_text_is_valid(entry.author, MAX_SETTING_VALUE_BYTES) &&
	       output_text_is_valid(entry.title, MAX_SETTING_VALUE_BYTES) && entry.year > 0 && entry.year <= 9999 &&
	       (len(entry.container) == 0 || output_text_is_valid(entry.container, MAX_SETTING_VALUE_BYTES)) &&
	       (len(entry.url) == 0 || output_text_is_valid(entry.url, MAX_SETTING_VALUE_BYTES))
}

@(private)
citation_reference_render_is_valid :: proc(reference: Citation_Reference) -> bool {
	return output_text_is_valid(reference.key, MAX_IDENTITY_BYTES) && reference.variant != .Invalid &&
	       len(reference.prefix) <= MAX_SETTING_VALUE_BYTES && len(reference.suffix) <= MAX_SETTING_VALUE_BYTES &&
	       len(reference.locator) <= MAX_SETTING_VALUE_BYTES
}

@(private)
citation_reference_is_valid :: proc(reference: Citation_Reference, scope: Scope) -> bool {
	return output_text_is_valid(reference.key, MAX_IDENTITY_BYTES) && reference.variant != .Invalid &&
	       reference.source_start <= reference.source_end && reference.source_end <= scope.source_bytes &&
	       len(reference.prefix) <= MAX_SETTING_VALUE_BYTES && len(reference.suffix) <= MAX_SETTING_VALUE_BYTES &&
	       len(reference.locator) <= MAX_SETTING_VALUE_BYTES
}

@(private)
citation_render_request_is_valid :: proc(request: Citation_Render_Request) -> bool {
	return request.operation_id != Operation_ID(0) && request.processor_kind != .Invalid && request.backend != .Invalid &&
	       output_text_is_valid(request.style_identity, MAX_IDENTITY_BYTES) && output_text_is_valid(request.locale, MAX_IDENTITY_BYTES) &&
	       ((request.style_resource_id == 0 && request.style_revision == 0) ||
	        (request.style_resource_id != 0 && request.style_revision != 0)) &&
	       len(request.references) > 0 && len(request.references) == len(request.resolutions) &&
	       len(request.references) <= MAX_CITATION_REFERENCES && len(request.entries) <= MAX_CITATION_ENTRIES &&
	       limits_are_valid(request.limits) && !(request.processor_kind == .Latex && request.backend != .Latex)
}

@(private)
render_citation_value :: proc(writer: ^Native_Writer, request: Citation_Render_Request, reference: Citation_Reference, entry: Bibliography_Entry) -> bool {
	if request.processor_kind == .Latex {
		command := "cite"
		if reference.variant == .Narrative do command = "textcite"
		if reference.variant == .Author_Only do command = "citeauthor"
		if reference.variant == .Suppress_Author do command = "citeyear"
		if !writer_byte(writer, '\\') || !writer_string(writer, command) do return false
		if len(reference.locator) > 0 && (!writer_byte(writer, '[') || !citation_write_latex(writer, reference.locator) || !writer_byte(writer, ']')) do return false
		return writer_byte(writer, '{') && citation_write_latex(writer, reference.key) && writer_byte(writer, '}')
	}
	open, close := "(", ")"
	if reference.variant == .Narrative || reference.variant == .Author_Only do open, close = "", ""
	if !citation_write_text(writer, request.backend, open) do return false
	if reference.variant != .Suppress_Author {
		if request.backend == .Html && request.include_links && len(entry.url) > 0 {
			if !writer_string(writer, "<a href=\"") || !citation_write_html(writer, entry.url, true) || !writer_string(writer, "\">") ||
			   !citation_write_html(writer, entry.author, false) || !writer_string(writer, "</a>") { return false }
		} else if !citation_write_text(writer, request.backend, entry.author) do return false
	}
	if reference.variant == .Narrative {
		if !citation_write_text(writer, request.backend, " (") || !citation_write_year(writer, entry.year) do return false
		if len(reference.locator) > 0 && (!citation_write_text(writer, request.backend, ", ") || !citation_write_text(writer, request.backend, reference.locator)) do return false
		return citation_write_text(writer, request.backend, ")")
	}
	if reference.variant != .Author_Only {
		if reference.variant != .Suppress_Author && !citation_write_text(writer, request.backend, ", ") do return false
		if !citation_write_year(writer, entry.year) do return false
		if len(reference.locator) > 0 && (!citation_write_text(writer, request.backend, ", ") || !citation_write_text(writer, request.backend, reference.locator)) do return false
	}
	return citation_write_text(writer, request.backend, close)
}

@(private)
render_bibliography_entry :: proc(writer: ^Native_Writer, request: Bibliography_Request, entry: Bibliography_Entry) -> bool {
	switch request.backend {
	case .Html:
		if !writer_string(writer, "<li id=\"ref-") || !citation_write_html(writer, entry.key, true) || !writer_string(writer, "\">") ||
		   !citation_write_html(writer, entry.author, false) || !writer_string(writer, ". <cite>") ||
		   !citation_write_html(writer, entry.title, false) || !writer_string(writer, "</cite>. ") || !citation_write_year(writer, entry.year) { return false }
		if request.include_links && len(entry.url) > 0 && (!writer_string(writer, ". <a href=\"") || !citation_write_html(writer, entry.url, true) || !writer_string(writer, "\">Link</a>")) do return false
		return writer_string(writer, "</li>\n")
	case .Markdown:
		if !writer_string(writer, "- ") || !citation_write_text(writer, .Markdown, entry.author) || !writer_string(writer, ". *") ||
		   !citation_write_text(writer, .Markdown, entry.title) || !writer_string(writer, "*. ") || !citation_write_year(writer, entry.year) { return false }
		if request.include_links && len(entry.url) > 0 && (!writer_string(writer, ". [Link](") || !citation_write_text(writer, .Markdown, entry.url) || !writer_byte(writer, ')')) do return false
		return writer_string(writer, ".\n")
	case .Latex:
		return writer_string(writer, "\\bibitem{") && citation_write_latex(writer, entry.key) && writer_string(writer, "} ") &&
		       citation_write_latex(writer, entry.author) && writer_string(writer, ". \\emph{") && citation_write_latex(writer, entry.title) &&
		       writer_string(writer, "}. ") && citation_write_year(writer, entry.year) && writer_string(writer, ".\n")
	case .Plain_Text:
		return writer_string(writer, entry.author) && writer_string(writer, ". ") && writer_string(writer, entry.title) &&
		       writer_string(writer, ". ") && citation_write_year(writer, entry.year) && writer_string(writer, ".\n")
	case .Invalid: return false
	}
	return false
}

@(private)
bibliography_entry_less :: proc(left, right: Bibliography_Entry, sort: Bibliography_Sort) -> bool {
	switch sort {
	case .Key: return strings.compare(left.key, right.key) < 0
	case .Author:
		comparison := strings.compare(left.author, right.author)
		return comparison < 0 || (comparison == 0 && strings.compare(left.key, right.key) < 0)
	case .Year: return left.year < right.year || (left.year == right.year && strings.compare(left.key, right.key) < 0)
	case .Title:
		comparison := strings.compare(left.title, right.title)
		return comparison < 0 || (comparison == 0 && strings.compare(left.key, right.key) < 0)
	case .Citation_Order, .Invalid: return false
	}
	return false
}

@(private)
citation_write_text :: proc(writer: ^Native_Writer, backend: Citation_Backend, value: string) -> bool {
	if len(value) == 0 do return true
	switch backend {
	case .Html: return citation_write_html(writer, value, false)
	case .Latex: return citation_write_latex(writer, value)
	case .Markdown:
		for byte in transmute([]u8)value {
			if byte == '\\' || byte == '*' || byte == '_' || byte == '[' || byte == ']' {
				if !writer_byte(writer, '\\') do return false
			}
			if !writer_byte(writer, byte) do return false
		}
		return true
	case .Plain_Text: return writer_string(writer, value)
	case .Invalid: return false
	}
	return false
}

@(private)
citation_write_html :: proc(writer: ^Native_Writer, value: string, attribute: bool) -> bool {
	for byte in transmute([]u8)value {
		switch byte {
		case '&': if !writer_string(writer, "&amp;") do return false
		case '<': if !writer_string(writer, "&lt;") do return false
		case '>': if !writer_string(writer, "&gt;") do return false
		case '"':
			if attribute {
				if !writer_string(writer, "&quot;") do return false
			} else if !writer_byte(writer, byte) do return false
		case: if !writer_byte(writer, byte) do return false
		}
	}
	return true
}

@(private)
citation_write_latex :: proc(writer: ^Native_Writer, value: string) -> bool {
	for byte in transmute([]u8)value {
		switch byte {
		case '\\': if !writer_string(writer, "\\textbackslash{}") do return false
		case '&', '%', '$', '#', '_', '{', '}':
			if !writer_byte(writer, '\\') || !writer_byte(writer, byte) do return false
		case '~': if !writer_string(writer, "\\textasciitilde{}") do return false
		case '^': if !writer_string(writer, "\\textasciicircum{}") do return false
		case: if !writer_byte(writer, byte) do return false
		}
	}
	return true
}

@(private)
citation_write_year :: proc(writer: ^Native_Writer, year: i32) -> bool {
	value := year
	digits: [4]u8
	for index in 0..<4 {
		digits[3 - index] = u8('0') + u8(value % 10)
		value /= 10
	}
	return writer_string(writer, string(digits[:]))
}

@(private)
citation_render_limit_failure :: proc(request: Citation_Render_Request, writer: Native_Writer) -> (Citation_Render_Result, bool, Failure) {
	failure := citation_failure(request.operation_id, .Limited, .Limit)
	failure.limit = u64(len(writer.bytes))
	failure.actual = u64(writer.count + 1)
	return {}, false, failure
}

@(private)
citation_bibliography_limit_failure :: proc(request: Bibliography_Request, writer: Native_Writer) -> (Citation_Render_Result, bool, Failure) {
	failure := citation_failure(request.operation_id, .Limited, .Limit)
	failure.limit = u64(len(writer.bytes))
	failure.actual = u64(writer.count + 1)
	return {}, false, failure
}

@(private)
citation_digest_is_present :: proc(digest: [32]u8) -> bool {
	for value in digest do if value != 0 do return true
	return false
}

@(private)
citation_failure :: proc(operation_id: Operation_ID, code: Failure_Code, field: Failure_Field) -> Failure {
	return {operation_id = operation_id, kind = .Export, code = code, field = field}
}
