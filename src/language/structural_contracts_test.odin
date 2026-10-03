// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../editor"
import "core:testing"

@(private)
structural_test_scope :: proc() -> Structural_Scope {
	return Structural_Scope {
		buffer_id = 41,
		source_revision = 7,
		language = Language_Identity{id = 1, generation = 1},
		provider = Provider_Handle{registry_id = 1, language_id = 1, provider_id = 1, provider_generation = 1},
		selection_generation = 2,
		parser_generation = 3,
		tree_generation = 4,
	}
}

@(test)
/* Verifies structural records retain exact bounded copied identities. */
structural_records_are_bounded :: proc(t: ^testing.T) {
	scope := structural_test_scope()
	request := Structural_Request {
		operation = .Forward,
		scope = scope,
		point = 8,
		start = 8,
		end = 8,
	}
	kind := Structural_Node_Kind{length = 10}
	copy(kind.bytes[:], "identifier")
	target := Structural_Target{scope = scope, start = 8, end = 18, kind = kind, depth = 3}

	testing.expect(t, structural_scope_is_valid(scope))
	testing.expect(t, structural_request_is_valid(request, 64))
	testing.expect(t, structural_target_is_valid(target, 64))
	testing.expect(t, structural_limits_are_valid(DEFAULT_STRUCTURAL_LIMITS))
	testing.expect_value(t, size_of(Structural_Node_Kind), 98)
}

@(test)
/* Verifies malformed structural scopes, regions, and limits are rejected. */
reject_stale_shapes_and_limits :: proc(t: ^testing.T) {
	scope := structural_test_scope()
	request := Structural_Request {
		operation = .Select,
		scope = scope,
		point = 8,
		start = 16,
		end = 8,
		has_region = true,
	}
	limits := DEFAULT_STRUCTURAL_LIMITS
	limits.nodes += 1

	testing.expect(t, !structural_request_is_valid(request, 64))
	testing.expect(t, !structural_limits_are_valid(limits))
	scope.tree_generation = 0
	testing.expect(t, !structural_scope_is_valid(scope))
}

@(test)
/* Verifies copied indentation-plan cleanup is idempotent. */
indentation_plan_cleanup_is_idempotent :: proc(t: ^testing.T) {
	edits := make([dynamic]Structural_Indent_Edit, 0, 2)
	_, _ = append(&edits, Structural_Indent_Edit{start = editor.Byte_Offset(4), end = editor.Byte_Offset(8), indent_level = 1, indent_bytes = 4})
	plan := Structural_Indentation_Plan{scope = structural_test_scope(), edits = edits, allocator = context.allocator}

	structural_indentation_plan_close(&plan)
	structural_indentation_plan_close(&plan)
	testing.expect(t, plan.edits == nil)
	testing.expect_value(t, plan.scope, Structural_Scope{})
	testing.expect_value(t, plan.usage, Structural_Usage{})
}
