// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor_session

import "../result_set"
import "../editor"
import "core:testing"

@(test)
/* Verifies one active result source owns unified location movement until cleared. */
active_result_source_owns_unified_movement :: proc(t: ^testing.T) {
	session: Session
	handle, initialized, _ := session_init(&session, 909, test_session_allocators())
	testing.expect(t, initialized)
	if !initialized do return
	defer session_close(&session)
	registry, registry_ok, _ := session_result_registry(&session, handle)
	testing.expect(t, registry_ok)
	locations := []result_set.Location_Definition {
		{id = 1, buffer_id = 1, revision = 1, start = 2, end = 3},
		{id = 2, buffer_id = 1, revision = 1, start = 5, end = 6},
	}
	_, published, _ := result_set.registry_publish(registry, result_set.Publication {
		set_id = 9, source = {id = 4, generation = 1, kind = .Test},
		completeness = .Complete, edit_capability = .Read_Only, locations = locations,
	})
	testing.expect(t, published)
	_, activated, _ := session_result_source_activate(&session, handle, 9)
	testing.expect(t, activated)
	result, location, moved, _ := session_result_source_move(&session, handle, .Next)
	testing.expect(t, moved)
	testing.expect_value(t, result.location_id, result_set.Location_ID(1))
	testing.expect_value(t, location.start, editor.Byte_Offset(2))
	cleared, _ := session_result_source_clear(&session, handle, 9, 1)
	testing.expect(t, cleared)
	_, active, _ := session_active_location_source(&session, handle)
	testing.expect(t, !active)
	result_set.registry_close_set(registry, 9, 1)
}
