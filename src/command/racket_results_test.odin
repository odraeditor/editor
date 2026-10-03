// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../hosting"
import "../result_set"
import "core:testing"

/* Verifies one factory programmable provider publishes copied admitted results. */
verify_racket_result_provider :: proc(t: ^testing.T, racket_runtime: ^hosting.Runtime) {
	registry: result_set.Registry
	ready, _ := result_set.registry_init(
		&registry,
		result_set.Config{limits = result_set.DEFAULT_LIMITS, allocator = context.allocator},
	)
	testing.expect(t, ready)
	if !ready do return
	defer result_set.registry_close(&registry)
	capability := Result_Capability_Context {
		editor_session_id = 91,
		access = {.Inspect, .Publish, .Move},
		registry = &registry,
		set_id = 31,
		provider_source_id = 41,
		capability_generation = 1,
	}
	turn, published, failure := racket_result_turn(racket_runtime, capability, 0)
	testing.expectf(
		t,
		published,
		"Racket result publication failed after %d calls: %v (runtime=%d): %s",
		turn.calls,
		failure.code,
		failure.actual,
		hosting.runtime_diagnostic(racket_runtime),
	)
	if !published do return
	testing.expect_value(t, turn.calls, u16(3))
	view, viewed, view_failure := result_set.registry_view(&registry, 31)
	testing.expectf(t, viewed, "result fixture view failed: %v", view_failure.code)
	if viewed {
		testing.expect_value(t, view.source.kind, result_set.Source_Kind.Programmable)
		testing.expect_value(t, len(view.locations), 1)
		testing.expect_value(t, view.locations[0].preview, "fixture")
	}
}
