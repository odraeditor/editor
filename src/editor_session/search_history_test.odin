// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor_session

import "../search"
import "core:fmt"
import "core:testing"

/* Verifies accepted searches are deduplicated, ordered, separated, and bounded. */
@(test)
retains_bounded_compatible_recency :: proc(t: ^testing.T) {
	session: Session
	handle, initialized, failure := session_init(&session, 301, test_session_allocators())
	testing.expectf(t, initialized, "session init failed with %v", failure.code)
	if !initialized {
		return
	}
	defer session_close(&session)

	for index in 0 ..< int(DEFAULT_SEARCH_HISTORY_ENTRIES) + 1 {
		pattern := fmt.tprintf("literal-%02d", index)
		accepted, accept_failure := session_search_history_accept(
			&session,
			handle,
			.Literal,
			pattern,
			search.DEFAULT_POLICY,
		)
		testing.expectf(t, accepted, "history accept failed with %v", accept_failure.code)
	}
	_, _ = session_search_history_accept(
		&session,
		handle,
		.Regular_Expression,
		"literal-[0-9]+",
		search.DEFAULT_POLICY,
	)
	_, _ = session_search_history_accept(
		&session,
		handle,
		.Literal,
		"literal-32",
		search.DEFAULT_POLICY,
	)

	literals, copied, copy_failure := session_search_history_descriptors(
		&session,
		handle,
		.Literal,
	)
	testing.expectf(t, copied, "history copy failed with %v", copy_failure.code)
	if copied {
		testing.expect_value(t, len(literals.descriptors), int(DEFAULT_SEARCH_HISTORY_ENTRIES) - 1)
		testing.expect_value(t, literals.descriptors[0].pattern, "literal-32")
		for descriptor in literals.descriptors {
			testing.expect(t, descriptor.pattern != "literal-00")
		}
		testing.expect(t, search_history_batch_close(&literals))
	}
	expressions, expression_ok, _ := session_search_history_descriptors(
		&session,
		handle,
		.Regular_Expression,
	)
	if expression_ok {
		testing.expect_value(t, len(expressions.descriptors), 1)
		testing.expect_value(t, expressions.descriptors[0].pattern, "literal-[0-9]+")
		search_history_batch_close(&expressions)
	}
}

/* Verifies navigation restores live input after the newest compatible entry. */
@(test)
navigation_restores_in_progress_query :: proc(t: ^testing.T) {
	session: Session
	handle, initialized, _ := session_init(&session, 303, test_session_allocators())
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer session_close(&session)
	_, _ = session_search_history_accept(&session, handle, .Literal, "older", search.DEFAULT_POLICY)
	_, _ = session_search_history_accept(&session, handle, .Regular_Expression, "ignored", search.DEFAULT_POLICY)
	_, _ = session_search_history_accept(&session, handle, .Literal, "newer", search.DEFAULT_POLICY)
	started, start_failure := session_search_history_begin(&session, handle, .Literal, "live")
	testing.expectf(t, started, "history navigation failed with %v", start_failure.code)

	newer, older_ok, _ := session_search_history_older(&session, handle)
	testing.expect(t, older_ok && newer.present)
	testing.expect_value(t, newer.descriptor.pattern, "newer")
	older, second_older_ok, _ := session_search_history_older(&session, handle)
	testing.expect(t, second_older_ok && older.present)
	testing.expect_value(t, older.descriptor.pattern, "older")
	_, newer_ok, _ := session_search_history_newer(&session, handle)
	testing.expect(t, newer_ok)
	restored, restored_ok, _ := session_search_history_newer(&session, handle)
	testing.expect(t, restored_ok && restored.present && restored.restored_in_progress)
	testing.expect_value(t, restored.descriptor.pattern, "live")
	ended, end_failure := session_search_history_end(&session, handle)
	testing.expectf(t, ended, "history navigation close failed with %v", end_failure.code)
}
