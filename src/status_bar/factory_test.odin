// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package status_bar

import "../display"
import "core:testing"

@(private = "file")
factory_test_request :: proc(width: u32) -> Factory_Request {
	return Factory_Request {
		generation = Generation(7),
		width_cells = width,
		buffer = Buffer_Observation {
			generation = Generation(7),
			identity = 11,
			revision = 13,
			label = "main.odin",
			writable = true,
			modified = true,
			point_offset = 23,
			text_bytes = 100,
			line = 4,
			line_count = 12,
			column = 7,
		},
		profile = display.unicode17_profile(),
		allocator = context.allocator,
		limits = DEFAULT_LIMITS,
	}
}

@(test)
/* Verifies the factory presents buffer safety, identity, and pane position. */
status_factory_composes_required_segments :: proc(t: ^testing.T) {
	view, ok, failure := compose_factory(factory_test_request(32))
	testing.expect(t, ok)
	testing.expect_value(t, failure.code, Failure_Code.None)
	defer view_close(&view)
	testing.expect_value(t, string(view.text), "** 100 main.odin 4:7 23%        ")
	testing.expect_value(t, len(view.segments), 5)
	testing.expect_value(t, view.segments[0].style_role, Semantic_Role.Safety)
	testing.expect_value(t, view.segments[1].style_role, Semantic_Role.Ordinary)
	testing.expect_value(t, view.segments[2].style_role, Semantic_Role.Buffer_Identity)
	testing.expect_value(t, view.segments[3].style_role, Semantic_Role.Position)
	testing.expect_value(t, view.segments[4].style_role, Semantic_Role.Position)
}

@(test)
/* Verifies configured position variants replace the factory percentage presentation. */
status_factory_applies_position_policy :: proc(t: ^testing.T) {
	request := factory_test_request(32)
	request.policy = DEFAULT_FACTORY_POLICY
	request.policy.position = .Line_Column
	line_view, line_ok, _ := compose_factory(request)
	testing.expect(t, line_ok)
	if line_ok {
		testing.expect_value(t, string(line_view.text), "** 100 main.odin 4:7            ")
		view_close(&line_view)
	}
	request.policy.position = .Byte_Offset
	byte_view, byte_ok, _ := compose_factory(request)
	testing.expect(t, byte_ok)
	if byte_ok {
		testing.expect_value(t, string(byte_view.text), "** 100 main.odin B:23           ")
		view_close(&byte_view)
	}
}

@(test)
/* Verifies the factory exposes read-only and clean state independently. */
status_factory_composes_read_only_state :: proc(t: ^testing.T) {
	request := factory_test_request(24)
	request.buffer.writable = false
	request.buffer.modified = false
	view, ok, _ := compose_factory(request)
	testing.expect(t, ok)
	defer view_close(&view)
	testing.expect(t, string(view.text[:2]) == "%%")
}

@(test)
/* Verifies clean writable buffers omit the redundant safety marker. */
status_factory_omits_clean_writable_state :: proc(t: ^testing.T) {
	request := factory_test_request(24)
	request.buffer.modified = false
	view, ok, _ := compose_factory(request)
	testing.expect(t, ok)
	defer view_close(&view)
	testing.expect_value(t, len(view.segments), 4)
	testing.expect_value(t, view.segments[0].style_role, Semantic_Role.Ordinary)
	testing.expect_value(t, view.segments[1].style_role, Semantic_Role.Buffer_Identity)
	testing.expect_value(t, string(view.text), "100 main.odin 4:7 23%   ")
}

@(test)
/* Verifies file context, name, position, and progress remain separate themed segments. */
status_separates_context_and_identity :: proc(t: ^testing.T) {
	request := factory_test_request(48)
	request.buffer.modified = false
	request.buffer.context_label = "src/odra"
	view, ok, failure := compose_factory(request)
	testing.expectf(t, ok, "contextual buffer identity failed with %v", failure.code)
	if !ok do return
	defer view_close(&view)
	testing.expect_value(t, string(view.text[:31]), "100 src/odra/ main.odin 4:7 23%")
	testing.expect_value(t, view.segments[0].id, BUFFER_SIZE_SEGMENT_ID)
	testing.expect_value(t, view.segments[1].id, BUFFER_CONTEXT_SEGMENT_ID)
	testing.expect_value(t, view.segments[1].style_role, Semantic_Role.Context)
	testing.expect_value(t, view.segments[2].id, BUFFER_IDENTITY_SEGMENT_ID)
	testing.expect_value(t, view.segments[2].style_role, Semantic_Role.Buffer_Identity)
	testing.expect_value(t, view.segments[3].id, POSITION_SEGMENT_ID)
	testing.expect_value(t, view.segments[4].id, PROGRESS_SEGMENT_ID)
}

@(test)
/* Verifies narrow factory views retain compact required information. */
status_factory_degrades_without_losing_identity :: proc(t: ^testing.T) {
	view, ok, _ := compose_factory(factory_test_request(16))
	testing.expect(t, ok)
	defer view_close(&view)
	testing.expect_value(t, string(view.text), "** main.odin 4:7")
	testing.expect(t, view.segments[2].compact)
}

@(test)
/* Verifies the factory names the first and final positions without punctuation noise. */
status_factory_names_buffer_edges :: proc(t: ^testing.T) {
	request := factory_test_request(24)
	request.buffer.modified = false
	request.buffer.point_offset = 0
	request.buffer.line = 1
	request.buffer.column = 1
	view, top_ok, _ := compose_factory(request)
	testing.expect(t, top_ok)
	if top_ok {
		testing.expect_value(t, string(view.text), "100 main.odin 1:1 Top   ")
		view_close(&view)
	}
	request.buffer.point_offset = request.buffer.text_bytes
	request.buffer.line = request.buffer.line_count
	request.buffer.column = 9
	bottom_view, bottom_ok, _ := compose_factory(request)
	testing.expect(t, bottom_ok)
	if bottom_ok {
		testing.expect_value(t, string(bottom_view.text), "100 main.odin 12:9 Bot  ")
		view_close(&bottom_view)
	}
}

@(test)
/* Verifies factory observations must belong to the requested generation. */
status_factory_rejects_mixed_generation :: proc(t: ^testing.T) {
	request := factory_test_request(32)
	request.buffer.generation = Generation(8)
	_, ok, failure := compose_factory(request)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.operation, Operation.Factory)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Request)
}

@(test)
/* Verifies available copied context appears in canonical group order while absent owners consume no cells. */
status_factory_composes_available_context :: proc(t: ^testing.T) {
	request := factory_test_request(96)
	encoding, _ := context_label_copy("UTF-8 LF")
	language_name, _ := context_label_copy("Odin")
	project_name, _ := context_label_copy("odra")
	workspace_name, _ := context_label_copy("editor")
	stamp := Source_Stamp {
		presentation = 7,
		buffer_identity = 11,
		buffer_revision = 13,
		pane_identity = 17,
		pane_generation = 19,
		owner_identity = 23,
		owner_generation = 29,
	}
	request.contextual = Context_Observation {
		generation = 7,
		buffer_identity = 11,
		buffer_revision = 13,
		pane_identity = 17,
		pane_generation = 19,
		document = {present = true, stamp = stamp, encoding = encoding},
		diagnostics = {present = true, stamp = stamp, errors = 1, warnings = 2},
		language = {present = true, stamp = stamp, name = language_name, service_health = .Active},
		project = {present = true, stamp = stamp, name = project_name},
		workspace = {present = true, stamp = stamp, name = workspace_name},
		pane = {present = true, stamp = stamp, policy = .Hard_Dedicated},
	}
	request.actions = Factory_Actions {
		buffer_identity = {registry_generation = 31, slot = 1, entry_generation = 1},
		project = {registry_generation = 31, slot = 2, entry_generation = 1},
		project_inspection = {registry_generation = 31, slot = 3, entry_generation = 1},
		editing_context = {registry_generation = 31, slot = 4, entry_generation = 1},
		editing_context_secondary = {registry_generation = 31, slot = 5, entry_generation = 1},
	}
	view, ok, failure := compose_factory(request)
	testing.expectf(t, ok, "context factory failed with %v", failure.code)
	if !ok do return
	defer view_close(&view)
	testing.expect_value(t, len(view.segments), 10)
	testing.expect_value(t, view.segments[0].kind, Segment_Kind.Buffer_State)
	testing.expect_value(t, view.segments[1].kind, Segment_Kind.Buffer_State)
	testing.expect_value(t, view.segments[2].kind, Segment_Kind.Pane_State)
	testing.expect_value(t, view.segments[3].kind, Segment_Kind.Buffer_Identity)
	testing.expect_value(t, view.segments[4].kind, Segment_Kind.Position)
	testing.expect_value(t, view.segments[5].kind, Segment_Kind.Position)
	testing.expect_value(t, view.segments[6].kind, Segment_Kind.Workspace)
	testing.expect_value(t, view.segments[7].kind, Segment_Kind.Project)
	testing.expect_value(t, view.segments[8].kind, Segment_Kind.Encoding)
	testing.expect_value(t, view.segments[9].kind, Segment_Kind.Editing_Context)
	testing.expect_value(t, view.segments[3].primary_command, request.actions.buffer_identity)
	testing.expect_value(t, view.segments[6].primary_command.registry_generation, u64(0))
	testing.expect_value(t, view.segments[7].primary_command, request.actions.project)
	testing.expect_value(t, view.segments[7].secondary_command, request.actions.project_inspection)
	testing.expect_value(t, view.segments[9].primary_command, request.actions.editing_context)
	testing.expect_value(
		t,
		view.segments[9].secondary_command,
		request.actions.editing_context_secondary,
	)
}

@(test)
/* Verifies modal state survives compact degradation as required editing context. */
status_factory_keeps_modal_state_visible :: proc(t: ^testing.T) {
	request := factory_test_request(80)
	profile_name, _ := context_label_copy("modal")
	state_name, _ := context_label_copy("Normal")
	stamp := Source_Stamp {
		presentation = 7,
		buffer_identity = 11,
		buffer_revision = 13,
		pane_identity = 17,
		pane_generation = 19,
		owner_identity = 2,
		owner_generation = 1,
	}
	request.contextual = Context_Observation {
		generation = 7,
		buffer_identity = 11,
		buffer_revision = 13,
		pane_identity = 17,
		pane_generation = 19,
		interaction = {
			present = true,
			stamp = stamp,
			profile = profile_name,
			state = state_name,
			modal = true,
		},
	}
	request.policy = DEFAULT_FACTORY_POLICY
	request.policy.visible -= {.Editing_Context}
	request.policy.compact = .Essential_Only
	full_view, full_ok, full_failure := compose_factory(request)
	testing.expectf(t, full_ok, "full modal status failed with %v", full_failure.code)
	if full_ok {
		full_found := false
		for segment in full_view.segments do if segment.id == EDITING_CONTEXT_SEGMENT_ID {
			full_found = true
			testing.expect(t, !segment.compact)
			testing.expect_value(t, string(full_view.text[segment.start_byte:segment.end_byte]), "NORMAL")
		}
		testing.expect(t, full_found)
		view_close(&full_view)
	}
	request.width_cells = 20
	view, ok, failure := compose_factory(request)
	testing.expectf(t, ok, "modal status failed with %v", failure.code)
	if !ok do return
	defer view_close(&view)
	found := false
	for segment in view.segments do if segment.id == EDITING_CONTEXT_SEGMENT_ID {
		found = true
		testing.expect(t, segment.compact)
		testing.expect_value(t, string(view.text[segment.start_byte:segment.end_byte]), "N")
	}
	testing.expect(t, found)
}

@(test)
/* Verifies non-Normal modal states retain explicit status labels. */
status_factory_names_modal_states :: proc(t: ^testing.T) {
	cases := [?]struct {state, full, compact: string} {
		{"Insert", "INSERT", "I"},
		{"Visual Character", "VISUAL", "V"},
		{"Visual Line", "VISUAL LINE", "V"},
		{"Visual Block", "VISUAL BLOCK", "V"},
		{"Replace", "REPLACE", "R"},
	}
	for test_case in cases {
		request := factory_test_request(80)
		profile_name, _ := context_label_copy("modal")
		state_name, _ := context_label_copy(test_case.state)
		stamp := Source_Stamp {
			presentation = 7,
			buffer_identity = 11,
			buffer_revision = 13,
			pane_identity = 17,
			pane_generation = 19,
			owner_identity = 2,
			owner_generation = 1,
		}
		request.contextual = {
			generation = 7,
			buffer_identity = 11,
			buffer_revision = 13,
			pane_identity = 17,
			pane_generation = 19,
			interaction = {
				present = true,
				stamp = stamp,
				profile = profile_name,
				state = state_name,
				modal = true,
			},
		}
		view, ok, failure := compose_factory(request)
		testing.expectf(t, ok, "%s status failed with %v", test_case.state, failure.code)
		if !ok do continue
		found := false
		for segment in view.segments do if segment.id == EDITING_CONTEXT_SEGMENT_ID {
			found = true
			testing.expect_value(
				t,
				string(view.text[segment.start_byte:segment.end_byte]),
				test_case.full,
			)
		}
		testing.expect(t, found)
		view_close(&view)

		request.width_cells = 20
		compact_view, compact_ok, compact_failure := compose_factory(request)
		testing.expectf(t, compact_ok, "%s compact status failed with %v", test_case.state, compact_failure.code)
		if !compact_ok do continue
		found = false
		for segment in compact_view.segments do if segment.id == EDITING_CONTEXT_SEGMENT_ID {
			found = true
			testing.expect(t, segment.compact)
			testing.expect_value(
				t,
				string(compact_view.text[segment.start_byte:segment.end_byte]),
				test_case.compact,
			)
		}
		testing.expect(t, found)
		view_close(&compact_view)
	}
}

@(test)
/* Verifies configured visibility and compact policy select only admitted optional context. */
status_factory_applies_optional_segment_policy :: proc(t: ^testing.T) {
	request := factory_test_request(64)
	project_name, _ := context_label_copy("odra")
	workspace_name, _ := context_label_copy("editor")
	stamp := Source_Stamp {
		presentation = 7,
		buffer_identity = 11,
		buffer_revision = 13,
		pane_identity = 17,
		pane_generation = 19,
		owner_identity = 23,
		owner_generation = 29,
	}
	request.contextual = Context_Observation {
		generation = 7,
		buffer_identity = 11,
		buffer_revision = 13,
		pane_identity = 17,
		pane_generation = 19,
		project = {present = true, stamp = stamp, name = project_name},
		workspace = {present = true, stamp = stamp, name = workspace_name},
	}
	request.policy = DEFAULT_FACTORY_POLICY
	request.policy.visible = {.Project}
	request.policy.compact = .Prefer_Compact
	view, ok, failure := compose_factory(request)
	testing.expectf(t, ok, "configured factory failed with %v", failure.code)
	if !ok do return
	defer view_close(&view)
	testing.expect_value(t, len(view.segments), 6)
	testing.expect_value(t, view.segments[5].kind, Segment_Kind.Project)
	testing.expect_value(t, string(view.segments[5].inspection_text), "odra")
	testing.expect_value(t, string(view.text[len(view.text) - 1:]), "P")
}

@(test)
/* Verifies essential-only policy excludes every optional contextual segment. */
status_factory_applies_essential_only_policy :: proc(t: ^testing.T) {
	request := factory_test_request(48)
	project_name, _ := context_label_copy("odra")
	stamp := Source_Stamp {
		presentation = 7,
		buffer_identity = 11,
		buffer_revision = 13,
		pane_identity = 17,
		pane_generation = 19,
		owner_identity = 23,
		owner_generation = 29,
	}
	request.contextual = Context_Observation {
		generation = 7,
		buffer_identity = 11,
		buffer_revision = 13,
		pane_identity = 17,
		pane_generation = 19,
		project = {present = true, stamp = stamp, name = project_name},
	}
	request.policy = DEFAULT_FACTORY_POLICY
	request.policy.compact = .Essential_Only
	view, ok, failure := compose_factory(request)
	testing.expectf(t, ok, "essential-only factory failed with %v", failure.code)
	if !ok do return
	defer view_close(&view)
	testing.expect_value(t, len(view.segments), 3)
}

@(test)
/* Verifies contextual facts cannot be published for another buffer identity or revision. */
status_factory_rejects_cross_buffer_context :: proc(t: ^testing.T) {
	request := factory_test_request(48)
	language_name, _ := context_label_copy("Odin")
	stamp := Source_Stamp {
		presentation = 7,
		buffer_identity = 11,
		buffer_revision = 13,
		pane_identity = 17,
		pane_generation = 19,
		owner_identity = 23,
		owner_generation = 29,
	}
	request.contextual = {
		generation = 7,
		buffer_identity = 11,
		buffer_revision = 13,
		pane_identity = 17,
		pane_generation = 19,
		language = {present = true, stamp = stamp, name = language_name},
	}
	request.buffer.identity = 12
	_, identity_ok, identity_failure := compose_factory(request)
	testing.expect(t, !identity_ok)
	testing.expect_value(t, identity_failure.code, Failure_Code.Invalid_Request)
	request.buffer.identity = 11
	request.buffer.revision = 14
	_, revision_ok, revision_failure := compose_factory(request)
	testing.expect(t, !revision_ok)
	testing.expect_value(t, revision_failure.code, Failure_Code.Invalid_Request)
}

@(test)
/* Verifies the ordinary document and language context emitted by application orchestration. */
status_composes_document_language_context :: proc(t: ^testing.T) {
	request := factory_test_request(80)
	request.buffer.modified = false
	encoding, _ := context_label_copy("UTF-8 LF")
	language_name, _ := context_label_copy("odin")
	stamp := Source_Stamp {
		presentation = 7,
		buffer_identity = 11,
		buffer_revision = 13,
		pane_identity = 17,
		pane_generation = 19,
		owner_identity = 23,
		owner_generation = 29,
	}
	request.contextual = {
		generation = 7,
		buffer_identity = 11,
		buffer_revision = 13,
		pane_identity = 17,
		pane_generation = 19,
		document = {present = true, stamp = stamp, encoding = encoding},
		language = {present = true, stamp = stamp, name = language_name, service_health = .Active},
	}
	view, ok, failure := compose_factory(request)
	testing.expectf(t, ok, "document-language factory failed with %v segment %d", failure.code, failure.segment)
	if !ok do return
	defer view_close(&view)
	testing.expect_value(t, string(view.text), "100 main.odin 4:7 23%                                           UTF-8 LF odin LS")
}

@(test)
/* Verifies language interaction health stays compact and separate from service health. */
status_composes_language_operation_health :: proc(t: ^testing.T) {
	request := factory_test_request(80)
	request.buffer.modified = false
	language_name, _ := context_label_copy("odin")
	stamp := Source_Stamp {
		presentation = 7,
		buffer_identity = 11,
		buffer_revision = 13,
		pane_identity = 17,
		pane_generation = 19,
		owner_identity = 23,
		owner_generation = 29,
	}
	request.contextual = {
		generation = 7,
		buffer_identity = 11,
		buffer_revision = 13,
		pane_identity = 17,
		pane_generation = 19,
		language = {
			present = true,
			stamp = stamp,
			name = language_name,
			service_health = .Active,
			operation_health = .Busy,
		},
	}
	busy, busy_ok, busy_failure := compose_factory(request)
	testing.expectf(t, busy_ok, "busy language operation failed with %v", busy_failure.code)
	if busy_ok {
		long_enough := len(busy.text) >= len("odin LS L:busy")
		testing.expect(t, long_enough)
		if long_enough {
			testing.expect_value(t, string(busy.text[len(busy.text) - len("odin LS L:busy"):]), "odin LS L:busy")
		}
		view_close(&busy)
	}
	request.contextual.language.operation_health = .Failed
	failed, failed_ok, failed_failure := compose_factory(request)
	testing.expectf(t, failed_ok, "failed language operation failed with %v", failed_failure.code)
	if failed_ok {
		long_enough := len(failed.text) >= len("odin LS L:failed")
		testing.expect(t, long_enough)
		if long_enough {
			testing.expect_value(t, string(failed.text[len(failed.text) - len("odin LS L:failed"):]), "odin LS L:failed")
		}
		view_close(&failed)
	}
}

@(test)
/* Verifies future provider facts use ordinary segment contracts without creating provider owners. */
status_contract_accepts_future_owner_fixtures :: proc(t: ^testing.T) {
	segments := [7]Segment_Definition {
		{id = 1, kind = .Remote, group = .Left, priority = 80, full_text = "@", omittable = true, style_role = .Context},
		{id = 2, kind = .Client, group = .Left, priority = 20, full_text = "phone", omittable = true, style_role = .Context},
		{id = 3, kind = .Frontend, group = .Left, priority = 20, full_text = "terminal", omittable = true, style_role = .Context},
		{id = 4, kind = .Buffer_Identity, group = .Left, priority = 254, full_text = "main.odin", required = true, truncatable = true, style_role = .Buffer_Identity},
		{id = 5, kind = .Position, group = .Right, priority = 253, full_text = "1:1", required = true, style_role = .Position},
		{id = 6, kind = .Version_Control, group = .Right, priority = 40, full_text = "VC:main", omittable = true, style_role = .Context},
		{id = 7, kind = .Editing_Context, group = .Right, priority = 50, full_text = "(Odin)", omittable = true, style_role = .Editing_Context},
	}
	view, ok, failure := compose(Composition_Request {
		generation = 1,
		width_cells = 72,
		segments = segments[:],
		profile = display.unicode17_profile(),
		allocator = context.allocator,
		limits = DEFAULT_LIMITS,
	})
	testing.expectf(t, ok, "future-owner fixture failed with %v", failure.code)
	if ok do view_close(&view)
}
