// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import "../ksawery"
import "../ui"
import "core:fmt"

/* ksawery_process_compact_feedback projects one active-first immutable record without owning it. */
ksawery_process_compact_feedback :: proc(
	records: []ksawery.Process_Record,
	storage: []u8,
) -> (content: string, role: ui.Style_Role, active: bool, present: bool) {
	if len(storage) == 0 do return "", .Invalid, false, false
	surface, described := ksawery.process_surface_descriptor(records)
	if !described || surface.state == .Empty do return "", .Invalid, false, false
	row, projected, _ := ksawery.process_surface_row(records, 0)
	if !projected do return "", .Invalid, false, false
	title, title_ok, _ := ksawery.process_surface_text(records, row.id, .Title)
	if !title_ok do return "", .Invalid, false, false
	selection := ksawery.Process_Selection{current = row.id}
	inspect_hint := ""
	if action, available, _ := ksawery.process_selection_action(records, selection, .Inspect);
	   available {
		if current, _ := ksawery.process_surface_action_is_current(records, action); current {
			inspect_hint = " | $ inspect"
		}
	}
	cancel_hint := ""
	if action, available, _ := ksawery.process_selection_action(records, selection, .Cancel);
	   available {
		if current, _ := ksawery.process_surface_action_is_current(records, action); current {
			cancel_hint = " | C-g cancel"
		}
	}
	if row.active {
		phase, phase_ok, _ := ksawery.process_surface_text(records, row.id, .Phase_Detail)
		phase_text := fmt.tprintf("%v", row.phase)
		if phase_ok && len(phase) > 0 do phase_text = string(phase)
		progress := ""
		if row.progress.kind == .Determinate {
			progress = fmt.tprintf(" %d/%d", row.progress.current, row.progress.total)
		}
		message := fmt.bprintf(
			storage,
			"Repository %s: %s%s%s%s",
			string(title),
			phase_text,
			progress,
			inspect_hint,
			cancel_hint,
		)
		return message, .Status_Active, true, true
	}
	message_text, message_ok, _ := ksawery.process_surface_text(records, row.id, .Message)
	outcome := fmt.tprintf("%v", row.outcome)
	if message_ok && len(message_text) > 0 do outcome = string(message_text)
	style := ui.Style_Role.Status_Normal
	attention := false
	if row.lifecycle == .Failed || row.lifecycle == .Timed_Out || row.lifecycle == .Indeterminate {
		style = .Diagnostic_Rejected
		attention = true
	} else if row.lifecycle == .Cancelled {
		style = .Diagnostic_Normal
	}
	message := fmt.bprintf(
		storage,
		"Repository %s: %s%s",
		string(title),
		outcome,
		inspect_hint,
	)
	return message, style, attention, true
}
