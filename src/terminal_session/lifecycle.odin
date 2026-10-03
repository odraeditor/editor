// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "../interactive_session"
import "../terminal_emulator"

/* registry_request_terminate begins bounded process cancellation for one live terminal. */
registry_request_terminate :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	now_ns: i64,
) -> (bool, Failure_Record) {
	state := registry_state(registry)
	if state == nil {
		return false, registry_access_failure(registry, .Process)
	}
	session, resolved := registry_resolve(state, ref)
	if !resolved {
		return false, failure_record(.Process, .Stale_Reference)
	}
	requested, process_failure_record := interactive_session.registry_request_cancel(
		&state.interactive,
		session.record.process.ref,
		now_ns,
	)
	if !requested {
		return false, process_failure(.Process, process_failure_record)
	}
	return true, {}
}

/* registry_clear_scrollback applies the terminal protocol's retained-history clear. */
registry_clear_scrollback :: proc(
	registry: ^Registry,
	ref: Session_Ref,
) -> (bool, Failure_Record) {
	state := registry_state(registry)
	if state == nil {
		return false, registry_access_failure(registry, .Scrollback)
	}
	session, resolved := registry_resolve(state, ref)
	if !resolved {
		return false, failure_record(.Scrollback, .Stale_Reference)
	}
	result := terminal_emulator.write(
		session.record.emulator,
		transmute([]u8)(string("\x1b[3J")),
	)
	if result != .OK {
		return false, emulator_failure(.Scrollback, result)
	}
	return true, {}
}
