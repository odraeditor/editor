// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "core:testing"
import "core:time"
import "core:fmt"
import "../terminal_emulator"

/* Verifies hostile geometry is rejected before native allocation or live-state mutation. */
@(test)
hardening_rejects_geometry_before_native_allocation :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil do _, _ = registry_close(&registry)
	oversized := test_open_request("oversized geometry")
	oversized.emulator.columns = MAX_TERMINAL_COLUMNS + 1
	oversized.start.columns = oversized.emulator.columns
	_, opened, open_failure := registry_open(&registry, oversized)
	testing.expect(t, !opened)
	testing.expect_value(t, open_failure.code, Failure_Code.Invalid_Argument)
	stats, inspected, _ := registry_inspect(&registry)
	testing.expect(t, inspected)
	if inspected do testing.expect_value(t, stats.session_count, u16(0))

	record, live, _ := registry_open(&registry, test_open_request("bounded geometry"))
	testing.expect(t, live)
	if !live do return
	resized, resize_failure := registry_resize(
		&registry, record.ref, MAX_TERMINAL_COLUMNS, MAX_TERMINAL_ROWS + 1, 8, 16,
	)
	testing.expect(t, !resized)
	testing.expect_value(t, resize_failure.code, Failure_Code.Projection_Limit)
	current, found, _ := registry_record(&registry, record.ref)
	testing.expect(t, found)
	if found do testing.expect_value(t, current.lifecycle, Lifecycle.Running)
}

/* Verifies the operating concurrency target makes fair progress and releases every owner. */
@(test)
hardening_releases_operating_session_set_after_fair_output :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	if !initialized do return
	refs: [8]Session_Ref
	emulators: [8]terminal_emulator.Ref
	for index in 0 ..< len(refs) {
		record, opened, failure := registry_open(
			&registry,
			test_open_request(
				fmt.tprintf("hardening-%d", index),
				arguments = []string{"-c", "printf bounded-output; sleep 0.05"},
			),
		)
		testing.expectf(t, opened, "session %d failed: %v", index, failure.code)
		if !opened {
			_, _ = registry_close(&registry)
			return
		}
		refs[index] = record.ref
		emulators[index] = record.emulator
	}
	progressed: [8]bool
	for turn in 0 ..< 2_000 {
		batch, stepped := registry_step_output_all(&registry, i64(turn + 1))
		testing.expect(t, stepped)
		if !stepped do break
		complete := true
		for ref, index in refs {
			record, found, _ := registry_record(&registry, ref)
			if found && record.output_bytes > 0 do progressed[index] = true
			complete = complete && progressed[index]
		}
		if complete do break
		if batch.sessions_progressed == 0 do time.sleep(time.Millisecond)
	}
	for value in progressed do testing.expect(t, value)
	closed, close_failure := registry_close(&registry)
	testing.expectf(t, closed, "registry close failed: %v", close_failure.code)
	for emulator in emulators {
		stats, result := terminal_emulator.stats(emulator)
		testing.expect_value(t, result, terminal_emulator.Result.OK)
		if result == .OK {
			testing.expect(t, !stats.live)
			testing.expect_value(t, stats.live_bytes, u64(0))
		}
	}
}
