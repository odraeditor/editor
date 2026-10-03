// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "core:fmt"
import "core:os"

/* main reports one post-cleanup diagnostic and maps failure to process status. */
main :: proc() {
	failure := run(os.args[1:])
	if failure.stage != .None {
		if failure.stage == .Gutter {
			fmt.eprintf(
				"odra: gutter operation=%v code=%v lane=%d limit=%d actual=%d\n",
				failure.gutter.operation,
				failure.gutter.code,
				u64(failure.gutter.lane),
				failure.gutter.limit,
				failure.gutter.actual,
			)
		}
		if failure.stage == .Status {
			fmt.eprintf(
				"odra: status operation=%v code=%v segment=%d limit=%d actual=%d\n",
				failure.status_bar.operation,
				failure.status_bar.code,
				u64(failure.status_bar.segment),
				failure.status_bar.limit,
				failure.status_bar.actual,
			)
		}
		if failure.stage == .Terminal_Workflow {
			fmt.eprintf(
				"odra: terminal-workflow stage=%v terminal=%v/%v process=%v emulator=%v limit=%d actual=%d\n",
				failure.terminal_workflow_stage,
				failure.terminal_session_failure.stage,
				failure.terminal_session_failure.code,
				failure.terminal_session_failure.process_code,
				failure.terminal_session_failure.emulator_result,
				failure.terminal_session_failure.limit,
				failure.terminal_session_failure.actual,
			)
		}
		fmt.eprintf(
			"odra: stage=%v arguments=%d document=%v terminal=%v/%v errno=%d limit=%d actual=%d bytes=%d clipboard=%v display=%v status=%v editor=%v view=%v/%v session=%v/%v layout=%v/%v view=%v/%v session=%v/%v policy=%d/%d hook=%d deferred=%d bridge=%v layout=%v/%v hosting=%v diagnostic=%q history=%v kill_ring=%v language_service=%v candidate=%v interaction=%v command=%v ui=%v/%v theme=%v/%v layout=%v/%v bridge=%v hosting=%v diagnostic=%q prompt=%v\n",
			failure.stage,
			failure.argument_count,
			failure.document.code,
			failure.terminal.code,
			failure.terminal.display_failure.code,
			failure.terminal.os_errno,
			failure.terminal.limit,
			failure.terminal.actual,
			failure.terminal.bytes_done,
			failure.clipboard.code,
			failure.display.code,
			failure.status_bar.code,
			failure.editor.code,
			failure.view.code,
			failure.view.editor_failure.code,
			failure.editor_session.code,
			failure.editor_session.view_failure.code,
			failure.layout.code,
			failure.layout.operation,
			failure.layout.view_failure.code,
			failure.layout.view_failure.editor_failure.code,
			failure.layout.session_failure.code,
			failure.layout.session_failure.view_failure.code,
			u64(failure.layout.display_policy_generation),
			failure.layout.display_action_index,
			u64(failure.layout.hook.hook_id),
			u64(failure.layout.deferred_sequence),
			failure.bridge.code,
			failure.bridge.layout_code,
			failure.bridge.layout_failure.operation,
			failure.hosting.code,
			failure.hosting.diagnostic,
			failure.history.code,
			failure.kill_ring.code,
			failure.language_service.code,
			failure.candidate.code,
			failure.interaction.code,
			failure.command.code,
			failure.ui.operation,
			failure.ui.code,
			failure.theme.operation,
			failure.theme.code,
			failure.command.layout_code,
			failure.command.layout_failure.operation,
			failure.command.bridge_code,
			failure.command.hosting_code,
			failure.command.diagnostic,
			failure.prompt_failure.code,
		)
		os.exit(1)
	}
}
