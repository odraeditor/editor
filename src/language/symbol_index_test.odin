// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../document"
import "../editor"
import "core:strings"
import "core:testing"

@(private)
Symbol_Index_Test_Fixture :: struct {
	buffer:   editor.Buffer,
	snapshot: editor.Buffer_Snapshot,
	owner:    Tree_Sitter_Owner,
	scope:    Symbol_Query_Scope,
	ready:    bool,
}

@(private)
symbol_index_test_open :: proc(
	fixture: ^Symbol_Index_Test_Fixture,
	contents: string,
) -> bool {
	fixture^ = {}
	initialized, _ := editor.buffer_init(
		&fixture.buffer,
		801,
		contents,
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	if !initialized do return false
	opened, _ := editor.buffer_snapshot_open(&fixture.buffer, &fixture.snapshot)
	if !opened {
		editor.buffer_close(&fixture.buffer)
		return false
	}
	owner_ready, _ := tree_sitter_owner_init(&fixture.owner, 3)
	if !owner_ready {
		editor.buffer_snapshot_close(&fixture.snapshot)
		editor.buffer_close(&fixture.buffer)
		return false
	}
	query_ready, _ := tree_sitter_owner_compile_odin_query(&fixture.owner, 5)
	language, provider := tree_sitter_test_identity()
	language.name.length = u16(copy(language.name.bytes[:], "odin"))
	parsed, parse_ok, _ := tree_sitter_owner_parse_snapshot(
		&fixture.owner,
		&fixture.snapshot,
		language,
		provider,
		7,
		11,
	)
	if !query_ready || !parse_ok {
		tree_sitter_owner_close(&fixture.owner)
		editor.buffer_snapshot_close(&fixture.snapshot)
		editor.buffer_close(&fixture.buffer)
		return false
	}
	fixture.scope = Symbol_Query_Scope {
		kind = .Active_Buffer,
		buffer_id = parsed.buffer_id,
		document_id = 19,
		has_document = true,
		source_revision = parsed.source_revision,
		language = parsed.language,
		provider = parsed.provider,
		selection_generation = parsed.selection_generation,
		request_generation = 13,
	}
	fixture.ready = true
	return true
}

@(private)
symbol_index_test_close :: proc(fixture: ^Symbol_Index_Test_Fixture) {
	if fixture == nil || !fixture.ready do return
	tree_sitter_owner_close(&fixture.owner)
	editor.buffer_snapshot_close(&fixture.snapshot)
	editor.buffer_close(&fixture.buffer)
	fixture^ = {}
}

@(private)
symbol_name_string :: proc(name: ^Symbol_Name) -> string {
	return string(name.bytes[:name.length])
}

/* Verifies maintained Odin extraction preserves source order and hierarchy. */
@(test)
odin_symbol_index_is_ordered_and_hierarchical :: proc(t: ^testing.T) {
	contents := "package demo\nThing :: struct { field: int }\nrun :: proc() { local := 1 }\n"
	fixture: Symbol_Index_Test_Fixture
	ready := symbol_index_test_open(&fixture, contents)
	testing.expect(t, ready)
	if !ready do return
	defer symbol_index_test_close(&fixture)
	index, indexed, failure := tree_sitter_owner_symbol_index(
		&fixture.owner,
		&fixture.snapshot,
		fixture.scope,
		17,
	)
	testing.expectf(t, indexed, "symbol indexing failed with %v", failure.code)
	if !indexed do return
	defer symbol_index_close(&index)
	view, viewed, _ := symbol_index_view(&index)
	testing.expect(t, viewed && view.symbols >= 3)

	previous_start := editor.Byte_Offset(0)
	seen_type := false
	seen_function := false
	seen_local := false
	for ordinal in 0 ..< view.symbols {
		descriptor, inspected, _ := symbol_index_descriptor(&index, ordinal)
		testing.expect(t, inspected)
		if !inspected do continue
		testing.expect(t, descriptor.location.start >= previous_start)
		previous_start = descriptor.location.start
		name := symbol_name_string(&descriptor.name)
		seen_type = seen_type || name == "Thing" && descriptor.kind == .Struct
		seen_function = seen_function || name == "run" && descriptor.kind == .Function
		seen_local = seen_local || name == "local" && descriptor.kind == .Variable &&
			descriptor.parent_id != Symbol_ID(0)
	}
	testing.expectf(
		t,
		seen_type && seen_function && seen_local,
		"missing extracted symbols: type=%v function=%v local=%v",
		seen_type,
		seen_function,
		seen_local,
	)
}

/* Verifies stale scope and cancellation reject without publishing an index. */
@(test)
symbol_index_rejects_stale_queries :: proc(t: ^testing.T) {
	fixture: Symbol_Index_Test_Fixture
	ready := symbol_index_test_open(&fixture, "package demo\nrun :: proc() {}\n")
	testing.expect(t, ready)
	if !ready do return
	defer symbol_index_test_close(&fixture)

	stale := fixture.scope
	stale.source_revision += 1
	_, stale_ok, stale_failure := tree_sitter_owner_symbol_index(
		&fixture.owner,
		&fixture.snapshot,
		stale,
		17,
	)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Selection)

	cancelled, _ := tree_sitter_owner_request_cancel(&fixture.owner)
	_, cancel_ok, cancel_failure := tree_sitter_owner_symbol_index(
		&fixture.owner,
		&fixture.snapshot,
		fixture.scope,
		17,
	)
	testing.expect(t, cancelled && !cancel_ok)
	testing.expect_value(t, cancel_failure.code, Failure_Code.Cancelled)
	tree_sitter_owner_clear_cancel(&fixture.owner)
}

/* Verifies syntax-tree resolution returns the exact current identifier at point. */
@(test)
odin_symbol_at_point_uses_current_tree_evidence :: proc(t: ^testing.T) {
	contents := "package demo\nrun :: proc() { run() }\n"
	fixture: Symbol_Index_Test_Fixture
	ready := symbol_index_test_open(&fixture, contents)
	testing.expect(t, ready)
	if !ready do return
	defer symbol_index_test_close(&fixture)
	call_offset := strings.last_index(contents, "run")
	symbol, resolved, failure := tree_sitter_owner_symbol_at_point(
		&fixture.owner,
		&fixture.snapshot,
		fixture.scope,
		editor.Byte_Offset(call_offset + 1),
	)
	testing.expectf(t, resolved, "tree symbol resolution failed with %v", failure.code)
	if resolved {
		testing.expect_value(t, symbol_name_string(&symbol.name), "run")
		testing.expect_value(t, symbol.location.start, editor.Byte_Offset(call_offset))
	}
}

/* Verifies the generic fallback resolves adjacent Unicode symbols exactly. */
@(test)
generic_symbol_resolution_is_unicode_safe :: proc(t: ^testing.T) {
	contents := "plain  żółw_name text"
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		802,
		contents,
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer editor.buffer_close(&buffer)
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(&buffer, &snapshot)
	testing.expect(t, opened)
	if !opened do return
	defer editor.buffer_snapshot_close(&snapshot)
	point := strings.index(contents, "name") + len("name")
	symbol, resolved, failure := generic_symbol_at_point(
		&snapshot,
		document.Document_ID(23),
		true,
		editor.Byte_Offset(point),
	)
	testing.expectf(t, resolved, "generic resolution failed with %v", failure.code)
	if resolved {
		testing.expect_value(t, symbol_name_string(&symbol.name), "żółw_name")
		testing.expect_value(t, symbol.location.start, editor.Byte_Offset(strings.index(contents, "ż")))
	}
	_, absent, absent_failure := generic_symbol_at_point(
		&snapshot,
		document.Document_ID(23),
		true,
		editor.Byte_Offset(len("plain ")),
	)
	testing.expect(t, !absent)
	testing.expect_value(t, absent_failure.code, Failure_Code.No_Symbol)
}

/* Verifies the generic navigator index retains ordered Unicode tokens without syntax state. */
@(test)
generic_symbol_index_is_bounded :: proc(t: ^testing.T) {
	contents := "alpha żółw_name alpha"
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(&buffer, 803, contents, {
		persistent = context.allocator, temporary = context.temp_allocator})
	testing.expect(t, initialized)
	if !initialized do return
	defer editor.buffer_close(&buffer)
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(&buffer, &snapshot)
	testing.expect(t, opened)
	if !opened do return
	defer editor.buffer_snapshot_close(&snapshot)
	limits := DEFAULT_SYMBOL_LIMITS
	limits.symbols = 2
	index, indexed, failure := generic_symbol_index(
		&snapshot, 0, false, 4, 5, limits, context.allocator)
	testing.expectf(t, indexed, "generic index failed with %v", failure.code)
	if !indexed do return
	defer symbol_index_close(&index)
	view, viewed, _ := symbol_index_view(&index)
	testing.expect(t, viewed)
	testing.expect_value(t, view.symbols, u32(2))
	testing.expect_value(t, view.descriptor.completeness, Symbol_Completeness.Incomplete)
	second, described, _ := symbol_index_descriptor(&index, 1)
	testing.expect(t, described)
	testing.expect_value(t, symbol_name_string(&second.name), "żółw_name")
	testing.expect_value(t, second.provider.provider_id, GENERIC_SYMBOL_PROVIDER_ID)
}

/* Verifies dense indexes stop at declared count and publish incompleteness. */
@(test)
odin_symbol_index_is_truthful_when_dense :: proc(t: ^testing.T) {
	contents := "package demo\na :: 1\nb :: 2\nc :: 3\n"
	fixture: Symbol_Index_Test_Fixture
	ready := symbol_index_test_open(&fixture, contents)
	testing.expect(t, ready)
	if !ready do return
	defer symbol_index_test_close(&fixture)
	limits := DEFAULT_SYMBOL_LIMITS
	limits.symbols = 2
	index, indexed, _ := tree_sitter_owner_symbol_index(
		&fixture.owner,
		&fixture.snapshot,
		fixture.scope,
		17,
		limits,
	)
	testing.expect(t, indexed)
	if !indexed do return
	defer symbol_index_close(&index)
	view, _, _ := symbol_index_view(&index)
	testing.expect_value(t, view.symbols, u32(2))
	testing.expect_value(t, view.descriptor.completeness, Symbol_Completeness.Incomplete)
}
