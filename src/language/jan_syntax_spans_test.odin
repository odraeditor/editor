// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "core:testing"

/* Verifies Jan nodes publish normalized exact-revision semantic syntax spans. */
@(test)
jan_syntax_spans_publish_shared_roles :: proc(t: ^testing.T) {
	owner: Jan_Structural_Owner
	initialized, _ := jan_structural_owner_init(&owner, 31)
	testing.expect(t, initialized)
	if !initialized do return
	defer jan_structural_owner_close(&owner)
	source := transmute([]u8)(string(
		"#+title: Demo\n" +
		"* TODO Heading\n" +
		"See [[https://example.test][example]] at <2026-09-10>.\n" +
		"# comment\n",
	))
	scope := jan_syntax_test_scope()
	analysis, analyzed, analysis_failure := jan_structural_owner_analyze(&owner, source, scope)
	testing.expect(t, analyzed)
	testing.expect_value(t, analysis_failure.code, Jan_Failure_Code.None)
	if !analyzed do return
	defer jan_structural_analysis_close(&analysis)
	result, queried, query_failure := jan_structural_analysis_query_spans(
		&analysis,
		0,
		u64(len(source)),
		0,
		Syntax_Snapshot_Generation(9),
	)
	testing.expect(t, queried)
	testing.expect_value(t, query_failure.code, Failure_Code.None)
	if !queried do return
	defer syntax_query_result_close(&result)
	testing.expect_value(t, result.snapshot.buffer_id, scope.buffer_id)
	testing.expect_value(t, result.snapshot.source_revision, scope.source_revision)
	testing.expect_value(t, result.snapshot.language, scope.language)
	testing.expect_value(t, result.snapshot.provider, scope.provider)
	testing.expect_value(t, result.snapshot.generation, Syntax_Snapshot_Generation(9))
	testing.expect_value(t, result.snapshot.span_count, u32(len(result.spans)))
	testing.expect(t, jan_syntax_test_has_role(result.spans[:], .Keyword))
	testing.expect(t, jan_syntax_test_has_role(result.spans[:], .Label))
	testing.expect(t, jan_syntax_test_has_role(result.spans[:], .String))
	testing.expect(t, jan_syntax_test_has_role(result.spans[:], .Constant))
	testing.expect(t, jan_syntax_test_has_role(result.spans[:], .Comment))
	for span in result.spans do testing.expect(t, syntax_span_is_valid(span, u64(len(source))))
}

/* Verifies visible bounds and malformed recovery remain contained. */
@(test)
jan_syntax_spans_bound_visibility_and_recovery :: proc(t: ^testing.T) {
	owner: Jan_Structural_Owner
	initialized, _ := jan_structural_owner_init(&owner, 32)
	testing.expect(t, initialized)
	if !initialized do return
	defer jan_structural_owner_close(&owner)
	source := transmute([]u8)(string("* Heading\n#+begin_src odin\nmain :: proc() {}\n"))
	scope := jan_syntax_test_scope()
	scope.parser_generation = 32
	scope.analysis_generation = 2
	analysis, analyzed, _ := jan_structural_owner_analyze(&owner, source, scope)
	testing.expect(t, analyzed)
	if !analyzed do return
	defer jan_structural_analysis_close(&analysis)
	result, queried, _ := jan_structural_analysis_query_spans(&analysis, 0, 10, 0, 10)
	testing.expect(t, queried)
	if queried {
		testing.expect(t, jan_syntax_test_has_role(result.spans[:], .Label))
		syntax_query_result_close(&result)
	}
	_, invalid, failure := jan_structural_analysis_query_spans(
		&analysis,
		0,
		u64(len(source)) + 1,
		0,
		11,
	)
	testing.expect(t, !invalid)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Transaction)
}

@(private)
jan_syntax_test_scope :: proc() -> Jan_Analysis_Scope {
	registration, _ := factory_bundle_registration(FACTORY_JAN_BUNDLE_IDENTITY)
	return {
		buffer_id = 77,
		document_id = 88,
		has_document = true,
		source_revision = 5,
		language = registration.language,
		provider = {registry_id = 2, language_id = registration.language.id, provider_id = 1, provider_generation = 1},
		selection_generation = 6,
		parser_generation = 31,
		grammar_generation = 1,
		configuration = registration.jan_configuration.identity,
		baseline = registration.jan_baseline,
		analysis_generation = 1,
	}
}

@(private)
jan_syntax_test_has_role :: proc(spans: []Syntax_Span, role: Syntax_Role) -> bool {
	for span in spans do if span.role == role do return true
	return false
}
