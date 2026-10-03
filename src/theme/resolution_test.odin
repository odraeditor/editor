// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package theme

import "../ui"
import "core:testing"

/* Verifies complete resolution and malformed-definition rejection before mutation. */
@(test)
definition_resolves_atomically_into_ui_proposal :: proc(t: ^testing.T) {
	registry: ui.Registry
	initialized, _ := ui.registry_init(&registry, 801)
	testing.expect(t, initialized)
	if !initialized do return
	defer ui.registry_close(&registry)

	styles := factory_fallback_styles()
	proposal, prepared, _ := ui.proposal_begin(&registry)
	testing.expect(t, prepared)
	if !prepared do return
	resolved, _ := definition_resolve_ui(&proposal, styles[:])
	_, duplicate, duplicate_failure := ui.proposal_add_style(&proposal, .Text_Normal)
	testing.expect(t, resolved && !duplicate)
	testing.expect_value(t, duplicate_failure.code, ui.Failure_Code.Invalid_Style)
	ui.proposal_abort(&proposal)

	malformed, malformed_prepared, _ := ui.proposal_begin(&registry)
	testing.expect(t, malformed_prepared)
	if !malformed_prepared do return
	defer if malformed.state != nil do ui.proposal_abort(&malformed)
	rejected, rejection := definition_resolve_ui(
		&malformed,
		styles[:CURRENT_STYLE_ROLE_COUNT - 1],
	)
	_, added_after_rejection, _ := ui.proposal_add_style(&malformed, .Text_Normal)
	testing.expect(t, !rejected && added_after_rejection)
	testing.expect_value(t, rejection.code, ui.Failure_Code.Invalid_Style)
	testing.expect_value(t, rejection.limit, u64(CURRENT_STYLE_ROLE_COUNT))
	testing.expect_value(t, rejection.actual, u64(CURRENT_STYLE_ROLE_COUNT - 1))
}
