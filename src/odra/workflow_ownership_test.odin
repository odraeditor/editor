// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../search"
import "core:testing"

/* Verifies every prompt end releases prompt-owned and nested transient state. */
@(test)
prompt_end_resets_transient_workflows :: proc(t: ^testing.T) {
	commands := Command_Context {
		prompt_workflow = {
			mode = .Incremental_Search,
			rejected = true,
		},
		search = {
			direction = .Forward,
			kind = .Literal,
			query_pattern_length = 3,
			query_replacement_length = 4,
		},
	}
	commands.interaction_workflow.inspection_sequence.stroke_count = 2

	command_context_end_prompt(&commands)

	testing.expect_value(t, commands.prompt_workflow.mode, Prompt_Mode.None)
	testing.expect(t, !commands.prompt_workflow.rejected)
	testing.expect_value(t, commands.search.direction, search.Direction.Invalid)
	testing.expect_value(t, commands.search.kind, search.Pattern_Kind.Invalid)
	testing.expect_value(t, commands.search.query_pattern_length, 0)
	testing.expect_value(t, commands.search.query_replacement_length, 0)
	testing.expect_value(t, commands.interaction_workflow.inspection_sequence.stroke_count, u8(0))
}

/* Verifies coordinator closure invalidates every retained workflow state. */
@(test)
coordinator_close_resets_owned_workflows :: proc(t: ^testing.T) {
	commands := Command_Context {
		prompt_workflow = {mode = .Exit_Choice},
		document_workflow = {
			exit_count = 2,
			exit_index = 1,
		},
		inventory_workflow = {
			decision_count = 2,
			path_length = 7,
		},
		clipboard_workflow = {
			kill_sequence_id = 9,
			last_command_was_kill = true,
		},
	}
	commands.interaction_workflow.inspection_pending.stroke_count = 1
	commands.interaction_workflow.inspection_sequence.stroke_count = 1

	command_context_close(&commands)

	testing.expect_value(t, commands.prompt_workflow.mode, Prompt_Mode.None)
	testing.expect_value(t, commands.document_workflow.exit_count, u32(0))
	testing.expect_value(t, commands.document_workflow.exit_index, u32(0))
	testing.expect_value(t, commands.inventory_workflow.decision_count, u32(0))
	testing.expect_value(t, commands.inventory_workflow.path_length, 0)
	testing.expect_value(t, commands.clipboard_workflow.kill_sequence_id, u64(0))
	testing.expect(t, !commands.clipboard_workflow.last_command_was_kill)
	testing.expect_value(t, commands.interaction_workflow.inspection_pending.stroke_count, u8(0))
	testing.expect_value(t, commands.interaction_workflow.inspection_sequence.stroke_count, u8(0))
}
