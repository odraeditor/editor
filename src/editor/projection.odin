// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor

import "base:runtime"
import "core:unicode/utf8"

/*
buffer_projection_replace atomically replaces one read-only terminal projection.
It advances the canonical revision without admitting an editor splice or undo record.
*/
buffer_projection_replace :: proc(
	buffer: ^Buffer,
	contents: string,
	temporary_allocator: runtime.Allocator,
	cancelled := false,
) -> (revision: Revision, ok: bool, failure: Failure_Context) {
	state, state_failure := buffer_live_state(buffer)
	if state_failure.code != .None {
		return 0, false, state_failure
	}
	if state.kind != .Terminal_Projection {
		return state.revision, false, Failure_Context {
			code = .Wrong_Buffer_Kind,
			buffer_id = state.buffer_id,
			revision = state.revision,
		}
	}
	if cancelled {
		return state.revision, false, Failure_Context {
			code = .Cancelled,
			buffer_id = state.buffer_id,
			revision = state.revision,
		}
	}
	if !utf8.valid_string(contents) {
		return state.revision, false, Failure_Context {
			code = .Malformed_UTF8,
			buffer_id = state.buffer_id,
			revision = state.revision,
		}
	}
	if temporary_allocator.procedure == nil {
		return state.revision, false, Failure_Context {
			code = .Temporary_Memory_Limit,
			buffer_id = state.buffer_id,
			revision = state.revision,
			limit = state.limits.temporary_bytes,
		}
	}

	root_stats, stats_ok, _ := buffer_stats(buffer)
	assert(stats_ok)
	working, opened, open_failure := buffer_working_revision_open_state(state)
	if !opened {
		return state.revision, false, open_failure
	}
	defer if working_revision_is_valid(&working) {
		aborted, _ := working_revision_abort(&working)
		assert(aborted)
	}
	start, start_ok, start_failure := working_revision_position(&working, 0)
	if !start_ok {
		return state.revision, false, start_failure
	}
	end, end_ok, end_failure := working_revision_position(
		&working,
		Byte_Offset(root_stats.text_bytes),
	)
	if !end_ok {
		return state.revision, false, end_failure
	}
	applied, apply_failure := working_revision_splice(
		&working,
		Working_Splice {start = start, end = end, replacement = contents},
		temporary_allocator,
	)
	if !applied {
		return state.revision, false, apply_failure
	}
	revision = working_revision_publish_reserved(
		&working,
		[]Working_Publication_Splice {{
			start = 0,
			end = Byte_Offset(root_stats.text_bytes),
			inserted_bytes = u64(len(contents)),
		}},
	)
	return revision, true, Failure_Context {
		buffer_id = state.buffer_id,
		revision = revision,
	}
}
