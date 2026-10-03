// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../editor"
import "core:testing"

/* Verifies the measured factory policy remains internally consistent. */
@(test)
default_policy_matches_selected_bounds :: proc(t: ^testing.T) {
	testing.expect(t, policy_is_valid(DEFAULT_POLICY))
	testing.expect_value(t, DEFAULT_POLICY.providers, u16(64))
	testing.expect_value(t, DEFAULT_POLICY.retained_trees, u16(256))
	testing.expect_value(t, DEFAULT_POLICY.analyzed_source_bytes, u64(64 * MEBIBYTE))
	testing.expect_value(t, DEFAULT_POLICY.spans, u32(65_536))
	testing.expect_value(t, DEFAULT_POLICY.retained_stale_work, u8(1))
}

/* Verifies every stable syntax role is admitted and invalid roles are rejected. */
@(test)
syntax_role_vocabulary_is_closed :: proc(t: ^testing.T) {
	for role_value in int(Syntax_Role.Attribute) ..= int(Syntax_Role.Variable_Parameter) {
		testing.expect(t, syntax_role_is_valid(Syntax_Role(role_value)))
	}
	testing.expect(t, !syntax_role_is_valid(.Invalid))
	testing.expect(t, !syntax_role_is_valid(Syntax_Role(255)))
}

/* Verifies normalized spans require exact non-empty in-bounds revisions. */
@(test)
syntax_spans_reject_bad_range_role_and_revision :: proc(t: ^testing.T) {
	provider := Provider_Handle {
		registry_id = 1,
		language_id = 1,
		provider_id = 1,
		provider_generation = 1,
	}
	valid := Syntax_Span {
		start = 2,
		end = 7,
		role = .Keyword,
		precedence = 10,
		provider = provider,
		source_revision = 3,
	}
	testing.expect(t, syntax_span_is_valid(valid, 12))

	cases := [?]struct {
		name: string,
		span: Syntax_Span,
	} {
		{"empty-range", {start = 7, end = 7, role = .Keyword, provider = provider, source_revision = 3}},
		{"reversed-range", {start = 8, end = 7, role = .Keyword, provider = provider, source_revision = 3}},
		{"range-past-source", {start = 2, end = 13, role = .Keyword, provider = provider, source_revision = 3}},
		{"invalid-role", {start = 2, end = 7, role = .Invalid, provider = provider, source_revision = 3}},
		{"missing-provider", {start = 2, end = 7, role = .Keyword, provider = {}, source_revision = 3}},
		{"zero-revision", {start = 2, end = 7, role = .Invalid, provider = provider, source_revision = editor.Revision(0)}},
	}
	for test_case in cases {
		testing.expectf(t, !syntax_span_is_valid(test_case.span, 12), "%s span was accepted", test_case.name)
	}
}

/* Verifies invalid subordinate resource values reject the complete policy. */
@(test)
policy_rejects_zero_and_overflow :: proc(t: ^testing.T) {
	cases := [?]struct {
		name:   string,
		policy: Policy,
	} {
		{"zero-providers", DEFAULT_POLICY},
		{"excessive-spans", DEFAULT_POLICY},
		{"insufficient-retention", DEFAULT_POLICY},
		{"excessive-cancel-interval", DEFAULT_POLICY},
		{"insufficient-retained-trees", DEFAULT_POLICY},
	}
	cases[0].policy.providers = 0
	cases[1].policy.spans = MAX_SYNTAX_SPANS + 1
	cases[2].policy.retained_analysis_bytes = MAX_ANALYZED_SOURCE_BYTES - 1
	cases[3].policy.cancellation_check_bytes = INCREMENTAL_WORK_BYTES + 1
	cases[4].policy.retained_trees = cases[4].policy.live_selections
	for test_case in cases {
		testing.expectf(t, !policy_is_valid(test_case.policy), "%s policy was accepted", test_case.name)
	}
}
