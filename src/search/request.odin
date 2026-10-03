// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package search

import "../editor"

/* request_validate binds one query and request to an exact live snapshot identity and range. */
request_validate :: proc(
	query: ^Query,
	request: Request,
	snapshot: editor.Buffer_Snapshot_Stats,
) -> (ok: bool, failure: Failure) {
	view, query_ok, query_failure := query_view(query)
	if !query_ok {
		return false, query_failure
	}
	if request.generation == Search_Generation(0) {
		return false, Failure{code = .Invalid_Generation, query_id = view.id}
	}
	if request.direction != .Forward && request.direction != .Backward {
		return false, Failure{code = .Invalid_Direction, query_id = view.id}
	}
	if request.scope.buffer_id != snapshot.buffer_id {
		return false, Failure {
			code = .Wrong_Buffer,
			buffer_id = request.scope.buffer_id,
			revision = request.scope.revision,
			query_id = view.id,
		}
	}
	if request.scope.revision != snapshot.revision {
		return false, Failure {
			code = .Stale_Revision,
			buffer_id = request.scope.buffer_id,
			revision = request.scope.revision,
			query_id = view.id,
			actual = u64(snapshot.revision),
		}
	}
	start := u64(request.scope.start)
	end := u64(request.scope.end)
	origin := u64(request.origin)
	if start > end {
		return false, Failure {
			code = .Invalid_Scope,
			buffer_id = request.scope.buffer_id,
			revision = request.scope.revision,
			query_id = view.id,
			limit = end,
			actual = start,
		}
	}
	if end > snapshot.text_bytes || origin < start || origin > end {
		return false, Failure {
			code = .Out_Of_Range,
			buffer_id = request.scope.buffer_id,
			revision = request.scope.revision,
			query_id = view.id,
			limit = snapshot.text_bytes,
			actual = max(end, origin),
		}
	}
	return true, {}
}

/* cancellation_reset starts a new uncancelled logical search generation. */
cancellation_reset :: proc(
	cancellation: ^Cancellation,
	generation: Search_Generation,
) -> (ok: bool, failure: Failure) {
	assert(cancellation != nil)
	if generation == Search_Generation(0) {
		return false, Failure{code = .Invalid_Generation}
	}
	cancellation.generation = generation
	cancellation.requested = false
	return true, {}
}

/* cancellation_request requests cancellation only for the matching live generation. */
cancellation_request :: proc(
	cancellation: ^Cancellation,
	generation: Search_Generation,
) -> bool {
	if cancellation == nil || generation == Search_Generation(0) ||
	   cancellation.generation != generation {
		return false
	}
	cancellation.requested = true
	return true
}

/* cancellation_requested reports cancellation without accepting stale generations. */
cancellation_requested :: proc(
	cancellation: ^Cancellation,
	generation: Search_Generation,
) -> bool {
	return cancellation != nil && generation != Search_Generation(0) &&
		cancellation.generation == generation && cancellation.requested
}
