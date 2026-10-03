// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_output

import "core:testing"

/* Verifies scalar precedence, backend specificity, and additive accounting. */
@(test)
output_settings_resolve_explicit_precedence :: proc(t: ^testing.T) {
	candidates := []Setting_Candidate {
		{key = "title", value = "factory", source = .Factory},
		{key = "title", value = "project", source = .Project},
		{key = "title", value = "generic invocation", source = .Invocation},
		{key = "title", value = "html invocation", backend = "html", source = .Invocation},
	}
	resolution, ok, _ := resolve_export_setting(3, "title", "html", candidates)
	testing.expect(t, ok)
	testing.expect_value(t, resolution.winner_index, u16(3))
	testing.expect_value(t, resolution.shadowed_count, u16(3))
	additive := []Setting_Candidate {
		{key = "header", value = "a", source = .User, additive = true, source_order = 1},
		{key = "header", value = "b", source = .Document, additive = true, source_order = 2},
	}
	resolution, ok, _ = resolve_export_setting(4, "header", "html", additive)
	testing.expect(t, ok)
	testing.expect(t, resolution.additive)
	testing.expect_value(t, resolution.contribution_count, u16(2))
}

/* Verifies complete plans accept exact includes, macros, filters, and destinations. */
@(test)
output_plan_is_complete_before_handoff :: proc(t: ^testing.T) {
	scope := output_test_scope()
	settings := []Setting_Candidate {{key = "title", value = "Report", source = .Document}}
	includes := []Include_Record {{resource_id = 7, resource_revision = 11, depth = 1, recursive = true}}
	macros := []Macro_Record {{identity = "author", depth = 1, expansion_bytes = 12, defined = true}}
	filters := []Filter_Record {{identity = "finalize", generation = scope.filter_generation, order = 1, available = true}}
	request := Export_Request {operation_id = 41, scope = scope, selection = output_test_selection(scope),
		backend = "html", projection = {contents = true, contents_depth = 3, number_headings = true},
		settings = settings, includes = includes, macros = macros, filters = filters,
		destination = {kind = .Resource, resource_id = 13, expected_revision = 17}, limits = DEFAULT_LIMITS,
		explicit = true}
	plan, ok, _ := prepare_output_plan(request)
	testing.expect(t, ok)
	testing.expect(t, plan.complete)
	testing.expect_value(t, plan.include_count, u32(1))
	testing.expect_value(t, plan.macro_count, u32(1))
	testing.expect_value(t, plan.filter_count, u16(1))
	request.explicit = false
	_, implicit_ok, implicit_failure := prepare_output_plan(request)
	testing.expect(t, !implicit_ok)
	testing.expect_value(t, implicit_failure.code, Failure_Code.Invalid_Request)
}

/* Verifies stale filters, duplicate includes, and recursive macros fail wholly. */
@(test)
output_plan_rejects_partial_or_stale_inputs :: proc(t: ^testing.T) {
	scope := output_test_scope()
	request := Export_Request {operation_id = 43, scope = scope, selection = output_test_selection(scope),
		backend = "plain-text", destination = {kind = .Preview}, limits = DEFAULT_LIMITS, explicit = true}
	request.includes = []Include_Record {
		{resource_id = 7, resource_revision = 11, depth = 1},
		{resource_id = 7, resource_revision = 12, depth = 2},
	}
	_, ok, failure := prepare_output_plan(request)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Cycle)
	request.includes = nil
	request.macros = []Macro_Record {{identity = "loop", depth = 1, expansion_bytes = 1, defined = true, recursive = true}}
	_, ok, failure = prepare_output_plan(request)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.field, Failure_Field.Macro)
	request.macros = nil
	request.filters = []Filter_Record {{identity = "stale", generation = scope.filter_generation - 1, order = 1, available = true}}
	_, ok, failure = prepare_output_plan(request)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Unavailable)
}

/* Verifies terminal operation states never skip confirmation or recovery. */
@(test)
output_lifecycle_is_closed_and_recoverable :: proc(t: ^testing.T) {
	state, ok := output_lifecycle_transition(.Prepared, .Confirmed)
	testing.expect(t, ok)
	state, ok = output_lifecycle_transition(state, .Active)
	testing.expect(t, ok)
	state, ok = output_lifecycle_transition(state, .Recovery_Required)
	testing.expect(t, ok)
	state, ok = output_lifecycle_transition(state, .Closed)
	testing.expect(t, ok)
	testing.expect_value(t, state, Lifecycle_State.Closed)
	_, ok = output_lifecycle_transition(.Prepared, .Completed)
	testing.expect(t, !ok)
}
