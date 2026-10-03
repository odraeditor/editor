// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package search

import "../editor"
import "base:runtime"
import "core:mem"
import "core:testing"

/* Verifies literal templates preserve every admitted byte when adaptation is disabled. */
@(test)
literal_replacement_expands_exact_text :: proc(t: ^testing.T) {
	persistent_tracking: mem.Tracking_Allocator
	temporary_tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&persistent_tracking, context.allocator)
	mem.tracking_allocator_init(&temporary_tracking, context.allocator)
	persistent := mem.tracking_allocator(&persistent_tracking)
	temporary := mem.tracking_allocator(&temporary_tracking)
	buffer, snapshot, opened := open_replacement_snapshot(t, 501, "ODRA")
	if !opened {
		mem.tracking_allocator_destroy(&temporary_tracking)
		mem.tracking_allocator_destroy(&persistent_tracking)
		return
	}
	query := make_replacement_query(t, 501, .Literal, "odra", persistent, temporary)
	template := make_replacement_template(
		t,
		&query,
		"river \\1 \\\\",
		Replacement_Policy{case_preservation = .None},
		persistent,
	)
	expansion: Replacement_Expansion
	expanded, failure := replacement_expand(
		&expansion,
		&snapshot,
		&template,
		Occurrence{buffer_id = 501, revision = 0, start = 0, end = 4},
		nil,
		Allocator_Set{persistent = persistent, temporary = temporary},
	)
	testing.expectf(t, expanded, "literal expansion failed with %v", failure)
	if expanded {
		view, viewed, _ := replacement_expansion_view(&expansion)
		testing.expect(t, viewed)
		testing.expect_value(t, view.text, "river \\1 \\\\")
		testing.expect(t, !view.adapted)
		testing.expect_value(t, view.usage.expanded_bytes, u64(11))
		replacement_expansion_close(&expansion)
	}
	replacement_template_close(&template)
	query_close(&query)
	editor.buffer_snapshot_close(&snapshot)
	editor.buffer_close(&buffer)
	testing.expect_value(t, temporary_tracking.current_memory_allocated, i64(0))
	testing.expect_value(t, persistent_tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&temporary_tracking)
	mem.tracking_allocator_destroy(&persistent_tracking)
}

/* Verifies regexp escapes, whole matches, and absent optional groups remain distinct. */
@(test)
regexp_replacement_expands_captures :: proc(t: ^testing.T) {
	buffer, snapshot, opened := open_replacement_snapshot(t, 503, "odra")
	if !opened {
		return
	}
	defer editor.buffer_snapshot_close(&snapshot)
	defer editor.buffer_close(&buffer)
	query := make_replacement_query(
		t,
		503,
		.Regular_Expression,
		"(odra)(-(river))?",
		context.allocator,
		context.temp_allocator,
	)
	defer query_close(&query)
	template := make_replacement_template(
		t,
		&query,
		"\\1|\\2|\\3|\\&|\\\\",
		Replacement_Policy{case_preservation = .None},
		context.allocator,
	)
	defer replacement_template_close(&template)
	captures := [2]Capture {
		{group = 0, start = 0, end = 4},
		{group = 1, start = 0, end = 4},
	}
	occurrence := Occurrence {
		buffer_id = 503,
		revision = 0,
		start = 0,
		end = 4,
		capture_count = 2,
	}
	expansion: Replacement_Expansion
	expanded, failure := replacement_expand(
		&expansion,
		&snapshot,
		&template,
		occurrence,
		captures[:],
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, expanded, "regexp expansion failed with %v", failure)
	if !expanded {
		return
	}
	defer replacement_expansion_close(&expansion)
	view, viewed, _ := replacement_expansion_view(&expansion)
	testing.expect(t, viewed)
	testing.expect_value(t, view.text, "odra|||odra|\\")
	testing.expect_value(t, view.usage.source_bytes, u64(11))
	testing.expect_value(t, view.usage.expanded_bytes, u64(13))
}

/* Verifies smart replacement case follows Unicode uppercase and capitalized matches. */
@(test)
smart_case_adapts_unicode_match_shapes :: proc(t: ^testing.T) {
	contents := "RZEKA Rzeka rzeka ŻÓŁĆ"
	buffer, snapshot, opened := open_replacement_snapshot(t, 505, contents)
	if !opened {
		return
	}
	defer editor.buffer_snapshot_close(&snapshot)
	defer editor.buffer_close(&buffer)
	query := make_replacement_query(t, 505, .Literal, "rzeka", context.allocator, context.temp_allocator)
	defer query_close(&query)
	template := make_replacement_template(
		t,
		&query,
		"rzeka",
		DEFAULT_REPLACEMENT_POLICY,
		context.allocator,
	)
	defer replacement_template_close(&template)
	cases := [?]struct {
		name:     string,
		start:    editor.Byte_Offset,
		end:      editor.Byte_Offset,
		expected: string,
	} {
		{"upper-source", 0, 5, "RZEKA"},
		{"title-source", 6, 11, "Rzeka"},
		{"lower-source", 12, 17, "rzeka"},
		{"unicode-title-source", 18, 26, "RZEKA"},
	}
	for test_case in cases {
		expansion: Replacement_Expansion
		expanded, failure := replacement_expand(
			&expansion,
			&snapshot,
			&template,
			Occurrence{buffer_id = 505, revision = 0, start = test_case.start, end = test_case.end},
			nil,
			Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
		)
		testing.expectf(t, expanded, "%s expansion failed with %v", test_case.name, failure)
		if expanded {
			view, viewed, _ := replacement_expansion_view(&expansion)
			testing.expectf(t, viewed, "%s expansion could not be viewed", test_case.name)
			testing.expectf(t, view.text == test_case.expected, "%s expansion returned the wrong text", test_case.name)
			replacement_expansion_close(&expansion)
		}
	}
	explicit := make_replacement_template(
		t,
		&query,
		"River",
		DEFAULT_REPLACEMENT_POLICY,
		context.allocator,
	)
	defer replacement_template_close(&explicit)
	expansion: Replacement_Expansion
	expanded, failure := replacement_expand(
		&expansion,
		&snapshot,
		&explicit,
		Occurrence{buffer_id = 505, revision = 0, start = 0, end = 5},
		nil,
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, expanded, "explicit-case expansion failed with %v", failure)
	if expanded {
		view, viewed, _ := replacement_expansion_view(&expansion)
		testing.expect(t, viewed)
		testing.expect_value(t, view.text, "River")
		testing.expect(t, !view.adapted)
		replacement_expansion_close(&expansion)
	}
}

/* Verifies malformed input, undefined captures, bounds, and stale matches fail privately. */
@(test)
templates_reject_invalid_input_before_expansion :: proc(t: ^testing.T) {
	query := make_replacement_query(
		t,
		507,
		.Regular_Expression,
		"(odra)",
		context.allocator,
		context.temp_allocator,
	)
	if query.state == nil {
		return
	}
	defer query_close(&query)
	cases := [?]struct {
		name:     string,
		text:     string,
		expected: Failure_Code,
	} {
		{"trailing-escape", "\\", .Malformed_Replacement_Template},
		{"whole-match-reference", "\\0", .Malformed_Replacement_Template},
		{"missing-capture", "\\2", .Capture_Reference},
		{"unknown-escape", "\\x", .Malformed_Replacement_Template},
		{"capture-overflow", "\\999999999999999999999999", .Arithmetic_Overflow},
	}
	for test_case in cases {
		template: Replacement_Template
		initialized, failure := replacement_template_init(
			&template,
			&query,
			Replacement_Template_Config {
				text = test_case.text,
				policy = DEFAULT_REPLACEMENT_POLICY,
				limits = DEFAULT_REPLACEMENT_LIMITS,
				allocator = context.allocator,
			},
		)
		testing.expectf(t, !initialized, "%s template unexpectedly initialized", test_case.name)
		testing.expectf(t, failure.code == test_case.expected, "%s template returned the wrong failure", test_case.name)
		testing.expectf(t, template.state == nil, "%s template retained state", test_case.name)
	}
	invalid_utf8 := [1]byte{0xff}
	template: Replacement_Template
	initialized, failure := replacement_template_init(
		&template,
		&query,
		Replacement_Template_Config {
			text = string(invalid_utf8[:]),
			policy = DEFAULT_REPLACEMENT_POLICY,
			limits = DEFAULT_REPLACEMENT_LIMITS,
			allocator = context.allocator,
		},
	)
	testing.expect(t, !initialized)
	testing.expect_value(t, failure.code, Failure_Code.Malformed_UTF8)
}

/* Verifies expansion ceilings and revision identity are checked before ownership. */
@(test)
expansion_rejects_oversize_and_stale_occurrences :: proc(t: ^testing.T) {
	buffer, snapshot, opened := open_replacement_snapshot(t, 509, "odra")
	if !opened {
		return
	}
	defer editor.buffer_snapshot_close(&snapshot)
	defer editor.buffer_close(&buffer)
	query := make_replacement_query(t, 509, .Literal, "odra", context.allocator, context.temp_allocator)
	defer query_close(&query)
	large: [MIN_EXPANDED_REPLACEMENT_BYTES + 1]byte
	for &byte_value in large {
		byte_value = 'x'
	}
	template: Replacement_Template
	initialized, init_failure := replacement_template_init(
		&template,
		&query,
		Replacement_Template_Config {
			text = string(large[:]),
			policy = Replacement_Policy{case_preservation = .None},
			limits = Replacement_Limits {
				template_bytes = u64(len(large)),
				expanded_bytes = MIN_EXPANDED_REPLACEMENT_BYTES,
				temporary_bytes = DEFAULT_MATCH_SPAN_BYTES,
			},
			allocator = context.allocator,
		},
	)
	testing.expectf(t, initialized, "bounded template failed with %v", init_failure)
	if !initialized {
		return
	}
	defer replacement_template_close(&template)
	expansion: Replacement_Expansion
	expanded, failure := replacement_expand(
		&expansion,
		&snapshot,
		&template,
		Occurrence{buffer_id = 509, revision = 0, start = 0, end = 4},
		nil,
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, !expanded)
	testing.expect_value(t, failure.code, Failure_Code.Expansion_Limit)
	testing.expect(t, expansion.state == nil)
	expanded, failure = replacement_expand(
		&expansion,
		&snapshot,
		&template,
		Occurrence{buffer_id = 509, revision = 1, start = 0, end = 4},
		nil,
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, !expanded)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Revision)
	testing.expect(t, expansion.state == nil)
}

@(private)
make_replacement_query :: proc(
	t: ^testing.T,
	id: Query_ID,
	kind: Pattern_Kind,
	pattern: string,
	persistent, temporary: runtime.Allocator,
) -> Query {
	query: Query
	initialized, failure := query_init(
		&query,
		Query_Config {
			id = id,
			kind = kind,
			pattern = pattern,
			policy = DEFAULT_POLICY,
			limits = DEFAULT_LIMITS,
			allocator = persistent,
			temporary_allocator = temporary,
		},
	)
	testing.expectf(t, initialized, "replacement query failed with %v", failure)
	return query
}

@(private)
make_replacement_template :: proc(
	t: ^testing.T,
	query: ^Query,
	text: string,
	policy: Replacement_Policy,
	allocator: runtime.Allocator,
) -> Replacement_Template {
	template: Replacement_Template
	initialized, failure := replacement_template_init(
		&template,
		query,
		Replacement_Template_Config {
			text = text,
			policy = policy,
			limits = DEFAULT_REPLACEMENT_LIMITS,
			allocator = allocator,
		},
	)
	testing.expectf(t, initialized, "replacement template failed with %v", failure)
	return template
}

@(private)
open_replacement_snapshot :: proc(
	t: ^testing.T,
	buffer_id: editor.Buffer_ID,
	contents: string,
) -> (buffer: editor.Buffer, snapshot: editor.Buffer_Snapshot, ok: bool) {
	initialized, init_failure := editor.buffer_init(
		&buffer,
		buffer_id,
		contents,
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, initialized, "replacement buffer failed with %v", init_failure)
	if !initialized {
		return {}, {}, false
	}
	opened, open_failure := editor.buffer_snapshot_open(&buffer, &snapshot)
	testing.expectf(t, opened, "replacement snapshot failed with %v", open_failure)
	if !opened {
		editor.buffer_close(&buffer)
		return {}, {}, false
	}
	return buffer, snapshot, true
}
