// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_computation

import "core:testing"

@(test)
/* Verifies execution feedback keeps distinct expected and failed outcomes. */
execution_feedback_distinguishes_user_outcomes :: proc(t: ^testing.T) {
	cases := []struct {
		code: Failure_Code,
		kind: Execution_Feedback_Kind,
	} {
		{.Unavailable, .Adapter_Unavailable},
		{.Malformed, .Malformed_Source},
		{.Unauthorized, .Authority_Rejected},
		{.Cancelled, .Cancelled},
		{.Process, .Execution_Failed},
	}
	for candidate in cases {
		feedback := execution_feedback_from_failure(candidate.code)
		testing.expect_value(t, feedback.kind, candidate.kind)
		testing.expect(t, feedback.source_preserved)
		testing.expect(t, feedback.retryable)
		testing.expect(t, len(feedback.message) > 0)
	}
}
