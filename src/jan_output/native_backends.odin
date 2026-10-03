// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_output

import "core:unicode/utf8"

/* Native_Backend identifies one factory-native deterministic renderer. */
Native_Backend :: enum u8 {
	Invalid,
	Plain_Text,
	Html,
	Markdown,
	Normalized_Jan,
}

/* Text_Encoding identifies plain-text output encoding. */
Text_Encoding :: enum u8 {
	Invalid,
	Utf_8,
	Ascii,
	Latin_1,
}

/* Unsupported_Policy controls explicit native-backend degradation. */
Unsupported_Policy :: enum u8 {
	Invalid,
	Reject,
	Plain_Text_With_Warning,
	Omit_With_Warning,
}

/* Native_Block_Kind identifies one normalized block family. */
Native_Block_Kind :: enum u8 {
	Invalid,
	Heading,
	Paragraph,
	List_Item,
	Quote,
	Source,
	Example,
	Horizontal_Rule,
	Raw,
}

/* Native_Fragment_Kind identifies one normalized inline family. */
Native_Fragment_Kind :: enum u8 {
	Invalid,
	Text,
	Emphasis,
	Strong,
	Code,
	Link,
	Image,
	Math,
	Raw,
}

/* Native_Fragment is one borrowed normalized inline value. */
Native_Fragment :: struct {
	kind:   Native_Fragment_Kind,
	text:   string,
	target: string,
}

/* Native_Block is one borrowed normalized block and fragment interval. */
Native_Block :: struct {
	kind:           Native_Block_Kind,
	level:          u16,
	fragment_start: u32,
	fragment_count: u32,
	language:       string,
}

/* Native_Document is one bounded normalized input for factory-native backends. */
Native_Document :: struct {
	title:     string,
	language:  string,
	blocks:    []Native_Block,
	fragments: []Native_Fragment,
}

/* Native_Backend_Options controls explicit safe rendering policy. */
Native_Backend_Options :: struct {
	encoding:          Text_Encoding,
	replace_unencodable: bool,
	full_document:     bool,
	allow_raw:         bool,
	unsupported:       Unsupported_Policy,
	css:               string,
}

/* Native_Backend_Result reports one complete bounded rendered candidate. */
Native_Backend_Result :: struct {
	backend:          Native_Backend,
	byte_count:       u64,
	diagnostic_count: u32,
	complete:         bool,
}

/* Native_Backend_Inspection exposes stable factory-native backend behavior. */
Native_Backend_Inspection :: struct {
	backend:                Native_Backend,
	capability:             Capability,
	state:                  Availability_State,
	supports_full_document: bool,
	raw_requires_policy:    bool,
	encoding_count:         u8,
}

/* native_backend_inspection returns every factory-native backend identity. */
native_backend_inspection :: proc() -> [4]Native_Backend_Inspection {
	return {
		{backend = .Plain_Text, capability = .Plain_Text, state = .Available,
		 raw_requires_policy = true, encoding_count = 3},
		{backend = .Html, capability = .Html, state = .Available,
		 supports_full_document = true, raw_requires_policy = true, encoding_count = 1},
		{backend = .Markdown, capability = .Markdown, state = .Available,
		 raw_requires_policy = true, encoding_count = 1},
		{backend = .Normalized_Jan, capability = .Normalized_Jan, state = .Available,
		 raw_requires_policy = true, encoding_count = 1},
	}
}

/* render_native_backend renders one checked native backend into caller-owned storage. */
render_native_backend :: proc(
	operation_id: Operation_ID,
	backend: Native_Backend,
	document: Native_Document,
	options: Native_Backend_Options,
	destination: []u8,
	limits := DEFAULT_LIMITS,
) -> (Native_Backend_Result, bool, Failure) {
	if operation_id == Operation_ID(0) || backend == .Invalid || len(destination) == 0 ||
	   u64(len(destination)) > limits.output_bytes || options.unsupported == .Invalid ||
	   !native_document_is_valid(document, limits) {
		return {}, false, backend_failure(operation_id, .Invalid_Request, .Node)
	}
	if backend == .Plain_Text && options.encoding == .Invalid {
		return {}, false, backend_failure(operation_id, .Invalid_Request, .Destination)
	}
	writer := Native_Writer {bytes = destination, encoding = .Utf_8, replace_unencodable = false}
	if backend == .Plain_Text {
		writer.encoding = options.encoding
		writer.replace_unencodable = options.replace_unencodable
	}
	diagnostics: u32
	ok := false
	switch backend {
	case .Plain_Text:
		ok = render_plain_text(&writer, document, options, &diagnostics)
	case .Html:
		ok = render_html(&writer, document, options, &diagnostics)
	case .Markdown:
		ok = render_markdown(&writer, document, options, &diagnostics)
	case .Normalized_Jan:
		ok = render_normalized_jan(&writer, document, options, &diagnostics)
	case .Invalid:
	}
	if !ok {
		failure := backend_failure(operation_id, .Unsupported, .Node)
		if writer.limited {
			failure.code = .Limited
			failure.field = .Limit
			failure.limit = u64(len(destination))
			failure.actual = u64(writer.count + 1)
		} else if writer.unencodable {
			failure.code = .Validation
			failure.field = .Destination
		}
		return {}, false, failure
	}
	return {backend = backend, byte_count = u64(writer.count), diagnostic_count = diagnostics, complete = true}, true, {}
}

@(private)
Native_Writer :: struct {
	bytes:              []u8,
	count:              int,
	encoding:           Text_Encoding,
	replace_unencodable: bool,
	limited:            bool,
	unencodable:        bool,
}

@(private)
native_document_is_valid :: proc(document: Native_Document, limits: Limits) -> bool {
	if !utf8.valid_string(document.title) || !utf8.valid_string(document.language) ||
	   len(document.blocks) == 0 || len(document.blocks) > int(limits.normalized_nodes) ||
	   len(document.fragments) > int(limits.normalized_nodes) {
		return false
	}
	for block in document.blocks {
		if block.kind == .Invalid || int(block.fragment_start) > len(document.fragments) ||
		   int(block.fragment_count) > len(document.fragments) - int(block.fragment_start) ||
		   (block.kind == .Heading && (block.level == 0 || block.level > 64)) ||
		   ((block.kind == .Source || block.kind == .Example) && !utf8.valid_string(block.language)) {
			return false
		}
	}
	for fragment in document.fragments {
		if fragment.kind == .Invalid || !utf8.valid_string(fragment.text) || !utf8.valid_string(fragment.target) ||
		   ((fragment.kind == .Link || fragment.kind == .Image) && len(fragment.target) == 0) {
			return false
		}
	}
	return true
}

@(private)
render_plain_text :: proc(writer: ^Native_Writer, document: Native_Document, options: Native_Backend_Options, diagnostics: ^u32) -> bool {
	if len(document.title) > 0 && (!writer_text(writer, document.title) || !writer_string(writer, "\n\n")) do return false
	for block in document.blocks {
		fragments := document.fragments[int(block.fragment_start):int(block.fragment_start + block.fragment_count)]
		switch block.kind {
		case .Heading:
			start := writer.count
			if !render_plain_fragments(writer, fragments, options, diagnostics) || !writer_byte(writer, '\n') do return false
			width := writer.count - start - 1
			underline := u8('-')
			if block.level == 1 do underline = '='
			for _ in 0 ..< width do if !writer_byte(writer, underline) do return false
			if !writer_string(writer, "\n\n") do return false
		case .Paragraph:
			if !render_plain_fragments(writer, fragments, options, diagnostics) || !writer_string(writer, "\n\n") do return false
		case .List_Item:
			if !writer_string(writer, "- ") || !render_plain_fragments(writer, fragments, options, diagnostics) || !writer_byte(writer, '\n') do return false
		case .Quote:
			if !writer_string(writer, "> ") || !render_plain_fragments(writer, fragments, options, diagnostics) || !writer_string(writer, "\n\n") do return false
		case .Source, .Example:
			if !writer_string(writer, "    ") || !render_plain_fragments(writer, fragments, options, diagnostics) || !writer_string(writer, "\n\n") do return false
		case .Horizontal_Rule:
			if !writer_string(writer, "----------------------------------------\n\n") do return false
		case .Raw:
			if !render_unsupported_plain(writer, fragments, options, diagnostics) do return false
		case .Invalid:
			return false
		}
	}
	return true
}

@(private)
render_plain_fragments :: proc(writer: ^Native_Writer, fragments: []Native_Fragment, options: Native_Backend_Options, diagnostics: ^u32) -> bool {
	for fragment in fragments {
		switch fragment.kind {
		case .Text, .Emphasis, .Strong, .Code, .Math:
			if !writer_text(writer, fragment.text) do return false
		case .Link:
			if !writer_text(writer, fragment.text) || !writer_string(writer, " <") ||
			   !writer_text(writer, fragment.target) || !writer_byte(writer, '>') { return false }
		case .Image:
			if !writer_string(writer, "[Image: ") || !writer_text(writer, fragment.text) ||
			   !writer_string(writer, "] <") || !writer_text(writer, fragment.target) || !writer_byte(writer, '>') { return false }
		case .Raw:
			if options.allow_raw {
				if !writer_text(writer, fragment.text) do return false
			} else if !handle_unsupported(writer, fragment.text, options.unsupported, diagnostics) do return false
		case .Invalid:
			return false
		}
	}
	return true
}

@(private)
render_html :: proc(writer: ^Native_Writer, document: Native_Document, options: Native_Backend_Options, diagnostics: ^u32) -> bool {
	if options.full_document {
		if !writer_string(writer, "<!doctype html>\n<html lang=\"") || !writer_html_escaped(writer, document.language, true) ||
		   !writer_string(writer, "\">\n<head>\n<meta charset=\"utf-8\">\n<title>") ||
		   !writer_html_escaped(writer, document.title, false) || !writer_string(writer, "</title>\n") { return false }
		if len(options.css) > 0 && (!writer_string(writer, "<style>") || !writer_html_escaped(writer, options.css, false) || !writer_string(writer, "</style>\n")) do return false
		if !writer_string(writer, "</head>\n<body>\n") do return false
	}
	for block in document.blocks {
		fragments := document.fragments[int(block.fragment_start):int(block.fragment_start + block.fragment_count)]
		switch block.kind {
		case .Heading:
			level := min(block.level, u16(6))
			if !writer_string(writer, "<h") || !writer_decimal(writer, u64(level)) || !writer_byte(writer, '>') ||
			   !render_html_fragments(writer, fragments, options, diagnostics) || !writer_string(writer, "</h") ||
			   !writer_decimal(writer, u64(level)) || !writer_string(writer, ">\n") { return false }
		case .Paragraph:
			if !writer_string(writer, "<p>") || !render_html_fragments(writer, fragments, options, diagnostics) || !writer_string(writer, "</p>\n") do return false
		case .List_Item:
			if !writer_string(writer, "<li>") || !render_html_fragments(writer, fragments, options, diagnostics) || !writer_string(writer, "</li>\n") do return false
		case .Quote:
			if !writer_string(writer, "<blockquote>") || !render_html_fragments(writer, fragments, options, diagnostics) || !writer_string(writer, "</blockquote>\n") do return false
		case .Source, .Example:
			if !writer_string(writer, "<pre><code") do return false
			if len(block.language) > 0 && (!writer_string(writer, " class=\"language-") || !writer_html_escaped(writer, block.language, true) || !writer_byte(writer, '"')) do return false
			if !writer_byte(writer, '>') || !render_html_fragments(writer, fragments, options, diagnostics) || !writer_string(writer, "</code></pre>\n") do return false
		case .Horizontal_Rule:
			if !writer_string(writer, "<hr>\n") do return false
		case .Raw:
			if options.allow_raw {
				for fragment in fragments do if !writer_string(writer, fragment.text) do return false
				if !writer_byte(writer, '\n') do return false
			} else {
				for fragment in fragments do if !handle_html_unsupported(writer, fragment.text, options.unsupported, diagnostics) do return false
				if !writer_byte(writer, '\n') do return false
			}
		case .Invalid:
			return false
		}
	}
	if options.full_document && !writer_string(writer, "</body>\n</html>\n") do return false
	return true
}

@(private)
render_html_fragments :: proc(writer: ^Native_Writer, fragments: []Native_Fragment, options: Native_Backend_Options, diagnostics: ^u32) -> bool {
	for fragment in fragments {
		switch fragment.kind {
		case .Text:
			if !writer_html_escaped(writer, fragment.text, false) do return false
		case .Emphasis:
			if !writer_string(writer, "<em>") || !writer_html_escaped(writer, fragment.text, false) || !writer_string(writer, "</em>") do return false
		case .Strong:
			if !writer_string(writer, "<strong>") || !writer_html_escaped(writer, fragment.text, false) || !writer_string(writer, "</strong>") do return false
		case .Code:
			if !writer_string(writer, "<code>") || !writer_html_escaped(writer, fragment.text, false) || !writer_string(writer, "</code>") do return false
		case .Link:
			if !writer_string(writer, "<a href=\"") || !writer_html_escaped(writer, fragment.target, true) || !writer_string(writer, "\">") ||
			   !writer_html_escaped(writer, fragment.text, false) || !writer_string(writer, "</a>") { return false }
		case .Image:
			if !writer_string(writer, "<img src=\"") || !writer_html_escaped(writer, fragment.target, true) ||
			   !writer_string(writer, "\" alt=\"") || !writer_html_escaped(writer, fragment.text, true) || !writer_string(writer, "\">") { return false }
		case .Math:
			if !writer_string(writer, "<span class=\"math\">") || !writer_html_escaped(writer, fragment.text, false) || !writer_string(writer, "</span>") do return false
		case .Raw:
			if options.allow_raw {
				if !writer_string(writer, fragment.text) do return false
			} else if !handle_html_unsupported(writer, fragment.text, options.unsupported, diagnostics) do return false
		case .Invalid:
			return false
		}
	}
	return true
}

@(private)
render_markdown :: proc(writer: ^Native_Writer, document: Native_Document, options: Native_Backend_Options, diagnostics: ^u32) -> bool {
	if len(document.title) > 0 && (!writer_string(writer, "# ") || !writer_markdown_escaped(writer, document.title) || !writer_string(writer, "\n\n")) do return false
	for block in document.blocks {
		fragments := document.fragments[int(block.fragment_start):int(block.fragment_start + block.fragment_count)]
		switch block.kind {
		case .Heading:
			for _ in 0 ..< int(block.level) do if !writer_byte(writer, '#') do return false
			if !writer_byte(writer, ' ') || !render_markdown_fragments(writer, fragments, options, diagnostics) || !writer_string(writer, "\n\n") do return false
		case .Paragraph:
			if !render_markdown_fragments(writer, fragments, options, diagnostics) || !writer_string(writer, "\n\n") do return false
		case .List_Item:
			if !writer_string(writer, "- ") || !render_markdown_fragments(writer, fragments, options, diagnostics) || !writer_byte(writer, '\n') do return false
		case .Quote:
			if !writer_string(writer, "> ") || !render_markdown_fragments(writer, fragments, options, diagnostics) || !writer_string(writer, "\n\n") do return false
		case .Source, .Example:
			if !writer_string(writer, "```") || !writer_string(writer, block.language) || !writer_byte(writer, '\n') ||
			   !render_plain_fragments(writer, fragments, options, diagnostics) || !writer_string(writer, "\n```\n\n") { return false }
		case .Horizontal_Rule:
			if !writer_string(writer, "---\n\n") do return false
		case .Raw:
			if options.allow_raw {
				for fragment in fragments do if !writer_string(writer, fragment.text) do return false
				if !writer_string(writer, "\n\n") do return false
			} else if !render_unsupported_plain(writer, fragments, options, diagnostics) do return false
		case .Invalid:
			return false
		}
	}
	return true
}

@(private)
render_markdown_fragments :: proc(writer: ^Native_Writer, fragments: []Native_Fragment, options: Native_Backend_Options, diagnostics: ^u32) -> bool {
	for fragment in fragments {
		switch fragment.kind {
		case .Text:
			if !writer_markdown_escaped(writer, fragment.text) do return false
		case .Emphasis:
			if !writer_byte(writer, '*') || !writer_markdown_escaped(writer, fragment.text) || !writer_byte(writer, '*') do return false
		case .Strong:
			if !writer_string(writer, "**") || !writer_markdown_escaped(writer, fragment.text) || !writer_string(writer, "**") do return false
		case .Code:
			if !writer_byte(writer, '`') || !writer_string(writer, fragment.text) || !writer_byte(writer, '`') do return false
		case .Link:
			if !writer_byte(writer, '[') || !writer_markdown_escaped(writer, fragment.text) || !writer_string(writer, "](") ||
			   !writer_string(writer, fragment.target) || !writer_byte(writer, ')') { return false }
		case .Image:
			if !writer_string(writer, "![") || !writer_markdown_escaped(writer, fragment.text) || !writer_string(writer, "](") ||
			   !writer_string(writer, fragment.target) || !writer_byte(writer, ')') { return false }
		case .Math:
			if !writer_byte(writer, '$') || !writer_string(writer, fragment.text) || !writer_byte(writer, '$') do return false
		case .Raw:
			if options.allow_raw {
				if !writer_string(writer, fragment.text) do return false
			} else if !handle_unsupported(writer, fragment.text, options.unsupported, diagnostics) do return false
		case .Invalid:
			return false
		}
	}
	return true
}

@(private)
render_normalized_jan :: proc(writer: ^Native_Writer, document: Native_Document, options: Native_Backend_Options, diagnostics: ^u32) -> bool {
	if len(document.title) > 0 && (!writer_string(writer, "#+title: ") || !writer_string(writer, document.title) || !writer_string(writer, "\n\n")) do return false
	for block in document.blocks {
		fragments := document.fragments[int(block.fragment_start):int(block.fragment_start + block.fragment_count)]
		switch block.kind {
		case .Heading:
			for _ in 0 ..< int(block.level) do if !writer_byte(writer, '*') do return false
			if !writer_byte(writer, ' ') || !render_jan_fragments(writer, fragments, options, diagnostics) || !writer_string(writer, "\n\n") do return false
		case .Paragraph:
			if !render_jan_fragments(writer, fragments, options, diagnostics) || !writer_string(writer, "\n\n") do return false
		case .List_Item:
			if !writer_string(writer, "- ") || !render_jan_fragments(writer, fragments, options, diagnostics) || !writer_byte(writer, '\n') do return false
		case .Quote:
			if !writer_string(writer, "#+begin_quote\n") || !render_jan_fragments(writer, fragments, options, diagnostics) || !writer_string(writer, "\n#+end_quote\n\n") do return false
		case .Source:
			if !writer_string(writer, "#+begin_src ") || !writer_string(writer, block.language) || !writer_byte(writer, '\n') ||
			   !render_plain_fragments(writer, fragments, options, diagnostics) || !writer_string(writer, "\n#+end_src\n\n") { return false }
		case .Example:
			if !writer_string(writer, "#+begin_example\n") || !render_plain_fragments(writer, fragments, options, diagnostics) || !writer_string(writer, "\n#+end_example\n\n") do return false
		case .Horizontal_Rule:
			if !writer_string(writer, "-----\n\n") do return false
		case .Raw:
			if options.allow_raw {
				for fragment in fragments do if !writer_string(writer, fragment.text) do return false
				if !writer_string(writer, "\n\n") do return false
			} else if !render_unsupported_plain(writer, fragments, options, diagnostics) do return false
		case .Invalid:
			return false
		}
	}
	return true
}

@(private)
render_jan_fragments :: proc(writer: ^Native_Writer, fragments: []Native_Fragment, options: Native_Backend_Options, diagnostics: ^u32) -> bool {
	for fragment in fragments {
		switch fragment.kind {
		case .Text:
			if !writer_string(writer, fragment.text) do return false
		case .Emphasis:
			if !writer_byte(writer, '/') || !writer_string(writer, fragment.text) || !writer_byte(writer, '/') do return false
		case .Strong:
			if !writer_byte(writer, '*') || !writer_string(writer, fragment.text) || !writer_byte(writer, '*') do return false
		case .Code:
			if !writer_byte(writer, '~') || !writer_string(writer, fragment.text) || !writer_byte(writer, '~') do return false
		case .Link:
			if !writer_string(writer, "[[") || !writer_string(writer, fragment.target) || !writer_string(writer, "][") ||
			   !writer_string(writer, fragment.text) || !writer_string(writer, "]]") { return false }
		case .Image:
			if !writer_string(writer, "[[") || !writer_string(writer, fragment.target) || !writer_string(writer, "][") ||
			   !writer_string(writer, fragment.text) || !writer_string(writer, "]]") { return false }
		case .Math:
			if !writer_string(writer, "\\(") || !writer_string(writer, fragment.text) || !writer_string(writer, "\\)") do return false
		case .Raw:
			if options.allow_raw {
				if !writer_string(writer, fragment.text) do return false
			} else if !handle_unsupported(writer, fragment.text, options.unsupported, diagnostics) do return false
		case .Invalid:
			return false
		}
	}
	return true
}

@(private)
render_unsupported_plain :: proc(writer: ^Native_Writer, fragments: []Native_Fragment, options: Native_Backend_Options, diagnostics: ^u32) -> bool {
	for fragment in fragments do if !handle_unsupported(writer, fragment.text, options.unsupported, diagnostics) do return false
	return writer_string(writer, "\n\n")
}

@(private)
handle_unsupported :: proc(writer: ^Native_Writer, text: string, policy: Unsupported_Policy, diagnostics: ^u32) -> bool {
	switch policy {
	case .Reject, .Invalid:
		return false
	case .Plain_Text_With_Warning:
		diagnostics^ += 1
		return writer_text(writer, text)
	case .Omit_With_Warning:
		diagnostics^ += 1
		return true
	}
	return false
}

@(private)
handle_html_unsupported :: proc(writer: ^Native_Writer, text: string, policy: Unsupported_Policy, diagnostics: ^u32) -> bool {
	switch policy {
	case .Reject, .Invalid:
		return false
	case .Plain_Text_With_Warning:
		diagnostics^ += 1
		return writer_html_escaped(writer, text, false)
	case .Omit_With_Warning:
		diagnostics^ += 1
		return true
	}
	return false
}

@(private)
writer_text :: proc(writer: ^Native_Writer, text: string) -> bool {
	if writer.encoding == .Utf_8 do return writer_string(writer, text)
	for value in text {
		if writer.encoding == .Ascii && value > 0x7f || writer.encoding == .Latin_1 && value > 0xff {
			if !writer.replace_unencodable {
				writer.unencodable = true
				return false
			}
			if !writer_byte(writer, '?') do return false
			continue
		}
		if !writer_byte(writer, u8(value)) do return false
	}
	return true
}

@(private)
writer_string :: proc(writer: ^Native_Writer, value: string) -> bool {
	if writer.count + len(value) > len(writer.bytes) {
		writer.limited = true
		return false
	}
	writer.count += copy(writer.bytes[writer.count:], value)
	return true
}

@(private)
writer_byte :: proc(writer: ^Native_Writer, value: u8) -> bool {
	if writer.count >= len(writer.bytes) {
		writer.limited = true
		return false
	}
	writer.bytes[writer.count] = value
	writer.count += 1
	return true
}

@(private)
writer_html_escaped :: proc(writer: ^Native_Writer, value: string, attribute: bool) -> bool {
	for byte in transmute([]u8)value {
		switch byte {
		case '&': if !writer_string(writer, "&amp;") do return false
		case '<': if !writer_string(writer, "&lt;") do return false
		case '>': if !writer_string(writer, "&gt;") do return false
		case '"':
			if attribute {if !writer_string(writer, "&quot;") do return false} else if !writer_byte(writer, byte) do return false
		case '\'':
			if attribute {if !writer_string(writer, "&#39;") do return false} else if !writer_byte(writer, byte) do return false
		case: if !writer_byte(writer, byte) do return false
		}
	}
	return true
}

@(private)
writer_markdown_escaped :: proc(writer: ^Native_Writer, value: string) -> bool {
	for byte in transmute([]u8)value {
		if byte == '\\' || byte == '*' || byte == '_' || byte == '[' || byte == ']' || byte == '`' {
			if !writer_byte(writer, '\\') do return false
		}
		if !writer_byte(writer, byte) do return false
	}
	return true
}

@(private)
writer_decimal :: proc(writer: ^Native_Writer, value: u64) -> bool {
	if value == 0 do return writer_byte(writer, '0')
	digits: [20]u8
	count := 0
	remaining := value
	for remaining > 0 {
		digits[count] = u8('0' + remaining % 10)
		remaining /= 10
		count += 1
	}
	for index := count - 1; index >= 0; index -= 1 do if !writer_byte(writer, digits[index]) do return false
	return true
}

@(private)
backend_failure :: proc(operation_id: Operation_ID, code: Failure_Code, field: Failure_Field) -> Failure {
	return {operation_id = operation_id, kind = .Export, code = code, field = field}
}
