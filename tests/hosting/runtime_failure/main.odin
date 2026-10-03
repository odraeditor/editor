// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../../src/hosting"

EXPECT_RUNTIME_UNAVAILABLE :: #config(EXPECT_RUNTIME_UNAVAILABLE, false)

main :: proc() {
	runtime: hosting.Runtime
	started, failure := hosting.runtime_start(&runtime)
	assert(!started, "faulted runtime unexpectedly started")
	assert(hosting.runtime_state(&runtime) == .Failed)
	assert(len(failure.diagnostic) > 0)
	if EXPECT_RUNTIME_UNAVAILABLE {
		assert(failure.code == .Runtime_Unavailable)
	} else {
		assert(failure.code == .Wrong_Result)
	}

	stopped, stop_failure := hosting.runtime_shutdown(&runtime)
	assert(!stopped, "failed runtime unexpectedly shut down")
	assert(stop_failure.code == .Invalid_State)
	assert(hosting.runtime_state(&runtime) == .Failed)
}
