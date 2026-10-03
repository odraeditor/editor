// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../editor"
import "base:runtime"

/* MAX_STRUCTURAL_NODES bounds named nodes visited by one structural query. */
MAX_STRUCTURAL_NODES :: 65_536
/* MAX_STRUCTURAL_DEPTH bounds named ancestor traversal by one query. */
MAX_STRUCTURAL_DEPTH :: 1_024
/* MAX_STRUCTURAL_INDENT_LINES bounds logical lines in one indentation plan. */
MAX_STRUCTURAL_INDENT_LINES :: 16_384
/* MAX_STRUCTURAL_PREPARED_BYTES bounds replacement text in one indentation plan. */
MAX_STRUCTURAL_PREPARED_BYTES :: 8 * MEBIBYTE
/* MAX_STRUCTURAL_NODE_KIND_BYTES bounds one copied grammar node-kind name. */
MAX_STRUCTURAL_NODE_KIND_BYTES :: 96
/* MAX_STRUCTURAL_INSPECTION_BYTES bounds one copied inspection result. */
MAX_STRUCTURAL_INSPECTION_BYTES :: 1 * MEBIBYTE
/* FACTORY_ODIN_INDENT_BYTES is one factory Odin indentation level. */
FACTORY_ODIN_INDENT_BYTES :: 4

/* Structural_Operation names one stable structural language operation. */
Structural_Operation :: enum u8 {
	Invalid,
	Forward,
	Backward,
	Up,
	Down,
	Select,
	Indent,
	Definition,
}

/* Structural_Node_Kind is one bounded copied grammar node-kind name. */
Structural_Node_Kind :: struct {
	bytes:  [MAX_STRUCTURAL_NODE_KIND_BYTES]u8,
	length: u16,
}

/* Structural_Scope identifies one exact retained analysis tree. */
Structural_Scope :: struct {
	buffer_id:            editor.Buffer_ID,
	source_revision:      editor.Revision,
	language:             Language_Identity,
	provider:             Provider_Handle,
	selection_generation: Selection_Generation,
	parser_generation:    Parser_Generation,
	tree_generation:      Tree_Generation,
}

/* Structural_Request is one exact point or ordered-region query. */
Structural_Request :: struct {
	operation:  Structural_Operation,
	scope:      Structural_Scope,
	point:      editor.Byte_Offset,
	start:      editor.Byte_Offset,
	end:        editor.Byte_Offset,
	has_region: bool,
}

/* Structural_Target is one copied named grammar node. */
Structural_Target :: struct {
	scope: Structural_Scope,
	start: editor.Byte_Offset,
	end:   editor.Byte_Offset,
	kind:  Structural_Node_Kind,
	depth: u16,
}

/* Structural_Usage reports bounded work performed by one structural query. */
Structural_Usage :: struct {
	visited_nodes:  u32,
	visited_depth:  u16,
	indent_lines:   u32,
	prepared_bytes: u64,
	temporary_bytes: u64,
}

/* Structural_Limits is the complete selected structural resource policy. */
Structural_Limits :: struct {
	nodes:            u32,
	depth:            u16,
	indent_lines:     u32,
	prepared_bytes:   u64,
	node_kind_bytes:  u16,
	diagnostic_bytes: u64,
	inspection_bytes: u64,
}

/* DEFAULT_STRUCTURAL_LIMITS is the measured factory structural policy. */
DEFAULT_STRUCTURAL_LIMITS :: Structural_Limits {
	nodes = MAX_STRUCTURAL_NODES,
	depth = MAX_STRUCTURAL_DEPTH,
	indent_lines = MAX_STRUCTURAL_INDENT_LINES,
	prepared_bytes = MAX_STRUCTURAL_PREPARED_BYTES,
	node_kind_bytes = MAX_STRUCTURAL_NODE_KIND_BYTES,
	diagnostic_bytes = MAX_DIAGNOSTIC_BYTES,
	inspection_bytes = MAX_STRUCTURAL_INSPECTION_BYTES,
}

/* Structural_Indent_Edit replaces one line's leading horizontal whitespace. */
Structural_Indent_Edit :: struct {
	start:        editor.Byte_Offset,
	end:          editor.Byte_Offset,
	indent_level: u16,
	indent_bytes: u32,
}

/* Structural_Indentation_Plan owns copied edits for one exact analysis scope. */
Structural_Indentation_Plan :: struct {
	scope:     Structural_Scope,
	start:     editor.Byte_Offset,
	end:       editor.Byte_Offset,
	edits:     [dynamic]Structural_Indent_Edit,
	usage:     Structural_Usage,
	allocator: runtime.Allocator,
}

/* Structural_Inspection is copied state and never triggers analysis. */
Structural_Inspection :: struct {
	scope:             Structural_Scope,
	available:         bool,
	grammar_rules:     Structural_Node_Kind,
	point:             editor.Byte_Offset,
	start:             editor.Byte_Offset,
	end:               editor.Byte_Offset,
	has_region:        bool,
	last_target:       Structural_Target,
	last_operation:    Structural_Operation,
	usage:             Structural_Usage,
	limits:            Structural_Limits,
	latest_failure:    Failure,
}

/* structural_scope_is_valid checks one complete nonzero exact-tree identity. */
structural_scope_is_valid :: proc(scope: Structural_Scope) -> bool {
	return scope.buffer_id != editor.Buffer_ID(0) &&
		scope.language.id != Language_ID(0) &&
		scope.language.generation != Language_Generation(0) &&
		scope.provider.provider_id != Provider_ID(0) &&
		scope.provider.provider_generation != Provider_Generation(0) &&
		scope.selection_generation != Selection_Generation(0) &&
		scope.parser_generation != Parser_Generation(0) &&
		scope.tree_generation != Tree_Generation(0)
}

/* structural_request_is_valid checks operation, scope, and ordered positions. */
structural_request_is_valid :: proc(request: Structural_Request, source_bytes: u64) -> bool {
	if request.operation <= .Invalid || request.operation > .Definition ||
	   !structural_scope_is_valid(request.scope) || u64(request.point) > source_bytes {
		return false
	}
	if !request.has_region do return request.start == request.point && request.end == request.point
	return request.start <= request.end && u64(request.end) <= source_bytes
}

/* structural_target_is_valid checks copied kind and exact non-empty range. */
structural_target_is_valid :: proc(target: Structural_Target, source_bytes: u64) -> bool {
	return structural_scope_is_valid(target.scope) && target.kind.length > 0 &&
		target.kind.length <= MAX_STRUCTURAL_NODE_KIND_BYTES && target.start < target.end &&
		u64(target.end) <= source_bytes && target.depth <= MAX_STRUCTURAL_DEPTH
}

/* structural_limits_are_valid checks selected nonzero subordinate ceilings. */
structural_limits_are_valid :: proc(limits: Structural_Limits) -> bool {
	return limits.nodes > 0 && limits.nodes <= MAX_STRUCTURAL_NODES &&
		limits.depth > 0 && limits.depth <= MAX_STRUCTURAL_DEPTH &&
		limits.indent_lines > 0 && limits.indent_lines <= MAX_STRUCTURAL_INDENT_LINES &&
		limits.prepared_bytes > 0 && limits.prepared_bytes <= MAX_STRUCTURAL_PREPARED_BYTES &&
		limits.node_kind_bytes > 0 && limits.node_kind_bytes <= MAX_STRUCTURAL_NODE_KIND_BYTES &&
		limits.diagnostic_bytes > 0 && limits.diagnostic_bytes <= MAX_DIAGNOSTIC_BYTES &&
		limits.inspection_bytes > 0 && limits.inspection_bytes <= MAX_STRUCTURAL_INSPECTION_BYTES
}

/* structural_indentation_plan_close releases copied edits exactly once. */
structural_indentation_plan_close :: proc(plan: ^Structural_Indentation_Plan) {
	if plan == nil do return
	if plan.edits != nil do delete(plan.edits)
	plan^ = {}
}
