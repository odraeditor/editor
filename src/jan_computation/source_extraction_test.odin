// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_computation

import "../editor"
import "core:testing"

/* Verifies focused editing preserves owner delimiters, indentation, and unrelated source. */
@(test)
source_extraction_publish_focused_body_only :: proc(t: ^testing.T) {
	prefix := "* Example\n#+begin_src racket\n"
	body := "  (+ 1 2)\n  (+ 3 4)\n"
	suffix := "#+end_src\nUnrelated text\n"
	source_storage: [256]u8
	cursor := copy(source_storage[:], prefix)
	body_start := cursor
	cursor += copy(source_storage[cursor:], body)
	body_end := cursor
	cursor += copy(source_storage[cursor:], suffix)
	source := string(source_storage[:cursor])
	scope := computation_test_scope()
	scope.source_bytes = u64(len(source))
	owner := computation_test_target(scope)
	owner.range.start = 10
	owner.range.end = language_byte_offset(len(source) - len("Unrelated text\n"))
	focused_storage: [128]u8
	edit, focused, opened, _ := open_source_edit(51, scope, owner, u64(body_start), u64(body_end), "  ", source, focused_storage[:])
	testing.expect(t, opened)
	testing.expect_value(t, focused, "(+ 1 2)\n(+ 3 4)\n")

	output: [256]u8
	publication, updated, published, _ := publish_source_edit(&edit, scope, owner, source, "(- 8 3)\n", output[:])
	testing.expect(t, published)
	testing.expect(t, publication.complete)
	testing.expect_value(t, updated[:body_start], prefix)
	testing.expect_value(t, updated[body_start:body_start + len("  (- 8 3)\n")], "  (- 8 3)\n")
	testing.expect_value(t, updated[len(updated) - len(suffix):], suffix)

	second_edit, _, second_opened, _ := open_source_edit(52, scope, owner, u64(body_start), u64(body_end), "  ", source, focused_storage[:])
	testing.expect(t, second_opened)
	testing.expect(t, abort_source_edit(&second_edit))
	_, _, aborted_published, aborted_failure := publish_source_edit(&second_edit, scope, owner, source, "ignored", output[:])
	testing.expect(t, !aborted_published)
	testing.expect_value(t, aborted_failure.code, Failure_Code.Stale)
}

/* Verifies stale bodies and allocation failures cannot publish partial source. */
@(test)
source_extraction_reject_stale_or_partial_edits :: proc(t: ^testing.T) {
	source := "#+begin_src racket\n  1\n#+end_src\n"
	scope := computation_test_scope()
	scope.source_bytes = u64(len(source))
	owner := computation_test_target(scope)
	owner.range.start = 0
	owner.range.end = language_byte_offset(len(source))
	body_start := u64(len("#+begin_src racket\n"))
	body_end := body_start + u64(len("  1\n"))
	focused: [16]u8
	edit, _, ok, _ := open_source_edit(53, scope, owner, body_start, body_end, "  ", source, focused[:])
	testing.expect(t, ok)
	stale_source := "#+begin_src racket\n  2\n#+end_src\n"
	output: [64]u8
	_, _, stale_ok, stale_failure := publish_source_edit(&edit, scope, owner, stale_source, "3\n", output[:])
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale)

	edit, _, ok, _ = open_source_edit(54, scope, owner, body_start, body_end, "  ", source, focused[:])
	testing.expect(t, ok)
	tiny: [4]u8
	_, _, allocation_ok, allocation_failure := publish_source_edit(&edit, scope, owner, source, "long replacement\n", tiny[:])
	testing.expect(t, !allocation_ok)
	testing.expect_value(t, allocation_failure.code, Failure_Code.Allocation_Failed)
	testing.expect_value(t, edit.state, Source_Edit_State.Open)
}

/* Verifies noweb arguments, indentation prefixing, additive separators, and admission. */
@(test)
source_extraction_expand_admitted_noweb :: proc(t: ^testing.T) {
	definitions := []Noweb_Definition {
		{identity = "helper", body = "value = $arguments\nnext", kind = .Source, source = .Document, admitted = true},
		{identity = "parts", body = "a", separator = ", ", kind = .Source, source = .Project_Library,
		 additive = true, admitted = true, order = 1},
		{identity = "parts", body = "b", separator = ", ", kind = .Source, source = .Project_Library,
		 additive = true, admitted = true, order = 2},
	}
	output: [256]u8
	trace: [32]Noweb_Trace
	expansion, expanded, ok, _ := expand_noweb("if true:\n  <<helper(7)>>\n<<parts>>", definitions, output[:], trace[:])
	testing.expect(t, ok)
	testing.expect(t, expansion.complete)
	testing.expect_value(t, expansion.reference_count, u32(3))
	testing.expect_value(t, expanded, "if true:\n  value = 7\n  next\na, b")

	definitions[1].admitted = false
	_, _, admitted_ok, admitted_failure := expand_noweb("<<parts>>", definitions, output[:], trace[:])
	testing.expect(t, !admitted_ok)
	testing.expect_value(t, admitted_failure.code, Failure_Code.Malformed)
}

/* Verifies missing, ambiguous, and cyclic noweb graphs publish nothing. */
@(test)
source_extraction_reject_invalid_noweb_graphs :: proc(t: ^testing.T) {
	output: [128]u8
	trace: [16]Noweb_Trace
	definitions := []Noweb_Definition {
		{identity = "a", body = "<<b>>", kind = .Source, source = .Document, admitted = true},
		{identity = "b", body = "<<a>>", kind = .Source, source = .Document, admitted = true},
	}
	expansion, _, ok, failure := expand_noweb("<<a>>", definitions, output[:], trace[:])
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Cycle)
	testing.expect_value(t, expansion.trace_count, u16(2))

	_, _, ok, failure = expand_noweb("<<missing>>", definitions, output[:], trace[:])
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Unavailable)
	definitions = []Noweb_Definition {
		{identity = "same", body = "x", kind = .Source, source = .Document, admitted = true},
		{identity = "same", body = "y", kind = .Result, source = .Document, admitted = true},
	}
	_, _, ok, failure = expand_noweb("<<same>>", definitions, output[:], trace[:])
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Conflict)
}

/* Verifies tangling stages complete ordered resources with provenance and collision policy. */
@(test)
source_extraction_plan_complete_tangle :: proc(t: ^testing.T) {
	scope := computation_test_scope()
	first_target, _ := tangle_resource_copy(7, "generated/main.rkt")
	second_target, _ := tangle_resource_copy(7, "generated/helper.rkt")
	first_owner := computation_test_target(scope)
	second_owner := first_owner
	second_owner.node_id = 6
	second_owner.range.start = 25
	second_owner.range.end = 40
	blocks := []Tangle_Block {
		{operation_id = 61, scope = scope, owner = first_owner, resource = first_target,
		 content = "(displayln \"second\")", comment_prefix = ";; ", mode = 0o755, order = 2, comments = true, padding = true, policy = .Overwrite},
		{operation_id = 62, scope = scope, owner = second_owner, resource = first_target,
		 content = "#lang racket", shebang = "#!/usr/bin/env racket", comment_prefix = ";; ", mode = 0o755, order = 1,
		 comments = true, padding = true, policy = .Overwrite},
		{operation_id = 63, scope = scope, owner = second_owner, resource = second_target,
		 content = "(provide helper)", mode = 0o644, order = 1, policy = .Reject},
	}
	existing := []Existing_Tangle_Resource{{resource = first_target, exists = true, generated_by_jan = false}}
	staging: [512]u8
	targets: [3]Tangle_Target
	outcomes: [3]Tangle_Outcome
	plan, ok, _ := plan_tangle(blocks, existing, staging[:], targets[:], outcomes[:], false)
	testing.expect(t, ok)
	testing.expect(t, plan.complete)
	testing.expect_value(t, plan.target_count, u32(2))
	testing.expect_value(t, plan.outcome_count, u32(3))
	main_index := -1
	for target, index in targets[:plan.target_count] do if tangle_resource_equal(target.resource, first_target) {
		main_index = index
		break
	}
	testing.expect(t, main_index >= 0)
	testing.expect(t, targets[main_index].complete)
	main_text := string(staging[targets[main_index].offset:targets[main_index].offset + targets[main_index].byte_count])
	testing.expect(t, contains_text(main_text, "#!/usr/bin/env racket\n"))
	testing.expect(t, contains_text(main_text, "#lang racket"))
	testing.expect(t, contains_text(main_text, "(displayln \"second\")"))

	blocks[0].policy = .Reject
	blocks[1].policy = .Reject
	_, collision_ok, collision_failure := plan_tangle(blocks, existing, staging[:], targets[:], outcomes[:], false)
	testing.expect(t, !collision_ok)
	testing.expect_value(t, collision_failure.code, Failure_Code.Conflict)
	_, cancelled_ok, cancelled_failure := plan_tangle(blocks, existing, staging[:], targets[:], outcomes[:], true)
	testing.expect(t, !cancelled_ok)
	testing.expect_value(t, cancelled_failure.code, Failure_Code.Cancelled)
}

@(private)
language_byte_offset :: proc(value: int) -> editor.Byte_Offset {
	return editor.Byte_Offset(value)
}

@(private)
contains_text :: proc(text, expected: string) -> bool {
	if len(expected) == 0 || len(expected) > len(text) do return false
	for index in 0 ..= len(text) - len(expected) do if text[index:index + len(expected)] == expected do return true
	return false
}
