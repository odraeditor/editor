// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor_session"
import "../interaction"
import "../layout"
import editor_view "../view"
import "core:testing"

/* Verifies native and programmable command failures preserve complete layout diagnostics. */
@(test)
layout_failures_keep_nested_causes :: proc(t: ^testing.T) {
	failure := layout.Failure_Context {
		code = .View_Failure,
		operation = .Teardown,
		layout = {
			owner_id = 71,
			layout_id = 72,
			generation = 73,
		},
		pane = {
			layout = {
				owner_id = 71,
				layout_id = 72,
				generation = 73,
			},
			pane_id = 74,
			slot = 5,
			slot_generation = 6,
		},
		maximum = 8,
		actual = 9,
		view_failure = editor_view.Failure_Context{code = .Active_Preparation},
		session_failure = editor_session.Failure_Context{code = .Busy},
	}
	command_handle := interaction.Command_Handle {
		registry_generation = 12,
		slot = 11,
		entry_generation = 13,
	}
	native := native_layout_failure(command_handle, failure)
	capability := layout_capability_layout_failure(failure)
	contained_failures := [2]Failure_Context{native, capability}
	for contained in contained_failures {
		testing.expect_value(t, contained.code, Failure_Code.Layout_Failure)
		testing.expect_value(t, contained.layout_code, layout.Failure_Code.View_Failure)
		testing.expect_value(t, contained.layout_failure, failure)
		testing.expect_value(t, contained.limit, u64(8))
		testing.expect_value(t, contained.actual, u64(9))
	}
	testing.expect_value(t, native.command, command_handle)
}
