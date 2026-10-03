// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package structural_syntax_equivalence

import editor "../../src/editor"
import language "../../src/language"
import reference "../structural_syntax_reference"
import "core:testing"

/* Verifies generated production containment and expansion match an independent tree oracle. */
@(test)
structural_selection_matches_model :: proc(t: ^testing.T) {
	line := "value :: 1\n"
	line_bytes := len(line)
	declaration_bytes := line_bytes - 1
	declarations := 128
	contents, allocation_error := make([dynamic]u8, 0, line_bytes * declarations)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	defer delete(contents)
	for _ in 0 ..< declarations {
		_, append_error := append(&contents, ..transmute([]u8)(string(line)))
		testing.expect(t, append_error == nil)
		if append_error != nil do return
	}

	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		701,
		string(contents[:]),
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
	owner: language.Tree_Sitter_Owner
	owner_ready, _ := language.tree_sitter_owner_init(&owner, 1)
	testing.expect(t, owner_ready)
	if !owner_ready do return
	defer language.tree_sitter_owner_close(&owner)
	query_ready, _ := language.tree_sitter_owner_compile_odin_query(&owner, 1)
	identity := language.Language_Identity{id = 1, generation = 1}
	provider := language.Provider_Handle {
		registry_id = 1,
		language_id = 1,
		provider_id = 1,
		provider_generation = 1,
	}
	parsed, parse_ok, _ := language.tree_sitter_owner_parse_snapshot(
		&owner,
		&snapshot,
		identity,
		provider,
		1,
		1,
	)
	testing.expect(t, query_ready && parse_ok)
	if !query_ready || !parse_ok do return
	scope := language.Structural_Scope {
		buffer_id = parsed.buffer_id,
		source_revision = parsed.source_revision,
		language = parsed.language,
		provider = parsed.provider,
		selection_generation = parsed.selection_generation,
		parser_generation = parsed.parser_generation,
		tree_generation = parsed.tree_generation,
	}

	nodes := make([]reference.Node, 1 + declarations * 2)
	defer delete(nodes)
	nodes[0] = reference.Node {
		start = 0,
		end = u32(len(contents)),
		parent = reference.INVALID_INDEX,
		first_child = 1,
		next_sibling = reference.INVALID_INDEX,
		named = true,
	}
	for index in 0 ..< declarations {
		declaration_index := 1 + index * 2
		identifier_index := declaration_index + 1
		start := index * line_bytes
		next := reference.INVALID_INDEX
		if index + 1 < declarations do next = u32(declaration_index + 2)
		nodes[declaration_index] = reference.Node {
			start = u32(start),
			end = u32(start + declaration_bytes),
			parent = 0,
			first_child = u32(identifier_index),
			next_sibling = next,
			named = true,
		}
		nodes[identifier_index] = reference.Node {
			start = u32(start),
			end = u32(start + len("value")),
			parent = u32(declaration_index),
			first_child = reference.INVALID_INDEX,
			next_sibling = reference.INVALID_INDEX,
			named = true,
		}
	}

	for index in 0 ..< declarations {
		point := index * line_bytes + 2
		reference_target, _, reference_ok, _ := reference.query(
			nodes,
			reference.Request{operation = .Containing, start = u32(point), end = u32(point)},
		)
		request := language.Structural_Request {
			operation = .Select,
			scope = scope,
			point = editor.Byte_Offset(point),
			start = editor.Byte_Offset(point),
			end = editor.Byte_Offset(point),
		}
		production_target, _, production_ok, _ := language.tree_sitter_owner_query_structure(
			&owner,
			&snapshot,
			request,
		)
		testing.expect(t, reference_ok && production_ok)
		if !reference_ok || !production_ok do continue
		testing.expect_value(t, production_target.start, editor.Byte_Offset(reference_target.start))
		testing.expect_value(t, production_target.end, editor.Byte_Offset(reference_target.end))

		reference_parent, _, reference_parent_ok, _ := reference.query(
			nodes,
			reference.Request{operation = .Expand, start = reference_target.start, end = reference_target.end},
		)
		request.has_region = true
		request.start = production_target.start
		request.end = production_target.end
		production_parent, _, production_parent_ok, _ := language.tree_sitter_owner_query_structure(
			&owner,
			&snapshot,
			request,
		)
		testing.expect(t, reference_parent_ok && production_parent_ok)
		if reference_parent_ok && production_parent_ok {
			testing.expect_value(t, production_parent.start, editor.Byte_Offset(reference_parent.start))
			testing.expect_value(t, production_parent.end, editor.Byte_Offset(reference_parent.end))
		}
	}
}
