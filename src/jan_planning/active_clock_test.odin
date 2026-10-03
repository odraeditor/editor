// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_planning

import "core:testing"

/* Verifies active-clock startup preserves exact state or requires recovery. */
@(test)
active_clock_schema_requires_explicit_recovery :: proc(t: ^testing.T) {
	scope := planning_test_scope()
	resource, resource_ok := resource_identity_copy(1, "project/notes.org")
	time_zone, time_zone_ok := active_clock_time_zone_copy("Europe/Warsaw")
	testing.expect(t, resource_ok && time_zone_ok)
	record := Active_Clock_Record {
		schema_version = ACTIVE_CLOCK_SCHEMA_VERSION,
		domain = 1,
		resource = resource,
		target = planning_test_target(scope),
		started_at = {seconds = 1_800_000_000, nanoseconds = 123},
		time_zone = time_zone,
		source_revision = u64(scope.analysis.source_revision),
		source_bytes = scope.source_bytes,
		last_transition = .Start,
		recovery_state = .Active,
	}
	testing.expect(t, active_clock_record_is_valid(record))
	testing.expect_value(t, active_clock_startup_state(record, scope.analysis), Clock_Recovery_State.Active)
	stale := scope.analysis
	stale.source_revision += 1
	testing.expect_value(t, active_clock_startup_state(record, stale), Clock_Recovery_State.Recovery_Required)
	record.recovery_state = .Recovery_Required
	testing.expect_value(t, active_clock_startup_state(record, scope.analysis), Clock_Recovery_State.Recovery_Required)
	record.recovery_state = .Resolved
	testing.expect_value(t, active_clock_startup_state(record, stale), Clock_Recovery_State.Resolved)
	record.schema_version += 1
	testing.expect_value(t, active_clock_startup_state(record, scope.analysis), Clock_Recovery_State.Invalid)
}
