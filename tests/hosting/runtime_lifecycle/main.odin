// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../../src/hosting"

ODRA_RACKET_BOUNDARY_RUNTIME_LIBRARY :: #config(
	ODRA_RACKET_BOUNDARY_RUNTIME_LIBRARY,
	"../../../.build/hosting/libodra_racket_runtime.a",
)

foreign import boundary_runtime {ODRA_RACKET_BOUNDARY_RUNTIME_LIBRARY}

@(default_calling_convention="c")
foreign boundary_runtime {
	odra_racket_runtime_boundary_stats :: proc(
		live, loaded, released: ^u64,
	) -> i32 ---
}

boundary_stats :: proc() -> (live, loaded, released: u64) {
	result := odra_racket_runtime_boundary_stats(&live, &loaded, &released)
	assert(result == 0)
	return
}

main :: proc() {
	runtime: hosting.Runtime
	live, loaded, released := boundary_stats()
	assert(live == 0 && loaded == 0 && released == 0)
	assert(hosting.runtime_state(&runtime) == .Uninitialized)
	started, start_failure := hosting.runtime_start(&runtime)
	assert(started, start_failure.diagnostic)
	assert(hosting.runtime_state(&runtime) == .Ready)
	assert(hosting.runtime_diagnostic(&runtime) == "")
	live, loaded, released = boundary_stats()
	assert(live > 0 && loaded == live && released == 0)
	result, called, call_failure := hosting.runtime_call_scalar(&runtime, 41)
	assert(called, call_failure.diagnostic)
	assert(result == 42)
	stopped, stop_failure := hosting.runtime_shutdown(&runtime)
	assert(stopped, stop_failure.diagnostic)
	assert(hosting.runtime_state(&runtime) == .Stopped)
	live, loaded, released = boundary_stats()
	assert(live == 0 && loaded > 0 && released == loaded)
	stopped, stop_failure = hosting.runtime_shutdown(&runtime)
	assert(!stopped, "duplicate shutdown was accepted")
	assert(stop_failure.code == .Invalid_State)
	assert(hosting.runtime_state(&runtime) == .Stopped)
	assert(hosting.runtime_diagnostic(&runtime) == "runtime_shutdown requires the Ready state")
}
