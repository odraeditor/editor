// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package syntax_workflow

import "../editor_session"

@(private)
syntax_workflow_test_session_close :: proc(
	session: ^editor_session.Session,
	handle: editor_session.Session_Handle,
) -> bool {
	for _ in 0 ..< int(editor_session.MAX_LIVE_BUFFERS) {
		descriptors, copied, _ := editor_session.session_descriptors(session, handle)
		if !copied do return false
		if len(descriptors.descriptors) == 0 {
			editor_session.descriptor_batch_close(&descriptors)
			closed, _ := editor_session.session_close(session)
			return closed
		}
		entry := descriptors.descriptors[0].graph.entry
		editor_session.descriptor_batch_close(&descriptors)
		detached: editor_session.Detached_Entry
		_, detached_ok, _ := editor_session.session_entry_detach(session, entry, &detached)
		if !detached_ok do return false
		_, cleaned, _ := editor_session.detached_entry_cleanup(&detached)
		if !cleaned do return false
		released, _ := editor_session.detached_entry_release(&detached)
		if !released do return false
	}
	return false
}
