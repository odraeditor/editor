// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_output

import "core:strings"
import "core:testing"

/* Verifies all native backends render one deterministic normalized document. */
@(test)
native_backends_render_deterministic_candidates :: proc(t: ^testing.T) {
	fragments, blocks := native_backend_test_values()
	document := Native_Document {title = "Native Backends", language = "en", blocks = blocks[:], fragments = fragments[:]}
	destination: [8_192]u8
	options := Native_Backend_Options {encoding = .Utf_8, unsupported = .Reject}
	plain, ok, _ := render_native_backend(1, .Plain_Text, document, options, destination[:])
	testing.expect(t, ok)
	plain_text := string(destination[:int(plain.byte_count)])
	testing.expect(t, strings.contains(plain_text, "Overview & status\n================="))
	testing.expect(t, strings.contains(plain_text, "Odra <https://example.test/?a=1&b=2>"))

	options.full_document = true
	html, html_ok, _ := render_native_backend(2, .Html, document, options, destination[:])
	testing.expect(t, html_ok)
	html_text := string(destination[:int(html.byte_count)])
	testing.expect(t, strings.has_prefix(html_text, "<!doctype html>\n<html lang=\"en\">"))
	testing.expect(t, strings.contains(html_text, "<h1>Overview &amp; status</h1>"))
	testing.expect(t, strings.contains(html_text, "?a=1&amp;b=2"))
	testing.expect(t, strings.has_suffix(html_text, "</body>\n</html>\n"))

	markdown, markdown_ok, _ := render_native_backend(3, .Markdown, document, options, destination[:])
	testing.expect(t, markdown_ok)
	markdown_text := string(destination[:int(markdown.byte_count)])
	testing.expect(t, strings.contains(markdown_text, "**carefully**"))
	testing.expect(t, strings.contains(markdown_text, "![Diagram](media/diagram.png)"))

	jan, jan_ok, _ := render_native_backend(4, .Normalized_Jan, document, options, destination[:])
	testing.expect(t, jan_ok)
	jan_text := string(destination[:int(jan.byte_count)])
	testing.expect(t, strings.has_prefix(jan_text, "#+title: Native Backends\n\n"))
	testing.expect(t, strings.contains(jan_text, "[[https://example.test/?a=1&b=2][Odra]]"))
	testing.expect(t, strings.contains(jan_text, "#+begin_src racket\n(+ 1 2)\n#+end_src"))

}

/* Verifies HTML escapes content and raw input needs explicit policy. */
@(test)
native_html_is_safe_by_default :: proc(t: ^testing.T) {
	fragments := []Native_Fragment {{kind = .Raw, text = "<script>alert(1)</script>"}}
	blocks := []Native_Block {{kind = .Raw, fragment_count = 1}}
	document := Native_Document {title = "Unsafe", language = "en", blocks = blocks, fragments = fragments}
	destination: [512]u8
	options := Native_Backend_Options {unsupported = .Reject}
	_, ok, failure := render_native_backend(5, .Html, document, options, destination[:])
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Unsupported)
	options.unsupported = .Plain_Text_With_Warning
	result, fallback_ok, _ := render_native_backend(6, .Html, document, options, destination[:])
	testing.expect(t, fallback_ok)
	testing.expect_value(t, result.diagnostic_count, u32(1))
	testing.expect(t, strings.contains(string(destination[:int(result.byte_count)]), "&lt;script&gt;"))
	options.allow_raw = true
	result, fallback_ok, _ = render_native_backend(7, .Html, document, options, destination[:])
	testing.expect(t, fallback_ok)
	testing.expect(t, strings.contains(string(destination[:int(result.byte_count)]), "<script>"))
}

/* Verifies plain text rejects or explicitly replaces unencodable characters. */
@(test)
native_plain_text_encoding_is_explicit :: proc(t: ^testing.T) {
	fragments := []Native_Fragment {{kind = .Text, text = "Zażółć"}}
	blocks := []Native_Block {{kind = .Paragraph, fragment_count = 1}}
	document := Native_Document {language = "pl", blocks = blocks, fragments = fragments}
	destination: [512]u8
	options := Native_Backend_Options {encoding = .Ascii, unsupported = .Reject}
	_, ok, failure := render_native_backend(8, .Plain_Text, document, options, destination[:])
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Validation)
	options.replace_unencodable = true
	result, replacement_ok, _ := render_native_backend(9, .Plain_Text, document, options, destination[:])
	testing.expect(t, replacement_ok)
	testing.expect(t, strings.contains(string(destination[:int(result.byte_count)]), "Za????"))
}

/* Verifies output bounds and stable inspection remain explicit. */
@(test)
native_backends_are_bounded_and_inspectable :: proc(t: ^testing.T) {
	fragments, blocks := native_backend_test_values()
	document := Native_Document {title = "Native Backends", language = "en", blocks = blocks[:], fragments = fragments[:]}
	destination: [16]u8
	options := Native_Backend_Options {encoding = .Utf_8, unsupported = .Reject}
	_, ok, failure := render_native_backend(10, .Plain_Text, document, options, destination[:])
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Limited)
	records := native_backend_inspection()
	testing.expect_value(t, len(records), 4)
	for record, index in records {
		testing.expect_value(t, record.state, Availability_State.Available)
		testing.expect(t, record.raw_requires_policy)
		for prior in records[:index] do testing.expect(t, prior.backend != record.backend)
	}
}

@(private = "file")
native_backend_test_values :: proc() -> ([8]Native_Fragment, [4]Native_Block) {
	fragments := [8]Native_Fragment {
		{kind = .Text, text = "Overview & status"},
		{kind = .Text, text = "Read "},
		{kind = .Strong, text = "carefully"},
		{kind = .Text, text = " and visit "},
		{kind = .Link, text = "Odra", target = "https://example.test/?a=1&b=2"},
		{kind = .Text, text = "."},
		{kind = .Text, text = "(+ 1 2)"},
		{kind = .Image, text = "Diagram", target = "media/diagram.png"},
	}
	blocks := [4]Native_Block {
		{kind = .Heading, level = 1, fragment_start = 0, fragment_count = 1},
		{kind = .Paragraph, fragment_start = 1, fragment_count = 5},
		{kind = .Source, fragment_start = 6, fragment_count = 1, language = "racket"},
		{kind = .Paragraph, fragment_start = 7, fragment_count = 1},
	}
	return fragments, blocks
}
