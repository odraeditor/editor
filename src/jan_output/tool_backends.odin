// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_output

import "core:strings"
import "core:unicode/utf8"

/* Tool_Backend identifies one optional-tool or adapter-backed output family. */
Tool_Backend :: enum u8 {
	Invalid,
	Beamer,
	Latex,
	Pdf,
	Odt,
	Texinfo,
	Info,
	Man_Page,
	ICalendar,
}

/* Tool_State identifies deterministic optional-tool availability. */
Tool_State :: enum u8 {
	Invalid,
	Available,
	Unavailable,
	Quarantined,
}

/* Tool_Step_Kind identifies one bounded external handoff. */
Tool_Step_Kind :: enum u8 {
	Invalid,
	Convert,
	Package,
	Compile,
	Validate,
}

/* Temporary_Resource_Kind identifies one cleanup-owned intermediate. */
Temporary_Resource_Kind :: enum u8 {
	Invalid,
	Directory,
	Source,
	Artifact,
	Log,
}

/* Tool_Descriptor identifies one exact configured executable. */
Tool_Descriptor :: struct {
	identity:   string,
	version:    string,
	generation: Provider_Generation,
	state:      Tool_State,
	trusted:    bool,
}

/* Tool_Step is one non-authorizing bounded process request. */
Tool_Step :: struct {
	kind:                Tool_Step_Kind,
	tool_index:          u16,
	input_resource_id:   u64,
	output_resource_id:  u64,
	timeout_milliseconds: u64,
	maximum_output_bytes: u64,
	sequence:            u16,
	cleanup_required:    bool,
}

/* Temporary_Resource identifies one exact cleanup obligation. */
Temporary_Resource :: struct {
	resource_id: u64,
	kind:        Temporary_Resource_Kind,
	created:     bool,
	cleaned:     bool,
}

/* Tool_Backend_Request identifies one explicit exact-generation adapter plan. */
Tool_Backend_Request :: struct {
	operation_id:       Operation_ID,
	scope:              Scope,
	backend:            Tool_Backend,
	input_resource_id:  u64,
	output_resource_id: u64,
	provider_generation: Provider_Generation,
	explicit:           bool,
	validate_output:    bool,
	limits:             Limits,
}

/* Tool_Backend_Plan describes a complete ordered adapter handoff. */
Tool_Backend_Plan :: struct {
	operation_id:       Operation_ID,
	backend:            Tool_Backend,
	provider_generation: Provider_Generation,
	step_count:         u16,
	temporary_count:    u16,
	cleanup_count:      u16,
	complete:           bool,
}

/* Tool_Backend_Result reports one complete bounded adapter-source candidate. */
Tool_Backend_Result :: struct {
	backend:    Tool_Backend,
	byte_count: u64,
	complete:   bool,
}

/* Odt_Package_Request describes validated ODT structure before packaging. */
Odt_Package_Request :: struct {
	operation_id:       Operation_ID,
	style_resource_id:  u64,
	style_revision:     u64,
	template_resource_id: u64,
	template_revision:  u64,
	media_count:        u32,
	math_count:         u32,
	link_count:         u32,
	content_bytes:      u64,
	converter_required: bool,
}

/* Calendar_Event is one copied deterministic iCalendar projection. */
Calendar_Event :: struct {
	uid:         string,
	summary:     string,
	description: string,
	location:    string,
	start_utc:   string,
	end_utc:     string,
	categories:  string,
	task:        bool,
	completed:   bool,
	private:     bool,
}

/* Tool_Backend_Inspection exposes one stable backend dependency. */
Tool_Backend_Inspection :: struct {
	backend:          Tool_Backend,
	capability:       Capability,
	state:            Availability_State,
	tool_identity:    string,
	tool_generation:  Provider_Generation,
	source_available: bool,
}

/* prepare_tool_backend_plan creates ordered steps and cleanup obligations without execution. */
prepare_tool_backend_plan :: proc(
	request: Tool_Backend_Request,
	tools: []Tool_Descriptor,
	steps: []Tool_Step,
	temporaries: []Temporary_Resource,
) -> (Tool_Backend_Plan, bool, Failure) {
	if request.operation_id == Operation_ID(0) || !scope_is_valid(request.scope) ||
	   request.backend == .Invalid || request.input_resource_id == 0 ||
	   request.output_resource_id == 0 || request.input_resource_id == request.output_resource_id ||
	   request.provider_generation == Provider_Generation(0) || !request.explicit ||
	   !limits_are_valid(request.limits) {
		return {}, false, tool_backend_failure(request.operation_id, .Invalid_Request, .Backend)
	}
	required_tool := tool_backend_required_identity(request.backend)
	if len(required_tool) == 0 {
		return {}, false, tool_backend_failure(request.operation_id, .Invalid_Request, .Backend)
	}
	tool_index := -1
	for tool, index in tools {
		if !tool_descriptor_is_valid(tool) do return {}, false, tool_backend_failure(request.operation_id, .Malformed, .Backend)
		if tool.identity == required_tool {
			if tool_index >= 0 do return {}, false, tool_backend_failure(request.operation_id, .Conflict, .Backend)
			tool_index = index
		}
	}
	if tool_index < 0 || tools[tool_index].state != .Available || !tools[tool_index].trusted ||
	   tools[tool_index].generation != request.provider_generation {
		return {}, false, tool_backend_failure(request.operation_id, .Unavailable, .Backend)
	}
	step_count := 1
	if request.validate_output do step_count += 1
	if request.backend == .Pdf do step_count += 1
	temporary_count := step_count + 1
	if len(steps) < step_count || len(temporaries) < temporary_count ||
	   step_count > int(request.limits.provider_operations) || temporary_count > int(request.limits.publication_targets) {
		failure := tool_backend_failure(request.operation_id, .Limited, .Limit)
		failure.limit = u64(min(len(steps), len(temporaries)))
		failure.actual = u64(max(step_count, temporary_count))
		return {}, false, failure
	}
	step_kind := Tool_Step_Kind.Convert
	if request.backend == .Odt do step_kind = .Package
	if request.backend == .Pdf || request.backend == .Info do step_kind = .Compile
	steps[0] = {kind = step_kind, tool_index = u16(tool_index), input_resource_id = request.input_resource_id,
		output_resource_id = request.output_resource_id, timeout_milliseconds = request.limits.elapsed_milliseconds,
		maximum_output_bytes = request.limits.output_bytes, sequence = 1, cleanup_required = true}
	next_step := 1
	if request.backend == .Pdf {
		steps[next_step] = steps[0]
		steps[next_step].sequence = u16(next_step + 1)
		next_step += 1
	}
	if request.validate_output {
		steps[next_step] = {kind = .Validate, tool_index = u16(tool_index),
			input_resource_id = request.output_resource_id, output_resource_id = request.output_resource_id,
			timeout_milliseconds = request.limits.elapsed_milliseconds,
			maximum_output_bytes = request.limits.output_bytes, sequence = u16(next_step + 1), cleanup_required = true}
	}
	for &temporary, index in temporaries[:temporary_count] {
		temporary = {resource_id = request.output_resource_id + u64(index) + 1,
			kind = .Artifact, created = false, cleaned = false}
		if index == 0 do temporary.kind = .Directory
		if index == temporary_count - 1 do temporary.kind = .Log
	}
	return {operation_id = request.operation_id, backend = request.backend,
		provider_generation = request.provider_generation, step_count = u16(step_count),
		temporary_count = u16(temporary_count), cleanup_count = u16(temporary_count), complete = true}, true, {}
}

/* odt_package_request_is_valid checks structure, template, media, math, and links before packaging. */
odt_package_request_is_valid :: proc(request: Odt_Package_Request, limits := DEFAULT_LIMITS) -> bool {
	return request.operation_id != Operation_ID(0) && request.style_resource_id != 0 &&
	       request.style_revision != 0 &&
	       ((request.template_resource_id == 0 && request.template_revision == 0) ||
	        (request.template_resource_id != 0 && request.template_revision != 0)) &&
	       request.media_count <= limits.publication_targets && request.math_count <= limits.normalized_nodes &&
	       request.link_count <= limits.links && request.content_bytes > 0 && request.content_bytes <= limits.output_bytes
}

/* tool_backend_cleanup_complete checks every created temporary was removed. */
tool_backend_cleanup_complete :: proc(plan: Tool_Backend_Plan, temporaries: []Temporary_Resource) -> bool {
	if !plan.complete || len(temporaries) != int(plan.temporary_count) do return false
	for temporary in temporaries {
		if temporary.resource_id == 0 || temporary.kind == .Invalid || (temporary.created && !temporary.cleaned) do return false
	}
	return true
}

/* tool_backend_inspection reports source and final-artifact availability independently. */
tool_backend_inspection :: proc(tools: []Tool_Descriptor, generation: Provider_Generation) -> [8]Tool_Backend_Inspection {
	records := [8]Tool_Backend_Inspection {
		{backend = .Beamer, capability = .Beamer, tool_identity = "pdflatex", source_available = true},
		{backend = .Latex, capability = .Latex_Pdf, tool_identity = "pdflatex", source_available = true},
		{backend = .Pdf, capability = .Latex_Pdf, tool_identity = "pdflatex"},
		{backend = .Odt, capability = .Odt, tool_identity = "odra-odt-packager"},
		{backend = .Texinfo, capability = .Texinfo_Info, tool_identity = "makeinfo", source_available = true},
		{backend = .Info, capability = .Texinfo_Info, tool_identity = "makeinfo"},
		{backend = .Man_Page, capability = .Man_Page, tool_identity = "groff", source_available = true},
		{backend = .ICalendar, capability = .Calendar, tool_identity = "icalendar-validator", source_available = true},
	}
	for &record in records {
		record.state = .Unavailable
		if record.source_available do record.state = .Available
		for tool in tools {
			if tool.identity == record.tool_identity && tool.generation == generation && tool.state == .Available && tool.trusted {
				record.state = .Available
				record.tool_generation = generation
				break
			}
		}
	}
	return records
}

/* render_tool_source_backend renders deterministic adapter source without invoking tools. */
render_tool_source_backend :: proc(
	operation_id: Operation_ID,
	backend: Tool_Backend,
	document: Native_Document,
	destination: []u8,
	limits := DEFAULT_LIMITS,
) -> (Tool_Backend_Result, bool, Failure) {
	if operation_id == Operation_ID(0) ||
	   (backend != .Beamer && backend != .Latex && backend != .Texinfo && backend != .Man_Page) ||
	   !native_document_is_valid(document, limits) || len(destination) == 0 || u64(len(destination)) > limits.output_bytes {
		return {}, false, tool_backend_failure(operation_id, .Invalid_Request, .Backend)
	}
	writer := Native_Writer {bytes = destination, encoding = .Utf_8}
	ok := false
	#partial switch backend {
	case .Beamer: ok = render_latex_document(&writer, document, true)
	case .Latex: ok = render_latex_document(&writer, document, false)
	case .Texinfo: ok = render_texinfo_document(&writer, document)
	case .Man_Page: ok = render_man_document(&writer, document)
	case: return {}, false, tool_backend_failure(operation_id, .Invalid_Request, .Backend)
	}
	if !ok {
		failure := tool_backend_failure(operation_id, .Unsupported, .Node)
		if writer.limited {
			failure.code = .Limited
			failure.field = .Limit
			failure.limit = u64(len(destination))
			failure.actual = u64(writer.count + 1)
		}
		return {}, false, failure
	}
	return {backend = backend, byte_count = u64(writer.count), complete = true}, true, {}
}

/* render_icalendar renders copied events without transport or publication. */
render_icalendar :: proc(
	operation_id: Operation_ID,
	events: []Calendar_Event,
	destination: []u8,
	limits := DEFAULT_LIMITS,
) -> (Tool_Backend_Result, bool, Failure) {
	if operation_id == Operation_ID(0) || len(events) == 0 || len(events) > int(limits.manifest_entries) ||
	   len(destination) == 0 || u64(len(destination)) > limits.output_bytes {
		return {}, false, tool_backend_failure(operation_id, .Invalid_Request, .Backend)
	}
	writer := Native_Writer {bytes = destination, encoding = .Utf_8}
	if !writer_string(&writer, "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Odra//Jan//EN\r\n") {
		return {}, false, tool_backend_failure(operation_id, .Limited, .Limit)
	}
	for event in events {
		if !calendar_event_is_valid(event) do return {}, false, tool_backend_failure(operation_id, .Malformed, .Node)
		component := "VEVENT"
		if event.task do component = "VTODO"
		if !writer_string(&writer, "BEGIN:") || !writer_string(&writer, component) || !writer_string(&writer, "\r\nUID:") ||
		   !writer_icalendar_text(&writer, event.uid) || !writer_string(&writer, "\r\nDTSTART:") ||
		   !writer_string(&writer, event.start_utc) || !writer_string(&writer, "\r\n") { return {}, false, tool_backend_failure(operation_id, .Limited, .Limit) }
		if len(event.end_utc) > 0 && (!writer_string(&writer, "DTEND:") || !writer_string(&writer, event.end_utc) || !writer_string(&writer, "\r\n")) do return {}, false, tool_backend_failure(operation_id, .Limited, .Limit)
		if !writer_string(&writer, "SUMMARY:") || !writer_icalendar_text(&writer, event.summary) || !writer_string(&writer, "\r\n") do return {}, false, tool_backend_failure(operation_id, .Limited, .Limit)
		if len(event.description) > 0 && (!writer_string(&writer, "DESCRIPTION:") || !writer_icalendar_text(&writer, event.description) || !writer_string(&writer, "\r\n")) do return {}, false, tool_backend_failure(operation_id, .Limited, .Limit)
		if len(event.location) > 0 && (!writer_string(&writer, "LOCATION:") || !writer_icalendar_text(&writer, event.location) || !writer_string(&writer, "\r\n")) do return {}, false, tool_backend_failure(operation_id, .Limited, .Limit)
		if len(event.categories) > 0 && (!writer_string(&writer, "CATEGORIES:") || !writer_icalendar_text(&writer, event.categories) || !writer_string(&writer, "\r\n")) do return {}, false, tool_backend_failure(operation_id, .Limited, .Limit)
		if event.completed && !writer_string(&writer, "STATUS:COMPLETED\r\n") do return {}, false, tool_backend_failure(operation_id, .Limited, .Limit)
		class := "PUBLIC"
		if event.private do class = "PRIVATE"
		if !writer_string(&writer, "CLASS:") || !writer_string(&writer, class) || !writer_string(&writer, "\r\nEND:") ||
		   !writer_string(&writer, component) || !writer_string(&writer, "\r\n") { return {}, false, tool_backend_failure(operation_id, .Limited, .Limit) }
	}
	if !writer_string(&writer, "END:VCALENDAR\r\n") do return {}, false, tool_backend_failure(operation_id, .Limited, .Limit)
	return {backend = .ICalendar, byte_count = u64(writer.count), complete = true}, true, {}
}

@(private)
tool_descriptor_is_valid :: proc(tool: Tool_Descriptor) -> bool {
	return output_text_is_valid(tool.identity, MAX_IDENTITY_BYTES) &&
	       output_text_is_valid(tool.version, MAX_SETTING_VALUE_BYTES) &&
	       tool.generation != Provider_Generation(0) && tool.state != .Invalid
}

@(private)
tool_backend_required_identity :: proc(backend: Tool_Backend) -> string {
	switch backend {
	case .Beamer, .Latex, .Pdf: return "pdflatex"
	case .Odt: return "odra-odt-packager"
	case .Texinfo, .Info: return "makeinfo"
	case .Man_Page: return "groff"
	case .ICalendar: return "icalendar-validator"
	case .Invalid: return ""
	}
	return ""
}

@(private)
render_latex_document :: proc(writer: ^Native_Writer, document: Native_Document, beamer: bool) -> bool {
	class := "article"
	if beamer do class = "beamer"
	if !writer_string(writer, "\\documentclass{") || !writer_string(writer, class) ||
	   !writer_string(writer, "}\n\\usepackage{hyperref}\n\\usepackage{graphicx}\n\\title{") ||
	   !writer_latex_escaped(writer, document.title) || !writer_string(writer, "}\n\\begin{document}\n\\maketitle\n") { return false }
	frame_open := false
	for block in document.blocks {
		fragments := document.fragments[int(block.fragment_start):int(block.fragment_start + block.fragment_count)]
		if beamer && block.kind == .Heading {
			if frame_open && !writer_string(writer, "\\end{frame}\n") do return false
			if !writer_string(writer, "\\begin{frame}[fragile]{") || !render_latex_fragments(writer, fragments) || !writer_string(writer, "}\n") do return false
			frame_open = true
			continue
		}
		switch block.kind {
		case .Heading:
			command := "section"
			if block.level == 2 do command = "subsection"
			if block.level > 2 do command = "subsubsection"
			if !writer_string(writer, "\\") || !writer_string(writer, command) || !writer_byte(writer, '{') ||
			   !render_latex_fragments(writer, fragments) || !writer_string(writer, "}\n") { return false }
		case .Paragraph:
			if !render_latex_fragments(writer, fragments) || !writer_string(writer, "\n\n") do return false
		case .List_Item:
			if !writer_string(writer, "\\begin{itemize}\n\\item ") || !render_latex_fragments(writer, fragments) || !writer_string(writer, "\n\\end{itemize}\n") do return false
		case .Quote:
			if !writer_string(writer, "\\begin{quote}\n") || !render_latex_fragments(writer, fragments) || !writer_string(writer, "\n\\end{quote}\n") do return false
		case .Source, .Example:
			if !writer_string(writer, "\\begin{verbatim}\n") || !render_latex_verbatim_fragments(writer, fragments) || !writer_string(writer, "\n\\end{verbatim}\n") do return false
		case .Horizontal_Rule:
			if !writer_string(writer, "\\hrulefill\n") do return false
		case .Raw, .Invalid:
			return false
		}
	}
	if frame_open && !writer_string(writer, "\\end{frame}\n") do return false
	return writer_string(writer, "\\end{document}\n")
}

@(private)
render_latex_fragments :: proc(writer: ^Native_Writer, fragments: []Native_Fragment) -> bool {
	for fragment in fragments {
		switch fragment.kind {
		case .Text: if !writer_latex_escaped(writer, fragment.text) do return false
		case .Emphasis:
			if !writer_string(writer, "\\emph{") || !writer_latex_escaped(writer, fragment.text) || !writer_byte(writer, '}') do return false
		case .Strong:
			if !writer_string(writer, "\\textbf{") || !writer_latex_escaped(writer, fragment.text) || !writer_byte(writer, '}') do return false
		case .Code:
			if !writer_string(writer, "\\texttt{") || !writer_latex_escaped(writer, fragment.text) || !writer_byte(writer, '}') do return false
		case .Link:
			if !writer_string(writer, "\\href{") || !writer_latex_escaped(writer, fragment.target) || !writer_string(writer, "}{") ||
			   !writer_latex_escaped(writer, fragment.text) || !writer_byte(writer, '}') { return false }
		case .Image:
			if !writer_string(writer, "\\includegraphics{") || !writer_latex_escaped(writer, fragment.target) || !writer_byte(writer, '}') do return false
		case .Math:
			if !writer_byte(writer, '$') || !writer_string(writer, fragment.text) || !writer_byte(writer, '$') do return false
		case .Raw, .Invalid:
			return false
		}
	}
	return true
}

@(private)
render_latex_verbatim_fragments :: proc(writer: ^Native_Writer, fragments: []Native_Fragment) -> bool {
	for fragment in fragments {
		if fragment.kind == .Raw || strings.contains(fragment.text, "\\end{verbatim}") ||
		   !writer_string(writer, fragment.text) { return false }
	}
	return true
}

@(private)
render_texinfo_document :: proc(writer: ^Native_Writer, document: Native_Document) -> bool {
	if !writer_string(writer, "\\input texinfo\n@setfilename output.info\n@node Top\n@top ") ||
	   !writer_texinfo_escaped(writer, document.title) || !writer_byte(writer, '\n') { return false }
	for block in document.blocks {
		fragments := document.fragments[int(block.fragment_start):int(block.fragment_start + block.fragment_count)]
		switch block.kind {
		case .Heading:
			command := "chapter"
			if block.level == 2 do command = "section"
			if block.level > 2 do command = "subsection"
			if !writer_byte(writer, '@') || !writer_string(writer, command) || !writer_byte(writer, ' ') || !render_texinfo_fragments(writer, fragments) || !writer_byte(writer, '\n') do return false
		case .Paragraph:
			if !render_texinfo_fragments(writer, fragments) || !writer_string(writer, "\n\n") do return false
		case .List_Item:
			if !writer_string(writer, "@itemize @bullet\n@item ") || !render_texinfo_fragments(writer, fragments) || !writer_string(writer, "\n@end itemize\n") do return false
		case .Quote:
			if !writer_string(writer, "@quotation\n") || !render_texinfo_fragments(writer, fragments) || !writer_string(writer, "\n@end quotation\n") do return false
		case .Source, .Example:
			if !writer_string(writer, "@example\n") || !render_texinfo_verbatim_fragments(writer, fragments) || !writer_string(writer, "\n@end example\n") do return false
		case .Horizontal_Rule:
			if !writer_string(writer, "@center ----------\n") do return false
		case .Raw, .Invalid:
			return false
		}
	}
	return writer_string(writer, "@bye\n")
}

@(private)
render_texinfo_verbatim_fragments :: proc(writer: ^Native_Writer, fragments: []Native_Fragment) -> bool {
	for fragment in fragments do if fragment.kind == .Raw || !writer_texinfo_escaped(writer, fragment.text) do return false
	return true
}

@(private)
render_texinfo_fragments :: proc(writer: ^Native_Writer, fragments: []Native_Fragment) -> bool {
	for fragment in fragments {
		switch fragment.kind {
		case .Text: if !writer_texinfo_escaped(writer, fragment.text) do return false
		case .Emphasis:
			if !writer_string(writer, "@emph{") || !writer_texinfo_escaped(writer, fragment.text) || !writer_byte(writer, '}') do return false
		case .Strong:
			if !writer_string(writer, "@strong{") || !writer_texinfo_escaped(writer, fragment.text) || !writer_byte(writer, '}') do return false
		case .Code:
			if !writer_string(writer, "@code{") || !writer_texinfo_escaped(writer, fragment.text) || !writer_byte(writer, '}') do return false
		case .Link:
			if !writer_string(writer, "@uref{") || !writer_texinfo_escaped(writer, fragment.target) || !writer_byte(writer, ',') ||
			   !writer_texinfo_escaped(writer, fragment.text) || !writer_byte(writer, '}') { return false }
		case .Image:
			if !writer_string(writer, "@image{") || !writer_texinfo_escaped(writer, fragment.target) || !writer_string(writer, ",,,,\"") ||
			   !writer_texinfo_escaped(writer, fragment.text) || !writer_string(writer, "\"}") { return false }
		case .Math:
			if !writer_string(writer, "@math{") || !writer_texinfo_escaped(writer, fragment.text) || !writer_byte(writer, '}') do return false
		case .Raw, .Invalid:
			return false
		}
	}
	return true
}

@(private)
render_man_document :: proc(writer: ^Native_Writer, document: Native_Document) -> bool {
	if !writer_string(writer, ".TH \"") || !writer_roff_escaped(writer, document.title) || !writer_string(writer, "\" \"1\"\n") do return false
	for block in document.blocks {
		fragments := document.fragments[int(block.fragment_start):int(block.fragment_start + block.fragment_count)]
		switch block.kind {
		case .Heading:
			if !writer_string(writer, ".SH \"") || !render_roff_fragments(writer, fragments) || !writer_string(writer, "\"\n") do return false
		case .Paragraph:
			if !writer_string(writer, ".PP\n") || !render_roff_fragments(writer, fragments) || !writer_byte(writer, '\n') do return false
		case .List_Item:
			if !writer_string(writer, ".IP \\(bu 2\n") || !render_roff_fragments(writer, fragments) || !writer_byte(writer, '\n') do return false
		case .Quote:
			if !writer_string(writer, ".RS\n") || !render_roff_fragments(writer, fragments) || !writer_string(writer, "\n.RE\n") do return false
		case .Source, .Example:
			if !writer_string(writer, ".nf\n") || !render_roff_verbatim_fragments(writer, fragments) || !writer_string(writer, "\n.fi\n") do return false
		case .Horizontal_Rule:
			if !writer_string(writer, ".sp\n\\l'\\n(.lu'\n.sp\n") do return false
		case .Raw, .Invalid:
			return false
		}
	}
	return true
}

@(private)
render_roff_verbatim_fragments :: proc(writer: ^Native_Writer, fragments: []Native_Fragment) -> bool {
	for fragment in fragments do if fragment.kind == .Raw || !writer_roff_escaped(writer, fragment.text) do return false
	return true
}

@(private)
render_roff_fragments :: proc(writer: ^Native_Writer, fragments: []Native_Fragment) -> bool {
	for fragment in fragments {
		switch fragment.kind {
		case .Text: if !writer_roff_escaped(writer, fragment.text) do return false
		case .Emphasis:
			if !writer_string(writer, "\\fI") || !writer_roff_escaped(writer, fragment.text) || !writer_string(writer, "\\fP") do return false
		case .Strong:
			if !writer_string(writer, "\\fB") || !writer_roff_escaped(writer, fragment.text) || !writer_string(writer, "\\fP") do return false
		case .Code:
			if !writer_string(writer, "\\f(CW") || !writer_roff_escaped(writer, fragment.text) || !writer_string(writer, "\\fP") do return false
		case .Link:
			if !writer_roff_escaped(writer, fragment.text) || !writer_string(writer, " (") || !writer_roff_escaped(writer, fragment.target) || !writer_byte(writer, ')') do return false
		case .Image:
			if !writer_string(writer, "[Image: ") || !writer_roff_escaped(writer, fragment.text) || !writer_string(writer, "] (") ||
			   !writer_roff_escaped(writer, fragment.target) || !writer_byte(writer, ')') { return false }
		case .Math: if !writer_roff_escaped(writer, fragment.text) do return false
		case .Raw, .Invalid: return false
		}
	}
	return true
}

@(private)
writer_latex_escaped :: proc(writer: ^Native_Writer, value: string) -> bool {
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
writer_texinfo_escaped :: proc(writer: ^Native_Writer, value: string) -> bool {
	for byte in transmute([]u8)value {
		if byte == '@' || byte == '{' || byte == '}' {
			if !writer_byte(writer, '@') do return false
		}
		if !writer_byte(writer, byte) do return false
	}
	return true
}

@(private)
writer_roff_escaped :: proc(writer: ^Native_Writer, value: string) -> bool {
	for byte in transmute([]u8)value {
		if (byte == '.' || byte == '\'') && (writer.count == 0 || writer.bytes[writer.count - 1] == '\n') {
			if !writer_string(writer, "\\&") do return false
		}
		if byte == '\\' && !writer_string(writer, "\\e") do return false
		if byte != '\\' && !writer_byte(writer, byte) do return false
	}
	return true
}

@(private)
writer_icalendar_text :: proc(writer: ^Native_Writer, value: string) -> bool {
	for byte in transmute([]u8)value {
		switch byte {
		case '\\': if !writer_string(writer, "\\\\") do return false
		case ',': if !writer_string(writer, "\\,") do return false
		case ';': if !writer_string(writer, "\\;") do return false
		case '\n': if !writer_string(writer, "\\n") do return false
		case '\r':
		case: if !writer_byte(writer, byte) do return false
		}
	}
	return true
}

@(private)
calendar_event_is_valid :: proc(event: Calendar_Event) -> bool {
	return output_text_is_valid(event.uid, MAX_SETTING_VALUE_BYTES) &&
	       output_text_is_valid(event.summary, MAX_SETTING_VALUE_BYTES) &&
	       calendar_utc_is_valid(event.start_utc) &&
	       (len(event.end_utc) == 0 || calendar_utc_is_valid(event.end_utc)) &&
	       utf8.valid_string(event.description) && utf8.valid_string(event.location) && utf8.valid_string(event.categories) &&
	       (!event.completed || event.task)
}

@(private)
calendar_utc_is_valid :: proc(value: string) -> bool {
	bytes := transmute([]u8)value
	if len(bytes) != 16 || bytes[8] != 'T' || bytes[15] != 'Z' do return false
	for byte, index in bytes {
		if index == 8 || index == 15 do continue
		if byte < '0' || byte > '9' do return false
	}
	return true
}

@(private)
tool_backend_failure :: proc(operation_id: Operation_ID, code: Failure_Code, field: Failure_Field) -> Failure {
	return {operation_id = operation_id, kind = .Export, code = code, field = field}
}
