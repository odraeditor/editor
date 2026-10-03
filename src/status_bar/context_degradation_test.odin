// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package status_bar

import "../display"
import "core:testing"

@(private)
context_degradation_request :: proc(width: u32, complete: bool) -> Factory_Request {
	alert_diagnostic, _ := context_diagnostic_copy("Provider state requires review")
	stamp := Source_Stamp {
		presentation = 31,
		buffer_identity = 37,
		buffer_revision = 41,
		pane_identity = 43,
		pane_generation = 47,
		owner_identity = 53,
		owner_generation = 59,
	}
	contextual := Context_Observation {
		generation = 31,
		buffer_identity = 37,
		buffer_revision = 41,
		pane_identity = 43,
		pane_generation = 47,
		alert = {present = true, stamp = stamp, severity = .Error, diagnostic = alert_diagnostic},
	}
	if complete {
		encoding, _ := context_label_copy("UTF-8 LF")
		language_name, _ := context_label_copy("Odin")
		project_name, _ := context_label_copy("odra")
		workspace_name, _ := context_label_copy("editors")
		contextual.document = {present = true, stamp = stamp, encoding = encoding}
		contextual.diagnostics = {present = true, stamp = stamp, errors = 2, warnings = 7}
		contextual.language = {present = true, stamp = stamp, name = language_name, service_health = .Failed}
		contextual.project = {present = true, stamp = stamp, name = project_name}
		contextual.workspace = {present = true, stamp = stamp, name = workspace_name}
		contextual.pane = {present = true, stamp = stamp, policy = .Soft_Dedicated}
	}
	return Factory_Request {
		generation = 31,
		width_cells = width,
		buffer = {
			generation = 31,
			identity = 37,
			revision = 41,
			label = "main.odin",
			writable = true,
			modified = true,
			point_offset = 23,
			text_bytes = 100,
			line = 4,
			line_count = 12,
			column = 7,
		},
		contextual = contextual,
		profile = display.unicode17_profile(),
		allocator = context.allocator,
		limits = DEFAULT_LIMITS,
	}
}

@(private)
context_degradation_has_kind :: proc(view: View, kind: Segment_Kind) -> bool {
	for segment in view.segments do if segment.kind == kind do return true
	return false
}

@(private)
context_degradation_groups_have_single_separators :: proc(view: View) -> bool {
	for group in Group.Left ..= Group.Right {
		previous_end: u32
		seen := false
		for segment in view.segments {
			if segment.group != group do continue
			if seen && segment.start_cell != previous_end + 1 do return false
			previous_end = segment.end_cell
			seen = true
		}
	}
	return true
}

/* Verifies ordinary contextual composition preserves semantic order, exact width, and one-cell separators. */
@(test)
status_degradation_preserves_geometry :: proc(t: ^testing.T) {
	view, ok, failure := compose_factory(context_degradation_request(104, true))
	testing.expectf(t, ok, "ordinary contextual composition failed with %v", failure.code)
	if !ok do return
	defer view_close(&view)
	testing.expect_value(t, view.accounting.text_cells, u32(104))
	testing.expect_value(t, len(view.segments), 11)
	testing.expect(t, context_degradation_groups_have_single_separators(view))
	kinds := [?]Segment_Kind {
		.Alert, .Encoding, .Buffer_State, .Pane_State, .Buffer_Identity,
		.Position, .Workspace, .Project, .Editing_Context,
	}
	for kind in kinds {
		testing.expectf(t, context_degradation_has_kind(view, kind), "missing %v", kind)
	}
}

/* Verifies narrow composition removes optional context before required safety, identity, position, and alert. */
@(test)
status_degradation_preserves_required_segments :: proc(t: ^testing.T) {
	view, ok, failure := compose_factory(context_degradation_request(24, true))
	testing.expectf(t, ok, "narrow contextual composition failed with %v", failure.code)
	if !ok do return
	defer view_close(&view)
	testing.expect_value(t, view.accounting.text_cells, u32(24))
	kinds := [?]Segment_Kind {.Alert, .Buffer_State, .Buffer_Identity, .Position}
	for kind in kinds {
		testing.expectf(t, context_degradation_has_kind(view, kind), "lost required %v", kind)
	}
	testing.expect(t, context_degradation_groups_have_single_separators(view))
}

/* Verifies the admitted minimum width uses compact alert and position forms plus grapheme-safe identity truncation. */
@(test)
contextual_status_degradation_fits_minimum_width :: proc(t: ^testing.T) {
	view, ok, failure := compose_factory(context_degradation_request(MIN_REQUIRED_CELLS, false))
	testing.expectf(t, ok, "minimum contextual composition failed with %v", failure.code)
	if !ok do return
	defer view_close(&view)
	testing.expect_value(t, view.accounting.text_cells, MIN_REQUIRED_CELLS)
	testing.expect_value(t, string(view.text), "! ** … 4:7")
	testing.expect(t, context_degradation_groups_have_single_separators(view))
}
