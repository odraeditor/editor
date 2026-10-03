// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../../src/hosting"

ODRA_RACKET_BOUNDARY_RUNTIME_LIBRARY :: #config(
	ODRA_RACKET_BOUNDARY_RUNTIME_LIBRARY,
	"../../../.build/hosting/libodra_racket_runtime_invalid_shutdown.a",
)

foreign import boundary_runtime {ODRA_RACKET_BOUNDARY_RUNTIME_LIBRARY}

@(default_calling_convention="c")
foreign boundary_runtime {
	odra_racket_runtime_boundary_stats :: proc(
		live, loaded, released: ^u64,
	) -> i32 ---
}

main :: proc() {
	runtime: hosting.Runtime
	started, start_failure := hosting.runtime_start(&runtime)
	assert(started, start_failure.diagnostic)
	assert(hosting.runtime_state(&runtime) == .Ready)

	live, loaded, released: u64
	stats_result := odra_racket_runtime_boundary_stats(&live, &loaded, &released)
	assert(stats_result == 0)
	assert(live > 0 && loaded == live && released == 0)

	stopped, stop_failure := hosting.runtime_shutdown(&runtime)
	assert(!stopped, "invalid Racket shutdown unexpectedly succeeded")
	assert(stop_failure.code == .Wrong_Result)
	assert(
		stop_failure.diagnostic ==
			"Odra built-in Racket module returned an invalid shutdown result",
	)
	assert(hosting.runtime_state(&runtime) == .Failed)

	stats_result = odra_racket_runtime_boundary_stats(&live, &loaded, &released)
	assert(stats_result == 0)
	assert(live == 0 && loaded > 0 && released == loaded)
}
